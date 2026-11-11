// «Entreno en casa» (palanca `casa`, dentro de Mi gimnasio): reglas y modelo de public/js/casa.js.
// Contrato: cola-b/CONTRATO_APP.md, sección 3. Datos de prueba inventados.
import { createRequire } from 'node:module';
import assert from 'node:assert/strict';
import { almacen, rpcDoble, ok, RED, NO_EXISTE, CAIDO } from './lib/doble-rpc.mjs';
const require = createRequire(import.meta.url);
const C = require('../public/js/casa.js');
let n = 0;
const eq = (a, b, m) => { assert.deepEqual(a, b, m); n++; };

const TIPOS = [{ tipo: 'mancuernas', nombre: 'Mancuernas', kg: true }, { tipo: 'banco_plano', nombre: 'Banco plano', kg: false },
  { tipo: 'discos', nombre: 'Discos', kg: true }, { tipo: 'bandas_elasticas', nombre: 'Bandas elásticas', kg: false }];
const carga = (estado, lugar, mas = {}) => ({ id: 'c-1', estado, lugar, equipos: [], sin_equipo: false, nota: null, ...mas });
const resp = (abierta = null, vigente = null, mas = {}) => ({ habilitado: true, tipos: TIPOS, abierta, vigente, ...mas });
const TOKEN = 'token-de-prueba';
const AMBAS = { gimnasio_fotos: true, casa: true };

// ---- Decodificar.
eq(C.decodificar(null), null, 'NULL (token caído)');
eq(C.decodificar({ habilitado: false }), null, 'habilitado:false');
{
  const d = C.decodificar(resp(carga('borrador', 'casa'), carga('listo', 'gimnasio', { id: 'c-0' })));
  eq(d.tipos, TIPOS, 'la lista es la del servidor, en su orden');
  eq([d.abierta.lugar, d.vigente.lugar, d.abierta.id], ['casa', 'gimnasio', 'c-1'], 'lugares');
  eq(C.decodificar(resp(carga('borrador', 'otro'))).abierta.lugar, 'gimnasio', 'lugar desconocido = gimnasio');
  eq(C.decodificar({ habilitado: true }).tipos, [], 'sin tipos');
  eq(C.decodificar(resp(null, null, { tipos: [{ tipo: 'ok_1', nombre: ' Uno ', kg: 'true' }, { tipo: 'Con Espacio', nombre: 'x' }, { tipo: 'sin_nombre' }, { tipo: 'ok_1', nombre: 'repetido' }, 7, null,
    { tipo: '"><img src=x>', nombre: 'malo' }] })).tipos, [{ tipo: 'ok_1', nombre: 'Uno', kg: false }], 'tipos mal formados afuera');
  const v = C.decodificar(resp(null, carga('listo', 'casa', { equipos: [{ tipo: 'discos', kg: 60 }, { tipo: 'mancuernas', kg: 12.5 }, { tipo: 'banco_plano' }, { tipo: 'discos', kg: 5 }, { tipo: 'x y' }, 3],
    sin_equipo: false, nota: 'Tengo poco lugar' }))).vigente;
  eq(v.equipos, [{ tipo: 'discos', kg: 60 }, { tipo: 'mancuernas', kg: 12.5 }, { tipo: 'banco_plano', kg: null }], 'equipos');
  eq(C.equiposVigentes(v, TIPOS), [{ tipo: 'mancuernas', nombre: 'Mancuernas', detalle: 'hasta 12,5 kg' }, { tipo: 'banco_plano', nombre: 'Banco plano', detalle: null },
    { tipo: 'discos', nombre: 'Discos', detalle: 'hasta 60 kg' }], 'lo que tiene, con «hasta N kg»');
  eq(C.equiposVigentes({ equipos: [{ tipo: 'tipo_nuevo', kg: null }] }, TIPOS)[0].nombre, 'tipo nuevo', 'un tipo que la lista ya no trae');
}

