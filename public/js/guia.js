/* =============================================================
   guia.js — «Tu guía» en la web del cliente

   Port de la sección de la app nativa MyPump 2.2.0 (rama nativa-220):
   · apps/ios/MyPump/Guia/GuiaView.swift, GuiaDestacada.swift,
     ReproductorGuia.swift, AudioDudaView.swift, AgendaView.swift y
     FormaVideo.swift (la interfaz);
   · las reglas puras y la lectura del JSON están en js/reglas-guia.js
     (MyPumpReglas/Guia.swift, Agenda.swift y FormatoVideo.swift), que se
     carga antes que este archivo;
   · MyPumpDatos/Guia.swift, Agenda.swift, AudioDuda.swift y Escrituras.swift
     (las RPC y las colas).
   2.2.0: la NOVEDAD arriba de la guía, los videos obligatorios, la agenda de
   la entrega al final y el recorte de las franjas negras de los videos.

   Módulo independiente: no depende de la estructura de cliente.html. Usa
   window.mypumpDB (supabase-client.js) y las variables de css/tokens.css.
   Inyecta su propio <style> (prefijo .gu-) y dibuja la guía en un overlay
   fijo propio.

   API (window.MyPumpGuia):
   · cargarResumen(token)            → Promise<resumen | null>
   · montarTarjeta(contenedor, token) → Promise<boolean> (si dibujó algo)
   · abrir(token)                    → abre la guía a pantalla completa
   · cerrar()
   · bienvenidaSiCorresponde(token, {nombre}) → Promise<boolean>
   · quitada(token), quitar(token), volverAMostrar(token)
   · mostrarFila(token), puedeVolverAMostrar(token)
   · alCambiar(fn)                   → función para desuscribirse
   ============================================================= */
