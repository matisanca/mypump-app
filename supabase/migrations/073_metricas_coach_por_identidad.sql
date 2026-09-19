-- 073_metricas_coach_por_identidad.sql
--
-- LOS MISMOS DOS BUGS DEL HISTORIAL, DEL LADO DEL COACH.
--
-- La 072 arregló la app: el historial de cargas es del EJERCICIO (lo que el
-- cliente hizo, por clave), no del slot de la rutina. Pero el coach ve las
-- cargas por otro camino, mypump_get_metricas_coach (mig 035), y ahí:
--
--   · e1rm_top rotulaba cada serie con el nombre del SLOT de la rutina
--     activa (`co.ejercicio_nombre`), no con lo que el cliente hizo. Una
--     sustitución "curl con barra 20 kg → curl con mancuernas 15 kg" salía
--     como una caída de e1RM del MISMO ejercicio. Medido en la mini el 19-sep:
--     1.028 de 7.596 series (34 clientes) en 12 semanas eran sustituciones
--     rotuladas con el nombre del original.
--   · Y el JOIN era solo contra la rutina ACTIVA, así que al arrancar un
--     bloque nuevo (ids nuevos) el bloque anterior desaparecía de las 12
--     semanas del coach.
--
-- Eso alimenta la card "Fuerza" del panel, "MyPump en vivo" y el dashboard del
-- Cerebro, la alerta "fuerza cayendo: X (-N%)" de la lista de pendientes y
-- `var_e1rm` del centinela — o sea, el veredicto semanal. Falsas alarmas.
--
-- LO QUE CAMBIA: `e1rm` agrupa por `rc.ejercicio_clave` (mig 072) y rotula
-- con el nombre registrado la última vez; `compuestos` toma los slots de
-- TODAS las rutinas del cliente. Misma firma, mismo RETURNS TABLE, misma
-- forma del JSON (`ejercicio`, `semana`, `e1rm`): los consumidores no cambian.
-- CREATE OR REPLACE alcanza porque no se toca la firma.
--
-- Requiere la 072 (columna ejercicio_clave).
BEGIN;

