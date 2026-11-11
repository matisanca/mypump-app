-- Reverso, paso 1: cortar con los endpoints todavía vivos. Ver el orden en nativa_chat_adjuntos_revertir.sql.
-- La app deja de ofrecer fotos y audios y mini-vision rechaza lo que siga subiendo (no_habilitado → 403, la cola del
-- teléfono lo da por terminado y la burbuja queda «no salió»). Lo ya mandado se sigue viendo. No borra nada.
BEGIN;
UPDATE mypump_app_config SET valor = 'false'::JSONB, actualizado_en = NOW() WHERE clave IN ('chat_adjuntos', 'chat_adjuntos_para_todos');
COMMIT;
