#!/usr/bin/env node
/* test-demo-historial.mjs — la demo sin cuenta con historia: que public/demo/historial.json esté, sea JSON válido y
 * tenga la forma esperada (es copia idéntica de apps/shared/demo/historial.json; si las apps están al lado, se compara
 * byte a byte), que las fechas salgan relativas a hoy, que Progreso tenga récords, y que el chat, la devolución, las
 * metas y la lista previa salgan con los módulos de la web. Y que el service worker lo guarde.
 * USO:  node scripts/test-demo-historial.mjs */
import { createRequire } from 'node:module';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
const require = createRequire(import.meta.url);
const H = require('../public/js/demo-historial.js');
const W = require('../public/js/wins.js');
const L = require('../public/js/lista-previa.js');
const D = require('../public/js/devolucion.js');
const M = require('../public/js/metas.js');
const RE = require('../public/js/reglas-entreno.js');

let ok = 0;
async function caso(n, f) { try { await f(); ok++; } catch (e) { console.error('MAL', n, '\n', e.stack || e); process.exitCode = 1; } }

const ruta = new URL('../public/demo/historial.json', import.meta.url);
if (!existsSync(ruta)) { console.error('MAL falta public/demo/historial.json (copiarlo de apps/shared/demo/historial.json)'); process.exit(1); }
const crudo = readFileSync(ruta);
let J;
try { J = JSON.parse(crudo.toString('utf8')); } catch (e) { console.error('MAL public/demo/historial.json no es JSON válido:', e.message); process.exit(1); }

await caso('el archivo tiene la forma esperada', () => assert.deepEqual(H.problemas(J), []));
await caso('un archivo roto se detecta y no arma nada', () => {
  for (const x of [null, [], {}, { ...J, version: 2 }, { ...J, entreno: [] }, { ...J, chat: [{ dia: 1, hora: '10:00', autor: 'coach', texto: 'x' }] }, { ...J, peso: 'x' }, { ...J, lista_previa: null }]) {
    assert.ok(H.problemas(x).length > 0); assert.equal(H.armar(x, '2026-11-10'), null);
  }
});
await caso('si el repo de las apps está al lado, es la misma copia byte a byte', () => {
  for (const base of ['../../mn-cola-a', '..']) {
    const origen = new URL(`${base}/apps/shared/demo/historial.json`, import.meta.url);
    if (existsSync(origen)) assert.ok(readFileSync(origen).equals(crudo), `distinto de ${fileURLToPath(origen)}`);
  }
});
await caso('sin datos reales ni palabras prohibidas', () => {
  const t = crudo.toString('utf8');
  assert.ok(!/\bIA\b|tu coach|tu entrenador|\bRIR\b|reserva|entrega|@|https?:|\+?\d{10,}/i.test(t.replace(/"autor": "coach"/g, '')));
});

