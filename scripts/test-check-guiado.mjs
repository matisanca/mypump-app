#!/usr/bin/env node
/* =============================================================
 * test-check-guiado.mjs — el check guiado (2.3.0) de la web del cliente.
 *
 * Las reglas (`CheckGuiado`, en public/cliente.html) tienen que dar lo mismo que
 * el iPhone (CheckGuiadoTests) y Android (CheckGuiadoTest): se corren TODOS los
 * casos de apps/shared/vectores/check_guiado.json contra el código real, que se
 * extrae del HTML por texto (como test-outbox.mjs).
 *
 * Además:
 *  · lo que sale por la cola al enviar son exactamente las tres ops del vector,
 *    y `checkin` y `peso` llegan al servidor con los mismos parámetros de hoy;
 *  · la op nueva no traba la cola: función inexistente o respuesta FALSE = hecha;
 *  · ningún texto del check dice lo que no puede decir.
 *
 * USO:  node scripts/test-check-guiado.mjs
 * ============================================================= */
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';

const raiz = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const html = fs.readFileSync(path.join(raiz, 'public/cliente.html'), 'utf8');
const V = JSON.parse(fs.readFileSync(path.join(raiz, 'apps/shared/vectores/check_guiado.json'), 'utf8'));

function entre(a, b, nombre) {
  const i = html.indexOf(a), f = html.indexOf(b, i);
  if (i < 0 || f < 0) { console.error(`✗ no encontré ${nombre} en cliente.html`); process.exit(1); }
  return html.slice(i, f + b.length);
}
const metricas = entre('const CHECKIN_METRICAS = [', '\n];', 'CHECKIN_METRICAS');
const reglas = entre('/* ═══ CHECK GUIADO · REGLAS (inicio) ═══', '/* ═══ CHECK GUIADO · REGLAS (fin) ═══ */', 'las reglas del check guiado');
const { CG, METRICAS } = new Function(`${metricas}\n${reglas}\nreturn { CG: CheckGuiado, METRICAS: CHECKIN_METRICAS };`)();

let ok = 0, mal = 0;
const caso = (nombre, fn) => {
  try { fn(); ok++; } catch (e) { mal++; console.log(`  ✗ ${nombre}\n      ${String(e.message).split('\n').slice(0, 6).join('\n      ')}`); }
};
const casoAsinc = async (nombre, fn) => {
  try { await fn(); ok++; } catch (e) { mal++; console.log(`  ✗ ${nombre}\n      ${String(e.message).split('\n').slice(0, 6).join('\n      ')}`); }
};

console.log('\nCheck guiado: reglas contra los vectores compartidos');

for (const c of ['general', 'ciclo']) {
  caso(`catálogo ${c}`, () => assert.deepEqual(CG.opciones(c).map(o => [o.clave, o.etiqueta]), V.catalogos[c]));
}
caso('catalogoDe: ciclo solo con true explícito', () => {
  assert.equal(CG.catalogoDe(true), 'ciclo');
  for (const x of [false, null, undefined, 'true', 1]) assert.equal(CG.catalogoDe(x), 'general');
});
for (const p of CG.PASOS) {
  const de = (tabla, fn) => {
    const esperado = tabla[p];
    if (esperado && typeof esperado === 'object') for (const c of Object.keys(esperado)) assert.equal(fn(p, c), esperado[c], `${p}/${c}`);
    else assert.equal(fn(p), esperado, p);
  };
  caso(`título de ${p}`, () => de(V.titulos, CG.titulo));
  caso(`apoyo de ${p}`, () => de(V.apoyos, CG.apoyo));
  caso(`salida discreta de ${p}`, () => de(V.omitir, CG.omitir));
}
caso('los pasos del vector son los de la web', () => assert.deepEqual(Object.keys(V.titulos), CG.PASOS));
for (const [e, [texto, boton]] of Object.entries(V.tarjeta)) {
  caso(`tarjeta ${e}`, () => { assert.equal(CG.textoTarjeta(e), texto); assert.equal(CG.botonTarjeta(e), boton); });
}
V.pasos.forEach((c, i) => caso(`pasos ${i}`, () => assert.deepEqual(CG.pasos(c.faltanFotos), c.pasos)));
V.alternar.forEach((c, i) => caso(`alternar ${i}`, () => assert.deepEqual(CG.alternar(c.senales, c.clave), c.queda)));
V.normalizar.forEach((c, i) => caso(`normalizar ${i}`, () => assert.deepEqual(CG.normalizar(c.senales, c.catalogo), c.queda)));
V.textoSenales.forEach((c, i) => caso(`textoSenales ${i}`, () => assert.equal(CG.textoSenales(c.senales, c.catalogo), c.texto)));
V.puedeSeguir.forEach((c, i) => caso(`puedeSeguir ${i} (${c.paso})`, () =>
  assert.equal(CG.puedeSeguir(c.paso, CG.borrador(c.borrador), c.fotosHechas), c.puede)));
