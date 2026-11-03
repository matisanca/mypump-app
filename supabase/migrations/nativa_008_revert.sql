-- ============================================================
-- nativa_008_revert — vuelve al estado del 03-11 (antes de nativa_008)
-- Las tres funciones son las definiciones vivas leídas de producción el 03-11 (md5 verificado).
-- Los check-in ya guardados con una semana corrida quedan como están (semana_lunes sigue siendo un lunes).
-- ============================================================
BEGIN;

CREATE OR REPLACE FUNCTION public.mypump_guardar_checkin(p_token text, p_fecha date, p_energia smallint, p_descanso smallint, p_hambre smallint, p_adherencia smallint, p_nota text DEFAULT NULL::text)
 RETURNS SETOF mypump_checkin_semanal
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_cliente_id TEXT;
  v_hoy        DATE;
  v_lunes      DATE;
  v_id         UUID;
BEGIN
  v_cliente_id := mypump_get_cliente_id_from_token(p_token);
  IF v_cliente_id IS NULL THEN RETURN; END IF;

  -- Ventana tolerante a zona horaria/reloj del device (regla 020/028).
  v_hoy := (NOW() AT TIME ZONE 'America/Argentina/Buenos_Aires')::DATE;
  IF p_fecha > v_hoy + 1 THEN
    RAISE EXCEPTION 'No se puede registrar una fecha futura';
  END IF;
  IF p_fecha < v_hoy - 7 THEN
    RAISE EXCEPTION 'Solo se permite backfill de hasta 7 dias';
  END IF;

  v_lunes := date_trunc('week', p_fecha)::DATE;  -- lunes ISO de esa semana

  INSERT INTO mypump_checkin_semanal
    (cliente_id, semana_lunes, energia, descanso, hambre, adherencia, nota)
  VALUES
    (v_cliente_id, v_lunes, p_energia, p_descanso, p_hambre, p_adherencia,
     NULLIF(trim(COALESCE(p_nota, '')), ''))
  ON CONFLICT (cliente_id, semana_lunes) DO UPDATE
    SET energia    = EXCLUDED.energia,
        descanso   = EXCLUDED.descanso,
        hambre     = EXCLUDED.hambre,
        adherencia = EXCLUDED.adherencia,
        nota       = EXCLUDED.nota,
        updated_at = NOW()
  RETURNING id INTO v_id;

  RETURN QUERY SELECT * FROM mypump_checkin_semanal WHERE id = v_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.mypump_get_checkin_semana(p_token text, p_fecha date)
 RETURNS SETOF mypump_checkin_semanal
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_cliente_id TEXT;
BEGIN
  v_cliente_id := mypump_get_cliente_id_from_token(p_token);
  IF v_cliente_id IS NULL THEN RETURN; END IF;
  RETURN QUERY
    SELECT * FROM mypump_checkin_semanal
    WHERE cliente_id = v_cliente_id
      AND semana_lunes = date_trunc('week', p_fecha)::DATE;
END;
$function$;

DROP FUNCTION IF EXISTS public.mypump_chat_faltantes_semana();
CREATE OR REPLACE FUNCTION public.mypump_chat_faltantes_semana()
 RETURNS TABLE(cliente_id text, nombre text, falta_check boolean, fotos_puestas integer, avisos_semana integer, ia_activa boolean, escalado boolean, silenciado boolean)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  WITH lunes AS (SELECT (date_trunc('week', now() AT TIME ZONE 'America/Argentina/Buenos_Aires'))::date AS d)
  SELECT
    c.cliente_id,
    c.nombre,
    NOT EXISTS (SELECT 1 FROM mypump_checkin_semanal k, lunes
                 WHERE k.cliente_id = c.cliente_id AND k.semana_lunes = lunes.d),
    (SELECT count(DISTINCT f.pose)::integer FROM mypump_fotos_progreso f, lunes
      WHERE f.cliente_id = c.cliente_id AND f.semana_lunes = lunes.d),
    -- Tope duro: 3 mensajes del coach por semana. Sin esto, alguien que nunca
    -- sube nada recibiría el domingo, el martes y el jueves TODAS las semanas,
    -- y eso no es seguimiento, es hostigamiento.
    (SELECT count(*)::integer FROM mypump_comentarios m, lunes
      WHERE m.cliente_id = c.cliente_id AND m.ambito = 'general' AND m.autor = 'coach'
        AND m.created_at >= lunes.d),
    COALESCE(e.ia_activa, TRUE),
    COALESCE(e.escalado, FALSE),
    COALESCE(e.silenciado_hasta > now(), FALSE)
  FROM mypump_clientes c
  LEFT JOIN mypump_chat_estado e ON e.cliente_id = c.cliente_id
  WHERE c.access_token_active
    -- Los sintéticos del banco de pruebas no reciben mensajes. Misma red que
    -- usan el centinela y el Radar.
    AND c.cliente_id NOT LIKE 'test%'
    AND lower(COALESCE(c.nombre,'')) NOT LIKE '%test%';
$function$;
REVOKE ALL ON FUNCTION public.mypump_chat_faltantes_semana() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.mypump_chat_faltantes_semana() TO authenticated, service_role;

DROP FUNCTION IF EXISTS public.mypump_set_revision_dia(TEXT, SMALLINT);
DROP FUNCTION IF EXISTS public.mypump_get_revision_dia(TEXT);
DROP FUNCTION IF EXISTS public.mypump_semana_revision(TEXT, DATE);
DROP FUNCTION IF EXISTS public.mypump_revision_dia(TEXT);
ALTER TABLE mypump_cliente_prefs DROP COLUMN IF EXISTS revision_dia;

COMMIT;
