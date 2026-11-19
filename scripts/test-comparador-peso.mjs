#!/usr/bin/env node
/* =============================================================
 * test-comparador-peso.mjs — el peso del comparador de fotos en la web (2.3.3).
 *
 * El pie «N semanas · ±X kg» de «Tu cambio» y del comparador clásico («Antes y ahora») salen de TuCambio.resumen.
 * Antes tomaba «el primer peso desde el lunes de la semana de la foto», sin tope, sobre los 60 días de Salud: con una
 * primera foto más vieja usaba un peso de meses después. Ahora cada foto toma el peso de su semana (o el más cercano en
 * ±7 días), hay una serie de peso aparte desde la primera foto, y una guarda de unidades esconde los cambios imposibles.
 *
 *  1. Las reglas (TuCambio, extraído de public/cliente.html por texto, como test-tucambio.mjs) con casos reales.
 *  2. La serie aparte (_pcAsegurar / _pesoSerieComparador) con un doble de mypumpDB.getPesoSalud.
 *  3. Los dos caminos usan la misma cuenta.
 * USO:  node scripts/test-comparador-peso.mjs
 * ============================================================= */
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';

const raiz = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const html = fs.readFileSync(path.join(raiz, 'public/cliente.html'), 'utf8');
const tramo = (desde, hasta) => {
  const a = html.indexOf(desde), b = html.indexOf(hasta, a);
  if (a < 0 || b < 0) { console.error(`✗ no encontré «${desde}» en cliente.html`); process.exit(1); }
  return html.slice(a, b);
};
const TC = new Function(`${tramo('/* ═══ TU CAMBIO · REGLAS (inicio) ═══', '/* ═══ TU CAMBIO · REGLAS (fin) ═══ */')}\nreturn TuCambio;`)();

let ok = 0, mal = 0;
async function caso(nombre, fn) { try { await fn(); ok++; } catch (e) { mal++; console.log(`  ✗ ${nombre}\n      ${String(e.message).split('\n').slice(0, 8).join('\n      ')}`); } }
const serie = (pares) => pares.map(([fecha, kg]) => ({ fecha, kg }));
// La regla vieja, tal cual estaba en cliente.html hasta 2.3.2: para comparar «igual que antes».
function resumenViejo(primera, ultima, peso) {
  const dia = (f) => Date.UTC(+f.slice(0, 4), +f.slice(5, 7) - 1, +f.slice(8, 10)) / 864e5;
  const pesoEn = (sem) => { const c = peso.filter(p => p.fecha >= sem).sort((a, b) => a.fecha < b.fecha ? -1 : 1)[0]; return c ? c.kg : null; };
  const semDif = Math.round((dia(ultima) - dia(primera)) / 7);
  let r = `${semDif} semana${semDif === 1 ? '' : 's'}`;
  const p0 = pesoEn(primera), p1 = pesoEn(ultima);
  if (p0 != null && p1 != null) { const d = p1 - p0; r += ` · ${d > 0 ? '+' : ''}${d.toFixed(1).replace('.', ',')} kg`; }
  return r;
}
const fotosDe = (...semanas) => semanas.flatMap(s => ['frente', 'perfil', 'espalda'].map(p => [s, p]));
const pieTuCambio = (fotos, peso, semanaActual = '2026-11-16') => TC.vista({ fotos, inicio: {}, semanaActual, pose: 'frente', peso }).pie;

