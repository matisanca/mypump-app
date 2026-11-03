-- =============================================================================
-- nativa_007 — correcciones del motor de recuperación (sobre 043/052/054/056)
--
-- Revisión contra los datos reales de mypump_salud_diaria (nov-2026). Ocho
-- problemas, cada uno marcado en el código con [Pn]:
--
--  [P1] La HRV de DÍA entraba como si fuera la nocturna. Las apps ya eligen por
--       fecha la mejor ventana (nocturna > madrugada > día) y la anotan en
--       detalle.ventana, pero el motor no la miraba: un día sin reloj de noche
--       aportaba un SDNN de vigilia (más bajo) a la media de 7 días y a la banda
--       de 60. Ahora: nocturna, si no hay madrugada, y la de día no cuenta.
--  [P2] HRV con 1-2 muestras y valores imposibles (5 ms, 309 ms). SDNN exige
--       n >= 3 cuando el dato trae n (es la mediana de lecturas de 1 minuto del
--       Apple Watch; con una sola es ruido). rMSSD no: Health Connect y Oura
--       mandan UN valor nocturno ya calculado por el dispositivo. Rango 10-200
--       ms para las dos. Como el filtro va en `serie`, sale también de la banda
--       de 60 días y del CV.
--  [P3] Carga crónica dividida por 28 aunque hubiera menos historia: un cliente
--       con 10 días de registros con RIR tenía un ratio agudo:crónico inflado ~2,8x y el
--       componente de carga en 0. Ahora se divide por los días con historia
--       (desde el primer registro de carga, tope 28) y el componente no existe
--       hasta tener 7 días.
--  [P4] La regularidad usaba STDDEV del punto medio del sueño en minutos del
--       día: 23:50 y 00:10 daban 1000 min de diferencia. Ahora es el desvío
--       circular, sqrt(-2 ln R), pasado a minutos.
--  [P5] Las "noches" de menos de 180 min (siesta o registro cortado) podían
--       ganarle a la noche entera de otra fuente. Ahora, si ese día hay una
--       noche de 180 min o más, el registro corto se descarta; si no la hay,
--       es una noche corta real y cuenta como tal (nunca como "sin dato").
--  [P6] Quien nunca llega al peso mínimo de 45 veía "insuficiente" sin saber
--       qué falta. Columna nueva `motivo_falta` (texto legible) al FINAL de la
--       tabla (y `confianza` después): las apps decodifican por nombre, así que una columna de más no las
--       rompe. También explica el "calibrando" (cuántos días faltan).
--  [P7] Respiración y SpO2 llegan como mediana del día y se colaban valores de
--       vigilia/ejercicio (30 rpm, 84 %). Solo cuentan dentro del rango de
--       reposo: respiración 8-22 rpm, SpO2 90-100 %.
--  [P8] La discordancia comparaba el check SEMANAL con el score DIARIO y saltaba
--       casi día por medio. Ahora compara contra la media de 7 días del score
--       (con al menos 3 días con score).
--
--  [B] Decisión de Mati (3-nov): el score sale con la mayor información que
--       haya. Ya no hay peso mínimo de 45: alcanza con FC en reposo/VFC o con
--       sueño (los pesos se renormalizan entre lo que exista). Solo queda
--       "insuficiente" si no hay ninguno de los dos. Columna nueva `confianza`
--       (alta/media/baja) y `motivo_falta` dice qué mejoraría el dato.
--       Confianza baja: score achicado hacia 50 o, con el INTERRUPTOR del
--       principio de la función prendido (por defecto), sin score.
--       Pisos al desvío de 60 días (FC 2 lpm, ln VFC 0,05) contra extremos.
--
-- La respuesta de mypump_get_recuperacion conserva las 12 columnas con el mismo
-- nombre, tipo y orden, y agrega `motivo_falta` al final. Cambia la firma de
-- salida, así que hay DROP + CREATE de calc, get y cliente_coach (este hacía
-- SELECT * de calc). get_recuperacion_global y _resumen eligen columnas por
-- nombre y no hace falta tocarlas.
--
-- Después de aplicar: regenerar docs/ESQUEMA_PRODUCCION.txt y
-- apps/shared/contrato.json (devuelve de mypump_get_recuperacion).
--
-- Volver atrás: re-ejecutar la definición de calc de 056 y las de get y
-- cliente_coach de 043/044 (con DROP antes, porque cambia la firma) y sus GRANT.
-- =============================================================================

BEGIN;

DROP FUNCTION IF EXISTS public.mypump_get_recuperacion(TEXT, INTEGER);
DROP FUNCTION IF EXISTS public.mypump_get_recuperacion_cliente_coach(TEXT, INTEGER);
DROP FUNCTION IF EXISTS public.mypump_calc_recuperacion(TEXT, DATE, DATE);

