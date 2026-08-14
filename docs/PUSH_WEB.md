# Web Push — el paso que tenés que hacer vos, Mati

Todo el camino está construido y probado. Falta **una sola cosa**, y es la
única que no puedo hacer yo: generar el par de claves VAPID. La mitad privada
es una credencial, y las credenciales las manejás vos.

Son cinco minutos.

---

## Por qué importa esto

`mypump_push_devices` está **vacía**: cero dispositivos. Ninguno de tus 62
clientes puede recibir hoy una notificación. No es que el push esté roto — es
que el plugin nativo solo existe adentro de la app, y todos abren MyPump como
un link del navegador.

Web Push cubre justamente ese caso: **funciona en el navegador**, y de paso
cubre Android entero sin Firebase y sin esperar a que Google apruebe la cuenta.

Mientras no exista la clave, no se rompe nada: los avisos quedan guardados en
la cola con estado `sin_device` y salen solos el día que la configures.

---

## Los dos comandos

En la Mac mini:

```bash
~/agentkit-coach/venv/bin/python3 -c "
from py_vapid import Vapid01 as V
from cryptography.hazmat.primitives import serialization as S
import base64
v = V(); v.generate_keys()
pub = v.public_key.public_bytes(S.Encoding.X962, S.PublicFormat.UncompressedPoint)
raw = v.private_key.private_numbers().private_value.to_bytes(32, 'big')
print('PUBLICA :', base64.urlsafe_b64encode(pub).decode().rstrip('='))
print('PRIVADA :', base64.urlsafe_b64encode(raw).decode().rstrip('='))
"
```

> Este comando está probado en la mini tal cual está escrito. Dos detalles que
> hicieron falta y no son obvios: `public_bytes_uncompressed()` **no existe**
> en la versión de `cryptography` que hay instalada (hay que pasar por
> `X962` + `UncompressedPoint`), y `pywebpush` **rechaza la clave privada en
> PEM** — la quiere como los 32 bytes crudos en base64url, que además es lo
> único que entra prolijo en una línea de `.env`.

Te va a imprimir dos líneas: **PUBLICA** (87 caracteres, empieza con `B`) y
**PRIVADA** (43 caracteres).

### Dónde va cada una

| Cuál | Dónde | Se commitea |
|---|---|---|
| **Pública** | `public/js/config.js` → `VAPID_PUBLIC_KEY: '...'` | Sí. Viaja al navegador en cada suscripción; no sirve para mandar nada por sí sola. |
| **Privada** | el `.env` de la mini → `VAPID_PRIVATE_KEY=...` | **NUNCA.** Es la que firma. |

Para la privada, en la mini:

```bash
printf 'VAPID_PRIVATE_KEY=%s\n' "$(pbpaste)" >> ~/pump-centinela/.env
```

(o pegala a mano con `nano ~/pump-centinela/.env`)

**Tienen que ser del mismo par.** Si mezclás la pública de una tanda con la
privada de otra, el navegador rechaza cada envío con un `403` que no explica
nada.

---

## Cómo saber que quedó bien

```bash
ssh mini 'cd ~/pump-centinela && ~/agentkit-coach/venv/bin/python3 push.py'
```

- **Antes**: `sin VAPID_PRIVATE_KEY: los avisos web quedan en la cola`
- **Después**: esa línea desaparece.

Después, entrá a la app desde el navegador del teléfono, aceptá las
notificaciones, y mirá la cobertura:

```sql
SELECT * FROM mypump_push_cobertura();
```

Te devuelve cuántos clientes activos hay, cuántos tienen dispositivo, y cómo se
reparten por plataforma.

**Ese número es el semáforo de la Fase 3.** Por debajo de ~60% con dispositivo,
la ronda del domingo todavía necesita el respaldo por WhatsApp.

---

## Una trampa de iOS que conviene saber de antemano

En iPhone, Web Push **solo funciona si la app está agregada a la pantalla de
inicio**. Safari no deja suscribirse desde una pestaña común: no muestra ni el
cartel de permiso.

O sea que en iPhone hay dos caminos y ninguno es "abrir el link":

1. Descargar la app del App Store (lo que empuja el pop-up nuevo), **o**
2. Compartir → *Agregar a inicio*

En Android no: ahí Web Push anda desde una pestaña normal.

Por eso el pop-up de descarga y esto son la misma pelea, y por eso el pop-up
salió primero.

---

## Qué pasa si la clave se pierde o la rotás

Las suscripciones viejas quedan muertas: fueron creadas contra la pública
anterior. El sender las va a ver responder `403`, que **no** da de baja el
device (solo lo hacen 404 y 410), así que se van a reintentar 4 veces y quedar
en error.

Si alguna vez rotás las claves, hay que limpiar:

```sql
UPDATE mypump_push_devices SET activo = FALSE WHERE plataforma = 'web';
```

Cada cliente se re-suscribe solo la próxima vez que abre la app.
