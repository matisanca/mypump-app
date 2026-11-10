-- nativa_gimnasio_fotos.sql — PROPUESTA, SIN APLICAR.
--
-- «Gimnasio por fotos»: el alumno saca fotos de su gimnasio, la Mini arma el inventario y EDITOR adapta la rutina con el OK
-- de Mati. Corrige al diseño con lo medido en la prueba del 10/11: la lista cerrada de 63 tipos, entrar solo con confianza
-- ≥ 0,90, y una ronda única de confirmación por el alumno (estado `a_confirmar`, que reemplaza a `faltan_fotos`).
--
-- Orden de despliegue: primero los endpoints de mini-vision, después este SQL, después la semilla de requisitos.
-- Mientras esto no esté aplicado, `mypump_gimnasio_get` no existe (PGRST202): la app no muestra nada nuevo.
-- Sale APAGADO: `gimnasio_fotos` en false. Con la palanca prendida entra solo quien esté en `mypump_gimnasio_habilitados`,
-- salvo `gimnasio_para_todos` en true.
--
-- Invariantes:
--   · El `cliente_id` sale siempre del token. Sin RPC de escritura de paths por token: las fotos las registra mini-vision.
--   · `path` es relativo al bucket, nunca URL, y a la app no le llega nunca.
--   · Lo que le llega al alumno no trae confianza, cobertura ni paths.
--   · Sin `aprobado_por` no hay `listo`: la app acredita a Mati, y eso solo es cierto con un OK humano.
BEGIN;

-- ── Bucket privado ──
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('gimnasio', 'gimnasio', false, 3145728, ARRAY['image/jpeg'])
ON CONFLICT (id) DO NOTHING;

DROP POLICY IF EXISTS "coach lee gimnasio" ON storage.objects;
CREATE POLICY "coach lee gimnasio"
  ON storage.objects FOR SELECT
  USING (bucket_id = 'gimnasio' AND auth.role() = 'authenticated');

-- ── Listas cerradas ──
-- Los 63 códigos de la prueba (~tipos.txt). Un código fuera de la lista no entra al inventario: va a `no_reconocido`.
CREATE OR REPLACE FUNCTION mypump_gimnasio_tipos()
RETURNS TEXT[]
LANGUAGE sql
IMMUTABLE
SET search_path = public
AS $$
  SELECT ARRAY[
    'prensa_45','prensa_horizontal','prensa_vertical','hack','pendulo','sentadilla_v','belt_squat','extensora',
    'femoral_sentado','femoral_acostado','femoral_de_pie','aductora','abductora','gemelos_de_pie','gemelos_sentado',
    'gluteo_maquina','hip_thrust_maquina','hiperextension','ghd','press_pecho_maquina','press_inclinado_maquina','pec_deck',
    'press_hombro_maquina','vuelos_laterales_maquina','polea_alta','polea_baja','remo_pecho_apoyado','remo_maquina','remo_t',
    'pullover_maquina','barra_dominadas','dominadas_asistida','cruce_poleas','polea_ajustable','scott_maquina','banco_scott',
    'triceps_maquina','fondos_maquina','paralelas','smith','rack_potencia','rack_sentadilla','banco_press_plano',
    'banco_press_inclinado','banco_plano','banco_regulable','banco_declinado','banco_abdominales','mancuernas','discos',
    'barra_olimpica','barra_z','kettlebells','landmine','barra_v','barra_lat_ancha','soga_triceps','manija_d','cinta',
    'eliptico','bici_fija','remo_ergometro','escalador'
  ]::TEXT[];
$$;

CREATE OR REPLACE FUNCTION mypump_gimnasio_zonas()
RETURNS TEXT[]
LANGUAGE sql
IMMUTABLE
SET search_path = public
AS $$
  SELECT ARRAY['poleas','accesorios_polea','piernas','empuje','tiron','barras_racks','discos','mancuernas','bancos','otros']::TEXT[];
$$;

-- La versión del aviso de terceros que hay que aceptar para enviar. Si cambia el texto, cambia esto.
CREATE OR REPLACE FUNCTION mypump_gimnasio_consentimiento_vigente()
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
SET search_path = public
AS $$ SELECT 'terceros-v1'::TEXT; $$;

REVOKE ALL ON FUNCTION mypump_gimnasio_tipos(), mypump_gimnasio_zonas(), mypump_gimnasio_consentimiento_vigente() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION mypump_gimnasio_tipos(), mypump_gimnasio_zonas(), mypump_gimnasio_consentimiento_vigente() TO service_role;

