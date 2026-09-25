-- 070_activar_archiva_sesiones.sql
--
-- mypump_activar_siguiente archiva las sesiones del bloque anterior.
--
-- Bug (visto en Emmanuel Matoff, 11-sep-2026): la app busca las sesiones por
-- (cliente_id, dia_id, semana) con la semana LOCAL del bloque. activar_siguiente
-- resetea semana_actual a 1 sobre la misma fila, asi que las sesiones de la
-- semana 1 del bloque anterior aparecen como "dia cerrado" del bloque nuevo, y
-- los ejercicios que conservan id se ven marcados como hechos.
--
-- Arreglo: al activar, se corren las sesiones previas fuera del rango de semanas
-- (semana - 100). Los registros de carga cuelgan de sesion_id y el historial por
-- ejercicio y el grafico de progreso filtran por ejercicio_id y por fecha, asi que
-- no pierden nada. Misma firma: no crea una segunda funcion en PostgREST.
CREATE OR REPLACE FUNCTION public.mypump_activar_siguiente(p_token text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_cliente_id TEXT; v_sig JSONB;
BEGIN
  v_cliente_id := mypump_get_cliente_id_from_token(p_token);
  IF v_cliente_id IS NULL THEN RETURN FALSE; END IF;
  SELECT estructura_siguiente INTO v_sig FROM mypump_rutinas
   WHERE cliente_id = v_cliente_id AND estado = 'activa' LIMIT 1;
  IF v_sig IS NULL THEN RETURN FALSE; END IF;

  -- Archivar las sesiones del bloque que termina: fuera del rango 1..N.
  UPDATE mypump_sesiones
     SET semana = semana - 100
   WHERE cliente_id = v_cliente_id AND semana > 0;

  UPDATE mypump_rutinas
     SET estructura = v_sig, estructura_siguiente = NULL, semana_actual = 1,
         fecha_inicio = CURRENT_DATE,
         version = version + 1, updated_at = NOW()
   WHERE cliente_id = v_cliente_id AND estado = 'activa';
  RETURN TRUE;
END;
$function$;
