#!/usr/bin/env node
/* =============================================================
 * test-gimnasio-cola.mjs — la cola y el modelo de «Gimnasio por fotos» contra
 * un doble del servidor (gimnasio/CONTRATO_APP.md), con el almacén en memoria.
 * Mismos escenarios que GimnasioTests.swift y GimnasioTest.kt.
 * IndexedDB real y el canvas se prueban en el navegador.
 * USO:  node scripts/test-gimnasio-cola.mjs
 * ============================================================= */
import { createRequire } from 'node:module';
const require = createRequire(import.meta.url);
const G = require('../public/js/gimnasio.js');
const { ModeloGimnasio, almacenMemoria, abrirAlmacen, cuentaDe } = require('../public/js/gimnasio-cola.js');

const ID = '11111111-1111-4111-8111-111111111111';
const TOK = 'token-de-prueba-0123456789';

function doble(ini = {}) {
  const d = {
    palanca: true, sinFuncion: false, habilitado: true, aceptado: false, sinRed: false, proximas: [], llamadas: [],
    abierta: null, vigente: null, fotos: [], ultimoEnviar: null, ultimoResponder: null, cabeceras: null, ...ini,
  };
  const vista = () => ({
    habilitado: true, consentimiento_version: 'terceros-v1', consentimiento_aceptado: d.aceptado,
    abierta: d.abierta ? { ...d.abierta, fotos: d.fotos.map(({ id, zona, ronda }) => ({ id, zona, ronda })) } : null,
    vigente: d.vigente,
  });
  d.rpc = async (fn, p) => {
    d.llamadas.push(fn);
    if (d.sinRed) return { ok: false, status: 0, codigo: 'NETWORK', clase: 'red' };
    if (d.sinFuncion) return { ok: false, status: 404, codigo: 'PGRST202', clase: 'permanente' };
    const dato = (data) => ({ ok: true, data });
    if (fn === 'mypump_gimnasio_get') return dato(d.habilitado ? vista() : { habilitado: false });
    if (fn === 'mypump_gimnasio_nuevo') {
      if (p.p_modo === 'parcial' && !d.vigente) return dato({ ok: false, error: 'sin_gimnasio_vigente' });
      if (d.abierta) return dato({ ok: true, ya: true, id: d.abierta.id, estado: d.abierta.estado });
      d.abierta = { id: ID, estado: 'borrador', modo: p.p_modo };
      return dato({ ok: true, ya: false, id: ID, estado: 'borrador' });
    }
    if (fn === 'mypump_gimnasio_enviar') {
      if (!d.abierta || d.abierta.id !== p.p_id) return dato({ ok: false, error: 'no_encontrado' });
      if (d.abierta.estado !== 'borrador') return dato({ ok: true, ya: true, estado: 'enviado' });
      if (p.p_consentimiento !== 'terceros-v1') return dato({ ok: false, error: 'sin_consentimiento' });
      d.ultimoEnviar = p;
      if (d.abierta.modo === 'completa') {
        const faltan = G.zonasFaltantes(d.fotos.map((f) => f.zona), p.p_no_hay);
        if (faltan.length) return dato({ ok: false, error: 'faltan_zonas', faltan });
      } else if (!d.fotos.length && !p.p_quitar.length) return dato({ ok: false, error: 'sin_novedad' });
      d.abierta = { ...d.abierta, estado: 'enviado' };
      d.aceptado = true;
      return dato({ ok: true, ya: false, estado: 'enviado' });
    }
    if (fn === 'mypump_gimnasio_responder') {
      if (d.abierta.estado !== 'a_confirmar') return dato({ ok: true, ya: true, estado: 'respondido' });
      d.ultimoResponder = p.p_respuestas;
      d.abierta = { ...d.abierta, estado: 'respondido', preguntas: [] };
      return dato({ ok: true, ya: false, estado: 'respondido' });
    }
    return dato(null);
  };
  d.fetch = async (url, o) => {
    const ruta = url.split('/gimnasio/')[1];
    d.llamadas.push(`vision/${ruta}`);
    const res = (status, j) => ({ status, json: async () => j });
    if (d.sinRed) throw new TypeError('Failed to fetch');
    if (ruta === 'upload') {
      if (d.proximas.length) {
        const s = d.proximas.shift();
        if (s === 0) throw new TypeError('Load failed');
        if (s === 'html') return { status: 200, json: async () => { throw new Error('no es JSON'); } };
        if (s !== 200) return res(s, { ok: false });
      }
      const h = o.headers; d.cabeceras = h;
      if (!d.abierta || h['x-gimnasio-id'] !== d.abierta.id) return res(404, { ok: false });
      if (d.abierta.estado !== 'borrador' && d.abierta.estado !== 'a_confirmar') return res(409, { ok: false });
      if (d.fotos.some((f) => f.id === h['x-gimnasio-foto'])) return res(200, { ok: true, ya: true });
      if (d.fotos.length >= G.TOPE_FOTOS) return res(413, { ok: false });
      d.fotos.push({ id: h['x-gimnasio-foto'], zona: h['x-gimnasio-zona'], ronda: d.abierta.estado === 'borrador' ? 0 : 1 });
      return res(200, { ok: true });
    }
    const j = JSON.parse(o.body);
    if (ruta === 'urls') return res(200, { ok: true, fotos: d.fotos.map((f) => ({ id: f.id, zona: f.zona, url: `https://ejemplo.invalid/${f.id}.jpg` })), expira_en: 3600 });
    if (ruta === 'borrar') {
      if (d.abierta.estado !== 'borrador') return res(409, { ok: false });
      d.fotos = d.fotos.filter((f) => f.id !== j.foto_id);
      return res(200, { ok: true });
    }
    return res(404, {});
  };
  d.subidas = () => d.llamadas.filter((x) => x === 'vision/upload').length;
  return d;
}

