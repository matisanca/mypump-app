#!/usr/bin/env node
/* =============================================================
   vectores-ejercicios.mjs — sustitución de ejercicios: la web es la fuente de verdad

   Corre las funciones REALES de origin/main (window.MyPump.exerciseSwap de public/js/app.js,
   getEffectiveEx y exGetSubs de public/cliente.html) y escribe {entrada, salida}. Los tests de
   la nativa (Swift Testing; JUnit en Android) leen los mismos archivos y exigen igualdad total.
   Los desvíos a propósito se declaran en apps/shared/vectores/excepciones-ejercicios.json.

   1. Catálogo: GET público de mypump_ejercicios_catalogo con la anon key de config.js y las
      mismas columnas que getCatalogoEjercicios. Va a apps/shared/catalogo-ejercicios.json
      ordenado por slug_en, para que el archivo no cambie entre corridas (la nativa lo empaqueta
      como respaldo offline). Con --sin-red se usa el que ya está.
      OJO: el orden del catálogo es parte de la entrada. _toEs colapsa variantes en el mismo
      nombre y findSubstitutes se queda con la PRIMERA de cada nombre+equipo; el alias de
      _resolve también se queda con la primera. La web usa el orden en que responde el servidor
      (sin ORDER BY); los vectores, el del archivo. El script avisa cuántas listas cambian.
   2. Vectores (el catálogo se referencia por índice para que el archivo no repita las URLs):
      - traducciones: _toEs y _equipLabel de cada fila, más entradas armadas a propósito;
      - orden: localeCompare(…, 'es'), el desempate de findSubstitutes;
      - nombres: _norm, _resolveByRules y _resolve por nombre;
      - listas: findSubstitutes de CADA fila del catálogo (todas las listas posibles) y las que
        cambian si el catálogo viene al revés;
      - casos: por ejercicio, _resolve, findSubstitutes, getEffectiveEx y exGetSubs, con y sin
        una sustitución aplicada; y exGetSubs sobre objetos con _orig* armados a mano;
      - sintetico: un catálogo armado a mano con lo que el real hoy no ejercita (el tope de 30,
        slugs repetidos, alias contra name_normalized, null === null, filas sin foto…).

   Corpus público (se commitea): fixtures de las cuentas de prueba, la demo y ejercicios
   difíciles a propósito. Privado (nunca se commitea): los ejercicios de los planes reales y los
   nombres registrados, si están en ~/Developer/nativa-evidencia/privado/estructuras/.

   Salidas: apps/shared/catalogo-ejercicios.json, apps/shared/vectores/sustitutos_ejercicio.json
   y privado/vectores/sustitutos_ejercicio.json

   Uso: node scripts/nativa/vectores-ejercicios.mjs [--sin-red]
   ============================================================= */

import { execFileSync } from 'node:child_process';
import crypto from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const RAIZ = path.join(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const PRIVADO = path.join(os.homedir(), 'Developer', 'nativa-evidencia', 'privado');
const REF = process.env.VECTORES_REF || 'origin/main';
const SIN_RED = process.argv.includes('--sin-red');

process.env.TZ = 'America/Argentina/Buenos_Aires';
const mostrar = (ruta) => execFileSync('git', ['show', `${REF}:${ruta}`], { cwd: RAIZ, maxBuffer: 64 * 1024 * 1024 }).toString();
const APP = mostrar('public/js/app.js');
const HTML = mostrar('public/cliente.html');
const commit = execFileSync('git', ['rev-parse', '--short', REF], { cwd: RAIZ }).toString().trim();
const leer = (p) => JSON.parse(fs.readFileSync(p, 'utf8'));

/** Corta desde `function <nombre>(` hasta la llave que la cierra (mismo método que generar-vectores.mjs). */
function extraer(nombre) {
  const i = HTML.indexOf(`function ${nombre}(`);
  if (i < 0) throw new Error(`no encontré function ${nombre}( en cliente.html@${REF}`);
  let prof = 0;
  for (let k = HTML.indexOf('{', i); k < HTML.length; k++) {
    if (HTML[k] === '{') prof++;
    else if (HTML[k] === '}' && --prof === 0) return HTML.slice(i, k + 1);
  }
  throw new Error(`function ${nombre} sin cierre`);
}

// ── Catálogo ─────────────────────────────────────────────────────────
// Columnas y orden de claves de getCatalogoEjercicios (public/js/supabase-client.js).
const COLUMNAS = ['slug_en', 'name_en', 'name_normalized', 'aliases_es', 'primary_muscle', 'equipment', 'patron_movimiento', 'image_eccentric', 'image_concentric'];
const ARCHIVO_CATALOGO = path.join(RAIZ, 'apps/shared/catalogo-ejercicios.json');
const fila = (f) => Object.fromEntries(COLUMNAS.map((c) => [c, f[c] === undefined ? null : f[c]]));
const porSlug = (a, b) => (a.slug_en < b.slug_en ? -1 : a.slug_en > b.slug_en ? 1 : 0);

async function bajarCatalogo() {
  const config = mostrar('public/js/config.js');
  const url = /SUPABASE_URL:\s*'([^']+)'/.exec(config)[1];
  const anon = /SUPABASE_ANON_KEY:\s*'([^']+)'/.exec(config)[1];
  const r = await fetch(`${url}/rest/v1/mypump_ejercicios_catalogo?select=${COLUMNAS.join(',')}`, {
    headers: { apikey: anon, Authorization: `Bearer ${anon}`, Prefer: 'count=exact' },
  });
  if (!r.ok) throw new Error(`GET del catálogo: ${r.status} ${await r.text()}`);
  const filas = await r.json();
  const total = Number((r.headers.get('content-range') || '').split('/')[1]);
  // supabase-js tampoco pagina: si el servidor recorta (max-rows), la web ve las mismas filas que acá.
  if (total && total !== filas.length) console.warn(`⚠ el catálogo tiene ${total} filas y el GET trajo ${filas.length}`);
  return filas.map(fila);
}