// ── 1. Casos reales (prueba.txt y REVISION.md de nativa-evidencia/v233/salud_peso, 19/11) ──
// Emmanuel (mt964255efo): fotos del 31/08 al 16/11. Pesos: 73,0 el 02/09 … 67,7 el 29/10 … 68,4 el 16/11.
const EMM = serie([['2026-09-02', 73.0], ['2026-09-09', 72.4], ['2026-09-14', 71.9], ['2026-10-29', 67.7], ['2026-11-05', 68.0], ['2026-11-16', 68.4]]);
const EMM_60 = EMM.filter(p => p.fecha >= '2026-09-21');   // lo que trae Salud (60 días desde el 19/11)
await caso('Emmanuel: −4,6 kg con la serie desde la primera foto', () => {
  assert.equal(TC.resumen('2026-08-31', '2026-11-16', EMM), '11 semanas · -4,6 kg');
  assert.equal(pieTuCambio(fotosDe('2026-08-31', '2026-10-26', '2026-11-16'), EMM), '11 semanas · -4,6 kg');
});
await caso('Emmanuel: el bug de antes (+0,7) y, sin la serie aparte, ya no inventa: solo las semanas', () => {
  assert.equal(resumenViejo('2026-08-31', '2026-11-16', EMM_60), '11 semanas · +0,7 kg');
  assert.equal(TC.resumen('2026-08-31', '2026-11-16', EMM_60), '11 semanas');
});
// Sebastián (mn8awmggfh3l): fotos del 20/07 al 16/11. 79,3 el 22/07, 79,0 el 22/09, 77,8 el 16/11.
const SEB = serie([['2026-07-22', 79.3], ['2026-08-12', 79.6], ['2026-09-15', 79.1], ['2026-09-22', 79.0], ['2026-11-16', 77.8]]);
await caso('Sebastián: −1,5 kg (antes −1,2)', () => {
  assert.equal(resumenViejo('2026-07-20', '2026-11-16', SEB.filter(p => p.fecha >= '2026-09-21')), '17 semanas · -1,2 kg');
  assert.equal(TC.resumen('2026-07-20', '2026-11-16', SEB), '17 semanas · -1,5 kg');
  assert.equal(pieTuCambio(fotosDe('2026-07-20', '2026-11-16'), SEB), '17 semanas · -1,5 kg');
});
// mrl1cczlai0u: libras hasta el 20/09 (213,8 a 220,4), kilos desde el 21/09 (98 a 101,4). Con la serie larga la cuenta
// vieja daba «12 semanas · −117,6 kg». Ahora: «12 semanas», sin kilos.
const LB = serie([['2026-08-17', 218.0], ['2026-08-30', 216.2], ['2026-09-20', 214.0], ['2026-09-21', 99.0], ['2026-10-15', 99.8], ['2026-11-09', 100.4]]);
await caso('libras: no muestra kilos (ni −117,6 ni nada)', () => {
  assert.equal(resumenViejo('2026-08-17', '2026-11-09', LB), '12 semanas · -117,6 kg');
  assert.equal(TC.resumen('2026-08-17', '2026-11-09', LB), '12 semanas');
  assert.equal(pieTuCambio(fotosDe('2026-08-17', '2026-11-09'), LB), '12 semanas');
  // Y al revés (kilos la primera semana, libras la última), igual.
  assert.equal(TC.resumen('2026-08-17', '2026-11-09', serie([['2026-08-18', 99.0], ['2026-11-10', 218.0]])), '12 semanas');
});

// ── Semanas sin peso ──
await caso('semana sin peso: toma el más cercano dentro de ±7 días', () => {
  // Semana del 14/09 (lun) al 20/09 (dom) sin peso: el 08/09 está a 6 días del lunes; el 25/09, a 5 del domingo → 80,0.
  const p = serie([['2026-09-08', 81.0], ['2026-09-25', 80.0], ['2026-11-10', 78.5]]);
  assert.equal(TC.pesoDeSemana('2026-09-14', p), 80.0);
  assert.equal(TC.resumen('2026-09-14', '2026-11-09', p), '8 semanas · -1,5 kg');
  // El de antes, si es el más cercano.
  assert.equal(TC.pesoDeSemana('2026-09-14', serie([['2026-09-12', 81.0], ['2026-09-26', 80.0]])), 81.0);
  // Empate de distancia: el de después.
  assert.equal(TC.pesoDeSemana('2026-09-14', serie([['2026-09-11', 81.0], ['2026-09-23', 80.0]])), 80.0);
  // Justo a 7 días todavía cuenta; a 8, no.
  assert.equal(TC.pesoDeSemana('2026-09-14', serie([['2026-09-07', 81.0]])), 81.0);
  assert.equal(TC.pesoDeSemana('2026-09-14', serie([['2026-09-27', 80.0]])), 80.0);
  assert.equal(TC.pesoDeSemana('2026-09-14', serie([['2026-09-06', 81.0], ['2026-09-28', 80.0]])), null);
});
await caso('sin peso cercano: no muestra kilos', () => {
  const p = serie([['2026-09-01', 81.0], ['2026-09-29', 80.0], ['2026-11-10', 78.5]]);
  assert.equal(TC.resumen('2026-09-14', '2026-11-09', p), '8 semanas');
  assert.equal(pieTuCambio(fotosDe('2026-09-14', '2026-11-09'), p), '8 semanas');
  // Tampoco si la que falta es la última.
  assert.equal(TC.resumen('2026-09-14', '2026-11-09', serie([['2026-09-15', 81.0], ['2026-10-20', 79.0]])), '8 semanas');
});
await caso('I1: el mismo pesaje (o pesajes de la misma semana) en las dos fotos: sin kg', () => {
  // Un solo peso el domingo 15/11, fotos 09/11 y 16/11: las dos fotos toman ese mismo pesaje.
  assert.equal(TC.resumen('2026-11-09', '2026-11-16', serie([['2026-11-15', 80.0]])), '1 semana');
  // Pesos el 09/11 y el 15/11, fotos 09/11 y 16/11: el de la última foto es de la semana de la primera.
  assert.equal(TC.resumen('2026-11-09', '2026-11-16', serie([['2026-11-09', 80.6], ['2026-11-15', 80.0]])), '1 semana');
  // Un solo peso el 12/11, fotos 02/11 y 16/11.
  assert.equal(TC.resumen('2026-11-02', '2026-11-16', serie([['2026-11-12', 80.0]])), '2 semanas');
  // Al revés: el de la primera foto cae en la semana de la última.
  assert.equal(TC.resumen('2026-11-09', '2026-11-16', serie([['2026-11-16', 80.0], ['2026-11-18', 79.5]])), '1 semana');
  // Dos pesajes distintos con el mismo valor, cada uno en su semana: 0,0 kg es real y se muestra.
  assert.equal(TC.resumen('2026-07-20', '2026-11-16', serie([['2026-07-21', 78.9], ['2026-11-17', 78.9]])), '17 semanas · 0,0 kg');
  // Semanas seguidas, cada una con su pesaje (uno de ellos tomado de ±7 días fuera de la otra semana): se muestra.
  assert.equal(TC.resumen('2026-11-09', '2026-11-16', serie([['2026-11-08', 80.5], ['2026-11-17', 80.0]])), '1 semana · -0,5 kg');
  // Si el más cercano a la semana 1 es el de la semana de la última foto, sería el mismo pesaje: sin kg.
  assert.equal(TC.resumen('2026-11-09', '2026-11-16', serie([['2026-11-06', 80.5], ['2026-11-17', 80.0]])), '1 semana');
});
await caso('dentro de la semana gana el primero cargado (como antes), aunque haya uno más cerca afuera', () => {
  const p = serie([['2026-11-08', 70.0], ['2026-11-15', 71.0], ['2026-11-12', 72.0]]);
  assert.equal(TC.pesoDeSemana('2026-11-09', p), 72.0);
});

