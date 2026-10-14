#!/usr/bin/env node
/* =============================================================
   cdp-localstorage.mjs — siembra y lee el localStorage de la Capacitor de Android por DevTools

   La Capacitor de debug deja depurar su WebView: con `adb forward` al socket `webview_devtools_remote_<pid>`,
   el protocolo de DevTools corre JavaScript en la página `https://localhost`. Así se siembra la "verdad" (la
   misma semilla que la prueba de iOS) con la app viva, y se lee de vuelta tal cual la ve la app.

   Uso: node scripts/nativa/cdp-localstorage.mjs <puerto> leer
        node scripts/nativa/cdp-localstorage.mjs <puerto> sembrar <semilla.json>
   Escribe en stdout el localStorage entero como JSON {clave: valor}.
   ============================================================= */
import fs from 'node:fs';

const [puerto, accion, archivo] = process.argv.slice(2);
const paginas = await (await fetch(`http://127.0.0.1:${puerto}/json`)).json();
const pagina = paginas.find((p) => p.type === 'page' && p.url.startsWith('https://localhost'));
if (!pagina) throw new Error(`sin página https://localhost: ${JSON.stringify(paginas.map((p) => p.url))}`);

const ws = new WebSocket(pagina.webSocketDebuggerUrl);
await new Promise((ok, mal) => { ws.onopen = ok; ws.onerror = mal; });
let id = 0;
const pendientes = new Map();
ws.onmessage = (e) => {
  const m = JSON.parse(e.data);
  if (pendientes.has(m.id)) { pendientes.get(m.id)(m); pendientes.delete(m.id); }
};
const enviar = (method, params) => new Promise((ok) => { const i = ++id; pendientes.set(i, ok); ws.send(JSON.stringify({ id: i, method, params })); });
async function evaluar(expresion) {
  const m = await enviar('Runtime.evaluate', { expression: expresion, returnByValue: true });
  if (m.error || m.result?.exceptionDetails) throw new Error(JSON.stringify(m.error || m.result.exceptionDetails));
  return m.result.result.value;
}

if (accion === 'sembrar') {
  const semilla = JSON.parse(fs.readFileSync(archivo, 'utf8'));
  for (const [k, v] of Object.entries(semilla)) await evaluar(`localStorage.setItem(${JSON.stringify(k)}, ${JSON.stringify(v)})`);
}
const todo = await evaluar(`JSON.stringify(Object.fromEntries(Array.from({ length: localStorage.length }, (_, i) => localStorage.key(i)).map((k) => [k, localStorage.getItem(k)])))`);
process.stdout.write(todo);
ws.close();
