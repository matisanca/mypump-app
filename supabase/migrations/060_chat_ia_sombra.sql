-- =============================================================
-- 060_chat_ia_sombra.sql — la IA escribe, pero NO publica
--
-- MODO SOMBRA, Y POR QUÉ ES EL PRIMER PASO Y NO UNA PRUEBA OPCIONAL
-- La IA va a hablar como Mati, sin aclararlo, a clientes que le pagan. Antes de
-- que eso pase hay que saber DOS cosas que no se pueden estimar leyendo código:
-- qué proporción de mensajes clasifica bien, y si el tono se le parece.
--
-- Durante esta etapa el worker genera la respuesta, la valida, y la deja como
-- BORRADOR en la bandeja del Cerebro. Mati la manda con un click, la edita, o
-- la descarta. Calibra el tono con un click en vez de escribir de cero, y de
-- paso queda medida la tasa de acierto.
--
-- El día que se prenda el automático, la única línea que cambia es el estado
-- inicial del borrador. Toda la maquinaria ya está probada con tráfico real.
--
-- LO QUE ESTA MIGRACIÓN NO HACE
-- No publica nada. No hay un solo camino acá que escriba en mypump_comentarios.
-- Eso es a propósito: mientras no exista ese camino, un bug del worker no puede
-- terminar en un mensaje a un cliente.
--
-- IDEMPOTENTE.
-- =============================================================

BEGIN;

-- ── 1. Los borradores ────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS mypump_chat_borradores (
  id            bigserial PRIMARY KEY,
  cliente_id    text        NOT NULL,
  -- El mensaje del cliente al que responde. UNIQUE: la misma garantía que el
  -- índice parcial de la 057, pero para los borradores — si el worker muere
  -- entre generar y reportar, al reiniciar no genera un segundo borrador para
  -- el mismo mensaje.
  respuesta_a   uuid        NOT NULL UNIQUE,
  clase         text        NOT NULL CHECK (clase IN ('simple','derivar','urgente')),
  respuesta     text,
  motivo        text,
  -- Lo que dijo el validador determinista. Se guarda aunque haya pasado: es lo
  -- que deja calibrar el prompt mirando datos en vez de impresiones.
  bloqueos      text[],
  estado        text        NOT NULL DEFAULT 'borrador'
                CHECK (estado IN ('borrador','enviado','descartado','vencido')),
  modelo        text,
  creado_en     timestamptz NOT NULL DEFAULT now(),
  resuelto_en   timestamptz
);

CREATE INDEX IF NOT EXISTS idx_chat_borradores_pendientes
  ON mypump_chat_borradores (creado_en DESC) WHERE estado = 'borrador';

ALTER TABLE mypump_chat_borradores ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "admin all mypump_chat_borradores" ON mypump_chat_borradores;
CREATE POLICY "admin all mypump_chat_borradores" ON mypump_chat_borradores
  FOR ALL USING (auth.role() = 'authenticated')
  WITH CHECK (auth.role() = 'authenticated');

