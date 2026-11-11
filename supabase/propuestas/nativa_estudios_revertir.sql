-- Reverso de nativa_estudios.sql, EN ESTE ORDEN:
--   1. Cortar, con todo vivo:             nativa_estudios_revertir_1_cortar.sql (apaga la palanca: la app deja de mostrar y el bot de tomar)
--   2. En la Mini: ESTUDIOS_APP=0 en el .env del bot y reiniciarlo (RUNBOOK); sacar las rutas /estudios/* de mini-vision y reiniciarlo.
--   3. Vaciar los objetos del bucket `estudios` (node nativa_estudios_vaciar.mjs vaciar --confirmar).
--   4. Este archivo. OJO: borra el historial de «Mati lo vio», los pedidos y la lista de órdenes mostradas. Los estudios
--      en sí no se tocan: siguen en la ficha (analisis_refs) y en el bucket `analisis` del bot.
--   5. Borrar el bucket:                  node nativa_estudios_vaciar.mjs bucket --confirmar
BEGIN;
DROP FUNCTION IF EXISTS mypump_estudios_limpieza_hecha(UUID);
DROP FUNCTION IF EXISTS mypump_estudios_para_limpiar(INTEGER, INTEGER);
DROP FUNCTION IF EXISTS mypump_ordenes_app_bloquear(UUID, TEXT, TEXT);
DROP FUNCTION IF EXISTS mypump_ordenes_app_publicar(UUID, TEXT);
DROP FUNCTION IF EXISTS mypump_ordenes_app_proponer(TEXT, UUID, TEXT, TEXT, TIMESTAMPTZ, DATE, TEXT, TEXT, TEXT, JSONB, BOOLEAN, JSONB, TEXT);
DROP FUNCTION IF EXISTS mypump_estudios_pedidos_abiertos(TEXT);
DROP FUNCTION IF EXISTS mypump_estudios_pedido_resolver(UUID, TEXT, TEXT, UUID, TEXT);
DROP FUNCTION IF EXISTS mypump_estudios_pedir(TEXT, TEXT, TEXT, TEXT, DATE, TEXT, DATE, TEXT, JSONB, UUID, TEXT);
DROP FUNCTION IF EXISTS mypump_estudios_marcar_visto(UUID, TEXT, TIMESTAMPTZ);
DROP FUNCTION IF EXISTS mypump_estudios_sin_ver(TEXT);
DROP FUNCTION IF EXISTS mypump_estudios_registrar(TEXT, DATE, BOOLEAN, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, BOOLEAN, UUID);
DROP FUNCTION IF EXISTS mypump_estudios_shas_guardados(TEXT, TEXT[]);
DROP FUNCTION IF EXISTS mypump_estudios_errores_nuevos();
DROP FUNCTION IF EXISTS mypump_estudios_devolver(UUID, BOOLEAN, TEXT);
DROP FUNCTION IF EXISTS mypump_estudios_procesado(UUID, TEXT, JSONB);
DROP FUNCTION IF EXISTS mypump_estudios_tomar();
DROP FUNCTION IF EXISTS mypump_estudios_paths_para_firmar(TEXT, TEXT, UUID);
DROP FUNCTION IF EXISTS mypump_estudios_archivo_registrar(TEXT, UUID, UUID, TEXT, TEXT, INTEGER, TEXT);
DROP FUNCTION IF EXISTS mypump_estudios_archivo_puede(TEXT, UUID, UUID);
DROP FUNCTION IF EXISTS mypump_estudios_avisar(TEXT, TEXT, UUID);
DROP FUNCTION IF EXISTS mypump_estudios_novedades_vistas(TEXT, UUID[]);
DROP FUNCTION IF EXISTS mypump_estudios_hecho(TEXT, UUID, DATE);
DROP FUNCTION IF EXISTS mypump_estudios_enviar(TEXT, UUID, INTEGER);
DROP FUNCTION IF EXISTS mypump_estudios_envio_nuevo(TEXT, UUID, UUID);
DROP FUNCTION IF EXISTS mypump_estudios_get(TEXT);
DROP FUNCTION IF EXISTS mypump_estudios_se_abre(UUID);
DROP FUNCTION IF EXISTS mypump_estudios_hoy();
DROP FUNCTION IF EXISTS mypump_estudios_habilitado(TEXT);
DROP TABLE IF EXISTS mypump_estudios_archivos;
DROP TABLE IF EXISTS mypump_estudios_envios;
DROP TABLE IF EXISTS mypump_estudios_pedidos;
DROP TABLE IF EXISTS mypump_estudios_hojas;
DROP TABLE IF EXISTS mypump_estudios;
DROP TABLE IF EXISTS mypump_ordenes_app;
DROP TABLE IF EXISTS mypump_estudios_habilitados;
DROP FUNCTION IF EXISTS mypump_ordenes_texto_prohibido(TEXT, JSONB);
DROP FUNCTION IF EXISTS mypump_estudios_plano(TEXT);
DROP FUNCTION IF EXISTS mypump_estudios_tipo_normal(TEXT);
DROP FUNCTION IF EXISTS mypump_estudios_titulo(TEXT);
DROP FUNCTION IF EXISTS mypump_estudios_tipos();
DELETE FROM mypump_app_config WHERE clave IN ('estudios_app', 'estudios_para_todos', 'ordenes_app_auto', 'estudios_avisos');
NOTIFY pgrst, 'reload schema';
COMMIT;
