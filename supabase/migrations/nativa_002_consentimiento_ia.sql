-- nativa_002_consentimiento_ia.sql
--
-- APPS NATIVAS, COMPUERTA G2 (segunda tanda): EL PERMISO PARA LA IA (D7).
--
-- Apple (guía 5.1.2(i)) pide avisar con quién se comparten los datos, también
-- una IA de terceros, y pedir permiso explícito antes. Decisión de Mati
-- (14-oct): un permiso con un "no" real que cubre TODO lo que lee los datos
-- del cliente con IA:
--   · el chat (chat_worker y sugerir_pendientes, Codex/OpenAI): quien dijo que
--     no queda escalado para Mati, sin pasar por el modelo;
--   · la foto del plato o de la etiqueta (mini-vision, OpenAI): la app no la
--     manda a analizar;
--   · la ronda del domingo (centinela, Claude): sus datos no van a ningún
--     envío y quedan con el respaldo determinista que ya existía.
--
-- Sin fila = nunca se le preguntó (la web y la app vieja no preguntan): sigue
-- como hoy. Solo `acepta = false` apaga la IA para ese cliente.
--
-- Solo agrega: una tabla y tres funciones. No cambia nada existente.
BEGIN;

CREATE TABLE IF NOT EXISTS mypump_consentimiento_ia (
  cliente_id     TEXT        PRIMARY KEY,
  acepta         BOOLEAN     NOT NULL,
  plataforma     TEXT        CHECK (plataforma IN ('ios', 'android')),
  app_version    TEXT,
  actualizado_en TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE mypump_consentimiento_ia ENABLE ROW LEVEL SECURITY;

CREATE POLICY "admin all mypump_consentimiento_ia"
  ON mypump_consentimiento_ia FOR ALL
  USING (auth.role() = 'authenticated')
  WITH CHECK (auth.role() = 'authenticated');

-- La app: qué decidió el cliente. NULL = token caído; {"acepta": null} = nunca se le preguntó.
CREATE OR REPLACE FUNCTION mypump_get_consentimiento_ia(p_token TEXT)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_cliente_id TEXT;
  v_fila       mypump_consentimiento_ia%ROWTYPE;
BEGIN
  v_cliente_id := mypump_get_cliente_id_from_token(p_token);
  IF v_cliente_id IS NULL THEN RETURN NULL; END IF;
  SELECT * INTO v_fila FROM mypump_consentimiento_ia WHERE cliente_id = v_cliente_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('acepta', NULL); END IF;
  RETURN jsonb_build_object('acepta', v_fila.acepta, 'actualizado_en', v_fila.actualizado_en);
END;
$$;

REVOKE ALL ON FUNCTION mypump_get_consentimiento_ia(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION mypump_get_consentimiento_ia(TEXT) TO anon, authenticated, service_role;

-- La app: guarda la decisión (y cada cambio desde Mis datos). TRUE = guardado; NULL = token caído.
CREATE OR REPLACE FUNCTION mypump_guardar_consentimiento_ia(
  p_token      TEXT,
  p_acepta     BOOLEAN,
  p_plataforma TEXT DEFAULT NULL,
  p_app        TEXT DEFAULT NULL
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_cliente_id TEXT;
BEGIN
  v_cliente_id := mypump_get_cliente_id_from_token(p_token);
  IF v_cliente_id IS NULL THEN RETURN NULL; END IF;
  IF p_acepta IS NULL OR (p_plataforma IS NOT NULL AND p_plataforma NOT IN ('ios', 'android')) THEN
    RAISE EXCEPTION 'consentimiento inválido' USING ERRCODE = '22023';
  END IF;

  INSERT INTO mypump_consentimiento_ia (cliente_id, acepta, plataforma, app_version)
  VALUES (v_cliente_id, p_acepta, p_plataforma, left(p_app, 40))
  ON CONFLICT (cliente_id) DO UPDATE
    SET acepta         = EXCLUDED.acepta,
        plataforma     = EXCLUDED.plataforma,
        app_version    = EXCLUDED.app_version,
        actualizado_en = NOW();

  RETURN TRUE;
END;
$$;

REVOKE ALL ON FUNCTION mypump_guardar_consentimiento_ia(TEXT, BOOLEAN, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION mypump_guardar_consentimiento_ia(TEXT, BOOLEAN, TEXT, TEXT) TO anon, authenticated, service_role;

-- El servidor (chat_worker, sugerir_pendientes, centinela): de estos clientes,
-- cuáles dijeron que no. Solo service_role: no es para la app.
CREATE OR REPLACE FUNCTION mypump_clientes_sin_ia(p_clientes TEXT[])
RETURNS TEXT[]
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(array_agg(cliente_id ORDER BY cliente_id), '{}'::TEXT[])
  FROM mypump_consentimiento_ia
  WHERE cliente_id = ANY(p_clientes) AND NOT acepta;
$$;

REVOKE ALL ON FUNCTION mypump_clientes_sin_ia(TEXT[]) FROM PUBLIC;
REVOKE ALL ON FUNCTION mypump_clientes_sin_ia(TEXT[]) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION mypump_clientes_sin_ia(TEXT[]) TO service_role;

NOTIFY pgrst, 'reload schema';

COMMIT;
