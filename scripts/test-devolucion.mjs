#!/usr/bin/env node
/* test-devolucion.mjs — «Devolución de Mati»: los casos compartidos con las apps
 * (apps/shared/fixtures/devolucion/casos.json, copia en scripts/fixtures/devolucion-casos.json),
 * el HTML (escapado, sin nada de IA ni terceros) y la palanca contra un doble del servidor.
 * USO:  node scripts/test-devolucion.mjs */
import { createRequire } from 'node:module';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
const require = createRequire(import.meta.url);
const D = require('../public/js/devolucion.js');

let ok = 0;
async function caso(n, f) { try { await f(); ok++; } catch (e) { console.error('MAL', n, '\n', e.stack || e); process.exitCode = 1; } }

const casos = JSON.parse(readFileSync(new URL('./fixtures/devolucion-casos.json', import.meta.url), 'utf8'));
for (const c of casos) {
  await caso(c.nombre, () => {
    const e = D.decodificar(c.respuesta);
    if (c.esperado === null) return assert.equal(e, null);
    assert.ok(e);
    const u = c.esperado.ultima;
    if (u) {
      assert.equal(e.ultima.id, u.id);
      assert.equal(D.etiqueta(e.ultima.semanaLunes, c.hoy), u.etiqueta);
      assert.deepEqual(e.ultima.lineas, u.lineas);
      assert.equal(D.esNueva(e.ultima, c.hoy), u.nueva);
    } else assert.equal(e.ultima, null);
    assert.deepEqual(e.anteriores.map(d => d.id), c.esperado.anteriores.map(d => d.id));
    assert.deepEqual(e.anteriores.map(d => D.etiqueta(d.semanaLunes, c.hoy)), c.esperado.anteriores.map(d => d.etiqueta));
    assert.deepEqual(e.anteriores.map(d => d.lineas), c.esperado.anteriores.map(d => d.lineas));
  });
}

await caso('no más de 12', () => {
  const l = Array.from({ length: 20 }, (_, i) => ({ id: 'd' + i, semana_lunes: `2026-${String((i % 12) + 1).padStart(2, '0')}-01`, texto: 'Bien.\nSeguí.\nAsí.' }));
  assert.ok(D.decodificar({ habilitado: true, devoluciones: l }).devoluciones.length <= D.MAXIMO);
});

await caso('el HTML escapa el texto y no habla de IA ni de terceros', () => {
  const e = D.decodificar({ habilitado: true, devoluciones: [
    { id: 'a"><img src=x onerror=alert(1)>', semana_lunes: '2026-11-09', texto: '<script>alert(1)</script>\nBien & firme.\nSeguí.', publicado_en: '2026-11-12T10:00:00Z' },
    { id: 'b', semana_lunes: '2026-11-02', texto: 'Uno.\nDos.\nTres.' }] });
  const h = D.html(e, '2026-11-12');
  assert.ok(!h.includes('<script>') && !h.includes('<img'));
  assert.ok(h.includes('&lt;script&gt;') && h.includes('Bien &amp; firme.'));
  assert.ok(h.includes('Devolución de Mati') && h.includes('Semana del 9 de noviembre') && h.includes('Nueva'));
  assert.ok(h.includes('Semanas anteriores') && h.includes('Semana del 2 de noviembre'));
  assert.ok(!/\bIA\b|inteligencia|autom[aá]tic|tu coach|tu entrenador/i.test(h.replace(/<[^>]+>/g, ' ')));
  assert.equal(D.html(D.decodificar({ habilitado: true, devoluciones: [] })), '');
  assert.equal(D.html(null), '');
});

// localStorage de mentira para la palanca y la copia.
const mem = new Map();
globalThis.localStorage = { getItem: k => (mem.has(k) ? mem.get(k) : null), setItem: (k, v) => mem.set(k, String(v)), removeItem: k => mem.delete(k) };
function doble(ini = {}) {
  const d = { habilitado: true, sinRed: false, sinFuncion: false, tokenCaido: false, llamadas: [], devoluciones: [
    { id: 'd1', semana_lunes: '2026-11-09', texto: 'Uno.\nDos.\nTres.', publicado_en: '2026-11-12T10:00:00Z' }], ...ini };
  d.rpc = async (fn, p) => {
    d.llamadas.push(fn);
    if (d.sinRed) return { ok: false, status: 0, codigo: 'NETWORK', clase: 'red' };
    if (d.sinFuncion) return { ok: false, status: 404, codigo: 'PGRST202', clase: 'permanente' };
    if (d.tokenCaido) return { ok: true, data: null };
    if (!d.habilitado) return { ok: true, data: { habilitado: false } };
    return { ok: true, data: { habilitado: true, devoluciones: d.devoluciones } };
  };
  return d;
}
function armar(d, token = 'tok-dev-1') { D._reiniciar(); let n = 0; D.configurar({ token, rpc: d.rpc, alCambiar: () => n++ }); return () => n; }

await caso('palanca apagada: no llama a nada y no hay estado', async () => {
  mem.clear(); const d = doble(); armar(d);
  await D.aplicarPalanca(false);
  assert.deepEqual(d.llamadas, []); assert.equal(D.estado, null);
});
await caso('prendida: trae, guarda y avisa', async () => {
  mem.clear(); const d = doble(); const cambios = armar(d);
  await D.aplicarPalanca(true);
  assert.deepEqual(d.llamadas, ['mypump_devolucion_get']); assert.equal(D.estado.ultima.id, 'd1'); assert.ok(cambios() >= 1);
  assert.ok(mem.get('mypump_devolucion_tok-dev-1'));
});
await caso('sin red: lo último guardado; palanca desconocida = la última leída', async () => {
  mem.clear(); await (async () => { const d = doble(); armar(d); await D.aplicarPalanca(true); })();
  const d = doble({ sinRed: true }); armar(d);
  await D.aplicarPalanca(null);
  assert.equal(D.estado.ultima.id, 'd1');
});
await caso('apagarla borra la copia', async () => {
  mem.clear(); const d = doble(); armar(d); await D.aplicarPalanca(true);
  await D.aplicarPalanca(false);
  assert.equal(D.estado, null); assert.ok(!mem.has('mypump_devolucion_tok-dev-1'));
});
for (const [n, ini] of [['sin habilitar', { habilitado: false }], ['sin la función', { sinFuncion: true }], ['token caído', { tokenCaido: true }]]) {
  await caso(`${n}: nada y sin copia`, async () => {
    mem.clear(); armar(doble()); await D.aplicarPalanca(true);
    const d = doble(ini); armar(d); await D.aplicarPalanca(true);
    assert.equal(D.estado, null); assert.ok(!mem.has('mypump_devolucion_tok-dev-1'));
  });
}
await caso('la copia es por cuenta', async () => {
  mem.clear(); armar(doble(), 'cuenta-a'); await D.aplicarPalanca(true);
  const d = doble({ sinRed: true }); armar(d, 'cuenta-b'); await D.aplicarPalanca(null);
  assert.equal(D.estado, null);
});

console.log(`test-devolucion: ${ok} ok`);
