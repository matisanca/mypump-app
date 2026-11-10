-- Paso 1 del reverso de nativa_feedback_alumno.sql: apagar las tres palancas. Las apps dejan de mostrar y de llamar; nada se borra.
UPDATE mypump_app_config SET valor = 'false'::JSONB, actualizado_en = NOW() WHERE clave IN ('me_duele', 'suple_estado', 'datos_brief');