const delServidor = SIN_RED ? null : await bajarCatalogo();
const catalogo = delServidor ? [...delServidor].sort(porSlug) : leer(ARCHIVO_CATALOGO);
if (delServidor) fs.writeFileSync(ARCHIVO_CATALOGO, '[\n' + catalogo.map((f) => JSON.stringify(f)).join(',\n') + '\n]\n');
const sha256 = crypto.createHash('sha256').update(fs.readFileSync(ARCHIVO_CATALOGO)).digest('hex');
const indice = new Map(catalogo.map((e, i) => [e.slug_en, i]));

// ── Funciones de la web ──────────────────────────────────────────────
const win = {};
new Function('window', APP)(win);   // app.js solo define objetos: el DOM queda adentro de funciones que acá no se llaman
const swap = win.MyPump.exerciseSwap;
const STATE = { exerciseSwaps: {} };
const cache = {};
const web = new Function('window', 'STATE', '_exSwapCache',
  `${extraer('getEffectiveEx')}\n${extraer('exGetSubs')}\nreturn { getEffectiveEx, exGetSubs };`)(win, STATE, cache);
/** Lo que hace loadEjercicioCatalogo al llegar las filas: reemplaza el catálogo y vacía la caché de sustitutos. */
function usar(db) {
  win.MYPUMP_EJERCICIO_DB = db;
  for (const k of Object.keys(cache)) delete cache[k];
}
usar(catalogo);

// ── (a) Traducciones ─────────────────────────────────────────────────
const traducciones = catalogo.map((e) => [swap._toEs(e), swap._equipLabel(e)]);

/** Las alternativas de primer nivel de una regex (`a|b(c|d)` → `a`, `b(c|d)`). */
function alternativas(fuente) {
  const out = [];
  let prof = 0, clase = false, actual = '';
  for (let i = 0; i < fuente.length; i++) {
    const c = fuente[i];
    if (c === '\\') { actual += c + fuente[++i]; continue; }
    if (clase) { if (c === ']') clase = false; }
    else if (c === '[') clase = true;
    else if (c === '(') prof++;
    else if (c === ')') prof--;
    else if (c === '|' && prof === 0) { out.push(actual); actual = ''; continue; }
    actual += c;
  }
  return [...out, actual];
}
/** Un texto que la alternativa describe (`remo.*polea.*sentad` → `remo polea sentad`). Puede que lo agarre una regla
 *  anterior: mejor, así se prueba también el orden de las listas. */
const ejemplo = (alt) => alt.replace(/\\b/g, '').replace(/\.[*?+]/g, ' ').replace(/\(([^()|]*)(\|[^()]*)?\)\??/g, '$1')
  .replace(/\[(.)[^\]]*\]\??/g, '$1').replace(/\\(.)/g, '$1').replace(/\?/g, '').replace(/^\^|\$$/g, '');
const ejemplosDe = (reglas) => reglas.flatMap(([re]) => alternativas(re.source).map(ejemplo));

