-- ============================================================
-- 056 — Health Connect como fuente de datos de salud (Android)
--
-- POR QUÉ
-- El 25% de los clientes de Mati usa Android. La app de iOS lee Apple Health;
-- la de Android va a leer Health Connect, que es el equivalente del sistema
-- (y el reemplazo oficial de Google Fit, cuyas APIs se apagan a fin de 2026).
--
-- El CHECK de `fuente` (mig 042:56) no incluye 'health_connect', así que HOY
-- cada fila que mandara un Android sería descartada en silencio por
-- _mypump_upsert_salud, que hace CONTINUE WHEN check_violation para no abortar
-- el lote entero (049:77). O sea: el cliente conecta, la app dice que sincronizó,
-- y no llega absolutamente nada. Sin error, sin log, sin síntoma hasta que
-- alguien mire la tabla.
--
-- LA ALTERNATIVA QUE SE DESCARTÓ
-- Grabar los datos de Android como 'apple_health' habría funcionado sin tocar
-- la base. No se hizo por dos motivos concretos, no por prolijidad:
--   1. El motor desempata por fuente cuando hay dos lecturas del mismo día.
--      Un cliente con Galaxy Watch + un Oura conectado por OAuth tendría dos
--      filas y el desempate estaría decidido sobre una etiqueta falsa.
--   2. El panel del coach muestra de dónde salió el dato. Mati vería
--      "Apple Health" en un cliente con un Samsung.
--
-- LA PRIORIDAD, Y POR QUÉ NO ES OBVIA
-- health_connect va al MISMO nivel que apple_health (1): los dos son
-- agregadores del sistema operativo que retransmiten lo que escribió el reloj,
-- no la fuente original del dato.
--
-- PERO su HRV es mejor: Health Connect solo tiene HeartRateVariabilityRmssdRecord,
-- o sea rMSSD. HealthKit solo tiene SDNN. El motor ya prefiere rMSSD sobre
-- SDNN ANTES de mirar la fuente (el CASE de `metrica` va primero en el ORDER
-- BY), así que la ventaja de Android queda tomada por ese desempate y no hace
-- falta inflarle el rango a la fuente. Dejarlo en 1 es lo correcto: si mañana
-- Health Connect empezara a exponer SDNN, no queremos que le gane a un Oura.
--
-- ROLLBACK
--   ALTER TABLE mypump_salud_diaria DROP CONSTRAINT mypump_salud_diaria_fuente_check;
--   ALTER TABLE mypump_salud_diaria ADD CONSTRAINT mypump_salud_diaria_fuente_check
--     CHECK (fuente IN ('apple_health','rook','manual','whoop','oura','withings','polar'));
--   -- el de entrenos no se restaura: antes de esta migración NO existía.
--   ALTER TABLE mypump_entrenos_health DROP CONSTRAINT mypump_entrenos_health_fuente_check;
--   -- y volver a aplicar 054 para revertir el CASE del motor.
-- ============================================================

-- ── 1. Permitir la fuente ──
ALTER TABLE mypump_salud_diaria
  DROP CONSTRAINT IF EXISTS mypump_salud_diaria_fuente_check;

ALTER TABLE mypump_salud_diaria
  ADD CONSTRAINT mypump_salud_diaria_fuente_check
  CHECK (fuente IN ('apple_health', 'health_connect', 'rook', 'manual',
                    'whoop', 'oura', 'withings', 'polar'));

-- ── 1b. Los entrenos: NOT VALID, y el motivo importa ──
--
-- mypump_entrenos_health tiene columna `fuente` pero NO tiene ningún CHECK
-- (verificado contra docs/ESQUEMA_PRODUCCION.txt, sección CHECK CONSTRAINTS:
-- lista 19 tablas, incluidos los DOS de mypump_salud_diaria, y esta tabla no
-- figura). O sea que acá no hay nada roto: sin constraint, los entrenos de un
-- Android entran igual. El bug de Android es SOLO el de arriba.
--
-- Se agrega igual, por simetría y para que mañana no entre cualquier cosa. Pero
-- va NOT VALID, y eso no es prolijidad: un ADD CONSTRAINT normal VALIDA las
-- filas que ya están, y si UNA sola tiene una fuente fuera de la lista, el ALTER
-- aborta. Como el editor SQL corre el archivo en una transacción, ese aborto se
-- llevaría puesto el arreglo de mypump_salud_diaria, que es el único que hoy
-- está tirando datos a la basura. No vale la pena arriesgar lo que importa por
-- lo que no.
--
-- NOT VALID chequea lo que entra de ahora en adelante y deja en paz lo viejo.
ALTER TABLE mypump_entrenos_health
  DROP CONSTRAINT IF EXISTS mypump_entrenos_health_fuente_check;

