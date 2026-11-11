// «Tu recorrido» (fin de plan, palanca `fin_plan`): reglas y modelo de public/js/recorrido.js.
// Contrato: cola-b/CONTRATO_APP.md, sección 1. Datos de prueba inventados.
import { createRequire } from 'node:module';
import assert from 'node:assert/strict';
import { almacen, rpcDoble, ok, RED, NO_EXISTE, CAIDO } from './lib/doble-rpc.mjs';
const require = createRequire(import.meta.url);
const R = require('../public/js/recorrido.js');
let n = 0;
const eq = (a, b, m) => { assert.deepEqual(a, b, m); n++; };
const si = (v, m) => { assert.ok(v, m); n++; };

const RESUMEN = { titulo: 'Tus 3 meses', mensaje: 'Mensaje de prueba.', logros: [
  { titulo: 'Entrenamientos hechos', valor: '41', detalle: 'De 48 planificados' },
  { titulo: 'Fuerza en sentadilla', valor: '+15 kg' }] };
const visible = (estado = 'publicado', mas = {}) => ({ habilitado: true, visible: true, estado, resumen: RESUMEN, respuestas: {}, agenda: 'mati', ...mas });
const TOKEN = 'token-de-prueba';
const CTA = R.cuentaDe(TOKEN);
const UUID = '11111111-2222-4333-8444-555555555555';
const nuevo = (resp, alm = almacen(), ids = [UUID]) => {
  const rpc = rpcDoble(resp);
  const m = R.crearModelo({ token: TOKEN, rpc, almacen: alm, nuevoId: () => ids.shift() || 'sin-id' });
  return { m, rpc, alm };
};

// ---- Decodificar: lo que no se entiende no se muestra.
eq(R.decodificar(null), null, 'NULL (token caído)');
eq(R.decodificar({ habilitado: false }), null, 'habilitado:false');
eq(R.decodificar({ habilitado: true, visible: false }), null, 'visible:false');
eq(R.decodificar(visible('cerrado')), null, 'estado desconocido');
eq(R.decodificar(visible('publicado', { resumen: { logros: [] } })), null, 'sin logros');
eq(R.decodificar(visible('publicado', { resumen: { logros: [{ titulo: 'x' }, { valor: '3' }, 7, null] } })), null, 'sin logros válidos');
eq(R.decodificar(visible('publicado', { resumen: null })), null, 'sin resumen');
{
  const d = R.decodificar(visible());
  eq([d.estado, d.titulo, d.mensaje, d.agenda, d.logros.length], ['publicado', 'Tus 3 meses', 'Mensaje de prueba.', 'mati', 2], 'visible');
  eq(d.logros[1], { titulo: 'Fuerza en sentadilla', valor: '+15 kg', detalle: null }, 'detalle opcional');
  eq(R.decodificar(visible('pedido', { resumen: { logros: RESUMEN.logros } })).titulo, 'Tu recorrido', 'título por defecto');
  eq(R.decodificar(visible('pedido', { agenda: 'app' })).agenda, 'app', 'agenda app');
  eq(R.decodificar(visible('pedido', { agenda: 'otra' })).agenda, 'mati', 'agenda desconocida = mati');
  eq(R.decodificar(visible('publicado', { resumen: { logros: Array.from({ length: 9 }, (_, i) => ({ titulo: `L${i}`, valor: i })) } })).logros.length, 6, 'tope de 6 logros');
  eq(R.decodificar(visible('publicado', { resumen: { logros: [{ titulo: 'Kilos', valor: 12 }] } })).logros[0].valor, '12', 'valor numérico');
  eq(R.decodificar(visible('pedido', { respuestas: { mejor: ' Bien ', costo: '', otra: 'x', objetivo: 7 } })).respuestas, { mejor: 'Bien', objetivo: '7' }, 'respuestas');
  eq(R.decodificar(visible('publicado', { campo_nuevo: { a: 1 } })).estado, 'publicado', 'un campo nuevo no rompe');
}

