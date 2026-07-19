-- ============================================================
-- 037 - Quimica / ciclo consolidado por cliente (SOLO COACH)
-- ============================================================
-- Reconciliacion clinica: que esta usando cada cliente (AAS, orales,
-- GH, insulina, peptidos, y ancilares AI/SERM/HCG). Hoy esta disperso en
-- el chat de WhatsApp, en las videollamadas de entrega y en farmaData del
-- Cerebro. Un job en la Mini lo consolida con Codex CLI y Mati (medico) lo
-- confirma. Es informacion CONFIDENCIAL de uso clinico del coach.
--
-- SEGURIDAD CRITICA: esta tabla es SOLO para el coach (rol authenticated,
-- el Cerebro logueado). NO hay RPC por token de cliente ni acceso anon:
-- esta info NUNCA debe llegar a la app del cliente. Por eso, a diferencia
-- de mypump_suplementos, aca NO se crea ninguna funcion get-por-token.
-- ============================================================

CREATE TABLE IF NOT EXISTS mypump_quimica (
  cliente_id     TEXT        PRIMARY KEY,
  items          JSONB       NOT NULL DEFAULT '[]'::jsonb,  -- [{compuesto,dosis,frecuencia,semanas,tipo}]
  protocolo      TEXT,        -- resumen del ciclo/fase en texto
  fase           TEXT,        -- on-cycle | off | pct | trt | cruise | sin datos
  confianza      TEXT        DEFAULT 'baja'  CHECK (confianza IN ('alta','media','baja')),
  revisado       BOOLEAN     NOT NULL DEFAULT false,
  notas          TEXT,
  actualizado_en TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE mypump_quimica ENABLE ROW LEVEL SECURITY;

-- SOLO authenticated (coach). Sin policy para anon = anon no ve nada.
CREATE POLICY "coach only mypump_quimica"
  ON mypump_quimica FOR ALL
  USING (auth.role() = 'authenticated')
  WITH CHECK (auth.role() = 'authenticated');

-- El job de la Mini escribe con service_role (bypassa RLS).
-- NO se crea ninguna funcion SECURITY DEFINER por token: la app del
-- cliente jamas debe poder leer esta tabla.

-- ============================================================
-- ROLLBACK:
--   DROP TABLE IF EXISTS mypump_quimica;
-- ============================================================
