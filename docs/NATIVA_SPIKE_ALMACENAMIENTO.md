# Prueba del almacenamiento viejo (riesgo n.º 1)

**Pregunta:** ¿la app nativa, publicada como update del mismo `com.pumpteam.mypump`, puede leer lo que la app
Capacitor dejó en el `localStorage` del WebView? Si no pudiera, haría falta una actualización puente de la Capacitor,
y eso toca código compartido con la web.

**Respuesta en iOS 17.5, 18.6 y 26.5:** sí, por dos caminos independientes, byte a byte y en las dos direcciones.

> **Ojo, en un iPhone de verdad la ruta es otra (TF-0, 14-oct, iOS 27.0).** El simulador guarda en
> `Library/WebKit/<bundle>/WebsiteData/…`; el iPhone, en `Library/WebKit/WebsiteData/…`, sin el bundle. Todo lo de
> abajo se probó en el simulador, y la Ruta B de la 2.0.0 (100) armaba la ruta del simulador: en el iPhone no encontró
> nada. Desde bb5bcfc el lector recorre todo `Library/WebKit` y reconoce el origen por su archivo `origin` (el formato
> del archivo y de la base es el mismo). La Ruta A, el WebView, no depende de la ruta.

## Cómo se probó (simulador "Nativa 17 (26.5)", 14-oct-2026)

1. Se compiló la Capacitor de `main` (su configuración de WebView, Info.plist, entitlements y SPM es idéntica a la de
   `v1.0.11` y `v1.0.12-b18`: `git diff` vacío salvo la versión en `package.json`).
2. Se entró a la demo y se cambió el tema y el día. Así la app escribió su `localStorage` de forma natural.
3. **Verdad de base:** con la app cerrada se sembraron en el mismo archivo los casos que no se producen a mano. Lo
   hace `scripts/nativa/legado_sqlite.py semilla/sembrar`:
   - token;
   - outbox de **500 operaciones** con los 9 kinds;
   - cola huérfana de otro token y cola `anon`;
   - cola de fotos;
   - sustituciones fijadas y sin `fijado`;
   - sesión y descanso en curso;
   - preferencias;
   - un valor de **1 MB**;
   - una clave unicode y un valor con un `\0` adentro.
   
   Quedaron 21 claves, unos 2,3 MB en UTF-16.
4. Se instaló encima la espía `apps/ios/Spike` con el mismo bundle id (`simctl install` = update real: conserva el
   contenedor). La espía lee por las dos rutas, compara y escribe una marca de vuelta.

## Resultados

| Prueba | Resultado |
|---|---|
| Ruta A (WKWebView en `capacitor://localhost` + `WKURLSchemeHandler`), **con** `WKAppBoundDomains` + `limitsNavigationsToAppBoundDomains` | ✅ 21/21 claves, idénticas a la verdad |
| Ruta A **sin** app-bound domains | ✅ idéntico (25/25 después de la vuelta) |
| Ruta B (lectura directa del SQLite) | ✅ idéntico |
| Escritura de vuelta (`callAsyncJavaScript`) | ✅ en el segundo arranque, la Ruta B la lee **desde el disco** |
| Vuelta atrás: Capacitor reinstalada encima de la espía (camino del plan B) | ✅ ve la marca de la nativa y su outbox intacto, y sigue escribiendo en el mismo archivo |

### iOS 17.5 y 18.6 (14-oct, `scripts/nativa/spike-legado.sh`, sin tocar la pantalla)

El script instala la Capacitor de `main`, la abre para que escriba su `localStorage`, siembra la verdad con la app
cerrada (20 claves), instala la espía encima sin app-bound domains y la arranca dos veces.

| iOS | Ruta A | Ruta B | Marca de vuelta en el 2.º arranque |
|---|---|---|---|
| 17.5 (iPhone 15) | ✅ 20/20 | ✅ 20/20 | ✅ leída del disco por la Ruta B |
| 18.6 (iPhone 16) | ✅ 20/20 | ✅ 20/20 | ✅ |

La ruta del archivo es la misma que en 26.5 (`WebsiteData/Default/<hash>/<hash>/LocalStorage/`).

## Lo que se aprendió

