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

## Lo que falta

- [x] iOS 17.5 y 18.6: idéntico (ver tabla).
- [ ] Matar la app justo después de la escritura de vuelta, para medir si se pierde. El diseño ya la confirma en el
  arranque siguiente con la Ruta B.
- [ ] Datos reales de una cuenta de prueba (`test-nativa-ios`, ya sembrada) escritos por la Capacitor con red, en el
  formato de `v1.0.11`.
- [x] Android: `WebView` en `https://localhost` + `shouldInterceptRequest` (ver la sección de Android). La verdad
  sale de la propia Capacitor después de un cierre, no del LevelDB: es lo mismo que ve ella.
- [ ] Android con datos reales de la versión de Play (1.0.12) en un teléfono físico.
- [ ] En un iPhone real, actualizando desde la versión de la tienda (Hito TF-0).

Evidencias: `~/Developer/nativa-evidencia/spike/` (verdad sembrada, informes de cada corrida y captura de la vuelta).
