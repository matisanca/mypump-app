-- =============================================================
-- MyPump — Migration 001: Schema inicial
-- Proyecto: app.mypumpteam.com
-- Supabase project: gydinputrtptqakdzyvc
--
-- AISLAMIENTO CRÍTICO: estas tablas son 100% independientes de
-- nutriplan_data (Cerebro). NUNCA hay foreign keys cruzadas.
-- cliente_id es TEXT (no UUID) que coincide con el ID interno de
-- Cerebro, pero Postgres no lo valida — la fuente está en JSONB.
--
-- ACCESO:
--   anon       → solo via RPC functions con token (SECURITY DEFINER)
--   authenticated → acceso completo (Mati / Cerebro)
-- =============================================================

-- =============================================================
-- HELPER: generador de tokens alfanuméricos de 32 caracteres
-- Usado por mypump_publicar_cliente y mypump_regenerar_token.
-- =============================================================
CREATE OR REPLACE FUNCTION generate_mypump_token()
RETURNS TEXT
LANGUAGE plpgsql
AS $$
DECLARE
  chars  TEXT    := 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
  result TEXT    := '';
  i      INTEGER;
BEGIN
  FOR i IN 1..32 LOOP
    result := result || substr(chars, (random() * 61)::int + 1, 1);
  END LOOP;
  RETURN result;
END;
$$;


-- =============================================================
-- TABLA 1: mypump_clientes
-- Un registro por cliente publicado desde Cerebro.
-- access_token = 32 chars alfanuméricos → URL del cliente.
-- =============================================================
CREATE TABLE IF NOT EXISTS mypump_clientes (
  id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  cliente_id          TEXT        NOT NULL UNIQUE,
  nombre              TEXT        NOT NULL,
  perfil              TEXT        NOT NULL DEFAULT 'natural'
                                  CHECK (perfil IN ('natural', 'farma')),
  access_token        TEXT        NOT NULL UNIQUE,
  access_token_active BOOLEAN     NOT NULL DEFAULT TRUE,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_accessed_at    TIMESTAMPTZ
);

-- Índice de búsqueda por token (solo tokens activos — partial index)
CREATE INDEX IF NOT EXISTS idx_mypump_clientes_token
  ON mypump_clientes(access_token)
  WHERE access_token_active = TRUE;

CREATE INDEX IF NOT EXISTS idx_mypump_clientes_cliente_id
  ON mypump_clientes(cliente_id);


-- =============================================================
-- TABLA 2: mypump_rutinas
-- Rutinas publicadas desde Cerebro, YA EXPANDIDAS con sets×reps.
-- La expansión ocurre en Cerebro (Prompt 3) antes de publicar;
-- cuando MyPump recibe la rutina, ya viene con series y reps.
--
-- Schema esperado del JSONB `estructura`:
-- {
--   "nombre_plan": "Mesociclo 1 - Hipertrofia",
--   "perfil": {
--     "nivel": "intermedio",
--     "split": "PPL x2 — 6 días",
--     "diasSemana": 6,
--     "objetivo": "Hipertrofia",
--     "resumen": "..."
--   },
--   "semanas_total": 12,
--   "dias": [
--     {
--       "n": 1,
--       "id": "lun",
--       "nombre": "TIRÓN A – ANCHO",
--       "bloques": [
--         {
--           "titulo": "BLOQUE 1 — ESPALDA",
--           "ejercicios": [
--             {
--               "id": "ex_001",
--               "nombre": "Jalón al pecho prono",
--               "tipo": "compuesto",
--               "series": 4,
--               "reps": "8-10",
--               "rir_objetivo": "1-2",
--               "descanso_segundos": 150,
--               "video_url": null,
--               "notas_tecnica": "Foco en bajada controlada"
--             }
--           ]
--         }
--       ]
--     }
--   ],
--   "mensajes_semana": [
--     { "n": 1, "titulo": "Semana 1 — Introducción", "msg": "..." }
--   ]
-- }
-- =============================================================
CREATE TABLE IF NOT EXISTS mypump_rutinas (
  id            UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  cliente_id    TEXT        NOT NULL,
  version       INTEGER     NOT NULL DEFAULT 1,
  estado        TEXT        NOT NULL DEFAULT 'activa'
                            CHECK (estado IN ('activa', 'archivada')),
  estructura    JSONB       NOT NULL,
  semana_actual INTEGER     NOT NULL DEFAULT 1,
  fecha_inicio  DATE,
  fecha_fin     DATE,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_by    UUID        REFERENCES auth.users(id)
);

