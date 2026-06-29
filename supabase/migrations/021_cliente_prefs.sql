-- ============================================================
-- 021 — Preferencias por cliente (restricciones alimentarias)
-- ============================================================
-- Caso: Gerardo (Egipto) no consigue cerdo. Clientes internacionales tienen
-- restricciones (sin cerdo/halal, sin mariscos, alergias). Guardamos por cliente
-- una lista de "grupos a excluir" (tags) que el front usa para esconder esos
-- alimentos de las sugerencias de sustitución (food swap).
--
-- El TAG (ej: 'cerdo', 'mariscos', 'lacteos') lo interpreta el cliente
-- (app.js → foodSwap._EXCLUDE_GROUPS mapea tag → regex de nombres). Así sumar
-- un grupo nuevo no requiere migración: se agrega el regex en app.js.
--
-- idioma: reservado para futuro (hoy las opciones universales ya muestran el
-- nombre en inglés para todos). Default 'es'.
-- ============================================================

CREATE TABLE IF NOT EXISTS mypump_cliente_prefs (
  cliente_id TEXT        PRIMARY KEY,
  excluir    TEXT[]      NOT NULL DEFAULT '{}',   -- tags de grupos a esconder (ej: {'cerdo'})
  idioma     TEXT        NOT NULL DEFAULT 'es',
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- RLS deny-all; el acceso público pasa por las RPC SECURITY DEFINER.
ALTER TABLE mypump_cliente_prefs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "admin all mypump_cliente_prefs"
  ON mypump_cliente_prefs FOR ALL
  USING (auth.role() = 'authenticated')
  WITH CHECK (auth.role() = 'authenticated');

-- ── RPC pública: el cliente lee SUS prefs (token como credencial) ──
-- Si no tiene fila, no devuelve nada → el front usa defaults (sin exclusiones).
CREATE OR REPLACE FUNCTION mypump_get_cliente_prefs(p_token TEXT)
RETURNS TABLE(excluir TEXT[], idioma TEXT)
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
    SELECT p.excluir, p.idioma
    FROM mypump_cliente_prefs p
    WHERE p.cliente_id = v_cliente_id;
END;
$$;

GRANT EXECUTE ON FUNCTION mypump_get_cliente_prefs(TEXT) TO anon;

-- ── RPC admin: setear las prefs de un cliente (por su token) ──
-- La corre Mati en el SQL editor (como superusuario), o Cerebro como
-- 'authenticated'. anon NO recibe EXECUTE (no es self-service por ahora).
CREATE OR REPLACE FUNCTION mypump_set_cliente_prefs(
  p_token   TEXT,
  p_excluir TEXT[],
  p_idioma  TEXT DEFAULT 'es'
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
  IF v_cliente_id IS NULL THEN RETURN FALSE; END IF;
  INSERT INTO mypump_cliente_prefs (cliente_id, excluir, idioma, updated_at)
  VALUES (v_cliente_id, COALESCE(p_excluir, '{}'), COALESCE(p_idioma, 'es'), NOW())
  ON CONFLICT (cliente_id) DO UPDATE
    SET excluir = EXCLUDED.excluir,
        idioma  = EXCLUDED.idioma,
        updated_at = NOW();
  RETURN TRUE;
END;
$$;

GRANT EXECUTE ON FUNCTION mypump_set_cliente_prefs(TEXT, TEXT[], TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION mypump_set_cliente_prefs(TEXT, TEXT[], TEXT) TO service_role;
