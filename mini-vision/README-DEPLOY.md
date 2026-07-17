# mini-vision — Deploy en la Mac mini (pasos de Mati)

Servicio de visión para MyPump (F7 escanear etiqueta / F10 foto del plato).
Corre `codex exec` con TU cuenta de ChatGPT (créditos de cuenta, sin API key).
Un solo archivo, sin dependencias: `server.mjs` (Node 18+).

## 1. Requisitos en la Mini (una vez)
```bash
# Codex CLI instalado y logueado con tu cuenta de ChatGPT:
npm install -g @openai/codex
codex login          # abre el browser → entrás con tu cuenta de OpenAI/ChatGPT
codex exec --skip-git-repo-check "decí hola"   # smoke test: debe responder
```

## 2. Subir el servicio (desde tu Mac, como siempre por scp)
```bash
scp -r "/Users/matiassancari/Desktop/💻 Software y Web (Pump)/mypump-app/mini-vision" usuario@LA_MINI:~/mini-vision
```

## 3. Arrancarlo y dejarlo corriendo (en la Mini)
Con pm2 (si ya lo usás para el bot) o launchd. Con pm2:
```bash
cd ~/mini-vision
pm2 start server.mjs --name mini-vision
pm2 save
```
Escucha en el puerto **8791** (cambiable con `PORT=`).

Smoke test local en la Mini:
```bash
curl -s http://localhost:8791/health
# → {"ok":true,"service":"mini-vision"}
```

## 4. Exponerlo con HTTPS
En el reverse proxy que ya usás para bot.mypumpteam.com / claude-proxy
(Caddy/nginx/cloudflared), agregá el subdominio **vision.mypumpteam.com →
localhost:8791**. Ejemplo Caddy:
```
vision.mypumpteam.com {
    reverse_proxy localhost:8791
}
```
(+ el registro DNS de `vision` apuntando igual que `bot`.)

## 5. Probar de punta a punta
```bash
curl -s https://vision.mypumpteam.com/health
```
Y desde la app: Dieta → sustituir un alimento → "Crear alimento" → botón
**"📷 Escanear etiqueta"** con una foto de una tabla nutricional.

## Seguridad / notas
- Autentica con el **token del cliente de MyPump** (se valida contra Supabase);
  no hay secretos en el frontend.
- Rate limit: 20 fotos por cliente por día (en memoria; se resetea al reiniciar).
- La imagen se guarda como archivo temporal y se BORRA al terminar cada pedido.
- Si algo falla, el front muestra el error y el cliente puede cargar a mano.
- Logs: `pm2 logs mini-vision`.
