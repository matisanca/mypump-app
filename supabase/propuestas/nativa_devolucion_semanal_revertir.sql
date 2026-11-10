-- Reverso de nativa_devolucion_semanal.sql.
-- Antes: en la Mini, sacar el modo real de publicar_devoluciones.py (volver al .bak, ver RUNBOOK_DEVOLUCION.md) para que
-- nadie llame a las funciones mientras desaparecen. La app no se rompe: sin `mypump_devolucion_get` (PGRST202) no muestra nada.
-- OJO: borra las devoluciones guardadas. Si alguna se publicó, antes hacer una copia:
--   \copy (SELECT * FROM mypump_devoluciones) TO 'devoluciones-<fecha>.csv' CSV HEADER
-- Para solo apagar sin borrar nada: UPDATE mypump_app_config SET valor = 'false'::jsonb WHERE clave = 'devolucion_semanal';
BEGIN;
UPDATE mypump_app_config SET valor = 'false'::JSONB WHERE clave IN ('devolucion_semanal', 'devolucion_para_todos');
DROP FUNCTION IF EXISTS mypump_devolucion_ver(TEXT, UUID[]);
DROP FUNCTION IF EXISTS mypump_devolucion_retirar(TEXT, UUID, TEXT);
DROP FUNCTION IF EXISTS mypump_devolucion_descartar(TEXT, UUID, TEXT);
DROP FUNCTION IF EXISTS mypump_devolucion_publicar(TEXT, UUID, TEXT);
DROP FUNCTION IF EXISTS mypump_devolucion_aprobar(TEXT, TEXT, UUID[]);
DROP FUNCTION IF EXISTS mypump_devolucion_emitir_codigo(TEXT, UUID[], TEXT, DATE, INTEGER);
DROP FUNCTION IF EXISTS mypump_devolucion_cargar(TEXT, TEXT, DATE, TEXT, DATE);
DROP FUNCTION IF EXISTS mypump_devolucion_get(TEXT);
DROP FUNCTION IF EXISTS mypump_devolucion_guarda(TEXT);
DROP FUNCTION IF EXISTS mypump_devolucion_habilitado(TEXT);
DROP TABLE IF EXISTS mypump_devolucion_habilitados;
DROP TABLE IF EXISTS mypump_devoluciones;
DROP TABLE IF EXISTS mypump_devolucion_aprobaciones;
DROP TABLE IF EXISTS mypump_devolucion_llave;
DROP FUNCTION IF EXISTS mypump_devolucion_hora_de_publicar();
DROP FUNCTION IF EXISTS mypump_devolucion_texto_motivo(TEXT);
DROP FUNCTION IF EXISTS mypump_devolucion_sha(TEXT);
-- Los avisos ya encolados que no salieron, no salen.
UPDATE mypump_push_cola SET estado = 'descartado' WHERE dedupe_key LIKE 'dev-%' AND estado IN ('pendiente', 'sin_device');
DELETE FROM mypump_app_config WHERE clave IN ('devolucion_semanal', 'devolucion_para_todos');
NOTIFY pgrst, 'reload schema';
COMMIT;