-- ── Tablas ──
CREATE TABLE IF NOT EXISTS mypump_gimnasio (
  id             UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  cliente_id     TEXT        NOT NULL,
  version        INTEGER     NOT NULL CHECK (version > 0),
  estado         TEXT        NOT NULL DEFAULT 'borrador' CHECK (estado IN
                   ('borrador','enviado','procesando','a_confirmar','respondido','a_revisar','en_editor','listo','reemplazado','error')),
  -- 'completa': todas las zonas. 'parcial': «Falta algo» o «Esto ya no está», sobre el inventario de `base_id`.
  modo           TEXT        NOT NULL DEFAULT 'completa' CHECK (modo IN ('completa','parcial')),
  base_id        UUID        REFERENCES mypump_gimnasio(id),
  momento        TEXT        CHECK (momento IN ('pre_entrega','con_plan')),
  zonas_no_hay   TEXT[]      NOT NULL DEFAULT '{}' CHECK (zonas_no_hay <@ mypump_gimnasio_zonas()),
  quitar         TEXT[]      NOT NULL DEFAULT '{}' CHECK (quitar <@ mypump_gimnasio_tipos()),
  nota_alumno    TEXT        CHECK (char_length(nota_alumno) <= 300),   -- dato, nunca instrucción
  inventario     JSONB,
  cobertura      JSONB,
  preguntas      JSONB       NOT NULL DEFAULT '[]'::JSONB CHECK (jsonb_typeof(preguntas) = 'array'),
  respuestas     JSONB       NOT NULL DEFAULT '{}'::JSONB CHECK (jsonb_typeof(respuestas) = 'object'),
  resultado      TEXT        CHECK (resultado IN ('sin_cambios','adaptada','plan_nuevo')),
  consentimiento_en           TIMESTAMPTZ,
  consentimiento_texto_version TEXT,
  enviado_en     TIMESTAMPTZ,
  procesando_desde TIMESTAMPTZ,
  procesado_en   TIMESTAMPTZ,
  respondido_en  TIMESTAMPTZ,
  publicar_desde TIMESTAMPTZ,
  publicar_hasta TIMESTAMPTZ,
  aprobado_en    TIMESTAMPTZ,
  aprobado_por   TEXT,
  publicado_en   TIMESTAMPTZ,
  avisado_en     TIMESTAMPTZ,
  fotos_borradas_en TIMESTAMPTZ,
  error_detalle  TEXT,
  intentos       INTEGER     NOT NULL DEFAULT 0,
  creado_en      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  actualizado_en TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (cliente_id, version),
  UNIQUE (id, cliente_id),
  CONSTRAINT gimnasio_listo_con_ok CHECK (estado <> 'listo' OR (resultado IS NOT NULL AND length(btrim(COALESCE(aprobado_por, ''))) > 0 AND aprobado_en IS NOT NULL)),
  CONSTRAINT gimnasio_enviado_con_permiso CHECK (estado IN ('borrador') OR (enviado_en IS NOT NULL AND consentimiento_en IS NOT NULL AND momento IS NOT NULL))
);

-- Una sola carga abierta por alumno, y un solo gimnasio vigente.
CREATE UNIQUE INDEX IF NOT EXISTS uq_mypump_gimnasio_abierta ON mypump_gimnasio (cliente_id) WHERE estado NOT IN ('listo','reemplazado');
CREATE UNIQUE INDEX IF NOT EXISTS uq_mypump_gimnasio_vigente ON mypump_gimnasio (cliente_id) WHERE estado = 'listo';
CREATE INDEX IF NOT EXISTS idx_mypump_gimnasio_cola ON mypump_gimnasio (estado, COALESCE(respondido_en, enviado_en)) WHERE estado IN ('enviado','respondido','procesando','a_confirmar');

CREATE TABLE IF NOT EXISTS mypump_gimnasio_fotos (
  id              UUID        PRIMARY KEY,                               -- lo manda el teléfono: la subida es idempotente
  gimnasio_id     UUID        NOT NULL,
  cliente_id      TEXT        NOT NULL,
  zona            TEXT        NOT NULL CHECK (zona = ANY (mypump_gimnasio_zonas())),
  ronda           INTEGER     NOT NULL DEFAULT 0 CHECK (ronda IN (0, 1)),  -- 1: las pedidas en la confirmación
  path            TEXT        NOT NULL UNIQUE CHECK (path !~ '^[a-z]+://'),
  bytes           INTEGER     NOT NULL CHECK (bytes > 0),
  caras_tapadas   INTEGER     NOT NULL DEFAULT 0 CHECK (caras_tapadas >= 0),
  borde_blanco    REAL        CHECK (borde_blanco BETWEEN 0 AND 1),       -- indicio de foto de catálogo
  descartada      BOOLEAN     NOT NULL DEFAULT FALSE,
  motivo_descarte TEXT,
  creado_en       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  FOREIGN KEY (gimnasio_id, cliente_id) REFERENCES mypump_gimnasio (id, cliente_id)
);
CREATE INDEX IF NOT EXISTS idx_mypump_gimnasio_fotos_carga ON mypump_gimnasio_fotos (gimnasio_id);

