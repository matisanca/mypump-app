-- 079_fotos_curadas_no_se_pisan.sql
--
-- Un Publicar o un Encolar del Cerebro ya no pisa las fotos de ejercicio
-- guardadas, y el matcher consulta primero la tabla curada.
--
-- Bug (3-nov-2026): esa noche se corrigieron en la base las fotos de las rutinas
-- (2.284 ejercicios sin foto la recibieron y se arreglaron 100 que mostraban otro
-- ejercicio). El Cerebro las deshacía en silencio:
--   · expandirRutinaParaMyPump manda images = null y matchearImagenesEjercicios le
--     pone la foto de mypump_match_ejercicio_por_nombre, sin _matched_slug;
--   · mypump_publicar_cliente (013/014) conservaba la foto vieja solo si la nueva
--     venía sin eccentric, así que ganaba la del matcher, y catalogo_slug nunca
--     se conservaba;
--   · mypump_encolar_siguiente (025) guardaba la cola tal cual llegaba.
-- Medido esa noche: un Publicar revertía ~64 de las 100 correcciones y cambiaba
-- 176 fotos guardadas.
--
-- Regla nueva, en el servidor para que cubra todas las pestañas abiertas del
-- Cerebro con el JS que tengan: si ya hay una foto guardada para ese nombre de
-- ejercicio, se conservan su images y su catalogo_slug, que salen del mismo slug.
-- La nueva gana solo si trae images._matched_slug, que lo ponen únicamente los
-- scripts curados (pumplib.foto_ejercicio) y «Revisar matches». El matcher queda
-- para llenar huecos.
--   · "Foto guardada" = images.eccentric o catalogo_slug no vacíos. Con
--     catalogo_slug solo, las apps ya muestran la foto de ese slug.
--   · El nombre se compara en minúsculas y sin espacios de más, como en la 014.
--   · Dónde se busca: publicar mira primero la rutina activa y después la cola;
--     encolar, primero la cola que reemplaza y después la rutina activa, porque
--     un bloque nuevo repite ejercicios. Una foto de la primera fuente le gana
--     siempre a una de la segunda.
--   · Dentro de una fuente, si el nombre está más de una vez con fotos
--     distintas, gana el del mismo día, después el curado y después el que tiene
--     catalogo_slug.
-- Además:
--   · Los jsonb_agg llevan COALESCE. Antes, un día sin bloques o un bloque sin
--     ejercicios quedaba en null (jsonb_set con null devuelve null). Y llevan
--     ORDER BY sobre WITH ORDINALITY, para no depender del orden del plan.
--   · publicar lee la rutina activa con FOR NO KEY UPDATE, la misma traba que
--     toma su UPDATE: nada la cambia entre que se leen las fotos guardadas y se
--     escribe. FOR UPDATE no, porque frenaría el FOR KEY SHARE de las claves
--     foráneas de mypump_sesiones y mypump_registros_carga: la app no podría
--     iniciar sesiones ni cargar series mientras un script tiene la fila.
--   · mypump_set_ejercicio_imagen («Revisar matches») escribe _matched_slug y
--     catalogo_slug del mismo slug. No escribe nada si el índice ya no existe o
--     si ese ejercicio ya tiene foto: «Revisar matches» solo lista ejercicios sin
--     foto, así que un índice viejo (la rutina se republicó mientras tanto) no
--     pisa la foto de otro ejercicio.
--   · mypump_match_ejercicio_por_nombre consulta primero mypump_alias_fotos (los
--     «seguro» y los «completos» de ~/pump-tools/alias_fotos.json, con la misma
--     lectura que pumplib.slug_foto). Si el nombre está, ese slug va primero con
--     score 1 y el resto queda en 0,9 o menos, así el Cerebro lo toma como
--     inequívoco. aliases_es del catálogo no se toca.
-- La tabla se vuelve a cargar con ~/pump-tools/alias_fotos_a_base.py cuando
-- cambia alias_fotos.json.

-- ── Fotos guardadas que se conservan ────────────────────────────────────────
-- p_nueva: la estructura que llega. p_guardadas: las estructuras guardadas, en
-- orden de prioridad (puede haber nulls). Devuelve p_nueva con images y
-- catalogo_slug de la foto guardada en cada ejercicio que no trae una curada.
CREATE OR REPLACE FUNCTION public.mypump_conservar_fotos(p_nueva jsonb, p_guardadas jsonb[])
 RETURNS jsonb
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
  -- MATERIALIZED: se arma una vez, no una por cada ejercicio de p_nueva.
  WITH guardadas AS MATERIALIZED (
    SELECT f.fo, dd.d->>'id' AS dia_id, dd.dord, bb.bo, ee.eo,
           btrim(regexp_replace(lower(ee.e->>'nombre'), '\s+', ' ', 'g')) AS k,
           ee.e->'images' AS img,
           ee.e->'catalogo_slug' AS slug,
           nullif(ee.e->'images'->>'_matched_slug', '') IS NOT NULL AS curada,
           nullif(ee.e->>'catalogo_slug', '') IS NOT NULL AS con_slug
      FROM unnest(p_guardadas) WITH ORDINALITY f(est, fo)
     CROSS JOIN LATERAL jsonb_array_elements(CASE WHEN jsonb_typeof(f.est->'dias') = 'array'
                                                  THEN f.est->'dias' ELSE '[]' END) WITH ORDINALITY dd(d, dord)
     CROSS JOIN LATERAL jsonb_array_elements(CASE WHEN jsonb_typeof(dd.d->'bloques') = 'array'
                                                  THEN dd.d->'bloques' ELSE '[]' END) WITH ORDINALITY bb(b, bo)
     CROSS JOIN LATERAL jsonb_array_elements(CASE WHEN jsonb_typeof(bb.b->'ejercicios') = 'array'
                                                  THEN bb.b->'ejercicios' ELSE '[]' END) WITH ORDINALITY ee(e, eo)
     WHERE nullif(ee.e->'images'->>'eccentric', '') IS NOT NULL
        OR nullif(ee.e->>'catalogo_slug', '') IS NOT NULL
  )
  SELECT CASE WHEN jsonb_typeof(p_nueva->'dias') = 'array' THEN
    jsonb_set(p_nueva, '{dias}', COALESCE((
      SELECT jsonb_agg(CASE WHEN jsonb_typeof(d->'bloques') = 'array' THEN
        jsonb_set(d, '{bloques}', COALESCE((
          SELECT jsonb_agg(CASE WHEN jsonb_typeof(b->'ejercicios') = 'array' THEN
            jsonb_set(b, '{ejercicios}', COALESCE((
              SELECT jsonb_agg(CASE
                  WHEN jsonb_typeof(e) <> 'object' THEN e
                  -- curada: la trae un script curado o «Revisar matches», gana la nueva
                  WHEN nullif(e->'images'->>'eccentric', '') IS NOT NULL
                   AND nullif(e->'images'->>'_matched_slug', '') IS NOT NULL THEN e
                  ELSE COALESCE((
                    SELECT e || jsonb_build_object('images', g.img, 'catalogo_slug', g.slug)
                      FROM guardadas g
                     WHERE g.k = btrim(regexp_replace(lower(e->>'nombre'), '\s+', ' ', 'g'))
                     ORDER BY g.fo, (g.dia_id IS NOT DISTINCT FROM d->>'id') DESC,
                              g.curada DESC, g.con_slug DESC, g.dord, g.bo, g.eo
                     LIMIT 1), e)
                END ORDER BY eo)
                FROM jsonb_array_elements(b->'ejercicios') WITH ORDINALITY x(e, eo)), '[]'))
            ELSE b END ORDER BY bo)
            FROM jsonb_array_elements(d->'bloques') WITH ORDINALITY y(b, bo)), '[]'))
        ELSE d END ORDER BY dord)
        FROM jsonb_array_elements(p_nueva->'dias') WITH ORDINALITY z(d, dord)), '[]'))
  ELSE p_nueva END
