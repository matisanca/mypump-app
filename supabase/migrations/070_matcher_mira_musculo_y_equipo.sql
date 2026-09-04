-- 070_matcher_mira_musculo_y_equipo.sql
--
-- LAS IMÁGENES DE LOS EJERCICIOS SEGUÍAN SALIENDO MAL.
--
-- Mati lo vio el 3-sep en su propia app: "Extensión en polea con cuerda agarre
-- neutro (cabeza medial)" mostraba a alguien parado en un rack. La imagen era
-- `Sled_Overhead_Triceps_Extension` — un TRINEO. Auditadas las rutinas activas:
-- 373 pares (nombre, imagen) distintos y 34 indiscutiblemente mal.
--
-- La muestra de lo que estaba pasando:
--
--   Abductores en máquina          -> Iliotibial_Tract-SMR   (un foam roller)
--   Abductores en máquina sentado  -> IT_Band_and_Glute_Stretch (un estiramiento)
--   Curl femoral en máquina        -> Ball_Leg_Curl          (una pelota suiza)
--   Crunch en máquina              -> Bosu_Ball_Cable_Crunch (un bosu)
--   Aperturas en pec deck          -> Bodyweight_Flyes       (sin máquina)
--   Extensión en polea con cuerda  -> Sled_Overhead_Triceps  (un trineo)
--
-- LA CAUSA, QUE NO ES EL UMBRAL
-- El 2-ago se endureció el matcher para exigir un match INEQUÍVOCO (que el
-- primero le saque ventaja al segundo). Eso redujo el ruido pero no podía
-- arreglarlo, porque el problema no es cuánta ventaja saca: es CONTRA QUÉ se
-- compara.
--
-- La función puntúa por trigramas del nombre en ESPAÑOL contra el name_en en
-- INGLÉS —que es ruido— y contra `aliases_es`, que no son nombres de ejercicio
-- sino etiquetas de GRUPO MUSCULAR (Zercher_Squats tiene ['sentadilla',
-- 'cuadriceps']). Así que gana cualquiera del grupo que por casualidad puntúe
-- un poco más alto, y un foam roller de banda iliotibial puntúa igual que la
-- máquina de abductores.
--
-- Mientras tanto la tabla tiene DOS COLUMNAS que resuelven esto y que la
-- función nunca miró: `primary_muscle` y `equipment`.
--
-- LO QUE HACE ESTA MIGRACIÓN
--
--   1. FILTRO DURO POR MÚSCULO. Los nombres que escribe el generador casi
--      siempre dicen el músculo entre paréntesis ("(cabeza medial)",
--      "(glúteo medio)", "(isquiotibiales)"). Si el nombre nombra un músculo,
--      solo compiten los ejercicios de ese músculo. Esto solo ya mata la mitad.
--
--   2. FILTRO DURO CONTRA APARATOS QUE NO SON EL GESTO. Un estiramiento, un
--      foam roll, un trineo o una pelota nunca son la foto de un ejercicio de
--      fuerza en máquina o polea. Se excluyen salvo que el nombre los pida.
--
--   3. EL EQUIPO PESA, PERO NO EXCLUYE. "polea" contra 'cable' suma; "polea"
--      contra 'barbell' resta. No excluye a propósito: un curl spider con
--      mancuernas ilustrado con barra Z es el MISMO gesto y se entiende
--      perfecto. Lo que no se entiende es una pelota suiza cuando decís máquina.
--
-- El contrato no cambia: mismos parámetros, mismas columnas, mismo orden. El
-- que llama (matchearImagenesEjercicios) sigue exigiendo que el match sea
-- inequívoco y con score >= 0.5, y esa guarda queda intacta: esto le da
-- candidatos mejores, no le afloja el criterio.
BEGIN;

