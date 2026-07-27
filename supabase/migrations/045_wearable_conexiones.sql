-- ============================================================
-- 045 — Vía A: conexiones OAuth con wearables (Oura, Whoop, …)
-- ============================================================
-- POR QUÉ APIs DIRECTAS Y NO UN AGREGADOR:
--   Los agregadores (Rook, Terra, Junction, Spike) arrancan en USD 300-500/mes
--   — para 50-100 clientes son USD 3-6 por cliente por mes solo en el
--   intermediario. Oura, Withings y Polar tienen API propia gratis y
--   self-serve, y Whoop también (con aprobación). Y son la ÚNICA vía para
--   traer HRV real de esos dispositivos: verificado que NINGUNO escribe HRV a
--   Apple Health (HealthKit solo tiene el campo SDNN y todos calculan rMSSD;
--   Whoop lo declara explícitamente como el motivo de no sincronizarla).
--
-- QUÉ APORTA ESTO QUE LA VÍA B NO:
--   · HRV real (rMSSD nocturno) de Oura/Whoop, que Apple Health no da.
--   · Funciona en la WEB: los clientes de Android, que nunca van a tener la
--     app nativa, pueden conectar su reloj igual.
--
-- SEGURIDAD DE LOS TOKENS:
--   Se guardan CIFRADOS (AES-GCM) desde la Pages Function; la clave vive en
--   env vars de Cloudflare y en el .env de la mini, NUNCA en Postgres. Eso
--   protege ante exposición del lado Supabase (dashboard, un backup, la
--   service key filtrada): quien lea la tabla obtiene bytes inútiles.
--   NO protege una mini comprometida, que ya tiene la service key — conviene
--   decirlo así y no pretender más. `enc_kid` permite rotar la clave sin
--   migrar los datos.
-- ============================================================

CREATE TABLE IF NOT EXISTS mypump_wearable_conexiones (
  id                 UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  cliente_id         TEXT        NOT NULL,
  proveedor          TEXT        NOT NULL CHECK (proveedor IN ('oura','whoop','withings','polar')),
  proveedor_user_id  TEXT,                       -- resuelve webhook → cliente
  estado             TEXT        NOT NULL DEFAULT 'pendiente'
                                 CHECK (estado IN ('pendiente','conectada','expirada','revocada','error')),
  scopes             TEXT[]      NOT NULL DEFAULT '{}',
  access_token_enc   TEXT,                       -- ciphertext, nunca plano
  refresh_token_enc  TEXT,
  enc_kid            TEXT,                       -- id de la clave, para rotar
  token_expira_en    TIMESTAMPTZ,
  ultimo_pull_en     TIMESTAMPTZ,
  ultimo_pull_hasta  DATE,                       -- watermark: hasta dónde se trajo
  ultimo_error       TEXT,
  intentos_fallidos  INTEGER     NOT NULL DEFAULT 0,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (cliente_id, proveedor),
  UNIQUE (proveedor, proveedor_user_id)
);

CREATE INDEX IF NOT EXISTS idx_wearable_conex_pull
  ON mypump_wearable_conexiones (estado, ultimo_pull_en NULLS FIRST);

ALTER TABLE mypump_wearable_conexiones ENABLE ROW LEVEL SECURITY;
CREATE POLICY "admin all mypump_wearable_conexiones"
  ON mypump_wearable_conexiones FOR ALL
  USING (auth.role() = 'authenticated') WITH CHECK (auth.role() = 'authenticated');

