-- PROPUESTA, sin aplicar. Para aplicar hace falta el OK de Mati (compuerta G2).
--
-- Check guiado (2.3.0): el check de la semana pasa a ser un paso a paso. Lo de siempre se sigue guardando igual y por las
-- mismas funciones, que esta propuesta NO toca:
--   · las cuatro escalas y la nota  → mypump_guardar_checkin  → mypump_checkin_semanal
--   · el peso                      → mypump_ingest_salud     → mypump_salud (peso_kg, manual)
--   · las fotos                    → /progreso/upload        → mypump_fotos_progreso
-- Por eso el brief, Progreso, el panel de Mati y la devolución semanal leen lo mismo que hoy.
--
-- Lo nuevo es una sola cosa: lo que el alumno marca en «¿Notaste algo de esto?». Va en una tabla aparte, una fila por
-- semana (lunes ISO, como el check). Hay dos listas:
--   · 'ciclo':   para quien `clientes_perfil` dice que usa algo: ciclo, TRT, péptidos (GLP-1 incluido) o posciclo;
--   · 'general': para todos los demás (naturales, sin definir o sin perfil). A un natural nunca le sale la de efectos.
-- La app pregunta cuál le toca con `mypump_check_guiado_get`; el servidor anota además qué decía el perfil al guardar.
--
-- Sale APAGADO: `check_guiado` en false. Apagado, las apps muestran la Revisión de siempre, `mypump_check_guiado_get`
-- contesta {"activo": false} y `mypump_check_guiado_guardar` no escribe nada. Sin esta propuesta aplicada las apps tampoco
-- cambian (la clave no existe = apagado).
--
-- Reverso: nativa_check_guiado_revertir.sql.

BEGIN;

CREATE TABLE IF NOT EXISTS mypump_check_guiado (
  cliente_id    TEXT        NOT NULL,
  semana_lunes  DATE        NOT NULL,
  catalogo      TEXT        NOT NULL CHECK (catalogo IN ('general', 'ciclo')),
  -- Claves de lo marcado ('acne', 'retencion'…). 'ninguno' = contestó que nada; vacío no se guarda.
  senales       TEXT[]      NOT NULL CHECK (cardinality(senales) BETWEEN 1 AND 16),
  -- Solo en la lista de efectos: cuánto molesta cada uno. {"nauseas": "moderado"}; claves de `senales`, valores
  -- leve | moderado | fuerte. Vacío en la lista general o con 'ninguno'. `senales` no cambia por esto.
  intensidades  JSONB       NOT NULL DEFAULT '{}'::JSONB CHECK (jsonb_typeof(intensidades) = 'object'),
  -- Lo que decía clientes_perfil en el momento de guardar (el perfil puede cambiar después).
  en_ciclo      BOOLEAN     NOT NULL DEFAULT FALSE,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (cliente_id, semana_lunes)
);

REVOKE ALL ON mypump_check_guiado FROM PUBLIC, anon;
ALTER TABLE mypump_check_guiado ENABLE ROW LEVEL SECURITY;

-- El panel de Mati (sesión iniciada), igual que mypump_checkin_semanal.
DROP POLICY IF EXISTS "admin all mypump_check_guiado" ON mypump_check_guiado;
CREATE POLICY "admin all mypump_check_guiado"
  ON mypump_check_guiado FOR ALL
  USING (auth.role() = 'authenticated')
  WITH CHECK (auth.role() = 'authenticated');

-- ── Palanca: apagada ──
INSERT INTO mypump_app_config (clave, valor, nota) VALUES
  ('check_guiado', 'false'::JSONB,
   'true: la Revisión de las apps muestra el check guiado (paso a paso). false: la Revisión de siempre')
ON CONFLICT (clave) DO NOTHING;

