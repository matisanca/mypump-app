-- ============================================================
-- 012 — Catálogo de ejercicios con imágenes (concéntrica + excéntrica)
-- ============================================================
-- Tabla compartida (no es por cliente) con metadata de cada ejercicio
-- del catálogo free-exercise-db (https://github.com/yuhonas/free-exercise-db,
-- licencia CC0). Las imágenes viven en Supabase Storage bucket
-- "exercise-images" (público).
--
-- Cerebro consulta esta tabla al publicar una rutina para matchear cada
-- ejercicio de la dieta con su par de imágenes (inicio + pico).
-- ============================================================

-- Extensión necesaria para fuzzy match por nombre (trigram similarity)
CREATE EXTENSION IF NOT EXISTS pg_trgm;

CREATE TABLE IF NOT EXISTS mypump_ejercicios_catalogo (
  id                UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  slug_en           TEXT        UNIQUE NOT NULL,   -- "Barbell_Bench_Press" (id en free-exercise-db)
  name_en           TEXT        NOT NULL,          -- "Barbell Bench Press"
  name_normalized   TEXT        NOT NULL,          -- lowercased + sin tildes + sin paréntesis para matching
  primary_muscle    TEXT,                          -- "chest" | "back" | "quadriceps" | etc.
  equipment         TEXT,                          -- "barbell" | "dumbbell" | "machine" | "bodyweight" | etc.
  mechanic          TEXT,                          -- "compound" | "isolation"
  force             TEXT,                          -- "push" | "pull" | "static"
  image_eccentric   TEXT        NOT NULL,          -- URL pública en Storage (frame 0: posición inicial)
  image_concentric  TEXT        NOT NULL,          -- URL pública (frame 1: pico del movimiento)
  aliases_es        TEXT[]      NOT NULL DEFAULT '{}',  -- traducciones/variantes en español precomputadas
  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Índice trigram para fuzzy match rápido contra name_normalized
CREATE INDEX IF NOT EXISTS idx_catalogo_name_trgm
  ON mypump_ejercicios_catalogo USING gin (name_normalized gin_trgm_ops);

-- Índice GIN sobre el array de aliases (para `WHERE aliases_es && ARRAY[...]`)
CREATE INDEX IF NOT EXISTS idx_catalogo_aliases
  ON mypump_ejercicios_catalogo USING gin (aliases_es);

-- RLS: lectura pública (catálogo compartido), escritura solo admin (Cerebro)
ALTER TABLE mypump_ejercicios_catalogo ENABLE ROW LEVEL SECURITY;

CREATE POLICY "read_all_catalogo"
  ON mypump_ejercicios_catalogo FOR SELECT
  USING (true);

CREATE POLICY "admin_write_catalogo"
  ON mypump_ejercicios_catalogo FOR ALL
  USING (auth.role() = 'authenticated')
  WITH CHECK (auth.role() = 'authenticated');

-- ============================================================
-- RPC: matching fuzzy por nombre (consulta del español al catálogo en inglés)
-- ============================================================
-- Estrategia:
--   1) Normalizar input (lowercase, sin tildes, sin paréntesis, sin números de día/serie)
--   2) Buscar exact match en aliases_es
--   3) Si no, similarity contra name_normalized + aliases concatenados
--   4) Devolver top 5 con score (0..1)
-- ============================================================
CREATE OR REPLACE FUNCTION mypump_match_ejercicio_por_nombre(p_query TEXT)
RETURNS TABLE (
  slug_en          TEXT,
  name_en          TEXT,
  image_eccentric  TEXT,
  image_concentric TEXT,
  score            REAL
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_norm TEXT;
BEGIN
  -- Normalización básica del input. Replicada (con menos features) del lado JS
  -- del script bootstrap. Más detalle abajo:
  --   • lowercase
  --   • quitar tildes/acentos (translate a-z plana)
  --   • quitar texto entre paréntesis "(grosor dorsal)" → ""
  --   • quitar sufijos típicos "-d1-0" del id generado por slugify
  --   • colapsar espacios múltiples
  v_norm := lower(coalesce(p_query, ''));
  v_norm := translate(v_norm,
    'áéíóúàèìòùäëïöüâêîôûãõñç',
    'aeiouaeiouaeiouaeiouaonc'
  );
  v_norm := regexp_replace(v_norm, '\(.*?\)',   ' ', 'g');   -- paréntesis fuera
  v_norm := regexp_replace(v_norm, '-d\d+-\d+', ' ', 'g');   -- sufijos slug
  v_norm := regexp_replace(v_norm, '[^a-z0-9 ]+', ' ', 'g'); -- solo alfanumérico
  v_norm := regexp_replace(v_norm, '\s+', ' ', 'g');         -- colapsar espacios
  v_norm := trim(v_norm);
  IF v_norm = '' THEN RETURN; END IF;

  RETURN QUERY
    WITH base AS (
      SELECT
        c.slug_en, c.name_en, c.image_eccentric, c.image_concentric,
        -- 1) Match exacto en aliases_es: score = 1.0
        CASE WHEN v_norm = ANY(c.aliases_es) THEN 1.0::REAL ELSE NULL END AS alias_score,
        -- 2) Trigram similarity contra name_normalized
        similarity(c.name_normalized, v_norm) AS name_score,
        -- 3) Mejor trigram similarity contra cualquier alias
        (SELECT max(similarity(unnest_alias, v_norm))
         FROM unnest(c.aliases_es) AS unnest_alias) AS best_alias_score
      FROM mypump_ejercicios_catalogo c
    )
    SELECT
      b.slug_en, b.name_en, b.image_eccentric, b.image_concentric,
      GREATEST(
        coalesce(b.alias_score, 0),
        coalesce(b.best_alias_score, 0),
        coalesce(b.name_score, 0)
      )::REAL AS score
    FROM base b
    WHERE GREATEST(
      coalesce(b.alias_score, 0),
      coalesce(b.best_alias_score, 0),
      coalesce(b.name_score, 0)
    ) > 0.25
    ORDER BY score DESC
    LIMIT 5;
