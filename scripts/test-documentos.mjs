// Pruebas de public/js/documentos.js
// Uso: node test-documentos.mjs <ruta a mn-web-contrato>
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import path from 'node:path';
const raiz = process.argv[2] || path.resolve(path.dirname(new URL(import.meta.url).pathname), '..');
const require = createRequire(import.meta.url);
const D = require(path.join(raiz, 'public/js/documentos.js'));
const BA = 'America/Argentina/Buenos_Aires';
let n = 0;
const t = (nombre, f) => { f(); n++; console.log('✓', nombre); };

t('la respuesta se lee entera', () => {
  const docs = D.decodificar({ documentos: [
    { id: 'd1', tipo: 'servicio_ar', titulo: 'C', estado: 'pendiente', firmado_en: null, revocado_en: null },
    { id: 'd2', tipo: 'consentimiento_ar', estado: 'firmado', firmado_en: '2026-11-10T15:03:22.123456+00:00' },
  ], pendientes: 1 });
  assert.deepEqual(docs.map(d => d.tipo), ['servicio_ar', 'consentimiento_ar']);
  assert.equal(docs[1].firmado_en, '2026-11-10T15:03:22.123456+00:00');
});

t('lo desconocido se descarta; error = sin documentos', () => {
  const docs = D.decodificar({ documentos: [
    { id: 'a', tipo: 'servicio_ext', estado: 'anulado' }, { id: 'b', tipo: 'otro', estado: 'pendiente' },
    { tipo: 'servicio_ar', estado: 'pendiente' }, null, 7, 'x',
    { id: 'c', tipo: 'servicio_ext', estado: 'revocado', revocado_en: '2026-11-12 03:30:00+00' },
  ] });
  assert.deepEqual(docs.map(d => d.id), ['c']);
  for (const r of [null, undefined, [], {}, { documentos: 'nada' }, 'texto', 3]) assert.deepEqual(D.decodificar(r), []);
});

t('nombres por tipo', () => {
  assert.equal(D.nombre('servicio_ar'), 'Contrato de coaching');
  assert.equal(D.nombre('servicio_ext'), 'Contrato de coaching');
  assert.equal(D.nombre('consentimiento_ar'), 'Consentimiento de atención médica');
});

t('estado a texto (igual que iOS y Android)', () => {
  assert.equal(D.estado({ estado: 'pendiente' }, BA), 'Pendiente de firma');
  assert.equal(D.boton('pendiente'), 'Leer y firmar');
  assert.equal(D.estado({ estado: 'firmado', firmado_en: '2026-11-10T15:03:22.123456+00:00' }, BA), 'Firmado el 10/11/2026');
  assert.equal(D.boton('firmado'), 'Ver documento');
  assert.equal(D.estado({ estado: 'revocado', revocado_en: '2026-11-12 02:30:00+00' }, BA), 'Revocado el 11/11/2026');
  assert.equal(D.boton('revocado'), 'Ver documento');
  assert.equal(D.estado({ estado: 'firmado', firmado_en: 'ayer' }, BA), 'Firmado');
});

t('el aviso solo con un contrato pendiente', () => {
  assert.equal(D.hayContratoPendiente([]), false);
  assert.equal(D.hayContratoPendiente(null), false);
  assert.equal(D.hayContratoPendiente([{ tipo: 'consentimiento_ar', estado: 'pendiente' }]), false);
  assert.equal(D.hayContratoPendiente([{ tipo: 'servicio_ar', estado: 'firmado' }]), false);
  assert.equal(D.hayContratoPendiente([{ tipo: 'servicio_ext', estado: 'pendiente' }]), true);
});

t('enlace: solo https del propio servicio, del documento pedido', () => {
  const s = 'https://firma.mypumpteam.com';
  const resp = { documentos: [{ id: 'd2', url: 'https://firma.mypumpteam.com/f/otro' }, { id: 'd1', url: 'https://firma.mypumpteam.com/f/abc.def' }] };
  assert.equal(D.enlaceDe(resp, 'd1', s), 'https://firma.mypumpteam.com/f/abc.def');
  assert.equal(D.enlaceDe(resp, 'd9', s), null);
  assert.equal(D.enlaceDe({ error: 'token' }, 'd1', s), null);
  assert.equal(D.enlaceDe(null, 'd1', s), null);
  for (const u of ['http://firma.mypumpteam.com/f/x', 'https://otro.example.com/f/x', 'https://firma.mypumpteam.com.example.com/f/x', 'javascript:alert(1)', '']) {
    assert.equal(D.enlaceSeguro(u, s), null, u);
  }
});

t('textos: sin pagos ni precios', () => {
  const todos = Object.values(D.T).concat(['servicio_ar', 'consentimiento_ar'].map(D.nombre));
  for (const x of todos) for (const p of ['pago', 'pagar', 'precio', 'cuota', '$', 'usd', 'comprar', 'suscrip']) {
    assert.ok(!x.toLowerCase().includes(p), `${x} nombra ${p}`);
  }
  assert.equal(D.T.errorAbrir, 'No pudimos abrir el documento. Probá de nuevo en un rato o usá el enlace que te llegó por correo.');
});
console.log(`${n} pruebas OK`);
