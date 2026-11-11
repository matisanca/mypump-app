// «Mi salud» (2.3.0, palanca web_230): la lógica pura (js/mi-salud.js) y la navegación cableada en cliente.html.
// La prueba en el navegador, contra un doble, está en nativa-evidencia/mi-salud/h/web/e2e.mjs.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { createRequire } from 'node:module';
const require = createRequire(import.meta.url);
const M = require('../public/js/mi-salud.js');
const leer = (f) => fs.readFileSync(new URL(`../public/${f}`, import.meta.url), 'utf8');
let n = 0;
const caso = (nombre, fn) => { fn(); n++; };

const todo = { estudios: true, proximoControl: true, tarjetaEstudios: { titulo: 'Tenés una orden nueva' }, controlCerca: true,
  presion: true, tarjetaPresion: { estado: 'toma', faltan: 2 }, recuperacion: true };

caso('bloques: en el orden de la pantalla y solo los que hoy se muestran', () => {
  assert.deepEqual(M.bloques(todo), ['control', 'estudios', 'presion', 'recuperacion']);
  assert.deepEqual(M.bloques({ ...todo, proximoControl: false }), ['estudios', 'presion', 'recuperacion']);
  // sin Estudios no hay control (vive adentro de Estudios)
  assert.deepEqual(M.bloques({ ...todo, estudios: false }), ['presion', 'recuperacion']);
  assert.deepEqual(M.bloques({ recuperacion: true }), ['recuperacion']);
  assert.deepEqual(M.bloques({}), []);
  assert.deepEqual(M.bloques(null), []);
});

caso('tarjeta de Revisión: oculta sin bloques, visible con uno', () => {
  assert.equal(M.tarjeta({}), null);
  assert.equal(M.tarjeta({ estudios: false, presion: false, recuperacion: false }), null);
  assert.deepEqual(M.tarjeta({ recuperacion: true }), { bloques: ['recuperacion'], numero: 0, linea: 'Recuperación', primero: null });
  assert.equal(M.tarjeta({ presion: true }).linea, 'Presión');
});

caso('sin nada pendiente: la lista de lo que hay, con comas e «y»', () => {
  assert.equal(M.lista(['control', 'estudios', 'presion', 'recuperacion']), 'Control, estudios, presión y recuperación');
  assert.equal(M.lista(['presion', 'recuperacion']), 'Presión y recuperación');
  assert.equal(M.lista([]), '');
  assert.equal(M.T.verMiControl, 'Ver mi control');
  const t = M.tarjeta({ ...todo, tarjetaEstudios: null, controlCerca: false, tarjetaPresion: { estado: 'hoyListo', faltan: 1 } });
  assert.equal(t.numero, 0);
  assert.equal(t.linea, 'Control, estudios, presión y recuperación');
});

caso('con pendientes: número (máximo 3) y la línea de lo primero, por prioridad', () => {
  const t = M.tarjeta(todo);
  assert.equal(t.numero, 3);
  assert.equal(t.linea, 'Tenés una orden nueva');
  assert.equal(t.primero, 'estudios');
  assert.equal(M.tarjeta({ ...todo, tarjetaEstudios: null }).linea, 'Tu próximo control de salud');
  const p = { ...todo, tarjetaEstudios: null, controlCerca: false };
  assert.equal(M.tarjeta(p).linea, 'Te faltan 2 tomas de presión');
  assert.equal(M.tarjeta({ ...p, tarjetaPresion: { estado: 'toma', faltan: 1 } }).linea, 'Te falta 1 toma de presión');
  assert.equal(M.tarjeta({ ...p, tarjetaPresion: { estado: 'repetir' } }).linea, 'Te falta repetir la toma de presión');
  assert.equal(M.tarjeta({ ...p, tarjetaPresion: { estado: 'preparar' } }).linea, 'Primero medí tu brazo y anotá tu tensiómetro');
  // «La de hoy ya está» no cuenta; con la sección apagada, lo de presión tampoco
  assert.equal(M.tarjeta({ ...p, tarjetaPresion: { estado: 'hoyListo' } }).numero, 0);
  assert.equal(M.tarjeta({ ...todo, presion: false, tarjetaEstudios: null, controlCerca: false }).numero, 0);
  // el control cerca sin Estudios no existe
  assert.equal(M.pendientes({ estudios: false, controlCerca: true }).length, 0);
});

caso('destinos viejos → «Mi salud» en su bloque; el resto sigue igual', () => {
  assert.deepEqual(M.destino('estudios'), { escena: 'misalud', bloque: 'estudios' });
  assert.deepEqual(M.destino('presion'), { escena: 'misalud', bloque: 'presion' });
  assert.deepEqual(M.destino('salud'), { escena: 'misalud', bloque: 'recuperacion' });
  assert.deepEqual(M.destino('myday'), { escena: 'misalud', bloque: 'recuperacion' });
  assert.deepEqual(M.destino('misalud'), { escena: 'misalud', bloque: null });
  for (const d of ['chat', 'revision', 'progress', 'train', 'Estudios', 'constructor', '__proto__', '', null, undefined, 3]) assert.equal(M.destino(d), null, String(d));
});

