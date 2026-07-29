#!/usr/bin/env node
/* =============================================================
 * test-wearables.mjs — ejercita functions/api/wearables/_lib.js
 *
 * POR QUÉ EXISTE
 * Este código NUNCA se ejecutó. Se escribió esperando las credenciales de
 * Oura y Whoop, que todavía no están cargadas, así que no corrió ni una vez —
 * exactamente el escenario donde vivían los 6 bugs encontrados el 28-jul
 * (cuatro RPCs consultando una tabla inexistente, una función de validación
 * que nadie llamaba). "Compila" no es "anda".
 *
 * Lo que sí se puede probar hoy, sin ninguna credencial: la cripto, que es la
 * parte donde una falla es peor. Si cifrar/descifrar no hace round-trip, los
 * refresh tokens quedan guardados como basura y no se nota hasta que un
 * cliente conecta su reloj y deja de sincronizar días después.
 *
 * NOTA SOBRE EL import: _lib.js es ESM, pero package.json no declara
 * "type":"module", así que Node trataría un .js como CommonJS y `export` sería
 * un error de sintaxis. Se importa por data: URL, que fuerza ESM y evalúa el
 * archivo TAL CUAL está — sin copiarlo ni transformarlo, que es lo único que
 * hace válida la prueba.
 *
 * USO:  node scripts/test-wearables.mjs
 * ============================================================= */

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { webcrypto } from 'node:crypto';

const raiz = path.dirname(path.dirname(fileURLToPath(import.meta.url)));

// Cloudflare Workers exponen crypto/atob/btoa como globales; Node moderno
// también, pero se aseguran acá para que el test no dependa de la versión.
if (!globalThis.crypto) globalThis.crypto = webcrypto;

const src = fs.readFileSync(path.join(raiz, 'functions/api/wearables/_lib.js'), 'utf8');
const lib = await import('data:text/javascript;base64,' + Buffer.from(src).toString('base64'));

const { cifrar, descifrar, faltaConfig, redirectUri, PROVEEDORES, aleatorio, b64u } = lib;

let ok = 0, fail = 0;
const t = async (nombre, fn) => {
  try { await fn(); console.log(`  ✓ ${nombre}`); ok++; }
  catch (e) { console.log(`  ✗ ${nombre}\n      ${e.message}`); fail++; }
};

// Clave de prueba: 32 bytes en base64 estándar, igual que la que va a
// OAUTH_ENC_KEY (`openssl rand -base64 32`).
const env = { OAUTH_ENC_KEY: Buffer.from(webcrypto.getRandomValues(new Uint8Array(32))).toString('base64') };

console.log('\nCifrado de los tokens');

await t('un token cifrado se recupera igual', async () => {
  const original = 'ory_at_7f3c9a1b-refresh-token-de-oura-con-guiones_y.puntos';
  const vuelto = await descifrar(env, await cifrar(env, original));
  if (vuelto !== original) throw new Error(`volvió "${vuelto}"`);
});

await t('el texto cifrado no contiene el original', async () => {
  const original = 'token-secretisimo-1234';
  const blob = await cifrar(env, original);
  if (blob.includes(original)) throw new Error('el token viaja en claro');
});

await t('dos cifrados del MISMO texto dan distinto (IV nuevo cada vez)', async () => {
  // Reusar el IV en AES-GCM no es un detalle: filtra el plaintext y rompe la
  // autenticación. Si esto falla, el cifrado no sirve de nada.
  const a = await cifrar(env, 'igual');
  const b = await cifrar(env, 'igual');
  if (a === b) throw new Error('mismo ciphertext dos veces → IV reusado');
  if (a.split('.')[0] === b.split('.')[0]) throw new Error('el IV se repite');
});

await t('un ciphertext manipulado NO se descifra (GCM autentica)', async () => {
  const blob = await cifrar(env, 'saldo: 100');
  const [iv, ct] = blob.split('.');
  // Se cambia un carácter del cuerpo cifrado.
  const roto = iv + '.' + (ct[0] === 'A' ? 'B' : 'A') + ct.slice(1);
  let fallo = false;
  try { await descifrar(env, roto); } catch (e) { fallo = true; }
  if (!fallo) throw new Error('aceptó un ciphertext alterado: no está autenticando');
});

await t('con OTRA clave no se puede leer', async () => {
  const otra = { OAUTH_ENC_KEY: Buffer.from(webcrypto.getRandomValues(new Uint8Array(32))).toString('base64') };
  const blob = await cifrar(env, 'privado');
  let fallo = false;
  try { await descifrar(otra, blob); } catch (e) { fallo = true; }
  if (!fallo) throw new Error('descifró con una clave distinta');
});

