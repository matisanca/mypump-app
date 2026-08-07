/* =============================================================
   salud-sintetica.js — datos de salud inventados, pero verosímiles

   POR QUÉ EXISTE
   El pipeline de salud (HealthKit → ingest → motor de recuperación en SQL →
   cards) solo se podía probar con un iPhone real, un reloj real y esperando
   días reales a que se juntara historia. Eso hacía que cada cambio en el motor
   se verificara a ojo, con los datos que hubiera, y que un caso como "cliente
   sin reloj" recién se descubriera cuando un cliente lo reportaba.

   Este módulo genera series de 60 días con la forma que tendrían de verdad, y
   las devuelve en los DOS formatos que hacen falta:
     · filas de ingest  → para scripts/seed-salud.mjs (postea a Supabase)
     · muestras HealthKit → para public/js/health-mock.js (miente el plugin)
   Que sea el mismo generador es el punto: si el mock y el seeder divergieran,
   probaríamos dos pipelines distintos y ninguno sería el real.

   Es UMD a propósito: lo carga un <script> clásico en el navegador (tiene que
   evaluarse ANTES que healthkit-bridge.js, y un módulo ESM siempre difiere) y
   también un require() desde Node.

   NO VA A PRODUCCIÓN: no está en el SHELL del service worker y health-mock.js
   solo lo carga bajo triple compuerta. Ver docs/BANCO_PRUEBAS_SALUD.md.
   ============================================================= */
