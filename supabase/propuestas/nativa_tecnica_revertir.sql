-- Reverso de nativa_tecnica.sql, EN ESTE ORDEN:
--   1. Cortar, con los endpoints vivos:   nativa_tecnica_revertir_1_cortar.sql
--   2. Descargar el worker:               launchctl bootout gui/$(id -u)/com.pump.tecnica && rm ~/Library/LaunchAgents/com.pump.tecnica.plist
--      (sin borrar el plist vuelve a cargar al reiniciar). Después, a mano: ~/pump-tecnica
--   3. Vaciar objetos y filas:            node nativa_tecnica_vaciar.mjs vaciar --confirmar   (sin error = vacío)
--   4. Sacar las rutas y funciones de mini-vision/server.mjs y reiniciar el servicio.
--   5. Vaciar otra vez, ya sin endpoints: node nativa_tecnica_vaciar.mjs vaciar --confirmar
--   6. Este archivo.
--   7. Borrar el bucket:                  node nativa_tecnica_vaciar.mjs bucket --confirmar
BEGIN;
DROP FUNCTION IF EXISTS mypump_tecnica_limpieza_hecha(UUID);
DROP FUNCTION IF EXISTS mypump_tecnica_para_avisar(INTEGER, INTEGER);
DROP FUNCTION IF EXISTS mypump_tecnica_para_limpiar(INTEGER, INTEGER);
DROP FUNCTION IF EXISTS mypump_tecnica_avisado(UUID);
DROP FUNCTION IF EXISTS mypump_tecnica_publicar_vencidas();
DROP FUNCTION IF EXISTS mypump_tecnica_descartar(UUID, TEXT, TEXT);
DROP FUNCTION IF EXISTS mypump_tecnica_aprobar(UUID, JSONB, TEXT, BOOLEAN);
DROP FUNCTION IF EXISTS mypump_tecnica_aprobar(UUID, JSONB, TEXT);        -- firma anterior, por si quedó de una versión vieja
DROP FUNCTION IF EXISTS mypump_tecnica_emitir_codigo(UUID, JSONB, TEXT, INTEGER);
DROP FUNCTION IF EXISTS mypump_tecnica_sha(TEXT);
DROP FUNCTION IF EXISTS mypump_tecnica_cierre_plazo(TIMESTAMPTZ);
DROP FUNCTION IF EXISTS mypump_tecnica_palanca();
DROP FUNCTION IF EXISTS mypump_tecnica_hora_de_publicar();
DROP FUNCTION IF EXISTS mypump_tecnica_a_revisar(INTEGER);
DROP FUNCTION IF EXISTS mypump_tecnica_guardar(UUID, TEXT, JSONB, JSONB, BOOLEAN, TIMESTAMPTZ, TIMESTAMPTZ, TEXT, TEXT, TEXT);
DROP FUNCTION IF EXISTS mypump_tecnica_reabrir_errores(INTEGER, INTEGER);
DROP FUNCTION IF EXISTS mypump_tecnica_liberar_colgadas(INTEGER, INTEGER);
DROP FUNCTION IF EXISTS mypump_tecnica_devolver(UUID, BOOLEAN, TEXT);
DROP FUNCTION IF EXISTS mypump_tecnica_tomar();
DROP FUNCTION IF EXISTS mypump_tecnica_borrar_video(TEXT, UUID);
DROP FUNCTION IF EXISTS mypump_tecnica_registrar(TEXT, UUID, TEXT, INTEGER, REAL);
DROP FUNCTION IF EXISTS mypump_tecnica_puede(TEXT, UUID);
DROP FUNCTION IF EXISTS mypump_tecnica_cancelar(TEXT, UUID);
DROP FUNCTION IF EXISTS mypump_tecnica_nuevo(TEXT, TEXT, TEXT, TEXT);
DROP FUNCTION IF EXISTS mypump_tecnica_get(TEXT);
DROP FUNCTION IF EXISTS mypump_tecnica_vista_alumno(mypump_tecnica);
DROP FUNCTION IF EXISTS mypump_tecnica_habilitado(TEXT);
DROP TABLE IF EXISTS mypump_tecnica_habilitados;
DROP TABLE IF EXISTS mypump_tecnica;
DROP TABLE IF EXISTS mypump_tecnica_aprobaciones;
DROP FUNCTION IF EXISTS mypump_tecnica_devolucion_valida(JSONB);
DROP FUNCTION IF EXISTS mypump_tecnica_texto_prohibido(JSONB);
DELETE FROM mypump_app_config WHERE clave IN ('tecnica_video', 'tecnica_para_todos');
NOTIFY pgrst, 'reload schema';
COMMIT;
