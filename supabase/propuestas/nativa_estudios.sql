-- nativa_estudios.sql — PROPUESTA, SIN APLICAR.
--
-- «Estudios y órdenes»: el alumno ve lo que tiene pendiente de hacerse, sube sus resultados (PDF o fotos), ve lo que ya
-- llegó (por la app o por WhatsApp, vía Pump Bot) con «Recibido» o «Mati lo vio», y abre la orden que le emitió Mati.
-- Diseño y revisión clínica: nativa-evidencia/estudios/DISENO.md.
--
-- Orden de despliegue: endpoints de mini-vision, este SQL, cambios del bot en la Mini (RUNBOOK). Sale APAGADO:
-- `estudios_app` en false. Prendida, entra solo quien esté en `mypump_estudios_habilitados`, salvo `estudios_para_todos`.
--
-- Invariantes:
--   · El `cliente_id` sale siempre del token. Los paths los arma el servidor y a la app no le llegan nunca.
--   · A la app no le llega nada clínico: ni valores, ni alertas, ni diagnósticos, ni prácticas, ni notas internas.
--   · «Mati lo vio» solo cambia con `mypump_estudios_marcar_visto`, por id de estudio, con quién lo marcó.
--   · Un archivo se puede abrir solo si lo subió el propio alumno desde la app, o si el estudio está visto Y la hoja
--     traía su nombre completo (identidad fuerte). Lo decide `mypump_estudios_paths_para_firmar`, no quien firma.
--   · Una orden solo es `visible` con los dos controles de texto pasados, copia propia y un nombre que la publicó (CHECK).
--   · Con la palanca apagada el bot no toma ningún envío.
BEGIN;

-- ── Bucket privado: lo que sube la app (carpeta e/) y la copia controlada de las órdenes (carpeta o/) ──
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('estudios', 'estudios', false, 20971520, ARRAY['application/pdf', 'image/jpeg'])
ON CONFLICT (id) DO NOTHING;
-- Sin políticas: ni el coach lo lee por la API. Todo pasa por la clave de servicio y URLs firmadas cortas.

-- ── Listas cerradas ──
CREATE OR REPLACE FUNCTION mypump_estudios_tipos()
RETURNS TEXT[] LANGUAGE sql IMMUTABLE SET search_path = public AS $$
  SELECT ARRAY['laboratorio','ecografia','ecocardiograma','ergometria','eco_estres','electrocardiograma','mapa',
               'densitometria','estudios','otro'];
$$;

-- El título que ve el alumno sale de acá: nadie escribe títulos a mano.
CREATE OR REPLACE FUNCTION mypump_estudios_titulo(p_tipo TEXT)
RETURNS TEXT LANGUAGE sql IMMUTABLE SET search_path = public AS $$
  SELECT CASE p_tipo
    WHEN 'laboratorio' THEN 'Análisis de laboratorio'
    WHEN 'ecografia' THEN 'Ecografía'
    WHEN 'ecocardiograma' THEN 'Ecocardiograma'
    WHEN 'ergometria' THEN 'Ergometría'
    WHEN 'eco_estres' THEN 'Eco estrés'
    WHEN 'electrocardiograma' THEN 'Electrocardiograma'
    WHEN 'mapa' THEN 'Presión de 24 horas'
    WHEN 'densitometria' THEN 'Densitometría'
    WHEN 'estudios' THEN 'Estudios'
    ELSE 'Estudio' END;
$$;

-- Lo que el bot llama de otra forma cae en un tipo de la lista; lo desconocido es 'otro'.
CREATE OR REPLACE FUNCTION mypump_estudios_tipo_normal(p_tipo TEXT)
RETURNS TEXT LANGUAGE sql IMMUTABLE SET search_path = public AS $$
  SELECT CASE
    WHEN lower(btrim(COALESCE(p_tipo, ''))) = ANY (mypump_estudios_tipos()) THEN lower(btrim(p_tipo))
    WHEN lower(COALESCE(p_tipo, '')) LIKE 'densitometria%' THEN 'densitometria'
    WHEN lower(COALESCE(p_tipo, '')) IN ('ecg', 'electro') THEN 'electrocardiograma'
    ELSE 'otro' END;
$$;

-- Texto en minúsculas y sin acentos, para comparar.
CREATE OR REPLACE FUNCTION mypump_estudios_plano(p TEXT)
RETURNS TEXT LANGUAGE sql IMMUTABLE SET search_path = public AS $$
  SELECT translate(lower(COALESCE(p, '')), 'áéíóúüñàèìòù', 'aeiouunaeiou');
$$;

-- CONTROL 2 de las órdenes y control único de todo texto corto que vaya a pantalla.
-- `p_practicas`: nombres de las prácticas del papel. Cada uno se descuenta UNA sola vez (su renglón en la orden): una
-- determinación puede llamarse «Testosterona total», pero un diagnóstico que repita la palabra no pasa.
-- Para texto de pantalla se llama con '[]': ahí no hay excepción.
CREATE OR REPLACE FUNCTION mypump_ordenes_texto_prohibido(p_texto TEXT, p_practicas JSONB DEFAULT '[]'::JSONB)
RETURNS BOOLEAN
LANGUAGE plpgsql
IMMUTABLE
SET search_path = public
AS $$
DECLARE
  v TEXT := regexp_replace(mypump_estudios_plano(p_texto), '\s+', ' ', 'g');
  p TEXT;
  i INTEGER;
BEGIN
  IF jsonb_typeof(p_practicas) = 'array' THEN
    -- Las más largas primero: «testosterona total y libre» antes que «testosterona total».
    FOR p IN SELECT regexp_replace(mypump_estudios_plano(x), '\s+', ' ', 'g')
               FROM jsonb_array_elements_text(p_practicas) x
              WHERE length(btrim(x)) >= 3 ORDER BY length(x) DESC LOOP
      i := position(p IN v);
      IF i > 0 THEN v := overlay(v PLACING ' ' FROM i FOR length(p)); END IF;
    END LOOP;
  END IF;
  RETURN v ~ ('\m(testosteron|androgen|anabol|esteroid|ergogenic|exogen|nandrolon|trembolon|boldenon|oxandrolon|estanozolol|'
           || 'stanozolol|metenolon|primobolan|drostanolon|mesterolon|proviron|oximetolon|metandrostenolon|dianabol|'
           || 'tamoxifen|clomifen|anastrozol|letrozol|exemestan|cabergolin|gonadotrof|gonadotrop|somatropin|'
           || 'semaglutid|tirzepatid|retatrutid|clenbuterol|aromatasa)')
      OR v ~ '\m(aas|trt|trh|pct|serm|sarm|sarms|hcg|hgh|rp|receta|recetas|particular|ciclo|ciclos|posciclo|postciclo|dosis|dopaje|doping|vial|viales|ampolla|ampollas|peptido|peptidos|intramuscular|inyeccion|inyecciones|inyectable|inyectables|aplicacion|aplicaciones)\M'
      OR v ~ '\m(terapia|reemplazo) (de reemplazo )?hormonal'
      OR v ~ '(inducid[oa]|secundari[oa] a|supresion del eje|bloqueo del eje|reduccion de danos)'
      OR v ~ '[0-9] ?(mg|mcg|ml|ui)\M'
      OR v ~ 'cada [0-9]+ (dias|horas|semanas)'
      OR v ~ '\m(t38|y42|f55|f1[0-9]|z72)\.?[0-9]?\M';
END;
$$;

REVOKE ALL ON FUNCTION mypump_estudios_tipos(), mypump_estudios_titulo(TEXT), mypump_estudios_tipo_normal(TEXT),
  mypump_estudios_plano(TEXT), mypump_ordenes_texto_prohibido(TEXT, JSONB) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION mypump_estudios_tipos(), mypump_estudios_titulo(TEXT), mypump_estudios_tipo_normal(TEXT),
  mypump_estudios_plano(TEXT), mypump_ordenes_texto_prohibido(TEXT, JSONB) TO service_role;

