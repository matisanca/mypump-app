-- ============================================================
-- 016 — patron_movimiento en el catálogo de ejercicios
-- ============================================================
-- Objetivo: habilitar SUSTITUCIÓN DE EJERCICIOS "mismo gesto, distinto
-- equipo". El catálogo (012) ya tiene primary_muscle + mechanic + force,
-- pero es DEMASIADO GRUESO para esto: "Press plano" y "Press inclinado"
-- son ambos chest+compound+push, y NO deben sustituirse entre sí.
--
-- Solución: una columna explícita patron_movimiento (el gesto exacto).
-- Un sustituto válido = MISMO patron_movimiento Y MISMO primary_muscle.
--
-- Taxonomía: parte de la lista acordada con Mati, AMPLIADA con criterio
-- ("mismo gesto = mismo patrón") para separar gestos que comparten músculo
-- pero NO son el mismo movimiento:
--   • fondos_paralelas      (dips — gesto distinto a un press)
--   • press_cerrado         (close-grip bench — no es un press normal)
--   • remo_menton           (upright row — vertical, no horizontal)
--   • zancada_unilateral    (lunge / split squat — no es una sentadilla bilateral)
--   • extension_triceps_kickback (kickback ≠ pushdown ≠ overhead)
--   • abduccion_cadera / aduccion_cadera
--   • extension_lumbar      (hiperextensión ≠ bisagra de cadera)
--   • core_rotacion / flexion_muneca
--
-- FAIL-SAFE: si un ejercicio no se puede clasificar con confianza, queda
-- patron_movimiento = NULL. Los NULL NO ofrecen ni reciben sustitutos
-- (preferimos no sugerir antes que sugerir un gesto equivocado).
-- ============================================================

ALTER TABLE mypump_ejercicios_catalogo
  ADD COLUMN IF NOT EXISTS patron_movimiento TEXT;

CREATE INDEX IF NOT EXISTS idx_catalogo_patron
  ON mypump_ejercicios_catalogo (patron_movimiento);

