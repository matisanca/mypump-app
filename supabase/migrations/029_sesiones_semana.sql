-- ============================================================
-- 029 — mypump_get_sesiones_semana: sesiones de la semana (day picker ✓)
-- ============================================================
-- FASE 1 (feedback de cliente): en la barra de días, marcar en verde con ✓
-- los días de la semana actual que el cliente ya COMPLETÓ (sesión con
-- finalizada_en). El front necesita todas las sesiones de una semana; hoy
-- solo existe mypump_get_sesion_dia (una por día). El filtro por semana
-- hace que al avanzar de semana el picker se resetee solo.
--
-- Devuelve una fila por dia_id (la sesión con más actividad de ese día,
-- mismo criterio que la 010, para ignorar sesiones "vacías" duplicadas).
-- ============================================================

CREATE OR REPLACE FUNCTION mypump_get_sesiones_semana(
  p_token  TEXT,
  p_semana INTEGER
)
RETURNS TABLE (
  dia_id        TEXT,
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
    SELECT DISTINCT ON (s.dia_id)
      s.dia_id, s.iniciada_en, s.finalizada_en
    FROM mypump_sesiones s
    WHERE s.cliente_id = v_cliente_id
      AND s.semana     = p_semana
    ORDER BY
      s.dia_id,
      -- Por día: preferir la sesión con más actividad real (criterio de 010)
      ((SELECT COUNT(*) FROM mypump_registros_carga rc WHERE rc.sesion_id = s.id) +
       (SELECT COUNT(*) FROM mypump_ejercicios_estado es WHERE es.sesion_id = s.id
          AND es.status IN ('completo','completo_sin_datos'))) DESC,
      s.iniciada_en DESC;
END;
$$;

GRANT EXECUTE ON FUNCTION mypump_get_sesiones_semana(TEXT, INTEGER) TO anon, authenticated;

-- ============================================================
-- ROLLBACK (revierte esta migración por completo):
--   DROP FUNCTION IF EXISTS mypump_get_sesiones_semana(TEXT, INTEGER);
-- ============================================================
