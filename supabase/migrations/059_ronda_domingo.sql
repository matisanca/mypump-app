-- =============================================================
-- 059_ronda_domingo.sql — el domingo deja de ser trabajo manual
--
-- POR QUÉ EXISTE
-- Hoy `centinela.py --pedido` redacta el mensaje del domingo y se lo manda A
-- MATI, con la cabecera literal `_Mandaselo a la lista de difusion:_`. En todo
-- el sistema NO EXISTE un camino que le mande un mensaje a un cliente:
-- `send_whatsapp()` postea a Meta con `to = COACH_PHONE_NUMBER` hardcodeado.
-- Así que el domingo a la noche Mati copia, pega y manda 62 veces, y eso le
-- abre ~60 conversaciones que terminan el jueves.
--
-- Con el chat de la 057, el mensaje ya tiene a dónde ir. Falta la pieza que lo
-- ponga ahí sin que él toque nada.
--
-- LO QUE HACE ESTA MIGRACIÓN
--   1. Una agenda: `mypump_chat_programados`. El centinela NO escribe los 62
--      mensajes de una; los programa repartidos en 40-60 minutos.
--   2. Un drenador que publica lo que ya venció, con una ventana horaria dura.
--   3. Una consulta que dice quién falta esta semana, del lado servidor, para
--      que los recordatorios del martes y el jueves CORTEN SOLOS.
--
-- POR QUÉ ESCALONADO Y NO TODO JUNTO
-- Un humano no manda 62 mensajes en el mismo segundo. Si los 62 llegan a las
-- 18:00:00 clavadas, la ilusión de que hay una persona del otro lado se cae en
-- la primera captura de pantalla que dos clientes comparen. Y de paso aplana el
-- pico de respuestas, que es lo que después tiene que atender la IA.
--
-- IDEMPOTENTE: se puede correr dos veces.
-- =============================================================

BEGIN;

-- ── 1. La agenda ─────────────────────────────────────────────────────────
--
-- `dedupe_key` UNIQUE es lo que hace que re-correr el domingo no duplique
-- nada. Mismo criterio que la cola de push: la garantía vive en el índice, no
-- en un `IF NOT EXISTS` del script que la puede saltear una condición de
-- carrera.
CREATE TABLE IF NOT EXISTS mypump_chat_programados (
  id              bigserial PRIMARY KEY,
  cliente_id      text        NOT NULL,
  contenido       text        NOT NULL,
  programado_para timestamptz NOT NULL,
  dedupe_key      text        UNIQUE,
  -- 'pendiente' → 'publicado' | 'cancelado'. Cancelado es lo que pasa cuando
  -- el cliente hizo lo que se le iba a pedir ANTES de que le llegue el pedido.
  estado          text        NOT NULL DEFAULT 'pendiente'
                  CHECK (estado IN ('pendiente','publicado','cancelado')),
  motivo          text,
  creado_en       timestamptz NOT NULL DEFAULT now(),
  publicado_en    timestamptz
);

CREATE INDEX IF NOT EXISTS idx_chat_prog_vencidos
  ON mypump_chat_programados (programado_para) WHERE estado = 'pendiente';

ALTER TABLE mypump_chat_programados ENABLE ROW LEVEL SECURITY;
-- Sin políticas: solo entra por RPC SECURITY DEFINER. El cliente no lo ve nunca
-- — ver un mensaje "programado para las 18:47" rompería toda la ilusión.