V.faltaParaEnviar.forEach((c, i) => caso(`faltaParaEnviar ${i}`, () => {
  const b = CG.borrador(c.borrador);
  assert.equal(CG.faltaParaEnviar(b), c.falta);
  assert.equal(CG.pasoQueFalta(b), c.paso);
}));
V.abrir.forEach((c) => caso(`abrir: ${c.caso}`, () => {
  const queda = CG.abrir({ guardado: c.guardado, semana: c.semana, catalogo: c.catalogo, enviado: c.enviado,
    senalesEnviadas: c.senalesEnviadas, catalogoEnviado: c.catalogoEnviado });
  assert.deepEqual(queda, c.queda);
}));
V.retomar.forEach((c, i) => caso(`retomar ${i}`, () => assert.equal(CG.retomar(CG.borrador({ semana: '2026-11-09', paso: c.paso }), c.pasos), c.abre)));
V.estado.forEach((c, i) => caso(`estado ${i}`, () =>
  assert.equal(CG.estado({ enviado: c.enviado, borrador: c.borrador, semana: c.semana, faltanFotos: c.faltanFotos }), c.estado)));

caso('el borrador pasa por JSON sin cambiar (así se guarda en el navegador)', () => {
  const b = CG.borrador(V.payload.borrador);
  assert.deepEqual(CG.borrador(JSON.parse(JSON.stringify(b))), b);
  assert.deepEqual(b, V.payload.borrador);
});
caso('un borrador roto no rompe: queda uno vacío', () => {
  for (const x of [null, 3, 'x', [], { paso: 'otro', valores: 'x', senales: 4, peso: 7, catalogo: 'raro' }]) {
    const b = CG.borrador(x);
    assert.deepEqual({ ...b, semana: '' }, { semana: '', paso: 'peso', peso: '', valores: {}, catalogo: 'general', senales: [], nota: '' });
  }
});
caso('faltan: el mismo texto del check de siempre', () => {
  assert.equal(CG.faltan({}), `Faltan: ${METRICAS.map(m => m.label).join(', ')}`);
  assert.equal(CG.faltan({ energia: 1, descanso: 2, hambre: 3, adherencia: 4 }), null);
});
caso('leerPeso: coma o punto, 30 a 300, un decimal', () => {
  const t = [['78,4', 78.4], ['78.44', 78.4], [' 80 ', 80], ['30', 30], ['300', 300], ['29,9', null], ['300,1', null],
    ['', null], ['  ', null], ['abc', null], ['78kg', null], ['7 8', null], ['1e2', null], ['-80', null], [null, null]];
  for (const [texto, v] of t) assert.equal(CG.leerPeso(texto), v, JSON.stringify(texto));
  assert.equal(CG.AVISO_RANGO, 'Revisá el peso: tiene que estar entre 30 y 300 kg.');
});

console.log('Check guiado: lo que sale por la cola');

const P = V.payload;
caso('al enviar salen exactamente las tres ops del vector, en orden', () =>
  assert.deepEqual(CG.opsDeEnvio(CG.borrador(P.borrador), P.fecha, null), P.ops));
caso('el peso que ya está cargado hoy no se manda de nuevo', () =>
  assert.deepEqual(CG.opsDeEnvio(CG.borrador(P.borrador), P.fecha, 78.4), P.ops.filter(o => o.kind !== 'peso')));
caso('otro peso cargado hoy: sale el nuevo', () =>
  assert.deepEqual(CG.opsDeEnvio(CG.borrador(P.borrador), P.fecha, 79), P.ops));
caso('sin peso: checkin y check_guiado, nada más', () =>
  assert.deepEqual(CG.opsDeEnvio(CG.borrador({ ...P.borrador, peso: '  ' }), P.fecha, null), P.ops.filter(o => o.kind !== 'peso')));