// ── Guarda de unidades ──
await caso('guarda: solo el 25 % del peso inicial; un cambio rápido pero real se muestra', () => {
  // Tirzepatida o déficit agresivo: −3,5 kg en 2 semanas SÍ se muestra (no hay tope por semana).
  assert.equal(TC.resumen('2026-10-26', '2026-11-09', serie([['2026-10-26', 95.0], ['2026-11-09', 91.5]])), '2 semanas · -3,5 kg');
  assert.equal(TC.resumen('2026-11-02', '2026-11-09', serie([['2026-11-02', 80.0], ['2026-11-09', 76.0]])), '1 semana · -4,0 kg');
  // Justo en el 25 % todavía se muestra; apenas arriba, no.
  assert.equal(TC.resumen('2026-09-14', '2026-11-09', serie([['2026-09-14', 80.0], ['2026-11-09', 100.0]])), '8 semanas · +20,0 kg');
  assert.equal(TC.resumen('2026-09-14', '2026-11-09', serie([['2026-09-14', 80.0], ['2026-11-09', 100.1]])), '8 semanas');
  assert.equal(TC.resumen('2026-09-14', '2026-11-09', serie([['2026-09-14', 80.0], ['2026-11-09', 59.9]])), '8 semanas');
  // 40 → 51: un 27,5 %.
  assert.equal(TC.resumen('2026-09-07', '2026-11-16', serie([['2026-09-07', 40.0], ['2026-11-16', 51.0]])), '10 semanas');
  assert.deepEqual(TC.cambio('2026-08-17', '2026-11-09', LB), { semanas: 12, kg: null });
});
await caso('sin «-0,0 kg»', () => {
  assert.equal(TC.resumen('2026-11-02', '2026-11-09', serie([['2026-11-02', 80.0], ['2026-11-09', 79.96]])), '1 semana · 0,0 kg');
  assert.equal(TC.resumen('2026-11-02', '2026-11-09', serie([['2026-11-02', 80.0], ['2026-11-09', 80.0]])), '1 semana · 0,0 kg');
});

