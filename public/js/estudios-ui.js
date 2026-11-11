/* =============================================================
   estudios-ui.js — «Estudios y órdenes»: las pantallas de la web.

   Todo texto sale de Estudios.T. Con la palanca apagada, sin poder leerla en esta
   carga, sin el servidor nuevo o sin cuenta no se crea nada: ni modelo, ni llamadas,
   ni la fila de Mis datos. En el navegador no se guarda nada: ni la palanca.
   Un archivo se ve desde la memoria (un Blob): su URL firmada no toca el DOM ni el historial.
   ============================================================= */
(function (raiz) {
  'use strict';

  const E = raiz.Estudios;
  const T = E.T;
  const FLAG = 'mypump_palanca_estudios_app';
  const SEG_ENTRE_REFRESCOS = 60;
  const VIDA_VISOR_MS = 9 * 60 * 1000;      // lo abierto se suelta de la memoria a los 9 minutos
  const TIRON_PX = 90;
  const ESPERAS_ARRANQUE_S = [4, 20];
  const QUIETO_MS = 350;                    // tras cambiar de pantalla: el segundo toque de un doble toque no cae en otro botón
  const MIRADA_MS = 1000;                   // una tarjeta nueva cuenta como vista si estuvo este rato en pantalla
  const JUNTAR_MS = 80;
  const ESPERA_DESTINO_MS = 12000;          // al llegar por el aviso: lo que se espera a saber si la cuenta tiene la sección

  const ui = {
    op: null, modelo: null, arrancando: false, enganchado: false, ultimoRefresco: 0,
    pila: [], error: null, ocupado: false, abriendo: false, preparando: 0,
    ultimoHtml: null, quietoHasta: 0, presionando: false, pendiente: false, firmaEntrada: '', vistas: new Map(), relojVisor: null, sueltas: [], tiron: null,
    origen: 'misdatos',                     // adónde vuelve «Cerrar»: de donde se entró
    destino: null,                          // { caida, hasta }: se llegó por el aviso y todavía no se sabe si hay sección
    apuntar: false,                         // al entrar, la tarjeta nueva tiene que quedar a la vista (hasta que toque algo)
    nuevasDeLaVisita: new Set(),            // la etiqueta «Nuevo» no se le va de la vista mientras está mirando
    mirando: new Map(), ojo: null, ojoDe: null, porAvisar: new Set(), relojAviso: null,
  };

  /* Un id del servidor dentro de un selector: escapado, para que no pueda cambiarlo. */
  const escCss = (s) => (raiz.CSS && raiz.CSS.escape ? raiz.CSS.escape(String(s)) : String(s).replace(/[^a-zA-Z0-9_-]/g, (c) => `\\${c.charCodeAt(0).toString(16)} `));
  const e = (s) => String(s == null ? '' : s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const svg = (d, t = 18) => `<svg viewBox="0 0 24 24" width="${t}" height="${t}" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${d}</svg>`;
  const IC = {
    chev: svg('<path d="m9 6 6 6-6 6"/>', 14),
    calendario: svg('<rect x="3" y="5" width="18" height="16" rx="3"/><path d="M3 10h18M8 3v4M16 3v4"/>'),
    reloj: svg('<circle cx="12" cy="12" r="9"/><path d="M12 7v5h4"/>'),
    tilde: svg('<circle cx="12" cy="12" r="9"/><path d="m8 12 3 3 5-6"/>'),
    bandeja: svg('<path d="M4 13 6 5h12l2 8v5a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1v-5Z"/><path d="M4 13h5l1 2h4l1-2h5"/>'),
    subir: svg('<path d="M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8l-5-5Z"/><path d="M14 3v5h5M12 18v-6M9.5 14.5 12 12l2.5 2.5"/>', 20),
    camara: svg('<path d="M4 8h3l2-3h6l2 3h3a1 1 0 0 1 1 1v10a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1V9a1 1 0 0 1 1-1Z"/><circle cx="12" cy="13.5" r="3.5"/>', 24),
    fotos: svg('<rect x="3" y="4" width="18" height="16" rx="2"/><circle cx="9" cy="10" r="1.6"/><path d="m4 18 5-5 4 3 3-2 4 4"/>', 24),
    pdf: svg('<path d="M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8l-5-5Z"/><path d="M14 3v5h5M9 13h6M9 17h4"/>', 24),
    equis: svg('<path d="M6 6l12 12M18 6 6 18"/>', 14),
    estrella: svg('<path d="M12 4v16M4 12h16M6.5 6.5l11 11M17.5 6.5l-11 11"/>', 14),
    hoja: svg('<path d="M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8l-5-5Z"/><path d="M14 3v5h5M9 13h6M9 17h4"/>', 26),
  };

  // ── Los archivos: la foto se recodifica (2400 px, 0,8, sin EXIF ni ubicación); el PDF va tal cual ──
  /* Con <img>, como en Gimnasio: el navegador aplica solo la orientación EXIF antes de dibujar. */
  function decodificar(file) {
    return new Promise((ok, no) => {
      const url = URL.createObjectURL(file);
      const img = new Image();
      img.onload = () => ok({ img, listo: () => URL.revokeObjectURL(url) });
      img.onerror = () => { URL.revokeObjectURL(url); no(new Error('no se pudo leer la imagen')); };
      img.src = url;
    });
  }
  function aJpeg(canvas) {
    return new Promise((ok, no) => {
      if (!canvas.toBlob) return no(new Error('sin toBlob'));
      canvas.toBlob((blob) => {
        if (!blob) return no(new Error('no se pudo recodificar'));
        new Response(blob).arrayBuffer().then((a) => ok(new Uint8Array(a)), no);
      }, 'image/jpeg', E.CALIDAD);
    });
  }
  async function prepararFoto(file) {
    const { img, listo } = await decodificar(file);
    const canvas = document.createElement('canvas');
    try {
      const w = img.naturalWidth || img.width, h = img.naturalHeight || img.height;
      if (!w || !h) throw new Error('imagen vacía');
      const esc = Math.min(1, E.MAX_PX / Math.max(w, h));
      canvas.width = Math.max(1, Math.round(w * esc));
      canvas.height = Math.max(1, Math.round(h * esc));
      const c = canvas.getContext('2d');
      c.fillStyle = '#fff';                 // un PNG con transparencia no puede quedar en negro
      c.fillRect(0, 0, canvas.width, canvas.height);
      c.drawImage(img, 0, 0, canvas.width, canvas.height);
      // El canvas ya no copia el EXIF; quitarMetadatos es la segunda llave. Si no entiende el archivo, esa foto no sale.
      const limpio = raiz.Gimnasio.quitarMetadatos(await aJpeg(canvas));
      if (!limpio || E.formato(limpio) !== 'jpeg') throw new Error('no se pudo preparar');
      return new Blob([limpio], { type: E.MIME.jpeg });
    } finally {
      listo();
      canvas.width = canvas.height = 0;     // Safari libera la memoria recién acá
    }
  }
  async function cabecera(file) {
    const b = file.slice(0, 5);
    return new Uint8Array(b.arrayBuffer ? await b.arrayBuffer() : await new Response(b).arrayBuffer());
  }

  /* → 'ok' | 'tope' | 'muyGrande' | 'ilegible' */
  async function sumarArchivo(m, file) {
    if (!m.puedeAgregar) return 'tope';
    let esPdf = false;
    try { esPdf = E.formato(await cabecera(file)) === 'pdf'; } catch (_) { return 'ilegible'; }
    if (esPdf) {
      if (file.size > m.topeMB * 1024 * 1024) return 'muyGrande';
      return m.elegir(file.slice(0, file.size, E.MIME.pdf), 'pdf');
    }
    let foto;
    try { foto = await prepararFoto(file); } catch (_) { return 'ilegible'; }
    return m.elegir(foto, 'jpeg');
  }

  async function procesarArchivos(lista) {
    const m = ui.modelo;
    if (!m || !lista.length) return;
    const hoja = m.hoja;
    ui.error = null;
    ui.preparando += 1;
    renderEscena();
    let aviso = null;
    try {
      for (const f of lista) {
        if (ui.modelo !== m || m.hoja !== hoja) return;      // se cerró la hoja mientras tanto
        const r = await sumarArchivo(m, f);
        if (r === 'tope') { aviso = T.topeArchivos(m.topeArchivos); break; }
        if (r === 'muyGrande') aviso = T.archivoMuyGrande(m.topeMB);
        else if (r === 'ilegible') aviso = T.archivoRechazado;
      }
    } finally {
      ui.preparando -= 1;
      if (ui.modelo === m && m.hoja === hoja) ui.error = aviso;
      renderEscena();
    }
  }

  // Un input con capture= abre la cámara y no deja llegar al carrete: uno por opción, como en Gimnasio.
  const ENTRADAS = {
    camara: { accept: 'image/*', capture: true },
    fotos: { accept: 'image/*', multiple: true },
    pdf: { accept: 'application/pdf,.pdf', multiple: true },
  };
  function pedirArchivos(cual) {
    const id = `estInput-${cual}`;
    let inp = document.getElementById(id);
    if (!inp) {
      const c = ENTRADAS[cual];
      inp = document.createElement('input');
      inp.type = 'file';
      inp.id = id;
      inp.hidden = true;
      inp.tabIndex = -1;
      inp.setAttribute('aria-hidden', 'true');
      inp.accept = c.accept;
      if (c.multiple) inp.multiple = true;
      if (c.capture) inp.setAttribute('capture', 'environment');
      document.body.appendChild(inp);
    }
    inp.onchange = () => {
      const lista = Array.from(inp.files || []);
      inp.value = '';
      procesarArchivos(lista);
    };
    inp.click();
  }

  /* La miniatura de una foto elegida: una URL de memoria que se suelta al quitarla, al enviar o al cerrar la hoja. */
  function vista(x) {
    if (!ui.vistas.has(x.id)) ui.vistas.set(x.id, URL.createObjectURL(x.cuerpo));
    return ui.vistas.get(x.id);
  }
  function podarVistas() {
    const vivos = new Set(ui.modelo ? ui.modelo.borrador.map((x) => x.id) : []);
    for (const [id, url] of ui.vistas) if (!vivos.has(id)) { URL.revokeObjectURL(url); ui.vistas.delete(id); }
  }

  // ── Piezas ──
  const nota = (t, alerta, id) => `<p class="gim-nota${alerta ? ' is-alerta' : ''}"${alerta ? ' role="alert"' : ''}${id ? ` id="${id}"` : ''}>${e(t)}</p>`;
  const errorHtml = () => (ui.error ? nota(ui.error, true, 'estError') : '');
  const h2 = (t, id) => `<h2 class="est-h2" id="${id}">${e(t)}</h2>`;
  const chip = (visto) => `<span class="est-chip${visto ? ' is-visto' : ''}">${visto ? IC.tilde : IC.bandeja}<span>${e(visto ? T.matiLoVio : T.recibido)}</span></span>`;
  /* «Nuevo», con ícono y texto. Se queda puesta durante la visita aunque ya se haya avisado al servidor. */
  const esNueva = (x) => x.nuevo || ui.nuevasDeLaVisita.has(x.id);
  const etiquetaNuevo = () => `<span class="est-chip is-nuevo">${IC.estrella}<span>${e(T.nuevo)}</span></span>`;
  /* `data-tarjeta`: adónde se lleva la pantalla al llegar por el aviso. `data-nueva`: lo que se mira para marcarla vista. */
  const marcas = (x) => ` data-tarjeta="${e(x.id)}"${x.nuevo ? ' data-nueva="1"' : ''}`;
  const pildora = (texto, accion, id, extra = '') => `<button type="button" class="est-pildora${extra}" data-est="${accion}"${id ? ` data-id="${e(id)}"` : ''}${ui.ocupado ? ' disabled' : ''}>${e(texto)}</button>`;

  const TEXTO_AVISO = {
    recibido: () => T.envioRecibido,
    recibidoConRechazo: () => `${T.envioRecibido} ${T.archivoRechazado}`,
    rechazado: () => T.archivoRechazado,
    topeDia: () => T.topeDia,
    error: () => T.noSePudoEnviar,
  };
  function avisoHtml(m) {
    const f = TEXTO_AVISO[m.aviso];
    if (!f) return '';
    const bien = m.aviso === 'recibido' || m.aviso === 'recibidoConRechazo';
    return `<div class="est-banda${bien ? ' is-bien' : ''}" id="estAviso" role="status">${bien ? IC.tilde : ''}<span>${e(f())}</span>
      <button type="button" class="est-x" data-est="cerrarAviso" aria-label="${e(T.cerrar)}">${IC.equis}</button></div>`;
  }

  function colaHtml(m) {
    if (!m.cola.length) return '';
    // Lo que falta subir vive solo en la memoria de esta página, y en un teléfono el navegador no pregunta antes de cerrarla.
    const noCierres = `<small class="est-banda-nota" id="estNoCierres">${e(T.noCierres)}</small>`;
    if (m.subiendo) return `<div class="est-banda" id="estCola" role="status"><div class="spinner est-spinner" aria-hidden="true"></div><span>${e(m.progreso)}${noCierres}</span></div>`;
    if (m.sinSenal) return `<div class="est-banda" id="estCola" role="status"><span>${e(T.sinSenal)}${noCierres}</span></div>`;
    return `<div class="est-banda" id="estCola" role="status"><span>${e(T.noSePudoEnviar)}${noCierres}</span>${pildora(T.probarDeNuevo, 'reanudar')}</div>`;
  }

  function pendienteHtml(p, hoy, i) {
    const f = E.fechaPendiente(p.desde, p.hasta, hoy);
    const linea = p.hecho ? `<p class="est-linea">${IC.tilde}<span>${e(E.hecho(p.hechoFecha))}</span></p>`
      : f ? `<p class="est-linea${f.pasada ? ' is-pasada' : ''}">${f.pasada ? IC.reloj : IC.calendario}<span>${e(f.texto)}</span></p>` : '';
    return `<article class="est-tarjeta${esNueva(p) ? ' is-nueva' : ''}" aria-labelledby="estPend${i}" tabindex="-1"${marcas(p)}>
      ${esNueva(p) ? etiquetaNuevo() : ''}<h3 class="est-h3" id="estPend${i}">${e(p.titulo)}</h3>
      ${p.detalle ? `<p class="gim-sub">${e(p.detalle)}</p>` : ''}${linea}
      <button type="button" class="btn-primary" data-est="subirResultado" data-id="${e(p.id)}">${IC.subir}<span>${e(T.subirResultado)}</span></button>
      <div class="est-botones">${p.hecho ? pildora(T.deshacer, 'deshacer', p.id) : pildora(T.yaMeLoHice, 'hecho', p.id)}${p.ordenId ? pildora(T.verOrden, 'verOrden', p.ordenId, ' is-verde') : ''}</div>
    </article>`;
  }

  function ordenHtml(o) {
    if (!o.vigente) return `<div class="est-fila is-vencida"><span class="est-fila-txt"><strong>${e(o.titulo)}</strong><small>${e(T.ordenVencida)}</small></span></div>`;
    return `<button type="button" class="est-fila" data-est="orden" data-id="${e(o.id)}"${marcas(o)}><span class="est-fila-txt">${esNueva(o) ? etiquetaNuevo() : ''}<strong>${e(o.titulo)}</strong><small>${e(E.detalleOrden(o))}</small></span><span class="md-chev">${IC.chev}</span></button>`;
  }

  function estudioHtml(x) {
    const dentro = `<span class="est-fila-txt"><strong>${e(x.titulo)}</strong><small>${e(E.detalleEstudio(x))}</small>${chip(x.visto)}</span>`;
    if (!x.sePuedeAbrir) return `<div class="est-fila">${dentro}</div>`;
    return `<button type="button" class="est-fila" data-est="verEstudio" data-id="${e(x.id)}">${dentro}<span class="est-ver">${e(T.ver)}</span></button>`;
  }

  const envioHtml = (x) => `<div class="est-fila"><span class="est-fila-txt"><strong>${e(E.tituloEnvio(x))}</strong>${E.archivos(x.archivos) ? `<small>${e(E.archivos(x.archivos))}</small>` : ''}${chip(false)}</span></div>`;

  function pLista(m) {
    const s = m.estado, b = E.bloques(s), pc = s.proximoControl;
    const cuando = pc ? (pc.cuando || E.fechaControl(pc.desde, pc.hasta)) : null;
    return `${avisoHtml(m)}
      ${m.errorDeCarga ? `<div class="est-banda" id="estErrorCarga" role="alert"><span>${e(T.errorDeCarga)}</span>${pildora(T.probarDeNuevo, 'recargar')}</div>` : ''}
      ${errorHtml()}
      ${pc ? `<div class="est-tarjeta est-control" id="estControl"><span class="est-control-ic">${IC.calendario}</span>
        <span class="est-fila-txt"><span class="est-ceja">${e(T.proximoControl)}</span><strong>${e(pc.titulo)}</strong>${cuando ? `<small id="estControlCuando">${e(cuando)}</small>` : ''}${pc.nota ? `<small class="est-control-nota" id="estControlNota">${e(pc.nota)}</small>` : ''}</span></div>` : ''}
      ${b.pendientes ? h2(T.teFaltaHacer, 'estFalta') + s.pendientes.map((p, i) => pendienteHtml(p, s.hoy, i)).join('') : ''}
      ${colaHtml(m)}
      <button type="button" class="btn-primary est-principal" data-est="subir" id="estSubir">${IC.subir}<span>${e(T.subirEstudio)}</span></button>
      ${b.vacio && !m.cola.length ? `<p class="est-vacio" id="estVacio">${e(T.vacio)}</p>` : ''}
      ${b.ordenes ? `${h2(T.tusOrdenes, 'estOrdenes')}<div class="est-grupo" role="group" aria-labelledby="estOrdenes">${s.ordenes.map(ordenHtml).join('')}</div>` : ''}
      ${b.estudios ? `${h2(T.tusEstudios, 'estEstudios')}<div class="est-grupo" role="group" aria-labelledby="estEstudios">${E.enviosVisibles(s).map(envioHtml).join('')}${s.estudios.map(estudioHtml).join('')}</div>
        <p class="est-nota" id="estNota">${e(T.notaRecibido)}</p>` : ''}`;
  }

  const puntos = (l) => `<ul class="est-puntos">${l.map((x) => `<li>${e(x)}</li>`).join('')}</ul>`;

  function pOrden(m, id) {
    const o = m.orden(id);
    if (!o || !o.vigente) { ui.pila = []; return pLista(m); }
    return `<h2 class="est-h1" id="estTitulo" tabindex="-1">${e(o.titulo)}</h2>
      ${E.detalleOrden(o) ? `<p class="gim-sub" id="estDetalleOrden">${e(E.detalleOrden(o))}</p>` : ''}
      ${errorHtml()}
      <button type="button" class="btn-primary" data-est="verOrden" data-id="${e(o.id)}" id="estVerOrden"${ui.abriendo ? ' disabled' : ''}>${IC.pdf}<span>${e(T.verOrden)}</span></button>
      <section class="est-tarjeta" aria-labelledby="estPrep"><h3 class="est-h3" id="estPrep">${e(T.comoPrepararte)}</h3>${puntos(E.preparacion(o.tipo))}</section>
      <section class="est-tarjeta" aria-labelledby="estDonde"><h3 class="est-h3" id="estDonde">${e(T.dondeHacerlo)}</h3>${puntos(E.donde(o.tipo))}</section>`;
  }

  function pSubir(m, d) {
    const n = m.borrador.length, lleno = !m.puedeAgregar;
    let fotos = 0, pdfs = 0;
    const opcion = (cual, ic, texto) => `<button type="button" class="est-opcion" data-est="elegir" data-cual="${cual}"${lleno ? ' disabled' : ''}>${ic}<span>${e(texto)}</span></button>`;
    return `<h2 class="est-h1" id="estTitulo" tabindex="-1">${e(d.pedidoId ? T.subirResultado : T.subirEstudio)}</h2>
      <p class="est-guia" id="estGuia">${e(T.guiaSubida)}</p>
      ${nota(T.topeArchivos(m.topeArchivos), false, 'estTope')}
      <div class="est-opciones">${opcion('camara', IC.camara, T.sacarFotos)}${opcion('fotos', IC.fotos, T.elegirFotos)}${opcion('pdf', IC.pdf, T.elegirPDF)}</div>
      ${n ? `<ul class="est-grupo est-archivos" id="estArchivos">${m.borrador.map((x) => {
        const nombre = x.formato === 'pdf' ? T.pdf(++pdfs) : T.foto(++fotos);
        return `<li class="est-fila"><span class="est-mini">${x.formato === 'pdf' ? IC.pdf : `<img src="${e(vista(x))}" alt="">`}</span><span class="est-fila-txt"><strong>${e(nombre)}</strong></span>
          <button type="button" class="est-pildora" data-est="quitar" data-id="${e(x.id)}" aria-label="${e(`${T.quitar} ${nombre}`)}">${e(T.quitar)}</button></li>`;
      }).join('')}</ul>` : ''}
      ${ui.preparando ? '<div class="est-preparando" id="estPreparando" aria-busy="true"><div class="spinner est-spinner" aria-hidden="true"></div></div>' : ''}
      ${errorHtml()}
      ${n ? `<button type="button" class="btn-primary est-principal" data-est="enviar" id="estEnviar"${ui.preparando ? ' disabled' : ''}>${e(T.enviarArchivos(n))}</button>` : ''}
      <button type="button" class="est-pildora est-cancelar" data-est="volver" id="estCancelar">${e(T.cancelar)}</button>`;
  }

  /* Varias hojas, o una ventana que el navegador no dejó abrir: las fotos se ven acá y cada PDF se abre con su botón.
     Cada `a.url` es una URL de memoria (blob:), nunca la firmada; se suelta al salir o a los 9 minutos. */
  function pVisor(d) {
    let fotos = 0, pdfs = 0;
    const uno = d.archivos.length === 1;
    return `<h2 class="est-h1" id="estTitulo" tabindex="-1">${e(d.titulo)}</h2>
      ${d.archivos.map((a) => (a.pdf
        ? `<a class="btn-primary est-enlace" href="${e(a.url)}" target="_blank" rel="noopener">${IC.pdf}<span>${e(uno ? d.rotulo : T.pdf(++pdfs))}</span></a>`
        : `<img class="est-hoja" src="${e(a.url)}" alt="${e(T.foto(++fotos))}">`)).join('')}`;
  }

  // ── Armar y pintar ──
  const tope = () => ui.pila[ui.pila.length - 1] || null;

  function cuerpo(m) {
    const d = tope();
    if (d && d.t === 'orden') return pOrden(m, d.id);
    if (d && d.t === 'subir') return pSubir(m, d);
    if (d && d.t === 'visor') return pVisor(d);
    return pLista(m);
  }

  function raizEscena() { return document.getElementById('scene-estudios'); }
  function escenaActiva() { const r = raizEscena(); return !!r && r.classList.contains('is-active'); }

  function renderEscena() {
    const r = raizEscena(), m = ui.modelo;
    if (!r) return;
    if (!m || !m.estado) { r.innerHTML = ''; ui.ultimoHtml = null; ui.pila = []; soltarVisor(); podarVistas(); if (escenaActiva()) cerrar(); return; }
    // No se le rehace la pantalla bajo el dedo: el toque se perdería.
    if (ui.presionando) { ui.pendiente = true; return; }
    ui.pendiente = false;
    const volver = ui.pila.length ? T.titulo : T.cerrar;
    const h = `<div class="gim est"><button type="button" class="sd-volver" data-est="volver" id="estVolver">‹ ${e(volver)}</button>${cuerpo(m)}</div>`;
    if (h !== ui.ultimoHtml) {
      const foco = document.activeElement && r.contains(document.activeElement) ? document.activeElement : null;
      const clave = foco ? [foco.getAttribute('data-est'), foco.getAttribute('data-id'), foco.getAttribute('data-cual')] : null;
      r.innerHTML = h;
      ui.ultimoHtml = h;
      // El foco del teclado no se pierde al repintar: vuelve al mismo botón si sigue estando.
      if (clave && clave[0]) {
        const mismo = Array.from(r.querySelectorAll(`[data-est="${escCss(clave[0])}"]`)).find((b) => b.getAttribute('data-id') === clave[1] && b.getAttribute('data-cual') === clave[2] && !b.disabled);
        if (mismo) mismo.focus({ preventScroll: true });
      }
    }
    podarVistas();
    const t = document.getElementById('hdrTitle');
    if (t && escenaActiva()) t.textContent = T.titulo;      // al soltar el visor desde otra sección no se le pisa el título
    vigilarNuevas();
  }

  // ── Novedades: marcar vista la tarjeta que estuvo de verdad en pantalla ──
  const enLista = () => escenaActiva() && !ui.pila.length && document.visibilityState === 'visible';

  /* ¿Se ve? Al menos la mitad de la tarjeta (o media pantalla, si es más alta que la pantalla). Con `entera`, toda. */
  function aLaVista(el, entera) {
    if (!el.getBoundingClientRect) return false;
    const c = el.getBoundingClientRect();
    const alto = raiz.innerHeight || (document.documentElement && document.documentElement.clientHeight) || 0;
    const ancho = raiz.innerWidth || (document.documentElement && document.documentElement.clientWidth) || 0;
    if (!alto || !(c.height > 0) || c.right <= 0 || c.left >= ancho) return false;
    // Lo que queda debajo del encabezado fijo o de la barra de pestañas no se ve.
    const cab = document.getElementById('appHeader'), barra = document.querySelector('.tabbar');
    const techo = cab && cab.getBoundingClientRect ? Math.max(0, cab.getBoundingClientRect().bottom) : 0;
    const piso = barra && barra.getBoundingClientRect ? Math.min(alto, barra.getBoundingClientRect().top) : alto;
    const visto = Math.min(c.bottom, piso) - Math.max(c.top, techo);
    return visto >= Math.min(c.height, piso - techo) / (entera ? 1 : 2) - (entera ? 1 : 0);
  }

  function dejarDeMirar() {
    for (const r of ui.mirando.values()) clearTimeout(r);
    ui.mirando.clear();
  }

  /* Las que se están viendo empiezan a contar; las que dejaron de verse, no cuentan. */
  function mirar() {
    const r = raizEscena(), m = ui.modelo;
    const vivas = new Set();
    if (r && m && m.estado && enLista()) {
      for (const el of Array.from(r.querySelectorAll('[data-nueva]'))) {
        const id = el.getAttribute('data-tarjeta');
        if (!id || !aLaVista(el)) continue;
        vivas.add(id);
        if (!ui.mirando.has(id)) ui.mirando.set(id, setTimeout(() => { ui.mirando.delete(id); vista1(id); }, MIRADA_MS));
      }
    }
    for (const [id, reloj] of ui.mirando) if (!vivas.has(id)) { clearTimeout(reloj); ui.mirando.delete(id); }
  }

  /* Pasó el rato: si sigue a la vista, se avisa. Si la llamada falla, vuelve a contar la próxima vez que se pinte o se mueva. */
  function vista1(id) {
    const r = raizEscena(), m = ui.modelo;
    if (!r || !m || !m.estado || !enLista()) return;
    const el = Array.from(r.querySelectorAll('[data-nueva]')).find((x) => x.getAttribute('data-tarjeta') === id);
    if (!el || !aLaVista(el)) return;
    ui.nuevasDeLaVisita.add(id);
    // Las que se vieron juntas salen en una sola llamada.
    ui.porAvisar.add(id);
    if (!ui.relojAviso) ui.relojAviso = setTimeout(() => {
      ui.relojAviso = null;
      const ids = Array.from(ui.porAvisar);
      ui.porAvisar.clear();
      if (ui.modelo === m && ids.length) m.marcarVistas(ids).catch(() => {});
    }, JUNTAR_MS);
  }

  /* Tras cada pintada: se vuelve a mirar, y el observador sigue a las tarjetas nuevas de ahora. Sin IntersectionObserver
     se mira al desplazar (ver `enganchar`). */
  function vigilarNuevas() {
    const r = raizEscena();
    if (!r) return;
    if (ui.ojo && ui.ojoDe !== ui.ultimoHtml) { ui.ojo.disconnect(); ui.ojo = null; }
    const l = enLista() ? Array.from(r.querySelectorAll('[data-nueva]')) : [];
    if (!l.length) { if (ui.ojo) { ui.ojo.disconnect(); ui.ojo = null; } dejarDeMirar(); return; }
    if (!ui.ojo && raiz.IntersectionObserver) {
      ui.ojo = new raiz.IntersectionObserver(() => mirar(), { threshold: [0, 0.25, 0.5, 0.75, 1] });
      ui.ojoDe = ui.ultimoHtml;
      l.forEach((el) => ui.ojo.observe(el));
    }
    mirar();
  }

  /* Al llegar por el aviso: la tarjeta queda a la vista y con el foco (el lector de pantalla la anuncia). Si ya se ve
     entera no se mueve nada (arriba quedan «Cerrar» y el título); si no, se la lleva arriba de todo. */
  function mostrarTarjeta() {
    const r = raizEscena(), m = ui.modelo;
    if (!ui.apuntar || !r || !m || !m.estado || ui.pila.length || !escenaActiva()) return;
    const d = ui.apuntar === 'llegada' ? E.tarjetaDeLlegada(m.estado) : E.primeraNueva(m.estado);
    const el = d && Array.from(r.querySelectorAll('[data-tarjeta]')).find((x) => x.getAttribute('data-tarjeta') === d.id);
    if (!el) return;
    // El encabezado es fijo y cambia de alto con la letra: se mide para que no tape la tarjeta.
    const cab = document.getElementById('appHeader');
    if (cab && r.style) r.style.setProperty('--est-encabezado', `${cab.offsetHeight || 0}px`);
    if (el.scrollIntoView && !aLaVista(el, true)) el.scrollIntoView({ block: 'start' });
    if (el.focus) el.focus({ preventScroll: true });
    mirar();
  }

  // ── El aviso de arriba en la pantalla principal ──
  /* Mismo lugar y patrón que la novedad destacada de la guía: tarjeta verde con un botón blanco grande. Toda la tarjeta
     lleva a Estudios, a la tarjeta en cuestión. Quien la pinta de nuevo (renderTrain rehace todo) la vuelve a poner. */
  function montarTarjeta(root) {
    let host = document.getElementById('estHost');
    const a = ui.modelo && ui.modelo.estado ? ui.modelo.tarjetaInicio : null;
    if (!root || !a) { if (host) host.remove(); return; }
    if (!host) {
      host = document.createElement('div');
      host.id = 'estHost';
      host.addEventListener('click', () => abrir({ desde: 'train', llegada: true }));
    }
    const html = `<div class="est-aviso${a.novedad ? ' is-novedad' : ''}" role="group" aria-label="${e(T.entradaMisDatos)}">
      <div class="est-aviso-fila"><span class="est-aviso-ic" aria-hidden="true">${IC.hoja}</span>
        <div class="est-aviso-txt"><span class="est-aviso-ceja">${a.novedad ? `<span class="est-punto" role="img" aria-label="${e(T.novedad)}"></span>` : ''}${e(T.entradaMisDatos)}</span><strong class="est-aviso-tit">${e(a.titulo)}</strong></div></div>
      <button type="button" class="est-aviso-btn" id="estAvisoBtn">${e(a.boton)}</button></div>`;
    if (host.dataset.h !== html) { host.innerHTML = html; host.dataset.h = html; }
    if (root.firstChild !== host) root.insertBefore(host, root.firstChild);
  }

  /* «Tu próximo control de salud» (`controles_app`): desde `avisar_desde` y mientras siga programado, debajo de la de
     Estudios (o primera, si no hay). Mismo patrón verde con el botón blanco grande «Ver mis estudios»: un toque a Estudios. */
  function montarControl(root) {
    let host = document.getElementById('ctlHost');
    const C = raiz.Controles;
    const a = C && ui.modelo && ui.modelo.estado ? ui.modelo.tarjetaControl : null;
    if (!root || !a) { if (host) host.remove(); return; }
    if (!host) {
      host = document.createElement('div');
      host.id = 'ctlHost';
      host.addEventListener('click', () => abrir({ desde: 'train' }));
    }
    const html = `<div class="est-aviso est-aviso-control" role="group" aria-label="${e(a.titulo)}">
      <div class="est-aviso-fila"><span class="est-aviso-ic" aria-hidden="true">${svg('<rect x="3" y="5" width="18" height="16" rx="3"/><path d="M3 10h18M8 3v4M16 3v4"/>', 26)}</span>
        <div class="est-aviso-txt"><span class="est-aviso-ceja">${e(C.T.cejaInicio)}</span><strong class="est-aviso-tit" id="ctlTitulo">${e(a.titulo)}</strong>
        <strong class="est-aviso-cuando" id="ctlCuando">${e(a.cuando)}</strong></div></div>
      <p class="est-aviso-nota" id="ctlNota">${e(a.nota)}</p>
      <button type="button" class="est-aviso-btn" id="ctlBoton">${e(a.boton)}</button></div>`;
    if (host.dataset.h !== html) { host.innerHTML = html; host.dataset.h = html; }
    // Justo debajo de la de Estudios si está; si no, primera. Solo se mueve si no está ya ahí (no titila).
    const est = document.getElementById('estHost');
    const conEst = !!est && est.parentNode === root;
    const enSuLugar = conEst ? est.nextSibling === host : root.firstChild === host;
    if (!enSuLugar) root.insertBefore(host, conEst ? est.nextSibling : root.firstChild);
  }

  /* Destino `estudios` (el clic del aviso o `?scene=estudios`), también al abrir en frío: quien llama ya dejó a la vista
     la pantalla de caída (Mis datos). En cuanto se sabe que la cuenta tiene la sección, se abre en la tarjeta nueva. Si
     la palanca está apagada, la cuenta no la tiene, el `get` no contesta a tiempo o el alumno ya se fue a otra pantalla,
     se queda donde está. */
  function destino(caida) {
    ui.destino = { caida: caida || 'misdatos', hasta: Date.now() + ESPERA_DESTINO_MS };
    cumplirDestino();
  }
  function cumplirDestino() {
    const d = ui.destino;
    if (!d) return;
    if (Date.now() > d.hasta || (ui.op && ui.op.escena && ui.op.escena() !== d.caida)) { ui.destino = null; return; }
    if (!ui.op || !ui.modelo || !ui.modelo.estado) return;
    ui.destino = null;
    abrir({ desde: d.caida, llegada: true, fresco: true });
  }

  function pintar() {
    if (!ui.op) return;
    const m = ui.modelo;
    const a = m && m.estado ? m.tarjetaInicio : null;
    montarTarjeta(document.getElementById('scene-train'));
    montarControl(document.getElementById('scene-train'));
    const firma = m && m.estado ? `1|${m.pendientes}|${m.novedad ? 1 : 0}|${a ? a.titulo : ''}` : '';
    if (firma !== ui.firmaEntrada) { ui.firmaEntrada = firma; ui.op.alCambiarEntrada(); }
    cumplirDestino();
    if (escenaActiva()) renderEscena();
  }

  /* Suelta de la memoria todo archivo abierto (la pestaña de una orden ya lo cargó y lo sigue mostrando). */
  function soltarVisor() {
    if (ui.relojVisor) { clearTimeout(ui.relojVisor); ui.relojVisor = null; }
    for (const u of ui.sueltas) { try { URL.revokeObjectURL(u); } catch (_) {} }
    ui.sueltas = [];
  }
  /* Al salir de la sección, al irse la página o a los 9 minutos: no queda ni la pantalla del archivo. */
  function cerrarVisor() {
    if (tope() && tope().t === 'visor') { ui.pila.pop(); ui.error = null; }
    soltarVisor();
    if (ui.modelo) renderEscena();
  }

  const aquietar = () => { ui.quietoHasta = Date.now() + QUIETO_MS; };

  function apilar(d) {
    aquietar();
    ui.pila.push(d);
    ui.error = null;
    renderEscena();
    window.scrollTo(0, 0);
    const t = document.getElementById('estTitulo');
    if (t) t.focus({ preventScroll: true });      // el lector de pantalla anuncia la pantalla nueva
  }

  function desapilar() {
    aquietar();
    const d = ui.pila.pop();
    if (d && d.t === 'subir' && ui.modelo) ui.modelo.descartarBorrador();
    if (d && d.t === 'visor') soltarVisor();
    ui.error = null;
    renderEscena();
    window.scrollTo(0, 0);
  }

  /* op: { desde: 'misdatos' | 'train', llegada: se entra por el aviso, fresco: el `get` acaba de llegar }.
     Siempre que haya una tarjeta nueva, la pantalla se abre con esa a la vista; por el aviso, si no hay nueva, con el
     primer pendiente. */
  function abrir(op = {}) {
    const m = ui.modelo;
    if (!m || !m.estado) return;
    aquietar();                                   // el segundo toque de un doble toque en Mis datos no cae en un botón de acá
    ui.origen = op.desde === 'train' ? 'train' : 'misdatos';
    ui.destino = null;
    ui.pila = [];
    ui.error = null;
    ui.nuevasDeLaVisita.clear();
    ui.apuntar = op.llegada ? 'llegada' : 'nueva';
    soltarVisor();
    m.limpiarAviso();
    m.descartarBorrador();
    ui.op.irA('estudios');
    mostrarTarjeta();
    const despues = () => { if (ui.modelo !== m) return null; mostrarTarjeta(); return m.drenar(); };
    if (op.fresco && Date.now() - ui.ultimoRefresco < 5000) { Promise.resolve().then(despues).catch(() => {}); return; }
    ui.ultimoRefresco = Date.now();
    m.refrescar().then(despues).catch(() => {});
  }

  function cerrar() { if (ui.op) ui.op.irA(ui.origen); }

  /* La URL firmada se pide recién al tocar y no sale de la memoria: cada archivo se baja sin caché a un Blob y lo que
     se muestra o se abre es ese Blob. Así no queda ni en el historial (que se sincroniza) ni en el caché de disco.
     La orden (un PDF) se abre en una pestaña, que hay que abrir en el mismo toque, antes de esperar al servidor, o el
     navegador la bloquea; un estudio, que puede traer varias hojas, y la orden cuando la pestaña no se pudo abrir, se
     ven en la pantalla. */
  async function bajarTodos(m, archivos) {
    const l = [];
    for (const a of archivos) {
      const blob = await m.bajar(a);
      if (!blob) return null;
      l.push({ blob, pdf: a.pdf });
    }
    return l;
  }

  async function abrirArchivos(clase, id, titulo, rotulo, pestana) {
    const m = ui.modelo;
    if (ui.abriendo || !m) return;
    ui.abriendo = true;
    ui.error = null;
    renderEscena();
    let w = null;
    if (pestana) { try { w = window.open('', '_blank'); } catch (_) { w = null; } }
    let r = 'error', bajados = null;
    try {
      r = await m.urls(clase, id);
      if (typeof r !== 'string') bajados = await bajarTodos(m, r.archivos);
    } finally { ui.abriendo = false; }
    const cerrarVentana = () => { try { if (w && !w.closed) w.close(); } catch (_) {} };
    if (ui.modelo !== m || !m.estado) { cerrarVentana(); return; }
    if (!escenaActiva()) { cerrarVentana(); renderEscena(); return; }      // se fue de la sección mientras bajaba
    if (typeof r === 'string' || !bajados) {
      cerrarVentana();
      // Todavía no se puede abrir: es de Mati, no un error.
      ui.error = r === 'todaviaNo' ? T.envioRecibido : T.noSePudoAbrir;
      renderEscena();
      return;
    }
    if (tope() && tope().t === 'visor') ui.pila.pop();
    soltarVisor();
    const archivos = bajados.map((x) => ({ url: URL.createObjectURL(x.blob), pdf: x.pdf }));
    ui.sueltas = archivos.map((a) => a.url);
    ui.relojVisor = setTimeout(cerrarVisor, VIDA_VISOR_MS);
    if (archivos.length === 1 && w && !w.closed) {
      try { w.opener = null; } catch (_) {}
      try { w.location.replace(archivos[0].url); renderEscena(); return; } catch (_) { cerrarVentana(); }
    } else cerrarVentana();
    apilar({ t: 'visor', titulo, rotulo, archivos });
  }

  // ── «Ya me lo hice»: la fecha ──
  function hoyIso(m) {
    if (m.estado && m.estado.hoy) return E.iso(m.estado.hoy);
    const d = new Date();
    return E.iso({ anio: d.getFullYear(), mes: d.getMonth() + 1, dia: d.getDate() });
  }

  function hojaFecha(pedidoId, origen) {
    const m = ui.modelo;
    const hoy = hoyIso(m);
    const ov = document.createElement('div');
    ov.className = 'fp-pick';
    ov.id = 'estHojaFecha';
    ov.innerHTML = `<div class="fp-pick-card est-hoja-fecha" role="dialog" aria-modal="true" aria-labelledby="estFechaTit">
      <label class="fp-pick-tit" id="estFechaTit" for="estFecha">${e(T.cuandoTeLoHiciste)}</label>
      <input type="date" class="est-fecha" id="estFecha" max="${hoy}" value="${hoy}" aria-describedby="estFechaError">
      <p class="gim-nota is-alerta" id="estFechaError" role="alert"></p>
      <button type="button" class="btn-primary" id="estFechaGuardar">${e(T.guardar)}</button>
      <button type="button" class="fp-pick-btn is-cancel" id="estFechaCancelar">${e(T.cancelar)}</button></div>`;
    const q = (s) => ov.querySelector(s);
    let guardando = false;
    // El segundo toque de un doble toque en «Ya me lo hice» cae sobre la hoja recién abierta: no guarda ni la cierra.
    const quietaHasta = Date.now() + QUIETO_MS;
    const quieta = () => Date.now() < quietaHasta;
    const salir = () => {
      aquietar();                                 // ni el de «Cancelar» cae en el botón que quedó debajo
      document.removeEventListener('keydown', teclas, true);
      ov.remove();
      if (origen && document.contains(origen)) origen.focus({ preventScroll: true });
      else { const b = document.querySelector(`#scene-estudios [data-id="${escCss(pedidoId)}"]`); if (b) b.focus({ preventScroll: true }); }
    };
    function teclas(ev) {
      if (ev.key === 'Escape') { ev.preventDefault(); if (!guardando) salir(); return; }
      if (ev.key !== 'Tab') return;
      // El foco no sale de la hoja mientras está abierta.
      const f = [q('#estFecha'), q('#estFechaGuardar'), q('#estFechaCancelar')].filter((x) => !x.disabled);
      const i = f.indexOf(document.activeElement);
      ev.preventDefault();
      f[(i + (ev.shiftKey ? -1 : 1) + f.length) % f.length].focus();
    }
    ov.addEventListener('click', (ev) => { if (!quieta() && (ev.target === ov || ev.target.id === 'estFechaCancelar') && !guardando) salir(); });
    q('#estFechaGuardar').addEventListener('click', async () => {
      if (guardando || quieta()) return;
      const valor = q('#estFecha').value;
      const error = q('#estFechaError');
      if (!E.dia(valor) || valor > hoy) { error.textContent = T.revisaLaFecha; return; }
      guardando = true;
      q('#estFechaGuardar').disabled = true;
      error.textContent = '';
      const r = await m.marcarHecho(pedidoId, valor).catch(() => 'error');
      guardando = false;
      if (r === 'ok') return salir();
      q('#estFechaGuardar').disabled = false;
      error.textContent = r === 'fecha' ? T.revisaLaFecha : T.noSePudoGuardar;
    });
    document.addEventListener('keydown', teclas, true);
    document.body.appendChild(ov);
    q('#estFecha').focus();
  }

  // ── Toques ──
  const ACCIONES = {
    volver() { if (ui.pila.length) desapilar(); else cerrar(); },
    cerrarAviso() { ui.modelo.limpiarAviso(); },
    recargar() { ui.ultimoRefresco = Date.now(); return ui.modelo.refrescar(); },
    reanudar() { return ui.modelo.reanudar(); },
    subir() { ui.modelo.limpiarAviso(); ui.modelo.descartarBorrador(); apilar({ t: 'subir', pedidoId: null }); },
    subirResultado(b) { ui.modelo.limpiarAviso(); ui.modelo.descartarBorrador(); apilar({ t: 'subir', pedidoId: b.dataset.id }); },
    hecho(b) { hojaFecha(b.dataset.id, b); },
    async deshacer(b) {
      if (ui.ocupado) return;
      ui.ocupado = true;
      ui.error = null;
      renderEscena();
      let r = 'error';
      try { r = await ui.modelo.marcarHecho(b.dataset.id, null); } finally { ui.ocupado = false; }
      if (r !== 'ok') ui.error = T.noSePudoGuardar;
      renderEscena();
    },
    orden(b) { apilar({ t: 'orden', id: b.dataset.id }); },
    verOrden(b) {
      const o = ui.modelo.orden(b.dataset.id);
      return abrirArchivos('orden', b.dataset.id, o ? o.titulo : T.verOrden, T.verOrden, true);
    },
    verEstudio(b) {
      const x = ui.modelo.estado.estudios.find((s) => s.id === b.dataset.id);
      if (!x || !x.sePuedeAbrir) return null;
      return abrirArchivos('estudio', x.id, x.titulo, T.ver, false);
    },
    elegir(b) { ui.error = null; pedirArchivos(b.dataset.cual); },      // sincrónico: en iOS el selector tiene que salir del mismo toque
    quitar(b) { ui.error = null; ui.modelo.quitar(b.dataset.id); renderEscena(); },
    enviar() {
      const m = ui.modelo, d = tope();
      if (!d || d.t !== 'subir' || ui.preparando) return null;
      // `enviar` vacía la hoja en el acto: un segundo toque no encuentra nada que mandar.
      if (!m.enviar(d.pedidoId)) return null;
      aquietar();
      ui.pila = [];
      ui.error = null;
      renderEscena();
      window.scrollTo(0, 0);
      return m.drenar();
    },
  };

  function enganchar() {
    if (ui.enganchado) return;
    ui.enganchado = true;
    const r = raizEscena();
    if (r) {
      r.addEventListener('click', (ev) => {
        const b = ev.target.closest('[data-est]');
        if (!b || b.disabled || !ui.modelo || !ui.modelo.estado || Date.now() < ui.quietoHasta) return;
        const f = ACCIONES[b.dataset.est];
        if (f) { const p = f(b); if (p && p.catch) p.catch(() => {}); }
      });
      const repintarPendiente = () => setTimeout(() => { if (ui.pendiente && ui.modelo && escenaActiva()) renderEscena(); }, 60);
      // En cuanto toca o desplaza, la pantalla no se le mueve más sola.
      const soltarMira = () => { ui.apuntar = false; };
      r.addEventListener('pointerdown', () => { ui.presionando = true; soltarMira(); }, true);
      r.addEventListener('touchstart', soltarMira, { passive: true });
      window.addEventListener('wheel', soltarMira, { passive: true });
      // Sin IntersectionObserver, y también al girar o agrandar la pantalla: se mira qué tarjeta nueva quedó a la vista.
      let frenoMira = 0;
      const alMover = () => { if (frenoMira || !ui.modelo || !escenaActiva()) return; frenoMira = setTimeout(() => { frenoMira = 0; mirar(); }, 200); };
      window.addEventListener('scroll', alMover, { passive: true });
      window.addEventListener('resize', alMover, { passive: true });
      const soltar = () => { if (!ui.presionando) return; ui.presionando = false; repintarPendiente(); };
      window.addEventListener('pointerup', soltar, true);
      window.addEventListener('pointercancel', soltar, true);
      // «Deslizá para reintentar»: tirar hacia abajo desde arriba de todo, en la lista.
      r.addEventListener('touchstart', (ev) => { ui.tiron = !ui.pila.length && window.scrollY <= 0 && ev.touches.length === 1 ? ev.touches[0].clientY : null; }, { passive: true });
      r.addEventListener('touchend', (ev) => {
        const y0 = ui.tiron;
        ui.tiron = null;
        if (y0 === null || !ui.modelo || !ev.changedTouches.length || window.scrollY > 0) return;
        if (ev.changedTouches[0].clientY - y0 >= TIRON_PX) { ui.ultimoRefresco = Date.now(); ui.modelo.refrescar().catch(() => {}); }
      }, { passive: true });
    }
    // Al salir de la sección (o irse la página) se suelta lo abierto.
    if (r && raiz.MutationObserver) new raiz.MutationObserver(() => { if (!escenaActiva()) { cerrarVisor(); dejarDeMirar(); ui.apuntar = false; } }).observe(r, { attributes: true, attributeFilter: ['class'] });
    window.addEventListener('pagehide', cerrarVisor);
    window.addEventListener('online', () => { if (ui.modelo) ui.modelo.reanudar().catch(() => {}); });
    document.addEventListener('visibilitychange', () => {
      const m = ui.modelo;
      if (document.visibilityState !== 'visible') { dejarDeMirar(); return; }
      if (!m) return;
      mirar();
      if (Date.now() - ui.ultimoRefresco > SEG_ENTRE_REFRESCOS * 1000) { ui.ultimoRefresco = Date.now(); m.refrescar().then(() => m.drenar()).catch(() => {}); }
      else m.drenar().catch(() => {});
    });
    // Los archivos de un envío a medias viven solo en esta página: el navegador pregunta antes de cerrarla.
    window.addEventListener('beforeunload', (ev) => {
      if (!ui.modelo || !ui.modelo.cola.length) return;
      ev.preventDefault();
      ev.returnValue = '';
    });
  }

  /* El primer `get` no llegó a contestar (un corte al abrir): se pregunta un par de veces más sin esperar a que la página
     vuelva a primer plano. */
  function preguntarDeNuevo(m, n) {
    if (!m.sinRespuesta || n >= ESPERAS_ARRANQUE_S.length) return;
    setTimeout(() => {
      if (ui.modelo !== m || !m.sinRespuesta) return;
      m.refrescar().then(() => preguntarDeNuevo(m, n + 1)).catch(() => {});
    }, ESPERAS_ARRANQUE_S[n] * 1000);
  }

  /* op: { token, rpc, visionUrl, irA(escena), escena() → la que está a la vista, alCambiarEntrada() } */
  function configurar(op) { ui.op = op; }

  /* valor: true o false si el servidor contestó en esta carga de la página; null si no se pudo preguntar.
     Sin una lectura fresca no se arranca nada ni se recuerda la anterior: un apagado de emergencia vale aunque la
     lectura falle. Lo que ya estaba andando en memoria (una subida en curso) sigue hasta que el servidor diga que no. */
  async function aplicarPalanca(valor, controles) {
    if (!ui.op) return;
    // Llegó otra lectura mientras se arma el modelo: se aplica apenas termina (no se pierde).
    if (ui.arrancando) { ui.pendiente = [valor, controles]; return; }
    try { localStorage.removeItem(FLAG); } catch (_) {}      // lo que recordaban las versiones anteriores
    if (valor === null) return;
    if (valor !== true) {
      ui.destino = null;
      dejarDeMirar();
      if (ui.modelo) { ui.modelo.cerrar(); ui.modelo = null; pintar(); }
      return;
    }
    if (ui.modelo) {
      // `controles_app` cambió en esta carga: apagada, se va en el momento; prendida, la trae el próximo `get`.
      const antes = ui.modelo.palancaControles;
      ui.modelo.usarPalancaControles(controles === true);
      if (!antes && controles === true) ui.modelo.refrescar().catch(() => {});
      else pintar();
      return;
    }
    ui.arrancando = true;
    try {
      const m = new raiz.EstudiosCola.ModeloEstudios({ rpc: ui.op.rpc, token: ui.op.token, visionUrl: ui.op.visionUrl, controles: controles === true });
      await m.refrescar();
      m.alCambiar = pintar;
      ui.modelo = m;
      ui.ultimoRefresco = Date.now();
      enganchar();
      pintar();
      preguntarDeNuevo(m, 0);
    } catch (_) {
      ui.modelo = null;
    } finally {
      ui.arrancando = false;
      const p = ui.pendiente; ui.pendiente = null;
      if (p) aplicarPalanca(p[0], p[1]);
    }
  }

  raiz.EstudiosUI = {
    configurar, aplicarPalanca, abrir, renderEscena, montarTarjeta, montarControl, destino,
    /* «Tu recorrido»: los controles de salud como hitos con fecha ([] si no hay o con la palanca apagada). */
    hitosControl: () => (ui.modelo && ui.modelo.estado ? ui.modelo.hitosControl : []),
    get origen() { return ui.origen; },
    /* Hay algo sin ver: el punto de la pestaña y de la fila de Mis datos. */
    novedad: () => !!(ui.modelo && ui.modelo.estado && ui.modelo.novedad),
    /* La novedad con su título y destino, para «Novedades de tu plan» (null si no hay nada sin ver). */
    novedadDeEstudios: () => (ui.modelo && ui.modelo.estado && ui.modelo.novedad) || null,
    titulo: () => T.titulo,
    entradaVisible: () => !!(ui.modelo && ui.modelo.estado),
    subtitulo: () => T.subtituloEntrada(ui.modelo ? ui.modelo.pendientes : 0),
    get _modelo() { return ui.modelo; },
  };
})(window);
