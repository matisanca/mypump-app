// Reserva clínica (19/11, OK de Mati): el plan que deja reps en reserva a propósito (cardiopatía, lumbar, competencia)
// nunca ve «Al fallo», «llevá al fallo» ni «Subí la carga»: ve la pauta del plan. Sin reserva, todo igual.
// Vectores: scripts/vectores-app/reserva_clinica.json, copia exacta de apps/shared/vectores (los mismos de iOS y Android).
// 1) Las reglas (reglas-entreno.js, carga-simple.js) y lo de cliente.html que decide, contra los vectores.
// 2) En Chrome de verdad: un plan con RIR clínico y otro sin RIR, con la pantalla de Entreno y cada ejercicio abierto.
import fs from 'node:fs';
import { createServer } from 'node:http';
import { spawn } from 'node:child_process';
import { tmpdir } from 'node:os';
import { join, extname, normalize, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';
import assert from 'node:assert/strict';

const require = createRequire(import.meta.url);
const raiz = join(dirname(fileURLToPath(import.meta.url)), '..');
const E = require('../public/js/reglas-entreno.js');
const C = require('../public/js/carga-simple.js');
const V = JSON.parse(fs.readFileSync(join(raiz, 'scripts/vectores-app/reserva_clinica.json'), 'utf8'));
const HTML = fs.readFileSync(join(raiz, 'public/cliente.html'), 'utf8');
const PROHIBIDO = new RegExp(V.prohibido, 'i');
// Regla de Mati: en lo que ve el alumno nunca — – « » · (el rango va «2 a 3»).
const SIGNOS = new RegExp(V.signos);
let n = 0;

const comoDias = (ejercicios) => [{ id: 'd1', bloques: [{ ejercicios }] }];

// ── 1. Las reglas ──
for (const r of V.indicada.si) { assert.equal(E.reservaIndicada(r), true, `indicada ${JSON.stringify(r)}`); n++; }
for (const r of V.indicada.no) { assert.equal(E.reservaIndicada(r), false, `no indicada ${JSON.stringify(r)}`); n++; }
for (const c of V.leyenda) {
  assert.equal(E.leyendaReserva(c.rir), c.sale, `leyenda ${JSON.stringify(c.rir)}`);
  assert.ok(!SIGNOS.test(E.leyendaRir(c.rir)), `leyenda sin signos prohibidos: ${E.leyendaRir(c.rir)}`);
  // La leyenda de «Series efectivas»: sin reserva clínica, «Al fallo» (2.3.0); con reserva, la del plan o ninguna.
  assert.equal(E.leyendaSerie('compuesto', false, c.rir, false), 'Al fallo');
  assert.equal(E.leyendaSerie('compuesto', false, c.rir, true), c.sale);
  assert.equal(E.leyendaSerie('calentamiento', false, c.rir, true), null, 'el calentamiento no lleva leyenda');
  n++;
}
assert.equal(E.fraseLeyenda('Al fallo'), ' al fallo');
assert.equal(E.fraseLeyenda('Dejando 2 a 3 en reserva'), ' dejando 2 a 3 en reserva');
assert.equal(E.fraseLeyenda(null), '');
n++;
for (const c of V.planes) { assert.equal(E.reservaClinicaDelPlan(comoDias(c.ejercicios), c.semana), c.sale, c.nombre); n++; }
assert.equal(E.reservaClinicaDelPlan(null, 1), false);
assert.equal(E.reservaClinicaDelPlan([{ bloques: [{ ejercicios: [null, {}] }] }, {}], 0), false, 'plan roto: sin reserva y sin romper');
n++;

// La nota de cliente.html: la función de verdad, sacada del HTML.
function extraer(nombre, desde = 'function') {
  const i = HTML.indexOf(`${desde} ${nombre}(`);
  if (i < 0) throw new Error(`no encontré ${desde} ${nombre}( en cliente.html`);
  let prof = 0, fin = -1;
  for (let k = HTML.indexOf('{', i); k < HTML.length; k++) {
    if (HTML[k] === '{') prof++;
    else if (HTML[k] === '}') { prof--; if (prof === 0) { fin = k + 1; break; } }
  }
  if (fin < 0) throw new Error(`no pude cerrar ${nombre}`);
  return HTML.slice(i, fin);
}
const H = new Function('ReglasEntreno', 'ctx', [
  'let DATA = null;',
  extraer('computeProgresionNota'),
  'let _rcMemo = null;',
  extraer('_reservaClinica'),
  extraer('_bannerSemana'),
  'return { computeProgresionNota, _reservaClinica, _bannerSemana, ponerDATA: (d) => { DATA = d; } };',
].join('\n'))(E);

for (const c of V.notas) {
  const con = H.computeProgresionNota(c.ejercicio, c.semana, true);
  const sin = H.computeProgresionNota(c.ejercicio, c.semana, false);
  assert.deepEqual(con, c.sale, `con reserva: ${c.nombre}`);
  assert.deepEqual(sin, c.sinReserva, `sin reserva: ${c.nombre}`);
  if (con) assert.ok(!PROHIBIDO.test(con.texto), `con reserva no dice «al fallo» ni «subí la carga»: ${con.texto}`);
  for (const x of [con, sin]) if (x) assert.ok(!SIGNOS.test(x.texto), `sin signos prohibidos ni guion de relleno: ${x.texto}`);
  n++;
}
assert.equal(H.computeProgresionNota({ progresion: [] }, 2, true), null, 'sin progresión no hay nota');
for (const c of V.banner) {
  assert.deepEqual(H._bannerSemana(c.ejercicios, c.semana, c.offset, false), c.sinReserva, `cartel sin reserva: ${c.nombre}`);
  assert.deepEqual(H._bannerSemana(c.ejercicios, c.semana, c.offset, true), c.conReserva, `cartel con reserva: ${c.nombre}`);
  n++;
}

// Quién tiene reserva clínica: el plan del alumno, nunca la demo (su plan de ejemplo trae rir_objetivo «1-2»).
{
  const clinico = V.planes.find(p => p.sale === true && p.semana === 1);
  const dias = comoDias(clinico.ejercicios);
  H.ponerDATA(null);
  assert.equal(H._reservaClinica(), false, 'sin DATA');
  H.ponerDATA({ _isDemo: true, rutina: { semana_actual: 1 }, _dias: dias });
  assert.equal(H._reservaClinica(), false, 'la demo queda como siempre');
  const d = { _isDemo: false, rutina: { semana_actual: 1 }, _dias: dias };
  H.ponerDATA(d);
  assert.equal(H._reservaClinica(), true, 'el plan del alumno con 2-3');
  const fin = V.planes.find(p => /ya terminó/.test(p.nombre));
  d._dias = comoDias(fin.ejercicios);
  d.rutina.semana_actual = fin.semana;
  assert.equal(H._reservaClinica(), false, 'otro plan u otra semana: se vuelve a calcular');
  d.rutina.semana_actual = 1;
  assert.equal(H._reservaClinica(), true, 'en su primera pauta (2-3) todavía tiene reserva');
  n++;
}

// La carga simple: con reserva nunca sugiere subir, tampoco la sugerencia que quedó guardada de antes.
for (const c of V.aumento) {
  const armar = (reservaClinica, estado) => new C.Carga(c.ejercicio, c.semana, { ultimaVez: c.ultimaVez, equipo: c.equipo, reservaClinica, estado });
  const sin = armar(false);
  assert.deepEqual(sin.aumento, c.sinReserva, `aumento sin reserva: ${c.nombre}`);
  assert.deepEqual(armar(true).aumento, c.conReserva, `aumento con reserva: ${c.nombre}`);
  assert.equal(C.corresponde(c.ejercicio, c.semana, null, true), false);
  assert.equal(C.corresponde(c.ejercicio, c.semana, null, false), c.sinReserva.tipo === 'sugerido');
  // Guardado antes de este arreglo, con la sugerencia: con reserva se cae; aceptada por el alumno, queda.
  const guardado = sin.estado;
  assert.deepEqual(armar(true, guardado).aumento, { tipo: 'noCorresponde' }, 'sugerencia guardada: con reserva se cae');
  assert.equal(armar(true, guardado).carga, c.sinReserva.desde, 'la carga sigue en la de la última vez');
  assert.deepEqual(armar(false, guardado).aumento, c.sinReserva, 'sin reserva, la guardada sigue');
  sin.aceptarAumento();
  assert.equal(sin.aumento.tipo, 'aceptado');
  assert.equal(armar(true, sin.estado).aumento.tipo, 'aceptado', 'lo que aceptó el alumno queda');
  n++;
}

// Las notas técnicas con reserva clínica van enteras (la reserva es del plan); sin reserva, sin RIR.
{
  const nota = 'Dejá 2 repeticiones en reserva y bajá controlado.';
  assert.equal(E.notaParaAlumno(nota, null, true), nota, 'reserva clínica del plan: la nota entera aunque esta semana no traiga rir');
  assert.equal(E.notaParaAlumno(nota, '0', false), E.sinRIR(nota), 'sin reserva: sin RIR');
  n++;
}

// cliente.html usa la regla en cada lugar que dice «al fallo» o sugiere subir.
const cables = [
  ['computeProgresionNota(ex, DATA.rutina.semana_actual, _clinica)', 'la nota del ejercicio'],
  ['_bannerSemana(_exDia, DATA.rutina.semana_actual, DATA.rutina.semana_offset, _reservaClinica())', 'el cartel de la semana'],
  ['ReglasEntreno.notaParaAlumno(ex.notas_tecnica, prog.rir, _clinica)', 'la nota técnica'],
  ['ReglasEntreno.notaParaAlumno(n, _rirPlan, _reservaClinica())', 'la nota de la preparación'],
  ['ReglasEntreno.leyendaSerie(ex.tipo, esSinPeso(ex), prog.rir, _clinica)', 'la leyenda de las series'],
  ['getProgresionActual(ex, DATA.rutina.semana_actual).rir, _reservaClinica()))', 'la pista de primera vez (carga simple)'],
  ['ReglasEntreno.leyendaSerie(ex.tipo, esSinPeso(ex), prog.rir, _reservaClinica()))', 'la pista de primera vez (la de antes)'],
  ['reservaClinica: _reservaClinica(),', 'la sugerencia de subir de la carga simple'],
];
for (const [t, que] of cables) { assert.ok(HTML.includes(t), `cliente.html: ${que}`); n++; }
assert.ok(!/['"`]Al fallo['"`]/.test(HTML), 'cliente.html no escribe «Al fallo» a mano: la leyenda sale de ReglasEntreno');
n++;

// ── 2. En el navegador de verdad ──
const CH = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
let enChrome = 0;

const PLAN = (rir) => {
  const prog = (reps) => reps.map((r, i) => ({ semana: i + 1, series: 3, reps: r, rir }));
  return {
    nombre_plan: 'Plan de prueba', semanas_total: 4,
    dias: [{ id: 'd1', n: 1, nombre: 'Empuje A', bloques: [
      { titulo: 'BLOQUE 1', subtitulo: 'Pecho y tríceps', ejercicios: [
        { id: 'e1', nombre: 'Press banca plano con barra', tipo: 'compuesto', series: 3, reps: '12', rir_objetivo: rir, descanso_segundos: 120,
          notas_tecnica: 'Dejá 2 repeticiones en reserva y bajá controlado.', progresion: prog(['12', '10', '8', '8']) },
        { id: 'e2', nombre: 'Extensión tríceps en polea', tipo: 'aislamiento', series: 3, reps: '12-15', rir_objetivo: rir, descanso_segundos: 75,
          progresion: prog(['12-15', '12-15', '10-12', '10-12']) },
      ] },
    ] }],
  };
};

async function pantallaDeEntreno({ rir, semana, web230 }) {
  const TIPOS = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.css': 'text/css', '.json': 'application/json', '.woff2': 'font/woff2', '.svg': 'image/svg+xml', '.png': 'image/png' };
  const servidor = createServer((req, res) => {
    const ruta = decodeURIComponent(new URL(req.url, 'http://x').pathname);
    if (ruta === '/js/config.js') {
      res.writeHead(200, { 'content-type': TIPOS['.js'], 'cache-control': 'no-store' });
      res.end(`window.MYPUMP_CONFIG = { SUPABASE_URL: location.origin + '/sb', SUPABASE_ANON_KEY: 'clave-de-prueba', VISION_URL: '', APP_URL: location.origin, VAPID_PUBLIC_KEY: '' };`);
      return;
    }
    if (ruta === '/sw.js' || ruta.startsWith('/sb/')) { res.writeHead(404); res.end(); return; }
    const archivo = join(raiz, 'public', normalize(ruta === '/cliente' ? '/cliente.html' : ruta).replace(/^(\.\.[/\\])+/, ''));
    if (!archivo.startsWith(join(raiz, 'public')) || !fs.existsSync(archivo) || !extname(archivo)) { res.writeHead(404); res.end(); return; }
    res.writeHead(200, { 'content-type': TIPOS[extname(archivo)] || 'application/octet-stream', 'cache-control': 'no-store' });
    res.end(fs.readFileSync(archivo));
  });
  await new Promise((r) => servidor.listen(0, '127.0.0.1', r));
  const BASE = `http://127.0.0.1:${servidor.address().port}`;
  const perfil = fs.mkdtempSync(join(tmpdir(), 'reserva-clinica-chrome-'));
  const chrome = spawn(CH, ['--headless=new', '--disable-gpu', '--no-first-run', '--no-default-browser-check',
    '--remote-debugging-port=0', `--user-data-dir=${perfil}`], { stdio: 'ignore' });
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  let ws, id = 0;
  const pend = new Map(), errores = [];
  const cmd = (method, params = {}) => new Promise((res, rej) => { const i = ++id; pend.set(i, { res, rej }); ws.send(JSON.stringify({ id: i, method, params })); });
  const evaluar = async (expr) => {
    const r = await cmd('Runtime.evaluate', { expression: expr, returnByValue: true });
    if (r.exceptionDetails) throw new Error(r.exceptionDetails.exception ? r.exceptionDetails.exception.description : r.exceptionDetails.text);
    return r.result.value;
  };
  try {
    let lista = [];
    for (let i = 0; i < 160 && !lista.length; i++) {
      try {
        const puerto = fs.readFileSync(join(perfil, 'DevToolsActivePort'), 'utf8').split('\n')[0].trim();
        lista = (await (await fetch(`http://127.0.0.1:${puerto}/json`)).json()).filter((t) => t.type === 'page');
      } catch { /* arrancando */ }
      if (!lista.length) await sleep(250);
    }
    ws = new WebSocket(lista[0].webSocketDebuggerUrl);
    await new Promise((r, j) => { ws.onopen = r; ws.onerror = j; });
    ws.onmessage = (e) => {
      const m = JSON.parse(e.data);
      if (m.id && pend.has(m.id)) { const p = pend.get(m.id); pend.delete(m.id); m.error ? p.rej(new Error(m.error.message)) : p.res(m.result); }
      else if (m.method === 'Runtime.exceptionThrown') errores.push(m.params.exceptionDetails.exception ? m.params.exceptionDetails.exception.description : m.params.exceptionDetails.text);
    };
    await cmd('Page.enable'); await cmd('Runtime.enable');
    await cmd('Emulation.setDeviceMetricsOverride', { width: 390, height: 844, deviceScaleFactor: 2, mobile: true });
    await cmd('Page.navigate', { url: `${BASE}/cliente?demo=1${web230 ? '' : '&web230=0'}` });
    let arranco = false;
    for (const fin = Date.now() + 15000; Date.now() < fin && !arranco;) {
      try { arranco = !!(await evaluar('typeof DATA !== "undefined" && !!DATA && DATA._isDemo === true && document.querySelector("#appRoot").hidden === false && document.querySelector("#loadScreen").hidden === true')); } catch { /* cargando */ }
      if (!arranco) await sleep(200);
    }
    assert.ok(arranco, 'la web no arrancó');
    // El plan del alumno en lugar del de la demo, por el mismo camino que la carga real (normalizarRutina), con la
    // última vez a 80 kg para que la carga simple tenga de dónde sugerir.
    const preparar = `(() => {
      const nr = normalizarRutina(${JSON.stringify(PLAN(rir))});
      if (!nr.usable) return 'plan no usable: ' + JSON.stringify(nr.problemas);
      const hace7 = new Date(Date.now() - 7 * 864e5).toISOString();
      DATA._isDemo = false;
      DATA.rutina = { ...DATA.rutina, nombre_plan: nr.est.nombre_plan, semanas_total: nr.est.semanas_total,
        semana_actual: ${semana}, semana_offset: 0, mensajes_semana: [] };
      DATA._dias = nr.est.dias;
      DATA.dia = nr.est.dias[0];
      DATA.historico_por_ejercicio = {};
      for (const b of DATA.dia.bloques) for (const ex of b.ejercicios) {
        DATA.historico_por_ejercicio[ex.id] = [1, 2, 3].map(s => ({ registrado_en: hace7, serie_numero: s, reps_realizadas: 12, peso_kg: ex.tipo === 'compuesto' ? 80 : 25 }));
      }
      STATE.exerciseStates = {}; STATE.exerciseMeta = {};
      STATE.session = buildSession();
      STATE.expandedId = null;
      setScene('train');
      renderTrain();
      return DATA.dia.bloques.flatMap(b => b.ejercicios.map(ex => ex.id));
    })()`;
    const ids = await evaluar(preparar);
    assert.ok(Array.isArray(ids) && ids.length === 2, `no se pudo poner el plan: ${JSON.stringify(ids)}`);
    const textos = { lista: await evaluar('document.body.innerText'), ejercicios: {} };
    for (const exId of ids) {
      // Abierto, con la carga y con la nota técnica desplegada (como la abre el alumno).
      textos.ejercicios[exId] = await evaluar(`(() => { STATE.expandedId = ${JSON.stringify(exId)}; renderTrain(); if (typeof csPintarPanel === 'function') csPintarPanel();
        document.querySelectorAll('[data-acc^="note-"]').forEach((b) => b.click()); return document.body.innerText; })()`);
    }
    textos.clinica = await evaluar('_reservaClinica()');
    if (process.env.VER_PANTALLAS) console.log(`--- rir ${rir} semana ${semana} web230 ${web230}\n`, JSON.stringify(textos, null, 1));
    return { textos, errores };
  } finally {
    try { ws && ws.close(); } catch { /* nada */ }
    chrome.kill('SIGKILL');
    servidor.close();
    try { fs.rmSync(perfil, { recursive: true, force: true }); } catch { /* nada */ }
  }
}

if (!fs.existsSync(CH) || typeof WebSocket === 'undefined') {
  // En CI no vale saltearla en silencio: sin navegador no se probaron las pantallas.
  if (process.env.CI) { console.error('test-reserva-clinica: sin Chrome (o sin WebSocket en Node) en CI: faltan las pantallas'); process.exit(1); }
  console.log('test-reserva-clinica: sin Chrome (o sin WebSocket en Node), se saltea la prueba en el navegador');
} else {
  for (const web230 of [true, false]) {
    const vista = web230 ? 'web 2.3.0' : 'web de antes';
    // Semana 2: bajan las reps (12 → 10) con las mismas series. Sin reserva: «Subí la carga», «toca subir», «Al fallo».
    const con = await pantallaDeEntreno({ rir: '2-3', semana: 2, web230 });
    assert.deepEqual(con.errores, [], `${vista}: excepciones en la página`);
    assert.equal(con.textos.clinica, true, `${vista}: el plan con 2-3 tiene reserva clínica`);
    const todoCon = [con.textos.lista, ...Object.values(con.textos.ejercicios)].join('\n');
    assert.ok(!PROHIBIDO.test(todoCon), `${vista}, con reserva: apareció «${(todoCon.match(PROHIBIDO) || [])[0]}»`);
    // La reserva va «2 a 3», nunca con guion medio (el «16–20» de la preparación es de antes y no es de esta regla).
    assert.ok(!/\d\s*[–—]\s*\d[^\n]*en reserva/i.test(todoCon), `${vista}, con reserva: la reserva con guion medio: ${(todoCon.match(/[^\n]*\d\s*[–—]\s*\d[^\n]*en reserva/i) || [])[0]}`);
    assert.ok(!/cambia(n)? carga o volumen/.test(todoCon), `${vista}, con reserva: sin el cartel de la semana`);
    assert.ok(todoCon.includes('Seguí la pauta de esta semana (3×10), dejando 2 a 3 en reserva.'), `${vista}, con reserva: la pauta del plan`);
    assert.ok(todoCon.includes('Dejando 2 a 3 en reserva'), `${vista}, con reserva: la leyenda de la reserva`);
    assert.ok(todoCon.includes('Dejá 2 repeticiones en reserva'), `${vista}, con reserva: la nota técnica entera`);

    const sin = await pantallaDeEntreno({ rir: '0', semana: 2, web230 });
    assert.deepEqual(sin.errores, [], `${vista}: excepciones en la página`);
    assert.equal(sin.textos.clinica, false, `${vista}: el plan al fallo no tiene reserva clínica`);
    const todoSin = [sin.textos.lista, ...Object.values(sin.textos.ejercicios)].join('\n');
    assert.ok(todoSin.includes('Subí la carga'), `${vista}, sin reserva: la nota de progresión de siempre`);
    assert.ok(/Al fallo/.test(todoSin), `${vista}, sin reserva: la leyenda «Al fallo»`);
    assert.ok(!todoSin.includes('Dejando 2 a 3 en reserva'), `${vista}, sin reserva: sin la leyenda de reserva`);
    assert.ok(!todoSin.includes('Dejá 2 repeticiones en reserva') && todoSin.includes(E.sinRIR('Dejá 2 repeticiones en reserva y bajá controlado.')),
      `${vista}, sin reserva: la nota técnica sin RIR`);
    if (web230) assert.ok(todoSin.includes('toca subir'), `${vista}, sin reserva: la carga simple sugiere subir`);
    assert.ok(/cambia(n)? carga o volumen/.test(todoSin), `${vista}, sin reserva: el cartel de la semana`);

    // Semana 1: sin reserva, la calibración «al fallo»; con reserva, la pauta.
    const con1 = await pantallaDeEntreno({ rir: '2-3', semana: 1, web230 });
    const todoCon1 = [con1.textos.lista, ...Object.values(con1.textos.ejercicios)].join('\n');
    assert.deepEqual(con1.errores, [], `${vista}: excepciones en la página`);
    assert.ok(!PROHIBIDO.test(todoCon1), `${vista}, semana 1 con reserva: apareció «${(todoCon1.match(PROHIBIDO) || [])[0]}»`);
    assert.ok(!/calibración/i.test(todoCon1), `${vista}, semana 1 con reserva: sin la calibración`);
    assert.ok(todoCon1.includes('Seguí la pauta de esta semana (3×12), dejando 2 a 3 en reserva.'), `${vista}, semana 1 con reserva: la pauta`);
    const sin1 = await pantallaDeEntreno({ rir: '0', semana: 1, web230 });
    const todoSin1 = [sin1.textos.lista, ...Object.values(sin1.textos.ejercicios)].join('\n');
    assert.deepEqual(sin1.errores, [], `${vista}: excepciones en la página`);
    assert.ok(/Llevá cada serie al fallo/.test(todoSin1), `${vista}, semana 1 sin reserva: la calibración de siempre`);
    enChrome += 4;
  }
}

console.log(`✓ reserva clínica: nunca «Al fallo» ni «Subí la carga» (${n} casos${enChrome ? `, ${enChrome} pantallas en Chrome` : ''})`);