// ---- Textos del contrato, tal cual.
eq([R.textoTarjeta('publicado'), R.textoTarjeta('pedido'), R.textoTarjeta('agendado'), R.textoTarjeta('otro')],
  ['Mirá todo lo que hiciste en estos meses.', 'Mati ya recibió tu pedido.', 'Tu videollamada con Mati ya está agendada.', null], 'tarjeta');
eq([R.textoListo('mati'), R.textoListo('app')], ['Te escribe para coordinar el horario.', 'Cuando esté tu horario lo vas a ver arriba de Entreno.'], 'listo según agenda');
eq(R.CAMPOS.map((c) => [c.clave, c.id, c.pregunta]), [
  ['mejor', 'recorrido-mejor', '¿Qué fue lo mejor de estos meses?'], ['costo', 'recorrido-costo', '¿Qué te costó más?'],
  ['objetivo', 'recorrido-objetivo', '¿Qué te gustaría lograr ahora?']], 'los tres campos');
for (const t of Object.values(R.T)) {
  assert.ok(!/\b(ia|coach|entrenador|renovaci[oó]n|vence|vencimiento|pausa|vacaciones|rir)\b/i.test(t), `texto prohibido: ${t}`); n++;
}
eq(Array.from(R.recortar('é'.repeat(600))).length, 500, 'tope de 500');
eq(Array.from(R.recortar('😀'.repeat(600))).length, 500, 'tope de 500 contando caracteres, no unidades');
eq(R.respuestasParaEnviar({ mejor: '  Dormir mejor  ', costo: '   ', objetivo: 'x'.repeat(700), otra: 'no' }), { mejor: 'Dormir mejor', objetivo: 'x'.repeat(500) }, 'respuestas para enviar');
si(/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/.test(R.uuid()), 'uuid');

// ---- Apagada: no llama a ningún RPC, haga lo que haga.
for (const cfg of [{}, { fin_plan: false }, { fin_plan: 'true' }, { fin_plan: 1 }, null]) {
  const { m, rpc } = nuevo({ mypump_fin_plan_get: ok(visible()) });
  eq(m.aplicarConfig(cfg), false, `apagada con ${JSON.stringify(cfg)}`);
  await m.refrescar(); m.visto(); m.escribir('mejor', 'x'); await m.pedir();
  eq([rpc.llamadas.length, m.estado, m.debeAbrirseSola], [0, null, false], 'apagada no llama ni muestra');
}

