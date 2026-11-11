-- Reverso de nativa_check_guiado.sql. Primero saca la palanca (las apps vuelven a la Revisión de siempre en la próxima
-- carga) y después las funciones y la tabla. Las escalas, la nota, el peso y las fotos no se tocan: nunca pasaron por acá.
--
-- OJO: borra lo que los alumnos marcaron en «¿Notaste algo de esto?». Si hay filas y se quieren conservar, exportarlas
-- antes:  \copy mypump_check_guiado TO 'check_guiado.csv' CSV HEADER
-- Si solo se quiere apagar, alcanza con:
--   UPDATE mypump_app_config SET valor = 'false', actualizado_en = NOW() WHERE clave = 'check_guiado';

BEGIN;

DELETE FROM mypump_app_config WHERE clave = 'check_guiado';

DROP FUNCTION IF EXISTS mypump_check_guiado_guardar(TEXT, DATE, JSONB);
DROP FUNCTION IF EXISTS mypump_check_guiado_get(TEXT, DATE);
DROP FUNCTION IF EXISTS mypump_check_guiado_en_ciclo(TEXT);
DROP FUNCTION IF EXISTS mypump_check_guiado_glp1(TEXT);
DROP TABLE IF EXISTS mypump_check_guiado;

NOTIFY pgrst, 'reload schema';

COMMIT;
