-- nativa_devolucion_semanal.sql — PROPUESTA, SIN APLICAR.
--
-- «Devolución de Mati»: 3 a 5 líneas por semana que el alumno ve arriba de todo en Revisión, con historial debajo.
-- Las escribe el circuito de la Mini (~/pump-seguimiento: armar_tanda.py → aprobar_tanda.py → publicar_devoluciones.py),
-- Mati las aprueba en la tanda y recién ahí se publican. Le llega el aviso «Mati» de siempre.
--
-- Por qué una tabla nueva y no `agentes_devoluciones` (pump-agentes): aquella es de otro circuito (la Mesa, con coaches,
-- carriles y `mesa_decidir`), su guardia exige `agentes.decidiendo`, no guarda una aprobación atada al texto ni de un solo
-- uso, y su `texto_final` ya alimenta `mypump_get_analisis_cliente` del tablero. Mezclar los dos productores en la misma
-- fila (única por cliente y semana) haría que uno pise o bloquee al otro. Esta no la toca.
--
-- Invariantes:
--   · El alumno solo ve lo publicado, y solo lo suyo: el `cliente_id` sale del token.
--   · Nada se publica sin aprobación. La aprobación exige un código de un solo uso que se le manda a Mati por WhatsApp
--     (nunca se imprime), atado a la lista exacta de devoluciones y al hash de cada texto. Cambiar un texto anula el código
--     y devuelve la devolución a borrador. Quién y cuándo quedan en `mypump_devolucion_aprobaciones`.
--   · Una aprobación de más de 36 h no sale sola: hay que aprobar otra vez. Solo se publica de 9 a 21 de Argentina.
--   · Lo que escribe la Mini pasa por un token interno (solo su hash vive en la base) y además por los permisos: las
--     funciones de servicio no las puede ejecutar ni anon ni authenticated. service_role no escribe las tablas de costado.
--   · El filtro de texto prohibido corre también acá (copia del de devolucion_comun.py de la Mini, que es un superconjunto
--     del de Técnica): fármacos, análisis, RIR/reserva, IA, terceros («tu coach», «tu entrenador»), cambios de plan.
--   · Sale APAGADO: `devolucion_semanal` en false. Prendida, entra quien esté en `mypump_devolucion_habilitados`, salvo
--     `devolucion_para_todos` en true. Con la palanca apagada no se publica nada y la app no muestra nada.
--
-- Después de aplicar, UNA vez y desde la Mini (el token no pasa por ningún SQL ni log): ver RUNBOOK_DEVOLUCION.md,
-- paso «llave». Sin la llave cargada todas las funciones de la Mini contestan acceso denegado.
BEGIN;

INSERT INTO mypump_app_config (clave, valor, nota) VALUES
  ('devolucion_semanal', 'false'::JSONB, 'Devolución de Mati en Revisión. true = abierta a mypump_devolucion_habilitados'),
  ('devolucion_para_todos', 'false'::JSONB, 'Devolución de Mati. true = abierta a todos, sin mirar mypump_devolucion_habilitados')
ON CONFLICT (clave) DO NOTHING;

-- ── Ayudantes ──
CREATE OR REPLACE FUNCTION mypump_devolucion_sha(p TEXT)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
SET search_path = public, pg_temp
AS $$ SELECT encode(sha256(convert_to(COALESCE(p, ''), 'UTF8')), 'hex'); $$;

-- NULL si el texto pasa; si no, el primer motivo. Misma lista que revisar_texto() de la Mini (devolucion_comun.py, 10/11).
-- `\y` es el límite de palabra de Postgres (el `\b` de Python).
CREATE OR REPLACE FUNCTION mypump_devolucion_texto_motivo(p TEXT)
RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE
SET search_path = public, pg_temp
AS $$
DECLARE
  v_lineas TEXT[];
  v_n      INTEGER;
