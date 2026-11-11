/* =============================================================
   compras-ui.js — «Dónde comprarlo» en la web (palanca `compras_pais`): el botón de cada suplemento, el renglón de ayuda
   y la hoja con las tiendas. Las reglas están en js/compras.js; la pestaña Suplementación (cliente.html) pide las piezas.

   Lo que llega del servidor (producto, tienda, nota, url) nunca se mete como HTML: se arma con textContent. La tienda
   se abre en otra pestaña con rel="noopener noreferrer", y solo si la url es https.
   ============================================================= */
(function (raiz) {
  'use strict';
  const C = raiz.Compras;
  const T = C.T;

  const ui = { op: null, modelo: null };
  const e = (s) => String(s == null ? '' : s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const IC = {
    bolsa: '<svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M6 8h12l1 12H5L6 8z"/><path d="M9 8V6a3 3 0 0 1 6 0v2"/></svg>',
    fuera: '<svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M14 5h5v5"/><path d="M19 5l-8 8"/><path d="M18 14v4a1 1 0 0 1-1 1H6a1 1 0 0 1-1-1V7a1 1 0 0 1 1-1h4"/></svg>',
  };

  const compras = () => (ui.modelo ? ui.modelo.compras : null);
  const el = (tag, cls, txt) => { const x = document.createElement(tag); if (cls) x.className = cls; if (txt != null) x.textContent = txt; return x; };

  /** Por cada ítem de la pestaña, sus opciones o null (ver Compras.cruzar). */
  function cruzar(itemsSupl) { return C.cruzar(compras(), itemsSupl); }

  /** El botón grande de un ítem. `indice` es el del ítem en la pestaña. */
  function botonHtml(indice) {
    return `<button type="button" class="compras-btn" id="compras-abrir-${indice}" data-compras="${indice}">${IC.bolsa}<span>${e(T.boton)}</span></button>`;
  }
  const ayudaHtml = () => `<p class="compras-ayuda" id="compras-ayuda">${e(T.ayuda)}</p>`;

  function cerrar() {
    const h = ui.op && ui.op.host();
    const b = h && h.querySelector('#comprasBack');
    if (b) b.remove();
  }

  /** La hoja de un suplemento: una tarjeta por opción y, si hay url, el botón que abre la tienda. */
  function abrir(nombre, opciones) {
    const h = ui.op && ui.op.host();
    if (!h || !opciones || !opciones.length) return;
    h.textContent = '';
    const back = el('div', 'modal-back'); back.id = 'comprasBack';
    const hoja = el('div', 'modal-sheet cb-hoja compras-hoja'); hoja.id = 'compras-hoja';
    hoja.setAttribute('role', 'dialog'); hoja.setAttribute('aria-modal', 'true'); hoja.setAttribute('aria-labelledby', 'comprasTit');
    const cab = el('div', 'cb-hoja-cab');
    const x = el('button', 'cb-cerrar', T.cerrar); x.type = 'button'; x.id = 'compras-cerrar';
    cab.append(x);
    const cuerpo = el('div', 'cb-hoja-cuerpo');
    const tit = el('div', 'compras-tit');
    const h2 = el('h2', 'cb-hoja-tit', nombre); h2.id = 'comprasTit';
    tit.append(h2, el('p', 'compras-sub', T.subtitulo));
    cuerpo.append(tit);
    opciones.forEach((o, i) => {
      const t = el('div', 'compras-op');
      t.append(el('div', 'compras-producto', o.producto), el('div', 'compras-tienda', o.tienda));
      if (o.nota) t.append(el('div', 'compras-nota', o.nota));
      const url = C.urlSegura(o.url);
      if (url) {
        const a = el('a', 'btn-primary cb-btn compras-ir');
        a.id = `compras-tienda-${i}`;
        a.href = url; a.target = '_blank'; a.rel = 'noopener noreferrer';
        a.insertAdjacentHTML('afterbegin', IC.fuera);
        a.append(el('span', null, T.abrirTienda));
        t.append(a);
      }
      cuerpo.append(t);
    });
    cuerpo.append(el('p', 'compras-pie', T.pie));
    hoja.append(cab, cuerpo);
    back.append(hoja);
    back.addEventListener('click', (ev) => { if (ev.target === back || ev.target.closest('#compras-cerrar')) cerrar(); });
    back.addEventListener('keydown', (ev) => { if (ev.key === 'Escape') cerrar(); });
    h.append(back);
    try { x.focus({ preventScroll: true }); } catch (_) {}
  }

  /* op: { token, rpc, host() → #modalHost } */
  function configurar(op) { ui.op = op; }

  /** cfg: la respuesta de `mypump_get_app_config`, o null si no se pudo preguntar. → true si quedó prendida. */
  function aplicarConfig(cfg) {
    if (!ui.op || !C) return false;
    if (!ui.modelo) {
      const almacen = { leer: (k) => localStorage.getItem(k), guardar: (k, v) => localStorage.setItem(k, v), borrar: (k) => localStorage.removeItem(k) };
      ui.modelo = C.crearModelo({ token: ui.op.token, rpc: ui.op.rpc, almacen });
    }
    return ui.modelo.aplicarConfig(cfg);
  }
  /** Con la suplementación recién cargada. Apagada no llama. */
  function refrescar(haySuplementacion) {
    return ui.modelo ? ui.modelo.refrescar(haySuplementacion).catch(() => {}) : Promise.resolve();
  }

  raiz.ComprasUI = { T, configurar, aplicarConfig, refrescar, cruzar, botonHtml, ayudaHtml, abrir, cerrar,
    prendida: () => !!(ui.modelo && ui.modelo.prendida) };
})(window);
