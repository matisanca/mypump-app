#!/usr/bin/env node
/* =============================================================
 * vectores-presion.mjs — arma scripts/vectores-app/presion.json con public/js/presion.js.
 *
 * Los casos clínicos llevan a mano lo que tiene que dar según presion/PROTOCOLO.md (`espera`): si la referencia
 * no da eso, no escribe nada. El archivo que sale lo leen también el kit de iOS, el de Android
 * (apps/shared/vectores/presion.json en la rama de las apps) y el ensayo del SQL.
 * USO:  node scripts/vectores-presion.mjs [--copiar <ruta a apps/shared/vectores>]
 * ============================================================= */
import { createRequire } from 'node:module';
import assert from 'node:assert/strict';
import fs from 'node:fs';
const require = createRequire(import.meta.url);
const P = require('../public/js/presion.js');

const t = (sis, dia, pulso = 62, extra = {}) => ({ orden: 0, posicion: 'sentado', sis, dia, pulso, latido_irregular: false, ...extra });
const tomas = (...ts) => ts.map((x, i) => ({ ...x, orden: i + 1 }));
const ses = (extra = {}, ...ts) => ({
  tipo: 'estandar', previo: { cafeina: false, fumo: false, comida: false, ejercicio: false }, reposo_cumplido: true, temporizador_salteado: false,
  entreno_entre_dosis_y_toma: null, sintomas: [], lista_espera: null, minutos_desde_ultima: 0, tomas: tomas(...ts), ...extra,
});
const subconjunto = (sale, espera, nombre) => {
  for (const k of Object.keys(espera)) assert.deepEqual(sale[k], espera[k], `${nombre}: ${k}`);
};

// ── Tomas sueltas ──
const validar = [
  [t(120, 80, 60), 'ok'], [t(159, 99, 119), 'ok'], [t(160, 90), 'confirmar'], [t(150, 100), 'confirmar'], [t(120, 80, 120), 'confirmar'],
  [t(120, 80, 40), 'confirmar'], [t(120, 80, 41), 'ok'], [t(59, 40), 'imposible'], [t(60, 40), 'ok'], [t(261, 100), 'imposible'], [t(260, 100), 'confirmar'],
  [t(120, 29), 'imposible'], [t(200, 161), 'imposible'], [t(120, 80, 24), 'imposible'], [t(120, 80, 221), 'imposible'], [t(100, 100), 'imposible'],
  [t(100, 91), 'imposible'], [t(100, 90), 'ok'], [t(80, 120), 'imposible'], [{ sis: 120.5, dia: 80, pulso: 60 }, 'imposible'], [{ sis: 120, dia: 80 }, 'imposible'],
].map(([toma, sale]) => ({ toma: { sis: toma.sis, dia: toma.dia, pulso: toma.pulso }, sale }));
const nivel = [[179, 119, 'alta'], [180, 80, 'urgencia'], [150, 120, 'urgencia'], [160, 80, 'alta'], [140, 100, 'alta'], [159, 99, 'comun'], [135, 85, 'comun']]
  .map(([sis, dia, sale]) => ({ toma: { sis, dia }, sale }));
const tramo = [[0, null], [21.9, 'menos_22'], [22, 'estandar'], [31.9, 'estandar'], [32, 'grande'], [41.9, 'grande'], [42, 'extra_grande'], [52, 'extra_grande'], [52.1, 'mas_52'], [60, 'mas_52']]
  .map(([cm, sale]) => ({ cm, sale }));
const ap = (tipo, validado, imp, val) => ({ tipo, validado, manguito_min_cm: imp ? imp[0] : null, manguito_max_cm: imp ? imp[1] : null,
  manguito_validado_min_cm: val ? val[0] : null, manguito_validado_max_cm: val ? val[1] : null });
