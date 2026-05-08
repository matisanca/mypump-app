-- ============================================================
-- 007 — Tracking de hábitos diarios del cliente (Mi Día)
-- ============================================================
-- Una fila por cliente por fecha.
-- fecha = DATE enviado por el frontend en timezone local del cliente
--         (el JS manda YYYY-MM-DD local, no se usa NOW()::DATE servidor).
-- ============================================================

-- TABLA
CREATE TABLE IF NOT EXISTS mypump_habitos_diarios (
  id                UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  cliente_id        TEXT        NOT NULL,
  fecha             DATE        NOT NULL,

  -- Entrenamiento: excluyentes. NULL = pendiente, no marcado aún.
  entrenamiento     TEXT        DEFAULT NULL
                    CHECK (entrenamiento IS NULL OR
                           entrenamiento IN ('entrene','descanso','falte')),

  -- Hábitos binarios: NULL = pendiente, TRUE = sí, FALSE = no
  comio_segun_plan  BOOLEAN     DEFAULT NULL,
  durmio_bien       BOOLEAN     DEFAULT NULL,   -- 7+ horas

  -- Agua: contador de vasos (cosmético, no afecta streak)
  vasos_agua        SMALLINT    NOT NULL DEFAULT 0
                    CHECK (vasos_agua BETWEEN 0 AND 12),

  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  UNIQUE (cliente_id, fecha)
);

CREATE INDEX IF NOT EXISTS idx_mypump_habitos_cliente_fecha
  ON mypump_habitos_diarios (cliente_id, fecha DESC);

-- RLS: anon solo vía RPCs SECURITY DEFINER
ALTER TABLE mypump_habitos_diarios ENABLE ROW LEVEL SECURITY;

CREATE POLICY "admin all mypump_habitos_diarios"
  ON mypump_habitos_diarios FOR ALL
  USING (auth.role() = 'authenticated')
  WITH CHECK (auth.role() = 'authenticated');

-- ============================================================
-- RPC 1: leer (o crear vacío) el registro del día
-- ============================================================
CREATE OR REPLACE FUNCTION mypump_get_habitos_dia(
  p_token TEXT,
  p_fecha DATE
)
RETURNS SETOF mypump_habitos_diarios
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_cliente_id TEXT;
BEGIN
  v_cliente_id := mypump_get_cliente_id_from_token(p_token);
  IF v_cliente_id IS NULL THEN RETURN; END IF;

  INSERT INTO mypump_habitos_diarios (cliente_id, fecha)
  VALUES (v_cliente_id, p_fecha)
  ON CONFLICT (cliente_id, fecha) DO NOTHING;

  RETURN QUERY
    SELECT * FROM mypump_habitos_diarios
    WHERE cliente_id = v_cliente_id AND fecha = p_fecha;
END;
$$;

GRANT EXECUTE ON FUNCTION mypump_get_habitos_dia(TEXT, DATE) TO anon;

-- ============================================================
-- RPC 2: actualizar UN campo del día (con validación backfill)
-- ============================================================
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

  -- Validar rango: solo hoy y hasta 2 días atrás, sin futuro
  v_hoy := (NOW() AT TIME ZONE 'America/Argentina/Buenos_Aires')::DATE;
  IF p_fecha > v_hoy THEN
    RAISE EXCEPTION 'No se puede marcar una fecha futura';
  END IF;
  IF p_fecha < v_hoy - 2 THEN
    RAISE EXCEPTION 'Solo se permite backfill de hasta 2 días';
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

-- ============================================================
-- RPC 3: calcular streak de días consecutivos cumplidos
-- Día válido = entrenamiento IN ('entrene','descanso')
--           AND comio_segun_plan = TRUE
--           AND durmio_bien = TRUE
-- Empieza desde ayer (hoy puede estar incompleto).
-- Sin registro = streak roto.
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
BEGIN
  v_cliente_id := mypump_get_cliente_id_from_token(p_token);
  IF v_cliente_id IS NULL THEN RETURN; END IF;

  v_hoy    := (NOW() AT TIME ZONE 'America/Argentina/Buenos_Aires')::DATE;
  v_cursor := v_hoy - 1; -- comenzar desde ayer

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
-- RPC 4: adherencia últimos 30 días del cliente
-- Devuelve 30 filas, más reciente primero.
-- ============================================================
CREATE OR REPLACE FUNCTION mypump_get_adherencia_30d(p_token TEXT)
RETURNS TABLE (
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
  v_cliente_id TEXT;
  v_hoy        DATE;
BEGIN
  v_cliente_id := mypump_get_cliente_id_from_token(p_token);
  IF v_cliente_id IS NULL THEN RETURN; END IF;

  v_hoy := (NOW() AT TIME ZONE 'America/Argentina/Buenos_Aires')::DATE;

  RETURN QUERY
    SELECT
      d.dia::DATE,
      h.entrenamiento,
      h.comio_segun_plan,
      h.durmio_bien,
      COALESCE(h.vasos_agua, 0)::SMALLINT,
      CASE
        WHEN h.entrenamiento IN ('entrene','descanso')
             AND h.comio_segun_plan = TRUE
             AND h.durmio_bien = TRUE
        THEN TRUE
        ELSE FALSE
      END AS es_valido
    FROM generate_series(v_hoy - 29, v_hoy, INTERVAL '1 day') d(dia)
    LEFT JOIN mypump_habitos_diarios h
      ON h.cliente_id = v_cliente_id AND h.fecha = d.dia::DATE
    ORDER BY d.dia DESC;
END;
$$;

GRANT EXECUTE ON FUNCTION mypump_get_adherencia_30d(TEXT) TO anon;

-- ============================================================
-- RPC 5 (admin): adherencia global de todos los clientes
-- Solo authenticated (Cerebro). Devuelve últimos 14 días
-- para todos los clientes publicados.
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
    CROSS JOIN generate_series(v_hoy - 13, v_hoy, INTERVAL '1 day') d(dia)
    LEFT JOIN mypump_habitos_diarios h
      ON h.cliente_id = c.cliente_id AND h.fecha = d.dia::DATE
    WHERE c.access_token_active = TRUE
    ORDER BY c.nombre, d.dia DESC;
END;
$$;

GRANT EXECUTE ON FUNCTION mypump_get_adherencia_global() TO authenticated;
