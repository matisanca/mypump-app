-- ============================================================
-- 039 - Analisis semanal persistido (veredicto del centinela)
-- ============================================================
-- Hasta ahora el centinela evaluaba a cada cliente y mandaba el
-- WhatsApp, pero el veredicto se perdia: vivia y moria en la corrida.
-- Esta tabla lo persiste, para tres cosas:
--   1) el panel del coach lee "que hay que revisar hoy" (balde=ajustar
--      sin resolver) y Mati lo marca como resuelto desde ahi;
--   2) cada cliente muestra su ultimo analisis en el dashboard, y sirve
--      de insumo para el brief pre-call;
--   3) el bot corre lun-jue a medida que llegan los checks: cada corrida
--      hace UPSERT sobre la fila de la semana (un cliente que el lunes
--      estaba sin_check pasa a su balde real cuando manda el check).
--
-- El bot escribe con service key (REST directo, como todo el centinela).
-- El panel lee con las RPC de abajo (rol authenticated = Mati logueado).
--
-- IMPORTANTE sobre resuelto_el: lo setea Mati desde el panel. El UPSERT
-- del bot NO lo pisa salvo que el balde cambie (si vuelve a "ajustar" por
-- una senal nueva, se re-abre). Eso se maneja en la RPC de upsert.
-- ============================================================

CREATE TABLE IF NOT EXISTS mypump_analisis_semanal (
  id                UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  cliente_id        TEXT        NOT NULL,
  semana_lunes      DATE        NOT NULL,   -- lunes ISO de la semana analizada
  balde             TEXT        NOT NULL
                                CHECK (balde IN ('ajustar','observar','bien','sin_check')),
  motivos           JSONB       NOT NULL DEFAULT '[]'::jsonb,  -- del motor de reglas
  banderas          JSONB       NOT NULL DEFAULT '[]'::jsonb,  -- lesion/viaje/enfermedad/etc de la nota
  senales           JSONB       NOT NULL DEFAULT '{}'::jsonb,  -- perfiles + cruces + carga/e1rm/adherencia (para el brief)
  mensaje_cliente   TEXT,       -- draft redactado para reenviar al cliente (opcional para Mati)
  sugerencia_coach  TEXT,       -- ajustes concretos, SOLO para el coach
  corrida_el        TIMESTAMPTZ NOT NULL DEFAULT NOW(),  -- ultima vez que el bot la evaluo
  resuelto_el       TIMESTAMPTZ,            -- Mati lo marca desde el panel; NULL = pendiente
  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (cliente_id, semana_lunes)
);

CREATE INDEX IF NOT EXISTS idx_mypump_analisis_cliente_semana
  ON mypump_analisis_semanal (cliente_id, semana_lunes DESC);

-- Para el panel: "que revisar" = ajustar de la semana en curso sin resolver
CREATE INDEX IF NOT EXISTS idx_mypump_analisis_pendientes
  ON mypump_analisis_semanal (semana_lunes, balde)
  WHERE resuelto_el IS NULL;

ALTER TABLE mypump_analisis_semanal ENABLE ROW LEVEL SECURITY;

CREATE POLICY "admin all mypump_analisis_semanal"
  ON mypump_analisis_semanal FOR ALL
  USING (auth.role() = 'authenticated')
  WITH CHECK (auth.role() = 'authenticated');

-- ============================================================
-- RPC 1: UPSERT del analisis (la usa el bot con service key).
-- Preserva resuelto_el salvo que el balde haya cambiado respecto de lo
-- guardado: si un cliente ya resuelto vuelve a "ajustar", se re-abre.
-- ============================================================
CREATE OR REPLACE FUNCTION mypump_upsert_analisis(
  p_cliente_id       TEXT,
  p_semana_lunes     DATE,
  p_balde            TEXT,
  p_motivos          JSONB   DEFAULT '[]'::jsonb,
  p_banderas         JSONB   DEFAULT '[]'::jsonb,
  p_senales          JSONB   DEFAULT '{}'::jsonb,
  p_mensaje_cliente  TEXT    DEFAULT NULL,
  p_sugerencia_coach TEXT    DEFAULT NULL
) RETURNS mypump_analisis_semanal
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_prev  mypump_analisis_semanal;
  v_row   mypump_analisis_semanal;
