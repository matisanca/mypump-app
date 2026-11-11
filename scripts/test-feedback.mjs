#!/usr/bin/env node
/* =============================================================
 * test-feedback.mjs — «Feedback del alumno» (2.3.0) en la web: «Me duele» y «¿Ya lo tenés?».
 *
 * Las reglas contra los MISMOS casos de iOS y Android (scripts/vectores-app/feedback.json,
 * copia exacta de apps/shared/fixtures/feedback/casos.json), el dibujo del cuerpo que va
 * embebido en public/js/feedback.js, los textos prohibidos y el modelo (palancas apagadas =
 * ninguna llamada; sin la función en el servidor = nada a la vista; marca optimista que
 * vuelve atrás).
 *
 * El dibujo y los textos se comparan con la referencia (rama nativa-feedback) cuando está a
 * mano: en este mismo repo después de unir las ramas, en FEEDBACK_REF, o en
 * ~/Developer/mn-feedback. Si está y difiere, falla. Si no está, se valida la copia contra
 * los toques de los casos.
 * USO:  node scripts/test-feedback.mjs
 * ============================================================= */
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import vm from 'node:vm';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';

const require = createRequire(import.meta.url);
const raiz = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const F = require('../public/js/feedback.js');
const V = JSON.parse(fs.readFileSync(path.join(raiz, 'scripts/vectores-app/feedback.json'), 'utf8'));

let ok = 0, fail = 0;
const igual = (a, b) => JSON.stringify(a) === JSON.stringify(b);
function t(nombre, cond, extra) {
  if (cond) { ok++; return; }
  fail++;
  console.log(`  ✗ ${nombre}${extra === undefined ? '' : ` → ${JSON.stringify(extra)}`}`);
}

// ── Reglas contra los casos compartidos ──
for (const c of V.zonas) t(`zona ${c.zona}/${c.lado}`, F.nombreZona(c.zona, c.lado) === c.nombre, F.nombreZona(c.zona, c.lado));
for (const [i, n] of V.niveles) t(`nivel ${i}`, F.nivel(i).id === n, F.nivel(i));
for (const [i, f] of V.fuerte) t(`fuerte ${i}`, F.esFuerte(i) === f);
for (const [a, b] of V.claves) t(`clave ${JSON.stringify(a)}`, F.clave(a) === b, F.clave(a));
{
  const fs_ = F.filas(V.suple.items, V.suple.marcas);
  t('filas de suplementos', igual(fs_, V.suple.filas), fs_);
  t('resumen', F.resumen(fs_) === V.suple.resumen, F.resumen(fs_));
  t('un protector nunca es fila', !fs_.some((f) => f.id === 'telmisartan'));
  t('lo que sale sin marca no es fila', !fs_.some((f) => f.id === 'multivitaminico'));
  t('filas sin lista', igual(F.filas(null, {}), []) && igual(F.filas([null, 3, 'x', {}], null), []));
  t('marca desconocida = sin marca', igual(F.filas([{ nombre: 'Zinc' }], { zinc: 'inventado' }), [{ id: 'zinc', nombre: 'Zinc', estado: null }]));
}
for (const c of V.toques) {
  const p = F.piezaEn(c.vista, c.x, c.y);
  t(`toque ${c.vista} ${c.x},${c.y}`, (p ? p.zona : null) === c.zona && (p ? p.lado : null) === c.lado, p);
}
{
  const e = F.decodificarEstado(V.molestias.respuesta);
  t('decodifica', !!e && e.dueleHabilitado === true && e.supleHabilitado === false);
  t('molestias que se entienden', igual(e.molestias.map((m) => m.id), V.molestias.ids), e.molestias.map((m) => m.id));
  for (const [ej, id] of Object.entries(V.molestias.por_ejercicio)) {
    const m = F.molestiaDe(e, ej);
    t(`molestia de ${ej}`, (m ? m.id : null) === id, m);
  }
  const a3 = e.molestias.find((m) => m.id === 'a3');
  t('lado raro = centro', a3.lado === 'centro' && F.nombreZona(a3.zona, a3.lado) === V.molestias.nombre_a3);
  t('intensidad fuera de rango se descarta', a3.intensidad === null);
  t('marcas', igual(e.marcas, V.molestias.marcas), e.marcas);
  t('abierta', e.molestias[0].abierta === true && e.molestias[1].abierta === false);
  for (const j of [null, undefined, 3, 'x', [], true]) t(`estado ${JSON.stringify(j)} no se entiende`, F.decodificarEstado(j) === null);
  const vacio = F.decodificarEstado({});
  t('objeto vacío = todo apagado', vacio.dueleHabilitado === false && vacio.supleHabilitado === false && vacio.molestias.length === 0);
  t('habilitado que no es booleano no prende', F.decodificarEstado({ me_duele: { habilitado: 'si' }, suple_estado: { habilitado: 1 } }).dueleHabilitado === false);
  t('campos internos no pasan', !('destino' in F.decodificarMolestia({ id: 'a', ejercicio_id: 'e', zona: 'codo', estado: 'avisada', destino: 'mati', clinico: true, resolucion: 'x' })));
}

