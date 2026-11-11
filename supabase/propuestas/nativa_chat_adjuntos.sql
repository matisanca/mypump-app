-- nativa_chat_adjuntos.sql — PROPUESTA, SIN APLICAR (va en el OK único de Mati).
--
-- Fotos y audios en el chat con Mati (función 6 de PROPUESTAS_FUNCIONES, aprobada el 10/11). El alumno manda una foto
-- (cámara o galería, reducida en el teléfono y sin EXIF) o un audio de hasta 2 minutos. Se ven en su burbuja y el audio se
-- reproduce. Del lado de la Mini, `chat_adjuntos.py` transcribe el audio (Deepgram, como audio_dudas.py) y describe la
-- foto (Claude CLI del plan, con las caras tapadas). Ese texto es INTERNO: lo ve la sesión de Mensajes en
-- `app_chat.py`, nunca la app. La app no muestra ningún aviso de IA ni de transcripción.
--
-- Orden de despliegue: primero los endpoints de mini-vision (nativa_chat_adjuntos_minivision.mjs), después este SQL,
-- después el procesador de la Mini (RUNBOOK en nativa-evidencia/chat-adjuntos). Sale APAGADO.
-- Mientras esto no esté aplicado, `mypump_chat_adjuntos_estado` no existe (PGRST202) y la app no muestra nada nuevo.
--
-- Invariantes:
--   · El `cliente_id` sale siempre del token. Los archivos los registra mini-vision con la service key; no hay RPC anon que
--     escriba un path.
--   · `path` es relativo al bucket, nunca URL, y a la app no le llega nunca. La carpeta es un hash del cliente_id: ni el
--     nombre ni el id quedan en el bucket.
--   · `texto_interno`, `clase` y `proceso_detalle` no salen por ninguna RPC anon.
--   · Idempotente: el id del adjunto lo genera el teléfono. Un reintento de la cola devuelve el mismo mensaje.
--   · Las dos funciones del chat del alumno cambian de RETURNS TABLE (suman `adjunto`): DROP + CREATE con los mismos
--     argumentos, los permisos de nuevo y NOTIFY pgrst. Las apps viejas ignoran la columna nueva (decodifican a mano).
BEGIN;

-- ── Bucket privado ──
-- 6 MB: una foto reducida pesa 0,3-0,8 MB y un audio de 2 min a 64 kbps, ~1 MB. El tope fino lo pone mini-vision.
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('chat-adjuntos', 'chat-adjuntos', false, 6291456, ARRAY['image/jpeg', 'audio/mp4', 'audio/webm', 'audio/ogg'])
ON CONFLICT (id) DO NOTHING;

-- El Cerebro (Mati, con sesión) puede firmar y ver. Nadie más: anon no tiene política.
DROP POLICY IF EXISTS "coach lee chat-adjuntos" ON storage.objects;
CREATE POLICY "coach lee chat-adjuntos"
  ON storage.objects FOR SELECT
  USING (bucket_id = 'chat-adjuntos' AND auth.role() = 'authenticated');

-- ── Lo que ve el alumno: el adjunto del mensaje ──
-- {id, tipo: 'foto'|'audio', duracion_s?}. Sin path ni texto interno.
ALTER TABLE public.mypump_comentarios ADD COLUMN IF NOT EXISTS adjunto JSONB;
COMMENT ON COLUMN public.mypump_comentarios.adjunto IS
  'Foto o audio del mensaje: {id, tipo, duracion_s}. Lo que es interno (path, transcripción) está en mypump_chat_adjuntos (nativa_chat_adjuntos).';

