-- 075_escrituras_idempotentes.sql
--
-- DOS ESCRITURAS QUE, REINTENTADAS, DUPLICABAN.
--
-- El Outbox de la app reintenta cuando no llega respuesta (señal mala en el
-- gimnasio). Eso es correcto — y lo hace más desde el 19-sep, cuando un
-- corte de red dejó de gastar intentos. Pero dos RPC no eran idempotentes y
-- un reintento tras una respuesta perdida creaba una segunda fila:
--
--   · mypump_iniciar_sesion: INSERT a secas. Dos sesiones para el mismo
--     (cliente, rutina, día, semana), las series repartidas entre las dos,
--     duración y tonelaje del día partidos. La app ya preguntaba antes con
--     mypump_get_sesion_dia, pero si ESA consulta se caía por red, leía
--     "no existe" y creaba otra.
--   · mypump_agregar_comentario (el chat con Mati): INSERT a secas. Un
--     mensaje que llegó pero cuya respuesta se perdió se reenviaba hasta 8
--     veces: Mati (y la IA del chat, que contesta cada uno) recibía
--     duplicados.
--
-- QUÉ HACE. Las dos devuelven lo que YA existe cuando la escritura es la
-- misma: la sesión abierta (o cerrada) de ese día y semana, y el mismo
-- mensaje del mismo cliente en los últimos 2 minutos. Misma firma, mismo
-- tipo de retorno, mismos GRANT (CREATE OR REPLACE los conserva).
BEGIN;

-- ── 1. Una sesión por (cliente, rutina, día, semana) ─────────────────────
CREATE OR REPLACE FUNCTION mypump_iniciar_sesion(
  p_token  TEXT,
  p_dia_id TEXT,
  p_semana INTEGER
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_cliente_id TEXT;
  v_rutina_id  UUID;
  v_sesion_id  UUID;
BEGIN
  v_cliente_id := mypump_get_cliente_id_from_token(p_token);
  IF v_cliente_id IS NULL THEN RETURN NULL; END IF;

  SELECT id INTO v_rutina_id
  FROM mypump_rutinas
  WHERE cliente_id = v_cliente_id AND estado = 'activa';
  IF v_rutina_id IS NULL THEN RETURN NULL; END IF;

  -- Idempotente (075): si ya hay una sesión de este día y semana en esta
  -- rutina, es ESA. La más reciente, por si el histórico ya traía dobles.
  SELECT id INTO v_sesion_id
  FROM mypump_sesiones
  WHERE cliente_id = v_cliente_id
    AND rutina_id  = v_rutina_id
    AND dia_id     = p_dia_id
    AND semana IS NOT DISTINCT FROM p_semana
  ORDER BY iniciada_en DESC
  LIMIT 1;
  IF v_sesion_id IS NOT NULL THEN RETURN v_sesion_id; END IF;

  INSERT INTO mypump_sesiones (cliente_id, rutina_id, dia_id, semana)
  VALUES (v_cliente_id, v_rutina_id, p_dia_id, p_semana)
  RETURNING id INTO v_sesion_id;

  RETURN v_sesion_id;
END;
$$;

-- ── 2. El mismo mensaje dos veces en 2 minutos es UN mensaje ─────────────
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

  -- Idempotente (075): un reintento del Outbox tras una respuesta perdida
  -- manda el MISMO texto al MISMO hilo segundos después. Se devuelve el que
  -- ya está. Dos minutos: más que el backoff máximo del Outbox (30 s × 3) y
  -- menos de lo que tarda una persona en querer repetir algo a propósito.
  SELECT id INTO v_id
  FROM mypump_comentarios
  WHERE cliente_id = v_cliente_id
    AND autor      = 'cliente'
    AND ambito     = p_ambito
    AND referencia_id IS NOT DISTINCT FROM p_referencia_id
    AND contenido  = p_contenido
    AND created_at >= NOW() - INTERVAL '2 minutes'
  ORDER BY created_at DESC
  LIMIT 1;
  IF v_id IS NOT NULL THEN RETURN v_id; END IF;

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

-- ── El guardarraíl de la 063 ────────────────────────────────────────────
DO $guard$
DECLARE v_dupes text;
BEGIN
  SELECT string_agg(proname || ' (' || n || ' firmas)', ', ') INTO v_dupes
  FROM (SELECT p.proname, count(*) AS n
        FROM pg_proc p JOIN pg_namespace ns ON ns.oid = p.pronamespace
        WHERE ns.nspname = 'public' AND p.proname LIKE 'mypump%'
        GROUP BY p.proname HAVING count(*) > 1) d;
  IF v_dupes IS NOT NULL THEN
    RAISE EXCEPTION 'Funciones mypump duplicadas, PostgREST va a tirar PGRST203: %', v_dupes;
  END IF;
END
$guard$;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ============================================================
-- ROLLBACK (manual): re-aplicar mypump_iniciar_sesion de la 001 y
-- mypump_agregar_comentario de la 018 tal cual están en el repo.
-- ============================================================