-- ── Tablas ──
CREATE TABLE IF NOT EXISTS mypump_estudios_habilitados (
  cliente_id    TEXT        PRIMARY KEY,
  motivo        TEXT,
  habilitado_en TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Un papel emitido que el alumno puede abrir. La fila la propone el publicador de la Mini; nunca se emite nada desde acá.
CREATE TABLE IF NOT EXISTS mypump_ordenes_app (
  id               UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  cliente_id       TEXT        NOT NULL,
  orden_id         UUID        NOT NULL,                                   -- medical.ordenes_pendientes.id
  documento_id     TEXT        NOT NULL UNIQUE CHECK (length(btrim(documento_id)) > 0),
  tipo             TEXT        NOT NULL CHECK (tipo IN ('laboratorio','estudios','ecografia','ecocardiograma')),
  emitida_en       TIMESTAMPTZ NOT NULL,
  vence_en         DATE        NOT NULL,
  path             TEXT        UNIQUE CHECK (path ~ '^o/[0-9a-f]{32}/[0-9a-f-]{36}\.pdf$'),
  sha256           TEXT        CHECK (sha256 ~ '^[0-9a-f]{64}$'),
  texto            TEXT        NOT NULL CHECK (char_length(texto) BETWEEN 40 AND 60000),
  practicas        JSONB       NOT NULL DEFAULT '[]'::JSONB CHECK (jsonb_typeof(practicas) = 'array'),
  control1_ok      BOOLEAN     NOT NULL DEFAULT FALSE,
  control1_detalle JSONB       NOT NULL DEFAULT '[]'::JSONB,
  estado           TEXT        NOT NULL DEFAULT 'a_revisar' CHECK (estado IN ('a_revisar','visible','bloqueada','reemplazada')),
  motivo_bloqueo   TEXT        CHECK (char_length(motivo_bloqueo) <= 400),
  publicado_por    TEXT        CHECK (char_length(publicado_por) <= 120),
  publicado_en     TIMESTAMPTZ,
  creado_en        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  actualizado_en   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  -- El doble control, en la tabla: ni un UPDATE a mano deja visible un papel que no pasó.
  CONSTRAINT orden_visible_controlada CHECK (estado <> 'visible' OR (
    control1_ok AND path IS NOT NULL AND sha256 IS NOT NULL
    AND length(btrim(COALESCE(publicado_por, ''))) > 0 AND publicado_en IS NOT NULL
    AND NOT mypump_ordenes_texto_prohibido(texto, practicas)))
);
CREATE INDEX IF NOT EXISTS idx_mypump_ordenes_app_cliente ON mypump_ordenes_app (cliente_id, emitida_en DESC);

-- Lo que el alumno ve en «Tus estudios»: una fila por fecha y tipo, igual que la fusión de la ficha.
CREATE TABLE IF NOT EXISTS mypump_estudios (
  id               UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  cliente_id       TEXT        NOT NULL,
  fecha            DATE        NOT NULL,
  fecha_legible    BOOLEAN     NOT NULL DEFAULT FALSE,                     -- FALSE: la hoja no traía fecha y el bot puso la del día
  tipo             TEXT        NOT NULL CHECK (tipo = ANY (mypump_estudios_tipos())),
  origen           TEXT        NOT NULL CHECK (origen IN ('whatsapp','app')),
  recibido_en      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  visto_en         TIMESTAMPTZ,
  visto_por        TEXT        CHECK (char_length(visto_por) <= 120),
  actualizado_en   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (cliente_id, fecha, tipo),
  CONSTRAINT estudio_visto_con_nombre CHECK ((visto_en IS NULL) = (visto_por IS NULL))
);
CREATE INDEX IF NOT EXISTS idx_mypump_estudios_cliente ON mypump_estudios (cliente_id, fecha DESC);
CREATE INDEX IF NOT EXISTS idx_mypump_estudios_sin_ver ON mypump_estudios (recibido_en) WHERE visto_en IS NULL;

-- Cada archivo guardado por el bot para ese estudio. `propia`: los mismos bytes los subió este alumno desde la app.
CREATE TABLE IF NOT EXISTS mypump_estudios_hojas (
  id               UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  estudio_id       UUID        NOT NULL REFERENCES mypump_estudios (id) ON DELETE CASCADE,
  cliente_id       TEXT        NOT NULL,
  path             TEXT        NOT NULL UNIQUE CHECK (path !~ '^[a-z]+://' AND path !~ '\.\.' AND char_length(path) <= 400),
  sha256           TEXT        CHECK (sha256 ~ '^[0-9a-f]{64}$'),
  mime             TEXT        NOT NULL DEFAULT 'application/pdf',
  propia           BOOLEAN     NOT NULL DEFAULT FALSE,
  identidad_fuerte BOOLEAN     NOT NULL DEFAULT FALSE,
  lote             TEXT        CHECK (char_length(lote) <= 40),
  creado_en        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  -- El path del bot empieza con el id de la ficha: una hoja nunca apunta a la carpeta de otro.
  CONSTRAINT hoja_en_su_carpeta CHECK (left(path, char_length(cliente_id) + 1) = cliente_id || '/')
);
CREATE INDEX IF NOT EXISTS idx_mypump_estudios_hojas_estudio ON mypump_estudios_hojas (estudio_id);

-- Lo pedido y todavía no llegado. Escriben Sistema base (órdenes), Entregas (antes de la llamada) y EDITOR (revisión, control).
CREATE TABLE IF NOT EXISTS mypump_estudios_pedidos (
  id               UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  cliente_id       TEXT        NOT NULL,
  tipo             TEXT        NOT NULL CHECK (tipo = ANY (mypump_estudios_tipos())),
  -- Aclaración corta para el alumno («abdominal»). Pasa por el control de texto, sin excepciones.
  detalle_alumno   TEXT        CHECK (char_length(detalle_alumno) <= 60 AND NOT mypump_ordenes_texto_prohibido(detalle_alumno)),
  practicas        JSONB       NOT NULL DEFAULT '[]'::JSONB CHECK (jsonb_typeof(practicas) = 'array'),   -- interno
  origen           TEXT        NOT NULL CHECK (origen IN ('orden','entrega','revision','control')),
  origen_ref       TEXT        NOT NULL CHECK (length(btrim(origen_ref)) > 0 AND char_length(origen_ref) <= 120),
  fecha_desde      DATE,                                                   -- «no antes de»
  fecha_limite     DATE        NOT NULL,
  estado           TEXT        NOT NULL DEFAULT 'pedido' CHECK (estado IN ('pedido','hecho','recibido','anulado')),
  hecho_fecha      DATE,
  hecho_en         TIMESTAMPTZ,
  estudio_id       UUID        REFERENCES mypump_estudios (id) ON DELETE SET NULL,
  completo         BOOLEAN,                                                -- NULL: falta que BOT MINI coteje con lo pedido
  pedido_por       TEXT        NOT NULL CHECK (length(btrim(pedido_por)) > 0 AND char_length(pedido_por) <= 120),
  nota_interna     TEXT        CHECK (char_length(nota_interna) <= 600),
  creado_en        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  actualizado_en   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (cliente_id, tipo, origen, origen_ref),
  CONSTRAINT pedido_fechas CHECK (fecha_desde IS NULL OR fecha_desde <= fecha_limite)
);
CREATE INDEX IF NOT EXISTS idx_mypump_estudios_pedidos_abiertos ON mypump_estudios_pedidos (cliente_id, fecha_limite) WHERE estado IN ('pedido','hecho');

-- Un envío de la app: todos sus archivos son un solo lote para Pump Bot.
CREATE TABLE IF NOT EXISTS mypump_estudios_envios (
  id               UUID        PRIMARY KEY,                                -- lo pone el teléfono: reintentar es idempotente
  cliente_id       TEXT        NOT NULL,
  pedido_id        UUID        REFERENCES mypump_estudios_pedidos (id) ON DELETE SET NULL,
  estado           TEXT        NOT NULL DEFAULT 'borrador' CHECK (estado IN ('borrador','enviado','procesando','procesado','error')),
  enviado_en       TIMESTAMPTZ,
  procesando_desde TIMESTAMPTZ,
  procesado_en     TIMESTAMPTZ,
  lote             TEXT        CHECK (char_length(lote) <= 40),
  intentos         INTEGER     NOT NULL DEFAULT 0,
  resumen          JSONB,                                                  -- interno: guardados, frenados, lectura parcial
  error_detalle    TEXT        CHECK (char_length(error_detalle) <= 600),
  creado_en        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  actualizado_en   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_mypump_estudios_envios_cola ON mypump_estudios_envios (estado, enviado_en) WHERE estado IN ('enviado','procesando');
CREATE INDEX IF NOT EXISTS idx_mypump_estudios_envios_cliente ON mypump_estudios_envios (cliente_id, creado_en DESC);

CREATE TABLE IF NOT EXISTS mypump_estudios_archivos (
  id               UUID        PRIMARY KEY,                                -- lo pone el teléfono
  envio_id         UUID        NOT NULL REFERENCES mypump_estudios_envios (id) ON DELETE CASCADE,
  cliente_id       TEXT        NOT NULL,
  path             TEXT        NOT NULL UNIQUE CHECK (path ~ '^e/[0-9a-f]{32}/[0-9a-f-]{36}/[0-9a-f-]{36}\.(pdf|jpg)$'),
  mime             TEXT        NOT NULL CHECK (mime IN ('application/pdf','image/jpeg')),
  bytes            INTEGER     NOT NULL CHECK (bytes > 0),
  sha256           TEXT        NOT NULL CHECK (sha256 ~ '^[0-9a-f]{64}$'),
  creado_en        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  borrado_en       TIMESTAMPTZ                                             -- el objeto de entrada ya se sacó del bucket
);
-- Los mismos bytes pueden entrar dos veces en un envío (la misma hoja elegida dos veces): son dos filas y el bot lee una sola.
-- Rechazar la segunda dejaba al teléfono contando un archivo más que el servidor, y el envío no cerraba nunca.
CREATE INDEX IF NOT EXISTS idx_mypump_estudios_archivos_sha ON mypump_estudios_archivos (cliente_id, sha256);

ALTER TABLE mypump_estudios_pedidos ADD COLUMN IF NOT EXISTS orden_app_id UUID REFERENCES mypump_ordenes_app (id) ON DELETE SET NULL;

-- En este proyecto las tablas nuevas heredan permisos por defecto, incluido TRUNCATE, que RLS no frena. anon y authenticated, nada:
-- son datos de salud y el Cerebro no los necesita. service_role solo lee; todo cambio pasa por las funciones de abajo.
REVOKE ALL ON mypump_estudios_habilitados, mypump_ordenes_app, mypump_estudios, mypump_estudios_hojas, mypump_estudios_pedidos,
  mypump_estudios_envios, mypump_estudios_archivos FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON mypump_ordenes_app, mypump_estudios, mypump_estudios_hojas, mypump_estudios_pedidos,
  mypump_estudios_envios, mypump_estudios_archivos TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON mypump_estudios_habilitados TO service_role;
ALTER TABLE mypump_estudios_habilitados ENABLE ROW LEVEL SECURITY;
ALTER TABLE mypump_ordenes_app ENABLE ROW LEVEL SECURITY;
ALTER TABLE mypump_estudios ENABLE ROW LEVEL SECURITY;
ALTER TABLE mypump_estudios_hojas ENABLE ROW LEVEL SECURITY;
ALTER TABLE mypump_estudios_pedidos ENABLE ROW LEVEL SECURITY;
ALTER TABLE mypump_estudios_envios ENABLE ROW LEVEL SECURITY;
ALTER TABLE mypump_estudios_archivos ENABLE ROW LEVEL SECURITY;

-- ── Palancas: apagadas ──
INSERT INTO mypump_app_config (clave, valor, nota) VALUES
  ('estudios_app', 'false'::JSONB, 'Estudios y órdenes. true = abierto a mypump_estudios_habilitados'),
  ('estudios_para_todos', 'false'::JSONB, 'Estudios y órdenes. true = abierto a todos, sin mirar mypump_estudios_habilitados'),
  ('ordenes_app_auto', 'false'::JSONB, 'Órdenes en la app. false = cada papel espera el OK; true = visible si pasan los dos controles')
ON CONFLICT (clave) DO NOTHING;

CREATE OR REPLACE FUNCTION mypump_estudios_habilitado(p_cliente_id TEXT)
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT COALESCE((SELECT valor = 'true'::JSONB FROM mypump_app_config WHERE clave = 'estudios_app'), FALSE)
     AND (COALESCE((SELECT valor = 'true'::JSONB FROM mypump_app_config WHERE clave = 'estudios_para_todos'), FALSE)
          OR EXISTS (SELECT 1 FROM mypump_estudios_habilitados WHERE cliente_id = p_cliente_id));
$$;

CREATE OR REPLACE FUNCTION mypump_estudios_hoy()
RETURNS DATE LANGUAGE sql STABLE SET search_path = public AS $$
  SELECT (NOW() AT TIME ZONE 'America/Argentina/Buenos_Aires')::DATE;
$$;

-- ¿Se puede abrir este estudio? Todas sus hojas tienen que cumplir: propia, o (visto e identidad fuerte).
CREATE OR REPLACE FUNCTION mypump_estudios_se_abre(p_estudio_id UUID)
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (SELECT 1 FROM mypump_estudios_hojas h WHERE h.estudio_id = p_estudio_id)
     AND NOT EXISTS (
       SELECT 1 FROM mypump_estudios_hojas h JOIN mypump_estudios e ON e.id = h.estudio_id
        WHERE h.estudio_id = p_estudio_id
          AND NOT (h.propia OR (e.visto_en IS NOT NULL AND h.identidad_fuerte)));
$$;

-- ── La app, por token (anon y authenticated). NULL = token caído ──
CREATE OR REPLACE FUNCTION mypump_estudios_get(p_token TEXT)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_cliente_id TEXT;
  v_hoy        DATE := mypump_estudios_hoy();
BEGIN
  v_cliente_id := mypump_get_cliente_id_from_token(p_token);
  IF v_cliente_id IS NULL THEN RETURN NULL; END IF;
  IF NOT mypump_estudios_habilitado(v_cliente_id) THEN RETURN jsonb_build_object('habilitado', FALSE); END IF;
  RETURN jsonb_build_object(
    'habilitado', TRUE,
    'hoy', v_hoy,
    'topes', jsonb_build_object('archivos_por_envio', 20, 'mb_por_archivo', 20),
    -- El control que viene: todavía no se puede hacer. Sin motivo.
    'proximo_control', (
      SELECT jsonb_build_object('tipo', p.tipo, 'titulo', mypump_estudios_titulo(p.tipo), 'desde', p.fecha_desde, 'hasta', p.fecha_limite)
        FROM mypump_estudios_pedidos p
       WHERE p.cliente_id = v_cliente_id AND p.origen = 'control' AND p.estado = 'pedido' AND p.fecha_desde > v_hoy
       ORDER BY p.fecha_desde, p.id LIMIT 1),
    'pendientes', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
               'id', p.id, 'tipo', p.tipo, 'titulo', mypump_estudios_titulo(p.tipo), 'detalle', p.detalle_alumno,
               'desde', p.fecha_desde, 'hasta', p.fecha_limite, 'estado', p.estado, 'hecho_fecha', p.hecho_fecha,
               'orden_id', (SELECT o.id FROM mypump_ordenes_app o WHERE o.id = p.orden_app_id AND o.cliente_id = v_cliente_id
                             AND o.estado = 'visible' AND o.vence_en >= v_hoy))
             ORDER BY p.fecha_limite, p.id)
        FROM mypump_estudios_pedidos p
       WHERE p.cliente_id = v_cliente_id AND p.estado IN ('pedido','hecho')
         AND NOT (p.origen = 'control' AND p.estado = 'pedido' AND p.fecha_desde > v_hoy)), '[]'::JSONB),
    'ordenes', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
               'id', o.id, 'tipo', o.tipo, 'titulo', mypump_estudios_titulo(o.tipo),
               'emitida', (o.emitida_en AT TIME ZONE 'America/Argentina/Buenos_Aires')::DATE,
               'vence', o.vence_en, 'vigente', o.vence_en >= v_hoy)
             ORDER BY o.emitida_en DESC, o.id)
        FROM mypump_ordenes_app o
       WHERE o.cliente_id = v_cliente_id AND o.estado = 'visible' AND o.vence_en >= v_hoy - 30), '[]'::JSONB),
    'estudios', COALESCE((
      SELECT jsonb_agg(x.j ORDER BY x.fecha DESC, x.id) FROM (
        SELECT e.fecha, e.id, jsonb_build_object(
                 'id', e.id, 'tipo', e.tipo, 'titulo', mypump_estudios_titulo(e.tipo),
                 'fecha', CASE WHEN e.fecha_legible THEN e.fecha END,
                 'hojas', (SELECT count(*) FROM mypump_estudios_hojas h WHERE h.estudio_id = e.id),
                 'estado', CASE WHEN e.visto_en IS NULL THEN 'recibido' ELSE 'visto' END,
                 'recibido_en', e.recibido_en,
                 'se_puede_abrir', mypump_estudios_se_abre(e.id)) AS j
          FROM mypump_estudios e WHERE e.cliente_id = v_cliente_id
         ORDER BY e.fecha DESC, e.id LIMIT 60) x), '[]'::JSONB),
    -- Envíos que todavía no se ven en «Tus estudios». Un error interno es trabajo nuestro: sigue «enviado».
    'envios', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
               'id', s.id, 'estado', CASE WHEN s.estado = 'borrador' THEN 'borrador' ELSE 'enviado' END,
               'archivos', (SELECT count(*) FROM mypump_estudios_archivos a WHERE a.envio_id = s.id),
               'pedido_id', s.pedido_id, 'enviado_en', s.enviado_en)
             ORDER BY s.creado_en DESC, s.id)
        FROM mypump_estudios_envios s
       WHERE s.cliente_id = v_cliente_id
         AND (s.estado IN ('enviado','procesando','error')
              -- Procesado sin nada guardado (hoja de otra persona, archivo ilegible): lo resuelve Mati; acá sigue «Recibido».
              OR (s.estado = 'procesado' AND COALESCE((s.resumen->>'guardados')::INTEGER, 0) = 0 AND s.procesado_en > NOW() - INTERVAL '30 days')
              OR (s.estado = 'borrador' AND s.creado_en > NOW() - INTERVAL '2 days'))), '[]'::JSONB)
  );