const calza = [
  [38, ap('brazo', 'si', [22, 42], [22, 42]), true], [42, ap('brazo', 'si', [22, 42], [22, 42]), false], [41.9, ap('brazo', 'si', [22, 42], null), true],
  [33, ap('brazo', 'si', [22, 42], [22, 32]), false], [32, ap('brazo', 'si', [22, 32], null), false], [31.5, ap('brazo', 'si', [22, 32], null), true],
  [52, ap('brazo', 'si', [32, 52], null), true], [45, ap('brazo', 'si', [31, 45], null), true], [38.5, ap('brazo', 'si', [22, 42], [25, 38.5]), true],
  [39, ap('brazo', 'si', [22, 42], [25, 38.5]), false], [21, ap('brazo', 'si', [22, 42], null), false], [35, ap('brazo', 'sin_revisar', null, null), null],
].map(([cm, aparato, sale]) => ({ cm, aparato, sale }));
const metodo = [
  [35, ap('brazo', 'si'), { metodo: 'brazo', provisoria: false, pedir_brazo: false, pedir_validado: false, admite_tomas: true }],
  [35, ap('brazo', 'sin_revisar'), { metodo: 'brazo', provisoria: false, pedir_brazo: false, pedir_validado: false, admite_tomas: true }],
  [35, ap('brazo', 'no'), { metodo: 'brazo', provisoria: true, pedir_brazo: false, pedir_validado: true, admite_tomas: true }],
  [35, ap('muneca', 'si'), { metodo: 'muneca_provisoria', provisoria: true, pedir_brazo: true, pedir_validado: false, admite_tomas: true }],
  [52, ap('muneca', 'si'), { metodo: 'muneca_provisoria', provisoria: true, pedir_brazo: true, pedir_validado: false, admite_tomas: true }],
  [54, ap('muneca', 'si'), { metodo: 'muneca_habitual', provisoria: false, pedir_brazo: false, pedir_validado: false, admite_tomas: true }],
  [54, ap('muneca', 'no'), { metodo: 'muneca_habitual', provisoria: false, pedir_brazo: false, pedir_validado: true, admite_tomas: true }],
  [35, ap('reloj_anillo_otro', 'no'), { metodo: 'no_sirve', provisoria: false, pedir_brazo: true, pedir_validado: false, admite_tomas: false }],
].map(([cm, aparato, sale]) => ({ cm, aparato, sale }));
const momento = [[3, 'otro'], [4, 'manana'], [11, 'manana'], [12, 'otro'], [20, 'otro']].map(([hora, sale]) => ({ hora, sale }));
const pasos = [['estandar', null], ['bajo_efecto', null], ['suelta', null], ['ortostatica', 'acostado_parado'], ['ortostatica', 'sentado_parado'], ['comparacion_brazos', null]]
  .map(([tipo, variante]) => ({ tipo, variante, sale: P.pasos(tipo, variante) }));

