-- Limpiar datos de testing del cliente test-001
-- (mantiene la rutina y dieta del seed para futuros tests)
-- Ejecutar en Supabase Dashboard → SQL Editor
--
-- CORRELO DESPUÉS DE CADA SESIÓN DEL BANCO DE PRUEBAS.
--
-- No es cosmético: el centinela de la mini y el panel del coach consultan a
-- TODOS los clientes, y test-001 es uno más para ellos. Los datos sintéticos de
-- scripts/seed-salud.mjs aparecen en el radar del domingo y en los briefs
-- pre-call hasta que se borren — o sea, Mati termina leyendo el análisis de un
-- cliente que no existe, mezclado con los de verdad.
--
-- Ver docs/BANCO_PRUEBAS_SALUD.md.

DELETE FROM mypump_ejercicios_estado WHERE cliente_id = 'test-001';
DELETE FROM mypump_registros_carga    WHERE cliente_id = 'test-001';
DELETE FROM mypump_sesiones           WHERE cliente_id = 'test-001';

-- Salud sintética. Sin esto quedan alimentando las líneas de base de 60 días
-- del motor de recuperación, así que ensucian incluso después de re-seedear.
DELETE FROM mypump_salud_diaria       WHERE cliente_id = 'test-001';
DELETE FROM mypump_entrenos_health    WHERE cliente_id = 'test-001';

-- El análisis semanal que el centinela ya haya escrito sobre esos datos.
DELETE FROM mypump_analisis_semanal   WHERE cliente_id = 'test-001';
