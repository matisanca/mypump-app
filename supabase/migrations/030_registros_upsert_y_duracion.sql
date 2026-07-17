-- ============================================================
-- 030 — Guardado confiable: upsert de series + duración de sesión (FASE 2)
-- ============================================================
-- Reporte del cliente: "algunos ejercicios no se guardan" y "el tiempo total
-- queda mal (20 min cuando entrenó mucho más)".
--
-- CAUSAS (auditadas):
-- 1. mypump_registrar_carga hace INSERT a secas: editar una serie confirmada y
--    re-confirmarla crea una fila DUPLICADA con el mismo (sesion_id,
--    ejercicio_id, serie_numero). El restore y el histórico levantan la fila
--    vieja o duplicada → "no se guardó lo que corregí".
-- 2. La duración de la sesión no se persiste en ningún lado: el front la
--    calcula en memoria y se pierde con un reload; el server solo tiene
--    iniciada_en (que además arranca en la primera serie confirmada, no al
--    empezar a entrenar).
--
-- FIX:
-- 1. Dedup de filas existentes (conservar la más reciente por terna) +
--    UNIQUE INDEX + ON CONFLICT DO UPDATE en la RPC (editar ACTUALIZA).
-- 2. Columna duracion_segundos + mypump_finalizar_sesion la recibe del front
--    (wall-clock real desde que el cliente empezó), cap server-side a 6 h.
-- ============================================================

-- ── 1) Dedup: conservar la fila más reciente por (sesion_id, ejercicio_id, serie_numero)
DELETE FROM mypump_registros_carga a
USING mypump_registros_carga b
WHERE a.sesion_id     = b.sesion_id
  AND a.ejercicio_id  = b.ejercicio_id
  AND a.serie_numero  = b.serie_numero
  AND (a.registrado_en < b.registrado_en
       OR (a.registrado_en = b.registrado_en AND a.id < b.id));

-- ── 2) Unicidad por serie dentro de la sesión
CREATE UNIQUE INDEX IF NOT EXISTS uq_mypump_registros_serie
  ON mypump_registros_carga (sesion_id, ejercicio_id, serie_numero);

-- ── 3) registrar_carga → UPSERT (editar una serie actualiza, no duplica)
CREATE OR REPLACE FUNCTION mypump_registrar_carga(
  p_token            TEXT,
  p_sesion_id        UUID,
  p_dia_id           TEXT,
  p_ejercicio_id     TEXT,
  p_ejercicio_nombre TEXT,
  p_serie            INTEGER,
  p_peso             NUMERIC,
  p_reps             INTEGER,
  p_rir              INTEGER,
  p_notas            TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_cliente_id  TEXT;
  v_rutina_id   UUID;
  v_registro_id UUID;
BEGIN
  v_cliente_id := mypump_get_cliente_id_from_token(p_token);
  IF v_cliente_id IS NULL THEN RETURN NULL; END IF;

  SELECT rutina_id INTO v_rutina_id
  FROM mypump_sesiones
  WHERE id = p_sesion_id AND cliente_id = v_cliente_id;
  IF v_rutina_id IS NULL THEN RETURN NULL; END IF;

  INSERT INTO mypump_registros_carga (
    cliente_id, rutina_id, sesion_id, dia_id,
    ejercicio_id, ejercicio_nombre,
    serie_numero, peso_kg, reps_realizadas, rir_real, notas
  )
  VALUES (
    v_cliente_id, v_rutina_id, p_sesion_id, p_dia_id,
    p_ejercicio_id, p_ejercicio_nombre,
    p_serie, p_peso, p_reps, p_rir, p_notas
  )
  ON CONFLICT (sesion_id, ejercicio_id, serie_numero) DO UPDATE
    SET peso_kg          = EXCLUDED.peso_kg,
        reps_realizadas  = EXCLUDED.reps_realizadas,
        rir_real         = EXCLUDED.rir_real,
        notas            = EXCLUDED.notas,
        ejercicio_nombre = EXCLUDED.ejercicio_nombre
        -- registrado_en se conserva (momento real en que hizo la serie)
  RETURNING id INTO v_registro_id;

  RETURN v_registro_id;
END;
$$;

-- ── 4) Duración de la sesión
ALTER TABLE mypump_sesiones
  ADD COLUMN IF NOT EXISTS duracion_segundos INTEGER;

-- Se reemplaza la firma de 3 args para no dejar overloads ambiguos (patrón 026).
DROP FUNCTION IF EXISTS mypump_finalizar_sesion(TEXT, UUID, TEXT);

CREATE OR REPLACE FUNCTION mypump_finalizar_sesion(
  p_token             TEXT,
  p_sesion_id         UUID,
  p_notas             TEXT,
  p_duracion_segundos INTEGER DEFAULT NULL
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_cliente_id TEXT;
  v_rows       INTEGER;
BEGIN
  v_cliente_id := mypump_get_cliente_id_from_token(p_token);
  IF v_cliente_id IS NULL THEN RETURN FALSE; END IF;

  UPDATE mypump_sesiones
  SET finalizada_en     = NOW(),
      notas_sesion      = p_notas,
      -- Cap de cordura: 10 s .. 6 h (contra relojes corridos / tabs olvidadas)
      duracion_segundos = CASE
        WHEN p_duracion_segundos IS NULL THEN duracion_segundos
        ELSE GREATEST(10, LEAST(21600, p_duracion_segundos))
      END
  WHERE id = p_sesion_id AND cliente_id = v_cliente_id;

  GET DIAGNOSTICS v_rows = ROW_COUNT;
  RETURN v_rows > 0;
END;
$$;

GRANT EXECUTE ON FUNCTION mypump_registrar_carga(TEXT, UUID, TEXT, TEXT, TEXT, INTEGER, NUMERIC, INTEGER, INTEGER, TEXT)
  TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION mypump_finalizar_sesion(TEXT, UUID, TEXT, INTEGER)
  TO anon, authenticated, service_role;

-- ============================================================
-- ROLLBACK (revierte esta migración; el dedup del paso 1 no es reversible
-- pero solo eliminó duplicados exactos que eran el bug):
--
-- DROP INDEX IF EXISTS uq_mypump_registros_serie;
-- ALTER TABLE mypump_sesiones DROP COLUMN IF EXISTS duracion_segundos;
-- DROP FUNCTION IF EXISTS mypump_finalizar_sesion(TEXT, UUID, TEXT, INTEGER);
-- -- Restaurar registrar_carga original (INSERT sin ON CONFLICT): re-correr la
-- -- definición de 001_mypump_schema.sql líneas 434-479.
-- -- Restaurar finalizar_sesion original (3 args): re-correr 001 líneas 515-539
-- -- + GRANT EXECUTE ... (TEXT, UUID, TEXT) TO anon;
-- ============================================================
