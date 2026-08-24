-- 066_revision_al_prompt.sql
--
-- LA SUGERENCIA LE PEDÍA AL CLIENTE ALGO QUE YA HABÍA MANDADO.
--
-- Nicolás escribió "Mañana subo las fotos! Me compré una balanza que mide grasa
-- y demás, 69 estoy". La IA le propuso a Mati contestar: "mañana cuando subas
-- las fotos lo miro junto con la revisión". Pero dos mensajes más arriba el
-- propio Mati le había escrito "me llegó el check, faltan las fotos nomás".
--
-- O sea: el check ESTABA. La IA no lo veía y quedó pidiendo algo ya entregado,
-- que es la manera más rápida de que un cliente sienta que no lo estás mirando.
--
-- El prompt recibía un único dato de la revisión: `ya_subio`, un booleano. Sabía
-- QUE había check, no QUÉ decía. Esta migración le pasa el contenido:
--
--   · el check semanal (energía, descanso, hambre, adherencia — 1 a 5 — y la
--     nota que escribió)
--   · el peso de la semana y el de la anterior, para poder decir si subió o bajó
--   · cuántas de las 3 fotos subió
--
-- Todo de la SEMANA EN CURSO, que es de lo que se está hablando.
--
-- LO QUE ESTO IMPLICA, Y HAY QUE DECIRLO
-- Hasta hoy al proveedor de IA solo le iba el texto de la conversación y el
-- nombre de pila. Ahora también le van estos números. Son datos de salud. La
-- política de privacidad decía textual que al chat "no se envía ningún dato de
-- salud: ni tu peso..." — se actualiza en el mismo commit, porque una política
-- que describe un sistema anterior es peor que no tenerla.
--
-- Lo que sigue sin salir: las fotos (solo se cuentan), la rutina, la dieta y
-- todo lo que trae el reloj.
BEGIN;

-- ── El armador de la revisión ───────────────────────────────────────────────
-- Una sola función para que las dos RPCs que alimentan al worker devuelvan
-- exactamente lo mismo. Si mañana se agrega un dato, se agrega acá y las dos lo
-- heredan — que es justo lo que no pasó con `sugerencia` en la 064, donde hubo
-- que acordarse de tocar `borradores_pendientes` aparte.
CREATE OR REPLACE FUNCTION mypump_revision_semana(p_cliente_id text)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  WITH lunes AS (
    SELECT (date_trunc('week', now() AT TIME ZONE 'America/Argentina/Buenos_Aires'))::date AS d
  ),
  chk AS (
    SELECT k.energia, k.descanso, k.hambre, k.adherencia, k.nota
      FROM mypump_checkin_semanal k, lunes l
     WHERE k.cliente_id = p_cliente_id AND k.semana_lunes = l.d
  ),
  fotos AS (
    SELECT count(*)::int AS n
      FROM mypump_fotos_progreso f, lunes l
     WHERE f.cliente_id = p_cliente_id AND f.semana_lunes = l.d
  ),
  -- Promedio de la semana, no la última medición suelta: el peso de un día
  -- puede moverse un kilo por agua y no dice nada.
  peso AS (
    SELECT ROUND(AVG(sd.valor)::numeric, 1) AS kg
      FROM mypump_salud_diaria sd, lunes l
     WHERE sd.cliente_id = p_cliente_id AND sd.tipo = 'peso_kg'
       AND sd.fecha >= l.d
  ),
  peso_prev AS (
    SELECT ROUND(AVG(sd.valor)::numeric, 1) AS kg
      FROM mypump_salud_diaria sd, lunes l
     WHERE sd.cliente_id = p_cliente_id AND sd.tipo = 'peso_kg'
       AND sd.fecha >= l.d - 7 AND sd.fecha < l.d
  )
  SELECT jsonb_strip_nulls(jsonb_build_object(
    'hay_check',   (SELECT count(*) FROM chk) > 0,
    'energia',     (SELECT energia    FROM chk),
    'descanso',    (SELECT descanso   FROM chk),
    'hambre',      (SELECT hambre     FROM chk),
    'adherencia',  (SELECT adherencia FROM chk),
    'nota',        (SELECT left(nota, 400) FROM chk),
    'fotos',       (SELECT n FROM fotos),
    'peso_kg',     (SELECT kg FROM peso),
    'peso_previo', (SELECT kg FROM peso_prev)
  ));