CREATE INDEX IF NOT EXISTS idx_mypump_rutinas_cliente_activa
  ON mypump_rutinas(cliente_id)
  WHERE estado = 'activa';

-- Un cliente puede tener a lo sumo UNA rutina activa a la vez
CREATE UNIQUE INDEX IF NOT EXISTS uniq_mypump_rutinas_una_activa
  ON mypump_rutinas(cliente_id)
  WHERE estado = 'activa';


-- =============================================================
-- TABLA 3: mypump_dietas
-- Dietas publicadas desde Cerebro.
-- Cuatro opciones (A/B/C/D) por comida, macros equivalentes ±5%.
--
-- Schema esperado del JSONB `estructura`:
-- {
--   "macros_target": {
--     "kcal": 3200, "prot": 220, "carb": 380, "fat": 90
--   },
--   "comidas": [
--     {
--       "id": "c1",
--       "name": "Desayuno",
--       "options": [
--         {
--           "name": "A",
--           "foods": [
--             {
--               "name": "Avena",
--               "kcal": 380, "prot": 13, "carb": 67, "fat": 7,
--               "qty": 100, "unit": "g", "unitGrams": null
--             }
--           ]
--         }
--       ]
--     }
--   ]
-- }
-- =============================================================
CREATE TABLE IF NOT EXISTS mypump_dietas (
  id         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  cliente_id TEXT        NOT NULL,
  version    INTEGER     NOT NULL DEFAULT 1,
  estado     TEXT        NOT NULL DEFAULT 'activa'
                         CHECK (estado IN ('activa', 'archivada')),
  estructura JSONB       NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_by UUID        REFERENCES auth.users(id)
);

CREATE INDEX IF NOT EXISTS idx_mypump_dietas_cliente_activa
  ON mypump_dietas(cliente_id)
  WHERE estado = 'activa';

CREATE UNIQUE INDEX IF NOT EXISTS uniq_mypump_dietas_una_activa
  ON mypump_dietas(cliente_id)
  WHERE estado = 'activa';


-- =============================================================
-- TABLA 4: mypump_sesiones
-- Cada sesión de entrenamiento iniciada por el cliente.
-- semana = semana del mesociclo (para correlacionar con JSONB mensajes_semana).
-- =============================================================
CREATE TABLE IF NOT EXISTS mypump_sesiones (
  id            UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  cliente_id    TEXT        NOT NULL,
  rutina_id     UUID        NOT NULL REFERENCES mypump_rutinas(id) ON DELETE CASCADE,
  dia_id        TEXT        NOT NULL,
  semana        INTEGER,
  iniciada_en   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  finalizada_en TIMESTAMPTZ,
  notas_sesion  TEXT
);

CREATE INDEX IF NOT EXISTS idx_mypump_sesiones_cliente_fecha
  ON mypump_sesiones(cliente_id, iniciada_en DESC);

CREATE INDEX IF NOT EXISTS idx_mypump_sesiones_rutina
  ON mypump_sesiones(rutina_id);