BEGIN
  IF p IS NULL OR btrim(p) = '' THEN RETURN 'texto vacío'; END IF;
  IF char_length(p) > 1500 THEN RETURN 'más de 1500 caracteres'; END IF;
  SELECT array_agg(l) INTO v_lineas FROM regexp_split_to_table(btrim(p), E'\n') l WHERE btrim(l) <> '';
  v_n := COALESCE(array_length(v_lineas, 1), 0);
  IF v_n NOT BETWEEN 3 AND 5 THEN RETURN v_n || ' líneas (van de 3 a 5)'; END IF;
  IF EXISTS (SELECT 1 FROM unnest(v_lineas) l WHERE char_length(l) > 300) THEN RETURN 'una línea de más de 300 caracteres'; END IF;
  IF position(':' IN p) > 0 THEN RETURN 'tiene «:»'; END IF;
  IF p ~ '(^|\s)[-–—](\s|$)' OR p ~ '(^|\n)\s*[-–—•*]' OR p ~ '[—–]' THEN RETURN 'tiene guiones o viñetas'; END IF;
  IF p ~ '[\U0001F000-\U0001FAFF☀-➿⬀-⯿️‍]' THEN RETURN 'tiene emojis'; END IF;
  IF p ~* '\yrir\y|reps? en reserva|repeticiones? en reserva|inteligencia artificial|\yia\y|mediapipe|\yopus\y|\yclaude\y|algoritmo' THEN
    RETURN 'RIR, reserva o IA'; END IF;
  IF p ~* 'cerca del fallo|lejos del fallo|antes del fallo|sin llegar al fallo|no llegu\w* al fallo|\y\w+ del fallo|en reserva|dej[aá]\w* \w+ reps?|guard[aá]\w* \w+ reps?' THEN
    -- «al fallo» sí: `\w+ del fallo` no lo toca.
    RETURN 'intensidad que no es al fallo'; END IF;
  IF p ~* ('\ytestost\w*|\ytesto\y|\ytrt\y|sustanon|nolvadex|clomid|proviron|\yhgh\y|\yglp\y|hormon\w*|pinch\w*|aromatasa|gonadotropina|enantato|cipionato|propionato|nandrolona|\ydeca\y|boldenona|trembolona|oxandrolona|anavar|'
           || 'winstrol|stanozolol|primobolan|masteron|dianabol|oximetolona|turinabol|\yhcg\y|gonadotrofina|clomifeno|'
           || 'tamoxifeno|anastrozol|letrozol|exemestano|cabergolina|semaglutid\w*|ozempic|tirzepatid\w*|mounjaro|retatrutid\w*|'
           || 'insulina|hormona de crecimiento|\ygh\y|p[eé]ptido\w*|\ybpc\y|tb.?500|\ysarms?\y|ostarine|cardarine|mk.?677|'
           || 'esteroide\w*|anab[oó]lic\w*|androg\w*|tu ciclo|el ciclo|post ?ciclo|\ypct\y|blast|cruise|f[aá]rmaco\w*|farmacol\w*|'
           || '\ydosis\y|\ymg\y|\ymcg\y|\yui\y|jeringa|inyec\w*|ampolla\w*|protocolo') THEN
    RETURN 'fármacos o dosis'; END IF;
  IF p ~* ('hematocrito|hemoglobina|colesterol|\yldl\y|\yhdl\y|triglic[eé]ridos|estradiol|prolactina|\ypsa\y|\ytgo\y|\ytgp\y|'
           || '\yshbg\y|\ylh\y|\yfsh\y|\ytsh\y|ferritina|glucosa|creatinina|glucemia|insulinemia|an[aá]lisis|laboratorio|'
           || '\ylos estudios\y|\ytus estudios\y|\yel estudio\y|presi[oó]n|\ysangre\y') THEN
    RETURN 'análisis o estudios'; END IF;
  IF p ~* 'tu coach|tu entrenador|el coach|el entrenador|\ymati\y|el equipo|los agentes?|\yficha\y|el sistema' THEN
    RETURN 'habla de un tercero'; END IF;
  IF p ~* '\y(acomodamos|sumamos|ajustamos|cambiamos|subimos|bajamos|armamos|revisamos|mandamos|pasamos|vemos|hablamos|seguimos|hacemos)\y|\yvamos a\y' THEN
    RETURN 'plural (siempre yo)'; END IF;
  IF p ~* 'ya lo cargu[eé]|lo cargu[eé]|lo sub[ií] al|lo pas[eé] al sistema' THEN RETURN 'suena a sistema'; END IF;
  IF p ~* 'te (cambio|armo|paso|mando) (la|una) (rutina|dieta)|nuevo bloque|bloque nuevo|rutina nueva|dieta nueva|te cambio (el|los) ejercicio|cambio de plan' THEN
    RETURN 'anuncia un cambio de plan'; END IF;
  RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION mypump_devolucion_hora_de_publicar()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SET search_path = public, pg_temp
AS $$ SELECT EXTRACT(HOUR FROM NOW() AT TIME ZONE 'America/Argentina/Buenos_Aires') BETWEEN 9 AND 20; $$;

