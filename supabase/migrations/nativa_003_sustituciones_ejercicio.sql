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
--   ex_id (el ejercicio del plan) → {original, current, fijado, semana, diaId, _ts}
-- `_ts` es cuándo la eligió el cliente (ms, reloj del teléfono). Lo que trae la
-- app vieja no lo tiene: cuenta como 0, lo más viejo.
--
-- Gana siempre lo más nuevo, también contra un borrado: borrar deja una LÁPIDA
-- (swap NULL) con su hora, para que un teléfono que todavía no sincronizó no
-- reviva lo que el cliente sacó en otro. Así ningún orden de llegada pierde lo
-- último que hizo el cliente, y que algo falte acá no significa que se borró
-- (si la tabla se vaciara, cada teléfono vuelve a subir lo suyo).
--
-- La poda (las no fijadas valen solo por su día y su semana) la sigue haciendo
-- cada teléfono y NO se manda: un teléfono viejo no puede borrar lo que el
-- cliente fijó después en otro.
--
-- La web NO la usa (sigue con su localStorage, como hoy) y el Cerebro tampoco.
-- Mientras no exista (PGRST202), la app sigue como hoy: solo en el teléfono.
--
-- Solo agrega: una tabla y cinco funciones. No cambia nada existente.
--
-- Ensayo: scripts/nativa/ensayar-migracion.py (BEGIN … ROLLBACK, con las
-- cuentas test-nativa-ios y test-nativa-real). Se aplica SOLO con el OK de Mati.
BEGIN;

