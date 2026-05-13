-- ============================================================
-- 010 — mypump_get_sesion_dia: preferir sesión con más actividad
-- ============================================================
-- Mejora sobre migration 009. La versión anterior ordenaba por
-- iniciada_en DESC y devolvía la más reciente. Eso falla si por
-- algún motivo existen 2 sesiones para el mismo (cliente, día, semana):
-- por ejemplo, una "vacía" (creada por error, sin sets) que es más
-- reciente que la "llena" (con sets cargados reales).
--
-- Nueva lógica: ordenar primero por cantidad de actividad
-- (sets cargados + ejercicios completados), después por fecha.
-- Así siempre devolvemos la sesión donde el cliente realmente entrenó.
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
    ORDER BY
      -- Preferir la que tiene más actividad real (sets + ejercicios completos)
      ((SELECT COUNT(*) FROM mypump_registros_carga rc WHERE rc.sesion_id = s.id) +
       (SELECT COUNT(*) FROM mypump_ejercicios_estado es WHERE es.sesion_id = s.id
          AND es.status IN ('completo','completo_sin_datos'))) DESC,
      -- En caso de empate, la más reciente
      s.iniciada_en DESC
    LIMIT 1;
END;
$$;

GRANT EXECUTE ON FUNCTION mypump_get_sesion_dia(TEXT, TEXT, INTEGER) TO anon;
