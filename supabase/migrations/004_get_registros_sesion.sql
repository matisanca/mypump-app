-- ============================================================
-- 004 — RPC para recuperar registros de carga de una sesión
-- ============================================================
-- Permite al frontend de MyPump restaurar los valores exactos
-- (peso/reps/RIR) cargados en cada serie al recargar la página.
-- Columnas reales de mypump_registros_carga:
--   serie_numero, peso_kg, reps_realizadas, rir_real, notas
-- ============================================================

CREATE OR REPLACE FUNCTION mypump_get_registros_sesion(
  p_token     TEXT,
  p_sesion_id UUID
)
RETURNS SETOF mypump_registros_carga
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_cliente_id TEXT;
BEGIN
  -- Validar token
  v_cliente_id := mypump_get_cliente_id_from_token(p_token);
  IF v_cliente_id IS NULL THEN RETURN; END IF;

  -- Verificar que la sesión pertenece al cliente
  IF NOT EXISTS (
    SELECT 1 FROM mypump_sesiones
    WHERE id = p_sesion_id
      AND cliente_id = v_cliente_id
  ) THEN RETURN; END IF;

  -- Devolver todos los registros de la sesión, ordenados por ejercicio y serie
  RETURN QUERY
    SELECT *
    FROM mypump_registros_carga
    WHERE sesion_id  = p_sesion_id
      AND cliente_id = v_cliente_id
    ORDER BY ejercicio_id, serie_numero ASC;
END;
$$;

GRANT EXECUTE ON FUNCTION mypump_get_registros_sesion(TEXT, UUID) TO anon;
