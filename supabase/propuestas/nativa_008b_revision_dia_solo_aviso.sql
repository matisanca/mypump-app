-- ============================================================
-- nativa_008b — Día de revisión por alumno, SOLO para el aviso (propuesta: no aplicada, requiere ensayo y OK de Mati)
-- ============================================================
-- Reemplaza a supabase/migrations/nativa_008_revision_dia.sql (nunca aplicada): aquella corre la semana para quien no
-- revisa el domingo (semana_lunes = lunes ISO de fecha + 7 - dia). Mati pidió que la semana siga de lunes a domingo, así
-- que acá no se toca ningún check, foto, vista ni la ronda: solo se guarda el día y la app lo lee para el aviso local.
-- NO aplicar las dos. Con todos en 7 no cambia nada.
-- La ronda de la Mini sigue con su DIA_REVISION. El aviso de fotos (aviso_fotos_semana.py) lee esta columna: el día del
-- aviso su clave coincide con el lunes ISO, así que anda igual.
-- ============================================================

BEGIN;
SET LOCAL lock_timeout = '5s';

ALTER TABLE mypump_cliente_prefs
  ADD COLUMN IF NOT EXISTS revision_dia SMALLINT NOT NULL DEFAULT 7
  CHECK (revision_dia BETWEEN 1 AND 7);

COMMENT ON COLUMN mypump_cliente_prefs.revision_dia IS
  'Día ISO del aviso de la revisión (1=lun … 7=dom). La semana sigue de lunes a domingo. Default 7.';

-- Pública (la app): el día del cliente del token. 7 sin token válido o sin fila.
CREATE OR REPLACE FUNCTION mypump_get_revision_dia(p_token TEXT)
RETURNS SMALLINT
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE v_cliente_id TEXT;
BEGIN
  v_cliente_id := mypump_get_cliente_id_from_token(p_token);
  IF v_cliente_id IS NULL THEN RETURN 7; END IF;
  RETURN COALESCE((SELECT revision_dia FROM mypump_cliente_prefs WHERE cliente_id = v_cliente_id), 7)::SMALLINT;
END;
$$;
REVOKE ALL ON FUNCTION mypump_get_revision_dia(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION mypump_get_revision_dia(TEXT) TO anon, authenticated, service_role;

-- Admin (Mati, Cerebro, scripts de la Mini): el alumno no lo cambia desde la app.
CREATE OR REPLACE FUNCTION mypump_set_revision_dia(p_cliente_id TEXT, p_dia SMALLINT)
RETURNS BOOLEAN
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF p_dia IS NULL OR p_dia NOT BETWEEN 1 AND 7 THEN RAISE EXCEPTION 'revision_dia va de 1 (lunes) a 7 (domingo)'; END IF;
  IF NOT EXISTS (SELECT 1 FROM mypump_clientes WHERE cliente_id = p_cliente_id) THEN RETURN FALSE; END IF;
  INSERT INTO mypump_cliente_prefs (cliente_id, revision_dia) VALUES (p_cliente_id, p_dia)
  ON CONFLICT (cliente_id) DO UPDATE SET revision_dia = EXCLUDED.revision_dia, updated_at = NOW();
  RETURN TRUE;
END;
$$;
REVOKE ALL ON FUNCTION mypump_set_revision_dia(TEXT, SMALLINT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION mypump_set_revision_dia(TEXT, SMALLINT) TO authenticated, service_role;

COMMIT;
NOTIFY pgrst, 'reload schema';