function entradasSinteticas() {
  const fuera = (name_en, extra = {}) => ({ slug_en: 'Sintetico', name_en, equipment: null, ...extra });
  const bases = ejemplosDe(swap._BASE_ES);
  const equipos = ejemplosDe(swap._EQUIP_ES);
  const mods = ejemplosDe(swap._MOD_ES);
  return [
    ...bases.map((b) => fuera(b)),
    ...bases.map((b) => fuera(b.replace(/\b\w/g, (l) => l.toUpperCase()))),
    ...equipos.flatMap((q) => [fuera(`${q} curl`), fuera(`${q} cable crossover`), fuera(`${q} leg press`)]),
    ...mods.flatMap((m) => [fuera(`${m} bench press`), fuera(`${m} smith machine row`)]),
    fuera('Incline Close-Grip One-Arm Smith Machine Bench Press'), fuera('Decline Wide-Grip Barbell Row'),
    fuera('Single-Arm Cable Crossover'), fuera('Lever Seated Fly'), fuera('E-Z Curl Bar Reverse Curl'),
    fuera('Ball Slam'), fuera('Exercise Ball Pull-In'), fuera('Band Good Morning'), fuera('Kettlebell Pistol Squat'),
    fuera('Bench Pressing'), fuera('Pressure Point'), fuera('BARBELL CURL'), fuera('Zzz Desconocido (Raro)'),
    fuera(''), fuera(null), fuera('', { slug_en: 'Con_Guiones_Bajos' }), fuera(null, { slug_en: 'Otro_Slug_' }),
    fuera(null, { slug_en: null }), fuera('', { slug_en: '' }),
    // _equipLabel: /\bsmith\b/i y EQUIP_LABEL
    ...Object.keys(swap.EQUIP_LABEL).map((q) => fuera('Remo', { equipment: q })),
    fuera('Remo', { equipment: 'foam roll' }), fuera('Remo', { equipment: 'Machine' }), fuera('Remo', { equipment: '' }),
    fuera('Smith Machine Squat', { equipment: 'machine' }), fuera('SMITH squat', { equipment: 'barbell' }),
    fuera('Blacksmith Row', { equipment: 'barbell' }), fuera('Smith_Machine Row', { equipment: 'barbell' }),
    fuera('ſmith Row', { equipment: 'barbell' }), fuera('Row (Smith)', { equipment: null }), fuera('smith-press'),
  ];
}
const sinteticas = entradasSinteticas().map((entrada) => ({ entrada, es: swap._toEs(entrada), equipo: swap._equipLabel(entrada) }));

// ── Orden: localeCompare(…, 'es'), el desempate de findSubstitutes ───
const EXTRA_ORDEN = ['Press', 'press', 'PRESS', 'Prés', 'pres', 'Presa', 'Ñandú', 'nandu', 'Nandu', 'ñandu', 'Curl', 'Curl ',
  ' Curl', 'Curl-a', 'Curla', 'Curl a', 'Curl(a)', 'Curl/a', "Curl'a", 'Curl,a', 'Curl 1', 'Curl 10', 'Curl 2', 'Curl1', 'cúrl',
  'Cúrl', 'a-b', 'ab', 'a b', 'a_b', 'aB', 'Ab', 'AB', 'Elevación', 'Elevacion', 'elevación', 'Elevaciön', 'chaleco', 'cuchillo',
  'llama', 'lomo', 'Á', 'A', 'a', 'á', 'à', 'â', 'ä', 'é', 'e', 'E', 'É', '', ' ', '-', '0', '9', '(', ')', '/', ',', "'"];
const aOrdenar = [...new Set([...traducciones.map((t) => t[0]), ...sinteticas.map((s) => s.es), ...catalogo.map((e) => e.name_en),
  ...EXTRA_ORDEN].filter((s) => typeof s === 'string'))];
const orden = { entrada: aOrdenar, salida: aOrdenar.map((_, i) => i).sort((a, b) => aOrdenar[a].localeCompare(aOrdenar[b], 'es')) };

// ── (c) Listas: findSubstitutes de cada fila del catálogo ────────────
/** Un sustituto es una fila del catálogo: se guarda [índice, _sameEquip]. Si la web cambia la forma, esto avisa. */
function comprimir(lista) {
  return lista.map((s) => {
    const i = indice.get(s.slug);
    const e = catalogo[i];
    const esperado = {
      slug: e.slug_en, name: traducciones[i][0], name_en: e.name_en, equipo: traducciones[i][1], equipmentRaw: e.equipment,
      primary_muscle: e.primary_muscle, patron_movimiento: e.patron_movimiento,
      images: { eccentric: e.image_eccentric || null, concentric: e.image_concentric || null }, _sameEquip: s._sameEquip,
    };
    if (JSON.stringify(s) !== JSON.stringify(esperado)) throw new Error(`el sustituto ${s.slug} no es su fila del catálogo: ${JSON.stringify(s)}`);
    return [i, s._sameEquip ? 1 : 0];
  });
}
function listasDe(db) {
  usar(db);
  const out = {};
  for (const e of db) {
    const l = swap.findSubstitutes({ catalogo_slug: e.slug_en });
    if (l.length) out[e.slug_en] = comprimir(l);
  }
  usar(catalogo);
  return out;
}
const listas = listasDe(catalogo);
const listasAlReves = Object.fromEntries(Object.entries(listasDe([...catalogo].reverse()))
  .filter(([slug, l]) => JSON.stringify(l) !== JSON.stringify(listas[slug])));
