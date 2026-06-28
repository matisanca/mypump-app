-- ============================================================
-- 020 — FIX: marcar comida / hábito "vuelve a cero" por zona horaria
-- ============================================================
-- BUG (reportado por Gustavo, le pasaba a varios): al marcar el desayuno/
-- almuerzo/cena como "comido", la app contaba las calorías unos segundos y
-- volvía a cero, sin guardar nada.
--
-- CAUSA RAÍZ: el front manda `p_fecha = TODAY_LOCAL` = la fecha LOCAL del
-- navegador del cliente (su "hoy" según la zona horaria / reloj del device).
-- Las RPC validaban esa fecha contra `v_hoy` = fecha en hora Argentina del
-- server, con una ventana durísima (sin futuro, backfill 2 días) y tiraban
-- EXCEPTION si no coincidía. Un cliente con el device aunque sea 1 día
-- adelantado (cualquier zona al este de Argentina, o reloj corrido) caía en
-- "No se puede marcar una fecha futura" → la RPC fallaba → el front hacía
-- rollback del marcado optimista → la comida "volvía a cero".
--
-- Reproducido en prod: marcar con fecha = mañana → "No se puede marcar una
-- fecha futura"; con fecha = hace 3 días → "Solo se permite backfill de 2 días".
--
-- FIX: ampliar la ventana para tolerar el desfasaje de zona horaria/reloj.
-- Por pura diferencia de timezone el "hoy" del device difiere a lo sumo ±1 día
-- de Argentina (UTC-3); dejamos +1 de futuro y 7 de backfill (margen para
-- reloj corrido y para registrar comidas olvidadas de la última semana).
-- El marcado es idempotente (UNIQUE cliente_id+fecha+comida_id) y de bajo
-- riesgo, así que ser permisivos no rompe nada — y deja de fallarle a la gente.
--
-- Se recrean las 3 RPC con la validación de fecha frágil:
--   mypump_marcar_comida, mypump_desmarcar_comida (011), mypump_set_habito (007).
-- Solo cambia el bloque de validación de fecha; el resto queda idéntico.
-- ============================================================

