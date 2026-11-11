/* =============================================================
   casa-ui.js — «Entreno en casa» en la web (palanca `casa`): el interruptor arriba de Mi gimnasio, la lista «¿Qué tenés
   en casa?» y la pantalla «Entrenás en casa». Las reglas están en js/casa.js; las pantallas las pide gimnasio-ui.js
   (piezas()), que es quien pinta la escena. Apagada, o sin Mi gimnasio, no se crea ni se llama nada.

   La lista de equipo viene del servidor y se escribe escapada. Las casillas son botones (role="checkbox"): un <input>
   con foco frenaría el repintado de la escena.
   ============================================================= */
(function (raiz) {
  'use strict';
  const C = raiz.Casa;
  const T = C.T;

  const ui = { op: null, cfg: undefined, modelo: null, gim: null, pintar: null, enganchado: false };
  const e = (s) => String(s == null ? '' : s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const IC = {
    casa: '<svg viewBox="0 0 24 24" width="24" height="24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M4 11l8-7 8 7"/><path d="M6 10v9h12v-9"/><path d="M10 19v-5h4v5"/></svg>',
    tilde: '<svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="3.2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="m5 12.5 4.5 4.5L19 7.5"/></svg>',
  };
  const raizEscena = () => document.getElementById('scene-gimnasio');
  const pintar = () => { if (ui.pintar) ui.pintar(); };

  // ── Piezas ──
  function interruptorHtml(m) {
    const i = m.interruptor;
    if (!i) return '';
    const quieto = i.bloqueado || i.ocupado;
    return `<div class="casa-int${i.prendido ? ' is-on' : ''}${i.bloqueado ? ' is-bloqueado' : ''}">
      <button type="button" class="casa-int-btn" role="switch" aria-checked="${i.prendido}" aria-describedby="casaIntAyuda" id="casa-interruptor" data-casa="interruptor"${quieto ? ' disabled' : ''}>
        <span class="casa-int-ic">${IC.casa}</span>
        <span class="casa-int-txt"><strong>${e(T.interruptor)}</strong><span id="casaIntAyuda">${e(i.bloqueado ? T.interruptorBloqueado : T.interruptorAyuda)}</span></span>
        <span class="md-switch casa-switch" aria-hidden="true"></span></button>
      ${m.error === 'cambiar' ? `<p class="gim-nota is-alerta casa-error" id="casa-error" role="alert">${e(T.errorCambiar)}</p>` : ''}</div>`;
  }

  function casilla(id, attrs, marcada, texto) {
    return `<button type="button" class="casa-fila${marcada ? ' is-on' : ''}" role="checkbox" aria-checked="${marcada}" id="${id}" ${attrs}>
      <span class="casa-casilla">${marcada ? IC.tilde : ''}</span><span class="casa-fila-txt">${e(texto)}</span></button>`;
  }

  function listaHtml(m) {
    const s = m.estado, b = m.borrador;
    const filas = s.tipos.map((t) => {
      const on = b.marcados.includes(t.tipo);
      let kg = '';
      if (t.kg && on) {
        const v = b.kg[t.tipo] || '';
        const mal = v.trim() !== '' && C.kilos(v) === null;
        kg = `<label class="casa-kg" for="casa-kg-${t.tipo}"><span>${e(T.kilos)}</span>
          <span class="casa-kg-campo"><input type="text" inputmode="decimal" autocomplete="off" maxlength="6" id="casa-kg-${t.tipo}" data-casa-kg="${t.tipo}" value="${e(v)}"><span>${e(T.kg)}</span></span></label>
          <p class="gim-nota is-alerta casa-kg-mal" data-casa-kg-mal="${t.tipo}"${mal ? '' : ' hidden'}>${e(T.kilosInvalidos)}</p>`;
      }
      return `<div class="casa-tipo${on ? ' is-on' : ''}">${casilla(`casa-tipo-${t.tipo}`, `data-casa="tipo" data-tipo="${t.tipo}"`, on, t.nombre)}${kg}</div>`;
    }).join('');
    const err = m.error === 'enviar' ? T.errorEnviar : m.error === 'sinDatos' ? T.sinDatos : null;
    return `<div class="casa-lista" id="casa-lista">
      <h2 class="gim-h">${e(T.listaTitulo)}</h2>
      <p class="gim-sub">${e(T.listaTexto)}</p>
      <div class="casa-tipos">${filas}
        <div class="casa-tipo casa-tipo-nada${b.sinEquipo ? ' is-on' : ''}">${casilla('casa-sin-equipo', 'data-casa="sinEquipo"', b.sinEquipo, T.sinEquipo)}</div></div>
      <label class="casa-nota-l" for="casa-nota">${e(T.nota)}</label>
      <textarea class="gim-area" id="casa-nota" rows="3" maxlength="${C.MAX_NOTA}" autocomplete="off">${e(b.nota)}</textarea>
      ${err ? `<p class="gim-nota is-alerta casa-error" id="casa-error" role="alert">${e(err)}</p>` : ''}
      <button type="button" class="btn-primary cb-btn" id="casa-enviar" data-casa="enviar"${m.puedeEnviar ? '' : ' disabled'}>${e(T.enviar)}</button></div>`;
  }

  function vigenteHtml(m) {
    const s = m.estado, v = s.vigente;
    const eqs = C.equiposVigentes(v, s.tipos);
    return `<div class="casa-vigente" id="casa-vigente">
      <h2 class="gim-h">${e(T.vigenteTitulo)}</h2>
      ${eqs.length ? `<div class="md-grupo">${eqs.map((q) => `<div class="gim-resumen-f casa-eq"><span>${e(q.nombre)}</span>${q.detalle ? `<span>${e(q.detalle)}</span>` : ''}</div>`).join('')}</div>` : ''}
      ${v.sinEquipo || !eqs.length ? `<p class="gim-sub" id="casa-sin-equipo-vigente">${e(T.vigenteSinEquipo)}</p>` : ''}
      <button type="button" class="btn-primary cb-btn gim-mt" id="casa-cambiar" data-casa="cambiar"${m.interruptor && m.interruptor.ocupado ? ' disabled' : ''}>${e(T.cambiar)}</button></div>`;
  }

  /** Lo que gimnasio-ui pone en la escena: null (no hay interruptor), o {arriba, cuerpo} con cuerpo null = las pantallas
   *  del gimnasio de siempre. */
  function piezas() {
    const m = ui.modelo;
    if (!m || !m.estado) return null;
    const p = m.pantalla;
    return { arriba: interruptorHtml(m), cuerpo: p === 'lista' ? listaHtml(m) : p === 'vigente' ? vigenteHtml(m) : null };
  }
  /** El renglón de la tarjeta de Entreno cuando lo que hay abierto es la lista de casa. */
  function detalleTarjeta() {
    const m = ui.modelo;
    return m && m.estado && m.pantalla === 'lista' ? T.listaTitulo : null;
  }

  // ── Toques ──
  const ACCIONES = {
    interruptor(b) { return ui.modelo.mover(b.getAttribute('aria-checked') !== 'true'); },
    cambiar() { return ui.modelo.cambiar(); },
    tipo(b) { ui.modelo.alternarTipo(b.dataset.tipo); },
    sinEquipo() { ui.modelo.alternarSinEquipo(); },
    enviar() {
      const n = document.getElementById('casa-nota');
      if (n) ui.modelo.fijarNota(n.value);
      return ui.modelo.enviar();
    },
  };

  function enganchar() {
    const r = raizEscena();
    if (ui.enganchado || !r) return;
    ui.enganchado = true;
    r.addEventListener('click', (ev) => {
      const b = ev.target.closest('[data-casa]');
      if (!b || b.disabled || !ui.modelo || !ui.modelo.estado) return;
      // Si el navegador no le sacó el foco al campo, la pantalla que viene no se pintaría.
      const foco = document.activeElement;
      if (foco && r.contains(foco) && foco !== b && (foco.tagName === 'INPUT' || foco.tagName === 'TEXTAREA')) foco.blur();
      const f = ACCIONES[b.dataset.casa];
      if (f) { const p = f(b); if (p && p.catch) p.catch(() => {}); }
    });
    r.addEventListener('input', (ev) => {
      const m = ui.modelo;
      if (!m || !m.estado) return;
      const t = ev.target;
      if (t.id === 'casa-nota') m.fijarNota(t.value);
      else if (t.dataset && t.dataset.casaKg) {
        m.fijarKg(t.dataset.casaKg, t.value);
        const mal = r.querySelector(`[data-casa-kg-mal="${t.dataset.casaKg}"]`);
        if (mal) mal.hidden = !(t.value.trim() !== '' && C.kilos(t.value) === null);
      }
    });
  }

  /* op: { token, rpc } */
  function configurar(op) { ui.op = op; }
  /** cfg: la respuesta de `mypump_get_app_config`, o null si no se pudo preguntar. Va ANTES de GimnasioUI.aplicarPalanca. */
  function aplicarConfig(cfg) { ui.cfg = cfg; }

  /** gimnasio-ui avisa que ya tiene su modelo (o null si se apagó). Desde acá `refrescar` del gimnasio trae también lo de casa. */
  function conGimnasio(modeloGim, pintarGim) {
    if (!modeloGim) { ui.modelo = null; ui.gim = null; return; }
    if (!ui.op || !C || ui.gim === modeloGim) return;
    const almacen = { leer: (k) => localStorage.getItem(k), guardar: (k, v) => localStorage.setItem(k, v), borrar: (k) => localStorage.removeItem(k) };
    const original = modeloGim.refrescar.bind(modeloGim);
    const m = C.crearModelo({ token: ui.op.token, rpc: ui.op.rpc, almacen,
      gimnasio: { refrescar: () => original(), nuevoCompleta: () => modeloGim.empezar('completa') } });
    if (!m.aplicarConfig(ui.cfg === undefined ? null : ui.cfg)) return;      // apagada: no se toca nada ni se llama a nada
    ui.gim = modeloGim; ui.modelo = m; ui.pintar = pintarGim;
    // Primero casa y después el gimnasio: cuando el gimnasio pinta, ya se sabe de qué lugar es la carga.
    modeloGim.refrescar = async (previa) => { await m.refrescar(); return original(previa); };
    m.alCambiar(pintar);
    enganchar();
  }

  raiz.CasaUI = { configurar, aplicarConfig, conGimnasio, piezas, detalleTarjeta, get _modelo() { return ui.modelo; } };
})(window);
