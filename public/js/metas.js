/* =============================================================
   metas.js — «Pump del día» (meta de pasos) y ritmo de peso: reglas puras y textos.

   Sin red, sin pantalla y sin almacenamiento. Gemelo de Metas.swift y Metas.kt
   (rama nativa-metas). Vectores comunes con las apps:
   scripts/vectores-app/metas_pasos.json, que corre scripts/test-metas.mjs.
   Las metas vienen de la raíz de mypump_dietas.estructura: meta_pasos_dia y
   ritmo_peso_kg_semana. La app nunca inventa una meta: si falta, no hay.
   ============================================================= */
(function (raiz) {
  'use strict';

  const RANGO_PASOS = [3000, 25000];
  const RANGO_RITMO = [-1.0, 0.5];
  const NOMBRE = 'Pump del día';
  const LLENO = 'Pump lleno';
  const INICIALES = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];

  const esNumero = (x) => typeof x === 'number' && Number.isFinite(x);
  // Como Math.round de JS (las apps lo copian con jsRound).
  const entero = (x) => Math.floor(x + 0.5);

  /** Las metas del plan. Un valor que falta, que no es número o que está fuera de rango, no está. */
  function metasDe(estructura) {
    const e = estructura && typeof estructura === 'object' ? estructura : {};
    const p = e.meta_pasos_dia, r = e.ritmo_peso_kg_semana;
    const metaPasos = esNumero(p) && p === Math.round(p) && p >= RANGO_PASOS[0] && p <= RANGO_PASOS[1] ? p : null;
    const ritmo = esNumero(r) && r >= RANGO_RITMO[0] && r <= RANGO_RITMO[1] ? r : null;
    return { metaPasos, ritmo, vacio: metaPasos == null && ritmo == null };
  }

  // Días como número (días desde 1970-01-01), sin husos: la fecha ya viene local.
  function numero(f) {
    const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(f || ''));
    if (!m) return null;
    const t = Date.UTC(+m[1], +m[2] - 1, +m[3]);
    const d = new Date(t);
    if (d.getUTCFullYear() !== +m[1] || d.getUTCMonth() !== +m[2] - 1 || d.getUTCDate() !== +m[3]) return null;
    return Math.round(t / 86400000);
  }
  function texto(n) {
    const d = new Date(n * 86400000);
    return `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, '0')}-${String(d.getUTCDate()).padStart(2, '0')}`;
  }

  /** pasos: { 'YYYY-MM-DD': número } (la mejor fuente de cada día). */
  function vista(pasos, meta, hoy) {
    const nHoy = numero(hoy);
    if (nHoy == null || !(meta > 0)) return null;
    const p = pasos || {};
    const val = (n) => p[texto(n)];
    const pasosHoy = Math.max(0, entero(esNumero(p[hoy]) ? p[hoy] : 0));
    const cumplido = pasosHoy >= meta;
    const llego = (n) => esNumero(val(n)) && entero(val(n)) >= meta;

    let racha = 0;
    let d = cumplido ? nHoy : nHoy - 1;
    while (llego(d) && racha < 400) { racha++; d--; }

    // 1970-01-01 fue jueves: (n + 3) % 7 es 0 los lunes.
    const lunes = nHoy - (((nHoy + 3) % 7) + 7) % 7;
    const semana = [];
    for (let i = 0; i < 7; i++) {
      const n = lunes + i, v = val(n);
      let estado;
      if (n > nHoy) estado = 'futuro';
      else if (n === nHoy) estado = cumplido ? 'cumplido' : 'hoy';
      else if (esNumero(v)) estado = entero(v) >= meta ? 'cumplido' : 'no';
      else estado = 'sin_dato';
      semana.push({ fecha: texto(n), inicial: INICIALES[i], estado });
    }

    const previos = [];
    for (let j = 1; j <= 7; j++) { const v = val(nHoy - j); if (esNumero(v)) previos.push(v); }
    const promedio7 = previos.length ? entero(previos.reduce((a, b) => a + b, 0) / previos.length) : null;

    return { meta, pasosHoy, fraccion: Math.min(1, pasosHoy / meta), falta: Math.max(0, meta - pasosHoy), cumplido, racha, semana, promedio7 };
  }

  // ── Una sola celebración por día ──
  function debeCelebrar(celebrados, hoy, pasosHoy, meta) {
    if (!(meta > 0) || !(pasosHoy >= meta) || numero(hoy) == null) return false;
    const c = Array.isArray(celebrados) ? celebrados : [];
    if (c.includes(hoy)) return false;
    // Un viaje al oeste vuelve a «ayer»: no se festeja dos veces el mismo esfuerzo.
    const ultima = c.slice().sort().pop();
    return !(ultima && ultima >= hoy);
  }
  function marcar(celebrados, hoy) {
    return (Array.isArray(celebrados) ? celebrados : []).filter((f) => f !== hoy).concat(hoy).sort().slice(-60);
  }

  // ── Textos (TEXTOS_PARA_OK, sección Metas) ──
  function miles(n) {
    const s = String(Math.abs(entero(n)));
    return (n < 0 ? '-' : '') + s.replace(/\B(?=(\d{3})+(?!\d))/g, '.');
  }
  const T = {
    nombre: NOMBRE,
    lleno: LLENO,
    deMeta: (v) => `de ${miles(v.meta)} pasos`,
    estado: (v) => (v.cumplido ? 'Llegaste a tus pasos de hoy' : `Te faltan ${miles(v.falta)} pasos`),
    racha: (n) => (n >= 2 ? `${n} días seguidos` : null),
    sinSalud: (meta) => `Tu meta es de ${miles(meta)} pasos por día`,
    conectar: 'Conectá Salud y vas a ver cómo venís',
    conectarBoton: 'Conectar Salud',
    celebracion: (meta) => `Llegaste a tus ${miles(meta)} pasos de hoy`,
    celebracionRacha: (n) => (n >= 2 ? `Van ${n} días seguidos` : null),
    seguir: 'Seguir',
    lineaSalud: (meta, prom) => (prom == null ? `Meta ${miles(meta)} pasos por día` : `Meta ${miles(meta)} pasos por día, tu promedio ${miles(prom)}`),
    accesible: (v) => {
      let s = `${NOMBRE}, ${miles(v.pasosHoy)} de ${miles(v.meta)} pasos. ${T.estado(v)}.`;
      const r = T.racha(v.racha);
      if (r) s += ` ${r}.`;
      return s;
    },
    enRitmo: 'Vas justo al ritmo que buscamos',
  };

  // ── Ritmo de peso ──
  function cantidad(kg) {
    const dec = Math.max(1, entero(Math.abs(kg) * 10));
    if (dec === 5) return 'medio kilo';
    if (dec < 10) return `${dec * 100} g`;
    if (dec === 10) return 'un kilo';
    let s = (dec / 10).toFixed(1).replace('.', ',');
    if (s.endsWith(',0')) s = s.slice(0, -2);
    return s + ' kg';
  }
  function textoMeta(r) {
    if (Math.abs(r) < 0.001) return 'Buscamos mantener tu peso';
    const c = cantidad(r);
    const unos = c.endsWith(' g') || c.includes(',') ? 'unos ' : '';
    return `Buscamos ${r < 0 ? 'bajar' : 'subir'} ${unos}${c} por semana`;
  }
  /** serie: [{fecha, kg}]. La tendencia es la media de 7 días contra la de los 7 anteriores, como la tarjeta de peso. */
  function ritmo(r, serie, hoy) {
    const meta = textoMeta(r);
    const nHoy = numero(hoy);
    const nada = { meta, tendencia: null, enRitmo: false, deltaG: null };
    if (nHoy == null) return nada;
    const media = (fin) => {
      const v = (serie || []).filter((p) => { const n = numero(p.fecha); return n != null && n > fin - 7 && n <= fin; }).map((p) => p.kg);
      return v.length ? v.reduce((a, b) => a + b, 0) / v.length : null;
    };
    const ultimos = (serie || []).filter((p) => { const n = numero(p.fecha); return n != null && n > nHoy - 7 && n <= nHoy; }).length;
    const m7 = media(nHoy), m7p = media(nHoy - 7);
    if (ultimos < 4 || m7 == null || m7p == null) return nada;
    const g = entero((m7 - m7p) * 1000);
    const tendencia = Math.abs(g) < 100 ? 'Venís estable' : `Venís ${g < 0 ? 'bajando' : 'subiendo'} ${cantidad(g / 1000)} por semana`;
    const o = r * 1000;
    const enRitmo = Math.abs(r) < 0.001 ? Math.abs(g) <= 150
      : (g < 0) === (o < 0) && Math.abs(g) >= 0.75 * Math.abs(o) && Math.abs(g) <= 1.5 * Math.abs(o);
    return { meta, tendencia, enRitmo, deltaG: g };
  }

  const API = { RANGO_PASOS, RANGO_RITMO, NOMBRE, LLENO, metasDe, numero, texto, vista, debeCelebrar, marcar, miles, T, cantidad, textoMeta, ritmo };
  if (typeof module !== 'undefined' && module.exports) module.exports = API;
  else raiz.Metas = API;
})(typeof window !== 'undefined' ? window : globalThis);
