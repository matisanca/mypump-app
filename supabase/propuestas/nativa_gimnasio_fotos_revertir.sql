-- Reverso de nativa_gimnasio_fotos.sql, EN ESTE ORDEN:
--   1. Cortar, con los endpoints vivos:   nativa_gimnasio_fotos_revertir_1_cortar.sql
--   2. Descargar el worker:               launchctl bootout gui/$(id -u)/com.pump.gimnasio && rm ~/Library/LaunchAgents/com.pump.gimnasio.plist
--      (sin borrar el plist vuelve a cargar al reiniciar). Después, a mano: ~/pump-gimnasio y los pedidos `*_gimnasio-v*.md` de ~/pump-seguimiento/pedidos/editor.
--   3. Vaciar objetos y filas:            node nativa_gimnasio_fotos_vaciar.mjs vaciar --confirmar   (sin error = vacío)
--   4. Sacar las rutas y funciones de mini-vision/server.mjs y reiniciar el servicio.
--   5. Vaciar otra vez, ya sin endpoints: node nativa_gimnasio_fotos_vaciar.mjs vaciar --confirmar
--   6. Este archivo.
--   7. Borrar el bucket:                  node nativa_gimnasio_fotos_vaciar.mjs bucket --confirmar
BEGIN;
DROP FUNCTION IF EXISTS mypump_gimnasio_reabrir_errores(INTEGER, INTEGER);
DROP FUNCTION IF EXISTS mypump_gimnasio_limpieza_hecha(UUID);
DROP FUNCTION IF EXISTS mypump_gimnasio_para_limpiar(INTEGER, INTEGER);
DROP FUNCTION IF EXISTS mypump_gimnasio_avisado(UUID);
DROP FUNCTION IF EXISTS mypump_gimnasio_cerrar(UUID, TEXT, TEXT);
DROP FUNCTION IF EXISTS mypump_gimnasio_servicio(TEXT);
DROP FUNCTION IF EXISTS mypump_gimnasio_vencer_confirmaciones(INTEGER);
DROP FUNCTION IF EXISTS mypump_gimnasio_guardar(UUID, TEXT, JSONB, JSONB, JSONB, TIMESTAMPTZ, TIMESTAMPTZ, TEXT, JSONB);
DROP FUNCTION IF EXISTS mypump_gimnasio_liberar_colgadas(INTEGER, INTEGER);
DROP FUNCTION IF EXISTS mypump_gimnasio_devolver(UUID, BOOLEAN, TEXT);
DROP FUNCTION IF EXISTS mypump_gimnasio_tomar();
DROP FUNCTION IF EXISTS mypump_gimnasio_foto_borrar(TEXT, UUID);
DROP FUNCTION IF EXISTS mypump_gimnasio_foto_registrar(TEXT, UUID, UUID, TEXT, TEXT, INTEGER, INTEGER, REAL);
DROP FUNCTION IF EXISTS mypump_gimnasio_foto_puede(TEXT, UUID, UUID);
DROP FUNCTION IF EXISTS mypump_gimnasio_responder(TEXT, UUID, JSONB);
DROP FUNCTION IF EXISTS mypump_gimnasio_enviar(TEXT, UUID, TEXT[], TEXT, TEXT[]);
DROP FUNCTION IF EXISTS mypump_gimnasio_nuevo(TEXT, TEXT);
DROP FUNCTION IF EXISTS mypump_gimnasio_get(TEXT);
DROP FUNCTION IF EXISTS mypump_gimnasio_vista_alumno(mypump_gimnasio);
DROP FUNCTION IF EXISTS mypump_gimnasio_habilitado(TEXT);
DROP TABLE IF EXISTS mypump_gimnasio_habilitados;
DROP TABLE IF EXISTS mypump_equipo_requisitos;
DROP TABLE IF EXISTS mypump_gimnasio_fotos;
DROP TABLE IF EXISTS mypump_gimnasio;
DROP FUNCTION IF EXISTS mypump_gimnasio_zonas();
DROP FUNCTION IF EXISTS mypump_gimnasio_tipos();
DELETE FROM mypump_app_config WHERE clave IN ('gimnasio_fotos', 'gimnasio_para_todos');
DROP POLICY IF EXISTS "coach lee gimnasio" ON storage.objects;
NOTIFY pgrst, 'reload schema';
COMMIT;
