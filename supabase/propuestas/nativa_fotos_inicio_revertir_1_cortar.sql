-- Reverso, paso 1: cortar con los endpoints todavía vivos. Ver el orden en nativa_fotos_inicio_revertir.sql.
-- La app deja de mostrar la sección y mini-vision rechaza lo que siga subiendo. No borra fotos ni filas.
-- Los avisos de «subí tus fotos» que todavía no salieron se descartan: llevarían a una pantalla que ya no está.
BEGIN;
UPDATE mypump_app_config SET valor = 'false'::JSONB, actualizado_en = NOW() WHERE clave = 'fotos_inicio';
UPDATE mypump_push_cola SET estado = 'descartado', error = 'fotos de inicio revertido'
 WHERE destino = 'fotos_inicio' AND estado IN ('pendiente', 'sin_device');
COMMIT;
