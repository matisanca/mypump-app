-- 064_borrador_sugerencia.sql
--
-- LA BANDEJA TE DEJABA EL COMPOSER VACÍO JUSTO EN LO DIFÍCIL.
--
-- Cuando la IA clasifica `simple`, redacta y (en automático) manda sola. Pero
-- cuando clasifica `derivar` o `urgente` —o sea, los casos que de verdad
-- necesitan a Mati— `procesar()` tiraba la respuesta a propósito:
--
--     if clase != "simple":
--         return {..., "respuesta": None, ...}
--
-- Correcto para el envío automático, pésimo para el trabajo del coach: Felipe
-- escribe tres renglones contando que le cuesta la comida y que cambió de
-- horario, y en el Cerebro aparece el motivo de la derivación y un composer en
-- blanco. Mati escribe de cero, 60 veces por semana.
--
-- Esta migración agrega `sugerencia`: un borrador escrito PARA MATI, que él
-- aprueba, edita o descarta. No es lo mismo que `respuesta` y por eso no
-- comparte columna:
--
--   · `respuesta`  = lo que la IA tiene permitido mandar SOLA. Solo `simple`,
--                    y solo si pasó el validador determinista.
--   · `sugerencia` = lo que la IA le propone a Mati. Nunca se envía sin un
--                    click humano.
--
-- LA GARANTÍA QUE NO SE NEGOCIA
-- `sugerencia` tiene exactamente UN camino hacia el cliente:
-- mypump_chat_borrador_resolver(p_enviar := true), que solo se llama desde el
-- botón del Cerebro. El drenador publica desde mypump_chat_programados, que no
-- toca esta tabla; y `mypump_chat_para_responder` solo lee para excluir. Si
-- algún día alguien agrega otro lector de esta columna, que sepa que está
-- rompiendo la única razón por la que se permite que la sugerencia sea
-- sustantiva.
BEGIN;

ALTER TABLE mypump_chat_borradores
  ADD COLUMN IF NOT EXISTS sugerencia text;

COMMENT ON COLUMN mypump_chat_borradores.sugerencia IS
  'Borrador que la IA le propone a Mati para los casos derivar/urgente. NUNCA '
  'se envía solo: el único camino al cliente es mypump_chat_borrador_resolver '
  'con p_enviar := true, o sea un click. A diferencia de `respuesta`, no pasa '
  'por el validador de salud, porque lo revisa una persona antes de salir.';

-- ── El resolver aprende a publicar la sugerencia ─────────────────────────────
-- Se REEMPLAZA con la MISMA firma (bigint, boolean, text). Ojo: `CREATE OR
-- REPLACE` con un parámetro nuevo NO reemplaza, crea una segunda función y
-- PostgREST devuelve PGRST203 — eso mató la ronda del domingo dos semanas en
-- silencio (ver 063). Acá la firma no cambia, así que es un reemplazo de verdad.
CREATE OR REPLACE FUNCTION mypump_chat_borrador_resolver(
  p_id     bigint,
  p_enviar boolean,
  p_texto  text DEFAULT NULL
) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  b      record;
  v_txt  text;
  v_id   uuid;
  v_base text;
BEGIN
  IF auth.role() NOT IN ('authenticated','service_role') THEN
    RAISE EXCEPTION 'Acceso denegado';
  END IF;

  SELECT * INTO b FROM mypump_chat_borradores WHERE id = p_id AND estado = 'borrador';
  IF NOT FOUND THEN RETURN NULL; END IF;

  IF NOT p_enviar THEN
    UPDATE mypump_chat_borradores SET estado = 'descartado', resuelto_en = now() WHERE id = p_id;
    RETURN NULL;
  END IF;

  -- Para `simple` sale `respuesta`; para derivar/urgente sale `sugerencia`.
  -- Nunca las dos: son excluyentes por construcción en el worker.
  v_base := COALESCE(b.respuesta, b.sugerencia);
  v_txt  := COALESCE(NULLIF(trim(COALESCE(p_texto, '')), ''), v_base);
  IF v_txt IS NULL OR trim(v_txt) = '' THEN RETURN NULL; END IF;

  -- `origen` queda en 'ia' aunque Mati lo haya editado: lo escribió el modelo y
  -- el registro tiene que decirlo. Si se marcara 'humano' al editar, dentro de
  -- seis meses nadie podría auditar qué escribió la IA de verdad.
  INSERT INTO mypump_comentarios (
    cliente_id, ambito, referencia_id, referencia_nombre,
    autor, contenido, leido_por_cliente, leido_por_coach, origen, meta)
  VALUES (
    b.cliente_id, 'general', NULL, NULL,
    'coach', trim(v_txt), FALSE, TRUE, 'ia',
    jsonb_build_object('respuesta_a', b.respuesta_a::text, 'borrador_id', b.id,
                       'clase', b.clase,
                       -- `sugerida` distingue en la auditoría lo que la IA
                       -- mandó sola de lo que Mati aprobó a mano.
                       'sugerida', (b.respuesta IS NULL AND b.sugerencia IS NOT NULL),
                       'editado', (p_texto IS NOT NULL AND trim(p_texto) <> COALESCE(v_base,''))))
  RETURNING id INTO v_id;

  UPDATE mypump_chat_borradores SET estado = 'enviado', resuelto_en = now() WHERE id = p_id;
  RETURN v_id;
