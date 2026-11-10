-- Reverso, paso 1: cortar con los endpoints todavía vivos. Ver el orden en nativa_tecnica_revertir.sql.
-- La app deja de mostrar la sección y mini-vision rechaza lo que siga subiendo. No borra nada.
BEGIN;
UPDATE mypump_app_config SET valor = 'false'::JSONB, actualizado_en = NOW() WHERE clave IN ('tecnica_video', 'tecnica_para_todos');
COMMIT;
