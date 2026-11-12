#!/usr/bin/env node
/* =============================================================
 * test-fotos-inicio.mjs — reglas, textos y siluetas de «Fotos de inicio», con
 * los MISMOS vectores de iOS y Android (scripts/vectores-app/fotos_inicio.json,
 * copia exacta de apps/shared/vectores/fotos_inicio.json), la fecha del EXIF,
 * el quitado de metadatos y que el service worker no guarde nada de esta sección.
 * USO:  node scripts/test-fotos-inicio.mjs
 * ============================================================= */
import fs from 'node:fs';
import vm from 'node:vm';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const F = require('../public/js/fotos-inicio.js');
const V = JSON.parse(fs.readFileSync(new URL('./vectores-app/fotos_inicio.json', import.meta.url), 'utf8'));

let ok = 0, fail = 0;
const igual = (a, b) => JSON.stringify(a) === JSON.stringify(b);
function t(nombre, cond, extra) {
  if (cond) { ok++; return; }
  fail++;
  console.log(`  ✗ ${nombre}${extra === undefined ? '' : ` → ${JSON.stringify(extra)}`}`);
}

// ── Constantes, poses y consejos ──
t('poses', igual(F.POSES, V.poses), F.POSES);
t('consejos', igual(F.CONSEJOS, V.consejos), F.CONSEJOS);
for (const k of ['maxPx', 'calidad', 'minLado', 'minLadoMotivacion', 'maxMotivacion', 'maxNota', 'brilloMinimo', 'nitidezMinima', 'diasVieja', 'ladoAnalisis']) {
  const nombre = k.replace(/[A-Z]/g, (c) => `_${c}`).toUpperCase();
  t(`constante ${k}`, F[nombre] === V[k], [nombre, F[nombre], V[k]]);
}

// ── Textos: las mismas claves y los mismos valores; nada de IA, inteligencia ni coach ──
for (const [k, v] of Object.entries(V.textos)) t(`texto ${k}`, F.T[k] === v, F.T[k]);
for (const k of Object.keys(F.T)) t(`texto de más ${k}`, k in V.textos || ['cuenta', 'faltan', 'problemaVieja'].includes(k));
for (const c of V.plurales) {
  t(`faltan ${c.n}`, F.T.faltan(c.n) === c.faltan, F.T.faltan(c.n));
  t(`cuenta ${c.n}`, F.T.cuenta(c.n) === c.cuenta, F.T.cuenta(c.n));
  t(`vieja ${c.n}`, F.T.problemaVieja(c.n) === c.vieja && F.texto('vieja', c.n) === c.vieja);
}
for (const [k, v] of Object.entries(V.textosProblema)) t(`texto del problema ${k}`, F.texto(k) === v, F.texto(k));
t('vieja sin días: 8', F.texto('vieja') === F.T.problemaVieja(8));
{
  const todos = [...Object.values(F.T).map((v) => (typeof v === 'function' ? v(2) : v)), ...F.CONSEJOS, ...F.POSES.flatMap((p) => [p.nombre, p.instruccion])];
  for (const v of todos) t(`sin IA ni coach: ${v.slice(0, 30)}`, !/\bIA\b|inteligencia|coach|entrenador|\bAI\b/i.test(v), v);
}

// ── Luma y medir: aritmética entera idéntica a Swift ──
for (const c of V.luma) t(`luma ${c.r},${c.g},${c.b}`, F.luma(c.r, c.g, c.b) === c.l, F.luma(c.r, c.g, c.b));
for (const c of V.medir) {
  const m = F.medir(Uint8Array.from(c.luma), c.ancho, c.alto, c.paso);
  t(`medir ${c.caso}`, m.brillo === c.brillo && m.nitidez === c.nitidez, m);
  const a = F.medir(c.luma, c.ancho, c.alto, c.paso);
  t(`medir ${c.caso} (lista común)`, a.brillo === c.brillo && a.nitidez === c.nitidez, a);
}
t('medir sin píxeles', igual(F.medir(new Uint8Array(3), 2, 2), { brillo: 0, nitidez: 0 }));
t('medir ancho 0', igual(F.medir(new Uint8Array(0), 0, 5), { brillo: 0, nitidez: 0 }));
{
  // RGBA → luma: lo que lee el canvas.
  const rgba = Uint8ClampedArray.from([255, 0, 0, 255, 0, 255, 0, 255, 12, 200, 99, 0]);
  t('luma de RGBA', igual(Array.from(F.lumaDeRGBA(rgba, 3, 1)), [76, 149, 132]));
}