CREATE FUNCTION public.mypump_calc_recuperacion(p_cliente_id TEXT, p_desde DATE, p_hasta DATE)
RETURNS TABLE(fecha date, score integer, estado text, banda text, dias_datos integer,
              banda_provisoria boolean, estado_autonomico text, hrv_metrica text,
              discordancia boolean, cobertura jsonb, componentes jsonb, motivos jsonb,
              motivo_falta text, confianza text)
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
WITH
-- ── INTERRUPTOR ────────────────────────────────────────────────────────────
-- baja_sin_score = TRUE: los días de confianza BAJA (una sola señal y sin VFC)
-- salen SIN score, como 'insuficiente' y con motivo_falta, hasta que las apps
-- lean `confianza`. Para apagarlo: cambiar TRUE por FALSE en la línea de abajo
-- y volver a correr esta migración entera (es idempotente: DROP IF EXISTS +
-- CREATE). Apagado, esos días muestran el score achicado hacia 50.
opciones AS (SELECT FALSE AS baja_sin_score),
-- ── 0. Registros que NO pueden representar la noche ─────────────────────────
-- [P5] Un sueno_min < 180 es una siesta o una noche cortada. Se descarta ese
-- registro (y, de la misma fecha y fuente, el punto medio y la eficiencia, que
-- son del mismo bloque) SOLO si ese día hay otra fuente con una noche de 180
-- min o más. Si no la hay, es una noche corta de verdad y cuenta como tal
-- (duración baja y deuda): descartarla como "sin dato" haría SUBIR el score.
corta AS (
  SELECT s.fecha, s.fuente
  FROM mypump_salud_diaria s
  WHERE s.cliente_id = p_cliente_id
    AND s.fecha BETWEEN (p_desde - 75) AND p_hasta
    AND s.tipo = 'sueno_min' AND s.valor < 180
    AND EXISTS (SELECT 1 FROM mypump_salud_diaria l
                WHERE l.cliente_id = p_cliente_id AND l.fecha = s.fecha
                  AND l.tipo = 'sueno_min' AND l.valor >= 180)
),
-- ── 1. Una fila por (fecha, tipo): resolver el conflicto multi-fuente ──────
-- La unique key de la tabla es (cliente, fecha, tipo, fuente). Los filtros de
-- calidad van ANTES del DISTINCT ON: si una fuente trae un dato inválido y otra
-- uno válido, gana el válido. Prioridad:
--   a) para hrv_ms, rMSSD SIEMPRE le gana a SDNN, y nocturna a madrugada
--   b) dispositivo dedicado > Apple Health > agregador > carga manual
serie AS (
  SELECT DISTINCT ON (s.fecha, s.tipo)
         s.fecha, s.tipo, s.valor, s.fuente,
         s.detalle->>'metrica' AS metrica,
         COALESCE((s.detalle->>'estimado')::BOOLEAN, FALSE) AS estimado
  FROM mypump_salud_diaria s
  WHERE s.cliente_id = p_cliente_id
    AND s.fecha BETWEEN (p_desde - 75) AND p_hasta
    -- [P1] la HRV de día no es HRV de recuperación
    AND NOT (s.tipo = 'hrv_ms' AND COALESCE(s.detalle->>'ventana', '') = 'dia')
    -- [P2] rango fisiológico, y SDNN con al menos 3 lecturas si trae n
    AND NOT (s.tipo = 'hrv_ms' AND (s.valor < 10 OR s.valor > 200))
    -- (CASE y no AND: el orden de evaluación del AND no está garantizado y el
    -- cast fallaría con un n no numérico; con detalle NULL el CASE da FALSE)
    AND NOT (s.tipo = 'hrv_ms' AND COALESCE(s.detalle->>'metrica', '') <> 'rmssd'
             AND CASE WHEN jsonb_typeof(s.detalle->'n') = 'number'
                      THEN (s.detalle->>'n')::NUMERIC < 3 ELSE FALSE END)
    -- [P5] siestas y noches cortadas
    AND NOT (s.tipo IN ('sueno_min', 'sueno_medio_min', 'sueno_eficiencia_pct')
             AND EXISTS (SELECT 1 FROM corta k WHERE k.fecha = s.fecha AND k.fuente = s.fuente))
    -- [P7] solo valores de reposo
    AND NOT (s.tipo = 'respiracion_rpm' AND (s.valor < 8  OR s.valor > 22))
    AND NOT (s.tipo = 'spo2_pct'        AND (s.valor < 90 OR s.valor > 100))
  ORDER BY s.fecha, s.tipo,
    (CASE WHEN s.tipo = 'hrv_ms' AND s.detalle->>'metrica' = 'rmssd' THEN 0 ELSE 1 END),
    (CASE WHEN s.tipo = 'hrv_ms' AND s.detalle->>'ventana' = 'madrugada' THEN 1 ELSE 0 END),
    (CASE s.fuente WHEN 'whoop' THEN 0 WHEN 'oura' THEN 0 WHEN 'withings' THEN 0
                   WHEN 'polar' THEN 0 WHEN 'apple_health' THEN 1 WHEN 'health_connect' THEN 1
                   WHEN 'rook' THEN 2 ELSE 3 END)
),
-- ── 2. Calendario DENSO ───────────────────────────────────────────────────
cal AS (
  SELECT generate_series(p_desde - 75, p_hasta, '1 day'::interval)::DATE AS fecha
),
-- ── 3. Pivot a columnas ───────────────────────────────────────────────────
piv AS (
  SELECT c.fecha,
    MAX(CASE WHEN s.tipo = 'fc_reposo'            THEN s.valor END) AS rhr,
    MAX(CASE WHEN s.tipo = 'hrv_ms'               THEN s.valor END) AS hrv,
    MAX(CASE WHEN s.tipo = 'hrv_ms'               THEN s.metrica END) AS hrv_metrica,
    MAX(CASE WHEN s.tipo = 'sueno_min'            THEN s.valor END) AS sueno,
    MAX(CASE WHEN s.tipo = 'sueno_medio_min'      THEN s.valor END) AS sueno_medio,
    MAX(CASE WHEN s.tipo = 'sueno_eficiencia_pct' THEN s.valor END) AS sueno_ef,
    MAX(CASE WHEN s.tipo = 'respiracion_rpm'      THEN s.valor END) AS resp,
    MAX(CASE WHEN s.tipo = 'spo2_pct'             THEN s.valor END) AS spo2,
    MAX(CASE WHEN s.tipo = 'temp_muneca_c'        THEN s.valor END) AS temp,
    COALESCE(BOOL_OR(s.tipo = 'sueno_min' AND s.estimado), FALSE) AS sueno_estimado
  FROM cal c
  LEFT JOIN serie s ON s.fecha = c.fecha
  GROUP BY c.fecha
),
base AS (
  SELECT p.*,
    CASE WHEN p.hrv > 0 THEN LN(p.hrv) END AS ln_hrv,
    -- [P4] el punto medio como ángulo en el círculo de 24 h
    SIN(p.sueno_medio::FLOAT8 / 1440 * 2 * PI()) AS medio_sin,
    COS(p.sueno_medio::FLOAT8 / 1440 * 2 * PI()) AS medio_cos
  FROM piv p
),
-- ── 4. Baselines: media móvil 7d (la señal) y banda 60d (el rango normal) ──
bl AS (
  SELECT b.*,
    AVG(b.ln_hrv)  OVER w7  AS hrv_mu7,
    AVG(b.rhr)     OVER w7  AS rhr_mu7,
    STDDEV_SAMP(b.ln_hrv) OVER w60 AS hrv_sd60,
    STDDEV_SAMP(b.rhr)    OVER w60 AS rhr_sd60,
    AVG(b.ln_hrv)  OVER w60 AS hrv_mu60,
    AVG(b.rhr)     OVER w60 AS rhr_mu60,
    STDDEV_SAMP(b.ln_hrv) OVER w7  AS hrv_sd7,
    COUNT(b.ln_hrv) OVER w7 AS hrv_n7,
    AVG(b.sueno)   OVER w3  AS sueno_mu3,
    -- [P4] regularidad con estadística circular
    AVG(b.medio_sin) OVER w7 AS medio_sin7,
    AVG(b.medio_cos) OVER w7 AS medio_cos7,
    COUNT(b.sueno_medio) OVER w7 AS medio_n7,
    AVG(b.resp) OVER w60 AS resp_mu60, STDDEV_SAMP(b.resp) OVER w60 AS resp_sd60,
    AVG(b.spo2) OVER w60 AS spo2_mu60, STDDEV_SAMP(b.spo2) OVER w60 AS spo2_sd60,
    AVG(b.temp) OVER w60 AS temp_mu60, STDDEV_SAMP(b.temp) OVER w60 AS temp_sd60,
    COUNT(CASE WHEN b.rhr IS NOT NULL OR b.hrv IS NOT NULL OR b.sueno IS NOT NULL
               THEN 1 END) OVER wall AS dias_datos
  FROM base b
  WINDOW
    w3   AS (ORDER BY b.fecha ROWS BETWEEN  3 PRECEDING AND 1 PRECEDING),
    w7   AS (ORDER BY b.fecha ROWS BETWEEN  7 PRECEDING AND 1 PRECEDING),
    w60  AS (ORDER BY b.fecha ROWS BETWEEN 60 PRECEDING AND 1 PRECEDING),
    wall AS (ORDER BY b.fecha ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
),
blr AS (
  SELECT bl.*,
    -- [P4] desvío circular en minutos: sqrt(-2 ln R) radianes × 1440 / 2π.
    -- R se acota a (0, 1] por redondeo de coma flotante.
    CASE WHEN bl.medio_n7 >= 2 THEN
      SQRT(-2 * LN(GREATEST(1e-9, LEAST(1.0,
        SQRT(bl.medio_sin7 ^ 2 + bl.medio_cos7 ^ 2))))) * 1440 / (2 * PI())
    END AS sueno_medio_sd7
  FROM bl
),
-- ── 5. CV semanal de HRV y su referencia de 60 días (igual que 054) ─────────
cv AS (
  SELECT blr.*,
    CASE WHEN blr.hrv_n7 >= 3 THEN ABS(blr.hrv_sd7) * 100 END AS cv7
  FROM blr
),
cvr AS (
  SELECT cv.*, AVG(cv.cv7) OVER (ORDER BY cv.fecha ROWS BETWEEN 60 PRECEDING AND 1 PRECEDING) AS cv_ref
  FROM cv
),
-- ── 6. z-scores + puerta SWC (igual que 052) ───────────────────────────────
z AS (
  SELECT c.*,
    CASE
      WHEN c.ln_hrv IS NULL OR c.hrv_mu7 IS NULL OR NOT (c.hrv_sd60 > 0) THEN NULL
      WHEN ABS(c.ln_hrv - c.hrv_mu7) >= COALESCE(0.005 * c.cv_ref, 0)
        -- piso del desvío: 0,05 en ln (~5 %). Con una banda casi plana, un
        -- cambio mínimo daba un z enorme y un score en los extremos.
        THEN (c.ln_hrv - c.hrv_mu7) / GREATEST(c.hrv_sd60, 0.05)
      ELSE 0
    END AS z_hrv,
    CASE WHEN c.rhr_sd60 > 0 AND c.rhr IS NOT NULL AND c.rhr_mu7 IS NOT NULL
         -- piso del desvío: 2 lpm (misma razón que la VFC)
         THEN (c.rhr - c.rhr_mu7) / GREATEST(c.rhr_sd60, 2) END AS z_rhr,
    (c.cv7 IS NOT NULL AND c.cv_ref IS NOT NULL AND c.cv7 > 1.3 * c.cv_ref) AS cv_alto
  FROM cvr c
),
-- ── 7. Carga del gimnasio: agudo (3d) vs crónico (28d prorrateado) ─────────
dia_carga AS (
  SELECT (r.registrado_en AT TIME ZONE 'America/Argentina/Buenos_Aires')::DATE AS fecha,
         COUNT(*) FILTER (WHERE r.rir_real IS NOT NULL AND r.rir_real <= 2) AS series_duras,
         COALESCE(SUM(r.peso_kg * r.reps_realizadas), 0) AS tonelaje
  FROM mypump_registros_carga r
  WHERE r.cliente_id = p_cliente_id
    AND r.registrado_en >= (p_desde - 75)::TIMESTAMPTZ
  GROUP BY 1
),
-- [P3] primer día con una serie CON RIR (lo único que usa la carga), de toda
-- la historia y no solo de la ventana
carga_ini AS (
  SELECT MIN((r.registrado_en AT TIME ZONE 'America/Argentina/Buenos_Aires')::DATE) AS d
  FROM mypump_registros_carga r
  WHERE r.cliente_id = p_cliente_id AND r.rir_real IS NOT NULL
),
carga AS (
  SELECT c.fecha,
    SUM(COALESCE(dc.series_duras, 0)) OVER w3  AS agudo,
    SUM(COALESCE(dc.series_duras, 0)) OVER w28 AS cronico,
    SUM(COALESCE(dc.tonelaje, 0))     OVER w28 AS ton28,
    -- [P3] días de historia que de verdad cubre la ventana crónica
    CASE WHEN ci.d IS NULL OR ci.d > c.fecha THEN 0
         ELSE LEAST(28, c.fecha - ci.d + 1) END AS dias_hist
  FROM cal c
  CROSS JOIN carga_ini ci
  LEFT JOIN dia_carga dc ON dc.fecha = c.fecha
  WINDOW w3  AS (ORDER BY c.fecha ROWS BETWEEN  2 PRECEDING AND CURRENT ROW),
         w28 AS (ORDER BY c.fecha ROWS BETWEEN 27 PRECEDING AND CURRENT ROW)
),
-- ── 8. Check subjetivo: el último de hasta 10 días atrás ───────────────────
subj AS (
  SELECT c.fecha,
    (SELECT ((ck.descanso + ck.energia)::NUMERIC / 2 - 1) / 4 * 100
     FROM mypump_checkin_semanal ck
     WHERE ck.cliente_id = p_cliente_id
       AND ck.descanso IS NOT NULL AND ck.energia IS NOT NULL
       AND ck.semana_lunes <= c.fecha AND ck.semana_lunes >= c.fecha - 10
     ORDER BY ck.semana_lunes DESC LIMIT 1) AS s_d
  FROM cal c
),
-- ── 9. Sub-scores ─────────────────────────────────────────────────────────
sc AS (
  SELECT z.*, ca.agudo, ca.cronico, ca.dias_hist, sj.s_d,
    CASE WHEN z.hrv_metrica = 'rmssd' THEN 1.0 ELSE 1.5 END AS u_umbral,
    CASE WHEN z.sueno IS NULL THEN NULL
         ELSE GREATEST(0, LEAST(100, (z.sueno - 270) / (450 - 270) * 100)) END AS s_dur,
    CASE WHEN z.sueno_mu3 IS NULL THEN NULL
         ELSE GREATEST(0, LEAST(100, (z.sueno_mu3 - 270) / (450 - 270) * 100)) END AS s_deuda,
    -- B.3 regularidad: desvío circular del punto medio (100 a ≤30min, 0 a ≥90min)
    CASE WHEN z.sueno_medio_sd7 IS NULL THEN NULL
         ELSE GREATEST(0, LEAST(100, (90 - z.sueno_medio_sd7) / 60 * 100)) END AS s_reg,
    -- C · CARGA: ratio agudo:crónico. 100 si ≤0.8, 50 en 1.3, 0 desde 2.0.
    -- [P3] el crónico se prorratea por los días con historia, no por 28 fijos,
    -- y sin 7 días de historia el ratio no significa nada.
    CASE WHEN ca.cronico IS NULL OR ca.cronico < 6 OR ca.dias_hist < 7 THEN NULL
         ELSE (WITH r AS (SELECT ca.agudo::NUMERIC
                                 / NULLIF(ca.cronico::NUMERIC * 3 / ca.dias_hist, 0) AS v)
               SELECT CASE WHEN r.v IS NULL THEN NULL
                           WHEN r.v <= 0.8 THEN 100
                           WHEN r.v >= 2.0 THEN 0
                           WHEN r.v <= 1.3 THEN 100 - (r.v - 0.8) / 0.5 * 50
                           ELSE 50 - (r.v - 1.3) / 0.7 * 50 END FROM r) END AS s_c,
    (100
      - CASE WHEN z.resp IS NOT NULL AND z.resp_sd60 > 0
             THEN LEAST(25, GREATEST(0, (ABS(z.resp - z.resp_mu60) / z.resp_sd60 - 2) * 25)) ELSE 0 END
      - CASE WHEN z.spo2 IS NOT NULL AND z.spo2_sd60 > 0
             THEN LEAST(25, GREATEST(0, ((z.spo2_mu60 - z.spo2) / z.spo2_sd60 - 2) * 25)) ELSE 0 END
      - CASE WHEN z.temp IS NOT NULL AND z.temp_sd60 > 0
             THEN LEAST(25, GREATEST(0, (ABS(z.temp - z.temp_mu60) / z.temp_sd60 - 2) * 25)) ELSE 0 END
    ) AS s_e_raw,
    (z.resp IS NOT NULL OR z.spo2 IS NOT NULL OR z.temp IS NOT NULL) AS hay_e
  FROM z
  JOIN carga ca ON ca.fecha = z.fecha
  JOIN subj  sj ON sj.fecha = z.fecha
),
-- ── 10. Veredicto autonómico + pesos (igual que 043) ──────────────────────
sa AS (
  SELECT sc.*,
    CASE
      WHEN sc.z_hrv IS NOT NULL AND sc.z_rhr IS NOT NULL THEN
        CASE
          WHEN sc.z_hrv <= -sc.u_umbral AND sc.z_rhr >= sc.u_umbral AND sc.cv_alto      THEN 'maladaptacion'
          WHEN sc.z_hrv <= -sc.u_umbral AND sc.z_rhr >= sc.u_umbral                     THEN 'fatiga_acumulada'
          WHEN sc.z_hrv <= -sc.u_umbral AND sc.z_rhr <= -sc.u_umbral AND sc.rhr < 50    THEN 'parasimpatico_saturado'
          WHEN sc.z_hrv >= 0.5 AND ABS(sc.z_rhr) < 0.5                                  THEN 'recuperado'
          ELSE 'normal' END
      WHEN sc.z_rhr IS NOT NULL THEN
        CASE WHEN sc.z_rhr >= 1.5 THEN 'fc_elevada'
             WHEN sc.z_rhr <= -1.0 THEN 'recuperado' ELSE 'normal' END
      ELSE NULL END AS v_auto,
    CASE
      WHEN sc.z_hrv IS NOT NULL AND sc.z_rhr IS NOT NULL
        THEN 50 + 50 * GREATEST(-1, LEAST(1, (sc.z_hrv - sc.z_rhr) / 4))
      WHEN sc.z_hrv IS NOT NULL
        THEN 50 + 50 * GREATEST(-1, LEAST(1, sc.z_hrv / 2))
      WHEN sc.z_rhr IS NOT NULL
        THEN 50 - 50 * GREATEST(-1, LEAST(1, sc.z_rhr / 2))
      WHEN sc.rhr IS NOT NULL OR sc.hrv IS NOT NULL
        THEN 50
      ELSE NULL END AS s_a_base
  FROM sc
),
fin AS (
  SELECT sa.*,
    CASE sa.v_auto
      WHEN 'maladaptacion'          THEN LEAST(sa.s_a_base, 25)
      WHEN 'fatiga_acumulada'       THEN LEAST(sa.s_a_base, 35)
      WHEN 'parasimpatico_saturado' THEN LEAST(sa.s_a_base, 45)
      ELSE sa.s_a_base END AS s_a,
    -- [P5] con una noche corta (< 180 min o duración en 0) la deuda y la
    -- regularidad de las noches previas no pueden levantar el sueño: el tope
    -- es la duración (0).
    CASE WHEN sa.s_dur IS NULL THEN NULL
         WHEN sa.sueno < 180 OR sa.s_dur = 0 THEN
           LEAST(sa.s_dur, sa.s_dur * 0.5 + COALESCE(sa.s_deuda, sa.s_dur) * 0.3 + COALESCE(sa.s_reg, sa.s_dur) * 0.2)
         ELSE
           (sa.s_dur * 0.5 + COALESCE(sa.s_deuda, sa.s_dur) * 0.3 + COALESCE(sa.s_reg, sa.s_dur) * 0.2)
    END AS s_b,
    CASE WHEN sa.hay_e THEN GREATEST(0, LEAST(100, sa.s_e_raw)) ELSE NULL END AS s_e
  FROM sa
),
w AS (
  SELECT fin.*,
    CASE WHEN fin.s_a IS NULL THEN 0
         WHEN fin.hrv_metrica = 'rmssd' THEN 45
         WHEN fin.hrv_metrica IS NOT NULL THEN 40
         ELSE 30 END AS w_a,
    CASE WHEN fin.s_b IS NULL THEN 0
         ELSE (CASE WHEN fin.hrv_metrica IS NOT NULL THEN 25 ELSE 30 END)
              * (CASE WHEN fin.sueno_estimado THEN 0.6 ELSE 1 END) END AS w_b,
    CASE WHEN fin.s_c IS NULL THEN 0 ELSE 20 END AS w_c,
    CASE WHEN fin.s_d IS NULL THEN 0 ELSE 12 END AS w_d,
    CASE WHEN fin.s_e IS NULL THEN 0 ELSE  8 END AS w_e
  FROM fin
),
tot AS (
  SELECT w.*, (w.w_a + w.w_b + w.w_c + w.w_d + w.w_e) AS w_tot,
    (COALESCE(w.s_a,0)*w.w_a + COALESCE(w.s_b,0)*w.w_b + COALESCE(w.s_c,0)*w.w_c
     + COALESCE(w.s_d,0)*w.w_d + COALESCE(w.s_e,0)*w.w_e) AS num
  FROM w
),
tot1 AS (
  SELECT t.*,
    -- [B] hay score con lo que haya, siempre que exista uno de los dos pilares
    -- objetivos (FC en reposo/VFC o sueño). Los pesos ya se renormalizan al
    -- dividir por w_tot, así que no hace falta un mínimo de peso.
    (t.w_a > 0 OR t.w_b > 0) AS hay_base,
    CASE WHEN t.dias_datos >= 14 AND (t.w_a > 0 OR t.w_b > 0)
         THEN t.num / NULLIF(t.w_tot, 0) END AS score_bruto,
    -- [B] confianza: alta = VFC nocturna válida + sueño con fases;
    -- baja = un solo pilar y sin VFC; media = el resto.
    CASE WHEN t.dias_datos < 14 OR NOT (t.w_a > 0 OR t.w_b > 0) THEN NULL
         WHEN t.w_a > 0 AND t.w_b > 0 AND t.hrv_metrica IS NOT NULL AND NOT t.sueno_estimado THEN 'alta'
         WHEN (t.w_a = 0 OR t.w_b = 0) AND t.hrv_metrica IS NULL THEN 'baja'
         ELSE 'media' END AS confianza
  FROM tot t
),
tot2 AS (
  SELECT t.*,
    (t.confianza = 'baja' AND o.baja_sin_score) AS baja_oculta,
    -- con confianza baja el score se achica hacia 50: una sola señal no
    -- alcanza para afirmar un extremo
    CASE WHEN t.score_bruto IS NULL THEN NULL
         WHEN t.confianza = 'baja' AND o.baja_sin_score THEN NULL
         WHEN t.confianza = 'baja' THEN 50 + (t.score_bruto - 50) * 0.5
         ELSE t.score_bruto END AS score_raw
  FROM tot1 t CROSS JOIN opciones o
),
-- [P8] media de 7 días del score (incluye el día): es lo comparable con un
-- check que la persona contesta una vez por semana.
tot3 AS (
  SELECT t.*,
    AVG(t.score_raw)   OVER w7i AS score_mu7,
    COUNT(t.score_raw) OVER w7i AS score_n7,
    -- [P6] lo más útil para mejorar la confianza, en orden de prioridad: el
    -- motivo muestra SOLO el primero (lo mínimo que más suma)
    ARRAY_REMOVE(ARRAY[
      CASE WHEN t.w_b = 0 THEN 'usá el reloj para dormir' END,
      CASE WHEN t.w_a > 0 AND t.w_b > 0 AND t.hrv_metrica IS NULL THEN 'dejá el reloj puesto toda la noche para que mida la VFC' END,
      CASE WHEN t.w_a = 0 THEN 'revisá que el reloj registre la frecuencia cardíaca en reposo' END,
      CASE WHEN t.w_b > 0 AND t.sueno_estimado THEN 'revisá que el reloj registre las fases del sueño' END,
      CASE WHEN t.w_c = 0 THEN 'cargá el RIR de tus series' END,
      CASE WHEN t.w_d = 0 THEN 'completá el check semanal' END
    ], NULL) AS mejoras
  FROM tot2 t
  WINDOW w7i AS (ORDER BY t.fecha ROWS BETWEEN 6 PRECEDING AND CURRENT ROW)
)
SELECT
  t.fecha,
  ROUND(t.score_raw)::INTEGER AS score,
  CASE WHEN NOT t.hay_base    THEN 'insuficiente'
       WHEN t.dias_datos < 14 THEN 'calibrando'
       WHEN t.baja_oculta     THEN 'insuficiente'
       ELSE 'ok' END AS estado,
  CASE WHEN t.score_raw IS NOT NULL THEN
    CASE WHEN t.score_raw >= 67 THEN 'alta'
         WHEN t.score_raw >= 34 THEN 'media'
         ELSE 'baja' END END AS banda,
  t.dias_datos::INTEGER,
  (t.dias_datos < 30) AS banda_provisoria,
  t.v_auto AS estado_autonomico,
  t.hrv_metrica,
  -- [P8] contra la media de 7 días del score, con al menos 3 días con score
  (t.s_d IS NOT NULL AND t.score_raw IS NOT NULL AND t.score_n7 >= 3
   AND ABS(t.score_mu7 - t.s_d) >= 40) AS discordancia,
  jsonb_strip_nulls(jsonb_build_object(
    'hrv',      t.hrv, 'fc_reposo', t.rhr, 'sueno_min', t.sueno,
    'cv7',      ROUND(t.cv7, 1), 'cv_alto', t.cv_alto,
    'z_hrv',    ROUND(t.z_hrv, 2), 'z_rhr', ROUND(t.z_rhr, 2)
  )) AS cobertura,
  jsonb_strip_nulls(jsonb_build_object(
    'autonomico', CASE WHEN t.s_a IS NULL THEN NULL
                       ELSE jsonb_build_object('score', ROUND(t.s_a), 'peso', t.w_a) END,
    'sueno',      CASE WHEN t.s_b IS NULL THEN NULL ELSE jsonb_build_object('score', ROUND(t.s_b), 'peso', ROUND(t.w_b)) END,
    'carga',      CASE WHEN t.s_c IS NULL THEN NULL ELSE jsonb_build_object('score', ROUND(t.s_c), 'peso', t.w_c, 'agudo', t.agudo, 'cronico', t.cronico) END,
    'subjetivo',  CASE WHEN t.s_d IS NULL THEN NULL ELSE jsonb_build_object('score', ROUND(t.s_d), 'peso', t.w_d) END,
    'otros',      CASE WHEN t.s_e IS NULL THEN NULL ELSE jsonb_build_object('score', ROUND(t.s_e), 'peso', t.w_e) END
  )) AS componentes,
  (SELECT COALESCE(jsonb_agg(m ORDER BY (m->>'peso')::NUMERIC DESC), '[]'::jsonb)
   FROM (
     SELECT jsonb_build_object('tipo','sueno','dir',-1,'valor',ROUND(t.sueno),
                               'baseline',ROUND(t.sueno_mu3),'peso', 100 - t.s_b) AS m
     WHERE t.s_b IS NOT NULL AND t.s_b < 60
     UNION ALL
     SELECT jsonb_build_object('tipo','fc_reposo','dir',1,'valor',ROUND(t.rhr,0),
                               'baseline',ROUND(t.rhr_mu7,0),'peso', ABS(t.z_rhr) * 30)
     WHERE t.z_rhr IS NOT NULL AND t.z_rhr >= 1
     UNION ALL
     SELECT jsonb_build_object('tipo','hrv','dir',-1,'valor',ROUND(t.hrv,0),
                               'baseline',ROUND(EXP(t.hrv_mu7),0),'metrica',t.hrv_metrica,
                               'peso', ABS(t.z_hrv) * 30)
     WHERE t.z_hrv IS NOT NULL AND t.z_hrv <= -1
     UNION ALL
     SELECT jsonb_build_object('tipo','carga','dir',1,'agudo',t.agudo,'cronico',t.cronico,
                               'peso', 100 - t.s_c)
     WHERE t.s_c IS NOT NULL AND t.s_c < 50
     UNION ALL
     SELECT jsonb_build_object('tipo','regularidad','dir',-1,'valor',ROUND(t.sueno_medio_sd7::NUMERIC),
                               'peso', 100 - t.s_reg)
     WHERE t.s_reg IS NOT NULL AND t.s_reg < 50
   ) q) AS motivos,
  -- [P6] texto legible de qué falta; NULL cuando el score existe
  CASE
    WHEN NOT t.hay_base THEN
      'Faltan datos del reloj para calcular la recuperación de este día. Alcanza con '
      || 'usar el reloj para dormir o con que registre la frecuencia cardíaca en reposo.'
    WHEN t.dias_datos < 14 THEN
      'Calibrando, hay ' || t.dias_datos || ' de 14 días con datos del reloj. Faltan '
      || (14 - t.dias_datos) || CASE WHEN 14 - t.dias_datos = 1 THEN ' día.' ELSE ' días.' END
    WHEN t.baja_oculta THEN
      'Con un solo dato del reloj el score todavía no es confiable. Para tenerlo, '
      || COALESCE(t.mejoras[1], 'usá el reloj para dormir') || '.'
    WHEN t.confianza IN ('media', 'baja') AND COALESCE(array_length(t.mejoras, 1), 0) > 0 THEN
      'Confianza ' || t.confianza || '. Para mejorarla, ' || t.mejoras[1] || '.'
  END AS motivo_falta,
  t.confianza
FROM tot3 t
WHERE t.fecha BETWEEN p_desde AND p_hasta
ORDER BY t.fecha;
$function$;

-- ── Lectura del cliente: misma guarda por token que 043 ─────────────────────
CREATE FUNCTION public.mypump_get_recuperacion(p_token TEXT, p_dias INTEGER DEFAULT 14)
RETURNS TABLE(fecha date, score integer, estado text, banda text, dias_datos integer,
              banda_provisoria boolean, estado_autonomico text, hrv_metrica text,
              discordancia boolean, cobertura jsonb, componentes jsonb, motivos jsonb,
              motivo_falta text, confianza text)
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_cliente_id TEXT;
  v_hoy        DATE;
BEGIN
  v_cliente_id := mypump_get_cliente_id_from_token(p_token);
  IF v_cliente_id IS NULL THEN RETURN; END IF;
  v_hoy := (NOW() AT TIME ZONE 'America/Argentina/Buenos_Aires')::DATE;
  RETURN QUERY
    SELECT * FROM mypump_calc_recuperacion(
      v_cliente_id, v_hoy - GREATEST(1, LEAST(90, p_dias)) + 1, v_hoy);
END;
$function$;

-- ── Lectura del coach: misma guarda por rol que 044 ─────────────────────────
CREATE FUNCTION public.mypump_get_recuperacion_cliente_coach(p_cliente_id TEXT, p_dias INTEGER DEFAULT 21)
RETURNS TABLE(fecha date, score integer, estado text, banda text, dias_datos integer,
              banda_provisoria boolean, estado_autonomico text, hrv_metrica text,
              discordancia boolean, cobertura jsonb, componentes jsonb, motivos jsonb,
              motivo_falta text, confianza text)
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE v_hoy DATE;
BEGIN
  IF auth.role() NOT IN ('authenticated','service_role') THEN RAISE EXCEPTION 'Acceso denegado'; END IF;
  v_hoy := (NOW() AT TIME ZONE 'America/Argentina/Buenos_Aires')::DATE;
  RETURN QUERY SELECT * FROM mypump_calc_recuperacion(p_cliente_id, v_hoy - GREATEST(1, LEAST(90, p_dias)) + 1, v_hoy);
END; $function$;

-- ── Permisos: un CREATE nuevo nace con EXECUTE para PUBLIC ─────────────────
REVOKE ALL ON FUNCTION public.mypump_calc_recuperacion(TEXT, DATE, DATE) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.mypump_calc_recuperacion(TEXT, DATE, DATE) TO service_role;

REVOKE ALL ON FUNCTION public.mypump_get_recuperacion(TEXT, INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.mypump_get_recuperacion(TEXT, INTEGER) TO anon, authenticated, service_role;

REVOKE ALL ON FUNCTION public.mypump_get_recuperacion_cliente_coach(TEXT, INTEGER) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.mypump_get_recuperacion_cliente_coach(TEXT, INTEGER) TO authenticated, service_role;

NOTIFY pgrst, 'reload schema';

COMMIT;
