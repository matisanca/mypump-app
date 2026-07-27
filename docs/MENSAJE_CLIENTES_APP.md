# Mensajes para pasarle la app al cliente

> Copiar/pegar en WhatsApp. El link personal de cada cliente sale del Cerebro
> (ficha del cliente → link de MyPump). Reemplazar `LINK_DEL_CLIENTE`.

## 1. Cliente nuevo (primera vez)

```
Te dejo tu acceso a MyPump 💪

LINK_DEL_CLIENTE

Bajate la app y entrás más rápido: https://apps.apple.com/ar/app/mypump/id6793259380
Si al abrirla te pide el link, pegá el de arriba.
```

## 2. Cliente que ya usa la web y querés pasar a la app

```
Ya está MyPump en la App Store 🎉
https://apps.apple.com/ar/app/mypump/id6793259380

Bajala y pegá tu link de siempre la primera vez. Después entrás directo.
```

## 3. "Bajé la app y no puedo entrar"

```
Abrí la app y abajo de todo tenés "¿Ya tenés tu link de acceso?".
Pegá ahí el link que te pasé y listo, queda guardado 👍
```

---

## Por qué el link no siempre abre la app solo

La app tiene Universal Links: tocando el link, iOS abre MyPump si está
instalada. Pero **WhatsApp abre los links en su propio navegador interno**, y
ahí iOS no dispara el Universal Link — cae en la web igual. Por eso el mensaje
menciona el campo para pegar el link: es el camino que funciona siempre.

Si el cliente mantiene apretado el link y elige "Abrir en Safari", ahí sí salta
a la app.

Una vez que entró (por el camino que sea), el token queda guardado y abre
directo: no vuelve a necesitar el link.
