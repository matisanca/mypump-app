-- nativa_contrato_firma.sql — PROPUESTA, SIN APLICAR.
--
-- «Firma propia»: reemplaza a BoldSign para las altas nuevas. Dos documentos separados, como hoy: el contrato de
-- servicio (solo si hay farmacología) y el consentimiento médico (solo Argentina). Los textos vigentes se cargan tal
-- cual, por versión, y no se editan nunca.
--
-- Orden de despliegue (ver pump-firma/RUNBOOK.md): 1) este SQL, 2) cargar las plantillas, 3) el servicio pump-firma en
-- la Mini, 4) el túnel, 5) el Apps Script. Mientras el Apps Script siga llamando a BoldSign, nada de esto se usa.
--
-- Invariantes:
--   · Todo vive en el esquema `contrato`, que PostgREST no expone. `anon` y `authenticated` no tienen ningún permiso.
--     Las dos únicas puertas en `public` son de lectura: `contrato_estado` (service_role) y `mypump_contrato_get` (token de la app).
--   · El servicio trabaja como `firma_srv`: solo EXECUTE sobre las funciones. No puede hacer UPDATE ni DELETE a mano.
--   · `contrato.eventos` y `contrato.sellos` solo agregan. Cada evento guarda el hash del anterior (cadena), y el último
--     hash se sella afuera (RFC 3161): el disparador protege de errores propios; la prueba ante terceros es el sello.
--   · Los hashes SHA-256 de las plantillas los calcula la base; los de los PDF, el servidor. Nunca el teléfono.
--   · La fecha de firma la pone el servidor. Un documento firmado no se anula ni se reemplaza.
--   · Nada se borra: tampoco al borrar la cuenta de la app (conservación legal; consentimiento médico, 10 años).
BEGIN;

CREATE SCHEMA IF NOT EXISTS contrato;
REVOKE ALL ON SCHEMA contrato FROM PUBLIC;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'firma_srv') THEN
    CREATE ROLE firma_srv NOLOGIN;
  END IF;
END $$;
-- La conexión del servicio hace `SET LOCAL ROLE firma_srv` al abrir cada transacción.
DO $$
BEGIN
  -- Desde Postgres 16, quien crea un rol lo administra pero no puede «ponérselo» si no se lo concede con SET.
  IF NOT pg_has_role(current_user, 'firma_srv', 'SET') THEN
    EXECUTE format('GRANT firma_srv TO %I WITH SET TRUE, INHERIT FALSE', current_user);
  END IF;
END $$;
GRANT USAGE ON SCHEMA contrato TO firma_srv;

-- ── Plantillas: el texto exacto, por versión ──
CREATE TABLE contrato.plantillas (
  id            TEXT PRIMARY KEY,
  tipo          TEXT NOT NULL CHECK (tipo IN ('servicio_ar', 'servicio_ext', 'consentimiento_ar')),
  version       TEXT NOT NULL,
  titulo        TEXT NOT NULL,
  fuente_md     TEXT NOT NULL,
  fuente_sha256 TEXT NOT NULL,
  fuente_md5    TEXT NOT NULL,
  vigente       BOOLEAN NOT NULL DEFAULT false,
  creado_en     TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (tipo, version),
  -- el hash lo calcula la base sobre el texto que guarda; quien carga la plantilla tiene que traer el mismo
  CHECK (fuente_sha256 = encode(sha256(convert_to(fuente_md, 'UTF8')), 'hex')),
  CHECK (fuente_md5 = md5(fuente_md))
);
CREATE UNIQUE INDEX plantillas_una_vigente ON contrato.plantillas (tipo) WHERE vigente;

CREATE FUNCTION contrato.plantillas_inmutables() RETURNS TRIGGER
LANGUAGE plpgsql SET search_path = contrato, pg_catalog AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'contrato.plantillas: una plantilla no se borra' USING ERRCODE = '42501';
  END IF;
  IF (NEW.id, NEW.tipo, NEW.version, NEW.titulo, NEW.fuente_md, NEW.fuente_sha256, NEW.fuente_md5, NEW.creado_en)
     IS DISTINCT FROM (OLD.id, OLD.tipo, OLD.version, OLD.titulo, OLD.fuente_md, OLD.fuente_sha256, OLD.fuente_md5, OLD.creado_en) THEN
    RAISE EXCEPTION 'contrato.plantillas: el texto de una versión no se edita; se carga una versión nueva' USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER plantillas_inmutables BEFORE UPDATE OR DELETE ON contrato.plantillas
  FOR EACH ROW EXECUTE FUNCTION contrato.plantillas_inmutables();

