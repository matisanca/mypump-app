#!/usr/bin/env node
/* =============================================================
   vectores-entreno.mjs — el motor de Entreno: la web es la fuente de verdad

   Corre las funciones REALES de public/cliente.html de origin/main con dobles mínimos del DOM, de la
   cola y de la base, y escribe {entrada, salida}. Los tests de la nativa (EntrenoTests.swift; JUnit en
   Android) leen los mismos archivos y exigen igualdad total.

   Qué cubre (ver docs/NATIVA_PARIDAD.md):
   - normalizar: normalizarRutina (ENT-04) y getDayNum.
   - textos: getDayShortName (ENT-01) y getNombreBloque (ENT-05).
   - ejercicios: getVariantesEntry, esSinPeso y exNoKg (SER-07, ENT-13); _repsSug (SER-01).
   - campos: normalizarCampoSerie (SER-04) y rirDeSet (SER-02).
   - historial: _ultimaSerieRef, suggestedKg, suggestedReps, lastSessionStr, prevSessionStr y _recordKg
     (SER-01, SER-07, SER-08), con un "ahora" fijo; kgHeredable (SER-03).
   - filas: renderSetRow (placeholders, one-tap, pista de calibración, botón habilitado).
   - confirmar: confirmarSerie entero (one-tap, kg heredado, topes y preguntas, día cerrado, auto-completo y
     el siguiente pendiente) con writeSet y writeExerciseStatus reales sobre una cola de mentira.
   - acciones: los handlers reales de bindTrainEvents (marcar completo, terminé, reabrir, lápiz, variante,
     abrir la card, volver al original) y el selector de RIR (SER-02, SER-06, SER-15).
   - resumen: los textos de los dos modales de "Cerrar sesión de hoy" (series, reps, volumen, minutos y
     hasta 3 pendientes; SES-06).
   - restaurar: loadRegistrosCarga y loadExerciseStates (SER-07: la variante vuelve de `notas`).
   - poda: pruneExerciseSwaps (SER-12).
   - comentarios: rebuildComentarioIndexes, totalUnreadComentarios, getUnreadDia y fmtComentarioFecha (SES-08).
   - tiempo: fmtTime, fmtCrono y minutosSesion (SES-03).
   - descanso: startRest, restTick, stopRest, restoreRest y los botones −15/+15/Saltar (SES-04).
   - semana: el banner de progresión y la calibración (ENT-07/08), y los textos de avanzar semana, bloque
     nuevo y día completado (ENT-14/15/17).

   Corpus público (se commitea): fixtures de las cuentas de prueba, la demo y casos armados a mano.
   Privado (nunca se commitea): las estructuras de los planes activos reales y los nombres registrados, si
   están en ~/Developer/nativa-evidencia/privado/estructuras/.

   Fechas: TZ fija (America/Argentina/Buenos_Aires) y un "ahora" fijo por caso (Date de mentira).

   Salidas: apps/shared/vectores/entreno.json y privado/vectores/entreno.json
   Uso: node scripts/nativa/vectores-entreno.mjs
   ============================================================= */

