/* =============================================================
   carga-simple.js — La carga única por ejercicio de la app 2.3.0.

   La carga se elige una vez y vale para todas las series que faltan; abajo
   queda fija la serie que toca, con el dial y un OK que dice lo que registra.
   No existe en la base: cada OK sale a registrar_carga serie por serie.

   Fuente de verdad: apps/ios/MyPumpKit/Sources/MyPumpReglas/CargaSimple.swift
   (rama nativa-230). Vectores: scripts/vectores-app/carga_simple.json, que
   corre scripts/test-carga-simple.mjs (los mismos del kit y de Android).
   ============================================================= */
(function (raiz) {
  'use strict';

  const KG_MAX = 2000;      // el tope de LIMITES_SERIE de la web (lo imposible)
  const REPS_MAX = 300;
  const P = {
    paso: 2.5, pasoMaquina: 5, pasoMancuernaLiviana: 1, pasoMancuernaPesada: 2, limiteMancuernaLiviana: 10,
  };

  const tituloFueraRE = /descarga|deload|re-?entrada|calibr|mantener|t[ée]cnica/i;
  const tituloAnteriorFueraRE = /descarga|deload|re-?entrada/i;
  const tituloCargaRE = /carga|fuerza|pico|potencia/i;
  const repsNoContablesRE = /\d\s*(s|seg|segundos?|m|mts?|metros?|min|minutos?|km)\b/i;
  const mismaCargaRE = /misma\s+carga|mismo\s+peso|manten[eé]\w*\s+(el\s+|la\s+)?(peso|carga)/i;
  const sinTopeRE = /amrap|∞|max|máx/i;

  const SLUGS_CARDIO = new Set(['walking_treadmill', 'jogging_treadmill', 'running_treadmill', 'bicycling_stationary',
    'bicycling', 'recumbent_bike', 'elliptical_trainer', 'rowing_stationary', 'stairmaster', 'step_mill']);
  const cardioRE = /\bcinta\b|caminadora|treadmill|\bcaminata\b|\bcaminar\b|\btrote\b|\bcorrer\b|eliptic|elliptical|\bbici(cleta)?s?\b|\bbike\b|ergometro|\bcardio\b|spinning|escaladora|stairmaster|step\s*mill|remo\s+(ergometro|indoor|estatico)|maquina\s+de\s+remo|remoergometro|rowing|\brower\b/;
  const noCardioRE = /granjero|farmer|estocada|zancada|lunge|desplante|crunch|abdominal|lateral|con\s+banda|\boso\b|monstruo|cangrejo/;

  const normal = (s) => String(s || '').toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '');

  function esCardio(nombre, tipo, slugs) {
    const t = String(tipo || '').trim().toLowerCase() || null;
    if (t === 'cardio') return true;
    if (t !== null && t !== 'calentamiento') return false;
    if ((slugs || []).some(s => s && SLUGS_CARDIO.has(String(s).trim().toLowerCase()))) return true;
    const n = normal(nombre);
    return cardioRE.test(n) && !noCardioRE.test(n);
  }

  /* ---- La pauta del plan ---- */
  const semanaJS = (s) => s || 1;
  // `upper` de JS: el mayor de los números del texto ("8-10" → 10).
  function tope(v) {
    if (v == null) return null;
    const m = String(v).match(/\d+/g);
    return m ? Math.max(...m.map(Number)) : null;
  }
  // `_repsSug`: el ÚLTIMO número de las reps del plan; null con AMRAP o máx.
  function repsDelPlan(reps) {
    if (reps == null) return null;
    const s = String(reps);
    if (sinTopeRE.test(s)) return null;
    const m = s.match(/\d+/g);
    return m ? parseInt(m[m.length - 1], 10) : null;
  }
  function pasoDePlan(prog, sem) {
    const cur = prog.find(p => p.semana === sem) || prog[Math.max(0, Math.min(sem - 1, prog.length - 1))];
    const prev = sem > 1 ? (prog.find(p => p.semana === sem - 1) || (sem - 2 < prog.length ? prog[sem - 2] : null) || null) : null;
    return { actual: cur, anterior: prev };
  }
  function pauta(e, semana) {
    const prog = e.progresion || [];
    if (prog.length) {
      const p = prog[Math.max(0, Math.min(semanaJS(semana) - 1, prog.length - 1))];
      return { series: p.series != null ? p.series : null, reps: p.reps != null ? p.reps : null };
    }
    return { series: e.series != null ? e.series : null, reps: e.reps != null ? e.reps : null };
  }
  const esCalibracion = (e, semana) => {
    const prog = e.progresion || [];
    return prog.length > 0 && !pasoDePlan(prog, semanaJS(semana)).anterior;
  };

  /* ---- Cuándo se sugiere subir y hasta cuánto ---- */
  function nombreDelTitulo(t) {
    if (t == null) return '';
    return String(t).replace(/^\s*semana\s+\d+\s*/i, '').replace(/^[ —–\-·:\n\t]+|[ —–\-·:\n\t]+$/g, '');
  }
  function corresponde(e, semana, mensajeSemana) {
    const prog = e.progresion || [];
    if (!prog.length || esCardio(e.nombre, e.tipo, [e.catalogo_slug, e.matched_slug]) || e.tipo === 'calentamiento') return false;
    if (esCalibracion(e, semana)) return false;
    const { actual: cur, anterior: prev } = pasoDePlan(prog, semanaJS(semana));
    if (!prev) return false;
    const a = tope(cur.reps), b = tope(prev.reps);
    if (a == null || b == null || !(a < b)) return false;
    if (cur.series == null || cur.series !== prev.series) return false;
    if (repsDelPlan(cur.reps) == null || repsDelPlan(prev.reps) == null) return false;
    if (repsNoContablesRE.test(String(cur.reps)) || repsNoContablesRE.test(String(prev.reps))) return false;
    const titulo = nombreDelTitulo(cur.titulo);
    if (tituloFueraRE.test(titulo) || tituloAnteriorFueraRE.test(nombreDelTitulo(prev.titulo))) return false;
    if (titulo && !tituloCargaRE.test(titulo)) return false;
    if (mensajeSemana && mismaCargaRE.test(mensajeSemana)) return false;
    return true;
  }
  function paso(equipo, kg) {
    if (equipo === 'maquina') return P.pasoMaquina;
    if (equipo === 'mancuerna') return kg < P.limiteMancuernaLiviana ? P.pasoMancuernaLiviana : P.pasoMancuernaPesada;
    return P.paso;
  }
  function mover(kg, pasos, equipo) {
    let k = kg;
    for (let n = 0; n < Math.abs(pasos); n++) {
      if (pasos > 0) {
        const p = paso(equipo, k);
        k = Math.floor(k / p + 1e-9) * p + p;
      } else {
        const p = paso(equipo, Math.max(0, k - 1e-6));
        k = Math.ceil(k / p - 1e-9) * p - p;
      }
      k = Math.min(KG_MAX, Math.max(0, Math.round(k * 100) / 100));
    }
    return k;
  }
  const SUBIDA_MIN = 2.5, SUBIDA_MAX = 5;
  function hasta(desde, equipo) {
    if (!(desde > 0)) return null;
    let k = desde;
    for (let n = 0; n < 10; n++) {
      k = mover(k, 1, equipo);
      const subida = k - desde;
      if (subida >= SUBIDA_MIN - 1e-9) return subida <= SUBIDA_MAX + 1e-9 ? k : null;
    }
    return null;
  }
  // La moda de los kilos y, en empate, la más alta. Un 0 viejo no es una carga.
  function moda(kilos) {
    const v = (kilos || []).filter(k => k > 0);
    if (!v.length) return null;
    const cuenta = new Map();
    for (const k of v) cuenta.set(k, (cuenta.get(k) || 0) + 1);
    let mejor = null, veces = -1;
    for (const [k, c] of cuenta) if (c > veces || (c === veces && k > mejor)) { mejor = k; veces = c; }
    return mejor;
  }

  /* ---- La guardia del OK apurado ---- */
  const ESPERA_SEGUNDO_TOQUE = 500, VENCE_EN = 3000;
  class GuardiaOK {
    constructor() { this.desde = null; this.serie = null; }
    activa(i, ahora) { return this.desde != null && this.serie === i && ahora - this.desde < VENCE_EN; }
    levantar(i, ahora) { this.desde = ahora; this.serie = i; }
    limpiar() { this.desde = null; this.serie = null; }
    esSegundoToque(i, ahora) {
      if (this.desde == null || this.serie !== i) return false;
      const t = ahora - this.desde;
      return t >= ESPERA_SEGUNDO_TOQUE && t < VENCE_EN;
    }
    esDobleToque(i, ahora) {
      return this.desde != null && this.serie === i && ahora - this.desde < ESPERA_SEGUNDO_TOQUE;
    }
  }

  /* ---- La carga de un ejercicio ----
     opts: {ultimaVez:[{reps,kg}], equipo, sinKg, recordKg, guardiaMs, mensajeSemana, seriesLocales, estado, yaAumentado}
     seriesLocales: [{reps, kg, confirmada, varianteRegistrada}] con reps y kg en texto, como la sesión de la web. */
  const MANO = { NO: 'noCorresponde', SUG: 'sugerido', ACE: 'aceptado', DES: 'descartado' };
  const numero = (t) => { if (t === '' || t == null) return null; const n = Number(String(t).replace(',', '.')); return isFinite(n) ? n : null; };
  const entero = (t) => { const n = numero(t); return n == null ? null : Math.trunc(n); };
  const copiaAumento = (a) => a ? { ...a } : { tipo: MANO.NO };

  class Carga {
    constructor(e, semana, opts) {
      const o = opts || {};
      const sk = !!o.sinKg;
      this.sinKg = sk;
      this.equipo = o.equipo || 'otro';
      const pa = pauta(e, semana);
      this.repsPlan = pa.reps;
      this.calibracion = esCalibracion(e, semana);
      const prog = e.progresion || [];
      const previa = prog.length ? pasoDePlan(prog, semanaJS(semana)).anterior : null;
      this.repsDelPlanCambian = !!previa && tope(previa.reps) !== tope(pa.reps);
      this.ultimaVez = o.ultimaVez || [];
      this.recordKg = o.recordKg || 0;
      this.guardiaMs = o.guardiaMs != null ? o.guardiaMs : 10000;
      this.varianteActual = null;

      const base = sk ? null : moda(this.ultimaVez.map(r => r.kg).filter(k => k != null));
      const est = o.estado || null;
      this.carga = est ? est.carga : base;
      this.cargaUltimaVez = est ? est.cargaUltimaVez : base;
      this.mismoPeso = est ? est.mismoPeso !== false : true;
      this.cargaCambioDesdeOK = est ? !!est.cargaCambioDesdeOK : false;
      this.ultimoOK = est ? (est.ultimoOK != null ? est.ultimoOK : null) : null;
      this.aumento = { tipo: MANO.NO };
      if (est && est.aumento) this.aumento = copiaAumento(est.aumento);
      else if (!est && !o.yaAumentado && base != null && !sk && corresponde(e, semana, o.mensajeSemana)) {
        const h = hasta(base, this.equipo);
        if (h != null) this.aumento = { tipo: MANO.SUG, desde: base, hasta: h };
      }

      const locales = o.seriesLocales || null;
      const cuantas = locales ? locales.length : Math.max(pa.series || 1, 1);
      const inicial = this.carga;
      this.series = [];
      for (let i = 0; i < cuantas; i++) {
        const l = locales && i < locales.length ? locales[i] : null;
        if (l && l.confirmada) {
          this.series.push({ reps: entero(l.reps), kg: numero(l.kg), confirmada: true, tocada: false, variante: l.varianteRegistrada || null, ajena: false });
        } else {
          const marcada = est && est.repsMarcadas && est.repsMarcadas[i] != null ? est.repsMarcadas[i] : (l ? entero(l.reps) : null);
          const kg = (!est || est.mismoPeso !== false) ? inicial : (est.kilos && est.kilos[i] != null ? est.kilos[i] : inicial);
          this.series.push({ reps: marcada, kg, confirmada: false, tocada: marcada != null, variante: null, ajena: false });
        }
      }
    }

    get estado() {
      const e = { carga: this.carga, cargaUltimaVez: this.cargaUltimaVez, mismoPeso: this.mismoPeso, aumento: copiaAumento(this.aumento),
        cargaCambioDesdeOK: this.cargaCambioDesdeOK, ultimoOK: this.ultimoOK, repsMarcadas: {}, kilos: {} };
      this.series.forEach((s, i) => {
        if (s.confirmada) return;
        if (s.tocada && s.reps != null) e.repsMarcadas[i] = s.reps;
        if (!this.mismoPeso && s.kg != null) e.kilos[i] = s.kg;
      });
      return e;
    }

    get activa() { const i = this.series.findIndex(s => !s.confirmada); return i >= 0 ? i : null; }
    get confirmadas() { return this.series.filter(s => s.confirmada).length; }
    get completo() { return this.activa == null; }

    referencia(i) {
      if (i >= 0 && i < this.ultimaVez.length) return this.ultimaVez[i];
      return this.ultimaVez.length ? this.ultimaVez[this.ultimaVez.length - 1] : null;
    }
    get pideElegirReps() { return repsDelPlan(this.repsPlan) == null; }

    base(i) {
      if (i < 0 || i >= this.series.length) return { reps: null, origen: 'ninguno' };
      const plan = repsDelPlan(this.repsPlan);
      const r = this.referencia(i);
      if (r && (plan == null || (!this.repsDelPlanCambian && (this.sinKg || this.series[i].kg === (r.kg != null ? r.kg : null))))) {
        return { reps: r.reps, origen: 'ultimaVez' };
      }
      if (plan != null) return { reps: plan, origen: 'plan' };
      return { reps: null, origen: 'ninguno' };
    }
    reps(i) {
      if (i < 0 || i >= this.series.length) return null;
      return this.series[i].reps != null ? this.series[i].reps : this.base(i).reps;
    }
    diferencia(i) {
      const r = this.reps(i), b = this.base(i).reps;
      return r == null || b == null || r === b ? null : r - b;
    }
    puedeConfirmar(i) {
      if (i < 0 || i >= this.series.length || this.series[i].confirmada) return false;
      const r = this.reps(i);
      if (r == null || r < 1) return false;
      if (this.pideElegirReps && !this.series[i].tocada) return false;
      return this.sinKg || this.series[i].kg != null;
    }
    get hechasConOtraCarga() {
      if (!this.mismoPeso || !this.cargaCambioDesdeOK || this.carga == null) return 0;
      return this.series.filter(s => s.confirmada && !s.ajena && s.kg !== this.carga && s.variante === this.varianteActual).length;
    }
    get ultimaVezMixta() { return new Set(this.ultimaVez.map(r => r.kg).filter(k => k != null)).size > 1; }

    fijarCarga(kg) {
      if (this.sinKg) return;
      if (kg !== this.carga) this.cargaCambioDesdeOK = true;
      this.carga = kg;
      const a = this.aumento;
      if ((a.tipo === MANO.SUG && kg !== a.desde) || (a.tipo === MANO.ACE && kg !== a.hasta)) this.aumento = { tipo: MANO.DES };
      if (!this.mismoPeso) return;
      for (const s of this.series) if (!s.confirmada) s.kg = kg;
    }
    moverCarga(pasos) { if (this.carga != null) this.fijarCarga(mover(this.carga, pasos, this.equipo)); }
    aplicarCargaALasHechas() {
      if (!this.mismoPeso || !this.cargaCambioDesdeOK || this.carga == null) return [];
      const tocadas = [];
      this.cargaCambioDesdeOK = false;
      this.series.forEach((s, i) => {
        if (s.confirmada && !s.ajena && s.kg !== this.carga && s.variante === this.varianteActual) { s.kg = this.carga; tocadas.push(i); }
      });
      return tocadas;
    }
    aceptarAumento() {
      const a = this.aumento;
      if (a.tipo !== MANO.SUG) return;
      this.aumento = { tipo: MANO.ACE, desde: a.desde, hasta: a.hasta };
      this.fijarCarga(a.hasta);
      if (!this.mismoPeso) for (const s of this.series) if (!s.confirmada) s.kg = a.hasta;
    }
    descartarAumento() { if (this.aumento.tipo === MANO.SUG) this.aumento = { tipo: MANO.DES }; }
    deshacerAumento() {
      const a = this.aumento;
      if (a.tipo !== MANO.ACE) return;
      this.aumento = { tipo: MANO.SUG, desde: a.desde, hasta: a.hasta };
      this.fijarCarga(a.desde);
    }
    usarMismoPeso(si) {
      if (si === this.mismoPeso) return;
      this.mismoPeso = si;
      this.series.forEach((s, i) => {
        if (s.confirmada) return;
        if (si) {
          if (this.carga == null) { const p = this.series.find(x => x.kg != null); this.carga = p ? p.kg : null; }
          s.kg = this.carga;
        } else if (this.ultimaVezMixta && this.carga === this.cargaUltimaVez) {
          const r = this.referencia(i);
          if (r && r.kg != null) s.kg = r.kg;
        }
      });
    }
    fijarKg(i, kg) {
      if (i < 0 || i >= this.series.length || this.series[i].confirmada || this.mismoPeso) return;
      this.series[i].kg = kg;
    }
    moverKg(i, pasos) {
      const s = this.series[i];
      if (s && s.kg != null) this.fijarKg(i, mover(s.kg, pasos, this.equipo));
    }
    ajustarReps(i, d) {
      if (i < 0 || i >= this.series.length || this.series[i].confirmada || !d) return;
      const plan = repsDelPlan(this.repsPlan);
      const r = this.reps(i);
      const actual = r != null ? r : (plan != null ? plan : 10);
      this.series[i].reps = Math.min(REPS_MAX, Math.max(1, actual + d));
      this.series[i].tocada = true;
    }
    // {res:'faltanDatos'} | {res:'guardia'} | {res:'lista', reps, kg}
    evaluarOK(i, ahora, insistio) {
      if (!this.puedeConfirmar(i)) return { res: 'faltanDatos' };
      const r = this.reps(i);
      const miro = this.series[i].tocada && r !== this.base(i).reps;   // sumar y restar lo mismo no es mirar
      if (!miro && !insistio && this.ultimoOK != null && ahora - this.ultimoOK < this.guardiaMs) return { res: 'guardia' };
      return { res: 'lista', reps: r, kg: this.sinKg ? null : this.series[i].kg };
    }
    anotarOK(ahora) { this.ultimoOK = ahora; this.cargaCambioDesdeOK = false; }
  }

  /* La última sesión ANTES de hoy, una fila por serie (si se corrigió, la más nueva: el historial viene de más nuevo a
     más viejo). Filtrada por variante; las filas viejas sin nota cuentan solo para la default. */
  function ultimaSesion(h, variante, esDefault, hoy, fechaDe) {
    const candidatas = (h || []).filter(r => {
      if (!(fechaDe(r.registrado_en) < hoy)) return false;
      const reps = r.reps_realizadas != null ? r.reps_realizadas : r.reps;
      if (reps == null) return false;
      if (!variante) return true;
      return r.notas === variante || (esDefault && r.notas == null);
    });
    if (!candidatas.length) return [];
    const ultimo = candidatas.map(r => fechaDe(r.registrado_en)).reduce((a, b) => (a > b ? a : b));
    const porSerie = new Map();
    for (const r of candidatas) {
      if (fechaDe(r.registrado_en) !== ultimo) continue;
      const n = r.serie_numero != null ? r.serie_numero : porSerie.size + 1;
      if (!porSerie.has(n)) porSerie.set(n, r);
    }
    return [...porSerie.keys()].sort((a, b) => a - b).map(n => {
      const r = porSerie.get(n);
      const reps = r.reps_realizadas != null ? r.reps_realizadas : r.reps;
      const kg = r.peso_kg != null ? Number(r.peso_kg) : null;
      return { reps: Number(reps), kg };
    });
  }

  // 52.5 → "52,5"; null → "".
  const kgTexto = (v) => (v == null ? '' : String(v).replace('.', ','));

  const API = {
    P, MANO, ESPERA_SEGUNDO_TOQUE, VENCE_EN, REPS_MAX,
    esCardio, tope, repsDelPlan, pauta, esCalibracion,
    corresponde, paso, mover, hasta, moda,
    GuardiaOK, Carga, ultimaSesion, kgTexto,
  };
  if (typeof module !== 'undefined' && module.exports) module.exports = API;
  else raiz.CargaSimple = API;
})(typeof window !== 'undefined' ? window : globalThis);