(function (root, factory) {
  if (typeof module !== 'undefined' && module.exports) module.exports = factory();
  else root.MyPumpSaludSintetica = factory();
})(typeof self !== 'undefined' ? self : this, function () {
  'use strict';

  /* PRNG determinista. Con la misma semilla sale la misma serie: sin esto, un
   * test que falla una vez cada veinte corridas es imposible de reproducir. */
  function mulberry32(a) {
    return function () {
      a |= 0; a = (a + 0x6D2B79F5) | 0;
      let t = Math.imul(a ^ (a >>> 15), 1 | a);
      t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
      return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
  }

  const ESCENARIOS = ['normal', 'fatiga', 'maladaptacion', 'sin-reloj', 'recien-conectado'];

  const ymd = (d) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
  const clamp = (v, lo, hi) => Math.max(lo, Math.min(hi, v));
  const r1 = (v) => Math.round(v * 10) / 10;

  /* Perfil diario según escenario.
   *
   * Los valores están elegidos para caer dentro de mypump_salud_valor_plausible
   * (migración 047) — si se fueran de rango, el RPC los descartaría en silencio
   * y estaríamos "probando" con una tabla vacía.
   *
   * `t` va de 0 (el día más viejo) a 1 (hoy). */
  function perfilDia(escenario, t, rnd) {
    const ruido = (amp) => (rnd() - 0.5) * 2 * amp;
    // Base sana: RHR 52, HRV 65 ms (SDNN), 7h40 de sueño.
    let rhr = 52 + ruido(3);
    let hrv = 65 + ruido(8);
    let sueno = 460 + ruido(35);

    if (escenario === 'fatiga' || escenario === 'maladaptacion') {
      // El deterioro arranca en el último tercio: así el baseline de 60 días
      // tiene de dónde salir y el z-score de los últimos días es real.
      const f = Math.max(0, (t - 0.66) / 0.34);
      rhr += 6 * f;
      hrv -= 13 * f;
      sueno -= 110 * f;
      if (escenario === 'maladaptacion' && f > 0) {
        // Oscilación día a día en la última semana: es lo que dispara cv_alto,
        // el ingrediente que separa "maladaptación" de "fatiga acumulada".
        hrv += (rnd() < 0.5 ? -1 : 1) * 14 * f;
      }
    }
    return {
      fc_reposo: Math.round(clamp(rhr, 25, 140)),
      hrv_ms: Math.round(clamp(hrv, 1, 400)),
      sueno_min: Math.round(clamp(sueno, 0, 1440)),
      pasos: Math.round(clamp(6000 + ruido(4000), 0, 100000)),
      actividad_min: Math.round(clamp(38 + ruido(25), 0, 1440)),
      kcal_activas: Math.round(clamp(430 + ruido(220), 0, 10000)),
      peso_kg: r1(clamp(82 + ruido(0.6), 25, 400)),
    };
  }

  /* Serie de días: [{ fecha, ...métricas }] del más viejo al más nuevo. */
  function generarDias(escenario, dias, seed) {
    const esc = ESCENARIOS.indexOf(escenario) === -1 ? 'normal' : escenario;
    // "recién conectado" es, por definición, poca historia: si respetara --dias
    // no probaría lo que dice probar (el estado `calibrando`).
    const n = esc === 'recien-conectado' ? Math.min(dias || 60, 3) : (dias || 60);
    const rnd = mulberry32((seed == null ? 42 : seed) >>> 0);
    const out = [];
    for (let i = n - 1; i >= 0; i--) {
      const d = new Date(); d.setHours(0, 0, 0, 0); d.setDate(d.getDate() - i);
      out.push(Object.assign({ fecha: ymd(d), _dia: d },
        perfilDia(esc, n === 1 ? 1 : (n - 1 - i) / (n - 1), rnd)));
    }
    return out;
  }

  /* ── Formato 1: filas para mypump_ingest_salud ────────────────────────── */
  function filasIngest(escenario, dias, seed, fuente) {
    const fuenteReal = fuente || 'apple_health';
    const soloDiurno = escenario === 'sin-reloj';
    const regs = [];
    for (const d of generarDias(escenario, dias, seed)) {
      const push = (tipo, valor, detalle) =>
        regs.push(Object.assign({ fecha: d.fecha, tipo, valor, fuente: fuenteReal }, detalle ? { detalle } : {}));

      // Lo que da CUALQUIER iPhone, con o sin reloj.
      push('pasos', d.pasos);
      push('actividad_min', d.actividad_min);
      push('kcal_activas', d.kcal_activas);

      if (soloDiurno) continue;   // el caso "no tengo reloj": nada de la noche

      push('fc_reposo', d.fc_reposo);
      // `metrica` importa: el motor le da más peso a un rMSSD (Oura, Whoop) que
      // a un SDNN de Apple Watch, que se mide en momentos sueltos y tiene ~29%
      // de error. Marcarlo mal cambiaría el score.
      push('hrv_ms', d.hrv_ms, { metrica: 'sdnn', ventana: 'nocturna', n: 12 });
      push('sueno_min', d.sueno_min);
      push('sueno_profundo_min', Math.round(d.sueno_min * 0.19));
      push('sueno_rem_min', Math.round(d.sueno_min * 0.22));
      push('sueno_ligero_min', Math.round(d.sueno_min * 0.59));
      // Punto medio del sueño en minutos desde medianoche (~3:20 AM). Es el
      // insumo de la regularidad: su desvío entre días es lo que se mide.
      push('sueno_medio_min', 200 + Math.round((d.hrv_ms % 7) - 3));
      push('sueno_eficiencia_pct', 88 + Math.round((d.pasos % 8)));
      push('peso_kg', d.peso_kg);
    }
    return regs;
  }

  /* ── Formato 2: muestras con la forma que devuelve el plugin ──────────── */
  const iso = (d, h, m) => {
    const x = new Date(d); x.setHours(h, m || 0, 0, 0); return x.toISOString();
  };

  function muestras(escenario, dias, seed) {
    const soloDiurno = escenario === 'sin-reloj';
    const out = { steps: [], activeEnergyBurned: [], restingHeartRate: [], heartRate: [],
                  heartRateVariability: [], sleep: [], weight: [] };
    for (const d of generarDias(escenario, dias, seed)) {
      const dia = d._dia;
      out.steps.push({ startDate: iso(dia, 0), endDate: iso(dia, 23, 59), value: d.pasos, unit: 'count' });
      out.activeEnergyBurned.push({ startDate: iso(dia, 0), endDate: iso(dia, 23, 59), value: d.kcal_activas, unit: 'kcal' });
      out.weight.push({ startDate: iso(dia, 8), endDate: iso(dia, 8), value: d.peso_kg, unit: 'kg' });
      if (soloDiurno) continue;

      out.restingHeartRate.push({ startDate: iso(dia, 4), endDate: iso(dia, 4), value: d.fc_reposo, unit: 'count/min' });
      // HRV nocturna: el bridge se queda con la mediana de la ventana de sueño.
      for (let k = 0; k < 3; k++) {
        out.heartRateVariability.push({
          startDate: iso(dia, 2 + k), endDate: iso(dia, 2 + k),
          // El plugin entrega SDNN en SEGUNDOS; el bridge lo pasa a ms.
          value: (d.hrv_ms + (k - 1) * 2) / 1000, unit: 's',
        });
      }
      // Sueño de la noche anterior, atribuido al día de despertarse.
      const ini = new Date(dia); ini.setDate(ini.getDate() - 1); ini.setHours(23, 20, 0, 0);
      const fin = new Date(ini.getTime() + d.sueno_min * 60000);
      const et = [['asleepDeep', 0.19], ['asleepREM', 0.22], ['asleepCore', 0.59]];
      let cur = ini.getTime();
      for (const [estado, frac] of et) {
        const dur = d.sueno_min * frac * 60000;
        out.sleep.push({ startDate: new Date(cur).toISOString(), endDate: new Date(cur + dur).toISOString(),
                         value: estado, sleepState: estado, unit: 'min', sourceId: 'com.apple.health.watch' });
        cur += dur;
      }
      out.sleep.push({ startDate: ini.toISOString(), endDate: fin.toISOString(),
                       value: 'inBed', sleepState: 'inBed', unit: 'min', sourceId: 'com.apple.health.watch' });
    }
    return out;
  }

  return { ESCENARIOS, generarDias, filasIngest, muestras, mulberry32 };
});
