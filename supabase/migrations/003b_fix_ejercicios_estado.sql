-- ============================================================
-- 003b — Fix integral del feature "marcar ejercicio como hecho"
-- ============================================================
-- 1) Corrige columna token → cliente_id (usaba nombre de columna inexistente)
-- 2) Renombra estado → status, updated_at → marcado_en
-- 3) Agrega campos faltantes: rutina_id, dia_id, series_objetivo,
--    series_completadas, marcado_manualmente
-- 4) Reemplaza UNIQUE constraint (token+sesion+ej → sesion+ej)
-- 5) Reemplaza ambas RPC functions con validación correcta del token
-- ============================================================

-- 1. Drop funciones viejas (todas las firmas posibles) --------
DROP FUNCTION IF EXISTS mypump_marcar_ejercicio_estado(TEXT, UUID, TEXT, TEXT);
DROP FUNCTION IF EXISTS mypump_marcar_ejercicio_estado(TEXT, UUID, TEXT, TEXT, INTEGER, TEXT, BOOLEAN);
DROP FUNCTION IF EXISTS mypump_get_ejercicios_estado(TEXT, UUID);

-- 2. Renombrar columnas (idempotente via DO blocks) -----------

-- token → cliente_id
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'mypump_ejercicios_estado' AND column_name = 'token'
  ) THEN
    ALTER TABLE mypump_ejercicios_estado RENAME COLUMN token TO cliente_id;
  END IF;
END $$;

-- estado → status
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'mypump_ejercicios_estado' AND column_name = 'estado'
  ) THEN
    ALTER TABLE mypump_ejercicios_estado RENAME COLUMN estado TO status;
  END IF;
END $$;

-- updated_at → marcado_en
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'mypump_ejercicios_estado' AND column_name = 'updated_at'
  ) AND NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'mypump_ejercicios_estado' AND column_name = 'marcado_en'
  ) THEN
    ALTER TABLE mypump_ejercicios_estado RENAME COLUMN updated_at TO marcado_en;
  END IF;
END $$;

-- 3. Agregar columnas faltantes (idempotente) -----------------
ALTER TABLE mypump_ejercicios_estado
  ADD COLUMN IF NOT EXISTS rutina_id          UUID,
  ADD COLUMN IF NOT EXISTS dia_id             TEXT,
  ADD COLUMN IF NOT EXISTS series_objetivo    INTEGER,
  ADD COLUMN IF NOT EXISTS series_completadas INTEGER     NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS marcado_manualmente BOOLEAN    NOT NULL DEFAULT FALSE;

-- 4. Backfill rutina_id y dia_id desde mypump_sesiones --------
-- (seguro incluso con 0 filas)
UPDATE mypump_ejercicios_estado e
SET
  rutina_id = s.rutina_id,
  dia_id    = s.dia_id
FROM mypump_sesiones s
WHERE e.sesion_id = s.id
  AND (e.rutina_id IS NULL OR e.dia_id IS NULL);

-- Hacer dia_id NOT NULL ahora que está completo
ALTER TABLE mypump_ejercicios_estado
  ALTER COLUMN dia_id SET DEFAULT 'unknown';

UPDATE mypump_ejercicios_estado
  SET dia_id = 'unknown' WHERE dia_id IS NULL;

ALTER TABLE mypump_ejercicios_estado
  ALTER COLUMN dia_id SET NOT NULL;

-- 5. Fix UNIQUE constraint ------------------------------------
-- Puede llamarse de distintas formas según PostgreSQL version
ALTER TABLE mypump_ejercicios_estado
  DROP CONSTRAINT IF EXISTS mypump_ejercicios_estado_token_sesion_id_ejercicio_id_key;
ALTER TABLE mypump_ejercicios_estado
  DROP CONSTRAINT IF EXISTS mypump_ejercicios_estado_cliente_id_sesion_id_ejercicio_id_key;
ALTER TABLE mypump_ejercicios_estado
  DROP CONSTRAINT IF EXISTS mypump_ejercicios_estado_sesion_id_ejercicio_id_key;

ALTER TABLE mypump_ejercicios_estado
  ADD CONSTRAINT mypump_ejercicios_estado_sesion_ejercicio_uq
  UNIQUE (sesion_id, ejercicio_id);

