-- 071_activar_dias_nuevos.sql
--
-- Complemento de la 070. La app guarda en localStorage la sesion abierta por
-- dia con la clave mypump_sesion_<token>_<dia.id>, y si la semana guardada
-- coincide con semana_actual la restaura tal cual. Emmanuel Matoff (11-sep)
-- abrio el dia fantasma, toco "cerrar dia" y el telefono le fijo la sesion
-- de junio como la de hoy: limpiar el servidor no alcanzaba.
--
-- Arreglo: al activar, cada dia del bloque nuevo recibe un id propio
-- ("b<version>d<n>"). Con eso la clave local no existe, get_sesion_dia no
-- encuentra nada viejo, y no hace falta que el cliente borre datos.
-- El id del dia solo es una clave (localStorage, outbox, dia_id de sesiones
-- y registros); el historial por ejercicio y el grafico no lo miran.
CREATE OR REPLACE FUNCTION public.mypump_activar_siguiente(p_token text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_cliente_id TEXT; v_sig JSONB; v_ver INT; v_dias JSONB;
BEGIN
  v_cliente_id := mypump_get_cliente_id_from_token(p_token);
  IF v_cliente_id IS NULL THEN RETURN FALSE; END IF;
  SELECT estructura_siguiente, version INTO v_sig, v_ver FROM mypump_rutinas
   WHERE cliente_id = v_cliente_id AND estado = 'activa' LIMIT 1;
  IF v_sig IS NULL THEN RETURN FALSE; END IF;

  -- Dias con id propio del bloque: b<version nueva>d<n>
  SELECT jsonb_agg(
           jsonb_set(d, '{id}', to_jsonb('b' || (v_ver + 1)::text || 'd' || COALESCE(d->>'n', (ord)::text)))
           ORDER BY ord)
    INTO v_dias
    FROM jsonb_array_elements(v_sig->'dias') WITH ORDINALITY AS t(d, ord);
  IF v_dias IS NOT NULL THEN
    v_sig := jsonb_set(v_sig, '{dias}', v_dias);
  END IF;

  -- Archivar las sesiones del bloque que termina: fuera del rango 1..N.
  UPDATE mypump_sesiones
     SET semana = semana - 100
   WHERE cliente_id = v_cliente_id AND semana > 0;

  UPDATE mypump_rutinas
     SET estructura = v_sig, estructura_siguiente = NULL, semana_actual = 1,
         fecha_inicio = CURRENT_DATE,
         version = v_ver + 1, updated_at = NOW()
   WHERE cliente_id = v_cliente_id AND estado = 'activa';
  RETURN TRUE;
END;
$function$;
