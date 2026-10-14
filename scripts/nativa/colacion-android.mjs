#!/usr/bin/env node
/* =============================================================
   colacion-android.mjs — las tablas de ColacionEspanol.kt (Android) desde Intl.Collator('es')

   La web ordena los sustitutos de ejercicio con `localeCompare(…, 'es')` (ICU dentro de V8). En Android no se puede usar
   java.text.Collator: en la JVM de los tests es el de OpenJDK (ignora el espacio y la puntuación) y en el teléfono es el
   ICU del sistema, que cambia con la versión de Android. ColacionEspanol.kt implementa la comparación de UCA en Kotlin
   puro con estas tablas: los grupos de igualdad primaria (con su variante secundaria y terciaria) de ASCII, Latin-1,
   Latin Extended-A, la puntuación general y algunos símbolos, y el orden secundario de las marcas combinantes.

   Reescribe el bloque entre los marcadores "── Tablas:" y "── Fin de las tablas generadas." del .kt. Después de
   correrlo: `cd apps/android && ./gradlew :core:reglas:test` (el vector `orden` tiene que seguir pasando).

   Uso: node scripts/nativa/colacion-android.mjs
   ============================================================= */

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const RAIZ = path.join(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const KT = path.join(RAIZ, 'apps/android/core/reglas/src/main/kotlin/com/pumpteam/mypump/reglas/ColacionEspanol.kt');

const base = new Intl.Collator('es', { sensitivity: 'base' });
const acento = new Intl.Collator('es', { sensitivity: 'accent' });
const variante = new Intl.Collator('es');
const rango = (a, b) => Array.from({ length: b - a + 1 }, (_, i) => String.fromCodePoint(a + i));

const repertorio = [
  ...rango(0x09, 0x0d), ' ', '\u0085', ' ', ' ', ...rango(0x2000, 0x200a), ' ', ' ', ' ', ' ', '　',
  ...rango(0x21, 0x7e), ...rango(0xa1, 0xff), ...rango(0x100, 0x17f), ...rango(0x2010, 0x2027), ...rango(0x2030, 0x205e),
  '€', '™', '←', '→', '✓',
].filter((c, i, a) => a.indexOf(c) === i);

// Solo los caracteres que NFD no descompone: los demás (á, ñ…) los arma el .kt con la letra y la marca.
const baseChars = repertorio.filter((c) => c.normalize('NFD') === c);
const ignorables = baseChars.filter((c) => variante.compare('a' + c + 'b', 'ab') === 0);
// Pesan como varios caracteres: el .kt los expande a mano (ß → ss, ½ → 1⁄2…).
const expansiones = ['¼', '½', '¾', 'ß', 'ŉ'];
const simples = baseChars.filter((c) => !ignorables.includes(c) && !expansiones.includes(c));
const orden = [...simples].sort((a, b) => variante.compare(a, b) || (a < b ? -1 : 1));
const grupos = [];
for (const c of orden) {
  const g = grupos[grupos.length - 1];
  if (g && base.compare(g[0], c) === 0) g.push(c); else grupos.push([c]);
}
const filas = grupos.map((g) => {
  let s = 0, t = 0;
  const sec = [], ter = [];
  g.forEach((c, i) => {
    if (i > 0 && acento.compare(g[i - 1], c) !== 0) { s++; t = 0; } else if (i > 0 && variante.compare(g[i - 1], c) !== 0) t++;
    sec.push(s); ter.push(t);
  });
  return { g: g.join(''), sec: sec.join(''), ter: ter.join('') };
});

// Marcas combinantes con peso solo secundario (U+0363–U+036F, las letras latinas combinantes, pesan como letras en ICU:
// en el .kt caen como caracteres desconocidos).
const marcas = rango(0x300, 0x36f)
  .filter((m) => m.normalize('NFD') === m && acento.compare('a' + m, 'a') !== 0 && base.compare('a' + m, 'a') === 0)
  .sort((x, y) => acento.compare('a' + x, 'a' + y) || (x < y ? -1 : 1));
const gruposMarcas = [];
for (const m of marcas) {
  const g = gruposMarcas[gruposMarcas.length - 1];
  if (g && acento.compare('a' + g[0], 'a' + m) === 0) g.push(m); else gruposMarcas.push([m]);
}

const esc = (s) => [...s].map((c) => '\\u' + c.charCodeAt(0).toString(16).toUpperCase().padStart(4, '0')).join('');
const bloque = [
  "    // ── Tablas: las genera scripts/nativa/colacion-android.mjs desde Intl.Collator('es') de node. No editar a mano. ──",
  `    // node ${process.versions.node} · ICU ${process.versions.icu} · CLDR ${process.versions.cldr}`,
  '    private val GRUPOS = arrayOf(',
  ...filas.map((f) => `        Grupo("${esc(f.g)}", "${f.sec}", "${f.ter}"),`),
  '    )',
  '    private val MARCAS = arrayOf(',
  ...gruposMarcas.map((g) => `        "${esc(g.join(''))}",`),
  '    )',
  `    private const val IGNORABLES = "${esc(ignorables.join(''))}"`,
  '    // ── Fin de las tablas generadas. ──',
].join('\n');

const kt = fs.readFileSync(KT, 'utf8');
const ini = kt.indexOf('    // ── Tablas:');
const finMarca = '    // ── Fin de las tablas generadas. ──';
const fin = kt.indexOf(finMarca);
if (ini < 0 || fin < 0) throw new Error('no encuentro los marcadores de las tablas en ColacionEspanol.kt');
fs.writeFileSync(KT, kt.slice(0, ini) + bloque + kt.slice(fin + finMarca.length));
console.log(`▸ ColacionEspanol.kt: ${filas.length} grupos primarios, ${gruposMarcas.length} grupos de marcas, ICU ${process.versions.icu}`);
