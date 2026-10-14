# Prueba del almacenamiento viejo (riesgo n.º 1)

**Pregunta:** ¿la app nativa, publicada como update del mismo `com.pumpteam.mypump`, puede leer lo que la app
Capacitor dejó en el `localStorage` del WebView? Si no pudiera, haría falta una actualización puente de la Capacitor,
y eso toca código compartido con la web.

**Respuesta en iOS 26.5:** sí, por dos caminos independientes, byte a byte y en las dos direcciones.

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

## Lo que falta

- [ ] iOS 17.5 y 18.x (runtimes bajando). Es el piso que soporta la nativa y otro WebKit.
- [ ] Matar la app justo después de la escritura de vuelta, para medir si se pierde. El diseño ya la confirma en el
  arranque siguiente con la Ruta B.
- [ ] Datos reales de una cuenta de prueba (`test-nativa-ios`, ya sembrada) escritos por la Capacitor con red, en el
  formato de `v1.0.11`.
- [ ] Android: `WebView` en `https://localhost` + `shouldInterceptRequest`, verificado contra el LevelDB.
- [ ] En un iPhone real, actualizando desde la versión de la tienda (Hito TF-0).

Evidencias: `~/Developer/nativa-evidencia/spike/` (verdad sembrada, informes de cada corrida y captura de la vuelta).