$function$;

REVOKE ALL ON FUNCTION public.mypump_conservar_fotos(jsonb, jsonb[]) FROM PUBLIC, anon, authenticated;

-- ── Publicar ─────────────────────────────────────────────────────────────────
-- Igual que la 014, salvo el merge de fotos (mypump_conservar_fotos).
CREATE OR REPLACE FUNCTION public.mypump_publicar_cliente(p_cliente_id text, p_nombre text, p_perfil text, p_rutina jsonb, p_dieta jsonb)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_token TEXT; v_rid UUID; v_did UUID; v_rv INT; v_dv INT;
  v_old_rutina JSONB; v_old_cola JSONB; v_merged_rutina JSONB;
BEGIN
  IF auth.role() <> 'authenticated' THEN RAISE EXCEPTION 'Acceso denegado'; END IF;
  SELECT access_token INTO v_token FROM mypump_clientes WHERE cliente_id=p_cliente_id;
  IF v_token IS NULL THEN
    v_token := generate_mypump_token();
    INSERT INTO mypump_clientes (cliente_id,nombre,perfil,access_token) VALUES (p_cliente_id,p_nombre,p_perfil,v_token);
  ELSE
    UPDATE mypump_clientes SET nombre=p_nombre, perfil=p_perfil, updated_at=NOW() WHERE cliente_id=p_cliente_id;
  END IF;
  -- 079: FOR NO KEY UPDATE (la traba del UPDATE), para que «Revisar matches» o un Encolar no cambien la fila entre esta
  -- lectura y el UPDATE. FOR UPDATE no: frenaría las claves foráneas de mypump_sesiones y mypump_registros_carga.
  SELECT id,version,estructura,estructura_siguiente INTO v_rid,v_rv,v_old_rutina,v_old_cola
    FROM mypump_rutinas WHERE cliente_id=p_cliente_id AND estado='activa' FOR NO KEY UPDATE;
  IF v_rid IS NOT NULL THEN
    -- 079: las fotos guardadas no se pisan (primero las de la rutina, después las de la cola).
    v_merged_rutina := mypump_conservar_fotos(p_rutina, ARRAY[v_old_rutina, v_old_cola]);
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
END; $function$;

-- ── Encolar ──────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.mypump_encolar_siguiente(p_cliente_id text, p_estructura jsonb)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  -- 079: las fotos guardadas no se pisan (primero las de la cola que se reemplaza,
  -- después las de la rutina activa). Con p_estructura null se cancela la cola.
  UPDATE mypump_rutinas
     SET estructura_siguiente = CASE WHEN p_estructura IS NULL THEN NULL
                                     ELSE mypump_conservar_fotos(p_estructura, ARRAY[estructura_siguiente, estructura]) END,
         updated_at = NOW()
   WHERE cliente_id = p_cliente_id AND estado = 'activa';
  RETURN FOUND;
END;
$function$;

