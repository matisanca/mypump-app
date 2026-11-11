/* =============================================================
   recorrido-ui.js — «Tu recorrido» en la web (palanca `fin_plan`): la tarjeta arriba de Entreno, la entrada en Mis datos
   y la hoja. Las reglas y los textos están en js/recorrido.js. Apagada no se llama a nada ni se ve nada.

   Fácil y bien visible: tarjeta arriba de todo, un botón grande con texto, la hoja a un toque. Todo lo que llega del
   servidor (el resumen de Mati) pasa por el escapado: nunca se mete como HTML.
   ============================================================= */
(function (raiz) {
  'use strict';
  const R = raiz.Recorrido;
  const T = R.T;
  const SEG_ENTRE_REFRESCOS = 60;

  const ui = { op: null, modelo: null, firma: null, solaPedida: false, ultimoRefresco: 0, enganchado: false };

  const e = (s) => String(s == null ? '' : s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const IC = {
    camino: '<svg viewBox="0 0 24 24" width="24" height="24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M4 20l5-9 4 5 3-6 4 10"/><path d="M14 5h5v3h-5z"/><path d="M14 4v7"/></svg>',
    ok: '<svg viewBox="0 0 24 24" width="28" height="28" aria-hidden="true"><circle cx="12" cy="12" r="11" fill="currentColor"/><path d="m7 12.5 3.3 3.3L17 9" fill="none" stroke="var(--color-on-brand)" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"/></svg>',
  };

  const estado = () => (ui.modelo ? ui.modelo.estado : null);
  const host = () => (ui.op ? ui.op.host() : null);
  const hoja = () => { const h = host(); return h ? h.querySelector('#recBack') : null; };

  // ── La tarjeta arriba de Entreno ──
  /* renderTrain rehace la escena: se vuelve a poner, siempre primera. */
  function montarTarjeta(root) {
    let caja = document.getElementById('recHost');
    const s = estado();
    if (!root || !s) { if (caja) caja.remove(); return; }
    if (!caja) {
      caja = document.createElement('div');
      caja.id = 'recHost';
      caja.addEventListener('click', (ev) => { if (ev.target.closest('#recorrido-abrir')) abrirHoja(); });
    }
    const html = `<section class="rec-tarjeta" id="recorrido-tarjeta" aria-labelledby="recTarjetaTit">
      <div class="rec-tarjeta-cab"><span class="rec-ic">${IC.camino}</span>
        <div class="rec-tarjeta-txt"><h2 id="recTarjetaTit">${e(T.tarjetaTitulo)}</h2><p>${e(R.textoTarjeta(s.estado))}</p></div></div>
      <button type="button" class="btn-primary cb-btn" id="recorrido-abrir">${e(T.botonVer)}</button></section>`;
    if (caja.dataset.h !== html) { caja.innerHTML = html; caja.dataset.h = html; }
    if (root.firstChild !== caja) root.insertBefore(caja, root.firstChild);
  }

  // ── La hoja ──
  /* Los controles de salud (palanca `controles_app`, desde js/estudios-ui.js) como hitos con fecha. Nada si no hay. */
  function controlesHtml() {
    const C = raiz.Controles, l = raiz.EstudiosUI && raiz.EstudiosUI.hitosControl ? raiz.EstudiosUI.hitosControl() : [];
    if (!C || !l.length) return '';
    const ic = (proximo) => `<span class="ctl-hito-ic" aria-hidden="true"><svg viewBox="0 0 24 24" width="22" height="22" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">${proximo
      ? '<rect x="3" y="5" width="18" height="16" rx="3"/><path d="M3 10h18M8 3v4M16 3v4"/>' : '<circle cx="12" cy="12" r="9"/><path d="m8 12 3 3 5-6"/>'}</svg></span>`;
    return `<section class="ctl-hitos" id="recorrido-controles" aria-labelledby="ctlHitosTit"><h3 id="ctlHitosTit">${e(C.T.hitosTitulo)}</h3>
      ${l.map((h, i) => `<div class="ctl-hito" id="recorrido-control-${i}">${ic(h.estado === C.T.hitoProximo)}
        <div class="ctl-hito-txt"><strong>${e(h.titulo)}</strong><span>${e(h.cuando)}</span><em>${e(h.estado)}</em></div></div>`).join('')}</section>`;
  }

  function logrosHtml(s) {
    return `<div class="rec-logros">${s.logros.map((l, i) => `<div class="rec-logro" id="recorrido-logro-${i}">
      <div class="rec-logro-valor">${e(l.valor)}</div><div class="rec-logro-tit">${e(l.titulo)}</div>
      ${l.detalle ? `<div class="rec-logro-det">${e(l.detalle)}</div>` : ''}</div>`).join('')}</div>`;
  }
  function preguntasHtml() {
    const t = ui.modelo.textos;
    return `<div class="rec-antes"><h3 class="rec-h3">${e(T.antesTitulo)}</h3><p class="rec-p">${e(T.antesTexto)}</p>
      ${R.CAMPOS.map((c) => `<label class="rec-campo" for="${c.id}"><span>${e(c.pregunta)}</span>
        <textarea id="${c.id}" data-rec-campo="${c.clave}" rows="3" maxlength="${R.MAX_TEXTO}" autocomplete="off">${e(t[c.clave])}</textarea></label>`).join('')}</div>`;
  }
  function cartelHtml(s) {
    const lineas = s.estado === 'agendado' ? [T.agendado] : [T.listo, R.textoListo(s.agenda)];
    return `<div class="rec-listo" id="recorrido-listo" role="status"><span class="rec-listo-ic">${IC.ok}</span>
      <p class="rec-listo-tit">${e(lineas[0])}</p>${lineas[1] ? `<p class="rec-p">${e(lineas[1])}</p>` : ''}</div>`;
  }
  function pieHtml(s) {
    if (s.estado !== 'publicado') return '';
    const m = ui.modelo;
    return `${m.error ? `<p class="rec-error" id="recorrido-error" role="alert">${e(T.error)}</p>` : ''}
      <button type="button" class="btn-primary cb-btn" id="recorrido-agendar"${m.enviando ? ' disabled aria-busy="true"' : ''}>${e(m.enviando ? T.enviando : T.agendar)}</button>
      <p class="rec-pie-nota">${e(T.agendarPie)}</p>`;
  }

  function pintarPie() {
    const b = hoja(), s = estado();
    if (!b || !s) return;
    const pie = b.querySelector('.rec-pie');
    const html = pieHtml(s);
    if (pie.dataset.h !== html) { pie.innerHTML = html; pie.dataset.h = html; }
    pie.hidden = !html;
  }

  function cerrarHoja() {
    const b = hoja();
    if (b) b.remove();
    ui.firma = null;
  }

  function abrirHoja() {
    const s = estado(), h = host();
    if (!s || !h) return;
    ui.firma = s.estado;
    h.innerHTML = `<div class="modal-back" id="recBack"><div class="modal-sheet cb-hoja rec-hoja" id="recorrido-hoja" role="dialog" aria-modal="true" aria-labelledby="recTit">
      <div class="cb-hoja-cab"><button type="button" class="cb-cerrar" id="recorrido-cerrar">${e(T.cerrar)}</button></div>
      <div class="cb-hoja-cuerpo">
        <h2 class="cb-hoja-tit" id="recTit">${e(s.titulo)}</h2>
        ${s.mensaje ? `<p class="rec-mensaje">${e(s.mensaje)}</p>` : ''}
        ${logrosHtml(s)}
        ${controlesHtml()}
        ${s.estado === 'publicado' ? preguntasHtml() : cartelHtml(s)}
      </div>
      <div class="cb-hoja-pie rec-pie"></div></div></div>`;
    const back = hoja();
    back.addEventListener('click', (ev) => {
      if (ev.target === back || ev.target.closest('#recorrido-cerrar')) { cerrarHoja(); return; }
      const b = ev.target.closest('#recorrido-agendar');
      if (b && !b.disabled) pedir();
    });
    back.addEventListener('input', (ev) => {
      const c = ev.target.getAttribute && ev.target.getAttribute('data-rec-campo');
      if (c && ui.modelo) ui.modelo.escribir(c, ev.target.value);
    });
    back.addEventListener('keydown', (ev) => { if (ev.key === 'Escape') cerrarHoja(); });
    pintarPie();
    ui.modelo.visto();
    const foco = back.querySelector('#recorrido-cerrar');
    if (foco) try { foco.focus({ preventScroll: true }); } catch (_) {}
  }

  async function pedir() {
    const m = ui.modelo;
    if (!m) return;
    // Lo que está en pantalla es lo que se manda, aunque el último `input` no haya llegado a guardarse.
    const b = hoja();
    if (b) b.querySelectorAll('[data-rec-campo]').forEach((t) => m.escribir(t.getAttribute('data-rec-campo'), t.value));
    await m.pedir();    // el modelo avisa: alCambiar repinta la hoja, la cierra si ya no está disponible, o muestra el error
  }

  /** Cada vez que el modelo cambia: la tarjeta, la entrada de Mis datos y, si está abierta, la hoja. */
  function alCambiar() {
    const s = estado();
    if (ui.op) ui.op.repintar();
    if (!hoja()) return;
    if (!s) { cerrarHoja(); return; }
    if (s.estado !== ui.firma) abrirHoja();       // pasó a pedido o agendado: se rehace entera (ya no hay campos)
    else pintarPie();                             // solo el botón y el error: no se le toca el texto a quien escribe
  }

  /** La primera vez que llega `publicado`, sola y una sola vez; sin taparle otra hoja ni el onboarding. */
  function abrirSola() {
    const m = ui.modelo;
    if (!m || ui.solaPedida || !m.debeAbrirseSola) return;
    ui.solaPedida = true;
    const intentar = (vueltas) => {
      if (!ui.modelo || !ui.modelo.debeAbrirseSola) { ui.solaPedida = false; return; }
      if (document.visibilityState !== 'visible' || (ui.op.ocupado && ui.op.ocupado())) {
        if (vueltas > 0) setTimeout(() => intentar(vueltas - 1), 1500);
        else ui.solaPedida = false;
        return;
      }
      ui.modelo.marcarAbiertaSola();
      abrirHoja();
    };
    setTimeout(() => intentar(40), 1400);
  }

  function refrescar() {
    const m = ui.modelo;
    if (!m || !m.prendida) return Promise.resolve();
    ui.ultimoRefresco = Date.now();
    return m.refrescar().then(abrirSola).catch(() => {});
  }

  /* op: { token, rpc, host() → #modalHost, ocupado() → otra hoja a la vista, repintar() → Entreno y Mis datos } */
  function configurar(op) { ui.op = op; }

  /** cfg: la respuesta de `mypump_get_app_config`, o null si no se pudo preguntar. */
  function aplicarConfig(cfg) {
    if (!ui.op || !R) return;
    if (!ui.modelo) {
      const almacen = { leer: (k) => localStorage.getItem(k), guardar: (k, v) => localStorage.setItem(k, v), borrar: (k) => localStorage.removeItem(k) };
      ui.modelo = R.crearModelo({ token: ui.op.token, rpc: ui.op.rpc, almacen });
      ui.modelo.alCambiar(alCambiar);
    }
    const prendida = ui.modelo.aplicarConfig(cfg);
    if (!prendida) return;
    if (!ui.enganchado) {
      ui.enganchado = true;
      document.addEventListener('visibilitychange', () => {
        if (document.visibilityState !== 'visible' || !ui.modelo || !ui.modelo.prendida) return;
        if (Date.now() - ui.ultimoRefresco > SEG_ENTRE_REFRESCOS * 1000) refrescar();
      });
    }
    refrescar();
  }

  raiz.RecorridoUI = {
    configurar, aplicarConfig, montarTarjeta, abrirHoja, cerrarHoja,
    entradaVisible: () => !!estado(),
    get _modelo() { return ui.modelo; },
  };
})(window);
