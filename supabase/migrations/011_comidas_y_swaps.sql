-- ============================================================
-- 011 — Tracking de comidas + persistencia de food swaps + custom foods
-- ============================================================
-- Tres features nuevas, una sola migration:
--
-- 1) mypump_comidas_marcadas: marcar qué comió el cliente en el día
--    (granular por comida, no binario como mypump_habitos_diarios)
--
-- 2) mypump_food_swaps: persistir sustituciones de alimentos en backend
--    para que sobrevivan cambio de device / cache (antes solo localStorage)
--
-- 3) mypump_custom_foods: alimentos personalizados creados por el cliente
--    (cuando un alimento no está en MYPUMP_FOOD_DB)
-- ============================================================

-- ============================================================
-- TABLA 1: mypump_comidas_marcadas
-- ============================================================
CREATE TABLE IF NOT EXISTS mypump_comidas_marcadas (
  id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  cliente_id      TEXT        NOT NULL,
  fecha           DATE        NOT NULL,
  comida_id       TEXT        NOT NULL,           -- 'c1','c2',... del JSONB
  opcion_elegida  TEXT        NOT NULL,           -- 'A','B',... opción al momento de marcar
  estado          TEXT        NOT NULL
                  CHECK (estado IN ('comido','saltado')),
  marcada_en      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  UNIQUE (cliente_id, fecha, comida_id)
);

CREATE INDEX IF NOT EXISTS idx_mypump_comidas_marcadas_cliente_fecha
  ON mypump_comidas_marcadas (cliente_id, fecha DESC);

ALTER TABLE mypump_comidas_marcadas ENABLE ROW LEVEL SECURITY;

CREATE POLICY "admin all mypump_comidas_marcadas"
  ON mypump_comidas_marcadas FOR ALL
  USING (auth.role() = 'authenticated')
  WITH CHECK (auth.role() = 'authenticated');

-- ============================================================
-- TABLA 2: mypump_food_swaps
-- ============================================================
CREATE TABLE IF NOT EXISTS mypump_food_swaps (
  id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  cliente_id   TEXT        NOT NULL,
  dieta_id     UUID        NOT NULL REFERENCES mypump_dietas(id) ON DELETE CASCADE,
  comida_id    TEXT        NOT NULL,
  opt_idx      INTEGER     NOT NULL,
  food_idx     INTEGER     NOT NULL,
  food_data    JSONB       NOT NULL,   -- {name, qty, unit, kcal, prot, carb, fat, category}
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  UNIQUE (cliente_id, dieta_id, comida_id, opt_idx, food_idx)
);

CREATE INDEX IF NOT EXISTS idx_mypump_food_swaps_cliente_dieta
  ON mypump_food_swaps (cliente_id, dieta_id);

ALTER TABLE mypump_food_swaps ENABLE ROW LEVEL SECURITY;

CREATE POLICY "admin all mypump_food_swaps"
  ON mypump_food_swaps FOR ALL
  USING (auth.role() = 'authenticated')
  WITH CHECK (auth.role() = 'authenticated');

-- ============================================================
-- TABLA 3: mypump_custom_foods
-- ============================================================
CREATE TABLE IF NOT EXISTS mypump_custom_foods (
  id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  cliente_id  TEXT        NOT NULL,
  name        TEXT        NOT NULL,
  kcal        NUMERIC     NOT NULL CHECK (kcal >= 0),
  prot        NUMERIC     NOT NULL CHECK (prot >= 0),
  carb        NUMERIC     NOT NULL CHECK (carb >= 0),
  fat         NUMERIC     NOT NULL CHECK (fat >= 0),
  unit        TEXT        NOT NULL DEFAULT 'g',
  unit_grams  NUMERIC,                       -- NULL si unit='g'/'ml'
  category    TEXT        CHECK (category IN
              ('proteina','carbohidrato','grasa','lacteo','fruta_verdura','mixto','condimento')),
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  UNIQUE (cliente_id, name)
);

CREATE INDEX IF NOT EXISTS idx_mypump_custom_foods_cliente
  ON mypump_custom_foods (cliente_id);

ALTER TABLE mypump_custom_foods ENABLE ROW LEVEL SECURITY;

CREATE POLICY "admin all mypump_custom_foods"
  ON mypump_custom_foods FOR ALL
  USING (auth.role() = 'authenticated')
  WITH CHECK (auth.role() = 'authenticated');

-- ============================================================
-- RPCs — Tracking de comidas
-- ============================================================

CREATE OR REPLACE FUNCTION mypump_marcar_comida(
  p_token     TEXT,
  p_fecha     DATE,
  p_comida_id TEXT,
  p_opcion    TEXT,
  p_estado    TEXT
)
RETURNS SETOF mypump_comidas_marcadas
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_cliente_id TEXT;
  v_hoy        DATE;
