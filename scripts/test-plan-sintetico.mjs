#!/usr/bin/env node
/* =============================================================
   test-plan-sintetico.mjs — que el banco fabrique la MISMA forma que produce
   el Cerebro en producción.

   POR QUÉ EXISTE
   Un banco de pruebas que genera datos con una forma distinta a la real es
   peor que no tener banco: da confianza falsa. Se pasan los tests, se deploya,
   y el bug estaba en el traductor.

   Dos bugs reales que este archivo ancla, encontrados el 7-ago-2026:

   1. `conBloqueEnCola` insertaba una fila con estado='en_cola'. Dos problemas
      a la vez: mypump_rutinas.estado tiene CHECK IN ('activa','archivada')
      (001:116) así que el INSERT ni entraba, y aunque entrara la app deriva
      tiene_siguiente de estructura_siguiente IS NOT NULL sobre la fila ACTIVA
      (025:37) — una fila nueva no enciende nada. La perilla existía, se
      "usaba", y no probaba absolutamente nada.

   2. La rutina no emitía `semana_offset`. Es la única condición que evita
      mostrarle "Semana de calibración" a alguien que va por la semana 13, y la
      lee en 6 lugares distintos. Sin ella el escenario macrociclo-2 mentía.

   USO:  node scripts/test-plan-sintetico.mjs
   ============================================================= */

import { rutina, dieta, sqlPlan } from './lib/plan-sintetico.mjs';
import { resolver, NOMBRES } from './lib/escenarios-cliente.mjs';

let ok = 0, fail = 0;
const t = (n, fn) => {
  try { fn(); console.log(`  ✓ ${n}`); ok++; }
  catch (e) { console.log(`  ✗ ${n}\n      ${e.message}`); fail++; }
};
const eq = (a, b, m) => { if (JSON.stringify(a) !== JSON.stringify(b)) throw new Error(`${m}\n      esperado: ${JSON.stringify(b)}\n      obtenido: ${JSON.stringify(a)}`); };
const si = (c, m) => { if (!c) throw new Error(m); };

const SQL = (o) => sqlPlan({
  clienteId: 'test-x', nombre: 'Test X', perfil: 'natural', token: 'TOK',
  rutina: rutina(o.rutina || {}), dieta: dieta({}), semanaActual: o.semanaActual || 1,
  conBloqueEnCola: o.conBloqueEnCola, siguiente: o.siguiente, sinDieta: o.sinDieta,
});

console.log('\nRutina');

t('semana_offset se emite cuando hay macrociclo 2', () => {
  eq(rutina({ semanaOffset: 12 }).semana_offset, 12, 'no emitió el offset');
});

t('semana_offset NO se emite en fase 1 (el Cerebro tampoco lo escribe)', () => {
  si(!('semana_offset' in rutina({})), 'emitió semana_offset en un plan de fase 1');
  si(!('semana_offset' in rutina({ semanaOffset: 0 })), 'emitió semana_offset: 0');
});

t('los ids de ejercicio tienen el formato del Cerebro: slug-d{dia}-{indice}', () => {
  const r = rutina({ split: 'upper-lower-4' });
  const ids = r.dias.flatMap(d => d.bloques.flatMap(b => b.ejercicios.map(e => e.id)));
  for (const id of ids) si(/^[a-z0-9-]+-d\d+-\d+$/.test(id), `id con formato ajeno: ${id}`);
  // El índice es GLOBAL dentro del día, no por bloque: si se reiniciara por
  // bloque habría ids repetidos y el histórico de dos ejercicios se mezclaría.
  si(new Set(ids).size === ids.length, 'hay ids de ejercicio repetidos');
});

t('el índice del id NO se reinicia en cada bloque', () => {
  const d1 = rutina({ split: 'ppl-6' }).dias[0];
  const idxs = d1.bloques.flatMap(b => b.ejercicios.map(e => Number(e.id.split('-').pop())));
  eq(idxs, idxs.map((_, i) => i), 'los índices no son correlativos dentro del día');
});

