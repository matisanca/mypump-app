-- nativa_wins_lista_previa.sql — PROPUESTA, SIN APLICAR.
--
-- Dos funciones de la 2.3.0, cada una detrás de su palanca (las dos salen APAGADAS):
--
-- 1) `wins_app` — Récords y logros que el alumno deja compartir con Mati.
--    La app festeja el récord en el teléfono. SOLO si el alumno dio su permiso (explícito, con la versión del texto que
--    aceptó, y revocable), deja el logro en `mypump_wins` con estado `pendiente`. De ahí no sale solo: la Mini lo lee,
--    arma el borrador para el grupo de logros del equipo y Mati lo aprueba por Mensajes. La app NUNCA publica.
--    Invariantes:
--      · Sin permiso vigente no se guarda nada (ni con la palanca prendida).
--      · Revocar siempre anda, también con la palanca apagada, y retira lo que todavía no salió (`pendiente`, `aprobado`).
--      · Un logro solo pasa a `enviado` desde `aprobado`: no hay camino de `pendiente` a `enviado`.
--      · Si el permiso se revocó, la Mini ya no lo ve en la cola y marcarlo lo deja `retirado`.
--      · Lo que guarda la app se arma campo por campo (nunca el JSON que mandó), con topes de tamaño y de cantidad.
--      · El `cliente_id` sale del token. Las tablas no las lee ni anon ni authenticated; las funciones de la Mini,
--        solo service_role.
--
-- 2) `lista_previa` — Lo que conviene tener listo antes de la videollamada de comienzo.
--    Solo lectura: `mypump_lista_previa` junta señales que ya existen (videos de la guía, dudas, formulario, fotos). No abre
--    ni cierra ninguna puerta: eso sigue siendo de `flujo.py` y de `entregas_app_agenda`. Un punto que no se sabe con
--    certeza no se manda (la app no lo muestra). Las claves `estudios` y `contrato` quedan reservadas: la app ya trae sus
--    textos, y se suman acá cuando existan sus tablas.
BEGIN;

INSERT INTO mypump_app_config (clave, valor, nota) VALUES
  ('wins_app', 'false'::JSONB, 'Récords y logros: festejo en la app y, con permiso del alumno, cola para Mati (mypump_wins)'),
  ('lista_previa', 'false'::JSONB, 'Lista de lo que conviene tener listo antes de la videollamada de comienzo')
ON CONFLICT (clave) DO NOTHING;

-- ───────────────────────────── 1) Wins ─────────────────────────────