END;
$$;

-- Abre un envío con el id del teléfono, o devuelve el que ya estaba (`ya`).
CREATE OR REPLACE FUNCTION mypump_estudios_envio_nuevo(p_token TEXT, p_id UUID, p_pedido_id UUID DEFAULT NULL)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_cliente_id TEXT;
  v_fila       mypump_estudios_envios%ROWTYPE;
BEGIN
  v_cliente_id := mypump_get_cliente_id_from_token(p_token);
  IF v_cliente_id IS NULL THEN RETURN NULL; END IF;
  IF NOT mypump_estudios_habilitado(v_cliente_id) THEN RETURN jsonb_build_object('ok', FALSE, 'error', 'no_habilitado'); END IF;
  IF p_id IS NULL THEN RAISE EXCEPTION 'falta el id' USING ERRCODE = '22023'; END IF;

  SELECT * INTO v_fila FROM mypump_estudios_envios WHERE id = p_id;
  IF FOUND THEN
    IF v_fila.cliente_id <> v_cliente_id THEN RETURN jsonb_build_object('ok', FALSE, 'error', 'id_repetido'); END IF;
    RETURN jsonb_build_object('ok', TRUE, 'ya', TRUE, 'id', v_fila.id, 'estado', CASE WHEN v_fila.estado = 'borrador' THEN 'borrador' ELSE 'enviado' END);
  END IF;
  IF p_pedido_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM mypump_estudios_pedidos WHERE id = p_pedido_id AND cliente_id = v_cliente_id AND estado IN ('pedido','hecho')) THEN
    p_pedido_id := NULL;                         -- el pedido se cerró mientras tanto: el envío entra igual, suelto
  END IF;
  IF (SELECT count(*) FROM mypump_estudios_envios WHERE cliente_id = v_cliente_id AND creado_en > NOW() - INTERVAL '24 hours') >= 6 THEN
    RETURN jsonb_build_object('ok', FALSE, 'error', 'tope_dia');
  END IF;
  BEGIN
    INSERT INTO mypump_estudios_envios (id, cliente_id, pedido_id) VALUES (p_id, v_cliente_id, p_pedido_id) RETURNING * INTO v_fila;
  EXCEPTION WHEN unique_violation THEN
    SELECT * INTO v_fila FROM mypump_estudios_envios WHERE id = p_id AND cliente_id = v_cliente_id;
    IF NOT FOUND THEN RETURN jsonb_build_object('ok', FALSE, 'error', 'id_repetido'); END IF;
    RETURN jsonb_build_object('ok', TRUE, 'ya', TRUE, 'id', v_fila.id, 'estado', CASE WHEN v_fila.estado = 'borrador' THEN 'borrador' ELSE 'enviado' END);
  END;
  RETURN jsonb_build_object('ok', TRUE, 'ya', FALSE, 'id', v_fila.id, 'estado', 'borrador');
