-- =============================================================
-- 058_push_multiplataforma.sql — el timbre deja de perder avisos
--
-- POR QUÉ EXISTE
-- `mypump_push_devices` está VACÍA: cero dispositivos, ninguno de los 62
-- clientes puede recibir un push hoy. La infraestructura funciona (APNs
-- directo, JWT ES256, worker cada 5 min) pero nadie la usa, porque abren la
-- app como un link del navegador y ahí el plugin nativo no existe.
--
-- Con cero dispositivos, `mypump_encolar_push` (048:112) descarta el 100% de
-- los avisos EN SILENCIO: `IF NOT EXISTS (device activo) THEN RETURN NULL`.
-- No queda una fila, ni un log, ni una métrica. Si el chat se prendiera hoy,
-- cada mensaje de Mati se evaporaría sin dejar rastro y nadie se enteraría de
-- que el timbre nunca sonó.
--
-- QUÉ CAMBIA
--   1. El aviso sin dispositivo YA NO SE DESCARTA: queda en 'sin_device'.
--   2. Al registrar su primer dispositivo, lo de las últimas 12 h se RE-ARMA.
--      Instala la app y le entra el timbre que se había perdido. Es el mejor
--      empujón de instalación que hay y sale de una línea de SQL.
--   3. Lo que se pasó de 24 h en 'sin_device' se descarta. Que el martes no
--      llegue el timbre del domingo.
--   4. La tabla de dispositivos acepta suscripciones Web Push, que es lo que
--      cubre a TODOS los que hoy usan la versión web — incluido Android, sin
--      Firebase y sin esperar a que Google apruebe la cuenta.
--
-- LO QUE NO CAMBIA
-- El contrato del sender. `mypump_push_pendientes` sigue devolviendo solo lo
-- que se puede mandar de verdad, así que `push.py` no se entera de nada nuevo
-- hasta que se le agregue la rama web.
--
-- IDEMPOTENTE: se puede correr dos veces.
-- =============================================================

BEGIN;

-- ── 1. El estado nuevo ────────────────────────────────────────────────────
--
-- 'sin_device' NO es un error: es "esto está listo para cuando haya a dónde
-- mandarlo". Separarlo de 'error' importa porque son dos preguntas distintas:
-- "¿el envío falló?" y "¿cuánta gente no tiene la app?". La segunda es la
-- métrica de corte para automatizar el domingo.
ALTER TABLE mypump_push_cola DROP CONSTRAINT IF EXISTS mypump_push_cola_estado_check;
ALTER TABLE mypump_push_cola ADD CONSTRAINT mypump_push_cola_estado_check
  CHECK (estado IN ('pendiente','enviado','error','descartado','sin_device'));

CREATE INDEX IF NOT EXISTS idx_push_cola_sin_device
  ON mypump_push_cola (cliente_id, creado_en) WHERE estado = 'sin_device';

-- ── 2. Web Push en la tabla de dispositivos ───────────────────────────────
--
-- Una suscripción Web Push son tres cosas: el endpoint (la URL del servicio
-- del navegador) y dos claves para cifrar el contenido. El endpoint va en
-- `token`, que ya es UNIQUE — así la garantía de "un envío por aviso por
-- dispositivo" sigue valiendo igual para APNs y para web, sin tocar el índice.
ALTER TABLE mypump_push_devices ADD COLUMN IF NOT EXISTS p256dh text;
ALTER TABLE mypump_push_devices ADD COLUMN IF NOT EXISTS auth   text;

-- `plataforma` no tenía CHECK y se deja así a propósito: ponerle uno ahora
-- volvería a fallar el día que aparezca 'android'. Lo que sí se documenta es
-- el vocabulario: 'ios' (APNs), 'web' (Web Push), 'android' (FCM, fase 6).
COMMENT ON COLUMN mypump_push_devices.plataforma IS
  'ios = APNs · web = Web Push (token = endpoint) · android = FCM';
COMMENT ON COLUMN mypump_push_devices.p256dh IS 'Solo web: clave pública de la suscripción';
COMMENT ON COLUMN mypump_push_devices.auth   IS 'Solo web: secreto de autenticación de la suscripción';

