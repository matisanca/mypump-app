-- Eliminar feature "marcar comida realizada"
-- Aplicar en Supabase Dashboard → SQL Editor cuando esté listo.
DROP FUNCTION IF EXISTS mypump_elegir_opcion_comida(TEXT, UUID, DATE, TEXT, TEXT, BOOLEAN);
DROP FUNCTION IF EXISTS mypump_get_elecciones_dia(TEXT, UUID, DATE);
DROP TABLE IF EXISTS mypump_dietas_elecciones;