-- ── Documentos: uno por persona y por tipo ──
CREATE TABLE contrato.documentos (
  id                    UUID PRIMARY KEY,
  tipo                  TEXT NOT NULL CHECK (tipo IN ('servicio_ar', 'servicio_ext', 'consentimiento_ar')),
  plantilla_id          TEXT NOT NULL REFERENCES contrato.plantillas (id),
  alta_ref              TEXT NOT NULL CHECK (length(alta_ref) BETWEEN 8 AND 200),
  lead_id               BIGINT,
  firmante_nombre       TEXT NOT NULL CHECK (length(btrim(firmante_nombre)) > 0),
  firmante_email        TEXT NOT NULL CHECK (firmante_email ~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'),
  firmante_whatsapp     TEXT,
  pais                  TEXT,
  variante              TEXT NOT NULL CHECK (variante IN ('AR', 'ES', 'OTRO')),
  campos                JSONB NOT NULL,
  token_n               INTEGER NOT NULL DEFAULT 1,
  token_sha256          TEXT NOT NULL UNIQUE CHECK (token_sha256 ~ '^[0-9a-f]{64}$'),
  estado                TEXT NOT NULL DEFAULT 'pendiente' CHECK (estado IN ('pendiente', 'firmado', 'revocado', 'anulado')),
  pdf_base_path         TEXT NOT NULL,
  pdf_base_sha256       TEXT NOT NULL CHECK (pdf_base_sha256 ~ '^[0-9a-f]{64}$'),
  pdf_final_path        TEXT,
  pdf_final_sha256      TEXT CHECK (pdf_final_sha256 ~ '^[0-9a-f]{64}$'),
  firmado_en            TIMESTAMPTZ,
  firma                 JSONB,
  baja_pedida_en        TIMESTAMPTZ,
  baja_resuelta_en      TIMESTAMPTZ,
  baja_resultado        TEXT CHECK (baja_resultado IN ('sigue', 'terminado')),
  revocado_en           TIMESTAMPTZ,
  pdf_revocacion_path   TEXT,
  pdf_revocacion_sha256 TEXT CHECK (pdf_revocacion_sha256 ~ '^[0-9a-f]{64}$'),
  reemplaza             UUID REFERENCES contrato.documentos (id),
  creado_en             TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK ((estado IN ('firmado', 'revocado')) = (firmado_en IS NOT NULL AND pdf_final_sha256 IS NOT NULL AND pdf_final_path IS NOT NULL AND firma IS NOT NULL)),
  CHECK ((estado = 'revocado') = (revocado_en IS NOT NULL)),
  CHECK ((baja_resuelta_en IS NULL) = (baja_resultado IS NULL)),
  CHECK (baja_resuelta_en IS NULL OR baja_pedida_en IS NOT NULL),
  CHECK (estado <> 'revocado' OR tipo = 'consentimiento_ar'),
  CHECK (baja_pedida_en IS NULL OR (tipo <> 'consentimiento_ar' AND estado = 'firmado'))
);
-- Un solo documento vivo por alta y por tipo: el alta repetida devuelve el mismo.
CREATE UNIQUE INDEX documentos_uno_vivo ON contrato.documentos (alta_ref, tipo) WHERE estado <> 'anulado';
CREATE INDEX documentos_por_mail ON contrato.documentos (lower(firmante_email));
CREATE INDEX documentos_por_lead ON contrato.documentos (lead_id) WHERE lead_id IS NOT NULL;
CREATE INDEX documentos_por_wa ON contrato.documentos (right(regexp_replace(coalesce(firmante_whatsapp, ''), '\D', '', 'g'), 10));

-- ── Eventos: solo agrega, encadenados ──
CREATE TABLE contrato.eventos (
  n            BIGINT PRIMARY KEY,
  documento_id UUID REFERENCES contrato.documentos (id),
  tipo         TEXT NOT NULL CHECK (tipo ~ '^[a-z_]{3,40}$'),
  ts           TIMESTAMPTZ NOT NULL,
  ip           TEXT CHECK (ip !~ '[[:cntrl:]]'),
  user_agent   TEXT CHECK (user_agent !~ '[[:cntrl:]]'),
  datos        TEXT NOT NULL CHECK (datos !~ '[[:cntrl:]]' AND (datos::jsonb) IS NOT NULL),
  prev_hash    TEXT NOT NULL CHECK (prev_hash ~ '^[0-9a-f]{64}$'),
  hash         TEXT NOT NULL UNIQUE CHECK (hash ~ '^[0-9a-f]{64}$')
);
CREATE INDEX eventos_por_doc ON contrato.eventos (documento_id, n);

CREATE FUNCTION contrato.solo_agrega() RETURNS TRIGGER
LANGUAGE plpgsql SET search_path = contrato, pg_catalog AS $$
BEGIN
  RAISE EXCEPTION '%: esta tabla solo agrega (sin UPDATE, DELETE ni TRUNCATE)', TG_TABLE_NAME USING ERRCODE = '42501';
END $$;
CREATE TRIGGER eventos_solo_agrega BEFORE UPDATE OR DELETE ON contrato.eventos
  FOR EACH ROW EXECUTE FUNCTION contrato.solo_agrega();
CREATE TRIGGER eventos_sin_truncate BEFORE TRUNCATE ON contrato.eventos
  FOR EACH STATEMENT EXECUTE FUNCTION contrato.solo_agrega();

-- Un documento no se borra y su historia solo avanza: pendiente → firmado → revocado, o pendiente → anulado.
-- Lo que se firmó (datos, PDF, hashes, fechas) no se puede cambiar ni siquiera con el rol dueño sin quitar este trigger,
-- y quitarlo es una migración que queda a la vista.
CREATE FUNCTION contrato.documentos_guardia() RETURNS TRIGGER
LANGUAGE plpgsql SET search_path = contrato, pg_catalog AS $$
BEGIN
  IF TG_OP <> 'UPDATE' THEN
    RAISE EXCEPTION 'contrato.documentos: un documento no se borra' USING ERRCODE = '42501';
  END IF;
  IF (NEW.id, NEW.tipo, NEW.plantilla_id, NEW.alta_ref, NEW.firmante_nombre, NEW.firmante_email, NEW.firmante_whatsapp, NEW.pais,
      NEW.variante, NEW.campos, NEW.token_n, NEW.token_sha256, NEW.pdf_base_path, NEW.pdf_base_sha256, NEW.reemplaza, NEW.creado_en)
     IS DISTINCT FROM
     (OLD.id, OLD.tipo, OLD.plantilla_id, OLD.alta_ref, OLD.firmante_nombre, OLD.firmante_email, OLD.firmante_whatsapp, OLD.pais,
      OLD.variante, OLD.campos, OLD.token_n, OLD.token_sha256, OLD.pdf_base_path, OLD.pdf_base_sha256, OLD.reemplaza, OLD.creado_en) THEN
    RAISE EXCEPTION 'contrato.documentos: los datos con los que se generó el documento no se editan' USING ERRCODE = '42501';
  END IF;
  IF OLD.lead_id IS NOT NULL AND NEW.lead_id IS DISTINCT FROM OLD.lead_id THEN
    RAISE EXCEPTION 'contrato.documentos: el alta vinculada no se cambia' USING ERRCODE = '42501';
  END IF;
  IF NEW.estado <> OLD.estado AND NOT ((OLD.estado = 'pendiente' AND NEW.estado IN ('firmado', 'anulado'))
                                    OR (OLD.estado = 'firmado' AND NEW.estado = 'revocado')) THEN
    RAISE EXCEPTION 'contrato.documentos: no se pasa de % a %', OLD.estado, NEW.estado USING ERRCODE = '42501';
  END IF;
  IF OLD.estado IN ('firmado', 'revocado') AND (NEW.firmado_en, NEW.pdf_final_path, NEW.pdf_final_sha256, NEW.firma)
       IS DISTINCT FROM (OLD.firmado_en, OLD.pdf_final_path, OLD.pdf_final_sha256, OLD.firma) THEN
    RAISE EXCEPTION 'contrato.documentos: lo firmado no se edita' USING ERRCODE = '42501';
  END IF;
  IF OLD.estado = 'revocado' AND (NEW.revocado_en, NEW.pdf_revocacion_path, NEW.pdf_revocacion_sha256)
       IS DISTINCT FROM (OLD.revocado_en, OLD.pdf_revocacion_path, OLD.pdf_revocacion_sha256) THEN
    RAISE EXCEPTION 'contrato.documentos: la revocación no se edita' USING ERRCODE = '42501';
  END IF;
  IF OLD.baja_pedida_en IS NOT NULL AND NEW.baja_pedida_en IS DISTINCT FROM OLD.baja_pedida_en THEN
    RAISE EXCEPTION 'contrato.documentos: el pedido de baja no se edita' USING ERRCODE = '42501';
  END IF;
  IF OLD.baja_resuelta_en IS NOT NULL AND (NEW.baja_resuelta_en, NEW.baja_resultado) IS DISTINCT FROM (OLD.baja_resuelta_en, OLD.baja_resultado) THEN
    RAISE EXCEPTION 'contrato.documentos: la resolución de la baja no se edita' USING ERRCODE = '42501';
  END IF;
  IF OLD.estado = 'anulado' AND (NEW.firmado_en, NEW.baja_pedida_en, NEW.revocado_en) IS DISTINCT FROM (OLD.firmado_en, OLD.baja_pedida_en, OLD.revocado_en) THEN
    RAISE EXCEPTION 'contrato.documentos: un anulado no cambia' USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER documentos_guardia BEFORE UPDATE OR DELETE ON contrato.documentos
  FOR EACH ROW EXECUTE FUNCTION contrato.documentos_guardia();
CREATE TRIGGER documentos_sin_truncate BEFORE TRUNCATE ON contrato.documentos
  FOR EACH STATEMENT EXECUTE FUNCTION contrato.solo_agrega();

-- El texto exacto que entra al hash de un evento. Lo reproduce pump-firma/tools/verificar_cadena.py sin tocar la base.
CREATE FUNCTION contrato.evento_canon(p_prev TEXT, p_n BIGINT, p_doc UUID, p_tipo TEXT, p_ts TIMESTAMPTZ, p_ip TEXT, p_ua TEXT, p_datos TEXT)
RETURNS TEXT LANGUAGE sql IMMUTABLE SET search_path = pg_catalog AS $$
  SELECT p_prev || E'\n' || p_n::TEXT || E'\n' || coalesce(p_doc::TEXT, '') || E'\n' || p_tipo || E'\n'
      || to_char(p_ts AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"') || E'\n'
      || coalesce(p_ip, '') || E'\n' || coalesce(p_ua, '') || E'\n' || p_datos;
$$;

CREATE FUNCTION contrato.registrar_evento(p_doc UUID, p_tipo TEXT, p_ip TEXT, p_ua TEXT, p_datos TEXT, p_ts TIMESTAMPTZ DEFAULT NULL)
RETURNS TEXT LANGUAGE plpgsql SECURITY DEFINER SET search_path = contrato, pg_catalog AS $$
DECLARE
  v_prev TEXT; v_n BIGINT; v_hash TEXT;
  v_ts TIMESTAMPTZ := date_trunc('microseconds', coalesce(p_ts, clock_timestamp()));
  v_ip TEXT := nullif(left(regexp_replace(coalesce(p_ip, ''), '[[:cntrl:]]', ' ', 'g'), 80), '');
  v_ua TEXT := nullif(left(regexp_replace(coalesce(p_ua, ''), '[[:cntrl:]]', ' ', 'g'), 400), '');
  v_datos TEXT := coalesce(p_datos, '{}');
BEGIN
  -- una sola escritura a la vez: la cadena es una sola para toda la tabla
  PERFORM pg_advisory_xact_lock(74260011);
  SELECT e.hash, e.n INTO v_prev, v_n FROM contrato.eventos e ORDER BY e.n DESC LIMIT 1;
  v_prev := coalesce(v_prev, repeat('0', 64));
  v_n := coalesce(v_n, 0) + 1;
  v_hash := encode(sha256(convert_to(contrato.evento_canon(v_prev, v_n, p_doc, p_tipo, v_ts, v_ip, v_ua, v_datos), 'UTF8')), 'hex');
  INSERT INTO contrato.eventos (n, documento_id, tipo, ts, ip, user_agent, datos, prev_hash, hash)
  VALUES (v_n, p_doc, p_tipo, v_ts, v_ip, v_ua, v_datos, v_prev, v_hash);
  RETURN v_hash;
END $$;

-- Eventos que manda la página (abrió, llegó al final, casilla…): con tope por documento, para que nadie infle la cadena.
CREATE FUNCTION contrato.evento_de_pagina(p_doc UUID, p_tipo TEXT, p_ip TEXT, p_ua TEXT, p_datos TEXT)
RETURNS TEXT LANGUAGE plpgsql SECURITY DEFINER SET search_path = contrato, pg_catalog AS $$
DECLARE v_hora INTEGER; v_total INTEGER;
BEGIN
  IF p_tipo NOT IN ('abierto', 'fin_lectura', 'casilla', 'pdf_visto', 'identidad_escrita') THEN
    RAISE EXCEPTION 'evento de página no permitido: %', p_tipo USING ERRCODE = '22023';
  END IF;
  IF length(coalesce(p_datos, '')) > 2000 THEN
    RAISE EXCEPTION 'evento de página demasiado largo' USING ERRCODE = '22023';
  END IF;
  SELECT count(*) FILTER (WHERE ts > clock_timestamp() - interval '1 hour'), count(*)
    INTO v_hora, v_total FROM contrato.eventos WHERE documento_id = p_doc AND tipo = p_tipo;
  IF v_hora >= 40 OR v_total >= 400 THEN
    RETURN NULL;
  END IF;
  RETURN contrato.registrar_evento(p_doc, p_tipo, p_ip, p_ua, p_datos);
END $$;

-- ── Códigos de un solo uso (mail) ──
CREATE TABLE contrato.codigos (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  documento_id  UUID NOT NULL REFERENCES contrato.documentos (id),
  proposito     TEXT NOT NULL CHECK (proposito IN ('firma', 'revocacion', 'baja')),
  codigo_hmac   TEXT NOT NULL CHECK (codigo_hmac ~ '^[0-9a-f]{64}$'),
  email         TEXT NOT NULL,
  creado_en     TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
  vence_en      TIMESTAMPTZ NOT NULL,
  intentos      INTEGER NOT NULL DEFAULT 0,
  verificado_en TIMESTAMPTZ,
  usado_en      TIMESTAMPTZ,
  anulado       BOOLEAN NOT NULL DEFAULT false
);
CREATE INDEX codigos_por_doc ON contrato.codigos (documento_id, proposito, creado_en DESC);

-- ── Sellos de tiempo externos: solo agrega ──
CREATE TABLE contrato.sellos (
  id           BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  objeto       TEXT NOT NULL CHECK (objeto IN ('documento', 'revocacion', 'cadena')),
  documento_id UUID REFERENCES contrato.documentos (id),
  evento_n     BIGINT,
  sha256       TEXT NOT NULL CHECK (sha256 ~ '^[0-9a-f]{64}$'),
  tsa          TEXT NOT NULL,
  tsr          BYTEA NOT NULL,
  hora_sello   TIMESTAMPTZ,
  creado_en    TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
  UNIQUE (objeto, sha256, tsa)
);
CREATE TRIGGER sellos_solo_agrega BEFORE UPDATE OR DELETE ON contrato.sellos
  FOR EACH ROW EXECUTE FUNCTION contrato.solo_agrega();
CREATE TRIGGER sellos_sin_truncate BEFORE TRUNCATE ON contrato.sellos
  FOR EACH STATEMENT EXECUTE FUNCTION contrato.solo_agrega();

-- ── Correo: bandeja de salida con reintentos ──
CREATE TABLE contrato.correos (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  documento_id UUID REFERENCES contrato.documentos (id),
  tipo         TEXT NOT NULL CHECK (tipo IN ('invitacion', 'codigo', 'copia_firmado', 'copia_revocacion', 'acuse_baja', 'custodia', 'aviso_interno')),
  para         TEXT NOT NULL,
  estado       TEXT NOT NULL DEFAULT 'pendiente' CHECK (estado IN ('pendiente', 'enviado', 'fallo')),
  intentos     INTEGER NOT NULL DEFAULT 0,
  message_id   TEXT,
  respuesta    TEXT,
  tomado_en    TIMESTAMPTZ,
  proximo_en   TIMESTAMPTZ,   -- después de un fallo: cuándo se vuelve a intentar (espera creciente, hasta 30 min)
  creado_en    TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
  enviado_en   TIMESTAMPTZ
);
CREATE INDEX correos_pendientes ON contrato.correos (creado_en) WHERE estado <> 'enviado';

-- ── Avisos al bot y a Entregas: bandeja de salida con reintentos ──
CREATE TABLE contrato.avisos (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  documento_id UUID NOT NULL REFERENCES contrato.documentos (id),
  tipo         TEXT NOT NULL CHECK (tipo IN ('firmado', 'revocado', 'baja_pedida', 'correccion_datos', 'falla')),
  cuerpo       JSONB NOT NULL,
  estado       TEXT NOT NULL DEFAULT 'pendiente' CHECK (estado IN ('pendiente', 'enviado', 'fallo')),
  intentos     INTEGER NOT NULL DEFAULT 0,
  respuesta    TEXT,
  tomado_en    TIMESTAMPTZ,
  proximo_en   TIMESTAMPTZ,   -- después de un fallo: cuándo se vuelve a intentar (espera creciente, hasta 30 min)
  creado_en    TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
  enviado_en   TIMESTAMPTZ
);
CREATE INDEX avisos_pendientes ON contrato.avisos (creado_en) WHERE estado <> 'enviado';

-- ── Altas frenadas: el formulario llegó sin un dato obligatorio (en Argentina: plan, objetivo o precio) y el contrato
-- no se emitió. No se frena en silencio: queda acá, se avisa qué falta y se vuelve a avisar hasta que se resuelva. ──
CREATE TABLE contrato.altas_frenadas (
  alta_ref        TEXT PRIMARY KEY,
  tipo            TEXT NOT NULL CHECK (tipo IN ('servicio_ar', 'servicio_ext', 'consentimiento_ar')),
  nombre          TEXT,
  email           TEXT NOT NULL,
  whatsapp        TEXT,
  faltan          TEXT[] NOT NULL CHECK (cardinality(faltan) > 0),
  creado_en       TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
  visto_en        TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),   -- última vez que el formulario llegó incompleto
  avisos          INTEGER NOT NULL DEFAULT 0,
  ultimo_aviso_en TIMESTAMPTZ,
  tomado_en       TIMESTAMPTZ,
  respuesta       TEXT,
  resuelto_en     TIMESTAMPTZ,
  resultado       TEXT            -- 'emitido' (llegó completo y nació el contrato) o el motivo del descarte a mano
);
CREATE INDEX altas_frenadas_abiertas ON contrato.altas_frenadas (visto_en) WHERE resuelto_en IS NULL;

-- ── Autorización del prestador y del médico para estampar su firma: solo agrega ──
-- Sin una fila vigente, el renglón de su firma queda en blanco, como hoy.
CREATE TABLE contrato.autorizaciones (
  id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  rol         TEXT NOT NULL CHECK (rol IN ('prestador', 'medico')),
  tipo        TEXT NOT NULL CHECK (tipo IN ('servicio_ar', 'servicio_ext', 'consentimiento_ar')),
  quien       TEXT NOT NULL,
  firma_sha256 TEXT NOT NULL CHECK (firma_sha256 ~ '^[0-9a-f]{64}$'),
  constancia  TEXT NOT NULL,
  desde       TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
  retirada    BOOLEAN NOT NULL DEFAULT false
);
CREATE TRIGGER autorizaciones_sin_truncate BEFORE TRUNCATE ON contrato.autorizaciones
  FOR EACH STATEMENT EXECUTE FUNCTION contrato.solo_agrega();
CREATE TRIGGER autorizaciones_solo_agrega BEFORE UPDATE OR DELETE ON contrato.autorizaciones
  FOR EACH ROW EXECUTE FUNCTION contrato.solo_agrega();

-- ═════════════ Funciones del servicio ═════════════

CREATE FUNCTION contrato.ahora() RETURNS TIMESTAMPTZ
LANGUAGE sql SECURITY DEFINER SET search_path = pg_catalog AS $$ SELECT date_trunc('microseconds', clock_timestamp()); $$;

CREATE FUNCTION contrato.plantilla_vigente(p_tipo TEXT) RETURNS JSONB
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = contrato, pg_catalog AS $$
  SELECT to_jsonb(p) FROM contrato.plantillas p WHERE p.tipo = p_tipo AND p.vigente;
$$;

CREATE FUNCTION contrato.plantilla(p_id TEXT) RETURNS JSONB
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = contrato, pg_catalog AS $$
  SELECT to_jsonb(p) FROM contrato.plantillas p WHERE p.id = p_id;
$$;

CREATE FUNCTION contrato.autorizacion_vigente(p_rol TEXT, p_tipo TEXT) RETURNS JSONB
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = contrato, pg_catalog AS $$
  SELECT CASE WHEN a.retirada THEN NULL ELSE to_jsonb(a) END
  FROM contrato.autorizaciones a WHERE a.rol = p_rol AND a.tipo = p_tipo ORDER BY a.id DESC LIMIT 1;
$$;

-- Lo que el servicio necesita de un documento (sin el texto de la plantilla).
CREATE FUNCTION contrato.doc_json(d contrato.documentos) RETURNS JSONB
LANGUAGE sql STABLE SET search_path = contrato, pg_catalog AS $$
  SELECT to_jsonb(d) - 'token_sha256';
$$;

CREATE FUNCTION contrato.doc_por_token(p_token_sha256 TEXT) RETURNS JSONB
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = contrato, pg_catalog AS $$
  SELECT contrato.doc_json(d) FROM contrato.documentos d WHERE d.token_sha256 = p_token_sha256;
$$;

CREATE FUNCTION contrato.doc_por_id(p_id UUID) RETURNS JSONB
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = contrato, pg_catalog AS $$
  SELECT contrato.doc_json(d) FROM contrato.documentos d WHERE d.id = p_id;
$$;

CREATE FUNCTION contrato.docs_por_alta(p_alta_ref TEXT) RETURNS JSONB
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = contrato, pg_catalog AS $$
  SELECT coalesce(jsonb_agg(contrato.doc_json(d) ORDER BY d.creado_en), '[]'::jsonb)
  FROM contrato.documentos d WHERE d.alta_ref = p_alta_ref AND d.estado <> 'anulado';
$$;

CREATE FUNCTION contrato.eventos_de(p_doc UUID) RETURNS JSONB
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = contrato, pg_catalog AS $$
  SELECT coalesce(jsonb_agg(jsonb_build_object('n', e.n, 'tipo', e.tipo, 'ts', e.ts, 'ip', e.ip, 'user_agent', e.user_agent,
                                               'datos', e.datos::jsonb, 'hash', e.hash) ORDER BY e.n), '[]'::jsonb)
  FROM contrato.eventos e WHERE e.documento_id = p_doc;
$$;

-- Deja en la bandeja de salida, dentro de la misma transacción del hecho, los correos y el aviso que le siguen.
-- Así un documento firmado nunca queda sin su copia pendiente de envío, aunque el servicio se caiga justo después.
CREATE FUNCTION contrato.encolar(p_doc UUID, p_correos JSONB, p_aviso JSONB)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = contrato, pg_catalog AS $$
BEGIN
  INSERT INTO contrato.correos (documento_id, tipo, para)
  SELECT p_doc, x->>'tipo', x->>'para' FROM jsonb_array_elements(coalesce(p_correos, '[]'::jsonb)) x
   WHERE coalesce(x->>'para', '') <> '';
  IF p_aviso IS NOT NULL THEN
    INSERT INTO contrato.avisos (documento_id, tipo, cuerpo) VALUES (p_doc, p_aviso->>'tipo', p_aviso->'cuerpo');
  END IF;
END $$;

-- El contrato de esta alta (o de esta persona: mismo correo o mismo WhatsApp) existe: lo que estaba frenado por un
-- dato faltante queda resuelto y se deja de avisar.
CREATE FUNCTION contrato.altas_frenadas_resolver(p_ref TEXT, p_email TEXT, p_whatsapp TEXT, p_tipo TEXT)
RETURNS INTEGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = contrato, pg_catalog AS $$
DECLARE v_n INTEGER; v_wa TEXT := right(regexp_replace(coalesce(p_whatsapp, ''), '\D', '', 'g'), 10);
BEGIN
  UPDATE contrato.altas_frenadas SET resuelto_en = clock_timestamp(), resultado = 'emitido', tomado_en = NULL
   WHERE resuelto_en IS NULL
     AND (alta_ref = p_ref OR email = lower(btrim(coalesce(p_email, ''))) OR (length(v_wa) = 10 AND right(whatsapp, 10) = v_wa))
     AND (tipo = p_tipo OR (tipo LIKE 'servicio%' AND p_tipo LIKE 'servicio%'));
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END $$;

-- Alta de un documento. Repetir el alta (misma `alta_ref` y tipo) devuelve el que ya existe: no hay dos links vivos.
CREATE FUNCTION contrato.crear_documento(
  p_id UUID, p_tipo TEXT, p_plantilla_id TEXT, p_alta_ref TEXT, p_lead_id BIGINT, p_nombre TEXT, p_email TEXT, p_whatsapp TEXT,
  p_pais TEXT, p_variante TEXT, p_campos JSONB, p_token_sha256 TEXT, p_pdf_base_path TEXT, p_pdf_base_sha256 TEXT,
  p_reemplaza UUID, p_ip TEXT, p_ua TEXT, p_datos_evento TEXT)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = contrato, pg_catalog AS $$
DECLARE v_doc contrato.documentos; v_pl contrato.plantillas; v_viejo contrato.documentos;
BEGIN
  PERFORM pg_advisory_xact_lock(74260012, hashtext(p_alta_ref || '|' || p_tipo));
  SELECT * INTO v_pl FROM contrato.plantillas WHERE id = p_plantilla_id;
  IF NOT FOUND OR v_pl.tipo <> p_tipo THEN
    RAISE EXCEPTION 'plantilla % inexistente o de otro tipo', p_plantilla_id USING ERRCODE = '22023';
  END IF;
  IF p_reemplaza IS NOT NULL THEN
    SELECT * INTO v_viejo FROM contrato.documentos WHERE id = p_reemplaza FOR UPDATE;
    IF NOT FOUND OR v_viejo.alta_ref <> p_alta_ref OR v_viejo.tipo <> p_tipo THEN
      RAISE EXCEPTION 'el documento a reemplazar no es de esta alta' USING ERRCODE = '22023';
    END IF;
    IF v_viejo.estado <> 'pendiente' THEN
      RETURN jsonb_build_object('resultado', 'no_reemplazable', 'documento', contrato.doc_json(v_viejo));
    END IF;
    UPDATE contrato.documentos SET estado = 'anulado' WHERE id = p_reemplaza;
    PERFORM contrato.registrar_evento(p_reemplaza, 'anulado', p_ip, p_ua, jsonb_build_object('motivo', 'reemplazado', 'por', p_id)::TEXT);
  ELSE
    SELECT * INTO v_doc FROM contrato.documentos WHERE alta_ref = p_alta_ref AND tipo = p_tipo AND estado <> 'anulado';
    IF FOUND THEN
      RETURN jsonb_build_object('resultado', 'ya_existia', 'documento', contrato.doc_json(v_doc));
    END IF;
  END IF;
  INSERT INTO contrato.documentos (id, tipo, plantilla_id, alta_ref, lead_id, firmante_nombre, firmante_email, firmante_whatsapp,
                                   pais, variante, campos, token_n, token_sha256, pdf_base_path, pdf_base_sha256, reemplaza)
  VALUES (p_id, p_tipo, p_plantilla_id, p_alta_ref, p_lead_id, btrim(p_nombre), lower(btrim(p_email)), nullif(regexp_replace(coalesce(p_whatsapp, ''), '\D', '', 'g'), ''),
          nullif(btrim(coalesce(p_pais, '')), ''), p_variante, p_campos, 1, p_token_sha256, p_pdf_base_path, p_pdf_base_sha256, p_reemplaza)
  RETURNING * INTO v_doc;
  PERFORM contrato.registrar_evento(p_id, 'creado', p_ip, p_ua, p_datos_evento);
  -- si esta alta (o esta persona) estaba frenada por un dato faltante, quedó resuelta: se deja de avisar
  PERFORM contrato.altas_frenadas_resolver(p_alta_ref, p_email, p_whatsapp, p_tipo);
  RETURN jsonb_build_object('resultado', 'creado', 'documento', contrato.doc_json(v_doc));
END $$;

-- Anular un pendiente (mail mal escrito, datos mal, alta caída). Un firmado no se anula.
CREATE FUNCTION contrato.anular(p_doc UUID, p_motivo TEXT, p_ip TEXT, p_ua TEXT)
RETURNS TEXT LANGUAGE plpgsql SECURITY DEFINER SET search_path = contrato, pg_catalog AS $$
DECLARE v_estado TEXT;
BEGIN
  SELECT estado INTO v_estado FROM contrato.documentos WHERE id = p_doc FOR UPDATE;
  IF NOT FOUND THEN RETURN 'no_existe'; END IF;
  IF v_estado <> 'pendiente' THEN RETURN 'no_anulable'; END IF;
  UPDATE contrato.documentos SET estado = 'anulado' WHERE id = p_doc;
  PERFORM contrato.registrar_evento(p_doc, 'anulado', p_ip, p_ua, jsonb_build_object('motivo', left(coalesce(p_motivo, ''), 300))::TEXT);
  RETURN 'anulado';
END $$;

-- Los pendientes de la misma persona (mismo correo) y clase que nacieron de OTRO envío del formulario: al llegar un
-- alta nueva se anulan, para que no queden dos contratos firmables a la vez.
CREATE FUNCTION contrato.pendientes_de_email(p_email TEXT, p_tipo TEXT, p_alta_ref TEXT) RETURNS JSONB
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = contrato, pg_catalog AS $$
  SELECT coalesce(jsonb_agg(d.id ORDER BY d.creado_en), '[]'::jsonb) FROM contrato.documentos d
   WHERE d.estado = 'pendiente' AND d.tipo = p_tipo AND d.alta_ref <> p_alta_ref AND lower(d.firmante_email) = lower(btrim(p_email));
$$;

CREATE FUNCTION contrato.vincular_lead(p_alta_ref TEXT, p_lead_id BIGINT)
RETURNS INTEGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = contrato, pg_catalog AS $$
DECLARE v_n INTEGER;
BEGIN
  UPDATE contrato.documentos SET lead_id = p_lead_id WHERE alta_ref = p_alta_ref AND lead_id IS NULL;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END $$;

-- El alta la crea el bot unos segundos después de que nace el documento: esto los une cuando aparece (para que la
-- app pueda mostrarle al alumno sus documentos). Solo completa un lead_id vacío; nunca cambia uno puesto.
CREATE FUNCTION contrato.vincular_leads_pendientes() RETURNS INTEGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = contrato, pg_catalog AS $$
DECLARE r RECORD; v_lead BIGINT; v_n INTEGER := 0;
BEGIN
  FOR r IN SELECT DISTINCT alta_ref, firmante_email, firmante_whatsapp, min(creado_en) AS creado
             FROM contrato.documentos WHERE lead_id IS NULL AND estado <> 'anulado' AND creado_en > clock_timestamp() - interval '90 days'
            GROUP BY 1, 2, 3 LOOP
    v_lead := contrato.lead_de(r.firmante_email, coalesce(r.firmante_whatsapp, ''), r.creado - interval '6 hours', r.creado + interval '48 hours');
    IF v_lead IS NOT NULL THEN
      UPDATE contrato.documentos SET lead_id = v_lead WHERE alta_ref = r.alta_ref AND lead_id IS NULL;
      v_n := v_n + 1;
    END IF;
  END LOOP;
  RETURN v_n;
END $$;

-- Emite un código: anula los anteriores sin usar y frena si se piden demasiados.
CREATE FUNCTION contrato.emitir_codigo(p_doc UUID, p_proposito TEXT, p_codigo_hmac TEXT, p_ttl_seg INTEGER, p_ip TEXT, p_ua TEXT)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = contrato, pg_catalog AS $$
DECLARE v_doc contrato.documentos; v_hora INTEGER; v_dia INTEGER; v_ultimo TIMESTAMPTZ; v_id UUID;
BEGIN
  SELECT * INTO v_doc FROM contrato.documentos WHERE id = p_doc FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('resultado', 'no_existe'); END IF;
  IF (p_proposito = 'firma' AND v_doc.estado <> 'pendiente')
     OR (p_proposito IN ('revocacion', 'baja') AND v_doc.estado <> 'firmado') THEN
    RETURN jsonb_build_object('resultado', 'no_corresponde', 'estado', v_doc.estado);
  END IF;
  -- Un enlace sin firmar no queda abierto para siempre: a los 60 días hay que emitir el documento de nuevo.
  IF p_proposito = 'firma' AND v_doc.creado_en < clock_timestamp() - interval '60 days' THEN
    RETURN jsonb_build_object('resultado', 'documento_vencido');
  END IF;
  SELECT count(*) FILTER (WHERE creado_en > clock_timestamp() - interval '1 hour'),
         count(*) FILTER (WHERE creado_en > clock_timestamp() - interval '24 hours'), max(creado_en)
    INTO v_hora, v_dia, v_ultimo FROM contrato.codigos WHERE documento_id = p_doc;
  IF v_ultimo IS NOT NULL AND v_ultimo > clock_timestamp() - interval '45 seconds' THEN
    RETURN jsonb_build_object('resultado', 'esperar', 'segundos', ceil(45 - extract(epoch FROM clock_timestamp() - v_ultimo)));
  END IF;
  IF v_hora >= 5 OR v_dia >= 12 THEN
    RETURN jsonb_build_object('resultado', 'limite');
  END IF;
  UPDATE contrato.codigos SET anulado = true WHERE documento_id = p_doc AND proposito = p_proposito AND usado_en IS NULL AND NOT anulado;
  INSERT INTO contrato.codigos (documento_id, proposito, codigo_hmac, email, vence_en)
  VALUES (p_doc, p_proposito, p_codigo_hmac, v_doc.firmante_email, clock_timestamp() + make_interval(secs => greatest(60, least(p_ttl_seg, 3600))))
  RETURNING id INTO v_id;
  PERFORM contrato.registrar_evento(p_doc, 'codigo_emitido', p_ip, p_ua, jsonb_build_object('codigo', v_id, 'proposito', p_proposito)::TEXT);
  RETURN jsonb_build_object('resultado', 'emitido', 'codigo', v_id, 'email', v_doc.firmante_email);
END $$;

-- Valida el código. Cada intento fallido cuenta; al quinto el código muere y hay que pedir otro.
-- Un código ya verificado se puede volver a presentar mientras no se haya usado (reintento de la firma).
CREATE FUNCTION contrato.validar_codigo(p_doc UUID, p_proposito TEXT, p_codigo_hmac TEXT, p_ip TEXT, p_ua TEXT)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = contrato, pg_catalog AS $$
DECLARE v_c contrato.codigos;
BEGIN
  SELECT * INTO v_c FROM contrato.codigos
   WHERE documento_id = p_doc AND proposito = p_proposito AND NOT anulado AND usado_en IS NULL
   ORDER BY creado_en DESC LIMIT 1 FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('resultado', 'sin_codigo'); END IF;
  IF v_c.vence_en < clock_timestamp() THEN RETURN jsonb_build_object('resultado', 'vencido'); END IF;
  IF v_c.intentos >= 5 THEN RETURN jsonb_build_object('resultado', 'bloqueado'); END IF;
  IF v_c.codigo_hmac = p_codigo_hmac THEN
    IF v_c.verificado_en IS NULL THEN
      UPDATE contrato.codigos SET verificado_en = clock_timestamp() WHERE id = v_c.id;
      PERFORM contrato.registrar_evento(p_doc, 'codigo_validado', p_ip, p_ua,
                jsonb_build_object('codigo', v_c.id, 'proposito', p_proposito, 'email', v_c.email)::TEXT);
    END IF;
    RETURN jsonb_build_object('resultado', 'ok', 'codigo', v_c.id, 'email', v_c.email);
  END IF;
  UPDATE contrato.codigos SET intentos = intentos + 1, anulado = (intentos + 1 >= 5) WHERE id = v_c.id;
  PERFORM contrato.registrar_evento(p_doc, 'codigo_incorrecto', p_ip, p_ua, jsonb_build_object('codigo', v_c.id, 'intento', v_c.intentos + 1)::TEXT);
  RETURN jsonb_build_object('resultado', CASE WHEN v_c.intentos + 1 >= 5 THEN 'bloqueado' ELSE 'incorrecto' END, 'quedan', greatest(0, 4 - v_c.intentos));
END $$;

-- La firma: un solo paso atómico. Exige un código verificado hace poco y sin usar, y que el documento siga pendiente.
-- La hora (`p_ts`) la pide antes el servicio a `contrato.ahora()` para imprimirla en el PDF; acá se controla que sea reciente.
CREATE FUNCTION contrato.firmar(p_doc UUID, p_codigo UUID, p_ts TIMESTAMPTZ, p_pdf_path TEXT, p_pdf_sha256 TEXT, p_firma JSONB,
                                p_ip TEXT, p_ua TEXT, p_datos_evento TEXT, p_correos JSONB, p_aviso JSONB)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = contrato, pg_catalog AS $$
DECLARE v_doc contrato.documentos; v_c contrato.codigos; v_hash TEXT;
BEGIN
  SELECT * INTO v_doc FROM contrato.documentos WHERE id = p_doc FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('resultado', 'no_existe'); END IF;
  IF v_doc.estado IN ('firmado', 'revocado') THEN
    RETURN jsonb_build_object('resultado', 'ya_firmado', 'documento', contrato.doc_json(v_doc));
  END IF;
  IF v_doc.estado <> 'pendiente' THEN RETURN jsonb_build_object('resultado', 'no_disponible', 'estado', v_doc.estado); END IF;
  SELECT * INTO v_c FROM contrato.codigos WHERE id = p_codigo AND documento_id = p_doc AND proposito = 'firma' FOR UPDATE;
  IF NOT FOUND OR v_c.anulado OR v_c.usado_en IS NOT NULL OR v_c.verificado_en IS NULL
     OR v_c.verificado_en < clock_timestamp() - interval '20 minutes' THEN
    RETURN jsonb_build_object('resultado', 'codigo_invalido');
  END IF;
  IF p_ts IS NULL OR p_ts < v_c.verificado_en - interval '5 seconds' OR p_ts > clock_timestamp() + interval '5 seconds'
     OR p_ts < clock_timestamp() - interval '5 minutes' THEN
    RETURN jsonb_build_object('resultado', 'hora_invalida');
  END IF;
  UPDATE contrato.codigos SET usado_en = clock_timestamp() WHERE id = v_c.id;
  UPDATE contrato.documentos
     SET estado = 'firmado', firmado_en = date_trunc('microseconds', p_ts), pdf_final_path = p_pdf_path, pdf_final_sha256 = p_pdf_sha256, firma = p_firma
   WHERE id = p_doc RETURNING * INTO v_doc;
  v_hash := contrato.registrar_evento(p_doc, 'firmado', p_ip, p_ua, p_datos_evento, p_ts);
  PERFORM contrato.encolar(p_doc, p_correos, p_aviso);
  RETURN jsonb_build_object('resultado', 'firmado', 'evento_hash', v_hash, 'documento', contrato.doc_json(v_doc));
END $$;

-- Revocación del consentimiento médico: mismo esquema (código + PDF con la revocación en el mismo texto).
CREATE FUNCTION contrato.revocar(p_doc UUID, p_codigo UUID, p_ts TIMESTAMPTZ, p_pdf_path TEXT, p_pdf_sha256 TEXT,
                                 p_ip TEXT, p_ua TEXT, p_datos_evento TEXT, p_correos JSONB, p_aviso JSONB)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = contrato, pg_catalog AS $$
DECLARE v_doc contrato.documentos; v_c contrato.codigos; v_hash TEXT;
BEGIN
  SELECT * INTO v_doc FROM contrato.documentos WHERE id = p_doc FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('resultado', 'no_existe'); END IF;
  IF v_doc.tipo <> 'consentimiento_ar' THEN RETURN jsonb_build_object('resultado', 'no_corresponde'); END IF;
  IF v_doc.estado = 'revocado' THEN RETURN jsonb_build_object('resultado', 'ya_revocado', 'documento', contrato.doc_json(v_doc)); END IF;
  IF v_doc.estado <> 'firmado' THEN RETURN jsonb_build_object('resultado', 'no_disponible', 'estado', v_doc.estado); END IF;
  SELECT * INTO v_c FROM contrato.codigos WHERE id = p_codigo AND documento_id = p_doc AND proposito = 'revocacion' FOR UPDATE;
  IF NOT FOUND OR v_c.anulado OR v_c.usado_en IS NOT NULL OR v_c.verificado_en IS NULL
     OR v_c.verificado_en < clock_timestamp() - interval '20 minutes' THEN
    RETURN jsonb_build_object('resultado', 'codigo_invalido');
  END IF;
  IF p_ts IS NULL OR p_ts < v_c.verificado_en - interval '5 seconds' OR p_ts > clock_timestamp() + interval '5 seconds'
     OR p_ts < clock_timestamp() - interval '5 minutes' THEN
    RETURN jsonb_build_object('resultado', 'hora_invalida');
  END IF;
  UPDATE contrato.codigos SET usado_en = clock_timestamp() WHERE id = v_c.id;
  UPDATE contrato.documentos
     SET estado = 'revocado', revocado_en = date_trunc('microseconds', p_ts), pdf_revocacion_path = p_pdf_path, pdf_revocacion_sha256 = p_pdf_sha256
   WHERE id = p_doc RETURNING * INTO v_doc;
  v_hash := contrato.registrar_evento(p_doc, 'revocado', p_ip, p_ua, p_datos_evento, p_ts);
  PERFORM contrato.encolar(p_doc, p_correos, p_aviso);
  RETURN jsonb_build_object('resultado', 'revocado', 'evento_hash', v_hash, 'documento', contrato.doc_json(v_doc));
END $$;

-- Contrato de servicio: el pedido de revocación, desistimiento o baja «por el mismo medio». Queda registrado y avisa;
-- lo que corresponda devolver lo resuelve Mati.
CREATE FUNCTION contrato.pedir_baja(p_doc UUID, p_codigo UUID, p_ip TEXT, p_ua TEXT, p_datos_evento TEXT, p_correos JSONB, p_aviso JSONB)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = contrato, pg_catalog AS $$
DECLARE v_doc contrato.documentos; v_c contrato.codigos; v_hash TEXT;
BEGIN
  SELECT * INTO v_doc FROM contrato.documentos WHERE id = p_doc FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('resultado', 'no_existe'); END IF;
  IF v_doc.tipo = 'consentimiento_ar' OR v_doc.estado <> 'firmado' THEN RETURN jsonb_build_object('resultado', 'no_corresponde'); END IF;
  SELECT * INTO v_c FROM contrato.codigos WHERE id = p_codigo AND documento_id = p_doc AND proposito = 'baja' FOR UPDATE;
  IF NOT FOUND OR v_c.anulado OR v_c.usado_en IS NOT NULL OR v_c.verificado_en IS NULL
     OR v_c.verificado_en < clock_timestamp() - interval '20 minutes' THEN
    RETURN jsonb_build_object('resultado', 'codigo_invalido');
  END IF;
  UPDATE contrato.codigos SET usado_en = clock_timestamp() WHERE id = v_c.id;
  UPDATE contrato.documentos SET baja_pedida_en = coalesce(baja_pedida_en, clock_timestamp()) WHERE id = p_doc RETURNING * INTO v_doc;
  v_hash := contrato.registrar_evento(p_doc, 'baja_pedida', p_ip, p_ua, p_datos_evento);
  PERFORM contrato.encolar(p_doc, p_correos, p_aviso);
  RETURN jsonb_build_object('resultado', 'registrada', 'evento_hash', v_hash, 'documento', contrato.doc_json(v_doc));
END $$;

-- Cómo terminó un pedido de baja (lo carga una persona del equipo): 'sigue' = se habló y el contrato continúa, la
-- agenda se destraba; 'terminado' = el contrato se dio por terminado. Queda como evento; no se edita.
CREATE FUNCTION contrato.resolver_baja(p_doc UUID, p_resultado TEXT, p_nota TEXT, p_ip TEXT, p_ua TEXT)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = contrato, pg_catalog AS $$
DECLARE v_doc contrato.documentos;
BEGIN
  IF p_resultado NOT IN ('sigue', 'terminado') THEN RETURN jsonb_build_object('resultado', 'resultado_invalido'); END IF;
  SELECT * INTO v_doc FROM contrato.documentos WHERE id = p_doc FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('resultado', 'no_existe'); END IF;
  IF v_doc.baja_pedida_en IS NULL THEN RETURN jsonb_build_object('resultado', 'sin_baja_pedida'); END IF;
  IF v_doc.baja_resuelta_en IS NOT NULL THEN RETURN jsonb_build_object('resultado', 'ya_resuelta', 'documento', contrato.doc_json(v_doc)); END IF;
  UPDATE contrato.documentos SET baja_resuelta_en = clock_timestamp(), baja_resultado = p_resultado WHERE id = p_doc RETURNING * INTO v_doc;
  PERFORM contrato.registrar_evento(p_doc, 'baja_resuelta', p_ip, p_ua,
            jsonb_build_object('resultado', p_resultado, 'nota', left(coalesce(p_nota, ''), 500))::TEXT);
  RETURN jsonb_build_object('resultado', 'resuelta', 'documento', contrato.doc_json(v_doc));
END $$;

CREATE FUNCTION contrato.registrar_sello(p_objeto TEXT, p_doc UUID, p_evento_n BIGINT, p_sha256 TEXT, p_tsa TEXT, p_tsr BYTEA, p_hora TIMESTAMPTZ)
RETURNS BIGINT LANGUAGE plpgsql SECURITY DEFINER SET search_path = contrato, pg_catalog AS $$
DECLARE v_id BIGINT;
BEGIN
  INSERT INTO contrato.sellos (objeto, documento_id, evento_n, sha256, tsa, tsr, hora_sello)
  VALUES (p_objeto, p_doc, p_evento_n, p_sha256, p_tsa, p_tsr, p_hora)
  ON CONFLICT (objeto, sha256, tsa) DO NOTHING RETURNING id INTO v_id;
  IF v_id IS NOT NULL AND p_doc IS NOT NULL THEN
    PERFORM contrato.registrar_evento(p_doc, 'sellado', NULL, NULL,
              jsonb_build_object('sello', v_id, 'objeto', p_objeto, 'sha256', p_sha256, 'tsa', p_tsa, 'hora_sello', p_hora)::TEXT);
  END IF;
  RETURN v_id;
END $$;

CREATE FUNCTION contrato.sellos_de(p_doc UUID) RETURNS JSONB
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = contrato, pg_catalog AS $$
  SELECT coalesce(jsonb_agg(jsonb_build_object('id', s.id, 'objeto', s.objeto, 'sha256', s.sha256, 'tsa', s.tsa, 'hora_sello', s.hora_sello,
                                               'tsr_b64', encode(s.tsr, 'base64')) ORDER BY s.id), '[]'::jsonb)
  FROM contrato.sellos s WHERE s.documento_id = p_doc;
$$;

-- Lo que falta sellar: firmados o revocados sin sello de alguna de las TSA pedidas.
CREATE FUNCTION contrato.sin_sello(p_tsas TEXT[], p_doc UUID DEFAULT NULL) RETURNS JSONB
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = contrato, pg_catalog AS $$
  SELECT coalesce(jsonb_agg(x), '[]'::jsonb) FROM (
    SELECT jsonb_build_object('documento', d.id, 'objeto', 'documento', 'sha256', d.pdf_final_sha256, 'tsa', t) x
      FROM contrato.documentos d CROSS JOIN unnest(p_tsas) t
     WHERE d.pdf_final_sha256 IS NOT NULL AND (p_doc IS NULL OR d.id = p_doc)
       AND NOT EXISTS (SELECT 1 FROM contrato.sellos s WHERE s.objeto = 'documento' AND s.sha256 = d.pdf_final_sha256 AND s.tsa = t)
    UNION ALL
    SELECT jsonb_build_object('documento', d.id, 'objeto', 'revocacion', 'sha256', d.pdf_revocacion_sha256, 'tsa', t)
      FROM contrato.documentos d CROSS JOIN unnest(p_tsas) t
     WHERE d.pdf_revocacion_sha256 IS NOT NULL AND (p_doc IS NULL OR d.id = p_doc)
       AND NOT EXISTS (SELECT 1 FROM contrato.sellos s WHERE s.objeto = 'revocacion' AND s.sha256 = d.pdf_revocacion_sha256 AND s.tsa = t)
  ) q;
$$;

-- Verificación pública: con el identificador, o con la huella de un PDF. No devuelve datos de la persona.
CREATE FUNCTION contrato.verificar(p_id UUID, p_sha256 TEXT) RETURNS JSONB
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = contrato, pg_catalog AS $$
  SELECT jsonb_build_object(
           'id', d.id, 'tipo', d.tipo, 'estado', d.estado, 'firmado_en', d.firmado_en, 'revocado_en', d.revocado_en,
           'coincide', CASE WHEN p_sha256 IS NULL THEN NULL
                            WHEN p_sha256 = d.pdf_final_sha256 THEN 'firmado'
                            WHEN p_sha256 = d.pdf_revocacion_sha256 THEN 'revocacion'
                            WHEN p_sha256 = d.pdf_base_sha256 THEN 'sin_firmar'
                            ELSE 'no' END,
           'sellos', (SELECT coalesce(jsonb_agg(jsonb_build_object('objeto', s.objeto, 'tsa', s.tsa, 'hora', s.hora_sello, 'sha256', s.sha256) ORDER BY s.id), '[]'::jsonb)
                        FROM contrato.sellos s WHERE s.documento_id = d.id))
    FROM contrato.documentos d
   WHERE d.estado <> 'anulado'
     AND ((p_id IS NOT NULL AND d.id = p_id)
       OR (p_id IS NULL AND p_sha256 IS NOT NULL AND p_sha256 IN (d.pdf_final_sha256, d.pdf_revocacion_sha256)))
   LIMIT 1;
$$;

CREATE FUNCTION contrato.cabeza_cadena() RETURNS JSONB
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = contrato, pg_catalog AS $$
  SELECT jsonb_build_object('n', e.n, 'hash', e.hash, 'ts', e.ts) FROM contrato.eventos e ORDER BY e.n DESC LIMIT 1;
$$;

-- Toda la cadena, para el respaldo diario y para verificarla fuera de la base.
CREATE FUNCTION contrato.cadena(p_desde BIGINT, p_tope INTEGER) RETURNS JSONB
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = contrato, pg_catalog AS $$
  SELECT coalesce(jsonb_agg(to_jsonb(e) ORDER BY e.n), '[]'::jsonb)
  FROM (SELECT * FROM contrato.eventos WHERE n > p_desde ORDER BY n LIMIT greatest(1, least(p_tope, 5000))) e;
$$;

CREATE FUNCTION contrato.respaldo_documentos(p_desde TIMESTAMPTZ) RETURNS JSONB
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = contrato, pg_catalog AS $$
  SELECT coalesce(jsonb_agg(contrato.doc_json(d) ORDER BY d.creado_en), '[]'::jsonb)
  FROM contrato.documentos d WHERE d.creado_en >= p_desde OR d.firmado_en >= p_desde OR d.revocado_en >= p_desde;
$$;

-- Correo
CREATE FUNCTION contrato.correo_nuevo(p_doc UUID, p_tipo TEXT, p_para TEXT) RETURNS UUID
LANGUAGE sql SECURITY DEFINER SET search_path = contrato, pg_catalog AS $$
  INSERT INTO contrato.correos (documento_id, tipo, para) VALUES (p_doc, p_tipo, p_para) RETURNING id;
$$;

CREATE FUNCTION contrato.correo_resultado(p_id UUID, p_ok BOOLEAN, p_message_id TEXT, p_respuesta TEXT)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = contrato, pg_catalog AS $$
DECLARE v_c contrato.correos;
BEGIN
  UPDATE contrato.correos
     SET estado = CASE WHEN p_ok THEN 'enviado' ELSE 'fallo' END, intentos = intentos + 1, message_id = coalesce(p_message_id, message_id),
         respuesta = left(coalesce(p_respuesta, ''), 500), enviado_en = CASE WHEN p_ok THEN clock_timestamp() ELSE enviado_en END,
         tomado_en = CASE WHEN p_ok THEN tomado_en ELSE NULL END,
         proximo_en = CASE WHEN p_ok THEN NULL ELSE clock_timestamp() + least(interval '30 seconds' * power(2, least(intentos, 10)), interval '30 minutes') END
   WHERE id = p_id AND estado <> 'enviado' RETURNING * INTO v_c;
  IF FOUND AND v_c.documento_id IS NOT NULL AND v_c.tipo <> 'codigo' THEN
    PERFORM contrato.registrar_evento(v_c.documento_id, CASE WHEN p_ok THEN 'correo_enviado' ELSE 'correo_fallo' END, NULL, NULL,
              jsonb_build_object('correo', v_c.id, 'tipo', v_c.tipo, 'message_id', v_c.message_id, 'intento', v_c.intentos)::TEXT);
  END IF;
END $$;

-- Toma los correos pendientes: quien los toma tiene 5 minutos para mandarlos antes de que otro los vuelva a tomar.
-- Los de código no pasan por acá (se mandan en el momento o no se mandan).
-- Devuelve a la bandeja un correo tomado que todavía no corresponde mandar (la custodia espera a los sellos).
CREATE FUNCTION contrato.correo_soltar(p_id UUID, p_espera_seg INTEGER) RETURNS VOID
LANGUAGE sql SECURITY DEFINER SET search_path = contrato, pg_catalog AS $$
  UPDATE contrato.correos SET tomado_en = NULL, proximo_en = clock_timestamp() + make_interval(secs => greatest(10, least(p_espera_seg, 3600)))
   WHERE id = p_id AND estado <> 'enviado';
$$;

-- La invitación (el correo con el enlace para firmar): una sola por documento, y solo mientras esté pendiente.
CREATE FUNCTION contrato.invitar(p_doc UUID) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = contrato, pg_catalog AS $$
DECLARE v_doc contrato.documentos; v_id UUID;
BEGIN
  SELECT * INTO v_doc FROM contrato.documentos WHERE id = p_doc FOR UPDATE;
  IF NOT FOUND OR v_doc.estado <> 'pendiente' THEN RETURN NULL; END IF;
  IF EXISTS (SELECT 1 FROM contrato.correos WHERE documento_id = p_doc AND tipo = 'invitacion') THEN RETURN NULL; END IF;
  INSERT INTO contrato.correos (documento_id, tipo, para) VALUES (p_doc, 'invitacion', v_doc.firmante_email) RETURNING id INTO v_id;
  RETURN v_id;
END $$;

CREATE FUNCTION contrato.correos_pendientes(p_tope INTEGER, p_doc UUID DEFAULT NULL) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = contrato, pg_catalog AS $$
DECLARE v JSONB;
BEGIN
  WITH t AS (
    SELECT id FROM contrato.correos
     WHERE estado <> 'enviado' AND tipo <> 'codigo'
       AND (proximo_en IS NULL OR proximo_en <= clock_timestamp()) AND creado_en > clock_timestamp() - interval '45 days'
       AND (p_doc IS NULL OR documento_id = p_doc)
       -- una invitación solo sale mientras el documento siga pendiente (si ya firmó o se anuló, no tiene sentido)
       AND (tipo <> 'invitacion' OR EXISTS (SELECT 1 FROM contrato.documentos d WHERE d.id = correos.documento_id AND d.estado = 'pendiente'))
       AND (tomado_en IS NULL OR tomado_en < clock_timestamp() - interval '5 minutes')
     ORDER BY creado_en LIMIT greatest(1, least(p_tope, 200)) FOR UPDATE SKIP LOCKED),
  u AS (UPDATE contrato.correos c SET tomado_en = clock_timestamp() FROM t WHERE c.id = t.id RETURNING c.*)
  SELECT coalesce(jsonb_agg(to_jsonb(u) ORDER BY u.creado_en), '[]'::jsonb) INTO v FROM u;
  RETURN v;
END $$;

-- Avisos
CREATE FUNCTION contrato.aviso_nuevo(p_doc UUID, p_tipo TEXT, p_cuerpo JSONB) RETURNS UUID
LANGUAGE sql SECURITY DEFINER SET search_path = contrato, pg_catalog AS $$
  INSERT INTO contrato.avisos (documento_id, tipo, cuerpo) VALUES (p_doc, p_tipo, p_cuerpo) RETURNING id;
$$;

CREATE FUNCTION contrato.aviso_resultado(p_id UUID, p_ok BOOLEAN, p_respuesta TEXT)
RETURNS VOID LANGUAGE sql SECURITY DEFINER SET search_path = contrato, pg_catalog AS $$
  UPDATE contrato.avisos
     SET estado = CASE WHEN p_ok THEN 'enviado' ELSE 'fallo' END, intentos = intentos + 1, respuesta = left(coalesce(p_respuesta, ''), 500),
         enviado_en = CASE WHEN p_ok THEN clock_timestamp() ELSE enviado_en END,
         tomado_en = CASE WHEN p_ok THEN tomado_en ELSE NULL END,
         proximo_en = CASE WHEN p_ok THEN NULL ELSE clock_timestamp() + least(interval '30 seconds' * power(2, least(intentos, 10)), interval '30 minutes') END
   WHERE id = p_id AND estado <> 'enviado';
$$;

CREATE FUNCTION contrato.avisos_pendientes(p_tope INTEGER, p_doc UUID DEFAULT NULL) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = contrato, pg_catalog AS $$
DECLARE v JSONB;
BEGIN
  WITH t AS (
    SELECT id FROM contrato.avisos
     WHERE estado <> 'enviado'
       AND (proximo_en IS NULL OR proximo_en <= clock_timestamp()) AND creado_en > clock_timestamp() - interval '45 days'
       AND (p_doc IS NULL OR documento_id = p_doc)
       AND (tomado_en IS NULL OR tomado_en < clock_timestamp() - interval '5 minutes')
     ORDER BY creado_en LIMIT greatest(1, least(p_tope, 200)) FOR UPDATE SKIP LOCKED),
  u AS (UPDATE contrato.avisos a SET tomado_en = clock_timestamp() FROM t WHERE a.id = t.id RETURNING a.*)
  SELECT coalesce(jsonb_agg(to_jsonb(u) ORDER BY u.creado_en), '[]'::jsonb) INTO v FROM u;
  RETURN v;
END $$;

-- Altas frenadas
-- Huella corta de la referencia del alta: lo que sale del servicio (cadena, avisos) nunca lleva la referencia cruda.
CREATE FUNCTION contrato.huella_alta(p_ref TEXT) RETURNS TEXT
LANGUAGE sql IMMUTABLE SET search_path = contrato, pg_catalog AS $$
  SELECT left(encode(sha256(convert_to(coalesce(p_ref, ''), 'UTF8')), 'hex'), 16);
$$;

-- Anota que el alta no se emitió y qué le falta. Repetir el mismo envío no vuelve a avisar antes de tiempo; si cambia
-- lo que falta (o estaba cerrada y vuelve a llegar incompleta), se avisa de nuevo enseguida.
CREATE FUNCTION contrato.alta_frenada(p_ref TEXT, p_tipo TEXT, p_nombre TEXT, p_email TEXT, p_whatsapp TEXT, p_faltan TEXT[],
                                      p_ip TEXT, p_ua TEXT)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = contrato, pg_catalog AS $$
DECLARE v contrato.altas_frenadas; v_otra contrato.altas_frenadas; v_nueva BOOLEAN := false; v_email TEXT := lower(btrim(p_email));
BEGIN
  PERFORM pg_advisory_xact_lock(74260013, hashtext(v_email));
  SELECT * INTO v FROM contrato.altas_frenadas WHERE alta_ref = p_ref FOR UPDATE;
  IF NOT FOUND THEN
    -- El formulario reenviado otro día trae otra referencia: es la misma persona. La frenada anterior se cierra y
    -- esta hereda su cuenta de avisos (si falta lo mismo no se avisa de nuevo antes de tiempo): nunca dos avisando.
    SELECT * INTO v_otra FROM contrato.altas_frenadas
     WHERE resuelto_en IS NULL AND email = v_email AND (tipo = p_tipo OR (tipo LIKE 'servicio%' AND p_tipo LIKE 'servicio%'))
     ORDER BY visto_en DESC LIMIT 1;
    v_nueva := v_otra.alta_ref IS NULL OR v_otra.faltan IS DISTINCT FROM p_faltan;
    UPDATE contrato.altas_frenadas SET resuelto_en = clock_timestamp(), resultado = 'reemplazada', tomado_en = NULL
     WHERE resuelto_en IS NULL AND email = v_email AND (tipo = p_tipo OR (tipo LIKE 'servicio%' AND p_tipo LIKE 'servicio%'));
    INSERT INTO contrato.altas_frenadas (alta_ref, tipo, nombre, email, whatsapp, faltan, creado_en, avisos, ultimo_aviso_en)
    VALUES (p_ref, p_tipo, nullif(btrim(coalesce(p_nombre, '')), ''), v_email,
            nullif(regexp_replace(coalesce(p_whatsapp, ''), '\D', '', 'g'), ''), p_faltan,
            coalesce(v_otra.creado_en, clock_timestamp()), coalesce(v_otra.avisos, 0),
            CASE WHEN v_nueva THEN NULL ELSE v_otra.ultimo_aviso_en END)
    RETURNING * INTO v;
  ELSE
    v_nueva := v.resuelto_en IS NOT NULL OR v.faltan IS DISTINCT FROM p_faltan OR v.tipo <> p_tipo;
    UPDATE contrato.altas_frenadas
       SET tipo = p_tipo, nombre = nullif(btrim(coalesce(p_nombre, '')), ''), email = v_email,
           whatsapp = nullif(regexp_replace(coalesce(p_whatsapp, ''), '\D', '', 'g'), ''), faltan = p_faltan,
           visto_en = clock_timestamp(), resuelto_en = NULL, resultado = NULL,
           ultimo_aviso_en = CASE WHEN v_nueva THEN NULL ELSE ultimo_aviso_en END,
           tomado_en = CASE WHEN v_nueva THEN NULL ELSE tomado_en END
     WHERE alta_ref = p_ref RETURNING * INTO v;
  END IF;
  IF v_nueva THEN  -- sin datos de la persona (la referencia del alta puede traer el correo: va su huella) y qué faltó
    PERFORM contrato.registrar_evento(NULL, 'alta_frenada', p_ip, p_ua,
                                      jsonb_build_object('alta', contrato.huella_alta(p_ref), 'tipo', p_tipo, 'faltan', to_jsonb(p_faltan))::TEXT);
  END IF;
  RETURN to_jsonb(v);
END $$;

-- Las que toca avisar: abiertas, sin aviso todavía o con el último hace más de `p_horas`. Se avisa hasta `p_dias`
-- después de la última vez que el formulario llegó incompleto; pasado eso sigue contando en /salud y en el parte diario.
CREATE FUNCTION contrato.altas_frenadas_para_avisar(p_horas INTEGER, p_dias INTEGER, p_tope INTEGER) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = contrato, pg_catalog AS $$
DECLARE v JSONB;
BEGIN
  WITH t AS (
    SELECT alta_ref FROM contrato.altas_frenadas
     WHERE resuelto_en IS NULL
       AND (ultimo_aviso_en IS NULL OR ultimo_aviso_en <= clock_timestamp() - make_interval(hours => greatest(1, p_horas)))
       AND visto_en > clock_timestamp() - make_interval(days => greatest(1, p_dias))
       AND (tomado_en IS NULL OR tomado_en < clock_timestamp() - interval '5 minutes')
     ORDER BY creado_en LIMIT greatest(1, least(p_tope, 200)) FOR UPDATE SKIP LOCKED),
  u AS (UPDATE contrato.altas_frenadas a SET tomado_en = clock_timestamp() FROM t WHERE a.alta_ref = t.alta_ref RETURNING a.*)
  SELECT coalesce(jsonb_agg(to_jsonb(u) || jsonb_build_object('huella', contrato.huella_alta(u.alta_ref)) ORDER BY u.creado_en), '[]'::jsonb) INTO v FROM u;
  RETURN v;
END $$;

-- Resultado del aviso. Si salió, cuenta y arranca la espera hasta el próximo; si no, se reintenta a los 5 minutos.
-- Si mientras el aviso viajaba el formulario llegó con otra cosa faltante (la toma se soltó), no se pisa: se avisa lo nuevo.
CREATE FUNCTION contrato.alta_frenada_avisada(p_ref TEXT, p_ok BOOLEAN, p_respuesta TEXT)
RETURNS VOID LANGUAGE sql SECURITY DEFINER SET search_path = contrato, pg_catalog AS $$
  UPDATE contrato.altas_frenadas
     SET avisos = avisos + CASE WHEN p_ok THEN 1 ELSE 0 END,
         ultimo_aviso_en = CASE WHEN p_ok THEN clock_timestamp() ELSE ultimo_aviso_en END,
         tomado_en = CASE WHEN p_ok THEN NULL ELSE tomado_en END,
         respuesta = left(coalesce(p_respuesta, ''), 500)
   WHERE alta_ref = p_ref AND resuelto_en IS NULL AND tomado_en IS NOT NULL;
$$;

-- Cierre a mano (la persona no va a seguir, o se resolvió por otro lado), por referencia o por su huella (la que
-- trae el aviso). Deja de avisar. Queda en la cadena.
CREATE FUNCTION contrato.alta_frenada_descartar(p_ref TEXT, p_motivo TEXT, p_ip TEXT, p_ua TEXT)
RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER SET search_path = contrato, pg_catalog AS $$
DECLARE v_huella TEXT;
BEGIN
  UPDATE contrato.altas_frenadas
     SET resuelto_en = clock_timestamp(), resultado = 'descartada: ' || left(coalesce(nullif(btrim(p_motivo), ''), 'sin motivo'), 200), tomado_en = NULL
   WHERE (alta_ref = p_ref OR contrato.huella_alta(alta_ref) = p_ref) AND resuelto_en IS NULL
  RETURNING contrato.huella_alta(alta_ref) INTO v_huella;
  IF NOT FOUND THEN RETURN false; END IF;
  -- el motivo (texto libre) queda en la tabla, no en la cadena
  PERFORM contrato.registrar_evento(NULL, 'alta_descartada', p_ip, p_ua, jsonb_build_object('alta', v_huella)::TEXT);
  RETURN true;
END $$;

-- Lo que quedó a medias y hay que mirar: sin copia al firmante, sin sello o sin aviso, pasado un rato; y las altas
-- que siguen frenadas por un dato faltante.
CREATE FUNCTION contrato.pendientes_de_atencion(p_minutos INTEGER) RETURNS JSONB
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = contrato, pg_catalog AS $$
  SELECT jsonb_build_object(
    'sin_copia', (SELECT coalesce(jsonb_agg(d.id), '[]'::jsonb) FROM contrato.documentos d
                   WHERE d.estado = 'firmado' AND d.firmado_en < clock_timestamp() - make_interval(mins => p_minutos)
                     AND NOT EXISTS (SELECT 1 FROM contrato.correos c WHERE c.documento_id = d.id AND c.tipo = 'copia_firmado' AND c.estado = 'enviado')),
    'sin_sello', (SELECT coalesce(jsonb_agg(d.id), '[]'::jsonb) FROM contrato.documentos d
                   WHERE d.estado IN ('firmado', 'revocado') AND d.firmado_en < clock_timestamp() - make_interval(mins => p_minutos)
                     AND NOT EXISTS (SELECT 1 FROM contrato.sellos s WHERE s.objeto = 'documento' AND s.sha256 = d.pdf_final_sha256)),
    'sin_aviso', (SELECT coalesce(jsonb_agg(a.id), '[]'::jsonb) FROM contrato.avisos a
                   WHERE a.estado <> 'enviado' AND a.creado_en < clock_timestamp() - make_interval(mins => p_minutos)),
    'altas_frenadas', (SELECT coalesce(jsonb_agg(f.alta_ref), '[]'::jsonb) FROM contrato.altas_frenadas f
                        WHERE f.resuelto_en IS NULL AND f.creado_en < clock_timestamp() - make_interval(mins => p_minutos)));
$$;

-- ═════════════ Puertas de lectura en public ═════════════

-- Para el bot y AUTOMATIZAR ENTREGAS (service_role). `bloquea_agenda` es verdadero mientras haya un contrato de
-- servicio de la firma propia sin firmar, o con baja pedida. Quien no tiene documentos acá (los que firmaron por
-- BoldSign, los naturales) no queda bloqueado nunca.
CREATE FUNCTION public.contrato_estado(p_lead_id BIGINT DEFAULT NULL, p_email TEXT DEFAULT NULL, p_whatsapp TEXT DEFAULT NULL)
RETURNS JSONB LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = contrato, pg_catalog AS $$
DECLARE v_wa TEXT := right(regexp_replace(coalesce(p_whatsapp, ''), '\D', '', 'g'), 10);
        v_mail TEXT := lower(btrim(coalesce(p_email, ''))); v_por TEXT; v_docs JSONB; v_serv JSONB; v_cons JSONB;
BEGIN
  IF p_lead_id IS NULL AND v_mail = '' AND length(v_wa) < 10 THEN
    RAISE EXCEPTION 'contrato_estado: hace falta el lead, el mail o el WhatsApp' USING ERRCODE = '22023';
  END IF;
  -- Se busca por un solo dato, del más firme al menos firme, para no mezclar personas que comparten teléfono o correo.
  v_por := CASE
    WHEN p_lead_id IS NOT NULL AND EXISTS (SELECT 1 FROM contrato.documentos d WHERE d.estado <> 'anulado' AND d.lead_id = p_lead_id) THEN 'lead'
    WHEN v_mail <> '' AND EXISTS (SELECT 1 FROM contrato.documentos d WHERE d.estado <> 'anulado' AND lower(d.firmante_email) = v_mail) THEN 'email'
    WHEN length(v_wa) = 10 AND EXISTS (SELECT 1 FROM contrato.documentos d WHERE d.estado <> 'anulado'
           AND right(regexp_replace(coalesce(d.firmante_whatsapp, ''), '\D', '', 'g'), 10) = v_wa) THEN 'whatsapp'
    ELSE 'nada' END;
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'id', d.id, 'tipo', d.tipo, 'estado', d.estado, 'creado_en', d.creado_en, 'firmado_en', d.firmado_en,
           'revocado_en', d.revocado_en, 'baja_pedida_en', d.baja_pedida_en, 'baja_resuelta_en', d.baja_resuelta_en,
           'baja_resultado', d.baja_resultado, 'lead_id', d.lead_id, 'alta_ref', d.alta_ref) ORDER BY d.creado_en, d.id), '[]'::jsonb)
    INTO v_docs
    FROM contrato.documentos d
   WHERE d.estado <> 'anulado'
     AND ((v_por = 'lead' AND d.lead_id = p_lead_id)
       -- por mail o por teléfono no se toman documentos que ya son de OTRO lead (personas que comparten contacto)
       OR (v_por = 'email' AND lower(d.firmante_email) = v_mail AND (p_lead_id IS NULL OR d.lead_id IS NULL OR d.lead_id = p_lead_id))
       OR (v_por = 'whatsapp' AND right(regexp_replace(coalesce(d.firmante_whatsapp, ''), '\D', '', 'g'), 10) = v_wa
           AND (p_lead_id IS NULL OR d.lead_id IS NULL OR d.lead_id = p_lead_id)));
  -- Decide el documento más nuevo de cada clase (una recompra trae un contrato nuevo; el viejo ya no cuenta).
  SELECT x INTO v_serv FROM jsonb_array_elements(v_docs) WITH ORDINALITY t(x, o) WHERE x->>'tipo' LIKE 'servicio_%' ORDER BY o DESC LIMIT 1;
  SELECT x INTO v_cons FROM jsonb_array_elements(v_docs) WITH ORDINALITY t(x, o) WHERE x->>'tipo' = 'consentimiento_ar' ORDER BY o DESC LIMIT 1;
  RETURN jsonb_build_object(
    'documentos', v_docs,
    'encontrado_por', v_por,
    -- contrato de servicio firmado, sin pedido de baja abierto y sin haberse dado por terminado
    'servicio_firmado', coalesce(v_serv->>'estado' = 'firmado' AND (v_serv->>'baja_pedida_en' IS NULL OR v_serv->>'baja_resultado' = 'sigue'), false),
    'baja_abierta', coalesce(v_serv->>'baja_pedida_en' IS NOT NULL AND v_serv->>'baja_resuelta_en' IS NULL, false),
    'consentimiento_vigente', coalesce(v_cons->>'estado' = 'firmado', false),
    'consentimiento_pendiente', coalesce(v_cons->>'estado' = 'pendiente', false),
    -- La agenda se frena solo si HAY un contrato de servicio y no está firmado, o tiene una baja pedida que no se
    -- resolvió con «sigue». Sin contrato emitido (alta sin farmacología, alumnos anteriores a este sistema) no se frena nada.
    'bloquea_agenda', coalesce(v_serv->>'estado' = 'pendiente'
                               OR (v_serv->>'estado' = 'firmado' AND v_serv->>'baja_pedida_en' IS NOT NULL
                                   AND coalesce(v_serv->>'baja_resultado', '') <> 'sigue'), false));
