-- ============================================================
-- 032 — Salud: tipo 'hrv_ms' (variabilidad cardíaca) — F9a
-- ============================================================
-- Preparación de wearables fase 2: además de pasos/actividad/kcal, el bridge
-- de Apple Health va a mandar HRV (indicador de recuperación), sueño y FC en
-- reposo. 'sueno_min' y 'fc_reposo' ya están en el CHECK original (027); falta
-- solo 'hrv_ms'. Reversible.
-- ============================================================

ALTER TABLE mypump_salud_diaria
  DROP CONSTRAINT IF EXISTS mypump_salud_diaria_tipo_check;

ALTER TABLE mypump_salud_diaria
  ADD CONSTRAINT mypump_salud_diaria_tipo_check
  CHECK (tipo IN ('pasos','actividad_min','kcal_activas','fc_reposo','sueno_min','peso_kg','hrv_ms'));

-- ============================================================
-- ROLLBACK (elimina primero filas hrv_ms si las hubiera, después restaura):
--
-- DELETE FROM mypump_salud_diaria WHERE tipo = 'hrv_ms';
-- ALTER TABLE mypump_salud_diaria DROP CONSTRAINT IF EXISTS mypump_salud_diaria_tipo_check;
-- ALTER TABLE mypump_salud_diaria ADD CONSTRAINT mypump_salud_diaria_tipo_check
--   CHECK (tipo IN ('pasos','actividad_min','kcal_activas','fc_reposo','sueno_min','peso_kg'));
-- ============================================================
