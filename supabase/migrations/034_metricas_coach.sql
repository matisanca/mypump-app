-- ============================================================
-- 034 - mypump_get_metricas_coach: metricas agregadas por cliente
-- ============================================================
-- Base de datos del bot centinela (Mini), de la seccion "MyPump en vivo"
-- del Cerebro y del brief pre-call. Una fila por cliente con rutina activa:
-- adherencia (sesiones/semana), rendimiento (tonelaje y e1RM de compuestos
-- por semana) y peso corporal (media semanal), ultimas p_semanas.
--
-- Notas:
-- - Se EXCLUYEN las sesiones con semana=0 (historial importado de Excel,
--   convencion del import de bitacoras: no son entrenos del ciclo actual).
-- - e1RM = peso * reps / 30 + peso (formula Epley/30 usada en las hojas).
-- - GRANT solo a authenticated (Cerebro logueado) y service_role (bot).
--   NUNCA anon: expone datos de todos los clientes.
-- ============================================================

CREATE OR REPLACE FUNCTION mypump_get_metricas_coach(p_semanas INTEGER DEFAULT 6)
RETURNS TABLE (
  cliente_id          TEXT,
  nombre              TEXT,
  perfil              TEXT,
  objetivo            TEXT,
  semana_actual       INTEGER,
  dias_plan           INTEGER,
  sesiones_por_semana JSONB,
  tonelaje_por_semana JSONB,
  e1rm_top            JSONB,
  peso_semanal        JSONB,
  ultima_sesion       TIMESTAMPTZ,
  ultimo_peso_fecha   DATE
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_desde DATE := (date_trunc('week', NOW()) - make_interval(weeks => GREATEST(p_semanas, 1) - 1))::DATE;
BEGIN
  RETURN QUERY
  WITH activos AS (
    SELECT c.cliente_id, c.nombre, c.perfil,
           r.id AS rutina_id, r.semana_actual,
           r.estructura->'perfil'->>'objetivo' AS objetivo,
           COALESCE(jsonb_array_length(r.estructura->'dias'), 0) AS dias_plan,
           r.estructura
    FROM mypump_clientes c
    JOIN mypump_rutinas r ON r.cliente_id = c.cliente_id AND r.estado = 'activa'
  ),
  ses AS (
    SELECT s.cliente_id,
           date_trunc('week', s.iniciada_en)::DATE AS sem,
           COUNT(*) FILTER (WHERE s.finalizada_en IS NOT NULL) AS finalizadas,
           MAX(s.iniciada_en) AS ult
    FROM mypump_sesiones s
    WHERE COALESCE(s.semana, 1) <> 0
      AND s.iniciada_en >= v_desde
    GROUP BY s.cliente_id, date_trunc('week', s.iniciada_en)::DATE
  ),
  ton AS (
    SELECT rc.cliente_id,
           date_trunc('week', rc.registrado_en)::DATE AS sem,
           ROUND(SUM(rc.peso_kg * rc.reps_realizadas)) AS kg
    FROM mypump_registros_carga rc
    JOIN mypump_sesiones s ON s.id = rc.sesion_id
    WHERE COALESCE(s.semana, 1) <> 0
      AND rc.registrado_en >= v_desde
      AND rc.peso_kg > 0 AND rc.reps_realizadas > 0
    GROUP BY rc.cliente_id, date_trunc('week', rc.registrado_en)::DATE
  ),
  compuestos AS (
    -- ejercicios tipo compuesto de la rutina activa de cada cliente
    SELECT a.cliente_id, e->>'id' AS ejercicio_id, e->>'nombre' AS ejercicio_nombre
    FROM activos a,
         jsonb_array_elements(a.estructura->'dias') d,
         jsonb_array_elements(d->'bloques') b,
         jsonb_array_elements(b->'ejercicios') e
    WHERE e->>'tipo' = 'compuesto'
  ),
  e1rm AS (
    SELECT rc.cliente_id, co.ejercicio_nombre,
           date_trunc('week', rc.registrado_en)::DATE AS sem,
           ROUND(MAX(rc.peso_kg * rc.reps_realizadas / 30.0 + rc.peso_kg), 1) AS mejor
    FROM mypump_registros_carga rc
    JOIN compuestos co ON co.cliente_id = rc.cliente_id AND co.ejercicio_id = rc.ejercicio_id
    JOIN mypump_sesiones s ON s.id = rc.sesion_id
    WHERE COALESCE(s.semana, 1) <> 0
      AND rc.registrado_en >= v_desde
      AND rc.peso_kg > 0 AND rc.reps_realizadas > 0 AND rc.reps_realizadas <= 15
    GROUP BY rc.cliente_id, co.ejercicio_nombre, date_trunc('week', rc.registrado_en)::DATE
  ),
  peso AS (
    SELECT sd.cliente_id,
           date_trunc('week', sd.fecha)::DATE AS sem,
           ROUND(AVG(sd.valor), 2) AS kg,
           MAX(sd.fecha) AS ult
    FROM mypump_salud_diaria sd
    WHERE sd.tipo = 'peso_kg' AND sd.fecha >= v_desde
    GROUP BY sd.cliente_id, date_trunc('week', sd.fecha)::DATE
  )
  SELECT
    a.cliente_id, a.nombre, a.perfil, a.objetivo,
    a.semana_actual, a.dias_plan::INTEGER,
    COALESCE((SELECT jsonb_agg(jsonb_build_object('semana', se.sem, 'sesiones', se.finalizadas) ORDER BY se.sem)
              FROM ses se WHERE se.cliente_id = a.cliente_id), '[]'::jsonb),
    COALESCE((SELECT jsonb_agg(jsonb_build_object('semana', t.sem, 'kg', t.kg) ORDER BY t.sem)
              FROM ton t WHERE t.cliente_id = a.cliente_id), '[]'::jsonb),
    COALESCE((SELECT jsonb_agg(jsonb_build_object('ejercicio', x.ejercicio_nombre, 'semana', x.sem, 'e1rm', x.mejor) ORDER BY x.ejercicio_nombre, x.sem)
              FROM e1rm x WHERE x.cliente_id = a.cliente_id), '[]'::jsonb),
    COALESCE((SELECT jsonb_agg(jsonb_build_object('semana', p.sem, 'kg', p.kg) ORDER BY p.sem)
              FROM peso p WHERE p.cliente_id = a.cliente_id), '[]'::jsonb),
    (SELECT MAX(se2.ult) FROM ses se2 WHERE se2.cliente_id = a.cliente_id),
    (SELECT MAX(p2.ult) FROM peso p2 WHERE p2.cliente_id = a.cliente_id)
  FROM activos a
  ORDER BY a.nombre;
END;
$$;

GRANT EXECUTE ON FUNCTION mypump_get_metricas_coach(INTEGER) TO authenticated, service_role;
REVOKE EXECUTE ON FUNCTION mypump_get_metricas_coach(INTEGER) FROM anon, public;

-- ============================================================
-- ROLLBACK (revierte esta migracion por completo):
--   DROP FUNCTION IF EXISTS mypump_get_metricas_coach(INTEGER);
-- ============================================================