BEGIN
  v_cliente_id := mypump_get_cliente_id_from_token(p_token);
  IF v_cliente_id IS NULL THEN RETURN; END IF;

  IF p_estado NOT IN ('comido','saltado') THEN
    RAISE EXCEPTION 'Estado inválido: %', p_estado;
  END IF;

  v_hoy := (NOW() AT TIME ZONE 'America/Argentina/Buenos_Aires')::DATE;
  IF p_fecha > v_hoy THEN
    RAISE EXCEPTION 'No se puede marcar una fecha futura';
  END IF;
  IF p_fecha < v_hoy - 2 THEN
    RAISE EXCEPTION 'Solo se permite backfill de hasta 2 días';
  END IF;

  INSERT INTO mypump_comidas_marcadas
    (cliente_id, fecha, comida_id, opcion_elegida, estado)
  VALUES
    (v_cliente_id, p_fecha, p_comida_id, p_opcion, p_estado)
  ON CONFLICT (cliente_id, fecha, comida_id) DO UPDATE
    SET opcion_elegida = EXCLUDED.opcion_elegida,
        estado         = EXCLUDED.estado,
        marcada_en     = NOW(),
        updated_at     = NOW();

  RETURN QUERY
    SELECT * FROM mypump_comidas_marcadas
    WHERE cliente_id = v_cliente_id
      AND fecha      = p_fecha
      AND comida_id  = p_comida_id;
END;
$$;

GRANT EXECUTE ON FUNCTION mypump_marcar_comida(TEXT, DATE, TEXT, TEXT, TEXT) TO anon;

CREATE OR REPLACE FUNCTION mypump_get_comidas_marcadas(
  p_token TEXT,
  p_fecha DATE
)
RETURNS SETOF mypump_comidas_marcadas
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
    SELECT * FROM mypump_comidas_marcadas
    WHERE cliente_id = v_cliente_id
      AND fecha      = p_fecha
    ORDER BY comida_id;
END;
$$;

GRANT EXECUTE ON FUNCTION mypump_get_comidas_marcadas(TEXT, DATE) TO anon;

