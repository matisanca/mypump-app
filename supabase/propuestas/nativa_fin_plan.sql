-- nativa_fin_plan.sql — PROPUESTA, SIN APLICAR. Para aplicar hace falta el OK de Mati (compuerta G2).
--
-- «Tu recorrido» (app 2.3.0 y web): cuando al plan le queda poco, la app le muestra al alumno lo que hizo en estos
-- meses y le deja pedir una videollamada con Mati para ver cómo seguir. Palanca `fin_plan`, APAGADA.
--
-- Mientras esto no esté aplicado, `mypump_fin_plan_get` no existe (PGRST202) y las apps no muestran nada.
--
-- Invariantes:
--   · Opt-in por alumno: sin una fila en `mypump_fin_plan` aprobada por una persona (`aprobado_por`), no se ve nada.
--     La arma la Mini (recompras) con el OK de Mati. La app nunca calcula a quién mostrarle.
--   · Nunca a quien ya venció: la fecha se lee en el momento de `client_plan_dates` (la fuente única). Si la fecha
--     pasó, si es estimada o si ya no es la que Mati aprobó (el plan se movió), la tarjeta deja de verse sola.
--   · Nunca a los excluidos: `mypump_fin_plan_excluidos` gana siempre, aunque haya una fila publicada por error.
--   · Al teléfono no viaja ninguna fecha de fin ni la palabra con la que se le dice puertas adentro. Los textos que
--     escribe la Mini se rechazan si traen palabras que al alumno no se le dicen (ver `mypump_fin_plan_texto_ok`).
--   · El `cliente_id` sale siempre del token. Las tablas no se tocan por fuera de las funciones (anon y authenticated, nada).
--   · La app no agenda ni manda nada a nadie: deja un pedido. Lo lee la Mini y sigue el circuito de siempre.
BEGIN;

-- ── Palanca: apagada. `fin_plan_dias` = desde cuántos días antes se puede ver (sin la clave, 21). ──
INSERT INTO mypump_app_config (clave, valor, nota) VALUES
  ('fin_plan', 'false'::JSONB, 'Tu recorrido (2.3.0): resumen del plan y pedido de videollamada con Mati. true = prendida'),
  ('fin_plan_dias', '21'::JSONB, 'Tu recorrido: desde cuántos días antes del fin del plan se puede ver (7 a 45)'),
  ('fin_plan_agenda', '"mati"'::JSONB, 'Tu recorrido: "mati" = Mati le escribe para coordinar; "app" = el horario se elige en la app')
ON CONFLICT (clave) DO NOTHING;

CREATE OR REPLACE FUNCTION mypump_fin_plan_prendida()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE((SELECT valor = 'true'::JSONB FROM mypump_app_config WHERE clave = 'fin_plan'), FALSE);
$$;

