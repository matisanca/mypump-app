-- Reverso de nativa_reps_calibracion.sql. Los archivos del bucket hay que borrarlos antes (Storage no deja borrar un
-- bucket con objetos): desde el panel o con la API de Storage y la service key. Con esto aplicado la app vuelve a no subir.
BEGIN;
DROP FUNCTION IF EXISTS mypump_reps_consentir(TEXT, BOOLEAN, TEXT, TEXT);
DROP FUNCTION IF EXISTS mypump_reps_puede_subir(TEXT);
DROP FUNCTION IF EXISTS mypump_reps_estado(TEXT);
DROP TABLE IF EXISTS mypump_reps_grabaciones;
DROP TABLE IF EXISTS mypump_reps_subida;
DROP POLICY IF EXISTS "coach lee reps-calibracion" ON storage.objects;
DELETE FROM storage.buckets WHERE id = 'reps-calibracion';
COMMIT;
