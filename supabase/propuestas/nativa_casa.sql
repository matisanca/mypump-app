-- nativa_casa.sql — PROPUESTA, SIN APLICAR. Para aplicar hace falta el OK de Mati (compuerta G2).
-- VA DESPUÉS de nativa_gimnasio_fotos.sql: es una excepción dentro de «Mi gimnasio» y usa sus tablas.
--
-- «Entreno en casa» (app 2.3.0 y web): un interruptor en Mi gimnasio para quien entrena en su casa. En vez de las
-- fotos por zona, marca lo que tiene de una lista corta. Reemplaza la pregunta «material en casa» del formulario.
-- Palanca `casa`, APAGADA. Además hace falta `gimnasio_fotos` y que el alumno tenga Mi gimnasio habilitado.
--
-- Decisiones:
--   · Es la misma carga de `mypump_gimnasio`, con `lugar = 'casa'`: una sola carga abierta y un solo lugar vigente por
--     alumno, con las mismas versiones, el mismo OK humano (`mypump_gimnasio_cerrar`) y la misma lectura de EDITOR y
--     Entregas (`mypump_gimnasio_servicio`, que ya devuelve la fila entera: trae `lugar` y `casa`).
--   · No pasa por el worker de fotos: lo que marca el alumno ya es un dato cerrado. Sale directo a `a_revisar`, con el
--     inventario armado con los mismos códigos de equipo (`estado: 'confirmado'`, `zona: 'casa'`).
--   · No se cambia ninguna función de nativa_gimnasio_fotos.sql: lo de casa viaja por tres funciones propias. El
--     reverso es borrar esas funciones y las dos columnas.
--   · La lista de equipo la sirve el servidor (con su nombre), para que las tres plataformas no la dupliquen.
--   · Las fotos son opcionales y entran por el mismo `/gimnasio/upload`, con zona `otros`.
BEGIN;

INSERT INTO mypump_app_config (clave, valor, nota) VALUES
  ('casa', 'false'::JSONB, 'Entreno en casa (2.3.0): interruptor en Mi gimnasio. true = prendida. Necesita gimnasio_fotos')
ON CONFLICT (clave) DO NOTHING;

-- Lo que se puede marcar, en orden. `kg` = pide hasta cuántos kilos. Los códigos que existen en
-- `mypump_gimnasio_tipos()` son los mismos; `bandas_elasticas`, `trx` y `mancuernas_regulables` son solo de casa.
CREATE OR REPLACE FUNCTION mypump_casa_tipos()
RETURNS JSONB
LANGUAGE sql
IMMUTABLE
SET search_path = public
AS $$
  SELECT '[
    {"tipo": "mancuernas", "nombre": "Mancuernas", "kg": true},
    {"tipo": "mancuernas_regulables", "nombre": "Mancuernas regulables", "kg": true},
    {"tipo": "barra_olimpica", "nombre": "Barra", "kg": false},
    {"tipo": "discos", "nombre": "Discos", "kg": true},
    {"tipo": "barra_z", "nombre": "Barra Z", "kg": false},
    {"tipo": "kettlebells", "nombre": "Pesas rusas", "kg": true},
    {"tipo": "banco_plano", "nombre": "Banco plano", "kg": false},
    {"tipo": "banco_regulable", "nombre": "Banco regulable", "kg": false},
    {"tipo": "rack_sentadilla", "nombre": "Soporte para sentadilla", "kg": false},
    {"tipo": "barra_dominadas", "nombre": "Barra de dominadas", "kg": false},
    {"tipo": "paralelas", "nombre": "Paralelas", "kg": false},
    {"tipo": "bandas_elasticas", "nombre": "Bandas elásticas", "kg": false},
    {"tipo": "trx", "nombre": "Correas de suspensión", "kg": false},
    {"tipo": "polea_ajustable", "nombre": "Polea", "kg": false},
    {"tipo": "cinta", "nombre": "Cinta para caminar o correr", "kg": false},
    {"tipo": "bici_fija", "nombre": "Bicicleta fija", "kg": false}
  ]'::JSONB;
$$;

