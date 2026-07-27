-- ============================================================
-- 044 — Recuperación del lado coach
-- ============================================================
-- Un wrapper por cliente_id (el panel no tiene el token del cliente, tiene su
-- id) y un resumen global para el listado y para el centinela.
--
-- NOTA DE DISEÑO: a propósito NO se toca mypump_get_metricas_coach. Sumarle
-- columnas obligaría a DROP + CREATE (cambia el RETURNS TABLE), y un DROP
-- RESETEA el ACL a PUBLIC — que es exactamente el agujero que cerró la 041.
-- Una RPC nueva cuesta un fetch más en el panel y no toca nada que ya funciona.
-- ============================================================

-- ── Serie diaria de un cliente, para la ficha del panel ───────────────────
CREATE OR REPLACE FUNCTION mypump_get_recuperacion_cliente_coach(
  p_cliente_id TEXT,
  p_dias       INTEGER DEFAULT 21
)
RETURNS TABLE (
  fecha DATE, score INTEGER, estado TEXT, banda TEXT, dias_datos INTEGER,
  banda_provisoria BOOLEAN, estado_autonomico TEXT, hrv_metrica TEXT,
  discordancia BOOLEAN, cobertura JSONB, componentes JSONB, motivos JSONB
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_hoy DATE;
BEGIN
  IF auth.role() NOT IN ('authenticated', 'service_role') THEN
    RAISE EXCEPTION 'Acceso denegado';
  END IF;
  v_hoy := (NOW() AT TIME ZONE 'America/Argentina/Buenos_Aires')::DATE;
  RETURN QUERY
    SELECT * FROM mypump_calc_recuperacion(
      p_cliente_id, v_hoy - GREATEST(1, LEAST(90, p_dias)) + 1, v_hoy);
END;
$$;

REVOKE ALL    ON FUNCTION mypump_get_recuperacion_cliente_coach(TEXT, INTEGER) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION mypump_get_recuperacion_cliente_coach(TEXT, INTEGER) TO authenticated, service_role;


-- ── Resumen por cliente: hoy + media 7d vs 7d previa ──────────────────────
-- Lo consumen el listado del panel (punto de alerta) y el centinela.
-- La caída de la media semanal es la señal, no el score de un día suelto:
-- un mal día es ruido, una semana en caída es una tendencia.
CREATE OR REPLACE FUNCTION mypump_get_recuperacion_resumen(
  p_dias INTEGER DEFAULT 14
)
RETURNS TABLE (
  cliente_id TEXT, nombre TEXT, score_hoy INTEGER, estado TEXT, banda TEXT,
  media_7d NUMERIC, media_7d_prev NUMERIC, delta_7d NUMERIC,
  dias_banda_baja INTEGER, estado_autonomico TEXT, hrv_metrica TEXT,
  discordancia BOOLEAN, motivos JSONB
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_hoy DATE;
BEGIN
  IF auth.role() NOT IN ('authenticated', 'service_role') THEN
    RAISE EXCEPTION 'Acceso denegado';
  END IF;
  v_hoy := (NOW() AT TIME ZONE 'America/Argentina/Buenos_Aires')::DATE;

  RETURN QUERY
  WITH serie AS (
    SELECT c.cliente_id, c.nombre, r.*
    FROM mypump_clientes c
    CROSS JOIN LATERAL mypump_calc_recuperacion(c.cliente_id, v_hoy - 13, v_hoy) r
    WHERE c.access_token_active = TRUE
  ),
  agg AS (
    SELECT s.cliente_id, s.nombre,
      ROUND(AVG(s.score) FILTER (WHERE s.fecha >  v_hoy - 7), 1) AS m7,
      ROUND(AVG(s.score) FILTER (WHERE s.fecha <= v_hoy - 7), 1) AS m7p,
      COUNT(*) FILTER (WHERE s.banda = 'baja' AND s.fecha > v_hoy - 7)::INTEGER AS bajos
    FROM serie s GROUP BY s.cliente_id, s.nombre
  ),
  hoy AS (
    SELECT DISTINCT ON (s.cliente_id) s.cliente_id, s.score, s.estado, s.banda,
           s.estado_autonomico, s.hrv_metrica, s.discordancia, s.motivos
    FROM serie s ORDER BY s.cliente_id, s.fecha DESC
  )
  SELECT a.cliente_id, a.nombre, h.score, h.estado, h.banda,
         a.m7, a.m7p, (a.m7 - a.m7p), a.bajos,
         h.estado_autonomico, h.hrv_metrica, h.discordancia, h.motivos
  FROM agg a JOIN hoy h ON h.cliente_id = a.cliente_id
  ORDER BY a.nombre;
END;
$$;

REVOKE ALL    ON FUNCTION mypump_get_recuperacion_resumen(INTEGER) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION mypump_get_recuperacion_resumen(INTEGER) TO authenticated, service_role;

-- ============================================================
-- Auditoría de ACLs (ver 041). Ninguna función de acá se dropeó, así que los
-- REVOKE de arriba alcanzan — pero conviene correrla igual después de aplicar:
--
-- SELECT p.proname, p.proacl FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
-- WHERE n.nspname='public' AND p.proname LIKE 'mypump%' AND p.proacl IS NULL;
-- ============================================================

-- ============================================================
-- ROLLBACK:
--   DROP FUNCTION IF EXISTS mypump_get_recuperacion_resumen(INTEGER);
--   DROP FUNCTION IF EXISTS mypump_get_recuperacion_cliente_coach(TEXT, INTEGER);
-- ============================================================
