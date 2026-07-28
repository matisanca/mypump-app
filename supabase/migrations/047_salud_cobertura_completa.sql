-- ============================================================
-- 047 — Cobertura completa de Apple Health + entrenamientos
--
-- POR QUÉ
-- El bridge captura 10 tipos. El plugin nativo expone 25 y Apple Health
-- guarda todavía más. Los que faltaban no son relleno: son los que un coach
-- que además es médico usa para decidir.
--
-- Tres huecos que dolían:
--
-- 1. ENERGÍA REAL. Hoy el TDEE sale de Mifflin-St Jeor, una fórmula de 1990
--    con ±10% de error individual. El iPhone/Watch mide kcal basales + activas
--    todos los días. Teniendo el gasto MEDIDO, la dieta se ajusta contra el
--    dato de esa persona y no contra el promedio de una población.
--
-- 2. SEGURIDAD CLÍNICA. Mati trabaja con farmacología deportiva. La presión
--    arterial es EL marcador que hay que vigilar con AAS (hipertensión), y la
--    glucosa lo es con GH/insulina. Si el cliente ya se las mide y quedan en
--    Apple Health, no verlas es tirar el dato más importante que tenemos.
--
-- 3. LO QUE ENTRENA FUERA DE LA APP. El cardio, el fútbol de los jueves, la
--    bici. Hoy es invisible: se le calculan kcal como si no existiera. Por eso
--    va una tabla de entrenamientos aparte — son EVENTOS (varios por día, con
--    tipo y duración), no una serie diaria, y meterlos en salud_diaria los
--    aplastaría a un número por día.
--
-- El peso ya estaba en la whitelist pero el bridge no lo leía: si el cliente
-- tiene balanza inteligente, ya está en Apple Health y lo estaba tipeando a
-- mano al pedo. Ahora se lee, con el manual ganando siempre (ver 048).
-- ============================================================

-- ── 1. Tipos nuevos en la whitelist ────────────────────────────────────
ALTER TABLE mypump_salud_diaria
  DROP CONSTRAINT IF EXISTS mypump_salud_diaria_tipo_check;

ALTER TABLE mypump_salud_diaria
  ADD CONSTRAINT mypump_salud_diaria_tipo_check
  CHECK (tipo IN (
    -- actividad
    'pasos', 'actividad_min', 'kcal_activas',
    'distancia_km', 'pisos',
    -- energía (TDEE medido, no estimado)
    'kcal_basales', 'kcal_totales',
    -- cardíaco
    'fc_reposo', 'hrv_ms', 'fc_media', 'fc_max',
    -- cardiorrespiratorio
    'vo2max',
    -- sueño
    'sueno_min', 'sueno_profundo_min', 'sueno_rem_min', 'sueno_ligero_min',
    'sueno_medio_min', 'sueno_eficiencia_pct',
    -- otras señales fisiológicas
    'respiracion_rpm', 'spo2_pct', 'temp_muneca_c', 'temp_corporal_c',
    -- clínicos (relevantes con farmacología)
    'presion_sistolica', 'presion_diastolica', 'glucosa_mg_dl',
    -- composición corporal
    'peso_kg', 'grasa_pct', 'masa_magra_kg', 'altura_cm',
    -- bienestar
    'mindful_min'
  ));

