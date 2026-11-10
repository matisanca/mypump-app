/* =============================================================
   tecnica-ui.js — «Técnica por video»: las pantallas de la web.

   Todo texto sale de Tecnica.T. Con la palanca apagada, sin el servidor nuevo o
   sin cuenta no se crea nada: ni modelo, ni IndexedDB, ni llamadas, ni botones.
   ============================================================= */
(function (raiz) {
  'use strict';

  const Tec = raiz.Tecnica;
  const T = Tec.T;
  const FLAG = 'mypump_palanca_tecnica_video';
  const SEG_ENTRE_REFRESCOS = 60;
  const ESPERA_METADATOS_MS = 8000;

  const ui = {
    op: null, modelo: null, arrancando: false, enganchado: false, ultimoRefresco: 0,
    origen: 'misdatos', directo: false, pila: [], error: null, ocupado: false, sel: null,
    ultimoHtml: null, presionando: false, pendiente: false, entrada: false, video: null, avisoDetalle: null,
  };

  const e = (s) => String(s == null ? '' : s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const IC = {
    chev: '<svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="m9 6 6 6-6 6"/></svg>',
    camara: '<svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><rect x="3" y="6" width="13" height="12" rx="2"/><path d="m16 10.5 5-3v9l-5-3"/></svg>',
  };

  // ── El archivo ──
  /* Solo los metadatos: el navegador no baja el archivo a memoria. null si no se pudo (códec que este navegador no abre): decide el servidor. */
  function leerDuracion(archivo) {
    return new Promise((ok) => {
      const url = URL.createObjectURL(archivo);
      const v = document.createElement('video');
      let listo = false;
      const fin = (d) => {
        if (listo) return;
        listo = true;
        clearTimeout(reloj);
        v.removeAttribute('src');
        try { v.load(); } catch (_) {}
        URL.revokeObjectURL(url);
        ok(typeof d === 'number' && isFinite(d) && d > 0 ? d : null);
      };
      const reloj = setTimeout(() => fin(null), ESPERA_METADATOS_MS);
      v.preload = 'metadata';
      v.muted = true;
      v.playsInline = true;
      v.onloadedmetadata = () => fin(v.duration);
      v.onerror = () => fin(null);
      v.src = url;
    });
  }
  async function contenedorValido(archivo) {
    try {
      const b = archivo.slice(0, 12);
      return Tec.esMp4OMov(new Uint8Array(b.arrayBuffer ? await b.arrayBuffer() : await new Response(b).arrayBuffer()));
    } catch (_) { return false; }
  }

  // Un input con capture= abre la cámara y no deja llegar al carrete: dos inputs, como en las fotos.
  function inputVideo(origen) {
    const id = origen === 'galeria' ? 'tecInputGal' : 'tecInputCam';
    let inp = document.getElementById(id);
    if (!inp) {
      inp = document.createElement('input');
      inp.type = 'file';
      inp.id = id;
      inp.style.display = 'none';
      inp.accept = origen === 'galeria' ? 'video/*,.mp4,.mov' : 'video/*';
      if (origen !== 'galeria') inp.setAttribute('capture', 'environment');
      document.body.appendChild(inp);
    }
    return inp;
  }

  function hoja(titulo, botones) {
    const ov = document.createElement('div');
    ov.className = 'fp-pick';
    ov.innerHTML = `<div class="fp-pick-card" role="dialog" aria-label="${e(titulo)}">
      <div class="fp-pick-tit">${e(titulo)}</div>
      ${botones.map((b, i) => `<button type="button" class="fp-pick-btn${b.cancelar ? ' is-cancel' : ''}" data-i="${i}"${b.id ? ` id="${b.id}"` : ''}>${e(b.texto)}</button>`).join('')}</div>`;
    ov.addEventListener('click', (ev) => {
      if (ev.target === ov) return ov.remove();
      const b = ev.target.closest('.fp-pick-btn');
      if (!b) return;
      ov.remove();
      const f = botones[Number(b.dataset.i)].accion;
      if (f) f();      // sincrónico: en iOS el selector tiene que salir del mismo toque
    });
    document.body.appendChild(ov);
  }

  function pedirVideo() {
    const elegir = (origen) => () => {
      const inp = inputVideo(origen);
      inp.onchange = () => {
        const a = inp.files && inp.files[0];
        inp.value = '';
        if (a) procesarArchivo(a);
      };
      inp.click();
    };
    hoja(T.grabarOElegir, [
      { texto: T.grabarAhora, id: 'tecCamara', accion: elegir('camara') },
      { texto: T.elegirGaleria, id: 'tecGaleria', accion: elegir('galeria') },
      { texto: T.cancelar, cancelar: true },
    ]);
  }

  function soltarVista() {
    if (ui.sel && ui.sel.url) { URL.revokeObjectURL(ui.sel.url); ui.sel.url = null; }
  }

  async function procesarArchivo(archivo) {
    const m = ui.modelo, s = ui.sel;
    if (!m || !s) return;
    soltarVista();
    s.archivo = null;
    s.duracion = null;
    s.validando = true;
    ui.error = null;
    renderEscena();
    const [duracion, contenedorOk] = await Promise.all([leerDuracion(archivo), contenedorValido(archivo)]);
    if (ui.sel !== s) return;
    s.validando = false;
    const rechazo = Tec.validarVideo({ bytes: archivo.size, duracion, contenedorOk }, m.topes);
    if (rechazo) {
      ui.error = T.rechazos[rechazo];
    } else {
      s.archivo = archivo;
      s.duracion = duracion;
      s.contenedorOk = contenedorOk;
      s.url = URL.createObjectURL(archivo);
    }
    renderEscena();
  }

  // ── Piezas ──
  const nota = (t, alerta, id) => `<p class="gim-nota${alerta ? ' is-alerta' : ''}"${alerta ? ' role="alert"' : ''}${id ? ` id="${id}"` : ''}>${e(t)}</p>`;
  const errorHtml = () => (ui.error ? nota(ui.error, true, 'tecError') : '');
  const avisoHtml = (m) => (m.aviso ? nota(m.aviso, true, 'tecAviso') : '');
  const textoBloqueo = (m, b) => (b === 'tope' ? T.topeSemana(m.topes.porSemana) : T.enRevision);
  const porciento = (p) => `${Math.round(Math.min(1, Math.max(0, p)) * 100)}%`;

  function filaCola(m, c) {
    const sube = m.subiendoId === c.id;
    const parado = c.pausado;
    return `<div class="tec-envio tec-cola" id="tecFilaCola"><strong>${e(c.nombre)}</strong>
      ${parado ? nota(T.noSubio, true, 'tecPausado') : nota(sube ? T.subiendo : T.esperandoSenal, false, 'tecEstadoCola')}
      ${!parado ? `<div class="gim-barra tec-barra" role="progressbar" aria-label="${e(T.subiendo)}" aria-valuemin="0" aria-valuemax="100" aria-valuenow="${sube ? Math.round(m.progreso * 100) : 0}"><span id="tecBarra" style="width:${sube ? porciento(m.progreso) : '0%'}"></span></div>` : ''}
      <div class="tec-acciones">${parado ? `<button type="button" class="btn-secondary" data-tec="reintentar" data-id="${e(c.id)}" id="tecReintentar">${e(T.probarDeNuevo)}</button>` : ''}
      <button type="button" class="btn-secondary" data-tec="cancelarCola" data-id="${e(c.id)}" id="tecCancelarCola">${e(T.cancelar)}</button></div></div>`;
  }

  function detalleFila(s) {
    if (Tec.conDevolucion(s)) { const f = Tec.fechaCorta(s.publicadoEn); return f ? T.creditoEl(f) : T.credito; }
    if (s.estado === 'rechazado') return Tec.textoRechazo(s.rechazoTexto);
    return T.recibido;
  }

  function pLista(m) {
    const b = m.bloqueo;
    const enCola = m.cola.map((c) => filaCola(m, c)).join('');
    const hay = m.envios.length || m.cola.length || m.guardando;
    return `${avisoHtml(m)}${errorHtml()}
      ${m.guardando ? `<div class="tec-envio" id="tecGuardando"><div class="spinner" aria-hidden="true"></div>${nota(T.subiendo)}</div>` : ''}
      ${enCola}
      ${b && !m.cola.length && !m.guardando ? nota(textoBloqueo(m, b), false, 'tecBloqueo') : ''}
      <button type="button" class="btn-primary" data-tec="mandar" id="tecMandar"${b ? ' disabled' : ''}>${IC.camara}<span>${e(T.mandar)}</span></button>
      ${hay ? '' : nota(T.sinEnvios, false, 'tecVacio')}
      ${m.envios.length ? `<div class="md-grupo">${m.envios.map((s) => `<button type="button" class="md-fila tec-fila" data-tec="ver" data-id="${e(s.id)}">
        <span class="gim-zona-txt"><span>${e(s.ejercicioNombre || T.titulo)}</span><small>${e(detalleFila(s))}</small></span><span class="md-chev">${IC.chev}</span></button>`).join('')}</div>` : ''}`;
  }

  function pElegir() {
    const lista = ui.op.ejercicios();
    return `<h2 class="gim-h gim-h-chico">${e(T.elegirEjercicio)}</h2>
      <div class="md-grupo">${lista.map((x, i) => `<button type="button" class="md-fila" data-tec="elegido" data-i="${i}"><span>${e(x.nombre)}</span><span class="md-chev">${IC.chev}</span></button>`).join('')}</div>`;
  }

  function pGrabar(m) {
    const s = ui.sel;
    const n = Array.from(s.nota).length;
    return `<h2 class="gim-h gim-h-chico" id="tecEjercicio">${e(s.ejercicio.nombre)}</h2>
      ${m.necesitaAviso ? `<div class="gim-aviso" id="tecAvisoTerceros">${e(T.avisoTerceros)}</div>` : ''}
      <p class="gim-sub" id="tecConsejo">${e(T.consejo)}</p>
      ${s.url ? `<video class="tec-video" id="tecPrevia" src="${e(s.url)}#t=0.1" controls playsinline muted preload="metadata"></video>` : ''}
      ${s.validando ? `<div class="tec-envio" id="tecValidando"><div class="spinner" aria-hidden="true"></div>${nota(T.preparandoVideo)}</div>` : ''}
      ${errorHtml()}${avisoHtml(m)}
      <button type="button" class="${s.archivo ? 'btn-secondary' : 'btn-primary'}" data-tec="elegirVideo" id="tecElegirVideo"${s.validando ? ' disabled' : ''}>${s.archivo ? '' : IC.camara}<span>${e(s.archivo ? T.cambiarVideo : T.grabarOElegir)}</span></button>
      ${s.archivo ? `<textarea class="gim-area" id="tecNota" rows="3" maxlength="${Tec.MAX_NOTA}" placeholder="${e(T.notaPlaceholder)}" aria-label="${e(T.notaPlaceholder)}">${e(s.nota)}</textarea>
      <div class="gim-cuenta" id="tecNotaCuenta">${n}/${Tec.MAX_NOTA}</div>
      <button type="button" class="btn-primary" data-tec="enviar" id="tecEnviar"${ui.ocupado || m.guardando ? ' disabled' : ''}>${e(T.enviar)}</button>` : ''}`;
  }

  const seccion = (titulo, html, id) => `<div class="md-ceja gim-sin-mayus"${id ? ` id="${id}"` : ''}>${e(titulo)}</div>${html}`;
  const parte = (etiqueta, t) => (t ? `<p class="tec-parte"><strong>${e(etiqueta)}</strong><span>${e(t)}</span></p>` : '');

  function pDetalle(m, id) {
    const s = m.envio(id);
    if (!s) { ui.pila = []; return pLista(m); }
    const d = Tec.conDevolucion(s) ? s.devolucion : null;
    const reproductor = ui.video && ui.video.id === id ? `<video class="tec-video" id="tecVideo" src="${e(ui.video.url)}" controls playsinline preload="metadata"></video>` : '';
    const puedeVer = s.tieneVideo;
    const verBtn = (momento, id2) => `<button type="button" class="btn-secondary tec-ver" data-tec="verVideo" data-id="${e(id)}"${momento != null ? ` data-t="${momento}"` : ''}${id2 ? ` id="${id2}"` : ''}>${e(T.verEnVideo)}</button>`;
    const sacarBtn = puedeVer ? `<button type="button" class="tec-sacar" data-tec="sacar" data-id="${e(id)}" id="tecSacar">${e(T.sacarVideo)}</button>` : '';
    const avisos = `${ui.avisoDetalle ? nota(ui.avisoDetalle, false, 'tecAvisoDetalle') : ''}${errorHtml()}`;
    if (!d) {
      return `<h2 class="gim-h gim-h-chico">${e(s.ejercicioNombre || T.titulo)}</h2>
        ${s.estado === 'rechazado' ? nota(Tec.textoRechazo(s.rechazoTexto), true, 'tecRechazo') : `<p class="gim-sub" id="tecRecibido">${e(T.recibido)}</p>`}
        ${avisos}${reproductor}${puedeVer && !reproductor ? verBtn(null, 'tecVerSolo') : ''}
        ${s.estado === 'rechazado' ? `<button type="button" class="btn-primary" data-tec="otra" data-id="${e(id)}" id="tecOtra"${m.bloqueo ? ' disabled' : ''}>${e(T.mandar)}</button>` : ''}${sacarBtn}`;
    }
    const f = Tec.fechaCorta(s.publicadoEn);
    const nombre = d.ejercicio || s.ejercicioNombre || '';
    const sinNada = !d.correcciones.length && !d.pedirOtro;
    return `<h2 class="gim-h gim-h-chico" id="tecTituloDev">${e(T.tituloDevolucion(nombre))}</h2>
      <p class="tec-credito" id="tecCredito">${e(f ? T.creditoEl(f) : T.credito)}</p>
      ${avisos}${reproductor}
      ${sinNada ? nota(T.sinCorrecciones, false, 'tecSinCorrecciones') : ''}
      ${d.bien.length ? seccion(T.bien, `<ul class="tec-lista">${d.bien.map((x) => `<li>${e(x)}</li>`).join('')}</ul>`, 'tecBien') : ''}
      ${d.correcciones.length ? seccion(T.corregir, d.correcciones.map((c, i) => `<div class="tec-correccion"><h3>${e(c.titulo)}</h3>
        ${parte(T.queSeVe, c.queSeVe)}${parte(T.porQue, c.porQue)}${parte(T.como, c.como)}
        ${puedeVer && c.momento != null ? verBtn(c.momento, `tecVer${i}`) : ''}</div>`).join(''), 'tecCorregir') : ''}
      ${d.noEvaluable.length ? seccion(T.noSePudoVer, `<ul class="tec-lista">${d.noEvaluable.map((n) => `<li>${e(n.que)}${n.motivo ? `. ${e(n.motivo)}` : ''}</li>`).join('')}</ul>`, 'tecNoVer') : ''}
      ${d.pedirOtro ? seccion(T.otroVideo, `${d.pedirOtro.como ? `<p class="gim-sub" id="tecComoOtro">${e(d.pedirOtro.como)}</p>` : ''}<button type="button" class="btn-primary" data-tec="otra" data-id="${e(id)}" id="tecOtra"${m.bloqueo ? ' disabled' : ''}>${e(T.mandar)}</button>`, 'tecOtroVideo') : ''}
      ${sacarBtn}`;
  }

  // ── Armar y pintar ──
  const tope = () => ui.pila[ui.pila.length - 1] || null;

  function cuerpo(m) {
    const d = tope();
    if (d && d.t === 'elegir') return pElegir();
    if (d && d.t === 'grabar' && ui.sel) return pGrabar(m);
    if (d && d.t === 'detalle') return pDetalle(m, d.id);
    return pLista(m);
  }

  function raizEscena() { return document.getElementById('scene-tecnica'); }
  function escenaActiva() { const r = raizEscena(); return !!r && r.classList.contains('is-active'); }
  const escribiendo = () => {
    const r = raizEscena(), a = document.activeElement;
    return !!r && !!a && r.contains(a) && (a.tagName === 'TEXTAREA' || a.tagName === 'INPUT');
  };

  function renderEscena() {
    const r = raizEscena(), m = ui.modelo;
    if (!r) return;
    if (!m || !m.estado) { r.innerHTML = ''; ui.ultimoHtml = null; if (escenaActiva()) cerrar(); return; }
    // No se le rehace la pantalla a quien escribe, ni el botón que tiene bajo el dedo.
    if (escribiendo() || ui.presionando) { ui.pendiente = true; return; }
    ui.pendiente = false;
    const volver = ui.pila.length > (ui.directo ? 1 : 0) ? T.titulo : T.cerrar;
    const h = `<div class="gim tec"><button type="button" class="sd-volver" data-tec="volver" id="tecVolver">‹ ${e(volver)}</button>${cuerpo(m)}</div>`;
    if (h !== ui.ultimoHtml) { r.innerHTML = h; ui.ultimoHtml = h; }
    const t = document.getElementById('hdrTitle');
    if (t) t.textContent = T.titulo;
  }

  function pintar() {
    if (!ui.op) return;
    const ve = !!(ui.modelo && ui.modelo.visibleEntrada);
    if (ve !== ui.entrada) { ui.entrada = ve; ui.op.alCambiarEntrada(); }
    if (escenaActiva()) renderEscena();
  }

  /* El avance no repinta: cada 1 % rearmaría la pantalla bajo el dedo. */
  function pintarProgreso(p) {
    const b = document.getElementById('tecBarra');
    if (!b) return;
    b.style.width = porciento(p);
    if (b.parentNode) b.parentNode.setAttribute('aria-valuenow', String(Math.round(p * 100)));
  }

  function limpiarSeleccion() { soltarVista(); ui.sel = null; }
  function nuevaSeleccion(ej) { limpiarSeleccion(); ui.sel = { ejercicio: ej, archivo: null, duracion: null, contenedorOk: false, url: null, nota: '', validando: false }; }

  function preparar(origen) {
    ui.origen = origen;
    ui.pila = [];
    ui.error = null;
    ui.directo = false;
    ui.video = null;
    ui.avisoDetalle = null;
    limpiarSeleccion();
    ui.op.irA('tecnica');
    ui.modelo.refrescar().then(() => ui.modelo && ui.modelo.drenar()).catch(() => {});
  }

  function abrir(origen) {
    if (!ui.modelo || !ui.modelo.estado) return;
    ui.modelo.limpiarAviso();
    preparar(origen);
  }

  /* Desde el ejercicio abierto: directo a grabar, salvo que no se pueda mandar: ahí la lista dice por qué. */
  function abrirConEjercicio(ex) {
    if (!ui.modelo || !ui.modelo.estado) return;
    ui.modelo.limpiarAviso();
    preparar('train');
    if (ui.modelo.bloqueo) return;
    nuevaSeleccion(Tec.ejercicioDe(ex));
    ui.directo = true;
    apilar({ t: 'grabar' });
  }

  function cerrar() { if (ui.op) ui.op.irA(ui.origen === 'train' ? 'train' : 'misdatos'); }
  function apilar(d) { ui.pila.push(d); ui.error = null; renderEscena(); window.scrollTo(0, 0); }

  function seekA(t) {
    const v = document.getElementById('tecVideo');
    if (!v) return;
    v.scrollIntoView({ block: 'center', behavior: 'smooth' });
    if (t == null) return;
    const ir = () => { try { v.currentTime = t; } catch (_) {} };
    if (v.readyState >= 1) ir(); else v.addEventListener('loadedmetadata', ir, { once: true });
  }

  // ── Toques ──
  const ACCIONES = {
    volver() {
      if (ui.pila.length > (ui.directo ? 1 : 0)) {
        const d = ui.pila.pop();
        if (d.t === 'grabar') limpiarSeleccion();
        ui.error = null; ui.video = null; ui.avisoDetalle = null;
        renderEscena();
      } else { limpiarSeleccion(); cerrar(); }
    },
    mandar() { ui.modelo.limpiarAviso(); apilar({ t: 'elegir' }); },
    elegido(b) {
      const x = ui.op.ejercicios()[Number(b.dataset.i)];
      if (!x) return;
      nuevaSeleccion(x);
      apilar({ t: 'grabar' });
    },
    elegirVideo() { ui.error = null; pedirVideo(); },
    async enviar() {
      const m = ui.modelo, s = ui.sel;
      if (!s || !s.archivo || ui.ocupado) return;
      ui.ocupado = true;
      ui.error = null;
      // A la lista enseguida: pasar 60 MB a IndexedDB tarda unos segundos y ahí se ve el estado.
      ui.pila = [];
      ui.directo = false;
      const pedido = m.enviar({ ejercicio: s.ejercicio, nota: s.nota, archivo: s.archivo, duracion: s.duracion, contenedorOk: s.contenedorOk });
      renderEscena();
      window.scrollTo(0, 0);
      let r;
      try { r = await pedido; } finally { ui.ocupado = false; }
      limpiarSeleccion();
      if (r !== 'ok') ui.error = r === 'enRevision' ? T.enRevision : r === 'tope' ? T.topeSemana(m.topes.porSemana) : T.rechazos[r] || T.errorGenerico;
      renderEscena();
    },
    reintentar(b) { ui.modelo.reintentar(b.dataset.id); },
    async cancelarCola(b) { await ui.modelo.cancelar(b.dataset.id); renderEscena(); },
    ver(b) { ui.video = null; ui.avisoDetalle = null; apilar({ t: 'detalle', id: b.dataset.id }); },
    otra(b) {
      const s = ui.modelo.envio(b.dataset.id);
      if (!s) return;
      nuevaSeleccion({ slug: s.ejercicioSlug || Tec.slugDe(s.ejercicioNombre), nombre: s.ejercicioNombre || '' });
      apilar({ t: 'grabar' });
    },
    async verVideo(b) {
      const id = b.dataset.id, t = b.dataset.t != null ? Number(b.dataset.t) : null;
      if (ui.video && ui.video.id === id) { seekA(t); return; }
      ui.error = null;
      const url = await ui.modelo.urlVideo(id);
      if (!url) { ui.error = T.noCargoVideo; renderEscena(); return; }
      ui.video = { id, url };
      renderEscena();
      seekA(t);
    },
    sacar(b) {
      const id = b.dataset.id;
      hoja(T.sacarConfirma, [
        { texto: T.sacarVideo, id: 'tecSacarSi', accion: () => sacarVideo(id) },
        { texto: T.cancelar, cancelar: true },
      ]);
    },
  };

  async function sacarVideo(id) {
    const r = await ui.modelo.borrarVideo(id);
    ui.error = r === 'ok' ? null : r === 'enAnalisis' ? T.enAnalisis : r === 'sinSenal' ? T.sinSenal : T.errorGenerico;
    if (r === 'ok') { ui.video = null; ui.avisoDetalle = T.videoSacado; }
    renderEscena();
  }

  function enganchar() {
    if (ui.enganchado) return;
    ui.enganchado = true;
    const r = raizEscena();
    if (r) {
      r.addEventListener('click', (ev) => {
        const b = ev.target.closest('[data-tec]');
        if (!b || b.disabled || !ui.modelo) return;
        const foco = document.activeElement;
        if (foco && r.contains(foco) && foco !== b && (foco.tagName === 'INPUT' || foco.tagName === 'TEXTAREA')) foco.blur();
        const f = ACCIONES[b.dataset.tec];
        if (f) { const p = f(b); if (p && p.catch) p.catch(() => {}); }
      });
      r.addEventListener('input', (ev) => {
        if (ev.target.id !== 'tecNota' || !ui.sel) return;
        ui.sel.nota = Tec.notaRecortada(ev.target.value);
        const c = document.getElementById('tecNotaCuenta');
        if (c) c.textContent = `${Array.from(ui.sel.nota).length}/${Tec.MAX_NOTA}`;
      });
      const repintarPendiente = () => setTimeout(() => { if (ui.pendiente && ui.modelo && escenaActiva()) renderEscena(); }, 60);
      r.addEventListener('pointerdown', () => { ui.presionando = true; }, true);
      const soltar = () => { if (!ui.presionando) return; ui.presionando = false; repintarPendiente(); };
      window.addEventListener('pointerup', soltar, true);
      window.addEventListener('pointercancel', soltar, true);
      r.addEventListener('focusout', repintarPendiente);
    }
    window.addEventListener('online', () => { if (ui.modelo) ui.modelo.reanudar(); });
    document.addEventListener('visibilitychange', () => {
      if (document.visibilityState !== 'visible' || !ui.modelo) return;
      if (Date.now() - ui.ultimoRefresco > SEG_ENTRE_REFRESCOS * 1000) { ui.ultimoRefresco = Date.now(); ui.modelo.refrescar().catch(() => {}); }
      ui.modelo.reanudar();
    });
  }

  const conLock = (token) => (fn) => {
    if (!navigator.locks || !navigator.locks.request) return fn();
    return navigator.locks.request(`tecnica-cola-${token}`, () => fn());
  };

  /* op: { token, rpc, visionUrl, irA(escena), alCambiarEntrada(), ejercicios() } */
  function configurar(op) { ui.op = op; }

  /* valor: true o false si el servidor contestó; null si no se pudo preguntar (se sigue con lo último que se supo). */
  async function aplicarPalanca(valor) {
    if (!ui.op || ui.arrancando) return;
    let prendida;
    try {
      if (valor === null) prendida = localStorage.getItem(FLAG) === '1';
      else {
        prendida = valor === true;
        if (prendida) localStorage.setItem(FLAG, '1'); else localStorage.removeItem(FLAG);
      }
    } catch (_) { prendida = valor === true; }
    if (!prendida) {
      if (ui.modelo) { ui.modelo.apagar(); ui.modelo = null; pintar(); }
      return;
    }
    if (ui.modelo) return;
    ui.arrancando = true;
    try {
      // Antes de abrir nada en el teléfono: a una cuenta sin la función no se le crea ni la base.
      const primera = await ui.op.rpc('mypump_tecnica_get', { p_token: ui.op.token });
      if (primera.ok ? !Tec.decodificarEstado(primera.data) : (primera.status === 404 || primera.codigo === 'PGRST202' || primera.clase === 'permanente')) return;
      const almacen = await raiz.TecnicaCola.abrirAlmacen();
      const m = new raiz.TecnicaCola.ModeloTecnica({ rpc: ui.op.rpc, almacen, token: ui.op.token, visionUrl: ui.op.visionUrl, conLock: conLock(ui.op.token) });
      await m.cargar();
      await m.refrescar(primera);
      m.alCambiar = pintar;
      m.alProgreso = pintarProgreso;
      ui.modelo = m;
      ui.ultimoRefresco = Date.now();
      enganchar();
      pintar();
      m.reanudar();
    } catch (_) {
      ui.modelo = null;
    } finally {
      ui.arrancando = false;
    }
  }

  raiz.TecnicaUI = {
    configurar, aplicarPalanca, abrir, abrirConEjercicio, renderEscena,
    titulo: () => T.titulo,
    entradaVisible: () => !!(ui.modelo && ui.modelo.visibleEntrada),
    get origen() { return ui.origen; },
    get _modelo() { return ui.modelo; },
  };
})(window);
