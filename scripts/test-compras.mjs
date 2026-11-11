// «Dónde comprarlo» (compras por país, palanca `compras_pais`): reglas y modelo de public/js/compras.js.
// Contrato: cola-b/CONTRATO_APP.md, sección 2. Productos y tiendas de prueba inventados.
import { createRequire } from 'node:module';
import assert from 'node:assert/strict';
import { almacen, rpcDoble, ok, RED, NO_EXISTE, CAIDO } from './lib/doble-rpc.mjs';
const require = createRequire(import.meta.url);
const C = require('../public/js/compras.js');
let n = 0;
const eq = (a, b, m) => { assert.deepEqual(a, b, m); n++; };

const OP = { producto: 'Creatina Marca Inventada 300 g', tienda: 'Tienda de Prueba', url: 'https://tienda-de-prueba.example/creatina', nota: 'La de pote blanco' };
const resp = (items, mas = {}) => ({ habilitado: true, pais: 'AR', items, ...mas });
const TOKEN = 'token-de-prueba';
const K = `mypump_compras_${TOKEN}`;

// ---- La url: solo https, entera y sin trampas.
eq(C.urlSegura('https://tienda-de-prueba.example/p?a=1'), 'https://tienda-de-prueba.example/p?a=1', 'https');
eq(C.urlSegura('  https://tienda-de-prueba.example  '), 'https://tienda-de-prueba.example/', 'recorta');
for (const mala of ['http://tienda-de-prueba.example', 'javascript:alert(1)', 'JAVASCRIPT:alert(1)', 'data:text/html,<b>x</b>', '//tienda-de-prueba.example', 'tienda-de-prueba.example',
  'https://', 'https:// tienda.example', 'https://a b.example', 'ftp://x.example', 'intent://x#Intent;end', ' javascript:https://x.example', 'https://usuario:clave@x.example',
  'https:/x.example\njavascript:alert(1)', '', null, undefined, 7, {}, 'https://' + 'a'.repeat(2100) + '.example']) {
  eq(C.urlSegura(mala), null, `url ignorada: ${String(mala).slice(0, 40)}`);
}

// ---- Decodificar.
eq(C.decodificar(null), null, 'NULL (token caído)');
eq(C.decodificar({ habilitado: false }), null, 'habilitado:false');
eq(C.decodificar(resp([])), null, 'items vacío = nada (ni un cartel)');
eq(C.decodificar({ habilitado: true }), null, 'sin items');
eq(C.decodificar(resp([{ nombre: 'Creatina', opciones: [] }, { nombre: '', opciones: [OP] }, { opciones: [OP] }, 7, null])), null, 'ítems sin opciones o sin nombre');
{
  const d = C.decodificar(resp([{ nombre: ' Creatina monohidrato ', opciones: [OP, { producto: 'Otra de Prueba', tienda: 'Local Inventado', url: 'http://sin-candado.example' },
    { producto: '', tienda: 'x' }, { producto: 'x' }, 'no', { producto: 'P3', tienda: 'T3' }, { producto: 'P4', tienda: 'T4' }, { producto: 'P5', tienda: 'T5' }] }]));
  eq(d.pais, 'AR', 'país');
  eq(d.items[0].nombre, 'Creatina monohidrato', 'nombre recortado');
  eq(d.items[0].opciones.length, 4, 'hasta 4 opciones, sin las inválidas');
  eq(d.items[0].opciones[0], { producto: OP.producto, tienda: OP.tienda, url: OP.url, nota: OP.nota }, 'opción entera');
  eq(d.items[0].opciones[1], { producto: 'Otra de Prueba', tienda: 'Local Inventado', url: null, nota: null }, 'url no https: la opción queda, sin botón');
  eq(C.decodificar({ habilitado: true, items: [{ nombre: 'Zinc', opciones: [OP] }] }).pais, null, 'sin país no se inventa uno');
  eq(C.decodificar(resp([{ nombre: 'Zinc', opciones: [OP], extra: 1 }], { campo_nuevo: true })).items.length, 1, 'un campo nuevo no rompe');
}

// ---- El cruce con la pestaña: por nombre EXACTO después de recortar espacios.
{
  const c = C.decodificar(resp([{ nombre: 'Creatina monohidrato', opciones: [OP] }, { nombre: 'Omega 3', opciones: [OP, OP] }]));
  eq(C.opcionesDe(c, 'Creatina monohidrato').length, 1, 'exacto');
  eq(C.opcionesDe(c, '  Creatina monohidrato  ').length, 1, 'recortando espacios');
  for (const otro of ['creatina monohidrato', 'Creatina', 'Creatina monohidrato 5 g', 'Creatina  monohidrato', 'Creatína monohidrato', 'Omega-3', '', null, undefined, 3]) {
    eq(C.opcionesDe(c, otro), [], `no cruza con ${JSON.stringify(otro)}`);
  }
  eq(C.opcionesDe(null, 'Omega 3'), [], 'sin compras');
  const items = [{ nombre: 'Omega 3' }, { nombre: 'Magnesio' }, { nombre: ' Creatina monohidrato ', estado: 'sube' }, { nombre: 'Omega 3', estado: 'sale' }, null];
  eq(C.cruzar(c, items).map((o) => (o ? o.length : null)), [2, null, 1, null, null], 'cruzar: por ítem, en su orden; lo que sale no lleva botón');
  eq(C.cruzar(null, items), [null, null, null, null, null], 'apagada: nada');
  eq(C.cruzar(c, null), [], 'sin ítems');
}