// ---- Kilos: opcional, de 1 a 400.
eq(['20', ' 12,5 ', '400', '1', 7.26, '0.96'].map(C.kilos), [20, 12.5, 400, 1, 7.3, 1], 'kilos válidos');
eq(['0', '0,5', '401', '-3', 'veinte', '', null, undefined, '1e3', '12kg', NaN, Infinity].map(C.kilos), Array(12).fill(null), 'kilos inválidos');

// ---- El interruptor en cada estado.
const I = (a, v) => C.interruptor(C.decodificar(resp(a, v)));
const P = (a, v) => C.pantalla(C.decodificar(resp(a, v)));
const A = (a, v, aCasa) => C.accion(C.decodificar(resp(a, v)), aCasa);
eq(C.interruptor(null), null, 'sin casa_get no hay interruptor');
eq([I(null, null), P(null, null)], [{ prendido: false, bloqueado: false }, null], 'sin nada: apagado');
eq([I(carga('borrador', 'casa'), null), P(carga('borrador', 'casa'), null)], [{ prendido: true, bloqueado: false }, 'lista'], 'borrador de casa: prendido y la lista');
eq([I(carga('borrador', 'gimnasio'), null), P(carga('borrador', 'gimnasio'), null)], [{ prendido: false, bloqueado: false }, null], 'borrador de gimnasio: apagado y las zonas');
eq([I(null, carga('listo', 'casa')), P(null, carga('listo', 'casa'))], [{ prendido: true, bloqueado: false }, 'vigente'], 'casa vigente: prendido');
eq([I(null, carga('listo', 'gimnasio')), P(null, carga('listo', 'gimnasio'))], [{ prendido: false, bloqueado: false }, null], 'gimnasio vigente: apagado');
eq([I(carga('borrador', 'gimnasio'), carga('listo', 'casa', { id: 'c-0' })), P(carga('borrador', 'gimnasio'), carga('listo', 'casa', { id: 'c-0' }))], [{ prendido: false, bloqueado: false }, null], 'manda la carga abierta');
eq([I(carga('borrador', 'casa'), carga('listo', 'gimnasio', { id: 'c-0' })), P(carga('borrador', 'casa'), carga('listo', 'gimnasio', { id: 'c-0' }))], [{ prendido: true, bloqueado: false }, 'lista'], 'manda la carga abierta (casa)');
for (const e of ['enviado', 'procesando', 'a_confirmar', 'respondido', 'a_revisar', 'en_editor', 'estado_nuevo']) {
  eq([I(carga(e, 'casa'), null), P(carga(e, 'casa'), null), A(carga(e, 'casa'), null, false)], [{ prendido: true, bloqueado: true }, null, 'nada'], `${e} de casa: bloqueado, «Recibido» de siempre`);
  eq([I(carga(e, 'gimnasio'), null), A(carga(e, 'gimnasio'), null, true)], [{ prendido: false, bloqueado: true }, 'nada'], `${e} de gimnasio: bloqueado`);
}
// Qué hace al moverlo.
eq(A(null, null, true), 'elegir', 'prender sin nada');
eq(A(carga('borrador', 'gimnasio'), null, true), 'elegir', 'prender con borrador de gimnasio');
eq(A(null, carga('listo', 'gimnasio'), true), 'elegir', 'prender con gimnasio vigente');
eq(A(carga('borrador', 'casa'), null, false), 'elegir', 'apagar con borrador de casa');
eq(A(null, carga('listo', 'casa'), false), 'gimnasio', 'apagar sin borrador y con casa vigente: la carga de gimnasio de siempre');
eq([A(carga('borrador', 'casa'), null, true), A(null, null, false), A(null, carga('listo', 'casa'), true)], ['nada', 'nada', 'nada'], 'ya estaba así');
eq(C.accion(null, true), 'nada', 'sin interruptor');

