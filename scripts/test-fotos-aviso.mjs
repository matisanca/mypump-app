#!/usr/bin/env node
/* =============================================================
 * test-fotos-aviso.mjs — lo que la sección de fotos le dice al cliente.
 *
 * POR QUÉ EXISTE
 * El handler de _tomarFoto agarraba #fpMsg UNA vez, al arrancar, y escribía
 * siempre en ese. Pero renderMydayFotos rehace el bloque con innerHTML y crea
 * un #fpMsg nuevo: desde el primer render, 'Subiendo…', 'Listo, guardada ✓',
 * 'Sin conexión: queda guardada y se sube sola.' y 'No se pudo guardar:
 * <motivo>' iban a un elemento que ya no estaba en la página. El cliente veía
 * 'Preparando la foto…', que se borraba con el render, y nunca se enteraba de
 * un rechazo (4xx). Visto en local el 15-oct-2026.
 *
 * Y aunque escribiera en el de la pantalla, el render que viene después (las
 * URLs firmadas, una pasada de la cola) lo dejaba vacío otra vez.
 *
 * Se extrae de cliente.html el código REAL (la cola, renderMydayFotos,
 * cargarFotosFirmadas, _tomarFoto y abrirGaleriaFotos) y se corre con una
 * página de mentira que hace lo mismo que el navegador: el innerHTML de
 * #myday-fotos crea un #fpMsg nuevo y el viejo queda fuera de la página.
 * La red (_subirFoto, fotosFirmadas) y el canvas (_fotoAJpeg) son dobles.
 *
 * USO:  node scripts/test-fotos-aviso.mjs
 * ============================================================= */

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const raiz = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const html = fs.readFileSync(path.join(raiz, 'public/cliente.html'), 'utf8');

// Las funciones de nivel superior de cliente.html cierran con `}` en la columna 0.
const funcion = (nombre) => {
  const m = html.match(new RegExp(`\\n((?:async )?function ${nombre}\\([^)]*\\) \\{[\\s\\S]*?\\n\\})\\n`));
  if (!m) { console.error(`✗ no encontré ${nombre} en cliente.html`); process.exit(1); }
  return m[1];
};
const ini = html.indexOf('const POSES = [');
const fin = html.indexOf('\nasync function loadFotos()', ini);
if (ini < 0 || fin < 0) { console.error('✗ no encontré la cola de fotos en cliente.html'); process.exit(1); }
const fuente = html.slice(ini, fin).replace(funcion('_subirFoto'), '').replace(funcion('_fotoAJpeg'), '')
  + '\n' + ['cargarFotosFirmadas', '_avanceSegmentos', '_encabezadoAvance', 'renderMydayFotos', '_tomarFoto', 'abrirGaleriaFotos'].map(funcion).join('\n');

let ok = 0, fail = 0;
const t = async (nombre, fn) => {
  let reloj;
  const colgado = new Promise((_, no) => { reloj = setTimeout(() => no(new Error('no terminó en 5 s: algo quedó esperando para siempre')), 5000); });
  try { await Promise.race([fn(), colgado]); console.log(`  ✓ ${nombre}`); ok++; }
  catch (e) { console.log(`  ✗ ${nombre}\n      ${e.message}`); fail++; }
  finally { clearTimeout(reloj); }
};
const dormir = (ms) => new Promise(r => setTimeout(r, ms));
async function hasta(cond, que) {
  const t0 = Date.now();
  while (!cond()) {
    if (Date.now() - t0 > 3000) throw new Error(`no pasó: ${que}`);
    await dormir(5);
  }
}

const HOY = '2026-11-04';            // miércoles
const LUNES = '2026-11-02';
const LUNES_ANTERIOR = '2026-10-26';
const FOTO = 'data:image/jpeg;base64,/9j/FOTO';

// Los textos tal cual los ve el cliente.
const DICE = {
  preparando: 'Preparando la foto…',
  subiendo: 'Subiendo…',
  listo: 'Listo, guardada ✓',
  sinRed: 'Sin conexión: queda guardada y se sube sola.',
  rechazo: 'No se pudo guardar: fecha fuera de rango',
  noGuardo: 'No se pudo guardar. Probá de nuevo con señal.',
  noLee: 'No se pudo leer esa foto. Probá con otra o sacala con la cámara.',
  galeria: 'No se pudieron cargar las fotos ahora.',
};

/* La página: #myday-fotos y el #fpMsg que haya adentro. Como en el navegador,
   cada innerHTML deja afuera el #fpMsg anterior y crea uno nuevo, vacío. */
function pagina() {
  const avisos = [];      // todos los #fpMsg que hubo, en orden
  let aviso = null;       // el que está en la página
  let renders = 0;
  const bloque = {
    set innerHTML(h) {
      renders++;
      if (aviso) aviso.enPagina = false;
      aviso = null;
      if (h.includes('id="fpMsg"')) {
        aviso = { textContent: '', className: 'fp-msg', enPagina: true };
        avisos.push(aviso);
      }
    },
    querySelectorAll: () => [],
  };
  return {
    document: { getElementById: (id) => (id === 'myday-fotos' ? bloque : id === 'fpMsg' ? aviso : null) },
    enPantalla: () => aviso,
    perdido: () => avisos.filter(a => !a.enPagina && a.textContent).map(a => a.textContent).pop(),
    renders: () => renders,
  };
}

