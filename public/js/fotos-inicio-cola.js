/* =============================================================
   fotos-inicio-cola.js — «Fotos de inicio»: dónde esperan las fotos y la cola.

   Mismo mecanismo que gimnasio-cola.js (y el mismo criterio que la cola de las
   apps, NATIVA_CONTRATO.md §13 «La cola»): 4xx es definitivo, 5xx, 429 y red no
   gastan la foto. Se sube de a una, en el orden en que se encolaron.

   Las fotos NO van a localStorage. Van a IndexedDB como bytes (Safari ha perdido
   Blobs guardados ahí), en una base propia con tres almacenes:
     cola   → una fila por foto: { id, cuenta, pose, tomadaEn, brillo, nitidez, ancho, alto, creado, miniatura }
     fotos  → los bytes del JPEG, por id. Se escribe junto con `cola`, en la misma transacción.
     kv     → la nota que no se pudo mandar, los borrados pendientes y el último estado (JSON, sin fotos).
   El token no se guarda acá: la cuenta es un hash corto, solo para separar cuentas.
   Si IndexedDB no existe o no abre (Safari privado), queda en memoria: mientras la
   pestaña esté abierta funciona igual; al recargar, esas fotos no siguen.
   ============================================================= */
(function (raiz) {
  'use strict';

  const F = (typeof module !== 'undefined' && module.exports) ? require('./fotos-inicio.js') : raiz.FotosInicio;

  const DB = 'mypump-fotos-inicio';
  const RPC_GET = 'mypump_fotos_inicio_get';
  const RPC_NOTA = 'mypump_fotos_inicio_nota';
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

  /* Sin el servidor nuevo (PGRST202 o 404) o un error que no es de red: la sección no existe para esta cuenta. */
  const apagadoPorError = (r) => r.status === 404 || r.codigo === 'PGRST202' || r.clase === 'permanente';
  const numero = (v) => (typeof v === 'number' && Number.isFinite(v) ? String(Math.round(v * 10) / 10) : null);

  /* deps: { rpc(fn, params) → {ok:true,data} | {ok:false,status,codigo,clase:'red'|'transitorio'|'permanente'},
             almacen, token, visionUrl, fetch, esperar(ms), ahora(), nuevoId(), conLock(fn), visible() } */
  class ModeloFotosInicio {
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

      this.estado = null;           // null: apagado, token caído, sin el servidor nuevo o sin red la primera vez
      this.tokenCaido = false;
      this.cola = [];
      this.subiendo = null;
      this.urls = {};
      this.miniaturas = {};         // las de esta visita, para no pedir firmas de lo que acaba de subir
      this.aviso = null;            // 'rechazada' | 'tope'
      this.borrador = this._borradorVacio();

      this.alCambiar = () => {};
      this._drenando = false;
      this._otraPasada = false;
      this._conError = new Set();
      this._borrarAlSubir = new Set();
      this._urlsVencen = 0;
      this._reintentoProgramado = false;
      this._reintentosDeFondo = 0;
      this._mandandoNota = false;
      this._lecturas = new Set();
      this._gets = new Set();
      this._guardado = Promise.resolve();
      this._mutaciones = 0;
      this._ultimoCreado = 0;
    }

    _borradorVacio() { return { notaPendiente: null, borrarPendientes: [] }; }
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
      // Lo que se agregue o se saque mientras viaja la lectura manda sobre lo leído.
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
      this.cola = filas.filter((f) => f.cuenta === this.cuenta).sort((a, b) => (a.creado || 0) - (b.creado || 0));
      for (const f of this.cola) {
        if (f.miniatura) this.miniaturas[f.id] = f.miniatura;
        this._ultimoCreado = Math.max(this._ultimoCreado, f.creado || 0);
      }
    }

    // ── Lo que lee la pantalla ──
    get visibleSeccion() { return !!this.estado; }
    get _colaCuerpo() { return this.cola.filter((c) => c.pose !== F.MOTIVACION); }
    get _colaMotivacion() { return this.cola.filter((c) => c.pose === F.MOTIVACION); }
    get posesEnServidor() { return F.posesDe(this.estado); }
    get posesEnCola() { return new Set(this._colaCuerpo.map((c) => c.pose)); }
    get faltan() { return F.faltan(this.posesEnServidor, this.posesEnCola); }
    /* Cuántas del cuerpo hay, contando las que esperan subir. */
    get cuenta3() { return F.POSES.length - this.faltan.length; }
    /* Las tres en el servidor: «Listas. Mati ya las tiene». */
    get listas() { return !!this.estado && F.faltan(this.posesEnServidor, []).length === 0 && !this._colaCuerpo.length; }
    get nota() { return this.borrador.notaPendiente !== null && this.borrador.notaPendiente !== undefined ? this.borrador.notaPendiente : (this.estado ? this.estado.nota : ''); }
    get notaPendiente() { return this.borrador.notaPendiente !== null && this.borrador.notaPendiente !== undefined; }
    get maxMotivacion() { return this.estado ? this.estado.maxMotivacion : F.MAX_MOTIVACION; }
    get puedeAgregarMotivacion() {
      return !!this.estado && F.puedeAgregarMotivacion(F.deMotivacion(this.estado).length, this._colaMotivacion.length, this.maxMotivacion);
    }

    /* 'falta' | 'subiendo' | 'esperando' | 'lista'. La que espera en la cola manda sobre la que ya está en el servidor. */
    estadoPose(clave) {
      const enCola = this._colaCuerpo.filter((c) => c.pose === clave).pop();
      if (enCola) return this.subiendo === enCola.id ? 'subiendo' : 'esperando';
      return this.posesEnServidor.has(clave) ? 'lista' : 'falta';
    }
    /* La miniatura que se ve de una pose: la de la cola, la que se sacó en esta visita o la firmada del servidor. */
    miniaturaPose(clave) {
      const enCola = this._colaCuerpo.filter((c) => c.pose === clave).pop();
      if (enCola) return enCola.miniatura || null;
      const f = this.estado ? this.estado.fotos.find((x) => x.pose === clave) : null;
      return f ? (this.miniaturas[f.id] || this.urls[f.id] || null) : null;
    }
    idServidor(clave) {
      const f = this.estado ? this.estado.fotos.find((x) => x.pose === clave) : null;
      return f ? f.id : null;
    }
    /* Las de «el físico que te motiva»: las del servidor y las que esperan. */
    get motivacion() {
      const enServidor = F.deMotivacion(this.estado).map((f) => ({ id: f.id, local: false, subiendo: false, esperando: false, miniatura: this.miniaturas[f.id] || this.urls[f.id] || null }));
      const aqui = this._colaMotivacion.map((c) => ({ id: c.id, local: true, subiendo: this.subiendo === c.id, esperando: this.subiendo !== c.id, miniatura: c.miniatura || null }));
      return [...enServidor, ...aqui];
    }

    // ── Servidor ──
    /* null: token caído (se esconde). habilitado:false, PGRST202 o 404: apagado, no se muestra nada. Sin red: lo último que se supo. */
    async refrescar(previa) {
      const durante = [];
      this._gets.add(durante);
      let r;
      try { r = previa || await this.rpc('mypump_fotos_inicio_get', { p_token: this.token }); } finally { this._gets.delete(durante); }
      if (r.ok) {
        if (r.data === null || r.data === undefined) { this.tokenCaido = true; this.estado = null; this._avisar(); return; }
        const e = F.decodificarEstado(r.data);
        if (!e) { this.apagar(); this._olvidarEstado(); this._avisar(); return; }
        this.tokenCaido = false;
        // Lo que terminó de subir mientras viajaba este `get` no está en su foto del servidor y ya salió de la cola.
        for (const f of durante) this._ponerEnServidor(e, f);
        // Lo que el alumno borró y todavía no se pudo sacar del servidor no vuelve a aparecer.
        const pend = this.borrador.borrarPendientes;
        if (pend.length) e.fotos = e.fotos.filter((f) => !pend.includes(f.id));
        this.estado = e;
        try { await this.almacen.guardarKV(this._kvEstado, r.data); } catch (_) {}
        await this._releerCola(false);
      } else if (apagadoPorError(r)) {
        this.apagar();
        this._olvidarEstado();
      } else if (!this.estado) {
        let j;
        try { j = await this.almacen.leerKV(this._kvEstado); } catch (_) {}
        const e = j ? F.decodificarEstado(j) : null;
        if (e) {
          const pend = this.borrador.borrarPendientes;
          if (pend.length) e.fotos = e.fotos.filter((f) => !pend.includes(f.id));
          this.estado = e;
          await this._releerCola(false);
        }
      }
      this._avisar();
    }

    _olvidarEstado() { this.almacen.borrarKV(this._kvEstado).catch(() => {}); }
    apagar() { this.estado = null; }

    /* Una del cuerpo reemplaza en el servidor a la anterior de esa pose. */
    _ponerEnServidor(e, foto) {
      if (!e || e.fotos.some((x) => x.id === foto.id)) return;
      if (foto.pose !== F.MOTIVACION) e.fotos = e.fotos.filter((x) => x.pose !== foto.pose);
      e.fotos.push(foto);
    }

    /* En fila: dos escrituras seguidas no se pueden pisar al revés. */
    _guardarBorrador() {
      this._mutaciones += 1;
      const copia = JSON.parse(JSON.stringify(this.borrador));
      this._guardado = this._guardado.then(() => this.almacen.guardarKV(this._kvBorrador, copia)).catch(() => {});
      return this._guardado;
    }

    /* Con el lock de las pestañas tomado: lo que hizo otra manda sobre lo que esta tenía en memoria. */
    async _sincronizar() {
      const antes = this._mutaciones;
      await this._guardado;
      let b;
      try { b = await this.almacen.leerKV(this._kvBorrador); } catch (_) {}
      if (b && antes === this._mutaciones) this.borrador = { ...this._borradorVacio(), ...b };
      await this._releerCola(false);
    }

    // ── Fotos ──
    /* Encola un JPEG ya preparado: { bytes, miniatura, ancho, alto, tomadaEn (ISO), brillo, nitidez }.
       → 'guardada' | 'tope' | 'noSeGuardo'. Una pose del cuerpo nueva saca de la cola a la anterior de esa pose que
       todavía no empezó a subir. Después hay que drenar. */
    async agregar(pose, foto) {
      if (!this.estado) return 'noSeGuardo';
      if (pose === F.MOTIVACION && !this.puedeAgregarMotivacion) { this.aviso = 'tope'; this._avisar(); return 'tope'; }
      const creado = Math.max(this.ahora(), this._ultimoCreado + 1);
      const meta = {
        id: String(this.nuevoId()).toLowerCase(), cuenta: this.cuenta, pose,
        tomadaEn: foto.tomadaEn || null, brillo: foto.brillo == null ? null : foto.brillo, nitidez: foto.nitidez == null ? null : foto.nitidez,
        ancho: foto.ancho || 0, alto: foto.alto || 0, creado, miniatura: foto.miniatura || null,
      };
      try { await this.almacen.agregarFoto(meta, foto.bytes); } catch (_) { return 'noSeGuardo'; }
      this._ultimoCreado = creado;
      // Primero se guarda la nueva y después se saca la vieja: un corte en el medio no deja la pose sin nada.
      if (pose !== F.MOTIVACION) {
        for (const vieja of this.cola.filter((c) => c.pose === pose && c.id !== this.subiendo)) await this._sacarDeLaCola(vieja.id);
      }
      this.cola.push(meta);
      for (const l of this._lecturas) l.mas.add(meta.id);
      if (meta.miniatura) this.miniaturas[meta.id] = meta.miniatura;
      this.aviso = null;
      this._avisar();
      return 'guardada';
    }

    drenarEnFondo() { this.drenar().catch(() => {}); }
    limpiarAviso() { this.aviso = null; }

    /* Borra una de «el físico que te motiva». → 'ok' | 'sinSenal' | 'error' */
    async borrarMotivacion(id) {
      const enCola = this.cola.find((c) => c.id === id);
      if (enCola && enCola.pose !== F.MOTIVACION) return 'error';
      if (this.subiendo === id) { this._borrarAlSubir.add(id); await this._sacarDeLaCola(id); this._avisar(); return 'ok'; }
      if (enCola) { await this._sacarDeLaCola(id); this._avisar(); return 'ok'; }
      if (!F.deMotivacion(this.estado).some((f) => f.id === id)) return 'error';
      const r = await this._postVision('inicio/borrar', { token: this.token, foto_id: id });
      if (!r) return 'sinSenal';
      if (r.status < 200 || r.status >= 300 || !r.json || r.json.ok !== true) { await this.refrescar(); return 'error'; }
      this._quitarDelServidor(id);
      this._avisar();
      return 'ok';
    }

    _quitarDelServidor(id) { if (this.estado) this.estado.fotos = this.estado.fotos.filter((f) => f.id !== id); }

    /* La que se borró mientras subía: si el pedido no sale se reintenta con la cola. */
    async _anotarBorrado(id) {
      if (!this.borrador.borrarPendientes.includes(id)) this.borrador.borrarPendientes = [...this.borrador.borrarPendientes, id];
      this._quitarDelServidor(id);
      await this._guardarBorrador();
    }

    /* true: no queda ninguno pendiente. */
    async _resolverBorrados() {
      for (const id of [...this.borrador.borrarPendientes]) {
        const r = await this._postVision('inicio/borrar', { token: this.token, foto_id: id });
        if (!r || r.status === 429 || r.status >= 500) return false;     // red o falla del servidor: sigue pendiente
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
      this._sacarDeMemoria(id);
      this._conError.delete(id);
      try { await this.almacen.sacarFoto(id); } catch (_) {}
    }

    // ── La nota de «el físico que te motiva» ──
    /* → 'ok' | 'sinSenal' (queda guardada y sale con la cola) | 'error' | 'tokenCaido' */
    async guardarNota(s) {
      const n = F.notaRecortada(s);
      const r = await this._mandarNota(n);
      if (r === 'sinSenal') {
        this.borrador.notaPendiente = n;
        await this._guardarBorrador();
        this._programarReintento();
      }
      this._avisar();
      return r;
    }

    async _mandarNota(n) {
      const r = await this.rpc('mypump_fotos_inicio_nota', { p_token: this.token, p_nota: n });
      if (!r.ok) return r.clase === 'permanente' ? 'error' : 'sinSenal';
      if (r.data === null || r.data === undefined) { this.tokenCaido = true; return 'tokenCaido'; }
      if (r.data.ok === true) {
        if (this.estado) this.estado.nota = typeof r.data.nota === 'string' ? r.data.nota : n;
        if (this.borrador.notaPendiente !== null && this.borrador.notaPendiente !== undefined) {
          this.borrador.notaPendiente = null;
          await this._guardarBorrador();
        }
        return 'ok';
      }
      if (r.data.error === 'no_habilitado') this.apagar();
      return 'error';
    }

    /* true: no quedó nada pendiente. */
    async _mandarNotaPendiente() {
      const n = this.borrador.notaPendiente;
      if (n === null || n === undefined || this._mandandoNota) return true;
      this._mandandoNota = true;
      try {
        const r = await this._mandarNota(n);
        if (r === 'sinSenal') return false;
        // Error definitivo o token caído: no se insiste para siempre.
        if (this.borrador.notaPendiente === n) { this.borrador.notaPendiente = null; await this._guardarBorrador(); }
        return true;
      } finally {
        this._mandandoNota = false;
      }
    }

    /* Lo llaman el `online`, volver a la pestaña y el arranque: un corte largo no agota los reintentos para siempre. */
    reanudar() { this._reintentosDeFondo = 0; this.drenarEnFondo(); }

    // ── Cola ──
    /* Una pasada a la vez. Red: corta y espera. 5xx o 429: espera y reintenta, y a la tercera seguida deja esa foto para el
       final y corta la pasada. Todo 4xx es definitivo. Al final salen los borrados y la nota pendientes. */
    async drenar() {
      if (!this.estado) return;
      if (this._drenando) { this._otraPasada = true; return; }   // la foto que llegó justo al terminar no espera al próximo evento
      this._drenando = true;
      try {
        do {
          this._otraPasada = false;
          await this.conLock(() => this._pasada());
        } while (this._otraPasada && this.estado && this.cola.some((c) => !this._conError.has(c.id)));
      } finally {
        this._drenando = false;
        this._avisar();
      }
    }

    /* Una foto del cuerpo que tiene otra más nueva de su pose en la cola ya no se sube (quedó de cuando la nueva se encoló
       mientras esta subía): si se reintentara después, pisaría en el servidor a la que el alumno eligió. */
    async _sacarReemplazadas() {
      const ultima = new Map();
      for (const c of this.cola) if (c.pose !== F.MOTIVACION) ultima.set(c.pose, c.id);
      for (const c of this.cola.slice()) if (c.pose !== F.MOTIVACION && ultima.get(c.pose) !== c.id) await this._sacarDeLaCola(c.id);
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
      while (this.estado) {
        await this._sacarReemplazadas();
        if (!(item = this._siguiente())) break;
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
        } else if (r.tipo === 'perdida') {
          await this._sacarDeLaCola(item.id);
        } else if (r.tipo === 'descartar') {
          // 403: el link ya no sirve o se cerró la sección. Lo demás tampoco va a entrar, y la foto NO se borra.
          if (r.s.refrescar) { refrescarAlFinal = true; cortada = true; break; }
          if (r.s.aviso) this.aviso = r.s.aviso;
          this._borrarAlSubir.delete(item.id);
          await this._sacarDeLaCola(item.id);
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
      if (!this.estado) return;
      await this._sincronizar();
      // Apareció algo mientras tanto (otra pestaña, una foto recién guardada): primero eso.
      if (!cortada && this._siguiente() && this.cola.some((c) => !this._conError.has(c.id))) { this._otraPasada = true; return; }
      if (this.borrador.borrarPendientes.length && !(await this._resolverBorrados())) { this._programarReintento(); return; }
      if (!(await this._mandarNotaPendiente())) this._programarReintento();
    }

    /* Mientras la pestaña esté a la vista y quede algo por salir no se abandona: con señal mala o un wifi sin internet el
       navegador nunca avisa `online`. Pasados los primeros intentos, más espaciado. */
    _programarReintento() {
      if (this._reintentoProgramado) return;
      const quedaAlgo = this.cola.length > 0 || this.notaPendiente || this.borrador.borrarPendientes.length > 0;
      if (!quedaAlgo) return;
      const agotado = this._reintentosDeFondo >= MAX_REINTENTOS_FONDO;
      if (agotado && !this.visible()) return;
      this._reintentoProgramado = true;
      this._reintentosDeFondo += 1;
      this.esperar(agotado ? ESPERA_LARGA_MS : ESPERA_REINTENTO_MS).then(() => { this._reintentoProgramado = false; return this.drenar(); }).catch(() => {});
    }

    async _subir(p) {
      let bytes = null;
      try { bytes = await this.almacen.leerBytes(p.id); } catch (_) { return { tipo: 'red' }; }
      if (!bytes) return { tipo: 'perdida' };
      const headers = { 'Content-Type': 'image/jpeg', 'x-inicio-token': this.token, 'x-inicio-foto': p.id, 'x-inicio-pose': p.pose };
      if (p.tomadaEn) headers['x-inicio-tomada'] = p.tomadaEn;
      if (numero(p.brillo) !== null) headers['x-inicio-brillo'] = numero(p.brillo);
      if (numero(p.nitidez) !== null) headers['x-inicio-nitidez'] = numero(p.nitidez);
      const ctrl = typeof AbortController !== 'undefined' ? new AbortController() : null;
      const reloj = ctrl ? setTimeout(() => ctrl.abort(), TIMEOUT_SUBIDA_MS) : null;
      try {
        const res = await this.fetch(`${this.visionUrl}/inicio/upload`, {
          method: 'POST',
          headers,
          body: typeof Blob !== 'undefined' ? new Blob([bytes], { type: 'image/jpeg' }) : bytes,
          cache: 'no-store',
          signal: ctrl ? ctrl.signal : undefined,
        });
        let j = null;
        try { j = await res.json(); } catch (_) {}
        const s = F.clasificarSubida(res.status, !!j && j.ok === true);
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
      await this._sacarDeLaCola(item.id);
      if (this._borrarAlSubir.delete(item.id)) { await this._anotarBorrado(item.id); return; }
      const subida = { id: item.id, pose: item.pose, tomadaEn: item.tomadaEn || null, ancho: item.ancho || 0, alto: item.alto || 0 };
      for (const g of this._gets) g.push(subida);
      this._ponerEnServidor(this.estado, subida);
      this._urlsVencen = 0;
    }

    // ── Miniaturas: URLs firmadas de 1 h; se piden de nuevo a los 50 min o si aparece una que no estaba ──
    async firmar(ids, forzar = false) {
      const falta = ids.some((id) => !this.urls[id]);
      if (!forzar && !falta && this._urlsVencen > this.ahora()) return;
      const r = await this._postVision('inicio/urls', { token: this.token });
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

  /* El arranque. Con la palanca apagada no se llama a nada ni se abre la base. A una cuenta sin la sección (habilitado:false,
     token caído, PGRST202 o 404) tampoco se le crea la base. Sin red la primera vez se sigue con lo último que se supo.
     op: { prendida, rpc, token, visionUrl, abrirAlmacen?, conLock?, fetch?, esperar?, ahora?, nuevoId?, visible? } → modelo | null */
  async function arrancar(op) {
    if (op.prendida !== true || !op.token) return null;
    const primera = await op.rpc('mypump_fotos_inicio_get', { p_token: op.token });
    if (primera.ok ? !F.decodificarEstado(primera.data) : apagadoPorError(primera)) return null;
    const almacen = await (op.abrirAlmacen || abrirAlmacen)();
    const m = new ModeloFotosInicio({ ...op, almacen });
    await m.cargar();
    await m.refrescar(primera);
    return m;
  }

  const API = { ModeloFotosInicio, abrirAlmacen, almacenMemoria, cuentaDe, arrancar, RPC_GET, RPC_NOTA };
  if (typeof module !== 'undefined' && module.exports) module.exports = API;
  else raiz.FotosInicioCola = API;
})(typeof window !== 'undefined' ? window : globalThis);
