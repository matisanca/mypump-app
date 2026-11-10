-- Reverso de nativa_008b. Borra las funciones y la columna: los días cargados se pierden. Las apps vuelven solas al domingo
-- (PGRST202 → 7).
BEGIN;
SET LOCAL lock_timeout = '5s';
DROP FUNCTION IF EXISTS mypump_get_revision_dia(TEXT);
DROP FUNCTION IF EXISTS mypump_set_revision_dia(TEXT, SMALLINT);
ALTER TABLE mypump_cliente_prefs DROP COLUMN IF EXISTS revision_dia;
COMMIT;
NOTIFY pgrst, 'reload schema';