CREATE TABLE IF NOT EXISTS mypump_exercise_swaps (
  cliente_id     TEXT        NOT NULL,
  rutina_id      UUID        NOT NULL,
  ex_id          TEXT        NOT NULL CHECK (length(ex_id) BETWEEN 1 AND 120),
  -- NULL = la lápida de una borrada.
  swap           JSONB       CHECK (swap IS NULL OR jsonb_typeof(swap) = 'object'),
  -- Cuándo la cambió el cliente (ms del teléfono). 0 = sin hora (lo de la app vieja).
  cambiado_en    BIGINT      NOT NULL DEFAULT 0 CHECK (cambiado_en >= 0),
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

-- Una entrada válida: un objeto de hasta 16 KB, con clave de 1 a 120 caracteres
-- y, si trae `_ts`, un número entre 0 y 9e15. Con CASE: el orden importa (un
-- `_ts` de texto no tiene que llegar al cast).
CREATE OR REPLACE FUNCTION mypump_sustitucion_valida(p_ex_id TEXT, p_swap JSONB)
RETURNS BOOLEAN
LANGUAGE sql
IMMUTABLE
SET search_path = public
AS $$
  SELECT CASE
    WHEN p_ex_id IS NULL OR length(p_ex_id) NOT BETWEEN 1 AND 120 THEN FALSE
    WHEN p_swap IS NULL OR jsonb_typeof(p_swap) <> 'object' THEN FALSE
    WHEN length(p_swap::text) > 16000 THEN FALSE
    WHEN NOT (p_swap ? '_ts') THEN TRUE
    WHEN jsonb_typeof(p_swap -> '_ts') <> 'number' THEN FALSE
    ELSE (p_swap ->> '_ts')::numeric BETWEEN 0 AND 9000000000000000
  END;
$$;

REVOKE ALL ON FUNCTION mypump_sustitucion_valida(TEXT, JSONB) FROM PUBLIC;
REVOKE ALL ON FUNCTION mypump_sustitucion_valida(TEXT, JSONB) FROM anon, authenticated;

-- La hora de una entrada ya validada (0 si no tiene).
CREATE OR REPLACE FUNCTION mypump_sustitucion_ts(p_swap JSONB)
RETURNS BIGINT
LANGUAGE sql
IMMUTABLE
SET search_path = public
AS $$
  SELECT COALESCE(floor((p_swap ->> '_ts')::numeric)::bigint, 0);
$$;

REVOKE ALL ON FUNCTION mypump_sustitucion_ts(JSONB) FROM PUBLIC;
REVOKE ALL ON FUNCTION mypump_sustitucion_ts(JSONB) FROM anon, authenticated;

-- La app: las de una rutina. {"vivas": {exId: entrada}, "borradas": {exId: ms}}.
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
  RETURN jsonb_build_object(
    'vivas', COALESCE((SELECT jsonb_object_agg(ex_id, swap) FROM mypump_exercise_swaps
                       WHERE cliente_id = v_cliente_id AND rutina_id = p_rutina_id AND swap IS NOT NULL), '{}'::jsonb),
    'borradas', COALESCE((SELECT jsonb_object_agg(ex_id, cambiado_en) FROM mypump_exercise_swaps
                          WHERE cliente_id = v_cliente_id AND rutina_id = p_rutina_id AND swap IS NULL), '{}'::jsonb));
END;
$$;

REVOKE ALL ON FUNCTION mypump_get_exercise_swaps(TEXT, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION mypump_get_exercise_swaps(TEXT, UUID) TO anon, authenticated, service_role;

-- La app (por la cola): guarda una, salvo que acá haya algo más nuevo (también
-- una lápida). TRUE = hecho (guardada, o había algo más nuevo); FALSE = la
-- rutina ya no es del cliente (nada que hacer); NULL = token caído. Una entrada
-- inválida o pasar el tope de 300 claves por rutina es un error 22023.
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

  INSERT INTO mypump_exercise_swaps (cliente_id, rutina_id, ex_id, swap, cambiado_en)
  VALUES (v_cliente_id, p_rutina_id, p_ex_id, p_swap, mypump_sustitucion_ts(p_swap))
  ON CONFLICT (cliente_id, rutina_id, ex_id) DO UPDATE
    SET swap           = EXCLUDED.swap,
        cambiado_en    = EXCLUDED.cambiado_en,
        actualizado_en = NOW()
    WHERE EXCLUDED.cambiado_en >= mypump_exercise_swaps.cambiado_en;

  RETURN TRUE;
END;
$$;

REVOKE ALL ON FUNCTION mypump_save_exercise_swap(TEXT, UUID, TEXT, JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION mypump_save_exercise_swap(TEXT, UUID, TEXT, JSONB) TO anon, authenticated, service_role;

-- La app (por la cola): "Volver a …". Deja la lápida con su hora, salvo que
-- acá haya algo más nuevo. TRUE = hecho; FALSE = la rutina ya no es del
-- cliente; NULL = token caído. Con el tope lleno y sin fila, no hay nada que
-- borrar: TRUE sin lápida.
CREATE OR REPLACE FUNCTION mypump_delete_exercise_swap(
  p_token     TEXT,
  p_rutina_id UUID,
  p_ex_id     TEXT,
  p_ts        BIGINT
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
  IF p_ex_id IS NULL OR length(p_ex_id) NOT BETWEEN 1 AND 120
     OR p_ts IS NULL OR p_ts NOT BETWEEN 0 AND 9000000000000000 THEN
    RAISE EXCEPTION 'borrado inválido' USING ERRCODE = '22023';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM mypump_rutinas WHERE id = p_rutina_id AND cliente_id = v_cliente_id) THEN
    RETURN FALSE;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM mypump_exercise_swaps
                 WHERE cliente_id = v_cliente_id AND rutina_id = p_rutina_id AND ex_id = p_ex_id)
     AND (SELECT count(*) FROM mypump_exercise_swaps
          WHERE cliente_id = v_cliente_id AND rutina_id = p_rutina_id) >= 300 THEN
    RETURN TRUE;
  END IF;

  INSERT INTO mypump_exercise_swaps (cliente_id, rutina_id, ex_id, swap, cambiado_en)
  VALUES (v_cliente_id, p_rutina_id, p_ex_id, NULL, p_ts)
  ON CONFLICT (cliente_id, rutina_id, ex_id) DO UPDATE
    SET swap           = NULL,
        cambiado_en    = EXCLUDED.cambiado_en,
        actualizado_en = NOW()
    WHERE EXCLUDED.cambiado_en >= mypump_exercise_swaps.cambiado_en;

  RETURN TRUE;
END;
$$;

REVOKE ALL ON FUNCTION mypump_delete_exercise_swap(TEXT, UUID, TEXT, BIGINT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION mypump_delete_exercise_swap(TEXT, UUID, TEXT, BIGINT) TO anon, authenticated, service_role;

NOTIFY pgrst, 'reload schema';

COMMIT;
