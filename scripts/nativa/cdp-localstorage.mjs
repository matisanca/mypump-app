#!/usr/bin/env node
/* =============================================================
   cdp-localstorage.mjs — siembra y lee el localStorage de la Capacitor de Android por DevTools

   La Capacitor de debug deja depurar su WebView: con `adb forward` al socket `webview_devtools_remote_<pid>`,
   el protocolo de DevTools corre JavaScript en la página `https://localhost`. Así se siembra la "verdad" (la
   misma semilla que la prueba de iOS) con la app viva, y se lee de vuelta tal cual la ve la app.

   Uso: node scripts/nativa/cdp-localstorage.mjs <puerto> leer
        node scripts/nativa/cdp-localstorage.mjs <puerto> sembrar <semilla.json | ->
        node scripts/nativa/cdp-localstorage.mjs <puerto> navegar <url>
   `leer` y `sembrar` escriben en stdout el localStorage entero como JSON {clave: valor}; con `-` la semilla
   llega por stdin (así un token no pasa por los argumentos, que los ve `ps`). `navegar` lleva la página a otra
   URL del mismo origen y espera que cargue: con la app vieja fuera de la
   página, nada pisa lo que se siembra después (sirve un archivo estático como /manifest.json: una ruta que no existe
   deja la página en chrome-error://). Escribe {href, origin} de la página nueva.
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
const eventos = [];
ws.onmessage = (e) => {
  const m = JSON.parse(e.data);
  if (pendientes.has(m.id)) { pendientes.get(m.id)(m); pendientes.delete(m.id); } else if (m.method) eventos.push(m);
};
const enviar = (method, params) => new Promise((ok) => { const i = ++id; pendientes.set(i, ok); ws.send(JSON.stringify({ id: i, method, params })); });
// Al abrir, index.html salta a cliente.html: una evaluación en el medio encuentra el contexto destruido (o sin
// localStorage todavía). Se reintenta; lo que se evalúa acá se puede repetir sin efectos (leer, o setItem de lo mismo).
async function evaluar(expresion) {
  let ultimo;
  for (let i = 0; i < 20; i++) {
    const m = await enviar('Runtime.evaluate', { expression: expresion, returnByValue: true });
    if (!m.error && !m.result?.exceptionDetails) return m.result.result.value;
    ultimo = JSON.stringify(m.error || m.result.exceptionDetails);
    await new Promise((ok) => setTimeout(ok, 500));
  }
  throw new Error(ultimo);
}
// En JavaScript de antes de Chrome 73 (Object.fromEntries no existe): el WebView de Android 9 sin actualizar es el 66.
const todo = () => evaluar(`(function () { var o = {}; for (var i = 0; i < localStorage.length; i++) { var k = localStorage.key(i); o[k] = localStorage.getItem(k); } return JSON.stringify(o); })()`);

if (accion === 'navegar') {
  await enviar('Page.enable', {});
  await enviar('Page.navigate', { url: archivo });
  for (let i = 0; i < 100 && !eventos.some((e) => e.method === 'Page.loadEventFired'); i++) await new Promise((ok) => setTimeout(ok, 100));
  process.stdout.write(await evaluar('JSON.stringify({ href: location.href, origin: location.origin })'));
} else {
  if (accion === 'sembrar') {
    const texto = archivo === '-' ? fs.readFileSync(0, 'utf8') : fs.readFileSync(archivo, 'utf8');
    const semilla = JSON.parse(texto);
    // Todo en una sola evaluación: una sola tanda para Chromium.
    await evaluar(`(function (s) { for (const [k, v] of Object.entries(s)) localStorage.setItem(k, v); return true; })(${JSON.stringify(semilla)})`);
  }
  process.stdout.write(await todo());
}
ws.close();
