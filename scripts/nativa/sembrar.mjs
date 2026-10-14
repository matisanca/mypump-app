#!/usr/bin/env node
/* =============================================================
   sembrar.mjs — cuentas de prueba de las apps nativas

   Envuelve scripts/seed-cliente.mjs con lo que las cuentas de la nativa necesitan:

   - **Token aleatorio de 32 caracteres.** El de seed-cliente es fijo por escenario
     (BANCO_<ESC>_TOKEN) y access_token es UNIQUE: dos cuentas del mismo escenario se
     pisarían el token.
   - **Ids fuera de lo que borra scripts/cleanup-test-data.sql** (test-banco-% y banco-%),
     porque otras sesiones lo corren y estas cuentas tienen que durar semanas.
     - Invisible: `test-nativa-<cuenta>`. El centinela, el Radar y la IA ignoran los `test%`.
     - Visible (para el chat): `nativa-<cuenta>`, con "test" en el nombre para que el
       centinela no la analice, pero con chat en el Cerebro.

   El plan (rutina y dieta) necesita rol `authenticated`: se aplica en la mini con
   ~/_aplicar.py. La historia va por las RPC reales, como en seed-cliente.

   Los tokens quedan en ~/Developer/nativa-evidencia/privado/cuentas-prueba.json, fuera del repo.

   Uso:
     node scripts/nativa/sembrar.mjs --cuenta ios --escenario en-ritmo
     node scripts/nativa/sembrar.mjs --cuenta tester --escenario en-ritmo --visible
     node scripts/nativa/sembrar.mjs --listar
   ============================================================= */

import { execFileSync } from 'node:child_process';
import crypto from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const RAIZ = path.join(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const REGISTRO = path.join(os.homedir(), 'Developer', 'nativa-evidencia', 'privado', 'cuentas-prueba.json');

const A = process.argv.slice(2);
const flag = (n) => A.includes(n);
const val = (n, d) => { const i = A.indexOf(n); return i >= 0 && A[i + 1] ? A[i + 1] : d; };

const leerRegistro = () => (fs.existsSync(REGISTRO) ? JSON.parse(fs.readFileSync(REGISTRO, 'utf8')) : {});
const guardarRegistro = (r) => {
  fs.mkdirSync(path.dirname(REGISTRO), { recursive: true });
  fs.writeFileSync(REGISTRO, JSON.stringify(r, null, 2), { mode: 0o600 });
};

if (flag('--listar')) {
  const r = leerRegistro();
  for (const [id, c] of Object.entries(r)) console.log(`${id.padEnd(28)} ${c.escenario.padEnd(22)} ${c.visible ? 'visible' : 'invisible'}  ${c.creada}`);
  process.exit(0);
}

const CUENTA = val('--cuenta');
if (!CUENTA || !/^[a-z0-9-]{2,30}$/.test(CUENTA)) {
  console.error('✗ falta --cuenta <nombre> (minúsculas, números y guiones)');
  process.exit(2);
}
const ESCENARIO = val('--escenario', 'en-ritmo');
const VISIBLE = flag('--visible');
const CLIENTE_ID = VISIBLE ? `nativa-${CUENTA}` : `test-nativa-${CUENTA}`;
const NOMBRE = VISIBLE ? `Tester Nativa ${CUENTA}` : `Test Nativa ${CUENTA}`;

function tokenAleatorio() {
  const alfabeto = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
  const bytes = crypto.randomBytes(64);
  let t = '';
  for (const b of bytes) {
    if (b < 248) t += alfabeto[b % 62];   // 248 = 4 × 62: sin sesgo
    if (t.length === 32) break;
  }
  return t;
}

const registro = leerRegistro();
const TOKEN = registro[CLIENTE_ID]?.token || tokenAleatorio();

const seed = (...extra) => execFileSync(process.execPath, [
  path.join(RAIZ, 'scripts', 'seed-cliente.mjs'),
  '--escenario', ESCENARIO, '--cliente', CLIENTE_ID, '--token', TOKEN, '--nombre', NOMBRE, ...extra,
], { cwd: RAIZ, stdio: ['ignore', 'pipe', 'inherit'] }).toString();

// 1. El plan, como SQL, aplicado en la mini (COMMIT).
seed('--solo-sql');
const sqlLocal = path.join(RAIZ, 'scripts', `.plan-${ESCENARIO}.sql`);
const sqlRemoto = `/tmp/nativa-plan-${CLIENTE_ID}.sql`;
execFileSync('scp', ['-q', sqlLocal, `mini:${sqlRemoto}`], { stdio: 'inherit' });
const aplicado = execFileSync('ssh', ['mini', `~/agentkit-coach/venv/bin/python3 ~/_aplicar.py ${sqlRemoto} && rm -f ${sqlRemoto}`]).toString();
fs.rmSync(sqlLocal, { force: true });
console.log(`▸ plan de ${CLIENTE_ID} aplicado en la base`);
if (/error/i.test(aplicado)) console.log(aplicado);

// 2. La historia por las RPC reales.
const salida = seed('--aplicar');
const resumen = salida.split('\n').find((l) => l.includes('sesiones ·'));
console.log(`▸ historia: ${resumen ? resumen.trim() : '(ver salida de seed-cliente)'}`);

registro[CLIENTE_ID] = {
  token: TOKEN, escenario: ESCENARIO, visible: VISIBLE, nombre: NOMBRE,
  creada: registro[CLIENTE_ID]?.creada || new Date().toISOString(), resembrada: new Date().toISOString(),
};
guardarRegistro(registro);
console.log(`✓ ${CLIENTE_ID} lista. El token quedó en ${REGISTRO.replace(os.homedir(), '~')} (no se imprime).`);