// ---- Lo marcado.
{
  let b = C.borradorVacio('c-1');
  b = C.alternarTipo(b, 'mancuernas'); b = C.alternarTipo(b, 'banco_plano');
  eq([b.marcados, C.puedeEnviar(b, TIPOS)], [['mancuernas', 'banco_plano'], true], 'marcar');
  b = Object.assign({}, b, { kg: { mancuernas: '22,5', banco_plano: '80', discos: '10' } });
  eq(C.equiposParaEnviar(b, TIPOS), [{ tipo: 'mancuernas', kg: 22.5 }, { tipo: 'banco_plano' }], 'kg solo donde la lista lo pide y solo de lo marcado');
  eq(C.equiposParaEnviar(Object.assign({}, b, { kg: { mancuernas: '900' } }), TIPOS)[0], { tipo: 'mancuernas' }, 'kg fuera de rango no viaja');
  eq(C.equiposParaEnviar(Object.assign({}, b, { marcados: ['discos', 'inventado', 'mancuernas'] }), TIPOS).map((q) => q.tipo), ['mancuernas', 'discos'], 'en el orden del servidor y solo de su lista');
  const nada = C.alternarSinEquipo(b);
  eq([nada.sinEquipo, nada.marcados, nada.kg, C.equiposParaEnviar(nada, TIPOS), C.puedeEnviar(nada, TIPOS)], [true, [], {}, [], true], '«No tengo nada de esto» desmarca todo');
  const otra = C.alternarTipo(nada, 'discos');
  eq([otra.sinEquipo, otra.marcados], [false, ['discos']], 'marcar un equipo lo desmarca');
  eq(C.alternarSinEquipo(nada).sinEquipo, false, 'se puede desmarcar');
  eq(C.puedeEnviar(C.borradorVacio('c-1'), TIPOS), false, 'sin nada marcado no se envía');
  eq(C.puedeEnviar(Object.assign(C.borradorVacio('c-1'), { marcados: ['inventado'] }), TIPOS), false, 'un tipo fuera de la lista no cuenta');
  eq(C.borradorValido({ id: 'otra', marcados: ['discos'] }, 'c-1'), C.borradorVacio('c-1'), 'el borrador de otra carga no vale');
  eq(C.borradorValido({ id: 'c-1', marcados: ['discos', 'discos', 7, 'x y'], kg: { discos: '20', 'x y': '1', mancuernas: 5 }, sinEquipo: 'si', nota: 'n'.repeat(400) }, 'c-1'),
    { id: 'c-1', marcados: ['discos'], kg: { discos: '20' }, sinEquipo: false, nota: 'n'.repeat(300) }, 'borrador saneado');
}

// ---- Textos del contrato.
eq([C.T.interruptor, C.T.interruptorAyuda, C.T.interruptorBloqueado, C.T.errorCambiar, C.T.listaTitulo, C.T.listaTexto, C.T.kilos, C.T.sinEquipo, C.T.nota, C.T.enviar,
  C.T.errorEnviar, C.T.sinDatos, C.T.vigenteTitulo, C.T.vigenteSinEquipo, C.T.cambiar], [
  'Entreno en casa', 'Prendelo si entrenás en tu casa y no en un gimnasio.', 'Ya lo recibimos. Lo vas a poder cambiar cuando esté listo.', 'No se pudo cambiar. Probá de nuevo.',
  '¿Qué tenés en casa?', 'Marcá todo lo que tengas. Con eso Mati arma tu rutina.', 'Hasta cuántos kilos (opcional)', 'No tengo nada de esto', '¿Algo más que quieras contarle a Mati?',
  'Enviar a Mati', 'No se pudo enviar. Probá de nuevo.', 'Marcá lo que tenés, o “No tengo nada de esto”.', 'Entrenás en casa', 'Sin equipo: entrenás con tu cuerpo.', 'Cambió lo que tengo en casa'], 'textos');

