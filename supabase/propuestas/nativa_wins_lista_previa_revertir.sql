-- Reverso de nativa_wins_lista_previa.sql.
-- La app no se rompe: con las palancas apagadas no llama a nada, y sin las funciones (PGRST202) no muestra nada nuevo.
-- Para solo apagar sin borrar nada (lo recomendado si ya hay permisos dados):
--   UPDATE mypump_app_config SET valor = 'false'::jsonb WHERE clave IN ('wins_app', 'lista_previa');
-- OJO: esto borra los permisos y la cola de logros. Antes, en la Mini, frenar el trabajo que lee `mypump_wins_cola` y,
-- si hubo permisos dados, guardar una copia (son la prueba del consentimiento):
--   \copy (SELECT * FROM mypump_wins_permisos) TO 'wins-permisos-<fecha>.csv' CSV HEADER
--   \copy (SELECT * FROM mypump_wins) TO 'wins-<fecha>.csv' CSV HEADER
BEGIN;
UPDATE mypump_app_config SET valor = 'false'::JSONB WHERE clave IN ('wins_app', 'lista_previa');
DROP FUNCTION IF EXISTS mypump_lista_previa(TEXT);
DROP FUNCTION IF EXISTS mypump_wins_marcar(UUID, TEXT, TIMESTAMPTZ, TEXT);
DROP FUNCTION IF EXISTS mypump_wins_cola(INTEGER);
DROP FUNCTION IF EXISTS mypump_wins_registrar(TEXT, UUID, TEXT, TEXT, DATE, JSONB);
DROP FUNCTION IF EXISTS mypump_wins_permiso(TEXT, BOOLEAN, INTEGER, TEXT);
DROP FUNCTION IF EXISTS mypump_wins_estado(TEXT);
DROP TABLE IF EXISTS mypump_wins;
DROP TABLE IF EXISTS mypump_wins_permisos;
DROP FUNCTION IF EXISTS mypump_wins_numero(JSONB, NUMERIC, NUMERIC);
DROP FUNCTION IF EXISTS mypump_wins_texto(TEXT, INTEGER);
DROP FUNCTION IF EXISTS mypump_wins_palanca();
DELETE FROM mypump_app_config WHERE clave IN ('wins_app', 'lista_previa');
NOTIFY pgrst, 'reload schema';
COMMIT;
