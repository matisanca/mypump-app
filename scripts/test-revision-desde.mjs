#!/usr/bin/env node
/* =============================================================
 * test-revision-desde.mjs — la revisión semanal se pide recién desde la fecha
 * de arranque (mypump_cliente_prefs.revision_desde, OK de Mati del 19/11).
 *
 * POR QUÉ EXISTE
 * Un alumno al que le publicaron el plan el miércoles veía esa misma semana
 * «Te faltan tu check y tus fotos de la semana», aunque su primera revisión es
 * la semana siguiente. El servidor ya frenaba el push de las fotos con
 * mypump_revision_habilitada; la web calculaba el aviso solo con el check y
 * las fotos.
 *
 * 1) Reglas (js/revision-desde.js) con los MISMOS vectores que iOS y Android:
 *    scripts/vectores-app/revision_desde.json, copia exacta de
 *    apps/shared/vectores/revision_desde.json (rama nativa-234).
 * 2) El código REAL de cliente.html (_pendientesSemana, _revisionHabilitada,
 *    _pendientesAviso y _leerRevisionDesde) en una caja con dobles: el borde
 *    del mismo lunes, sin fecha igual que antes, sin red queda la última.
 * 3) getRevisionDesde de supabase-client.js: distingue «null» de «no se pudo».
 * 4) Lo que usa cada aviso, el sw y el ?v= del <script>.
 *
 * USO:  node scripts/test-revision-desde.mjs
 * ============================================================= */
import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const R = require('../public/js/revision-desde.js');
const leer = (rel) => fs.readFileSync(new URL(rel, import.meta.url), 'utf8');
const V = JSON.parse(leer('./vectores-app/revision_desde.json'));
const html = leer('../public/cliente.html');
const sw = leer('../public/sw.js');
const cliente = leer('../public/js/supabase-client.js');

let ok = 0, fail = 0;
async function caso(nombre, fn) {
  try { await fn(); ok++; console.log(`  ✓ ${nombre}`); }
  catch (e) { fail++; console.log(`  ✗ ${nombre}\n      ${e.message}`); }
}

// ── 1) Reglas ──
await caso('la copia de los vectores es exacta', () => {
  const app = new URL('../apps/shared/vectores/revision_desde.json', import.meta.url);
  if (fs.existsSync(app)) assert.equal(fs.readFileSync(app, 'utf8'), leer('./vectores-app/revision_desde.json'));
});
await caso('habilitada: los vectores', () => {
  assert.ok(V.habilitada.length >= 10);
  for (const c of V.habilitada) assert.equal(R.habilitada(c.hoy, c.desde), c.habilitada, c.nombre);
});
await caso('sin arranque: solo 9999-12-31 (la entrega todavía no se hizo)', () => {
  assert.equal(R.sinArranque('9999-12-31'), true);
  for (const d of [null, '', 'basura', '2026-11-23', '2026-13-01']) assert.equal(R.sinArranque(d), false, String(d));
  // En los vectores del aviso, sin aviso es exactamente el caso sin arranque.
  for (const c of V.aviso) assert.equal(c.aviso === null, R.sinArranque(c.desde), c.nombre);
});
await caso('normalizar', () => {
  assert.equal(R.normalizar('2026-11-23'), '2026-11-23');
  assert.equal(R.normalizar(' 2026-11-23T00:00:00 '), '2026-11-23');
  for (const d of [null, undefined, '', 'basura', 20261123, '2026-00-10', '2026-11-32']) assert.equal(R.normalizar(d), null, String(d));
});

// ── 2) El código real de cliente.html, en una caja ──
const funcion = (nombre) => {
  const m = html.match(new RegExp(`\\n((?:async )?function ${nombre}\\([^)]*\\) \\{[\\s\\S]*?\\n\\})\\n`));
  if (!m) throw new Error(`no encontré ${nombre} en cliente.html`);
  return m[1];
};
const constante = (nombre) => {
  const m = html.match(new RegExp(`\\n(const ${nombre} = [^\\n]*;)\\n`));
  if (!m) throw new Error(`no encontré ${nombre} en cliente.html`);
  return m[1];
};
const fuente = [
  constante('_REV_DESDE_KEY'),
  'let _revDesdeMem = null, _revDesdeLeida = false;',
  ...['_lunesISO', '_pendientesSemana', '_revisionDesde', '_revisionHabilitada', '_pendientesAviso', '_leerRevisionDesde'].map(funcion),
].join('\n');

