-- Reverso de nativa_reps_calibracion.sql, EN ESTE ORDEN:
--   1. Cortar, con los endpoints vivos:    nativa_reps_calibracion_revertir_1_cortar.sql
--   2. Vaciar objetos y filas:             node nativa_reps_calibracion_vaciar.mjs vaciar --confirmar   (sin error = vacío)
--   3. Sacar las rutas y funciones de mini-vision/server.mjs y reiniciar el servicio.
--   4. Vaciar otra vez, ya sin endpoints:  node nativa_reps_calibracion_vaciar.mjs vaciar --confirmar   (alguien pudo aceptar y subir entre 1 y 3)
--   5. Este archivo.
--   6. Borrar el bucket:                   node nativa_reps_calibracion_vaciar.mjs bucket --confirmar
-- Con esto aplicado la app vuelve a no subir.
BEGIN;
DROP FUNCTION IF EXISTS mypump_reps_total_bytes();
DROP FUNCTION IF EXISTS mypump_reps_borrado_hecho(TEXT);
DROP FUNCTION IF EXISTS mypump_reps_para_borrar();
DROP FUNCTION IF EXISTS mypump_reps_revocar(TEXT);
DROP FUNCTION IF EXISTS mypump_reps_consentir(TEXT, BOOLEAN, TEXT, TEXT);
DROP FUNCTION IF EXISTS mypump_reps_puede_subir(TEXT);
DROP FUNCTION IF EXISTS mypump_reps_estado(TEXT);
DROP TABLE IF EXISTS mypump_reps_grabaciones;
DROP TABLE IF EXISTS mypump_reps_subida;
DROP POLICY IF EXISTS "coach lee reps-calibracion" ON storage.objects;
COMMIT;