CREATE OR REPLACE FUNCTION mypump_get_metricas_coach(p_semanas INTEGER DEFAULT 6)
RETURNS TABLE (
  cliente_id          TEXT,
  nombre              TEXT,
  perfil              TEXT,
  objetivo            TEXT,
  semana_actual       INTEGER,
  dias_plan           INTEGER,
  sesiones_por_semana JSONB,
  tonelaje_por_semana JSONB,
  e1rm_top            JSONB,
  peso_semanal        JSONB,
  ultima_sesion       TIMESTAMPTZ,
  ultimo_peso_fecha   DATE,
  ultimo_checkin      JSONB
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_desde DATE := (date_trunc('week', NOW()) - make_interval(weeks => GREATEST(p_semanas, 1) - 1))::DATE;
BEGIN
  RETURN QUERY
  WITH activos AS (
    SELECT c.cliente_id, c.nombre, c.perfil,
           r.id AS rutina_id, r.semana_actual,
           r.estructura->'perfil'->>'objetivo' AS objetivo,
           COALESCE(jsonb_array_length(r.estructura->'dias'), 0) AS dias_plan,
           r.estructura
    FROM mypump_clientes c
    JOIN mypump_rutinas r ON r.cliente_id = c.cliente_id AND r.estado = 'activa'
  ),
  ses AS (
    SELECT s.cliente_id,
           date_trunc('week', s.iniciada_en)::DATE AS sem,
           COUNT(*) FILTER (WHERE s.finalizada_en IS NOT NULL) AS finalizadas,
           MAX(s.iniciada_en) AS ult
    FROM mypump_sesiones s
    WHERE COALESCE(s.semana, 1) <> 0
      AND s.iniciada_en >= v_desde
    GROUP BY s.cliente_id, date_trunc('week', s.iniciada_en)::DATE
  ),
  ton AS (
    SELECT rc.cliente_id,
           date_trunc('week', rc.registrado_en)::DATE AS sem,
           ROUND(SUM(rc.peso_kg * rc.reps_realizadas)) AS kg
    FROM mypump_registros_carga rc
    JOIN mypump_sesiones s ON s.id = rc.sesion_id
    WHERE COALESCE(s.semana, 1) <> 0
      AND rc.registrado_en >= v_desde
      AND rc.peso_kg > 0 AND rc.reps_realizadas > 0
    GROUP BY rc.cliente_id, date_trunc('week', rc.registrado_en)::DATE
  ),
  -- Slots marcados 'compuesto' en TODAS las rutinas del cliente, no solo la
  -- activa. Antes era solo la activa, así que al arrancar un bloque nuevo (ids
  -- nuevos) las 12 semanas del coach se quedaban sin el bloque anterior.
  compuestos AS (
    SELECT DISTINCT r.cliente_id, e->>'id' AS ejercicio_id
    FROM mypump_rutinas r
    JOIN activos a ON a.cliente_id = r.cliente_id,
         jsonb_array_elements(r.estructura->'dias') d,
         jsonb_array_elements(d->'bloques') b,
         jsonb_array_elements(b->'ejercicios') e
    WHERE e->>'tipo' = 'compuesto'
  ),
  -- La identidad es rc.ejercicio_clave (mig 072): lo que el cliente HIZO. El
  -- slot solo sirve para filtrar "es un compuesto"; el nombre y la agrupación
  -- salen del registro. Antes se rotulaba con el nombre del slot, así que una
  -- sustitución (curl barra 20 → mancuerna 15) aparecía como caída de e1RM del
  -- MISMO ejercicio: 1.028 de 7.596 series (34 clientes) en 12 semanas eran eso.
  e1rm AS (
    SELECT rc.cliente_id, rc.ejercicio_clave,
           date_trunc('week', rc.registrado_en)::DATE AS sem,
           ROUND(MAX(rc.peso_kg * rc.reps_realizadas / 30.0 + rc.peso_kg), 1) AS mejor
    FROM mypump_registros_carga rc
    JOIN compuestos co ON co.cliente_id = rc.cliente_id AND co.ejercicio_id = rc.ejercicio_id
    JOIN mypump_sesiones s ON s.id = rc.sesion_id
    WHERE COALESCE(s.semana, 1) <> 0
      AND rc.registrado_en >= v_desde
      AND rc.peso_kg > 0 AND rc.reps_realizadas > 0 AND rc.reps_realizadas <= 15
      AND rc.ejercicio_clave <> ''
    GROUP BY rc.cliente_id, rc.ejercicio_clave, date_trunc('week', rc.registrado_en)::DATE
  ),
  -- Un rótulo por clave: el nombre tal cual se registró la ÚLTIMA vez, para
  -- que el coach vea "Curl con mancuernas" y no la clave normalizada.
  rotulo AS (
    SELECT DISTINCT ON (rc.cliente_id, rc.ejercicio_clave)
           rc.cliente_id, rc.ejercicio_clave, rc.ejercicio_nombre
    FROM mypump_registros_carga rc
    WHERE rc.registrado_en >= v_desde AND rc.ejercicio_clave <> ''
    ORDER BY rc.cliente_id, rc.ejercicio_clave, rc.registrado_en DESC
  ),
  peso AS (
    SELECT sd.cliente_id,
           date_trunc('week', sd.fecha)::DATE AS sem,
           ROUND(AVG(sd.valor), 2) AS kg,
           MAX(sd.fecha) AS ult
    FROM mypump_salud_diaria sd
    WHERE sd.tipo = 'peso_kg' AND sd.fecha >= v_desde
    GROUP BY sd.cliente_id, date_trunc('week', sd.fecha)::DATE
  ),
  chk AS (
    SELECT DISTINCT ON (ck.cliente_id) ck.cliente_id,
           jsonb_build_object('semana', ck.semana_lunes, 'energia', ck.energia,
             'descanso', ck.descanso, 'hambre', ck.hambre, 'adherencia', ck.adherencia,
             'nota', ck.nota) AS ultimo
    FROM mypump_checkin_semanal ck
    ORDER BY ck.cliente_id, ck.semana_lunes DESC
  )
  SELECT
    a.cliente_id, a.nombre, a.perfil, a.objetivo,
    a.semana_actual, a.dias_plan::INTEGER,
    COALESCE((SELECT jsonb_agg(jsonb_build_object('semana', se.sem, 'sesiones', se.finalizadas) ORDER BY se.sem)
              FROM ses se WHERE se.cliente_id = a.cliente_id), '[]'::jsonb),
    COALESCE((SELECT jsonb_agg(jsonb_build_object('semana', t.sem, 'kg', t.kg) ORDER BY t.sem)
              FROM ton t WHERE t.cliente_id = a.cliente_id), '[]'::jsonb),
    COALESCE((SELECT jsonb_agg(jsonb_build_object('ejercicio', COALESCE(ro.ejercicio_nombre, x.ejercicio_clave), 'semana', x.sem, 'e1rm', x.mejor) ORDER BY x.ejercicio_clave, x.sem)
              FROM e1rm x
              LEFT JOIN rotulo ro ON ro.cliente_id = x.cliente_id AND ro.ejercicio_clave = x.ejercicio_clave
              WHERE x.cliente_id = a.cliente_id), '[]'::jsonb),
    COALESCE((SELECT jsonb_agg(jsonb_build_object('semana', p.sem, 'kg', p.kg) ORDER BY p.sem)
              FROM peso p WHERE p.cliente_id = a.cliente_id), '[]'::jsonb),
    (SELECT MAX(se2.ult) FROM ses se2 WHERE se2.cliente_id = a.cliente_id),
    (SELECT MAX(p2.ult) FROM peso p2 WHERE p2.cliente_id = a.cliente_id),
    (SELECT c2.ultimo FROM chk c2 WHERE c2.cliente_id = a.cliente_id)
  FROM activos a
  ORDER BY a.nombre;
END;
$$;

-- ── El guardarraíl de la 063 ────────────────────────────────────────────────
DO $guard$
DECLARE v_dupes text;
BEGIN
  SELECT string_agg(proname || ' (' || n || ' firmas)', ', ') INTO v_dupes
  FROM (SELECT p.proname, count(*) AS n
        FROM pg_proc p JOIN pg_namespace ns ON ns.oid = p.pronamespace
        WHERE ns.nspname = 'public' AND p.proname LIKE 'mypump%'
        GROUP BY p.proname HAVING count(*) > 1) d;
  IF v_dupes IS NOT NULL THEN
    RAISE EXCEPTION 'Funciones mypump duplicadas, PostgREST va a tirar PGRST203: %', v_dupes;
  END IF;
END
$guard$;

COMMIT;

NOTIFY pgrst, 'reload schema';
