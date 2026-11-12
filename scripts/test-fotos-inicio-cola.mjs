#!/usr/bin/env node
/* =============================================================
 * test-fotos-inicio-cola.mjs — la cola y el modelo de «Fotos de inicio» contra
 * un servidor de mentira en memoria (NATIVA_CONTRATO.md §13), con el almacén en
 * memoria. IndexedDB real y el canvas se prueban en el navegador.
 * USO:  node scripts/test-fotos-inicio-cola.mjs
 * ============================================================= */
import { createRequire } from 'node:module';
const require = createRequire(import.meta.url);
const F = require('../public/js/fotos-inicio.js');
const { ModeloFotosInicio, almacenMemoria, abrirAlmacen, cuentaDe, arrancar } = require('../public/js/fotos-inicio-cola.js');

const TOK = 'token-de-prueba-0123456789';

/* El servidor: la RPC por token y mini-vision (/inicio/upload, /inicio/urls, /inicio/borrar). */
function doble(ini = {}) {
  const d = {
    habilitado: true, sinFuncion: false, tokenCaido: false, sinRed: false, proximas: [], llamadas: [], fotos: [], nota: '',
    maxMotivacion: 4, cerrada: false, cabeceras: [], cuerpos: [], notaFalla: null, ...ini,
  };
  const cuerpo = () => d.fotos.filter((f) => f.pose !== 'motivacion');
  d.rpc = async (fn, p) => {
    d.llamadas.push(fn);
    if (d.sinRed) return { ok: false, status: 0, codigo: 'NETWORK', clase: 'red' };
    if (d.sinFuncion) return { ok: false, status: 404, codigo: 'PGRST202', clase: 'permanente' };
    if (d.tokenCaido || p.p_token !== TOK) return { ok: true, data: null };
    if (fn === 'mypump_fotos_inicio_get') {
      if (!d.habilitado) return { ok: true, data: { habilitado: false } };
      const completo = new Set(cuerpo().map((f) => f.pose)).size === 3;
      return { ok: true, data: { habilitado: true, completo, completado_en: completo ? '2026-11-10T12:00:00+00:00' : null, nota: d.nota, max_motivacion: d.maxMotivacion, fotos: d.fotos.map(({ id, pose, tomada_en, ancho, alto }) => ({ id, pose, tomada_en, ancho, alto })) } };
    }
    if (fn === 'mypump_fotos_inicio_nota') {
      if (d.notaFalla) { const x = d.notaFalla; d.notaFalla = null; return x; }
      if (!d.habilitado) return { ok: true, data: { ok: false, error: 'no_habilitado' } };
      d.nota = F.notaRecortada(p.p_nota);
      return { ok: true, data: { ok: true, nota: d.nota } };
    }
    return { ok: false, status: 404, codigo: 'PGRST202', clase: 'permanente' };
  };
  d.fetch = async (url, o) => {
    const ruta = url.split('/inicio/')[1];
    d.llamadas.push(`vision/${ruta}`);
    const res = (status, j) => ({ status, json: async () => j });
    if (d.sinRed) throw new TypeError('Failed to fetch');
    if (ruta === 'upload') {
      if (d.proximas.length) {
        const s = d.proximas.shift();
        if (s === 0) throw new TypeError('Load failed');
        if (s !== 200) return res(s, { ok: false });
      }
      const h = o.headers;
      d.cabeceras.push(h); d.cuerpos.push(o.body);
      if (h['x-inicio-token'] !== TOK || d.cerrada || !d.habilitado) return res(403, { ok: false });
      if (d.fotos.some((f) => f.id === h['x-inicio-foto'])) return res(200, { ok: true, ya: true });
      const pose = h['x-inicio-pose'];
      if (pose === 'motivacion' && d.fotos.filter((f) => f.pose === 'motivacion').length >= d.maxMotivacion) return res(413, { ok: false, error: 'tope' });
      if (pose !== 'motivacion') d.fotos = d.fotos.filter((f) => f.pose !== pose);
      d.fotos.push({ id: h['x-inicio-foto'], pose, tomada_en: h['x-inicio-tomada'] || null, ancho: 1200, alto: 1600 });
      return res(200, { ok: true });
    }
    const j = JSON.parse(o.body);
    if (j.token !== TOK) return res(403, { ok: false });
    if (ruta === 'urls') return res(200, { ok: true, fotos: d.fotos.map((f) => ({ id: f.id, pose: f.pose, url: `https://ejemplo.invalid/${f.id}.jpg` })) });
    if (ruta === 'borrar') {
      const f = d.fotos.find((x) => x.id === j.foto_id);
      if (!f || f.pose !== 'motivacion') return res(404, { ok: false });
      d.fotos = d.fotos.filter((x) => x.id !== j.foto_id);
      return res(200, { ok: true });
    }
    return res(404, {});
  };
  d.subidas = () => d.llamadas.filter((x) => x === 'vision/upload').length;
  return d;
}

