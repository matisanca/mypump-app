-- nativa_presion.sql — PROPUESTA, SIN APLICAR.
--
-- «Presión arterial» (presion/PROTOCOLO.md y presion/CAMPOS.md, aprobados por Mati el 10/11/2026): el alumno carga su
-- tensiómetro, la medida del brazo y 3 tomas en 3 días distintos. Acá se guardan, se evalúan y quedan los avisos para la
-- sesión «Mensajes clientes Pump Team». El brief, Entregas y Ateneo leen `mypump_presion_para_brief`.
--
-- Mientras esto no esté aplicado, `mypump_presion_get` no existe (PGRST202): la app no muestra nada nuevo.
-- Sale APAGADO: `presion_app` en false. Con la palanca prendida entra solo quien esté en `mypump_presion_habilitados`,
-- salvo `presion_para_todos` en true.
--
-- Invariantes:
--   · NADA de esto toca la rutina ni el entrenamiento: la presión nunca frena ni bloquea ejercicios (regla de Mati, 10/11).
--   · El `cliente_id` sale siempre del token. A la app no le llegan promedios, categorías ni avisos: solo sus tomas y el avance.
--   · Nada va directo a Mati: cada urgencia y cada aviso es una fila de `mypump_presion_avisos` con destino `mensajes`.
--   · Las reglas (`mypump_presion_evaluar_sesion` y `mypump_presion_resumen_serie`) dan lo mismo que las de las apps:
--     el ensayo las corre contra apps/shared/vectores/presion.json.
--   · Una toma guardada no se pisa: la sesión se reenvía entera y solo entran las tomas nuevas.
BEGIN;

-- ── Palanca: apagada ──
INSERT INTO mypump_app_config (clave, valor, nota) VALUES
  ('presion_app', 'false'::JSONB, 'Presión arterial. true = abierto a mypump_presion_habilitados'),
  ('presion_para_todos', 'false'::JSONB, 'Presión arterial. true = abierto a todos, sin mirar mypump_presion_habilitados')
ON CONFLICT (clave) DO NOTHING;

