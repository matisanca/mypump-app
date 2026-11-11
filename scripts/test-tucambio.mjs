#!/usr/bin/env node
/* =============================================================
 * test-tucambio.mjs — «Tu cambio» (2.3.0) de la web del cliente.
 *
 * Las reglas (`TuCambio`, en public/cliente.html) tienen que dar lo mismo que el iPhone (TuCambioVectoresTests) y
 * Android (TuCambioVectoresTest): se corren TODOS los casos de apps/shared/vectores/tucambio.json contra el código
 * real, que se extrae del HTML por texto (como test-check-guiado.mjs). Además: ningún texto dice lo que no puede decir.
 *
 * USO:  node scripts/test-tucambio.mjs
 * ============================================================= */
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';

const raiz = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const html = fs.readFileSync(path.join(raiz, 'public/cliente.html'), 'utf8');
const V = JSON.parse(fs.readFileSync(path.join(raiz, 'apps/shared/vectores/tucambio.json'), 'utf8'));
const a = html.indexOf('/* ═══ TU CAMBIO · REGLAS (inicio) ═══'), b = html.indexOf('/* ═══ TU CAMBIO · REGLAS (fin) ═══ */');
if (a < 0 || b < 0) { console.error('✗ no encontré las reglas de Tu cambio en cliente.html'); process.exit(1); }
const TC = new Function(`${html.slice(a, b)}\nreturn TuCambio;`)();

let ok = 0, mal = 0;
const caso = (nombre, fn) => { try { fn(); ok++; } catch (e) { mal++; console.log(`  ✗ ${nombre}\n      ${String(e.message).split('\n').slice(0, 8).join('\n      ')}`); } };

caso('textos', () => assert.deepEqual(TC.T, V.textos));
for (const c of V.casos) {
  caso(c.nombre, () => {
    const r = TC.vista({ fotos: c.fotos, inicio: c.inicio, semanaActual: V.semanaActual, pose: c.pose, peso: c.peso.map(([fecha, kg]) => ({ fecha, kg })) });
    assert.deepEqual(r, c.esperado);
  });
}
for (const [f, e] of V.fechas) caso(`fecha ${f}`, () => assert.equal(TC.fecha(f), e));
for (const [p, e] of V.sinFoto) caso(`sinFoto ${p}`, () => assert.equal(TC.sinFoto(p), e));
for (const f of V.fechaLocal) caso(`fechaLocal ${f.iso}`, () => assert.equal(TC.fechaLocal(f.iso, f.zona), f.esperado));

// Lo que se ve de Tu cambio en la página: nada de IA, ciclo, fármacos ni compartir.
const ui = html.slice(html.indexOf('/* ═══ TU CAMBIO · PANTALLA (inicio) ═══'), html.indexOf('/* ═══ TU CAMBIO · PANTALLA (fin) ═══ */'));
caso('la pantalla existe', () => assert.ok(ui.length > 500));
caso('sin palabras prohibidas', () => {
  for (const p of [/\bIA\b/, /inteligencia artificial/i, /\bciclo\b/i, /fármaco/i, /compartir/i, /navigator\.share/, /tu coach/i, /tu entrenador/i]) {
    assert.ok(!p.test(ui) && !p.test(JSON.stringify(TC.T)), `aparece ${p}`);
  }
});

console.log(`${mal ? '✗' : '✓'} tucambio: ${ok} bien, ${mal} mal`);
process.exit(mal ? 1 : 0);
