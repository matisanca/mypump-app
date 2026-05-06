-- Limpiar datos de testing del cliente test-001
-- (mantiene la rutina y dieta del seed para futuros tests)
-- Ejecutar en Supabase Dashboard → SQL Editor

DELETE FROM mypump_ejercicios_estado WHERE cliente_id = 'test-001';
DELETE FROM mypump_registros_carga    WHERE cliente_id = 'test-001';
DELETE FROM mypump_sesiones           WHERE cliente_id = 'test-001';