-- ── ¿Le toca la lista de efectos? Un solo lugar para el criterio ──
-- Decisión de Mati (11/11): a todo el que usa algo, es decir ciclo, TRT, péptidos (GLP-1 incluido) o posciclo. Sin fila,
-- sin_definir o natural: no. El nombre `en_ciclo` (función, columna y clave del JSON) se mantiene por compatibilidad con
-- las apps y con lo ya escrito; hoy quiere decir «usa algo».
-- Los GLP-1 no tienen perfil propio: son el subperfil `peptidos.glp1`, así que entran por 'peptidos'.
CREATE OR REPLACE FUNCTION mypump_check_guiado_en_ciclo(p_cliente_id TEXT)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE((SELECT perfiles && ARRAY['ciclo', 'trt', 'peptidos', 'posciclo']
                     FROM clientes_perfil WHERE cliente_id = p_cliente_id), FALSE);
$$;

-- ── ¿Usa un GLP-1? Solo a ellos la lista de efectos les suma los digestivos (náuseas, vómitos, estreñimiento…) ──
CREATE OR REPLACE FUNCTION mypump_check_guiado_glp1(p_cliente_id TEXT)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE((SELECT 'peptidos.glp1' = ANY(subperfiles) FROM clientes_perfil WHERE cliente_id = p_cliente_id), FALSE);
$$;

REVOKE ALL ON FUNCTION mypump_check_guiado_en_ciclo(TEXT), mypump_check_guiado_glp1(TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION mypump_check_guiado_en_ciclo(TEXT), mypump_check_guiado_glp1(TEXT) TO service_role;

-- ── Lo que la app lee al abrir Revisión ──
-- NULL = el token no sirve. {"activo": false} = palanca apagada (no dice nada del perfil).
CREATE OR REPLACE FUNCTION mypump_check_guiado_get(p_token TEXT, p_fecha DATE)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
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
  v_lunes := date_trunc('week', COALESCE(p_fecha, (NOW() AT TIME ZONE 'America/Argentina/Buenos_Aires')::DATE))::DATE;
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
$$;

-- ── Guardar lo marcado (una fila por semana; la última gana) ──
-- p_respuestas: {"catalogo": "general" | "ciclo", "senales": ["acne", "nauseas"], "intensidades": {"acne": "leve", "nauseas": "moderado"}}
-- `intensidades` es opcional (sin la clave = vacío) y solo vale en la lista de efectos: claves marcadas, valores leve | moderado | fuerte.
-- TRUE = guardado. FALSE = palanca apagada (no se guarda; la app lo da por hecho). NULL = el token no sirve.
-- Con 'ninguno' junto a otras, 'ninguno' se descarta. Lo inválido da 22023 (la cola de la app no lo reintenta).
CREATE OR REPLACE FUNCTION mypump_check_guiado_guardar(p_token TEXT, p_fecha DATE, p_respuestas JSONB)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
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
  VALUES (v_cliente_id, date_trunc('week', p_fecha)::DATE, v_catalogo, v_senales, v_intens, mypump_check_guiado_en_ciclo(v_cliente_id))
  ON CONFLICT (cliente_id, semana_lunes) DO UPDATE
    SET catalogo = EXCLUDED.catalogo, senales = EXCLUDED.senales, intensidades = EXCLUDED.intensidades,
        en_ciclo = EXCLUDED.en_ciclo, updated_at = NOW();
  RETURN TRUE;
END;
$$;

REVOKE ALL ON FUNCTION mypump_check_guiado_get(TEXT, DATE), mypump_check_guiado_guardar(TEXT, DATE, JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION mypump_check_guiado_get(TEXT, DATE), mypump_check_guiado_guardar(TEXT, DATE, JSONB)
  TO anon, authenticated, service_role;

NOTIFY pgrst, 'reload schema';

COMMIT;

-- Para prenderlo (con OK de Mati, desde ~/_aplicar.py):
--   UPDATE mypump_app_config SET valor = 'true', actualizado_en = NOW() WHERE clave = 'check_guiado';
-- Para leerlo en el brief o en el panel:
--   SELECT semana_lunes, catalogo, senales, intensidades, en_ciclo FROM mypump_check_guiado WHERE cliente_id = '…' ORDER BY 1 DESC;
