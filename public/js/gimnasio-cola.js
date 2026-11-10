/* =============================================================
   gimnasio-cola.js — «Gimnasio por fotos»: dónde esperan las fotos y la cola.

   Puerto de ModeloGimnasio.swift a la web, con el mismo criterio que la cola de
   fotos de progreso: 4xx es definitivo, 5xx, 429 y red no gastan la foto.

   Las fotos NO van a localStorage: 80 de 1600 px no entran. Van a IndexedDB como
   bytes (Safari ha perdido Blobs guardados ahí), en tres almacenes:
     cola   → una fila por foto: { id, cuenta, gimnasioId, zona, pregunta, creado, miniatura }
     fotos  → los bytes del JPEG, por id. Se escribe junto con `cola`, en la misma transacción.
     kv     → el borrador y el último estado (JSON, sin fotos).
   Una fila por foto: dos pestañas no se pisan un índice común, y un mismo
   x-gimnasio-foto en dos pasadas el servidor lo devuelve con ya:true, sin duplicar.
   El token no se guarda acá: la cuenta es un hash corto, solo para separar cuentas.
   Si IndexedDB no existe o no abre (Safari privado), queda en memoria: mientras la
   pestaña esté abierta funciona igual; al recargar, esas fotos no siguen.
   ============================================================= */
