-- PROPUESTA, sin aplicar. Para aplicar hace falta el OK de Mati (compuerta G2).
--
-- Por qué: las apps ya dejan cargar en Dieta hasta 7 días atrás, pero `mypump_marcar_comida` solo acepta de −2 a 0 (el resto
-- de las RPC de Dieta aceptan de −7 a +1). Sin esto, en los días −3 a −7 «Comí» y «Salté» quedan deshabilitados y la app
-- explica por qué. Con esto se abren los 7 días sin publicar otra versión: la clave `dieta_dias_marcar` es la que leen las
-- apps (`mypump_get_app_config`); sin la clave se quedan en 2.
--
-- La web sigue andando igual: se ensancha una ventana, no cambia la firma ni lo que devuelve. También alinea el futuro con
-- las otras RPC (+1): un teléfono adelantado respecto de Argentina (Europa, de noche) hoy recibe «fecha futura» al marcar.

BEGIN;

CREATE OR REPLACE FUNCTION public.mypump_marcar_comida(
  p_token text, p_fecha date, p_comida_id text, p_opcion text, p_estado text, p_foods_excluidos jsonb DEFAULT NULL
) RETURNS SETOF mypump_comidas_marcadas
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $fn$
DECLARE
  v_cliente_id TEXT;
  v_hoy        DATE;
BEGIN
  v_cliente_id := mypump_get_cliente_id_from_token(p_token);
  IF v_cliente_id IS NULL THEN RETURN; END IF;
  IF p_estado NOT IN ('comido','saltado') THEN
    RAISE EXCEPTION 'Estado inválido: %', p_estado;
  END IF;
  v_hoy := (NOW() AT TIME ZONE 'America/Argentina/Buenos_Aires')::DATE;
  IF p_fecha > v_hoy + 1 THEN RAISE EXCEPTION 'No se puede marcar una fecha futura'; END IF;
  IF p_fecha < v_hoy - 7 THEN RAISE EXCEPTION 'Solo se permite backfill de hasta 7 días'; END IF;

  INSERT INTO mypump_comidas_marcadas
    (cliente_id, fecha, comida_id, opcion_elegida, estado, foods_excluidos)
  VALUES
    (v_cliente_id, p_fecha, p_comida_id, p_opcion, p_estado,
     CASE WHEN p_foods_excluidos IS NOT NULL
               AND jsonb_typeof(p_foods_excluidos) = 'array'
               AND jsonb_array_length(p_foods_excluidos) > 0
          THEN p_foods_excluidos ELSE NULL END)
  ON CONFLICT (cliente_id, fecha, comida_id) DO UPDATE
    SET opcion_elegida  = EXCLUDED.opcion_elegida,
        estado          = EXCLUDED.estado,
        foods_excluidos = EXCLUDED.foods_excluidos,
        marcada_en      = NOW(),
        updated_at      = NOW();

  RETURN QUERY
    SELECT * FROM mypump_comidas_marcadas
    WHERE cliente_id = v_cliente_id AND fecha = p_fecha AND comida_id = p_comida_id;
END;
$fn$;

INSERT INTO mypump_app_config (clave, valor) VALUES ('dieta_dias_marcar', '7'::jsonb)
ON CONFLICT (clave) DO UPDATE SET valor = EXCLUDED.valor;

COMMIT;

-- Reverso: `CREATE OR REPLACE` con las dos líneas de la ventana anteriores (`p_fecha > v_hoy` y `p_fecha < v_hoy - 2`) y
-- `DELETE FROM mypump_app_config WHERE clave = 'dieta_dias_marcar';`