// ── Problemas y bloquea ──
for (const c of V.problemas) {
  const p = F.problemas(c.pose, c.ancho, c.alto, { brillo: c.brillo, nitidez: c.nitidez }, c.dias);
  t(`problemas ${JSON.stringify(c)}`, igual(p, c.problemas), p);
  t(`bloquea ${JSON.stringify(c)}`, F.bloquea(p) === c.bloquea);
}
t('orden de los problemas', igual(F.PROBLEMAS, ['chica', 'apaisada', 'oscura', 'movida', 'vieja']));

// ── Subida ──
for (const c of V.subida) {
  const s = F.clasificarSubida(c.status, c.ok);
  t(`subida ${c.status}/${c.ok}`, s.accion === c.accion && (s.aviso || null) === c.aviso && !!s.refrescar === c.refrescar, s);
}

// ── El set ──
for (const c of V.faltan) {
  t(`faltan ${JSON.stringify(c)}`, igual(F.faltan(c.enServidor, c.enCola), c.faltan), F.faltan(c.enServidor, c.enCola));
  t(`faltan con Set ${JSON.stringify(c)}`, igual(F.faltan(new Set(c.enServidor), new Set(c.enCola)), c.faltan));
}
for (const c of V.siguiente) t(`siguiente ${JSON.stringify(c)}`, F.siguiente(c.pose, c.faltan) === c.siguiente, F.siguiente(c.pose, c.faltan));
for (const c of V.motivacion) t(`motivación ${JSON.stringify(c)}`, F.puedeAgregarMotivacion(c.servidor, c.cola, c.maximo) === c.puede);
t('motivación con el máximo de fábrica', F.puedeAgregarMotivacion(3, 0) === true && F.puedeAgregarMotivacion(4, 0) === false);
for (const c of V.notas) t(`nota ${JSON.stringify(c.s).slice(0, 40)}`, F.notaRecortada(c.s) === c.n, F.notaRecortada(c.s));
t('nota null', F.notaRecortada(null) === '');
t('largo por punto de código', F.largoNota('💪a') === 2);

// ── Días ──
for (const c of V.dias) {
  t(`días ${c.tomada}`, F.dias(c.tomada, c.ahora) === c.dias, F.dias(c.tomada, c.ahora));
  t(`días con Date ${c.tomada}`, F.dias(new Date(c.tomada), new Date(c.ahora)) === c.dias);
}
t('días con algo que no es fecha', F.dias('no', '2026-11-10T00:00:00Z') === 0);

// ── Decodificar el estado ──
for (const c of V.decodificar) {
  const e = F.decodificarEstado(c.j);
  t(`decodificar hab ${JSON.stringify(c.j).slice(0, 50)}`, (e !== null) === c.habilitado);
  if (!e) continue;
  t(`poses ${JSON.stringify(c.j).slice(0, 40)}`, igual([...F.posesDe(e)].sort(), c.poses), [...F.posesDe(e)]);
  t('motivación', F.deMotivacion(e).length === c.motivacion);
  t('nota', e.nota === c.nota); t('completo', e.completo === c.completo); t('maxMotivacion', e.maxMotivacion === c.maxMotivacion);
}
{
  const e = F.decodificarEstado(V.decodificar[3].j);
  const d = e.fotos.find((f) => f.id === 'd');
  t('ancho que no es número → 0', d && d.ancho === 0 && d.alto === 0);
  const a = e.fotos.find((f) => f.id === 'a');
  t('foto completa', a && a.tomadaEn === '2026-11-10T17:00:00+00:00' && a.ancho === 1200 && a.alto === 1600);
  t('completado_en', e.completadoEn === '2026-11-10T17:00:00+00:00');
  t('sin id o basura: afuera', e.fotos.length === 4);
}
t('decodificar lista', F.decodificarEstado([{ habilitado: true }]) === null);
t('decodificar habilitado "true"', F.decodificarEstado({ habilitado: 'true' }) === null);

// ── Siluetas: los mismos trazos que las apps ──
t('caja', igual(V.siluetas.caja, [120, 260]));
for (const k of ['frente', 'perfil', 'espalda']) {
  const s = F.silueta(k);
  t(`silueta ${k}`, s && s.contorno === V.siluetas[k].contorno && s.detalle === V.siluetas[k].detalle);
  t(`silueta ${k} solo M, C y Z`, /^[MCZ0-9 .-]+$/.test(s.contorno + s.detalle));
}
t('sin silueta para la motivación', F.silueta('motivacion') === null && F.silueta('x') === null);