import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const RAIZ = path.join(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const PRIVADO = path.join(os.homedir(), 'Developer', 'nativa-evidencia', 'privado');
const REF = process.env.VECTORES_REF || 'origin/main';

process.env.TZ = 'America/Argentina/Buenos_Aires';
const HTML = execFileSync('git', ['show', `${REF}:public/cliente.html`], { cwd: RAIZ, maxBuffer: 64 * 1024 * 1024 }).toString();
const commit = execFileSync('git', ['rev-parse', '--short', REF], { cwd: RAIZ }).toString().trim();
const leer = (p) => JSON.parse(fs.readFileSync(p, 'utf8'));
const copia = (x) => (x === undefined ? null : JSON.parse(JSON.stringify(x)));

// ── Extracción (mismo método que generar-vectores.mjs) ──────────────
function cierre(i, abre, cierra) {
  let prof = 0;
  for (let k = i; k < HTML.length; k++) {
    if (HTML[k] === abre) prof++;
    else if (HTML[k] === cierra && --prof === 0) return k;
  }
  throw new Error(`sin cierre desde ${i}`);
}
/** `function <nombre>(` (con su `async`, si lo tiene) hasta la llave que la cierra. */
function extraer(nombre) {
  let i = HTML.indexOf(`function ${nombre}(`);
  if (i < 0) throw new Error(`no encontré function ${nombre}( en cliente.html@${REF}`);
  if (HTML.slice(i - 6, i) === 'async ') i -= 6;
  return HTML.slice(i, cierre(HTML.indexOf('{', HTML.indexOf(')', i)), '{', '}') + 1);
}
/** `const <NOMBRE> = …;`: un array u objeto literal completo, o una sola línea. */
function extraerConst(nombre) {
  const i = HTML.indexOf(`const ${nombre} = `);
  if (i < 0) throw new Error(`no encontré const ${nombre}`);
  const j = i + `const ${nombre} = `.length;
  if (HTML[j] === '[' || HTML[j] === '{') return HTML.slice(i, cierre(j, HTML[j], HTML[j] === '[' ? ']' : '}') + 1) + ';';
  return HTML.slice(i, HTML.indexOf('\n', i));
}
/** Un tramo literal del código (para lo que no es una función con nombre). */
function tramo(desde, hasta) {
  const i = HTML.indexOf(desde);
  const k = HTML.indexOf(hasta, i);
  if (i < 0 || k < 0) throw new Error(`no encontré el tramo ${desde} … ${hasta}`);
  return HTML.slice(i, k + hasta.length);
}

// ── El mundo: las funciones reales con dobles ───────────────────────
// Un reloj de mentira: `new Date()` y `Date.now()` dan RELOJ.ms; con argumentos es el Date de siempre.
const RELOJ = { ms: Date.UTC(2026, 9, 14, 18, 0, 0) };   // 14-oct-2026 15:00 en Buenos Aires
const DateReal = Date;
class Reloj extends DateReal {
  constructor(...a) { if (a.length === 0) super(RELOJ.ms); else super(...a); }
  static now() { return RELOJ.ms; }
}
// Lo que cambia caso a caso: el DOM de mentira, la base, las respuestas de los modales y lo que se registró.
let CTX = {};
function nuevoCtx(extra = {}) {
  CTX = {
    ls: {}, cola: [], modales: [], respuestas: [], timeouts: [], alertas: [], llamadas: [],
    // Los dobles que la web usa con `.then` o `.catch` tienen que devolver una promesa.
    ensureSesionIniciada: async () => null, loadHistorico: async () => {}, marcarLeidosEjercicio: async () => {},
    ...extra,
  };
  return CTX;
}
const almacen = new Proxy({}, {
  get: (_, k) => ({
    getItem: (c) => (c in CTX.ls ? CTX.ls[c] : null),
    setItem: (c, v) => { CTX.ls[c] = String(v); },
    removeItem: (c) => { delete CTX.ls[c]; },
  })[k],
  ownKeys: () => Object.keys(CTX.ls),
  getOwnPropertyDescriptor: (_, k) => (k in CTX.ls ? { enumerable: true, configurable: true, value: CTX.ls[k] } : undefined),
});
const libres = {
  $: (s) => (CTX.$ ? CTX.$(s) : null),
  $$: (s) => (CTX.$$ ? CTX.$$(s) : []),
  document: { getElementById: (id) => (CTX.porId ? CTX.porId(id) : null), querySelector: () => null, hidden: false },
  window: { get mypumpDB() { return CTX.db; }, scrollTo() {} },
  MyPump: { ui: { showConfirmModal: async (o) => { CTX.modales.push(copia(o)); return CTX.respuestas.length ? CTX.respuestas.shift() : false; } } },
  Outbox: {
    enqueue: (kind, payload, key) => { CTX.cola.push({ kind, key, payload: copia(payload) }); },
    flush: async () => { CTX.llamadas.push('flush'); },
    pending: () => 0, flushSoon() {},
  },
  localStorage: almacen,
  location: { reload: () => { CTX.llamadas.push('reload'); } },
  setTimeout: (f, ms) => { CTX.timeouts.push(ms); return 1; },
  setInterval: () => 7, clearInterval: () => {},
  Date: Reloj,
  console: { log() {}, warn() {}, error() {} },
  navigator: { vibrate() {} },
  alert: (m) => { CTX.alertas.push(m); },
};
const CONSTANTES = ['SESION_MAX_H', 'DESCANSO_POR_DEFECTO', 'VARIANTES_EJ', '_SIN_PESO_RE', '_CON_CARGA_RE', 'LIMITES_SERIE', '_comKey'];
/** Un ámbito con las funciones `reales` de la web, `dobles` que llaman a CTX[nombre] y código `extra` (que
 *  exporta las funciones de `exportar`). */
function construir(reales, dobles = [], extra = '', exportar = []) {
  const src = [
    'let DATA = null, RUTINA_ID = null, _sesionId = null, _sesionIniciada = false, _diaFinalizado = false, _sessionStart = null, _startedByButton = false;',
    "const TOKEN = 'tok';",
    'const STATE = {};',
    'const _histPromises = {};',
    ...CONSTANTES.map(extraerConst),
    ...dobles.map((n) => `function ${n}(...a) { __ctx().llamadas.push(['${n}', ...a]); return __ctx().${n} ? __ctx().${n}(...a) : undefined; }`),
    ...reales.map(extraer),
    extra,
    `return {
      poner(v) {
        if ('DATA' in v) DATA = v.DATA;
        if ('RUTINA_ID' in v) RUTINA_ID = v.RUTINA_ID;
        if ('_sesionId' in v) _sesionId = v._sesionId;
        if ('_sesionIniciada' in v) _sesionIniciada = v._sesionIniciada;
        if ('_diaFinalizado' in v) _diaFinalizado = v._diaFinalizado;
        if ('_sessionStart' in v) _sessionStart = v._sessionStart;
        if ('_startedByButton' in v) _startedByButton = v._startedByButton;
        for (const k of Object.keys(STATE)) delete STATE[k];
        Object.assign(STATE, v.STATE || {});
        for (const k of Object.keys(_histPromises)) delete _histPromises[k];
      },
      leer() { return { DATA, RUTINA_ID, _sesionId, _sesionIniciada, _diaFinalizado, _sessionStart, _startedByButton, STATE }; },
      ${[...reales, ...exportar].join(',\n      ')}
    };`,
  ].join('\n');
  const nombres = Object.keys(libres);
  return new Function('__ctx', ...nombres, src)(() => CTX, ...nombres.map((n) => libres[n]));
}

// ── Corpus ───────────────────────────────────────────────────────────
const fixtures = path.join(RAIZ, 'apps/shared/fixtures');
const cuentas = fs.readdirSync(fixtures).filter((c) => fs.existsSync(path.join(fixtures, c, 'get_rutina_activa.json')));
const rutinasPublicas = cuentas.map((c) => leer(path.join(fixtures, c, 'get_rutina_activa.json'))[0].estructura);
rutinasPublicas.push(leer(path.join(RAIZ, 'apps/shared/demo/rutina.json')));
const ARCHIVOS_PRIVADOS = ['estructuras/rutinas.json', 'estructuras/rutinas-en-cola.json'];
const rutinasPrivadas = fs.existsSync(path.join(PRIVADO, ARCHIVOS_PRIVADOS[0]))
  ? ARCHIVOS_PRIVADOS.flatMap((a) => leer(path.join(PRIVADO, a)))
  : [];
const nombresRegistrados = fs.existsSync(path.join(PRIVADO, 'estructuras/nombres-registrados.json'))
  ? leer(path.join(PRIVADO, 'estructuras/nombres-registrados.json')) : [];

const ejerciciosDe = (rutinas) => rutinas.flatMap((r) => ((r && r.dias) || []).flatMap((d) => ((d && d.bloques) || []).filter(Boolean)
  .flatMap((b) => (b.ejercicios || []).filter((e) => e && typeof e === 'object'))));
const unicos = (xs) => [...new Set(xs)];

// Planes armados a mano con lo que la base real hoy no trae. Solo formas que el decodificador de la nativa
// representa igual que JS: ver `excepciones` al final (bloques o días que no son objetos, descansos con
// decimales, semanas_total como texto, un día sin la clave `bloques`).
const ej = (id, extra = {}) => ({ id, nombre: `Ejercicio ${id}`, tipo: 'compuesto', series: 3, reps: '8-10', descanso_segundos: 90, ...extra });
const PLANES_SINTETICOS = [
  null,
  {},
  { dias: [] },
  { dias: 'ocho' },
  { dias: {} },
  { semanas_total: 0, dias: [{ bloques: [{ ejercicios: [ej('a', { descanso_segundos: 0, series: 0 })] }] }] },
  { semanas_total: 16, dias: [{ id: '', nombre: '', bloques: [{ titulo: 'B', ejercicios: [
    ej('a'), ej('b', { descanso_segundos: null }), ej('c', { descanso_segundos: -30 }), ej('d', { descanso_segundos: '90' }),
    ej('e', { descanso_segundos: ' 60 ' }), ej('f', { descanso_segundos: 'noventa' }), ej('g', { descanso_segundos: 45 }),
    ej('h', { series: null }), ej('i', { series: -2 }), ej('j', { series: '3' }), ej('k', { series: 4 }), ej('l', { series: '0' }),
    { id: 'm', nombre: 'Sin descanso ni series' },
  ] }] }] },
  { semanas_total: -1, dias: [{ id: 'a', nombre: 'Lunes', bloques: [] }, { id: 'b', bloques: [{ ejercicios: [] }, { titulo: 'X' }] }] },
  { dias: [{ id: 'lun', nombre: 'PUSH', bloques: [{ titulo: 'A', ejercicios: [ej('x')] }] }, { id: 'mar', nombre: 'Descanso activo', bloques: [] },
    { nombre: 'Sin id', bloques: [{ subtitulo: 'Core', ejercicios: [ej('y', { tipo: 'core', progresion: [{ semana: 1, series: 3, reps: '12', rir: '1' }] })] }] }] },
  { semanas_total: 12, semana_offset: 12, dias: [{ id: 'b2d1', n: 3, nombre: 'Torso', bloques: [{ ejercicios: [ej('z')] }] }, { id: 'b2d2', nombre: 'Pierna', bloques: [{ ejercicios: [ej('w')] }] }] },
  { semanas_total: 4, dias: [{ id: 'd1', nombre: 'Empuje', bloques: [{ titulo: 'BLOQUE 0 — CALENTAMIENTO', ejercicios: [
    ej('cal', { tipo: 'calentamiento', progresion: [{ semana: 1, series: 2, reps: '12', rir: '3' }, { semana: 2, series: 2, reps: '10', rir: '2' }, { semana: 3, series: 3, reps: '10', rir: '2' }] }),
  ] }, { titulo: 'BLOQUE 1 — PECHO', ejercicios: [
    ej('pre', { progresion: [{ semana: 1, series: 3, reps: '10', rir: '2' }, { semana: 2, series: 3, reps: '10', rir: '2' }, { semana: 3, series: 3, reps: '8', rir: '1' }] }),
  ] }] }] },
];

// ── A. normalizarRutina y getDayNum ─────────────────────────────────
const W = construir(['normalizarRutina', 'getDayNum', 'getDayShortName', 'getNombreBloque', 'getProgresionActual', 'computeProgresionNota']);
function normalizado(est) {
  const r = W.normalizarRutina(est);
  const dias = Array.isArray(r.est.dias) && r.est.dias.length && r.est.dias.every((d) => Array.isArray(d.bloques)) ? r.est.dias : null;
  return {
    usable: r.usable, problemas: r.problemas,
    semanasTotal: dias ? r.est.semanas_total : null,
    dias: dias && dias.map((d) => ({
      id: d.id, nombre: d.nombre, numero: String(W.getDayNum(d, dias)),
      bloques: d.bloques.map((b) => b.ejercicios.map((x) => [x.descanso_segundos, x.series])),
    })),
  };
}
const vNormalizar = (planes, conRef) => planes.map((est, i) => ({ ...(conRef ? { ref: i } : { est: copia(est) }), ...normalizado(est) }));

// ── B. Textos de día y de bloque ─────────────────────────────────────
const DIAS_DIFICILES = ['TIRÓN A — ANCHO', 'Empuje A', 'FULLBODY', 'pierna/glúteo', '  ', '', 'Día 1', 'ÑANDÚ', 'straße', 'ß-tag', 'İstanbul',
  '🔥 PUSH', 'éxito total', 'A—B', 'A–B', 'A-B', 'A/B', 'Tab\tSep', ' Lead', 'X Y', 'Ǆemal', 'ǅungla', 'ŉ', '﻿BOM', 'ÉPICO',
  'superSERIE', 'x', 'TORSO + BRAZOS', 'Día 3 (comodín)', 'ΟΔΟΣ', 'ΣΑΣ Α', 'ΟΔΌΣ.', 'ǈubljana', 'ﬁesta', 'İİ', 'ÅNGSTRÖM', 'ⅷ día'];
const BLOQUES_DIFICILES = [
  { titulo: 'BLOQUE 0 — CALENTAMIENTO' }, { titulo: 'bloque 1 - espalda' }, { titulo: 'Bloque 12–Pierna' }, { titulo: 'BLOQUE 2' },
  { titulo: 'BLOQUE X — Y' }, { titulo: 'Bloque 3 —   ' }, { titulo: 'BLOQUE 4 — A\nB' }, { subtitulo: 'Calentamiento' },
  { titulo: 'BLOQUE 1 — X', subtitulo: '' }, { titulo: '' }, {}, { titulo: 'bloque 1 — x' }, { titulo: 'BLOQUE 1 — straße' },
  { titulo: 'BLOQUE 5 —— DOBLE' }, { titulo: 'BLOQUE 6 — biserie: press + aperturas' }, { titulo: 'Bloque7—sin espacios' },
  { titulo: 'BLOQUES 1 — X' }, { titulo: '  BLOQUE 1 — X' }, { subtitulo: 'Hombro / Tríceps', titulo: 'BLOQUE 2' },
  { titulo: 'BLOQUE 1 — X\u0085' }, { titulo: 'BLOQUE 1 — X\ufeff' }, { titulo: 'BLOQUE 1 — \u00a0Y\u2003' }, { titulo: 'BLOQUE 1 — \u0085Z' },
];
function vTextos(rutinas, extraDias, extraBloques) {
  const nombresDia = unicos([...extraDias, ...rutinas.flatMap((r) => ((r && r.dias) || []).map((d) => d && d.nombre)).filter((n) => typeof n === 'string')]);
  const bloques = [...extraBloques, ...rutinas.flatMap((r) => ((r && r.dias) || []).flatMap((d) => ((d && d.bloques) || []).filter(Boolean)
    .map((b) => ({ titulo: b.titulo, subtitulo: b.subtitulo }))))];
  const vistos = new Set();
  return {
    dias: nombresDia.map((nombre) => ({ nombre, corto: W.getDayShortName(nombre) })).concat([{ nombre: null, corto: W.getDayShortName(null) }]),
    bloques: bloques.filter((b) => { const k = JSON.stringify(b); if (vistos.has(k)) return false; vistos.add(k); return true; })
      .map((b) => ({ ...b, nombre: W.getNombreBloque(b) })),
  };
}

// ── C. Ejercicio: variantes, sin peso y reps sugeridas ───────────────
const WE = construir(['getVariantesEntry', 'getVariantesEj', 'esSinPeso', 'exNoKg', '_repsSug', 'normalizarCampoSerie', 'rirDeSet']);
const NOMBRES_DIFICILES = ['Rueda abdominal', 'RUEDA ABDOMINAL', 'Ab wheel', 'Rollout con ab wheel (core anterior)', 'Roller abdominal',
  'Extensión de tríceps en polea', 'Tríceps en polea con soga', 'TRICEPS EN CABLE', 'TRÍCEPS EN CABLE', 'Pushdown en polea', 'Jalón de tríceps en polea',
  'Polea alta tríceps', 'Jalón al pecho', 'JALON A LA NUCA', 'Jalón a la nuca', 'Pulldown', 'Dorsalera', 'Remo en polea', 'Remo gironda', 'REMO CABLE',
  'Curl en polea', 'Polea curl', 'Curl  de bíceps en cable', 'Crunch en máquina', 'Crunch abdominal', 'CRUNCH', 'Plancha', 'Plancha con disco',
  'Planchas', 'Flexiones de brazo', 'Flexión de brazo con lastre', 'Flexion de brazos', 'Elevación de piernas', 'Elevaciones de piernas',
  'Mountain climber', 'Mountainclimber', 'Hollow hold', 'Lagartijas', 'Abdominales', 'Abdominal', 'Crunch en polea alta', 'Press banca',
  'Curl con barras', 'Crunch con BARRA', 'Pesa rusa', 'Plancha con pesas', 'Plancha pesada', 'Crunch en MÁQUINA', 'Crunch en MAQUINA',
  'Swing con Kettlebell', 'Crunch con Kettlebell', 'Plancha ſmith', 'Plancha smith', 'Plancha SMITH', 'Crunch multipower',
  'Crunch en banco declinado con disco', 'Crunch en banco declinado', 'Flexión de brazos', 'Flexión de brazos', 'ELEVACIÓN DE PIERNAS',
  'jalón al pecho con agarre neutro', 'Remo en polea baja', 'Curl en polea a una mano', 'Tríceps polea', 'tricepspolea', '', 'Hollow', 'hollowbody',
  'Plancha lateral con peso', 'Plancha con carga', 'Remo  en  polea', 'Remo\ten polea', 'Remo en polea', 'Jalón al pecho'];
const TIPOS = ['compuesto', 'aislamiento', 'core', 'cardio', 'calentamiento', undefined];
function vEjercicios(ejercicios, extraNombres) {
  const pares = new Map();
  const sumar = (nombre, tipo) => { const k = JSON.stringify([nombre, tipo ?? null]); if (!pares.has(k)) pares.set(k, { nombre, tipo }); };
  for (const e of ejercicios) if (typeof e.nombre === 'string') sumar(e.nombre, e.tipo);
  for (const n of extraNombres) for (const t of [undefined, 'calentamiento']) sumar(n, t);
  for (const t of TIPOS) sumar('Plancha', t);
  return [...pares.values()].map(({ nombre, tipo }) => {
    const ex = { nombre, tipo };
    const v = WE.getVariantesEntry(ex);
    return { nombre, tipo: tipo ?? null, variantes: v ? { etiqueta: v.label, ops: v.ops, sinPeso: v.sinPeso === true } : null,
      sinPeso: WE.esSinPeso(ex), sinKg: WE.exNoKg(ex) };
  });
}
const REPS_DIFICILES = [null, '', 'AMRAP', 'amrap', 'Amrap 10', 'máx', 'MÁX', 'Max', 'MAX', 'max. seg', 'Máx. reps', '∞', '8-10', '10 min',
  '12/15/20', '20-15', '3x10', '١٢', '12abc', 'abc', '0', '007', '99999999999999999999', ' 8 ', '12 c/lado', '30 s / 30 s',
  'rutina completa', '—', '10-12 (al fallo)', 'mAx', 'MAXIMO', 'máximo', 'maximo 12'];
function vReps(ejercicios, extra) {
  const todos = unicos([...extra, ...ejercicios.flatMap((e) => [...(Array.isArray(e.progresion) ? e.progresion : []).map((p) => p && p.reps), e.reps])
    .filter((r) => r === null || typeof r === 'string' || typeof r === 'number')]);
  return todos.map((reps) => ({ reps, sug: WE._repsSug(reps) }));
}
const CAMPOS = [['kg', '62,5'], ['kg', '6a2.5kg'], ['kg', '62.5.5'], ['kg', ',5'], ['kg', '.'], ['kg', ''], ['kg', '1,2,3'], ['kg', '١٢'],
  ['kg', '  80 '], ['kg', '80,'], ['kg', '0'], ['kg', '00.50'], ['kg', '1e3'], ['kg', '-5'], ['kg', '+5'], ['kg', '62,5,5'], ['kg', '..5'], ['kg', null],
  ['reps', '12,'], ['reps', '1 2'], ['reps', 'abc'], ['reps', ''], ['reps', '٣'], ['reps', '007'], ['reps', '12.5'], ['reps', null],
  ['rir', 'x'], ['rir', '0'], ['otro', ' a,b '], ['otro', null]];
const RIRS = ['', null, '0', '3', ' 2', '2.7', '-1', 'x', '0x1', '08', '5abc', '  ', '٣', '5', ' 4', '+2', '9999999999999999999999'];

// ── D. Historial: sugeridos, récord y "última vez" ───────────────────
const WH = construir(['fechaLocalDe', '_varianteActiva', '_ultimaSerieRef', 'suggestedKg', 'kgHeredable', 'suggestedReps', 'lastSessionStr',
  'prevSessionStr', '_recordKg', 'getVariantesEntry', 'getVariantesEj', 'esSinPeso', 'exNoKg']);
const AHORA = RELOJ.ms;
const isoHace = (horas) => new DateReal(AHORA - horas * 3600e3).toISOString().replace('Z', '+00:00');
const fila = (horas, serie, peso, reps, rir, notas) => ({ clave: 'x', registrado_en: isoHace(horas), peso_kg: peso, reps_realizadas: reps, rir_real: rir,
  serie_numero: serie, notas, ejercicio_nombre: 'X' });
// Sesiones a distintas distancias del ahora. 14-oct 15:00 local: "hace 15,5 h" son las 23:30 del 13 (ayer local, hoy en UTC).
const HISTORIALES = [
  [],
  [fila(26, 1, 80, 10, 2, null), fila(26.1, 2, 82.5, 8, 1, null), fila(26.2, 3, 82.5, 7, 0, null)],
  [fila(2, 1, 85, 9, null, null), fila(2.1, 2, 85, 8, null, null), fila(50, 1, 80, 10, 2, null), fila(50.1, 2, 82.5, 8, 1, null)],
  [fila(15.5, 1, 40, 12, 1, null), fila(15.6, 2, 42.5, 10, 0, null), fila(15.7, 3, 0, 10, 0, null)],
  [fila(70, 1, 17.5, 12, 1, 'Soga'), fila(70.1, 2, 17.5, 11, 1, 'Soga'), fila(70.2, 1, 25, 10, 2, 'Barra'), fila(170, 1, 20, 12, 1, null), fila(170.1, 2, 22.5, 10, 0, null)],
  [fila(150, 2, null, 10, null, null), fila(150.1, 1, 0, 12, 1, null), fila(300, 1, 0, 15, null, null)],
  [fila(330, 1, 60, 0, 1, null), fila(330.1, 2, 62.5, null, 0, 'Prono'), fila(340, 1, 60, 8, 3, 'Neutro')],
  [fila(9000, 1, 100, 5, 0, null), fila(9000.1, 2, 100.25, 5, 0, null), fila(9000.2, 3, 1e-7, 5, 0, null)],
  [fila(170, 1, 50, 10, 1, null), fila(170.1, null, 55, 8, 1, null), fila(171, 3, 57.5, 6, 0, null)],
  [fila(0.5, 1, 30, 10, 1, 'Rodillas extendidas'), fila(0.6, 2, 30, 9, 1, null), fila(24 * 13, 1, 0, 8, 2, 'Rodillas flexionadas'), fila(24 * 14 + 2, 1, 0, 6, null, null)],
  [fila(24 * 7 - 1, 1, 70, 10, 1, null), fila(24 * 7 + 20, 2, 72, 9, 1, '')],
  [fila(30, 1, 90, 0, 2, null), fila(30.1, 2, 85, 6, 1, null), fila(400, 1, 95, 0, null, 'Soga')],
];
const EJ_HIST = [
  { id: 'tri-d1-0', nombre: 'Extensión de tríceps en polea', tipo: 'aislamiento' },
  { id: 'jal-d1-1', nombre: 'Jalón al pecho', tipo: 'compuesto' },
  { id: 'rue-d1-2', nombre: 'Rueda abdominal', tipo: 'core' },
  { id: 'pre-d1-3', nombre: 'Press banca', tipo: 'compuesto' },
  { id: 'pla-d1-4', nombre: 'Plancha', tipo: 'core' },
  { id: 'cal-d1-5', nombre: 'Movilidad de hombros', tipo: 'calentamiento' },
];
function vHistorial(ejercicios, historiales, series = 4) {
  const casos = [];
  for (const ex of ejercicios) {
    const ops = WH.getVariantesEj(ex);
    const variantes = ops ? [undefined, ops[0], ops[1], 'Otra'] : [undefined, 'Soga'];
    for (const [hi, h] of historiales.entries()) {
      for (const variante of variantes) {
        for (let idx = 0; idx < series; idx++) {
          WH.poner({ DATA: { dia: { id: 'd1', bloques: [{ ejercicios: [ex] }] }, historico_por_ejercicio: { [ex.id]: h }, rutina: { semana_actual: 1 } },
            STATE: { session: { [ex.id]: { sets: [], variante } } } });
          const { v, esDefault } = WH._varianteActiva(ex.id);
          const ref = WH._ultimaSerieRef(ex.id, idx, v, esDefault);
          const prev = WH.prevSessionStr(ex.id);
          casos.push({ ex: ejercicios.indexOf(ex), h: hi, variante: variante ?? null, idx,
            ref: ref ? h.indexOf(ref) : null, kg: WH.suggestedKg(ex.id, idx), reps: WH.suggestedReps(ex.id, idx),
            record: WH.lastSessionStr(ex.id), recordKg: WH._recordKg(ex.id), ultimaVez: prev });
        }
      }
    }
  }
  return casos;
}
// kgHeredable: la serie confirmada más cercana hacia atrás con kg > 0, si no la primera hacia adelante.
const SERIES_HER = [
  [], [{ kg: '80', confirmed: true }, { kg: '', confirmed: false }, { kg: '', confirmed: false }],
  [{ kg: '80', confirmed: true }, { kg: '82.5', confirmed: true }, { kg: '', confirmed: false }],
  [{ kg: '0', confirmed: true }, { kg: '', confirmed: false }, { kg: '60', confirmed: true }],
  [{ kg: '70', confirmed: false }, { kg: '', confirmed: false }], [{ kg: 'abc', confirmed: true }, { kg: '5abc', confirmed: true }, { kg: '', confirmed: false }],
  [{ kg: '', confirmed: false }, { kg: '-5', confirmed: true }, { kg: '.5', confirmed: true }, { kg: '', confirmed: false }],
  [{ kg: '62,5', confirmed: true }, { kg: '', confirmed: false }],
];
function vHeredable() {
  const casos = [];
  for (const [si, sets] of SERIES_HER.entries()) for (let idx = 0; idx < Math.max(1, sets.length) + 1; idx++) {
    WH.poner({ DATA: { dia: { bloques: [] } }, STATE: { session: { e: { sets } } } });
    casos.push({ series: si, idx, kg: WH.kgHeredable('e', idx) });
  }
  return { series: SERIES_HER, casos };
}

// ── E. La fila de una serie (renderSetRow) ───────────────────────────
const WF = construir(['renderSetRow', 'fechaLocalDe', '_varianteActiva', '_ultimaSerieRef', 'suggestedKg', 'kgHeredable', 'suggestedReps',
  'getProgresionActual', '_repsSug', 'getVariantesEntry', 'getVariantesEj', 'esSinPeso', 'exNoKg'], [], "const ICONS = { edit: '<i-edit>', check: '<i-check>' };");
const sinEtiquetas = (s) => s.replace(/<b>/g, '«').replace(/<\/b>/g, '»').replace(/<[^>]+>/g, '');
function leerFila(html) {
  const inputs = [...html.matchAll(/<input class="set-input"[^>]*>/g)].map((m) => m[0]);
  const atr = (s, a) => { const m = s.match(new RegExp(`${a}="([^"]*)"`)); return m ? m[1] : null; };
  const rir = html.match(/<button class="rir-btn"[^>]*>([\s\S]*?)<\/button>/)[1];
  const boton = html.match(/<button class="set-confirm[^"]*"[^>]*>/)[0];
  const pista = html.match(/<div class="set-sug-hint" data-sugconfirm[^>]*>([\s\S]*?)<\/div>/);
  const calib = html.match(/<div class="set-sug-hint is-calib">([\s\S]*?)<\/div>/);
  const clase = html.match(/<div class="(set-row[^"]*)"/)[1];
  return {
    clase, phReps: atr(inputs[0], 'placeholder'), reps: atr(inputs[0], 'value'), repsSoloLectura: /readonly/.test(inputs[0]),
    phKg: atr(inputs[1], 'placeholder'), kg: atr(inputs[1], 'value'), kgSoloLectura: /readonly/.test(inputs[1]),
    rir: sinEtiquetas(rir), editar: /is-edit/.test(boton), deshabilitado: /disabled/.test(boton), titulo: atr(boton, 'title'),
    pista: pista ? sinEtiquetas(pista[1]) : null, calibracion: calib ? sinEtiquetas(calib[1]) : null,
  };
}
// Ejercicios del plan para las filas: con progresión numérica, AMRAP, sin peso, calentamiento y campos viejos.
const EJ_FILA = [
  { id: 'tri-d1-0', nombre: 'Extensión de tríceps en polea', tipo: 'aislamiento', descanso_segundos: 90, progresion: [{ semana: 1, series: 3, reps: '10-12', rir: '1' }] },
  { id: 'pre-d1-1', nombre: 'Press banca', tipo: 'compuesto', descanso_segundos: 150, progresion: [{ semana: 1, series: 4, reps: '8', rir: '0 (al fallo)' }] },
  { id: 'dom-d1-2', nombre: 'Dominadas', tipo: 'compuesto', descanso_segundos: 120, progresion: [{ semana: 1, series: 3, reps: 'AMRAP', rir: null }] },
  { id: 'rue-d1-3', nombre: 'Rueda abdominal', tipo: 'core', descanso_segundos: 60, progresion: [{ semana: 1, series: 3, reps: '12-15', rir: null }] },
  { id: 'cal-d1-4', nombre: 'Movilidad de hombros', tipo: 'calentamiento', descanso_segundos: 30, series: 2, reps: '10' },
  { id: 'cin-d1-5', nombre: 'Cinta 10 min', tipo: 'cardio', descanso_segundos: 90, progresion: [{ semana: 1, series: null, reps: '10 min', rir: null }] },
  { id: 'vie-d1-6', nombre: 'Curl con barra Z', tipo: 'aislamiento', descanso_segundos: 90, series: 3, reps: '10-12' },
];
const ESTADOS_SERIE = [
  [{ reps: '', kg: '', rir: '', confirmed: false }, { reps: '', kg: '', rir: '', confirmed: false }, { reps: '', kg: '', rir: '', confirmed: false }],
  [{ reps: '10', kg: '80', rir: '2', confirmed: true }, { reps: '', kg: '', rir: '', confirmed: false }, { reps: '', kg: '', rir: '', confirmed: false }],
  [{ reps: '10', kg: '80', rir: '', confirmed: true }, { reps: '9', kg: '', rir: '0', confirmed: false }, { reps: '', kg: '', rir: '', confirmed: false }],
  [{ reps: '', kg: '75', rir: '', confirmed: false }, { reps: '', kg: '', rir: '', confirmed: false }],
  [{ reps: '12', kg: '0', rir: '', confirmed: true }, { reps: '', kg: '', rir: '', confirmed: false }],
  [{ reps: '10', kg: '62.5', rir: '1', confirmed: true }, { reps: '10', kg: '62.5', rir: '1', confirmed: true }, { reps: '8', kg: '62.5', rir: '0', confirmed: true }],
];
function vFilas(ejercicios, historiales, estados = ESTADOS_SERIE.map((_, i) => i)) {
  const casos = [];
  for (const [ei, ex] of ejercicios.entries()) {
    for (const efectivo of [ex, { ...ex, nombre: 'Plancha' }, { ...ex, nombre: 'Jalón al pecho' }].filter((e, k) => k === 0 || ex.tipo !== 'calentamiento')) {
      for (const [hi, h] of historiales.entries()) {
        for (const si of estados) {
          const sets = ESTADOS_SERIE[si];
          const ops = WF.getVariantesEj(ex);
          for (const variante of (ops ? [ops[0], ops[1]] : [undefined])) {
            for (let i = 0; i < sets.length; i++) {
              const activa = sets.findIndex((s) => !s.confirmed);
              WF.poner({ DATA: { dia: { id: 'd1', bloques: [{ ejercicios: [ex] }] }, historico_por_ejercicio: { [ex.id]: h }, rutina: { semana_actual: 1 } },
                STATE: { session: { [ex.id]: { sets: copia(sets), variante } } } });
              casos.push({ ex: ei, efectivo: efectivo.nombre, h: hi, series: si, variante: variante ?? null, i, activa: i === activa,
                ...leerFila(WF.renderSetRow(efectivo, sets[i], i, i === activa)) });
            }
          }
        }
      }
    }
  }
  return casos;
}

