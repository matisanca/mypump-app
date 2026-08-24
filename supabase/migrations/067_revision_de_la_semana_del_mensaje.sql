-- 067_revision_de_la_semana_del_mensaje.sql
--
-- LA REVISION SE MIRABA EN LA SEMANA EQUIVOCADA.
--
-- La 066 le pasó al prompt la revisión de la semana... calculada con `now()`.
-- Parece obvio y está mal: la conversación que se está contestando puede ser de
-- la semana pasada.
--
-- El caso que lo destapó, medido el lunes 24-ago a las 19:50:
--
--   · hoy es lunes 24 → date_trunc('week', now()) = 24-ago, o sea la semana
--     EMPEZÓ HACE UNAS HORAS y todavía no hay ningún check cargado;
--   · el mensaje de Nicolás es del 21-ago → semana del 17-ago;
--   · su check de la semana del 17 SÍ existe: energía 4, descanso 3, hambre 2,
--     adherencia 4.
--
-- Resultado: la IA leyó "no hay check" y le propuso a Mati escribirle
-- "completá la revisión, que todavía no quedó cargada" — cuando dos mensajes
-- antes el propio Mati le había dicho "me llegó el check, faltan las fotos
-- nomás". Peor que no cruzar nada: cruzarlo con la semana que no era.
--
-- Y no es un caso raro. Pasa TODOS los lunes y martes con cualquier
-- conversación que venga del fin de semana, que es cuando llegan casi todas
-- (la ronda sale el domingo 18:00).
--
-- El ancla correcta es la fecha DEL MENSAJE que se está contestando.
BEGIN;

-- ── La revisión, anclada a una fecha de referencia ──────────────────────────
-- `p_ref` por defecto es now() para no romper a ningún llamador viejo, pero las
-- dos RPCs del worker ahora le pasan el created_at del mensaje.
DROP FUNCTION IF EXISTS mypump_revision_semana(text);

CREATE FUNCTION mypump_revision_semana(
  p_cliente_id text,
  p_ref        timestamptz DEFAULT now()
) RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  WITH lunes AS (
    SELECT (date_trunc('week', p_ref AT TIME ZONE 'America/Argentina/Buenos_Aires'))::date AS d
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
  peso AS (
    SELECT ROUND(AVG(sd.valor)::numeric, 1) AS kg
      FROM mypump_salud_diaria sd, lunes l
     WHERE sd.cliente_id = p_cliente_id AND sd.tipo = 'peso_kg'
       AND sd.fecha >= l.d AND sd.fecha < l.d + 7
  ),
  peso_prev AS (
    SELECT ROUND(AVG(sd.valor)::numeric, 1) AS kg
      FROM mypump_salud_diaria sd, lunes l
     WHERE sd.cliente_id = p_cliente_id AND sd.tipo = 'peso_kg'
       AND sd.fecha >= l.d - 7 AND sd.fecha < l.d
  )
  SELECT jsonb_strip_nulls(jsonb_build_object(
    'semana',      (SELECT d FROM lunes),
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
REVOKE ALL ON FUNCTION mypump_revision_semana(text, timestamptz) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION mypump_revision_semana(text, timestamptz) TO authenticated, service_role;

-- ── Las dos RPCs pasan la fecha del mensaje ─────────────────────────────────
-- `ya_subio` tenía el mismo error de ancla, así que ahora sale de la misma
-- fuente en vez de repetir el date_trunc a mano. Un solo lugar donde
-- equivocarse.
CREATE OR REPLACE FUNCTION mypump_chat_para_responder(p_limite integer DEFAULT 10)
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
  ),
  con_rev AS (
    SELECT u.*, mypump_revision_semana(u.cliente_id, u.created_at) AS rev
    FROM ultimo_por_cliente u
  )
  SELECT
    u.cliente_id, c.nombre, u.id, u.contenido, u.created_at,
    (SELECT COALESCE(jsonb_agg(jsonb_build_object('autor', h.autor, 'texto', h.contenido)
                               ORDER BY h.created_at), '[]'::jsonb)
       FROM (SELECT x.autor, x.contenido, x.created_at
               FROM mypump_comentarios x
              WHERE x.cliente_id = u.cliente_id AND x.ambito = 'general'
              ORDER BY x.created_at DESC LIMIT 10) h),
    COALESCE((u.rev->>'hay_check')::boolean, FALSE),
    u.rev
  FROM con_rev u
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

CREATE OR REPLACE FUNCTION mypump_chat_borradores_sin_sugerencia(p_limite integer DEFAULT 20)
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
  WITH base AS (
    SELECT b.id, b.clase, b.motivo, b.cliente_id, b.creado_en,
           m.id AS msg_id, m.contenido, m.created_at,
           mypump_revision_semana(b.cliente_id, m.created_at) AS rev
      FROM mypump_chat_borradores b
      JOIN mypump_comentarios m ON m.id = b.respuesta_a
     WHERE b.estado = 'borrador' AND b.sugerencia IS NULL AND b.clase <> 'simple'
  )
  SELECT
    x.id, x.clase, x.motivo, x.cliente_id, c.nombre,
    x.msg_id, x.contenido, x.created_at,
    (SELECT COALESCE(jsonb_agg(jsonb_build_object('autor', h.autor, 'texto', h.contenido)
                               ORDER BY h.created_at), '[]'::jsonb)
       FROM (SELECT y.autor, y.contenido, y.created_at
               FROM mypump_comentarios y
              WHERE y.cliente_id = x.cliente_id AND y.ambito = 'general'
              ORDER BY y.created_at DESC LIMIT 10) h),
    COALESCE((x.rev->>'hay_check')::boolean, FALSE),
    x.rev
  FROM base x
  JOIN mypump_clientes c ON c.cliente_id = x.cliente_id
  ORDER BY (x.clase = 'urgente') DESC, x.creado_en DESC
  LIMIT LEAST(GREATEST(COALESCE(p_limite, 20), 1), 50);
END;
$$;
REVOKE ALL ON FUNCTION mypump_chat_borradores_sin_sugerencia(integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION mypump_chat_borradores_sin_sugerencia(integer) TO service_role;

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
