/* =============================================================
   tecnica-cola.js — «Técnica por video»: dónde espera el video y la cola.

   Mismo criterio que la cola de Gimnasio, con dos diferencias que da el tamaño:
   - El video se guarda en IndexedDB en trozos de 4 MB, leídos del archivo de a uno:
     nunca hay un ArrayBuffer con el video entero. Con la pestaña abierta se sube el
     File original; después de recargar, un Blob armado con los trozos.
   - Reintentar cuesta hasta 60 MB de datos del alumno, así que los fallos tienen tope
     (MAX_FALLOS): después queda en pausa con «Probar de nuevo». Un intento que casi no
     mandó datos (un 429, un rechazo apenas arranca) gasta de otro cupo, más largo.

   Un rechazo del servidor puede llegar como corte: mini-vision cierra la conexión
   apenas contesta, con el cuerpo sin leer, y el navegador solo ve un error de red.
   Por eso después de un corte se le pregunta a `mypump_tecnica_get` cómo quedó:
   sin respuesta, no hay señal y no se cuenta; con respuesta y el envío ya tomado,
   llegó; con respuesta y sigue en borrador, cuenta como fallo.

   Sin IndexedDB o sin lugar: queda en memoria y sirve con la pestaña abierta.
   El token no se guarda acá: la cuenta es un hash corto, solo para separar cuentas.
   ============================================================= */
