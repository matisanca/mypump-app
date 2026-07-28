-- ============================================================
-- 048 — Push: registro de dispositivos y cola de envíos
--
-- POR QUÉ
-- Las notificaciones locales (recordar entrenar, el check, pesarse) las arma
-- el propio teléfono y alcanzan para lo que es previsible por calendario.
-- Pero lo que pasa del lado del coach —"te dejé un comentario", "te publiqué
-- la rutina nueva"— hoy no llega: el cliente se entera si abre la app por su
-- cuenta, o si Mati le escribe a mano por WhatsApp. Eso es push, y push
-- necesita saber a qué dispositivo mandarle.
--
-- DECISIONES
-- · Un cliente puede tener VARIOS dispositivos (iPhone + iPad). La clave es el
--   token del device, no el cliente: si guardáramos uno solo, instalar la app
--   en el iPad apagaría las notificaciones del teléfono sin avisar.
-- · Cola en tabla y no envío directo: el sender vive en la mini y puede estar
--   caído o sin red. Encolar deja el aviso pendiente en vez de perderlo, y
--   permite reintentar sin duplicar (estado + intentos).
-- · El token de APNs es un identificador de dispositivo, no un secreto del
--   usuario: igual va con RLS y solo se toca por RPC con token de acceso.
-- ============================================================

