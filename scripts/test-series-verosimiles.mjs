// test-series-verosimiles.mjs — una serie con valores imposibles no se registra
//
// POR QUE EXISTE (19-sep-2026). En mypump_registros_carga había 23 series con
// reps como 1214, 1110 o 12120 y pesos de 800 y 3.530 kg. El patrón es de
// concatenación: al EDITAR una serie confirmada el campo conservaba el valor
// viejo y lo tipeado se pegaba atrás ("12" + "14"). Y como el peso sugerido
// de la semana siguiente sale del histórico, un 800 kg se repitió tres semanas
// con un solo toque. Además, el teclado decimal en español pone COMA y
// parseFloat("62,5") es 62: el medio kilo se perdía en silencio.
//
// Fija: (1) normalización de lo tipeado, (2) topes duros que rechazan,
// (3) saltos raros que se PREGUNTAN y no se bloquean, (4) al foco se
// selecciona todo, (5) writeSet tolera la coma.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const HTML = fs.readFileSync(path.join(ROOT, 'public/cliente.html'), 'utf8');

let fallas = 0;
function t(nombre, fn) {
  try { fn(); console.log(`  ✓ ${nombre}`); }
  catch (e) { fallas++; console.log(`  ✗ ${nombre}\n      ${e.message}`); }
}
const extraer = (re) => { const m = HTML.match(re); if (!m) throw new Error('no encontré ' + re); return m[0]; };