-- ── Estados OAuth en curso (CSRF + PKCE) ─────────────────────────────────
-- Efímeros: se borran al usarse. El `state` es lo único que ata el callback
-- del proveedor con el cliente que inició el flujo.
CREATE TABLE IF NOT EXISTS mypump_oauth_estados (
  state         TEXT        PRIMARY KEY,
  cliente_id    TEXT        NOT NULL,
  proveedor     TEXT        NOT NULL,
  code_verifier TEXT,                            -- PKCE
  expira_en     TIMESTAMPTZ NOT NULL,
  usado_en      TIMESTAMPTZ,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
ALTER TABLE mypump_oauth_estados ENABLE ROW LEVEL SECURITY;
CREATE POLICY "admin all mypump_oauth_estados"
  ON mypump_oauth_estados FOR ALL
  USING (auth.role() = 'authenticated') WITH CHECK (auth.role() = 'authenticated');


-- ============================================================
-- RPC del CLIENTE: qué relojes tiene conectados (por token).
-- Devuelve SOLO estado, nunca tokens. Es lo que la app pollea mientras el
-- cliente está en la pantalla del proveedor.
-- ============================================================
CREATE OR REPLACE FUNCTION mypump_get_conexiones(p_token TEXT)
RETURNS TABLE (proveedor TEXT, estado TEXT, ultimo_pull_en TIMESTAMPTZ)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_cliente_id TEXT;
BEGIN
  v_cliente_id := mypump_get_cliente_id_from_token(p_token);
  IF v_cliente_id IS NULL THEN RETURN; END IF;
  RETURN QUERY
    SELECT w.proveedor, w.estado, w.ultimo_pull_en
    FROM mypump_wearable_conexiones w
    WHERE w.cliente_id = v_cliente_id
    ORDER BY w.proveedor;
END;
$$;
GRANT EXECUTE ON FUNCTION mypump_get_conexiones(TEXT) TO anon, authenticated;

-- ── Desconectar (por token, acción del cliente) ───────────────────────────
CREATE OR REPLACE FUNCTION mypump_desconectar_wearable(p_token TEXT, p_proveedor TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_cliente_id TEXT;
BEGIN
  v_cliente_id := mypump_get_cliente_id_from_token(p_token);
  IF v_cliente_id IS NULL THEN RETURN FALSE; END IF;
  DELETE FROM mypump_wearable_conexiones
   WHERE cliente_id = v_cliente_id AND proveedor = p_proveedor;
  RETURN TRUE;
END;
$$;
GRANT EXECUTE ON FUNCTION mypump_desconectar_wearable(TEXT, TEXT) TO anon, authenticated;

-- ============================================================
-- RPCs de SERVIDOR: las llaman las Pages Functions y la mini con la service
-- key. NUNCA anon: manejan tokens.
-- ============================================================
CREATE OR REPLACE FUNCTION mypump_oauth_iniciar_service(
  p_token TEXT, p_proveedor TEXT, p_state TEXT, p_verifier TEXT)
RETURNS TEXT
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_cliente_id TEXT;
BEGIN
  v_cliente_id := mypump_get_cliente_id_from_token(p_token);
  IF v_cliente_id IS NULL THEN RETURN NULL; END IF;
  DELETE FROM mypump_oauth_estados WHERE expira_en < NOW();   -- limpieza barata
  INSERT INTO mypump_oauth_estados (state, cliente_id, proveedor, code_verifier, expira_en)
  VALUES (p_state, v_cliente_id, p_proveedor, p_verifier, NOW() + INTERVAL '15 minutes');
  RETURN v_cliente_id;
END;
$$;
REVOKE ALL ON FUNCTION mypump_oauth_iniciar_service(TEXT,TEXT,TEXT,TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION mypump_oauth_iniciar_service(TEXT,TEXT,TEXT,TEXT) TO service_role;

-- Canjea el state (un solo uso) y guarda la conexión ya cifrada.
CREATE OR REPLACE FUNCTION mypump_oauth_completar_service(
  p_state TEXT, p_acc_enc TEXT, p_ref_enc TEXT, p_kid TEXT,
  p_expira TIMESTAMPTZ, p_prov_user TEXT, p_scopes TEXT[])
RETURNS TEXT
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_st RECORD;
BEGIN
  SELECT * INTO v_st FROM mypump_oauth_estados
   WHERE state = p_state AND usado_en IS NULL AND expira_en > NOW();
  IF NOT FOUND THEN RETURN NULL; END IF;
  UPDATE mypump_oauth_estados SET usado_en = NOW() WHERE state = p_state;

  INSERT INTO mypump_wearable_conexiones
    (cliente_id, proveedor, proveedor_user_id, estado, scopes,
     access_token_enc, refresh_token_enc, enc_kid, token_expira_en)
  VALUES (v_st.cliente_id, v_st.proveedor, p_prov_user, 'conectada', COALESCE(p_scopes,'{}'),
          p_acc_enc, p_ref_enc, p_kid, p_expira)
  ON CONFLICT (cliente_id, proveedor) DO UPDATE
    SET proveedor_user_id = EXCLUDED.proveedor_user_id, estado = 'conectada',
        scopes = EXCLUDED.scopes, access_token_enc = EXCLUDED.access_token_enc,
        refresh_token_enc = EXCLUDED.refresh_token_enc, enc_kid = EXCLUDED.enc_kid,
        token_expira_en = EXCLUDED.token_expira_en, ultimo_error = NULL,
        intentos_fallidos = 0, updated_at = NOW();
  RETURN v_st.cliente_id;
END;
$$;
REVOKE ALL ON FUNCTION mypump_oauth_completar_service(TEXT,TEXT,TEXT,TEXT,TIMESTAMPTZ,TEXT,TEXT[]) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION mypump_oauth_completar_service(TEXT,TEXT,TEXT,TEXT,TIMESTAMPTZ,TEXT,TEXT[]) TO service_role;

-- ============================================================
-- ROLLBACK:
--   DROP FUNCTION IF EXISTS mypump_oauth_completar_service(TEXT,TEXT,TEXT,TEXT,TIMESTAMPTZ,TEXT,TEXT[]);
--   DROP FUNCTION IF EXISTS mypump_oauth_iniciar_service(TEXT,TEXT,TEXT,TEXT);
--   DROP FUNCTION IF EXISTS mypump_desconectar_wearable(TEXT, TEXT);
--   DROP FUNCTION IF EXISTS mypump_get_conexiones(TEXT);
--   DROP TABLE IF EXISTS mypump_oauth_estados;
--   DROP TABLE IF EXISTS mypump_wearable_conexiones;
-- ============================================================