END;
$$;

-- Pasa a `enviado`. Idempotente. `p_archivos`: cuántos mandó el teléfono; si en el servidor hay menos, todavía no.
CREATE OR REPLACE FUNCTION mypump_estudios_enviar(p_token TEXT, p_id UUID, p_archivos INTEGER)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_cliente_id TEXT;
  v_fila       mypump_estudios_envios%ROWTYPE;
  v_n          INTEGER;
BEGIN
  v_cliente_id := mypump_get_cliente_id_from_token(p_token);
  IF v_cliente_id IS NULL THEN RETURN NULL; END IF;
  SELECT * INTO v_fila FROM mypump_estudios_envios WHERE id = p_id AND cliente_id = v_cliente_id FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', FALSE, 'error', 'no_encontrado'); END IF;
  IF v_fila.estado <> 'borrador' THEN RETURN jsonb_build_object('ok', TRUE, 'ya', TRUE, 'estado', 'enviado'); END IF;
  IF NOT mypump_estudios_habilitado(v_cliente_id) THEN RETURN jsonb_build_object('ok', FALSE, 'error', 'no_habilitado'); END IF;
  SELECT count(*) INTO v_n FROM mypump_estudios_archivos WHERE envio_id = p_id;
  IF v_n = 0 THEN RETURN jsonb_build_object('ok', FALSE, 'error', 'sin_archivos'); END IF;
  IF p_archivos IS NOT NULL AND v_n < p_archivos THEN RETURN jsonb_build_object('ok', FALSE, 'error', 'faltan_archivos', 'hay', v_n); END IF;
  UPDATE mypump_estudios_envios SET estado = 'enviado', enviado_en = NOW(), actualizado_en = NOW() WHERE id = p_id;
  RETURN jsonb_build_object('ok', TRUE, 'ya', FALSE, 'estado', 'enviado');
END;
$$;

-- «Ya me lo hice»: no cierra nada, solo le avisa a Mati que falta el resultado. `p_fecha` NULL lo deshace.
CREATE OR REPLACE FUNCTION mypump_estudios_hecho(p_token TEXT, p_pedido_id UUID, p_fecha DATE)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_cliente_id TEXT;
  v_fila       mypump_estudios_pedidos%ROWTYPE;
  v_hoy        DATE := mypump_estudios_hoy();
BEGIN
  v_cliente_id := mypump_get_cliente_id_from_token(p_token);
  IF v_cliente_id IS NULL THEN RETURN NULL; END IF;
  IF NOT mypump_estudios_habilitado(v_cliente_id) THEN RETURN jsonb_build_object('ok', FALSE, 'error', 'no_habilitado'); END IF;
  SELECT * INTO v_fila FROM mypump_estudios_pedidos WHERE id = p_pedido_id AND cliente_id = v_cliente_id FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', FALSE, 'error', 'no_encontrado'); END IF;
  IF v_fila.estado NOT IN ('pedido','hecho') THEN RETURN jsonb_build_object('ok', TRUE, 'ya', TRUE, 'estado', v_fila.estado); END IF;
  IF p_fecha IS NULL THEN
    UPDATE mypump_estudios_pedidos SET estado = 'pedido', hecho_fecha = NULL, hecho_en = NULL, actualizado_en = NOW() WHERE id = p_pedido_id;
    RETURN jsonb_build_object('ok', TRUE, 'estado', 'pedido');
  END IF;
  IF p_fecha > v_hoy + 1 OR p_fecha < v_hoy - 120 THEN RETURN jsonb_build_object('ok', FALSE, 'error', 'fecha'); END IF;
  UPDATE mypump_estudios_pedidos SET estado = 'hecho', hecho_fecha = p_fecha, hecho_en = NOW(), actualizado_en = NOW() WHERE id = p_pedido_id;
  RETURN jsonb_build_object('ok', TRUE, 'estado', 'hecho');
END;
$$;