// ── Código real, ejecutado ──────────────────────────────────────────────────
const codigo = [
  extraer(/const LIMITES_SERIE = \{[^\n]*\n/),
  extraer(/function normalizarCampoSerie\(field, v\) \{[\s\S]*?\n\}\n/),
  extraer(/function _recordKg\(exId\) \{[\s\S]*?\n\}\n/),
  extraer(/async function _serieVerosimil\(exId, idx, setObj, noKg, prog\) \{[\s\S]*?\n\}\n/),
].join('\n');

function armar({ historico = [], repsHist = '', repsPlan = null, confirma = true } = {}) {
  const llamadas = { dudosa: [], modal: [] };
  const fn = new Function('DATA', 'suggestedReps', '_repsSug', 'MyPump', '_marcarSerieDudosa',
    codigo + '\nreturn { normalizarCampoSerie, _serieVerosimil, _recordKg, LIMITES_SERIE };');
  const api = fn(
    { historico_por_ejercicio: { ex1: historico } },
    () => repsHist,
    () => repsPlan,
    { ui: { showConfirmModal: async (o) => { llamadas.modal.push(o); return confirma; } } },
    (exId, idx, msg) => llamadas.dudosa.push(msg),
  );
  return { ...api, llamadas };
}

console.log('\n1. normalización de lo tipeado');
t('kg: coma → punto', () => { const a = armar(); if (a.normalizarCampoSerie('kg', '62,5') !== '62.5') throw new Error(a.normalizarCampoSerie('kg', '62,5')); });
t('kg: letras y símbolos afuera', () => { if (armar().normalizarCampoSerie('kg', '6a2.5kg') !== '62.5') throw new Error(); });
t('kg: un solo punto decimal', () => { if (armar().normalizarCampoSerie('kg', '62.5.5') !== '62.55') throw new Error(armar().normalizarCampoSerie('kg', '62.5.5')); });
t('reps: solo dígitos', () => { if (armar().normalizarCampoSerie('reps', '12,') !== '12') throw new Error(); });
t('otro campo: intacto', () => { if (armar().normalizarCampoSerie('rir', 'x') !== 'x') throw new Error(); });

console.log('\n2. topes duros: se rechaza y se marca la fila');
const casos = [
  ['reps 1214', { reps: '1214', kg: '40' }, false, /repeticiones/],
  ['reps 12120', { reps: '12120', kg: '40' }, false, /repeticiones/],
  ['reps 0', { reps: '0', kg: '40' }, false, /repeticiones/],
  ['kg 800', { reps: '10', kg: '800' }, false, /peso/],
  ['kg 3530', { reps: '12', kg: '3530' }, false, /peso/],
  ['kg 62,5 (coma vieja en STATE)', { reps: '10', kg: '62,5' }, true, null],
  ['plancha 120 s (sin kg)', { reps: '120', kg: '' }, true, null, true],
];
for (const [nombre, setObj, esperado, re, noKg] of casos) {
  const a = armar();
  const r = await a._serieVerosimil('ex1', 0, setObj, !!noKg, { reps: '10' });
  t(`${nombre} → ${esperado ? 'pasa' : 'rechazada'}`, () => {
    if (r !== esperado) throw new Error(`devolvió ${r}`);
    if (re && !re.test(a.llamadas.dudosa[0] || '')) throw new Error('mensaje: ' + a.llamadas.dudosa[0]);
    if (!esperado && a.llamadas.modal.length) throw new Error('lo imposible no se pregunta, se rechaza');
  });
}

console.log('\n3. saltos raros: se preguntan, no se bloquean');
{
  const hist = [{ peso_kg: 80, reps_realizadas: 10 }, { peso_kg: 82.5, reps_realizadas: 8 }];
  let a = armar({ historico: hist, confirma: true });
  let r = await a._serieVerosimil('ex1', 0, { reps: '10', kg: '250' }, false, { reps: '10' });
  t('250 kg con récord 82,5 → pregunta y registra si dice que sí', () => {
    if (!a.llamadas.modal.length) throw new Error('no preguntó');
    if (!/récord era 82\.5/.test(a.llamadas.modal[0].body)) throw new Error(a.llamadas.modal[0].body);
    if (r !== true) throw new Error('debió registrar');
  });
  a = armar({ historico: hist, confirma: false });
  r = await a._serieVerosimil('ex1', 0, { reps: '10', kg: '250' }, false, { reps: '10' });
  t('…y si dice "Corregir" no registra', () => { if (r !== false) throw new Error(); });
  a = armar({ historico: hist });
  r = await a._serieVerosimil('ex1', 0, { reps: '10', kg: '90' }, false, { reps: '10' });
  t('90 kg con récord 82,5 → ni pregunta', () => { if (r !== true || a.llamadas.modal.length) throw new Error(); });
  a = armar({ historico: [], repsHist: '12' });
  r = await a._serieVerosimil('ex1', 0, { reps: '110', kg: '120' }, false, { reps: '12' });
  t('110 reps viniendo de 12 → pregunta', () => { if (!a.llamadas.modal.length || !/110 repeticiones/.test(a.llamadas.modal[0].body)) throw new Error(JSON.stringify(a.llamadas.modal)); });
  a = armar({ historico: [], repsHist: '' , repsPlan: 15 });
  r = await a._serieVerosimil('ex1', 0, { reps: '25', kg: '20' }, false, { reps: '15' });
  t('25 reps con plan de 15 → ni pregunta', () => { if (a.llamadas.modal.length) throw new Error(); });
  a = armar({ historico: [] });
  r = await a._serieVerosimil('ex1', 0, { reps: '10', kg: '300' }, false, { reps: '10' });
  t('primera vez con el ejercicio: sin récord no hay con qué comparar → pasa', () => { if (r !== true || a.llamadas.modal.length) throw new Error(); });
}

console.log('\n4. cableado en cliente.html');
t('confirmarSerie llama a _serieVerosimil ANTES de confirmed = true', () => {
  const i = HTML.indexOf('async function confirmarSerie(exId, idx)');
  const c = HTML.slice(i, i + 4000);
  const a = c.indexOf('await _serieVerosimil(exId, idx, setObj, noKg, prog)'), b = c.indexOf('setObj.confirmed = true;');
  if (a < 0) throw new Error('no llama a _serieVerosimil');
  if (!(a < b)) throw new Error('la guardia va antes de confirmar');
});
t('el handler de input normaliza y guarda lo normalizado', () => {
  const i = HTML.indexOf("$$('[data-set] input').forEach(inp => {");
  const c = HTML.slice(i, i + 1600);
  if (!c.includes('normalizarCampoSerie(field, inp.value)')) throw new Error('no normaliza');
  if (!c.includes('STATE.session[exId].sets[+idx][field] = v;')) throw new Error('guarda el valor crudo');
});
t('al foco se selecciona todo (edición = reemplazo, no concatenación)', () => {
  const i = HTML.indexOf("$$('[data-set] input').forEach(inp => {");
  const c = HTML.slice(i, i + 1600);
  if (!/addEventListener\('focus'[\s\S]{0,200}inp\.select\(\)/.test(c)) throw new Error('sin select() al foco');
});
t('writeSet tolera coma en kg', () => {
  const i = HTML.indexOf("Outbox.enqueue('carga', {");
  const c = HTML.slice(i, i + 1200);
  if (!c.includes("parseFloat(String(s.kg).replace(',', '.')) || 0")) throw new Error('parseFloat(s.kg) pelado');
});

console.log();
if (fallas) { console.log(`✗ ${fallas} fallo(s): pueden volver a entrar series de 3.530 kg\n`); process.exit(1); }
console.log('✓ series verosímiles: topes, preguntas, coma y selección al foco\n');
