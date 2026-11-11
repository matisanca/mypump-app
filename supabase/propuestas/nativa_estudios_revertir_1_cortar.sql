-- Paso 1 del reverso de nativa_estudios.sql: apaga todo sin borrar nada. La app deja de mostrar la sección y el bot de tomar envíos.
UPDATE mypump_app_config SET valor = 'false'::JSONB, actualizado_en = NOW() WHERE clave IN ('estudios_app', 'estudios_para_todos', 'ordenes_app_auto');
