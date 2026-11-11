-- nativa_compras_pais.sql — PROPUESTA, SIN APLICAR. Para aplicar hace falta el OK de Mati (compuerta G2).
--
-- «Dónde comprarlo» (app 2.3.0 y web): para los suplementos del plan del alumno, dónde se consiguen en su país.
-- Palanca `compras_pais`, APAGADA.
--
-- Es un dato remoto y verificado, nunca inventado:
--   · Este archivo NO carga ninguna tienda ni ningún país: las tablas nacen vacías. Los datos los carga la Mini desde
--     la lista aprobada por Mati (`marcas.yaml`), con quién lo verificó y cuándo.
--   · Sin país cargado para el alumno, sin dato para ese país, con un dato verificado hace más de 180 días o sin un
--     suplemento que coincida EXACTO: no se muestra nada. No hay país por defecto ni coincidencia aproximada.
--   · Solo los suplementos de `mypump_suplementacion`. Los ítems `protector` (fármacos) y los que salen, nunca.
--   · El `cliente_id` sale siempre del token. Las tablas no se tocan por fuera de las funciones (anon y authenticated, nada).
--
-- Mientras esto no esté aplicado, `mypump_compras_get` no existe (PGRST202) y las apps no muestran nada.
BEGIN;

INSERT INTO mypump_app_config (clave, valor, nota) VALUES
  ('compras_pais', 'false'::JSONB, 'Dónde comprarlo (2.3.0): tiendas verificadas por país en Suplementación. true = prendida')
ON CONFLICT (clave) DO NOTHING;

-- La clave con la que se comparan los nombres: minúsculas, sin tildes, sin lo que va entre paréntesis, con guiones y
-- signos como espacios. «Omega-3 (EPA + DHA)» y «omega 3» dan lo mismo. Si no coincide entero, no coincide.
CREATE OR REPLACE FUNCTION mypump_compras_clave(p TEXT)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
SET search_path = public
AS $$
  SELECT btrim(regexp_replace(regexp_replace(
    translate(lower(regexp_replace(COALESCE(p, ''), '\([^)]*\)', ' ', 'g')), 'áéíóúüàèìòù', 'aeiouuaeiou'),
    '[^a-z0-9ñ+]+', ' ', 'g'), '\s+', ' ', 'g'));
$$;

CREATE TABLE IF NOT EXISTS mypump_compras_pais (
  id             UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  pais           TEXT        NOT NULL CHECK (pais ~ '^[A-Z]{2}$'),              -- ISO 3166-1 alfa-2
  claves         TEXT[]      NOT NULL CHECK (cardinality(claves) BETWEEN 1 AND 12 AND array_position(claves, '') IS NULL AND array_position(claves, NULL) IS NULL),
  producto       TEXT        NOT NULL CHECK (char_length(btrim(producto)) BETWEEN 1 AND 80),   -- marca y producto, como figura en la tienda
  tienda         TEXT        NOT NULL CHECK (char_length(btrim(tienda)) BETWEEN 1 AND 60),
  url            TEXT        CHECK (url IS NULL OR (url ~ '^https://[^[:space:]]+$' AND char_length(url) <= 300)),
  nota           TEXT        CHECK (char_length(nota) <= 140),
  orden          INTEGER     NOT NULL DEFAULT 0,
  verificado_por TEXT        NOT NULL CHECK (length(btrim(verificado_por)) > 0),
  verificado_en  DATE        NOT NULL,
  activo         BOOLEAN     NOT NULL DEFAULT TRUE,
  creado_en      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT compras_sin_control CHECK (concat_ws('', producto, tienda, nota) !~ '[[:cntrl:]]')
);
CREATE INDEX IF NOT EXISTS idx_mypump_compras_pais ON mypump_compras_pais (pais) WHERE activo;

