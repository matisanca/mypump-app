-- Reverso, paso 1: cortar la subida con los endpoints todavía vivos. Ver el orden en nativa_reps_calibracion_revertir.sql.
-- La app deja de subir (`mypump_reps_estado` da puedeSubir falso) y lo que esté viajando lo frena el rechequeo del endpoint.
BEGIN;
UPDATE mypump_reps_subida SET automatica = FALSE, adoptar_sin_marca = FALSE, acepta = FALSE, borrado_pendiente = TRUE, actualizado_en = NOW();
COMMIT;
