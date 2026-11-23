// Días anteriores en Dieta y copiar a hoy: mismos casos que DiasDietaTests de la app 2.3.0.
import { createRequire } from 'node:module';
import assert from 'node:assert/strict';
const require = createRequire(import.meta.url);
const D = require('../public/js/dias-dieta.js');
const A = require('../public/js/ajustes-dieta.js');
let n = 0;
const eq = (a, b, m) => { assert.deepEqual(a, b, m); n++; };

const f = D.seleccionables('2026-11-09', '2026-11-09');
eq([f.length, f[0], f[7]], [8, '2026-11-09', '2026-11-02'], 'hoy y siete atrás');
const at = D.seleccionables('2026-11-09', '2026-11-10');
eq([at[0], at[at.length - 1]], ['2026-11-09', '2026-11-03'], 'teléfono atrasado');
eq(D.sumar('2026-01-02', -3), '2025-12-30', 'cruza el año');
eq(D.sumar('2026-03-01', -1), '2026-02-28', 'cruza el mes');
eq(D.permiteMarcar('2026-11-07', '2026-11-09', 2), true, 'marcar 2');
eq(D.permiteMarcar('2026-11-06', '2026-11-09', 2), false, 'marcar 3');
eq(D.permiteMarcar('2026-11-02', '2026-11-09', 7), true, 'marcar 7');
eq(D.permiteMarcar('2026-11-10', '2026-11-09', 7), false, 'mañana no');
eq([D.diasMarcar(null), D.diasMarcar(1), D.diasMarcar(5), D.diasMarcar(30)], [2, 2, 5, 7], 'palanca');
eq(D.rotuloCorto('2026-11-09', '2026-11-09'), 'Hoy', 'hoy');
eq(D.rotuloCorto('2026-11-08', '2026-11-09'), 'Ayer', 'ayer');
eq(D.rotuloCorto('2026-11-07', '2026-11-09'), 'Sáb 7', 'corto');
eq(D.rotuloLargo('2026-11-07'), 'sábado 7 de noviembre', 'largo');
eq(D.hoyServidor(new Date('2026-11-10T02:00:00Z')), '2026-11-09', 'Argentina es −3');

const comida = (id, ops = ['A', 'B'], als = 2) => ({ id, name: id, options: ops.map(o => ({ name: o,
  foods: Array.from({ length: als }, (_, i) => ({ name: `x${i}`, qty: 100, unit: 'g', kcal: 100, prot: 10, carb: 10, fat: 1 })) })) });
const libre = (id, descripcion, kcal) => ({ id, descripcion, kcal });
const marca = (opcion, estado, ex = []) => ({ opcion, estado, foodsExcluidos: ex });
const aj = (o = {}) => Object.assign(A.nuevoAjuste(0), o);
const plan = (comidas, x = {}) => D.plan({ comidas, origenMarcas: x.om || {}, origenAjustes: x.oa || {}, origenLibres: x.ol || [],
  hoyMarcas: x.hm || {}, hoyAjustes: x.ha || {}, hoyLibres: x.hl || [], otroPlan: !!x.otro, kcal: () => 100 });

let p = plan([comida('d'), comida('a'), comida('m')], { om: { d: marca('B', 'comido', [1]), a: marca('A', 'saltado') }, oa: { m: aj({ omitida: true }) } });
eq(p.comidas.map(c => c.comidaId), ['d'], 'no se copia saltado ni omitida');
eq([p.comidas[0].opcion, p.comidas[0].marca.foodsExcluidos, p.comidas[0].estado], [1, [1], 'nueva'], 'lo comido');
const a1 = aj({ opcion: 1, deltaKcal: 50 });
p = plan([comida('d')], { oa: { d: a1 } });
eq([p.comidas.length, p.comidas[0].marca, p.comidas[0].opcion, p.comidas[0].conCantidades], [1, null, 1, true], 'solo ajuste');
p = plan([comida('d'), comida('a')], { om: { d: marca('A', 'comido'), a: marca('A', 'comido') }, hm: { d: marca('A', 'comido'), a: marca('B', 'comido') } });
eq(p.comidas.map(c => c.estado), ['igual', 'conflicto'], 'igual y conflicto');
p = plan([comida('d', ['A'])], { om: { d: marca('Z', 'comido') } });
eq(p.comidas, [], 'opción inexistente');
p = plan([comida('d')], { om: { d: marca('A', 'comido', [1, 7]) } });
eq(p.comidas[0].marca.foodsExcluidos, [1], 'tildes fuera de rango');
p = plan([comida('d')], { ol: [libre('1', 'Pizza', 500), libre('2', ' pizza ', 500.2)], hl: [libre('9', 'PIZZA', 500)] });
eq(p.libres.map(l => l.estado), ['igual', 'nueva'], 'libres por conteo');
p = plan([comida('d')], { om: { d: marca('A', 'comido') }, ol: [libre('1', 'x', 1)], otro: true });
eq([p.comidas.length, p.libres.length, p.otroPlan], [0, 1, true], 'otro plan');
eq(D.estado(null, aj(), null, aj(), 'A'), 'igual', 'ajustes iguales');
eq(D.estado(null, aj({ deltaKcal: 50 }), null, aj(), 'A'), 'conflicto', 'ajustes distintos');