(function (raiz) {
  'use strict';

  const G = (typeof module !== 'undefined' && module.exports) ? require('./gimnasio.js') : raiz.Gimnasio;

  const DB = 'mypump-gimnasio';
  const VENCE_MS = 30 * 24 * 3600 * 1000;   // lo que nadie subió en 30 días no se guarda para siempre
  const MAX_INTENTOS_SEGUIDOS = 3;
  const MAX_REINTENTOS_FONDO = 5;
  const ESPERA_REINTENTO_MS = 60000;
  const ESPERA_LARGA_MS = 180000;
  const TIMEOUT_SUBIDA_MS = 150000;
  const TIMEOUT_VISION_MS = 30000;

  // ── Almacén en memoria: fallback y pruebas ──
  function almacenMemoria() {
    const cola = new Map(), fotos = new Map(), kv = new Map();
    return {
      persistente: false,
      async leerKV(k) { return kv.has(k) ? JSON.parse(kv.get(k)) : undefined; },
      async guardarKV(k, v) { kv.set(k, JSON.stringify(v)); },
      async borrarKV(k) { kv.delete(k); },
      async agregarFoto(meta, bytes) { cola.set(meta.id, { ...meta }); fotos.set(meta.id, bytes); },
      async leerBytes(id) { return fotos.get(id) || null; },
      async sacarFoto(id) { cola.delete(id); fotos.delete(id); },
      async listar() { return [...cola.values()].map((m) => ({ ...m })); },
    };
  }

  // ── Almacén en IndexedDB ──
  function promesa(req) {
    return new Promise((ok, no) => { req.onsuccess = () => ok(req.result); req.onerror = () => no(req.error); });
  }
  function fin(tx) {
    return new Promise((ok, no) => {
      tx.oncomplete = () => ok();
      tx.onerror = () => no(tx.error);
      tx.onabort = () => no(tx.error || new Error('transacción abortada'));
    });
  }
  function abrirIDB(idb) {
    return new Promise((ok, no) => {
      let req;
      try { req = idb.open(DB, 1); } catch (e) { no(e); return; }
      // Hay Safaris en los que open no contesta nunca: mejor memoria que una pantalla colgada.
      const reloj = setTimeout(() => no(new Error('indexedDB no contestó')), 4000);
      req.onupgradeneeded = () => {
        const d = req.result;
        if (!d.objectStoreNames.contains('cola')) d.createObjectStore('cola', { keyPath: 'id' });
        if (!d.objectStoreNames.contains('fotos')) d.createObjectStore('fotos', { keyPath: 'id' });
        if (!d.objectStoreNames.contains('kv')) d.createObjectStore('kv', { keyPath: 'k' });
      };
      req.onsuccess = () => { clearTimeout(reloj); ok(req.result); };
      req.onerror = () => { clearTimeout(reloj); no(req.error); };
      req.onblocked = () => { clearTimeout(reloj); no(new Error('indexedDB bloqueada')); };
    });
  }
  async function almacenIDB(idb) {
    let d = await abrirIDB(idb);
    const vigilar = () => { d.onversionchange = () => { try { d.close(); } catch (_) {} }; };
    vigilar();
    // iOS puede cerrar la conexión mientras la pestaña está de fondo (por ejemplo, al ir a la cámara): se reabre una vez.
    const con = async (fn) => {
      try { return await fn(d); } catch (e) {
        if (!e || e.name !== 'InvalidStateError') throw e;
        d = await abrirIDB(idb);
        vigilar();
        return fn(d);
      }
    };
    return {
      persistente: true,
      leerKV: (k) => con(async (b) => { const r = await promesa(b.transaction('kv').objectStore('kv').get(k)); return r ? r.v : undefined; }),
      guardarKV: (k, v) => con(async (b) => { const t = b.transaction('kv', 'readwrite'); t.objectStore('kv').put({ k, v }); await fin(t); }),
      borrarKV: (k) => con(async (b) => { const t = b.transaction('kv', 'readwrite'); t.objectStore('kv').delete(k); await fin(t); }),
      agregarFoto: (meta, bytes) => con(async (b) => {
        const t = b.transaction(['cola', 'fotos'], 'readwrite');
        t.objectStore('fotos').put({ id: meta.id, bytes });
        t.objectStore('cola').put(meta);
        await fin(t);
      }),
      leerBytes: (id) => con(async (b) => { const r = await promesa(b.transaction('fotos').objectStore('fotos').get(id)); return r ? r.bytes : null; }),
      sacarFoto: (id) => con(async (b) => {
        const t = b.transaction(['cola', 'fotos'], 'readwrite');
        t.objectStore('fotos').delete(id);
        t.objectStore('cola').delete(id);
        await fin(t);
      }),
      listar: () => con((b) => promesa(b.transaction('cola').objectStore('cola').getAll())),
    };
  }
  /* IndexedDB si se puede; si no, memoria. Nunca falla. */
  async function abrirAlmacen(idb) {
    const fabrica = idb === undefined ? (typeof indexedDB !== 'undefined' ? indexedDB : null) : idb;
    if (fabrica) { try { return await almacenIDB(fabrica); } catch (_) {} }
    return almacenMemoria();
  }

  /* Hash corto y estable del token (cyrb53): separa cuentas en un teléfono compartido. No es secreto ni autentica nada. */
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

  function uuid() {
    if (typeof crypto !== 'undefined' && crypto.randomUUID) return crypto.randomUUID();
    const b = crypto.getRandomValues(new Uint8Array(16));
    b[6] = (b[6] & 0x0f) | 0x40; b[8] = (b[8] & 0x3f) | 0x80;
    const h = Array.from(b, (x) => x.toString(16).padStart(2, '0')).join('');
    return `${h.slice(0, 8)}-${h.slice(8, 12)}-${h.slice(12, 16)}-${h.slice(16, 20)}-${h.slice(20)}`;
  }

  /* deps: { rpc(fn, params) → {ok:true,data} | {ok:false,status,codigo,clase:'red'|'transitorio'|'permanente'},
             almacen, token, visionUrl, fetch, esperar(ms), ahora(), nuevoId() } */
  class ModeloGimnasio {
    constructor(deps) {
      this.rpc = deps.rpc;
      this.almacen = deps.almacen;
      this.token = deps.token;
      this.visionUrl = String(deps.visionUrl || '').replace(/\/$/, '');
      this.fetch = deps.fetch || ((...a) => fetch(...a));
      this.esperar = deps.esperar || ((ms) => new Promise((r) => setTimeout(r, ms)));
      this.ahora = deps.ahora || (() => Date.now());
      this.nuevoId = deps.nuevoId || uuid;
      this.conLock = deps.conLock || ((fn) => fn());
      this.visible = deps.visible || (() => typeof document === 'undefined' || document.visibilityState === 'visible');
      this.cuenta = cuentaDe(this.token);

      this.estado = null;           // null: apagado, sin el servidor nuevo o sin red la primera vez
      this.cola = [];
      this.subiendo = null;
      this.urls = {};
      this.miniaturas = {};         // las de esta visita, para no pedir firmas de lo que acaba de subir
      this.avisoFoto = null;
      this.avisoEnvio = null;
      this.subidasEnvio = 0;
      this.totalEnvio = 0;
      this.borrador = this._borradorVacio();

      this.alCambiar = () => {};
      this._drenando = false;
      this._conError = new Set();
      this._borrarAlSubir = new Set();
      this._urlsVencen = 0;
      this._reintentoProgramado = false;
      this._reintentosDeFondo = 0;
      this._mandandoEnvio = false;
      this._otraPasada = false;
      this._lecturas = new Set();
      this._gets = new Set();
      this._guardado = Promise.resolve();
      this._mutaciones = 0;
      this.preparando = 0;          // fotos elegidas que todavía se están reduciendo: el envío las espera
    }

    _borradorVacio() { return { gimnasioId: null, noHay: [], nota: '', quitar: [], respuestas: {}, avisoVersion: null, envio: null, borrarPendientes: [] }; }
    get _kvBorrador() { return `borrador:${this.cuenta}`; }
    get _kvEstado() { return `estado:${this.cuenta}`; }
    _avisar() { try { this.alCambiar(); } catch (_) {} }

    /* Lee lo que quedó guardado. Va una sola vez, antes de refrescar. */
    async cargar() {
      try {
        const b = await this.almacen.leerKV(this._kvBorrador);
        if (b) this.borrador = { ...this._borradorVacio(), ...b };
      } catch (_) {}
      await this._releerCola(true);
    }

    async _releerCola(purgar) {
      let filas = [];
      // Lo que se agregue o se saque mientras viaja la lectura manda sobre lo leído: si no, una foto recién guardada
      // desaparece un momento y el envío podría salir sin ella.
      const durante = { mas: new Set(), menos: new Set() };
      this._lecturas.add(durante);
      try { filas = await this.almacen.listar(); } catch (_) { return; } finally { this._lecturas.delete(durante); }
      const leidas = new Set(filas.map((f) => f.id));
      filas = filas.filter((f) => !durante.menos.has(f.id)).concat(this.cola.filter((c) => durante.mas.has(c.id) && !leidas.has(c.id)));
      if (purgar) {
        const limite = this.ahora() - VENCE_MS;
        for (const f of filas.filter((x) => (x.creado || 0) < limite)) { try { await this.almacen.sacarFoto(f.id); } catch (_) {} }
        filas = filas.filter((x) => (x.creado || 0) >= limite);
      }
      // Las de esta cuenta, y las de otro link de la misma persona: esas llevan la carga abierta.
      const abiertaId = this.abierta && this.abierta.id;
      this.cola = filas.filter((f) => f.cuenta === this.cuenta || (abiertaId && f.gimnasioId === abiertaId))
        .sort((a, b) => (a.creado || 0) - (b.creado || 0));
      for (const f of this.cola) if (f.miniatura) this.miniaturas[f.id] = f.miniatura;
    }

    // ── Lo que lee la pantalla ──
    get abierta() { return this.estado ? this.estado.abierta : null; }
    get vigente() { return this.estado ? this.estado.vigente : null; }
    get envio() { return this.borrador.envio; }
    get nota() { return this.borrador.nota; }
    get noHay() { return new Set(this.borrador.noHay); }
    get quitar() { return new Set(this.borrador.quitar); }
    get respuestas() { return this.borrador.respuestas; }
    get tarjetaVisible() { return G.tarjetaVisible(!!this.estado, this.abierta && this.abierta.estado, !!this.vigente); }
    get entradaVisible() { return G.entradaVisible(!!this.estado, !!this.vigente); }
    get pantalla() { return G.pantalla(this.abierta ? this.abierta.estado : null, !!this.vigente); }
    get necesitaAviso() {
      const e = this.estado;
      return !!e && !e.consentimientoAceptado && this.borrador.avisoVersion !== e.consentimientoVersion;
    }
    get _colaDeLaCarga() {
      const a = this.abierta;
      if (!a) return [];
      const enServidor = new Set(a.fotos.map((f) => f.id));
      return this.cola.filter((c) => c.gimnasioId === a.id && !enServidor.has(c.id));
    }
    get zonasConFotos() {
      const a = this.abierta;
      return new Set([...(a ? a.fotos.map((f) => f.zona) : []), ...this._colaDeLaCarga.map((c) => c.zona)]);
    }
    get faltantes() { const a = this.abierta; return a ? G.zonasFaltantes(this.zonasConFotos, this.noHay, a.modo) : []; }
    get puedeEnviar() { const a = this.abierta; return !!a && G.puedeEnviar(a.modo, this.zonasConFotos, this.noHay, this.quitar); }
    get puedeAgregar() { return G.puedeAgregar(this.abierta ? this.abierta.fotos.length : 0, this._colaDeLaCarga.length); }
    get totalFotos() { return (this.abierta ? this.abierta.fotos.length : 0) + this._colaDeLaCarga.length; }

    fotos(zona) {
      const a = this.abierta;
      const enServidor = (a ? a.fotos : []).filter((f) => f.zona === zona)
        .map((f) => ({ id: f.id, local: false, subiendo: false, esperando: false, miniatura: this.miniaturas[f.id] || null }));
      const aqui = this._colaDeLaCarga.filter((c) => c.zona === zona).map((c) => ({
        id: c.id, local: true, subiendo: this.subiendo === c.id, esperando: this.subiendo !== c.id, miniatura: c.miniatura || null,
      }));
      return [...enServidor, ...aqui];
    }

    // ── Servidor ──
    /* Sin el servidor nuevo o apagado para esta cuenta: nada. Sin red: lo último que se supo, solo para seguir una carga a medio hacer. */
    async refrescar(previa) {
      const durante = [];
      this._gets.add(durante);
      let r;
      try { r = previa || await this.rpc('mypump_gimnasio_get', { p_token: this.token }); } finally { this._gets.delete(durante); }
      if (r.ok) {
        if (r.data === null || r.data === undefined) { this.estado = null; this._avisar(); return; }
        const e = G.decodificarEstado(r.data);
        if (!e) { this.apagar(); this._olvidarEstado(); this._avisar(); return; }
        // Lo que terminó de subir mientras viajaba este `get` no está en su foto del servidor y ya salió de la cola.
        if (e.abierta) for (const f of durante) if (f.gimnasioId === e.abierta.id && !e.abierta.fotos.some((x) => x.id === f.foto.id)) e.abierta.fotos.push(f.foto);
        await this._aplicar(e);
        try { await this.almacen.guardarKV(this._kvEstado, r.data); } catch (_) {}
        await this._releerCola(false);
      } else if (r.status === 404 || r.codigo === 'PGRST202' || r.clase === 'permanente') {
        this.apagar();
        this._olvidarEstado();
      } else if (!this.estado) {
        let j;
        try { j = await this.almacen.leerKV(this._kvEstado); } catch (_) {}
        const e = j ? G.decodificarEstado(j) : null;
        if (e && e.abierta && (e.abierta.estado === 'borrador' || e.abierta.estado === 'a_confirmar')) {
          await this._aplicar(e);
          await this._releerCola(false);
        }
      }
      this._avisar();
    }

    _olvidarEstado() { this.almacen.borrarKV(this._kvEstado).catch(() => {}); }
    apagar() { this.estado = null; }

    async _aplicar(e) {
      this.estado = e;
      let b = this.borrador;
      const antes = JSON.stringify(b);
      const id = e.abierta ? e.abierta.id : null;
      if (b.gimnasioId !== id) {
        b = { ...this._borradorVacio(), gimnasioId: id, avisoVersion: b.avisoVersion, envio: b.envio && b.envio.gimnasioId === id ? b.envio : null, borrarPendientes: id ? b.borrarPendientes : [] };
      }
      // Lo que el servidor ya tomó deja de estar pendiente (un reintento devuelve `ya`).
      if (b.envio && e.abierta && ((b.envio.tipo === 'enviar' && e.abierta.estado !== 'borrador') || (b.envio.tipo === 'responder' && e.abierta.estado !== 'a_confirmar'))) {
        b = { ...b, envio: null };
      }
      this.borrador = b;
      // Lo que el alumno borró y todavía no se pudo sacar del servidor no vuelve a aparecer.
      if (e.abierta && b.borrarPendientes.length) e.abierta.fotos = e.abierta.fotos.filter((f) => !b.borrarPendientes.includes(f.id));
      if (JSON.stringify(b) !== antes) await this._guardarBorrador();
    }

    /* En fila: dos escrituras seguidas no se pueden pisar al revés. */
    _guardarBorrador() {
      this._mutaciones += 1;
      const copia = JSON.parse(JSON.stringify(this.borrador));
      this._guardado = this._guardado.then(() => this.almacen.guardarKV(this._kvBorrador, copia)).catch(() => {});
      return this._guardado;
    }

    /* Con el lock de las pestañas tomado: lo que hizo otra (cancelar, nota, fotos nuevas) manda sobre lo que esta tenía en memoria. */
    async _sincronizar() {
      const antes = this._mutaciones;
      await this._guardado;
      let b;
      try { b = await this.almacen.leerKV(this._kvBorrador); } catch (_) {}
      if (b && antes === this._mutaciones) this.borrador = { ...this._borradorVacio(), ...b };
      await this._releerCola(false);
    }

    /* → 'ok' | 'sinSenal' | 'error' | 'tokenCaido'. `parcial` sin gimnasio vigente cae a la completa. */
    async empezar(modo = 'completa') { return this._nuevo(modo, 1); }

    async aceptarAviso() {
      if (!this.estado) return;
      this.borrador.avisoVersion = this.estado.consentimientoVersion;
      await this._guardarBorrador();
    }

    async _nuevo(modo, reintentos) {
      const r = await this.rpc('mypump_gimnasio_nuevo', { p_token: this.token, p_modo: modo });
      if (!r.ok) return r.clase === 'permanente' ? 'error' : 'sinSenal';
      if (r.data === null || r.data === undefined) return 'tokenCaido';
      if (r.data.ok === true) { await this.refrescar(); return 'ok'; }
      switch (r.data.error) {
        case 'sin_gimnasio_vigente': return this._nuevo('completa', reintentos);
        case 'no_habilitado': this.apagar(); this._avisar(); return 'error';
        case 'reintentar': return reintentos > 0 ? this._nuevo(modo, reintentos - 1) : 'error';
        default: return 'error';
      }
    }

    // ── Fotos ──
    /* Encola un JPEG ya preparado (1600 px, 0,8, sin EXIF). → 'guardada' | 'tope' | 'noSeGuardo'. Después hay que drenar. */
    async agregar(zona, foto, pregunta = null) {
      const a = this.abierta;
      if (!a) return 'noSeGuardo';
      // Las de una pregunta tienen su propio cupo en el servidor: el tope de 80 es el de la carga.
      if (!pregunta && !this.puedeAgregar) { this.avisoFoto = 'tope'; this._avisar(); return 'tope'; }
      const meta = { id: String(this.nuevoId()).toLowerCase(), cuenta: this.cuenta, gimnasioId: a.id, zona, pregunta, creado: this.ahora(), miniatura: foto.miniatura || null };
      try { await this.almacen.agregarFoto(meta, foto.bytes); } catch (_) { return 'noSeGuardo'; }
      this.cola.push(meta);
      for (const l of this._lecturas) l.mas.add(meta.id);
      if (meta.miniatura) this.miniaturas[meta.id] = meta.miniatura;
      this.avisoFoto = null;
      if (this.noHay.has(zona) || pregunta) {
        this.borrador.noHay = this.borrador.noHay.filter((z) => z !== zona);
        if (pregunta) this.borrador.respuestas[pregunta] = 'subida';
        await this._guardarBorrador();
      }
      this._avisar();
      return 'guardada';
    }

    drenarEnFondo() { this.drenar().catch(() => {}); }

    /* → 'ok' | 'sinSenal' | 'error' */
    async borrarFoto(id) {
      if (this.subiendo === id) { this._borrarAlSubir.add(id); await this._sacarDeLaCola(id); this._avisar(); return 'ok'; }
      if (this.cola.some((c) => c.id === id)) { await this._sacarDeLaCola(id); this._avisar(); return 'ok'; }
      const r = await this._postVision('gimnasio/borrar', { token: this.token, foto_id: id });
      if (!r) return 'sinSenal';
      if (r.status === 409 || r.status < 200 || r.status >= 300 || !r.json || r.json.ok !== true) { await this.refrescar(); return 'error'; }
      this._quitarDeLaCarga(id);
      this._avisar();
      return 'ok';
    }

    _quitarDeLaCarga(id) {
      const a = this.abierta;
      if (a) a.fotos = a.fotos.filter((f) => f.id !== id);
    }

    /* La que se borró mientras subía: si el pedido no sale se reintenta, y la carga no se manda hasta resolverlo. */
    async _anotarBorrado(id) {
      if (!this.borrador.borrarPendientes.includes(id)) this.borrador.borrarPendientes = [...this.borrador.borrarPendientes, id];
      this._quitarDeLaCarga(id);
      await this._guardarBorrador();
    }

    /* true: no queda ninguno pendiente. */
    async _resolverBorrados() {
      for (const id of [...this.borrador.borrarPendientes]) {
        const r = await this._postVision('gimnasio/borrar', { token: this.token, foto_id: id });
        if (!r || r.status === 429 || r.status >= 500) return false;     // red o falla nuestra: sigue pendiente
        this.borrador.borrarPendientes = this.borrador.borrarPendientes.filter((x) => x !== id);
        await this._guardarBorrador();
      }
      return true;
    }

    _sacarDeMemoria(id) {
      this.cola = this.cola.filter((c) => c.id !== id);
      for (const l of this._lecturas) l.menos.add(id);
    }

    async _sacarDeLaCola(id) {
      const quitada = this.cola.find((c) => c.id === id);
      this._sacarDeMemoria(id);
      try { await this.almacen.sacarFoto(id); } catch (_) {}
      if (quitada && quitada.pregunta && !this.cola.some((c) => c.pregunta === quitada.pregunta) && this.borrador.respuestas[quitada.pregunta] != null) {
        delete this.borrador.respuestas[quitada.pregunta];
        await this._guardarBorrador();
      }
    }

    marcarNoHay(zona, no) {
      const s = this.noHay;
      if (no) s.add(zona); else s.delete(zona);
      this.borrador.noHay = G.ZONAS.map((z) => z.clave).filter((c) => s.has(c));
      this._guardarBorrador();
      this._avisar();
    }
    fijarNota(s) {
      const n = G.notaRecortada(s);
      if (n === this.borrador.nota) return;
      this.borrador.nota = n;
      this._guardarBorrador();
    }
    alternarQuitar(tipo) {
      const q = this.borrador.quitar;
      this.borrador.quitar = q.includes(tipo) ? q.filter((t) => t !== tipo) : [...q, tipo];
      this._guardarBorrador();
      this._avisar();
    }
    responder(id, valor) {
      if (valor === null || valor === undefined) delete this.borrador.respuestas[id]; else this.borrador.respuestas[id] = valor;
      this._guardarBorrador();
      this._avisar();
    }
    limpiarAvisoFoto() { this.avisoFoto = null; }

    /* La pantalla avisa cuántas fotos elegidas se están reduciendo: al terminar, sale lo que estaba esperando. */
    empezarPreparacion() { this.preparando += 1; }
    terminarPreparacion() { this.preparando = Math.max(0, this.preparando - 1); if (!this.preparando) this.drenarEnFondo(); }

    /* Lo llaman el `online`, volver a la pestaña y el arranque: un corte largo no agota los reintentos para siempre. */
    reanudar() { this._reintentosDeFondo = 0; this.drenarEnFondo(); }

    // ── Cola ──
    /* Una pasada a la vez. Red: corta y espera. 5xx o 429: espera y reintenta, y a la tercera seguida deja esa foto para el
       final y corta la pasada. Todo 4xx es definitivo. Al vaciarse la cola de la carga sale lo que el alumno haya mandado. */
    async drenar() {
      if (!this.estado) return;
      if (this._drenando) { this._otraPasada = true; return; }   // la foto que llegó justo al terminar no espera al próximo evento
      this._drenando = true;
      try {
        do {
          this._otraPasada = false;
          await this.conLock(() => this._pasada());
        } while (this._otraPasada && this.estado && (this.borrador.envio || this.cola.some((c) => !this._conError.has(c.id))));
      } finally {
        this._drenando = false;
        this._avisar();
      }
    }

    _siguiente() {
      const vivos = this.cola.filter((c) => !this._borrarAlSubir.has(c.id));
      return vivos.find((c) => !this._conError.has(c.id)) || vivos[0] || null;
    }

    async _pasada() {
      await this._sincronizar();
      let cortada = false;
      let refrescarAlFinal = false;
      let seguidas = 0;
      let item;
      while ((item = this._siguiente())) {
        this.subiendo = item.id;
        this._avisar();
        const r = await this._subir(item);
        this.subiendo = null;
        if (this._borrarAlSubir.has(item.id) && (r.tipo === 'red' || r.tipo === 'reintentar')) {
          // Pudo haber llegado aunque no se sepa: se pide sacarla igual.
          this._borrarAlSubir.delete(item.id);
          await this._anotarBorrado(item.id);
          this._avisar();
          if (r.tipo === 'red') { this._programarReintento(); cortada = true; break; }
          continue;
        }
        if (r.tipo === 'ok') {
          await this._sacarSubida(item);
          seguidas = 0;
          this._reintentosDeFondo = 0;
          this.subidasEnvio += 1;
        } else if (r.tipo === 'perdida') {
          await this._sacarDeLaCola(item.id);
        } else if (r.tipo === 'descartar') {
          refrescarAlFinal = refrescarAlFinal || !!r.s.refrescar;
          if (r.s.aviso) this.avisoFoto = r.s.aviso;
          await this._descartar(item);
        } else if (r.tipo === 'reintentar') {
          this._conError.add(item.id);
          seguidas += 1;
          if (seguidas >= MAX_INTENTOS_SEGUIDOS) { this._programarReintento(); cortada = true; break; }
          this._avisar();
          await this.esperar(Math.pow(2, seguidas) * 1000);
        } else {      // red: en la web no hay quién avise si fue un corte de un momento
          this._programarReintento();
          cortada = true;
          break;
        }
        this._avisar();
      }
      this._borrarAlSubir.clear();
      if (refrescarAlFinal) await this.refrescar();
      await this._sincronizar();
      // Apareció algo mientras tanto (otra pestaña, una foto recién guardada): primero eso.
      if (!cortada && this._siguiente() && this.cola.some((c) => !this._conError.has(c.id))) { this._otraPasada = true; return; }
      if (this.borrador.borrarPendientes.length && !(await this._resolverBorrados())) { this._programarReintento(); return; }
      await this._mandarEnvio();
    }

    /* Mientras la pestaña esté a la vista y quede algo por salir no se abandona: con señal mala o un wifi sin internet el
       navegador nunca avisa `online`. Pasados los primeros intentos, más espaciado. */
    _programarReintento() {
      if (this._reintentoProgramado) return;
      const quedaAlgo = this.cola.length > 0 || !!this.borrador.envio || this.borrador.borrarPendientes.length > 0;
      const agotado = this._reintentosDeFondo >= MAX_REINTENTOS_FONDO;
      if (agotado && !(quedaAlgo && this.visible())) return;
      this._reintentoProgramado = true;
      this._reintentosDeFondo += 1;
      this.esperar(agotado ? ESPERA_LARGA_MS : ESPERA_REINTENTO_MS).then(() => { this._reintentoProgramado = false; return this.drenar(); }).catch(() => {});
    }

    async _subir(p) {
      let bytes = null;
      try { bytes = await this.almacen.leerBytes(p.id); } catch (_) { return { tipo: 'red' }; }
      if (!bytes) return { tipo: 'perdida' };
      const ctrl = typeof AbortController !== 'undefined' ? new AbortController() : null;
      const reloj = ctrl ? setTimeout(() => ctrl.abort(), TIMEOUT_SUBIDA_MS) : null;
      try {
        const res = await this.fetch(`${this.visionUrl}/gimnasio/upload`, {
          method: 'POST',
          headers: { 'Content-Type': 'image/jpeg', 'x-gimnasio-token': this.token, 'x-gimnasio-id': p.gimnasioId, 'x-gimnasio-foto': p.id, 'x-gimnasio-zona': p.zona },
          body: typeof Blob !== 'undefined' ? new Blob([bytes], { type: 'image/jpeg' }) : bytes,
          cache: 'no-store',
          signal: ctrl ? ctrl.signal : undefined,
        });
        let j = null;
        try { j = await res.json(); } catch (_) {}
        const s = G.clasificarSubida(res.status, !!j && j.ok === true);
        if (s.accion === 'ok') return { tipo: 'ok' };
        if (s.accion === 'descartar') return { tipo: 'descartar', s };
        return { tipo: 'reintentar' };
      } catch (_) {
        return { tipo: 'red' };
      } finally {
        if (reloj) clearTimeout(reloj);
      }
    }

    /* Subió bien. Si la borraron mientras subía se saca también del servidor. */
    async _sacarSubida(item) {
      this._conError.delete(item.id);
      this._sacarDeMemoria(item.id);
      try { await this.almacen.sacarFoto(item.id); } catch (_) {}
      if (this._borrarAlSubir.delete(item.id)) {
        await this._anotarBorrado(item.id);     // sale antes del envío, con reintento (_resolverBorrados)
        return;
      }
      const a = this.abierta;
      const subida = { id: item.id, zona: item.zona, ronda: a && a.estado === 'borrador' ? 0 : 1 };
      for (const g of this._gets) g.push({ gimnasioId: item.gimnasioId, foto: subida });
      if (a && item.gimnasioId === a.id && !a.fotos.some((f) => f.id === item.id)) {
        a.fotos.push(subida);
        this._urlsVencen = 0;
      }
    }

    /* No va a entrar nunca. Si era para una pregunta, se le pide que la saque de nuevo. */
    async _descartar(item) {
      await this._sacarDeLaCola(item.id);
      this._conError.delete(item.id);
      if (item.pregunta && this.borrador.envio && this.borrador.envio.tipo === 'responder') {
        this.borrador.envio = null;
        await this._guardarBorrador();
      }
    }

    // ── Enviar ──
    /* «Enviar a Mati»: queda anotado y sale al vaciarse la cola; si no hay red, cuando vuelva. */
    async enviarCarga() {
      const a = this.abierta, e = this.estado;
      if (!a || !e) return;
      if (this.necesitaAviso) { this.avisoEnvio = 'sinConsentimiento'; this._avisar(); return; }
      this.avisoEnvio = null;
      this.totalEnvio = this.totalFotos;
      this.subidasEnvio = a.fotos.length;
      this.borrador.envio = {
        tipo: 'enviar', gimnasioId: a.id, noHay: this.borrador.noHay, nota: this.borrador.nota,
        consentimiento: e.consentimientoVersion, quitar: a.modo === 'parcial' ? this.borrador.quitar : [],
      };
      await this._guardarBorrador();
      this._avisar();
      this._reintentosDeFondo = 0;
      await this.drenar();
    }

    async enviarRespuestas() {
      const a = this.abierta;
      if (!a) return;
      this.avisoEnvio = null;
      this.borrador.envio = { tipo: 'responder', gimnasioId: a.id };
      await this._guardarBorrador();
      this._avisar();
      this._reintentosDeFondo = 0;
      await this.drenar();
    }

    /* Volver a editar: lo que estaba en la cola sigue subiendo, pero la carga no se manda hasta que la vuelva a enviar. */
    async cancelarEnvio() {
      this.borrador.envio = null;
      await this._guardarBorrador();
      this._avisar();
    }

    async _mandarEnvio() {
      const e = this.borrador.envio;
      if (!e || this._mandandoEnvio || this.preparando > 0 || this.cola.some((c) => c.gimnasioId === e.gimnasioId)) return;
      this._mandandoEnvio = true;
      try {
        let r;
        if (e.tipo === 'enviar') {
          r = await this.rpc('mypump_gimnasio_enviar', { p_token: this.token, p_id: e.gimnasioId, p_no_hay: e.noHay, p_nota: e.nota, p_consentimiento: e.consentimiento, p_quitar: e.quitar });
        } else {
          const preguntas = this.abierta ? this.abierta.preguntas : [];
          r = await this.rpc('mypump_gimnasio_responder', { p_token: this.token, p_id: e.gimnasioId, p_respuestas: G.respuestasParaEnviar(preguntas, this.borrador.respuestas) });
        }
        if (!r.ok) {
          if (r.clase === 'permanente') {      // 22023: error de programación, no se reintenta
            this.borrador.envio = null;
            await this._guardarBorrador();
            this.avisoEnvio = 'error';
          } else {
            this._programarReintento();
          }
          return;
        }
        if (r.data === null || r.data === undefined) return;      // token caído: queda guardado para el link nuevo
        const j = r.data;
        this.borrador.envio = null;
        if (j.ok === true) {
          if (e.tipo === 'responder') this.borrador.respuestas = {};
          await this._guardarBorrador();
          await this.refrescar();
          return;
        }
        await this._guardarBorrador();
        switch (j.error) {
          case 'faltan_zonas': this.avisoEnvio = { faltan: Array.isArray(j.faltan) ? j.faltan.filter((z) => typeof z === 'string') : [] }; break;
          case 'sin_consentimiento':
            this.borrador.avisoVersion = null;
            await this._guardarBorrador();
            this.avisoEnvio = 'sinConsentimiento';
            await this.refrescar();
            break;
          case 'sin_novedad': this.avisoEnvio = 'sinNovedad'; break;
          case 'no_encontrado':
          case 'estado_invalido': await this.refrescar(); break;
          case 'no_habilitado': this.apagar(); break;
          default: this.avisoEnvio = 'error';
        }
      } finally {
        this._mandandoEnvio = false;
        this._avisar();
      }
    }

    // ── Miniaturas: URLs firmadas de 1 h; se piden de nuevo a los 50 min o si aparece una que no estaba ──
    async firmar(gimnasioId, ids, forzar = false) {
      const falta = ids.some((id) => !this.urls[id]);
      if (!forzar && !falta && this._urlsVencen > this.ahora()) return;
      const r = await this._postVision('gimnasio/urls', { token: this.token, gimnasio_id: gimnasioId });
      if (!r || !r.json || r.json.ok !== true || !Array.isArray(r.json.fotos)) return;
      const mapa = { ...this.urls };
      for (const f of r.json.fotos) if (f && typeof f.id === 'string' && typeof f.url === 'string') mapa[f.id] = f.url;
      this.urls = mapa;
      this._urlsVencen = this.ahora() + 50 * 60 * 1000;
      this._avisar();
    }

    async _postVision(ruta, cuerpo) {
      const ctrl = typeof AbortController !== 'undefined' ? new AbortController() : null;
      const reloj = ctrl ? setTimeout(() => ctrl.abort(), TIMEOUT_VISION_MS) : null;
      try {
        const res = await this.fetch(`${this.visionUrl}/${ruta}`, {
          method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(cuerpo), cache: 'no-store', signal: ctrl ? ctrl.signal : undefined,
        });
        let json = null;
        try { json = await res.json(); } catch (_) {}
        return { status: res.status, json };
      } catch (_) {
        return null;
      } finally {
        if (reloj) clearTimeout(reloj);
      }
    }
  }

  const API = { ModeloGimnasio, abrirAlmacen, almacenMemoria, cuentaDe };
  if (typeof module !== 'undefined' && module.exports) module.exports = API;
  else raiz.GimnasioCola = API;
})(typeof window !== 'undefined' ? window : globalThis);