-- ── «Revisar matches» ────────────────────────────────────────────────────────
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
      RAISE EXCEPTION 'Ejercicio del catálogo no encontrado: %', p_slug_en;
    END IF;

    -- 079: con _matched_slug, para que un Publicar del Cerebro la trate como curada.
    v_new_imgs := jsonb_build_object(
      'eccentric',     v_image_ec,
      'concentric',    v_image_co,
      '_matched_slug', p_slug_en
    );
  END IF;

  v_path := ARRAY['dias', p_dia_idx::TEXT, 'bloques', p_bloque_idx::TEXT, 'ejercicios', p_ejercicio_idx::TEXT];

  -- 079: images y catalogo_slug del MISMO slug (las apps sacan el músculo de
  -- catalogo_slug). No escribe si el índice ya no existe o si el ejercicio ya
  -- tiene foto: «Revisar matches» solo lista los que no tienen (renderEjReview),
  -- así que es un índice viejo que apunta a otro ejercicio.
  UPDATE mypump_rutinas
     SET estructura = jsonb_set(estructura, v_path,
           (estructura #> v_path) || jsonb_build_object('images', v_new_imgs, 'catalogo_slug', p_slug_en))
   WHERE id = p_rutina_id
     AND jsonb_typeof(estructura #> v_path) = 'object'
     AND COALESCE(estructura #>> (v_path || '{images,eccentric}'::TEXT[]), '') = ''
     AND COALESCE(estructura #>> (v_path || '{images,concentric}'::TEXT[]), '') = '';

  RETURN FOUND;
END;
$function$;

-- ── Tabla curada (a) ─────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.mypump_alias_fotos (
  completo   BOOLEAN NOT NULL,   -- true: «completos», la clave lleva los paréntesis; false: «alias», sin paréntesis
  clave      TEXT NOT NULL,      -- minúsculas, sin tildes, espacios colapsados (pumplib.norm_ejercicio)
  slug_en    TEXT NOT NULL REFERENCES public.mypump_ejercicios_catalogo(slug_en) ON UPDATE CASCADE,
  nota       TEXT,
  cargado_en TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (completo, clave)
);
COMMENT ON TABLE public.mypump_alias_fotos IS
  'Nombre de ejercicio → slug del catálogo, solo los matches «seguro» de ~/pump-tools/alias_fotos.json (3-nov-2026). '
  'La consulta mypump_match_ejercicio_por_nombre antes que aliases_es. Se recarga con ~/pump-tools/alias_fotos_a_base.py.';
ALTER TABLE public.mypump_alias_fotos ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.mypump_alias_fotos FROM PUBLIC, anon, authenticated;

-- Slug curado para un nombre, o null. La misma lectura que pumplib.slug_foto:
-- 1. el nombre completo con paréntesis («completos»);
-- 2. sin lo que va entre paréntesis («alias»), salvo que el paréntesis nombre un
--    equipo que el resto del nombre no dice («Patada trasera (con polea)»).
CREATE OR REPLACE FUNCTION public.mypump_slug_curado(p_nombre text)
 RETURNS text
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public'
AS $function$
DECLARE
  v_cruda TEXT;   -- minúsculas y sin tildes, con paréntesis y signos (pumplib._sin_tildes)
  v_clave TEXT;
  v_slug  TEXT;
BEGIN
  v_cruda := lower(regexp_replace(normalize(coalesce(p_nombre, ''), NFD), '[̀-ͯ]', '', 'g'));

  SELECT a.slug_en INTO v_slug FROM mypump_alias_fotos a
   WHERE a.completo AND a.clave = trim(regexp_replace(v_cruda, '\s+', ' ', 'g'));
  IF v_slug IS NOT NULL THEN RETURN v_slug; END IF;

  v_clave := trim(regexp_replace(regexp_replace(v_cruda, '\(.*?\)', '', 'g'), '\s+', ' ', 'g'));
  IF EXISTS (
    SELECT 1
      FROM regexp_matches(
             coalesce((SELECT string_agg(p[1], ' ') FROM regexp_matches(v_cruda, '\((.*?)\)', 'g') p), ''),
             '\y(polea|cable|maquina|mancuernas?|barra|multipower|smith|pec deck|bandas?|belt|prensa|kettlebell|pesa rusa|disco|landmine|trx|paralelas|hack|sentadilla|squat)\y',
             'g') w
     WHERE strpos(v_clave, w[1]) = 0
  ) THEN
    RETURN NULL;
  END IF;

  SELECT a.slug_en INTO v_slug FROM mypump_alias_fotos a WHERE NOT a.completo AND a.clave = v_clave;
  RETURN v_slug;
END;
$function$;

REVOKE ALL ON FUNCTION public.mypump_slug_curado(text) FROM PUBLIC, anon, authenticated;

-- ── Matcher ──────────────────────────────────────────────────────────────────
-- Igual que la 070, con el paso 0 (la tabla curada) y el tope del resto.
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
  v_curado    TEXT;             -- 079: slug de mypump_alias_fotos, si el nombre está ahí
  v_tope      REAL := 1;        -- 079: con un curado primero, el resto queda en 0,9 o menos
BEGIN
  -- ── 0. La tabla curada (079) ─────────────────────────────────────────────
  -- Si el nombre está en mypump_alias_fotos, ese slug va primero con score 1.
  -- Matchear siempre empata en 1 cuando el alias es exacto, y el Cerebro solo
  -- toma un match inequívoco (top > segundo + 0,01): por eso el resto se
  -- recorta a 0,9 y no repite el curado.
  v_curado := mypump_slug_curado(p_query);
  IF v_curado IS NOT NULL THEN
    RETURN QUERY
      SELECT c.slug_en, c.name_en, c.image_eccentric, c.image_concentric, 1::REAL
        FROM mypump_ejercicios_catalogo c
       WHERE c.slug_en = v_curado;
    IF FOUND THEN v_tope := 0.9; ELSE v_curado := NULL; END IF;
  END IF;

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
           LEAST(v_tope, GREATEST(0, LEAST(1, b.bruto + b.ajuste)))::REAL AS score
      FROM base b
     WHERE b.bruto > 0.25
       AND b.slug_en IS DISTINCT FROM v_curado
     ORDER BY (b.bruto + b.ajuste) DESC, b.slug_en
     LIMIT CASE WHEN v_curado IS NULL THEN 5 ELSE 4 END;
END;
$function$;

-- Carga del 3-nov-2026: los «seguro» de alias_fotos.json (alias_fotos_a_base.py --sql).
INSERT INTO public.mypump_alias_fotos (completo, clave, slug_en, nota) VALUES
  (false, 'abdominales colgados en barra', 'Hanging_Leg_Raise', NULL),
  (false, 'abdominales en bisagra', 'Jackknife_Sit-Up', 'cuerpo en V'),
  (false, 'abduccion de cadera en maquina', 'Thigh_Abductor', 'máquina de abductores'),
  (false, 'abduccion en maquina', 'Thigh_Abductor', 'máquina de abductores'),
  (false, 'abductor en maquina', 'Thigh_Abductor', 'máquina de abductores'),
  (false, 'abductores', 'Thigh_Abductor', 'máquina de abductores'),
  (false, 'abductores en maquina', 'Thigh_Abductor', 'máquina de abductores'),
  (false, 'abductores en maquina con torso inclinado', 'Thigh_Abductor', 'máquina de abductores'),
  (false, 'abductores en maquina sentado', 'Thigh_Abductor', 'máquina de abductores'),
  (false, 'aductores', 'Thigh_Adductor', 'máquina de aductores'),
  (false, 'aductores en maquina', 'Thigh_Adductor', 'máquina de aductores'),
  (false, 'aperturas con mancuernas en banco inclinado', 'Incline_Dumbbell_Flyes', NULL),
  (false, 'aperturas en pec deck', 'Butterfly', 'pec deck'),
  (false, 'aperturas en pec deck con rotacion externa', 'Butterfly', 'pec deck'),
  (false, 'aperturas en pec deck rango parcial protegiendo hombro', 'Butterfly', 'pec deck'),
  (false, 'aperturas en pec deck — tope de apertura a la altura del pecho', 'Butterfly', 'pec deck'),
  (false, 'aperturas en pec deck, rango controlado sin hiperextender hombro', 'Butterfly', 'pec deck'),
  (false, 'aperturas en peck deck', 'Butterfly', 'pec deck'),
  (false, 'aperturas pec deck', 'Butterfly', 'pec deck'),
  (false, 'cruce de poleas', 'Cable_Crossover', 'poleas altas, de arriba hacia abajo'),
  (false, 'cruce de poleas alto a bajo', 'Cable_Crossover', 'poleas altas, de arriba hacia abajo'),
  (false, 'cruce de poleas alto a bajo con rotacion externa', 'Cable_Crossover', 'poleas altas, de arriba hacia abajo'),
  (false, 'cruce de poleas alto hacia abajo', 'Cable_Crossover', 'poleas altas, de arriba hacia abajo'),
  (false, 'cruce de poleas alto hacia bajo', 'Cable_Crossover', 'poleas altas, de arriba hacia abajo'),
  (false, 'cruce de poleas alto→bajo', 'Cable_Crossover', 'poleas altas, de arriba hacia abajo'),
  (false, 'cruce de poleas de abajo hacia arriba', 'Low_Cable_Crossover', 'de abajo hacia arriba'),
  (false, 'cruce de poleas de abajo hacia arriba — extra opcional', 'Low_Cable_Crossover', 'de abajo hacia arriba'),
  (false, 'cruce de poleas de alto a bajo', 'Cable_Crossover', 'poleas altas, de arriba hacia abajo'),
  (false, 'cruce de poleas de alto hacia bajo', 'Cable_Crossover', 'poleas altas, de arriba hacia abajo'),
  (false, 'crunch', 'Crunches', 'crunch en el piso'),
  (false, 'crunch en maquina', 'Ab_Crunch_Machine', NULL),
  (false, 'crunch en maquina — core', 'Ab_Crunch_Machine', NULL),
  (false, 'crunch en polea', 'Cable_Crunch', 'crunch de rodillas en polea alta'),
  (false, 'crunch en polea alta', 'Cable_Crunch', 'crunch de rodillas en polea alta'),
  (false, 'crunch en polea alta de rodillas', 'Cable_Crunch', 'crunch de rodillas en polea alta'),
  (false, 'curl con barra recta o ez', 'Barbell_Curl', 'primera opción: barra recta'),
  (false, 'curl con barra w', 'EZ-Bar_Curl', NULL),
  (false, 'curl con barra z', 'EZ-Bar_Curl', NULL),
  (false, 'curl con mancuernas alterno de pie supinando', 'Dumbbell_Alternate_Bicep_Curl', NULL),
  (false, 'curl con mancuernas alterno sentado', 'Seated_Dumbbell_Curl', 'sentado con mancuernas (la foto sube las dos)'),
  (false, 'curl de biceps con cable a una mano', 'Standing_One-Arm_Cable_Curl', 'de pie, polea baja, a una mano'),
  (false, 'curl en cable a una mano', 'Standing_One-Arm_Cable_Curl', 'de pie, polea baja, a una mano'),
  (false, 'curl en cable a una mano con polea baja', 'Standing_One-Arm_Cable_Curl', 'de pie, polea baja, a una mano'),
  (false, 'curl en cable a una mano con rotacion', 'Standing_One-Arm_Cable_Curl', 'de pie, polea baja, a una mano'),
  (false, 'curl en cable a una mano de pie', 'Standing_One-Arm_Cable_Curl', 'de pie, polea baja, a una mano'),
  (false, 'curl en cable a una mano polea baja', 'Standing_One-Arm_Cable_Curl', 'de pie, polea baja, a una mano'),
  (false, 'curl en polea a una mano', 'Standing_One-Arm_Cable_Curl', 'de pie, polea baja, a una mano'),
  (false, 'curl en polea a una mano de pie', 'Standing_One-Arm_Cable_Curl', 'de pie, polea baja, a una mano'),
  (false, 'curl en polea baja con barra recta', 'Standing_Biceps_Cable_Curl', NULL),
  (false, 'curl femoral acostado', 'Lying_Leg_Curls', NULL),
  (false, 'curl femoral acostado en maquina', 'Lying_Leg_Curls', NULL),
  (false, 'curl femoral parado', 'Standing_Leg_Curl', NULL),
  (false, 'curl femoral sentado', 'Seated_Leg_Curl', NULL),
  (false, 'curl femoral sentado a una pierna', 'Seated_Leg_Curl', 'a una pierna: la foto es con las dos · 3-nov: Mati aprobó sumarlo (bajo riesgo)'),
  (false, 'curl femoral sentado en maquina', 'Seated_Leg_Curl', NULL),
  (false, 'curl femoral sentado — prefatiga', 'Seated_Leg_Curl', NULL),
  (false, 'curl femoral tumbado', 'Lying_Leg_Curls', NULL),
  (false, 'curl femoral tumbado a una pierna', 'Lying_Leg_Curls', 'a una pierna: la foto es con las dos · 3-nov: Mati aprobó sumarlo (bajo riesgo)'),
  (false, 'curl femoral tumbado en maquina', 'Lying_Leg_Curls', NULL),
  (false, 'curl inclinado con mancuerna', 'Incline_Dumbbell_Curl', 'el ángulo del banco no cambia la foto'),
  (false, 'curl inclinado con mancuernas', 'Incline_Dumbbell_Curl', 'el ángulo del banco no cambia la foto'),
  (false, 'curl inclinado con mancuernas 45°', 'Incline_Dumbbell_Curl', 'el ángulo del banco no cambia la foto'),
  (false, 'curl inclinado con mancuernas 60°', 'Incline_Dumbbell_Curl', 'el ángulo del banco no cambia la foto'),
  (false, 'curl inclinado con mancuernas a 45°', 'Incline_Dumbbell_Curl', 'el ángulo del banco no cambia la foto'),
  (false, 'curl inclinado con mancuernas banco 60°', 'Incline_Dumbbell_Curl', 'el ángulo del banco no cambia la foto'),
  (false, 'curl inclinado con mancuernas en banco 45°', 'Incline_Dumbbell_Curl', 'el ángulo del banco no cambia la foto'),
  (false, 'curl inclinado con mancuernas en banco 60°', 'Incline_Dumbbell_Curl', 'el ángulo del banco no cambia la foto'),
  (false, 'curl inclinado con mancuernas — banco 45°', 'Incline_Dumbbell_Curl', 'el ángulo del banco no cambia la foto'),
  (false, 'curl inverso con barra en polea', 'Reverse_Cable_Curl', NULL),
  (false, 'curl inverso con barra ez', 'Reverse_Barbell_Curl', NULL),
  (false, 'curl inverso con barra ez en polea', 'Reverse_Cable_Curl', NULL),
  (false, 'curl inverso con barra o cable', 'Reverse_Barbell_Curl', NULL),
  (false, 'curl inverso con barra recta', 'Reverse_Barbell_Curl', NULL),
  (false, 'curl inverso con barra z', 'Reverse_Barbell_Curl', NULL),
  (false, 'curl inverso en barra de ez', 'Reverse_Barbell_Curl', NULL),
  (false, 'curl inverso en polea', 'Reverse_Cable_Curl', NULL),
  (false, 'curl inverso en polea baja', 'Reverse_Cable_Curl', NULL),
  (false, 'curl inverso en polea con barra recta', 'Reverse_Cable_Curl', NULL),
  (false, 'curl martillo', 'Hammer_Curls', NULL),
  (false, 'curl martillo con mancuerna', 'Hammer_Curls', NULL),
  (false, 'curl martillo con mancuernas', 'Hammer_Curls', NULL),
  (false, 'curl martillo en polea', 'Cable_Hammer_Curls_-_Rope_Attachment', 'con cuerda'),
  (false, 'curl martillo en polea baja con cuerda', 'Cable_Hammer_Curls_-_Rope_Attachment', 'con cuerda'),
  (false, 'curl martillo en polea con cuerda', 'Cable_Hammer_Curls_-_Rope_Attachment', 'con cuerda'),
  (false, 'curl martillo en predicador con mancuerna', 'Preacher_Hammer_Dumbbell_Curl', NULL),
  (false, 'curl nordico', 'Natural_Glute_Ham_Raise', 'nórdico'),
  (false, 'curl predicador', 'Preacher_Curl', 'con barra en banco Scott'),
  (false, 'curl predicador con mancuerna a una mano', 'One_Arm_Dumbbell_Preacher_Curl', NULL),
  (false, 'curl predicador en maquina', 'Machine_Preacher_Curls', NULL),
  (false, 'curl predicador en maquina o barra', 'Machine_Preacher_Curls', NULL),
  (false, 'curl predicador en maquina o barra ez', 'Machine_Preacher_Curls', NULL),
  (false, 'curl predicador en maquina, rango parcial sin bloqueo', 'Machine_Preacher_Curls', NULL),
  (false, 'curl spider con mancuerna', 'Dumbbell_Prone_Incline_Curl', 'boca abajo en banco inclinado con mancuernas (Spider_Curl es con barra Z en el Scott)'),
  (false, 'curl spider con mancuernas', 'Dumbbell_Prone_Incline_Curl', 'boca abajo en banco inclinado con mancuernas (Spider_Curl es con barra Z en el Scott)'),
  (false, 'curl spider con mancuernas o barra', 'Dumbbell_Prone_Incline_Curl', 'boca abajo en banco inclinado con mancuernas (Spider_Curl es con barra Z en el Scott)'),
  (false, 'dominadas', 'Pullups', NULL),
  (false, 'dominadas asistidas o lastradas segun sensacion', 'Pullups', NULL),
  (false, 'dominadas con lastre', 'Weighted_Pull_Ups', NULL),
  (false, 'dominadas, con straps', 'Pullups', NULL),
  (false, 'elev. de talon en multipower', 'Smith_Machine_Calf_Raise', NULL),
  (false, 'elevacion de gemelos de pie', 'Standing_Calf_Raises', NULL),
  (false, 'elevacion de gemelos en prensa', 'Calf_Press_On_The_Leg_Press_Machine', 'en la prensa'),
  (false, 'elevacion de gemelos sentado', 'Seated_Calf_Raise', 'máquina de sóleo sentado'),
  (false, 'elevacion de piernas colgado', 'Hanging_Leg_Raise', NULL),
  (false, 'elevacion de talon a una pierna con mancuerna', 'Standing_Dumbbell_Calf_Raise', 'a una pierna: la foto es con las dos · 3-nov: Mati aprobó sumarlo (bajo riesgo)'),
  (false, 'elevacion de talon de pie en maquina', 'Standing_Calf_Raises', NULL),
  (false, 'elevacion de talon de pie en multipower', 'Smith_Machine_Calf_Raise', NULL),
  (false, 'elevacion de talon en maquina de soleo sentado', 'Seated_Calf_Raise', 'máquina de sóleo sentado'),
  (false, 'elevacion de talon en multipower', 'Smith_Machine_Calf_Raise', NULL),
  (false, 'elevacion de talon en multipower de pie', 'Smith_Machine_Calf_Raise', NULL),
  (false, 'elevacion de talon en multipower o maquina de pie', 'Smith_Machine_Calf_Raise', NULL),
  (false, 'elevacion de talon en prensa', 'Calf_Press_On_The_Leg_Press_Machine', 'en la prensa'),
  (false, 'elevacion de talon en prensa de piernas', 'Calf_Press_On_The_Leg_Press_Machine', 'en la prensa'),
  (false, 'elevacion de talon sentado con disco', 'Seated_Calf_Raise', 'con disco en las rodillas: la foto es la máquina · 3-nov: Mati aprobó sumarlo (bajo riesgo)'),
  (false, 'elevacion de talon sentado en maquina', 'Seated_Calf_Raise', 'máquina de sóleo sentado'),
  (false, 'elevacion de talon sentado en maquina de soleo', 'Seated_Calf_Raise', 'máquina de sóleo sentado'),
  (false, 'elevacion de talon sentado en maquina soleo', 'Seated_Calf_Raise', 'máquina de sóleo sentado'),
  (false, 'elevacion de talones en maquina de soleo', 'Seated_Calf_Raise', 'máquina de sóleo sentado'),
  (false, 'elevaciones frontales alternas con mancuerna', 'Front_Dumbbell_Raise', 'alternas, de pie'),
  (false, 'elevaciones laterales', 'Side_Lateral_Raise', 'de pie con mancuernas'),
  (false, 'elevaciones laterales con cable a una mano', 'Standing_Low-Pulley_Deltoid_Raise', 'de pie, a una mano, polea baja (NO Cable_Seated_Lateral_Raise: esa es sentado e inclinado, es de deltoides posterior)'),
  (false, 'elevaciones laterales con mancuernas', 'Side_Lateral_Raise', 'de pie con mancuernas'),
  (false, 'elevaciones laterales con mancuernas sentado', 'Seated_Side_Lateral_Raise', NULL),
  (false, 'elevaciones laterales en polea a una mano', 'Standing_Low-Pulley_Deltoid_Raise', 'de pie, a una mano, polea baja (NO Cable_Seated_Lateral_Raise: esa es sentado e inclinado, es de deltoides posterior)'),
  (false, 'encogimientos con mancuernas', 'Dumbbell_Shrug', NULL),
  (false, 'encogimientos con mancuernas pesadas', 'Dumbbell_Shrug', NULL),
  (false, 'encogimientos en polea baja con barra', 'Cable_Shrugs', NULL),
  (false, 'espinales en banco ghd', 'Hyperextensions_Back_Extensions', NULL),
  (false, 'extension con barra en polea alta', 'Triceps_Pushdown', 'empuje hacia abajo con barra en polea alta'),
  (false, 'extension con barra en polea alta agarre prono', 'Triceps_Pushdown', 'empuje hacia abajo con barra en polea alta'),
  (false, 'extension con barra en polea alta, agarre prono', 'Triceps_Pushdown', 'empuje hacia abajo con barra en polea alta'),
  (false, 'extension con barra recta en polea alta', 'Triceps_Pushdown', 'empuje hacia abajo con barra en polea alta'),
  (false, 'extension de cuadriceps', 'Leg_Extensions', NULL),
  (false, 'extension de cuadriceps a una pierna', 'Single-Leg_Leg_Extension', NULL),
  (false, 'extension de cuadriceps en maquina', 'Leg_Extensions', NULL),
  (false, 'extension de cuadriceps en maquina — finisher', 'Leg_Extensions', NULL),
  (false, 'extension de cuadriceps en maquina — prefatiga', 'Leg_Extensions', NULL),
  (false, 'extension de cuadriceps liviana', 'Leg_Extensions', NULL),
  (false, 'extension de cuadriceps unilateral', 'Single-Leg_Leg_Extension', NULL),
  (false, 'extension de cuadriceps unilateral en maquina', 'Single-Leg_Leg_Extension', NULL),
  (false, 'extension de triceps con barra en polea alta', 'Triceps_Pushdown', 'empuje hacia abajo con barra en polea alta'),
  (false, 'extension de triceps en maquina', 'Machine_Triceps_Extension', NULL),
  (false, 'extension de triceps en polea', 'Triceps_Pushdown', 'empuje hacia abajo en polea'),
  (false, 'extension de triceps en polea con cuerda', 'Triceps_Pushdown_-_Rope_Attachment', 'empuje hacia abajo con cuerda'),
  (false, 'extension de triceps overhead con mancuerna', 'Seated_Triceps_Press', 'una mancuerna a dos manos por encima de la cabeza'),
  (false, 'extension en polea alta agarre prono', 'Triceps_Pushdown', 'empuje hacia abajo con barra en polea alta'),
  (false, 'extension en polea alta con agarre prono barra recta', 'Triceps_Pushdown', 'empuje hacia abajo con barra en polea alta'),
  (false, 'extension en polea alta con barra', 'Triceps_Pushdown', 'empuje hacia abajo con barra en polea alta'),
  (false, 'extension en polea alta con barra recta', 'Triceps_Pushdown', 'empuje hacia abajo con barra en polea alta'),
  (false, 'extension en polea alta con barra, agarre prono', 'Triceps_Pushdown', 'empuje hacia abajo con barra en polea alta'),
  (false, 'extension en polea con barra recta', 'Triceps_Pushdown', 'empuje hacia abajo con barra en polea alta'),
  (false, 'extension en polea con cuerda', 'Triceps_Pushdown_-_Rope_Attachment', 'empuje hacia abajo con cuerda'),
  (false, 'extension en polea con cuerda hacia abajo', 'Triceps_Pushdown_-_Rope_Attachment', 'empuje hacia abajo con cuerda'),
  (false, 'extension overhead con cuerda', 'Cable_Rope_Overhead_Triceps_Extension', 'por encima de la cabeza con cuerda'),
  (false, 'extension overhead con cuerda en polea', 'Cable_Rope_Overhead_Triceps_Extension', 'por encima de la cabeza con cuerda'),
  (false, 'extension overhead con cuerda en polea — usar codera en codo izquierdo', 'Cable_Rope_Overhead_Triceps_Extension', 'por encima de la cabeza con cuerda'),
  (false, 'extension overhead con mancuerna', 'Seated_Triceps_Press', 'una mancuerna a dos manos por encima de la cabeza'),
  (false, 'extension overhead con mancuerna a dos manos', 'Seated_Triceps_Press', 'una mancuerna a dos manos por encima de la cabeza'),
  (false, 'face pull con cuerda en polea', 'Face_Pull', NULL),
  (false, 'face pull con cuerda en polea alta', 'Face_Pull', NULL),
  (false, 'face pull en polea', 'Face_Pull', NULL),
  (false, 'fondos en maquina asistida o paralelas', 'Dips_-_Triceps_Version', 'fondos en paralelas (la asistida es el mismo gesto)'),
  (false, 'fondos en maquina o press frances', 'Dip_Machine', 'son dos ejercicios distintos a elección · 3-nov: Mati aprobó sumarlo (bajo riesgo)'),
  (false, 'gemelos en prensa', 'Calf_Press_On_The_Leg_Press_Machine', 'en la prensa'),
  (false, 'gemelos sentado en maquina', 'Seated_Calf_Raise', 'máquina de sóleo sentado'),
  (false, 'hack squat', 'Hack_Squat', NULL),
  (false, 'hack squat con respaldo', 'Hack_Squat', NULL),
  (false, 'hack squat en maquina', 'Hack_Squat', NULL),
  (false, 'hack squat en maquina, rango parcial sin redondear lumbar', 'Hack_Squat', NULL),
  (false, 'hip thrust', 'Barbell_Hip_Thrust', NULL),
  (false, 'hip thrust con barra', 'Barbell_Hip_Thrust', NULL),
  (false, 'hip thrust con barra apoyada en banco', 'Barbell_Hip_Thrust', NULL),
  (false, 'hip thrust con barra en banco', 'Barbell_Hip_Thrust', NULL),
  (false, 'hip thrust con barra o en maquina', 'Barbell_Hip_Thrust', NULL),
  (false, 'hip thrust en maquina', 'Barbell_Hip_Thrust', 'en máquina: la foto es con barra · 3-nov: Mati aprobó sumarlo (bajo riesgo)'),
  (false, 'hip thrust en maquina con respaldo, sin carga axial', 'Barbell_Hip_Thrust', 'en máquina: la foto es con barra · 3-nov: Mati aprobó sumarlo (bajo riesgo)'),
  (false, 'hip thrust en maquina o con barra', 'Barbell_Hip_Thrust', 'en máquina: la foto es con barra · 3-nov: Mati aprobó sumarlo (bajo riesgo)'),
  (false, 'hip thrust en maquina o con barra apoyada', 'Barbell_Hip_Thrust', 'en máquina: la foto es con barra · 3-nov: Mati aprobó sumarlo (bajo riesgo)'),
  (false, 'hip thrust en maquina o multipower', 'Barbell_Hip_Thrust', 'en máquina: la foto es con barra · 3-nov: Mati aprobó sumarlo (bajo riesgo)'),
  (false, 'hiperextensiones', 'Hyperextensions_Back_Extensions', NULL),
  (false, 'jalon a una mano en polea', 'One_Arm_Lat_Pulldown', NULL),
  (false, 'jalon a una mano en polea alta', 'One_Arm_Lat_Pulldown', NULL),
  (false, 'jalon agarre neutro cerrado', 'V-Bar_Pulldown', 'agarre neutro (triángulo)'),
  (false, 'jalon al pecho', 'Wide-Grip_Lat_Pulldown', 'agarre prono abierto'),
  (false, 'jalon al pecho a una mano en dorsalera', 'One_Arm_Lat_Pulldown', NULL),
  (false, 'jalon al pecho agarre neutro', 'V-Bar_Pulldown', 'agarre neutro (triángulo)'),
  (false, 'jalon al pecho agarre neutro cerrado', 'V-Bar_Pulldown', 'agarre neutro (triángulo)'),
  (false, 'jalon al pecho agarre neutro en polea', 'V-Bar_Pulldown', 'agarre neutro (triángulo)'),
  (false, 'jalon al pecho agarre neutro, con straps', 'V-Bar_Pulldown', 'agarre neutro (triángulo)'),
  (false, 'jalon al pecho agarre prono', 'Wide-Grip_Lat_Pulldown', 'agarre prono abierto'),
  (false, 'jalon al pecho agarre prono ancho', 'Wide-Grip_Lat_Pulldown', 'agarre prono abierto'),
  (false, 'jalon al pecho con agarre neutro', 'V-Bar_Pulldown', 'agarre neutro (triángulo)'),
  (false, 'jalon al pecho con agarre prono', 'Wide-Grip_Lat_Pulldown', 'agarre prono abierto'),
  (false, 'jalon al pecho neutro', 'V-Bar_Pulldown', 'agarre neutro (triángulo)'),
  (false, 'jalon al pecho neutro en polea', 'V-Bar_Pulldown', 'agarre neutro (triángulo)'),
  (false, 'jalon al pecho prono', 'Wide-Grip_Lat_Pulldown', 'agarre prono abierto'),
  (false, 'jalon unilateral en polea alta', 'One_Arm_Lat_Pulldown', NULL),
  (false, 'kickback con mancuerna', 'Tricep_Dumbbell_Kickback', NULL),
  (false, 'pajaros con mancuernas', 'Seated_Bent-Over_Rear_Delt_Raise', 'sentado e inclinado con mancuernas'),
  (false, 'pajaros con mancuernas en banco inclinado', 'Reverse_Flyes', 'boca abajo en banco inclinado'),
  (false, 'pajaros en maquina', 'Reverse_Machine_Flyes', 'pec deck inverso'),
  (false, 'pajaros en maquina / reverse pec deck', 'Reverse_Machine_Flyes', 'pec deck inverso'),
  (false, 'pajaros en maquina reverse pec deck', 'Reverse_Machine_Flyes', 'pec deck inverso'),
  (false, 'pajaros en maquina — pec deck inverso', 'Reverse_Machine_Flyes', 'pec deck inverso'),
  (false, 'pajaros en pec deck inverso', 'Reverse_Machine_Flyes', 'pec deck inverso'),
  (false, 'pajaros en polea alta', 'Cable_Rear_Delt_Fly', 'poleas altas cruzadas, de pie'),
  (false, 'pajaros en polea cruzada', 'Cable_Rear_Delt_Fly', 'poleas altas cruzadas, de pie'),
  (false, 'pajaros en polea cruzada de pie', 'Cable_Rear_Delt_Fly', 'poleas altas cruzadas, de pie'),
  (false, 'pajaros en reverse pec deck', 'Reverse_Machine_Flyes', 'pec deck inverso'),
  (false, 'patada de gluteo en polea', 'One-Legged_Cable_Kickback', NULL),
  (false, 'patada de triceps con mancuerna', 'Tricep_Dumbbell_Kickback', NULL),
  (false, 'patada trasera de gluteo en polea', 'One-Legged_Cable_Kickback', NULL),
  (false, 'patada trasera en polea', 'One-Legged_Cable_Kickback', NULL),
  (false, 'pec deck inverso', 'Reverse_Machine_Flyes', 'pec deck inverso'),
  (false, 'peso muerto parcial por debajo de la rodilla', 'Rack_Pulls', 'desde pines bajo la rodilla'),
  (false, 'peso muerto rumano', 'Romanian_Deadlift', NULL),
  (false, 'peso muerto rumano con barra', 'Romanian_Deadlift', NULL),
  (false, 'peso muerto rumano con barra / rdl', 'Romanian_Deadlift', NULL),
  (false, 'peso muerto rumano con mancuernas', 'Stiff-Legged_Dumbbell_Deadlift', 'bisagra con mancuernas'),
  (false, 'plancha abdominal', 'Plank', NULL),
  (false, 'prensa', 'Leg_Press', 'la altura de los pies no cambia la foto'),
  (false, 'prensa 45°', 'Leg_Press', 'la altura de los pies no cambia la foto'),
  (false, 'prensa 45° pies bajos', 'Leg_Press', 'la altura de los pies no cambia la foto'),
  (false, 'prensa a pie alto a una pierna', 'Leg_Press', 'a una pierna: la foto es con las dos · 3-nov: Mati aprobó sumarlo (bajo riesgo)'),
  (false, 'prensa de piernas', 'Leg_Press', 'la altura de los pies no cambia la foto'),
  (false, 'prensa de piernas 45°', 'Leg_Press', 'la altura de los pies no cambia la foto'),
  (false, 'prensa de piernas 45° con espalda bien apoyada, sin despegar la lumbar', 'Leg_Press', 'la altura de los pies no cambia la foto'),
  (false, 'prensa de piernas a 45°', 'Leg_Press', 'la altura de los pies no cambia la foto'),
  (false, 'prensa de piernas a una pierna', 'Leg_Press', 'a una pierna: la foto es con las dos · 3-nov: Mati aprobó sumarlo (bajo riesgo)'),
  (false, 'prensa de piernas con pies altos y juntos', 'Narrow_Stance_Leg_Press', 'pies juntos'),
  (false, 'prensa de piernas con pies bajos y juntos', 'Narrow_Stance_Leg_Press', 'pies juntos'),
  (false, 'prensa de piernas pie alto', 'Leg_Press', 'la altura de los pies no cambia la foto'),
  (false, 'prensa de piernas pies bajos y juntos', 'Narrow_Stance_Leg_Press', 'pies juntos'),
  (false, 'prensa de piernas pies medios', 'Leg_Press', 'la altura de los pies no cambia la foto'),
  (false, 'prensa de piernas, pies a media altura', 'Leg_Press', 'la altura de los pies no cambia la foto'),
  (false, 'prensa inclinada 45°', 'Leg_Press', 'la altura de los pies no cambia la foto'),
  (false, 'press banca', 'Barbell_Bench_Press_-_Medium_Grip', NULL),
  (false, 'press cerrado en maquina smith', 'Smith_Machine_Close-Grip_Bench_Press', 'primera opción: Smith'),
  (false, 'press cerrado en maquina smith o multipower', 'Smith_Machine_Close-Grip_Bench_Press', 'primera opción: Smith'),
  (false, 'press cerrado en maquina smith o press cerrado con barra', 'Smith_Machine_Close-Grip_Bench_Press', 'primera opción: Smith'),
  (false, 'press con mancuernas de pie o sentado', 'Dumbbell_Shoulder_Press', NULL),
  (false, 'press con mancuernas sentado', 'Seated_Dumbbell_Press', NULL),
  (false, 'press de banca libre con barra', 'Barbell_Bench_Press_-_Medium_Grip', NULL),
  (false, 'press de hombro con mancuernas', 'Dumbbell_Shoulder_Press', NULL),
  (false, 'press de hombro con mancuernas sentado', 'Seated_Dumbbell_Press', NULL),
  (false, 'press de hombro en maquina sentado', 'Machine_Shoulder_Military_Press', NULL),
  (false, 'press de hombros en maquina', 'Machine_Shoulder_Military_Press', NULL),
  (false, 'press de pecho en maquina convergente', 'Leverage_Chest_Press', NULL),
  (false, 'press de pecho en maquina convergente, agarre abierto', 'Leverage_Chest_Press', NULL),
  (false, 'press frances con barra ez', 'EZ-Bar_Skullcrusher', 'rompecráneos con barra Z'),
  (false, 'press inclinado con mancuernas', 'Incline_Dumbbell_Press', 'el ángulo (30°/45°) no cambia la foto'),
  (false, 'press inclinado con mancuernas 30°', 'Incline_Dumbbell_Press', 'el ángulo (30°/45°) no cambia la foto'),
  (false, 'press inclinado con mancuernas 30°, rango controlado', 'Incline_Dumbbell_Press', 'el ángulo (30°/45°) no cambia la foto'),
  (false, 'press inclinado con mancuernas, muneca neutra', 'Incline_Dumbbell_Press', 'el ángulo (30°/45°) no cambia la foto'),
  (false, 'press inclinado en maquina', 'Leverage_Incline_Chest_Press', NULL),
  (false, 'press inclinado en maquina smith', 'Smith_Machine_Incline_Bench_Press', NULL),
  (false, 'press inclinado en maquina smith o maquina guiada', 'Smith_Machine_Incline_Bench_Press', NULL),
  (false, 'press inclinado en maquina — rango controlado, sin sobreabrir hombro', 'Leverage_Incline_Chest_Press', NULL),
  (false, 'press inclinado en multipower', 'Smith_Machine_Incline_Bench_Press', NULL),
  (false, 'press inclinado en multipower con pausa', 'Smith_Machine_Incline_Bench_Press', NULL),
  (false, 'press inclinado en smith', 'Smith_Machine_Incline_Bench_Press', NULL),
  (false, 'press militar con mancuernas', 'Dumbbell_Shoulder_Press', NULL),
  (false, 'press militar en maquina', 'Machine_Shoulder_Military_Press', NULL),
  (false, 'press militar en maquina sentado con respaldo', 'Machine_Shoulder_Military_Press', NULL),
  (false, 'press militar en maquina smith', 'Smith_Machine_Overhead_Shoulder_Press', NULL),
  (false, 'press militar en smith', 'Smith_Machine_Overhead_Shoulder_Press', NULL),
  (false, 'press militar sentado en maquina', 'Machine_Shoulder_Military_Press', NULL),
  (false, 'press plano con mancuernas', 'Dumbbell_Bench_Press', NULL),
  (false, 'press plano con mancuernas rango controlado', 'Dumbbell_Bench_Press', NULL),
  (false, 'press plano con mancuernas, rango controlado sin sobreestirar', 'Dumbbell_Bench_Press', NULL),
  (false, 'press plano con mancuernas, recorrido controlado sin hiperextender el hombro', 'Dumbbell_Bench_Press', NULL),
  (false, 'press plano con mancuernas, recorrido parcial seguro', 'Dumbbell_Bench_Press', NULL),
  (false, 'press plano en maquina', 'Leverage_Chest_Press', NULL),
  (false, 'press plano en maquina convergente', 'Leverage_Chest_Press', NULL),
  (false, 'pull through', 'Pull_Through', 'en polea baja con cuerda'),
  (false, 'pullover en polea', 'Straight-Arm_Pulldown', 'brazos rectos en polea alta con barra'),
  (false, 'pullover en polea alta', 'Straight-Arm_Pulldown', 'brazos rectos en polea alta con barra'),
  (false, 'pullover en polea alta con cuerda', 'Rope_Straight-Arm_Pulldown', 'con cuerda'),
  (false, 'pullover en polea alta con cuerda, brazos rectos', 'Rope_Straight-Arm_Pulldown', 'con cuerda'),
  (false, 'pullover en polea — finisher', 'Straight-Arm_Pulldown', 'brazos rectos en polea alta con barra'),
  (false, 'pushdown con barra v en polea', 'Triceps_Pushdown_-_V-Bar_Attachment', NULL),
  (false, 'rdl con barra', 'Romanian_Deadlift', NULL),
  (false, 'rdl con barra / peso muerto rumano', 'Romanian_Deadlift', NULL),
  (false, 'rdl con barra recorrido controlado', 'Romanian_Deadlift', NULL),
  (false, 'rdl con barra, recorrido controlado', 'Romanian_Deadlift', NULL),
  (false, 'rdl con mancuernas', 'Stiff-Legged_Dumbbell_Deadlift', 'bisagra con mancuernas'),
  (false, 'rdl con mancuernas rango controlado', 'Stiff-Legged_Dumbbell_Deadlift', 'bisagra con mancuernas'),
  (false, 'rdl con mancuernas — usar straps', 'Stiff-Legged_Dumbbell_Deadlift', 'bisagra con mancuernas'),
  (false, 'rdl con mancuernas, rango controlado', 'Stiff-Legged_Dumbbell_Deadlift', 'bisagra con mancuernas'),
  (false, 'rdl con mancuernas, rango corto sin llegar al piso', 'Stiff-Legged_Dumbbell_Deadlift', 'bisagra con mancuernas'),
  (false, 'remo con barra', 'Bent_Over_Barbell_Row', NULL),
  (false, 'remo con mancuerna', 'One-Arm_Dumbbell_Row', 'no dice si es a una mano o con dos mancuernas · 3-nov: Mati aprobó sumarlo (bajo riesgo)'),
  (false, 'remo con mancuerna a una mano', 'One-Arm_Dumbbell_Row', NULL),
  (false, 'remo con mancuerna a una mano apoyado en banco, con straps', 'One-Arm_Dumbbell_Row', NULL),
  (false, 'remo en maquina con apoyo pectoral', 'Leverage_Iso_Row', 'remo en máquina de palanca'),
  (false, 'remo en maquina con pecho apoyado, con straps', 'Leverage_Iso_Row', 'remo en máquina de palanca'),
  (false, 'remo en maquina de palanca', 'Leverage_Iso_Row', 'remo en máquina de palanca'),
  (false, 'remo en maquina de palanca con pecho apoyado', 'Leverage_Iso_Row', 'remo en máquina de palanca'),
  (false, 'remo en maquina palanca', 'Leverage_Iso_Row', 'remo en máquina de palanca'),
  (false, 'remo en maquina palanca agarre neutro', 'Leverage_Iso_Row', 'remo en máquina de palanca'),
  (false, 'remo en maquina palanca con apoyo pectoral', 'Leverage_Iso_Row', 'remo en máquina de palanca'),
  (false, 'remo en polea baja', 'Seated_Cable_Rows', 'triángulo, agarre neutro'),
  (false, 'remo en polea sentado', 'Seated_Cable_Rows', 'triángulo, agarre neutro'),
  (false, 'remo en polea sentado agarre cerrado', 'Seated_Cable_Rows', 'triángulo, agarre neutro'),
  (false, 'remo en polea sentado agarre cerrado neutro', 'Seated_Cable_Rows', 'triángulo, agarre neutro'),
  (false, 'remo en polea sentado agarre en v', 'Seated_Cable_Rows', 'triángulo, agarre neutro'),
  (false, 'remo en polea sentado agarre estrecho', 'Seated_Cable_Rows', 'triángulo, agarre neutro'),
  (false, 'remo en polea sentado agarre neutro', 'Seated_Cable_Rows', 'triángulo, agarre neutro'),
  (false, 'remo en polea sentado con agarre cerrado', 'Seated_Cable_Rows', 'triángulo, agarre neutro'),
  (false, 'remo en polea sentado con agarre en v', 'Seated_Cable_Rows', 'triángulo, agarre neutro'),
  (false, 'remo en polea sentado con agarre neutro', 'Seated_Cable_Rows', 'triángulo, agarre neutro'),
  (false, 'remo en polea sentado con pecho erguido', 'Seated_Cable_Rows', 'triángulo, agarre neutro'),
  (false, 'remo en punta con barra', 'T-Bar_Row_with_Handle', 'barra en punta (landmine)'),
  (false, 'remo pendlay con barra', 'Bent_Over_Barbell_Row', 'Pendlay: cada repetición vuelve al piso, la foto no lo muestra · 3-nov: Mati aprobó sumarlo (bajo riesgo)'),
  (false, 'remo sentado con cable a una mano', 'Seated_One-arm_Cable_Pulley_Rows', NULL),
  (false, 'remo t con pecho apoyado', 'Lying_T-Bar_Row', NULL),
  (false, 'reverse pec deck', 'Reverse_Machine_Flyes', 'pec deck inverso'),
  (false, 'rollout', 'Ab_Roller', 'rueda abdominal de rodillas'),
  (false, 'rollout ab wheel', 'Ab_Roller', 'rueda abdominal de rodillas'),
  (false, 'rollout con ab wheel', 'Ab_Roller', 'rueda abdominal de rodillas'),
  (false, 'rollout con rueda abdominal', 'Ab_Roller', 'rueda abdominal de rodillas'),
  (false, 'rollout con rueda de abdominales', 'Ab_Roller', 'rueda abdominal de rodillas'),
  (false, 'rollout en ab wheel', 'Ab_Roller', 'rueda abdominal de rodillas'),
  (false, 'rollout en ab wheel — core', 'Ab_Roller', 'rueda abdominal de rodillas'),
  (false, 'rollout en rueda abdominal — 3×8-10 reps', 'Ab_Roller', 'rueda abdominal de rodillas'),
  (false, 'sentadilla bulgara', 'Split_Squat_with_Dumbbells', 'búlgara con mancuernas, pie de atrás elevado'),
  (false, 'sentadilla bulgara con mancuernas', 'Split_Squat_with_Dumbbells', 'búlgara con mancuernas, pie de atrás elevado'),
  (false, 'sentadilla bulgara con mancuernas a los costados', 'Split_Squat_with_Dumbbells', 'búlgara con mancuernas, pie de atrás elevado'),
  (false, 'sentadilla bulgara con mancuernas torso vertical', 'Split_Squat_with_Dumbbells', 'búlgara con mancuernas, pie de atrás elevado'),
  (false, 'sentadilla bulgara con mancuernas, torso vertical', 'Split_Squat_with_Dumbbells', 'búlgara con mancuernas, pie de atrás elevado'),
  (false, 'sentadilla bulgara con torso inclinado y mancuernas', 'Split_Squat_with_Dumbbells', 'búlgara con mancuernas, pie de atrás elevado'),
  (false, 'sentadilla bulgara en multipower', 'Smith_Single-Leg_Split_Squat', 'búlgara en Smith'),
  (false, 'sentadilla bulgara en smith', 'Smith_Single-Leg_Split_Squat', 'búlgara en Smith'),
  (false, 'sentadilla en smith', 'Smith_Machine_Squat', NULL),
  (false, 'sentadilla goblet con mancuerna hasta 90°', 'Goblet_Squat', 'la foto es con pesa rusa y el plan dice mancuerna · 3-nov: Mati aprobó sumarlo (bajo riesgo)'),
  (false, 'sentadilla hack', 'Hack_Squat', NULL),
  (false, 'sentadilla hack en maquina', 'Hack_Squat', NULL),
  (false, 'sentadilla libre', 'Barbell_Squat', 'con barra en la espalda'),
  (false, 'sentadilla libre con barra', 'Barbell_Squat', 'con barra en la espalda'),
  (false, 'sissy squat', 'Weighted_Sissy_Squat', NULL),
  (false, 'skull crusher', 'EZ-Bar_Skullcrusher', 'rompecráneos con barra Z'),
  (false, 'soleo', 'Seated_Calf_Raise', 'máquina de sóleo sentado'),
  (false, 'soleo en maquina', 'Seated_Calf_Raise', 'máquina de sóleo sentado'),
  (false, 'soleo en maquina sentado', 'Seated_Calf_Raise', 'máquina de sóleo sentado'),
  (false, 'soleo en maquina sentado carga alta', 'Seated_Calf_Raise', 'máquina de sóleo sentado'),
  (false, 'soleo en maquina sentado con pausa abajo', 'Seated_Calf_Raise', 'máquina de sóleo sentado'),
  (false, 'soleo sentado en maquina', 'Seated_Calf_Raise', 'máquina de sóleo sentado'),
  (false, 'zancada alternada con mancuernas', 'Dumbbell_Lunges', 'zancada con mancuernas'),
  (false, 'zancadas caminando con mancuernas', 'Dumbbell_Lunges', 'zancada con mancuernas'),
  (true, 'aperturas con mancuernas en banco inclinado (deltoides posterior / romboides)', 'Reverse_Flyes', 'revisión Opus 3-nov: bloque DELTOIDES POSTERIOR de Juan Pagán; la de pecho estaba mal'),
  (true, 'patada trasera (con polea)', 'One-Legged_Cable_Kickback', 'el paréntesis dice la polea'),
  (true, 'press con mancuernas (deltoides anterior)', 'Seated_Dumbbell_Press', 'de hombro (deltoides anterior)')
ON CONFLICT (completo, clave) DO UPDATE SET slug_en = EXCLUDED.slug_en, nota = EXCLUDED.nota, cargado_en = NOW();
