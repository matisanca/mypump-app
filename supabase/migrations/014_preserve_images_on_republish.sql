-- 014 — Preservar images al republicar
-- ============================================================
-- BUG: cuando Cerebro republica un cliente, el matcher local
-- (matchearImagenesEjercicios en nutriplan/index.html) usa el RPC
-- mypump_match_ejercicio_por_nombre con threshold 0.5. Si el match
-- no llega a 0.5, setea ej.images=null. Luego mypump_publicar_cliente
-- hace UPDATE estructura=p_rutina, sobrescribiendo las URLs buenas
-- que ya estaban en la DB.
--
-- FIX: antes del UPDATE, mergear los images de la rutina vieja
-- con la nueva. Si el ejercicio nuevo viene con images=null pero
-- el viejo (matcheado por nombre normalizado) tenía images, preservar.
-- ============================================================

CREATE OR REPLACE FUNCTION mypump_publicar_cliente(
  p_cliente_id TEXT, p_nombre TEXT, p_perfil TEXT,
  p_rutina JSONB, p_dieta JSONB
) RETURNS TEXT
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_token TEXT;
  v_rid UUID;
  v_did UUID;
  v_rv INT;
  v_dv INT;
  v_old_rutina JSONB;
  v_merged_rutina JSONB;
BEGIN
  IF auth.role() <> 'authenticated' THEN RAISE EXCEPTION 'Acceso denegado'; END IF;

  SELECT access_token INTO v_token FROM mypump_clientes WHERE cliente_id = p_cliente_id;
  IF v_token IS NULL THEN
    v_token := generate_mypump_token();
    INSERT INTO mypump_clientes (cliente_id, nombre, perfil, access_token)
    VALUES (p_cliente_id, p_nombre, p_perfil, v_token);
  ELSE
    UPDATE mypump_clientes SET nombre = p_nombre, perfil = p_perfil, updated_at = NOW()
    WHERE cliente_id = p_cliente_id;
  END IF;

  -- RUTINA: merge images viejas si las nuevas vienen null
  SELECT id, version, estructura INTO v_rid, v_rv, v_old_rutina
  FROM mypump_rutinas WHERE cliente_id = p_cliente_id AND estado = 'activa';

  IF v_rid IS NOT NULL THEN
    -- Merge: por cada ejercicio nuevo, si images IS NULL y existe ejercicio viejo
    -- con mismo nombre (lower+trim) que tiene images, preservar las viejas.
    WITH old_imgs AS (
      SELECT
        lower(trim(e->>'nombre')) AS nombre_key,
        e->'images' AS images
      FROM jsonb_array_elements(v_old_rutina->'dias') d,
           jsonb_array_elements(d->'bloques') b,
           jsonb_array_elements(b->'ejercicios') e
      WHERE e->'images'->>'eccentric' IS NOT NULL
    ),
    new_dias AS (
      SELECT jsonb_agg(
        jsonb_set(d, '{bloques}',
          (SELECT jsonb_agg(
            jsonb_set(b, '{ejercicios}',
              (SELECT jsonb_agg(
                CASE
                  WHEN (e->'images'->>'eccentric') IS NULL
                       AND (SELECT images FROM old_imgs WHERE nombre_key = lower(trim(e->>'nombre')) LIMIT 1) IS NOT NULL
                  THEN jsonb_set(e, '{images}', (SELECT images FROM old_imgs WHERE nombre_key = lower(trim(e->>'nombre')) LIMIT 1))
                  ELSE e
                END
              ) FROM jsonb_array_elements(b->'ejercicios') e)
            )
          ) FROM jsonb_array_elements(d->'bloques') b)
        )
      ) AS dias_merged
      FROM jsonb_array_elements(p_rutina->'dias') d
    )
    SELECT jsonb_set(p_rutina, '{dias}', dias_merged) INTO v_merged_rutina FROM new_dias;

    UPDATE mypump_rutinas
      SET estructura = COALESCE(v_merged_rutina, p_rutina),
          version = v_rv + 1,
          updated_at = NOW()
      WHERE id = v_rid;
  ELSE
    SELECT COALESCE(MAX(version),0)+1 INTO v_rv FROM mypump_rutinas WHERE cliente_id = p_cliente_id;
    INSERT INTO mypump_rutinas (cliente_id, version, estado, estructura, created_by, fecha_inicio)
    VALUES (p_cliente_id, v_rv, 'activa', p_rutina, auth.uid(), CURRENT_DATE);
  END IF;

  -- DIETA: igual, merge si fuera necesario (la dieta no tiene images por ahora, pero por simetría)
  SELECT id, version INTO v_did, v_dv FROM mypump_dietas WHERE cliente_id = p_cliente_id AND estado = 'activa';
  IF v_did IS NOT NULL THEN
    UPDATE mypump_dietas SET estructura = p_dieta, version = v_dv + 1, updated_at = NOW() WHERE id = v_did;
  ELSE
    SELECT COALESCE(MAX(version),0)+1 INTO v_dv FROM mypump_dietas WHERE cliente_id = p_cliente_id;
    INSERT INTO mypump_dietas (cliente_id, version, estado, estructura, created_by)
    VALUES (p_cliente_id, v_dv, 'activa', p_dieta, auth.uid());
  END IF;

  RETURN v_token;
END; $$;

GRANT EXECUTE ON FUNCTION mypump_publicar_cliente(TEXT,TEXT,TEXT,JSONB,JSONB) TO authenticated;
