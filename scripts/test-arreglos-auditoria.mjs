#!/usr/bin/env node
/* =============================================================
 * test-arreglos-auditoria.mjs — los arreglos de la auditoría del 10/11 en la web.
 *
 * F2: ninguna lectura tenía tope y con la señal «colgada» la web quedaba en
 *     «Cargando…» para siempre. Se corre el supabase-client.js REAL con un
 *     cliente de Supabase que nunca contesta.
 * F3: si la rutina llegaba y la dieta se cortaba, la web mostraba la dieta de
 *     ejemplo de 3.200 kcal con «Todavía no tenés dieta publicada» y guardaba la
 *     copia sin dieta. Se extraen de cliente.html las funciones reales.
 *
 * USO:  node scripts/test-arreglos-auditoria.mjs
 * ============================================================= */

import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import { fileURLToPath } from 'node:url';

const raiz = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const html = fs.readFileSync(path.join(raiz, 'public/cliente.html'), 'utf8');
const funcion = (nombre) => {
  const m = html.match(new RegExp(`\\n((?:async )?function ${nombre}\\([^)]*\\) \\{[\\s\\S]*?\\n\\})\\n`));
  if (!m) { console.error(`✗ no encontré ${nombre} en cliente.html`); process.exit(1); }
  return m[1];
};

let ok = 0, fail = 0;
const t = async (nombre, fn) => {
  try { await fn(); console.log(`  ✓ ${nombre}`); ok++; }
  catch (e) { console.log(`  ✗ ${nombre}\n      ${e.message}`); fail++; }
};
const igual = (a, b, m) => { if (JSON.stringify(a) !== JSON.stringify(b)) throw new Error(`${m}: ${JSON.stringify(a)} ≠ ${JSON.stringify(b)}`); };

console.log('F2 · las lecturas tienen tope');
{
  const fuente = fs.readFileSync(path.join(raiz, 'public/js/supabase-client.js'), 'utf8');
  let abortado = false;
  const cuelga = () => {
    const q = new Promise(() => {});        // ni responde ni corta
    q.abortSignal = (s) => { s.addEventListener('abort', () => { abortado = true; }); return q; };
    return q;
  };
  const ctx = {
    console, AbortController, URLSearchParams,
    // El tope real es de 15 s: el reloj de la prueba corre 1000 veces más rápido.
    setTimeout: (f, ms) => setTimeout(f, ms / 1000), clearTimeout,
    location: { hostname: 'app' },
    window: { MYPUMP_CONFIG: { SUPABASE_URL: 'https://x', SUPABASE_ANON_KEY: 'k' }, supabase: { createClient: () => ({ rpc: cuelga }) } },
  };
  vm.createContext(ctx);
  vm.runInContext(fuente, ctx);
  const db = ctx.window.mypumpDB;
  await t('una lectura colgada termina como «sin red» y no deja la carga esperando', async () => {
    const reloj = setTimeout(() => { throw new Error('la lectura no terminó'); }, 2000);
    const r = await db.getRutinaActiva('tok');
    clearTimeout(reloj);
    igual(r, null, 'rutina');
    igual(db._lastError && db._lastError.code, 'NETWORK', 'el error cuenta como red (el arranque cae a la copia)');
    if (!abortado) throw new Error('el pedido no se cortó');
  });
  await t('la info colgada también (es la primera del arranque)', async () => {
    igual(await db.getClienteInfo('tok'), null, 'info');
    igual(db._lastError.transitorio, true, 'transitorio');
  });
}

