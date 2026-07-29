#!/usr/bin/env node
/* =============================================================
 * test-outbox.mjs — la cola de escrituras del cliente.
 *
 * POR QUÉ EXISTE
 * El Outbox es lo único que separa "el cliente cargó la serie" de "la serie
 * está en la base". Vive en el gimnasio, donde la señal es mala: si pierde
 * una escritura, el cliente ya vio el tilde y nadie se entera nunca.
 *
 * Los cuatro casos de abajo son bugs REALES que tenía (29-jul-2026):
 *   · `queue = remaining` al terminar borraba todo lo encolado MIENTRAS el
 *     envío estaba en vuelo — confirmar la serie 2 mientras se manda la 1 la
 *     hacía desaparecer de memoria y de localStorage.
 *   · una RPC que rechaza DEVOLVIENDO NULL (token revocado) se contaba como
 *     guardada y la op se borraba de la cola.
 *   · sin tope de reintentos, un error permanente se reintentaba cada 30 s
 *     para siempre y dejaba el cartel de "sin conexión" pegado.
 *   · `await flush()` volvía al instante si ya había un drenado en curso, así
 *     que cerrar el día no esperaba a que las series se mandaran.
 *
 * Se extrae el IIFE del Outbox de cliente.html y se ejecuta con dobles: es el
 * código REAL, no una reimplementación.
 *
 * USO:  node scripts/test-outbox.mjs
 * ============================================================= */

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const raiz = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const html = fs.readFileSync(path.join(raiz, 'public/cliente.html'), 'utf8');

const ini = html.indexOf('const Outbox = (() => {');
const fin = html.indexOf('})();', ini);
if (ini < 0 || fin < 0) { console.error('✗ no encontré el IIFE del Outbox'); process.exit(1); }
const fuente = html.slice(ini, fin + 5);

let ok = 0, fail = 0;
const t = async (nombre, fn) => {
  try { await fn(); console.log(`  ✓ ${nombre}`); ok++; }
  catch (e) { console.log(`  ✗ ${nombre}\n      ${e.message}`); fail++; }
};
const dormir = (ms) => new Promise(r => setTimeout(r, ms));

/* Monta el Outbox con dobles controlables. `responder` decide qué devuelve
   cada envío; `enviados` registra el orden real. */
function montar(responder) {
  const store = {};
  const enviados = [];
  const ctx = {
    OUTBOX_ENABLED: true,
    TOKEN: 'tok',
    DATA: { dia: { id: 'd1' }, rutina: { semana_actual: 1 } },
    _sesionId: 'ses-1',
    ensureSesionIniciada: async () => 'ses-1',
    navigator: { onLine: true },
    localStorage: {
      getItem: k => (k in store ? store[k] : null),
      setItem: (k, v) => { store[k] = String(v); },
      removeItem: k => { delete store[k]; },
    },
    showSaveState() {}, hideSaveToast() {},
    console: { warn() {}, log() {} },
    setTimeout, clearTimeout, Date,
    window: {
      mypumpDB: {
        _lastError: null,
        registrarCarga: async (_t, _s, datos) => { enviados.push(datos.serie); return responder(datos.serie); },
        getSesionDia: async () => ({ id: 'ses-1' }),
        iniciarSesion: async () => ({ success: true, data: 'ses-1' }),
      },
    },
  };
  ctx.window.localStorage = ctx.localStorage;
  const fn = new Function(...Object.keys(ctx), `${fuente}; return Outbox;`);
  const Outbox = fn(...Object.values(ctx));
  Outbox.load();
  return { Outbox, enviados, store, ctx };
}

const okRes = { success: true, data: 'row-id' };

console.log('\nNo perder escrituras');