const igualALista = (subs, slug) => JSON.stringify(comprimir(subs)) === JSON.stringify((slug && listas[slug]) || []);

// ── Corpus ───────────────────────────────────────────────────────────
const fixtures = path.join(RAIZ, 'apps/shared/fixtures');
const rutinasPublicas = fs.readdirSync(fixtures).sort().map((c) => leer(path.join(fixtures, c, 'get_rutina_activa.json'))[0].estructura);
rutinasPublicas.push(leer(path.join(RAIZ, 'apps/shared/demo/rutina.json')));
const existe = (r) => fs.existsSync(path.join(PRIVADO, r));
const rutinasPrivadas = existe('estructuras/rutinas.json')
  ? [...leer(path.join(PRIVADO, 'estructuras/rutinas.json')), ...(existe('estructuras/rutinas-en-cola.json') ? leer(path.join(PRIVADO, 'estructuras/rutinas-en-cola.json')) : [])]
  : [];
const nombresRegistrados = existe('estructuras/nombres-registrados.json') ? leer(path.join(PRIVADO, 'estructuras/nombres-registrados.json')) : [];

const ejerciciosDe = (rutinas) => rutinas.flatMap((r) => (r.dias || []).flatMap((d) => (d.bloques || []).filter(Boolean)
  .flatMap((b) => (b.ejercicios || []).filter((e) => e && typeof e === 'object'))));

// Solo lo que mira la sustitución (el resto del ejercicio no cambia nada). Sin id: los lugares repetidos se juntan.
const CAMPOS = ['nombre', 'tipo', 'images', 'catalogo_slug', '_matched_slug', '_origNombre', '_origImages', '_origSlug'];
const recortar = (e) => Object.fromEntries(CAMPOS.filter((k) => k in e).map((k) => [k, e[k]]));

const URL_IMG = 'https://gydinputrtptqakdzyvc.supabase.co/storage/v1/object/public/exercise-images';
const img = (slug, extra = {}) => ({ eccentric: `${URL_IMG}/${slug}/0.jpg`, concentric: `${URL_IMG}/${slug}/1.jpg`, ...extra });
const ais = (nombre, extra = {}) => ({ nombre, tipo: 'aislamiento', ...extra });
const comp = (nombre, extra = {}) => ({ nombre, tipo: 'compuesto', ...extra });

