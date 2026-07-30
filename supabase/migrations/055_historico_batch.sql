-- ============================================================
-- 055 — Histórico de carga de VARIOS ejercicios en una sola llamada
--
-- POR QUÉ
-- La pantalla de Progreso pedía el histórico ejercicio por ejercicio:
-- `allEx.map(ex => getHistoricoEjercicio(...))` (cliente.html:4820). Medido en
-- el navegador el 29-jul-2026: **9 llamadas a mypump_get_historico_ejercicio en
-- un solo arranque**, y ese número es el de ejercicios del plan entero, no los
-- del día — un plan de 4 días con 9 ejercicios cada uno son 36 round trips.
--
-- Cada uno paga latencia completa (TLS + PostgREST + plpgsql) y, peor, cada uno
-- vuelve a resolver el token con mypump_get_cliente_id_from_token. En un
-- teléfono con datos móviles eso son segundos de espera para mostrar un dato
-- que ya está todo en la misma tabla.
--
-- Esta función hace lo mismo en UNA llamada, resolviendo el token una sola vez.
-- El LATERAL mantiene el límite POR EJERCICIO (no un límite global): si no,
-- un ejercicio con mucho historial se comería el cupo de los demás.
--
-- NO reemplaza a mypump_get_historico_ejercicio: esa se sigue usando para el
-- detalle de un ejercicio suelto (cliente.html:2445). Esto es aditivo.
-- ============================================================

CREATE OR REPLACE FUNCTION mypump_get_historico_ejercicios(
  p_token          TEXT,
  p_ejercicio_ids  TEXT[],
  p_limit_por_ej   INTEGER DEFAULT 24
)
RETURNS TABLE(
  ejercicio_id    TEXT,
  registrado_en   TIMESTAMPTZ,
  peso_kg         NUMERIC,
  reps_realizadas INTEGER,
  rir_real        INTEGER,
  serie_numero    INTEGER,
  notas           TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_cliente_id TEXT;
  v_limit      INTEGER;
  v_ids        TEXT[];
BEGIN
  v_cliente_id := mypump_get_cliente_id_from_token(p_token);
  IF v_cliente_id IS NULL THEN RETURN; END IF;

  IF p_ejercicio_ids IS NULL OR array_length(p_ejercicio_ids, 1) IS NULL THEN
    RETURN;
  END IF;

  -- Topes defensivos: esta función es anon (por token) y el array viene del
  -- cliente. Sin esto, un pedido con 10.000 ids y limit 100.000 es un DoS
  -- barato contra una base que ya se cayó una vez por saturación de IO.
  v_limit := LEAST(GREATEST(COALESCE(p_limit_por_ej, 24), 1), 200);
  v_ids   := p_ejercicio_ids[1:200];

  RETURN QUERY
  SELECT e.id, h.registrado_en, h.peso_kg, h.reps_realizadas,
         h.rir_real, h.serie_numero, h.notas
  FROM unnest(v_ids) AS e(id)
  CROSS JOIN LATERAL (
    SELECT r.registrado_en, r.peso_kg, r.reps_realizadas,
           r.rir_real, r.serie_numero, r.notas
    FROM mypump_registros_carga r
    WHERE r.cliente_id = v_cliente_id
      AND r.ejercicio_id = e.id
    ORDER BY r.registrado_en DESC
    LIMIT v_limit
  ) h;
END;
$$;

-- Mismo alcance que la versión de a uno: la valida el token, no el rol.
GRANT EXECUTE ON FUNCTION mypump_get_historico_ejercicios(TEXT, TEXT[], INTEGER)
  TO anon, authenticated, service_role;

-- ============================================================
-- VERIFICACIÓN
--   SELECT ejercicio_id, count(*)
--   FROM mypump_get_historico_ejercicios('<token>', ARRAY['id1','id2'], 24)
--   GROUP BY 1;
--
-- ROLLBACK
--   DROP FUNCTION IF EXISTS mypump_get_historico_ejercicios(TEXT, TEXT[], INTEGER);
--   (la app cae sola al camino de a uno: ver el catch en getHistoricoEjercicios)
-- ============================================================