ALTER TABLE mypump_gimnasio ADD COLUMN IF NOT EXISTS lugar TEXT NOT NULL DEFAULT 'gimnasio' CHECK (lugar IN ('gimnasio','casa'));
-- {"equipos": [{"tipo", "kg"?}], "sin_equipo": bool}. Solo con lugar = 'casa' y ya enviada.
ALTER TABLE mypump_gimnasio ADD COLUMN IF NOT EXISTS casa JSONB CHECK (casa IS NULL OR (lugar = 'casa' AND jsonb_typeof(casa) = 'object'));

CREATE OR REPLACE FUNCTION mypump_casa_habilitada(p_cliente_id TEXT)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE((SELECT valor = 'true'::JSONB FROM mypump_app_config WHERE clave = 'casa'), FALSE)
     AND mypump_gimnasio_habilitado(p_cliente_id);
$$;

-- Lo que ve el alumno de una carga, del lado de casa.
CREATE OR REPLACE FUNCTION mypump_casa_vista(r mypump_gimnasio)
RETURNS JSONB
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT jsonb_build_object(
    'id', r.id,
    'estado', CASE WHEN r.estado = 'error' THEN 'enviado' ELSE r.estado END,
    'lugar', r.lugar,
    'equipos', COALESCE(r.casa->'equipos', '[]'::JSONB),
    'sin_equipo', COALESCE((r.casa->>'sin_equipo')::BOOLEAN, FALSE),
    'nota', CASE WHEN r.lugar = 'casa' THEN r.nota_alumno END);
$$;

-- ── La app, por token (anon y authenticated). NULL = token caído ──
-- {habilitado, tipos, abierta, vigente}: `abierta` y `vigente` son las mismas cargas de `mypump_gimnasio_get`, con su lugar.
CREATE OR REPLACE FUNCTION mypump_casa_get(p_token TEXT)
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
  IF NOT mypump_casa_habilitada(v_cliente_id) THEN RETURN jsonb_build_object('habilitado', FALSE); END IF;
  SELECT * INTO v_abierta FROM mypump_gimnasio WHERE cliente_id = v_cliente_id AND estado NOT IN ('listo','reemplazado');
  SELECT * INTO v_vigente FROM mypump_gimnasio WHERE cliente_id = v_cliente_id AND estado = 'listo';
  RETURN jsonb_build_object(
    'habilitado', TRUE,
    'tipos', mypump_casa_tipos(),
    'abierta', CASE WHEN v_abierta.id IS NULL THEN NULL ELSE mypump_casa_vista(v_abierta) END,
    'vigente', CASE WHEN v_vigente.id IS NULL THEN NULL ELSE mypump_casa_vista(v_vigente) END);
END;
$$;

-- El interruptor. TRUE: abre una carga de casa, o pasa a casa el borrador que estaba. FALSE: el borrador vuelve a ser
-- de gimnasio. Una carga ya enviada no cambia de lugar (`en_curso`): hay que esperar a que quede lista.
CREATE OR REPLACE FUNCTION mypump_casa_elegir(p_token TEXT, p_casa BOOLEAN)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_cliente_id TEXT;
  v_fila       mypump_gimnasio%ROWTYPE;
  v_lugar      TEXT := CASE WHEN p_casa THEN 'casa' ELSE 'gimnasio' END;