// Ejercicios difíciles a propósito.
const DIFICILES = [
  // curl femoral: la regla de "sentado" va antes que el comodín "femoral"
  ais('Curl femoral sentado'), ais('Curl femoral acostado'), ais('Curl femoral tumbado'), ais('Curl femoral'),
  ais('CURL FEMORAL SENTADO (máquina)'), ais('Curl femoral parado'), ais('Curl femoral de pie a una pierna'), ais('Curl femoral nórdico'),
  ais('Femoral sentado'), ais('Leg curl sentado'), ais('Curl femoral en máquina sentado'), ais('Curl femoral-d3-1'), ais('Curl femoral (sentado)'),
  ais('Curl femoral sentado', { images: img('Lying_Leg_Curls', { _matched_slug: 'Lying_Leg_Curls' }) }),
  // jalón
  comp('Jalón al pecho'), comp('Jalón al pecho prono'), comp('Jalón agarre neutro'), comp('Jalón con V-bar'), comp('Jalón al pecho (supino)'),
  comp('Jalon tras nuca'), comp('Jalón unilateral en polea'), comp('Pulldown'), comp('Jalo\u{301}n al pecho'), comp('JALÓN AL PECHO-d1-0'),
  // remo
  comp('Remo con barra'), comp('Remo con mancuerna a una mano'), comp('Remo en polea sentado'), comp('Remo polea baja'),
  comp('Remo en máquina palanca'), comp('Remo al mentón'), comp('Remo en T'), comp('Remo Pendlay'), comp('Iso-row'),
  comp('Remo sentado en polea'), comp('Remo en máquina'), comp('Remo invertido'), comp('Remo'),
  // parado
  ais('Curl de bíceps parado con barra'), comp('Press militar parado'), ais('Elevación de talones parado'), ais('Gemelos parado en multipower'),
  comp('Press de hombros parado con mancuernas'), ais('Curl martillo parado'),
  // calentamiento y cardio: nunca tienen sustitutos, aunque el nombre o el slug resuelvan
  { nombre: 'Sentadilla con barra', tipo: 'calentamiento' }, { nombre: 'Cinta 10 min', tipo: 'cardio' },
  { nombre: 'Movilidad de hombros con banda', tipo: 'calentamiento' }, { nombre: 'Bici fija', tipo: 'cardio', catalogo_slug: 'Barbell_Squat' },
  { nombre: 'Press plano', tipo: 'Cardio' }, { nombre: 'Press plano', tipo: 'core' }, { nombre: 'Press plano' }, { nombre: 'Press plano', tipo: null },
  // sin imágenes
  comp('Press inclinado con mancuernas', { images: null }), comp('Press plano en máquina', { images: {} }),
  comp('Hip thrust', { images: { eccentric: '', concentric: '' } }), comp('Prensa 45°'), comp('Abdominales', { images: null }),
  comp('Zzz sin match', { images: null }),
  // con images._matched_slug
  ais('Lo que sea', { images: img('Hammer_Curls', { _matched_slug: 'Hammer_Curls' }) }),
  ais('Curl martillo', { images: { _matched_slug: 'No_Existe' } }),
  ais('Curl martillo', { images: img('Preacher_Curl', { _matched_slug: 'No_Existe' }) }),
  ais('Curl martillo', { images: { _matched_slug: 'Bottoms-Up_Clean_From_The_Hang_Position' } }),
  ais('Curl martillo', { images: { _matched_slug: 'Hammer_Curls' } }),
  ais('Curl martillo', { images: { _matched_slug: '' , eccentric: '' } }),
  // prioridad entre catalogo_slug suelto, images._matched_slug y _matched_slug suelto
  comp('Press plano', { catalogo_slug: 'Dumbbell_Bench_Press', images: img('Barbell_Bench_Press_-_Medium_Grip', { _matched_slug: 'Barbell_Bench_Press_-_Medium_Grip' }) }),
  comp('Press plano', { catalogo_slug: 'No_Existe', images: { _matched_slug: 'Dumbbell_Bench_Press' } }),
  comp('Press plano', { _matched_slug: 'Dumbbell_Bench_Press' }),
  comp('Press plano', { catalogo_slug: '', _matched_slug: 'Dumbbell_Bench_Press' }),
  comp('Press plano', { catalogo_slug: 'Dumbbell_Bench_Press' }),
  comp('Press plano', { catalogo_slug: 'Dumbbell_Bench_Press', images: img('Leg_Press') }),
  comp('Press plano', { catalogo_slug: null, _matched_slug: 'No_Existe', images: { eccentric: '' } }),
  comp('Press plano', { _matched_slug: 'Leg_Press', images: null }),
  // el slug que viene en la URL de la imagen
  comp('X', { images: { concentric: img('Leg_Press').concentric } }), comp('X', { images: { eccentric: `${URL_IMG}//0.jpg` } }),
  comp('X', { images: { eccentric: 'https://x/exercise-images/No_Existe/0.jpg' } }), comp('X', { images: { eccentric: 'exercise-images/Leg_Press' } }),
  comp('X', { images: { eccentric: 'a/exercise-images/No_Existe/exercise-images/Leg_Press/0.jpg' } }),
  comp('Sentadilla', { images: { eccentric: '', concentric: img('Hack_Squat').concentric } }),
  // nombre normalizado y alias exactos (paso 4); el alias se queda con la primera fila del catálogo
  comp('Ab Crunch Machine'), comp('Zercher Squats'), comp('core'), comp('Cuádriceps'), comp('antebrazos'), comp('Air Bike'),
  // texto difícil
  comp(''), comp('   '), comp('(solo paréntesis)'), comp('Curl (a\u000bb) martillo'), comp('Curl (a\u0085b) martillo'), comp('Curl (a\nb) martillo'),
  comp('İnclinado press'), comp('Press \u{212A}ettlebell'), comp('Peso muerto rumano 🏋️'), comp('Sentadilla búlgara'),
  comp('Extensión de cuádriceps'), comp('Pájaro en máquina'), comp('Elevaciones laterales en polea a una mano'), comp('Face pull'),
  comp('Patada de tríceps'), comp('Press francés'), comp('Dominadas'), comp('Flexiones de brazos'), comp('Peso muerto'),
  comp('RDL con mancuernas'), comp('Ñandú'), comp('Extensión overhead con cuerda'), comp('Press cerrado en multipower'),
  comp('Elevación de talones sentado (sóleo)'), comp('Aperturas en polea baja'), comp('Pullover con mancuerna'), comp('Encogimientos'),
  comp('Hip thrust - d2-3'), comp('Abducción'), comp('Aducción'), comp('Crunch en máquina'), comp('Plancha'), comp('Rueda abdominal'),
];

