#!/usr/bin/env node
/* test-wins.mjs — «Récords y logros»: la regla y los textos contra los MISMOS vectores de las apps
 * (apps/shared/vectores/wins.json, copia exacta en scripts/fixtures/wins.json), y el modelo contra un doble del
 * servidor: palanca apagada = cero llamadas, permiso dar y revocar, la cola local (reintento, descarte, sin_permiso,
 * PGRST202), nunca encola sin permiso, y el HTML escapado y sin palabras prohibidas.
 * USO:  node scripts/test-wins.mjs */
import { createRequire } from 'node:module';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
const require = createRequire(import.meta.url);
const W = require('../public/js/wins.js');
const V = JSON.parse(readFileSync(new URL('./fixtures/wins.json', import.meta.url), 'utf8'));

let ok = 0, L_rpc;
async function caso(n, f) { try { await f(); ok++; } catch (e) { console.error('MAL', n, '\n', e.stack || e); process.exitCode = 1; } }

// ── Los vectores ──
for (const c of V.records) await caso(`récords: ${c.nombre}`, () => assert.deepEqual(W.records(c.ejercicios), c.salida));
for (const c of V.textos) await caso(`textos con ${c.n}`, () => {
  assert.equal(W.titulo(c.n), c.titulo); assert.equal(W.subtitulo(c.n), c.subtitulo); assert.equal(W.conPermiso(c.n), c.con_permiso);
});
for (const c of V.racha) await caso(`racha de ${c.dias}`, () => assert.equal(W.esHito(c.dias), c.es_hito));
await caso('los textos fijos, el tope, los hitos y la versión son los de los vectores', () => {
  assert.deepEqual(W.FIJOS, V.fijos); assert.equal(W.TOPE, V.tope); assert.deepEqual(W.HITOS, V.hitos_racha); assert.equal(W.PERMISO_VERSION, V.permiso_version);
});
await caso('entradas rotas no rompen', () => {
  assert.deepEqual(W.records(null), []); assert.deepEqual(W.records([null, {}, { clave: 'x', nombre: 'X', anteriores: [{ kg: 'a', reps: 1 }], hoy: [{ kg: 1, reps: 1.5 }] }]), []);
});

// ── El HTML ──
const SIN_PROHIBIDAS = /\bIA\b|inteligencia|tu coach|tu entrenador|\bRIR\b|reserva|entrega/i;
const soloTexto = (h) => h.replace(/<[^>]+>/g, ' ');
await caso('el festejo escapa el nombre del ejercicio', () => {
  const r = W.records([{ clave: 'x', nombre: '<img src=x onerror=alert(1)> & "co"', anteriores: [{ kg: 10, reps: 8 }], hoy: [{ kg: 12, reps: 8 }] }]);
  const h = W.htmlFestejo(r, 'sin_permiso');
  assert.ok(!h.includes('<img') && h.includes('&lt;img src=x onerror=alert(1)&gt; &amp; &quot;co&quot;'));
});
await caso('el festejo: título, subtítulo, fila y los dos botones', () => {
  const r = V.records.find((c) => c.nombre === 'varios ejercicios, en el orden del día').salida;
  const h = W.htmlFestejo(r, 'sin_permiso');
  for (const t of ['3 récords hoy', 'Superaste 3 de tus mejores marcas.', 'Remo con barra', '57,5 kg × 8', '+2,5 kg', 'Antes: 55 kg × 8', 'Contarle a Mati', 'Seguir']) assert.ok(h.includes(t), t);
  assert.ok(!h.includes('Mati se va a enterar'));
  const c = W.htmlFestejo(r, 'con_permiso');
  assert.ok(c.includes('Mati se va a enterar de estos logros.') && !c.includes('Contarle a Mati') && c.includes('Seguir'));
  const d = W.htmlFestejo(r, 'demo_avisado');
  assert.ok(d.includes('En la demo no se envía nada.') && !d.includes('Contarle a Mati'));
  assert.ok(!SIN_PROHIBIDAS.test(soloTexto(h + c + d)));
});
await caso('la hoja de permiso: título, los 3 párrafos y los dos botones', () => {
  const h = W.htmlPermiso();
  for (const t of [V.fijos.permiso_titulo, ...V.fijos.permiso_cuerpo, V.fijos.permiso_si, V.fijos.permiso_no]) assert.ok(h.includes(t), t);
  assert.ok(!SIN_PROHIBIDAS.test(soloTexto(h)));
});

