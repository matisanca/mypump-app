-- ============================================================
-- nativa_semana_revision_alan — El lunes cuenta como la revisión del domingo anterior, SOLO para quien está marcado
-- (propuesta: no aplicada; requiere ensayo en ROLLBACK, revisión y OK de Mati)
-- ============================================================
-- Diagnóstico: ~/Developer/nativa-evidencia/v232/CHECK_DOMINGO_DIAG.md. Alan revisa el domingo pero a veces carga el
-- lunes: hoy eso cae en la semana nueva y el domingo siguiente la app la da por completa.
-- Regla (Mati, 17/11): para los marcados, semana de revisión = lunes ISO de (fecha - 1 día): el lunes todavía es la
-- semana que terminó el domingo; martes a domingo, la semana en curso. Para el resto, el lunes ISO de la fecha, igual
-- que hoy (date_trunc('week', fecha)): para ellos no cambia ningún resultado.
-- Sin cambiar tablas ni claves: solo cómo se calcula semana_lunes al guardar y al leer.
-- Cambian (CREATE OR REPLACE, MISMA firma): mypump_guardar_checkin, mypump_get_checkin_semana,
-- mypump_check_guiado_get, mypump_check_guiado_guardar, mypump_revision_semana. El cuerpo es el vivo al 17/11 con un
-- solo cambio: el cálculo de la semana.
-- No cambian (revisadas): mypump_chat_semana / chat_actividad_semana (mensajes del chat, no la revisión),
-- mypump_chat_faltantes_semana (domingo, martes y jueves dan lo mismo con las dos reglas), mypump_get_metricas_coach
-- (último check por semana_lunes), pump_paquete_semanal (recibe la semana), mypump_lunes_siguiente.
-- ============================================================

BEGIN;
SET LOCAL lock_timeout = '5s';

ALTER TABLE mypump_cliente_prefs
  ADD COLUMN IF NOT EXISTS revision_lunes_cuenta BOOLEAN NOT NULL DEFAULT FALSE;

COMMENT ON COLUMN mypump_cliente_prefs.revision_lunes_cuenta IS
  'TRUE: lo que carga el lunes cuenta para la semana que terminó el domingo anterior (mypump_semana_revision). Default FALSE.';

-- La semana de revisión de un alumno para una fecha (la del teléfono). Sin fila o sin marca: lunes ISO de la fecha.
-- ::timestamp (sin zona) para que no dependa del TimeZone de la sesión; con UTC da lo mismo que date_trunc('week', date).
CREATE OR REPLACE FUNCTION mypump_semana_revision(p_cliente_id TEXT, p_fecha DATE)
RETURNS DATE
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT date_trunc('week', (p_fecha - CASE WHEN COALESCE(
           (SELECT revision_lunes_cuenta FROM mypump_cliente_prefs WHERE cliente_id = p_cliente_id), FALSE)
         THEN 1 ELSE 0 END)::timestamp)::date;
$$;
REVOKE ALL ON FUNCTION mypump_semana_revision(TEXT, DATE) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION mypump_semana_revision(TEXT, DATE) TO service_role;

-- ── mypump_guardar_checkin: solo cambia v_lunes ──
CREATE OR REPLACE FUNCTION public.mypump_guardar_checkin(p_token text, p_fecha date, p_energia smallint, p_descanso smallint, p_hambre smallint, p_adherencia smallint, p_nota text DEFAULT NULL::text)
 RETURNS SETOF mypump_checkin_semanal
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_cliente_id TEXT;
  v_hoy        DATE;
  v_lunes      DATE;
  v_id         UUID;
