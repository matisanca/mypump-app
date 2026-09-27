#!/usr/bin/env node
/* =============================================================
 * test-sesion-cacheada.mjs — la sesión del día que el teléfono recuerda.
 *
 * POR QUÉ EXISTE
 * restoreSesionDelDia confiaba en localStorage sin preguntar: si la semana
 * guardada coincidía con la de la rutina, recuperaba esa sesión y listo. Pero
 * el servidor archiva las sesiones de un bloque viejo (semana - 100) al
 * activar el siguiente (070b/071) y al reiniciar la semana (078). El
 * teléfono que ya había abierto el día seguía colgado de la sesión archivada:
 * día cerrado con las series de julio, y las series nuevas iban a parar a esa
 * sesión — hasta que cambiaba la semana. Pasó con Emmanuel Matoff (11-sep) y,
 * muy probablemente, con Facundo Palero en su semana 5 (26-sep).
 *
 * Ahora el caché se confirma con mypump_get_sesion_dia. Si el servidor no
 * devuelve ESA sesión, se descartan las 4 claves y se sigue con lo que diga
 * el servidor. Sin red (supabase-js no lanza: null con _lastError) se confía
 * en el caché como antes.
 *
 * Se extrae la función de cliente.html y se ejecuta con dobles: es el código
 * REAL, no una reimplementación.
 *
 * USO:  node scripts/test-sesion-cacheada.mjs
 * ============================================================= */

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const raiz = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const html = fs.readFileSync(path.join(raiz, 'public/cliente.html'), 'utf8');

const ini = html.indexOf('let _restoreSeq = 0;');
const fin = html.indexOf('/* ---- LAZY LOAD HISTORICO ---- */', ini);
if (ini < 0 || fin < 0) { console.error('✗ no encontré restoreSesionDelDia en cliente.html'); process.exit(1); }
const fuente = html.slice(ini, fin);

let ok = 0, fail = 0;
const t = async (nombre, fn) => {
  try { await fn(); console.log(`  ✓ ${nombre}`); ok++; }
  catch (e) { console.log(`  ✗ ${nombre}\n      ${e.message}`); fail++; }
};
const dormir = (ms) => new Promise(r => setTimeout(r, ms));
const igual = (real, esperado, que) => {
  if (real !== esperado) throw new Error(`${que}: ${JSON.stringify(real)} (esperaba ${JSON.stringify(esperado)})`);
};

const TOKEN = 'tok';
const K = (dia) => `mypump_sesion_${TOKEN}_${dia}`;
const JULIO = Date.parse('2026-07-20T18:00:00Z');

/* Monta restoreSesionDelDia con dobles. `servidor(dia, semana)` contesta la
   RPC: {sesion} (o {sesion:null}) si respondió, {red:true} si no hubo señal,
   {error:{...}} si el servidor rechazó. Puede ser async para simular demora. */
function montar({ store = {}, servidor, dia = 'd3', semana = 5 }) {
  const consultas = [];
  const cargadas = [];
  const DATA = { dia: { id: dia }, rutina: { semana_actual: semana }, _isDemo: false };
  const mypumpDB = {
    _lastError: null,
    async getSesionDia(token, diaId, sem) {
      consultas.push(`${diaId}|${sem}`);
      const r = await servidor(diaId, sem);
      // Lo mismo que rpc() de supabase-client.js: _lastError queda puesto
      // ANTES de devolver, y un fallo devuelve null.
      if (r.red)   { mypumpDB._lastError = { code: 'NETWORK', status: 0, transitorio: true }; return null; }
      if (r.error) { mypumpDB._lastError = r.error; return null; }
      mypumpDB._lastError = null;
      return r.sesion || null;
    },
  };
  const ctx = {
    RUTINA_ID: 'rut-1',
    TOKEN,
    DATA,
    localStorage: {
      getItem: k => (k in store ? store[k] : null),
      setItem: (k, v) => { store[k] = String(v); },
      removeItem: k => { delete store[k]; },
    },
    window: { mypumpDB },
    console: { warn() {}, log() {}, error() {} },
  };
  const cuerpo = `
    let _sesionId = null, _sesionIniciada = false, _diaFinalizado = false, _sessionStart = null;
    async function loadExerciseStates() { __cargadas.push('estados:' + _sesionId); }
    async function loadRegistrosCarga() { __cargadas.push('series:' + _sesionId); }
    function persistSessionStart() {
      if (_sessionStart && DATA && DATA.dia) localStorage.setItem('mypump_sesion_' + TOKEN + '_' + DATA.dia.id + '_start', String(_sessionStart));
    }
    ${fuente}
    return {
      restoreSesionDelDia,
      estado: () => ({ _sesionId, _sesionIniciada, _diaFinalizado, _sessionStart }),
    };`;
  const fn = new Function(...Object.keys(ctx), '__cargadas', cuerpo);
  const app = fn(...Object.values(ctx), cargadas);
  return { ...app, store, consultas, cargadas, DATA, mypumpDB };
}

