// Capturas de tienda con emulación REAL de móvil.
//
// `chrome --headless --screenshot --window-size` NO sirve: el viewport de
// layout queda en 756px (medido) y la captura recorta a 360 — por eso las
// capturas viejas salían cortadas a la derecha y el LEEME decía que era un
// artefacto de headless. Acá se hace por CDP con Emulation.setDeviceMetricsOverride,
// que es lo único que da un viewport móvil de verdad.
import { spawn } from 'node:child_process';
import { writeFileSync } from 'node:fs';

const CH = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const PORT = 9333;
const UA = 'Mozilla/5.0 (Linux; Android 14; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36';
const sleep = ms => new Promise(r => setTimeout(r, ms));

const TOMAS = JSON.parse(process.argv[2]); // [{scene, out, espera?, js?}]
const BASE = process.argv[3];

const chrome = spawn(CH, [
  '--headless=new', '--disable-gpu', '--hide-scrollbars', '--no-first-run',
  `--remote-debugging-port=${PORT}`, '--user-data-dir=/tmp/_shotprofile',
], { stdio: 'ignore' });

let ws, id = 0;
const pend = new Map();
const cmd = (method, params = {}) => new Promise((res, rej) => {
  const i = ++id; pend.set(i, { res, rej });
  ws.send(JSON.stringify({ id: i, method, params }));
});

try {
  let list;
  for (let i = 0; i < 60; i++) {
    try { list = await (await fetch(`http://127.0.0.1:${PORT}/json`)).json(); if (list.length) break; } catch {}
    await sleep(250);
  }
  const page = list.find(t => t.type === 'page');
  ws = new WebSocket(page.webSocketDebuggerUrl);
  await new Promise(r => ws.addEventListener('open', r));
  ws.addEventListener('message', e => {
    const m = JSON.parse(e.data);
    if (m.id && pend.has(m.id)) {
      const { res, rej } = pend.get(m.id); pend.delete(m.id);
      m.error ? rej(new Error(m.method + ' ' + JSON.stringify(m.error))) : res(m.result);
    }
  });

  await cmd('Page.enable');
  await cmd('Emulation.setDeviceMetricsOverride', {
    width: 360, height: 640, deviceScaleFactor: 3, mobile: true,
    screenWidth: 360, screenHeight: 640,
  });
  await cmd('Emulation.setUserAgentOverride', { userAgent: UA, platform: 'Linux armv8l' });
  await cmd('Emulation.setTouchEmulationEnabled', { enabled: true, maxTouchPoints: 5 });

  for (const t of TOMAS) {
    await cmd('Page.navigate', { url: `${BASE}&scene=${t.scene}` });
    await sleep(t.espera ?? 9000);
    // El banner de "Instalá MyPump como app" solo existe en la version web y
    // tapa media pantalla. En una captura para Play seria doblemente absurdo:
    // el que la mira ya esta instalando la app nativa.
    await cmd('Runtime.evaluate', { expression: "document.querySelectorAll('.a2hs-banner,.dl-popup,[id*=descarga]').forEach(e=>e.remove())" });
    await sleep(400);
    if (t.js) {
      await cmd('Runtime.evaluate', { expression: t.js, awaitPromise: true });
      await sleep(t.tras ?? 2500);
    }
    const vp = await cmd('Runtime.evaluate', { expression: 'innerWidth+"x"+innerHeight+" scroll="+document.documentElement.scrollWidth', returnByValue: true });
    const { data } = await cmd('Page.captureScreenshot', { format: 'png', captureBeyondViewport: false });
    writeFileSync(t.out, Buffer.from(data, 'base64'));
    console.log(`✓ ${t.out}  vp=${vp.result.value}`);
  }
} finally {
  ws?.close(); chrome.kill();
}