// ---- Prendida: estados.
{
  const { m, rpc, alm } = nuevo({ mypump_fin_plan_get: ok(visible()) });
  eq(m.aplicarConfig({ fin_plan: true }), true, 'prendida');
  eq(m.estado, null, 'antes de preguntar no se ve nada');
  let avisos = 0; m.alCambiar(() => avisos++);
  await m.refrescar();
  eq([m.estado.estado, rpc.nombres(), rpc.llamadas[0].params], ['publicado', ['mypump_fin_plan_get'], { p_token: TOKEN }], 'solo viaja el token');
  si(avisos > 0, 'avisa');
  si(alm.m.has(`mypump_recorrido_${CTA}`), 'queda la copia');
  // Se abre sola una vez por cuenta.
  eq(m.debeAbrirseSola, true, 'la primera vez se abre sola');
  m.marcarAbiertaSola();
  eq(m.debeAbrirseSola, false, 'una sola vez');
  eq(R.crearModelo({ token: 'otra-cuenta', rpc, almacen: alm }).debeAbrirseSola, false, 'otra cuenta, apagada');
  // visto: una vez por carga.
  m.visto(); m.visto();
  eq(rpc.de('mypump_fin_plan_visto').length, 1, 'visto una vez');
  // Un corte de red deja lo que ya se veía.
  rpc.respuestas.mypump_fin_plan_get = RED;
  await m.refrescar();
  eq(m.estado.estado, 'publicado', 'sin red queda lo que se veía');
  rpc.respuestas.mypump_fin_plan_get = CAIDO;
  await m.refrescar();
  eq(m.estado.estado, 'publicado', 'con el servidor caído también');
  // Otra carga sin red: sale de la copia. Con la función borrada o visible:false, desaparece y se borra la copia.
  const otro = R.crearModelo({ token: TOKEN, rpc: rpcDoble({ mypump_fin_plan_get: RED }), almacen: alm });
  otro.aplicarConfig(null);
  await otro.refrescar();
  eq(otro.estado && otro.estado.estado, 'publicado', 'sin red al cargar: la copia, con la palanca que se supo');
  for (const r of [NO_EXISTE, { ok: false, status: 404, codigo: 'HTTP', clase: 'permanente' }, ok(null), ok({ habilitado: false }), ok({ habilitado: true, visible: false }), ok(visible('raro'))]) {
    const a2 = almacen(Object.fromEntries(alm.m));
    const x = R.crearModelo({ token: TOKEN, rpc: rpcDoble({ mypump_fin_plan_get: r }), almacen: a2 });
    x.aplicarConfig({ fin_plan: true });
    await x.refrescar();
    eq([x.estado, a2.m.has(`mypump_recorrido_${CTA}`)], [null, false], `no se ve con ${JSON.stringify(r).slice(0, 60)}`);
  }
  // Se apaga la palanca: deja de verse y se borra la copia.
  m.aplicarConfig({ fin_plan: false });
  eq([m.estado, alm.m.has(`mypump_recorrido_${CTA}`)], [null, false], 'al apagarla desaparece');
}
for (const e of ['pedido', 'agendado']) {
  const { m } = nuevo({ mypump_fin_plan_get: ok(visible(e)) });
  m.aplicarConfig({ fin_plan: true });
  await m.refrescar();
  eq([m.estado.estado, m.debeAbrirseSola, await m.pedir()], [e, false, 'nada'], `${e}: no se abre sola ni se puede pedir`);
}