// ── El modelo, contra un doble del servidor ──
const mem = new Map();
globalThis.localStorage = { getItem: (k) => (mem.has(k) ? mem.get(k) : null), setItem: (k, v) => mem.set(k, String(v)), removeItem: (k) => mem.delete(k) };
function doble(ini = {}) {
  const d = { palanca: true, permiso: false, sinRed: false, sinFuncion: false, caido: false, tokenCaido: false, rechazo: null, llamadas: [], filas: [], ...ini };
  d.rpc = async (fn, p) => {
    d.llamadas.push({ fn, ...p });
    if (d.sinRed) return { ok: false, status: 0, codigo: 'NETWORK', clase: 'red' };
    if (d.caido) return { ok: false, status: 503, codigo: '', clase: 'transitorio' };
    if (d.sinFuncion) return { ok: false, status: 404, codigo: 'PGRST202', clase: 'permanente' };
    if (d.rechazo) return { ok: false, status: 400, codigo: d.rechazo, clase: 'permanente' };
    if (d.tokenCaido) return { ok: true, data: { ok: false, motivo: 'token' } };
    if (fn === 'mypump_wins_estado') return { ok: true, data: { ok: true, activa: d.palanca, permiso: d.permiso, ...(d.permiso ? { desde: '2026-11-10T12:00:00Z', version: 1 } : {}) } };
    if (fn === 'mypump_wins_permiso') {
      if (p.p_otorga) { if (!d.palanca) return { ok: true, data: { ok: false, motivo: 'apagada' } }; d.permiso = true; return { ok: true, data: { ok: true, permiso: true } }; }
      d.permiso = false; const n = d.filas.length; d.filas = []; return { ok: true, data: { ok: true, permiso: false, retirados: n } };
    }
    if (fn === 'mypump_wins_registrar') {
      if (!d.palanca) return { ok: true, data: { ok: true, guardado: false, motivo: 'apagada' } };
      if (!d.permiso) return { ok: true, data: { ok: true, guardado: false, motivo: 'sin_permiso' } };
      if (p.p_datos && p.p_datos.kg === 999) return { ok: true, data: { ok: false, motivo: 'datos' } };
      const ya = d.filas.some((f) => f.p_id === p.p_id);
      if (!ya) d.filas.push(p);
      return { ok: true, data: { ok: true, guardado: true, ya } };
    }
    return { ok: false, status: 404, codigo: 'PGRST202', clase: 'permanente' };
  };
  d.de = (fn) => d.llamadas.filter((l) => l.fn === fn);
  return d;
}
let cambios = 0;
function armar(d, token = 'tok-wins-1') { W._reiniciar(); cambios = 0; W.configurar({ token, rpc: d.rpc, alCambiar: () => cambios++ }); }
const REC = V.records[0].salida;                 // remo con barra, +2,5 kg
const REC2 = V.records[1].salida;                // press banca, +1 rep
const DIA = '2026-11-10';
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;

