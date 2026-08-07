/* =============================================================
   escenarios-cliente.mjs — el catálogo de "casos de cliente"

   QUÉ ES UN ESCENARIO
   La descripción completa de UN cliente: qué plan tiene, en qué semana está,
   cuánto entrenó, qué comió, si se pesa, si manda el check, si tiene datos de
   salud. O sea: todo lo que hace que la app se comporte distinto.

   POR QUÉ ESTÁN NOMBRADOS Y NO SON PERILLAS SUELTAS
   El producto cartesiano de las perillas es inmanejable y casi todo él es
   imposible en la vida real (nadie tiene 8 semanas de carga y cero sesiones).
   Estos son los casos que SÍ pasan, más los bordes que rompen la app. Cada uno
   tiene un motivo escrito de por qué está en la lista.

   Cada escenario declara solo lo que lo distingue; `base` pone el resto.
   ============================================================= */

const base = {
  perfil: 'natural',
  objetivo: 'Hipertrofia',
  split: 'ppl-6',
  semanasTotal: 12,
  semanaActual: 4,
  semanaOffset: 0,
  comidas: 4,
  opciones: 4,
  kcal: 2800,
  // Historia
  semanasEntrenadas: 3,     // cuántas semanas hacia atrás tienen sesiones
  adherenciaEntreno: 0.85,  // fracción de los días del plan efectivamente cerrados
  progresoCarga: 0.02,      // cuánto sube el peso por semana (2% = progresa)
  semanasChecks: 3,
  check: { energia: 4, descanso: 4, hambre: 3, adherencia: 4 },
  diasPeso: 21,
  tendenciaPeso: 0,         // kg por semana: + sube, − baja, 0 plano
  pesoInicial: 78,
  comidasMarcadas: 0.7,     // fracción de comidas marcadas por día
  diasComidas: 14,
  comentariosCoach: 0,
  salud: null,              // null | 'normal' | 'fatiga' | 'maladaptacion' | 'sin-reloj' | 'recien-conectado'
  conBloqueEnCola: false,
  sinDieta: false,
};