// ── tomada_en ──
{
  const ahora = Date.UTC(2026, 10, 10, 12);
  t('tomada: EXIF primero', F.tomadaEn(ahora - 86400000, ahora - 3600000, ahora) === ahora - 86400000);
  t('tomada: sin EXIF, el archivo', F.tomadaEn(null, ahora - 3600000, ahora) === ahora - 3600000);
  t('tomada: archivo del futuro → ahora', F.tomadaEn(null, ahora + 86400000, ahora) === ahora);
  t('tomada: archivo de 1970 → ahora', F.tomadaEn(null, 0, ahora) === ahora);
  t('tomada: nada → ahora', F.tomadaEn(undefined, NaN, ahora) === ahora);
  t('tomada: un segundo adelantado no cuenta como futuro', F.tomadaEn(null, ahora + 1000, ahora) === ahora);
  t('iso con zona', F.iso(Date.UTC(2026, 10, 10, 12, 0, 5, 123)) === '2026-11-10T12:00:05Z');
}

// ── La fecha del EXIF: JPEG armado a mano ──
const seg = (m, cuerpo) => { const b = Buffer.from(cuerpo); return Buffer.concat([Buffer.from([0xff, m, (b.length + 2) >> 8, (b.length + 2) & 255]), b]); };
const SOI = Buffer.from([0xff, 0xd8]), EOI = Buffer.from([0xff, 0xd9]);
function exifConFecha(fecha, le = true, etiqueta = 0x9003) {
  const u16 = (v) => (le ? [v & 255, v >> 8] : [v >> 8, v & 255]);
  const u32 = (v) => (le ? [v & 255, (v >> 8) & 255, (v >> 16) & 255, v >>> 24] : [v >>> 24, (v >> 16) & 255, (v >> 8) & 255, v & 255]);
  const ifd0 = 8, exifIfd = ifd0 + 2 + 12 + 4, datos = exifIfd + 2 + 12 + 4;
  const tiff = [...(le ? [0x49, 0x49] : [0x4d, 0x4d]), ...u16(42), ...u32(ifd0),
    ...u16(1), ...u16(0x8769), ...u16(4), ...u32(1), ...u32(exifIfd), ...u32(0),
    ...u16(1), ...u16(etiqueta), ...u16(2), ...u32(20), ...u32(datos), ...u32(0),
    ...Buffer.from(`${fecha}\0`, 'latin1')];
  return seg(0xe1, Buffer.concat([Buffer.from('Exif\0\0', 'latin1'), Buffer.from(tiff)]));
}
{
  const jfif = seg(0xe0, 'JFIF\0datos'), dqt = seg(0xdb, 'tablas'), sos = Buffer.concat([seg(0xda, 'cab'), Buffer.from([0x12, 0x34]), EOI]);
  const esperado = new Date(2026, 10, 3, 9, 30, 15).getTime();
  t('EXIF little endian', F.fechaExif(Buffer.concat([SOI, jfif, exifConFecha('2026:11:03 09:30:15'), dqt, sos])) === esperado);
  t('EXIF big endian', F.fechaExif(Buffer.concat([SOI, exifConFecha('2026:11:03 09:30:15', false), dqt, sos])) === esperado);
  t('EXIF DateTimeDigitized', F.fechaExif(Buffer.concat([SOI, exifConFecha('2026:11:03 09:30:15', true, 0x9004), sos])) === esperado);
  t('EXIF sin fecha válida', F.fechaExif(Buffer.concat([SOI, exifConFecha('0000:00:00 00:00:00'), sos])) === null);
  t('sin EXIF', F.fechaExif(Buffer.concat([SOI, jfif, dqt, sos])) === null);
  t('no es JPEG', F.fechaExif(Buffer.from('hola')) === null);
  t('EXIF cortado no rompe', F.fechaExif(Buffer.concat([SOI, exifConFecha('2026:11:03 09:30:15')]).subarray(0, 30)) === null);
}

