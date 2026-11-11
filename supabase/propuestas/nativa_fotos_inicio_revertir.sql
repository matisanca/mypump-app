-- Reverso de nativa_fotos_inicio.sql, EN ESTE ORDEN:
--   1. Cortar, con los endpoints vivos:   nativa_fotos_inicio_revertir_1_cortar.sql
--   2. En la Mini, apagar lo que lea las fotos de la app (`fotos_app.activo: false` en el config de Entregas).
--   3. Si las fotos hacen falta, bajarlas antes:  python3 nativa_fotos_inicio_firmar.py bajar <cliente_id> <carpeta>
--   4. Vaciar objetos y filas:            node nativa_fotos_inicio_vaciar.mjs vaciar --confirmar   (sin error = vacío)
--   5. Sacar las rutas y funciones de mini-vision/server.mjs y reiniciar el servicio.
--   6. Vaciar otra vez, ya sin endpoints: node nativa_fotos_inicio_vaciar.mjs vaciar --confirmar
--   7. Este archivo. No corre con filas: las fotos de un alumno no se pierden por un reverso apurado.
--   8. Borrar el bucket:                  node nativa_fotos_inicio_vaciar.mjs bucket --confirmar
BEGIN;
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM mypump_fotos_inicio) THEN
    RAISE EXCEPTION 'quedan fotos de inicio: vaciar primero (paso 4)' USING ERRCODE = '55000';
  END IF;
END $$;
DROP FUNCTION IF EXISTS mypump_fotos_inicio_leido(TEXT, TIMESTAMPTZ);
DROP FUNCTION IF EXISTS mypump_fotos_inicio_pendientes(INTEGER);
DROP FUNCTION IF EXISTS mypump_fotos_inicio_servicio(TEXT);
DROP FUNCTION IF EXISTS mypump_fotos_inicio_cerrar(TEXT);
DROP FUNCTION IF EXISTS mypump_fotos_inicio_pedir(TEXT, TEXT);
DROP FUNCTION IF EXISTS mypump_fotos_inicio_para_limpiar(INTEGER);
DROP FUNCTION IF EXISTS mypump_fotos_inicio_borrada(UUID);
DROP FUNCTION IF EXISTS mypump_fotos_inicio_borrar(TEXT, UUID);
DROP FUNCTION IF EXISTS mypump_fotos_inicio_registrar(TEXT, UUID, TEXT, TEXT, INTEGER, INTEGER, INTEGER, TIMESTAMPTZ, REAL, REAL);
DROP FUNCTION IF EXISTS mypump_fotos_inicio_puede(TEXT, UUID, TEXT);
DROP FUNCTION IF EXISTS mypump_fotos_inicio_nota(TEXT, TEXT);
DROP FUNCTION IF EXISTS mypump_fotos_inicio_get(TEXT);
DROP FUNCTION IF EXISTS mypump_fotos_inicio_habilitado(TEXT);
DROP FUNCTION IF EXISTS mypump_fotos_inicio_max_motivacion();
DROP VIEW IF EXISTS mypump_fotos_inicio_vista;
DROP TABLE IF EXISTS mypump_fotos_inicio;
DROP TABLE IF EXISTS mypump_fotos_inicio_sets;
DELETE FROM mypump_app_config WHERE clave = 'fotos_inicio';
-- Los avisos con el destino `fotos_inicio`: los que no salieron ya se descartaron en el paso 1; acá se va el rastro, y con
-- él la clave de dedupe (si la sección vuelve, el aviso puede volver a salir).
DELETE FROM mypump_push_cola WHERE destino = 'fotos_inicio';
NOTIFY pgrst, 'reload schema';
COMMIT;
