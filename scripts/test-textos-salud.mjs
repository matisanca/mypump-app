#!/usr/bin/env node
/* =============================================================
 * test-textos-salud.mjs — que la app no le hable de Apple a un Android.
 *
 * POR QUÉ EXISTE
 * Toda la sección de salud se escribió cuando MyPump era solo de iPhone. En un
 * Android decía "Salud de Apple", "iPhone y Apple Watch", "Conectar Apple
 * Health", y mandaba a Ajustes → Salud, que en Android no existe. El cliente
 * leía instrucciones de un teléfono que no tiene y no encontraba una sola de
 * las pantallas que se le nombraban.
 *
 * No fue un descuido puntual: eran QUINCE lugares. Con eso, arreglarlos una vez
 * no alcanza — el próximo que escriba un texto nuevo va a poner "iPhone" otra
 * vez, porque es lo que hay alrededor. Este test es lo que convierte eso en un
 * error de build en vez de en una captura de pantalla de un cliente enojado.
 *
 * USO:  node scripts/test-textos-salud.mjs
 * ============================================================= */

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const raiz = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const src = fs.readFileSync(path.join(raiz, 'public/cliente.html'), 'utf8');

let pasaron = 0, fallaron = 0;
const test = (nombre, fn) => {
  try { fn(); console.log(`  ✓ ${nombre}`); pasaron++; }
  catch (e) { console.error(`  ✗ ${nombre}\n      ${e.message}`); fallaron++; }
};
const iguales = (a, b, m) => { if (a !== b) throw new Error(`${m}\n      esperaba: ${b}\n      recibí:   ${a}`); };
const cierto  = (c, m) => { if (!c) throw new Error(m); };

// ── Sacar la tabla del fuente, no una copia ─────────────────────────────
/* Se evalúa el literal real de cliente.html. Una copia tipeada acá se
 * desincroniza y el test pasa a mentir, que es peor que no tenerlo. */
const m = /const _TXT_SALUD = (\{[\s\S]*?\n\});/.exec(src);
if (!m) {
  console.error('✗ no encontré `const _TXT_SALUD = {...}` en cliente.html.\n' +
                '  Si lo renombraste, actualizá este test: sin la tabla no se valida NADA.');
  process.exit(1);
}
const TXT = new Function(`return ${m[1]}`)();

console.log('\nVocabulario de salud por plataforma');

test('están las dos plataformas', () => {
  cierto(TXT.ios && TXT.android, 'falta ios o android en _TXT_SALUD');
});

test('las dos tienen exactamente las mismas claves', () => {
  const a = Object.keys(TXT.ios).sort(), b = Object.keys(TXT.android).sort();
  // Una clave que exista solo en ios devuelve undefined en Android y la UI
  // renderiza el string "undefined" al cliente.
  iguales(a.join(','), b.join(','), 'las claves no coinciden');
});

test('ningún texto queda vacío', () => {
  for (const p of ['ios', 'android'])
    for (const [k, v] of Object.entries(TXT[p]))
      cierto(typeof v === 'string' && v.trim().length > 0, `${p}.${k} está vacío`);
});

test('el vocabulario de Android no nombra Apple, iPhone ni Apple Watch', () => {
  const sucios = Object.entries(TXT.android)
    .filter(([, v]) => /apple|iphone|ipad|watchos/i.test(v));
  iguales(sucios.map(([k]) => k).join(', ') || '(ninguno)', '(ninguno)',
          'hay claves de Android que nombran productos de Apple');
});

test('el vocabulario de iOS no nombra Health Connect ni Android', () => {
  const sucios = Object.entries(TXT.ios)
    .filter(([, v]) => /health connect|android|samsung|galaxy/i.test(v));
  iguales(sucios.map(([k]) => k).join(', ') || '(ninguno)', '(ninguno)',
          'hay claves de iOS que nombran cosas de Android');
});

// ── Lo que de verdad importa: que no queden textos cableados ────────────
console.log('\nNingún texto de Apple cableado fuera de la tabla');

/* Se recorren solo los literales que pueden llegar a la pantalla: contenido de
 * template strings y de comillas dentro de asignaciones de HTML. Los
 * comentarios y los nombres de función (renderAppleHealthEstado) no cuentan. */
function lineasVisibles(texto) {
  const out = [];
  texto.split('\n').forEach((l, i) => {
    const t = l.trim();
    if (t.startsWith('//') || t.startsWith('*') || t.startsWith('/*')) return;
    out.push({ n: i + 1, l });
  });
  return out;
}

// La tabla misma queda excluida: ahí los textos de Apple son correctos.
const desde = src.indexOf('const _TXT_SALUD');
const hasta = src.indexOf('const _T =', desde);
const sinTabla = src.slice(0, desde) + src.slice(hasta);

const PROHIBIDO = /(Salud de Apple|Apple Salud|Conectar Apple Health|iPhone y Apple Watch|app Salud del iPhone|app de iPhone|Este iPhone no tiene)/;

test('no queda copy de Apple cableada en la UI', () => {
  const malas = lineasVisibles(sinTabla)
    .filter(({ l }) => PROHIBIDO.test(l))
    // El rótulo del diagnóstico (?diag=health) es una pantalla interna de Mati,
    // no del cliente, y solo se abre escribiendo la URL a mano.
    .filter(({ l }) => !/Diagnóstico Apple Health/.test(l))
    // La rama de iOS del ternario de wearables es correcta.
    .filter(({ l }) => !/_esAndroid\(\)/.test(l));
  iguales(malas.map(({ n }) => `línea ${n}`).join(', ') || '(ninguna)', '(ninguna)',
          'hay textos de Apple cableados; usá _T(clave) en vez de escribirlos');
});

test('_T() se usa de verdad en la UI', () => {
  const usos = (sinTabla.match(/_T\('/g) || []).length;
  cierto(usos >= 10, `_T() se usa solo ${usos} veces; se esperaban 10 o más. ` +
                     '¿Se revirtió el reemplazo?');
});

test('_esAndroid() no depende solo de Capacitor', () => {
  // Si mira únicamente window.Capacitor, en el banco de pruebas (que simula el
  // plugin, no Capacitor entero) devolvería 'ios' y no se probaría nada.
  const fn = /function _esAndroid\(\)[\s\S]*?\n\}/.exec(sinTabla);
  cierto(fn, 'no encontré _esAndroid()');
  cierto(/MyPumpHealth/.test(fn[0]),
         '_esAndroid() debería preguntarle primero al bridge (MyPumpHealth.plataforma)');
});

console.log(`\n${pasaron} pasaron, ${fallaron} fallaron`);
process.exit(fallaron ? 1 : 0);