END $$;

-- Para la app (Fase 2): el alumno ve el estado de sus documentos con su token. Sin links ni datos de más: el link de
-- firma lo entrega el servicio, que vuelve a validar el token.
CREATE FUNCTION public.mypump_contrato_get(p_token TEXT)
RETURNS JSONB LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, contrato AS $$
DECLARE v_cliente TEXT; v_docs JSONB;
BEGIN
  SELECT c.cliente_id INTO v_cliente FROM public.mypump_clientes c WHERE c.access_token = p_token AND c.access_token_active;
  IF v_cliente IS NULL THEN
    RAISE EXCEPTION 'token inválido' USING ERRCODE = '28000';
  END IF;
  SELECT coalesce(jsonb_agg(jsonb_build_object('id', d.id, 'tipo', d.tipo, 'titulo', p.titulo, 'estado', d.estado,
                                               'firmado_en', d.firmado_en, 'revocado_en', d.revocado_en) ORDER BY d.creado_en), '[]'::jsonb)
    INTO v_docs
    FROM contrato.documentos d JOIN contrato.plantillas p ON p.id = d.plantilla_id
   WHERE d.estado <> 'anulado'
     AND d.lead_id IN (SELECT l.id FROM public.onboarding_leads l WHERE l.linked_client_id = v_cliente);
  RETURN jsonb_build_object('documentos', v_docs,
    'pendientes', (SELECT count(*) FROM jsonb_array_elements(v_docs) x WHERE x->>'estado' = 'pendiente'));