let n = 0;
function modelo(d, almacen = almacenMemoria(), token = TOK) {
  const m = new ModeloGimnasio({
    rpc: (f, x) => d.rpc(f, x), fetch: (u, o) => d.fetch(u, o), almacen, token, visionUrl: 'https://vision.ejemplo.test/',
    esperar: () => new Promise((r) => setTimeout(r, 0)), nuevoId: () => `f${++n}`,
  });
  return m;
}
const foto = (b = [1, 2, 3]) => ({ bytes: new Uint8Array(b).buffer, miniatura: 'data:image/jpeg;base64,AA' });
const borrador = (extra) => ({ abierta: { id: ID, estado: 'borrador', modo: 'completa' }, aceptado: true, ...extra });
const listo = async (m) => { await m.cargar(); await m.refrescar(); return m; };
const TODAS = G.ZONAS.map((z) => z.clave).filter((z) => z !== 'otros');

let ok = 0, fail = 0;
const casos = [];
const t = (nombre, fn) => casos.push([nombre, fn]);
const si = (c, msg) => { if (!c) throw new Error(msg || 'esperaba verdadero'); };
const eq = (a, b, msg) => { if (JSON.stringify(a) !== JSON.stringify(b)) throw new Error(`${msg || ''} ${JSON.stringify(a)} ≠ ${JSON.stringify(b)}`); };

