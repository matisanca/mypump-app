-- nativa_001_recibo_conteos_palanca.sql
--
-- APPS NATIVAS, COMPUERTA G2 (primera tanda). Solo agrega: dos tablas y tres
-- funciones nuevas. No cambia ninguna tabla ni función existente, y la web no
-- las usa. La app nativa ya las llama y, mientras no existan (PGRST202), sigue
-- como antes: recibo solo en el teléfono, sin conteos y con la palanca abierta.
--
--   1. mypump_migracion_nativa + mypump_registrar_migracion_nativa: el RECIBO
--      de cada corrida de la migración del almacenamiento viejo (Capacitor →
--      nativa). Son conteos antes y después, sin contenido ni claves con
--      token. Con el recibo confirmado, a los 90 días el teléfono borra su
--      copia cruda (sin servidor, nunca la borra).
--   2. mypump_conteos_cliente: filas por tabla del cliente, de solo lectura. Es
--      la prueba de cero pérdida en cada cliente del escalonado: el teléfono
--      la pide antes y después de mandar lo que importó, y va en el recibo. No
--      toca last_accessed_at (no pasa por get_cliente_info).
--   3. mypump_app_config + mypump_get_app_config: la palanca remota que la app
--      lee al abrir. Pausa las ops importadas y la escritura de vuelta, apaga el
--      anclaje que borra swaps y fija una versión mínima, sin publicar una
--      versión nueva. Se cambia con un UPDATE (ver el pie).
--
-- Ensayo: scripts/nativa/ensayar-migracion.py (BEGIN … ROLLBACK, con la cuenta
-- test-nativa-ios). Se aplica SOLO con el OK de Mati.
BEGIN;

-- ── 1. Recibo de la migración ────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS mypump_migracion_nativa (
  id           BIGSERIAL   PRIMARY KEY,
  cliente_id   TEXT        NOT NULL,
  migracion    UUID        NOT NULL,   -- uuid de la migración del teléfono (no es el IDFV)
  corrida      INTEGER     NOT NULL CHECK (corrida BETWEEN 0 AND 10000),
  plataforma   TEXT        NOT NULL CHECK (plataforma IN ('ios', 'android')),
  app_version  TEXT,
  recibo       JSONB       NOT NULL,
  recibido_en  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (migracion, corrida)            -- reenviar el mismo recibo no duplica
);

CREATE INDEX IF NOT EXISTS idx_mypump_migracion_nativa_cliente
  ON mypump_migracion_nativa (cliente_id, recibido_en DESC);

ALTER TABLE mypump_migracion_nativa ENABLE ROW LEVEL SECURITY;

CREATE POLICY "admin all mypump_migracion_nativa"
  ON mypump_migracion_nativa FOR ALL
  USING (auth.role() = 'authenticated')
  WITH CHECK (auth.role() = 'authenticated');

