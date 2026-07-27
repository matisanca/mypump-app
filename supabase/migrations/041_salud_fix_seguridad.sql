-- ============================================================
-- 041 — Salud: cerrar escritura pública + destrabar los tipos nuevos
-- ============================================================
-- Dos bugs que venían desde la 027 y que juntos dejaron muerto el pipeline
-- de wearables sin que nadie lo notara (la card se auto-oculta si no hay datos).
--
-- BUG A (seguridad).  En Postgres, CREATE FUNCTION otorga EXECUTE a PUBLIC por
-- defecto. La 027 hizo `GRANT ... TO service_role` sobre
-- mypump_ingest_salud_service, que es un no-op sobre un permiso ya abierto, y
-- nunca hizo el REVOKE. Verificado en producción: con la anon key —que es
-- pública por diseño, está commiteada en public/js/config.js— cualquiera podía
-- ejecutar mypump_ingest_salud_service y _mypump_upsert_salud (HTTP 200) y
-- escribir registros de salud para cualquier cliente_id arbitrario, salteándose
-- por completo el X-Salud-Secret del webhook. Las dos son SECURITY DEFINER y no
-- validan token ni existencia del cliente: confían en quien las llama.
--
-- BUG B (datos).  _mypump_upsert_salud tenía la lista de tipos válidos
-- hardcodeada (027:73). La migración 032 amplió el CHECK de la tabla con
-- 'hrv_ms' pero no tocó la función, así que el HRV llegaba y se descartaba en
-- silencio: el CONTINUE ni siquiera incrementa el contador, así que el
-- `ingresados` que devuelve la RPC tampoco lo delataba.
--
-- El fix de B no es ampliar la lista —eso repite el mismo drift en la próxima
-- migración que agregue un tipo— sino BORRARLA: se deja que el CHECK de la
-- tabla sea la única fuente de verdad y se atrapa check_violation por registro.
-- ============================================================

-- ============================================================
-- 1. Helper de upsert: sin whitelist propia (el CHECK de la tabla manda)
-- ============================================================
-- CREATE OR REPLACE conserva el ACL existente; los REVOKE van igual más abajo
-- porque el ACL existente es justamente el que está mal.
CREATE OR REPLACE FUNCTION _mypump_upsert_salud(
  p_cliente_id     TEXT,
  p_registros      JSONB,
  p_fuente_default TEXT
)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count  INTEGER := 0;
  v_rec    JSONB;
  v_tipo   TEXT;
  v_fuente TEXT;
  v_fecha  DATE;
  v_valor  NUMERIC;
BEGIN
  IF p_cliente_id IS NULL THEN RETURN 0; END IF;
  IF p_registros IS NULL OR jsonb_typeof(p_registros) <> 'array' THEN RETURN 0; END IF;

  FOR v_rec IN SELECT * FROM jsonb_array_elements(p_registros) LOOP
    v_tipo   := v_rec->>'tipo';
    v_fuente := COALESCE(v_rec->>'fuente', p_fuente_default);
    IF v_tipo IS NULL OR v_fuente IS NULL THEN CONTINUE; END IF;

    BEGIN
      v_fecha := (v_rec->>'fecha')::DATE;
      v_valor := (v_rec->>'valor')::NUMERIC;
    EXCEPTION WHEN OTHERS THEN CONTINUE;  -- fecha/valor mal formados → saltar
    END;
    IF v_fecha IS NULL OR v_valor IS NULL THEN CONTINUE; END IF;

    -- Sin lista hardcodeada: si el tipo o la fuente no pasan el CHECK de la
    -- tabla, el INSERT tira check_violation y se saltea ESE registro sin
    -- abortar el lote. Agregar un tipo nuevo pasa a ser una sola línea (el
    -- ALTER del CHECK) en vez de dos que se pueden desincronizar.
    BEGIN
      INSERT INTO mypump_salud_diaria (cliente_id, fecha, tipo, valor, detalle, fuente)
      VALUES (p_cliente_id, v_fecha, v_tipo, v_valor,
              CASE WHEN jsonb_typeof(v_rec->'detalle') IS NOT NULL THEN v_rec->'detalle' ELSE NULL END,
              v_fuente)
      ON CONFLICT (cliente_id, fecha, tipo, fuente) DO UPDATE
        SET valor = EXCLUDED.valor, detalle = EXCLUDED.detalle, updated_at = NOW();
      v_count := v_count + 1;
    EXCEPTION WHEN check_violation THEN CONTINUE;
    END;
  END LOOP;

  RETURN v_count;
END;
$$;

-- ============================================================
-- 2. ACLs: quién puede ejecutar qué
-- ============================================================
-- Helper interno: NADIE lo llama directo. Solo lo invocan las RPCs de arriba,
-- que al ser SECURITY DEFINER corren como owner y no necesitan el grant.
REVOKE ALL ON FUNCTION _mypump_upsert_salud(TEXT, JSONB, TEXT) FROM PUBLIC, anon, authenticated;

-- Vía A (agregador / webhook): solo el server, nunca el browser.
REVOKE ALL    ON FUNCTION mypump_ingest_salud_service(TEXT, JSONB) FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION mypump_ingest_salud_service(TEXT, JSONB) TO service_role;

-- Lectura global (todos los clientes): solo coach logueado y server.
-- Ya tenía el guard interno `auth.role() <> 'authenticated' → RAISE`, pero el
-- guard adentro y el permiso afuera tienen que decir lo mismo.
REVOKE ALL    ON FUNCTION mypump_get_salud_global(INTEGER) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION mypump_get_salud_global(INTEGER) TO authenticated, service_role;

-- mypump_ingest_salud(token,...) y mypump_get_salud(token,...) SÍ siguen
-- abiertas a anon a propósito: son el camino del cliente y validan por token.

-- ============================================================
-- 3. Auditoría de ACLs — correr después de CUALQUIER migración que dropee
--    funciones. `proacl IS NULL` significa "default", o sea EXECUTE a PUBLIC.
--    OJO: CREATE OR REPLACE conserva el ACL, pero DROP + CREATE lo RESETEA.
--    Toda migración que dropee una función tiene que re-aplicar su REVOKE en
--    el mismo archivo (le pasa a mypump_get_metricas_coach en la 044).
--
-- SELECT p.proname, p.proacl
-- FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
-- WHERE n.nspname = 'public'
--   AND (p.proname LIKE 'mypump%' OR p.proname LIKE '\_mypump%')
--   AND p.proacl IS NULL
-- ORDER BY p.proname;
-- ============================================================

-- ============================================================
-- ROLLBACK (vuelve al estado de la 027 — reabre el agujero, no lo hagas salvo
-- que algo se haya roto de verdad):
--
-- GRANT EXECUTE ON FUNCTION _mypump_upsert_salud(TEXT, JSONB, TEXT)      TO PUBLIC;
-- GRANT EXECUTE ON FUNCTION mypump_ingest_salud_service(TEXT, JSONB)     TO PUBLIC;
-- GRANT EXECUTE ON FUNCTION mypump_get_salud_global(INTEGER)             TO PUBLIC;
-- -- y volver a poner la whitelist de 027:73-74 dentro del loop:
-- --   IF v_tipo   NOT IN ('pasos','actividad_min','kcal_activas','fc_reposo','sueno_min','peso_kg') THEN CONTINUE; END IF;
-- --   IF v_fuente NOT IN ('apple_health','rook','manual') THEN CONTINUE; END IF;
-- ============================================================
