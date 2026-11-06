/* =============================================================
   codigo-barras.js — el código de barras de «Agregar alimento» (app 2.1.0).
   Port de MyPumpReglas/CodigoBarras.swift (y de su gemelo de Android): el
   número leído, la respuesta de Open Food Facts (API v2, pública y sin clave)
   llevada a un alimento por 100 g y la caché por código. Puro salvo `buscar`.
   Lo verifican los vectores de apps/shared/vectores/barras_off.json.
   ============================================================= */
(function () {
  'use strict';

  const CAMPOS = 'product_name,product_name_es,brands,nutriments,serving_size,serving_quantity,serving_quantity_unit,quantity';
  const ESPERA_MS = 8000;
  const LARGO_NOMBRE = 80;
  const MAX_MACROS = 110, MAX_KCAL = 950;

  // Math.round de JS: lo que usa la app como jsRound.
  const jsRound = (x) => Math.round(x);
  const r1 = (x) => jsRound(x * 10) / 10;

  function digitoControl(sinControl) {
    let suma = 0;
    const d = sinControl.split('').reverse();
    for (let i = 0; i < d.length; i++) suma += Number(d[i]) * (i % 2 === 0 ? 3 : 1);
    return (10 - suma % 10) % 10;
  }
  function controlValido(c) {
    const ultimo = Number(c[c.length - 1]);
    return !isNaN(ultimo) && digitoControl(c.slice(0, -1)) === ultimo;
  }
  function expandirUPCE(c) {
    if (c.length !== 8 || (c[0] !== '0' && c[0] !== '1')) return null;
    const m = c.slice(1, 7), u = c[6];
    let cuerpo;
    if (u === '0' || u === '1' || u === '2') cuerpo = m.slice(0, 2) + u + '0000' + m.slice(2, 5);
    else if (u === '3') cuerpo = m.slice(0, 3) + '00000' + m.slice(3, 5);
    else if (u === '4') cuerpo = m.slice(0, 4) + '00000' + m.slice(4, 5);
    else cuerpo = m.slice(0, 5) + '0000' + u;
    const a = c[0] + cuerpo + c[7];
    return controlValido(a) ? a : null;
  }

  /* El código como se le pregunta a Open Food Facts, o null si no es un
     EAN/UPC válido. EAN-13 y EAN-8 quedan igual; UPC-A (12) lleva un 0
     adelante; UPC-E se expande. */
  function normalizar(texto, upcE) {
    const t = String(texto == null ? '' : texto).trim();
    if (!t || !/^[0-9]+$/.test(t)) return null;
    if (upcE) {
      if (t.length !== 8) return null;
      const a = expandirUPCE(t);
      return a ? '0' + a : null;
    }
    if (t.length === 13 || t.length === 8) return controlValido(t) ? t : null;
    if (t.length === 12) return controlValido(t) ? '0' + t : null;
    return null;
  }

  // Texto de Open Food Facts saneado: sin etiquetas, controles y espacios
  // Unicode como separadores, sin espacios de más.
  function limpio(v) {
    if (typeof v !== 'string') return '';
    const s = v.replace(/<[/!]?[A-Za-z][^<>]*>/g, ' ');
    return s.replace(/[\p{Cc}\p{Zs}\p{Zl}\p{Zp}]/gu, ' ').split(' ').filter(Boolean).join(' ');
  }
  function leerNumero(s) {
    const t = String(s).trim().replace(/,/g, '.');
    if (!t) return null;
    // Double(String) de Swift: decimal o exponente; nada de "0x", espacios internos ni vacío.
    if (!/^[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?$/.test(t)) return null;
    const v = Number(t);
    return isFinite(v) ? v : null;
  }
  function numero(v) {
    let x = null;
    if (typeof v === 'number') x = v;
    else if (typeof v === 'string') x = leerNumero(v);
    if (x == null || !isFinite(x) || x < 0) return null;
    return x;
  }
  function normalizarTexto(s) {
    return String(s || '').toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '').trim();
  }

  const LETRAS = new Set('abcdefghijklmnopqrstuvwxyzáéíóúüñ'.split(''));
  const NO_ES_MEDIDA = new Set(['portion', 'portions', 'serving', 'servings', 'porcion', 'porción', 'porciones',
    'unit', 'g', 'gr', 'grs', 'gramo', 'gramos', 'ml', 'cc', 'oz', 'kg', 'l', 'lt']);
  function nombreMedida(s) {
    const t = Array.from(String(s == null ? '' : s).trim().toLowerCase());
    if (t.length < 3 || t[0] !== '1' || (t[1] !== ' ' && t[1] !== '\t')) return 'porción';
    let i = 1;
    while (i < t.length && (t[i] === ' ' || t[i] === '\t')) i++;
    let j = i;
    while (j < t.length && LETRAS.has(t[j])) j++;
    const w = t.slice(i, j).join('');
    if (!w || NO_ES_MEDIDA.has(w) || w.length > 20) return 'porción';
    return w;
  }

  // AlimentoPropioNuevo.preparar con unidad «g»: null si no se puede.
  function preparar(nombre, kcal, p0, c0, f0) {
    const num = (x) => (x != null && isFinite(x) && x > 0) ? x : 0;
    const p = num(p0), c = num(c0), f = num(f0);
    const k = (kcal != null && isFinite(kcal) && kcal > 0) ? kcal : jsRound(p * 4 + c * 4 + f * 9);
    if (!String(nombre).trim()) return null;
    if (k <= 0 && p <= 0 && c <= 0 && f <= 0) return null;
    const d = { kcal: jsRound(k), p: r1(p), c: r1(c), g: r1(f) };
    if (d.kcal > MAX_KCAL || d.p + d.c + d.g > MAX_MACROS) return null;
    return d;
  }

  /* La respuesta de /api/v2/product/<código>.json →
     { estado: 'encontrado', producto } | { estado: 'incompleto', parcial } | { estado: 'noEncontrado' }. */
  function leer(j, codigo) {
    const p = j && j.status === 1 && j.product && typeof j.product === 'object' && !Array.isArray(j.product) ? j.product : null;
    if (!p) return { estado: 'noEncontrado' };
    let nombre = limpio(p.product_name_es);
    if (!nombre) nombre = limpio(p.product_name);
    const marca = limpio(p.brands).split(',').map(x => x.trim()).find(x => x) || '';
    if (nombre) {
      nombre = nombre[0].toUpperCase() + nombre.slice(1);
      if (marca && !normalizarTexto(nombre).includes(normalizarTexto(marca))) nombre += ` (${marca})`;
      nombre = Array.from(nombre).slice(0, LARGO_NOMBRE).join('').trim();
    }
    const n = p.nutriments && typeof p.nutriments === 'object' ? p.nutriments : {};
    const prot = numero(n.proteins_100g), carb = numero(n.carbohydrates_100g), grasa = numero(n.fat_100g);
    const kcalDecl = numero(n['energy-kcal_100g']);
    const kj = numero(n['energy-kj_100g']) ?? numero(n.energy_100g);
    const kcalDeKj = kj != null ? kj / 4.184 : null;
    const atwater = (prot != null && carb != null && grasa != null) ? 4 * prot + 4 * carb + 9 * grasa : null;
    let kcal;
    if (kcalDecl != null && kcalDeKj != null) {
      if (Math.abs(kcalDecl - kcalDeKj) > 0.1 * Math.max(kcalDecl, kcalDeKj) && atwater != null) {
        kcal = Math.abs(kcalDecl - atwater) <= Math.abs(kcalDeKj - atwater) ? kcalDecl : kcalDeKj;
      } else kcal = kcalDecl;
    } else kcal = kcalDecl != null ? kcalDecl : kcalDeKj;

    const parcial = (motivo) => {
      const r = { codigo, motivo };
      if (nombre) r.nombre = nombre;
      if (kcal != null) r.kcal = jsRound(kcal);
      if (prot != null) r.p = r1(prot);
      if (carb != null) r.c = r1(carb);
      if (grasa != null) r.g = r1(grasa);
      return { estado: 'incompleto', parcial: r };
    };
    if (!nombre) return parcial('sinNombre');
    if (prot == null || carb == null || grasa == null || atwater == null) return parcial('faltanDatos');
    if (kcal != null && !(0.6 * atwater - 25 <= kcal && kcal <= 1.4 * atwater + 40)) return parcial('noCierran');
    let por100;
    if (prot === 0 && carb === 0 && grasa === 0 && (kcal != null ? jsRound(kcal) : 0) === 0) {
      if (kcal == null) return parcial('enCero');
      por100 = { kcal: 0, p: 0, c: 0, g: 0 };
    } else {
      const d = preparar(nombre, kcal, prot, carb, grasa);
      if (!d) return parcial('noCierran');
      por100 = d;
    }
    const producto = { codigo, nombre, por100, medida: null, gramosMedida: null };
    const unidad = limpio(p.serving_quantity_unit).toLowerCase();
    const sq = numero(p.serving_quantity);
    if (sq != null && sq >= 1 && sq <= 1000 && jsRound(sq) !== 100 && (!unidad || unidad === 'g')) {
      producto.medida = nombreMedida(typeof p.serving_size === 'string' ? p.serving_size : (p.serving_size == null ? null : String(p.serving_size)));
      producto.gramosMedida = r1(sq);
    }
    return { estado: 'encontrado', producto };
  }

  const TEXTO_PARCIAL = {
    sinNombre: 'Open Food Facts tiene este producto, pero le faltan datos de la etiqueta.',
    faltanDatos: 'Open Food Facts tiene este producto, pero le faltan datos de la etiqueta.',
    noCierran: 'Open Food Facts tiene este producto, pero sus valores no cierran.',
    enCero: 'Open Food Facts tiene este producto con todo en cero y sin calorías: revisá la etiqueta y cargalo.',
  };

  /* Caché por código en el navegador: encontrado 30 días; no encontrado o
     incompleto, un día. Hasta 300 entradas. */
  const CLAVE_CACHE = 'mypump_barras_v1', DIA = 86400000, MAXIMO = 300;
  function cacheLeer() { try { return JSON.parse(localStorage.getItem(CLAVE_CACHE) || '{}') || {}; } catch (_) { return {}; } }
  function vigente(codigo, ahora) {
    const e = cacheLeer()[codigo];
    if (!e || !e.lectura) return null;
    const vida = e.lectura.estado === 'encontrado' ? 30 * DIA : DIA;
    const edad = ahora - e.ms;
    return edad >= 0 && edad < vida ? e.lectura : null;
  }
  function cacheGuardar(codigo, lectura, ahora) {
    try {
      const c = cacheLeer();
      c[codigo] = { lectura, ms: ahora };
      const claves = Object.keys(c);
      if (claves.length > MAXIMO) {
        claves.sort((a, b) => c[a].ms - c[b].ms).slice(0, claves.length - MAXIMO).forEach(k => delete c[k]);
      }
      localStorage.setItem(CLAVE_CACHE, JSON.stringify(c));
    } catch (_) {}
  }

  /* Busca en Open Food Facts (con caché). Sin red o con error del servidor:
     { estado: 'sinRed' } y no se guarda nada. */
  async function buscar(codigo) {
    const ahora = Date.now();
    const c = vigente(codigo, ahora);
    if (c) return c;
    const ctl = typeof AbortController !== 'undefined' ? new AbortController() : null;
    const timer = ctl ? setTimeout(() => ctl.abort(), ESPERA_MS) : null;
    try {
      const r = await fetch(`https://world.openfoodfacts.org/api/v2/product/${codigo}.json?fields=${CAMPOS}`,
        { signal: ctl ? ctl.signal : undefined, headers: { Accept: 'application/json' } });
      if (r.status === 404) { const l = { estado: 'noEncontrado' }; cacheGuardar(codigo, l, ahora); return l; }
      if (!r.ok) return { estado: 'sinRed' };
      const l = leer(await r.json(), codigo);
      cacheGuardar(codigo, l, ahora);
      return l;
    } catch (_) {
      return { estado: 'sinRed' };
    } finally {
      if (timer) clearTimeout(timer);
    }
  }

  // Para la hoja de cantidad: el candidato de AjustesDieta (origen «barras»).
  function candidato(prod) {
    const c = { nombre: prod.nombre, por100: prod.por100, origen: 'barras', codigo: prod.codigo };
    if (prod.medida && prod.gramosMedida) { c.unidad = prod.medida; c.gramosPorUnidad = prod.gramosMedida; }
    return c;
  }

  window.CodigoBarras = { normalizar, leer, buscar, candidato, nombreMedida, TEXTO_PARCIAL };
})();
