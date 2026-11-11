/* =============================================================
   presion-cola.js — «Presión arterial»: el estado, la sesión en curso y la cola.

   Implementa presion/CONTRATO_APP.md. Las reglas y los textos son de presion.js.

   · Con la palanca apagada, sin el servidor nuevo (PGRST202 o 404) o sin estado habilitado
     no se crea nada: ni modelo, ni IndexedDB, ni llamadas (`arrancar`).
   · Sesiones y síntomas se guardan primero en el teléfono y se mandan en orden. La sesión
     viaja entera después de cada toma y el servidor la toma por `id`: repetirla no duplica.
     Sin red, 5xx o 429 quedan en la cola. Un 4xx que no sea 429, o `ok: false`, se descarta
     y se refresca el estado.
   · La sesión en curso se guarda con la hora de fin de cada espera: al volver (otra pestaña,
     recarga) el temporizador sigue donde iba y una repetición pendiente se retoma.
   · El paso que sigue y el texto de guardia los decide `evaluarSesion` acá, sin esperar al servidor.
   · Nada de esto toca la rutina ni el entrenamiento.

   Almacén: IndexedDB (cola y kv), como las colas de Gimnasio y Técnica; si no abre, memoria.
   El token no se guarda: la cuenta es un hash corto, solo para separar cuentas.
   ============================================================= */