BEGIN
  v_cliente_id := mypump_get_cliente_id_from_token(p_token);
  IF v_cliente_id IS NULL THEN RETURN NULL; END IF;
  IF p_casa IS NULL THEN RAISE EXCEPTION 'falta el lugar' USING ERRCODE = '22023'; END IF;
  IF NOT mypump_casa_habilitada(v_cliente_id) THEN RETURN jsonb_build_object('ok', FALSE, 'error', 'no_habilitado'); END IF;

  SELECT * INTO v_fila FROM mypump_gimnasio WHERE cliente_id = v_cliente_id AND estado NOT IN ('listo','reemplazado') FOR UPDATE;
  IF FOUND THEN
    IF v_fila.lugar = v_lugar THEN RETURN jsonb_build_object('ok', TRUE, 'ya', TRUE, 'id', v_fila.id, 'estado', CASE WHEN v_fila.estado = 'error' THEN 'enviado' ELSE v_fila.estado END, 'lugar', v_fila.lugar); END IF;
    IF v_fila.estado <> 'borrador' THEN RETURN jsonb_build_object('ok', FALSE, 'error', 'en_curso'); END IF;
    -- Solo cambia el lugar. `modo` y `base_id` no se tocan acá: si era un «Falta algo» y prendió el interruptor por
    -- error, al apagarlo sigue siendo el mismo «Falta algo». Casa pasa a carga completa recién al enviarla.
    UPDATE mypump_gimnasio SET lugar = v_lugar, actualizado_en = NOW() WHERE id = v_fila.id;
    RETURN jsonb_build_object('ok', TRUE, 'ya', FALSE, 'id', v_fila.id, 'estado', 'borrador', 'lugar', v_lugar);
  END IF;
  -- Sin carga abierta: apagar no abre nada (para volver al gimnasio se usa «Cambié de gimnasio», como siempre).
  IF NOT p_casa THEN RETURN jsonb_build_object('ok', TRUE, 'ya', TRUE, 'id', NULL, 'lugar', 'gimnasio'); END IF;
  BEGIN
    INSERT INTO mypump_gimnasio (cliente_id, version, modo, lugar)
    VALUES (v_cliente_id, COALESCE((SELECT MAX(version) FROM mypump_gimnasio WHERE cliente_id = v_cliente_id), 0) + 1, 'completa', 'casa')
    RETURNING * INTO v_fila;
  EXCEPTION WHEN unique_violation THEN
    RETURN jsonb_build_object('ok', FALSE, 'error', 'reintentar');
  END;
  RETURN jsonb_build_object('ok', TRUE, 'ya', FALSE, 'id', v_fila.id, 'estado', 'borrador', 'lugar', 'casa');
END;
$$;