CREATE OR REPLACE FUNCTION mypump_desmarcar_comida(
  p_token     TEXT,
  p_fecha     DATE,
  p_comida_id TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_cliente_id TEXT;
  v_hoy        DATE;
  v_deleted    INTEGER;
BEGIN
  v_cliente_id := mypump_get_cliente_id_from_token(p_token);
  IF v_cliente_id IS NULL THEN RETURN FALSE; END IF;

  v_hoy := (NOW() AT TIME ZONE 'America/Argentina/Buenos_Aires')::DATE;
  IF p_fecha < v_hoy - 2 OR p_fecha > v_hoy THEN
    RAISE EXCEPTION 'Fecha fuera de rango permitido';
  END IF;

  DELETE FROM mypump_comidas_marcadas
  WHERE cliente_id = v_cliente_id
    AND fecha      = p_fecha
    AND comida_id  = p_comida_id;

  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  RETURN v_deleted > 0;
END;
$$;

GRANT EXECUTE ON FUNCTION mypump_desmarcar_comida(TEXT, DATE, TEXT) TO anon;

-- ============================================================
-- RPCs — Food swaps (persistencia backend)
-- ============================================================

CREATE OR REPLACE FUNCTION mypump_save_food_swap(
  p_token     TEXT,
  p_dieta_id  UUID,
  p_comida_id TEXT,
  p_opt_idx   INTEGER,
  p_food_idx  INTEGER,
  p_food_data JSONB
)
RETURNS SETOF mypump_food_swaps
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_cliente_id TEXT;
BEGIN
  v_cliente_id := mypump_get_cliente_id_from_token(p_token);
  IF v_cliente_id IS NULL THEN RETURN; END IF;

  -- Validar que la dieta pertenezca al cliente (defensa en profundidad)
  IF NOT EXISTS (SELECT 1 FROM mypump_dietas
                 WHERE id = p_dieta_id AND cliente_id = v_cliente_id) THEN
    RAISE EXCEPTION 'Dieta no encontrada o no pertenece al cliente';
  END IF;

  INSERT INTO mypump_food_swaps
    (cliente_id, dieta_id, comida_id, opt_idx, food_idx, food_data)
  VALUES
    (v_cliente_id, p_dieta_id, p_comida_id, p_opt_idx, p_food_idx, p_food_data)
  ON CONFLICT (cliente_id, dieta_id, comida_id, opt_idx, food_idx) DO UPDATE
    SET food_data  = EXCLUDED.food_data,
        updated_at = NOW();

  RETURN QUERY
    SELECT * FROM mypump_food_swaps
    WHERE cliente_id = v_cliente_id
      AND dieta_id   = p_dieta_id
      AND comida_id  = p_comida_id
      AND opt_idx    = p_opt_idx
      AND food_idx   = p_food_idx;
END;
$$;

GRANT EXECUTE ON FUNCTION mypump_save_food_swap(TEXT, UUID, TEXT, INTEGER, INTEGER, JSONB) TO anon;

CREATE OR REPLACE FUNCTION mypump_delete_food_swap(
  p_token     TEXT,
  p_dieta_id  UUID,
  p_comida_id TEXT,
  p_opt_idx   INTEGER,
  p_food_idx  INTEGER
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_cliente_id TEXT;
  v_deleted    INTEGER;
BEGIN
  v_cliente_id := mypump_get_cliente_id_from_token(p_token);
  IF v_cliente_id IS NULL THEN RETURN FALSE; END IF;

  DELETE FROM mypump_food_swaps
  WHERE cliente_id = v_cliente_id
    AND dieta_id   = p_dieta_id
    AND comida_id  = p_comida_id
    AND opt_idx    = p_opt_idx
    AND food_idx   = p_food_idx;

  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  RETURN v_deleted > 0;
END;
$$;

GRANT EXECUTE ON FUNCTION mypump_delete_food_swap(TEXT, UUID, TEXT, INTEGER, INTEGER) TO anon;

CREATE OR REPLACE FUNCTION mypump_get_food_swaps(
  p_token    TEXT,
  p_dieta_id UUID
)
RETURNS SETOF mypump_food_swaps
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
    SELECT * FROM mypump_food_swaps
    WHERE cliente_id = v_cliente_id
      AND dieta_id   = p_dieta_id
    ORDER BY comida_id, opt_idx, food_idx;
END;
$$;

GRANT EXECUTE ON FUNCTION mypump_get_food_swaps(TEXT, UUID) TO anon;

-- ============================================================
-- RPCs — Custom foods
-- ============================================================

CREATE OR REPLACE FUNCTION mypump_create_custom_food(
  p_token       TEXT,
  p_name        TEXT,
  p_kcal        NUMERIC,
  p_prot        NUMERIC,
  p_carb        NUMERIC,
  p_fat         NUMERIC,
  p_unit        TEXT,
  p_unit_grams  NUMERIC,
  p_category    TEXT
)
RETURNS SETOF mypump_custom_foods
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_cliente_id TEXT;
  v_name       TEXT;
BEGIN
  v_cliente_id := mypump_get_cliente_id_from_token(p_token);
  IF v_cliente_id IS NULL THEN RETURN; END IF;

  v_name := trim(p_name);
  IF v_name = '' THEN
    RAISE EXCEPTION 'El nombre del alimento es obligatorio';
  END IF;

  -- Validar unit
  IF p_unit NOT IN ('g','ml','unidad','rebanada','taza','cucharada','cucharadita','porcion') THEN
    RAISE EXCEPTION 'Unidad inválida: %', p_unit;
  END IF;

  -- Si unit no es g/ml, exigir unit_grams > 0
  IF p_unit NOT IN ('g','ml') AND (p_unit_grams IS NULL OR p_unit_grams <= 0) THEN
    RAISE EXCEPTION 'Para unidad "%" debés indicar gramos por unidad', p_unit;
  END IF;

  INSERT INTO mypump_custom_foods
    (cliente_id, name, kcal, prot, carb, fat, unit, unit_grams, category)
  VALUES
    (v_cliente_id, v_name, p_kcal, p_prot, p_carb, p_fat, p_unit, p_unit_grams, p_category)
  ON CONFLICT (cliente_id, name) DO UPDATE
    SET kcal       = EXCLUDED.kcal,
        prot       = EXCLUDED.prot,
        carb       = EXCLUDED.carb,
        fat        = EXCLUDED.fat,
        unit       = EXCLUDED.unit,
        unit_grams = EXCLUDED.unit_grams,
        category   = EXCLUDED.category;

  RETURN QUERY
    SELECT * FROM mypump_custom_foods
    WHERE cliente_id = v_cliente_id AND name = v_name;
END;
$$;

GRANT EXECUTE ON FUNCTION mypump_create_custom_food(TEXT, TEXT, NUMERIC, NUMERIC, NUMERIC, NUMERIC, TEXT, NUMERIC, TEXT) TO anon;

CREATE OR REPLACE FUNCTION mypump_get_custom_foods(p_token TEXT)
RETURNS SETOF mypump_custom_foods
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
    SELECT * FROM mypump_custom_foods
    WHERE cliente_id = v_cliente_id
    ORDER BY name;
END;
$$;

GRANT EXECUTE ON FUNCTION mypump_get_custom_foods(TEXT) TO anon;
