#!/usr/bin/env node
/* test-lista-previa.mjs — «Antes de la videollamada»: la regla y los textos contra los MISMOS vectores de las apps
 * (apps/shared/vectores/lista_previa.json, copia exacta en scripts/fixtures/lista_previa.json), el HTML (filas con
 * destino = botón, escapado) y el modelo contra un doble: palanca apagada = cero llamadas, sin red o sin la función =
 * nada, y como mucho un pedido por minuto.
 * USO:  node scripts/test-lista-previa.mjs */
import { createRequire } from 'node:module';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
const require = createRequire(import.meta.url);
const L = require('../public/js/lista-previa.js');
const V = JSON.parse(readFileSync(new URL('./fixtures/lista_previa.json', import.meta.url), 'utf8'));

let ok = 0;
async function caso(n, f) { try { await f(); ok++; } catch (e) { console.error('MAL', n, '\n', e.stack || e); process.exitCode = 1; } }

for (const c of V.casos) await caso(`lista: ${c.nombre}`, () => assert.deepEqual(L.lista(c.respuesta), c.salida));
await caso('los textos, los títulos y los destinos son los de los vectores', () => {
  assert.deepEqual(L.TEXTOS, V.textos); assert.deepEqual(L.TITULOS, V.titulos); assert.deepEqual(L.DESTINOS, V.destinos);
});
await caso('entradas raras no rompen', () => {
  for (const x of [null, undefined, 3, 'x', [], { ok: true, activa: true, items: [{ clave: 'constructor', estado: 'falta' }, { clave: 'toString', estado: 'hecho' }] }]) assert.equal(L.lista(x), null);
});

const DEMO = V.casos[0].salida;
await caso('el HTML: título, resumen, consejo, las filas con destino son botones y las otras no', () => {
  const h = L.html(DEMO);
  for (const t of ['Antes de la videollamada', 'Llevás 1 de 3', 'Ese día buscá un lugar tranquilo y con buena conexión.', 'Mirar los videos de tu guía', 'Te faltan 2 videos', 'Opcional']) assert.ok(h.includes(t), t);
  assert.equal((h.match(/<button /g) || []).length, 3);
  assert.ok(/<button[^>]*data-lp-destino="guia"[^>]*data-test="lista-previa-guia"[^>]*aria-label="Mirar los videos de tu guía, Falta, Te faltan 2 videos"/.test(h));
  assert.ok(/<button[^>]*data-lp-destino="guia"[^>]*data-test="lista-previa-dudas"/.test(h));
  assert.ok(/<button[^>]*data-lp-destino="fotos"[^>]*data-test="lista-previa-fotos"/.test(h));
  assert.ok(/<div class="lp-fila is-hecha" data-test="lista-previa-formulario" role="group" aria-label="Responder las preguntas de Mati, Hecho"/.test(h));
  assert.ok(h.includes('lp-sola') && !h.includes('lp-dentro'));
  assert.ok(L.html(DEMO, { enTarjeta: true }).includes('lp-dentro'));
  assert.ok(!/\bIA\b|tu coach|tu entrenador|\bRIR\b|reserva|entrega/i.test(h.replace(/<[^>]+>/g, ' ')));
});
await caso('todo listo: sin botones en lo hecho, y el resumen', () => {
  const h = L.html(V.casos[1].salida);
  assert.ok(h.includes('Ya tenés todo listo') && h.includes('is-listo'));
  assert.equal((h.match(/<button /g) || []).length, 1);   // solo la duda opcional, que falta
});
await caso('sin nada que mostrar, cadena vacía', () => { assert.equal(L.html(null), ''); assert.equal(L.html({ items: [] }), ''); });
await caso('el HTML escapa lo que pinta', () => {
  const h = L.html({ items: [{ clave: 'x"><b>', titulo: '<script>1</script>', hecho: false, opcional: false, detalle: 'a & b', destino: 'guia"><i>', accesible: 'x "y"' }], resumen: '<u>', todo_listo: false });
  assert.ok(!h.includes('<script>') && !h.includes('<b>') && !h.includes('<i>') && !h.includes('<u>'));
  assert.ok(h.includes('&lt;script&gt;') && h.includes('a &amp; b') && h.includes('x &quot;y&quot;'));
});