// ---- El pedido: el id queda en disco ANTES de mandar y los reintentos usan el mismo.
{
  const kId = `mypump_recorrido_pedido_${CTA}`, kBorr = `mypump_recorrido_borrador_${CTA}`;
  let enDiscoAlMandar = null;
  const alm = almacen();
  const { m, rpc } = nuevo({ mypump_fin_plan_get: ok(visible()), mypump_fin_plan_pedir: () => { enDiscoAlMandar = alm.leer(kId); return RED; } }, alm, [UUID, 'otro-id']);
  m.aplicarConfig({ fin_plan: true });
  await m.refrescar();
  m.escribir('mejor', '  Aprendí a comer  ');
  m.escribir('costo', 'y'.repeat(800));
  m.escribir('inventada', 'no');
  eq(m.textos, { mejor: '  Aprendí a comer  ', costo: 'y'.repeat(500), objetivo: '' }, 'lo escrito, con tope');
  si(alm.m.has(kBorr), 'lo escrito queda en disco');
  eq(R.crearModelo({ token: TOKEN, rpc, almacen: alm }).textos.mejor, '  Aprendí a comer  ', 'y vuelve en otra carga');
  eq(await m.pedir(), 'error', 'sin red');
  eq([enDiscoAlMandar, m.error, m.enviando, m.estado.estado], [UUID, true, false, 'publicado'], 'id en disco antes de mandar; error y sigue publicado');
  eq(rpc.de('mypump_fin_plan_pedir')[0].params, { p_token: TOKEN, p_id: UUID, p_respuestas: { mejor: 'Aprendí a comer', costo: 'y'.repeat(500) } }, 'lo que viaja');
  rpc.respuestas.mypump_fin_plan_pedir = CAIDO;
  eq(await m.pedir(), 'error', 'servidor caído');
  rpc.respuestas.mypump_fin_plan_pedir = ok(null);
  eq(await m.pedir(), 'error', 'NULL');
  rpc.respuestas.mypump_fin_plan_pedir = ok({ ok: false, error: 'otro' });
  eq(await m.pedir(), 'error', 'error desconocido');
  // Otra carga de la página (otro modelo): reintenta con el MISMO id.
  const rpc2 = rpcDoble({ mypump_fin_plan_get: ok(visible()), mypump_fin_plan_pedir: ok({ ok: true, ya: true, estado: 'pedido' }) });
  const m2 = R.crearModelo({ token: TOKEN, rpc: rpc2, almacen: alm, nuevoId: () => 'id-nuevo-que-no-debe-usarse' });
  m2.aplicarConfig({ fin_plan: true });
  await m2.refrescar();
  eq(await m2.pedir(), 'ok', 'reintento');
  eq(new Set([...rpc.de('mypump_fin_plan_pedir'), ...rpc2.de('mypump_fin_plan_pedir')].map((l) => l.params.p_id)), new Set([UUID]), 'siempre el mismo id');
  eq([m2.estado.estado, m2.estado.respuestas.mejor, m2.error, alm.m.has(kId), alm.m.has(kBorr)], ['pedido', 'Aprendí a comer', false, false, false], 'pedido: sin id ni borrador');
  eq(await m2.pedir(), 'nada', 'ya pedido no se manda de nuevo');
  eq(rpc2.de('mypump_fin_plan_pedir').length, 1, 'una sola vez');
  eq(R.decodificar(JSON.parse(alm.leer(`mypump_recorrido_${CTA}`))).estado, 'pedido', 'la copia queda en pedido');
}
{
  // No se puede tocar dos veces: mientras manda, el segundo toque no sale.
  let soltar; const espera = new Promise((r) => { soltar = r; });
  const { m, rpc } = nuevo({ mypump_fin_plan_get: ok(visible()), mypump_fin_plan_pedir: async () => { await espera; return ok({ ok: true, ya: false, estado: 'pedido' }); } });
  m.aplicarConfig({ fin_plan: true });
  await m.refrescar();
  const a = m.pedir();
  eq(m.enviando, true, 'enviando');
  eq(await m.pedir(), 'nada', 'segundo toque');
  // Un `get` viejo que llega mientras tanto no pisa el pedido.
  const viejo = m.refrescar();
  soltar();
  eq([await a, await viejo, m.estado.estado, rpc.de('mypump_fin_plan_pedir').length, rpc.de('mypump_fin_plan_get').length], ['ok', undefined, 'pedido', 1, 1], 'un solo pedido');
}
{
  // Un `get` que salió antes del pedido y vuelve después con «publicado» no lo deshace.
  let soltarGet; const esperaGet = new Promise((r) => { soltarGet = r; });
  const { m } = nuevo({ mypump_fin_plan_get: (p, k) => (k === 1 ? ok(visible()) : esperaGet.then(() => ok(visible()))), mypump_fin_plan_pedir: ok({ ok: true, ya: false, estado: 'pedido' }) });
  m.aplicarConfig({ fin_plan: true });
  await m.refrescar();
  const lento = m.refrescar();
  eq(await m.pedir(), 'ok', 'pedido');
  soltarGet(); await lento;
  eq(m.estado.estado, 'pedido', 'la respuesta vieja se descarta');
}
for (const error of ['apagado', 'no_disponible']) {
  const alm = almacen();
  const { m } = nuevo({ mypump_fin_plan_get: ok(visible()), mypump_fin_plan_pedir: ok({ ok: false, error }) }, alm);
  m.aplicarConfig({ fin_plan: true });
  await m.refrescar();
  eq([await m.pedir(), m.estado, m.error, alm.m.has(`mypump_recorrido_${CTA}`), alm.m.has(`mypump_recorrido_pedido_${CTA}`)], ['cerrar', null, false, false, false], `${error}: se cierra y deja de verse`);
}
{
  // El servidor contesta «agendado»; y uno que llega pedido desde otro teléfono limpia lo que quedaba a medio escribir.
  const { m } = nuevo({ mypump_fin_plan_get: ok(visible()), mypump_fin_plan_pedir: ok({ ok: true, ya: true, estado: 'agendado' }) });
  m.aplicarConfig({ fin_plan: true });
  await m.refrescar();
  eq([await m.pedir(), m.estado.estado], ['ok', 'agendado'], 'ya agendado');
  const alm = almacen();
  const b = nuevo({ mypump_fin_plan_get: ok(visible()) }, alm);
  b.m.aplicarConfig({ fin_plan: true });
  await b.m.refrescar();
  b.m.escribir('mejor', 'a medias');
  b.rpc.respuestas.mypump_fin_plan_get = ok(visible('pedido', { respuestas: { mejor: 'desde el teléfono' } }));
  await b.m.refrescar();
  eq([b.m.estado.estado, b.m.textos.mejor, alm.m.has(`mypump_recorrido_borrador_${CTA}`)], ['pedido', 'desde el teléfono', false], 'pedido en otro lado');
}
{
  // Un almacén que falla (modo privado) no rompe: el id vive en memoria y el reintento usa el mismo.
  const roto = { leer: () => { throw new Error('x'); }, guardar: () => { throw new Error('x'); }, borrar: () => { throw new Error('x'); } };
  const rpc = rpcDoble({ mypump_fin_plan_get: ok(visible()), mypump_fin_plan_pedir: RED });
  let k = 0;
  const m = R.crearModelo({ token: TOKEN, rpc, almacen: roto, nuevoId: () => `id-${++k}` });
  eq(m.aplicarConfig({ fin_plan: true }), true, 'prendida sin almacén');
  await m.refrescar();
  await m.pedir(); await m.pedir();
  eq(rpc.de('mypump_fin_plan_pedir').map((l) => l.params.p_id), ['id-1', 'id-1'], 'mismo id en memoria');
  // Y un rpc que tira una excepción cuenta como red.
  const m3 = R.crearModelo({ token: TOKEN, rpc: async () => { throw new Error('red'); }, almacen: almacen() });
  m3.aplicarConfig({ fin_plan: true });
  await m3.refrescar();
  eq(m3.estado, null, 'excepción = sin red');
}

