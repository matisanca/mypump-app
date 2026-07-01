-- ============================================================
-- 023 — Guardrails de performance tras la saturación del 1-jul
-- ============================================================
-- El 1-jul el Disk IO del instance (Nano) se agotó y la DB quedó colgada
-- (pool tapado, ni el SQL editor entraba) → MyPump caído para todos los
-- clientes. Causas: Cerebro y el bot reescribían el blob COMPLETO de
-- nutriplan_data (~3 MB) en cada guardado, y las queries colgadas se
-- acumulaban sin límite hasta tapar el pool.
--
-- Tres guardrails:
--  1) statement_timeout en los roles de la API → una query lenta muere a
--     los 10s en vez de acumularse (mata el espiral de la muerte).
--  2) RPC bot_merge_client → el bot escribe SOLO el cliente que cambió
--     (jsonb_set server-side, ~100 kB) en vez del blob entero (~3 MB).
--  3) (aplicados aparte) Cerebro slim: planHistory fuera de la nube +
--     debounce 6s; autovacuum agresivo en nutriplan_data (ya corrido).
-- ============================================================

-- ── 1) VACUNA: timeout de 10s para todas las queries de la API ──
-- PostgREST conecta como authenticator y hace SET ROLE anon/authenticated.
ALTER ROLE authenticator SET statement_timeout = '10s';
ALTER ROLE anon SET statement_timeout = '10s';
ALTER ROLE authenticated SET statement_timeout = '10s';

-- ── 2) RPC: merge de UN cliente en el blob nutriplan_data ──
-- El bot la usa como fast-path (fallback automático al PATCH completo si
-- no existe). NO se le da EXECUTE a anon: el bot usa su key de servicio.
CREATE OR REPLACE FUNCTION bot_merge_client(
  p_row_id    TEXT,
  p_client_id TEXT,
  p_client    JSONB
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE nutriplan_data
     SET payload    = jsonb_set(payload, ARRAY['clients', p_client_id], p_client, true),
         updated_at = NOW()
   WHERE id = p_row_id;
  RETURN FOUND;
END;
$$;

REVOKE ALL ON FUNCTION bot_merge_client(TEXT, TEXT, JSONB) FROM PUBLIC;
REVOKE ALL ON FUNCTION bot_merge_client(TEXT, TEXT, JSONB) FROM anon;
GRANT EXECUTE ON FUNCTION bot_merge_client(TEXT, TEXT, JSONB) TO service_role;
GRANT EXECUTE ON FUNCTION bot_merge_client(TEXT, TEXT, JSONB) TO authenticated;
