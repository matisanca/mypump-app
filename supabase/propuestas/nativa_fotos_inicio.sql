-- nativa_fotos_inicio.sql — PROPUESTA, SIN APLICAR.
--
-- «Fotos de inicio»: el alumno saca en la app las tres fotos de su físico (frente, perfil y espalda) con una guía y un control
-- de calidad, y si quiere suma «el físico que te motiva». Reemplaza a las fotos del formulario de inscripción y a las que
-- llegaban por WhatsApp: el revisor de físico de la entrega las baja desde la Mini con la service_role.
--
-- Orden de despliegue: primero los endpoints de mini-vision (`nativa_fotos_inicio_minivision.mjs`), después este SQL.
-- Mientras esto no esté aplicado, `mypump_fotos_inicio_get` no existe (PGRST202): la app no muestra nada nuevo.
-- Sale APAGADO: `fotos_inicio` en false. Con la palanca prendida la sección le aparece solo a quien la Mini se la pidió
-- (`mypump_fotos_inicio_pedir`) y hasta que se cierra (`mypump_fotos_inicio_cerrar`): las entregas que ya están en curso
-- siguen por WhatsApp.
--
-- Invariantes:
--   · El `cliente_id` sale siempre del token. Sin RPC de escritura de paths por token: las fotos las registra mini-vision.
--   · `path` es relativo al bucket, nunca URL, y a la app no le llega nunca.
--   · El ancho y el alto los mide el servidor sobre el JPEG guardado, no los declara el teléfono.
--   · Una pose del cuerpo tiene una sola foto vigente: sacarla de nuevo la reemplaza. Con las tres, el set está completo.
--   · Ni anon ni authenticated leen las tablas ni el bucket: solo la service_role. Las fotos del cuerpo no se abren a nadie más.
BEGIN;

-- ── Bucket privado, sin políticas: solo la service_role ──
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('fotos-inicio', 'fotos-inicio', false, 4194304, ARRAY['image/jpeg'])
ON CONFLICT (id) DO NOTHING;

-- ── Tablas ──
-- Una fila por alumno al que se le pidieron. Sin fila no hay sección.
CREATE TABLE IF NOT EXISTS mypump_fotos_inicio_sets (
  cliente_id      TEXT        PRIMARY KEY,
  pedido_en       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  pedido_por      TEXT,
  nota_motivacion TEXT        CHECK (char_length(nota_motivacion) <= 300),   -- dato, nunca instrucción
  completado_en   TIMESTAMPTZ,            -- la primera vez que estuvieron frente, perfil y espalda
  actualizado_en  TIMESTAMPTZ,            -- el último cambio en una de esas tres
  motivacion_en   TIMESTAMPTZ,            -- el último cambio en «el físico que te motiva» (fotos o nota)
  leido_en        TIMESTAMPTZ,            -- hasta qué `actualizado_en` leyó el revisor (lo anota la Mini)
  cerrado_en      TIMESTAMPTZ             -- después de la entrega: la app deja de mostrar la sección
);

