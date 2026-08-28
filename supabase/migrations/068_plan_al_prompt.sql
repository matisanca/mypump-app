-- 068_plan_al_prompt.sql
--
-- LAS SUGERENCIAS LE REPETÍAN AL CLIENTE LO QUE ACABABA DE ESCRIBIR.
--
-- Martín: "arranqué la semana con 72 kg así que vengo bien, lo único que se me
-- está complicando entrenar 6 días".
-- La IA propuso: "martin, recibí el check y vi los 72 kg, también que se te está
-- complicando entrenar 6 días". Y se terminaba ahí. Un eco.
--
-- Roberto preguntó algo concreto —"hago 10' de calentamiento y 40' post-pesas,
-- llego a 8 mil pasos, ¿meto 50/60 min más para llegar a 13 mil o espero a que
-- me estanque?"— y la sugerencia le contestó preguntándole por el hambre y las
-- venas, que él ya había explicado en el mismo mensaje.
--
-- LA CAUSA ES EL PROMPT, NO EL MODELO. Decía "reconocé lo que contó y hacé LA
-- pregunta que Mati necesitaría", y prohibía toda indicación. El modelo hizo
-- exactamente eso. Cuando el cliente ya contestó todo, no le queda nada que
-- preguntar: repite y rellena.
--
-- Para contestar "¿agrego cardio?" hay que saber qué entrena y cuánto come. El
-- prompt no tenía nada de eso: `mypump_revision_semana` da lo que el cliente
-- reportó, no lo que Mati le prescribió. Esta migración suma el plan.
--
-- Se manda un RESUMEN, no el plan entero: la rutina de Roberto son 72 KB de
-- JSON con cada serie de cada día. Al prompt le sirve saber "6 días, semana 2 de
-- 12, 1643 kcal y 165 g de proteína", no la lista de ejercicios.
--
-- LO QUE ESTO CAMBIA EN LA POSTURA, Y HAY QUE DECIRLO
-- Con el plan a la vista, la sugerencia puede llevar criterio de entrenamiento
-- y nutrición. Eso es lo que Mati pidió —él aprueba antes de que salga— pero es
-- un cambio real: hasta hoy ninguna respuesta generada podía contener una
-- indicación. Sigue sin poder: `respuesta` (lo único que se manda solo) no toca
-- nada de esto y su validador determinista no se afloja. Lo que cambia es
-- `sugerencia`, que no tiene camino al cliente que no pase por el botón.
BEGIN;

-- ── El plan, en cuatro líneas ───────────────────────────────────────────────
CREATE OR REPLACE FUNCTION mypump_plan_resumen(p_cliente_id text)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT jsonb_strip_nulls(jsonb_build_object(
    'dias_entreno', (SELECT jsonb_array_length(ru.estructura->'dias')
                       FROM mypump_rutinas ru
                      WHERE ru.cliente_id = p_cliente_id AND ru.estado = 'activa'
                      ORDER BY ru.version DESC LIMIT 1),
    'semana',       (SELECT ru.semana_actual FROM mypump_rutinas ru
                      WHERE ru.cliente_id = p_cliente_id AND ru.estado = 'activa'
                      ORDER BY ru.version DESC LIMIT 1),
    'semanas_total',(SELECT (ru.estructura->>'semanas_total')::int FROM mypump_rutinas ru
                      WHERE ru.cliente_id = p_cliente_id AND ru.estado = 'activa'
                      ORDER BY ru.version DESC LIMIT 1),
    'fase',         (SELECT ru.estructura->>'fase' FROM mypump_rutinas ru
                      WHERE ru.cliente_id = p_cliente_id AND ru.estado = 'activa'
                      ORDER BY ru.version DESC LIMIT 1),
    'macros',       (SELECT d.estructura->'macros_target' FROM mypump_dietas d
                      WHERE d.cliente_id = p_cliente_id AND d.estado = 'activa'
                      ORDER BY d.version DESC LIMIT 1)
  ));
