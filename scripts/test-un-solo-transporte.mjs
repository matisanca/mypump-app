#!/usr/bin/env node
/* =============================================================
   test-un-solo-transporte.mjs — un teléfono, un push. No dos.

   POR QUÉ EXISTE
   `activarPushSiCorresponde()` lanzaba el registro nativo y la suscripción de
   Web Push EN PARALELO, con este comentario: "se intentan los dos porque
   preguntar '¿cuál soy?' acá duplicaría la lógica de plataforma". El
   razonamiento era bueno y el resultado estaba mal por un motivo que no estaba
   escrito en ningún lado: adentro de la app el Web Push no se caía por diseño,
   se caía porque NINGÚN WebView expone `PushManager`. iOS/WKWebView no lo
   tiene, el WebView de Android tampoco.

   O sea: la garantía de "un solo transporte" no la daba nuestro código, la
   daba una limitación de terceros que nadie nos prometió mantener. El día que
   Google la levante —y viene levantando cosas del WebView todos los años— el
   mismo teléfono queda registrado dos veces en `mypump_push_devices`, y como
   el sender manda un aviso POR DEVICE, cada mensaje del chat llega duplicado.
   A 62 personas, sin que se rompa nada que se pueda ver desde acá.

   Eso hasta hoy era teórico porque en Android el push nativo estaba apagado
   (`MYPUMP_FCM = false`, sin google-services.json). Con Firebase adentro del
   binario dejó de serlo.

   LO QUE FIJA ESTE TEST
   1. Si el nativo se registra, NO se suscribe Web Push. Ni aunque el entorno
      lo permita todo (ese es el punto: se simula el WebView del futuro).
   2. Si el nativo NO está —Android sin Firebase, o el navegador— Web Push
      sigue saliendo. La red de abajo no se puede perder: es la que cubre a los
      62 de hoy, que entran por el link del navegador.
   3. Si el nativo está pero FALLA (APNs no contesta, error de registro), Web
      Push queda como respaldo. Eso antes no existía.

   El 2 es el que más importa: es fácil "arreglar" el 1 con un `if (nativo)
   return` de más arriba y dejar sin push a todo el mundo.

   USO:  node scripts/test-un-solo-transporte.mjs
   ============================================================= */

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const raiz = path.join(path.dirname(fileURLToPath(import.meta.url)), '..');
const SRC = fs.readFileSync(path.join(raiz, 'public/js/notificaciones.js'), 'utf8');

/* ── Un entorno por escenario ────────────────────────────────────────────
   notificaciones.js es un IIFE con estado propio (los `localStorage` de
   "último token enviado"), así que cada caso arranca de cero. Si se
   compartiera, el segundo escenario vería el device del primero ya guardado y
   pasaría por el motivo equivocado. */
function montar({ plataforma, fcm, nativoResponde, pushApiEnWebview }) {
  const store = {};
  const REGISTRADOS = { nativo: [], web: [] };

  const g = {};
  g.window = g;
  g.localStorage = {
    getItem: k => (k in store ? store[k] : null),
    setItem: (k, v) => { store[k] = String(v); },
    removeItem: k => { delete store[k]; },
  };
  g.document = { addEventListener() {}, hidden: false };
  g.addEventListener = () => {};
  g.console = console;
  g.setTimeout = setTimeout;
  g.clearTimeout = clearTimeout;
  g.Promise = Promise;
  g.atob = s => Buffer.from(s, 'base64').toString('binary');
  g.Uint8Array = Uint8Array;
  g.JSON = JSON;
  g.Notification = { permission: 'granted' };

  g.TOKEN = 'tok-cliente';
  g.MYPUMP_FCM = fcm;
  g.MYPUMP_CONFIG = {
    // La real, para que `applicationServerKey` no explote en el b64→bytes.
    VAPID_PUBLIC_KEY: 'BNvglUfWzZHzfotOBnoa7mxfB-GrtWFZACAxHec7BhKaJfLINFs64jxAdV6XWFtcElQdFz6OhsSmyfBHcWz3SXs',
  };

  g.mypumpDB = {
    registrarPush: async (_t, device, plat) => {
      REGISTRADOS.nativo.push({ device, plat });
      return { success: true, data: {} };
    },
    registrarPushWeb: async (_t, endpoint) => {
      REGISTRADOS.web.push({ endpoint });
      return { success: true, data: {} };
    },
  };

  /* El WebView del futuro: Push API disponible adentro de la app nativa.
     Es exactamente el escenario que hoy no se puede reproducir en un teléfono
     y por el que existe este archivo. */
  if (pushApiEnWebview) {
    g.PushManager = function () {};
    g.navigator = {
      serviceWorker: {
        ready: Promise.resolve({
          pushManager: {
            getSubscription: async () => null,
            subscribe: async () => ({
              toJSON: () => ({
                endpoint: 'https://fcm.googleapis.com/wp/ENDPOINT-DE-PRUEBA',
                keys: { p256dh: 'p256dh-de-prueba', auth: 'auth-de-prueba' },
              }),
            }),
          },
        }),
      },
    };
  } else {
    g.navigator = {};
  }

  const listeners = {};
  const nativoDisponible = plataforma !== 'web';
  g.Capacitor = {
    isNativePlatform: () => nativoDisponible,
    getPlatform: () => plataforma,
    Plugins: {
      LocalNotifications: {
        checkPermissions: async () => ({ display: 'granted' }),
        requestPermissions: async () => ({ display: 'granted' }),
        getPending: async () => ({ notifications: [] }),
        cancel: async () => {},
        schedule: async () => {},
        addListener: () => ({ remove() {} }),
      },
      // En el navegador el plugin no existe; adentro de la app sí.
      ...(nativoDisponible ? {
        PushNotifications: {
          addListener: (ev, fn) => { listeners[ev] = fn; return { remove() {} }; },
          register: async () => {
            if (nativoResponde === 'ok') listeners.registration?.({ value: 'DEVICE-TOKEN-123' });
            else if (nativoResponde === 'error') listeners.registrationError?.({ error: 'no' });
            // 'timeout' → nadie contesta nunca, y el timeout de 15s decide.
          },
          checkPermissions: async () => ({ receive: 'granted' }),
          requestPermissions: async () => ({ receive: 'granted' }),
        },
      } : {}),
    },
  };

  new Function('window', 'globalThis', `with (window) { ${SRC} }`)(g, g);
  return { N: g.MyPumpNotif, REGISTRADOS };
}

