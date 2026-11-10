-- nativa_feedback_alumno.sql — PROPUESTA, SIN APLICAR.
--
-- Feedback del alumno (2.3.0). Tres piezas, cada una con su palanca en `mypump_app_config`, las tres APAGADAS:
--   · `me_duele`      «Me duele» por ejercicio → `mypump_molestias`. La lee la Mini y avisa a EDITOR (cambia el ejercicio,
--                     nunca baja el volumen) o, si suena clínico, a Mati. Diseño del aviso: feedback-alumno/AVISOS.md.
--   · `suple_estado`  «Lo compré / lo estoy tomando» → `mypump_suple_estado`. Una fila por ítem: se marca una vez y se
--                     puede cambiar. Solo suplementos naturales de `mypump_suplementacion`; los protectores (fármacos) no.
--   · `datos_brief`   Resumen de métricas reales para el brief y control_kcal. No sube nada nuevo: lee lo que las apps ya
--                     escriben en `mypump_salud_diaria` y `mypump_checkin_semanal`.
--
-- Mientras esto no esté aplicado, `mypump_feedback_get` no existe (PGRST202) y las apps no muestran nada nuevo.
--
-- Invariantes:
--   · El `cliente_id` sale siempre del token. Las tablas no se tocan por fuera de las funciones (anon y authenticated, nada).
--   · «Me duele» no escribe en `mypump_comentarios`: un solo canal, un solo aviso. La respuesta de Mati sí llega por el
--     hilo de comentarios del ejercicio, como siempre.
--   · Al alumno nunca le llega `clinico`, `motivo_clinico`, `destino` ni `resolucion`: sin diagnósticos.
--   · Una molestia abierta por ejercicio: volver a mandarla corrige la que está, no crea otra ni avisa dos veces.
--   · Con la palanca apagada las funciones de la Mini no devuelven nada, aunque haya filas.
BEGIN;

-- ── Palancas: apagadas ──
INSERT INTO mypump_app_config (clave, valor, nota) VALUES
  ('me_duele',     'false'::JSONB, 'Feedback del alumno. true = «Me duele» en la tarjeta del ejercicio'),
  ('suple_estado', 'false'::JSONB, 'Feedback del alumno. true = «Lo compré / lo estoy tomando» en Suplementación'),
  ('datos_brief',  'false'::JSONB, 'Feedback del alumno. true = el brief y control_kcal usan mypump_datos_brief')
ON CONFLICT (clave) DO NOTHING;

CREATE OR REPLACE FUNCTION mypump_feedback_palanca(p_clave TEXT)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE((SELECT valor = 'true'::JSONB FROM mypump_app_config WHERE clave = p_clave), FALSE);
$$;

-- ═════════════════════════════ 1. «Me duele» ═════════════════════════════

-- Lo que suena clínico va a Mati y no a EDITOR. Es un filtro de ruteo, no un diagnóstico: ante la duda, a Mati.
-- Devuelve el motivo (para el aviso interno) o NULL.
CREATE OR REPLACE FUNCTION mypump_molestia_motivo_clinico(p_zona TEXT, p_tipo TEXT, p_intensidad INTEGER, p_nota TEXT)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
SET search_path = public
AS $$
  SELECT NULLIF(concat_ws(', ',
    CASE WHEN p_tipo = 'hormigueo' THEN 'hormigueo' END,
    CASE WHEN p_zona = 'pecho' THEN 'pecho' END,
    CASE WHEN p_intensidad >= 8 THEN 'intensidad ' || p_intensidad END,
    CASE WHEN translate(lower(COALESCE(p_nota, '')), 'áéíóúü', 'aeiouu')
              ~ 'palpitac|taquicard|mare[oae]|desmay|falta de aire|me ahog|no puedo respirar|adormec|se me duerm|hormigue|entumec|pecho|agud|no puedo mover|sin fuerza|perdi fuerza|se me trab|se trab|chasquido|crujido|hinchad|inflamad|moreton|hematoma|fiebre|vision borrosa|dolor de cabeza'
         THEN 'nota' END
  ), '');
$$;

