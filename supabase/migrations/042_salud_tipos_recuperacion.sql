-- ============================================================
-- 042 — Salud: tipos y fuentes que necesita el motor de recuperación
-- ============================================================
-- Amplía los dos CHECK de mypump_salud_diaria. Gracias a la 041, la función
-- _mypump_upsert_salud ya no tiene lista propia: este ALTER alcanza para que
-- los tipos nuevos empiecen a entrar (antes había que tocar los dos lados y
-- fue exactamente el bug que dejó afuera a hrv_ms durante un mes).
--
-- TIPOS NUEVOS
--  · sueno_profundo_min / sueno_rem_min / sueno_ligero_min
--      Etapas del sueño. HealthKit las expone como asleepDeep/asleepREM/
--      asleepCore; Oura y Whoop las mandan por API.
--  · sueno_medio_min
--      Punto medio del sueño en minutos desde medianoche (ej. 232 = 03:52).
--      Es el insumo de la REGULARIDAD: la SD de este valor en 7 días mide si
--      la persona se acuesta siempre a la misma hora. Un horario errático
--      pesa en la recuperación aunque la duración total esté bien.
--  · sueno_eficiencia_pct
--      Dormido / en cama. Distingue "8h en cama durmiendo mal" de "8h dormidas".
--  · respiracion_rpm / spo2_pct / temp_muneca_c
--      Señales de "algo pasa" (enfermedad incipiente, alcohol, calor). Se usan
--      SOLO como desviación de la banda propia, nunca por valor absoluto: un
--      SpO2 de 95% puede ser normal en una persona y anómalo en otra.
--  · grasa_pct
--      Composición corporal de balanzas inteligentes (Withings y similares).
--
-- FUENTES NUEVAS: whoop, oura, withings, polar — las APIs directas de la Vía A.
-- Se mantiene 'rook' aunque el agregador esté descartado: hay lógica de
-- prioridad de fuente en el front que la referencia, y sacarla no aporta nada.
-- ============================================================

ALTER TABLE mypump_salud_diaria
  DROP CONSTRAINT IF EXISTS mypump_salud_diaria_tipo_check;

ALTER TABLE mypump_salud_diaria
  ADD CONSTRAINT mypump_salud_diaria_tipo_check
  CHECK (tipo IN (
    -- actividad
    'pasos', 'actividad_min', 'kcal_activas',
    -- cardíaco
    'fc_reposo', 'hrv_ms',
    -- sueño
    'sueno_min', 'sueno_profundo_min', 'sueno_rem_min', 'sueno_ligero_min',
    'sueno_medio_min', 'sueno_eficiencia_pct',
    -- otras señales fisiológicas
    'respiracion_rpm', 'spo2_pct', 'temp_muneca_c',
    -- composición corporal
    'peso_kg', 'grasa_pct'
  ));

ALTER TABLE mypump_salud_diaria
  DROP CONSTRAINT IF EXISTS mypump_salud_diaria_fuente_check;

ALTER TABLE mypump_salud_diaria
  ADD CONSTRAINT mypump_salud_diaria_fuente_check
  CHECK (fuente IN ('apple_health', 'rook', 'manual', 'whoop', 'oura', 'withings', 'polar'));

-- ============================================================
-- Índice para el motor de recuperación: barre (cliente, tipo) sobre una
-- ventana de ~75 días. El índice de la 027 es (cliente_id, fecha DESC) y
-- obliga a filtrar tipo después; este lo cubre entero.
-- ============================================================
CREATE INDEX IF NOT EXISTS idx_mypump_salud_cliente_tipo_fecha
  ON mypump_salud_diaria (cliente_id, tipo, fecha DESC);

-- ============================================================
-- NOTA sobre detalle->>'metrica' (la usa el motor en la 043):
-- En hrv_ms, `detalle` lleva {"metrica": "rmssd"|"sdnn", "ventana": "...", "n": N}.
-- No es cosmético: el rMSSD nocturno de Oura/Whoop y el SDNN esporádico del
-- Apple Watch NO son la misma variable ni tienen la misma calidad (el Apple
-- Watch mide en momentos aleatorios, con MAPE ~29% contra una banda pectoral).
-- El motor le da distinto peso y distinto umbral a cada uno según este campo.
-- ============================================================

-- ============================================================
-- ROLLBACK (borra primero las filas de los tipos/fuentes nuevos):
--
-- DELETE FROM mypump_salud_diaria WHERE tipo IN ('sueno_profundo_min','sueno_rem_min',
--   'sueno_ligero_min','sueno_medio_min','sueno_eficiencia_pct','respiracion_rpm',
--   'spo2_pct','temp_muneca_c','grasa_pct');
-- DELETE FROM mypump_salud_diaria WHERE fuente IN ('whoop','oura','withings','polar');
-- DROP INDEX IF EXISTS idx_mypump_salud_cliente_tipo_fecha;
-- ALTER TABLE mypump_salud_diaria DROP CONSTRAINT IF EXISTS mypump_salud_diaria_tipo_check;
-- ALTER TABLE mypump_salud_diaria ADD CONSTRAINT mypump_salud_diaria_tipo_check
--   CHECK (tipo IN ('pasos','actividad_min','kcal_activas','fc_reposo','sueno_min','peso_kg','hrv_ms'));
-- ALTER TABLE mypump_salud_diaria DROP CONSTRAINT IF EXISTS mypump_salud_diaria_fuente_check;
-- ALTER TABLE mypump_salud_diaria ADD CONSTRAINT mypump_salud_diaria_fuente_check
--   CHECK (fuente IN ('apple_health','rook','manual'));
-- ============================================================