CREATE TABLE IF NOT EXISTS mypump_fotos_inicio (
  id             UUID        PRIMARY KEY,                               -- lo manda el teléfono: la subida es idempotente
  cliente_id     TEXT        NOT NULL REFERENCES mypump_fotos_inicio_sets (cliente_id),
  pose           TEXT        NOT NULL CHECK (pose IN ('frente','perfil','espalda','motivacion')),
  path           TEXT        NOT NULL UNIQUE CHECK (path !~ '^[a-z]+://'),
  bytes          INTEGER     NOT NULL CHECK (bytes > 0),
  ancho          INTEGER     NOT NULL CHECK (ancho > 0),
  alto           INTEGER     NOT NULL CHECK (alto > 0),
  tomada_en      TIMESTAMPTZ NOT NULL,                                  -- cuándo la sacó, según el teléfono
  brillo         REAL        CHECK (brillo BETWEEN 0 AND 255),          -- lo que midió el control del teléfono
  nitidez        REAL        CHECK (nitidez >= 0),
  vigente        BOOLEAN     NOT NULL DEFAULT TRUE,
  reemplazada_en TIMESTAMPTZ,
  creado_en      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  -- Con menos de 1080 px del lado largo la lectura del físico se descarta.
  CONSTRAINT fotos_inicio_resolucion CHECK (pose = 'motivacion' OR GREATEST(ancho, alto) >= 1080),
  CONSTRAINT fotos_inicio_reemplazo CHECK (vigente = (reemplazada_en IS NULL))
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_mypump_fotos_inicio_pose ON mypump_fotos_inicio (cliente_id, pose) WHERE vigente AND pose <> 'motivacion';
CREATE INDEX IF NOT EXISTS idx_mypump_fotos_inicio_cliente ON mypump_fotos_inicio (cliente_id) WHERE vigente;
CREATE INDEX IF NOT EXISTS idx_mypump_fotos_inicio_limpiar ON mypump_fotos_inicio (reemplazada_en) WHERE NOT vigente;

-- En este proyecto las tablas nuevas heredan permisos por defecto para anon y authenticated, incluido TRUNCATE, que RLS no
-- frena. Se sacan todos. RLS prendido y sin políticas: nadie más que la service_role.
REVOKE ALL ON mypump_fotos_inicio_sets, mypump_fotos_inicio FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON mypump_fotos_inicio_sets, mypump_fotos_inicio TO service_role;
ALTER TABLE mypump_fotos_inicio_sets ENABLE ROW LEVEL SECURITY;
ALTER TABLE mypump_fotos_inicio ENABLE ROW LEVEL SECURITY;

-- Lo que pidió AUTOMATIZAR, una fila por foto vigente: cliente_id, pose, tomada_en, ancho y alto, y si el set está completo.
CREATE OR REPLACE VIEW mypump_fotos_inicio_vista WITH (security_invoker = true) AS
  SELECT f.cliente_id, f.pose, f.tomada_en, f.ancho, f.alto, GREATEST(f.ancho, f.alto) AS lado_largo,
         f.id, f.path, f.bytes, f.brillo, f.nitidez, f.creado_en,
         (s.completado_en IS NOT NULL) AS set_completo, s.completado_en, s.actualizado_en, s.leido_en, s.cerrado_en
    FROM mypump_fotos_inicio f JOIN mypump_fotos_inicio_sets s USING (cliente_id)
   WHERE f.vigente;
REVOKE ALL ON mypump_fotos_inicio_vista FROM PUBLIC, anon, authenticated;
GRANT SELECT ON mypump_fotos_inicio_vista TO service_role;

-- ── Palanca: apagada ──
INSERT INTO mypump_app_config (clave, valor, nota) VALUES
  ('fotos_inicio', 'false'::JSONB, 'Fotos de inicio en la app. true = se muestran a quien se las pidió la Mini (mypump_fotos_inicio_pedir)')
ON CONFLICT (clave) DO NOTHING;

CREATE OR REPLACE FUNCTION mypump_fotos_inicio_max_motivacion()
RETURNS INTEGER LANGUAGE sql IMMUTABLE SET search_path = public AS $$ SELECT 4 $$;

CREATE OR REPLACE FUNCTION mypump_fotos_inicio_habilitado(p_cliente_id TEXT)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE((SELECT valor = 'true'::JSONB FROM mypump_app_config WHERE clave = 'fotos_inicio'), FALSE)
     AND EXISTS (SELECT 1 FROM mypump_fotos_inicio_sets WHERE cliente_id = p_cliente_id AND cerrado_en IS NULL);
$$;

-- ── La app, por token (anon y authenticated). NULL = token caído ──
-- Sin paths. Las fotos vigentes, en el orden de las poses.
CREATE OR REPLACE FUNCTION mypump_fotos_inicio_get(p_token TEXT)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_cliente_id TEXT;
  v_set        mypump_fotos_inicio_sets%ROWTYPE;
BEGIN
  v_cliente_id := mypump_get_cliente_id_from_token(p_token);
  IF v_cliente_id IS NULL THEN RETURN NULL; END IF;
  IF NOT mypump_fotos_inicio_habilitado(v_cliente_id) THEN RETURN jsonb_build_object('habilitado', FALSE); END IF;
  SELECT * INTO v_set FROM mypump_fotos_inicio_sets WHERE cliente_id = v_cliente_id;
  RETURN jsonb_build_object(
    'habilitado', TRUE,
    'completo', v_set.completado_en IS NOT NULL,
    'completado_en', v_set.completado_en,
    'nota', COALESCE(v_set.nota_motivacion, ''),
    'max_motivacion', mypump_fotos_inicio_max_motivacion(),
    'fotos', COALESCE((SELECT jsonb_agg(jsonb_build_object('id', f.id, 'pose', f.pose, 'tomada_en', f.tomada_en, 'ancho', f.ancho, 'alto', f.alto)
                                        ORDER BY array_position(ARRAY['frente','perfil','espalda','motivacion'], f.pose), f.creado_en, f.id)
                         FROM mypump_fotos_inicio f WHERE f.cliente_id = v_cliente_id AND f.vigente), '[]'::JSONB)
  );
END;
$$;

-- La nota de «el físico que te motiva». Vacía la borra.
CREATE OR REPLACE FUNCTION mypump_fotos_inicio_nota(p_token TEXT, p_nota TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_cliente_id TEXT;
  v_nota       TEXT := NULLIF(left(btrim(regexp_replace(COALESCE(p_nota, ''), '[[:cntrl:]]+', ' ', 'g')), 300), '');
BEGIN
  v_cliente_id := mypump_get_cliente_id_from_token(p_token);
  IF v_cliente_id IS NULL THEN RETURN NULL; END IF;
  IF NOT mypump_fotos_inicio_habilitado(v_cliente_id) THEN RETURN jsonb_build_object('ok', FALSE, 'error', 'no_habilitado'); END IF;
  UPDATE mypump_fotos_inicio_sets SET nota_motivacion = v_nota, motivacion_en = NOW()
   WHERE cliente_id = v_cliente_id AND nota_motivacion IS DISTINCT FROM v_nota;
  RETURN jsonb_build_object('ok', TRUE, 'nota', COALESCE(v_nota, ''));
END;
$$;

REVOKE ALL ON FUNCTION mypump_fotos_inicio_max_motivacion(), mypump_fotos_inicio_habilitado(TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION mypump_fotos_inicio_max_motivacion(), mypump_fotos_inicio_habilitado(TEXT) TO service_role;
REVOKE ALL ON FUNCTION mypump_fotos_inicio_get(TEXT), mypump_fotos_inicio_nota(TEXT, TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION mypump_fotos_inicio_get(TEXT), mypump_fotos_inicio_nota(TEXT, TEXT) TO anon, authenticated, service_role;

-- ── Mini-vision (service_role) ──
-- Antes de leer el cuerpo y otra vez, con el set trabado, al registrar. 'ok', 'ya', 'ajena', 'no_habilitado', 'tope'.
CREATE OR REPLACE FUNCTION mypump_fotos_inicio_puede(p_cliente_id TEXT, p_foto_id UUID, p_pose TEXT)
RETURNS TEXT
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_de TEXT;
BEGIN
  IF p_pose IS NULL OR p_pose NOT IN ('frente','perfil','espalda','motivacion') THEN RAISE EXCEPTION 'pose inválida' USING ERRCODE = '22023'; END IF;
  SELECT cliente_id INTO v_de FROM mypump_fotos_inicio WHERE id = p_foto_id;
  IF v_de = p_cliente_id THEN RETURN 'ya'; END IF;
  IF v_de IS NOT NULL THEN RETURN 'ajena'; END IF;
  IF NOT mypump_fotos_inicio_habilitado(p_cliente_id) THEN RETURN 'no_habilitado'; END IF;
  IF p_pose = 'motivacion' AND (SELECT count(*) FROM mypump_fotos_inicio WHERE cliente_id = p_cliente_id AND pose = 'motivacion' AND vigente) >= mypump_fotos_inicio_max_motivacion() THEN
    RETURN 'tope';
  END IF;
  RETURN 'ok';
END;
$$;

-- Registra la foto ya guardada. En una pose del cuerpo reemplaza a la vigente y devuelve en `borrar` lo que hay que sacar del bucket.
CREATE OR REPLACE FUNCTION mypump_fotos_inicio_registrar(
  p_cliente_id TEXT,
  p_foto_id    UUID,
  p_pose       TEXT,
  p_path       TEXT,
  p_bytes      INTEGER,
  p_ancho      INTEGER,
  p_alto       INTEGER,
  p_tomada_en  TIMESTAMPTZ DEFAULT NULL,
  p_brillo     REAL DEFAULT NULL,
  p_nitidez    REAL DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_puede  TEXT;
  v_borrar JSONB := '[]'::JSONB;
  v_tomada TIMESTAMPTZ := p_tomada_en;
BEGIN
  -- Traba el set: dos subidas de la misma cuenta se ordenan acá.
  PERFORM 1 FROM mypump_fotos_inicio_sets WHERE cliente_id = p_cliente_id FOR UPDATE;
  v_puede := mypump_fotos_inicio_puede(p_cliente_id, p_foto_id, p_pose);
  IF v_puede <> 'ok' THEN RETURN jsonb_build_object('resultado', v_puede, 'borrar', v_borrar); END IF;
  IF p_pose <> 'motivacion' AND GREATEST(p_ancho, p_alto) < 1080 THEN RETURN jsonb_build_object('resultado', 'chica', 'borrar', v_borrar); END IF;
  -- El reloj del teléfono puede estar mal: una fecha del futuro o ninguna, es ahora.
  IF v_tomada IS NULL OR v_tomada > NOW() + INTERVAL '1 day' THEN v_tomada := NOW(); END IF;

  IF p_pose <> 'motivacion' THEN
    WITH viejas AS (
      UPDATE mypump_fotos_inicio SET vigente = FALSE, reemplazada_en = NOW()
       WHERE cliente_id = p_cliente_id AND pose = p_pose AND vigente
      RETURNING id, path
    )
    SELECT COALESCE(jsonb_agg(jsonb_build_object('id', id, 'path', path)), '[]'::JSONB) INTO v_borrar FROM viejas;
  END IF;

  INSERT INTO mypump_fotos_inicio (id, cliente_id, pose, path, bytes, ancho, alto, tomada_en, brillo, nitidez)
  VALUES (p_foto_id, p_cliente_id, p_pose, p_path, p_bytes, p_ancho, p_alto, v_tomada,
          CASE WHEN p_brillo BETWEEN 0 AND 255 THEN p_brillo END, CASE WHEN p_nitidez >= 0 THEN p_nitidez END);

  IF p_pose = 'motivacion' THEN
    UPDATE mypump_fotos_inicio_sets SET motivacion_en = NOW() WHERE cliente_id = p_cliente_id;
  ELSE
    UPDATE mypump_fotos_inicio_sets s SET
      actualizado_en = NOW(),
      completado_en = COALESCE(s.completado_en, CASE WHEN (SELECT count(*) FROM mypump_fotos_inicio f
                                                            WHERE f.cliente_id = p_cliente_id AND f.vigente AND f.pose <> 'motivacion') = 3 THEN NOW() END)
    WHERE s.cliente_id = p_cliente_id;
  END IF;
  RETURN jsonb_build_object('resultado', 'ok', 'borrar', v_borrar);
END;
$$;

-- Saca una foto de «el físico que te motiva». Las del cuerpo no se borran: se reemplazan.
CREATE OR REPLACE FUNCTION mypump_fotos_inicio_borrar(p_cliente_id TEXT, p_foto_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_fila mypump_fotos_inicio%ROWTYPE;
BEGIN
  PERFORM 1 FROM mypump_fotos_inicio_sets WHERE cliente_id = p_cliente_id FOR UPDATE;
  SELECT * INTO v_fila FROM mypump_fotos_inicio WHERE id = p_foto_id AND cliente_id = p_cliente_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('resultado', 'no_encontrado'); END IF;
  IF NOT v_fila.vigente THEN RETURN jsonb_build_object('resultado', 'ok', 'id', v_fila.id, 'path', v_fila.path); END IF;
  IF v_fila.pose <> 'motivacion' THEN RETURN jsonb_build_object('resultado', 'no_se_puede'); END IF;
  IF NOT mypump_fotos_inicio_habilitado(p_cliente_id) THEN RETURN jsonb_build_object('resultado', 'no_habilitado'); END IF;
  UPDATE mypump_fotos_inicio SET vigente = FALSE, reemplazada_en = NOW() WHERE id = p_foto_id;
  UPDATE mypump_fotos_inicio_sets SET motivacion_en = NOW() WHERE cliente_id = p_cliente_id;
  RETURN jsonb_build_object('resultado', 'ok', 'id', v_fila.id, 'path', v_fila.path);
END;
$$;

-- El objeto ya no está en el bucket: se va la fila. Nunca una vigente.
CREATE OR REPLACE FUNCTION mypump_fotos_inicio_borrada(p_foto_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  DELETE FROM mypump_fotos_inicio WHERE id = p_foto_id AND NOT vigente;
  RETURN FOUND;
END;
$$;

-- Lo reemplazado o borrado cuyo objeto no se pudo sacar en el momento (para el barrido de la Mini).
CREATE OR REPLACE FUNCTION mypump_fotos_inicio_para_limpiar(p_limite INTEGER DEFAULT 50)
RETURNS TABLE (id UUID, path TEXT)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT f.id, f.path FROM mypump_fotos_inicio f WHERE NOT f.vigente ORDER BY f.reemplazada_en LIMIT GREATEST(1, LEAST(COALESCE(p_limite, 50), 500));
$$;

-- ── La Mini: Entregas y el revisor de físico (service_role) ──
-- Le pide las fotos a un alumno: desde acá le aparece la sección (con la palanca prendida). Idempotente; reabre una cerrada.
-- Con la sección ya visible y fotos por subir, le encola UN aviso (mypump_encolar_push, mig 058) con el destino
-- `fotos_inicio`: tocarlo abre justo la pantalla de las fotos. Uno solo por alumno (dedupe); pedir otra vez no repite.
-- Con la palanca apagada no avisa: el aviso sale en el primer `pedir` que se haga con la palanca prendida.
CREATE OR REPLACE FUNCTION mypump_fotos_inicio_pedir(p_cliente_id TEXT, p_por TEXT DEFAULT NULL)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_set mypump_fotos_inicio_sets%ROWTYPE;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM mypump_clientes WHERE cliente_id = p_cliente_id) THEN
    RETURN jsonb_build_object('ok', FALSE, 'error', 'sin_cuenta');   -- todavía no tiene cuenta de la app
  END IF;
  INSERT INTO mypump_fotos_inicio_sets (cliente_id, pedido_por) VALUES (p_cliente_id, NULLIF(btrim(COALESCE(p_por, '')), ''))
  ON CONFLICT (cliente_id) DO UPDATE SET cerrado_en = NULL
  RETURNING * INTO v_set;
  IF v_set.completado_en IS NULL AND mypump_fotos_inicio_habilitado(p_cliente_id) THEN
    PERFORM mypump_encolar_push(p_cliente_id, 'Mati', 'Necesito tus fotos de inicio. Tocá acá y las subís en un minuto',
                                'fotos_inicio', 'fotos-inicio:' || p_cliente_id);
  END IF;
  RETURN jsonb_build_object('ok', TRUE, 'pedido_en', v_set.pedido_en, 'completo', v_set.completado_en IS NOT NULL);
END;
$$;

-- Después de la entrega: la app deja de mostrar la sección. Las fotos quedan (son el «antes»).
CREATE OR REPLACE FUNCTION mypump_fotos_inicio_cerrar(p_cliente_id TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE mypump_fotos_inicio_sets SET cerrado_en = NOW() WHERE cliente_id = p_cliente_id AND cerrado_en IS NULL;
  RETURN FOUND;
END;
$$;

-- El set de un alumno con los paths, para firmar y bajar desde la Mini (`nativa_fotos_inicio_firmar.py`). NULL = no se le pidieron.
CREATE OR REPLACE FUNCTION mypump_fotos_inicio_servicio(p_cliente_id TEXT)
RETURNS JSONB
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT jsonb_build_object(
    'cliente_id', s.cliente_id,
    'bucket', 'fotos-inicio',
    'completo', s.completado_en IS NOT NULL,
    'completado_en', s.completado_en,
    'actualizado_en', s.actualizado_en,
    'motivacion_en', s.motivacion_en,
    'leido_en', s.leido_en,
    'pedido_en', s.pedido_en,
    'cerrado_en', s.cerrado_en,
    'nota_motivacion', s.nota_motivacion,
    'faltan', COALESCE((SELECT jsonb_agg(p ORDER BY o) FROM unnest(ARRAY['frente','perfil','espalda']) WITH ORDINALITY AS t(p, o)
                         WHERE NOT EXISTS (SELECT 1 FROM mypump_fotos_inicio f WHERE f.cliente_id = s.cliente_id AND f.pose = p AND f.vigente)), '[]'::JSONB),
    'fotos', COALESCE((SELECT jsonb_agg(jsonb_build_object(
                          'id', f.id, 'cliente_id', f.cliente_id, 'pose', f.pose, 'tomada_en', f.tomada_en, 'ancho', f.ancho, 'alto', f.alto,
                          'lado_largo', GREATEST(f.ancho, f.alto), 'bytes', f.bytes, 'brillo', f.brillo, 'nitidez', f.nitidez, 'path', f.path)
                          ORDER BY array_position(ARRAY['frente','perfil','espalda','motivacion'], f.pose), f.creado_en, f.id)
                         FROM mypump_fotos_inicio f WHERE f.cliente_id = s.cliente_id AND f.vigente), '[]'::JSONB)
  )
  FROM mypump_fotos_inicio_sets s WHERE s.cliente_id = p_cliente_id;
$$;

-- Los sets completos que el revisor todavía no leyó, o que cambiaron después de la última lectura. `p_reposo_min`: minutos
-- sin cambios, para no leer un set mientras el alumno está repitiendo fotos. Para consultar cada 10 minutos.
CREATE OR REPLACE FUNCTION mypump_fotos_inicio_pendientes(p_reposo_min INTEGER DEFAULT 10)
RETURNS TABLE (cliente_id TEXT, completado_en TIMESTAMPTZ, actualizado_en TIMESTAMPTZ, leido_en TIMESTAMPTZ)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT s.cliente_id, s.completado_en, s.actualizado_en, s.leido_en
    FROM mypump_fotos_inicio_sets s
   WHERE s.completado_en IS NOT NULL AND s.cerrado_en IS NULL
     AND (s.leido_en IS NULL OR s.actualizado_en > s.leido_en)
     AND s.actualizado_en <= NOW() - make_interval(mins => GREATEST(0, COALESCE(p_reposo_min, 10)))
   ORDER BY s.actualizado_en;
$$;

-- El revisor leyó el set tal como estaba en `p_hasta` (el `actualizado_en` que le devolvió `servicio`). Nunca retrocede.
CREATE OR REPLACE FUNCTION mypump_fotos_inicio_leido(p_cliente_id TEXT, p_hasta TIMESTAMPTZ)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_hasta IS NULL THEN RAISE EXCEPTION 'falta p_hasta' USING ERRCODE = '22023'; END IF;
  UPDATE mypump_fotos_inicio_sets SET leido_en = LEAST(p_hasta, actualizado_en)
   WHERE cliente_id = p_cliente_id AND completado_en IS NOT NULL AND (leido_en IS NULL OR leido_en < LEAST(p_hasta, actualizado_en));
  RETURN FOUND;
END;
$$;

REVOKE ALL ON FUNCTION
  mypump_fotos_inicio_puede(TEXT, UUID, TEXT),
  mypump_fotos_inicio_registrar(TEXT, UUID, TEXT, TEXT, INTEGER, INTEGER, INTEGER, TIMESTAMPTZ, REAL, REAL),
  mypump_fotos_inicio_borrar(TEXT, UUID), mypump_fotos_inicio_borrada(UUID), mypump_fotos_inicio_para_limpiar(INTEGER),
  mypump_fotos_inicio_pedir(TEXT, TEXT), mypump_fotos_inicio_cerrar(TEXT), mypump_fotos_inicio_servicio(TEXT),
  mypump_fotos_inicio_pendientes(INTEGER), mypump_fotos_inicio_leido(TEXT, TIMESTAMPTZ)
FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION
  mypump_fotos_inicio_puede(TEXT, UUID, TEXT),
  mypump_fotos_inicio_registrar(TEXT, UUID, TEXT, TEXT, INTEGER, INTEGER, INTEGER, TIMESTAMPTZ, REAL, REAL),
  mypump_fotos_inicio_borrar(TEXT, UUID), mypump_fotos_inicio_borrada(UUID), mypump_fotos_inicio_para_limpiar(INTEGER),
  mypump_fotos_inicio_pedir(TEXT, TEXT), mypump_fotos_inicio_cerrar(TEXT), mypump_fotos_inicio_servicio(TEXT),
  mypump_fotos_inicio_pendientes(INTEGER), mypump_fotos_inicio_leido(TEXT, TIMESTAMPTZ)
TO service_role;

NOTIFY pgrst, 'reload schema';
COMMIT;