BEGIN
  v_cliente_id := mypump_get_cliente_id_from_token(p_token);
  IF v_cliente_id IS NULL THEN RETURN; END IF;

  -- Ventana tolerante a zona horaria/reloj del device (regla 020/028).
  v_hoy := (NOW() AT TIME ZONE 'America/Argentina/Buenos_Aires')::DATE;
  IF p_fecha > v_hoy + 1 THEN
    RAISE EXCEPTION 'No se puede registrar una fecha futura';
  END IF;
  IF p_fecha < v_hoy - 7 THEN
    RAISE EXCEPTION 'Solo se permite backfill de hasta 7 dias';
  END IF;

  v_lunes := mypump_semana_revision(v_cliente_id, p_fecha);  -- lunes ISO; con la marca, el lunes es la semana anterior

  INSERT INTO mypump_checkin_semanal
    (cliente_id, semana_lunes, energia, descanso, hambre, adherencia, nota)
  VALUES
    (v_cliente_id, v_lunes, p_energia, p_descanso, p_hambre, p_adherencia,
     NULLIF(trim(COALESCE(p_nota, '')), ''))
  ON CONFLICT (cliente_id, semana_lunes) DO UPDATE
    SET energia    = EXCLUDED.energia,
        descanso   = EXCLUDED.descanso,
        hambre     = EXCLUDED.hambre,
        adherencia = EXCLUDED.adherencia,
        nota       = EXCLUDED.nota,
        updated_at = NOW()
  RETURNING id INTO v_id;

  RETURN QUERY SELECT * FROM mypump_checkin_semanal WHERE id = v_id;
END;
$function$;

-- ── mypump_get_checkin_semana ──
CREATE OR REPLACE FUNCTION public.mypump_get_checkin_semana(p_token text, p_fecha date)
 RETURNS SETOF mypump_checkin_semanal
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_cliente_id TEXT;
BEGIN
  v_cliente_id := mypump_get_cliente_id_from_token(p_token);
  IF v_cliente_id IS NULL THEN RETURN; END IF;
  RETURN QUERY
    SELECT * FROM mypump_checkin_semanal
    WHERE cliente_id = v_cliente_id
      AND semana_lunes = mypump_semana_revision(v_cliente_id, p_fecha);
END;
$function$;

