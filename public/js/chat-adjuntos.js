/* =============================================================
   chat-adjuntos.js — Fotos y audios en el chat con Mati (2.3.0, palanca `chat_adjuntos`).

   Gemelo de ReglasChatAdjuntos y de la cola de adjuntos de las apps:
   - El archivo espera en IndexedDB (por cuenta) hasta que mini-vision dice que entró. Sin señal queda «enviando…»;
     un rechazo queda «no salió» con «Reintentar» y «Borrar». Nunca se pierde sin aviso.
   - Un 429 (tope del día) NO se reintenta solo: cada intento volvería a mandar el archivo entero.
   - El id lo pone el teléfono (uuid): un reintento de algo que ya entró contesta `ya` y no duplica.
   - Lo que pasa con el archivo del lado de la Mini no se nombra nunca acá.

   Sin IndexedDB: queda en memoria y sirve con la pestaña abierta.
   ============================================================= */
(function (raiz) {
  'use strict';

  const R = {
    AUDIO_MAXIMO: 120,
    AUDIO_MINIMO: 1,
    AUDIO_AVISO: 110,
    DESLIZAR_PARA_CANCELAR_PX: 90,
    FOTO_LADO_MAXIMO: 1600,
    FOTO_CALIDAD: 0.75,
    BYTES_MAXIMOS: 3 * 1024 * 1024,
    FIRMA_VIGENTE_MS: 50 * 60000,
    FIRMAS_POR_PEDIDO: 60,
    DIAS_GUARDADO: 14,
    CODIGO_TOPE: 'ADJUNTO_TOPE',
    CODIGO_RECHAZO: 'ADJUNTO_RECHAZO',
    CODIGO_SIN_ARCHIVO: 'ADJUNTO_SIN_ARCHIVO',
  };

  const T = {
    ADJUNTAR: 'Mandar una foto',
    GRABAR: 'Grabar un audio',
    AYUDA_GRABAR: 'Mantené apretado para grabar. Con el teclado, Enter empieza y Enter lo manda.',
    MANDAR_AUDIO: 'Mandar el audio',
    DESLIZAR: 'Deslizá para cancelar',
    CANCELAR: 'Cancelar',
    QUEDAN_DIEZ: 'Te quedan 10 segundos',
    MUY_CORTO: 'Mantené apretado mientras hablás.',
    NO_SALIO: 'No salió.',
    REINTENTAR: 'Reintentar',
    BORRAR: 'Borrar',
    TOPE: 'Por hoy llegaste al máximo de fotos y audios. Probá mañana.',
    SIN_ARCHIVO: 'Este archivo ya no está en el teléfono.',
    NO_DISPONIBLE: 'Ya no está disponible.',
    NO_CARGA: 'No se pudo cargar. Tocá para probar de nuevo.',
    REPRODUCIR: 'Escuchar',
    PAUSAR: 'Pausar',
    CERRAR: 'Cerrar',
    FOTO: 'Foto',
    SIN_MICROFONO: 'Para mandarme audios, permití el micrófono en los ajustes del navegador.',
    SIN_GRABADOR: 'Este navegador no puede grabar audios. Probá desde la app.',
    FOTO_ILEGIBLE: 'Esa foto no se pudo abrir. Probá con otra.',
    NO_SE_ESCUCHA: 'Este audio no se puede escuchar en este navegador.',
  };

  function duracion(s) {
    const t = Number.isFinite(s) ? Math.max(0, Math.round(s)) : 0;
    return `${Math.floor(t / 60)}:${String(t % 60).padStart(2, '0')}`;
  }
  function duracionHablada(s) {
    const t = Number.isFinite(s) ? Math.max(0, Math.round(s)) : 0;
    const m = Math.floor(t / 60), r = t % 60;
    const seg = r === 1 ? '1 segundo' : `${r} segundos`;
    if (!m) return seg;
    const min = m === 1 ? '1 minuto' : `${m} minutos`;
    return r ? `${min} ${seg}` : min;
  }
  const textoAudio = (s) => `Audio de ${duracion(s || 0)}`;
  const textoAudioAccesible = (s) => `Audio de ${duracionHablada(s || 0)}`;
  function textoFallo(motivo) {
    if (motivo === R.CODIGO_TOPE) return T.TOPE;
    if (motivo === R.CODIGO_SIN_ARCHIVO) return T.SIN_ARCHIVO;
    return T.NO_SALIO;
  }
  const sePuedeReintentar = (motivo) => motivo !== R.CODIGO_SIN_ARCHIVO;

  /* POST /chat/adjunto → qué hace la cola. 403 es del token solo si el error lo dice (si no, es la palanca apagada). */
  function subida(status, ok, error) {
    if (status >= 200 && status < 300) return ok ? 'ok' : 'reintentar';
    const e = String(error || '').toLowerCase();
    if (status === 0 || status === 408 || status >= 500) return 'reintentar';
    if (status === 429) return 'tope';
    if (status === 409) return 'idRepetido';
    if ((status === 401 || status === 403) && e.includes('token')) return 'token';
    return 'rechazo';
  }

  /* El formato del grabador: m4a primero (lo escuchan el iPhone y Safari), si no webm/opus (Chrome, Firefox). */
  function mimeGrabacion(esSoportado) {
    for (const m of ['audio/mp4;codecs=mp4a.40.2', 'audio/mp4', 'audio/webm;codecs=opus', 'audio/webm', 'audio/ogg;codecs=opus']) {
      try { if (esSoportado(m)) return m; } catch (_) {}
    }
    return '';
  }

  /* Lo que mira el servidor: los primeros bytes. Un archivo que no es lo que dice no se encola. */
  function formatoDeBytes(b, tipo) {
    if (!b || b.length < 12) return null;
    if (tipo === 'foto') return b[0] === 0xff && b[1] === 0xd8 && b[2] === 0xff ? 'image/jpeg' : null;
    const s = (i, n) => String.fromCharCode(...b.slice(i, i + n));
    if (s(4, 4) === 'ftyp') return 'audio/mp4';
    if (b[0] === 0x1a && b[1] === 0x45 && b[2] === 0xdf && b[3] === 0xa3) return 'audio/webm';
    if (s(0, 4) === 'OggS') return 'audio/ogg';
    return null;
  }

  // Los textos de la pantalla (el test mira que no nombren nada interno).
  const TEXTOS = Object.values(T);

  // ── Almacén ──
  function almacenMemoria() {
    const cola = new Map(), archivos = new Map(), kv = new Map();
    return {
      persistente: false,
      async leerKV(k) { return kv.has(k) ? JSON.parse(kv.get(k)) : undefined; },
      async guardarKV(k, v) { kv.set(k, JSON.stringify(v)); },
      async agregar(meta, bytes) { cola.set(meta.id, { ...meta }); archivos.set(meta.id, bytes); },
      async actualizar(meta) { if (cola.has(meta.id)) cola.set(meta.id, { ...meta }); },
      async leerBytes(id) { return archivos.get(id) || null; },
      async sacar(id) { cola.delete(id); archivos.delete(id); },
      async listar() { return [...cola.values()].map((m) => ({ ...m })); },
    };
  }

  const DB = 'mypump-chat-adjuntos';
  const promesa = (req) => new Promise((ok, no) => { req.onsuccess = () => ok(req.result); req.onerror = () => no(req.error); });
  const fin = (tx) => new Promise((ok, no) => {
    tx.oncomplete = () => ok();
    tx.onerror = () => no(tx.error);
    tx.onabort = () => no(tx.error || new Error('transacción abortada'));
  });
  function abrirIDB(idb) {
    return new Promise((ok, no) => {
      let req;
      try { req = idb.open(DB, 1); } catch (e) { no(e); return; }
      const reloj = setTimeout(() => no(new Error('indexedDB no contestó')), 4000);
      req.onupgradeneeded = () => {
        const d = req.result;
        for (const [n, k] of [['cola', 'id'], ['archivos', 'id'], ['kv', 'k']]) if (!d.objectStoreNames.contains(n)) d.createObjectStore(n, { keyPath: k });
      };
      req.onsuccess = () => { clearTimeout(reloj); ok(req.result); };
      req.onerror = () => { clearTimeout(reloj); no(req.error); };
      req.onblocked = () => { clearTimeout(reloj); no(new Error('indexedDB bloqueada')); };
    });
  }
  async function almacenIDB(idb) {
    let d = await abrirIDB(idb);
    const con = async (fn) => {
      try { return await fn(d); } catch (e) {
        if (!e || e.name !== 'InvalidStateError') throw e;
        d = await abrirIDB(idb);
        return fn(d);
      }
    };
    return {
      persistente: true,
      leerKV: (k) => con(async (b) => { const r = await promesa(b.transaction('kv').objectStore('kv').get(k)); return r ? r.v : undefined; }),
      guardarKV: (k, v) => con(async (b) => { const t = b.transaction('kv', 'readwrite'); t.objectStore('kv').put({ k, v }); await fin(t); }),
      agregar: (meta, bytes) => con(async (b) => {
        const t = b.transaction(['cola', 'archivos'], 'readwrite');
        t.objectStore('archivos').put({ id: meta.id, bytes });
        t.objectStore('cola').put(meta);
        await fin(t);
      }),
      actualizar: (meta) => con(async (b) => { const t = b.transaction('cola', 'readwrite'); t.objectStore('cola').put(meta); await fin(t); }),
      leerBytes: (id) => con(async (b) => { const r = await promesa(b.transaction('archivos').objectStore('archivos').get(id)); return r ? r.bytes : null; }),
      sacar: (id) => con(async (b) => {
        const t = b.transaction(['cola', 'archivos'], 'readwrite');
        t.objectStore('archivos').delete(id);
        t.objectStore('cola').delete(id);
        await fin(t);
      }),
      listar: () => con((b) => promesa(b.transaction('cola').objectStore('cola').getAll())),
    };
  }
  async function abrirAlmacen(idb) {
    const fabrica = idb === undefined ? (typeof indexedDB !== 'undefined' ? indexedDB : null) : idb;
    if (fabrica) { try { return await almacenIDB(fabrica); } catch (_) {} }
    return almacenMemoria();
  }

  function uuid() {
    if (typeof crypto !== 'undefined' && crypto.randomUUID) return crypto.randomUUID();
    const b = crypto.getRandomValues(new Uint8Array(16));
    b[6] = (b[6] & 0x0f) | 0x40; b[8] = (b[8] & 0x3f) | 0x80;
    const h = Array.from(b, (x) => x.toString(16).padStart(2, '0')).join('');
    return `${h.slice(0, 8)}-${h.slice(8, 12)}-${h.slice(12, 16)}-${h.slice(16, 20)}-${h.slice(20)}`;
  }

  /* Hash corto del token para separar cuentas en un teléfono compartido (cyrb53). No es secreto ni autentica nada. */
  function cuentaDe(token) {
    let h1 = 0xdeadbeef, h2 = 0x41c6ce57;
    for (let i = 0; i < token.length; i++) {
      const c = token.charCodeAt(i);
      h1 = Math.imul(h1 ^ c, 2654435761);
      h2 = Math.imul(h2 ^ c, 1597334677);
    }
    h1 = Math.imul(h1 ^ (h1 >>> 16), 2246822507) ^ Math.imul(h2 ^ (h2 >>> 13), 3266489909);
    h2 = Math.imul(h2 ^ (h2 >>> 16), 2246822507) ^ Math.imul(h1 ^ (h1 >>> 13), 3266489909);
    return (4294967296 * (2097151 & h2) + (h1 >>> 0)).toString(36);
  }

  const ESPERAS_MS = [5000, 15000, 30000, 60000, 120000, 300000];
  const TIMEOUT_SUBIDA_MS = 120000;
  const TIMEOUT_FIRMA_MS = 20000;

  /* deps: { token, visionUrl, rpc(fn, params) → {ok,data}|{ok:false,clase}, fetch, almacen, ahora(), nuevoId(),
             programar(fn, ms) → cancelar, alCambiar() } */
  class ModeloChatAdjuntos {
    constructor(deps) {
      this.token = deps.token;
      this.visionUrl = (deps.visionUrl || '').replace(/\/+$/, '');
      this.rpc = deps.rpc;
      this.fetch = deps.fetch || ((...a) => fetch(...a));
      this.almacen = deps.almacen || almacenMemoria();
      this.ahora = deps.ahora || (() => Date.now());
      this.nuevoId = deps.nuevoId || uuid;
      this.programar = deps.programar || ((fn, ms) => { const t = setTimeout(fn, ms); return () => clearTimeout(t); });
      this.alCambiar = deps.alCambiar || (() => {});
      this.cuenta = cuentaDe(String(this.token || ''));
      this.activo = false;
      this.audioMaximo = R.AUDIO_MAXIMO;
      this.pendientes = new Map();   // id → { id, tipo, mime, segundos, creado, cuenta, fallo, motivo }
      this.confirmados = new Map();  // id → { comentarioId, createdAt } (para que el hilo lo cambie por la fila real)
      this.locales = new Map();      // id → Blob (lo que salió de este navegador: se ve sin pedir firma)
      this.firmas = new Map();       // id → { url, mime, vence }
      this.sinBajar = new Set();
      this.anuncio = null;           // { n, texto }
      this.drenando = false;
      this.intentosSeguidos = 0;
      this.cancelarEspera = null;
      this.pausadoPorToken = false;
    }

    avisar(texto) { this.anuncio = { n: ((this.anuncio && this.anuncio.n) || 0) + 1, texto }; this.alCambiar(); }

    /* palanca: true/false de mypump_app_config, o null sin saber (queda lo último que se supo). */
    async consultar(palanca) {
      const clave = `estado_${this.cuenta}`;
      if (palanca === false) return this._ponerEstado(false, null, clave);
      if (!this.visionUrl || !this.rpc) return this._ponerEstado(false, null, clave);
      const r = await this.rpc('mypump_chat_adjuntos_estado', { p_token: this.token });
      // El servidor ya mira la palanca y si el cliente está habilitado: manda lo que contesta.
      if (r && r.ok) {
        const d = r.data;
        const si = !!(d && typeof d === 'object' && d.habilitado === true);
        return this._ponerEstado(si, si ? d.audio_max_s : null, clave);
      }
      // Sin red o sin la función todavía: lo último que se supo; sin nada, apagado.
      if (r && r.clase === 'permanente') return this._ponerEstado(false, null, clave);
      const antes = await this.almacen.leerKV(clave).catch(() => undefined);
      this.activo = !!(antes && antes.habilitado);
      if (antes && Number.isFinite(antes.audio_max_s)) this.audioMaximo = Math.min(R.AUDIO_MAXIMO, antes.audio_max_s);
      this.alCambiar();
      return this.activo;
    }
    async _ponerEstado(habilitado, audioMax, clave) {
      this.activo = habilitado;
      this.audioMaximo = Number.isFinite(audioMax) && audioMax >= 10 ? Math.min(R.AUDIO_MAXIMO, audioMax) : R.AUDIO_MAXIMO;
      try { await this.almacen.guardarKV(clave, { habilitado, audio_max_s: this.audioMaximo }); } catch (_) {}
      this.alCambiar();
      return habilitado;
    }

    /* Lo que quedó de antes (la pestaña cerrada sin señal) vuelve como «enviando…» o «no salió». Lo viejo se borra. */
    async cargar() {
      let lista = [];
      try { lista = await this.almacen.listar(); } catch (_) {}
      const limite = this.ahora() - R.DIAS_GUARDADO * 86400000;
      for (const m of lista) {
        if (m.cuenta !== this.cuenta) continue;
        if (new Date(m.creado).getTime() < limite) { await this.almacen.sacar(m.id).catch(() => {}); continue; }
        this.pendientes.set(m.id, { ...m });
      }
      this.alCambiar();
      this.drenar();
    }

    /* bytes: Uint8Array ya listo (la foto reducida y sin metadatos; el audio grabado). */
    async encolar(tipo, bytes, segundos) {
      if (!this.activo) return null;
      if (tipo === 'audio' && !(Number.isFinite(segundos) && segundos >= R.AUDIO_MINIMO)) { this.avisar(T.MUY_CORTO); return null; }
      const mime = formatoDeBytes(bytes, tipo);
      if (!mime) { this.avisar(tipo === 'foto' ? T.FOTO_ILEGIBLE : T.NO_SALIO); return null; }
      if (bytes.length > R.BYTES_MAXIMOS) { this.avisar(tipo === 'foto' ? T.FOTO_ILEGIBLE : T.NO_SALIO); return null; }
      const id = String(this.nuevoId()).toLowerCase();
      const meta = {
        id, tipo, mime, cuenta: this.cuenta, creado: new Date(this.ahora()).toISOString(), fallo: false, motivo: null,
        segundos: tipo === 'audio' ? Math.round(Math.min(segundos, this.audioMaximo)) : null,
      };
      try { await this.almacen.agregar(meta, bytes); } catch (_) {
        // Sin lugar: igual sale con la pestaña abierta.
        this.almacen = almacenMemoria();
        await this.almacen.agregar(meta, bytes);
      }
      this.pendientes.set(id, meta);
      this.locales.set(id, new Blob([bytes], { type: mime }));
      this.alCambiar();
      this.drenar();
      return id;
    }

    async drenar() {
      if (this.drenando || this.pausadoPorToken) return;
      this.drenando = true;
      try {
        for (;;) {
          const m = [...this.pendientes.values()].find((x) => !x.fallo);
          if (!m) break;
          const r = await this._subir(m);
          if (r === 'esperar') { this._esperar(); break; }
          if (r === 'token') { this.pausadoPorToken = true; break; }
        }
      } finally { this.drenando = false; }
    }
    _esperar() {
      if (this.cancelarEspera) return;
      const ms = ESPERAS_MS[Math.min(this.intentosSeguidos, ESPERAS_MS.length - 1)];
      this.intentosSeguidos++;
      this.cancelarEspera = this.programar(() => { this.cancelarEspera = null; this.drenar(); }, ms);
    }
    /* Volvió la señal o la pestaña: se prueba ya. */
    despertar() {
      if (this.cancelarEspera) { this.cancelarEspera(); this.cancelarEspera = null; }
      this.intentosSeguidos = 0;
      this.drenar();
    }

    async _subir(m) {
      const bytes = await this.almacen.leerBytes(m.id).catch(() => null);
      if (!bytes) return this._fallar(m, R.CODIGO_SIN_ARCHIVO);
      const headers = { 'Content-Type': m.mime.split(';')[0], 'x-chat-token': this.token, 'x-chat-id': m.id, 'x-chat-tipo': m.tipo };
      if (m.tipo === 'audio') headers['x-chat-duracion'] = String(m.segundos);
      let status = 0, cuerpo = null;
      try {
        const ctl = typeof AbortController !== 'undefined' ? new AbortController() : null;
        const reloj = ctl ? setTimeout(() => ctl.abort(), TIMEOUT_SUBIDA_MS) : null;
        const cortar = () => { if (reloj) clearTimeout(reloj); };
        try {
          const res = await this.fetch(`${this.visionUrl}/chat/adjunto`, { method: 'POST', headers, body: bytes, signal: ctl ? ctl.signal : undefined });
          status = res.status;
          try { cuerpo = await res.json(); } catch (_) { cuerpo = null; }
        } finally { cortar(); }
      } catch (_) { status = 0; }
      const que = subida(status, !!(cuerpo && cuerpo.ok), cuerpo && cuerpo.error);
      switch (que) {
        case 'ok':
          this.intentosSeguidos = 0;
          await this.almacen.sacar(m.id).catch(() => {});
          this.pendientes.delete(m.id);
          this.confirmados.set(m.id, { comentarioId: cuerpo.comentario_id, createdAt: cuerpo.created_at, tipo: m.tipo, segundos: m.segundos });
          this.alCambiar();
          return 'ok';
        case 'reintentar': return 'esperar';
        case 'token': return 'token';
        case 'tope': {
          // Lo que sigue en la cola también chocaría con el tope: queda «no salió» sin mandar el archivo otra vez.
          this.avisar(T.TOPE);
          for (const o of [...this.pendientes.values()]) if (o.id !== m.id && !o.fallo) await this._fallar(o, R.CODIGO_TOPE);
          return this._fallar(m, R.CODIGO_TOPE);
        }
        case 'idRepetido': {
          // El id es de otro mensaje (casi imposible): sale con uno nuevo.
          const bytes2 = bytes;
          await this.almacen.sacar(m.id).catch(() => {});
          this.pendientes.delete(m.id);
          const blob = this.locales.get(m.id);
          this.locales.delete(m.id);
          const nuevo = { ...m, id: String(this.nuevoId()).toLowerCase() };
          await this.almacen.agregar(nuevo, bytes2);
          this.pendientes.set(nuevo.id, nuevo);
          if (blob) this.locales.set(nuevo.id, blob);
          this.alCambiar();
          return 'ok';
        }
        default: return this._fallar(m, R.CODIGO_RECHAZO);
      }
    }
    async _fallar(m, motivo) {
      const f = { ...m, fallo: true, motivo };
      this.pendientes.set(m.id, f);
      await this.almacen.actualizar(f).catch(() => {});
      this.alCambiar();
      return 'fallo';
    }

    async reintentar(id) {
      const m = this.pendientes.get(id);
      if (!m || !m.fallo || !sePuedeReintentar(m.motivo)) return;
      const f = { ...m, fallo: false, motivo: null };
      this.pendientes.set(id, f);
      await this.almacen.actualizar(f).catch(() => {});
      this.pausadoPorToken = false;
      this.alCambiar();
      this.despertar();
    }
    async descartar(id) {
      if (!this.pendientes.has(id)) return;
      this.pendientes.delete(id);
      this.locales.delete(id);
      await this.almacen.sacar(id).catch(() => {});
      this.alCambiar();
    }

    /* Las burbujas «enviando…»/«no salió» para el hilo (orden de creación). */
    burbujas() {
      return [...this.pendientes.values()].sort((a, b) => a.creado.localeCompare(b.creado)).map((m) => ({
        id: 'adj_' + m.id, autor: 'cliente', created_at: m.creado, _tmp: true, _fallo: m.fallo, _motivo: m.motivo,
        contenido: m.tipo === 'foto' ? T.FOTO : textoAudio(m.segundos),
        adjunto: { id: m.id, tipo: m.tipo, duracion_s: m.segundos, borrado: false },
      }));
    }

    // ── Ver y escuchar ──

    /* La URL para mostrar un adjunto: lo propio sin pedir nada; lo demás con una firma (de a muchos por pedido). */
    async url(id, idsVisibles) {
      let local = this.locales.get(id);
      // Lo que todavía espera en la cola (después de recargar): del archivo guardado, nunca del servidor.
      if (!local && this.pendientes.has(id)) {
        const p = this.pendientes.get(id);
        const bytes = await this.almacen.leerBytes(id).catch(() => null);
        if (!bytes) return null;
        local = new Blob([bytes], { type: p.mime });
        this.locales.set(id, local);
      }
      if (local) return (typeof URL !== 'undefined' && URL.createObjectURL) ? URL.createObjectURL(local) : null;
      const f = this.firmas.get(id);
      if (f && f.vence > this.ahora()) return f.url;
      await this.firmar([id, ...(idsVisibles || []).filter((x) => x !== id)]);
      const g = this.firmas.get(id);
      if (g) { this.sinBajar.delete(id); return g.url; }
      this.sinBajar.add(id);
      return null;
    }
    mime(id) {
      const l = this.locales.get(id);
      if (l) return l.type;
      const f = this.firmas.get(id);
      return f ? f.mime : null;
    }
    async firmar(ids) {
      const faltan = [...new Set(ids.map((x) => String(x).toLowerCase()))].filter((x) => {
        const f = this.firmas.get(x);
        return !this.locales.has(x) && !(f && f.vence > this.ahora());
      }).slice(0, R.FIRMAS_POR_PEDIDO);
      if (!faltan.length || !this.visionUrl) return;
      try {
        const ctl = typeof AbortController !== 'undefined' ? new AbortController() : null;
        const reloj = ctl ? setTimeout(() => ctl.abort(), TIMEOUT_FIRMA_MS) : null;
        const cortar = () => { if (reloj) clearTimeout(reloj); };
        try {
          const res = await this.fetch(`${this.visionUrl}/chat/urls`, {
            method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ token: this.token, ids: faltan }),
            signal: ctl ? ctl.signal : undefined,
          });
          const d = await res.json().catch(() => null);
          if (!res.ok || !d || !d.ok || !Array.isArray(d.adjuntos)) return;
          const vence = this.ahora() + R.FIRMA_VIGENTE_MS;
          for (const a of d.adjuntos) if (a && a.id && a.url) this.firmas.set(String(a.id).toLowerCase(), { url: a.url, mime: a.mime || null, vence });
        } finally { cortar(); }
      } catch (_) {}
    }
  }

  const api = {
    R, T, TEXTOS, duracion, duracionHablada, textoAudio, textoAudioAccesible, textoFallo, sePuedeReintentar, subida,
    mimeGrabacion, formatoDeBytes, almacenMemoria, abrirAlmacen, cuentaDe, ModeloChatAdjuntos,
  };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  else raiz.ChatAdjuntos = api;
})(typeof window !== 'undefined' ? window : globalThis);