END $$;

-- La misma búsqueda, para el servicio (que arma los links): devuelve los ids de los documentos del dueño del token.
CREATE FUNCTION contrato.docs_de_app(p_token TEXT) RETURNS JSONB
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, contrato AS $$
DECLARE v_cliente TEXT;
BEGIN
  SELECT c.cliente_id INTO v_cliente FROM public.mypump_clientes c WHERE c.access_token = p_token AND c.access_token_active;
  IF v_cliente IS NULL THEN RETURN NULL; END IF;
  RETURN (SELECT coalesce(jsonb_agg(contrato.doc_json(d) ORDER BY d.creado_en), '[]'::jsonb)
            FROM contrato.documentos d
           WHERE d.estado <> 'anulado'
             AND d.lead_id IN (SELECT l.id FROM public.onboarding_leads l WHERE l.linked_client_id = v_cliente));
END $$;

-- Busca el lead de un alta (lo crea el bot unos segundos después). Conservador a propósito, porque el vínculo no se
-- puede cambiar y es lo que le muestra los documentos a alguien en la app: tiene que coincidir el correo (el teléfono
-- solo vale si el lead no tiene correo), haber nacido cerca del documento, y ser el ÚNICO candidato. Si hay duda, no vincula.
CREATE FUNCTION contrato.lead_de(p_email TEXT, p_whatsapp TEXT, p_desde TIMESTAMPTZ, p_hasta TIMESTAMPTZ) RETURNS BIGINT
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog AS $$
  WITH c AS (
    SELECT l.id FROM public.onboarding_leads l
     WHERE l.created_at >= p_desde AND l.created_at <= p_hasta
       AND ((coalesce(btrim(p_email), '') <> '' AND lower(btrim(l.email)) = lower(btrim(p_email)))
         OR (coalesce(btrim(l.email), '') = '' AND length(regexp_replace(coalesce(p_whatsapp, ''), '\D', '', 'g')) >= 10
             AND right(regexp_replace(coalesce(l.whatsapp, ''), '\D', '', 'g'), 10) = right(regexp_replace(p_whatsapp, '\D', '', 'g'), 10))))
  SELECT (SELECT id FROM c LIMIT 1) WHERE (SELECT count(*) FROM c) = 1;