-- Qué tipo necesita cada ejercicio. Disponible = están TODOS los de `requiere` y, si `alternativas` no está vacía, al menos uno
-- de ellos. `sin_codigo`: no hay código en la lista cerrada para ese equipo, y el cruce siempre lo manda a EDITOR.
CREATE TABLE IF NOT EXISTS mypump_equipo_requisitos (
  catalogo_slug  TEXT        PRIMARY KEY,
  requiere       TEXT[]      NOT NULL DEFAULT '{}' CHECK (requiere <@ mypump_gimnasio_tipos()),
  alternativas   TEXT[]      NOT NULL DEFAULT '{}' CHECK (alternativas <@ mypump_gimnasio_tipos()),
  sin_codigo     BOOLEAN     NOT NULL DEFAULT FALSE,
  revisado_por   TEXT,
  actualizado_en TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Las cuentas abiertas mientras `gimnasio_para_todos` esté en false (piloto y tandas).
CREATE TABLE IF NOT EXISTS mypump_gimnasio_habilitados (
  cliente_id    TEXT        PRIMARY KEY,
  motivo        TEXT,
  habilitado_en TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- En este proyecto las tablas nuevas heredan permisos por defecto para anon y authenticated, incluido TRUNCATE, que RLS no
-- frena. Se sacan todos y se dan solo estos. anon, nada.
REVOKE ALL ON mypump_gimnasio, mypump_gimnasio_fotos, mypump_equipo_requisitos, mypump_gimnasio_habilitados FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON mypump_gimnasio, mypump_gimnasio_fotos, mypump_equipo_requisitos, mypump_gimnasio_habilitados TO service_role;
GRANT SELECT ON mypump_gimnasio, mypump_gimnasio_fotos, mypump_equipo_requisitos, mypump_gimnasio_habilitados TO authenticated;   -- el coach solo lee

ALTER TABLE mypump_gimnasio ENABLE ROW LEVEL SECURITY;
ALTER TABLE mypump_gimnasio_fotos ENABLE ROW LEVEL SECURITY;
ALTER TABLE mypump_equipo_requisitos ENABLE ROW LEVEL SECURITY;
ALTER TABLE mypump_gimnasio_habilitados ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "coach lee mypump_gimnasio" ON mypump_gimnasio;
DROP POLICY IF EXISTS "coach lee mypump_gimnasio_fotos" ON mypump_gimnasio_fotos;
DROP POLICY IF EXISTS "coach lee mypump_equipo_requisitos" ON mypump_equipo_requisitos;
DROP POLICY IF EXISTS "coach lee mypump_gimnasio_habilitados" ON mypump_gimnasio_habilitados;
CREATE POLICY "coach lee mypump_gimnasio" ON mypump_gimnasio FOR SELECT USING (auth.role() = 'authenticated');
CREATE POLICY "coach lee mypump_gimnasio_fotos" ON mypump_gimnasio_fotos FOR SELECT USING (auth.role() = 'authenticated');
CREATE POLICY "coach lee mypump_equipo_requisitos" ON mypump_equipo_requisitos FOR SELECT USING (auth.role() = 'authenticated');
CREATE POLICY "coach lee mypump_gimnasio_habilitados" ON mypump_gimnasio_habilitados FOR SELECT USING (auth.role() = 'authenticated');

-- ── Palanca: apagada ──
INSERT INTO mypump_app_config (clave, valor, nota) VALUES
  ('gimnasio_fotos', 'false'::JSONB, 'Gimnasio por fotos. true = abierto a mypump_gimnasio_habilitados'),
  ('gimnasio_para_todos', 'false'::JSONB, 'Gimnasio por fotos. true = abierto a todos, sin mirar mypump_gimnasio_habilitados')
ON CONFLICT (clave) DO NOTHING;

CREATE OR REPLACE FUNCTION mypump_gimnasio_habilitado(p_cliente_id TEXT)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE((SELECT valor = 'true'::JSONB FROM mypump_app_config WHERE clave = 'gimnasio_fotos'), FALSE)
     AND (COALESCE((SELECT valor = 'true'::JSONB FROM mypump_app_config WHERE clave = 'gimnasio_para_todos'), FALSE)
          OR EXISTS (SELECT 1 FROM mypump_gimnasio_habilitados WHERE cliente_id = p_cliente_id));
$$;

-- ── Lo que ve el alumno de una carga. Sin paths, sin cobertura, sin confianza ──
CREATE OR REPLACE FUNCTION mypump_gimnasio_vista_alumno(r mypump_gimnasio)
RETURNS JSONB
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT jsonb_build_object(
    'id', r.id,
    'version', r.version,
    -- Un error interno es trabajo nuestro: el alumno sigue viendo «Recibido».
    'estado', CASE WHEN r.estado = 'error' THEN 'enviado' ELSE r.estado END,
    'modo', r.modo,
    'zonas_no_hay', to_jsonb(r.zonas_no_hay),
    'nota_alumno', r.nota_alumno,
    'enviado_en', r.enviado_en,
    'resultado', CASE WHEN r.estado IN ('listo','reemplazado') THEN r.resultado END,
    'publicado_en', CASE WHEN r.estado IN ('listo','reemplazado') THEN r.publicado_en END,
    'preguntas', CASE WHEN r.estado = 'a_confirmar' THEN r.preguntas ELSE '[]'::JSONB END,
    'fotos', COALESCE((SELECT jsonb_agg(jsonb_build_object('id', f.id, 'zona', f.zona, 'ronda', f.ronda) ORDER BY f.creado_en, f.id)
                       FROM mypump_gimnasio_fotos f WHERE f.gimnasio_id = r.id AND NOT f.descartada), '[]'::JSONB),
    'zonas_faltantes', CASE WHEN r.estado = 'borrador' AND r.modo = 'completa' THEN
        COALESCE((SELECT jsonb_agg(z ORDER BY o) FROM unnest(mypump_gimnasio_zonas()) WITH ORDINALITY AS t(z, o)
                  WHERE z <> 'otros' AND NOT z = ANY (r.zonas_no_hay)
                    AND NOT EXISTS (SELECT 1 FROM mypump_gimnasio_fotos f WHERE f.gimnasio_id = r.id AND f.zona = z AND NOT f.descartada)), '[]'::JSONB)
      ELSE '[]'::JSONB END,
    'equipos', CASE WHEN r.estado = 'listo' THEN
        COALESCE((SELECT jsonb_agg(jsonb_build_object('tipo', e->>'tipo', 'zona', e->>'zona', 'cantidad', COALESCE((e->>'cantidad')::INTEGER, 1)))
                  FROM jsonb_array_elements(COALESCE(r.inventario->'equipos', '[]'::JSONB)) e
                  WHERE COALESCE(e->>'estado', 'confirmado') = 'confirmado'), '[]'::JSONB)
      ELSE '[]'::JSONB END
  );
$$;

-- ── La app, por token (anon y authenticated). NULL = token caído ──
CREATE OR REPLACE FUNCTION mypump_gimnasio_get(p_token TEXT)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_cliente_id TEXT;
  v_abierta    mypump_gimnasio%ROWTYPE;
  v_vigente    mypump_gimnasio%ROWTYPE;
BEGIN
  v_cliente_id := mypump_get_cliente_id_from_token(p_token);
  IF v_cliente_id IS NULL THEN RETURN NULL; END IF;
  IF NOT mypump_gimnasio_habilitado(v_cliente_id) THEN RETURN jsonb_build_object('habilitado', FALSE); END IF;
  SELECT * INTO v_abierta FROM mypump_gimnasio WHERE cliente_id = v_cliente_id AND estado NOT IN ('listo','reemplazado');
  SELECT * INTO v_vigente FROM mypump_gimnasio WHERE cliente_id = v_cliente_id AND estado = 'listo';
  RETURN jsonb_build_object(
    'habilitado', TRUE,
    'consentimiento_version', mypump_gimnasio_consentimiento_vigente(),
    'consentimiento_aceptado', EXISTS (SELECT 1 FROM mypump_gimnasio WHERE cliente_id = v_cliente_id AND consentimiento_texto_version = mypump_gimnasio_consentimiento_vigente()),
    'abierta', CASE WHEN v_abierta.id IS NULL THEN NULL ELSE mypump_gimnasio_vista_alumno(v_abierta) END,
    'vigente', CASE WHEN v_vigente.id IS NULL THEN NULL ELSE mypump_gimnasio_vista_alumno(v_vigente) END
  );
END;
$$;

-- Abre una carga, o devuelve la que ya estaba abierta (`ya`). `p_modo` 'parcial' necesita un gimnasio vigente.
CREATE OR REPLACE FUNCTION mypump_gimnasio_nuevo(p_token TEXT, p_modo TEXT DEFAULT 'completa')
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_cliente_id TEXT;
  v_fila       mypump_gimnasio%ROWTYPE;
  v_base       UUID;
BEGIN
  v_cliente_id := mypump_get_cliente_id_from_token(p_token);
  IF v_cliente_id IS NULL THEN RETURN NULL; END IF;
  IF NOT mypump_gimnasio_habilitado(v_cliente_id) THEN RETURN jsonb_build_object('ok', FALSE, 'error', 'no_habilitado'); END IF;
  IF p_modo IS NULL OR p_modo NOT IN ('completa','parcial') THEN RAISE EXCEPTION 'modo inválido' USING ERRCODE = '22023'; END IF;

  SELECT * INTO v_fila FROM mypump_gimnasio WHERE cliente_id = v_cliente_id AND estado NOT IN ('listo','reemplazado');
  IF FOUND THEN RETURN jsonb_build_object('ok', TRUE, 'ya', TRUE, 'id', v_fila.id, 'version', v_fila.version, 'estado', v_fila.estado); END IF;

  IF p_modo = 'parcial' THEN
    SELECT id INTO v_base FROM mypump_gimnasio WHERE cliente_id = v_cliente_id AND estado = 'listo';
    IF v_base IS NULL THEN RETURN jsonb_build_object('ok', FALSE, 'error', 'sin_gimnasio_vigente'); END IF;
  END IF;

  -- Dos pedidos a la vez: el segundo espera a este por el índice único y cae en la excepción.
  BEGIN
    INSERT INTO mypump_gimnasio (cliente_id, version, modo, base_id)
    VALUES (v_cliente_id, COALESCE((SELECT MAX(version) FROM mypump_gimnasio WHERE cliente_id = v_cliente_id), 0) + 1, p_modo, v_base)
    RETURNING * INTO v_fila;
  EXCEPTION WHEN unique_violation THEN
    SELECT * INTO v_fila FROM mypump_gimnasio WHERE cliente_id = v_cliente_id AND estado NOT IN ('listo','reemplazado');
    IF NOT FOUND THEN RETURN jsonb_build_object('ok', FALSE, 'error', 'reintentar'); END IF;
    RETURN jsonb_build_object('ok', TRUE, 'ya', TRUE, 'id', v_fila.id, 'version', v_fila.version, 'estado', v_fila.estado);
  END;
  RETURN jsonb_build_object('ok', TRUE, 'ya', FALSE, 'id', v_fila.id, 'version', v_fila.version, 'estado', v_fila.estado);
END;
$$;

-- Pasa a `enviado`. Idempotente. El servidor fija `momento` y revisa que estén todas las zonas.
CREATE OR REPLACE FUNCTION mypump_gimnasio_enviar(
  p_token           TEXT,
  p_id              UUID,
  p_no_hay          TEXT[],
  p_nota            TEXT,
  p_consentimiento  TEXT,
  p_quitar          TEXT[] DEFAULT '{}'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_cliente_id TEXT;
  v_fila       mypump_gimnasio%ROWTYPE;
  v_no_hay     TEXT[];
  v_quitar     TEXT[] := COALESCE(p_quitar, '{}');
  v_faltan     TEXT[];
  v_fotos      INTEGER;
BEGIN
  v_cliente_id := mypump_get_cliente_id_from_token(p_token);
  IF v_cliente_id IS NULL THEN RETURN NULL; END IF;
  SELECT * INTO v_fila FROM mypump_gimnasio WHERE id = p_id AND cliente_id = v_cliente_id FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', FALSE, 'error', 'no_encontrado'); END IF;
  IF v_fila.estado <> 'borrador' THEN
    RETURN jsonb_build_object('ok', TRUE, 'ya', TRUE, 'estado', CASE WHEN v_fila.estado = 'error' THEN 'enviado' ELSE v_fila.estado END);
  END IF;
  IF NOT mypump_gimnasio_habilitado(v_cliente_id) THEN RETURN jsonb_build_object('ok', FALSE, 'error', 'no_habilitado'); END IF;
  IF p_consentimiento IS DISTINCT FROM mypump_gimnasio_consentimiento_vigente() THEN
    RETURN jsonb_build_object('ok', FALSE, 'error', 'sin_consentimiento');
  END IF;
  IF NOT (COALESCE(p_no_hay, '{}') <@ mypump_gimnasio_zonas()) OR NOT (v_quitar <@ mypump_gimnasio_tipos()) THEN
    RAISE EXCEPTION 'zona o tipo inválido' USING ERRCODE = '22023';
  END IF;

  -- «No hay» es la única falta segura: una zona con fotos no puede quedar marcada así.
  SELECT COALESCE(array_agg(DISTINCT z), '{}') INTO v_no_hay FROM unnest(COALESCE(p_no_hay, '{}')) z
   WHERE NOT EXISTS (SELECT 1 FROM mypump_gimnasio_fotos f WHERE f.gimnasio_id = p_id AND f.zona = z AND NOT f.descartada);
  SELECT count(*) INTO v_fotos FROM mypump_gimnasio_fotos f WHERE f.gimnasio_id = p_id AND NOT f.descartada;

  IF v_fila.modo = 'completa' THEN
    IF cardinality(v_quitar) > 0 THEN RETURN jsonb_build_object('ok', FALSE, 'error', 'quitar_solo_parcial'); END IF;
    SELECT COALESCE(array_agg(z ORDER BY o), '{}') INTO v_faltan FROM unnest(mypump_gimnasio_zonas()) WITH ORDINALITY AS t(z, o)
     WHERE z <> 'otros' AND NOT z = ANY (v_no_hay)
       AND NOT EXISTS (SELECT 1 FROM mypump_gimnasio_fotos f WHERE f.gimnasio_id = p_id AND f.zona = z AND NOT f.descartada);
    IF cardinality(v_faltan) > 0 THEN RETURN jsonb_build_object('ok', FALSE, 'error', 'faltan_zonas', 'faltan', to_jsonb(v_faltan)); END IF;
  ELSIF v_fotos = 0 AND cardinality(v_quitar) = 0 THEN
    RETURN jsonb_build_object('ok', FALSE, 'error', 'sin_novedad');
  END IF;

  UPDATE mypump_gimnasio SET
    estado = 'enviado',
    momento = CASE WHEN EXISTS (SELECT 1 FROM mypump_rutinas r WHERE r.cliente_id = v_cliente_id AND r.estado = 'activa') THEN 'con_plan' ELSE 'pre_entrega' END,
    zonas_no_hay = v_no_hay,
    quitar = v_quitar,
    nota_alumno = NULLIF(left(btrim(regexp_replace(COALESCE(p_nota, ''), '[[:cntrl:]]+', ' ', 'g')), 300), ''),
    consentimiento_en = NOW(),
    consentimiento_texto_version = p_consentimiento,
    enviado_en = NOW(),
    actualizado_en = NOW()
  WHERE id = p_id;
  RETURN jsonb_build_object('ok', TRUE, 'ya', FALSE, 'estado', 'enviado');
END;
$$;

-- La respuesta a la ronda única. Puede venir incompleta: lo que no contestó sigue dudoso y lo ve EDITOR.
CREATE OR REPLACE FUNCTION mypump_gimnasio_responder(p_token TEXT, p_id UUID, p_respuestas JSONB)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_cliente_id TEXT;
  v_fila       mypump_gimnasio%ROWTYPE;
  v_validas    JSONB;
BEGIN
  v_cliente_id := mypump_get_cliente_id_from_token(p_token);
  IF v_cliente_id IS NULL THEN RETURN NULL; END IF;
  IF p_respuestas IS NULL OR jsonb_typeof(p_respuestas) <> 'object' OR pg_column_size(p_respuestas) > 16384 THEN
    RAISE EXCEPTION 'respuestas inválidas' USING ERRCODE = '22023';
  END IF;
  SELECT * INTO v_fila FROM mypump_gimnasio WHERE id = p_id AND cliente_id = v_cliente_id FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', FALSE, 'error', 'no_encontrado'); END IF;
  IF v_fila.estado <> 'a_confirmar' THEN
    IF v_fila.respondido_en IS NOT NULL THEN RETURN jsonb_build_object('ok', TRUE, 'ya', TRUE, 'estado', CASE WHEN v_fila.estado = 'error' THEN 'enviado' ELSE v_fila.estado END); END IF;
    RETURN jsonb_build_object('ok', FALSE, 'error', 'estado_invalido');
  END IF;
  -- Solo las preguntas que se hicieron: una clave inventada no se guarda.
  SELECT COALESCE(jsonb_object_agg(k, v), '{}'::JSONB) INTO v_validas
    FROM jsonb_each(p_respuestas) AS t(k, v)
   WHERE EXISTS (SELECT 1 FROM jsonb_array_elements(v_fila.preguntas) p WHERE p->>'id' = k);
  UPDATE mypump_gimnasio SET estado = 'respondido', respuestas = v_validas, respondido_en = NOW(), intentos = 0, actualizado_en = NOW() WHERE id = p_id;
  RETURN jsonb_build_object('ok', TRUE, 'ya', FALSE, 'estado', 'respondido');
END;
$$;

REVOKE ALL ON FUNCTION mypump_gimnasio_habilitado(TEXT), mypump_gimnasio_vista_alumno(mypump_gimnasio) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION mypump_gimnasio_habilitado(TEXT), mypump_gimnasio_vista_alumno(mypump_gimnasio) TO service_role;
REVOKE ALL ON FUNCTION mypump_gimnasio_get(TEXT), mypump_gimnasio_nuevo(TEXT, TEXT), mypump_gimnasio_enviar(TEXT, UUID, TEXT[], TEXT, TEXT, TEXT[]), mypump_gimnasio_responder(TEXT, UUID, JSONB) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION mypump_gimnasio_get(TEXT), mypump_gimnasio_nuevo(TEXT, TEXT), mypump_gimnasio_enviar(TEXT, UUID, TEXT[], TEXT, TEXT, TEXT[]), mypump_gimnasio_responder(TEXT, UUID, JSONB) TO anon, authenticated, service_role;

-- ── Mini-vision (service_role) ──
-- Antes de procesar una foto y otra vez, con la carga trabada, al registrarla. 'ok', 'ya', 'no_encontrado', 'ajena', 'estado', 'tope', 'no_habilitado'.
CREATE OR REPLACE FUNCTION mypump_gimnasio_foto_puede(p_cliente_id TEXT, p_gimnasio_id UUID, p_foto_id UUID)
RETURNS TEXT
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_fila  mypump_gimnasio%ROWTYPE;
  v_ajena UUID;
  v_n     INTEGER;
BEGIN
  SELECT * INTO v_fila FROM mypump_gimnasio WHERE id = p_gimnasio_id AND cliente_id = p_cliente_id;
  IF NOT FOUND THEN RETURN 'no_encontrado'; END IF;
  SELECT gimnasio_id INTO v_ajena FROM mypump_gimnasio_fotos WHERE id = p_foto_id;
  IF v_ajena = p_gimnasio_id THEN RETURN 'ya'; END IF;
  IF v_ajena IS NOT NULL THEN RETURN 'ajena'; END IF;
  IF NOT mypump_gimnasio_habilitado(p_cliente_id) THEN RETURN 'no_habilitado'; END IF;
  IF v_fila.estado = 'borrador' THEN
    SELECT count(*) INTO v_n FROM mypump_gimnasio_fotos WHERE gimnasio_id = p_gimnasio_id AND ronda = 0;
    RETURN CASE WHEN v_n >= 80 THEN 'tope' ELSE 'ok' END;
  END IF;
  IF v_fila.estado = 'a_confirmar' AND EXISTS (SELECT 1 FROM jsonb_array_elements(v_fila.preguntas) p WHERE p->>'clase' = 'foto') THEN
    SELECT count(*) INTO v_n FROM mypump_gimnasio_fotos WHERE gimnasio_id = p_gimnasio_id AND ronda = 1;
    RETURN CASE WHEN v_n >= 9 THEN 'tope' ELSE 'ok' END;
  END IF;
  RETURN 'estado';
END;
$$;

CREATE OR REPLACE FUNCTION mypump_gimnasio_foto_registrar(
  p_cliente_id TEXT, p_gimnasio_id UUID, p_foto_id UUID, p_zona TEXT, p_path TEXT, p_bytes INTEGER, p_caras INTEGER, p_borde_blanco REAL
)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_estado TEXT;
  v_puede  TEXT;
BEGIN
  SELECT estado INTO v_estado FROM mypump_gimnasio WHERE id = p_gimnasio_id AND cliente_id = p_cliente_id FOR UPDATE;
  IF NOT FOUND THEN RETURN 'no_encontrado'; END IF;
  v_puede := mypump_gimnasio_foto_puede(p_cliente_id, p_gimnasio_id, p_foto_id);
  IF v_puede <> 'ok' THEN RETURN v_puede; END IF;
  INSERT INTO mypump_gimnasio_fotos (id, gimnasio_id, cliente_id, zona, ronda, path, bytes, caras_tapadas, borde_blanco)
  VALUES (p_foto_id, p_gimnasio_id, p_cliente_id, p_zona, CASE WHEN v_estado = 'borrador' THEN 0 ELSE 1 END, p_path, p_bytes, p_caras, p_borde_blanco);
  RETURN 'ok';
END;
$$;

-- Borra el registro y devuelve el path para sacar el objeto. Solo mientras la foto se puede cambiar.
CREATE OR REPLACE FUNCTION mypump_gimnasio_foto_borrar(p_cliente_id TEXT, p_foto_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_gim   UUID;
  v_ronda INTEGER;
  v_path  TEXT;
  v_estado TEXT;
BEGIN
  SELECT gimnasio_id INTO v_gim FROM mypump_gimnasio_fotos WHERE id = p_foto_id AND cliente_id = p_cliente_id;
  IF v_gim IS NULL THEN RETURN jsonb_build_object('resultado', 'no_encontrado'); END IF;
  SELECT estado INTO v_estado FROM mypump_gimnasio WHERE id = v_gim FOR UPDATE;
  SELECT ronda, path INTO v_ronda, v_path FROM mypump_gimnasio_fotos WHERE id = p_foto_id;
  IF v_path IS NULL THEN RETURN jsonb_build_object('resultado', 'no_encontrado'); END IF;
  IF NOT (v_estado = 'borrador' OR (v_estado = 'a_confirmar' AND v_ronda = 1)) THEN RETURN jsonb_build_object('resultado', 'estado'); END IF;
  DELETE FROM mypump_gimnasio_fotos WHERE id = p_foto_id;
  RETURN jsonb_build_object('resultado', 'ok', 'path', v_path);
END;
$$;

REVOKE ALL ON FUNCTION mypump_gimnasio_foto_puede(TEXT, UUID, UUID), mypump_gimnasio_foto_registrar(TEXT, UUID, UUID, TEXT, TEXT, INTEGER, INTEGER, REAL), mypump_gimnasio_foto_borrar(TEXT, UUID) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION mypump_gimnasio_foto_puede(TEXT, UUID, UUID), mypump_gimnasio_foto_registrar(TEXT, UUID, UUID, TEXT, TEXT, INTEGER, INTEGER, REAL), mypump_gimnasio_foto_borrar(TEXT, UUID) TO service_role;

-- ── El worker (service_role) ──
-- Toma UNA fila. Devuelve la carga con todas sus fotos, o NULL si no hay nada.
CREATE OR REPLACE FUNCTION mypump_gimnasio_tomar()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_fila mypump_gimnasio%ROWTYPE;
  v_fase TEXT;
BEGIN
  SELECT * INTO v_fila FROM mypump_gimnasio WHERE estado IN ('enviado','respondido')
   ORDER BY COALESCE(respondido_en, enviado_en), id LIMIT 1 FOR UPDATE SKIP LOCKED;
  IF NOT FOUND THEN RETURN NULL; END IF;
  v_fase := v_fila.estado;
  UPDATE mypump_gimnasio SET estado = 'procesando', procesando_desde = NOW(), intentos = intentos + 1, actualizado_en = NOW() WHERE id = v_fila.id RETURNING * INTO v_fila;
  RETURN to_jsonb(v_fila) || jsonb_build_object('fase', v_fase, 'fotos',
    COALESCE((SELECT jsonb_agg(to_jsonb(f) ORDER BY f.creado_en, f.id) FROM mypump_gimnasio_fotos f WHERE f.gimnasio_id = v_fila.id), '[]'::JSONB));
END;
$$;

-- Devuelve la fila a la cola. `p_contar` FALSE: se frenó por cuota, no fue culpa de la fila y no gasta un intento.
CREATE OR REPLACE FUNCTION mypump_gimnasio_devolver(p_id UUID, p_contar BOOLEAN DEFAULT TRUE, p_detalle TEXT DEFAULT NULL)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  UPDATE mypump_gimnasio SET
    estado = CASE WHEN respondido_en IS NULL THEN 'enviado' ELSE 'respondido' END,
    procesando_desde = NULL,
    intentos = CASE WHEN p_contar THEN intentos ELSE GREATEST(intentos - 1, 0) END,
    error_detalle = COALESCE(left(p_detalle, 500), error_detalle),
    actualizado_en = NOW()
  WHERE id = p_id AND estado = 'procesando'
  RETURNING TRUE;
$$;

-- Lo que quedó en `procesando` porque el worker se cayó: vuelve a la cola, o a `error` si ya se intentó de más.
CREATE OR REPLACE FUNCTION mypump_gimnasio_liberar_colgadas(p_minutos INTEGER DEFAULT 60, p_max_intentos INTEGER DEFAULT 3)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_n INTEGER;
BEGIN
  WITH t AS (
    UPDATE mypump_gimnasio SET
      estado = CASE WHEN intentos >= p_max_intentos THEN 'error' WHEN respondido_en IS NULL THEN 'enviado' ELSE 'respondido' END,
      error_detalle = CASE WHEN intentos >= p_max_intentos THEN 'quedó colgada en procesando' ELSE error_detalle END,
      procesando_desde = NULL, actualizado_en = NOW()
    WHERE estado = 'procesando' AND procesando_desde < NOW() - make_interval(mins => p_minutos)
    RETURNING 1)
  SELECT count(*) INTO v_n FROM t;
  RETURN v_n;
END;
$$;

-- El resultado del worker. Solo desde `procesando`. `a_confirmar` una sola vez: máximo una ronda.
CREATE OR REPLACE FUNCTION mypump_gimnasio_guardar(
  p_id             UUID,
  p_estado         TEXT,
  p_inventario     JSONB,
  p_cobertura      JSONB DEFAULT NULL,
  p_preguntas      JSONB DEFAULT '[]'::JSONB,
  p_publicar_desde TIMESTAMPTZ DEFAULT NULL,
  p_publicar_hasta TIMESTAMPTZ DEFAULT NULL,
  p_error          TEXT DEFAULT NULL,
  p_descartes      JSONB DEFAULT '[]'::JSONB
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_fila mypump_gimnasio%ROWTYPE;
BEGIN
  IF p_estado NOT IN ('a_confirmar','a_revisar','en_editor','error') THEN RAISE EXCEPTION 'estado inválido' USING ERRCODE = '22023'; END IF;
  IF p_preguntas IS NULL OR jsonb_typeof(p_preguntas) <> 'array' OR p_descartes IS NULL OR jsonb_typeof(p_descartes) <> 'array' THEN RAISE EXCEPTION 'forma inválida' USING ERRCODE = '22023'; END IF;
  SELECT * INTO v_fila FROM mypump_gimnasio WHERE id = p_id FOR UPDATE;
  IF NOT FOUND OR v_fila.estado <> 'procesando' THEN RETURN FALSE; END IF;
  IF p_estado = 'a_confirmar' AND (v_fila.respondido_en IS NOT NULL OR jsonb_array_length(p_preguntas) = 0) THEN
    RAISE EXCEPTION 'una sola ronda, y con preguntas' USING ERRCODE = '22023';
  END IF;
  UPDATE mypump_gimnasio_fotos f SET descartada = TRUE, motivo_descarte = left(d->>'motivo', 200)
    FROM jsonb_array_elements(p_descartes) d WHERE f.gimnasio_id = p_id AND f.id = (d->>'foto')::UUID;
  UPDATE mypump_gimnasio SET
    estado = p_estado,
    inventario = COALESCE(p_inventario, inventario),
    cobertura = p_cobertura,
    preguntas = CASE WHEN p_estado = 'a_confirmar' THEN p_preguntas ELSE preguntas END,
    publicar_desde = p_publicar_desde,
    publicar_hasta = p_publicar_hasta,
    error_detalle = left(p_error, 500),
    procesado_en = NOW(),
    procesando_desde = NULL,
    intentos = 0,
    actualizado_en = NOW()
  WHERE id = p_id;
  RETURN TRUE;
END;
$$;

-- Nadie contestó en este plazo: sigue el camino con lo que haya, y lo no contestado llega dudoso a EDITOR.
CREATE OR REPLACE FUNCTION mypump_gimnasio_vencer_confirmaciones(p_horas INTEGER DEFAULT 72)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_n INTEGER;
BEGIN
  WITH t AS (
    UPDATE mypump_gimnasio SET estado = 'respondido', respondido_en = NOW(), intentos = 0, actualizado_en = NOW()
    WHERE estado = 'a_confirmar' AND procesado_en < NOW() - make_interval(hours => p_horas)
    RETURNING 1)
  SELECT count(*) INTO v_n FROM t;
  RETURN v_n;
END;
$$;

-- ── EDITOR y AUTOMATIZAR (service_role) ──
-- La carga abierta y el gimnasio vigente, completos.
CREATE OR REPLACE FUNCTION mypump_gimnasio_servicio(p_cliente_id TEXT)
RETURNS JSONB
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT jsonb_build_object(
    'abierta', (SELECT to_jsonb(g) || jsonb_build_object('fotos', COALESCE((SELECT jsonb_agg(to_jsonb(f) ORDER BY f.creado_en, f.id) FROM mypump_gimnasio_fotos f WHERE f.gimnasio_id = g.id), '[]'::JSONB))
                FROM mypump_gimnasio g WHERE g.cliente_id = p_cliente_id AND g.estado NOT IN ('listo','reemplazado')),
    'vigente', (SELECT to_jsonb(g) || jsonb_build_object('fotos', COALESCE((SELECT jsonb_agg(to_jsonb(f) ORDER BY f.creado_en, f.id) FROM mypump_gimnasio_fotos f WHERE f.gimnasio_id = g.id), '[]'::JSONB))
                FROM mypump_gimnasio g WHERE g.cliente_id = p_cliente_id AND g.estado = 'listo')
  );
$$;

-- Cierra con el OK humano. El gimnasio anterior sigue vigente hasta este momento. Con plan, nunca antes de `publicar_desde`.
CREATE OR REPLACE FUNCTION mypump_gimnasio_cerrar(p_id UUID, p_resultado TEXT, p_aprobado_por TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_fila mypump_gimnasio%ROWTYPE;
BEGIN
  IF p_resultado IS NULL OR p_resultado NOT IN ('sin_cambios','adaptada','plan_nuevo') OR length(btrim(COALESCE(p_aprobado_por, ''))) = 0 THEN
    RAISE EXCEPTION 'resultado o aprobación inválidos' USING ERRCODE = '22023';
  END IF;
  SELECT * INTO v_fila FROM mypump_gimnasio WHERE id = p_id FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', FALSE, 'error', 'no_encontrado'); END IF;
  IF v_fila.estado = 'listo' THEN RETURN jsonb_build_object('ok', TRUE, 'ya', TRUE); END IF;
  IF v_fila.estado NOT IN ('a_revisar','en_editor') THEN RETURN jsonb_build_object('ok', FALSE, 'error', 'estado_invalido'); END IF;
  IF v_fila.momento = 'con_plan' AND v_fila.publicar_desde IS NOT NULL AND NOW() < v_fila.publicar_desde THEN
    RETURN jsonb_build_object('ok', FALSE, 'error', 'antes_de_la_ventana', 'publicar_desde', v_fila.publicar_desde);
  END IF;
  UPDATE mypump_gimnasio SET estado = 'reemplazado', actualizado_en = NOW() WHERE cliente_id = v_fila.cliente_id AND estado = 'listo';
  UPDATE mypump_gimnasio SET estado = 'listo', resultado = p_resultado, aprobado_por = btrim(p_aprobado_por), aprobado_en = NOW(), publicado_en = NOW(), actualizado_en = NOW() WHERE id = p_id;
  RETURN jsonb_build_object('ok', TRUE, 'ya', FALSE);
END;
$$;

CREATE OR REPLACE FUNCTION mypump_gimnasio_avisado(p_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  UPDATE mypump_gimnasio SET avisado_en = COALESCE(avisado_en, NOW()), actualizado_en = NOW() WHERE id = p_id AND estado = 'listo' RETURNING TRUE;
$$;

-- Las fotos se borran a los 90 días de cerrar la carga, por carpeta (también lo que haya quedado sin fila); el inventario queda.
CREATE OR REPLACE FUNCTION mypump_gimnasio_para_limpiar(p_dias INTEGER DEFAULT 90, p_limite INTEGER DEFAULT 20)
RETURNS JSONB
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(jsonb_agg(jsonb_build_object('id', g.id, 'cliente_id', g.cliente_id)), '[]'::JSONB)
  FROM (SELECT id, cliente_id FROM mypump_gimnasio
        WHERE estado IN ('listo','reemplazado') AND fotos_borradas_en IS NULL AND aprobado_en < NOW() - make_interval(days => p_dias)
        ORDER BY aprobado_en LIMIT p_limite) g;
$$;

CREATE OR REPLACE FUNCTION mypump_gimnasio_limpieza_hecha(p_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  DELETE FROM mypump_gimnasio_fotos WHERE gimnasio_id = p_id;
  UPDATE mypump_gimnasio SET fotos_borradas_en = NOW(), actualizado_en = NOW() WHERE id = p_id AND estado IN ('listo','reemplazado');
  RETURN FOUND;
END;
$$;

REVOKE ALL ON FUNCTION
  mypump_gimnasio_tomar(), mypump_gimnasio_devolver(UUID, BOOLEAN, TEXT), mypump_gimnasio_liberar_colgadas(INTEGER, INTEGER),
  mypump_gimnasio_guardar(UUID, TEXT, JSONB, JSONB, JSONB, TIMESTAMPTZ, TIMESTAMPTZ, TEXT, JSONB), mypump_gimnasio_vencer_confirmaciones(INTEGER),
  mypump_gimnasio_servicio(TEXT), mypump_gimnasio_cerrar(UUID, TEXT, TEXT), mypump_gimnasio_avisado(UUID),
  mypump_gimnasio_para_limpiar(INTEGER, INTEGER), mypump_gimnasio_limpieza_hecha(UUID)
FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION
  mypump_gimnasio_tomar(), mypump_gimnasio_devolver(UUID, BOOLEAN, TEXT), mypump_gimnasio_liberar_colgadas(INTEGER, INTEGER),
  mypump_gimnasio_guardar(UUID, TEXT, JSONB, JSONB, JSONB, TIMESTAMPTZ, TIMESTAMPTZ, TEXT, JSONB), mypump_gimnasio_vencer_confirmaciones(INTEGER),
  mypump_gimnasio_servicio(TEXT), mypump_gimnasio_cerrar(UUID, TEXT, TEXT), mypump_gimnasio_avisado(UUID),
  mypump_gimnasio_para_limpiar(INTEGER, INTEGER), mypump_gimnasio_limpieza_hecha(UUID)
TO service_role;

COMMIT;

-- Abrir el piloto, a mano y sin dejar ids en el repo:
--   INSERT INTO mypump_gimnasio_habilitados (cliente_id, motivo) VALUES ('<cliente_id>', 'piloto') ON CONFLICT DO NOTHING;
--   UPDATE mypump_app_config SET valor = 'true', actualizado_en = NOW() WHERE clave = 'gimnasio_fotos';
