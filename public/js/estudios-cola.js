/* =============================================================
   estudios-cola.js — «Estudios y órdenes»: el modelo y la cola de subida.

   Misma lógica que ModeloEstudios de la app: `envio_nuevo` → cada archivo →
   `enviar`; un 5xx, un 429 o un corte no gastan el archivo y se reintenta con el
   mismo id; todo otro 4xx es definitivo para ese archivo; 401 no pierde nada.

   Son datos médicos y esto es un navegador: los archivos elegidos y lo que
   contesta el servidor viven SOLO en memoria de esta página. Nada se guarda en el
   navegador, y el token no viaja nunca en una URL ni se escribe en un registro.
   ============================================================= */
(function (raiz) {
  'use strict';

  const E = (typeof module !== 'undefined' && module.exports) ? require('./estudios.js') : raiz.Estudios;
  /* Las reglas del control de salud (js/controles.js). Sin ellas, sin controles. */
  const controlesApi = () => ((typeof module !== 'undefined' && module.exports) ? require('./controles.js') : raiz.Controles) || null;
  /* «AAAA-MM-DD» de hoy en el navegador (solo si el servidor no manda `hoy`). */
  const hoyLocal = () => { const d = new Date(); return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`; };

  const MAX_SEGUIDAS = 3;       // errores del servidor seguidos antes de cortar la pasada
  const MAX_FONDO = 5;          // pasadas solas (una por minuto) por envío
  const MAX_VUELTAS = 2;        // veces que un envío se abre o se sube de nuevo
  const ESPERA_FONDO_S = 60;
  const ESPERA_SUBIDA_MS = 180000;
  const ESPERA_URLS_MS = 30000;
  const ESPERA_BAJAR_MS = 120000;
  const IMAGEN = /^image\/(jpeg|png|webp|gif)$/;

  function uuid() {
    const c = typeof crypto !== 'undefined' ? crypto : null;
    if (c && c.randomUUID) return c.randomUUID();
    const b = new Uint8Array(16);
    c.getRandomValues(b);
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    const h = Array.from(b, (x) => x.toString(16).padStart(2, '0')).join('');
    return `${h.slice(0, 8)}-${h.slice(8, 12)}-${h.slice(12, 16)}-${h.slice(16, 20)}-${h.slice(20)}`;
  }

  /* Para no sumar dos veces los mismos bytes en un envío. null si este navegador no lo puede calcular. */
  async function sha256(blob) {
    const c = typeof crypto !== 'undefined' ? crypto.subtle : null;
    if (!c) return null;
    const d = await c.digest('SHA-256', blob.arrayBuffer ? await blob.arrayBuffer() : await new Response(blob).arrayBuffer());
    return Array.from(new Uint8Array(d), (x) => x.toString(16).padStart(2, '0')).join('');
  }

  async function conLimite(ms, hacer) {
    const ctrl = typeof AbortController !== 'undefined' ? new AbortController() : null;
    const reloj = ctrl ? setTimeout(() => ctrl.abort(), ms) : null;
    try { return await hacer(ctrl ? ctrl.signal : undefined); } finally { if (reloj) clearTimeout(reloj); }
  }

  /* → { status, json } o null si se cortó. El token va en un encabezado; el cuerpo Blob lleva Content-Length solo. */
  function subirPorFetch(q) {
    return conLimite(ESPERA_SUBIDA_MS, async (signal) => {
      try {
        const res = await fetch(q.url, {
          method: 'POST', body: q.cuerpo, cache: 'no-store', credentials: 'omit', referrerPolicy: 'no-referrer', signal,
          headers: { 'Content-Type': q.mime, 'x-estudios-token': q.token, 'x-estudios-envio': q.envio, 'x-estudios-archivo': q.archivo },
        });
        let json = null;
        try { json = await res.json(); } catch (_) {}
        return { status: res.status, json };
      } catch (_) { return null; }
    });
  }

  /* Una URL firmada se abre solo si es https (o el doble local de las pruebas). */
  function urlSegura(s) {
    try {
      const u = new URL(s);
      return u.protocol === 'https:' || (u.protocol === 'http:' && (u.hostname === 'localhost' || u.hostname === '127.0.0.1'));
    } catch (_) { return false; }
  }

  /* deps: { rpc(fn, params) → {ok:true,data} | {ok:false,status,codigo,clase}, token, visionUrl,
             subir(pedido), fetch, esperar(segundos), nuevoId(), huella(blob), zona } */
  class ModeloEstudios {
    constructor(deps) {
      this.rpc = deps.rpc;
      this.token = deps.token;
      this.visionUrl = String(deps.visionUrl || '').replace(/\/$/, '');
      this.subir = deps.subir || subirPorFetch;
      this.fetch = deps.fetch || ((...a) => fetch(...a));
      this.esperar = deps.esperar || ((s) => new Promise((ok) => setTimeout(ok, s * 1000)));
      this.nuevoId = deps.nuevoId || uuid;
      this.huella = deps.huella || sha256;
      this.zona = deps.zona;

      /* null: apagado, sin el servidor nuevo, o todavía no se supo nada. No se muestra nada. Con un control de salud, su
         fecha alimenta el bloque «Próximo control» (`_componer`). */
      this.estado = null;
      /* Lo que devolvió `mypump_estudios_get`, tal cual. */
      this._crudo = null;
      /* Sube con cada pedido de controles y cada vez que dejan de valer: solo vale la respuesta del último pedido, y una que
         viajaba cuando se apagó la palanca o la sección se descarta. */
      this._vueltaCtl = 0;
      /* Los controles de salud (`mypump_controles_get`): null con `controles_app` apagada, sin la sección, con la función
         inexistente o `habilitado: false`. Como lo de estudios, no se guarda en el navegador. */
      this.controles = null;
      /* La palanca `controles_app` leída en esta carga. Sin leerla, apagada. */
      this.palancaControles = deps.controles === true;
      /* El último `get` falló por red o servicio y lo que se ve puede estar viejo. */
      this.errorDeCarga = false;
      /* Todavía no se supo si la cuenta tiene la sección: el `get` no llegó a contestar. */
      this.sinRespuesta = false;
      this.cola = [];
      this.borrador = [];
      this.sinSenal = false;
      this.subiendo = false;
      /* Quedó algo en la cola y la pasada se cortó sin que sea por señal: se ofrece probar de nuevo. */
      this.detenido = false;
      /* Cambia cada vez que se descarta lo elegido: una foto que se estaba convirtiendo para la hoja anterior no entra en la próxima. */
      this.hoja = 0;
      /* 'recibido' | 'recibidoConRechazo' | 'rechazado' | 'topeDia' | 'error' */
      this.aviso = null;
      this.alCambiar = null;

      this._drenando = false;
      this._reintento = false;
      this._fondo = 0;
      this._muerto = false;
      this._marcando = new Set();
    }

    _cambio() { if (this.alCambiar && !this._muerto) { try { this.alCambiar(); } catch (_) {} } }

    async _rpc(fn, params) {
      try { return await this.rpc(fn, { p_token: this.token, ...params }); } catch (_) { return { ok: false, status: 0, codigo: 'NETWORK', clase: 'red' }; }
    }

    // ── Lo que lee la pantalla ──
    get habilitado() { return !!this.estado; }
    get pendientes() { return this.estado ? this.estado.pendientes.length : 0; }
    /* La novedad de Estudios (título + destino) o null: el punto y el aviso de arriba salen de acá. */
    get novedad() { return E.novedadDeEstudios(this.estado); }
    get tarjetaInicio() { return E.tarjetaInicio(this.estado); }
    /* La tarjeta de arriba del control: desde `avisar_desde` y mientras siga programado. Con la fecha del servidor; si no la
       manda, la de Estudios y, si tampoco, la del navegador. */
    get tarjetaControl() {
      const C = controlesApi();
      return C && this.palancaControles && this.estado && this.controles ? C.tarjetaInicio(this.controles, (this._crudo && this._crudo.hoy) || E.dia(hoyLocal())) : null;
    }
    /* «Tu recorrido»: el próximo control y los últimos, con su fecha. */
    get hitosControl() { const C = controlesApi(); return C && this.palancaControles && this.estado && this.controles ? C.hitos(this.controles) : []; }
    get topeArchivos() { return this.estado ? this.estado.topeArchivos : E.TOPE_ARCHIVOS; }
    get topeMB() { return this.estado ? this.estado.topeMB : E.TOPE_MB; }
    get puedeAgregar() { return this.borrador.length < this.topeArchivos; }
    /* «Subiendo 2 de 5», del envío que está saliendo. */
    get progreso() {
      const e = this.cola[0];
      return e ? E.progreso(e.archivos.filter((a) => a.subido).length, e.archivos.length) : null;
    }
    orden(id) { return this.estado ? this.estado.ordenes.find((o) => o.id === id) || null : null; }
    limpiarAviso() { if (this.aviso) { this.aviso = null; this._cambio(); } }

    // ── Servidor ──
    /* Token caído, función inexistente o `habilitado: false`: la sección no existe. Sin red se queda con lo que ya se
       veía en esta visita (nada se guarda en el navegador) y avisa que no se pudo cargar. */
    async refrescar(primera) {
      const r = primera || await this._rpc('mypump_estudios_get', {});
      if (this._muerto) return;
      if (r.ok) {
        const e = E.decodificarEstado(r.data, this.zona);
        if (!e) return this.apagar();
        this._crudo = e;
        this.errorDeCarga = false;
        this.sinRespuesta = false;
        this._componer();              // Estudios no espera a los controles
        this._cambio();
        if (await this._refrescarControles() && !this._muerto) { this._componer(); this._cambio(); }
        return;
      } else if (r.status === 404 || r.codigo === 'PGRST202' || r.clase === 'permanente') {
        return this.apagar();
      } else {
        this.errorDeCarga = !!this.estado;
        this.sinRespuesta = !this.estado;
        this._cambio();
      }
    }

    /* `mypump_controles_get`, solo con la palanca y la sección a la vista (la tarjeta lleva ahí). Token caído,
       `habilitado: false`, una respuesta rara o la función inexistente: sin controles. Un corte deja lo de esta visita. */
    async _refrescarControles() {
      const C = controlesApi();
      if (!C || !this.palancaControles || !this._crudo) { const habia = !!this.controles; this.controles = null; return habia; }
      const vuelta = ++this._vueltaCtl;
      const r = await this._rpc('mypump_controles_get', {});
      // Se apagó la palanca o la sección mientras viajaba (o salió otro pedido después): esta respuesta ya es vieja.
      if (vuelta !== this._vueltaCtl || this._muerto || !this.palancaControles || !this._crudo) return false;
      if (r.ok) this.controles = C.decodificar(r.data);
      else if (r.status === 404 || r.codigo === 'PGRST202' || r.clase === 'permanente') this.controles = null;
      return true;
    }
    _componer() {
      const C = controlesApi();
      const pc = C && this.controles && this._crudo ? C.proximoParaEstudios(this.controles, this._crudo.ordenes.length > 0) : null;
      this.estado = this._crudo && pc ? { ...this._crudo, proximoControl: pc } : this._crudo;
    }
    /* Lo que dijo la config de `controles_app`. Apagada, el control deja de verse en el momento. */
    usarPalancaControles(prendida) {
      this.palancaControles = prendida === true;
      if (!this.palancaControles) { this._vueltaCtl++; if (this.controles) { this.controles = null; this._componer(); this._cambio(); } }
    }

    /* La sección deja de verse. La cola se conserva en memoria: si vuelve a estar habilitada, sale. */
    apagar() { this._vueltaCtl++; this.estado = null; this._crudo = null; this.controles = null; this.errorDeCarga = false; this.sinRespuesta = false; this._cambio(); }

    /* Palanca apagada: no queda nada, ni lo elegido. */
    cerrar() {
      this._vueltaCtl++; this.estado = null; this._crudo = null; this.controles = null; this.cola = []; this.borrador = []; this.aviso = null;
      this._muerto = true;
    }

    /* «Ya me lo hice» con su fecha (`AAAA-MM-DD`), o null para deshacerlo. → 'ok' | 'fecha' | 'sinSenal' | 'error' */
    async marcarHecho(pedidoId, fecha) {
      const r = await this._rpc('mypump_estudios_hecho', { p_pedido_id: pedidoId, p_fecha: fecha || null });
      if (!r.ok) return r.clase === 'permanente' ? 'error' : 'sinSenal';
      const j = r.data;
      if (!j || typeof j !== 'object') return 'error';
      if (j.ok === true) { await this.refrescar(); return 'ok'; }
      if (j.error === 'fecha') return 'fecha';
      if (j.error === 'no_encontrado') { await this.refrescar(); return 'ok'; }   // ya llegó o lo cerraron: vale lo del servidor
      if (j.error === 'no_habilitado') this.apagar();
      return 'error';
    }

    /* Las tarjetas nuevas que estuvieron de verdad en pantalla (ids de pedidos y de órdenes, mezclados). Solo apaga el
       «Nuevo»: el pendiente sigue. Apagada o cerrada la sección no se llama a nada. Si falla no se guarda ni se encola:
       sale de nuevo la próxima vez que la tarjeta esté a la vista. → cuántas quedaron apagadas acá */
    async marcarVistas(ids) {
      const s = this.estado;
      if (!s || this._muerto || this._sinVistas) return 0;
      const nuevas = new Set(s.pendientes.concat(s.ordenes).filter((x) => x.nuevo).map((x) => x.id));
      const l = Array.from(new Set(ids)).filter((id) => nuevas.has(id) && !this._marcando.has(id));
      if (!l.length) return 0;
      l.forEach((id) => this._marcando.add(id));
      let r;
      try { r = await this._rpc('mypump_estudios_novedades_vistas', { p_ids: l }); } finally { l.forEach((id) => this._marcando.delete(id)); }
      if (this._muerto) return 0;
      if (!r.ok) {
        // Un servidor sin la función: no se le insiste en esta visita.
        if (r.status === 404 || r.codigo === 'PGRST202') this._sinVistas = true;
        return 0;
      }
      const j = r.data;
      if (j === null || j === undefined) { await this.refrescar(); return 0; }      // token caído
      if (typeof j !== 'object') return 0;
      if (j.ok !== true) { if (j.error === 'no_habilitado') this.apagar(); return 0; }
      const n = this.estado ? E.apagarNuevas(this.estado, l) : 0;
      if (n) this._cambio();
      return n;
    }

    // ── Hoja de subida ──
    /* Suma un archivo a lo que se está por enviar. Las fotos ya llegan en JPEG (2400 px, 0,8, sin EXIF); el PDF, tal cual.
       → 'ok' | 'tope' | 'muyGrande' | 'ilegible' */
    async elegir(cuerpo, formato) {
      const hoja = this.hoja;
      const medir = () => E.puedeAgregar({ bytes: cuerpo ? cuerpo.size : 0, formato, yaHay: this.borrador.length, topeArchivos: this.topeArchivos, topeMB: this.topeMB });
      let r = medir();
      if (r !== 'ok') return r;
      let huella = null;
      try { huella = await this.huella(cuerpo); } catch (_) {}
      if (hoja !== this.hoja || this._muerto) return 'ok';
      r = medir();
      if (r !== 'ok') return r;
      if (huella && this.borrador.some((x) => x.huella === huella)) return 'ok';   // el mismo archivo dos veces: ya está
      this.borrador.push({ id: this.nuevoId(), formato, cuerpo, huella });
      this._cambio();
      return 'ok';
    }

    quitar(id) {
      const n = this.borrador.length;
      this.borrador = this.borrador.filter((x) => x.id !== id);
      if (this.borrador.length !== n) this._cambio();
    }

    /* Se cerró la hoja sin enviar: no queda nada. */
    descartarBorrador() { this.hoja += 1; this.borrador = []; this._cambio(); }

    /* «Enviar»: lo elegido pasa a la cola con sus ids ya puestos; sale con `drenar()`. Es sincrónico a propósito:
       un segundo toque encuentra la hoja vacía y no arma otro envío. */
    enviar(pedidoId) {
      if (!this.borrador.length || this._muerto) return false;
      this.cola.push({
        id: this.nuevoId(), pedidoId: pedidoId || null, abierto: false, rechazados: 0, vueltas: 0,
        archivos: this.borrador.map((x) => ({ id: x.id, formato: x.formato, cuerpo: x.cuerpo, subido: false })),
      });
      this.borrador = [];
      this.hoja += 1;
      this.aviso = null;
      this._cambio();
      return true;
    }

    // ── Cola ──
    /* El alumno tocó «Probar de nuevo» o volvió la señal: se empieza a contar de nuevo. */
    reanudar() { this._fondo = 0; return this.drenar(); }

    /* Una pasada a la vez, un envío por vez. Red: corta y espera a que vuelva. 5xx o 429: espera y reintenta, y a la
       tercera seguida corta la pasada y prueba sola más tarde. */
    async drenar() {
      if (this._drenando || !this.cola.length || this._muerto) return;
      this._drenando = true;
      this.subiendo = true;
      this.sinSenal = false;
      this.detenido = false;
      this._cambio();
      let termino = false;
      try {
        while (this.cola.length && !this._muerto) {
          const paso = await this._sacar(this.cola[0]);
          if (paso === 'listo') termino = true;
          else if (paso === 'cortar') break;
        }
      } finally {
        this._drenando = false;
        this.subiendo = false;
        this.detenido = this.cola.length > 0 && !this.sinSenal;
        this._cambio();
      }
      if (termino) await this.refrescar();
    }

    async _sacar(envio) {
      if (!envio.abierto) return this._abrir(envio);
      let seguidas = 0;
      for (;;) {
        if (this._muerto) return 'cortar';
        const a = envio.archivos.find((x) => !x.subido);
        if (!a) break;
        this._cambio();
        const r = await this._subir(a, envio);
        if (this._muerto) return 'cortar';
        if (r === 'ok') { a.subido = true; seguidas = 0; continue; }
        if (r === 'descartar') {
          envio.archivos = envio.archivos.filter((x) => x !== a);
          envio.rechazados += 1;
          continue;
        }
        if (r === 'token') {
          // 401 o 403: el link o la habilitación, no el archivo. No se pierde nada: lo que valga lo dice el próximo `get`.
          await this.refrescar();
          return 'cortar';
        }
        if (r === 'reabrir') {
          // 404: el servidor no conoce el envío. Se abre de nuevo y se sube todo otra vez.
          if (!this._darVuelta(envio)) { this._programarReintento(); envio.vueltas = 0; return 'cortar'; }
          this._desdeCero(envio, true);
          return 'seguir';
        }
        if (r === 'cerrado') return this._cerrar(envio, true);   // 409: ya quedó enviado; `enviar` lo confirma (`ya`)
        if (r === 'red') { this.sinSenal = true; this._programarReintento(); return 'cortar'; }
        seguidas += 1;
        if (seguidas >= MAX_SEGUIDAS) { this._programarReintento(); return 'cortar'; }
        await this.esperar(Math.pow(2, seguidas));
      }
      if (!envio.archivos.length) {
        // No quedó ninguno: el envío se descarta en silencio y se le dice que pruebe de otra forma.
        this._terminar(envio, 'rechazado');
        return 'seguir';
      }
      return this._cerrar(envio, false);
    }

    _desdeCero(envio, reabrir) {
      if (reabrir) envio.abierto = false;
      for (const a of envio.archivos) a.subido = false;
    }

    /* Cuenta las vueltas de un envío (subir todo de nuevo, cambiarle el id): false cuando ya dio las que puede. */
    _darVuelta(envio) {
      if (envio.vueltas >= MAX_VUELTAS) return false;
      envio.vueltas += 1;
      return true;
    }

    async _abrir(envio) {
      const r = await this._rpc('mypump_estudios_envio_nuevo', { p_id: envio.id, p_pedido_id: envio.pedidoId });
      if (!r.ok) return this._falla(r, envio);
      const j = r.data;
      if (j === null || j === undefined) { await this.refrescar(); return 'cortar'; }   // token caído: lo elegido queda
      if (j.ok === true) {
        if (j.estado === 'enviado') { this._terminar(envio, envio.rechazados > 0 ? 'recibidoConRechazo' : 'recibido'); return 'listo'; }
        envio.abierto = true;
        return 'seguir';
      }
      if (j.error === 'tope_dia') this._terminar(envio, 'topeDia');
      else if (j.error === 'no_habilitado') { this.apagar(); return 'cortar'; }           // se conserva: si lo vuelven a habilitar, sale
      else if (j.error === 'id_repetido' && this._darVuelta(envio)) envio.id = this.nuevoId();   // el id ya es de otro envío
      else this._terminar(envio, 'error');
      return 'seguir';
    }

    async _cerrar(envio, yaCerrado) {
      const r = await this._rpc('mypump_estudios_enviar', { p_id: envio.id, p_archivos: envio.archivos.length });
      if (!r.ok) return this._falla(r, envio);
      const j = r.data;
      if (j === null || j === undefined) { await this.refrescar(); return 'cortar'; }
      if (j.ok === true) {
        this._terminar(envio, envio.rechazados > 0 ? 'recibidoConRechazo' : 'recibido');
        return 'listo';
      }
      if (yaCerrado) this._terminar(envio, 'error');
      else if (j.error === 'faltan_archivos' || j.error === 'sin_archivos') {
        // En el servidor hay menos de los que subieron: se suben de nuevo (los que ya están contestan `ya`).
        if (!this._darVuelta(envio)) { this._programarReintento(); envio.vueltas = 0; return 'cortar'; }
        this._desdeCero(envio, false);
      } else if (j.error === 'no_encontrado') {
        if (!this._darVuelta(envio)) { this._terminar(envio, 'error'); return 'seguir'; }
        this._desdeCero(envio, true);
      } else if (j.error === 'no_habilitado') { this.apagar(); return 'cortar'; }
      else this._terminar(envio, 'error');
      return 'seguir';
    }

    _falla(r, envio) {
      // Sin la función o sin permiso (se revirtió el servidor, cambió la clave): la sección se apaga y la cola se conserva.
      if (r.codigo === 'PGRST202' || r.status === 401 || r.status === 403 || r.status === 404) { this.apagar(); return 'cortar'; }
      if (r.clase === 'permanente') { this._terminar(envio, 'error'); return 'seguir'; }
      if (r.clase === 'red') this.sinSenal = true;
      this._programarReintento();
      return 'cortar';
    }

    /* → 'ok' | 'descartar' | 'reintentar' | 'token' | 'reabrir' | 'cerrado' | 'red' */
    async _subir(a, envio) {
      if (!a.cuerpo || !a.cuerpo.size) return 'descartar';
      let res = null;
      try {
        res = await this.subir({ url: `${this.visionUrl}/estudios/upload`, token: this.token, envio: envio.id, archivo: a.id, mime: E.MIME[a.formato], cuerpo: a.cuerpo });
      } catch (_) { res = null; }
      if (!res || !res.status) return 'red';
      // Lo que no habla del archivo sino del link o del envío no gasta el archivo.
      if (res.status === 401 || res.status === 403) return 'token';
      if (res.status === 404) return 'reabrir';
      if (res.status === 409) return 'cerrado';
      return E.clasificarSubida(res.status, !!(res.json && res.json.ok === true));
    }

    /* Después de una tanda de errores, una pasada más sola, con la página abierta. */
    _programarReintento() {
      if (this._reintento || this._fondo >= MAX_FONDO || this._muerto) return;
      this._reintento = true;
      this._fondo += 1;
      Promise.resolve(this.esperar(ESPERA_FONDO_S)).then(() => {
        this._reintento = false;
        if (!this._muerto) return this.drenar();
      }).catch(() => { this._reintento = false; });
    }

    /* El envío sale de la cola (enviado o descartado) y sus archivos se sueltan de la memoria. */
    _terminar(envio, aviso) {
      for (const a of envio.archivos) a.cuerpo = null;
      this.cola = this.cola.filter((x) => x !== envio);
      if (aviso) this.aviso = aviso;
      this._fondo = 0;
      this._cambio();
    }

    // ── Abrir una orden o un estudio propio ──
    /* Pide las URL en el momento (duran 10 minutos: no se guardan en ningún lado).
       → { archivos: [{ url, pdf }] } | 'todaviaNo' | 'error' */
    async urls(clase, id) {
      let res = null, json = null;
      try {
        await conLimite(ESPERA_URLS_MS, async (signal) => {
          res = await this.fetch(`${this.visionUrl}/estudios/urls`, {
            method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ token: this.token, clase, id }),
            cache: 'no-store', credentials: 'omit', referrerPolicy: 'no-referrer', signal,
          });
          try { json = await res.json(); } catch (_) { json = null; }
        });
      } catch (_) { return 'error'; }
      if (!res) return 'error';
      if (res.status === 409 && json && json.error === 'todavia_no') { await this.refrescar(); return 'todaviaNo'; }
      if (res.status === 401 || res.status === 403) { await this.refrescar(); return 'error'; }
      if (res.status !== 200 || !json || json.ok !== true || !Array.isArray(json.archivos)) return 'error';
      const archivos = json.archivos.filter((f) => f && typeof f.url === 'string' && urlSegura(f.url)).map((f) => ({ url: f.url, pdf: f.mime === 'application/pdf' }));
      return archivos.length && archivos.length === json.archivos.length ? { archivos } : 'error';
    }

    /* Baja un archivo firmado a memoria, sin caché de disco. La pantalla muestra ese Blob: la URL firmada no llega
       al DOM ni al historial. El tipo lo fija la clase del archivo, nunca el servidor: un PDF o una imagen, nada que
       el navegador pueda ejecutar como página.  a: { url, pdf } → Blob | null */
    async bajar(a) {
      if (!a || !urlSegura(a.url)) return null;
      let blob = null;
      try {
        await conLimite(ESPERA_BAJAR_MS, async (signal) => {
          const res = await this.fetch(a.url, { cache: 'no-store', credentials: 'omit', referrerPolicy: 'no-referrer', signal });
          if (!res || res.status !== 200) return;
          const b = await res.blob();
          if (!b || !b.size) return;
          blob = b.slice(0, b.size, a.pdf ? E.MIME.pdf : (IMAGEN.test(b.type) ? b.type : E.MIME.jpeg));
        });
      } catch (_) { return null; }
      return blob;
    }
  }

  const API = { ModeloEstudios, MAX_SEGUIDAS, MAX_FONDO, MAX_VUELTAS, urlSegura, uuid };
  if (typeof module !== 'undefined' && module.exports) module.exports = API;
  else raiz.EstudiosCola = API;
})(typeof window !== 'undefined' ? window : globalThis);
