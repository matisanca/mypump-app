-- nativa_tecnica.sql — PROPUESTA, SIN APLICAR.
--
-- «Técnica por video»: el alumno manda el video de un ejercicio; la Mini lo analiza, deja una devolución `a_revisar`
-- y solo se publica con el OK de Mati, a las 24 a 48 horas de mandado (plazo variable), siempre de día.
--
-- Orden de despliegue: primero los endpoints de mini-vision, después este SQL, después el worker (ver ~tecnica/ESTADO.md).
-- Mientras esto no esté aplicado, `mypump_tecnica_get` no existe (PGRST202): la app no muestra nada nuevo.
-- Sale APAGADO: `tecnica_video` en false. Con la palanca prendida entra solo quien esté en `mypump_tecnica_habilitados`,
-- salvo `tecnica_para_todos` en true.
--
-- Invariantes:
--   · El `cliente_id` sale siempre del token. El path lo arma el servidor y a la app no le llega nunca.
--   · Lo que le llega al alumno es `devolucion` y nada de `resultado`: sin confianza, sin mediciones, sin rastro de cómo se hizo.
--   · Sin `aprobado_por` no hay publicación: la app dice «Lo revisó Mati», y eso solo es cierto con un OK humano.
--   · Con la palanca apagada no sale ningún video hacia el análisis, aunque haya filas en cola.
BEGIN;

-- ── Bucket privado ──
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('tecnica', 'tecnica', false, 62914560, ARRAY['video/mp4'])
ON CONFLICT (id) DO NOTHING;

-- La versión del aviso de terceros. Si cambia el texto, cambia esto.
CREATE OR REPLACE FUNCTION mypump_tecnica_consentimiento_vigente()
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
SET search_path = public
AS $$ SELECT 'terceros-tecnica-v1'::TEXT; $$;

-- La última barrera antes del alumno. El worker ya filtra; esto cubre también lo que se edite a mano.
CREATE OR REPLACE FUNCTION mypump_tecnica_texto_prohibido(p JSONB)
RETURNS BOOLEAN
LANGUAGE sql
IMMUTABLE
SET search_path = public
AS $$
  SELECT p::TEXT ~* '\yrir\y|reps? en reserva|repeticiones? en reserva|inteligencia artificial|\yIA\y|mediapipe|\yopus\y|\yclaude\y|algoritmo';
$$;

CREATE OR REPLACE FUNCTION mypump_tecnica_devolucion_valida(p JSONB)
RETURNS BOOLEAN
LANGUAGE sql
IMMUTABLE
SET search_path = public
AS $$
  SELECT jsonb_typeof(p) = 'object'
     AND jsonb_typeof(p->'bien') = 'array'
     AND jsonb_typeof(p->'correcciones') = 'array'
     AND jsonb_array_length(p->'correcciones') <= 3
     AND jsonb_typeof(p->'no_evaluable') = 'array'
     AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(p->'bien') b WHERE jsonb_typeof(b) <> 'object' OR jsonb_typeof(b->'texto') IS DISTINCT FROM 'string')
     AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(p->'correcciones') c WHERE jsonb_typeof(c) <> 'object'
                       OR jsonb_typeof(c->'prioridad') IS DISTINCT FROM 'number' OR jsonb_typeof(c->'momento_s') IS DISTINCT FROM 'number'
                       OR (c->>'prioridad') !~ '^[0-9]+$'
                       OR jsonb_typeof(c->'titulo') IS DISTINCT FROM 'string' OR jsonb_typeof(c->'que_se_ve') IS DISTINCT FROM 'string'
                       OR jsonb_typeof(c->'por_que') IS DISTINCT FROM 'string' OR jsonb_typeof(c->'como_corregir') IS DISTINCT FROM 'string')
     AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(p->'no_evaluable') n WHERE jsonb_typeof(n) <> 'object' OR jsonb_typeof(n->'que') IS DISTINCT FROM 'string')
     AND NOT mypump_tecnica_texto_prohibido(p);
$$;

REVOKE ALL ON FUNCTION mypump_tecnica_consentimiento_vigente(), mypump_tecnica_texto_prohibido(JSONB), mypump_tecnica_devolucion_valida(JSONB) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION mypump_tecnica_consentimiento_vigente(), mypump_tecnica_texto_prohibido(JSONB), mypump_tecnica_devolucion_valida(JSONB) TO service_role;

