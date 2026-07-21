-- ============================================================
-- 040 - Segundo mensaje al cliente: el del AJUSTE / a charlar
-- ============================================================
-- El analisis ya guarda 'mensaje_cliente' (la devolucion general del check).
-- Cuando hay algo que ajustar o charlar del entreno (balde=ajustar), Mati
-- quiere un SEGUNDO draft aparte, mas puntual: que haga referencia a lo que
-- paso (entreno flojo, fuerza que no acompana, etc.) y le pregunte para
-- entenderlo e intentar resolverlo. Se muestra en un segundo recuadro del panel.
--
-- Es client-facing (a diferencia de sugerencia_coach, que es solo para Mati).
-- ============================================================

ALTER TABLE mypump_analisis_semanal
  ADD COLUMN IF NOT EXISTS mensaje_ajuste TEXT;

-- ── upsert: se le agrega el nuevo campo. Se DROPEA y recrea (cambia la firma). ──
DROP FUNCTION IF EXISTS mypump_upsert_analisis(TEXT, DATE, TEXT, JSONB, JSONB, JSONB, TEXT, TEXT);

CREATE OR REPLACE FUNCTION mypump_upsert_analisis(
  p_cliente_id       TEXT,
  p_semana_lunes     DATE,
  p_balde            TEXT,
  p_motivos          JSONB   DEFAULT '[]'::jsonb,
  p_banderas         JSONB   DEFAULT '[]'::jsonb,
  p_senales          JSONB   DEFAULT '{}'::jsonb,
  p_mensaje_cliente  TEXT    DEFAULT NULL,
  p_sugerencia_coach TEXT    DEFAULT NULL,
  p_mensaje_ajuste   TEXT    DEFAULT NULL
) RETURNS mypump_analisis_semanal
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row mypump_analisis_semanal;
BEGIN
  INSERT INTO mypump_analisis_semanal (
    cliente_id, semana_lunes, balde, motivos, banderas, senales,
    mensaje_cliente, sugerencia_coach, mensaje_ajuste, corrida_el
  ) VALUES (
    p_cliente_id, p_semana_lunes, p_balde, p_motivos, p_banderas, p_senales,
    p_mensaje_cliente, p_sugerencia_coach, p_mensaje_ajuste, NOW()
  )
  ON CONFLICT (cliente_id, semana_lunes) DO UPDATE SET
    balde            = EXCLUDED.balde,
    motivos          = EXCLUDED.motivos,
    banderas         = EXCLUDED.banderas,
    senales          = EXCLUDED.senales,
    mensaje_cliente  = EXCLUDED.mensaje_cliente,
    sugerencia_coach = EXCLUDED.sugerencia_coach,
    mensaje_ajuste   = EXCLUDED.mensaje_ajuste,
    corrida_el       = NOW(),
    resuelto_el      = CASE
                         WHEN mypump_analisis_semanal.balde = EXCLUDED.balde
                           THEN mypump_analisis_semanal.resuelto_el
                         ELSE NULL
                       END
  RETURNING * INTO v_row;
  RETURN v_row;
END;
$$;

REVOKE ALL ON FUNCTION mypump_upsert_analisis(TEXT, DATE, TEXT, JSONB, JSONB, JSONB, TEXT, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION mypump_upsert_analisis(TEXT, DATE, TEXT, JSONB, JSONB, JSONB, TEXT, TEXT, TEXT)
  TO service_role, authenticated;

-- ── pendientes: sumar mensaje_ajuste al output (get_analisis_cliente ya lo
--    trae solo por ser SETOF de la tabla). ──
DROP FUNCTION IF EXISTS mypump_get_analisis_pendientes(DATE);

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
  mensaje_ajuste    TEXT,
  corrida_el        TIMESTAMPTZ
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT a.cliente_id, c.nombre, a.semana_lunes, a.balde, a.motivos,
         a.banderas, a.senales, a.mensaje_cliente, a.sugerencia_coach,
         a.mensaje_ajuste, a.corrida_el
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
-- ROLLBACK:
--   DROP FUNCTION IF EXISTS mypump_get_analisis_pendientes(DATE);
--   DROP FUNCTION IF EXISTS mypump_upsert_analisis(TEXT, DATE, TEXT, JSONB, JSONB, JSONB, TEXT, TEXT, TEXT);
--   ALTER TABLE mypump_analisis_semanal DROP COLUMN IF EXISTS mensaje_ajuste;
--   (y recrear las versiones de 039)
-- ============================================================
