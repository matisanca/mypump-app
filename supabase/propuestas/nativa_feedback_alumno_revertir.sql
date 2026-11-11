-- Reverso de nativa_feedback_alumno.sql, EN ESTE ORDEN:
--   1. Cortar:                 nativa_feedback_alumno_revertir_1_cortar.sql (las apps dejan de mostrar y de llamar)
--   2. En la Mini: sacar la lectura de molestias y de «no lo consigo» del vigía, y la de mypump_datos_brief del brief y de
--      control_kcal (feedback-alumno/AVISOS.md). Sin eso, esos scripts fallan al no encontrar las funciones.
--   3. Si hay filas que conservar (molestias, estados de suplementos), exportarlas antes: este archivo BORRA las dos tablas.
--   4. Este archivo.
BEGIN;
DROP VIEW IF EXISTS public.mypump_datos_brief;
DROP FUNCTION IF EXISTS mypump_datos_resumen(DATE);
DROP VIEW IF EXISTS public.mypump_datos_dia;
DROP FUNCTION IF EXISTS mypump_feedback_get(TEXT);
DROP FUNCTION IF EXISTS mypump_suple_avisado(TEXT, TEXT, TIMESTAMPTZ);
DROP FUNCTION IF EXISTS mypump_suple_no_consigue(INTEGER);
DROP FUNCTION IF EXISTS mypump_suple_marcar(TEXT, TEXT, TEXT, TEXT);
DROP TABLE IF EXISTS mypump_suple_estado;
DROP FUNCTION IF EXISTS mypump_suple_clave(TEXT);
DROP FUNCTION IF EXISTS mypump_molestia_cerrar(UUID, TEXT, TEXT, TIMESTAMPTZ);
DROP FUNCTION IF EXISTS mypump_molestia_avisada(UUID, TIMESTAMPTZ);
DROP FUNCTION IF EXISTS mypump_molestias_pendientes(TEXT, INTEGER);
DROP FUNCTION IF EXISTS mypump_molestia_registrar(TEXT, UUID, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, INTEGER, TEXT, TEXT, TEXT);
DROP FUNCTION IF EXISTS mypump_molestia_vista_alumno(mypump_molestias);
DROP TABLE IF EXISTS mypump_molestias;
DROP FUNCTION IF EXISTS mypump_molestia_motivo_clinico(TEXT, TEXT, INTEGER, TEXT);
DROP FUNCTION IF EXISTS mypump_feedback_palanca(TEXT);
DELETE FROM mypump_app_config WHERE clave IN ('me_duele', 'suple_estado', 'datos_brief');
NOTIFY pgrst, 'reload schema';
COMMIT;