t('ejerciciosPorDia se respeta de verdad', () => {
  for (const n of [3, 5, 6]) {
    const d = rutina({ split: 'upper-lower-4', ejerciciosPorDia: n }).dias[1];  // LOWER: 1 solo grupo
    eq(d.bloques.reduce((a, b) => a + b.ejercicios.length, 0), n, `pidió ${n} por día`);
  }
});

console.log('\nPerillas de plan roto');

t('diasVacios deja dias: [] (la app no arranca)', () => eq(rutina({ diasVacios: true }).dias, [], 'no vació los días'));
t('sinSemanasTotal saca la clave entera', () => si(!('semanas_total' in rutina({ sinSemanasTotal: true })), 'dejó semanas_total'));
t('diaSinEjercicios vacía SOLO el primer día', () => {
  const r = rutina({ diaSinEjercicios: true });
  eq(r.dias[0].bloques, [], 'no vació el día 1');
  si(r.dias[1].bloques.length > 0, 'vació también el día 2');
});
t('sinDescanso saca descanso_segundos de TODOS los ejercicios', () => {
  const r = rutina({ sinDescanso: true });
  const con = r.dias.flatMap(d => d.bloques.flatMap(b => b.ejercicios)).filter(e => 'descanso_segundos' in e);
  eq(con.length, 0, `quedaron ${con.length} ejercicios con descanso`);
});

console.log('\nDieta');

t('opciones por comida se respeta (1, 2 y 4)', () => {
  for (const n of [1, 2, 4]) {
    for (const c of dieta({ opciones: n }).comidas) eq(c.options.length, n, `pidió ${n} opciones`);
  }
});

t('UN alimento por rol: nunca dos proteínas en la misma opción', () => {
  // Es la regla del proyecto que más veces se rompió en el generador real.
  for (const c of dieta({ comidas: 5, opciones: 4 }).comidas) {
    for (const op of c.options) {
      const roles = op.foods.map(f => f.category);
      eq(roles.length, new Set(roles).size, `opción ${op.name} de ${c.name} con dos alimentos del mismo rol: ${roles}`);
    }
  }
});

t('las opciones de UNA comida son intercambiables entre sí (±15% kcal)', () => {
  // A/B/C/D son por COMIDA: el cliente combina desayuno A + almuerzo C. Las 4
  // opciones DE CADA comida tienen que valer lo mismo entre ellas.
  for (const c of dieta({ comidas: 4, opciones: 4 }).comidas) {
    const kcals = c.options.map(o => o.foods.reduce((a, f) => a + f.kcal, 0));
    const min = Math.min(...kcals), max = Math.max(...kcals);
    si((max - min) / max <= 0.15, `${c.name}: opciones desparejas ${kcals.join('/')} kcal`);
  }
});

t('sinMacrosTarget saca la clave (rompe el arranque de la app)', () => {
  si(!('macros_target' in dieta({ sinMacrosTarget: true })), 'dejó macros_target');
});

t('sinUnitGrams reproduce lo que publica el Cerebro hoy', () => {
  const d = dieta({ sinUnitGrams: true });
  const prot = d.comidas[0].options[0].foods.find(f => f.category === 'proteina');
  eq(prot.unit, 'unidad', 'no puso unit unidad');
  si(!('unitGrams' in prot), 'dejó unitGrams');
});

console.log('\nSQL del plan');

t('el bloque en cola va como estructura_siguiente de la fila ACTIVA', () => {
  const s = SQL({ conBloqueEnCola: true, siguiente: rutina({ split: 'full-body-3' }) });
  si(/UPDATE mypump_rutinas[\s\S]*SET estructura_siguiente =/.test(s), 'no escribe estructura_siguiente');
  si(/WHERE cliente_id = 'test-x' AND estado = 'activa'/.test(s), 'no apunta a la fila activa');
});