export const ESCENARIOS = {
  /* ── Los que existen de verdad, hoy, entre los 50 clientes ─────────── */

  'recien-vinculado': {
    _que: 'Le publicaron el plan y todavía no abrió la app. Es el día 1 de todo.',
    _mirar: 'Que no haya ni un solo NaN, ni un promedio de cero elementos, ni un "última vez" vacío. Es el estado que más clientes atraviesan y el que menos se prueba.',
    semanaActual: 1, semanasEntrenadas: 0, semanasChecks: 0, diasPeso: 0,
    diasComidas: 0, comidasMarcadas: 0, salud: null,
  },

  'primera-semana': {
    _que: 'Arrancó hace días: entrenó un par de veces, sin histórico previo.',
    _mirar: 'El hint de "primer día sin histórico" y que ningún ejercicio muestre "📅 Última vez" mintiendo.',
    semanaActual: 1, semanasEntrenadas: 1, semanasChecks: 1, diasPeso: 4,
    diasComidas: 5, salud: 'recien-conectado',
  },

  'en-ritmo': {
    _que: 'El cliente promedio: 4ª semana, entrena, come, se pesa, manda el check.',
    _mirar: 'Que todo se vea normal. Es la línea de base contra la que se comparan los demás.',
    salud: 'normal',
  },

  'macrociclo-2': {
    _que: 'Terminó el bloque de 12 y va por la semana 13 de 24. semana_offset = 12.',
    _mirar: 'Que NO diga "Semana de calibración" (la condición vive solo en el offset), y que el header, el eyebrow de la dieta y el botón de pasar de semana digan todos SEM 13/24 y no cuatro números distintos.',
    semanaActual: 1, semanaOffset: 12, semanasTotal: 12,
    semanasEntrenadas: 8, semanasChecks: 6, diasPeso: 60, salud: 'normal',
  },

  'ultima-semana-con-cola': {
    _que: 'Semana 12 de 12, con el bloque siguiente ya encolado por el coach.',
    _mirar: 'El botón de activar el bloque nuevo. Y después de activarlo: que el plan cambie de verdad y que las sesiones del bloque viejo no revivan.',
    semanaActual: 12, semanasEntrenadas: 10, semanasChecks: 8,
    diasPeso: 80, conBloqueEnCola: true, salud: 'normal',
  },

  'ultima-semana-sin-cola': {
    _que: 'Semana 12 de 12 y el coach no encoló nada. Pantalla sin salida.',
    _mirar: 'Qué le ofrece la app a alguien que terminó el plan y no tiene siguiente. Hoy: nada.',
    semanaActual: 12, semanasEntrenadas: 10, semanasChecks: 8, diasPeso: 80,
  },

  'abandonado': {
    _que: 'Entrenó 4 semanas y hace 3 que no aparece: sin sesiones, sin check, sin peso.',
    _mirar: 'Del lado del coach: que caiga en el radar. Es el que más plata cuesta y el que más tarda en detectarse.',
    semanaActual: 8, semanasEntrenadas: 4, semanasChecks: 4,
    diasPeso: 50, adherenciaEntreno: 0, salud: null,
  },

  'estancado': {
    _que: 'Entrena y cumple, pero la carga no sube hace 5 semanas y el peso está plano.',
    _mirar: 'Las señales de estancamiento del centinela y el balde "ajustar". El caso que justifica todo el motor de análisis.',
    semanaActual: 9, semanasEntrenadas: 8, semanasChecks: 8, progresoCarga: 0,
    diasPeso: 60, tendenciaPeso: 0, check: { energia: 3, descanso: 3, hambre: 4, adherencia: 4 },
    salud: 'fatiga',
  },

  'fundido': {
    _que: 'Adherencia alta pero energía y descanso por el piso, con recuperación en rojo.',
    _mirar: 'El cruce de señal objetiva (HRV/FC) con la subjetiva, y la bandera de discordancia.',
    semanaActual: 7, semanasEntrenadas: 6, semanasChecks: 6, progresoCarga: 0.005,
    check: { energia: 2, descanso: 1, hambre: 4, adherencia: 5 },
    diasPeso: 45, salud: 'maladaptacion',
  },

  'sin-reloj': {
    _que: 'iPhone sin Apple Watch: llegan pasos y actividad, nada de sueño ni pulso.',
    _mirar: 'Que la card de Recuperación explique que hace falta un reloj y NO ofrezca un botón de conectar. Es el caso de Mati y el bug que arreglamos.',
    salud: 'sin-reloj', semanasEntrenadas: 4, diasPeso: 30,
  },

  'come-mal': {
    _que: 'Entrena bien pero marca la mitad de las comidas y reporta hambre alta.',
    _mirar: 'Que la adherencia de dieta y la de entreno se cuenten por separado y no se promedien en una sola.',
    comidasMarcadas: 0.4, check: { energia: 3, descanso: 4, hambre: 5, adherencia: 2 },
    semanasEntrenadas: 5, semanasChecks: 5, diasPeso: 35, salud: 'normal',
  },

  'con-comentarios': {
    _que: 'Tiene comentarios del coach sin leer en varios ámbitos.',
    _mirar: 'El badge global y que cada comentario tenga una pantalla donde aparecer. Hay ámbitos que hoy no tienen ninguna.',
    comentariosCoach: 4, salud: 'normal',
  },

  /* ── Los bordes que rompen la app ──────────────────────────────────── */

  'sin-dieta': {
    _que: 'Tiene rutina publicada pero no dieta.',
    _mirar: 'Hoy ve SAMPLE_DIET (3200 kcal, 5 comidas) como si fuera su plan, sin ningún aviso. Come según una dieta que nadie le escribió.',
    sinDieta: true, semanasEntrenadas: 2,
  },

  'dieta-2-opciones': {
    _que: 'Comidas con 2 opciones en vez de 4.',
    _mirar: 'Que la grilla de pestañas A/B no se rompa ni deje huecos. La app asume 4 en varios lugares.',
    opciones: 2, semanasEntrenadas: 3,
  },

  'dieta-1-opcion': {
    _que: 'Una sola opción por comida: no hay nada que elegir.',
    _mirar: 'Que no muestre un selector de una sola pestaña.',
    opciones: 1, semanasEntrenadas: 3,
  },

  'plan-sin-macros': {
    _que: 'Dieta publicada SIN macros_target.',
    _mirar: 'ROMPE EL ARRANQUE ENTERO de la app, no solo la escena Dieta: pantalla en blanco, no puede ni entrenar. Es el peor estado publicable y hay que poder verlo.',
    dietaRota: { sinMacrosTarget: true }, semanasEntrenadas: 1,
  },

  'plan-sin-dias': {
    _que: 'Rutina publicada con dias: [].',
    _mirar: 'La app no arranca nunca. Se queda cargando.',
    rutinaRota: { diasVacios: true }, semanasEntrenadas: 0,
  },

  'dia-vacio': {
    _que: 'Un día del plan sin ejercicios.',
    _mirar: 'Progreso NaN y "sesión completa" de entrada, sin haber entrenado.',
    rutinaRota: { diaSinEjercicios: true }, semanasEntrenadas: 1,
  },

  'sin-descanso': {
    _que: 'Ejercicios sin descanso_segundos.',
    _mirar: 'Chip "NaN:NaN" y el timer de descanso que no termina nunca.',
    rutinaRota: { sinDescanso: true }, semanasEntrenadas: 2,
  },

  'alimentos-por-unidad': {
    _que: 'Alimentos con unit "unidad" y sin unitGrams — como publica el Cerebro HOY.',
    _mirar: 'Qué hace el swap y el cálculo de macros cuando no sabe cuántos gramos es "2 unidades". Afecta a TODA dieta publicada.',
    dietaRota: { sinUnitGrams: true }, semanasEntrenadas: 3,
  },
};

/** Devuelve el escenario completo (base + overrides), o null si no existe. */
export function resolver(nombre) {
  const e = ESCENARIOS[nombre];
  if (!e) return null;
  return { ...base, ...e, _nombre: nombre };
}

export const NOMBRES = Object.keys(ESCENARIOS);
