-- ============================================================
-- 006 — Fix fecha_inicio en mypump_publicar_cliente
-- ============================================================
-- El INSERT de mypump_rutinas no estaba seteando fecha_inicio,
-- por lo que mypump_rutinas.fecha_inicio quedaba NULL al publicar
-- un cliente nuevo desde Cerebro.
--
-- Esta migration recrea la función con el MISMO comportamiento
-- de 001_mypump_schema.sql (líneas 622-681), agregando solamente
-- `fecha_inicio = CURRENT_DATE` en el INSERT de mypump_rutinas.
--
-- Cambios mínimos vs original:
--   1. INSERT mypump_rutinas ahora incluye fecha_inicio.
--   (Todo lo demás se preserva: generate_mypump_token,
--   created_by = auth.uid(), variables, search_path, grants.)
--
-- NO se toca access_token_active en re-publicación — preserva
-- el comportamiento original de respetar revocaciones previas.
-- ============================================================

CREATE OR REPLACE FUNCTION mypump_publicar_cliente(
  p_cliente_id TEXT,
  p_nombre     TEXT,
  p_perfil     TEXT,
  p_rutina     JSONB,
  p_dieta      JSONB
)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_token               TEXT;
  v_next_rutina_version INTEGER;
  v_next_dieta_version  INTEGER;
BEGIN
  -- Solo authenticated puede ejecutar esta función
  IF auth.role() <> 'authenticated' THEN
    RAISE EXCEPTION 'Acceso denegado';
  END IF;

  -- Upsert cliente
  SELECT access_token INTO v_token
  FROM mypump_clientes
  WHERE cliente_id = p_cliente_id;

  IF v_token IS NULL THEN
    v_token := generate_mypump_token();
    INSERT INTO mypump_clientes (cliente_id, nombre, perfil, access_token)
    VALUES (p_cliente_id, p_nombre, p_perfil, v_token);
  ELSE
    UPDATE mypump_clientes
    SET nombre = p_nombre, perfil = p_perfil, updated_at = NOW()
    WHERE cliente_id = p_cliente_id;
  END IF;

  -- Versión de rutina: MAX(version) + 1 sobre todas las versiones del cliente
  SELECT COALESCE(MAX(version), 0) + 1 INTO v_next_rutina_version
  FROM mypump_rutinas WHERE cliente_id = p_cliente_id;

  UPDATE mypump_rutinas SET estado = 'archivada'
  WHERE cliente_id = p_cliente_id AND estado = 'activa';

  -- INSERT rutina nueva con fecha_inicio (← FIX de esta migration)
  INSERT INTO mypump_rutinas (
    cliente_id, version, estado, estructura, created_by, fecha_inicio
  )
  VALUES (
    p_cliente_id, v_next_rutina_version, 'activa', p_rutina, auth.uid(), CURRENT_DATE
  );

  -- Versión de dieta: misma lógica
  SELECT COALESCE(MAX(version), 0) + 1 INTO v_next_dieta_version
  FROM mypump_dietas WHERE cliente_id = p_cliente_id;

  UPDATE mypump_dietas SET estado = 'archivada'
  WHERE cliente_id = p_cliente_id AND estado = 'activa';

  INSERT INTO mypump_dietas (cliente_id, version, estado, estructura, created_by)
  VALUES (p_cliente_id, v_next_dieta_version, 'activa', p_dieta, auth.uid());

  RETURN v_token;
END;
$$;

GRANT EXECUTE ON FUNCTION mypump_publicar_cliente(TEXT, TEXT, TEXT, JSONB, JSONB) TO authenticated;
