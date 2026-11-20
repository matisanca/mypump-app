#!/usr/bin/env node
/* =============================================================
 * test-carga-teclado.mjs — «Salir del peso sin registrar nada» en la web (2.3.3, como Android S2).
 *  1. CargaSimple.EsperaTrasTeclado (public/js/carga-simple.js) con un reloj que maneja la prueba: los mismos casos
 *     que EsperaTecladoTest de Android (rama nativa-233). El caso de Sebastián (19/11): escribió el peso, se cerró el
 *     teclado y el mismo toque registró la serie.
 *  2. Que public/cliente.html use la espera y traiga lo demás del rediseño: Enter suelta el campo, tocar afuera suelta,
 *     «Ahora: serie N de M», la fila activa, el kilo 46/44/40 y la nota de la semana arriba de la pauta.
 * Los toques reales (teclado, foco y el OK) se prueban en el navegador.
 * USO:  node scripts/test-carga-teclado.mjs
 * ============================================================= */
import { createRequire } from 'node:module';
import assert from 'node:assert/strict';
import fs from 'node:fs';
const require = createRequire(import.meta.url);
const C = require('../public/js/carga-simple.js');
const HTML = fs.readFileSync(new URL('../public/cliente.html', import.meta.url), 'utf8');
const SW = fs.readFileSync(new URL('../public/sw.js', import.meta.url), 'utf8');

let ok = 0;
async function caso(n, f) { try { await f(); ok++; } catch (e) { console.error('MAL', n, '\n', e.stack || e); process.exitCode = 1; } }
const reloj = (t0 = 1000) => { const r = { t: t0 }; r.f = () => r.t; return r; };

// ── 1. La espera, con el reloj de la prueba ──
await caso('espera: medio segundo, como Android', () => {
  assert.equal(C.ESPERA_TECLADO_MS, 500);
  assert.equal(new C.EsperaTrasTeclado(() => 0).ms, 500);
});
await caso('espera: sin teclado el OK no espera', () => {
  const r = reloj(), e = new C.EsperaTrasTeclado(r.f);
  e.ver(false); assert.ok(e.admite());
  e.ver(false); assert.ok(e.admite());
  assert.ok(!e.recienVuelve());
});
await caso('espera: con el panel escondido no admite nunca', () => {
  const r = reloj(), e = new C.EsperaTrasTeclado(r.f);
  e.ver(true); assert.ok(!e.admite());
  r.t += 10000; assert.ok(!e.admite(), 'escondido no registra nunca');
});
await caso('espera: al volver espera medio segundo (el toque que cerró el teclado no registra)', () => {
  const r = reloj(), e = new C.EsperaTrasTeclado(r.f);
  e.ver(true);
  r.t = 5000; e.ver(false);
  assert.ok(!e.admite(), 'el toque que cerró el teclado');
  assert.ok(e.recienVuelve());
  r.t = 5000 + 499; assert.ok(!e.admite());
  r.t = 5000 + 500; assert.ok(e.admite());
  assert.ok(!e.recienVuelve());
});
await caso('espera: repintar sin cambios no la reinicia', () => {
  const r = reloj(), e = new C.EsperaTrasTeclado(r.f);
  e.ver(true);
  r.t = 5000; e.ver(false);
  r.t = 5300; e.ver(false);   // otra pintada con el panel a la vista: sigue contando desde que volvió
  r.t = 5500; assert.ok(e.admite());
});
await caso('espera: cada vuelta arranca otra espera', () => {
  const r = reloj(), e = new C.EsperaTrasTeclado(r.f);
  e.ver(true); e.ver(false);
  r.t += 2000; assert.ok(e.admite());
  e.ver(true);
  r.t += 3000; e.ver(false); assert.ok(!e.admite());
  r.t += 500; assert.ok(e.admite());
});

