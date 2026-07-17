-- ============================================================
-- 033 — Comidas LIBRES (foto del plato / registro manual) — F10
-- ============================================================
-- El cliente registra una comida FUERA del plan (foto del plato → estimación
-- con IA, o carga manual). Se suma al balance calórico del día junto a las
-- comidas del plan. Todo editable/borrable por el cliente.
--
-- ⚠ Ventana de fecha TOLERANTE (+1 futuro / -7 backfill) como TODA RPC que
-- recibe fecha local del cliente (regla timezone: un cliente en España tiene
-- su "hoy" adelantado vs Argentina; NUNCA validar p_fecha > v_hoy estricto).
-- ============================================================

CREATE TABLE IF NOT EXISTS mypump_comidas_libres (
  id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  cliente_id  TEXT        NOT NULL,
  fecha       DATE        NOT NULL,
  hora        TIME,
  descripcion TEXT        NOT NULL,
  kcal        NUMERIC     NOT NULL DEFAULT 0,
  prot        NUMERIC     NOT NULL DEFAULT 0,
  carb        NUMERIC     NOT NULL DEFAULT 0,
  fat         NUMERIC     NOT NULL DEFAULT 0,
  detalle     JSONB,               -- alimentos detectados por la IA (editables)
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_mypump_comidas_libres_cliente_fecha
  ON mypump_comidas_libres (cliente_id, fecha DESC);

ALTER TABLE mypump_comidas_libres ENABLE ROW LEVEL SECURITY;

CREATE POLICY "admin all mypump_comidas_libres"
  ON mypump_comidas_libres FOR ALL
  USING (auth.role() = 'authenticated')
  WITH CHECK (auth.role() = 'authenticated');

-- ── RPC 1: crear ──
CREATE OR REPLACE FUNCTION mypump_crear_comida_libre(
  p_token       TEXT,
  p_fecha       DATE,
  p_hora        TIME,
  p_descripcion TEXT,
  p_kcal        NUMERIC,
  p_prot        NUMERIC,
  p_carb        NUMERIC,
  p_fat         NUMERIC,
  p_detalle     JSONB DEFAULT NULL
)
RETURNS SETOF mypump_comidas_libres
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_cliente_id TEXT;
  v_hoy        DATE;
  v_id         UUID;
BEGIN
  v_cliente_id := mypump_get_cliente_id_from_token(p_token);
  IF v_cliente_id IS NULL THEN RETURN; END IF;

  IF p_descripcion IS NULL OR length(trim(p_descripcion)) = 0 THEN
    RAISE EXCEPTION 'Falta la descripción';
  END IF;

  -- Ventana tolerante a zona horaria/reloj del device (regla 020/028).
  v_hoy := (NOW() AT TIME ZONE 'America/Argentina/Buenos_Aires')::DATE;
  IF p_fecha > v_hoy + 1 THEN
    RAISE EXCEPTION 'No se puede registrar una fecha futura';
  END IF;
  IF p_fecha < v_hoy - 7 THEN
    RAISE EXCEPTION 'Solo se permite backfill de hasta 7 días';
  END IF;

  INSERT INTO mypump_comidas_libres
    (cliente_id, fecha, hora, descripcion, kcal, prot, carb, fat, detalle)
  VALUES
    (v_cliente_id, p_fecha, p_hora, trim(p_descripcion),
     GREATEST(0, COALESCE(p_kcal, 0)), GREATEST(0, COALESCE(p_prot, 0)),
     GREATEST(0, COALESCE(p_carb, 0)), GREATEST(0, COALESCE(p_fat, 0)),
     p_detalle)
  RETURNING id INTO v_id;

  RETURN QUERY SELECT * FROM mypump_comidas_libres WHERE id = v_id;
END;
$$;

GRANT EXECUTE ON FUNCTION mypump_crear_comida_libre(TEXT, DATE, TIME, TEXT, NUMERIC, NUMERIC, NUMERIC, NUMERIC, JSONB)
  TO anon, authenticated, service_role;

-- ── RPC 2: listar por fecha ──
CREATE OR REPLACE FUNCTION mypump_get_comidas_libres(
  p_token TEXT,
  p_fecha DATE
)
RETURNS SETOF mypump_comidas_libres
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
    SELECT * FROM mypump_comidas_libres
    WHERE cliente_id = v_cliente_id AND fecha = p_fecha
    ORDER BY hora NULLS LAST, created_at;
END;
$$;

GRANT EXECUTE ON FUNCTION mypump_get_comidas_libres(TEXT, DATE) TO anon, authenticated;

-- ── RPC 3: borrar ──
CREATE OR REPLACE FUNCTION mypump_borrar_comida_libre(
  p_token TEXT,
  p_id    UUID
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_cliente_id TEXT;
  v_rows       INTEGER;
BEGIN
  v_cliente_id := mypump_get_cliente_id_from_token(p_token);
  IF v_cliente_id IS NULL THEN RETURN FALSE; END IF;

  DELETE FROM mypump_comidas_libres
  WHERE id = p_id AND cliente_id = v_cliente_id;

  GET DIAGNOSTICS v_rows = ROW_COUNT;
  RETURN v_rows > 0;
END;
$$;

GRANT EXECUTE ON FUNCTION mypump_borrar_comida_libre(TEXT, UUID) TO anon, authenticated;

-- ============================================================
-- ROLLBACK (revierte esta migración por completo):
--
-- DROP FUNCTION IF EXISTS mypump_borrar_comida_libre(TEXT, UUID);
-- DROP FUNCTION IF EXISTS mypump_get_comidas_libres(TEXT, DATE);
-- DROP FUNCTION IF EXISTS mypump_crear_comida_libre(TEXT, DATE, TIME, TEXT, NUMERIC, NUMERIC, NUMERIC, NUMERIC, JSONB);
-- DROP TABLE IF EXISTS mypump_comidas_libres;
-- ============================================================
