/* =============================================================
   demo-historial.js — la demo sin cuenta («Ver demo») con ocho semanas de historia.

   Lee public/demo/historial.json (copia idéntica de apps/shared/demo/historial.json: no
   editarla a mano) y lo pasa a las formas que ya usa la web: el historial por ejercicio,
   el peso y los pasos de Salud, las metas, el chat, la Devolución de Mati y la lista
   previa. Los `dia` son relativos a hoy (0 = hoy): acá se vuelven fechas locales.

   Sin red (el archivo viaja con la app y entra en la caché del service worker) y sin
   escribir nada. Son datos inventados: solo se usan en la demo, nunca con una cuenta.
   ============================================================= */
(function (raiz) {
  'use strict';

  const RUTA = '/demo/historial.json';
  const dos = (n) => String(n).padStart(2, '0');
  const esObjeto = (x) => !!x && typeof x === 'object' && !Array.isArray(x);
  const entero = (x) => typeof x === 'number' && Number.isInteger(x);
  const numero = (x) => typeof x === 'number' && Number.isFinite(x);
  const esHora = (x) => typeof x === 'string' && /^([01]\d|2[0-3]):[0-5]\d$/.test(x);
  const texto = (x) => typeof x === 'string' && x.trim().length > 0;

  /** Los problemas de forma del archivo ([] = sirve). */
  function problemas(j) {
    const p = [];
    if (!esObjeto(j)) return ['no es un objeto'];
    if (j.version !== 1) p.push('version distinta de 1');
    if (!Array.isArray(j.entreno) || !j.entreno.length) p.push('entreno vacío');
    else j.entreno.forEach((e, i) => {
      if (!esObjeto(e) || !texto(e.ejercicio_id) || !texto(e.nombre) || !Array.isArray(e.sesiones) || !e.sesiones.length) return p.push(`entreno[${i}] mal formado`);
      e.sesiones.forEach((s, k) => {
        if (!esObjeto(s) || !entero(s.dia) || s.dia >= 0 || !esHora(s.hora) || !Array.isArray(s.series) || !s.series.length
          || !s.series.every((x) => esObjeto(x) && numero(x.kg) && x.kg > 0 && entero(x.reps) && x.reps >= 1)) p.push(`entreno[${i}].sesiones[${k}] mal formada`);
      });
    });
    if (!Array.isArray(j.peso) || !j.peso.length || !j.peso.every((x) => esObjeto(x) && entero(x.dia) && x.dia <= 0 && numero(x.kg) && x.kg > 0)) p.push('peso mal formado');
    if (!Array.isArray(j.pasos) || !j.pasos.length || !j.pasos.every((x) => esObjeto(x) && entero(x.dia) && x.dia <= 0 && entero(x.pasos) && x.pasos >= 0)) p.push('pasos mal formado');
    if (!esObjeto(j.metas) || !entero(j.metas.meta_pasos_dia) || !numero(j.metas.ritmo_peso_kg_semana)) p.push('metas mal formado');
    if (!Array.isArray(j.chat) || !j.chat.length || !j.chat.every((x) => esObjeto(x) && entero(x.dia) && x.dia <= 0 && esHora(x.hora) && (x.autor === 'coach' || x.autor === 'cliente') && texto(x.texto))) p.push('chat mal formado');
    if (!Array.isArray(j.devoluciones) || !j.devoluciones.length || !j.devoluciones.every((x) => esObjeto(x) && entero(x.semanas_atras) && x.semanas_atras >= 1 && texto(x.texto))) p.push('devoluciones mal formado');
    if (!esObjeto(j.lista_previa) || j.lista_previa.ok !== true || !Array.isArray(j.lista_previa.items)) p.push('lista_previa mal formada');
    return p;
  }

  function hoyLocal() { const d = new Date(); return `${d.getFullYear()}-${dos(d.getMonth() + 1)}-${dos(d.getDate())}`; }
  // Una fecha local a `dia` días de hoy, a tal hora. El constructor de Date acomoda solo el cambio de mes.
  function instante(hoy, dia, hora, masMin) {
    const [a, m, d] = hoy.split('-').map(Number);
    const [h, mi] = (hora || '12:00').split(':').map(Number);
    return new Date(a, m - 1, d + dia, h, mi + (masMin || 0), 0, 0);
  }
  function fecha(hoy, dia) { const f = instante(hoy, dia, '12:00'); return `${f.getFullYear()}-${dos(f.getMonth() + 1)}-${dos(f.getDate())}`; }
  function claveDefecto(nombre) {
    return String(nombre || '').toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '').replace(/\(.*?\)/g, ' ').replace(/[^a-z0-9 ]+/g, ' ').replace(/\s+/g, ' ').trim();
  }

  /** j: el historial; hoy: 'YYYY-MM-DD' local; clave: la función de clave de ejercicio de la web. null si el archivo no sirve. */
  function armar(j, hoy, clave) {
    if (problemas(j).length) return null;
    const h = /^\d{4}-\d{2}-\d{2}$/.test(String(hoy)) ? hoy : hoyLocal();
    const k = typeof clave === 'function' ? clave : claveDefecto;

    // El historial por ejercicio: una fila por serie, de la más nueva a la más vieja (como la RPC).
    const historico = {};
    for (const e of j.entreno) {
      const c = k(e.nombre);
      const filas = [];
      for (const s of e.sesiones) {
        s.series.forEach((x, i) => filas.push({
          clave: c, ejercicio_id: e.ejercicio_id, ejercicio_nombre: e.nombre, serie_numero: i + 1,
          peso_kg: x.kg, reps_realizadas: x.reps, rir_real: null, notas: null,
          registrado_en: instante(h, s.dia, s.hora, 3 * i).toISOString(),
        }));
      }
      filas.sort((a, b) => (a.registrado_en < b.registrado_en ? 1 : a.registrado_en > b.registrado_en ? -1 : 0));
      historico[c] = (historico[c] || []).concat(filas);
    }

    const salud = [];
    for (const x of j.peso) salud.push({ fecha: fecha(h, x.dia), tipo: 'peso_kg', valor: x.kg, fuente: 'manual' });
    for (const x of j.pasos) salud.push({ fecha: fecha(h, x.dia), tipo: 'pasos', valor: x.pasos, fuente: 'manual' });

    const chat = j.chat.map((x, i) => ({
      id: `demo-chat-${i}`, autor: x.autor, contenido: x.texto, leido_por_cliente: true,
      created_at: instante(h, x.dia, x.hora).toISOString(),
    })).sort((a, b) => (a.created_at < b.created_at ? -1 : a.created_at > b.created_at ? 1 : 0));

    // semanas_atras: 1 = el lunes de la semana pasada.
    const base = instante(h, 0, '12:00');
    const hastaLunes = (base.getDay() + 6) % 7;
    const devoluciones = {
      habilitado: true,
      devoluciones: j.devoluciones.map((x, i) => ({ id: `demo-dev-${i}`, semana_lunes: fecha(h, -hastaLunes - 7 * x.semanas_atras), texto: x.texto })),
    };

    return {
      hoy: h, historico, salud, chat, devoluciones,
      metas: { meta_pasos_dia: j.metas.meta_pasos_dia, ritmo_peso_kg_semana: j.metas.ritmo_peso_kg_semana },
      listaPrevia: j.lista_previa,
    };
  }

  /** Trae el archivo (mismo origen; sin red sale de la caché del service worker). null si falta o no sirve. */
  async function cargar(hoy, clave) {
    try {
      const r = await fetch(RUTA, { credentials: 'omit' });
      if (!r.ok) return null;
      return armar(await r.json(), hoy, clave);
    } catch (_) { return null; }
  }

  const api = { RUTA, problemas, armar, cargar, fecha };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  else raiz.DemoHistorial = api;
})(typeof window !== 'undefined' ? window : globalThis);
