-- ============================================================
-- nativa_008 — Día de revisión por cliente (se aplica solo con el OK de Mati)
-- ============================================================
-- Hoy la revisión es de lunes a domingo para todos: el aviso local (id 1002) y el
-- pedido de la ronda salen el DOMINGO, el último día de la semana, y el lunes 00:00
-- arranca una semana nueva (semana_lunes = lunes ISO de la fecha).
--
-- `revision_dia` es el día ISO del aviso y del pedido (1 = lunes … 7 = domingo),
-- que es también el ÚLTIMO día de la semana de revisión: la semana nueva abre al
-- día siguiente a las 00:00. Default 7 = lo de hoy, sin ningún cambio.
-- Caso que lo motiva: un alumno quiere el aviso el SÁBADO y poder cargar desde el
-- DOMINGO 00:00  →  revision_dia = 6.
--
-- La clave sigue siendo un lunes (semana_lunes), para no tocar las tablas, las
-- vistas ni lo que ya lee semana_lunes (Cerebro, brief, analisis, centinela):
--     semana_lunes = lunes ISO de (fecha + (7 - revision_dia) días)
-- Con 7 es +0 (lo de hoy). Con 6 es +1: el sábado cae en la semana de su lunes y
-- el domingo ya en la del lunes siguiente. El período se ve en el panel "un día
-- antes" (el domingo de ese cliente figura con la semana que empieza el lunes).
--
-- Cambiar el día con datos cargados: hacerlo un día que NO quede entre el día
-- viejo y el nuevo (para 7 → 6, cualquier día de lunes a viernes). Si no, una
-- carga del domingo puede quedar en una semana y la del sábado en otra.
-- ============================================================

BEGIN;
SET LOCAL lock_timeout = '5s';   -- tablas chicas: si algo las tiene tomadas, falla en vez de quedar esperando

ALTER TABLE mypump_cliente_prefs
  ADD COLUMN IF NOT EXISTS revision_dia SMALLINT NOT NULL DEFAULT 7
  CHECK (revision_dia BETWEEN 1 AND 7);

COMMENT ON COLUMN mypump_cliente_prefs.revision_dia IS
  'Día ISO del aviso y del pedido de la revisión (1=lun … 7=dom), último día de la semana de revisión. Default 7.';