// ── F. confirmarSerie entero ─────────────────────────────────────────
const WC = construir(['confirmarSerie', '_serieVerosimil', '_recordKg', 'writeSet', 'rirDeSet', 'setExStatus', 'writeExerciseStatus', 'getExStatus',
  'checkIfDayCompleted', 'getProgresionActual', '_repsSug', 'suggestedReps', 'suggestedKg', 'kgHeredable', '_ultimaSerieRef', '_varianteActiva',
  'fechaLocalDe', 'getVariantesEntry', 'getVariantesEj', 'esSinPeso', 'exNoKg', 'normalizarCampoSerie'],
['unlockAudio', 'ensureSesionIniciada', 'startRest', 'renderTrain', 'loadHistorico', 'marcarLeidosEjercicio', '_marcarSerieDudosa', 'showDayCompletedModal']);
const DIA_C = {
  id: 'd2', bloques: [
    { titulo: 'BLOQUE 0 — CALENTAMIENTO', ejercicios: [
      { id: 'cal-d2-0', nombre: 'Movilidad de hombros', tipo: 'calentamiento', descanso_segundos: 30, series: 2, reps: '10' }] },
    { titulo: 'BLOQUE 1 — PECHO', ejercicios: [
      { id: 'pre-d2-0', nombre: 'Press banca', tipo: 'compuesto', descanso_segundos: 150, progresion: [{ semana: 1, series: 3, reps: '8', rir: '0 (al fallo)' }, { semana: 2, series: 3, reps: '6', rir: '0' }] },
      { id: 'tri-d2-1', nombre: 'Extensión de tríceps en polea', tipo: 'aislamiento', descanso_segundos: 90, progresion: [{ semana: 1, series: 2, reps: '12', rir: '1' }] },
      { id: 'dom-d2-2', nombre: 'Dominadas', tipo: 'compuesto', descanso_segundos: 120, progresion: [{ semana: 1, series: 2, reps: 'AMRAP', rir: null }] },
      { id: 'rue-d2-3', nombre: 'Rueda abdominal', tipo: 'core', descanso_segundos: 60, progresion: [{ semana: 1, series: 2, reps: '12-15', rir: null }] },
    ] },
  ],
};
const HIST_C = {
  'pre-d2-0': [fila(50, 1, 80, 10, 2, null), fila(50.1, 2, 82.5, 8, 1, null), fila(50.2, 3, 82.5, 7, 0, null)],
  'tri-d2-1': [fila(70, 1, 17.5, 12, 1, 'Soga'), fila(70.1, 2, 17.5, 11, 1, 'Soga'), fila(70.2, 1, 25, 10, 2, 'Barra')],
  'dom-d2-2': [], 'rue-d2-3': [], 'cal-d2-0': [],
};
const vacias = (n) => Array.from({ length: n }, () => ({ reps: '', kg: '', rir: '', confirmed: false }));
function sesionBase() {
  return {
    'cal-d2-0': { sets: vacias(2), completed: false, status: 'pendiente' },
    'pre-d2-0': { sets: vacias(3), completed: false, status: 'pendiente' },
    'tri-d2-1': { sets: vacias(2), completed: false, status: 'pendiente', variante: 'Barra' },
    'dom-d2-2': { sets: vacias(2), completed: false, status: 'pendiente' },
    'rue-d2-3': { sets: vacias(2), completed: false, status: 'pendiente', variante: 'Rodillas flexionadas' },
  };
}
// Cada caso: qué ejercicio y serie, cómo está la sesión antes, el día cerrado o no, y qué contesta el cliente.
const CASOS_C = [];
{
  const c = (nombre, ex, idx, cambios = {}) => CASOS_C.push({ nombre, ex, idx, ...cambios });
  c('one-tap con historial', 'pre-d2-0', 0);
  c('one-tap serie 2 con historial', 'pre-d2-0', 1);
  c('one-tap serie 3 (la del historial de 3 series)', 'pre-d2-0', 2);
  c('one-tap sin historial y AMRAP: no hay sugerido', 'dom-d2-2', 0);
  c('reps tipeadas en AMRAP sin kg: falta el kg', 'dom-d2-2', 0, { sets: { 'dom-d2-2': [{ reps: '9', kg: '', rir: '', confirmed: false }, { reps: '', kg: '', rir: '', confirmed: false }] } });
  c('reps tipeadas y kg tipeado', 'dom-d2-2', 0, { sets: { 'dom-d2-2': [{ reps: '9', kg: '10', rir: '', confirmed: false }, { reps: '', kg: '', rir: '', confirmed: false }] } });
  c('kg heredado de la serie anterior', 'dom-d2-2', 1, { sets: { 'dom-d2-2': [{ reps: '9', kg: '10', rir: '1', confirmed: true }, { reps: '8', kg: '', rir: '', confirmed: false }] } });
  c('sin peso: one-tap con las reps del plan', 'rue-d2-3', 0);
  c('sin peso: el kg tipeado se borra', 'rue-d2-3', 0, { sets: { 'rue-d2-3': [{ reps: '10', kg: '20', rir: '', confirmed: false }, { reps: '', kg: '', rir: '', confirmed: false }] } });
  c('calentamiento: sin descanso', 'cal-d2-0', 0);
  c('variante Soga: sugerido de Soga', 'tri-d2-1', 0, { variante: { 'tri-d2-1': 'Soga' } });
  c('variante Barra (default): filas viejas sin nota no cuentan si hay de Barra', 'tri-d2-1', 0);
  c('variante Maneral: sin historial de esa variante', 'tri-d2-1', 0, { variante: { 'tri-d2-1': 'Maneral' } });
  c('última serie: completo y se abre el siguiente', 'pre-d2-0', 2, { sets: { 'pre-d2-0': [{ reps: '10', kg: '80', rir: '', confirmed: true }, { reps: '8', kg: '82.5', rir: '1', confirmed: true }, { reps: '', kg: '', rir: '', confirmed: false }] } });
  c('última serie con el estado ya completo: no se vuelve a marcar', 'pre-d2-0', 2, { status: { 'pre-d2-0': 'completo' }, sets: { 'pre-d2-0': [{ reps: '10', kg: '80', rir: '', confirmed: true }, { reps: '8', kg: '82.5', rir: '1', confirmed: true }, { reps: '', kg: '', rir: '', confirmed: false }] } });
  c('última serie del día: día completo', 'rue-d2-3', 1, {
    status: { 'cal-d2-0': 'completo', 'pre-d2-0': 'completo', 'tri-d2-1': 'saltado', 'dom-d2-2': 'completo_sin_datos' },
    sets: { 'rue-d2-3': [{ reps: '12', kg: '', rir: '', confirmed: true }, { reps: '', kg: '', rir: '', confirmed: false }] } });
  c('serie ya confirmada: no hace nada', 'pre-d2-0', 0, { sets: { 'pre-d2-0': [{ reps: '10', kg: '80', rir: '', confirmed: true }, ...vacias(2)] } });
  c('día cerrado: reabrir', 'pre-d2-0', 0, { diaFinalizado: true, respuestas: [true] });
  c('día cerrado: dejarlo cerrado', 'pre-d2-0', 0, { diaFinalizado: true, respuestas: [false] });
  c('reps 0: rechazada', 'pre-d2-0', 0, { sets: { 'pre-d2-0': [{ reps: '0', kg: '80', rir: '', confirmed: false }, ...vacias(2)] } });
  c('reps 1214: rechazada', 'pre-d2-0', 0, { sets: { 'pre-d2-0': [{ reps: '1214', kg: '40', rir: '', confirmed: false }, ...vacias(2)] } });
  c('kg 3530: rechazada', 'pre-d2-0', 0, { sets: { 'pre-d2-0': [{ reps: '12', kg: '3530', rir: '', confirmed: false }, ...vacias(2)] } });
  c('kg 2000: en el tope duro todavía pregunta', 'pre-d2-0', 0, { sets: { 'pre-d2-0': [{ reps: '12', kg: '2000', rir: '', confirmed: false }, ...vacias(2)] }, respuestas: [false] });
  c('kg 600,5: pregunta', 'pre-d2-0', 0, { sets: { 'pre-d2-0': [{ reps: '10', kg: '600,5', rir: '', confirmed: false }, ...vacias(2)] }, respuestas: [false] });
  c('kg 800: pregunta y corrige', 'pre-d2-0', 0, { sets: { 'pre-d2-0': [{ reps: '10', kg: '800', rir: '', confirmed: false }, ...vacias(2)] }, respuestas: [false] });
  c('kg 800: pregunta y registra', 'pre-d2-0', 0, { sets: { 'pre-d2-0': [{ reps: '10', kg: '800', rir: '', confirmed: false }, ...vacias(2)] }, respuestas: [true] });
  c('kg 250 con récord 82,5: pregunta', 'pre-d2-0', 0, { sets: { 'pre-d2-0': [{ reps: '10', kg: '250', rir: '', confirmed: false }, ...vacias(2)] }, respuestas: [true] });
  c('kg 62,5 con coma', 'pre-d2-0', 0, { sets: { 'pre-d2-0': [{ reps: '10', kg: '62,5', rir: '0', confirmed: false }, ...vacias(2)] } });
  c('110 reps viniendo de 10: pregunta', 'pre-d2-0', 0, { sets: { 'pre-d2-0': [{ reps: '110', kg: '80', rir: '', confirmed: false }, ...vacias(2)] }, respuestas: [true] });
  c('31 reps viniendo de 10: pregunta', 'pre-d2-0', 0, { sets: { 'pre-d2-0': [{ reps: '31', kg: '80', rir: '', confirmed: false }, ...vacias(2)] }, respuestas: [false] });
  c('dos dudas juntas', 'pre-d2-0', 0, { sets: { 'pre-d2-0': [{ reps: '200', kg: '700', rir: '', confirmed: false }, ...vacias(2)] }, respuestas: [true] });
  c('sin peso con 300 reps', 'rue-d2-3', 0, { sets: { 'rue-d2-3': [{ reps: '300', kg: '', rir: '', confirmed: false }, ...vacias(1)] }, respuestas: [true] });
  c('sin peso con 301 reps', 'rue-d2-3', 0, { sets: { 'rue-d2-3': [{ reps: '301', kg: '', rir: '', confirmed: false }, ...vacias(1)] } });
  c('con sustitución: va el nombre del sustituto', 'pre-d2-0', 0, { swaps: { 'pre-d2-0': { current: { nombre: 'Press de banca en máquina' }, fijado: false } } });
  c('serie restaurada con otro nombre', 'pre-d2-0', 1, { sets: { 'pre-d2-0': [{ reps: '', kg: '', rir: '', confirmed: false }, { reps: '8', kg: '80', rir: '', confirmed: false, nombreRegistrado: 'Press de banca en máquina', varianteRegistrada: 'Vieja' }, ...vacias(1)] } });
  c('sin sesión todavía (sesionId null)', 'pre-d2-0', 0, { sesionId: null });
  c('RIR 0 se manda como 0', 'tri-d2-1', 1, { sets: { 'tri-d2-1': [{ reps: '12', kg: '20', rir: '', confirmed: true }, { reps: '10', kg: '20', rir: '0', confirmed: false }] } });
  c('semana 2', 'pre-d2-0', 0, { semana: 2 });
  c('peso con varios puntos ya normalizado', 'dom-d2-2', 0, { sets: { 'dom-d2-2': [{ reps: '8', kg: '.5', rir: '', confirmed: false }, ...vacias(1)] } });
  c('reps con espacios (vieja de la web)', 'dom-d2-2', 0, { sets: { 'dom-d2-2': [{ reps: ' 8', kg: '5', rir: '', confirmed: false }, ...vacias(1)] } });
}
async function vConfirmar(casos) {
  const salida = [];
  for (const c of casos) {
    nuevoCtx({ respuestas: [...(c.respuestas || [])] });
    const sesion = sesionBase();
    for (const [k, v] of Object.entries(c.sets || {})) sesion[k].sets = copia(v);
    for (const [k, v] of Object.entries(c.variante || {})) sesion[k].variante = v;
    const estados = {};
    for (const [k, v] of Object.entries(c.status || {})) { estados[k] = v; sesion[k].status = v; }
    WC.poner({
      DATA: { dia: copia(DIA_C), historico_por_ejercicio: copia(HIST_C), rutina: { semana_actual: c.semana || 1 }, _isDemo: false },
      RUTINA_ID: 'rut-1', _sesionId: 'sesionId' in c ? c.sesionId : 'ses-1', _diaFinalizado: !!c.diaFinalizado,
      STATE: { session: sesion, exerciseStates: estados, exerciseSwaps: copia(c.swaps || {}), expandedId: c.ex },
    });
    if (c.diaFinalizado) CTX.ls[`mypump_sesion_tok_${DIA_C.id}_finalizada`] = '1';
    await WC.confirmarSerie(c.ex, c.idx);
    const fin = WC.leer();
    salida.push({
      nombre: c.nombre, ex: c.ex, idx: c.idx, semana: c.semana || 1, sesionId: 'sesionId' in c ? c.sesionId : 'ses-1',
      diaFinalizado: !!c.diaFinalizado, respuestas: c.respuestas || [], antes: { sets: c.sets || {}, variante: c.variante || {}, status: c.status || {}, swaps: c.swaps || {} },
      despues: {
        sesion: Object.fromEntries(Object.entries(fin.STATE.session).map(([k, v]) => [k, { sets: v.sets, completed: v.completed, status: v.status, variante: v.variante ?? null }])),
        diaFinalizado: fin._diaFinalizado, expandido: fin.STATE.expandedId ?? null, finalizadaLocal: CTX.ls[`mypump_sesion_tok_${DIA_C.id}_finalizada`] ?? null,
      },
      cola: CTX.cola, modales: CTX.modales.map((m) => ({ titulo: m.title, cuerpo: m.body, confirmar: m.confirmLabel, cancelar: m.cancelLabel })),
      dudosas: CTX.llamadas.filter((l) => l[0] === '_marcarSerieDudosa').map((l) => l[3]),
      descanso: (CTX.llamadas.find((l) => l[0] === 'startRest') || [null, null])[1],
      historialPedido: CTX.llamadas.filter((l) => l[0] === 'loadHistorico').map((l) => l[1]),
      leidos: CTX.llamadas.filter((l) => l[0] === 'marcarLeidosEjercicio').map((l) => l[1]),
      sesionAsegurada: CTX.llamadas.some((l) => l[0] === 'ensureSesionIniciada'),
      diaCompleto: CTX.timeouts.length > 0,
    });
  }
  return { dia: DIA_C, historial: HIST_C, casos: salida };
}