// ── Quitar metadatos ──
{
  const jfif = seg(0xe0, 'JFIF\0datos'), exif = seg(0xe1, 'Exif\0\0GPSLatitude -34.60'), xmp = seg(0xe1, 'http://ns.adobe.com/xap GPS'), com = seg(0xfe, 'comentario'), icc = seg(0xe2, 'ICC_PROFILE');
  const dqt = seg(0xdb, 'tablas'), sos = Buffer.concat([seg(0xda, 'cab'), Buffer.from([0x12, 0x34, 0xff, 0x00, 0x56])]);
  const sale = Buffer.from(F.quitarMetadatos(Buffer.concat([SOI, jfif, exif, xmp, icc, com, dqt, sos, EOI])));
  t('deja la imagen y saca los metadatos', sale.equals(Buffer.concat([SOI, jfif, dqt, sos, EOI])));
  t('no queda GPS', !sale.toString('latin1').includes('GPS'));
  t('no es JPEG → null', F.quitarMetadatos(Buffer.from('hola mundo')) === null);
}

// ── Reducir sin agrandar ──
t('reduce 4000×3000', igual(F.medidaReducida(4000, 3000), { ancho: 1600, alto: 1200 }));
t('reduce 3024×4032', igual(F.medidaReducida(3024, 4032), { ancho: 1200, alto: 1600 }));
t('no agranda', igual(F.medidaReducida(900, 1200), { ancho: 900, alto: 1200 }));

// ── El service worker: los archivos nuevos en el shell y nada de esta sección va a un cache ──
{
  const fuente = fs.readFileSync(new URL('../public/sw.js', import.meta.url), 'utf8');
  const version = /const VERSION\s*=\s*'([^']+)'/.exec(fuente)[1];
  t('versión del sw subida', Number(/^v(\d+)/.exec(version)[1]) >= 57, version);
  for (const a of ['/js/fotos-inicio.js', '/js/fotos-inicio-cola.js', '/js/fotos-inicio-ui.js', '/css/fotos-inicio.css']) t(`shell ${a}`, fuente.includes(`'${a}'`));
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
  t('POST de subida sin tocar', !responde('https://vision.ejemplo.test/inicio/upload', 'POST'));
  t('RPC sin tocar', !responde('https://x.supabase.co/rest/v1/rpc/mypump_fotos_inicio_get', 'POST'));
  t('URL firmada, otro origen, sin tocar', !responde('https://x.supabase.co/storage/v1/object/sign/fotos-inicio/a.jpg?token=x'));
  t('mismo origen /inicio/ sin tocar', !responde('https://app.ejemplo.test/inicio/a.jpg'));
  t('el resto sigue igual', responde('https://app.ejemplo.test/js/app.js'));
}

// ── La web: escena, ids de prueba y textos que salen del objeto ──
{
  const html = fs.readFileSync(new URL('../public/cliente.html', import.meta.url), 'utf8');
  const ui = fs.readFileSync(new URL('../public/js/fotos-inicio-ui.js', import.meta.url), 'utf8');
  t('escena', html.includes('id="scene-fotosinicio"'));
  for (const s of ['/js/fotos-inicio.js', '/js/fotos-inicio-cola.js', '/js/fotos-inicio-ui.js', '/css/fotos-inicio.css']) t(`cliente.html carga ${s}`, html.includes(s));
  t('palanca fotos_inicio', /cfg\.fotos_inicio === true/.test(html));
  for (const id of ['fotos-inicio-tarjeta', 'fotos-inicio-pose-', 'fotos-inicio-foto', 'fotos-inicio-usar', 'fotos-inicio-otra', 'fotos-inicio-usar-igual',
    'fotos-inicio-problema-', 'fotos-inicio-bien', 'fotos-inicio-motivacion-agregar', 'fotos-inicio-nota', 'fotos-inicio-nota-guardar', 'fotos-inicio-listo']) {
    t(`id de prueba ${id}`, ui.includes(`"${id}`) || ui.includes(`'${id}`) || ui.includes(`data-test="${id}`));
  }
  t('id de prueba mis-datos-fotos-inicio', html.includes('mis-datos-fotos-inicio'));
  t('el input no fuerza la cámara', !/capture/.test(ui.replace(/\/\*[\s\S]*?\*\/|\/\/.*$/gm, '')));
  // Ningún texto suelto en la UI: entre etiquetas solo ${...}.
  const sueltos = [...ui.matchAll(/>\s*([A-Za-zÁÉÍÓÚáéíóúñ¿¡][A-Za-z0-9ÁÉÍÓÚáéíóúñ ,.¿?¡!:]*)\s*</g)].map((m) => m[1].trim()).filter(Boolean);
  t('la UI no escribe textos a mano', sueltos.length === 0, sueltos);
}

console.log(`${fail ? '✗' : '✓'} fotos-inicio: ${ok} ok, ${fail} fallas`);
process.exit(fail ? 1 : 0);
