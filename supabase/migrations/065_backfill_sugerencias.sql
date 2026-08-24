-- 065_backfill_sugerencias.sql
--
-- La 064 hizo que la IA redacte una sugerencia para derivar/urgente, pero
-- SOLO para lo que entra de ahora en más. Los 9 borradores que ya estaban
-- esperando en la bandeja se generaron antes y tienen `sugerencia` en NULL, así
-- que el Cerebro los sigue mostrando con el composer vacío — que es justo lo
-- que el cambio venía a arreglar. Mati recargó, vio lo mismo, y tenía razón.
--
-- Esta migración da las dos piezas que faltan para rellenarlos:
--
--   1. leerlos CON su hilo, que `mypump_chat_para_responder` no puede dar
--      porque justamente excluye los mensajes que ya tienen borrador;
--   2. escribirles la sugerencia sin abrir ningún camino de envío.
--
-- Sirve igual de acá en adelante: si el worker se cae mientras genera, o si
-- algún día se quiere regenerar una sugerencia, esto es lo que se usa.
BEGIN;

-- ── Leer los borradores que quedaron sin sugerencia, con contexto ────────────
-- Devuelve la misma forma que `mypump_chat_para_responder` (para que el worker
-- pueda reusar armar_prompt tal cual) más el `borrador_id`.
CREATE OR REPLACE FUNCTION mypump_chat_borradores_sin_sugerencia(p_limite integer DEFAULT 20)
RETURNS TABLE (
  borrador_id  bigint,
  clase        text,
  motivo       text,
  cliente_id   text,
  nombre       text,
  mensaje_id   uuid,
  mensaje      text,
  mensaje_at   timestamptz,
  contexto     jsonb,
  ya_subio     boolean
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF auth.role() <> 'service_role' THEN
    RAISE EXCEPTION 'Acceso denegado';
  END IF;

  RETURN QUERY
  SELECT
    b.id, b.clase, b.motivo,
    b.cliente_id, c.nombre,
    m.id, m.contenido, m.created_at,
    -- Los últimos 10 del hilo, igual que para_responder: el modelo necesita
    -- ver la conversación, no solo el mensaje suelto.
    (SELECT COALESCE(jsonb_agg(jsonb_build_object('autor', h.autor, 'texto', h.contenido)
                               ORDER BY h.created_at), '[]'::jsonb)
       FROM (SELECT x.autor, x.contenido, x.created_at
               FROM mypump_comentarios x
              WHERE x.cliente_id = b.cliente_id AND x.ambito = 'general'
              ORDER BY x.created_at DESC LIMIT 10) h),
    EXISTS (SELECT 1 FROM mypump_checkin_semanal k
             WHERE k.cliente_id = b.cliente_id
               AND k.semana_lunes = (date_trunc('week', now() AT TIME ZONE 'America/Argentina/Buenos_Aires'))::date)
  FROM mypump_chat_borradores b
  JOIN mypump_clientes c   ON c.cliente_id = b.cliente_id
  JOIN mypump_comentarios m ON m.id = b.respuesta_a
  WHERE b.estado = 'borrador'
    AND b.sugerencia IS NULL
    -- `simple` no lleva sugerencia: ya tiene `respuesta`, que es lo que se
    -- manda. Pedirle una sería generar texto que nadie va a mirar.
    AND b.clase <> 'simple'
  ORDER BY (b.clase = 'urgente') DESC, b.creado_en DESC
  LIMIT LEAST(GREATEST(COALESCE(p_limite, 20), 1), 50);
END;
$$;
REVOKE ALL ON FUNCTION mypump_chat_borradores_sin_sugerencia(integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION mypump_chat_borradores_sin_sugerencia(integer) TO service_role;

-- ── Escribirle la sugerencia a un borrador ──────────────────────────────────
-- Lo único que toca es la columna `sugerencia`, y solo si sigue en 'borrador'.
-- NO cambia el estado, NO inserta en mypump_comentarios, NO puede publicar. La
-- garantía de la 064 sigue intacta: el único camino al cliente es el resolver
-- con p_enviar := true, o sea el botón de Mati.
CREATE OR REPLACE FUNCTION mypump_chat_borrador_sugerir(
  p_id         bigint,
  p_sugerencia text
) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_n int;
BEGIN
  IF auth.role() <> 'service_role' THEN
    RAISE EXCEPTION 'Acceso denegado';
  END IF;

  IF p_sugerencia IS NULL OR trim(p_sugerencia) = '' THEN
    RETURN FALSE;
  END IF;

  UPDATE mypump_chat_borradores
     SET sugerencia = left(trim(p_sugerencia), 1200)
   WHERE id = p_id
     AND estado = 'borrador'
     -- Nunca pisa una sugerencia existente: si se corre el backfill dos veces
     -- no se paga el modelo de nuevo ni se cambia algo que Mati ya leyó.
     AND sugerencia IS NULL
     -- Cinturón: en `simple` la que manda es `respuesta`. Que esto no pueda
     -- meterle texto por otra puerta.
     AND clase <> 'simple';

  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n > 0;
END;
$$;
REVOKE ALL ON FUNCTION mypump_chat_borrador_sugerir(bigint, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION mypump_chat_borrador_sugerir(bigint, text) TO service_role;

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
    RAISE EXCEPTION 'Quedaron funciones mypump duplicadas y PostgREST va a tirar PGRST203: %', v_dupes;
  END IF;
END
$guard$;

COMMIT;

NOTIFY pgrst, 'reload schema';