// ---- La cola B entera está en la página y en el service worker (con la versión de caché subida).
{
  const { readFileSync } = await import('node:fs');
  const sw = readFileSync(new URL('../public/sw.js', import.meta.url), 'utf8');
  const html = readFileSync(new URL('../public/cliente.html', import.meta.url), 'utf8');
  si(Number(/const VERSION\s*=\s*'v(\d+)/.exec(sw)[1]) >= 57, 'versión del sw subida');
  for (const a of ['/js/recorrido.js', '/js/recorrido-ui.js', '/js/compras.js', '/js/compras-ui.js', '/js/casa.js', '/js/casa-ui.js', '/css/cola-b.css']) {
    si(sw.includes(`'${a}'`), `shell ${a}`);
    si(html.includes(`"${a}"`), `cliente.html carga ${a}`);
  }
  // casa.js y casa-ui.js antes que gimnasio-ui.js; las reglas antes que su pantalla.
  const pos = (a) => html.indexOf(`src="${a}"`);
  si(pos('/js/casa.js') < pos('/js/casa-ui.js') && pos('/js/casa-ui.js') < pos('/js/gimnasio-ui.js'), 'orden de casa');
  si(pos('/js/recorrido.js') < pos('/js/recorrido-ui.js') && pos('/js/compras.js') < pos('/js/compras-ui.js'), 'orden de recorrido y compras');
}

{
  // Las claves locales llevan un hash del token, no el token; las viejas se pasan una vez y se borran.
  const alm = almacen();
  alm.guardar(`mypump_recorrido_pedido_${TOKEN}`, 'id-viejo');
  alm.guardar(`mypump_recorrido_sola_${TOKEN}`, '1');
  R.crearModelo({ token: TOKEN, rpc: rpcDoble({}), almacen: alm });
  eq([alm.leer(`mypump_recorrido_pedido_${CTA}`), alm.leer(`mypump_recorrido_sola_${CTA}`)], ['id-viejo', '1'], 'migra las claves viejas');
  si(![...alm.m.keys()].some(k => k.includes(TOKEN)), 'ninguna clave lleva el token');
  si(R.cuentaDe(TOKEN) !== R.cuentaDe('otra-cuenta') && !CTA.includes(TOKEN), 'hash por cuenta');
}

console.log(`recorrido: ${n} ok`);