CREATE TABLE IF NOT EXISTS mypump_push_devices (
  id           bigserial PRIMARY KEY,
  cliente_id   text        NOT NULL,
  token        text        NOT NULL UNIQUE,   -- device token de APNs
  plataforma   text        NOT NULL DEFAULT 'ios',
  -- Para poder desactivar por versión si un build tiene un bug de push.
  app_version  text,
  activo       boolean     NOT NULL DEFAULT true,
  -- APNs responde 410 Gone cuando el usuario desinstaló: ahí se apaga.
  ultimo_error text,
  registrado_en timestamptz NOT NULL DEFAULT now(),
  visto_en      timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_push_devices_cliente
  ON mypump_push_devices (cliente_id) WHERE activo;

ALTER TABLE mypump_push_devices ENABLE ROW LEVEL SECURITY;
-- Sin políticas: solo entra por RPC SECURITY DEFINER. anon no lee ni escribe.

CREATE TABLE IF NOT EXISTS mypump_push_cola (
  id          bigserial PRIMARY KEY,
  cliente_id  text        NOT NULL,
  titulo      text        NOT NULL,
  cuerpo      text        NOT NULL,
  -- A dónde llevar al tocar la notificación ('comentarios', 'entreno'…).
  destino     text,
  -- Para no mandar dos veces lo mismo si el trigger corre de nuevo.
  dedupe_key  text UNIQUE,
  estado      text        NOT NULL DEFAULT 'pendiente'
              CHECK (estado IN ('pendiente','enviado','error','descartado')),
  intentos    integer     NOT NULL DEFAULT 0,
  error       text,
  creado_en   timestamptz NOT NULL DEFAULT now(),
  enviado_en  timestamptz
);

CREATE INDEX IF NOT EXISTS idx_push_cola_pendientes
  ON mypump_push_cola (creado_en) WHERE estado = 'pendiente';

ALTER TABLE mypump_push_cola ENABLE ROW LEVEL SECURITY;

-- ── Registrar el dispositivo (lo llama la app con su token de acceso) ──
CREATE OR REPLACE FUNCTION mypump_registrar_push(
  p_token       text,
  p_device      text,
  p_plataforma  text DEFAULT 'ios',
  p_app_version text DEFAULT NULL
) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_cliente text;
BEGIN
  SELECT cliente_id INTO v_cliente
  FROM mypump_tokens WHERE token = p_token AND revocado_en IS NULL;
  IF v_cliente IS NULL THEN RAISE EXCEPTION 'token invalido'; END IF;
  IF p_device IS NULL OR length(trim(p_device)) < 32 THEN RETURN false; END IF;

  INSERT INTO mypump_push_devices (cliente_id, token, plataforma, app_version)
  VALUES (v_cliente, trim(p_device), COALESCE(p_plataforma,'ios'), p_app_version)
  ON CONFLICT (token) DO UPDATE SET
    -- Si el mismo device pasa a otro cliente (prestó el teléfono, se re-vinculó),
    -- el token de APNs sigue siendo el mismo: hay que reasignarlo, no duplicar.
    cliente_id  = EXCLUDED.cliente_id,
    activo      = true,
    ultimo_error = NULL,
    app_version = COALESCE(EXCLUDED.app_version, mypump_push_devices.app_version),
    visto_en    = now();
  RETURN true;
END;
$$;

REVOKE ALL ON FUNCTION mypump_registrar_push(text, text, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION mypump_registrar_push(text, text, text, text) TO anon, authenticated;

-- ── Encolar un aviso (lo usa el Cerebro / el centinela con service key) ──
CREATE OR REPLACE FUNCTION mypump_encolar_push(
  p_cliente_id text,
  p_titulo     text,
  p_cuerpo     text,
  p_destino    text DEFAULT NULL,
  p_dedupe     text DEFAULT NULL
) RETURNS bigint
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_id bigint;
BEGIN
  IF p_cliente_id IS NULL OR p_titulo IS NULL OR p_cuerpo IS NULL THEN RETURN NULL; END IF;
  -- Sin dispositivo activo no tiene sentido encolar: se descarta en silencio.
  IF NOT EXISTS (SELECT 1 FROM mypump_push_devices WHERE cliente_id = p_cliente_id AND activo)
    THEN RETURN NULL; END IF;

  INSERT INTO mypump_push_cola (cliente_id, titulo, cuerpo, destino, dedupe_key)
  VALUES (p_cliente_id, left(p_titulo, 80), left(p_cuerpo, 240), p_destino, p_dedupe)
  ON CONFLICT (dedupe_key) DO NOTHING
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION mypump_encolar_push(text, text, text, text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION mypump_encolar_push(text, text, text, text, text) TO service_role;

-- ── Lo que el sender de la mini tiene que mandar ──
CREATE OR REPLACE FUNCTION mypump_push_pendientes(p_limite integer DEFAULT 50)
RETURNS TABLE (
  id bigint, cliente_id text, titulo text, cuerpo text, destino text,
  device_token text, plataforma text, intentos integer
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT c.id, c.cliente_id, c.titulo, c.cuerpo, c.destino,
         d.token, d.plataforma, c.intentos
  FROM mypump_push_cola c
  JOIN mypump_push_devices d ON d.cliente_id = c.cliente_id AND d.activo
  WHERE c.estado = 'pendiente'
    AND c.intentos < 4          -- 4 intentos y se da por perdido
  ORDER BY c.creado_en
  LIMIT LEAST(GREATEST(COALESCE(p_limite, 50), 1), 500);
END;
$$;

REVOKE ALL ON FUNCTION mypump_push_pendientes(integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION mypump_push_pendientes(integer) TO service_role;

-- ── Resultado del envío ──
CREATE OR REPLACE FUNCTION mypump_push_resultado(
  p_id           bigint,
  p_ok           boolean,
  p_error        text DEFAULT NULL,
  p_device_token text DEFAULT NULL,
  p_baja_device  boolean DEFAULT false
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF p_ok THEN
    UPDATE mypump_push_cola
       SET estado = 'enviado', enviado_en = now(), intentos = intentos + 1, error = NULL
     WHERE id = p_id;
  ELSE
    UPDATE mypump_push_cola
       SET intentos = intentos + 1,
           error = left(COALESCE(p_error,''), 300),
           -- Al 4º intento deja de ser 'pendiente' y sale de la cola.
           estado = CASE WHEN intentos + 1 >= 4 THEN 'error' ELSE 'pendiente' END
     WHERE id = p_id;
  END IF;

  -- APNs 410 Gone = la app ya no está en ese dispositivo. Se apaga para no
  -- seguir intentando contra un token muerto para siempre.
  IF p_baja_device AND p_device_token IS NOT NULL THEN
    UPDATE mypump_push_devices
       SET activo = false, ultimo_error = left(COALESCE(p_error,'410'), 200)
     WHERE token = p_device_token;
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION mypump_push_resultado(bigint, boolean, text, text, boolean) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION mypump_push_resultado(bigint, boolean, text, text, boolean) TO service_role;

-- ── Aviso automático cuando el coach deja un comentario ──
-- Es el caso que motivó todo esto: hoy el cliente no se entera hasta que abre
-- la app. El dedupe_key por id de comentario evita mandarlo dos veces.
CREATE OR REPLACE FUNCTION _mypump_push_on_comentario()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_titulo text;
BEGIN
  IF NEW.autor <> 'coach' THEN RETURN NEW; END IF;

  -- Si el comentario cuelga de algo concreto (un ejercicio, una comida), el
  -- título lo dice: "Mati comentó Press banca" ubica mucho mejor que un
  -- genérico, y el cliente entra sabiendo a qué.
  v_titulo := CASE
    WHEN NEW.referencia_nombre IS NOT NULL AND length(trim(NEW.referencia_nombre)) > 0
      THEN 'Mati comentó ' || left(NEW.referencia_nombre, 40)
    ELSE 'Mati te dejó un mensaje'
  END;

  PERFORM mypump_encolar_push(
    NEW.cliente_id,
    v_titulo,
    left(COALESCE(NEW.contenido, 'Entrá a verlo'), 140),
    'comentarios',
    'com-' || NEW.id::text
  );
  RETURN NEW;
END;
$$;

DO $$
BEGIN
  -- Se crea solo si la tabla tiene las columnas que el trigger usa. Este
  -- trigger es AFTER INSERT: si fallara, abortaría la inserción del comentario
  -- y el coach no podría comentar. Mejor no crearlo que romper eso.
  IF EXISTS (SELECT 1 FROM information_schema.columns
             WHERE table_name = 'mypump_comentarios' AND column_name = 'autor')
     AND EXISTS (SELECT 1 FROM information_schema.columns
             WHERE table_name = 'mypump_comentarios' AND column_name = 'contenido')
  THEN
    DROP TRIGGER IF EXISTS trg_push_comentario ON mypump_comentarios;
    CREATE TRIGGER trg_push_comentario
      AFTER INSERT ON mypump_comentarios
      FOR EACH ROW EXECUTE FUNCTION _mypump_push_on_comentario();
  END IF;
END $$;

-- Blindaje extra: que un fallo en el push JAMÁS impida comentar. Encolar es
-- accesorio; el comentario es el dato real. Se envuelve la llamada para que
-- cualquier excepción quede en el log y siga de largo.
CREATE OR REPLACE FUNCTION _mypump_push_on_comentario()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_titulo text;
BEGIN
  IF NEW.autor <> 'coach' THEN RETURN NEW; END IF;

  v_titulo := CASE
    WHEN NEW.referencia_nombre IS NOT NULL AND length(trim(NEW.referencia_nombre)) > 0
      THEN 'Mati comentó ' || left(NEW.referencia_nombre, 40)
    ELSE 'Mati te dejó un mensaje'
  END;

  BEGIN
    PERFORM mypump_encolar_push(
      NEW.cliente_id, v_titulo,
      left(COALESCE(NEW.contenido, 'Entrá a verlo'), 140),
      'comentarios', 'com-' || NEW.id::text
    );
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'push del comentario % fallo: %', NEW.id, SQLERRM;
  END;

  RETURN NEW;
END;
$$;
