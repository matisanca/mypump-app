-- =============================================================
-- 062_chat_ia_automatico.sql — la IA pasa de escribir a contestar
--
-- QUÉ CAMBIA
-- Hasta acá el worker dejaba un BORRADOR y Mati lo mandaba con un click (modo
-- sombra, mig 060). Ahora las respuestas `simple` que pasan el validador salen
-- solas — pero NO al instante.
--
-- POR QUÉ NO SE PUBLICA DIRECTO
-- Una respuesta que llega 900 ms después del mensaje no la escribió una
-- persona, y con eso se cae toda la premisa. La demora no es un adorno: es el
-- requisito de producto que además simplifica la ingeniería, porque tapa por
-- completo la latencia de Codex (25 s de generación adentro de 4 minutos es
-- invisible).
--
-- Y la maquinaria para demorar YA EXISTE: `mypump_chat_programados` +
-- `mypump_chat_drenar` de la 059, que se hicieron para escalonar la ronda del
-- domingo. Reusarla trae gratis la ventana horaria (08:00-22:59 ART, porque
-- contestar a las 4 AM es la delación más grande que existe) y la cancelación
-- automática si la conversación se escala mientras tanto.
--
-- LO ÚNICO QUE FALTABA
-- La agenda publicaba todo como `origen='sistema'` y sin `meta`. Para una
-- respuesta de IA eso pierde dos cosas que importan:
--   · la trazabilidad — dentro de seis meses nadie podría auditar qué escribió
--     el modelo;
--   · la garantía de no-doble-respuesta — el índice único parcial sobre
--     `meta->>'respuesta_a'` (mig 057) solo protege si el meta viaja.
--
-- IDEMPOTENTE.
-- =============================================================

BEGIN;

-- ── 1. La agenda transporta la procedencia ───────────────────────────────
ALTER TABLE mypump_chat_programados ADD COLUMN IF NOT EXISTS origen text NOT NULL DEFAULT 'sistema';
ALTER TABLE mypump_chat_programados ADD COLUMN IF NOT EXISTS meta   jsonb;

ALTER TABLE mypump_chat_programados DROP CONSTRAINT IF EXISTS mypump_chat_programados_origen_check;
ALTER TABLE mypump_chat_programados ADD CONSTRAINT mypump_chat_programados_origen_check
  CHECK (origen IN ('humano','ia','sistema'));

COMMENT ON COLUMN mypump_chat_programados.origen IS
  'sistema = plantilla de la ronda · ia = la escribió el modelo · humano = la escribió Mati';