REVOKE ALL ON FUNCTION mypump_estudios_habilitado(TEXT), mypump_estudios_hoy(), mypump_estudios_se_abre(UUID) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION mypump_estudios_habilitado(TEXT), mypump_estudios_hoy(), mypump_estudios_se_abre(UUID) TO service_role;
REVOKE ALL ON FUNCTION mypump_estudios_get(TEXT), mypump_estudios_envio_nuevo(TEXT, UUID, UUID), mypump_estudios_enviar(TEXT, UUID, INTEGER),
  mypump_estudios_hecho(TEXT, UUID, DATE) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION mypump_estudios_get(TEXT), mypump_estudios_envio_nuevo(TEXT, UUID, UUID), mypump_estudios_enviar(TEXT, UUID, INTEGER),
  mypump_estudios_hecho(TEXT, UUID, DATE) TO anon, authenticated, service_role;

-- ── Mini-vision (service_role) ──
-- Antes de leer el cuerpo y otra vez, con el envío trabado, al registrar. 'ok', 'ya', 'no_encontrado', 'ajeno', 'estado', 'tope', 'no_habilitado'.
CREATE OR REPLACE FUNCTION mypump_estudios_archivo_puede(p_cliente_id TEXT, p_envio_id UUID, p_archivo_id UUID)
RETURNS TEXT
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_estado TEXT;
  v_de     UUID;
BEGIN
  SELECT estado INTO v_estado FROM mypump_estudios_envios WHERE id = p_envio_id AND cliente_id = p_cliente_id;
  IF NOT FOUND THEN RETURN 'no_encontrado'; END IF;
  SELECT envio_id INTO v_de FROM mypump_estudios_archivos WHERE id = p_archivo_id;
  IF v_de = p_envio_id THEN RETURN 'ya'; END IF;
  IF v_de IS NOT NULL THEN RETURN 'ajeno'; END IF;
  IF NOT mypump_estudios_habilitado(p_cliente_id) THEN RETURN 'no_habilitado'; END IF;
  IF v_estado <> 'borrador' THEN RETURN 'estado'; END IF;
  IF (SELECT count(*) FROM mypump_estudios_archivos WHERE envio_id = p_envio_id) >= 20 THEN RETURN 'tope'; END IF;
  RETURN 'ok';
END;
$$;

-- 'ok', 'ya' o una negativa de `puede`.
CREATE OR REPLACE FUNCTION mypump_estudios_archivo_registrar(
  p_cliente_id TEXT, p_envio_id UUID, p_archivo_id UUID, p_path TEXT, p_mime TEXT, p_bytes INTEGER, p_sha256 TEXT
)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_puede TEXT;
BEGIN
  PERFORM 1 FROM mypump_estudios_envios WHERE id = p_envio_id AND cliente_id = p_cliente_id FOR UPDATE;
  IF NOT FOUND THEN RETURN 'no_encontrado'; END IF;
  v_puede := mypump_estudios_archivo_puede(p_cliente_id, p_envio_id, p_archivo_id);
  IF v_puede <> 'ok' THEN RETURN v_puede; END IF;
  INSERT INTO mypump_estudios_archivos (id, envio_id, cliente_id, path, mime, bytes, sha256)
  VALUES (p_archivo_id, p_envio_id, p_cliente_id, p_path, p_mime, p_bytes, p_sha256);
  UPDATE mypump_estudios_envios SET actualizado_en = NOW() WHERE id = p_envio_id;
  RETURN 'ok';
END;
$$;