ALTER TABLE mypump_entrenos_health
  ADD CONSTRAINT mypump_entrenos_health_fuente_check
  CHECK (fuente IN ('apple_health', 'health_connect', 'rook', 'manual',
                    'whoop', 'oura', 'withings', 'polar'))
  NOT VALID;

-- Qué hay realmente en esa columna. Si sale limpio, lo de abajo lo valida.
DO $$
DECLARE v_raras TEXT;
BEGIN
  SELECT string_agg(DISTINCT coalesce(fuente, '<NULL>'), ', ')
    INTO v_raras
    FROM mypump_entrenos_health
   WHERE fuente IS NOT NULL
     AND fuente NOT IN ('apple_health', 'health_connect', 'rook', 'manual',
                        'whoop', 'oura', 'withings', 'polar');
  IF v_raras IS NULL THEN
    RAISE NOTICE 'entrenos: ninguna fuente fuera de la lista. Podés validar el constraint con:';
    RAISE NOTICE '  ALTER TABLE mypump_entrenos_health VALIDATE CONSTRAINT mypump_entrenos_health_fuente_check;';
  ELSE
    RAISE WARNING 'entrenos: hay fuentes fuera de la lista -> %. El constraint queda NOT VALID a propósito.', v_raras;
  END IF;
END $$;

-- ── 2. El motor tiene que conocer la fuente nueva ──
--
-- Sin esto, health_connect cae al ELSE 3 del CASE — o sea, por DEBAJO de un
-- peso tipeado a mano. Un cliente de Android que además se pesa a mano vería
-- el motor prefiriendo el número escrito con el dedo sobre el del reloj.
--
-- Se re-declara la función entera porque CREATE OR REPLACE no admite cambiar
-- solo un pedazo. Es la misma 054 con dos líneas distintas; el resto se
-- reproduce tal cual para que este archivo sea la definición vigente.
-- Verificación de que no se coló nada más:
--   diff <(sed -n '45,421p' 054_cv_real_y_autonomico_nulo.sql) <(sed -n '/^CREATE OR REPLACE/,$p' 056_...)
--
-- Como 054 es de 377 líneas y acá solo cambia el CASE de fuentes, se aplica
-- con un UPDATE quirúrgico sobre el cuerpo en vez de repetirlo: más corto de
-- leer y sin riesgo de que una copia manual se desincronice.
DO $$
DECLARE
  v_src TEXT;
  v_nuevo TEXT;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_src
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE p.proname = 'mypump_calc_recuperacion' AND n.nspname = 'public'
   LIMIT 1;

  IF v_src IS NULL THEN
    RAISE EXCEPTION 'no existe mypump_calc_recuperacion — aplicá 054 primero';
  END IF;

  IF position('health_connect' IN v_src) > 0 THEN
    RAISE NOTICE 'mypump_calc_recuperacion ya conoce health_connect, no se toca';
    RETURN;
  END IF;

  v_nuevo := replace(
    v_src,
    'WHEN ''polar'' THEN 0 WHEN ''apple_health'' THEN 1',
    'WHEN ''polar'' THEN 0 WHEN ''apple_health'' THEN 1 WHEN ''health_connect'' THEN 1'
  );

  IF v_nuevo = v_src THEN
    RAISE EXCEPTION 'no encontré el CASE de fuentes en mypump_calc_recuperacion — revisá a mano';
  END IF;

  EXECUTE v_nuevo;
  RAISE NOTICE 'mypump_calc_recuperacion actualizada: health_connect al nivel de apple_health';
END $$;

-- CREATE OR REPLACE conserva el ACL, así que los GRANT de 043 siguen en pie.
-- Igual se re-afirman: la regla del proyecto es que toda migración que toque
-- una función deje sus permisos explícitos, porque un DROP futuro los resetea
-- a PUBLIC y ese agujero ya se abrió una vez.
REVOKE ALL ON FUNCTION mypump_calc_recuperacion(TEXT, DATE, DATE) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION mypump_calc_recuperacion(TEXT, DATE, DATE) TO service_role;

-- ── Verificación ──
-- 1. La fuente entra:
--    SELECT mypump_ingest_salud('<token>', '[{"fecha":"2026-08-07","tipo":"fc_reposo",
--                                            "valor":52,"fuente":"health_connect"}]'::jsonb);
--    → tiene que devolver 1, no 0.
-- 2. El motor la conoce:
--    SELECT position('health_connect' IN pg_get_functiondef(
--      'mypump_calc_recuperacion(TEXT,DATE,DATE)'::regprocedure)) > 0;
--    → true