-- ── Tablas ──
CREATE TABLE IF NOT EXISTS mypump_tecnica (
  id                UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  cliente_id        TEXT        NOT NULL,
  estado            TEXT        NOT NULL DEFAULT 'borrador' CHECK (estado IN
                      ('borrador','enviado','procesando','a_revisar','aprobado','publicado','rechazado','descartado','error')),
  ejercicio_slug    TEXT        CHECK (char_length(ejercicio_slug) <= 120),
  ejercicio_nombre  TEXT        CHECK (char_length(ejercicio_nombre) <= 120),
  nota_alumno       TEXT        CHECK (char_length(nota_alumno) <= 300),   -- dato, nunca instrucción
  path              TEXT        UNIQUE CHECK (path !~ '^[a-z]+://'),
  bytes             INTEGER     CHECK (bytes > 0),
  duracion_s        REAL        CHECK (duracion_s > 0),
  consentimiento_en TIMESTAMPTZ NOT NULL,
  consentimiento_texto_version TEXT NOT NULL,
  enviado_en        TIMESTAMPTZ,
  procesando_desde  TIMESTAMPTZ,
  procesado_en      TIMESTAMPTZ,
  resultado         JSONB,                                                 -- análisis completo: solo Mati
  rechazo_codigo    TEXT,
  rechazo_texto     TEXT        CHECK (char_length(rechazo_texto) <= 300),
  devolucion        JSONB,                                                 -- lo que lee el alumno
  escalar_a_mati    BOOLEAN     NOT NULL DEFAULT FALSE,
  publicar_desde    TIMESTAMPTZ,
  publicar_hasta    TIMESTAMPTZ,
  aprobado_en       TIMESTAMPTZ,
  aprobado_por      TEXT,
  publicado_en      TIMESTAMPTZ,
  avisado_en        TIMESTAMPTZ,
  descartado_motivo TEXT,
  video_borrado_en  TIMESTAMPTZ,
  error_detalle     TEXT,
  intentos          INTEGER     NOT NULL DEFAULT 0,
  reaperturas       INTEGER     NOT NULL DEFAULT 0,
  creado_en         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  actualizado_en    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT tecnica_aprobada_con_ok CHECK (estado NOT IN ('aprobado','publicado')
    OR (length(btrim(COALESCE(aprobado_por, ''))) > 0 AND aprobado_en IS NOT NULL AND devolucion IS NOT NULL AND publicar_desde IS NOT NULL)),
  CONSTRAINT tecnica_enviada_con_video CHECK (estado IN ('borrador','descartado') OR video_borrado_en IS NOT NULL OR path IS NOT NULL OR estado = 'rechazado')
);

-- Un solo análisis abierto por alumno.
CREATE UNIQUE INDEX IF NOT EXISTS uq_mypump_tecnica_abierta ON mypump_tecnica (cliente_id) WHERE estado IN ('borrador','enviado','procesando');
CREATE INDEX IF NOT EXISTS idx_mypump_tecnica_cola ON mypump_tecnica (estado, enviado_en) WHERE estado IN ('enviado','procesando');
CREATE INDEX IF NOT EXISTS idx_mypump_tecnica_cliente ON mypump_tecnica (cliente_id, creado_en DESC);