// ── Sesiones: [nombre, entrada, lo que tiene que dar según el protocolo] ──
const cafe = { cafeina: true, fumo: false, comida: false, ejercicio: false };
const S = [
  ['toma común, cuenta', ses({}, t(124, 78)), { paso: 'listo', texto: 'ninguno', cuenta: true, motivo_exclusion: null, reglas: [], urgencia: false }],
  ['café previo: no cuenta', ses({ previo: cafe }, t(124, 78)), { paso: 'listo', texto: 'toma_no_cuenta', cuenta: false, motivo_exclusion: 'condicion_incumplida', reglas: [] }],
  ['entreno en la última hora: no cuenta', ses({ previo: { ...cafe, cafeina: false, ejercicio: true } }, t(118, 70)), { cuenta: false, texto: 'toma_no_cuenta' }],
  ['temporizador salteado: no cuenta', ses({ reposo_cumplido: false, temporizador_salteado: true }, t(124, 78)), { cuenta: false, motivo_exclusion: 'condicion_incumplida', texto: 'toma_no_cuenta' }],
  ['160/100: repetir a los 5 minutos', ses({}, t(162, 94)), { paso: 'repetir', texto: 'quedate_sentado_5min', cuenta: false, reglas: [], urgencia: false }],
  ['diastólica 100: repetir', ses({}, t(150, 100)), { paso: 'repetir', texto: 'quedate_sentado_5min' }],
  ['160/100 sin repetir a los 10 minutos: recordatorio, no es alta', ses({ minutos_desde_ultima: 10 }, t(165, 95)), { paso: 'repetir', texto: 'repetir_pendiente', reglas: ['repetir_pendiente'], cuenta: false }],
  ['160/100 confirmada: alta, vale el promedio de las dos', ses({}, t(164, 96), t(160, 92)), { paso: 'listo', texto: 'ninguno', cuenta: true, valor: { sis: 162, dia: 94, pulso: 62 }, reglas: ['alta_toma_160_100'], urgencia: false }],
  ['160/100 que baja: no es alta y cuenta el promedio', ses({}, t(162, 90), t(148, 88)), { paso: 'listo', cuenta: true, valor: { sis: 155, dia: 89, pulso: 62 }, reglas: [] }],
  ['café previo y 160/100 confirmada: no cuenta pero es alta', ses({ previo: cafe }, t(170, 100), t(166, 101)), { cuenta: false, motivo_exclusion: 'condicion_incumplida', reglas: ['alta_toma_160_100'] }],
  ['180/120: espera con la lista de síntomas', ses({}, t(184, 110)), { paso: 'repetir_con_lista', texto: 'lista_sintomas_espera', reglas: [], urgencia: false, cuenta: false }],
  ['diastólica 120: espera con la lista', ses({}, t(170, 120)), { paso: 'repetir_con_lista', texto: 'lista_sintomas_espera' }],
  ['180/120 con un Sí en la espera: guardia por síntomas en el acto', ses({ lista_espera: 'si', sintomas: ['dolor_pecho'] }, t(186, 112)), { paso: 'guardia_sintomas', texto: 'guardia_sintomas', urgencia: true, reglas: ['sintoma_alarma_en_espera'] }],
  ['180/120 con todos en No: sigue la espera', ses({ lista_espera: 'no' }, t(186, 112)), { paso: 'repetir_con_lista', texto: 'lista_sintomas_espera', urgencia: false, reglas: [] }],
  ['180/120 confirmada: guardia por presión', ses({ lista_espera: 'no' }, t(186, 112), t(182, 108)), { paso: 'guardia_presion', texto: 'guardia_presion', urgencia: true, reglas: ['toma_180_120_confirmada'] }],
  ['180 confirmada por la diastólica de 120', ses({}, t(182, 100), t(170, 121)), { paso: 'guardia_presion', urgencia: true, reglas: ['toma_180_120_confirmada'] }],
  ['180/120 que baja a 160/100: alta, sin guardia', ses({ lista_espera: 'no' }, t(184, 104), t(168, 100)), { paso: 'listo', texto: 'ninguno', urgencia: false, reglas: ['alta_toma_160_100'], cuenta: true }],
  ['180/120 que baja de 160/100: nada especial', ses({ lista_espera: 'no' }, t(182, 98), t(150, 92)), { paso: 'listo', urgencia: false, reglas: [], cuenta: true, valor: { sis: 166, dia: 95, pulso: 62 } }],
  ['diastólica confirmada de 110 a 119: alta, no urgencia', ses({}, t(150, 114), t(150, 112)), { paso: 'listo', urgencia: false, reglas: ['alta_toma_160_100'] }],
  ['180/120 sin repetir a los 10 minutos: recordatorio con la lista', ses({ minutos_desde_ultima: 10 }, t(190, 110)), { paso: 'repetir_con_lista', texto: 'repetir_pendiente', reglas: [], urgencia: false }],
  ['180/120 sin repetir a los 15 minutos: cuenta como alta', ses({ minutos_desde_ultima: 15 }, t(190, 110)), { paso: 'repetir_con_lista', texto: 'repetir_pendiente', reglas: ['alta_180_120_sin_repetir'], urgencia: false }],
  ['160 y después 180: alta y pide otra con la lista', ses({}, t(166, 96), t(184, 100)), { paso: 'repetir_con_lista', texto: 'lista_sintomas_espera', reglas: ['alta_toma_160_100'], urgencia: false }],
  ['160, 180 y 180: guardia por presión', ses({ lista_espera: 'no' }, t(166, 96), t(184, 100), t(181, 99)), { paso: 'guardia_presion', urgencia: true, reglas: ['toma_180_120_confirmada'] }],
  ['síntoma de alarma con presión común: guardia por síntomas', ses({ sintomas: ['falta_aire'] }, t(122, 78)), { paso: 'guardia_sintomas', texto: 'guardia_sintomas', urgencia: true, reglas: ['sintoma_alarma'] }],
  ['desmayo: guardia y regla propia', ses({ sintomas: ['desmayo'] }, t(110, 70)), { paso: 'guardia_sintomas', urgencia: true, reglas: ['desmayo', 'sintoma_alarma'] }],
  ['desmayo en el esfuerzo: alarma', ses({ sintomas: ['desmayo_en_esfuerzo'] }, t(110, 70)), { paso: 'guardia_sintomas', urgencia: true, reglas: ['desmayo', 'sintoma_alarma'] }],
  ['pulso 120 con palpitaciones: urgencia', ses({ sintomas: ['palpitaciones'] }, t(128, 80, 124)), { paso: 'guardia_sintomas', texto: 'guardia_sintomas', urgencia: true, reglas: ['pulso_120_sintomas'] }],
  ['pulso 120 sin síntomas: nada', ses({}, t(128, 80, 124)), { paso: 'listo', urgencia: false, reglas: [] }],
  ['pulso 119 con palpitaciones: no es urgencia', ses({ sintomas: ['palpitaciones'] }, t(128, 80, 119)), { paso: 'listo', urgencia: false, reglas: [] }],
  ['pulso 40 con mareo: urgencia', ses({ sintomas: ['mareo_al_pararse'] }, t(112, 70, 40)), { paso: 'guardia_sintomas', urgencia: true, reglas: ['pulso_40_mareo', 'sintomas_al_pararse'] }],
  ['pulso 40 sin síntomas: aviso', ses({}, t(112, 70, 38)), { paso: 'listo', urgencia: false, reglas: ['pulso_40_sin_sintomas'] }],
  ['sistólica menor de 90 con mareo: sentate y agua', ses({ sintomas: ['mareo_al_pararse'] }, t(88, 56)), { paso: 'listo', texto: 'sentate_agua', urgencia: false, reglas: ['sintomas_al_pararse', 'sistolica_menor_90_sintomas'] }],
  ['sistólica menor de 90 sin síntomas: nada', ses({}, t(88, 56)), { paso: 'listo', texto: 'ninguno', reglas: [] }],
  ['vómitos o diarrea: al brief', ses({ sintomas: ['vomitos_diarrea'] }, t(110, 70)), { paso: 'listo', urgencia: false, reglas: ['sintoma_vomitos_diarrea'] }],
  ['suelta de 135/85: dispara una serie', ses({ tipo: 'suelta' }, t(136, 80)), { paso: 'listo', cuenta: false, motivo_exclusion: 'otra', reglas: ['suelta_135_85'] }],
  ['suelta por debajo: nada', ses({ tipo: 'suelta' }, t(134, 84)), { cuenta: false, reglas: [] }],
  ['suelta de 160/100 confirmada: alta', ses({ tipo: 'suelta' }, t(162, 100), t(160, 98)), { reglas: ['alta_toma_160_100', 'suelta_135_85'], urgencia: false }],
  ['suelta de 180/120 confirmada: urgencia', ses({ tipo: 'suelta' }, t(190, 120), t(188, 118)), { paso: 'guardia_presion', urgencia: true }],
  ['bajo efecto válida', ses({ tipo: 'bajo_efecto', entreno_entre_dosis_y_toma: false }, t(142, 86, 96)), { cuenta: false, motivo_exclusion: 'bajo_efecto', valida_bajo_efecto: true, texto: 'ninguno' }],
  ['bajo efecto con entreno entre la dosis y la toma: no cuenta', ses({ tipo: 'bajo_efecto', entreno_entre_dosis_y_toma: true }, t(130, 80)), { valida_bajo_efecto: false, texto: 'toma_no_cuenta' }],
  ['bajo efecto sin reposo: no vale', ses({ tipo: 'bajo_efecto', entreno_entre_dosis_y_toma: false, reposo_cumplido: false }, t(130, 80)), { valida_bajo_efecto: false }],
  ['bajo efecto de 180/120 confirmada: urgencia igual', ses({ tipo: 'bajo_efecto', entreno_entre_dosis_y_toma: true }, t(182, 110), t(180, 112)), { paso: 'guardia_presion', urgencia: true, valida_bajo_efecto: false }],
  ['ortostática sin caída', ses({ tipo: 'ortostatica' }, t(124, 76, 58, { posicion: 'acostado' }), t(120, 78, 72, { posicion: 'de_pie', minutos_de_pie: 1 }), t(122, 79, 70, { posicion: 'de_pie', minutos_de_pie: 3 })),
    { paso: 'listo', cuenta: false, motivo_exclusion: 'ortostatica', reglas: [], ortostatica: { caida_sis_max: 4, caida_dia_max: -2, subida_pulso_max: 14, hipotension: false, hipertension_posible: false } }],
  ['ortostática con caída de 20', ses({ tipo: 'ortostatica' }, t(130, 80, 60, { posicion: 'acostado' }), t(110, 78, 80, { posicion: 'de_pie', minutos_de_pie: 1 }), t(118, 80, 76, { posicion: 'de_pie', minutos_de_pie: 3 })),
    { reglas: ['ortostatica_positiva'], ortostatica: { caida_sis_max: 20, caida_dia_max: 2, subida_pulso_max: 20, hipotension: true, hipertension_posible: false } }],
  ['ortostática con caída de la diastólica de 10', ses({ tipo: 'ortostatica' }, t(120, 80, 60, { posicion: 'acostado' }), t(112, 70, 70, { posicion: 'de_pie', minutos_de_pie: 1 })),
    { reglas: ['ortostatica_positiva'] }],
  ['ortostática con subida de 20: hipertensión ortostática posible', ses({ tipo: 'ortostatica' }, t(120, 78, 60, { posicion: 'acostado' }), t(141, 84, 66, { posicion: 'de_pie', minutos_de_pie: 1 })),
    { reglas: [], ortostatica: { caida_sis_max: -21, caida_dia_max: -6, subida_pulso_max: 6, hipotension: false, hipertension_posible: true } }],
  ['ortostática con mareo: quedate sentado', ses({ tipo: 'ortostatica', sintomas: ['mareo_al_pararse'] }, t(120, 78, 60, { posicion: 'acostado' }), t(116, 76, 70, { posicion: 'de_pie', minutos_de_pie: 1 })),
    { texto: 'quedate_sentado_ortostatica', reglas: ['sintomas_al_pararse'], urgencia: false }],
  ['de pie con 180: no cuenta para la alta', ses({ tipo: 'ortostatica' }, t(150, 90, 60, { posicion: 'acostado' }), t(182, 100, 70, { posicion: 'de_pie', minutos_de_pie: 1 }), t(181, 100, 70, { posicion: 'de_pie', minutos_de_pie: 3 })),
    { paso: 'listo', urgencia: false, reglas: [] }],
  ['comparación de brazos: no cuenta ni pide repetir', ses({ tipo: 'comparacion_brazos' }, t(128, 80, 60, { brazo: 'izq' }), t(140, 82, 60, { brazo: 'der' }), t(138, 82, 60, { brazo: 'der' }), t(126, 80, 60, { brazo: 'izq' })),
    { paso: 'listo', cuenta: false, motivo_exclusion: 'comparacion_brazos', reglas: [] }],
  ['sin tomas', ses({}), { paso: 'listo', cuenta: false, motivo_exclusion: 'error', valor: null, reglas: [] }],
];
const sesion = S.map(([nombre, entrada, espera]) => {
  const sale = P.evaluarSesion(entrada);
  subconjunto(sale, espera, nombre);
  return { nombre, entrada, sale };
});

