-- ============================================================
-- 018 — Comentarios bidireccionales coach ↔ cliente
-- ============================================================
-- Notas manuales ancladas a un ejercicio / día / rutina / dieta / comida /
-- generales. El cliente deja notas ("hice plano con mancuernas porque la
-- máquina estaba ocupada") y ve las que le deja el coach, y viceversa.
--
-- Tabla APARTE keyeada por (cliente_id, referencia_id): así los comentarios
-- SOBREVIVEN a la republicación de la rutina (mypump_publicar_cliente hace
-- UPDATE de estructura; los comentarios no se tocan).
--
-- ⚠️ TODO IMPORTANTE: referencia_id para 'ejercicio' es ejercicio.id, que en
--    expandirRutinaParaMyPump se genera como `${slugify(ej)}-d{dia}-{idx}`.
--    Ese id embebe día+índice, así que si cambia el orden/nombre del ejercicio
--    entre versiones, los comentarios viejos quedan huérfanos (referencia_id no
--    matchea). Por eso guardamos referencia_nombre como snapshot (no se pierde
--    el contexto). MANTENER ejercicio.id estable entre versiones para no
--    huérfanar comentarios (idealmente un id propio por slot, no derivado del
--    índice). NO se modifica mypump_publicar_cliente en esta migración.
-- ============================================================

CREATE TABLE IF NOT EXISTS mypump_comentarios (
  id                 UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  cliente_id         TEXT        NOT NULL,
  ambito             TEXT        NOT NULL CHECK (ambito IN ('ejercicio','dia','rutina','dieta','comida','general')),
  referencia_id      TEXT,                          -- p.ej. ejercicio.id ('press-banca-d1-0')
  referencia_nombre  TEXT,                          -- snapshot del nombre (evita perder contexto si el id cambia)
  autor              TEXT        NOT NULL CHECK (autor IN ('cliente','coach')),
  contenido          TEXT        NOT NULL,
  leido_por_cliente  BOOLEAN     NOT NULL DEFAULT FALSE,
  leido_por_coach    BOOLEAN     NOT NULL DEFAULT FALSE,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at         TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_mypump_comentarios_ref
  ON mypump_comentarios (cliente_id, ambito, referencia_id);

-- RLS: deny-all. Todo acceso público pasa por las RPC SECURITY DEFINER (que
-- bypassean RLS). Solo authenticated (Cerebro/Mati) puede tocar la tabla directo.
ALTER TABLE mypump_comentarios ENABLE ROW LEVEL SECURITY;

CREATE POLICY "admin all mypump_comentarios"
  ON mypump_comentarios FOR ALL
  USING (auth.role() = 'authenticated')
  WITH CHECK (auth.role() = 'authenticated');

-- ============================================================
-- RPC PÚBLICAS — anon, token como credencial (igual que el resto del schema).
-- SECURITY DEFINER: bypassean RLS y validan el token internamente.
-- ============================================================

-- Inserta un comentario del CLIENTE. autor='cliente', ya leído por él,
-- pendiente para el coach. Devuelve el id, o NULL si el token es inválido.
CREATE OR REPLACE FUNCTION mypump_agregar_comentario(
  p_token             TEXT,
  p_ambito            TEXT,
  p_referencia_id     TEXT,
  p_referencia_nombre TEXT,
  p_contenido         TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_cliente_id TEXT;
  v_id         UUID;
BEGIN
  v_cliente_id := mypump_get_cliente_id_from_token(p_token);
  IF v_cliente_id IS NULL THEN RETURN NULL; END IF;
  IF p_contenido IS NULL OR length(trim(p_contenido)) = 0 THEN RETURN NULL; END IF;

  INSERT INTO mypump_comentarios
    (cliente_id, ambito, referencia_id, referencia_nombre, autor, contenido,
     leido_por_cliente, leido_por_coach)
  VALUES
    (v_cliente_id, p_ambito, p_referencia_id, p_referencia_nombre, 'cliente', p_contenido,
     TRUE, FALSE)
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

-- Devuelve los comentarios del cliente del token, opcionalmente filtrados por
-- ámbito y/o referencia. Orden cronológico (created_at ASC).
CREATE OR REPLACE FUNCTION mypump_get_comentarios(
  p_token         TEXT,
  p_ambito        TEXT DEFAULT NULL,
  p_referencia_id TEXT DEFAULT NULL
)
RETURNS TABLE(
  id                 UUID,
  ambito             TEXT,
  referencia_id      TEXT,
  referencia_nombre  TEXT,
  autor              TEXT,
  contenido          TEXT,
  leido_por_cliente  BOOLEAN,
  leido_por_coach    BOOLEAN,
  created_at         TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_cliente_id TEXT;
BEGIN
  v_cliente_id := mypump_get_cliente_id_from_token(p_token);
  IF v_cliente_id IS NULL THEN RETURN; END IF;

  RETURN QUERY
  SELECT c.id, c.ambito, c.referencia_id, c.referencia_nombre, c.autor,
         c.contenido, c.leido_por_cliente, c.leido_por_coach, c.created_at
  FROM mypump_comentarios c
  WHERE c.cliente_id = v_cliente_id
    AND (p_ambito IS NULL OR c.ambito = p_ambito)
    AND (p_referencia_id IS NULL OR c.referencia_id = p_referencia_id)
  ORDER BY c.created_at ASC;
END;
$$;

-- Marca como leídos por el cliente los comentarios del COACH (opcionalmente
-- filtrados por ámbito/referencia). Devuelve cuántos se marcaron.
CREATE OR REPLACE FUNCTION mypump_marcar_leidos_cliente(
  p_token         TEXT,
  p_ambito        TEXT DEFAULT NULL,
  p_referencia_id TEXT DEFAULT NULL
)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_cliente_id TEXT;
  v_count      INTEGER;
BEGIN
  v_cliente_id := mypump_get_cliente_id_from_token(p_token);
  IF v_cliente_id IS NULL THEN RETURN 0; END IF;

  WITH upd AS (
    UPDATE mypump_comentarios
       SET leido_por_cliente = TRUE, updated_at = NOW()
     WHERE cliente_id = v_cliente_id
       AND autor = 'coach'
       AND leido_por_cliente = FALSE
       AND (p_ambito IS NULL OR ambito = p_ambito)
       AND (p_referencia_id IS NULL OR referencia_id = p_referencia_id)
    RETURNING 1
  )
  SELECT count(*) INTO v_count FROM upd;

  RETURN v_count;
END;
$$;

-- ============================================================
-- RPC ADMIN — la llama NutriPlan/Cerebro (sin token de cliente).
-- Inserta un comentario del COACH (pendiente de leer por el cliente).
-- ============================================================
CREATE OR REPLACE FUNCTION mypump_coach_comentar(
  p_cliente_id        TEXT,
  p_ambito            TEXT,
  p_referencia_id     TEXT,
  p_referencia_nombre TEXT,
  p_contenido         TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id UUID;
BEGIN
  -- Solo roles confiables (Cerebro autentica como 'authenticated'; un proceso
  -- backend usaría 'service_role'). anon nunca recibe EXECUTE (ver GRANTs).
  IF auth.role() NOT IN ('authenticated', 'service_role') THEN
    RAISE EXCEPTION 'Acceso denegado';
  END IF;
  IF p_contenido IS NULL OR length(trim(p_contenido)) = 0 THEN RETURN NULL; END IF;

  INSERT INTO mypump_comentarios
    (cliente_id, ambito, referencia_id, referencia_nombre, autor, contenido,
     leido_por_cliente, leido_por_coach)
  VALUES
    (p_cliente_id, p_ambito, p_referencia_id, p_referencia_nombre, 'coach', p_contenido,
     FALSE, TRUE)
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

-- ============================================================
-- GRANTS
-- ============================================================
-- Públicas (anon, token como credencial)
GRANT EXECUTE ON FUNCTION mypump_agregar_comentario(TEXT, TEXT, TEXT, TEXT, TEXT) TO anon;
GRANT EXECUTE ON FUNCTION mypump_get_comentarios(TEXT, TEXT, TEXT)                TO anon;
GRANT EXECUTE ON FUNCTION mypump_marcar_leidos_cliente(TEXT, TEXT, TEXT)          TO anon;

-- Admin. La spec pide service_role; agregamos authenticated también porque
-- Cerebro se loguea como 'authenticated' (igual que mypump_publicar_cliente).
-- Si querés service_role-only, quitá la línea de authenticated.
GRANT EXECUTE ON FUNCTION mypump_coach_comentar(TEXT, TEXT, TEXT, TEXT, TEXT) TO service_role;
GRANT EXECUTE ON FUNCTION mypump_coach_comentar(TEXT, TEXT, TEXT, TEXT, TEXT) TO authenticated;