-- 6. Fix CHECK constraint de status ---------------------------
ALTER TABLE mypump_ejercicios_estado
  DROP CONSTRAINT IF EXISTS mypump_ejercicios_estado_estado_check,
  DROP CONSTRAINT IF EXISTS mypump_ejercicios_estado_status_check;

ALTER TABLE mypump_ejercicios_estado
  ADD CONSTRAINT mypump_ejercicios_estado_status_check
  CHECK (status IN ('pendiente', 'completo', 'completo_sin_datos', 'saltado'));

-- 7. Recrear índice con nombre correcto ----------------------
DROP INDEX IF EXISTS idx_eje_estado_token_sesion;
CREATE INDEX IF NOT EXISTS idx_eje_estado_cliente_sesion
  ON mypump_ejercicios_estado (cliente_id, sesion_id);

-- 8. RPC: marcar/actualizar estado (versión completa) --------
CREATE OR REPLACE FUNCTION mypump_marcar_ejercicio_estado(
  p_token              TEXT,
  p_sesion_id          UUID,
  p_dia_id             TEXT,
  p_ejercicio_id       TEXT,
  p_series_objetivo    INTEGER,
  p_status             TEXT,
  p_marcado_manualmente BOOLEAN DEFAULT FALSE
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_cliente_id         TEXT;
  v_rutina_id          UUID;
  v_series_completadas INTEGER;
  v_estado_id          UUID;
BEGIN
  -- Validación usando el helper existente (mismo patrón que todo el schema)
  v_cliente_id := mypump_get_cliente_id_from_token(p_token);
  IF v_cliente_id IS NULL THEN RETURN NULL; END IF;

  -- Verificar que la sesión pertenece al cliente
  SELECT rutina_id INTO v_rutina_id
  FROM mypump_sesiones
  WHERE id = p_sesion_id AND cliente_id = v_cliente_id;

  IF v_rutina_id IS NULL THEN RETURN NULL; END IF;

  -- Contar series con datos reales para este ejercicio en esta sesión
  SELECT COUNT(*) INTO v_series_completadas
  FROM mypump_registros_carga
  WHERE sesion_id    = p_sesion_id
    AND ejercicio_id = p_ejercicio_id
    AND peso_kg      IS NOT NULL;

  -- UPSERT
  INSERT INTO mypump_ejercicios_estado (
    cliente_id, sesion_id, rutina_id, dia_id, ejercicio_id,
    status, series_objetivo, series_completadas,
    marcado_manualmente, marcado_en
  ) VALUES (
    v_cliente_id, p_sesion_id, v_rutina_id, p_dia_id, p_ejercicio_id,
    p_status, p_series_objetivo, v_series_completadas,
    p_marcado_manualmente, NOW()
  )
  ON CONFLICT (sesion_id, ejercicio_id) DO UPDATE SET
    status               = EXCLUDED.status,
    series_objetivo      = EXCLUDED.series_objetivo,
    series_completadas   = EXCLUDED.series_completadas,
    marcado_manualmente  = EXCLUDED.marcado_manualmente,
    marcado_en           = EXCLUDED.marcado_en
  RETURNING id INTO v_estado_id;

  RETURN v_estado_id;
END;
$$;

-- 9. RPC: obtener estados de una sesión ----------------------
CREATE OR REPLACE FUNCTION mypump_get_ejercicios_estado(
  p_token     TEXT,
  p_sesion_id UUID
)
RETURNS SETOF mypump_ejercicios_estado
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
    SELECT *
    FROM   mypump_ejercicios_estado
    WHERE  sesion_id  = p_sesion_id
      AND  cliente_id = v_cliente_id
    ORDER BY marcado_en ASC NULLS LAST;
END;
$$;

-- 10. Grants -------------------------------------------------
GRANT EXECUTE ON FUNCTION mypump_marcar_ejercicio_estado(TEXT, UUID, TEXT, TEXT, INTEGER, TEXT, BOOLEAN) TO anon;
GRANT EXECUTE ON FUNCTION mypump_get_ejercicios_estado(TEXT, UUID) TO anon;