/* El servicio de fotos. Cada subida sigue su guion, con lo que devuelve el
   _subirFoto real: 'ok', 'sinRed', '502', '400' (rechazo: no va a entrar
   nunca) o 'compuerta' (espera a que la prueba la suelte, y después ok). */
function servicio(guion) {
  const s = { recibidas: 0, bucket: [], frenadas: [] };
  s.soltar = () => s.frenadas.splice(0).forEach(seguir => seguir());
  s.subir = async (pose) => {
    s.recibidas++;
    const paso = guion.length ? guion.shift() : 'sinRed';
    if (paso === 'compuerta') await new Promise(seguir => s.frenadas.push(seguir));
    if (paso === 'sinRed') return { ok: false, fatal: false, red: true, error: 'sin conexión' };
    if (paso === '502') return { ok: false, fatal: false, error: 'HTTP 502' };
    if (paso === '400') return { ok: false, fatal: true, error: 'fecha fuera de rango' };
    s.bucket.push({ semana_lunes: LUNES, pose });
    return { ok: true, semana: LUNES };
  };
  return s;
}

/* Monta la sección real con los dobles y la pinta, como cuando el cliente
   entra a Revisión. `fotos`: lo que ya tenía subido. `cuota`: los caracteres
   que entran en localStorage (más, tira como Safari). `jpeg`: el _fotoAJpeg. */
function montar({ guion = [], fotos = [], cuota, jpeg } = {}) {
  const store = {};
  const pag = pagina();
  const s = servicio(guion);
  // Las URLs firmadas: cada pedido espera a que la prueba conteste.
  const firmas = { pedidos: [], contestar(lista) { this.pedidos.splice(0).forEach(r => r(lista)); } };
  const inputs = {};
  const STATE = { scene: 'revision', fotos: fotos.slice(), fotosUrls: null };
  const ctx = {
    TOKEN: 'tok',
    STATE,
    navigator: { onLine: true },
    localStorage: {
      getItem: k => (k in store ? store[k] : null),
      setItem: (k, v) => {
        if (cuota && String(v).length > cuota) throw new Error('QuotaExceededError');
        store[k] = String(v);
      },
      removeItem: k => { delete store[k]; },
    },
    window: { MYPUMP_CONFIG: { VISION_URL: 'https://fotos.test' } },
    document: pag.document,
    hoyLocal: () => HOY,
    web230: () => false,
    FOTOS_URLS_TTL: 50 * 60 * 1000,
    _subirFoto: (...a) => s.subir(...a),
    _fotoAJpeg: jpeg || (async (archivo) => archivo.dataUrl),   // el "archivo" ya trae su JPEG
    _fpInput: (origen) => (inputs[origen] = inputs[origen] || { value: '', files: null, onchange: null, click() {} }),
    loadFotos: async () => { STATE.fotos = [...fotos, ...s.bucket]; },
    fotosFirmadas: () => new Promise(r => firmas.pedidos.push(r)),
    renderRecordatorio() {},
    _pedirFoto() {},
  };
  const api = new Function(...Object.keys(ctx),
    `${fuente}\nreturn { flushFotos, renderMydayFotos, _tomarFoto, abrirGaleriaFotos };`)(...Object.values(ctx));
  api.renderMydayFotos();   // la sección ya está en pantalla cuando el cliente toca una pose
  /* El cliente toca la pose y elige la foto: corre el onchange REAL. */
  const sacar = (pose = 'frente') => {
    api._tomarFoto(pose, 'camara');
    const inp = inputs.camara;
    inp.files = [{ dataUrl: FOTO }];
    return inp.onchange();
  };
  const enCola = () => Object.keys(JSON.parse(store.mypump_fotoq_tok || '{}'));
  return { api, s, pag, firmas, sacar, enCola };
}

/* Lo que dice el #fpMsg que está en la página. */
function ve(m, texto, clase) {
  const a = m.pag.enPantalla();
  if (!a) throw new Error('no hay #fpMsg en la página');
  if (a.textContent !== texto) {
    const perdido = m.pag.perdido();
    throw new Error(`en pantalla dice «${a.textContent}» y tenía que decir «${texto}»`
      + (perdido && perdido !== a.textContent ? `; «${perdido}» quedó escrito en un #fpMsg que ya no está en la página` : ''));
  }
  if (clase && !a.className.split(/\s+/).includes(clase)) throw new Error(`dice «${texto}» pero con la clase «${a.className}», sin ${clase}`);
}

console.log('\nEl aviso va al #fpMsg que está en pantalla, no al de antes del render');