caso('con algo que falta o un peso inválido no sale nada', () => {
  assert.deepEqual(CG.opsDeEnvio(CG.borrador({ ...P.borrador, senales: [] }), P.fecha, null), []);
  assert.deepEqual(CG.opsDeEnvio(CG.borrador({ ...P.borrador, valores: { energia: 4 } }), P.fecha, null), []);
  assert.deepEqual(CG.opsDeEnvio(CG.borrador({ ...P.borrador, peso: '500' }), P.fecha, null), []);
});
caso('checkin y peso no llevan ni un campo más que los de hoy', () => {
  const ops = CG.opsDeEnvio(CG.borrador(P.borrador), P.fecha, null);
  assert.deepEqual(Object.keys(ops[0].payload).sort(), ['datos', 'fecha']);
  assert.deepEqual(Object.keys(ops[0].payload.datos).sort(), ['adherencia', 'descanso', 'energia', 'hambre', 'nota']);
  assert.deepEqual(Object.keys(ops[1].payload).sort(), ['fecha', 'valor']);
});
caso('la RPC de lo marcado', () => {
  const l = CG.rpcGuardar('tok', P.ops[2].payload);
  assert.equal(l.funcion, P.rpc.check_guiado.funcion);
  assert.deepEqual(l.parametros, { p_token: 'tok', ...P.rpc.check_guiado.parametros });
});

// La cola real (el IIFE del Outbox de cliente.html) con un servidor de mentira.
function montarCola(responderGuiado) {
  const i = html.indexOf('const Outbox = (() => {'), f = html.indexOf('})();', i);
  const fuente = html.slice(i, f + 5);
  const store = {};
  const llamadas = [];
  const db = {
    _lastError: null,
    guardarCheckin: async (token, fecha, datos) => { llamadas.push(['mypump_guardar_checkin', { token, fecha, datos }]); return { success: true, data: 'id' }; },
    ingestSalud: async (token, filas) => { llamadas.push(['mypump_ingest_salud', { token, filas }]); return { success: true, data: 1 }; },
    gimnasioRpc: async (fn, params) => { llamadas.push([fn, params]); return responderGuiado(); },
  };
  const ctx = {
    OUTBOX_ENABLED: true, TOKEN: 'tok', DATA: { dia: { id: 'd1' }, rutina: { semana_actual: 1 } }, _sesionId: 's',
    ensureSesionIniciada: async () => 's', navigator: { onLine: true },
    localStorage: { getItem: k => (k in store ? store[k] : null), setItem: (k, v) => { store[k] = String(v); }, removeItem: k => { delete store[k]; } },
    showSaveState() {}, hideSaveToast() {}, console: { warn() {}, log() {}, error() {} },
    setTimeout, clearTimeout, Date, CheckGuiado: CG, hoyLocal: () => P.fecha, window: { mypumpDB: db },
  };
  const Outbox = new Function(...Object.keys(ctx), `${fuente}; return Outbox;`)(...Object.values(ctx));
  Outbox.load();
  return { Outbox, llamadas };
}
const dormir = (ms) => new Promise(r => setTimeout(r, ms));
const encolarTodo = (Outbox) => { for (const op of CG.opsDeEnvio(CG.borrador(P.borrador), P.fecha, null)) Outbox.enqueue(op.kind, op.payload, op.dedupeKey); };

await casoAsinc('las tres ops llegan al servidor: checkin y peso como hoy, y lo marcado por su función', async () => {
  const { Outbox, llamadas } = montarCola(() => ({ ok: true, data: true }));
  encolarTodo(Outbox);
  await dormir(80);
  assert.equal(Outbox.pending(), 0);
  assert.deepEqual(llamadas, [
    ['mypump_guardar_checkin', { token: 'tok', fecha: P.fecha, datos: P.ops[0].payload.datos }],
    ['mypump_ingest_salud', { token: 'tok', filas: [{ fecha: P.fecha, tipo: 'peso_kg', valor: 78.4, fuente: 'manual' }] }],
    [P.rpc.check_guiado.funcion, { p_token: 'tok', ...P.rpc.check_guiado.parametros }],
  ]);
});
for (const [nombre, r] of [
  ['función inexistente (PGRST202)', { ok: false, status: 404, codigo: 'PGRST202', clase: 'permanente' }],
  ['404 sin código', { ok: false, status: 404, codigo: '', clase: 'permanente' }],
  ['respuesta FALSE (palanca apagada en el servidor)', { ok: true, data: false }],
  ['respuesta null', { ok: true, data: null }],
]) {
  await casoAsinc(`${nombre}: hecha, no traba la cola`, async () => {
    const { Outbox, llamadas } = montarCola(() => r);
    encolarTodo(Outbox);
    await dormir(80);
    assert.equal(Outbox.pending(), 0);
    assert.equal(llamadas.filter(l => l[0] === 'mypump_check_guiado_guardar').length, 1, 'una sola llamada, sin reintentos');
  });
}
await casoAsinc('sin red: lo marcado queda en la cola y lo demás ya salió', async () => {
  const { Outbox, llamadas } = montarCola(() => ({ ok: false, status: 0, codigo: 'NETWORK', clase: 'red' }));
  encolarTodo(Outbox);
  await dormir(80);
  assert.equal(Outbox.pending(), 1);
  assert.equal([...Outbox.pendingKeys()][0], `check_guiado_${P.fecha}`);
  assert.deepEqual(llamadas.slice(0, 2).map(l => l[0]), ['mypump_guardar_checkin', 'mypump_ingest_salud']);
});
await casoAsinc('servidor caído (5xx): se reintenta, no se da por hecha', async () => {
  const { Outbox } = montarCola(() => ({ ok: false, status: 503, codigo: '', clase: 'transitorio' }));
  encolarTodo(Outbox);
  await dormir(80);
  assert.equal(Outbox.pending(), 1);
});