// exGetSubs sobre objetos que ya traen _orig* (lo que devuelve getEffectiveEx), armados a mano.
const DIRECTOS = [
  ais('Curl martillo', { _origSlug: 'Barbell_Squat' }),
  ais('Sustituto', { _origNombre: 'Jalón al pecho', _origImages: null, _origSlug: null }),
  ais('Sustituto', { _origNombre: '', images: { _matched_slug: 'Leg_Press' } }),
  comp('Press plano', { catalogo_slug: 'Leg_Press' }),   // sin _orig*: exGetSubs no mira el catalogo_slug suelto
  comp('Press plano', { _origSlug: 'No_Existe', images: { _matched_slug: 'Leg_Press' } }),
  comp('Press plano', { _origSlug: '', images: { _matched_slug: 'Leg_Press' } }),
  comp('Press plano', { _origImages: img('Hack_Squat'), images: img('Leg_Press') }),
  comp('Press plano', { _origImages: {}, images: img('Leg_Press', { _matched_slug: 'Leg_Press' }) }),
  comp('Press plano', { _origNombre: 'Remo con barra', _matched_slug: 'Leg_Press' }),
  { nombre: 'Press plano', tipo: 'cardio', _origSlug: 'Leg_Press' },
];

// ── (b) Nombres ──────────────────────────────────────────────────────
function vectoresNombres(nombres) {
  const unicos = [...new Set(nombres.filter((n) => typeof n === 'string'))];
  return unicos.map((n) => ({ n, norm: swap._norm(n), regla: swap._resolveByRules(n), slug: swap._resolve({ nombre: n })?.slug_en ?? null }));
}

// ── (c) Casos por ejercicio ──────────────────────────────────────────
/** El slug con el que exGetSubs resolvió el original: su clave de caché (`n:…` si no resolvió). */
function resueltoPorExGetSubs() {
  const claves = Object.keys(cache);
  if (claves.length > 1) throw new Error('la caché de exGetSubs tiene más de una clave');
  return claves.length ? (claves[0].startsWith('n:') ? null : claves[0]) : undefined;
}

/** exGetSubs con la caché vacía: devuelve el resultado y con qué slug resolvió (o que lo excluyó por tipo). */
function exGetSubs(ex) {
  for (const k of Object.keys(cache)) delete cache[k];
  const subs = web.exGetSubs(ex);
  const resueltoUI = resueltoPorExGetSubs();
  if (!igualALista(subs, resueltoUI)) throw new Error(`exGetSubs no coincide con la lista de su original: ${JSON.stringify(ex)}`);
  return { subs, salida: { ...(resueltoUI === undefined ? { excluido: true } : { resueltoUI }), subs: subs.length } };
}

/** Los ejercicios del corpus van una vez (recortados y sin repetir); los casos los referencian por índice (e). */
function vectoresCasos(ejercicios, directos) {
  const unicos = [...new Map(ejercicios.map(recortar).map((e) => [JSON.stringify(e), e])).values()];
  const todos = [...unicos, ...directos];
  const casos = [];
  todos.forEach((ex, i) => {
    if (i >= unicos.length) {   // ya trae _orig*: exGetSubs directo, sin getEffectiveEx
      casos.push({ e: i, directo: true, ...exGetSubs(ex).salida });
      return;
    }
    const resuelto = swap._resolve(ex)?.slug_en ?? null;
    if (!igualALista(swap.findSubstitutes(ex), resuelto)) throw new Error(`findSubstitutes no coincide con su lista: ${JSON.stringify(ex)}`);
    const conSwap = (sw) => {
      STATE.exerciseSwaps = sw ? { [ex.id]: sw } : {};
      const eff = web.getEffectiveEx(ex);
      STATE.exerciseSwaps = {};
      const { subs, salida } = exGetSubs(eff);
      const caso = {
        e: i, resuelto,
        ...(sw ? { sw: { ...sw.current, fijado: sw.fijado } } : {}),
        efectivo: {
          nombre: eff.nombre ?? null, images: eff.images ?? null, _isSwapped: !!eff._isSwapped, _swapSlug: eff._swapSlug ?? null,
          _swapFijado: !!eff._swapFijado, _origNombre: eff._origNombre ?? null, _origImages: eff._origImages, _origSlug: eff._origSlug,
        },
        ...salida,
      };
      casos.push(caso);
      return subs;
    };
    const subs = conSwap(null);
    // Con una sustitución aplicada (como la deja confirmExSwap): se sigue resolviendo sobre el ORIGINAL.
    if (subs.length) {
      const sub = subs[i % subs.length];
      conSwap({
        original: { slug: null, nombre: ex.nombre, images: ex.images || null },
        current: { slug: sub.slug, nombre: sub.name, equipment: sub.equipmentRaw, images: sub.images },
        fijado: i % 2 === 0, semana: 1, diaId: 'd1',
      });
    }
  });
  return { ejercicios: todos, casos };
}

