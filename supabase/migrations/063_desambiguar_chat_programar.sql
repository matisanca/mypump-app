-- =============================================================
-- 063_desambiguar_chat_programar.sql — la ronda del domingo vuelve a existir
--
-- QUÉ PASÓ
-- La 059 creó mypump_chat_programar(text, text, timestamptz, text).
-- La 062 le agregó `p_origen` y `p_meta` con CREATE OR REPLACE... pero cambiar
-- la lista de parámetros NO reemplaza: crea una función NUEVA. Quedaron las dos.
--
-- Y como los parámetros nuevos tienen DEFAULT, una llamada con los 4 de siempre
-- encaja en AMBAS. PostgREST no puede elegir y devuelve:
--   PGRST203 "Could not choose the best candidate function"
--
-- LO QUE COSTÓ
-- `recordatorios.py` llama con 4 parámetros. O sea: la ronda del domingo y los
-- recordatorios del martes y jueves venían muriendo a los 30 segundos, todas
-- las semanas, desde que se aplicó la 062. El domingo 16-ago los 62 clientes no
-- recibieron nada. `chat_worker.py` manda los 6 y por eso las respuestas de la
-- IA no cayeron por esta causa — lo que hizo el bug todavía más difícil de ver:
-- media feature andaba.
--
-- POR QUÉ UN DROP EXPLÍCITO Y NO OTRO CREATE OR REPLACE
-- Otro CREATE OR REPLACE dejaría las dos firmas igual que ahora. La única forma
-- de sacar la vieja es nombrarla por su firma exacta.
--
-- IDEMPOTENTE.
-- =============================================================

BEGIN;

-- La firma vieja, nombrada exacta. IF EXISTS para que re-correr no falle.
DROP FUNCTION IF EXISTS public.mypump_chat_programar(text, text, timestamptz, text);

-- ── Red de contención ────────────────────────────────────────────────────
--
-- Que una RPC quede con dos firmas es un error de migración, no un estado
-- válido: rompe a TODOS los llamadores que no pasen todos los parámetros, y lo
-- hace en silencio y con semanas de retraso. Esto lo convierte en un error
-- ruidoso, acá y ahora, en vez de un domingo sin mensajes dentro de un mes.
DO $$
DECLARE
  v_dupes text;
BEGIN
  SELECT string_agg(proname || ' (' || n || ' firmas)', ', ')
    INTO v_dupes
  FROM (
    SELECT p.proname, count(*) AS n
    FROM pg_proc p
    JOIN pg_namespace ns ON ns.oid = p.pronamespace
    WHERE ns.nspname = 'public' AND p.proname LIKE 'mypump%'
    GROUP BY p.proname
    HAVING count(*) > 1
  ) d;

  IF v_dupes IS NOT NULL THEN
    RAISE EXCEPTION 'Quedan RPCs mypump_* con firmas duplicadas: %. '
                    'Una llamada que no pase todos los parametros va a fallar con PGRST203.', v_dupes;
  END IF;
END $$;

COMMIT;

-- PostgREST cachea el esquema: sin esto sigue viendo las dos firmas hasta que
-- se le ocurra recargar solo. Va FUERA de la transacción a propósito.
NOTIFY pgrst, 'reload schema';