await t('sin señal: «Sin conexión: queda guardada y se sube sola.»', async () => {
  const m = montar({ guion: ['sinRed'] });
  await m.sacar();
  ve(m, DICE.sinRed, 'is-warn');
});

await t('rechazo (4xx): «No se pudo guardar: <motivo>»', async () => {
  const m = montar({ guion: ['400'] });
  await m.sacar();
  ve(m, DICE.rechazo, 'is-err');
});

await t('subió bien: «Listo, guardada ✓»', async () => {
  const m = montar({ guion: ['ok'] });
  await m.sacar();
  ve(m, DICE.listo, 'is-ok');
});

await t('no entra en el teléfono y no hay señal: «No se pudo guardar. Probá de nuevo con señal.»', async () => {
  const m = montar({ guion: ['sinRed'], cuota: 20 });
  await m.sacar();
  ve(m, DICE.noGuardo, 'is-err');
});

await t('mientras sube: «Subiendo…»', async () => {
  const m = montar({ guion: ['compuerta'] });
  const listo = m.sacar();
  await hasta(() => m.s.recibidas >= 1, 'la subida no arrancó');
  ve(m, DICE.subiendo);
  m.s.soltar();
  await listo;
  ve(m, DICE.listo, 'is-ok');
});

await t('foto que no se puede leer, con un render en el medio (volver de la cámara drena la cola)', async () => {
  let fallar;
  const m = montar({ jpeg: () => new Promise((_, no) => { fallar = no; }) });
  const listo = m.sacar();
  await hasta(() => fallar, 'no llegó a convertir la foto');
  ve(m, DICE.preparando);
  m.api.renderMydayFotos();
  fallar(new Error('no se pudo leer la imagen'));
  await listo;
  ve(m, DICE.noLee, 'is-err');
});

console.log('\nLos renders que vienen después no lo borran');

await t('llegan las URLs firmadas y se repinta la miniatura: «Listo, guardada ✓» sigue', async () => {
  const m = montar({ guion: ['ok'] });
  await m.sacar();
  await hasta(() => m.firmas.pedidos.length, 'después de subir no se pidieron las URLs firmadas');
  const antes = m.pag.renders();
  m.firmas.contestar([{ semana_lunes: LUNES, pose: 'frente', url: 'https://fotos.test/frente.jpg' }]);
  await hasta(() => m.pag.renders() > antes, 'con las URLs no se repintó');
  ve(m, DICE.listo, 'is-ok');
});

await t('el rechazo tampoco: las URLs firmadas que se pidieron al entrar llegan después y repintan', async () => {
  const m = montar({ guion: ['400'], fotos: [{ semana_lunes: LUNES_ANTERIOR, pose: 'frente' }] });
  await m.sacar();
  ve(m, DICE.rechazo, 'is-err');
  const antes = m.pag.renders();
  m.firmas.contestar([{ semana_lunes: LUNES_ANTERIOR, pose: 'frente', url: 'https://fotos.test/vieja.jpg' }]);
  await hasta(() => m.pag.renders() > antes, 'con las URLs no se repintó');
  ve(m, DICE.rechazo, 'is-err');
});

await t('una pasada de la cola que sigue sin señal no borra «Sin conexión…»', async () => {
  const m = montar({ guion: ['sinRed', 'sinRed'] });
  await m.sacar();
  const antes = m.pag.renders();
  await m.api.flushFotos();
  if (m.pag.renders() === antes) throw new Error('la pasada no repintó: la prueba no prueba nada');
  if (m.enCola().length !== 1) throw new Error('la foto tenía que seguir en la cola');
  ve(m, DICE.sinRed, 'is-warn');
});

await t('«Ver mis fotos» sin conexión, con un render en el medio: «No se pudieron cargar las fotos ahora.»', async () => {
  const m = montar({ fotos: [{ semana_lunes: LUNES_ANTERIOR, pose: 'frente' }] });
  const abrir = m.api.abrirGaleriaFotos();
  m.api.renderMydayFotos();
  m.firmas.contestar([]);
  await abrir;
  ve(m, DICE.galeria, 'is-err');
});

console.log('\nY no queda un aviso que ya no es cierto');

await t('la pasada sube la foto que había quedado sin señal: «Sin conexión…» se va', async () => {
  const m = montar({ guion: ['sinRed', 'ok'] });
  await m.sacar();
  await m.api.flushFotos();
  if (m.enCola().length || m.s.bucket.length !== 1) throw new Error('la pasada no subió la foto: la prueba no prueba nada');
  ve(m, '');
});

await t('la pasada la manda y la rechazan (4xx): tampoco queda «se sube sola»', async () => {
  const m = montar({ guion: ['sinRed', '400'] });
  await m.sacar();
  await m.api.flushFotos();
  if (m.enCola().length) throw new Error('el rechazo tenía que sacarla de la cola');
  ve(m, '');
});

console.log(`\n${ok} pasaron, ${fail} fallaron\n`);
process.exit(fail ? 1 : 0);
