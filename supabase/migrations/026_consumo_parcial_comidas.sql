-- ============================================================
-- 026 — Consumo PARCIAL de comidas
-- ============================================================
-- Hoy marcar "Comí" cuenta TODA la comida aunque el cliente comió solo una
-- parte (ej: comió los huevos pero no el pan). Agregamos foods_excluidos: un
-- array JSONB con los ÍNDICES de los alimentos que NO comió (dentro de la
-- opción marcada). NULL/[] = comió todo (retrocompatible: registros viejos y
-- el flujo "Comí todo" no guardan nada y siguen contando la comida completa).
-- ============================================================

ALTER TABLE mypump_comidas_marcadas
  ADD COLUMN IF NOT EXISTS foods_excluidos JSONB;

-- Reemplaza el RPC con un parámetro opcional p_foods_excluidos.
-- (Se dropea la firma de 5 args para no dejar overloads ambiguos.)
DROP FUNCTION IF EXISTS mypump_marcar_comida(TEXT, DATE, TEXT, TEXT, TEXT);

CREATE OR REPLACE FUNCTION mypump_marcar_comida(
  p_token           TEXT,
  p_fecha           DATE,
  p_comida_id       TEXT,
  p_opcion          TEXT,
  p_estado          TEXT,
  p_foods_excluidos JSONB DEFAULT NULL
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
    (cliente_id, fecha, comida_id, opcion_elegida, estado, foods_excluidos)
  VALUES
    (v_cliente_id, p_fecha, p_comida_id, p_opcion, p_estado,
     -- Un array vacío se guarda como NULL (comió todo).
     CASE WHEN p_foods_excluidos IS NOT NULL
               AND jsonb_typeof(p_foods_excluidos) = 'array'
               AND jsonb_array_length(p_foods_excluidos) > 0
          THEN p_foods_excluidos ELSE NULL END)
  ON CONFLICT (cliente_id, fecha, comida_id) DO UPDATE
    SET opcion_elegida  = EXCLUDED.opcion_elegida,
        estado          = EXCLUDED.estado,
        foods_excluidos = EXCLUDED.foods_excluidos,
        marcada_en      = NOW(),
        updated_at      = NOW();

  RETURN QUERY
    SELECT * FROM mypump_comidas_marcadas
    WHERE cliente_id = v_cliente_id
      AND fecha      = p_fecha
      AND comida_id  = p_comida_id;
END;
$$;

GRANT EXECUTE ON FUNCTION mypump_marcar_comida(TEXT, DATE, TEXT, TEXT, TEXT, JSONB)
  TO anon, authenticated, service_role;