// ── G. Acciones de la card (handlers reales de bindTrainEvents) ──────
const WA = construir(['bindTrainEvents', 'openRirPicker', 'writeSet', 'rirDeSet', 'setExStatus', 'writeExerciseStatus', 'getExStatus',
  'checkIfDayCompleted', 'getProgresionActual', 'invalidarHistorico', 'persistExerciseSwaps'],
['startEntrenamiento', 'enviarComentarioEjercicio', 'normalizarCampoSerie', 'kgHeredable', 'exNoKg', '_repsSug', 'suggestedKg', 'confirmarSerie',
  'renderTrain', 'loadHistorico', 'marcarLeidosEjercicio', 'stopRest', 'ensureSesionIniciada', 'showDayCompletedModal', 'openFinishModal',
  'openEarlyFinishModal', 'openExSwapModal', 'getEffectiveEx', 'persistSessionStart', 'closeModal']);
function boton(atributo, valor) {
  const escuchas = {};
  return { getAttribute: (a) => (a === atributo ? valor : null), addEventListener: (ev, f) => { escuchas[ev] = f; }, escuchas, disabled: false, textContent: '' };
}
const CASOS_A = [
  { nombre: 'marcar completo con todas confirmadas', attr: 'data-mark', valor: 'pre-d2-0', sets: { 'pre-d2-0': 'todas' } },
  { nombre: 'marcar completo con una sin confirmar: nada', attr: 'data-mark', valor: 'pre-d2-0' },
  { nombre: 'marcar completo el último: día completo', attr: 'data-mark', valor: 'rue-d2-3', sets: { 'rue-d2-3': 'todas' },
    status: { 'cal-d2-0': 'completo', 'pre-d2-0': 'completo', 'tri-d2-1': 'saltado', 'dom-d2-2': 'completo_sin_datos' } },
  { nombre: 'terminé con series: completo manual', attr: 'data-finish', valor: 'pre-d2-0', sets: { 'pre-d2-0': 'una' } },
  { nombre: 'terminé sin series: pregunta y queda sin datos', attr: 'data-finish', valor: 'pre-d2-0', respuestas: [true] },
  { nombre: 'terminé sin series: vuelve', attr: 'data-finish', valor: 'pre-d2-0', respuestas: [false] },
  { nombre: 'terminé el último sin series: día completo', attr: 'data-finish', valor: 'rue-d2-3', respuestas: [true],
    status: { 'cal-d2-0': 'completo', 'pre-d2-0': 'completo', 'tri-d2-1': 'saltado', 'dom-d2-2': 'completo_sin_datos' } },
  { nombre: 'reabrir un completo', attr: 'data-reopen', valor: 'pre-d2-0', status: { 'pre-d2-0': 'completo' }, sets: { 'pre-d2-0': 'todas' } },
  { nombre: 'reabrir uno sin datos', attr: 'data-reopen', valor: 'dom-d2-2', status: { 'dom-d2-2': 'completo_sin_datos' } },
  { nombre: 'lápiz sobre una serie de un completo', attr: 'data-edit', valor: 'pre-d2-0|1', status: { 'pre-d2-0': 'completo' }, sets: { 'pre-d2-0': 'todas' } },
  { nombre: 'lápiz sobre una serie de un pendiente', attr: 'data-edit', valor: 'pre-d2-0|0', sets: { 'pre-d2-0': 'una' } },
  { nombre: 'lápiz sobre un completo_sin_datos', attr: 'data-edit', valor: 'pre-d2-0|0', status: { 'pre-d2-0': 'completo_sin_datos' }, sets: { 'pre-d2-0': 'una' } },
  { nombre: 'variante', attr: 'data-variante', valor: 'tri-d2-1|Soga' },
  { nombre: 'variante con barra en el nombre', attr: 'data-variante', valor: 'tri-d2-1|A|B' },
  { nombre: 'abrir la card sin historial', attr: 'data-toggle', valor: 'dom-d2-2', expandido: null, historial: {} },
  { nombre: 'abrir la card con historial', attr: 'data-toggle', valor: 'pre-d2-0', expandido: 'dom-d2-2' },
  { nombre: 'cerrar la card abierta', attr: 'data-toggle', valor: 'pre-d2-0', expandido: 'pre-d2-0' },
  { nombre: 'volver al original', attr: 'data-revert-ex', valor: 'pre-d2-0', swaps: { 'pre-d2-0': { current: { nombre: 'Press de banca en máquina' }, fijado: true }, 'tri-d2-1': { current: { nombre: 'X' }, fijado: false } } },
];
async function vAcciones() {
  const salida = [];
  for (const c of CASOS_A) {
    nuevoCtx({ respuestas: [...(c.respuestas || [])] });
    const sesion = sesionBase();
    for (const [k, v] of Object.entries(c.sets || {})) {
      sesion[k].sets = sesion[k].sets.map((s, i) => (v === 'todas' || i === 0 ? { reps: '10', kg: '50', rir: '', confirmed: true } : s));
    }
    const estados = {};
    for (const [k, v] of Object.entries(c.status || {})) { estados[k] = v; sesion[k].status = v; }
    const hist = 'historial' in c ? c.historial : copia(HIST_C);
    WA.poner({
      DATA: { dia: copia(DIA_C), _dias: [copia(DIA_C)], historico_por_ejercicio: hist, rutina: { semana_actual: 1 }, _isDemo: false },
      RUTINA_ID: 'rut-1', _sesionId: 'ses-1',
      STATE: { session: sesion, exerciseStates: estados, exerciseSwaps: copia(c.swaps || {}), expandedId: 'expandido' in c ? c.expandido : c.valor.split('|')[0] },
    });
    const b = boton(c.attr, c.valor);
    CTX.$$ = (s) => (s === `[${c.attr}]` ? [b] : []);
    WA.bindTrainEvents();
    await b.escuchas.click({ stopPropagation() {} });
    await new Promise((r) => setImmediate(r));
    const fin = WA.leer();
    salida.push({
      nombre: c.nombre, attr: c.attr, valor: c.valor, respuestas: c.respuestas || [],
      antes: { sets: c.sets || {}, status: c.status || {}, swaps: c.swaps || {}, expandido: 'expandido' in c ? c.expandido : c.valor.split('|')[0], conHistorial: !('historial' in c) },
      despues: {
        sesion: Object.fromEntries(Object.entries(fin.STATE.session).map(([k, v]) => [k, { sets: v.sets, completed: v.completed, status: v.status, variante: v.variante ?? null }])),
        expandido: fin.STATE.expandedId ?? null, swaps: Object.keys(fin.STATE.exerciseSwaps).sort(),
        historialEnCache: Object.keys(fin.DATA.historico_por_ejercicio).sort(),
      },
      cola: CTX.cola, modales: CTX.modales.map((m) => ({ titulo: m.title, cuerpo: m.body, confirmar: m.confirmLabel, cancelar: m.cancelLabel })),
      stopRest: CTX.llamadas.some((l) => l[0] === 'stopRest'), sesionAsegurada: CTX.llamadas.some((l) => l[0] === 'ensureSesionIniciada'),
      historialPedido: CTX.llamadas.filter((l) => l[0] === 'loadHistorico').map((l) => l[1]),
      leidos: CTX.llamadas.filter((l) => l[0] === 'marcarLeidosEjercicio').map((l) => l[1]),
      diaCompleto: CTX.timeouts.length > 0, swapsGuardados: CTX.ls['mypump_exercise_swaps_rut-1'] ? Object.keys(JSON.parse(CTX.ls['mypump_exercise_swaps_rut-1'])).sort() : null,
    });
  }
  // El selector de RIR: elige un valor; si la serie ya estaba confirmada, se vuelve a mandar.
  const rir = [];
  for (const [confirmada, inicial, valor, ex, variante] of [[true, '1', '0'], [true, '', '3'], [false, '', '2'], [true, '0', '5'], [false, '4', '0'], [true, '2', '2'],
    [true, '3', '1'], [true, '5', '4'], [true, '', '1', 'tri-d2-1', 'Soga'], [true, '2', '0', 'tri-d2-1', null]]) {
    nuevoCtx();
    const sesion = sesionBase();
    const lugar = ex || 'pre-d2-0';
    sesion[lugar].sets[1] = { reps: '8', kg: '82.5', rir: inicial, confirmed: confirmada, ...(ex ? { varianteRegistrada: variante } : {}) };
    WA.poner({ DATA: { dia: copia(DIA_C), historico_por_ejercicio: {}, rutina: { semana_actual: 1 }, _isDemo: false }, RUTINA_ID: 'rut-1', _sesionId: 'ses-1',
      STATE: { session: sesion, exerciseStates: {}, exerciseSwaps: {} } });
    const opciones = [0, 1, 2, 3, 4, 5].map((n) => boton('data-rirset', String(n)));
    let leyenda = null;
    CTX.$ = (s) => (s === '#modalHost' ? { set innerHTML(h) { leyenda = (h.match(/id="rirLegend">([^<]*)</) || [])[1]; } } : { addEventListener() {} });
    CTX.$$ = (s) => (s === '#modalHost [data-rirset]' ? opciones : []);
    WA.openRirPicker(lugar, 1);
    opciones[Number(valor)].escuchas.click();
    rir.push({ ex: lugar, confirmada, inicial, varianteRegistrada: ex ? variante : null, valor, leyenda, serie: WA.leer().STATE.session[lugar].sets[1], cola: CTX.cola });
  }
  return { casos: salida, rir };
}

