/* =============================================================
   plan-sintetico.mjs — rutinas y dietas de mentira con forma de verdad

   POR QUÉ ACÁ Y NO EN public/
   Esto es andamiaje de pruebas. `npx cap sync ios` copia public/ entero al
   binario que se manda a Apple — ya pasó con el mock de HealthKit y hubo que
   sacarlo del pipeline. Lo que no necesita el navegador, vive en scripts/.

   QUÉ GENERA
   Las dos estructuras JSON que el Cerebro publica en mypump_rutinas.estructura
   y mypump_dietas.estructura. La forma está calcada de supabase/seed/
   01_test_rutina.sql y de lo que consume cliente.html — si esto se desviara,
   el banco probaría una app que no existe.

   LAS PERILLAS SON LAS QUE CAMBIAN LA UI DE VERDAD
   No hay un parámetro por campo: hay uno por cada cosa que hace que la app se
   comporte distinto. Ver docs/BANCO_PRUEBAS_SALUD.md.
   ============================================================= */

/* PRNG determinista: misma semilla, mismo plan. Sin esto un caso que falla es
 * irreproducible. */
export function mulberry32(a) {
  return function () {
    a |= 0; a = (a + 0x6D2B79F5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

const DIAS_ID = ['lun', 'mar', 'mie', 'jue', 'vie', 'sab', 'dom'];
const DIAS_ABR = ['LUN', 'MAR', 'MIE', 'JUE', 'VIE', 'SAB', 'DOM'];

/* Catálogo mínimo pero real: los nombres tienen que existir en el catálogo de
 * ejercicios para que el matcher de imágenes y el swap por patrón de
 * movimiento tengan de dónde agarrarse. Salieron de rutinas publicadas. */
const EJERCICIOS = {
  espalda: [
    ['Jalón al pecho prono', 'compuesto'], ['Remo con barra', 'compuesto'],
    ['Remo en polea baja', 'compuesto'], ['Pullover en polea', 'aislado'],
  ],
  pecho: [
    ['Press banca', 'compuesto'], ['Press inclinado con mancuernas', 'compuesto'],
    ['Aperturas en polea', 'aislado'], ['Fondos en paralelas', 'compuesto'],
  ],
  // 7 de pierna a propósito: un día de LOWER puro con 6 ejercicios es un caso
  // real, y con 5 en el pool la perilla `ejerciciosPorDia` mentía en silencio.
  pierna: [
    ['Sentadilla libre', 'compuesto'], ['Prensa 45°', 'compuesto'],
    ['Curl femoral tumbado', 'aislado'], ['Extensión de cuádriceps', 'aislado'],
    ['Peso muerto rumano', 'compuesto'], ['Hip thrust', 'compuesto'],
    ['Elevación de gemelos de pie', 'aislado'],
  ],
  hombro: [
    ['Press militar con mancuernas', 'compuesto'], ['Elevaciones laterales', 'aislado'],
    ['Pec deck inverso', 'aislado'],
  ],
  brazo: [
    ['Curl con barra Z', 'aislado'], ['Extensión de tríceps en polea', 'aislado'],
    ['Curl martillo', 'aislado'],
  ],
};

const SPLITS = {
  'full-body-3': [
    { nombre: 'FULL BODY A', grupos: ['pierna', 'pecho', 'espalda'] },
    { nombre: 'FULL BODY B', grupos: ['pierna', 'hombro', 'brazo'] },
    { nombre: 'FULL BODY C', grupos: ['espalda', 'pecho', 'pierna'] },
  ],
  'upper-lower-4': [
    { nombre: 'UPPER A', grupos: ['pecho', 'espalda', 'hombro'] },
    { nombre: 'LOWER A', grupos: ['pierna'] },
    { nombre: 'UPPER B', grupos: ['espalda', 'pecho', 'brazo'] },
    { nombre: 'LOWER B', grupos: ['pierna'] },
  ],
  'ppl-6': [
    { nombre: 'TIRÓN A — ANCHO', grupos: ['espalda', 'brazo'] },
    { nombre: 'EMPUJE A — PECHO', grupos: ['pecho', 'hombro'] },
    { nombre: 'PIERNA A', grupos: ['pierna'] },
    { nombre: 'TIRÓN B — GROSOR', grupos: ['espalda', 'brazo'] },
    { nombre: 'EMPUJE B — HOMBRO', grupos: ['hombro', 'pecho'] },
    { nombre: 'PIERNA B', grupos: ['pierna'] },
  ],
};

export const SPLITS_DISPONIBLES = Object.keys(SPLITS);

/* slug()/id de ejercicio: TIENE que coincidir con cómo los arma el Cerebro
 * (`slug(nombre)-d{día}-{índice}`), porque el histórico por ejercicio, el peso
 * por variante y los estados se guardan contra ese id. Un id distinto acá y el
 * banco mostraría "primera vez" en un ejercicio que tiene 8 semanas de carga. */
const slug = (s) => s.toLowerCase()
  .normalize('NFD').replace(/[̀-ͯ]/g, '')
  .replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');

/**
 * Estructura de rutina.
 *
 * @param {object} o
 *   split            'full-body-3' | 'upper-lower-4' | 'ppl-6'
 *   semanasTotal     12 o 24 (el macrociclo largo cambia el "SEM 13/24")
 *   objetivo         'Hipertrofia' | 'Definición' | 'Mantenimiento'
 *   nivel            'principiante' | 'intermedio' | 'avanzado'
 *   ejerciciosPorDia cuántos por día (default 5)
 *   sinVideos        true → video_url null en todos (caso real muy común)
 *   seed
 */
export function rutina(o = {}) {
  const split = SPLITS[o.split] || SPLITS['ppl-6'];
  const rnd = mulberry32(o.seed == null ? 7 : o.seed);
  const porDia = o.ejerciciosPorDia || 5;
  const semanasTotal = o.semanasTotal || 12;

  const dias = split.map((d, i) => {
    /* Reparto exacto: la suma de los bloques tiene que dar `porDia`.
     * Con round() por bloque los restos se acumulaban y un día de 2 grupos
     * pedido en 5 ejercicios salía con 7 — el volumen semanal del plan no
     * era el que decía ser, que es justo lo que el banco tiene que poder fijar. */
    const cupos = d.grupos.map((g, gi) => {
      const base = Math.floor(porDia / d.grupos.length);
      const extra = gi < (porDia % d.grupos.length) ? 1 : 0;
      return Math.min(base + extra, EJERCICIOS[g].length);
    });
    let idxDia = 0;   // índice GLOBAL dentro del día: así arma los ids el Cerebro
    const bloques = d.grupos.map((g, gi) => {
      const pool = EJERCICIOS[g];
      const ejercicios = [];
      for (let k = 0; k < cupos[gi]; k++) {
        const [nombre, tipo] = pool[k];
        ejercicios.push({
          id: `${slug(nombre)}-d${i + 1}-${idxDia++}`,
          nombre,
          tipo,
          series: tipo === 'compuesto' ? 4 : 3,
          reps: tipo === 'compuesto' ? '6-8' : '10-12',
          rir_objetivo: o.objetivo === 'Definición' ? '2-3' : '1-2',
          descanso_segundos: tipo === 'compuesto' ? 180 : 90,
          video_url: o.sinVideos ? null : `https://www.youtube.com/watch?v=${slug(nombre).slice(0, 11)}`,
          notas_tecnica: rnd() > 0.6 ? 'Controlá la fase excéntrica.' : null,
        });
      }
      return { titulo: `BLOQUE ${gi + 1} — ${g.toUpperCase()}`, subtitulo: g.toUpperCase(), ejercicios };
    });
    return { n: i + 1, id: DIAS_ID[i], nombre: d.nombre, abreviado: DIAS_ABR[i], bloques };
  });

  const est = {
    nombre_plan: `Mesociclo ${o.objetivo || 'Hipertrofia'} — banco de pruebas`,
    perfil: {
      nivel: o.nivel || 'intermedio',
      split: o.split || 'ppl-6',
      diasSemana: dias.length,
      objetivo: o.objetivo || 'Hipertrofia',
      resumen: 'Plan sintético del banco de pruebas. No es de un cliente real.',
    },
    semanas_total: semanasTotal,
    dias,
    mensajes_semana: Array.from({ length: semanasTotal }, (_, k) => ({
      n: k + 1,
      titulo: `Semana ${k + 1}`,
      msg: k === 0 ? 'Arrancamos.' : k + 1 === semanasTotal ? 'Última semana del bloque.' : 'Sostené la técnica.',
    })),
  };

  /* semana_offset: la numeración continuada del macrociclo ("SEM 13/24").
   *
   * Es la perilla que MÁS lugares cambia de golpe y la que menos se puede ver
   * sin el banco: la lee el header, el eyebrow de la dieta, el botón de pasar
   * de semana, el modal de confirmación, y —la que importa— la condición de
   * `_esCalibracion`, que es lo único que evita mostrarle "Semana de
   * calibración" a alguien que va por la semana 13. Un cliente que termina un
   * bloque de 12 y recibe el segundo vive acá durante meses.
   *
   * Se emite solo si es > 0: el Cerebro tampoco lo escribe en la fase 1, y el
   * banco tiene que producir el mismo JSON que produce producción. */
  if (o.semanaOffset) est.semana_offset = o.semanaOffset;

  /* ── Perillas de plan ROTO ─────────────────────────────────────────────
   * No son hipótesis: son estados que el Cerebro puede publicar y que hoy
   * tumban la app del cliente. Sin poder fabricarlos, el único lugar donde se
   * ven es en el teléfono de alguien. */
  if (o.diasVacios) est.dias = [];                    // la app no arranca nunca
  if (o.sinSemanasTotal) delete est.semanas_total;    // el front dice 1, el server 12
  if (o.diaSinEjercicios && est.dias[0]) est.dias[0].bloques = [];  // "sesión completa" sin entrenar
  if (o.sinDescanso) {
    // chip "NaN:NaN" y timer de descanso eterno
    for (const d of est.dias) for (const b of (d.bloques || [])) for (const e of b.ejercicios) delete e.descanso_segundos;
  }
  return est;
}

/* ── Dieta ───────────────────────────────────────────────────────────────
 * Las opciones A/B/C/D son POR COMIDA y son INTERCAMBIABLES entre sí: el
 * cliente combina desayuno A + almuerzo C + cena B. O sea que las 4 opciones
 * de UNA comida tienen que valer lo mismo entre ellas; no hay que igualar el
 * desayuno con el almuerzo. Es la regla que más veces se malinterpretó.  */
const ALIMENTOS = {
  proteina: [
    ['Pechuga de pollo', 200, 'g', 330, 62, 0, 7],
    ['Carne magra', 200, 'g', 340, 60, 0, 11],
    ['Merluza', 250, 'g', 290, 58, 0, 5],
    ['Claras de huevo', 400, 'g', 200, 44, 3, 0],
  ],
  carbohidrato: [
    ['Arroz blanco cocido', 250, 'g', 325, 6, 70, 1],
    ['Papa hervida', 400, 'g', 340, 8, 76, 0],
    ['Fideos cocidos', 250, 'g', 320, 11, 65, 2],
    ['Avena', 90, 'g', 342, 12, 60, 6],
  ],
  grasa: [
    ['Palta', 70, 'g', 112, 1, 6, 10],
    ['Aceite de oliva', 12, 'ml', 106, 0, 0, 12],
    ['Almendras', 18, 'g', 104, 4, 4, 9],
  ],
  vegetal: [
    ['Ensalada mixta', 150, 'g', 30, 2, 5, 0],
    ['Brócoli', 200, 'g', 68, 6, 10, 1],
  ],
};

/**
 * Estructura de dieta.
 *
 * @param {object} o
 *   comidas      cuántas comidas al día (default 4)
 *   opciones     cuántas opciones por comida: 1 a 4 (default 4 — el caso real)
 *   kcal         objetivo calórico (default 2800)
 *   sinVegetales true → dieta sin la fila de verduras (caso feo pero existe)
 *   seed
 */
export function dieta(o = {}) {
  const nComidas = o.comidas || 4;
  const nOpciones = Math.min(4, Math.max(1, o.opciones == null ? 4 : o.opciones));
  const rnd = mulberry32(o.seed == null ? 11 : o.seed);
  const kcal = o.kcal || 2800;
  const nombres = ['Desayuno', 'Almuerzo', 'Merienda', 'Cena', 'Colación'];

  const comidas = [];
  for (let i = 0; i < nComidas; i++) {
    /* Los ROLES se deciden una vez POR COMIDA, no por opción.
     *
     * Antes el `if (rnd() > 0.5) rol('grasa')` estaba adentro del loop de
     * opciones, así que la A podía llevar aceite y la B no: 767 vs 654 kcal
     * para la misma comida. Eso rompe la regla del proyecto — las opciones
     * A/B/C/D son POR COMIDA e INTERCAMBIABLES entre sí, el cliente combina
     * desayuno A + almuerzo C + cena B. Si no valen lo mismo, el que elige la
     * B come 113 kcal menos sin enterarse, y el banco estaría probando el swap
     * y los macros contra dietas que el generador real no publicaría. */
    const roles = ['proteina', 'carbohidrato'];
    if (rnd() > 0.5) roles.push('grasa');
    if (!o.sinVegetales && i > 0) roles.push('vegetal');

    const options = [];
    for (let j = 0; j < nOpciones; j++) {
      /* UN alimento por rol: ajustar la cantidad del que está, no agregar un
       * segundo del mismo rol. Dos proteínas en la misma comida es el error
       * clásico del generador. */
      const foods = roles.map((cat) => {
        const lista = ALIMENTOS[cat];
        const [name, qty, unit, kcal, prot, carb, fat] = lista[(i + j) % lista.length];
        return { name, qty, unit, kcal, prot, carb, fat, category: cat, swappable: true };
      });
      options.push({ name: String.fromCharCode(65 + j), foods });   // A, B, C, D
    }

    /* Igualar las opciones ENTRE SÍ escalando cantidades contra la A.
     * Escalar `qty` escala kcal y los tres macros en la misma proporción, que
     * es exactamente lo que hace el coach a mano cuando arma las alternativas. */
    const kcalDe = (op) => op.foods.reduce((a, f) => a + f.kcal, 0);
    const objetivo = kcalDe(options[0]);
    for (const op of options.slice(1)) {
      const k = objetivo / kcalDe(op);
      for (const f of op.foods) {
        f.qty  = Math.round(f.qty * k);
        f.kcal = Math.round(f.kcal * k);
        f.prot = Math.round(f.prot * k);
        f.carb = Math.round(f.carb * k);
        f.fat  = Math.round(f.fat * k);
      }
    }
    comidas.push({ id: `c${i + 1}`, name: nombres[i] || `Comida ${i + 1}`, options });
  }

  // Los macros del target se derivan de lo que realmente hay en la opción A,
  // para que el anillo de la app no muestre un desfase imposible.
  const sumA = comidas.reduce((acc, c) => {
    for (const f of c.options[0].foods) {
      acc.kcal += f.kcal; acc.prot += f.prot; acc.carb += f.carb; acc.fat += f.fat;
    }
    return acc;
  }, { kcal: 0, prot: 0, carb: 0, fat: 0 });

  const est = {
    macros_target: {
      kcal: o.kcal ? kcal : Math.round(sumA.kcal),
      prot: Math.round(sumA.prot), carb: Math.round(sumA.carb), fat: Math.round(sumA.fat),
    },
    comidas,
  };

  /* ── Perillas de dieta ROTA ────────────────────────────────────────────
   * Mismo criterio que en rutina(): son formas que el Cerebro puede publicar
   * y que revientan la escena Dieta. `sinMacrosTarget` es la peor de todas —
   * no rompe la pantalla de dieta, se lleva puesto el ARRANQUE ENTERO de la
   * app, así que el cliente ve una pantalla en blanco y no puede ni entrenar. */
  if (o.sinMacrosTarget) delete est.macros_target;
  if (o.comidaSinOpciones && est.comidas[0]) est.comidas[0].options = [];
  if (o.tiposDiaVacio) est.tipos_dia = [];   // getActivePlan devuelve la raíz, sin .comidas
  if (o.sinUnitGrams) {
    // El caso REAL: el Cerebro publica unit:'unidad' sin unitGrams. Toda dieta
    // publicada hoy cae acá, así que el banco tiene que poder reproducirlo.
    for (const c of est.comidas) for (const op of c.options) for (const f of op.foods) {
      if (f.category === 'proteina') { f.unit = 'unidad'; f.qty = 2; delete f.unitGrams; }
    }
  }
  return est;
}

/* Escape de literales para el SQL que se genera. Nada de esto viene del
 * usuario, pero un apóstrofo en "Jalón" rompería el INSERT igual. */
const q = (s) => `'${String(s).replace(/'/g, "''")}'`;

/**
 * SQL idempotente que deja al cliente con esta rutina y esta dieta activas.
 *
 * Va por SQL y no por RPC porque mypump_rutinas/mypump_dietas tienen RLS de
 * `authenticated` (001:275-287): publicar es del coach, no del cliente. Un
 * script con la anon key no puede — y está bien que no pueda.
 */
export function sqlPlan({ clienteId, nombre, perfil, token, rutina: r, dieta: d,
                          semanaActual, conBloqueEnCola, siguiente, sinDieta }) {
  const L = [];
  L.push(`-- Generado por scripts/seed-cliente.mjs — NO editar a mano.`);
  L.push(`-- Cliente sintético del banco de pruebas: ${clienteId}`);
  L.push(``);
  L.push(`-- 1. El cliente (idempotente: si ya está, se actualiza el perfil)`);
  L.push(`INSERT INTO mypump_clientes (cliente_id, nombre, perfil, access_token, access_token_active)`);
  L.push(`VALUES (${q(clienteId)}, ${q(nombre)}, ${q(perfil)}, ${q(token)}, TRUE)`);
  L.push(`ON CONFLICT (cliente_id) DO UPDATE SET nombre = EXCLUDED.nombre,`);
  L.push(`  perfil = EXCLUDED.perfil, access_token = EXCLUDED.access_token, access_token_active = TRUE;`);
  L.push(``);
  L.push(`-- 2. Rutina`);
  L.push(`UPDATE mypump_rutinas SET estado = 'archivada' WHERE cliente_id = ${q(clienteId)} AND estado = 'activa';`);
  L.push(`INSERT INTO mypump_rutinas (cliente_id, version, estado, estructura, semana_actual, fecha_inicio)`);
  L.push(`VALUES (${q(clienteId)}, 1, 'activa', ${q(JSON.stringify(r))}::jsonb, ${semanaActual || 1},`);
  L.push(`        CURRENT_DATE - (${(semanaActual || 1) - 1} * 7));`);
  if (conBloqueEnCola) {
    L.push(``);
    L.push(`-- 2b. Bloque EN COLA.`);
    L.push(`--`);
    L.push(`-- Va como \`estructura_siguiente\` DE LA FILA ACTIVA, no como una fila aparte.`);
    L.push(`-- Dos motivos:`);
    L.push(`--   · mypump_get_rutina_activa deriva tiene_siguiente de`);
    L.push(`--     (estructura_siguiente IS NOT NULL) — migración 025:37. Una fila`);
    L.push(`--     nueva no enciende nada.`);
    L.push(`--   · mypump_rutinas.estado tiene CHECK IN ('activa','archivada')`);
    L.push(`--     (001:116), así que un INSERT con estado='en_cola' ni siquiera entra:`);
    L.push(`--     revienta la constraint y se lleva puesto el resto del script.`);
    L.push(`--`);
    L.push(`-- El bloque en cola es OTRO plan, no el mismo: si fuera idéntico, activarlo`);
    L.push(`-- no se notaría y el caso no probaría nada.`);
    L.push(`UPDATE mypump_rutinas`);
    L.push(`   SET estructura_siguiente = ${q(JSON.stringify(siguiente || r))}::jsonb`);
    L.push(` WHERE cliente_id = ${q(clienteId)} AND estado = 'activa';`);
  }
  L.push(``);
  L.push(`-- 3. Dieta`);
  L.push(`UPDATE mypump_dietas SET estado = 'archivada' WHERE cliente_id = ${q(clienteId)} AND estado = 'activa';`);
  if (sinDieta) {
    L.push(`-- (a propósito NO se publica dieta: el cliente con rutina y sin dieta ve`);
    L.push(`--  SAMPLE_DIET —3200 kcal, 5 comidas— como si fuera su plan, sin ningún`);
    L.push(`--  aviso. Es el caso que hay que poder mirar de frente.)`);
  } else {
    L.push(`INSERT INTO mypump_dietas (cliente_id, version, estado, estructura)`);
    L.push(`VALUES (${q(clienteId)}, 1, 'activa', ${q(JSON.stringify(d))}::jsonb);`);
  }
  L.push(``);
  return L.join('\n');
}
