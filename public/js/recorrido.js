/* =============================================================
   recorrido.js — «Tu recorrido» (fin de plan, app 2.3.0, palanca `fin_plan`): reglas, textos y modelo.

   Sin pantalla: lo prueba scripts/test-recorrido.mjs. Contrato: cola-b/CONTRATO_APP.md, sección 1.
   · Apagada (sin la clave o con cualquier valor que no sea `true`) no se llama a ningún RPC y no se ve nada.
   · PGRST202, 404, NULL, `habilitado:false`, `visible:false`, un estado desconocido o sin logros: no se ve nada.
   · Un corte de red deja lo que ya se veía (la copia del navegador).
   · A quién se le muestra lo decide el servidor: acá no hay fechas ni se calcula nada con ellas.
   · El pedido es idempotente: el id se guarda en el navegador ANTES de mandar y se reintenta con el mismo.
   Textos: los del contrato, tal cual. Solo «Mati».
   ============================================================= */
(function (raiz) {
  'use strict';

  const MAX_TEXTO = 500;
  const MAX_LOGROS = 6;
  const ESTADOS = ['publicado', 'pedido', 'agendado'];
  const PALANCA = 'mypump_palanca_fin_plan';
  const CAMPOS = [
    { clave: 'mejor', id: 'recorrido-mejor', pregunta: '¿Qué fue lo mejor de estos meses?' },
    { clave: 'costo', id: 'recorrido-costo', pregunta: '¿Qué te costó más?' },
    { clave: 'objetivo', id: 'recorrido-objetivo', pregunta: '¿Qué te gustaría lograr ahora?' },
  ];

  const T = {
    tarjetaTitulo: 'Tu recorrido con Mati',
    tarjetaPublicado: 'Mirá todo lo que hiciste en estos meses.',
    tarjetaPedido: 'Mati ya recibió tu pedido.',
    tarjetaAgendado: 'Tu videollamada con Mati ya está agendada.',
    botonVer: 'Ver mi recorrido',
    entradaMisDatos: 'Tu recorrido con Mati',
    hojaTitulo: 'Tu recorrido',
    antesTitulo: 'Antes de hablar con Mati',
    antesTexto: 'Si querés, contale esto. Le sirve para prepararse.',
    agendar: 'Agendar con Mati',
    agendarPie: 'Es una videollamada para ver cómo seguimos.',
    enviando: 'Enviando…',
    error: 'No se pudo enviar. Probá de nuevo.',
    listo: 'Listo. Mati ya recibió tu pedido.',
    listoMati: 'Te escribe para coordinar el horario.',
    listoApp: 'Cuando esté tu horario lo vas a ver arriba de Entreno.',
    agendado: 'Tu videollamada con Mati ya está agendada.',
    cerrar: 'Cerrar',
  };

  const esObj = (v) => v !== null && typeof v === 'object' && !Array.isArray(v);
  /** Un texto para mostrar: recortado; un número vale como texto; lo demás, null. */
  function texto(v) {
    if (typeof v === 'number' && isFinite(v)) return String(v);
    if (typeof v !== 'string') return null;
    const s = v.trim();
    return s ? s : null;
  }
  /** Hasta 500 caracteres (contados como los cuenta el servidor, no en unidades UTF-16). */
  const recortar = (s) => Array.from(String(s == null ? '' : s)).slice(0, MAX_TEXTO).join('');

  /** La respuesta de `mypump_fin_plan_get` → lo que se muestra, o null = no se muestra nada. */
  function decodificar(j) {
    if (!esObj(j) || j.habilitado !== true || j.visible !== true) return null;
    if (!ESTADOS.includes(j.estado)) return null;
    const r = esObj(j.resumen) ? j.resumen : {};
    const logros = (Array.isArray(r.logros) ? r.logros : []).map((l) => {
      if (!esObj(l)) return null;
      const titulo = texto(l.titulo), valor = texto(l.valor);
      return titulo && valor ? { titulo, valor, detalle: texto(l.detalle) } : null;
    }).filter(Boolean).slice(0, MAX_LOGROS);
    if (!logros.length) return null;
    const resp = esObj(j.respuestas) ? j.respuestas : {};
    const respuestas = {};
    for (const c of CAMPOS) { const t = texto(resp[c.clave]); if (t) respuestas[c.clave] = recortar(t); }
    return {
      estado: j.estado,
      titulo: texto(r.titulo) || T.hojaTitulo,
      mensaje: texto(r.mensaje),
      logros,
      respuestas,
      agenda: j.agenda === 'app' ? 'app' : 'mati',
    };
  }

  const textoTarjeta = (estado) => estado === 'publicado' ? T.tarjetaPublicado : estado === 'pedido' ? T.tarjetaPedido
    : estado === 'agendado' ? T.tarjetaAgendado : null;
  const textoListo = (agenda) => agenda === 'app' ? T.listoApp : T.listoMati;

  /** Lo que viaja en `p_respuestas`: solo las tres claves, recortadas, y solo las que tienen algo. */
  function respuestasParaEnviar(textos) {
    const r = {};
    for (const c of CAMPOS) {
      const v = textos && typeof textos[c.clave] === 'string' ? recortar(textos[c.clave]).trim() : '';
      if (v) r[c.clave] = v;
    }
    return r;
  }

  function uuid() {
    const c = raiz.crypto;
    if (c && c.randomUUID) return c.randomUUID();
    const b = new Uint8Array(16);
    if (c && c.getRandomValues) c.getRandomValues(b); else for (let i = 0; i < 16; i++) b[i] = Math.floor(Math.random() * 256);
    b[6] = (b[6] & 0x0f) | 0x40; b[8] = (b[8] & 0x3f) | 0x80;
    const h = Array.from(b, (x) => x.toString(16).padStart(2, '0')).join('');
    return `${h.slice(0, 8)}-${h.slice(8, 12)}-${h.slice(12, 16)}-${h.slice(16, 20)}-${h.slice(20)}`;
  }

  const noExiste = (r) => r.status === 404 || r.codigo === 'PGRST202' || r.clase === 'permanente';

  /* deps: { token, rpc(fn, params) → {ok, data} | {ok:false, status, codigo, clase}, almacen {leer, guardar, borrar}, nuevoId? } */
  function crearModelo(deps) {
    const { token, almacen } = deps;
    const nuevoId = deps.nuevoId || uuid;
    const K = { estado: `mypump_recorrido_${token}`, borrador: `mypump_recorrido_borrador_${token}`,
      pedido: `mypump_recorrido_pedido_${token}`, sola: `mypump_recorrido_sola_${token}` };
    const leer = (k) => { try { return almacen.leer(k); } catch (_) { return null; } };
    const guardar = (k, v) => { try { almacen.guardar(k, v); } catch (_) {} };
    const borrar = (k) => { try { almacen.borrar(k); } catch (_) {} };
    const leerJson = (k) => { try { return JSON.parse(leer(k) || 'null'); } catch (_) { return null; } };
    const rpc = async (fn, params) => { try { return (await deps.rpc(fn, params)) || { ok: false }; } catch (_) { return { ok: false, status: 0, codigo: 'NETWORK', clase: 'red' }; } };

    let prendida = false, estado = null, crudo = null, enviando = false, error = false, vistoMandado = false, vuelta = 0, idEnMemoria = null;
    const escuchas = [];
    const avisar = () => escuchas.forEach((f) => { try { f(); } catch (_) {} });

    function fijar(j) {
      const e = decodificar(j);
      estado = e; crudo = e ? j : null;
      if (e) guardar(K.estado, JSON.stringify(j)); else borrar(K.estado);
      // Ya pedido (desde acá o desde otro teléfono): lo que quedaba a medio escribir y el id del pedido ya no hacen falta.
      if (e && e.estado !== 'publicado') { borrar(K.borrador); borrar(K.pedido); idEnMemoria = null; }
    }
    function borradorGuardado() {
      const b = leerJson(K.borrador);
      const r = {};
      if (esObj(b)) for (const c of CAMPOS) if (typeof b[c.clave] === 'string') r[c.clave] = recortar(b[c.clave]);
      return r;
    }

    const m = {
      get prendida() { return prendida; },
      /** null = no se muestra nada. */
      get estado() { return prendida ? estado : null; },
      get enviando() { return enviando; },
      get error() { return error; },
      alCambiar(f) { escuchas.push(f); },

      /** cfg: lo que devolvió `mypump_get_app_config`; null = no se pudo preguntar (queda lo último que se supo). */
      aplicarConfig(cfg) {
        if (esObj(cfg)) { prendida = cfg.fin_plan === true; guardar(PALANCA, prendida ? '1' : '0'); }
        else prendida = leer(PALANCA) === '1';
        if (!prendida) { vuelta++; estado = null; crudo = null; error = false; borrar(K.estado); }
        avisar();
        return prendida;
      },

      /** Al cargar la cuenta y al volver a primer plano. Apagada no llama. */
      async refrescar() {
        if (!prendida || enviando) return;
        const v = vuelta;
        const r = await rpc('mypump_fin_plan_get', { p_token: token });
        if (!prendida || v !== vuelta) return;      // se apagó o se pidió mientras viajaba: esta respuesta ya es vieja
        if (r.ok) fijar(r.data);                    // NULL (token caído), habilitado:false o visible:false → nada
        else if (noExiste(r)) fijar(null);
        else if (!estado) { const j = leerJson(K.estado); const e = decodificar(j); if (e) { estado = e; crudo = j; } }
        avisar();
      },

      /** Se abre sola una sola vez por cuenta, la primera vez que llega `publicado`. */
      get debeAbrirseSola() { return !!(prendida && estado && estado.estado === 'publicado' && leer(K.sola) !== '1'); },
      marcarAbiertaSola() { guardar(K.sola, '1'); },

      /** Una vez, al abrir la hoja. Si falla no importa. */
      visto() {
        if (!prendida || !estado || vistoMandado) return;
        vistoMandado = true;
        rpc('mypump_fin_plan_visto', { p_token: token });
      },

      /** Lo que hay en los tres campos: lo que está escribiendo y, si no, lo que ya había contestado. */
      get textos() {
        const b = borradorGuardado(), r = {};
        for (const c of CAMPOS) r[c.clave] = b[c.clave] != null ? b[c.clave] : ((estado && estado.respuestas[c.clave]) || '');
        return r;
      },
      /** Lo escrito se guarda en el navegador mientras tanto. */
      escribir(clave, valor) {
        if (!CAMPOS.some((c) => c.clave === clave)) return;
        const b = borradorGuardado();
        b[clave] = recortar(valor);
        guardar(K.borrador, JSON.stringify(b));
      },

      /** → 'ok' | 'cerrar' (ya no está disponible: cerrar la hoja) | 'error' (se puede reintentar) | 'nada'. */
      async pedir() {
        if (!prendida || !estado || estado.estado !== 'publicado' || enviando) return 'nada';
        let id = leer(K.pedido) || idEnMemoria;
        if (!id) { id = String(nuevoId()); idEnMemoria = id; guardar(K.pedido, id); }   // en disco ANTES de mandar
        const respuestas = respuestasParaEnviar(m.textos);
        enviando = true; error = false; avisar();
        const r = await rpc('mypump_fin_plan_pedir', { p_token: token, p_id: id, p_respuestas: respuestas });
        enviando = false;
        const d = r.ok && esObj(r.data) ? r.data : null;
        if (d && d.ok === true && prendida && crudo) {
          vuelta++;
          fijar(Object.assign({}, crudo, { estado: d.estado === 'agendado' ? 'agendado' : 'pedido', respuestas }));
          avisar();
          return 'ok';
        }
        if (d && d.ok === false && (d.error === 'apagado' || d.error === 'no_disponible')) {
          vuelta++;
          fijar(null); borrar(K.pedido); idEnMemoria = null;
          avisar();
          return 'cerrar';
        }
        error = true; avisar();
        return 'error';
      },
      limpiarError() { if (error) { error = false; avisar(); } },
    };
    return m;
  }

  const API = { MAX_TEXTO, MAX_LOGROS, ESTADOS, CAMPOS, T, PALANCA, decodificar, textoTarjeta, textoListo, recortar, respuestasParaEnviar, uuid, crearModelo };
  if (typeof module !== 'undefined' && module.exports) module.exports = API;
  else raiz.Recorrido = API;
})(typeof window !== 'undefined' ? window : globalThis);
