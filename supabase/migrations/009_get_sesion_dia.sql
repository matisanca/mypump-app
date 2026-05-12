-- ============================================================
-- 009 — Reconectar sesión existente desde el servidor
-- ============================================================
-- Bug: cuando el cliente pierde localStorage (cambio de dispositivo,
-- modo incógnito, limpieza de cache, o retroceso manual de semana
-- desde admin), la app crea una sesión vacía nueva en vez de reconectar
-- con la sesión real que ya tiene cargada en el servidor.
--
-- Esta RPC devuelve la sesión más reciente para (cliente, dia, semana).
-- El frontend la llama al iniciar la app si no encuentra sesión local.
-- ============================================================

CREATE OR REPLACE FUNCTION mypump_get_sesion_dia(
  p_token   TEXT,
  p_dia_id  TEXT,
  p_semana  INTEGER
)
RETURNS TABLE (
  id            UUID,
  dia_id        TEXT,
  semana        INTEGER,
  iniciada_en   TIMESTAMPTZ,
  finalizada_en TIMESTAMPTZ
)
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
    SELECT s.id, s.dia_id, s.semana, s.iniciada_en, s.finalizada_en
    FROM mypump_sesiones s
    WHERE s.cliente_id = v_cliente_id
      AND s.dia_id     = p_dia_id
      AND s.semana     = p_semana
    ORDER BY s.iniciada_en DESC
    LIMIT 1;
END;
$$;

GRANT EXECUTE ON FUNCTION mypump_get_sesion_dia(TEXT, TEXT, INTEGER) TO anon;
