-- Reverso de nativa_controles_salud.sql. Borra la tabla con los controles cargados: antes, apagar la palanca
-- (`controles_app` en false) y, si hay filas, exportarlas (pg_dump -t mypump_controles_salud).
-- También borra salud_suplementos_propuestas (exportarla antes si tiene filas: pg_dump -t salud_suplementos_propuestas).
-- No toca nada más: ni Estudios, ni los pedidos, ni mypump_app_config fuera de su clave.
BEGIN;
DROP FUNCTION IF EXISTS mypump_controles_get(TEXT);
DROP TABLE IF EXISTS salud_suplementos_propuestas;
DROP TABLE IF EXISTS mypump_controles_salud;
DROP FUNCTION IF EXISTS mypump_controles_tocado();
DROP FUNCTION IF EXISTS mypump_controles_titulo_ok(TEXT);
DELETE FROM mypump_app_config WHERE clave = 'controles_app';
NOTIFY pgrst, 'reload schema';
COMMIT;
