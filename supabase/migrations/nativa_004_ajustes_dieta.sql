-- nativa_004_ajustes_dieta.sql
--
-- APPS NATIVAS, COMPUERTA G2 (cuarta tanda): LOS AJUSTES DE PORCIONES DEL DÍA.
-- Feedback de clientes del 20-oct, que Mati pidió implementar:
--   - «si tengo más hambre en una comida que en otra, agregar cuántas calorías
--     más quiero y que recalcule las porciones; después restarlas en la siguiente»;
--   - Emilio García Álvarez: «hoy no fui a entrenar, saco el pre-entreno… cómo
--     puedo jugar con los gramos… y tú vas viendo cómo yo voy jugando con las
--     calorías».
--
-- La app calcula todo (AjustePorciones, igual en iOS y en Android, con los
-- vectores de apps/shared/vectores/ajuste_porciones.json). Acá se guarda UNA FILA
-- POR DÍA con lo que eligió el cliente, para que Mati lo pueda ver y para que el
-- cliente lo encuentre en otro teléfono:
--   ajustes = {comida_id: {deltaKcal, compensar, omitida, opcion, cantidades, anclas}}
--             (anclas = a qué alimento va cada cantidad a mano: {índice: {nombre, unidad}})
--   resumen = [{comida_id, nombre, kcal_plan, kcal_dia, omitida}]  (para leerlo sin la app)
--   kcal_plan / kcal_dia = el total del día con las opciones elegidas.
-- No es «Comí / Salté» (D10): es el plan del día, ajustado por el cliente.
--
-- Fecha: la local del teléfono, con la ventana de siempre (+1 / −7 días).
-- Volver al plan guarda {} y la fila queda: no se borra nada, Mati ve que lo
-- tocó y otro teléfono del cliente no resucita un ajuste que ya sacó.
--
-- La web y el Cerebro no la usan. Mientras no exista (PGRST202), la app sigue
-- igual: los ajustes quedan solo en el teléfono.
--
-- Solo agrega: una tabla y dos funciones. No cambia nada existente.
-- Ensayo: scripts/nativa/ensayar-migracion.py (BEGIN … ROLLBACK, con test-nativa-ios
-- y test-nativa-real). Se aplica SOLO con el OK de Mati.
BEGIN;

CREATE TABLE IF NOT EXISTS mypump_ajustes_dieta (
  cliente_id     TEXT        NOT NULL,
  fecha          DATE        NOT NULL,
  dieta_id       UUID,
  tipo_dia       TEXT        CHECK (tipo_dia IS NULL OR length(tipo_dia) <= 120),
  ajustes        JSONB       NOT NULL CHECK (jsonb_typeof(ajustes) = 'object' AND pg_column_size(ajustes) <= 16000),
  resumen        JSONB       CHECK (resumen IS NULL OR (jsonb_typeof(resumen) = 'array' AND pg_column_size(resumen) <= 16000)),
  kcal_plan      NUMERIC     CHECK (kcal_plan IS NULL OR kcal_plan BETWEEN 0 AND 30000),
  kcal_dia       NUMERIC     CHECK (kcal_dia IS NULL OR kcal_dia BETWEEN 0 AND 30000),
  creado_en      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  actualizado_en TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (cliente_id, fecha)
);

-- Sin clave foránea a mypump_dietas a propósito: si el Cerebro vuelve a publicar
-- la dieta, un ON DELETE CASCADE se llevaría lo que hizo el cliente.

ALTER TABLE mypump_ajustes_dieta ENABLE ROW LEVEL SECURITY;

CREATE POLICY "admin all mypump_ajustes_dieta"
  ON mypump_ajustes_dieta FOR ALL
  USING (auth.role() = 'authenticated')
  WITH CHECK (auth.role() = 'authenticated');