CREATE TABLE IF NOT EXISTS mypump_cliente_pais (
  cliente_id     TEXT        PRIMARY KEY,
  pais           TEXT        NOT NULL CHECK (pais ~ '^[A-Z]{2}$'),
  fuente         TEXT        NOT NULL CHECK (char_length(btrim(fuente)) BETWEEN 1 AND 60),   -- de dónde salió: ficha, formulario, el alumno
  actualizado_en TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

REVOKE ALL ON mypump_compras_pais, mypump_cliente_pais FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT, UPDATE, DELETE ON mypump_compras_pais TO service_role;     -- alta, solo por mypump_compras_cargar (normaliza las claves)
GRANT SELECT, DELETE ON mypump_cliente_pais TO service_role;
ALTER TABLE mypump_compras_pais ENABLE ROW LEVEL SECURITY;
ALTER TABLE mypump_cliente_pais ENABLE ROW LEVEL SECURITY;

-- ── La app, por token (anon y authenticated). NULL = token caído ──
-- {habilitado, pais, items: [{nombre, opciones: [{producto, tienda, url, nota}]}]}. Solo ítems con al menos una opción.
CREATE OR REPLACE FUNCTION mypump_compras_get(p_token TEXT)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_cliente_id TEXT;
  v_pais       TEXT;
  v_items      JSONB;
BEGIN
  v_cliente_id := mypump_get_cliente_id_from_token(p_token);
  IF v_cliente_id IS NULL THEN RETURN NULL; END IF;
  IF NOT COALESCE((SELECT valor = 'true'::JSONB FROM mypump_app_config WHERE clave = 'compras_pais'), FALSE) THEN
    RETURN jsonb_build_object('habilitado', FALSE);
  END IF;
  SELECT pais INTO v_pais FROM mypump_cliente_pais WHERE cliente_id = v_cliente_id;
  IF v_pais IS NULL THEN RETURN jsonb_build_object('habilitado', TRUE, 'items', '[]'::JSONB); END IF;

  WITH plan AS (
    SELECT DISTINCT ON (mypump_compras_clave(it->>'nombre'))
           btrim(it->>'nombre') AS nombre, mypump_compras_clave(it->>'nombre') AS clave, o AS orden
      FROM mypump_suplementacion(p_token) s,
           jsonb_array_elements(CASE WHEN jsonb_typeof(s.suplementacion->'items') = 'array' THEN s.suplementacion->'items' ELSE '[]'::JSONB END)
             WITH ORDINALITY AS t(it, o)
     WHERE jsonb_typeof(it) = 'object'
       AND jsonb_typeof(it->'nombre') = 'string'
       AND mypump_compras_clave(it->>'nombre') <> ''
       AND it->'protector' IS DISTINCT FROM 'true'::JSONB
       AND lower(btrim(COALESCE(it->>'estado', ''))) <> 'sale'
     ORDER BY mypump_compras_clave(it->>'nombre'), o
  )
  SELECT COALESCE(jsonb_agg(jsonb_build_object('nombre', x.nombre, 'opciones', x.opciones) ORDER BY x.orden), '[]'::JSONB) INTO v_items
    FROM (
      SELECT p.nombre, p.orden,
             (SELECT jsonb_agg(jsonb_strip_nulls(jsonb_build_object('producto', btrim(c.producto), 'tienda', btrim(c.tienda), 'url', c.url, 'nota', NULLIF(btrim(c.nota), '')))
                               ORDER BY c.orden, c.tienda, c.id)
                FROM (SELECT * FROM mypump_compras_pais c0
                       WHERE c0.activo AND c0.pais = v_pais AND p.clave = ANY (c0.claves)
                         AND c0.verificado_en >= (NOW() AT TIME ZONE 'America/Argentina/Buenos_Aires')::DATE - 180
                         AND c0.verificado_en <= (NOW() AT TIME ZONE 'America/Argentina/Buenos_Aires')::DATE + 1
                       ORDER BY c0.orden, c0.tienda, c0.id LIMIT 4) c) AS opciones
        FROM plan p
    ) x
   WHERE x.opciones IS NOT NULL;

  RETURN jsonb_build_object('habilitado', TRUE, 'pais', v_pais, 'items', v_items);
END;
$$;

-- ── La Mini (service_role) ──
-- Carga una opción verificada. `p_nombres`: cómo figura el suplemento en los planes (se normalizan a claves).
CREATE OR REPLACE FUNCTION mypump_compras_cargar(
  p_pais TEXT, p_nombres TEXT[], p_producto TEXT, p_tienda TEXT, p_url TEXT, p_nota TEXT,
  p_verificado_por TEXT, p_verificado_en DATE, p_orden INTEGER DEFAULT 0)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_claves TEXT[];
  v_id     UUID;
BEGIN
  SELECT COALESCE(array_agg(DISTINCT k), '{}') INTO v_claves FROM (SELECT mypump_compras_clave(n) AS k FROM unnest(COALESCE(p_nombres, '{}')) n) q WHERE k <> '';
  IF cardinality(v_claves) = 0 THEN RAISE EXCEPTION 'sin nombres de suplemento' USING ERRCODE = '22023'; END IF;
  IF p_verificado_en IS NULL OR p_verificado_en > (NOW() AT TIME ZONE 'America/Argentina/Buenos_Aires')::DATE + 1 THEN
    RAISE EXCEPTION 'fecha de verificación inválida' USING ERRCODE = '22023';
  END IF;
  INSERT INTO mypump_compras_pais (pais, claves, producto, tienda, url, nota, orden, verificado_por, verificado_en)
  VALUES (upper(btrim(p_pais)), v_claves, btrim(p_producto), btrim(p_tienda), NULLIF(btrim(p_url), ''), NULLIF(btrim(p_nota), ''),
          COALESCE(p_orden, 0), btrim(p_verificado_por), p_verificado_en)
  RETURNING id INTO v_id;
  RETURN jsonb_build_object('ok', TRUE, 'id', v_id, 'claves', to_jsonb(v_claves));
END;
$$;

-- El país del alumno, con su fuente. NULL en `p_pais` lo borra (vuelve a no ver nada).
CREATE OR REPLACE FUNCTION mypump_compras_fijar_pais(p_cliente_id TEXT, p_pais TEXT, p_fuente TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_cliente_id IS NULL OR length(btrim(p_cliente_id)) = 0 THEN RAISE EXCEPTION 'sin cliente' USING ERRCODE = '22023'; END IF;
  IF p_pais IS NULL THEN
    DELETE FROM mypump_cliente_pais WHERE cliente_id = p_cliente_id;
    RETURN jsonb_build_object('ok', TRUE, 'pais', NULL);
  END IF;
  INSERT INTO mypump_cliente_pais (cliente_id, pais, fuente) VALUES (p_cliente_id, upper(btrim(p_pais)), btrim(p_fuente))
  ON CONFLICT (cliente_id) DO UPDATE SET pais = EXCLUDED.pais, fuente = EXCLUDED.fuente, actualizado_en = NOW();
  RETURN jsonb_build_object('ok', TRUE, 'pais', upper(btrim(p_pais)));
END;
$$;

REVOKE ALL ON FUNCTION mypump_compras_clave(TEXT), mypump_compras_cargar(TEXT, TEXT[], TEXT, TEXT, TEXT, TEXT, TEXT, DATE, INTEGER),
  mypump_compras_fijar_pais(TEXT, TEXT, TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION mypump_compras_clave(TEXT), mypump_compras_cargar(TEXT, TEXT[], TEXT, TEXT, TEXT, TEXT, TEXT, DATE, INTEGER),
  mypump_compras_fijar_pais(TEXT, TEXT, TEXT) TO service_role;
REVOKE ALL ON FUNCTION mypump_compras_get(TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION mypump_compras_get(TEXT) TO anon, authenticated, service_role;

NOTIFY pgrst, 'reload schema';
COMMIT;