// ── Foto dentro de los 60 días: igual que antes ──
await caso('fotos dentro de los 60 días, con peso en cada semana: el mismo pie que antes', () => {
  const p = serie([['2026-09-22', 79.0], ['2026-09-24', 78.6], ['2026-10-01', 78.9], ['2026-10-27', 78.1], ['2026-10-29', 77.9],
    ['2026-11-16', 77.8], ['2026-11-17', 77.5]]);
  for (const [a, b] of [['2026-09-21', '2026-11-16'], ['2026-09-21', '2026-10-26'], ['2026-10-26', '2026-11-16'], ['2026-09-28', '2026-11-16']]) {
    assert.equal(TC.resumen(a, b, p), resumenViejo(a, b, p), `${a} → ${b}`);
  }
  assert.equal(TC.resumen('2026-09-21', '2026-11-16', p), '8 semanas · -1,2 kg');
  assert.equal(pieTuCambio(fotosDe('2026-09-21', '2026-11-16'), p), '8 semanas · -1,2 kg');
});

// ── 2. La serie aparte (los helpers de la página, con dobles) ──
const pagina = tramo('// Serie de peso por fecha (prefiere carga manual sobre wearable) ordenada asc.', '// Media de los puntos cuya fecha cae en');
function montar({ fotos = [], salud = [], cola = {}, hoy = '2026-11-19', demo = false, respuesta = [] } = {}) {
  const llamadas = [];
  const env = {
    STATE: { fotos, salud }, TOKEN: 'tok', DATA: { _isDemo: demo }, TuCambio: TC,
    hoyLocal: () => hoy, _fotoqLeer: () => cola,
    _lunesISO: (f) => TC.lunes(f),
    window: { mypumpDB: { getPesoSalud: async (t, d, h) => { llamadas.push([t, d, h]); return typeof respuesta === 'function' ? respuesta() : respuesta; } } },
  };
  const f = new Function(...Object.keys(env), `${pagina}\nreturn { _pesoSerie, _pcAsegurar, _pesoSerieComparador, _pcDesdeNecesario };`)(...Object.values(env));
  return { ...f, env, llamadas };
}
const fila = (fecha, valor, fuente = 'manual') => ({ fecha, tipo: 'peso_kg', valor, fuente });
await caso('serie aparte: se pide solo el peso, desde el lunes de la primera foto menos 7 días hasta hoy, una vez', async () => {
  const m = montar({ fotos: [{ semana_lunes: '2026-11-16', pose: 'frente' }, { semana_lunes: '2026-08-31', pose: 'frente' }],
    respuesta: [fila('2026-09-02', 73.0), fila('2026-10-29', 67.7)] });
  assert.equal(m._pcDesdeNecesario(), '2026-08-24');
  assert.equal(await m._pcAsegurar(), true);
  assert.deepEqual(m.llamadas, [['tok', '2026-08-24', '2026-11-19']]);
  assert.equal(await m._pcAsegurar(), false);   // ya está: no se vuelve a pedir
  assert.equal(m.llamadas.length, 1);
});
await caso('serie aparte: la foto más vieja de la cola también cuenta', async () => {
  const m = montar({ fotos: [{ semana_lunes: '2026-10-05', pose: 'frente' }], cola: { 'x': { fecha: '2026-09-03', pose: 'perfil' } } });
  assert.equal(m._pcDesdeNecesario(), '2026-08-24');
});
await caso('serie aparte: si los 60 días de Salud ya cubren la primera foto, no se pide nada', async () => {
  const m = montar({ fotos: [{ semana_lunes: '2026-10-05', pose: 'frente' }] });
  assert.equal(await m._pcAsegurar(), false);
  assert.equal(m.llamadas.length, 0);
});
await caso('serie aparte: en la demo o sin fotos, no se pide nada', async () => {
  assert.equal(await montar({ demo: true, fotos: [{ semana_lunes: '2026-07-20', pose: 'frente' }] })._pcAsegurar(), false);
  const sin = montar();
  assert.equal(await sin._pcAsegurar(), false);
  assert.equal(sin.llamadas.length, 0);
});
await caso('serie aparte: si falla, no reintenta en cada render (sí 5 minutos después)', async () => {
  const m = montar({ fotos: [{ semana_lunes: '2026-07-20', pose: 'frente' }], respuesta: null });
  assert.equal(await m._pcAsegurar(), false);
  assert.equal(await m._pcAsegurar(), false);
  assert.equal(m.llamadas.length, 1);
  m.env.STATE.pesoComp.ts -= 6 * 60 * 1000;
  await m._pcAsegurar();
  assert.equal(m.llamadas.length, 2);
});
await caso('serie aparte: dos pedidos a la vez comparten la misma llamada', async () => {
  const m = montar({ fotos: [{ semana_lunes: '2026-07-20', pose: 'frente' }], respuesta: [fila('2026-07-22', 79.3)] });
  const [a, b] = await Promise.all([m._pcAsegurar(), m._pcAsegurar()]);
  assert.equal(a, true); assert.equal(b, true);
  assert.equal(m.llamadas.length, 1);
});
await caso('serie del comparador: la aparte más Salud (el peso de hoy), la manual gana; Salud no cambia', async () => {
  const salud = [fila('2026-11-16', 68.6, 'apple_health'), fila('2026-11-16', 68.4), fila('2026-11-19', 68.2), { fecha: '2026-11-19', tipo: 'pasos', valor: 9000, fuente: 'apple_health' }];
  const m = montar({ fotos: [{ semana_lunes: '2026-08-31', pose: 'frente' }], salud,
    respuesta: [fila('2026-09-02', 73.0), fila('2026-11-16', 68.6, 'apple_health'), fila('2026-11-16', 68.4)] });
  await m._pcAsegurar();
  assert.deepEqual(m._pesoSerieComparador(), serie([['2026-09-02', 73.0], ['2026-11-16', 68.4], ['2026-11-19', 68.2]]));
  assert.deepEqual(m._pesoSerie(), serie([['2026-11-16', 68.4], ['2026-11-19', 68.2]]));   // la de Salud, sin lo viejo
  assert.equal(m.env.STATE.salud, salud);
  assert.equal(TC.resumen('2026-08-31', '2026-11-16', m._pesoSerieComparador()), '11 semanas · -4,6 kg');
});

