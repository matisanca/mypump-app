/* =============================================================
   compras.js — «Dónde comprarlo» (compras por país, app 2.3.0, palanca `compras_pais`): reglas, textos y modelo.

   Sin pantalla: lo prueba scripts/test-compras.mjs. Contrato: cola-b/CONTRATO_APP.md, sección 2.
   · Apagada no se llama a ningún RPC y no se ve nada. PGRST202, 404, NULL o `habilitado:false`: nada.
   · Se consulta junto con la suplementación y solo si hay suplementación. Queda una copia para verla sin red.
   · Se cruza con los ítems de la pestaña por NOMBRE EXACTO (después de recortar espacios). Nada de parecidos.
   · `items` vacío = no hay dato verificado: no se muestra nada, ni un cartel de «no hay».
   · La url solo vale si es `https://`; cualquier otra cosa se ignora y la opción se muestra sin botón.
   · Acá no se inventa nada: ni país por defecto, ni tiendas, ni búsquedas armadas.
   ============================================================= */
(function (raiz) {
  'use strict';

  const MAX_OPCIONES = 4;
  const PALANCA = 'mypump_palanca_compras_pais';

  const T = {
    boton: 'Dónde comprarlo',
    ayuda: 'Tocá “Dónde comprarlo” para ver dónde conseguir cada suplemento.',
    subtitulo: 'Dónde comprarlo',
    abrirTienda: 'Abrir la tienda',
    pie: 'Son lugares que Mati revisó.',
    cerrar: 'Cerrar',
  };

  const esObj = (v) => v !== null && typeof v === 'object' && !Array.isArray(v);
  const texto = (v) => { if (typeof v !== 'string') return null; const s = v.trim(); return s ? s : null; };

  /** La url tal cual si es https y está bien formada; si no, null (la opción queda sin botón). */
  function urlSegura(v) {
    if (typeof v !== 'string') return null;
    const s = v.trim();
    if (!/^https:\/\/[^\s]+$/i.test(s) || s.length > 2000) return null;
    try {
      const u = new URL(s);
      return u.protocol === 'https:' && u.hostname && !u.username && !u.password ? u.href : null;
    } catch (_) { return null; }
  }

  function opcion(o) {
    if (!esObj(o)) return null;
    const producto = texto(o.producto), tienda = texto(o.tienda);
    if (!producto || !tienda) return null;
    return { producto, tienda, url: urlSegura(o.url), nota: texto(o.nota) };
  }

  /** La respuesta de `mypump_compras_get` → {pais, items:[{nombre, opciones}]} solo con ítems que tienen opciones; null = nada. */
  function decodificar(j) {
    if (!esObj(j) || j.habilitado !== true) return null;
    const items = [];
    const vistos = new Set();
    for (const it of (Array.isArray(j.items) ? j.items : [])) {
      if (!esObj(it)) continue;
      const nombre = texto(it.nombre);
      if (!nombre || vistos.has(nombre)) continue;
      const opciones = (Array.isArray(it.opciones) ? it.opciones : []).map(opcion).filter(Boolean).slice(0, MAX_OPCIONES);
      if (!opciones.length) continue;
      vistos.add(nombre);
      items.push({ nombre, opciones });
    }
    return items.length ? { pais: texto(j.pais), items } : null;
  }

  /** Las opciones del ítem de la pestaña que se llama exactamente así (recortando espacios); [] si no hay. */
  function opcionesDe(compras, nombre) {
    const n = texto(nombre);
    if (!compras || !n) return [];
    const it = compras.items.find((x) => x.nombre === n);
    return it ? it.opciones : [];
  }

  /** Por cada ítem de la pestaña (en su orden), sus opciones o null. `sale` nunca lleva botón. */
  function cruzar(compras, itemsSupl) {
    return (Array.isArray(itemsSupl) ? itemsSupl : []).map((it) => {
      if (!esObj(it) || (typeof it.estado === 'string' && it.estado.trim().toLowerCase() === 'sale')) return null;
      const o = opcionesDe(compras, it.nombre);
      return o.length ? o : null;
    });
  }

  const noExiste = (r) => r.status === 404 || r.codigo === 'PGRST202' || r.clase === 'permanente';

  /* deps: { token, rpc(fn, params) → {ok, data} | {ok:false, status, codigo, clase}, almacen {leer, guardar, borrar} } */
  function crearModelo(deps) {
    const { token, almacen } = deps;
    const K = `mypump_compras_${token}`;
    const leer = (k) => { try { return almacen.leer(k); } catch (_) { return null; } };
    const guardar = (k, v) => { try { almacen.guardar(k, v); } catch (_) {} };
    const borrar = (k) => { try { almacen.borrar(k); } catch (_) {} };
    const rpc = async (fn, params) => { try { return (await deps.rpc(fn, params)) || { ok: false }; } catch (_) { return { ok: false, status: 0, codigo: 'NETWORK', clase: 'red' }; } };

    let prendida = false, compras = null, vuelta = 0;
    function fijar(j) {
      compras = decodificar(j);
      if (compras) guardar(K, JSON.stringify(j)); else borrar(K);
    }

    return {
      get prendida() { return prendida; },
      /** null = no se muestra nada. */
      get compras() { return prendida ? compras : null; },

      /** cfg: lo que devolvió `mypump_get_app_config`; null = no se pudo preguntar (queda lo último que se supo). */
      aplicarConfig(cfg) {
        if (esObj(cfg)) { prendida = cfg.compras_pais === true; guardar(PALANCA, prendida ? '1' : '0'); }
        else prendida = leer(PALANCA) === '1';
        if (!prendida) { vuelta++; compras = null; borrar(K); }
        return prendida;
      },

      /** Junto con la suplementación. haySuplementacion false = no hay nada que cruzar: no se llama y no se muestra. */
      async refrescar(haySuplementacion) {
        if (!prendida) return;
        if (!haySuplementacion) { vuelta++; compras = null; return; }
        const v = ++vuelta;
        const r = await rpc('mypump_compras_get', { p_token: token });
        if (!prendida || v !== vuelta) return;
        if (r.ok) fijar(r.data);
        else if (noExiste(r)) fijar(null);
        else if (!compras) { try { compras = decodificar(JSON.parse(leer(K) || 'null')); } catch (_) { compras = null; } }
      },
    };
  }

  const API = { MAX_OPCIONES, PALANCA, T, urlSegura, decodificar, opcionesDe, cruzar, crearModelo };
  if (typeof module !== 'undefined' && module.exports) module.exports = API;
  else raiz.Compras = API;
})(typeof window !== 'undefined' ? window : globalThis);
