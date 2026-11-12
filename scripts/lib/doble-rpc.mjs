// Doble de `mypumpDB.gimnasioRpc` y del almacén del navegador para los tests de la cola B (recorrido, compras, casa).
// Nombres y datos de prueba inventados: nada de esto existe.
export function almacen(inicial = {}) {
  const m = new Map(Object.entries(inicial));
  return { m, leer: (k) => (m.has(k) ? m.get(k) : null), guardar: (k, v) => { m.set(k, String(v)); }, borrar: (k) => { m.delete(k); } };
}
export const ok = (data) => ({ ok: true, data });
export const RED = { ok: false, status: 0, codigo: 'NETWORK', clase: 'red' };
export const NO_EXISTE = { ok: false, status: 404, codigo: 'PGRST202', clase: 'permanente' };
export const CAIDO = { ok: false, status: 503, codigo: 'HTTP', clase: 'transitorio' };

/** respuestas: { nombre_del_rpc: valor | (params, n) => valor }. Anota cada llamada en `.llamadas`. */
export function rpcDoble(respuestas = {}) {
  const llamadas = [];
  const f = async (fn, params) => {
    llamadas.push({ fn, params });
    const r = f.respuestas[fn];
    const n = llamadas.filter((l) => l.fn === fn).length;
    const v = typeof r === 'function' ? await r(params, n) : r;
    return v === undefined ? NO_EXISTE : v;
  };
  f.respuestas = respuestas;
  f.llamadas = llamadas;
  f.nombres = () => llamadas.map((l) => l.fn);
  f.de = (fn) => llamadas.filter((l) => l.fn === fn);
  return f;
}
