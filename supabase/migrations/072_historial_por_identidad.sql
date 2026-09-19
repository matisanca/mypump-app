-- 072_historial_por_identidad.sql
--
-- EL HISTORIAL DE CARGAS ESTABA ATADO AL SLOT DE LA RUTINA, NO AL EJERCICIO.
--
-- Mati, 19-sep-2026, con dos reportes de clientes:
--
--   1. "Cuando cambio un ejercicio por un sustituto me deja las cargas del
--       ejercicio original, no las del sustituto."
--   2. "Si hago el mismo ejercicio dos veces en la semana, los toma como si
--       fuesen distintos: distinta última carga y distinto récord."
--
-- LAS DOS SON EL MISMO BUG. El historial se busca por `ejercicio_id`, y ese id
-- no identifica al ejercicio: identifica al SLOT de la rutina. Tiene el día
-- adentro (`curl-biceps-d1-0`, `curl-biceps-d4-2`), y cuando el cliente
-- sustituye, writeSet() manda el id del slot igual — con este comentario en el
-- código: "El ejercicio_id se mantiene → no rompe histórico/progresión". Es al
-- revés: mantenerlo es lo que lo rompe.
--
--   · Sustituir: las cargas del original y del sustituto quedan mezcladas bajo
--     el mismo id, y "Última" muestra la del que se hizo más recientemente,
--     sea cual sea. (bug 1)
--   · Repetir: dos ids, dos historiales, dos récords. (bug 2)
--   · Y un tercero que ya estaba documentado sin arreglo: al armar un bloque
--     nuevo se regeneran los ids, así que "última vez" y récord desaparecen
--     aunque el nombre sea idéntico (Matoff y Nacho, 11-sep).
--
-- LA IDENTIDAD CORRECTA YA ESTABA GUARDADA. Cada fila tiene `ejercicio_nombre`
-- con lo que el cliente REALMENTE hizo: el nombre del sustituto si sustituyó.
-- 25.495 registros, el 100% con nombre. Medido antes de escribir esto:
--
--   · 247 slots donde se hizo más de un ejercicio (sustituciones mezcladas).
--   · 200 claves que hoy están partidas en varios ids.
--   · Normalizar el nombre (sin acentos, sin paréntesis) NO pega ejercicios
--     distintos: lo único que colapsa es "Jalon" con "Jalón" y "Press
--     inclinado" con "Press inclinado (pectoral superior)". Que SON el mismo.
--
-- LO QUE HACE ESTA MIGRACIÓN
--
--   1. `mypump_clave_ejercicio(nombre)`: la normalización, IMMUTABLE. Tiene un
--      espejo exacto en JS (claveEjercicio en cliente.html) y un test que
--      corre las dos sobre los 703 nombres reales y exige igualdad.
--   2. Columna generada `ejercicio_clave` en mypump_registros_carga. Se
--      autopuebla para las 25 mil filas viejas y se recalcula sola en cada
--      INSERT/UPDATE: el escritor no tiene que saber que existe.
--   3. RPC nueva `mypump_get_historico_por_clave`. NOMBRE NUEVO a propósito:
--      agregarle un parámetro a la existente crea una segunda firma y
--      PostgREST tira PGRST203 (ya pasó, ver la 063). La vieja queda viva para
--      la app sin actualizar.
--
-- QUÉ NO SE TOCA. Las sesiones y `mypump_ejercicios_estado` siguen por slot:
-- "hecho hoy" es del slot, no de la identidad. Solo el historial cambia de
-- llave.
--
-- Numeración: el repo va por 070 (matcher) y la mini tiene 070/071 sueltas
-- (activar_siguiente). 072 no pisa a ninguna.
BEGIN;

-- ── 1. La clave ─────────────────────────────────────────────────────────────
-- IMMUTABLE es obligatorio para una columna generada. lower/translate/
-- regexp_replace lo son. Cualquier cambio acá obliga a recalcular la columna
-- (DROP + ADD) y a cambiar el espejo en JS: son la misma función en dos
-- lenguajes y el test lo vigila.
CREATE OR REPLACE FUNCTION mypump_clave_ejercicio(p_nombre TEXT)
RETURNS TEXT
LANGUAGE sql IMMUTABLE PARALLEL SAFE
AS $$
  SELECT trim(
    regexp_replace(
      regexp_replace(
        regexp_replace(
          translate(lower(coalesce(p_nombre, '')),
                    'áéíóúàèìòùäëïöüâêîôûãõñç',
                    'aeiouaeiouaeiouaeiouaonc'),
          '\(.*?\)', ' ', 'g'),        -- "(cabeza medial)", "(pectoral superior)": es el músculo, no el ejercicio
        '[^a-z0-9 ]+', ' ', 'g'),      -- guiones, comas, grados, lo que sea
      '\s+', ' ', 'g')
  );