// ── G2. El resumen de "Cerrar sesión de hoy" (los dos modales reales) ──
const WZ = construir(['openFinishModal', 'openEarlyFinishModal', 'getExStatus', 'minutosSesion'], ['closeModal', 'writeFinish', 'ensureSesionIniciada'],
  "const ICONS = { flag: '' };");
const SERIES_RESUMEN = [
  { 'pre-d2-0': [{ reps: '10', kg: '80', confirmed: true }, { reps: '8', kg: '82.5', confirmed: true }, { reps: '7', kg: '', confirmed: false }] },
  { 'pre-d2-0': [{ reps: '0x10', kg: '1e3', confirmed: true }, { reps: ' 8', kg: '.5', confirmed: true }, { reps: 'abc', kg: '50', confirmed: true }],
    'rue-d2-3': [{ reps: '12', kg: '', confirmed: true }, { reps: '15', kg: '0', confirmed: true }] },
  { 'tri-d2-1': [{ reps: '12', kg: '17.5', confirmed: true }, { reps: '11', kg: '17.3', confirmed: true }], 'dom-d2-2': [{ reps: '5', kg: '10.1', confirmed: true }, { reps: '', kg: '', confirmed: false }] },
  {},
];
const ESTADOS_RESUMEN = [{}, { 'cal-d2-0': 'completo', 'pre-d2-0': 'completo' }, { 'cal-d2-0': 'saltado', 'pre-d2-0': 'completo', 'tri-d2-1': 'completo_sin_datos', 'dom-d2-2': 'completo', 'rue-d2-3': 'completo' },
  { 'rue-d2-3': 'completo' }];
