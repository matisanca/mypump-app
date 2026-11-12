#!/usr/bin/env node
// 2.3.1: los reemplazos de comida no suben las kcal en silencio (window.MyPump.reemplazosKcal de public/js/app.js).
// Mismos vectores que iOS y Android (apps/shared/vectores/reemplazos_kcal.json).
import fs from 'node:fs';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
globalThis.window = { MyPump: {} };
require('../public/js/app.js');
const R = globalThis.window.MyPump.reemplazosKcal;
const V = JSON.parse(fs.readFileSync(new URL('./vectores-app/reemplazos_kcal.json', import.meta.url)));
let n = 0;

assert.equal(R.USAR_IGUAL, V.textos.usarIgual);
assert.equal(R.ELEGIR_OTRO, V.textos.elegirOtro);
assert.equal(R.DESHACER, V.textos.deshacer);
for (const c of V.ordenar) {
  const subs = c.subs.map(s => ({ name: s.nombre, kcal: s.kcal, _universal: s.universal, _isCustom: s.propio }));
  const o = R.ordenar(subs, c.kcalOriginal);
  assert.deepEqual(o.universales.map(s => s.name), c.universales, c.nombre);
  assert.deepEqual(o.resto.map(s => s.name), c.resto, c.nombre);
  n++;
}
for (const c of V.confirmar) {
  const k = `${c.kcalOriginal}→${c.kcalReemplazo}`;
  assert.equal(R.desvioPct(c.kcalOriginal, c.kcalReemplazo), c.desvioPct, k);
  assert.equal(R.pideConfirmacion(c.kcalOriginal, c.kcalReemplazo), c.pide, k);
  assert.equal(R.suma(c.kcalOriginal, c.kcalReemplazo), c.suma, k);
  if (c.texto) assert.equal(R.textoConfirmacion(c.kcalOriginal, c.kcalReemplazo), c.texto, k);
  n++;
}
for (const c of V.renglon) { assert.equal(R.renglon(c.suma), c.texto, String(c.suma)); n++; }

// La hoja y la cabecera usan las reglas (no un cálculo propio).
const html = fs.readFileSync(new URL('../public/cliente.html', import.meta.url), 'utf8');
assert.match(html, /reemplazosKcal\.desvioPct\(food\.kcal, s\.kcal\)/);
assert.match(html, /'sin dato'/);
assert.match(html, /reemplazosKcal\.ordenar\(subs, food\.kcal\)/);
assert.match(html, /RK\.pideConfirmacion\(original\.kcal, sub\.kcal\)/);
assert.match(html, /reemplazosKcal\.renglon\(_reemplazosDelDia\(\)\.suma\)/);
assert.match(html, /data-reemp-deshacer/);
assert.doesNotMatch(html, /origKcal > 0 \? Math\.round/);
n += 7;
console.log(`test-reemplazos: ${n} casos OK`);
