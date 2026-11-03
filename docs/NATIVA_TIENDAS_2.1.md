# MyPump 2.1: lo que cambia para las tiendas

Material para las fichas de la 2.1 (tanda 2 de `NATIVA_TANDAS_2_A_4.md`). Cada parte suma su sección.

## Código de barras en Dieta (S3)

**Qué hace.** En «Agregar alimento» aparece «Escanear código de barras». El escáner lee el código del envase, la app lo
busca en [Open Food Facts](https://world.openfoodfacts.org) y abre la misma hoja de cantidad que la búsqueda. Si el
producto no está o le faltan datos, ofrece cargarlo a mano (con el código) o sacarle una foto a la etiqueta. Esa foto
usa la misma lectura con IA que ya existe. Lo que se busca queda guardado en el teléfono, por código y por cuenta: un
producto encontrado vale 30 días y uno que no está, un día. Un alimento propio creado desde un código no vence, así que
al volver a escanearlo aparece directo.

**Qué viaja.** A Open Food Facts le llega **solo el código de barras**, en un `GET` público sin clave y con el
User-Agent «PumpTeam/<versión> (iOS|Android)», como pide la API. No viaja el token, ni el nombre, ni nada de la cuenta.
La respuesta se valida como un alimento propio y lo que no cierra se descarta. Ejemplos: más de 950 kcal o más de 110 g de
macros cada 100 g, o kcal que no cierran con las macros.

### iOS

- **Escáner:** VisionKit (`DataScannerViewController`) con EAN-13, EAN-8 y UPC-E. UPC-A llega como EAN-13. Con un iPhone
  que no lo soporta (anterior al A12), o sin permiso de cámara, aparece un aviso que manda a buscar por nombre. Sin
  permiso, el aviso también ofrece «Abrir Ajustes».
- **Permiso de cámara:** `NSCameraUsageDescription` ya existía por las fotos. El texto ahora nombra el escaneo:
  «…fotos de tus platos o de etiquetas nutricionales, o escanear el código de barras de un alimento…».
- **Etiqueta de privacidad / PrivacyInfo.xcprivacy:** no cambian. El código de barras de un producto no es un dato del
  usuario, y no se manda nada que lo identifique. Open Food Facts no es un SDK: es un pedido HTTP sin rastreo.
- **Notas para el revisor (si pregunta):** *"The barcode scanner in Diet → Add food looks up the scanned EAN/UPC in the
  public Open Food Facts database. Only the barcode number is sent; no account data. Camera access is only used while
  the scanner is open."*

### Android

- **Escáner:** el **Google code scanner** (`com.google.android.gms:play-services-code-scanner` 16.1.0). Lo elegimos
  sobre ML Kit con CameraX porque **no pide el permiso de cámara**: abre su propia pantalla (de Play Services) y le
  devuelve a la app solo el número. El manifest sigue con `CAMERA` en `tools:node="remove"` y el manifest final de release
  no suma ningún permiso. El modelo no va empaquetado: lo baja Play Services al instalar la app (meta-data
  `com.google.mlkit.vision.DEPENDENCIES = barcode_ui`). Sin Play Services, o mientras se baja, aparece un aviso y queda
  la búsqueda por nombre.
- **Data safety:** no cambia. No se recopila ni se comparte un dato nuevo del usuario: el código de un producto no es un
  dato personal y no va asociado a la cuenta.
- **Permisos:** ninguno nuevo.

### Datos (para la ficha, el brief y una 2.0.3)

- El agregado escaneado se guarda en `agregados` con `"origen": "barras"` y `"codigo": "<EAN>"`. Uno propio creado desde
  un código va con `"origen": "propio"` y el mismo `"codigo"`.
- **Compatibilidad con la 2.0.3:** su decodificado lee un origen desconocido como `base` y no descarta el agregado (iOS:
  `try? decode(Origen) ?? .base`; Android: `?: Origen.BASE`). Las macros y la cantidad se ven igual. Si esa versión
  reescribe el día, se pierden el origen y el código, pero no el agregado. Por eso no hizo falta caer en `"propio"`.
- El `resumen` que lee la ficha no cambia.
- Las reglas (normalizar el código y su dígito de control, UPC-E a EAN-13, el mapeo de Open Food Facts con el nombre en
  español primero y la marca entre paréntesis, kJ → kcal y la validación) están en el kit: `CodigoBarras` en iOS y en
  Android. Los vectores compartidos están en `apps/shared/vectores/barras_off.json`: 12 respuestas reales de productos
  argentinos (yogures, leches, galletitas, bizcochos, barras de cereal, turrón y alfajor) y 20 casos sintéticos.
