-- =============================================================
-- 049 — Dos bugs que dejaban medio pipeline de salud muerto en silencio
--
-- BUG 1: cuatro funciones leen el cliente de `mypump_tokens`, UNA TABLA QUE NO
-- EXISTE. Los tokens viven en mypump_clientes (access_token / access_token_active).
-- Afectadas:
--     mypump_ingest_entrenos   → los entrenos de Apple NUNCA se guardaron
--     mypump_get_entrenos_health → el coach nunca los pudo ver
--     mypump_get_gasto_real    → el gasto real nunca se calculó
--     mypump_registrar_push    → NINGÚN iPhone quedó registrado para push
--
-- Las cuatro tiran `relation "mypump_tokens" does not exist` en la primera
-- línea. Del lado del cliente están todas envueltas en try/catch, así que el
-- síntoma visible era "no llega nada" — sin un error a la vista.
--
-- POR QUÉ NO SALTÓ AL APLICAR LAS MIGS 047/048: PostgreSQL no valida las
-- referencias a tablas dentro del cuerpo de una función plpgsql al crearla.
-- Se compila al primer uso. Las migraciones aplicaron limpias y rompieron
-- recién en producción, sin ruido.
--
-- BUG 2: mypump_salud_valor_plausible existe desde la mig 047 y NADIE LA LLAMA.
-- Se creó la función y no se enganchó al INSERT. Verificado mandando basura por
-- mypump_ingest_salud: entraron los 6 registros —
--     fc_reposo=0, fc_reposo=400, hrv_ms=0, peso_kg=825, spo2_pct=150, sueno_min=2000
--
-- No es cosmético. El motor de recuperación (mig 043) calcula z-scores contra
-- una media y un desvío de 60 días: un solo HRV en 0 o una FC en 400 corren el
-- baseline y ensucian el score de TODOS los días siguientes, sin que el número
-- se vea "roto" — se ve plausible y está mal, que es peor.
--
-- VERIFICACIÓN (la de abajo es la que encontró los dos bugs):
--   SELECT mypump_ingest_salud('<token>', '[{"fecha":"2026-07-21","tipo":"fc_reposo",
--          "valor":400,"unidad":"bpm","fuente":"apple_health"}]'::jsonb);
--   -- antes: 1   ahora: 0
--   SELECT mypump_ingest_entrenos('<token>', '[...]'::jsonb);
--   -- antes: ERROR relation "mypump_tokens"   ahora: 1
--
-- ROLLBACK: no hace falta. Todo es CREATE OR REPLACE de funciones; para volver
-- atrás se re-aplican las migs 047 y 048. No toca datos ni esquema.
-- =============================================================

-- ── BUG 2 ────────────────────────────────────────────────────
-- El chequeo va DESPUÉS del CHECK de la tabla y antes del INSERT. Los dos
-- filtros son distintos a propósito: el CHECK dice si el TIPO existe, esto dice
-- si el VALOR es de un ser humano vivo.
CREATE OR REPLACE FUNCTION _mypump_upsert_salud(
  p_cliente_id TEXT, p_registros JSONB, p_fuente_default TEXT
) RETURNS INTEGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_count  INTEGER := 0;
  v_rec    JSONB;
  v_tipo   TEXT;
  v_fuente TEXT;
  v_fecha  DATE;
  v_valor  NUMERIC;
BEGIN
  IF p_cliente_id IS NULL THEN RETURN 0; END IF;
  IF p_registros IS NULL OR jsonb_typeof(p_registros) <> 'array' THEN RETURN 0; END IF;

  FOR v_rec IN SELECT * FROM jsonb_array_elements(p_registros) LOOP
    v_tipo   := v_rec->>'tipo';
    v_fuente := COALESCE(v_rec->>'fuente', p_fuente_default);
    IF v_tipo IS NULL OR v_fuente IS NULL THEN CONTINUE; END IF;

    BEGIN
      v_fecha := (v_rec->>'fecha')::DATE;
      v_valor := (v_rec->>'valor')::NUMERIC;
    EXCEPTION WHEN OTHERS THEN CONTINUE;  -- fecha/valor mal formados → saltar
    END;
    IF v_fecha IS NULL OR v_valor IS NULL THEN CONTINUE; END IF;

    -- Un sensor que se despega, un reloj que se resetea o un dedo que erra el
    -- teclado meten valores imposibles. Entran callados y arruinan el baseline
    -- del motor de recuperación, que es lo caro: el score de los 60 días
    -- siguientes queda corrido y sigue pareciendo un número normal.
    CONTINUE WHEN NOT mypump_salud_valor_plausible(v_tipo, v_valor);

    -- Sin lista hardcodeada: si el tipo o la fuente no pasan el CHECK de la
    -- tabla, el INSERT tira check_violation y se saltea ESE registro sin
    -- abortar el lote.
    BEGIN
      INSERT INTO mypump_salud_diaria (cliente_id, fecha, tipo, valor, detalle, fuente)
      VALUES (p_cliente_id, v_fecha, v_tipo, v_valor,
              CASE WHEN jsonb_typeof(v_rec->'detalle') IS NOT NULL THEN v_rec->'detalle' ELSE NULL END,
              v_fuente)
      ON CONFLICT (cliente_id, fecha, tipo, fuente) DO UPDATE
        SET valor = EXCLUDED.valor, detalle = EXCLUDED.detalle, updated_at = NOW();
      v_count := v_count + 1;
    EXCEPTION WHEN check_violation THEN CONTINUE;
    END;
  END LOOP;

  RETURN v_count;
