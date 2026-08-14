#!/usr/bin/env node
/* =============================================================
   test-popup-descarga.mjs — el cartel de "descargá la app"

   POR QUÉ EXISTE
   El pop-up es intrusivo a propósito: ocupa la pantalla entera y es lo único
   que puede mover la aguja de instalaciones, que hoy está en cero (la tabla
   `mypump_push_devices` está vacía: los 62 clientes usan la app como link del
   navegador, así que no hay un solo teléfono al que se le pueda tocar el
   timbre).

   Justamente porque es intrusivo, las condiciones para mostrarlo tienen que ser
   exactas. Los dos modos de fallar son caros y ninguno da error:

   · Mostrarlo de más — a alguien que YA instaló, o adentro de la app nativa.
     "Descargá la app" adentro de la app es la clase de detalle que hace que un
     cliente deje de confiar en lo que lee.
   · No mostrarlo nunca — con un chequeo de iOS de más, en el iPad no aparece,
     y nadie se entera de que no aparece.

   EL CASO QUE MÁS FÁCIL SE ROMPE
   iPadOS 13+ manda un user agent que dice "Macintosh". Un `/iPad/.test(ua)`
   solo, que es lo primero que uno escribe, deja a todos los iPad afuera para
   siempre y sin una sola señal.

   USO:  node scripts/test-popup-descarga.mjs
   ============================================================= */

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const raiz = path.join(path.dirname(fileURLToPath(import.meta.url)), '..');
const html = fs.readFileSync(path.join(raiz, 'public/cliente.html'), 'utf8');

// ── Extraer la función real del HTML ────────────────────────────────────
// A propósito no se copia el cuerpo acá: si se copiara, el test seguiría verde
// después de que alguien rompa la versión que corre de verdad.
const m = html.match(/function dlCorresponde\(\) \{[\s\S]*?\n\}/);
if (!m) {
  console.error('✗ no se encontró dlCorresponde() en cliente.html — ¿la renombraron?');
  process.exit(1);
}
const CUERPO = m[0];

// Las constantes también salen del archivo, no del test. Escribirlas acá a mano
// parece inofensivo y no lo es: alguien pone DL_DIAS = 0 "para probar", se lo
// olvida puesto, el pop-up pasa a reaparecer en cada recarga, y el test que
// existe justamente para eso sigue en verde porque estaba mirando su propia
// copia del número.
const mc = html.match(/const DL_KEY\s*=\s*'([^']+)';\s*\nconst DL_DIAS\s*=\s*(\d+);/);
if (!mc) {
  console.error('✗ no se encontraron DL_KEY / DL_DIAS en cliente.html');
  process.exit(1);
}
const [, DL_KEY, DL_DIAS_TXT] = mc;
const DL_DIAS = Number(DL_DIAS_TXT);

const UA_IPHONE = 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_2 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.2 Mobile/15E148 Safari/604.1';
const UA_IPADOS = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15';
const UA_MAC    = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0 Safari/537.36';
const UA_ANDROID= 'Mozilla/5.0 (Linux; Android 14; SM-S911B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0 Mobile Safari/537.36';

/* Corre la función real dentro de un entorno fabricado. `ahora` permite mover
   el reloj sin dormir el test. */
function correr({ ua, touch = 0, standalone = undefined, displayMode = false, nativo = false, pospuesto = 0, ahora = 1_700_000_000_000 }) {
  const ctx = {
    navigator: { userAgent: ua, maxTouchPoints: touch, standalone },
    matchMedia: (q) => ({ matches: /standalone/.test(q) ? displayMode : false }),
    Capacitor: nativo ? { isNativePlatform: () => true } : undefined,
    localStorage: { getItem: (k) => (k === DL_KEY && pospuesto ? String(pospuesto) : null) },
    Date: { now: () => ahora },
  };
  ctx.window = ctx;
  // DL_KEY y DL_DIAS entran como PARÁMETROS con el valor leído del archivo.
  const fn = new Function('window', 'navigator', 'localStorage', 'Date', 'DL_KEY', 'DL_DIAS', `
    ${CUERPO}
    return dlCorresponde();
  `);
  return fn(ctx, ctx.navigator, ctx.localStorage, ctx.Date, DL_KEY, DL_DIAS);
}

// ── Framework ───────────────────────────────────────────────────────────
let ok = 0, fail = 0;
const t = (n, fn) => {
  try { fn(); console.log(`  ✓ ${n}`); ok++; }
  catch (e) { console.log(`  ✗ ${n}\n      ${e.message}`); fail++; }
};
const si = (r, m) => { if (r !== true)  throw new Error(`${m}: debía mostrarse y no se mostró`); };
const no = (r, m) => { if (r !== false) throw new Error(`${m}: NO debía mostrarse y se mostró`); };