-- ── Lo interno ──
CREATE TABLE IF NOT EXISTS mypump_chat_adjuntos (
  id                UUID        PRIMARY KEY,                                   -- lo genera el teléfono
  cliente_id        TEXT        NOT NULL,
  comentario_id     UUID        NOT NULL UNIQUE REFERENCES mypump_comentarios(id),
  tipo              TEXT        NOT NULL CHECK (tipo IN ('foto', 'audio')),
  path              TEXT        NOT NULL UNIQUE CHECK (path !~ '^/' AND path !~ '\.\.' AND path !~* '^https?:'),
  mime              TEXT        NOT NULL CHECK (mime IN ('image/jpeg', 'audio/mp4', 'audio/webm', 'audio/ogg')),
  bytes             INTEGER     NOT NULL CHECK (bytes > 0 AND bytes <= 6291456),
  duracion_s        REAL        CHECK (duracion_s IS NULL OR (duracion_s > 0 AND duracion_s <= 130)),
  creado_en         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  -- El proceso de la Mini: pendiente → procesando → listo | error. Un error queda a la vista de Mensajes para escucharlo
  -- o mirarlo a mano: un adjunto sin texto nunca saca el mensaje de la bandeja (el vigía avisa igual).
  proceso           TEXT        NOT NULL DEFAULT 'pendiente' CHECK (proceso IN ('pendiente', 'procesando', 'listo', 'error')),
  intentos          INTEGER     NOT NULL DEFAULT 0,
  reintentar_desde  TIMESTAMPTZ,
  tomado_en         TIMESTAMPTZ,
  texto_interno     TEXT        CHECK (texto_interno IS NULL OR length(texto_interno) <= 8000),
  clase             TEXT        CHECK (clase IS NULL OR clase IN ('estudio', 'dolor', 'maquina', 'tecnica', 'comida', 'fisico',
                                                                  'win', 'captura_app', 'otro')),
  proceso_detalle   JSONB,
  procesado_en      TIMESTAMPTZ,
  archivo_borrado_en TIMESTAMPTZ,
  CHECK ((tipo = 'audio') = (duracion_s IS NOT NULL)),
  CHECK ((tipo = 'foto') = (mime = 'image/jpeg'))
);
CREATE INDEX IF NOT EXISTS idx_mypump_chat_adjuntos_cliente ON mypump_chat_adjuntos (cliente_id, creado_en DESC);
CREATE INDEX IF NOT EXISTS idx_mypump_chat_adjuntos_proceso ON mypump_chat_adjuntos (creado_en) WHERE proceso IN ('pendiente', 'procesando');