-- ── 2. Programar ─────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION mypump_chat_programar(
  p_cliente_id text,
  p_contenido  text,
  p_cuando     timestamptz,
  p_dedupe     text DEFAULT NULL
) RETURNS bigint
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_id bigint;
BEGIN
  IF p_cliente_id IS NULL OR p_contenido IS NULL OR length(trim(p_contenido)) = 0
    THEN RETURN NULL; END IF;

  INSERT INTO mypump_chat_programados (cliente_id, contenido, programado_para, dedupe_key)
  VALUES (p_cliente_id, trim(p_contenido), COALESCE(p_cuando, now()), p_dedupe)
  ON CONFLICT (dedupe_key) DO NOTHING
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION mypump_chat_programar(text, text, timestamptz, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION mypump_chat_programar(text, text, timestamptz, text) TO service_role;

-- ── 3. Quién falta esta semana ───────────────────────────────────────────
--
-- Los recordatorios del martes y el jueves cortan solos PORQUE SON UNA
-- CONSULTA, no una máquina de estados. Se recalcula lo mismo que
-- `_pendientesSemana()` hace en la app (cliente.html:6826): falta el check, o
-- faltan fotos. Si el cliente ya subió, no aparece acá y no se le manda nada.
--
-- Con flags ("ya se le avisó") habría que acordarse de apagarlos, y el día que
-- uno se desincronice el cliente recibe un recordatorio de algo que ya hizo —
-- que es la forma más rápida de que deje de leer los mensajes.
CREATE OR REPLACE FUNCTION mypump_chat_faltantes_semana()
RETURNS TABLE (
  cliente_id   text,
  nombre       text,
  falta_check  boolean,
  fotos_puestas integer,
  avisos_semana integer,
  ia_activa    boolean,
  escalado     boolean,
  silenciado   boolean
)
LANGUAGE sql SECURITY DEFINER SET search_path = public
AS $$
  WITH lunes AS (SELECT (date_trunc('week', now() AT TIME ZONE 'America/Argentina/Buenos_Aires'))::date AS d)
  SELECT
    c.cliente_id,
    c.nombre,
    NOT EXISTS (SELECT 1 FROM mypump_checkin_semanal k, lunes
                 WHERE k.cliente_id = c.cliente_id AND k.semana_lunes = lunes.d),
    (SELECT count(DISTINCT f.pose)::integer FROM mypump_fotos_progreso f, lunes
      WHERE f.cliente_id = c.cliente_id AND f.semana_lunes = lunes.d),
    -- Tope duro: 3 mensajes del coach por semana. Sin esto, alguien que nunca
    -- sube nada recibiría el domingo, el martes y el jueves TODAS las semanas,
    -- y eso no es seguimiento, es hostigamiento.
    (SELECT count(*)::integer FROM mypump_comentarios m, lunes
      WHERE m.cliente_id = c.cliente_id AND m.ambito = 'general' AND m.autor = 'coach'
        AND m.created_at >= lunes.d),
    COALESCE(e.ia_activa, TRUE),
    COALESCE(e.escalado, FALSE),
    COALESCE(e.silenciado_hasta > now(), FALSE)
  FROM mypump_clientes c
  LEFT JOIN mypump_chat_estado e ON e.cliente_id = c.cliente_id
  WHERE c.access_token_active
    -- Los sintéticos del banco de pruebas no reciben mensajes. Misma red que
    -- usan el centinela y el Radar.
    AND c.cliente_id NOT LIKE 'test%'
    AND lower(COALESCE(c.nombre,'')) NOT LIKE '%test%';
$$;

REVOKE ALL ON FUNCTION mypump_chat_faltantes_semana() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION mypump_chat_faltantes_semana() TO authenticated, service_role;

-- ── 4. El drenador ───────────────────────────────────────────────────────
--
-- Publica lo que ya venció. Se llama cada pocos minutos.
--
-- La ventana horaria es una regla de producto, no un detalle: un mensaje de
-- "Mati" a las 4 de la mañana es la delación más grande que existe. Fuera de
-- la ventana NO se publica y NO se cancela — se queda esperando a mañana.
CREATE OR REPLACE FUNCTION mypump_chat_drenar(p_limite integer DEFAULT 20)
RETURNS TABLE (cliente_id text, publicado boolean, motivo text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  r      record;
  v_hora integer;
BEGIN
  v_hora := EXTRACT(hour FROM (now() AT TIME ZONE 'America/Argentina/Buenos_Aires'))::integer;
  -- 08:00 a 22:59. Fuera de eso el drenador no hace nada y vuelve mañana.
  IF v_hora < 8 OR v_hora >= 23 THEN RETURN; END IF;

  FOR r IN
    SELECT * FROM mypump_chat_programados
     WHERE estado = 'pendiente' AND programado_para <= now()
     ORDER BY programado_para
     LIMIT LEAST(GREATEST(COALESCE(p_limite, 20), 1), 200)
    -- Sin esto, dos corridas del drenador que se pisen publicarían el mismo
    -- mensaje dos veces: el UPDATE de abajo llega tarde.
    FOR UPDATE SKIP LOCKED
  LOOP
    -- Última chance de no molestar: si entre que se programó y ahora el cliente
    -- fue escalado o Mati tomó la conversación, el mensaje enlatado sobra.
    IF EXISTS (SELECT 1 FROM mypump_chat_estado e
                WHERE e.cliente_id = r.cliente_id
                  AND (e.escalado OR e.silenciado_hasta > now())) THEN
      UPDATE mypump_chat_programados
         SET estado = 'cancelado', motivo = 'escalado o silenciado' WHERE id = r.id;
      cliente_id := r.cliente_id; publicado := FALSE; motivo := 'escalado o silenciado';
      RETURN NEXT; CONTINUE;
    END IF;

    -- El INSERT dispara los dos triggers que ya existen: el de push (que ahora
    -- nunca descarta, mig 058) y el de mypump_chat_estado.
    INSERT INTO mypump_comentarios (
      cliente_id, ambito, referencia_id, referencia_nombre,
      autor, contenido, leido_por_cliente, leido_por_coach, origen, meta)
    VALUES (
      r.cliente_id, 'general', NULL, NULL,
      'coach', r.contenido, FALSE, TRUE, 'sistema',
      jsonb_build_object('programado_id', r.id));

    UPDATE mypump_chat_programados
       SET estado = 'publicado', publicado_en = now() WHERE id = r.id;

    cliente_id := r.cliente_id; publicado := TRUE; motivo := NULL;
    RETURN NEXT;
  END LOOP;
END;
$$;

REVOKE ALL ON FUNCTION mypump_chat_drenar(integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION mypump_chat_drenar(integer) TO service_role;

-- ── 5. Cancelar lo que ya no aplica ──────────────────────────────────────
--
-- El caso: el domingo se programan 62 pedidos de revisión repartidos en una
-- hora. A las 18:05 un cliente sube su check. Su mensaje estaba programado para
-- las 18:47 — pedirle a las 18:47 algo que hizo a las 18:05 es exactamente el
-- error que hace que la gente deje de leer.
CREATE OR REPLACE FUNCTION mypump_chat_cancelar_programado(
  p_cliente_id text,
  p_prefijo    text DEFAULT NULL
) RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_n integer;
BEGIN
  UPDATE mypump_chat_programados
     SET estado = 'cancelado', motivo = 'el cliente ya lo hizo'
   WHERE cliente_id = p_cliente_id
     AND estado = 'pendiente'
     AND (p_prefijo IS NULL OR dedupe_key LIKE p_prefijo || '%');
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END;
$$;

REVOKE ALL ON FUNCTION mypump_chat_cancelar_programado(text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION mypump_chat_cancelar_programado(text, text) TO service_role;

-- Y se engancha solo: cuando el cliente guarda su check, lo programado se cae.
CREATE OR REPLACE FUNCTION _mypump_cancelar_pedido_al_chequear()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  PERFORM mypump_chat_cancelar_programado(NEW.cliente_id, NULL);
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_cancelar_pedido_al_chequear ON mypump_checkin_semanal;
CREATE TRIGGER trg_cancelar_pedido_al_chequear
  AFTER INSERT OR UPDATE ON mypump_checkin_semanal
  FOR EACH ROW EXECUTE FUNCTION _mypump_cancelar_pedido_al_chequear();

COMMIT;