console.log('F3 · la dieta que no llegó por un corte');
{
  const ctx = { console, localStorage: new Map(), TOKEN: 'tok' };
  ctx.localStorage.getItem = (k) => ctx.localStorage.has(k) ? ctx.localStorage.get(k) : null;
  ctx.localStorage.setItem = (k, v) => ctx.localStorage.set(k, String(v));
  vm.createContext(ctx);
  vm.runInContext(['_dietaDelArranque', '_dietaDeLaCopia', 'saveOfflineSnapshot', 'loadOfflineSnapshot', '_avisoDietaOculta'].map(funcion).join('\n'), ctx);
  const red = { code: 'NETWORK', transitorio: true };
  const buena = { id: 'dieta-1', estructura: { comidas: [] } };

  await t('con error y con copia: la dieta de la copia', async () => {
    igual(ctx._dietaDelArranque(null, red, { dieta: buena }), { dieta: buena, sinRed: false, deCopia: true }, 'arranque');
  });
  await t('con error y sin copia: «sin red», nunca «no tiene dieta»', async () => {
    igual(ctx._dietaDelArranque(null, red, null), { dieta: null, sinRed: true, deCopia: false }, 'arranque');
    const aviso = ctx._avisoDietaOculta('sin-red');
    if (/Todavía no tenés/.test(aviso)) throw new Error('dice que no tiene dieta');
    if (!/Sin conexión/.test(aviso) || !/data-recargar-datos/.test(aviso)) throw new Error('falta el aviso de conexión o el botón');
  });
  await t('sin error y sin filas sí es «no tiene» (y no se muestra el ejemplo)', async () => {
    igual(ctx._dietaDelArranque(null, null, { dieta: buena }), { dieta: null, sinRed: false, deCopia: false }, 'arranque');
    if (!/Todavía no tenés dieta/.test(ctx._avisoDietaOculta('sin-dieta'))) throw new Error('aviso');
  });
  await t('la copia buena no se pisa con un hueco', async () => {
    ctx.saveOfflineSnapshot({ nombre: 'A' }, { id: 'r' }, buena);
    // Arranque con la dieta cortada: lo que se guarda es la dieta de la copia.
    ctx.saveOfflineSnapshot({ nombre: 'A' }, { id: 'r' }, ctx._dietaDeLaCopia());
    igual(ctx.loadOfflineSnapshot().dieta, buena, 'dieta guardada');
  });
  await t('init usa la decisión y no guarda un hueco', async () => {
    const init = funcion('init');
    if (!/_dietaDelArranque\(dieta, errDieta/.test(init)) throw new Error('init no mira el error de la dieta');
    if (!/_dietaSinRed \? _dietaDeLaCopia\(\) : dieta/.test(init)) throw new Error('init guarda la copia sin mirar el corte');
    if (!/DATA\._dietaOculta = /.test(init)) throw new Error('una cuenta real vería el ejemplo');
  });
}

console.log('F6 · fotos rechazadas y fotos nuevas durante una subida');
{
  const ls = new Map();
  const ctx = {
    console, TOKEN: 'tok', STATE: { scene: 'otra' }, navigator: { onLine: true },
    localStorage: { getItem: (k) => ls.has(k) ? ls.get(k) : null, setItem: (k, v) => ls.set(k, String(v)), removeItem: (k) => ls.delete(k) },
    loadFotos: async () => {}, renderMydayFotos: () => {},
  };
  vm.createContext(ctx);
  vm.runInContext(`const FOTOQ_KEY = () => 'mypump_fotoq_' + TOKEN;\n` +
    ['_fotoqLeer', '_fotoqGuardar', '_fotoqSacar', '_fotosRechazadas', '_fotosRechazadasGuardar', '_fotoRechazar', '_fotoReintentar',
     '_fotoDescartar', 'flushFotos', '_flushFotosPasada'].map(funcion).join('\n') +
    `\nconst FOTOS_RECHAZADAS_KEY = () => 'mypump_fotos_rechazadas_' + TOKEN;\nlet _fotosDrenando = false;`, ctx);
  await t('un rechazo de la cola queda en «no se pudo subir» (no se borra)', async () => {
    ctx._fotoqGuardar({ 'L|frente': { pose: 'frente', fecha: 'F', dataUrl: 'data:a' } });
    ctx._subirFoto = async () => ({ ok: false, fatal: true, error: 'fecha fuera de rango' });
    await ctx.flushFotos();
    igual(Object.keys(ctx._fotoqLeer()), [], 'cola');
    igual(ctx._fotosRechazadas()['L|frente'].motivo, 'fecha fuera de rango', 'rechazada');
    ctx._subirFoto = async () => ({ ok: true });
    await ctx._fotoReintentar('L|frente');
    igual(Object.keys(ctx._fotosRechazadas()), [], 'al reintentar y entrar, se va');
  });
  await t('una foto sacada mientras otra sube no se pierde', async () => {
    ctx._fotoqGuardar({ 'L|frente': { pose: 'frente', fecha: 'F', dataUrl: 'data:a' } });
    ctx._subirFoto = async () => {
      // Mientras sube la de frente, el alumno saca la de perfil.
      const q = ctx._fotoqLeer(); q['L|perfil'] = { pose: 'perfil', fecha: 'F', dataUrl: 'data:b' }; ctx._fotoqGuardar(q);
      ctx._subirFoto = async () => ({ ok: false, red: true });
      return { ok: true };
    };
    await ctx.flushFotos();
    igual(Object.keys(ctx._fotoqLeer()), ['L|perfil'], 'la nueva sigue en la cola');
  });
}

console.log('F14 · lo escrito no se borra si falla el envío');
{
  let alertas = 0;
  const ls = new Map();
  const ctx = {
    console, TOKEN: 'tok', STATE: {}, DATA: { dia: { id: 'd1' } }, RUTINA_ID: 'r',
    alert: () => { alertas++; }, loadComentarios: async () => {},
    localStorage: { getItem: (k) => ls.has(k) ? ls.get(k) : null, setItem: (k, v) => ls.set(k, String(v)), removeItem: (k) => ls.delete(k) },
    window: { mypumpDB: { agregarComentario: async () => ({ success: false }), finalizarSesion: async () => ({ success: false }) } },
    _csVaciarDeshacer: () => {}, ensureSesionIniciada: async () => {}, Outbox: { flush: async () => {} }, minutosSesion: () => 30,
  };
  vm.createContext(ctx);
  vm.runInContext(['enviarComentarioEjercicio', '_notasCierreKey', '_notasCierreGuardadas', '_notasCierreAnotar', 'writeFinish'].map(funcion).join('\n') + '\nlet _sesionId = "s1";', ctx);
  await t('el comentario que no salió queda escrito', async () => {
    await ctx.enviarComentarioEjercicio('ex1', 'Press', '  me dolió el hombro ');
    igual(ctx.STATE.borradoresComentario.ex1, 'me dolió el hombro', 'borrador');
    ctx.window.mypumpDB.agregarComentario = async () => ({ success: true });
    await ctx.enviarComentarioEjercicio('ex1', 'Press', 'me dolió el hombro');
    igual(ctx.STATE.borradoresComentario.ex1, undefined, 'al salir se borra');
  });
  await t('las notas del cierre quedan si el cierre falla', async () => {
    await ctx.writeFinish('poco tiempo hoy');
    igual(ctx._notasCierreGuardadas(), 'poco tiempo hoy', 'notas');
    if (!/_notasCierreGuardadas\(\)/.test(html.slice(html.indexOf('id="sessionNotes"') - 200, html.indexOf('id="sessionNotes"') + 300))) throw new Error('el modal no vuelve a mostrar las notas');
  });
  await t('el OK de la carga simple no espera al historial del siguiente', async () => {
    const f = funcion('confirmarSerie');
    if (!/if \(foto\) loadHistorico\(next\.id\)\.then/.test(f)) throw new Error('confirmarSerie sigue esperando el historial con el OK');
  });
}

console.log('F7 · Progreso y Suplementación se releen al volver');
{
  const llamadas = [];
  let pendientes = 0;
  const ctx = {
    console, TOKEN: 'tok', DATA: {}, STATE: { progressLoaded: true, progresoLeidoEn: 0, suplLeidaEn: 0 },
    Outbox: { pending: () => pendientes },
    loadProgressAndRender: async (r) => { llamadas.push('progreso:' + r); },
    loadSuplementacion: async () => { llamadas.push('supl'); },
  };
  vm.createContext(ctx);
  vm.runInContext('const RELEER_PROGRESO_MS = 5 * 60 * 1000;\nconst RELEER_SUPL_MS = 10 * 60 * 1000;\n' + funcion('_relecturasAlVolver'), ctx);
  const T0 = 1_792_000_000_000;
  await t('pasados unos minutos se releen, y al minuto no', async () => {
    ctx._relecturasAlVolver(T0);
    await new Promise((r) => setTimeout(r, 0));
    igual(llamadas, ['progreso:true', 'supl'], 'primera vuelta');
    ctx._relecturasAlVolver(T0 + 60_000);
    igual(llamadas.length, 2, 'al minuto no se relee nada');
    ctx._relecturasAlVolver(T0 + 6 * 60_000);
    igual(llamadas.slice(2), ['progreso:true'], 'a los 6 minutos solo Progreso');
  });
  await t('con escrituras en cola Progreso espera', async () => {
    pendientes = 1;
    await new Promise((r) => setTimeout(r, 0));
    const n = llamadas.length;
    ctx._relecturasAlVolver(T0 + 60 * 60_000);
    igual(llamadas.slice(n), ['supl'], 'solo Suplementación');
  });
  await t('una relectura sin red deja lo que se veía', async () => {
    const f = funcion('loadProgressAndRender');
    if (!/if \(refresco && STATE\.progressLoaded\) return;/.test(f)) throw new Error('el corte pisaría Progreso con «sin red»');
  });
}

console.log(`\n${ok} OK · ${fail} fallas`);
process.exit(fail ? 1 : 0);