END;
$$;

-- ── BUG 1 ────────────────────────────────────────────────────
-- mypump_get_cliente_id_from_token() es el helper que YA usaban las funciones
-- viejas (mypump_ingest_salud, por ejemplo) y el único que sabe dónde viven de
-- verdad los tokens. Las cuatro de abajo pasan a usarlo.

CREATE OR REPLACE FUNCTION mypump_ingest_entrenos(p_token TEXT, p_entrenos JSONB)
RETURNS INTEGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_cliente text;
  v_e       jsonb;
  v_n       integer := 0;
  v_inicio  timestamptz;
  v_tipo    text;
BEGIN
  v_cliente := mypump_get_cliente_id_from_token(p_token);
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
    -- Nada del futuro ni de hace mas de 2 anos.
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
      -- Se refresca porque Apple completa kcal/FC minutos despues de terminar:
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

CREATE OR REPLACE FUNCTION mypump_get_entrenos_health(p_token TEXT, p_dias INTEGER DEFAULT 30)
RETURNS TABLE(fecha date, inicio timestamptz, tipo text, duracion_min numeric,
              kcal numeric, distancia_km numeric, fc_media numeric, fc_max numeric)
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_cliente text;
BEGIN
  v_cliente := mypump_get_cliente_id_from_token(p_token);
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

CREATE OR REPLACE FUNCTION mypump_get_gasto_real(p_token TEXT, p_dias INTEGER DEFAULT 14)
RETURNS TABLE(dias_con_dato integer, kcal_totales_med numeric, kcal_basales_med numeric,
              kcal_activas_med numeric, vs_estimado_pct numeric)
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_cliente text; v_desde date;
BEGIN
  v_cliente := mypump_get_cliente_id_from_token(p_token);
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

CREATE OR REPLACE FUNCTION mypump_registrar_push(
  p_token TEXT, p_device TEXT, p_plataforma TEXT DEFAULT 'ios', p_app_version TEXT DEFAULT NULL
) RETURNS BOOLEAN
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_cliente text;
BEGIN
  v_cliente := mypump_get_cliente_id_from_token(p_token);
  IF v_cliente IS NULL THEN RAISE EXCEPTION 'token invalido'; END IF;
  IF p_device IS NULL OR length(trim(p_device)) < 32 THEN RETURN false; END IF;

  INSERT INTO mypump_push_devices (cliente_id, token, plataforma, app_version)
  VALUES (v_cliente, trim(p_device), COALESCE(p_plataforma,'ios'), p_app_version)
  ON CONFLICT (token) DO UPDATE SET
    -- Si el mismo device pasa a otro cliente (prestó el teléfono, se re-vinculó),
    -- el token de APNs sigue siendo el mismo: hay que reasignarlo, no duplicar.
    cliente_id  = EXCLUDED.cliente_id,
    activo      = true,
    ultimo_error = NULL,
    app_version = COALESCE(EXCLUDED.app_version, mypump_push_devices.app_version),
    visto_en    = now();
  RETURN true;
END;
$$;

-- ── Permisos ─────────────────────────────────────────────────
-- CREATE OR REPLACE conserva el ACL (a diferencia de DROP + CREATE, que lo
-- resetea a PUBLIC). Se re-aplica igual: es barato y ya nos pasó una vez que
-- una migración reabriera lo que otra había cerrado.
REVOKE ALL ON FUNCTION _mypump_upsert_salud(TEXT, JSONB, TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION _mypump_upsert_salud(TEXT, JSONB, TEXT) TO service_role;

GRANT EXECUTE ON FUNCTION mypump_ingest_entrenos(TEXT, JSONB)        TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION mypump_get_entrenos_health(TEXT, INTEGER)  TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION mypump_get_gasto_real(TEXT, INTEGER)       TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION mypump_registrar_push(TEXT, TEXT, TEXT, TEXT) TO anon, authenticated, service_role;

-- Auditoría: ninguna función de salud debería quedar con proacl NULL (= abierta
-- a PUBLIC por default de Postgres).
--   SELECT proname FROM pg_proc
--    WHERE proname LIKE 'mypump%salud%' AND proacl IS NULL;