// ── Catálogo sintético: lo que el real hoy no ejercita ──────────────
// El tope de 30 (la lista más larga del real tiene 25), un alias igual al name_normalized de otra fila, slugs
// repetidos (byId se queda con la última; find, con la primera), músculo y equipo null (null === null), patrón "",
// filas sin foto, un slug con acento descompuesto y dos filas que solo se distinguen por el equipo crudo.
function vectoresSintetico() {
  const S = (slug_en, extra = {}) => fila({
    slug_en, name_en: slug_en.replace(/_/g, ' '), name_normalized: slug_en.toLowerCase().replace(/_/g, ' '), aliases_es: [],
    primary_muscle: 'zz', equipment: 'barbell', patron_movimiento: 'zz_patron',
    image_eccentric: `${URL_IMG}/${slug_en}/0.jpg`, image_concentric: `${URL_IMG}/${slug_en}/1.jpg`, ...extra,
  });
  const db = [
    S('Zz_Original'),
    ...Array.from({ length: 34 }, (_, i) => S(`Zz_Movimiento_${String(i).padStart(2, '0')}`, { equipment: ['barbell', 'dumbbell', null][i % 3] })),
    S('Zz_Doble', { name_en: 'Zz Doble Primera', name_normalized: 'zz doble primera', patron_movimiento: 'zz_doble', primary_muscle: 'zz2' }),
    S('Zz_Doble_Companero', { patron_movimiento: 'zz_doble', primary_muscle: 'zz2' }),
    S('Zz_Doble', { name_en: 'Zz Doble Segunda', name_normalized: 'zz doble segunda', patron_movimiento: 'zz_doble', primary_muscle: 'zz2' }),
    S('Zz_Alias_Primero', { aliases_es: ['zz trampa', 5, null], patron_movimiento: 'zz_alias' }),
    S('Zz_Trampa', { name_normalized: 'zz trampa', patron_movimiento: 'zz_alias' }),
    S('Zz_Sin_Musculo_A', { primary_muscle: null, equipment: null, patron_movimiento: 'zz_null' }),
    S('Zz_Sin_Musculo_B', { primary_muscle: null, equipment: null, patron_movimiento: 'zz_null' }),
    S('Zz_Sin_Musculo_C', { primary_muscle: null, equipment: 'cable', patron_movimiento: 'zz_null' }),
    S('Zz_Patron_Vacio', { patron_movimiento: '' }), S('Zz_Patron_Vacio_2', { patron_movimiento: '' }),
    S('Zz_Sin_Foto', { image_eccentric: '', image_concentric: null, patron_movimiento: 'zz_fotos', primary_muscle: 'zz3' }),
    S('Zz_Solo_Excentrica', { image_concentric: null, patron_movimiento: 'zz_fotos', primary_muscle: 'zz3' }),
    S('Zz_Cafe\u{301}', { patron_movimiento: 'zz_cafe' }), S('Zz_Cafe_2', { patron_movimiento: 'zz_cafe' }),
    S('Zz_Smith_Orig', { name_en: 'Zz Smith Original', patron_movimiento: 'zz_smith', primary_muscle: 'zz4' }),
    S('Zz_Smith_A', { name_en: 'Smith Zz', equipment: 'machine', patron_movimiento: 'zz_smith', primary_muscle: 'zz4' }),
    S('Zz_Smith_B', { name_en: 'Smith Zz', equipment: 'barbell', patron_movimiento: 'zz_smith', primary_muscle: 'zz4' }),
  ];
  const refs = [
    { catalogo_slug: 'Zz_Original' }, { nombre: 'zz original' }, { catalogo_slug: 'Zz_Doble' }, { nombre: 'Zz Doble Primera' },
    { images: { eccentric: `${URL_IMG}/Zz_Doble/0.jpg` } }, { nombre: 'Zz trampa' }, { catalogo_slug: 'Zz_Sin_Musculo_A' },
    { catalogo_slug: 'Zz_Sin_Musculo_C' }, { catalogo_slug: 'Zz_Patron_Vacio' }, { catalogo_slug: 'Zz_Sin_Foto' },
    { catalogo_slug: 'Zz_Solo_Excentrica' }, { catalogo_slug: 'Zz_Café', nombre: 'Zz nada' }, { catalogo_slug: 'Zz_Cafe\u{301}' },
    { catalogo_slug: 'Zz_Smith_Orig' },
  ];
  const efectivos = [ais('x', { catalogo_slug: 'Zz_Sin_Foto' }), ais('x', { catalogo_slug: 'Zz_Solo_Excentrica' }),
    ais('Zz Doble Segunda'), ais('', { images: { _matched_slug: 'Zz_Original' } })];
  usar(db);
  const salida = {
    catalogo: db,
    casos: refs.map((ref) => {
      const r = swap._resolve(ref);
      return { ref, resuelto: r ? db.indexOf(r) : null, subs: swap.findSubstitutes(ref) };
    }),
    efectivos: efectivos.map((ex) => {
      const eff = web.getEffectiveEx(ex);
      for (const k of Object.keys(cache)) delete cache[k];
      return {
        ex, efectivo: { nombre: eff.nombre ?? null, images: eff.images ?? null, _isSwapped: false, _swapSlug: null, _swapFijado: false,
          _origNombre: eff._origNombre ?? null, _origImages: eff._origImages, _origSlug: eff._origSlug },
        subs: web.exGetSubs(eff),
      };
    }),
  };
  usar(catalogo);
  return salida;
}