$$;

-- ── Permisos ──
-- RLS prendido y sin políticas: aunque algún día se exponga el esquema, nadie lee ni escribe fuera de las funciones.
ALTER TABLE contrato.plantillas     ENABLE ROW LEVEL SECURITY;
ALTER TABLE contrato.documentos     ENABLE ROW LEVEL SECURITY;
ALTER TABLE contrato.eventos        ENABLE ROW LEVEL SECURITY;
ALTER TABLE contrato.codigos        ENABLE ROW LEVEL SECURITY;
ALTER TABLE contrato.sellos         ENABLE ROW LEVEL SECURITY;
ALTER TABLE contrato.correos        ENABLE ROW LEVEL SECURITY;
ALTER TABLE contrato.avisos         ENABLE ROW LEVEL SECURITY;
ALTER TABLE contrato.autorizaciones ENABLE ROW LEVEL SECURITY;
ALTER TABLE contrato.altas_frenadas ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON ALL TABLES IN SCHEMA contrato FROM PUBLIC;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA contrato FROM PUBLIC;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA contrato TO firma_srv;
REVOKE EXECUTE ON FUNCTION contrato.plantillas_inmutables(), contrato.solo_agrega(), contrato.documentos_guardia() FROM firma_srv;

REVOKE ALL ON FUNCTION public.contrato_estado(BIGINT, TEXT, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.mypump_contrato_get(TEXT) FROM PUBLIC;
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    EXECUTE 'REVOKE ALL ON SCHEMA contrato FROM anon, authenticated';
    EXECUTE 'REVOKE ALL ON FUNCTION public.contrato_estado(BIGINT, TEXT, TEXT) FROM anon, authenticated';
    EXECUTE 'GRANT EXECUTE ON FUNCTION public.contrato_estado(BIGINT, TEXT, TEXT) TO service_role';
    EXECUTE 'GRANT EXECUTE ON FUNCTION public.mypump_contrato_get(TEXT) TO anon, authenticated, service_role';
  END IF;
END $$;
GRANT EXECUTE ON FUNCTION public.contrato_estado(BIGINT, TEXT, TEXT) TO firma_srv;

-- Bucket privado para los PDF. Solo entra el servicio, con la service key.
DO $$
BEGIN
  IF to_regclass('storage.buckets') IS NOT NULL THEN
    INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
    VALUES ('contratos', 'contratos', false, 10485760, ARRAY['application/pdf'])
    ON CONFLICT (id) DO NOTHING;
  END IF;
END $$;

NOTIFY pgrst, 'reload schema';
COMMIT;
