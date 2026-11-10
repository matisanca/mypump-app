// Postgres 17 embebido (PGlite) para las pruebas: nada de esto toca la base real.
// Uso: node pg_prueba.mjs <puerto> <sql de la propuesta>   → queda escuchando; imprime LISTO.
import { PGlite } from '@electric-sql/pglite';
import { PGLiteSocketServer } from '@electric-sql/pglite-socket';
import fs from 'node:fs';

const [puerto, propuesta] = process.argv.slice(2);
const db = await PGlite.create();
// Lo mínimo de la base real que la propuesta espera encontrar.
await db.exec(`
  CREATE ROLE anon NOLOGIN; CREATE ROLE authenticated NOLOGIN; CREATE ROLE service_role NOLOGIN;
  CREATE TABLE public.mypump_clientes (id UUID PRIMARY KEY DEFAULT gen_random_uuid(), cliente_id TEXT UNIQUE, nombre TEXT,
    access_token TEXT UNIQUE, access_token_active BOOLEAN DEFAULT true);
  CREATE TABLE public.onboarding_leads (id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY, nombre TEXT, apellido TEXT, email TEXT,
    whatsapp TEXT, plan TEXT, tipo TEXT, va_a_usar_farma BOOLEAN, payload JSONB, linked_client_id TEXT, created_at TIMESTAMPTZ DEFAULT now());
`);
await db.exec(fs.readFileSync(propuesta, 'utf8'));
const server = new PGLiteSocketServer({ db, port: Number(puerto), host: '127.0.0.1' });
await server.start();
console.log('LISTO');
process.on('SIGTERM', async () => { await server.stop(); await db.close(); process.exit(0); });