// ── Series ──
const dia = (fecha, s) => ({ fecha, ...s });
const serie = (extra, ...sesiones) => ({ serie: { tipo: 'estandar', tomas_objetivo: 3, fecha_inicio: '2026-11-04' }, solo_urgencias: false, basal_pulso: null, sesiones, ...extra });
const be = (fecha, sis, dia_, pulso, entreno = false) => dia(fecha, ses({ tipo: 'bajo_efecto', entreno_entre_dosis_y_toma: entreno }, t(sis, dia_, pulso)));
const R = [
  ['ejemplo de CAMPOS: 131/81 limítrofe', serie({}, dia('2026-11-04', ses({}, t(130, 80, 62))), dia('2026-11-05', ses({}, t(134, 84, 63))), dia('2026-11-06', ses({ previo: cafe }, t(140, 86, 70))), dia('2026-11-07', ses({}, t(129, 79, 61)))),
    { tomas_validas: 3, dias: ['2026-11-04', '2026-11-05', '2026-11-07'], serie_valida: true, faltan: 0, promedio: { sis: 131, dia: 81, pulso: 62 }, maximos: { sis: 134, dia: 84 }, categoria: 'limitrofe', reglas: [] }],
  ['sin tomas', serie({}), { tomas_validas: 0, serie_valida: false, faltan: 3, promedio: null, maximos: null, categoria: null, reglas: [] }],
  ['incompleta, 2 de 3', serie({}, dia('2026-11-04', ses({}, t(120, 78))), dia('2026-11-06', ses({}, t(122, 76)))), { tomas_validas: 2, serie_valida: false, faltan: 1, categoria: null, promedio: { sis: 121, dia: 77, pulso: 62 } }],
  ['dos tomas el mismo día cuentan como una', serie({}, dia('2026-11-04', ses({ orden: 1 }, t(120, 78))), dia('2026-11-04', ses({ orden: 2 }, t(140, 90))), dia('2026-11-05', ses({}, t(122, 76)))), { tomas_validas: 2, dias: ['2026-11-04', '2026-11-05'], promedio: { sis: 121, dia: 77, pulso: 62 } }],
  ['fuera de los 7 días no cuenta', serie({}, dia('2026-11-04', ses({}, t(120, 78))), dia('2026-11-10', ses({}, t(122, 76))), dia('2026-11-11', ses({}, t(124, 76)))), { tomas_validas: 2, dias: ['2026-11-04', '2026-11-10'], serie_valida: false }],
  ['promedio de 135: alta', serie({}, dia('2026-11-04', ses({}, t(134, 80))), dia('2026-11-05', ses({}, t(136, 82))), dia('2026-11-06', ses({}, t(135, 81)))), { promedio: { sis: 135, dia: 81, pulso: 62 }, categoria: 'hipertension_casa', reglas: ['alta_promedio_135_85'] }],
  ['promedio con diastólica de 85: alta', serie({}, dia('2026-11-04', ses({}, t(124, 85))), dia('2026-11-05', ses({}, t(126, 86))), dia('2026-11-06', ses({}, t(122, 84)))), { promedio: { sis: 124, dia: 85, pulso: 62 }, categoria: 'hipertension_casa', reglas: ['alta_promedio_135_85'] }],
  ['134/84: limítrofe, sin alta', serie({}, dia('2026-11-04', ses({}, t(134, 84))), dia('2026-11-05', ses({}, t(134, 84))), dia('2026-11-06', ses({}, t(134, 84)))), { categoria: 'limitrofe', reglas: [] }],
  ['124/78: elevada', serie({}, dia('2026-11-04', ses({}, t(124, 78))), dia('2026-11-05', ses({}, t(124, 78))), dia('2026-11-06', ses({}, t(124, 78)))), { categoria: 'elevada', reglas: [] }],
  ['118/76: óptima', serie({}, dia('2026-11-04', ses({}, t(118, 76))), dia('2026-11-05', ses({}, t(118, 76))), dia('2026-11-06', ses({}, t(118, 76)))), { categoria: 'optima', reglas: [] }],
  ['150/95: estadio 2 de NICE', serie({}, dia('2026-11-04', ses({}, t(150, 90))), dia('2026-11-05', ses({}, t(152, 92))), dia('2026-11-06', ses({}, t(148, 88)))), { categoria: 'hipertension_casa_estadio_2', reglas: ['alta_promedio_135_85'] }],
  ['incompleta con valores altos: no hay alta por promedio', serie({}, dia('2026-11-04', ses({}, t(150, 92))), dia('2026-11-05', ses({}, t(152, 94)))), { serie_valida: false, categoria: null, reglas: [] }],
  ['un día con repetición vale el promedio de las dos', serie({}, dia('2026-11-04', ses({}, t(164, 100), t(150, 90))), dia('2026-11-05', ses({}, t(130, 80))), dia('2026-11-06', ses({}, t(130, 80)))),
    { promedio: { sis: 139, dia: 85, pulso: 62 }, maximos: { sis: 164, dia: 100 }, reglas: ['alta_promedio_135_85'] }],
  ['alta por toma confirmada dentro de la serie', serie({}, dia('2026-11-04', ses({}, t(164, 100), t(162, 98))), dia('2026-11-05', ses({}, t(120, 70)))), { reglas: ['alta_toma_160_100'], serie_valida: false }],
  ['muñeca solo para urgencias: sin categoría ni alta por promedio', serie({ solo_urgencias: true }, dia('2026-11-04', ses({}, t(140, 90))), dia('2026-11-05', ses({}, t(140, 90))), dia('2026-11-06', ses({}, t(140, 90)))), { serie_valida: true, categoria: null, reglas: [] }],
  ['pulso de 100 en 2 de las 3 tomas', serie({}, dia('2026-11-04', ses({}, t(120, 78, 102))), dia('2026-11-05', ses({}, t(120, 78, 100))), dia('2026-11-06', ses({}, t(120, 78, 80)))), { reglas: ['pulso_100_dos_tomas'] }],
  ['pulso 20 por encima de la basal', serie({ basal_pulso: 58 }, dia('2026-11-04', ses({}, t(120, 78, 78))), dia('2026-11-05', ses({}, t(120, 78, 78))), dia('2026-11-06', ses({}, t(120, 78, 78)))), { reglas: ['pulso_20_sobre_basal'] }],
  ['pulso 19 por encima de la basal: nada', serie({ basal_pulso: 59 }, dia('2026-11-04', ses({}, t(120, 78, 78))), dia('2026-11-05', ses({}, t(120, 78, 78))), dia('2026-11-06', ses({}, t(120, 78, 78)))), { reglas: [] }],
  ['latido irregular en 2 tomas', serie({}, dia('2026-11-04', ses({}, t(120, 78, 62, { latido_irregular: true }))), dia('2026-11-05', ses({ previo: cafe }, t(120, 78, 62, { latido_irregular: true })))), { reglas: ['latido_irregular_2_tomas'] }],
  ['bajo efecto de 150/95: alta', serie({ serie: { tipo: 'bajo_efecto', tomas_objetivo: 3, fecha_inicio: '2026-11-04' } }, be('2026-11-04', 152, 90, 88), be('2026-11-05', 150, 92, 90), be('2026-11-06', 148, 94, 86)),
    { tomas_validas: 3, serie_valida: true, categoria: null, bajo_efecto: { n: 3, validas: 3, promedio: { sis: 150, dia: 92, pulso: 88 }, tomas_pulso_100_o_mas: 0, aviso: false, alta: true }, reglas: ['alta_bajo_efecto_150_95'] }],
  ['bajo efecto de 135/85 a 149/94: aviso', serie({ serie: { tipo: 'bajo_efecto', tomas_objetivo: 3, fecha_inicio: '2026-11-04' } }, be('2026-11-04', 140, 86, 90), be('2026-11-05', 138, 84, 92)),
    { tomas_validas: 2, serie_valida: false, bajo_efecto: { n: 2, validas: 2, promedio: { sis: 139, dia: 85, pulso: 91 }, tomas_pulso_100_o_mas: 0, aviso: true, alta: false }, reglas: ['bajo_efecto_135_85'] }],
  ['bajo efecto con una sola válida: sin promedio', serie({ serie: { tipo: 'bajo_efecto', tomas_objetivo: 3, fecha_inicio: '2026-11-04' } }, be('2026-11-04', 160, 98, 90, true), be('2026-11-05', 156, 96, 92)),
    { tomas_validas: 1, bajo_efecto: { n: 2, validas: 1, promedio: null, tomas_pulso_100_o_mas: 0, aviso: false, alta: false }, reglas: [] }],
  ['bajo efecto con pulso de 100 en 2 tomas: aviso', serie({ serie: { tipo: 'bajo_efecto', tomas_objetivo: 3, fecha_inicio: '2026-11-04' } }, be('2026-11-04', 128, 80, 104), be('2026-11-05', 126, 78, 100)), { reglas: ['pulso_100_bajo_efecto'] }],
  ['tomas comunes y bajo efecto en la misma serie: aparte', serie({}, dia('2026-11-04', ses({}, t(124, 78))), dia('2026-11-05', ses({}, t(126, 80))), dia('2026-11-06', ses({}, t(122, 76))), be('2026-11-04', 152, 96, 90), be('2026-11-05', 154, 96, 92)),
    { tomas_validas: 3, promedio: { sis: 124, dia: 78, pulso: 62 }, categoria: 'elevada', reglas: ['alta_bajo_efecto_150_95'] }],
];
const series = R.map(([nombre, entrada, espera]) => {
  const sale = P.resumenSerie(entrada);
  subconjunto(sale, espera, nombre);
  return { nombre, entrada, sale };
});

