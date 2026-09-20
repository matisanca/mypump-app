-- 074_series_verosimiles.sql
--
-- LAS SERIES IMPOSIBLES CONTAMINABAN TODO LO QUE SE CALCULA CON ELLAS.
--
-- 19-sep-2026. Auditando antes del build 1.0.11 aparecieron en
-- mypump_registros_carga 23 series como estas:
--
--   reps 1214, 1110, 12120, 1416, 1515 · peso 800, 3.525, 3.530, 781,8 kg
--
-- El patrón es de CONCATENACIÓN: al editar una serie ya confirmada el campo
-- conservaba el valor viejo y lo tipeado se pegaba atrás ("12" + "14";
-- "35" + "30"). La app lo arregla desde este build (selecciona todo al foco,
-- rechaza lo imposible y pregunta lo raro). Pero lo que ya está guardado
-- seguía entrando en:
--
--   · el RÉCORD y la "última vez" de la card (máximo del historial) — un
--     cliente veía "🏆 Récord: 3530kg × 12" en curl martillo;
--   · el PESO SUGERIDO de la semana siguiente: un 800 kg en press plano en
--     máquina se repitió TRES semanas con un solo toque;
--   · el e1RM del panel del coach y el tonelaje semanal (ton);
--   · las "cargas en retroceso" del centinela: tras un 800 kg, las semanas
--     normales aparecían como caída del 89-96 % → "fuerza cayendo" falso a
--     Mati y al cliente (mrk2n0qm7swk, mqve6pngpcao el 17-sep).
--
-- QUÉ HACE. Una columna generada `verosimil` (reps ≤ 300 y peso ≤ 600 kg:
-- nadie hace más de 300 repeticiones de una serie ni mueve más de 600 kg
-- en una máquina) y los tres lectores que alimentan lo de arriba la usan.
-- NO se borra nada: las filas quedan, marcadas, por si algún día se quieren
-- corregir a mano. Recalcular una columna generada es DROP + ADD.
--
-- Lectores que NO cambian a propósito: los conteos de sesión y adherencia
-- (la serie se hizo, aunque el número sea basura) y las dos RPC viejas de
-- historial por slot (031/055), que la app solo usa si falta la 072.
BEGIN;

ALTER TABLE mypump_registros_carga
  ADD COLUMN IF NOT EXISTS verosimil BOOLEAN
  GENERATED ALWAYS AS (
    COALESCE(reps_realizadas, 0) BETWEEN 0 AND 300
    AND COALESCE(peso_kg, 0) BETWEEN 0 AND 600
  ) STORED;

-- ── 1. Historial de la card (072) ────────────────────────────────────────────
CREATE OR REPLACE FUNCTION mypump_get_historico_por_clave(
  p_token          TEXT,
  p_claves         TEXT[],
  p_limit_por_ej   INTEGER DEFAULT 24
)
RETURNS TABLE(
  clave            TEXT,
  registrado_en    TIMESTAMPTZ,
  peso_kg          NUMERIC,
  reps_realizadas  INTEGER,
  rir_real         INTEGER,
  serie_numero     INTEGER,
  notas            TEXT,
  ejercicio_nombre TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_cliente_id TEXT;
  v_limit      INTEGER;
  v_claves     TEXT[];
BEGIN
  v_cliente_id := mypump_get_cliente_id_from_token(p_token);
  IF v_cliente_id IS NULL THEN RETURN; END IF;

  IF p_claves IS NULL OR array_length(p_claves, 1) IS NULL THEN
    RETURN;
  END IF;

  v_limit  := LEAST(GREATEST(COALESCE(p_limit_por_ej, 24), 1), 200);
  -- Se normaliza también lo que llega: si la app manda el nombre crudo por
  -- error, igual matchea. Y se deduplica para no repetir filas.
  SELECT array_agg(DISTINCT mypump_clave_ejercicio(k))
    INTO v_claves
    FROM unnest(p_claves[1:200]) AS k
   WHERE k IS NOT NULL AND trim(k) <> '';
  IF v_claves IS NULL THEN RETURN; END IF;

  RETURN QUERY
  SELECT e.k, h.registrado_en, h.peso_kg, h.reps_realizadas,
         h.rir_real, h.serie_numero, h.notas, h.ejercicio_nombre
  FROM unnest(v_claves) AS e(k)
  CROSS JOIN LATERAL (
    SELECT r.registrado_en, r.peso_kg, r.reps_realizadas,
           r.rir_real, r.serie_numero, r.notas, r.ejercicio_nombre
    FROM mypump_registros_carga r
    WHERE r.cliente_id = v_cliente_id
      AND r.ejercicio_clave = e.k
      AND r.verosimil                      -- 074: sin las series imposibles
    ORDER BY r.registrado_en DESC
    LIMIT v_limit
  ) h;
END;
$$;

-- ── 2. Progresión de cargas (024): la lee el centinela para "fuerza cayendo" ─
CREATE OR REPLACE FUNCTION mypump_get_progresion_cargas(
  p_cliente_id TEXT,
  p_semanas    INTEGER DEFAULT 12
)
RETURNS TABLE(
  fecha           DATE,
  ejercicio       TEXT,
  ejercicio_id    TEXT,
  peso_realizado  NUMERIC,
  reps_realizadas INTEGER,
  rir_real        INTEGER,
  semana          INTEGER,
  e1rm            NUMERIC
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT DISTINCT ON (r.sesion_id, r.ejercicio_id)
         r.registrado_en::date                                   AS fecha,
         r.ejercicio_nombre                                      AS ejercicio,
         r.ejercicio_id,
         r.peso_kg                                               AS peso_realizado,
         r.reps_realizadas,
         r.rir_real,
         s.semana,
         ROUND(r.peso_kg * (1 + r.reps_realizadas / 30.0), 1)    AS e1rm
    FROM mypump_registros_carga r
    JOIN mypump_sesiones s ON s.id = r.sesion_id
   WHERE r.cliente_id = p_cliente_id
     AND r.registrado_en >= NOW() - make_interval(days => GREATEST(p_semanas, 1) * 7)
     AND r.peso_kg > 0
     AND r.reps_realizadas > 0
     AND r.verosimil                        -- 074
   ORDER BY r.sesion_id, r.ejercicio_id,
            (r.peso_kg * (1 + r.reps_realizadas / 30.0)) DESC;
$$;

-- ── 3. Métricas del coach (073): tonelaje y e1RM ────────────────────────────
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
      AND rc.verosimil                     -- 074
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
      AND rc.verosimil                     -- 074: un 800 kg con 10 reps pasaba el tope de reps
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

-- ============================================================
-- ROLLBACK (manual): re-aplicar 072 (historico_por_clave), 024
-- (progresion_cargas) y 073 (metricas_coach) tal cual están en el repo, y
-- después:
--   ALTER TABLE mypump_registros_carga DROP COLUMN IF EXISTS verosimil;
-- ============================================================