-- ── 2. Rangos sanos por tipo ───────────────────────────────────────────
-- Un sensor que falla no manda null: manda basura. Una FC de 0, una presión
-- de 400. Sin este filtro, un solo día corrupto arrastra el baseline de 60
-- días y el cliente ve un número que no significa nada.
CREATE OR REPLACE FUNCTION mypump_salud_valor_plausible(p_tipo text, p_valor numeric)
RETURNS boolean
LANGUAGE sql IMMUTABLE
AS $$
  SELECT CASE p_tipo
    WHEN 'pasos'                THEN p_valor BETWEEN 0 AND 100000
    WHEN 'distancia_km'         THEN p_valor BETWEEN 0 AND 200
    WHEN 'pisos'                THEN p_valor BETWEEN 0 AND 500
    WHEN 'actividad_min'        THEN p_valor BETWEEN 0 AND 1440
    WHEN 'mindful_min'          THEN p_valor BETWEEN 0 AND 1440
    WHEN 'kcal_activas'         THEN p_valor BETWEEN 0 AND 10000
    WHEN 'kcal_basales'         THEN p_valor BETWEEN 500 AND 5000
    WHEN 'kcal_totales'         THEN p_valor BETWEEN 500 AND 15000
    WHEN 'fc_reposo'            THEN p_valor BETWEEN 25 AND 140
    WHEN 'fc_media'             THEN p_valor BETWEEN 30 AND 200
    WHEN 'fc_max'               THEN p_valor BETWEEN 60 AND 230
    WHEN 'hrv_ms'               THEN p_valor BETWEEN 1 AND 400
    WHEN 'vo2max'               THEN p_valor BETWEEN 10 AND 100
    WHEN 'sueno_min'            THEN p_valor BETWEEN 0 AND 1440
    WHEN 'sueno_profundo_min'   THEN p_valor BETWEEN 0 AND 1440
    WHEN 'sueno_rem_min'        THEN p_valor BETWEEN 0 AND 1440
    WHEN 'sueno_ligero_min'     THEN p_valor BETWEEN 0 AND 1440
    WHEN 'sueno_medio_min'      THEN p_valor BETWEEN 0 AND 1440
    WHEN 'sueno_eficiencia_pct' THEN p_valor BETWEEN 0 AND 100
    WHEN 'respiracion_rpm'      THEN p_valor BETWEEN 4 AND 40
    WHEN 'spo2_pct'             THEN p_valor BETWEEN 50 AND 100
    WHEN 'temp_muneca_c'        THEN p_valor BETWEEN 25 AND 45
    WHEN 'temp_corporal_c'      THEN p_valor BETWEEN 30 AND 45
    WHEN 'presion_sistolica'    THEN p_valor BETWEEN 60 AND 260
    WHEN 'presion_diastolica'   THEN p_valor BETWEEN 30 AND 180
    WHEN 'glucosa_mg_dl'        THEN p_valor BETWEEN 20 AND 600
    WHEN 'peso_kg'              THEN p_valor BETWEEN 25 AND 400
    WHEN 'grasa_pct'            THEN p_valor BETWEEN 2 AND 70
    WHEN 'masa_magra_kg'        THEN p_valor BETWEEN 15 AND 200
    WHEN 'altura_cm'            THEN p_valor BETWEEN 80 AND 260
    ELSE TRUE   -- tipo nuevo todavía sin rango: se acepta, no se bloquea
  END;
$$;

COMMENT ON FUNCTION mypump_salud_valor_plausible IS
  'Rango fisiológicamente posible por tipo. Amplio a propósito: descarta '
  'basura de sensor (FC 0, presión 400), NO valores raros pero reales.';

-- ── 3. Entrenamientos de Apple Health ──────────────────────────────────
-- Tabla aparte y no un tipo más: son eventos con tipo y duración, y puede
-- haber varios por día. Aplastarlos a un número por día perdería justo lo
-- que los hace útiles (qué hizo, cuánto, a qué intensidad).
CREATE TABLE IF NOT EXISTS mypump_entrenos_health (
  id           bigserial PRIMARY KEY,
  cliente_id   text        NOT NULL,
  fecha        date        NOT NULL,
  inicio       timestamptz NOT NULL,
  fin          timestamptz,
  tipo         text        NOT NULL,      -- 'running', 'cycling', 'strengthTraining'…
  duracion_min numeric,
  kcal         numeric,
  distancia_km numeric,
  fc_media     numeric,
  fc_max       numeric,
  fuente       text        NOT NULL DEFAULT 'apple_health',
  -- Clave natural: mismo entreno reimportado no se duplica. HealthKit no da
  -- un id estable entre lecturas, así que (cliente, inicio, tipo) es lo más
  -- cercano a una identidad que tenemos.
  UNIQUE (cliente_id, inicio, tipo)
);