-- ── mypump_check_guiado_get ──
CREATE OR REPLACE FUNCTION public.mypump_check_guiado_get(p_token text, p_fecha date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_cliente_id TEXT;
  v_lunes      DATE;
  v_fila       mypump_check_guiado;
BEGIN
  v_cliente_id := mypump_get_cliente_id_from_token(p_token);
  IF v_cliente_id IS NULL THEN RETURN NULL; END IF;
  IF NOT COALESCE((SELECT valor = 'true'::JSONB FROM mypump_app_config WHERE clave = 'check_guiado'), FALSE) THEN
    RETURN jsonb_build_object('activo', FALSE);
  END IF;
  v_lunes := mypump_semana_revision(v_cliente_id,
               COALESCE(p_fecha, (NOW() AT TIME ZONE 'America/Argentina/Buenos_Aires')::DATE));
  SELECT * INTO v_fila FROM mypump_check_guiado WHERE cliente_id = v_cliente_id AND semana_lunes = v_lunes;
  RETURN jsonb_build_object(
    'activo',   TRUE,
    'en_ciclo', mypump_check_guiado_en_ciclo(v_cliente_id),
    'glp1',     mypump_check_guiado_glp1(v_cliente_id),
    'semana',   v_lunes,
    'catalogo', v_fila.catalogo,
    'senales',  CASE WHEN v_fila.cliente_id IS NULL THEN NULL ELSE to_jsonb(v_fila.senales) END,
    'intensidades', CASE WHEN v_fila.cliente_id IS NULL THEN NULL ELSE v_fila.intensidades END
  );
END;
$function$;

-- ── mypump_check_guiado_guardar: solo cambia la semana del INSERT ──
CREATE OR REPLACE FUNCTION public.mypump_check_guiado_guardar(p_token text, p_fecha date, p_respuestas jsonb)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_cliente_id TEXT;
  v_hoy        DATE;
  v_catalogo   TEXT;
  v_senales    TEXT[];
  v_intens     JSONB;
BEGIN
  v_cliente_id := mypump_get_cliente_id_from_token(p_token);
  IF v_cliente_id IS NULL THEN RETURN NULL; END IF;
  IF NOT COALESCE((SELECT valor = 'true'::JSONB FROM mypump_app_config WHERE clave = 'check_guiado'), FALSE) THEN
    RETURN FALSE;
  END IF;

  -- La misma ventana que mypump_guardar_checkin.
  v_hoy := (NOW() AT TIME ZONE 'America/Argentina/Buenos_Aires')::DATE;
  IF p_fecha IS NULL THEN RAISE EXCEPTION 'Falta la fecha' USING ERRCODE = '22023'; END IF;
  IF p_fecha > v_hoy + 1 THEN RAISE EXCEPTION 'No se puede registrar una fecha futura' USING ERRCODE = '22023'; END IF;
  IF p_fecha < v_hoy - 7 THEN RAISE EXCEPTION 'Solo se permite backfill de hasta 7 dias' USING ERRCODE = '22023'; END IF;

  IF p_respuestas IS NULL OR jsonb_typeof(p_respuestas) <> 'object' OR pg_column_size(p_respuestas) > 2000 THEN
    RAISE EXCEPTION 'respuestas inválidas' USING ERRCODE = '22023';
  END IF;
  v_catalogo := p_respuestas->>'catalogo';
  IF v_catalogo IS NULL OR v_catalogo NOT IN ('general', 'ciclo') THEN
    RAISE EXCEPTION 'catálogo inválido' USING ERRCODE = '22023';
  END IF;
  IF jsonb_typeof(p_respuestas->'senales') IS DISTINCT FROM 'array'
     OR EXISTS (SELECT 1 FROM jsonb_array_elements(p_respuestas->'senales') e
                WHERE jsonb_typeof(e) <> 'string' OR (e #>> '{}') !~ '^[a-z][a-z0-9_]{0,23}$') THEN
    RAISE EXCEPTION 'señales inválidas' USING ERRCODE = '22023';
  END IF;
  SELECT COALESCE(array_agg(DISTINCT s ORDER BY s), '{}') INTO v_senales
    FROM jsonb_array_elements_text(p_respuestas->'senales') s;
  -- Solo las claves de la lista del catálogo (las mismas que apps/shared/vectores/check_guiado.json).
  IF NOT v_senales <@ (CASE v_catalogo
       WHEN 'ciclo' THEN ARRAY['acne','retencion','pecho','cabeza','animo','libido','sueno','aplicacion',
                             'nauseas','vomitos','estrenimiento','diarrea','acidez','ninguno']
       ELSE ARRAY['dolor','digestion','animo','enfermo','ninguno'] END) THEN
    RAISE EXCEPTION 'señales inválidas' USING ERRCODE = '22023';
  END IF;
  IF cardinality(v_senales) > 1 THEN v_senales := array_remove(v_senales, 'ninguno'); END IF;
  IF cardinality(v_senales) NOT BETWEEN 1 AND 16 THEN
    RAISE EXCEPTION 'señales inválidas' USING ERRCODE = '22023';
  END IF;

  -- Intensidades: un objeto; cada clave es un efecto marcado (nunca 'ninguno') y cada valor leve | moderado | fuerte.
  v_intens := COALESCE(p_respuestas->'intensidades', '{}'::JSONB);
  IF jsonb_typeof(v_intens) <> 'object'
     OR (v_catalogo <> 'ciclo' AND v_intens <> '{}'::JSONB)
     OR EXISTS (SELECT 1 FROM jsonb_each(v_intens) i
                WHERE i.key = 'ninguno' OR NOT i.key = ANY(v_senales)
                   OR jsonb_typeof(i.value) <> 'string' OR (i.value #>> '{}') NOT IN ('leve', 'moderado', 'fuerte')) THEN
    RAISE EXCEPTION 'intensidades inválidas' USING ERRCODE = '22023';
  END IF;

  INSERT INTO mypump_check_guiado (cliente_id, semana_lunes, catalogo, senales, intensidades, en_ciclo)
  VALUES (v_cliente_id, mypump_semana_revision(v_cliente_id, p_fecha), v_catalogo, v_senales, v_intens, mypump_check_guiado_en_ciclo(v_cliente_id))
  ON CONFLICT (cliente_id, semana_lunes) DO UPDATE
    SET catalogo = EXCLUDED.catalogo, senales = EXCLUDED.senales, intensidades = EXCLUDED.intensidades,
        en_ciclo = EXCLUDED.en_ciclo, updated_at = NOW();
  RETURN TRUE;
END;
$function$;

-- ── mypump_revision_semana (la del coach): solo cambia el CTE lunes ──
CREATE OR REPLACE FUNCTION public.mypump_revision_semana(p_cliente_id text, p_ref timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  WITH lunes AS (
    SELECT mypump_semana_revision(p_cliente_id, (p_ref AT TIME ZONE 'America/Argentina/Buenos_Aires')::date) AS d
  ),
  chk AS (
    SELECT k.energia, k.descanso, k.hambre, k.adherencia, k.nota
      FROM mypump_checkin_semanal k, lunes l
     WHERE k.cliente_id = p_cliente_id AND k.semana_lunes = l.d
  ),
  fotos AS (
    SELECT count(*)::int AS n
      FROM mypump_fotos_progreso f, lunes l
     WHERE f.cliente_id = p_cliente_id AND f.semana_lunes = l.d
  ),
  peso AS (
    SELECT ROUND(AVG(sd.valor)::numeric, 1) AS kg
      FROM mypump_salud_diaria sd, lunes l
     WHERE sd.cliente_id = p_cliente_id AND sd.tipo = 'peso_kg'
       AND sd.fecha >= l.d AND sd.fecha < l.d + 7
  ),
  arranque AS (
    SELECT mypump_revision_desde_efectiva(p_cliente_id) AS d
  ),
  peso_prev AS (
    SELECT ROUND(AVG(sd.valor)::numeric, 1) AS kg
      FROM mypump_salud_diaria sd, lunes l
     WHERE sd.cliente_id = p_cliente_id AND sd.tipo = 'peso_kg'
       AND sd.fecha >= l.d - 7 AND sd.fecha < l.d
  )
  SELECT jsonb_strip_nulls(jsonb_build_object(
    'semana',      (SELECT d FROM lunes),
    'hay_check',   (SELECT count(*) FROM chk) > 0,
    'energia',     (SELECT energia    FROM chk),
    'descanso',    (SELECT descanso   FROM chk),
    'hambre',      (SELECT hambre     FROM chk),
    'adherencia',  (SELECT adherencia FROM chk),
    'nota',        (SELECT left(nota, 400) FROM chk),
    'fotos',       (SELECT n FROM fotos),
    'peso_kg',     (SELECT kg FROM peso),
    'peso_previo', (SELECT kg FROM peso_prev),
    -- revision_desde (14/11). Con jsonb_strip_nulls, a quien no tiene restricción le sale lo mismo que antes.
    'revision_desde',     (SELECT CASE WHEN d < DATE '9999-12-31' THEN d END FROM arranque),
    'antes_del_arranque', (SELECT CASE WHEN (p_ref AT TIME ZONE 'America/Argentina/Buenos_Aires')::date < d
                                       THEN TRUE END FROM arranque)
  ));
$function$;

-- ── Marcar a Alan (mn8awmgg28en). Sin fila previa: revision_dia queda en su default 7 (domingo), como hoy. ──
INSERT INTO mypump_cliente_prefs (cliente_id, revision_lunes_cuenta) VALUES ('mn8awmgg28en', TRUE)
ON CONFLICT (cliente_id) DO UPDATE SET revision_lunes_cuenta = TRUE, updated_at = NOW();

COMMIT;
NOTIFY pgrst, 'reload schema';
