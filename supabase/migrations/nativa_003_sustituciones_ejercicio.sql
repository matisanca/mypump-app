-- nativa_003_sustituciones_ejercicio.sql
--
-- APPS NATIVAS, COMPUERTA G2 (tercera tanda): LAS SUSTITUCIONES DE EJERCICIO
-- EN EL SERVIDOR (SER-14). Decisión de Mati del 14-oct.
--
-- Hoy la sustitución que elige el cliente ("hago prensa en vez de sentadilla",
-- fijada o solo por hoy) vive únicamente en el teléfono: la web la guarda en
-- `mypump_exercise_swaps_<RUTINA>` del localStorage y la nativa en un archivo.
-- Si cambia de teléfono o reinstala, la pierde. Con esta tabla la app nativa la
-- guarda también acá y la recupera en cualquier teléfono.
--
-- Cada fila es una entrada del mapa de la web, tal cual:
--   ex_id (el ejercicio del plan) → {original, current, fijado, semana, diaId}
-- La poda (las no fijadas valen solo por su día y su semana) la sigue haciendo
-- la app, igual que hoy; acá solo se guarda lo que queda.
--
-- La web NO la usa (sigue con su localStorage, como hoy) y el Cerebro tampoco.
-- Mientras no exista (PGRST202), la app sigue como hoy: solo en el teléfono.
--
-- Solo agrega: una tabla y cuatro funciones. No cambia nada existente.
--
-- Ensayo: scripts/nativa/ensayar-migracion.py (BEGIN … ROLLBACK, con las
-- cuentas test-nativa-ios y test-nativa-real). Se aplica SOLO con el OK de Mati.
BEGIN;

CREATE TABLE IF NOT EXISTS mypump_exercise_swaps (
  cliente_id     TEXT        NOT NULL,
  rutina_id      UUID        NOT NULL,
  ex_id          TEXT        NOT NULL CHECK (length(ex_id) BETWEEN 1 AND 120),
  swap           JSONB       NOT NULL CHECK (jsonb_typeof(swap) = 'object'),
  creado_en      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  actualizado_en TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (cliente_id, rutina_id, ex_id)
);

-- Sin clave foránea a mypump_rutinas a propósito: si el Cerebro borra y vuelve a
-- crear una rutina, un ON DELETE CASCADE se llevaría las sustituciones.

ALTER TABLE mypump_exercise_swaps ENABLE ROW LEVEL SECURITY;

CREATE POLICY "admin all mypump_exercise_swaps"
  ON mypump_exercise_swaps FOR ALL
  USING (auth.role() = 'authenticated')
  WITH CHECK (auth.role() = 'authenticated');

-- Una entrada válida: un objeto de hasta 16 KB con clave de 1 a 120 caracteres.
-- Topes: 300 sustituciones por rutina (una rutina real tiene menos de 100
-- ejercicios).
CREATE OR REPLACE FUNCTION mypump_sustitucion_valida(p_ex_id TEXT, p_swap JSONB)
RETURNS BOOLEAN
LANGUAGE sql
IMMUTABLE
SET search_path = public
AS $$
  SELECT p_ex_id IS NOT NULL AND length(p_ex_id) BETWEEN 1 AND 120
     AND p_swap IS NOT NULL AND jsonb_typeof(p_swap) = 'object'
     AND length(p_swap::text) <= 16000;
$$;

REVOKE ALL ON FUNCTION mypump_sustitucion_valida(TEXT, JSONB) FROM PUBLIC;
REVOKE ALL ON FUNCTION mypump_sustitucion_valida(TEXT, JSONB) FROM anon, authenticated;

