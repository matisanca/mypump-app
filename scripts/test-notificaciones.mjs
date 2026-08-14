#!/usr/bin/env node
/* =============================================================
   test-notificaciones.mjs — que la app mande UN solo recordatorio

   POR QUÉ EXISTE
   Hasta ahora la app programaba cuatro avisos locales: entrenar (todos los
   días), la revisión (domingo), pesarse y "cerrá el día". Cuatro por semana de
   una app de coaching se leen como ruido, y lo que hace el cliente con el ruido
   no es apagar el que molesta: entra a Ajustes y apaga TODO. Con eso se lleva
   puesto el único que le importa al negocio — el de la revisión del domingo,
   que es el que sostiene el seguimiento semanal.

   Así que ahora hay uno solo. Y esa clase de decisión se deshace sola con el
   tiempo: alguien va a querer "un avisito para pesarse" y va a ser una línea.
   Este test es el que dice que no. Si el conteo pasa de 1, se pone rojo y hay
   que borrarlo a propósito, no de casualidad.

   LO QUE PROTEGE, Y QUE NO ES OBVIO
   Los tres avisos eliminados ya están AGENDADOS en el sistema operativo de todo
   cliente que abrió la app antes de este cambio. Borrar el código no los
   cancela: iOS/Android los siguen disparando hasta que alguien pida su baja por
   id. Un cliente que actualice seguiría recibiendo "Hoy toca entrenar 💪" para
   siempre, sin que exista una sola línea en el repo que lo explique. El test 3
   es el que cubre eso y es el que de verdad importa.

   USO:  node scripts/test-notificaciones.mjs
   ============================================================= */

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const raiz = path.join(path.dirname(fileURLToPath(import.meta.url)), '..');

// ── Entorno mínimo de navegador ─────────────────────────────────────────
const store = {};
globalThis.localStorage = {
  getItem: k => (k in store ? store[k] : null),
  setItem: (k, v) => { store[k] = String(v); },
  removeItem: k => { delete store[k]; },
};
globalThis.document = { addEventListener() {}, hidden: false };
globalThis.window = globalThis;
globalThis.addEventListener = () => {};

// ── Mock del plugin de notificaciones locales ───────────────────────────
// `pendientes` simula lo que el sistema tiene agendado. Arranca con los tres
// viejos puestos: es exactamente el teléfono de un cliente que actualiza.
let permiso = 'granted';
let pendientes = [{ id: 1001 }, { id: 1002 }, { id: 1003 }, { id: 1004 }];
const AGENDADO = [];
const CANCELADO = [];

globalThis.Capacitor = {
  isNativePlatform: () => true,
  getPlatform: () => 'ios',
  Plugins: {
    LocalNotifications: {
      checkPermissions: async () => ({ display: permiso }),
      requestPermissions: async () => ({ display: permiso }),
      getPending: async () => ({ notifications: pendientes.slice() }),
      cancel: async ({ notifications }) => {
        for (const n of notifications) {
          CANCELADO.push(Number(n.id));
          pendientes = pendientes.filter(p => Number(p.id) !== Number(n.id));
        }
      },
      schedule: async ({ notifications }) => {
        AGENDADO.push(...notifications);
        pendientes.push(...notifications.map(n => ({ id: n.id })));
      },
      addListener: () => ({ remove() {} }),
    },
    // El registro de push sale por acá; que no explote alcanza.
    PushNotifications: {
      register: async () => {},
      addListener: () => ({ remove() {} }),
      checkPermissions: async () => ({ receive: 'granted' }),
      requestPermissions: async () => ({ receive: 'granted' }),
    },
  },
};

const src = fs.readFileSync(path.join(raiz, 'public/js/notificaciones.js'), 'utf8');
new Function(src)();
const N = globalThis.MyPumpNotif;

// ── Framework ───────────────────────────────────────────────────────────
let ok = 0, fail = 0;
const t = async (n, fn) => {
  try { await fn(); console.log(`  ✓ ${n}`); ok++; }
  catch (e) { console.log(`  ✗ ${n}\n      ${e.message}`); fail++; }
};
const eq = (a, b, m) => { if (a !== b) throw new Error(`${m}: esperaba ${JSON.stringify(b)}, vino ${JSON.stringify(a)}`); };

const reset = () => { AGENDADO.length = 0; CANCELADO.length = 0; };

console.log('\n=== Recordatorios locales ===\n');

await t('programa UNA sola notificación, no cuatro', async () => {
  reset();
  const r = await N.reprogramar();
  eq(r.ok, true, 'reprogramar');
  eq(AGENDADO.length, 1, 'cantidad de recordatorios agendados');
});

await t('la única que queda es la de la revisión, y cae domingo', async () => {
  const n = AGENDADO[0];
  eq(n.id, 1002, 'id');
  eq(n.extra.destino, 'revision', 'destino del tap');
  eq(n.schedule.on.weekday, 1, 'weekday (1 = domingo)');
  if (!/revisi/i.test(n.title)) throw new Error(`el título no habla de la revisión: "${n.title}"`);
});

await t('da de baja las tres viejas que quedaron agendadas en el teléfono', async () => {
  // El caso real: el cliente actualiza la app. 1001/1003/1004 ya están puestas
  // en el sistema y NADIE más las va a borrar — sacar el código no alcanza.
  for (const id of [1001, 1003, 1004]) {
    if (!CANCELADO.includes(id)) throw new Error(`la notificación ${id} quedó viva en el teléfono del cliente`);
  }
  const vivas = pendientes.map(p => Number(p.id)).filter(id => id !== 1002);
  eq(vivas.length, 0, `quedaron ids ajenos agendados: ${vivas.join(', ')}`);
});

await t('los textos declarados son exactamente uno', async () => {
  // Segundo candado, por si alguien agrega el texto antes que el schedule.
  eq(Object.keys(N.TEXTOS).length, 1, 'entradas en TEXTOS');
  eq(Object.keys(N.prefs()).length, 1, 'entradas en prefs');
});

await t('si el cliente la apaga, no queda ninguna agendada', async () => {
  reset();
  await N.setPref('check', { on: false });
  const r = await N.reprogramar();
  eq(r.ok, true, 'reprogramar');
  eq(r.programadas, 0, 'programadas');
  eq(AGENDADO.length, 0, 'nada agendado');
  await N.setPref('check', { on: true });
});

await t('sin permiso no agenda nada (y no rompe)', async () => {
  reset();
  permiso = 'denied';
  const r = await N.reprogramar();
  eq(r.ok, false, 'ok');
  eq(r.motivo, 'sin_permiso', 'motivo');
  eq(AGENDADO.length, 0, 'nada agendado');
  permiso = 'granted';
});

console.log(`\n${fail === 0 ? '✅' : '❌'}  ${ok} pasaron, ${fail} fallaron\n`);
process.exit(fail === 0 ? 0 : 1);