// ---- El modelo. Un servidor de mentira con la misma lógica que mypump_casa_*.
function servidor(inicial = {}) {
  const s = { abierta: null, vigente: null, fallar: {}, ...inicial };
  const rpc = rpcDoble({
    mypump_casa_get: () => s.fallar.get || ok(resp(s.abierta, s.vigente)),
    mypump_casa_elegir: (p) => {
      if (s.fallar.elegir) { const f = s.fallar.elegir; if (s.fallar.unaVez) s.fallar = {}; return f; }
      const lugar = p.p_casa ? 'casa' : 'gimnasio';
      if (s.abierta) {
        if (s.abierta.lugar === lugar) return ok({ ok: true, ya: true, id: s.abierta.id, estado: s.abierta.estado, lugar });
        if (s.abierta.estado !== 'borrador') return ok({ ok: false, error: 'en_curso' });
        s.abierta = { ...s.abierta, lugar };
        return ok({ ok: true, ya: false, id: s.abierta.id, estado: 'borrador', lugar });
      }
      if (!p.p_casa) return ok({ ok: true, ya: true, id: null, lugar: 'gimnasio' });
      s.abierta = carga('borrador', 'casa', { id: 'c-2' });
      return ok({ ok: true, ya: false, id: 'c-2', estado: 'borrador', lugar: 'casa' });
    },
    mypump_casa_enviar: (p) => {
      if (s.fallar.enviar) return s.fallar.enviar;
      if (!s.abierta || s.abierta.id !== p.p_id) return ok({ ok: false, error: 'no_encontrado' });
      if (s.abierta.estado !== 'borrador') return ok({ ok: true, ya: true, estado: s.abierta.estado });
      if (!p.p_equipos.length && !p.p_sin_equipo) return ok({ ok: false, error: 'sin_datos' });
      s.abierta = { ...s.abierta, estado: 'a_revisar', equipos: p.p_equipos, sin_equipo: p.p_sin_equipo, nota: p.p_nota };
      return ok({ ok: true, ya: false, estado: 'a_revisar' });
    },
  });
  const gim = { refrescos: 0, nuevos: 0, resultadoNuevo: 'ok',
    refrescar: async () => { gim.refrescos++; },
    nuevoCompleta: async () => { gim.nuevos++; if (gim.resultadoNuevo === 'ok') { s.abierta = carga('borrador', 'gimnasio', { id: 'c-3' }); await m.refrescar(); } return gim.resultadoNuevo; } };
  const alm = inicial.almacen || almacen();
  const m = C.crearModelo({ token: TOKEN, rpc, almacen: alm, gimnasio: gim });
  return { s, rpc, gim, alm, m };
}

