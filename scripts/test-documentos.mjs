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

// La palanca `contrato_app` en cliente.html: apagada (o sin la clave) no llama a mypump_contrato_get ni muestra nada.
{
  const fs = await import('node:fs');
  const vm = await import('node:vm');
  const html = fs.readFileSync(path.join(raiz, 'public/cliente.html'), 'utf8');
  const a = html.indexOf('const _DOC_PALANCA_KEY'), b = html.indexOf('// Quien firmó en otra pestaña');
  const c = html.indexOf('function renderAvisoContrato()'), d = html.indexOf('/* ═══════ MIS DATOS (app 2.1.0');
  assert.ok(a > 0 && b > a && c > b && d > c, 'bloque de Documentos en cliente.html');
  const montar = (guardado) => {
    const mem = new Map(guardado ? [['mypump_palanca_contrato_app', '1']] : []);
    const llamadas = [], avisos = [];
    const ctx = {
      STATE: { documentos: [], mdDocs: false, scene: 'train' }, TOKEN: 'tok', DATA: {}, JSON,
      localStorage: { getItem: k => mem.has(k) ? mem.get(k) : null, setItem: (k, v) => mem.set(k, String(v)), removeItem: k => mem.delete(k) },
      window: { MyPumpDocumentos: { ...D, hayContratoPendiente: D.hayContratoPendiente }, mypumpDB: { getContrato: async (t) => { llamadas.push(t); return { documentos: [{ id: 'd1', tipo: 'servicio_ar', estado: 'pendiente' }] }; } } },
      document: { querySelectorAll: () => [], getElementById: () => null },
      renderMisDatos: () => {}, escapeHtml: x => x, _CHEV_DER: '',
    };
    ctx.document.getElementById = () => { avisos.push(1); return null; };
    vm.createContext(ctx);
    vm.runInContext(html.slice(a, b) + html.slice(c, d) + '\nthis._docPalanca = _docPalanca; this.loadDocumentos = loadDocumentos; this.renderAvisoContrato = renderAvisoContrato; this.on = () => _docOn;', ctx);
    return { ctx, mem, llamadas, avisos };
  };
  const espera = () => new Promise(r => setTimeout(r, 0));
  let m = montar(false);
  await m.ctx.loadDocumentos(); m.ctx.renderAvisoContrato();
  m.ctx._docPalanca({}); await espera(); await m.ctx.loadDocumentos(); m.ctx.renderAvisoContrato();
  m.ctx._docPalanca(null); await espera();
  assert.equal(m.llamadas.length, 0, 'sin la clave: ninguna llamada');
  assert.equal(m.avisos.length, 0, 'sin la clave: ningún aviso');
  assert.equal(m.ctx.STATE.documentos.length, 0);
  m.ctx._docPalanca({ contrato_app: true }); await espera();
  assert.equal(m.llamadas.length, 1, 'prendida: lee el contrato');
  assert.equal(m.mem.get('mypump_palanca_contrato_app'), '1');
  assert.equal(m.ctx.STATE.documentos.length, 1);
  m.ctx._docPalanca({ contrato_app: false }); await espera();
  assert.equal(m.ctx.STATE.documentos.length, 0, 'apagada: se va lo leído');
  assert.equal(m.mem.has('mypump_palanca_contrato_app'), false);
  await m.ctx.loadDocumentos();
  assert.equal(m.llamadas.length, 1, 'apagada: no vuelve a leer');
  m = montar(true);
  assert.equal(m.ctx.on(), true, 'con lo último guardado arranca prendida');
  m.ctx._docPalanca(null); await m.ctx.loadDocumentos();
  assert.equal(m.ctx.on(), true, 'config sin respuesta: vale lo guardado');
  assert.equal(m.llamadas.length, 1);
  n++; console.log('✓ palanca contrato_app: apagada sin la clave, último valor sin respuesta');
}
console.log(`${n} pruebas OK`);