-- ── Tablas ──
-- Solo el hash del token de la Mini. Una fila.
CREATE TABLE IF NOT EXISTS mypump_devolucion_llave (
  id         SMALLINT    PRIMARY KEY DEFAULT 1 CHECK (id = 1),
  hash       TEXT        NOT NULL CHECK (hash ~ '^[0-9a-f]{64}$'),
  creado_en  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Un código por pedido de aprobación: guarda el hash, nunca el código, y la lista exacta {id: hash del texto}.
CREATE TABLE IF NOT EXISTS mypump_devolucion_aprobaciones (
  id                UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  codigo_hash       TEXT        NOT NULL,
  items             JSONB       NOT NULL CHECK (jsonb_typeof(items) = 'object'),
  tanda             DATE,
  por               TEXT        NOT NULL CHECK (length(btrim(por)) > 0),
  emitido_en        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  vence_en          TIMESTAMPTZ NOT NULL,
  usado_en          TIMESTAMPTZ,
  anulado_en        TIMESTAMPTZ,
  intentos_fallidos INTEGER     NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS idx_mypump_devolucion_aprob_abiertas ON mypump_devolucion_aprobaciones (vence_en) WHERE usado_en IS NULL AND anulado_en IS NULL;

CREATE TABLE IF NOT EXISTS mypump_devoluciones (
  id             UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  cliente_id     TEXT        NOT NULL,
  semana_lunes   DATE        NOT NULL CHECK (EXTRACT(ISODOW FROM semana_lunes) = 1),
  texto          TEXT        NOT NULL,
  texto_hash     TEXT        NOT NULL,
  estado         TEXT        NOT NULL DEFAULT 'borrador' CHECK (estado IN ('borrador','aprobado','publicado','descartado','retirado')),
  tanda          DATE,
  aprobacion_id  UUID        REFERENCES mypump_devolucion_aprobaciones (id),
  aprobado_hash  TEXT,
  aprobado_por   TEXT,
  aprobado_en    TIMESTAMPTZ,
  publicado_en   TIMESTAMPTZ,
  push_id        BIGINT,
  motivo         TEXT,
  creado_en      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  actualizado_en TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT devolucion_una_por_semana UNIQUE (cliente_id, semana_lunes),
  CONSTRAINT devolucion_hash_del_texto CHECK (texto_hash = encode(sha256(convert_to(texto, 'UTF8')), 'hex')),
  -- Aprobada, publicada o retirada: con su aprobación y por ESTE texto.
  CONSTRAINT devolucion_aprobada_con_ok CHECK (estado NOT IN ('aprobado','publicado','retirado')
    OR (aprobacion_id IS NOT NULL AND aprobado_hash = texto_hash AND aprobado_en IS NOT NULL AND length(btrim(COALESCE(aprobado_por, ''))) > 0)),
  CONSTRAINT devolucion_publicada_con_fecha CHECK (estado NOT IN ('publicado','retirado') OR publicado_en IS NOT NULL)
);
CREATE INDEX IF NOT EXISTS idx_mypump_devoluciones_alumno ON mypump_devoluciones (cliente_id, semana_lunes DESC) WHERE estado = 'publicado';

CREATE TABLE IF NOT EXISTS mypump_devolucion_habilitados (
  cliente_id TEXT        PRIMARY KEY,
  motivo     TEXT,
  creado_en  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

REVOKE ALL ON mypump_devoluciones, mypump_devolucion_aprobaciones, mypump_devolucion_llave, mypump_devolucion_habilitados FROM PUBLIC, anon, authenticated;
-- service_role puede mirar las devoluciones y manejar a quién se le abre; escribir, solo por las funciones (con el token).
REVOKE ALL ON mypump_devoluciones, mypump_devolucion_aprobaciones, mypump_devolucion_llave FROM service_role;
GRANT SELECT ON mypump_devoluciones TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON mypump_devolucion_habilitados TO service_role;
ALTER TABLE mypump_devoluciones ENABLE ROW LEVEL SECURITY;
ALTER TABLE mypump_devolucion_aprobaciones ENABLE ROW LEVEL SECURITY;
ALTER TABLE mypump_devolucion_llave ENABLE ROW LEVEL SECURITY;
ALTER TABLE mypump_devolucion_habilitados ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION mypump_devolucion_habilitado(p_cliente_id TEXT)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT COALESCE((SELECT valor = 'true'::JSONB FROM mypump_app_config WHERE clave = 'devolucion_semanal'), FALSE)
     AND (COALESCE((SELECT valor = 'true'::JSONB FROM mypump_app_config WHERE clave = 'devolucion_para_todos'), FALSE)
          OR EXISTS (SELECT 1 FROM mypump_devolucion_habilitados WHERE cliente_id = p_cliente_id));
$$;

-- La guarda de todo lo que escribe la Mini: nunca desde la app (anon/authenticated) y siempre con el token interno.
CREATE OR REPLACE FUNCTION mypump_devolucion_guarda(p_token TEXT)
RETURNS VOID
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF COALESCE(auth.role(), '') IN ('anon', 'authenticated') THEN RAISE EXCEPTION 'acceso denegado' USING ERRCODE = '42501'; END IF;
  IF p_token IS NULL OR char_length(p_token) < 32
     OR NOT EXISTS (SELECT 1 FROM mypump_devolucion_llave WHERE id = 1 AND hash = mypump_devolucion_sha(p_token)) THEN
    RAISE EXCEPTION 'acceso denegado' USING ERRCODE = '42501';
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION mypump_devolucion_sha(TEXT), mypump_devolucion_texto_motivo(TEXT), mypump_devolucion_hora_de_publicar(),
  mypump_devolucion_habilitado(TEXT), mypump_devolucion_guarda(TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION mypump_devolucion_sha(TEXT), mypump_devolucion_texto_motivo(TEXT), mypump_devolucion_hora_de_publicar(),
  mypump_devolucion_habilitado(TEXT), mypump_devolucion_guarda(TEXT) TO service_role;

-- ── La app, por token. NULL = token caído. Solo lo publicado y solo lo suyo ──
CREATE OR REPLACE FUNCTION mypump_devolucion_get(p_token TEXT)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_cliente_id TEXT;
BEGIN
  v_cliente_id := mypump_get_cliente_id_from_token(p_token);
  IF v_cliente_id IS NULL THEN RETURN NULL; END IF;
  IF NOT mypump_devolucion_habilitado(v_cliente_id) THEN RETURN jsonb_build_object('habilitado', FALSE); END IF;
  RETURN jsonb_build_object(
    'habilitado', TRUE,
    'devoluciones', COALESCE((
      SELECT jsonb_agg(jsonb_build_object('id', d.id, 'semana_lunes', d.semana_lunes, 'texto', d.texto, 'publicado_en', d.publicado_en)
                       ORDER BY d.semana_lunes DESC)
        FROM (SELECT * FROM mypump_devoluciones WHERE cliente_id = v_cliente_id AND estado = 'publicado'
               ORDER BY semana_lunes DESC LIMIT 12) d), '[]'::JSONB));
END;
$$;

REVOKE ALL ON FUNCTION mypump_devolucion_get(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION mypump_devolucion_get(TEXT) TO anon, authenticated, service_role;

-- ── La Mini (token interno) ──
-- Carga o actualiza el borrador de la semana. Un texto distinto vuelve a borrador, borra la aprobación y anula los códigos
-- que lo incluían. Lo publicado no se cambia (se retira).
CREATE OR REPLACE FUNCTION mypump_devolucion_cargar(p_token TEXT, p_cliente_id TEXT, p_semana_lunes DATE, p_texto TEXT, p_tanda DATE DEFAULT NULL)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  -- Sin espacios ni saltos al principio y al final, con los mismos blancos Unicode que el strip() de Python de la Mini
  -- (NBSP incluido): la huella se calcula sobre eso y tiene que dar igual en los dos lados.
  v_texto  TEXT := regexp_replace(COALESCE(p_texto, ''), '^[\s\u001c-\u001f\u0085\u00a0\u1680\u2000-\u200a\u2028\u2029\u202f\u205f\u3000]+|[\s\u001c-\u001f\u0085\u00a0\u1680\u2000-\u200a\u2028\u2029\u202f\u205f\u3000]+$', '', 'g');
  v_hash   TEXT;
  v_motivo TEXT;
  v_fila   mypump_devoluciones%ROWTYPE;
BEGIN
  PERFORM mypump_devolucion_guarda(p_token);
  IF p_semana_lunes IS NULL OR EXTRACT(ISODOW FROM p_semana_lunes) <> 1 THEN RETURN jsonb_build_object('ok', FALSE, 'error', 'semana_invalida'); END IF;
  IF NOT EXISTS (SELECT 1 FROM mypump_clientes WHERE cliente_id = p_cliente_id) THEN RETURN jsonb_build_object('ok', FALSE, 'error', 'cliente_inexistente'); END IF;
  v_motivo := mypump_devolucion_texto_motivo(v_texto);
  IF v_motivo IS NOT NULL THEN RETURN jsonb_build_object('ok', FALSE, 'error', 'texto_prohibido', 'motivo', v_motivo); END IF;
  v_hash := mypump_devolucion_sha(v_texto);

  SELECT * INTO v_fila FROM mypump_devoluciones WHERE cliente_id = p_cliente_id AND semana_lunes = p_semana_lunes FOR UPDATE;
  IF NOT FOUND THEN
    INSERT INTO mypump_devoluciones (cliente_id, semana_lunes, texto, texto_hash, tanda)
    VALUES (p_cliente_id, p_semana_lunes, v_texto, v_hash, p_tanda)
    ON CONFLICT (cliente_id, semana_lunes) DO NOTHING
    RETURNING * INTO v_fila;
    IF NOT FOUND THEN RETURN jsonb_build_object('ok', FALSE, 'error', 'reintentar'); END IF;
    RETURN jsonb_build_object('ok', TRUE, 'ya', FALSE, 'id', v_fila.id, 'estado', v_fila.estado, 'texto_hash', v_hash);
  END IF;
  IF v_fila.estado IN ('publicado', 'retirado') THEN
    RETURN jsonb_build_object('ok', FALSE, 'error', 'ya_publicada', 'id', v_fila.id, 'estado', v_fila.estado);
  END IF;
  IF v_fila.texto_hash = v_hash AND v_fila.estado IN ('borrador', 'aprobado') THEN
    RETURN jsonb_build_object('ok', TRUE, 'ya', TRUE, 'id', v_fila.id, 'estado', v_fila.estado, 'texto_hash', v_hash);
  END IF;
  UPDATE mypump_devolucion_aprobaciones SET anulado_en = NOW()
   WHERE usado_en IS NULL AND anulado_en IS NULL AND items ? v_fila.id::TEXT;
  UPDATE mypump_devoluciones
     SET texto = v_texto, texto_hash = v_hash, estado = 'borrador', tanda = COALESCE(p_tanda, tanda),
         aprobacion_id = NULL, aprobado_hash = NULL, aprobado_por = NULL, aprobado_en = NULL, motivo = NULL, actualizado_en = NOW()
   WHERE id = v_fila.id RETURNING * INTO v_fila;
  RETURN jsonb_build_object('ok', TRUE, 'ya', FALSE, 'id', v_fila.id, 'estado', v_fila.estado, 'texto_hash', v_hash);
END;
$$;

-- Emite el código para aprobar una lista de borradores tal como están. Devuelve el código UNA vez (la Mini se lo manda a Mati
-- por WhatsApp y no lo imprime); acá queda solo el hash. Anula los códigos abiertos que compartan alguna devolución.
CREATE OR REPLACE FUNCTION mypump_devolucion_emitir_codigo(p_token TEXT, p_ids UUID[], p_por TEXT, p_tanda DATE DEFAULT NULL, p_horas INTEGER DEFAULT 12)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_items JSONB;
  v_malos JSONB;
  v_crudo TEXT;
  v_bytes BYTEA;
  v_i     INTEGER;
  v_vence TIMESTAMPTZ;
  v_n     INTEGER;
BEGIN
  PERFORM mypump_devolucion_guarda(p_token);
  IF length(btrim(COALESCE(p_por, ''))) = 0 OR char_length(p_por) > 120 THEN RAISE EXCEPTION 'falta quién aprueba' USING ERRCODE = '22023'; END IF;
  IF p_horas IS NULL OR p_horas NOT BETWEEN 1 AND 36 THEN RAISE EXCEPTION 'plazo del código inválido' USING ERRCODE = '22023'; END IF;
  v_n := COALESCE(cardinality(p_ids), 0);
  IF v_n = 0 OR v_n > 200 OR v_n <> (SELECT count(DISTINCT x) FROM unnest(p_ids) x WHERE x IS NOT NULL) THEN
    RAISE EXCEPTION 'lista de devoluciones inválida' USING ERRCODE = '22023';
  END IF;
  PERFORM 1 FROM mypump_devoluciones WHERE id = ANY (p_ids) ORDER BY id FOR UPDATE;
  SELECT jsonb_agg(jsonb_build_object('id', x, 'estado', d.estado)) INTO v_malos
    FROM unnest(p_ids) x LEFT JOIN mypump_devoluciones d ON d.id = x
   WHERE d.id IS NULL OR d.estado <> 'borrador';
  IF v_malos IS NOT NULL THEN RETURN jsonb_build_object('ok', FALSE, 'error', 'estado_invalido', 'detalle', v_malos); END IF;
  SELECT jsonb_object_agg(d.id::TEXT, d.texto_hash) INTO v_items FROM mypump_devoluciones d WHERE d.id = ANY (p_ids);
  UPDATE mypump_devolucion_aprobaciones SET anulado_en = NOW()
   WHERE usado_en IS NULL AND anulado_en IS NULL AND items ?| (SELECT array_agg(x::TEXT) FROM unnest(p_ids) x);
  -- 12 caracteres de un alfabeto de 32 sin los que se confunden (0/O, 1/I): 60 bits. Con 8 hex (32 bits) la huella guardada
  -- se revertía por fuerza bruta en segundos. Bytes al azar de un uuid v4, salteando los que llevan versión y variante.
  v_bytes := uuid_send(gen_random_uuid());
  v_crudo := '';
  FOREACH v_i IN ARRAY ARRAY[0,1,2,3,4,5,7,9,10,11,12,13] LOOP
    v_crudo := v_crudo || substr('23456789ABCDEFGHJKLMNPQRSTUVWXYZ', (get_byte(v_bytes, v_i) % 32) + 1, 1);
  END LOOP;
  v_vence := NOW() + make_interval(hours => p_horas);
  INSERT INTO mypump_devolucion_aprobaciones (codigo_hash, items, tanda, por, vence_en)
  VALUES (mypump_devolucion_sha(v_crudo), v_items, p_tanda, btrim(p_por), v_vence);
  RETURN jsonb_build_object('ok', TRUE, 'codigo', substr(v_crudo, 1, 4) || '-' || substr(v_crudo, 5, 4) || '-' || substr(v_crudo, 9, 4), 'vence_en', v_vence, 'n', v_n);
END;
$$;

-- El OK de Mati: el código que él dictó y la lista que aprueba (toda o una parte de la que se emitió). Todo o nada: si una
-- no está en el código o su texto cambió desde que se emitió, no se aprueba ninguna y el código sigue sin usar.
-- Un código errado suma un intento a todos los abiertos; al quinto se anulan.
CREATE OR REPLACE FUNCTION mypump_devolucion_aprobar(p_token TEXT, p_codigo TEXT, p_ids UUID[])
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_ok    mypump_devolucion_aprobaciones%ROWTYPE;
  v_malos JSONB;
  v_n     INTEGER;
BEGIN
  PERFORM mypump_devolucion_guarda(p_token);
  v_n := COALESCE(cardinality(p_ids), 0);
  IF v_n = 0 OR v_n > 200 OR v_n <> (SELECT count(DISTINCT x) FROM unnest(p_ids) x WHERE x IS NOT NULL) THEN
    RAISE EXCEPTION 'lista de devoluciones inválida' USING ERRCODE = '22023';
  END IF;
  SELECT * INTO v_ok FROM mypump_devolucion_aprobaciones
   WHERE codigo_hash = mypump_devolucion_sha(upper(regexp_replace(COALESCE(p_codigo, ''), '[^0-9A-Za-z]', '', 'g')))
     AND usado_en IS NULL AND anulado_en IS NULL AND vence_en > NOW()
   ORDER BY emitido_en DESC LIMIT 1 FOR UPDATE;
  IF NOT FOUND THEN
    UPDATE mypump_devolucion_aprobaciones
       SET intentos_fallidos = intentos_fallidos + 1, anulado_en = CASE WHEN intentos_fallidos + 1 >= 5 THEN NOW() END
     WHERE usado_en IS NULL AND anulado_en IS NULL AND vence_en > NOW();
    RETURN jsonb_build_object('ok', FALSE, 'error', 'codigo_invalido');
  END IF;
  PERFORM 1 FROM mypump_devoluciones WHERE id = ANY (p_ids) ORDER BY id FOR UPDATE;
  SELECT jsonb_agg(x) INTO v_malos
    FROM unnest(p_ids) x LEFT JOIN mypump_devoluciones d ON d.id = x
   WHERE d.id IS NULL OR d.estado <> 'borrador' OR (v_ok.items ->> x::TEXT) IS DISTINCT FROM d.texto_hash;
  IF v_malos IS NOT NULL THEN RETURN jsonb_build_object('ok', FALSE, 'error', 'codigo_de_otro_texto', 'ids', v_malos); END IF;

  UPDATE mypump_devolucion_aprobaciones SET usado_en = NOW() WHERE id = v_ok.id;
  UPDATE mypump_devoluciones
     SET estado = 'aprobado', aprobacion_id = v_ok.id, aprobado_hash = texto_hash, aprobado_por = v_ok.por, aprobado_en = NOW(), actualizado_en = NOW()
   WHERE id = ANY (p_ids);
  RETURN jsonb_build_object('ok', TRUE, 'aprobadas', v_n);
END;
$$;

-- Publica una aprobada. `p_texto_hash` es el del texto que la Mini cree que sale: tiene que ser el aprobado.
-- Encola el aviso «Mati» (uno solo por devolución: dedupe `dev-<id>`). Repetir con una ya publicada no hace nada.
CREATE OR REPLACE FUNCTION mypump_devolucion_publicar(p_token TEXT, p_id UUID, p_texto_hash TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_fila mypump_devoluciones%ROWTYPE;
  v_push BIGINT;
BEGIN
  PERFORM mypump_devolucion_guarda(p_token);
  SELECT * INTO v_fila FROM mypump_devoluciones WHERE id = p_id FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', FALSE, 'error', 'no_encontrado'); END IF;
  IF v_fila.estado = 'publicado' THEN RETURN jsonb_build_object('ok', TRUE, 'ya', TRUE, 'publicado_en', v_fila.publicado_en); END IF;
  IF v_fila.estado <> 'aprobado' THEN RETURN jsonb_build_object('ok', FALSE, 'error', 'estado_invalido', 'estado', v_fila.estado); END IF;
  IF p_texto_hash IS DISTINCT FROM v_fila.texto_hash OR v_fila.aprobado_hash IS DISTINCT FROM v_fila.texto_hash THEN
    RETURN jsonb_build_object('ok', FALSE, 'error', 'texto_distinto');
  END IF;
  -- Las 36 horas corren desde que se emitió el código, no desde que se usó: el plazo total no se suma.
  IF NOW() - COALESCE((SELECT emitido_en FROM mypump_devolucion_aprobaciones WHERE id = v_fila.aprobacion_id), v_fila.aprobado_en) > INTERVAL '36 hours' THEN RETURN jsonb_build_object('ok', FALSE, 'error', 'aprobacion_vencida'); END IF;
  IF mypump_devolucion_texto_motivo(v_fila.texto) IS NOT NULL THEN RETURN jsonb_build_object('ok', FALSE, 'error', 'texto_prohibido'); END IF;
  IF NOT mypump_devolucion_hora_de_publicar() THEN RETURN jsonb_build_object('ok', FALSE, 'error', 'fuera_de_horario'); END IF;
  IF NOT mypump_devolucion_habilitado(v_fila.cliente_id) THEN RETURN jsonb_build_object('ok', FALSE, 'error', 'no_habilitado'); END IF;

  UPDATE mypump_devoluciones SET estado = 'publicado', publicado_en = NOW(), actualizado_en = NOW() WHERE id = p_id RETURNING * INTO v_fila;
  BEGIN
    v_push := mypump_encolar_push(v_fila.cliente_id, 'Mati', 'Te dejé la devolución de tu semana', 'revision', 'dev-' || v_fila.id::TEXT);
    UPDATE mypump_devoluciones SET push_id = v_push WHERE id = p_id;
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'push de la devolución % falló: %', p_id, SQLERRM;
  END;
  RETURN jsonb_build_object('ok', TRUE, 'ya', FALSE, 'publicado_en', v_fila.publicado_en, 'push', v_push IS NOT NULL);
END;
$$;

-- «Esta semana no» (o un error antes de publicar). Anula los códigos que la incluían.
CREATE OR REPLACE FUNCTION mypump_devolucion_descartar(p_token TEXT, p_id UUID, p_motivo TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_estado TEXT;
BEGIN
  PERFORM mypump_devolucion_guarda(p_token);
  SELECT estado INTO v_estado FROM mypump_devoluciones WHERE id = p_id FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', FALSE, 'error', 'no_encontrado'); END IF;
  IF v_estado = 'descartado' THEN RETURN jsonb_build_object('ok', TRUE, 'ya', TRUE); END IF;
  IF v_estado NOT IN ('borrador', 'aprobado') THEN RETURN jsonb_build_object('ok', FALSE, 'error', 'estado_invalido', 'estado', v_estado); END IF;
  UPDATE mypump_devolucion_aprobaciones SET anulado_en = NOW() WHERE usado_en IS NULL AND anulado_en IS NULL AND items ? p_id::TEXT;
  UPDATE mypump_devoluciones
     SET estado = 'descartado', aprobacion_id = NULL, aprobado_hash = NULL, aprobado_por = NULL, aprobado_en = NULL,
         motivo = left(p_motivo, 300), actualizado_en = NOW()
   WHERE id = p_id;
  RETURN jsonb_build_object('ok', TRUE, 'ya', FALSE);
END;
$$;

-- Saca de la app una ya publicada (un error). Queda en la tabla como retirada; el alumno deja de verla.
CREATE OR REPLACE FUNCTION mypump_devolucion_retirar(p_token TEXT, p_id UUID, p_motivo TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_estado TEXT;
BEGIN
  PERFORM mypump_devolucion_guarda(p_token);
  IF length(btrim(COALESCE(p_motivo, ''))) = 0 THEN RAISE EXCEPTION 'falta el motivo' USING ERRCODE = '22023'; END IF;
  SELECT estado INTO v_estado FROM mypump_devoluciones WHERE id = p_id FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', FALSE, 'error', 'no_encontrado'); END IF;
  IF v_estado = 'retirado' THEN RETURN jsonb_build_object('ok', TRUE, 'ya', TRUE); END IF;
  IF v_estado <> 'publicado' THEN RETURN jsonb_build_object('ok', FALSE, 'error', 'estado_invalido', 'estado', v_estado); END IF;
  UPDATE mypump_devoluciones SET estado = 'retirado', motivo = left(p_motivo, 300), actualizado_en = NOW() WHERE id = p_id;
  -- Si el aviso todavía no salió, no sale.
  UPDATE mypump_push_cola SET estado = 'descartado' WHERE dedupe_key = 'dev-' || p_id::TEXT AND estado IN ('pendiente', 'sin_device');
  RETURN jsonb_build_object('ok', TRUE, 'ya', FALSE);
END;
$$;

-- Lo que la Mini necesita para decidir: estado de las suyas, sin texto.
CREATE OR REPLACE FUNCTION mypump_devolucion_ver(p_token TEXT, p_ids UUID[])
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  PERFORM mypump_devolucion_guarda(p_token);
  IF COALESCE(cardinality(p_ids), 0) > 500 THEN RAISE EXCEPTION 'demasiadas' USING ERRCODE = '22023'; END IF;
  RETURN COALESCE((SELECT jsonb_agg(jsonb_build_object('id', id, 'cliente_id', cliente_id, 'semana_lunes', semana_lunes, 'estado', estado,
                                                      'texto_hash', texto_hash, 'aprobado_en', aprobado_en, 'publicado_en', publicado_en,
                                                      'habilitado', mypump_devolucion_habilitado(cliente_id)))
                     FROM mypump_devoluciones WHERE id = ANY (p_ids)), '[]'::JSONB);
END;
$$;

REVOKE ALL ON FUNCTION
  mypump_devolucion_cargar(TEXT, TEXT, DATE, TEXT, DATE), mypump_devolucion_emitir_codigo(TEXT, UUID[], TEXT, DATE, INTEGER),
  mypump_devolucion_aprobar(TEXT, TEXT, UUID[]), mypump_devolucion_publicar(TEXT, UUID, TEXT), mypump_devolucion_descartar(TEXT, UUID, TEXT),
  mypump_devolucion_retirar(TEXT, UUID, TEXT), mypump_devolucion_ver(TEXT, UUID[])
FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION
  mypump_devolucion_cargar(TEXT, TEXT, DATE, TEXT, DATE), mypump_devolucion_emitir_codigo(TEXT, UUID[], TEXT, DATE, INTEGER),
  mypump_devolucion_aprobar(TEXT, TEXT, UUID[]), mypump_devolucion_publicar(TEXT, UUID, TEXT), mypump_devolucion_descartar(TEXT, UUID, TEXT),
  mypump_devolucion_retirar(TEXT, UUID, TEXT), mypump_devolucion_ver(TEXT, UUID[])
TO service_role;

NOTIFY pgrst, 'reload schema';
COMMIT;
