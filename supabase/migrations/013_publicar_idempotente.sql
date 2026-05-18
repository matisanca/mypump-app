-- ============================================================
-- 013 — mypump_publicar_cliente IDEMPOTENTE (UPDATE in-place)
-- ============================================================
-- Problema previo (006 y anteriores):
--   Cada re-publicación archivaba la rutina/dieta activa e
--   insertaba una nueva con un id distinto. Como mypump_sesiones
--   y mypump_registros_carga FK-ean a mypump_rutinas(id), todo el
--   progreso del cliente quedaba huérfano contra una rutina
--   archivada. El frontend del cliente solo lee la rutina activa,
--   por lo que mostraba 0 sesiones y "reseteaba" el progreso
--   percibido. Lo mismo aplicaba para mypump_dietas_elecciones
--   contra mypump_dietas.
--
-- Fix:
--   En cada publicación, si ya existe una rutina/dieta ACTIVA para
--   el cliente_id, hacemos UPDATE in-place sobre su estructura
--   (preservando id + created_at). Solo en primera publicación
--   hacemos INSERT.
--
--   Resultado:
--     • access_token preservado (igual que antes)
--     • mypump_rutinas.id preservado → sesiones+registros intactos
--     • mypump_dietas.id preservado → dietas_elecciones intactas
--     • version sigue incrementándose (auditoría de cuántas
--       veces Mati publicó), updated_at refleja último cambio
--     • Mati puede re-publicar para sincronizar cambios de
--       dieta/rutina SIN romper el progreso del cliente
--
-- Compatibilidad:
--   Misma firma (TEXT, TEXT, TEXT, JSONB, JSONB) → TEXT.
--   Cerebro NO necesita cambios, sigue llamando igual.
-- ============================================================

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
  v_token             TEXT;
  v_rutina_activa_id  UUID;
  v_dieta_activa_id   UUID;
  v_rutina_version    INTEGER;
  v_dieta_version     INTEGER;
BEGIN
  -- Solo authenticated puede ejecutar
  IF auth.role() <> 'authenticated' THEN
    RAISE EXCEPTION 'Acceso denegado';
  END IF;

  -- ===== 1. UPSERT cliente (sin tocar access_token si existe) =====
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

  -- ===== 2. RUTINA: UPDATE in-place si ya existe activa =====
  SELECT id, version INTO v_rutina_activa_id, v_rutina_version
  FROM mypump_rutinas
  WHERE cliente_id = p_cliente_id AND estado = 'activa';

  IF v_rutina_activa_id IS NOT NULL THEN
    -- Re-publicación: UPDATE preservando id (y por ende todas las
    -- sesiones+registros del cliente).
    UPDATE mypump_rutinas
    SET estructura = p_rutina,
        version    = v_rutina_version + 1,
        updated_at = NOW()
    WHERE id = v_rutina_activa_id;
  ELSE
    -- Primera publicación o caso edge (todas archivadas).
    -- Buscar max version del cliente para no chocar.
    SELECT COALESCE(MAX(version), 0) + 1 INTO v_rutina_version
    FROM mypump_rutinas WHERE cliente_id = p_cliente_id;

    INSERT INTO mypump_rutinas (
      cliente_id, version, estado, estructura, created_by, fecha_inicio
    )
    VALUES (
      p_cliente_id, v_rutina_version, 'activa', p_rutina, auth.uid(), CURRENT_DATE
    );
  END IF;

  -- ===== 3. DIETA: misma lógica (UPDATE in-place) =====
  SELECT id, version INTO v_dieta_activa_id, v_dieta_version
  FROM mypump_dietas
  WHERE cliente_id = p_cliente_id AND estado = 'activa';

  IF v_dieta_activa_id IS NOT NULL THEN
    UPDATE mypump_dietas
    SET estructura = p_dieta,
        version    = v_dieta_version + 1,
        updated_at = NOW()
    WHERE id = v_dieta_activa_id;
  ELSE
    SELECT COALESCE(MAX(version), 0) + 1 INTO v_dieta_version
    FROM mypump_dietas WHERE cliente_id = p_cliente_id;

    INSERT INTO mypump_dietas (cliente_id, version, estado, estructura, created_by)
    VALUES (p_cliente_id, v_dieta_version, 'activa', p_dieta, auth.uid());
  END IF;

  RETURN v_token;
END;
$$;

GRANT EXECUTE ON FUNCTION mypump_publicar_cliente(TEXT, TEXT, TEXT, JSONB, JSONB) TO authenticated;

-- ============================================================
-- updated_at column en mypump_rutinas y mypump_dietas
-- ============================================================
-- La tabla original (001_mypump_schema.sql) solo tenía created_at.
-- Agregamos updated_at para que el frontend pueda detectar
-- "hay cambios nuevos en la dieta/rutina, hagamos pull-to-refresh".
-- ============================================================
ALTER TABLE mypump_rutinas
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW();

ALTER TABLE mypump_dietas
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW();

-- ============================================================
-- REPARACIÓN: migrar progreso de rutinas/dietas ARCHIVADAS
-- hacia la rutina/dieta ACTIVA actual del cliente
-- ============================================================
-- Para cada cliente con sesiones+registros colgados de rutinas
-- archivadas (caso Fabián, Damián, etc.): re-apuntar el FK al
-- id de la rutina activa actual. Idempotente: si ya está
-- apuntando a la activa, el WHERE no matchea.
--
-- Caso especial: si el cliente tiene rutina ACTIVA pero el
-- progreso está en una archivada (porque el flow viejo creaba
-- nueva versión en cada republicación), re-apuntamos todo el
-- progreso al id activo y borramos las archivadas vacías.
-- ============================================================

-- 3a. Migrar mypump_sesiones de rutinas archivadas → rutina activa
WITH activas AS (
  SELECT cliente_id, id AS rutina_activa_id
  FROM mypump_rutinas
  WHERE estado = 'activa'
)
UPDATE mypump_sesiones s
SET rutina_id = a.rutina_activa_id
FROM activas a
WHERE s.cliente_id = a.cliente_id
  AND s.rutina_id <> a.rutina_activa_id;

-- 3b. Migrar mypump_registros_carga
WITH activas AS (
  SELECT cliente_id, id AS rutina_activa_id
  FROM mypump_rutinas
  WHERE estado = 'activa'
)
UPDATE mypump_registros_carga r
SET rutina_id = a.rutina_activa_id
FROM activas a
WHERE r.cliente_id = a.cliente_id
  AND r.rutina_id <> a.rutina_activa_id;

-- 3c. Migrar mypump_dietas_elecciones de dietas archivadas → dieta activa
WITH activas AS (
  SELECT cliente_id, id AS dieta_activa_id
  FROM mypump_dietas
  WHERE estado = 'activa'
)
UPDATE mypump_dietas_elecciones e
SET dieta_id = a.dieta_activa_id
FROM activas a
WHERE e.cliente_id = a.cliente_id
  AND e.dieta_id <> a.dieta_activa_id;

-- 3d. Borrar rutinas archivadas vacías (sin sesiones ni registros)
DELETE FROM mypump_rutinas r
WHERE estado = 'archivada'
  AND NOT EXISTS (SELECT 1 FROM mypump_sesiones        WHERE rutina_id = r.id)
  AND NOT EXISTS (SELECT 1 FROM mypump_registros_carga WHERE rutina_id = r.id);

-- 3e. Borrar dietas archivadas vacías (sin elecciones)
DELETE FROM mypump_dietas d
WHERE estado = 'archivada'
  AND NOT EXISTS (SELECT 1 FROM mypump_dietas_elecciones WHERE dieta_id = d.id);
