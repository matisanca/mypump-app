-- ============================================================
-- MIGRACIÓN 003 — Estado por ejercicio
-- Tabla + 2 RPCs para marcar/leer el estado de cada ejercicio
-- durante una sesión de entrenamiento.
--
-- Estados posibles:
--   pendiente           → aún no completado (estado inicial)
--   completo            → todas las series confirmadas
--   completo_sin_datos  → marcado manualmente sin cargar datos
--   saltado             → el atleta lo saltó/omitió
-- ============================================================

-- 1. Tabla de estados -----------------------------------------
CREATE TABLE IF NOT EXISTS mypump_ejercicios_estado (
  id            UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  token         TEXT        NOT NULL,
  sesion_id     UUID        NOT NULL,
  ejercicio_id  TEXT        NOT NULL,
  estado        TEXT        NOT NULL DEFAULT 'pendiente'
                  CHECK (estado IN ('pendiente','completo','completo_sin_datos','saltado')),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now(),

  UNIQUE (token, sesion_id, ejercicio_id)
);

-- Índices útiles para las lecturas por sesión
CREATE INDEX IF NOT EXISTS idx_eje_estado_token_sesion
  ON mypump_ejercicios_estado (token, sesion_id);

-- 2. RPC: marcar/actualizar estado ----------------------------
CREATE OR REPLACE FUNCTION mypump_marcar_ejercicio_estado(
  p_token        TEXT,
  p_sesion_id    UUID,
  p_ejercicio_id TEXT,
  p_estado       TEXT
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Validar que el token sea legítimo
  IF NOT EXISTS (
    SELECT 1 FROM mypump_clientes WHERE token = p_token
  ) THEN
    RAISE EXCEPTION 'token_invalido';
  END IF;

  -- Validar estado
  IF p_estado NOT IN ('pendiente','completo','completo_sin_datos','saltado') THEN
    RAISE EXCEPTION 'estado_invalido: %', p_estado;
  END IF;

  INSERT INTO mypump_ejercicios_estado
    (token, sesion_id, ejercicio_id, estado, updated_at)
  VALUES
    (p_token, p_sesion_id, p_ejercicio_id, p_estado, now())
  ON CONFLICT (token, sesion_id, ejercicio_id)
  DO UPDATE SET
    estado     = EXCLUDED.estado,
    updated_at = now();
END;
$$;

-- 3. RPC: obtener todos los estados de una sesión -------------
CREATE OR REPLACE FUNCTION mypump_get_ejercicios_estado(
  p_token     TEXT,
  p_sesion_id UUID
)
RETURNS TABLE (
  ejercicio_id TEXT,
  estado       TEXT,
  updated_at   TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Validar token
  IF NOT EXISTS (
    SELECT 1 FROM mypump_clientes WHERE token = p_token
  ) THEN
    RAISE EXCEPTION 'token_invalido';
  END IF;

  RETURN QUERY
  SELECT ee.ejercicio_id, ee.estado, ee.updated_at
  FROM   mypump_ejercicios_estado ee
  WHERE  ee.token = p_token
    AND  ee.sesion_id = p_sesion_id
  ORDER BY ee.updated_at;
END;
$$;

-- 4. Permisos (rol anon, acceso sólo vía RPC) ----------------
GRANT EXECUTE ON FUNCTION mypump_marcar_ejercicio_estado TO anon;
GRANT EXECUTE ON FUNCTION mypump_get_ejercicios_estado   TO anon;
