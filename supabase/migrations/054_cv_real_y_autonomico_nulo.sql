-- =============================================================
-- 054 — El CV del HRV estaba ~4x subestimado (la puerta SWC casi no frenaba)
--
-- Dos cosas en mypump_calc_recuperacion, las dos de la 043 (no de la 052).
--
-- 1) cv7 NO ERA UN COEFICIENTE DE VARIACION.
--    hrv_mu7 y hrv_sd7 son la media y el desvio de LN(hrv) — de los
--    logaritmos. cv7 se calculaba como sd7/mu7*100, que divide el desvio de
--    los logs por ln(HRV basal) ~= 3.8. Eso no es el CV de nada.
--
--    Para una variable lognormal (el HRV lo es) el CV se aproxima por el
--    DESVIO DE SUS LOGS: CV ~= sd(ln). Asi que el CV real de alguien con
--    rMSSD 45 y sd(ln)=0.15 es ~15%, no el ~3.9% que reportaba.
--
--    CONSECUENCIA: el umbral SWC = 0.5*CV quedaba en 0.0195 en vez de 0.075.
--    La puerta que existe para que el score NO se mueva por ruido de medicion
--    solo frenaba cambios menores al 2% — practicamente nunca. Un dia con
--    rMSSD 42 contra una base de 45 (ruido puro segun el propio criterio)
--    pasaba la puerta y bajaba el score ~2 puntos.
--
--    Se nota tambien en que la 052 (ELSE 0) no cambio ningun score sobre los
--    datos sinteticos: la puerta no se estaba activando.
--
--    `cv_alto` compara cv7 contra su propio promedio de 60d: es una RAZON, el
--    factor se cancelaba y no cambia de comportamiento.
--
--    `cobertura.cv7` pasa a ser un numero interpretable (~10-20% en rMSSD),
--    comparable con la literatura de HRV. Antes era ~4% y no significaba nada.
--
-- 2) 'componentes.autonomico' se emitia SIEMPRE, aun sin dato cardiaco.
--    Los otros cuatro componentes usan CASE WHEN <score> IS NULL THEN NULL, y
--    jsonb_strip_nulls borra la clave entera. El autonomico no: con s_a NULL
--    quedaba {"autonomico": {"peso": 0}} — la clave presente pero sin score.
--    La app (cliente.html:5251) itera las claves que existen y hace
--    Math.round(c.score) -> Math.round(undefined) -> NaN. El cliente sin reloj
--    que entrena y hace el check veia "Corazon (pulso + variabilidad) — NaN".
--
-- VERIFICACION: con una serie sintetica, un dia con |ln_hrv - mu7| entre el
-- umbral viejo y el nuevo tiene que pasar de z_hrv != 0 a z_hrv = 0. Y un
-- cliente sin fc_reposo ni hrv_ms no debe traer la clave 'autonomico'.
--
-- ROLLBACK: re-aplicar la 052.
-- =============================================================