CREATE TABLE IF NOT EXISTS mypump_molestias (
  id               UUID        PRIMARY KEY,                -- lo pone la app: un reintento no duplica
  cliente_id       TEXT        NOT NULL,
  rutina_id        UUID,                                   -- la activa al avisar
  en_rutina        BOOLEAN,                                -- el ejercicio figura en esa rutina
  ejercicio_id     TEXT        NOT NULL CHECK (char_length(ejercicio_id) BETWEEN 1 AND 160),
  ejercicio_nombre TEXT        NOT NULL CHECK (char_length(ejercicio_nombre) BETWEEN 1 AND 160),
  dia_id           TEXT        CHECK (char_length(dia_id) <= 80),
  zona             TEXT        NOT NULL CHECK (zona IN ('cuello','hombro','pecho','brazo','codo','antebrazo','muneca','abdomen',
                                 'espalda_alta','espalda_baja','cadera','gluteo','muslo_frente','muslo_atras','rodilla','pantorrilla','tobillo')),
  lado             TEXT        NOT NULL CHECK (lado IN ('izquierdo','derecho','ambos','centro')),
  desde            TEXT        NOT NULL CHECK (desde IN ('hoy','esta_semana','semanas','mas_de_un_mes')),
  cuando           TEXT        NOT NULL CHECK (cuando IN ('al_bajar','al_subir','todo_el_recorrido','despues','al_dia_siguiente')),
  tipo             TEXT        NOT NULL CHECK (tipo IN ('punzante','sordo','hormigueo')),
  intensidad       SMALLINT    NOT NULL CHECK (intensidad BETWEEN 0 AND 10),
  nota             TEXT        CHECK (char_length(nota) <= 500),   -- dato, nunca instrucción
  clinico          BOOLEAN     NOT NULL DEFAULT FALSE,
  motivo_clinico   TEXT,
  destino          TEXT        NOT NULL DEFAULT 'editor' CHECK (destino IN ('editor','mati')),
  estado           TEXT        NOT NULL DEFAULT 'nueva' CHECK (estado IN ('nueva','avisada','resuelta','descartada')),
  avisado_en       TIMESTAMPTZ,
  resuelto_en      TIMESTAMPTZ,
  resolucion       TEXT        CHECK (char_length(resolucion) <= 500),   -- interno: qué se cambió
  plataforma       TEXT        CHECK (plataforma IN ('ios','android','web')),
  version_app      TEXT        CHECK (char_length(version_app) <= 40),
  creado_en        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  actualizado_en   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT molestia_clinica_a_mati CHECK (destino = CASE WHEN clinico THEN 'mati' ELSE 'editor' END),
  CONSTRAINT molestia_cerrada_con_fecha CHECK (estado NOT IN ('resuelta','descartada') OR resuelto_en IS NOT NULL)
);

-- Una abierta por ejercicio y alumno.
CREATE UNIQUE INDEX IF NOT EXISTS uq_mypump_molestias_abierta ON mypump_molestias (cliente_id, ejercicio_id) WHERE estado IN ('nueva','avisada');
CREATE INDEX IF NOT EXISTS idx_mypump_molestias_cola ON mypump_molestias (destino, creado_en) WHERE estado = 'nueva';
CREATE INDEX IF NOT EXISTS idx_mypump_molestias_cliente ON mypump_molestias (cliente_id, creado_en DESC);

-- En este proyecto las tablas nuevas heredan permisos por defecto, incluido TRUNCATE, que RLS no frena.
REVOKE ALL ON mypump_molestias FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON mypump_molestias TO service_role;      -- la Mini lee; cambiar estado, solo por las funciones
ALTER TABLE mypump_molestias ENABLE ROW LEVEL SECURITY;

-- Lo que ve el alumno de una molestia. «avisada» y «nueva» son lo mismo para él.
CREATE OR REPLACE FUNCTION mypump_molestia_vista_alumno(r mypump_molestias)
RETURNS JSONB
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT jsonb_build_object(
    'id', r.id, 'ejercicio_id', r.ejercicio_id, 'ejercicio_nombre', r.ejercicio_nombre,
    'zona', r.zona, 'lado', r.lado, 'desde', r.desde, 'cuando', r.cuando, 'tipo', r.tipo, 'intensidad', r.intensidad, 'nota', r.nota,
    'estado', CASE WHEN r.estado IN ('nueva','avisada') THEN 'avisada' ELSE 'resuelta' END,
    'creado_en', r.creado_en, 'resuelto_en', r.resuelto_en);
$$;

