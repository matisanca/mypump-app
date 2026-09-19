#!/usr/bin/env node
/* =============================================================
   test-historial-por-identidad.mjs — el historial es del EJERCICIO, no del slot

   POR QUÉ EXISTE
   Dos clientes, 19-sep-2026: "cuando sustituyo un ejercicio me deja las cargas
   del original" y "el mismo ejercicio dos veces en la semana tiene dos
   récords". Y uno documentado desde el 11-sep: activar un bloque nuevo borraba
   "última vez" y récord. Los tres eran el mismo bug: el historial se buscaba
   por ex.id, que es el id del SLOT de la rutina (lleva el día adentro y se
   regenera por bloque), no del ejercicio.

   La identidad correcta es el NOMBRE EFECTIVO normalizado — lo que el cliente
   realmente hizo — y vive en dos lugares que tienen que ser idénticos:
   claveEjercicio() en cliente.html y mypump_clave_ejercicio() en la 072.
   Verificado el 19-sep sobre los 1.246 nombres reales de la base: 0 diferencias.
   Este test no tiene la base, así que fija (a) vectores que cubren cada regla y
   (b) que la migración use las MISMAS reglas, para que nadie cambie una sola.

   USO:  node scripts/test-historial-por-identidad.mjs
   ============================================================= */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const raiz = path.join(path.dirname(fileURLToPath(import.meta.url)), '..');
const HTML = fs.readFileSync(path.join(raiz, 'public/cliente.html'), 'utf8');
const SBC  = fs.readFileSync(path.join(raiz, 'public/js/supabase-client.js'), 'utf8');
const SQL  = fs.readFileSync(path.join(raiz, 'supabase/migrations/072_historial_por_identidad.sql'), 'utf8');

// La función de verdad, extraída del HTML y ejecutada — no un grep.
const src = HTML.match(/function claveEjercicio\(nombre\) \{[\s\S]*?\n\}/);
if (!src) { console.log('✗ no encontré claveEjercicio() en cliente.html'); process.exit(1); }
const claveEjercicio = new Function(src[0] + '; return claveEjercicio;')();

let ok = 0, fail = 0;
const t = (n, fn) => {
  try { fn(); console.log(`  ✓ ${n}`); ok++; }
  catch (e) { console.log(`  ✗ ${n}\n      ${e.message}`); fail++; }
};
const eq = (a, b, m) => { if (a !== b) throw new Error(`${m}: esperaba ${JSON.stringify(b)}, vino ${JSON.stringify(a)}`); };

console.log('\n=== La clave ===\n');

t('el mismo ejercicio en dos días da la MISMA clave (bug 2)', () => {
  // Los ids de slot difieren (d1-0 vs d4-2); la clave sale del nombre, no del id.
  eq(claveEjercicio('Curl de bíceps con mancuernas'), claveEjercicio('Curl de bíceps con mancuernas'), 'igualdad');
});

t('acentos y ñ no parten el historial', () => {
  eq(claveEjercicio('Jalón al pecho'), claveEjercicio('Jalon al pecho'), 'jalón/jalon');
  eq(claveEjercicio('Extensión de cuádriceps'), 'extension de cuadriceps', 'tildes');
  eq(claveEjercicio('Pájaros en máquina'), 'pajaros en maquina', 'máquina');
  eq(claveEjercicio('Curl araña'), 'curl arana', 'ñ');
});

t('el paréntesis es el músculo, no el ejercicio', () => {
  eq(claveEjercicio('Press inclinado con mancuernas (pectoral superior)'),
     claveEjercicio('Press inclinado con mancuernas'), 'con y sin paréntesis');
  eq(claveEjercicio('Extensión en polea con cuerda agarre neutro (cabeza medial)'),
     'extension en polea con cuerda agarre neutro', 'cabeza medial');
});