BEGIN
  SELECT * INTO v_prev FROM mypump_analisis_semanal
    WHERE cliente_id = p_cliente_id AND semana_lunes = p_semana_lunes;

  INSERT INTO mypump_analisis_semanal (
    cliente_id, semana_lunes, balde, motivos, banderas, senales,
    mensaje_cliente, sugerencia_coach, corrida_el
  ) VALUES (
    p_cliente_id, p_semana_lunes, p_balde, p_motivos, p_banderas, p_senales,
    p_mensaje_cliente, p_sugerencia_coach, NOW()
  )
  ON CONFLICT (cliente_id, semana_lunes) DO UPDATE SET
    balde            = EXCLUDED.balde,
    motivos          = EXCLUDED.motivos,
    banderas         = EXCLUDED.banderas,
    senales          = EXCLUDED.senales,
    mensaje_cliente  = EXCLUDED.mensaje_cliente,
    sugerencia_coach = EXCLUDED.sugerencia_coach,
    corrida_el       = NOW(),
    -- Si ya estaba resuelto y el balde NO cambio, se mantiene resuelto.
    -- Si el balde cambio (p.ej. paso a 'ajustar' de nuevo), se re-abre.
    resuelto_el      = CASE
                         WHEN mypump_analisis_semanal.balde = EXCLUDED.balde
                           THEN mypump_analisis_semanal.resuelto_el
                         ELSE NULL
                       END
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;

REVOKE ALL ON FUNCTION mypump_upsert_analisis(TEXT, DATE, TEXT, JSONB, JSONB, JSONB, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION mypump_upsert_analisis(TEXT, DATE, TEXT, JSONB, JSONB, JSONB, TEXT, TEXT)
  TO service_role, authenticated;

-- ============================================================
-- RPC 2: lo pendiente de la semana en curso, para "revisar hoy".
-- Devuelve solo lo accionable (ajustar) sin resolver, mas nombre.
-- ============================================================
CREATE OR REPLACE FUNCTION mypump_get_analisis_pendientes(
  p_semana_lunes DATE DEFAULT NULL
) RETURNS TABLE (
  cliente_id        TEXT,
  nombre            TEXT,
  semana_lunes      DATE,
  balde             TEXT,
  motivos           JSONB,
  banderas          JSONB,
  senales           JSONB,
  mensaje_cliente   TEXT,
  sugerencia_coach  TEXT,
  corrida_el        TIMESTAMPTZ
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT a.cliente_id, c.nombre, a.semana_lunes, a.balde, a.motivos,
         a.banderas, a.senales, a.mensaje_cliente, a.sugerencia_coach, a.corrida_el
  FROM mypump_analisis_semanal a
  LEFT JOIN mypump_clientes c ON c.cliente_id = a.cliente_id
  WHERE a.resuelto_el IS NULL
    AND a.balde = 'ajustar'
    AND a.semana_lunes = COALESCE(
          p_semana_lunes,
          (CURRENT_DATE - ((EXTRACT(ISODOW FROM CURRENT_DATE)::int - 1)))
        )
  ORDER BY a.corrida_el DESC;
$$;

GRANT EXECUTE ON FUNCTION mypump_get_analisis_pendientes(DATE) TO authenticated;

-- ============================================================
-- RPC 3: el analisis mas reciente de UN cliente (dashboard + brief).
-- ============================================================
CREATE OR REPLACE FUNCTION mypump_get_analisis_cliente(
  p_cliente_id TEXT,
  p_limite     INTEGER DEFAULT 8
) RETURNS SETOF mypump_analisis_semanal
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT * FROM mypump_analisis_semanal
  WHERE cliente_id = p_cliente_id
  ORDER BY semana_lunes DESC
  LIMIT GREATEST(1, p_limite);
$$;

GRANT EXECUTE ON FUNCTION mypump_get_analisis_cliente(TEXT, INTEGER) TO authenticated;

-- ============================================================
-- RPC 4: marcar como resuelto desde el panel (Mati).
-- ============================================================
CREATE OR REPLACE FUNCTION mypump_resolver_analisis(
  p_cliente_id   TEXT,
  p_semana_lunes DATE
) RETURNS mypump_analisis_semanal
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row mypump_analisis_semanal;
BEGIN
  UPDATE mypump_analisis_semanal
    SET resuelto_el = NOW()
    WHERE cliente_id = p_cliente_id AND semana_lunes = p_semana_lunes
    RETURNING * INTO v_row;
  RETURN v_row;
END;
$$;

GRANT EXECUTE ON FUNCTION mypump_resolver_analisis(TEXT, DATE) TO authenticated;

-- ============================================================
-- ROLLBACK (para revertir a mano si hiciera falta):
--   DROP FUNCTION IF EXISTS mypump_resolver_analisis(TEXT, DATE);
--   DROP FUNCTION IF EXISTS mypump_get_analisis_cliente(TEXT, INTEGER);
--   DROP FUNCTION IF EXISTS mypump_get_analisis_pendientes(DATE);
--   DROP FUNCTION IF EXISTS mypump_upsert_analisis(TEXT, DATE, TEXT, JSONB, JSONB, JSONB, TEXT, TEXT);
--   DROP TABLE IF EXISTS mypump_analisis_semanal;
-- ============================================================