function escribir(destino, datos) {
  fs.mkdirSync(destino, { recursive: true });
  const archivo = path.join(destino, 'sustitutos_ejercicio.json');
  fs.writeFileSync(archivo, JSON.stringify({
    fuente: `public/js/app.js@${commit} + public/cliente.html@${commit}`,
    catalogo: { archivo: 'apps/shared/catalogo-ejercicios.json', filas: catalogo.length, sha256 },
    ...datos,
  }) + '\n');
  return datos.casos.length;
}

const nombresDe = (ejercicios) => ejercicios.map((e) => e.nombre);
const muestrasReglas = ejemplosDe(swap._RESOLVE_RULES);

const pub = vectoresCasos([...ejerciciosDe(rutinasPublicas), ...DIFICILES], DIRECTOS);
const nPub = escribir(path.join(RAIZ, 'apps/shared/vectores'), {
  traducciones, sinteticas, orden, listas, listasAlReves, sintetico: vectoresSintetico(),
  nombres: vectoresNombres([...nombresDe(pub.ejercicios), ...muestrasReglas, ...muestrasReglas.map((m) => m.toUpperCase()), ...EXTRA_ORDEN]),
  ...pub,
});

let nPriv = 0;
if (rutinasPrivadas.length) {
  const priv = vectoresCasos(ejerciciosDe(rutinasPrivadas), []);
  // traducciones y listas se repiten para que el archivo se lea solo (los casos se comparan contra ellas).
  nPriv = escribir(path.join(PRIVADO, 'vectores'), {
    traducciones, sinteticas: [], orden: { entrada: [], salida: [] }, listas, listasAlReves: {},
    nombres: vectoresNombres([...nombresDe(priv.ejercicios), ...nombresRegistrados]),
    ...priv,
  });
}

// Cuánto cambia la web si el catálogo llega en el orden del servidor (sin ORDER BY) y no en el del archivo.
if (delServidor) {
  const delOrden = listasDe(delServidor);
  const distintas = Object.keys({ ...listas, ...delOrden }).filter((s) => JSON.stringify(listas[s] || []) !== JSON.stringify(delOrden[s] || [])).length;
  usar(delServidor);
  const nombres = [...new Set([...nombresDe(pub.ejercicios), ...nombresDe(ejerciciosDe(rutinasPrivadas)), ...nombresRegistrados])];
  const resServidor = nombres.map((n) => swap._resolve({ nombre: n })?.slug_en ?? null);
  usar(catalogo);
  const resDistintas = nombres.filter((n, i) => (swap._resolve({ nombre: n })?.slug_en ?? null) !== resServidor[i]).length;
  if (distintas || resDistintas) {
    console.warn(`⚠ con el orden del servidor cambian ${distintas} de ${catalogo.length} listas y ${resDistintas} de ${nombres.length} resoluciones por nombre`);
  }
}

console.log(`▸ app.js/cliente.html@${commit}: catálogo ${catalogo.length} filas (${SIN_RED ? 'el del archivo' : 'recién bajado'}) · `
  + `${traducciones.length + sinteticas.length} traducciones · ${Object.keys(listas).length} listas (${Object.keys(listasAlReves).length} cambian al revés) · `
  + `casos ${nPub} públicos / ${nPriv} privados`);
