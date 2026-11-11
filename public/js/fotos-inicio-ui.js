/* =============================================================
   fotos-inicio-ui.js — «Fotos de inicio»: las pantallas de la web.

   Las pantallas 1 a 5 de NATIVA_CONTRATO.md §13, gemelas de las apps. Todo
   texto sale de FotosInicio.T. Con la palanca apagada, sin el servidor nuevo o
   sin cuenta no se crea nada: ni modelo, ni IndexedDB, ni llamadas, ni tarjeta.
   ============================================================= */
(function (raiz) {
  'use strict';

  const F = raiz.FotosInicio;
  const T = F.T;
  const FLAG = 'mypump_palanca_fotos_inicio';
  const MINI_PX = 320;
  const SEG_ENTRE_REFRESCOS = 60;
  const ESTADOS = { falta: T.falta, subiendo: T.subiendo, esperando: T.esperandoSenal, lista: T.lista };

  const ui = {
    op: null, modelo: null, arrancando: false, enganchado: false, ultimoRefresco: 0,
    origen: 'revision', pila: [], error: null, procesando: false, guardandoNota: false, notaMsg: null, notaBorrador: null,
    consejos: null, firmaUrls: '', ultimoHtml: null, presionando: false, pendiente: false, entrada: false,
  };

  const e = (s) => String(s == null ? '' : s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const IC = {
    camara: '<svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M4 8h3l2-3h6l2 3h3a1 1 0 0 1 1 1v10a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1V9a1 1 0 0 1 1-1Z"/><circle cx="12" cy="13.5" r="3.5"/></svg>',
    candado: '<svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><rect x="5" y="11" width="14" height="10" rx="2"/><path d="M8 11V8a4 4 0 0 1 8 0v3"/></svg>',
    chev: '<svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="m9 6 6 6-6 6"/></svg>',
    ok: '<svg viewBox="0 0 24 24" width="22" height="22" aria-hidden="true"><circle cx="12" cy="12" r="11" fill="currentColor"/><path d="m7 12.5 3.3 3.3L17 9" fill="none" stroke="var(--color-on-brand)" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"/></svg>',
    alerta: '<svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M10.3 3.9 1.8 18a2 2 0 0 0 1.7 3h17a2 2 0 0 0 1.7-3L13.7 3.9a2 2 0 0 0-3.4 0z"/><path d="M12 9v4"/><path d="M12 17h.01"/></svg>',
    foto: '<svg viewBox="0 0 24 24" width="22" height="22" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round" aria-hidden="true"><rect x="3" y="4" width="18" height="16" rx="2"/><circle cx="9" cy="10" r="1.6"/><path d="m4 18 5-5 4 3 3-2 4 4"/></svg>',
    mas: '<svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" aria-hidden="true"><path d="M12 5v14M5 12h14"/></svg>',
    equis: '<svg viewBox="0 0 24 24" width="12" height="12" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" aria-hidden="true"><path d="M6 6l12 12M18 6 6 18"/></svg>',
  };

  /* La silueta de referencia de una pose, con los colores de la app (claro y oscuro). */
  function siluetaSvg(clave, clase) {
    const s = F.silueta(clave);
    if (!s) return '';
    return `<svg class="${clase}" viewBox="0 0 120 260" aria-hidden="true" focusable="false"><path class="fi-sil-cuerpo" d="${s.contorno}"/><path class="fi-sil-detalle" d="${s.detalle}"/></svg>`;
  }

  // ── La foto: lado mayor ≤ 1600 px, 0,85, orientada y sin metadatos; se mide sobre la reducida ──
  /* Se decodifica con <img> a propósito, como en Gimnasio: desde Safari 13.4 y Chrome 81 el navegador aplica solo la
     orientación EXIF, y createImageBitmap con opciones recién existe en Safari 16.4. */
  function decodificar(file) {
    return new Promise((ok, no) => {
      const url = URL.createObjectURL(file);
      const img = new Image();
      img.onload = () => ok({ img, listo: () => URL.revokeObjectURL(url) });
      img.onerror = () => { URL.revokeObjectURL(url); no(new Error('no se pudo leer la imagen')); };
      img.src = url;
    });
  }
  function aJpeg(canvas, calidad) {
    return new Promise((ok, no) => {
      const porDataUrl = () => {
        try {
          const d = canvas.toDataURL('image/jpeg', calidad);
          if (!/^data:image\/jpeg;base64,/.test(d)) throw new Error('formato no soportado');
          const bin = atob(d.split(',')[1]);
          const b = new Uint8Array(bin.length);
          for (let i = 0; i < bin.length; i++) b[i] = bin.charCodeAt(i);
          ok(b);
        } catch (err) { no(err); }
      };
      if (!canvas.toBlob) return porDataUrl();
      canvas.toBlob((blob) => {
        if (!blob) return porDataUrl();
        new Response(blob).arrayBuffer().then((a) => ok(new Uint8Array(a)), no);
      }, 'image/jpeg', calidad);
    });
  }
  async function leerFechaExif(file) {
    try { return F.fechaExif(new Uint8Array(await file.slice(0, 256 * 1024).arrayBuffer())); } catch (_) { return null; }
  }
  async function prepararFoto(file) {
    const exifMs = await leerFechaExif(file);
    const { img, listo } = await decodificar(file);
    const canvas = document.createElement('canvas'), mini = document.createElement('canvas');
    try {
      const w = img.naturalWidth || img.width, h = img.naturalHeight || img.height;
      if (!w || !h) throw new Error('imagen vacía');
      const r = F.medidaReducida(w, h);
      canvas.width = r.ancho;
      canvas.height = r.alto;
      const ctx = canvas.getContext('2d', { willReadFrequently: true });
      ctx.drawImage(img, 0, 0, canvas.width, canvas.height);
      const medida = F.medir(F.lumaDeRGBA(ctx.getImageData(0, 0, canvas.width, canvas.height).data, canvas.width, canvas.height), canvas.width, canvas.height);
      const limpio = F.quitarMetadatos(await aJpeg(canvas, F.CALIDAD));
      if (!limpio || limpio.length > F.MAX_BYTES) throw new Error('no se pudo preparar');
      const em = Math.min(1, MINI_PX / Math.max(canvas.width, canvas.height));
      mini.width = Math.max(1, Math.round(canvas.width * em));
      mini.height = Math.max(1, Math.round(canvas.height * em));
      mini.getContext('2d').drawImage(canvas, 0, 0, mini.width, mini.height);
      const ahora = Date.now();
      const tomada = F.tomadaEn(exifMs, file.lastModified, ahora);
      return {
        bytes: limpio.buffer, miniatura: mini.toDataURL('image/jpeg', 0.7), ancho: canvas.width, alto: canvas.height,
        brillo: medida.brillo, nitidez: medida.nitidez, tomadaEn: F.iso(tomada), dias: F.dias(tomada, ahora),
        vista: URL.createObjectURL(new Blob([limpio], { type: 'image/jpeg' })),
      };
    } finally {
      canvas.width = canvas.height = 0; mini.width = mini.height = 0;    // Safari libera la memoria recién acá
      listo();
    }
  }

  /* Un solo input y sin `capture`: el teléfono ofrece la cámara o la galería (para el temporizador hace falta la galería). */
  function elegirFoto(clave) {
    let inp = document.getElementById('fiInput');
    if (!inp) {
      inp = document.createElement('input');
      inp.type = 'file';
      inp.id = 'fiInput';
      inp.accept = 'image/*';
      inp.hidden = true;
      inp.setAttribute('aria-hidden', 'true');
      inp.tabIndex = -1;
      document.body.appendChild(inp);
    }
    inp.onchange = () => {
      const f = inp.files && inp.files[0];
      inp.value = '';
      if (f) procesar(f, clave);
    };
    inp.click();    // sincrónico: en iOS tiene que salir del mismo toque
  }

  function soltarVista(d) { if (d && d.foto && d.foto.vista) { try { URL.revokeObjectURL(d.foto.vista); } catch (_) {} d.foto.vista = null; } }

  async function procesar(file, clave) {
    const m = ui.modelo;
    if (!m) return;
    ui.procesando = true;
    ui.error = null;
    m.limpiarAviso();
    renderEscena();
    let foto = null;
    try { foto = await prepararFoto(file); } catch (_) { ui.error = T.ilegible; }
    ui.procesando = false;
    if (!foto || !ui.modelo) { renderEscena(); return; }
    if (clave === F.MOTIVACION) {
      soltarVista({ foto });
      if (F.bloquea(F.problemas(F.MOTIVACION, foto.ancho, foto.alto, foto))) ui.error = T.problemaChica;
      else {
        const r = await m.agregar(F.MOTIVACION, foto);
        if (r === 'noSeGuardo') ui.error = T.noSeGuardo;
        if (r === 'guardada') m.drenarEnFondo();
      }
      renderEscena();
      return;
    }
    const revisar = { t: 'revisar', clave, foto, problemas: F.problemas(clave, foto.ancho, foto.alto, foto, foto.dias) };
    const d = tope();
    if (d && d.t === 'revisar') { soltarVista(d); ui.pila[ui.pila.length - 1] = revisar; } else ui.pila.push(revisar);
    renderEscena();
    raiz.scrollTo(0, 0);
    enfocarTitulo();
  }

  // ── Piezas ──
  const nota = (t, alerta, id, test) => `<p class="fi-nota${alerta ? ' is-alerta' : ''}"${alerta ? ' role="alert"' : ''}${id ? ` id="${id}"` : ''}${test ? ` data-test="${test}"` : ''}>${e(t)}</p>`;
  function avisosHtml(m) {
    let h = '';
    if (m.aviso) h += nota(m.aviso === 'tope' ? T.motivacionTope : T.fotoRechazada, true, 'fiAviso');
    if (ui.error) h += nota(ui.error, true, 'fiError');
    return h;
  }
  const procesandoHtml = () => (ui.procesando ? '<div class="fi-procesando" role="status" aria-busy="true"><div class="spinner" aria-hidden="true"></div></div>' : '');

  function poseBoton(m, p) {
    const est = m.estadoPose(p.clave);
    const mini = est === 'falta' ? null : m.miniaturaPose(p.clave);
    const img = mini ? `<img src="${e(mini)}" alt="">` : siluetaSvg(p.clave, 'fi-sil-chica');
    return `<button type="button" class="fi-pose is-${est}" data-fi="pose" data-clave="${p.clave}" id="fiPose-${p.clave}" data-test="fotos-inicio-pose-${p.clave}" aria-label="${e(`${p.nombre}: ${ESTADOS[est]}`)}">
      <span class="fi-pose-img${mini ? ' con-foto' : ''}">${img}</span>
      <span class="fi-pose-nom">${e(p.nombre)}</span>
      <span class="fi-estado is-${est}">${est === 'lista' ? IC.ok : ''}<span>${e(ESTADOS[est])}</span></span></button>`;
  }

  function motivacionHtml(m) {
    const fotos = m.motivacion;
    const puede = m.puedeAgregarMotivacion && !ui.procesando;
    const valor = ui.notaBorrador !== null ? ui.notaBorrador : m.nota;
    const msg = ui.notaMsg === 'ok' ? nota(T.motivacionGuardada, false, 'fiNotaMsg')
      : ui.notaMsg === 'sinSenal' || (ui.notaMsg === null && m.notaPendiente) ? nota(T.notaSinSenal, false, 'fiNotaMsg') : '';
    return `<section class="fi-seccion" aria-labelledby="fiMotTit">
      <div class="fi-sec-cab"><h3 class="fi-h3" id="fiMotTit">${e(T.motivacionTitulo)}</h3><span class="fi-chip">${e(T.opcional)}</span></div>
      <p class="fi-sub">${e(T.motivacionBajada)}</p>
      ${fotos.length ? `<div class="fi-grilla">${fotos.map((f) => `<div class="fi-mini">
        ${f.miniatura ? `<img src="${e(f.miniatura)}" alt="">` : `<span class="fi-mini-v">${IC.foto}</span>`}
        ${f.subiendo || f.esperando ? `<span class="fi-mini-est">${e(f.subiendo ? T.subiendo : T.esperandoSenal)}</span>` : ''}
        <button type="button" class="fi-mini-x" data-fi="borrar" data-id="${e(f.id)}" aria-label="${e(T.borrarFoto)}">${IC.equis}</button></div>`).join('')}</div>` : ''}
      <button type="button" class="btn-secondary fi-agregar" data-fi="agregarMotivacion" id="fiMotAgregar" data-test="fotos-inicio-motivacion-agregar"${puede ? '' : ' disabled'}>${IC.mas}<span>${e(T.motivacionAgregar)}</span></button>
      <p class="fi-nota${puede || ui.procesando ? '' : ' is-alerta'}" id="fiMotTope">${e(T.motivacionTope)}</p>
      <label class="fi-label" for="fiNota">${e(T.motivacionNota)}</label>
      <textarea class="fi-area" id="fiNota" data-test="fotos-inicio-nota" rows="3" aria-describedby="fiNotaCuenta">${e(valor)}</textarea>
      <div class="fi-cuenta" id="fiNotaCuenta" aria-live="polite">${F.largoNota(valor)}/${F.MAX_NOTA}</div>
      <button type="button" class="btn-secondary" data-fi="guardarNota" id="fiNotaGuardar" data-test="fotos-inicio-nota-guardar"${ui.guardandoNota ? ' disabled' : ''}>${e(T.motivacionGuardar)}</button>
      <div aria-live="polite">${msg}</div>
    </section>`;
  }

  // ── Pantallas ──
  function pResumen(m) {
    const n = m.cuenta3;
    const abiertos = ui.consejos === null ? n === 0 : ui.consejos;
    const cab = m.listas
      ? `<div class="fi-listo" id="fiListo" data-test="fotos-inicio-listo"><span class="fi-grande">${IC.ok}</span>
          <h2 class="fi-h" tabindex="-1" data-fi-titulo>${e(T.listoTitulo)}</h2><p class="fi-sub">${e(T.listoBajada)}</p></div>`
      : `<h2 class="fi-h" tabindex="-1" data-fi-titulo>${e(m.faltan.length ? T.faltan(m.faltan.length) : T.tarjetaTitulo)}</h2>
         <p class="fi-sub">${e(T.tarjetaBajada)}</p>`;
    return `${cab}
      <p class="fi-privacidad">${IC.candado}<span>${e(T.privacidad)}</span></p>
      ${avisosHtml(m)}
      <details class="fi-consejos" id="fiConsejos"${abiertos ? ' open' : ''}>
        <summary class="fi-consejos-tit">${e(T.consejosTitulo)}</summary>
        <ul>${F.CONSEJOS.map((c) => `<li>${e(c)}</li>`).join('')}</ul>
      </details>
      <div class="fi-poses-cab"><span>${e(T.cuenta(n))}</span></div>
      <div class="fi-poses">${F.POSES.map((p) => poseBoton(m, p)).join('')}</div>
      ${procesandoHtml()}
      ${motivacionHtml(m)}
      ${m.listas ? `<button type="button" class="btn-primary" data-fi="cerrar" id="fiCerrar">${e(T.listoBoton)}</button>` : ''}`;
  }

  function pPose(m, clave) {
    const p = F.pose(clave);
    if (!p) { ui.pila = []; return pResumen(m); }
    const est = m.estadoPose(clave);
    const mini = est === 'falta' ? null : m.miniaturaPose(clave);
    // El nombre de la pose ya es el título del encabezado: acá va la instrucción, que es lo que hay que leer.
    return `<div class="fi-sil-grande">${siluetaSvg(clave, 'fi-sil')}${mini ? `<img class="fi-sil-actual" src="${e(mini)}" alt="">` : ''}</div>
      <p class="fi-instruccion" tabindex="-1" data-fi-titulo>${e(p.instruccion)}</p>
      ${est !== 'falta' ? `<p class="fi-nota" id="fiPoseEstado">${e(est === 'lista' ? T.listoBajada : ESTADOS[est])}</p>` : ''}
      ${avisosHtml(m)}${procesandoHtml()}
      <button type="button" class="btn-primary" data-fi="foto" data-clave="${clave}" id="fiFoto" data-test="fotos-inicio-foto"${ui.procesando ? ' disabled' : ''}>${IC.camara}<span>${e(est === 'falta' ? T.botonFoto : T.repetir)}</span></button>`;
  }

  function pRevisar(m, d) {
    const p = F.pose(d.clave);
    const probs = d.problemas;
    const bloq = F.bloquea(probs);
    const lista = probs.length
      ? `<ul class="fi-problemas" role="alert" tabindex="-1" data-fi-titulo>${probs.map((x) => `<li class="fi-problema" data-test="fotos-inicio-problema-${x}" id="fiProblema-${x}">${IC.alerta}<span>${e(F.texto(x, d.foto.dias))}</span></li>`).join('')}</ul>`
      : `<p class="fi-bien" data-test="fotos-inicio-bien" id="fiBien" role="status" tabindex="-1" data-fi-titulo>${IC.ok}<span>${e(T.seVeBien)}</span></p>`;
    const otra = (primario) => `<button type="button" class="${primario ? 'btn-primary' : 'btn-secondary'}" data-fi="otra" data-clave="${d.clave}" id="fiOtra" data-test="fotos-inicio-otra"${ui.procesando ? ' disabled' : ''}>${IC.camara}<span>${e(T.botonOtra)}</span></button>`;
    let botones;
    if (bloq) botones = otra(true);
    else if (probs.length) botones = `${otra(true)}<button type="button" class="btn-secondary" data-fi="usar" id="fiUsarIgual" data-test="fotos-inicio-usar-igual">${e(T.botonUsarIgual)}</button>`;
    else botones = `<button type="button" class="btn-primary" data-fi="usar" id="fiUsar" data-test="fotos-inicio-usar">${e(T.botonUsar)}</button>${otra(false)}`;
    return `<div class="fi-vista">${d.foto.vista ? `<img src="${e(d.foto.vista)}" alt="${e(p ? p.nombre : '')}" id="fiVista">` : ''}</div>
      ${lista}
      ${avisosHtml(m)}${procesandoHtml()}
      <div class="fi-botones">${botones}</div>`;
  }

  // ── Armar y pintar ──
  const tope = () => ui.pila[ui.pila.length - 1] || null;

  function cuerpo(m) {
    const d = tope();
    if (d && d.t === 'pose') return pPose(m, d.clave);
    if (d && d.t === 'revisar') return pRevisar(m, d);
    return pResumen(m);
  }

  function tituloDe(d) {
    if (d && (d.t === 'pose' || d.t === 'revisar')) { const p = F.pose(d.clave); return p ? p.nombre : T.tarjetaTitulo; }
    return T.tarjetaTitulo;
  }
  function titulo() { return tituloDe(tope()); }

  function firmarLoQueSeVe(m) {
    if (!m.estado) return;
    const ids = m.estado.fotos.filter((f) => !m.miniaturas[f.id] && !m.urls[f.id]).map((f) => f.id);
    if (!ids.length) return;
    const clave = ids.join(',');
    if (clave === ui.firmaUrls) return;       // una vez por lo que se está viendo: si el servidor no devuelve alguna, no se insiste
    ui.firmaUrls = clave;
    m.firmar(ids).catch(() => {});
  }

  function raizEscena() { return document.getElementById('scene-fotosinicio'); }
  function escenaActiva() { const r = raizEscena(); return !!r && r.classList.contains('is-active'); }
  const escribiendo = () => {
    const r = raizEscena(), a = document.activeElement;
    return !!r && !!a && r.contains(a) && (a.tagName === 'TEXTAREA' || a.tagName === 'INPUT');
  };
  function enfocarTitulo() {
    setTimeout(() => { const h = document.querySelector('#scene-fotosinicio [data-fi-titulo]'); if (h) try { h.focus({ preventScroll: true }); } catch (_) {} }, 0);
  }

  function renderEscena(forzar) {
    const r = raizEscena(), m = ui.modelo;
    if (!r) return;
    if (!m || !m.estado) { r.innerHTML = ''; ui.ultimoHtml = null; if (escenaActiva()) cerrar(); return; }
    // No se le rehace la pantalla a quien escribe, ni el botón que tiene bajo el dedo: un cambio de DOM entre el down y el
    // up se come el toque.
    if (!forzar && (escribiendo() || ui.presionando)) { ui.pendiente = true; return; }
    ui.pendiente = false;
    const volver = ui.pila.length ? tituloDe(ui.pila[ui.pila.length - 2]) : T.cerrar;
    const h = `<div class="fi"><button type="button" class="sd-volver" data-fi="volver" id="fiVolver">‹ ${e(volver)}</button>${cuerpo(m)}</div>`;
    if (h !== ui.ultimoHtml) { r.innerHTML = h; ui.ultimoHtml = h; }
    const t = document.getElementById('hdrTitle');
    if (t && escenaActiva()) t.textContent = titulo();
    firmarLoQueSeVe(m);
  }

  /* La tarjeta, arriba de todo en Revisión. renderRevision rehace todo: se vuelve a poner. */
  function montarTarjeta(root) {
    let host = document.getElementById('fiHost');
    const m = ui.modelo;
    if (!root || !m || !m.estado) { if (host) host.remove(); return; }
    if (!host) {
      host = document.createElement('div');
      host.id = 'fiHost';
      host.addEventListener('click', () => abrir('revision'));
    }
    const n = m.cuenta3;
    const html = `<button type="button" class="fi-tarjeta${m.listas ? ' is-lista' : ''}" id="fiTarjeta" data-test="fotos-inicio-tarjeta">
      <span class="fi-tarjeta-ic">${m.listas ? IC.ok : IC.camara}</span>
      <span class="fi-tarjeta-txt"><strong>${e(T.tarjetaTitulo)}</strong><span>${e(m.listas ? T.tarjetaLista : T.tarjetaBajada)}</span>
        ${m.listas ? '' : `<span class="fi-tarjeta-cuenta">${e(T.cuenta(n))}</span>`}</span>
      ${m.listas ? `<span class="md-chev">${IC.chev}</span>` : `<span class="fi-tarjeta-cta">${e(n ? T.tarjetaSeguir : T.tarjetaEmpezar)}</span>`}</button>`;
    if (host.dataset.h !== html) { host.innerHTML = html; host.dataset.h = html; }
    if (root.firstChild !== host) root.insertBefore(host, root.firstChild);
  }

  function pintar() {
    if (!ui.op) return;
    montarTarjeta(document.getElementById('scene-revision'));
    const ve = !!(ui.modelo && ui.modelo.estado);
    if (ve !== ui.entrada) { ui.entrada = ve; ui.op.alCambiarEntrada(); }
    if (escenaActiva()) renderEscena();
  }

  function abrir(origen) {
    if (!ui.modelo || !ui.modelo.estado) return;
    ui.origen = origen;
    for (const d of ui.pila) soltarVista(d);
    ui.pila = [];
    ui.error = null;
    ui.notaMsg = null;
    ui.notaBorrador = null;
    ui.consejos = null;
    ui.firmaUrls = '';
    ui.modelo.limpiarAviso();
    ui.op.irA('fotosinicio');
    raiz.scrollTo(0, 0);
    ui.modelo.refrescar().then(() => ui.modelo && ui.modelo.drenarEnFondo()).catch(() => {});
  }
  function cerrar() {
    for (const d of ui.pila) soltarVista(d);
    ui.pila = [];
    if (ui.op) ui.op.irA(ui.origen === 'misdatos' ? 'misdatos' : 'revision');
  }
  function irA(pila) {
    ui.pila = pila;
    ui.error = null;
    if (ui.modelo) ui.modelo.limpiarAviso();
    renderEscena(true);
    raiz.scrollTo(0, 0);
    enfocarTitulo();
  }

  // ── Toques ──
  const ACCIONES = {
    volver() {
      if (!ui.pila.length) return cerrar();
      soltarVista(ui.pila.pop());
      irA(ui.pila);
    },
    cerrar() { cerrar(); },
    pose(b) { irA([{ t: 'pose', clave: b.dataset.clave }]); },
    foto(b) { elegirFoto(b.dataset.clave); },
    otra(b) { elegirFoto(b.dataset.clave); },
    agregarMotivacion() { ui.notaMsg = null; elegirFoto(F.MOTIVACION); },
    async usar() {
      const m = ui.modelo, d = tope();
      if (!m || !d || d.t !== 'revisar' || F.bloquea(d.problemas)) return;
      const r = await m.agregar(d.clave, d.foto);
      if (r !== 'guardada') { ui.error = T.noSeGuardo; renderEscena(true); return; }
      m.drenarEnFondo();
      soltarVista(d);
      const sig = F.siguiente(d.clave, m.faltan);
      irA(sig ? [{ t: 'pose', clave: sig }] : []);
    },
    async borrar(b) {
      const r = await ui.modelo.borrarMotivacion(b.dataset.id);
      ui.error = r === 'sinSenal' ? T.sinSenal.split(':')[0] : null;
      renderEscena(true);
    },
    async guardarNota() {
      const m = ui.modelo;
      const area = document.getElementById('fiNota');
      const valor = area ? area.value : m.nota;
      ui.guardandoNota = true; ui.notaMsg = null; renderEscena(true);
      let r;
      try { r = await m.guardarNota(valor); } finally { ui.guardandoNota = false; }
      if (r === 'ok' || r === 'sinSenal') { ui.notaMsg = r; ui.notaBorrador = null; }
      renderEscena(true);
    },
  };

  function enganchar() {
    if (ui.enganchado) return;
    ui.enganchado = true;
    const r = raizEscena();
    if (r) {
      r.addEventListener('click', (ev) => {
        const b = ev.target.closest('[data-fi]');
        if (!b || b.disabled || !ui.modelo) return;
        const foco = document.activeElement;
        if (foco && r.contains(foco) && foco !== b && (foco.tagName === 'INPUT' || foco.tagName === 'TEXTAREA')) foco.blur();
        const f = ACCIONES[b.dataset.fi];
        if (f) { const p = f(b); if (p && p.catch) p.catch(() => {}); }
      });
      r.addEventListener('input', (ev) => {
        if (ev.target.id !== 'fiNota') return;
        const a = ev.target;
        // Hasta 300 contados por punto de código, como el servidor (maxlength cuenta otra cosa y corta los emojis a la mitad).
        if (F.largoNota(a.value) > F.MAX_NOTA) a.value = Array.from(a.value).slice(0, F.MAX_NOTA).join('');
        ui.notaBorrador = a.value;
        ui.notaMsg = null;
        const c = document.getElementById('fiNotaCuenta');
        if (c) c.textContent = `${F.largoNota(a.value)}/${F.MAX_NOTA}`;
      });
      // Lo que el alumno abrió o cerró a mano se respeta al repintar (el `toggle` también salta al pintarlo abierto).
      r.addEventListener('click', (ev) => { const s = ev.target.closest('#fiConsejos > summary'); if (s) ui.consejos = !s.parentNode.open; });
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
    return navigator.locks.request(`fotos-inicio-cola-${token}`, () => fn());
  };

  /* op: { token, rpc, visionUrl, irA(escena), alCambiarEntrada() } */
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
      const m = await raiz.FotosInicioCola.arrancar({
        prendida: true, rpc: ui.op.rpc, token: ui.op.token, visionUrl: ui.op.visionUrl, conLock: conLock(ui.op.token),
      });
      if (!m) return;
      m.alCambiar = pintar;
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

  raiz.FotosInicioUI = {
    configurar, aplicarPalanca, montarTarjeta, abrir, renderEscena, titulo,
    entradaVisible: () => !!(ui.modelo && ui.modelo.estado),
    get origen() { return ui.origen; },
    get _modelo() { return ui.modelo; },
  };
})(window);
