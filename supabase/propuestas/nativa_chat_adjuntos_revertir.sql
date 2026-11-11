-- Reverso de nativa_chat_adjuntos.sql, EN ESTE ORDEN:
--   1. Cortar, con los endpoints vivos:   nativa_chat_adjuntos_revertir_1_cortar.sql
--   2. Descargar el procesador de la Mini: launchctl bootout gui/$(id -u)/com.pump.chatadjuntos
--      && rm ~/Library/LaunchAgents/com.pump.chatadjuntos.plist   (sin borrar el plist vuelve a cargar al reiniciar)
--   3. Sacar las rutas /chat/* de mini-vision/server.mjs y reiniciar el servicio.
--   4. Este archivo. Los mensajes con adjunto QUEDAN en el chat (la base solo crece): pierden la columna `adjunto` y se
--      ven como el texto que ya tienen («Foto», «Audio de 0:42»). La transcripción y la descripción se pierden con la
--      tabla: si Mati las quiere guardar, exportarlas antes (SELECT comentario_id, texto_interno FROM mypump_chat_adjuntos).
--   5. Vaciar y borrar el bucket:         node nativa_chat_adjuntos_vaciar.mjs vaciar --confirmar && … bucket --confirmar
BEGIN;

-- Las dos del chat del alumno vuelven a la definición de nativa_005 (sin `adjunto`).
DROP FUNCTION IF EXISTS public.mypump_get_chat(text, timestamp with time zone, integer);
CREATE FUNCTION public.mypump_get_chat(p_token text, p_antes timestamp with time zone DEFAULT NULL::timestamp with time zone, p_limite integer DEFAULT 30)
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

DROP FUNCTION IF EXISTS public.mypump_chat_nuevos(text, timestamp with time zone);
CREATE FUNCTION public.mypump_chat_nuevos(p_token text, p_desde timestamp with time zone)
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

REVOKE ALL ON FUNCTION public.mypump_get_chat(text, timestamp with time zone, integer), public.mypump_chat_nuevos(text, timestamp with time zone) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.mypump_get_chat(text, timestamp with time zone, integer) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.mypump_chat_nuevos(text, timestamp with time zone) TO anon, authenticated, service_role;

DROP FUNCTION IF EXISTS mypump_chat_adjunto_purgado(UUID);
DROP FUNCTION IF EXISTS mypump_chat_adjuntos_para_purgar(INTEGER, INTEGER);
DROP FUNCTION IF EXISTS mypump_chat_adjunto_guardar(UUID, TEXT, TEXT, TEXT, JSONB, INTEGER);
DROP FUNCTION IF EXISTS mypump_chat_adjunto_tomar();
DROP FUNCTION IF EXISTS mypump_chat_adjuntos_paths(TEXT, UUID[]);
DROP FUNCTION IF EXISTS mypump_chat_adjunto_registrar(TEXT, UUID, TEXT, TEXT, TEXT, INTEGER, REAL);
DROP FUNCTION IF EXISTS mypump_chat_adjunto_puede(TEXT, UUID);
DROP FUNCTION IF EXISTS mypump_chat_adjuntos_estado(TEXT);
DROP FUNCTION IF EXISTS mypump_chat_adjuntos_habilitado(TEXT);
DROP TABLE IF EXISTS mypump_chat_adjuntos_habilitados;
DROP TABLE IF EXISTS mypump_chat_adjuntos;
ALTER TABLE public.mypump_comentarios DROP COLUMN IF EXISTS adjunto;
DELETE FROM mypump_app_config WHERE clave IN ('chat_adjuntos', 'chat_adjuntos_para_todos');
DROP POLICY IF EXISTS "coach lee chat-adjuntos" ON storage.objects;
NOTIFY pgrst, 'reload schema';
COMMIT;
