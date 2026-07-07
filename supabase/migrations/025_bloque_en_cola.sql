-- ============================================================
-- 025 — Bloque siguiente "en cola" (se activa solo al terminar el actual)
-- ============================================================
-- Al generar el próximo bloque mientras el cliente todavía NO terminó el
-- actual, NO se pisa su plan: se guarda como `estructura_siguiente`. El
-- cliente sigue su plan, y en la última semana aparece un botón "Empezar
-- bloque nuevo" que activa la estructura encolada (swap in-place → conserva
-- el mismo rutina_id, así el historial de cargas no se pierde).
-- ============================================================

ALTER TABLE mypump_rutinas ADD COLUMN IF NOT EXISTS estructura_siguiente JSONB;

-- ── get_rutina_activa: exponer tiene_siguiente ──
DROP FUNCTION IF EXISTS mypump_get_rutina_activa(TEXT);
CREATE FUNCTION mypump_get_rutina_activa(p_token TEXT)
RETURNS TABLE(
  id             UUID,
  version        INTEGER,
  estructura     JSONB,
  semana_actual  INTEGER,
  fecha_inicio   DATE,
  fecha_fin      DATE,
  tiene_siguiente BOOLEAN
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
  SELECT r.id, r.version, r.estructura, r.semana_actual, r.fecha_inicio, r.fecha_fin,
         (r.estructura_siguiente IS NOT NULL) AS tiene_siguiente
  FROM mypump_rutinas r
  WHERE r.cliente_id = v_cliente_id AND r.estado = 'activa';
END;
$$;
GRANT EXECUTE ON FUNCTION mypump_get_rutina_activa(TEXT) TO anon, authenticated, service_role;

-- ── Encolar el bloque siguiente (Cerebro/coach) ──
CREATE OR REPLACE FUNCTION mypump_encolar_siguiente(
  p_cliente_id TEXT,
  p_estructura JSONB
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE mypump_rutinas
     SET estructura_siguiente = p_estructura,
         updated_at = NOW()
   WHERE cliente_id = p_cliente_id AND estado = 'activa';
  RETURN FOUND;
END;
$$;
REVOKE ALL ON FUNCTION mypump_encolar_siguiente(TEXT, JSONB) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION mypump_encolar_siguiente(TEXT, JSONB) TO authenticated, service_role;

-- ── Activar el bloque encolado (cliente, con token) ──
-- Swap in-place: estructura ← estructura_siguiente, semana_actual ← 1.
-- Mismo rutina_id ⇒ sesiones/registros históricos se conservan.
CREATE OR REPLACE FUNCTION mypump_activar_siguiente(p_token TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_cliente_id TEXT;
  v_sig JSONB;
BEGIN
  v_cliente_id := mypump_get_cliente_id_from_token(p_token);
  IF v_cliente_id IS NULL THEN RETURN FALSE; END IF;

  SELECT estructura_siguiente INTO v_sig
    FROM mypump_rutinas
   WHERE cliente_id = v_cliente_id AND estado = 'activa'
   LIMIT 1;
  IF v_sig IS NULL THEN RETURN FALSE; END IF;

  UPDATE mypump_rutinas
     SET estructura = v_sig,
         estructura_siguiente = NULL,
         semana_actual = 1,
         version = version + 1,
         updated_at = NOW()
   WHERE cliente_id = v_cliente_id AND estado = 'activa';
  RETURN TRUE;
END;
$$;
REVOKE ALL ON FUNCTION mypump_activar_siguiente(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION mypump_activar_siguiente(TEXT) TO anon, authenticated, service_role;