-- ── 3. Encolar ya no descarta nunca ───────────────────────────────────────
CREATE OR REPLACE FUNCTION mypump_encolar_push(
  p_cliente_id text,
  p_titulo     text,
  p_cuerpo     text,
  p_destino    text DEFAULT NULL,
  p_dedupe     text DEFAULT NULL
) RETURNS bigint
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_id     bigint;
  v_estado text;
BEGIN
  IF p_cliente_id IS NULL OR p_titulo IS NULL OR p_cuerpo IS NULL THEN RETURN NULL; END IF;

  -- Antes acá había un RETURN NULL. Con la tabla de dispositivos vacía, eso
  -- significaba tirar el 100% de los avisos sin dejar rastro.
  v_estado := CASE
    WHEN EXISTS (SELECT 1 FROM mypump_push_devices WHERE cliente_id = p_cliente_id AND activo)
    THEN 'pendiente' ELSE 'sin_device' END;

  INSERT INTO mypump_push_cola (cliente_id, titulo, cuerpo, destino, dedupe_key, estado)
  VALUES (p_cliente_id, left(p_titulo, 80), left(p_cuerpo, 240), p_destino, p_dedupe, v_estado)
  ON CONFLICT (dedupe_key) DO NOTHING
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION mypump_encolar_push(text, text, text, text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION mypump_encolar_push(text, text, text, text, text) TO service_role;

-- ── 4. Registrar un dispositivo re-arma lo que se había perdido ───────────
--
-- La ventana de 12 h es la parte pensada. Sin ella, alguien que instala la app
-- un jueves recibiría de golpe el pedido de revisión del domingo pasado, que
-- ya no aplica. Con ella, recibe lo de hoy y nada más.
CREATE OR REPLACE FUNCTION _mypump_push_rearmar(p_cliente_id text)
RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_n integer;
BEGIN
  UPDATE mypump_push_cola
     SET estado = 'pendiente'
   WHERE cliente_id = p_cliente_id
     AND estado = 'sin_device'
     AND creado_en > now() - interval '12 hours';
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END;
$$;

REVOKE ALL ON FUNCTION _mypump_push_rearmar(text) FROM PUBLIC, anon, authenticated;

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
  v_cliente := mypump_get_cliente_id_from_token(p_token);
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
    plataforma  = EXCLUDED.plataforma,
    app_version = COALESCE(EXCLUDED.app_version, mypump_push_devices.app_version),
    visto_en    = now();

  PERFORM _mypump_push_rearmar(v_cliente);
  RETURN true;
END;
$$;

REVOKE ALL ON FUNCTION mypump_registrar_push(text, text, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION mypump_registrar_push(text, text, text, text) TO anon, authenticated;

-- ── 5. Registrar una suscripción Web Push ────────────────────────────────
--
-- Función aparte y no un parámetro más en la de arriba: agregarle argumentos a
-- `mypump_registrar_push` crearía una sobrecarga, y con sobrecargas PostgREST
-- tiene que adivinar cuál llamar según el JSON que le mandan. Cuando adivina
-- mal, el error que devuelve no dice nada útil.
CREATE OR REPLACE FUNCTION mypump_registrar_push_web(
  p_token    text,
  p_endpoint text,
  p_p256dh   text,
  p_auth     text
) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_cliente text;
BEGIN
  v_cliente := mypump_get_cliente_id_from_token(p_token);
  IF v_cliente IS NULL THEN RAISE EXCEPTION 'token invalido'; END IF;
  IF p_endpoint IS NULL OR p_endpoint !~ '^https://' THEN RETURN false; END IF;
  IF p_p256dh IS NULL OR p_auth IS NULL THEN RETURN false; END IF;

  INSERT INTO mypump_push_devices (cliente_id, token, plataforma, p256dh, auth)
  VALUES (v_cliente, p_endpoint, 'web', p_p256dh, p_auth)
  ON CONFLICT (token) DO UPDATE SET
    cliente_id   = EXCLUDED.cliente_id,
    activo       = true,
    ultimo_error = NULL,
    plataforma   = 'web',
    -- Las claves se renuevan solas cuando el navegador rota la suscripción.
    -- Si no se pisaran, el cifrado fallaría con un 400 imposible de leer.
    p256dh       = EXCLUDED.p256dh,
    auth         = EXCLUDED.auth,
    visto_en     = now();

  PERFORM _mypump_push_rearmar(v_cliente);
  RETURN true;
END;
$$;

REVOKE ALL ON FUNCTION mypump_registrar_push_web(text, text, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION mypump_registrar_push_web(text, text, text, text) TO anon, authenticated;

-- ── 6. El sender recibe lo que necesita para cada transporte ─────────────
--
-- Se le agregan las tres columnas de web al final. Agregar al FINAL importa:
-- `push.py` lee por nombre, pero cualquier consumidor que lea por posición
-- sigue funcionando igual.
--
-- Y acá se hace el GC, aprovechando que el worker la llama cada 5 minutos: un
-- cron aparte para esto sería una pieza más que se puede caer sola y en
-- silencio, para una tarea que dura milisegundos.
DROP FUNCTION IF EXISTS mypump_push_pendientes(integer);
CREATE FUNCTION mypump_push_pendientes(p_limite integer DEFAULT 50)
RETURNS TABLE (
  id bigint, cliente_id text, titulo text, cuerpo text, destino text,
  device_token text, plataforma text, intentos integer,
  p256dh text, auth text
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  -- Lo que lleva más de un día esperando un dispositivo ya no sirve: si el
  -- cliente instala la app el miércoles, el pedido de revisión del domingo le
  -- llegaría como un fantasma.
  UPDATE mypump_push_cola
     SET estado = 'descartado', error = 'sin dispositivo por mas de 24h'
   WHERE estado = 'sin_device' AND creado_en < now() - interval '24 hours';

  RETURN QUERY
  SELECT c.id, c.cliente_id, c.titulo, c.cuerpo, c.destino,
         d.token, d.plataforma, c.intentos, d.p256dh, d.auth
  FROM mypump_push_cola c
  JOIN mypump_push_devices d ON d.cliente_id = c.cliente_id AND d.activo
  WHERE c.estado = 'pendiente'      -- 'sin_device' NO entra: no hay a dónde mandarlo
    AND c.intentos < 4              -- 4 intentos y se da por perdido
  ORDER BY c.creado_en
  LIMIT LEAST(GREATEST(COALESCE(p_limite, 50), 1), 500);
END;
$$;

REVOKE ALL ON FUNCTION mypump_push_pendientes(integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION mypump_push_pendientes(integer) TO service_role;

-- ── 7. Cuánta gente puede recibir un timbre ──────────────────────────────
--
-- La métrica de corte para automatizar el domingo. Debajo de ~60% con
-- dispositivo, la ronda todavía necesita el respaldo por WhatsApp, y eso hay
-- que poder mirarlo sin escribir una consulta a mano cada vez.
CREATE OR REPLACE FUNCTION mypump_push_cobertura()
RETURNS TABLE (
  clientes_activos    integer,
  con_device          integer,
  por_plataforma      jsonb,
  avisos_sin_device_7d integer
)
LANGUAGE sql SECURITY DEFINER SET search_path = public
AS $$
  SELECT
    (SELECT count(*)::integer FROM mypump_clientes WHERE access_token_active),
    (SELECT count(DISTINCT cliente_id)::integer FROM mypump_push_devices WHERE activo),
    (SELECT COALESCE(jsonb_object_agg(plataforma, n), '{}'::jsonb)
       FROM (SELECT plataforma, count(*) AS n FROM mypump_push_devices WHERE activo GROUP BY 1) t),
    (SELECT count(*)::integer FROM mypump_push_cola
      WHERE estado IN ('sin_device','descartado') AND creado_en > now() - interval '7 days');
$$;

REVOKE ALL ON FUNCTION mypump_push_cobertura() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION mypump_push_cobertura() TO authenticated, service_role;

COMMIT;