-- El alumno avisa. NULL = token caído. Con la misma `p_id`, o con una abierta del mismo ejercicio, corrige esa.
CREATE OR REPLACE FUNCTION mypump_molestia_registrar(
  p_token            TEXT,
  p_id               UUID,
  p_ejercicio_id     TEXT,
  p_ejercicio_nombre TEXT,
  p_dia_id           TEXT,
  p_zona             TEXT,
  p_lado             TEXT,
  p_desde            TEXT,
  p_cuando           TEXT,
  p_tipo             TEXT,
  p_intensidad       INTEGER,
  p_nota             TEXT,
  p_plataforma       TEXT,
  p_version          TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_cliente_id TEXT;
  v_fila       mypump_molestias%ROWTYPE;
  v_rutina     UUID;
  v_en_rutina  BOOLEAN;
  v_nota       TEXT := NULLIF(btrim(COALESCE(p_nota, '')), '');
  v_motivo     TEXT;
  v_ya         BOOLEAN := FALSE;
BEGIN
  v_cliente_id := mypump_get_cliente_id_from_token(p_token);
  IF v_cliente_id IS NULL THEN RETURN NULL; END IF;
  IF NOT mypump_feedback_palanca('me_duele') THEN RETURN jsonb_build_object('ok', FALSE, 'error', 'apagado'); END IF;
  IF p_id IS NULL
     OR char_length(btrim(COALESCE(p_ejercicio_id, ''))) NOT BETWEEN 1 AND 160
     OR char_length(btrim(COALESCE(p_ejercicio_nombre, ''))) NOT BETWEEN 1 AND 160
     OR char_length(COALESCE(p_dia_id, '')) > 80
     OR p_zona IS NULL OR p_zona NOT IN ('cuello','hombro','pecho','brazo','codo','antebrazo','muneca','abdomen',
          'espalda_alta','espalda_baja','cadera','gluteo','muslo_frente','muslo_atras','rodilla','pantorrilla','tobillo')
     OR p_lado IS NULL OR p_lado NOT IN ('izquierdo','derecho','ambos','centro')
     OR p_desde IS NULL OR p_desde NOT IN ('hoy','esta_semana','semanas','mas_de_un_mes')
     OR p_cuando IS NULL OR p_cuando NOT IN ('al_bajar','al_subir','todo_el_recorrido','despues','al_dia_siguiente')
     OR p_tipo IS NULL OR p_tipo NOT IN ('punzante','sordo','hormigueo')
     OR p_intensidad IS NULL OR p_intensidad NOT BETWEEN 0 AND 10
     OR char_length(COALESCE(v_nota, '')) > 500
     OR (p_plataforma IS NOT NULL AND p_plataforma NOT IN ('ios','android','web'))
     OR char_length(COALESCE(p_version, '')) > 40 THEN
    RETURN jsonb_build_object('ok', FALSE, 'error', 'datos');
  END IF;

  v_motivo := mypump_molestia_motivo_clinico(p_zona, p_tipo, p_intensidad, v_nota);

  -- La misma (reintento) o la abierta de este ejercicio (corrección).
  SELECT * INTO v_fila FROM mypump_molestias WHERE id = p_id;
  IF FOUND AND v_fila.cliente_id <> v_cliente_id THEN RETURN jsonb_build_object('ok', FALSE, 'error', 'datos'); END IF;
  IF FOUND AND v_fila.estado NOT IN ('nueva','avisada') THEN
    RETURN jsonb_build_object('ok', TRUE, 'ya', TRUE, 'molestia', mypump_molestia_vista_alumno(v_fila));
  END IF;
  IF NOT FOUND THEN
    SELECT * INTO v_fila FROM mypump_molestias
    WHERE cliente_id = v_cliente_id AND ejercicio_id = btrim(p_ejercicio_id) AND estado IN ('nueva','avisada') FOR UPDATE;
  END IF;

  IF FOUND THEN
    v_ya := TRUE;
    -- Si cambió algo, vuelve a «nueva» para que se avise otra vez; si pasó a clínico, cambia de destino.
    IF (v_fila.zona, v_fila.lado, v_fila.desde, v_fila.cuando, v_fila.tipo, v_fila.intensidad, COALESCE(v_fila.nota, ''))
       IS DISTINCT FROM (p_zona, p_lado, p_desde, p_cuando, p_tipo, p_intensidad::SMALLINT, COALESCE(v_nota, '')) THEN
      UPDATE mypump_molestias SET zona = p_zona, lado = p_lado, desde = p_desde, cuando = p_cuando, tipo = p_tipo,
             intensidad = p_intensidad, nota = v_nota, clinico = v_motivo IS NOT NULL, motivo_clinico = v_motivo,
             destino = CASE WHEN v_motivo IS NOT NULL THEN 'mati' ELSE 'editor' END,
             estado = 'nueva', avisado_en = NULL, actualizado_en = NOW()
      WHERE id = v_fila.id RETURNING * INTO v_fila;
    END IF;
    RETURN jsonb_build_object('ok', TRUE, 'ya', v_ya, 'molestia', mypump_molestia_vista_alumno(v_fila));
  END IF;

  -- Tope: 8 por día. Más que eso no es un aviso, es ruido (o abuso del token).
  IF (SELECT count(*) FROM mypump_molestias WHERE cliente_id = v_cliente_id AND creado_en > NOW() - INTERVAL '24 hours') >= 8 THEN
    RETURN jsonb_build_object('ok', FALSE, 'error', 'tope');
  END IF;

  SELECT id, jsonb_path_exists(estructura, '$.** ? (@.id == $e)', jsonb_build_object('e', btrim(p_ejercicio_id)))
    INTO v_rutina, v_en_rutina
  FROM mypump_rutinas WHERE cliente_id = v_cliente_id AND estado = 'activa' ORDER BY created_at DESC LIMIT 1;

  BEGIN
    INSERT INTO mypump_molestias (id, cliente_id, rutina_id, en_rutina, ejercicio_id, ejercicio_nombre, dia_id, zona, lado, desde, cuando, tipo,
                                  intensidad, nota, clinico, motivo_clinico, destino, plataforma, version_app)
    VALUES (p_id, v_cliente_id, v_rutina, v_en_rutina, btrim(p_ejercicio_id), btrim(p_ejercicio_nombre), NULLIF(btrim(COALESCE(p_dia_id, '')), ''),
            p_zona, p_lado, p_desde, p_cuando, p_tipo, p_intensidad, v_nota, v_motivo IS NOT NULL, v_motivo,
            CASE WHEN v_motivo IS NOT NULL THEN 'mati' ELSE 'editor' END, p_plataforma, NULLIF(btrim(COALESCE(p_version, '')), ''))
    RETURNING * INTO v_fila;
  EXCEPTION WHEN unique_violation THEN
    RETURN jsonb_build_object('ok', FALSE, 'error', 'reintentar');
  END;
  RETURN jsonb_build_object('ok', TRUE, 'ya', FALSE, 'molestia', mypump_molestia_vista_alumno(v_fila));
END;
$$;

-- ── La Mini (service_role). Diseño del aviso: feedback-alumno/AVISOS.md ──
-- Las que faltan avisar, las clínicas primero. Con la palanca apagada, nada. No trae el token ni nada del alumno más que su id.
CREATE OR REPLACE FUNCTION mypump_molestias_pendientes(p_destino TEXT DEFAULT NULL, p_limite INTEGER DEFAULT 20)
RETURNS JSONB
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT CASE WHEN NOT mypump_feedback_palanca('me_duele') THEN '[]'::JSONB ELSE
    COALESCE((SELECT jsonb_agg(to_jsonb(m) ORDER BY m.clinico DESC, m.creado_en)
              FROM (SELECT id, cliente_id, rutina_id, en_rutina, ejercicio_id, ejercicio_nombre, dia_id, zona, lado, desde, cuando, tipo, intensidad,
                           nota, clinico, motivo_clinico, destino, plataforma, version_app, creado_en, actualizado_en
                    FROM mypump_molestias
                    WHERE estado = 'nueva' AND (p_destino IS NULL OR destino = p_destino)
                    ORDER BY clinico DESC, creado_en LIMIT LEAST(GREATEST(COALESCE(p_limite, 20), 1), 100)) m), '[]'::JSONB) END;
$$;

-- El aviso salió: no vuelve a aparecer en pendientes (salvo que el alumno la corrija).
CREATE OR REPLACE FUNCTION mypump_molestia_avisada(p_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  WITH u AS (UPDATE mypump_molestias SET estado = 'avisada', avisado_en = NOW(), actualizado_en = NOW()
             WHERE id = p_id AND estado = 'nueva' RETURNING 1)
  SELECT EXISTS (SELECT 1 FROM u);
$$;

-- EDITOR cambió el ejercicio (o Mati la cerró). `p_resolucion` es interna: qué se cambió.
CREATE OR REPLACE FUNCTION mypump_molestia_cerrar(p_id UUID, p_estado TEXT, p_resolucion TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_n INTEGER;
BEGIN
  IF p_estado IS NULL OR p_estado NOT IN ('resuelta','descartada') OR char_length(COALESCE(p_resolucion, '')) > 500 THEN
    RAISE EXCEPTION 'estado o resolución inválidos' USING ERRCODE = '22023';
  END IF;
  UPDATE mypump_molestias SET estado = p_estado, resolucion = NULLIF(btrim(COALESCE(p_resolucion, '')), ''), resuelto_en = NOW(), actualizado_en = NOW()
  WHERE id = p_id AND estado IN ('nueva','avisada');
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n = 1;
END;
$$;

-- ═════════════════════════════ 2. «Lo compré / lo estoy tomando» ═════════════════════════════

-- La clave de un ítem: su nombre en minúsculas, sin tildes y con un solo espacio. Los ítems de la suplementación no tienen id.
-- Misma regla en las apps (vectores en apps/shared/fixtures/feedback/casos.json).
CREATE OR REPLACE FUNCTION mypump_suple_clave(p_nombre TEXT)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
SET search_path = public
AS $$
  SELECT btrim(regexp_replace(translate(lower(COALESCE(p_nombre, '')), 'áàäâéèëêíìïîóòöôúùüûñ', 'aaaaeeeeiiiioooouuuun'), '\s+', ' ', 'g'));
$$;

CREATE TABLE IF NOT EXISTS mypump_suple_estado (
  cliente_id     TEXT        NOT NULL,
  item           TEXT        NOT NULL CHECK (char_length(item) BETWEEN 1 AND 160),      -- mypump_suple_clave(nombre)
  item_nombre    TEXT        NOT NULL CHECK (char_length(item_nombre) BETWEEN 1 AND 160),
  estado         TEXT        NOT NULL CHECK (estado IN ('comprado','tomando','no_lo_consigo','lo_deje')),
  nota           TEXT        CHECK (char_length(nota) <= 300),                          -- dato, nunca instrucción
  marcado_en     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  historial      JSONB       NOT NULL DEFAULT '[]'::JSONB,                              -- los estados anteriores, hasta 20
  avisado_en     TIMESTAMPTZ,                                                           -- «no lo consigo» ya pasó a Mensajes
  PRIMARY KEY (cliente_id, item)
);
CREATE INDEX IF NOT EXISTS idx_mypump_suple_estado_cola ON mypump_suple_estado (marcado_en) WHERE estado = 'no_lo_consigo' AND avisado_en IS NULL;

REVOKE ALL ON mypump_suple_estado FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON mypump_suple_estado TO service_role;   -- el brief lee el estado por ítem
ALTER TABLE mypump_suple_estado ENABLE ROW LEVEL SECURITY;

-- El alumno marca un ítem. NULL = token caído. Solo ítems de SU suplementación que no sean protectores (fármacos).
CREATE OR REPLACE FUNCTION mypump_suple_marcar(p_token TEXT, p_item TEXT, p_estado TEXT, p_nota TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_cliente_id TEXT;
  v_clave      TEXT := mypump_suple_clave(p_item);
  v_nombre     TEXT;
  v_nota       TEXT := NULLIF(btrim(COALESCE(p_nota, '')), '');
  v_fila       mypump_suple_estado%ROWTYPE;
BEGIN
  v_cliente_id := mypump_get_cliente_id_from_token(p_token);
  IF v_cliente_id IS NULL THEN RETURN NULL; END IF;
  IF NOT mypump_feedback_palanca('suple_estado') THEN RETURN jsonb_build_object('ok', FALSE, 'error', 'apagado'); END IF;
  IF p_estado IS NULL OR p_estado NOT IN ('comprado','tomando','no_lo_consigo','lo_deje')
     OR char_length(v_clave) NOT BETWEEN 1 AND 160 OR char_length(COALESCE(v_nota, '')) > 300 THEN
    RETURN jsonb_build_object('ok', FALSE, 'error', 'datos');
  END IF;

  -- El ítem tiene que estar en lo que la app le muestra hoy, y no ser un protector.
  SELECT it->>'nombre' INTO v_nombre
  FROM mypump_suplementacion(p_token) s, jsonb_array_elements(CASE WHEN jsonb_typeof(s.suplementacion->'items') = 'array' THEN s.suplementacion->'items' ELSE '[]'::JSONB END) it
  WHERE mypump_suple_clave(it->>'nombre') = v_clave
    AND COALESCE(it->>'protector', '') NOT IN ('true', '1', 'si', 'sí')
  LIMIT 1;
  IF v_nombre IS NULL THEN RETURN jsonb_build_object('ok', FALSE, 'error', 'item'); END IF;

  SELECT * INTO v_fila FROM mypump_suple_estado WHERE cliente_id = v_cliente_id AND item = v_clave FOR UPDATE;
  IF FOUND AND v_fila.estado = p_estado AND COALESCE(v_fila.nota, '') = COALESCE(v_nota, '') THEN
    RETURN jsonb_build_object('ok', TRUE, 'ya', TRUE, 'item', v_clave, 'estado', v_fila.estado, 'marcado_en', v_fila.marcado_en);
  END IF;

  INSERT INTO mypump_suple_estado AS e (cliente_id, item, item_nombre, estado, nota)
  VALUES (v_cliente_id, v_clave, left(btrim(v_nombre), 160), p_estado, v_nota)
  ON CONFLICT (cliente_id, item) DO UPDATE SET
    historial = (SELECT COALESCE(jsonb_agg(h ORDER BY n), '[]'::JSONB)
                 FROM (SELECT h, n FROM jsonb_array_elements(e.historial || jsonb_build_object('estado', e.estado, 'nota', e.nota, 'marcado_en', e.marcado_en))
                       WITH ORDINALITY AS t(h, n) ORDER BY n DESC LIMIT 20) u),
    item_nombre = EXCLUDED.item_nombre, estado = EXCLUDED.estado, nota = EXCLUDED.nota, marcado_en = NOW(), avisado_en = NULL
  RETURNING * INTO v_fila;
  RETURN jsonb_build_object('ok', TRUE, 'ya', FALSE, 'item', v_clave, 'estado', v_fila.estado, 'marcado_en', v_fila.marcado_en);
END;
$$;

-- «No lo consigo» sin avisar, para Mensajes (marcas de su país). Con la palanca apagada, nada.
CREATE OR REPLACE FUNCTION mypump_suple_no_consigue(p_limite INTEGER DEFAULT 20)
RETURNS JSONB
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT CASE WHEN NOT mypump_feedback_palanca('suple_estado') THEN '[]'::JSONB ELSE
    COALESCE((SELECT jsonb_agg(jsonb_build_object('cliente_id', e.cliente_id, 'item', e.item, 'item_nombre', e.item_nombre, 'nota', e.nota, 'marcado_en', e.marcado_en) ORDER BY e.marcado_en)
              FROM (SELECT * FROM mypump_suple_estado WHERE estado = 'no_lo_consigo' AND avisado_en IS NULL
                    ORDER BY marcado_en LIMIT LEAST(GREATEST(COALESCE(p_limite, 20), 1), 100)) e), '[]'::JSONB) END;
$$;

CREATE OR REPLACE FUNCTION mypump_suple_avisado(p_cliente_id TEXT, p_item TEXT)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  WITH u AS (UPDATE mypump_suple_estado SET avisado_en = NOW()
             WHERE cliente_id = p_cliente_id AND item = p_item AND estado = 'no_lo_consigo' AND avisado_en IS NULL RETURNING 1)
  SELECT EXISTS (SELECT 1 FROM u);
$$;

-- ═════════════════════════════ La app, por token: una sola lectura ═════════════════════════════
-- NULL = token caído. Cada mitad dice si está habilitada; apagada, viene vacía.
CREATE OR REPLACE FUNCTION mypump_feedback_get(p_token TEXT)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_cliente_id TEXT;
  v_duele      BOOLEAN := mypump_feedback_palanca('me_duele');
  v_suple      BOOLEAN := mypump_feedback_palanca('suple_estado');
BEGIN
  v_cliente_id := mypump_get_cliente_id_from_token(p_token);
  IF v_cliente_id IS NULL THEN RETURN NULL; END IF;
  RETURN jsonb_build_object(
    'me_duele', jsonb_build_object(
      'habilitado', v_duele,
      -- Las abiertas, y las cerradas de los últimos 14 días.
      'molestias', CASE WHEN v_duele THEN COALESCE((SELECT jsonb_agg(mypump_molestia_vista_alumno(m) ORDER BY m.creado_en DESC)
                     FROM (SELECT * FROM mypump_molestias WHERE cliente_id = v_cliente_id AND estado <> 'descartada'
                             AND (estado IN ('nueva','avisada') OR resuelto_en > NOW() - INTERVAL '14 days')
                           ORDER BY creado_en DESC LIMIT 40) m), '[]'::JSONB) ELSE '[]'::JSONB END),
    'suple_estado', jsonb_build_object(
      'habilitado', v_suple,
      'items', CASE WHEN v_suple THEN COALESCE((SELECT jsonb_agg(jsonb_build_object('item', e.item, 'estado', e.estado, 'nota', e.nota, 'marcado_en', e.marcado_en) ORDER BY e.item)
                     FROM mypump_suple_estado e WHERE e.cliente_id = v_cliente_id), '[]'::JSONB) ELSE '[]'::JSONB END)
  );
END;
$$;

-- ═════════════════════════════ 3. Datos de vuelta para el brief ═════════════════════════════
-- No sube nada nuevo. Por día: pasos y sueño de Salud (Apple Salud o Health Connect) y el peso que el alumno carga en
-- «Peso corporal» (la app pide que sea en ayunas al despertar). La cuenta de pasos es la de `mypump_pasos_salud` (nativa_006).

-- Un renglón por alumno y día, los últimos 60 días.
CREATE OR REPLACE VIEW public.mypump_datos_dia WITH (security_invoker = true) AS
SELECT s.cliente_id, s.fecha,
       max(s.valor) FILTER (WHERE s.tipo = 'pasos' AND s.fuente <> 'manual')::INTEGER                                AS pasos,
       max(s.valor) FILTER (WHERE s.tipo = 'sueno_min' AND s.fuente <> 'manual')::INTEGER                            AS sueno_min,
       COALESCE((array_agg(s.valor ORDER BY s.updated_at DESC) FILTER (WHERE s.tipo = 'peso_kg' AND s.fuente = 'manual'))[1],
                (array_agg(s.valor ORDER BY s.updated_at DESC) FILTER (WHERE s.tipo = 'peso_kg' AND s.fuente <> 'manual'))[1])::NUMERIC(5,2) AS peso_ayunas,
       -- De dónde salió cada dato: 'salud' (Apple Salud o Health Connect), 'reloj' (otra fuente conectada) o 'manual'.
       CASE WHEN bool_or(s.tipo IN ('pasos','sueno_min') AND s.fuente IN ('apple_health','health_connect')) THEN 'salud'
            WHEN bool_or(s.tipo IN ('pasos','sueno_min') AND s.fuente <> 'manual') THEN 'reloj' END                    AS fuente,
       CASE WHEN bool_or(s.tipo = 'peso_kg' AND s.fuente = 'manual') THEN 'manual'
            WHEN bool_or(s.tipo = 'peso_kg') THEN 'salud' END                                                         AS fuente_peso
FROM mypump_salud_diaria s
WHERE s.tipo IN ('pasos','sueno_min','peso_kg')
  AND s.fecha >= (now() AT TIME ZONE 'America/Argentina/Buenos_Aires')::date - 60
GROUP BY s.cliente_id, s.fecha;

COMMENT ON VIEW public.mypump_datos_dia IS
  'Datos de vuelta por alumno y día (60 días): pasos y sueno_min de Salud, peso_ayunas (el manual de «Peso corporal» gana). nativa_feedback_alumno.';

-- El resumen que leen el brief y control_kcal, a una fecha (por defecto, hoy en Buenos Aires). El día `p_al` no entra:
-- está a medias. `pasos_confiable`: más de 4 días con dato; si no, el brief sigue con el formulario.
CREATE OR REPLACE FUNCTION mypump_datos_resumen(p_al DATE DEFAULT NULL)
RETURNS TABLE (
  cliente_id TEXT, al DATE, habilitado BOOLEAN,
  pasos_promedio_7d INTEGER, pasos_dias_7d INTEGER, pasos_confiable BOOLEAN,
  sueno_promedio_7d_min INTEGER, sueno_dias_7d INTEGER,
  peso_ayunas_ultimo NUMERIC, peso_ayunas_fecha DATE, peso_ayunas_promedio_7d NUMERIC, peso_ayunas_dias_7d INTEGER,
  peso_ayunas_promedio_7d_previo NUMERIC, peso_cambio_semanal_kg NUMERIC,
  adherencia_ultima SMALLINT, adherencia_semana DATE, adherencia_promedio_4s NUMERIC, adherencia_checks_4s INTEGER,
  fuente TEXT, ultimo_dato DATE
)
LANGUAGE sql
STABLE
SET search_path = public
AS $$
  WITH hoy AS (SELECT COALESCE(p_al, (now() AT TIME ZONE 'America/Argentina/Buenos_Aires')::date) AS d),
  dias AS (
    SELECT s.cliente_id, s.fecha,
           max(s.valor) FILTER (WHERE s.tipo = 'pasos' AND s.fuente <> 'manual') AS pasos,
           max(s.valor) FILTER (WHERE s.tipo = 'sueno_min' AND s.fuente <> 'manual') AS sueno,
           COALESCE((array_agg(s.valor ORDER BY s.updated_at DESC) FILTER (WHERE s.tipo = 'peso_kg' AND s.fuente = 'manual'))[1],
                    (array_agg(s.valor ORDER BY s.updated_at DESC) FILTER (WHERE s.tipo = 'peso_kg' AND s.fuente <> 'manual'))[1]) AS peso,
           bool_or(s.tipo IN ('pasos','sueno_min') AND s.fuente IN ('apple_health','health_connect')) AS de_salud,
           bool_or(s.tipo IN ('pasos','sueno_min') AND s.fuente <> 'manual') AS de_reloj
    FROM mypump_salud_diaria s, hoy
    WHERE s.tipo IN ('pasos','sueno_min','peso_kg') AND s.fecha >= hoy.d - 30 AND s.fecha <= hoy.d
    GROUP BY s.cliente_id, s.fecha
  ),
  salud AS (
    SELECT d.cliente_id,
           round(avg(d.pasos) FILTER (WHERE d.fecha >= hoy.d - 7 AND d.fecha < hoy.d))::INTEGER AS pasos_prom,
           count(d.pasos) FILTER (WHERE d.fecha >= hoy.d - 7 AND d.fecha < hoy.d)::INTEGER AS pasos_dias,
           -- El sueño de anoche se guarda con la fecha de hoy y ya está completo: entra.
           round(avg(d.sueno) FILTER (WHERE d.fecha > hoy.d - 7))::INTEGER AS sueno_prom,
           count(d.sueno) FILTER (WHERE d.fecha > hoy.d - 7)::INTEGER AS sueno_dias,
           (array_agg(d.peso ORDER BY d.fecha DESC) FILTER (WHERE d.peso IS NOT NULL))[1] AS peso_ultimo,
           max(d.fecha) FILTER (WHERE d.peso IS NOT NULL) AS peso_fecha,
           round(avg(d.peso) FILTER (WHERE d.fecha > hoy.d - 7), 2) AS peso_prom,
           count(d.peso) FILTER (WHERE d.fecha > hoy.d - 7)::INTEGER AS peso_dias,
           round(avg(d.peso) FILTER (WHERE d.fecha > hoy.d - 14 AND d.fecha <= hoy.d - 7), 2) AS peso_prom_previo,
           CASE WHEN bool_or(d.de_salud AND d.fecha >= hoy.d - 7) THEN 'salud' WHEN bool_or(d.de_reloj AND d.fecha >= hoy.d - 7) THEN 'reloj'
                WHEN bool_or(d.peso IS NOT NULL) THEN 'manual' END AS fuente,
           max(d.fecha) AS ultimo
    FROM dias d, hoy GROUP BY d.cliente_id
  ),
  checks AS (
    SELECT c.cliente_id,
           (array_agg(c.adherencia ORDER BY c.semana_lunes DESC))[1] AS ultima,
           max(c.semana_lunes) AS semana,
           round(avg(c.adherencia), 1) AS prom,
           count(*)::INTEGER AS n
    FROM mypump_checkin_semanal c, hoy
    WHERE c.adherencia IS NOT NULL AND c.semana_lunes > hoy.d - 28 AND c.semana_lunes <= hoy.d
    GROUP BY c.cliente_id
  )
  SELECT COALESCE(s.cliente_id, k.cliente_id), hoy.d, mypump_feedback_palanca('datos_brief'),
         s.pasos_prom, COALESCE(s.pasos_dias, 0), COALESCE(s.pasos_dias, 0) > 4,
         s.sueno_prom, COALESCE(s.sueno_dias, 0),
         s.peso_ultimo, s.peso_fecha, s.peso_prom, COALESCE(s.peso_dias, 0),
         s.peso_prom_previo, CASE WHEN s.peso_prom IS NOT NULL AND s.peso_prom_previo IS NOT NULL THEN s.peso_prom - s.peso_prom_previo END,
         k.ultima, k.semana, k.prom, COALESCE(k.n, 0),
         s.fuente, s.ultimo
  FROM salud s FULL JOIN checks k ON k.cliente_id = s.cliente_id, hoy;
$$;

-- Lo de hoy, para leer con un SELECT (PostgREST: /mypump_datos_brief?cliente_id=eq.<id>).
CREATE OR REPLACE VIEW public.mypump_datos_brief WITH (security_invoker = true) AS
SELECT * FROM mypump_datos_resumen(NULL);

COMMENT ON VIEW public.mypump_datos_brief IS
  'Resumen por alumno para el brief y control_kcal: pasos (promedio de 7 días completos, igual que mypump_pasos_salud), sueño, '
  'peso en ayunas y adherencia del check. habilitado = palanca datos_brief. Para otra fecha: mypump_datos_resumen(fecha). nativa_feedback_alumno.';

-- ── Permisos ──
REVOKE ALL ON public.mypump_datos_dia, public.mypump_datos_brief FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.mypump_datos_dia, public.mypump_datos_brief TO service_role;

REVOKE ALL ON FUNCTION
  mypump_feedback_palanca(TEXT), mypump_molestia_motivo_clinico(TEXT, TEXT, INTEGER, TEXT), mypump_molestia_vista_alumno(mypump_molestias),
  mypump_molestias_pendientes(TEXT, INTEGER), mypump_molestia_avisada(UUID), mypump_molestia_cerrar(UUID, TEXT, TEXT),
  mypump_suple_clave(TEXT), mypump_suple_no_consigue(INTEGER), mypump_suple_avisado(TEXT, TEXT), mypump_datos_resumen(DATE)
FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION
  mypump_feedback_palanca(TEXT), mypump_molestia_motivo_clinico(TEXT, TEXT, INTEGER, TEXT), mypump_molestia_vista_alumno(mypump_molestias),
  mypump_molestias_pendientes(TEXT, INTEGER), mypump_molestia_avisada(UUID), mypump_molestia_cerrar(UUID, TEXT, TEXT),
  mypump_suple_clave(TEXT), mypump_suple_no_consigue(INTEGER), mypump_suple_avisado(TEXT, TEXT), mypump_datos_resumen(DATE)
TO service_role;

REVOKE ALL ON FUNCTION
  mypump_feedback_get(TEXT), mypump_suple_marcar(TEXT, TEXT, TEXT, TEXT),
  mypump_molestia_registrar(TEXT, UUID, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, INTEGER, TEXT, TEXT, TEXT)
FROM PUBLIC;
GRANT EXECUTE ON FUNCTION
  mypump_feedback_get(TEXT), mypump_suple_marcar(TEXT, TEXT, TEXT, TEXT),
  mypump_molestia_registrar(TEXT, UUID, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, INTEGER, TEXT, TEXT, TEXT)
TO anon, authenticated, service_role;

NOTIFY pgrst, 'reload schema';
COMMIT;
