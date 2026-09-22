-- 077_avanzar_semana_monotona.sql
--
-- "Pasar a la semana siguiente" no puede hacer RETROCEDER.
--
-- 20-sep-2026. El 19 la app pasó de mandar `p_semana_destino = NULL` (el
-- servidor hacía +1 sobre SU semana) a mandar el destino explícito, para que
-- un reintento o un segundo dispositivo no saltearan una semana. Pero el
-- destino sale de `DATA.rutina.semana_actual`, que puede estar viejo:
--
--   · la app arrancó del snapshot offline (se guarda sin fecha de vencimiento);
--   · Mati movió la semana desde el Cerebro con la app del cliente abierta.
--
-- Y la RPC aplicaba ese destino sin compararlo con la semana real: un cliente
-- en la semana 5 con la app creyendo que estaba en la 3 volvía a la 4.
--
-- Con esto, un destino explícito solo puede ADELANTAR. El NULL sigue haciendo
-- +1 como siempre, y para mover hacia atrás está mypump_reset_semana.
--
-- OJO: el botón "⚙️ Forzar semana" del Cerebro usaba esta RPC para las dos
-- direcciones. Se cambió a mypump_reset_semana en el mismo momento que esto
-- (nutriplan/index.html, forzarSemanaMyPump): si se revierte una, revertir la
-- otra, o el botón deja de mover clientes hacia atrás sin decirlo.
BEGIN;

CREATE OR REPLACE FUNCTION mypump_avanzar_semana(
  p_token           TEXT,
  p_semana_destino  INTEGER DEFAULT NULL
)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_cliente_id    TEXT;
  v_semana_actual INTEGER;
  v_semanas_total INTEGER;
  v_nueva_semana  INTEGER;
BEGIN
  v_cliente_id := mypump_get_cliente_id_from_token(p_token);
  IF v_cliente_id IS NULL THEN RETURN NULL; END IF;

  -- Leer semana actual y total de la rutina activa
  SELECT
    semana_actual,
    COALESCE((estructura->>'semanas_total')::INTEGER, 12)
  INTO v_semana_actual, v_semanas_total
  FROM mypump_rutinas
  WHERE cliente_id = v_cliente_id
    AND estado = 'activa'
  LIMIT 1;

  IF v_semana_actual IS NULL THEN RETURN NULL; END IF;

  -- Calcular nueva semana
  IF p_semana_destino IS NOT NULL THEN
    -- MONÓTONA (077): con un destino explícito no se puede RETROCEDER. La app
    -- manda `su semana + 1` para que un reintento no salte una semana, pero su
    -- semana puede estar vieja (snapshot offline, o el coach la movió desde el
    -- Cerebro con la app abierta) y entonces el destino caía por debajo de la
    -- real. Para mover una semana hacia atrás está mypump_reset_semana.
    v_nueva_semana := GREATEST(v_semana_actual, LEAST(p_semana_destino, v_semanas_total));
  ELSE
    v_nueva_semana := LEAST(v_semana_actual + 1, v_semanas_total);
  END IF;

  -- Si ya estamos en la semana destino, no hacer nada (idempotente)
  IF v_nueva_semana = v_semana_actual THEN RETURN v_semana_actual; END IF;

  UPDATE mypump_rutinas
  SET semana_actual = v_nueva_semana
  WHERE cliente_id = v_cliente_id
    AND estado = 'activa';

  RETURN v_nueva_semana;
END;
$$;

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

-- ROLLBACK: re-aplicar mypump_avanzar_semana de la 005.