let n = 0;
const deps = (d, extra = {}) => ({
  rpc: (f, x) => d.rpc(f, x), fetch: (u, o) => d.fetch(u, o), token: TOK, visionUrl: 'https://vision.ejemplo.test/',
  esperar: () => new Promise((r) => setTimeout(r, 0)), nuevoId: () => `F${++n}-ABC`, visible: () => false, ...extra,
});
const modelo = (d, almacen = almacenMemoria(), extra) => new ModeloFotosInicio({ ...deps(d, extra), almacen });
const foto = (b = [0xff, 0xd8, 1, 2, 3]) => ({ bytes: new Uint8Array(b).buffer, miniatura: 'data:image/jpeg;base64,AA', ancho: 1200, alto: 1600, tomadaEn: '2026-11-10T12:00:00Z', brillo: 120.44, nitidez: 33.06 });
const listo = async (m) => { await m.cargar(); await m.refrescar(); return m; };
const pausa = () => new Promise((r) => setTimeout(r, 20));

let ok = 0, fail = 0;
const casos = [];
const t = (nombre, fn) => casos.push([nombre, fn]);
const si = (c, msg) => { if (!c) throw new Error(msg || 'esperaba verdadero'); };
const eq = (a, b, msg) => { if (JSON.stringify(a) !== JSON.stringify(b)) throw new Error(`${msg || ''} ${JSON.stringify(a)} ≠ ${JSON.stringify(b)}`); };

