#!/usr/bin/env node
/* =============================================================
 * test-controles.mjs — «Tu próximo control de salud» en la web (palanca `controles_app`): las reglas con los MISMOS
 * vectores de iOS y Android (scripts/vectores-app/controles.json, copia exacta de apps/shared/vectores/controles.json)
 * y el modelo de Estudios contra un doble del servidor: las dos palancas, la sección, la caída segura, y que el
 * control alimenta el bloque «Próximo control». No toca la red. Datos inventados.
 * USO:  node scripts/test-controles.mjs
 * ============================================================= */
import fs from 'node:fs';
import { createRequire } from 'node:module';
import assert from 'node:assert/strict';
const require = createRequire(import.meta.url);
const E = require('../public/js/estudios.js');
const C = require('../public/js/controles.js');
const { ModeloEstudios } = require('../public/js/estudios-cola.js');
const V = JSON.parse(fs.readFileSync(new URL('./vectores-app/controles.json', import.meta.url), 'utf8'));

let ok = 0;
async function caso(n, f) { try { await f(); ok++; } catch (e) { console.error('MAL', n, '\n', e.stack || e); process.exitCode = 1; } }

// ── Reglas, con los vectores de la app ──
await caso('la copia de los vectores es exacta', () => {
  const app = new URL('../apps/shared/vectores/controles.json', import.meta.url);
  if (fs.existsSync(app)) assert.equal(fs.readFileSync(app, 'utf8'), fs.readFileSync(new URL('./vectores-app/controles.json', import.meta.url), 'utf8'));
});
await caso('textos', () => {
  assert.deepEqual(Object.keys(C.T).sort(), Object.keys(V.textos).sort());
  for (const [k, v] of Object.entries(V.textos)) assert.equal(C.T[k], v, k);
  assert.equal(C.TITULO_MAX, V.tituloMax);
});
await caso('título', () => { for (const c of V.titulo) assert.equal(C.titulo(c.entra), c.sale, JSON.stringify(c.entra)); });
await caso('cuándo', () => { for (const c of V.cuando) assert.equal(C.cuando(E.dia(c.fecha), E.dia(c.hoy)), c.texto); });
await caso('casos', () => {
  assert.ok(V.casos.length >= 20);
  for (const c of V.casos) {
    const e = C.decodificar(c.respuesta);
    const est = C.proximoParaEstudios(e, c.hayOrdenes !== false);
    assert.deepEqual(est ? { titulo: est.titulo, cuando: est.cuando, nota: est.nota } : null, c.sale.estudios, c.nombre);
    assert.deepEqual(C.tarjetaInicio(e, E.dia(c.hoyTelefono)), c.sale.inicio, c.nombre);
    assert.deepEqual(C.hitos(e), c.sale.hitos, c.nombre);
  }
});
await caso('ningún texto nombra el ciclo, fármacos ni «IA»', () => {
  const todos = [];
  const juntar = (j) => { if (typeof j === 'string') todos.push(j); else if (Array.isArray(j)) j.forEach(juntar); else if (j && typeof j === 'object') Object.values(j).forEach(juntar); };
  juntar(V.textos); for (const c of V.casos) juntar(c.sale);
  for (const s of todos.filter((x) => x !== C.T.tituloPorDefecto)) assert.notEqual(C.titulo([...s].slice(0, 60).join('')), C.T.tituloPorDefecto, s);
});

// ── El modelo de Estudios contra un doble ──
const HOY = '2026-11-10';
const ctl = (f, a, estado) => ({ titulo_alumno: 'Control de salud', fecha_objetivo: f, avisar_desde: a, estado });
function doble(op = {}) {
  const d = { llamadas: [], controles: op.controles ?? { habilitado: true, hoy: HOY, proximo: null, ultimos: [] }, sinFuncion: false, sinRed: false };
  d.rpc = async (fn) => {
    d.llamadas.push(fn);
    if (d.sinRed) return { ok: false, status: 0, codigo: 'NETWORK', clase: 'red' };
    if (fn === 'mypump_estudios_get') return { ok: true, data: { habilitado: true, hoy: HOY, proximo_control: { tipo: 'laboratorio', titulo: 'Análisis de laboratorio', desde: '2026-11-23', hasta: '2026-11-29' }, pendientes: [], ordenes: [], estudios: [], envios: [] } };
    if (fn === 'mypump_controles_get') return d.sinFuncion ? { ok: false, status: 404, codigo: 'PGRST202', clase: 'permanente' } : { ok: true, data: d.controles };
    return { ok: true, data: [] };
  };
  return d;
}
const armar = (d, controles) => new ModeloEstudios({ rpc: d.rpc, token: 'tk-prueba', visionUrl: '', controles });
const conProximo = (p) => ({ habilitado: true, hoy: HOY, proximo: p, ultimos: [ctl('2026-10-01', '2026-09-24', 'revisado')] });

