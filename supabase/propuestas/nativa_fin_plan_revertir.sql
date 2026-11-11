-- Reverso de nativa_fin_plan.sql. Antes: nativa_fin_plan_revertir_1_cortar.sql y apagar en la Mini lo que lea los pedidos.
-- Borra los resúmenes, los pedidos y la lista de excluidos: si hay pedidos sin leer, leerlos antes (mypump_fin_plan_pedidos).
BEGIN;
DROP FUNCTION IF EXISTS mypump_fin_plan_marcar(TEXT, TEXT, UUID);
DROP FUNCTION IF EXISTS mypump_fin_plan_pedidos();
DROP FUNCTION IF EXISTS mypump_fin_plan_publicar(TEXT, DATE, JSONB, TEXT);
DROP FUNCTION IF EXISTS mypump_fin_plan_candidatos();
DROP FUNCTION IF EXISTS mypump_fin_plan_pedir(TEXT, UUID, JSONB);
DROP FUNCTION IF EXISTS mypump_fin_plan_visto(TEXT);
DROP FUNCTION IF EXISTS mypump_fin_plan_get(TEXT);
DROP FUNCTION IF EXISTS mypump_fin_plan_vale(TEXT);
DROP TABLE IF EXISTS mypump_fin_plan_excluidos;
DROP TABLE IF EXISTS mypump_fin_plan;
DROP FUNCTION IF EXISTS mypump_fin_plan_resumen_error(JSONB);
DROP FUNCTION IF EXISTS mypump_fin_plan_texto_ok(TEXT);
DROP FUNCTION IF EXISTS mypump_fin_plan_hoy();
DROP FUNCTION IF EXISTS mypump_fin_plan_dias();
DROP FUNCTION IF EXISTS mypump_fin_plan_prendida();
DELETE FROM mypump_app_config WHERE clave IN ('fin_plan', 'fin_plan_dias', 'fin_plan_agenda');
NOTIFY pgrst, 'reload schema';
COMMIT;