-- Lo único que se firma. Devuelve los paths SOLO si el pedido es del alumno y se puede abrir; si no, lista vacía.
-- `p_clase`: 'estudio' (bucket analisis del bot) u 'orden' (bucket estudios).
CREATE OR REPLACE FUNCTION mypump_estudios_paths_para_firmar(p_cliente_id TEXT, p_clase TEXT, p_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT mypump_estudios_habilitado(p_cliente_id) THEN RETURN jsonb_build_object('resultado', 'no_habilitado'); END IF;
  IF p_clase = 'estudio' THEN
    IF NOT EXISTS (SELECT 1 FROM mypump_estudios WHERE id = p_id AND cliente_id = p_cliente_id) THEN RETURN jsonb_build_object('resultado', 'no_encontrado'); END IF;
    IF NOT mypump_estudios_se_abre(p_id) THEN RETURN jsonb_build_object('resultado', 'todavia_no'); END IF;
    RETURN jsonb_build_object('resultado', 'ok', 'bucket', 'analisis', 'archivos',
      (SELECT jsonb_agg(jsonb_build_object('path', h.path, 'mime', h.mime) ORDER BY h.creado_en, h.id)
         FROM mypump_estudios_hojas h WHERE h.estudio_id = p_id AND h.cliente_id = p_cliente_id));
  ELSIF p_clase = 'orden' THEN
    RETURN COALESCE((
      SELECT jsonb_build_object('resultado', 'ok', 'bucket', 'estudios', 'archivos', jsonb_build_array(jsonb_build_object('path', o.path, 'mime', 'application/pdf')))
        FROM mypump_ordenes_app o
       WHERE o.id = p_id AND o.cliente_id = p_cliente_id AND o.estado = 'visible' AND o.vence_en >= mypump_estudios_hoy()),
      jsonb_build_object('resultado', 'no_encontrado'));
  END IF;
  RETURN jsonb_build_object('resultado', 'no_encontrado');
END;
$$;

-- ── El bot (service_role) ──
-- Toma UN envío con todos sus archivos, o NULL. También retoma lo que quedó colgado por un reinicio (45 min) hasta 3 intentos.
CREATE OR REPLACE FUNCTION mypump_estudios_tomar()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_fila mypump_estudios_envios%ROWTYPE;
BEGIN
  -- Con la palanca maestra apagada no sale ningún archivo hacia la lectura, aunque haya envíos en cola.
  IF NOT COALESCE((SELECT valor = 'true'::JSONB FROM mypump_app_config WHERE clave = 'estudios_app'), FALSE) THEN RETURN NULL; END IF;
  UPDATE mypump_estudios_envios SET estado = 'error', error_detalle = 'colgado 3 veces', actualizado_en = NOW()
   WHERE estado = 'procesando' AND procesando_desde < NOW() - INTERVAL '45 minutes' AND intentos >= 3;
  SELECT * INTO v_fila FROM mypump_estudios_envios
   WHERE estado = 'enviado' OR (estado = 'procesando' AND procesando_desde < NOW() - INTERVAL '45 minutes')
   ORDER BY enviado_en, id LIMIT 1 FOR UPDATE SKIP LOCKED;
  IF NOT FOUND THEN RETURN NULL; END IF;
  UPDATE mypump_estudios_envios SET estado = 'procesando', procesando_desde = NOW(), intentos = intentos + 1, actualizado_en = NOW()
   WHERE id = v_fila.id RETURNING * INTO v_fila;
  RETURN jsonb_build_object('id', v_fila.id, 'cliente_id', v_fila.cliente_id, 'pedido_id', v_fila.pedido_id, 'intentos', v_fila.intentos,
    'archivos', COALESCE((SELECT jsonb_agg(jsonb_build_object('id', a.id, 'path', a.path, 'mime', a.mime, 'bytes', a.bytes, 'sha256', a.sha256)
                                           ORDER BY a.creado_en, a.id)
                            FROM mypump_estudios_archivos a WHERE a.envio_id = v_fila.id), '[]'::JSONB));
END;
$$;

CREATE OR REPLACE FUNCTION mypump_estudios_procesado(p_id UUID, p_lote TEXT, p_resumen JSONB)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE mypump_estudios_envios SET estado = 'procesado', procesado_en = NOW(), lote = p_lote, resumen = p_resumen, error_detalle = NULL, actualizado_en = NOW()
   WHERE id = p_id AND estado = 'procesando';
  RETURN FOUND;
END;
$$;

-- Vuelve a la cola (falla nuestra). `p_contar` FALSE devuelve el intento: se frenó por cuota, no por el envío.
CREATE OR REPLACE FUNCTION mypump_estudios_devolver(p_id UUID, p_contar BOOLEAN DEFAULT TRUE, p_detalle TEXT DEFAULT NULL)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE mypump_estudios_envios
     SET estado = CASE WHEN p_contar AND intentos >= 3 THEN 'error' ELSE 'enviado' END,
         intentos = CASE WHEN p_contar THEN intentos ELSE GREATEST(intentos - 1, 0) END,
         procesando_desde = NULL, error_detalle = left(p_detalle, 600), actualizado_en = NOW()
   WHERE id = p_id AND estado = 'procesando';
  RETURN FOUND;
END;
$$;

-- El gancho del guardado del bot: un archivo quedó en la ficha. Vale para WhatsApp y para la app.
-- Devuelve qué pasó con los pedidos, para el resumen que recibe Mati. NULL si la ficha no tiene cuenta en la app.
CREATE OR REPLACE FUNCTION mypump_estudios_registrar(
  p_cliente_id TEXT, p_fecha DATE, p_fecha_legible BOOLEAN, p_tipo TEXT, p_origen TEXT, p_lote TEXT,
  p_path TEXT, p_sha256 TEXT, p_mime TEXT, p_identidad_fuerte BOOLEAN, p_envio_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tipo     TEXT := mypump_estudios_tipo_normal(p_tipo);
  v_estudio  mypump_estudios%ROWTYPE;
  v_propia   BOOLEAN;
  v_pedido   mypump_estudios_pedidos%ROWTYPE;
  v_abiertos INTEGER;
  v_cruce    TEXT := 'sin_pedido';
  v_del_envio UUID;
  v_nuevas   INTEGER := 0;
BEGIN
  IF p_origen NOT IN ('whatsapp','app') THEN RAISE EXCEPTION 'origen inválido' USING ERRCODE = '22023'; END IF;
  IF p_fecha IS NULL THEN RAISE EXCEPTION 'falta la fecha' USING ERRCODE = '22023'; END IF;
  IF NOT EXISTS (SELECT 1 FROM mypump_clientes WHERE cliente_id = p_cliente_id) THEN RETURN NULL; END IF;

  INSERT INTO mypump_estudios (cliente_id, fecha, fecha_legible, tipo, origen)
  VALUES (p_cliente_id, p_fecha, COALESCE(p_fecha_legible, FALSE), v_tipo, p_origen)
  ON CONFLICT (cliente_id, fecha, tipo) DO UPDATE
    SET actualizado_en = NOW(), fecha_legible = mypump_estudios.fecha_legible OR EXCLUDED.fecha_legible
  RETURNING * INTO v_estudio;

  v_propia := p_sha256 IS NOT NULL AND EXISTS (SELECT 1 FROM mypump_estudios_archivos a WHERE a.cliente_id = p_cliente_id AND a.sha256 = p_sha256);
  -- Sin path: el bot guardó la lectura pero no pudo subir el archivo. El estudio se lista igual y no se puede abrir.
  IF p_path IS NOT NULL AND btrim(p_path) <> '' THEN
    INSERT INTO mypump_estudios_hojas (estudio_id, cliente_id, path, sha256, mime, propia, identidad_fuerte, lote)
    VALUES (v_estudio.id, p_cliente_id, p_path, p_sha256, COALESCE(p_mime, 'application/pdf'), v_propia, COALESCE(p_identidad_fuerte, FALSE), left(p_lote, 40))
    ON CONFLICT (path) DO NOTHING;
    GET DIAGNOSTICS v_nuevas = ROW_COUNT;
    -- Una hoja nueva en un estudio ya visto: nadie la miró todavía.
    IF v_nuevas > 0 AND v_estudio.visto_en IS NOT NULL THEN
      UPDATE mypump_estudios SET visto_en = NULL, visto_por = NULL WHERE id = v_estudio.id;
    END IF;
  END IF;

  -- Cierre de pedidos. Automático solo sin ambigüedad: fecha leída, posterior al pedido y a su «no antes de»,
  -- identidad segura, y un único pedido abierto de ese tipo (o el pedido desde el que se abrió el envío).
  IF p_envio_id IS NOT NULL THEN
    SELECT pedido_id INTO v_del_envio FROM mypump_estudios_envios WHERE id = p_envio_id AND cliente_id = p_cliente_id;
  END IF;
  SELECT count(*) INTO v_abiertos FROM mypump_estudios_pedidos WHERE cliente_id = p_cliente_id AND tipo = v_tipo AND estado IN ('pedido','hecho');
  IF v_abiertos > 0 THEN
    SELECT * INTO v_pedido FROM mypump_estudios_pedidos
     WHERE cliente_id = p_cliente_id AND tipo = v_tipo AND estado IN ('pedido','hecho')
       AND (v_abiertos = 1 OR id = v_del_envio)
     ORDER BY (id = v_del_envio) DESC NULLS LAST LIMIT 1 FOR UPDATE;
    IF NOT FOUND THEN v_cruce := 'varios_pedidos';
    ELSIF NOT COALESCE(p_fecha_legible, FALSE) THEN v_cruce := 'sin_fecha';
    ELSIF NOT (v_propia OR COALESCE(p_identidad_fuerte, FALSE)) THEN v_cruce := 'identidad_floja';
    ELSIF p_fecha < (v_pedido.creado_en AT TIME ZONE 'America/Argentina/Buenos_Aires')::DATE THEN v_cruce := 'estudio_viejo';
    ELSIF v_pedido.fecha_desde IS NOT NULL AND p_fecha < v_pedido.fecha_desde THEN v_cruce := 'antes_de_tiempo';
    ELSE
      UPDATE mypump_estudios_pedidos SET estado = 'recibido', estudio_id = v_estudio.id, completo = NULL, actualizado_en = NOW() WHERE id = v_pedido.id;
      v_cruce := 'cerrado';
    END IF;
  END IF;
  RETURN jsonb_build_object('estudio_id', v_estudio.id, 'tipo', v_tipo, 'propia', v_propia, 'cruce', v_cruce,
    'pedido_id', CASE WHEN v_cruce NOT IN ('sin_pedido','varios_pedidos') THEN v_pedido.id END);
END;
$$;

-- ── «Mati lo vio» (Mensajes, service_role) ──
-- Lo que espera el feedback de un alumno. Sin paths.
CREATE OR REPLACE FUNCTION mypump_estudios_sin_ver(p_cliente_id TEXT DEFAULT NULL)
RETURNS JSONB LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT COALESCE(jsonb_agg(jsonb_build_object('id', e.id, 'cliente_id', e.cliente_id, 'fecha', e.fecha, 'tipo', e.tipo,
           'origen', e.origen, 'recibido_en', e.recibido_en,
           'hojas', (SELECT count(*) FROM mypump_estudios_hojas h WHERE h.estudio_id = e.id)) ORDER BY e.recibido_en, e.id), '[]'::JSONB)
    FROM mypump_estudios e WHERE e.visto_en IS NULL AND (p_cliente_id IS NULL OR e.cliente_id = p_cliente_id);
$$;

-- Por id de estudio y con lo que había cuando se leyó: si después entró otra hoja (`p_leido_hasta`), no se marca.
CREATE OR REPLACE FUNCTION mypump_estudios_marcar_visto(p_estudio_id UUID, p_por TEXT, p_leido_hasta TIMESTAMPTZ)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_fila mypump_estudios%ROWTYPE;
BEGIN
  IF length(btrim(COALESCE(p_por, ''))) = 0 THEN RAISE EXCEPTION 'falta quién lo vio' USING ERRCODE = '22023'; END IF;
  IF p_leido_hasta IS NULL THEN RAISE EXCEPTION 'falta hasta cuándo se leyó' USING ERRCODE = '22023'; END IF;
  SELECT * INTO v_fila FROM mypump_estudios WHERE id = p_estudio_id FOR UPDATE;
  IF NOT FOUND THEN RETURN 'no_encontrado'; END IF;
  IF v_fila.visto_en IS NOT NULL THEN RETURN 'ya'; END IF;
  IF EXISTS (SELECT 1 FROM mypump_estudios_hojas WHERE estudio_id = p_estudio_id AND creado_en > p_leido_hasta) THEN RETURN 'hojas_nuevas'; END IF;
  UPDATE mypump_estudios SET visto_en = NOW(), visto_por = left(btrim(p_por), 120), actualizado_en = NOW() WHERE id = p_estudio_id;
  RETURN 'ok';
END;
$$;

-- ── Pedidos (Sistema base, Entregas, EDITOR, BOT MINI: service_role) ──
-- Alta o cambio de un pedido. No reabre uno ya recibido ni anulado: para eso está `_pedido_reabrir`.
CREATE OR REPLACE FUNCTION mypump_estudios_pedir(
  p_cliente_id TEXT, p_tipo TEXT, p_origen TEXT, p_origen_ref TEXT, p_fecha_limite DATE, p_pedido_por TEXT,
  p_fecha_desde DATE DEFAULT NULL, p_detalle_alumno TEXT DEFAULT NULL, p_practicas JSONB DEFAULT '[]'::JSONB,
  p_orden_app_id UUID DEFAULT NULL, p_nota_interna TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_fila mypump_estudios_pedidos%ROWTYPE;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM mypump_clientes WHERE cliente_id = p_cliente_id) THEN RETURN jsonb_build_object('ok', FALSE, 'error', 'sin_cuenta'); END IF;
  IF NOT (p_tipo = ANY (mypump_estudios_tipos())) THEN RETURN jsonb_build_object('ok', FALSE, 'error', 'tipo'); END IF;
  IF mypump_ordenes_texto_prohibido(p_detalle_alumno) THEN RETURN jsonb_build_object('ok', FALSE, 'error', 'detalle_prohibido'); END IF;
  IF p_origen = 'control' AND p_fecha_desde IS NULL THEN RETURN jsonb_build_object('ok', FALSE, 'error', 'control_sin_desde'); END IF;
  IF p_orden_app_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM mypump_ordenes_app WHERE id = p_orden_app_id AND cliente_id = p_cliente_id) THEN
    RETURN jsonb_build_object('ok', FALSE, 'error', 'orden_ajena');
  END IF;
  INSERT INTO mypump_estudios_pedidos (cliente_id, tipo, detalle_alumno, practicas, origen, origen_ref, fecha_desde, fecha_limite, pedido_por, orden_app_id, nota_interna)
  VALUES (p_cliente_id, p_tipo, NULLIF(btrim(p_detalle_alumno), ''), COALESCE(p_practicas, '[]'::JSONB), p_origen, btrim(p_origen_ref),
          p_fecha_desde, p_fecha_limite, btrim(p_pedido_por), p_orden_app_id, p_nota_interna)
  ON CONFLICT (cliente_id, tipo, origen, origen_ref) DO UPDATE
    SET detalle_alumno = EXCLUDED.detalle_alumno, practicas = EXCLUDED.practicas, fecha_desde = EXCLUDED.fecha_desde,
        fecha_limite = EXCLUDED.fecha_limite, orden_app_id = COALESCE(EXCLUDED.orden_app_id, mypump_estudios_pedidos.orden_app_id),
        nota_interna = COALESCE(EXCLUDED.nota_interna, mypump_estudios_pedidos.nota_interna), actualizado_en = NOW()
    WHERE mypump_estudios_pedidos.estado IN ('pedido','hecho')
  RETURNING * INTO v_fila;
  IF v_fila.id IS NULL THEN RETURN jsonb_build_object('ok', TRUE, 'ya_cerrado', TRUE); END IF;
  RETURN jsonb_build_object('ok', TRUE, 'id', v_fila.id, 'estado', v_fila.estado);
END;
$$;

-- `p_accion`: 'cerrar' (viejo pero sirve, con el OK de Mati; `p_completo` TRUE), 'completo' (el cotejo dio bien),
-- 'reabrir' (llegó incompleto o no era), 'anular'.
CREATE OR REPLACE FUNCTION mypump_estudios_pedido_resolver(p_id UUID, p_accion TEXT, p_por TEXT, p_estudio_id UUID DEFAULT NULL, p_nota TEXT DEFAULT NULL)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_fila mypump_estudios_pedidos%ROWTYPE;
BEGIN
  IF length(btrim(COALESCE(p_por, ''))) = 0 THEN RAISE EXCEPTION 'falta quién' USING ERRCODE = '22023'; END IF;
  SELECT * INTO v_fila FROM mypump_estudios_pedidos WHERE id = p_id FOR UPDATE;
  IF NOT FOUND THEN RETURN 'no_encontrado'; END IF;
  IF p_estudio_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM mypump_estudios WHERE id = p_estudio_id AND cliente_id = v_fila.cliente_id) THEN RETURN 'estudio_ajeno'; END IF;
  IF p_accion = 'cerrar' THEN
    UPDATE mypump_estudios_pedidos SET estado = 'recibido', completo = TRUE, estudio_id = COALESCE(p_estudio_id, estudio_id),
           nota_interna = left(concat_ws(' · ', nota_interna, 'cerrado por ' || p_por, p_nota), 600), actualizado_en = NOW() WHERE id = p_id;
  ELSIF p_accion = 'completo' THEN
    IF v_fila.estado <> 'recibido' THEN RETURN 'estado'; END IF;
    UPDATE mypump_estudios_pedidos SET completo = TRUE, actualizado_en = NOW() WHERE id = p_id;
  ELSIF p_accion = 'reabrir' THEN
    UPDATE mypump_estudios_pedidos SET estado = 'pedido', completo = FALSE, hecho_fecha = NULL, hecho_en = NULL,
           nota_interna = left(concat_ws(' · ', nota_interna, 'reabierto por ' || p_por, p_nota), 600), actualizado_en = NOW() WHERE id = p_id;
  ELSIF p_accion = 'anular' THEN
    UPDATE mypump_estudios_pedidos SET estado = 'anulado',
           nota_interna = left(concat_ws(' · ', nota_interna, 'anulado por ' || p_por, p_nota), 600), actualizado_en = NOW() WHERE id = p_id;
  ELSE
    RAISE EXCEPTION 'acción inválida' USING ERRCODE = '22023';
  END IF;
  RETURN 'ok';
