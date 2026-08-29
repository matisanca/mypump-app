/* fcm-flag.js — ¿este binario trae Firebase adentro?
 *
 * Existe por un crash muy específico. En Android, PushNotifications.register()
 * levanta "Default FirebaseApp is not initialized" EN EL HILO PRINCIPAL cuando
 * el APK no tiene google-services.json, y se lleva puesto el proceso: la app se
 * cierra sola, sin diálogo. Un try/catch de JavaScript NO lo atrapa, porque el
 * que revienta es el lado nativo. Por eso hasta hoy Android tenía el push
 * apagado con un `return null` a secas.
 *
 * Un `return null` fijo tiene el problema opuesto: el día que Firebase esté
 * configurado, hay que acordarse de sacarlo, y si no, el push sigue apagado en
 * silencio. Ya nos pasó tres veces esta semana con datos que se calculaban bien
 * y nadie consumía.
 *
 * Este flag lo decide el BUILD, no una persona: el paso "Marcar si hay Firebase"
 * de codemagic.yaml reescribe este archivo con `true` si y solo si
 * android/app/google-services.json existe en el momento de compilar. Si no
 * existe, queda en false y el guard sigue protegiendo.
 *
 * En la web siempre es false, y está bien: el navegador usa Web Push (VAPID),
 * que es otro camino y no depende de esto.
 */
window.MYPUMP_FCM = false;
