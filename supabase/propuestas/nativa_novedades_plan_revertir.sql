-- Reverso de nativa_novedades_plan.sql. Sin la clave las apps quedan apagadas (lo mismo que `false`).
-- Lo que cada teléfono guardó (novedades_base.json, novedades.json; en la web mypump_novedades_*) queda en el teléfono y
-- no se vuelve a usar mientras la palanca esté apagada. Ensayo: BEGIN; <el DELETE>; SELECT count(*) ... = 0; ROLLBACK;
BEGIN;
DELETE FROM mypump_app_config WHERE clave = 'novedades_plan';
COMMIT;