END;
$$;

-- Tablero interno: pedidos abiertos (para Mensajes y Entregas), con lo vencido y lo que tiene la orden vencida. Sin datos clínicos de más.
CREATE OR REPLACE FUNCTION mypump_estudios_pedidos_abiertos(p_cliente_id TEXT DEFAULT NULL)
RETURNS JSONB LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT COALESCE(jsonb_agg(jsonb_build_object('id', p.id, 'cliente_id', p.cliente_id, 'tipo', p.tipo, 'origen', p.origen, 'origen_ref', p.origen_ref,
           'estado', p.estado, 'desde', p.fecha_desde, 'hasta', p.fecha_limite, 'hecho_fecha', p.hecho_fecha,
           'vencido', p.fecha_limite < mypump_estudios_hoy(),
           'orden_vencida', EXISTS (SELECT 1 FROM mypump_ordenes_app o WHERE o.id = p.orden_app_id AND o.vence_en < mypump_estudios_hoy()),
           'habilitado', mypump_estudios_habilitado(p.cliente_id)) ORDER BY p.fecha_limite, p.id), '[]'::JSONB)
    FROM mypump_estudios_pedidos p WHERE p.estado IN ('pedido','hecho') AND (p_cliente_id IS NULL OR p.cliente_id = p_cliente_id);
$$;

-- ── Órdenes (publicador de la Mini, service_role) ──
-- Propone un papel ya copiado al bucket. Queda `a_revisar`, o `bloqueada` si no pasa algún control. Con `ordenes_app_auto`
-- y los dos controles pasados, queda `visible` de una. Idempotente por `documento_id`: no pisa una fila que ya existe.
CREATE OR REPLACE FUNCTION mypump_ordenes_app_proponer(
  p_cliente_id TEXT, p_orden_id UUID, p_documento_id TEXT, p_tipo TEXT, p_emitida_en TIMESTAMPTZ, p_vence_en DATE,
  p_path TEXT, p_sha256 TEXT, p_texto TEXT, p_practicas JSONB, p_control1_ok BOOLEAN, p_control1_detalle JSONB,
  p_reemplaza TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_fila    mypump_ordenes_app%ROWTYPE;
  v_control2 BOOLEAN;
  v_auto    BOOLEAN := COALESCE((SELECT valor = 'true'::JSONB FROM mypump_app_config WHERE clave = 'ordenes_app_auto'), FALSE);
  v_estado  TEXT;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM mypump_clientes WHERE cliente_id = p_cliente_id) THEN RETURN jsonb_build_object('ok', FALSE, 'error', 'sin_cuenta'); END IF;
  SELECT * INTO v_fila FROM mypump_ordenes_app WHERE documento_id = p_documento_id;
  IF FOUND THEN RETURN jsonb_build_object('ok', TRUE, 'ya', TRUE, 'id', v_fila.id, 'estado', v_fila.estado); END IF;
  v_control2 := NOT mypump_ordenes_texto_prohibido(p_texto, p_practicas);
  v_estado := CASE WHEN NOT (COALESCE(p_control1_ok, FALSE) AND v_control2) THEN 'bloqueada' WHEN v_auto THEN 'visible' ELSE 'a_revisar' END;
  INSERT INTO mypump_ordenes_app (cliente_id, orden_id, documento_id, tipo, emitida_en, vence_en, path, sha256, texto, practicas,
                                  control1_ok, control1_detalle, estado, motivo_bloqueo, publicado_por, publicado_en)
  VALUES (p_cliente_id, p_orden_id, btrim(p_documento_id), p_tipo, p_emitida_en, p_vence_en, p_path, p_sha256, p_texto, COALESCE(p_practicas, '[]'::JSONB),
          COALESCE(p_control1_ok, FALSE), COALESCE(p_control1_detalle, '[]'::JSONB), v_estado,
          CASE WHEN v_estado = 'bloqueada' THEN CASE WHEN NOT COALESCE(p_control1_ok, FALSE) THEN 'control 1' ELSE 'control 2' END END,
          CASE WHEN v_estado = 'visible' THEN 'automático (dos controles)' END, CASE WHEN v_estado = 'visible' THEN NOW() END)
  RETURNING * INTO v_fila;
  IF p_reemplaza IS NOT NULL AND v_estado <> 'bloqueada' THEN
    UPDATE mypump_ordenes_app SET estado = 'reemplazada', actualizado_en = NOW()
     WHERE documento_id = p_reemplaza AND cliente_id = p_cliente_id AND estado IN ('a_revisar','visible');
  END IF;
  RETURN jsonb_build_object('ok', TRUE, 'ya', FALSE, 'id', v_fila.id, 'estado', v_fila.estado, 'control2_ok', v_control2);