CREATE OR REPLACE FUNCTION mypump_fin_plan_dias()
RETURNS INTEGER
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT LEAST(45, GREATEST(7, COALESCE(
    (SELECT CASE WHEN jsonb_typeof(valor) = 'number' THEN (valor #>> '{}')::NUMERIC::INTEGER END
       FROM mypump_app_config WHERE clave = 'fin_plan_dias'), 21)));
$$;

-- «Hoy» en Argentina: la base corre en UTC y el plan termina con el día de acá.
CREATE OR REPLACE FUNCTION mypump_fin_plan_hoy()
RETURNS DATE
LANGUAGE sql
STABLE
SET search_path = public
AS $$
  SELECT (NOW() AT TIME ZONE 'America/Argentina/Buenos_Aires')::DATE;
$$;

-- Un texto que va al alumno. FALSE si trae algo que no se le dice: la palabra de puertas adentro, plata, pausas,
-- «tu coach», «tu entrenador» o IA. Es una red, no reemplaza la lectura de Mati.
CREATE OR REPLACE FUNCTION mypump_fin_plan_texto_ok(p TEXT)
RETURNS BOOLEAN
LANGUAGE sql
IMMUTABLE
SET search_path = public
AS $$
  SELECT p IS NULL OR NOT (
    translate(lower(p), 'áéíóúüàèìòù', 'aeiouuaeiou')
      ~ '(renov|recompra|venc|coach|entrenador|inteligencia artificial|pausa|vacacion|cuota|precio|descuento|oferta|(^|[^a-z])promo(s|cion|ciones)?([^a-z]|$)|(^|[^a-z])pag[oa]s?([^a-z]|$)|(^|[^a-z])ia([^a-z]|$)|(^|[^a-z])rir([^a-z]|$)|[0-9]{1,2}/[0-9]{1,2}|quedan? [0-9]+ (dia|semana|mes))'
  );
$$;

-- El resumen que arma la Mini: {"titulo"?, "mensaje"?, "logros": [{"titulo", "valor", "detalle"?}]} con 1 a 6 logros.
-- Devuelve NULL si está bien, o qué está mal.
CREATE OR REPLACE FUNCTION mypump_fin_plan_resumen_error(p JSONB)
RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE
SET search_path = public
AS $$
DECLARE
  v_l JSONB;
  v_k TEXT;
BEGIN
  IF p IS NULL OR jsonb_typeof(p) <> 'object' THEN RETURN 'no es un objeto'; END IF;
  FOR v_k IN SELECT jsonb_object_keys(p) LOOP
    IF v_k NOT IN ('titulo', 'mensaje', 'logros') THEN RETURN 'clave desconocida: ' || left(v_k, 40); END IF;
  END LOOP;
  IF p ? 'titulo' AND (jsonb_typeof(p->'titulo') <> 'string' OR char_length(btrim(p->>'titulo')) NOT BETWEEN 1 AND 60) THEN RETURN 'titulo: texto de 1 a 60'; END IF;
  IF p ? 'mensaje' AND (jsonb_typeof(p->'mensaje') <> 'string' OR char_length(btrim(p->>'mensaje')) NOT BETWEEN 1 AND 400) THEN RETURN 'mensaje: texto de 1 a 400'; END IF;
  IF jsonb_typeof(p->'logros') IS DISTINCT FROM 'array' OR jsonb_array_length(p->'logros') NOT BETWEEN 1 AND 6 THEN RETURN 'logros: lista de 1 a 6'; END IF;
  FOR v_l IN SELECT * FROM jsonb_array_elements(p->'logros') LOOP
    IF jsonb_typeof(v_l) <> 'object' THEN RETURN 'logro: no es un objeto'; END IF;
    FOR v_k IN SELECT jsonb_object_keys(v_l) LOOP
      IF v_k NOT IN ('titulo', 'valor', 'detalle') THEN RETURN 'logro: clave desconocida: ' || left(v_k, 40); END IF;
    END LOOP;
    IF jsonb_typeof(v_l->'titulo') IS DISTINCT FROM 'string' OR char_length(btrim(v_l->>'titulo')) NOT BETWEEN 1 AND 40 THEN RETURN 'logro.titulo: texto de 1 a 40'; END IF;
    IF jsonb_typeof(v_l->'valor') IS DISTINCT FROM 'string' OR char_length(btrim(v_l->>'valor')) NOT BETWEEN 1 AND 24 THEN RETURN 'logro.valor: texto de 1 a 24'; END IF;
    IF v_l ? 'detalle' AND (jsonb_typeof(v_l->'detalle') <> 'string' OR char_length(btrim(v_l->>'detalle')) NOT BETWEEN 1 AND 120) THEN RETURN 'logro.detalle: texto de 1 a 120'; END IF;
    IF NOT mypump_fin_plan_texto_ok(concat_ws(' · ', v_l->>'titulo', v_l->>'valor', v_l->>'detalle')) THEN RETURN 'logro: texto que al alumno no se le dice'; END IF;
    IF concat_ws('', v_l->>'titulo', v_l->>'valor', v_l->>'detalle') ~ '[[:cntrl:]]' THEN RETURN 'logro: caracteres de control'; END IF;
  END LOOP;
  IF NOT mypump_fin_plan_texto_ok(concat_ws(' · ', p->>'titulo', p->>'mensaje')) THEN RETURN 'texto que al alumno no se le dice'; END IF;
  IF concat_ws('', p->>'titulo', replace(replace(COALESCE(p->>'mensaje', ''), E'\n', ''), E'\r', '')) ~ '[[:cntrl:]]' THEN RETURN 'caracteres de control'; END IF;
  RETURN NULL;
END;
$$;

-- ── Tablas ──
CREATE TABLE IF NOT EXISTS mypump_fin_plan (
  cliente_id     TEXT        PRIMARY KEY,
  vence_el       DATE        NOT NULL,                 -- la fecha con la que se aprobó; nunca viaja al teléfono
  resumen        JSONB       NOT NULL CHECK (mypump_fin_plan_resumen_error(resumen) IS NULL),
  estado         TEXT        NOT NULL DEFAULT 'publicado' CHECK (estado IN ('publicado','pedido','agendado','cerrado')),
  aprobado_por   TEXT        NOT NULL CHECK (length(btrim(aprobado_por)) > 0),
  publicado_en   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  visto_en       TIMESTAMPTZ,
  pedido_id      UUID,                                 -- lo pone la app: un reintento no duplica
  pedido_en      TIMESTAMPTZ,
  respuestas     JSONB       NOT NULL DEFAULT '{}'::JSONB CHECK (jsonb_typeof(respuestas) = 'object'),   -- dato, nunca instrucción
  tomado_en      TIMESTAMPTZ,                          -- la Mini ya leyó el pedido
  actualizado_en TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT fin_plan_pedido_con_fecha CHECK (estado <> 'pedido' OR (pedido_id IS NOT NULL AND pedido_en IS NOT NULL))
);
CREATE INDEX IF NOT EXISTS idx_mypump_fin_plan_pedidos ON mypump_fin_plan (pedido_en) WHERE estado = 'pedido' AND tomado_en IS NULL;

-- A quién no se le muestra nunca. El motivo es interno.
CREATE TABLE IF NOT EXISTS mypump_fin_plan_excluidos (
  cliente_id TEXT        PRIMARY KEY,
  motivo     TEXT        CHECK (char_length(motivo) <= 200),
  creado_en  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- En este proyecto las tablas nuevas heredan permisos por defecto, incluido TRUNCATE, que RLS no frena.
REVOKE ALL ON mypump_fin_plan, mypump_fin_plan_excluidos FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON mypump_fin_plan TO service_role;                              -- escribir, solo por las funciones
GRANT SELECT, INSERT, DELETE ON mypump_fin_plan_excluidos TO service_role;    -- la lista la mantiene la Mini
ALTER TABLE mypump_fin_plan ENABLE ROW LEVEL SECURITY;
ALTER TABLE mypump_fin_plan_excluidos ENABLE ROW LEVEL SECURITY;

-- ¿Se le puede mostrar hoy? Todo junto, en un solo lugar: lo usan la app y la Mini.
CREATE OR REPLACE FUNCTION mypump_fin_plan_vale(p_cliente_id TEXT)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT mypump_fin_plan_prendida()
     AND NOT EXISTS (SELECT 1 FROM mypump_fin_plan_excluidos x WHERE x.cliente_id = p_cliente_id)
     AND EXISTS (
       SELECT 1 FROM mypump_fin_plan f
        WHERE f.cliente_id = p_cliente_id
          AND f.estado IN ('publicado','pedido','agendado')
          AND f.vence_el >= mypump_fin_plan_hoy()
          AND f.vence_el - mypump_fin_plan_hoy() <= mypump_fin_plan_dias()
          -- La fuente única tiene que decir lo mismo, hoy: una sola fila, sin estimar y con la misma fecha.
          AND (SELECT count(*) FROM client_plan_dates d WHERE d.nutriplan_id = p_cliente_id) = 1
          AND EXISTS (SELECT 1 FROM client_plan_dates d
                       WHERE d.nutriplan_id = p_cliente_id AND d.plan_vencimiento = f.vence_el AND COALESCE(d.estimado, FALSE) = FALSE));
$$;

-- ── La app, por token (anon y authenticated). NULL = token caído ──
CREATE OR REPLACE FUNCTION mypump_fin_plan_get(p_token TEXT)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_cliente_id TEXT;
  v_fila       mypump_fin_plan%ROWTYPE;
BEGIN
  v_cliente_id := mypump_get_cliente_id_from_token(p_token);
  IF v_cliente_id IS NULL THEN RETURN NULL; END IF;
  IF NOT mypump_fin_plan_prendida() THEN RETURN jsonb_build_object('habilitado', FALSE); END IF;
  IF NOT mypump_fin_plan_vale(v_cliente_id) THEN RETURN jsonb_build_object('habilitado', TRUE, 'visible', FALSE); END IF;
  SELECT * INTO v_fila FROM mypump_fin_plan WHERE cliente_id = v_cliente_id;
  RETURN jsonb_build_object(
    'habilitado', TRUE,
    'visible', TRUE,
    'estado', v_fila.estado,
    'resumen', v_fila.resumen,
    'respuestas', v_fila.respuestas,
    'agenda', COALESCE((SELECT CASE WHEN valor = '"app"'::JSONB THEN 'app' ELSE 'mati' END FROM mypump_app_config WHERE clave = 'fin_plan_agenda'), 'mati')
  );
END;
$$;

-- El alumno abrió el resumen. Sirve para saber si lo vio; no cambia nada de lo que ve.
CREATE OR REPLACE FUNCTION mypump_fin_plan_visto(p_token TEXT)
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
  IF NOT mypump_fin_plan_vale(v_cliente_id) THEN RETURN jsonb_build_object('ok', FALSE, 'error', 'no_disponible'); END IF;
  UPDATE mypump_fin_plan SET visto_en = COALESCE(visto_en, NOW()) WHERE cliente_id = v_cliente_id;
  RETURN jsonb_build_object('ok', TRUE);
END;
$$;

-- El alumno pide la videollamada con Mati. `p_respuestas`: {"mejor"?, "costo"?, "objetivo"?}, textos de hasta 500.
-- Con el mismo `p_id` es un reintento. Con otro, mientras la Mini no lo haya tomado, corrige las respuestas.
CREATE OR REPLACE FUNCTION mypump_fin_plan_pedir(p_token TEXT, p_id UUID, p_respuestas JSONB DEFAULT '{}'::JSONB)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_cliente_id TEXT;
  v_fila       mypump_fin_plan%ROWTYPE;
  v_resp       JSONB := '{}'::JSONB;
  v_k          TEXT;
  v_t          TEXT;
BEGIN
  v_cliente_id := mypump_get_cliente_id_from_token(p_token);
  IF v_cliente_id IS NULL THEN RETURN NULL; END IF;
  IF NOT mypump_fin_plan_prendida() THEN RETURN jsonb_build_object('ok', FALSE, 'error', 'apagado'); END IF;
  IF p_id IS NULL OR (p_respuestas IS NOT NULL AND jsonb_typeof(p_respuestas) <> 'object') THEN
    RAISE EXCEPTION 'pedido mal formado' USING ERRCODE = '22023';
  END IF;
  IF NOT mypump_fin_plan_vale(v_cliente_id) THEN RETURN jsonb_build_object('ok', FALSE, 'error', 'no_disponible'); END IF;

  FOREACH v_k IN ARRAY ARRAY['mejor', 'costo', 'objetivo'] LOOP
    IF jsonb_typeof(COALESCE(p_respuestas, '{}'::JSONB)->v_k) = 'string' THEN
      v_t := NULLIF(left(btrim(regexp_replace(p_respuestas->>v_k, '[[:cntrl:]]+', ' ', 'g')), 500), '');
      IF v_t IS NOT NULL THEN v_resp := v_resp || jsonb_build_object(v_k, v_t); END IF;
    END IF;
  END LOOP;

  SELECT * INTO v_fila FROM mypump_fin_plan WHERE cliente_id = v_cliente_id FOR UPDATE;
  IF v_fila.estado = 'agendado' THEN RETURN jsonb_build_object('ok', TRUE, 'ya', TRUE, 'estado', 'agendado'); END IF;
  IF v_fila.estado = 'pedido' THEN
    -- Reintento, o corrección mientras nadie lo leyó. Ya tomado, queda como está: no se avisa dos veces.
    IF v_fila.pedido_id <> p_id AND v_fila.tomado_en IS NULL AND v_resp <> '{}'::JSONB AND v_resp <> v_fila.respuestas THEN
      UPDATE mypump_fin_plan SET respuestas = v_resp, actualizado_en = NOW() WHERE cliente_id = v_cliente_id;
    END IF;
    RETURN jsonb_build_object('ok', TRUE, 'ya', TRUE, 'estado', 'pedido');
  END IF;
  UPDATE mypump_fin_plan SET estado = 'pedido', pedido_id = p_id, pedido_en = NOW(), respuestas = v_resp,
         visto_en = COALESCE(visto_en, NOW()), actualizado_en = NOW()
   WHERE cliente_id = v_cliente_id;
  RETURN jsonb_build_object('ok', TRUE, 'ya', FALSE, 'estado', 'pedido');
END;
$$;

-- ── La Mini (service_role) ──
-- A quién se le podría armar el resumen hoy: con cuenta activa, fecha firme dentro de la ventana, sin excluir y sin
-- una fila vigente para esa fecha. Devuelve ids y fechas, sin nombres.
CREATE OR REPLACE FUNCTION mypump_fin_plan_candidatos()
RETURNS JSONB
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(jsonb_agg(jsonb_build_object('cliente_id', d.nutriplan_id, 'vence_el', d.plan_vencimiento,
                                               'dias', d.plan_vencimiento - mypump_fin_plan_hoy()) ORDER BY d.plan_vencimiento, d.nutriplan_id), '[]'::JSONB)
    FROM client_plan_dates d
   WHERE d.plan_vencimiento >= mypump_fin_plan_hoy()
     AND d.plan_vencimiento - mypump_fin_plan_hoy() <= mypump_fin_plan_dias()
     AND COALESCE(d.estimado, FALSE) = FALSE
     AND (SELECT count(*) FROM client_plan_dates d2 WHERE d2.nutriplan_id = d.nutriplan_id) = 1
     AND EXISTS (SELECT 1 FROM mypump_clientes c WHERE c.cliente_id = d.nutriplan_id AND c.access_token_active)
     AND NOT EXISTS (SELECT 1 FROM mypump_fin_plan_excluidos x WHERE x.cliente_id = d.nutriplan_id)
     AND NOT EXISTS (SELECT 1 FROM mypump_fin_plan f WHERE f.cliente_id = d.nutriplan_id AND f.vence_el = d.plan_vencimiento);
$$;

-- Publica o corrige el resumen de un alumno, con el OK de una persona. Rechaza al excluido, al vencido, la fecha que
-- no coincide con la fuente única y el texto que no pasa. Si la fecha cambió respecto de la fila anterior, empieza de cero.
CREATE OR REPLACE FUNCTION mypump_fin_plan_publicar(p_cliente_id TEXT, p_vence_el DATE, p_resumen JSONB, p_aprobado_por TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_error TEXT;
  v_fila  mypump_fin_plan%ROWTYPE;
BEGIN
  IF p_cliente_id IS NULL OR p_vence_el IS NULL OR length(btrim(COALESCE(p_aprobado_por, ''))) = 0 THEN
    RAISE EXCEPTION 'faltan datos o la aprobación' USING ERRCODE = '22023';
  END IF;
  IF EXISTS (SELECT 1 FROM mypump_fin_plan_excluidos WHERE cliente_id = p_cliente_id) THEN RETURN jsonb_build_object('ok', FALSE, 'error', 'excluido'); END IF;
  IF NOT EXISTS (SELECT 1 FROM mypump_clientes c WHERE c.cliente_id = p_cliente_id AND c.access_token_active) THEN RETURN jsonb_build_object('ok', FALSE, 'error', 'sin_cuenta'); END IF;
  IF p_vence_el < mypump_fin_plan_hoy() THEN RETURN jsonb_build_object('ok', FALSE, 'error', 'vencido'); END IF;
  IF (SELECT count(*) FROM client_plan_dates d WHERE d.nutriplan_id = p_cliente_id) <> 1
     OR NOT EXISTS (SELECT 1 FROM client_plan_dates d WHERE d.nutriplan_id = p_cliente_id AND d.plan_vencimiento = p_vence_el AND COALESCE(d.estimado, FALSE) = FALSE) THEN
    RETURN jsonb_build_object('ok', FALSE, 'error', 'fecha_no_coincide');
  END IF;
  v_error := mypump_fin_plan_resumen_error(p_resumen);
  IF v_error IS NOT NULL THEN RETURN jsonb_build_object('ok', FALSE, 'error', 'resumen', 'detalle', v_error); END IF;

  SELECT * INTO v_fila FROM mypump_fin_plan WHERE cliente_id = p_cliente_id FOR UPDATE;
  IF NOT FOUND THEN
    INSERT INTO mypump_fin_plan (cliente_id, vence_el, resumen, aprobado_por) VALUES (p_cliente_id, p_vence_el, p_resumen, btrim(p_aprobado_por));
    RETURN jsonb_build_object('ok', TRUE, 'nuevo', TRUE);
  END IF;
  IF v_fila.vence_el <> p_vence_el THEN
    UPDATE mypump_fin_plan SET vence_el = p_vence_el, resumen = p_resumen, aprobado_por = btrim(p_aprobado_por), estado = 'publicado',
           publicado_en = NOW(), visto_en = NULL, pedido_id = NULL, pedido_en = NULL, respuestas = '{}'::JSONB, tomado_en = NULL, actualizado_en = NOW()
     WHERE cliente_id = p_cliente_id;
    RETURN jsonb_build_object('ok', TRUE, 'nuevo', TRUE);
  END IF;
  UPDATE mypump_fin_plan SET resumen = p_resumen, aprobado_por = btrim(p_aprobado_por), actualizado_en = NOW(),
         estado = CASE WHEN estado = 'cerrado' THEN 'publicado' ELSE estado END
   WHERE cliente_id = p_cliente_id;
  RETURN jsonb_build_object('ok', TRUE, 'nuevo', FALSE);
END;
$$;

-- Los pedidos que nadie leyó todavía. Con la palanca apagada no devuelve nada, aunque haya filas.
CREATE OR REPLACE FUNCTION mypump_fin_plan_pedidos()
RETURNS JSONB
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(jsonb_agg(jsonb_build_object('cliente_id', f.cliente_id, 'pedido_id', f.pedido_id, 'pedido_en', f.pedido_en,
                                               'respuestas', f.respuestas, 'vence_el', f.vence_el) ORDER BY f.pedido_en, f.cliente_id), '[]'::JSONB)
    FROM mypump_fin_plan f
   WHERE f.estado = 'pedido' AND f.tomado_en IS NULL AND mypump_fin_plan_vale(f.cliente_id);
$$;

-- La Mini avisa en qué quedó: 'tomado' (leyó el pedido, compara con el que leyó), 'agendado', 'cerrado' o 'publicado'
-- (se cayó la videollamada y se vuelve a ofrecer).
CREATE OR REPLACE FUNCTION mypump_fin_plan_marcar(p_cliente_id TEXT, p_marca TEXT, p_pedido_id UUID DEFAULT NULL)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_n INTEGER;
BEGIN
  IF p_marca IS NULL OR p_marca NOT IN ('tomado','agendado','cerrado','publicado') THEN RAISE EXCEPTION 'marca inválida' USING ERRCODE = '22023'; END IF;
  IF p_marca = 'tomado' THEN
    UPDATE mypump_fin_plan SET tomado_en = NOW(), actualizado_en = NOW()
     WHERE cliente_id = p_cliente_id AND estado = 'pedido' AND tomado_en IS NULL AND pedido_id IS NOT DISTINCT FROM p_pedido_id;
  ELSIF p_marca = 'publicado' THEN
    UPDATE mypump_fin_plan SET estado = 'publicado', pedido_id = NULL, pedido_en = NULL, tomado_en = NULL, actualizado_en = NOW()
     WHERE cliente_id = p_cliente_id AND estado IN ('pedido','agendado','cerrado');
  ELSE
    UPDATE mypump_fin_plan SET estado = p_marca, actualizado_en = NOW() WHERE cliente_id = p_cliente_id AND estado <> p_marca;
  END IF;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN jsonb_build_object('ok', v_n = 1);
END;
$$;

REVOKE ALL ON FUNCTION mypump_fin_plan_prendida(), mypump_fin_plan_dias(), mypump_fin_plan_hoy(), mypump_fin_plan_texto_ok(TEXT),
  mypump_fin_plan_resumen_error(JSONB), mypump_fin_plan_vale(TEXT), mypump_fin_plan_candidatos(),
  mypump_fin_plan_publicar(TEXT, DATE, JSONB, TEXT), mypump_fin_plan_pedidos(), mypump_fin_plan_marcar(TEXT, TEXT, UUID)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION mypump_fin_plan_prendida(), mypump_fin_plan_dias(), mypump_fin_plan_hoy(), mypump_fin_plan_texto_ok(TEXT),
  mypump_fin_plan_resumen_error(JSONB), mypump_fin_plan_vale(TEXT), mypump_fin_plan_candidatos(),
  mypump_fin_plan_publicar(TEXT, DATE, JSONB, TEXT), mypump_fin_plan_pedidos(), mypump_fin_plan_marcar(TEXT, TEXT, UUID)
  TO service_role;
REVOKE ALL ON FUNCTION mypump_fin_plan_get(TEXT), mypump_fin_plan_visto(TEXT), mypump_fin_plan_pedir(TEXT, UUID, JSONB) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION mypump_fin_plan_get(TEXT), mypump_fin_plan_visto(TEXT), mypump_fin_plan_pedir(TEXT, UUID, JSONB) TO anon, authenticated, service_role;

NOTIFY pgrst, 'reload schema';
COMMIT;