const HOY = '2026-11-10';   // un martes
const a = H.armar(J, HOY);
const fechaDe = (iso) => { const d = new Date(iso); return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`; };

await caso('las fechas son relativas a hoy', () => {
  assert.equal(H.fecha(HOY, 0), '2026-11-10'); assert.equal(H.fecha(HOY, -1), '2026-11-09'); assert.equal(H.fecha(HOY, -10), '2026-10-31'); assert.equal(H.fecha('2026-01-01', -1), '2025-12-31');
  const otro = H.armar(J, '2027-03-01');
  assert.equal(otro.salud.find((r) => r.tipo === 'pasos' && r.valor === 6240).fecha, '2027-03-01');
  assert.equal(a.salud.find((r) => r.tipo === 'pasos' && r.valor === 6240).fecha, HOY);
  const sinHoy = H.armar(J);
  assert.ok(/^\d{4}-\d{2}-\d{2}$/.test(sinHoy.hoy));
});
await caso('el historial: una fila por serie, por clave, de la más nueva a la más vieja, a la hora + 3 min por serie', () => {
  assert.equal(Object.keys(a.historico).length, J.entreno.length);
  const remo = a.historico['remo con barra'];
  assert.equal(remo.length, J.entreno[0].sesiones.reduce((n, s) => n + s.series.length, 0));
  for (let i = 1; i < remo.length; i++) assert.ok(remo[i - 1].registrado_en >= remo[i].registrado_en);
  const s0 = J.entreno[0].sesiones[0];
  const dia = remo.filter((r) => fechaDe(r.registrado_en) === H.fecha(HOY, s0.dia)).sort((x, y) => x.serie_numero - y.serie_numero);
  assert.deepEqual(dia.map((r) => [r.serie_numero, r.peso_kg, r.reps_realizadas]), s0.series.map((x, i) => [i + 1, x.kg, x.reps]));
  const t0 = new Date(dia[0].registrado_en), t1 = new Date(dia[1].registrado_en);
  assert.equal(`${String(t0.getHours()).padStart(2, '0')}:${String(t0.getMinutes()).padStart(2, '0')}`, s0.hora);
  assert.equal(t1 - t0, 3 * 60000);
  assert.ok(Object.values(a.historico).flat().every((r) => fechaDe(r.registrado_en) < HOY), 'hoy no hay sesión');
});
await caso('la clave la pone la web (se le pasa su función)', () => {
  const b = H.armar(J, HOY, (n) => 'k:' + n);
  assert.ok(b.historico['k:Remo con barra'] && b.historico['k:Prensa 45°']);
});
await caso('Progreso: la historia alcanza y cargar más kg hoy da récord y festejo', () => {
  const remo = a.historico['remo con barra'];
  assert.ok(RE.historiaSuficiente(remo.map((r) => fechaDe(r.registrado_en)), HOY));
  const anteriores = remo.map((r) => ({ kg: r.peso_kg, reps: r.reps_realizadas }));
  const tope = Math.max(...anteriores.map((m) => m.kg));
  const r = W.records([{ clave: 'remo con barra', nombre: 'Remo con barra', anteriores, hoy: [{ kg: tope + 2.5, reps: 8 }] }]);
  assert.equal(r.length, 1); assert.equal(r[0].tipo, 'record_kg'); assert.equal(r[0].chip, '+2,5 kg');
  assert.equal(W.records([{ clave: 'remo con barra', nombre: 'Remo con barra', anteriores, hoy: [{ kg: tope - 5, reps: 8 }] }]).length, 0);
  // Y la tarjeta de Progreso marca récord: la última sesión de algún ejercicio superó a todas las anteriores.
  const conRecord = Object.values(a.historico).filter((filas) => {
    const porDia = {};
    for (const f of filas) { const d = fechaDe(f.registrado_en); porDia[d] = Math.max(porDia[d] || 0, f.peso_kg); }
    const v = Object.keys(porDia).sort().map((d) => porDia[d]);
    return v.length >= 2 && v[v.length - 1] > Math.max(...v.slice(0, -1));
  });
  assert.ok(conRecord.length >= 1);
});
await caso('peso y pasos en la forma de Salud', () => {
  const peso = a.salud.filter((r) => r.tipo === 'peso_kg'), pasos = a.salud.filter((r) => r.tipo === 'pasos');
  assert.equal(peso.length, J.peso.length); assert.equal(pasos.length, J.pasos.length);
  assert.ok(peso.every((r) => r.fuente === 'manual' && /^\d{4}-\d{2}-\d{2}$/.test(r.fecha) && r.fecha <= HOY));
});
await caso('metas: el Pump del día (meta 9.000, hoy 6.240, con racha) y el ritmo de peso', () => {
  const m = M.metasDe(a.metas);
  assert.equal(m.metaPasos, 9000); assert.equal(m.ritmo, -0.4);
  const pasos = {}; for (const r of a.salud) if (r.tipo === 'pasos') pasos[r.fecha] = r.valor;
  const v = M.vista(pasos, m.metaPasos, HOY);
  assert.equal(v.pasosHoy, 6240); assert.equal(v.cumplido, false); assert.ok(v.racha >= 2, `racha ${v.racha}`);
  assert.equal(M.T.estado(v), 'Te faltan 2.760 pasos');
  const serie = a.salud.filter((r) => r.tipo === 'peso_kg').map((r) => ({ fecha: r.fecha, kg: r.valor })).sort((x, y) => (x.fecha < y.fecha ? -1 : 1));
  const r = M.ritmo(m.ritmo, serie, HOY);
  assert.ok(r.meta.startsWith('Buscamos bajar'));
});
await caso('el chat: en orden, Mati y el alumno, todo leído', () => {
  assert.equal(a.chat.length, J.chat.length);
  for (let i = 1; i < a.chat.length; i++) assert.ok(a.chat[i - 1].created_at <= a.chat[i].created_at);
  assert.ok(a.chat.some((m) => m.autor === 'coach') && a.chat.some((m) => m.autor === 'cliente'));
  assert.ok(a.chat.every((m) => m.leido_por_cliente === true && typeof m.contenido === 'string' && m.id.startsWith('demo-chat-')));
  assert.equal(fechaDe(a.chat[a.chat.length - 1].created_at), H.fecha(HOY, -1));
});
await caso('la Devolución de Mati: semanas_atras 1 = el lunes de la semana pasada', () => {
  const e = D.decodificar(a.devoluciones);
  assert.equal(e.ultima.semanaLunes, '2026-11-02'); assert.deepEqual(e.anteriores.map((d) => d.semanaLunes), ['2026-10-26', '2026-10-19']);
  assert.equal(e.ultima.lineas.length, 3);
  const h = D.html(e, HOY);
  assert.ok(h.includes('Devolución de Mati') && h.includes('Semana del 2 de noviembre') && h.includes('Semanas anteriores'));
  // Un lunes y un domingo: la semana pasada sigue siendo la anterior a la del lunes de esta.
  assert.equal(D.decodificar(H.armar(J, '2026-11-09').devoluciones).ultima.semanaLunes, '2026-11-02');
  assert.equal(D.decodificar(H.armar(J, '2026-11-15').devoluciones).ultima.semanaLunes, '2026-11-02');
});
await caso('la lista previa de la demo es la del vector', () => {
  const V = JSON.parse(readFileSync(new URL('./fixtures/lista_previa.json', import.meta.url), 'utf8'));
  assert.deepEqual(L.lista(a.listaPrevia), V.casos[0].salida);
});
await caso('el service worker guarda el archivo y los módulos nuevos', () => {
  const sw = readFileSync(new URL('../public/sw.js', import.meta.url), 'utf8');
  for (const u of ['/demo/historial.json', '/js/demo-historial.js', '/js/wins.js', '/js/lista-previa.js', '/css/wins.css', '/css/lista-previa.css']) assert.ok(sw.includes(`'${u}'`), u);
  const html = readFileSync(new URL('../public/cliente.html', import.meta.url), 'utf8');
  for (const u of ['/js/demo-historial.js', '/js/wins.js', '/js/lista-previa.js', '/css/wins.css', '/css/lista-previa.css']) assert.ok(html.includes(u), u);
});

console.log(`test-demo-historial: ${ok} ok`);