-- =============================================================
-- TABLA 5: mypump_registros_carga
-- Un registro por serie por ejercicio por sesión.
-- ejercicio_nombre es snapshot: si la rutina cambia luego,
-- el historial mantiene el nombre que tenía en el momento.
-- =============================================================
CREATE TABLE IF NOT EXISTS mypump_registros_carga (
  id               UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  cliente_id       TEXT        NOT NULL,
  rutina_id        UUID        NOT NULL REFERENCES mypump_rutinas(id) ON DELETE CASCADE,
  sesion_id        UUID        NOT NULL REFERENCES mypump_sesiones(id) ON DELETE CASCADE,
  dia_id           TEXT        NOT NULL,
  ejercicio_id     TEXT        NOT NULL,
  ejercicio_nombre TEXT,
  serie_numero     INTEGER     NOT NULL CHECK (serie_numero > 0),
  peso_kg          NUMERIC(6,2),
  reps_realizadas  INTEGER,
  rir_real         INTEGER     CHECK (rir_real >= 0 AND rir_real <= 5),
  notas            TEXT,
  registrado_en    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Índice principal para gráficos de progresión por ejercicio
CREATE INDEX IF NOT EXISTS idx_mypump_registros_cliente_ej
  ON mypump_registros_carga(cliente_id, ejercicio_id, registrado_en DESC);

CREATE INDEX IF NOT EXISTS idx_mypump_registros_sesion
  ON mypump_registros_carga(sesion_id);


-- =============================================================
-- TABLA 6: mypump_dietas_elecciones
-- Elección de opción A/B/C/D por comida por día.
-- Unique constraint garantiza una sola elección por (cliente, dieta, fecha, comida).
-- =============================================================
CREATE TABLE IF NOT EXISTS mypump_dietas_elecciones (
  id             UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  cliente_id     TEXT        NOT NULL,
  dieta_id       UUID        NOT NULL REFERENCES mypump_dietas(id) ON DELETE CASCADE,
  fecha          DATE        NOT NULL,
  comida_id      TEXT        NOT NULL,
  opcion_elegida TEXT        NOT NULL CHECK (opcion_elegida IN ('A', 'B', 'C', 'D')),
  completada     BOOLEAN     NOT NULL DEFAULT FALSE,
  registrado_en  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (cliente_id, dieta_id, fecha, comida_id)
);

CREATE INDEX IF NOT EXISTS idx_mypump_dietas_elecciones_cliente_fecha
  ON mypump_dietas_elecciones(cliente_id, fecha DESC);


-- =============================================================
-- ROW LEVEL SECURITY
-- Toda interacción pública va por RPC SECURITY DEFINER.
-- anon NO tiene políticas directas de SELECT/INSERT/UPDATE/DELETE.
-- authenticated (Mati/Cerebro) tiene acceso completo a todo.
-- =============================================================
ALTER TABLE mypump_clientes          ENABLE ROW LEVEL SECURITY;
ALTER TABLE mypump_rutinas           ENABLE ROW LEVEL SECURITY;
ALTER TABLE mypump_dietas            ENABLE ROW LEVEL SECURITY;
ALTER TABLE mypump_sesiones          ENABLE ROW LEVEL SECURITY;
ALTER TABLE mypump_registros_carga   ENABLE ROW LEVEL SECURITY;
ALTER TABLE mypump_dietas_elecciones ENABLE ROW LEVEL SECURITY;

-- Política admin: acceso total para el rol authenticated
CREATE POLICY "admin all mypump_clientes"
  ON mypump_clientes FOR ALL
  USING (auth.role() = 'authenticated');

CREATE POLICY "admin all mypump_rutinas"
  ON mypump_rutinas FOR ALL
  USING (auth.role() = 'authenticated');

CREATE POLICY "admin all mypump_dietas"
  ON mypump_dietas FOR ALL
  USING (auth.role() = 'authenticated');

CREATE POLICY "admin all mypump_sesiones"
  ON mypump_sesiones FOR ALL
  USING (auth.role() = 'authenticated');

CREATE POLICY "admin all mypump_registros_carga"
  ON mypump_registros_carga FOR ALL
  USING (auth.role() = 'authenticated');

CREATE POLICY "admin all mypump_dietas_elecciones"
  ON mypump_dietas_elecciones FOR ALL
  USING (auth.role() = 'authenticated');


-- =============================================================
-- FUNCIÓN INTERNA: resuelve cliente_id desde token
-- Solo usada internamente por las RPC públicas y admin.
-- SECURITY DEFINER para bypassear RLS al consultar mypump_clientes.
-- No se le otorga EXECUTE a anon (uso interno únicamente).
-- =============================================================
CREATE OR REPLACE FUNCTION mypump_get_cliente_id_from_token(token TEXT)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_cliente_id TEXT;
BEGIN
  SELECT cliente_id INTO v_cliente_id
  FROM mypump_clientes
  WHERE access_token = token AND access_token_active = TRUE;
  RETURN v_cliente_id;
END;
$$;


-- =============================================================
-- RPC PÚBLICAS — accesibles por rol anon con p_token como credencial
-- Todas son SECURITY DEFINER: bypassean RLS y validan el token
-- internamente. Si el token es inválido, devuelven vacío/null.
-- =============================================================

-- Devuelve {cliente_id, nombre, perfil} y actualiza last_accessed_at.
-- Retorna 0 filas si token inválido o revocado.
CREATE OR REPLACE FUNCTION mypump_get_cliente_info(p_token TEXT)
RETURNS TABLE(cliente_id TEXT, nombre TEXT, perfil TEXT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE mypump_clientes
  SET last_accessed_at = NOW()
  WHERE access_token = p_token AND access_token_active = TRUE;

  RETURN QUERY
  SELECT c.cliente_id, c.nombre, c.perfil
  FROM mypump_clientes c
  WHERE c.access_token = p_token AND c.access_token_active = TRUE;
END;
$$;

-- Devuelve la rutina activa completa del cliente.
CREATE OR REPLACE FUNCTION mypump_get_rutina_activa(p_token TEXT)
RETURNS TABLE(
  id            UUID,
  version       INTEGER,
  estructura    JSONB,
  semana_actual INTEGER,
  fecha_inicio  DATE,
  fecha_fin     DATE
)
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
  SELECT r.id, r.version, r.estructura, r.semana_actual, r.fecha_inicio, r.fecha_fin
  FROM mypump_rutinas r
  WHERE r.cliente_id = v_cliente_id AND r.estado = 'activa';
END;
$$;

-- Devuelve la dieta activa completa del cliente.
CREATE OR REPLACE FUNCTION mypump_get_dieta_activa(p_token TEXT)
RETURNS TABLE(
  id         UUID,
  version    INTEGER,
  estructura JSONB
)
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
  SELECT d.id, d.version, d.estructura
  FROM mypump_dietas d
  WHERE d.cliente_id = v_cliente_id AND d.estado = 'activa';
END;
$$;

-- Inicia una sesión de entrenamiento. Devuelve el UUID de la sesión creada.
-- Devuelve NULL si el token es inválido o el cliente no tiene rutina activa.
CREATE OR REPLACE FUNCTION mypump_iniciar_sesion(
  p_token  TEXT,
  p_dia_id TEXT,
  p_semana INTEGER
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_cliente_id TEXT;
  v_rutina_id  UUID;
  v_sesion_id  UUID;
BEGIN
  v_cliente_id := mypump_get_cliente_id_from_token(p_token);
  IF v_cliente_id IS NULL THEN RETURN NULL; END IF;

  SELECT id INTO v_rutina_id
  FROM mypump_rutinas
  WHERE cliente_id = v_cliente_id AND estado = 'activa';
  IF v_rutina_id IS NULL THEN RETURN NULL; END IF;

  INSERT INTO mypump_sesiones (cliente_id, rutina_id, dia_id, semana)
  VALUES (v_cliente_id, v_rutina_id, p_dia_id, p_semana)
  RETURNING id INTO v_sesion_id;

  RETURN v_sesion_id;
END;
$$;

-- Registra un set individual.
-- Valida que p_sesion_id pertenezca al cliente del token antes de insertar.
-- Devuelve UUID del registro creado, o NULL si la validación falla.
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

  -- Verificar que la sesión pertenezca al cliente del token
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
  RETURNING id INTO v_registro_id;

  RETURN v_registro_id;
END;
$$;

-- Devuelve las últimas N sesiones de un ejercicio para gráficos de progresión.
CREATE OR REPLACE FUNCTION mypump_get_historico_ejercicio(
  p_token        TEXT,
  p_ejercicio_id TEXT,
  p_limit        INTEGER DEFAULT 10
)
RETURNS TABLE(
  registrado_en   TIMESTAMPTZ,
  peso_kg         NUMERIC,
  reps_realizadas INTEGER,
  rir_real        INTEGER,
  serie_numero    INTEGER
)
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
  SELECT r.registrado_en, r.peso_kg, r.reps_realizadas, r.rir_real, r.serie_numero
  FROM mypump_registros_carga r
  WHERE r.cliente_id = v_cliente_id AND r.ejercicio_id = p_ejercicio_id
  ORDER BY r.registrado_en DESC
  LIMIT p_limit;
END;
$$;

-- Finaliza una sesión. Valida pertenencia al cliente del token.
-- Devuelve TRUE si se actualizó, FALSE si la sesión no existe o no pertenece al cliente.
CREATE OR REPLACE FUNCTION mypump_finalizar_sesion(
  p_token     TEXT,
  p_sesion_id UUID,
  p_notas     TEXT
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
  SET finalizada_en = NOW(), notas_sesion = p_notas
  WHERE id = p_sesion_id AND cliente_id = v_cliente_id;

  GET DIAGNOSTICS v_rows = ROW_COUNT;
  RETURN v_rows > 0;
END;
$$;

-- UPSERT de la elección de opción de comida (A/B/C/D) para un día dado.
-- Permite cambiar opción y marcar completada en la misma llamada.
-- Valida que la dieta pertenezca al cliente del token.
CREATE OR REPLACE FUNCTION mypump_elegir_opcion_comida(
  p_token      TEXT,
  p_dieta_id   UUID,
  p_fecha      DATE,
  p_comida_id  TEXT,
  p_opcion     TEXT,
  p_completada BOOLEAN
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

  IF NOT EXISTS (
    SELECT 1 FROM mypump_dietas
    WHERE id = p_dieta_id AND cliente_id = v_cliente_id
  ) THEN RETURN FALSE; END IF;

  INSERT INTO mypump_dietas_elecciones
    (cliente_id, dieta_id, fecha, comida_id, opcion_elegida, completada)
  VALUES
    (v_cliente_id, p_dieta_id, p_fecha, p_comida_id, p_opcion, p_completada)
  ON CONFLICT (cliente_id, dieta_id, fecha, comida_id)
  DO UPDATE SET
    opcion_elegida = EXCLUDED.opcion_elegida,
    completada     = EXCLUDED.completada,
    registrado_en  = NOW();

  RETURN TRUE;
END;
$$;

-- Devuelve las elecciones del cliente para un día específico.
CREATE OR REPLACE FUNCTION mypump_get_elecciones_dia(
  p_token    TEXT,
  p_dieta_id UUID,
  p_fecha    DATE
)
RETURNS TABLE(
  comida_id      TEXT,
  opcion_elegida TEXT,
  completada     BOOLEAN
)
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
  SELECT e.comida_id, e.opcion_elegida, e.completada
  FROM mypump_dietas_elecciones e
  WHERE e.cliente_id = v_cliente_id
    AND e.dieta_id   = p_dieta_id
    AND e.fecha      = p_fecha;
END;
$$;


-- =============================================================
-- RPC ADMIN — solo authenticated (Cerebro/Mati)
-- =============================================================

-- Función principal de publicación desde Cerebro.
-- 1. Crea o actualiza el cliente en mypump_clientes.
-- 2. Archiva rutina activa anterior, inserta nueva versión.
-- 3. Archiva dieta activa anterior, inserta nueva versión.
-- 4. Devuelve access_token para armar el link del cliente.
CREATE OR REPLACE FUNCTION mypump_publicar_cliente(
  p_cliente_id TEXT,
  p_nombre     TEXT,
  p_perfil     TEXT,
  p_rutina     JSONB,
  p_dieta      JSONB
)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_token               TEXT;
  v_next_rutina_version INTEGER;
  v_next_dieta_version  INTEGER;
BEGIN
  -- Solo authenticated puede ejecutar esta función
  IF auth.role() <> 'authenticated' THEN
    RAISE EXCEPTION 'Acceso denegado';
  END IF;

  -- Upsert cliente
  SELECT access_token INTO v_token
  FROM mypump_clientes
  WHERE cliente_id = p_cliente_id;

  IF v_token IS NULL THEN
    v_token := generate_mypump_token();
    INSERT INTO mypump_clientes (cliente_id, nombre, perfil, access_token)
    VALUES (p_cliente_id, p_nombre, p_perfil, v_token);
  ELSE
    UPDATE mypump_clientes
    SET nombre = p_nombre, perfil = p_perfil, updated_at = NOW()
    WHERE cliente_id = p_cliente_id;
  END IF;

  -- Versión de rutina: MAX(version) + 1 sobre todas las versiones del cliente
  SELECT COALESCE(MAX(version), 0) + 1 INTO v_next_rutina_version
  FROM mypump_rutinas WHERE cliente_id = p_cliente_id;

  UPDATE mypump_rutinas SET estado = 'archivada'
  WHERE cliente_id = p_cliente_id AND estado = 'activa';

  INSERT INTO mypump_rutinas (cliente_id, version, estado, estructura, created_by)
  VALUES (p_cliente_id, v_next_rutina_version, 'activa', p_rutina, auth.uid());

  -- Versión de dieta: misma lógica
  SELECT COALESCE(MAX(version), 0) + 1 INTO v_next_dieta_version
  FROM mypump_dietas WHERE cliente_id = p_cliente_id;

  UPDATE mypump_dietas SET estado = 'archivada'
  WHERE cliente_id = p_cliente_id AND estado = 'activa';

  INSERT INTO mypump_dietas (cliente_id, version, estado, estructura, created_by)
  VALUES (p_cliente_id, v_next_dieta_version, 'activa', p_dieta, auth.uid());

  RETURN v_token;
END;
$$;

-- Revoca el acceso de un cliente (desactiva su token).
CREATE OR REPLACE FUNCTION mypump_revocar_acceso(p_cliente_id TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rows INTEGER;
BEGIN
  IF auth.role() <> 'authenticated' THEN RAISE EXCEPTION 'Acceso denegado'; END IF;

  UPDATE mypump_clientes
  SET access_token_active = FALSE, updated_at = NOW()
  WHERE cliente_id = p_cliente_id;

  GET DIAGNOSTICS v_rows = ROW_COUNT;
  RETURN v_rows > 0;
END;
$$;

-- Genera un nuevo token para el cliente (invalida el anterior in-place).
CREATE OR REPLACE FUNCTION mypump_regenerar_token(p_cliente_id TEXT)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_new_token TEXT;
BEGIN
  IF auth.role() <> 'authenticated' THEN RAISE EXCEPTION 'Acceso denegado'; END IF;

  v_new_token := generate_mypump_token();

  UPDATE mypump_clientes
  SET access_token = v_new_token, access_token_active = TRUE, updated_at = NOW()
  WHERE cliente_id = p_cliente_id;

  RETURN v_new_token;
END;
$$;


-- =============================================================
-- GRANTS
-- =============================================================

-- Funciones públicas (anon — token como credencial)
GRANT EXECUTE ON FUNCTION mypump_get_cliente_info(TEXT)                                                       TO anon;
GRANT EXECUTE ON FUNCTION mypump_get_rutina_activa(TEXT)                                                      TO anon;
GRANT EXECUTE ON FUNCTION mypump_get_dieta_activa(TEXT)                                                       TO anon;
GRANT EXECUTE ON FUNCTION mypump_iniciar_sesion(TEXT, TEXT, INTEGER)                                          TO anon;
GRANT EXECUTE ON FUNCTION mypump_registrar_carga(TEXT, UUID, TEXT, TEXT, TEXT, INTEGER, NUMERIC, INTEGER, INTEGER, TEXT) TO anon;
GRANT EXECUTE ON FUNCTION mypump_get_historico_ejercicio(TEXT, TEXT, INTEGER)                                 TO anon;
GRANT EXECUTE ON FUNCTION mypump_finalizar_sesion(TEXT, UUID, TEXT)                                           TO anon;
GRANT EXECUTE ON FUNCTION mypump_elegir_opcion_comida(TEXT, UUID, DATE, TEXT, TEXT, BOOLEAN)                  TO anon;
GRANT EXECUTE ON FUNCTION mypump_get_elecciones_dia(TEXT, UUID, DATE)                                         TO anon;

-- Funciones admin (authenticated — Cerebro/Mati)
GRANT EXECUTE ON FUNCTION mypump_publicar_cliente(TEXT, TEXT, TEXT, JSONB, JSONB) TO authenticated;
GRANT EXECUTE ON FUNCTION mypump_revocar_acceso(TEXT)                             TO authenticated;
GRANT EXECUTE ON FUNCTION mypump_regenerar_token(TEXT)                            TO authenticated;