await caso('palanca apagada: no llama ni muestra; el bloque queda como siempre', async () => {
  const d = doble({ controles: conProximo(ctl('2026-11-16', '2026-11-09', 'programado')) });
  const m = armar(d, false);
  await m.refrescar();
  assert.ok(!d.llamadas.includes('mypump_controles_get'));
  assert.equal(m.tarjetaControl, null); assert.deepEqual(m.hitosControl, []);
  assert.equal(E.fechaControl(m.estado.proximoControl.desde, m.estado.proximoControl.hasta), 'Semana del 23/11');
  assert.equal(m.estado.proximoControl.nota, undefined);
});
await caso('sin control', async () => {
  const d = doble(); const m = armar(d, true);
  await m.refrescar();
  assert.ok(d.llamadas.includes('mypump_controles_get'));
  assert.equal(m.tarjetaControl, null); assert.deepEqual(m.hitosControl, []);
  assert.equal(m.estado.proximoControl.titulo, 'Análisis de laboratorio');
});
await caso('control lejano: solo en Estudios', async () => {
  const m = armar(doble({ controles: conProximo(ctl('2026-12-30', '2026-12-23', 'programado')) }), true);
  await m.refrescar();
  assert.equal(m.tarjetaControl, null);
  assert.deepEqual([m.estado.proximoControl.titulo, m.estado.proximoControl.cuando, m.estado.proximoControl.nota], ['Control de salud', 'El miércoles 30/12', C.T.notaProgramado]);
  assert.deepEqual(m.hitosControl.map((h) => h.estado), ['Próximo', 'Mati lo vio']);
});
await caso('control dentro de la ventana: la tarjeta de arriba', async () => {
  const m = armar(doble({ controles: conProximo(ctl('2026-11-16', '2026-11-09', 'programado')) }), true);
  await m.refrescar();
  assert.deepEqual(m.tarjetaControl, { titulo: 'Tu próximo control de salud', cuando: 'El lunes 16/11', nota: C.T.notaProgramado, boton: 'Ver mis estudios' });
});
await caso('órdenes enviadas: se va de arriba', async () => {
  const m = armar(doble({ controles: conProximo(ctl('2026-11-16', '2026-11-09', 'ordenes_enviadas')) }), true);
  await m.refrescar();
  assert.equal(m.tarjetaControl, null);
  // Este doble no trae órdenes en Estudios: la nota no manda a buscar «Tus órdenes».
  assert.equal(m.estado.proximoControl.nota, C.T.notaOrdenesSinLista);
});
await caso('la respuesta vieja de controles no vuelve a pintar (palanca o sección apagadas mientras viaja)', async () => {
  for (const como of ['palanca', 'seccion']) {
    const d = doble({ controles: conProximo(ctl('2026-11-16', '2026-11-09', 'programado')) });
    const m = armar(d, true);
    const rpc = d.rpc;
    m._rpc = async (fn, p) => { if (fn === 'mypump_controles_get') { if (como === 'palanca') m.usarPalancaControles(false); else m.apagar(); } return rpc(fn, p); };
    await m.refrescar();
    assert.ok(d.llamadas.includes('mypump_controles_get'));
    assert.equal(m.controles, null); assert.equal(m.tarjetaControl, null); assert.deepEqual(m.hitosControl, []);
    if (m.estado) assert.equal(m.estado.proximoControl.nota, undefined);
  }
});
await caso('Estudios no espera a los controles', async () => {
  const d = doble({ controles: conProximo(ctl('2026-11-16', '2026-11-09', 'programado')) });
  const m = armar(d, true);
  const rpc = d.rpc; let soltar; const freno = new Promise((r) => { soltar = r; });
  m._rpc = async (fn, p) => { if (fn === 'mypump_controles_get') await freno; return rpc(fn, p); };
  const viaje = m.refrescar();
  await new Promise((r) => setTimeout(r, 10));
  assert.equal(m.estado.proximoControl.titulo, 'Análisis de laboratorio', 'Estudios ya se ve');
  soltar(); await viaje;
  assert.equal(m.estado.proximoControl.cuando, 'El lunes 16/11');
});
await caso('apagar en el momento, y caída segura', async () => {
  const d = doble({ controles: conProximo(ctl('2026-11-16', '2026-11-09', 'programado')) });
  const m = armar(d, true);
  await m.refrescar();
  assert.ok(m.tarjetaControl);
  m.usarPalancaControles(false);
  assert.equal(m.tarjetaControl, null); assert.equal(m.estado.proximoControl.titulo, 'Análisis de laboratorio');
  m.usarPalancaControles(true); await m.refrescar(); assert.ok(m.tarjetaControl);
  d.sinRed = true; await m.refrescar(); assert.ok(m.tarjetaControl, 'un corte deja lo de esta visita');
  const d2 = doble({ controles: conProximo(ctl('2026-11-16', '2026-11-09', 'programado')) }); d2.sinFuncion = true;
  const m2 = armar(d2, true); await m2.refrescar();
  assert.ok(m2.estado); assert.equal(m2.controles, null); assert.equal(m2.tarjetaControl, null);
  const m3 = armar(doble({ controles: [] }), true); await m3.refrescar();
  assert.ok(m3.estado); assert.equal(m3.controles, null);
  m.apagar(); assert.equal(m.tarjetaControl, null); assert.deepEqual(m.hitosControl, []);
});
await caso('la web carga controles.js antes de Estudios y el service worker lo guarda', () => {
  const html = fs.readFileSync(new URL('../public/cliente.html', import.meta.url), 'utf8');
  assert.ok(html.indexOf('/js/controles.js') > html.indexOf('/js/estudios.js') && html.indexOf('/js/controles.js') < html.indexOf('/js/estudios-cola.js'));
  assert.ok(/cfg\.controles_app === true/.test(html));
  assert.ok(fs.readFileSync(new URL('../public/sw.js', import.meta.url), 'utf8').includes("'/js/controles.js'"));
});
await caso('nada del control va a localStorage ni a una URL', () => {
  for (const f of ['controles.js', 'estudios-ui.js', 'estudios-cola.js']) {
    const s = fs.readFileSync(new URL(`../public/js/${f}`, import.meta.url), 'utf8');
    assert.ok(!/localStorage\.setItem\([^)]*control/i.test(s), f);
  }
});

console.log(`test-controles: ${ok} casos OK${process.exitCode ? ' (con fallas)' : ''}`);