await caso('M1: si el alumno corrige el peso de hoy, el comparador usa el valor nuevo sin recargar', async () => {
  const salud = [fila('2026-11-16', 68.4), fila('2026-11-19', 70.0)];
  const m = montar({ fotos: [{ semana_lunes: '2026-08-31', pose: 'frente' }], salud,
    respuesta: [fila('2026-09-02', 73.0), fila('2026-11-16', 68.4), fila('2026-11-19', 70.0)] });
  await m._pcAsegurar();
  assert.equal(TC.resumen('2026-08-31', '2026-11-16', m._pesoSerieComparador()), '11 semanas · -4,6 kg');
  // Lo mismo que hacen _cgPonerPeso y el guardado de Mi día: sacan el manual de hoy de STATE.salud y ponen el nuevo.
  m.env.STATE.salud = m.env.STATE.salud.filter(r => !(r.fecha === '2026-11-19' && r.fuente === 'manual'));
  m.env.STATE.salud.push(fila('2026-11-19', 68.0));
  const s2 = m._pesoSerieComparador();
  assert.deepEqual(s2.find(p => p.fecha === '2026-11-19'), { fecha: '2026-11-19', kg: 68.0 });
  assert.equal(s2.filter(p => p.fecha === '2026-11-19').length, 1);
  assert.equal(TC.resumen('2026-08-31', '2026-11-16', s2), '11 semanas · -4,6 kg');   // el 16/11 sigue siendo el de su semana
  assert.equal(TC.resumen('2026-08-31', '2026-11-19', s2), '11 semanas · -5,0 kg');
  assert.equal(m.llamadas.length, 1);   // sin volver a pedir
});

// ── 3. Los dos caminos usan la misma cuenta ──
await caso('«Antes y ahora» y «Tu cambio» usan TuCambio.resumen con la serie del comparador', () => {
  const gal = tramo('async function abrirGaleriaFotos(opciones) {', '  const tira = semanas.map(');
  assert.match(gal, /TuCambio\.resumen\(primera, ultima, _pesoSerieComparador\(\)\)/);
  assert.match(gal, /await _pcAsegurar\(\)/);
  assert.doesNotMatch(gal, /p\.fecha >= sem/);
  assert.match(html, /function _tcVista\(pose\) \{[\s\S]{0,300}peso: _pesoSerieComparador\(\)/);
  // La fila Peso de Salud sigue con los 60 días.
  assert.match(html, /_filaSalud\(\{ tipo: 'peso_kg'/);
  assert.match(tramo('async function loadSalud() {', 'STATE.salud = (await'), /setDate\(d\.getDate\(\) - 59\)/);
});
await caso('el cliente pide solo el peso, filtrado por PostgREST', () => {
  const cli = fs.readFileSync(path.join(raiz, 'public/js/supabase-client.js'), 'utf8');
  assert.match(cli, /async getPesoSalud\(token, desde, hasta\) \{\s*return await rpc\('mypump_get_salud', \{ p_token: token, p_desde: desde, p_hasta: hasta \}, TOPE_LECTURA_MS, q => q\.eq\('tipo', 'peso_kg'\)\);/);
  assert.match(cli, /if \(filtrar\) q = filtrar\(q\);/);
});

console.log(`${mal ? '✗' : '✓'} comparador-peso: ${ok} bien, ${mal} mal`);
process.exit(mal ? 1 : 0);