console.log('\n=== Pop-up de descarga ===\n');

// ── Los que SÍ ──────────────────────────────────────────────────────────
t('iPhone en Safari, sin instalar → se muestra', () => {
  si(correr({ ua: UA_IPHONE, touch: 5 }), 'iPhone web');
});

t('iPad con iPadOS 13+, que dice ser una Mac → se muestra igual', () => {
  // El caso que se rompe solo: el UA no tiene "iPad" por ningún lado.
  si(correr({ ua: UA_IPADOS, touch: 5 }), 'iPad web');
});

t('pasaron más de 3 días desde que lo cerró → vuelve', () => {
  const ahora = 1_700_000_000_000;
  si(correr({ ua: UA_IPHONE, touch: 5, pospuesto: ahora - 4 * 86400000, ahora }), 'a los 4 días');
});

// ── Los que NO ──────────────────────────────────────────────────────────
t('adentro de la app nativa → nunca', () => {
  no(correr({ ua: UA_IPHONE, touch: 5, nativo: true }), 'Capacitor');
});

t('ya la agregó a la pantalla de inicio (navigator.standalone) → nunca', () => {
  no(correr({ ua: UA_IPHONE, touch: 5, standalone: true }), 'standalone de Safari');
});

t('instalada según el estándar (display-mode) → nunca', () => {
  // El otro camino. Si se mira uno solo de los dos, a alguien que ya instaló le
  // sigue apareciendo el cartel que le pide instalar.
  no(correr({ ua: UA_IPHONE, touch: 5, standalone: undefined, displayMode: true }), 'display-mode');
});

t('Android → no (Play todavía no está aprobado)', () => {
  no(correr({ ua: UA_ANDROID, touch: 5 }), 'Android');
});

t('Mac de escritorio → no (el link del App Store no le sirve)', () => {
  // Misma cadena "Macintosh" que el iPad; lo que los separa es el touch.
  no(correr({ ua: UA_MAC, touch: 0 }), 'Mac');
});

t('lo cerró hace 1 hora → no lo ve de nuevo', () => {
  const ahora = 1_700_000_000_000;
  no(correr({ ua: UA_IPHONE, touch: 5, pospuesto: ahora - 3600000, ahora }), 'al ratito');
});

t('la espera configurada es de varios días, no de cero', () => {
  // Sin este piso, un DL_DIAS = 0 olvidado hace que el cartel salte en CADA
  // recarga: el "seguir en el navegador" deja de tener efecto y la app se
  // vuelve inusable justo para el que eligió no instalarla.
  if (!(DL_DIAS >= 1)) throw new Error(`DL_DIAS = ${DL_DIAS}: el pop-up reaparecería sin descanso`);
});

// ── El markup y el link ─────────────────────────────────────────────────
t('el botón apunta al App Store de MyPump', () => {
  const esperado = 'https://apps.apple.com/ar/app/mypump/id6793259380';
  if (!html.includes(esperado)) throw new Error(`no está el link ${esperado}`);
});

t('tiene salida: existe el botón de seguir en el navegador', () => {
  // Sin salida, un cliente parado en el gimnasio con la serie a medio cargar
  // queda trabado. Se pierde más de lo que gana la instalación.
  if (!/id="dlSalir"/.test(html)) throw new Error('falta #dlSalir');
  if (!/Seguir en el navegador/.test(html)) throw new Error('falta el texto de salida');
});

t('vive FUERA de #appRoot', () => {
  // Esto ya pasó: el markup quedó adentro de `<div class="app" id="appRoot" hidden>`
  // y heredó su `hidden`. El elemento existía, el CSS estaba aplicado, el
  // `hidden` propio decía false — y medía 0×0. Nada tira error: simplemente el
  // cartel no se ve nunca y las instalaciones siguen en cero.
  const iApp = html.indexOf('</div><!-- /app -->');
  const iDl  = html.indexOf('id="dlBack"');
  if (iApp === -1) throw new Error('no se encontró el cierre de #appRoot');
  if (iDl === -1)  throw new Error('no se encontró #dlBack');
  if (iDl < iApp)  throw new Error('#dlBack está adentro de #appRoot: hereda su hidden y no se muestra nunca');
});

t('arranca oculto en el HTML', () => {
  // Si el markup no viniera con `hidden`, se vería un instante en TODAS las
  // plataformas antes de que corra el JS — incluida la app nativa.
  if (!/<div class="dl-back" id="dlBack" hidden>/.test(html)) throw new Error('#dlBack no arranca con hidden');
});

console.log(`\n${fail === 0 ? '✅' : '❌'}  ${ok} pasaron, ${fail} fallaron\n`);
process.exit(fail === 0 ? 0 : 1);
