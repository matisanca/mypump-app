/* =============================================================
   lista-previa.js — «Antes de la videollamada» (web = app 2.3.0), detrás de la palanca
   `lista_previa`.

   Solo lee `mypump_lista_previa` con el token: lo que conviene tener listo antes de la
   videollamada de comienzo. No abre ni cierra nada. La regla y los textos son los de las
   apps (apps/shared/vectores/lista_previa.json, copia en scripts/fixtures/lista_previa.json),
   que corre scripts/test-lista-previa.mjs.

   Apagada, sin la función del servidor (PGRST202) o sin red: no se muestra nada.
   ============================================================= */
(function (raiz) {
  'use strict';

  const TITULOS = {
    guia: 'Mirar los videos de tu guía',
    dudas: 'Dejarle tus dudas a Mati',
    formulario: 'Responder las preguntas de Mati',
    fotos: 'Subir tus fotos de inicio',
    estudios: 'Subir tus estudios',
    contrato: 'Firmar el contrato',
  };
  // guia = la guía de videos; fotos = las fotos de Revisión. Sin destino, la fila no es un botón.
  const DESTINOS = { guia: 'guia', dudas: 'guia', fotos: 'fotos' };
  const TEXTOS = {
    titulo: 'Antes de la videollamada',
    todo_listo: 'Ya tenés todo listo',
    consejo: 'Ese día buscá un lugar tranquilo y con buena conexión.',
    opcional: 'Opcional',
    hecho: 'Hecho',
    falta: 'Falta',
  };
  const CADA_MS = 60000;   // como mucho un pedido por minuto
  const FLAG = 'mypump-palanca-lista-previa';

  /** Lo que devuelve `mypump_lista_previa` → lo que se muestra; null = nada. El orden es el del servidor. */
  function lista(j) {
    if (!j || typeof j !== 'object' || Array.isArray(j) || j.ok !== true || j.activa !== true || !Array.isArray(j.items)) return null;
    const items = [], vistas = new Set();
    for (const it of j.items) {
      if (!it || typeof it !== 'object' || Array.isArray(it)) continue;
      const clave = it.clave, estado = it.estado;
      if (typeof clave !== 'string' || !Object.prototype.hasOwnProperty.call(TITULOS, clave) || (estado !== 'hecho' && estado !== 'falta') || vistas.has(clave)) continue;
      vistas.add(clave);
      const hecho = estado === 'hecho', opcional = it.opcional === true;
      const faltan = it.faltan;
      let detalle = null;
      if (!hecho && clave === 'guia' && typeof faltan === 'number' && Number.isInteger(faltan) && faltan >= 1) {
        detalle = faltan === 1 ? 'Te falta 1 video' : `Te faltan ${faltan} videos`;
      } else if (!hecho && opcional) {
        detalle = TEXTOS.opcional;
      }
      const accesible = [TITULOS[clave], hecho ? TEXTOS.hecho : (opcional ? detalle : TEXTOS.falta), detalle && !opcional ? detalle : null].filter(Boolean).join(', ');
      // A dónde lleva tocar un punto que falta (un toque, directo al lugar). Lo hecho no se toca.
      const destino = hecho ? null : (DESTINOS[clave] || null);
      items.push({ clave, titulo: TITULOS[clave], hecho, opcional, detalle, destino, accesible });
    }
    if (!items.length) return null;
    const obligatorios = items.filter((i) => !i.opcional);
    const hechos = obligatorios.filter((i) => i.hecho).length;
    const todo = obligatorios.length > 0 && hechos === obligatorios.length;
    const resumen = !obligatorios.length ? null : todo ? TEXTOS.todo_listo : `Llevás ${hechos} de ${obligatorios.length}`;
    return { items, resumen, todo_listo: todo };
  }

  function esc(s) {
    return String(s == null ? '' : s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  }
  const TILDE = '<svg viewBox="0 0 24 24" aria-hidden="true" focusable="false"><circle cx="12" cy="12" r="11" fill="currentColor"/><path d="M7 12.4l3.2 3.2L17 8.8" fill="none" stroke="#fff" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round"/></svg>';
  const VACIO = '<svg viewBox="0 0 24 24" aria-hidden="true" focusable="false"><circle cx="12" cy="12" r="10" fill="none" stroke="currentColor" stroke-width="2"/></svg>';
  const FLECHA = '<svg class="lp-flecha" viewBox="0 0 24 24" aria-hidden="true" focusable="false"><path d="M9 6l6 6-6 6" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round"/></svg>';

  /** La lista, siempre desplegada. `enTarjeta`: va dentro de la tarjeta de la videollamada (sin caja propia). */
  function html(salida, opciones) {
    if (!salida || !Array.isArray(salida.items) || !salida.items.length) return '';
    const dentro = !!(opciones && opciones.enTarjeta);
    const filas = salida.items.map((i) => {
      const adentro = `<span class="lp-circulo${i.hecho ? ' is-hecho' : ''}">${i.hecho ? TILDE : VACIO}</span>
          <span class="lp-txt"><span class="lp-tit">${esc(i.titulo)}</span>${i.detalle ? `<span class="lp-det">${esc(i.detalle)}</span>` : ''}</span>`;
      return i.destino
        ? `<li><button type="button" class="lp-fila lp-boton" data-lp-destino="${esc(i.destino)}" data-test="lista-previa-${esc(i.clave)}" aria-label="${esc(i.accesible)}">${adentro}${FLECHA}</button></li>`
        : `<li><div class="lp-fila${i.hecho ? ' is-hecha' : ''}" data-test="lista-previa-${esc(i.clave)}" role="group" aria-label="${esc(i.accesible)}">${adentro}</div></li>`;
    }).join('');
    return `<section class="lp-lista${dentro ? ' lp-dentro' : ' lp-sola'}" aria-label="${esc(TEXTOS.titulo)}" data-test="lista-previa">
      <div class="lp-cab"><h3 class="lp-titulo">${esc(TEXTOS.titulo)}</h3>${
        salida.resumen ? `<span class="lp-resumen${salida.todo_listo ? ' is-listo' : ''}" data-test="lista-previa-resumen">${esc(salida.resumen)}</span>` : ''}</div>
      <ul class="lp-items">${filas}</ul>
      <p class="lp-consejo">${esc(TEXTOS.consejo)}</p>
    </section>`;
  }

  // ───────────────────────── El modelo ─────────────────────────
  const ui = { op: null, prendida: false, salida: null, ultimo: 0, enVuelo: null, luego: null };
  const ahora = () => (ui.op && ui.op.ahora ? ui.op.ahora() : Date.now());

  /** op: { token, rpc(fn, params), alCambiar(), ahora?() } */
  function configurar(op) {
    if (ui.luego) clearTimeout(ui.luego);
    ui.op = op; ui.prendida = false; ui.salida = null; ui.ultimo = 0; ui.enVuelo = null; ui.luego = null;
  }
  function poner(salida) {
    const cambio = JSON.stringify(salida) !== JSON.stringify(ui.salida);
    ui.salida = salida;
    if (cambio && ui.op && ui.op.alCambiar) { try { ui.op.alCambiar(); } catch (_) {} }
  }

  /** Pide la lista. Si ya se pidió hace menos de un minuto, queda un solo pedido para cuando se cumpla. */
  function refrescar() {
    if (!ui.op || !ui.prendida) return Promise.resolve();
    if (ui.enVuelo) return ui.enVuelo;
    const falta = ui.ultimo ? CADA_MS - (ahora() - ui.ultimo) : 0;
    if (falta > 0) {
      if (!ui.luego && typeof setTimeout === 'function') {
        const op = ui.op;
        ui.luego = setTimeout(() => { ui.luego = null; if (ui.op === op) refrescar(); }, falta);
        if (ui.luego && ui.luego.unref) ui.luego.unref();
      }
      return Promise.resolve();
    }
    const op = ui.op;
    ui.ultimo = ahora();
    ui.enVuelo = (async () => {
      let r;
      try { r = await op.rpc('mypump_lista_previa', { p_token: op.token }); } catch (_) { r = null; }
      if (ui.op !== op || !ui.prendida) return;
      // Sin red, sin la función o con una respuesta que no se entiende: nada.
      poner(r && r.ok ? lista(r.data) : null);
    })().finally(() => { ui.enVuelo = null; });
    return ui.enVuelo;
  }

  /** valor: true/false leído de mypump_get_app_config; null = no se pudo leer: vale lo último que se supo. */
  async function aplicarPalanca(valor) {
    if (!ui.op) return;
    let prendida;
    try {
      if (valor === null || valor === undefined) prendida = localStorage.getItem(FLAG) === '1';
      else {
        prendida = valor === true;
        if (prendida) localStorage.setItem(FLAG, '1'); else localStorage.removeItem(FLAG);
      }
    } catch (_) { prendida = valor === true; }
    ui.prendida = prendida;
    if (!prendida) { if (ui.luego) { clearTimeout(ui.luego); ui.luego = null; } poner(null); return; }
    await refrescar();
  }

  const api = {
    TITULOS, DESTINOS, TEXTOS, CADA_MS,
    lista, html, configurar, aplicarPalanca, refrescar,
    get salida() { return ui.salida; },
    get prendida() { return ui.prendida; },
    _reiniciar() { configurar(null); },
  };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  else raiz.ListaPrevia = api;
})(typeof window !== 'undefined' ? window : globalThis);