$$;
REVOKE ALL ON FUNCTION mypump_revision_semana(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION mypump_revision_semana(text) TO authenticated, service_role;

-- ── Las dos RPCs del worker devuelven la revisión ───────────────────────────
-- Cambia el RETURNS TABLE, así que DROP obligado en las dos.
DROP FUNCTION IF EXISTS mypump_chat_para_responder(integer);

CREATE FUNCTION mypump_chat_para_responder(p_limite integer DEFAULT 10)
RETURNS TABLE (
  cliente_id   text,
  nombre       text,
  mensaje_id   uuid,
  mensaje      text,
  mensaje_at   timestamptz,
  contexto     jsonb,
  ya_subio     boolean,
  revision     jsonb
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
    u.cliente_id, c.nombre, u.id, u.contenido, u.created_at,
    (SELECT COALESCE(jsonb_agg(jsonb_build_object('autor', h.autor, 'texto', h.contenido)
                               ORDER BY h.created_at), '[]'::jsonb)
       FROM (SELECT x.autor, x.contenido, x.created_at
               FROM mypump_comentarios x
              WHERE x.cliente_id = u.cliente_id AND x.ambito = 'general'
              ORDER BY x.created_at DESC LIMIT 10) h),
    EXISTS (SELECT 1 FROM mypump_checkin_semanal k
             WHERE k.cliente_id = u.cliente_id
               AND k.semana_lunes = (date_trunc('week', now() AT TIME ZONE 'America/Argentina/Buenos_Aires'))::date),
    mypump_revision_semana(u.cliente_id)
  FROM ultimo_por_cliente u
  JOIN mypump_clientes c ON c.cliente_id = u.cliente_id
  LEFT JOIN mypump_chat_estado e ON e.cliente_id = u.cliente_id
  WHERE COALESCE(e.ia_activa, TRUE)
    AND NOT COALESCE(e.escalado, FALSE)
    AND NOT EXISTS (SELECT 1 FROM mypump_chat_borradores b WHERE b.respuesta_a = u.id)
    AND NOT EXISTS (SELECT 1 FROM mypump_chat_programados p
                     WHERE p.estado = 'pendiente' AND p.meta->>'respuesta_a' = u.id::text)
    AND c.cliente_id NOT LIKE 'test%'
  ORDER BY u.created_at
  LIMIT LEAST(GREATEST(COALESCE(p_limite, 10), 1), 50);
END;
$$;
REVOKE ALL ON FUNCTION mypump_chat_para_responder(integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION mypump_chat_para_responder(integer) TO authenticated, service_role;

DROP FUNCTION IF EXISTS mypump_chat_borradores_sin_sugerencia(integer);

CREATE FUNCTION mypump_chat_borradores_sin_sugerencia(p_limite integer DEFAULT 20)
RETURNS TABLE (
  borrador_id  bigint,
  clase        text,
  motivo       text,
  cliente_id   text,
  nombre       text,
  mensaje_id   uuid,
  mensaje      text,
  mensaje_at   timestamptz,
  contexto     jsonb,
  ya_subio     boolean,
  revision     jsonb
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF auth.role() <> 'service_role' THEN
    RAISE EXCEPTION 'Acceso denegado';
  END IF;

  RETURN QUERY
  SELECT
    b.id, b.clase, b.motivo, b.cliente_id, c.nombre,
    m.id, m.contenido, m.created_at,
    (SELECT COALESCE(jsonb_agg(jsonb_build_object('autor', h.autor, 'texto', h.contenido)
                               ORDER BY h.created_at), '[]'::jsonb)
       FROM (SELECT x.autor, x.contenido, x.created_at
               FROM mypump_comentarios x
              WHERE x.cliente_id = b.cliente_id AND x.ambito = 'general'
              ORDER BY x.created_at DESC LIMIT 10) h),
    EXISTS (SELECT 1 FROM mypump_checkin_semanal k
             WHERE k.cliente_id = b.cliente_id
               AND k.semana_lunes = (date_trunc('week', now() AT TIME ZONE 'America/Argentina/Buenos_Aires'))::date),
    mypump_revision_semana(b.cliente_id)
  FROM mypump_chat_borradores b
  JOIN mypump_clientes c    ON c.cliente_id = b.cliente_id
  JOIN mypump_comentarios m ON m.id = b.respuesta_a
  WHERE b.estado = 'borrador'
    AND b.sugerencia IS NULL
    AND b.clase <> 'simple'
  ORDER BY (b.clase = 'urgente') DESC, b.creado_en DESC
  LIMIT LEAST(GREATEST(COALESCE(p_limite, 20), 1), 50);
END;
$$;
REVOKE ALL ON FUNCTION mypump_chat_borradores_sin_sugerencia(integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION mypump_chat_borradores_sin_sugerencia(integer) TO service_role;

-- ── Permite regenerar una sugerencia que ya existe ──────────────────────────
-- El backfill de la 065 no pisa lo que ya está, a propósito. Pero las 9
-- sugerencias que se generaron hoy salieron SIN la revisión, así que hay que
-- poder rehacerlas una vez. `p_forzar` existe para eso y para nada más.
CREATE OR REPLACE FUNCTION mypump_chat_borrador_sugerir(
  p_id         bigint,
  p_sugerencia text,
  p_forzar     boolean DEFAULT FALSE
) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_n int;
BEGIN
  IF auth.role() <> 'service_role' THEN
    RAISE EXCEPTION 'Acceso denegado';
  END IF;
  IF p_sugerencia IS NULL OR trim(p_sugerencia) = '' THEN
    RETURN FALSE;
  END IF;

  UPDATE mypump_chat_borradores
     SET sugerencia = left(trim(p_sugerencia), 1200)
   WHERE id = p_id
     AND estado = 'borrador'
     AND clase <> 'simple'
     AND (p_forzar OR sugerencia IS NULL);

  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n > 0;
END;
$$;
DROP FUNCTION IF EXISTS mypump_chat_borrador_sugerir(bigint, text);
REVOKE ALL ON FUNCTION mypump_chat_borrador_sugerir(bigint, text, boolean) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION mypump_chat_borrador_sugerir(bigint, text, boolean) TO service_role;

-- ── El guardarraíl de la 063 ────────────────────────────────────────────────
DO $guard$
DECLARE v_dupes text;
BEGIN
  SELECT string_agg(proname || ' (' || n || ' firmas)', ', ') INTO v_dupes
  FROM (SELECT p.proname, count(*) AS n
        FROM pg_proc p JOIN pg_namespace ns ON ns.oid = p.pronamespace
        WHERE ns.nspname = 'public' AND p.proname LIKE 'mypump%'
        GROUP BY p.proname HAVING count(*) > 1) d;
  IF v_dupes IS NOT NULL THEN
    RAISE EXCEPTION 'Quedaron funciones mypump duplicadas y PostgREST va a tirar PGRST203: %', v_dupes;
  END IF;
END
$guard$;

COMMIT;

NOTIFY pgrst, 'reload schema';
