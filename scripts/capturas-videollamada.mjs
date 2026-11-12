// Capturas y prueba de punta a punta de la videollamada 2.3.0 en la web, con el doble de prueba
// (scripts/lib/doble-agenda.js): sin red, sin producción y sin Meet real. Sirve public/ y la página de prueba en
// 127.0.0.1 y maneja Chrome headless por CDP con un viewport de teléfono de verdad (como capturas-tienda.mjs).
//
// USO:  node scripts/capturas-videollamada.mjs [carpeta de salida]
// Sale con código 1 si algo no da (scroll horizontal, una llamada que no salió, un botón que falta).
import { spawn } from 'node:child_process';
import { createServer } from 'node:http';
import { readFileSync, writeFileSync, mkdirSync, existsSync, mkdtempSync } from 'node:fs';
import { join, extname, normalize, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { tmpdir } from 'node:os';

const raiz = dirname(dirname(fileURLToPath(import.meta.url)));
const SALIDA = process.argv[2] || join(raiz, 'capturas-videollamada');
mkdirSync(SALIDA, { recursive: true });
const CH = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const ANCHO = 390, ALTO = 844;
const sleep = ms => new Promise(r => setTimeout(r, ms));

// ── El servidor local: public/ y la página de prueba ──
const TIPOS = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.css': 'text/css', '.woff2': 'font/woff2', '.svg': 'image/svg+xml', '.png': 'image/png' };
const servidor = createServer((req, res) => {
  const ruta = decodeURIComponent(new URL(req.url, 'http://x').pathname);
  let archivo;
  if (ruta === '/prueba/' || ruta === '/prueba/index.html') archivo = join(raiz, 'scripts/videollamada/prueba.html');
  else if (ruta === '/prueba/doble-agenda.js') archivo = join(raiz, 'scripts/lib/doble-agenda.js');
  else archivo = join(raiz, 'public', normalize(ruta).replace(/^(\.\.[/\\])+/, ''));
  if (!archivo.startsWith(raiz) || !existsSync(archivo)) { res.writeHead(404); res.end(); return; }
  res.writeHead(200, { 'content-type': TIPOS[extname(archivo)] || 'application/octet-stream', 'cache-control': 'no-store' });
  res.end(readFileSync(archivo));
});
// Puertos libres que elige el sistema (la máquina puede tener otros servidores andando).
await new Promise(r => servidor.listen(0, '127.0.0.1', r));
const BASE = `http://127.0.0.1:${servidor.address().port}/prueba/`;

const perfil = mkdtempSync(join(tmpdir(), 'vl-chrome-'));
const chrome = spawn(CH, ['--headless=new', '--disable-gpu', '--hide-scrollbars', '--no-first-run', '--no-default-browser-check',
  '--remote-debugging-port=0', `--user-data-dir=${perfil}`], { stdio: 'ignore' });

let ws, id = 0, fallas = 0;
const pend = new Map();
const cmd = (method, params = {}) => new Promise((res, rej) => {
  const i = ++id; pend.set(i, { res, rej });
  ws.send(JSON.stringify({ id: i, method, params }));
});
const evaluar = async expr => {
  const r = await cmd('Runtime.evaluate', { expression: expr, awaitPromise: true, returnByValue: true });
  if (r.exceptionDetails) throw new Error(`${expr}: ${JSON.stringify(r.exceptionDetails.exception && r.exceptionDetails.exception.description)}`);
  return r.result.value;
};
const comprobar = (c, m) => { console.log(`${c ? '  ✓' : '  ✗'} ${m}`); if (!c) fallas++; };
const clic = async sel => comprobar(await evaluar(`(() => { const b = document.querySelector(${JSON.stringify(sel)}); if (!b || b.disabled) return false; b.click(); return true; })()`), `clic en ${sel}`);

async function abrir(escenario, tema, extra = '') {
  await cmd('Page.navigate', { url: `${BASE}?escenario=${escenario}&tema=${tema}${extra}` });
  await sleep(1500);
}
async function capturar(nombre) {
  const sinScroll = await evaluar('document.documentElement.scrollWidth <= innerWidth && [...document.querySelectorAll(".vl-pantalla,.vl-p-cuerpo")].every(e => e.scrollWidth <= e.clientWidth + 1)');
  comprobar(sinScroll, `${nombre}: sin scroll horizontal a ${ANCHO} px`);
  const { data } = await cmd('Page.captureScreenshot', { format: 'png' });
  const out = join(SALIDA, `${nombre}.png`);
  writeFileSync(out, Buffer.from(data, 'base64'));
  console.log(`  → ${out}`);
}
const texto = sel => evaluar(`(document.querySelector(${JSON.stringify(sel)}) || {}).textContent || ''`);
const llamadas = () => evaluar('JSON.stringify(window.mypumpDB.llamadas)').then(JSON.parse);

try {
  let lista;
  for (let i = 0; i < 120; i++) {
    try {
      const puerto = readFileSync(join(perfil, 'DevToolsActivePort'), 'utf8').split('\n')[0].trim();
      lista = await (await fetch(`http://127.0.0.1:${puerto}/json`)).json(); if (lista.length) break;
    } catch { /* arrancando */ }
    await sleep(250);
  }
  const pagina = lista.find(t => t.type === 'page');
  ws = new WebSocket(pagina.webSocketDebuggerUrl);
  await new Promise(r => ws.addEventListener('open', r));
  ws.addEventListener('message', e => {
    const m = JSON.parse(e.data);
    if (m.id && pend.has(m.id)) { const { res, rej } = pend.get(m.id); pend.delete(m.id); m.error ? rej(new Error(JSON.stringify(m.error))) : res(m.result); }
  });
  await cmd('Page.enable');
  await cmd('Runtime.enable');
  await cmd('Emulation.setDeviceMetricsOverride', { width: ANCHO, height: ALTO, deviceScaleFactor: 2, mobile: true, screenWidth: ANCHO, screenHeight: ALTO });
  await cmd('Emulation.setTouchEmulationEnabled', { enabled: true, maxTouchPoints: 5 });
  await cmd('Emulation.setTimezoneOverride', { timezoneId: 'America/Argentina/Buenos_Aires' });

  for (const tema of ['claro', 'oscuro']) {
    const t = tema === 'claro' ? 'light' : 'dark';
    console.log(`\n▸ ${tema}`);
    await cmd('Emulation.setEmulatedMedia', { features: [{ name: 'prefers-color-scheme', value: t }] });

    // 1. Elegir el horario y confirmar (palanca prendida).
    await abrir('elegir', t);
    comprobar((await texto('.vl-agendar .vl-titulo')) === 'Agendá tu videollamada de comienzo', 'tarjeta «Agendá tu videollamada de comienzo» arriba de Entreno');
    await capturar(`web-agendar-${tema}`);
    await clic('[data-vl="elegir"]');
    await sleep(400);
    comprobar((await texto('.vl-pantalla [data-vl="confirmar"]')) === 'Elegí un horario', 'botón apagado «Elegí un horario»');
    await clic('.vl-p-hora:nth-of-type(1)');
    await sleep(300);
    comprobar(/^Confirmar \S+ \d+, 10:00$/.test(await texto('.vl-pantalla [data-vl="confirmar"]')), `botón «${await texto('.vl-pantalla [data-vl="confirmar"]')}»`);
    await capturar(`web-elegir-horario-${tema}`);
    await clic('.vl-pantalla [data-vl="confirmar"]');
    await sleep(1200);
    comprobar((await texto('#vl-p-titulo')) === 'Listo, quedó agendada', 'pantalla «Listo, quedó agendada»');
    comprobar((await llamadas()).filter(l => l.fn === 'entregas_app_reservar').length === 1, 'una sola entregas_app_reservar (por la cola)');
    await capturar(`web-confirmacion-${tema}`);
    await clic('.vl-pantalla [data-vl="cerrar"]');
    await sleep(500);
    comprobar(!!(await evaluar('!!document.querySelector(".vl-tarjeta:not(.vl-agendar)")')), 'después de agendar, la tarjeta de la videollamada arriba');

    // 2. Días antes: la tarjeta fija, «Entrar» apagado y el cambio.
    await abrir('diasAntes', t);
    comprobar((await texto('.vl-cuenta')) === 'Se habilita 10 minutos antes de empezar', 'cuenta: «Se habilita 10 minutos antes de empezar»');
    comprobar(/^En \d+ días$|^Mañana$/.test(await texto('.vl-cuando')), `etiqueta «${await texto('.vl-cuando')}»`);
    comprobar(await evaluar('!!document.querySelector(".vl-tarjeta button.vl-boton[disabled]")'), '«Entrar» apagado');
    await clic('.vl-ayuda summary');
    await sleep(300);
    comprobar(await evaluar('document.querySelector(".vl-ayuda").open && document.querySelectorAll(".vl-ayuda li").length === 5'), '«¿Cómo entro?» con los 5 pasos');
    await capturar(`web-tarjeta-dias-antes-${tema}`);
    await clic('[data-vl="cambiar"]');
    await sleep(400);
    comprobar(/^Ahora es el \S+ \d+ a las 10:00\.$/.test(await texto('.vl-p-ahora b')), `«${await texto('.vl-p-ahora b')}»`);
    comprobar(/^Podés cambiarlo 1 vez, hasta el \S+ \d+ a las 10:00\.$/.test(await texto('.vl-p-ahora .vl-nota')), `«${await texto('.vl-p-ahora .vl-nota')}»`);
    await clic('.vl-p-dia:nth-of-type(3) .vl-p-hora:nth-of-type(2)');
    await sleep(300);
    comprobar(/^Cambiar al \S+ \d+, 12:00$/.test(await texto('.vl-pantalla [data-vl="confirmar"]')), `botón «${await texto('.vl-pantalla [data-vl="confirmar"]')}»`);
    await capturar(`web-cambiar-horario-${tema}`);
    await clic('.vl-pantalla [data-vl="confirmar"]');
    await sleep(1200);
    const cambios = (await llamadas()).filter(l => l.fn === 'entregas_app_cambiar');
    comprobar(cambios.length === 1 && cambios[0].p_reserva === 'r1' && /^[0-9a-f-]{36}$/.test(cambios[0].p_id), 'entregas_app_cambiar(p_reserva r1, p_id uuid) una vez');
    comprobar((await texto('#vl-p-titulo')) === 'Listo, la cambiamos', 'pantalla «Listo, la cambiamos»');
    await clic('.vl-pantalla [data-vl="cerrar"]');
    await sleep(600);
    comprobar(!(await evaluar('!!document.querySelector("[data-vl=cambiar]")')), 'sin cambios restantes ya no se ofrece cambiar');

    // 3. Por entrar: la tarjeta verde con «Entrar a la videollamada».
    await abrir('porEntrar', t);
    const a = await evaluar('(() => { const a = document.querySelector("a.vl-entrar"); return a && { href: a.href, target: a.target, rel: a.rel }; })()');
    comprobar(!!a && a.href === 'https://meet.google.com/abc-defg-hij' && a.target === '_blank' && /noopener/.test(a.rel), '«Entrar a la videollamada» abre el link de mentira en otra pestaña (noopener)');
    comprobar((await texto('.vl-ya')) === 'Ya podés entrar', '«Ya podés entrar»');
    comprobar((await texto('.vl-admite')) === 'Mati te admite en la sala. Si tarda un poco, esperá ahí sin salir.', 'texto de la sala');
    // 2.3.1: el código de la reunión debajo de «Entrar», con «Copiar código» y dónde pegarlo.
    comprobar((await texto('.vl-codigo-valor')) === 'abc-defg-hij', 'el código de la reunión a la vista');
    comprobar((await texto('.vl-codigo-pasos')).includes('Si no se abre la reunión:') && (await evaluar('document.querySelectorAll(".vl-codigo-pasos li").length')) === 4,
      'dónde pegar el código, en 4 pasos');
    comprobar((await texto('.vl-codigo-copiar')) === 'Copiar código', '«Copiar código»');
    await capturar(`web-tarjeta-entrar-${tema}`);
    await clic('[data-vl="copiar-codigo"]');
    await sleep(400);
    comprobar((await texto('.vl-codigo-copiar')) === 'Código copiado' || (await evaluar('String(getSelection())')) === 'abc-defg-hij',
      '«Copiar código» copia (o deja el código seleccionado si no hay portapapeles)');
    await capturar(`web-codigo-copiado-${tema}`);

    // 4. Palanca apagada: sin «Agendá» ni la pantalla nueva; nunca se llama a cambiar.
    await abrir('diasAntes', t, '&palanca=0');
    comprobar(!(await evaluar('!!document.querySelector("[data-vl=cambiar],[data-vl=elegir]")')), 'palanca apagada: sin «Cambiar horario» ni «Elegir horario»');
    comprobar((await texto('.vl-nota')) === '¿Necesitás cambiarla? Escribinos por el chat.', 'palanca apagada: «¿Necesitás cambiarla? Escribinos por el chat.»');
    await abrir('elegir', t, '&palanca=0');
    comprobar(!(await evaluar('!!document.querySelector(".vl-agendar")')), 'palanca apagada: sin «Agendá tu videollamada» en Entreno');
  }

  // Texto grande (el navegador al 150 %): todo en rem.
  console.log('\n▸ texto grande');
  await cmd('Emulation.setEmulatedMedia', { features: [{ name: 'prefers-color-scheme', value: 'light' }] });
  for (const [esc, nombre] of [['porEntrar', 'web-tarjeta-entrar-texto-grande'], ['diasAntes', 'web-tarjeta-dias-antes-texto-grande']]) {
    await abrir(esc, 'light');
    await evaluar('document.documentElement.style.fontSize = "150%"');
    await sleep(300);
    await capturar(nombre);
  }
  await abrir('elegir', 'light');
  await evaluar('document.documentElement.style.fontSize = "150%"');
  await clic('[data-vl="elegir"]');
  await sleep(300);
  await clic('.vl-p-hora:nth-of-type(2)');
  await capturar('web-elegir-horario-texto-grande');
} finally {
  ws?.close();
  chrome.kill();
  servidor.close();
}
console.log(fallas ? `\n✗ ${fallas} comprobaciones fallaron` : '\n✓ capturas-videollamada: todo OK');
process.exit(fallas ? 1 : 0);