-- Guardar los ajustes de un día ({} = volvió al plan). TRUE = guardado; NULL = el
-- token no sirve.
CREATE OR REPLACE FUNCTION mypump_guardar_ajustes_dieta(
  p_token     TEXT,
  p_fecha     DATE,
  p_dieta_id  UUID,
  p_tipo_dia  TEXT,
  p_ajustes   JSONB,
  p_resumen   JSONB   DEFAULT NULL,
  p_kcal_plan NUMERIC DEFAULT NULL,
  p_kcal_dia  NUMERIC DEFAULT NULL
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_cliente_id TEXT;
  v_hoy        DATE;
  v_vacio      BOOLEAN;
BEGIN
  v_cliente_id := mypump_get_cliente_id_from_token(p_token);
  IF v_cliente_id IS NULL THEN RETURN NULL; END IF;

  v_hoy := (NOW() AT TIME ZONE 'America/Argentina/Buenos_Aires')::DATE;
  IF p_fecha IS NULL OR p_fecha > v_hoy + 1 OR p_fecha < v_hoy - 7 THEN
    RAISE EXCEPTION 'Fecha fuera de la ventana permitida' USING ERRCODE = '22023';
  END IF;
  IF p_ajustes IS NULL OR jsonb_typeof(p_ajustes) <> 'object' OR pg_column_size(p_ajustes) > 16000 THEN
    RAISE EXCEPTION 'Ajustes inválidos' USING ERRCODE = '22023';
  END IF;
  IF p_resumen IS NOT NULL AND (jsonb_typeof(p_resumen) <> 'array' OR pg_column_size(p_resumen) > 16000) THEN
    RAISE EXCEPTION 'Resumen inválido' USING ERRCODE = '22023';
  END IF;
  IF p_tipo_dia IS NOT NULL AND length(p_tipo_dia) > 120 THEN
    RAISE EXCEPTION 'Tipo de día inválido' USING ERRCODE = '22023';
  END IF;

  -- Sin ajustes (volvió al plan) no hay resumen ni totales que valgan.
  v_vacio := p_ajustes = '{}'::jsonb;
  INSERT INTO mypump_ajustes_dieta (cliente_id, fecha, dieta_id, tipo_dia, ajustes, resumen, kcal_plan, kcal_dia)
  VALUES (v_cliente_id, p_fecha, p_dieta_id, p_tipo_dia, p_ajustes,
          CASE WHEN NOT v_vacio THEN p_resumen END,
          CASE WHEN NOT v_vacio AND p_kcal_plan BETWEEN 0 AND 30000 THEN p_kcal_plan END,
          CASE WHEN NOT v_vacio AND p_kcal_dia BETWEEN 0 AND 30000 THEN p_kcal_dia END)
  ON CONFLICT (cliente_id, fecha) DO UPDATE
    SET dieta_id = EXCLUDED.dieta_id, tipo_dia = EXCLUDED.tipo_dia, ajustes = EXCLUDED.ajustes,
        resumen = EXCLUDED.resumen, kcal_plan = EXCLUDED.kcal_plan, kcal_dia = EXCLUDED.kcal_dia,
        actualizado_en = NOW();
  RETURN TRUE;
END;
$$;

REVOKE ALL ON FUNCTION mypump_guardar_ajustes_dieta(TEXT, DATE, UUID, TEXT, JSONB, JSONB, NUMERIC, NUMERIC) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION mypump_guardar_ajustes_dieta(TEXT, DATE, UUID, TEXT, JSONB, JSONB, NUMERIC, NUMERIC) TO anon, authenticated, service_role;

-- Los ajustes de un rango de fechas (como mucho 31 días), del más viejo al más nuevo:
-- [{fecha, dieta_id, tipo_dia, ajustes}]. NULL = el token no sirve.
CREATE OR REPLACE FUNCTION mypump_get_ajustes_dieta(p_token TEXT, p_desde DATE, p_hasta DATE)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_cliente_id TEXT;
BEGIN
  v_cliente_id := mypump_get_cliente_id_from_token(p_token);
  IF v_cliente_id IS NULL THEN RETURN NULL; END IF;
  IF p_desde IS NULL OR p_hasta IS NULL OR p_hasta < p_desde OR p_hasta - p_desde > 30 THEN
    RAISE EXCEPTION 'Rango inválido' USING ERRCODE = '22023';
  END IF;
  RETURN COALESCE((
    SELECT jsonb_agg(jsonb_build_object('fecha', fecha, 'dieta_id', dieta_id, 'tipo_dia', tipo_dia, 'ajustes', ajustes)
                     ORDER BY fecha)
      FROM mypump_ajustes_dieta
     WHERE cliente_id = v_cliente_id AND fecha BETWEEN p_desde AND p_hasta), '[]'::jsonb);
END;
$$;

REVOKE ALL ON FUNCTION mypump_get_ajustes_dieta(TEXT, DATE, DATE) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION mypump_get_ajustes_dieta(TEXT, DATE, DATE) TO anon, authenticated, service_role;

NOTIFY pgrst, 'reload schema';

COMMIT;