// Apagada (hacen falta las DOS palancas): no llama a nada.
for (const cfg of [{}, { casa: true }, { gimnasio_fotos: true }, { casa: 'true', gimnasio_fotos: true }, { casa: false, gimnasio_fotos: true }, null]) {
  const { m, rpc, gim } = servidor({ abierta: carga('borrador', 'casa') });
  eq(m.aplicarConfig(cfg), false, `apagada con ${JSON.stringify(cfg)}`);
  await m.refrescar(); await m.mover(true); m.alternarTipo('discos'); await m.enviar();
  eq([rpc.llamadas.length, gim.refrescos, m.estado, m.interruptor, m.pantalla, m.borrador], [0, 0, null, null, null, null], 'apagada no llama ni muestra');
}
{
  // Sin la función, con el token caído o no habilitado: no hay interruptor. Sin red queda lo último que se vio.
  for (const r of [NO_EXISTE, ok(null), ok({ habilitado: false })]) {
    const { m, s } = servidor(); s.fallar.get = r;
    m.aplicarConfig(AMBAS); await m.refrescar();
    eq([m.estado, m.interruptor], [null, null], `sin interruptor con ${JSON.stringify(r).slice(0, 50)}`);
  }
  const a = servidor({ vigente: carga('listo', 'casa') });
  a.m.aplicarConfig(AMBAS); await a.m.refrescar();
  a.s.fallar.get = RED; await a.m.refrescar();
  eq(a.m.pantalla, 'vigente', 'sin red queda');
  const b = servidor({ almacen: a.alm }); b.s.fallar.get = CAIDO;
  eq(b.m.aplicarConfig(null), true, 'sin config: lo último que se supo');
  await b.m.refrescar();
  eq(b.m.pantalla, 'vigente', 'otra carga sin red: la copia');
}
{
  // Prender: elegir(true), se refrescan los dos y aparece la lista.
  const { m, s, rpc, gim } = servidor();
  m.aplicarConfig(AMBAS); await m.refrescar();
  eq([m.interruptor, m.pantalla], [{ prendido: false, bloqueado: false, ocupado: false }, null], 'apagado');
  const estados = []; m.alCambiar(() => estados.push(m.interruptor && m.interruptor.prendido));
  eq(await m.mover(true), 'ok', 'prender');
  eq(rpc.de('mypump_casa_elegir')[0].params, { p_token: TOKEN, p_casa: true }, 'lo que viaja');
  eq([estados[0], m.interruptor, m.pantalla, gim.refrescos, s.abierta.lugar], [true, { prendido: true, bloqueado: false, ocupado: false }, 'lista', 1, 'casa'], 'prendido, la lista y el gimnasio refrescado');
  eq(await m.mover(true), 'nada', 'ya estaba prendido');
  // Marcar, kilos y nota: quedan en disco hasta enviar.
  m.alternarTipo('mancuernas'); m.alternarTipo('bandas_elasticas'); m.alternarTipo('inventado');
  m.fijarKg('mancuernas', '20'); m.fijarNota('  Tengo poco lugar  ');
  eq([m.borrador.marcados, m.puedeEnviar], [['mancuernas', 'bandas_elasticas'], true], 'marcado');
  eq(await m.enviar(), 'ok', 'enviar');
  eq(rpc.de('mypump_casa_enviar')[0].params, { p_token: TOKEN, p_id: 'c-2', p_equipos: [{ tipo: 'mancuernas', kg: 20 }, { tipo: 'bandas_elasticas' }], p_sin_equipo: false, p_nota: 'Tengo poco lugar' }, 'lo que viaja');
  eq([m.interruptor, m.pantalla, m.borrador, m.error, gim.refrescos], [{ prendido: true, bloqueado: true, ocupado: false }, null, null, null, 2], 'recibido: bloqueado, pantalla del gimnasio, los dos refrescados');
  eq(await m.mover(false), 'nada', 'bloqueado no se mueve');
  eq(await m.enviar(), 'nada', 'ya enviado');
  // Mati la aprueba: es la vigente de casa.
  s.vigente = { ...s.abierta, estado: 'listo' }; s.abierta = null;
  await m.refrescar();
  eq([m.interruptor.prendido, m.interruptor.bloqueado, m.pantalla], [true, false, 'vigente'], 'vigente de casa');
  // «Cambió lo que tengo en casa» → elegir(true): se abre otra carga de casa, vacía. El interruptor, que ya está prendido, no hace nada.
  eq(await m.mover(true), 'nada', 'el interruptor ya está prendido');
  const antes = rpc.de('mypump_casa_elegir').length;
  eq(await m.cambiar(), 'ok', 'cambió lo que tengo');
  eq([rpc.de('mypump_casa_elegir').length - antes, rpc.de('mypump_casa_elegir').pop().params.p_casa, m.pantalla, m.borrador, s.vigente.lugar],
    [1, true, 'lista', C.borradorVacio('c-2'), 'casa'], 'otra carga de casa, vacía, y la vigente sigue');
  eq(await m.cambiar(), 'nada', 'con la lista abierta, cambiar no hace nada');
  s.fallar.elegir = RED; s.abierta = null; await m.refrescar();
  eq([await m.cambiar(), m.error, m.pantalla], ['error', 'cambiar', 'vigente'], 'cambiar sin red: avisa y queda igual');
}
{
  // Lo marcado vuelve en otra carga de la página, y el de otra carga se descarta.
  const a = servidor({ abierta: carga('borrador', 'casa') });
  a.m.aplicarConfig(AMBAS); await a.m.refrescar();
  a.m.alternarTipo('discos'); a.m.fijarKg('discos', '40'); a.m.fijarNota('nota');
  const b = servidor({ abierta: carga('borrador', 'casa'), almacen: a.alm });
  b.m.aplicarConfig(AMBAS); await b.m.refrescar();
  eq([b.m.borrador.marcados, b.m.borrador.kg, b.m.borrador.nota], [['discos'], { discos: '40' }, 'nota'], 'lo marcado se guarda en disco');
  const c = servidor({ abierta: carga('borrador', 'casa', { id: 'otra' }), almacen: a.alm });
  c.m.aplicarConfig(AMBAS); await c.m.refrescar();
  eq(c.m.borrador, C.borradorVacio('otra'), 'otra carga: borrador vacío');
}
{
  // «No tengo nada de esto».
  const { m, rpc } = servidor({ abierta: carga('borrador', 'casa') });
  m.aplicarConfig(AMBAS); await m.refrescar();
  eq([m.puedeEnviar, await m.enviar(), m.error, rpc.de('mypump_casa_enviar').length], [false, 'sinDatos', 'sinDatos', 0], 'sin nada marcado no sale');
  m.alternarTipo('discos'); m.alternarSinEquipo();
  eq(m.error, null, 'marcar limpia el aviso');
  eq(await m.enviar(), 'ok', 'enviar sin equipo');
  eq(rpc.de('mypump_casa_enviar')[0].params, { p_token: TOKEN, p_id: 'c-1', p_equipos: [], p_sin_equipo: true, p_nota: null }, 'sin equipo');
}
{
  // Errores de enviar.
  const { m, s, gim } = servidor({ abierta: carga('borrador', 'casa') });
  m.aplicarConfig(AMBAS); await m.refrescar();
  m.alternarTipo('discos');
  for (const f of [RED, CAIDO, ok(null), ok({ ok: false, error: 'contradiccion' })]) {
    s.fallar.enviar = f;
    eq([await m.enviar(), m.error, m.borrador.marcados, m.enviando], ['error', 'enviar', ['discos'], false], `no se pudo enviar: ${JSON.stringify(f).slice(0, 40)}`);
  }
  s.fallar.enviar = ok({ ok: false, error: 'sin_datos' });
  eq([await m.enviar(), m.error], ['sinDatos', 'sinDatos'], 'sin_datos del servidor');
  // Reintentar da `ya`: es seguro.
  s.fallar.enviar = null; s.abierta = { ...s.abierta, estado: 'a_revisar' };
  const antes = gim.refrescos;
  eq([await m.enviar(), m.pantalla, m.interruptor.bloqueado, gim.refrescos > antes], ['ok', null, true, true], 'reintento con ya:true');
  // no_encontrado: se refresca y se muestra lo que haya.
  const x = servidor({ abierta: carga('borrador', 'casa') });
  x.m.aplicarConfig(AMBAS); await x.m.refrescar(); x.m.alternarTipo('discos');
  x.s.abierta = null;
  eq([await x.m.enviar(), x.m.pantalla, x.gim.refrescos], ['error', null, 1], 'no_encontrado: refresca los dos');
  // no_habilitado: se esconde todo.
  const y = servidor({ abierta: carga('borrador', 'casa') });
  y.m.aplicarConfig(AMBAS); await y.m.refrescar(); y.m.alternarTipo('discos');
  y.s.fallar.enviar = ok({ ok: false, error: 'no_habilitado' });
  await y.m.enviar();
  eq([y.m.estado, y.m.interruptor, y.m.error], [null, null, null], 'no_habilitado: sin interruptor');
}
{
  // Apagar con un borrador de casa: elegir(false) y vuelven las zonas.
  const { m, s, rpc } = servidor({ abierta: carga('borrador', 'casa') });
  m.aplicarConfig(AMBAS); await m.refrescar();
  eq(await m.mover(false), 'ok', 'apagar');
  eq([rpc.de('mypump_casa_elegir')[0].params.p_casa, m.interruptor.prendido, m.pantalla, s.abierta.lugar], [false, false, null, 'gimnasio'], 'borrador de gimnasio');
}
{
  // Apagar sin borrador y con casa vigente: la carga de gimnasio de siempre, sin llamar a elegir.
  const { m, rpc, gim } = servidor({ vigente: carga('listo', 'casa') });
  m.aplicarConfig(AMBAS); await m.refrescar();
  eq(await m.mover(false), 'ok', 'apagar con casa vigente');
  eq([gim.nuevos, rpc.de('mypump_casa_elegir').length, m.interruptor.prendido, m.pantalla], [1, 0, false, null], 'mypump_gimnasio_nuevo completa');
  const f = servidor({ vigente: carga('listo', 'casa') });
  f.m.aplicarConfig(AMBAS); await f.m.refrescar();
  f.gim.resultadoNuevo = 'sinSenal';
  eq([await f.m.mover(false), f.m.error, f.m.interruptor.prendido, f.m.pantalla], ['error', 'cambiar', true, 'vigente'], 'si falla, vuelve a como estaba');
}
{
  // Si `elegir` falla por red: el interruptor vuelve a como estaba y avisa. Mientras viaja se ve movido.
  const { m, s } = servidor();
  m.aplicarConfig(AMBAS); await m.refrescar();
  for (const f of [RED, CAIDO, ok(null), ok({ ok: false, error: 'otro' })]) {
    s.fallar.elegir = f;
    const p = m.mover(true);
    eq([m.interruptor.prendido, m.interruptor.ocupado, await m.mover(false)], [true, true, 'nada'], 'mientras viaja: movido y sin doble toque');
    eq([await p, m.interruptor, m.error], ['error', { prendido: false, bloqueado: false, ocupado: false }, 'cambiar'], `vuelve: ${JSON.stringify(f).slice(0, 40)}`);
  }
  // `reintentar`: una vez más y sale.
  s.fallar = { elegir: ok({ ok: false, error: 'reintentar' }), unaVez: true };
  eq([await m.mover(true), m.pantalla, m.error], ['ok', 'lista', null], 'reintentar una vez');
  // `reintentar` dos veces: error.
  const r = servidor(); r.m.aplicarConfig(AMBAS); await r.m.refrescar();
  r.s.fallar.elegir = ok({ ok: false, error: 'reintentar' });
  eq([await r.m.mover(true), r.rpc.de('mypump_casa_elegir').length], ['error', 2], 'reintentar solo una vez');
  // `en_curso`: se refresca y queda bloqueado. `no_habilitado`: se esconde.
  const e = servidor(); e.m.aplicarConfig(AMBAS); await e.m.refrescar();
  e.s.abierta = carga('enviado', 'gimnasio');
  eq([await e.m.mover(true), e.m.interruptor, e.m.error], ['ok', { prendido: false, bloqueado: true, ocupado: false }, null], 'en_curso');
  const h = servidor(); h.m.aplicarConfig(AMBAS); await h.m.refrescar();
  h.s.fallar.elegir = ok({ ok: false, error: 'no_habilitado' });
  eq([await h.m.mover(true), h.m.interruptor], ['ok', null], 'no_habilitado: se esconde');
}

console.log(`casa: ${n} ok`);
