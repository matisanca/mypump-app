/* =============================================================
   reglas-entreno.js — Las reglas de Entreno de la app 2.0.3 que la web
   no tenía: la preparación de cada ejercicio (E1), el descanso elegido
   por ejercicio (E2), el aviso de récord (E3) y el RIR del plan (E4).

   Fuente de verdad: apps/ios/MyPumpKit/Sources/MyPumpReglas/
   Preparacion.swift, PreferenciasEntreno.swift y RecordSerie.swift
   (rama nativa-202). Vectores: scripts/vectores-app/preparacion.json y
   entreno_203.json, que corre scripts/test-reglas-entreno.mjs.
   ============================================================= */
(function (raiz) {
  'use strict';
  const fin = (x) => typeof x === 'number' && isFinite(x);
  // JS.texto de la app: el número como lo escribe JS, con coma.
  const conComa = (x) => String(x).replace('.', ',');

  /* ---------------- Preparación (E1) ---------------- */
  const P = {
    descansoSegundos: 30,
    pctCalentamiento: 25, pctAproximaciones: [60, 85], pctSiguientePrincipal: 75, pctAccesorio: 60,
    repsCalentamiento: '16-20', repsAproximacion: '5', repsAccesorio: '5-6', repsPotenciacion: '1-3',
    potenciacionKg: 5, potenciacionKgLiviano: 2.5, potenciacionLimiteLiviano: 50, potenciacionTope: 10,
    kgBarra: 20, paso: 2.5, pasoMaquina: 5, pasoMancuernaLiviana: 1, pasoMancuernaPesada: 2, limiteMancuernaLiviana: 10,
  };
  const TEXTO_SIN_KG = 'Usalas para encontrar tu peso de trabajo.';
  const barraRE = /\bbarra\b/;
  const noBarraLibreRE = /polea|cable|jalon|maquina|smith|multipower|dominada|mancuerna|barra\s*(z|ez)\b/;
  const mancuernaRE = /mancuerna/;
  const maquinaRE = /maquina|polea|cable|prensa|smith|multipower|jalon|hack|pec\s*deck|contractora/;
  const accesorioRE = new RegExp(['remo al menton', 'unilateral', 'a una mano', 'a un brazo', 'a una pierna', 'bulgara',
    'zancada', 'estocada', 'press cerrado', 'agarre cerrado', 'fondos en maquina', 'pull[\\s-]*through', 'subida al cajon',
    '\\bstep\\b', 'goblet'].join('|'));
  const sinPreparacionRE = new RegExp(['salto al cajon', 'box jump', 'swing', 'turkish', 'get[\\s-]*up', 'power clean',
    'cargada', 'farmer', 'granjero', 'monster walk', 'rollout', 'isometric'].join('|'));

  const normal = (s) => String(s || '').toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '');
  const compuesto = (t) => t === 'compuesto';
  const monoarticular = (t) => t === 'aislamiento' || t === 'aislado';
  function esPrincipal(nombre, tipo) { return compuesto(tipo) && !accesorioRE.test(normal(nombre)); }
  function sinPreparacion(nombre) { return sinPreparacionRE.test(normal(nombre)); }
  function esBarra(nombre, equipo) {
    if (String(equipo || '').trim().toLowerCase() === 'barbell') return true;
    const n = normal(nombre);
    return barraRE.test(n) && !noBarraLibreRE.test(n);
  }
  function equipoDe(nombre, equipo) {
    const e = String(equipo || '').trim().toLowerCase(), n = normal(nombre);
    if (e === 'dumbbell' || mancuernaRE.test(n)) return 'mancuerna';
    if (esBarra(nombre, equipo)) return 'barra';
    if (e === 'machine' || e === 'cable' || maquinaRE.test(n)) return 'maquina';
    return 'otro';
  }
  function redondearKg(kg, eq) {
    const p = eq === 'mancuerna' ? (kg < P.limiteMancuernaLiviana ? P.pasoMancuernaLiviana : P.pasoMancuernaPesada)
      : eq === 'maquina' ? P.pasoMaquina : P.paso;
    const r = Math.floor(kg / p + 0.5 + 1e-9) * p;
    if (eq === 'barra') return Math.max(P.kgBarra, r);
    return r > 0 ? r : null;
  }
  // entrada = {tipo, musculo (null si el catálogo no lo tiene), nombre, sinPeso}
  const cuenta = (e) => (compuesto(e.tipo) || monoarticular(e.tipo)) && !e.sinPeso && !sinPreparacion(e.nombre);
  const grupo = (e) => { const m = String(e.musculo || '').trim().toLowerCase(); return m || null; };
  function primero(dia, i) {
    if (i < 0 || i >= dia.length || !cuenta(dia[i])) return false;
    const e = dia[i], g = grupo(e), pr = esPrincipal(e.nombre, e.tipo);
    if (!g) return pr && dia.findIndex(cuenta) === i;
    return dia.findIndex(x => cuenta(x) && grupo(x) === g && esPrincipal(x.nombre, x.tipo) === pr) === i;
  }
  // El `aproximaciones` del plan: null si no viene o no se entiende (decide la web); [] es «sin preparación».
  function aproximacionesDelPlan(v) {
    if (!Array.isArray(v)) return null;
    const numero = (x) => (typeof x === 'number' ? x : (typeof x === 'string' && x.replace('%', '').trim() !== '' ? Number(x.replace(/%/g, '').replace(',', '.').trim()) : NaN));
    const series = v.map(o => {
      if (!o || typeof o !== 'object' || Array.isArray(o)) return null;
      const a = {};
      if (typeof o.reps === 'number' && fin(o.reps) && o.reps >= 1 && o.reps <= 100) a.reps = String(Math.round(o.reps));
      else if (typeof o.reps === 'string' && o.reps.trim() && o.reps.length <= 12) a.reps = o.reps.trim();
      const p = numero(o.pct); if (fin(p) && p > 0 && p <= 150) a.pct = p;
      const k = numero(o.kg); if (fin(k) && k > 0 && k <= 1000) a.kg = k;
      if (typeof o.nota === 'string' && o.nota.trim()) a.nota = o.nota;
      return a.reps != null || a.kg != null ? a : null;
    }).filter(Boolean);
    return v.length === 0 || series.length ? series : null;
  }
  const serie = (tipo, o) => Object.assign({ tipo, numero: null, reps: '', kg: null, barraSola: false, opcional: false, nota: null }, o);
  function preparacion(dia, indice, nombre, equipo, sinKg, kgEfectivo, plan) {
    if (indice < 0 || indice >= dia.length) return [];
    const ref = sinKg ? null : (fin(kgEfectivo) && kgEfectivo > 0 ? kgEfectivo : null);
    const eq = equipoDe(nombre, equipo);
    const barraPesada = eq === 'barra' && (ref || 0) < P.kgBarra;
    const kg = (pct) => {
      if (ref == null || barraPesada) return [null, false];
      const k = redondearKg(ref * pct / 100, eq);
      if (k == null || k > ref) return [null, false];
      return [k, eq === 'barra' && k <= P.kgBarra];
    };
    if (plan) {
      const n = plan.length;
      return plan.map((a, i) => {
        const [k, sola] = sinKg ? [null, false] : (a.kg != null ? [a.kg, false] : (a.pct != null ? kg(a.pct) : [null, false]));
        return serie('aproximacion', { numero: n > 1 ? i + 1 : null, reps: a.reps != null ? a.reps : '–', kg: k, barraSola: sola, nota: a.nota || null });
      });
    }
    const e = dia[indice];
    if (!cuenta(e) || sinKg) return [];
    const esPrimero = primero(dia, indice);
    if (!esPrincipal(e.nombre, e.tipo)) {
      if (!esPrimero) return [];
      const [k, sola] = kg(P.pctAccesorio);
      return [serie('aproximacion', { reps: P.repsAccesorio, kg: k, barraSola: sola })];
    }
    const aproximaciones = () => P.pctAproximaciones.map((p, i) => {
      const [k, sola] = kg(p);
      return serie('aproximacion', { numero: i + 1, reps: P.repsAproximacion, kg: k, barraSola: sola });
    });
    if (!grupo(e)) {
      const s = [];
      if (esPrimero) { const [k, sola] = kg(P.pctCalentamiento); s.push(serie('calentamiento', { reps: P.repsCalentamiento, kg: k, barraSola: sola })); }
      return s.concat(aproximaciones());
    }
    if (!esPrimero) {
      const [k, sola] = kg(P.pctSiguientePrincipal);
      return [serie('aproximacion', { reps: P.repsAproximacion, kg: k, barraSola: sola })];
    }
    const [kc, solac] = kg(P.pctCalentamiento);
    const s = [serie('calentamiento', { reps: P.repsCalentamiento, kg: kc, barraSola: solac })].concat(aproximaciones());
    let kp = null;
    if (ref != null && !barraPesada) {
      const suma = Math.min(P.potenciacionTope, ref < P.potenciacionLimiteLiviano ? P.potenciacionKgLiviano : P.potenciacionKg);
      kp = redondearKg(ref + suma, eq);
    }
    s.push(serie('potenciacion', { reps: P.repsPotenciacion, kg: kp, barraSola: eq === 'barra' && kp === P.kgBarra, opcional: true }));
    return s;
  }
  function etiquetaPreparacion(s) {
    if (s.tipo === 'calentamiento') return 'Calentamiento';
    if (s.tipo === 'aproximacion') return s.numero != null ? `Aproximación ${s.numero}` : 'Aproximación';
    return 'Potenciación';
  }
  function textoKgPreparacion(s) { return s.barraSola ? 'Barra sola' : (s.kg != null ? conComa(s.kg) : null); }
  function kgEfectivo(escrito, sugerido) {
    const t = String(escrito || '') === '' ? String(sugerido || '') : String(escrito);
    const k = parseFloat(t.replace(',', '.'));
    return fin(k) && k > 0 ? k : null;
  }

  /* ---------------- Descanso elegido (E2) ---------------- */
  const DESCANSO = { minimo: 30, maximo: 300, paso: 15, porDefecto: 90 };
  const OPCIONES_DESCANSO = [];
  for (let s = DESCANSO.minimo; s <= DESCANSO.maximo; s += DESCANSO.paso) OPCIONES_DESCANSO.push(s);
  const descansoValido = (s) => (OPCIONES_DESCANSO.includes(s) ? s : null);
  // plan: descanso_segundos del ejercicio (≤ 0 o sin valor → 90).
  function descansoPlan(v) { const n = Number(v); return fin(n) && n > 0 ? n : DESCANSO.porDefecto; }
  function segundosDescanso(propio, plan) {
    const p = descansoValido(propio);
    if (p != null) return p;
    return plan != null ? plan : DESCANSO.porDefecto;
  }

  /* ---------------- RIR del plan (E4) ---------------- */
  const numeroRE = /\d+([.,]\d+)?/g;
  const rangoRE = /\d+([.,]\d+)?(\s*[-–]\s*\d+([.,]\d+)?)?/;
  const rpeRE = /rpe/i;
  // ¿La serie lleva RIR? No en calentamiento, cardio, core ni peso corporal.
  function llevaRir(tipo, sinPeso) { return !['calentamiento', 'cardio', 'core'].includes(tipo || '') && !sinPeso; }
  function rirAGuardar(objetivo) {
    if (objetivo == null) return '0';
    const o = String(objetivo);
    if (rpeRE.test(o)) return '0';
    const m = o.match(numeroRE);
    if (!m) return '0';
    const n = Number(m[0].replace(',', '.'));
    if (!fin(n)) return '0';
    return String(Math.min(5, Math.max(0, Math.ceil(n))));
  }
  function leyendaRir(objetivo) {
    if (objetivo == null) return 'Al fallo';
    const o = String(objetivo);
    if (rpeRE.test(o)) return 'Al fallo';
    const rango = o.match(rangoRE);
    if (!rango) return 'Al fallo';
    const numeros = (rango[0].match(numeroRE) || []).map(x => Number(x.replace(',', '.')));
    if (numeros.every(x => x === 0)) return 'Al fallo';
    const partes = rango[0].split(/[-–]/).map(p => p.trim().replace('.', ','));
    return `Dejando ${partes.join('–')} en reserva`;
  }

  /* ---------------- Récord (E3) ---------------- */
  const TOL = 1e-6;
  const TOPE_HISTORIAL = 48, DIAS_SUFICIENTES = 180;
  // marca = {kg, reps}
  function evaluarRecord(s, sinKg, verosimil, anteriores, hoy) {
    if (sinKg || !verosimil || !(s.reps >= 1) || !(s.kg > 0) || !fin(s.kg)) return null;
    const sirve = (m) => m.kg > 0 && fin(m.kg) && m.reps >= 1;
    const previas = anteriores.filter(sirve);
    if (!previas.length) return null;
    const piso = previas.concat(hoy.filter(sirve));
    const mejorKg = Math.max(...piso.map(m => m.kg));
    const mejorReps = Math.max(0, ...piso.filter(m => Math.abs(m.kg - mejorKg) < TOL).map(m => m.reps));
    if (s.kg > mejorKg + TOL) {
      const d = Math.round((s.kg - mejorKg) * 100) / 100;
      return { tipo: 'kg', delta: d, texto: `Récord: +${conComa(d)} kg` };
    }
    if (Math.abs(s.kg - mejorKg) < TOL && s.reps > mejorReps) {
      const n = s.reps - mejorReps;
      return { tipo: 'reps', delta: n, texto: `Récord: +${n} rep${n === 1 ? '' : 's'}` };
    }
    return null;
  }
  // Con 48 filas que abarcan menos de 180 días, el récord de verdad puede ser más viejo: no se avisa.
  function historiaSuficiente(fechas, hoy) {
    if (fechas.length < TOPE_HISTORIAL) return true;
    const dia = (ymd) => { const t = Date.parse(ymd + 'T00:00:00Z'); return fin(t) ? Math.round(t / 86400000) : null; };
    const nHoy = dia(hoy);
    const ns = fechas.map(dia).filter(x => x != null);
    if (nHoy == null || !ns.length) return false;
    return nHoy - Math.min(...ns) >= DIAS_SUFICIENTES;
  }

  /* ── Volumen por músculo (app 2.1, VolumenMusculo.swift) ──
     Las series de cada músculo de lunes a domingo, con la semana pasada al
     lado y lo de hoy aparte. Cada fila del historial es una serie; el
     calentamiento y el cardio no cuentan. Sin músculo del catálogo va a «Sin
     músculo asignado», al final. Vectores: apps/shared/vectores/volumen.json. */
  const VOL_NO_CUENTAN = ['cardio', 'calentamiento'];
  const VOL_ORDEN = ['quadriceps', 'shoulders', 'abdominals', 'chest', 'hamstrings', 'triceps', 'biceps', 'lats',
    'middle back', 'calves', 'lower back', 'forearms', 'glutes', 'traps', 'adductors', 'neck', 'abductors'];
  const VOL_NOMBRES = { quadriceps: 'cuádriceps', shoulders: 'hombros', abdominals: 'abdominales', chest: 'pecho',
    hamstrings: 'isquiotibiales', triceps: 'tríceps', biceps: 'bíceps', lats: 'dorsales', 'middle back': 'espalda media',
    calves: 'pantorrillas', 'lower back': 'zona lumbar', forearms: 'antebrazos', glutes: 'glúteos', traps: 'trapecios',
    adductors: 'aductores', neck: 'cuello', abductors: 'abductores' };
  const VOL_SIN_MUSCULO = 'Sin músculo asignado';
  const VOL_VACIO = 'Todavía no registraste series esta semana.';
  function volNormalizar(m) {
    const x = String(m == null ? '' : m).trim().toLowerCase();
    return VOL_ORDEN.includes(x) ? x : null;
  }
  function volNombre(m) {
    const n = VOL_NOMBRES[volNormalizar(m)];
    return n ? n[0].toUpperCase() + n.slice(1) : VOL_SIN_MUSCULO;
  }
  const _fechaOk = (f) => typeof f === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(f) && !isNaN(Date.parse(f + 'T12:00:00Z'))
    && new Date(f + 'T12:00:00Z').toISOString().slice(0, 10) === f;
  function _lunes(f) {
    const d = new Date(f + 'T12:00:00Z');
    const dow = (d.getUTCDay() + 6) % 7;
    d.setUTCDate(d.getUTCDate() - dow);
    return d.toISOString().slice(0, 10);
  }
  function _menos7(f) { const d = new Date(f + 'T12:00:00Z'); d.setUTCDate(d.getUTCDate() - 7); return d.toISOString().slice(0, 10); }
  // historial: [{musculo, tipo, fecha 'YYYY-MM-DD', lugar, serie}]
  function volumenMusculo(historial, hoy) {
    const lunes = _lunes(hoy), anterior = _menos7(lunes);
    const cuenta = new Map();
    for (const r of (historial || [])) {
      if (r.tipo && VOL_NO_CUENTAN.includes(r.tipo)) continue;
      if (!_fechaOk(r.fecha)) continue;
      const sem = _lunes(r.fecha);
      const k = volNormalizar(r.musculo) || '';
      const c = cuenta.get(k) || { semana: 0, anterior: 0, hoy: 0 };
      if (sem === lunes) { c.semana++; if (r.fecha === hoy) c.hoy++; }
      else if (sem === anterior) c.anterior++;
      else continue;
      cuenta.set(k, c);
    }
    const rango = (m) => { if (!m) return VOL_ORDEN.length; const i = VOL_ORDEN.indexOf(m); return i < 0 ? VOL_ORDEN.length : i; };
    const filas = [...cuenta.entries()].sort((a, b) =>
      (b[1].semana - a[1].semana) || (b[1].anterior - a[1].anterior) || (rango(a[0]) - rango(b[0])))
      .map(([k, v]) => ({ musculo: k || null, nombre: volNombre(k || null), semana: v.semana, anterior: v.anterior, hoy: v.hoy }));
    const ordenadas = filas.filter(f => f.musculo).concat(filas.filter(f => !f.musculo));
    const suma = (c) => ordenadas.reduce((s, f) => s + f[c], 0);
    const tope = ordenadas.reduce((m, f) => Math.max(m, f.semana, f.anterior), 0);
    return { semana: lunes, filas: ordenadas, total: suma('semana'), totalAnterior: suma('anterior'), totalHoy: suma('hoy'), tope };
  }

  /* ---------------- sinRIR (2.3.1) ----------------
     REGLA DURA: «RIR» y «reps en reserva» no aparecen NUNCA en una pantalla del alumno (todo al fallo). El texto libre
     del plan (notas_tecnica, notas de la preparación) pasa por acá antes de dibujarse: se saca la mención sin romper la
     frase y, si queda alguna que no se entienda, se saca la oración entera. «cerca del fallo» pasa a «al fallo».
     Mismo algoritmo en MyPumpModelos/TextoAlumno.swift y modelos/TextoAlumno.kt; vectores: sin_rir.json. */
  const SR_N = String.raw`\d+(?:[.,]\d+)?(?:\s*(?:[-–]|a|o)\s*\d+(?:[.,]\d+)?)?`;
  const SR_RES = String.raw`(?:en reserva|en la recámara|en el tanque)`;
  const SR_REPS = String.raw`(?:repeticiones|repes|reps|rep)`;
  const SR_DETECTA = /\bRIR\b|en reserva|en la recámara|en el tanque|cerca del fallo/i;
  const SR_QUEDA = /\bRIR\b|en reserva|en la recámara|en el tanque/i;
  const SR_PASOS = [
    [/\bcerca del fallo\b/gi, 'al fallo'],
    [/\bno calcules\s+(?:el\s+)?RIR\b\s*[:.,;]?\s*/gi, ''],
    [new RegExp(String.raw`,\s*([^\s,.;:()]+(?:\s+[^\s,.;:()]+)?)\s+y\s+(?:con\s+)?RIR\s*` + SR_N, 'gi'), ' y $1'],
    [new RegExp(String.raw`\s*[·,;]\s*(?:con\s+)?RIR\s*` + SR_N, 'gi'), ''],
    [new RegExp(String.raw`\s+y\s+(?:con\s+)?RIR\s*` + SR_N, 'gi'), ''],
    [/\s*\([^()]*(?:\bRIR\b|en reserva|en la recámara|en el tanque|te sobra|que te queden|quedar\s+\d)[^()]*\)/gi, ''],
    [new RegExp(String.raw`\s*\b(?:con\s+)?RIR\s*` + SR_N, 'gi'), ''],
    [new RegExp(String.raw`(?:\s+y\s+|\s*,\s*)?\b(?:dejá|deja|quedate con)\s+` + SR_N + String.raw`\s*` + SR_REPS + String.raw`?\s*` + SR_RES + String.raw`(?:\s+en todo)?\s*(?:y\s+|,\s*)?`, 'gi'), ' '],
    [new RegExp(String.raw`\s*,?\s*(?:\by\s+)?(?:solo\s+)?(?:\b(?:dejando|dejar|con|que te queden?)\s+)?(?:solo\s+)?` + SR_N + String.raw`\s*` + SR_REPS + String.raw`?\s*` + SR_RES + String.raw`(?:\s+en todo)?`, 'gi'), ''],
  ];
  const SR_LIMPIEZA = [
    [/[ \t]{2,}/g, ' '],
    [/\(\s*\)/g, ''],
    [/\s+([,.;:)])/g, '$1'],
    [/\(\s+/g, '('],
    [/[,;:]\s*([.!?])/g, '$1'],
    [/([,;:])\s*[,;:]/g, '$1'],
    [/\s*[·—–]\s*([.!?)]|$)/g, '$1'],
  ];
  function srOracion(o) {
    let x = o.replace(/^[\s,;:·—–-]+/, '').trim();
    if (!x || /^[.!?]+$/.test(x)) return '';
    if (SR_QUEDA.test(x)) return '';
    return x.charAt(0).toUpperCase() + x.slice(1);
  }
  function srLinea(l) {
    let x = l;
    for (const [re, por] of SR_PASOS) x = x.replace(re, por);
    for (const [re, por] of SR_LIMPIEZA) x = x.replace(re, por);
    return x.split(/(?<=[.!?])\s+/).map(srOracion).filter(Boolean).join(' ');
  }
  function sinRIR(texto) {
    if (texto == null) return texto;
    const t = String(texto);
    if (!SR_DETECTA.test(t)) return t;
    const lineas = [];
    for (const l of t.split('\n')) {
      if (!SR_DETECTA.test(l)) { lineas.push(l); continue; }
      const r = srLinea(l);
      if (r) lineas.push(r);
    }
    return lineas.join('\n').trim();
  }

  /* El plan con reserva a propósito (decisión clínica de Mati: lumbar, cardiopatía, excepciones): el rir de esa semana
     tiene un número mayor que 0. Ahí la nota es una indicación clínica y se muestra entera, sin sinRIR. Sin dato, 0,
     «al fallo» o un RPE: al fallo. */
  function conReserva(rir) {
    if (rir == null) return false;
    const o = String(rir);
    if (rpeRE.test(o)) return false;
    const rango = o.match(rangoRE);
    if (!rango) return false;
    return (rango[0].match(numeroRE) || []).some(x => Number(x.replace(',', '.')) > 0);
  }
  /** La nota del plan como la ve el alumno: entera si esa semana lleva reserva; si no, sin RIR. */
  function notaParaAlumno(texto, rir) {
    if (texto == null) return texto;
    return conReserva(rir) ? String(texto) : sinRIR(String(texto));
  }

  const API = {
    P, TEXTO_SIN_KG, esPrincipal, sinPreparacion, equipoDe, redondearKg, primero, aproximacionesDelPlan, preparacion,
    etiquetaPreparacion, textoKgPreparacion, kgEfectivo,
    DESCANSO, OPCIONES_DESCANSO, descansoValido, descansoPlan, segundosDescanso,
    llevaRir, rirAGuardar, leyendaRir,
    evaluarRecord, historiaSuficiente, TOPE_HISTORIAL,
    volumenMusculo, VOL_VACIO,
    sinRIR, conReserva, notaParaAlumno,
  };
  if (typeof module !== 'undefined' && module.exports) module.exports = API;
  else raiz.ReglasEntreno = API;
})(typeof window !== 'undefined' ? window : globalThis);