caso('la tarjeta de presión de Entreno, solo cuando pide algo', () => {
  for (const e of ['repetir', 'preparar', 'toma']) assert.equal(M.presionPideAlgo({ estado: e }), true);
  assert.equal(M.presionPideAlgo({ estado: 'hoyListo' }), false);
  assert.equal(M.presionPideAlgo(null), false);
});

caso('textos: «Mi salud» exacto, sin «entrenador», sin IA, sin ciclo ni medicación', () => {
  assert.equal(M.T.titulo, 'Mi salud');
  const todos = JSON.stringify(Object.values(M.T).map((v) => (typeof v === 'function' ? [v(1), v(2)] : v)));
  assert.doesNotMatch(todos, /entrenador|\bIA\b|inteligencia|ciclo|testo|f[aá]rmac|dosis|\bRIR\b/i);
});

const html = leer('cliente.html');
const fn = (nombre) => { const i = html.indexOf(`function ${nombre}(`); assert.ok(i > 0, nombre); return html.slice(i, html.indexOf('\n}\n', i)); };

caso('navegación: todo detrás de web_230 y Estudios adentro de «Mi salud»', () => {
  assert.match(fn('_miSaludOn'), /web230\(\)/);
  const ss = fn('setScene');
  assert.match(ss, /if \(scene === 'estudios' && _miSaludOn\(\)\) scene = 'misalud';/);
  assert.match(ss, /if \(scene === 'misalud' && !_miSaludOn\(\)\) scene = 'revision';/);
  assert.match(ss, /scene === 'presion' && !_presionPorUI && _miSaludOn\(\)\) \{ irAMiSalud\('presion'\);/);
  assert.match(ss, /if \(scene === 'misalud'\) renderMiSalud\(\);/);
  assert.ok(html.includes('<section class="scene" id="scene-misalud"></section>'));
  assert.ok(html.includes('<script src="/js/mi-salud.js"></script>'));
  assert.ok(leer('sw.js').includes("'/js/mi-salud.js'"));
});

caso('destinos: el link ?scene=, los avisos del teléfono y las novedades pasan por irADestino o Estudios', () => {
  const u = fn('_aplicarSceneDeURL');
  assert.ok(u.indexOf('irADestino(s)') > 0 && u.indexOf('irADestino(s)') < u.indexOf("if (s === 'estudios')"), 'antes de la caída vieja');
  const d = fn('irADestino');
  assert.match(d, /window\.MiSalud\.destino\(d\)/);
  assert.match(d, /EstudiosUI\.destino\('misalud'\)/);
  assert.match(d, /PresionUI\.abrirDirecto\('misalud'\)/);
  const notif = leer('js/notificaciones.js');
  assert.equal((notif.match(/window\.irADestino : window\.setScene\)\(/g) || []).length, 2, 'local y push');
  assert.ok(html.includes('window.irADestino = irADestino;'));
});

caso('un solo lugar: Mis datos y Revisión no repiten Estudios, Presión ni Recuperación con la palanca prendida', () => {
  const md = fn('renderMisDatos');
  assert.match(md, /\$\{!ms && window\.EstudiosUI && window\.EstudiosUI\.entradaVisible\(\)/);
  assert.match(md, /\$\{!ms && window\.PresionUI && window\.PresionUI\.entradaVisible\(\)/);
  assert.match(md, /id="mdMiSalud"/);
  assert.match(fn('_renderRevTarjetas'), /_miSaludOn\(\) \? '' : tarjeta\('rvRecup'/);
  assert.match(fn('_estPuntos'), /id === 'estPuntoMisDatos' && _miSaludOn\(\)/);
});

caso('Estudios y Presión: los ganchos que usa «Mi salud», sin cambiar nada con la palanca apagada', () => {
  const eu = leer('js/estudios-ui.js');
  assert.match(eu, /const incrustada = \(\) => !!\(ui\.op && ui\.op\.incrustada && ui\.op\.incrustada\(\)\);/);
  assert.match(eu, /incrustada\(\) \? '' : controlHtml\(pc\)/);
  const pu = leer('js/presion-ui.js');
  assert.match(pu, /sinTarjeta \|\| \(soloConAlgo && t && t\.estado === 'hoyListo'\) \? '' : tarjetaHtml\(ui\.modelo\)/);
  assert.match(pu, /origen === 'train' \|\| origen === 'misalud' \? origen : 'misdatos'/);
});

console.log(`mi-salud: ${n} casos ok`);
