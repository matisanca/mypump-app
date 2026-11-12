#!/usr/bin/env node
/* =============================================================
 * test-gimnasio.mjs — reglas de «Gimnasio por fotos», con los MISMOS vectores
 * de iOS y Android (scripts/vectores-app/gimnasio.json, copia exacta de
 * apps/shared/vectores/gimnasio.json), el quitado de metadatos y que el service
 * worker no guarde nada de esta sección.
 * USO:  node scripts/test-gimnasio.mjs
 * ============================================================= */
import fs from 'node:fs';
import vm from 'node:vm';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const G = require('../public/js/gimnasio.js');
const V = JSON.parse(fs.readFileSync(new URL('./vectores-app/gimnasio.json', import.meta.url), 'utf8'));

let ok = 0, fail = 0;
const igual = (a, b) => JSON.stringify(a) === JSON.stringify(b);
function t(nombre, cond, extra) {
  if (cond) { ok++; return; }
  fail++;
  console.log(`  ✗ ${nombre}${extra === undefined ? '' : ` → ${JSON.stringify(extra)}`}`);
}

t('zonas', igual(G.ZONAS.map(({ clave, nombre }) => ({ clave, nombre })), V.zonas));
t('tope', G.TOPE_FOTOS === V.topeFotos); t('nota', G.MAX_NOTA === V.maxNota); t('px', G.MAX_PX === V.maxPx); t('calidad', G.CALIDAD === V.calidad);
for (const [k, v] of Object.entries(V.textos)) t(`texto ${k}`, G.T[k] === v, G.T[k]);
for (const c of V.plurales) {
  t(`fotos ${c.n}`, G.T.cuentaFotos(c.n) === c.fotos);
  t(`faltan ${c.n}`, G.T.faltanZonas(c.n) === c.faltan);
  t(`necesitamos ${c.n}`, G.T.necesitamosFotos(c.n) === c.necesitamos);
}
for (const c of V.faltantes) t(`faltantes ${JSON.stringify(c)}`, igual(G.zonasFaltantes(c.conFotos, c.noHay, c.modo), c.faltan));
for (const c of V.puedeEnviar) t(`puedeEnviar ${JSON.stringify(c)}`, G.puedeEnviar(c.modo, c.conFotos, c.noHay, c.quitar) === c.puede);
for (const c of V.tope) { t(`restan ${c.servidor}+${c.cola}`, G.restan(c.servidor, c.cola) === c.restan); t(`puede ${c.servidor}+${c.cola}`, G.puedeAgregar(c.servidor, c.cola) === c.puede); }
for (const c of V.pantalla) t(`pantalla ${c.abierta}/${c.vigente}`, G.pantalla(c.abierta, c.vigente) === c.pantalla);
for (const c of V.tarjeta) t(`tarjeta ${JSON.stringify(c)}`, G.tarjetaVisible(c.habilitado, c.abierta, c.vigente) === c.visible);
for (const c of V.entrada) t(`entrada ${JSON.stringify(c)}`, G.entradaVisible(c.habilitado, c.vigente) === c.visible);
for (const c of V.subida) {
  const s = G.clasificarSubida(c.status, c.ok);
  t(`subida ${c.status}/${c.ok}`, s.accion === c.accion && (s.aviso || undefined) === c.aviso && !!s.refrescar === !!c.refrescar, s);
}
for (const c of V.respuestas) {
  const p = G.decodificarPregunta(c.p);
  t(`respuesta ${c.p.id} ${JSON.stringify(c.v)}`, G.respuestaValida(p, c.v) === c.valida);
}
{
  const ps = V.paraEnviar.preguntas.map(G.decodificarPregunta);
  t('paraEnviar', igual(G.respuestasParaEnviar(ps, V.paraEnviar.borrador), V.paraEnviar.resultado));
  t('fotosPedidas', G.fotosPedidas(ps, V.paraEnviar.borrador) === V.paraEnviar.fotosPedidas);
  // 2.3.1: la de opción múltiple que vio y no marcó va como []; «No sé» sigue como duda.
  const pw = V.paraEnviarVistas.preguntas.map(G.decodificarPregunta);
  t('paraEnviar con vistas', igual(G.respuestasParaEnviar(pw, V.paraEnviarVistas.borrador, V.paraEnviarVistas.vistas), V.paraEnviarVistas.resultado));
  t('paraEnviar sin vistas', igual(G.respuestasParaEnviar(pw, V.paraEnviarVistas.borrador), V.paraEnviarVistas.sinVistas));
}
for (const c of V.kilos) t(`kilos ${JSON.stringify(c.s)}`, G.kilos(c.s) === c.n, G.kilos(c.s));
for (const c of V.fechas) t(`fecha ${c.iso}`, G.fechaCorta(c.iso, c.zona) === c.texto, G.fechaCorta(c.iso, c.zona));
for (const c of V.decodificar) {
  const e = G.decodificarEstado(c.j);
  t(`decodificar hab ${JSON.stringify(c.j).slice(0, 40)}`, (e !== null) === c.habilitado);
  if (!e) continue;
  t('abierta', (e.abierta ? e.abierta.estado : undefined) === c.abierta);
  if (c.equipos !== undefined) { t('equipos', e.vigente.equipos.length === c.equipos); t('cantidad', e.vigente.equipos[e.vigente.equipos.length - 1].cantidad === c.cantidad); }
  if (c.preguntas !== undefined) t('preguntas', e.abierta.preguntas.length === c.preguntas);
}