t('palanca apagada: no llama a nada ni abre la base', async () => {
  const d = doble(); let abrio = 0;
  const m = await arrancar({ ...deps(d), prendida: false, abrirAlmacen: async () => { abrio++; return almacenMemoria(); } });
  eq(m, null); eq(d.llamadas, []); eq(abrio, 0);
  const sinValor = await arrancar({ ...deps(d), prendida: null, abrirAlmacen: async () => { abrio++; return almacenMemoria(); } });
  eq(sinValor, null); eq(d.llamadas, []); eq(abrio, 0);
});
t('habilitado:false, PGRST202 o token caído: un solo get y no se crea la base', async () => {
  for (const ini of [{ habilitado: false }, { sinFuncion: true }, { tokenCaido: true }]) {
    const d = doble(ini); let abrio = 0;
    const m = await arrancar({ ...deps(d), prendida: true, abrirAlmacen: async () => { abrio++; return almacenMemoria(); } });
    eq(m, null, JSON.stringify(ini)); eq(d.llamadas, ['mypump_fotos_inicio_get']); eq(abrio, 0);
  }
});
t('prendida y habilitada: arranca con el estado', async () => {
  const d = doble();
  const m = await arrancar({ ...deps(d), prendida: true, abrirAlmacen: async () => almacenMemoria() });
  si(m && m.visibleSeccion); eq(m.faltan, ['frente', 'perfil', 'espalda']); eq(m.cuenta3, 0); si(!m.listas);
  eq(d.llamadas, ['mypump_fotos_inicio_get'], 'el estado del arranque no se pide dos veces');
});
t('tres poses y completo', async () => {
  const d = doble(); const m = await listo(modelo(d));
  eq(await m.agregar('frente', foto()), 'guardada');
  eq(m.estadoPose('frente'), 'esperando'); eq(m.faltan, ['perfil', 'espalda']); eq(m.cuenta3, 1);
  eq(F.siguiente('frente', m.faltan), 'perfil');
  await m.agregar('perfil', foto()); await m.agregar('espalda', foto());
  si(!m.listas, 'en cola todavía no las tiene Mati');
  await m.drenar();
  eq(d.fotos.map((f) => f.pose), ['frente', 'perfil', 'espalda'], 'en el orden en que se encolaron');
  eq(m.cola.length, 0); si(m.listas); eq(m.estadoPose('perfil'), 'lista');
  await m.refrescar(); si(m.listas); si(m.estado.completo);
  const h = d.cabeceras[0];
  eq(h['x-inicio-token'], TOK); eq(h['Content-Type'], 'image/jpeg'); eq(h['x-inicio-pose'], 'frente');
  eq(h['x-inicio-foto'], 'f1-abc', 'el id va en minúsculas'); eq(h['x-inicio-tomada'], '2026-11-10T12:00:00Z');
  eq(h['x-inicio-brillo'], '120.4'); eq(h['x-inicio-nitidez'], '33.1');
  si(typeof Blob === 'undefined' || d.cuerpos[0] instanceof Blob, 'el cuerpo es el JPEG');
});
t('reemplazo en cola: la nueva de la misma pose saca a la que no empezó a subir', async () => {
  const al = almacenMemoria(); const d = doble({ sinRed: true });
  d.sinRed = false; const m = await listo(modelo(d, al)); d.sinRed = true;
  await m.agregar('frente', foto()); const vieja = m.cola[0].id;
  await m.agregar('perfil', foto());
  await m.agregar('frente', foto([0xff, 0xd8, 9]));
  eq(m.cola.map((c) => c.pose), ['perfil', 'frente']); si(!m.cola.some((c) => c.id === vieja));
  eq(await al.leerBytes(vieja), null, 'los bytes de la vieja se borran');
  eq((await al.listar()).length, 2);
});
t('reemplazo: la que ya está subiendo no se saca; las dos llegan y queda la última', async () => {
  const d = doble(); const m = await listo(modelo(d));
  await m.agregar('frente', foto());
  const primera = m.cola[0].id;
  let soltar; const frenada = new Promise((r) => { soltar = r; });
  const fetchOriginal = d.fetch;
  m.fetch = async (u, o) => { if (u.endsWith('/upload') && o.headers['x-inicio-foto'] === primera) await frenada; return fetchOriginal(u, o); };
  const drenando = m.drenar();
  await pausa(); eq(m.subiendo, primera);
  await m.agregar('frente', foto([0xff, 0xd8, 7]));
  eq(m.cola.length, 2, 'la que sube sigue en la cola');
  soltar(); await drenando; await pausa();
  eq(d.fotos.filter((f) => f.pose === 'frente').length, 1); si(d.fotos[0].id !== primera, 'queda la nueva');
  eq(m.cola.length, 0); eq(m.estado.fotos.filter((f) => f.pose === 'frente').length, 1);
});
t('sin red: queda en la cola, «Esperando señal», y al reanudar sube', async () => {
  const al = almacenMemoria(); const d = doble(); const m = await listo(modelo(d, al));
  d.sinRed = true;
  await m.agregar('frente', foto()); await m.drenar();
  eq(m.cola.length, 1); eq(m.estadoPose('frente'), 'esperando'); eq(d.fotos.length, 0);
  // Recarga sin red: lo último que se supo, con la cola.
  const m2 = modelo(d, al); await listo(m2);
  si(m2.visibleSeccion, 'sin red sigue con lo guardado'); eq(m2.cola.length, 1); eq(m2.estadoPose('frente'), 'esperando');
  d.sinRed = false; m2.reanudar(); await pausa();
  eq(d.fotos.length, 1); eq(m2.cola.length, 0); eq(m2.estadoPose('frente'), 'lista'); eq((await al.listar()).length, 0);
});
t('5xx y 429 reintentan sin gastar la foto', async () => {
  const d = doble({ proximas: [503, 429] }); const m = await listo(modelo(d));
  await m.agregar('frente', foto()); await m.drenar();
  eq(d.fotos.length, 1); eq(d.subidas(), 3); eq(m.aviso, null);
});
t('tres 5xx seguidos: corta la pasada, deja la foto y reintenta sola', async () => {
  const d = doble({ proximas: [500, 502, 503] }); const m = await listo(modelo(d));
  await m.agregar('frente', foto()); await m.drenar();
  await pausa();
  eq(d.fotos.length, 1); eq(m.cola.length, 0);
});
t('200 sin ok (portal cautivo): reintenta', async () => {
  const d = doble(); const m = await listo(modelo(d));
  let una = true; const f0 = d.fetch;
  m.fetch = async (u, o) => { if (una && u.endsWith('/upload')) { una = false; return { status: 200, json: async () => { throw new Error('html'); } }; } return f0(u, o); };
  await m.agregar('frente', foto()); await m.drenar(); eq(d.fotos.length, 1);
});
t('4xx descarta con aviso y no traba a las demás', async () => {
  for (const s of [400, 422]) {
    const d = doble({ proximas: [s] }); const m = await listo(modelo(d));
    await m.agregar('frente', foto()); await m.agregar('perfil', foto()); await m.drenar();
    eq(m.aviso, 'rechazada', String(s)); eq(m.cola.length, 0); eq(d.fotos.map((f) => f.pose), ['perfil']); eq(m.estadoPose('frente'), 'falta');
  }
});
t('409: se descarta sin aviso', async () => {
  const d = doble({ proximas: [409] }); const m = await listo(modelo(d));
  await m.agregar('frente', foto()); await m.drenar(); eq(m.aviso, null); eq(m.cola.length, 0);
});
t('403: descarta y refresca (sección cerrada → se esconde)', async () => {
  const d = doble(); const m = await listo(modelo(d));
  await m.agregar('frente', foto());
  d.cerrada = true; d.habilitado = false;
  await m.drenar();
  eq(m.cola.length, 1, 'con 403 la foto no se borra'); si(!m.visibleSeccion); eq(d.llamadas.filter((x) => x === 'mypump_fotos_inicio_get').length, 2);
});
t('403 con el token caído: se esconde', async () => {
  const d = doble(); const m = await listo(modelo(d));
  await m.agregar('frente', foto()); d.tokenCaido = true; d.cerrada = true;
  await m.drenar(); si(!m.visibleSeccion); si(m.tokenCaido);
});
t('tope de motivación: no deja agregar más y el 413 descarta con aviso', async () => {
  const d = doble(); const m = await listo(modelo(d));
  for (let i = 0; i < 4; i++) eq(await m.agregar('motivacion', foto()), 'guardada');
  si(!m.puedeAgregarMotivacion); eq(await m.agregar('motivacion', foto()), 'tope'); eq(m.aviso, 'tope');
  await m.drenar(); eq(d.fotos.length, 4);
  // El servidor bajó el tope: la que no entra vuelve con 413.
  const e = doble({ maxMotivacion: 1 }); const m2 = await listo(modelo(e));
  eq(await m2.agregar('motivacion', foto()), 'guardada');
  e.maxMotivacion = 0;
  await m2.drenar(); eq(m2.aviso, 'tope'); eq(m2.cola.length, 0); eq(e.fotos.length, 0);
});
t('las de motivación no se reemplazan entre sí', async () => {
  const d = doble(); const m = await listo(modelo(d));
  await m.agregar('motivacion', foto()); await m.agregar('motivacion', foto()); eq(m.cola.length, 2);
  await m.drenar(); eq(d.fotos.length, 2); eq(m.motivacion.length, 2);
});
t('borrar motivación en la cola: sale sin llamar al servidor', async () => {
  const al = almacenMemoria(); const d = doble({ sinRed: true }); d.sinRed = false;
  const m = await listo(modelo(d, al)); d.sinRed = true;
  await m.agregar('motivacion', foto()); const id = m.cola[0].id;
  eq(await m.borrarMotivacion(id), 'ok'); eq(m.cola.length, 0); eq(m.motivacion.length, 0); eq(await al.leerBytes(id), null);
  si(!d.llamadas.includes('vision/borrar'));
});
t('borrar motivación en el servidor: /inicio/borrar con token y foto_id', async () => {
  const d = doble(); const m = await listo(modelo(d));
  await m.agregar('motivacion', foto()); await m.drenar();
  const id = d.fotos[0].id;
  const pedido = []; const f0 = d.fetch; m.fetch = async (u, o) => { if (u.endsWith('/borrar')) pedido.push(JSON.parse(o.body)); return f0(u, o); };
  eq(await m.borrarMotivacion(id), 'ok'); eq(d.fotos.length, 0); eq(m.motivacion.length, 0);
  eq(pedido, [{ token: TOK, foto_id: id }]);
  d.sinRed = true; await m.agregar('motivacion', foto()); d.sinRed = false; await m.drenar();
  d.sinRed = true; eq(await m.borrarMotivacion(d.fotos[0].id), 'sinSenal'); eq(m.motivacion.length, 1);
});
t('borrar una del cuerpo: no se puede', async () => {
  const d = doble(); const m = await listo(modelo(d));
  await m.agregar('frente', foto()); await m.drenar();
  eq(await m.borrarMotivacion(d.fotos[0].id), 'error'); eq(d.fotos.length, 1); si(!d.llamadas.includes('vision/borrar'));
});
t('borrar la que está subiendo: se pide sacarla al terminar', async () => {
  const d = doble(); const m = await listo(modelo(d));
  await m.agregar('motivacion', foto()); const id = m.cola[0].id;
  let soltar; const frenada = new Promise((r) => { soltar = r; }); const f0 = d.fetch;
  m.fetch = async (u, o) => { if (u.endsWith('/upload')) await frenada; return f0(u, o); };
  const dr = m.drenar(); await pausa();
  eq(await m.borrarMotivacion(id), 'ok'); eq(m.motivacion.length, 0);
  soltar(); await dr; await pausa();
  eq(d.fotos.length, 0, 'subió y se borró'); eq(m.motivacion.length, 0); eq(m.borrador.borrarPendientes, []);
});
t('nota: se guarda recortada', async () => {
  const d = doble(); const m = await listo(modelo(d));
  eq(await m.guardarNota('  Hombros\ny cintura  '), 'ok'); eq(d.nota, 'Hombros y cintura'); eq(m.nota, 'Hombros y cintura'); si(!m.notaPendiente);
  eq(d.llamadas.filter((x) => x === 'mypump_fotos_inicio_nota').length, 1);
  await m.guardarNota('x'.repeat(400)); eq(d.nota.length, 300);
});
t('nota pendiente: sin red queda guardada, sobrevive a recargar y sale al drenar', async () => {
  const al = almacenMemoria(); const d = doble(); const m = await listo(modelo(d, al));
  d.sinRed = true;
  eq(await m.guardarNota('la espalda'), 'sinSenal'); si(m.notaPendiente); eq(m.nota, 'la espalda');
  const m2 = modelo(d, al); await listo(m2);
  si(m2.notaPendiente); eq(m2.nota, 'la espalda', 'la pantalla muestra la pendiente');
  d.sinRed = false; await m2.refrescar(); eq(m2.nota, 'la espalda', 'el servidor viejo no la pisa');
  m2.reanudar(); await pausa();
  eq(d.nota, 'la espalda'); si(!m2.notaPendiente); eq(m2.nota, 'la espalda');
});
t('nota con 5xx: pendiente; con error definitivo: no', async () => {
  const d = doble({ notaFalla: { ok: false, status: 503, codigo: '503', clase: 'transitorio' } }); const m = await listo(modelo(d));
  eq(await m.guardarNota('a'), 'sinSenal'); si(m.notaPendiente);
  await m.drenar(); eq(d.nota, 'a'); si(!m.notaPendiente);
  d.notaFalla = { ok: false, status: 400, codigo: '22023', clase: 'permanente' };
  eq(await m.guardarNota('b'), 'error'); si(!m.notaPendiente); eq(d.nota, 'a');
});
t('nota con la sección apagada: se esconde', async () => {
  const d = doble(); const m = await listo(modelo(d)); d.habilitado = false;
  eq(await m.guardarNota('a'), 'error'); si(!m.visibleSeccion);
});
t('miniaturas: /inicio/urls con el token, una vez por hora', async () => {
  const d = doble(); const m = await listo(modelo(d));
  await m.agregar('frente', foto()); await m.drenar();
  const id = d.fotos[0].id;
  await m.firmar([id]); eq(m.urls[id], `https://ejemplo.invalid/${id}.jpg`);
  await m.firmar([id]); eq(d.llamadas.filter((x) => x === 'vision/urls').length, 1);
  m.miniaturas = {};
  eq(m.miniaturaPose('frente'), `https://ejemplo.invalid/${id}.jpg`);
});
t('la foto subió pero se perdió la respuesta: el reintento da ya y no duplica', async () => {
  const d = doble(); const m = await listo(modelo(d));
  await m.agregar('frente', foto()); const id = m.cola[0].id;
  d.fotos.push({ id, pose: 'frente', tomada_en: null, ancho: 1200, alto: 1600 });
  m.estado.fotos = [];
  await m.drenar();
  eq(d.fotos.length, 1); eq(m.cola.length, 0); eq(m.estado.fotos.length, 1);
});
t('lo que sube mientras viaja un get no desaparece', async () => {
  const d = doble(); const m = await listo(modelo(d));
  await m.agregar('frente', foto());
  let soltar; const frenado = new Promise((r) => { soltar = r; }); const r0 = d.rpc;
  const viejo = await r0('mypump_fotos_inicio_get', { p_token: TOK });
  m.rpc = async (f, x) => { if (f === 'mypump_fotos_inicio_get') { await frenado; return viejo; } return r0(f, x); };
  const ref = m.refrescar(); await m.drenar(); soltar(); await ref;
  eq(m.estadoPose('frente'), 'lista');
});
t('estado por pose: falta, esperando, subiendo, lista', async () => {
  const d = doble(); const m = await listo(modelo(d));
  eq(m.estadoPose('perfil'), 'falta');
  await m.agregar('perfil', foto());
  let visto = null; const f0 = d.fetch;
  m.fetch = async (u, o) => { visto = m.estadoPose('perfil'); return f0(u, o); };
  await m.drenar(); eq(visto, 'subiendo'); eq(m.estadoPose('perfil'), 'lista');
});
t('sin estado no encola', async () => {
  const d = doble({ habilitado: false }); const m = await listo(modelo(d));
  eq(await m.agregar('frente', foto()), 'noSeGuardo'); await m.drenar(); eq(d.subidas(), 0);
});
t('cuentas separadas en el mismo teléfono', async () => {
  const al = almacenMemoria(); const d = doble(); const m = await listo(modelo(d, al));
  d.sinRed = true; await m.agregar('frente', foto());
  const otro = new ModeloFotosInicio({ ...deps(d), token: 'otro-token-9876543210', almacen: al });
  await otro.cargar(); eq(otro.cola.length, 0);
});
t('sin indexedDB: cae a memoria', async () => {
  si(!(await abrirAlmacen(null)).persistente);
  si(!(await abrirAlmacen({ open() { throw new Error('SecurityError'); } })).persistente);
});
t('el token no se guarda en el almacén', async () => {
  const al = almacenMemoria(); const d = doble(); const m = await listo(modelo(d, al));
  d.sinRed = true; await m.agregar('frente', foto()); await m.guardarNota('x');
  await pausa();
  const todo = JSON.stringify([await al.listar(), await al.leerKV(`borrador:${cuentaDe(TOK)}`), await al.leerKV(`estado:${cuentaDe(TOK)}`)]);
  si(!todo.includes(TOK)); si(cuentaDe(TOK) && !TOK.includes(cuentaDe(TOK)));
});
t('lo que nadie subió en 30 días se borra', async () => {
  const al = almacenMemoria(); const d = doble(); let reloj = Date.UTC(2026, 9, 1);
  const m = await listo(modelo(d, al, { ahora: () => reloj }));
  d.sinRed = true; await m.agregar('frente', foto());
  reloj += 31 * 86400000;
  const m2 = modelo(d, al, { ahora: () => reloj }); await m2.cargar();
  eq(m2.cola.length, 0); eq((await al.listar()).length, 0);
});

for (const [nombre, fn] of casos) {
  try { await fn(); ok++; } catch (e) { fail++; console.log(`  ✗ ${nombre}\n      ${e.message}`); }
}
console.log(`${fail ? '✗' : '✓'} fotos-inicio-cola: ${ok} ok, ${fail} fallas`);
process.exit(fail ? 1 : 0);
