-- ============================================================
-- 057 — Cimientos del chat cliente ↔ Mati
--
-- POR QUÉ
-- Hoy Mati le pide la revisión semanal a cada uno de sus 62 clientes por
-- WhatsApp, de a uno, todos los domingos. Eso le abre ~60 conversaciones que
-- terminan el jueves. El chat dentro de la app es lo que corta eso.
--
-- No se crea una tabla nueva: `mypump_comentarios` ya es bidireccional
-- (`autor IN ('cliente','coach')`), su CHECK de `ambito` YA acepta 'general'
-- (018:28), y las RPC del cliente y la del coach ya existen. Una tabla nueva
-- dejaría a Mati con DOS bandejas: la del chat y la de los comentarios por
-- ejercicio, que hoy tampoco lee nadie. Una sola tabla es una sola bandeja, y
-- eso es el producto.
--
-- ⚠ LO PRIMERO Y LO MÁS IMPORTANTE DE ESTE ARCHIVO
-- El trigger de 019 le manda un WhatsApp a Mati por CADA comentario de
-- cliente. Con el chat prendido eso son ~60 WhatsApps por semana: la feature
-- reproduciendo exactamente el problema que viene a matar. Hay que excluir
-- 'general' ANTES de que exista un solo mensaje de chat, no después.
--
-- ROLLBACK al final del archivo.
-- ============================================================

-- ── 1. El trigger de WhatsApp deja de disparar con el chat ──
--
-- Los comentarios por ejercicio siguen avisando igual: son pocos y puntuales.
-- El chat no, porque para eso está la bandeja del Cerebro.
CREATE OR REPLACE FUNCTION mypump_notify_coach_comentario()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_secret TEXT;
BEGIN
  -- 'general' = chat. Ver la cabecera: sin este AND, 60 clientes chateando son
  -- 60 WhatsApps por semana al teléfono de Mati.
  IF NEW.autor = 'cliente' AND NEW.ambito <> 'general' THEN
    SELECT decrypted_secret INTO v_secret
      FROM vault.decrypted_secrets
     WHERE name = 'mypump_notify_secret'
     LIMIT 1;

    PERFORM net.http_post(
      url     := 'https://bot.mypumpteam.com/mypump/comentario',
      headers := jsonb_build_object(
                   'Content-Type',   'application/json',
                   'X-Mypump-Secret', COALESCE(v_secret, '')
                 ),
      body    := jsonb_build_object(
                   'comentario_id',     NEW.id,
                   'cliente_id',        NEW.cliente_id,
                   'ambito',            NEW.ambito,
                   'referencia_id',     NEW.referencia_id,
                   'referencia_nombre', NEW.referencia_nombre,
                   'contenido',         NEW.contenido,
                   'autor',             NEW.autor
                 )
    );
  END IF;
  RETURN NEW;
END;
$$;

-- ── 2. Columnas de auditoría ──
--
-- `autor` sigue siendo 'coach' para que el cliente vea "Mati" y nada más.
-- `origen` es lo que ve Mati en la bandeja: quién escribió de verdad.
ALTER TABLE mypump_comentarios
  ADD COLUMN IF NOT EXISTS origen TEXT NOT NULL DEFAULT 'humano',
  ADD COLUMN IF NOT EXISTS meta   JSONB;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'mypump_comentarios_origen_check') THEN
    ALTER TABLE mypump_comentarios
      ADD CONSTRAINT mypump_comentarios_origen_check
      CHECK (origen IN ('humano', 'ia', 'sistema'));
  END IF;
END $$;