CREATE TABLE IF NOT EXISTS mypump_tecnica_habilitados (
  cliente_id    TEXT        PRIMARY KEY,
  motivo        TEXT,
  habilitado_en TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- En este proyecto las tablas nuevas heredan permisos por defecto, incluido TRUNCATE, que RLS no frena. anon, nada.
REVOKE ALL ON mypump_tecnica, mypump_tecnica_habilitados FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON mypump_tecnica, mypump_tecnica_habilitados TO service_role;
ALTER TABLE mypump_tecnica ENABLE ROW LEVEL SECURITY;
ALTER TABLE mypump_tecnica_habilitados ENABLE ROW LEVEL SECURITY;

-- ── Palanca: apagada ──
INSERT INTO mypump_app_config (clave, valor, nota) VALUES
  ('tecnica_video', 'false'::JSONB, 'Técnica por video. true = abierto a mypump_tecnica_habilitados'),
  ('tecnica_para_todos', 'false'::JSONB, 'Técnica por video. true = abierto a todos, sin mirar mypump_tecnica_habilitados')
ON CONFLICT (clave) DO NOTHING;

CREATE OR REPLACE FUNCTION mypump_tecnica_habilitado(p_cliente_id TEXT)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE((SELECT valor = 'true'::JSONB FROM mypump_app_config WHERE clave = 'tecnica_video'), FALSE)
     AND (COALESCE((SELECT valor = 'true'::JSONB FROM mypump_app_config WHERE clave = 'tecnica_para_todos'), FALSE)
          OR EXISTS (SELECT 1 FROM mypump_tecnica_habilitados WHERE cliente_id = p_cliente_id));
$$;

-- ── Lo que ve el alumno. Sin path, sin resultado, sin confianza ──
-- El trabajo interno se ve siempre igual: «en revisión». La devolución aparece recién publicada.
CREATE OR REPLACE FUNCTION mypump_tecnica_vista_alumno(r mypump_tecnica)
RETURNS JSONB
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT jsonb_build_object(
    'id', r.id,
    'estado', CASE WHEN r.estado IN ('procesando','a_revisar','aprobado','error') THEN 'enviado' ELSE r.estado END,
    'ejercicio_slug', r.ejercicio_slug,
    'ejercicio_nombre', r.ejercicio_nombre,
    'nota_alumno', r.nota_alumno,
    'enviado_en', r.enviado_en,
    'tiene_video', r.path IS NOT NULL AND r.video_borrado_en IS NULL,
    'rechazo_texto', CASE WHEN r.estado = 'rechazado' THEN r.rechazo_texto END,
    'publicado_en', CASE WHEN r.estado = 'publicado' THEN r.publicado_en END,
    'devolucion', CASE WHEN r.estado = 'publicado' THEN jsonb_build_object(
        'credito', 'Lo revisó Mati',
        'ejercicio', r.devolucion->>'ejercicio',
        'bien', COALESCE((SELECT jsonb_agg(b->>'texto') FROM jsonb_array_elements(r.devolucion->'bien') b), '[]'::JSONB),
        'correcciones', COALESCE((SELECT jsonb_agg(jsonb_build_object('prioridad', (c->>'prioridad')::INTEGER, 'titulo', c->>'titulo', 'que_se_ve', c->>'que_se_ve',
                                   'por_que', c->>'por_que', 'como_corregir', c->>'como_corregir', 'momento_s', (c->>'momento_s')::REAL) ORDER BY (c->>'prioridad')::INTEGER)
                                  FROM jsonb_array_elements(r.devolucion->'correcciones') c), '[]'::JSONB),
        'no_evaluable', COALESCE((SELECT jsonb_agg(jsonb_build_object('que', n->>'que', 'motivo', n->>'motivo')) FROM jsonb_array_elements(r.devolucion->'no_evaluable') n), '[]'::JSONB),
        'pedir_otro_video', r.devolucion->'pedir_otro_video'
      ) END
  );
$$;

-- ── La app, por token. NULL = token caído ──
CREATE OR REPLACE FUNCTION mypump_tecnica_get(p_token TEXT)
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
  IF NOT mypump_tecnica_habilitado(v_cliente_id) THEN RETURN jsonb_build_object('habilitado', FALSE); END IF;
  RETURN jsonb_build_object(
    'habilitado', TRUE,
    'consentimiento_version', mypump_tecnica_consentimiento_vigente(),
    'consentimiento_aceptado', EXISTS (SELECT 1 FROM mypump_tecnica WHERE cliente_id = v_cliente_id AND consentimiento_texto_version = mypump_tecnica_consentimiento_vigente()),
    'topes', jsonb_build_object('duracion_min_s', 4, 'duracion_max_s', 75, 'bytes_max', 62914560, 'por_semana', 3),
    'envios', COALESCE((SELECT jsonb_agg(mypump_tecnica_vista_alumno(t) ORDER BY t.creado_en DESC)
                        FROM (SELECT * FROM mypump_tecnica WHERE cliente_id = v_cliente_id AND estado <> 'descartado' ORDER BY creado_en DESC LIMIT 20) t), '[]'::JSONB)
  );
END;
$$;

-- Abre un envío, o devuelve el borrador que ya estaba. Tope: 3 por semana y uno abierto por vez.
CREATE OR REPLACE FUNCTION mypump_tecnica_nuevo(
  p_token          TEXT,
  p_ejercicio_slug TEXT,
  p_ejercicio_nombre TEXT,
  p_nota           TEXT,
  p_consentimiento TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_cliente_id TEXT;
  v_fila       mypump_tecnica%ROWTYPE;
BEGIN
  v_cliente_id := mypump_get_cliente_id_from_token(p_token);
  IF v_cliente_id IS NULL THEN RETURN NULL; END IF;
  IF NOT mypump_tecnica_habilitado(v_cliente_id) THEN RETURN jsonb_build_object('ok', FALSE, 'error', 'no_habilitado'); END IF;
  IF p_consentimiento IS DISTINCT FROM mypump_tecnica_consentimiento_vigente() THEN RETURN jsonb_build_object('ok', FALSE, 'error', 'consentimiento'); END IF;
  IF char_length(COALESCE(p_nota, '')) > 300 OR char_length(COALESCE(p_ejercicio_slug, '')) > 120 OR char_length(COALESCE(p_ejercicio_nombre, '')) > 120 THEN
    RAISE EXCEPTION 'texto muy largo' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_fila FROM mypump_tecnica WHERE cliente_id = v_cliente_id AND estado IN ('borrador','enviado','procesando');
  IF FOUND THEN
    IF v_fila.estado = 'borrador' THEN
      UPDATE mypump_tecnica SET ejercicio_slug = p_ejercicio_slug, ejercicio_nombre = p_ejercicio_nombre, nota_alumno = NULLIF(btrim(p_nota), ''), actualizado_en = NOW() WHERE id = v_fila.id;
      RETURN jsonb_build_object('ok', TRUE, 'ya', TRUE, 'id', v_fila.id, 'estado', 'borrador');
    END IF;
    RETURN jsonb_build_object('ok', FALSE, 'error', 'en_curso', 'id', v_fila.id);
  END IF;
  IF (SELECT count(*) FROM mypump_tecnica WHERE cliente_id = v_cliente_id AND enviado_en > NOW() - INTERVAL '7 days' AND estado <> 'rechazado') >= 3 THEN
    RETURN jsonb_build_object('ok', FALSE, 'error', 'tope_semanal');
  END IF;

  BEGIN
    INSERT INTO mypump_tecnica (cliente_id, ejercicio_slug, ejercicio_nombre, nota_alumno, consentimiento_en, consentimiento_texto_version)
    VALUES (v_cliente_id, p_ejercicio_slug, p_ejercicio_nombre, NULLIF(btrim(p_nota), ''), NOW(), p_consentimiento)
    RETURNING * INTO v_fila;
  EXCEPTION WHEN unique_violation THEN
    RETURN jsonb_build_object('ok', FALSE, 'error', 'reintentar');
  END;
  RETURN jsonb_build_object('ok', TRUE, 'ya', FALSE, 'id', v_fila.id, 'estado', 'borrador');
END;
$$;

-- El alumno se arrepiente antes de subir.
CREATE OR REPLACE FUNCTION mypump_tecnica_cancelar(p_token TEXT, p_id UUID)
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
  DELETE FROM mypump_tecnica WHERE id = p_id AND cliente_id = v_cliente_id AND estado = 'borrador';
  RETURN jsonb_build_object('ok', TRUE, 'borrado', FOUND);
END;
$$;

REVOKE ALL ON FUNCTION mypump_tecnica_habilitado(TEXT), mypump_tecnica_vista_alumno(mypump_tecnica) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION mypump_tecnica_habilitado(TEXT), mypump_tecnica_vista_alumno(mypump_tecnica) TO service_role;
REVOKE ALL ON FUNCTION mypump_tecnica_get(TEXT), mypump_tecnica_nuevo(TEXT, TEXT, TEXT, TEXT, TEXT), mypump_tecnica_cancelar(TEXT, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION mypump_tecnica_get(TEXT), mypump_tecnica_nuevo(TEXT, TEXT, TEXT, TEXT, TEXT), mypump_tecnica_cancelar(TEXT, UUID) TO anon, authenticated, service_role;

-- ── mini-vision (service_role) ──
CREATE OR REPLACE FUNCTION mypump_tecnica_puede(p_cliente_id TEXT, p_id UUID)
RETURNS TEXT
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_fila mypump_tecnica%ROWTYPE;
BEGIN
  SELECT * INTO v_fila FROM mypump_tecnica WHERE id = p_id;
  IF NOT FOUND OR v_fila.cliente_id <> p_cliente_id THEN RETURN 'no_encontrado'; END IF;
  IF v_fila.path IS NOT NULL THEN RETURN 'ya'; END IF;
  IF NOT mypump_tecnica_habilitado(p_cliente_id) THEN RETURN 'no_habilitado'; END IF;
  IF v_fila.estado <> 'borrador' THEN RETURN 'estado'; END IF;
  RETURN 'ok';
END;
$$;

-- Registrar el video es enviarlo: pasa a `enviado` en la misma operación.
CREATE OR REPLACE FUNCTION mypump_tecnica_registrar(p_cliente_id TEXT, p_id UUID, p_path TEXT, p_bytes INTEGER, p_duracion REAL)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_fila mypump_tecnica%ROWTYPE;
BEGIN
  SELECT * INTO v_fila FROM mypump_tecnica WHERE id = p_id FOR UPDATE;
  IF NOT FOUND OR v_fila.cliente_id <> p_cliente_id THEN RETURN 'no_encontrado'; END IF;
  IF v_fila.path IS NOT NULL THEN RETURN 'ya'; END IF;
  IF NOT mypump_tecnica_habilitado(p_cliente_id) THEN RETURN 'no_habilitado'; END IF;
  IF v_fila.estado <> 'borrador' THEN RETURN 'estado'; END IF;
  UPDATE mypump_tecnica SET path = p_path, bytes = p_bytes, duracion_s = p_duracion, estado = 'enviado', enviado_en = NOW(), actualizado_en = NOW() WHERE id = p_id;
  RETURN 'ok';
END;
$$;

-- El alumno saca su video. Una devolución ya publicada queda; un envío todavía sin analizar se cierra.
CREATE OR REPLACE FUNCTION mypump_tecnica_borrar_video(p_cliente_id TEXT, p_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_fila mypump_tecnica%ROWTYPE;
BEGIN
  SELECT * INTO v_fila FROM mypump_tecnica WHERE id = p_id FOR UPDATE;
  IF NOT FOUND OR v_fila.cliente_id <> p_cliente_id THEN RETURN jsonb_build_object('resultado', 'no_encontrado'); END IF;
  IF v_fila.path IS NULL OR v_fila.video_borrado_en IS NOT NULL THEN RETURN jsonb_build_object('resultado', 'no_encontrado'); END IF;
  IF v_fila.estado = 'procesando' THEN RETURN jsonb_build_object('resultado', 'estado'); END IF;
  UPDATE mypump_tecnica SET video_borrado_en = NOW(),
         estado = CASE WHEN estado IN ('enviado','a_revisar','aprobado','error') THEN 'descartado' ELSE estado END,
         descartado_motivo = CASE WHEN estado IN ('enviado','a_revisar','aprobado','error') THEN 'el alumno borró el video' ELSE descartado_motivo END,
         actualizado_en = NOW()
   WHERE id = p_id;
  RETURN jsonb_build_object('resultado', 'ok', 'path', v_fila.path);
END;
$$;

-- ── El worker (service_role) ──
CREATE OR REPLACE FUNCTION mypump_tecnica_tomar()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_fila mypump_tecnica%ROWTYPE;
BEGIN
  IF NOT COALESCE((SELECT valor = 'true'::JSONB FROM mypump_app_config WHERE clave = 'tecnica_video'), FALSE) THEN RETURN NULL; END IF;
  -- De a uno en todo el servicio: la cuota de Claude es compartida con producción.
  IF EXISTS (SELECT 1 FROM mypump_tecnica WHERE estado = 'procesando') THEN RETURN NULL; END IF;
  SELECT * INTO v_fila FROM mypump_tecnica WHERE estado = 'enviado' AND path IS NOT NULL AND video_borrado_en IS NULL ORDER BY enviado_en, id LIMIT 1 FOR UPDATE SKIP LOCKED;
  IF NOT FOUND THEN RETURN NULL; END IF;
  UPDATE mypump_tecnica SET estado = 'procesando', procesando_desde = NOW(), intentos = intentos + 1, actualizado_en = NOW() WHERE id = v_fila.id RETURNING * INTO v_fila;
  RETURN to_jsonb(v_fila) - 'resultado' - 'devolucion';
END;
$$;

-- `p_contar` FALSE: se frenó por cuota, no fue culpa de la fila.
CREATE OR REPLACE FUNCTION mypump_tecnica_devolver(p_id UUID, p_contar BOOLEAN DEFAULT TRUE, p_detalle TEXT DEFAULT NULL)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  UPDATE mypump_tecnica SET estado = 'enviado', procesando_desde = NULL,
         intentos = CASE WHEN p_contar THEN intentos ELSE GREATEST(intentos - 1, 0) END,
         error_detalle = COALESCE(left(p_detalle, 500), error_detalle), actualizado_en = NOW()
   WHERE id = p_id AND estado = 'procesando' RETURNING TRUE;
$$;

CREATE OR REPLACE FUNCTION mypump_tecnica_liberar_colgadas(p_minutos INTEGER DEFAULT 45, p_max_intentos INTEGER DEFAULT 3)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  n INTEGER;
BEGIN
  WITH x AS (
    UPDATE mypump_tecnica SET estado = CASE WHEN intentos >= p_max_intentos THEN 'error' ELSE 'enviado' END,
           error_detalle = CASE WHEN intentos >= p_max_intentos THEN 'colgada varias veces' ELSE error_detalle END, procesando_desde = NULL, actualizado_en = NOW()
     WHERE estado = 'procesando' AND procesando_desde < NOW() - make_interval(mins => p_minutos) RETURNING 1)
  SELECT count(*) INTO n FROM x;
  RETURN n;
END;
$$;

CREATE OR REPLACE FUNCTION mypump_tecnica_reabrir_errores(p_horas INTEGER DEFAULT 6, p_max INTEGER DEFAULT 3)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  n INTEGER;
BEGIN
  WITH x AS (
    UPDATE mypump_tecnica SET estado = 'enviado', intentos = 0, reaperturas = reaperturas + 1, actualizado_en = NOW()
     WHERE estado = 'error' AND reaperturas < p_max AND actualizado_en < NOW() - make_interval(hours => p_horas) AND path IS NOT NULL AND video_borrado_en IS NULL
       AND COALESCE(error_detalle, '') NOT ILIKE '%SalidaInvalida%'      -- si el modelo no da una salida válida, reintentar solo gasta cuota
       AND NOT EXISTS (SELECT 1 FROM mypump_tecnica o WHERE o.cliente_id = mypump_tecnica.cliente_id AND o.estado IN ('borrador','enviado','procesando'))
     RETURNING 1)
  SELECT count(*) INTO n FROM x;
  RETURN n;
END;
$$;

-- El resultado del worker. Solo desde `procesando`. `a_revisar` lleva propuesta y ventana; `rechazado`, el texto para el alumno.
CREATE OR REPLACE FUNCTION mypump_tecnica_guardar(
  p_id             UUID,
  p_estado         TEXT,
  p_resultado      JSONB,
  p_propuesta      JSONB DEFAULT NULL,
  p_escalar        BOOLEAN DEFAULT FALSE,
  p_publicar_desde TIMESTAMPTZ DEFAULT NULL,
  p_publicar_hasta TIMESTAMPTZ DEFAULT NULL,
  p_rechazo_codigo TEXT DEFAULT NULL,
  p_rechazo_texto  TEXT DEFAULT NULL,
  p_error          TEXT DEFAULT NULL
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_fila mypump_tecnica%ROWTYPE;
BEGIN
  IF p_estado NOT IN ('a_revisar','rechazado','error') THEN RAISE EXCEPTION 'estado inválido' USING ERRCODE = '22023'; END IF;
  IF p_estado = 'a_revisar' AND (p_propuesta IS NULL OR NOT mypump_tecnica_devolucion_valida(p_propuesta) OR p_publicar_desde IS NULL OR p_publicar_hasta IS NULL OR p_publicar_hasta < p_publicar_desde) THEN
    RAISE EXCEPTION 'propuesta o ventana inválidas' USING ERRCODE = '22023';
  END IF;
  IF p_estado = 'rechazado' AND length(btrim(COALESCE(p_rechazo_texto, ''))) = 0 THEN RAISE EXCEPTION 'rechazo sin texto' USING ERRCODE = '22023'; END IF;
  SELECT * INTO v_fila FROM mypump_tecnica WHERE id = p_id FOR UPDATE;
  IF NOT FOUND OR v_fila.estado <> 'procesando' THEN RETURN FALSE; END IF;
  UPDATE mypump_tecnica SET estado = p_estado, resultado = COALESCE(p_resultado, resultado), devolucion = p_propuesta, escalar_a_mati = COALESCE(p_escalar, FALSE),
         publicar_desde = p_publicar_desde, publicar_hasta = p_publicar_hasta, rechazo_codigo = left(p_rechazo_codigo, 40), rechazo_texto = left(p_rechazo_texto, 300),
         error_detalle = left(p_error, 500), procesado_en = NOW(), procesando_desde = NULL, intentos = 0, actualizado_en = NOW()
   WHERE id = p_id;
  RETURN TRUE;
END;
$$;

-- ── Mati (service_role, desde la sesión que le arma el OK) ──
CREATE OR REPLACE FUNCTION mypump_tecnica_a_revisar(p_limite INTEGER DEFAULT 30)
RETURNS JSONB
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(jsonb_agg(to_jsonb(t) ORDER BY t.escalar_a_mati DESC, t.publicar_desde), '[]'::JSONB)
  FROM (SELECT * FROM mypump_tecnica WHERE estado = 'a_revisar' ORDER BY escalar_a_mati DESC, publicar_desde LIMIT p_limite) t;
$$;

-- Siempre de día en Argentina, y con la palanca prendida.
CREATE OR REPLACE FUNCTION mypump_tecnica_hora_de_publicar()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXTRACT(HOUR FROM NOW() AT TIME ZONE 'America/Argentina/Buenos_Aires') BETWEEN 10 AND 19;
$$;

CREATE OR REPLACE FUNCTION mypump_tecnica_palanca()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE((SELECT valor = 'true'::JSONB FROM mypump_app_config WHERE clave = 'tecnica_video'), FALSE);
$$;

REVOKE ALL ON FUNCTION mypump_tecnica_hora_de_publicar(), mypump_tecnica_palanca() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION mypump_tecnica_hora_de_publicar(), mypump_tecnica_palanca() TO service_role;

-- El OK de Mati. `p_devolucion` es la versión final, editada o no. Antes de la ventana queda `aprobado` y sale sola cuando llega la hora.
CREATE OR REPLACE FUNCTION mypump_tecnica_aprobar(p_id UUID, p_devolucion JSONB, p_aprobado_por TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_fila mypump_tecnica%ROWTYPE;
  v_final JSONB;
BEGIN
  IF length(btrim(COALESCE(p_aprobado_por, ''))) = 0 THEN RAISE EXCEPTION 'falta quién aprueba' USING ERRCODE = '22023'; END IF;
  SELECT * INTO v_fila FROM mypump_tecnica WHERE id = p_id FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', FALSE, 'error', 'no_encontrado'); END IF;
  IF v_fila.estado IN ('aprobado','publicado') THEN RETURN jsonb_build_object('ok', TRUE, 'ya', TRUE, 'estado', v_fila.estado); END IF;
  IF v_fila.estado <> 'a_revisar' THEN RETURN jsonb_build_object('ok', FALSE, 'error', 'estado_invalido'); END IF;
  v_final := COALESCE(p_devolucion, v_fila.devolucion);
  IF NOT mypump_tecnica_devolucion_valida(v_final) THEN RETURN jsonb_build_object('ok', FALSE, 'error', 'devolucion_invalida'); END IF;
  UPDATE mypump_tecnica SET devolucion = v_final, aprobado_por = btrim(p_aprobado_por), aprobado_en = NOW(),
         estado = CASE WHEN NOW() >= publicar_desde AND mypump_tecnica_hora_de_publicar() AND mypump_tecnica_palanca() THEN 'publicado' ELSE 'aprobado' END,
         publicado_en = CASE WHEN NOW() >= publicar_desde AND mypump_tecnica_hora_de_publicar() AND mypump_tecnica_palanca() THEN NOW() END, actualizado_en = NOW()
   WHERE id = p_id RETURNING * INTO v_fila;
  RETURN jsonb_build_object('ok', TRUE, 'ya', FALSE, 'estado', v_fila.estado, 'publicar_desde', v_fila.publicar_desde);
END;
$$;

CREATE OR REPLACE FUNCTION mypump_tecnica_descartar(p_id UUID, p_motivo TEXT, p_por TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_fila mypump_tecnica%ROWTYPE;
BEGIN
  IF length(btrim(COALESCE(p_por, ''))) = 0 THEN RAISE EXCEPTION 'falta quién descarta' USING ERRCODE = '22023'; END IF;
  SELECT * INTO v_fila FROM mypump_tecnica WHERE id = p_id FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', FALSE, 'error', 'no_encontrado'); END IF;
  IF v_fila.estado NOT IN ('a_revisar','aprobado','error') THEN RETURN jsonb_build_object('ok', FALSE, 'error', 'estado_invalido'); END IF;
  UPDATE mypump_tecnica SET estado = 'descartado', descartado_motivo = left(p_motivo || ' (' || p_por || ')', 300), actualizado_en = NOW() WHERE id = p_id;
  RETURN jsonb_build_object('ok', TRUE);
END;
$$;

-- Lo aprobado que ya llegó a su hora. Lo corre el worker.
CREATE OR REPLACE FUNCTION mypump_tecnica_publicar_vencidas()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  n INTEGER;
BEGIN
  WITH x AS (UPDATE mypump_tecnica SET estado = 'publicado', publicado_en = NOW(), actualizado_en = NOW() WHERE estado = 'aprobado' AND NOW() >= publicar_desde AND mypump_tecnica_hora_de_publicar() AND mypump_tecnica_palanca() RETURNING 1)
  SELECT count(*) INTO n FROM x;
  RETURN n;
END;
$$;

CREATE OR REPLACE FUNCTION mypump_tecnica_avisado(p_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  UPDATE mypump_tecnica SET avisado_en = COALESCE(avisado_en, NOW()), actualizado_en = NOW() WHERE id = p_id AND estado = 'publicado' RETURNING TRUE;
$$;

-- Los videos se borran a los 90 días de mandados. La devolución queda.
CREATE OR REPLACE FUNCTION mypump_tecnica_para_limpiar(p_dias INTEGER DEFAULT 90, p_limite INTEGER DEFAULT 20)
RETURNS JSONB
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(jsonb_agg(jsonb_build_object('id', t.id, 'path', t.path)), '[]'::JSONB)
  FROM (SELECT id, path FROM mypump_tecnica
         WHERE video_borrado_en IS NULL AND path IS NOT NULL AND enviado_en < NOW() - make_interval(days => p_dias) AND estado NOT IN ('enviado','procesando')
         ORDER BY enviado_en LIMIT p_limite) t;
$$;

CREATE OR REPLACE FUNCTION mypump_tecnica_limpieza_hecha(p_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  UPDATE mypump_tecnica SET video_borrado_en = NOW(), actualizado_en = NOW() WHERE id = p_id AND estado NOT IN ('enviado','procesando') AND video_borrado_en IS NULL RETURNING TRUE;
$$;

REVOKE ALL ON FUNCTION
  mypump_tecnica_puede(TEXT, UUID), mypump_tecnica_registrar(TEXT, UUID, TEXT, INTEGER, REAL), mypump_tecnica_borrar_video(TEXT, UUID),
  mypump_tecnica_tomar(), mypump_tecnica_devolver(UUID, BOOLEAN, TEXT), mypump_tecnica_liberar_colgadas(INTEGER, INTEGER), mypump_tecnica_reabrir_errores(INTEGER, INTEGER),
  mypump_tecnica_guardar(UUID, TEXT, JSONB, JSONB, BOOLEAN, TIMESTAMPTZ, TIMESTAMPTZ, TEXT, TEXT, TEXT),
  mypump_tecnica_a_revisar(INTEGER), mypump_tecnica_aprobar(UUID, JSONB, TEXT), mypump_tecnica_descartar(UUID, TEXT, TEXT), mypump_tecnica_publicar_vencidas(),
  mypump_tecnica_avisado(UUID), mypump_tecnica_para_limpiar(INTEGER, INTEGER), mypump_tecnica_limpieza_hecha(UUID)
FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION
  mypump_tecnica_puede(TEXT, UUID), mypump_tecnica_registrar(TEXT, UUID, TEXT, INTEGER, REAL), mypump_tecnica_borrar_video(TEXT, UUID),
  mypump_tecnica_tomar(), mypump_tecnica_devolver(UUID, BOOLEAN, TEXT), mypump_tecnica_liberar_colgadas(INTEGER, INTEGER), mypump_tecnica_reabrir_errores(INTEGER, INTEGER),
  mypump_tecnica_guardar(UUID, TEXT, JSONB, JSONB, BOOLEAN, TIMESTAMPTZ, TIMESTAMPTZ, TEXT, TEXT, TEXT),
  mypump_tecnica_a_revisar(INTEGER), mypump_tecnica_aprobar(UUID, JSONB, TEXT), mypump_tecnica_descartar(UUID, TEXT, TEXT), mypump_tecnica_publicar_vencidas(),
  mypump_tecnica_avisado(UUID), mypump_tecnica_para_limpiar(INTEGER, INTEGER), mypump_tecnica_limpieza_hecha(UUID)
TO service_role;

NOTIFY pgrst, 'reload schema';
COMMIT;
