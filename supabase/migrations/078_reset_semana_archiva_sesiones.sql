-- 078_reset_semana_archiva_sesiones.sql
--
-- mypump_reset_semana archiva las sesiones del bloque anterior, igual que
-- mypump_activar_siguiente desde la 070b.
--
-- Bug (Facundo Palero mn8awmggba8v, visto el 26-sep-2026): la app busca las
-- sesiones por (cliente_id, dia_id, semana) con la semana LOCAL del bloque, ni
-- por rutina_id ni por fecha. Un bloque nuevo armado desde el Cerebro entra por
-- mypump_publicar_cliente (UPDATE sobre la MISMA fila: no toca semana_actual ni
-- fecha_inicio) + mypump_reset_semana(…, 1), y ninguna de las dos archivaba. Las
-- sesiones de julio siguieron en las semanas 1, 4, 5, 6 y 7: en la 4 la app
-- reusó sesiones de julio abiertas y mezcló sus series con las de septiembre, y
-- al pasar a la 5 los días 1-3 aparecieron cerrados con un solo ejercicio. Alan
-- Guevara (mn8awmgg3fuu) tiene una sesión de julio esperándolo en la semana 4.
--
-- Por qué acá y no en publicar_cliente: la base no puede distinguir "bloque
-- nuevo" de "arreglo de un typo" al publicar (la de Alan fue un bloque nuevo con
-- la misma fase), y todos los caminos que arrancan un bloque sin la cola terminan
-- en esta RPC con la semana 1: el Publicar del Cerebro al cambiar de fase, las
-- sesiones post-call, y "Forzar semana" a la 1. Y la semana 1 ES el arranque de
-- un bloque (la app la trata como semana de calibración).
--
-- Regla:
--   · a la semana 1 desde otra  → arranque de bloque: TODAS las sesiones a
--     semana - 100 (como 070b) y fecha_inicio = hoy. Con eso fecha_inicio pasa a
--     ser el inicio del bloque en los dos caminos (activar_siguiente ya lo hace).
--   · cualquier otro movimiento → se archiva lo que queda POR ENCIMA de la semana
--     nueva y de la vieja (semana > LEAST(vieja, nueva)). Eso es siempre de un
--     bloque viejo o de semanas que se van a volver a hacer, y pre-tildaría días.
--     Lo de la semana nueva y para abajo no se toca.
--   · ya en la 1 y se pide la 1 → ajuste de un bloque recién arrancado (como el
--     de Alan del 10-sep, "semana 1 intacta"): la semana 1 queda; solo se archiva
--     lo de arriba.
--
-- OJO: "Forzar semana" del Cerebro también llama a esta RPC. Llevar a alguien a
-- la 1 desde otra semana ahora ARRANCA EL BLOQUE. Si era para corregir un
-- "pasar semana" tocado sin querer, lo archivado se devuelve con:
--   UPDATE mypump_sesiones SET semana = semana + 100
--    WHERE cliente_id = '<id>' AND semana BETWEEN -99 AND -76
--      AND iniciada_en >= '<inicio real del bloque>';
--
-- Nada se borra: los registros de carga cuelgan de sesion_id, y el historial y
-- los gráficos van por ejercicio (clave del nombre, 072) y por fecha.
-- Lo que esta RPC NO arregla: sesiones viejas que ya están EN la semana actual
-- (las de julio de Facundo en su semana 5). Esas van con el arreglo puntual.
--
-- Misma firma (text, integer) → integer: no crea una segunda función.
BEGIN;

CREATE OR REPLACE FUNCTION mypump_reset_semana(
  p_cliente_id TEXT,
  p_semana     INTEGER DEFAULT 1
)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_total  INTEGER;
  v_vieja  INTEGER;
  v_nueva  INTEGER;
  v_corte  INTEGER;
  v_inicio BOOLEAN;
BEGIN
  -- FOR UPDATE: que un "pasar semana" simultáneo no se meta entre la lectura
  -- de la semana vieja y el archivado.
  SELECT COALESCE((estructura->>'semanas_total')::int, 12), COALESCE(semana_actual, 1)
    INTO v_total, v_vieja
    FROM mypump_rutinas
   WHERE cliente_id = p_cliente_id AND estado = 'activa'
   LIMIT 1
   FOR UPDATE;

  IF v_total IS NULL THEN
    RETURN NULL; -- sin rutina activa
  END IF;

  v_nueva  := LEAST(GREATEST(COALESCE(p_semana, 1), 1), v_total);
  v_inicio := (v_nueva = 1 AND v_vieja > 1);
  v_corte  := CASE WHEN v_inicio THEN 0 ELSE LEAST(v_vieja, v_nueva) END;

  -- Archivar fuera del rango 1..N (mismo criterio que 070b). Por cliente y no
  -- por rutina_id: get_sesiones_semana y get_sesion_dia tampoco miran la rutina.
  UPDATE mypump_sesiones
     SET semana = semana - 100
   WHERE cliente_id = p_cliente_id AND semana > v_corte;

  UPDATE mypump_rutinas
     SET semana_actual = v_nueva,
         fecha_inicio  = CASE WHEN v_inicio THEN CURRENT_DATE ELSE fecha_inicio END,
         updated_at    = NOW()
   WHERE cliente_id = p_cliente_id AND estado = 'activa';

  RETURN v_nueva;
END;
$$;

REVOKE ALL ON FUNCTION mypump_reset_semana(TEXT, INTEGER) FROM PUBLIC;
REVOKE ALL ON FUNCTION mypump_reset_semana(TEXT, INTEGER) FROM anon;
GRANT EXECUTE ON FUNCTION mypump_reset_semana(TEXT, INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION mypump_reset_semana(TEXT, INTEGER) TO service_role;

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

-- ROLLBACK: re-aplicar mypump_reset_semana de la 024 (solo mueve semana_actual).
