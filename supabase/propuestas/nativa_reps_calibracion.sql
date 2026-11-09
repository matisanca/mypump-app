-- nativa_reps_calibracion.sql — PROPUESTA, SIN APLICAR.
--
-- Subida de las grabaciones del contador de reps (.mpcal) desde el iPhone, para mejorar el contador con datos reales.
--
-- Quién sube:
--   · La cuenta que se habilite (`automatica = true`): sin que tenga que hacer nada. Lo ya guardado de antes de marcar
--     cada archivo con su cuenta, solo con `adoptar_sin_marca = true`. Se habilita a mano, por cuenta, con un UPDATE que NO va en este archivo: el repo es público y acá no van ids.
--   · Los demás alumnos: solo con consentimiento explícito (`acepta = true`), revocable desde Mis datos. Sin fila,
--     apagado.
--
-- Orden de despliegue: primero los endpoints de mini-vision, después este SQL (al revés el interruptor aparece y da error).
-- Mientras esto no esté aplicado, `mypump_reps_estado` no existe (PGRST202): la app no sube y se ve igual que hoy.
-- El `cliente_id` lo deduce siempre el servidor del token. El bucket es privado: solo lee el rol authenticated (el coach).
-- Los archivos no traen cuenta ni nombre (ver `EncabezadoSerie`). Mini-vision sube con la service key (ver el .mjs de al lado).
BEGIN;

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('reps-calibracion', 'reps-calibracion', false, 20971520, ARRAY['application/octet-stream'])
ON CONFLICT (id) DO NOTHING;

DROP POLICY IF EXISTS "coach lee reps-calibracion" ON storage.objects;
CREATE POLICY "coach lee reps-calibracion"
  ON storage.objects FOR SELECT
  USING (bucket_id = 'reps-calibracion' AND auth.role() = 'authenticated');

CREATE TABLE IF NOT EXISTS mypump_reps_subida (
  cliente_id     TEXT        PRIMARY KEY,
  automatica     BOOLEAN     NOT NULL DEFAULT FALSE,
  adoptar_sin_marca BOOLEAN  NOT NULL DEFAULT FALSE,
  acepta         BOOLEAN,
  plataforma     TEXT        CHECK (plataforma IN ('ios', 'android')),
  app_version    TEXT,
  actualizado_en TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS mypump_reps_grabaciones (
  cliente_id TEXT        NOT NULL,
  sesion     TEXT        NOT NULL CHECK (length(sesion) BETWEEN 1 AND 80),
  sha256     TEXT        NOT NULL CHECK (sha256 ~ '^[0-9a-f]{64}$'),
  path       TEXT        NOT NULL,
  bytes      INTEGER     NOT NULL CHECK (bytes > 0),
  subida_en  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (cliente_id, sesion)
);

ALTER TABLE mypump_reps_subida ENABLE ROW LEVEL SECURITY;
ALTER TABLE mypump_reps_grabaciones ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "admin all mypump_reps_subida" ON mypump_reps_subida;
DROP POLICY IF EXISTS "admin all mypump_reps_grabaciones" ON mypump_reps_grabaciones;
CREATE POLICY "admin all mypump_reps_subida" ON mypump_reps_subida FOR ALL
  USING (auth.role() = 'authenticated') WITH CHECK (auth.role() = 'authenticated');
CREATE POLICY "admin all mypump_reps_grabaciones" ON mypump_reps_grabaciones FOR ALL
  USING (auth.role() = 'authenticated') WITH CHECK (auth.role() = 'authenticated');

-- La app: qué puede hacer esta cuenta. NULL = token caído.
CREATE OR REPLACE FUNCTION mypump_reps_estado(p_token TEXT)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_cliente_id TEXT;
  v_fila       mypump_reps_subida%ROWTYPE;
BEGIN
  v_cliente_id := mypump_get_cliente_id_from_token(p_token);
  IF v_cliente_id IS NULL THEN RETURN NULL; END IF;
  SELECT * INTO v_fila FROM mypump_reps_subida WHERE cliente_id = v_cliente_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('automatica', FALSE, 'acepta', NULL, 'adoptar_sin_marca', FALSE); END IF;
  RETURN jsonb_build_object('automatica', v_fila.automatica, 'acepta', v_fila.acepta, 'adoptar_sin_marca', v_fila.adoptar_sin_marca);
END;
$$;

REVOKE ALL ON FUNCTION mypump_reps_estado(TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION mypump_reps_estado(TEXT) TO anon, authenticated, service_role;

-- Mini-vision, antes de guardar un archivo: la llave de verdad. La app nunca decide sola.
CREATE OR REPLACE FUNCTION mypump_reps_puede_subir(p_cliente_id TEXT)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE((SELECT automatica OR acepta IS TRUE FROM mypump_reps_subida WHERE cliente_id = p_cliente_id), FALSE);
$$;

REVOKE ALL ON FUNCTION mypump_reps_puede_subir(TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION mypump_reps_puede_subir(TEXT) TO service_role;

-- Solo mini-vision (`/reps/consentimiento`): la decisión del alumno. TRUE = guardado; NULL = token caído.
-- El borrado de lo ya subido al revocar lo hace mini-vision (`/reps/consentimiento`), que también llama a esta función.
CREATE OR REPLACE FUNCTION mypump_reps_consentir(
  p_token      TEXT,
  p_acepta     BOOLEAN,
  p_plataforma TEXT DEFAULT NULL,
  p_app        TEXT DEFAULT NULL
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
  IF p_acepta IS NULL OR (p_plataforma IS NOT NULL AND p_plataforma NOT IN ('ios', 'android')) THEN
    RAISE EXCEPTION 'consentimiento inválido' USING ERRCODE = '22023';
  END IF;
  INSERT INTO mypump_reps_subida (cliente_id, acepta, plataforma, app_version, actualizado_en)
  VALUES (v_cliente_id, p_acepta, p_plataforma, p_app, NOW())
  ON CONFLICT (cliente_id) DO UPDATE
    SET acepta = EXCLUDED.acepta, plataforma = EXCLUDED.plataforma,
        app_version = EXCLUDED.app_version, actualizado_en = NOW();
  RETURN TRUE;
END;
$$;

REVOKE ALL ON FUNCTION mypump_reps_consentir(TEXT, BOOLEAN, TEXT, TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION mypump_reps_consentir(TEXT, BOOLEAN, TEXT, TEXT) TO service_role;

COMMIT;

-- La cuenta automática se habilita aparte, a mano, sin dejar el id en el repo. `adoptar_sin_marca` solo si en ese iPhone
-- nunca grabó otra cuenta:
--   INSERT INTO mypump_reps_subida (cliente_id, automatica, adoptar_sin_marca) VALUES ('<cliente_id>', TRUE, TRUE)
--   ON CONFLICT (cliente_id) DO UPDATE SET automatica = TRUE, adoptar_sin_marca = TRUE, actualizado_en = NOW();
