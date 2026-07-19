-- ============================================================
-- 035 - Check semanal liviano del cliente (sliders 1-5 + nota)
-- ============================================================
-- El cliente registra 1 vez por semana como viene (energia, descanso,
-- hambre, adherencia percibida) + una nota libre. NO reemplaza la
-- conversacion de WhatsApp: la alimenta. El coach lo ve en el dashboard,
-- en "MyPump en vivo" y en la mini-ficha del centinela.
--
-- Escala 1-5 en todos: valor mayor = mejor, EXCEPTO hambre (5 = mucha
-- hambre, que en deficit es una senal a vigilar). El coach interpreta.
--
-- Ventana de fecha TOLERANTE (+1/-7) como toda RPC que recibe la fecha
-- local del cliente (regla timezone). La semana se ancla al lunes ISO.
-- ============================================================

CREATE TABLE IF NOT EXISTS mypump_checkin_semanal (
  id            UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  cliente_id    TEXT        NOT NULL,
  semana_lunes  DATE        NOT NULL,   -- lunes ISO de la semana del check
  energia       SMALLINT    CHECK (energia   BETWEEN 1 AND 5),
  descanso      SMALLINT    CHECK (descanso  BETWEEN 1 AND 5),
  hambre        SMALLINT    CHECK (hambre    BETWEEN 1 AND 5),
  adherencia    SMALLINT    CHECK (adherencia BETWEEN 1 AND 5),
  nota          TEXT,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (cliente_id, semana_lunes)
);

CREATE INDEX IF NOT EXISTS idx_mypump_checkin_cliente_semana
  ON mypump_checkin_semanal (cliente_id, semana_lunes DESC);

ALTER TABLE mypump_checkin_semanal ENABLE ROW LEVEL SECURITY;

CREATE POLICY "admin all mypump_checkin_semanal"
  ON mypump_checkin_semanal FOR ALL
  USING (auth.role() = 'authenticated')
  WITH CHECK (auth.role() = 'authenticated');

-- -- RPC 1: crear/actualizar el check de la semana (upsert por lunes ISO) --
CREATE OR REPLACE FUNCTION mypump_guardar_checkin(
  p_token      TEXT,
  p_fecha      DATE,       -- "hoy" del cliente (fecha local)
  p_energia    SMALLINT,
  p_descanso   SMALLINT,
  p_hambre     SMALLINT,
  p_adherencia SMALLINT,
  p_nota       TEXT DEFAULT NULL
)
RETURNS SETOF mypump_checkin_semanal
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_cliente_id TEXT;
  v_hoy        DATE;
  v_lunes      DATE;
  v_id         UUID;
BEGIN
  v_cliente_id := mypump_get_cliente_id_from_token(p_token);
  IF v_cliente_id IS NULL THEN RETURN; END IF;

  -- Ventana tolerante a zona horaria/reloj del device (regla 020/028).
  v_hoy := (NOW() AT TIME ZONE 'America/Argentina/Buenos_Aires')::DATE;
  IF p_fecha > v_hoy + 1 THEN
    RAISE EXCEPTION 'No se puede registrar una fecha futura';
  END IF;
  IF p_fecha < v_hoy - 7 THEN
    RAISE EXCEPTION 'Solo se permite backfill de hasta 7 dias';
  END IF;

  v_lunes := date_trunc('week', p_fecha)::DATE;  -- lunes ISO de esa semana

  INSERT INTO mypump_checkin_semanal
    (cliente_id, semana_lunes, energia, descanso, hambre, adherencia, nota)
  VALUES
    (v_cliente_id, v_lunes, p_energia, p_descanso, p_hambre, p_adherencia,
     NULLIF(trim(COALESCE(p_nota, '')), ''))
  ON CONFLICT (cliente_id, semana_lunes) DO UPDATE
    SET energia    = EXCLUDED.energia,
        descanso   = EXCLUDED.descanso,
        hambre     = EXCLUDED.hambre,
        adherencia = EXCLUDED.adherencia,
        nota       = EXCLUDED.nota,
        updated_at = NOW()
  RETURNING id INTO v_id;

  RETURN QUERY SELECT * FROM mypump_checkin_semanal WHERE id = v_id;
END;
$$;

GRANT EXECUTE ON FUNCTION mypump_guardar_checkin(TEXT, DATE, SMALLINT, SMALLINT, SMALLINT, SMALLINT, TEXT)
  TO anon, authenticated;

-- -- RPC 2: el check de la semana que contiene p_fecha (para la app) --
CREATE OR REPLACE FUNCTION mypump_get_checkin_semana(
  p_token TEXT,
  p_fecha DATE
)
RETURNS SETOF mypump_checkin_semanal
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_cliente_id TEXT;
BEGIN
  v_cliente_id := mypump_get_cliente_id_from_token(p_token);
  IF v_cliente_id IS NULL THEN RETURN; END IF;
  RETURN QUERY
    SELECT * FROM mypump_checkin_semanal
    WHERE cliente_id = v_cliente_id
      AND semana_lunes = date_trunc('week', p_fecha)::DATE;
END;
$$;

GRANT EXECUTE ON FUNCTION mypump_get_checkin_semana(TEXT, DATE) TO anon, authenticated;

-- ============================================================
-- Extender mypump_get_metricas_coach: agregar ultimo_checkin JSONB.
-- Cambia el RETURNS TABLE, asi que hay que DROP + CREATE (no OR REPLACE).
-- El resto de la logica es identica a la 034.
-- ============================================================
DROP FUNCTION IF EXISTS mypump_get_metricas_coach(INTEGER);

CREATE FUNCTION mypump_get_metricas_coach(p_semanas INTEGER DEFAULT 6)
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
  ultimo_peso_fecha   DATE,
  ultimo_checkin      JSONB
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
  ),
  chk AS (
    SELECT DISTINCT ON (ck.cliente_id) ck.cliente_id,
           jsonb_build_object('semana', ck.semana_lunes, 'energia', ck.energia,
             'descanso', ck.descanso, 'hambre', ck.hambre, 'adherencia', ck.adherencia,
             'nota', ck.nota) AS ultimo
    FROM mypump_checkin_semanal ck
    ORDER BY ck.cliente_id, ck.semana_lunes DESC
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
    (SELECT MAX(p2.ult) FROM peso p2 WHERE p2.cliente_id = a.cliente_id),
    (SELECT c2.ultimo FROM chk c2 WHERE c2.cliente_id = a.cliente_id)
  FROM activos a
  ORDER BY a.nombre;
END;
$$;

GRANT EXECUTE ON FUNCTION mypump_get_metricas_coach(INTEGER) TO authenticated, service_role;
REVOKE EXECUTE ON FUNCTION mypump_get_metricas_coach(INTEGER) FROM anon, public;

-- ============================================================
-- ROLLBACK (revierte esta migracion por completo):
--   DROP FUNCTION IF EXISTS mypump_get_checkin_semana(TEXT, DATE);
--   DROP FUNCTION IF EXISTS mypump_guardar_checkin(TEXT, DATE, SMALLINT, SMALLINT, SMALLINT, SMALLINT, TEXT);
--   DROP TABLE IF EXISTS mypump_checkin_semanal;
--   -- y recrear mypump_get_metricas_coach SIN ultimo_checkin (ver 034).
-- ============================================================
