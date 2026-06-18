-- ============================================================
-- 017 — Correcciones al backfill de patron_movimiento (016)
-- ============================================================
-- Bugs detectados al probar contra rutinas reales:
--  1) Plural "Rows": el límite \mrow\M no matchea "Rows" (la s rompe \M), así
--     que "Seated Cable Rows", "Cable Rope Rear-Delt Rows", etc. quedaron NULL.
--     Fix: \mrows?\M (cubre row y rows). Idem \mraises?\M, \mtoes?\M.
--  2) "Straight-Arm Pulldown" / "Rope Straight-Arm Pulldown" (gesto pullover)
--     caían en jalon_vertical porque contienen "pulldown" y esa regla iba antes.
--     Fix: evaluar pullover/straight-arm ANTES que pulldown en el bloque de lats.
--
-- Re-corre el backfill completo corregido (idempotente: pisa patron_movimiento).
-- ============================================================
UPDATE mypump_ejercicios_catalogo SET patron_movimiento = CASE

  WHEN name_en ~* '(stretch|foam roll|\msmr\M|-smr|mobility|self-myofascial)' THEN NULL
  WHEN equipment = 'foam roll' THEN NULL

  -- PECHO
  WHEN primary_muscle = 'chest' AND name_en ~* '(\mfly\M|flye|pec deck|butterfly|crossover|cross over|cable cross)' THEN 'apertura_pectoral'
  WHEN primary_muscle = 'chest' AND name_en ~* 'pullover' THEN 'pullover'
  WHEN primary_muscle = 'chest' AND name_en ~* '\mdips?\M' THEN 'fondos_paralelas'
  WHEN primary_muscle = 'chest' AND name_en ~* '(\mpress\M|bench)' AND name_en ~* 'incline' THEN 'empuje_inclinado'
  WHEN primary_muscle = 'chest' AND name_en ~* '(\mpress\M|bench)' AND name_en ~* 'decline' THEN 'empuje_declinado'
  WHEN primary_muscle = 'chest' AND name_en ~* '(\mpress\M|bench)' THEN 'empuje_horizontal'
  WHEN primary_muscle = 'chest' AND name_en ~* '(push-?up|pushup)' THEN 'empuje_horizontal'

  -- HOMBROS
  WHEN primary_muscle = 'shoulders' AND name_en ~* '(lateral raise|side lateral|side-lateral|\mside laterals\M)' THEN 'elevacion_lateral'
  WHEN primary_muscle = 'shoulders' AND name_en ~* 'front (cable raise|barbell raise|dumbbell raise|raise)' THEN 'elevacion_frontal'
  WHEN primary_muscle = 'shoulders' AND name_en ~* '(rear delt|rear-delt|rear lateral|reverse fly|reverse flye|reverse machine fly|face pull|bent over.*(raise|lateral))' THEN 'deltoide_posterior'
  WHEN primary_muscle = 'shoulders' AND name_en ~* 'upright row' THEN 'remo_menton'
  WHEN primary_muscle = 'shoulders' AND name_en ~* '(shoulder press|military|overhead press|arnold|push press|seated.*\mpress\M|standing.*\mpress\M)' THEN 'empuje_vertical_hombro'
  WHEN primary_muscle = 'shoulders' AND name_en ~* '\mpress\M' THEN 'empuje_vertical_hombro'

  -- TRAPECIOS
  WHEN primary_muscle = 'traps' AND name_en ~* 'shrug' THEN 'encogimiento_trapecio'
  WHEN primary_muscle = 'traps' AND name_en ~* 'upright row' THEN 'remo_menton'

  -- ESPALDA  (FIX: pullover/straight-arm ANTES que pulldown; \mrows?\M plural)
  WHEN primary_muscle = 'lats' AND name_en ~* '(pullover|straight-arm|straight arm)' THEN 'pullover'
  WHEN primary_muscle = 'lats' AND name_en ~* '(pulldown|pull-down|pull down)' THEN 'jalon_vertical'
  WHEN primary_muscle = 'lats' AND name_en ~* '(pull-?up|pullup|chin-?up|chinup|chin up)' THEN 'jalon_vertical'
  WHEN primary_muscle IN ('lats','middle back') AND name_en ~* '\mrows?\M' THEN 'remo_horizontal'
  WHEN primary_muscle = 'middle back' AND name_en ~* 'shrug' THEN 'encogimiento_trapecio'
  WHEN primary_muscle = 'middle back' AND name_en ~* '(pulldown|pull-?up|pullup)' THEN 'jalon_vertical'
  WHEN primary_muscle = 'lower back' AND name_en ~* '(hyperextension|back extension)' THEN 'extension_lumbar'
  WHEN primary_muscle = 'lower back' AND name_en ~* '(good morning|deadlift)' THEN 'bisagra_cadera'

  -- BÍCEPS / ANTEBRAZO
  WHEN primary_muscle = 'biceps' AND name_en ~* '(hammer|cross body)' THEN 'curl_martillo_braquial'
  WHEN primary_muscle = 'biceps' AND name_en ~* 'reverse.*curl' THEN 'curl_martillo_braquial'
  WHEN primary_muscle = 'biceps' AND name_en ~* 'curl' THEN 'curl_biceps'
  WHEN primary_muscle = 'forearms' AND name_en ~* '(reverse curl|hammer)' THEN 'curl_martillo_braquial'
  WHEN primary_muscle = 'forearms' AND name_en ~* 'wrist curl' THEN 'flexion_muneca'

  -- TRÍCEPS
  WHEN primary_muscle = 'triceps' AND name_en ~* '(pushdown|push-down|push down)' THEN 'extension_triceps_pushdown'
  WHEN primary_muscle = 'triceps' AND name_en ~* 'kickback' THEN 'extension_triceps_kickback'
  WHEN primary_muscle = 'triceps' AND name_en ~* '(close-grip|close grip).*bench' THEN 'press_cerrado'
  WHEN primary_muscle = 'triceps' AND name_en ~* '\mdips?\M' THEN 'fondos_paralelas'
  WHEN primary_muscle = 'triceps' AND name_en ~* '(overhead|french|skull|nose breaker|triceps press|lying.*(extension|triceps)|extension)' THEN 'extension_triceps_overhead'

  -- CUÁDRICEPS
  WHEN primary_muscle = 'quadriceps' AND name_en ~* 'leg extension' THEN 'extension_rodilla'
  WHEN primary_muscle = 'quadriceps' AND name_en ~* '(split squat|bulgarian|\mlunges?\M)' THEN 'zancada_unilateral'
  WHEN primary_muscle = 'quadriceps' AND name_en ~* '(squat|leg press|hack)' AND name_en !~* '(jump|jerk|clean|snatch|depth|sprint|box jump)' THEN 'sentadilla_prensa'

  -- ISQUIOTIBIALES
  WHEN primary_muscle = 'hamstrings' AND name_en ~* 'leg curl' THEN 'flexion_rodilla'
  WHEN primary_muscle = 'hamstrings' AND name_en ~* '(glute ham|nordic)' THEN 'flexion_rodilla'
  WHEN primary_muscle = 'hamstrings' AND name_en ~* '(romanian|stiff-leg|stiff leg|good morning|deadlift)' THEN 'bisagra_cadera'

  -- GLÚTEOS
  WHEN primary_muscle = 'glutes' AND name_en ~* '(hip thrust|glute bridge)' THEN 'extension_cadera_gluteo'
  WHEN primary_muscle = 'glutes' AND name_en ~* '(kickback|kick back)' THEN 'extension_cadera_gluteo'
  WHEN primary_muscle = 'glutes' AND name_en ~* '(\mlunges?\M|split squat)' THEN 'zancada_unilateral'
  WHEN primary_muscle = 'glutes' AND name_en ~* '(squat|leg press|hack)' AND name_en !~* '(jump|jerk|clean|snatch|depth|sprint|box jump)' THEN 'sentadilla_prensa'

  -- ABDUCTORES / ADUCTORES
  WHEN primary_muscle = 'abductors' THEN 'abduccion_cadera'
  WHEN primary_muscle = 'adductors' THEN 'aduccion_cadera'

  -- GEMELOS / SÓLEO
  WHEN primary_muscle = 'calves' AND name_en ~* 'seated' THEN 'gemelo_sentado'
  WHEN primary_muscle = 'calves' AND name_en ~* '(calf|calves|\mtoes?\M)' THEN 'gemelo_de_pie'

  -- CORE
  WHEN primary_muscle = 'abdominals' AND name_en ~* '(rollout|roller|ab wheel|\mplank\M)' THEN 'core_anti_extension'
  WHEN primary_muscle = 'abdominals' AND name_en ~* '(russian twist|woodchop|wood chop|oblique|side bend|\mtwists?\M)' THEN 'core_rotacion'
  WHEN primary_muscle = 'abdominals' AND name_en ~* '(crunch|sit-?up|leg raise|knee raise|leg-hip|v-up|jackknife|\mraises?\M)' THEN 'core_flexion'

  ELSE NULL
END;

SELECT
  COALESCE(patron_movimiento, '(SIN CLASIFICAR · NULL)') AS patron,
  COUNT(*) AS n
FROM mypump_ejercicios_catalogo
GROUP BY patron_movimiento
ORDER BY (patron_movimiento IS NULL), n DESC;
