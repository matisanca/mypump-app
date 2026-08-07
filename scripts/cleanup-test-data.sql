-- ============================================================
-- Borrar TODO lo que dejó el banco de pruebas.
-- Ejecutar en Supabase Dashboard → SQL Editor.
--
-- CORRELO DESPUÉS DE CADA SESIÓN DEL BANCO.
--
-- No es cosmético: el centinela de la mini y el panel del coach consultan a
-- TODOS los clientes. Los datos sintéticos aparecen en el radar del domingo y
-- en los briefs pre-call hasta que se borren — o sea, Mati termina leyendo el
-- análisis de un cliente que no existe, mezclado con los de verdad.
--
-- Alcanza a los tres prefijos que usa el banco:
--   test-001        el cliente viejo de supabase/seed/01_test_rutina.sql
--   test-banco-*    los escenarios de scripts/seed-cliente.mjs (default)
--   banco-*         los mismos con --visible-al-coach
--
-- Los `banco-*` son los que MÁS urge limpiar: existen justamente porque el
-- filtro anti-"test" del centinela (centinela.py:1103) no los descarta, así
-- que sí llegan al radar real.
--
-- Ver docs/BANCO_PRUEBAS.md.
-- ============================================================

-- Un solo predicado para todo, para que no se escape una tabla al agregar un
-- prefijo nuevo.
CREATE TEMP VIEW _banco AS
  SELECT cliente_id FROM mypump_clientes
   WHERE cliente_id = 'test-001'
      OR cliente_id LIKE 'test-banco-%'
      OR cliente_id LIKE 'banco-%';

-- ── Entreno ──
DELETE FROM mypump_ejercicios_estado WHERE cliente_id IN (SELECT cliente_id FROM _banco);
DELETE FROM mypump_registros_carga   WHERE cliente_id IN (SELECT cliente_id FROM _banco);
DELETE FROM mypump_sesiones          WHERE cliente_id IN (SELECT cliente_id FROM _banco);

-- ── Dieta ──
-- Ninguna de estas cuatro se limpiaba antes: los food swaps y los custom foods
-- sobreviven a la republicación de la dieta, así que un swap sintético seguía
-- pegado a un índice de comida del plan siguiente.
DELETE FROM mypump_comidas_marcadas  WHERE cliente_id IN (SELECT cliente_id FROM _banco);
DELETE FROM mypump_comidas_libres    WHERE cliente_id IN (SELECT cliente_id FROM _banco);
DELETE FROM mypump_food_swaps        WHERE cliente_id IN (SELECT cliente_id FROM _banco);
DELETE FROM mypump_custom_foods      WHERE cliente_id IN (SELECT cliente_id FROM _banco);

-- ── Revisión ──
DELETE FROM mypump_checkin_semanal   WHERE cliente_id IN (SELECT cliente_id FROM _banco);
DELETE FROM mypump_fotos_progreso    WHERE cliente_id IN (SELECT cliente_id FROM _banco);
DELETE FROM mypump_comentarios       WHERE cliente_id IN (SELECT cliente_id FROM _banco);
DELETE FROM mypump_habitos_diarios   WHERE cliente_id IN (SELECT cliente_id FROM _banco);

-- ── Salud ──
-- Sin esto quedan alimentando las líneas de base de 60 días del motor de
-- recuperación, así que ensucian incluso después de re-seedear.
DELETE FROM mypump_salud_diaria      WHERE cliente_id IN (SELECT cliente_id FROM _banco);
DELETE FROM mypump_entrenos_health   WHERE cliente_id IN (SELECT cliente_id FROM _banco);
DELETE FROM mypump_wearable_conexiones WHERE cliente_id IN (SELECT cliente_id FROM _banco);

-- ── Lo que el coach ya escribió sobre esos datos ──
DELETE FROM mypump_analisis_semanal  WHERE cliente_id IN (SELECT cliente_id FROM _banco);
DELETE FROM mypump_push_devices      WHERE cliente_id IN (SELECT cliente_id FROM _banco);

-- ── Los planes y los clientes sintéticos ──
-- test-001 se conserva (lo usa el seed viejo); los del banco se van enteros.
DELETE FROM mypump_rutinas    WHERE cliente_id LIKE 'test-banco-%' OR cliente_id LIKE 'banco-%';
DELETE FROM mypump_dietas     WHERE cliente_id LIKE 'test-banco-%' OR cliente_id LIKE 'banco-%';
DELETE FROM mypump_cliente_prefs WHERE cliente_id LIKE 'test-banco-%' OR cliente_id LIKE 'banco-%';
DELETE FROM mypump_clientes   WHERE cliente_id LIKE 'test-banco-%' OR cliente_id LIKE 'banco-%';

DROP VIEW _banco;

-- Verificación: esto tiene que dar 0 filas.
SELECT cliente_id, nombre FROM mypump_clientes
 WHERE cliente_id LIKE 'test-banco-%' OR cliente_id LIKE 'banco-%';
