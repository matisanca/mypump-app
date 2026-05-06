# Deploy de MyPump a producción

## Estado actual

- ✅ Código en GitHub: _pendiente — ver Paso 0_
- ✅ Branch principal: `main`
- ✅ Build: estático puro (sin build step)
- ✅ Folder a servir: `public/`
- ✅ Routing: `public/_redirects` mapea `/:token` → `/cliente.html`
- ✅ Config: `public/js/config.js` versionado con anon key pública

---

## Paso 0 — Subir el repo a GitHub (primera vez)

> Si ya hiciste esto, salteá a Paso 1.

**Opción A — con `gh` CLI** (más rápido):

```bash
cd /Users/matiassancari/Desktop/mypump-app
gh repo create mypump-app --public --source=. --remote=origin --push
```

**Opción B — manual:**

1. Andá a https://github.com/new
2. Nombre: `mypump-app` · Público o Privado (tu elección)
3. **NO** tildés "Initialize this repository" (ya tenemos archivos)
4. Click "Create repository"
5. Ejecutá en terminal:

```bash
cd /Users/matiassancari/Desktop/mypump-app
git remote add origin https://github.com/TU_USUARIO/mypump-app.git
git branch -M main
git push -u origin main
```

Reemplazá `TU_USUARIO` por tu usuario real de GitHub.

---

## Paso 1 — Crear proyecto en Cloudflare Pages (5 min)

1. Andá a https://dash.cloudflare.com → sidebar **"Workers & Pages"** → **"Create"**
2. Tab **"Pages"** → **"Connect to Git"**
3. Autorizá Cloudflare a leer tu GitHub (solo la primera vez)
4. Seleccioná el repo **`mypump-app`**
5. Configuración del build:

   | Campo | Valor |
   |-------|-------|
   | Project name | `mypump-app` |
   | Production branch | `main` |
   | Framework preset | **None** |
   | Build command | _(dejar **vacío**)_ |
   | Build output directory | `public` |

6. Click **"Save and Deploy"**
7. Esperá ~30 segundos al primer deploy
8. **Verificar**: abrí la URL temporal:
   ```
   https://mypump-app.pages.dev/test-001
   ```
   Debería cargar la pantalla de MyPump (aunque el token test-001 no tenga cliente real, la app carga).

> ⚠️ Si ves pantalla en blanco: abrí DevTools console y verificá que no hay error de Supabase.

---

## Paso 2 — Agregar dominio personalizado en Cloudflare (3 min)

1. En el proyecto `mypump-app` recién creado → tab **"Custom domains"**
2. Click **"Set up a custom domain"**
3. Ingresá: **`app.mypumpteam.com`**
4. Cloudflare mostrará un registro CNAME. Anotá el valor, va a ser algo como:
   ```
   mypump-app.pages.dev
   ```
5. (Completá el DNS en Paso 3 y volvé acá a confirmar)

---

## Paso 3 — Configurar DNS en GoDaddy (5 min)

> Solo configuramos el **subdomain** `app`. El WordPress en `mypumpteam.com` no se toca.

1. Andá a https://dcc.godaddy.com → seleccioná `mypumpteam.com`
2. Menú **DNS** → **"Manage Zones"**
3. Click **"Add"** (o el botón de agregar registro)
4. Completá así:

   | Campo | Valor |
   |-------|-------|
   | Type | **CNAME** |
   | Name | **`app`** (solo `app`, sin el dominio) |
   | Value | el valor que te dio Cloudflare en Paso 2 |
   | TTL | 1 hora (o default) |

5. **Save**

---

## Paso 4 — Esperar propagación DNS (5–30 min)

DNS puede tardar hasta 30 minutos. Para verificar en cualquier momento:

```bash
nslookup app.mypumpteam.com
# o
dig app.mypumpteam.com
```

Cuando devuelva una IP de Cloudflare (rango `172.66.x.x`, `104.x.x.x` u otro de CF), está listo.

---

## Paso 5 — Verificación end-to-end

1. Abrí **`https://app.mypumpteam.com/test-001`** (token de ejemplo)
2. Verificá que carga sin errores de consola
3. Andá a **Cerebro** → elegí un cliente con trainPlan + dieta → **"Publicar a MyPump"**
4. Copiá el link generado → abrilo en el browser
5. Si el plan del cliente carga correctamente = **INTEGRACIÓN COMPLETA ✅**

---

## Mantenimiento

- Cada `git push origin main` → Cloudflare **auto-deploya en ~30 segundos**.
- Sin costos extras: Cloudflare Pages free tier cubre este uso de sobra.
- `mypumpteam.com` (sin subdomain) sigue intacto en su WordPress original.

---

## Troubleshooting

| Síntoma | Causa probable | Solución |
|---------|---------------|----------|
| 404 en Cloudflare | `_redirects` no aplicado | Verificar que `public/_redirects` existe y está commiteado |
| Pantalla en blanco | Error Supabase URL/key | Abrir DevTools console · Verificar `public/js/config.js` |
| DNS no resuelve | Propagación pendiente | Esperar más · ejecutar `dig app.mypumpteam.com` |
| "Token inválido" en la app | access_token revocado | Supabase Dashboard → tabla `mypump_clientes` → `access_token_active = true` |
| CORS error | URL de Supabase incorrecta | Verificar `SUPABASE_URL` en `config.js` |
