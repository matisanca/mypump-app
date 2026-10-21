-- =============================================================================
-- nativa_005 — ocultar los recordatorios apilados en el chat (Mati, 20-oct-2026)
--
-- Mati: «queda muy bot cuando se acumulan varios mensajes de nuestro lado sin
-- respuesta… borrá las acumulaciones así queda limpia la conver». El 20-oct, 58
-- de 86 chats terminaban con 3 o más mensajes nuestros sin respuesta, casi todos
-- recordatorios de Revisión de la ronda (recordatorios.py: domingo, martes y
-- jueves, hasta 13 por mes). La ronda ya cambió (domingo y miércoles, nunca más
-- de dos nuestros seguidos sin respuesta); esto limpia lo que quedó apilado.
--
-- NO SE BORRA NADA. La base solo crece: los mensajes quedan en la tabla con
-- `oculto = true` y la marca en `meta.oculto` (cuándo, por qué). Lo que cambia es
-- qué se muestra:
--   · el chat del cliente (web, iPhone y Android): mypump_get_chat,
--     mypump_chat_nuevos y mypump_get_comentarios ya no los devuelven;
--   · la tarjeta de la semana del Cerebro: mypump_chat_semana tampoco.
-- La bandeja y el hilo del Cerebro leen la tabla directo y filtran `oculto` en
-- su propio código.
--
-- QUÉ SE OCULTA: en el chat general de cada cliente, cada tramo de mensajes
-- nuestros entre dos mensajes suyos deja visible SOLO el recordatorio automático
-- más nuevo (origen 'sistema'). Las respuestas de la IA y los mensajes de Mati no
-- se tocan, ni nada de lo que escribió el cliente.
--
-- Volver atrás: UPDATE mypump_comentarios SET oculto = false
--               WHERE meta->'oculto'->>'por' = 'nativa_005';
-- =============================================================================

BEGIN;

ALTER TABLE public.mypump_comentarios
  ADD COLUMN IF NOT EXISTS oculto boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.mypump_comentarios.oculto IS
  'No se muestra en el chat (cliente ni Cerebro). La fila no se borra: la marca y el motivo van en meta.oculto (nativa_005).';

-- ── El chat del cliente ──────────────────────────────────────────────────────
-- Las mismas funciones que en producción al 20-oct (pg_get_functiondef), con el
-- filtro `NOT c.oculto`. Mismas firmas: CREATE OR REPLACE alcanza.