-- ============================================================
-- BACKFILL determinístico desde name_en (inglés) + primary_muscle.
-- Orden = prioridad (primer WHEN que matchea gana). De específico a general.
-- \m \M = límites de palabra (evita falsos positivos como "dip" en otra palabra).
-- ============================================================
UPDATE mypump_ejercicios_catalogo SET patron_movimiento = CASE

  -- ── GUARDAS: nunca clasificar estiramientos / SMR / movilidad ──
  WHEN name_en ~* '(stretch|foam roll|\msmr\M|-smr|mobility|self-myofascial)' THEN NULL
  WHEN equipment = 'foam roll' THEN NULL

  -- ── PECHO ──────────────────────────────────────────────────
  WHEN primary_muscle = 'chest' AND name_en ~* '(\mfly\M|flye|pec deck|butterfly|crossover|cross over|cable cross)' THEN 'apertura_pectoral'
  WHEN primary_muscle = 'chest' AND name_en ~* 'pullover' THEN 'pullover'
  WHEN primary_muscle = 'chest' AND name_en ~* '\mdips?\M' THEN 'fondos_paralelas'
  WHEN primary_muscle = 'chest' AND name_en ~* '(\mpress\M|bench)' AND name_en ~* 'incline' THEN 'empuje_inclinado'
  WHEN primary_muscle = 'chest' AND name_en ~* '(\mpress\M|bench)' AND name_en ~* 'decline' THEN 'empuje_declinado'
  WHEN primary_muscle = 'chest' AND name_en ~* '(\mpress\M|bench)' THEN 'empuje_horizontal'
  WHEN primary_muscle = 'chest' AND name_en ~* '(push-?up|pushup)' THEN 'empuje_horizontal'

  -- ── HOMBROS ────────────────────────────────────────────────
  WHEN primary_muscle = 'shoulders' AND name_en ~* '(lateral raise|side lateral|side-lateral|\mside laterals\M)' THEN 'elevacion_lateral'
  WHEN primary_muscle = 'shoulders' AND name_en ~* 'front (cable raise|barbell raise|dumbbell raise|raise)' THEN 'elevacion_frontal'
  WHEN primary_muscle = 'shoulders' AND name_en ~* '(rear delt|rear-delt|rear lateral|reverse fly|reverse flye|reverse machine fly|face pull|bent over.*(raise|lateral))' THEN 'deltoide_posterior'
  WHEN primary_muscle = 'shoulders' AND name_en ~* 'upright row' THEN 'remo_menton'
  WHEN primary_muscle = 'shoulders' AND name_en ~* '(shoulder press|military|overhead press|arnold|push press|seated.*\mpress\M|standing.*\mpress\M)' THEN 'empuje_vertical_hombro'
  WHEN primary_muscle = 'shoulders' AND name_en ~* '\mpress\M' THEN 'empuje_vertical_hombro'

  -- ── TRAPECIOS ──────────────────────────────────────────────
  WHEN primary_muscle = 'traps' AND name_en ~* 'shrug' THEN 'encogimiento_trapecio'
  WHEN primary_muscle = 'traps' AND name_en ~* 'upright row' THEN 'remo_menton'

  -- ── ESPALDA (dorsal / media / baja) ────────────────────────
  WHEN primary_muscle = 'lats' AND name_en ~* '(pulldown|pull-down|pull down)' THEN 'jalon_vertical'
  WHEN primary_muscle = 'lats' AND name_en ~* '(pull-?up|pullup|chin-?up|chinup|chin up)' THEN 'jalon_vertical'
  WHEN primary_muscle = 'lats' AND name_en ~* '(pullover|straight-arm|straight arm)' THEN 'pullover'
  WHEN primary_muscle IN ('lats','middle back') AND name_en ~* '\mrow\M' THEN 'remo_horizontal'
  WHEN primary_muscle = 'middle back' AND name_en ~* 'shrug' THEN 'encogimiento_trapecio'
  WHEN primary_muscle = 'middle back' AND name_en ~* '(pulldown|pull-?up|pullup)' THEN 'jalon_vertical'
  WHEN primary_muscle = 'lower back' AND name_en ~* '(hyperextension|back extension)' THEN 'extension_lumbar'
  WHEN primary_muscle = 'lower back' AND name_en ~* '(good morning|deadlift)' THEN 'bisagra_cadera'

  -- ── BÍCEPS / ANTEBRAZO ─────────────────────────────────────
  WHEN primary_muscle = 'biceps' AND name_en ~* '(hammer|cross body)' THEN 'curl_martillo_braquial'
  WHEN primary_muscle = 'biceps' AND name_en ~* 'reverse.*curl' THEN 'curl_martillo_braquial'
  WHEN primary_muscle = 'biceps' AND name_en ~* 'curl' THEN 'curl_biceps'
  WHEN primary_muscle = 'forearms' AND name_en ~* '(reverse curl|hammer)' THEN 'curl_martillo_braquial'
  WHEN primary_muscle = 'forearms' AND name_en ~* 'wrist curl' THEN 'flexion_muneca'

  -- ── TRÍCEPS ────────────────────────────────────────────────
  WHEN primary_muscle = 'triceps' AND name_en ~* '(pushdown|push-down|push down)' THEN 'extension_triceps_pushdown'
  WHEN primary_muscle = 'triceps' AND name_en ~* 'kickback' THEN 'extension_triceps_kickback'
  WHEN primary_muscle = 'triceps' AND name_en ~* '(close-grip|close grip).*bench' THEN 'press_cerrado'
  WHEN primary_muscle = 'triceps' AND name_en ~* '\mdips?\M' THEN 'fondos_paralelas'
  WHEN primary_muscle = 'triceps' AND name_en ~* '(overhead|french|skull|nose breaker|triceps press|lying.*(extension|triceps)|extension)' THEN 'extension_triceps_overhead'

  -- ── CUÁDRICEPS ─────────────────────────────────────────────
  WHEN primary_muscle = 'quadriceps' AND name_en ~* 'leg extension' THEN 'extension_rodilla'
  WHEN primary_muscle = 'quadriceps' AND name_en ~* '(split squat|bulgarian|\mlunge\M|lunges)' THEN 'zancada_unilateral'
  WHEN primary_muscle = 'quadriceps' AND name_en ~* '(squat|leg press|hack)' AND name_en !~* '(jump|jerk|clean|snatch|depth|sprint|box jump)' THEN 'sentadilla_prensa'

  -- ── ISQUIOTIBIALES ─────────────────────────────────────────
  WHEN primary_muscle = 'hamstrings' AND name_en ~* 'leg curl' THEN 'flexion_rodilla'
  WHEN primary_muscle = 'hamstrings' AND name_en ~* '(glute ham|nordic)' THEN 'flexion_rodilla'
  WHEN primary_muscle = 'hamstrings' AND name_en ~* '(romanian|stiff-leg|stiff leg|good morning|deadlift)' THEN 'bisagra_cadera'

  -- ── GLÚTEOS ────────────────────────────────────────────────
  WHEN primary_muscle = 'glutes' AND name_en ~* '(hip thrust|glute bridge)' THEN 'extension_cadera_gluteo'
  WHEN primary_muscle = 'glutes' AND name_en ~* '(kickback|kick back)' THEN 'extension_cadera_gluteo'
  WHEN primary_muscle = 'glutes' AND name_en ~* '(lunge|split squat)' THEN 'zancada_unilateral'
  WHEN primary_muscle = 'glutes' AND name_en ~* '(squat|leg press|hack)' AND name_en !~* '(jump|jerk|clean|snatch|depth|sprint|box jump)' THEN 'sentadilla_prensa'

  -- ── ABDUCTORES / ADUCTORES ─────────────────────────────────
  WHEN primary_muscle = 'abductors' THEN 'abduccion_cadera'
  WHEN primary_muscle = 'adductors' THEN 'aduccion_cadera'

  -- ── GEMELOS / SÓLEO ────────────────────────────────────────
  WHEN primary_muscle = 'calves' AND name_en ~* 'seated' THEN 'gemelo_sentado'
  WHEN primary_muscle = 'calves' AND name_en ~* '(calf|calves|\mtoe\M)' THEN 'gemelo_de_pie'

  -- ── CORE ───────────────────────────────────────────────────
  WHEN primary_muscle = 'abdominals' AND name_en ~* '(rollout|roller|ab wheel|\mplank\M)' THEN 'core_anti_extension'
  WHEN primary_muscle = 'abdominals' AND name_en ~* '(russian twist|woodchop|wood chop|oblique|side bend|\mtwist\M)' THEN 'core_rotacion'
  WHEN primary_muscle = 'abdominals' AND name_en ~* '(crunch|sit-?up|leg raise|knee raise|leg-hip|v-up|jackknife|\mraise\M)' THEN 'core_flexion'

  ELSE NULL
END;

-- ============================================================
-- VERIFICACIÓN — conteo por patrón + cuántos quedaron NULL.
-- (Última sentencia: su resultado se muestra en el SQL Editor.)
-- ============================================================
SELECT
  COALESCE(patron_movimiento, '(SIN CLASIFICAR · NULL)') AS patron,
  COUNT(*) AS n
FROM mypump_ejercicios_catalogo
GROUP BY patron_movimiento
ORDER BY (patron_movimiento IS NULL), n DESC;