END;
$$;

-- Cerebro (authenticated) lo llama al publicar. anon también puede llamarlo
-- para consultas del catálogo desde la app (futuro: cliente busca un ejercicio).
GRANT EXECUTE ON FUNCTION mypump_match_ejercicio_por_nombre(TEXT) TO anon;
GRANT EXECUTE ON FUNCTION mypump_match_ejercicio_por_nombre(TEXT) TO authenticated;

-- ============================================================
-- RPC admin: setear las imágenes de un ejercicio específico de una rutina
-- ============================================================
-- Path tipo: [dia_idx, bloque_idx, ejercicio_idx] (indices numéricos en el JSONB).
-- Cerebro la llama desde la vista admin de revisión de matches.
-- ============================================================
CREATE OR REPLACE FUNCTION mypump_set_ejercicio_imagen(
  p_rutina_id     UUID,
  p_dia_idx       INTEGER,
  p_bloque_idx    INTEGER,
  p_ejercicio_idx INTEGER,
  p_slug_en       TEXT      -- slug del catálogo (NULL = limpiar imágenes)
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_image_ec TEXT;
  v_image_co TEXT;
  v_new_imgs JSONB;
  v_path TEXT[];
BEGIN
  IF auth.role() <> 'authenticated' THEN
    RAISE EXCEPTION 'Acceso denegado';
  END IF;

  IF p_slug_en IS NULL THEN
    v_new_imgs := 'null'::jsonb;
  ELSE
    SELECT image_eccentric, image_concentric
      INTO v_image_ec, v_image_co
      FROM mypump_ejercicios_catalogo
     WHERE slug_en = p_slug_en;

    IF v_image_ec IS NULL THEN
      RAISE EXCEPTION 'Ejercicio del catálogo no encontrado: %', p_slug_en;
    END IF;

    v_new_imgs := jsonb_build_object(
      'eccentric',  v_image_ec,
      'concentric', v_image_co
    );
  END IF;

  v_path := ARRAY['dias', p_dia_idx::TEXT, 'bloques', p_bloque_idx::TEXT, 'ejercicios', p_ejercicio_idx::TEXT, 'images'];

  UPDATE mypump_rutinas
     SET estructura = jsonb_set(estructura, v_path, v_new_imgs, true)
   WHERE id = p_rutina_id;

  RETURN FOUND;
END;
$$;

GRANT EXECUTE ON FUNCTION mypump_set_ejercicio_imagen(UUID, INTEGER, INTEGER, INTEGER, TEXT) TO authenticated;