-- ── 2. Qué tiene que mirar el worker ─────────────────────────────────────
--
-- Mensajes de cliente sin respuesta posterior del coach y sin borrador. El
-- COALESCING vive acá y no en Python: se devuelve UNA fila por cliente, la del
-- último mensaje, con los anteriores pegados como contexto. Tres mensajes
-- seguidos ("hola", "che", "estás?") merecen UNA respuesta — es lo que haría
-- una persona, y además evita tres llamadas al modelo.
CREATE OR REPLACE FUNCTION mypump_chat_para_responder(p_limite integer DEFAULT 10)
RETURNS TABLE (
  cliente_id   text,
  nombre       text,
  mensaje_id   uuid,
  mensaje      text,
  mensaje_at   timestamptz,
  contexto     jsonb,
  ya_subio     boolean
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  WITH ultimo_coach AS (
    SELECT m.cliente_id, max(m.created_at) AS at
    FROM mypump_comentarios m
    WHERE m.ambito = 'general' AND m.autor = 'coach'
    GROUP BY m.cliente_id
  ),
  sin_responder AS (
    SELECT m.*
    FROM mypump_comentarios m
    LEFT JOIN ultimo_coach u ON u.cliente_id = m.cliente_id
    WHERE m.ambito = 'general' AND m.autor = 'cliente'
      AND (u.at IS NULL OR m.created_at > u.at)
      -- Un minuto de gracia: si el cliente esta escribiendo el segundo mensaje,
      -- conviene esperarlo y contestar una sola vez.
      AND m.created_at < now() - interval '1 minute'
  ),
  ultimo_por_cliente AS (
    SELECT DISTINCT ON (s.cliente_id) s.*
    FROM sin_responder s
    ORDER BY s.cliente_id, s.created_at DESC
  )
  SELECT
    u.cliente_id,
    c.nombre,
    u.id,
    u.contenido,
    u.created_at,
    -- Los últimos 10 del hilo, para que el modelo no conteste a ciegas.
    -- CERO datos de salud: solo lo que las dos partes ya se dijeron.
    (SELECT COALESCE(jsonb_agg(jsonb_build_object('autor', h.autor, 'texto', h.contenido)
                               ORDER BY h.created_at), '[]'::jsonb)
       FROM (SELECT x.autor, x.contenido, x.created_at
               FROM mypump_comentarios x
              WHERE x.cliente_id = u.cliente_id AND x.ambito = 'general'
              ORDER BY x.created_at DESC LIMIT 10) h),
    EXISTS (SELECT 1 FROM mypump_checkin_semanal k
             WHERE k.cliente_id = u.cliente_id
               AND k.semana_lunes = (date_trunc('week', now() AT TIME ZONE 'America/Argentina/Buenos_Aires'))::date)
  FROM ultimo_por_cliente u
  JOIN mypump_clientes c ON c.cliente_id = u.cliente_id
  LEFT JOIN mypump_chat_estado e ON e.cliente_id = u.cliente_id
  WHERE COALESCE(e.ia_activa, TRUE)          -- Mati tomó la conversación
    AND NOT COALESCE(e.escalado, FALSE)      -- ya está en su teléfono
    AND NOT EXISTS (SELECT 1 FROM mypump_chat_borradores b WHERE b.respuesta_a = u.id)
    AND c.cliente_id NOT LIKE 'test%'
  ORDER BY u.created_at
  LIMIT LEAST(GREATEST(COALESCE(p_limite, 10), 1), 50);
END;
$$;

REVOKE ALL ON FUNCTION mypump_chat_para_responder(integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION mypump_chat_para_responder(integer) TO authenticated, service_role;

-- ── 3. Guardar el borrador ───────────────────────────────────────────────
CREATE OR REPLACE FUNCTION mypump_chat_borrador_guardar(
  p_cliente_id  text,
  p_respuesta_a uuid,
  p_clase       text,
  p_respuesta   text DEFAULT NULL,
  p_motivo      text DEFAULT NULL,
  p_bloqueos    text[] DEFAULT NULL,
  p_modelo      text DEFAULT NULL
) RETURNS bigint
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_id bigint;
BEGIN
  INSERT INTO mypump_chat_borradores
    (cliente_id, respuesta_a, clase, respuesta, motivo, bloqueos, modelo)
  VALUES
    (p_cliente_id, p_respuesta_a, p_clase, p_respuesta, p_motivo, p_bloqueos, p_modelo)
  ON CONFLICT (respuesta_a) DO NOTHING
  RETURNING id INTO v_id;

  -- 'urgente' y 'derivar' marcan la conversación como escalada ACÁ, en la misma
  -- transacción que crea el borrador. Si el worker tuviera que hacer una
  -- segunda llamada para escalar y muriera en el medio, quedaría un caso
  -- urgente registrado y sin escalar — que es la peor combinación posible.
  IF p_clase IN ('urgente','derivar') THEN
    INSERT INTO mypump_chat_estado (cliente_id, escalado, escalado_motivo, escalado_at)
    VALUES (p_cliente_id, TRUE, COALESCE(p_motivo, p_clase), now())
    ON CONFLICT (cliente_id) DO UPDATE SET
      escalado = TRUE,
      escalado_motivo = COALESCE(EXCLUDED.escalado_motivo, mypump_chat_estado.escalado_motivo),
      escalado_at = now(),
      updated_at = now();
  END IF;

  RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION mypump_chat_borrador_guardar(text, uuid, text, text, text, text[], text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION mypump_chat_borrador_guardar(text, uuid, text, text, text, text[], text) TO service_role;

-- ── 4. Lo que ve Mati en la bandeja ──────────────────────────────────────
CREATE OR REPLACE FUNCTION mypump_chat_borradores_pendientes()
RETURNS TABLE (
  id          bigint,
  cliente_id  text,
  nombre      text,
  clase       text,
  respuesta   text,
  motivo      text,
  bloqueos    text[],
  mensaje     text,
  creado_en   timestamptz
)
LANGUAGE sql SECURITY DEFINER SET search_path = public
AS $$
  SELECT b.id, b.cliente_id, c.nombre, b.clase, b.respuesta, b.motivo, b.bloqueos,
         m.contenido, b.creado_en
  FROM mypump_chat_borradores b
  JOIN mypump_clientes c ON c.cliente_id = b.cliente_id
  LEFT JOIN mypump_comentarios m ON m.id = b.respuesta_a
  WHERE b.estado = 'borrador'
  ORDER BY (b.clase = 'urgente') DESC, b.creado_en DESC
  LIMIT 100;
$$;

REVOKE ALL ON FUNCTION mypump_chat_borradores_pendientes() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION mypump_chat_borradores_pendientes() TO authenticated, service_role;

-- ── 5. Mati resuelve el borrador ─────────────────────────────────────────
--
-- Este es el ÚNICO camino por el que una respuesta generada por IA puede llegar
-- a un cliente, y pasa por un click de Mati. Mientras dure la sombra, no hay
-- otro. `p_texto` permite editar antes de mandar: es como se calibra el tono.
CREATE OR REPLACE FUNCTION mypump_chat_borrador_resolver(
  p_id     bigint,
  p_enviar boolean,
  p_texto  text DEFAULT NULL
) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  b      record;
  v_txt  text;
  v_id   uuid;
BEGIN
  IF auth.role() NOT IN ('authenticated','service_role') THEN
    RAISE EXCEPTION 'Acceso denegado';
  END IF;

  SELECT * INTO b FROM mypump_chat_borradores WHERE id = p_id AND estado = 'borrador';
  IF NOT FOUND THEN RETURN NULL; END IF;

  IF NOT p_enviar THEN
    UPDATE mypump_chat_borradores SET estado = 'descartado', resuelto_en = now() WHERE id = p_id;
    RETURN NULL;
  END IF;

  v_txt := COALESCE(NULLIF(trim(COALESCE(p_texto, '')), ''), b.respuesta);
  IF v_txt IS NULL OR trim(v_txt) = '' THEN RETURN NULL; END IF;

  -- `origen` queda en 'ia' aunque Mati lo haya editado: lo escribió el modelo y
  -- el registro tiene que decirlo. Si se marcara 'humano' al editar, dentro de
  -- seis meses nadie podría auditar qué escribió la IA de verdad.
  INSERT INTO mypump_comentarios (
    cliente_id, ambito, referencia_id, referencia_nombre,
    autor, contenido, leido_por_cliente, leido_por_coach, origen, meta)
  VALUES (
    b.cliente_id, 'general', NULL, NULL,
    'coach', trim(v_txt), FALSE, TRUE, 'ia',
    jsonb_build_object('respuesta_a', b.respuesta_a::text, 'borrador_id', b.id,
                       'editado', (p_texto IS NOT NULL AND trim(p_texto) <> COALESCE(b.respuesta,''))))
  RETURNING id INTO v_id;

  UPDATE mypump_chat_borradores SET estado = 'enviado', resuelto_en = now() WHERE id = p_id;
  RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION mypump_chat_borrador_resolver(bigint, boolean, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION mypump_chat_borrador_resolver(bigint, boolean, text) TO authenticated, service_role;

-- ── 6. Cómo viene calibrando ─────────────────────────────────────────────
--
-- La métrica que decide si el automático se prende o si el prompt se vuelve a
-- escribir. Si Mati envía tal cual el 80%, el tono está. Si edita el 80%, no.
-- Y si la IA escala el 70%, el prompt está mal calibrado, no el diseño.
CREATE OR REPLACE FUNCTION mypump_chat_ia_calibracion(p_dias integer DEFAULT 14)
RETURNS TABLE (
  total       integer,
  simples     integer,
  derivados   integer,
  urgentes    integer,
  enviados    integer,
  editados    integer,
  descartados integer,
  bloqueados  integer
)
LANGUAGE sql SECURITY DEFINER SET search_path = public
AS $$
  SELECT
    count(*)::integer,
    count(*) FILTER (WHERE clase = 'simple')::integer,
    count(*) FILTER (WHERE clase = 'derivar')::integer,
    count(*) FILTER (WHERE clase = 'urgente')::integer,
    count(*) FILTER (WHERE estado = 'enviado')::integer,
    (SELECT count(*)::integer FROM mypump_comentarios
      WHERE origen = 'ia' AND (meta->>'editado')::boolean
        AND created_at > now() - make_interval(days => GREATEST(COALESCE(p_dias,14),1))),
    count(*) FILTER (WHERE estado = 'descartado')::integer,
    count(*) FILTER (WHERE bloqueos IS NOT NULL AND array_length(bloqueos,1) > 0)::integer
  FROM mypump_chat_borradores
  WHERE creado_en > now() - make_interval(days => GREATEST(COALESCE(p_dias,14),1));
$$;

REVOKE ALL ON FUNCTION mypump_chat_ia_calibracion(integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION mypump_chat_ia_calibracion(integer) TO authenticated, service_role;

COMMIT;