function caja({ hoy = '2026-11-19', desde, respuesta = { ok: true, valor: null }, demo = false, sinStorage = false } = {}) {
  const guardado = new Map();
  if (desde != null) guardado.set('mypump_revision_desde_tok', desde);
  const pintadas = [];
  const localStorage = {
    getItem(k) { if (sinStorage) throw new Error('bloqueado'); return guardado.has(k) ? guardado.get(k) : null; },
    setItem(k, v) { if (sinStorage) throw new Error('bloqueado'); guardado.set(k, String(v)); },
    removeItem(k) { if (sinStorage) throw new Error('bloqueado'); guardado.delete(k); },
  };
  const ctx = {
    TOKEN: 'tok', DATA: { _isDemo: demo }, STATE: { checkin: null, fotos: [], scene: 'train' },
    window: { RevisionDesde: R, mypumpDB: { getRevisionDesde: async () => respuesta } },
    localStorage, hoyLocal: () => ctx._hoy, _hoy: hoy,
    checkGuiadoPrendido: () => false, _cgCheckin: () => null, FOTOS_URL: () => 'https://fotos', _fotoqLeer: () => ({}),
    renderRecordatorio: () => pintadas.push('recordatorio'), renderMydayFotos: () => pintadas.push('fotos'),
    renderMydayCheckin: () => pintadas.push('check'), Date, Number, String, Object, Set, Promise,
  };
  vm.createContext(ctx);
  vm.runInContext(fuente, ctx);
  // JSON: los objetos de la caja son de otro realm (deepStrictEqual compara prototipos).
  const plano = (x) => JSON.parse(JSON.stringify(x));
  return { ctx, guardado, pintadas, p: () => plano(vm.runInContext('_pendientesAviso()', ctx)), real: () => plano(vm.runInContext('_pendientesSemana()', ctx)),
    leer: () => vm.runInContext('_leerRevisionDesde()', ctx) };
}
const NADA = { faltaCheck: false, faltanFotos: false, total: 0 };
const TODO = { faltaCheck: true, faltanFotos: true, total: 2 };

await caso('sin fecha: el aviso es el de siempre', () => {
  assert.deepEqual(caja().p(), TODO);
  assert.deepEqual(caja({ desde: 'basura' }).p(), TODO);
});
await caso('antes del arranque no se pide nada; lo que falta de verdad sigue igual', () => {
  const c = caja({ hoy: '2026-11-19', desde: '2026-11-23' });
  assert.deepEqual(c.p(), NADA);
  assert.deepEqual(c.real(), TODO);   // el check y la sección de fotos siguen sabiendo qué falta
});
await caso('borde: el domingo anterior todavía no, el mismo lunes ya sí', () => {
  assert.deepEqual(caja({ hoy: '2026-11-22', desde: '2026-11-23' }).p(), NADA);
  assert.deepEqual(caja({ hoy: '2026-11-23', desde: '2026-11-23' }).p(), TODO);
  // Con la app abierta de un día para el otro: al llegar el lunes, el próximo render ya lo pide.
  const c = caja({ hoy: '2026-11-22', desde: '2026-11-23' });
  c.ctx._hoy = '2026-11-23';
  assert.deepEqual(c.p(), TODO);
});
await caso('9999-12-31 (la entrega todavía no se hizo): nunca', () => {
  assert.deepEqual(caja({ hoy: '2027-06-01', desde: '9999-12-31' }).p(), NADA);
});
await caso('en la demo, como siempre', () => {
  assert.deepEqual(caja({ desde: '2026-11-23', demo: true }).p(), TODO);
});
await caso('al leer: guarda la fecha y repinta solo si cambia lo que se pide', async () => {
  const c = caja({ respuesta: { ok: true, valor: '2026-11-23' } });
  assert.deepEqual(c.p(), TODO);
  await c.leer();
  assert.equal(c.guardado.get('mypump_revision_desde_tok'), '2026-11-23');
  assert.deepEqual(c.p(), NADA);
  assert.deepEqual(c.pintadas, ['recordatorio']);
  const d = caja({ hoy: '2026-11-30', respuesta: { ok: true, valor: '2026-11-23' } });
  await d.leer();
  assert.deepEqual(d.pintadas, []);   // ya arrancó: nada que repintar
});
await caso('el servidor dice «sin fecha»: se borra la vieja y vuelve el aviso', async () => {
  const c = caja({ desde: '2026-11-23', respuesta: { ok: true, valor: null } });
  assert.deepEqual(c.p(), NADA);
  await c.leer();
  assert.equal(c.guardado.has('mypump_revision_desde_tok'), false);
  assert.deepEqual(c.p(), TODO);
});
await caso('sin respuesta: queda la última que se supo y se vuelve a preguntar', async () => {
  let n = 0;
  const c = caja({ desde: '2026-11-23' });
  c.ctx.window.mypumpDB.getRevisionDesde = async () => { n++; return { ok: false, valor: null }; };
  await c.leer();
  assert.deepEqual(c.p(), NADA);
  await c.leer();
  assert.equal(n, 2);
  // Nunca leída y sin respuesta: como siempre.
  const d = caja({ respuesta: { ok: false, valor: null } });
  await d.leer();
  assert.deepEqual(d.p(), TODO);
});
await caso('con el almacenamiento bloqueado, la fecha vive en memoria', async () => {
  const c = caja({ sinStorage: true, respuesta: { ok: true, valor: '2026-11-23' } });
  assert.deepEqual(c.p(), TODO);
  await c.leer();
  assert.deepEqual(c.p(), NADA);
});
await caso('la escena de Revisión se repinta (fotos y check) cuando cambia', async () => {
  const c = caja({ respuesta: { ok: true, valor: '2026-11-23' } });
  c.ctx.STATE.scene = 'revision';
  await c.leer();
  assert.deepEqual(c.pintadas, ['recordatorio', 'fotos', 'check']);
});