(function (raiz) {
  'use strict';

  const enNode = typeof module !== 'undefined' && module.exports;
  const P = enNode ? require('./presion.js') : raiz.Presion;
  const { cuentaDe } = enNode ? require('./gimnasio-cola.js') : raiz.GimnasioCola;

  const DB = 'mypump-presion';
  const VENCE_MS = 30 * 24 * 3600 * 1000;
  const MAX_REINTENTOS_FONDO = 5;
  const ESPERA_REINTENTO_MS = 60000;
  const ESPERA_LARGA_MS = 180000;
  const TIPOS_APARATO = ['brazo', 'muneca', 'reloj_anillo_otro'];
  const TIPOS_SESION = ['estandar', 'bajo_efecto', 'suelta', 'ortostatica', 'comparacion_brazos'];
  const GUIADAS = ['ortostatica', 'comparacion_brazos'];
  const MEDIDA_MIN = 20, MEDIDA_MAX = 70;

  // ── Almacén en memoria: fallback y pruebas ──
  function almacenMemoria() {
    const cola = new Map(), kv = new Map();
    return {
      persistente: false,
      async leerKV(k) { return kv.has(k) ? JSON.parse(kv.get(k)) : undefined; },
      async guardarKV(k, v) { kv.set(k, JSON.stringify(v)); },
      async borrarKV(k) { kv.delete(k); },
      async poner(fila) { cola.set(fila.id, JSON.stringify(fila)); },
      async sacar(id) { cola.delete(id); },
      async listar() { return [...cola.values()].map((s) => JSON.parse(s)); },
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
    // iOS puede cerrar la conexión con la pestaña de fondo: se reabre una vez.
    const con = async (fn) => {
      try { return await fn(d); } catch (e) {
        if (!e || e.name !== 'InvalidStateError') throw e;
        d = await abrirIDB(idb);
        vigilar();
        return fn(d);
      }
    };
    const escribir = (almacen, f) => con(async (b) => { const t = b.transaction(almacen, 'readwrite'); f(t.objectStore(almacen)); await fin(t); });
    return {
      persistente: true,
      leerKV: (k) => con(async (b) => { const r = await promesa(b.transaction('kv').objectStore('kv').get(k)); return r ? r.v : undefined; }),
      guardarKV: (k, v) => escribir('kv', (s) => s.put({ k, v })),
      borrarKV: (k) => escribir('kv', (s) => s.delete(k)),
      poner: (fila) => escribir('cola', (s) => s.put(fila)),
      sacar: (id) => escribir('cola', (s) => s.delete(id)),
      listar: () => con((b) => promesa(b.transaction('cola').objectStore('cola').getAll())),
    };
  }
  /* IndexedDB si se puede; si no, memoria. Nunca falla. */
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

  // ── Decodificar: todo campo es opcional y lo desconocido se ignora ──
  const num = (x) => (typeof x === 'number' && Number.isFinite(x) ? x : null);
  const txt = (x) => (typeof x === 'string' && x ? x : null);
  const obj = (x) => (x && typeof x === 'object' && !Array.isArray(x) ? x : null);
  const lista = (x) => (Array.isArray(x) ? x : []);

  /** La fecha local (AAAA-MM-DD) de un instante en una zona IANA. */
  function fechaLocal(ms, zona) {
    try {
      const p = new Intl.DateTimeFormat('en-CA', { timeZone: zona || undefined, year: 'numeric', month: '2-digit', day: '2-digit' }).formatToParts(new Date(ms));
      const v = (t) => p.find((x) => x.type === t).value;
      return `${v('year')}-${v('month')}-${v('day')}`;
    } catch (_) {
      return new Date(ms).toISOString().slice(0, 10);
    }
  }

  function decodificarAparato(j) {
    const a = obj(j);
    if (!a || TIPOS_APARATO.indexOf(a.tipo) === -1) return null;
    return {
      id: txt(a.id), tipo: a.tipo, marca: txt(a.marca), modelo: txt(a.modelo), modelo_codigo: txt(a.modelo_codigo),
      manguito_min_cm: num(a.manguito_min_cm), manguito_max_cm: num(a.manguito_max_cm),
      manguito_validado_min_cm: num(a.manguito_validado_min_cm), manguito_validado_max_cm: num(a.manguito_validado_max_cm),
      validado: a.validado === 'si' || a.validado === 'no' ? a.validado : 'sin_revisar',
    };
  }
  function decodificarToma(j) {
    const t = obj(j);
    if (!t || num(t.sis) === null || num(t.dia) === null) return null;
    return { orden: num(t.orden) || 0, posicion: txt(t.posicion) || 'sentado', sis: t.sis, dia: t.dia, pulso: num(t.pulso), latido_irregular: t.latido_irregular === true };
  }
  function decodificarSesion(j) {
    const s = obj(j);
    if (!s || !txt(s.id)) return null;
    const tomas = lista(s.tomas).map(decodificarToma).filter(Boolean).sort((a, b) => a.orden - b.orden);
    return { id: s.id.toLowerCase(), serie_id: txt(s.serie_id), fecha: txt(s.fecha), tipo: TIPOS_SESION.indexOf(s.tipo) !== -1 ? s.tipo : 'suelta', cuenta: s.cuenta === true, tomas };
  }
  function decodificarSerie(j) {
    const s = obj(j);
    if (!s) return null;
    const objetivo = num(s.tomas_objetivo) || 3;
    const dias = lista(s.dias).filter((d) => typeof d === 'string');
    const faltan = num(s.faltan);
    return {
      id: txt(s.id), motivo: txt(s.motivo), tipo: s.tipo === 'bajo_efecto' ? 'bajo_efecto' : 'estandar', estado: txt(s.estado) || 'pendiente',
      tomas_objetivo: objetivo, fecha_inicio: txt(s.fecha_inicio), fecha_limite: txt(s.fecha_limite), brazo: s.brazo === 'der' ? 'der' : 'izq',
      ortostatica: s.ortostatica === 'acostado_parado' || s.ortostatica === 'sentado_parado' ? s.ortostatica : null,
      comparar_brazos: s.comparar_brazos === true, medida_pedida: s.medida_pedida === true,
      dias, faltan: faltan === null ? Math.max(0, objetivo - dias.length) : Math.max(0, faltan),
    };
  }
  function decodificarTensiometros(j) {
    const t = obj(j), tr = t && obj(t.tramos);
    if (!tr) return null;
    const tramos = {};
    for (const k of ['estandar', 'grande', 'extra_grande', 'mas_52']) {
      tramos[k] = lista(tr[k]).map(obj).filter((x) => x && txt(x.nombre)).map((x) => ({ nombre: x.nombre, codigo: txt(x.codigo), pais: txt(x.pais), nota: txt(x.nota) }));
    }
    return { version: t.version == null ? null : String(t.version), tramos };
  }
  /** El estado de `mypump_presion_get`, o null si no le toca (apagado, token caído o respuesta rara). */
  function decodificarEstado(j) {
    const e = obj(j);
    if (!e || e.habilitado !== true) return null;
    const p = obj(e.pendiente);
    return {
      habilitado: true, fotos: e.fotos === true, hoy: txt(e.hoy),
      aparato: decodificarAparato(e.aparato),
      circunferencia_brazo_cm: num(e.circunferencia_brazo_cm),
      serie: decodificarSerie(e.serie),
      sesiones: lista(e.sesiones).map(decodificarSesion).filter(Boolean),
      pendiente: p && txt(p.sesion_id) ? { sesion_id: p.sesion_id.toLowerCase(), nivel: p.nivel === 'urgencia' ? 'urgencia' : 'alta', desde: txt(p.desde) } : null,
      tensiometros: decodificarTensiometros(e.tensiometros),
    };
  }

  const sinServidor = (r) => !r.ok && (r.status === 404 || r.codigo === 'PGRST202');
  const copia = (x) => JSON.parse(JSON.stringify(x));
  const medidaValida = (cm) => typeof cm === 'number' && Number.isFinite(cm) && cm >= MEDIDA_MIN && cm <= MEDIDA_MAX;
  /** «38,5» o «38.5» → 38.5 con un decimal; null si no es un número. */
  function leerMedida(s) {
    const n = Number(String(s == null ? '' : s).trim().replace(',', '.'));
    return String(s == null ? '' : s).trim() && Number.isFinite(n) ? Math.round(n * 10) / 10 : null;
  }

  /* deps: { rpc(fn, params) → {ok:true,data} | {ok:false,status,codigo,clase}, almacen, token, zona, plataforma, appVersion,
             esperar(ms), ahora(), nuevoId(), conLock(fn), visible() } */
  class ModeloPresion {
    constructor(deps) {
      this.rpc = deps.rpc;
      this.almacen = deps.almacen;
      this.token = deps.token;
      this.zona = deps.zona || (() => { try { return Intl.DateTimeFormat().resolvedOptions().timeZone || 'UTC'; } catch (_) { return 'UTC'; } })();
      this.plataforma = deps.plataforma || 'web';
      this.appVersion = deps.appVersion || null;
      this.esperar = deps.esperar || ((ms) => new Promise((r) => setTimeout(r, ms)));
      this.ahora = deps.ahora || (() => Date.now());
      this.nuevoId = deps.nuevoId || uuid;
      this.conLock = deps.conLock || ((fn) => fn());
      this.visible = deps.visible || (() => typeof document === 'undefined' || document.visibilityState === 'visible');
      this.cuenta = cuentaDe(this.token);

      this.estado = null;       // null: apagado, sin el servidor nuevo o sin red la primera vez
      this.cola = [];           // { id, cuenta, clase: 'sesion' | 'sintoma', cuerpo, creado, rev }
      this.curso = null;        // la sesión en curso (ver `empezar`)
      this.alCambiar = () => {};

      this._drenando = false;
      this._otraPasada = false;
      this._reintentoProgramado = false;
      this._reintentosDeFondo = 0;
    }

    get _kvEstado() { return `estado:${this.cuenta}`; }
    get _kvCurso() { return `curso:${this.cuenta}`; }
    _avisar() { try { this.alCambiar(); } catch (_) {} }
    _iso(ms) { return new Date(ms === undefined ? this.ahora() : ms).toISOString(); }

    async cargar() {
      let filas = [];
      try { filas = await this.almacen.listar(); } catch (_) {}
      const ahora = this.ahora();
      for (const f of filas) {
        if ((f.creado || 0) < ahora - VENCE_MS) { try { await this.almacen.sacar(f.id); } catch (_) {} }
      }
      this.cola = filas.filter((f) => f.cuenta === this.cuenta && (f.creado || 0) >= ahora - VENCE_MS).sort((a, b) => (a.creado || 0) - (b.creado || 0));
      let c;
      try { c = await this.almacen.leerKV(this._kvCurso); } catch (_) {}
      // Una sesión de otro día ya no se retoma: lo anotado quedó en la cola.
      if (c && c.sesion && fechaLocal(Date.parse(c.sesion.inicio), this.zona) === this.hoy) this.curso = c;
      else if (c) this._olvidarCurso();
    }

    // ── Lo que lee la pantalla ──
    get visibleEntrada() { return !!this.estado; }
    get hoy() { return (this.estado && this.estado.hoy) || fechaLocal(this.ahora(), this.zona); }
    get enCola() { return this.cola.length; }
    get metodo() { return P.metodo(this.estado ? this.estado.circunferencia_brazo_cm : null, this.estado ? this.estado.aparato : null); }
    apagar() { this.estado = null; }

    /** Las sesiones para «Tus tomas»: las del servidor y las que todavía esperan en el teléfono, la más nueva primero. */
    get sesiones() {
      const e = this.estado;
      if (!e) return [];
      const vistas = new Map(e.sesiones.map((s) => [s.id, s]));
      const locales = this.cola.filter((f) => f.clase === 'sesion').map((f) => f.cuerpo);
      if (this.curso && this.curso.sesion.tomas.length) locales.push(this.curso.sesion);
      for (const s of locales) {
        const prev = vistas.get(s.id);
        if (prev && prev.tomas.length >= s.tomas.length) continue;
        vistas.set(s.id, { id: s.id, serie_id: s.serie_id || null, fecha: fechaLocal(Date.parse(s.inicio), this.zona), tipo: s.tipo, cuenta: false, tomas: s.tomas.map(decodificarToma).filter(Boolean), _inicio: s.inicio });
      }
      return [...vistas.values()].filter((s) => s.tomas.length).sort((a, b) => (a.fecha === b.fecha ? 0 : a.fecha < b.fecha ? 1 : -1));
    }

    /** La serie con lo que todavía no confirmó el servidor: una toma en cola que cuenta ya suma su día. */
    get serie() { return this._serieVista(null); }
    _serieVista(sinId) {
      const s = this.estado && this.estado.serie;
      if (!s) return null;
      const dias = s.dias.slice();
      let comparar = s.comparar_brazos, orto = s.ortostatica;
      for (const f of this.cola) {
        if (f.clase !== 'sesion' || f.id === sinId || f.cuerpo.serie_id !== s.id) continue;
        const c = f.cuerpo, dia = fechaLocal(Date.parse(c.inicio), this.zona);
        if (c.tipo === 'comparacion_brazos' && c.tomas.length >= 4) comparar = false;
        if (c.tipo === 'ortostatica' && c.tomas.length >= 3) orto = null;
        if (f.reconstruida || dias.indexOf(dia) !== -1 || dias.length >= s.tomas_objetivo) continue;
        const ev = P.evaluarSesion(c);
        if (s.tipo === 'bajo_efecto' ? ev.valida_bajo_efecto : ev.cuenta) dias.push(dia);
      }
      const nuevos = dias.length - s.dias.length;
      return { ...s, dias, faltan: Math.max(0, s.faltan - nuevos), comparar_brazos: comparar, ortostatica: orto };
    }

    get hoyListo() { const s = this.serie; return !!s && s.dias.indexOf(this.hoy) !== -1; }

    /**
     * La repetición que quedó sin hacer: la de la sesión en curso (espera vencida) o la que avisa el servidor.
     * → null | { sesion_id, nivel, local, conLista }
     */
    get pendiente() {
      const c = this.curso;
      if (c && c.etapa === 'espera') return { sesion_id: c.sesion.id, nivel: c.lista ? 'urgencia' : 'alta', local: true, conLista: !!c.lista && c.sesion.lista_espera === null };
      if (c) return null;
      const p = this.estado && this.estado.pendiente;
      return p ? { sesion_id: p.sesion_id, nivel: p.nivel, local: false, conLista: p.nivel === 'urgencia' } : null;
    }

    /**
     * La tarjeta de arriba en la primera pestaña (CONTRATO_APP.md, «Fácil de encontrar»). Es una tarjeta más: no frena ni
     * condiciona la rutina. → null | { estado: 'repetir' | 'preparar' | 'toma' | 'hoyListo', hechas, total, faltan, primera }
     */
    get tarjeta() {
      if (!this.estado) return null;
      if (this.pendiente) return { estado: 'repetir' };
      const s = this.serie;
      if (!s) return null;
      const total = s.tomas_objetivo, hechas = Math.max(0, Math.min(total, total - s.faltan));
      const base = { hechas, total, faltan: s.faltan, primera: hechas === 0 };
      if (!this.estado.aparato || !this.metodo.admite_tomas || s.medida_pedida) return { estado: 'preparar', ...base };
      if (this.hoyListo) return { estado: 'hoyListo', ...base };
      if (s.faltan <= 0) return null;
      return { estado: 'toma', ...base };
    }

    // ── Servidor ──
    async refrescar(previa) {
      const r = previa || await this.rpc('mypump_presion_get', { p_token: this.token, p_zona: this.zona });
      if (r.ok) {
        const e = decodificarEstado(r.data);
        if (r.data === null || r.data === undefined) { this.estado = null; this._avisar(); return; }     // token caído: no se olvida nada
        if (!e) { this.apagar(); this._olvidarEstado(); this._avisar(); return; }
        await this._aplicar(r.data, e);
      } else if (sinServidor(r) || r.clase === 'permanente') {
        this.apagar();
        this._olvidarEstado();
      } else if (!this.estado) {
        // Sin red: lo último que se supo, para poder anotar una toma igual.
        let j;
        try { j = await this.almacen.leerKV(this._kvEstado); } catch (_) {}
        const e = j ? decodificarEstado(j) : null;
        if (e) this.estado = e;
      }
      this._avisar();
    }

    async _aplicar(crudo, decodificado) {
      const e = decodificado || decodificarEstado(crudo);
      if (!e) return false;
      this.estado = e;
      try { await this.almacen.guardarKV(this._kvEstado, crudo); } catch (_) {}
      return true;
    }
    _olvidarEstado() { this.almacen.borrarKV(this._kvEstado).catch(() => {}); }

    /* Aparato y medida no van a la cola: se guardan con señal. → 'ok' | 'sinSenal' | 'error' */
    async _guardar(fn, params) {
      let r;
      try { r = await this.rpc(fn, params); } catch (_) { r = { ok: false, clase: 'red' }; }
      if (!r.ok) {
        if (sinServidor(r)) { this.apagar(); this._olvidarEstado(); this._avisar(); return 'error'; }
        return r.clase === 'permanente' ? 'error' : 'sinSenal';
      }
      const j = obj(r.data);
      if (!j) return 'sinSenal';            // token caído
      if (j.ok !== true) return 'error';
      if (!(await this._aplicar(j.estado))) await this.refrescar();
      this._avisar();
      return 'ok';
    }
    guardarAparato(a) {
      if (!a || TIPOS_APARATO.indexOf(a.tipo) === -1) return Promise.resolve('error');
      const limpio = (s) => { const v = String(s == null ? '' : s).trim(); return v ? v.slice(0, 80) : null; };
      return this._guardar('mypump_presion_aparato', { p_token: this.token, p_aparato: {
        tipo: a.tipo, marca: limpio(a.marca), modelo: limpio(a.modelo), modelo_codigo: limpio(a.modelo_codigo),
        manguito_min_cm: num(a.manguito_min_cm), manguito_max_cm: num(a.manguito_max_cm),
      } });
    }
    guardarMedida(cm) {
      if (!medidaValida(cm)) return Promise.resolve('error');
      return this._guardar('mypump_presion_medida', { p_token: this.token, p_cm: Math.round(cm * 10) / 10, p_zona: this.zona });
    }

    // ── La sesión en curso ──
    /* curso = { sesion (el cuerpo que viaja), etapa, fin (ms en que termina la espera), lista (la espera lleva la lista de alarma),
                 respuestas {codigo: 'si'|'no'}, paso (índice en `pasos`), pasos, variante, guardia ('presion'|'sintomas'), cierre, reconstruida }
       etapas: previas → reposo → anotar → (sintomas) → espera → anotar … → listo | guardia
               guiadas: intro → reposo → anotar → (parate) → reposo → anotar … → listo */
    async _guardarCurso() {
      try {
        if (this.curso) await this.almacen.guardarKV(this._kvCurso, this.curso);
        else await this.almacen.borrarKV(this._kvCurso);
      } catch (_) {}
    }
    _olvidarCurso() { this.curso = null; this.almacen.borrarKV(this._kvCurso).catch(() => {}); }

    /** tipo: 'estandar' | 'bajo_efecto' | 'suelta' | 'ortostatica' | 'comparacion_brazos'. Con serie, queda atada a ella. */
    async empezar(tipo) {
      if (!this.estado || !this.metodo.admite_tomas || TIPOS_SESION.indexOf(tipo) === -1) return false;
      const serie = tipo === 'suelta' ? null : this.serie;
      const variante = tipo === 'ortostatica' ? ((serie && serie.ortostatica) || 'acostado_parado') : null;
      const ahora = this.ahora();
      this.curso = {
        sesion: {
          id: String(this.nuevoId()).toLowerCase(), serie_id: serie ? serie.id : null, tipo,
          inicio: this._iso(ahora), zona_horaria: this.zona, brazo: serie ? serie.brazo : 'izq',
          previo: { cafeina: null, fumo: null, comida: null, ejercicio: null },
          reposo_cumplido: false, temporizador_salteado: false,
          dosis_estimulante_hora: null, entreno_entre_dosis_y_toma: null,
          sintomas: [], lista_espera: null, nota: null, texto_alumno: 'ninguno',
          app_version: this.appVersion, plataforma: this.plataforma, tomas: [],
        },
        etapa: GUIADAS.indexOf(tipo) !== -1 ? 'intro' : 'previas',
        fin: null, lista: false, respuestas: {}, paso: 0, pasos: P.pasos(tipo, variante), variante, guardia: null, cierre: null, reconstruida: false,
      };
      await this._guardarCurso();
      this._avisar();
      return true;
    }

    /** Retoma la repetición que avisa el servidor cuando la sesión no está en este teléfono: solo viaja lo que se sabe. */
    async retomarDelServidor() {
      const p = this.estado && this.estado.pendiente;
      if (!p || this.curso) return false;
      const s = this.estado.sesiones.find((x) => x.id === p.sesion_id);
      const ahora = this.ahora();
      this.curso = {
        sesion: {
          id: p.sesion_id, serie_id: s ? s.serie_id : null, tipo: s ? s.tipo : 'suelta', inicio: p.desde || this._iso(ahora), zona_horaria: this.zona,
          sintomas: [], lista_espera: null, texto_alumno: 'repetir_pendiente', app_version: this.appVersion, plataforma: this.plataforma,
          tomas: (s ? s.tomas : []).map((t) => ({ ...t })),
        },
        etapa: 'anotar', fin: null, lista: false, respuestas: {}, paso: 0, pasos: P.pasos('suelta'), variante: null, guardia: null, cierre: null, reconstruida: true,
      };
      await this._guardarCurso();
      this._avisar();
      return true;
    }

    /** Segundos que faltan de la espera en curso (0 si terminó o no hay). */
    restante() {
      const c = this.curso;
      if (!c || !c.fin) return 0;
      return Math.max(0, Math.ceil((c.fin - this.ahora()) / 1000));
    }
    minutosDesdeUltima() {
      const c = this.curso, t = c && c.sesion.tomas[c.sesion.tomas.length - 1];
      const ms = t && t.medido_en ? Date.parse(t.medido_en) : NaN;
      return Number.isFinite(ms) ? Math.max(0, Math.floor((this.ahora() - ms) / 60000)) : 0;
    }
    /** Pasados los 10 minutos sin repetir, la espera se muestra como recordatorio en el inicio. */
    get esperaVencida() {
      const c = this.curso;
      return !!c && c.etapa === 'espera' && this.minutosDesdeUltima() >= P.RECORDATORIO_MIN;
    }

    /** Estándar y suelta: las 4 preguntas. Con algún Sí la toma queda marcada (no cuenta). */
    async responderPrevias(previo) {
      const c = this.curso;
      if (!c || c.etapa !== 'previas') return;
      for (const k of Object.keys(c.sesion.previo)) c.sesion.previo[k] = previo[k] === true;
      await this._aReposo();
    }
    /** Bajo efecto: a qué hora tomó el estimulante (HH:MM local) y si entrenó entre la dosis y la toma. */
    async responderBajoEfecto(hora, entreno) {
      const c = this.curso;
      if (!c || c.etapa !== 'previas') return;
      c.sesion.dosis_estimulante_hora = /^\d{2}:\d{2}$/.test(String(hora || '')) ? hora : null;
      c.sesion.entreno_entre_dosis_y_toma = entreno === true;
      await this._aReposo();
    }
    /** Guiadas: arranca la espera del paso (el reposo, o el reloj de estar parado). */
    async empezarPaso() {
      const c = this.curso;
      if (!c || (c.etapa !== 'intro' && c.etapa !== 'parate')) return;
      await this._aReposo();
    }
    async _aReposo(desde) {
      const c = this.curso;
      c.etapa = 'reposo';
      c.fin = (desde || this.ahora()) + c.pasos[c.paso].espera_s * 1000;
      await this._guardarCurso();
      this._avisar();
    }
    /** «Ya esperé»: mide sin el temporizador. Solo en el reposo de la toma sentado. */
    async saltearReposo() {
      const c = this.curso;
      if (!c || c.etapa !== 'reposo' || GUIADAS.indexOf(c.sesion.tipo) !== -1) return;
      c.sesion.temporizador_salteado = true;
      c.sesion.reposo_cumplido = false;
      c.etapa = 'anotar';
      await this._guardarCurso();
      this._avisar();
    }
    /** Lo llama la pantalla cuando el reloj llega a cero. → true si cambió de etapa. */
    async tiempoCumplido() {
      const c = this.curso;
      if (!c || c.etapa !== 'reposo' || this.restante() > 0) return false;
      if (c.paso === 0 && !c.sesion.temporizador_salteado) c.sesion.reposo_cumplido = true;
      c.etapa = 'anotar';
      await this._guardarCurso();
      this._avisar();
      return true;
    }
    /** Terminó la espera de la repetición: a anotar la toma que sigue. */
    async repetir() {
      const c = this.curso;
      if (!c || c.etapa !== 'espera' || this.restante() > 0) return false;
      c.etapa = 'anotar';
      await this._guardarCurso();
      this._avisar();
      return true;
    }

    /**
     * Anota una toma. → 'imposible' | 'confirmar' (falta `confirmada`) | 'sintomas' (se abre la hoja antes de evaluar) | la etapa que sigue.
     * El número se guarda y se manda antes de preguntar nada más.
     */
    async anotar(toma, confirmada) {
      const c = this.curso;
      if (!c || c.etapa !== 'anotar') return 'imposible';
      const t = { sis: toma.sis, dia: toma.dia, pulso: toma.pulso };
      const v = P.validarToma(t);
      if (v === 'imposible') return 'imposible';
      if (v === 'confirmar' && !confirmada) return 'confirmar';
      const paso = c.pasos[c.paso] || c.pasos[0];
      c.sesion.tomas.push({
        orden: c.sesion.tomas.reduce((m, x) => Math.max(m, x.orden || 0), 0) + 1,
        posicion: paso.posicion, minutos_de_pie: paso.minutos_de_pie, brazo: paso.brazo || c.sesion.brazo || null,
        sis: t.sis, dia: t.dia, pulso: t.pulso, latido_irregular: toma.latido_irregular === true,
        medido_en: this._iso(), confirmada_por_alumno: v === 'confirmar',
      });
      c.finAnterior = c.fin;
      c.fin = null;
      if (t.pulso >= 120 || t.pulso <= 40 || t.sis < 90) {
        c.etapa = 'sintomas';
        await this._encolarSesion();
        this._avisar();
        this.drenar().catch(() => {});
        return 'sintomas';
      }
      return this._evaluar();
    }

    /** La hoja de síntomas que se abre sola después de una toma (pulso de 120 o más, de 40 o menos, o alta menor de 90). */
    async responderSintomas(codigos, nota) {
      const c = this.curso;
      if (!c || c.etapa !== 'sintomas') return null;
      this._sumarSintomas(codigos, nota);
      return this._evaluar();
    }
    _sumarSintomas(codigos, nota) {
      const s = this.curso.sesion;
      for (const k of codigos || []) if (P.SINTOMAS[k] && s.sintomas.indexOf(k) === -1) s.sintomas.push(k);
      const n = String(nota == null ? '' : nota).trim().slice(0, 500);
      if (n) s.nota = n;
    }

    /** Sí o No en una fila de la lista de la espera. Un Sí es guardia en el acto; con las 8 en No la lista queda contestada. */
    async responderLista(codigo, valor) {
      const c = this.curso;
      if (!c || c.etapa !== 'espera' || !c.lista || P.ALARMA.indexOf(codigo) === -1) return c ? c.etapa : null;
      c.respuestas[codigo] = valor === true ? 'si' : 'no';
      if (valor === true) {
        c.sesion.lista_espera = 'si';
        this._sumarSintomas([codigo]);
        return this._evaluar();
      }
      if (P.ALARMA.every((k) => c.respuestas[k] === 'no')) {
        c.sesion.lista_espera = 'no';
        await this._encolarSesion();
        this.drenar().catch(() => {});
      } else await this._guardarCurso();
      this._avisar();
      return c.etapa;
    }

    /** «Me mareé» en la ortostática: se corta ahí, sin terminar. */
    async meMaree() {
      const c = this.curso;
      if (!c || c.sesion.tipo !== 'ortostatica') return;
      this._sumarSintomas(['mareo_al_pararse']);
      c.cierre = { mareo: true };
      c.sesion.texto_alumno = 'quedate_sentado_ortostatica';
      c.etapa = 'listo';
      c.fin = null;
      if (c.sesion.tomas.length) await this._encolarSesion();
      else { await this._encolarSintoma({ contexto: 'boton', sesion_id: null, codigos: ['mareo_al_pararse'], sin_sintomas_en_lista: null, nota: null }); await this._guardarCurso(); }
      this._avisar();
      this.drenar().catch(() => {});
    }

    /* Decide lo que sigue con `evaluarSesion`, sin esperar al servidor. → la etapa nueva */
    async _evaluar() {
      const c = this.curso, s = c.sesion;
      const ev = P.evaluarSesion({ ...s, minutos_desde_ultima: 0 });
      s.texto_alumno = ev.texto;
      const guiada = GUIADAS.indexOf(s.tipo) !== -1;
      if (ev.paso === 'guardia_presion' || ev.paso === 'guardia_sintomas') {
        c.etapa = 'guardia';
        c.guardia = ev.paso === 'guardia_presion' ? 'presion' : 'sintomas';
        c.fin = null;
      } else if (ev.paso === 'repetir' || ev.paso === 'repetir_con_lista') {
        c.etapa = 'espera';
        c.lista = ev.paso === 'repetir_con_lista' && s.lista_espera !== 'no';
        c.respuestas = {};
        c.fin = this.ahora() + P.ESPERA_REPETICION_S * 1000;
      } else if (guiada && c.paso < c.pasos.length - 1) {
        c.paso += 1;
        if (s.tipo === 'ortostatica' && c.paso === 1) c.etapa = 'parate';       // se para y recién ahí corre el reloj
        // El minuto 3 se cuenta desde que se paró, no desde que terminó de anotar.
        else { await this._aReposo(s.tipo === 'ortostatica' && c.finAnterior ? Math.max(c.finAnterior, this.ahora() - c.pasos[c.paso].espera_s * 1000) : undefined); }
      } else {
        const serie = this._serieVista(s.id);
        const suma = !c.reconstruida && serie && s.serie_id === serie.id && (serie.tipo === 'bajo_efecto' ? ev.valida_bajo_efecto : ev.cuenta) && serie.dias.indexOf(this.hoy) === -1;
        c.etapa = 'listo';
        c.cierre = {
          noCuenta: !c.reconstruida && ev.texto === 'toma_no_cuenta', agua: ev.texto === 'sentate_agua',
          mareo: ev.texto === 'quedate_sentado_ortostatica',
          irregular: s.tomas.some((t) => t.latido_irregular === true),
          completa: !!suma && serie.faltan <= 1,
        };
      }
      await this._encolarSesion();
      this._avisar();
      this.drenar().catch(() => {});
      return c.etapa;
    }

    /** Cierra la sesión en curso (lo anotado ya está en la cola). */
    async cerrar() { this._olvidarCurso(); this._avisar(); }
    /** «Esperar» en las preguntas previas: no se anotó nada, no queda nada. */
    async descartar() {
      if (this.curso && this.curso.sesion.tomas.length) return;
      this._olvidarCurso();
      this._avisar();
    }

    // ── Síntomas fuera de una toma ──
    /** El botón «Marcar un síntoma». Medir nunca es condición. → 'guardia' | 'recibido' */
    async marcarSintoma(codigos, nota) {
      const validos = (codigos || []).filter((k) => P.SINTOMAS[k]);
      const n = String(nota == null ? '' : nota).trim().slice(0, 500) || null;
      const c = this.curso;
      const conToma = !!c && c.sesion.tomas.length > 0 && c.etapa !== 'guardia' && c.etapa !== 'listo';
      await this._encolarSintoma({ contexto: 'boton', sesion_id: conToma ? c.sesion.id : null, codigos: validos, sin_sintomas_en_lista: null, nota: n });
      const alarma = P.deAlarma(validos);
      if (conToma) {
        // Hay una toma en curso: los síntomas también van con ella y deciden el paso.
        this._sumarSintomas(validos, n);
        // También un pulso de urgencia con palpitaciones o mareo es guardia: lo decide la misma regla.
        if (P.evaluarSesion({ ...c.sesion, minutos_desde_ultima: 0 }).paso === 'guardia_sintomas') { await this._evaluar(); return 'guardia'; }
        await this._encolarSesion();
      } else if (alarma && c && !c.sesion.tomas.length) this._olvidarCurso();
      this._avisar();
      this.drenar().catch(() => {});
      return alarma ? 'guardia' : 'recibido';
    }

    /** La lista del recordatorio cuando la sesión no está en este teléfono. → 'guardia' | 'sigue' | 'falta' */
    async responderRecordatorio(respuestas) {
      const p = this.estado && this.estado.pendiente;
      if (!p) return 'falta';
      const si = P.ALARMA.filter((k) => respuestas[k] === 'si');
      const todosNo = P.ALARMA.every((k) => respuestas[k] === 'no');
      if (!si.length && !todosNo) return 'falta';
      await this._encolarSintoma({ contexto: 'recordatorio_180_120', sesion_id: p.sesion_id, codigos: si, sin_sintomas_en_lista: todosNo, nota: null });
      this._avisar();
      this.drenar().catch(() => {});
      return si.length ? 'guardia' : 'sigue';
    }

    // ── Cola ──
    async _poner(fila) {
      const i = this.cola.findIndex((f) => f.id === fila.id);
      if (i === -1) this.cola.push(fila); else this.cola[i] = fila;
      try { await this.almacen.poner(fila); } catch (_) {}        // sin lugar: sigue en memoria mientras la pestaña esté abierta
    }
    async _encolarSesion() {
      const c = this.curso;
      const prev = this.cola.find((f) => f.id === c.sesion.id);
      await this._poner({ id: c.sesion.id, cuenta: this.cuenta, clase: 'sesion', cuerpo: copia(c.sesion), creado: prev ? prev.creado : this.ahora(), rev: (prev ? prev.rev : 0) + 1, reconstruida: c.reconstruida === true });
      await this._guardarCurso();
      this._reintentosDeFondo = 0;
    }
    async _encolarSintoma(d) {
      const id = String(this.nuevoId()).toLowerCase();
      await this._poner({ id, cuenta: this.cuenta, clase: 'sintoma', cuerpo: { id, marcado_en: this._iso(), zona_horaria: this.zona, ...d }, creado: this.ahora(), rev: 1 });
      this._reintentosDeFondo = 0;
    }
    async _sacar(id) {
      this.cola = this.cola.filter((f) => f.id !== id);
      try { await this.almacen.sacar(id); } catch (_) {}
    }

    /** Al volver al frente y al abrir la pantalla. */
    reanudar() { this._reintentosDeFondo = 0; return this.drenar().catch(() => {}); }

    /* Una pasada a la vez, con el lock de las pestañas: dos pestañas no mandan lo mismo a la vez (y si pasara, el servidor lo toma por id). */
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

    async _pasada() {
      let refrescar = false;
      while (this.estado && this.cola.length) {
        const f = this.cola[0], rev = f.rev;
        let r;
        try {
          r = f.clase === 'sintoma'
            ? await this.rpc('mypump_presion_sintoma', { p_token: this.token, p_sintoma: f.cuerpo })
            : await this.rpc('mypump_presion_sesion', { p_token: this.token, p_sesion: f.cuerpo });
        } catch (_) { r = { ok: false, status: 0, codigo: 'NETWORK', clase: 'red' }; }
        if (!r.ok) {
          // Sin el servidor nuevo: se apaga y no se llama más. Lo anotado queda guardado hasta que venza.
          if (sinServidor(r)) { this.apagar(); this._olvidarEstado(); return; }
          if (r.clase === 'permanente') { await this._sacar(f.id); refrescar = true; continue; }       // 4xx que no es 429: no va a entrar nunca
          this._programarReintento();
          break;
        }
        const j = obj(r.data);
        if (!j) break;                                  // token caído: queda guardado por si vuelve
        const actual = this.cola.find((x) => x.id === f.id);
        if (j.ok !== true) { await this._sacar(f.id); refrescar = true; continue; }
        // Si mientras viajaba se anotó otra toma, la fila sigue y vuelve a salir con todo.
        if (!actual || actual.rev === rev) await this._sacar(f.id);
        if (j.estado && await this._aplicar(j.estado)) refrescar = false;
        else if (f.clase === 'sesion') refrescar = true;
      }
      if (refrescar && this.estado) await this.refrescar();
    }

    _programarReintento() {
      if (this._reintentoProgramado) return;
      const agotado = this._reintentosDeFondo >= MAX_REINTENTOS_FONDO;
      if (agotado && !(this.cola.length && this.visible())) return;
      this._reintentoProgramado = true;
      this._reintentosDeFondo += 1;
      this.esperar(agotado ? ESPERA_LARGA_MS : ESPERA_REINTENTO_MS).then(() => { this._reintentoProgramado = false; return this.drenar(); }).catch(() => {});
    }
  }

  /**
   * La única puerta: con la palanca apagada no se llama ni se crea nada. Prendida, primero se pregunta el estado
   * y recién con una cuenta habilitada se abre el almacén.
   * op: { palanca, rpc, token, abrirAlmacen?, ...deps } → ModeloPresion | null
   */
  async function arrancar(op) {
    if (op.palanca !== true || !op.token) return null;
    const zona = op.zona || (() => { try { return Intl.DateTimeFormat().resolvedOptions().timeZone || 'UTC'; } catch (_) { return 'UTC'; } })();
    let primera;
    try { primera = await op.rpc('mypump_presion_get', { p_token: op.token, p_zona: zona }); } catch (_) { primera = { ok: false, clase: 'red' }; }
    if (primera.ok ? !decodificarEstado(primera.data) : (sinServidor(primera) || primera.clase === 'permanente')) return null;
    const almacen = await (op.abrirAlmacen || abrirAlmacen)();
    const m = new ModeloPresion({ ...op, almacen, zona });
    // Sin red la primera vez solo sigue quien ya tenía un estado habilitado guardado.
    await m.refrescar(primera);
    if (!m.estado) return null;
    await m.cargar();
    return m;
  }

  const API = { ModeloPresion, arrancar, abrirAlmacen, almacenMemoria, decodificarEstado, fechaLocal, leerMedida, medidaValida, MEDIDA_MIN, MEDIDA_MAX };
  if (enNode) module.exports = API;
  else raiz.PresionCola = API;
})(typeof window !== 'undefined' ? window : globalThis);