// ── Lo que trae cuando ningún dato sobra: nunca nombres de IA ni RIR en lo que lee el alumno ──
for (const [k, v] of Object.entries(G.T)) {
  if (typeof v !== 'string') continue;
  t(`sin IA ni RIR: ${k}`, !/\bIA\b|inteligencia artificial|servicios externos|entrenador|\bRIR\b/i.test(v), v);
}

// ── Quitar metadatos: JPEG armado a mano con EXIF y GPS ──
const seg = (m, cuerpo) => { const b = Buffer.from(cuerpo); return Buffer.concat([Buffer.from([0xff, m, (b.length + 2) >> 8, (b.length + 2) & 255]), b]); };
const SOI = Buffer.from([0xff, 0xd8]), EOI = Buffer.from([0xff, 0xd9]);
const jfif = seg(0xe0, 'JFIF\0datos'), exif = seg(0xe1, 'Exif\0\0GPSLatitude -34.60'), xmp = seg(0xe1, 'http://ns.adobe.com/xap GPS'), com = seg(0xfe, 'comentario'), icc = seg(0xe2, 'ICC_PROFILE');
const dqt = seg(0xdb, 'tablas'), sos = Buffer.concat([seg(0xda, 'cab'), Buffer.from([0x12, 0x34, 0xff, 0x00, 0x56])]);
{
  const sale = Buffer.from(G.quitarMetadatos(Buffer.concat([SOI, jfif, exif, xmp, icc, com, dqt, sos, EOI])));
  t('deja la imagen y saca los metadatos', sale.equals(Buffer.concat([SOI, jfif, dqt, sos, EOI])), sale.toString('latin1'));
  t('no queda GPS', !sale.toString('latin1').includes('GPS'));
  t('no es JPEG → null', G.quitarMetadatos(Buffer.from('hola mundo')) === null);
  t('segmento cortado → null', G.quitarMetadatos(Buffer.concat([SOI, Buffer.from([0xff, 0xe1, 0xff, 0xff, 1, 2])])) === null);
}

// ── El service worker: nada de esta sección va a un cache ──
{
  const fuente = fs.readFileSync(new URL('../public/sw.js', import.meta.url), 'utf8');
  const version = /const VERSION\s*=\s*'([^']+)'/.exec(fuente)[1];
  t('versión del sw subida', Number(/^v(\d+)/.exec(version)[1]) >= 55, version);
  for (const a of ['/js/gimnasio.js', '/js/gimnasio-cola.js', '/js/gimnasio-ui.js', '/css/gimnasio.css']) t(`shell ${a}`, fuente.includes(`'${a}'`));
  const oyentes = {};
  const ctx = {
    self: { addEventListener: (n, f) => { oyentes[n] = f; } }, location: new URL('https://app.ejemplo.test/'), URL, caches: {},
    fetch: () => { throw new Error('no debería ir a la red'); }, console,
  };
  vm.createContext(ctx);
  vm.runInContext(fuente, ctx);
  const responde = (url, method = 'GET', mode = 'cors') => {
    let usado = false;
    oyentes.fetch({ request: { url, method, mode }, respondWith() { usado = true; } });
    return usado;
  };
  t('POST de subida sin tocar', !responde('https://vision.ejemplo.test/gimnasio/upload', 'POST'));
  t('POST de urls sin tocar', !responde('https://vision.ejemplo.test/gimnasio/urls', 'POST'));
  t('RPC sin tocar', !responde('https://x.supabase.co/rest/v1/rpc/mypump_gimnasio_get', 'POST'));
  t('URL firmada, otro origen, sin tocar', !responde('https://x.supabase.co/storage/v1/object/sign/gimnasio/a.jpg?token=x'));
  t('mismo origen /gimnasio/ sin tocar', !responde('https://app.ejemplo.test/gimnasio/a.jpg'));
  t('el resto sigue igual', responde('https://app.ejemplo.test/js/app.js'));
}

console.log(`${fail ? '✗' : '✓'} gimnasio: ${ok} ok, ${fail} fallas`);
process.exit(fail ? 1 : 0);