// ── 3) supabase-client: null del servidor ≠ no se pudo ──
await caso('getRevisionDesde distingue null de error', async () => {
  const m = cliente.match(/\n {2}(async getRevisionDesde\(token\) \{[\s\S]*?\n {2}\}),\n/);
  assert.ok(m, 'no encontré getRevisionDesde en supabase-client.js');
  const prueba = async (data, lastError) => {
    const ctx = { window: { mypumpDB: { _lastError: lastError } }, rpc: async () => data };
    vm.createContext(ctx);
    return JSON.parse(JSON.stringify(await vm.runInContext(`({ ${m[1]} }).getRevisionDesde('tok')`, ctx)));
  };
  assert.deepEqual(await prueba('2026-11-23', null), { ok: true, valor: '2026-11-23' });
  assert.deepEqual(await prueba(null, null), { ok: true, valor: null });
  assert.deepEqual(await prueba(null, { code: 'NETWORK' }), { ok: false, valor: null });
  assert.deepEqual(await prueba(null, { code: 'PGRST202' }), { ok: false, valor: null });   // la función no está
  assert.match(m[1], /rpc\('mypump_get_revision_desde', \{ p_token: token \}\)/);
});

// ── 4) Quién usa qué ──
await caso('el badge, el banner, el aviso de fotos y el check usan la versión con arranque', () => {
  assert.match(funcion('renderRecordatorio'), /const p = _pendientesAviso\(\);/);
  assert.doesNotMatch(funcion('renderRecordatorio'), /_pendientesSemana\(\)/);
  assert.match(funcion('renderMydayFotos'), /const conGuia = [^;]*&& _revisionHabilitada\(\);/);
  assert.match(funcion('_cgRenderTarjeta'), /_pendientesAviso\(\)\.faltanFotos/);
  assert.match(funcion('_cgAbrir'), /CheckGuiado\.pasos\(_pendientesAviso\(\)\.faltanFotos\)/);
  // Nadie más pide la revisión con la versión sin arranque.
  const usos = html.match(/(?<!function )_pendientesSemana\(\)/g) || [];
  assert.equal(usos.length, 1, 'solo _pendientesAviso llama a _pendientesSemana');
  assert.match(funcion('loadRevision'), /_leerRevisionDesde\(\)/);
});
await caso('el sw guarda el módulo y el <script> va con la versión del sw', () => {
  assert.match(sw, /'\/js\/revision-desde\.js',/);
  const v = sw.match(/const VERSION\s*=\s*'(v\d+)-/)[1];
  assert.ok(html.includes(`<script src="/js/revision-desde.js?v=${v}"></script>`), `falta revision-desde.js?v=${v}`);
  assert.ok(html.indexOf('/js/revision-desde.js') < html.indexOf('function _revisionHabilitada'));
});

console.log(`\n${ok} ok, ${fail} mal`);
if (fail) process.exit(1);
