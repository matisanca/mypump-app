-- Reverso de nativa_compras_pais.sql. Para cortar sin borrar:
--   UPDATE mypump_app_config SET valor = 'false'::JSONB, actualizado_en = NOW() WHERE clave = 'compras_pais';
-- Este archivo borra las tiendas cargadas y el país de cada alumno (se vuelven a cargar desde la lista de la Mini).
BEGIN;
DROP FUNCTION IF EXISTS mypump_compras_fijar_pais(TEXT, TEXT, TEXT);
DROP FUNCTION IF EXISTS mypump_compras_cargar(TEXT, TEXT[], TEXT, TEXT, TEXT, TEXT, TEXT, DATE, INTEGER);
DROP FUNCTION IF EXISTS mypump_compras_get(TEXT);
DROP TABLE IF EXISTS mypump_cliente_pais;
DROP TABLE IF EXISTS mypump_compras_pais;
DROP FUNCTION IF EXISTS mypump_compras_clave(TEXT);
DELETE FROM mypump_app_config WHERE clave = 'compras_pais';
NOTIFY pgrst, 'reload schema';
COMMIT;