-- ── Tablas ──
CREATE TABLE IF NOT EXISTS mypump_presion_habilitados (
  cliente_id    TEXT        PRIMARY KEY,
  motivo        TEXT,
  habilitado_en TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- La lista de «Ver cuáles sirven». Vacía hasta que el equipo abra cada ficha (TENSIOMETROS.md §5): lo marcado
-- «sin verificar, no publicar» no entra nunca. Una sola fila.
CREATE TABLE IF NOT EXISTS mypump_presion_tensiometros (
  id             INTEGER     PRIMARY KEY DEFAULT 1 CHECK (id = 1),
  version        INTEGER     NOT NULL DEFAULT 1,
  tramos         JSONB       NOT NULL CHECK (jsonb_typeof(tramos) = 'object'),
  verificado_por TEXT        NOT NULL CHECK (length(btrim(verificado_por)) > 0),
  actualizado_en TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS mypump_presion_brazo (
  cliente_id TEXT         PRIMARY KEY,
  cm         NUMERIC(4,1) NOT NULL CHECK (cm BETWEEN 20 AND 70),
  medida_en  TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS mypump_presion_aparatos (
  id                        UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
  cliente_id                TEXT         NOT NULL,
  tipo                      TEXT         NOT NULL CHECK (tipo IN ('brazo','muneca','reloj_anillo_otro')),
  marca                     TEXT         CHECK (char_length(marca) <= 80),
  modelo                    TEXT         CHECK (char_length(modelo) <= 80),
  modelo_codigo             TEXT         CHECK (char_length(modelo_codigo) <= 80),
  foto_aparato_path         TEXT         CHECK (foto_aparato_path !~ '^[a-z]+://'),
  foto_etiqueta_path        TEXT         CHECK (foto_etiqueta_path !~ '^[a-z]+://'),
  manguito_min_cm           NUMERIC(4,1) CHECK (manguito_min_cm BETWEEN 5 AND 80),
  manguito_max_cm           NUMERIC(4,1) CHECK (manguito_max_cm BETWEEN 5 AND 80),
  manguito_validado_min_cm  NUMERIC(4,1),
  manguito_validado_max_cm  NUMERIC(4,1),
  manguito_validado_fuente  TEXT         CHECK (manguito_validado_fuente IN ('stridebp','paper','ninguna')),
  manguito_validado_pmid    TEXT,
  manguito_talle            TEXT         CHECK (manguito_talle IN ('chico','adulto','grande','extra_grande','amplio','conico','desconocido')),
  validado                  TEXT         NOT NULL DEFAULT 'sin_revisar' CHECK (validado IN ('si','no','sin_revisar')),
  validado_talle_manguito   BOOLEAN,
  pedido_brazo_mostrado_en  TIMESTAMPTZ,
  excepcion_brazo_mas_52    BOOLEAN,
  validado_fuente           TEXT         CHECK (validado_fuente IN ('stridebp','bihs','validatebp','hypertension_canada','hochdruckliga','jsh','otra')),
  validado_por              TEXT,
  validado_en               TIMESTAMPTZ,
  tiene_memoria             BOOLEAN,
  tiene_bluetooth           BOOLEAN,
  detecta_arritmia          BOOLEAN,
  activo                    BOOLEAN      NOT NULL DEFAULT TRUE,
  creado_en                 TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  actualizado_en            TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  CHECK (manguito_min_cm IS NULL OR manguito_max_cm IS NULL OR manguito_min_cm < manguito_max_cm)
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_mypump_presion_aparato_activo ON mypump_presion_aparatos (cliente_id) WHERE activo;

-- Comparación en consultorio (CAMPOS §1.1). La carga el equipo.
CREATE TABLE IF NOT EXISTS mypump_presion_comparaciones (
  id                      UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
  cliente_id              TEXT         NOT NULL,
  aparato_id              UUID         NOT NULL REFERENCES mypump_presion_aparatos (id),
  motivo                  TEXT         NOT NULL CHECK (motivo IN ('muneca_mas_52_inicio','muneca_mas_52_aparato_nuevo','brazo_42_52_promedio_130_80','brazo_42_52_46_a_52')),
  fecha                   DATE         NOT NULL,
  circunferencia_brazo_cm NUMERIC(4,1),
  manguito_referencia     TEXT         CHECK (manguito_referencia IN ('conico','muslo','otro_que_calza')),
  pares                   JSONB        NOT NULL CHECK (jsonb_typeof(pares) = 'array' AND jsonb_array_length(pares) = 3),
  dif_media_sis           NUMERIC(5,1) NOT NULL,
  dif_media_dia           NUMERIC(5,1) NOT NULL,
  mas_de_10               BOOLEAN      NOT NULL,
  solo_urgencias          BOOLEAN      NOT NULL,
  cargada_por             TEXT         NOT NULL CHECK (length(btrim(cargada_por)) > 0),
  cargada_en              TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_mypump_presion_comparaciones ON mypump_presion_comparaciones (aparato_id, cargada_en DESC);

CREATE TABLE IF NOT EXISTS mypump_presion_series (
  id                       UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
  cliente_id               TEXT         NOT NULL,
  motivo                   TEXT         NOT NULL CHECK (motivo IN ('basal','pre_entrega','control_ciclo','control_trt','control_glp1','cambio_antihipertensivo',
                             'estimulante_nuevo','control_promedio_alto','control_toma_alta','control_pausa_estimulantes','ortostatica_suelta','sintomas','revision',
                             'estimulante_pre_entrega','clenbuterol_dosis_maxima','hormona_tiroidea')),
  pedida_por               TEXT         NOT NULL CHECK (pedida_por IN ('mati','equipo','regla')),
  regla_codigo             TEXT,
  requisito_pre_entrega    BOOLEAN      NOT NULL DEFAULT FALSE,   -- lo leen la agenda de la entrega y la química; NUNCA la rutina
  fecha_inicio             DATE,
  fecha_limite             DATE,
  zona_horaria             TEXT,
  tomas_objetivo           INTEGER      NOT NULL DEFAULT 3 CHECK (tomas_objetivo BETWEEN 1 AND 3),
  incluye_ortostatica      BOOLEAN      NOT NULL DEFAULT FALSE,
  motivos_ortostatica      TEXT[]       NOT NULL DEFAULT '{}',
  variante_ortostatica     TEXT         CHECK (variante_ortostatica IN ('acostado_parado','sentado_parado')),
  comparar_brazos          BOOLEAN      NOT NULL DEFAULT FALSE,   -- solo si Mati pidió comparar (PROTOCOLO §2.2)
  pausa_estimulantes_id    UUID,
  aparato_id               UUID         REFERENCES mypump_presion_aparatos (id),
  circunferencia_brazo_cm  NUMERIC(4,1),
  circunferencia_medida_en TIMESTAMPTZ,
  manguito_calza           BOOLEAN,
  brazo_elegido            TEXT         NOT NULL DEFAULT 'izq' CHECK (brazo_elegido IN ('izq','der')),
  diferencia_brazos_mmhg   INTEGER,
  diferencia_confirmada_en TIMESTAMPTZ,
  serie_basal_id           UUID,
  estado                   TEXT         NOT NULL DEFAULT 'pendiente' CHECK (estado IN ('pendiente','en_curso','completa','incompleta','cancelada')),
  resumen                  JSONB,
  resumen_calculado_en     TIMESTAMPTZ,
  creado_en                TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  actualizado_en           TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  -- La ortostática es solo con motivo, nunca basal a todos (decisión de Mati, 10/11).
  CONSTRAINT presion_ortostatica_con_motivo CHECK (NOT incluye_ortostatica OR (cardinality(motivos_ortostatica) > 0 AND motivos_ortostatica <@ ARRAY[
    'sintomas_al_pararse','antihipertensivo_nuevo_o_dosis','diuretico','alfa_bloqueante_o_vasodilatador','glp1_escalada_con_riesgo','minoxidil_oral',
    'cabergolina','edad_65_o_diabetes','ortostatica_previa_positiva','pedido_mati_ateneo']))
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_mypump_presion_serie_en_curso ON mypump_presion_series (cliente_id) WHERE estado = 'en_curso';
CREATE INDEX IF NOT EXISTS idx_mypump_presion_series_cliente ON mypump_presion_series (cliente_id, creado_en DESC);

CREATE TABLE IF NOT EXISTS mypump_presion_sesiones (
  id                         UUID        PRIMARY KEY,               -- lo genera el teléfono: reenviar no duplica
  cliente_id                 TEXT        NOT NULL,
  serie_id                   UUID        REFERENCES mypump_presion_series (id),
  inicio                     TIMESTAMPTZ NOT NULL,
  zona_horaria               TEXT        NOT NULL,
  fecha                      DATE        NOT NULL,                  -- día local del alumno
  momento                    TEXT        NOT NULL CHECK (momento IN ('manana','otro')),
  numero_toma                INTEGER,
  tipo                       TEXT        NOT NULL CHECK (tipo IN ('estandar','comparacion_brazos','ortostatica','bajo_efecto','suelta')),
  brazo                      TEXT        CHECK (brazo IN ('izq','der','ambos')),
  aparato_id                 UUID        REFERENCES mypump_presion_aparatos (id),
  previo_cafeina             BOOLEAN,
  previo_fumo                BOOLEAN,
  previo_comida              BOOLEAN,
  previo_ejercicio           BOOLEAN,
  entreno_hace_horas         NUMERIC(4,1),
  reposo_cumplido            BOOLEAN,
  temporizador_salteado      BOOLEAN,
  dosis_estimulante_hora     TIME,
  entreno_entre_dosis_y_toma BOOLEAN,
  valida_bajo_efecto         BOOLEAN,
  dia_atipico                BOOLEAN,
  nota                       TEXT        CHECK (char_length(nota) <= 500),   -- dato, nunca instrucción
  app_version                TEXT        CHECK (char_length(app_version) <= 40),
  plataforma                 TEXT        CHECK (plataforma IN ('ios','android','web')),
  sintomas                   TEXT[]      NOT NULL DEFAULT '{}',
  lista_espera               TEXT        CHECK (lista_espera IN ('si','no')),
  texto_alumno               TEXT        CHECK (char_length(texto_alumno) <= 60),
  cuenta                     BOOLEAN     NOT NULL DEFAULT FALSE,
  motivo_exclusion           TEXT,
  evaluacion                 JSONB,
  creado_en                  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  actualizado_en             TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_mypump_presion_sesiones_cliente ON mypump_presion_sesiones (cliente_id, inicio DESC);
CREATE INDEX IF NOT EXISTS idx_mypump_presion_sesiones_serie ON mypump_presion_sesiones (serie_id) WHERE serie_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS mypump_presion_tomas (
  id                    UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  sesion_id             UUID        NOT NULL REFERENCES mypump_presion_sesiones (id) ON DELETE CASCADE,
  orden                 INTEGER     NOT NULL CHECK (orden BETWEEN 1 AND 4),
  posicion              TEXT        NOT NULL DEFAULT 'sentado' CHECK (posicion IN ('sentado','acostado','de_pie')),
  minutos_de_pie        INTEGER     CHECK (minutos_de_pie IN (1, 3)),
  brazo                 TEXT        CHECK (brazo IN ('izq','der')),
  sistolica             INTEGER     NOT NULL CHECK (sistolica BETWEEN 60 AND 260),
  diastolica            INTEGER     NOT NULL CHECK (diastolica BETWEEN 30 AND 160),
  pulso                 INTEGER     NOT NULL CHECK (pulso BETWEEN 25 AND 220),
  latido_irregular      BOOLEAN     NOT NULL DEFAULT FALSE,
  medido_en             TIMESTAMPTZ NOT NULL,
  origen                TEXT        NOT NULL DEFAULT 'manual' CHECK (origen IN ('manual','bluetooth','salud_del_telefono')),
  origen_fuente         TEXT,
  foto_pantalla_path    TEXT        CHECK (foto_pantalla_path !~ '^[a-z]+://'),
  confirmada_por_alumno BOOLEAN     NOT NULL DEFAULT FALSE,
  valida_para_promedio  BOOLEAN     NOT NULL DEFAULT FALSE,
  motivo_exclusion      TEXT        CHECK (motivo_exclusion IN ('condicion_incumplida','comparacion_brazos','ortostatica','bajo_efecto','muneca','error','otra')),
  UNIQUE (sesion_id, orden),
  CHECK (sistolica - diastolica >= 10)
);

CREATE TABLE IF NOT EXISTS mypump_presion_sintomas (
  id                    UUID        PRIMARY KEY,                    -- lo genera el teléfono
  cliente_id            TEXT        NOT NULL,
  marcado_en            TIMESTAMPTZ NOT NULL,
  zona_horaria          TEXT,
  sesion_id             UUID,
  toma_id               UUID,
  contexto              TEXT        NOT NULL CHECK (contexto IN ('boton','en_toma','ortostatica','espera_180_120','recordatorio_180_120')),
  sin_sintomas_en_lista BOOLEAN,
  codigos               TEXT[]      NOT NULL DEFAULT '{}' CHECK (codigos <@ ARRAY['dolor_pecho','falta_aire','cefalea_fuerte_nueva','cambios_vista','debilidad_un_lado',
                          'dificultad_hablar','confusion','desmayo','desmayo_en_esfuerzo','palpitaciones','mareo_al_pararse','vomitos_diarrea','otro']),
  de_alarma             BOOLEAN     NOT NULL DEFAULT FALSE,
  nota                  TEXT        CHECK (char_length(nota) <= 500),
  creado_en             TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_mypump_presion_sintomas_cliente ON mypump_presion_sintomas (cliente_id, marcado_en DESC);

CREATE TABLE IF NOT EXISTS mypump_presion_avisos (
  id                     UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  cliente_id             TEXT        NOT NULL,
  nivel                  TEXT        NOT NULL CHECK (nivel IN ('urgencia','aviso','brief')),
  regla                  TEXT        NOT NULL,
  es_alta                BOOLEAN     NOT NULL DEFAULT FALSE,
  origen_tipo            TEXT        NOT NULL CHECK (origen_tipo IN ('sesion','sintoma','serie')),
  origen_id              UUID        NOT NULL,
  paso                   INTEGER,
  texto_alumno           TEXT,
  valores                JSONB,
  destino                TEXT        NOT NULL DEFAULT 'mensajes' CHECK (destino = 'mensajes'),   -- el único destino: nada directo a Mati
  enviado_a_mensajes_en  TIMESTAMPTZ,
  mensaje_borrador       TEXT        CHECK (char_length(mensaje_borrador) <= 2000),
  enviado_por_mati_en    TIMESTAMPTZ,
  pausa_estimulantes_id  UUID,
  creado_en              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  cerrado_en             TIMESTAMPTZ,
  cerrado_por            TEXT,
  nota_mati              TEXT,
  UNIQUE (origen_tipo, origen_id, regla)
);
CREATE INDEX IF NOT EXISTS idx_mypump_presion_avisos_cola ON mypump_presion_avisos (creado_en) WHERE enviado_a_mensajes_en IS NULL AND nivel <> 'brief';
CREATE INDEX IF NOT EXISTS idx_mypump_presion_avisos_cliente ON mypump_presion_avisos (cliente_id, creado_en DESC);

CREATE TABLE IF NOT EXISTS mypump_presion_pausas (
  id                   UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  cliente_id           TEXT        NOT NULL,
  aviso_id             UUID        NOT NULL REFERENCES mypump_presion_avisos (id),
  criterio             TEXT        NOT NULL CHECK (criterio IN ('promedio_135_85','toma_160_100_confirmada','bajo_efecto_150_95','toma_180_120_sin_repetir','urgencia')),
  valores              JSONB,
  estimulantes         TEXT[]      NOT NULL DEFAULT '{}',
  pedido_editor_texto  TEXT,
  pedido_editor_en     TIMESTAMPTZ,
  editor_estado        TEXT        NOT NULL DEFAULT 'pendiente' CHECK (editor_estado IN ('pendiente','aplicado','observado')),
  editor_revisado_en   TIMESTAMPTZ,
  mensaje_borrador     TEXT,
  enviado_por_mati_en  TIMESTAMPTZ,
  serie_control_id     UUID,
  reanudar             TEXT        NOT NULL DEFAULT 'pendiente' CHECK (reanudar IN ('pendiente','si','no')),
  reanudar_decidido_en TIMESTAMPTZ,
  creado_en            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  cerrado_en           TIMESTAMPTZ
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_mypump_presion_pausa_abierta ON mypump_presion_pausas (cliente_id) WHERE cerrado_en IS NULL;

-- En este proyecto las tablas nuevas heredan permisos por defecto, incluido TRUNCATE, que RLS no frena. anon, nada.
REVOKE ALL ON mypump_presion_habilitados, mypump_presion_tensiometros, mypump_presion_brazo, mypump_presion_aparatos, mypump_presion_comparaciones,
  mypump_presion_series, mypump_presion_sesiones, mypump_presion_tomas, mypump_presion_sintomas, mypump_presion_avisos, mypump_presion_pausas
  FROM PUBLIC, anon, authenticated, service_role;
-- El equipo lee todo; lo que cambia algo pasa por las funciones de abajo. La lista de habilitados y la de tensiómetros se editan a mano.
GRANT SELECT ON mypump_presion_habilitados, mypump_presion_tensiometros, mypump_presion_brazo, mypump_presion_aparatos, mypump_presion_comparaciones,
  mypump_presion_series, mypump_presion_sesiones, mypump_presion_tomas, mypump_presion_sintomas, mypump_presion_avisos, mypump_presion_pausas TO service_role;
GRANT INSERT, UPDATE, DELETE ON mypump_presion_habilitados, mypump_presion_tensiometros TO service_role;
ALTER TABLE mypump_presion_habilitados ENABLE ROW LEVEL SECURITY;
ALTER TABLE mypump_presion_tensiometros ENABLE ROW LEVEL SECURITY;
ALTER TABLE mypump_presion_brazo ENABLE ROW LEVEL SECURITY;
ALTER TABLE mypump_presion_aparatos ENABLE ROW LEVEL SECURITY;
ALTER TABLE mypump_presion_comparaciones ENABLE ROW LEVEL SECURITY;
ALTER TABLE mypump_presion_series ENABLE ROW LEVEL SECURITY;
ALTER TABLE mypump_presion_sesiones ENABLE ROW LEVEL SECURITY;
ALTER TABLE mypump_presion_tomas ENABLE ROW LEVEL SECURITY;
ALTER TABLE mypump_presion_sintomas ENABLE ROW LEVEL SECURITY;
ALTER TABLE mypump_presion_avisos ENABLE ROW LEVEL SECURITY;
ALTER TABLE mypump_presion_pausas ENABLE ROW LEVEL SECURITY;

-- ══ Reglas puras (las mismas de public/js/presion.js; el ensayo las corre contra los vectores) ══

-- Promedio redondeado al entero, la mitad para arriba, con cuentas enteras.
CREATE OR REPLACE FUNCTION mypump_presion_media(p INTEGER[])
RETURNS INTEGER LANGUAGE sql IMMUTABLE SET search_path = public AS $$
  SELECT CASE WHEN COALESCE(array_length(p, 1), 0) = 0 THEN NULL
              ELSE floor((2 * (SELECT sum(x) FROM unnest(p) x) + array_length(p, 1))::NUMERIC / (2 * array_length(p, 1)))::INTEGER END;
$$;

-- 'ok', 'imposible' o 'confirmar' (CAMPOS §4, control al anotar a mano).
CREATE OR REPLACE FUNCTION mypump_presion_validar(p_sis NUMERIC, p_dia NUMERIC, p_pulso NUMERIC)
RETURNS TEXT LANGUAGE sql IMMUTABLE SET search_path = public AS $$
  SELECT CASE
    WHEN p_sis IS NULL OR p_dia IS NULL OR p_pulso IS NULL OR p_sis <> floor(p_sis) OR p_dia <> floor(p_dia) OR p_pulso <> floor(p_pulso) THEN 'imposible'
    WHEN p_sis < 60 OR p_sis > 260 OR p_dia < 30 OR p_dia > 160 OR p_pulso < 25 OR p_pulso > 220 OR p_sis - p_dia < 10 THEN 'imposible'
    WHEN p_sis >= 160 OR p_dia >= 100 OR p_pulso >= 120 OR p_pulso <= 40 THEN 'confirmar'
    ELSE 'ok' END;
$$;

CREATE OR REPLACE FUNCTION mypump_presion_categoria(p_sis INTEGER, p_dia INTEGER)
RETURNS TEXT LANGUAGE sql IMMUTABLE SET search_path = public AS $$
  SELECT CASE WHEN p_sis >= 150 OR p_dia >= 95 THEN 'hipertension_casa_estadio_2'
              WHEN p_sis >= 135 OR p_dia >= 85 THEN 'hipertension_casa'
              WHEN p_sis >= 130 OR p_dia >= 80 THEN 'limitrofe'
              WHEN p_sis >= 120 THEN 'elevada' ELSE 'optima' END;
$$;

-- Una sesión: qué le toca a la app, si la toma cuenta y qué reglas se cumplen. Solo con tomas sentado; la urgencia y la
-- alta se evalúan siempre, también en las tomas que no cuentan (PROTOCOLO §2.4).
CREATE OR REPLACE FUNCTION mypump_presion_evaluar_sesion(p JSONB)
RETURNS JSONB LANGUAGE plpgsql IMMUTABLE SET search_path = public AS $$
DECLARE
  v_tipo    TEXT := COALESCE(p->>'tipo', 'estandar');
  v_sint    TEXT[] := ARRAY(SELECT jsonb_array_elements_text(CASE WHEN jsonb_typeof(p->'sintomas') = 'array' THEN p->'sintomas' ELSE '[]'::JSONB END));
  v_tomas   JSONB := CASE WHEN jsonb_typeof(p->'tomas') = 'array' THEN p->'tomas' ELSE '[]'::JSONB END;
  v_alarmas CONSTANT TEXT[] := ARRAY['dolor_pecho','falta_aire','cefalea_fuerte_nueva','cambios_vista','debilidad_un_lado','dificultad_hablar','confusion','desmayo','desmayo_en_esfuerzo'];
  v_s INTEGER[]; v_d INTEGER[]; v_pu INTEGER[];
  v_niv TEXT[] := '{}';
  v_n INTEGER; i INTEGER;
  v_conf180 BOOLEAN := FALSE; v_conf160 BOOLEAN := FALSE;
  v_guiada BOOLEAN; v_ult TEXT := 'comun'; v_pend BOOLEAN;
  v_min NUMERIC := COALESCE((p->>'minutos_desde_ultima')::NUMERIC, 0);
  v_reglas TEXT[] := '{}'; v_paso TEXT := 'listo'; v_texto TEXT := 'ninguno';
  v_alarma BOOLEAN; v_p120 BOOLEAN; v_p40 BOOLEAN; v_urg BOOLEAN;
  v_otros INTEGER; v_orto JSONB := NULL; v_valor JSONB := NULL;
  v_incumplida BOOLEAN; v_cuenta BOOLEAN := FALSE; v_motivo TEXT := NULL; v_valida_be BOOLEAN;
  b_sis INTEGER; b_dia INTEGER; b_pulso INTEGER; v_cs INTEGER; v_cd INTEGER; v_sp INTEGER; v_sube INTEGER; v_pie140 BOOLEAN;
BEGIN
  SELECT array_agg(sis ORDER BY orden, ord), array_agg(dia ORDER BY orden, ord), array_agg(pulso ORDER BY orden, ord) INTO v_s, v_d, v_pu
  FROM (SELECT (t->>'sis')::INTEGER sis, (t->>'dia')::INTEGER dia, (t->>'pulso')::INTEGER pulso, (t->>'orden')::NUMERIC orden, ord
        FROM jsonb_array_elements(v_tomas) WITH ORDINALITY AS x(t, ord)
        WHERE COALESCE(t->>'posicion', 'sentado') = 'sentado') q;
  v_n := COALESCE(array_length(v_s, 1), 0);
  FOR i IN 1..v_n LOOP
    v_niv := v_niv || CASE WHEN v_s[i] >= 180 OR v_d[i] >= 120 THEN 'urgencia' WHEN v_s[i] >= 160 OR v_d[i] >= 100 THEN 'alta' ELSE 'comun' END;
    IF i > 1 THEN
      IF v_niv[i] = 'urgencia' AND v_niv[i - 1] = 'urgencia' THEN v_conf180 := TRUE; END IF;
      IF v_niv[i] <> 'comun' AND v_niv[i - 1] <> 'comun' THEN v_conf160 := TRUE; END IF;
    END IF;
  END LOOP;
  v_guiada := v_tipo IN ('ortostatica', 'comparacion_brazos');
  IF v_n > 0 THEN v_ult := v_niv[v_n]; END IF;
  v_pend := NOT v_guiada AND v_n > 0 AND ((v_ult = 'urgencia' AND NOT v_conf180) OR (v_ult = 'alta' AND NOT v_conf160));

  v_alarma := v_sint && v_alarmas;
  v_p120 := EXISTS (SELECT 1 FROM unnest(v_pu) x WHERE x >= 120) AND v_sint && ARRAY['palpitaciones','dolor_pecho','falta_aire','mareo_al_pararse'];
  v_p40 := EXISTS (SELECT 1 FROM unnest(v_pu) x WHERE x <= 40) AND v_sint && ARRAY['mareo_al_pararse','desmayo','desmayo_en_esfuerzo'];
  IF v_alarma THEN v_reglas := v_reglas || CASE WHEN p->>'lista_espera' = 'si' THEN 'sintoma_alarma_en_espera' ELSE 'sintoma_alarma' END; END IF;
  IF v_sint && ARRAY['desmayo','desmayo_en_esfuerzo'] THEN v_reglas := v_reglas || 'desmayo'::TEXT; END IF;
  IF v_p120 THEN v_reglas := v_reglas || 'pulso_120_sintomas'::TEXT; END IF;
  IF v_p40 THEN v_reglas := v_reglas || 'pulso_40_mareo'::TEXT; END IF;
  IF v_conf180 THEN v_reglas := v_reglas || 'toma_180_120_confirmada'::TEXT;
  ELSIF v_conf160 THEN v_reglas := v_reglas || 'alta_toma_160_100'::TEXT; END IF;
  -- Una toma de 180/120 sin repetir cuenta como alta a los 15 minutos (el recordatorio sale a los 10).
  IF v_pend AND v_ult = 'urgencia' AND v_min >= 15 THEN v_reglas := v_reglas || 'alta_180_120_sin_repetir'::TEXT; END IF;
  IF v_pend AND v_ult = 'alta' AND v_min >= 10 THEN v_reglas := v_reglas || 'repetir_pendiente'::TEXT; END IF;

  v_urg := v_alarma OR v_p120 OR v_p40;
  IF v_urg THEN v_paso := 'guardia_sintomas'; v_texto := 'guardia_sintomas';
  ELSIF v_conf180 THEN v_paso := 'guardia_presion'; v_texto := 'guardia_presion';
  ELSIF v_pend THEN
    v_paso := CASE WHEN v_ult = 'urgencia' THEN 'repetir_con_lista' ELSE 'repetir' END;
    v_texto := CASE WHEN v_min >= 10 THEN 'repetir_pendiente' WHEN v_ult = 'urgencia' THEN 'lista_sintomas_espera' ELSE 'quedate_sentado_5min' END;
  END IF;

  SELECT count(*) INTO v_otros FROM unnest(v_sint) x WHERE x <> ALL (v_alarmas);
  IF EXISTS (SELECT 1 FROM unnest(v_s) x WHERE x < 90) AND v_otros > 0 THEN
    v_reglas := v_reglas || 'sistolica_menor_90_sintomas'::TEXT;
    IF v_paso = 'listo' THEN v_texto := 'sentate_agua'; END IF;
  END IF;
  IF 'mareo_al_pararse' = ANY (v_sint) THEN
    v_reglas := v_reglas || 'sintomas_al_pararse'::TEXT;
    IF v_tipo = 'ortostatica' AND v_paso = 'listo' THEN v_texto := 'quedate_sentado_ortostatica'; END IF;
  END IF;
  IF 'vomitos_diarrea' = ANY (v_sint) THEN v_reglas := v_reglas || 'sintoma_vomitos_diarrea'::TEXT; END IF;
  IF EXISTS (SELECT 1 FROM unnest(v_pu) x WHERE x <= 40) AND cardinality(v_sint) = 0 THEN v_reglas := v_reglas || 'pulso_40_sin_sintomas'::TEXT; END IF;

  IF v_tipo = 'ortostatica' THEN
    SELECT (t->>'sis')::INTEGER, (t->>'dia')::INTEGER, (t->>'pulso')::INTEGER INTO b_sis, b_dia, b_pulso
    FROM jsonb_array_elements(v_tomas) WITH ORDINALITY AS x(t, ord) WHERE t->>'posicion' IS DISTINCT FROM 'de_pie' ORDER BY ord LIMIT 1;
    SELECT max(b_sis - (t->>'sis')::INTEGER), max(b_dia - (t->>'dia')::INTEGER), max((t->>'pulso')::INTEGER - b_pulso), max((t->>'sis')::INTEGER - b_sis),
           bool_or((t->>'sis')::INTEGER >= 140 AND (t->>'sis')::INTEGER > b_sis)
      INTO v_cs, v_cd, v_sp, v_sube, v_pie140
    FROM jsonb_array_elements(v_tomas) t WHERE t->>'posicion' = 'de_pie';
    IF b_sis IS NOT NULL AND v_cs IS NOT NULL THEN
      v_orto := jsonb_build_object('caida_sis_max', v_cs, 'caida_dia_max', v_cd, 'subida_pulso_max', v_sp,
                                   'hipotension', v_cs >= 20 OR v_cd >= 10, 'hipertension_posible', v_sube >= 20 OR v_pie140);
      IF v_cs >= 20 OR v_cd >= 10 THEN v_reglas := v_reglas || 'ortostatica_positiva'::TEXT; END IF;
    END IF;
  END IF;

  IF v_n > 0 THEN v_valor := jsonb_build_object('sis', mypump_presion_media(v_s), 'dia', mypump_presion_media(v_d), 'pulso', mypump_presion_media(v_pu)); END IF;
  v_incumplida := COALESCE((p->'previo'->>'cafeina')::BOOLEAN, FALSE) OR COALESCE((p->'previo'->>'fumo')::BOOLEAN, FALSE)
               OR COALESCE((p->'previo'->>'comida')::BOOLEAN, FALSE) OR COALESCE((p->'previo'->>'ejercicio')::BOOLEAN, FALSE)
               OR (p->>'reposo_cumplido')::BOOLEAN IS DISTINCT FROM TRUE OR (p->>'temporizador_salteado')::BOOLEAN IS TRUE;
  IF jsonb_array_length(v_tomas) = 0 THEN v_motivo := 'error';
  ELSIF v_tipo = 'bajo_efecto' THEN v_motivo := 'bajo_efecto';
  ELSIF v_tipo = 'ortostatica' THEN v_motivo := 'ortostatica';
  ELSIF v_tipo = 'comparacion_brazos' THEN v_motivo := 'comparacion_brazos';
  ELSIF v_tipo = 'suelta' THEN v_motivo := 'otra';
  ELSIF v_n = 0 THEN v_motivo := 'error';
  ELSIF v_incumplida THEN v_motivo := 'condicion_incumplida';
  ELSIF v_pend THEN v_motivo := 'otra';
  ELSE v_cuenta := TRUE; END IF;
  IF v_motivo = 'condicion_incumplida' AND v_paso = 'listo' AND v_texto = 'ninguno' THEN v_texto := 'toma_no_cuenta'; END IF;
  v_valida_be := v_tipo = 'bajo_efecto' AND v_n > 0 AND NOT v_pend AND (p->>'reposo_cumplido')::BOOLEAN IS TRUE
             AND (p->>'temporizador_salteado')::BOOLEAN IS NOT TRUE AND (p->>'entreno_entre_dosis_y_toma')::BOOLEAN IS FALSE;
  IF v_tipo = 'bajo_efecto' AND v_n > 0 AND NOT v_valida_be AND v_paso = 'listo' AND v_texto = 'ninguno' THEN v_texto := 'toma_no_cuenta'; END IF;
  -- Una toma suelta de 135/85 o más no avisa: dispara una serie de 3 tomas (PROTOCOLO §6).
  IF v_tipo = 'suelta' AND v_valor IS NOT NULL AND NOT v_pend AND ((v_valor->>'sis')::INTEGER >= 135 OR (v_valor->>'dia')::INTEGER >= 85) THEN
    v_reglas := v_reglas || 'suelta_135_85'::TEXT;
  END IF;

  RETURN jsonb_build_object('paso', v_paso, 'texto', v_texto, 'cuenta', v_cuenta, 'motivo_exclusion', v_motivo, 'valor', v_valor,
    'valida_bajo_efecto', v_valida_be, 'urgencia', v_urg OR v_conf180, 'ortostatica', v_orto,
    'reglas', COALESCE((SELECT jsonb_agg(x ORDER BY x COLLATE "C") FROM unnest(v_reglas) x), '[]'::JSONB));
END;
$$;

-- La serie: 3 tomas válidas, una por día, en 3 días distintos dentro de los 7 días del inicio.
CREATE OR REPLACE FUNCTION mypump_presion_resumen_serie(p JSONB)
RETURNS JSONB LANGUAGE plpgsql IMMUTABLE SET search_path = public AS $$
DECLARE
  v_obj INTEGER := COALESCE(NULLIF((p->'serie'->>'tomas_objetivo')::INTEGER, 0), 3);
  v_be_serie BOOLEAN := p->'serie'->>'tipo' = 'bajo_efecto';
  v_ini DATE := (p->'serie'->>'fecha_inicio')::DATE;
  v_solo BOOLEAN := (p->>'solo_urgencias')::BOOLEAN IS TRUE;
  v_basal INTEGER := CASE WHEN jsonb_typeof(p->'basal_pulso') = 'number' THEN (p->>'basal_pulso')::INTEGER END;
  r RECORD; ev JSONB; v_f DATE; v_plazo BOOLEAN;
  v_reglas TEXT[] := '{}';
  v_dias DATE[] := '{}'; v_vs INTEGER[] := '{}'; v_vd INTEGER[] := '{}'; v_vp INTEGER[] := '{}';
  v_bdias DATE[] := '{}'; v_bs INTEGER[] := '{}'; v_bd INTEGER[] := '{}'; v_bp INTEGER[] := '{}';
  v_max_s INTEGER; v_max_d INTEGER; v_ben INTEGER := 0; v_irr INTEGER := 0;
  v_prom JSONB := NULL; v_bprom JSONB := NULL; v_validas INTEGER; v_valida BOOLEAN;
  v_be_alta BOOLEAN := FALSE; v_be_aviso BOOLEAN := FALSE; v_be_pulso INTEGER;
BEGIN
  FOR r IN SELECT s, ord FROM jsonb_array_elements(CASE WHEN jsonb_typeof(p->'sesiones') = 'array' THEN p->'sesiones' ELSE '[]'::JSONB END) WITH ORDINALITY AS x(s, ord)
           ORDER BY s->>'fecha', COALESCE((s->>'orden')::NUMERIC, 0), ord LOOP
    ev := mypump_presion_evaluar_sesion(r.s);
    v_reglas := v_reglas || ARRAY(SELECT jsonb_array_elements_text(ev->'reglas'));
    v_irr := v_irr + (SELECT count(*) FROM jsonb_array_elements(COALESCE(r.s->'tomas', '[]'::JSONB)) t WHERE (t->>'latido_irregular')::BOOLEAN IS TRUE);
    v_f := (r.s->>'fecha')::DATE;
    v_plazo := v_ini IS NULL OR (v_f >= v_ini AND v_f <= v_ini + 6);
    IF r.s->>'tipo' = 'bajo_efecto' THEN
      v_ben := v_ben + 1;
      IF (ev->>'valida_bajo_efecto')::BOOLEAN AND v_plazo AND NOT v_f = ANY (v_bdias) AND cardinality(v_bdias) < v_obj THEN
        v_bdias := v_bdias || v_f;
        v_bs := v_bs || (ev->'valor'->>'sis')::INTEGER; v_bd := v_bd || (ev->'valor'->>'dia')::INTEGER; v_bp := v_bp || (ev->'valor'->>'pulso')::INTEGER;
      END IF;
    END IF;
    IF (ev->>'cuenta')::BOOLEAN AND v_plazo AND NOT v_f = ANY (v_dias) AND cardinality(v_dias) < v_obj THEN
      v_dias := v_dias || v_f;
      v_vs := v_vs || (ev->'valor'->>'sis')::INTEGER; v_vd := v_vd || (ev->'valor'->>'dia')::INTEGER; v_vp := v_vp || (ev->'valor'->>'pulso')::INTEGER;
      SELECT GREATEST(v_max_s, max((t->>'sis')::INTEGER)), GREATEST(v_max_d, max((t->>'dia')::INTEGER)) INTO v_max_s, v_max_d
      FROM jsonb_array_elements(COALESCE(r.s->'tomas', '[]'::JSONB)) t;
    END IF;
  END LOOP;

  IF cardinality(v_vs) > 0 THEN v_prom := jsonb_build_object('sis', mypump_presion_media(v_vs), 'dia', mypump_presion_media(v_vd), 'pulso', mypump_presion_media(v_vp)); END IF;
  v_validas := CASE WHEN v_be_serie THEN cardinality(v_bdias) ELSE cardinality(v_dias) END;
  v_valida := v_validas >= v_obj;
  IF NOT v_be_serie AND v_valida AND NOT v_solo AND ((v_prom->>'sis')::INTEGER >= 135 OR (v_prom->>'dia')::INTEGER >= 85) THEN v_reglas := v_reglas || 'alta_promedio_135_85'::TEXT; END IF;
  IF (SELECT count(*) FROM unnest(v_vp) x WHERE x >= 100) >= 2 THEN v_reglas := v_reglas || 'pulso_100_dos_tomas'::TEXT; END IF;
  IF NOT v_be_serie AND v_valida AND v_basal IS NOT NULL AND (v_prom->>'pulso')::INTEGER - v_basal >= 20 THEN v_reglas := v_reglas || 'pulso_20_sobre_basal'::TEXT; END IF;
  IF v_irr >= 2 THEN v_reglas := v_reglas || 'latido_irregular_2_tomas'::TEXT; END IF;

  IF cardinality(v_bs) > 0 THEN v_bprom := jsonb_build_object('sis', mypump_presion_media(v_bs), 'dia', mypump_presion_media(v_bd), 'pulso', mypump_presion_media(v_bp)); END IF;
  IF cardinality(v_bs) >= 2 THEN
    v_be_alta := (v_bprom->>'sis')::INTEGER >= 150 OR (v_bprom->>'dia')::INTEGER >= 95;
    v_be_aviso := NOT v_be_alta AND ((v_bprom->>'sis')::INTEGER >= 135 OR (v_bprom->>'dia')::INTEGER >= 85);
  END IF;
  SELECT count(*) INTO v_be_pulso FROM unnest(v_bp) x WHERE x >= 100;
  IF v_be_alta THEN v_reglas := v_reglas || 'alta_bajo_efecto_150_95'::TEXT; END IF;
  IF v_be_aviso THEN v_reglas := v_reglas || 'bajo_efecto_135_85'::TEXT; END IF;
  IF v_be_pulso >= 2 THEN v_reglas := v_reglas || 'pulso_100_bajo_efecto'::TEXT; END IF;

  RETURN jsonb_build_object(
    'tomas_validas', v_validas,
    'dias', COALESCE((SELECT jsonb_agg(to_char(d, 'YYYY-MM-DD') ORDER BY o) FROM unnest(CASE WHEN v_be_serie THEN v_bdias ELSE v_dias END) WITH ORDINALITY AS x(d, o)), '[]'::JSONB),
    'serie_valida', v_valida, 'faltan', GREATEST(0, v_obj - v_validas), 'promedio', v_prom,
    'maximos', CASE WHEN v_max_s IS NOT NULL THEN jsonb_build_object('sis', v_max_s, 'dia', v_max_d) END,
    'categoria', CASE WHEN NOT v_be_serie AND v_valida AND NOT v_solo THEN mypump_presion_categoria((v_prom->>'sis')::INTEGER, (v_prom->>'dia')::INTEGER) END,
    'bajo_efecto', jsonb_build_object('n', v_ben, 'validas', cardinality(v_bs), 'promedio', CASE WHEN cardinality(v_bs) >= 2 THEN v_bprom END,
                                      'tomas_pulso_100_o_mas', v_be_pulso, 'aviso', v_be_aviso, 'alta', v_be_alta),
    'reglas', COALESCE((SELECT jsonb_agg(x ORDER BY x COLLATE "C") FROM (SELECT DISTINCT x FROM unnest(v_reglas) x) q), '[]'::JSONB));
END;
$$;

-- Nivel de cada regla (PROTOCOLO §5.2): urgencia, aviso o brief, y si cuenta como alta.
CREATE OR REPLACE FUNCTION mypump_presion_nivel_regla(p_regla TEXT, p_con_sintomas BOOLEAN DEFAULT FALSE)
RETURNS TABLE (nivel TEXT, es_alta BOOLEAN) LANGUAGE sql IMMUTABLE SET search_path = public AS $$
  SELECT CASE
      WHEN p_regla IN ('toma_180_120_confirmada','sintoma_alarma','sintoma_alarma_en_espera','desmayo','pulso_120_sintomas','pulso_40_mareo') THEN 'urgencia'
      WHEN p_regla IN ('alta_promedio_135_85','alta_toma_160_100','alta_bajo_efecto_150_95','alta_180_120_sin_repetir','bajo_efecto_135_85','pulso_100_bajo_efecto',
                       'sintomas_al_pararse','sistolica_menor_90_sintomas','latido_irregular_2_tomas','pulso_100_dos_tomas','pulso_20_sobre_basal','pulso_40_sin_sintomas',
                       'diferencia_brazos_20') THEN 'aviso'
      WHEN p_regla = 'ortostatica_positiva' AND p_con_sintomas THEN 'aviso'
      ELSE 'brief' END,
    p_regla IN ('toma_180_120_confirmada','sintoma_alarma','sintoma_alarma_en_espera','desmayo','pulso_120_sintomas','pulso_40_mareo',
                'alta_promedio_135_85','alta_toma_160_100','alta_bajo_efecto_150_95','alta_180_120_sin_repetir');
$$;

REVOKE ALL ON FUNCTION mypump_presion_media(INTEGER[]), mypump_presion_validar(NUMERIC, NUMERIC, NUMERIC), mypump_presion_categoria(INTEGER, INTEGER),
  mypump_presion_evaluar_sesion(JSONB), mypump_presion_resumen_serie(JSONB), mypump_presion_nivel_regla(TEXT, BOOLEAN) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION mypump_presion_media(INTEGER[]), mypump_presion_validar(NUMERIC, NUMERIC, NUMERIC), mypump_presion_categoria(INTEGER, INTEGER),
  mypump_presion_evaluar_sesion(JSONB), mypump_presion_resumen_serie(JSONB), mypump_presion_nivel_regla(TEXT, BOOLEAN) TO service_role;

-- ══ Internas ══

CREATE OR REPLACE FUNCTION mypump_presion_habilitado(p_cliente_id TEXT)
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT COALESCE((SELECT valor = 'true'::JSONB FROM mypump_app_config WHERE clave = 'presion_app'), FALSE)
     AND (COALESCE((SELECT valor = 'true'::JSONB FROM mypump_app_config WHERE clave = 'presion_para_todos'), FALSE)
          OR EXISTS (SELECT 1 FROM mypump_presion_habilitados WHERE cliente_id = p_cliente_id));
$$;

-- Una zona que Postgres no conoce no rompe nada: vale la de Argentina.
CREATE OR REPLACE FUNCTION mypump_presion_zona(p_zona TEXT)
RETURNS TEXT LANGUAGE sql STABLE SET search_path = public AS $$
  SELECT COALESCE((SELECT name FROM pg_timezone_names WHERE name = p_zona LIMIT 1), 'America/Argentina/Buenos_Aires');
$$;

CREATE OR REPLACE FUNCTION mypump_presion_tipo_serie(p_motivo TEXT)
RETURNS TEXT LANGUAGE sql IMMUTABLE SET search_path = public AS $$
  SELECT CASE WHEN p_motivo IN ('estimulante_nuevo','estimulante_pre_entrega','clenbuterol_dosis_maxima') THEN 'bajo_efecto' ELSE 'estandar' END;
$$;

-- El rango que manda: el validado si está, si no el impreso. En el límite entre dos talles, el más grande.
CREATE OR REPLACE FUNCTION mypump_presion_calza(p_cm NUMERIC, a mypump_presion_aparatos)
RETURNS BOOLEAN LANGUAGE sql IMMUTABLE SET search_path = public AS $$
  SELECT CASE WHEN p_cm IS NULL OR lo IS NULL OR hi IS NULL THEN NULL
              WHEN p_cm < lo OR p_cm > hi THEN FALSE
              WHEN p_cm = hi AND hi IN (32, 42) THEN FALSE ELSE TRUE END
  FROM (SELECT CASE WHEN a.manguito_validado_min_cm IS NOT NULL AND a.manguito_validado_max_cm IS NOT NULL THEN a.manguito_validado_min_cm ELSE a.manguito_min_cm END lo,
               CASE WHEN a.manguito_validado_min_cm IS NOT NULL AND a.manguito_validado_max_cm IS NOT NULL THEN a.manguito_validado_max_cm ELSE a.manguito_max_cm END hi) r;
$$;

-- La sesión como la leen las reglas.
CREATE OR REPLACE FUNCTION mypump_presion_sesion_json(s mypump_presion_sesiones, p_ahora TIMESTAMPTZ)
RETURNS JSONB LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT jsonb_build_object(
    'tipo', s.tipo, 'fecha', to_char(s.fecha, 'YYYY-MM-DD'), 'orden', extract(epoch FROM s.inicio),
    'previo', jsonb_build_object('cafeina', s.previo_cafeina, 'fumo', s.previo_fumo, 'comida', s.previo_comida, 'ejercicio', s.previo_ejercicio),
    'reposo_cumplido', s.reposo_cumplido, 'temporizador_salteado', s.temporizador_salteado,
    'entreno_entre_dosis_y_toma', s.entreno_entre_dosis_y_toma, 'sintomas', to_jsonb(s.sintomas), 'lista_espera', s.lista_espera,
    'minutos_desde_ultima', GREATEST(0, floor(extract(epoch FROM p_ahora - LEAST(p_ahora, (SELECT max(medido_en) FROM mypump_presion_tomas WHERE sesion_id = s.id))) / 60)),
    'tomas', COALESCE((SELECT jsonb_agg(jsonb_build_object('orden', t.orden, 'posicion', t.posicion, 'minutos_de_pie', t.minutos_de_pie, 'brazo', t.brazo,
                         'sis', t.sistolica, 'dia', t.diastolica, 'pulso', t.pulso, 'latido_irregular', t.latido_irregular) ORDER BY t.orden)
                       FROM mypump_presion_tomas t WHERE t.sesion_id = s.id), '[]'::JSONB));
$$;

CREATE OR REPLACE FUNCTION mypump_presion_aviso_nuevo(p_cliente_id TEXT, p_regla TEXT, p_origen_tipo TEXT, p_origen_id UUID, p_valores JSONB, p_texto TEXT, p_con_sintomas BOOLEAN, p_paso INTEGER)
RETURNS VOID LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  INSERT INTO mypump_presion_avisos (cliente_id, nivel, regla, es_alta, origen_tipo, origen_id, valores, texto_alumno, paso)
  SELECT p_cliente_id, n.nivel, p_regla, n.es_alta, p_origen_tipo, p_origen_id, p_valores, p_texto, p_paso FROM mypump_presion_nivel_regla(p_regla, p_con_sintomas) n
  ON CONFLICT (origen_tipo, origen_id, regla) DO NOTHING;
$$;

-- Recalcula la serie: resumen (CAMPOS §8), avisos de la serie y cierre. Los fármacos no se copian acá: el brief los cruza con la ficha.
CREATE OR REPLACE FUNCTION mypump_presion_recalcular_serie(p_serie_id UUID, p_ahora TIMESTAMPTZ DEFAULT NOW())
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v mypump_presion_series%ROWTYPE;
  a mypump_presion_aparatos%ROWTYPE;
  c mypump_presion_comparaciones%ROWTYPE;
  v_entrada JSONB; r JSONB; v_regla TEXT; v_resumen JSONB; v_basal INTEGER; v_todas JSONB; v_orto JSONB; v_hoy DATE; v_estado TEXT;
  v_provisoria BOOLEAN; v_habitual BOOLEAN;
BEGIN
  SELECT * INTO v FROM mypump_presion_series WHERE id = p_serie_id FOR UPDATE;
  IF NOT FOUND OR v.estado = 'cancelada' THEN RETURN; END IF;
  SELECT * INTO a FROM mypump_presion_aparatos WHERE id = v.aparato_id;
  SELECT * INTO c FROM mypump_presion_comparaciones WHERE aparato_id = v.aparato_id ORDER BY cargada_en DESC LIMIT 1;
  SELECT (resumen->'promedios'->'global'->>'pulso')::INTEGER INTO v_basal FROM mypump_presion_series
   WHERE id = v.serie_basal_id AND aparato_id IS NOT DISTINCT FROM v.aparato_id AND (resumen->>'serie_valida')::BOOLEAN;
  v_entrada := jsonb_build_object(
    'serie', jsonb_build_object('tipo', mypump_presion_tipo_serie(v.motivo), 'tomas_objetivo', v.tomas_objetivo, 'fecha_inicio', to_char(v.fecha_inicio, 'YYYY-MM-DD')),
    'solo_urgencias', COALESCE(c.solo_urgencias, FALSE), 'basal_pulso', v_basal,
    'sesiones', COALESCE((SELECT jsonb_agg(mypump_presion_sesion_json(s, p_ahora) ORDER BY s.inicio) FROM mypump_presion_sesiones s WHERE s.serie_id = v.id), '[]'::JSONB));
  r := mypump_presion_resumen_serie(v_entrada);

  FOR v_regla IN SELECT jsonb_array_elements_text(r->'reglas') LOOP
    IF v_regla IN ('alta_promedio_135_85','pulso_100_dos_tomas','pulso_20_sobre_basal','latido_irregular_2_tomas','alta_bajo_efecto_150_95','bajo_efecto_135_85','pulso_100_bajo_efecto') THEN
      PERFORM mypump_presion_aviso_nuevo(v.cliente_id, v_regla, 'serie', v.id, jsonb_build_object('promedio', r->'promedio', 'bajo_efecto', r->'bajo_efecto'->'promedio'), 'ninguno', FALSE, NULL);
    END IF;
  END LOOP;

  SELECT jsonb_build_object('sis', mypump_presion_media(array_agg(t.sistolica)), 'dia', mypump_presion_media(array_agg(t.diastolica)),
                            'pulso', mypump_presion_media(array_agg(t.pulso)), 'n', count(*)) INTO v_todas
  FROM mypump_presion_tomas t JOIN mypump_presion_sesiones s ON s.id = t.sesion_id WHERE s.serie_id = v.id AND s.tipo = 'estandar' AND t.posicion = 'sentado';
  SELECT s.evaluacion->'ortostatica' || jsonb_build_object('hecha', TRUE, 'motivos', to_jsonb(v.motivos_ortostatica), 'variante', v.variante_ortostatica,
           'sintomas', cardinality(s.sintomas) > 0, 'fecha', to_char(s.fecha, 'YYYY-MM-DD')) INTO v_orto
  FROM mypump_presion_sesiones s WHERE s.serie_id = v.id AND s.tipo = 'ortostatica' AND s.evaluacion->'ortostatica' <> 'null'::JSONB ORDER BY s.inicio DESC LIMIT 1;

  v_habitual := a.tipo = 'muneca' AND COALESCE(v.circunferencia_brazo_cm, 0) > 52;
  v_provisoria := (a.tipo = 'muneca' AND NOT v_habitual) OR (a.tipo = 'brazo' AND a.validado = 'no');
  v_resumen := jsonb_build_object(
    'version', 1, 'motivo', v.motivo, 'requisito_pre_entrega', v.requisito_pre_entrega,
    'periodo', jsonb_build_object('desde', to_char(v.fecha_inicio, 'YYYY-MM-DD'), 'hasta', r->'dias'->-1, 'limite', to_char(v.fecha_limite, 'YYYY-MM-DD'), 'zona_horaria', v.zona_horaria),
    'serie_valida', r->'serie_valida', 'tomas_validas', r->'tomas_validas', 'tomas_objetivo', v.tomas_objetivo, 'dias', r->'dias',
    'repeticiones_5min', (SELECT count(*) FROM mypump_presion_sesiones s WHERE s.serie_id = v.id AND s.tipo IN ('estandar','bajo_efecto') AND (SELECT count(*) FROM mypump_presion_tomas t WHERE t.sesion_id = s.id) > 1),
    'tomas_excluidas', COALESCE((SELECT jsonb_object_agg(m, n) FROM (SELECT s.motivo_exclusion m, count(*) n FROM mypump_presion_sesiones s WHERE s.serie_id = v.id AND s.motivo_exclusion IS NOT NULL GROUP BY 1) q), '{}'::JSONB),
    'aparato', jsonb_build_object('tipo', a.tipo, 'modelo', a.modelo, 'modelo_codigo', a.modelo_codigo, 'validado', a.validado, 'validado_talle_manguito', a.validado_talle_manguito,
      'manguito_cm', CASE WHEN a.manguito_min_cm IS NOT NULL THEN jsonb_build_array(a.manguito_min_cm, a.manguito_max_cm) END,
      'manguito_validado_cm', CASE WHEN a.manguito_validado_min_cm IS NOT NULL THEN jsonb_build_array(a.manguito_validado_min_cm, a.manguito_validado_max_cm) END,
      'conico', a.manguito_talle = 'conico', 'circunferencia_brazo_cm', v.circunferencia_brazo_cm, 'manguito_calza', v.manguito_calza,
      'provisoria', COALESCE(v_provisoria, FALSE), 'muneca_habitual', COALESCE(v_habitual, FALSE),
      'consultorio', jsonb_build_object('requerida', COALESCE(v_habitual, FALSE) OR COALESCE(a.tipo = 'brazo' AND v.circunferencia_brazo_cm >= 46, FALSE), 'hecha', c.id IS NOT NULL,
                                        'dif_sis', c.dif_media_sis, 'dif_dia', c.dif_media_dia, 'mas_de_10', COALESCE(c.mas_de_10, FALSE)),
      'solo_urgencias', COALESCE(c.solo_urgencias, FALSE)),
    'brazo', jsonb_build_object('elegido', v.brazo_elegido, 'comparacion_hecha', v.diferencia_brazos_mmhg IS NOT NULL, 'diferencia_mmhg', v.diferencia_brazos_mmhg),
    'promedios', jsonb_build_object('global', CASE WHEN r->'promedio' <> 'null'::JSONB THEN r->'promedio' || jsonb_build_object('n', jsonb_array_length(r->'dias')) END, 'todas_las_tomas', v_todas),
    'maximos', r->'maximos', 'categoria', r->'categoria', 'orientativa', TRUE,
    'cortes', jsonb_build_object('hipertension_casa', '135/85', 'aviso_mati', '135/85', 'limitrofe', '130/80', 'estadio_2_nice', '150/95',
                                 'alta_toma_confirmada', '160/100', 'alta_bajo_efecto', '150/95', 'aviso_bajo_efecto', '135/85', 'urgencia', '180/120'),
    -- Depende de si está en ciclo o con antihipertensivo: lo decide el brief con la ficha.
    'fuera_de_objetivo', NULL,
    'alta', jsonb_build_object('es_alta', EXISTS (SELECT 1 FROM mypump_presion_avisos w WHERE w.es_alta AND ((w.origen_tipo = 'serie' AND w.origen_id = v.id)
                                 OR (w.origen_tipo = 'sesion' AND w.origen_id IN (SELECT id FROM mypump_presion_sesiones WHERE serie_id = v.id)))),
      'criterios', COALESCE((SELECT jsonb_agg(DISTINCT w.regla) FROM mypump_presion_avisos w WHERE w.es_alta AND ((w.origen_tipo = 'serie' AND w.origen_id = v.id)
                                 OR (w.origen_tipo = 'sesion' AND w.origen_id IN (SELECT id FROM mypump_presion_sesiones WHERE serie_id = v.id)))), '[]'::JSONB)),
    'pausa_estimulantes', COALESCE((SELECT jsonb_build_object('abierta', TRUE, 'pausa_id', pz.id, 'desde', pz.creado_en) FROM mypump_presion_pausas pz WHERE pz.cliente_id = v.cliente_id AND pz.cerrado_en IS NULL),
                                   jsonb_build_object('abierta', FALSE, 'pausa_id', NULL, 'desde', NULL)),
    'pulso', jsonb_build_object('promedio', r->'promedio'->'pulso', 'basal', v_basal),
    'ortostatica', COALESCE(v_orto, jsonb_build_object('hecha', FALSE, 'pedida', v.incluye_ortostatica, 'motivos', to_jsonb(v.motivos_ortostatica))),
    'bajo_efecto', r->'bajo_efecto', 'alertas', r->'reglas',
    'sintomas', COALESCE((SELECT jsonb_agg(DISTINCT x) FROM mypump_presion_sesiones s, unnest(s.sintomas) x WHERE s.serie_id = v.id), '[]'::JSONB),
    'calidad', jsonb_build_object(
      'temporizador_salteado', (SELECT count(*) FROM mypump_presion_sesiones s WHERE s.serie_id = v.id AND s.temporizador_salteado),
      'fuera_de_la_manana', (SELECT count(*) FROM mypump_presion_sesiones s WHERE s.serie_id = v.id AND s.momento = 'otro' AND s.tipo = 'estandar'),
      'tomas_manuales', (SELECT count(*) FROM mypump_presion_tomas t JOIN mypump_presion_sesiones s ON s.id = t.sesion_id WHERE s.serie_id = v.id AND t.origen = 'manual'),
      'fotos', 0, 'muneca', a.tipo = 'muneca'),
    'comparacion', jsonb_build_object('serie_id', v.serie_basal_id, 'comparable', v_basal IS NOT NULL));

  v_hoy := (p_ahora AT TIME ZONE mypump_presion_zona(v.zona_horaria))::DATE;
  v_estado := CASE WHEN v.estado NOT IN ('pendiente', 'en_curso') THEN v.estado
                   WHEN (r->>'serie_valida')::BOOLEAN
                        AND NOT (v.incluye_ortostatica AND NOT EXISTS (SELECT 1 FROM mypump_presion_sesiones x WHERE x.serie_id = v.id AND x.tipo = 'ortostatica'))
                        AND NOT (v.comparar_brazos AND NOT EXISTS (SELECT 1 FROM mypump_presion_sesiones x WHERE x.serie_id = v.id AND x.tipo = 'comparacion_brazos'))
                        THEN 'completa'
                   WHEN v.fecha_limite IS NOT NULL AND v_hoy > v.fecha_limite THEN 'incompleta' ELSE v.estado END;
  UPDATE mypump_presion_series SET resumen = v_resumen, resumen_calculado_en = p_ahora, estado = v_estado, actualizado_en = p_ahora WHERE id = v.id;
END;
$$;

-- Evalúa una sesión, deja sus avisos y recalcula su serie. Se llama al guardar y desde el barrido.
CREATE OR REPLACE FUNCTION mypump_presion_recalcular(p_sesion_id UUID, p_ahora TIMESTAMPTZ DEFAULT NOW())
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  s mypump_presion_sesiones%ROWTYPE; ev JSONB; v_regla TEXT; v_tipo_ap TEXT; v_ya_suelta BOOLEAN;
BEGIN
  SELECT * INTO s FROM mypump_presion_sesiones WHERE id = p_sesion_id FOR UPDATE;
  IF NOT FOUND THEN RETURN NULL; END IF;
  ev := mypump_presion_evaluar_sesion(mypump_presion_sesion_json(s, p_ahora));
  SELECT tipo INTO v_tipo_ap FROM mypump_presion_aparatos WHERE id = s.aparato_id;
  UPDATE mypump_presion_sesiones SET cuenta = (ev->>'cuenta')::BOOLEAN, motivo_exclusion = ev->>'motivo_exclusion',
         valida_bajo_efecto = CASE WHEN s.tipo = 'bajo_efecto' THEN (ev->>'valida_bajo_efecto')::BOOLEAN END, evaluacion = ev, actualizado_en = p_ahora WHERE id = s.id;
  UPDATE mypump_presion_tomas SET valida_para_promedio = (ev->>'cuenta')::BOOLEAN AND posicion = 'sentado',
         motivo_exclusion = CASE WHEN (ev->>'cuenta')::BOOLEAN THEN NULL ELSE ev->>'motivo_exclusion' END WHERE sesion_id = s.id;
  v_ya_suelta := EXISTS (SELECT 1 FROM mypump_presion_avisos WHERE origen_tipo = 'sesion' AND origen_id = s.id AND regla = 'suelta_135_85');
  FOR v_regla IN SELECT jsonb_array_elements_text(ev->'reglas') LOOP
    PERFORM mypump_presion_aviso_nuevo(s.cliente_id, v_regla, 'sesion', s.id,
      jsonb_build_object('valor', ev->'valor', 'tipo', s.tipo, 'fecha', to_char(s.fecha, 'YYYY-MM-DD'), 'sintomas', to_jsonb(s.sintomas), 'muneca', v_tipo_ap = 'muneca',
                         'tomas', (SELECT jsonb_agg(jsonb_build_object('orden', t.orden, 'posicion', t.posicion, 'sis', t.sistolica, 'dia', t.diastolica, 'pulso', t.pulso) ORDER BY t.orden) FROM mypump_presion_tomas t WHERE t.sesion_id = s.id)),
      COALESCE(s.texto_alumno, ev->>'texto'), cardinality(s.sintomas) > 0, (SELECT count(*)::INTEGER - 1 FROM mypump_presion_tomas t WHERE t.sesion_id = s.id));
  END LOOP;
  -- Una toma suelta de 135/85 o más pide una serie de 3 tomas, si no hay una abierta.
  IF ev->'reglas' ? 'suelta_135_85' AND NOT v_ya_suelta AND NOT EXISTS (SELECT 1 FROM mypump_presion_series WHERE cliente_id = s.cliente_id AND estado IN ('pendiente', 'en_curso')) THEN
    INSERT INTO mypump_presion_series (cliente_id, motivo, pedida_por, regla_codigo, zona_horaria) VALUES (s.cliente_id, 'control_toma_alta', 'regla', 'suelta_135_85', s.zona_horaria);
  END IF;
  IF s.serie_id IS NOT NULL THEN PERFORM mypump_presion_recalcular_serie(s.serie_id, p_ahora); END IF;
  RETURN ev;
END;
$$;

-- Lo que el reloj cambia solo: la toma de 180/120 que no se repitió y las series que vencieron. Lo corre el get de cada
-- alumno y, sin argumento, el trabajo de la Mini cada pocos minutos.
CREATE OR REPLACE FUNCTION mypump_presion_barrer(p_cliente_id TEXT DEFAULT NULL)
RETURNS INTEGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_id UUID; n INTEGER := 0;
BEGIN
  FOR v_id IN SELECT id FROM mypump_presion_sesiones
              WHERE (p_cliente_id IS NULL OR cliente_id = p_cliente_id) AND inicio > NOW() - INTERVAL '2 days'
                AND evaluacion->>'paso' IN ('repetir', 'repetir_con_lista')
                AND NOT (evaluacion->'reglas' ?| ARRAY['alta_180_120_sin_repetir', 'repetir_pendiente']) LOOP
    PERFORM mypump_presion_recalcular(v_id); n := n + 1;
  END LOOP;
  FOR v_id IN SELECT id FROM mypump_presion_series
              WHERE (p_cliente_id IS NULL OR cliente_id = p_cliente_id) AND estado = 'en_curso'
                AND fecha_limite < (NOW() AT TIME ZONE mypump_presion_zona(zona_horaria))::DATE LOOP
    PERFORM mypump_presion_recalcular_serie(v_id); n := n + 1;
  END LOOP;
  RETURN n;
END;
$$;

-- Lo que ve el alumno: sus tomas tal como las anotó y el avance. Sin promedios, sin categorías, sin avisos.
CREATE OR REPLACE FUNCTION mypump_presion_estado(p_cliente_id TEXT, p_zona TEXT)
RETURNS JSONB LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_zona TEXT := mypump_presion_zona(p_zona);
  v_hoy DATE := (NOW() AT TIME ZONE mypump_presion_zona(p_zona))::DATE;
  a mypump_presion_aparatos%ROWTYPE;
  v mypump_presion_series%ROWTYPE;
  v_serie JSONB := NULL; v_pend JSONB := NULL;
BEGIN
  SELECT * INTO a FROM mypump_presion_aparatos WHERE cliente_id = p_cliente_id AND activo;
  SELECT * INTO v FROM mypump_presion_series WHERE cliente_id = p_cliente_id AND estado IN ('pendiente', 'en_curso')
   ORDER BY (estado = 'en_curso') DESC, creado_en LIMIT 1;
  IF v.id IS NOT NULL THEN
    v_serie := jsonb_build_object('id', v.id, 'motivo', v.motivo, 'tipo', mypump_presion_tipo_serie(v.motivo), 'estado', v.estado, 'tomas_objetivo', v.tomas_objetivo,
      'fecha_inicio', v.fecha_inicio, 'fecha_limite', v.fecha_limite, 'brazo', v.brazo_elegido,
      'ortostatica', CASE WHEN v.incluye_ortostatica AND NOT EXISTS (SELECT 1 FROM mypump_presion_sesiones s WHERE s.serie_id = v.id AND s.tipo = 'ortostatica')
                          THEN COALESCE(v.variante_ortostatica, 'acostado_parado') END,
      'comparar_brazos', v.comparar_brazos AND NOT EXISTS (SELECT 1 FROM mypump_presion_sesiones s WHERE s.serie_id = v.id AND s.tipo = 'comparacion_brazos'),
      'medida_pedida', v.circunferencia_brazo_cm IS NULL,
      'dias', COALESCE(v.resumen->'dias', '[]'::JSONB), 'faltan', COALESCE((v.resumen->>'tomas_objetivo')::INTEGER - (v.resumen->>'tomas_validas')::INTEGER, v.tomas_objetivo));
  END IF;
  SELECT jsonb_build_object('sesion_id', s.id, 'nivel', CASE WHEN s.evaluacion->>'paso' = 'repetir_con_lista' THEN 'urgencia' ELSE 'alta' END,
                            'desde', (SELECT max(medido_en) FROM mypump_presion_tomas WHERE sesion_id = s.id)) INTO v_pend
  FROM mypump_presion_sesiones s WHERE s.cliente_id = p_cliente_id AND s.fecha = v_hoy AND s.evaluacion->>'paso' IN ('repetir', 'repetir_con_lista')
  ORDER BY s.inicio DESC LIMIT 1;
  RETURN jsonb_build_object(
    'habilitado', TRUE, 'fotos', FALSE, 'hoy', to_char(v_hoy, 'YYYY-MM-DD'), 'zona_horaria', v_zona,
    'aparato', CASE WHEN a.id IS NOT NULL THEN jsonb_build_object('id', a.id, 'tipo', a.tipo, 'marca', a.marca, 'modelo', a.modelo, 'modelo_codigo', a.modelo_codigo,
      'manguito_min_cm', a.manguito_min_cm, 'manguito_max_cm', a.manguito_max_cm, 'manguito_validado_min_cm', a.manguito_validado_min_cm,
      'manguito_validado_max_cm', a.manguito_validado_max_cm, 'validado', a.validado) END,
    'circunferencia_brazo_cm', (SELECT cm FROM mypump_presion_brazo WHERE cliente_id = p_cliente_id),
    'serie', v_serie,
    'sesiones', COALESCE((SELECT jsonb_agg(jsonb_build_object('id', s.id, 'serie_id', s.serie_id, 'fecha', to_char(s.fecha, 'YYYY-MM-DD'), 'tipo', s.tipo, 'cuenta', s.cuenta,
        'tomas', COALESCE((SELECT jsonb_agg(jsonb_build_object('orden', t.orden, 'posicion', t.posicion, 'sis', t.sistolica, 'dia', t.diastolica, 'pulso', t.pulso,
                           'latido_irregular', t.latido_irregular) ORDER BY t.orden) FROM mypump_presion_tomas t WHERE t.sesion_id = s.id), '[]'::JSONB)) ORDER BY s.inicio DESC)
      FROM (SELECT * FROM mypump_presion_sesiones WHERE cliente_id = p_cliente_id ORDER BY inicio DESC LIMIT 30) s), '[]'::JSONB),
    'pendiente', v_pend,
    'tensiometros', (SELECT jsonb_build_object('version', version, 'tramos', tramos) FROM mypump_presion_tensiometros WHERE id = 1));
END;
$$;

-- ══ La app, por token. NULL = token caído ══

CREATE OR REPLACE FUNCTION mypump_presion_get(p_token TEXT, p_zona TEXT DEFAULT NULL)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_cliente_id TEXT;
BEGIN
  v_cliente_id := mypump_get_cliente_id_from_token(p_token);
  IF v_cliente_id IS NULL THEN RETURN NULL; END IF;
  IF NOT mypump_presion_habilitado(v_cliente_id) THEN RETURN jsonb_build_object('habilitado', FALSE); END IF;
  PERFORM mypump_presion_barrer(v_cliente_id);
  RETURN mypump_presion_estado(v_cliente_id, p_zona);
END;
$$;

CREATE OR REPLACE FUNCTION mypump_presion_aparato(p_token TEXT, p_aparato JSONB)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_cliente_id TEXT; v_min NUMERIC; v_max NUMERIC; v_tipo TEXT := p_aparato->>'tipo';
BEGIN
  v_cliente_id := mypump_get_cliente_id_from_token(p_token);
  IF v_cliente_id IS NULL THEN RETURN NULL; END IF;
  IF NOT mypump_presion_habilitado(v_cliente_id) THEN RETURN jsonb_build_object('ok', FALSE, 'error', 'no_habilitado'); END IF;
  PERFORM pg_advisory_xact_lock(hashtext('mypump_presion:' || v_cliente_id));
  IF v_tipo IS NULL OR v_tipo NOT IN ('brazo', 'muneca', 'reloj_anillo_otro') THEN RETURN jsonb_build_object('ok', FALSE, 'error', 'datos'); END IF;
  IF char_length(COALESCE(p_aparato->>'marca', '')) > 80 OR char_length(COALESCE(p_aparato->>'modelo', '')) > 80 OR char_length(COALESCE(p_aparato->>'modelo_codigo', '')) > 80 THEN
    RETURN jsonb_build_object('ok', FALSE, 'error', 'datos');
  END IF;
  BEGIN
    v_min := round((p_aparato->>'manguito_min_cm')::NUMERIC, 1); v_max := round((p_aparato->>'manguito_max_cm')::NUMERIC, 1);
  EXCEPTION WHEN OTHERS THEN RETURN jsonb_build_object('ok', FALSE, 'error', 'datos'); END;
  IF (v_min IS NULL) <> (v_max IS NULL) OR v_min < 5 OR v_max > 80 OR v_min >= v_max THEN RETURN jsonb_build_object('ok', FALSE, 'error', 'datos'); END IF;
  -- Cambiar de aparato o de manguito es un aparato nuevo: la validación del anterior no se hereda.
  UPDATE mypump_presion_aparatos SET activo = FALSE, actualizado_en = NOW() WHERE cliente_id = v_cliente_id AND activo;
  INSERT INTO mypump_presion_aparatos (cliente_id, tipo, marca, modelo, modelo_codigo, manguito_min_cm, manguito_max_cm)
  VALUES (v_cliente_id, v_tipo, NULLIF(btrim(p_aparato->>'marca'), ''), NULLIF(btrim(p_aparato->>'modelo'), ''), NULLIF(btrim(p_aparato->>'modelo_codigo'), ''), v_min, v_max);
  RETURN jsonb_build_object('ok', TRUE, 'estado', mypump_presion_estado(v_cliente_id, NULL));
END;
$$;

CREATE OR REPLACE FUNCTION mypump_presion_medida(p_token TEXT, p_cm NUMERIC, p_zona TEXT DEFAULT NULL)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_cliente_id TEXT; v_cm NUMERIC := round(p_cm, 1); a mypump_presion_aparatos%ROWTYPE;
BEGIN
  v_cliente_id := mypump_get_cliente_id_from_token(p_token);
  IF v_cliente_id IS NULL THEN RETURN NULL; END IF;
  IF NOT mypump_presion_habilitado(v_cliente_id) THEN RETURN jsonb_build_object('ok', FALSE, 'error', 'no_habilitado'); END IF;
  PERFORM pg_advisory_xact_lock(hashtext('mypump_presion:' || v_cliente_id));
  IF v_cm IS NULL OR v_cm < 20 OR v_cm > 70 THEN RETURN jsonb_build_object('ok', FALSE, 'error', 'datos'); END IF;
  INSERT INTO mypump_presion_brazo (cliente_id, cm) VALUES (v_cliente_id, v_cm)
  ON CONFLICT (cliente_id) DO UPDATE SET cm = EXCLUDED.cm, medida_en = NOW();
  SELECT * INTO a FROM mypump_presion_aparatos WHERE cliente_id = v_cliente_id AND activo;
  -- La medida es de la serie abierta que todavía no la tiene: se pide de nuevo antes de cada serie.
  UPDATE mypump_presion_series SET circunferencia_brazo_cm = v_cm, circunferencia_medida_en = NOW(), manguito_calza = mypump_presion_calza(v_cm, a), actualizado_en = NOW()
   WHERE id = (SELECT id FROM mypump_presion_series WHERE cliente_id = v_cliente_id AND estado IN ('pendiente', 'en_curso') AND circunferencia_brazo_cm IS NULL
               ORDER BY (estado = 'en_curso') DESC, creado_en LIMIT 1);
  IF a.id IS NOT NULL THEN
    UPDATE mypump_presion_aparatos SET excepcion_brazo_mas_52 = (a.tipo = 'muneca' AND v_cm > 52), actualizado_en = NOW() WHERE id = a.id;
  END IF;
  RETURN jsonb_build_object('ok', TRUE, 'estado', mypump_presion_estado(v_cliente_id, p_zona));
END;
$$;

CREATE OR REPLACE FUNCTION mypump_presion_sesion(p_token TEXT, p_sesion JSONB)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_cliente_id TEXT; v_id UUID; v_serie_id UUID; v_tipo TEXT := p_sesion->>'tipo'; v_zona TEXT; v_inicio TIMESTAMPTZ; v_fecha DATE;
  a mypump_presion_aparatos%ROWTYPE; v mypump_presion_series%ROWTYPE; ya mypump_presion_sesiones%ROWTYPE;
  t JSONB; v_sint TEXT[]; v_medido TIMESTAMPTZ;
BEGIN
  v_cliente_id := mypump_get_cliente_id_from_token(p_token);
  IF v_cliente_id IS NULL THEN RETURN NULL; END IF;
  IF NOT mypump_presion_habilitado(v_cliente_id) THEN RETURN jsonb_build_object('ok', FALSE, 'error', 'no_habilitado'); END IF;
  PERFORM pg_advisory_xact_lock(hashtext('mypump_presion:' || v_cliente_id));
  BEGIN
    v_id := (p_sesion->>'id')::UUID; v_serie_id := (p_sesion->>'serie_id')::UUID; v_inicio := (p_sesion->>'inicio')::TIMESTAMPTZ;
  EXCEPTION WHEN OTHERS THEN RETURN jsonb_build_object('ok', FALSE, 'error', 'datos'); END;
  IF v_id IS NULL OR v_inicio IS NULL OR v_tipo IS NULL OR v_tipo NOT IN ('estandar', 'comparacion_brazos', 'ortostatica', 'bajo_efecto', 'suelta')
     OR jsonb_typeof(p_sesion->'tomas') IS DISTINCT FROM 'array' OR jsonb_array_length(p_sesion->'tomas') NOT BETWEEN 1 AND 4 THEN
    RETURN jsonb_build_object('ok', FALSE, 'error', 'datos');
  END IF;
  -- Un reloj adelantado o una toma que quedó días en la cola no se rechazan: una urgencia no se puede perder por eso.
  v_inicio := LEAST(NOW(), v_inicio);
  FOR t IN SELECT * FROM jsonb_array_elements(p_sesion->'tomas') LOOP
    IF jsonb_typeof(t->'sis') IS DISTINCT FROM 'number' OR jsonb_typeof(t->'dia') IS DISTINCT FROM 'number' OR jsonb_typeof(t->'pulso') IS DISTINCT FROM 'number'
       OR mypump_presion_validar((t->>'sis')::NUMERIC, (t->>'dia')::NUMERIC, (t->>'pulso')::NUMERIC) = 'imposible' THEN
      RETURN jsonb_build_object('ok', FALSE, 'error', 'imposible');
    END IF;
    IF jsonb_typeof(t->'orden') IS DISTINCT FROM 'number' OR (t->>'orden')::NUMERIC NOT IN (1, 2, 3, 4) OR COALESCE(t->>'posicion', 'sentado') NOT IN ('sentado', 'acostado', 'de_pie')
       OR COALESCE(t->>'brazo', 'izq') NOT IN ('izq', 'der') OR (jsonb_typeof(t->'minutos_de_pie') = 'number' AND (t->>'minutos_de_pie')::NUMERIC NOT IN (1, 3))
       OR jsonb_typeof(COALESCE(t->'minutos_de_pie', 'null'::JSONB)) NOT IN ('number', 'null') THEN
      RETURN jsonb_build_object('ok', FALSE, 'error', 'datos');
    END IF;
  END LOOP;
  v_sint := ARRAY(SELECT jsonb_array_elements_text(CASE WHEN jsonb_typeof(p_sesion->'sintomas') = 'array' THEN p_sesion->'sintomas' ELSE '[]'::JSONB END));
  IF NOT v_sint <@ ARRAY['dolor_pecho','falta_aire','cefalea_fuerte_nueva','cambios_vista','debilidad_un_lado','dificultad_hablar','confusion','desmayo','desmayo_en_esfuerzo',
                         'palpitaciones','mareo_al_pararse','vomitos_diarrea','otro']
     OR COALESCE(p_sesion->>'lista_espera', 'no') NOT IN ('si', 'no') OR char_length(COALESCE(p_sesion->>'nota', '')) > 500
     OR COALESCE(p_sesion->>'plataforma', 'ios') NOT IN ('ios', 'android', 'web') OR COALESCE(p_sesion->>'brazo', 'izq') NOT IN ('izq', 'der', 'ambos') THEN
    RETURN jsonb_build_object('ok', FALSE, 'error', 'datos');
  END IF;

  SELECT * INTO ya FROM mypump_presion_sesiones WHERE id = v_id FOR UPDATE;
  IF FOUND AND ya.cliente_id <> v_cliente_id THEN RETURN jsonb_build_object('ok', FALSE, 'error', 'datos'); END IF;
  IF ya.id IS NULL THEN
    SELECT * INTO a FROM mypump_presion_aparatos WHERE cliente_id = v_cliente_id AND activo;
    IF a.id IS NULL OR a.tipo = 'reloj_anillo_otro' THEN RETURN jsonb_build_object('ok', FALSE, 'error', 'aparato'); END IF;
    IF v_serie_id IS NOT NULL THEN
      IF NOT EXISTS (SELECT 1 FROM mypump_presion_series WHERE id = v_serie_id AND cliente_id = v_cliente_id) THEN
        RETURN jsonb_build_object('ok', FALSE, 'error', 'serie');   -- la serie no es suya
      END IF;
      SELECT * INTO v FROM mypump_presion_series WHERE id = v_serie_id AND cliente_id = v_cliente_id FOR UPDATE;
      -- Las guiadas (ortostática y comparación) entran también con la serie ya completa. Cualquier otra toma sobre una serie
      -- que cerró, venció o no puede abrirse queda como suelta: se guarda, se evalúa y deja sus avisos. Nunca se pierde.
      IF NOT (v.estado IN ('pendiente', 'en_curso') OR (v.estado = 'completa' AND v_tipo IN ('ortostatica', 'comparacion_brazos')))
         OR (v.estado = 'pendiente' AND EXISTS (SELECT 1 FROM mypump_presion_series WHERE cliente_id = v_cliente_id AND estado = 'en_curso')) THEN
        v := NULL; v_serie_id := NULL;
      END IF;
    END IF;
    IF v_serie_id IS NULL AND v_tipo = 'estandar' THEN v_tipo := 'suelta'; END IF;
    v_zona := mypump_presion_zona(p_sesion->>'zona_horaria');
    v_fecha := (v_inicio AT TIME ZONE v_zona)::DATE;
    BEGIN
      INSERT INTO mypump_presion_sesiones (id, cliente_id, serie_id, inicio, zona_horaria, fecha, momento, tipo, brazo, aparato_id, previo_cafeina, previo_fumo, previo_comida,
        previo_ejercicio, reposo_cumplido, temporizador_salteado, dosis_estimulante_hora, entreno_entre_dosis_y_toma, nota, app_version, plataforma, sintomas, lista_espera, texto_alumno)
      VALUES (v_id, v_cliente_id, v_serie_id, v_inicio, v_zona, v_fecha,
        CASE WHEN extract(hour FROM v_inicio AT TIME ZONE v_zona) >= 4 AND extract(hour FROM v_inicio AT TIME ZONE v_zona) < 12 THEN 'manana' ELSE 'otro' END,
        v_tipo, COALESCE(p_sesion->>'brazo', 'izq'), a.id, (p_sesion->'previo'->>'cafeina')::BOOLEAN, (p_sesion->'previo'->>'fumo')::BOOLEAN, (p_sesion->'previo'->>'comida')::BOOLEAN,
        (p_sesion->'previo'->>'ejercicio')::BOOLEAN, (p_sesion->>'reposo_cumplido')::BOOLEAN, (p_sesion->>'temporizador_salteado')::BOOLEAN,
        (p_sesion->>'dosis_estimulante_hora')::TIME, (p_sesion->>'entreno_entre_dosis_y_toma')::BOOLEAN, NULLIF(btrim(p_sesion->>'nota'), ''),
        left(p_sesion->>'app_version', 40), p_sesion->>'plataforma', v_sint, p_sesion->>'lista_espera', left(p_sesion->>'texto_alumno', 60));
    EXCEPTION WHEN data_exception OR check_violation THEN
      RETURN jsonb_build_object('ok', FALSE, 'error', 'datos');
    END;
    IF v.id IS NOT NULL AND v.estado = 'pendiente' THEN
      UPDATE mypump_presion_series SET estado = 'en_curso', fecha_inicio = v_fecha, fecha_limite = v_fecha + 6, zona_horaria = v_zona, aparato_id = a.id,
             manguito_calza = mypump_presion_calza(circunferencia_brazo_cm, a), actualizado_en = NOW() WHERE id = v.id;
    END IF;
  ELSE
    -- La sesión ya estaba: lo que contestó antes de medir no se pisa. Los síntomas se suman y un Sí de la lista no vuelve a No.
    UPDATE mypump_presion_sesiones SET sintomas = ARRAY(SELECT DISTINCT x FROM unnest(sintomas || v_sint) x ORDER BY 1),
           lista_espera = CASE WHEN lista_espera = 'si' OR p_sesion->>'lista_espera' = 'si' THEN 'si' ELSE COALESCE(p_sesion->>'lista_espera', lista_espera) END,
           texto_alumno = COALESCE(left(p_sesion->>'texto_alumno', 60), texto_alumno), actualizado_en = NOW() WHERE id = v_id;
  END IF;

  FOR t IN SELECT * FROM jsonb_array_elements(p_sesion->'tomas') LOOP
    BEGIN v_medido := LEAST(NOW(), (t->>'medido_en')::TIMESTAMPTZ); EXCEPTION WHEN OTHERS THEN v_medido := NULL; END;
    INSERT INTO mypump_presion_tomas (sesion_id, orden, posicion, minutos_de_pie, brazo, sistolica, diastolica, pulso, latido_irregular, medido_en, confirmada_por_alumno)
    VALUES (v_id, (t->>'orden')::NUMERIC::INTEGER, COALESCE(t->>'posicion', 'sentado'), (t->>'minutos_de_pie')::NUMERIC::INTEGER, t->>'brazo',
            (t->>'sis')::NUMERIC::INTEGER, (t->>'dia')::NUMERIC::INTEGER, (t->>'pulso')::NUMERIC::INTEGER,
            t->'latido_irregular' = 'true'::JSONB, COALESCE(v_medido, NOW()), t->'confirmada_por_alumno' = 'true'::JSONB)
    ON CONFLICT (sesion_id, orden) DO NOTHING;
  END LOOP;
  IF cardinality(v_sint) > 0 OR p_sesion->>'lista_espera' IS NOT NULL THEN
    INSERT INTO mypump_presion_sintomas (id, cliente_id, marcado_en, zona_horaria, sesion_id, contexto, sin_sintomas_en_lista, codigos, de_alarma)
    VALUES (v_id, v_cliente_id, NOW(), left(p_sesion->>'zona_horaria', 64), v_id,
            CASE WHEN p_sesion->>'lista_espera' IS NOT NULL THEN 'espera_180_120' WHEN v_tipo = 'ortostatica' THEN 'ortostatica' ELSE 'en_toma' END,
            CASE WHEN p_sesion->>'lista_espera' IS NOT NULL THEN p_sesion->>'lista_espera' = 'no' AND cardinality(v_sint) = 0 END, v_sint,
            v_sint && ARRAY['dolor_pecho','falta_aire','cefalea_fuerte_nueva','cambios_vista','debilidad_un_lado','dificultad_hablar','confusion','desmayo','desmayo_en_esfuerzo'])
    ON CONFLICT (id) DO UPDATE SET codigos = ARRAY(SELECT DISTINCT x FROM unnest(mypump_presion_sintomas.codigos || EXCLUDED.codigos) x ORDER BY 1),
      de_alarma = mypump_presion_sintomas.de_alarma OR EXCLUDED.de_alarma, contexto = EXCLUDED.contexto,
      sin_sintomas_en_lista = EXCLUDED.sin_sintomas_en_lista AND NOT (mypump_presion_sintomas.de_alarma OR EXCLUDED.de_alarma)
      WHERE mypump_presion_sintomas.cliente_id = EXCLUDED.cliente_id;
  END IF;
  PERFORM mypump_presion_recalcular(v_id);
  -- La comparación de brazos deja la diferencia en la serie (izquierda menos derecha, promedio de cada lado).
  IF v_tipo = 'comparacion_brazos' AND COALESCE(ya.serie_id, v_serie_id) IS NOT NULL THEN
    UPDATE mypump_presion_series SET diferencia_brazos_mmhg = d.dif, actualizado_en = NOW()
    FROM (SELECT round(avg(sistolica) FILTER (WHERE brazo = 'izq') - avg(sistolica) FILTER (WHERE brazo = 'der'))::INTEGER dif FROM mypump_presion_tomas WHERE sesion_id = v_id) d
    WHERE id = COALESCE(ya.serie_id, v_serie_id) AND d.dif IS NOT NULL;
  END IF;
  RETURN jsonb_build_object('ok', TRUE, 'estado', mypump_presion_estado(v_cliente_id, p_sesion->>'zona_horaria'));
END;
$$;

CREATE OR REPLACE FUNCTION mypump_presion_sintoma(p_token TEXT, p_sintoma JSONB)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_cliente_id TEXT; v_id UUID; v_sesion UUID; v_cod TEXT[]; v_ctx TEXT := COALESCE(p_sintoma->>'contexto', 'boton'); v_alarma BOOLEAN; v_nuevo BOOLEAN;
  v_marcado TIMESTAMPTZ;
BEGIN
  v_cliente_id := mypump_get_cliente_id_from_token(p_token);
  IF v_cliente_id IS NULL THEN RETURN NULL; END IF;
  IF NOT mypump_presion_habilitado(v_cliente_id) THEN RETURN jsonb_build_object('ok', FALSE, 'error', 'no_habilitado'); END IF;
  PERFORM pg_advisory_xact_lock(hashtext('mypump_presion:' || v_cliente_id));
  BEGIN v_id := (p_sintoma->>'id')::UUID; v_sesion := (p_sintoma->>'sesion_id')::UUID;
  EXCEPTION WHEN OTHERS THEN RETURN jsonb_build_object('ok', FALSE, 'error', 'datos'); END;
  v_cod := ARRAY(SELECT jsonb_array_elements_text(CASE WHEN jsonb_typeof(p_sintoma->'codigos') = 'array' THEN p_sintoma->'codigos' ELSE '[]'::JSONB END));
  IF v_id IS NULL OR v_ctx NOT IN ('boton', 'recordatorio_180_120') OR char_length(COALESCE(p_sintoma->>'nota', '')) > 500
     OR NOT v_cod <@ ARRAY['dolor_pecho','falta_aire','cefalea_fuerte_nueva','cambios_vista','debilidad_un_lado','dificultad_hablar','confusion','desmayo','desmayo_en_esfuerzo',
                           'palpitaciones','mareo_al_pararse','vomitos_diarrea','otro']
     THEN
    RETURN jsonb_build_object('ok', FALSE, 'error', 'datos');
  END IF;
  -- La sesión puede no haber llegado nunca (marcó el síntoma antes de la primera toma): el síntoma se guarda igual, suelto.
  IF v_sesion IS NOT NULL AND NOT EXISTS (SELECT 1 FROM mypump_presion_sesiones WHERE id = v_sesion AND cliente_id = v_cliente_id) THEN v_sesion := NULL; END IF;
  -- La hora es la del teléfono (pudo quedar horas sin señal), nunca del futuro.
  BEGIN v_marcado := LEAST(NOW(), (p_sintoma->>'marcado_en')::TIMESTAMPTZ); EXCEPTION WHEN OTHERS THEN v_marcado := NULL; END;
  v_alarma := v_cod && ARRAY['dolor_pecho','falta_aire','cefalea_fuerte_nueva','cambios_vista','debilidad_un_lado','dificultad_hablar','confusion','desmayo','desmayo_en_esfuerzo'];
  INSERT INTO mypump_presion_sintomas (id, cliente_id, marcado_en, zona_horaria, sesion_id, contexto, sin_sintomas_en_lista, codigos, de_alarma, nota)
  VALUES (v_id, v_cliente_id, COALESCE(v_marcado, NOW()), left(p_sintoma->>'zona_horaria', 64), v_sesion, v_ctx,
          CASE WHEN v_ctx = 'recordatorio_180_120' THEN p_sintoma->'sin_sintomas_en_lista' = 'true'::JSONB AND cardinality(v_cod) = 0 END, v_cod, v_alarma, NULLIF(btrim(p_sintoma->>'nota'), ''))
  ON CONFLICT (id) DO NOTHING;
  GET DIAGNOSTICS v_nuevo = ROW_COUNT;
  IF NOT v_nuevo AND NOT EXISTS (SELECT 1 FROM mypump_presion_sintomas WHERE id = v_id AND cliente_id = v_cliente_id) THEN RETURN jsonb_build_object('ok', FALSE, 'error', 'datos'); END IF;
  IF v_nuevo THEN
    IF v_alarma THEN PERFORM mypump_presion_aviso_nuevo(v_cliente_id, 'sintoma_alarma', 'sintoma', v_id, jsonb_build_object('codigos', to_jsonb(v_cod), 'contexto', v_ctx, 'marcado_en', COALESCE(v_marcado, NOW())), 'guardia_sintomas', TRUE, NULL); END IF;
    IF v_cod && ARRAY['desmayo', 'desmayo_en_esfuerzo'] THEN PERFORM mypump_presion_aviso_nuevo(v_cliente_id, 'desmayo', 'sintoma', v_id, jsonb_build_object('codigos', to_jsonb(v_cod)), 'guardia_sintomas', TRUE, NULL); END IF;
    IF 'mareo_al_pararse' = ANY (v_cod) THEN PERFORM mypump_presion_aviso_nuevo(v_cliente_id, 'sintomas_al_pararse', 'sintoma', v_id, jsonb_build_object('codigos', to_jsonb(v_cod)), 'ninguno', TRUE, NULL); END IF;
    IF v_cod && ARRAY['vomitos_diarrea', 'palpitaciones', 'otro'] AND NOT v_alarma THEN PERFORM mypump_presion_aviso_nuevo(v_cliente_id, 'sintoma_marcado', 'sintoma', v_id, jsonb_build_object('codigos', to_jsonb(v_cod)), 'ninguno', TRUE, NULL); END IF;
  END IF;
  RETURN jsonb_build_object('ok', TRUE);
END;
$$;

-- ══ El equipo y las otras sesiones (service_role). Ver presion/INTERFAZ.md ══

-- Pide una serie. `p_opciones`: requisito_pre_entrega, regla_codigo, brazo, comparar_brazos, motivos_ortostatica, variante_ortostatica, serie_basal_id, pausa_estimulantes_id.
CREATE OR REPLACE FUNCTION mypump_presion_serie_pedir(p_cliente_id TEXT, p_motivo TEXT, p_pedida_por TEXT, p_opciones JSONB DEFAULT '{}'::JSONB)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_id UUID; v_mot TEXT[] := ARRAY(SELECT jsonb_array_elements_text(CASE WHEN jsonb_typeof(p_opciones->'motivos_ortostatica') = 'array' THEN p_opciones->'motivos_ortostatica' ELSE '[]'::JSONB END));
BEGIN
  IF NOT EXISTS (SELECT 1 FROM mypump_clientes WHERE cliente_id = p_cliente_id) THEN RETURN jsonb_build_object('ok', FALSE, 'error', 'cliente'); END IF;
  -- Dos series abiertas del mismo motivo no: se devuelve la que ya está.
  SELECT id INTO v_id FROM mypump_presion_series WHERE cliente_id = p_cliente_id AND motivo = p_motivo AND estado IN ('pendiente', 'en_curso');
  IF FOUND THEN RETURN jsonb_build_object('ok', TRUE, 'ya', TRUE, 'id', v_id); END IF;
  INSERT INTO mypump_presion_series (cliente_id, motivo, pedida_por, regla_codigo, requisito_pre_entrega, tomas_objetivo, incluye_ortostatica, motivos_ortostatica, variante_ortostatica,
    comparar_brazos, brazo_elegido, serie_basal_id, pausa_estimulantes_id)
  VALUES (p_cliente_id, p_motivo, p_pedida_por, p_opciones->>'regla_codigo', (p_opciones->>'requisito_pre_entrega')::BOOLEAN IS TRUE,
    CASE WHEN p_motivo = 'ortostatica_suelta' THEN 1 ELSE 3 END, cardinality(v_mot) > 0, v_mot,
    CASE WHEN cardinality(v_mot) > 0 THEN COALESCE(p_opciones->>'variante_ortostatica', 'acostado_parado') END,
    (p_opciones->>'comparar_brazos')::BOOLEAN IS TRUE, COALESCE(p_opciones->>'brazo', 'izq'), (p_opciones->>'serie_basal_id')::UUID, (p_opciones->>'pausa_estimulantes_id')::UUID)
  RETURNING id INTO v_id;
  RETURN jsonb_build_object('ok', TRUE, 'ya', FALSE, 'id', v_id);
END;
$$;

CREATE OR REPLACE FUNCTION mypump_presion_serie_cancelar(p_serie_id UUID, p_por TEXT)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF length(btrim(COALESCE(p_por, ''))) = 0 THEN RAISE EXCEPTION 'falta quién' USING ERRCODE = '22023'; END IF;
  UPDATE mypump_presion_series SET estado = 'cancelada', regla_codigo = COALESCE(regla_codigo || ' · ', '') || 'cancelada por ' || p_por, actualizado_en = NOW()
   WHERE id = p_serie_id AND estado IN ('pendiente', 'en_curso');
  RETURN jsonb_build_object('ok', FOUND);
END;
$$;

-- El equipo revisa el aparato en STRIDE BP y carga lo validado (TENSIOMETROS.md §5). Solo toca los campos que vienen.
CREATE OR REPLACE FUNCTION mypump_presion_aparato_validar(p_aparato_id UUID, p_datos JSONB, p_por TEXT)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF length(btrim(COALESCE(p_por, ''))) = 0 OR COALESCE(p_datos->>'validado', 'si') NOT IN ('si', 'no', 'sin_revisar') THEN RAISE EXCEPTION 'datos' USING ERRCODE = '22023'; END IF;
  UPDATE mypump_presion_aparatos SET
    validado = COALESCE(p_datos->>'validado', validado), validado_fuente = COALESCE(p_datos->>'validado_fuente', validado_fuente),
    modelo_codigo = COALESCE(p_datos->>'modelo_codigo', modelo_codigo),
    manguito_min_cm = COALESCE((p_datos->>'manguito_min_cm')::NUMERIC, manguito_min_cm), manguito_max_cm = COALESCE((p_datos->>'manguito_max_cm')::NUMERIC, manguito_max_cm),
    manguito_validado_min_cm = COALESCE((p_datos->>'manguito_validado_min_cm')::NUMERIC, manguito_validado_min_cm),
    manguito_validado_max_cm = COALESCE((p_datos->>'manguito_validado_max_cm')::NUMERIC, manguito_validado_max_cm),
    manguito_validado_fuente = COALESCE(p_datos->>'manguito_validado_fuente', manguito_validado_fuente),
    manguito_validado_pmid = COALESCE(p_datos->>'manguito_validado_pmid', manguito_validado_pmid),
    manguito_talle = COALESCE(p_datos->>'manguito_talle', manguito_talle),
    validado_talle_manguito = COALESCE((p_datos->>'validado_talle_manguito')::BOOLEAN, validado_talle_manguito),
    tiene_memoria = COALESCE((p_datos->>'tiene_memoria')::BOOLEAN, tiene_memoria), tiene_bluetooth = COALESCE((p_datos->>'tiene_bluetooth')::BOOLEAN, tiene_bluetooth),
    detecta_arritmia = COALESCE((p_datos->>'detecta_arritmia')::BOOLEAN, detecta_arritmia),
    validado_por = p_por, validado_en = NOW(), actualizado_en = NOW()
  WHERE id = p_aparato_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', FALSE, 'error', 'aparato'); END IF;
  UPDATE mypump_presion_series s SET manguito_calza = mypump_presion_calza(s.circunferencia_brazo_cm, a), actualizado_en = NOW()
    FROM mypump_presion_aparatos a WHERE a.id = p_aparato_id AND s.aparato_id = a.id AND s.estado IN ('pendiente', 'en_curso');
  PERFORM mypump_presion_recalcular_serie(id) FROM mypump_presion_series WHERE aparato_id = p_aparato_id AND estado IN ('pendiente', 'en_curso');
  RETURN jsonb_build_object('ok', TRUE);
END;
$$;

-- Comparación en consultorio: 3 pares alternados. Positivo = el de casa da más. Más de 10 mmHg de diferencia media, en la
-- sistólica o en la diastólica, con muñeca: queda solo para urgencias (PROTOCOLO §4.3 y §7.2 punto 5).
CREATE OR REPLACE FUNCTION mypump_presion_comparacion_cargar(p_aparato_id UUID, p_datos JSONB, p_por TEXT)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  a mypump_presion_aparatos%ROWTYPE; v_ds NUMERIC; v_dd NUMERIC; v_mas BOOLEAN; v_id UUID;
BEGIN
  SELECT * INTO a FROM mypump_presion_aparatos WHERE id = p_aparato_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', FALSE, 'error', 'aparato'); END IF;
  IF length(btrim(COALESCE(p_por, ''))) = 0 OR jsonb_typeof(p_datos->'pares') IS DISTINCT FROM 'array' OR jsonb_array_length(p_datos->'pares') <> 3
     OR EXISTS (SELECT 1 FROM jsonb_array_elements(p_datos->'pares') x WHERE mypump_presion_validar((x->>'consultorio_sis')::NUMERIC, (x->>'consultorio_dia')::NUMERIC, 60) = 'imposible'
                                                                           OR mypump_presion_validar((x->>'casa_sis')::NUMERIC, (x->>'casa_dia')::NUMERIC, 60) = 'imposible') THEN
    RAISE EXCEPTION 'datos' USING ERRCODE = '22023';
  END IF;
  SELECT round(avg((x->>'casa_sis')::NUMERIC - (x->>'consultorio_sis')::NUMERIC), 1), round(avg((x->>'casa_dia')::NUMERIC - (x->>'consultorio_dia')::NUMERIC), 1)
    INTO v_ds, v_dd FROM jsonb_array_elements(p_datos->'pares') x;
  v_mas := abs(v_ds) > 10 OR abs(v_dd) > 10;
  INSERT INTO mypump_presion_comparaciones (cliente_id, aparato_id, motivo, fecha, circunferencia_brazo_cm, manguito_referencia, pares, dif_media_sis, dif_media_dia, mas_de_10, solo_urgencias, cargada_por)
  VALUES (a.cliente_id, a.id, p_datos->>'motivo', (p_datos->>'fecha')::DATE, (p_datos->>'circunferencia_brazo_cm')::NUMERIC, p_datos->>'manguito_referencia', p_datos->'pares',
          v_ds, v_dd, v_mas, v_mas AND a.tipo = 'muneca', p_por)
  RETURNING id INTO v_id;
  PERFORM mypump_presion_recalcular_serie(id) FROM mypump_presion_series WHERE aparato_id = p_aparato_id AND estado IN ('pendiente', 'en_curso', 'completa');
  RETURN jsonb_build_object('ok', TRUE, 'id', v_id, 'dif_media_sis', v_ds, 'dif_media_dia', v_dd, 'mas_de_10', v_mas, 'solo_urgencias', v_mas AND a.tipo = 'muneca');
END;
$$;

-- Lo que leen el brief, Entregas y Ateneo. Sin tomas dice que no hay: nunca «normal».
CREATE OR REPLACE FUNCTION mypump_presion_para_brief(p_cliente_id TEXT)
RETURNS JSONB LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT jsonb_build_object(
    'tiene_tomas', EXISTS (SELECT 1 FROM mypump_presion_sesiones WHERE cliente_id = p_cliente_id),
    'series', COALESCE((SELECT jsonb_agg(jsonb_build_object('id', s.id, 'motivo', s.motivo, 'estado', s.estado, 'pedida_por', s.pedida_por, 'requisito_pre_entrega', s.requisito_pre_entrega,
                          'creada_en', s.creado_en, 'resumen', s.resumen) ORDER BY s.creado_en DESC)
                        FROM (SELECT * FROM mypump_presion_series WHERE cliente_id = p_cliente_id AND estado <> 'cancelada' ORDER BY creado_en DESC LIMIT 6) s), '[]'::JSONB),
    -- Requisito para agendar la entrega o decidir la química. NUNCA para la rutina.
    'requisito_pre_entrega', (SELECT jsonb_build_object('pedido', count(*) > 0, 'cumplido', count(*) > 0 AND bool_and(estado = 'completa'),
                                'pendientes', COALESCE(jsonb_agg(motivo) FILTER (WHERE estado <> 'completa'), '[]'::JSONB))
                              FROM mypump_presion_series WHERE cliente_id = p_cliente_id AND requisito_pre_entrega AND estado <> 'cancelada' AND creado_en > NOW() - INTERVAL '60 days'),
    'avisos_abiertos', COALESCE((SELECT jsonb_agg(jsonb_build_object('id', w.id, 'nivel', w.nivel, 'regla', w.regla, 'es_alta', w.es_alta, 'valores', w.valores, 'creado_en', w.creado_en,
                                   'enviado_por_mati_en', w.enviado_por_mati_en) ORDER BY w.creado_en DESC)
                                 FROM mypump_presion_avisos w WHERE w.cliente_id = p_cliente_id AND w.cerrado_en IS NULL AND w.creado_en > NOW() - INTERVAL '90 days'), '[]'::JSONB),
    'pausa_estimulantes', (SELECT to_jsonb(pz) FROM mypump_presion_pausas pz WHERE pz.cliente_id = p_cliente_id AND pz.cerrado_en IS NULL),
    'aparato', (SELECT to_jsonb(a) - 'foto_aparato_path' - 'foto_etiqueta_path' FROM mypump_presion_aparatos a WHERE a.cliente_id = p_cliente_id AND a.activo),
    'circunferencia_brazo_cm', (SELECT cm FROM mypump_presion_brazo WHERE cliente_id = p_cliente_id));
$$;

-- La cola de Mensajes: urgencias primero. `brief` no entra: eso lo lee el brief.
CREATE OR REPLACE FUNCTION mypump_presion_avisos_pendientes(p_limite INTEGER DEFAULT 30)
RETURNS JSONB LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT COALESCE(jsonb_agg(to_jsonb(q) ORDER BY (q.nivel = 'urgencia') DESC, q.creado_en), '[]'::JSONB)
  FROM (SELECT id, cliente_id, nivel, regla, es_alta, origen_tipo, origen_id, valores, texto_alumno, creado_en FROM mypump_presion_avisos
        WHERE enviado_a_mensajes_en IS NULL AND cerrado_en IS NULL AND nivel <> 'brief'
        ORDER BY (nivel = 'urgencia') DESC, creado_en LIMIT LEAST(GREATEST(p_limite, 1), 200)) q;
$$;

-- Mensajes marca lo que hizo con un aviso. `p_cambios`: tomado (bool), mensaje_borrador, enviado_por_mati (bool), cerrar {por, nota}.
CREATE OR REPLACE FUNCTION mypump_presion_aviso_marcar(p_id UUID, p_cambios JSONB)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  UPDATE mypump_presion_avisos SET
    enviado_a_mensajes_en = CASE WHEN (p_cambios->>'tomado')::BOOLEAN IS TRUE THEN COALESCE(enviado_a_mensajes_en, NOW()) ELSE enviado_a_mensajes_en END,
    mensaje_borrador = COALESCE(p_cambios->>'mensaje_borrador', mensaje_borrador),
    enviado_por_mati_en = CASE WHEN (p_cambios->>'enviado_por_mati')::BOOLEAN IS TRUE THEN COALESCE(enviado_por_mati_en, NOW()) ELSE enviado_por_mati_en END,
    cerrado_en = CASE WHEN p_cambios ? 'cerrar' THEN COALESCE(cerrado_en, NOW()) ELSE cerrado_en END,
    cerrado_por = COALESCE(p_cambios->'cerrar'->>'por', cerrado_por), nota_mati = COALESCE(p_cambios->'cerrar'->>'nota', nota_mati)
  WHERE id = p_id;
  RETURN jsonb_build_object('ok', FOUND);
END;
$$;

-- La pausa de estimulantes la abre Mensajes cuando una alta cae en alguien con estimulantes en el plan (el servidor no conoce el plan).
CREATE OR REPLACE FUNCTION mypump_presion_pausa_abrir(p_aviso_id UUID, p_criterio TEXT, p_estimulantes TEXT[], p_pedido_editor TEXT DEFAULT NULL)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  w mypump_presion_avisos%ROWTYPE; v_id UUID;
BEGIN
  SELECT * INTO w FROM mypump_presion_avisos WHERE id = p_aviso_id;
  IF NOT FOUND OR NOT w.es_alta THEN RETURN jsonb_build_object('ok', FALSE, 'error', 'aviso'); END IF;
  SELECT id INTO v_id FROM mypump_presion_pausas WHERE cliente_id = w.cliente_id AND cerrado_en IS NULL;
  IF FOUND THEN RETURN jsonb_build_object('ok', TRUE, 'ya', TRUE, 'id', v_id); END IF;
  INSERT INTO mypump_presion_pausas (cliente_id, aviso_id, criterio, valores, estimulantes, pedido_editor_texto, pedido_editor_en)
  VALUES (w.cliente_id, w.id, p_criterio, w.valores, COALESCE(p_estimulantes, '{}'), p_pedido_editor, CASE WHEN p_pedido_editor IS NOT NULL THEN NOW() END)
  RETURNING id INTO v_id;
  UPDATE mypump_presion_avisos SET pausa_estimulantes_id = v_id WHERE id = w.id;
  RETURN jsonb_build_object('ok', TRUE, 'ya', FALSE, 'id', v_id);
END;
$$;

-- `p_cambios`: editor_estado, mensaje_borrador, enviado_por_mati (bool), serie_control_id, reanudar ('si'|'no'; cierra la pausa).
CREATE OR REPLACE FUNCTION mypump_presion_pausa_actualizar(p_id UUID, p_cambios JSONB)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  UPDATE mypump_presion_pausas SET
    editor_estado = COALESCE(p_cambios->>'editor_estado', editor_estado),
    editor_revisado_en = CASE WHEN p_cambios ? 'editor_estado' THEN NOW() ELSE editor_revisado_en END,
    mensaje_borrador = COALESCE(p_cambios->>'mensaje_borrador', mensaje_borrador),
    enviado_por_mati_en = CASE WHEN (p_cambios->>'enviado_por_mati')::BOOLEAN IS TRUE THEN COALESCE(enviado_por_mati_en, NOW()) ELSE enviado_por_mati_en END,
    serie_control_id = COALESCE((p_cambios->>'serie_control_id')::UUID, serie_control_id),
    reanudar = COALESCE(p_cambios->>'reanudar', reanudar),
    reanudar_decidido_en = CASE WHEN p_cambios->>'reanudar' IN ('si', 'no') THEN NOW() ELSE reanudar_decidido_en END,
    cerrado_en = CASE WHEN p_cambios->>'reanudar' IN ('si', 'no') THEN COALESCE(cerrado_en, NOW()) ELSE cerrado_en END
  WHERE id = p_id;
  RETURN jsonb_build_object('ok', FOUND);
END;
$$;

-- ── Permisos: lo interno no se llama desde afuera; lo del equipo, solo service_role; lo de la app, por token ──
REVOKE ALL ON FUNCTION mypump_presion_habilitado(TEXT), mypump_presion_zona(TEXT), mypump_presion_tipo_serie(TEXT), mypump_presion_calza(NUMERIC, mypump_presion_aparatos),
  mypump_presion_sesion_json(mypump_presion_sesiones, TIMESTAMPTZ), mypump_presion_aviso_nuevo(TEXT, TEXT, TEXT, UUID, JSONB, TEXT, BOOLEAN, INTEGER),
  mypump_presion_recalcular_serie(UUID, TIMESTAMPTZ), mypump_presion_recalcular(UUID, TIMESTAMPTZ), mypump_presion_estado(TEXT, TEXT)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION mypump_presion_barrer(TEXT), mypump_presion_serie_pedir(TEXT, TEXT, TEXT, JSONB), mypump_presion_serie_cancelar(UUID, TEXT),
  mypump_presion_aparato_validar(UUID, JSONB, TEXT), mypump_presion_comparacion_cargar(UUID, JSONB, TEXT), mypump_presion_para_brief(TEXT),
  mypump_presion_avisos_pendientes(INTEGER), mypump_presion_aviso_marcar(UUID, JSONB), mypump_presion_pausa_abrir(UUID, TEXT, TEXT[], TEXT),
  mypump_presion_pausa_actualizar(UUID, JSONB) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION mypump_presion_barrer(TEXT), mypump_presion_serie_pedir(TEXT, TEXT, TEXT, JSONB), mypump_presion_serie_cancelar(UUID, TEXT),
  mypump_presion_aparato_validar(UUID, JSONB, TEXT), mypump_presion_comparacion_cargar(UUID, JSONB, TEXT), mypump_presion_para_brief(TEXT),
  mypump_presion_avisos_pendientes(INTEGER), mypump_presion_aviso_marcar(UUID, JSONB), mypump_presion_pausa_abrir(UUID, TEXT, TEXT[], TEXT),
  mypump_presion_pausa_actualizar(UUID, JSONB) TO service_role;
REVOKE ALL ON FUNCTION mypump_presion_get(TEXT, TEXT), mypump_presion_aparato(TEXT, JSONB), mypump_presion_medida(TEXT, NUMERIC, TEXT),
  mypump_presion_sesion(TEXT, JSONB), mypump_presion_sintoma(TEXT, JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION mypump_presion_get(TEXT, TEXT), mypump_presion_aparato(TEXT, JSONB), mypump_presion_medida(TEXT, NUMERIC, TEXT),
  mypump_presion_sesion(TEXT, JSONB), mypump_presion_sintoma(TEXT, JSONB) TO anon, authenticated, service_role;

NOTIFY pgrst, 'reload schema';
COMMIT;