/* El teléfono de Matoff: abrió el día 3 de la semana 5 del bloque viejo,
   lo cerró, y le quedó todo eso guardado. */
const cacheViejo = () => ({
  [K('d3')]: 'ses-vieja',
  [`${K('d3')}_semana`]: '5',
  [`${K('d3')}_finalizada`]: '1',
  [`${K('d3')}_start`]: String(JULIO),
});

console.log('\nEl servidor confirma el caché');

await t('misma sesión en el servidor → se usa el caché tal cual', async () => {
  const app = montar({ store: cacheViejo(), servidor: async () => ({ sesion: { id: 'ses-vieja', finalizada_en: null } }) });
  await app.restoreSesionDelDia();
  const e = app.estado();
  igual(e._sesionId, 'ses-vieja', '_sesionId');
  // El cerrado es LOCAL a propósito: reabrir el día solo borra la clave local
  // (finalizada_en queda en la base). Tomarlo del servidor lo volvía a cerrar.
  igual(e._diaFinalizado, true, '_diaFinalizado');
  igual(e._sessionStart, JULIO, '_sessionStart');
  igual(app.store[K('d3')], 'ses-vieja', 'clave de sesión');
  igual(app.cargadas.join(','), 'estados:ses-vieja,series:ses-vieja', 'cargas');
  igual(app.consultas.length, 1, 'consultas al servidor');
});

console.log('\nEl servidor archivó la sesión del caché');

await t('no hay sesión del día → el día arranca limpio y se borran las 4 claves', async () => {
  const app = montar({ store: cacheViejo(), servidor: async () => ({ sesion: null }) });
  await app.restoreSesionDelDia();
  const e = app.estado();
  igual(e._sesionId, null, '_sesionId');
  igual(e._sesionIniciada, false, '_sesionIniciada');
  igual(e._diaFinalizado, false, '_diaFinalizado (el día fantasma aparecía CERRADO)');
  igual(e._sessionStart, null, '_sessionStart');
  for (const suf of ['', '_semana', '_finalizada', '_start']) {
    if (`${K('d3')}${suf}` in app.store) throw new Error(`quedó la clave ${K('d3')}${suf}`);
  }
  igual(app.cargadas.length, 0, 'cargas (traía las series de julio)');
  igual(app.consultas.length, 1, 'consultas al servidor');
});

await t('hay OTRA sesión (la del bloque nuevo) → se usa esa, con su arranque', async () => {
  const iniciada = '2026-09-26T13:00:00Z';
  const app = montar({
    store: cacheViejo(),
    servidor: async () => ({ sesion: { id: 'ses-nueva', iniciada_en: iniciada, finalizada_en: null } }),
  });
  await app.restoreSesionDelDia();
  const e = app.estado();
  igual(e._sesionId, 'ses-nueva', '_sesionId');
  igual(e._diaFinalizado, false, '_diaFinalizado');
  // El _start guardado era el de la sesión archivada: con él la duración del
  // día salía de julio (y el tope la dejaba en null).
  igual(e._sessionStart, Date.parse(iniciada), '_sessionStart');
  igual(app.store[K('d3')], 'ses-nueva', 'clave de sesión');
  igual(app.store[`${K('d3')}_semana`], '5', 'clave de semana');
  igual(app.store[`${K('d3')}_start`], String(Date.parse(iniciada)), 'clave de arranque');
  if (`${K('d3')}_finalizada` in app.store) throw new Error('quedó marcada como finalizada');
  igual(app.cargadas.join(','), 'estados:ses-nueva,series:ses-nueva', 'cargas');
  igual(app.consultas.length, 1, 'consultas al servidor (se reusa la respuesta)');
});

