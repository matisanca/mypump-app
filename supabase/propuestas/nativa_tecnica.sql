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
--   · Sin aprobación no hay publicación: la app dice «Lo revisó Mati», y eso solo es cierto con un OK humano. La aprobación exige un código
--     de un solo uso, atado al envío y al texto exacto; quién y cuándo quedan en `mypump_tecnica_aprobaciones`. Un nombre escrito no alcanza.
--   · Una ventana vencida nunca publica sola, ni siquiera algo ya aprobado: hace falta decidir otra vez, con `p_fuera_de_plazo`.
--   · Con la palanca apagada no sale ningún video hacia el análisis, aunque haya filas en cola.
BEGIN;

-- ── Bucket privado ──
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('tecnica', 'tecnica', false, 62914560, ARRAY['video/mp4'])
ON CONFLICT (id) DO NOTHING;

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

REVOKE ALL ON FUNCTION mypump_tecnica_texto_prohibido(JSONB), mypump_tecnica_devolucion_valida(JSONB) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION mypump_tecnica_texto_prohibido(JSONB), mypump_tecnica_devolucion_valida(JSONB) TO service_role;

-- ── Tablas ──
-- Una fila por código emitido: guarda el hash, nunca el código. service_role no la toca: solo por las funciones de abajo.
-- Sin FK hacia `mypump_tecnica`: el registro sobrevive si se borra el envío, y no tiene datos del alumno.
CREATE TABLE IF NOT EXISTS mypump_tecnica_aprobaciones (
  id                UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  envio_id          UUID        NOT NULL,
  codigo_hash       TEXT        NOT NULL,
  devolucion_hash   TEXT        NOT NULL,
  por               TEXT        NOT NULL CHECK (length(btrim(por)) > 0 AND char_length(por) <= 120),
  emitido_en        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  vence_en          TIMESTAMPTZ NOT NULL,
  usado_en          TIMESTAMPTZ,
  anulado_en        TIMESTAMPTZ,
  intentos_fallidos INTEGER     NOT NULL DEFAULT 0,
  UNIQUE (id, envio_id)
);
CREATE INDEX IF NOT EXISTS idx_mypump_tecnica_aprobaciones_envio ON mypump_tecnica_aprobaciones (envio_id, emitido_en DESC);

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
  aprobacion_id     UUID,
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
    OR (length(btrim(COALESCE(aprobado_por, ''))) > 0 AND aprobado_en IS NOT NULL AND aprobacion_id IS NOT NULL AND devolucion IS NOT NULL AND publicar_desde IS NOT NULL AND publicar_hasta IS NOT NULL)),
  CONSTRAINT tecnica_aprobacion_del_envio FOREIGN KEY (aprobacion_id, id) REFERENCES mypump_tecnica_aprobaciones (id, envio_id),
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
REVOKE ALL ON mypump_tecnica_aprobaciones FROM PUBLIC, anon, authenticated, service_role;
-- Sobre los envíos, service_role solo lee: todo lo que cambia un envío pasa por las funciones DEFINER, que exigen el código de Mati
-- para aprobar. Con UPDATE directo se podía publicar «de costado» o cambiar el texto de una fila ya aprobada.
REVOKE ALL ON mypump_tecnica FROM service_role;
GRANT SELECT ON mypump_tecnica TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON mypump_tecnica_habilitados TO service_role;
ALTER TABLE mypump_tecnica ENABLE ROW LEVEL SECURITY;
ALTER TABLE mypump_tecnica_habilitados ENABLE ROW LEVEL SECURITY;
ALTER TABLE mypump_tecnica_aprobaciones ENABLE ROW LEVEL SECURITY;

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
    -- Un error que ya no se reintenta no puede quedar como «en revisión» para siempre: el alumno no podría mandar otro.
    'estado', CASE WHEN r.estado = 'error' AND (r.reaperturas >= 3 OR COALESCE(r.error_detalle, '') ILIKE '%SalidaInvalida%') THEN 'rechazado'
                   WHEN r.estado IN ('procesando','a_revisar','aprobado','error') THEN 'enviado' ELSE r.estado END,
    'ejercicio_slug', r.ejercicio_slug,
    'ejercicio_nombre', r.ejercicio_nombre,
    'nota_alumno', r.nota_alumno,
    'enviado_en', r.enviado_en,
    'tiene_video', r.path IS NOT NULL AND r.video_borrado_en IS NULL,
    'rechazo_texto', CASE WHEN r.estado = 'rechazado' THEN r.rechazo_texto
                          WHEN r.estado = 'error' AND (r.reaperturas >= 3 OR COALESCE(r.error_detalle, '') ILIKE '%SalidaInvalida%') THEN 'No pudimos revisar este video. Mandame otro cuando puedas.' END,
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
  p_nota           TEXT
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
    INSERT INTO mypump_tecnica (cliente_id, ejercicio_slug, ejercicio_nombre, nota_alumno)
    VALUES (v_cliente_id, p_ejercicio_slug, p_ejercicio_nombre, NULLIF(btrim(p_nota), ''))
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
REVOKE ALL ON FUNCTION mypump_tecnica_get(TEXT), mypump_tecnica_nuevo(TEXT, TEXT, TEXT, TEXT), mypump_tecnica_cancelar(TEXT, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION mypump_tecnica_get(TEXT), mypump_tecnica_nuevo(TEXT, TEXT, TEXT, TEXT), mypump_tecnica_cancelar(TEXT, UUID) TO anon, authenticated, service_role;

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
  -- Una fila por alumno: dos errores del mismo alumno violarían el índice único y frenarían la vuelta del worker para todos.
  WITH elegidas AS (
    SELECT DISTINCT ON (cliente_id) id FROM mypump_tecnica
     WHERE estado = 'error' AND reaperturas < p_max AND actualizado_en < NOW() - make_interval(hours => p_horas) AND path IS NOT NULL AND video_borrado_en IS NULL
       AND COALESCE(error_detalle, '') NOT ILIKE '%SalidaInvalida%'      -- si el modelo no da una salida válida, reintentar solo gasta cuota
       AND NOT EXISTS (SELECT 1 FROM mypump_tecnica o WHERE o.cliente_id = mypump_tecnica.cliente_id AND o.estado IN ('borrador','enviado','procesando'))
     ORDER BY cliente_id, actualizado_en
  ), x AS (
    UPDATE mypump_tecnica SET estado = 'enviado', intentos = 0, reaperturas = reaperturas + 1, actualizado_en = NOW()
     WHERE id IN (SELECT id FROM elegidas)
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
  FROM (SELECT * FROM mypump_tecnica WHERE estado = 'a_revisar' OR (estado = 'aprobado' AND NOW() > publicar_hasta)
         ORDER BY escalar_a_mati DESC, publicar_desde LIMIT p_limite) t;
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

-- Hasta cuándo puede salir algo ya aprobado: las 20 de Argentina del día siguiente. Así el OK dado de noche, o una ventana que abre a las 19:50,
-- siempre tiene un tramo de día entero para salir.
CREATE OR REPLACE FUNCTION mypump_tecnica_cierre_plazo(p_desde TIMESTAMPTZ)
RETURNS TIMESTAMPTZ
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT (date_trunc('day', p_desde AT TIME ZONE 'America/Argentina/Buenos_Aires') + INTERVAL '1 day 20 hours') AT TIME ZONE 'America/Argentina/Buenos_Aires';
$$;

CREATE OR REPLACE FUNCTION mypump_tecnica_sha(p TEXT)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
SECURITY DEFINER
SET search_path = public
AS $$ SELECT encode(sha256(convert_to(p, 'UTF8')), 'hex'); $$;

REVOKE ALL ON FUNCTION mypump_tecnica_hora_de_publicar(), mypump_tecnica_palanca(), mypump_tecnica_cierre_plazo(TIMESTAMPTZ), mypump_tecnica_sha(TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION mypump_tecnica_hora_de_publicar(), mypump_tecnica_palanca(), mypump_tecnica_cierre_plazo(TIMESTAMPTZ), mypump_tecnica_sha(TEXT) TO service_role;

-- Emite el código que hace falta para aprobar: de un solo uso, atado a este envío y a este texto, 30 minutos. Devuelve el código UNA vez; acá queda solo el hash.
-- Emitir no cambia nada del envío y anula el código anterior que hubiera.
-- Quien tenga la service key puede emitir: lo que asegura es que no se apruebe de costado ni otro texto que el que Mati leyó. Para que un agente no pueda
-- completar solo el paso, el código se le manda a Mati por WhatsApp (`--codigo-por-whatsapp`) y lo tiene que dictar él.
CREATE OR REPLACE FUNCTION mypump_tecnica_emitir_codigo(p_id UUID, p_devolucion JSONB, p_por TEXT, p_minutos INTEGER DEFAULT 30)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_fila   mypump_tecnica%ROWTYPE;
  v_final  JSONB;
  v_crudo  TEXT;
  v_vence  TIMESTAMPTZ;
BEGIN
  IF length(btrim(COALESCE(p_por, ''))) = 0 OR char_length(p_por) > 120 THEN RAISE EXCEPTION 'falta quién aprueba' USING ERRCODE = '22023'; END IF;
  IF p_minutos NOT BETWEEN 1 AND 120 THEN RAISE EXCEPTION 'plazo del código inválido' USING ERRCODE = '22023'; END IF;
  SELECT * INTO v_fila FROM mypump_tecnica WHERE id = p_id FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', FALSE, 'error', 'no_encontrado'); END IF;
  IF NOT (v_fila.estado = 'a_revisar' OR (v_fila.estado = 'aprobado' AND NOW() > v_fila.publicar_hasta)) THEN RETURN jsonb_build_object('ok', FALSE, 'error', 'estado_invalido', 'estado', v_fila.estado); END IF;
  v_final := COALESCE(p_devolucion, v_fila.devolucion);
  IF v_final IS NULL OR NOT mypump_tecnica_devolucion_valida(v_final) THEN RETURN jsonb_build_object('ok', FALSE, 'error', 'devolucion_invalida'); END IF;
  UPDATE mypump_tecnica_aprobaciones SET anulado_en = NOW() WHERE envio_id = p_id AND usado_en IS NULL AND anulado_en IS NULL;
  v_crudo := upper(left(replace(gen_random_uuid()::TEXT, '-', ''), 8));
  v_vence := NOW() + make_interval(mins => p_minutos);
  INSERT INTO mypump_tecnica_aprobaciones (envio_id, codigo_hash, devolucion_hash, por, vence_en)
  VALUES (p_id, mypump_tecnica_sha(v_crudo), mypump_tecnica_sha(v_final::TEXT), btrim(p_por), v_vence);
  RETURN jsonb_build_object('ok', TRUE, 'codigo', left(v_crudo, 4) || '-' || right(v_crudo, 4), 'vence_en', v_vence);
END;
$$;

-- El OK de Mati. `p_devolucion` es la versión final, editada o no, y tiene que ser la misma por la que se emitió el código.
-- Antes de la ventana queda `aprobado` y sale sola cuando llega la hora. Con la ventana vencida no hace nada, salvo decisión explícita (`p_fuera_de_plazo`).
-- La firma cambió (antes `p_aprobado_por TEXT`): sin este DROP quedarían dos sobrecargas y PostgREST no sabría a cuál llamar.
DROP FUNCTION IF EXISTS mypump_tecnica_aprobar(UUID, JSONB, TEXT);
CREATE OR REPLACE FUNCTION mypump_tecnica_aprobar(p_id UUID, p_devolucion JSONB, p_codigo TEXT, p_fuera_de_plazo BOOLEAN DEFAULT FALSE)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_fila  mypump_tecnica%ROWTYPE;
  v_ok    mypump_tecnica_aprobaciones%ROWTYPE;
  v_final JSONB;
  v_ahora BOOLEAN;
BEGIN
  SELECT * INTO v_fila FROM mypump_tecnica WHERE id = p_id FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', FALSE, 'error', 'no_encontrado'); END IF;
  IF v_fila.estado = 'publicado' OR (v_fila.estado = 'aprobado' AND NOW() <= v_fila.publicar_hasta) THEN RETURN jsonb_build_object('ok', TRUE, 'ya', TRUE, 'estado', v_fila.estado); END IF;
  IF v_fila.estado NOT IN ('a_revisar','aprobado') THEN RETURN jsonb_build_object('ok', FALSE, 'error', 'estado_invalido'); END IF;
  IF NOW() > v_fila.publicar_hasta AND NOT COALESCE(p_fuera_de_plazo, FALSE) THEN RETURN jsonb_build_object('ok', FALSE, 'error', 'ventana_vencida', 'publicar_hasta', v_fila.publicar_hasta); END IF;
  v_final := COALESCE(p_devolucion, v_fila.devolucion);
  IF NOT mypump_tecnica_devolucion_valida(v_final) THEN RETURN jsonb_build_object('ok', FALSE, 'error', 'devolucion_invalida'); END IF;

  SELECT * INTO v_ok FROM mypump_tecnica_aprobaciones WHERE envio_id = p_id AND usado_en IS NULL AND anulado_en IS NULL ORDER BY emitido_en DESC LIMIT 1 FOR UPDATE;
  IF NOT FOUND OR NOW() > v_ok.vence_en THEN RETURN jsonb_build_object('ok', FALSE, 'error', 'codigo_invalido'); END IF;
  IF v_ok.codigo_hash IS DISTINCT FROM mypump_tecnica_sha(upper(regexp_replace(COALESCE(p_codigo, ''), '[^0-9A-Za-z]', '', 'g'))) THEN
    UPDATE mypump_tecnica_aprobaciones SET intentos_fallidos = intentos_fallidos + 1, anulado_en = CASE WHEN intentos_fallidos + 1 >= 5 THEN NOW() END WHERE id = v_ok.id;
    RETURN jsonb_build_object('ok', FALSE, 'error', 'codigo_invalido');
  END IF;
  IF v_ok.devolucion_hash IS DISTINCT FROM mypump_tecnica_sha(v_final::TEXT) THEN RETURN jsonb_build_object('ok', FALSE, 'error', 'codigo_de_otro_texto'); END IF;

  UPDATE mypump_tecnica_aprobaciones SET usado_en = NOW() WHERE id = v_ok.id;
  v_ahora := NOW() >= v_fila.publicar_desde AND mypump_tecnica_hora_de_publicar() AND mypump_tecnica_palanca();
  UPDATE mypump_tecnica SET devolucion = v_final, aprobado_por = v_ok.por, aprobado_en = NOW(), aprobacion_id = v_ok.id,
         publicar_hasta = GREATEST(publicar_hasta, mypump_tecnica_cierre_plazo(GREATEST(NOW(), publicar_desde))),
         estado = CASE WHEN v_ahora THEN 'publicado' ELSE 'aprobado' END,
         publicado_en = CASE WHEN v_ahora THEN NOW() END, actualizado_en = NOW()
   WHERE id = p_id RETURNING * INTO v_fila;
  RETURN jsonb_build_object('ok', TRUE, 'ya', FALSE, 'estado', v_fila.estado, 'publicar_desde', v_fila.publicar_desde, 'publicar_hasta', v_fila.publicar_hasta);
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

-- Lo aprobado que ya llegó a su hora y sigue dentro del plazo. Lo corre el worker. Lo vencido se queda: se avisa y lo decide Mati.
CREATE OR REPLACE FUNCTION mypump_tecnica_publicar_vencidas()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  n INTEGER;
BEGIN
  WITH x AS (UPDATE mypump_tecnica SET estado = 'publicado', publicado_en = NOW(), actualizado_en = NOW() WHERE estado = 'aprobado' AND aprobacion_id IS NOT NULL AND NOW() >= publicar_desde AND NOW() <= publicar_hasta AND mypump_tecnica_hora_de_publicar() AND mypump_tecnica_palanca() RETURNING 1)
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

-- Lo que merece un aviso a Mati. Solo ids y estado: nunca el alumno ni el texto.
CREATE OR REPLACE FUNCTION mypump_tecnica_para_avisar(p_limite INTEGER DEFAULT 50, p_max_reaperturas INTEGER DEFAULT 3)
RETURNS JSONB
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(jsonb_agg(jsonb_build_object('id', t.id, 'estado', t.estado, 'escalar', t.escalar_a_mati, 'publicar_hasta', t.publicar_hasta, 'reaperturas', t.reaperturas, 'vencida', t.vencida, 'error_definitivo', t.definitivo)), '[]'::JSONB)
  FROM (SELECT id, estado, escalar_a_mati, publicar_hasta, reaperturas,
               estado IN ('a_revisar','aprobado') AND NOW() > publicar_hasta AS vencida,
               estado = 'error' AND (reaperturas >= p_max_reaperturas OR path IS NULL OR video_borrado_en IS NOT NULL OR COALESCE(error_detalle, '') ILIKE '%SalidaInvalida%') AS definitivo
          FROM mypump_tecnica
         WHERE estado = 'a_revisar' OR (estado = 'aprobado' AND NOW() > publicar_hasta)
            OR (estado = 'error' AND (reaperturas >= p_max_reaperturas OR path IS NULL OR video_borrado_en IS NOT NULL OR COALESCE(error_detalle, '') ILIKE '%SalidaInvalida%'))
         ORDER BY actualizado_en DESC LIMIT p_limite) t;
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
  mypump_tecnica_a_revisar(INTEGER), mypump_tecnica_emitir_codigo(UUID, JSONB, TEXT, INTEGER), mypump_tecnica_aprobar(UUID, JSONB, TEXT, BOOLEAN), mypump_tecnica_descartar(UUID, TEXT, TEXT), mypump_tecnica_publicar_vencidas(), mypump_tecnica_para_avisar(INTEGER, INTEGER),
  mypump_tecnica_avisado(UUID), mypump_tecnica_para_limpiar(INTEGER, INTEGER), mypump_tecnica_limpieza_hecha(UUID)
FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION
  mypump_tecnica_puede(TEXT, UUID), mypump_tecnica_registrar(TEXT, UUID, TEXT, INTEGER, REAL), mypump_tecnica_borrar_video(TEXT, UUID),
  mypump_tecnica_tomar(), mypump_tecnica_devolver(UUID, BOOLEAN, TEXT), mypump_tecnica_liberar_colgadas(INTEGER, INTEGER), mypump_tecnica_reabrir_errores(INTEGER, INTEGER),
  mypump_tecnica_guardar(UUID, TEXT, JSONB, JSONB, BOOLEAN, TIMESTAMPTZ, TIMESTAMPTZ, TEXT, TEXT, TEXT),
  mypump_tecnica_a_revisar(INTEGER), mypump_tecnica_emitir_codigo(UUID, JSONB, TEXT, INTEGER), mypump_tecnica_aprobar(UUID, JSONB, TEXT, BOOLEAN), mypump_tecnica_descartar(UUID, TEXT, TEXT), mypump_tecnica_publicar_vencidas(), mypump_tecnica_para_avisar(INTEGER, INTEGER),
  mypump_tecnica_avisado(UUID), mypump_tecnica_para_limpiar(INTEGER, INTEGER), mypump_tecnica_limpieza_hecha(UUID)
TO service_role;

NOTIFY pgrst, 'reload schema';
COMMIT;