await caso('palanca apagada: cero llamadas, sin festejo, sin ajuste y nunca encola', async () => {
  mem.clear(); const d = doble(); armar(d);
  await W.aplicarPalanca(false);
  assert.equal(W.puedeFestejar(), false); assert.equal(W.ajusteVisible(), false);
  assert.equal(W.encolarRecords(REC, DIA), 0); assert.equal(await W.darPermiso(), false);
  await W.vaciar();
  assert.deepEqual(d.llamadas, []);
});
await caso('sin la clave en la config (undefined → null) y sin nada guardado: apagada', async () => {
  mem.clear(); const d = doble(); armar(d);
  await W.aplicarPalanca(null);
  assert.equal(W.puedeFestejar(), false); assert.deepEqual(d.llamadas, []);
});
await caso('prendida sin permiso: lee el estado, festeja y NO encola', async () => {
  mem.clear(); const d = doble(); armar(d);
  await W.aplicarPalanca(true);
  assert.deepEqual(d.llamadas.map((l) => l.fn), ['mypump_wins_estado']);
  assert.equal(W.puedeFestejar(), true); assert.equal(W.permiso, false); assert.equal(W.ajusteVisible(), true);
  assert.equal(W.encolarRecords(REC, DIA), 0); assert.equal(W.encolarRacha(7, 9000, DIA), false);
  assert.deepEqual(W.cola, []); assert.equal(d.de('mypump_wins_registrar').length, 0);
});
await caso('dar el permiso: manda versión y plataforma web, y después encola y registra', async () => {
  mem.clear(); const d = doble(); armar(d); await W.aplicarPalanca(true);
  assert.equal(await W.darPermiso(), true);
  assert.deepEqual(d.de('mypump_wins_permiso')[0], { fn: 'mypump_wins_permiso', p_token: 'tok-wins-1', p_otorga: true, p_version: 1, p_plataforma: 'web' });
  assert.equal(W.permiso, true);
  assert.equal(W.encolarRecords(REC, DIA), 1);
  await W.vaciar();
  const r = d.de('mypump_wins_registrar');
  assert.equal(r.length, 1);
  assert.ok(UUID.test(r[0].p_id)); assert.equal(r[0].p_tipo, 'record_kg'); assert.equal(r[0].p_clave, 'remo con barra'); assert.equal(r[0].p_dia, DIA);
  assert.deepEqual(r[0].p_datos, { ejercicio: 'Remo con barra', kg: 57.5, reps: 8, antes_kg: 55, antes_reps: 8 });
  assert.deepEqual(W.cola, []);
});
await caso('dar el permiso sin red o con la función apagada: no queda dado', async () => {
  mem.clear(); let d = doble(); armar(d); await W.aplicarPalanca(true);
  d.sinRed = true;
  assert.equal(await W.darPermiso(), false); assert.equal(W.permiso, false);
  d.sinRed = false; d.palanca = false;
  assert.equal(await W.darPermiso(), false); assert.equal(W.permiso, false);
});
await caso('la racha: solo en un hito, con clave pasos y {dias, meta}', async () => {
  mem.clear(); const d = doble({ permiso: true }); armar(d); await W.aplicarPalanca(true);
  assert.equal(W.encolarRacha(6, 9000, DIA), false); assert.equal(W.encolarRacha(7, 9000, DIA), true);
  await W.vaciar();
  const r = d.de('mypump_wins_registrar');
  assert.equal(r.length, 1); assert.equal(r[0].p_tipo, 'racha_pasos'); assert.equal(r[0].p_clave, 'pasos'); assert.deepEqual(r[0].p_datos, { dias: 7, meta: 9000 });
});
await caso('sin red queda en la cola (y en disco) y sale al reintentar, con el mismo id', async () => {
  mem.clear(); const d = doble({ permiso: true }); armar(d); await W.aplicarPalanca(true);
  d.sinRed = true;
  W.encolarRecords(REC, DIA); await W.vaciar();
  assert.equal(W.cola.length, 1); const id = W.cola[0].id;
  // Otra visita: la cola se lee del disco.
  armar(d); assert.equal(W.cola.length, 1);
  await W.aplicarPalanca(null);                      // sin red: vale lo último que se supo
  assert.equal(W.puedeFestejar(), true); assert.equal(W.permiso, true); assert.equal(W.cola.length, 1);
  d.sinRed = false;
  await W.vaciar();
  assert.deepEqual(W.cola, []); assert.equal(d.filas.length, 1); assert.equal(d.filas[0].p_id, id);
});
await caso('el servidor caído (5xx) también deja para después', async () => {
  mem.clear(); const d = doble({ permiso: true }); armar(d); await W.aplicarPalanca(true);
  d.caido = true; W.encolarRecords(REC, DIA); await W.vaciar();
  assert.equal(W.cola.length, 1);
  d.caido = false; await W.vaciar(); assert.deepEqual(W.cola, []);
});
await caso('motivo datos: se descarta y sigue con el resto', async () => {
  mem.clear(); const d = doble({ permiso: true }); armar(d); await W.aplicarPalanca(true);
  d.sinRed = true;
  W.encolar({ tipo: 'record_kg', clave: 'malo', dia: DIA, datos: { ejercicio: 'Malo', kg: 999, reps: 1, antes_kg: 1, antes_reps: 1 } });
  W.encolarRecords(REC, DIA); await W.vaciar();
  d.sinRed = false; await W.vaciar();
  assert.deepEqual(W.cola, []); assert.equal(d.filas.length, 1); assert.equal(d.filas[0].p_clave, 'remo con barra');
});
await caso('motivo sin_permiso: se saca, se recuerda permiso = false y no encola más', async () => {
  mem.clear(); const d = doble({ permiso: true }); armar(d); await W.aplicarPalanca(true);
  d.sinRed = true; W.encolarRecords(REC, DIA); await W.vaciar(); d.sinRed = false;
  d.permiso = false;                                 // lo sacó desde otro teléfono
  await W.vaciar();
  assert.deepEqual(W.cola, []); assert.equal(W.permiso, false); assert.equal(d.filas.length, 0);
  assert.equal(W.encolarRecords(REC2, DIA), 0);
  armar(d); assert.equal(W.permiso, false);          // quedó en disco
});
await caso('PGRST202: se vacía la cola y no se muestra nada', async () => {
  mem.clear(); const d = doble({ permiso: true }); armar(d); await W.aplicarPalanca(true);
  d.sinRed = true; W.encolarRecords(REC, DIA); W.encolarRecords(REC2, DIA); await W.vaciar(); d.sinRed = false;
  assert.equal(W.cola.length, 2);
  d.sinFuncion = true; await W.vaciar();
  assert.deepEqual(W.cola, []); assert.equal(W.puedeFestejar(), false);
});
await caso('sin_permiso vacía TODA la cola (no solo ese logro) con una sola llamada', async () => {
  mem.clear(); const d = doble({ permiso: true }); armar(d); await W.aplicarPalanca(true);
  d.sinRed = true; W.encolarRecords(REC, DIA); W.encolarRecords(REC2, DIA); await W.vaciar(); d.sinRed = false;
  assert.equal(W.cola.length, 2);
  d.permiso = false; d.llamadas.length = 0; await W.vaciar();
  assert.deepEqual(W.cola, []); assert.equal(W.permiso, false); assert.equal(d.de('mypump_wins_registrar').length, 1);
});
await caso('PGRST202 al registrar además baja el permiso; y al leer el estado también', async () => {
  mem.clear(); const d = doble({ permiso: true }); armar(d); await W.aplicarPalanca(true);
  d.sinRed = true; W.encolarRecords(REC, DIA); await W.vaciar(); d.sinRed = false;
  d.sinFuncion = true; await W.vaciar();
  assert.equal(W.permiso, false); assert.equal(W.ajusteVisible(), false);
  mem.clear(); const e = doble({ permiso: true }); armar(e); await W.aplicarPalanca(true); assert.equal(W.permiso, true);
  e.sinFuncion = true; await W.refrescar();
  assert.equal(W.permiso, false); assert.deepEqual(W.cola, []);
});
await caso('motivo datos: se saca al primer intento; token: al tercero; sin red no cuenta intentos', async () => {
  mem.clear(); const d = doble({ permiso: true }); armar(d); await W.aplicarPalanca(true);
  W.encolar({ tipo: 'record_kg', clave: 'x', dia: DIA, datos: { ejercicio: 'X', kg: 999, reps: 8, antes_kg: 900, antes_reps: 8 } }); await W.vaciar();
  assert.deepEqual(W.cola, []); assert.equal(d.de('mypump_wins_registrar').length, 1);
  d.sinRed = true; W.encolarRecords(REC, DIA); for (let i = 0; i < 5; i++) await W.vaciar();
  assert.equal(W.cola.length, 1); assert.equal(W.cola[0].intentos, 0);
  d.sinRed = false; d.tokenCaido = true;
  await W.vaciar(); assert.equal(W.cola.length, 1); await W.vaciar(); assert.equal(W.cola.length, 1); await W.vaciar();
  assert.deepEqual(W.cola, []);
});
await caso('lo ya enviado en esta sesión no se encola otra vez; una marca mejor sí, con id nuevo', async () => {
  mem.clear(); const d = doble({ permiso: true }); armar(d); await W.aplicarPalanca(true);
  W.encolarRecords(REC, DIA); await W.vaciar(); assert.equal(d.filas.length, 1);
  assert.equal(W.encolarRecords(REC, DIA), 1); await W.vaciar();          // reabrir el festejo: dice que sí, pero no manda otro
  assert.equal(d.filas.length, 1); assert.equal(d.de('mypump_wins_registrar').length, 1);
  W.encolarRecords([{ ...REC[0], kg: 70 }], DIA); await W.vaciar();
  assert.equal(d.filas.length, 2); assert.notEqual(d.filas[0].p_id, d.filas[1].p_id);
});
await caso('dos pestañas: si la otra revoca mientras esta manda, no se reescribe el permiso ni queda cola', async () => {
  mem.clear(); const d = doble({ permiso: true }); const rpc = d.rpc; let despues = null, n = 0;
  d.rpc = async (fn, p) => { const r = await rpc(fn, p); if (fn === 'mypump_wins_registrar') { n++; if (despues) { despues(); despues = null; } } return r; };
  armar(d); await W.aplicarPalanca(true);
  d.sinRed = true; W.encolarRecords(REC, DIA); W.encolarRecords(REC2, DIA); await W.vaciar(); d.sinRed = false;
  const k = [...mem.keys()].find((x) => x.startsWith('mypump-wins-'));
  n = 0; despues = () => mem.set(k, JSON.stringify({ activa: true, permiso: false, cola: [] }));
  await W.vaciar();
  assert.equal(W.permiso, false); assert.deepEqual(W.cola, []); assert.equal(n, 1);
  assert.equal(JSON.parse(mem.get(k)).permiso, false); assert.deepEqual(JSON.parse(mem.get(k)).cola, []);
  assert.equal(W.encolarRecords(REC, DIA), 0);
});
await caso('dos pestañas: lo que la otra encoló mientras esta mandaba no se pierde', async () => {
  mem.clear(); const d = doble({ permiso: true }); armar(d); await W.aplicarPalanca(true);
  const k = [...mem.keys()].find((x) => x.startsWith('mypump-wins-'));
  const otro = { id: '11111111-1111-4111-8111-111111111111', tipo: 'racha_pasos', clave: 'pasos', dia: DIA, datos: { dias: 7, meta: 9000 }, intentos: 0 };
  const rpc = d.rpc; let hecho = false;
  d.rpc = async (fn, p) => { if (fn === 'mypump_wins_registrar' && !hecho) { hecho = true; const j = JSON.parse(mem.get(k)); j.cola.push(otro); mem.set(k, JSON.stringify(j)); } return rpc(fn, p); };
  W.configurar({ token: 'tok-wins-1', rpc: d.rpc, alCambiar() {} }); await W.aplicarPalanca(true);
  W.encolarRecords(REC, DIA); await W.vaciar(); await W.vaciar();
  assert.deepEqual(d.filas.map((f) => f.p_tipo).sort(), ['racha_pasos', 'record_kg']); assert.deepEqual(W.cola, []);
});
await caso('la palanca se recuerda: el modelo arranca con lo último que se supo, sin llamar', async () => {
  mem.clear(); const d = doble({ permiso: true }); armar(d); await W.aplicarPalanca(true);
  d.llamadas.length = 0; d.sinRed = true; armar(d);
  assert.equal(W.puedeFestejar(), true); assert.equal(W.permiso, true); assert.deepEqual(d.llamadas, []);
  assert.equal(W.encolarRecords(REC, DIA), 1); await W.vaciar(); assert.equal(W.cola.length, 1);
  await W.aplicarPalanca(false); armar(d); assert.equal(W.puedeFestejar(), false);
});
await caso('la función no existe al abrir: nada, sin romper', async () => {
  mem.clear(); const d = doble({ sinFuncion: true }); armar(d);
  await W.aplicarPalanca(true);
  assert.equal(W.puedeFestejar(), false); assert.equal(W.ajusteVisible(), false); assert.equal(W.encolarRecords(REC, DIA), 0);
});
await caso('sin red al abrir y sin nada guardado: nada', async () => {
  mem.clear(); const d = doble({ sinRed: true }); armar(d);
  await W.aplicarPalanca(true);
  assert.equal(W.puedeFestejar(), false); assert.equal(W.ajusteVisible(), false);
});
await caso('un rechazo permanente que no es de datos: tres intentos y se descarta', async () => {
  mem.clear(); const d = doble({ permiso: true }); armar(d); await W.aplicarPalanca(true);
  d.rechazo = '22P02'; W.encolarRecords(REC, DIA); await W.vaciar();
  assert.equal(W.cola.length, 1);
  await W.vaciar(); assert.equal(W.cola.length, 1);
  await W.vaciar(); assert.deepEqual(W.cola, []);
});
await caso('token caído al registrar: queda para después', async () => {
  mem.clear(); const d = doble({ permiso: true }); armar(d); await W.aplicarPalanca(true);
  d.tokenCaido = true; W.encolarRecords(REC, DIA); await W.vaciar();
  assert.equal(W.cola.length, 1);
});
await caso('revocar: llama con p_otorga false, vacía la cola y deja de encolar', async () => {
  mem.clear(); const d = doble({ permiso: true }); armar(d); await W.aplicarPalanca(true);
  d.sinRed = true; W.encolarRecords(REC, DIA); await W.vaciar(); d.sinRed = false;
  assert.equal(await W.revocar(), true);
  assert.deepEqual(d.de('mypump_wins_permiso').pop(), { fn: 'mypump_wins_permiso', p_token: 'tok-wins-1', p_otorga: false });
  assert.deepEqual(W.cola, []); assert.equal(W.permiso, false); assert.equal(W.encolarRecords(REC, DIA), 0);
  assert.equal(d.filas.length, 0);
});
await caso('revocar sin red: sigue dado', async () => {
  mem.clear(); const d = doble({ permiso: true }); armar(d); await W.aplicarPalanca(true);
  d.sinRed = true;
  assert.equal(await W.revocar(), false); assert.equal(W.permiso, true);
});
await caso('palanca apagada con el permiso dado: el ajuste se ve y se puede apagar, sin otra llamada', async () => {
  mem.clear(); const d = doble({ permiso: true }); armar(d); await W.aplicarPalanca(true);
  d.llamadas.length = 0; armar(d);
  await W.aplicarPalanca(false);
  assert.deepEqual(d.llamadas, []); assert.equal(W.puedeFestejar(), false); assert.equal(W.ajusteVisible(), true);
  assert.equal(W.encolarRecords(REC, DIA), 0);
  assert.equal(await W.revocar(), true); assert.equal(W.ajusteVisible(), false);
  assert.deepEqual(d.llamadas.map((l) => l.fn), ['mypump_wins_permiso']);
});
await caso('el servidor dice activa false: no festeja; con permiso, el ajuste sigue', async () => {
  mem.clear(); const d = doble({ palanca: false, permiso: true }); armar(d);
  await W.aplicarPalanca(true);
  assert.equal(W.puedeFestejar(), false); assert.equal(W.ajusteVisible(), true);
});
await caso('el mismo ejercicio el mismo día: el mismo logro conserva el id; una marca nueva lo reemplaza con id nuevo', async () => {
  mem.clear(); const d = doble({ permiso: true }); armar(d); await W.aplicarPalanca(true);
  d.sinRed = true;
  W.encolarRecords(REC, DIA); const id = W.cola[0].id;
  W.encolarRecords(REC, DIA);
  assert.equal(W.cola.length, 1); assert.equal(W.cola[0].id, id);
  W.encolarRecords([{ ...REC[0], kg: 60 }], DIA);
  assert.equal(W.cola.length, 1); assert.notEqual(W.cola[0].id, id); assert.equal(W.cola[0].datos.kg, 60);
});
await caso('un error del servidor al leer el estado (que no sea «no existe») no pierde la cola', async () => {
  mem.clear(); const d = doble({ permiso: true }); armar(d); await W.aplicarPalanca(true);
  d.sinRed = true; W.encolarRecords(REC, DIA); await new Promise((r) => setTimeout(r, 5));
  const rpc = d.rpc; L_rpc = async (fn, p) => (fn === 'mypump_wins_estado' ? { ok: false, status: 403, codigo: '42501', clase: 'permanente' } : rpc(fn, p));
  W.configurar({ token: 'tok-wins-1', rpc: L_rpc, alCambiar() {} }); await W.aplicarPalanca(true);
  assert.equal(W.cola.length, 1);
});
await caso('tope de 50: lo más viejo se descarta', async () => {
  mem.clear(); const d = doble({ permiso: true }); armar(d); await W.aplicarPalanca(true);
  d.sinRed = true;
  for (let i = 0; i < 60; i++) W.encolar({ tipo: 'record_kg', clave: `ej ${i}`, dia: DIA, datos: { ejercicio: `Ej ${i}`, kg: 10, reps: 8, antes_kg: 8, antes_reps: 8 } });
  await W.vaciar();
  assert.equal(W.cola.length, 50); assert.equal(W.cola[0].clave, 'ej 10'); assert.equal(W.cola[49].clave, 'ej 59');
});
await caso('la cola y el permiso son por cuenta', async () => {
  mem.clear(); const d = doble({ permiso: true }); armar(d, 'cuenta-a'); await W.aplicarPalanca(true);
  d.sinRed = true; W.encolarRecords(REC, DIA); await W.vaciar();
  armar(d, 'cuenta-b');
  assert.deepEqual(W.cola, []); assert.equal(W.permiso, null);
});
await caso('sin almacenamiento no rompe', async () => {
  const real = globalThis.localStorage;
  globalThis.localStorage = { getItem() { throw new Error('x'); }, setItem() { throw new Error('x'); }, removeItem() { throw new Error('x'); } };
  try {
    const d = doble({ permiso: true }); armar(d); await W.aplicarPalanca(true);
    assert.equal(W.puedeFestejar(), true); assert.equal(W.encolarRecords(REC, DIA), 1); await W.vaciar(); assert.equal(d.filas.length, 1);
  } finally { globalThis.localStorage = real; }
});

console.log(`test-wins: ${ok} ok`);
