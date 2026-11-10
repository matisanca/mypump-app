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

console.log(`\n${ok} OK · ${fail} fallas`);
process.exit(fail ? 1 : 0);