// Comí, caso del 21/11: el total suma solo lo marcado.
let pedidas = 0;
p = D.plan({ comidas: [comida('d'), comida('a')], origenMarcas: { a: marca('B', 'comido') }, origenAjustes: { d: aj({ deltaKcal: 50 }) },
  origenLibres: [], hoyMarcas: {}, hoyAjustes: {}, hoyLibres: [], kcal: (c, m) => { pedidas++; assert.ok(m); return 500; } });
eq(pedidas, 1, 'las kcal solo se piden con marca');
const sd = p.comidas.find(c => c.comidaId === 'd'), sa = p.comidas.find(c => c.comidaId === 'a');
eq([sd.kcal, D.detalle(sd)], [0, 'Opción A, con ajustes, sin tocar Comí'], 'sin Comí la lista no muestra kcal');
eq(D.detalle(sa), 'Opción B, 500 kcal', 'con Comí, sus kcal');
for (const t of [D.detalle(sd), D.detalle(sa), A.TEXTO_SIN_COMI]) eq(/[—–«»·]/.test(t), false, `sin signos prohibidos: ${t}`);
const agr = (ts) => ({ nombre: 'Yogur', cantidad: 1, unidad: 'g', gramosUnidad: null, gramos: 100, kcal: 60, p: 5, c: 8, g: 1,
  por100: { kcal: 60, p: 5, c: 8, g: 1 }, origen: 'base', _ts: ts });
const comiHoy = marca('A', 'comido', [1]);
eq(D.marcaTrasCopiar(null, 'A', aj({ deltaKcal: 50 }), comiHoy, null), comiHoy, 'reemplazar conserva el Comí de hoy tal cual');
eq(D.marcaTrasCopiar(null, 'B', aj({ opcion: 1 }), comiHoy, null), marca('B', 'comido'), 'otra opción: Comí con la copiada');
eq(D.marcaTrasCopiar(null, 'A', aj({ agregados: [agr(7)] }), comiHoy, null), marca('A', 'comido'), 'otros agregados: todo tildado');
eq(D.marcaTrasCopiar(marca('B', 'comido', [0]), 'B', null, comiHoy, null), marca('B', 'comido', [0]), 'con marca ese día, esa');
eq(D.marcaTrasCopiar(null, 'A', aj({ deltaKcal: 50 }), marca('A', 'saltado'), null), null, 'Salté de hoy se va');
eq(D.marcaTrasCopiar(null, 'A', aj({ deltaKcal: 50 }), null, null), null, 'sin marca no se marca');
const a50 = aj({ deltaKcal: 50 });
eq(plan([comida('d')], { oa: { d: a50 }, hm: { d: comiHoy }, ha: { d: a50 } }).comidas[0].estado, 'igual', 'Comí hoy y lo mismo cargado: igual');
eq(plan([comida('d')], { oa: { d: a50 }, hm: { d: comiHoy } }).comidas[0].estado, 'conflicto', 'Comí hoy sin cargar: conflicto');
eq(plan([comida('d')], { oa: { d: a50 }, hm: { d: marca('A', 'saltado') }, ha: { d: a50 } }).comidas[0].estado, 'conflicto', 'Salté hoy: conflicto');
eq(A.avisoSinComi(null, a50, true), 'Cargada, falta tocar Comí', 'cargada sin Comí');
eq(A.avisoSinComi(null, aj({ agregados: [agr(3)] }), true), 'Cargada, falta tocar Comí', 'con agregados');
eq(A.avisoSinComi(null, aj({ cantidades: { 0: 80 } }), true), 'Cargada, falta tocar Comí', 'con gramos');
eq([A.avisoSinComi(marca('A', 'comido'), a50, true), A.avisoSinComi(marca('A', 'saltado'), a50, true), A.avisoSinComi(null, null, true),
  A.avisoSinComi(null, aj({ opcion: 1 }), true), A.avisoSinComi(null, aj({ omitida: true }), true), A.avisoSinComi(null, a50, false)],
  [null, null, null, null, null, null], 'sin aviso con marca, sin carga, omitida o fuera de la ventana');

// Tildes: siguen a cada agregado por su _ts.
eq(A.excluidosTrasCambio([0, 2, 3], 2, [10, 20], [20]), [0, 2], 'borrar el primero corre el tilde del segundo');
eq(A.excluidosTrasCambio([2], 2, [10], [10, 20]), [2], 'sumar no corre');
eq(A.excluidosTrasCambio([2], 2, [10], []), [], 'el tilde del borrado se va');
eq(A.excluidosTrasCambio([9], 2, [10], [10]), [], 'fuera de rango se cae');
console.log(`días de dieta: ${n} verificaciones OK`);
