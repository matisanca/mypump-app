-- ============================================================
-- 005 — Avance de semana del cliente
-- ============================================================
-- Permite al cliente avanzar de semana desde la app.
-- Si p_semana_destino es NULL, avanza semana_actual + 1.
-- Si p_semana_destino tiene valor, salta a esa semana exacta
-- (usado para override admin desde Cerebro — Parte B).
-- Devuelve la nueva semana_actual, o NULL si el token es invalido.
-- ============================================================

CREATE OR REPLACE FUNCTION mypump_avanzar_semana(
  p_token           TEXT,
  p_semana_destino  INTEGER DEFAULT NULL
)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_cliente_id    TEXT;
  v_semana_actual INTEGER;
  v_semanas_total INTEGER;
  v_nueva_semana  INTEGER;
BEGIN
  v_cliente_id := mypump_get_cliente_id_from_token(p_token);
  IF v_cliente_id IS NULL THEN RETURN NULL; END IF;

  -- Leer semana actual y total de la rutina activa
  SELECT
    semana_actual,
    COALESCE((estructura->>'semanas_total')::INTEGER, 12)
  INTO v_semana_actual, v_semanas_total
  FROM mypump_rutinas
  WHERE cliente_id = v_cliente_id
    AND estado = 'activa'
  LIMIT 1;

  IF v_semana_actual IS NULL THEN RETURN NULL; END IF;

  -- Calcular nueva semana
  IF p_semana_destino IS NOT NULL THEN
    v_nueva_semana := GREATEST(1, LEAST(p_semana_destino, v_semanas_total));
  ELSE
    v_nueva_semana := LEAST(v_semana_actual + 1, v_semanas_total);
  END IF;

  -- Si ya estamos en la semana destino, no hacer nada (idempotente)
  IF v_nueva_semana = v_semana_actual THEN RETURN v_semana_actual; END IF;

  UPDATE mypump_rutinas
  SET semana_actual = v_nueva_semana
  WHERE cliente_id = v_cliente_id
    AND estado = 'activa';

  RETURN v_nueva_semana;
END;
$$;

GRANT EXECUTE ON FUNCTION mypump_avanzar_semana(TEXT, INTEGER) TO anon;