// ── El modelo ──
const mem = new Map();
globalThis.localStorage = { getItem: (k) => (mem.has(k) ? mem.get(k) : null), setItem: (k, v) => mem.set(k, String(v)), removeItem: (k) => mem.delete(k) };
function doble(ini = {}) {
  const d = { sinRed: false, sinFuncion: false, respuesta: V.casos[0].respuesta, llamadas: [], ...ini };
  d.rpc = async (fn, p) => {
    d.llamadas.push({ fn, ...p });
    if (d.sinRed) return { ok: false, status: 0, codigo: 'NETWORK', clase: 'red' };
    if (d.sinFuncion) return { ok: false, status: 404, codigo: 'PGRST202', clase: 'permanente' };
    return { ok: true, data: d.respuesta };
  };
  return d;
}
let cambios = 0, reloj = 1000000;
function armar(d) { L._reiniciar(); cambios = 0; reloj = 1000000; L.configurar({ token: 'tok-lp-1', rpc: d.rpc, alCambiar: () => cambios++, ahora: () => reloj }); }

await caso('palanca apagada (o sin la clave y sin nada guardado): cero llamadas y nada', async () => {
  mem.clear(); const d = doble(); armar(d);
  await L.aplicarPalanca(false); await L.refrescar();
  assert.deepEqual(d.llamadas, []); assert.equal(L.salida, null);
  armar(d); await L.aplicarPalanca(null); await L.refrescar();
  assert.deepEqual(d.llamadas, []); assert.equal(L.salida, null);
});
await caso('prendida: pide con el token, guarda la salida y avisa', async () => {
  mem.clear(); const d = doble(); armar(d);
  await L.aplicarPalanca(true);
  assert.deepEqual(d.llamadas, [{ fn: 'mypump_lista_previa', p_token: 'tok-lp-1' }]);
  assert.deepEqual(L.salida, DEMO); assert.equal(cambios, 1);
});
await caso('como mucho un pedido por minuto; pasado el minuto vuelve a pedir', async () => {
  mem.clear(); const d = doble(); armar(d);
  await L.aplicarPalanca(true);
  reloj += 30000; await L.refrescar(); await L.refrescar();
  assert.equal(d.llamadas.length, 1);
  reloj += 31000; d.respuesta = V.casos[1].respuesta; await L.refrescar();
  assert.equal(d.llamadas.length, 2); assert.equal(L.salida.todo_listo, true); assert.equal(cambios, 2);
  L._reiniciar();
});
await caso('la misma respuesta no vuelve a avisar', async () => {
  mem.clear(); const d = doble(); armar(d);
  await L.aplicarPalanca(true); reloj += 61000; await L.refrescar();
  assert.equal(d.llamadas.length, 2); assert.equal(cambios, 1);
});
for (const [n, ini] of [['sin red', { sinRed: true }], ['sin la función (PGRST202)', { sinFuncion: true }], ['inactiva', { respuesta: { ok: true, activa: false, items: [] } }], ['token caído', { respuesta: { ok: false, motivo: 'token' } }], ['respuesta nula', { respuesta: null }]]) {
  await caso(`${n}: nada y sin romper`, async () => {
    mem.clear(); const d = doble(ini); armar(d);
    await L.aplicarPalanca(true);
    assert.equal(L.salida, null); assert.equal(L.html(L.salida), '');
  });
}
await caso('lo que se veía se va si después no hay red', async () => {
  mem.clear(); const d = doble(); armar(d);
  await L.aplicarPalanca(true); assert.ok(L.salida);
  d.sinRed = true; reloj += 61000; await L.refrescar();
  assert.equal(L.salida, null); assert.equal(cambios, 2);
});
await caso('apagar la palanca saca la lista sin llamar', async () => {
  mem.clear(); const d = doble(); armar(d);
  await L.aplicarPalanca(true); d.llamadas.length = 0;
  await L.aplicarPalanca(false);
  assert.equal(L.salida, null); assert.deepEqual(d.llamadas, []);
});
await caso('un rpc que revienta no rompe', async () => {
  mem.clear(); L._reiniciar(); L.configurar({ token: 't', rpc: async () => { throw new Error('x'); }, alCambiar() {} });
  await L.aplicarPalanca(true);
  assert.equal(L.salida, null);
});
L._reiniciar();
console.log(`test-lista-previa: ${ok} ok`);
