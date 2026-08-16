#!/usr/bin/env node
/* =============================================================
 * check-escenas.mjs — que el tabbar, las escenas y ?scene= hablen el mismo idioma.
 *
 * POR QUÉ EXISTE
 * Los ids de las escenas son en INGLÉS (`scene-train`, `scene-diet`,
 * `scene-progress`) y lo que se lee en el tabbar es en español (Entreno, Dieta,
 * Progreso). Es una trampa fácil: al agregar `?scene=` se escribió una lista a
 * mano con los nombres visibles —'dieta', 'rutina', 'progreso'— y ninguno
 * existía.
 *
 * Y setScene no falla suave: apaga TODAS las escenas y prende la que matchea.
 * Un nombre inválido no "no hace nada", deja la app EN BLANCO — header y
 * tabbar, y nada en el medio. El cliente ve una app rota.
 *
 * USO:  node scripts/check-escenas.mjs
 * ============================================================= */

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const raiz = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const src = fs.readFileSync(path.join(raiz, 'public/cliente.html'), 'utf8');

let fallas = 0;
const fallar = (m) => { console.error(`  ✗ ${m}`); fallas++; };

// Del markup, no de una lista tipeada acá.
const escenas = [...src.matchAll(/id="scene-([a-z]+)"/g)].map((m) => m[1]);
const tabs = [...src.matchAll(/data-scene="([a-z]+)"/g)].map((m) => m[1]);

console.log(`\nescenas en el markup: ${escenas.join(', ')}`);
console.log(`tabs del tabbar:      ${tabs.join(', ')}`);

console.log('\n1. Cada tab apunta a una escena que existe');
const huerfanos = tabs.filter((t) => !escenas.includes(t));
if (huerfanos.length) {
  fallar(`estos tabs apuntan a escenas inexistentes: ${huerfanos.join(', ')}\n` +
         '      Al tocarlos, setScene apaga todo y la app queda en blanco.');
} else {
  console.log(`   ✓ los ${tabs.length} tabs resuelven`);
}

console.log('\n2. ?scene= saca las válidas del DOM, no de una lista tipeada');
const fn = /function _aplicarSceneDeURL\(\)[\s\S]*?\n\}/.exec(src);
if (!fn) {
  fallar('no encontré _aplicarSceneDeURL(). ¿Se renombró? Sin ella, ?scene= no se valida.');
} else {
  const cuerpo = fn[0];
  if (!/\$\$\('\.scene'\)/.test(cuerpo)) {
    fallar('_aplicarSceneDeURL no deriva la lista del DOM.\n' +
           '      Una lista a mano se desincroniza de los ids y deja la app en blanco:\n' +
           '      usá $$(\'.scene\').map(e => e.id.replace(/^scene-/, \'\')).');
  } else {
    console.log('   ✓ la lista sale de $$(\'.scene\')');
  }
  // Una lista literal de escenas dentro de la función es justo el bug de origen.
  const literal = /\[\s*'(?:myday|train|diet|progress|revision|salud|rutina|dieta|progreso)'/.test(cuerpo);
  if (literal) fallar('hay una lista de escenas escrita a mano dentro de _aplicarSceneDeURL');
}

console.log('\n3. Se aplica DESPUÉS de que haya datos');
// Antes se llamaba al parsear el script: cambiaba de escena antes de que la
// carga async trajera rutina y dieta, y el cliente aterrizaba en una pantalla
// vacía. Tiene que ir después de renderDiet().
const iRender = src.indexOf('  renderDiet();');
const iScene = src.indexOf('_aplicarSceneDeURL();');
if (iRender < 0 || iScene < 0) {
  fallar('no encuentro renderDiet() o la llamada a _aplicarSceneDeURL()');
} else if (iScene < iRender) {
  fallar('_aplicarSceneDeURL() se llama ANTES de renderDiet(): la escena se aplica\n' +
         '      sobre datos que todavía no llegaron y la pantalla sale vacía.');
} else {
  console.log('   ✓ se llama después de renderDiet()');
}

console.log('\n4. El selector de dias no se cuela en otras escenas');
// Bug visto en una captura de tienda: el day picker aparecia ENCIMA del chat.
// setScene lo esconde, pero renderDayPicker corre despues (cuando llegan los
// datos) y lo volvia a mostrar con un `hidden = false` pelado. Al entrar por
// deep link ?scene=chat — que es justo como llega el push — el orden es
// siempre ese, asi que el bug era 100% reproducible en la pantalla estrella.
{
  const i = src.indexOf('function renderDayPicker()');
  const cuerpo = i < 0 ? '' : src.slice(i, i + 2000);
  if (i < 0) {
    fallar('no encuentro renderDayPicker()');
  } else if (/picker\.hidden\s*=\s*false/.test(cuerpo)) {
    fallar('renderDayPicker() hace `picker.hidden = false` sin mirar la escena.\n' +
           '      Se cuela encima del chat/dieta/revision cuando el render corre\n' +
           '      despues de setScene. Tiene que ser hidden = STATE.scene !== \'train\'.');
  } else if (!/picker\.hidden\s*=\s*STATE\.scene\s*!==\s*'train'/.test(cuerpo)) {
    fallar('renderDayPicker() no condiciona la visibilidad del picker a la escena train');
  } else {
    console.log('   ✓ solo se muestra en Entreno');
  }
}

console.log('');
if (fallas) { console.error(`✗ ${fallas} problema(s) en el ruteo de escenas\n`); process.exit(1); }
console.log('✓ tabbar, escenas y ?scene= coinciden\n');
