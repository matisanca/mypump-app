-- Corta «Tu recorrido» sin borrar nada: las apps dejan de mostrarlo en la próxima lectura y la Mini deja de recibir pedidos.
UPDATE mypump_app_config SET valor = 'false'::JSONB, actualizado_en = NOW() WHERE clave = 'fin_plan';
