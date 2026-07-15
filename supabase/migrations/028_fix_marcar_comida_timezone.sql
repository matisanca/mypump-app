-- ============================================================
-- 028 — FIX (regresión): marcar comida "se vuelve a desmarcar" por zona horaria
-- ============================================================
-- REPORTE (Gustavo, otra vez): marca la comida y se desmarca sola. "Lo mismo de
-- la vez pasada" — porque LO ES.
--
-- HISTORIA:
--   · 020 arregló este bug ampliando la ventana de fecha a +1 futuro / -7
--     backfill (el front manda TODAY_LOCAL = fecha local del device; un cliente
--     al este de Argentina —ej. España— tiene su "hoy" hasta 1 día adelantado,
--     y la RPC lo rechazaba como "fecha futura" → el marcado optimista se
--     revertía → la comida se desmarcaba).
--   · 026 (consumo parcial) reescribió mypump_marcar_comida para agregar
--     p_foods_excluidos y, sin querer, REINTRODUJO el chequeo estricto
--     (p_fecha > v_hoy, backfill 2 días) → volvió a romper para los clientes
--     adelantados. desmarcar_comida y set_habito siguieron tolerantes.
--
-- FIX: redefinir mypump_marcar_comida (versión de 6 args, con p_foods_excluidos)
-- restaurando la ventana tolerante de 020 (+1 futuro / -7 backfill). El resto de
-- la función queda idéntico a 026. Idempotente y de bajo riesgo.
-- ============================================================

CREATE OR REPLACE FUNCTION mypump_marcar_comida(
  p_token           TEXT,
  p_fecha           DATE,
  p_comida_id       TEXT,
  p_opcion          TEXT,
  p_estado          TEXT,
  p_foods_excluidos JSONB DEFAULT NULL
)
RETURNS SETOF mypump_comidas_marcadas
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_cliente_id TEXT;
  v_hoy        DATE;
BEGIN
  v_cliente_id := mypump_get_cliente_id_from_token(p_token);
  IF v_cliente_id IS NULL THEN RETURN; END IF;

  IF p_estado NOT IN ('comido','saltado') THEN
    RAISE EXCEPTION 'Estado inválido: %', p_estado;
  END IF;

  -- Ventana TOLERANTE a zona horaria/reloj del device (restaura 020).
  -- Por diferencia de timezone el "hoy" del device difiere a lo sumo ±1 día de
  -- Argentina; dejamos +1 de futuro y 7 de backfill (comidas olvidadas).
  v_hoy := (NOW() AT TIME ZONE 'America/Argentina/Buenos_Aires')::DATE;
  IF p_fecha > v_hoy + 1 THEN
    RAISE EXCEPTION 'No se puede marcar una fecha futura';
  END IF;
  IF p_fecha < v_hoy - 7 THEN
    RAISE EXCEPTION 'Solo se permite backfill de hasta 7 días';
  END IF;

  INSERT INTO mypump_comidas_marcadas
    (cliente_id, fecha, comida_id, opcion_elegida, estado, foods_excluidos)
  VALUES
    (v_cliente_id, p_fecha, p_comida_id, p_opcion, p_estado,
     -- Un array vacío se guarda como NULL (comió todo).
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
    WHERE cliente_id = v_cliente_id
      AND fecha      = p_fecha
      AND comida_id  = p_comida_id;
END;
$$;

GRANT EXECUTE ON FUNCTION mypump_marcar_comida(TEXT, DATE, TEXT, TEXT, TEXT, JSONB)
  TO anon, authenticated, service_role;
