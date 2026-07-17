-- ============================================================
-- 031 — Histórico de ejercicio expone `notas` (variante/agarre) — FASE 4
-- ============================================================
-- El cliente cambia el agarre en un mismo ejercicio (tríceps en polea con
-- barra / soga / maneral) y con cada agarre mueve un peso distinto. La
-- variante elegida ya se guarda en mypump_registros_carga.notas (mecanismo de
-- la rueda abdominal), pero mypump_get_historico_ejercicio NO la devolvía →
-- el front no podía discriminar el sugerido por variante.
--
-- Cambio: agregar `notas` al RETURNS TABLE. La columna ya existe en la tabla;
-- solo se expone. Hay que DROPear primero porque cambiar el tipo de retorno
-- de una función existente no se puede con CREATE OR REPLACE.
-- ============================================================

DROP FUNCTION IF EXISTS mypump_get_historico_ejercicio(TEXT, TEXT, INTEGER);

CREATE FUNCTION mypump_get_historico_ejercicio(
  p_token        TEXT,
  p_ejercicio_id TEXT,
  p_limit        INTEGER DEFAULT 10
)
RETURNS TABLE(
  registrado_en   TIMESTAMPTZ,
  peso_kg         NUMERIC,
  reps_realizadas INTEGER,
  rir_real        INTEGER,
  serie_numero    INTEGER,
  notas           TEXT
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
  SELECT r.registrado_en, r.peso_kg, r.reps_realizadas, r.rir_real, r.serie_numero, r.notas
  FROM mypump_registros_carga r
  WHERE r.cliente_id = v_cliente_id AND r.ejercicio_id = p_ejercicio_id
  ORDER BY r.registrado_en DESC
  LIMIT p_limit;
END;
$$;

GRANT EXECUTE ON FUNCTION mypump_get_historico_ejercicio(TEXT, TEXT, INTEGER)
  TO anon, authenticated, service_role;

-- ============================================================
-- ROLLBACK (restaura la versión sin `notas`, la de 001):
--
-- DROP FUNCTION IF EXISTS mypump_get_historico_ejercicio(TEXT, TEXT, INTEGER);
-- CREATE FUNCTION mypump_get_historico_ejercicio(
--   p_token TEXT, p_ejercicio_id TEXT, p_limit INTEGER DEFAULT 10
-- ) RETURNS TABLE(registrado_en TIMESTAMPTZ, peso_kg NUMERIC,
--   reps_realizadas INTEGER, rir_real INTEGER, serie_numero INTEGER)
-- LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
-- DECLARE v_cliente_id TEXT;
-- BEGIN
--   v_cliente_id := mypump_get_cliente_id_from_token(p_token);
--   IF v_cliente_id IS NULL THEN RETURN; END IF;
--   RETURN QUERY
--   SELECT r.registrado_en, r.peso_kg, r.reps_realizadas, r.rir_real, r.serie_numero
--   FROM mypump_registros_carga r
--   WHERE r.cliente_id = v_cliente_id AND r.ejercicio_id = p_ejercicio_id
--   ORDER BY r.registrado_en DESC LIMIT p_limit;
-- END; $$;
-- GRANT EXECUTE ON FUNCTION mypump_get_historico_ejercicio(TEXT, TEXT, INTEGER) TO anon;
-- ============================================================