// ── 2. La pantalla usa la espera y trae el rediseño ──
const sinEspacios = (s) => s.replace(/\s+/g, ' ');
const H = sinEspacios(HTML);
await caso('pantalla: el OK y «Guardar corrección» pasan por la espera', () => {
  // 19/11: la espera sale de CS.EsperaTrasTeclado si existe y, con un carga-simple.js viejo en caché, del respaldo (test-cache-versiones.mjs).
  assert.match(H, /const _CsEspera = \(CS && typeof CS\.EsperaTrasTeclado === 'function'\) \? CS\.EsperaTrasTeclado : _CsEsperaRespaldo;/);
  assert.match(H, /const _csEspera = CS \? new _CsEspera\(/);
  assert.match(H, /case 'ok': \{ if \(_csEspera && !_csEspera\.admite\(\)\) return;/);
  assert.match(H, /case 'corr-guardar': if \(_csEspera && !_csEspera\.admite\(\)\) return; return csGuardarCorreccion\(\);/);
  // la espera se alimenta en cada pintada del panel, con «escondido por el teclado», antes del return temprano
  const i = H.indexOf('function csPintarPanel()');
  const tramo = H.slice(i, H.indexOf('host.hidden = false;', i));
  assert.match(tramo, /_csEspera\.ver\(porTeclado\)/);
  assert.match(tramo, /const porTeclado = !seVe && !!s && STATE\.scene === 'train' && _csTeclado;/);
});
await caso('pantalla: Enter y tocar afuera sueltan el peso; otro campo de kilos no', () => {
  const inputs = HTML.match(/<input class="cs-(?:carga-num|kg-input)[^>]*>/g) || [];
  assert.equal(inputs.length, 3, 'la carga, el kilo de cada serie y el de la corrección');
  for (const x of inputs) assert.match(x, /enterkeyhint="done"/, x);
  assert.match(H, /if \(e\.key !== 'Enter' \|\| e\.isComposing \|\| !e\.target\.matches \|\| !e\.target\.matches\(campo\)\) return; e\.preventDefault\(\); e\.target\.blur\(\);/);
  assert.match(H, /train\.addEventListener\('keydown', alTecla\); panel\.addEventListener\('keydown', alTecla\);/);
  assert.match(H, /document\.addEventListener\('pointerdown', \(e\) => \{[^}]*t\.closest\(`\$\{campo\},\.cs-carga-campo`\)\) return; soltarPeso\(\); \}, true\);/);
  // sin preventDefault en el toque de afuera: el botón tocado hace lo suyo
  const i = H.indexOf("document.addEventListener('pointerdown'");
  assert.ok(!H.slice(i, i + 400).includes('preventDefault'));
});
await caso('pantalla: «Ahora: serie N de M» y la fila activa resaltada', () => {
  assert.ok(HTML.includes('<b role="heading" aria-level="3" data-cs-serie-ahora><span class="cs-ahora">Ahora:</span> serie ${s.activa + 1} de ${s.series.length}</b>'));
  assert.match(HTML, /\.cs-fila\.is-activa\{[^}]*background:var\(--color-brand-subtle\);box-shadow:inset 0 0 0 2px var\(--color-brand\)\}/);
  assert.ok(HTML.includes('<span class="cs-sr">La que toca ahora.</span>'));
});
await caso('pantalla: el kilo baja a 46/44/40 y el OK vuelve animado (sin animación con «reducir movimiento»)', () => {
  assert.match(HTML, /\.cs-carga-num\{[^}]*font-size:46px/);
  assert.match(HTML, /\.cs-carga-num\.is-l4\{font-size:44px\}/);
  assert.match(HTML, /\.cs-carga-num\.is-l5\{font-size:40px\}/);
  assert.match(HTML, /\.cs-ok\.is-vuelve\{animation:cs-ok-vuelve \.32s/);
  assert.match(HTML, /prefers-reduced-motion:reduce\)\{[^{]*\.cs-ok\.is-vuelve\{animation:none\}/);
});
await caso('pantalla: con web_230 la nota de la semana va arriba de la pauta, en su recuadro', () => {
  const i = H.indexOf('<div class="ex-panel">');
  const panel = H.slice(i, i + 900);
  const nota = panel.indexOf('${web230() ? _notaSemanaHtml(_progNota) : \'\'}');
  const pauta = panel.indexOf('${_metricasHtml(ex,');
  assert.ok(nota > 0 && pauta > nota, 'la nota antes de la pauta');
  assert.ok(panel.includes('${_progNota && !web230() ?'), 'sin la palanca queda como antes');
  assert.match(HTML, /\.ex-nota-semana\{[^}]*background:var\(--color-brand-subtle\);border:1px solid color-mix\(in oklab,var\(--color-brand\) 35%,transparent\)/);
  assert.match(HTML, /\.ex-nota-semana-txt\{font-size:17px/);
});
await caso('service worker: versión nueva de la 2.3.3', () => {
  assert.match(SW, /^const VERSION\s+= 'v\d+-20261119-233';$/m);
});

if (!process.exitCode) console.log(`test-carga-teclado: ${ok} casos ok`);
