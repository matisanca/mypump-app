-- ============================================================
-- 022 — Hábito "cardio" en Mi Día
-- ============================================================
-- Pedido de clientes: poder registrar el cardio hecho, junto a agua / entrené /
-- dormí bien / comí según plan. Se agrega como toggle sí/no (tri-estado con NULL
-- = pendiente), calcando comio_segun_plan / durmio_bien.
--
-- IMPACTO en streak/adherencia: NINGUNO. El "día válido" (get_streak /
-- get_adherencia) sigue dependiendo solo de entrenamiento + comio_segun_plan +
-- durmio_bien. cardio queda cosmético igual que vasos_agua.
--
-- Se recrea mypump_set_habito COPIANDO la versión vigente (migration 020, ventana
-- de fecha tolerante +1/-7) con solo 2 cambios: 'cardio' en el whitelist y un
-- branch ELSIF nuevo. NO se toca la validación de fecha ni los demás campos.
-- ============================================================

-- 1) Columna nueva (idempotente; NULL = pendiente, TRUE = hizo, FALSE = no)
ALTER TABLE mypump_habitos_diarios
  ADD COLUMN IF NOT EXISTS cardio BOOLEAN DEFAULT NULL;

-- 2) Recrear set_habito con soporte de 'cardio'
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

  IF p_campo NOT IN ('entrenamiento','comio_segun_plan','durmio_bien','vasos_agua','cardio') THEN
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

  ELSIF p_campo = 'cardio' THEN
    UPDATE mypump_habitos_diarios
    SET cardio = CASE WHEN p_valor IS NULL OR p_valor = 'null' THEN NULL
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
