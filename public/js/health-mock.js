/* =============================================================
   health-mock.js — hacerse pasar por el plugin de HealthKit, en la Mac

   POR QUÉ EXISTE
   El flujo real de salud (onboarding → hoja de permisos → sync de 7 días →
   backfill de 60 → ingest → motor → cards) solo se podía recorrer con un
   iPhone en la mano. Eso convertía cada cambio de UI en un ciclo de build +
   TestFlight + probar a ojo, y por eso llegaron a producción cosas como un
   botón que no hacía nada y un onboarding que se colgaba minutos.

   Este archivo miente en la capa MÁS BAJA posible: se hace pasar por
   window.Capacitor y por el plugin Health. Todo lo de arriba —el bridge, el
   ingest, el motor de recuperación, las cards— es el código real, sin una sola
   rama de "si estamos testeando". Un mock más arriba probaría el mock.

   NUNCA SE ACTIVA EN PRODUCCIÓN. Triple compuerta en el loader de cliente.html:
     1. ?mockhealth=1 explícito en la URL
     2. NO hay un Capacitor real (o sea: nunca dentro de la app nativa)
     3. el host es localhost / 127.0.0.1
   Y no está en el SHELL del service worker, así que ni siquiera se cachea.

   PARÁMETROS
     ?mockhealth=1            enciende esto
     &mockescenario=normal    normal | fatiga | maladaptacion | sin-reloj | recien-conectado
     &mockseed=42             semilla del generador
     &mockdias=60             cuántos días de historia simulada
     &mockdeny=1              el cliente "acepta" la hoja pero no llega NADA
                              (camino sinDatos → aviso de Ajustes)
     &mockreset=1             borra el estado local de salud y el onboarding,
                              para volver a ver el flujo desde cero
     &mocklento=1             mete 700 ms por lectura del backfill: sirve para
                              VER el progreso y comprobar que la UI no se traba

   Ver docs/BANCO_PRUEBAS_SALUD.md.
   ============================================================= */
(function () {
  'use strict';

  const q = new URLSearchParams(location.search);
  const GEN = window.MyPumpSaludSintetica;
  if (!GEN) { console.error('[mock] falta salud-sintetica.js'); return; }

  const escenario = q.get('mockescenario') || 'normal';
  const seed      = parseInt(q.get('mockseed') || '42', 10);
  const dias      = parseInt(q.get('mockdias') || '60', 10);
  const denegar   = q.get('mockdeny') === '1';
  const lento     = q.get('mocklento') === '1';

  if (q.get('mockreset') === '1') {
    for (const k of ['mypump_health_connected', 'mypump_health_denegado',
                     'mypump_health_backfill_v1', 'mypump_health_last_sync',
                     'mypump_health_racha_vacia', 'mypump_health_diag',
                     'mypump_onboarding_v1']) {
      try { localStorage.removeItem(k); } catch (e) {}
    }
    console.warn('[mock] estado de salud y onboarding reseteados');
  }

  // Si se pidió denegar, no hay muestras: es indistinguible de un cliente que
  // destildó todo en la hoja de permisos, que es justo lo que se quiere probar.
  const MS = denegar ? {} : GEN.muestras(escenario, dias, seed);

  const dormir = (ms) => new Promise(r => setTimeout(r, ms));

  /* Filtra por ventana igual que HealthKit: devuelve toda muestra que SE SOLAPE
   * con el rango. No es un detalle — el plugin usa predicateForSamples con
   * options:[] y por eso el bridge tiene que deduplicar al partir ventanas. Si
   * acá filtráramos con límites estrictos, ese código nunca se ejercitaría. */
  function enVentana(arr, desde, hasta) {
    const d = new Date(desde).getTime(), h = new Date(hasta).getTime();
    return (arr || []).filter(s =>
      new Date(s.endDate).getTime() >= d && new Date(s.startDate).getTime() <= h);
  }

  const Health = {
    async isAvailable() { return { available: true }; },

    async requestAuthorization({ read }) {
      // La hoja real tarda: sin esta pausa el botón "Conectando…" ni parpadea y
      // no se puede ver si la UI lo maneja bien.
      await dormir(400);
      return { granted: true, read };
    },

    // HealthKit NUNCA informa el permiso de LECTURA: contesta "ya preguntado"
    // haya dicho el cliente que sí o que no. Se replica tal cual, porque es la
    // razón por la que existe toda la lógica de "sospechar por falta de datos".
    async checkAuthorization({ read }) { return { readAuthorized: read, readDenied: [] }; },

    async readSamples({ dataType, startDate, endDate, limit }) {
      if (lento) await dormir(700);
      const arr = enVentana(MS[dataType], startDate, endDate);
      return { samples: limit ? arr.slice(0, limit) : arr };
    },

    async queryAggregated({ dataType, startDate, endDate, bucket }) {
      const arr = enVentana(MS[dataType], startDate, endDate);
      if (!arr.length) return { samples: [] };
      // Solo 3 tipos aceptan queryAggregated en el plugin real, y solo con
      // ciertas operaciones (ver scripts/check-healthkit-tipos.mjs). Un tipo
      // fuera de esa matriz tiene que EXPLOTAR acá igual que en iOS: si no, el
      // banco daría por bueno algo que en el teléfono falla.
      const permitidos = ['steps', 'distance', 'calories', 'activeEnergyBurned',
                          'heartRate', 'weight', 'restingHeartRate'];
      if (permitidos.indexOf(dataType) === -1) {
        throw new Error(`queryAggregated no soporta "${dataType}" (igual que en iOS)`);
      }
      // Un bucket por día, con la suma o el promedio del día.
      const porDia = {};
      for (const s of arr) {
        const k = new Date(s.startDate).toISOString().slice(0, 10);
        (porDia[k] = porDia[k] || []).push(Number(s.value) || 0);
      }
      const promedia = ['heartRate', 'weight', 'restingHeartRate'].indexOf(dataType) !== -1;
      return {
        samples: Object.keys(porDia).sort().map(k => ({
          startDate: `${k}T00:00:00.000Z`, endDate: `${k}T23:59:59.000Z`,
          value: promedia
            ? porDia[k].reduce((a, b) => a + b, 0) / porDia[k].length
            : porDia[k].reduce((a, b) => a + b, 0),
        })),
      };
    },

    async queryWorkouts() { return { workouts: [] }; },
  };

  window.Capacitor = {
    isNativePlatform: () => true,
    getPlatform: () => 'ios',
    Plugins: { Health },
  };

  console.warn(`[mock] HealthKit simulado — escenario "${escenario}", ${dias} días, seed ${seed}` +
               (denegar ? ' · SIN DATOS (mockdeny)' : '') + (lento ? ' · LENTO' : ''));
})();