t("NUNCA inserta estado='en_cola' (viola el CHECK y no enciende nada)", () => {
  // Solo las líneas ejecutables: la cabecera del bloque MENCIONA 'en_cola'
  // justamente para explicar por qué no se usa.
  const ejecutable = SQL({ conBloqueEnCola: true })
    .split('\n').filter(l => !l.trim().startsWith('--')).join('\n');
  si(!/'en_cola'/.test(ejecutable), "el SQL todavía usa estado='en_cola'");
});

t('sin bloque en cola no toca estructura_siguiente', () => {
  si(!/estructura_siguiente/.test(SQL({})), 'escribió estructura_siguiente sin pedirlo');
});

t('el bloque en cola es OTRO plan, no el mismo', () => {
  // Si fuera idéntico, activarlo no se notaría y el caso no probaría nada.
  const sig = rutina({ split: 'full-body-3', semanasTotal: 8 });
  const s = SQL({ conBloqueEnCola: true, siguiente: sig });
  si(s.includes('FULL BODY A'), 'no usó la estructura siguiente que se le pasó');
});

t('sinDieta no publica dieta (el cliente ve SAMPLE_DIET)', () => {
  const s = SQL({ sinDieta: true });
  si(!/INSERT INTO mypump_dietas/.test(s), 'publicó dieta igual');
  si(/UPDATE mypump_dietas SET estado = 'archivada'/.test(s), 'no archivó la dieta anterior');
});

t('el token del cliente se respeta y el SQL es idempotente', () => {
  const s = SQL({});
  si(s.includes("'TOK'"), 'no usó el token que se le pasó');
  si(/ON CONFLICT \(cliente_id\) DO UPDATE/.test(s), 'no es idempotente en mypump_clientes');
  si(/UPDATE mypump_rutinas SET estado = 'archivada'/.test(s), 'no archiva la rutina anterior');
});

t('las comillas simples de los nombres no rompen el SQL', () => {
  // "Jalón", "Extensión"… y cualquier apóstrofo que entre por un nombre.
  const s = sqlPlan({
    clienteId: 'x', nombre: "O'Brien", perfil: 'natural', token: 'T',
    rutina: rutina({}), dieta: dieta({}), semanaActual: 1,
  });
  si(s.includes("'O''Brien'"), 'no escapó el apóstrofo');
});

console.log('\nCatálogo de escenarios');

t('todos los escenarios resuelven y generan un plan válido', () => {
  for (const n of NOMBRES) {
    const e = resolver(n);
    si(e, `${n} no resuelve`);
    si(e._que && e._mirar, `${n} sin _que/_mirar: un escenario sin motivo escrito no sirve`);
    const r = rutina({ split: e.split, semanasTotal: e.semanasTotal, objetivo: e.objetivo,
                       semanaOffset: e.semanaOffset, ...(e.rutinaRota || {}) });
    si(r && typeof r === 'object', `${n} no genera rutina`);
    si(dieta({ comidas: e.comidas, opciones: e.opciones, ...(e.dietaRota || {}) }), `${n} no genera dieta`);
  }
});

t('macrociclo-2 produce SEM 13, no SEM 1', () => {
  const e = resolver('macrociclo-2');
  eq(e.semanaActual + e.semanaOffset, 13, 'la semana visible no es 13');
});

t('recien-vinculado no tiene NADA de historia', () => {
  const e = resolver('recien-vinculado');
  eq([e.semanasEntrenadas, e.semanasChecks, e.diasPeso, e.diasComidas], [0, 0, 0, 0], 'tiene historia');
});

t('abandonado tiene historia pero adherencia 0 (dejó de entrenar)', () => {
  const e = resolver('abandonado');
  si(e.semanasEntrenadas > 0, 'no tiene historia previa');
  eq(e.adherenciaEntreno, 0, 'sigue entrenando');
});

console.log(`\n${ok} pasaron, ${fail} fallaron\n`);
process.exit(fail ? 1 : 0);
