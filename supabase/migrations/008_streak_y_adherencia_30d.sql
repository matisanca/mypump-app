-- ============================================================
-- 008 — Correcciones a hábitos diarios
-- 1. mypump_get_streak: incluir hoy si ya es válido
-- 2. mypump_get_adherencia_global: 14 → 30 días
-- ============================================================

-- ============================================================
-- CORRECCIÓN 1: Streak incluye hoy si hoy es válido
-- Lógica nueva:
--   - Si hoy está completo (válido), cursor empieza en hoy.
--   - Si hoy está incompleto o sin registro, cursor empieza en ayer.
--   Así la racha crece el mismo día cuando el cliente ya completó todo.
-- ============================================================
CREATE OR REPLACE FUNCTION mypump_get_streak(p_token TEXT)
RETURNS TABLE (streak INTEGER, ultimo_dia_valido DATE)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_cliente_id TEXT;
  v_hoy        DATE;
  v_cursor     DATE;
  v_streak     INTEGER := 0;
  v_ultimo     DATE    := NULL;
  v_row        mypump_habitos_diarios%ROWTYPE;
  v_hoy_valido BOOLEAN := FALSE;
BEGIN
  v_cliente_id := mypump_get_cliente_id_from_token(p_token);
  IF v_cliente_id IS NULL THEN RETURN; END IF;

  v_hoy := (NOW() AT TIME ZONE 'America/Argentina/Buenos_Aires')::DATE;

  -- Verificar si hoy ya es un día válido
  SELECT * INTO v_row
  FROM mypump_habitos_diarios
  WHERE cliente_id = v_cliente_id AND fecha = v_hoy;

  IF FOUND
     AND v_row.entrenamiento IN ('entrene','descanso')
     AND v_row.comio_segun_plan = TRUE
     AND v_row.durmio_bien = TRUE
  THEN
    v_hoy_valido := TRUE;
  END IF;

  -- Empezar desde hoy si hoy es válido, desde ayer si no
  IF v_hoy_valido THEN
    v_cursor := v_hoy;
  ELSE
    v_cursor := v_hoy - 1;
  END IF;

  WHILE v_cursor >= v_hoy - 365 LOOP
    SELECT * INTO v_row
    FROM mypump_habitos_diarios
    WHERE cliente_id = v_cliente_id AND fecha = v_cursor;

    IF FOUND
       AND v_row.entrenamiento IN ('entrene','descanso')
       AND v_row.comio_segun_plan = TRUE
       AND v_row.durmio_bien = TRUE
    THEN
      v_streak := v_streak + 1;
      IF v_ultimo IS NULL THEN v_ultimo := v_cursor; END IF;
    ELSE
      EXIT;
    END IF;

    v_cursor := v_cursor - 1;
  END LOOP;

  RETURN QUERY SELECT v_streak, v_ultimo;
END;
$$;

GRANT EXECUTE ON FUNCTION mypump_get_streak(TEXT) TO anon;

-- ============================================================
-- CORRECCIÓN 2: Adherencia global devuelve 30 días (no 14)
-- ============================================================
CREATE OR REPLACE FUNCTION mypump_get_adherencia_global()
RETURNS TABLE (
  cliente_id        TEXT,
  nombre            TEXT,
  fecha             DATE,
  entrenamiento     TEXT,
  comio_segun_plan  BOOLEAN,
  durmio_bien       BOOLEAN,
  vasos_agua        SMALLINT,
  es_valido         BOOLEAN
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_hoy DATE;
BEGIN
  IF auth.role() <> 'authenticated' THEN
    RAISE EXCEPTION 'Acceso denegado';
  END IF;

  v_hoy := (NOW() AT TIME ZONE 'America/Argentina/Buenos_Aires')::DATE;

  RETURN QUERY
    SELECT
      c.cliente_id,
      c.nombre,
      d.dia::DATE AS fecha,
      h.entrenamiento,
      h.comio_segun_plan,
      h.durmio_bien,
      COALESCE(h.vasos_agua, 0)::SMALLINT,
      CASE
        WHEN h.entrenamiento IN ('entrene','descanso')
             AND h.comio_segun_plan = TRUE
             AND h.durmio_bien = TRUE
        THEN TRUE ELSE FALSE
      END AS es_valido
    FROM mypump_clientes c
    CROSS JOIN generate_series(v_hoy - 29, v_hoy, INTERVAL '1 day') d(dia)
    LEFT JOIN mypump_habitos_diarios h
      ON h.cliente_id = c.cliente_id AND h.fecha = d.dia::DATE
    WHERE c.access_token_active = TRUE
    ORDER BY c.nombre, d.dia DESC;
END;
$$;

GRANT EXECUTE ON FUNCTION mypump_get_adherencia_global() TO authenticated;
