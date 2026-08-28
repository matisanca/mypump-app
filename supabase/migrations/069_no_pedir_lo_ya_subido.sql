-- 069_no_pedir_lo_ya_subido.sql
--
-- QUE NADIE RECIBA UN PEDIDO DE ALGO QUE YA HIZO. NUNCA MAS.
--
-- El 28-ago tres clientes preguntaron lo mismo: Ismael ("la hice hace dos
-- días"), Gerardo ("la envié el lunes o martes") y José ("está hecha mati").
-- Los tres tenían el check de la semana y las 3 fotos, y el recordatorio se los
-- volvió a pedir igual. La causa estaba en `faltantes()` de recordatorios.py,
-- que nunca miraba `falta_check` — arreglado en el commit e2de1d5.
--
-- Pero ese arreglo tapa una sola de las dos puertas.
--
-- LA QUE QUEDABA ABIERTA: entre que el mensaje se PROGRAMA y se PUBLICA pasan
-- 40 a 60 minutos, porque el escalonado reparte los 60 envíos para que no
-- salgan todos en el mismo segundo. Si el cliente sube la revisión dentro de esa
-- hora —que es justo lo que hace alguien que ve la notificación del domingo y va
-- a la app— el mensaje ya está en la cola y sale igual.
--
-- Esta migración cierra esa puerta: el drenador vuelve a preguntar, JUSTO ANTES
-- de publicar, si todavía falta algo. Si no falta, cancela.
--
-- La tabla ya tenía previsto este caso desde la 059; el comentario de la columna
-- `estado` decía textual: "Cancelado es lo que pasa cuando el cliente hizo lo
-- que se le iba a pedir ANTES de que le llegue el pedido". Estaba escrita la
-- intención y no el código.
--
-- Solo aplica a los pedidos de revisión (dedupe `dom-` y `rec-`). Las respuestas
-- de la IA y lo que escribe Mati no se tocan: esos no piden nada.
BEGIN;

CREATE OR REPLACE FUNCTION mypump_chat_drenar(p_limite integer DEFAULT 20)
RETURNS TABLE (cliente_id text, publicado boolean, motivo text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  r                 record;
  v_hora            integer;
  v_solo_respuestas boolean;
  v_lunes           date;
  v_falta_check     boolean;
  v_fotos           integer;
BEGIN
  v_hora  := EXTRACT(hour FROM (now() AT TIME ZONE 'America/Argentina/Buenos_Aires'))::integer;
  v_lunes := (date_trunc('week', now() AT TIME ZONE 'America/Argentina/Buenos_Aires'))::date;

  -- LA VENTANA HORARIA APLICA A LO NO SOLICITADO, NO A LAS RESPUESTAS.
  -- Lo que sale porque nosotros lo decidimos despierta a alguien; contestarle a
  -- quien acaba de escribir a las 00:30 es lo que haría cualquiera.
  v_solo_respuestas := (v_hora < 8 OR v_hora >= 23);

  FOR r IN
    SELECT * FROM mypump_chat_programados
     WHERE estado = 'pendiente' AND programado_para <= now()
       AND (NOT v_solo_respuestas OR origen IN ('ia','humano'))
     ORDER BY programado_para
     LIMIT LEAST(GREATEST(COALESCE(p_limite, 20), 1), 200)
    FOR UPDATE SKIP LOCKED
  LOOP
    -- Última chance de no molestar: si entre que se programó y ahora el cliente
    -- fue escalado o Mati tomó la conversación, el enlatado sobra.
    IF EXISTS (SELECT 1 FROM mypump_chat_estado e
                WHERE e.cliente_id = r.cliente_id
                  AND (e.escalado OR e.silenciado_hasta > now())) THEN
      UPDATE mypump_chat_programados
         SET estado = 'cancelado', motivo = 'escalado o silenciado' WHERE id = r.id;
      cliente_id := r.cliente_id; publicado := FALSE; motivo := 'escalado o silenciado';
      RETURN NEXT; CONTINUE;
    END IF;

    -- ── Y la segunda: ¿todavía falta lo que le vamos a pedir? ──────────────
    --
    -- Se pregunta ACA, contra la base, en el momento de publicar. No se confía
    -- en lo que se sabía cuando se programó, que puede tener una hora de viejo.
    -- El que subió en el medio no recibe nada.
    IF r.dedupe_key IS NOT NULL
       AND (r.dedupe_key LIKE 'dom-%' OR r.dedupe_key LIKE 'rec-%') THEN

      SELECT NOT EXISTS (SELECT 1 FROM mypump_checkin_semanal k
                          WHERE k.cliente_id = r.cliente_id AND k.semana_lunes = v_lunes)
        INTO v_falta_check;
      SELECT count(DISTINCT f.pose)::integer FROM mypump_fotos_progreso f
        WHERE f.cliente_id = r.cliente_id AND f.semana_lunes = v_lunes
        INTO v_fotos;

      IF NOT v_falta_check AND v_fotos >= 3 THEN
        UPDATE mypump_chat_programados
           SET estado = 'cancelado', motivo = 'ya subió la revisión completa'
         WHERE id = r.id;
        cliente_id := r.cliente_id; publicado := FALSE;
        motivo := 'ya subió la revisión completa';
        RETURN NEXT; CONTINUE;
      END IF;
    END IF;

    BEGIN
      INSERT INTO mypump_comentarios (
        cliente_id, ambito, referencia_id, referencia_nombre,
        autor, contenido, leido_por_cliente, leido_por_coach, origen, meta)
      VALUES (
        r.cliente_id, 'general', NULL, NULL,
        'coach', r.contenido, FALSE, TRUE, r.origen,
        COALESCE(r.meta, '{}'::jsonb) || jsonb_build_object('programado_id', r.id));

      UPDATE mypump_chat_programados
         SET estado = 'publicado', publicado_en = now() WHERE id = r.id;
      cliente_id := r.cliente_id; publicado := TRUE; motivo := NULL;

    EXCEPTION WHEN unique_violation THEN
      -- El índice único de `respuesta_a` saltó: alguien más ya contestó ese
      -- mensaje. No es un error, es la garantía funcionando.
      UPDATE mypump_chat_programados
         SET estado = 'cancelado', motivo = 'ya habia una respuesta a ese mensaje'
       WHERE id = r.id;
      cliente_id := r.cliente_id; publicado := FALSE;
      motivo := 'ya habia una respuesta a ese mensaje';
    END;

    RETURN NEXT;
  END LOOP;
END;
$$;
REVOKE ALL ON FUNCTION mypump_chat_drenar(integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION mypump_chat_drenar(integer) TO service_role;

-- ── El guardarraíl de la 063 ────────────────────────────────────────────────
DO $guard$
DECLARE v_dupes text;
BEGIN
  SELECT string_agg(proname || ' (' || n || ' firmas)', ', ') INTO v_dupes
  FROM (SELECT p.proname, count(*) AS n
        FROM pg_proc p JOIN pg_namespace ns ON ns.oid = p.pronamespace
        WHERE ns.nspname = 'public' AND p.proname LIKE 'mypump%'
        GROUP BY p.proname HAVING count(*) > 1) d;
  IF v_dupes IS NOT NULL THEN
    RAISE EXCEPTION 'Funciones mypump duplicadas, PostgREST va a tirar PGRST203: %', v_dupes;
  END IF;
END
$guard$;

COMMIT;

NOTIFY pgrst, 'reload schema';