// ── El borrador y lo que se manda ──
{
  const b0 = F.borradorVacio();
  t('borrador vacío no se puede avisar', F.completa(b0) === false);
  const b = { zona: 'hombro', lado: 'derecho', desde: 'hoy', cuando: 'al_subir', tipo: 'sordo', intensidad: 7, nota: '  duele al final  ' };
  t('borrador completo', F.completa(b) === true);
  for (const [k, v] of [['zona', 'oreja'], ['lado', 'arriba'], ['desde', 'ayer'], ['cuando', 'nunca'], ['tipo', 'raro'], ['intensidad', 11], ['intensidad', null], ['intensidad', 2.5]]) {
    t(`incompleto con ${k}=${v}`, F.completa({ ...b, [k]: v }) === false);
  }
  const p = F.parametrosMolestia('tok', 'id-1', 'ex_010', 'Remo', 'd1', b, null);
  const FIRMA = ['p_token', 'p_id', 'p_ejercicio_id', 'p_ejercicio_nombre', 'p_dia_id', 'p_zona', 'p_lado', 'p_desde', 'p_cuando', 'p_tipo', 'p_intensidad', 'p_nota', 'p_plataforma', 'p_version'];
  t('parámetros = la firma del SQL', igual(Object.keys(p).sort(), FIRMA.slice().sort()), Object.keys(p));
  t('plataforma web', p.p_plataforma === 'web');
  t('id tal cual', p.p_id === 'id-1' && p.p_token === 'tok');
  t('nota sin espacios de punta', p.p_nota === 'duele al final');
  t('intensidad del escalón', p.p_intensidad === 7 && [2, 5, 7, 9].every((n, i) => F.NIVELES[i].id === n));
  t('sin día ni versión = null', F.parametrosMolestia('t', 'i', 'e', 'n', null, b, null).p_dia_id === null && p.p_version === null);
  t('nota vacía = null', F.parametrosMolestia('t', 'i', 'e', 'n', null, { ...b, nota: '   ' }, null).p_nota === null);
  t('incompleto no se manda', F.parametrosMolestia('t', 'i', 'e', 'n', null, { ...b, zona: null }, null) === null);
  t('nota por puntos de código', Array.from(F.nota('😀'.repeat(600))).length === 500 && F.nota('a'.repeat(501)).length === 500 && F.nota('hola') === 'hola');
  t('nombres largos se recortan', F.parametrosMolestia('t', 'i', 'e'.repeat(300), 'n'.repeat(300), 'd'.repeat(200), b, 'v'.repeat(90)).p_ejercicio_id.length === 160
    && F.parametrosMolestia('t', 'i', 'e', 'n'.repeat(300), 'd'.repeat(200), b, 'v'.repeat(90)).p_dia_id.length === 80);
  t('nombre con sustituto', F.nombreParaAvisar('Remo en máquina', 'Remo con barra') === 'Remo en máquina (en lugar de Remo con barra)');
  t('nombre sin sustituto', F.nombreParaAvisar('Remo', null) === 'Remo' && F.nombreParaAvisar('Remo', 'Remo') === 'Remo');

  // Tocar el dibujo: zona y lado de una vez; con «los dos», tocar el otro lado de la misma zona no lo deshace.
  let d = F.tocarPieza(b0, { zona: 'hombro', lado: 'derecho' });
  t('tocar da zona y lado', d.zona === 'hombro' && d.lado === 'derecho');
  d = { ...d, lado: 'ambos' };
  t('con los dos, el otro lado no lo deshace', F.tocarPieza(d, { zona: 'hombro', lado: 'izquierdo' }).lado === 'ambos');
  t('con los dos, otra zona sí cambia', igual([F.tocarPieza(d, { zona: 'codo', lado: 'izquierdo' }).zona, F.tocarPieza(d, { zona: 'codo', lado: 'izquierdo' }).lado], ['codo', 'izquierdo']));
  t('la cabeza no cambia nada', F.tocarPieza(d, { zona: null, lado: null }) === d);
  t('elegida con los dos', F.piezaElegida({ zona: 'hombro', lado: 'izquierdo' }, d) && F.piezaElegida({ zona: 'hombro', lado: 'derecho' }, d) && !F.piezaElegida({ zona: 'codo', lado: 'derecho' }, d));

  // Corregir un aviso: el borrador sale de la molestia y la intensidad vuelve a su escalón.
  const m = F.decodificarMolestia({ id: 'u', ejercicio_id: 'e', zona: 'espalda_baja', lado: 'centro', desde: 'hoy', cuando: 'al_bajar', tipo: 'punzante', intensidad: 6, nota: 'x', estado: 'avisada' });
  const bm = F.borradorDe(m);
  t('borrador de una molestia', bm.zona === 'espalda_baja' && bm.intensidad === 7 && bm.nota === 'x' && F.completa(bm));
  t('la vista de una zona', F.vistaDe('espalda_baja') === 'espalda' && F.vistaDe('pecho') === 'frente' && F.vistaDe('muslo_atras') === 'espalda');
  t('molestia sin intensidad no completa', F.completa(F.borradorDe(F.decodificarMolestia({ id: 'u', ejercicio_id: 'e', zona: 'codo', estado: 'avisada' }))) === false);
}