CREATE INDEX IF NOT EXISTS idx_entrenos_health_cliente_fecha
  ON mypump_entrenos_health (cliente_id, fecha DESC);

ALTER TABLE mypump_entrenos_health ENABLE ROW LEVEL SECURITY;

-- Sin políticas: igual que salud_diaria, solo entra por RPC SECURITY DEFINER
-- con el token. RLS activa + cero políticas = anon no ve nada.
COMMENT ON TABLE mypump_entrenos_health IS
  'Entrenamientos leídos de Apple Health (cardio, deportes, lo que hace fuera '
  'de la app). Sin esto su gasto real es invisible para el plan.';

-- ── 4. Ingesta de entrenamientos ───────────────────────────────────────
CREATE OR REPLACE FUNCTION mypump_ingest_entrenos(
  p_token   text,
  p_entrenos jsonb
) RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_cliente text;
  v_e       jsonb;
  v_n       integer := 0;
  v_inicio  timestamptz;
  v_tipo    text;
BEGIN
  SELECT cliente_id INTO v_cliente
  FROM mypump_tokens WHERE token = p_token AND revocado_en IS NULL;
  IF v_cliente IS NULL THEN RAISE EXCEPTION 'token invalido'; END IF;

  IF jsonb_typeof(p_entrenos) <> 'array' THEN RETURN 0; END IF;
  -- Tope defensivo: una sync normal trae decenas. Miles = bug o abuso.
  IF jsonb_array_length(p_entrenos) > 500 THEN RAISE EXCEPTION 'demasiados entrenos'; END IF;

  FOR v_e IN SELECT * FROM jsonb_array_elements(p_entrenos) LOOP
    BEGIN
      v_inicio := (v_e->>'inicio')::timestamptz;
      v_tipo   := NULLIF(trim(v_e->>'tipo'), '');
    EXCEPTION WHEN others THEN
      CONTINUE;   -- fecha o tipo ilegibles: se saltea, no se aborta la tanda
    END;
    CONTINUE WHEN v_inicio IS NULL OR v_tipo IS NULL;
    -- Nada del futuro ni de hace más de 2 años.
    CONTINUE WHEN v_inicio > now() + interval '1 day'
              OR v_inicio < now() - interval '2 years';

    INSERT INTO mypump_entrenos_health
      (cliente_id, fecha, inicio, fin, tipo, duracion_min, kcal, distancia_km, fc_media, fc_max, fuente)
    VALUES (
      v_cliente,
      (v_inicio AT TIME ZONE 'America/Argentina/Buenos_Aires')::date,
      v_inicio,
      NULLIF(v_e->>'fin','')::timestamptz,
      left(v_tipo, 60),
      NULLIF(v_e->>'duracion_min','')::numeric,
      NULLIF(v_e->>'kcal','')::numeric,
      NULLIF(v_e->>'distancia_km','')::numeric,
      NULLIF(v_e->>'fc_media','')::numeric,
      NULLIF(v_e->>'fc_max','')::numeric,
      COALESCE(NULLIF(v_e->>'fuente',''), 'apple_health')
    )
    ON CONFLICT (cliente_id, inicio, tipo) DO UPDATE SET
      -- Se refresca porque Apple completa kcal/FC minutos después de terminar:
      -- la primera lectura suele venir incompleta.
      fin          = COALESCE(EXCLUDED.fin,          mypump_entrenos_health.fin),
      duracion_min = COALESCE(EXCLUDED.duracion_min, mypump_entrenos_health.duracion_min),
      kcal         = COALESCE(EXCLUDED.kcal,         mypump_entrenos_health.kcal),
      distancia_km = COALESCE(EXCLUDED.distancia_km, mypump_entrenos_health.distancia_km),
      fc_media     = COALESCE(EXCLUDED.fc_media,     mypump_entrenos_health.fc_media),
      fc_max       = COALESCE(EXCLUDED.fc_max,       mypump_entrenos_health.fc_max);

    v_n := v_n + 1;
  END LOOP;

  RETURN v_n;