// ---- Textos del contrato.
eq([C.T.boton, C.T.ayuda, C.T.subtitulo, C.T.abrirTienda, C.T.pie, C.T.cerrar],
  ['Dónde comprarlo', 'Tocá “Dónde comprarlo” para ver dónde conseguir cada suplemento.', 'Dónde comprarlo', 'Abrir la tienda', 'Son lugares que Mati revisó.', 'Cerrar'], 'textos');

// ---- Apagada: no llama a ningún RPC.
for (const cfg of [{}, { compras_pais: false }, { compras_pais: 'true' }, null]) {
  const rpc = rpcDoble({ mypump_compras_get: ok(resp([{ nombre: 'Omega 3', opciones: [OP] }])) });
  const m = C.crearModelo({ token: TOKEN, rpc, almacen: almacen() });
  eq(m.aplicarConfig(cfg), false, `apagada con ${JSON.stringify(cfg)}`);
  await m.refrescar(true);
  eq([rpc.llamadas.length, m.compras], [0, null], 'apagada no llama ni muestra');
}

// ---- Prendida.
{
  const alm = almacen();
  const rpc = rpcDoble({ mypump_compras_get: ok(resp([{ nombre: 'Omega 3', opciones: [OP] }])) });
  const m = C.crearModelo({ token: TOKEN, rpc, almacen: alm });
  eq(m.aplicarConfig({ compras_pais: true }), true, 'prendida');
  // Sin suplementación no se pregunta.
  await m.refrescar(false);
  eq([rpc.llamadas.length, m.compras], [0, null], 'sin suplementación no llama');
  await m.refrescar(true);
  eq([rpc.nombres(), rpc.llamadas[0].params, m.compras.items.length, alm.m.has(K)], [['mypump_compras_get'], { p_token: TOKEN }, 1, true], 'con suplementación: una llamada, solo el token, y queda la copia');
  // Sin red queda lo que se veía; en otra carga sin red sale de la copia (con la palanca que se supo).
  rpc.respuestas.mypump_compras_get = RED;
  await m.refrescar(true);
  eq(m.compras.items.length, 1, 'sin red queda');
  const m2 = C.crearModelo({ token: TOKEN, rpc: rpcDoble({ mypump_compras_get: CAIDO }), almacen: alm });
  eq(m2.aplicarConfig(null), true, 'sin config: lo último que se supo');
  await m2.refrescar(true);
  eq(m2.compras.items[0].nombre, 'Omega 3', 'la copia');
  eq(C.crearModelo({ token: 'otra-cuenta', rpc, almacen: alm }).compras, null, 'la copia es por cuenta');
  // Nada que mostrar: se borra la copia.
  for (const r of [NO_EXISTE, ok(null), ok({ habilitado: false }), ok(resp([]))]) {
    const a2 = almacen(Object.fromEntries(alm.m));
    const x = C.crearModelo({ token: TOKEN, rpc: rpcDoble({ mypump_compras_get: r }), almacen: a2 });
    x.aplicarConfig({ compras_pais: true });
    await x.refrescar(true);
    eq([x.compras, a2.m.has(K)], [null, false], `no se ve con ${JSON.stringify(r).slice(0, 50)}`);
  }
  // Se queda sin suplementación: deja de verse sin llamar.
  rpc.respuestas.mypump_compras_get = ok(resp([{ nombre: 'Omega 3', opciones: [OP] }]));
  await m.refrescar(true);
  const antes = rpc.llamadas.length;
  await m.refrescar(false);
  eq([m.compras, rpc.llamadas.length], [null, antes], 'sin suplementación: nada');
  // Se apaga: se borra todo.
  await m.refrescar(true);
  m.aplicarConfig({ compras_pais: false });
  eq([m.compras, alm.m.has(K)], [null, false], 'al apagarla desaparece');
}
{
  // Una respuesta vieja que llega tarde no pisa a la nueva.
  let soltar; const espera = new Promise((r) => { soltar = r; });
  const rpc = rpcDoble({ mypump_compras_get: (p, k) => (k === 1 ? espera.then(() => ok(resp([{ nombre: 'Vieja', opciones: [OP] }]))) : ok(resp([{ nombre: 'Nueva', opciones: [OP] }]))) });
  const m = C.crearModelo({ token: TOKEN, rpc, almacen: almacen() });
  m.aplicarConfig({ compras_pais: true });
  const a = m.refrescar(true);
  await m.refrescar(true);
  soltar(); await a;
  eq(m.compras.items[0].nombre, 'Nueva', 'gana la última');
}

console.log(`compras: ${n} ok`);
