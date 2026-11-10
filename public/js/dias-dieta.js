/* Días anteriores en Dieta y copiar a hoy: las reglas de la app 2.3.0 (DiasDieta y CopiaDeComidas de MyPumpReglas).
 * Sin DOM, para probarlas sola (scripts/test-dias-dieta.mjs). El servidor mira la fecha de Argentina. */
(function (global) {
  'use strict';
  const AD = (typeof module !== 'undefined' && module.exports) ? require('./ajustes-dieta.js') : global.AjustesDieta;

  const DIAS_ATRAS = 7;
  const DIAS_MARCAR_FABRICA = 2;
  const ZONA_SERVIDOR = 'America/Argentina/Buenos_Aires';

  const hoyServidor = (ahora = new Date()) => ahora.toLocaleDateString('en-CA', { timeZone: ZONA_SERVIDOR });

  function _partes(iso) {
    const p = String(iso).split('-').map(Number);
    return p.length === 3 && p.every(Number.isFinite) ? p : null;
  }
  function sumar(iso, dias) {
    const p = _partes(iso);
    if (!p) return null;
    return new Date(Date.UTC(p[0], p[1] - 1, p[2] + dias)).toISOString().slice(0, 10);
  }
  // Hoy primero y después los días que el servidor todavía acepta: un teléfono atrasado no ofrece uno que la base rechazaría.
  function seleccionables(hoy, hoyServ) {
    const piso = sumar(hoyServ, -DIAS_ATRAS) || hoy;
    const r = [];
    for (let i = 0; i <= DIAS_ATRAS; i++) {
      const f = sumar(hoy, -i);
      if (f === hoy || f >= piso) r.push(f);
    }
    return r;
  }
  function permiteMarcar(iso, hoyServ, dias) {
    const piso = sumar(hoyServ, -Math.max(0, Math.min(dias, DIAS_ATRAS)));
    return !!piso && iso >= piso && iso <= hoyServ;
  }
  // La ventana de «Comí» / «Salté» que dice la palanca remota (dieta_dias_marcar), entre la de fábrica y 7.
  function diasMarcar(palanca) {
    const n = Number.isInteger(palanca) ? palanca : DIAS_MARCAR_FABRICA;
    return Math.max(DIAS_MARCAR_FABRICA, Math.min(n, DIAS_ATRAS));
  }

  const SEMANA = ['domingo', 'lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado'];
  const SEMANA_CORTA = ['Dom', 'Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb'];
  const MESES = ['enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'];
  function _dia(iso) {
    const p = _partes(iso);
    return p ? new Date(Date.UTC(p[0], p[1] - 1, p[2])) : null;
  }
  function rotuloCorto(iso, hoy) {
    if (iso === hoy) return 'Hoy';
    if (iso === sumar(hoy, -1)) return 'Ayer';
    const d = _dia(iso);
    return d ? `${SEMANA_CORTA[d.getUTCDay()]} ${d.getUTCDate()}` : iso;
  }
  function rotuloLargo(iso) {
    const d = _dia(iso);
    return d ? `${SEMANA[d.getUTCDay()]} ${d.getUTCDate()} de ${MESES[d.getUTCMonth()]}` : iso;
  }

  /* ---- Copiar a hoy ---- */
  const _opcionNombre = (c, i) => (c.options[i] && c.options[i].name) || String.fromCharCode(65 + i);
  const _excl = (m) => (m.foodsExcluidos || []).slice().sort((a, b) => a - b);
  function igualMarca(a, b) {
    if (!a || !b) return !a && !b;
    return a.opcion === b.opcion && a.estado === b.estado && JSON.stringify(_excl(a)) === JSON.stringify(_excl(b));
  }
  function _canonico(v) {
    if (Array.isArray(v)) return v.map(_canonico);
    if (v && typeof v === 'object') return Object.keys(v).sort().reduce((o, k) => { o[k] = _canonico(v[k]); return o; }, {});
    return v;
  }
  function igualAjuste(a, b) {
    if (!a || !b) return !a && !b;
    return JSON.stringify(_canonico(AD.serializarAjuste(a))) === JSON.stringify(_canonico(AD.serializarAjuste(b)));
  }
  // 'nueva': hoy no hay nada; 'igual': ya está eso; 'conflicto': hay otra cosa y solo se pisa si el cliente lo pide.
  function estado(marca, ajuste, hoyMarca, hoyAjuste) {
    if (!hoyMarca && !hoyAjuste) return 'nueva';
    return igualMarca(hoyMarca, marca) && igualAjuste(hoyAjuste, ajuste) ? 'igual' : 'conflicto';
  }
  const _norm = (s) => String(s == null ? '' : s).trim().toLowerCase();
  // La misma descripción y las mismas kcal redondeadas: copiarla de nuevo la duplicaría.
  function mismaLibre(a, b) {
    return _norm(a.descripcion) === _norm(b.descripcion) && Math.round(Number(a.kcal) || 0) === Math.round(Number(b.kcal) || 0);
  }

  function plan({ comidas, origenMarcas, origenAjustes, origenLibres, hoyMarcas, hoyAjustes, hoyLibres, otroPlan, kcal }) {
    const p = { comidas: [], libres: [], otroPlan: !!otroPlan };
    // Por conteo: dos iguales en el origen y una hoy son una que ya está y una nueva.
    const quedan = hoyLibres.slice();
    p.libres = origenLibres.map((l) => {
      const i = quedan.findIndex((x) => mismaLibre(x, l));
      if (i < 0) return { libre: l, id: `libre:${l.id}`, estado: 'nueva' };
      quedan.splice(i, 1);
      return { libre: l, id: `libre:${l.id}`, estado: 'igual' };
    });
    if (otroPlan) return p;
    for (const c of comidas) {
      if (!c.options || !c.options.length) continue;
      const m = origenMarcas[c.id];
      const a = origenAjustes[c.id];
      if ((!m && !a) || (m && m.estado === 'saltado') || (a && a.omitida)) continue;
      let o = a ? a.opcion : 0;
      if (m) {
        // La opción de la marca tiene que seguir existiendo: indiceOpcion caería a la A y copiaría otra comida.
        if (!m.opcion) continue;
        const existe = c.options.some((x, i) => x.name === m.opcion || (!x.name && String.fromCharCode(65 + i) === m.opcion));
        if (!existe) continue;
        o = AD.indiceOpcion(c, m.opcion);
      }
      if (o < 0 || o >= c.options.length || (a && (a.opcion < 0 || a.opcion >= c.options.length))) continue;
      let marca = m || null;
      if (m) {
        const tope = c.options[o].foods.length + (a ? a.agregados.length : 0);
        marca = { opcion: m.opcion, estado: m.estado, foodsExcluidos: (m.foodsExcluidos || []).filter((i) => i < tope) };
      }
      p.comidas.push({
        id: c.id, comidaId: c.id, nombre: c.name || '', opcion: o, nombreOpcion: _opcionNombre(c, o), marca, ajuste: a || null,
        kcal: kcal(c, marca, a || null, o), agregados: a ? a.agregados.length : 0,
        conCantidades: !!a && (Object.keys(a.cantidades || {}).length > 0 || (a.deltaKcal || 0) !== 0),
        estado: estado(marca, a || null, hoyMarcas[c.id] || null, hoyAjustes[c.id] || null),
      });
    }
    return p;
  }

  const API = { DIAS_ATRAS, DIAS_MARCAR_FABRICA, hoyServidor, sumar, seleccionables, permiteMarcar, diasMarcar, rotuloCorto, rotuloLargo,
    igualMarca, igualAjuste, estado, mismaLibre, plan };
  if (typeof module !== 'undefined' && module.exports) module.exports = API;
  else global.DiasDieta = API;
})(typeof window !== 'undefined' ? window : globalThis);