CREATE TABLE IF NOT EXISTS mypump_chat_adjuntos_habilitados (
  cliente_id TEXT        PRIMARY KEY,
  motivo     TEXT,
  creado_en  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE mypump_chat_adjuntos ENABLE ROW LEVEL SECURITY;
ALTER TABLE mypump_chat_adjuntos_habilitados ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "coach lee mypump_chat_adjuntos" ON mypump_chat_adjuntos;
DROP POLICY IF EXISTS "coach lee mypump_chat_adjuntos_habilitados" ON mypump_chat_adjuntos_habilitados;
CREATE POLICY "coach lee mypump_chat_adjuntos" ON mypump_chat_adjuntos FOR SELECT USING (auth.role() = 'authenticated');
CREATE POLICY "coach lee mypump_chat_adjuntos_habilitados" ON mypump_chat_adjuntos_habilitados FOR SELECT USING (auth.role() = 'authenticated');
REVOKE ALL ON mypump_chat_adjuntos, mypump_chat_adjuntos_habilitados FROM anon;

-- ── Palanca: apagada ──
INSERT INTO mypump_app_config (clave, valor, nota) VALUES
  ('chat_adjuntos', 'false'::JSONB, 'Fotos y audios en el chat. true = abierto a mypump_chat_adjuntos_habilitados'),
  ('chat_adjuntos_para_todos', 'false'::JSONB, 'Fotos y audios en el chat. true = abierto a todos, sin mirar la lista')
ON CONFLICT (clave) DO NOTHING;

CREATE OR REPLACE FUNCTION mypump_chat_adjuntos_habilitado(p_cliente_id TEXT)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE((SELECT valor = 'true'::JSONB FROM mypump_app_config WHERE clave = 'chat_adjuntos'), FALSE)
     AND (COALESCE((SELECT valor = 'true'::JSONB FROM mypump_app_config WHERE clave = 'chat_adjuntos_para_todos'), FALSE)
          OR EXISTS (SELECT 1 FROM mypump_chat_adjuntos_habilitados WHERE cliente_id = p_cliente_id));
$$;

-- ── Para la app (anon, por token) ──
-- NULL = el token no vale. {habilitado:false} = no se muestra nada nuevo. Con la palanca abierta, los topes que respeta
-- la app (los mismos que controla mini-vision).
CREATE OR REPLACE FUNCTION mypump_chat_adjuntos_estado(p_token TEXT)
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
  IF NOT mypump_chat_adjuntos_habilitado(v_cliente_id) THEN RETURN jsonb_build_object('habilitado', FALSE); END IF;
  RETURN jsonb_build_object('habilitado', TRUE, 'audio_max_s', 120, 'foto_max_bytes', 3145728, 'audio_max_bytes', 3145728,
                            'por_dia', 30);
END;
$$;

-- Las mismas del chat del alumno (pg_get_functiondef del 10/11, iguales a nativa_005), con `adjunto` al final.
DROP FUNCTION IF EXISTS public.mypump_get_chat(text, timestamp with time zone, integer);
CREATE FUNCTION public.mypump_get_chat(p_token text, p_antes timestamp with time zone DEFAULT NULL::timestamp with time zone, p_limite integer DEFAULT 30)
 RETURNS TABLE(id uuid, autor text, contenido text, leido_por_cliente boolean, created_at timestamp with time zone, adjunto jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_cliente_id TEXT;
  v_limite     INTEGER;
BEGIN
  v_cliente_id := mypump_get_cliente_id_from_token(p_token);
  IF v_cliente_id IS NULL THEN RETURN; END IF;

  -- Tope defensivo: la función es anon y el límite viene del cliente.
  v_limite := LEAST(GREATEST(COALESCE(p_limite, 30), 1), 100);

  RETURN QUERY
  SELECT c.id, c.autor, c.contenido, c.leido_por_cliente, c.created_at, c.adjunto
  FROM mypump_comentarios c
  WHERE c.cliente_id = v_cliente_id
    AND c.ambito = 'general'
    AND NOT c.oculto   -- nativa_005: los recordatorios apilados no se muestran
    AND (p_antes IS NULL OR c.created_at < p_antes)
  ORDER BY c.created_at DESC
  LIMIT v_limite;
END;
$function$;

DROP FUNCTION IF EXISTS public.mypump_chat_nuevos(text, timestamp with time zone);
CREATE FUNCTION public.mypump_chat_nuevos(p_token text, p_desde timestamp with time zone)
 RETURNS TABLE(id uuid, autor text, contenido text, created_at timestamp with time zone, adjunto jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_cliente_id TEXT;
BEGIN
  v_cliente_id := mypump_get_cliente_id_from_token(p_token);
  IF v_cliente_id IS NULL THEN RETURN; END IF;

  RETURN QUERY
  SELECT c.id, c.autor, c.contenido, c.created_at, c.adjunto
  FROM mypump_comentarios c
  WHERE c.cliente_id = v_cliente_id
    AND c.ambito = 'general'
    AND NOT c.oculto   -- nativa_005
    AND c.created_at > COALESCE(p_desde, NOW() - INTERVAL '30 days')
  ORDER BY c.created_at ASC
  LIMIT 50;
END;
$function$;

REVOKE ALL ON FUNCTION public.mypump_get_chat(text, timestamp with time zone, integer), public.mypump_chat_nuevos(text, timestamp with time zone) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.mypump_get_chat(text, timestamp with time zone, integer) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.mypump_chat_nuevos(text, timestamp with time zone) TO anon, authenticated, service_role;
REVOKE ALL ON FUNCTION mypump_chat_adjuntos_estado(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION mypump_chat_adjuntos_estado(TEXT) TO anon, authenticated, service_role;

-- ── Para mini-vision (service_role) ──
-- Antes de leer el cuerpo: 'ok' | 'ya' (reintento de uno guardado) | 'ajena' (ese id es de otra cuenta) |
-- 'no_habilitado' | 'tope' (30 por día por cuenta, contando filas).
CREATE OR REPLACE FUNCTION mypump_chat_adjunto_puede(p_cliente_id TEXT, p_id UUID)
RETURNS TEXT
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_dueno TEXT;
BEGIN
  SELECT cliente_id INTO v_dueno FROM mypump_chat_adjuntos WHERE id = p_id;
  IF FOUND THEN RETURN CASE WHEN v_dueno = p_cliente_id THEN 'ya' ELSE 'ajena' END; END IF;
  IF NOT mypump_chat_adjuntos_habilitado(p_cliente_id) THEN RETURN 'no_habilitado'; END IF;
  IF (SELECT count(*) FROM mypump_chat_adjuntos WHERE cliente_id = p_cliente_id AND creado_en > NOW() - INTERVAL '24 hours') >= 30 THEN
    RETURN 'tope';
  END IF;
  RETURN 'ok';
END;
$$;

-- El archivo ya está en el bucket: crea el mensaje del alumno y la fila interna, en una sola transacción.
-- {resultado: 'ok'|'ya'|'ajena'|'no_habilitado'|'tope', comentario_id?, created_at?}
CREATE OR REPLACE FUNCTION mypump_chat_adjunto_registrar(
  p_cliente_id TEXT, p_id UUID, p_tipo TEXT, p_path TEXT, p_mime TEXT, p_bytes INTEGER, p_duracion_s REAL DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_fila    mypump_chat_adjuntos%ROWTYPE;
  v_com     UUID;
  v_creado  TIMESTAMPTZ;
  v_texto   TEXT;
  v_puede   TEXT;
BEGIN
  IF p_cliente_id IS NULL OR p_id IS NULL THEN RAISE EXCEPTION 'faltan datos' USING ERRCODE = '22023'; END IF;
  IF p_tipo IS NULL OR p_tipo NOT IN ('foto', 'audio') THEN RAISE EXCEPTION 'tipo inválido' USING ERRCODE = '22023'; END IF;
  -- Dos reintentos a la vez del mismo id: el segundo espera al primero y contesta 'ya'.
  PERFORM pg_advisory_xact_lock(hashtextextended('chat_adjunto:' || p_id::TEXT, 0));
  SELECT * INTO v_fila FROM mypump_chat_adjuntos WHERE id = p_id;
  IF FOUND THEN
    IF v_fila.cliente_id <> p_cliente_id THEN RETURN jsonb_build_object('resultado', 'ajena'); END IF;
    SELECT created_at INTO v_creado FROM mypump_comentarios WHERE id = v_fila.comentario_id;
    RETURN jsonb_build_object('resultado', 'ya', 'comentario_id', v_fila.comentario_id, 'created_at', v_creado);
  END IF;
  v_puede := mypump_chat_adjunto_puede(p_cliente_id, p_id);
  IF v_puede <> 'ok' THEN RETURN jsonb_build_object('resultado', v_puede); END IF;
  IF p_tipo = 'audio' AND (p_duracion_s IS NULL OR p_duracion_s <= 0) THEN
    RAISE EXCEPTION 'audio sin duración' USING ERRCODE = '22023';
  END IF;

  -- El texto es para lo que no conoce adjuntos: el Cerebro, la tarjeta de la semana y las apps viejas.
  v_texto := CASE WHEN p_tipo = 'foto' THEN 'Foto'
                  ELSE 'Audio de ' || (round(p_duracion_s)::INT / 60)::TEXT || ':' || lpad((round(p_duracion_s)::INT % 60)::TEXT, 2, '0') END;
  INSERT INTO mypump_comentarios (cliente_id, ambito, autor, contenido, leido_por_cliente, leido_por_coach, adjunto, meta)
  VALUES (p_cliente_id, 'general', 'cliente', v_texto, TRUE, FALSE,
          jsonb_strip_nulls(jsonb_build_object('id', p_id, 'tipo', p_tipo,
                                               'duracion_s', CASE WHEN p_tipo = 'audio' THEN round(p_duracion_s::NUMERIC, 1) END)),
          jsonb_build_object('adjunto', p_id))
  RETURNING id, created_at INTO v_com, v_creado;

  INSERT INTO mypump_chat_adjuntos (id, cliente_id, comentario_id, tipo, path, mime, bytes, duracion_s)
  VALUES (p_id, p_cliente_id, v_com, p_tipo, p_path, p_mime, p_bytes, CASE WHEN p_tipo = 'audio' THEN p_duracion_s END);

  RETURN jsonb_build_object('resultado', 'ok', 'comentario_id', v_com, 'created_at', v_creado);
END;
$$;

-- Los paths para firmar: solo de esa cuenta, solo los pedidos, sin los ya purgados.
CREATE OR REPLACE FUNCTION mypump_chat_adjuntos_paths(p_cliente_id TEXT, p_ids UUID[])
RETURNS TABLE(id UUID, tipo TEXT, path TEXT, mime TEXT)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT a.id, a.tipo, a.path, a.mime FROM mypump_chat_adjuntos a
  WHERE a.cliente_id = p_cliente_id AND a.id = ANY(p_ids[1:60]) AND a.archivo_borrado_en IS NULL;
$$;

-- ── Para el procesador de la Mini (service_role) ──
-- Toma uno: pendiente cuya espera venció, o procesando colgado hace más de 15 min. Nunca dos a la vez el mismo.
CREATE OR REPLACE FUNCTION mypump_chat_adjunto_tomar()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_fila mypump_chat_adjuntos%ROWTYPE;
BEGIN
  SELECT * INTO v_fila FROM mypump_chat_adjuntos
  WHERE archivo_borrado_en IS NULL
    AND ((proceso = 'pendiente' AND COALESCE(reintentar_desde, '-infinity') <= NOW())
      OR (proceso = 'procesando' AND tomado_en < NOW() - INTERVAL '15 minutes'))
  ORDER BY creado_en
  LIMIT 1
  FOR UPDATE SKIP LOCKED;
  IF NOT FOUND THEN RETURN NULL; END IF;
  UPDATE mypump_chat_adjuntos SET proceso = 'procesando', intentos = intentos + 1, tomado_en = NOW() WHERE id = v_fila.id;
  RETURN jsonb_build_object('id', v_fila.id, 'tipo', v_fila.tipo, 'path', v_fila.path, 'mime', v_fila.mime,
                            'duracion_s', v_fila.duracion_s, 'intentos', v_fila.intentos + 1);
END;
$$;

-- El resultado. p_estado 'listo' (con texto), 'error' (definitivo, con el motivo en el detalle) o 'reintentar' (vuelve a
-- pendiente y espera p_espera_min). Solo sobre una fila que está procesando.
CREATE OR REPLACE FUNCTION mypump_chat_adjunto_guardar(
  p_id UUID, p_estado TEXT, p_texto TEXT DEFAULT NULL, p_clase TEXT DEFAULT NULL, p_detalle JSONB DEFAULT NULL,
  p_espera_min INTEGER DEFAULT 2
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_estado = 'listo' AND (p_texto IS NULL OR btrim(p_texto) = '') THEN RAISE EXCEPTION 'listo sin texto' USING ERRCODE = '22023'; END IF;
  IF p_estado NOT IN ('listo', 'error', 'reintentar') THEN RAISE EXCEPTION 'estado inválido' USING ERRCODE = '22023'; END IF;
  UPDATE mypump_chat_adjuntos SET
    proceso = CASE WHEN p_estado = 'reintentar' THEN 'pendiente' ELSE p_estado END,
    texto_interno = CASE WHEN p_estado = 'listo' THEN left(btrim(p_texto), 8000) ELSE texto_interno END,
    clase = CASE WHEN p_estado = 'listo' THEN p_clase ELSE clase END,
    proceso_detalle = COALESCE(proceso_detalle, '{}'::JSONB) || COALESCE(p_detalle, '{}'::JSONB),
    procesado_en = CASE WHEN p_estado = 'reintentar' THEN procesado_en ELSE NOW() END,
    reintentar_desde = CASE WHEN p_estado = 'reintentar' THEN NOW() + make_interval(mins => GREATEST(1, LEAST(p_espera_min, 120))) END,
    tomado_en = NULL
  WHERE id = p_id AND proceso = 'procesando';
  RETURN FOUND;
END;
$$;

-- Retención (decisión de Mati, apagada mientras no la pida: hoy las fotos de progreso no se borran). Los archivos de más de
-- p_dias, ya procesados o con error. El mensaje y el texto interno quedan; la burbuja dice que ya no está disponible.
CREATE OR REPLACE FUNCTION mypump_chat_adjuntos_para_purgar(p_dias INTEGER, p_limite INTEGER DEFAULT 50)
RETURNS JSONB
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(jsonb_agg(jsonb_build_object('id', a.id, 'path', a.path)), '[]'::JSONB)
  FROM (SELECT id, path FROM mypump_chat_adjuntos
        WHERE archivo_borrado_en IS NULL AND proceso IN ('listo', 'error')
          AND creado_en < NOW() - make_interval(days => GREATEST(p_dias, 30))
        ORDER BY creado_en LIMIT LEAST(GREATEST(p_limite, 1), 200)) a;
$$;

CREATE OR REPLACE FUNCTION mypump_chat_adjunto_purgado(p_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  WITH a AS (UPDATE mypump_chat_adjuntos SET archivo_borrado_en = NOW() WHERE id = p_id AND archivo_borrado_en IS NULL
             RETURNING comentario_id)
  UPDATE mypump_comentarios c SET adjunto = c.adjunto || '{"borrado": true}'::JSONB FROM a WHERE c.id = a.comentario_id
  RETURNING TRUE;
$$;

REVOKE ALL ON FUNCTION
  mypump_chat_adjuntos_habilitado(TEXT), mypump_chat_adjunto_puede(TEXT, UUID),
  mypump_chat_adjunto_registrar(TEXT, UUID, TEXT, TEXT, TEXT, INTEGER, REAL), mypump_chat_adjuntos_paths(TEXT, UUID[]),
  mypump_chat_adjunto_tomar(), mypump_chat_adjunto_guardar(UUID, TEXT, TEXT, TEXT, JSONB, INTEGER),
  mypump_chat_adjuntos_para_purgar(INTEGER, INTEGER), mypump_chat_adjunto_purgado(UUID)
FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION
  mypump_chat_adjuntos_habilitado(TEXT), mypump_chat_adjunto_puede(TEXT, UUID),
  mypump_chat_adjunto_registrar(TEXT, UUID, TEXT, TEXT, TEXT, INTEGER, REAL), mypump_chat_adjuntos_paths(TEXT, UUID[]),
  mypump_chat_adjunto_tomar(), mypump_chat_adjunto_guardar(UUID, TEXT, TEXT, TEXT, JSONB, INTEGER),
  mypump_chat_adjuntos_para_purgar(INTEGER, INTEGER), mypump_chat_adjunto_purgado(UUID)
TO service_role;

-- El guardarraíl de la 063: sin firmas duplicadas (PGRST203).
DO $guard$
DECLARE v_dupes text;
BEGIN
  SELECT string_agg(proname || ' (' || n || ' firmas)', ', ') INTO v_dupes
  FROM (SELECT p.proname, count(*) AS n
        FROM pg_proc p JOIN pg_namespace ns ON ns.oid = p.pronamespace
        WHERE ns.nspname = 'public' AND p.proname LIKE 'mypump%'
        GROUP BY p.proname HAVING count(*) > 1) d;
  IF v_dupes IS NOT NULL THEN
    RAISE EXCEPTION 'Funciones mypump duplicadas, PostgREST va a tirar PGRST203: %', v_dupes;
  END IF;
END
$guard$;

NOTIFY pgrst, 'reload schema';
COMMIT;

-- Abrir el piloto, a mano y sin dejar ids en el repo:
--   INSERT INTO mypump_chat_adjuntos_habilitados (cliente_id, motivo) VALUES ('<cliente_id>', 'piloto') ON CONFLICT DO NOTHING;
--   UPDATE mypump_app_config SET valor = 'true', actualizado_en = NOW() WHERE clave = 'chat_adjuntos';