-- ── 3. Índices ──
--
-- La tabla solo tenía el índice de (cliente_id, ambito, referencia_id), que
-- servía para el acordeón de un ejercicio. Un chat ordenado por fecha y una
-- bandeja de no leídos son consultas distintas y hoy serían seq scan.
CREATE INDEX IF NOT EXISTS idx_mypump_comentarios_fecha
  ON mypump_comentarios (cliente_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_mypump_comentarios_pendientes_coach
  ON mypump_comentarios (cliente_id, created_at DESC)
  WHERE leido_por_coach = FALSE AND autor = 'cliente';

CREATE INDEX IF NOT EXISTS idx_mypump_comentarios_chat
  ON mypump_comentarios (cliente_id, created_at DESC)
  WHERE ambito = 'general';

-- ── 4. Idempotencia de la IA, garantizada por la base ──
--
-- El worker de IA (fase 4) responde mensajes de a tandas. Si muere después de
-- generar y antes de reportar, al reiniciar vuelve a ver el mensaje sin
-- respuesta y contesta DE NUEVO — el cliente recibe dos veces lo mismo, con
-- distinta redacción, y ahí se cae la ilusión de que hay una persona.
--
-- Esto no se "mitiga" en el worker: se hace imposible acá. Mismo criterio que
-- el `dedupe_key UNIQUE` de la cola de push (048:51).
CREATE UNIQUE INDEX IF NOT EXISTS idx_mypump_comentarios_respuesta_unica
  ON mypump_comentarios ((meta->>'respuesta_a'))
  WHERE meta ? 'respuesta_a';

-- ── 5. Estado de la CONVERSACIÓN (no del mensaje) ──
--
-- La bandeja tiene que ordenar 62 hilos por "quién está esperando respuesta"
-- sin agregar sobre toda la tabla de comentarios en cada refresco. Y Mati
-- necesita un interruptor por cliente para apagar la IA cuando quiere atender
-- él una conversación.
CREATE TABLE IF NOT EXISTS mypump_chat_estado (
  cliente_id            TEXT PRIMARY KEY,
  ultimo_msg_cliente_at TIMESTAMPTZ,
  ultimo_msg_coach_at   TIMESTAMPTZ,
  no_leidos_coach       INTEGER     NOT NULL DEFAULT 0,
  -- Interruptor por cliente. Cuando Mati "toma" la conversación, la IA deja de
  -- contestarle a esa persona hasta que él la suelte.
  ia_activa             BOOLEAN     NOT NULL DEFAULT TRUE,
  escalado              BOOLEAN     NOT NULL DEFAULT FALSE,
  escalado_motivo       TEXT,
  escalado_at           TIMESTAMPTZ,
  -- Corta los recordatorios del martes/jueves sin tener que borrar nada.
  silenciado_hasta      TIMESTAMPTZ,
  updated_at            TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE mypump_chat_estado ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "admin all mypump_chat_estado" ON mypump_chat_estado;
CREATE POLICY "admin all mypump_chat_estado" ON mypump_chat_estado
  FOR ALL USING (auth.role() = 'authenticated')
  WITH CHECK (auth.role() = 'authenticated');

CREATE INDEX IF NOT EXISTS idx_mypump_chat_estado_bandeja
  ON mypump_chat_estado (escalado DESC, no_leidos_coach DESC, ultimo_msg_cliente_at DESC NULLS LAST);

-- Se mantiene solo, en el mismo INSERT del mensaje. Así la bandeja lee una
-- tabla de 62 filas en vez de agregar sobre miles de comentarios.
CREATE OR REPLACE FUNCTION _mypump_chat_estado_upsert()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NEW.ambito <> 'general' THEN RETURN NEW; END IF;

  INSERT INTO mypump_chat_estado (
    cliente_id, ultimo_msg_cliente_at, ultimo_msg_coach_at, no_leidos_coach, updated_at)
  VALUES (
    NEW.cliente_id,
    CASE WHEN NEW.autor = 'cliente' THEN NEW.created_at END,
    CASE WHEN NEW.autor = 'coach'   THEN NEW.created_at END,
    CASE WHEN NEW.autor = 'cliente' THEN 1 ELSE 0 END,
    NOW())
  ON CONFLICT (cliente_id) DO UPDATE SET
    ultimo_msg_cliente_at = CASE WHEN NEW.autor = 'cliente'
                                 THEN NEW.created_at ELSE mypump_chat_estado.ultimo_msg_cliente_at END,
    ultimo_msg_coach_at   = CASE WHEN NEW.autor = 'coach'
                                 THEN NEW.created_at ELSE mypump_chat_estado.ultimo_msg_coach_at END,
    no_leidos_coach       = CASE WHEN NEW.autor = 'cliente'
                                 THEN mypump_chat_estado.no_leidos_coach + 1
                                 ELSE mypump_chat_estado.no_leidos_coach END,
    updated_at            = NOW();

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_mypump_chat_estado ON mypump_comentarios;
CREATE TRIGGER trg_mypump_chat_estado
  AFTER INSERT ON mypump_comentarios
  FOR EACH ROW EXECUTE FUNCTION _mypump_chat_estado_upsert();

-- ── 6. RPC del cliente: el chat, paginado ──
--
-- `mypump_get_comentarios` (018:89) NO tiene LIMIT y se llama entera en cada
-- arranque de la app. Con el chat prendido eso pasa a ser la llamada más cara
-- del bootstrap. No se toca —hay código vivo que la usa— y se agrega esta.
CREATE OR REPLACE FUNCTION mypump_get_chat(
  p_token  TEXT,
  p_antes  TIMESTAMPTZ DEFAULT NULL,
  p_limite INTEGER     DEFAULT 30
)
RETURNS TABLE(
  id                UUID,
  autor             TEXT,
  contenido         TEXT,
  leido_por_cliente BOOLEAN,
  created_at        TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_cliente_id TEXT;
  v_limite     INTEGER;
BEGIN
  v_cliente_id := mypump_get_cliente_id_from_token(p_token);
  IF v_cliente_id IS NULL THEN RETURN; END IF;

  -- Tope defensivo: la función es anon y el límite viene del cliente.
  v_limite := LEAST(GREATEST(COALESCE(p_limite, 30), 1), 100);

  RETURN QUERY
  SELECT c.id, c.autor, c.contenido, c.leido_por_cliente, c.created_at
  FROM mypump_comentarios c
  WHERE c.cliente_id = v_cliente_id
    AND c.ambito = 'general'
    AND (p_antes IS NULL OR c.created_at < p_antes)
  ORDER BY c.created_at DESC
  LIMIT v_limite;
END;
$$;

-- ── 7. RPC del cliente: el poll incremental ──
--
-- Se llama cada 15-45 s con la app abierta. Cuando no hay nada nuevo devuelve
-- cero filas, que son ~200 bytes. Con 62 clientes eso es ruido estadístico.
--
-- Es polling y no Realtime a propósito: la tabla es deny-all RLS y todo el
-- acceso anon entra por RPC SECURITY DEFINER que validan el token adentro.
-- Realtime no pasa por RPC, filtra por RLS con el JWT — y acá el JWT es la
-- anon key, compartida por los 62. Habilitarlo bien exigiría un JWT por
-- cliente, o sea rediseñar la auth entera.
CREATE OR REPLACE FUNCTION mypump_chat_nuevos(
  p_token TEXT,
  p_desde TIMESTAMPTZ
)
RETURNS TABLE(
  id         UUID,
  autor      TEXT,
  contenido  TEXT,
  created_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_cliente_id TEXT;
BEGIN
  v_cliente_id := mypump_get_cliente_id_from_token(p_token);
  IF v_cliente_id IS NULL THEN RETURN; END IF;

  RETURN QUERY
  SELECT c.id, c.autor, c.contenido, c.created_at
  FROM mypump_comentarios c
  WHERE c.cliente_id = v_cliente_id
    AND c.ambito = 'general'
    AND c.created_at > COALESCE(p_desde, NOW() - INTERVAL '30 days')
  ORDER BY c.created_at ASC
  LIMIT 50;
END;
$$;

-- ── 8. RPC del coach: marcar leído ──
--
-- `leido_por_coach` existe desde 018 y NADIE la escribe nunca. Sin esto la
-- bandeja no puede distinguir lo atendido de lo pendiente.
CREATE OR REPLACE FUNCTION mypump_marcar_leidos_coach(p_cliente_id TEXT)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_n INTEGER;
BEGIN
  IF auth.role() NOT IN ('authenticated', 'service_role') THEN
    RAISE EXCEPTION 'Acceso denegado';
  END IF;

  UPDATE mypump_comentarios
     SET leido_por_coach = TRUE, updated_at = NOW()
   WHERE cliente_id = p_cliente_id
     AND autor = 'cliente'
     AND leido_por_coach = FALSE;
  GET DIAGNOSTICS v_n = ROW_COUNT;

  UPDATE mypump_chat_estado
     SET no_leidos_coach = 0, updated_at = NOW()
   WHERE cliente_id = p_cliente_id;

  RETURN v_n;
END;
$$;

-- ── 9. RPC del coach: escribir, con auditoría ──
--
-- La v1 (018:165) queda intacta: hay grants y llamadores potenciales colgando
-- de esa firma. Esta agrega `origen` y `meta`, que es lo que necesita el
-- worker de IA para dejar rastro y para no contestar dos veces.
CREATE OR REPLACE FUNCTION mypump_coach_comentar_v2(
  p_cliente_id        TEXT,
  p_contenido         TEXT,
  p_ambito            TEXT  DEFAULT 'general',
  p_referencia_id     TEXT  DEFAULT NULL,
  p_referencia_nombre TEXT  DEFAULT NULL,
  p_origen            TEXT  DEFAULT 'humano',
  p_meta              JSONB DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_id UUID;
BEGIN
  IF auth.role() NOT IN ('authenticated', 'service_role') THEN
    RAISE EXCEPTION 'Acceso denegado';
  END IF;
  IF p_contenido IS NULL OR length(trim(p_contenido)) = 0 THEN
    RETURN NULL;
  END IF;

  INSERT INTO mypump_comentarios (
    cliente_id, ambito, referencia_id, referencia_nombre,
    autor, contenido, leido_por_cliente, leido_por_coach, origen, meta)
  VALUES (
    p_cliente_id, p_ambito, p_referencia_id, p_referencia_nombre,
    'coach', trim(p_contenido), FALSE, TRUE, p_origen, p_meta)
  RETURNING id INTO v_id;

  RETURN v_id;
EXCEPTION
  -- El índice único de respuesta_a saltó: alguien ya contestó ese mensaje.
  -- No es un error, es la garantía funcionando. Se devuelve NULL y el worker
  -- sigue de largo.
  WHEN unique_violation THEN
    RETURN NULL;
END;
$$;

-- ── 10. El push del chat abre el chat ──
--
-- El trigger mandaba `destino='comentarios'` y el handler del cliente hace
-- setScene(destino). La escena 'comentarios' NO EXISTE (son train, diet,
-- progress, myday, revision, salud): tocar la notificación abría la app y no
-- navegaba a ningún lado. Ahora existe 'chat' y el destino apunta ahí.
--
-- Y para el chat el título deja de ser "Mati comentó <ejercicio>": es "Mati",
-- que es lo que uno espera ver cuando le escribe una persona.
CREATE OR REPLACE FUNCTION _mypump_push_on_comentario()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_titulo  text;
  v_destino text;
BEGIN
  IF NEW.autor <> 'coach' THEN RETURN NEW; END IF;

  IF NEW.ambito = 'general' THEN
    v_titulo  := 'Mati';
    v_destino := 'chat';
  ELSE
    v_destino := 'chat';
    v_titulo := CASE
      WHEN NEW.referencia_nombre IS NOT NULL AND length(trim(NEW.referencia_nombre)) > 0
        THEN 'Mati comentó ' || left(NEW.referencia_nombre, 40)
      ELSE 'Mati te dejó un mensaje'
    END;
  END IF;

  BEGIN
    PERFORM mypump_encolar_push(
      NEW.cliente_id, v_titulo,
      left(COALESCE(NEW.contenido, 'Entrá a verlo'), 140),
      v_destino, 'com-' || NEW.id::text
    );
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'push del comentario % fallo: %', NEW.id, SQLERRM;
  END;

  RETURN NEW;
END;
$$;

-- ── 11. Permisos ──
--
-- Las del cliente son anon porque el token ES la credencial, igual que el
-- resto de las RPC de la app. Las del coach, nunca anon.
REVOKE ALL ON FUNCTION mypump_get_chat(TEXT, TIMESTAMPTZ, INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION mypump_get_chat(TEXT, TIMESTAMPTZ, INTEGER)
  TO anon, authenticated, service_role;

REVOKE ALL ON FUNCTION mypump_chat_nuevos(TEXT, TIMESTAMPTZ) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION mypump_chat_nuevos(TEXT, TIMESTAMPTZ)
  TO anon, authenticated, service_role;

REVOKE ALL ON FUNCTION mypump_marcar_leidos_coach(TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION mypump_marcar_leidos_coach(TEXT)
  TO authenticated, service_role;

REVOKE ALL ON FUNCTION mypump_coach_comentar_v2(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, JSONB)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION mypump_coach_comentar_v2(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, JSONB)
  TO authenticated, service_role;

GRANT SELECT, INSERT, UPDATE ON mypump_chat_estado TO authenticated, service_role;

-- ============================================================
-- VERIFICACIÓN
--   -- 1. un mensaje de chat NO dispara el WhatsApp a Mati:
--   SELECT prosrc LIKE '%ambito <> ''general''%'
--     FROM pg_proc WHERE proname = 'mypump_notify_coach_comentario';   -- true
--
--   -- 2. no se puede contestar dos veces el mismo mensaje:
--   SELECT mypump_coach_comentar_v2('cid','hola','general',NULL,NULL,'ia',
--            '{"respuesta_a":"<uuid>"}'::jsonb);   -- uuid la 1ª, NULL la 2ª
--
--   -- 3. el estado se mantiene solo:
--   SELECT * FROM mypump_chat_estado WHERE cliente_id = 'cid';
--
-- ROLLBACK
--   DROP TRIGGER IF EXISTS trg_mypump_chat_estado ON mypump_comentarios;
--   DROP FUNCTION IF EXISTS _mypump_chat_estado_upsert();
--   DROP TABLE IF EXISTS mypump_chat_estado;
--   DROP FUNCTION IF EXISTS mypump_get_chat(TEXT, TIMESTAMPTZ, INTEGER);
--   DROP FUNCTION IF EXISTS mypump_chat_nuevos(TEXT, TIMESTAMPTZ);
--   DROP FUNCTION IF EXISTS mypump_marcar_leidos_coach(TEXT);
--   DROP FUNCTION IF EXISTS mypump_coach_comentar_v2(TEXT,TEXT,TEXT,TEXT,TEXT,TEXT,JSONB);
--   DROP INDEX IF EXISTS idx_mypump_comentarios_respuesta_unica;
--   DROP INDEX IF EXISTS idx_mypump_comentarios_chat;
--   DROP INDEX IF EXISTS idx_mypump_comentarios_pendientes_coach;
--   DROP INDEX IF EXISTS idx_mypump_comentarios_fecha;
--   ALTER TABLE mypump_comentarios DROP COLUMN IF EXISTS meta, DROP COLUMN IF EXISTS origen;
--   -- y volver a aplicar 019 y 048 para restaurar los dos triggers.
-- ============================================================