CREATE OR REPLACE FUNCTION mypump_calc_recuperacion(
  p_cliente_id TEXT,
  p_desde      DATE,
  p_hasta      DATE
)
RETURNS TABLE (
  fecha              DATE,
  score              INTEGER,
  estado             TEXT,      -- 'ok' | 'calibrando' | 'insuficiente'
  banda              TEXT,      -- 'alta' | 'media' | 'baja'
  dias_datos         INTEGER,
  banda_provisoria   BOOLEAN,
  estado_autonomico  TEXT,
  hrv_metrica        TEXT,      -- 'rmssd' | 'sdnn' | NULL
  discordancia       BOOLEAN,
  cobertura          JSONB,
  componentes        JSONB,
  motivos            JSONB
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
WITH
-- ── 1. Una fila por (fecha, tipo): resolver el conflicto multi-fuente ──────
-- La unique key de la tabla es (cliente, fecha, tipo, fuente), así que el mismo
-- día puede tener el mismo tipo de varias fuentes. Prioridad:
--   a) para hrv_ms, rMSSD SIEMPRE le gana a SDNN (métrica correcta > ruidosa)
--   b) dispositivo dedicado > Apple Health > agregador > carga manual
serie AS (
  SELECT DISTINCT ON (s.fecha, s.tipo)
         s.fecha, s.tipo, s.valor, s.fuente,
         s.detalle->>'metrica' AS metrica,
         COALESCE((s.detalle->>'estimado')::BOOLEAN, FALSE) AS estimado
  FROM mypump_salud_diaria s
  WHERE s.cliente_id = p_cliente_id
    AND s.fecha BETWEEN (p_desde - 75) AND p_hasta
  ORDER BY s.fecha, s.tipo,
    (CASE WHEN s.tipo = 'hrv_ms' AND s.detalle->>'metrica' = 'rmssd' THEN 0 ELSE 1 END),
    (CASE s.fuente WHEN 'whoop' THEN 0 WHEN 'oura' THEN 0 WHEN 'withings' THEN 0
                   WHEN 'polar' THEN 0 WHEN 'apple_health' THEN 1
                   WHEN 'rook' THEN 2 ELSE 3 END)
),
-- ── 2. Calendario DENSO ───────────────────────────────────────────────────
-- Sin esto, "7 PRECEDING" significaría "7 filas con dato" y un cliente que
-- sincroniza salteado tendría un baseline de tres semanas atrás disfrazado de
-- media de 7 días.
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
    -- Sueño sin etapas (derivado de 'inBed', no de fases reales) → el
    -- componente pesa 40% menos: es una estimación, no una medición.
    COALESCE(BOOL_OR(s.tipo = 'sueno_min' AND s.estimado), FALSE) AS sueno_estimado
  FROM cal c
  LEFT JOIN serie s ON s.fecha = c.fecha
  GROUP BY c.fecha
),
base AS (
  SELECT p.*, CASE WHEN p.hrv > 0 THEN LN(p.hrv) END AS ln_hrv
  FROM piv p
),
-- ── 4. Baselines: media móvil 7d (la señal) y banda 60d (el rango normal) ──
-- Ambas EXCLUYEN el día evaluado (1 PRECEDING) — si no, el propio valor
-- arrastraría su baseline y aplanaría la desviación.
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
    -- deuda de sueño: media de las 3 noches previas
    AVG(b.sueno)   OVER w3  AS sueno_mu3,
    -- regularidad: dispersión del punto medio del sueño en la última semana
    STDDEV_SAMP(b.sueno_medio) OVER w7 AS sueno_medio_sd7,
    -- bandas de las señales secundarias
    AVG(b.resp) OVER w60 AS resp_mu60, STDDEV_SAMP(b.resp) OVER w60 AS resp_sd60,
    AVG(b.spo2) OVER w60 AS spo2_mu60, STDDEV_SAMP(b.spo2) OVER w60 AS spo2_sd60,
    AVG(b.temp) OVER w60 AS temp_mu60, STDDEV_SAMP(b.temp) OVER w60 AS temp_sd60,
    -- cuántos días con AL MENOS una métrica objetiva lleva acumulados
    COUNT(CASE WHEN b.rhr IS NOT NULL OR b.hrv IS NOT NULL OR b.sueno IS NOT NULL
               THEN 1 END) OVER wall AS dias_datos
  FROM base b
  WINDOW
    w3   AS (ORDER BY b.fecha ROWS BETWEEN  3 PRECEDING AND 1 PRECEDING),
    w7   AS (ORDER BY b.fecha ROWS BETWEEN  7 PRECEDING AND 1 PRECEDING),
    w60  AS (ORDER BY b.fecha ROWS BETWEEN 60 PRECEDING AND 1 PRECEDING),
    wall AS (ORDER BY b.fecha ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
),
-- ── 5. CV semanal de HRV y su referencia de 60 días ────────────────────────
-- El CV exige ≥3 mediciones en la ventana (Plews: menos de 3 no da un promedio
-- semanal válido). Como referencia se usa la media de 60d del propio CV — no
-- la mediana, porque no existe como window function y la diferencia práctica
-- sobre una medida que ya es de dispersión es menor.
cv AS (
  SELECT bl.*,
    -- CV en %, sobre la escala ORIGINAL del HRV.
    -- hrv_sd7/hrv_mu7 son el desvio y la media de los LOGARITMOS, asi que
    -- sd7/mu7 no es un coeficiente de variacion: es el desvio de los logs
    -- dividido por ln(HRV basal) ~= 3.8, o sea ~4x mas chico de lo real.
    -- Para una variable lognormal —el HRV lo es— el CV se aproxima por el
    -- DESVIO DE SUS LOGS. Con eso, el umbral SWC = 0.5*CV vuelve a ser
    -- 0.005*cv7, y el cv7 que ve el coach en `cobertura` pasa a ser un numero
    -- comparable con la literatura (~10-20% en rMSSD) en vez de un ~4% que no
    -- significaba nada.
    -- `cv_alto` (mas abajo) compara cv7 contra su propio promedio, asi que es
    -- una RAZON y el factor se cancelaba: ese no cambia de comportamiento.
    CASE WHEN bl.hrv_n7 >= 3
         THEN ABS(bl.hrv_sd7) * 100 END AS cv7
  FROM bl
),
cvr AS (
  SELECT cv.*, AVG(cv.cv7) OVER (ORDER BY cv.fecha ROWS BETWEEN 60 PRECEDING AND 1 PRECEDING) AS cv_ref
  FROM cv
),
-- ── 6. z-scores + puerta SWC ──────────────────────────────────────────────
-- SWC = 0.5 × CV. Si la desviación no lo supera, el z se fuerza a 0: el score
-- NO se mueve por ruido de medición. Es lo que hace que un número entero de
-- 0-100 sea honesto en vez de teatro de precisión.
z AS (
  SELECT c.*,
    -- ELSE 0, NO NULL. El comentario de arriba siempre dijo "se fuerza a 0",
    -- pero el CASE no tenia ELSE, asi que un dia con HRV ESTABLE devolvia NULL
    -- — el mismo valor que "no hay HRV". Y aguas abajo eso cambia de formula:
    --   con las dos senales: 50 + 50*clamp((z_hrv - z_rhr)/4)
    --   sin HRV:             50 - 50*clamp(z_rhr/2)
    -- o sea que los dias mas estables pasaban a tener el DOBLE de sensibilidad
    -- a la FC en reposo, que es exactamente lo contrario de lo que la puerta
    -- SWC quiere lograr. Con z_rhr = +1 SD: 37.5 esperado vs 25 real, 12.5
    -- puntos de diferencia en el score. NULL queda solo para "no hay dato".
    CASE
      WHEN c.ln_hrv IS NULL OR c.hrv_mu7 IS NULL OR NOT (c.hrv_sd60 > 0) THEN NULL
      WHEN ABS(c.ln_hrv - c.hrv_mu7) >= COALESCE(0.005 * c.cv_ref, 0)
        THEN (c.ln_hrv - c.hrv_mu7) / c.hrv_sd60
      ELSE 0
    END AS z_hrv,
    CASE WHEN c.rhr_sd60 > 0 AND c.rhr IS NOT NULL AND c.rhr_mu7 IS NOT NULL
         THEN (c.rhr - c.rhr_mu7) / c.rhr_sd60 END AS z_rhr,
    (c.cv7 IS NOT NULL AND c.cv_ref IS NOT NULL AND c.cv7 > 1.3 * c.cv_ref) AS cv_alto
  FROM cvr c
),
-- ── 7. Carga del gimnasio: agudo (3d) vs crónico (28d prorrateado) ─────────
-- Series duras = RIR ≤ 2 (cerca del fallo). El tonelaje solo no alcanza:
-- 20 series fáciles no fatigan como 10 al fallo.
dia_carga AS (
  SELECT (r.registrado_en AT TIME ZONE 'America/Argentina/Buenos_Aires')::DATE AS fecha,
         COUNT(*) FILTER (WHERE r.rir_real IS NOT NULL AND r.rir_real <= 2) AS series_duras,
         COALESCE(SUM(r.peso_kg * r.reps_realizadas), 0) AS tonelaje
  FROM mypump_registros_carga r
  WHERE r.cliente_id = p_cliente_id
    AND r.registrado_en >= (p_desde - 75)::TIMESTAMPTZ
  GROUP BY 1
),
carga AS (
  SELECT c.fecha,
    SUM(COALESCE(dc.series_duras, 0)) OVER w3  AS agudo,
    SUM(COALESCE(dc.series_duras, 0)) OVER w28 AS cronico,
    SUM(COALESCE(dc.tonelaje, 0))     OVER w28 AS ton28
  FROM cal c
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
  SELECT z.*, ca.agudo, ca.cronico, sj.s_d,

    -- A · AUTONÓMICO (HRV ⊕ FC reposo, fusionados a propósito)
    -- El umbral U se ensancha con SDNN: con MAPE ~29% hace falta una
    -- desviación mucho mayor para creerle a un solo día.
    CASE WHEN z.hrv_metrica = 'rmssd' THEN 1.0 ELSE 1.5 END AS u_umbral,

    -- B.1 duración: 100 a partir de 7.5h, cae lineal a 0 en 4.5h.
    -- Dormir de más NO suma (no hay evidencia de que 10h recuperen más que 8).
    CASE WHEN z.sueno IS NULL THEN NULL
         ELSE GREATEST(0, LEAST(100, (z.sueno - 270) / (450 - 270) * 100)) END AS s_dur,
    -- B.2 deuda acumulada de las 3 noches previas
    CASE WHEN z.sueno_mu3 IS NULL THEN NULL
         ELSE GREATEST(0, LEAST(100, (z.sueno_mu3 - 270) / (450 - 270) * 100)) END AS s_deuda,
    -- B.3 regularidad: SD del punto medio del sueño (100 a ≤30min, 0 a ≥90min)
    CASE WHEN z.sueno_medio_sd7 IS NULL THEN NULL
         ELSE GREATEST(0, LEAST(100, (90 - z.sueno_medio_sd7) / 60 * 100)) END AS s_reg,

    -- C · CARGA: ratio agudo:crónico. 100 si ≤0.8, 50 en 1.3, 0 desde 2.0.
    CASE WHEN ca.cronico IS NULL OR ca.cronico < 6 THEN NULL   -- <6 series/28d = no entrena
         ELSE (WITH r AS (SELECT ca.agudo::NUMERIC / NULLIF(ca.cronico::NUMERIC * 3 / 28, 0) AS v)
               SELECT CASE WHEN r.v IS NULL THEN NULL
                           WHEN r.v <= 0.8 THEN 100
                           WHEN r.v >= 2.0 THEN 0
                           WHEN r.v <= 1.3 THEN 100 - (r.v - 0.8) / 0.5 * 50
                           ELSE 50 - (r.v - 1.3) / 0.7 * 50 END FROM r) END AS s_c,

    -- E · OTRAS SEÑALES: solo desviación de la banda propia, nunca valor
    -- absoluto. Cada una descuenta hasta 25 puntos si se sale de ±2 SD.
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
-- ── 10. Veredicto autonómico + pesos ──────────────────────────────────────
sa AS (
  SELECT sc.*,
    CASE
      WHEN sc.z_hrv IS NOT NULL AND sc.z_rhr IS NOT NULL THEN
        CASE
          WHEN sc.z_hrv <= -sc.u_umbral AND sc.z_rhr >= sc.u_umbral AND sc.cv_alto      THEN 'maladaptacion'
          WHEN sc.z_hrv <= -sc.u_umbral AND sc.z_rhr >= sc.u_umbral                     THEN 'fatiga_acumulada'
          -- Saturación parasimpática: HRV y FC bajas A LA VEZ. Es un fenómeno de
          -- atletas de resistencia de élite con bradicardia real, así que además
          -- del z se exige FC en reposo < 50 lpm en términos absolutos. Sin esa
          -- condición, cualquier día en que ambas señales caen juntas por ruido
          -- se marcaba como saturación y se comía 55 puntos de score — lo vimos
          -- disparar con FC de 54 en el test de la UI.
          WHEN sc.z_hrv <= -sc.u_umbral AND sc.z_rhr <= -sc.u_umbral AND sc.rhr < 50    THEN 'parasimpatico_saturado'
          WHEN sc.z_hrv >= 0.5 AND ABS(sc.z_rhr) < 0.5                                  THEN 'recuperado'
          ELSE 'normal' END
      WHEN sc.z_rhr IS NOT NULL THEN
        CASE WHEN sc.z_rhr >= 1.5 THEN 'fc_elevada'
             WHEN sc.z_rhr <= -1.0 THEN 'recuperado' ELSE 'normal' END
      ELSE NULL END AS v_auto,

    -- s_A base: la diferencia entre las dos señales es la que informa.
    -- Con las dos, (z_hrv - z_rhr) captura el gradiente completo; sin HRV se
    -- cae a FC reposo sola, que es la métrica más robusta que existe.
    CASE
      WHEN sc.z_hrv IS NOT NULL AND sc.z_rhr IS NOT NULL
        THEN 50 + 50 * GREATEST(-1, LEAST(1, (sc.z_hrv - sc.z_rhr) / 4))
      WHEN sc.z_hrv IS NOT NULL
        THEN 50 + 50 * GREATEST(-1, LEAST(1, sc.z_hrv / 2))
      WHEN sc.z_rhr IS NOT NULL
        THEN 50 - 50 * GREATEST(-1, LEAST(1, sc.z_rhr / 2))
      WHEN sc.rhr IS NOT NULL OR sc.hrv IS NOT NULL
        THEN 50            -- hay dato pero todavía no hay baseline → neutro
      ELSE NULL END AS s_a_base
  FROM sc
),
fin AS (
  SELECT sa.*,
    -- Tope por veredicto: un cuadro de maladaptación no puede dar 70 porque
    -- durmió bien. La fisiología manda sobre el promedio ponderado.
    CASE sa.v_auto
      WHEN 'maladaptacion'          THEN LEAST(sa.s_a_base, 25)
      WHEN 'fatiga_acumulada'       THEN LEAST(sa.s_a_base, 35)
      WHEN 'parasimpatico_saturado' THEN LEAST(sa.s_a_base, 45)
      ELSE sa.s_a_base END AS s_a,
    -- B: media ponderada de lo que haya de sueño
    CASE WHEN sa.s_dur IS NULL THEN NULL ELSE
      (sa.s_dur * 0.5 + COALESCE(sa.s_deuda, sa.s_dur) * 0.3 + COALESCE(sa.s_reg, sa.s_dur) * 0.2)
    END AS s_b,
    CASE WHEN sa.hay_e THEN GREATEST(0, LEAST(100, sa.s_e_raw)) ELSE NULL END AS s_e
  FROM sa
),
w AS (
  SELECT fin.*,
    -- Pesos. Con rMSSD el bloque autonómico pesa más porque el dato es bueno;
    -- con SDNN del Apple Watch pesa menos porque es ruidoso; sin HRV, el peso
    -- se reparte hacia sueño (que pasa a ser la señal principal).
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
)
SELECT
  t.fecha,
  -- El score solo existe si hay baseline (≥14 días) Y peso suficiente (≥45).
  CASE WHEN t.dias_datos >= 14 AND t.w_tot >= 45
       THEN ROUND(t.num / NULLIF(t.w_tot, 0))::INTEGER END AS score,
  CASE WHEN t.w_tot < 45      THEN 'insuficiente'
       WHEN t.dias_datos < 14 THEN 'calibrando'
       ELSE 'ok' END AS estado,
  CASE WHEN t.dias_datos >= 14 AND t.w_tot >= 45 THEN
    CASE WHEN t.num / NULLIF(t.w_tot,0) >= 67 THEN 'alta'
         WHEN t.num / NULLIF(t.w_tot,0) >= 34 THEN 'media'
         ELSE 'baja' END END AS banda,
  t.dias_datos::INTEGER,
  (t.dias_datos < 30) AS banda_provisoria,
  t.v_auto AS estado_autonomico,
  t.hrv_metrica,
  -- Discordancia: el motor y la persona dicen cosas distintas. No es un error
  -- del cliente ni del sensor: es información, y gana lo que el cliente siente.
  (t.s_d IS NOT NULL AND t.w_tot >= 45 AND t.dias_datos >= 14
   AND ABS(t.num / NULLIF(t.w_tot,0) - t.s_d) >= 40) AS discordancia,
  jsonb_strip_nulls(jsonb_build_object(
    'hrv',      t.hrv, 'fc_reposo', t.rhr, 'sueno_min', t.sueno,
    'cv7',      ROUND(t.cv7, 1), 'cv_alto', t.cv_alto,
    'z_hrv',    ROUND(t.z_hrv, 2), 'z_rhr', ROUND(t.z_rhr, 2)
  )) AS cobertura,
  jsonb_strip_nulls(jsonb_build_object(
    -- CASE, igual que los otros cuatro: sin dato cardiaco s_a es NULL y
    -- jsonb_strip_nulls (que es recursivo) borraba solo el campo interno,
    -- dejando {"autonomico": {"peso": 0}}. La app itera las claves presentes
    -- y hacia Math.round(undefined) -> pintaba "NaN" en la fila del corazon.
    'autonomico', CASE WHEN t.s_a IS NULL THEN NULL
                       ELSE jsonb_build_object('score', ROUND(t.s_a), 'peso', t.w_a) END,
    'sueno',      CASE WHEN t.s_b IS NULL THEN NULL ELSE jsonb_build_object('score', ROUND(t.s_b), 'peso', ROUND(t.w_b)) END,
    'carga',      CASE WHEN t.s_c IS NULL THEN NULL ELSE jsonb_build_object('score', ROUND(t.s_c), 'peso', t.w_c, 'agudo', t.agudo, 'cronico', t.cronico) END,
    'subjetivo',  CASE WHEN t.s_d IS NULL THEN NULL ELSE jsonb_build_object('score', ROUND(t.s_d), 'peso', t.w_d) END,
    'otros',      CASE WHEN t.s_e IS NULL THEN NULL ELSE jsonb_build_object('score', ROUND(t.s_e), 'peso', t.w_e) END
  )) AS componentes,
  -- Motivos = HECHOS estructurados, no frases. La copy la arma cada consumidor:
  -- la app en voseo, el panel en tono clínico, el centinela en su registro.
  -- Un solo motor, tres voces.
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
     SELECT jsonb_build_object('tipo','regularidad','dir',-1,'valor',ROUND(t.sueno_medio_sd7),
                               'peso', 100 - t.s_reg)
     WHERE t.s_reg IS NOT NULL AND t.s_reg < 50
   ) q) AS motivos
FROM tot t
WHERE t.fecha BETWEEN p_desde AND p_hasta
ORDER BY t.fecha;
$$;