-- Manda lo que tiene en casa. `p_equipos`: [{"tipo", "kg"?}] con tipos de `mypump_casa_tipos()`; `kg` (hasta cuántos
-- kilos) solo donde la lista lo pide, entre 1 y 400. `p_sin_equipo` TRUE = no tiene nada (entrena con su cuerpo).
-- Idempotente: reintentar da `ya`.
CREATE OR REPLACE FUNCTION mypump_casa_enviar(p_token TEXT, p_id UUID, p_equipos JSONB, p_sin_equipo BOOLEAN, p_nota TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_cliente_id TEXT;
  v_fila       mypump_gimnasio%ROWTYPE;
  v_e          JSONB;
  v_def        JSONB;
  v_kg         NUMERIC;
  v_equipos    JSONB := '[]'::JSONB;
  v_inv        JSONB := '[]'::JSONB;
  v_vistos     TEXT[] := '{}';
BEGIN
  v_cliente_id := mypump_get_cliente_id_from_token(p_token);
  IF v_cliente_id IS NULL THEN RETURN NULL; END IF;
  SELECT * INTO v_fila FROM mypump_gimnasio WHERE id = p_id AND cliente_id = v_cliente_id FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', FALSE, 'error', 'no_encontrado'); END IF;
  IF v_fila.lugar <> 'casa' THEN RETURN jsonb_build_object('ok', FALSE, 'error', 'no_es_casa'); END IF;
  IF v_fila.estado <> 'borrador' THEN
    RETURN jsonb_build_object('ok', TRUE, 'ya', TRUE, 'estado', CASE WHEN v_fila.estado = 'error' THEN 'enviado' ELSE v_fila.estado END);
  END IF;
  IF NOT mypump_casa_habilitada(v_cliente_id) THEN RETURN jsonb_build_object('ok', FALSE, 'error', 'no_habilitado'); END IF;
  IF p_equipos IS NOT NULL AND jsonb_typeof(p_equipos) <> 'array' THEN RAISE EXCEPTION 'equipos mal formado' USING ERRCODE = '22023'; END IF;

  FOR v_e IN SELECT * FROM jsonb_array_elements(COALESCE(p_equipos, '[]'::JSONB)) LOOP
    IF jsonb_typeof(v_e) <> 'object' OR jsonb_typeof(v_e->'tipo') IS DISTINCT FROM 'string' THEN RAISE EXCEPTION 'equipo mal formado' USING ERRCODE = '22023'; END IF;
    SELECT t INTO v_def FROM jsonb_array_elements(mypump_casa_tipos()) t WHERE t->>'tipo' = v_e->>'tipo';
    IF v_def IS NULL THEN RAISE EXCEPTION 'equipo fuera de la lista' USING ERRCODE = '22023'; END IF;
    IF (v_e->>'tipo') = ANY (v_vistos) THEN CONTINUE; END IF;
    v_vistos := v_vistos || (v_e->>'tipo');
    v_kg := NULL;
    IF (v_def->>'kg')::BOOLEAN AND jsonb_typeof(v_e->'kg') = 'number' THEN
      v_kg := round((v_e->>'kg')::NUMERIC, 1);
      IF v_kg < 1 OR v_kg > 400 THEN RAISE EXCEPTION 'kilos fuera de rango' USING ERRCODE = '22023'; END IF;
    END IF;
    v_equipos := v_equipos || jsonb_build_array(jsonb_strip_nulls(jsonb_build_object('tipo', v_e->>'tipo', 'kg', v_kg)));
    v_inv := v_inv || jsonb_build_array(jsonb_strip_nulls(jsonb_build_object(
      'tipo', v_e->>'tipo', 'nombre', v_def->>'nombre', 'zona', 'casa', 'cantidad', 1, 'estado', 'confirmado', 'kg_max', v_kg, 'origen', 'alumno')));
  END LOOP;

  IF jsonb_array_length(v_equipos) = 0 AND NOT COALESCE(p_sin_equipo, FALSE) THEN RETURN jsonb_build_object('ok', FALSE, 'error', 'sin_datos'); END IF;
  IF jsonb_array_length(v_equipos) > 0 AND COALESCE(p_sin_equipo, FALSE) THEN RETURN jsonb_build_object('ok', FALSE, 'error', 'contradiccion'); END IF;

  UPDATE mypump_gimnasio SET
    estado = 'a_revisar',
    -- Casa es siempre una carga completa: no hay «falta algo» sobre un gimnasio que no es el suyo.
    modo = 'completa', base_id = NULL,
    momento = CASE WHEN EXISTS (SELECT 1 FROM mypump_rutinas r WHERE r.cliente_id = v_cliente_id AND r.estado = 'activa') THEN 'con_plan' ELSE 'pre_entrega' END,
    casa = jsonb_build_object('equipos', v_equipos, 'sin_equipo', COALESCE(p_sin_equipo, FALSE)),
    inventario = jsonb_build_object('lugar', 'casa', 'equipos', v_inv),
    nota_alumno = NULLIF(left(btrim(regexp_replace(COALESCE(p_nota, ''), '[[:cntrl:]]+', ' ', 'g')), 300), ''),
    enviado_en = NOW(), procesado_en = NOW(), actualizado_en = NOW()
  WHERE id = p_id;
  RETURN jsonb_build_object('ok', TRUE, 'ya', FALSE, 'estado', 'a_revisar');
END;
$$;

REVOKE ALL ON FUNCTION mypump_casa_tipos(), mypump_casa_habilitada(TEXT), mypump_casa_vista(mypump_gimnasio) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION mypump_casa_tipos(), mypump_casa_habilitada(TEXT), mypump_casa_vista(mypump_gimnasio) TO service_role;
REVOKE ALL ON FUNCTION mypump_casa_get(TEXT), mypump_casa_elegir(TEXT, BOOLEAN), mypump_casa_enviar(TEXT, UUID, JSONB, BOOLEAN, TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION mypump_casa_get(TEXT), mypump_casa_elegir(TEXT, BOOLEAN), mypump_casa_enviar(TEXT, UUID, JSONB, BOOLEAN, TEXT) TO anon, authenticated, service_role;

NOTIFY pgrst, 'reload schema';
COMMIT;