// ── El dibujo embebido ──
{
  const C = F.CUERPO;
  t('lienzo 200 × 420', C.ancho === 200 && C.alto === 420 && igual(Object.keys(C.vistas), ['frente', 'espalda']));
  const largo = { capsula: 5, elipse: 4, caja: 5 };
  const vistas = new Set();
  for (const v of F.VISTAS) {
    const ids = new Set();
    for (const p of C.vistas[v]) {
      const bien = largo[p.forma] === p.a.length && p.a.every((n) => typeof n === 'number' && isFinite(n))
        && (p.zona === null ? p.lado === null : (F.zonaValida(p.zona) && F.LADOS.includes(p.lado) && p.lado !== 'ambos'));
      t(`pieza ${v} ${F.idPieza(p)}`, bien, p);
      t(`pieza ${v} ${F.idPieza(p)} única`, !ids.has(F.idPieza(p)));
      ids.add(F.idPieza(p));
      if (p.zona) {
        vistas.add(p.zona);
        const c = F.centro(p);
        t(`pieza ${v} ${F.idPieza(p)} adentro del lienzo`, c.x > 0 && c.x < C.ancho && c.y > 0 && c.y < C.alto);
        t(`pieza ${v} ${F.idPieza(p)} se contiene`, F.contiene(p, c.x, c.y, 0));
      }
    }
    t(`una sola cabeza en ${v}`, C.vistas[v].filter((p) => !p.zona).length === 1);
  }
  t('todas las zonas están en el dibujo', F.ZONAS.every((z) => vistas.has(z.id)), F.ZONAS.filter((z) => !vistas.has(z.id)).map((z) => z.id));

  const candidatos = [process.env.FEEDBACK_REF, raiz, path.join(os.homedir(), 'Developer/mn-feedback')].filter(Boolean);
  const ref = candidatos.find((d) => fs.existsSync(path.join(d, 'apps/shared/fixtures/feedback/cuerpo.json')));
  if (ref) {
    const leer = (f) => JSON.parse(fs.readFileSync(path.join(ref, 'apps/shared/fixtures/feedback', f), 'utf8'));
    t('el dibujo embebido es igual a cuerpo.json', igual(C, leer('cuerpo.json')));
    t('los casos son la copia exacta de casos.json', igual(V, leer('casos.json')));
    const swift = path.join(ref, 'apps/ios/MyPumpKit/Sources/MyPumpReglas/TextosFeedback.swift');
    if (fs.existsSync(swift)) {
      const pares = [...fs.readFileSync(swift, 'utf8').matchAll(/public static let (\w+) = "((?:[^"\\]|\\.)*)"/g)];
      t('textos de la app leídos', pares.length >= 30, pares.length);
      for (const [, k, v] of pares) t(`texto ${k} = el de la app`, F.T[k] === v, F.T[k]);
    }
  } else {
    console.log('  (sin la referencia de nativa-feedback a mano: el dibujo se valida solo contra los toques de los casos)');
  }
}