CREATE OR REPLACE FUNCTION public.mypump_get_chat(p_token text, p_antes timestamp with time zone DEFAULT NULL::timestamp with time zone, p_limite integer DEFAULT 30)
 RETURNS TABLE(id uuid, autor text, contenido text, leido_por_cliente boolean, created_at timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_cliente_id TEXT;
  v_limite     INTEGER;
BEGIN
  v_cliente_id := mypump_get_cliente_id_from_token(p_token);
  IF v_cliente_id IS NULL THEN RETURN; END IF;

  -- Tope defensivo: la función es anon y el límite viene del cliente.
  v_limite := LEAST(GREATEST(COALESCE(p_limite, 30), 1), 100);

  RETURN QUERY
  SELECT c.id, c.autor, c.contenido, c.leido_por_cliente, c.created_at
  FROM mypump_comentarios c
  WHERE c.cliente_id = v_cliente_id
    AND c.ambito = 'general'
    AND NOT c.oculto   -- nativa_005: los recordatorios apilados no se muestran
    AND (p_antes IS NULL OR c.created_at < p_antes)
  ORDER BY c.created_at DESC
  LIMIT v_limite;
END;
$function$;

CREATE OR REPLACE FUNCTION public.mypump_chat_nuevos(p_token text, p_desde timestamp with time zone)
 RETURNS TABLE(id uuid, autor text, contenido text, created_at timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_cliente_id TEXT;
BEGIN
  v_cliente_id := mypump_get_cliente_id_from_token(p_token);
  IF v_cliente_id IS NULL THEN RETURN; END IF;

  RETURN QUERY
  SELECT c.id, c.autor, c.contenido, c.created_at
  FROM mypump_comentarios c
  WHERE c.cliente_id = v_cliente_id
    AND c.ambito = 'general'
    AND NOT c.oculto   -- nativa_005
    AND c.created_at > COALESCE(p_desde, NOW() - INTERVAL '30 days')
  ORDER BY c.created_at ASC
  LIMIT 50;
END;
$function$;

CREATE OR REPLACE FUNCTION public.mypump_get_comentarios(p_token text, p_ambito text DEFAULT NULL::text, p_referencia_id text DEFAULT NULL::text)
 RETURNS TABLE(id uuid, ambito text, referencia_id text, referencia_nombre text, autor text, contenido text, leido_por_cliente boolean, leido_por_coach boolean, created_at timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_cliente_id TEXT;
BEGIN
  v_cliente_id := mypump_get_cliente_id_from_token(p_token);
  IF v_cliente_id IS NULL THEN RETURN; END IF;
  RETURN QUERY
  SELECT c.id,c.ambito,c.referencia_id,c.referencia_nombre,c.autor,c.contenido,c.leido_por_cliente,c.leido_por_coach,c.created_at
  FROM mypump_comentarios c
  WHERE c.cliente_id=v_cliente_id
    AND NOT c.oculto   -- nativa_005
    AND (p_ambito IS NULL OR c.ambito=p_ambito)
    AND (p_referencia_id IS NULL OR c.referencia_id=p_referencia_id)
  ORDER BY c.created_at ASC;
END; $function$;

-- ── La tarjeta de la semana del Cerebro ──────────────────────────────────────

CREATE OR REPLACE FUNCTION public.mypump_chat_semana(p_cliente_id text, p_semana date DEFAULT NULL::date)
 RETURNS TABLE(autor text, contenido text, origen text, created_at timestamp with time zone)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT m.autor, m.contenido, m.origen, m.created_at
  FROM mypump_comentarios m
  WHERE m.cliente_id = p_cliente_id
    AND m.ambito = 'general'
    AND NOT m.oculto   -- nativa_005
    AND m.created_at >= COALESCE(p_semana,
          (date_trunc('week', now() AT TIME ZONE 'America/Argentina/Buenos_Aires'))::date)
    AND m.created_at < COALESCE(p_semana,
          (date_trunc('week', now() AT TIME ZONE 'America/Argentina/Buenos_Aires'))::date) + 7
  -- El `, m.id` desempata. Dos mensajes con el MISMO created_at ordenarian
  -- distinto en cada llamada, y el panel mostraria la conversacion en un orden
  -- que cambia al refrescar. Pasa poco, pero cuando pasa se ve como un bug de
  -- la app y no hay forma de reproducirlo.
  ORDER BY m.created_at, m.id
  LIMIT 200;
$function$;

-- ── Lo apilado ───────────────────────────────────────────────────────────────
-- `tramo` cuenta los mensajes del cliente hasta cada fila: los nuestros que
-- quedan entre dos suyos comparten tramo. En cada tramo queda visible el
-- recordatorio automático más nuevo; los anteriores se ocultan.

WITH m AS (
  SELECT id, cliente_id, autor, origen, created_at,
         count(*) FILTER (WHERE autor = 'cliente')
           OVER (PARTITION BY cliente_id ORDER BY created_at, id) AS tramo
  FROM mypump_comentarios
  WHERE ambito = 'general'
), r AS (
  SELECT id,
         row_number() OVER (PARTITION BY cliente_id, tramo ORDER BY created_at DESC, id DESC) AS desde_el_ultimo
  FROM m
  WHERE autor = 'coach' AND origen = 'sistema'
)
UPDATE mypump_comentarios c
   SET oculto = true,
       meta = COALESCE(c.meta, '{}'::jsonb) || jsonb_build_object('oculto', jsonb_build_object(
                'en', now(), 'por', 'nativa_005', 'motivo', 'recordatorio apilado sin respuesta'))
  FROM r
 WHERE c.id = r.id
   AND r.desde_el_ultimo > 1
   AND NOT c.oculto;

NOTIFY pgrst, 'reload schema';

COMMIT;
