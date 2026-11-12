/* =============================================================
   gimnasio-ui.js — «Gimnasio por fotos»: las pantallas de la web.

   La misma experiencia que GimnasioView.swift. Todo texto sale de Gimnasio.T.
   Con la palanca apagada, sin el servidor nuevo o sin cuenta no se crea nada:
   ni modelo, ni IndexedDB, ni llamadas, ni tarjeta.
   ============================================================= */
(function (raiz) {
  'use strict';

  const G = raiz.Gimnasio;
  const T = G.T;
  const FLAG = 'mypump_palanca_gimnasio_fotos';
  const MINI_PX = 240;
  const SEG_ENTRE_REFRESCOS = 60;

  const ui = {
    op: null, modelo: null, arrancando: false, enganchado: false, ultimoRefresco: 0,
    origen: 'train', pila: [], indice: 0, error: null, ocupado: false, procesando: false,
    firma: '', firmaUrls: '', ultimoHtml: null, presionando: false, pendiente: false, entrada: false, marcadosQuitar: new Set(), kilos: {},
  };

  const e = (s) => String(s == null ? '' : s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const IC = {
    pesa: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" aria-hidden="true"><path d="M6.5 7v10M17.5 7v10M3.5 9.5v5M20.5 9.5v5M6.5 12h11"/></svg>',
    chev: '<svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="m9 6 6 6-6 6"/></svg>',
    ok: '<svg viewBox="0 0 24 24" width="22" height="22" aria-hidden="true"><circle cx="12" cy="12" r="11" fill="currentColor"/><path d="m7 12.5 3.3 3.3L17 9" fill="none" stroke="var(--color-on-brand)" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"/></svg>',
    no: '<svg viewBox="0 0 24 24" width="22" height="22" fill="none" stroke="currentColor" stroke-width="1.8" aria-hidden="true"><circle cx="12" cy="12" r="10"/></svg>',
    camara: '<svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M4 8h3l2-3h6l2 3h3a1 1 0 0 1 1 1v10a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1V9a1 1 0 0 1 1-1Z"/><circle cx="12" cy="13.5" r="3.5"/></svg>',
    foto: '<svg viewBox="0 0 24 24" width="22" height="22" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round" aria-hidden="true"><rect x="3" y="4" width="18" height="16" rx="2"/><circle cx="9" cy="10" r="1.6"/><path d="m4 18 5-5 4 3 3-2 4 4"/></svg>',
    equis: '<svg viewBox="0 0 24 24" width="12" height="12" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" aria-hidden="true"><path d="M6 6l12 12M18 6 6 18"/></svg>',
  };

  // ── La foto: 1600 px, 0,8 y sin metadatos ──
  /* Se decodifica con <img> a propósito, como _fotoAJpeg: desde Safari 13.4 y Chrome 81 el navegador aplica solo la
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
  async function prepararFoto(file) {
    const { img, listo } = await decodificar(file);
    const canvas = document.createElement('canvas'), mini = document.createElement('canvas');
    try {
      const w = img.naturalWidth || img.width, h = img.naturalHeight || img.height;
      if (!w || !h) throw new Error('imagen vacía');
      const esc = Math.min(1, G.MAX_PX / Math.max(w, h));
      canvas.width = Math.max(1, Math.round(w * esc));
      canvas.height = Math.max(1, Math.round(h * esc));
      canvas.getContext('2d').drawImage(img, 0, 0, canvas.width, canvas.height);
      const limpio = G.quitarMetadatos(await aJpeg(canvas, G.CALIDAD));
      if (!limpio || limpio.length > G.MAX_BYTES) throw new Error('no se pudo preparar');
      const em = Math.min(1, MINI_PX / Math.max(canvas.width, canvas.height));
      mini.width = Math.max(1, Math.round(canvas.width * em));
      mini.height = Math.max(1, Math.round(canvas.height * em));
      mini.getContext('2d').drawImage(canvas, 0, 0, mini.width, mini.height);
      return { bytes: limpio.buffer, miniatura: mini.toDataURL('image/jpeg', 0.6) };
    } finally {
      canvas.width = canvas.height = 0; mini.width = mini.height = 0;    // Safari libera la memoria recién acá
      listo();
    }
  }

  // Un input con capture= abre la cámara y no deja llegar al carrete: dos inputs, como en las fotos de progreso.
  function inputFoto(origen) {
    const id = origen === 'galeria' ? 'gimInputGal' : 'gimInputCam';
    let inp = document.getElementById(id);
    if (!inp) {
      inp = document.createElement('input');
      inp.type = 'file';
      inp.id = id;
      inp.style.display = 'none';
      if (origen === 'galeria') inp.accept = 'image/*,.heic,.heif';
      else { inp.accept = 'image/*'; inp.setAttribute('capture', 'environment'); }
      document.body.appendChild(inp);
    }
    return inp;
  }

  function pedirFoto(zona, pregunta) {
    const ov = document.createElement('div');
    ov.className = 'fp-pick';
    ov.innerHTML = `<div class="fp-pick-card" role="dialog" aria-label="${e(T.agregarFoto)}">
      <div class="fp-pick-tit">${e(G.nombreZona(zona))}</div>
      <button class="fp-pick-btn" data-origen="camara">Sacar la foto ahora</button>
      <button class="fp-pick-btn" data-origen="galeria">Elegir de la galería</button>
      <button class="fp-pick-btn is-cancel" data-origen="">Cancelar</button></div>`;
    ov.addEventListener('click', (ev) => {
      if (ev.target === ov) return ov.remove();
      const b = ev.target.closest('.fp-pick-btn');
      if (!b) return;
      ov.remove();
      if (!b.dataset.origen) return;
      const inp = inputFoto(b.dataset.origen);
      inp.multiple = b.dataset.origen === 'galeria' && !pregunta;
      inp.onchange = () => {
        const archivos = Array.from(inp.files || []);
        inp.value = '';
        if (archivos.length) procesar(archivos, zona, pregunta);
      };
      inp.click();    // sincrónico: en iOS tiene que salir del mismo toque
    });
    document.body.appendChild(ov);
  }

  async function procesar(archivos, zona, pregunta) {
    const m = ui.modelo;
    if (!m) return;
    ui.procesando = true;
    ui.error = null;
    m.empezarPreparacion();
    pintar();
    let aviso = null;
    try { for (const f of archivos) {
      if (!pregunta && !m.puedeAgregar) { aviso = 'tope'; break; }
      let foto;
      // De a una: en un teléfono, varias de 12 MP decodificadas juntas tiran la pestaña.
      try { foto = await prepararFoto(f); } catch (_) { aviso = 'rechazada'; continue; }
      const r = await m.agregar(zona, foto, pregunta);
      if (r === 'tope') { aviso = 'tope'; break; }
      if (r === 'noSeGuardo') { ui.error = T.noSeGuardo; break; }
      m.drenarEnFondo();
    } } finally {
      ui.procesando = false;
      if (aviso) m.avisoFoto = aviso;
      m.terminarPreparacion();
    }
    pintar();
  }

  // ── Piezas ──
  const nota = (t, alerta, id) => `<p class="gim-nota${alerta ? ' is-alerta' : ''}"${alerta ? ' role="alert"' : ''}${id ? ` id="${id}"` : ''}>${e(t)}</p>`;
  const avisoFotoHtml = (m) => (m.avisoFoto ? nota(m.avisoFoto === 'tope' ? T.tope : T.fotoRechazada, true, 'gimAvisoFoto') : '');
  function avisoEnvioHtml(m) {
    const a = m.avisoEnvio;
    if (!a) return '';
    if (a.faltan) return nota(T.faltanZonas(a.faltan.length), true, 'gimAvisoEnvio');
    return nota(a === 'sinNovedad' ? T.sinNovedad : T.errorGenerico, true, 'gimAvisoEnvio');
  }
  const errorHtml = () => (ui.error ? nota(ui.error, true, 'gimError') : '');

  function fotoRef(m, ids) {
    if (!ids || !ids.length) return '';
    return `<div class="gim-refs">${ids.map((id) => {
      const u = m.miniaturas[id] || m.urls[id];
      return `<div class="gim-ref">${u ? `<img src="${e(u)}" alt="" loading="lazy">` : IC.foto}</div>`;
    }).join('')}</div>`;
  }
  const opcion = (texto, marcada, attrs) => `<button type="button" class="gim-op${marcada ? ' is-on' : ''}" aria-pressed="${marcada}" ${attrs}>${marcada ? IC.ok : IC.no}<span>${e(texto)}</span></button>`;

  // ── Pantallas ──
  /* Sin carga abierta no hay nada que leer: se abre sola y sigue a las zonas. Solo se queda acá si no se pudo. */
  function pArranque() {
    if (!ui.error) return '<div class="tec-envio" id="gimArrancando"><div class="spinner" aria-hidden="true"></div></div>';
    return `${errorHtml()}
      <button type="button" class="btn-primary" data-gim="empezar" id="gimReintentar"${ui.ocupado ? ' disabled' : ''}>${e(T.botonReintentar)}</button>`;
  }

  function detalleZona(m, z, fotos) {
    const no = m.noHay.has(z.clave) && !fotos.length;
    return {
      lista: no || fotos.length > 0,
      detalle: no ? T.noHayCorto : !fotos.length ? (z.clave === G.ZONA_OPCIONAL ? T.opcional : T.sinFotos) : T.cuentaFotos(fotos.length),
    };
  }

  function pZonas(m) {
    const a = m.abierta;
    const faltan = (m.avisoEnvio && m.avisoEnvio.faltan) || [];
    return `${a.modo === 'completa' && m.faltantes.length ? `<h2 class="gim-h gim-h-chico" id="gimFaltan">${e(T.faltanZonas(m.faltantes.length))}</h2>` : ''}
      ${nota(T.consejoPermiso)}
      ${avisoFotoHtml(m)}${avisoEnvioHtml(m)}
      <div class="md-grupo gim-zonas">${G.ZONAS.map((z) => {
        const d = detalleZona(m, z, m.fotos(z.clave));
        return `<button type="button" class="md-fila gim-zona" data-gim="zona" data-z="${e(z.clave)}"><span class="gim-zona-ic${d.lista ? ' is-on' : ''}">${d.lista ? IC.ok : IC.no}</span>
          <span class="gim-zona-txt"><span>${e(z.nombre)}</span><small class="${faltan.includes(z.clave) ? 'is-alerta' : ''}">${e(d.detalle)}</small></span><span class="md-chev">${IC.chev}</span></button>`;
      }).join('')}</div>
      <button type="button" class="btn-primary gim-mt" data-gim="revisar" id="gimRevisar">${e(T.revisarYEnviar)}</button>`;
  }

  function miniatura(f, m) {
    const u = f.miniatura || m.urls[f.id];
    return `<div class="gim-mini">${u ? `<img src="${e(u)}" alt="" loading="lazy">` : `<span class="gim-mini-v">${IC.foto}</span>`}
      ${f.subiendo || f.esperando ? `<span class="gim-mini-est">${e(f.subiendo ? T.subiendo : T.esperandoSenal)}</span>` : ''}
      <button type="button" class="gim-mini-x" data-gim="borrar" data-id="${e(f.id)}" aria-label="${e(T.borrarFoto)}">${IC.equis}</button></div>`;
  }

  function pZona(m, clave) {
    const z = G.ZONAS.find((x) => x.clave === clave);
    if (!z) { ui.pila = []; return pZonas(m); }
    const fotos = m.fotos(z.clave);
    const no = m.noHay.has(z.clave);
    const puede = m.puedeAgregar && !ui.procesando;
    return `<h2 class="gim-h gim-h-chico">${e(z.pedido)}</h2>
      <p class="gim-sub">${e(T.consejoCamara)}</p>
      ${fotos.length ? `<div class="gim-grilla">${fotos.map((f) => miniatura(f, m)).join('')}</div>` : ''}
      ${avisoFotoHtml(m)}${errorHtml()}
      <button type="button" class="btn-primary gim-mt" data-gim="agregar" data-z="${e(z.clave)}" id="gimAgregar"${puede ? '' : ' disabled'}>${IC.camara}<span>${e(T.agregarFoto)}</span></button>
      ${z.clave !== G.ZONA_OPCIONAL && m.abierta.modo === 'completa' && !fotos.length ? opcion(T.noHay, no, `data-gim="nohay" data-z="${e(z.clave)}" id="gimNoHay"`) : ''}`;
  }

  function pRevisar(m) {
    const n = Array.from(m.nota).length;
    return `<div class="md-grupo gim-resumen">${G.ZONAS.map((z) => {
      const c = m.fotos(z.clave).length;
      const txt = c > 0 ? T.cuentaFotos(c) : m.noHay.has(z.clave) ? T.noHayCorto : z.clave === G.ZONA_OPCIONAL ? T.opcional : T.sinFotos;
      return `<div class="gim-resumen-f"><span>${e(z.nombre)}</span><span class="${m.faltantes.includes(z.clave) ? 'is-alerta' : ''}">${e(txt)}</span></div>`;
    }).join('')}</div>
      <textarea class="gim-area" id="gimNota" rows="3" maxlength="${G.MAX_NOTA}" placeholder="${e(T.notaPlaceholder)}" aria-label="${e(T.notaPlaceholder)}">${e(m.nota)}</textarea>
      <div class="gim-cuenta" id="gimNotaCuenta">${n}/${G.MAX_NOTA}</div>
      ${m.faltantes.length ? nota(T.faltanZonas(m.faltantes.length), true, 'gimFaltanRev') : ''}
      ${avisoEnvioHtml(m)}
      <button type="button" class="btn-primary" data-gim="enviar" id="gimEnviar"${m.puedeEnviar && !ui.procesando ? '' : ' disabled'}>${e(T.botonEnviar)}</button>`;
  }

  function pEnviando(m) {
    const quedan = m._colaDeLaCarga.length;
    return `<div class="gim-centro"><div class="spinner" aria-hidden="true"></div>
      ${quedan ? `<p class="gim-h gim-h-chico" id="gimSubiendo">${e(T.subiendoFotos(m.subidasEnvio, Math.max(m.totalEnvio, m.subidasEnvio + quedan)))}</p>` : ''}
      <p class="gim-sub" id="gimEnviando">${e(T.enviandoSeguir)}</p>
      <button type="button" class="btn-secondary" data-gim="volverEditar" id="gimVolverEditar">${e(T.volverAEditar)}</button></div>`;
  }

  const pRecibido = () => `<div class="gim-centro" id="gimRecibido"><span class="gim-grande">${IC.ok}</span><p class="gim-h gim-h-chico">${e(T.recibido)}</p></div>`;

  function pListo(m) {
    const v = m.vigente;
    let titulo = null;
    if (v && v.resultado === 'sin_cambios') titulo = T.sinCambios;
    else if (v && (v.resultado === 'adaptada' || v.resultado === 'plan_nuevo')) {
      const f = G.fechaCorta(v.publicadoEn);
      titulo = f ? T.adaptadoPorMati(f) : null;
    }
    const zonas = G.ZONAS.map((z) => {
      const eqs = ((v && v.equipos) || []).filter((q) => q.zona === z.clave);
      if (!eqs.length) return '';
      return `<div class="md-ceja">${e(z.nombre)}</div><div class="md-grupo">${eqs.map((q) => `<div class="gim-resumen-f"><span>${e(q.nombre)}</span>${q.cantidad > 1 ? `<span>×${q.cantidad}</span>` : ''}</div>`).join('')}</div>`;
    }).join('');
    return `${titulo ? `<h2 class="gim-h gim-h-chico" id="gimResultado">${e(titulo)}</h2>` : ''}
      ${errorHtml()}
      ${zonas}
      <div class="md-grupo gim-mt">
        <button type="button" class="md-fila" data-gim="nuevo" data-modo="parcial" id="gimFaltaAlgo"><span>${e(T.faltaAlgo)}</span></button>
        <button type="button" class="md-fila" data-gim="yaNoEsta" id="gimYaNoEsta"><span>${e(T.yaNoEsta)}</span><span class="md-chev">${IC.chev}</span></button>
        <button type="button" class="md-fila" data-gim="nuevo" data-modo="completa" id="gimCambie"><span>${e(T.cambieDeGimnasio)}</span></button>
      </div>`;
  }

  function pYaNoEsta(m) {
    const eqs = (m.vigente && m.vigente.equipos) || [];
    return `<div class="md-ceja gim-sin-mayus">${e(T.marcarLoQueNoEsta)}</div>
      ${eqs.map((q, i) => opcion(q.nombre, ui.marcadosQuitar.has(q.tipo), `data-gim="marcarQuitar" data-i="${i}"`)).join('')}
      ${errorHtml()}
      <button type="button" class="btn-primary gim-mt" data-gim="enviarQuitar" id="gimEnviarQuitar"${ui.marcadosQuitar.size && !ui.ocupado ? '' : ' disabled'}>${e(T.botonEnviar)}</button>`;
  }

  function pPreguntas(m) {
    const ps = m.abierta.preguntas;
    if (!ps.length) return pRecibido();
    const i = Math.min(ui.indice, ps.length - 1);
    ui.indice = i;
    const n = G.fotosPedidas(ps, m.respuestas);
    return `<div class="gim-q-num" id="gimNumero">${e(T.preguntaDe(i + 1, ps.length))}</div>
      <div class="gim-barra" aria-hidden="true"><span style="width:${((i + 1) / ps.length) * 100}%"></span></div>
      ${n > 0 ? nota(T.necesitamosFotos(n), false, 'gimNecesitamos') : ''}
      ${avisoFotoHtml(m)}${m.avisoEnvio ? nota(T.errorGenerico, true, 'gimAvisoEnvio') : ''}
      ${pPregunta(m, ps[i], i)}
      <div class="gim-nav">
        ${i > 0 ? `<button type="button" class="btn-secondary" data-gim="anterior" id="gimAnterior">${e(T.anterior)}</button>` : ''}
        ${i < ps.length - 1 ? `<button type="button" class="btn-primary" data-gim="siguiente" id="gimSiguiente">${e(T.siguiente)}</button>`
          : `<button type="button" class="btn-primary" data-gim="enviarRespuestas" id="gimEnviarRespuestas"${ui.procesando ? ' disabled' : ''}>${e(T.botonEnviar)}</button>`}
      </div>`;
  }

  function pPregunta(m, p, i) {
    const v = m.respuestas[p.id];
    const noSe = v === 'no_se';
    let c = '';
    if (p.clase === 'elegir') {
      if (p.multiple) {
        const sel = new Set(Array.isArray(v) ? v : []);
        c = nota(T.marcarTodas) + p.opciones.map((o, k) => opcion(o.texto, sel.has(o.valor), `data-gim="multi" data-k="${k}"`)).join('');
      } else {
        c = p.opciones.map((o, k) => opcion(o.texto, v === o.valor, `data-gim="uno" data-k="${k}"`)).join('');
      }
    } else if (p.clase === 'numero') {
      const previo = ui.kilos[p.id] != null ? ui.kilos[p.id] : (typeof v === 'number' ? String(v).replace('.', ',') : '');
      const malo = previo !== '' && G.kilos(previo) === null;
      c = `<div class="gim-kilos"><input type="text" inputmode="decimal" autocomplete="off" id="gimKilos" placeholder="${e(T.elegirKilos)}" aria-label="${e(T.elegirKilos)}" value="${e(previo)}"><span>${e(p.unidad || T.kg)}</span></div>
        <p class="gim-nota is-alerta" id="gimKilosMal"${malo ? '' : ' hidden'}>${e(T.kilosInvalidos)}</p>`;
    } else if (p.clase === 'confirmar') {
      const mapa = v && typeof v === 'object' ? v : {};
      c = p.items.map((it, k) => `<div class="gim-item"><div class="gim-item-t">${e(it.texto)}</div>${fotoRef(m, it.fotos)}<div class="gim-tres" role="group" aria-label="${e(it.texto)}">
        ${[['si', T.si], ['no', T.no], ['no_se', T.noSe]].map(([val, tx]) => `<button type="button" class="gim-chip${mapa[it.tipo] === val ? ' is-on' : ''}" aria-pressed="${mapa[it.tipo] === val}" data-gim="confirmar" data-k="${k}" data-v="${val}">${e(tx)}</button>`).join('')}
      </div></div>`).join('');
    } else if (p.clase === 'foto') {
      const enCola = m.cola.find((x) => x.pregunta === p.id);
      c = nota(T.consejoCamara);
      if (v === 'subida') c += nota(!enCola ? T.cuentaFotos(1) : m.subiendo === enCola.id ? T.subiendo : T.esperandoSenal, false, 'gimFotoEstado');
      c += `<button type="button" class="btn-primary" data-gim="agregar" data-z="${e(p.zona || G.ZONA_OPCIONAL)}" data-p="${i}" id="gimAgregar"${ui.procesando ? ' disabled' : ''}>${IC.camara}<span>${e(T.agregarFoto)}</span></button>`;
      c += opcion(T.noPuedoFoto, v === 'no_puedo', 'data-gim="noPuedo" id="gimNoPuedo"');
    }
    const conNoSe = p.clase !== 'foto' && p.clase !== 'confirmar';
    return `<h2 class="gim-h gim-h-chico">${e(p.texto)}</h2>${fotoRef(m, p.fotos)}${c}${conNoSe ? opcion(T.noSe, noSe, 'data-gim="noSe" id="gimNoSe"') : ''}`;
  }

  // ── Armar y pintar ──
  const firmaPantalla = (m) => `${m.pantalla}-${m.envio ? 1 : 0}`;
  const tope = () => ui.pila[ui.pila.length - 1] || null;

  function cuerpo(m) {
    if (m.envio) return pEnviando(m);
    const d = tope();
    if (d && d.t === 'zona') return pZona(m, d.clave);
    if (d && d.t === 'revisar') return pRevisar(m);
    if (d && d.t === 'yaNoEsta') return pYaNoEsta(m);
    switch (m.pantalla) {
      case 'inicio': return pArranque();
      case 'zonas': return pZonas(m);
      case 'recibido': return pRecibido();
      case 'preguntas': return pPreguntas(m);
      default: return pListo(m);
    }
  }

  function titulo() {
    const d = tope();
    if (d && d.t === 'zona') return G.nombreZona(d.clave);
    if (d && d.t === 'revisar') return T.revisarTitulo;
    if (d && d.t === 'yaNoEsta') return T.yaNoEsta;
    return T.tarjetaTitulo;
  }

  function firmarLoQueSeVe(m) {
    const a = m.abierta;
    if (!a) return;
    let ids = [];
    const d = tope();
    if (d && d.t === 'zona') ids = m.fotos(d.clave).filter((f) => !f.local && !f.miniatura).map((f) => f.id);
    else if (m.pantalla === 'preguntas' && a.preguntas.length) {
      const p = a.preguntas[Math.min(ui.indice, a.preguntas.length - 1)];
      ids = [...p.fotos, ...p.items.flatMap((it) => it.fotos)];
    }
    if (!ids.length) return;
    const clave = `${a.id}:${ids.join(',')}`;
    if (clave === ui.firmaUrls) return;       // una vez por lo que se está viendo: si el servidor no devuelve alguna, no se insiste en bucle
    ui.firmaUrls = clave;
    m.firmar(a.id, ids).catch(() => {});
  }

  function raizEscena() { return document.getElementById('scene-gimnasio'); }
  function escenaActiva() { const r = raizEscena(); return !!r && r.classList.contains('is-active'); }
  const escribiendo = () => {
    const r = raizEscena(), a = document.activeElement;
    return !!r && !!a && r.contains(a) && (a.tagName === 'TEXTAREA' || a.tagName === 'INPUT');
  };

  function renderEscena() {
    const r = raizEscena(), m = ui.modelo;
    if (!r) return;
    if (!m || !m.estado) { r.innerHTML = ''; ui.ultimoHtml = null; if (escenaActiva()) cerrar(); return; }
    const f = firmaPantalla(m);
    const cambioDeEtapa = f !== ui.firma;
    if (cambioDeEtapa) { ui.firma = f; ui.pila = []; ui.indice = 0; }
    // No se le rehace la pantalla a quien escribe, ni el botón que tiene bajo el dedo: un cambio de DOM entre el down y el
    // up se come el toque (en Safari, además, el botón no toma el foco y el campo se suelta recién al apretar).
    if (!cambioDeEtapa && (escribiendo() || ui.presionando)) { ui.pendiente = true; return; }
    ui.pendiente = false;
    const volver = ui.pila.length ? T.tarjetaTitulo : T.cerrar;
    // «Entreno en casa» (js/casa-ui.js): el interruptor arriba de todo y, si la carga es de casa, su lista en lugar de las zonas.
    const casa = raiz.CasaUI && !ui.pila.length && !m.envio ? raiz.CasaUI.piezas() : null;
    const h = `<div class="gim"><button type="button" class="sd-volver" data-gim="volver" id="gimVolver">‹ ${e(volver)}</button>${casa ? casa.arriba : ''}${casa && casa.cuerpo != null ? casa.cuerpo : cuerpo(m)}</div>`;
    if (h !== ui.ultimoHtml) { r.innerHTML = h; ui.ultimoHtml = h; }
    const t = document.getElementById('hdrTitle');
    if (t) t.textContent = titulo();
    firmarLoQueSeVe(m);
    if (m.pantalla === 'inicio' && !m.envio && !ui.ocupado && !ui.error && escenaActiva()) empezar('completa');
  }

  function detalleTarjeta(m) {
    const casa = raiz.CasaUI ? raiz.CasaUI.detalleTarjeta() : null;
    if (casa) return casa;
    switch (m.pantalla) {
      case 'zonas': return m.faltantes.length ? T.faltanZonas(m.faltantes.length) : T.revisarYEnviar;
      case 'recibido': return T.recibido;
      case 'preguntas': return T.confirmarTarjeta;
      default: return T.inicioBajada;
    }
  }

  /* «¿Entrenás en casa? Tocá acá» (palanca `casa`): debajo de la tarjeta, abre Mi gimnasio con el interruptor arriba. */
  function botonCasa() {
    const t = raiz.CasaUI && raiz.CasaUI.botonTarjeta ? raiz.CasaUI.botonTarjeta() : null;
    const sola = ui.modelo && !ui.modelo.tarjetaVisible ? ' is-sola' : '';
    return t ? `<button type="button" class="casa-tarjeta-btn${sola}" id="casa-tarjeta">${e(t)}</button>` : '';
  }

  /* La tarjeta arriba en Entreno, debajo de la de la guía. renderTrain rehace todo: se vuelve a poner. */
  function montarTarjeta(root, despuesDe) {
    let host = document.getElementById('gimHost');
    const m = ui.modelo;
    // Con el gimnasio ya cargado la tarjeta no va, pero el botón de casa sí: nadie queda a tres toques.
    // Simplificar (11/11, web_230): el botón de casa pasa adentro de «Mi gimnasio y mi técnica» (a 2 toques desde Entreno).
    const casaEnHub = !!(ui.op && ui.op.casaEnHub && ui.op.casaEnHub());
    const casa = m && !casaEnHub ? botonCasa() : '';
    if (!root || !m || (!m.tarjetaVisible && !casa)) { if (host) host.remove(); return; }
    if (!host) {
      host = document.createElement('div');
      host.id = 'gimHost';
      host.addEventListener('click', () => abrir('train'));
    }
    const html = !m.tarjetaVisible ? casa : `<button type="button" class="gim-tarjeta" id="gimTarjeta"><span class="gim-tarjeta-ic">${IC.pesa}</span>
      <span class="gim-tarjeta-txt"><strong>${e(T.tarjetaTitulo)}</strong><span>${e(detalleTarjeta(m))}</span></span><span class="md-chev">${IC.chev}</span></button>${casa}`;
    if (host.dataset.h !== html) { host.innerHTML = html; host.dataset.h = html; }
    const sigue = despuesDe && despuesDe.parentNode === root ? despuesDe.nextSibling : root.firstChild;
    if (sigue !== host) root.insertBefore(host, sigue);
  }

  function pintar() {
    if (!ui.op) return;
    montarTarjeta(document.getElementById('scene-train'), document.getElementById('guiaHost'));
    const ve = !!(ui.modelo && ui.modelo.entradaVisible);
    if (ve !== ui.entrada) { ui.entrada = ve; ui.op.alCambiarEntrada(); }
    if (ui.op.alCambiar) { try { ui.op.alCambiar(); } catch (_) {} }   // «Mi gimnasio y mi técnica» (web_230)
    if (escenaActiva()) renderEscena();
  }

  function abrir(origen) {
    if (!ui.modelo || !ui.modelo.estado) return;
    ui.origen = origen;
    ui.pila = [];
    ui.indice = 0;
    ui.error = null;
    ui.firma = firmaPantalla(ui.modelo);
    ui.firmaUrls = '';
    ui.op.irA('gimnasio');
    ui.modelo.refrescar().then(() => ui.modelo && ui.modelo.drenarEnFondo()).catch(() => {});
  }
  /* Simplificar (11/11, web_230): desde «Mi gimnasio y mi técnica» se vuelve ahí. */
  function cerrar() { if (ui.op) ui.op.irA(ui.origen === 'misdatos' || ui.origen === 'dondeentreno' ? ui.origen : 'train'); }
  function apilar(d) { ui.pila.push(d); ui.error = null; ui.firmaUrls = ''; renderEscena(); window.scrollTo(0, 0); }

  async function empezar(modo) {
    const m = ui.modelo;
    ui.ocupado = true; renderEscena();
    let r = 'ok';
    try { r = await m.empezar(modo); } finally { ui.ocupado = false; }
    ui.error = r === 'ok' ? (m.pantalla === 'inicio' ? T.sinSenal : null) : r === 'sinSenal' ? T.sinSenal : T.errorGenerico;
    renderEscena();
  }

  // ── Toques ──
  const ACCIONES = {
    volver() { if (ui.pila.length) { if (tope().t === 'zona' && ui.modelo) ui.modelo.limpiarAvisoFoto(); ui.pila.pop(); ui.error = null; ui.firmaUrls = ''; renderEscena(); } else cerrar(); },
    empezar() { ui.error = null; return empezar('completa'); },
    zona(b) { apilar({ t: 'zona', clave: b.dataset.z }); },
    revisar() { apilar({ t: 'revisar' }); },
    yaNoEsta() { ui.marcadosQuitar = new Set(); apilar({ t: 'yaNoEsta' }); },
    agregar(b) {
      const m = ui.modelo;
      const pid = b.dataset.p != null ? m.abierta.preguntas[Number(b.dataset.p)].id : null;
      pedirFoto(b.dataset.z, pid);
    },
    async borrar(b) {
      const r = await ui.modelo.borrarFoto(b.dataset.id);
      ui.error = r === 'ok' ? null : r === 'sinSenal' ? T.sinSenal : T.errorGenerico;
      renderEscena();
    },
    nohay(b) { ui.modelo.marcarNoHay(b.dataset.z, !ui.modelo.noHay.has(b.dataset.z)); },
    enviar() { const n = document.getElementById('gimNota'); if (n) ui.modelo.fijarNota(n.value); ui.modelo.enviarCarga(); },
    volverEditar() { ui.modelo.cancelarEnvio(); },
    nuevo(b) { empezar(b.dataset.modo); },
    marcarQuitar(b) {
      const q = ui.modelo.vigente.equipos[Number(b.dataset.i)];
      if (!ui.marcadosQuitar.delete(q.tipo)) ui.marcadosQuitar.add(q.tipo);
      renderEscena();
    },
    async enviarQuitar() {
      const m = ui.modelo;
      ui.ocupado = true; renderEscena();
      let r;
      try { r = await m.empezar('parcial'); } finally { ui.ocupado = false; }
      if (r !== 'ok' || !m.abierta || m.abierta.modo !== 'parcial') { ui.error = r === 'sinSenal' ? T.sinSenal : T.errorGenerico; renderEscena(); return; }
      for (const t of ui.marcadosQuitar) if (!m.quitar.has(t)) m.alternarQuitar(t);
      await m.enviarCarga();
    },
    anterior() { ui.indice = Math.max(0, ui.indice - 1); ui.firmaUrls = ''; renderEscena(); window.scrollTo(0, 0); },
    siguiente() { ui.indice += 1; ui.firmaUrls = ''; renderEscena(); window.scrollTo(0, 0); },
    enviarRespuestas() { ui.modelo.enviarRespuestas(); },
    multi(b) {
      const m = ui.modelo, p = preguntaActual();
      const s = new Set(Array.isArray(m.respuestas[p.id]) ? m.respuestas[p.id] : []);
      const val = p.opciones[Number(b.dataset.k)].valor;
      if (!s.delete(val)) s.add(val);
      m.responder(p.id, p.opciones.map((o) => o.valor).filter((v) => s.has(v)));
    },
    uno(b) {
      const m = ui.modelo, p = preguntaActual(), val = p.opciones[Number(b.dataset.k)].valor;
      m.responder(p.id, m.respuestas[p.id] === val ? null : val);
    },
    noSe() {
      const m = ui.modelo, p = preguntaActual();
      if (p.clase === 'numero') delete ui.kilos[p.id];
      m.responder(p.id, m.respuestas[p.id] === 'no_se' ? null : 'no_se');
    },
    confirmar(b) {
      const m = ui.modelo, p = preguntaActual(), tipo = p.items[Number(b.dataset.k)].tipo;
      const mapa = { ...(m.respuestas[p.id] && typeof m.respuestas[p.id] === 'object' ? m.respuestas[p.id] : {}) };
      if (mapa[tipo] === b.dataset.v) delete mapa[tipo]; else mapa[tipo] = b.dataset.v;
      m.responder(p.id, Object.keys(mapa).length ? mapa : null);
    },
    noPuedo() { const m = ui.modelo, p = preguntaActual(); m.responder(p.id, m.respuestas[p.id] === 'no_puedo' ? null : 'no_puedo'); },
  };
  function preguntaActual() { const ps = ui.modelo.abierta.preguntas; return ps[Math.min(ui.indice, ps.length - 1)]; }

  function enganchar() {
    if (ui.enganchado) return;
    ui.enganchado = true;
    const r = raizEscena();
    if (r) {
      r.addEventListener('click', (ev) => {
        const b = ev.target.closest('[data-gim]');
        if (!b || b.disabled || !ui.modelo) return;
        // Si el navegador no le sacó el foco al campo, la pantalla que viene no se pintaría.
        const foco = document.activeElement;
        if (foco && r.contains(foco) && foco !== b && (foco.tagName === 'INPUT' || foco.tagName === 'TEXTAREA')) foco.blur();
        const f = ACCIONES[b.dataset.gim];
        if (f) { const p = f(b); if (p && p.catch) p.catch(() => {}); }
      });
      r.addEventListener('input', (ev) => {
        const m = ui.modelo;
        if (!m) return;
        if (ev.target.id === 'gimNota') {
          m.fijarNota(ev.target.value);
          const c = document.getElementById('gimNotaCuenta');
          if (c) c.textContent = `${Array.from(ev.target.value).length}/${G.MAX_NOTA}`;
        } else if (ev.target.id === 'gimKilos') {
          const p = preguntaActual(), s = ev.target.value, n = G.kilos(s);
          ui.kilos[p.id] = s;
          if (n !== null) m.responder(p.id, n);
          else if (m.respuestas[p.id] !== 'no_se') m.responder(p.id, null);
          const mal = document.getElementById('gimKilosMal');
          if (mal) mal.hidden = !(s !== '' && n === null);
        }
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
    return navigator.locks.request(`gimnasio-cola-${token}`, () => fn());
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
      if (ui.modelo) { ui.modelo.apagar(); ui.modelo = null; if (raiz.CasaUI) raiz.CasaUI.conGimnasio(null); pintar(); }
      return;
    }
    if (ui.modelo) return;
    ui.arrancando = true;
    try {
      // Antes de abrir nada en el teléfono: a una cuenta sin la función no se le crea ni la base.
      const primera = await ui.op.rpc('mypump_gimnasio_get', { p_token: ui.op.token });
      if (primera.ok ? !raiz.Gimnasio.decodificarEstado(primera.data) : (primera.status === 404 || primera.codigo === 'PGRST202' || primera.clase === 'permanente')) return;
      const almacen = await raiz.GimnasioCola.abrirAlmacen();
      const m = new raiz.GimnasioCola.ModeloGimnasio({
        rpc: ui.op.rpc, almacen, token: ui.op.token, visionUrl: ui.op.visionUrl, conLock: conLock(ui.op.token),
      });
      await m.cargar();
      if (raiz.CasaUI) raiz.CasaUI.conGimnasio(m, pintar);      // con la palanca `casa`, cada refresco trae también lo de casa
      await m.refrescar(primera);
      m.alCambiar = pintar;
      ui.modelo = m;
      ui.ultimoRefresco = Date.now();
      enganchar();
      pintar();
      m.reanudar();
    } catch (_) {
      ui.modelo = null;
      if (raiz.CasaUI) raiz.CasaUI.conGimnasio(null);
    } finally {
      ui.arrancando = false;
    }
  }

  raiz.GimnasioUI = {
    configurar, aplicarPalanca, montarTarjeta, abrir, renderEscena, titulo,
    entradaVisible: () => !!(ui.modelo && ui.modelo.entradaVisible),
    /* Para «Mi gimnasio y mi técnica»: la línea de la tarjeta (lo que falta, o casa) y el texto del botón de casa. */
    detalle: () => {
      const m = ui.modelo;
      if (!m || !m.estado) return null;
      if (m.tarjetaVisible) return detalleTarjeta(m);
      return raiz.CasaUI ? raiz.CasaUI.detalleTarjeta() : null;   // con el gimnasio ya cargado, solo lo de casa (si hay)
    },
    /* Va en «Mi gimnasio y mi técnica» con el gimnasio ya cargado o con «Entreno en casa» habilitado (como el iPhone). */
    enHub: () => {
      const m = ui.modelo, c = raiz.CasaUI && raiz.CasaUI._modelo;
      return !!(m && m.estado) && (!!m.entradaVisible || !!(c && c.estado && c.interruptor));
    },
    textoCasa: () => (raiz.CasaUI && raiz.CasaUI.botonTarjeta ? raiz.CasaUI.botonTarjeta() : null),
    get origen() { return ui.origen; },
    get _modelo() { return ui.modelo; },
  };
})(window);