-- TRUE = guardado. FALSE = rechazado sin error (tope del cliente, o el uuid es
-- de otro cliente): el teléfono lo deja en su disco. NULL = token caído, como
-- el resto de las RPC. Un recibo mal formado es un error (22023).
CREATE OR REPLACE FUNCTION mypump_registrar_migracion_nativa(
  p_token     TEXT,
  p_migracion UUID,
  p_corrida   INTEGER,
  p_recibo    JSONB
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_cliente_id TEXT;
  v_dueno      TEXT;
BEGIN
  v_cliente_id := mypump_get_cliente_id_from_token(p_token);
  IF v_cliente_id IS NULL THEN RETURN NULL; END IF;

  IF p_migracion IS NULL OR p_corrida IS NULL OR p_corrida NOT BETWEEN 0 AND 10000
     OR p_recibo IS NULL OR jsonb_typeof(p_recibo) <> 'object'
     OR octet_length(p_recibo::TEXT) > 16384
     OR COALESCE(p_recibo->>'plataforma', '') NOT IN ('ios', 'android') THEN
    RAISE EXCEPTION 'recibo inválido' USING ERRCODE = '22023';
  END IF;

  -- El uuid de una migración es de un solo cliente: otro token no lo pisa.
  SELECT cliente_id INTO v_dueno FROM mypump_migracion_nativa WHERE migracion = p_migracion LIMIT 1;
  IF v_dueno IS NOT NULL AND v_dueno <> v_cliente_id THEN RETURN FALSE; END IF;

  -- Un cliente no llena la tabla: 200 recibos son años de reinstalaciones.
  IF v_dueno IS NULL
     AND (SELECT count(*) FROM mypump_migracion_nativa WHERE cliente_id = v_cliente_id) >= 200 THEN
    RETURN FALSE;
  END IF;

  INSERT INTO mypump_migracion_nativa (cliente_id, migracion, corrida, plataforma, app_version, recibo)
  VALUES (v_cliente_id, p_migracion, p_corrida, p_recibo->>'plataforma', left(p_recibo->>'app', 40), p_recibo)
  ON CONFLICT (migracion, corrida) DO UPDATE
    SET recibo      = EXCLUDED.recibo,
        app_version = EXCLUDED.app_version,
        recibido_en = NOW();

  RETURN TRUE;
END;
$$;

REVOKE ALL ON FUNCTION mypump_registrar_migracion_nativa(TEXT, UUID, INTEGER, JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION mypump_registrar_migracion_nativa(TEXT, UUID, INTEGER, JSONB) TO anon, authenticated, service_role;

-- ── 2. Conteos del cliente (solo lectura) ────────────────────────────────
CREATE OR REPLACE FUNCTION mypump_conteos_cliente(p_token TEXT)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v TEXT;
BEGIN
  v := mypump_get_cliente_id_from_token(p_token);
  IF v IS NULL THEN RETURN NULL; END IF;

  RETURN jsonb_build_object(
    'registros_carga',   (SELECT count(*) FROM mypump_registros_carga   WHERE cliente_id = v),
    'sesiones',          (SELECT count(*) FROM mypump_sesiones          WHERE cliente_id = v),
    'ejercicios_estado', (SELECT count(*) FROM mypump_ejercicios_estado WHERE cliente_id = v),
    'comentarios',       (SELECT count(*) FROM mypump_comentarios       WHERE cliente_id = v),
    'comidas_marcadas',  (SELECT count(*) FROM mypump_comidas_marcadas  WHERE cliente_id = v),
    'comidas_libres',    (SELECT count(*) FROM mypump_comidas_libres    WHERE cliente_id = v),
    'custom_foods',      (SELECT count(*) FROM mypump_custom_foods      WHERE cliente_id = v),
    'food_swaps',        (SELECT count(*) FROM mypump_food_swaps        WHERE cliente_id = v),
    'habitos_diarios',   (SELECT count(*) FROM mypump_habitos_diarios   WHERE cliente_id = v),
    'checkin_semanal',   (SELECT count(*) FROM mypump_checkin_semanal   WHERE cliente_id = v),
    'fotos_progreso',    (SELECT count(*) FROM mypump_fotos_progreso    WHERE cliente_id = v),
    'peso_manual',       (SELECT count(*) FROM mypump_salud_diaria      WHERE cliente_id = v AND tipo = 'peso_kg'),
    'salud_diaria',      (SELECT count(*) FROM mypump_salud_diaria      WHERE cliente_id = v),
    'entrenos_health',   (SELECT count(*) FROM mypump_entrenos_health   WHERE cliente_id = v),
    'push_devices',      (SELECT count(*) FROM mypump_push_devices      WHERE cliente_id = v)
  );
END;
$$;

REVOKE ALL ON FUNCTION mypump_conteos_cliente(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION mypump_conteos_cliente(TEXT) TO anon, authenticated, service_role;

-- ── 3. Palanca remota ────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS mypump_app_config (
  clave          TEXT        PRIMARY KEY CHECK (clave ~ '^[a-z0-9_]{1,64}$'),
  valor          JSONB       NOT NULL,
  nota           TEXT,
  actualizado_en TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE mypump_app_config ENABLE ROW LEVEL SECURITY;

CREATE POLICY "admin all mypump_app_config"
  ON mypump_app_config FOR ALL
  USING (auth.role() = 'authenticated')
  WITH CHECK (auth.role() = 'authenticated');

-- Los valores por defecto son lo que la app hace sin la tabla: todo prendido y
-- sin versión mínima. Pausar algo es cambiar un valor, nunca borrar la fila.
INSERT INTO mypump_app_config (clave, valor, nota) VALUES
  ('migracion_ops_legadas',      'true'::JSONB,
   'false: la nativa importa las ops de la Capacitor pero no las manda (quedan guardadas en el teléfono)'),
  ('migracion_escritura_vuelta', 'true'::JSONB,
   'false: la nativa no borra nada del almacenamiento viejo de la Capacitor'),
  ('anclaje_borra_swaps',        'true'::JSONB,
   'false: un swap de comida anclado que ya no coincide con la dieta no se borra del servidor (solo se oculta)'),
  ('version_minima_ios',         'null'::JSONB,
   'texto como "2.0.3": por debajo, la app nativa de iPhone pide actualizar'),
  ('version_minima_android',     'null'::JSONB,
   'texto como "2.0.3": por debajo, la app nativa de Android pide actualizar')
ON CONFLICT (clave) DO NOTHING;

-- Sin token: se lee antes de tener cuenta (la versión mínima vale también en la
-- bienvenida). Devuelve el objeto clave → valor; no hay nada privado en la tabla.
CREATE OR REPLACE FUNCTION mypump_get_app_config()
RETURNS JSONB
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(jsonb_object_agg(clave, valor), '{}'::JSONB) FROM mypump_app_config;
$$;

REVOKE ALL ON FUNCTION mypump_get_app_config() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION mypump_get_app_config() TO anon, authenticated, service_role;

NOTIFY pgrst, 'reload schema';

COMMIT;

-- Para usar la palanca (desde el SQL editor o _aplicar.py):
--   UPDATE mypump_app_config SET valor = 'false', actualizado_en = NOW() WHERE clave = 'migracion_ops_legadas';
--   UPDATE mypump_app_config SET valor = '"2.0.3"', actualizado_en = NOW() WHERE clave = 'version_minima_ios';