- **Ruta en iOS 17+:**
  `Library/WebKit/com.pumpteam.mypump/WebsiteData/Default/<hash>/<hash>/LocalStorage/localstorage.sqlite3`.
  - Al lado hay un archivo `origin` con dos orígenes (el de arriba y el del frame), los dos `capacitor://localhost`.
  - El hash depende de `Default/salt`: se identifica leyendo `origin`, no recalculando.
- **Lo reciente vive en el `-wal`.** Con la app ya cerrada, el `.sqlite3` tenía 4 KB vacíos y el `-wal` 37 KB con todo.
  Leer solo el archivo principal da **cero claves**. La Ruta B copia db + wal + shm y abre la copia.
- **Esquema:** `ItemTable(key TEXT UNIQUE, value BLOB)`, con el valor en **UTF-16LE**.
- La carpeta del formato anterior (`WebsiteData/LocalStorage/`) existe pero está vacía en una instalación limpia de
  iOS 26. Un iPhone que viene de iOS ≤16 sin abrir MyPump desde entonces puede tener
  `capacitor_localhost_0.localstorage` ahí. La Ruta B lo busca.
- **En el simulador, el UUID de la carpeta del contenedor cambia al reinstalar, pero el contenido se conserva.** No hay
  que guardar rutas absolutas.
- La app final **no necesita declarar `WKAppBoundDomains`**: la Ruta A funciona igual sin él.
- El `.pbxproj` escrito a mano con carpetas sincronizadas (objectVersion 77) compila con Xcode 26.6 y Swift 6. Es el
  mismo enfoque que va a usar `apps/ios/MyPump`.

## Android (14-oct, `scripts/nativa/spike-legado-android.sh`, emulador Android 16 / WebView 133)

**Funciona por la ruta A.** El procedimiento:
1. Se instala la Capacitor de debug compilada de `main` (Capacitor 8.5; `androidScheme` por defecto, así que el origen
   es `https://localhost`).
2. Con la app viva se siembra la misma semilla que en iOS por el protocolo de DevTools (`scripts/nativa/cdp-localstorage.mjs`).
3. Se cierra la app y se vuelve a leer desde ella misma: esa es la verdad, lo que quedó en disco.
4. Se instala encima la espía (`apps/android-spike`): mismo paquete, misma firma de debug, update real.

| Corrida | Espera antes del cierre forzado | Arranque 1 (lee) | Arranque 2 (marca de la espía) |
|---|---|---|---|
| 1 | 10 s | 21/21 iguales | sobrevivió |
| 2 | 3 s | 23/23 iguales | sobrevivió |
| 3 | 1 s | 23/23 iguales | sobrevivió |

**Lo que se aprendió:**
- Alcanza un `WebView` con `javaScriptEnabled` y `domStorageEnabled`, el almacén por defecto (sin sufijo de directorio),
  una página servida por la propia app en `https://localhost` (`shouldInterceptRequest`) y `evaluateJavascript`. No hace
  falta ningún puente: el JSON vuelve en el callback.
- Leer las 23 claves (más de 1 MB de valores) tarda 5-9 s en el emulador, contando el arranque del WebView. Se hace
  una sola vez, en el primer arranque.
- La marca escrita desde el WebView nativo sobrevive a un cierre forzado 1 s después. Igual se confirma en el arranque
  siguiente, como en iOS.
- El WebView lo provee el sistema y es el mismo para las dos apps en el mismo teléfono: si migra su almacenamiento
  entre versiones, lo migra para la nativa también. Lo que rompería todo es cambiar el origen (otro `androidScheme`) o
  el directorio de datos. La app nativa no debe hacer ninguna de las dos cosas.
- La ruta B (leer el LevelDB directo) no hace falta en Android. Las colas y los cachés se leen con la A, y la
  confirmación de la escritura es otra lectura por la A.

### La migración de verdad (14-oct, `scripts/nativa/emu-migracion.sh`, emulador Android 16 / WebView 133)

La 2.0.0 (100) de debug encima de la Capacitor 1.0.12 (18) de debug, compilada de `android/` sin tocarlo
(`compilar-capacitor-android.sh`), con la cuenta `test-nativa-android` y sin tocar la pantalla:

1. Capacitor sin cuenta: por DevTools, el token y una cola chica. Con red, la Capacitor manda ella esa cola (el formato
   es el de la web) y deja su sesión del día y su copia offline.
