# Deploy de MyPump

## Estado

**Pendiente** — se completa después de configurar el dominio en GoDaddy.

## TODOs

- [ ] Crear proyecto en Cloudflare Pages apuntando a este repo (`matiassancari/mypump-app`)
- [ ] Configurar build: directorio de publicación = `public`, sin build command
- [ ] Agregar dominio custom `app.mypumpteam.com` en Cloudflare Pages
- [ ] Configurar el registro DNS en GoDaddy (CNAME → `pages.dev`)
- [ ] Inyectar `SUPABASE_ANON_KEY` como variable de entorno en Cloudflare Pages
  - Settings → Environment variables → `SUPABASE_ANON_KEY`
  - Actualizar `supabase-client.js` para leer de la variable en build time (o hardcodear la anon key — es pública por diseño)
- [ ] Verificar que `_redirects` funciona correctamente con el routing de tokens

## Notas

- La `anon key` de Supabase es segura para exponer en el frontend. RLS + RPC previenen cualquier acceso no autorizado.
- Cloudflare Pages no ejecuta JS server-side: el build es puramente estático.
- El archivo `_redirects` maneja el routing SPA para los tokens.