-- La app: las de una rutina, como el mapa de la web (`{}` = ninguna).
-- NULL = token caído o rutina que no es del cliente.
CREATE OR REPLACE FUNCTION mypump_get_exercise_swaps(p_token TEXT, p_rutina_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_cliente_id TEXT;
BEGIN
  v_cliente_id := mypump_get_cliente_id_from_token(p_token);
  IF v_cliente_id IS NULL THEN RETURN NULL; END IF;
  IF NOT EXISTS (SELECT 1 FROM mypump_rutinas WHERE id = p_rutina_id AND cliente_id = v_cliente_id) THEN
    RETURN NULL;
  END IF;
  RETURN COALESCE((SELECT jsonb_object_agg(ex_id, swap)
                   FROM mypump_exercise_swaps
                   WHERE cliente_id = v_cliente_id AND rutina_id = p_rutina_id), '{}'::jsonb);
END;
$$;

REVOKE ALL ON FUNCTION mypump_get_exercise_swaps(TEXT, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION mypump_get_exercise_swaps(TEXT, UUID) TO anon, authenticated, service_role;

-- La app (por la cola): guarda una; la última gana.
-- TRUE = guardada; FALSE = la rutina ya no es del cliente (nada que hacer);
-- NULL = token caído. Una entrada inválida o pasar el tope es un error 22023.
CREATE OR REPLACE FUNCTION mypump_save_exercise_swap(
  p_token     TEXT,
  p_rutina_id UUID,
  p_ex_id     TEXT,
  p_swap      JSONB
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
  IF v_cliente_id IS NULL THEN RETURN NULL; END IF;
  IF NOT mypump_sustitucion_valida(p_ex_id, p_swap) THEN
    RAISE EXCEPTION 'sustitución inválida' USING ERRCODE = '22023';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM mypump_rutinas WHERE id = p_rutina_id AND cliente_id = v_cliente_id) THEN
    RETURN FALSE;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM mypump_exercise_swaps
                 WHERE cliente_id = v_cliente_id AND rutina_id = p_rutina_id AND ex_id = p_ex_id)
     AND (SELECT count(*) FROM mypump_exercise_swaps
          WHERE cliente_id = v_cliente_id AND rutina_id = p_rutina_id) >= 300 THEN
    RAISE EXCEPTION 'demasiadas sustituciones en la rutina' USING ERRCODE = '22023';
  END IF;

  INSERT INTO mypump_exercise_swaps (cliente_id, rutina_id, ex_id, swap)
  VALUES (v_cliente_id, p_rutina_id, p_ex_id, p_swap)
  ON CONFLICT (cliente_id, rutina_id, ex_id) DO UPDATE
    SET swap           = EXCLUDED.swap,
        actualizado_en = NOW();

  RETURN TRUE;
END;
$$;

REVOKE ALL ON FUNCTION mypump_save_exercise_swap(TEXT, UUID, TEXT, JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION mypump_save_exercise_swap(TEXT, UUID, TEXT, JSONB) TO anon, authenticated, service_role;

-- La app (por la cola): "Volver a …" y la poda. TRUE aunque no hubiera fila
-- (objetivo cumplido); NULL = token caído.
CREATE OR REPLACE FUNCTION mypump_delete_exercise_swap(p_token TEXT, p_rutina_id UUID, p_ex_id TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_cliente_id TEXT;
BEGIN
  v_cliente_id := mypump_get_cliente_id_from_token(p_token);
  IF v_cliente_id IS NULL THEN RETURN NULL; END IF;
  DELETE FROM mypump_exercise_swaps
  WHERE cliente_id = v_cliente_id AND rutina_id = p_rutina_id AND ex_id = p_ex_id;
  RETURN TRUE;
END;
$$;

REVOKE ALL ON FUNCTION mypump_delete_exercise_swap(TEXT, UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION mypump_delete_exercise_swap(TEXT, UUID, TEXT) TO anon, authenticated, service_role;

-- La app, la primera vez que un teléfono sincroniza una rutina: sube lo que
-- tenía guardado solo en el teléfono (de antes de esta tabla, o lo que trajo la
-- migración del almacenamiento viejo). Devuelve el mapa que quedó, como la
-- lectura. Se puede repetir sin duplicar.
--   p_reemplazar = FALSE: suma lo que falta y, si la misma sustitución ya
--     estaba (la subió otro teléfono), queda la del servidor.
--   p_reemplazar = TRUE: el mapa enviado pasa a ser el de la rutina. Solo
--     cuando la migración se repite (el cliente volvió a usar la app vieja y
--     eso es lo último que hizo).
-- NULL = token caído o rutina que no es del cliente. Si alguna entrada es
-- inválida o pasa el tope, error 22023 y no se guarda nada.
CREATE OR REPLACE FUNCTION mypump_import_exercise_swaps(
  p_token      TEXT,
  p_rutina_id  UUID,
  p_swaps      JSONB,
  p_reemplazar BOOLEAN DEFAULT FALSE
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_cliente_id TEXT;
BEGIN
  v_cliente_id := mypump_get_cliente_id_from_token(p_token);
  IF v_cliente_id IS NULL THEN RETURN NULL; END IF;
  IF p_swaps IS NULL OR jsonb_typeof(p_swaps) <> 'object' THEN
    RAISE EXCEPTION 'sustituciones inválidas' USING ERRCODE = '22023';
  END IF;
  IF EXISTS (SELECT 1 FROM jsonb_each(p_swaps) e WHERE NOT mypump_sustitucion_valida(e.key, e.value)) THEN
    RAISE EXCEPTION 'sustitución inválida' USING ERRCODE = '22023';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM mypump_rutinas WHERE id = p_rutina_id AND cliente_id = v_cliente_id) THEN
    RETURN NULL;
  END IF;

  IF COALESCE(p_reemplazar, FALSE) THEN
    IF (SELECT count(*) FROM jsonb_object_keys(p_swaps)) > 300 THEN
      RAISE EXCEPTION 'demasiadas sustituciones en la rutina' USING ERRCODE = '22023';
    END IF;
    DELETE FROM mypump_exercise_swaps s
    WHERE s.cliente_id = v_cliente_id AND s.rutina_id = p_rutina_id AND NOT (p_swaps ? s.ex_id);
    INSERT INTO mypump_exercise_swaps (cliente_id, rutina_id, ex_id, swap)
    SELECT v_cliente_id, p_rutina_id, e.key, e.value FROM jsonb_each(p_swaps) e
    ON CONFLICT (cliente_id, rutina_id, ex_id) DO UPDATE
      SET swap           = EXCLUDED.swap,
          actualizado_en = NOW()
      WHERE mypump_exercise_swaps.swap IS DISTINCT FROM EXCLUDED.swap;
  ELSE
    IF (SELECT count(*) FROM (
          SELECT ex_id FROM mypump_exercise_swaps WHERE cliente_id = v_cliente_id AND rutina_id = p_rutina_id
          UNION
          SELECT key FROM jsonb_each(p_swaps)) t) > 300 THEN
      RAISE EXCEPTION 'demasiadas sustituciones en la rutina' USING ERRCODE = '22023';
    END IF;
    INSERT INTO mypump_exercise_swaps (cliente_id, rutina_id, ex_id, swap)
    SELECT v_cliente_id, p_rutina_id, e.key, e.value FROM jsonb_each(p_swaps) e
    ON CONFLICT (cliente_id, rutina_id, ex_id) DO NOTHING;
  END IF;

  RETURN COALESCE((SELECT jsonb_object_agg(ex_id, swap)
                   FROM mypump_exercise_swaps
                   WHERE cliente_id = v_cliente_id AND rutina_id = p_rutina_id), '{}'::jsonb);
END;
$$;

REVOKE ALL ON FUNCTION mypump_import_exercise_swaps(TEXT, UUID, JSONB, BOOLEAN) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION mypump_import_exercise_swaps(TEXT, UUID, JSONB, BOOLEAN) TO anon, authenticated, service_role;

NOTIFY pgrst, 'reload schema';

COMMIT;
