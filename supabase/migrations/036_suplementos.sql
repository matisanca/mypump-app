-- ============================================================
-- 036 - Suplementacion consolidada por cliente (fuente de verdad)
-- ============================================================
-- Hoy la suplementacion esta dispersa: dictada en las videollamadas de
-- entrega (Fathom) y suelta en el chat de WhatsApp de cada cliente. No hay
-- una fuente limpia. Este tabla la consolida: un job en la Mini lee lo
-- alcanzable (memoria de WhatsApp + formulario) y con Codex CLI extrae el
-- stack estructurado; Mati lo confirma/edita (revisado=true). Alimenta las
-- recomendaciones del domingo y, mas adelante, se muestra en la app.
--
-- Una fila por cliente (el stack ACTUAL, upsert por cliente_id).
-- ============================================================

CREATE TABLE IF NOT EXISTS mypump_suplementos (
  cliente_id     TEXT        PRIMARY KEY,
  items          JSONB       NOT NULL DEFAULT '[]'::jsonb,  -- [{nombre,dosis,timing}]
  resumen        TEXT,
  fuente         TEXT        DEFAULT 'whatsapp',  -- whatsapp|form|videollamada|mixto|manual
  confianza      TEXT        DEFAULT 'baja'  CHECK (confianza IN ('alta','media','baja')),
  revisado       BOOLEAN     NOT NULL DEFAULT false,   -- Mati confirmo el stack
  notas          TEXT,
  actualizado_en TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE mypump_suplementos ENABLE ROW LEVEL SECURITY;

CREATE POLICY "admin all mypump_suplementos"
  ON mypump_suplementos FOR ALL
  USING (auth.role() = 'authenticated')
  WITH CHECK (auth.role() = 'authenticated');

-- RPC para la app del cliente (a futuro): su propio stack por token.
CREATE OR REPLACE FUNCTION mypump_get_suplementos(p_token TEXT)
RETURNS SETOF mypump_suplementos
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_cliente_id TEXT;
BEGIN
  v_cliente_id := mypump_get_cliente_id_from_token(p_token);
  IF v_cliente_id IS NULL THEN RETURN; END IF;
  RETURN QUERY SELECT * FROM mypump_suplementos WHERE cliente_id = v_cliente_id;
END;
$$;

GRANT EXECUTE ON FUNCTION mypump_get_suplementos(TEXT) TO anon, authenticated;

-- El job de consolidacion (Mini) escribe con service_role (bypassa RLS).
-- El Cerebro (authenticated) lee/edita por la policy de arriba.

-- ============================================================
-- ROLLBACK:
--   DROP FUNCTION IF EXISTS mypump_get_suplementos(TEXT);
--   DROP TABLE IF EXISTS mypump_suplementos;
-- ============================================================