t('puntuación, grados y espacios múltiples no cuentan', () => {
  eq(claveEjercicio('Curl inclinado con mancuernas a 45°'), 'curl inclinado con mancuernas a 45', 'grados');
  eq(claveEjercicio('  Remo   en polea — sentado, agarre neutro '), 'remo en polea sentado agarre neutro', 'espacios/guiones');
  eq(claveEjercicio('Cruce de poleas alto→bajo'), 'cruce de poleas alto bajo', 'flecha');
});

t('ejercicios DISTINTOS siguen distintos', () => {
  if (claveEjercicio('Press inclinado con mancuernas') === claveEjercicio('Press plano con mancuernas'))
    throw new Error('inclinado y plano colapsaron');
  if (claveEjercicio('Curl femoral sentado') === claveEjercicio('Curl femoral tumbado'))
    throw new Error('sentado y tumbado colapsaron');
});

t('vacío y null no explotan', () => {
  eq(claveEjercicio(''), '', 'vacío');
  eq(claveEjercicio(null), '', 'null');
  eq(claveEjercicio(undefined), '', 'undefined');
});

console.log('\n=== JS y SQL son la misma función ===\n');

t('la migración normaliza con las MISMAS reglas, en el MISMO orden', () => {
  // Si alguien cambia una regla en un lado y no en el otro, el historial se
  // parte en silencio: lo escrito con la clave nueva no matchea lo viejo.
  const i_lower = SQL.indexOf('lower(coalesce(p_nombre');
  const i_acc   = SQL.indexOf("'áéíóúàèìòùäëïöüâêîôûãõñç'");
  const i_par   = SQL.indexOf("'\\(.*?\\)', ' ', 'g'");
  const i_alnum = SQL.indexOf("'[^a-z0-9 ]+', ' ', 'g'");
  const i_esp   = SQL.indexOf("'\\s+', ' ', 'g'");
  for (const [n, i] of Object.entries({ lower: i_lower, acentos: i_acc, parentesis: i_par, alnum: i_alnum, espacios: i_esp }))
    if (i < 0) throw new Error(`la 072 no tiene la regla "${n}"`);
  // En SQL el anidamiento es de adentro hacia afuera: lower → acentos →
  // paréntesis → alnum → espacios. La posición en el texto lo refleja.
  if (!(i_lower < i_acc && i_acc < i_par && i_par < i_alnum && i_alnum < i_esp))
    throw new Error('el orden de las reglas en SQL no es lower → acentos → paréntesis → alnum → espacios');
});

t('la tabla de acentos de SQL cubre lo que NFD cubre en JS', () => {
  // NFD en JS saca cualquier diacrítico; translate en SQL solo los listados.
  // Si aparece un carácter fuera de la lista, JS y SQL divergen. Se verifica
  // que cada carácter de la lista SQL lo resuelva JS igual que SQL.
  const de = 'áéíóúàèìòùäëïöüâêîôûãõñç', a = 'aeiouaeiouaeiouaeiouaonc';
  eq(de.length, a.length, 'largo de la tabla translate');
  for (let i = 0; i < de.length; i++)
    eq(claveEjercicio(de[i]), a[i], `carácter ${de[i]}`);
});

t('la columna es GENERADA y hay índice por (cliente, clave, fecha)', () => {
  if (!/GENERATED ALWAYS AS \(mypump_clave_ejercicio\(ejercicio_nombre\)\) STORED/.test(SQL))
    throw new Error('ejercicio_clave no es una columna generada: el escritor tendría que llenarla y se olvidaría');
  if (!/ON mypump_registros_carga \(cliente_id, ejercicio_clave, registrado_en DESC\)/.test(SQL))
    throw new Error('falta el índice que usa la RPC');
  if (!/IMMUTABLE/.test(SQL)) throw new Error('la función tiene que ser IMMUTABLE para una columna generada');
});