// Chequeos sueltos contra el protocolo.
assert.equal(P.validarToma(validar[0].toma), 'ok');
for (const v of validar) assert.equal(P.validarToma(v.toma), v.sale, `validar ${JSON.stringify(v.toma)}`);
for (const v of nivel) assert.equal(P.nivelToma(v.toma), v.sale, `nivel ${JSON.stringify(v.toma)}`);
for (const v of tramo) assert.equal(P.tramoBrazo(v.cm), v.sale, `tramo ${v.cm}`);
for (const v of calza) assert.equal(P.manguitoCalza(v.cm, v.aparato), v.sale, `calza ${v.cm} ${JSON.stringify(v.aparato)}`);
for (const v of metodo) assert.deepEqual(P.metodo(v.cm, v.aparato), v.sale, `método ${v.cm} ${v.aparato.tipo}`);
for (const v of momento) assert.equal(P.momento(v.hora), v.sale);

const T = P.T, N = P.N;
const textos = {
  ...Object.fromEntries(Object.entries(T).filter(([, v]) => typeof v !== 'function')),
  comoIzq: T.como('izq'), comoDer: T.como('der'), ortostaticaAcostado: T.ortostatica(false), ortostaticaSentado: T.ortostatica(true),
  g6Acostado: T.g6(false), g6Sentado: T.g6(true), faltan1: T.faltan(1), faltan2: T.faltan(2), avanceAlt2: T.avanceAlt(2, 3),
};
const propios = { ...Object.fromEntries(Object.entries(N).filter(([, v]) => typeof v !== 'function')), minutoParado1: N.minutoParado(1), minutoParado3: N.minutoParado(3), graficoAlt3: N.graficoAlt(3) };
// Ningún texto dice quién calcula ni usa palabras que el alumno no ve.
const todo = JSON.stringify([textos, propios]);
for (const mal of [/\bIA\b/, /inteligencia artificial/i, /tu coach/i, /tu entrenador/i, /hipertensi/i, /\bnormal\b/i, /riesgo/i, /no entren/i]) assert.ok(!mal.test(todo), `texto prohibido: ${mal}`);

const salida = {
  _: 'Presión arterial: lo que comparten la web, el kit de iOS, el de Android y el servidor (presion/PROTOCOLO.md y CAMPOS.md). Lo arma scripts/vectores-presion.mjs de la rama web; no se edita a mano.',
  limites: P.LIM, espera_repeticion_s: P.ESPERA_REPETICION_S, reposo_s: P.REPOSO_S, recordatorio_min: P.RECORDATORIO_MIN, sin_repetir_min: P.SIN_REPETIR_MIN,
  alarma: P.ALARMA, otros: P.OTROS, sintomas: P.SINTOMAS,
  validar, nivel, tramo, calza, metodo, momento, pasos, sesion, serie: series, textos, propios,
};
const json = JSON.stringify(salida, null, 1) + '\n';
fs.writeFileSync(new URL('./vectores-app/presion.json', import.meta.url), json);
const i = process.argv.indexOf('--copiar');
if (i > 0) fs.writeFileSync(`${process.argv[i + 1]}/presion.json`, json);
console.log(`presion.json: ${sesion.length} sesiones, ${series.length} series, ${validar.length + nivel.length + tramo.length + calza.length + metodo.length + momento.length + pasos.length} casos sueltos`);