END;
$$;
REVOKE ALL ON FUNCTION mypump_chat_borrador_resolver(bigint, boolean, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION mypump_chat_borrador_resolver(bigint, boolean, text) TO authenticated, service_role;

-- ── Guardar acepta la sugerencia ────────────────────────────────────────────
-- Acá SÍ hay un parámetro nuevo, así que hay que DROPear la firma vieja de
-- forma explícita o quedan dos funciones y PostgREST no sabe cuál llamar.
DROP FUNCTION IF EXISTS mypump_chat_borrador_guardar(text, uuid, text, text, text, text[], text);

CREATE OR REPLACE FUNCTION mypump_chat_borrador_guardar(
  p_cliente_id  text,
  p_respuesta_a uuid,
  p_clase       text,
  p_respuesta   text,
  p_motivo      text,
  p_bloqueos    text[],
  p_modelo      text,
  p_sugerencia  text DEFAULT NULL
) RETURNS bigint
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_id bigint;
BEGIN
  IF auth.role() <> 'service_role' THEN
    RAISE EXCEPTION 'Acceso denegado';
  END IF;

  -- Cinturón además de los tiradores: aunque el worker se equivoque, una clase
  -- que no sea `simple` NO puede guardar `respuesta` (que es lo único que el
  -- automático manda solo). Si viniera algo, se degrada a sugerencia.
  IF p_clase <> 'simple' AND p_respuesta IS NOT NULL THEN
    p_sugerencia := COALESCE(p_sugerencia, p_respuesta);
    p_respuesta  := NULL;
  END IF;

  INSERT INTO mypump_chat_borradores
    (cliente_id, respuesta_a, clase, respuesta, motivo, bloqueos, modelo, sugerencia)
  VALUES
    (p_cliente_id, p_respuesta_a, p_clase, p_respuesta, p_motivo, p_bloqueos, p_modelo, p_sugerencia)
  ON CONFLICT (respuesta_a) DO NOTHING
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;
REVOKE ALL ON FUNCTION mypump_chat_borrador_guardar(text, uuid, text, text, text, text[], text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION mypump_chat_borrador_guardar(text, uuid, text, text, text, text[], text, text) TO service_role;

-- ── La bandeja tiene que poder VER la sugerencia ─────────────────────────────
-- `mypump_chat_borradores_pendientes` declara sus columnas una por una, así que
-- agregar el campo a la tabla no alcanza: sin tocar esta función, el Cerebro
-- pediría los borradores y `sugerencia` llegaría `undefined`, la UI caería en la
-- rama vieja y todo esto no se vería. Cambiar el RETURNS TABLE obliga a DROP:
-- `CREATE OR REPLACE` no puede cambiar el tipo de retorno.
DROP FUNCTION IF EXISTS mypump_chat_borradores_pendientes();

CREATE FUNCTION mypump_chat_borradores_pendientes()
RETURNS TABLE (
  id          bigint,
  cliente_id  text,
  nombre      text,
  clase       text,
  respuesta   text,
  sugerencia  text,
  motivo      text,
  bloqueos    text[],
  mensaje     text,
  creado_en   timestamptz
)
LANGUAGE sql SECURITY DEFINER SET search_path = public
AS $$
  SELECT b.id, b.cliente_id, c.nombre, b.clase, b.respuesta, b.sugerencia,
         b.motivo, b.bloqueos, m.contenido, b.creado_en
  FROM mypump_chat_borradores b
  JOIN mypump_clientes c ON c.cliente_id = b.cliente_id
  LEFT JOIN mypump_comentarios m ON m.id = b.respuesta_a
  WHERE b.estado = 'borrador'
  ORDER BY (b.clase = 'urgente') DESC, b.creado_en DESC
  LIMIT 100;
$$;
REVOKE ALL ON FUNCTION mypump_chat_borradores_pendientes() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION mypump_chat_borradores_pendientes() TO authenticated, service_role;

-- ── El guardarraíl de la 063, otra vez ───────────────────────────────────────
-- Si quedó alguna función mypump* duplicada, abortar acá y no dentro de dos
-- semanas cuando alguien pregunte por qué no llegó un mensaje.
DO $guard$
DECLARE v_dupes text;
BEGIN
  SELECT string_agg(proname || ' (' || n || ' firmas)', ', ') INTO v_dupes
  FROM (SELECT p.proname, count(*) AS n
        FROM pg_proc p JOIN pg_namespace ns ON ns.oid = p.pronamespace
        WHERE ns.nspname = 'public' AND p.proname LIKE 'mypump%'
        GROUP BY p.proname HAVING count(*) > 1) d;
  IF v_dupes IS NOT NULL THEN
    RAISE EXCEPTION 'Quedaron funciones mypump duplicadas y PostgREST va a tirar PGRST203: %', v_dupes;
  END IF;
END
$guard$;

COMMIT;

NOTIFY pgrst, 'reload schema';