t('palanca apagada para la cuenta: no se muestra nada', async () => {
  const d = doble({ habilitado: false }); const m = await listo(modelo(d));
  si(!m.estado); si(!m.tarjetaVisible); si(!m.entradaVisible);
  await m.drenar(); eq(d.subidas(), 0);
});
t('sin el servidor nuevo (PGRST202): no se muestra nada ni se reintenta', async () => {
  const d = doble({ sinFuncion: true }); const m = await listo(modelo(d));
  si(!m.estado); eq(d.llamadas, ['mypump_gimnasio_get']);
});
t('sin red y sin nada guardado: no se muestra', async () => {
  const d = doble({ sinRed: true }); const m = await listo(modelo(d)); si(!m.estado);
});
t('sin red con una carga a medias: sigue; con otra cosa, no', async () => {
  const al = almacenMemoria();
  const d = doble(borrador()); await listo(modelo(d, al));
  d.sinRed = true;
  const m2 = await listo(modelo(d, al));
  eq(m2.pantalla, 'zonas');
  const e = doble({ abierta: { id: ID, estado: 'procesando', modo: 'completa' } }); const al2 = almacenMemoria();
  await listo(modelo(e, al2)); e.sinRed = true;
  si(!(await listo(modelo(e, al2))).estado);
});
t('token caído (null): se esconde', async () => {
  const d = doble(); d.rpc = async () => ({ ok: true, data: null });
  si(!(await listo(modelo(d))).estado);
});
t('aviso de terceros una sola vez', async () => {
  const al = almacenMemoria(); const d = doble(); const m = await listo(modelo(d, al));
  si(m.necesitaAviso); await m.aceptarAviso(); si(!m.necesitaAviso);
  si(!(await listo(modelo(d, al))).necesitaAviso, 'al volver no se repite');
});
t('envío completo: fotos, no hay, nota y consentimiento', async () => {
  const d = doble(); const m = await listo(modelo(d));
  await m.aceptarAviso(); eq(await m.empezar(), 'ok'); eq(m.pantalla, 'zonas');
  for (const z of TODAS.slice(0, -1)) eq(await m.agregar(z, foto()), 'guardada');
  m.marcarNoHay('bancos', true); m.fijarNota('x'.repeat(400)); eq(m.nota.length, 300);
  si(m.puedeEnviar); await m.enviarCarga();
  eq(d.fotos.length, 8); eq(d.ultimoEnviar.p_no_hay, ['bancos']); eq(d.ultimoEnviar.p_consentimiento, 'terceros-v1'); eq(d.ultimoEnviar.p_nota.length, 300); eq(d.ultimoEnviar.p_quitar, []);
  eq(m.pantalla, 'recibido'); eq(m.envio, null); eq(m.cola.length, 0);
  eq(d.cabeceras['x-gimnasio-token'], TOK); eq(d.cabeceras['Content-Type'], 'image/jpeg');
});
t('el envío espera a la cola y sale con lo último', async () => {
  const d = doble(borrador({ sinRed: true })); d.sinRed = false;
  const m = await listo(modelo(d));
  d.sinRed = true;
  for (const z of TODAS) await m.agregar(z, foto());
  await m.enviarCarga();
  eq(d.llamadas.includes('mypump_gimnasio_enviar'), false, 'no sale sin las fotos');
  si(m.envio); eq(m.cola.length, 9);
  d.sinRed = false; m.reanudar();
  await new Promise((r) => setTimeout(r, 30));
  eq(d.fotos.length, 9); eq(m.pantalla, 'recibido');
});
t('corte a mitad: no se pierde nada, sigue tras recargar, sin duplicar', async () => {
  const al = almacenMemoria(); const d = doble(borrador({ proximas: [200, 0] })); const m = await listo(modelo(d, al));
  await m.agregar('poleas', foto()); await m.agregar('piernas', foto()); await m.agregar('discos', foto());
  await m.drenar();
  eq(d.fotos.length, 1); eq(m.cola.length, 2);
  const m2 = await listo(modelo(d, al));
  eq(m2.cola.length, 2); await m2.drenar();
  eq(d.fotos.length, 3); eq(m2.cola.length, 0); eq((await al.listar()).length, 0);
  eq(await al.leerBytes(d.fotos[2].id), null, 'los bytes se borran al subir');
});
t('la foto subió pero se perdió la respuesta: el reintento da ya y no duplica', async () => {
  const d = doble(borrador()); const m = await listo(modelo(d));
  await m.agregar('poleas', foto());
  const id = m.cola[0].id;
  d.fotos.push({ id, zona: 'poleas', ronda: 0 });
  m.estado.abierta.fotos = [];
  await m.drenar();
  eq(d.fotos.filter((f) => f.id === id).length, 1); eq(m.cola.length, 0); eq(m.abierta.fotos.filter((f) => f.id === id).length, 1);
});
t('reintento: 503 y 429 no gastan la foto', async () => {
  const d = doble(borrador({ proximas: [503, 429] })); const m = await listo(modelo(d));
  await m.agregar('poleas', foto()); await m.drenar();
  eq(d.fotos.length, 1); eq(d.subidas(), 3); eq(m.avisoFoto, null);
});
t('200 que no es JSON (portal cautivo): reintenta', async () => {
  const d = doble(borrador({ proximas: ['html'] })); const m = await listo(modelo(d));
  await m.agregar('poleas', foto()); await m.drenar(); eq(d.fotos.length, 1); eq(d.subidas(), 2);
});
t('tres 503 seguidos: corta, deja la foto y reintenta sola', async () => {
  const d = doble(borrador({ proximas: [503, 503, 503] })); const m = await listo(modelo(d));
  await m.agregar('poleas', foto()); await m.drenar();
  await new Promise((r) => setTimeout(r, 30));
  eq(d.fotos.length, 1); eq(m.cola.length, 0);
});
t('una foto que el servidor no puede guardar no traba a las demás', async () => {
  const d = doble(borrador({ proximas: [503] })); const m = await listo(modelo(d));
  await m.agregar('poleas', foto()); await m.agregar('piernas', foto()); await m.drenar();
  eq(d.fotos.map((f) => f.zona), ['piernas', 'poleas']);
});
t('foto rechazada (400): se descarta y avisa', async () => {
  const d = doble(borrador({ proximas: [400] })); const m = await listo(modelo(d));
  await m.agregar('poleas', foto()); await m.drenar();
  eq(m.cola.length, 0); eq(m.avisoFoto, 'rechazada'); eq(d.subidas(), 1); si(m.faltantes.includes('poleas'));
});
t('413: se descarta y avisa el tope', async () => {
  const d = doble(borrador({ proximas: [413] })); const m = await listo(modelo(d));
  await m.agregar('poleas', foto()); await m.drenar(); eq(m.avisoFoto, 'tope');
});
t('403 descarta sin aviso; 404 y 409 descartan y refrescan', async () => {
  for (const [s, refresca] of [[403, 0], [404, 1], [409, 1]]) {
    const d = doble(borrador({ proximas: [s] })); const m = await listo(modelo(d));
    const antes = () => d.llamadas.filter((x) => x === 'mypump_gimnasio_get').length;
    await m.agregar('poleas', foto()); await m.drenar();
    eq(m.cola.length, 0); eq(m.avisoFoto, null); eq(antes(), 1 + refresca, `status ${s}`);
  }
});
t('tope de 80: la 81 no entra; las de pregunta no cuentan', async () => {
  const d = doble(borrador()); d.fotos = Array.from({ length: 79 }, (_, i) => ({ id: `s${i}`, zona: 'poleas', ronda: 0 }));
  const m = await listo(modelo(d));
  eq(await m.agregar('poleas', foto()), 'guardada');
  si(!m.puedeAgregar); eq(await m.agregar('poleas', foto()), 'tope'); eq(m.avisoFoto, 'tope'); eq(m.cola.length, 1);
  d.abierta.estado = 'a_confirmar'; await m.refrescar();
  eq(await m.agregar('bancos', foto(), 'foto_1'), 'guardada');
});
t('no se pudo guardar en el teléfono: avisa y no encola', async () => {
  const d = doble(borrador()); const al = almacenMemoria(); al.agregarFoto = async () => { throw new Error('QuotaExceededError'); };
  const m = await listo(modelo(d, al));
  eq(await m.agregar('poleas', foto()), 'noSeGuardo'); eq(m.cola.length, 0);
});
t('borrar en cola, subiendo y en el servidor', async () => {
  const d = doble(borrador()); const m = await listo(modelo(d));
  await m.agregar('poleas', foto()); eq(await m.borrarFoto(m.cola[0].id), 'ok'); eq(m.cola.length, 0);
  await m.agregar('poleas', foto()); await m.drenar(); const id = d.fotos[0].id;
  eq(await m.borrarFoto(id), 'ok'); eq(d.fotos.length, 0); eq(m.abierta.fotos.length, 0);
  // Mientras sube
  await m.agregar('piernas', foto());
  const m2 = m; const orig = m2.fetch;
  m2.fetch = async (u, o) => { if (u.endsWith('upload')) await m2.borrarFoto(m2.subiendo); return orig(u, o); };
  await m2.drenar();
  eq(d.fotos.length, 0, 'la que se borró subiendo no queda en el servidor');
});
t('borrar sin red y 409', async () => {
  const d = doble(borrador()); d.fotos = [{ id: 's1', zona: 'poleas', ronda: 0 }]; const m = await listo(modelo(d));
  d.sinRed = true; eq(await m.borrarFoto('s1'), 'sinSenal'); d.sinRed = false;
  d.abierta.estado = 'enviado'; eq(await m.borrarFoto('s1'), 'error');
});
t('la foto saca el No hay de su zona', async () => {
  const d = doble(borrador()); const m = await listo(modelo(d));
  m.marcarNoHay('poleas', true); await m.agregar('poleas', foto()); si(!m.noHay.has('poleas'));
});
t('faltan_zonas del servidor: marca las zonas y vuelve a editar', async () => {
  const d = doble(borrador()); const m = await listo(modelo(d));
  m.marcarNoHay('poleas', true); await m.agregar('piernas', foto());
  for (const z of TODAS) if (z !== 'poleas' && z !== 'piernas') m.marcarNoHay(z, true);
  const r0 = d.rpc;
  d.rpc = async (fn, p) => (fn === 'mypump_gimnasio_enviar' ? { ok: true, data: { ok: false, error: 'faltan_zonas', faltan: ['poleas'] } } : r0(fn, p));
  await m.enviarCarga();
  eq(m.avisoEnvio, { faltan: ['poleas'] }); eq(m.envio, null); eq(m.pantalla, 'zonas');
});
t('sin_consentimiento: vuelve a mostrar el aviso', async () => {
  const d = doble({ abierta: { id: ID, estado: 'borrador', modo: 'completa' } }); const m = await listo(modelo(d));
  await m.aceptarAviso(); for (const z of TODAS) m.marcarNoHay(z, true);
  const r0 = d.rpc;
  d.rpc = async (fn, p) => (fn === 'mypump_gimnasio_enviar' ? { ok: true, data: { ok: false, error: 'sin_consentimiento' } } : r0(fn, p));
  await m.enviarCarga(); si(m.necesitaAviso); eq(m.envio, null);
});
t('no_habilitado al enviar: se esconde', async () => {
  const d = doble(borrador()); const m = await listo(modelo(d)); await m.agregar('poleas', foto());
  const r0 = d.rpc;
  d.rpc = async (fn, p) => (fn === 'mypump_gimnasio_enviar' ? { ok: true, data: { ok: false, error: 'no_habilitado' } } : r0(fn, p));
  for (const z of TODAS) m.marcarNoHay(z, true);
  await m.enviarCarga(); si(!m.estado);
});
t('enviar sin red queda guardado y al volver sale una sola vez', async () => {
  const al = almacenMemoria(); const d = doble(borrador()); const m = await listo(modelo(d, al));
  for (const z of TODAS) m.marcarNoHay(z, true);
  const r0 = d.rpc; let caido = true;
  d.rpc = async (fn, p) => (fn === 'mypump_gimnasio_enviar' && caido ? { ok: false, status: 0, codigo: 'NETWORK', clase: 'red' } : r0(fn, p));
  m._programarReintento = () => {};
  await m.enviarCarga(); si(m.envio);
  caido = false;
  const m2 = await listo(modelo(d, al)); si(m2.envio); await m2.drenar();
  eq(m2.envio, null); eq(m2.pantalla, 'recibido'); eq(d.ultimoEnviar.p_no_hay.length, 9);
});
t('el servidor ya tomó el envío: la marca se limpia sola', async () => {
  const al = almacenMemoria(); const d = doble(borrador()); const m = await listo(modelo(d, al));
  m.borrador.envio = { tipo: 'enviar', gimnasioId: ID, noHay: [], nota: '', consentimiento: 'terceros-v1', quitar: [] };
  d.abierta.estado = 'procesando'; await m.refrescar(); eq(m.envio, null);
});
t('volver a editar: cancela el envío, la cola sigue', async () => {
  const d = doble(borrador()); const m = await listo(modelo(d));
  d.sinRed = true; await m.agregar('poleas', foto()); for (const z of TODAS) m.marcarNoHay(z, true);
  await m.enviarCarga(); si(m.envio); await m.cancelarEnvio(); eq(m.envio, null); eq(m.cola.length, 1);
  d.sinRed = false; await m.drenar(); eq(d.fotos.length, 1); eq(d.llamadas.includes('mypump_gimnasio_enviar'), false);
});
t('faltan fotos: la de la ronda va antes de responder y responde incompleto', async () => {
  const preguntas = [
    { id: 'peso', clase: 'numero', texto: 't', unidad: 'kg' },
    { id: 'foto_1', clase: 'foto', zona: 'bancos', texto: 't', fotos: [] },
    { id: 'sin_contestar', clase: 'elegir', multiple: false, texto: 't', opciones: [{ valor: 'a', texto: 'A' }] },
  ];
  const d = doble({ abierta: { id: ID, estado: 'a_confirmar', modo: 'completa', preguntas }, aceptado: true }); const m = await listo(modelo(d));
  eq(m.pantalla, 'preguntas');
  m.responder('peso', 32.5); eq(G.fotosPedidas(m.abierta.preguntas, m.respuestas), 1);
  await m.agregar('bancos', foto(), 'foto_1'); eq(m.respuestas.foto_1, 'subida');
  const orden = []; const r0 = d.rpc, f0 = d.fetch;
  d.rpc = async (fn, p) => { if (fn.includes('responder')) orden.push('responder'); return r0(fn, p); };
  d.fetch = async (u, o) => { if (u.endsWith('upload')) orden.push('foto'); return f0(u, o); };
  m.fetch = d.fetch; m.rpc = d.rpc;
  await m.enviarRespuestas();
  eq(orden, ['foto', 'responder']); eq(d.ultimoResponder, { peso: 32.5, foto_1: 'subida' }); eq(d.fotos[0].ronda, 1); eq(m.pantalla, 'recibido');
});
t('la foto de una pregunta rechazada: se la vuelve a pedir y no responde', async () => {
  const preguntas = [{ id: 'foto_1', clase: 'foto', zona: 'bancos', texto: 't' }];
  const d = doble({ abierta: { id: ID, estado: 'a_confirmar', modo: 'completa', preguntas }, aceptado: true, proximas: [400] }); const m = await listo(modelo(d));
  await m.agregar('bancos', foto(), 'foto_1'); await m.enviarRespuestas();
  eq(m.envio, null); eq(m.respuestas.foto_1, undefined); eq(m.avisoFoto, 'rechazada'); eq(d.llamadas.includes('mypump_gimnasio_responder'), false);
});
t('parcial con algo que ya no está; sin vigente cae a completa; sin novedad avisa', async () => {
  const vigente = { id: 'v1', estado: 'listo', modo: 'completa', resultado: 'adaptada', equipos: [{ tipo: 'pec_deck', nombre: 'Pec deck', zona: 'empuje', cantidad: 1 }] };
  const d = doble({ aceptado: true, vigente }); const m = await listo(modelo(d));
  eq(m.pantalla, 'listo'); si(m.entradaVisible); si(!m.tarjetaVisible);
  eq(await m.empezar('parcial'), 'ok'); eq(m.abierta.modo, 'parcial'); eq(m.faltantes, []);
  si(!m.puedeEnviar); m.alternarQuitar('pec_deck'); si(m.puedeEnviar);
  await m.enviarCarga(); eq(d.ultimoEnviar.p_quitar, ['pec_deck']); eq(m.pantalla, 'recibido');
  const e = doble({ aceptado: true }); const n2 = await listo(modelo(e));
  eq(await n2.empezar('parcial'), 'ok'); eq(n2.abierta.modo, 'completa');
});
t('una carga nueva no hereda el borrador de la anterior', async () => {
  const al = almacenMemoria(); const d = doble(borrador()); const m = await listo(modelo(d, al));
  m.marcarNoHay('poleas', true); m.fijarNota('hola');
  d.abierta = { id: '22222222-2222-4222-8222-222222222222', estado: 'borrador', modo: 'completa' };
  await m.refrescar(); eq(m.nota, ''); eq([...m.noHay], []);
});
t('dos cuentas en un teléfono no se mezclan; otro link de la misma persona sigue la carga', async () => {
  const al = almacenMemoria(); const d = doble(borrador()); const m = await listo(modelo(d, al));
  await m.agregar('poleas', foto());
  const ajena = doble({ aceptado: true }); const b = await listo(modelo(ajena, al, 'otra-cuenta-0123456789'));
  eq(b.cola.length, 0, 'la de otro no se ve');
  await b.drenar(); eq(ajena.subidas(), 0);
  const mismo = await listo(modelo(d, al, 'link-nuevo-0123456789abc'));
  eq(mismo.cola.length, 1, 'misma carga, otro link'); await mismo.drenar(); eq(d.fotos.length, 1);
});
t('lo que quedó hace más de 30 días se borra', async () => {
  const al = almacenMemoria(); const d = doble(borrador()); const m = await listo(modelo(d, al));
  await m.agregar('poleas', foto());
  const m2 = modelo(d, al); m2.ahora = () => Date.now() + 31 * 24 * 3600 * 1000; await m2.cargar();
  eq((await al.listar()).length, 0);
});
t('una foto agregada mientras se relee la cola no desaparece', async () => {
  const al = almacenMemoria(); const d = doble(borrador()); const m = await listo(modelo(d, al));
  const listar0 = al.listar; let solto; const freno = new Promise((r) => { solto = r; });
  al.listar = async () => { const r = await listar0(); await freno; return r; };
  const lectura = m._releerCola(false);
  await new Promise((r) => setTimeout(r, 0));
  await m.agregar('poleas', foto());
  solto(); await lectura;
  eq(m.cola.length, 1);
});
t('dos pasadas a la vez no suben dos veces', async () => {
  const d = doble(borrador()); const m = await listo(modelo(d));
  await m.agregar('poleas', foto()); await Promise.all([m.drenar(), m.drenar(), m.drenar()]);
  eq(d.subidas(), 1);
});
t('firmar: una vez y no cachea de más', async () => {
  const d = doble(borrador()); d.fotos = [{ id: 's1', zona: 'poleas', ronda: 0 }]; const m = await listo(modelo(d));
  await m.firmar(ID, ['s1']); si(m.urls.s1); await m.firmar(ID, ['s1']);
  eq(d.llamadas.filter((x) => x === 'vision/urls').length, 1);
  const r = m.ahora; m.ahora = () => r() + 51 * 60 * 1000; await m.firmar(ID, ['s1']);
  eq(d.llamadas.filter((x) => x === 'vision/urls').length, 2);
});
t('sin servidor de fotos ni de datos: cero subidas con la palanca apagada', async () => {
  const d = doble({ habilitado: false }); const al = almacenMemoria(); const m = await listo(modelo(d, al));
  m.reanudar(); await new Promise((r) => setTimeout(r, 5)); eq(d.subidas(), 0); eq(await m.agregar('poleas', foto()), 'noSeGuardo');
});
t('sin indexedDB: cae a memoria', async () => {
  si(!(await abrirAlmacen(null)).persistente);
  const roto = { open() { throw new Error('SecurityError'); } };
  si(!(await abrirAlmacen(roto)).persistente);
});
t('el hash de cuenta no contiene el token', () => {
  const c = cuentaDe(TOK); si(c && !TOK.includes(c) && !c.includes('token')); eq(cuentaDe(TOK), c);
});
t('el token no se guarda en el almacén', async () => {
  const al = almacenMemoria(); const d = doble(borrador()); const m = await listo(modelo(d, al));
  await m.agregar('poleas', foto()); m.marcarNoHay('bancos', true);
  await new Promise((r) => setTimeout(r, 0));
  const todo = JSON.stringify([await al.listar(), await al.leerKV(`borrador:${cuentaDe(TOK)}`), await al.leerKV(`estado:${cuentaDe(TOK)}`)]);
  si(!todo.includes(TOK));
});

for (const [nombre, fn] of casos) {
  try { await fn(); ok++; } catch (e) { fail++; console.log(`  ✗ ${nombre}\n      ${e.message}`); }
}
console.log(`${fail ? '✗' : '✓'} gimnasio-cola: ${ok} ok, ${fail} fallas`);
process.exit(fail ? 1 : 0);