async function vResumen() {
  const casos = [];
  for (const [si, series] of SERIES_RESUMEN.entries()) for (const [ei, estados] of ESTADOS_RESUMEN.entries()) for (const hace of [null, 30 * 60e3, 7 * 3600e3, 20e3]) {
    for (const modal of ['openFinishModal', 'openEarlyFinishModal']) {
      nuevoCtx();
      const sesion = sesionBase();
      for (const [k, v] of Object.entries(series)) sesion[k].sets = copia(v);
      let html = '';
      CTX.$ = (s) => (s === '#modalHost' ? { set innerHTML(h) { html = h; } } : { addEventListener() {}, value: '' });
      WZ.poner({ DATA: { dia: copia(DIA_C) }, _sessionStart: hace === null ? null : RELOJ.ms - hace, STATE: { session: sesion, exerciseStates: copia(estados) } });
      await WZ[modal]();
      const texto = html.match(/<div class="modal-text">([^<]*)<\/div>/)[1];
      const pendientes = [...html.matchAll(/<li>([^<]*)<\/li>/g)].map((m) => m[1]);
      const aviso = (html.match(/<div class="ewarn-label">([^<]*)<\/div>/) || [])[1] ?? null;
      casos.push({ modal, series: si, estados: ei, inicio: hace === null ? null : RELOJ.ms - hace, ahora: RELOJ.ms, texto, aviso, pendientes });
    }
  }
  return { series: SERIES_RESUMEN, estados: ESTADOS_RESUMEN, casos };
}

// ── H. Restaurar la sesión del día (registros y estados) ─────────────
const WR = construir(['loadRegistrosCarga', 'loadExerciseStates', 'getVariantesEntry', 'getVariantesEj']);
const REGISTROS = [
  { ejercicio_id: 'pre-d2-0', serie_numero: 1, peso_kg: 80, reps_realizadas: 10, rir_real: 2, notas: null, ejercicio_nombre: 'Press banca' },
  { ejercicio_id: 'pre-d2-0', serie_numero: 2, peso_kg: 82.5, reps_realizadas: 8, rir_real: 0, notas: null, ejercicio_nombre: 'Press de banca en máquina' },
  { ejercicio_id: 'pre-d2-0', serie_numero: 4, peso_kg: 82.5, reps_realizadas: 6, rir_real: null, notas: null, ejercicio_nombre: 'Press banca' },
  { ejercicio_id: 'tri-d2-1', serie_numero: 1, peso_kg: 17.5, reps_realizadas: 12, rir_real: null, notas: 'Soga', ejercicio_nombre: 'Extensión de tríceps en polea' },
  { ejercicio_id: 'tri-d2-1', serie_numero: 2, peso_kg: null, reps_realizadas: null, rir_real: 1, notas: '', ejercicio_nombre: null },
  { ejercicio_id: 'rue-d2-3', serie_numero: 1, peso_kg: 0, reps_realizadas: 12, rir_real: 0, notas: 'Rodillas extendidas', ejercicio_nombre: 'Rueda abdominal' },
  { ejercicio_id: 'dom-d2-2', serie_numero: 0, peso_kg: 10, reps_realizadas: 5, rir_real: 1, notas: 'Lastre', ejercicio_nombre: 'Dominadas' },
  { ejercicio_id: 'dom-d2-2', serie_numero: 1, peso_kg: 10, reps_realizadas: 5, rir_real: 1, notas: 'Lastre', ejercicio_nombre: 'Dominadas' },
  { ejercicio_id: 'otro-d9-0', serie_numero: 1, peso_kg: 10, reps_realizadas: 5, rir_real: 1, notas: null, ejercicio_nombre: 'Otro' },
];
const ESTADOS_SRV = [
  { ejercicio_id: 'pre-d2-0', status: 'completo', series_completadas: 3, marcado_manualmente: false },
  { ejercicio_id: 'dom-d2-2', status: 'completo_sin_datos', series_completadas: null, marcado_manualmente: true },
  { ejercicio_id: 'tri-d2-1', status: 'saltado', series_completadas: 0, marcado_manualmente: null },
  { ejercicio_id: 'otro-d9-0', status: 'completo', series_completadas: 1, marcado_manualmente: false },
];
async function vRestaurar() {
  const casos = [];
  for (const [nombre, regs, estados, confirmadaLocal] of [
    ['registros y estados', REGISTROS, ESTADOS_SRV, false],
    ['una serie ya confirmada en el teléfono no se pisa', REGISTROS, [], true],
    ['sin registros', [], ESTADOS_SRV, false],
    ['sin red', null, null, false],
  ]) {
    nuevoCtx({ db: {
      getRegistrosSesion: async () => ({ success: regs !== null, data: regs || [] }),
      getEjerciciosEstado: async () => estados,
    } });
    const sesion = sesionBase();
    if (confirmadaLocal) sesion['pre-d2-0'].sets[1] = { reps: '7', kg: '85', rir: '', confirmed: true };
    WR.poner({ DATA: { dia: copia(DIA_C), rutina: { semana_actual: 1 } }, RUTINA_ID: 'rut-1', _sesionId: 'ses-1',
      STATE: { session: sesion, exerciseStates: {}, exerciseMeta: {} } });
    await WR.loadExerciseStates();
    await WR.loadRegistrosCarga();
    const fin = WR.leer();
    casos.push({ nombre, registros: regs, estados, confirmadaLocal,
      sesion: Object.fromEntries(Object.entries(fin.STATE.session).map(([k, v]) => [k, { sets: v.sets, completed: v.completed, status: v.status, variante: v.variante ?? null }])),
      estadosLocales: fin.STATE.exerciseStates, meta: fin.STATE.exerciseMeta });
  }
  return casos;
}