$$;

-- ── 2. La columna, autopoblada ──────────────────────────────────────────────
ALTER TABLE mypump_registros_carga
  ADD COLUMN IF NOT EXISTS ejercicio_clave TEXT
  GENERATED ALWAYS AS (mypump_clave_ejercicio(ejercicio_nombre)) STORED;

-- El índice que la RPC usa: por cliente, por clave, lo más nuevo primero.
CREATE INDEX IF NOT EXISTS idx_mypump_registros_clave
  ON mypump_registros_carga (cliente_id, ejercicio_clave, registrado_en DESC);

-- ── 3. La RPC ───────────────────────────────────────────────────────────────
-- Mismo contrato que mypump_get_historico_ejercicios (055): batch, por token,
-- con topes defensivos porque el array viene del cliente. Devuelve la clave
-- pedida en cada fila para que la app mapee, y además el nombre tal cual se
-- registró, que sirve para debug y para mostrar "hiciste X" si hace falta.
CREATE OR REPLACE FUNCTION mypump_get_historico_por_clave(
  p_token          TEXT,
  p_claves         TEXT[],
  p_limit_por_ej   INTEGER DEFAULT 24
)
RETURNS TABLE(
  clave            TEXT,
  registrado_en    TIMESTAMPTZ,
  peso_kg          NUMERIC,
  reps_realizadas  INTEGER,
  rir_real         INTEGER,
  serie_numero     INTEGER,
  notas            TEXT,
  ejercicio_nombre TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_cliente_id TEXT;
  v_limit      INTEGER;
  v_claves     TEXT[];
BEGIN
  v_cliente_id := mypump_get_cliente_id_from_token(p_token);
  IF v_cliente_id IS NULL THEN RETURN; END IF;

  IF p_claves IS NULL OR array_length(p_claves, 1) IS NULL THEN
    RETURN;
  END IF;

  v_limit  := LEAST(GREATEST(COALESCE(p_limit_por_ej, 24), 1), 200);
  -- Se normaliza también lo que llega: si la app manda el nombre crudo por
  -- error, igual matchea. Y se deduplica para no repetir filas.
  SELECT array_agg(DISTINCT mypump_clave_ejercicio(k))
    INTO v_claves
    FROM unnest(p_claves[1:200]) AS k
   WHERE k IS NOT NULL AND trim(k) <> '';
  IF v_claves IS NULL THEN RETURN; END IF;

  RETURN QUERY
  SELECT e.k, h.registrado_en, h.peso_kg, h.reps_realizadas,
         h.rir_real, h.serie_numero, h.notas, h.ejercicio_nombre
  FROM unnest(v_claves) AS e(k)
  CROSS JOIN LATERAL (
    SELECT r.registrado_en, r.peso_kg, r.reps_realizadas,
           r.rir_real, r.serie_numero, r.notas, r.ejercicio_nombre
    FROM mypump_registros_carga r
    WHERE r.cliente_id = v_cliente_id
      AND r.ejercicio_clave = e.k
    ORDER BY r.registrado_en DESC
    LIMIT v_limit
  ) h;
END;
$$;

-- Mismo alcance que las de historial: la valida el token, no el rol.
GRANT EXECUTE ON FUNCTION mypump_get_historico_por_clave(TEXT, TEXT[], INTEGER)
  TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION mypump_clave_ejercicio(TEXT)
  TO anon, authenticated, service_role;

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

-- ============================================================
-- ROLLBACK (manual):
--   DROP FUNCTION IF EXISTS mypump_get_historico_por_clave(TEXT, TEXT[], INTEGER);
--   DROP INDEX IF EXISTS idx_mypump_registros_clave;
--   ALTER TABLE mypump_registros_carga DROP COLUMN IF EXISTS ejercicio_clave;
--   DROP FUNCTION IF EXISTS mypump_clave_ejercicio(TEXT);
-- La app cae sola a la RPC vieja si la nueva no existe.
-- ============================================================
