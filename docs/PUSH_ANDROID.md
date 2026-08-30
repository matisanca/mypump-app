# Push en Android — qué falta para prenderlo

Todo el código está escrito y probado. Faltan **dos credenciales**, y cada una
prende un camino distinto. No son alternativas: hacen falta las dos, porque
cubren a gente distinta.

| Camino | A quién le llega | Qué falta |
|---|---|---|
| **Web Push (VAPID)** | Todos los que usan la PWA desde Chrome — **hoy, los 62** | 1 par de claves |
| **FCM** | Los que instalen la app nativa desde Play | Proyecto Firebase + cuenta de servicio |

El WebView de la app instalada **no implementa la Push API**, así que Web Push no
la cubre. Y el navegador no puede usar FCM. Por eso van las dos.

---

## 1. Web Push — cubre a todos los clientes de hoy

Es el que más impacto tiene y el más corto.

```bash
npx web-push generate-vapid-keys
```

Devuelve dos claves.

- La **pública** va en `public/js/config.js`, en `VAPID_PUBLIC_KEY`. Es pública
  de verdad: viaja al navegador de cada cliente. Se commitea.
- La **privada** va en el `.env` de la mini como `VAPID_PRIVATE_KEY`. **No se
  commitea nunca.**

```
VAPID_PRIVATE_KEY=...
VAPID_SUBJECT=mailto:info@mypumpteam.com
```

Listo. `push.py` lo levanta en la corrida siguiente y los avisos que quedaron en
la cola salen solos — no se pierden mientras la clave no está.

## 2. FCM — cubre la app nativa

1. **Crear el proyecto** en console.firebase.google.com. Agregar una app
   Android con el package exacto **`com.pumpteam.mypump`**.
2. **Bajar `google-services.json`** y ponerlo en `android/app/`. Se commitea:
   no es un secreto, va adentro del APK igual.
3. **Cuenta de servicio**: Configuración del proyecto → Cuentas de servicio →
   "Generar nueva clave privada". Ese JSON **sí es secreto**. Va a la mini
   (fuera del repo) y se apunta desde el `.env`:

```
FCM_SA_PATH=/Users/matiassancari/pump-centinela/fcm-service-account.json
FCM_PROJECT_ID=el-id-del-proyecto-firebase
```

4. Taggear un build. El push nativo se prende **solo**: el paso "Marcar si el
   binario lleva Firebase" detecta el `google-services.json` y escribe el flag.

---

## Por qué esto no se puede volver a apagar en silencio

Android estuvo sin push durante meses y no había un error en ningún lado. Dos
huecos, los dos mudos:

**En el binario.** `notificaciones.js` tenía `if (android) return null` con un
comentario que decía "para prenderlo, sacar estas tres líneas". Dependía de que
alguien se acordara. Existía por una razón real: sin `google-services.json`,
`PushNotifications.register()` levanta *"Default FirebaseApp is not
initialized"* **en el hilo nativo** y mata el proceso — la app se cierra sola,
sin diálogo. Un `try/catch` de JavaScript no lo atrapa.

Ahora lo decide el build. `fcm-flag.js` se reescribe con `true` si y solo si
`google-services.json` estaba presente al compilar. Si aparece, se prende solo;
si se pierde, se apaga solo. Y no puede crashear.

**En el servidor.** `push.py` devolvía `"android/FCM todavia no implementado"` y
nadie lo veía. Ahora cada corrida imprime qué transporte está vivo:

```
transportes: APNs ok · web APAGADO · FCM APAGADO
  sin VAPID_PRIVATE_KEY: los avisos web quedan en la cola
  sin FCM_SA_PATH/FCM_PROJECT_ID: los avisos del Android nativo quedan en la cola
```

Un transporte apagado no es un error —es una config que falta— pero **no puede
ser invisible**, que fue exactamente el problema.

`scripts/test_push_android.py` falla si alguna de las dos puntas se vuelve a
apagar. Verificado con tres mutantes: reponer el `return null` fijo, commitear
el flag en `true`, o desenchufar el router de FCM.

## Un detalle del envío que importa

FCM manda **`notification` y `data` juntos**. El primero es lo que hace que el
aviso se vea; el segundo lleva el `destino` para que el tap abra la pantalla
correcta.

> **Esto decía lo contrario hasta el 29-ago, y estaba mal.** La versión vieja
> mandaba solo `data`, con este argumento: "con `notification` el tap no puede
> llevar al chat". Es falso, y se llevaba puesta la feature entera.
>
> El plugin de Capacitor postea la notificación **únicamente** adentro de
> `if (notification != null)` (`PushNotificationsPlugin.java:246-282`, la única
> llamada a `notificationManager.notify()` que tiene). Con data-only ese bloque
> es `null` y no entra nunca: lo único que hace es emitir
> `pushNotificationReceived` (`:296`), un evento que en toda la app **no
> escucha nadie**.
>
> Y FCM contesta `200` igual, porque aceptó el mensaje para entrega. Así que
> `enviar_fcm` devolvía éxito, el ledger lo anotaba como entregado, y el
> Cerebro iba a mostrar avisos que en el teléfono nunca aparecieron.
>
> El miedo al deep link no tenía fundamento: `handleOnNewIntent` (`:58-77`)
> vuelca **todas** las claves del intent —`destino` incluido— adentro de
> `notification.data`, y recién ahí dispara `pushNotificationActionPerformed`,
> que es el listener que sí existe en `notificaciones.js`.
>
> Lo cubre `scripts/test_push_android.py`, y el arreglo es **server-side**: no
> hizo falta binario nuevo.

**No se declara `channel_id`.** Si se nombra un canal que la app no creó,
Android 8+ descarta la notificación en silencio. Sin el campo, FCM usa su canal
de respaldo, que siempre existe.

Y va con `priority: high`. Sin eso, Doze puede demorar el aviso de la ronda del
domingo hasta la mañana siguiente.