await t('la otra sesión ya está cerrada en el servidor → el día aparece cerrado', async () => {
  const store = cacheViejo();
  delete store[`${K('d3')}_finalizada`];
  const app = montar({
    store,
    servidor: async () => ({ sesion: { id: 'ses-nueva', iniciada_en: '2026-09-25T13:00:00Z', finalizada_en: '2026-09-25T14:10:00Z' } }),
  });
  await app.restoreSesionDelDia();
  igual(app.estado()._diaFinalizado, true, '_diaFinalizado');
  igual(app.store[`${K('d3')}_finalizada`], '1', 'clave de finalizada');
});

console.log('\nSin señal se confía en el caché (como antes)');

await t('corte de red → se usa el caché y no se borra nada', async () => {
  const antes = cacheViejo();
  const app = montar({ store: { ...antes }, servidor: async () => ({ red: true }) });
  await app.restoreSesionDelDia();
  const e = app.estado();
  igual(e._sesionId, 'ses-vieja', '_sesionId');
  igual(e._diaFinalizado, true, '_diaFinalizado');
  igual(e._sessionStart, JULIO, '_sessionStart');
  for (const k of Object.keys(antes)) igual(app.store[k], antes[k], k);
  igual(app.consultas.length, 1, 'consultas al servidor');
});

await t('error del servidor (503) → tampoco se descarta el caché', async () => {
  const app = montar({ store: cacheViejo(), servidor: async () => ({ error: { code: '', status: 503, transitorio: true } }) });
  await app.restoreSesionDelDia();
  igual(app.estado()._sesionId, 'ses-vieja', '_sesionId');
  igual(app.store[K('d3')], 'ses-vieja', 'clave de sesión');
});

console.log('\nLo que ya andaba');

await t('caché de otra semana → se borra y se pregunta una sola vez', async () => {
  const app = montar({ store: cacheViejo(), semana: 6, servidor: async () => ({ sesion: null }) });
  await app.restoreSesionDelDia();
  igual(app.estado()._sesionId, null, '_sesionId');
  if (K('d3') in app.store) throw new Error('quedó la sesión de la semana 5');
  igual(app.consultas.join(','), 'd3|6', 'consultas al servidor');
});

await t('sin caché → pregunta al servidor y guarda lo que venga', async () => {
  const app = montar({ store: {}, servidor: async () => ({ sesion: { id: 'ses-x', iniciada_en: '2026-09-26T12:00:00Z', finalizada_en: null } }) });
  await app.restoreSesionDelDia();
  igual(app.estado()._sesionId, 'ses-x', '_sesionId');
  igual(app.store[K('d3')], 'ses-x', 'clave de sesión');
  igual(app.consultas.length, 1, 'consultas al servidor');
});

console.log('\nCambio de día mientras se pregunta');

await t('la respuesta tardía del día anterior no pisa la sesión del día nuevo', async () => {
  // Ahora hay una consulta ANTES de fijar _sesionId en el camino del caché:
  // si el cliente toca otro día en ese rato, la restauración vieja no puede
  // terminar después y dejar la sesión del día 3 puesta mientras mira el 4
  // (las series del 4 irían a parar a la sesión del 3).
  const store = {
    ...cacheViejo(),
    [K('d4')]: 'ses-d4', [`${K('d4')}_semana`]: '5',
  };
  const app = montar({
    store,
    servidor: async (dia) => {
      if (dia === 'd3') { await dormir(60); return { sesion: { id: 'ses-vieja' } }; }
      return { sesion: { id: 'ses-d4' } };
    },
  });
  const primera = app.restoreSesionDelDia();        // día 3, la respuesta tarda
  await dormir(5);
  app.DATA.dia = { id: 'd4' };                       // cambiarDia()
  await app.restoreSesionDelDia();                   // día 4, responde enseguida
  await primera;
  igual(app.estado()._sesionId, 'ses-d4', '_sesionId');
  if (app.cargadas.some(c => c.endsWith('ses-vieja'))) throw new Error(`cargó la sesión del día 3: ${app.cargadas.join(',')}`);
});

console.log(`\n${ok} pasaron, ${fail} fallaron\n`);
process.exit(fail ? 1 : 0);