await t('entrada vacía o mal formada devuelve null y no revienta', async () => {
  if (await cifrar(env, '') !== null) throw new Error('cifrar("") debería dar null');
  if (await cifrar(env, null) !== null) throw new Error('cifrar(null) debería dar null');
  if (await descifrar(env, null) !== null) throw new Error('descifrar(null) debería dar null');
  if (await descifrar(env, 'sin-punto') !== null) throw new Error('un blob sin "." debería dar null');
});

await t('aguanta un token largo (Whoop manda JWT grandes)', async () => {
  // b64u hace String.fromCharCode(...array): con arrays enormes revienta el
  // stack. Un refresh token de Whoop ronda el kilobyte.
  const largo = 'x'.repeat(4096);
  const vuelto = await descifrar(env, await cifrar(env, largo));
  if (vuelto !== largo) throw new Error('se perdió en el camino');
});

await t('aguanta acentos y emoji (UTF-8 multibyte)', async () => {
  const raro = 'señal-ñandú-café-🏋️';
  const vuelto = await descifrar(env, await cifrar(env, raro));
  if (vuelto !== raro) throw new Error(`volvió "${vuelto}"`);
});

console.log('\nConfiguración');

await t('faltaConfig nombra la env var que falta', () => {
  const completo = {
    OAUTH_ENC_KEY: 'x', OAUTH_REDIRECT_BASE: 'https://app.mypumpteam.com',
    SUPABASE_URL: 'https://x.supabase.co', SUPABASE_SERVICE_ROLE_KEY: 'k',
    OURA_CLIENT_ID: 'i', OURA_CLIENT_SECRET: 's',
  };
  if (faltaConfig(completo, 'oura') !== null) throw new Error('con todo cargado no debería faltar nada');
  for (const k of Object.keys(completo)) {
    const sinUna = { ...completo }; delete sinUna[k];
    const r = faltaConfig(sinUna, 'oura');
    if (!r || !r.includes(k)) throw new Error(`sin ${k} debería avisar por su nombre, dijo "${r}"`);
  }
});

await t('un proveedor desconocido no explota', () => {
  if (!faltaConfig({}, 'garmin')) throw new Error('debería rechazar un proveedor que no existe');
});

await t('la redirect_uri es la que hay que registrar en Oura y Whoop', () => {
  const u = redirectUri({ OAUTH_REDIRECT_BASE: 'https://app.mypumpteam.com' });
  if (u !== 'https://app.mypumpteam.com/api/wearables/callback') throw new Error(u);
  // Sin barra final duplicada: los proveedores comparan la URL exacta y
  // "//callback" no matchea con lo registrado.
  const u2 = redirectUri({ OAUTH_REDIRECT_BASE: 'https://app.mypumpteam.com/' });
  if (u2.includes('//api')) throw new Error(`barra doble: ${u2} — no va a matchear con la registrada`);
});

await t('cada proveedor tiene todos los campos que el flujo necesita', () => {
  for (const [clave, p] of Object.entries(PROVEEDORES)) {
    for (const campo of ['nombre', 'authorize', 'token', 'scopes', 'idEnv', 'secretEnv']) {
      if (p[campo] === undefined) throw new Error(`${clave}: falta ${campo}`);
    }
    if (!Array.isArray(p.scopes) || !p.scopes.length) throw new Error(`${clave}: scopes vacío`);
    for (const url of [p.authorize, p.token]) {
      if (!url.startsWith('https://')) throw new Error(`${clave}: ${url} no es https`);
    }
  }
});

console.log('\nEstado / aleatoriedad');

await t('el state del OAuth no se repite', () => {
  // El `state` es lo que ata el callback al pedido original. Si se repitiera,
  // se podría enganchar la respuesta de un cliente a la sesión de otro.
  const vistos = new Set();
  for (let i = 0; i < 500; i++) vistos.add(aleatorio(32));
  if (vistos.size !== 500) throw new Error(`${500 - vistos.size} repetidos de 500`);
});

await t('el state es url-safe (viaja en la query)', () => {
  for (let i = 0; i < 50; i++) {
    const s = aleatorio(32);
    if (/[+/=]/.test(s)) throw new Error(`"${s}" tiene caracteres que hay que escapar`);
    if (encodeURIComponent(s) !== s) throw new Error(`"${s}" cambia al ponerlo en una URL`);
  }
});

console.log(`\n${ok} pasaron, ${fail} fallaron\n`);
process.exit(fail ? 1 : 0);