// ── Textos: sin dos puntos, sin guiones, sin emojis y sin palabras prohibidas ──
{
  const textos = [
    ...Object.values(F.T), ...F.DESDE.map((o) => o.texto), ...F.CUANDO.map((o) => o.texto), ...F.TIPO.map((o) => o.texto),
    ...F.NIVELES.map((o) => o.texto), ...F.LADOS_ELEGIBLES.map((o) => o.texto), ...F.ESTADOS_SUPLE.flatMap((s) => [s.accion, s.marcado]),
    ...F.ZONAS.flatMap((z) => F.LADOS.map((l) => F.nombreZona(z.id, l))), F.resumen([{ estado: 'comprado' }, { estado: null }]),
    F.nombreParaAvisar('Remo en máquina', 'Remo con barra'),
  ];
  t('todos son texto', textos.every((s) => typeof s === 'string' && s.trim().length > 0));
  const mal = (re) => textos.filter((s) => re.test(s));
  t('sin dos puntos', mal(/:/).length === 0, mal(/:/));
  t('sin guiones', mal(/[-–—]/).length === 0, mal(/[-–—]/));
  t('sin emojis', mal(/\p{Extended_Pictographic}/u).length === 0, mal(/\p{Extended_Pictographic}/u));
  const PROHIBIDAS = /\bIA\b|inteligencia artificial|coach|tu entrenador|\bRIR\b|cerca del fallo|en reserva/i;
  t('sin IA, coach, tu entrenador, RIR ni cerca del fallo', mal(PROHIBIDAS).length === 0, mal(PROHIBIDAS));
  const DIAGNOSTICO = /diagn[oó]stic|lesi[oó]n|tendinitis|desgarro|contractura|esguince|inflamaci[oó]n|hernia|m[eé]dico|tratamiento/i;
  t('nada que suene a diagnóstico', mal(DIAGNOSTICO).length === 0, mal(DIAGNOSTICO));
  // Las pantallas no traen textos propios: todo sale de Feedback.T. Lo que queda entre etiquetas en el código son plantillas.
  const sinComentarios = (s) => s.replace(/\/\*[\s\S]*?\*\//g, '').replace(/^\s*\/\/.*$/gm, '').replace(/\s\/\/ .*$/gm, '');
  const uiSrc = sinComentarios(fs.readFileSync(path.join(raiz, 'public/js/feedback-ui.js'), 'utf8'));
  t('las pantallas sin palabras prohibidas', !PROHIBIDAS.test(uiSrc) && !DIAGNOSTICO.test(uiSrc));
  const sueltos = [...uiSrc.matchAll(/>([^<>${}`'"()=;\n]*[A-Za-zÁÉÍÓÚáéíóúñ]{3,}[^<>${}`'"()=;\n]*)</g)].map((m) => m[1].trim()).filter(Boolean);
  t('las pantallas sin textos sueltos', sueltos.length === 0, sueltos);
  t('«Me duele» no escribe comentarios', !/comentario/i.test(uiSrc));
}

// ── El modelo y lo que se pinta, con un navegador de mentira ──
function navegador() {
  const guardado = new Map();
  const w = {
    localStorage: { getItem: (k) => (guardado.has(k) ? guardado.get(k) : null), setItem: (k, v) => guardado.set(k, String(v)), removeItem: (k) => guardado.delete(k) },
    crypto: globalThis.crypto,
  };
  w.window = w;
  const document = { hidden: false, addEventListener() {}, removeEventListener() {}, querySelector: () => null, activeElement: null, body: null };
  const ctx = vm.createContext({ window: w, document, localStorage: w.localStorage, console, setTimeout, Date, JSON, Math });
  for (const f of ['feedback.js', 'feedback-ui.js']) {
    vm.runInContext(`(function(){ var module = undefined; ${fs.readFileSync(path.join(raiz, 'public/js', f), 'utf8')}\n}).call(window)`, ctx, { filename: f });
  }
  return { w, guardado };
}
const SERVIDOR = () => ({ me_duele: { habilitado: true, molestias: [] }, suple_estado: { habilitado: true, items: [{ item: 'omega 3', estado: 'comprado' }] } });
function conServidor(responder) {
  const { w, guardado } = navegador();
  const llamadas = [];
  let cambios = 0;
  w.FeedbackUI.configurar({ token: 'tok-de-prueba', version: null, alCambiar: () => { cambios++; }, rpc: async (fn, p) => { llamadas.push([fn, p]); return responder(fn, p); } });
  return { ui: w.FeedbackUI, llamadas, guardado, cambios: () => cambios };
}
const EJ = { id: 'ex_010', nombre: 'Remo con barra', original: null, diaId: 'd1', tipo: 'compuesto' };
const ITEMS = V.suple.items;

{
  // Palancas apagadas: ni una llamada, nada a la vista.
  const s = conServidor(() => ({ ok: true, data: SERVIDOR() }));
  await s.ui.aplicarPalanca(false);
  t('apagadas: ninguna llamada', s.llamadas.length === 0, s.llamadas);
  t('apagadas: nada a la vista', s.ui.botonHtml(EJ) === '' && s.ui.estadoHtml(EJ) === '' && s.ui.supleHtml(ITEMS) === '');
  // Sin poder preguntar y sin nada sabido: tampoco.
  await s.ui.aplicarPalanca(null);
  t('sin respuesta de la palanca y sin nada sabido: ninguna llamada', s.llamadas.length === 0);
}
{
  // Prendidas: una sola lectura.
  const s = conServidor(() => ({ ok: true, data: SERVIDOR() }));
  await s.ui.aplicarPalanca(true);
  t('prendidas: una sola lectura', igual(s.llamadas.map((l) => l[0]), ['mypump_feedback_get']) && igual(s.llamadas[0][1], { p_token: 'tok-de-prueba' }));
  t('botón en el ejercicio', /data-duele-ex="ex_010"/.test(s.ui.botonHtml(EJ)) && s.ui.botonHtml(EJ).includes(F.T.dueleBoton));
  t('sin botón en calentamiento ni cardio', s.ui.botonHtml({ ...EJ, tipo: 'calentamiento' }) === '' && s.ui.botonHtml({ ...EJ, tipo: 'cardio' }) === '');
  t('sin molestia no hay tarjeta', s.ui.estadoHtml(EJ) === '');
  const h = s.ui.supleHtml(ITEMS);
  t('sección de suplementos', h.includes(F.T.supleTitulo) && h.includes('2 de 3 marcados') === false && h.includes('1 de 2 marcados'), h.match(/\d de \d marcados/));
  t('sin protectores ni lo que sale', !/Telmisart/.test(h) && !/Multivitam/.test(h) && !/Zinc/.test(h));
  t('cuatro estados por fila', (h.match(/<option value="(comprado|tomando|no_lo_consigo|lo_deje)"/g) || []).length === 8);
  // Una palanca que vuelve apagada: se va todo, sin más llamadas.
  await s.ui.aplicarPalanca(false);
  t('se apaga: nada a la vista y sin más llamadas', s.ui.botonHtml(EJ) === '' && s.ui.supleHtml(ITEMS) === '' && s.llamadas.length === 1);
}
for (const [nombre, resp] of [
  ['sin la función (PGRST202)', { ok: false, status: 404, codigo: 'PGRST202', clase: 'permanente' }],
  ['404', { ok: false, status: 404, codigo: '', clase: 'permanente' }],
  ['respuesta que no se entiende', { ok: true, data: 'hola' }],
  ['token caído', { ok: true, data: null }],
  ['el servidor dice apagado', { ok: true, data: { me_duele: { habilitado: false, molestias: [] }, suple_estado: { habilitado: false, items: [] } } }],
]) {
  const s = conServidor(() => resp);
  await s.ui.aplicarPalanca(true);
  t(`${nombre}: nada a la vista`, s.ui.botonHtml(EJ) === '' && s.ui.estadoHtml(EJ) === '' && s.ui.supleHtml(ITEMS) === '' && s.llamadas.length === 1);
}
{
  // Sin red: lo último que se supo de esta cuenta.
  const s = conServidor(() => ({ ok: true, data: SERVIDOR() }));
  await s.ui.aplicarPalanca(true);
  const guardado = s.guardado;
  const { w } = navegador();
  for (const [k, v] of guardado) w.localStorage.setItem(k, v);
  w.FeedbackUI.configurar({ token: 'tok-de-prueba', rpc: async () => ({ ok: false, status: 0, codigo: 'NETWORK', clase: 'red' }), alCambiar() {} });
  await w.FeedbackUI.aplicarPalanca(null);
  t('sin red: lo último guardado', w.FeedbackUI.dueleHabilitado() && w.FeedbackUI.supleHtml(ITEMS).includes('1 de 2 marcados'));
  const otro = navegador();
  for (const [k, v] of guardado) otro.w.localStorage.setItem(k, v);
  otro.w.FeedbackUI.configurar({ token: 'otra-cuenta', rpc: async () => ({ ok: false, status: 0, codigo: 'NETWORK', clase: 'red' }), alCambiar() {} });
  await otro.w.FeedbackUI.aplicarPalanca(null);
  t('sin red: lo guardado de otra cuenta no se muestra', !otro.w.FeedbackUI.dueleHabilitado());
}
// Marcar: se ve enseguida, viaja con el nombre del ítem y, si falla, vuelve atrás.
{
  const { w } = navegador();
  const llamadas = [];
  let modo = 'ok';
  let soltar = null;
  w.FeedbackUI.configurar({
    token: 'tok', alCambiar() {},
    rpc: (fn, p) => {
      llamadas.push([fn, p]);
      if (fn === 'mypump_feedback_get') return Promise.resolve({ ok: true, data: SERVIDOR() });
      return new Promise((r) => { soltar = () => r(modo === 'ok' ? { ok: true, data: { ok: true } } : modo === 'rechazo' ? { ok: true, data: { ok: false, error: 'item' } } : { ok: false, status: 0, clase: 'red' }); });
    },
  });
  await w.FeedbackUI.aplicarPalanca(true);
  // La sección se enlaza a mano: un select de mentira que dispara onchange.
  const selects = [];
  const root = { querySelectorAll: () => selects };
  const elegir = async (nombre, valor) => {
    selects.length = 0;
    const sel = { dataset: { suplMarca: '0', nombre }, value: valor, onchange: null };
    selects.push(sel);
    w.FeedbackUI.enlazarSuple(root);
    sel.onchange();
  };
  await elegir('Creatina monohidrato', 'tomando');
  let h = w.FeedbackUI.supleHtml(ITEMS);
  t('marca optimista: se ve antes de que conteste', h.includes('Lo estás tomando') && h.includes('2 de 2 marcados') && /is-viajando/.test(h));
  t('marca: viaja el nombre del ítem', igual(llamadas[1], ['mypump_suple_marcar', { p_token: 'tok', p_item: 'Creatina monohidrato', p_estado: 'tomando', p_nota: null }]), llamadas[1]);
  soltar(); await new Promise((r) => setTimeout(r, 5));
  h = w.FeedbackUI.supleHtml(ITEMS);
  t('marca tomada: queda', h.includes('Lo estás tomando') && !/is-viajando/.test(h) && !h.includes(F.T.supleError));

  modo = 'red';
  await elegir('Creatina monohidrato', 'no_lo_consigo');
  t('no lo consigo: el aviso sale enseguida', w.FeedbackUI.supleHtml(ITEMS).includes(F.T.supleNoConsigoAviso));
  soltar(); await new Promise((r) => setTimeout(r, 5));
  h = w.FeedbackUI.supleHtml(ITEMS);
  t('falla la red: vuelve a como estaba y avisa', h.includes('Lo estás tomando') && !h.includes(F.T.supleNoConsigoAviso) && h.includes(F.T.supleError));

  modo = 'rechazo';
  await elegir('Omega 3', 'lo_deje');
  soltar(); await new Promise((r) => setTimeout(r, 5));
  h = w.FeedbackUI.supleHtml(ITEMS);
  t('el servidor no lo toma: vuelve a como estaba', h.includes('Comprado') && !h.includes('Lo dejaste') && h.includes(F.T.supleError));
  const n = llamadas.length;
  modo = 'ok';
  await elegir('Omega 3', 'comprado');
  t('marcar lo mismo no llama', llamadas.length === n);
  await elegir('Omega 3', 'inventado');
  t('un estado desconocido no llama', llamadas.length === n);
  t('ninguna escritura de comentarios', llamadas.every((l) => !/coment/.test(l[0])));
}

// ── El service worker lleva la sección y la página la carga ──
{
  const sw = fs.readFileSync(path.join(raiz, 'public/sw.js'), 'utf8');
  for (const f of ['/js/feedback.js', '/js/feedback-ui.js', '/css/feedback.css']) t(`sw con ${f}`, sw.includes(`'${f}'`));
  const html = fs.readFileSync(path.join(raiz, 'public/cliente.html'), 'utf8');
  t('cliente.html carga la sección', html.includes('/js/feedback.js') && html.includes('/js/feedback-ui.js') && html.includes('/css/feedback.css'));
  t('la palanca sale de me_duele y suple_estado', /cfg\.me_duele === true \|\| cfg\.suple_estado === true/.test(html));
}

console.log(`\n${ok} ok, ${fail} fallas`);
process.exit(fail ? 1 : 0);