2. Sin red y con la web estacionada en `/manifest.json` (mismo origen, sin scripts): una cola de 8 ops (5 kinds; 2 sin
   sesión, una de un día que ya no existe; 2 sin `_id`), una cola anon, una de un token rotado, el descanso, ajustes,
   1 MB, unicode, un `\0` y un surrogate suelto. 18 claves.
3. La nativa encima (misma clave de debug: update real), con red. Después un segundo y un tercer arranque, y la
   Capacitor otra vez encima (plan B).

| Qué | Resultado (corrida 5554, `nativa-evidencia/migracion-android/20261014-153011`) |
|---|---|
| Fase L | token adoptado, cola 6, por validar 2, estacionadas 1, anon 1: 18 claves leídas en ~1 s (con el 1 MB) |
| Fase R | cola 1, para revisar 1 (el día que no existe), no resuelve 1 (el token rotado), **recibo confirmado** |
| Escritura de vuelta | borrada 4 (la cola y los 3 cachés de sesión), marca ok; ya estaba en el leveldb al mirarlo |
| Segundo arranque | **escritura confirmada 1**, nada nuevo (ya en el libro 2); la base, igual |
| Tercer arranque | la Fase L no corre: la huella quedó quieta |
| La base | las 3 series, el estado, el agua, el peso y el check llegaron una vez; la anon y la rotada, nunca |
| Plan B | la Capacitor ve la marca, sin su cola ni sus sesiones; la anon, la rotada, el 1 MB, el unicode y el surrogate siguen; con red no resucita nada |

Del arranque a la escritura de vuelta: 6 s. 24/24 chequeos en el informe.

**Lo que se aprendió (y quedó en el código):**
- El leveldb está en `app_webview/Default/Local Storage/leveldb`; en WebView viejos, en `app_webview/Local
  Storage/leveldb`. La app no arma la ruta: recorre `app_webview*` (`LevelDbLegado`, con tests de las dos).
- La página se carga con `loadDataWithBaseURL` en `https://localhost`: el documento toma el origen sin pedirlo, así que
  no pasa por el service worker que registró la web (`sw.js`). Ojo: el WebView pasa esa carga por
  `shouldInterceptRequest` como `data:`; contestarla deja el documento en `chrome-error://` sin `localStorage`.
- Una ruta que no existe en la Capacitor (`/__x.txt`) también termina en `chrome-error://`: para estacionar la web hay
  que ir a un archivo estático.
- Chromium baja el `localStorage` en tandas y espacia las bajadas según cuántas ya hizo el proceso. En un proceso nuevo
  (la nativa al arrancar) llegó enseguida; en la prueba instrumentada, con varias escrituras previas en el mismo
  proceso, la escritura de vuelta no estaba en el disco a los 15 s. Por eso se confirma en el arranque siguiente.
- `evaluateJavascript` pasa los textos a UTF-8: un surrogate suelto llegaría roto. La lectura firma cada valor en
  JavaScript y devuelve JSON en ASCII (`\uXXXX`) por tramos; del lado de Kotlin la firma recalculada tiene que dar igual.
- Entreno (Android e iOS) restaura el descanso que trajo la migración y DESPUÉS cambia al día que se veía en la
  Capacitor; `cambiarDia` lo detiene. La sesión llega bien; el descanso en curso se pierde si los días no coinciden.

## Lo que falta

- [x] iOS 17.5 y 18.6: idéntico (ver tabla).
- [ ] Matar la app justo después de la escritura de vuelta, para medir si se pierde. El diseño ya la confirma en el
  arranque siguiente con la Ruta B.
- [ ] Datos reales de una cuenta de prueba (`test-nativa-ios`, ya sembrada) escritos por la Capacitor con red, en el
  formato de `v1.0.11`.
- [x] Android: `WebView` en `https://localhost` + `shouldInterceptRequest` (ver la sección de Android). La verdad
  sale de la propia Capacitor después de un cierre, no del LevelDB: es lo mismo que ve ella.
- [x] Android: la migración de punta a punta en el emulador (Fase L, Fase R, recibo, escritura de vuelta confirmada,
  plan B), ver arriba.
- [ ] Android con datos reales de la versión de Play (1.0.12) en un teléfono físico.
- [ ] En un iPhone real, actualizando desde la versión de la tienda (Hito TF-0).

Evidencias: `~/Developer/nativa-evidencia/spike/` (verdad sembrada, informes de cada corrida y captura de la vuelta).
