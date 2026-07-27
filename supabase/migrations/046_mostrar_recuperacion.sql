-- ============================================================
-- 046 — Preferencia: mostrar o no el score de recuperación al cliente
-- ============================================================
-- La columna `mostrar_recuperacion` se creó en la 043 pero era una columna
-- MUERTA: no había forma de escribirla ni nadie la leía. Acá se le ponen las
-- dos RPCs y la app pasa a respetarla.
--
-- POR QUÉ EXISTE: hay un fenómeno documentado (ortosomnia) donde el propio
-- tracker genera ansiedad — el score malo presiona, la presión activa el
-- simpático, y la app que debía ayudar a recuperar es la razón por la que la
-- persona mira el techo. Para un cliente que se engancha así, lo sano es que
-- pueda apagar el número.
--
-- Clave del diseño: apagarlo NO deja de capturar. El dato se sigue guardando
-- y el coach lo sigue viendo en su panel; lo único que desaparece es el
-- número de la pantalla del cliente. Así la decisión de entrenamiento no
-- pierde información por una preferencia de UI.
-- ============================================================

CREATE OR REPLACE FUNCTION mypump_set_mostrar_recuperacion(p_token TEXT, p_mostrar BOOLEAN)
RETURNS BOOLEAN
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_cliente_id TEXT;
BEGIN
  v_cliente_id := mypump_get_cliente_id_from_token(p_token);
  IF v_cliente_id IS NULL THEN RETURN FALSE; END IF;
  INSERT INTO mypump_cliente_prefs (cliente_id, mostrar_recuperacion)
  VALUES (v_cliente_id, COALESCE(p_mostrar, TRUE))
  ON CONFLICT (cliente_id) DO UPDATE
    SET mostrar_recuperacion = EXCLUDED.mostrar_recuperacion, updated_at = NOW();
  RETURN TRUE;
END;
$$;
GRANT EXECUTE ON FUNCTION mypump_set_mostrar_recuperacion(TEXT, BOOLEAN) TO anon, authenticated;

-- Default TRUE cuando no hay fila de prefs: el score se muestra salvo que el
-- cliente lo apague explícitamente.
CREATE OR REPLACE FUNCTION mypump_get_mostrar_recuperacion(p_token TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE v_cliente_id TEXT; v_m BOOLEAN;
BEGIN
  v_cliente_id := mypump_get_cliente_id_from_token(p_token);
  IF v_cliente_id IS NULL THEN RETURN TRUE; END IF;
  SELECT mostrar_recuperacion INTO v_m FROM mypump_cliente_prefs WHERE cliente_id = v_cliente_id;
  RETURN COALESCE(v_m, TRUE);
END;
$$;
GRANT EXECUTE ON FUNCTION mypump_get_mostrar_recuperacion(TEXT) TO anon, authenticated;

-- ============================================================
-- ROLLBACK:
--   DROP FUNCTION IF EXISTS mypump_get_mostrar_recuperacion(TEXT);
--   DROP FUNCTION IF EXISTS mypump_set_mostrar_recuperacion(TEXT, BOOLEAN);
-- ============================================================
