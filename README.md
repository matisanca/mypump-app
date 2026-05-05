# MyPump

Página pública de clientes de Pump Team. Cada cliente recibe un link único (`app.mypumpteam.com/TOKEN`) que abre su rutina de entrenamiento, dieta personalizada y registro de cargas. Sin login, sin cuentas: el acceso es exclusivamente por token en la URL.

## Stack

- **Frontend**: Vanilla JS + HTML + CSS (sin frameworks)
- **Backend**: Supabase (PostgreSQL + RPC functions + RLS)
- **Deploy**: Cloudflare Pages en `app.mypumpteam.com`
- **Integración**: Cerebro de Pump Team publica via `mypump_publicar_cliente()`

---

## Setup local

### 1. Instalar dependencias del dev server

```bash
npm install   # opcional — solo instala npx serve
```

### 2. Configurar credenciales de Supabase

1. Ir al [dashboard de Supabase](https://supabase.com/dashboard/project/gydinputrtptqakdzyvc)
2. **Settings → API → Project API keys → anon public**
3. Copiar esa key y pegarla en `public/js/supabase-client.js`:

```js
const SUPABASE_ANON_KEY = 'PEGAR_ACÁ';
```

> La `anon key` es segura para exponer en el frontend. Las tablas tienen RLS habilitado
> y todo acceso de clientes pasa por RPC functions que validan el token.

### 3. Levantar el server local

```bash
npm run dev
# → http://localhost:3000
```

### 4. Testear con un cliente real

Para testear el flujo completo necesitás una fila en `mypump_clientes`.
Podés insertar una de prueba directamente en el SQL Editor de Supabase:

```sql
INSERT INTO mypump_clientes (cliente_id, nombre, perfil, access_token)
VALUES ('test-001', 'Matías Sancari', 'natural', 'TOKEN_DE_PRUEBA_32CHARS_ACÁ');
```

Luego abrir: `http://localhost:3000/TOKEN_DE_PRUEBA_32CHARS_ACÁ`

Si la conexión funciona, vas a ver:
```
✓ Cliente válido: Matías Sancari (natural)
```

---

## Aplicar la migration en Supabase

1. Ir a [SQL Editor](https://supabase.com/dashboard/project/gydinputrtptqakdzyvc/sql/new)
2. Pegar el contenido de `supabase/migrations/001_mypump_schema.sql`
3. Click **Run**

Esto crea 6 tablas + RLS + 9 RPC públicas + 3 RPC admin + grants.

---

## Deploy a Cloudflare Pages

Pendiente — ver `docs/DEPLOY.md`.

---

## Estructura

```
public/
├── index.html          Landing del subdominio (no es la página del cliente)
├── cliente.html        Página del cliente (token en la URL)
├── css/
│   ├── tokens.css      Design system: variables CSS
│   ├── base.css        Reset + tipografía + estilos base
│   └── components.css  Componentes (Prompt 2)
├── js/
│   ├── supabase-client.js  window.mypumpDB — acceso a Supabase via RPC
│   ├── theme.js            window.mypumpTheme — toggle light/dark
│   └── app.js              Lógica de cliente (Prompt 2)
├── assets/             Logo, íconos, etc.
└── _redirects          Routing para Cloudflare Pages

supabase/migrations/
└── 001_mypump_schema.sql

docs/
├── ARCHITECTURE.md     Diagrama de arquitectura
└── DEPLOY.md           Guía de deploy (pendiente)
```
