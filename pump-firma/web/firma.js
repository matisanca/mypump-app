'use strict';
/* Página de firma. Sin dependencias. Todo texto legal llega del servidor: acá no se redacta nada.
   Orden de la pantalla (no cambiarlo): documento completo → renglón del prestador → casilla optativa → casillas
   obligatorias → identidad → código → avisos del documento (el de revocación queda último) → dibujo de la firma y botón. */
(function () {
  var app = document.getElementById('app');
  var token = (location.pathname.match(/^\/f\/([0-9a-f]{40,64})$/) || [])[1] || '';
  var D = null;                 // lo que devolvió /api/doc
  var estado = { leido: false, casillas: {}, firmo: false, enviando: false, confirma: {} };

  function el(tag, attrs, hijos) {
    var e = document.createElement(tag);
    Object.keys(attrs || {}).forEach(function (k) {
      if (k === 'texto') e.textContent = attrs[k];
      else if (k === 'html') e.innerHTML = attrs[k];   // solo HTML que arma nuestro servidor
      else if (k === 'clase') e.className = attrs[k];
      else e.setAttribute(k, attrs[k]);
    });
    (hijos || []).forEach(function (h) { if (h) e.appendChild(h); });
    return e;
  }
  function api(ruta, cuerpo) {
    cuerpo = cuerpo || {}; cuerpo.t = token;
    return fetch(ruta, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(cuerpo), cache: 'no-store' })
      .then(function (r) { return r.json().then(function (j) { j._http = r.status; return j; }, function () { return { error: 'interno', _http: r.status }; }); },
            function () { return { error: 'red', _http: 0 }; });
  }
  function textoError(r) {
    if (r.error === 'red') return 'No hay conexión. No se firmó nada: revisá tu conexión y probá de nuevo.';
    var e = (D && D.errores) || {};
    return e[r.error] || e.interno || 'Algo falló y no se firmó nada. Probá de nuevo en un momento.';
  }
  function fecha(iso) {
    try { return new Date(iso).toLocaleString('es-AR', { dateStyle: 'long', timeStyle: 'short' }); } catch (e) { return iso; }
  }
  function limpiar() { while (app.firstChild) app.removeChild(app.firstChild); }
  function mensaje(clase, t) { return el('p', { clase: 'mensaje ' + clase, texto: t, role: clase === 'mal' ? 'alert' : 'status' }); }

  // ── arranque ──
  if (!token) { limpiar(); app.appendChild(mensaje('mal', 'Este enlace no es válido. Revisá que esté completo o pedinos uno nuevo.')); return; }
  api('/api/doc').then(function (r) {
    limpiar();
    if (r.error) { app.appendChild(mensaje('mal', r.error === 'red' ? textoError(r) : (r.error === 'anulado' ? 'Este enlace ya no está vigente porque te mandamos uno nuevo. Usá el último que te llegó.' : 'Este enlace no es válido. Revisá que esté completo o pedinos uno nuevo.'))); return; }
    D = r;
    document.getElementById('contacto').textContent = D.contacto;
    if (D.estado === 'pendiente') pantallaFirma(); else pantallaFirmado();
  });

  // ── documento firmado: ver, bajar, revocar o pedir la baja ──
  function pantallaFirmado(recien) {
    limpiar();
    var t = el('section', { clase: 'tarjeta' });
    t.appendChild(el('h1', { texto: D.titulo ? quitarHtml(D.titulo) : 'Documento' }));
    if (D.estado === 'revocado') t.appendChild(mensaje('aviso', 'Revocaste este consentimiento el ' + fecha(D.revocado_en) + '.'));
    else t.appendChild(mensaje('bien', (recien ? 'Listo, quedó firmado. ' : 'Firmado el ' + fecha(D.firmado_en) + '. ') + 'Te mandamos una copia en PDF a ' + D.correo + '.'));
    if (D.baja_pedida_en) t.appendChild(mensaje('aviso', 'Recibimos tu pedido el ' + fecha(D.baja_pedida_en) + '. Te escribimos para confirmarte cómo sigue.'));
    t.appendChild(el('a', { clase: 'boton', href: '/f/' + token + '/documento.pdf', target: '_blank', rel: 'noopener', texto: 'Ver o bajar el PDF' }));
    if (D.sha256) t.appendChild(el('p', { clase: 'chico', texto: 'Identificador: ' + D.id + ' · Huella SHA-256: ' + D.sha256 }));
    app.appendChild(t);
    if (D.puede_revocar) app.appendChild(panelSalida('revocacion', 'Revocar este consentimiento', 'Revocación del consentimiento',
      'Podés revocar tu consentimiento cuando quieras. Desde ese momento el Dr. Sancari no emite órdenes ni recetas a tu nombre. Tus otros contratos no cambian.', '/api/revocar'));
    if (D.baja && !D.baja_pedida_en) app.appendChild(panelSalida('baja', D.baja.boton, D.baja.titulo,
      'Tu pedido queda registrado con fecha y hora, y te escribimos para confirmarte cómo sigue.', '/api/baja', D.baja.confirmar));
  }
  function panelSalida(proposito, rotulo, titulo, explicacion, ruta, rotuloConfirmar) {
    var caja = el('section', { clase: 'tarjeta salida' });
    var abrir = el('button', { clase: 'boton secundario', type: 'button', texto: rotulo });
    var cuerpo = el('div', { clase: 'oculto' });
    var motivo = el('textarea', { rows: '3', maxlength: '500', placeholder: 'Motivo (optativo)' });
    var cod = campoCodigo(proposito);
    var aviso = el('div');
    var confirmar = el('button', { clase: 'boton peligro', type: 'button', texto: rotuloConfirmar || 'Confirmar' });
    cuerpo.appendChild(el('h2', { texto: titulo }));
    cuerpo.appendChild(el('p', { texto: explicacion }));
    cuerpo.appendChild(motivo); cuerpo.appendChild(cod.nodo); cuerpo.appendChild(aviso); cuerpo.appendChild(confirmar);
    abrir.addEventListener('click', function () { cuerpo.classList.remove('oculto'); abrir.classList.add('oculto'); });
    confirmar.addEventListener('click', function () {
      aviso.textContent = '';
      if (!/^\d{6}$/.test(cod.valor())) { aviso.appendChild(mensaje('mal', D.errores.sin_codigo)); return; }
      confirmar.disabled = true;
      api(ruta, { codigo: cod.valor(), motivo: motivo.value }).then(function (r) {
        confirmar.disabled = false;
        if (r.error) { aviso.appendChild(mensaje('mal', textoError(r))); return; }
        api('/api/doc').then(function (d) { if (!d.error) { D = d; pantallaFirmado(); } });
      });
    });
    caja.appendChild(abrir); caja.appendChild(cuerpo);
    return caja;
  }

  // ── el código por correo ──
  function campoCodigo(proposito) {
    var nodo = el('div', { clase: 'codigo' });
    var pedir = el('button', { clase: 'boton secundario', type: 'button', texto: 'Mandarme el código a ' + D.correo });
    var entrada = el('input', { type: 'text', inputmode: 'numeric', autocomplete: 'one-time-code', maxlength: '6', pattern: '[0-9]{6}', placeholder: 'Código de 6 dígitos', 'aria-label': 'Código de 6 dígitos' });
    var nota = el('div');
    entrada.addEventListener('input', function () { entrada.value = entrada.value.replace(/\D/g, '').slice(0, 6); revisar(); });
    pedir.addEventListener('click', function () {
      pedir.disabled = true; nota.textContent = '';
      api('/api/codigo', { proposito: proposito }).then(function (r) {
        if (r.error) { nota.appendChild(mensaje('mal', textoError(r))); pedir.disabled = false; return; }
        nota.appendChild(mensaje('bien', 'Te mandamos el código a ' + r.correo + '. Vale por ' + r.minutos + ' minutos. Si no lo ves, mirá en correo no deseado.'));
        pedir.textContent = 'Mandarme otro código';
        setTimeout(function () { pedir.disabled = false; }, 46000);
        entrada.focus();
      });
    });
    nodo.appendChild(pedir); nodo.appendChild(entrada); nodo.appendChild(nota);
    return { nodo: nodo, valor: function () { return entrada.value; } };
  }

  // ── la pantalla de firma ──
  var refs = {};
  function pantallaFirma() {
    limpiar();
    app.appendChild(el('section', { clase: 'tarjeta medio' }, [el('p', { texto: D.aviso_medio })]));

    var doc = el('article', { clase: 'tarjeta documento' });
    doc.appendChild(el('h1', { html: D.titulo }));
    if (D.subtitulo) doc.appendChild(el('p', { clase: 'subtitulo', html: D.subtitulo }));
    doc.appendChild(el('div', { clase: 'cuerpo', html: D.cuerpo_html }));
    var fin = el('div', { clase: 'fin', 'aria-hidden': 'true' });
    doc.appendChild(fin);
    doc.appendChild(el('p', { clase: 'chico' }, [el('a', { href: '/f/' + token + '/documento.pdf', target: '_blank', rel: 'noopener', texto: 'Ver este documento en PDF' })]));
    app.appendChild(doc);
    if ('IntersectionObserver' in window) {
      var ojo = new IntersectionObserver(function (xs) {
        if (xs.some(function (x) { return x.isIntersecting; }) && !estado.leido) { estado.leido = true; api('/api/evento', { tipo: 'fin_lectura' }); ojo.disconnect(); revisar(); }
      });
      ojo.observe(fin);
    } else { estado.leido = true; }

    var f = el('section', { clase: 'tarjeta firmas' });
    f.appendChild(el('h2', { texto: 'Firmas' }));
    var puseControles = false;
    function controles() {
      if (puseControles) return; puseControles = true;
      D.casillas.filter(function (c) { return c.clave !== 'inicio_anticipado'; }).forEach(function (c) { f.appendChild(casilla(c)); });
      f.appendChild(identidad());
      f.appendChild(el('h3', { texto: 'Validá tu correo' }));
      refs.codigo = campoCodigo('firma');
      f.appendChild(refs.codigo.nodo);
    }
    D.firmas.forEach(function (p) {
      if (p.pieza === 'prestador') f.appendChild(el('p', { clase: 'prestador', html: p.html }));
      else if (p.pieza === 'inicio_anticipado') {
        var c = D.casillas.filter(function (x) { return x.clave === 'inicio_anticipado'; })[0];
        if (c) f.appendChild(casilla(c));
      } else if (p.pieza === 'aviso') { controles(); f.appendChild(el('p', { clase: 'aviso', html: p.html })); }
      else if (p.pieza === 'firmante') {
        controles();
        if (D.aviso_es) f.appendChild(el('p', { clase: 'aviso', texto: D.aviso_es }));
        f.appendChild(lienzo());
      }
    });
    refs.faltan = el('div', { clase: 'faltan' });
    refs.boton = el('button', { clase: 'boton principal', type: 'button', texto: D.boton });
    refs.boton.addEventListener('click', firmar);
    refs.aviso = el('div');
    f.appendChild(refs.faltan); f.appendChild(refs.aviso); f.appendChild(refs.boton);
    app.appendChild(f);
    revisar();
  }

  function casilla(c) {
    var id = 'c_' + c.clave;
    var caja = el('input', { type: 'checkbox', id: id });
    estado.casillas[c.clave] = false;
    caja.addEventListener('change', function () {
      estado.casillas[c.clave] = caja.checked;
      api('/api/evento', { tipo: 'casilla', datos: { casilla: c.clave, valor: caja.checked } });
      revisar();
    });
    var rot = el('label', { for: id });
    rot.appendChild(el('span', { clase: 'etiqueta ' + (c.obligatoria ? 'obligatoria' : 'optativa'), texto: c.obligatoria ? 'Obligatoria' : 'Optativa' }));
    rot.appendChild(el('span', { texto: ' ' + c.texto }));
    return el('div', { clase: 'casilla' + (c.obligatoria ? '' : ' optativa') }, [caja, rot]);
  }

  function identidad() {
    var caja = el('div', { clase: 'identidad' });
    caja.appendChild(el('h3', { texto: 'Tus datos' }));
    caja.appendChild(el('p', { clase: 'chico', texto: 'Escribí tu nombre y apellido y tu documento como figuran arriba, en el documento.' }));
    refs.nombre = el('input', { type: 'text', autocomplete: 'name', maxlength: '120' });
    refs.documento = el('input', { type: 'text', autocomplete: 'off', maxlength: '40', inputmode: D.documento_rotulo === 'DNI' ? 'numeric' : 'text' });
    caja.appendChild(el('label', { clase: 'campo', texto: 'Nombre y apellido' }, [refs.nombre]));
    caja.appendChild(el('label', { clase: 'campo', texto: D.documento_rotulo }, [refs.documento]));
    refs.domicilio = el('input', { type: 'text', autocomplete: 'street-address', maxlength: '200' });
    var dom = el('label', { clase: 'campo' + (D.pide_domicilio ? '' : ' oculto'), texto: D.pide_domicilio ? 'Domicilio' : 'Domicilio correcto' }, [refs.domicilio]);
    caja.appendChild(dom);
    if (!D.pide_domicilio) {
      var corr = el('button', { clase: 'enlace', type: 'button', texto: 'Mi domicilio está mal en el documento' });
      corr.addEventListener('click', function () { dom.classList.remove('oculto'); corr.classList.add('oculto'); refs.domicilio.focus(); });
      caja.appendChild(corr);
    }
    refs.correcciones = el('div');
    caja.appendChild(refs.correcciones);
    var avisado = false;
    [refs.nombre, refs.documento, refs.domicilio].forEach(function (i) {
      i.addEventListener('input', revisar);
      i.addEventListener('blur', function () { if (!avisado && refs.nombre.value.trim() && refs.documento.value.trim()) { avisado = true; api('/api/evento', { tipo: 'identidad_escrita' }); } });
    });
    return caja;
  }

  function lienzo() {
    var caja = el('div', { clase: 'lienzo' });
    caja.appendChild(el('h3', { texto: 'Tu firma' }));
    caja.appendChild(el('p', { clase: 'chico', texto: 'Dibujá tu firma con el dedo o con el mouse.' }));
    var c = el('canvas', { 'aria-label': 'Recuadro para dibujar tu firma', role: 'img' });
    var borrar = el('button', { clase: 'enlace', type: 'button', texto: 'Borrar y volver a firmar' });
    caja.appendChild(c); caja.appendChild(borrar);
    var ctx, dibujando = false, largo = 0, ult = null;
    function preparar() {
      var r = c.getBoundingClientRect(), dpr = Math.min(window.devicePixelRatio || 1, 2);
      c.width = Math.round(Math.max(280, r.width) * dpr); c.height = Math.round(160 * dpr);
      ctx = c.getContext('2d'); ctx.scale(dpr, dpr); ctx.lineWidth = 2.2; ctx.lineCap = 'round'; ctx.lineJoin = 'round'; ctx.strokeStyle = '#111';
      largo = 0; estado.firmo = false; revisar();
    }
    function punto(e) { var r = c.getBoundingClientRect(); return { x: e.clientX - r.left, y: e.clientY - r.top }; }
    c.addEventListener('pointerdown', function (e) { e.preventDefault(); c.setPointerCapture(e.pointerId); dibujando = true; ult = punto(e); });
    c.addEventListener('pointermove', function (e) {
      if (!dibujando) return; e.preventDefault();
      var p = punto(e); ctx.beginPath(); ctx.moveTo(ult.x, ult.y); ctx.lineTo(p.x, p.y); ctx.stroke();
      largo += Math.abs(p.x - ult.x) + Math.abs(p.y - ult.y); ult = p;
      if (largo > 120 && !estado.firmo) { estado.firmo = true; revisar(); }
    });
    ['pointerup', 'pointercancel', 'pointerleave'].forEach(function (n) { c.addEventListener(n, function () { dibujando = false; }); });
    borrar.addEventListener('click', preparar);
    setTimeout(preparar, 0);
    refs.png = function () {
      // fondo blanco y tamaño acotado: lo que viaja es lo que se ve
      var s = document.createElement('canvas'), w = Math.min(c.width, 900), h = Math.round(c.height * w / c.width);
      s.width = w; s.height = h; var x = s.getContext('2d'); x.fillStyle = '#fff'; x.fillRect(0, 0, w, h); x.drawImage(c, 0, 0, w, h);
      return s.toDataURL('image/png');
    };
    return caja;
  }

  function faltantes() {
    var f = [];
    if (!estado.leido) f.push('Llegar hasta el final del documento');
    D.casillas.forEach(function (c) { if (c.obligatoria && !estado.casillas[c.clave]) f.push('Marcar la casilla obligatoria: «' + c.texto.slice(0, 60) + '…»'); });
    if (!refs.nombre || refs.nombre.value.trim().split(/\s+/).length < 2) f.push('Escribir tu nombre y apellido');
    if (!refs.documento || refs.documento.value.trim().length < 5) f.push('Escribir tu ' + D.documento_rotulo);
    if (D.pide_domicilio && refs.domicilio.value.trim().length < 5) f.push('Escribir tu domicilio');
    if (!refs.codigo || !/^\d{6}$/.test(refs.codigo.valor())) f.push('Pedir el código y escribirlo');
    if (!estado.firmo) f.push('Dibujar tu firma');
    return f;
  }
  function revisar() {
    if (!refs.boton) return;
    var f = faltantes();
    refs.boton.disabled = estado.enviando || f.length > 0;
    refs.faltan.textContent = '';
    if (f.length) {
      refs.faltan.appendChild(el('p', { clase: 'chico', texto: 'Para firmar falta:' }));
      refs.faltan.appendChild(el('ul', {}, f.map(function (x) { return el('li', { texto: x }); })));
    }
  }

  var ROTULO = { nombre: 'nombre y apellido', documento: 'documento' };
  function pedirConfirmacion(errores) {
    refs.correcciones.textContent = '';
    var hubo = false;
    errores.forEach(function (e) {
      if (e.error === 'no_coincide') {
        hubo = true;
        var id = 'conf_' + e.campo, caja = el('input', { type: 'checkbox', id: id });
        caja.addEventListener('change', function () { estado.confirma[e.campo] = caja.checked; });
        refs.correcciones.appendChild(el('div', { clase: 'casilla correccion' }, [caja, el('label', { for: id,
          texto: 'El ' + ROTULO[e.campo] + ' que escribiste no coincide con el que figura en el documento. Si te equivocaste al escribir, corregilo. Si el que está mal es el del documento, marcá esta casilla y el documento se firma con el que escribiste vos.' })]));
      } else {
        refs.correcciones.appendChild(mensaje('mal', e.campo === 'documento' ? 'Revisá tu ' + D.documento_rotulo + ': no parece válido.' : (e.campo === 'domicilio' ? 'Escribí tu domicilio completo.' : 'Escribí tu nombre y apellido completos.')));
      }
    });
    return hubo;
  }

  function firmar() {
    if (estado.enviando || faltantes().length) return;
    estado.enviando = true; refs.boton.disabled = true; refs.boton.textContent = 'Firmando…'; refs.aviso.textContent = '';
    var cuerpo = {
      casillas: estado.casillas, nombre: refs.nombre.value, documento: refs.documento.value, domicilio: refs.domicilio.value,
      codigo: refs.codigo.valor(), firma_png: refs.png(),
      confirma_correccion: Object.keys(estado.confirma).filter(function (k) { return estado.confirma[k]; })
    };
    api('/api/firmar', cuerpo).then(function (r) {
      estado.enviando = false; refs.boton.textContent = D.boton;
      if (r.ok) { api('/api/doc').then(function (d) { if (!d.error) { D = d; pantallaFirmado(true); window.scrollTo(0, 0); } }); return; }
      if (r.error === 'identidad') { pedirConfirmacion(r.errores || []); refs.aviso.appendChild(mensaje('mal', 'Revisá tus datos. No se firmó nada todavía.')); refs.nombre.scrollIntoView({ block: 'center' }); }
      else refs.aviso.appendChild(mensaje('mal', textoError(r)));
      revisar();
    });
  }

  function quitarHtml(h) { var d = document.createElement('div'); d.innerHTML = h; return d.textContent; }
})();