await t('lo encolado MIENTRAS se manda otra cosa no se pierde', async () => {
  // El caso del gimnasio: confirmás la serie 2 mientras la 1 todavía viaja.
  const { Outbox, enviados } = montar(async () => { await dormir(40); return okRes; });
  Outbox.enqueue('carga', { diaId: 'd1', semana: 1, datos: { serie: 1 } }, 'k1');
  await dormir(10);                       // el envío de la 1 está en vuelo
  Outbox.enqueue('carga', { diaId: 'd1', semana: 1, datos: { serie: 2 } }, 'k2');
  await dormir(300);
  if (!enviados.includes(2)) {
    throw new Error(`la serie 2 nunca se mandó (enviadas: ${JSON.stringify(enviados)})`);
  }
  if (Outbox.pending() !== 0) throw new Error(`quedaron ${Outbox.pending()} en la cola`);
});

await t('tampoco se pierde de localStorage', async () => {
  const { Outbox, store } = montar(async () => { await dormir(40); return okRes; });
  Outbox.enqueue('carga', { diaId: 'd1', semana: 1, datos: { serie: 1 } }, 'k1');
  await dormir(10);
  Outbox.enqueue('carga', { diaId: 'd1', semana: 1, datos: { serie: 2 } }, 'k2');
  await dormir(15);   // en pleno vuelo: la 2 tiene que estar persistida
  const guardado = JSON.parse(store['mypump_outbox_tok'] || '[]');
  if (!guardado.some(o => o.dedupeKey === 'k2')) {
    throw new Error('la serie 2 no estaba en localStorage durante el vuelo');
  }
});

console.log('\nUn rechazo no es un guardado');

await t('una RPC que devuelve null NO cuenta como guardada', async () => {
  // Token revocado: PostgREST responde 200 y la función devuelve NULL.
  const { Outbox } = montar(async () => ({ success: true, data: null }));
  Outbox.enqueue('carga', { diaId: 'd1', semana: 1, datos: { serie: 1 } }, 'k1');
  await dormir(120);
  if (Outbox.pending() === 0) throw new Error('se borró de la cola como si se hubiera guardado');
});

await t('un 0 tampoco (ingest devuelve la cantidad aceptada)', async () => {
  const { Outbox } = montar(async () => ({ success: true, data: 0 }));
  Outbox.enqueue('carga', { diaId: 'd1', semana: 1, datos: { serie: 1 } }, 'k1');
  await dormir(120);
  if (Outbox.pending() === 0) throw new Error('un 0 se contó como guardado');
});

await t('un id de verdad SÍ cuenta', async () => {
  const { Outbox } = montar(async () => okRes);
  Outbox.enqueue('carga', { diaId: 'd1', semana: 1, datos: { serie: 1 } }, 'k1');
  await dormir(120);
  if (Outbox.pending() !== 0) throw new Error('no se sacó de la cola una escritura exitosa');
});

console.log('\nUn error permanente no se reintenta para siempre');

await t('a los N intentos la abandona en vez de reintentar sin fin', async () => {
  let intentos = 0;
  const { Outbox } = montar(async () => { intentos++; return { success: false }; });
  Outbox.enqueue('carga', { diaId: 'd1', semana: 1, datos: { serie: 1 } }, 'k1');
  // Se fuerzan los drenados en vez de esperar el backoff real (llega a 30 s).
  for (let i = 0; i < 12 && Outbox.pending(); i++) await Outbox.flush();
  if (Outbox.pending() !== 0) {
    throw new Error(`sigue en la cola tras ${intentos} intentos — se reintentaría para siempre`);
  }
  if (intentos > 10) throw new Error(`${intentos} intentos es demasiado`);
});

console.log('\nEsperar de verdad al cerrar el día');

await t('await flush() espera al drenado que ya está en curso', async () => {
  // writeFinish hace `await Outbox.flush()` antes de marcar el día cerrado.
  // Si vuelve al instante, el día se cierra con series sin mandar.
  let terminado = false;
  const { Outbox } = montar(async () => { await dormir(80); terminado = true; return okRes; });
  Outbox.enqueue('carga', { diaId: 'd1', semana: 1, datos: { serie: 1 } }, 'k1');
  await dormir(10);          // hay un flush en vuelo
  await Outbox.flush();      // esto TIENE que esperarlo
  if (!terminado) throw new Error('volvió antes de que el envío terminara');
});

console.log(`\n${ok} pasaron, ${fail} fallaron\n`);
process.exit(fail ? 1 : 0);