console.log('Check guiado: textos');

// Todo lo que el check le dice al alumno: los textos de las reglas y los literales de la pantalla.
const pantalla = entre('/* ═══════ CHECK GUIADO (2.3.0) · modelo y pantalla ═══════', '/* ══════════ ESCENA REVISIÓN (R)', 'la pantalla del check guiado');
const sinComentarios = (src) => src.replace(/\/\*[\s\S]*?\*\//g, ' ').replace(/(^|[^:'"`\\])\/\/[^\n]*/g, '$1 ');
const literales = (src) => [...sinComentarios(src).matchAll(/'((?:[^'\\\n]|\\.)*)'|"((?:[^"\\\n]|\\.)*)"|`((?:[^`\\]|\\.)*)`/g)].map(m => m[1] ?? m[2] ?? m[3] ?? '');
const textos = [
  ...CG.PASOS.flatMap(p => ['general', 'ciclo'].flatMap(c => [CG.titulo(p, c), CG.apoyo(p, c), CG.omitir(p) || ''])),
  ...['general', 'ciclo'].flatMap(c => CG.opciones(c).map(o => o.etiqueta)),
  ...Object.keys(V.tarjeta).flatMap(e => [CG.textoTarjeta(e), CG.botonTarjeta(e)]),
  CG.AVISO_RANGO, CG.faltan({}), ...METRICAS.flatMap(m => [m.label, m.lo, m.hi]),
  ...literales(reglas), ...literales(pantalla),
];
const PROHIBIDO = [/\bIA\b/, /inteligencia artificial/i, /\bcoach\b/i, /entrenador/i, /\bRIR\b/i, /repeticiones en reserva/i];
caso(`ningún texto dice IA, coach, entrenador ni RIR (${textos.length} textos)`, () => {
  assert.ok(textos.length > 80, 'se extrajeron pocos textos: ¿cambió el marcador?');
  for (const t of textos) for (const re of PROHIBIDO) assert.ok(!re.test(t), `«${t.slice(0, 90)}» coincide con ${re}`);
});
caso('la pantalla dice lo que pide la especificación', () => {
  for (const t of ['Check de la semana', 'Enviar mi check', 'Actualizar mi check', 'Listo', 'Mati lo ve antes de tu devolución.',
    'Cerrar', 'Salir', 'Seguir', 'Atrás', 'Paso ', 'Ej: 78,4', 'Escribí acá (opcional)', 'Media de 7 días: ']) {
    assert.ok(sinComentarios(pantalla).includes(t), `falta «${t}»`);
  }
});
caso('los identificadores de prueba son los de las tres plataformas', () => {
  for (const id of ['check-guiado-tarjeta', 'check-guiado-abrir', 'cg-cerrar', 'cg-avance', 'cg-atras', 'cg-seguir', 'cg-omitir',
    'cg-titulo', 'cg-peso', 'cg-escala-${m.k}-${n}', 'cg-senal-${o.clave}', 'cg-nota', 'cg-fila-${p}', 'cg-enviar', 'cg-falta',
    'cg-listo', 'cg-cerrar-listo']) {
    assert.ok(pantalla.includes(id), `falta ${id}`);
  }
});
caso('apagada, la pantalla de hoy: la palanca sin la clave no prende nada', () => {
  assert.ok(html.includes('_cgAplicarPalanca(cfg.check_guiado === true);'));
  assert.ok(html.includes("if (checkGuiadoPrendido()) return _cgRenderTarjeta(el);"));
  assert.ok(html.includes('if (checkGuiadoPrendido()) loadCheckGuiado()'));
  assert.ok(/async function loadCheckGuiado\(\) \{\n  if \(!checkGuiadoPrendido\(\)/.test(html), 'la lectura nueva solo con la palanca prendida');
});

console.log(`\n${mal ? '✗' : '✓'} check guiado: ${ok} ok, ${mal} mal\n`);
process.exit(mal ? 1 : 0);
