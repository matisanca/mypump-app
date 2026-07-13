-- ============================================================
-- 027 — Salud diaria (wearables / Apple Health) — pipeline AGNÓSTICO
-- ============================================================
-- Destino ÚNICO para datos de salud, sin importar la fuente:
--   · apple_health → el plugin nativo (Capacitor/HealthKit) llama
--     mypump_ingest_salud(p_token, p_registros) directo (anon + token),
--     igual que el resto de escrituras del cliente.
--   · rook / agregador → el webhook pega en la Cloudflare Pages Function
--     functions/api/salud.js, que valida un secreto compartido y llama
--     mypump_ingest_salud_service(p_cliente_id, p_registros) (service_role).
--   · manual → carga a mano (futuro).
-- Una fila por (cliente, fecha, tipo, fuente): idempotente (upsert), así
-- reenviar el mismo día no duplica. El coach puede leer por cliente en Cerebro.
-- ============================================================

-- TABLA
CREATE TABLE IF NOT EXISTS mypump_salud_diaria (
  id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  cliente_id  TEXT        NOT NULL,
  fecha       DATE        NOT NULL,
  tipo        TEXT        NOT NULL
              CHECK (tipo IN ('pasos','actividad_min','kcal_activas','fc_reposo','sueno_min','peso_kg')),
  valor       NUMERIC     NOT NULL,
  detalle     JSONB,                                  -- opcional: rangos, device, etc.
  fuente      TEXT        NOT NULL DEFAULT 'manual'
              CHECK (fuente IN ('apple_health','rook','manual')),
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (cliente_id, fecha, tipo, fuente)
);

CREATE INDEX IF NOT EXISTS idx_mypump_salud_cliente_fecha
  ON mypump_salud_diaria (cliente_id, fecha DESC);

-- RLS: anon solo vía RPCs SECURITY DEFINER
ALTER TABLE mypump_salud_diaria ENABLE ROW LEVEL SECURITY;

CREATE POLICY "admin all mypump_salud_diaria"
  ON mypump_salud_diaria FOR ALL
  USING (auth.role() = 'authenticated')
  WITH CHECK (auth.role() = 'authenticated');

-- ============================================================
-- Helper interno: upsertea un array JSONB de registros para un cliente.
-- Cada registro: {fecha, tipo, valor, detalle?, fuente?}. Los inválidos se
-- saltan (no abortan el lote). Devuelve la cantidad ingresada.
-- ============================================================
CREATE OR REPLACE FUNCTION _mypump_upsert_salud(
  p_cliente_id     TEXT,
  p_registros      JSONB,
  p_fuente_default TEXT
)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
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
    -- Validar contra los CHECK antes de insertar (saltear registros basura).
    IF v_tipo   NOT IN ('pasos','actividad_min','kcal_activas','fc_reposo','sueno_min','peso_kg') THEN CONTINUE; END IF;
    IF v_fuente NOT IN ('apple_health','rook','manual') THEN CONTINUE; END IF;
    BEGIN
      v_fecha := (v_rec->>'fecha')::DATE;
      v_valor := (v_rec->>'valor')::NUMERIC;
    EXCEPTION WHEN OTHERS THEN CONTINUE;  -- fecha/valor mal formados → saltar
    END;
    IF v_fecha IS NULL OR v_valor IS NULL THEN CONTINUE; END IF;

    INSERT INTO mypump_salud_diaria (cliente_id, fecha, tipo, valor, detalle, fuente)
    VALUES (p_cliente_id, v_fecha, v_tipo, v_valor,
            CASE WHEN jsonb_typeof(v_rec->'detalle') IS NOT NULL THEN v_rec->'detalle' ELSE NULL END,
            v_fuente)
    ON CONFLICT (cliente_id, fecha, tipo, fuente) DO UPDATE
      SET valor = EXCLUDED.valor, detalle = EXCLUDED.detalle, updated_at = NOW();
    v_count := v_count + 1;
  END LOOP;

  RETURN v_count;
END;
$$;

-- ============================================================
-- RPC 1: ingesta por TOKEN (Vía B — plugin nativo Apple Health).
-- fuente por defecto 'apple_health'. Anon-callable como el resto.
-- ============================================================
CREATE OR REPLACE FUNCTION mypump_ingest_salud(
  p_token     TEXT,
  p_registros JSONB
)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_cliente_id TEXT;
BEGIN
  v_cliente_id := mypump_get_cliente_id_from_token(p_token);
  IF v_cliente_id IS NULL THEN RETURN 0; END IF;
  RETURN _mypump_upsert_salud(v_cliente_id, p_registros, 'apple_health');
END;
$$;

GRANT EXECUTE ON FUNCTION mypump_ingest_salud(TEXT, JSONB) TO anon, authenticated;

-- ============================================================
-- RPC 2: ingesta por CLIENTE_ID (Vía A — agregador Rook).
-- La llama SOLO functions/api/salud.js con la service_role key, tras validar
-- el secreto compartido. fuente por defecto 'rook'.
-- ============================================================
CREATE OR REPLACE FUNCTION mypump_ingest_salud_service(
  p_cliente_id TEXT,
  p_registros  JSONB
)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN _mypump_upsert_salud(p_cliente_id, p_registros, 'rook');
END;
$$;

GRANT EXECUTE ON FUNCTION mypump_ingest_salud_service(TEXT, JSONB) TO service_role;

-- ============================================================
-- RPC 3: leer salud del cliente en un rango (para la card "Salud" de Mi Día).
-- Si hay varias fuentes para el mismo (fecha,tipo) devuelve todas; el frontend
-- prioriza. Anon + token.
-- ============================================================
CREATE OR REPLACE FUNCTION mypump_get_salud(
  p_token TEXT,
  p_desde DATE,
  p_hasta DATE
)
RETURNS TABLE (fecha DATE, tipo TEXT, valor NUMERIC, fuente TEXT, detalle JSONB)
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
    SELECT s.fecha, s.tipo, s.valor, s.fuente, s.detalle
    FROM mypump_salud_diaria s
    WHERE s.cliente_id = v_cliente_id
      AND s.fecha BETWEEN p_desde AND p_hasta
    ORDER BY s.fecha DESC, s.tipo;
END;
$$;

GRANT EXECUTE ON FUNCTION mypump_get_salud(TEXT, DATE, DATE) TO anon, authenticated;

-- ============================================================
-- RPC 4 (admin): salud de todos los clientes últimos N días (Cerebro).
-- Solo authenticated. Para sumar al análisis del macrociclo más adelante.
-- ============================================================
CREATE OR REPLACE FUNCTION mypump_get_salud_global(p_dias INTEGER DEFAULT 14)
RETURNS TABLE (cliente_id TEXT, nombre TEXT, fecha DATE, tipo TEXT, valor NUMERIC, fuente TEXT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_hoy DATE;
BEGIN
  IF auth.role() <> 'authenticated' THEN
    RAISE EXCEPTION 'Acceso denegado';
  END IF;
  v_hoy := (NOW() AT TIME ZONE 'America/Argentina/Buenos_Aires')::DATE;

  RETURN QUERY
    SELECT s.cliente_id, c.nombre, s.fecha, s.tipo, s.valor, s.fuente
    FROM mypump_salud_diaria s
    JOIN mypump_clientes c ON c.cliente_id = s.cliente_id
    WHERE s.fecha >= v_hoy - GREATEST(1, p_dias)
    ORDER BY c.nombre, s.fecha DESC, s.tipo;
END;
$$;

GRANT EXECUTE ON FUNCTION mypump_get_salud_global(INTEGER) TO authenticated;