-- ── Interna: el día del cliente (7 sin fila) ──
CREATE OR REPLACE FUNCTION mypump_revision_dia(p_cliente_id TEXT)
RETURNS SMALLINT
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT COALESCE((SELECT revision_dia FROM mypump_cliente_prefs WHERE cliente_id = p_cliente_id), 7)::SMALLINT;
$$;
REVOKE ALL ON FUNCTION mypump_revision_dia(TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION mypump_revision_dia(TEXT) TO service_role;

-- ── Interna: la clave de la semana de revisión de esa fecha para ese cliente ──
CREATE OR REPLACE FUNCTION mypump_semana_revision(p_cliente_id TEXT, p_fecha DATE)
RETURNS DATE
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT date_trunc('week', p_fecha + (7 - mypump_revision_dia(p_cliente_id)))::DATE;
$$;
REVOKE ALL ON FUNCTION mypump_semana_revision(TEXT, DATE) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION mypump_semana_revision(TEXT, DATE) TO service_role;

-- ── Pública (app y mini-vision): el día del cliente del token. 7 si no hay token válido ──
CREATE OR REPLACE FUNCTION mypump_get_revision_dia(p_token TEXT)
RETURNS SMALLINT
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE v_cliente_id TEXT;
BEGIN
  v_cliente_id := mypump_get_cliente_id_from_token(p_token);
  IF v_cliente_id IS NULL THEN RETURN 7; END IF;
  RETURN mypump_revision_dia(v_cliente_id);
END;
$$;
REVOKE ALL ON FUNCTION mypump_get_revision_dia(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION mypump_get_revision_dia(TEXT) TO anon, authenticated, service_role;

-- ── Admin (Mati / Cerebro / scripts de la Mini con service key): NO self-service ──
CREATE OR REPLACE FUNCTION mypump_set_revision_dia(p_cliente_id TEXT, p_dia SMALLINT)
RETURNS BOOLEAN
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF p_dia IS NULL OR p_dia NOT BETWEEN 1 AND 7 THEN RAISE EXCEPTION 'revision_dia va de 1 (lunes) a 7 (domingo)'; END IF;
  IF NOT EXISTS (SELECT 1 FROM mypump_clientes WHERE cliente_id = p_cliente_id) THEN RETURN FALSE; END IF;
  INSERT INTO mypump_cliente_prefs (cliente_id, revision_dia) VALUES (p_cliente_id, p_dia)
  ON CONFLICT (cliente_id) DO UPDATE SET revision_dia = EXCLUDED.revision_dia, updated_at = NOW();
  RETURN TRUE;
END;
$$;
REVOKE ALL ON FUNCTION mypump_set_revision_dia(TEXT, SMALLINT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION mypump_set_revision_dia(TEXT, SMALLINT) TO authenticated, service_role;

-- ── El check: misma ventana (−7/+1), clave por cliente ──
-- Única línea que cambia en las dos: date_trunc('week', p_fecha) → mypump_semana_revision(v_cliente_id, p_fecha).
-- El app 2.0.2 (ya publicada) manda p_fecha = hoy del teléfono, así que el check pasa a la semana correcta SIN
-- actualizar la app (lo de la app es solo el borrador local y el banner).
CREATE OR REPLACE FUNCTION public.mypump_guardar_checkin(p_token text, p_fecha date, p_energia smallint,
  p_descanso smallint, p_hambre smallint, p_adherencia smallint, p_nota text DEFAULT NULL::text)
 RETURNS SETOF mypump_checkin_semanal
 LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  v_cliente_id TEXT; v_hoy DATE; v_lunes DATE; v_id UUID;
BEGIN
  v_cliente_id := mypump_get_cliente_id_from_token(p_token);
  IF v_cliente_id IS NULL THEN RETURN; END IF;
  v_hoy := (NOW() AT TIME ZONE 'America/Argentina/Buenos_Aires')::DATE;
  IF p_fecha > v_hoy + 1 THEN RAISE EXCEPTION 'No se puede registrar una fecha futura'; END IF;
  IF p_fecha < v_hoy - 7 THEN RAISE EXCEPTION 'Solo se permite backfill de hasta 7 dias'; END IF;

  v_lunes := mypump_semana_revision(v_cliente_id, p_fecha);   -- antes: date_trunc('week', p_fecha)

  INSERT INTO mypump_checkin_semanal (cliente_id, semana_lunes, energia, descanso, hambre, adherencia, nota)
  VALUES (v_cliente_id, v_lunes, p_energia, p_descanso, p_hambre, p_adherencia, NULLIF(trim(COALESCE(p_nota, '')), ''))
  ON CONFLICT (cliente_id, semana_lunes) DO UPDATE
    SET energia = EXCLUDED.energia, descanso = EXCLUDED.descanso, hambre = EXCLUDED.hambre,
        adherencia = EXCLUDED.adherencia, nota = EXCLUDED.nota, updated_at = NOW()
  RETURNING id INTO v_id;
  RETURN QUERY SELECT * FROM mypump_checkin_semanal WHERE id = v_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.mypump_get_checkin_semana(p_token text, p_fecha date)
 RETURNS SETOF mypump_checkin_semanal
 LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE v_cliente_id TEXT;
BEGIN
  v_cliente_id := mypump_get_cliente_id_from_token(p_token);
  IF v_cliente_id IS NULL THEN RETURN; END IF;
  RETURN QUERY SELECT * FROM mypump_checkin_semanal
    WHERE cliente_id = v_cliente_id AND semana_lunes = mypump_semana_revision(v_cliente_id, p_fecha);
END;
$function$;

-- ── La ronda: cada cliente con SU semana y su día ──
-- Cambia el tipo de retorno (suma revision_dia y semana_lunes): hay que DROP + CREATE, y recordatorios.py nuevo
-- tiene que salir junto (el viejo ignora las columnas de más, así que el orden seguro es: SQL primero, script después).
-- "Hoy" se evalúa en la hora de Argentina, como siempre. El tope cuenta desde el primer día del período del cliente.
DROP FUNCTION IF EXISTS public.mypump_chat_faltantes_semana();
CREATE FUNCTION public.mypump_chat_faltantes_semana()
 RETURNS TABLE(cliente_id text, nombre text, falta_check boolean, fotos_puestas integer, avisos_semana integer,
               ia_activa boolean, escalado boolean, silenciado boolean, revision_dia smallint, semana_lunes date)
 LANGUAGE sql SECURITY DEFINER SET search_path TO 'public'
AS $function$
  WITH hoy AS (SELECT (now() AT TIME ZONE 'America/Argentina/Buenos_Aires')::date AS d),
  cli AS (
    SELECT c.cliente_id, c.nombre, mypump_revision_dia(c.cliente_id) AS dia,
           mypump_semana_revision(c.cliente_id, hoy.d) AS lunes
    FROM mypump_clientes c, hoy
    WHERE c.access_token_active
      AND c.cliente_id NOT LIKE 'test%'
      AND lower(COALESCE(c.nombre,'')) NOT LIKE '%test%'
  )
  SELECT
    k.cliente_id, k.nombre,
    NOT EXISTS (SELECT 1 FROM mypump_checkin_semanal x WHERE x.cliente_id = k.cliente_id AND x.semana_lunes = k.lunes),
    (SELECT count(DISTINCT f.pose)::integer FROM mypump_fotos_progreso f
      WHERE f.cliente_id = k.cliente_id AND f.semana_lunes = k.lunes),
    (SELECT count(*)::integer FROM mypump_comentarios m
      WHERE m.cliente_id = k.cliente_id AND m.ambito = 'general' AND m.autor = 'coach'
        AND m.created_at >= (k.lunes - (7 - k.dia))),          -- primer día del período del cliente
    COALESCE(e.ia_activa, TRUE), COALESCE(e.escalado, FALSE), COALESCE(e.silenciado_hasta > now(), FALSE),
    k.dia::smallint, k.lunes
  FROM cli k
  LEFT JOIN mypump_chat_estado e ON e.cliente_id = k.cliente_id;
$function$;
-- El DROP borra los permisos: se reponen los vivos al 03-11 (postgres, authenticated y service_role; sin PUBLIC ni anon).
REVOKE ALL ON FUNCTION public.mypump_chat_faltantes_semana() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.mypump_chat_faltantes_semana() TO authenticated, service_role;

COMMIT;

-- ============================================================
-- Vuelta atrás: nativa_008_revert.sql (repone las tres funciones vivas al 03-11 y borra lo nuevo).
-- Orden de despliegue: 1) esta migración; 2) server.mjs de vision y recordatorios.py de la ronda (ignoran la RPC
-- si no existe, así que también pueden ir antes); 3) las apps 2.0.3, que leen mypump_get_revision_dia.
-- ============================================================