END;
$$;

-- El OK humano de un papel `a_revisar`. Vuelve a correr el control 2: la lista pudo haber crecido desde que se propuso.
CREATE OR REPLACE FUNCTION mypump_ordenes_app_publicar(p_id UUID, p_por TEXT)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_fila mypump_ordenes_app%ROWTYPE;
BEGIN
  IF length(btrim(COALESCE(p_por, ''))) = 0 THEN RAISE EXCEPTION 'falta quién publica' USING ERRCODE = '22023'; END IF;
  SELECT * INTO v_fila FROM mypump_ordenes_app WHERE id = p_id FOR UPDATE;
  IF NOT FOUND THEN RETURN 'no_encontrado'; END IF;
  IF v_fila.estado = 'visible' THEN RETURN 'ya'; END IF;
  IF v_fila.estado <> 'a_revisar' THEN RETURN 'estado'; END IF;
  IF NOT v_fila.control1_ok OR mypump_ordenes_texto_prohibido(v_fila.texto, v_fila.practicas) THEN
    UPDATE mypump_ordenes_app SET estado = 'bloqueada', motivo_bloqueo = 'no pasó el control al publicar', actualizado_en = NOW() WHERE id = p_id;
    RETURN 'bloqueada';
  END IF;
  UPDATE mypump_ordenes_app SET estado = 'visible', publicado_por = left(btrim(p_por), 120), publicado_en = NOW(), actualizado_en = NOW() WHERE id = p_id;
  RETURN 'ok';
END;
$$;

-- Saca un papel de la vista del alumno (orden corregida, error). No borra nada.
CREATE OR REPLACE FUNCTION mypump_ordenes_app_bloquear(p_id UUID, p_por TEXT, p_motivo TEXT)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF length(btrim(COALESCE(p_por, ''))) = 0 OR length(btrim(COALESCE(p_motivo, ''))) = 0 THEN RAISE EXCEPTION 'falta quién o por qué' USING ERRCODE = '22023'; END IF;
  UPDATE mypump_ordenes_app SET estado = 'bloqueada', motivo_bloqueo = left(p_por || ': ' || p_motivo, 400), actualizado_en = NOW()
   WHERE id = p_id AND estado IN ('a_revisar','visible');
  RETURN CASE WHEN FOUND THEN 'ok' ELSE 'no_encontrado' END;
END;
$$;

-- ── Limpieza de lo que entró por la app: a los 30 días de procesado, el objeto de entrada sobra (la copia buena es la de la ficha) ──
CREATE OR REPLACE FUNCTION mypump_estudios_para_limpiar(p_dias INTEGER DEFAULT 30, p_limite INTEGER DEFAULT 50)
RETURNS JSONB LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT COALESCE(jsonb_agg(jsonb_build_object('id', x.id, 'path', x.path)), '[]'::JSONB) FROM (
    SELECT a.id, a.path FROM mypump_estudios_archivos a JOIN mypump_estudios_envios s ON s.id = a.envio_id
     WHERE a.borrado_en IS NULL
       AND ((s.estado = 'procesado' AND s.procesado_en < NOW() - make_interval(days => GREATEST(p_dias, 7)))
            OR (s.estado = 'borrador' AND s.actualizado_en < NOW() - INTERVAL '7 days'))
     ORDER BY a.creado_en LIMIT LEAST(GREATEST(p_limite, 1), 200)) x;
$$;

CREATE OR REPLACE FUNCTION mypump_estudios_limpieza_hecha(p_archivo_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE mypump_estudios_archivos SET borrado_en = NOW() WHERE id = p_archivo_id AND borrado_en IS NULL;
  RETURN FOUND;
END;
$$;

REVOKE ALL ON FUNCTION
  mypump_estudios_archivo_puede(TEXT, UUID, UUID), mypump_estudios_archivo_registrar(TEXT, UUID, UUID, TEXT, TEXT, INTEGER, TEXT),
  mypump_estudios_paths_para_firmar(TEXT, TEXT, UUID), mypump_estudios_tomar(), mypump_estudios_procesado(UUID, TEXT, JSONB),
  mypump_estudios_devolver(UUID, BOOLEAN, TEXT),
  mypump_estudios_registrar(TEXT, DATE, BOOLEAN, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, BOOLEAN, UUID),
  mypump_estudios_sin_ver(TEXT), mypump_estudios_marcar_visto(UUID, TEXT, TIMESTAMPTZ),
  mypump_estudios_pedir(TEXT, TEXT, TEXT, TEXT, DATE, TEXT, DATE, TEXT, JSONB, UUID, TEXT),
  mypump_estudios_pedido_resolver(UUID, TEXT, TEXT, UUID, TEXT), mypump_estudios_pedidos_abiertos(TEXT),
  mypump_ordenes_app_proponer(TEXT, UUID, TEXT, TEXT, TIMESTAMPTZ, DATE, TEXT, TEXT, TEXT, JSONB, BOOLEAN, JSONB, TEXT),
  mypump_ordenes_app_publicar(UUID, TEXT), mypump_ordenes_app_bloquear(UUID, TEXT, TEXT),
  mypump_estudios_para_limpiar(INTEGER, INTEGER), mypump_estudios_limpieza_hecha(UUID)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION
  mypump_estudios_archivo_puede(TEXT, UUID, UUID), mypump_estudios_archivo_registrar(TEXT, UUID, UUID, TEXT, TEXT, INTEGER, TEXT),
  mypump_estudios_paths_para_firmar(TEXT, TEXT, UUID), mypump_estudios_tomar(), mypump_estudios_procesado(UUID, TEXT, JSONB),
  mypump_estudios_devolver(UUID, BOOLEAN, TEXT),
  mypump_estudios_registrar(TEXT, DATE, BOOLEAN, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, BOOLEAN, UUID),
  mypump_estudios_sin_ver(TEXT), mypump_estudios_marcar_visto(UUID, TEXT, TIMESTAMPTZ),
  mypump_estudios_pedir(TEXT, TEXT, TEXT, TEXT, DATE, TEXT, DATE, TEXT, JSONB, UUID, TEXT),
  mypump_estudios_pedido_resolver(UUID, TEXT, TEXT, UUID, TEXT), mypump_estudios_pedidos_abiertos(TEXT),
  mypump_ordenes_app_proponer(TEXT, UUID, TEXT, TEXT, TIMESTAMPTZ, DATE, TEXT, TEXT, TEXT, JSONB, BOOLEAN, JSONB, TEXT),
  mypump_ordenes_app_publicar(UUID, TEXT), mypump_ordenes_app_bloquear(UUID, TEXT, TEXT),
  mypump_estudios_para_limpiar(INTEGER, INTEGER), mypump_estudios_limpieza_hecha(UUID)
  TO service_role;

NOTIFY pgrst, 'reload schema';
COMMIT;
