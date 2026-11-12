/* =============================================================
   casa.js — «Entreno en casa» (app 2.3.0, palanca `casa`): reglas, textos y modelo del interruptor de Mi gimnasio.

   Sin pantalla: lo prueba scripts/test-casa.mjs. Contrato: cola-b/CONTRATO_APP.md, sección 3.
   · Es una excepción dentro de Mi gimnasio: hacen falta las dos palancas (`gimnasio_fotos` y `casa`). Apagada no se
     llama a ningún RPC y no se ve nada. PGRST202, 404, NULL o `habilitado:false`: el interruptor no existe.
   · La carga de casa es la misma carga de `mypump_gimnasio_get` (mismo id) con `lugar:"casa"`.
   · La lista de equipo NO está escrita acá: la da el servidor (`tipos`), en su orden y con su nombre.
   · Después de cada `elegir` / `enviar` se refrescan los dos (casa y gimnasio).
   ============================================================= */
(function (raiz) {
  'use strict';

  const MAX_NOTA = 300;
  const KG_MIN = 1, KG_MAX = 400;
  const PALANCA = 'mypump_palanca_casa';

  const T = {
    interruptor: 'Entreno en casa',
    interruptorAyuda: 'Prendelo si entrenás en tu casa y no en un gimnasio.',
    interruptorBloqueado: 'Ya lo recibimos. Lo vas a poder cambiar cuando esté listo.',
    errorCambiar: 'No se pudo cambiar. Probá de nuevo.',
    listaTitulo: '¿Qué tenés en casa?',
    tarjeta: '¿Entrenás en casa? Tocá acá',
    listaTexto: 'Marcá todo lo que tengas. Con eso Mati arma tu rutina.',
    kilos: 'Hasta cuántos kilos (opcional)',
    kilosInvalidos: 'Poné un número entre 1 y 400',
    kg: 'kg',
    sinEquipo: 'No tengo nada de esto',
    nota: '¿Algo más que quieras contarle a Mati?',
    enviar: 'Enviar a Mati',
    errorEnviar: 'No se pudo enviar. Probá de nuevo.',
    sinDatos: 'Marcá lo que tenés, o “No tengo nada de esto”.',
    vigenteTitulo: 'Entrenás en casa',
    vigenteSinEquipo: 'Sin equipo: entrenás con tu cuerpo.',
    cambiar: 'Cambió lo que tengo en casa',
    hasta: (n) => `hasta ${n} kg`,
  };

  const esObj = (v) => v !== null && typeof v === 'object' && !Array.isArray(v);
  const lista = (v) => (Array.isArray(v) ? v : []);
  const TIPO = /^[a-z0-9_]{1,40}$/;
  const notaRecortada = (s) => Array.from(String(s == null ? '' : s)).slice(0, MAX_NOTA).join('');

  /** «20», «12,5» → número entre 1 y 400 con un decimal; lo demás, null. */
  function kilos(v) {
    let n;
    if (typeof v === 'number') n = v;
    else {
      const t = String(v == null ? '' : v).trim().replace(',', '.');
      if (!/^\d+(\.\d+)?$/.test(t)) return null;
      n = Number(t);
    }
    if (!Number.isFinite(n)) return null;
    n = Math.round(n * 10) / 10;
    return n >= KG_MIN && n <= KG_MAX ? n : null;
  }
  const formatoKg = (n) => (Number.isInteger(n) ? String(n) : n.toFixed(1).replace('.', ','));

  function decodificarCarga(j) {
    if (!esObj(j) || typeof j.id !== 'string' || !j.id || typeof j.estado !== 'string' || !j.estado) return null;
    const vistos = new Set();
    const equipos = [];
    for (const q of lista(j.equipos)) {
      if (!esObj(q) || typeof q.tipo !== 'string' || !TIPO.test(q.tipo) || vistos.has(q.tipo)) continue;
      vistos.add(q.tipo);
      equipos.push({ tipo: q.tipo, kg: kilos(typeof q.kg === 'number' ? q.kg : null) });
    }
    return {
      id: j.id, estado: j.estado,
      lugar: j.lugar === 'casa' ? 'casa' : 'gimnasio',
      equipos, sinEquipo: j.sin_equipo === true,
      nota: typeof j.nota === 'string' ? j.nota : null,
    };
  }

  /** La respuesta de `mypump_casa_get` → {tipos, abierta, vigente}; null = el interruptor no existe. */
  function decodificar(j) {
    if (!esObj(j) || j.habilitado !== true) return null;
    const vistos = new Set();
    const tipos = [];
    for (const t of lista(j.tipos)) {
      if (!esObj(t) || typeof t.tipo !== 'string' || !TIPO.test(t.tipo) || vistos.has(t.tipo)) continue;
      const nombre = typeof t.nombre === 'string' && t.nombre.trim() ? t.nombre.trim() : null;
      if (!nombre) continue;
      vistos.add(t.tipo);
      tipos.push({ tipo: t.tipo, nombre, kg: t.kg === true });
    }
    return { tipos, abierta: decodificarCarga(j.abierta), vigente: decodificarCarga(j.vigente) };
  }

  /** Prendido = la carga abierta es de casa, o no hay carga abierta y la vigente es de casa.
   *  Bloqueado = hay una carga ya enviada (cualquier estado que no sea `borrador`). */
  function interruptor(e) {
    if (!e) return null;
    const a = e.abierta, v = e.vigente;
    return {
      prendido: a ? a.lugar === 'casa' : !!(v && v.lugar === 'casa'),
      bloqueado: !!(a && a.estado !== 'borrador'),
    };
  }

  /** Qué se muestra en lugar de las pantallas del gimnasio: 'lista' (borrador de casa), 'vigente' (casa aprobada) o null. */
  function pantalla(e) {
    if (!e) return null;
    const a = e.abierta, v = e.vigente;
    if (a) return a.lugar === 'casa' && a.estado === 'borrador' ? 'lista' : null;
    return v && v.lugar === 'casa' && v.estado === 'listo' ? 'vigente' : null;
  }

  /** Qué hay que hacer al mover el interruptor: 'elegir' (mypump_casa_elegir), 'gimnasio' (la carga completa de
   *  gimnasio de siempre, el camino de «Cambié de gimnasio») o 'nada'. */
  function accion(e, aCasa) {
    const i = interruptor(e);
    if (!i || i.bloqueado || i.prendido === !!aCasa) return 'nada';
    if (aCasa) return 'elegir';
    return e.abierta ? 'elegir' : 'gimnasio';
  }

  // ── Lo marcado (queda en el navegador hasta enviarlo) ──
  const borradorVacio = (id) => ({ id, marcados: [], kg: {}, sinEquipo: false, nota: '' });
  function borradorValido(b, id) {
    if (!esObj(b) || b.id !== id) return borradorVacio(id);
    const kg = {};
    if (esObj(b.kg)) for (const [k, v] of Object.entries(b.kg)) if (TIPO.test(k) && typeof v === 'string') kg[k] = v.slice(0, 8);
    return {
      id,
      marcados: Array.from(new Set(lista(b.marcados).filter((t) => typeof t === 'string' && TIPO.test(t)))),
      kg, sinEquipo: b.sinEquipo === true, nota: notaRecortada(typeof b.nota === 'string' ? b.nota : ''),
    };
  }
  /** Marcar un equipo desmarca «No tengo nada de esto». */
  function alternarTipo(b, tipo) {
    const on = b.marcados.includes(tipo);
    return Object.assign({}, b, { marcados: on ? b.marcados.filter((t) => t !== tipo) : b.marcados.concat([tipo]), sinEquipo: on ? b.sinEquipo : false });
  }
  /** «No tengo nada de esto» desmarca todo. */
  function alternarSinEquipo(b) {
    return b.sinEquipo ? Object.assign({}, b, { sinEquipo: false }) : Object.assign({}, b, { sinEquipo: true, marcados: [], kg: {} });
  }
  /** En el orden del servidor, solo tipos de su lista; `kg` solo donde la lista lo pide y si es un número válido. */
  function equiposParaEnviar(b, tipos) {
    if (b.sinEquipo) return [];
    return tipos.filter((t) => b.marcados.includes(t.tipo)).map((t) => {
      const n = t.kg ? kilos(b.kg[t.tipo]) : null;
      return n == null ? { tipo: t.tipo } : { tipo: t.tipo, kg: n };
    });
  }
  const puedeEnviar = (b, tipos) => b.sinEquipo || equiposParaEnviar(b, tipos).length > 0;

  /** Lo que tiene, para la pantalla «Entrenás en casa»: [{nombre, detalle}] en el orden de la lista del servidor. */
  function equiposVigentes(carga, tipos) {
    const orden = new Map(tipos.map((t, i) => [t.tipo, i]));
    return carga.equipos.slice().sort((a, b) => (orden.has(a.tipo) ? orden.get(a.tipo) : 999) - (orden.has(b.tipo) ? orden.get(b.tipo) : 999))
      .map((q) => {
        const t = tipos.find((x) => x.tipo === q.tipo);
        return { tipo: q.tipo, nombre: t ? t.nombre : q.tipo.replace(/_/g, ' '), detalle: q.kg != null ? T.hasta(formatoKg(q.kg)) : null };
      });
  }

  const noExiste = (r) => r.status === 404 || r.codigo === 'PGRST202' || r.clase === 'permanente';

  /* deps: { token, rpc(fn, params) → {ok, data} | {ok:false, status, codigo, clase}, almacen {leer, guardar, borrar},
   *         gimnasio: { refrescar() → Promise, nuevoCompleta() → Promise<'ok' | otra cosa> } } */
  function crearModelo(deps) {
    const { token, almacen, gimnasio } = deps;
    const K = { estado: `mypump_casa_${token}`, borrador: `mypump_casa_borrador_${token}` };
    const leer = (k) => { try { return almacen.leer(k); } catch (_) { return null; } };
    const guardar = (k, v) => { try { almacen.guardar(k, v); } catch (_) {} };
    const borrar = (k) => { try { almacen.borrar(k); } catch (_) {} };
    const leerJson = (k) => { try { return JSON.parse(leer(k) || 'null'); } catch (_) { return null; } };
    const rpc = async (fn, params) => { try { return (await deps.rpc(fn, params)) || { ok: false }; } catch (_) { return { ok: false, status: 0, codigo: 'NETWORK', clase: 'red' }; } };

    let prendida = false, estado = null, error = null, moviendoA = null, enviando = false, vuelta = 0, enMemoria = null;
    const escuchas = [];
    const avisar = () => escuchas.forEach((f) => { try { f(); } catch (_) {} });

    function fijar(j) {
      estado = decodificar(j);
      if (estado) guardar(K.estado, JSON.stringify(j)); else borrar(K.estado);
    }
    const idAbierta = () => (estado && estado.abierta && pantalla(estado) === 'lista' ? estado.abierta.id : null);
    function leerBorrador() {
      const id = idAbierta();
      if (!id) return null;
      if (enMemoria && enMemoria.id === id) return enMemoria;
      enMemoria = borradorValido(leerJson(K.borrador), id);
      return enMemoria;
    }
    function guardarBorrador(b) { enMemoria = b; guardar(K.borrador, JSON.stringify(b)); }
    async function refrescarLosDos() {
      await m.refrescar();
      try { await gimnasio.refrescar(); } catch (_) {}
    }
    async function elegir(aCasa, reintentos) {
      const r = await rpc('mypump_casa_elegir', { p_token: token, p_casa: aCasa });
      const d = r.ok && esObj(r.data) ? r.data : null;
      if (d && d.ok === true) { await refrescarLosDos(); return 'ok'; }
      if (d && d.error === 'no_habilitado') { vuelta++; fijar(null); return 'ok'; }           // se esconde el interruptor
      if (d && d.error === 'en_curso') { await refrescarLosDos(); return 'ok'; }             // queda bloqueado
      if (d && d.error === 'reintentar' && reintentos > 0) return elegir(aCasa, reintentos - 1);
      return 'error';
    }

    async function cambiarLugar(que, aCasa) {
      if (que === 'nada' || moviendoA != null || enviando) return 'nada';
      moviendoA = aCasa; error = null; avisar();
      let r = 'error';
      try {
        if (que === 'gimnasio') r = (await gimnasio.nuevoCompleta()) === 'ok' ? 'ok' : 'error';
        else r = await elegir(aCasa, 1);
      } catch (_) { r = 'error'; }
      moviendoA = null;
      if (r === 'error') error = 'cambiar';
      avisar();
      return r;
    }

    const m = {
      get prendida() { return prendida; },
      /** null = el interruptor no existe. */
      get estado() { return prendida ? estado : null; },
      get interruptor() {
        const i = interruptor(m.estado);
        if (!i) return null;
        // Mientras viaja se muestra donde lo dejó el dedo; si falla, vuelve a como estaba.
        return { prendido: moviendoA != null ? moviendoA : i.prendido, bloqueado: i.bloqueado, ocupado: moviendoA != null };
      },
      get pantalla() { return pantalla(m.estado); },
      get error() { return error; },                 // null | 'cambiar' | 'enviar' | 'sinDatos'
      get enviando() { return enviando; },
      get borrador() { return leerBorrador(); },
      get puedeEnviar() { const b = leerBorrador(); return !!b && !enviando && puedeEnviar(b, estado.tipos); },
      alCambiar(f) { escuchas.push(f); },

      /** cfg: lo que devolvió `mypump_get_app_config`; null = no se pudo preguntar (queda lo último que se supo). */
      aplicarConfig(cfg) {
        if (esObj(cfg)) { prendida = cfg.casa === true && cfg.gimnasio_fotos === true; guardar(PALANCA, prendida ? '1' : '0'); }
        else prendida = leer(PALANCA) === '1';
        if (!prendida) { vuelta++; estado = null; error = null; borrar(K.estado); }
        return prendida;
      },

      /** Junto con `mypump_gimnasio_get`. Apagada no llama. */
      async refrescar() {
        if (!prendida) return;
        const v = ++vuelta;
        const r = await rpc('mypump_casa_get', { p_token: token });
        if (!prendida || v !== vuelta) return;
        if (r.ok) fijar(r.data);                     // NULL (token caído) o habilitado:false → sin interruptor
        else if (noExiste(r)) fijar(null);
        else if (!estado) estado = decodificar(leerJson(K.estado));    // sin red: lo último que se vio
      },

      /** Mover el interruptor. → 'ok' | 'error' (vuelve a como estaba) | 'nada'. */
      mover(aCasa) { return cambiarLugar(accion(m.estado, aCasa), !!aCasa); },
      /** «Cambió lo que tengo en casa»: con casa vigente y sin carga abierta, abre otra carga de casa. */
      cambiar() { return cambiarLugar(pantalla(m.estado) === 'vigente' ? 'elegir' : 'nada', true); },

      alternarTipo(tipo) {
        const b = leerBorrador();
        if (!b || !estado.tipos.some((t) => t.tipo === tipo)) return;
        guardarBorrador(alternarTipo(b, tipo)); error = null; avisar();
      },
      alternarSinEquipo() {
        const b = leerBorrador();
        if (!b) return;
        guardarBorrador(alternarSinEquipo(b)); error = null; avisar();
      },
      /** Sin avisar: no se le rehace la pantalla a quien escribe. */
      fijarKg(tipo, textoKg) {
        const b = leerBorrador();
        if (!b || !TIPO.test(tipo)) return;
        guardarBorrador(Object.assign({}, b, { kg: Object.assign({}, b.kg, { [tipo]: String(textoKg).slice(0, 8) }) }));
      },
      fijarNota(s) {
        const b = leerBorrador();
        if (!b) return;
        guardarBorrador(Object.assign({}, b, { nota: notaRecortada(s) }));
      },

      /** → 'ok' | 'sinDatos' | 'error' | 'nada'. */
      async enviar() {
        const b = leerBorrador();
        if (!b || enviando || moviendoA != null) return 'nada';
        if (!puedeEnviar(b, estado.tipos)) { error = 'sinDatos'; avisar(); return 'sinDatos'; }
        enviando = true; error = null; avisar();
        const nota = b.nota.trim();
        const r = await rpc('mypump_casa_enviar', { p_token: token, p_id: b.id, p_equipos: equiposParaEnviar(b, estado.tipos),
          p_sin_equipo: b.sinEquipo, p_nota: nota ? nota : null });
        const d = r.ok && esObj(r.data) ? r.data : null;
        let fin = 'error';
        if (d && d.ok === true) { borrar(K.borrador); enMemoria = null; await refrescarLosDos(); fin = 'ok'; }
        else if (d && d.error === 'sin_datos') fin = 'sinDatos';
        else if (d && d.error === 'no_habilitado') { vuelta++; fijar(null); try { await gimnasio.refrescar(); } catch (_) {} }
        else if (d && typeof d.error === 'string') await refrescarLosDos();     // no_encontrado, no_es_casa, contradiccion: lo que haya ahora
        enviando = false;
        error = fin === 'ok' ? null : fin === 'sinDatos' ? 'sinDatos' : (m.estado ? 'enviar' : null);
        avisar();
        return fin;
      },
    };
    return m;
  }

  const API = { MAX_NOTA, KG_MIN, KG_MAX, PALANCA, T, kilos, formatoKg, notaRecortada, decodificar, decodificarCarga, interruptor, pantalla, accion,
    borradorVacio, borradorValido, alternarTipo, alternarSinEquipo, equiposParaEnviar, puedeEnviar, equiposVigentes, crearModelo };
  if (typeof module !== 'undefined' && module.exports) module.exports = API;
  else raiz.Casa = API;
})(typeof window !== 'undefined' ? window : globalThis);