// ── I. Poda de sustituciones (SER-12) ────────────────────────────────
const WP = construir(['pruneExerciseSwaps', 'invalidarHistorico', 'persistExerciseSwaps'], ['prefetchHistoricoDia']);
const sw = (fijado, semana, diaId) => {
  const s = { original: { slug: 'O', nombre: 'Original', images: null }, current: { slug: 'S', nombre: 'Sustituto', equipment: 'machine', images: null }, semana, diaId };
  if (fijado !== undefined) s.fijado = fijado;
  return s;
};
const MAPAS_PODA = [
  { a: sw(true, 1, 'd1'), b: sw(false, 1, 'd1'), c: sw(false, 2, 'd2'), d: sw(false, 1, 'd3'), e: sw(false, undefined, 'd2'), f: sw(false, 1, undefined), g: sw(true, 1, 'd3') },
  { x: sw(false, 1, 'd1') }, {}, { y: sw(false, '1', 'd1'), z: sw(null, 1, 'd2'), n: null },
];
function vPoda() {
  const casos = [];
  for (const [mi, mapa] of MAPAS_PODA.entries()) {
    for (const semana of [1, 2]) for (const completados of [[], ['d3'], ['d1', 'd2']]) for (const diaId of ['d1', 'd2']) {
      for (const diaFinalizado of [false, true]) for (const opts of [undefined, { conservarDiaActual: true }, { sinPrefetch: true }]) {
        nuevoCtx();
        WP.poner({ DATA: { dia: { id: diaId }, rutina: { semana_actual: semana }, historico_por_ejercicio: Object.fromEntries(Object.keys(mapa).map((k) => [k, []])) },
          RUTINA_ID: 'rut-1', _diaFinalizado: diaFinalizado,
          STATE: { exerciseSwaps: copia(mapa), diasCompletados: new Set(completados) } });
        WP.pruneExerciseSwaps(opts);
        const fin = WP.leer();
        casos.push({ mapa: mi, semana, completados, diaId, diaFinalizado, opciones: opts || null,
          quedan: Object.keys(fin.STATE.exerciseSwaps).sort(), invalidados: Object.keys(mapa).filter((k) => !(k in fin.DATA.historico_por_ejercicio)).sort(),
          guardo: 'mypump_exercise_swaps_rut-1' in CTX.ls, prefetch: CTX.llamadas.some((l) => l[0] === 'prefetchHistoricoDia') });
      }
    }
  }
  return { mapas: MAPAS_PODA, casos };
}

// ── J. Comentarios (SES-08) ──────────────────────────────────────────
const WM = construir(['rebuildComentarioIndexes', 'totalUnreadComentarios', 'getComentariosFor', 'getUnreadFor', 'getUnreadDia', 'fmtComentarioFecha'], ['updateGlobalCommentBadge']);
const com = (id, ambito, ref, autor, leido, creado) => ({ id, ambito, referencia_id: ref, referencia_nombre: 'X', autor, contenido: `c${id}`,
  leido_por_cliente: leido, leido_por_coach: false, created_at: creado || '2026-10-12T21:05:00+00:00' });
const FILAS_COM = [
  com('1', 'ejercicio', 'pre-d2-0', 'coach', false), com('2', 'ejercicio', 'pre-d2-0', 'cliente', true), com('3', 'ejercicio', 'pre-d2-0', 'coach', true),
  com('4', 'ejercicio', 'tri-d2-1', 'coach', false), com('5', 'ejercicio', 'tri-d2-1', 'coach', null), com('6', 'general', null, 'coach', false),
  com('7', 'general', null, 'coach', false), com('8', 'ejercicio', 'otro-d9-0', 'coach', false), com('9', 'ejercicio', '', 'coach', false),
  com('10', 'ejercicio', null, 'coach', false), com('11', 'ejercicio', 'dom-d2-2', 'cliente', false),
];
const FECHAS_COM = ['2026-10-12T21:05:00+00:00', '2026-10-14T03:30:00Z', '2026-01-01T12:00:00.123456+00:00', '2026-09-05T00:07:00-03:00',
  '2026-10-14T15:00:00+00:00', '2026-12-31T23:59:59Z', '2026-06-15T16:30:00+00:00', '2026-03-09T11:00:00.5+00:00'];
function vComentarios() {
  const casos = [];
  for (const filas of [FILAS_COM, [], FILAS_COM.slice(0, 5), FILAS_COM.filter((c) => c.ambito === 'general')]) {
    nuevoCtx();
    WM.poner({ STATE: {} });
    WM.rebuildComentarioIndexes(filas);
    const st = WM.leer().STATE;
    casos.push({ filas: filas.map((f) => f.id),
      porRef: Object.fromEntries(Object.entries(st.comentariosByRef).map(([k, v]) => [k, v.map((c) => c.id)])),
      sinLeer: st.comentariosUnread, total: WM.totalUnreadComentarios(), dia: WM.getUnreadDia(DIA_C) });
  }
  return { filas: FILAS_COM, casos, fechas: FECHAS_COM.map((iso) => ({ iso, texto: WM.fmtComentarioFecha(iso) })) };
}

// ── K. Tiempo de la sesión (SES-03) ──────────────────────────────────
const WT = construir(['fmtTime', 'fmtCrono', 'minutosSesion']);
function vTiempo() {
  const fmt = [0, 1, 9, 59, 60, 61, 90, 150, 599, 600, 3599, 3600, 7322, -5, -61].map((s) => ({ s, texto: WT.fmtTime(s) }));
  const crono = [0, 999, 1000, 59999, 60000, 3599999, 3600000, 3661000, 21600000, 36000000, -5000, 86399999].map((ms) => ({ ms, texto: WT.fmtCrono(ms) }));
  const minutos = [];
  for (const inicio of [null, 0]) minutos.push({ inicio, ahora: RELOJ.ms, min: (WT.poner({ _sessionStart: inicio }), WT.minutosSesion()) });
  for (const delta of [0, 499, 500, 29999, 30000, 89999, 90000, 3600000, 21599499, 21599500, 21600000, 21600499, 21600500, 21601000, -499, -500, -1000, 90061000]) {
    WT.poner({ _sessionStart: RELOJ.ms - delta });
    minutos.push({ inicio: RELOJ.ms - delta, ahora: RELOJ.ms, min: WT.minutosSesion() });
  }
  return { fmt, crono, minutos };
}

// ── L. Descanso (SES-04) ─────────────────────────────────────────────
// Los botones −15 / +15 / Saltar se atan una vez al cargar la página (no es una función con nombre).
const botonesDescanso = tramo("$$('[data-rest]').forEach(", '}));');
const WD = construir(['startRest', 'persistRest', 'restoreRest', 'restTick', 'stopRest', 'updateRestUI', 'fmtTime'], ['fireRestDone', 'maybeAskNotifPermission'],
  `function __botones() { ${botonesDescanso} }`, ['__botones']);
function domDescanso() {
  const el = () => ({ hidden: true, textContent: '', style: {}, clases: new Set(),
    get classList() { const c = this.clases; return { add: (x) => c.add(x), remove: (x) => c.delete(x), toggle: (x, v) => (v ? c.add(x) : c.delete(x)) }; } });
  const dom = { '#restBar': el(), '#restTime': el(), '#restTarget': el(), '#restProgFill': el() };
  CTX.$ = (s) => dom[s] || el();
  return dom;
}
const SECUENCIAS = [
  [['iniciar', 0, 90], ['tick', 1000], ['tick', 89999], ['tick', 90000], ['tick', 91000], ['tick', 92000]],
  [['iniciar', 0, 90], ['ajustar', 5000, '15'], ['tick', 104000], ['tick', 105000], ['ajustar', 106000, '15'], ['tick', 107000], ['tick', 120000], ['tick', 122000]],
  [['iniciar', 0, 60], ['ajustar', 10000, '-15'], ['ajustar', 11000, '-15'], ['tick', 30000], ['ajustar', 31000, '-15'], ['tick', 31000], ['tick', 32000]],
  [['iniciar', 0, 150], ['saltar', 3000], ['tick', 4000]],
  [['iniciar', 0, 90], ['restaurar', 50000], ['tick', 89000], ['restaurar', 91000], ['tick', 91500], ['restaurar', 92000]],
  [['iniciar', 0, 45], ['iniciar', 20000, 30], ['tick', 49000], ['tick', 50000], ['tick', 52000]],
  [['restaurar', 0]],
  [['iniciar', 0, 90], ['ajustar', 1000, '-15'], ['ajustar', 1000, '-15'], ['ajustar', 1000, '-15'], ['ajustar', 1000, '-15'], ['ajustar', 1000, '-15'], ['ajustar', 1000, '-15'], ['tick', 1000], ['tick', 3000]],
  [['iniciar', 0, 90], ['tick', 90000], ['ajustar', 91000, '15'], ['tick', 104999], ['tick', 105000], ['tick', 107000]],
];
function vDescanso() {
  return SECUENCIAS.map((pasos) => {
    nuevoCtx();
    const dom = domDescanso();
    WD.poner({ STATE: { rest: null } });
    const T0 = RELOJ.ms;
    const estados = [];
    let botones = null;
    for (const [accion, t, arg] of pasos) {
      RELOJ.ms = T0 + t;
      if (accion === 'iniciar') WD.startRest(arg);
      else if (accion === 'tick') WD.restTick();
      else if (accion === 'restaurar') WD.restoreRest();
      else {
        if (!botones) {
          botones = { skip: boton('data-rest', 'skip'), '-15': boton('data-rest', '-15'), 15: boton('data-rest', '15') };
          CTX.$$ = (s) => (s === '[data-rest]' ? Object.values(botones) : []);
          WD.__botones();
        }
        (accion === 'saltar' ? botones.skip : botones[arg]).escuchas.click();
      }
      const r = WD.leer().STATE.rest;
      estados.push({ accion, t, arg: arg ?? null,
        descanso: r ? { fin: r.endsAt - T0, objetivo: r.target, cierre: r.autoCloseAt - T0, terminado: r.doneFired } : null,
        disparos: CTX.llamadas.filter((l) => l[0] === 'fireRestDone').length,
        guardado: CTX.ls['mypump_rest_tok'] ? (({ endsAt, target, autoCloseAt }) => ({ fin: endsAt - T0, objetivo: target, cierre: autoCloseAt - T0 }))(JSON.parse(CTX.ls['mypump_rest_tok'])) : null,
        visible: !dom['#restBar'].hidden, listo: dom['#restBar'].clases.has('is-done'),
        texto: dom['#restTime'].textContent, objetivoTexto: dom['#restTarget'].textContent, ancho: dom['#restProgFill'].style.width ?? null });
    }
    RELOJ.ms = T0;
    return estados;
  });
}

// ── M. Semana: banner, calibración, avanzar, bloque nuevo, día completo ──
// El banner de la semana vive adentro de renderTrain: se toma ese tramo tal cual (con su if/else y su HTML).
const bannerSrc = tramo('const _exDia = DATA.dia.bloques.flatMap(b => b.ejercicios);', 'no te guardes reps.</div>`;');
const WS = construir(['getProgresionActual', 'computeProgresionNota', 'confirmAvanzarSemana', 'doAvanzarSemana', 'confirmEmpezarBloqueNuevo',
  'doEmpezarBloqueNuevo', 'showDayCompletedModal', 'checkIfDayCompleted', 'getExStatus'], ['cambiarDia'],
`function __banner() { let html = ''; ${bannerSrc} }
  return { n: _nCambian, calibracion: _esCalibracion, texto: html.replace(/<[^>]+>/g, '') || null }; }`, ['__banner']);