(function (raiz) {
  'use strict';

  const Tec = (typeof module !== 'undefined' && module.exports) ? require('./tecnica.js') : raiz.Tecnica;
  const { cuentaDe } = (typeof module !== 'undefined' && module.exports) ? require('./gimnasio-cola.js') : raiz.GimnasioCola;
  const T = Tec.T;

  const DB = 'mypump-tecnica';
  const TROZO_BYTES = 4 * 1024 * 1024;
  const VENCE_MS = 7 * 24 * 3600 * 1000;
  const VENCE_INCOMPLETO_MS = 3600 * 1000;
  const MAX_FALLOS = 4;
  const MAX_FALLOS_BARATOS = 12;       // a 1 por minuto cubre los 4 minutos que el servidor puede tardar en soltar una subida cortada
  const AVANCE_BARATO = 0.05;
  const MAX_REINTENTOS_FONDO = 5;
  const ESPERA_SIN_SENAL_MS = 60000;
  const ESPERA_LARGA_MS = 180000;
  const ESPERA_CORTE_MS = 5000;
  const SIN_AVANCE_MS = 60000;
  const TIMEOUT_POST_MS = 30000;

  const aBuffer = (b) => (b.arrayBuffer ? b.arrayBuffer() : new Response(b).arrayBuffer());

  // ── Almacén en memoria: fallback y pruebas ──
  function almacenMemoria() {
    const cola = new Map(), videos = new Map(), kv = new Map();
    return {
      persistente: false,
      async leerKV(k) { return kv.has(k) ? JSON.parse(kv.get(k)) : undefined; },
      async guardarKV(k, v) { kv.set(k, JSON.stringify(v)); },
      async borrarKV(k) { kv.delete(k); },
      async agregarVideo(meta, archivo) { videos.set(meta.id, archivo); cola.set(meta.id, { ...meta, completo: true }); },
      async leerVideo(meta) { return videos.get(meta.id) || null; },
      async actualizar(meta) { if (cola.has(meta.id)) cola.set(meta.id, { ...meta, completo: true }); },
      async sacarVideo(id) { cola.delete(id); videos.delete(id); },
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
      const reloj = setTimeout(() => no(new Error('indexedDB no contestó')), 4000);
      req.onupgradeneeded = () => {
        const d = req.result;
        if (!d.objectStoreNames.contains('cola')) d.createObjectStore('cola', { keyPath: 'id' });
        if (!d.objectStoreNames.contains('trozos')) d.createObjectStore('trozos', { keyPath: 'k' });
        if (!d.objectStoreNames.contains('kv')) d.createObjectStore('kv', { keyPath: 'k' });
      };
      req.onsuccess = () => { clearTimeout(reloj); ok(req.result); };
      req.onerror = () => { clearTimeout(reloj); no(req.error); };
      req.onblocked = () => { clearTimeout(reloj); no(new Error('indexedDB bloqueada')); };
    });
  }
  const claveTrozo = (id, n) => `${id}:${String(n).padStart(4, '0')}`;
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
    const sacar = (id) => con(async (b) => {
      const t = b.transaction(['cola', 'trozos'], 'readwrite');
      t.objectStore('cola').delete(id);
      t.objectStore('trozos').delete(IDBKeyRange.bound(`${id}:`, `${id}:￿`));
      await fin(t);
    });
    const ponerMeta = (m) => con(async (b) => { const t = b.transaction('cola', 'readwrite'); t.objectStore('cola').put(m); await fin(t); });
    return {
      persistente: true,
      leerKV: (k) => con(async (b) => { const r = await promesa(b.transaction('kv').objectStore('kv').get(k)); return r ? r.v : undefined; }),
      guardarKV: (k, v) => con(async (b) => { const t = b.transaction('kv', 'readwrite'); t.objectStore('kv').put({ k, v }); await fin(t); }),
      borrarKV: (k) => con(async (b) => { const t = b.transaction('kv', 'readwrite'); t.objectStore('kv').delete(k); await fin(t); }),
      /* La fila entra primero como incompleta: si la pestaña se cierra a mitad, no es un video a medias en la cola sino basura que se limpia sola. */
      async agregarVideo(meta, archivo) {
        await ponerMeta({ ...meta, completo: false });
        try {
          const total = Math.max(1, Math.ceil(archivo.size / TROZO_BYTES));
          for (let n = 0; n < total; n++) {
            const bytes = await aBuffer(archivo.slice(n * TROZO_BYTES, (n + 1) * TROZO_BYTES));
            await con(async (b) => { const t = b.transaction('trozos', 'readwrite'); t.objectStore('trozos').put({ k: claveTrozo(meta.id, n), bytes }); await fin(t); });
          }
          await ponerMeta({ ...meta, completo: true });
        } catch (e) {
          try { await sacar(meta.id); } catch (_) {}
          throw e;
        }
      },
      /* null si falta un trozo. Cada trozo pasa a Blob enseguida para que el navegador lo administre fuera del heap de JS. */
      async leerVideo(meta) {
        const total = Math.max(1, Math.ceil(meta.bytes / TROZO_BYTES));
        const partes = [];
        for (let n = 0; n < total; n++) {
          const r = await con((b) => promesa(b.transaction('trozos').objectStore('trozos').get(claveTrozo(meta.id, n))));
          if (!r) return null;
          partes.push(new Blob([r.bytes]));
        }
        const blob = new Blob(partes, { type: meta.tipo || 'video/mp4' });
        return blob.size === meta.bytes ? blob : null;
      },
      /* Solo si la fila sigue: una cancelación no puede revivir con una escritura que venía en camino. */
      actualizar: (m) => con(async (b) => {
        const t = b.transaction('cola', 'readwrite'), s = t.objectStore('cola');
        const r = s.get(m.id);
        r.onsuccess = () => { if (r.result) s.put({ ...m, completo: true }); };
        await fin(t);
      }),
      sacarVideo: sacar,
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

  /* XMLHttpRequest y no fetch: es el único que da avance de subida, y el cuerpo Blob lleva Content-Length solo.
     → { status, json } o null si se cortó. Sin avance por un minuto se corta: un timeout fijo castigaría a la señal lenta. */
  function subirConXHR({ url, token, id, cuerpo, alProgreso, registrarAbortar }) {
    return new Promise((ok) => {
      const xhr = new XMLHttpRequest();
      let reloj = null;
      const rearmar = () => { clearTimeout(reloj); reloj = setTimeout(() => xhr.abort(), SIN_AVANCE_MS); };
      const listo = (v) => { clearTimeout(reloj); ok(v); };
      xhr.open('POST', url);
      xhr.setRequestHeader('Content-Type', 'application/octet-stream');
      xhr.setRequestHeader('x-tecnica-token', token);
      xhr.setRequestHeader('x-tecnica-id', id);
      xhr.upload.onprogress = (ev) => { rearmar(); if (ev.lengthComputable) alProgreso(ev.loaded, ev.total); };
      // Terminado el envío, el servidor todavía procesa (ffprobe, ffmpeg, Storage): ahí el reloj es más largo.
      xhr.upload.onload = () => { clearTimeout(reloj); reloj = setTimeout(() => xhr.abort(), SIN_AVANCE_MS * 5); };
      xhr.onload = () => {
        let json = null;
        try { json = JSON.parse(xhr.responseText); } catch (_) {}
        listo(xhr.status ? { status: xhr.status, json } : null);
      };
      xhr.onerror = () => listo(null);
      xhr.onabort = () => listo(null);
      xhr.ontimeout = () => listo(null);
      if (registrarAbortar) registrarAbortar(() => xhr.abort());
      rearmar();
      xhr.send(cuerpo);
    });
  }

  /* deps: { rpc(fn, params) → {ok:true,data} | {ok:false,status,codigo,clase}, almacen, token, visionUrl,
             subir(pedido), fetch, esperar(ms), ahora(), nuevoId(), conLock(fn), visible() } */
  class ModeloTecnica {
    constructor(deps) {
      this.rpc = deps.rpc;
      this.almacen = deps.almacen;
      this.token = deps.token;
      this.visionUrl = String(deps.visionUrl || '').replace(/\/$/, '');
      this.subidor = deps.subir || subirConXHR;
      this.fetch = deps.fetch || ((...a) => fetch(...a));
      this.esperar = deps.esperar || ((ms) => new Promise((r) => setTimeout(r, ms)));
      this.ahora = deps.ahora || (() => Date.now());
      this.nuevoId = deps.nuevoId || uuid;
      this.conLock = deps.conLock || ((fn) => fn());
      this.visible = deps.visible || (() => typeof document === 'undefined' || document.visibilityState === 'visible');
      this.cuenta = cuentaDe(this.token);

      this.estado = null;           // null: apagado, sin el servidor nuevo o sin red la primera vez
      this.cola = [];
      this.subiendoId = null;
      this.progreso = 0;            // 0 a 1
      this.guardando = false;       // el video elegido se está pasando a IndexedDB
      this.aviso = null;
      this.avisoVisto = false;
      this.alCambiar = () => {};
      this.alProgreso = () => {};

      this._vivos = new Map();      // id → File: lo que se eligió en esta visita
      this._drenando = false;
      this._otraPasada = false;
      this._reintentoProgramado = false;
      this._reintentosDeFondo = 0;
      this._cancelados = new Set();
      this._abortar = null;
      this._urls = {};
    }

    get _kvAviso() { return `aviso:${this.cuenta}`; }
    get _kvEstado() { return `estado:${this.cuenta}`; }
    _avisar() { try { this.alCambiar(); } catch (_) {} }

    async cargar() {
      try { this.avisoVisto = !!(await this.almacen.leerKV(this._kvAviso)); } catch (_) {}
      await this._releerCola(true);
    }

    async _releerCola(purgar) {
      let filas;
      try { filas = await this.almacen.listar(); } catch (_) { return; }
      const ahora = this.ahora();
      if (purgar) {
        for (const f of filas) {
          const vencio = f.completo ? (f.creado || 0) < ahora - VENCE_MS : (f.creado || 0) < ahora - VENCE_INCOMPLETO_MS;
          if (vencio) { try { await this.almacen.sacarVideo(f.id); } catch (_) {} }
        }
        filas = filas.filter((f) => f.completo && (f.creado || 0) >= ahora - VENCE_MS);
      }
      const propias = filas.filter((f) => f.completo && f.cuenta === this.cuenta && !this._cancelados.has(f.id));
      const soloAca = this.cola.filter((c) => c.soloMemoria && !propias.some((f) => f.id === c.id));
      this.cola = [...propias, ...soloAca].sort((a, b) => (a.creado || 0) - (b.creado || 0));
    }

    // ── Lo que lee la pantalla ──
    get visibleEntrada() { return !!this.estado; }
    get envios() { return this.estado ? this.estado.envios.filter((e) => e.estado !== 'borrador') : []; }
    get topes() { return this.estado ? this.estado.topes : Tec.TOPES_BASE; }
    /* El aviso breve, solo la primera vez: es informativo y no frena ni condiciona el envío. */
    get necesitaAviso() { return !!this.estado && !this.avisoVisto && !this.envios.length; }
    get bloqueo() { return Tec.bloqueo(this.estado, this.cola.length + (this.guardando ? 1 : 0), this.ahora()); }
    envio(id) { return this.envios.find((e) => e.id === id) || null; }
    limpiarAviso() { this.aviso = null; }
    apagar() { this.estado = null; }

    // ── Servidor ──
    async refrescar(previa) {
      const r = previa || await this.rpc('mypump_tecnica_get', { p_token: this.token });
      if (r.ok) {
        if (r.data === null || r.data === undefined) { this.estado = null; this._avisar(); return; }
        const e = Tec.decodificarEstado(r.data);
        if (!e) { this.apagar(); this._olvidarEstado(); this._avisar(); return; }
        this.estado = e;
        try { await this.almacen.guardarKV(this._kvEstado, r.data); } catch (_) {}
        await this._conciliar(e);
      } else if (r.status === 404 || r.codigo === 'PGRST202' || r.clase === 'permanente') {
        this.apagar();
        this._olvidarEstado();
      } else if (!this.estado) {
        // Sin red: lo último que se supo, para ver el estado y seguir un envío a medias.
        let j;
        try { j = await this.almacen.leerKV(this._kvEstado); } catch (_) {}
        const e = j ? Tec.decodificarEstado(j) : null;
        if (e) this.estado = e;
      }
      this._avisar();
    }

    _olvidarEstado() { this.almacen.borrarKV(this._kvEstado).catch(() => {}); }

    /* El servidor ya lo tomó (subió bien y se perdió la respuesta, por ejemplo al recargar): en la cola no tiene nada más que hacer. */
    async _conciliar(e) {
      for (const c of [...this.cola]) {
        if (!c.servidorId || c.id === this.subiendoId) continue;
        const s = e.envios.find((x) => x.id === c.servidorId);
        if (s && s.estado !== 'borrador') await this._sacar(c.id);
      }
    }

    // ── Enviar ──
    /* Aceptar el aviso de terceros es parte del envío. → 'ok' | 'enRevision' | 'tope' | 'invalido' | clave de rechazo */
    async enviar({ ejercicio, nota, archivo, duracion, contenedorOk }) {
      const e = this.estado;
      if (!e || !ejercicio || !archivo) return 'invalido';
      const b = this.bloqueo;
      if (b) return b;
      const rechazo = Tec.validarVideo({ bytes: archivo.size, duracion, contenedorOk }, e.topes);
      if (rechazo) return rechazo;
      this.aviso = null;
      this.guardando = true;
      this._avisar();
      const meta = {
        id: String(this.nuevoId()).toLowerCase(), cuenta: this.cuenta, servidorId: null,
        slug: ejercicio.slug, nombre: ejercicio.nombre, nota: Tec.notaRecortada(nota).trim() || null,
        bytes: archivo.size, tipo: archivo.type || 'video/mp4',
        duracion: typeof duracion === 'number' && isFinite(duracion) ? duracion : null, creado: this.ahora(), fallos: 0, fallosBaratos: 0, pausado: false, soloMemoria: false,
      };
      try {
        await this.almacen.agregarVideo(meta, archivo);
      } catch (_) {
        meta.soloMemoria = true;      // sin lugar en el teléfono: sirve mientras la pestaña siga abierta
      }
      this._vivos.set(meta.id, archivo);
      this.cola.push(meta);
      this.guardando = false;
      this.avisoVisto = true;
      try { await this.almacen.guardarKV(this._kvAviso, '1'); } catch (_) {}
      this._reintentosDeFondo = 0;
      this._avisar();
      this.drenar().catch(() => {});
      return 'ok';
    }

    /* Del alumno: el video en pausa vuelve a intentar con el contador en cero. */
    async reintentar(id) {
      const c = this.cola.find((x) => x.id === id);
      if (!c) return;
      c.fallos = 0;
      c.fallosBaratos = 0;
      c.pausado = false;
      this.aviso = null;
      await this._persistir(c);
      this._reintentosDeFondo = 0;
      this._avisar();
      this.drenar().catch(() => {});
    }

    async cancelar(id) {
      const c = this.cola.find((x) => x.id === id);
      if (!c) return;
      this._cancelados.add(id);
      if (this.subiendoId === id && this._abortar) this._abortar();
      await this._sacar(id);
      if (c.servidorId) { await this._cancelarEnServidor(c.servidorId); await this.refrescar(); }   // pudo haber llegado justo antes
      this._avisar();
    }

    /* Una fila en borrador no molesta (el próximo `nuevo` la vuelve a usar): si falla, no pasa nada. */
    async _cancelarEnServidor(servidorId) {
      try { await this.rpc('mypump_tecnica_cancelar', { p_token: this.token, p_id: servidorId }); } catch (_) {}
    }

    async _persistir(c) {
      if (c.soloMemoria || this._cancelados.has(c.id)) return;
      try { await this.almacen.actualizar(c); } catch (_) {}
    }

    async _sacar(id) {
      this.cola = this.cola.filter((c) => c.id !== id);
      this._vivos.delete(id);
      try { await this.almacen.sacarVideo(id); } catch (_) {}
    }

    reanudar() { this._reintentosDeFondo = 0; this.drenar().catch(() => {}); }

    /* Una pasada a la vez, con el lock de las pestañas: dos pestañas no suben el mismo video. */
    async drenar() {
      if (!this.estado) return;
      if (this._drenando) { this._otraPasada = true; return; }
      this._drenando = true;
      try {
        do {
          this._otraPasada = false;
          await this.conLock(() => this._pasada());
        } while (this._otraPasada && this.estado);
      } finally {
        this._drenando = false;
        this._avisar();
      }
    }

    _siguiente() { return this.cola.find((c) => !c.pausado && !this._cancelados.has(c.id)) || null; }

    async _pasada() {
      await this._releerCola(false);
      let item;
      while (this.estado && (item = this._siguiente())) {
        if (!item.servidorId) {
          const creado = await this._crearEnServidor(item);
          if (creado === 'sigue') continue;
          if (creado === 'corta') return;
          continue;
        }
        const seguir = await this._intentarSubida(item);
        if (!seguir) return;
      }
    }

    /* → 'sigue' | 'corta' | 'descartado' */
    async _crearEnServidor(item, reintentos = 1) {
      const r = await this.rpc('mypump_tecnica_nuevo', {
        p_token: this.token, p_ejercicio_slug: item.slug, p_ejercicio_nombre: item.nombre, p_nota: item.nota,
      });
      if (!r.ok) {
        if (r.clase === 'permanente') return this._descartarLocal(item, T.errorGenerico);
        this._programarReintento(ESPERA_SIN_SENAL_MS);
        return 'corta';
      }
      if (r.data === null || r.data === undefined) return 'corta';      // token caído: queda guardado por si vuelve
      const j = r.data;
      if (this._cancelados.has(item.id)) {        // canceló mientras viajaba el pedido
        if (j.ok === true && typeof j.id === 'string') await this._cancelarEnServidor(j.id.toLowerCase());
        return 'descartado';
      }
      if (j.ok === true && typeof j.id === 'string') {
        item.servidorId = j.id.toLowerCase();
        await this._persistir(item);
        return 'sigue';
      }
      switch (j.error) {
        case 'en_curso': return this._descartarLocal(item, T.enRevision, true);
        case 'tope_semanal': return this._descartarLocal(item, T.topeSemana(this.topes.porSemana), true);
        case 'no_habilitado': this.apagar(); this._avisar(); return 'corta';   // queda en la cola (como Gimnasio y Estudios): si la vuelven a habilitar, sale
        case 'reintentar':
          if (reintentos > 0) return this._crearEnServidor(item, reintentos - 1);
          this._programarReintento(ESPERA_SIN_SENAL_MS);
          return 'corta';
        default: return this._descartarLocal(item, T.errorGenerico);
      }
    }

    async _descartarLocal(item, aviso, refrescar) {
      await this._sacar(item.id);
      if (aviso) this.aviso = aviso;
      if (refrescar) await this.refrescar();
      this._avisar();
      return 'descartado';
    }

    /* true: se puede seguir con la pasada. */
    async _intentarSubida(item) {
      let cuerpo = this._vivos.get(item.id) || null;
      if (!cuerpo) {
        try { cuerpo = await this.almacen.leerVideo(item); } catch (_) { this._programarReintento(ESPERA_SIN_SENAL_MS); return false; }
        if (this._cancelados.has(item.id)) return true;
        if (!cuerpo) {      // faltan trozos: no hay manera de reconstruirlo
          await this._cancelarEnServidor(item.servidorId);
          await this._descartarLocal(item, T.noSubio);
          return true;
        }
      }
      this.subiendoId = item.id;
      this.progreso = 0;
      this._avisar();
      let res;
      try {
        res = await this.subidor({
          url: `${this.visionUrl}/tecnica/upload`, token: this.token, id: item.servidorId, cuerpo,
          alProgreso: (hecho, total) => { this.progreso = total ? hecho / total : 0; try { this.alProgreso(this.progreso); } catch (_) {} },
          registrarAbortar: (fn) => { this._abortar = fn; },
        });
      } catch (_) { res = null; }
      this._abortar = null;
      this.subiendoId = null;
      cuerpo = null;
      if (this._cancelados.has(item.id)) return true;      // cancelar ya lo sacó
      if (res) {
        const s = Tec.clasificarSubida(res.status, res.json);
        if (s.accion === 'ok') {
          await this._sacar(item.id);
          this.aviso = null;
          this._marcarEnviado(item);
          await this.refrescar();
          return true;
        }
        if (s.accion === 'descartar') {
          await this._cancelarEnServidor(item.servidorId);
          await this._descartarLocal(item, s.aviso, !!s.refrescar);
          return true;
        }
        return this._contarFallo(item, res.status === 429);
      }
      return this._despuesDeUnCorte(item, this.progreso < AVANCE_BARATO);
    }

    /* Si el `get` de después falla, el alumno igual ve «Recibido» y no vuelve a tener el botón habilitado. */
    _marcarEnviado(item) {
      if (!this.estado) return;
      const e = this.estado.envios.find((x) => x.id === item.servidorId);
      const hoy = new Date(this.ahora()).toISOString();
      if (e) Object.assign(e, { estado: 'enviado', tieneVideo: true, enviadoEn: e.enviadoEn || hoy });
      else this.estado.envios.unshift({ id: item.servidorId, estado: 'enviado', ejercicioSlug: item.slug, ejercicioNombre: item.nombre, nota: item.nota, enviadoEn: hoy, tieneVideo: true, rechazoTexto: null, publicadoEn: null, devolucion: null });
    }

    /* El corte puede ser señal, una subida que sí llegó, o un rechazo disfrazado. Lo aclara el `get`. */
    async _despuesDeUnCorte(item, barato) {
      let r;
      try { r = await this.rpc('mypump_tecnica_get', { p_token: this.token }); } catch (_) { r = { ok: false, clase: 'red' }; }
      if (!r.ok) {
        if (r.status === 404 || r.codigo === 'PGRST202' || r.clase === 'permanente') { await this.refrescar(r); return false; }
        // Sin señal real el corte es instantáneo y no gasta. Si alcanzó a mandar datos, sí cuenta: si no, una señal intermitente no tendría tope.
        if (!barato) return this._contarFallo(item, false);
        this._soltarVivo(item);
        this._programarReintento(ESPERA_SIN_SENAL_MS);
        this._avisar();
        return false;
      }
      await this.refrescar(r);
      if (!this.estado) return false;      // token caído o apagado: queda guardado
      const envio = this.estado.envios.find((x) => x.id === item.servidorId);
      if (envio && envio.estado !== 'borrador') {
        await this._sacar(item.id);
        this._avisar();
        return true;
      }
      // Ya no existe del lado del servidor: ningún reintento puede funcionar.
      if (!envio) { await this._descartarLocal(item, T.noSubio); return true; }
      return this._contarFallo(item, barato);
    }

    /* Falló con el servidor al alcance. Pasado el tope queda en pausa: reintentar solo no puede comerse los datos del alumno. */
    async _contarFallo(item, barato) {
      this._soltarVivo(item);
      if (barato) item.fallosBaratos = (item.fallosBaratos || 0) + 1;
      else item.fallos = (item.fallos || 0) + 1;
      if (item.fallos >= MAX_FALLOS || item.fallosBaratos >= MAX_FALLOS_BARATOS) {
        item.pausado = true;
        await this._persistir(item);
        this._avisar();
        return true;
      }
      await this._persistir(item);
      this._avisar();
      this._programarReintento(barato ? ESPERA_SIN_SENAL_MS : ESPERA_CORTE_MS * Math.pow(3, item.fallos - 1));
      return false;
    }

    /* Después de un fallo se sigue con la copia guardada: el archivo original puede haber dejado de ser legible. */
    _soltarVivo(item) { if (!item.soloMemoria) this._vivos.delete(item.id); }

    _programarReintento(ms) {
      if (this._reintentoProgramado) return;
      const quedaAlgo = this.cola.some((c) => !c.pausado);
      const agotado = this._reintentosDeFondo >= MAX_REINTENTOS_FONDO;
      if (agotado && !(quedaAlgo && this.visible())) return;
      this._reintentoProgramado = true;
      this._reintentosDeFondo += 1;
      this.esperar(agotado ? ESPERA_LARGA_MS : ms).then(() => { this._reintentoProgramado = false; return this.drenar(); }).catch(() => {});
    }

    // ── Ver y borrar ──
    /* → la URL firmada del video propio, o null. Dura una hora: se reusa 50 minutos. */
    async urlVideo(id) {
      const c = this._urls[id];
      if (c && c.vence > this.ahora()) return c.url;
      const r = await this._post('tecnica/url', { token: this.token, id });
      if (!r || !r.json || r.json.ok !== true || typeof r.json.url !== 'string') return null;
      this._urls[id] = { url: r.json.url, vence: this.ahora() + 50 * 60 * 1000 };
      return r.json.url;
    }

    /* → 'ok' | 'enAnalisis' | 'sinSenal' | 'error' */
    async borrarVideo(id) {
      const r = await this._post('tecnica/borrar', { token: this.token, id });
      if (!r) return 'sinSenal';
      if (r.status === 409) return 'enAnalisis';
      if (r.status < 200 || r.status >= 300 || !r.json || r.json.ok !== true) return 'error';
      delete this._urls[id];
      await this.refrescar();
      return 'ok';
    }

    async _post(ruta, cuerpo) {
      const ctrl = typeof AbortController !== 'undefined' ? new AbortController() : null;
      const reloj = ctrl ? setTimeout(() => ctrl.abort(), TIMEOUT_POST_MS) : null;
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

  const API = { ModeloTecnica, abrirAlmacen, almacenMemoria, subirConXHR, TROZO_BYTES, MAX_FALLOS, MAX_FALLOS_BARATOS };
  if (typeof module !== 'undefined' && module.exports) module.exports = API;
  else raiz.TecnicaCola = API;
})(typeof window !== 'undefined' ? window : globalThis);