(function () {
  'use strict';
  if (window.MyPumpGuia) return;

  // ─── Constantes (ReglasGuia y ReglasAudioDuda) ─────────────────
  const MAX_DUDAS_LLAMADA = 30;      // compartido con la web y la app
  const PLACA_MS = 2600;             // la placa al cambiar de video
  const INTENTOS_MAX = 8;            // la cola abandona después de 8 rechazos
  const AUDIO_TOPE = 300;            // corta solo a los 5 minutos
  const AUDIO_AVISO = 270;           // «Te quedan 30 segundos.»
  const AUDIO_MINIMO = 2;            // menos de esto no se manda
  const AUDIO_BITRATE = 64000;
  const SONDEO_CADA_MS = 15000;      // la lista de audios, cada 15 s
  const SONDEO_MAX_MS = 180000;      // como mucho 3 minutos

  // ─── Utilidades ─────────────────────────────────────────────────
  function esc(s) {
    return String(s == null ? '' : s)
      .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;').replace(/'/g, '&#39;');
  }

  // Un hash corto del token para las claves de localStorage (no se guarda el
  // token en la clave). FNV-1a de 32 bits, dos pasadas para 64 bits de largo.
  function hashToken(t) {
    let a = 0x811c9dc5, b = 0x01000193 ^ 0x5bd1e995;
    for (let i = 0; i < t.length; i++) {
      const c = t.charCodeAt(i);
      a ^= c; a = Math.imul(a, 0x01000193) >>> 0;
      b ^= c; b = Math.imul(b, 0x01000193 + 0x9e) >>> 0;
    }
    return a.toString(36) + b.toString(36);
  }

  const almacen = {
    leer(k, def) {
      try { const v = localStorage.getItem(k); return v == null ? def : JSON.parse(v); } catch (_) { return def; }
    },
    guardar(k, v) { try { localStorage.setItem(k, JSON.stringify(v)); } catch (_) { /* lleno o privado */ } },
    borrar(k) { try { localStorage.removeItem(k); } catch (_) { /* nada */ } },
  };

  function uuid() {
    if (window.crypto && typeof crypto.randomUUID === 'function') return crypto.randomUUID();
    const b = new Uint8Array(16);
    crypto.getRandomValues(b);
    b[6] = (b[6] & 0x0f) | 0x40; b[8] = (b[8] & 0x3f) | 0x80;
    const h = Array.from(b, x => x.toString(16).padStart(2, '0')).join('');
    return `${h.slice(0, 8)}-${h.slice(8, 12)}-${h.slice(12, 16)}-${h.slice(16, 20)}-${h.slice(20)}`;
  }

  function esDemo() {
    try { return new URLSearchParams(location.search).get('demo') === '1'; } catch (_) { return false; }
  }
  const db = () => window.mypumpDB || null;

  // La palanca `elegir_horario` (mypump_app_config, videollamada 2.3.0). Sin la
  // clave, apagada: la agenda de la guía queda como en la 2.2.0 y nunca se llama
  // a entregas_app_cambiar. Sin red queda lo último que se supo.
  const FLAG_ELEGIR = 'mypump_palanca_elegir_horario';
  let _elegirHorario = (() => { try { return localStorage.getItem(FLAG_ELEGIR) === '1'; } catch (_) { return false; } })();
  const palancaElegirHorario = () => _elegirHorario;
  const tokenValido = t => typeof t === 'string' && t.length > 0;
  const reducirMovimiento = () => !!(window.matchMedia && matchMedia('(prefers-reduced-motion: reduce)').matches);
  const fmtNum = n => Number(n).toLocaleString('es-AR');

  // ─── Las reglas puras: js/reglas-guia.js (window.ReglasGuia) ────
  // Sin ese archivo (un caché viejo a medio actualizar) la guía no arranca.
  const RG = window.ReglasGuia;
  if (!RG) return;
  const { MAX_TEXTO, MAX_SEGUNDOS, texto, esObjeto, lista, largo, R, RD, RA, RV, AvanceVideo, vistaSuplementacion,
          normalizarGuia, normalizarResumen, normalizarAgenda, normalizarReserva } = RG;

  // ─── Textos del audio (ReglasAudioDuda) ─────────────────────────
  // El cliente no se entera de que el audio se pasa a texto (Mati, 4-nov).
  const TA = {
    invitacion: '¿Te es más fácil hablarlo? Mandame un audio, como por WhatsApp. Hasta 5 minutos cada uno.',
    grabar: 'Grabar un audio',
    terminar: 'Terminar',
    terminarAccesible: 'Terminar de grabar',
    antesDelPermiso: 'Te va a pedir permiso para usar el micrófono, aceptalo así te escucho.',
    mandar: 'Mandar',
    grabarDeNuevo: 'Grabar de nuevo',
    borrar: 'Borrar',
    mandando: 'Mandando tu audio…',
    noSeMando: 'No se pudo mandar.',
    reintentar: 'Reintentar',
    errorTranscripcion: 'No pude escuchar bien este audio, ¿me lo mandás de nuevo o lo escribís?',
    subido: despues => (despues ? 'Listo, me llegó tu audio, te contesto por WhatsApp.'
                                : 'Listo, me llegó tu audio, lo escucho antes de la videollamada.'),
    grabaste: s => `Grabaste ${contador(s)}`,
    avisos: {
      // En el navegador no hay «Ajustes, MyPump»: va el texto de la web (pack.html).
      permisoNegado: 'Tu celu no me dio permiso para el micrófono. En iPhone andá a Ajustes, Safari, Micrófono y ponelo en Permitir. En Android tocá el candado al lado de la dirección y habilitá el micrófono. O escribime la duda acá arriba.',
      sinMicrofono: 'No encontré un micrófono en este dispositivo. Escribime la duda acá arriba.',
      ocupado: 'El micrófono lo está usando otra app. Cerrala y probá de nuevo.',
      muyCorto: 'No se escuchó nada, probá de nuevo.',
      quedan30: 'Te quedan 30 segundos.',
      tope: 'Ya me mandaste 10 audios. Lo que te falte escribímelo o lo vemos en la llamada.',
      pendientes: 'Esperá un toque que se terminen de mandar los otros audios.',
      largo: 'Es muy largo, mandámelo en audios de hasta 5 minutos.',
      formato: 'Este audio está en un formato que no puedo recibir. Escribime la duda acá arriba.',
      noSeMando: 'No se pudo mandar.',
      yaFallo: 'No pude escuchar bien este audio, ¿me lo mandás de nuevo o lo escribís?',
    },
  };
  function contador(seg) {
    const s = Math.max(0, Math.trunc(isFinite(seg) ? seg : 0));
    return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`;
  }
  function avisoDeMotivo(m) {
    switch (m) {
      case 'tope': return 'tope';
      case 'pendientes': return 'pendientes';
      case 'tamano': case 'largo': return 'largo';
      case 'formato': return 'formato';
      case 'error': return 'yaFallo';
      default: return 'noSeMando';
    }
  }

  // ─── Dudas en audio (ModeloAudioDuda) ───────────────────────────
  // En la web el audio queda en memoria hasta que sube (como pack.html): si
  // falla, «No se pudo mandar» con «Reintentar» y el mismo p_id.
  function soportaAudio() {
    return !!(window.isSecureContext && navigator.mediaDevices && navigator.mediaDevices.getUserMedia && window.MediaRecorder);
  }
  function elegirMime() {
    const ok = t => { try { return MediaRecorder.isTypeSupported(t); } catch (_) { return false; } };
    const webkit = /Apple/.test(navigator.vendor || '') && !/CriOS|FxiOS|EdgiOS/.test(navigator.userAgent || '');
    // Safari graba en audio/mp4 (AAC); Chrome y Android en audio/webm (opus).
    const orden = webkit ? ['audio/mp4', 'audio/webm;codecs=opus', 'audio/webm']
                         : ['audio/webm;codecs=opus', 'audio/webm', 'audio/mp4', 'audio/ogg;codecs=opus'];
    return orden.find(ok) || '';
  }

  class Audios {
    constructor(modelo) {
      this.m = modelo;
      this.soporte = soportaAudio();
      this.disponible = false;     // entregas_app_audios respondió alguna vez
      this.fase = 'reposo';        // reposo | pidiendo | grabando | revisando
      this.aviso = null;
      this.avisoDado = false;
      this.segundos = 0;
      this.permiso = 'sinPreguntar';
      this.servidor = [];
      this.locales = [];
      this.blob = null; this.url = null; this.mime = '';
      this._rec = null; this._stream = null; this._chunks = []; this._inicio = 0; this._tics = null;
      this._cancelado = false;
      this._sondeo = null; this._sondeoInicio = 0;
      this.seccionAbierta = false;
      this.escucha = null;         // el Audio de la revisión
      this.alEmpezar = null;       // la vista pausa los videos
      this.alAnunciar = null;
      this.alTic = null;
      this._consultarPermiso();
    }

    async _consultarPermiso() {
      try {
        if (!navigator.permissions || !navigator.permissions.query) return;
        const p = await navigator.permissions.query({ name: 'microphone' });
        const poner = () => { this.permiso = p.state === 'granted' ? 'dado' : p.state === 'denied' ? 'negado' : 'sinPreguntar'; };
        poner();
        p.onchange = () => { poner(); this.m.avisar(); };
      } catch (_) { /* Safari viejo o Firefox: queda «sin preguntar» */ }
    }

    get mostrar() { return this.soporte && this.disponible; }
    get mandandoAlguno() { return this.locales.some(l => l.estado === 'mandando'); }
    get haySubidos() { return this.servidor.some(a => a.estado === 'subido') || this.locales.some(l => l.estado === 'subido'); }
    get transcriptos() {
      return new Set(this.servidor.filter(a => a.estado === 'transcripto' && a.texto).map(a => a.texto.trim()).filter(Boolean));
    }
    // Lo del servidor primero; lo local que todavía no está, después.
    get filas() {
      const out = this.servidor.map(a => ({ id: a.id, estado: a.estado === 'error' ? 'error' : 'subido' }));
      for (const l of this.locales) if (!out.some(o => o.id === l.id)) out.push({ id: l.id, estado: l.estado, aviso: l.aviso });
      return out;
    }

    anunciar(t) { if (this.alAnunciar) this.alAnunciar(t); }

    // Al abrir la guía: la lista y, si hay alguno en «subido», el sondeo.
    async abrirSeccion() {
      this.seccionAbierta = true;
      await this.cargarLista();
      this._sondear();
    }
    cerrarSeccion() {
      this.seccionAbierta = false;
      clearTimeout(this._sondeo); this._sondeo = null;
    }

    async cargarLista() {
      if (!this.soporte || !db()) return;
      const d = await db().getAudiosGuia(this.m.token);
      if (!Array.isArray(d)) return;       // sin la 019 el botón no aparece
      this.disponible = true;
      this.servidor = d.filter(esObjeto).map(a => ({
        id: texto(a.id) || '', estado: texto(a.estado), texto: texto(a.texto),
      })).filter(a => a.id && ['subido', 'transcripto', 'error'].includes(a.estado));
      this.locales = this.locales.filter(l => !(l.estado === 'subido' && this.servidor.some(s => s.id === l.id)));
      this.m.avisar();
    }

    _sondear() {
      if (!this.seccionAbierta || !this.haySubidos || this._sondeo) return;
      this._sondeoInicio = Date.now();
      const vuelta = async () => {
        this._sondeo = null;
        if (!this.seccionAbierta || Date.now() - this._sondeoInicio > SONDEO_MAX_MS) return;
        await this.cargarLista();
        // Mientras se esperaba la lista pudo arrancar otro sondeo: no se duplica.
        if (!this._sondeo && this.haySubidos && this.seccionAbierta) this._sondeo = setTimeout(vuelta, SONDEO_CADA_MS);
      };
      this._sondeo = setTimeout(vuelta, SONDEO_CADA_MS);
    }

    // ── El grabador (MaquinaAudio) ──
    async tocarGrabar() {
      if (this.fase !== 'reposo' && this.fase !== 'revisando') return;
      this._descartar();
      this.aviso = null;
      this.fase = 'pidiendo';
      this._cancelado = false;
      this.m.avisar();
      let stream;
      try {
        stream = await navigator.mediaDevices.getUserMedia({ audio: true });
      } catch (e) {
        const n = e && e.name;
        let a = 'ocupado';
        if (n === 'NotAllowedError' || n === 'SecurityError') { a = 'permisoNegado'; this.permiso = 'negado'; }
        else if (n === 'NotFoundError' || n === 'OverconstrainedError') a = 'sinMicrofono';
        this.fase = 'reposo';
        this.aviso = a;
        this.anunciar(TA.avisos[a]);
        this.m.avisar();
        return;
      }
      this.permiso = 'dado';
      // Se fue a segundo plano con el cartel del permiso: nada que revisar.
      if (this._cancelado || this.fase !== 'pidiendo') {
        stream.getTracks().forEach(t => t.stop());
        this.fase = 'reposo';
        this.m.avisar();
        return;
      }
      const elegido = elegirMime();
      let rec;
      try {
        rec = elegido ? new MediaRecorder(stream, { mimeType: elegido, audioBitsPerSecond: AUDIO_BITRATE })
                      : new MediaRecorder(stream);
      } catch (_) {
        try { rec = new MediaRecorder(stream); } catch (__) {
          stream.getTracks().forEach(t => t.stop());
          this.fase = 'reposo'; this.aviso = 'formato'; this.anunciar(TA.avisos.formato); this.m.avisar();
          return;
        }
      }
      if (this.alEmpezar) this.alEmpezar();
      this._stream = stream;
      this._rec = rec;
      this._chunks = [];
      this.mime = (rec.mimeType || elegido || 'audio/webm').split(';')[0];
      rec.ondataavailable = ev => { if (ev.data && ev.data.size) this._chunks.push(ev.data); };
      // Si el micrófono se corta (otra app, se desconectó) o el grabador falla, se cierra lo grabado.
      rec.onerror = () => { if (this.fase === 'grabando') this._parar(); };
      stream.getTracks().forEach(tr => { tr.onended = () => { if (this.fase === 'grabando' && this._rec === rec) this._parar(); }; });
      rec.onstop = () => {
        // Sin timeslice: el Blob se arma acá (con timeslice Safari armaba mp4 rotos).
        if (this.fase === 'revisando' && this._chunks.length) {
          this.blob = new Blob(this._chunks, { type: this.mime });
          this.url = URL.createObjectURL(this.blob);
          this.m.avisar();
        }
        this._chunks = [];
      };
      try { rec.start(); } catch (_) {
        stream.getTracks().forEach(t => t.stop());
        this._rec = null; this._stream = null;
        this.fase = 'reposo'; this.aviso = 'ocupado'; this.anunciar(TA.avisos.ocupado); this.m.avisar();
        return;
      }
      this._inicio = performance.now();
      this.segundos = 0;
      this.avisoDado = false;
      this.fase = 'grabando';
      this._tics = setInterval(() => this._tic(), 500);
      this.m.avisar();
    }

    _transcurrido() { return Math.min(AUDIO_TOPE, Math.max(0, (performance.now() - this._inicio) / 1000)); }

    _tic() {
      if (this.fase !== 'grabando') return;
      const s = (performance.now() - this._inicio) / 1000;
      this.segundos = Math.min(AUDIO_TOPE, s);
      if (s >= AUDIO_TOPE) { this._parar(); return; }
      if (s >= AUDIO_AVISO && !this.avisoDado) {
        this.avisoDado = true;
        this.aviso = 'quedan30';
        this.anunciar(TA.avisos.quedan30);
        this.m.avisar();
        return;
      }
      if (this.alTic) this.alTic(this.segundos);
    }

    terminar() { if (this.fase === 'grabando') this._parar(); }

    // Segundo plano, otro video que arranca o cerrar la guía: si graba, se
    // frena y pasa a revisar.
    cortar() {
      if (this.fase === 'grabando') this._parar();
      else if (this.fase === 'pidiendo') this._cancelado = true;
      if (this.escucha) this.escucha.pause();
    }

    _parar() {
      const s = this._transcurrido();
      clearInterval(this._tics); this._tics = null;
      if (s < AUDIO_MINIMO) {
        this.fase = 'reposo';
        this.aviso = 'muyCorto';
        this._chunks = [];
        this._soltarGrabador();
        this.anunciar(TA.avisos.muyCorto);
      } else {
        this.fase = 'revisando';
        this.segundos = s;
        if (this.aviso === 'quedan30') this.aviso = null;
        this._soltarGrabador();
        this.anunciar(TA.grabaste(s));
      }
      this.m.avisar();
    }

    _soltarGrabador() {
      try { if (this._rec && this._rec.state !== 'inactive') this._rec.stop(); } catch (_) { /* nada */ }
      if (this._stream) this._stream.getTracks().forEach(t => t.stop());
      this._rec = null; this._stream = null;
    }

    _descartar() {
      if (this.escucha) { this.escucha.pause(); this.escucha = null; }
      if (this.url) URL.revokeObjectURL(this.url);
      this.url = null; this.blob = null;
    }

    grabarDeNuevo() { if (this.fase === 'revisando') { this.fase = 'reposo'; this.tocarGrabar(); } }

    borrar() {
      if (this.fase !== 'revisando') return;
      this._descartar();
      this.fase = 'reposo'; this.aviso = null; this.segundos = 0;
      this.m.avisar();
    }

    alternarEscucha() {
      if (!this.url) return;
      if (!this.escucha) {
        this.escucha = new Audio(this.url);
        this.escucha.addEventListener('timeupdate', () => { if (this.alTic) this.alTic(null); });
        this.escucha.addEventListener('ended', () => this.m.avisar());
        this.escucha.addEventListener('pause', () => this.m.avisar());
        this.escucha.addEventListener('play', () => this.m.avisar());
      }
      if (this.escucha.paused) this.escucha.play().catch(() => {}); else this.escucha.pause();
    }

    mandar() {
      if (this.fase !== 'revisando' || !this.blob) return;
      const local = { id: uuid(), estado: 'mandando', aviso: null, blob: this.blob, mime: this.mime,
                      segundos: Math.round(this.segundos), intentada: false, nuevoId: false, esperas: 0 };
      if (this.escucha) { this.escucha.pause(); this.escucha = null; }
      if (this.url) URL.revokeObjectURL(this.url);
      this.url = null; this.blob = null;
      this.fase = 'reposo'; this.aviso = null; this.segundos = 0;
      this.locales.push(local);
      this.m.avisar();
      this._enviar(local);
    }

    reintentar(id) {
      const l = this.locales.find(x => x.id === id);
      if (!l || l.estado === 'mandando' || !l.blob) return;
      if (l.nuevoId) { l.id = uuid(); l.nuevoId = false; l.intentada = false; }
      l.estado = 'mandando'; l.aviso = null; l.esperas = 0;
      this.m.avisar();
      this._enviar(l);
    }

    // iniciar → subir → subido, con el mismo p_id en cada intento.
    async _enviar(l) {
      const d = db();
      const fallo = () => { l.estado = 'noSeMando'; this.m.avisar(); };
      if (!d) return fallo();
      for (let vuelta = 0; vuelta < 2; vuelta++) {
        const r = await d.iniciarAudioGuia(this.m.token, l.mime, l.blob.size, l.segundos, l.id);
        if (!r.success || !esObjeto(r.data)) return fallo();
        const t = r.data;
        if (t.ok !== true) {
          const motivo = texto(t.motivo);
          if (motivo === 'pendientes' && l.esperas < 12) {
            // Otros audios a medio mandar (hasta 3 a la vez): más tarde, solo.
            l.esperas++;
            setTimeout(() => this._enviar(l), SONDEO_CADA_MS);
            return;
          }
          if (motivo === 'id') { l.nuevoId = true; return fallo(); }
          if (motivo === 'token' || motivo == null) return fallo();
          l.estado = 'rechazado';
          l.aviso = avisoDeMotivo(motivo);
          this.m.avisar();
          return;
        }
        const bucket = texto(t.bucket), ruta = texto(t.ruta);
        if (!bucket || !ruta) return fallo();
        const quizasYaSubio = l.intentada;
        l.intentada = true;
        const up = await d.subirAudioGuia(bucket, ruta, l.blob, texto(t.mime) || l.mime);
        if (!up.ok && !(up.existe && quizasYaSubio)) return fallo();
        const s = await d.subidoAudioGuia(this.m.token, l.id);
        if (!s.success) {
          // El archivo subió: el worker lo ve igual (pack.html). Se muestra «Listo».
          if (s.transitorio) return this._listo(l);
          return fallo();
        }
        if (esObjeto(s.data) && s.data.ok === true) return this._listo(l);
        const m = esObjeto(s.data) ? texto(s.data.motivo) : null;
        if (m === 'sin_archivo' || m === 'vencido' || m === 'no_existe') { l.intentada = m !== 'sin_archivo'; continue; }
        if (m === 'token' || m == null) return fallo();
        l.estado = 'rechazado'; l.aviso = avisoDeMotivo(m);
        this.m.avisar();
        return;
      }
      fallo();
    }

    _listo(l) {
      l.estado = 'subido';
      l.blob = null;
      this.m.avisar();
      this.cargarLista().then(() => this._sondear());
    }
  }

  // ─── La agenda de la entrega (MyPumpDatos/Agenda.swift, 2.2.0) ──
  // · entregas_app_agenda al abrir la guía, al ver el último obligatorio y al
  //   volver a primer plano con la guía abierta o con una reserva pendiente.
  //   Nunca en segundo plano.
  // · entregas_app_reservar por su propia cola (el carril de la reserva, que
  //   no frena ni espera a los avances y las dudas), con un p_id fijo: sin red
  //   no se gasta el intento y un reintento devuelve la misma reserva.
  // Sin el servidor nuevo (PGRST202 u ok:false) no se muestra nada y no hay
  // errores: la guía queda como en la 2.1.0.
  class Agenda {
    constructor(modelo) {
      this.m = modelo;
      const a = almacen.leer(modelo.k('agenda'), null);
      // La copia guardada es la respuesta ya leída: se vuelve a leer igual (tolerante).
      this.agenda = esObjeto(a) && a.ok === true ? normalizarAgendaCopia(a) : null;
      this.desdeCache = false;
      this.aviso = null;           // tomada | vencida | error (lo último que dijo reservar)
      this.anuncio = '';
      this.anuncios = 0;
      const op = almacen.leer(modelo.k('reserva'), null);
      // Lo que quedó en la cola de otra apertura: «Estamos reservando…».
      this.op = esObjeto(op) && RG.esUuid(op.id) && typeof op.franja === 'string' && op.franja ? op : null;
      this.enCola = this.op ? { id: this.op.franja, inicio: this.op.inicio || '', fin: this.op.fin || '' } : null;
      this._consulta = null;
      this._sondeo = null; this._marcaSondeo = 0;
      this._enVuelo = false; this._reintento = null; this._espera = 0;
      this.vigilantes = new Set();   // la guía abierta y las tarjetas de Entreno a la vista
      this._reloj = null; this._tics = 0;
      if (this.op) setTimeout(() => this.procesar(), 0);
    }

    get disponible() { return !!(this.agenda && this.agenda.ok); }
    get textos() { return RA.textos(this.agenda ? this.agenda.textos : {}); }
    get avisoMin() { return this.agenda ? this.agenda.avisoMin : null; }
    get reserva() { return this.agenda ? this.agenda.reserva : null; }
    get pendiente() { return !!this.enCola || !!(this.reserva && this.reserva.estado === 'pendiente'); }
    // Videollamada 2.3.0: de comienzo o de revisión, desde cuántos minutos
    // antes se entra (el del servidor o los 10 de la app) y si se puede cambiar.
    get tipo() { return this.agenda ? this.agenda.tipo : 'comienzo'; }
    get entrarDesdeMin() { return this.agenda ? this.agenda.entrarDesdeMin : null; }
    get puedeCambiar() { return RA.puedeCambiar(this.agenda, new Date()); }
    // Un cambio saliendo es la confirmada de antes hasta que el servidor responda.
    get cambiando() { return !!(this.op && this.op.cambia); }
    vista(faltanLocal) { return RA.vista(this.agenda, faltanLocal, !!this.enCola && !this.cambiando, this.aviso); }

    _guardar() { if (this.agenda) almacen.guardar(this.m.k('agenda'), this.agenda); }

    // entregas_app_agenda. Si ya hay una en vuelo, se espera esa.
    consultar() {
      if (this._consulta) return this._consulta;
      this._consulta = this._traer().finally(() => { this._consulta = null; });
      return this._consulta;
    }

    async _traer() {
      const d = db();
      if (!d || typeof d.getAgendaGuia !== 'function') return;
      let r;
      try { r = await d.getAgendaGuia(this.m.token); } catch (_) { r = { success: false, transitorio: true }; }
      if (!r || !r.success) {
        // Sin red o el servidor ocupado: lo guardado, con «Sin conexión».
        if (r && r.transitorio) { this.desdeCache = !!this.agenda; this.m.avisar(); return; }
        // PGRST202 (sin la 021) o cualquier rechazo: no hay agenda, como en la 2.1.0. Sin mensajes.
        this._olvidar();
        return;
      }
      const a = normalizarAgenda(r.data);
      if (!a.ok) { this._olvidar(); return; }
      const antes = this.reserva ? this.reserva.estado : null;
      this.agenda = a;
      this.desdeCache = false;
      this._guardar();
      // Lo último que dijo reservar deja de valer cuando la reserva cambia de estado o ya no hay.
      if (a.reserva && (a.reserva.estado === 'fallo' || RA.vigente(a.reserva))) this.aviso = null;
      if (a.reserva && a.reserva.estado !== antes) this._anunciar(a.reserva);
      if (a.reserva && a.reserva.estado === 'pendiente') this.sondear();
      this._vigilar();
      this.m.avisar();
    }

    _olvidar() {
      const habia = !!this.agenda;
      this.agenda = null;
      this.desdeCache = false;
      almacen.borrar(this.m.k('agenda'));
      if (habia) this.m.avisar();
    }

    _anunciar(r) {
      const t = this.textos;
      if (r.estado === 'confirmada') this.anuncio = `Tu ${RA.nombre(r.tipo)} quedó agendada`;
      else if (r.estado === 'fallo') this.anuncio = t.fallo(r.motivo === 'tomada' ? 'tomada' : 'error');
      else this.anuncio = t.pendiente;
      this.anuncios++;
    }

    // Una reserva pendiente: cada 5 s durante 60 s (después, al volver a
    // primer plano). Uno solo a la vez.
    sondear() {
      if (this._sondeo || !this.pendiente) return;
      const inicio = Date.now();
      const marca = ++this._marcaSondeo;
      const vuelta = async () => {
        if (marca !== this._marcaSondeo) return;
        if (Date.now() - inicio > RA.SONDEO_MAXIMO_MS || document.visibilityState === 'hidden') { this._sondeo = null; return; }
        this._sondeo = 'consultando';   // ocupado: la consulta no puede abrir otro sondeo
        // Mientras la reserva sigue en la cola no hay nada que consultar: espera su respuesta.
        if (!this.enCola) await this.consultar();
        if (marca !== this._marcaSondeo) return;
        if (!this.pendiente) { this._sondeo = null; return; }
        this._sondeo = setTimeout(vuelta, RA.SONDEO_CADA_MS);
      };
      this._sondeo = setTimeout(vuelta, RA.SONDEO_CADA_MS);
    }

    // Segundo plano: nunca se consulta de fondo.
    pararSondeo() {
      if (typeof this._sondeo === 'number') clearTimeout(this._sondeo);
      this._sondeo = null;
      this._marcaSondeo++;
      this._pararReloj();
    }

    // De vuelta a primer plano con una reserva pendiente, o en la franja
    // esperando que Mati abra la sala (aunque la guía esté cerrada).
    async alVolver() {
      if (!this.pendiente && !RA.esperandoSala(this.reserva, new Date(), this.avisoMin)) { this._vigilar(); return; }
      await this.consultar();
      this.sondear();
      this._vigilar();
    }

    // ── El reloj de la confirmada (TimelineView cada 15 s y vigilarSala) ──
    // Con una confirmada que no terminó y alguien mirando (la guía abierta o
    // la tarjeta de Entreno): se repinta cada 15 s (el botón aparece a la hora)
    // y, en la franja sin la sala abierta, se consulta la agenda cada 30 s.
    vigilar(quien) { this.vigilantes.add(quien); this._vigilar(); }
    dejarDeVigilar(quien) { this.vigilantes.delete(quien); if (!this.vigilantes.size) this._pararReloj(); }

    _hayConfirmadaViva() {
      const ahora = Date.now();
      return [this.reserva, this.m.resumen && this.m.resumen.reserva].some(r => {
        const f = r && r.estado === 'confirmada' ? R.instante(r.fin) : null;
        return !!f && f.getTime() > ahora;
      });
    }

    // Cuánto falta para que la confirmada más cercana empiece (ms), o null.
    _faltaParaEntrega() {
      const ahora = Date.now();
      const ts = [this.reserva, this.m.resumen && this.m.resumen.reserva]
        .filter(r => r && r.estado === 'confirmada')
        .map(r => R.instante(r.inicio)).filter(Boolean).map(d => d.getTime() - ahora);
      return ts.length ? Math.min(...ts) : null;
    }

    _vigilar() {
      if (this._reloj || !this.vigilantes.size || document.visibilityState === 'hidden' || !this._hayConfirmadaViva()) return;
      // Lejos de la videollamada no cambia nada cada 15 s: se despierta una vez
      // antes de que empiece la cuenta regresiva (24 h antes de que se habilite
      // «Entrar») o a las 6 h. Con la cuenta a la vista, cada 15 s.
      const falta = this._faltaParaEntrega();
      const ventana = (Math.max(0, Number(this.avisoMin) || 0, (this.entrarDesdeMin || RA.ENTRAR_DESDE_MIN) + 24 * 60) + 60) * 60000;
      if (falta != null && falta > ventana + 3 * 3600000) {
        this._relojLejos = setTimeout(() => {
          this._relojLejos = null;
          this._reloj = null;
          this.m.avisar();
          this._vigilar();
        }, Math.min(falta - ventana - 3 * 3600000, 6 * 3600000));
        this._reloj = this._relojLejos;
        return;
      }
      this._tics = 0;
      this._reloj = setInterval(() => {
        if (!this.vigilantes.size || document.visibilityState === 'hidden' || !this._hayConfirmadaViva()) { this._pararReloj(); this.m.avisar(); return; }
        this._tics++;
        const pasos = Math.max(1, Math.round(RA.SALA_CADA_MS / 15000));
        if (this._tics % pasos === 0 && RA.esperandoSala(this.reserva, new Date(), this.avisoMin)) this.consultar();
        this.m.avisar();
      }, 15000);
    }

    _pararReloj() {
      clearInterval(this._reloj); this._reloj = null;
      if (this._relojLejos) { clearTimeout(this._relojLejos); this._relojLejos = null; }
    }

    // ── Reservar ──
    // La franja elegida en la hoja de confirmación. Por la cola, con un p_id
    // armado una sola vez: cada reintento manda el mismo. Si ya hay una
    // saliendo, no se encola otra.
    reservar(f) {
      if (this.enCola || this.op || RA.vigente(this.reserva) || !f) return;
      this._encolar(f, null);
    }

    // Cambiar la confirmada a otra franja (palanca `elegir_horario`): la misma
    // cola y el mismo carril que reservar, con el p_id fijo y la reserva que se
    // deja (entregas_app_cambiar). El servidor libera la vieja solo si toma la nueva.
    cambiar(f) {
      const r = this.reserva;
      if (!palancaElegirHorario() || this.enCola || this.op || !f || !r || r.estado !== 'confirmada' || !r.id || !this.puedeCambiar) return;
      this._encolar(f, r.id);
    }

    _encolar(f, cambia) {
      this.aviso = null;
      this.op = { id: uuid(), franja: f.id, inicio: f.inicio, fin: f.fin, intentos: 0 };
      if (cambia) this.op.cambia = cambia;
      this.enCola = { id: f.id, inicio: f.inicio, fin: f.fin };
      almacen.guardar(this.m.k('reserva'), this.op);
      this._espera = 0;
      this.m.avisar();
      this.procesar();
    }

    _soltarOp() { this.op = null; this.enCola = null; almacen.borrar(this.m.k('reserva')); }

    // entregas_app_reservar(p_token, p_franja, p_id). Red o transitorio: se
    // reintenta con el mismo p_id sin gastar intento. Sin la función
    // (PGRST202): se da por resuelta con «error» (la pantalla deja elegir otra).
    async procesar() {
      const op = this.op;
      const d = db();
      const fn = op && op.cambia ? 'cambiarEntregaGuia' : 'reservarEntregaGuia';
      if (!op || this._enVuelo) return;
      // Un cambio que quedó en la cola con la palanca apagada no sale: se resuelve como fuera de plazo.
      if (op.cambia && !palancaElegirHorario()) { this._alGuardar({ ok: false, motivo: 'plazo' }); return; }
      if (!d || typeof d[fn] !== 'function') return;
      if (navigator.onLine === false) { this._programar(); return; }
      clearTimeout(this._reintento); this._reintento = null;
      this._enVuelo = true;
      let r;
      try {
        r = op.cambia ? await d.cambiarEntregaGuia(this.m.token, op.cambia, op.franja, op.id)
                      : await d.reservarEntregaGuia(this.m.token, op.franja, op.id);
      } catch (_) { r = { success: false, transitorio: true }; }
      this._enVuelo = false;
      if (this.op !== op) return;
      let respuesta = null;
      if (!r || !r.success) {
        if (!r || r.transitorio) { this._programar(); return; }    // sin red: no se gasta el intento
        if (r.code === 'PGRST202') respuesta = { ok: false, motivo: 'error' };
      } else if (esObjeto(r.data) && texto(r.data.motivo) !== 'token') {
        respuesta = r.data;
      }
      if (!respuesta) {
        // Rechazado (token caído, una respuesta vacía, otro error permanente): cuenta como intento.
        op.intentos = (op.intentos || 0) + 1;
        if (op.intentos >= INTENTOS_MAX) { this._alAbandonar(); return; }
        almacen.guardar(this.m.k('reserva'), op);
        this._programar();
        return;
      }
      this._alGuardar(respuesta);
    }

    _programar() {
      if (this._reintento) return;
      this._espera = Math.min(60000, this._espera ? this._espera * 2 : 3000);
      this._reintento = setTimeout(() => { this._reintento = null; this.procesar(); }, this._espera);
    }

    // La respuesta de entregas_app_reservar.
    _alGuardar(r) {
      this._soltarOp();
      this._espera = 0;
      const reserva = normalizarReserva(r.reserva);
      const motivo = texto(r.motivo);
      if ((r.ok === true || motivo === 'ya_tiene') && reserva) {
        // Bien, o ya tenía una (la vigente): esa es la que se ve.
        if (this.agenda) { this.agenda.reserva = reserva; this.agenda.franjas = []; this._guardar(); }
        this._anunciar(reserva);
      } else if (r.ok === true) {
        this.aviso = null;   // salió sin la reserva en la respuesta: la trae la agenda
      } else {
        if (motivo === 'tomada') this.aviso = 'tomada';
        else if (motivo === 'franja') this.aviso = 'vencida';
        else if (motivo === 'obligatorios' || motivo === 'autorizada' || motivo === 'ya_tiene') this.aviso = null;   // la agenda de nuevo dice qué pasa
        else if (motivo === 'tope' || motivo === 'plazo') this.aviso = 'sinCambio';   // el cambio ya no se puede desde la app
        else this.aviso = 'error';
        if (this.aviso) { this.anuncio = RA.TEXTO_AVISO[this.aviso]; this.anuncios++; }
      }
      this.m.avisar();
      this.consultar().then(() => this.sondear());
    }

    // Abandonada (8 rechazos): se elige otra.
    _alAbandonar() {
      this._soltarOp();
      this.aviso = 'error';
      this.anuncio = this.textos.fallo('error'); this.anuncios++;
      this.m.avisar();
      this.consultar();
    }
  }
  // La copia guardada: los nombres ya leídos vuelven al formato del servidor.
  function normalizarAgendaCopia(a) {
    const r = a.reserva;
    return normalizarAgenda({
      ok: a.ok, motivo: a.motivo, autorizada: a.autorizada, habilitada: a.habilitada, faltan: a.faltan, zona: a.zona,
      franjas: a.franjas, aviso_min: a.avisoMin, textos: a.textos,
      tipo: a.tipo, entrar_desde_min: a.entrarDesdeMin, cambio: a.cambio,
      reserva: r ? { id: r.id, inicio: r.inicio, fin: r.fin, estado: r.estado, meet_url: r.meetUrl, motivo: r.motivo, sala_abierta_en: r.salaAbiertaEn,
                     tipo: r.tipo } : null,
    });
  }

  // ─── El modelo de un cliente (ModeloGuia) ───────────────────────
  class Modelo {
    constructor(token) {
      this.token = token;
      const h = hashToken(token);
      this.k = n => `mypump_guia_${n}_${h}`;
      const g = almacen.leer(this.k('guia'), null);
      this.guia = g && g.ok === true && Array.isArray(g.clips) ? g : null;
      const r = almacen.leer(this.k('resumen'), null);
      this.resumen = esObjeto(r) && typeof r.ok === 'boolean' ? r : null;
      this.estado = this.guia ? 'lista' : 'cargando';   // cargando | lista | oculta | sinRed
      this.desdeCache = false;
      // «Quitar de Entreno»: solo en este navegador, por cliente (guia_quitada.json).
      this.quitada = !!almacen.leer(this.k('quitada'), false);
      // 2.2.0: cuándo se ocultó (una novedad posterior la hace volver). Aparte de
      // la marca de la 2.1.0, que sigue igual. null = sin fecha.
      const qe = Number(almacen.leer(this.k('quitada_en'), NaN));
      this.quitadaEn = this.quitada && isFinite(qe) && qe > 0 ? new Date(qe) : null;
      this.bienvenidaVista = !!almacen.leer(this.k('bienvenida'), false);
      const tv = !!almacen.leer(this.k('tarjeta_vista'), false);
      this.primeraSesionTarjeta = !tv;
      this._tarjetaVista = tv;
      this.cola = lista(almacen.leer(this.k('cola'), [])).filter(op => esObjeto(op) && esObjeto(op.payload));
      this.cola.forEach(op => { op.enVuelo = false; });
      this.envios = {};          // por video (id) y '' para la videollamada
      this.borradores = {};
      this.confirmadas = [];
      this.cargas = 0;
      this.oyentes = new Set();
      this.audios = new Audios(this);
      this.agenda = new Agenda(this);
      this._procesando = false;
      this._reintento = null;
      this._espera = 0;
      if (this.guia) this.superponer();
    }

    avisar() {
      for (const f of Array.from(this.oyentes)) { try { f(); } catch (e) { console.warn('[guia]', e); } }
      for (const f of Array.from(oyentesGlobales)) { try { f(); } catch (e) { console.warn('[guia]', e); } }
    }

    // ── Tarjeta y fila (nunca llaman al get) ──
    // La marca de «Ocultar» que vale: sin novedad_en, la de la 2.1.0 tal cual;
    // con una novedad posterior, la tarjeta vuelve.
    get quitadaVigente() { return R.quitadaVigente(this.quitada, this.quitadaEn, this.novedadEn); }
    get mostrarTarjeta() { return R.tarjetaEnEntreno(this.resumen, this.quitadaVigente); }
    get mostrarFila() { return R.filaEnMisDatos(this.resumen, this.quitadaVigente); }
    get puedeQuitar() { return this.mostrarTarjeta; }
    get puedeVolverAMostrar() { return R.puedeVolverAMostrar(this.resumen, this.quitadaVigente); }
    get avanceTarjeta() {
      const r = this.resumen || {};
      return { total: r.total || 0, vistos: r.vistos || 0, minutosRestantes: r.minutosRestantes || 0 };
    }
    // Con novedad sin ver, también destacada (la compacta de «ya viste todo» va
    // solo si vio también lo nuevo).
    get tarjetaDestacada() { return this.mostrarTarjeta && (!!this.avanceNovedad || !R.completo(this.avanceTarjeta)); }
    get mostrarBienvenida() { return R.mostrarBienvenida(this.resumen, this.bienvenidaVista, this.quitadaVigente); }

    // ── Novedad (2.2.0) ──
    // La de la última tanda nueva: la del resumen (más nuevo) o la de la copia.
    get novedadEn() { return (this.resumen && this.resumen.novedadEn) || (this.guia && this.guia.novedadEn) || null; }
    // El avance de la tarjeta «NOVEDAD EN TU GUÍA» (solo los nuevos). null = la de la 2.1.0.
    get avanceNovedad() { return R.avanceNovedad(this.resumen, this.guia); }

    // ── Agenda (2.2.0) ──
    // Los obligatorios que faltan según el navegador (con lo de la cola encima):
    // el respaldo del `faltan` del servidor.
    get faltanLocal() { return this.guia ? RA.faltan(this.guia) : null; }
    get vistaAgenda() { return this.agenda.vista(this.faltanLocal); }
    // La reserva de la tarjeta fija de Entreno (videollamada 2.3.0): desde que
    // se agenda hasta que termina, la de la agenda (la más nueva) o, si la guía
    // no se abrió, la del resumen. Sin guía no queda nada.
    reservaTarjeta(ahora) {
      if ((this.resumen && this.resumen.ok === false) || this.estado === 'oculta') return null;
      const t = ahora || new Date();
      // La del resumen solo mientras la agenda no se trajo: con la agenda, manda la agenda (sin reserva o en fallo,
      // no hay tarjeta; si no, una cancelada seguiría con «Entrar»).
      const r = this.agenda.agenda ? this.agenda.reserva : this.resumen && this.resumen.reserva;
      return RA.paraTarjeta(r, t) ? r : null;
    }

    // Ocultar guarda también la fecha; volver a mostrar borra las dos.
    ponerQuitada(q) {
      this.quitada = !!q;
      this.quitadaEn = q ? new Date() : null;
      if (q) { almacen.guardar(this.k('quitada'), true); almacen.guardar(this.k('quitada_en'), this.quitadaEn.getTime()); }
      else { almacen.borrar(this.k('quitada')); almacen.borrar(this.k('quitada_en')); }
      this.avisar();
    }
    marcarBienvenidaVista() { this.bienvenidaVista = true; almacen.guardar(this.k('bienvenida'), true); }
    marcarTarjetaVista() {
      if (this._tarjetaVista) return;
      this._tarjetaVista = true;
      almacen.guardar(this.k('tarjeta_vista'), true);
    }

    aplicarResumen(r) { this.resumen = r; almacen.guardar(this.k('resumen'), r); }
    guardarGuia() { if (this.guia) almacen.guardar(this.k('guia'), this.guia); }
    guardarCola() {
      almacen.guardar(this.k('cola'), this.cola.map(op => ({ id: op.id, kind: op.kind, payload: op.payload, intentos: op.intentos || 0 })));
    }

    // entregas_app_resumen: solo lee. Sin red queda lo guardado.
    actualizarResumen() {
      if (this._resumenEnCurso) return this._resumenEnCurso;
      this._resumenEnCurso = (async () => {
        const d = db();
        if (!d) return;
        const j = await d.getGuiaResumen(this.token);
        // null = no respondió (red o servidor): queda lo guardado. La base
        // responde {ok:false} o false cuando no hay guía.
        if (j === null || j === undefined) return;
        const r = normalizarResumen(j);
        if (!r.ok) { this.ocultar(); return; }
        // Con avances todavía en la cola, el servidor cuenta menos de lo que el
        // cliente ya vio: la tarjeta no retrocede.
        const enCola = this.cola.some(op => op.kind === 'avance' && op.payload.visto === true);
        // Los conteos de `c` con la fecha, `mostrar_tarjeta` y lo de la 2.2.0 de `de`.
        const conFechas = (c, de) => {
          const x = Object.assign({}, c, { fechaEntrega: de.fechaEntrega, mostrarTarjetaServidor: de.mostrarTarjetaServidor,
                                          novedadEn: de.novedadEn, reserva: de.reserva });
          // El avance de lo nuevo es un conteo: con avances en la cola, nunca menos vistos.
          if (de.nuevosTotal != null && de.nuevosVistos != null) {
            x.nuevosTotal = de.nuevosTotal;
            x.nuevosVistos = c.nuevosTotal === de.nuevosTotal ? Math.max(de.nuevosVistos, c.nuevosVistos || 0) : de.nuevosVistos;
          } else { x.nuevosTotal = null; x.nuevosVistos = null; }
          return x;
        };
        if (enCola && this.guia) {
          this.resumen = conFechas(this.resumen && this.resumen.ok ? this.resumen : r, r);
          this.superponer();
        } else if (enCola && this.resumen && this.resumen.ok && this.resumen.total === r.total && this.resumen.vistos > r.vistos) {
          this.aplicarResumen(conFechas(this.resumen, r));
        } else {
          this.aplicarResumen(r);
        }
        this.avisar();
        if (this.cola.length) this.procesarCola();
        // Una reserva pendiente: al volver se consulta la agenda, aunque la guía esté cerrada.
        await this.agenda.alVolver();
      })().finally(() => { this._resumenEnCurso = null; });
      return this._resumenEnCurso;
    }

    // entregas_app_get: SOLO al abrir la guía.
    abrir() {
      if (this._carga) return this._carga;
      this._carga = this._traer().finally(() => { this._carga = null; });
      return this._carga;
    }

    async _traer() {
      const carga = ++this.cargas;
      const d = db();
      const j = d ? await d.getGuia(this.token) : null;
      if (j === null || j === undefined) {
        // Sin red o el servidor caído: lo guardado, si hay.
        if (this.guia) { this.desdeCache = true; this.estado = 'lista'; this.superponer(); } else this.estado = 'sinRed';
        this.avisar();
        return;
      }
      const g = normalizarGuia(j);
      if (!g.ok) { this.ocultar(); return; }
      // Lo confirmado después de que salió este get todavía no viene.
      for (const c of this.confirmadas) if (c.carga >= carga) asegurar(c, g);
      this.confirmadas = this.confirmadas.filter(c => c.carga >= carga);
      this.guia = g;
      this.desdeCache = false;
      this.guardarGuia();
      this.superponer();
      this.estado = 'lista';
      this.avisar();
      if (this.cola.length) this.procesarCola();
    }

    // ok:false (token revocado o sin página aprobada): la sección desaparece sin mensaje.
    ocultar() {
      this.guia = null;
      this.estado = 'oculta';
      this.desdeCache = false;
      this.aplicarResumen(normalizarResumen({ ok: false }));
      almacen.borrar(this.k('guia'));
      this.avisar();
    }

    // Lo pendiente gana sobre lo que trajo el servidor: el avance en la cola
    // marca visto y suma segundos.
    superponer() {
      for (const op of this.cola) {
        if (op.kind === 'avance') this._avanceLocal(op.payload.video, op.payload.segundos, op.payload.visto === true, false);
      }
      this.recalcularResumen();
    }

    recalcularResumen() {
      const g = this.guia;
      if (!g || !g.ok) return;
      // Como entregas_012: sin los videos de los suplementos.
      const a = R.avance(R.deLaLista(g));
      const base = this.resumen && this.resumen.ok ? this.resumen : null;
      // Lo de la 2.2.0 sigue al resumen; el avance de lo nuevo, a la guía si la guía sabe de esa tanda.
      const nuevos = R.deLaLista(g).filter(c => c.nuevo);
      const bNovedad = base ? base.novedadEn || null : null;
      const alDia = nuevos.length > 0 && (bNovedad == null || bNovedad === g.novedadEn);
      const conNuevos = alDia && base && base.nuevosTotal != null;
      this.aplicarResumen({
        ok: true, total: a.total, vistos: a.vistos, minutosRestantes: Math.round(a.minutosRestantes * 10) / 10,
        fechaEntrega: base ? base.fechaEntrega : g.fechaEntrega,
        mostrarTarjetaServidor: base ? base.mostrarTarjetaServidor : null,
        novedadEn: bNovedad || g.novedadEn || null,
        reserva: base ? base.reserva || null : null,
        nuevosTotal: conNuevos ? nuevos.length : (base ? base.nuevosTotal == null ? null : base.nuevosTotal : null),
        nuevosVistos: conNuevos ? nuevos.filter(c => c.visto).length : (base ? base.nuevosVistos == null ? null : base.nuevosVistos : null),
      });
    }

    clipVisto(id) { const c = this.guia && this.guia.clips.find(x => x.id === id); return !!(c && c.visto); }

    _avanceLocal(video, segundos, visto, guardar) {
      const g = this.guia;
      if (!g) return false;
      const c = g.clips.find(x => x.id === video);
      if (!c) return false;
      const s = Math.max(c.segundos, Number(segundos) || 0), v = c.visto || !!visto;
      if (s === c.segundos && v === c.visto) return false;
      const cambioVisto = v !== c.visto;
      c.segundos = s; c.visto = v;
      if (guardar) {
        this.guardarGuia();
        if (cambioVisto) this.recalcularResumen();
      }
      return true;
    }

    // El avance de un video por la cola. Una sola op por video (la que no
    // está en vuelo): el mayor de los segundos y visto si alguna lo tenía.
    avance(video, segundos, visto) {
      const s = Math.min(MAX_SEGUNDOS, Math.max(0, Math.round(segundos)));
      const v = !!visto || this.clipVisto(video);
      const faltabanAntes = this.faltanLocal || 0;
      const cambio = this._avanceLocal(video, s, v, true);
      // Vio el último obligatorio: la agenda de nuevo (y otra vez cuando el avance llegue al servidor).
      if (faltabanAntes > 0 && this.faltanLocal === 0 && this.agenda.disponible) this.agenda.consultar();
      const previa = this.cola.find(op => op.kind === 'avance' && op.payload.video === video && !op.enVuelo);
      if (previa) {
        previa.payload.segundos = Math.max(previa.payload.segundos || 0, s);
        previa.payload.visto = previa.payload.visto === true || v;
      } else {
        this.cola.push({ id: uuid(), kind: 'avance', payload: { video, segundos: s, visto: v }, intentos: 0 });
      }
      this.guardarCola();
      if (cambio) this.avisar();
      this.procesarCola();
    }

    // ── Dudas ──
    get pendientes() {
      return this.cola.filter(op => op.kind === 'duda' || op.kind === 'llamada').map(op => ({
        id: op.id, video: op.kind === 'duda' ? op.payload.video : null, texto: op.payload.texto, previas: op.payload.previas || 0,
      }));
    }
    vecesEnGuia(t, video) {
      const g = this.guia;
      if (!g) return 0;
      if (video != null) { const c = g.clips.find(x => x.id === video); return R.veces(t, c && c.duda); }
      return R.vecesLlamada(t, g.dudasLlamada);
    }
    // Las de la cola que el servidor todavía no trae.
    get pendientesSinLlegar() { return this.pendientes.filter(p => this.vecesEnGuia(p.texto, p.video) <= p.previas); }
    get dudasLlamadaContadas() {
      return ((this.guia && this.guia.dudasLlamada.length) || 0) + this.pendientesSinLlegar.filter(p => p.video == null).length;
    }
    get puedeSumarDudaLlamada() { return this.dudasLlamadaContadas < MAX_DUDAS_LLAMADA; }
    // Sin las que ya se ven como transcripción de un audio.
    get dudasLlamadaVisibles() {
      const tr = this.audios.transcriptos;
      const ds = ((this.guia && this.guia.dudasLlamada) || []).map(d => d.texto);
      return tr.size ? ds.filter(d => !tr.has(d.trim())) : ds;
    }
    previasDe(t, video) {
      return this.vecesEnGuia(t, video) + this.pendientes.filter(p => p.video === video && p.texto === t).length;
    }

    enviarDuda(video) {
      const t = R.textoParaMandar(this.borradores[video] || '');
      if (!t) return false;
      this.borradores[video] = '';
      this.envios[video] = 'enviando';
      const previas = this.previasDe(t, video);
      // p_id (entregas_013): un uuid al azar, armado una sola vez.
      const id = uuid();
      this.cola.push({ id, kind: 'duda', payload: { video, texto: t, previas, id }, intentos: 0 });
      this.guardarCola();
      this.avisar();
      this.procesarCola();
      return true;
    }

    enviarDudaLlamada() {
      if (!this.puedeSumarDudaLlamada) return false;
      const t = R.textoParaMandar(this.borradores[''] || '');
      if (!t) return false;
      this.borradores[''] = '';
      this.envios[''] = 'enviando';
      const previas = this.previasDe(t, null);
      const id = uuid();
      this.cola.push({ id, kind: 'llamada', payload: { texto: t, previas, id }, intentos: 0 });
      this.guardarCola();
      this.avisar();
      this.procesarCola();
      return true;
    }

    _devolver(t, clave) {
      const actual = this.borradores[clave] || '';
      this.borradores[clave] = actual ? t + '\n' + actual : t;
      this.envios[clave] = 'noSeGuardo';
    }

    // ── La cola ──
    async _ejecutar(op) {
      const d = db();
      if (!d) return { red: true };
      const p = op.payload;
      let r;
      if (op.kind === 'avance') r = await d.guardarAvanceGuia(this.token, p.video, p.segundos, p.visto === true);
      else if (op.kind === 'duda') r = await d.enviarDudaGuia(this.token, p.video, p.texto, p.id);
      else if (op.kind === 'llamada') r = await d.enviarDudaLlamadaGuia(this.token, p.texto, p.id);
      else return { hecho: false };
      if (!r || !r.success) return r && r.transitorio ? { red: true } : { hecho: false };
      // El avance: FALSE = token caído o sin guía, no hay nada que guardar.
      if (op.kind === 'avance') return { hecho: true, data: r.data };
      // Una duda sin respuesta (null) no se da por guardada.
      if (r.data === null || r.data === undefined) return { hecho: false };
      return { hecho: true, data: r.data };
    }

    async procesarCola() {
      if (this._procesando) { this._otraVez = true; return; }
      if (!db() || !this.cola.length) return;
      if (navigator.onLine === false) { this._programar(true); return; }
      this._procesando = true;
      this._otraVez = false;
      clearTimeout(this._reintento); this._reintento = null;
      let red = false, cambio = false;
      try {
        for (const op of this.cola.slice()) {
          if (!this.cola.includes(op)) continue;
          op.enVuelo = true;
          let r;
          try { r = await this._ejecutar(op); } catch (_) { r = { red: true }; } finally { op.enVuelo = false; }
          if (r.red) { red = true; break; }   // sin red: corta la pasada sin gastar intento
          if (r.hecho) {
            this.cola = this.cola.filter(x => x !== op);
            this._alGuardar(op, r.data);
            cambio = true;
          } else {
            op.intentos = (op.intentos || 0) + 1;
            if (op.intentos >= INTENTOS_MAX) {
              this.cola = this.cola.filter(x => x !== op);
              this._alAbandonar(op);
              cambio = true;
            }
          }
          this.guardarCola();
        }
      } finally {
        this._procesando = false;
      }
      if (cambio) this.avisar();
      // Entró algo mientras salía la pasada: otra pasada enseguida.
      if (this._otraVez && !red && this.cola.length) { this._otraVez = false; setTimeout(() => this.procesarCola(), 0); return; }
      if (this.cola.length) this._programar(red); else this._espera = 0;
    }

    _programar(red) {
      if (this._reintento) return;
      this._espera = Math.min(60000, this._espera ? this._espera * 2 : (red ? 5000 : 3000));
      this._reintento = setTimeout(() => { this._reintento = null; this.procesarCola(); }, this._espera);
    }

    _alGuardar(op, data) {
      // El último obligatorio llegó al servidor: ahora sí la agenda se habilita.
      if (op.kind === 'avance' && op.payload.visto === true && this.faltanLocal === 0 && this.agenda.disponible
          && (!this.agenda.agenda.habilitada || (this.agenda.agenda.faltan || 0) > 0)) this.agenda.consultar();
      if (op.kind !== 'duda' && op.kind !== 'llamada') return;
      const video = op.kind === 'duda' ? op.payload.video : null;
      const clave = video == null ? '' : video;
      if (data === false) { this._devolver(op.payload.texto, clave); return; }
      const c = { video, texto: op.payload.texto, esperadas: (op.payload.previas || 0) + 1, carga: this.cargas };
      this.confirmadas.push(c);
      if (this.guia && asegurar(c, this.guia)) this.guardarGuia();
      this.envios[clave] = 'listo';
    }

    _alAbandonar(op) {
      if (op.kind !== 'duda' && op.kind !== 'llamada') return;
      this._devolver(op.payload.texto, op.kind === 'duda' ? op.payload.video : '');
    }
  }

  // Que la duda confirmada se vea, sin repetirla si un get ya la trajo.
  function asegurar(c, g) {
    if (!c.texto) return false;
    let vueltas = 0, cambio = false;
    if (c.video != null) {
      const clip = g.clips.find(x => x.id === c.video);
      if (!clip) return false;
      while (R.veces(c.texto, clip.duda) < c.esperadas && vueltas < 5) {
        vueltas++;
        clip.duda = clip.duda ? clip.duda + '\n' + c.texto : c.texto;
        cambio = true;
      }
      return cambio;
    }
    while (R.vecesLlamada(c.texto, g.dudasLlamada) < c.esperadas && vueltas < 5) {
      vueltas++;
      g.dudasLlamada.push({ texto: c.texto, en: null });
      cambio = true;
    }
    return cambio;
  }

  const modelos = new Map();
  const oyentesGlobales = new Set();
  function modelo(token) {
    let m = modelos.get(token);
    if (!m) { m = new Modelo(token); modelos.set(token, m); }
    return m;
  }

  // Volvió la señal o la pestaña: se vacían las colas.
  window.addEventListener('online', () => {
    for (const m of modelos.values()) { m._espera = 0; m.procesarCola(); m.agenda._espera = 0; m.agenda.procesar(); }
  });
  document.addEventListener('visibilitychange', () => {
    // La reserva pendiente tampoco se consulta de fondo.
    if (document.visibilityState !== 'visible') { for (const m of modelos.values()) m.agenda.pararSondeo(); return; }
    for (const m of modelos.values()) {
      if (m.cola.length) m.procesarCola();
      if (m.agenda.op) m.agenda.procesar();
      // Al volver a primer plano, el resumen de nuevo (como la app), a lo sumo cada
      // 5 minutos; al terminar consulta la agenda (alVolver). Si no toca el
      // resumen, la agenda directo (pendiente o esperando la sala).
      if (!m._resumenAlVolver || Date.now() - m._resumenAlVolver > 300000) {
        m._resumenAlVolver = Date.now();
        Promise.resolve(m.actualizarResumen()).then(() => m.avisar()).catch(() => {});
      } else {
        m.agenda.alVolver().then(() => m.avisar()).catch(() => {});
      }
    }
  });

  // ─── Íconos ─────────────────────────────────────────────────────
  const svg = (d, extra) => `<svg viewBox="0 0 24 24" aria-hidden="true" focusable="false" ${extra || ''}>${d}</svg>`;
  const I = {
    play: svg('<path d="M8 5.5v13a1 1 0 0 0 1.5.86l10.2-6.5a1 1 0 0 0 0-1.72L9.5 4.64A1 1 0 0 0 8 5.5z" fill="currentColor"/>'),
    check: svg('<path d="M5 12.5l4.2 4.2L19 7" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round"/>'),
    chevron: svg('<path d="M6 9l6 6 6-6" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"/>'),
    cerrar: svg('<path d="M6 6l12 12M18 6L6 18" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round"/>'),
    reloj: svg('<circle cx="12" cy="12" r="8.5" fill="none" stroke="currentColor" stroke-width="2"/><path d="M12 7.5V12l3 2" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"/>'),
    parlante: svg('<path d="M4 9.5h3.5L12 6v12l-4.5-3.5H4z" fill="currentColor"/><path d="M15.5 9a4 4 0 0 1 0 6M18 6.5a7.5 7.5 0 0 1 0 11" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"/>'),
    stop: svg('<rect x="6.5" y="6.5" width="11" height="11" rx="2" fill="currentColor"/>'),
    pausa: svg('<rect x="6.5" y="5.5" width="4" height="13" rx="1.2" fill="currentColor"/><rect x="13.5" y="5.5" width="4" height="13" rx="1.2" fill="currentColor"/>'),
    mic: svg('<rect x="9" y="3.5" width="6" height="11" rx="3" fill="currentColor"/><path d="M5.5 11.5a6.5 6.5 0 0 0 13 0M12 18v2.5" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"/>'),
    ojo: svg('<path d="M2.5 12S6 5.5 12 5.5 21.5 12 21.5 12 18 18.5 12 18.5 2.5 12 2.5 12z" fill="none" stroke="currentColor" stroke-width="2"/><circle cx="12" cy="12" r="3" fill="currentColor"/>'),
    ojoTachado: svg('<path d="M2.5 12S6 5.5 12 5.5c1.6 0 3 .45 4.2 1.1M21.5 12S18 18.5 12 18.5c-1.6 0-3-.45-4.2-1.1" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"/><path d="M4 20L20 4" stroke="currentColor" stroke-width="2" stroke-linecap="round"/>'),
    sinRed: svg('<path d="M2.5 9a14 14 0 0 1 19 0M5.5 12.2a9.5 9.5 0 0 1 13 0M8.6 15.4a5 5 0 0 1 6.8 0" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"/><circle cx="12" cy="19" r="1.4" fill="currentColor"/><path d="M4 4l16 16" stroke="currentColor" stroke-width="2" stroke-linecap="round"/>'),
    lista: svg('<path d="M9 7h11M9 12h11M9 17h11" stroke="currentColor" stroke-width="2" stroke-linecap="round"/><circle cx="4.5" cy="7" r="1.3" fill="currentColor"/><circle cx="4.5" cy="12" r="1.3" fill="currentColor"/><circle cx="4.5" cy="17" r="1.3" fill="currentColor"/>'),
    alerta: svg('<circle cx="12" cy="12" r="9" fill="none" stroke="currentColor" stroke-width="2"/><path d="M12 7.5v5.5" stroke="currentColor" stroke-width="2.2" stroke-linecap="round"/><circle cx="12" cy="16.5" r="1.3" fill="currentColor"/>'),
    subiendo: svg('<circle cx="12" cy="12" r="9" fill="none" stroke="currentColor" stroke-width="2"/><path d="M12 16.5V8M8.5 11.5L12 8l3.5 3.5" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>'),
    listo: svg('<circle cx="12" cy="12" r="9" fill="none" stroke="currentColor" stroke-width="2"/><path d="M8 12.3l2.8 2.8L16.2 9.5" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"/>'),
    // 2.2.0: la novedad y la agenda
    destello: svg('<path d="M12 3l1.9 5.6L19.5 10.5l-5.6 1.9L12 18l-1.9-5.6L4.5 10.5l5.6-1.9z" fill="currentColor"/><path d="M18.5 15.5l.8 2.2 2.2.8-2.2.8-.8 2.2-.8-2.2-2.2-.8 2.2-.8z" fill="currentColor"/>'),
    calendario: svg('<rect x="3.5" y="5" width="17" height="15.5" rx="2.5" fill="none" stroke="currentColor" stroke-width="2"/><path d="M3.5 10h17M8 3v4M16 3v4" stroke="currentColor" stroke-width="2" stroke-linecap="round"/>'),
    candado: svg('<rect x="5" y="10.5" width="14" height="10" rx="2.2" fill="currentColor"/><path d="M8 10.5V8a4 4 0 0 1 8 0v2.5" fill="none" stroke="currentColor" stroke-width="2.2"/>'),
    playCirculo: svg('<circle cx="12" cy="12" r="9" fill="none" stroke="currentColor" stroke-width="2"/><path d="M10 8.5v7l5.6-3.5z" fill="currentColor"/>'),
    globo: svg('<circle cx="12" cy="12" r="8.5" fill="none" stroke="currentColor" stroke-width="2"/><path d="M3.5 12h17M12 3.5c2.5 2.6 3.6 5.4 3.6 8.5s-1.1 5.9-3.6 8.5c-2.5-2.6-3.6-5.4-3.6-8.5S9.5 6.1 12 3.5z" fill="none" stroke="currentColor" stroke-width="1.8"/>'),
    video: svg('<rect x="3" y="6.5" width="12.5" height="11" rx="2.2" fill="currentColor"/><path d="M15.5 10.5l5-3v9l-5-3z" fill="currentColor"/>'),
  };

  // ─── Estilos ────────────────────────────────────────────────────
  const ESTILOS = `
.gu-overlay,.gu-bienvenida{position:fixed;inset:0;z-index:9000;display:flex;flex-direction:column;background:var(--color-bg-secondary);color:var(--color-text-primary);font-family:var(--font-sans);-webkit-font-smoothing:antialiased}
.gu-overlay *,.gu-bienvenida *,.gu-tarjeta *,.gu-aviso-oculta *{box-sizing:border-box}
.gu-overlay [hidden],.gu-tarjeta[hidden]{display:none!important}
.gu-overlay button,.gu-bienvenida button,.gu-tarjeta button,.gu-aviso-oculta button{font-family:inherit;-webkit-tap-highlight-color:transparent}
.gu-barra{display:flex;align-items:center;justify-content:center;position:relative;min-height:52px;padding:calc(env(safe-area-inset-top,0px)) 56px 0;background:var(--color-bg-primary);border-bottom:1px solid var(--color-border);flex:0 0 auto}
.gu-barra-titulo{font-weight:600;font-size:17px}
.gu-cerrar{position:absolute;right:6px;bottom:4px;width:44px;height:44px;border:0;background:transparent;color:var(--color-text-secondary);border-radius:var(--radius-full);display:flex;align-items:center;justify-content:center;cursor:pointer}
.gu-cerrar svg{width:22px;height:22px}
.gu-cerrar:focus-visible,.gu-overlay button:focus-visible,.gu-overlay textarea:focus-visible,.gu-tarjeta button:focus-visible,.gu-bienvenida button:focus-visible{outline:2px solid var(--color-brand);outline-offset:2px}
.gu-banner{display:flex;gap:8px;align-items:center;justify-content:center;padding:8px 16px;font-size:13px;font-weight:600;color:var(--color-alerta);background:var(--color-bg-primary);border-bottom:1px solid var(--color-border)}
.gu-banner svg{width:16px;height:16px}
.gu-scroll{flex:1 1 auto;overflow-y:auto;-webkit-overflow-scrolling:touch;overscroll-behavior:contain}
.gu-contenido{max-width:640px;margin:0 auto;padding:16px 16px calc(32px + env(safe-area-inset-bottom,0px));display:flex;flex-direction:column;gap:16px}
.gu-card{background:var(--color-bg-primary);border-radius:var(--radius-lg);box-shadow:var(--shadow-sm);overflow:hidden}
.gu-pad{padding:20px}
.gu-sub{font-size:14px;color:var(--color-text-secondary);line-height:1.4}
.gu-nota{font-size:13px;color:var(--color-text-secondary);line-height:1.4;margin:0}
.gu-peligro{color:var(--color-danger)!important}
.gu-marca-t{color:var(--color-brand-text);font-weight:600}
.gu-cab{position:relative;padding:26px 20px 20px}
.gu-cab::before{content:"";position:absolute;top:0;left:0;right:0;height:6px;background:var(--color-brand)}
.gu-cab h2{margin:0 0 6px;font-family:var(--font-display);font-size:24px;font-weight:700;line-height:1.15}
.gu-cab p{margin:0 0 6px;font-size:16px;line-height:1.45}
.gu-firma{font-size:14px;color:var(--color-text-secondary)}
.gu-progreso{height:6px;border-radius:3px;background:var(--color-bg-tertiary);overflow:hidden;margin-top:6px}
.gu-progreso>span{display:block;height:100%;background:var(--color-brand);border-radius:3px;transition:width var(--transition-base)}
.gu-cuadro{position:relative;width:100%;aspect-ratio:16/9;max-height:calc((100vh - 52px) * .6);margin:0 auto;background:#000}
.gu-cuadro video{position:absolute;inset:0;width:100%;height:100%;background:transparent;object-fit:contain}
.gu-cuadro.gu-ajustado,.gu-vpq-cuadro.gu-ajustado{background:transparent}
.gu-capa{position:absolute;inset:0;display:flex}
.gu-capa:empty{pointer-events:none}
.gu-portada,.gu-placa,.gu-sinvideo{flex:1;border:0;margin:0;color:#fff;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:10px;padding:16px 20px;text-align:center;cursor:pointer}
.gu-portada{background:linear-gradient(180deg,#0a0a0a,#121c14)}
.gu-portada-titulo{font-family:var(--font-display);font-size:19px;font-weight:700;line-height:1.2;max-width:90%}
.gu-linea-verde{width:56px;height:3px;border-radius:2px;background:#5cba73}
.gu-portada-play{width:58px;height:58px;border-radius:50%;background:rgba(255,255,255,.16);display:flex;align-items:center;justify-content:center;margin-top:4px}
.gu-portada-play svg{width:26px;height:26px;margin-left:3px}
.gu-placa{background:#111814;align-items:flex-start;text-align:left;justify-content:center;padding:20px 24px}
.gu-placa-ceja{font-size:12px;font-weight:700;letter-spacing:.06em;text-transform:uppercase;color:#a8d9b5}
.gu-placa-bloque{font-size:14px;color:#dbdbdb}
.gu-placa-titulo{font-family:var(--font-display);font-size:20px;font-weight:700;line-height:1.2}
.gu-placa-barra{width:100%;height:3px;background:rgba(255,255,255,.14);border-radius:2px;overflow:hidden;margin-top:6px}
.gu-placa-barra>span{display:block;height:100%;width:0;background:#5cba73;border-radius:2px;animation:gu-llenar ${PLACA_MS}ms linear forwards}
@keyframes gu-llenar{to{width:100%}}
.gu-sinvideo{background:#111;cursor:default}
.gu-sinvideo svg{width:28px;height:28px;opacity:.8}
.gu-sinvideo span{font-size:15px;font-weight:600}
.gu-banda{background:var(--color-brand-subtle);padding:16px}
.gu-ceja{font-size:12px;font-weight:600;letter-spacing:.05em;text-transform:uppercase;color:var(--color-brand-text)}
.gu-banda h3{margin:4px 0 0;font-size:17px;font-weight:600;line-height:1.3}
.gu-botones{display:flex;flex-wrap:wrap;gap:8px;margin-top:12px}
.gu-boton-chico{min-height:44px;padding:0 16px;border:0;border-radius:var(--radius-full);background:var(--color-bg-primary);color:var(--color-brand-text);font-size:15px;font-weight:600;cursor:pointer}
.gu-boton-chico:active{opacity:.6}
.gu-actual{padding:16px;display:flex;flex-direction:column;gap:12px}
.gu-motivo{font-size:15px;line-height:1.45;color:var(--color-text-secondary);display:flex;flex-direction:column;gap:4px}
.gu-motivo p{margin:0}
.gu-motivo .gu-hacer{color:var(--color-text-primary)}
.gu-duda{display:flex;flex-direction:column;gap:8px}
.gu-duda-titulo{font-size:15px;font-weight:600}
.gu-ya{background:var(--color-bg-tertiary);border-radius:var(--radius-sm);padding:10px 12px;display:flex;flex-direction:column;gap:4px;font-size:15px}
.gu-ya-titulo{font-size:12px;font-weight:600;color:var(--color-text-secondary)}
.gu-ya p{margin:0;white-space:pre-wrap;overflow-wrap:anywhere}
.gu-encola{display:flex;gap:6px;align-items:flex-start;color:var(--color-text-secondary);font-size:15px}
.gu-encola svg{width:16px;height:16px;flex:0 0 16px;margin-top:2px}
.gu-encola span{white-space:pre-wrap;overflow-wrap:anywhere}
.gu-campo{display:flex;flex-direction:column;align-items:flex-end;gap:4px}
.gu-campo textarea{width:100%;min-height:56px;max-height:160px;resize:none;border:1.5px solid transparent;border-radius:var(--radius-md);background:var(--color-bg-tertiary);color:var(--color-text-primary);font:inherit;font-size:16px;line-height:1.4;padding:10px 12px;outline:none}
.gu-campo textarea:focus{border-color:var(--color-brand)}
.gu-campo textarea::placeholder{color:var(--color-text-muted)}
.gu-contador{font-size:12px;color:var(--color-text-secondary)}
.gu-envio{display:flex;align-items:center;gap:8px;justify-content:space-between}
.gu-envio-estado{font-size:13px;color:var(--color-text-secondary);line-height:1.35}
.gu-boton-marca{min-height:44px;padding:0 18px;border:0;border-radius:var(--radius-full);background:var(--color-brand);color:var(--color-on-brand);font-size:15px;font-weight:600;cursor:pointer;flex:0 0 auto}
.gu-boton-marca:disabled{opacity:.4;cursor:default}
.gu-boton-sec{min-height:44px;padding:0 16px;border:1px solid var(--color-brand-text);border-radius:var(--radius-full);background:transparent;color:var(--color-brand-text);font-size:15px;font-weight:600;cursor:pointer;display:inline-flex;align-items:center;gap:6px}
.gu-boton-sec svg{width:16px;height:16px}
.gu-boton-sec:disabled{opacity:.4;cursor:default}
.gu-boton-sec.gu-rojo{border-color:var(--color-danger);color:var(--color-danger)}
.gu-bloque-cab{width:100%;min-height:56px;border:0;background:transparent;color:inherit;display:flex;align-items:center;gap:12px;padding:12px 20px;text-align:left;cursor:pointer}
.gu-bloque-cab>span{flex:1;display:flex;flex-direction:column;gap:2px}
.gu-bloque-titulo{font-size:17px;font-weight:600}
.gu-chev{width:18px;height:18px;color:var(--color-text-secondary);transition:transform var(--transition-base);flex:0 0 18px}
[aria-expanded="true"]>.gu-chev{transform:rotate(180deg)}
.gu-filas{padding-bottom:6px}
.gu-fila.gu-fila-actual{background:var(--color-brand-subtle)}
.gu-fila-linea{display:flex;align-items:stretch}
.gu-fila-boton{flex:1;min-height:48px;border:0;background:transparent;color:var(--color-text-primary);display:flex;align-items:center;gap:12px;padding:10px 4px 10px 20px;text-align:left;font-size:16px;cursor:pointer;line-height:1.3}
.gu-fila-boton:disabled{opacity:.5;cursor:default}
.gu-fila-titulo{flex:1}
.gu-dur{font-size:14px;color:var(--color-text-secondary);font-variant-numeric:tabular-nums;flex:0 0 auto}
.gu-motivo-boton{width:48px;border:0;background:transparent;color:var(--color-text-secondary);display:flex;align-items:center;justify-content:center;cursor:pointer}
.gu-fila .gu-motivo{padding:0 20px 12px 54px;font-size:14px}
.gu-icono{width:22px;height:22px;flex:0 0 22px;border-radius:50%;border:2px solid var(--color-text-muted);display:flex;align-items:center;justify-content:center;color:var(--color-brand)}
.gu-icono svg{width:12px;height:12px}
.gu-icono.gu-visto{background:var(--color-brand);border-color:var(--color-brand);color:var(--color-on-brand)}
.gu-icono.gu-sonando,.gu-icono.gu-es-actual{border-color:var(--color-brand)}
.gu-dolor-zona{display:flex;flex-direction:column;gap:var(--space-3,12px)}
.gu-dolor-zona:empty{display:none}
.gu-dolor{border:1px solid var(--color-brand)}
.gu-dolor-texto{padding:20px;display:flex;flex-direction:column;gap:10px}
.gu-dolor-texto h3{margin:0;font-family:var(--font-display);font-size:20px;font-weight:700;line-height:1.2}
.gu-dolor-sub{font-size:15px;font-weight:600;color:var(--color-brand-text);margin-top:-6px}
.gu-dolor-texto p{margin:0;font-size:16px;line-height:1.45;white-space:pre-line}
.gu-dolor-videos{border-top:1px solid var(--color-border)}
.gu-pasos{display:flex;gap:8px;margin-top:10px}
.gu-paso{flex:1;min-height:44px;border:0;background:none;color:inherit;display:flex;flex-direction:column;align-items:center;gap:6px;cursor:pointer;padding:0}
.gu-paso-n{width:32px;height:32px;border-radius:50%;display:flex;align-items:center;justify-content:center;font-size:15px;font-weight:600;border:2px solid var(--color-border);color:var(--color-text-muted)}
.gu-paso-ahora .gu-paso-n{border-color:var(--color-brand);color:var(--color-brand-text)}
.gu-paso-hecho .gu-paso-n{border-color:var(--color-brand);background:var(--color-brand);color:var(--color-on-brand)}
.gu-paso-t{font-size:15px;font-weight:600;text-align:center}
.gu-llamada{position:relative;padding:20px 20px 20px 24px;display:flex;flex-direction:column;gap:10px}
.gu-llamada::before{content:"";position:absolute;left:0;top:0;bottom:0;width:4px;background:var(--color-brand)}
.gu-llamada h3{margin:0;font-family:var(--font-display);font-size:20px;font-weight:700;line-height:1.2}
.gu-recuadro{background:var(--color-brand-subtle);border-radius:var(--radius-sm);padding:10px 12px;font-size:15px;line-height:1.4;margin:0}
.gu-lista-dudas{display:flex;flex-direction:column}
.gu-lista-dudas>p{margin:0;padding:8px 0;border-top:1px solid var(--color-border);font-size:15px;white-space:pre-wrap;overflow-wrap:anywhere}
.gu-lista-dudas>.gu-encola{padding:8px 0;border-top:1px solid var(--color-border)}
.gu-audio{display:flex;flex-direction:column;gap:8px;padding-top:8px;border-top:1px solid var(--color-border);margin-top:4px}
.gu-grabando{display:flex;align-items:center;gap:12px}
.gu-terminar{min-height:44px;padding:0 18px;border:0;border-radius:var(--radius-full);background:var(--color-danger);color:#fff;font-size:15px;font-weight:600;display:inline-flex;align-items:center;gap:6px;cursor:pointer}
.gu-terminar svg{width:16px;height:16px}
.gu-punto{width:10px;height:10px;border-radius:50%;background:var(--color-danger);animation:gu-latir 1.4s ease-in-out infinite}
@keyframes gu-latir{0%,100%{opacity:1}50%{opacity:.25}}
.gu-cuenta{font-size:17px;font-weight:600;font-variant-numeric:tabular-nums}
.gu-revision{display:flex;align-items:center;gap:12px}
.gu-escuchar{width:44px;height:44px;border:0;border-radius:50%;background:var(--color-brand-subtle);color:var(--color-brand-text);display:flex;align-items:center;justify-content:center;cursor:pointer;flex:0 0 44px}
.gu-escuchar svg{width:18px;height:18px}
.gu-escuchar:disabled{opacity:.4}
.gu-barra-audio{flex:1;height:4px;border-radius:2px;background:var(--color-bg-tertiary);overflow:hidden}
.gu-barra-audio>span{display:block;height:100%;width:0;background:var(--color-brand)}
.gu-cuenta-chica{font-size:13px;color:var(--color-text-secondary);font-variant-numeric:tabular-nums}
.gu-fila-audio{display:flex;gap:8px;align-items:flex-start;font-size:15px;line-height:1.35;color:var(--color-text-secondary)}
.gu-fila-audio svg{width:18px;height:18px;flex:0 0 18px;margin-top:1px}
.gu-fila-audio .gu-ok{color:var(--color-brand)}
.gu-fila-audio>div{display:flex;flex-direction:column;gap:6px;align-items:flex-start}
.gu-supl h3{margin:0 0 4px;font-size:17px;font-weight:600}
.gu-momento{border-top:1px solid var(--color-border);padding-top:10px;margin-top:10px;display:flex;flex-direction:column;gap:8px}
.gu-momento-titulo{font-size:14px;font-weight:600;color:var(--color-brand-text)}
.gu-item{display:flex;flex-direction:column;gap:3px;padding:4px 0}
.gu-item-linea{display:flex;align-items:baseline;gap:8px}
.gu-item-nombre{flex:1;font-weight:600;font-size:16px}
.gu-etq{font-size:12px;font-weight:600;color:var(--color-brand-text);margin-left:6px}
.gu-etq.gu-gris{color:var(--color-text-secondary);font-weight:400}
.gu-cant{font-weight:600;font-variant-numeric:tabular-nums;text-align:right}
.gu-item p{margin:0;font-size:14px;line-height:1.4}
.gu-detalle{padding-left:10px;border-left:2px solid var(--color-border);color:var(--color-text-secondary)}
.gu-vpq{display:flex;flex-direction:column;gap:10px;margin-top:6px}
.gu-vpq-boton{align-self:flex-start;min-height:36px;padding:0 14px;border:1px solid var(--color-brand-text);border-radius:var(--radius-full);background:transparent;color:var(--color-brand-text);font-size:14px;font-weight:600;display:inline-flex;align-items:center;gap:6px;cursor:pointer;margin:4px 0}
.gu-vpq-boton svg{width:14px;height:14px}
.gu-vpq-boton .gu-visto-t{color:var(--color-brand)}
.gu-vpq-cuadro{position:relative;width:100%;aspect-ratio:16/9;max-height:calc((100vh - 52px) * .6);margin:0 auto;background:#000;border-radius:var(--radius-md);overflow:hidden}
.gu-vpq-cuadro video{position:absolute;inset:0;width:100%;height:100%;object-fit:contain;background:transparent}
.gu-vpq-cuadro .gu-sinvideo{position:absolute;inset:0}
.gu-pie{font-size:14px;color:var(--color-text-secondary);line-height:1.45;padding:16px 20px;margin:0}
.gu-accion{align-self:center;min-height:44px;padding:0 16px;border:0;background:transparent;color:var(--color-text-secondary);font-size:14px;display:inline-flex;align-items:center;gap:6px;cursor:pointer}
.gu-accion svg{width:16px;height:16px}
.gu-estado{min-height:50vh;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:10px;text-align:center;padding:24px}
.gu-estado svg{width:36px;height:36px;color:var(--color-text-secondary)}
.gu-estado h3{margin:0;font-size:18px}
.gu-girando{width:32px;height:32px;border-radius:50%;border:3px solid var(--color-bg-tertiary);border-top-color:var(--color-brand);animation:gu-girar .9s linear infinite}
@keyframes gu-girar{to{transform:rotate(360deg)}}
.gu-oculto{position:absolute!important;width:1px;height:1px;overflow:hidden;clip:rect(0 0 0 0);white-space:nowrap}
/* La tarjeta de Entreno */
.gu-tarjeta{font-family:var(--font-sans);color:var(--color-text-primary)}
.gu-destacada{background:#17852b;color:#fff;border-radius:var(--radius-lg);padding:16px;display:flex;flex-direction:column;gap:12px;box-shadow:0 8px 16px rgba(23,133,43,.28)}
[data-theme="dark"] .gu-destacada{background:#157a28;box-shadow:0 8px 16px rgba(21,122,40,.28)}
.gu-dest-cab{display:flex;align-items:center;justify-content:space-between;gap:8px;margin:-8px -8px 0 0}
.gu-dest-ceja{font-size:12px;font-weight:800;letter-spacing:.08em;text-transform:uppercase}
.gu-ocultar{min-width:44px;min-height:44px;padding:0 8px;border:0;background:transparent;color:#fff;font-size:15px;font-weight:600;cursor:pointer}
.gu-dest-fila{display:flex;align-items:center;gap:12px}
.gu-dest-titulo{font-family:var(--font-display);font-size:26px;font-weight:700;line-height:1.1}
.gu-dest-sub{font-size:15px;font-weight:500}
.gu-icono-play{position:relative;width:52px;height:52px;flex:0 0 52px;border-radius:50%;background:rgba(255,255,255,.2);display:flex;align-items:center;justify-content:center;color:#fff}
.gu-icono-play svg{width:20px;height:20px;margin-left:2px;position:relative}
.gu-icono-play.gu-pulso::before{content:"";position:absolute;inset:0;border-radius:50%;border:2px solid currentColor;animation:gu-halo 1.8s ease-out .4s 4 both}
@keyframes gu-halo{from{transform:scale(1);opacity:.7}to{transform:scale(1.5);opacity:0}}
.gu-barra-blanca{height:6px;border-radius:3px;background:rgba(255,255,255,.28);overflow:hidden}
.gu-barra-blanca>span{display:block;height:100%;background:#fff;border-radius:3px}
.gu-boton-blanco{min-height:50px;width:100%;border:0;border-radius:var(--radius-full);background:#fff;color:#157a28;font-size:17px;font-weight:600;display:flex;align-items:center;justify-content:center;gap:8px;cursor:pointer}
.gu-boton-blanco svg{width:16px;height:16px}
.gu-boton-blanco:active{transform:scale(.97);opacity:.9}
.gu-compacta{width:100%;border:0;background:var(--color-bg-primary);border-radius:var(--radius-lg);box-shadow:var(--shadow-sm);padding:14px 16px;display:flex;align-items:center;gap:12px;text-align:left;cursor:pointer}
.gu-anillo{position:relative;width:44px;height:44px;flex:0 0 44px;color:var(--color-brand)}
.gu-anillo>svg{width:44px;height:44px;transform:rotate(-90deg)}
.gu-anillo>span{position:absolute;inset:0;display:flex;align-items:center;justify-content:center}
.gu-anillo>span svg{width:18px;height:18px}
.gu-compacta-texto{flex:1;display:flex;flex-direction:column;gap:2px}
.gu-compacta-texto b{font-size:17px;font-weight:600}
.gu-aviso-oculta{position:fixed;left:16px;right:16px;bottom:calc(16px + env(safe-area-inset-bottom,0px));z-index:9100;max-width:480px;margin:0 auto;display:flex;align-items:center;gap:12px;padding:2px 8px 2px 16px;border-radius:30px;background:var(--color-bg-primary);color:var(--color-text-primary);box-shadow:var(--shadow-lg);font-family:var(--font-sans);border:1px solid var(--color-border)}
.gu-aviso-oculta>span{flex:1;display:flex;align-items:center;gap:8px;font-size:15px;font-weight:600}
.gu-aviso-oculta svg{width:18px;height:18px}
.gu-aviso-oculta button{min-width:44px;min-height:44px;padding:0 8px;border:0;background:transparent;color:var(--color-brand-text);font-size:15px;font-weight:700;cursor:pointer}
/* La bienvenida */
.gu-bienvenida{background:var(--color-bg-secondary);overflow-y:auto}
.gu-bv-cuerpo{flex:1;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:24px;padding:calc(32px + env(safe-area-inset-top,0px)) 24px 16px;text-align:center;max-width:520px;margin:0 auto;width:100%}
.gu-bv-halo{width:146px;height:146px;border-radius:50%;background:var(--color-brand-subtle);display:flex;align-items:center;justify-content:center}
.gu-bv-halo .gu-icono-play{width:104px;height:104px;flex-basis:104px;background:var(--color-brand);color:var(--color-on-brand);box-shadow:0 8px 18px rgba(29,147,48,.35)}
.gu-bv-halo .gu-icono-play svg{width:40px;height:40px;margin-left:4px}
.gu-bv-cuerpo h2{margin:0;font-family:var(--font-display);font-size:34px;font-weight:700;line-height:1.1}
.gu-bv-cuerpo p{margin:0;font-size:20px;line-height:1.4;color:var(--color-text-secondary)}
.gu-bv-botones{display:flex;flex-direction:column;gap:4px;padding:8px 24px calc(12px + env(safe-area-inset-bottom,0px));max-width:520px;margin:0 auto;width:100%}
.gu-bv-botones .gu-boton-marca{min-height:52px;width:100%;font-size:17px;display:flex;align-items:center;justify-content:center;gap:8px}
.gu-bv-botones .gu-boton-marca svg{width:16px;height:16px}
.gu-mas-tarde{min-height:48px;border:0;background:transparent;color:var(--color-brand-text);font-size:17px;font-weight:600;cursor:pointer}
/* 2.2.0: la novedad, los obligatorios y la agenda de la entrega */
.gu-novedad{display:inline-flex;align-items:center;gap:6px;color:var(--color-brand-text)}
.gu-novedad svg{width:18px;height:18px;flex:0 0 18px}
.gu-etq-oblig{display:flex;align-items:center;gap:4px;margin-top:2px;font-size:12px;font-weight:400;color:var(--color-text-secondary)}
.gu-etq-oblig svg{width:12px;height:12px;flex:0 0 12px}
.gu-agenda{display:flex;flex-direction:column;gap:8px}
.gu-agenda-contador{min-height:44px;border:0;background:transparent;color:var(--color-brand-text);font-size:15px;font-weight:600;display:flex;align-items:center;gap:8px;text-align:left;padding:0 4px;cursor:pointer}
.gu-agenda-contador svg{width:20px;height:20px;flex:0 0 20px}
.gu-agenda-caja{padding:20px;display:flex;flex-direction:column;gap:10px}
.gu-agenda-caja.gu-gris{background:var(--color-bg-tertiary);box-shadow:none}
.gu-agenda-caja.gu-verde{background:var(--color-brand-subtle)}
.gu-agenda-cab{margin:0;display:flex;align-items:center;gap:8px;font-size:17px;font-weight:600}
.gu-agenda-cab svg{width:20px;height:20px;flex:0 0 20px}
.gu-apagado{color:var(--color-text-secondary)}
.gu-agenda-cab.gu-apagado span{color:var(--color-text-primary)}
.gu-agenda-texto{margin:0;font-size:16px;line-height:1.45;display:flex;align-items:center;gap:8px}
.gu-agenda-sinred,.gu-agenda-zona{display:flex;align-items:center;gap:6px;margin:0;font-size:13px;font-weight:600;color:var(--color-text-secondary)}
.gu-agenda-zona{font-weight:400}
.gu-agenda-sinred svg,.gu-agenda-zona svg{width:15px;height:15px;flex:0 0 15px}
.gu-agenda-aviso{display:flex;align-items:flex-start;gap:6px;margin:0;font-size:15px;font-weight:600;color:var(--color-alerta)}
.gu-agenda-aviso svg{width:17px;height:17px;flex:0 0 17px;margin-top:1px}
.gu-agenda-dia{display:flex;flex-direction:column;gap:8px;padding-top:4px}
.gu-agenda-dia-titulo{font-size:15px;font-weight:600}
.gu-chips{display:flex;flex-wrap:wrap;gap:8px}
.gu-chip{min-height:44px;padding:0 16px;border:1px solid color-mix(in srgb,var(--color-brand) 35%,transparent);border-radius:var(--radius-full);background:var(--color-brand-subtle);color:var(--color-brand-text);font-size:15px;font-weight:600;font-variant-numeric:tabular-nums;cursor:pointer;transition:transform .18s}
.gu-chip:active{transform:scale(.96)}
.gu-agenda-confirmada{margin:0;font-size:20px;font-weight:600;line-height:1.3}
.gu-agenda-sala{margin:0;font-size:17px;font-weight:600;color:var(--color-brand-text)}
.gu-boton-ancho{width:100%;display:flex;align-items:center;justify-content:center;gap:8px;text-decoration:none}
.gu-boton-ancho svg,.gu-boton-sec svg{width:16px;height:16px}
.gu-girando.gu-chico{width:16px;height:16px;border-width:2px;flex:0 0 16px}
.gu-hoja-fondo{position:fixed;inset:0;z-index:9200;background:rgba(0,0,0,.45)}
.gu-hoja{position:fixed;left:0;right:0;bottom:0;z-index:9201;max-width:520px;margin:0 auto;max-height:90vh;overflow-y:auto;background:var(--color-bg-primary);color:var(--color-text-primary);border-radius:20px 20px 0 0;box-shadow:var(--shadow-lg);padding:24px 24px calc(24px + env(safe-area-inset-bottom,0px));display:flex;flex-direction:column;align-items:center;gap:12px;text-align:center}
.gu-hoja-icono{color:var(--color-brand)}
.gu-hoja-icono svg{width:44px;height:44px}
.gu-hoja p{margin:0 0 8px;font-size:20px;font-weight:600;line-height:1.35}
.gu-hoja .gu-boton-sec{justify-content:center}
/* La videollamada (2.3.0): la tarjeta fija arriba de Entreno (y al final de la
   guía) y la pantalla para elegir o cambiar el horario. En rem: crece con el
   texto grande del navegador. */
.vl-tarjeta,.vl-pantalla{font-family:var(--font-sans);color:var(--color-text-primary);line-height:1.35}
.vl-tarjeta *,.vl-pantalla *{box-sizing:border-box}
.vl-tarjeta button,.vl-pantalla button{font-family:inherit;-webkit-tap-highlight-color:transparent}
.vl-tarjeta :focus-visible,.vl-pantalla :focus-visible{outline:2px solid var(--color-brand);outline-offset:2px}
.vl-tarjeta{display:flex;flex-direction:column;gap:.875rem;padding:1.25rem;margin:0 0 .75rem;border-radius:var(--radius-lg);background:var(--color-bg-primary);border:1.5px solid color-mix(in srgb,var(--color-brand) 45%,transparent);box-shadow:var(--shadow-sm);overflow-wrap:break-word}
.vl-tarjeta.vl-activa{background:#17852b;border-color:transparent;color:#fff;box-shadow:0 .5rem 1rem rgba(23,133,43,.35)}
[data-theme="dark"] .vl-tarjeta.vl-activa{background:#157a28;box-shadow:0 .5rem 1rem rgba(21,122,40,.35)}
.vl-tarjeta p{margin:0}
/* base.css pinta los <p> de gris: lo principal va con el color de la tarjeta (blanco en la verde). */
.vl-dia,.vl-hora,.vl-ya,.vl-admite,.vl-linea,.vl-reservando,.vl-hora-grande,.vl-p-contenido>p:not([class]){color:inherit}
.vl-sinred{display:flex;align-items:center;gap:.375rem;font-size:.8125rem;font-weight:600;color:var(--color-text-secondary)}
.vl-activa .vl-sinred{color:rgba(255,255,255,.85)}
.vl-sinred svg{width:.9375rem;height:.9375rem;flex:0 0 auto}
.vl-cab{display:flex;flex-wrap:wrap;align-items:center;gap:.5rem}
.vl-icono{width:1.875rem;height:1.875rem;flex:0 0 auto;border-radius:50%;background:var(--color-brand);color:var(--color-on-brand);display:inline-flex;align-items:center;justify-content:center}
.vl-icono svg{width:.875rem;height:.875rem}
.vl-activa .vl-icono{background:#fff;color:#157a28}
.vl-titulo{margin:0;flex:1 1 9rem;min-width:0;font-size:.9375rem;font-weight:700;color:var(--color-brand-text)}
.vl-activa .vl-titulo{color:#fff}
.vl-agendar .vl-titulo{font-size:1.0625rem;color:var(--color-text-primary)}
.vl-cuando{flex:0 0 auto;padding:.3125rem .625rem;border-radius:var(--radius-full);background:var(--color-brand-subtle);color:var(--color-brand-text);font-size:.75rem;font-weight:700}
.vl-activa .vl-cuando{background:#fff;color:#157a28}
.vl-fecha{display:flex;flex-direction:column;gap:.125rem}
.vl-dia{font-size:1.25rem;font-weight:600}
.vl-hora{display:flex;align-items:baseline;flex-wrap:wrap;gap:.375rem}
.vl-hora-grande{font-family:var(--font-display);font-size:2.75rem;font-weight:800;line-height:1.05;font-variant-numeric:tabular-nums}
.vl-hasta{font-size:1.25rem;font-weight:500;color:var(--color-text-secondary);font-variant-numeric:tabular-nums}
.vl-ar,.vl-zona{display:flex;align-items:center;gap:.375rem;font-size:.8125rem;color:var(--color-text-secondary)}
.vl-ar svg,.vl-zona svg{width:.9375rem;height:.9375rem;flex:0 0 auto}
.vl-activa .vl-hasta,.vl-activa .vl-ar{color:rgba(255,255,255,.85)}
.vl-reservando{display:flex;align-items:center;gap:.5rem;font-size:1rem}
.vl-entrar-zona{display:flex;flex-direction:column;gap:.5rem}
.vl-ya{font-size:1.0625rem;font-weight:600}
.vl-boton{min-height:3.25rem;width:100%;padding:.5rem 1.125rem;border:0;border-radius:var(--radius-full);background:var(--color-brand);color:var(--color-on-brand);font-size:1.0625rem;font-weight:600;display:flex;align-items:center;justify-content:center;gap:.5rem;cursor:pointer;text-align:center;text-decoration:none}
.vl-boton svg{width:1rem;height:1rem;flex:0 0 auto}
.vl-boton:disabled{opacity:.4;cursor:default}
.vl-entrar{min-height:3.5rem;background:#fff;color:#157a28}
[data-theme="dark"] .vl-entrar{background:#f7f7f7}
.vl-entrar:active,.vl-boton:not(:disabled):active{transform:scale(.97)}
.vl-cuenta{font-size:.9375rem;font-weight:600;color:var(--color-text-secondary);text-align:center;font-variant-numeric:tabular-nums}
.vl-linea{display:flex;align-items:flex-start;gap:.5rem;font-size:.9375rem;font-weight:500}
.vl-linea svg{width:1.0625rem;height:1.0625rem;flex:0 0 auto;margin-top:.0625rem;color:var(--color-brand-text)}
.vl-admite{font-size:.9375rem}
.vl-ayuda summary{list-style:none;min-height:2.75rem;display:flex;align-items:center;gap:.5rem;cursor:pointer;font-size:.9375rem;font-weight:600;color:var(--color-brand-text)}
.vl-ayuda summary::-webkit-details-marker{display:none}
.vl-ayuda summary>svg{width:1.0625rem;height:1.0625rem;flex:0 0 auto}
.vl-ayuda summary .vl-chev{margin-left:auto;width:.875rem;height:.875rem;transition:transform .2s}
.vl-ayuda[open] summary .vl-chev{transform:rotate(180deg)}
.vl-activa .vl-ayuda summary{color:#fff}
.vl-ayuda ol{list-style:none;margin:.25rem 0 0;padding:0;display:flex;flex-direction:column;gap:.5rem}
.vl-ayuda li{display:flex;align-items:baseline;gap:.5rem;font-size:.9375rem}
.vl-ayuda li>span:first-child{flex:0 0 auto;width:1.375rem;height:1.375rem;border-radius:50%;background:var(--color-brand-subtle);font-size:.75rem;font-weight:700;display:inline-flex;align-items:center;justify-content:center}
.vl-activa .vl-ayuda li>span:first-child{background:rgba(255,255,255,.2)}
.vl-acciones{display:flex;flex-wrap:wrap;gap:.5rem}
.vl-sec{min-height:2.75rem;padding:.375rem 1rem;border:1px solid var(--color-brand-text);border-radius:var(--radius-full);background:transparent;color:var(--color-brand-text);font-size:.9375rem;font-weight:600;display:inline-flex;align-items:center;justify-content:center;gap:.375rem;cursor:pointer;text-align:center}
.vl-sec svg{width:1rem;height:1rem;flex:0 0 auto}
.vl-nota{font-size:.8125rem;color:var(--color-text-secondary)}
.vl-sub{font-size:.9375rem;color:var(--color-text-secondary)}
.vl-aviso{display:flex;align-items:flex-start;gap:.375rem;font-size:.9375rem;font-weight:600;color:var(--color-alerta)}
.vl-aviso svg{width:1.0625rem;height:1.0625rem;flex:0 0 auto;margin-top:.0625rem}
.vl-pantalla{position:fixed;inset:0;z-index:9400;display:flex;flex-direction:column;background:var(--color-bg-secondary)}
.vl-p-barra{flex:0 0 auto;display:grid;grid-template-columns:1fr auto 1fr;align-items:center;min-height:3.25rem;padding:0 .5rem;padding-top:env(safe-area-inset-top);background:var(--color-bg-primary);border-bottom:1px solid var(--color-border)}
.vl-p-nav{font-size:1.0625rem;font-weight:600;text-align:center}
.vl-p-cerrar{justify-self:start;min-height:2.75rem;padding:0 .5rem;border:0;background:transparent;color:var(--color-brand-text);font-size:1.0625rem;cursor:pointer}
.vl-p-cuerpo{flex:1;overflow-y:auto;-webkit-overflow-scrolling:touch}
.vl-p-contenido{max-width:40rem;margin:0 auto;padding:1rem 1rem 1.5rem;display:flex;flex-direction:column;gap:1.25rem}
.vl-p-contenido p{margin:0}
.vl-p-titulo{margin:0;font-family:var(--font-display);font-size:1.75rem;font-weight:800;line-height:1.15;outline:none}
.vl-p-cab{display:flex;flex-direction:column;gap:.5rem}
.vl-p-ahora{padding:1rem;border-radius:var(--radius-md);background:var(--color-brand-subtle);display:flex;flex-direction:column;gap:.25rem}
.vl-p-ahora b{font-size:.9375rem}
.vl-p-dia{padding:1rem;border-radius:1rem;background:var(--color-bg-primary);box-shadow:var(--shadow-sm);display:flex;flex-direction:column;gap:.75rem}
.vl-p-dia h3{margin:0;font-size:1.0625rem;font-weight:600}
.vl-p-horas{display:grid;grid-template-columns:repeat(auto-fit,minmax(min(100%,8.5rem),1fr));gap:.5rem}
.vl-p-hora{position:relative;min-height:4.5rem;padding:.5rem;border:0;border-radius:var(--radius-md);background:var(--color-bg-tertiary);color:var(--color-text-primary);display:flex;flex-direction:column;align-items:center;justify-content:center;gap:.125rem;cursor:pointer}
.vl-p-hora b{font-family:var(--font-display);font-size:1.5rem;font-weight:800;font-variant-numeric:tabular-nums}
.vl-p-hora span{font-size:.75rem;color:var(--color-text-secondary);font-variant-numeric:tabular-nums}
.vl-p-hora[aria-pressed="true"]{background:var(--color-brand);color:var(--color-on-brand)}
.vl-p-hora[aria-pressed="true"] span{color:inherit;opacity:.85}
.vl-p-hora .vl-p-tilde{position:absolute;top:.5rem;right:.5rem;width:1.125rem;height:1.125rem}
.vl-p-pie{flex:0 0 auto;padding:.75rem 1rem;padding-bottom:max(.75rem,env(safe-area-inset-bottom));background:var(--color-bg-primary);border-top:1px solid var(--color-border)}
.vl-p-pie>*{max-width:40rem;margin:0 auto}
.vl-p-enviando{min-height:3.25rem;display:flex;align-items:center;justify-content:center;gap:.75rem;font-size:.9375rem;font-weight:600}
.vl-p-listo{align-items:center;text-align:center}
.vl-p-ok{margin-top:1.5rem;width:5.25rem;height:5.25rem;border-radius:50%;background:var(--color-brand);color:var(--color-on-brand);display:flex;align-items:center;justify-content:center}
.vl-p-ok svg{width:2.25rem;height:2.25rem}
.vl-p-resumen{width:100%;padding:1.5rem;border-radius:var(--radius-lg);background:var(--color-bg-primary);box-shadow:var(--shadow-sm);display:flex;flex-direction:column;align-items:center;gap:.25rem}
.vl-p-resumen .vl-titulo{flex:none}
.vl-p-lineas{width:100%;display:flex;flex-direction:column;gap:.75rem;text-align:left}
.vl-p-botones{width:100%;display:flex;flex-direction:column;gap:.5rem}
.vl-p-botones .vl-sec{width:100%;min-height:3.25rem;font-size:1.0625rem}
@media (prefers-reduced-motion: reduce){.vl-ayuda summary .vl-chev{transition:none}.vl-entrar:active,.vl-boton:not(:disabled):active{transform:none}}
/* El recorte de las franjas negras metidas en el archivo: el cuadro ya tiene la
   forma de la zona útil y el video la llena, parejo de los dos lados. En
   pantalla completa se ve entero. */
.gu-cuadro.gu-recortado video,.gu-vpq-cuadro.gu-recortado video{object-fit:cover}
.gu-cuadro video:fullscreen,.gu-vpq-cuadro video:fullscreen{object-fit:contain}
.gu-cuadro video:-webkit-full-screen,.gu-vpq-cuadro video:-webkit-full-screen{object-fit:contain}
@media (prefers-reduced-motion: reduce){.gu-punto,.gu-icono-play.gu-pulso::before,.gu-girando{animation:none}.gu-chip{transition:none}.gu-placa-barra>span{animation:none;width:100%}}
`;

  function inyectarEstilos() {
    if (document.getElementById('gu-estilos')) return;
    const s = document.createElement('style');
    s.id = 'gu-estilos';
    s.textContent = ESTILOS;
    document.head.appendChild(s);
  }

  // ─── Piezas de HTML ─────────────────────────────────────────────
  // Las claves de los recuadros: «v:<id>» por video y «l» para la videollamada.
  const claveCampo = video => (video == null || video === '' ? 'l' : 'v:' + video);
  const videoDeClave = k => (k === 'l' ? '' : k.slice(2));

  function htmlMotivo(motivo) {
    const { hacer, paraQue } = R.partes(motivo);
    if (!hacer && !paraQue) return '';
    return `<div class="gu-motivo">${paraQue ? `<p><span class="gu-marca-t">Para qué.</span> ${esc(paraQue)}</p>` : ''}${hacer ? `<p class="gu-hacer"><span class="gu-marca-t">Qué hacer.</span> ${esc(hacer)}</p>` : ''}</div>`;
  }

  function htmlContador(n) {
    if (n <= 800) return '';
    return n > MAX_TEXTO ? `Te pasaste: ${fmtNum(n)} de 1.000 caracteres` : `${fmtNum(n)} de 1.000 caracteres`;
  }

  // El valor del recuadro no va en el HTML: se pone después (así repintar no
  // depende de lo que se escribe).
  function htmlCampo(k, placeholder) {
    return `<div class="gu-campo"><textarea data-gu-campo="${esc(k)}" rows="2" placeholder="${esc(placeholder)}" aria-label="${esc(placeholder)}"></textarea><div class="gu-contador" data-gu-contador="${esc(k)}" aria-live="polite"></div></div>`;
  }

  function htmlEstadoEnvio(envio, listo, enCola) {
    let t = '', cls = '';
    if (envio === 'noSeGuardo') { t = 'No se pudo guardar, probá de nuevo o escribime por el chat.'; cls = ' gu-peligro'; }
    else if (envio === 'listo' && !enCola) t = listo;
    else if (envio === 'enviando' || envio === 'listo') t = enCola ? 'Se envía sola apenas tengas señal.' : listo;
    return `<span class="gu-envio-estado${cls}" role="status">${esc(t)}</span>`;
  }

  function htmlEncola(t) {
    return `<div class="gu-encola" aria-label="${esc('Enviando: ' + t)}">${I.reloj}<span>${esc(t)}</span></div>`;
  }

  function htmlDudaVideo(m, clip, despues) {
    const ya = R.renglones(clip.duda);
    const enCola = m.pendientesSinLlegar.filter(p => p.video === clip.id);
    const k = claveCampo(clip.id);
    let h = '<div class="gu-duda"><div class="gu-duda-titulo">¿Te quedó alguna duda de este video?</div>';
    if (ya.length || enCola.length) {
      h += '<div class="gu-ya">';
      if (ya.length) h += '<div class="gu-ya-titulo">Ya me dejaste</div>' + ya.map(d => `<p>${esc(d)}</p>`).join('');
      h += enCola.map(p => htmlEncola(p.texto)).join('');
      h += '</div>';
    }
    h += htmlCampo(k, despues ? 'Escribila acá y me llega' : 'Escribila acá y me llega antes de la videollamada');
    h += `<div class="gu-envio">${htmlEstadoEnvio(m.envios[clip.id], despues ? 'Listo, me llega y te contesto.' : 'Listo, me llega antes de la videollamada.', enCola.length > 0)}`;
    h += `<button type="button" class="gu-boton-marca" data-gu="enviar" data-k="${esc(k)}" disabled>Enviar duda</button></div></div>`;
    return h;
  }

  function htmlIconoClip(visto, actual, sonando) {
    if (visto) return `<span class="gu-icono gu-visto">${I.check}</span>`;
    if (actual) return `<span class="gu-icono ${sonando ? 'gu-sonando' : 'gu-es-actual'}">${sonando ? I.parlante : I.play}</span>`;
    return '<span class="gu-icono"></span>';
  }

  const mayusculaInicial = t => (t ? t.charAt(0).toUpperCase() + t.slice(1) : t);

  // «Agregar a mi calendario»: un .ics que abre el calendario del teléfono o de
  // la compu (como EventKit en iOS e Intent.ACTION_INSERT en Android: local,
  // sin permisos de cuenta). Nada sale del navegador.
  function agregarAlCalendario(r) {
    const i = r && R.instante(r.inicio), f = r && R.instante(r.fin);
    if (!i) return;
    const fin = f && f > i ? f : new Date(i.getTime() + 3600000);
    const utc = d => d.toISOString().replace(/[-:]/g, '').replace(/\.\d{3}/, '');
    const escIcs = t => String(t).replace(/[\\;,]/g, m => '\\' + m).replace(/\n/g, '\\n');
    const lineas = ['BEGIN:VCALENDAR', 'VERSION:2.0', 'PRODID:-//Pump Team//MyPump//ES', 'CALSCALE:GREGORIAN', 'BEGIN:VEVENT',
      `UID:${escIcs((r.id || utc(i)) + '@mypump')}`, `DTSTAMP:${utc(new Date())}`, `DTSTART:${utc(i)}`, `DTEND:${utc(fin)}`,
      `SUMMARY:${escIcs(RA.mayuscula(RA.nombre(r.tipo)) + ' con Mati')}`,
      // Se entra desde la app (Mati, 10/11); el link queda en el evento solo de respaldo.
      `DESCRIPTION:${escIcs('Entrá desde la app MyPump, en Entreno. Mati te admite en la sala.')}`];
    if (r.meetUrl) lineas.push(`URL:${r.meetUrl}`);
    lineas.push('END:VEVENT', 'END:VCALENDAR');
    const url = URL.createObjectURL(new Blob([lineas.join('\r\n') + '\r\n'], { type: 'text/calendar;charset=utf-8' }));
    const a = document.createElement('a');
    a.href = url; a.download = 'videollamada-mypump.ics'; a.rel = 'noopener';
    document.body.appendChild(a); a.click(); a.remove();
    setTimeout(() => URL.revokeObjectURL(url), 10000);
  }

  // ─── La videollamada (VideollamadaView, 2.3.0) ──────────────────
  // Decisión de Mati del 10/11: el alumno entra desde la app, nunca por un link
  // de WhatsApp.
  // · La tarjeta fija arriba de Entreno (y al final de la guía), desde que se
  //   agenda hasta que termina: día, hora (la del teléfono y la de Argentina si
  //   difiere), «Entrar» apagado con la cuenta regresiva y activo desde 10
  //   minutos antes (Meet restringido: Mati lo admite), y «¿Cómo entro?».
  // · Con la palanca `elegir_horario`: la pantalla para elegir el horario y
  //   para cambiarlo con el tope que manda el servidor.
  // · La web no agenda avisos: no hay permiso nuevo que pedir.
  // Al alumno nunca se le dice «entrega»: «de comienzo» o «de revisión».
  const VI = {
    mano: svg('<path d="M9 11.5V5.2a1.7 1.7 0 0 1 3.4 0v5.3l4.3.9a2.3 2.3 0 0 1 1.8 2.6l-.8 4.8a2.3 2.3 0 0 1-2.3 1.9h-4.8a2.3 2.3 0 0 1-1.9-1l-3.2-4.8a1.5 1.5 0 0 1 2.2-2z" fill="currentColor"/>'),
    pregunta: svg('<circle cx="12" cy="12" r="9" fill="none" stroke="currentColor" stroke-width="2"/><path d="M9.6 9.4a2.5 2.5 0 1 1 3.6 2.3c-.8.4-1.2.9-1.2 1.8v.4" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"/><circle cx="12" cy="17" r="1.2" fill="currentColor"/>'),
    cambiar: svg('<path d="M4.5 9.5a7.5 7.5 0 0 1 13.2-3.2L19.5 8M19.5 4v4h-4M19.5 14.5a7.5 7.5 0 0 1-13.2 3.2L4.5 16M4.5 20v-4h4" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>'),
    tilde: svg('<circle cx="12" cy="12" r="10" fill="currentColor"/><path d="M7.5 12.3l3 3 6-6.3" fill="none" stroke="var(--color-brand)" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"/>'),
    persona: svg('<circle cx="10" cy="8" r="3.6" fill="currentColor"/><path d="M3.5 19.5a6.5 6.5 0 0 1 13 0z" fill="currentColor"/><path d="M15.5 12.5l2 2 4-4" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>'),
  };
  // «¿Cómo entro?» abierto o cerrado, por cliente (los repintados no lo cierran).
  const ayudaAbierta = new Map();

  function htmlVideollamada(m, r, ahora) {
    const ag = m.agenda, desdeMin = ag.entrarDesdeMin;
    const e = RA.estadoEntrar(r, ahora, desdeMin);
    const activa = e.tipo === 'habilitado';
    const confirmada = r.estado === 'confirmada';
    const i = R.instante(r.inicio), f = R.instante(r.fin);
    const titulo = RA.tituloTarjeta(r.tipo);
    let h = `<section class="vl-tarjeta${activa ? ' vl-activa' : ''}" data-vl-token="${esc(m.token)}" aria-label="${esc(titulo)}">`;
    if (ag.desdeCache) h += `<p class="vl-sinred">${I.sinRed}<span>Sin conexión</span></p>`;
    const cuando = RA.cuando(r, undefined, ahora);
    h += `<div class="vl-cab"><span class="vl-icono" aria-hidden="true">${I.video}</span><h3 class="vl-titulo">${esc(titulo)}</h3>${
      cuando ? `<span class="vl-cuando">${esc(cuando)}</span>` : ''}</div>`;
    if (i) {
      const ar = RA.horaArgentina(i);
      h += `<div class="vl-fecha"><p class="vl-dia">${esc(RA.mayuscula(RA.diaLargo(i)))}</p>
        <p class="vl-hora"><span class="vl-hora-grande">${esc(RA.hora(i))}</span>${f ? `<span class="vl-hasta">a ${esc(RA.hora(f))}</span>` : ''}</p>${
        ar ? `<p class="vl-ar">${I.globo}<span>${esc(ar)}</span></p>` : ''}</div>`;
    }
    if (!confirmada) {
      h += `<p class="vl-reservando" role="status"><span class="gu-girando gu-chico" aria-hidden="true"></span><span>${esc(ag.textos.pendiente)}</span></p>`;
    } else if (activa) {
      h += `<div class="vl-entrar-zona"><p class="vl-ya">${esc(ag.textos.entrar(r))}</p>
        <a class="vl-boton vl-entrar" href="${esc(r.meetUrl)}" target="_blank" rel="noopener noreferrer" title="Abre Google Meet. Mati te admite en la sala">${I.video}<span>Entrar a la videollamada</span></a></div>`;
    } else {
      const cuenta = RA.textoCuenta(e, desdeMin);
      h += `<div class="vl-entrar-zona"><button type="button" class="vl-boton" disabled>${I.candado}<span>Entrar</span></button>${
        cuenta ? `<p class="vl-cuenta">${esc(cuenta)}</p>` : ''}</div>`;
    }
    if (confirmada && !activa) h += `<p class="vl-linea">${VI.mano}<span>${esc(RA.TEXTO_DESDE_ACA)}</span></p>`;
    if (activa) h += `<p class="vl-admite">${esc(RA.TEXTO_ADMITE)}</p>`;
    if (confirmada) {
      const abierta = !!ayudaAbierta.get(m.token);
      h += `<details class="vl-ayuda"${abierta ? ' open' : ''}><summary data-vl="ayuda">${VI.pregunta}<span>¿Cómo entro?</span>${I.chevron.replace('<svg', '<svg class="vl-chev"')}</summary>
        <ol>${RA.AYUDA_ENTRAR.map((t, n) => `<li><span aria-hidden="true">${n + 1}</span><span>${esc(t)}</span></li>`).join('')}</ol></details>`;
    }
    if (confirmada && !activa) {
      const cambiar = palancaElegirHorario() && ag.puedeCambiar;
      h += `<div class="vl-acciones"><button type="button" class="vl-sec" data-vl="calendario" aria-label="Agregar a mi calendario" title="Descarga el evento para tu calendario">${I.calendario}<span>Al calendario</span></button>${
        cambiar ? `<button type="button" class="vl-sec" data-vl="cambiar">${VI.cambiar}<span>Cambiar horario</span></button>` : ''}</div>`;
      if (!cambiar) h += `<p class="vl-nota">${esc(ag.textos.cambiar)}</p>`;
    }
    return h + '</section>';
  }

  // «Agendá tu videollamada» (palanca): arriba de Entreno y al final de la guía.
  function htmlAgendar(m) {
    const ag = m.agenda, t = ag.textos;
    const dias = RA.dias(ag.agenda ? ag.agenda.franjas : []);
    return `<section class="vl-tarjeta vl-agendar" data-vl-token="${esc(m.token)}" aria-label="${esc(t.tituloDe(ag.tipo))}">
      <div class="vl-cab"><span class="vl-icono" aria-hidden="true">${I.calendario}</span><h3 class="vl-titulo">${esc(t.tituloDe(ag.tipo))}</h3></div>${
      ag.aviso ? `<p class="vl-aviso" role="status">${I.alerta}<span>${esc(t.fallo(ag.aviso))}</span></p>` : ''}
      <p class="vl-sub">${esc(RA.textoDesde(dias))}</p>
      <button type="button" class="vl-boton" data-vl="elegir">${I.calendario}<span>Elegir horario</span></button></section>`;
  }

  // Lo de arriba de Entreno: la videollamada agendada (hasta que termina) o,
  // con la palanca y horarios libres, «Agendá tu videollamada».
  function htmlVideollamadaEntreno(m) {
    const r = m.reservaTarjeta();
    if (r) return htmlVideollamada(m, r, new Date());
    if (palancaElegirHorario() && m.resumen && m.resumen.ok !== false && m.estado !== 'oculta' && m.vistaAgenda.tipo === 'franjas') return htmlAgendar(m);
    return '';
  }

  // ── La pantalla para elegir o cambiar el horario (PantallaHorario) ──
  let pantalla = null;   // {m, cambiando, elegido, enviado, anuncios, el, foco, oyente, overflow}

  function diasPantalla(p) {
    const ag = p.m.agenda;
    const viejo = p.cambiando ? R.instante(p.cambiando.inicio) : null;
    return RA.dias(ag.agenda ? ag.agenda.franjas : [])
      .map(d => Object.assign({}, d, { chips: d.chips.filter(c => !viejo || c.inicio.getTime() !== viejo.getTime()) }))
      .filter(d => d.chips.length);
  }
  // Lo que ya quedó: la confirmada que no es la que se cambia.
  function listaPantalla(p) {
    const r = p.m.agenda.reserva;
    if (!p.enviado || !r || r.estado !== 'confirmada') return null;
    if (p.cambiando) {
      const nuevo = R.instante(r.inicio), viejo = R.instante(p.cambiando.inicio);
      return nuevo && viejo && nuevo.getTime() !== viejo.getTime() ? r : null;
    }
    return r;
  }

  function abrirPantalla(m, cambiando, desde) {
    if (pantalla || !palancaElegirHorario()) return;
    inyectarEstilos();
    const el = document.createElement('div');
    el.className = 'vl-pantalla';
    el.setAttribute('role', 'dialog');
    el.setAttribute('aria-modal', 'true');
    el.setAttribute('aria-labelledby', 'vl-p-titulo');
    el.innerHTML = `<div class="vl-p-barra"><span data-vl-zona="cerrar"></span><span class="vl-p-nav" data-vl-zona="nav"></span><span></span></div>
      <div class="vl-p-cuerpo" data-vl-zona="cuerpo"></div><div class="vl-p-pie" data-vl-zona="pie"></div>
      <div class="gu-oculto" aria-live="polite" data-vl-zona="vivo"></div>`;
    const p = { m, cambiando: cambiando || null, elegido: null, enviado: false, anuncios: m.agenda.anuncios, el, foco: desde || document.activeElement,
                overflow: document.documentElement.style.overflow, previo: {} };
    p.oyente = () => pintarPantalla();
    m.oyentes.add(p.oyente);
    pantalla = p;
    el.addEventListener('keydown', e => { if (e.key === 'Escape') { e.preventDefault(); e.stopPropagation(); cerrarPantalla(); } });
    document.body.appendChild(el);
    document.documentElement.style.overflow = 'hidden';
    pintarPantalla();
    setTimeout(() => { const t = el.querySelector('#vl-p-titulo'); if (t) t.focus({ preventScroll: true }); }, 0);
  }

  function cerrarPantalla() {
    const p = pantalla;
    if (!p) return;
    pantalla = null;
    p.m.oyentes.delete(p.oyente);
    p.el.remove();
    document.documentElement.style.overflow = p.overflow;
    if (p.foco && p.foco.isConnected && typeof p.foco.focus === 'function') p.foco.focus({ preventScroll: true });
    p.m.avisar();
  }

  function pintarPantalla() {
    const p = pantalla;
    if (!p) return;
    const ag = p.m.agenda;
    // Tomada, vencida o sin cambio: se vuelve a elegir con el aviso arriba.
    if (p.enviado && ag.anuncios !== p.anuncios && ag.aviso && !listaPantalla(p)) { p.enviado = false; p.elegido = null; }
    const lista = listaPantalla(p);
    const enviando = p.enviado && !lista && (!!ag.enCola || ag.pendiente);
    const tipo = (p.cambiando && p.cambiando.tipo) || ag.tipo;
    const zonas = {};
    p.el.querySelectorAll('[data-vl-zona]').forEach(z => { zonas[z.dataset.vlZona] = z; });
    const poner = (k, html) => { if (p.previo[k] !== html) { p.previo[k] = html; zonas[k].innerHTML = html; } };
    poner('cerrar', lista ? '' : '<button type="button" class="vl-p-cerrar" data-vl="cerrar">Cerrar</button>');
    poner('nav', lista ? '' : esc(p.cambiando ? 'Cambiar horario' : 'Elegí tu horario'));
    if (lista) {
      const i = R.instante(lista.inicio);
      const ar = i && RA.horaArgentina(i);
      poner('cuerpo', `<div class="vl-p-contenido vl-p-listo"><span class="vl-p-ok" aria-hidden="true">${I.check}</span>
        <h2 class="vl-p-titulo" id="vl-p-titulo" tabindex="-1">${esc(p.cambiando ? 'Listo, la cambiamos' : 'Listo, quedó agendada')}</h2>${
        i ? `<div class="vl-p-resumen"><p class="vl-titulo">${esc(RA.tituloTarjeta(lista.tipo))}</p><p class="vl-dia">${esc(RA.mayuscula(RA.diaLargo(i)))}</p>
          <p class="vl-hora-grande">${esc(RA.hora(i))}</p>${ar ? `<p class="vl-nota">${esc(ar)}</p>` : ''}</div>` : ''}
        <div class="vl-p-lineas"><p class="vl-linea">${VI.mano}<span>${esc(RA.textoListoEntrar(ag.entrarDesdeMin))}</span></p>
          <p class="vl-linea">${VI.persona}<span>${esc(RA.TEXTO_ADMITE)}</span></p></div>
        <div class="vl-p-botones"><button type="button" class="vl-boton" data-vl="cerrar">Listo</button>
          <button type="button" class="vl-sec" data-vl="calendario-listo">${I.calendario}<span>Agregar a mi calendario</span></button></div></div>`);
      poner('pie', '');
      zonas.pie.hidden = true;
      if (!p.anunciado) { p.anunciado = true; zonas.vivo.textContent = `Tu ${RA.nombre(lista.tipo)} quedó agendada`; setTimeout(() => { const t = p.el.querySelector('#vl-p-titulo'); if (t) t.focus({ preventScroll: true }); }, 0); }
      return;
    }
    zonas.pie.hidden = false;
    const dias = diasPantalla(p);
    const chips = dias.flatMap(d => d.chips);
    if (p.elegido && !chips.some(c => c.id === p.elegido)) p.elegido = null;
    const t = ag.textos;
    let c = `<div class="vl-p-contenido"><div class="vl-p-cab"><h2 class="vl-p-titulo" id="vl-p-titulo" tabindex="-1">${esc(p.cambiando ? 'Elegí el nuevo horario' : RA.tituloElegir(tipo))}</h2>
      <p class="vl-sub">${esc(RA.textoElegirPantalla(chips))}</p>${
      RA.difiereDeArgentina(chips.map(x => x.inicio)) ? `<p class="vl-zona">${I.globo}<span>${esc(RA.TEXTO_ZONA_TELEFONO)}</span></p>` : ''}</div>`;
    if (p.cambiando) {
      const ahoraEs = RA.textoAhoraEs(p.cambiando), tope = RA.textoTope(ag.agenda && ag.agenda.cambio);
      c += `<div class="vl-p-ahora">${ahoraEs ? `<b>${esc(ahoraEs)}</b>` : ''}${tope ? `<p class="vl-nota">${esc(tope)}</p>` : ''}</div>`;
    }
    if (ag.aviso) c += `<p class="vl-aviso" role="status">${I.alerta}<span>${esc(t.fallo(ag.aviso))}</span></p>`;
    if (!dias.length) c += `<p>${esc(t.sinFranjas)}</p>`;
    for (const d of dias) {
      c += `<section class="vl-p-dia" aria-label="${esc(RA.mayuscula(d.titulo))}"><h3>${esc(RA.mayuscula(d.titulo))}</h3><div class="vl-p-horas">`;
      for (const x of d.chips) {
        const sel = p.elegido === x.id;
        const debajo = RA.horaArgentina(x.inicio) || `a ${RA.hora(x.fin)}`;
        c += `<button type="button" class="vl-p-hora" data-vl="hora" data-id="${esc(x.id)}" aria-pressed="${sel}"${enviando ? ' disabled' : ''}
          aria-label="${esc(`${d.titulo}, a las ${RA.hora(x.inicio)}`)}"><b>${esc(RA.hora(x.inicio))}</b><span>${esc(debajo)}</span>${sel ? VI.tilde.replace('<svg', '<svg class="vl-p-tilde"') : ''}</button>`;
      }
      c += '</div></section>';
    }
    poner('cuerpo', c + '</div>');
    const elegido = chips.find(x => x.id === p.elegido);
    poner('pie', enviando
      ? `<div class="vl-p-enviando" role="status"><span class="gu-girando gu-chico" aria-hidden="true"></span><span>${esc(p.cambiando ? 'Estamos cambiando tu horario…' : t.pendiente)}</span></div>`
      : `<button type="button" class="vl-boton" data-vl="confirmar"${elegido ? '' : ' disabled'}>${esc(elegido ? RA.textoBotonElegir(elegido, !!p.cambiando) : 'Elegí un horario')}</button>`);
  }

  // Los botones de la tarjeta y de la pantalla (en Entreno y dentro de la guía).
  document.addEventListener('click', e => {
    const b = e.target.closest && e.target.closest('[data-vl]');
    if (!b) return;
    const enPantalla = pantalla && pantalla.el.contains(b);
    const tarjeta = b.closest('[data-vl-token]');
    const m = enPantalla ? pantalla.m : (tarjeta ? modelo(tarjeta.dataset.vlToken) : null);
    if (!m) return;
    switch (b.dataset.vl) {
      case 'ayuda': {
        e.preventDefault();
        const d = b.closest('details');
        const abierta = !ayudaAbierta.get(m.token);
        ayudaAbierta.set(m.token, abierta);
        if (d) d.open = abierta;
        break;
      }
      case 'calendario': agregarAlCalendario(m.reservaTarjeta()); break;
      case 'elegir': abrirPantalla(m, null, b); break;
      case 'cambiar': {
        const r = m.agenda.reserva;
        if (r && r.estado === 'confirmada' && m.agenda.puedeCambiar) abrirPantalla(m, r, b);
        break;
      }
      case 'cerrar': cerrarPantalla(); break;
      case 'calendario-listo': if (pantalla) agregarAlCalendario(listaPantalla(pantalla)); break;
      case 'hora':
        if (pantalla) { pantalla.elegido = pantalla.elegido === b.dataset.id ? null : b.dataset.id; pintarPantalla(); }
        break;
      case 'confirmar': {
        const p = pantalla;
        if (!p) break;
        const x = diasPantalla(p).flatMap(d => d.chips).find(c => c.id === p.elegido);
        if (!x) break;
        p.enviado = true;
        p.anuncios = m.agenda.anuncios;
        if (p.cambiando) m.agenda.cambiar(x.franja); else m.agenda.reservar(x.franja);
        pintarPantalla();
        break;
      }
      default: break;
    }
  });

  // ─── La vista de la guía (GuiaView + ControlReproductor) ────────
  let vistaAbierta = null;

  class Vista {
    constructor(m) {
      this.m = m;
      this.velocidad = 1;
      this.abiertos = new Set();
      this.motivos = new Set();
      this.volverA = null;
      this.portada = true;
      this.actualId = null;
      this.videoCargado = null;
      this.placaId = null;
      this.tPlaca = null;
      this.sinConexion = false;
      this.avance = new AvanceVideo(false);
      this.retomado = false;
      this.vpq = { abierto: null, video: null, avance: null, retomado: false, sinConexion: false };
      this.elegido = null;          // la franja de la hoja de confirmación
      this._anuncios = m.agenda.anuncios;
      this.previo = {};
      this._rafId = 0;
      this._oyente = () => this.programar();
      this._foco = document.activeElement;
      this._overflow = document.documentElement.style.overflow;
      this.construir();
      m.oyentes.add(this._oyente);
      m.audios.alEmpezar = () => { this.pausar(); this.vpqPausar(); };
      m.audios.alAnunciar = t => { if (this.vivo) { this.vivo.textContent = ''; setTimeout(() => { if (this.vivo) this.vivo.textContent = t; }, 50); } };
      m.audios.alTic = () => this.pintarTicAudio();
      // La guía abierta mira el reloj de la entrega confirmada (el botón para entrar).
      m.agenda.vigilar(this);
    }

    get despues() { return R.yaPaso(this.m.guia && this.m.guia.fechaEntrega); }
    clips() { return R.deLaLista(this.m.guia); }
    get actual() {
      if (this.actualId == null) return null;
      const i = this.clips().findIndex(c => c.id === this.actualId);
      return i < 0 ? null : i;
    }
    get clipActual() { const i = this.actual; return i == null ? null : this.clips()[i]; }
    get hayAnterior() { const i = this.actual; return i != null && R.anterior(this.clips(), i) != null; }
    get haySiguiente() { const i = this.actual; return i != null && R.siguiente(this.clips(), i) != null; }
    get reproduciendo() { return !!this.video && !this.video.paused && !this.video.ended; }
    get pantallaCompleta() { return document.fullscreenElement === this.video || !!(this.video && this.video.webkitDisplayingFullscreen); }

    // ── El DOM ──
    construir() {
      inyectarEstilos();
      const root = document.createElement('div');
      root.className = 'gu-overlay';
      root.setAttribute('role', 'dialog');
      root.setAttribute('aria-modal', 'true');
      root.setAttribute('aria-label', 'Tu guía');
      root.innerHTML = `
        <div class="gu-barra"><span class="gu-barra-titulo">Tu guía</span>
          <button type="button" class="gu-cerrar" data-gu="cerrar" aria-label="Cerrar la guía">${I.cerrar}</button></div>
        <div class="gu-banner" data-gu-zona="banner" hidden>${I.sinRed}<span>Sin conexión: ves lo último que guardaste</span></div>
        <div class="gu-scroll" data-gu-zona="scroll"><div class="gu-contenido">
          <div data-gu-zona="estado"></div>
          <div class="gu-card" data-gu-zona="cabecera"></div>
          <div class="gu-dolor-zona" data-gu-zona="dolor"></div>
          <section class="gu-card" data-gu-zona="reproductor" aria-label="Reproductor">
            <div class="gu-cuadro"><video playsinline webkit-playsinline controls preload="metadata" controlslist="nodownload"></video><div class="gu-capa" data-gu-zona="capa"></div></div>
            <div class="gu-banda" data-gu-zona="banda"></div>
            <div class="gu-actual" data-gu-zona="actual"></div>
          </section>
          <div data-gu-zona="resto" style="display:flex;flex-direction:column;gap:16px"></div>
        </div></div>
        <div data-gu-zona="hoja"></div>
        <div class="gu-oculto" aria-live="polite" data-gu-zona="vivo"></div>`;
      this.root = root;
      this.z = {};
      root.querySelectorAll('[data-gu-zona]').forEach(el => { this.z[el.dataset.guZona] = el; });
      this.vivo = this.z.vivo;
      this.video = root.querySelector('video');
      this.conectarVideo();
      root.addEventListener('click', e => this.alClic(e));
      root.addEventListener('input', e => this.alEscribir(e));
      root.addEventListener('keydown', e => {
        if (e.key !== 'Escape' || this.pantallaCompleta) return;
        e.preventDefault();
        // Con la hoja de confirmación abierta, Escape es «Elegir otro».
        if (this.elegido) { this.cerrarHoja(); return; }
        cerrarGuia();
      });
      this._visibilidad = () => {
        if (document.visibilityState === 'hidden') {
          this.pausar(); this.vpqPausar(); this.m.audios.cortar(); this.m.audios.cerrarSeccion();
        } else if (this.m.estado === 'lista') {
          this.m.audios.abrirSeccion();
          // De vuelta con la guía abierta: la agenda de nuevo (nunca de fondo).
          this.m.agenda.consultar();
        }
      };
      this._salida = () => { this.guardarAlSalir(); this.vpqGuardar(); };
      document.addEventListener('visibilitychange', this._visibilidad);
      window.addEventListener('pagehide', this._salida);
      document.body.appendChild(root);
      document.documentElement.style.overflow = 'hidden';
      setTimeout(() => { const b = root.querySelector('.gu-cerrar'); if (b) b.focus({ preventScroll: true }); }, 0);
    }

    destruir() {
      this.pausar();
      this.vpqCerrar(true);
      clearTimeout(this.tPlaca);
      cancelAnimationFrame(this._rafId); clearTimeout(this._tRespaldo); this._rafId = 0;
      this.m.audios.cortar();
      this.m.audios.cerrarSeccion();
      this.m.audios.alEmpezar = null; this.m.audios.alAnunciar = null; this.m.audios.alTic = null;
      this.m.agenda.dejarDeVigilar(this);
      this.m.oyentes.delete(this._oyente);
      document.removeEventListener('visibilitychange', this._visibilidad);
      window.removeEventListener('pagehide', this._salida);
      try { this.video.removeAttribute('src'); this.video.load(); } catch (_) { /* nada */ }
      this.root.remove();
      document.documentElement.style.overflow = this._overflow;
      if (this._foco && this._foco.focus && this._foco.isConnected) { try { this._foco.focus({ preventScroll: true }); } catch (_) { /* nada */ } }
    }

    conectarVideo() {
      const v = this.video;
      v.addEventListener('timeupdate', () => this.avanzo(v.currentTime));
      v.addEventListener('ended', () => this.termino());
      v.addEventListener('loadedmetadata', () => { ajustarCuadro(v); this.listo(); });
      v.addEventListener('error', () => {
        if (!v.getAttribute('src')) return;
        if (!this.portada || this.placaId) { this.sinConexion = true; this.programar(); }
      });
      v.addEventListener('play', () => {
        // Un solo video a la vez, y si grababa un audio, se frena.
        this.vpqPausar();
        this.m.audios.cortar();
        if (this.placaId) { clearTimeout(this.tPlaca); this.placaId = null; }
        this.portada = false;
        this.programar();
      });
      v.addEventListener('pause', () => this.programar());
    }

    // ── El reproductor ──
    prepararInicial() {
      if (this.actual != null) return;
      const i = R.inicial(this.clips());
      if (i == null) return;
      if (this.actualId != null) this.portada = true;
      this.cargar(i, false, false);
    }

    reproducir(i) { this.cargar(i, true, false); }
    siguiente() { const a = this.actual; if (a == null) return; const i = R.siguiente(this.clips(), a); if (i != null) this.cargar(i, true, true); }
    anterior() { const a = this.actual; if (a == null) return; const i = R.anterior(this.clips(), a); if (i != null) this.cargar(i, true, true); }

    empezar() {
      if (this.actual == null) { this.prepararInicial(); return; }
      this.portada = false;
      this.arrancar();
      this.programar();
    }

    cambiarVelocidad() {
      this.velocidad = R.velocidadSiguiente(this.velocidad);
      this.video.defaultPlaybackRate = this.velocidad;
      this.video.playbackRate = this.velocidad;
      this.programar();
    }

    cerrarPlaca() {
      if (!this.placaId) return;
      clearTimeout(this.tPlaca);
      this.placaId = null;
      this.arrancar();
      this.programar();
    }

    reintentar() {
      const i = this.actual;
      if (i == null) return;
      this.videoCargado = null;
      this.cargar(i, true, false);
    }

    guardarAlSalir() {
      const id = this.videoCargado;
      if (!id || !this.video.getAttribute('src')) return;
      const g = this.avance.alSalir(this.video.currentTime);
      if (g) this.m.avance(id, g.segundos, g.visto);
    }

    pausar() {
      this.guardarAlSalir();
      if (this.video && !this.video.paused) this.video.pause();
    }

    // Arrancó el «Ver por qué»: este se frena y, si estaba la placa, se va sin arrancar.
    frenarPorOtro() {
      clearTimeout(this.tPlaca);
      this.placaId = null;
      if (!this.video.paused) this.pausar();
      this.programar();
    }

    cargar(i, reproducir, conPlaca) {
      const lista = this.clips();
      const clip = lista[i];
      if (!clip || !clip.url) return;
      this.guardarAlSalir();
      clearTimeout(this.tPlaca);
      this.placaId = null;
      this.actualId = clip.id;
      this.abiertos.add(R.claveBloque(clip));
      if (reproducir) this.portada = false;
      this.sinConexion = false;
      const v = this.video;
      if (this.videoCargado !== clip.id) {
        this.videoCargado = clip.id;
        this.avance = new AvanceVideo(clip.visto);
        this.retomado = false;
        if (navigator.onLine === false) {
          v.removeAttribute('src');
          try { v.load(); } catch (_) { /* nada */ }
          this.sinConexion = reproducir;
          this.programar();
          return;
        }
        marcarClip(v, clip.id, clip.url);
        v.src = clip.url;
        try { v.load(); } catch (_) { /* nada */ }
      }
      v.defaultPlaybackRate = this.velocidad;
      v.playbackRate = this.velocidad;
      // En pantalla completa la placa no se ve: ahí pasa directo.
      if (conPlaca && !this.pantallaCompleta) {
        v.pause();
        this.placaId = clip.id;
        this.tPlaca = setTimeout(() => this.cerrarPlaca(), PLACA_MS);
      } else if (reproducir) {
        this.arrancar();
      } else {
        v.pause();
      }
      this.programar();
    }

    arrancar() {
      const v = this.video;
      if (navigator.onLine === false && !v.getAttribute('src')) { this.sinConexion = true; this.programar(); return; }
      if (!v.getAttribute('src')) { const i = this.actual; if (i != null) { this.videoCargado = null; this.cargar(i, true, false); } return; }
      // Si ya había terminado, tocarlo de nuevo lo arranca desde el principio.
      if (R.estaAlFinal(v.currentTime, v.duration)) v.currentTime = 0;
      this.vpqPausar();
      this.m.audios.cortar();
      v.defaultPlaybackRate = this.velocidad;
      v.playbackRate = this.velocidad;
      const p = v.play();
      if (p && p.catch) {
        p.catch(err => {
          // El navegador no dejó arrancar solo (sin un toque): vuelve la portada.
          if (err && err.name === 'NotAllowedError') { this.portada = true; this.programar(); }
        });
      }
    }

    // Retoma donde quedó, una vez por carga.
    listo() {
      const v = this.video;
      v.playbackRate = this.velocidad;
      if (this.retomado) return;
      this.retomado = true;
      const c = this.m.guia && this.m.guia.clips.find(x => x.id === this.videoCargado);
      if (!c) return;
      const desde = R.retomar(c, v.duration);
      if (desde != null) {
        this.avance = new AvanceVideo(c.visto, desde);
        try { v.currentTime = desde; } catch (_) { /* nada */ }
      }
    }

    avanzo(t) {
      const v = this.video;
      if (this.placaId || v.paused || !this.videoCargado) return;
      const g = this.avance.alAvanzar(t, v.duration);
      if (g) this.m.avance(this.videoCargado, g.segundos, g.visto);
    }

    termino() {
      const id = this.videoCargado;
      if (!id) return;
      const g = this.avance.alTerminar(this.video.duration);
      this.m.avance(id, g.segundos, g.visto);
      // Pasa solo al siguiente, con su placa. Con una duda a medio escribir, no.
      if (this.haySiguiente && !R.textoParaMandar(this.m.borradores[id] || '')) this.siguiente();
      else this.programar();
    }

    // ── «Ver por qué» de un suplemento ──
    vpqVideo() {
      if (this.vpq.video) return this.vpq.video;
      const v = document.createElement('video');
      v.setAttribute('playsinline', ''); v.setAttribute('webkit-playsinline', '');
      v.controls = true; v.preload = 'metadata';
      v.setAttribute('controlslist', 'nodownload');
      v.addEventListener('timeupdate', () => {
        if (v.paused || !this.vpq.abierto || !this.vpq.avance) return;
        const g = this.vpq.avance.alAvanzar(v.currentTime, v.duration);
        if (g) this.m.avance(this.vpq.abierto, g.segundos, g.visto);
      });
      v.addEventListener('ended', () => {
        if (!this.vpq.abierto || !this.vpq.avance) return;
        const g = this.vpq.avance.alTerminar(v.duration);
        this.m.avance(this.vpq.abierto, g.segundos, g.visto);
      });
      v.addEventListener('loadedmetadata', () => {
        ajustarCuadro(v);
        if (this.vpq.retomado) return;
        this.vpq.retomado = true;
        const c = R.clipDeSuplemento(this.m.guia, this.vpq.abierto);
        const desde = c ? R.retomar(c, v.duration) : null;
        if (desde != null) { this.vpq.avance = new AvanceVideo(c.visto, desde); try { v.currentTime = desde; } catch (_) { /* nada */ } }
      });
      v.addEventListener('play', () => { this.frenarPorOtro(); this.m.audios.cortar(); });
      v.addEventListener('error', () => { if (v.getAttribute('src')) { this.vpq.sinConexion = true; this.programar(); } });
      this.vpq.video = v;
      return v;
    }

    vpqGuardar() {
      const v = this.vpq.video;
      if (!v || !this.vpq.abierto || !this.vpq.avance || !v.getAttribute('src')) return;
      const g = this.vpq.avance.alSalir(v.currentTime);
      if (g) this.m.avance(this.vpq.abierto, g.segundos, g.visto);
    }

    vpqPausar() {
      const v = this.vpq.video;
      if (!v || !this.vpq.abierto) return;
      this.vpqGuardar();
      if (!v.paused) v.pause();
    }

    vpqCerrar(sinPintar) {
      this.vpqPausar();
      this.vpq.abierto = null;
      const v = this.vpq.video;
      if (v) { v.removeAttribute('src'); try { v.load(); } catch (_) { /* nada */ } }
      if (!sinPintar) this.programar();
    }

    vpqAlternar(id) {
      if (this.vpq.abierto === id) { this.vpqCerrar(); return; }
      this.vpqCerrar(true);
      const c = R.clipDeSuplemento(this.m.guia, id);
      if (!c) { this.programar(); return; }
      this.vpq.abierto = id;
      this.vpq.avance = new AvanceVideo(c.visto);
      this.vpq.retomado = false;
      this.vpq.sinConexion = false;
      const v = this.vpqVideo();
      if (navigator.onLine === false) {
        this.vpq.sinConexion = true;
      } else {
        marcarClip(v, c.id, c.url);
        v.src = c.url;
        try { v.load(); } catch (_) { /* nada */ }
        this.frenarPorOtro();
        this.m.audios.cortar();
        const p = v.play();
        if (p && p.catch) p.catch(() => {});
      }
      this.programar();
    }

    vpqReintentar() {
      const id = this.vpq.abierto;
      if (!id) return;
      this.vpq.abierto = null;
      this.vpqAlternar(id);
    }

    // ── Eventos ──
    alClic(e) {
      const b = e.target.closest('[data-gu]');
      if (!b || !this.root.contains(b) || b.disabled) return;
      const a = b.dataset.gu;
      const m = this.m;
      switch (a) {
        case 'cerrar': cerrarGuia(); break;
        case 'reintentar-get': m.estado = m.guia ? 'lista' : 'cargando'; this.programar(); m.abrir().then(() => this.alLlegarGuia()); break;
        case 'empezar': this.empezar(); break;
        case 'placa': this.cerrarPlaca(); break;
        case 'reintentar-video': this.reintentar(); break;
        case 'anterior': this.anterior(); break;
        case 'siguiente': this.siguiente(); break;
        case 'velocidad': this.cambiarVelocidad(); break;
        case 'volver-lista': {
          const id = this.volverA;
          this.volverA = null;
          const fila = id && this.root.querySelector(`[data-gu-fila="${cssEsc(id)}"]`);
          if (fila) fila.scrollIntoView({ behavior: reducirMovimiento() ? 'auto' : 'smooth', block: 'center' });
          this.programar();
          break;
        }
        case 'paso': {
          const destino = b.dataset.paso === 'videos' ? this.z.reproductor : this.root.querySelector('.gu-llamada');
          if (destino) destino.scrollIntoView({ behavior: reducirMovimiento() ? 'auto' : 'smooth', block: 'start' });
          break;
        }
        case 'bloque': {
          const t = b.dataset.b;
          if (this.abiertos.has(t)) this.abiertos.delete(t); else this.abiertos.add(t);
          this.programar();
          break;
        }
        case 'fila': {
          const i = Number(b.dataset.i);
          const c = this.clips()[i];
          if (!c) break;
          this.reproducir(i);
          this.volverA = c.id;
          this.z.reproductor.scrollIntoView({ behavior: reducirMovimiento() ? 'auto' : 'smooth', block: 'start' });
          break;
        }
        case 'motivo': {
          const id = b.dataset.id;
          if (this.motivos.has(id)) this.motivos.delete(id); else this.motivos.add(id);
          this.programar();
          break;
        }
        case 'enviar': {
          const k = b.dataset.k;
          if (k === 'l') m.enviarDudaLlamada(); else m.enviarDuda(videoDeClave(k));
          break;
        }
        case 'vpq': this.vpqAlternar(b.dataset.id); break;
        case 'vpq-reintentar': this.vpqReintentar(); break;
        case 'quitar': m.ponerQuitada(true); break;
        case 'volver-mostrar': m.ponerQuitada(false); break;
        case 'grabar': if (document.activeElement && document.activeElement.blur) document.activeElement.blur(); m.audios.tocarGrabar(); break;
        case 'terminar': m.audios.terminar(); break;
        case 'escuchar': m.audios.alternarEscucha(); break;
        case 'mandar-audio': m.audios.mandar(); break;
        case 'regrabar': m.audios.grabarDeNuevo(); break;
        case 'borrar-audio': m.audios.borrar(); break;
        case 'reintentar-audio': m.audios.reintentar(b.dataset.id); break;
        // La agenda de la entrega (2.2.0)
        case 'ir-video': this.irAlVideo(b.dataset.id); break;
        case 'franja': this.elegido = b.dataset.id; this.programar(); break;
        case 'confirmar-reserva': {
          const c = this.chipElegido();
          this.elegido = null;
          if (c) m.agenda.reservar(c.franja);
          this.programar();
          break;
        }
        case 'elegir-otro': this.cerrarHoja(); break;
        case 'calendario': agregarAlCalendario(m.agenda.reserva); break;
        default: break;
      }
    }

    // «Ir al próximo video» y el contador de la agenda: abre su capítulo, lo
    // reproduce y sube al reproductor.
    irAlVideo(id) {
      const i = this.clips().findIndex(c => c.id === id);
      if (i < 0) return;
      this.abiertos.add(R.claveBloque(this.clips()[i]));
      this.reproducir(i);
      this.volverA = id;
      this.z.reproductor.scrollIntoView({ behavior: reducirMovimiento() ? 'auto' : 'smooth', block: 'start' });
    }

    chipElegido() {
      if (!this.elegido) return null;
      const a = this.m.agenda.agenda;
      for (const d of RA.dias(a ? a.franjas : [])) for (const c of d.chips) if (c.id === this.elegido) return c;
      return null;
    }

    cerrarHoja() {
      const id = this.elegido;
      this.elegido = null;
      this.programar();
      // El foco vuelve al chip que la abrió.
      setTimeout(() => {
        const b = id && this.root.querySelector(`[data-gu="franja"][data-id="${cssEsc(id)}"]`);
        if (b) b.focus({ preventScroll: true });
      }, 30);
    }

    alEscribir(e) {
      const t = e.target;
      if (!t || t.tagName !== 'TEXTAREA' || t.dataset.guCampo == null) return;
      const k = t.dataset.guCampo;
      this.m.borradores[videoDeClave(k)] = t.value;
      this.ajustarCampo(t, k);
    }

    ajustarCampo(t, k) {
      const c = this.root.querySelector(`[data-gu-contador="${cssEsc(k)}"]`);
      const n = largo(t.value);
      if (c) { c.textContent = htmlContador(n); c.classList.toggle('gu-peligro', n > MAX_TEXTO); }
      const b = this.root.querySelector(`[data-gu="enviar"][data-k="${cssEsc(k)}"]`);
      if (b) b.disabled = !R.textoParaMandar(t.value);
      t.style.height = 'auto';
      t.style.height = Math.min(t.scrollHeight + 3, 160) + 'px';
    }

    // Llegó una guía: el reproductor se prepara si su video ya no está.
    alLlegarGuia() {
      if (this.m.estado !== 'lista') return;
      this.prepararInicial();
      const c = this.clipActual;
      if (c) this.abiertos.add(R.claveBloque(c));
      this.programar();
    }

    // ── Pintar ──
    // Un repintado por cuadro. Con la pestaña en segundo plano el navegador
    // frena requestAnimationFrame: el setTimeout lo cubre.
    programar() {
      if (this._rafId) return;
      const hacer = () => {
        if (!this._rafId) return;
        cancelAnimationFrame(this._rafId); clearTimeout(this._tRespaldo);
        this._rafId = 0;
        this.pintar();
      };
      this._rafId = requestAnimationFrame(hacer);
      this._tRespaldo = setTimeout(hacer, 120);
    }

    // Cada zona se reemplaza solo si cambió, y el foco y lo escrito se conservan.
    zona(nombre, html) {
      if (this.previo[nombre] === html) return false;
      this.previo[nombre] = html;
      const el = this.z[nombre];
      const a = document.activeElement;
      const campo = a && a.tagName === 'TEXTAREA' && el.contains(a) ? a.dataset.guCampo : null;
      const sel = campo != null ? [a.selectionStart, a.selectionEnd] : null;
      el.innerHTML = html;
      el.querySelectorAll('textarea[data-gu-campo]').forEach(t => {
        const k = t.dataset.guCampo;
        t.value = this.m.borradores[videoDeClave(k)] || '';
        this.ajustarCampo(t, k);
        if (campo != null && k === campo) {
          try { t.focus({ preventScroll: true }); t.setSelectionRange(sel[0], sel[1]); } catch (_) { /* nada */ }
        }
      });
      return true;
    }

    pintar() {
      const m = this.m;
      if (m.estado === 'oculta') { cerrarGuia(); return; }
      const lista = m.estado === 'lista' && m.guia;
      this.z.banner.hidden = !(lista && m.desdeCache);
      ['cabecera', 'dolor', 'reproductor', 'resto'].forEach(n => { this.z[n].hidden = !lista; });
      if (!lista) {
        this.zona('estado', m.estado === 'sinRed'
          ? `<div class="gu-estado">${I.sinRed}<h3>No pudimos traer tu guía</h3><p class="gu-sub">Se cortó la conexión. Probá de nuevo cuando tengas señal.</p><button type="button" class="gu-boton-sec" data-gu="reintentar-get">Reintentar</button></div>`
          : '<div class="gu-estado" aria-busy="true"><div class="gu-girando" role="progressbar" aria-label="Cargando tu guía"></div></div>');
        return;
      }
      this.zona('estado', '');
      const clips = this.clips();
      if (this.actual == null) this.prepararInicial();
      const despues = this.despues;
      this.zona('cabecera', this.htmlCabecera(clips, despues));
      this.zona('dolor', this.htmlDolor(clips));
      this.zona('capa', this.htmlCapa(clips));
      this.zona('banda', this.htmlBanda(clips));
      const c = this.clipActual;
      this.zona('actual', c ? htmlMotivo(c.motivo) + htmlDudaVideo(m, c, despues) : '');
      this.z.actual.hidden = !c;
      if (this.zona('resto', this.htmlResto(clips, despues))) this.ubicarVpq();
      else if (this.vpq.abierto && this.vpq.video && !this.vpq.video.isConnected) this.ubicarVpq();
      this.pintarTicAudio();
      // La hoja de confirmación: solo mientras la franja sigue entre las que se ven.
      const chip = this.chipElegido();
      if (this.elegido && (!chip || this.m.vistaAgenda.tipo !== 'franjas')) this.elegido = null;
      if (this.zona('hoja', this.elegido ? this.htmlHoja(chip) : '') && this.elegido) {
        setTimeout(() => { const b = this.root.querySelector('[data-gu="confirmar-reserva"]'); if (b) b.focus({ preventScroll: true }); }, 0);
      }
      // Lo que dice la agenda (confirmada, tomada…), para los lectores de pantalla.
      const ag = this.m.agenda;
      if (ag.anuncios !== this._anuncios) {
        this._anuncios = ag.anuncios;
        const t = ag.anuncio;
        if (this.vivo && t) { this.vivo.textContent = ''; setTimeout(() => { if (this.vivo) this.vivo.textContent = t; }, 50); }
      }
    }

    // El video del «Ver por qué» vive fuera del HTML: se mueve a su lugar en
    // la misma tarea (así no se pausa).
    ubicarVpq() {
      const slot = this.z.resto.querySelector('[data-gu-slot="vpq"]');
      if (slot && this.vpq.video) { slot.insertBefore(this.vpq.video, slot.firstChild); ajustarCuadro(this.vpq.video); }
    }

    pintarTicAudio() {
      const a = this.m.audios;
      const c = this.root.querySelector('[data-gu-cuenta]');
      if (c && a.fase === 'grabando') c.textContent = contador(a.segundos);
      if (a.fase === 'revisando') {
        const e = a.escucha;
        const t = e && !e.paused ? e.currentTime : a.segundos;
        const cc = this.root.querySelector('[data-gu-cuenta-rev]');
        if (cc) cc.textContent = contador(t);
        const bar = this.root.querySelector('[data-gu-barra-rev]');
        if (bar) bar.style.width = `${Math.min(100, (e ? e.currentTime : 0) / Math.max(a.segundos, 0.1) * 100)}%`;
      }
    }

    htmlCabecera(clips, despues) {
      const g = this.m.guia;
      const a = R.avance(clips);
      const cuando = R.fechaLlamada(g.fechaEntrega);
      const hola = g.nombrePila ? `Hola ${g.nombrePila}` : 'Hola';
      const m = this.m;
      const hayDudas = g.dudasLlamada.length > 0 || g.clips.some(c => c.duda) || m.pendientesSinLlegar.length > 0
        || m.audios.locales.length > 0 || m.audios.servidor.length > 0;
      const intro = RD.introduccion(g, hayDudas);
      const avance = `<div style="margin-top:12px"><div class="gu-sub">${esc(R.textoAvance(a))}</div>
        <div class="gu-progreso" aria-hidden="true"><span style="width:${(R.fraccion(a) * 100).toFixed(1)}%"></span></div></div>`;
      if (intro) {
        const pasos = intro.pasos.map(p => `<button type="button" class="gu-paso gu-paso-${p.estado}" data-gu="paso" data-paso="${p.id}" aria-label="${esc(RD.textoHablado(p, intro.pasos.length))}">
          <span class="gu-paso-n" aria-hidden="true">${p.estado === 'hecho' ? '✓' : p.numero}</span><span class="gu-paso-t">${esc(p.titulo)}</span></button>`).join('');
        return `<div class="gu-cab"><h2>${esc(hola)}</h2><p>${esc(intro.texto)}</p><div class="gu-pasos">${pasos}</div>${avance}</div>`;
      }
      const txt = despues
        ? 'Te dejo estos videos según lo que hablamos en la videollamada. Miralos con calma, te van a servir para arrancar bien.'
        : `Armé estos videos para vos${cuando ? `, antes de nuestra videollamada del ${cuando}` : ''}, según lo que me contaste. Si llegás a ver el primer bloque, en la llamada vamos directo a lo tuyo.`;
      return `<div class="gu-cab"><h2>${esc(hola)}</h2><p>${esc(txt)}</p><div class="gu-firma">Mati</div>${avance}</div>`;
    }

    // «Lo que más te importa» y sus partes, arriba del reproductor. Sin `dolor`, nada.
    htmlDolor(clips) {
      const v = RD.vista(this.m.guia.dolor);
      if (!v) return '';
      const r = RD.reparto(R.bloques(clips), v);
      const tarjeta = (titulo, subtitulo, parrafos, bloque, aria) => `<section class="gu-card gu-dolor" aria-label="${esc(aria)}">
        <div class="gu-dolor-texto"><h3>${esc(titulo)}</h3>${subtitulo ? `<div class="gu-dolor-sub">${esc(subtitulo)}</div>` : ''}
        ${parrafos.map(p => `<p>${esc(p)}</p>`).join('')}</div>${bloque ? `<div class="gu-dolor-videos">${this.htmlBloque(bloque, clips, RD.TITULO_VIDEOS)}</div>` : ''}</section>`;
      return tarjeta(RD.TITULO_BLOQUE, v.subtitulo, v.parrafos, r.principal, RD.TITULO_BLOQUE)
        + v.partes.map((p, i) => tarjeta(p.titulo, null, p.parrafos, r.partes[i], p.titulo)).join('');
    }

    htmlCapa(clips) {
      const total = clips.length;
      if (this.placaId) {
        const i = clips.findIndex(c => c.id === this.placaId);
        const c = clips[i];
        if (c) {
          return `<button type="button" class="gu-placa" data-gu="placa" aria-label="${esc(c.titulo)}, tocá para empezar ya">
            <span class="gu-placa-ceja">${esc(R.textoPlaca(i, total))}</span>
            ${c.bloque ? `<span class="gu-placa-bloque">${esc(c.bloque)}</span>` : ''}
            <span class="gu-placa-titulo">${esc(c.titulo)}</span>
            <span class="gu-placa-barra"><span></span></span></button>`;
        }
      }
      if (this.sinConexion) {
        return `<div class="gu-sinvideo">${I.sinRed}<span>Necesitás conexión para ver el video</span><button type="button" class="gu-boton-sec" style="color:#fff;border-color:#fff" data-gu="reintentar-video">Reintentar</button></div>`;
      }
      const c = this.clipActual;
      if (this.portada && c) {
        const i = this.actual;
        return `<button type="button" class="gu-portada" data-gu="empezar" aria-label="${esc('Reproducir ' + c.titulo)}" title="${esc(`Video ${i + 1} de ${total}, ${R.duracionHablada(c.minutos)}`)}">
          <span class="gu-portada-titulo">${esc(c.titulo)}</span><span class="gu-linea-verde"></span>
          <span class="gu-portada-play">${I.play}</span></button>`;
      }
      return '';
    }

    htmlBanda(clips) {
      const c = this.clipActual, i = this.actual;
      let h = '';
      if (c) h += `<div class="gu-ceja">${esc(R.textoNumero(i, clips.length, c.bloque))}</div><h3>${esc(c.titulo)}</h3>`;
      h += '<div class="gu-botones">';
      if (this.hayAnterior) h += '<button type="button" class="gu-boton-chico" data-gu="anterior">Anterior</button>';
      if (this.haySiguiente) h += '<button type="button" class="gu-boton-chico" data-gu="siguiente">Siguiente</button>';
      const vel = R.textoVelocidad(this.velocidad);
      h += `<button type="button" class="gu-boton-chico" data-gu="velocidad" aria-label="Velocidad ${esc(vel)}" title="Cambia entre 1x, 1,25x y 1,5x">Velocidad ${esc(vel)}</button>`;
      if (this.volverA) h += '<button type="button" class="gu-boton-chico" data-gu="volver-lista">Volver a la lista</button>';
      return h + '</div>';
    }

    htmlBloque(b, clips, tituloEmbebido) {
      const abierto = this.abiertos.has(b.id);
      const vistos = b.indices.filter(i => clips[i] && clips[i].visto).length;
      const sub = R.textoBloque(b) + (vistos > 0 ? `, ${vistos === b.indices.length ? 'todos vistos' : `${vistos} ${vistos === 1 ? 'visto' : 'vistos'}`}` : '');
      // 2.2.0: «Novedad», con el destello y el color de la marca.
      const titulo = b.novedad ? `<span class="gu-bloque-titulo gu-novedad">${I.destello}${esc(b.titulo)}</span>` : `<span class="gu-bloque-titulo">${esc(tituloEmbebido || b.titulo)}</span>`;
      let h = `<div class="${tituloEmbebido ? 'gu-bloque-embebido' : 'gu-card'}"><button type="button" class="gu-bloque-cab" data-gu="bloque" data-b="${esc(b.id)}" aria-expanded="${abierto}">
        <span>${titulo}<span class="gu-sub">${esc(sub)}</span></span>${I.chevron.replace('<svg', '<svg class="gu-chev"')}</button>`;
      if (abierto) {
        h += '<div class="gu-filas">';
        for (const i of b.indices) if (clips[i]) h += this.htmlFila(clips[i], i);
        h += '</div>';
      }
      return h + '</div>';
    }

    htmlFila(c, i) {
      const actual = this.actualId === c.id;
      const { hacer, paraQue } = R.partes(c.motivo);
      const tieneMotivo = !!(hacer || paraQue);
      const abierto = this.motivos.has(c.id);
      const sonando = actual && this.reproduciendo;
      // 2.2.0: la etiqueta discreta de los obligatorios, solo con la agenda en el servidor.
      const etiqueta = this.m.agenda.disponible && RA.esObligatorio(c, this.m.guia) ? RA.ETIQUETA_OBLIGATORIO : null;
      const valor = [c.visto ? 'Visto' : 'Sin ver', actual ? 'Es el video actual' : null, etiqueta,
                     c.url ? R.duracionHablada(c.minutos) : 'Lo estoy subiendo'].filter(Boolean).join(', ');
      let h = `<div class="gu-fila${actual ? ' gu-fila-actual' : ''}" data-gu-fila="${esc(c.id)}"><div class="gu-fila-linea">
        <button type="button" class="gu-fila-boton" data-gu="fila" data-i="${i}" ${c.url ? '' : 'disabled'} aria-label="${esc(c.titulo + ', ' + valor)}">
          ${htmlIconoClip(c.visto, actual, sonando)}<span class="gu-fila-titulo">${esc(c.titulo)}${etiqueta ? `<span class="gu-etq-oblig" aria-hidden="true">${I.calendario}${esc(etiqueta)}</span>` : ''}</span>
          <span class="gu-dur">${esc(c.url ? R.duracion(c.minutos) : 'Lo estoy subiendo')}</span></button>`;
      if (tieneMotivo) {
        h += `<button type="button" class="gu-motivo-boton" data-gu="motivo" data-id="${esc(c.id)}" aria-label="Para qué sirve" aria-expanded="${abierto}">${I.chevron.replace('<svg', '<svg class="gu-chev"')}</button>`;
      }
      h += '</div>';
      if (abierto) h += htmlMotivo(c.motivo);
      return h + '</div>';
    }

    htmlLlamada(despues) {
      const m = this.m;
      const ya = m.dudasLlamadaVisibles;
      const enCola = m.pendientesSinLlegar.filter(p => p.video == null);
      let h = `<section class="gu-card gu-llamada" aria-label="Dudas para la videollamada">
        <h3>${despues ? '¿Te quedó algo para preguntarme?' : '¿Qué querés que hablemos en la videollamada?'}</h3>
        <p class="gu-recuadro">${despues ? 'Recorré tu plan con calma y si te surge alguna duda, anotala acá y te contesto.'
                                        : 'Recorré tu plan con calma y anotá acá todas las dudas que te surjan, así las vemos en la videollamada.'}</p>
        <p class="gu-nota">${despues ? 'Me llega y te contesto. Podés dejar varias.' : 'Me llega antes de la videollamada. Podés dejar varias.'}</p>`;
      if (ya.length || enCola.length) {
        h += '<div class="gu-lista-dudas">';
        if (ya.length) h += `<div class="gu-ya-titulo" style="padding-bottom:4px">${ya.length === 1 ? 'Ya me dejaste esta' : `Ya me dejaste estas ${ya.length}`}</div>`;
        h += ya.map(d => `<p>${esc(d)}</p>`).join('');
        h += enCola.map(p => htmlEncola(p.texto)).join('');
        h += '</div>';
      }
      if (m.puedeSumarDudaLlamada) {
        h += htmlCampo('l', despues ? 'Tu pregunta' : 'Por ejemplo, algo que no entendiste del plan o que querés cambiar');
        h += `<div class="gu-envio">${htmlEstadoEnvio(m.envios[''], despues ? 'Listo, me llega y te contesto.' : 'Listo, la vemos en la videollamada.', enCola.length > 0)}
          <button type="button" class="gu-boton-marca" data-gu="enviar" data-k="l" disabled>Enviar</button></div>`;
      } else {
        h += '<p class="gu-nota">Ya dejaste 30, que es el máximo. Si te queda algo, escribime por el chat.</p>';
      }
      if (m.audios.mostrar) h += this.htmlAudio(despues);
      return h + '</section>';
    }

    htmlAudio(despues) {
      const a = this.m.audios;
      let h = `<div class="gu-audio"><p class="gu-nota">${esc(TA.invitacion)}</p>`;
      if (a.fase === 'reposo' || a.fase === 'pidiendo') {
        h += `<div><button type="button" class="gu-boton-sec" data-gu="grabar" ${a.fase === 'pidiendo' || a.mandandoAlguno ? 'disabled' : ''}>${I.mic}${esc(TA.grabar)}</button></div>`;
        if (a.permiso === 'sinPreguntar') h += `<p class="gu-nota" style="font-size:12px">${esc(TA.antesDelPermiso)}</p>`;
      } else if (a.fase === 'grabando') {
        h += `<div class="gu-grabando"><button type="button" class="gu-terminar" data-gu="terminar" aria-label="${esc(TA.terminarAccesible)}" aria-pressed="true">${I.stop}${esc(TA.terminar)}</button>
          <span class="gu-punto" aria-hidden="true"></span><span class="gu-cuenta" data-gu-cuenta aria-hidden="true">${contador(a.segundos)}</span></div>`;
      } else if (a.fase === 'revisando') {
        const sonando = a.escucha && !a.escucha.paused;
        h += `<div class="gu-revision"><button type="button" class="gu-escuchar" data-gu="escuchar" ${a.url ? '' : 'disabled'} aria-label="${sonando ? 'Pausar tu audio' : 'Escuchar tu audio'}">${sonando ? I.pausa : I.play}</button>
          <span class="gu-barra-audio" aria-hidden="true"><span data-gu-barra-rev></span></span>
          <span class="gu-cuenta-chica" data-gu-cuenta-rev aria-label="${esc('Dura ' + contador(a.segundos))}">${contador(a.segundos)}</span></div>
          <div class="gu-botones" style="margin-top:0"><button type="button" class="gu-boton-marca" data-gu="mandar-audio" ${a.blob ? '' : 'disabled'}>${esc(TA.mandar)}</button>
          <button type="button" class="gu-boton-sec" data-gu="regrabar">${esc(TA.grabarDeNuevo)}</button>
          <button type="button" class="gu-boton-sec gu-rojo" data-gu="borrar-audio">${esc(TA.borrar)}</button></div>`;
      }
      if (a.aviso) {
        const gris = a.aviso === 'quedan30';
        h += `<p class="gu-nota${gris ? '' : ' gu-peligro'}">${esc(TA.avisos[a.aviso] || '')}</p>`;
      }
      for (const f of a.filas) {
        let ic = I.subiendo, cls = '', t = '', extra = '';
        if (f.estado === 'mandando') t = TA.mandando;
        else if (f.estado === 'noSeMando') { ic = I.alerta; cls = ' gu-peligro'; t = TA.noSeMando; extra = `<button type="button" class="gu-boton-sec" data-gu="reintentar-audio" data-id="${esc(f.id)}">${esc(TA.reintentar)}</button>`; }
        else if (f.estado === 'rechazado') { ic = I.alerta; cls = ' gu-peligro'; t = TA.avisos[f.aviso] || TA.noSeMando; }
        else if (f.estado === 'subido') { ic = I.listo.replace('<svg', '<svg class="gu-ok"'); t = TA.subido(despues); }
        else if (f.estado === 'error') { ic = I.alerta; cls = ' gu-peligro'; t = TA.errorTranscripcion; }
        h += `<div class="gu-fila-audio${cls}">${ic}<div><span>${esc(t)}</span>${extra}</div></div>`;
      }
      return h + '</div>';
    }

    htmlSupl(despues) {
      const s = vistaSuplementacion(this.m.guia.suplementacion);
      if (!s) return '';
      const neg = t => R.negritas(t).map(x => (x.negrita ? `<strong>${esc(x.texto)}</strong>` : esc(x.texto))).join('');
      let h = `<section class="gu-card gu-pad gu-supl" aria-label="${esc(s.titulo)}"><h3>${esc(s.titulo)}</h3>`;
      if (s.accion) h += `<p class="gu-sub" style="margin:0">${esc(s.accion)}</p>`;
      for (const mo of s.momentos) {
        h += `<div class="gu-momento"><div class="gu-momento-titulo" role="heading" aria-level="4">${esc(mo.titulo)}</div>`;
        for (const f of mo.filas) {
          h += `<div class="gu-item"><div class="gu-item-linea"><span class="gu-item-nombre">${esc(f.nombre)}${f.nuevo ? '<span class="gu-etq">nuevo</span>' : ''}${f.opcional ? '<span class="gu-etq gu-gris">opcional</span>' : ''}</span>${f.cantidad ? `<span class="gu-cant">${esc(f.cantidad)}</span>` : ''}</div>`;
          if (f.nota) h += `<p class="gu-sub">${esc(f.nota)}</p>`;
          if (f.porQue) h += `<p><span class="gu-marca-t">Por qué.</span> ${esc(f.porQue)}</p>`;
          for (const d of f.detalle) h += `<p class="gu-detalle">${neg(d)}</p>`;
          const c = R.clipDeSuplemento(this.m.guia, f.videoId);
          if (c) h += this.htmlVerPorQue(c, f.nombre, despues);
          h += '</div>';
        }
        h += '</div>';
      }
      if (s.sigue) h += `<div class="gu-momento"><p style="margin:0;font-size:14px"><strong>Sigue igual.</strong> ${esc(s.sigue)}</p></div>`;
      if (s.sale.length) {
        h += `<div class="gu-momento"><p style="margin:0;font-size:14px"><strong>Dejás de tomar.</strong> ${esc(s.sale.map(x => x.nombre).join(', '))}</p>`;
        for (const x of s.sale) if (x.porQue) h += `<p class="gu-nota">${esc(`${x.nombre}: ${x.porQue}`)}</p>`;
        h += '</div>';
      }
      return h + '</section>';
    }

    htmlVerPorQue(c, nombre, despues) {
      const abierto = this.vpq.abierto === c.id;
      const icono = abierto ? I.stop : c.visto ? I.listo.replace('<svg', '<svg class="gu-visto-t"') : I.play;
      const label = abierto ? `Cerrar el video de ${nombre}` : `${R.rotuloVerPorQue(c)}, ${nombre}${c.visto ? ', visto' : ''}`;
      let h = `<div class="gu-vpq"><button type="button" class="gu-vpq-boton" data-gu="vpq" data-id="${esc(c.id)}" aria-expanded="${abierto}" aria-label="${esc(label)}">${icono}${esc(abierto ? 'Cerrar el video' : R.rotuloVerPorQue(c))}</button>`;
      if (abierto) {
        h += '<div class="gu-vpq-cuadro" data-gu-slot="vpq">';
        if (this.vpq.sinConexion) h += `<div class="gu-sinvideo">${I.sinRed}<span>Necesitás conexión para ver el video</span><button type="button" class="gu-boton-sec" style="color:#fff;border-color:#fff" data-gu="vpq-reintentar">Reintentar</button></div>`;
        h += '</div>';
        h += htmlDudaVideo(this.m, c, despues);
      }
      return h + '</div>';
    }

    // ── La agenda de la entrega (AgendaView, 2.2.0) ──
    // El servidor decide: acá solo se pide, se muestra y se reserva. Sin la 021
    // (vista «nada») no se pinta nada.
    htmlAgenda() {
      const m = this.m, ag = m.agenda;
      const v = m.vistaAgenda;
      if (v.tipo === 'nada') return '';
      const t = ag.textos;
      const primero = RA.primeroQueFalta(m.guia);
      let h = '<div class="gu-agenda" data-gu-ancla="agenda">';
      // El contador va con la agenda bloqueada o sin autorizar, si falta alguno.
      if ((v.tipo === 'noAutorizada' || v.tipo === 'bloqueada') && v.faltan > 0 && primero) {
        h += `<button type="button" class="gu-agenda-contador" data-gu="ir-video" data-id="${esc(primero.id)}" title="Va al primer video que te falta">${I.playCirculo}<span>${esc(RA.textoContador(v.faltan))}</span></button>`;
      }
      const caja = (clase, cuerpo) => `<section class="gu-card gu-agenda-caja${clase ? ' ' + clase : ''}" aria-label="${esc(t.titulo)}">${
        ag.desdeCache ? `<div class="gu-agenda-sinred">${I.sinRed}<span>Sin conexión</span></div>` : ''}${cuerpo}</section>`;
      const cab = (icono, titulo, tono) => `<h3 class="gu-agenda-cab${tono ? ' ' + tono : ''}">${icono}<span>${esc(titulo)}</span></h3>`;
      const aviso = a => (a ? `<p class="gu-agenda-aviso" role="status">${I.alerta}<span>${esc(t.fallo(a))}</span></p>` : '');
      switch (v.tipo) {
        case 'noAutorizada':
          h += caja('gu-gris', cab(I.candado, t.titulo, 'gu-apagado') + `<p class="gu-agenda-texto gu-apagado">${esc(t.noAutorizada)}</p>`);
          break;
        case 'bloqueada': {
          const habilitando = v.faltan === 0;
          let c = cab(I.candado, t.titulo, 'gu-apagado');
          c += `<p class="gu-agenda-texto gu-apagado">${habilitando ? '<span class="gu-girando gu-chico" aria-hidden="true"></span>' : ''}${esc(t.bloqueada(v.faltan))}</p>`;
          if (v.faltan > 0 && primero) c += `<div><button type="button" class="gu-boton-sec" data-gu="ir-video" data-id="${esc(primero.id)}">${I.play}Ir al próximo video</button></div>`;
          h += caja('gu-gris', c);
          break;
        }
        case 'franjas': {
          // La palanca `elegir_horario`: la pantalla nueva para elegir (y después cambiar).
          if (palancaElegirHorario()) { h += htmlAgendar(m); break; }
          const dias = RA.dias(ag.agenda.franjas);
          const chips = dias.flatMap(d => d.chips);
          let c = cab(I.calendario, t.titulo, 'gu-marca-t') + aviso(v.aviso);
          c += `<p class="gu-sub" style="margin:0">${esc(t.encabezado(chips))}</p>`;
          if (RA.difiereDeArgentina(chips.map(x => x.inicio))) c += `<p class="gu-agenda-zona">${I.globo}<span>${esc(RA.TEXTO_ZONA_TELEFONO)}</span></p>`;
          for (const d of dias) {
            c += `<div class="gu-agenda-dia"><div class="gu-agenda-dia-titulo" role="heading" aria-level="4">${esc(mayusculaInicial(d.titulo))}</div><div class="gu-chips">`;
            c += d.chips.map(x => `<button type="button" class="gu-chip" data-gu="franja" data-id="${esc(x.id)}" aria-label="${esc(`${d.titulo}, de ${x.texto}`)}" title="Abre la confirmación">${esc(x.texto)}</button>`).join('');
            c += '</div></div>';
          }
          h += caja('', c);
          break;
        }
        case 'sinFranjas':
          h += caja('', cab(I.calendario, t.titulo) + aviso(v.aviso) + `<p class="gu-agenda-texto">${esc(t.sinFranjas)}</p>`);
          break;
        case 'reservando':
          h += caja('', cab(I.calendario, t.titulo) + `<p class="gu-agenda-texto" role="status"><span class="gu-girando gu-chico" aria-hidden="true"></span>${esc(t.pendiente)}</p>`);
          break;
        case 'confirmada':
          // La misma tarjeta que arriba de Entreno (videollamada 2.3.0).
          h += htmlVideollamada(m, v.reserva, new Date());
          if (v.aviso) h += `<p class="gu-sub" style="margin:0">${esc(RA.TEXTO_AVISO[v.aviso] || '')}</p>`;
          break;
        default: break;
      }
      return h + '</div>';
    }

    // La hoja de confirmación: sin formularios, «Confirmar» o «Elegir otro».
    htmlHoja(c) {
      const t = this.m.agenda.textos;
      return `<div class="gu-hoja-fondo" data-gu="elegir-otro"></div>
        <div class="gu-hoja" role="dialog" aria-modal="true" aria-labelledby="gu-hoja-texto">
          <span class="gu-hoja-icono" aria-hidden="true">${I.calendario}</span>
          <p id="gu-hoja-texto">${esc(t.confirmar(c))}</p>
          <button type="button" class="gu-boton-marca gu-boton-ancho" data-gu="confirmar-reserva">Confirmar</button>
          <button type="button" class="gu-boton-sec gu-boton-ancho" data-gu="elegir-otro">Elegir otro</button>
        </div>`;
    }

    htmlResto(clips, despues) {
      // Sin `dolor`, `resto` son todos los capítulos, como siempre.
      const bloques = RD.reparto(R.bloques(clips), RD.vista(this.m.guia.dolor)).resto;
      // 2.2.0: lo nuevo arriba de todo; debajo, lo de siempre.
      let h = bloques.filter(b => b.novedad).map(b => this.htmlBloque(b, clips)).join('');
      h += bloques.filter(b => b.esApp).map(b => this.htmlBloque(b, clips)).join('');
      h += this.htmlLlamada(despues);
      h += bloques.filter(b => !b.esApp && !b.novedad).map(b => this.htmlBloque(b, clips)).join('');
      h += this.htmlSupl(despues);
      // La agenda de la entrega, al final (después de las dudas para la llamada).
      h += this.htmlAgenda();
      h += `<p class="gu-card gu-pie">${despues ? 'Si algún video no te carga o tenés algo para contarme, escribime por el chat.'
                                               : 'Si algún video no te carga o tenés algo para contarme antes de la llamada, escribime por el chat.'}</p>`;
      if (this.m.puedeQuitar) h += `<button type="button" class="gu-accion" data-gu="quitar" title="La guía queda en Mis datos">${I.ojoTachado}Quitar de Entreno</button>`;
      else if (this.m.puedeVolverAMostrar) h += `<button type="button" class="gu-accion" data-gu="volver-mostrar">${I.ojo}Volver a mostrar en Entreno</button>`;
      return h;
    }
  }

  function cssEsc(s) {
    return window.CSS && window.CSS.escape ? window.CSS.escape(s) : String(s).replace(/["\\]/g, '\\$&');
  }

  function cerrarGuia() {
    const v = vistaAbierta;
    if (!v) return;
    vistaAbierta = null;
    v.destruir();
    repintarTarjetas();
    window.dispatchEvent(new CustomEvent('mypump:guia', { detail: { tipo: 'cerrada' } }));
  }

  async function abrirGuia(token) {
    if (!tokenValido(token) || esDemo() || !db()) return false;
    if (vistaAbierta) return true;
    const m = modelo(token);
    if (m.estado === 'oculta') m.estado = m.guia ? 'lista' : 'cargando';
    const v = new Vista(m);
    vistaAbierta = v;
    v.pintar();
    v.alLlegarGuia();
    // El get, una vez por apertura.
    await m.abrir();
    if (vistaAbierta !== v) return true;
    v.alLlegarGuia();
    if (m.estado === 'lista') m.audios.abrirSeccion();
    if (m.cola.length) m.procesarCola();
    // La agenda de la entrega (2.2.0): lo que quedó en la cola ya está en el
    // modelo; acá, la consulta. Sin la 021 no se ve nada.
    if (m.estado === 'lista') m.agenda.consultar();
    return true;
  }

  // ─── La tarjeta de Entreno (TarjetaGuia y TarjetaGuiaDestacada) ──
  const tarjetas = [];

  // 2.3.0: la videollamada fija arriba, desde que se agenda hasta que termina
  // (aunque la tarjeta de la guía esté oculta). Antes, «Tu guía».
  function htmlTarjeta(m) {
    return htmlVideollamadaEntreno(m) + htmlTarjetaGuia(m);
  }

  function htmlTarjetaGuia(m) {
    if (m.tarjetaDestacada) {
      // 2.2.0: con novedad sin ver, «NOVEDAD EN TU GUÍA» con el avance de lo nuevo; si no, la de la 2.1.0.
      const nov = m.avanceNovedad;
      const a = nov || m.avanceTarjeta;
      const t = nov ? R.textoTarjetaNovedad(nov) : R.textoTarjeta(a);
      const pulso = m.primeraSesionTarjeta && !reducirMovimiento();
      return `<div class="gu-tarjeta gu-destacada" role="group" aria-label="${nov ? 'Novedad en tu guía' : 'Tu guía'}">
        <div class="gu-dest-cab"><span class="gu-dest-ceja">${nov ? 'Novedad en tu guía' : 'Empezá por acá'}</span>
          <button type="button" class="gu-ocultar" data-gu-t="ocultar" title="La guía queda en Mis datos">Ocultar</button></div>
        <div class="gu-dest-fila"><span class="gu-icono-play${pulso ? ' gu-pulso' : ''}" aria-hidden="true">${I.play}</span>
          <div><div class="gu-dest-titulo">Tu guía</div><div class="gu-dest-sub">${esc(t)}</div></div></div>
        <div class="gu-barra-blanca" aria-hidden="true"><span style="width:${R.fraccion(a) > 0 ? Math.max(3, R.fraccion(a) * 100).toFixed(1) : 0}%"></span></div>
        <button type="button" class="gu-boton-blanco" data-gu-t="abrir">${I.play}${esc(nov ? 'Ver lo nuevo' : R.botonTarjeta(a))}</button></div>`;
    }
    if (m.mostrarTarjeta) {
      const a = m.avanceTarjeta;
      const t = R.textoTarjeta(a);
      const r = 18, circ = 2 * Math.PI * r, f = R.fraccion(a);
      return `<button type="button" class="gu-tarjeta gu-compacta" data-gu-t="abrir" aria-label="${esc('Tu guía, ' + t)}">
        <span class="gu-anillo" aria-hidden="true"><svg viewBox="0 0 44 44"><circle cx="22" cy="22" r="${r}" fill="none" stroke="var(--color-bg-tertiary)" stroke-width="4"/>
          <circle cx="22" cy="22" r="${r}" fill="none" stroke="currentColor" stroke-width="4" stroke-linecap="round" stroke-dasharray="${(circ * f).toFixed(2)} ${circ.toFixed(2)}"/></svg>
          <span>${R.completo(a) ? I.check : I.play}</span></span>
        <span class="gu-compacta-texto" aria-hidden="true"><b>Tu guía</b><span class="gu-sub">${esc(t)}</span></span>
        ${I.chevron.replace('<svg', '<svg class="gu-chev" style="transform:rotate(-90deg)"')}</button>`;
    }
    return '';
  }

  function pintarTarjeta(reg) {
    const m = modelo(reg.token);
    // La entrega confirmada que no terminó: la tarjeta mira el reloj (15 s) y, en
    // la franja sin la sala abierta, la agenda cada 30 s. Si la reserva vino solo
    // del resumen (la guía no se abrió), primero se trae la agenda, una vez.
    if (!esDemo() && reg.contenedor.isConnected) {
      m.agenda.vigilar(reg);
      const r = m.reservaTarjeta();
      // Con la palanca y sin reserva, la agenda dice si hay horarios para «Agendá tu videollamada».
      if (!reg.agendaPedida && !m.agenda.reserva && (r || (palancaElegirHorario() && m.resumen && m.resumen.ok))) {
        reg.agendaPedida = true; m.agenda.consultar();
      }
    } else {
      m.agenda.dejarDeVigilar(reg);
    }
    const html = esDemo() ? '' : htmlTarjeta(m);
    if (reg.previo === html) return !!html;
    reg.previo = html;
    reg.contenedor.innerHTML = html;
    reg.contenedor.hidden = !html;
    if (html && m.tarjetaDestacada) m.marcarTarjetaVista();
    return !!html;
  }

  function repintarTarjetas() {
    for (let i = tarjetas.length - 1; i >= 0; i--) {
      if (!tarjetas[i].contenedor.isConnected) { modelo(tarjetas[i].token).agenda.dejarDeVigilar(tarjetas[i]); tarjetas.splice(i, 1); continue; }
      pintarTarjeta(tarjetas[i]);
    }
  }
  oyentesGlobales.add(() => repintarTarjetas());

  function avisoOculta(token) {
    inyectarEstilos();
    const previo = document.querySelector('.gu-aviso-oculta');
    if (previo) previo.remove();
    const el = document.createElement('div');
    el.className = 'gu-aviso-oculta';
    el.setAttribute('role', 'status');
    el.innerHTML = `<span>${I.ojoTachado}La encontrás en Mis datos</span><button type="button" title="Vuelve a poner la guía en Entreno">Deshacer</button>`;
    let t = null;
    const sacar = () => { clearTimeout(t); el.remove(); };
    el.querySelector('button').addEventListener('click', () => { modelo(token).ponerQuitada(false); sacar(); });
    document.body.appendChild(el);
    t = setTimeout(sacar, 5000);
  }

  // ─── La bienvenida (BienvenidaGuia) ─────────────────────────────
  function mostrarBienvenida(m, nombreCuenta) {
    inyectarEstilos();
    const a = m.avanceTarjeta;
    const el = document.createElement('div');
    el.className = 'gu-bienvenida';
    el.setAttribute('role', 'dialog');
    el.setAttribute('aria-modal', 'true');
    el.setAttribute('aria-label', 'Tu guía');
    const titulo = R.tituloBienvenida(m.guia && m.guia.nombrePila, nombreCuenta);
    el.innerHTML = `<div class="gu-bv-cuerpo"><div class="gu-bv-halo"><span class="gu-icono-play${reducirMovimiento() ? '' : ' gu-pulso'}" aria-hidden="true">${I.play}</span></div>
      <div style="display:flex;flex-direction:column;gap:12px"><h2>${esc(titulo)}</h2><p>${esc(R.textoBienvenida(a))}</p></div></div>
      <div class="gu-bv-botones"><button type="button" class="gu-boton-marca" data-bv="ver">${I.play}Ver mi guía</button>
      <button type="button" class="gu-mas-tarde" data-bv="tarde" title="La guía te queda arriba de Entreno">Más tarde</button></div>`;
    const overflow = document.documentElement.style.overflow;
    const cerrar = () => { el.remove(); document.documentElement.style.overflow = overflow; };
    el.addEventListener('click', e => {
      const b = e.target.closest('[data-bv]');
      if (!b) return;
      cerrar();
      if (b.dataset.bv === 'ver') abrirGuia(m.token);
    });
    el.addEventListener('keydown', e => { if (e.key === 'Escape') cerrar(); });
    document.body.appendChild(el);
    document.documentElement.style.overflow = 'hidden';
    m.marcarBienvenidaVista();
    setTimeout(() => { const b = el.querySelector('[data-bv="ver"]'); if (b) b.focus({ preventScroll: true }); }, 0);
  }

  // ─── API pública ────────────────────────────────────────────────
  function resumenPublico(m) {
    const r = m.resumen;
    if (!r || !r.ok) return null;
    return {
      ok: true,
      total: r.total,
      vistos: r.vistos,
      minutos_restantes: r.minutosRestantes,
      fecha_entrega: r.fechaEntrega,
      mostrar_tarjeta: r.mostrarTarjetaServidor,
      // Lo que ya resolvieron las reglas de la app:
      tarjeta_en_entreno: m.mostrarTarjeta,
      fila_en_mis_datos: m.mostrarFila,
      quitada: m.quitadaVigente,
    };
  }

  // ─── La forma de cada video (FormaVideo.swift y ReglasVideo) ────
  // El cuadro toma la proporción real del clip: a todo el ancho si entra; los
  // verticales hasta el 60 % del alto visible, centrados. Además, si el archivo
  // trae el negro adentro (una grabación vertical metida en un 1280×720), el
  // cuadro toma la forma de la zona útil y el video se recorta a ella (pedido de
  // Mati del 6/11: «nunca hay franjas negras»).
  //
  // La zona útil se mide una sola vez por clip (id y url), con el clip ya
  // cargado y de a uno: en un <video> aparte con crossorigin (sin tocar el que
  // se ve), 4 cuadros chicos al 30, 50, 70 y 90 % (desde el 30 % para saltear
  // la placa del título), dibujados en un canvas. Si el servidor no deja leer
  // los píxeles (el canvas queda «tainted») o algo falla, no se recorta y queda
  // como antes, sin errores. Lo medido queda guardado en el navegador.
  const CLAVE_RECUADROS = 'mypump_guia_recuadros';
  const TOPE_RECUADROS = 300;
  const claveRecuadro = (id, url) => `${id}|${url}`;
  const sinMedir = new Set();      // falló en esta sesión (CORS, red): no se insiste hasta recargar
  let colaMedir = Promise.resolve();
  const enMedicion = new Set();

  function recuadroGuardado(id, url) {
    const t = almacen.leer(CLAVE_RECUADROS, null);
    const v = esObjeto(t) ? t[claveRecuadro(id, url)] : null;
    if (!Array.isArray(v) || v.length !== 4 || !v.every(x => typeof x === 'number' && isFinite(x) && x >= 0 && x <= 1) || !(v[2] > 0) || !(v[3] > 0)) return null;
    return { x: v[0], y: v[1], ancho: v[2], alto: v[3] };
  }
  function guardarRecuadro(id, url, r) {
    let t = almacen.leer(CLAVE_RECUADROS, null);
    if (!esObjeto(t)) t = {};
    const k = claveRecuadro(id, url);
    if (Object.keys(t).length >= TOPE_RECUADROS && !(k in t)) t = {};
    t[k] = [r.x, r.y, r.ancho, r.alto];
    almacen.guardar(CLAVE_RECUADROS, t);
  }

  // El clip que va a mostrar este <video> (para la forma guardada y la medición).
  function marcarClip(v, id, url) { if (v) { v.dataset.guClip = id || ''; v.dataset.guUrl = url || ''; } }

  function ajustarCuadro(v) {
    const c = v && v.parentElement;
    if (!c || !v.videoWidth || !v.videoHeight) return;
    const id = v.dataset.guClip, url = v.dataset.guUrl;
    const archivo = RV.proporcion(v.videoWidth, v.videoHeight) || RV.PROPORCION_DEFECTO;
    const medido = id && url ? recuadroGuardado(id, url) : null;
    const recorte = RV.recorte(medido);
    const p = RV.conRecorte(archivo, recorte);
    c.style.aspectRatio = String(p);
    c.style.width = `min(100%, calc((100vh - 52px) * ${(RV.ALTO_MAXIMO * p).toFixed(4)}))`;
    c.classList.add('gu-ajustado');
    c.classList.toggle('gu-recortado', !!recorte);
    if (!medido && id && url) medirDespues(v, id, url);
  }

  function medirDespues(v, id, url) {
    const k = claveRecuadro(id, url);
    if (sinMedir.has(k) || enMedicion.has(k)) return;
    enMedicion.add(k);
    // De a una: cada medición abre el archivo y no compite con otra.
    colaMedir = colaMedir.then(async () => {
      // Un respiro para que el video que se ve arranque primero.
      await new Promise(r => setTimeout(r, 1200));
      let r = null;
      try { r = await medirRecuadro(url); } catch (_) { r = null; }
      enMedicion.delete(k);
      if (!r) { sinMedir.add(k); return; }
      guardarRecuadro(id, url, r);
      // Si ese <video> sigue con el mismo clip, el cuadro toma la forma nueva.
      if (v.isConnected && v.dataset.guClip === id && v.dataset.guUrl === url) ajustarCuadro(v);
    }).catch(() => { enMedicion.delete(k); });
  }

  function esperar(el, evento, ms) {
    return new Promise((ok, mal) => {
      const t = setTimeout(() => { limpiar(); mal(new Error('tiempo')); }, ms);
      const bien = () => { limpiar(); ok(); };
      const error = () => { limpiar(); mal(new Error('error')); };
      const limpiar = () => { clearTimeout(t); el.removeEventListener(evento, bien); el.removeEventListener('error', error); };
      el.addEventListener(evento, bien);
      el.addEventListener('error', error);
    });
  }

  // La unión de lo que no es negro en 4 cuadros chicos. RV.ENTERO si no hay
  // nada que medir de más (un video negro entero no se recorta); null si no se
  // pudo leer (se prueba en la próxima carga de la página).
  async function medirRecuadro(url) {
    if (!document.body) return null;
    const v = document.createElement('video');
    v.crossOrigin = 'anonymous';
    v.muted = true; v.defaultMuted = true;
    v.playsInline = true; v.setAttribute('playsinline', ''); v.setAttribute('webkit-playsinline', '');
    v.preload = 'auto';
    v.setAttribute('aria-hidden', 'true');
    v.style.cssText = 'position:fixed;left:-10px;top:-10px;width:2px;height:2px;opacity:0;pointer-events:none';
    document.body.appendChild(v);
    try {
      v.src = url;
      // En iOS un video que no arranca no carga cuadros: mudo y en línea se puede arrancar y frenar.
      try { const p = v.play(); if (p && p.then) p.then(() => v.pause()).catch(() => {}); } catch (_) { /* nada */ }
      await esperar(v, 'loadeddata', 20000);
      v.pause();
      const dur = v.duration;
      if (!isFinite(dur) || dur <= 0 || !v.videoWidth || !v.videoHeight) return null;
      const escala = Math.min(1, 320 / Math.max(v.videoWidth, v.videoHeight));
      const w = Math.max(1, Math.round(v.videoWidth * escala)), h = Math.max(1, Math.round(v.videoHeight * escala));
      const canvas = document.createElement('canvas');
      canvas.width = w; canvas.height = h;
      const ctx = canvas.getContext('2d', { willReadFrequently: true });
      if (!ctx) return null;
      const rs = [];
      let leidos = 0;
      for (const f of [0.3, 0.5, 0.7, 0.9]) {
        try {
          v.currentTime = dur * f;
          await esperar(v, 'seeked', 8000);
        } catch (_) { continue; }
        ctx.drawImage(v, 0, 0, w, h);
        let px;
        try { px = ctx.getImageData(0, 0, w, h).data; } catch (_) { return null; }   // «tainted»: no se recorta
        leidos++;
        const r = RV.recuadro(RV.luma(px, w * h), w, h);
        if (r) rs.push(r);
      }
      if (!leidos) return null;
      return RV.unir(rs) || RV.ENTERO;
    } finally {
      v.removeAttribute('src');
      try { v.load(); } catch (_) { /* nada */ }
      v.remove();
    }
  }

  window.MyPumpGuia = {
    // El resumen para la tarjeta (entregas_app_resumen, solo lee). null si no
    // hay guía, si falla sin nada guardado o en la demo.
    async cargarResumen(token) {
      if (!tokenValido(token) || esDemo() || !db()) return null;
      try {
        const m = modelo(token);
        await m.actualizarResumen();
        return resumenPublico(m);
      } catch (e) {
        console.warn('[guia] cargarResumen', e);
        return null;
      }
    },

    // Dibuja en `contenedor` la tarjeta verde, la compacta o nada. Se vuelve a
    // dibujar sola cuando cambia algo (el avance, Ocultar, Deshacer).
    async montarTarjeta(contenedor, token) {
      if (!contenedor) return false;
      inyectarEstilos();
      if (!tokenValido(token) || esDemo() || !db()) { contenedor.innerHTML = ''; contenedor.hidden = true; return false; }
      let reg = tarjetas.find(t => t.contenedor === contenedor);
      if (!reg) {
        reg = { contenedor, token, previo: null };
        tarjetas.push(reg);
        contenedor.addEventListener('click', e => {
          const b = e.target.closest('[data-gu-t]');
          if (!b || !contenedor.contains(b)) return;
          if (b.dataset.guT === 'abrir') abrirGuia(reg.token);
          else if (b.dataset.guT === 'ocultar') { modelo(reg.token).ponerQuitada(true); avisoOculta(reg.token); }
        });
      } else if (reg.token !== token) {
        reg.token = token; reg.previo = null;
      }
      pintarTarjeta(reg);
      try { await modelo(token).actualizarResumen(); } catch (_) { /* queda lo guardado */ }
      return pintarTarjeta(reg);
    },

    abrir(token) { return abrirGuia(token); },

    // La palanca `elegir_horario` de mypump_get_app_config: true/false, o null
    // (sin red o sin la función) para quedarse con lo último que se supo.
    aplicarPalanca(valor) {
      if (valor === null || valor === undefined) return palancaElegirHorario();
      const v = valor === true;
      try { if (v) localStorage.setItem(FLAG_ELEGIR, '1'); else localStorage.removeItem(FLAG_ELEGIR); } catch (_) { /* solo en memoria */ }
      if (v !== _elegirHorario) {
        _elegirHorario = v;
        if (!v) cerrarPantalla();
        for (const m of modelos.values()) m.avisar();
        repintarTarjetas();
      }
      return v;
    },
    cerrar() { cerrarGuia(); },
    abierta() { return !!vistaAbierta; },

    // La bienvenida de la primera vez: con la tarjeta en Entreno, sin ningún
    // video visto y una sola vez por cliente. `opciones.nombre`: el nombre de
    // la cuenta, si la guía guardada no trae nombre_pila.
    async bienvenidaSiCorresponde(token, opciones) {
      if (!tokenValido(token) || esDemo() || !db() || vistaAbierta) return false;
      const m = modelo(token);
      if (m.bienvenidaVista) return false;
      try { await m.actualizarResumen(); } catch (_) { /* lo guardado */ }
      if (!m.mostrarBienvenida || vistaAbierta || document.querySelector('.gu-bienvenida')) return false;
      mostrarBienvenida(m, opciones && opciones.nombre);
      return true;
    },

    // Para la fila «Ver mi guía» de Mis datos (con el resumen ya cargado).
    quitada(token) { return tokenValido(token) ? modelo(token).quitadaVigente : false; },
    mostrarFila(token) { return tokenValido(token) && !esDemo() ? modelo(token).mostrarFila : false; },
    puedeVolverAMostrar(token) { return tokenValido(token) && !esDemo() ? modelo(token).puedeVolverAMostrar : false; },
    quitar(token) { if (tokenValido(token)) modelo(token).ponerQuitada(true); },
    volverAMostrar(token) {
      if (!tokenValido(token)) return false;
      const m = modelo(token);
      m.ponerQuitada(false);
      return m.mostrarTarjeta;
    },

    // Avisa cada vez que cambia algo de la guía (resumen, quitada, avance).
    alCambiar(fn) {
      if (typeof fn !== 'function') return () => {};
      oyentesGlobales.add(fn);
      return () => oyentesGlobales.delete(fn);
    },

    // Para pruebas: las reglas puras y los normalizadores.
    _reglas: R,
    _AvanceVideo: AvanceVideo,
    _vistaSuplementacion: vistaSuplementacion,
    _normalizarGuia: normalizarGuia,
    _normalizarResumen: normalizarResumen,
  };
})();
