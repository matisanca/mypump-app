/* =============================================================
   ajustes-dieta.js — Los ajustes de comidas del cliente (D22) y los
   alimentos agregados (D1), con la misma lógica que las apps nativas.

   Fuente de verdad: apps/ios/MyPumpKit/Sources/MyPumpReglas/
   AjustePorciones.swift y AgregadosComida.swift (rama nativa-202). Los
   vectores compartidos (apps/shared/vectores/ajuste_porciones.json y
   agregados_comida.json) los corre scripts/test-ajustes-dieta.mjs: si la
   app cambia una regla, este archivo tiene que cambiar igual.

   Antes la web no leía los ajustes: quien ajustaba una comida en la app
   veía en la web el plan sin ajustar.

   Un alimento es el de la dieta publicada: {name, qty, unit, kcal, prot,
   carb, fat}. Las macros son el TOTAL de la qty del plan.
   ============================================================= */
(function (raiz) {
  'use strict';

  // Math.round de JS: la mitad redondea hacia arriba (igual que jsRound en Swift).
  const R = (x) => Math.round(x);
  const fin = (x) => typeof x === 'number' && isFinite(x);
  const num = (x) => (fin(x) ? x : 0);

  /* ---------------- AjustePorciones ---------------- */
  const PASO = 50;
  const FACTOR_MIN = 0.25;
  const FACTOR_MAX = 3.0;

  function normalTexto(s) { return String(s == null ? '' : s).trim().toLowerCase(); }
  function unidadNormal(u) {
    const n = normalTexto(u);
    if (['', 'g', 'gr', 'grs', 'gramo', 'gramos'].includes(n)) return 'g';
    if (n === 'cc') return 'ml';
    return n;
  }
  function anclaCoincide(ancla, a) {
    return normalTexto(ancla.nombre) === normalTexto(a.name) && unidadNormal(ancla.unidad) === unidadNormal(a.unit);
  }

  function esPeso(unidad) {
    const u = String(unidad == null ? 'g' : unidad).toLowerCase().trim();
    return ['g', 'gr', 'grs', 'gramo', 'gramos', 'ml', 'cc', ''].includes(u);
  }
  function redondear(q, unidad) {
    if (!fin(q) || q <= 0) return 0;
    if (esPeso(unidad)) return q < 20 ? Math.max(1, R(q)) : Math.max(5, R(q / 5) * 5);
    return Math.max(0.5, R(q * 2) / 2);
  }
  function pasoCantidad(a) {
    if (!esPeso(a.unit)) return 0.5;
    return num(a.qty) >= 100 ? 10 : 5;
  }
  function maximoCantidad(plan) { return redondear(num(plan.qty) * FACTOR_MAX, plan.unit); }
  function bajar(plan, q) {
    const nueva = q - pasoCantidad(plan);
    return fin(nueva) && nueva > 0 ? redondear(nueva, plan.unit) : 0;
  }
  function subir(plan, q) { return Math.min(maximoCantidad(plan), redondear(q + pasoCantidad(plan), plan.unit)); }
  function puedeSubir(plan, q) { return q + pasoCantidad(plan) <= maximoCantidad(plan); }

  function conCantidad(a, qty) {
    const q0 = a.qty;
    if (!fin(q0) || q0 <= 0 || !fin(qty) || qty < 0) return a;
    const f = qty / q0;
    const b = Object.assign({}, a, { qty });
    if (fin(a.kcal)) b.kcal = R(a.kcal * f);
    if (fin(a.prot)) b.prot = R(a.prot * f * 10) / 10;
    if (fin(a.carb)) b.carb = R(a.carb * f * 10) / 10;
    if (fin(a.fat)) b.fat = R(a.fat * f * 10) / 10;
    return b;
  }
  function kcal(als) { return als.reduce((s, a) => s + num(a.kcal), 0); }

  function escalables(als, fijos) {
    const r = [];
    als.forEach((a, i) => { if (!fijos.has(i) && num(a.kcal) > 0 && num(a.qty) > 0) r.push(i); });
    return r;
  }
  function escalon(q, unidad) { return esPeso(unidad) ? (q < 20 ? 1 : 5) : 0.5; }
  function factor(base, delta) { return Math.min(FACTOR_MAX, Math.max(FACTOR_MIN, (base + delta) / base)); }

  function escalar(als, deltaKcal, cantidades) {
    cantidades = cantidades || new Map();
    const r = als.map((a, i) => (cantidades.has(i) ? conCantidad(a, cantidades.get(i)) : a));
    if (!fin(deltaKcal) || deltaKcal === 0) return r;
    const libres = escalables(als, new Set(cantidades.keys()));
    const base = libres.reduce((s, i) => s + num(als[i].kcal), 0);
    if (!(base > 0)) return r;
    const f = factor(base, deltaKcal);
    const sube = deltaKcal > 0;
    for (const i of libres) {
      const a = als[i], q0 = num(a.qty);
      const q = redondear(q0 * f, a.unit);
      r[i] = conCantidad(a, sube ? Math.max(q, q0) : Math.min(q, q0));
    }
    afinar(r, als, libres, base * f, sube);
    return r;
  }

  function afinar(r, plan, libres, objetivo, sube) {
    for (let vuelta = 0; vuelta < 60; vuelta++) {
      const actual = libres.reduce((s, i) => s + num(r[i].kcal), 0);
      const resto = objetivo - actual;
      if (Math.abs(resto) < 1) return;
      let mejor = null;
      for (const i of libres) {
        const a = plan[i], q0 = num(a.qty), q = num(r[i].qty);
        const paso = escalon(resto > 0 ? q : Math.max(0, q - 1), a.unit);
        const nueva = resto > 0 ? q + paso : q - paso;
        const minimo = Math.max(redondear(q0 * FACTOR_MIN, a.unit), esPeso(a.unit) ? 1 : 0.5, sube ? q0 : 0);
        const maximo = Math.min(redondear(q0 * FACTOR_MAX, a.unit), sube ? Infinity : q0);
        if (!(nueva >= minimo && nueva <= maximo)) continue;
        const cambio = num(conCantidad(a, nueva).kcal) - num(r[i].kcal);
        const error = Math.abs(resto - cambio);
        if (error < Math.abs(resto) && (mejor === null || error < mejor.error)) mejor = { i, qty: nueva, error };
      }
      if (!mejor) return;
      r[mejor.i] = conCantidad(plan[mejor.i], mejor.qty);
    }
  }

  // comida = {id, nombre, opcion (0 = A), alimentos}
  function cantidadesValidas(c, aj) {
    const r = new Map();
    if (!aj || aj.opcion !== c.opcion) return r;
    for (const k of Object.keys(aj.cantidades || {})) {
      const i = Number(k), v = aj.cantidades[k];
      if (!Number.isInteger(i) || i < 0 || i >= c.alimentos.length || !fin(v) || v < 0) continue;
      const ancla = aj.anclas && aj.anclas[k];
      if (ancla && !anclaCoincide(ancla, c.alimentos[i])) continue;
      r.set(i, v);
    }
    return r;
  }
  function baseEscalable(c, aj) {
    return escalables(c.alimentos, new Set(cantidadesValidas(c, aj).keys())).reduce((s, i) => s + num(c.alimentos[i].kcal), 0);
  }
  function limitesDelta(c, aj) {
    const base = baseEscalable(c, aj);
    return {
      min: -Math.floor(base * (1 - FACTOR_MIN) / PASO) * PASO,
      max: Math.floor(base * (FACTOR_MAX - 1) / PASO) * PASO,
    };
  }
  // Al guardar: cada cantidad con el alimento al que va y las kcal dentro de lo que la comida puede absorber.
  function anclar(aj, c) {
    const r = clonarAjuste(aj);
    const validas = cantidadesValidas(c, aj);
    r.cantidades = {}; r.anclas = {};
    for (const [i, v] of validas) {
      r.cantidades[String(i)] = v;
      r.anclas[String(i)] = { nombre: c.alimentos[i].name, unidad: c.alimentos[i].unit == null ? null : c.alimentos[i].unit };
    }
    const l = limitesDelta(c, r);
    r.deltaKcal = Math.min(Math.max(r.deltaKcal, l.min), l.max);
    return r;
  }
  function esNeutro(aj) {
    return !aj || (aj.deltaKcal === 0 && Object.keys(aj.cantidades || {}).length === 0 && !aj.omitida
      && !(aj.agregados && aj.agregados.length));
  }

  // El día: cada comida con su ajuste y lo que le pasan las anteriores (AjustePorciones.dia).
  function dia(comidas, ajustes) {
    const r = {};
    let arrastre = 0, origenes = [];
    for (const c of comidas) {
      const aj = ajustes[c.id];
      const llega = arrastre, deQuien = origenes;
      const plan = kcal(c.alimentos);
      const cantidades = cantidadesValidas(c, aj);
      const omitida = !!(aj && aj.omitida);
      const delta = omitida ? 0 : (aj ? aj.deltaKcal : 0);
      let als, noAbsorbido;
      if (omitida) {
        als = c.alimentos.map(a => (num(a.qty) > 0 ? conCantidad(a, 0) : a));
        noAbsorbido = llega;
      } else {
        const base = escalables(c.alimentos, new Set(cantidades.keys())).reduce((s, i) => s + num(c.alimentos[i].kcal), 0);
        if (base > 0) {
          als = escalar(c.alimentos, delta + llega, cantidades);
          noAbsorbido = R(llega - base * (factor(base, delta + llega) - factor(base, delta)));
        } else {
          als = escalar(c.alimentos, 0, cantidades);
          noAbsorbido = llega;
        }
      }
      const extra = alimentosAgregados(aj);
      const hoy = kcal(als) + kcal(extra);
      const cambiados = new Set();
      c.alimentos.forEach((a, i) => { if (als[i].qty !== a.qty) cambiados.add(i); });
      const propio = esNeutro(aj) ? 0 : R(hoy - plan - (llega - noAbsorbido));
      r[c.id] = {
        alimentos: als, agregados: extra, kcalPlan: plan, kcal: hoy, deltaPropio: delta, omitida,
        compensacion: llega, compensaDe: llega !== 0 ? deQuien : [], noAbsorbido, cambiados, propio,
        ajustada: omitida || cambiados.size > 0 || extra.length > 0,
      };
      let siguiente = noAbsorbido;
      let nuevos = noAbsorbido !== 0 ? deQuien.slice() : [];
      if (aj && aj.compensar && propio !== 0) { siguiente -= propio; nuevos.push(c.nombre); }
      arrastre = siguiente;
      origenes = siguiente !== 0 ? nuevos : [];
    }
    return r;
  }

  // La comida que recibe lo que sale de `id`: la primera siguiente que se come y tiene algo que escalar.
  function destino(comidas, ajustes, id) {
    const i = comidas.findIndex(c => c.id === id);
    if (i < 0) return null;
    return comidas.slice(i + 1).find(c => !(ajustes[c.id] && ajustes[c.id].omitida) && baseEscalable(c, ajustes[c.id]) > 0) || null;
  }

  /* ---------------- Lectura con topes (AjusteComida.init(from:)) ---------------- */
  function leerAjuste(x) {
    if (!x || typeof x !== 'object' || Array.isArray(x)) return null;
    const entero = (v) => (typeof v === 'number' && Number.isInteger(v) ? v : null);
    const d = entero(x.deltaKcal);
    const op = entero(x.opcion);
    const cant = {};
    if (x.cantidades && typeof x.cantidades === 'object') {
      for (const k of Object.keys(x.cantidades)) { const v = x.cantidades[k]; if (fin(v) && v >= 0) cant[k] = v; }
    }
    const anclas = {};
    if (x.anclas && typeof x.anclas === 'object') {
      for (const k of Object.keys(x.anclas)) {
        const a = x.anclas[k];
        if (a && typeof a.nombre === 'string') anclas[k] = { nombre: a.nombre, unidad: typeof a.unidad === 'string' ? a.unidad : null };
      }
    }
    const vistos = new Set();
    const agregados = (Array.isArray(x.agregados) ? x.agregados : [])
      .map(leerAgregado).filter(a => a && !vistos.has(a._ts) && vistos.add(a._ts)).slice(0, 50);
    return {
      deltaKcal: d !== null && Math.abs(d) <= 30000 ? d : 0,
      compensar: typeof x.compensar === 'boolean' ? x.compensar : true,
      omitida: typeof x.omitida === 'boolean' ? x.omitida : false,
      opcion: op !== null && op >= 0 && op <= 99 ? op : 0,
      cantidades: cant, anclas, agregados,
    };
  }
  function leerAjustes(obj) {
    const r = {};
    if (!obj || typeof obj !== 'object') return r;
    for (const k of Object.keys(obj)) { const a = leerAjuste(obj[k]); if (a) r[k] = a; }
    return r;
  }
  function clonarAjuste(aj) {
    const a = aj || nuevoAjuste();
    return {
      deltaKcal: a.deltaKcal || 0, compensar: a.compensar !== false, omitida: !!a.omitida, opcion: a.opcion || 0,
      cantidades: Object.assign({}, a.cantidades), anclas: Object.assign({}, a.anclas),
      agregados: (a.agregados || []).slice(),
    };
  }
  function nuevoAjuste(opcion) {
    return { deltaKcal: 0, compensar: true, omitida: false, opcion: opcion || 0, cantidades: {}, anclas: {}, agregados: [] };
  }
  // Lo que se guarda: sin agregados, la clave no va (igual que la app).
  function serializarAjuste(aj) {
    const o = { deltaKcal: aj.deltaKcal, compensar: aj.compensar, omitida: aj.omitida, opcion: aj.opcion,
      cantidades: aj.cantidades, anclas: aj.anclas };
    if (aj.agregados && aj.agregados.length) o.agregados = aj.agregados;
    return o;
  }

  /* ---------------- AgregadosComida ---------------- */
  const MAX_POR_COMIDA = 8, MAX_POR_DIA = 24, MAX_BYTES = 15000, LARGO_NOMBRE = 80;

  function leerAgregado(x) {
    if (!x || typeof x !== 'object') return null;
    const n = (v, max) => (fin(v) && v >= 0 && v <= max ? v : null);
    const nombre = typeof x.nombre === 'string' ? x.nombre.trim() : '';
    const cantidad = n(x.cantidad, 100000), gramos = n(x.gramos, 100000), k = n(x.kcal, 30000);
    const p = n(x.p, 10000), c = n(x.c, 10000), g = n(x.g, 10000);
    const p100 = x.por100 || {};
    const por100 = { kcal: n(p100.kcal, 10000), p: n(p100.p, 10000), c: n(p100.c, 10000), g: n(p100.g, 10000) };
    const ts = fin(x._ts) && x._ts >= 0 && x._ts < 1e15 ? Math.trunc(x._ts) : null;
    if (!nombre || !(cantidad > 0) || gramos === null || k === null || p === null || c === null || g === null
      || por100.kcal === null || por100.p === null || por100.c === null || por100.g === null || ts === null) return null;
    const r = { nombre, cantidad, unidad: typeof x.unidad === 'string' && x.unidad ? x.unidad : 'g', gramos, kcal: k, p, c, g,
      por100, origen: ['base', 'propio', 'barras'].includes(x.origen) ? x.origen : 'base', _ts: ts };
    if (fin(x.gramosUnidad) && x.gramosUnidad > 0) r.gramosUnidad = x.gramosUnidad;
    if (typeof x.codigo === 'string' && /^\d{8,14}$/.test(x.codigo)) r.codigo = x.codigo;
    return r;
  }
  // El agregado como un alimento más de la comida.
  function comoAlimento(ag) {
    return { name: ag.nombre, qty: ag.cantidad, unit: ag.unidad, kcal: ag.kcal, prot: ag.p, carb: ag.c, fat: ag.g, _agregado: ag._ts };
  }
  function alimentosAgregados(aj) {
    if (!aj || aj.omitida) return [];
    return (aj.agregados || []).map(comoAlimento);
  }

  function normalizar(s) {
    return String(s == null ? '' : s).toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '').trim();
  }
  function singular(w) {
    if (w.length > 4 && w.endsWith('ces')) return w.slice(0, -3) + 'z';
    if (w.length > 3 && w.endsWith('es')) return w.slice(0, -2);
    if (w.length > 3 && w.endsWith('s')) return w.slice(0, -1);
    return w;
  }
  const GRAMO = { nombre: 'g', gramos: 1 };

  // candidato = {nombre, por100:{kcal,p,c,g}, unidad?, gramosPorUnidad?, origen, codigo?}
  function medidas(cand) {
    if (cand.unidad && fin(cand.gramosPorUnidad) && cand.gramosPorUnidad > 0) {
      const n = normalizar(cand.unidad);
      if (!['', 'g', 'gr', 'grs', 'gramo', 'gramos', 'ml', 'cc'].includes(n)) {
        const nombre = ['u', 'un', 'uni', 'unid', 'unidad', 'unidades'].includes(n) ? 'unidad'
          : ['porcion', 'porciones'].includes(n) ? 'porción' : singular(n);
        return [GRAMO, { nombre, gramos: cand.gramosPorUnidad }];
      }
    }
    const m = medidaCasera(cand.nombre);
    return m ? [GRAMO, m] : [GRAMO];
  }
  function medidaCasera(nombre) {
    const name = normalizar(nombre);
    if (!name) return null;
    const has = (...kw) => kw.some(k => name.includes(k));
    const M = (nombre, gramos) => ({ nombre, gramos });
    if (has('mani', 'cacahuate') && has('mantequilla', 'manteca', 'crema', 'pasta', 'untable')) return M('cucharada', 16);
    if (has('leche', 'bebida', 'jugo', 'zumo', 'licuado', 'gaseosa', 'kefir', 'caldo', 'infusion', 'yogur bebible', 'chocolatada')) return M('vaso', 200);
    if (has('aceite', 'oliva', 'ghee') || has('manteca', 'mantequilla')) return M('cucharada', 15);
    if (has('almendra', 'nuez', 'nueces', 'castana', 'avellana', 'pistacho', 'mani', 'cacahuate', 'frutos secos',
      'semilla', 'girasol', 'chia', 'lino', 'mix de')) return M('puñado', 30);
    if (has('whey', 'proteina en polvo', 'caseina')) return M('scoop', 30);
    if (has('atun')) return M('lata', 120);
    if (has('pollo', 'pechuga', 'carne', 'nalga', 'bife', 'cerdo', 'lomo', 'pescado', 'merluza', 'pavo', 'salmon',
      'cuadril', 'cuadrada', 'peceto', 'asado', 'bondiola', 'milanesa', 'tira', 'magra', 'roast', 'colita')) {
      return M('palma', has('crud') ? R(100 / 0.75) : 100);
    }
    if (has('arroz', 'fideo', 'pasta', 'avena', 'quinoa', 'polenta', 'tallarin', 'noqui', 'cuscus', 'couscous',
      'trigo', 'mostacho', 'spaghetti', 'ravioli')) {
      if (has('avena')) return M('taza', 80);
      if (has('cocid', 'hervid', 'al dente')) return M('taza', 175);
      if (has('fideo', 'pasta', 'tallarin', 'noqui', 'mostacho', 'spaghetti', 'ravioli', 'cuscus', 'couscous')) return M('taza en crudo', 100);
      if (has('quinoa')) return M('taza en crudo', 170);
      if (has('polenta')) return M('taza en crudo', 150);
      return M('taza en crudo', 185);
    }
    if (has('lenteja', 'garbanzo', 'poroto', 'alubia', 'frijol', 'chaucha seca')) return M('taza', 190);
    if (has('papa', 'patata', 'batata', 'boniato') && !has('papaya')) {
      if (has('pure')) return M('taza', 175);
      return M('mediana', 150);
    }
    if (has('lechuga', 'rucula', 'radicheta', 'escarola', 'hojas verdes', 'mix de hojas')) return null;
    if (has('brocoli', 'brecol', 'coliflor', 'calabaza', 'zapallo', 'zanahoria', 'espinaca', 'morron', 'pimiento',
      'berenjena', 'zucchini', 'zapallito', 'repollo', 'remolacha', 'chaucha', 'cebolla', 'tomate', 'verdura')) return M('puño', 90);
    if (has('ricota', 'untable', 'yogur', 'yoghurt', 'queso blanco', 'queso crema', 'cottage', 'requeson')) return M('taza', 245);
    if (has('frutilla', 'arandano', 'mora', 'frambuesa', 'frutos rojos', 'berries')) return M('puñado', 80);
    if (has('palta', 'aguacate')) return M('palta', 140);
    if (has('pan') && !has('rallado')) return M('rebanada', 30);
    if (has('tostada')) return M('tostada', has('arroz') ? 9 : 25);
    return null;
  }

  // base = [{name, kcal, prot, carb, fat, unit?, unitGrams?, _propio?}] (MYPUMP_FOOD_DB + los propios)
  function buscar(base, consulta, limite) {
    limite = limite || 60;
    const palabras = normalizar(consulta).split(/[ /]+/).filter(Boolean);
    if (!palabras.length) return [];
    const todos = base.filter(a => { const n = normalizar(a.name); return palabras.every(p => n.includes(p)); });
    const empiezan = todos.filter(a => normalizar(a.name).startsWith(palabras[0]));
    const resto = todos.filter(a => !normalizar(a.name).startsWith(palabras[0]));
    return empiezan.concat(resto).slice(0, limite);
  }
  function candidatoDeBase(a) {
    const gu = Number(a.unitGrams);
    return {
      nombre: a.name, por100: { kcal: num(a.kcal), p: num(a.prot), c: num(a.carb), g: num(a.fat) },
      unidad: a.unit && fin(gu) && gu > 0 ? a.unit : null, gramosPorUnidad: fin(gu) && gu > 0 ? gu : null,
      origen: a._propio ? 'propio' : 'base',
    };
  }
  function inicial(cand) {
    const ms = medidas(cand);
    if (cand.unidad && ms.length > 1) return { cantidad: 1, medida: ms[1] };
    return { cantidad: 100, medida: GRAMO };
  }
  const esGramo = (m) => m.nombre === 'g';
  function pasoAgregado(cantidad, m) { return esGramo(m) ? (cantidad >= 100 ? 10 : 5) : 0.5; }
  function acotarAgregado(cantidad, m) {
    if (!fin(cantidad)) return esGramo(m) ? 1 : 0.5;
    if (esGramo(m)) return Math.min(2000, Math.max(1, R(cantidad)));
    return Math.min(50, Math.max(0.5, R(cantidad * 2) / 2));
  }
  function subirAgregado(cantidad, m) {
    const p = pasoAgregado(cantidad, m);
    return acotarAgregado(esGramo(m) ? (Math.floor(cantidad / p) + 1) * p : cantidad + p, m);
  }
  function bajarAgregado(cantidad, m) {
    const p = pasoAgregado(Math.max(0, cantidad - 1), m);
    return acotarAgregado(esGramo(m) ? (Math.ceil(cantidad / p) - 1) * p : cantidad - p, m);
  }
  function agregado(cand, cantidad, m, ts) {
    const q = acotarAgregado(cantidad, m);
    const gramos = R(q * m.gramos * 10) / 10;
    const f = gramos / 100;
    const r = {
      nombre: String(cand.nombre).trim().slice(0, LARGO_NOMBRE), cantidad: q, unidad: m.nombre,
      gramos, kcal: R(cand.por100.kcal * f), p: R(cand.por100.p * f * 10) / 10,
      c: R(cand.por100.c * f * 10) / 10, g: R(cand.por100.g * f * 10) / 10,
      por100: cand.por100, origen: cand.origen || 'base', _ts: ts,
    };
    if (!esGramo(m)) r.gramosUnidad = m.gramos;
    if (cand.codigo) r.codigo = cand.codigo;
    return r;
  }
  function candidatoDeAgregado(ag) {
    return { nombre: ag.nombre, por100: ag.por100, unidad: ag.gramosUnidad ? ag.unidad : null,
      gramosPorUnidad: ag.gramosUnidad || null, origen: ag.origen, codigo: ag.codigo };
  }
  // Cota de arriba de lo que pesa el día como jsonb en la base (pg_column_size, que nativa_004 acota a 16000):
  // la misma cuenta que la app (AgregadosComida.bytesJsonb). Cada contenedor lleva 4 de cabecera y 4 por entrada
  // (clave y valor en los objetos), los textos sus bytes UTF-8 y los números un numeric; la alineación, en el peor caso.
  const utf8 = (t) => new TextEncoder().encode(t).length;
  function gruposNumeric(texto) {
    const pe = String(texto).toLowerCase().split('e');
    const exponente = pe.length > 1 ? (parseInt(pe[1], 10) || 0) : 0;
    const pm = pe[0].split('.');
    let digitos = (pm[0] + (pm.length > 1 ? pm[1] : '')).split('');
    let n = pm[0].length + exponente;
    while (digitos[0] === '0') { digitos.shift(); n -= 1; }
    while (digitos[digitos.length - 1] === '0') digitos.pop();
    if (!digitos.length) return { grupos: 0, largo: false };
    const grupo = (q) => Math.floor(q / 4);
    const alto = n - 1, bajo = n - digitos.length;
    const peso = grupo(alto);
    const decimales = Math.max(-bajo, 0);
    return { grupos: peso - grupo(bajo) + 1, largo: decimales > 63 || peso > 63 || peso < -64 };
  }
  function bytesNumeric(d) {
    if (!isFinite(d)) return 9;
    const g = gruposNumeric(String(Math.abs(d)));
    return 9 + (g.largo ? 2 : 0) + 2 * g.grupos;
  }
  function bytesValor(v) {
    const anidado = (x) => (x !== null && typeof x === 'object' ? 3 : 0) + bytesValor(x);
    if (v === null || v === undefined || typeof v === 'boolean') return 0;
    if (typeof v === 'string') return utf8(v);
    if (typeof v === 'number') return bytesNumeric(v);
    if (Array.isArray(v)) return 4 + 4 * v.length + v.reduce((s, x) => s + anidado(x), 0);
    const ks = Object.keys(v).filter(k => v[k] !== undefined);
    return 4 + 8 * ks.length + ks.reduce((s, k) => s + utf8(k) + anidado(v[k]), 0);
  }
  function bytesJsonb(ajustes) {
    const o = {};
    for (const k of Object.keys(ajustes)) o[k] = serializarAjuste(ajustes[k]);
    return 4 + bytesValor(JSON.parse(JSON.stringify(o)));
  }
  function motivoNoEntra(ajustes, comidaId) {
    const a = ajustes[comidaId];
    if (a && a.agregados.length > MAX_POR_COMIDA) return `Llegaste a ${MAX_POR_COMIDA} alimentos agregados en esta comida.`;
    const total = Object.values(ajustes).reduce((s, x) => s + x.agregados.length, 0);
    if (total > MAX_POR_DIA) return `Llegaste a ${MAX_POR_DIA} alimentos agregados en el día.`;
    if (bytesJsonb(ajustes) > MAX_BYTES) return 'No entran más alimentos agregados hoy.';
    return null;
  }
  // Los tildes siguen a cada agregado: `antes` y `despues` son los _ts de los agregados, en orden.
  function excluidosTrasCambio(excluidos, n, antes, despues) {
    const r = new Set();
    for (const i of excluidos) {
      if (i < n) { r.add(i); continue; }
      const j = i - n < antes.length ? despues.indexOf(antes[i - n]) : -1;
      if (j >= 0) r.add(n + j);
    }
    return Array.from(r).sort((a, b) => a - b);
  }
  function excluidosTrasBorrar(excluidos, n, j) {
    const k = n + j;
    return excluidos.filter(i => i !== k).map(i => (i > k ? i - 1 : i));
  }
  function resumenAgregados(aj) {
    return ((aj && aj.agregados) || []).map(a => ({ nombre: a.nombre, cantidad: a.cantidad, unidad: a.unidad,
      gramos: a.gramos, kcal: a.kcal, p: a.p, c: a.c, g: a.g }));
  }

  /* ---------------- ConsumoDelDia ---------------- */
  const letra = (i) => String.fromCharCode(65 + i);
  // La opción de una marca: la primera con ese nombre; si no, la sin nombre con esa letra; si no, la A.
  function indiceOpcion(c, nombre) {
    if (!nombre) return 0;
    const i = c.options.findIndex(o => o.name === nombre);
    if (i >= 0) return i;
    const j = c.options.findIndex((o, k) => !o.name && letra(k) === nombre);
    return j >= 0 ? j : 0;
  }
  // Las comidas del día como las ve el cliente (comidas = las de la dieta publicada: {id, name, options:[{name, foods}]}).
  // marcas = {comidaId: {opcion, estado, foodsExcluidos}}; vistas = {comidaId: índice de la opción que se ve}.
  // efectivo(comidaId, opcion, idx, alimento) aplica los reemplazos.
  function comidasDelDia(comidas, marcas, ajustes, vistas, efectivo) {
    efectivo = efectivo || ((_c, _o, _i, a) => a);
    return comidas.map(c => {
      const m = marcas[c.id];
      const deMarca = m && m.estado === 'comido' ? indiceOpcion(c, m.opcion) : null;
      const elegida = deMarca != null ? deMarca : (vistas[c.id] != null ? vistas[c.id] : (ajustes[c.id] ? ajustes[c.id].opcion : 0));
      const o = c.options.length ? Math.min(Math.max(0, elegida), c.options.length - 1) : 0;
      const foods = (c.options[o] && c.options[o].foods) || [];
      return { id: c.id, nombre: c.name || '', opcion: o, alimentos: foods.map((a, i) => efectivo(c.id, o, i, a)) };
    });
  }
  function consumo(comidas, marcas, libres, ajustes, vistas, efectivo) {
    ajustes = ajustes || {}; vistas = vistas || {};
    const delDia = comidasDelDia(comidas, marcas, ajustes, vistas, efectivo);
    const aj = Object.keys(ajustes).length ? dia(delDia, ajustes) : {};
    const t = { kcal: 0, prot: 0, carb: 0, fat: 0, comidas: 0, hechas: 0, salteadas: 0 };
    for (const c of delDia) {
      if (ajustes[c.id] && ajustes[c.id].omitida) continue;
      t.comidas++;
      const m = marcas[c.id];
      if (!m) continue;
      if (m.estado !== 'comido') { t.salteadas++; continue; }
      t.hechas++;
      const excl = new Set(m.foodsExcluidos || []);
      const todos = (aj[c.id] ? aj[c.id].alimentos : c.alimentos).concat(aj[c.id] ? aj[c.id].agregados : []);
      todos.forEach((a, i) => {
        if (excl.has(i)) return;
        t.kcal += num(a.kcal); t.prot += num(a.prot); t.carb += num(a.carb); t.fat += num(a.fat);
      });
    }
    for (const l of (libres || [])) {
      t.kcal += Number(l.kcal) || 0; t.prot += Number(l.prot) || 0; t.carb += Number(l.carb) || 0; t.fat += Number(l.fat) || 0;
    }
    return t;
  }

  const API = {
    indiceOpcion, comidasDelDia, consumo,
    PASO, FACTOR_MIN, FACTOR_MAX, MAX_POR_COMIDA, MAX_POR_DIA,
    esPeso, redondear, pasoCantidad, maximoCantidad, bajar, subir, puedeSubir, conCantidad, kcal,
    escalar, cantidadesValidas, baseEscalable, limitesDelta, anclar, esNeutro, dia, destino,
    leerAjuste, leerAjustes, clonarAjuste, nuevoAjuste, serializarAjuste,
    leerAgregado, comoAlimento, alimentosAgregados, medidas, medidaCasera, buscar, candidatoDeBase,
    candidatoDeAgregado, inicial, pasoAgregado, acotarAgregado, subirAgregado, bajarAgregado, agregado,
    motivoNoEntra, bytesJsonb, bytesValor, gruposNumeric, excluidosTrasBorrar, excluidosTrasCambio, resumenAgregados, normalizar,
  };
  if (typeof module !== 'undefined' && module.exports) module.exports = API;
  else raiz.AjustesDieta = API;
})(typeof window !== 'undefined' ? window : globalThis);