// ── Framework ───────────────────────────────────────────────────────────
let ok = 0, fail = 0;
const t = async (n, fn) => {
  try { await fn(); console.log(`  ✓ ${n}`); ok++; }
  catch (e) { console.log(`  ✗ ${n}\n      ${e.message}`); fail++; }
};
const eq = (a, b, m) => { if (a !== b) throw new Error(`${m}: esperaba ${JSON.stringify(b)}, vino ${JSON.stringify(a)}`); };

console.log('\n=== Un teléfono, un transporte ===\n');

await t('iOS nativo: se registra APNs y NO se suscribe Web Push', async () => {
  const { N, REGISTRADOS } = montar({
    plataforma: 'ios', fcm: false, nativoResponde: 'ok', pushApiEnWebview: true,
  });
  await N.registrarPush();
  eq(REGISTRADOS.nativo.length, 1, 'devices nativos');
  eq(REGISTRADOS.nativo[0].plat, 'ios', 'plataforma declarada');
  eq(REGISTRADOS.web.length, 0, 'suscripciones web (el teléfono quedaría duplicado)');
});

await t('Android CON Firebase: se registra FCM y NO se suscribe Web Push', async () => {
  const { N, REGISTRADOS } = montar({
    plataforma: 'android', fcm: true, nativoResponde: 'ok', pushApiEnWebview: true,
  });
  await N.registrarPush();
  eq(REGISTRADOS.nativo.length, 1, 'devices nativos');
  eq(REGISTRADOS.nativo[0].plat, 'android', 'plataforma declarada');
  eq(REGISTRADOS.web.length, 0, 'suscripciones web (el teléfono quedaría duplicado)');
});

await t('Android SIN Firebase: no toca el nativo y Web Push lo cubre igual', async () => {
  // `PushNotifications.register()` acá mataría el proceso, así que PUSH()
  // devuelve null antes de llamarlo. Lo que no puede pasar es que además se
  // quede sin Web Push: sería un cliente sin ningún aviso.
  const { N, REGISTRADOS } = montar({
    plataforma: 'android', fcm: false, nativoResponde: 'ok', pushApiEnWebview: true,
  });
  await N.registrarPush();
  eq(REGISTRADOS.nativo.length, 0, 'devices nativos (register() cierra la app)');
  eq(REGISTRADOS.web.length, 1, 'suscripciones web');
});

await t('navegador: no hay plugin nativo y sale Web Push', async () => {
  // El caso de los 62 de hoy: entran por el link, sin instalar nada.
  const { N, REGISTRADOS } = montar({
    plataforma: 'web', fcm: false, nativoResponde: 'ok', pushApiEnWebview: true,
  });
  await N.registrarPush();
  eq(REGISTRADOS.nativo.length, 0, 'devices nativos');
  eq(REGISTRADOS.web.length, 1, 'suscripciones web');
});

await t('el nativo falla: Web Push queda de red', async () => {
  const { N, REGISTRADOS } = montar({
    plataforma: 'ios', fcm: false, nativoResponde: 'error', pushApiEnWebview: true,
  });
  await N.registrarPush();
  eq(REGISTRADOS.nativo.length, 0, 'devices nativos');
  eq(REGISTRADOS.web.length, 1, 'suscripciones web');
});

await t('app nativa en un WebView sin Push API: nada se rompe', async () => {
  // El presente. Se prueba igual para que el día que cambie, cambie el test 1
  // y no este.
  const { N, REGISTRADOS } = montar({
    plataforma: 'ios', fcm: false, nativoResponde: 'ok', pushApiEnWebview: false,
  });
  await N.registrarPush();
  eq(REGISTRADOS.nativo.length, 1, 'devices nativos');
  eq(REGISTRADOS.web.length, 0, 'suscripciones web');
});

console.log(`\n${fail === 0 ? '✅' : '❌'}  ${ok} pasaron, ${fail} fallaron\n`);
process.exit(fail === 0 ? 0 : 1);