function bannerDe() { return WS.__banner(); }
function vSemana(rutinas, conRef) {
  const banners = [];
  for (const [ri, est] of rutinas.entries()) {
    const n = normalizado(est);
    if (!n.usable) continue;
    const dias = W.normalizarRutina(est).est.dias;
    const maxSem = Math.max(2, ...ejerciciosDe([est]).map((e) => (Array.isArray(e.progresion) ? e.progresion.length : 0))) + 1;
    for (const [di, dia] of dias.entries()) for (let semana = 1; semana <= maxSem; semana++) for (const offset of [0, 12]) {
      WS.poner({ DATA: { dia, rutina: { semana_actual: semana, semana_offset: offset } } });
      const r = bannerDe();
      banners.push({ ...(conRef ? { ref: ri } : { plan: ri }), dia: di, semana, offset, n: r.n, calibracion: r.calibracion, texto: r.texto });
    }
  }
  return banners;
}
async function vTextosSemana() {
  const avanzar = [];
  for (const [semana, total, offset] of [[1, 12, 0], [5, 12, 0], [11, 12, 0], [12, 12, 0], [1, 12, 12], [3, 6, 18], [13, 12, 0]]) {
    for (const completo of [false, true]) {
      nuevoCtx({ respuestas: [false] });
      const status = completo ? { 'cal-d2-0': 'completo', 'pre-d2-0': 'completo', 'tri-d2-1': 'completo', 'dom-d2-2': 'completo', 'rue-d2-3': 'saltado' } : {};
      WS.poner({ DATA: { dia: copia(DIA_C), rutina: { semana_actual: semana, semanas_total: total, semana_offset: offset } }, STATE: { session: {}, exerciseStates: status } });
      await WS.confirmAvanzarSemana();
      avanzar.push({ semana, total, offset, diaCompleto: completo, modal: CTX.modales[0] ? { titulo: CTX.modales[0].title, cuerpo: CTX.modales[0].body, confirmar: CTX.modales[0].confirmLabel, cancelar: CTX.modales[0].cancelLabel } : null });
    }
  }
  const errores = [];
  for (const fn of ['doAvanzarSemana', 'doEmpezarBloqueNuevo']) {
    for (const [nombre, ultimo] of [['red', { code: 'NETWORK', transitorio: true }], ['transitorio', { code: '', status: 503, transitorio: true }], ['rechazo', { code: 'P0001', status: 400, transitorio: false }], ['token', null]]) {
      nuevoCtx({ respuestas: [false], db: { _lastError: ultimo, avanzarSemana: async () => null, activarSiguiente: async () => (fn === 'doEmpezarBloqueNuevo' ? false : null) } });
      WS.poner({ DATA: { dia: copia(DIA_C), rutina: { semana_actual: 4 } } });
      await WS[fn]();
      const m = CTX.modales[0];
      errores.push({ fn, caso: nombre, modal: m ? { titulo: m.title, cuerpo: m.body, confirmar: m.confirmLabel, cancelar: m.cancelLabel } : null });
    }
  }
  // Éxito: borra los cachés de sesión de ESE token y recarga.
  nuevoCtx({ db: { _lastError: null, avanzarSemana: async (t, destino) => { CTX.llamadas.push(['avanzar', destino]); return destino; } } });
  CTX.ls = { 'mypump_sesion_tok_d1': 'x', 'mypump_sesion_tok_d1_semana': '4', 'mypump_sesion_otro_d1': 'y', 'mypump_rest_tok': '{}', 'mypump_dia_visualizado_rut-1': 'd1' };
  WS.poner({ DATA: { dia: copia(DIA_C), rutina: { semana_actual: 4 } } });
  await WS.doAvanzarSemana();
  const exito = { destino: CTX.llamadas.find((l) => l[0] === 'avanzar')[1], quedan: Object.keys(CTX.ls).sort(), recargo: CTX.llamadas.includes('reload') };
  nuevoCtx({ respuestas: [false] });
  await WS.confirmEmpezarBloqueNuevo();
  const bloque = CTX.modales.map((m) => ({ titulo: m.title, cuerpo: m.body, confirmar: m.confirmLabel, cancelar: m.cancelLabel }))[0];
  const completo = [];
  const DIAS = [{ id: 'd1', nombre: 'Tirón' }, { id: 'd2', nombre: 'Empuje' }, { id: 'd3' }, { id: 'd4', nombre: 'Pierna' }];
  for (const [actual, mostrado] of [['d1', false], ['d2', false], ['d3', false], ['d4', false], ['d1', true], ['x', false]]) {
    nuevoCtx({ respuestas: [false] });
    WS.poner({ DATA: { dia: { id: actual }, _dias: DIAS }, STATE: { diaCompletadoMostrado: mostrado } });
    await WS.showDayCompletedModal();
    const m = CTX.modales[0];
    completo.push({ actual, mostrado, modal: m ? { titulo: m.title, cuerpo: m.body, confirmar: m.confirmLabel, cancelar: m.cancelLabel } : null });
  }
  return { avanzar, errores, exito, bloque, diaCompleto: { dias: DIAS, casos: completo } };
}

// Textos que la web arma adentro de renderTrain (no son funciones): se leen del código para que la nativa los
// compare con los suyos y un cambio de redacción en la web haga fallar el test.
function textosFijos() {
  const html = (re) => {
    const m = HTML.match(re);
    if (!m) throw new Error(`no encontré ${re}`);
    return m[1].replace(/<br\s*\/?>/g, '\n').replace(/<[^>]+>/g, '').replace(/[ \t]+/g, ' ').trim();
  };
  return {
    diaVacio: html(/<div class="prog-empty" style="padding:32px 16px">([^]*?)<\/div>/),
    demo: html(/<div class="demo-banner">([^]*?)<\/div>/),
    empezar: html(/<span class="ss-txt"><strong>([^<]*)<\/strong>/),
    empezarDetalle: html(/<span class="ss-txt"><strong>[^<]*<\/strong>\s*<small>([^<]*)<\/small>/),
    sinCerrar: html(/<span class="sc-hint">(quedó abierta[^<]*)<\/span>/),
    porPrimeraSerie: html(/<span class="sc-hint">(⏱[^<]*)<\/span>/),
    sinComentarios: html(/<div class="ex-com-empty">([^<]*)<\/div>/),
    comentarioFallo: (HTML.match(/alert\('(No se pudo enviar el comentario[^']*)'\)/) || [])[1],
    cerrarSinSesion: (HTML.match(/alert\('(No se pudo guardar la sesión[^']*)'\)/) || [])[1],
    cerrarFallo: (HTML.match(/alert\('(No se pudo cerrar la sesión[^']*)'\)/) || [])[1],
    sinVariantes: html(/<div class="swap-empty">(No hay otra variante[^<]*)<\/div>/),
  };
}

// ── Escribir ─────────────────────────────────────────────────────────
function escribir(destino, datos) {
  fs.mkdirSync(destino, { recursive: true });
  fs.writeFileSync(path.join(destino, 'entreno.json'), JSON.stringify({ fuente: `public/cliente.html@${commit}`, ahora: AHORA, zona: process.env.TZ, ...datos }) + '\n');
}
// Lo que la nativa decide distinto a propósito, o no puede representar. Ver EntrenoTests.swift.
const excepciones = [
  'Un bloque, día o ejercicio que no es objeto (null, texto): la web lo vuelve un objeto vacío (bloque "B{i}" vacío, día "Día n" sin bloques, ejercicio sin nombre); el decodificador de la nativa (Rutina.swift) lo descarta.',
  'Un día sin la clave `bloques`: la web suma "<día>: sin bloques." a los problemas; la nativa no distingue "falta" de "vacío" y dice solo "sin ejercicios.".',
  'descanso_segundos o series con decimales o en notación rara ("1e2", "0x10", true): la web los usa como número; la nativa los lee como entero (Int) o los descarta.',
  'semanas_total como texto ("12"): la web lo deja texto y arma "SEM 5/120" (concatena); la nativa lo lee como número.',
  'Bloques con `nombre` o `title` en vez de `titulo`: la web los lee para el rótulo; la nativa solo conoce `titulo` y `subtitulo`.',
];

const ejPublicos = ejerciciosDe(rutinasPublicas);
const historial = vHistorial(EJ_HIST, HISTORIALES);
const pub = {
  normalizar: vNormalizar([...rutinasPublicas, ...PLANES_SINTETICOS], false),
  textos: vTextos(rutinasPublicas, DIAS_DIFICILES, BLOQUES_DIFICILES),
  ejercicios: vEjercicios(ejPublicos, NOMBRES_DIFICILES),
  reps: vReps(ejPublicos, REPS_DIFICILES),
  campos: CAMPOS.map(([campo, v]) => ({ campo, v, out: WE.normalizarCampoSerie(campo, v) })),
  rir: RIRS.map((v) => ({ v, out: WE.rirDeSet(v) })),
  historial: { ejercicios: EJ_HIST, historiales: HISTORIALES, casos: historial },
  heredable: vHeredable(),
  filas: { ejercicios: EJ_FILA, historiales: HISTORIALES.slice(0, 6), series: ESTADOS_SERIE, casos: vFilas(EJ_FILA, HISTORIALES.slice(0, 6)) },
  confirmar: await vConfirmar(CASOS_C),
  acciones: await vAcciones(),
  resumen: await vResumen(),
  restaurar: await vRestaurar(),
  poda: vPoda(),
  comentarios: vComentarios(),
  tiempo: vTiempo(),
  descanso: vDescanso(),
  semana: { banners: vSemana([...rutinasPublicas, ...PLANES_SINTETICOS.filter((p) => p && Array.isArray(p.dias))], false),
    planes: [...rutinasPublicas, ...PLANES_SINTETICOS.filter((p) => p && Array.isArray(p.dias))], ...(await vTextosSemana()) },
  textosFijos: textosFijos(),
  excepciones,
};
escribir(path.join(RAIZ, 'apps/shared/vectores'), pub);
const cuenta = (d) => Object.entries(d).filter(([k]) => !['textosFijos', 'excepciones'].includes(k))
  .map(([k, v]) => [k, Array.isArray(v) ? v.length : Array.isArray(v.casos) ? v.casos.length : Object.values(v).filter(Array.isArray).reduce((a, x) => a + x.length, 0)]);
let resumenPrivado = 'sin estructuras privadas';
if (rutinasPrivadas.length) {
  const ejPriv = ejerciciosDe(rutinasPrivadas);
  // Los ejercicios reales con los historiales sintéticos: uno de cada nombre+tipo, para que el archivo no explote.
  const vistos = new Set();
  const ejHistPriv = ejPriv.filter((e) => { const k = `${e.nombre}|${e.tipo}`; if (vistos.has(k)) return false; vistos.add(k); return true; })
    .map((e, i) => ({ id: `${i}-${e.id}`, nombre: e.nombre, tipo: e.tipo, descanso_segundos: e.descanso_segundos, progresion: e.progresion, series: e.series, reps: e.reps }));
  // Las filas, sobre un tercio de esos ejercicios (vFilas indexa sobre la lista que recibe: se guarda esa misma).
  const ejFilaPriv = ejHistPriv.filter((_, i) => i % 4 === 0);
  const priv = {
    archivos: ARCHIVOS_PRIVADOS,
    normalizar: vNormalizar(rutinasPrivadas, true),
    textos: vTextos(rutinasPrivadas, [], []),
    ejercicios: vEjercicios(ejPriv, nombresRegistrados.filter((n) => typeof n === 'string')),
    reps: vReps(ejPriv, []),
    historial: { ejercicios: ejHistPriv, historiales: HISTORIALES, casos: vHistorial(ejHistPriv, HISTORIALES.slice(0, 5), 2) },
    filas: { ejercicios: ejFilaPriv, historiales: HISTORIALES.slice(0, 3), series: ESTADOS_SERIE, casos: vFilas(ejFilaPriv, HISTORIALES.slice(0, 3), [0, 1, 2, 5]) },
    semana: { banners: vSemana(rutinasPrivadas, true) },
  };
  escribir(path.join(PRIVADO, 'vectores'), priv);
  resumenPrivado = cuenta(priv).map(([k, n]) => `${k} ${n}`).join(' · ');
}
console.log(`▸ cliente.html@${commit}`);
console.log(`  públicos: ${cuenta(pub).map(([k, n]) => `${k} ${n}`).join(' · ')}`);
console.log(`  privados: ${resumenPrivado}`);