t('la RPC nueva tiene nombre NUEVO (no una segunda firma de la vieja)', () => {
  // Agregar un parámetro a mypump_get_historico_ejercicios crearía dos firmas
  // y PostgREST tira PGRST203 (pasó en agosto, mató la ronda 2 semanas).
  if (!/FUNCTION mypump_get_historico_por_clave\(/.test(SQL)) throw new Error('no está mypump_get_historico_por_clave');
  if (/CREATE OR REPLACE FUNCTION mypump_get_historico_ejercicios\(/.test(SQL))
    throw new Error('la 072 redefine la RPC vieja: riesgo de firma duplicada');
});

console.log('\n=== La app usa la clave en los lugares correctos ===\n');

t('writeSet registra el nombre EFECTIVO (la fuente de la identidad)', () => {
  const i = HTML.indexOf('function writeSet(exId, setIdx)');
  const cuerpo = HTML.slice(i, i + 1500);
  if (!/ejercicioNombre\s*=\s*swap \? swap\.current\.nombre : ex\.nombre/.test(cuerpo))
    throw new Error('writeSet ya no snapshotea el nombre del sustituto: la clave dejaría de reflejar lo que se hizo');
});

t('loadHistorico pide por clave del slot, con caída a la RPC vieja', () => {
  const i = HTML.indexOf('async function loadHistorico(exId)');
  const cuerpo = HTML.slice(i, i + 1200);
  if (!cuerpo.includes('claveDeSlot(exId)')) throw new Error('loadHistorico no calcula la clave del slot');
  if (!cuerpo.includes('getHistoricoPorClave(')) throw new Error('loadHistorico no usa la RPC por clave');
  if (!cuerpo.includes('getHistoricoEjercicio(TOKEN, exId')) throw new Error('sin caída a la RPC vieja, la app sin migración se queda sin historial');
});

t('claveDeSlot usa el ejercicio EFECTIVO (el sustituto si hay swap)', () => {
  const i = HTML.indexOf('function claveDeSlot(exId)');
  const cuerpo = HTML.slice(i, i + 300);
  if (!cuerpo.includes('getEffectiveEx(ex).nombre'))
    throw new Error('claveDeSlot no pasa por getEffectiveEx: un slot sustituido pediría el historial del original (bug 1)');
});

t('aplicar y revertir un swap invalidan el historial del slot', () => {
  const ap = HTML.indexOf("current:  { slug: sub.slug, nombre: sub.name");
  const apBody = HTML.slice(ap, ap + 900);
  if (!apBody.includes('invalidarHistorico(ex.id)')) throw new Error('aplicar swap no invalida: quedaría en caché el historial del original');
  if (!apBody.includes('loadHistorico(ex.id)')) throw new Error('aplicar swap no recarga');
  const rv = HTML.indexOf("btn.getAttribute('data-revert-ex')");
  const rvBody = HTML.slice(rv, rv + 500);
  if (!rvBody.includes('invalidarHistorico(exId)')) throw new Error('revertir swap no invalida: quedaría el historial del sustituto');
  if (!rvBody.includes('loadHistorico(exId)')) throw new Error('revertir swap no recarga');
});

t('cuando un swap se descarta solo (otra semana / día cerrado) también se invalida', () => {
  const i = HTML.indexOf('function pruneExerciseSwaps()');
  const cuerpo = HTML.slice(i, i + 900);
  if (!cuerpo.includes('invalidarHistorico(exId)')) throw new Error('prune borra el swap pero deja el historial del sustituto en caché');
});

t('la pantalla de Progreso agrupa por ejercicio, no por slot', () => {
  const i = HTML.indexOf('async function loadProgressAndRender()');
  const cuerpo = HTML.slice(i, i + 3000);
  if (cuerpo.includes('if (seen.has(ex.id)) continue;'))
    throw new Error('Progreso sigue deduplicando por ex.id: el mismo ejercicio en dos días sale dos veces');
  if (!cuerpo.includes('claveEjercicio(eff.nombre)')) throw new Error('Progreso no agrupa por clave del ejercicio efectivo');
  if (!cuerpo.includes('getHistoricoPorClave(')) throw new Error('Progreso no pide el historial por clave');
  if (!/for \(const id of \(r\.ids \|\| \[r\.id\]\)\) DATA\.historico_por_ejercicio\[id\] = r\.rows/.test(cuerpo))
    throw new Error('Progreso no llena la caché de TODOS los slots que comparten la clave');
});

t('loadHistorico no deja que un fetch viejo pise al slot ya sustituido (carrera)', () => {
  // El barrido del 19-sep lo encontró: sustituir mientras viaja el fetch de la
  // clave vieja → el fetch viejo escribe el historial del ORIGINAL bajo el slot
  // ya sustituido. Bug 1 de vuelta, por una ventana de red.
  const i = HTML.indexOf('async function loadHistorico(exId)');
  const cuerpo = HTML.slice(i, i + 2200);
  if (!cuerpo.includes('_histPromises[exId] !== p || claveDeSlot(exId) !== clave'))
    throw new Error('el fetch no verifica que siga siendo el vigente y de la misma clave antes de escribir');
  if (/\n\s*delete _histPromises\[exId\];\n\}/.test(cuerpo))
    throw new Error('vuelve a borrar la promesa a ciegas al final: un fetch viejo borraría la promesa NUEVA');
});

t('un fallo de red no marca el historial como "vacío" (se vuelve a pedir)', () => {
  const i = HTML.indexOf('async function loadHistorico(exId)');
  const cuerpo = HTML.slice(i, i + 2200);
  if (!cuerpo.includes('delete DATA.historico_por_ejercicio[exId]'))
    throw new Error('ante un fallo deja [] y la card queda en "Primera vez" toda la sesión');
});

t('el prefetch del día es UNA llamada, repartida a los slots que comparten clave', () => {
  const i = HTML.indexOf('function prefetchHistoricoDia()');
  const cuerpo = HTML.slice(i, i + 1800);
  if (!cuerpo.includes('getHistoricoPorClave(TOKEN, claves')) throw new Error('el prefetch sigue pidiendo de a uno');
  if (!cuerpo.includes('new Set(ids.map(claveDeSlot)')) throw new Error('no deduplica las claves del día');
});

t('cuando prune descarta un swap, vuelve a pedir el historial', () => {
  const i = HTML.indexOf('function pruneExerciseSwaps()');
  const cuerpo = HTML.slice(i, i + 1100);
  if (!cuerpo.includes('prefetchHistoricoDia()'))
    throw new Error('prune invalida pero no re-pide: la card vuelve al original y muestra "Primera vez" hasta que la expandan');
});

t('el cliente de Supabase solo apaga el camino por clave si la RPC NO EXISTE', () => {
  // Un corte de señal en el gimnasio NO puede reactivar el bug viejo por el
  // resto de la sesión. Solo PGRST202 (función inexistente) latchea.
  const i = SBC.indexOf('async getHistoricoPorClave(');
  const cuerpo = SBC.slice(i, i + 1600);
  if (!cuerpo.includes("PGRST202")) throw new Error('no distingue "la RPC no existe" de "falló este request"');
  const iLatch = cuerpo.indexOf('_sinHistoricoPorClave = true');
  const iIf = cuerpo.lastIndexOf('if (noExiste)', iLatch);
  if (iIf < 0) throw new Error('el latch no está condicionado a noExiste');
});

t('el cliente de Supabase devuelve null si la RPC no existe (para la caída)', () => {
  const i = SBC.indexOf('async getHistoricoPorClave(');
  const cuerpo = SBC.slice(i, i + 1600);
  if (!cuerpo.includes('return null')) throw new Error('getHistoricoPorClave no devuelve null cuando falta la RPC');
  if (!cuerpo.includes('_sinHistoricoPorClave = true')) throw new Error('no memoriza la ausencia: sondearía en cada llamada');
});

console.log(`\n${fail === 0 ? '✅' : '❌'}  ${ok} pasaron, ${fail} fallaron\n`);
process.exit(fail === 0 ? 0 : 1);