-- ── 2. Programar, ahora con procedencia ──────────────────────────────────
CREATE OR REPLACE FUNCTION mypump_chat_programar(
  p_cliente_id text,
  p_contenido  text,
  p_cuando     timestamptz,
  p_dedupe     text  DEFAULT NULL,
  p_origen     text  DEFAULT 'sistema',
  p_meta       jsonb DEFAULT NULL
) RETURNS bigint
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_id bigint;
BEGIN
  IF p_cliente_id IS NULL OR p_contenido IS NULL OR length(trim(p_contenido)) = 0
    THEN RETURN NULL; END IF;

  -- Segundo candado, además del índice único de mypump_comentarios: si ya hay
  -- una respuesta AGENDADA para este mismo mensaje, no se agenda otra. Sin
  -- esto, dos corridas del worker que se pisen dejarían dos respuestas en la
  -- agenda, y el índice recién las frenaría al publicar — con una de las dos
  -- muriendo en silencio y sin que nadie sepa cuál.
  IF p_meta ? 'respuesta_a' AND EXISTS (
        SELECT 1 FROM mypump_chat_programados
         WHERE estado = 'pendiente'
           AND meta->>'respuesta_a' = p_meta->>'respuesta_a')
    THEN RETURN NULL; END IF;

  INSERT INTO mypump_chat_programados
    (cliente_id, contenido, programado_para, dedupe_key, origen, meta)
  VALUES
    (p_cliente_id, trim(p_contenido), COALESCE(p_cuando, now()), p_dedupe,
     COALESCE(p_origen, 'sistema'), p_meta)
  ON CONFLICT (dedupe_key) DO NOTHING
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION mypump_chat_programar(text, text, timestamptz, text, text, jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION mypump_chat_programar(text, text, timestamptz, text, text, jsonb) TO service_role;

-- La firma vieja (4 argumentos) queda viva para `recordatorios.py`, que no sabe
-- nada de origen ni de meta y no tiene por qué saberlo.
CREATE OR REPLACE FUNCTION mypump_chat_programar(
  p_cliente_id text,
  p_contenido  text,
  p_cuando     timestamptz,
  p_dedupe     text DEFAULT NULL
) RETURNS bigint
LANGUAGE sql SECURITY DEFINER SET search_path = public
AS $$
  SELECT mypump_chat_programar(p_cliente_id, p_contenido, p_cuando, p_dedupe, 'sistema', NULL::jsonb);
$$;

REVOKE ALL ON FUNCTION mypump_chat_programar(text, text, timestamptz, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION mypump_chat_programar(text, text, timestamptz, text) TO service_role;

-- ── 3. El drenador respeta la procedencia ────────────────────────────────
CREATE OR REPLACE FUNCTION mypump_chat_drenar(p_limite integer DEFAULT 20)
RETURNS TABLE (cliente_id text, publicado boolean, motivo text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  r                record;
  v_hora           integer;
  v_solo_respuestas boolean;
BEGIN
  v_hora := EXTRACT(hour FROM (now() AT TIME ZONE 'America/Argentina/Buenos_Aires'))::integer;

  -- LA VENTANA HORARIA APLICA A LO NO SOLICITADO, NO A LAS RESPUESTAS.
  --
  -- Al principio cortaba todo entre las 23:00 y las 08:00, y estaba mal. Son
  -- dos cosas distintas:
  --
  --   · Lo que sale porque nosotros lo decidimos —la ronda del domingo, los
  --     recordatorios— despierta a alguien. Ahí la ventana es sagrada: un
  --     mensaje de "Mati" a las 4 de la mañana es la delación más grande que
  --     existe, y encima es una falta de respeto.
  --
  --   · La respuesta a alguien que ACABA de escribir es otra cosa. Si el
  --     cliente mandó un mensaje a las 00:30, está despierto: lo demuestra el
  --     hecho de que escribió. Contestarle a las 00:33 es lo que haría
  --     cualquiera. Callarse hasta las 8 de la mañana es lo raro.
  --
  -- La demora máxima es de 15 minutos, así que una respuesta nunca puede
  -- alejarse de la hora en que el cliente escribió.
  v_solo_respuestas := (v_hora < 8 OR v_hora >= 23);

  FOR r IN
    SELECT * FROM mypump_chat_programados
     WHERE estado = 'pendiente' AND programado_para <= now()
       AND (NOT v_solo_respuestas OR origen IN ('ia','humano'))
     ORDER BY programado_para
     LIMIT LEAST(GREATEST(COALESCE(p_limite, 20), 1), 200)
    FOR UPDATE SKIP LOCKED
  LOOP
    -- Última chance de no molestar: si entre que se programó y ahora el cliente
    -- fue escalado o Mati tomó la conversación, el enlatado sobra.
    IF EXISTS (SELECT 1 FROM mypump_chat_estado e
                WHERE e.cliente_id = r.cliente_id
                  AND (e.escalado OR e.silenciado_hasta > now())) THEN
      UPDATE mypump_chat_programados
         SET estado = 'cancelado', motivo = 'escalado o silenciado' WHERE id = r.id;
      cliente_id := r.cliente_id; publicado := FALSE; motivo := 'escalado o silenciado';
      RETURN NEXT; CONTINUE;
    END IF;

    BEGIN
      INSERT INTO mypump_comentarios (
        cliente_id, ambito, referencia_id, referencia_nombre,
        autor, contenido, leido_por_cliente, leido_por_coach, origen, meta)
      VALUES (
        r.cliente_id, 'general', NULL, NULL,
        'coach', r.contenido, FALSE, TRUE, r.origen,
        COALESCE(r.meta, '{}'::jsonb) || jsonb_build_object('programado_id', r.id));

      UPDATE mypump_chat_programados
         SET estado = 'publicado', publicado_en = now() WHERE id = r.id;
      cliente_id := r.cliente_id; publicado := TRUE; motivo := NULL;

    EXCEPTION WHEN unique_violation THEN
      -- El índice único de `respuesta_a` saltó: alguien más ya contestó ese
      -- mensaje (Mati desde la bandeja, u otra corrida). No es un error: es la
      -- garantía funcionando. Se marca cancelado y se sigue.
      UPDATE mypump_chat_programados
         SET estado = 'cancelado', motivo = 'ya habia una respuesta a ese mensaje'
       WHERE id = r.id;
      cliente_id := r.cliente_id; publicado := FALSE;
      motivo := 'ya habia una respuesta a ese mensaje';
    END;

    RETURN NEXT;
  END LOOP;
END;
$$;

REVOKE ALL ON FUNCTION mypump_chat_drenar(integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION mypump_chat_drenar(integer) TO service_role;

-- ── 4. Un mensaje con respuesta AGENDADA sale de la cola del worker ──────
--
-- Sin esto, el worker vuelve a ver el mismo mensaje en la corrida siguiente
-- (60 s después): la respuesta está agendada pero todavía no publicada, así
-- que `ultimo_coach` no cambió. Generaría una segunda respuesta, gastaría una
-- llamada a Codex, y las dos garantías de unicidad recién la frenarían al
-- final — desperdiciando cupo cada minuto hasta que la primera se publique.
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
  WHERE COALESCE(e.ia_activa, TRUE)
    AND NOT COALESCE(e.escalado, FALSE)
    AND NOT EXISTS (SELECT 1 FROM mypump_chat_borradores b WHERE b.respuesta_a = u.id)
    -- ← lo nuevo
    AND NOT EXISTS (SELECT 1 FROM mypump_chat_programados p
                     WHERE p.estado = 'pendiente' AND p.meta->>'respuesta_a' = u.id::text)
    AND c.cliente_id NOT LIKE 'test%'
  ORDER BY u.created_at
  LIMIT LEAST(GREATEST(COALESCE(p_limite, 10), 1), 50);
END;
$$;

REVOKE ALL ON FUNCTION mypump_chat_para_responder(integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION mypump_chat_para_responder(integer) TO authenticated, service_role;

-- ── 5. Lo que la IA tiene agendado, visible para Mati ────────────────────
--
-- Durante la demora hay una respuesta escrita que el cliente todavía no vio. Si
-- Mati abre esa conversación en ese rato y no ve nada, contesta él y quedan dos
-- respuestas — la suya y la de la IA, que sale igual minutos después.
CREATE OR REPLACE FUNCTION mypump_chat_agendado_para(p_cliente_id text)
RETURNS TABLE (id bigint, contenido text, programado_para timestamptz, origen text)
LANGUAGE sql SECURITY DEFINER SET search_path = public
AS $$
  SELECT p.id, p.contenido, p.programado_para, p.origen
  FROM mypump_chat_programados p
  WHERE p.cliente_id = p_cliente_id AND p.estado = 'pendiente'
  ORDER BY p.programado_para
  LIMIT 5;
$$;

REVOKE ALL ON FUNCTION mypump_chat_agendado_para(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION mypump_chat_agendado_para(text) TO authenticated, service_role;

-- Y que Mati pueda frenarla: si va a contestar él, lo agendado se cae.
CREATE OR REPLACE FUNCTION mypump_chat_cancelar_agendado(p_id bigint)
RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF auth.role() NOT IN ('authenticated','service_role') THEN
    RAISE EXCEPTION 'Acceso denegado';
  END IF;
  UPDATE mypump_chat_programados
     SET estado = 'cancelado', motivo = 'lo freno Mati'
   WHERE id = p_id AND estado = 'pendiente';
  RETURN FOUND;
END;
$$;

REVOKE ALL ON FUNCTION mypump_chat_cancelar_agendado(bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION mypump_chat_cancelar_agendado(bigint) TO authenticated, service_role;

COMMIT;
