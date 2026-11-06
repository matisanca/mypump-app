-- 079_revert.sql — vuelve las 4 funciones a como estaban el 3-nov-2026 antes de la 079 (pg_get_functiondef) y borra lo nuevo.
BEGIN;
CREATE OR REPLACE FUNCTION public.mypump_match_ejercicio_por_nombre(p_query text)
 RETURNS TABLE(slug_en text, name_en text, image_eccentric text, image_concentric text, score real)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$

;

CREATE OR REPLACE FUNCTION public.mypump_publicar_cliente(p_cliente_id text, p_nombre text, p_perfil text, p_rutina jsonb, p_dieta jsonb)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_token TEXT; v_rid UUID; v_did UUID; v_rv INT; v_dv INT;
  v_old_rutina JSONB; v_merged_rutina JSONB;
BEGIN
  IF auth.role() <> 'authenticated' THEN RAISE EXCEPTION 'Acceso denegado'; END IF;
  SELECT access_token INTO v_token FROM mypump_clientes WHERE cliente_id=p_cliente_id;
  IF v_token IS NULL THEN
    v_token := generate_mypump_token();
    INSERT INTO mypump_clientes (cliente_id,nombre,perfil,access_token) VALUES (p_cliente_id,p_nombre,p_perfil,v_token);
  ELSE
    UPDATE mypump_clientes SET nombre=p_nombre, perfil=p_perfil, updated_at=NOW() WHERE cliente_id=p_cliente_id;
  END IF;
  SELECT id,version,estructura INTO v_rid,v_rv,v_old_rutina FROM mypump_rutinas WHERE cliente_id=p_cliente_id AND estado='activa';
  IF v_rid IS NOT NULL THEN
    WITH old_imgs AS (
      SELECT lower(trim(e->>'nombre')) AS nk, e->'images' AS img
      FROM jsonb_array_elements(v_old_rutina->'dias') d,
           jsonb_array_elements(d->'bloques') b,
           jsonb_array_elements(b->'ejercicios') e
      WHERE e->'images'->>'eccentric' IS NOT NULL
    ),
    new_dias AS (
      SELECT jsonb_agg(
        jsonb_set(d,'{bloques}',
          (SELECT jsonb_agg(jsonb_set(b,'{ejercicios}',
            (SELECT jsonb_agg(
              CASE WHEN (e->'images'->>'eccentric') IS NULL
                   AND (SELECT img FROM old_imgs WHERE nk=lower(trim(e->>'nombre')) LIMIT 1) IS NOT NULL
                   THEN jsonb_set(e,'{images}',(SELECT img FROM old_imgs WHERE nk=lower(trim(e->>'nombre')) LIMIT 1))
                   ELSE e END
            ) FROM jsonb_array_elements(b->'ejercicios') e)
          )) FROM jsonb_array_elements(d->'bloques') b)
        )
      ) AS dm FROM jsonb_array_elements(p_rutina->'dias') d
    )
    SELECT jsonb_set(p_rutina,'{dias}',dm) INTO v_merged_rutina FROM new_dias;
    UPDATE mypump_rutinas SET estructura=COALESCE(v_merged_rutina,p_rutina), version=v_rv+1, updated_at=NOW() WHERE id=v_rid;
  ELSE
    SELECT COALESCE(MAX(version),0)+1 INTO v_rv FROM mypump_rutinas WHERE cliente_id=p_cliente_id;
    INSERT INTO mypump_rutinas (cliente_id,version,estado,estructura,created_by,fecha_inicio) VALUES (p_cliente_id,v_rv,'activa',p_rutina,auth.uid(),CURRENT_DATE);
  END IF;
  SELECT id,version INTO v_did,v_dv FROM mypump_dietas WHERE cliente_id=p_cliente_id AND estado='activa';
  IF v_did IS NOT NULL THEN
    UPDATE mypump_dietas SET estructura=p_dieta, version=v_dv+1, updated_at=NOW() WHERE id=v_did;
  ELSE
    SELECT COALESCE(MAX(version),0)+1 INTO v_dv FROM mypump_dietas WHERE cliente_id=p_cliente_id;
    INSERT INTO mypump_dietas (cliente_id,version,estado,estructura,created_by) VALUES (p_cliente_id,v_dv,'activa',p_dieta,auth.uid());
  END IF;
  RETURN v_token;
END; $function$

;

CREATE OR REPLACE FUNCTION public.mypump_encolar_siguiente(p_cliente_id text, p_estructura jsonb)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  UPDATE mypump_rutinas SET estructura_siguiente = p_estructura, updated_at = NOW()
   WHERE cliente_id = p_cliente_id AND estado = 'activa';
  RETURN FOUND;
END;
$function$

;

CREATE OR REPLACE FUNCTION public.mypump_set_ejercicio_imagen(p_rutina_id uuid, p_dia_idx integer, p_bloque_idx integer, p_ejercicio_idx integer, p_slug_en text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_image_ec TEXT;
  v_image_co TEXT;
  v_new_imgs JSONB;
  v_path TEXT[];
BEGIN
  IF auth.role() <> 'authenticated' THEN
    RAISE EXCEPTION 'Acceso denegado';
  END IF;

  IF p_slug_en IS NULL THEN
    v_new_imgs := 'null'::jsonb;
  ELSE
    SELECT image_eccentric, image_concentric
      INTO v_image_ec, v_image_co
      FROM mypump_ejercicios_catalogo
     WHERE slug_en = p_slug_en;

    IF v_image_ec IS NULL THEN
      RAISE EXCEPTION 'Ejercicio del cat√°logo no encontrado: %', p_slug_en;
    END IF;

    v_new_imgs := jsonb_build_object(
      'eccentric',  v_image_ec,
      'concentric', v_image_co
    );
  END IF;

  v_path := ARRAY['dias', p_dia_idx::TEXT, 'bloques', p_bloque_idx::TEXT, 'ejercicios', p_ejercicio_idx::TEXT, 'images'];

  UPDATE mypump_rutinas
     SET estructura = jsonb_set(estructura, v_path, v_new_imgs, true)
   WHERE id = p_rutina_id;

  RETURN FOUND;
END;
$function$

;

DROP FUNCTION IF EXISTS public.mypump_slug_curado(text);
DROP FUNCTION IF EXISTS public.mypump_conservar_fotos(jsonb, jsonb[]);
DROP TABLE IF EXISTS public.mypump_alias_fotos;
COMMIT;