-- ── 1) mypump_marcar_comida ─────────────────────────────────
CREATE OR REPLACE FUNCTION mypump_marcar_comida(
  p_token     TEXT,
  p_fecha     DATE,
  p_comida_id TEXT,
  p_opcion    TEXT,
  p_estado    TEXT
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

  -- Ventana tolerante a zona horaria/reloj del device (ver cabecera 020).
  v_hoy := (NOW() AT TIME ZONE 'America/Argentina/Buenos_Aires')::DATE;
  IF p_fecha > v_hoy + 1 THEN
    RAISE EXCEPTION 'No se puede marcar una fecha futura';
  END IF;
  IF p_fecha < v_hoy - 7 THEN
    RAISE EXCEPTION 'Solo se permite backfill de hasta 7 días';
  END IF;

  INSERT INTO mypump_comidas_marcadas
    (cliente_id, fecha, comida_id, opcion_elegida, estado)
  VALUES
    (v_cliente_id, p_fecha, p_comida_id, p_opcion, p_estado)
  ON CONFLICT (cliente_id, fecha, comida_id) DO UPDATE
    SET opcion_elegida = EXCLUDED.opcion_elegida,
        estado         = EXCLUDED.estado,
        marcada_en     = NOW(),
        updated_at     = NOW();

  RETURN QUERY
    SELECT * FROM mypump_comidas_marcadas
    WHERE cliente_id = v_cliente_id
      AND fecha      = p_fecha
      AND comida_id  = p_comida_id;
END;
$$;

GRANT EXECUTE ON FUNCTION mypump_marcar_comida(TEXT, DATE, TEXT, TEXT, TEXT) TO anon;

-- ── 2) mypump_desmarcar_comida ──────────────────────────────
CREATE OR REPLACE FUNCTION mypump_desmarcar_comida(
  p_token     TEXT,
  p_fecha     DATE,
  p_comida_id TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_cliente_id TEXT;
  v_hoy        DATE;
  v_deleted    INTEGER;
BEGIN
  v_cliente_id := mypump_get_cliente_id_from_token(p_token);
  IF v_cliente_id IS NULL THEN RETURN FALSE; END IF;

  -- Ventana tolerante a zona horaria/reloj del device (ver cabecera 020).
  v_hoy := (NOW() AT TIME ZONE 'America/Argentina/Buenos_Aires')::DATE;
  IF p_fecha > v_hoy + 1 OR p_fecha < v_hoy - 7 THEN
    RAISE EXCEPTION 'Fecha fuera de rango permitido';
  END IF;

  DELETE FROM mypump_comidas_marcadas
  WHERE cliente_id = v_cliente_id
    AND fecha      = p_fecha
    AND comida_id  = p_comida_id;

  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  RETURN v_deleted > 0;
END;
$$;

GRANT EXECUTE ON FUNCTION mypump_desmarcar_comida(TEXT, DATE, TEXT) TO anon;

-- ── 3) mypump_set_habito (Mi Día) ───────────────────────────
CREATE OR REPLACE FUNCTION mypump_set_habito(
  p_token  TEXT,
  p_fecha  DATE,
  p_campo  TEXT,
  p_valor  TEXT
)
RETURNS SETOF mypump_habitos_diarios
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

  IF p_campo NOT IN ('entrenamiento','comio_segun_plan','durmio_bien','vasos_agua') THEN
    RAISE EXCEPTION 'Campo inválido: %', p_campo;
  END IF;

  -- Ventana tolerante a zona horaria/reloj del device (ver cabecera 020).
  v_hoy := (NOW() AT TIME ZONE 'America/Argentina/Buenos_Aires')::DATE;
  IF p_fecha > v_hoy + 1 THEN
    RAISE EXCEPTION 'No se puede marcar una fecha futura';
  END IF;
  IF p_fecha < v_hoy - 7 THEN
    RAISE EXCEPTION 'Solo se permite backfill de hasta 7 días';
  END IF;

  -- Crear fila si no existe
  INSERT INTO mypump_habitos_diarios (cliente_id, fecha)
  VALUES (v_cliente_id, p_fecha)
  ON CONFLICT (cliente_id, fecha) DO NOTHING;

  -- Actualizar el campo específico
  IF p_campo = 'entrenamiento' THEN
    UPDATE mypump_habitos_diarios
    SET entrenamiento = CASE WHEN p_valor IS NULL OR p_valor = 'null' THEN NULL
                             ELSE p_valor END,
        updated_at = NOW()
    WHERE cliente_id = v_cliente_id AND fecha = p_fecha;

  ELSIF p_campo = 'comio_segun_plan' THEN
    UPDATE mypump_habitos_diarios
    SET comio_segun_plan = CASE WHEN p_valor IS NULL OR p_valor = 'null' THEN NULL
                                WHEN p_valor = 'true' THEN TRUE ELSE FALSE END,
        updated_at = NOW()
    WHERE cliente_id = v_cliente_id AND fecha = p_fecha;

  ELSIF p_campo = 'durmio_bien' THEN
    UPDATE mypump_habitos_diarios
    SET durmio_bien = CASE WHEN p_valor IS NULL OR p_valor = 'null' THEN NULL
                           WHEN p_valor = 'true' THEN TRUE ELSE FALSE END,
        updated_at = NOW()
    WHERE cliente_id = v_cliente_id AND fecha = p_fecha;

  ELSIF p_campo = 'vasos_agua' THEN
    UPDATE mypump_habitos_diarios
    SET vasos_agua = LEAST(12, GREATEST(0, p_valor::SMALLINT)),
        updated_at = NOW()
    WHERE cliente_id = v_cliente_id AND fecha = p_fecha;
  END IF;

  RETURN QUERY
    SELECT * FROM mypump_habitos_diarios
    WHERE cliente_id = v_cliente_id AND fecha = p_fecha;
END;
$$;

GRANT EXECUTE ON FUNCTION mypump_set_habito(TEXT, DATE, TEXT, TEXT) TO anon;