-- Cambia el cuerpo, no la firma ni el tipo de retorno, así que CREATE OR
-- REPLACE alcanza. (Si algún día se le suma una columna al RETURNS TABLE hay
-- que DROPear primero — ver la 067 y la 068, donde ya me lo olvidé una vez.)
CREATE OR REPLACE FUNCTION mypump_match_ejercicio_por_nombre(p_query text)
RETURNS TABLE (
  slug_en          text,
  name_en          text,
  image_eccentric  text,
  image_concentric text,
  score            real
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_norm      TEXT;
  v_musculos  TEXT[] := NULL;   -- NULL = el nombre no dice el músculo
  v_equipos   TEXT[] := NULL;   -- NULL = el nombre no dice el equipo
  v_quiere_raro BOOLEAN;
BEGIN
  v_norm := lower(coalesce(p_query, ''));
  v_norm := translate(v_norm,
    'áéíóúàèìòùäëïöüâêîôûãõñç',
    'aeiouaeiouaeiouaeiouaonc'
  );
  -- OJO: los paréntesis se sacan DESPUÉS de leer el músculo. El nombre pone
  -- ahí justamente el dato más útil —"(cabeza medial)", "(glúteo medio)"— y la
  -- versión vieja lo tiraba a la basura antes de mirarlo.
  v_norm := regexp_replace(v_norm, '-d\d+-\d+', ' ', 'g');
  v_norm := regexp_replace(v_norm, '[^a-z0-9 ()]+', ' ', 'g');
  v_norm := regexp_replace(v_norm, '\s+', ' ', 'g');
  v_norm := trim(v_norm);
  IF v_norm = '' THEN RETURN; END IF;

  -- ── 1. Qué músculo dice el nombre ────────────────────────────────────────
  -- El orden importa: "extension de cuadriceps" tiene que caer en cuádriceps y
  -- no en tríceps por la palabra "extension".
  v_musculos := CASE
    WHEN v_norm ~ 'triceps|cabeza (larga|lateral|medial)' THEN ARRAY['triceps']
    WHEN v_norm ~ 'biceps|braquial|predicador|spider'     THEN ARRAY['biceps']
    WHEN v_norm ~ 'antebrazo|muneca|braquiorradial'       THEN ARRAY['forearms','biceps']
    -- La espalda va ANTES que el pecho a proposito: en "jalon AL PECHO" la
    -- palabra pecho dice adonde va la barra, no que musculo entrena. Con el
    -- orden invertido, un jalon al pecho matcheaba con un Cable Chest Press.
    WHEN v_norm ~ 'dorsal|espalda|jalon|remo|pullover|dominada' THEN ARRAY['lats','middle back','traps','lower back']
    WHEN v_norm ~ 'pectoral|pecho|pec deck|aperturas'     THEN ARRAY['chest']
    WHEN v_norm ~ 'cuadriceps|sentadilla|prensa|zancada'  THEN ARRAY['quadriceps','glutes']
    WHEN v_norm ~ 'femoral|isquio'                        THEN ARRAY['hamstrings']
    WHEN v_norm ~ 'gluteo|hip thrust'                     THEN ARRAY['glutes','hamstrings','abductors','adductors']
    WHEN v_norm ~ 'abductor'                              THEN ARRAY['abductors','glutes']
    WHEN v_norm ~ 'aductor'                               THEN ARRAY['adductors']
    WHEN v_norm ~ 'deltoide|hombro|elevacion(es)? later'  THEN ARRAY['shoulders']
    WHEN v_norm ~ 'gemelo|talon|pantorrilla|soleo'        THEN ARRAY['calves']
    WHEN v_norm ~ 'abdominal|oblicuo|crunch|plancha'      THEN ARRAY['abdominals']
    WHEN v_norm ~ 'trapecio|encogimiento'                 THEN ARRAY['traps']
    ELSE NULL
  END;

  -- ── 2. Qué equipo dice el nombre ─────────────────────────────────────────
  -- "polea alta con barra recta" es una POLEA con un accesorio de barra, no
  -- una barra libre: por eso la polea se evalúa primero.
  v_equipos := CASE
    WHEN v_norm ~ 'polea|cable|crossover'   THEN ARRAY['cable']
    WHEN v_norm ~ 'mancuerna'               THEN ARRAY['dumbbell']
    WHEN v_norm ~ 'kettlebell|pesa rusa'    THEN ARRAY['kettlebells']
    WHEN v_norm ~ 'multipower|smith'        THEN ARRAY['barbell','machine']
    WHEN v_norm ~ 'maquina|pec deck|prensa' THEN ARRAY['machine']
    WHEN v_norm ~ 'barra'                   THEN ARRAY['barbell','e-z curl bar']
    ELSE NULL
  END;

  -- ¿El nombre pide de verdad un estiramiento / movilidad / trineo?
  v_quiere_raro := v_norm ~ 'estiramiento|movilidad|foam|liberacion|trineo|sled|pelota|bosu|fitball';

  -- Recién ahora se tiran los paréntesis, para comparar el texto.
  v_norm := regexp_replace(v_norm, '\(.*?\)', ' ', 'g');
  v_norm := regexp_replace(v_norm, '[^a-z0-9 ]+', ' ', 'g');
  v_norm := regexp_replace(v_norm, '\s+', ' ', 'g');
  v_norm := trim(v_norm);
  IF v_norm = '' THEN RETURN; END IF;

  RETURN QUERY
    WITH candidatos AS (
      SELECT c.slug_en, c.name_en, c.image_eccentric, c.image_concentric,
             c.equipment, c.aliases_es, c.name_normalized
        FROM mypump_ejercicios_catalogo c
       WHERE
         -- FILTRO 1: el músculo, cuando el nombre lo dice.
         (v_musculos IS NULL OR c.primary_muscle = ANY(v_musculos))
         -- FILTRO 2: nada de estiramientos, foam rolls, trineos ni pelotas
         -- cuando lo que se pidió es un ejercicio de fuerza.
         AND (v_quiere_raro OR (
                coalesce(c.equipment,'') NOT IN ('foam roll','exercise ball','medicine ball')
            AND c.name_en !~* '(stretch|-smr|\ysmr\y|\ysled\y|\ybosu\y|\yball\y)'
         ))
    ),
    base AS (
      SELECT
        k.slug_en, k.name_en, k.image_eccentric, k.image_concentric,
        GREATEST(
          CASE WHEN v_norm = ANY(k.aliases_es) THEN 1.0::REAL ELSE 0 END,
          coalesce(similarity(k.name_normalized, v_norm), 0),
          coalesce((SELECT max(similarity(a, v_norm)) FROM unnest(k.aliases_es) AS a), 0)
        )::REAL AS bruto,
        -- FILTRO 3 (blando): el equipo suma o resta, no excluye.
        (CASE
          WHEN v_equipos IS NULL OR k.equipment IS NULL THEN 0
          WHEN k.equipment = ANY(v_equipos)             THEN 0.20
          ELSE -0.20
        END
        -- FILTRO 4 (blando): la ESPECIFICIDAD que nadie pidio.
        --
        -- Los alias son etiquetas de grupo muscular, asi que dentro de un grupo
        -- todos empatan y gana cualquiera. El desempate que faltaba: si el
        -- ejercicio del catalogo dice "Lying", "One-Arm" o "Rear" y el nombre
        -- en español NO lo pide, es una variante mas específica de la que se
        -- pidió y no deberia ganarle a la version simple.
        --
        -- Sin esto, "Elevaciones laterales con mancuernas" ganaba con un
        -- "Dumbbell Lying One-Arm REAR Lateral Raise" — acostado, a un brazo y
        -- de deltoides posterior. Las tres cosas de mas.
        - (CASE WHEN k.name_en ~* '\ylying\y'      AND v_norm !~ 'tumbad|acostad|tendid' THEN 0.10 ELSE 0 END)
        - (CASE WHEN k.name_en ~* '\yseated\y'     AND v_norm !~ 'sentad'                THEN 0.06 ELSE 0 END)
        - (CASE WHEN k.name_en ~* 'one.?arm|single' AND v_norm !~ 'un brazo|unilateral'   THEN 0.10 ELSE 0 END)
        - (CASE WHEN k.name_en ~* '\yrear\y'       AND v_norm !~ 'posterior'             THEN 0.12 ELSE 0 END)
        - (CASE WHEN k.name_en ~* 'incline'         AND v_norm !~ 'inclinad'              THEN 0.08 ELSE 0 END)
        - (CASE WHEN k.name_en ~* 'decline'         AND v_norm !~ 'declinad'              THEN 0.08 ELSE 0 END)
        - (CASE WHEN k.name_en ~* 'reverse'         AND v_norm !~ 'inverso|invertid'      THEN 0.08 ELSE 0 END)
        - (CASE WHEN k.name_en ~* 'behind'          AND v_norm !~ 'nuca|detras'           THEN 0.10 ELSE 0 END)
        - (CASE WHEN k.name_en ~* 'kneeling'        AND v_norm !~ 'arrodillad|rodilla'    THEN 0.08 ELSE 0 END)
        )::REAL AS ajuste
      FROM candidatos k
    )
    SELECT b.slug_en, b.name_en, b.image_eccentric, b.image_concentric,
           GREATEST(0, LEAST(1, b.bruto + b.ajuste))::REAL AS score
      FROM base b
     WHERE b.bruto > 0.25
     ORDER BY (b.bruto + b.ajuste) DESC, b.slug_en
     LIMIT 5;
END;
$$;

REVOKE ALL ON FUNCTION mypump_match_ejercicio_por_nombre(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION mypump_match_ejercicio_por_nombre(text) TO authenticated, service_role;

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