-- Un permiso por otorgamiento. Vigente = `revocado_en IS NULL`; a lo sumo uno vigente por alumno. No se borra: queda la
-- historia de cuándo lo dio, con qué texto, y cuándo lo sacó.
CREATE TABLE IF NOT EXISTS mypump_wins_permisos (
  id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  cliente_id  TEXT        NOT NULL,
  version     INTEGER     NOT NULL CHECK (version BETWEEN 1 AND 999),
  plataforma  TEXT        CHECK (plataforma IN ('ios', 'android', 'web')),
  otorgado_en TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  revocado_en TIMESTAMPTZ,
  CONSTRAINT wins_permiso_revocado_despues CHECK (revocado_en IS NULL OR revocado_en >= otorgado_en)
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_mypump_wins_permiso_vigente ON mypump_wins_permisos (cliente_id) WHERE revocado_en IS NULL;
CREATE INDEX IF NOT EXISTS idx_mypump_wins_permisos_cliente ON mypump_wins_permisos (cliente_id, otorgado_en DESC);

-- La cola. El `id` lo genera la app (un reintento no duplica).
CREATE TABLE IF NOT EXISTS mypump_wins (
  id             UUID        PRIMARY KEY,
  cliente_id     TEXT        NOT NULL,
  permiso_id     UUID        NOT NULL REFERENCES mypump_wins_permisos (id),
  tipo           TEXT        NOT NULL CHECK (tipo IN ('record_kg', 'record_reps', 'racha_pasos')),
  -- Récord: la clave del ejercicio. Racha: 'pasos'.
  clave          TEXT        NOT NULL CHECK (char_length(clave) BETWEEN 1 AND 120),
  dia            DATE        NOT NULL,
  datos          JSONB       NOT NULL CHECK (jsonb_typeof(datos) = 'object'),
  estado         TEXT        NOT NULL DEFAULT 'pendiente' CHECK (estado IN ('pendiente', 'aprobado', 'enviado', 'descartado', 'retirado')),
  motivo         TEXT        CHECK (motivo IS NULL OR char_length(motivo) <= 300),
  creado_en      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  decidido_en    TIMESTAMPTZ,
  enviado_en     TIMESTAMPTZ,
  actualizado_en TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT wins_uno_por_dia UNIQUE (cliente_id, tipo, clave, dia),
  CONSTRAINT wins_enviado_con_fecha CHECK ((estado = 'enviado') = (enviado_en IS NOT NULL)),
  CONSTRAINT wins_enviado_decidido CHECK (estado NOT IN ('aprobado', 'enviado') OR decidido_en IS NOT NULL)
);
CREATE INDEX IF NOT EXISTS idx_mypump_wins_cola ON mypump_wins (creado_en) WHERE estado IN ('pendiente', 'aprobado');
CREATE INDEX IF NOT EXISTS idx_mypump_wins_cliente ON mypump_wins (cliente_id, creado_en DESC);

REVOKE ALL ON mypump_wins, mypump_wins_permisos FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON mypump_wins, mypump_wins_permisos TO service_role;
ALTER TABLE mypump_wins ENABLE ROW LEVEL SECURITY;
ALTER TABLE mypump_wins_permisos ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION mypump_wins_palanca()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$ SELECT COALESCE((SELECT valor = 'true'::JSONB FROM mypump_app_config WHERE clave = 'wins_app'), FALSE); $$;

-- Un texto que viene de la app (el nombre del ejercicio): una sola línea, sin caracteres de control, con tope. NULL si
-- queda vacío. Va a parar a un borrador que lee Mati: es dato, nunca una instrucción.
CREATE OR REPLACE FUNCTION mypump_wins_texto(p TEXT, p_max INTEGER)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
SET search_path = public, pg_temp
AS $$ SELECT NULLIF(left(btrim(regexp_replace(regexp_replace(COALESCE(p, ''), '[[:cntrl:]]+', ' ', 'g'), '\s+', ' ', 'g')), p_max), ''); $$;

-- Un número JSON dentro de un rango, o NULL (no levanta error con basura).
CREATE OR REPLACE FUNCTION mypump_wins_numero(p JSONB, p_min NUMERIC, p_max NUMERIC)
RETURNS NUMERIC
LANGUAGE sql
IMMUTABLE
SET search_path = public, pg_temp
AS $$
  SELECT CASE WHEN jsonb_typeof(p) = 'number' AND (p #>> '{}')::NUMERIC BETWEEN p_min AND p_max THEN (p #>> '{}')::NUMERIC END;
$$;

-- Lo que la app necesita saber al abrir: si la función está prendida y si este alumno tiene el permiso dado.
CREATE OR REPLACE FUNCTION mypump_wins_estado(p_token TEXT)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_cid TEXT := mypump_get_cliente_id_from_token(p_token);
  v_p   mypump_wins_permisos;
BEGIN
  IF v_cid IS NULL THEN RETURN jsonb_build_object('ok', FALSE, 'motivo', 'token'); END IF;
  SELECT * INTO v_p FROM mypump_wins_permisos WHERE cliente_id = v_cid AND revocado_en IS NULL;
  RETURN jsonb_build_object('ok', TRUE, 'activa', mypump_wins_palanca(), 'permiso', v_p.id IS NOT NULL)
         || jsonb_strip_nulls(jsonb_build_object('desde', v_p.otorgado_en, 'version', v_p.version));
END;
$$;

-- Dar o sacar el permiso. Dar exige la palanca prendida; sacar anda siempre. Sacarlo retira lo que no salió.
CREATE OR REPLACE FUNCTION mypump_wins_permiso(p_token TEXT, p_otorga BOOLEAN, p_version INTEGER DEFAULT 1, p_plataforma TEXT DEFAULT NULL)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_cid       TEXT := mypump_get_cliente_id_from_token(p_token);
  v_retirados INTEGER := 0;
BEGIN
  IF v_cid IS NULL THEN RETURN jsonb_build_object('ok', FALSE, 'motivo', 'token'); END IF;
  IF p_otorga IS NULL THEN RETURN jsonb_build_object('ok', FALSE, 'motivo', 'datos'); END IF;
  -- Dos toques a la vez del mismo alumno, de a uno.
  PERFORM pg_advisory_xact_lock(hashtextextended('mypump_wins:' || v_cid, 0));
  IF p_otorga THEN
    IF NOT mypump_wins_palanca() THEN RETURN jsonb_build_object('ok', FALSE, 'motivo', 'apagada'); END IF;
    IF p_version IS NULL OR p_version NOT BETWEEN 1 AND 999 THEN RETURN jsonb_build_object('ok', FALSE, 'motivo', 'datos'); END IF;
    INSERT INTO mypump_wins_permisos (cliente_id, version, plataforma)
    SELECT v_cid, p_version, CASE WHEN p_plataforma IN ('ios', 'android', 'web') THEN p_plataforma END
     WHERE NOT EXISTS (SELECT 1 FROM mypump_wins_permisos WHERE cliente_id = v_cid AND revocado_en IS NULL);
    RETURN jsonb_build_object('ok', TRUE, 'permiso', TRUE);
  END IF;
  UPDATE mypump_wins_permisos SET revocado_en = NOW() WHERE cliente_id = v_cid AND revocado_en IS NULL;
  UPDATE mypump_wins SET estado = 'retirado', motivo = 'el alumno sacó el permiso', actualizado_en = NOW()
   WHERE cliente_id = v_cid AND estado IN ('pendiente', 'aprobado');
  GET DIAGNOSTICS v_retirados = ROW_COUNT;
  RETURN jsonb_build_object('ok', TRUE, 'permiso', FALSE, 'retirados', v_retirados);
END;
$$;

-- Dejar un logro en la cola. `guardado: false` con su motivo no es un error: la app lo descarta sin reintentar.
--   record_kg / record_reps: datos = {ejercicio, kg, reps, antes_kg, antes_reps}
--   racha_pasos:             datos = {dias, meta}
CREATE OR REPLACE FUNCTION mypump_wins_registrar(p_token TEXT, p_id UUID, p_tipo TEXT, p_clave TEXT, p_dia DATE, p_datos JSONB)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_cid     TEXT := mypump_get_cliente_id_from_token(p_token);
  v_permiso UUID;
  v_hoy     DATE := (NOW() AT TIME ZONE 'America/Argentina/Buenos_Aires')::DATE;
  v_clave   TEXT := mypump_wins_texto(p_clave, 120);
  v_datos   JSONB;
  v_ej      TEXT;
  v_kg      NUMERIC; v_reps NUMERIC; v_akg NUMERIC; v_areps NUMERIC; v_dias NUMERIC; v_meta NUMERIC;
  v_dueno   TEXT;
BEGIN
  IF v_cid IS NULL THEN RETURN jsonb_build_object('ok', FALSE, 'motivo', 'token'); END IF;
  IF NOT mypump_wins_palanca() THEN RETURN jsonb_build_object('ok', TRUE, 'guardado', FALSE, 'motivo', 'apagada'); END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('mypump_wins:' || v_cid, 0));
  SELECT id INTO v_permiso FROM mypump_wins_permisos WHERE cliente_id = v_cid AND revocado_en IS NULL;
  IF v_permiso IS NULL THEN RETURN jsonb_build_object('ok', TRUE, 'guardado', FALSE, 'motivo', 'sin_permiso'); END IF;
  IF p_id IS NULL OR v_clave IS NULL OR p_dia IS NULL OR jsonb_typeof(p_datos) IS DISTINCT FROM 'object'
     OR p_tipo IS NULL OR p_tipo NOT IN ('record_kg', 'record_reps', 'racha_pasos') THEN
    RETURN jsonb_build_object('ok', FALSE, 'motivo', 'datos');
  END IF;
  -- El día es el del teléfono: una semana para atrás (la cola de la app sin señal) y un día de margen por el huso.
  IF p_dia < v_hoy - 7 OR p_dia > v_hoy + 1 THEN RETURN jsonb_build_object('ok', TRUE, 'guardado', FALSE, 'motivo', 'fecha'); END IF;

  IF p_tipo = 'racha_pasos' THEN
    v_dias := mypump_wins_numero(p_datos -> 'dias', 2, 400);
    v_meta := mypump_wins_numero(p_datos -> 'meta', 1000, 60000);
    IF v_dias IS NULL OR v_meta IS NULL OR v_dias <> trunc(v_dias) OR v_meta <> trunc(v_meta) OR v_clave <> 'pasos' THEN
      RETURN jsonb_build_object('ok', FALSE, 'motivo', 'datos');
    END IF;
    v_datos := jsonb_build_object('dias', v_dias::INTEGER, 'meta', v_meta::INTEGER);
  ELSE
    v_ej    := mypump_wins_texto(p_datos ->> 'ejercicio', 80);
    v_kg    := mypump_wins_numero(p_datos -> 'kg', 0.5, 1000);
    v_reps  := mypump_wins_numero(p_datos -> 'reps', 1, 200);
    v_akg   := mypump_wins_numero(p_datos -> 'antes_kg', 0.5, 1000);
    v_areps := mypump_wins_numero(p_datos -> 'antes_reps', 1, 200);
    IF v_ej IS NULL OR v_kg IS NULL OR v_reps IS NULL OR v_akg IS NULL OR v_areps IS NULL
       OR v_reps <> trunc(v_reps) OR v_areps <> trunc(v_areps) THEN
      RETURN jsonb_build_object('ok', FALSE, 'motivo', 'datos');
    END IF;
    -- Tiene que ser un récord de verdad: más kg, o el mismo kg con más reps.
    IF (p_tipo = 'record_kg' AND v_kg <= v_akg) OR (p_tipo = 'record_reps' AND (v_kg <> v_akg OR v_reps <= v_areps)) THEN
      RETURN jsonb_build_object('ok', FALSE, 'motivo', 'datos');
    END IF;
    v_datos := jsonb_build_object('ejercicio', v_ej, 'kg', v_kg, 'reps', v_reps::INTEGER, 'antes_kg', v_akg, 'antes_reps', v_areps::INTEGER);
  END IF;

  -- El mismo id otra vez (reintento): ya está. Un id ajeno no se pisa ni se confirma.
  SELECT cliente_id INTO v_dueno FROM mypump_wins WHERE id = p_id;
  IF FOUND THEN
    IF v_dueno = v_cid THEN RETURN jsonb_build_object('ok', TRUE, 'guardado', TRUE, 'ya', TRUE); END IF;
    RETURN jsonb_build_object('ok', FALSE, 'motivo', 'datos');
  END IF;
  -- Tope: 30 logros por alumno en 24 h (una sesión larga no pasa de 15 ejercicios).
  IF (SELECT count(*) FROM mypump_wins WHERE cliente_id = v_cid AND creado_en > NOW() - INTERVAL '24 hours') >= 30 THEN
    RETURN jsonb_build_object('ok', TRUE, 'guardado', FALSE, 'motivo', 'tope');
  END IF;
  -- Otro logro del mismo ejercicio y día: si todavía no lo miró nadie, queda la marca nueva; si no, se deja como está.
  INSERT INTO mypump_wins (id, cliente_id, permiso_id, tipo, clave, dia, datos)
  VALUES (p_id, v_cid, v_permiso, p_tipo, v_clave, p_dia, v_datos)
  ON CONFLICT ON CONSTRAINT wins_uno_por_dia DO UPDATE
     SET datos = EXCLUDED.datos, permiso_id = EXCLUDED.permiso_id, actualizado_en = clock_timestamp()
   WHERE mypump_wins.estado = 'pendiente';
  RETURN jsonb_build_object('ok', TRUE, 'guardado', TRUE, 'ya', FALSE);
END;
$$;

-- ── Para la Mini (solo service_role) ──
-- La cola: lo pendiente y lo aprobado que falta mandar, SOLO de quien sigue con el permiso dado. El nombre del alumno
-- no sale de acá: la Mini lo busca en su ficha por `cliente_id`.
CREATE OR REPLACE FUNCTION mypump_wins_cola(p_limite INTEGER DEFAULT 50)
RETURNS JSONB
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT COALESCE(jsonb_agg(to_jsonb(x) ORDER BY x.creado_en), '[]'::JSONB) FROM (
    SELECT w.id, w.cliente_id, w.tipo, w.clave, w.dia, w.datos, w.estado, w.creado_en, w.actualizado_en, p.otorgado_en AS permiso_desde
      FROM mypump_wins w
      JOIN mypump_wins_permisos p ON p.id = w.permiso_id AND p.revocado_en IS NULL
     WHERE w.estado IN ('pendiente', 'aprobado') AND mypump_wins_palanca()
     ORDER BY w.creado_en
     LIMIT LEAST(GREATEST(COALESCE(p_limite, 50), 1), 200)
  ) x;
$$;

-- Los pasos de la Mini: pendiente → aprobado (el OK de Mati) o descartado; aprobado → enviado o descartado.
-- `p_actualizado_en` es el que vino en la cola: si el alumno cambió la marca después, no se aprueba lo que Mati no vio.
-- (`actualizado_en` usa clock_timestamp(): dos cambios en la misma transacción también se distinguen.)
CREATE OR REPLACE FUNCTION mypump_wins_marcar(p_id UUID, p_estado TEXT, p_actualizado_en TIMESTAMPTZ, p_motivo TEXT DEFAULT NULL)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v mypump_wins;
BEGIN
  SELECT * INTO v FROM mypump_wins WHERE id = p_id FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', FALSE, 'motivo', 'no_existe'); END IF;
  IF p_estado IS NULL OR p_estado NOT IN ('aprobado', 'enviado', 'descartado') THEN RETURN jsonb_build_object('ok', FALSE, 'motivo', 'datos'); END IF;
  IF v.estado NOT IN ('pendiente', 'aprobado') THEN RETURN jsonb_build_object('ok', FALSE, 'motivo', 'cerrado', 'estado', v.estado); END IF;
  IF p_estado <> 'descartado' THEN
    IF NOT mypump_wins_palanca() THEN RETURN jsonb_build_object('ok', FALSE, 'motivo', 'apagada'); END IF;
    IF NOT EXISTS (SELECT 1 FROM mypump_wins_permisos WHERE id = v.permiso_id AND revocado_en IS NULL) THEN
      UPDATE mypump_wins SET estado = 'retirado', motivo = 'el alumno sacó el permiso', actualizado_en = NOW() WHERE id = p_id;
      RETURN jsonb_build_object('ok', FALSE, 'motivo', 'sin_permiso');
    END IF;
    IF p_actualizado_en IS NULL OR p_actualizado_en <> v.actualizado_en THEN RETURN jsonb_build_object('ok', FALSE, 'motivo', 'cambio'); END IF;
    IF (p_estado = 'aprobado' AND v.estado <> 'pendiente') OR (p_estado = 'enviado' AND v.estado <> 'aprobado') THEN
      RETURN jsonb_build_object('ok', FALSE, 'motivo', 'orden', 'estado', v.estado);
    END IF;
  END IF;
  UPDATE mypump_wins
     SET estado = p_estado, motivo = left(p_motivo, 300), actualizado_en = clock_timestamp(),
         decidido_en = CASE WHEN p_estado = 'enviado' THEN decidido_en ELSE NOW() END,
         enviado_en = CASE WHEN p_estado = 'enviado' THEN NOW() END
   WHERE id = p_id
  RETURNING * INTO v;
  RETURN jsonb_build_object('ok', TRUE, 'estado', v.estado, 'actualizado_en', v.actualizado_en);
END;
$$;

REVOKE ALL ON FUNCTION mypump_wins_palanca(), mypump_wins_texto(TEXT, INTEGER), mypump_wins_numero(JSONB, NUMERIC, NUMERIC),
  mypump_wins_estado(TEXT), mypump_wins_permiso(TEXT, BOOLEAN, INTEGER, TEXT), mypump_wins_registrar(TEXT, UUID, TEXT, TEXT, DATE, JSONB),
  mypump_wins_cola(INTEGER), mypump_wins_marcar(UUID, TEXT, TIMESTAMPTZ, TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION mypump_wins_estado(TEXT), mypump_wins_permiso(TEXT, BOOLEAN, INTEGER, TEXT),
  mypump_wins_registrar(TEXT, UUID, TEXT, TEXT, DATE, JSONB) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION mypump_wins_cola(INTEGER), mypump_wins_marcar(UUID, TEXT, TIMESTAMPTZ, TEXT) TO service_role;

-- ───────────────────────────── 2) Lista previa ─────────────────────────────

-- {ok, activa, items:[{clave, estado:'hecho'|'falta', opcional?, faltan?}]}
-- Activa = palanca prendida, guía publicada y la videollamada de comienzo todavía no pasó.
CREATE OR REPLACE FUNCTION mypump_lista_previa(p_token TEXT)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_cid    TEXT := mypump_get_cliente_id_from_token(p_token);
  v_fecha  TIMESTAMPTZ;
  v_items  JSONB := '[]'::JSONB;
  v_n      INTEGER;
  v_faltan INTEGER;
  v_form   RECORD;
BEGIN
  IF v_cid IS NULL THEN RETURN jsonb_build_object('ok', FALSE, 'motivo', 'token'); END IF;
  IF NOT COALESCE((SELECT valor = 'true'::JSONB FROM mypump_app_config WHERE clave = 'lista_previa'), FALSE) THEN
    RETURN jsonb_build_object('ok', TRUE, 'activa', FALSE, 'items', '[]'::JSONB);
  END IF;
  SELECT fecha_entrega INTO v_fecha FROM entregas_pack_link WHERE cliente_id = v_cid AND estado = 'aprobado';
  IF NOT FOUND
     -- La videollamada ya pasó: agendada por fuera de la app (la fecha de la guía) o desde la app (la reserva).
     OR (v_fecha IS NOT NULL AND NOW() > v_fecha + INTERVAL '1 hour')
     OR EXISTS (SELECT 1 FROM entregas_reservas WHERE cliente_id = v_cid AND estado = 'confirmada'
                   AND COALESCE(tipo, 'comienzo') = 'comienzo' AND fin < NOW()) THEN
    RETURN jsonb_build_object('ok', TRUE, 'activa', FALSE, 'items', '[]'::JSONB);
  END IF;

  -- Los videos de la guía: la misma cuenta que abre la agenda.
  SELECT count(*) INTO v_n FROM entregas_pack WHERE cliente_id = v_cid AND estado = 'aprobado';
  IF v_n > 0 THEN
    v_faltan := entregas_obligatorios_faltan(v_cid);
    v_items := v_items || jsonb_build_object('clave', 'guia', 'estado', CASE WHEN v_faltan = 0 THEN 'hecho' ELSE 'falta' END, 'faltan', v_faltan);
    -- Las dudas son opcionales: escritas en un video o en audio.
    v_items := v_items || jsonb_build_object('clave', 'dudas', 'opcional', TRUE, 'estado', CASE WHEN
         EXISTS (SELECT 1 FROM entregas_pack WHERE cliente_id = v_cid AND estado = 'aprobado' AND btrim(COALESCE(duda, '')) <> '')
      OR EXISTS (SELECT 1 FROM entregas_pack_audio WHERE cliente_id = v_cid AND subido_en IS NOT NULL)
      THEN 'hecho' ELSE 'falta' END);
  END IF;

  -- El formulario específico: solo si se sabe que le llegó (lo abrió o lo respondió). Sin fila no prueba nada.
  SELECT estado, abierto_en, respondido_en INTO v_form FROM entregas_formulario
   WHERE cliente_id = v_cid ORDER BY creado_en DESC NULLS LAST LIMIT 1;
  IF FOUND AND (v_form.estado = 'respondido' OR v_form.respondido_en IS NOT NULL) THEN
    v_items := v_items || jsonb_build_object('clave', 'formulario', 'estado', 'hecho');
  ELSIF FOUND AND v_form.abierto_en IS NOT NULL THEN
    v_items := v_items || jsonb_build_object('clave', 'formulario', 'estado', 'falta');
  END IF;

  -- Las fotos de inicio: las tres poses.
  SELECT count(DISTINCT pose) INTO v_n FROM mypump_fotos_progreso WHERE cliente_id = v_cid AND pose IN ('frente', 'perfil', 'espalda');
  v_items := v_items || jsonb_build_object('clave', 'fotos', 'estado', CASE WHEN v_n >= 3 THEN 'hecho' ELSE 'falta' END);

  RETURN jsonb_build_object('ok', TRUE, 'activa', TRUE, 'items', v_items);
END;
$$;

REVOKE ALL ON FUNCTION mypump_lista_previa(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION mypump_lista_previa(TEXT) TO anon, authenticated, service_role;

NOTIFY pgrst, 'reload schema';
COMMIT;