END;
$$;

REVOKE ALL ON FUNCTION mypump_ingest_entrenos(text, jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION mypump_ingest_entrenos(text, jsonb) TO anon, authenticated;

-- ── 5. Lectura de entrenamientos para el cliente ───────────────────────
CREATE OR REPLACE FUNCTION mypump_get_entrenos_health(
  p_token text,
  p_dias  integer DEFAULT 30
) RETURNS TABLE (
  fecha date, inicio timestamptz, tipo text,
  duracion_min numeric, kcal numeric, distancia_km numeric,
  fc_media numeric, fc_max numeric
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_cliente text;
BEGIN
  SELECT cliente_id INTO v_cliente
  FROM mypump_tokens WHERE token = p_token AND revocado_en IS NULL;
  IF v_cliente IS NULL THEN RAISE EXCEPTION 'token invalido'; END IF;

  RETURN QUERY
  SELECT e.fecha, e.inicio, e.tipo, e.duracion_min, e.kcal,
         e.distancia_km, e.fc_media, e.fc_max
  FROM mypump_entrenos_health e
  WHERE e.cliente_id = v_cliente
    AND e.fecha >= current_date - LEAST(GREATEST(COALESCE(p_dias, 30), 1), 365)
  ORDER BY e.inicio DESC;
END;
$$;

REVOKE ALL ON FUNCTION mypump_get_entrenos_health(text, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION mypump_get_entrenos_health(text, integer) TO anon, authenticated;

-- ── 6. Gasto energético real (para ajustar la dieta con datos, no fórmula) ──
CREATE OR REPLACE FUNCTION mypump_get_gasto_real(
  p_token text,
  p_dias  integer DEFAULT 14
) RETURNS TABLE (
  dias_con_dato    integer,
  kcal_totales_med numeric,   -- mediana: un domingo de maratón no corre el número
  kcal_basales_med numeric,
  kcal_activas_med numeric,
  vs_estimado_pct  numeric    -- lo llena la app comparando con su TDEE de fórmula
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_cliente text; v_desde date;
BEGIN
  SELECT cliente_id INTO v_cliente
  FROM mypump_tokens WHERE token = p_token AND revocado_en IS NULL;
  IF v_cliente IS NULL THEN RAISE EXCEPTION 'token invalido'; END IF;

  v_desde := current_date - LEAST(GREATEST(COALESCE(p_dias, 14), 3), 90);

  RETURN QUERY
  WITH d AS (
    SELECT s.fecha,
           MAX(CASE WHEN s.tipo = 'kcal_totales' THEN s.valor END) AS tot,
           MAX(CASE WHEN s.tipo = 'kcal_basales' THEN s.valor END) AS bas,
           MAX(CASE WHEN s.tipo = 'kcal_activas' THEN s.valor END) AS act
    FROM mypump_salud_diaria s
    WHERE s.cliente_id = v_cliente AND s.fecha >= v_desde
    GROUP BY s.fecha
  )
  SELECT
    COUNT(*) FILTER (WHERE COALESCE(tot, bas + act) IS NOT NULL)::integer,
    -- Si el sensor no da el total, se reconstruye: basal + activas.
    ROUND(percentile_cont(0.5) WITHIN GROUP (ORDER BY COALESCE(tot, bas + act))::numeric, 0),
    ROUND(percentile_cont(0.5) WITHIN GROUP (ORDER BY bas)::numeric, 0),
    ROUND(percentile_cont(0.5) WITHIN GROUP (ORDER BY act)::numeric, 0),
    NULL::numeric
  FROM d;
END;
$$;

REVOKE ALL ON FUNCTION mypump_get_gasto_real(text, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION mypump_get_gasto_real(text, integer) TO anon, authenticated;

COMMENT ON FUNCTION mypump_get_gasto_real IS
  'Gasto energético MEDIDO por el dispositivo, en mediana de N días. Sirve '
  'para contrastar contra el TDEE de Mifflin-St Jeor: si difieren mucho, '
  'manda el medido.';