$$;
REVOKE ALL ON FUNCTION mypump_plan_resumen(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION mypump_plan_resumen(text) TO authenticated, service_role;

-- ── Las dos RPCs del worker lo devuelven ────────────────────────────────────
-- Suma la columna `plan` al RETURNS TABLE, así que DROP obligado:
-- CREATE OR REPLACE no puede cambiar el tipo de retorno (lo dice la
-- 067 y lo volví a olvidar acá; el error es claro y aborta la
-- transacción entera, que es lo que uno quiere).
DROP FUNCTION IF EXISTS mypump_chat_para_responder(integer);

CREATE FUNCTION mypump_chat_para_responder(p_limite integer DEFAULT 10)
RETURNS TABLE (
  cliente_id text, nombre text, mensaje_id uuid, mensaje text,
  mensaje_at timestamptz, contexto jsonb, ya_subio boolean,
  revision jsonb, plan jsonb
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  WITH ultimo_coach AS (
    SELECT m.cliente_id, max(m.created_at) AS at FROM mypump_comentarios m
     WHERE m.ambito = 'general' AND m.autor = 'coach' GROUP BY m.cliente_id),
  sin_responder AS (
    SELECT m.* FROM mypump_comentarios m
      LEFT JOIN ultimo_coach u ON u.cliente_id = m.cliente_id
     WHERE m.ambito = 'general' AND m.autor = 'cliente'
       AND (u.at IS NULL OR m.created_at > u.at)
       AND m.created_at < now() - interval '1 minute'),
  ultimo_por_cliente AS (
    SELECT DISTINCT ON (s.cliente_id) s.* FROM sin_responder s
     ORDER BY s.cliente_id, s.created_at DESC),
  con_rev AS (
    SELECT u.*, mypump_revision_semana(u.cliente_id, u.created_at) AS rev
      FROM ultimo_por_cliente u)
  SELECT
    u.cliente_id, c.nombre, u.id, u.contenido, u.created_at,
    (SELECT COALESCE(jsonb_agg(jsonb_build_object('autor', h.autor, 'texto', h.contenido)
                               ORDER BY h.created_at), '[]'::jsonb)
       FROM (SELECT x.autor, x.contenido, x.created_at FROM mypump_comentarios x
              WHERE x.cliente_id = u.cliente_id AND x.ambito = 'general'
              ORDER BY x.created_at DESC LIMIT 10) h),
    COALESCE((u.rev->>'hay_check')::boolean, FALSE),
    u.rev,
    mypump_plan_resumen(u.cliente_id)
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

-- Suma la columna `plan` al RETURNS TABLE, así que DROP obligado:
-- CREATE OR REPLACE no puede cambiar el tipo de retorno (lo dice la
-- 067 y lo volví a olvidar acá; el error es claro y aborta la
-- transacción entera, que es lo que uno quiere).
DROP FUNCTION IF EXISTS mypump_chat_borradores_sin_sugerencia(integer);

CREATE FUNCTION mypump_chat_borradores_sin_sugerencia(p_limite integer DEFAULT 20)
RETURNS TABLE (
  borrador_id bigint, clase text, motivo text, cliente_id text, nombre text,
  mensaje_id uuid, mensaje text, mensaje_at timestamptz, contexto jsonb,
  ya_subio boolean, revision jsonb, plan jsonb
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
     WHERE b.estado = 'borrador' AND b.sugerencia IS NULL AND b.clase <> 'simple')
  SELECT
    x.id, x.clase, x.motivo, x.cliente_id, c.nombre,
    x.msg_id, x.contenido, x.created_at,
    (SELECT COALESCE(jsonb_agg(jsonb_build_object('autor', h.autor, 'texto', h.contenido)
                               ORDER BY h.created_at), '[]'::jsonb)
       FROM (SELECT y.autor, y.contenido, y.created_at FROM mypump_comentarios y
              WHERE y.cliente_id = x.cliente_id AND y.ambito = 'general'
              ORDER BY y.created_at DESC LIMIT 10) h),
    COALESCE((x.rev->>'hay_check')::boolean, FALSE),
    x.rev,
    mypump_plan_resumen(x.cliente_id)
  FROM base x
  JOIN mypump_clientes c ON c.cliente_id = x.cliente_id
  ORDER BY (x.clase = 'urgente') DESC, x.creado_en DESC
  LIMIT LEAST(GREATEST(COALESCE(p_limite, 20), 1), 50);
END;
$$;
REVOKE ALL ON FUNCTION mypump_chat_borradores_sin_sugerencia(integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION mypump_chat_borradores_sin_sugerencia(integer) TO service_role;

DO $guard$
DECLARE v_dupes text;
BEGIN
  SELECT string_agg(proname || ' (' || n || ' firmas)', ', ') INTO v_dupes
  FROM (SELECT p.proname, count(*) AS n
        FROM pg_proc p JOIN pg_namespace ns ON ns.oid = p.pronamespace
        WHERE ns.nspname = 'public' AND p.proname LIKE 'mypump%'
        GROUP BY p.proname HAVING count(*) > 1) d;
  IF v_dupes IS NOT NULL THEN
    RAISE EXCEPTION 'Funciones mypump duplicadas, PostgREST va a tirar PGRST203: %', v_dupes;
  END IF;
END
$guard$;

COMMIT;

NOTIFY pgrst, 'reload schema';
