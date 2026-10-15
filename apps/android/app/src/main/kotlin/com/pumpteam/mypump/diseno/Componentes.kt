package com.pumpteam.mypump.diseno

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.browser.customtabs.CustomTabsClient
import androidx.browser.customtabs.CustomTabsIntent
import androidx.browser.customtabs.CustomTabsService
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import java.math.BigDecimal
import java.math.RoundingMode
import kotlin.math.abs
import kotlin.math.floor

/** Grilla de 8 (con medios pasos de 4), como `Espacio` de iOS. */
object Espacio {
    val xxs = 4.dp
    val xs = 8.dp
    val s = 12.dp
    val m = 16.dp
    val l = 24.dp
    val xl = 32.dp
    val xxl = 48.dp
}

/** Esquinas: tarjetas 24, controles 14, miniaturas 12. */
object Radio {
    val tarjeta = 24.dp
    val control = 14.dp
    val miniatura = 12.dp
}

/** Ancho de lectura en tablets: el contenido no se estira más que esto. */
val AnchoLectura = 700.dp

/**
 * La superficie de tarjeta: fondo, esquinas, sombra suave en claro y borde de pelo en oscuro (en negro una sombra no se
 * ve: lo que separa es el borde).
 */
@Composable
fun Modifier.superficieTarjeta(radio: Dp = Radio.tarjeta, color: Color = MyPump.colores.tarjeta): Modifier {
    val c = MyPump.colores
    val forma = RoundedCornerShape(radio)
    val sombra = if (c.oscuro) this else this.shadow(10.dp, forma, ambientColor = Color(0x14000000), spotColor = Color(0x14000000))
    return sombra.clip(forma).background(color).border(1.dp, c.borde, forma)
}

/** Tarjeta con su relleno, a lo ancho. */
@Composable
fun Tarjeta(
    modifier: Modifier = Modifier,
    relleno: Dp = Espacio.m,
    espaciado: Dp = Espacio.s,
    contenido: @Composable ColumnScope.() -> Unit,
) {
    Column(
        modifier = modifier.fillMaxWidth().superficieTarjeta().padding(relleno),
        verticalArrangement = Arrangement.spacedBy(espaciado),
        content = contenido,
    )
}

/**
 * Botón principal de la marca: lima con texto negro, en cápsula. Deshabilitado no se desvanece (un lima lavado parece un
 * error): pasa a gris con el texto secundario. Con [cargando] muestra la ruedita.
 */
@Composable
fun BotonMarca(
    texto: String,
    alTocar: () -> Unit,
    modifier: Modifier = Modifier,
    habilitado: Boolean = true,
    compacto: Boolean = false,
    cargando: Boolean = false,
) {
    val c = MyPump.colores
    Button(
        onClick = alTocar,
        enabled = habilitado && !cargando,
        modifier = modifier
            .then(if (compacto) Modifier else Modifier.fillMaxWidth())
            .defaultMinSize(minHeight = if (compacto) 44.dp else 54.dp),
        shape = CircleShape,
        colors = ButtonDefaults.buttonColors(
            containerColor = c.marca,
            contentColor = c.sobreMarca,
            disabledContainerColor = if (cargando) c.marca else c.campo,
            disabledContentColor = if (cargando) c.sobreMarca else c.textoSecundario,
        ),
        contentPadding = PaddingValues(horizontal = if (compacto) 16.dp else 20.dp, vertical = 8.dp),
    ) {
        if (cargando) {
            CircularProgressIndicator(Modifier.size(20.dp), color = c.sobreMarca, strokeWidth = 2.5.dp)
        } else {
            Text(texto, style = if (compacto) MaterialTheme.typography.labelLarge else MaterialTheme.typography.titleMedium)
        }
    }
}

/** El secundario a juego: misma forma, relleno gris y texto del color pedido. */
@Composable
fun BotonSecundario(
    texto: String,
    alTocar: () -> Unit,
    modifier: Modifier = Modifier,
    compacto: Boolean = false,
    tono: Color = MyPump.colores.texto,
    habilitado: Boolean = true,
    cargando: Boolean = false,
) {
    val c = MyPump.colores
    Button(
        onClick = alTocar,
        enabled = habilitado && !cargando,
        modifier = modifier
            .then(if (compacto) Modifier else Modifier.fillMaxWidth())
            .defaultMinSize(minHeight = if (compacto) 44.dp else 54.dp),
        shape = CircleShape,
        colors = ButtonDefaults.buttonColors(
            containerColor = c.campo,
            contentColor = tono,
            disabledContainerColor = c.campo,
            disabledContentColor = c.textoSecundario,
        ),
        elevation = null,
        contentPadding = PaddingValues(horizontal = if (compacto) 16.dp else 20.dp, vertical = 8.dp),
    ) {
        if (cargando) {
            CircularProgressIndicator(Modifier.size(20.dp), color = tono, strokeWidth = 2.5.dp)
        } else {
            Text(texto, style = if (compacto) MaterialTheme.typography.labelLarge else MaterialTheme.typography.titleMedium)
        }
    }
}

/** Aviso destacado (link vencido, plan incompleto): ícono de alerta y texto sobre un fondo teñido. */
@Composable
fun Aviso(icono: ImageVector, titulo: String, texto: String, modifier: Modifier = Modifier, tono: Color = MyPump.colores.alerta) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(18.dp))
            .background(tono.copy(alpha = 0.12f))
            .padding(Espacio.m),
        horizontalArrangement = Arrangement.spacedBy(Espacio.s),
    ) {
        Icon(icono, contentDescription = null, tint = tono, modifier = Modifier.size(24.dp))
        Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Text(titulo, style = MaterialTheme.typography.titleMedium)
            Text(texto, style = MaterialTheme.typography.bodyMedium, color = MyPump.colores.textoSecundario)
        }
    }
}

/** La marca: el azulejo lima con la pesa y "MyPump" en Archivo pesada, con "Pump" en verde. */
@Composable
fun MarcaMyPump(modifier: Modifier = Modifier, conLema: Boolean = true) {
    val c = MyPump.colores
    Column(modifier = modifier.semantics(mergeDescendants = true) {}, horizontalAlignment = Alignment.CenterHorizontally) {
        Box(
            modifier = Modifier
                .size(72.dp)
                .shadow(16.dp, RoundedCornerShape(20.dp), ambientColor = c.marca, spotColor = c.marca)
                .clip(RoundedCornerShape(20.dp))
                .background(c.marca),
            contentAlignment = Alignment.Center,
        ) {
            Icon(Iconos.Pesa, contentDescription = null, tint = c.sobreMarca, modifier = Modifier.size(38.dp))
        }
        Spacer(Modifier.height(10.dp))
        Text(
            buildAnnotatedString {
                append("My")
                withStyle(SpanStyle(color = c.marcaTexto)) { append("Pump") }
            },
            style = MaterialTheme.typography.displaySmall.copy(fontWeight = FontWeight.W900, fontSize = 44.sp, lineHeight = 50.sp),
            color = c.texto,
        )
        if (conLema) {
            Spacer(Modifier.height(10.dp))
            Text(
                "Tu entrenamiento y tu nutrición, con tu coach.",
                style = MaterialTheme.typography.bodyMedium,
                color = c.textoSecundario,
                textAlign = TextAlign.Center,
            )
        }
    }
}

/** Fondo de las pantallas de acceso: el de la app con un resplandor lima arriba. */
@Composable
fun Modifier.fondoMarca(): Modifier {
    val c = MyPump.colores
    return this
        .background(c.fondo)
        .drawBehind {
            val radio = 420.dp.toPx()
            drawRect(
                Brush.radialGradient(
                    colors = listOf(c.marca.copy(alpha = if (c.oscuro) 0.22f else 0.35f), Color.Transparent),
                    center = Offset(size.width / 2, 0f),
                    radius = radio,
                ),
            )
        }
}

/** Ícono blanco en un azulejo de color, como las filas de ajustes. */
@Composable
fun IconoAzulejo(icono: ImageVector, color: Color, modifier: Modifier = Modifier, lado: Dp = 30.dp) {
    Box(
        modifier = modifier
            .size(lado)
            .clip(RoundedCornerShape(lado * 0.27f))
            .background(Brush.verticalGradient(listOf(color.copy(alpha = 0.85f), color))),
        contentAlignment = Alignment.Center,
    ) {
        Icon(icono, contentDescription = null, tint = Color.White, modifier = Modifier.size(lado * 0.58f))
    }
}

/** Encabezado de sección: título en negrita y un detalle a la derecha ("Fotos de la semana      0/3"). */
@Composable
fun EncabezadoSeccion(titulo: String, modifier: Modifier = Modifier, detalle: String? = null) {
    Row(modifier = modifier.fillMaxWidth().padding(horizontal = 4.dp), verticalAlignment = Alignment.Bottom) {
        Text(
            titulo,
            style = MaterialTheme.typography.titleLarge.copy(fontFamily = Inter, fontWeight = FontWeight.Bold, fontSize = 20.sp),
            modifier = Modifier.weight(1f).semantics { heading() },
        )
        if (detalle != null) Text(detalle, style = MaterialTheme.typography.bodyMedium, color = MyPump.colores.textoSecundario)
    }
}

/** Rótulo chico de una sección de ajustes ("Apariencia"). */
@Composable
fun RotuloSeccion(texto: String, modifier: Modifier = Modifier) {
    Text(
        texto,
        style = MaterialTheme.typography.titleSmall,
        color = MyPump.colores.textoSecundario,
        modifier = modifier.padding(start = Espacio.m, top = Espacio.l, bottom = Espacio.xs).semantics { heading() },
    )
}

/** La letra chica debajo de una sección. */
@Composable
fun PieSeccion(texto: String, modifier: Modifier = Modifier) {
    Text(
        texto,
        style = MaterialTheme.typography.bodySmall,
        color = MyPump.colores.textoSecundario,
        modifier = modifier.padding(start = Espacio.m, end = Espacio.m, top = Espacio.xs),
    )
}

/** Un estado vacío o de error a pantalla completa: ícono grande, título, texto y una acción opcional. */
@Composable
fun EstadoVacio(
    icono: ImageVector,
    titulo: String,
    texto: String,
    modifier: Modifier = Modifier,
    accion: (@Composable () -> Unit)? = null,
) {
    Column(
        modifier = modifier.fillMaxSize().padding(horizontal = Espacio.xl),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Icon(icono, contentDescription = null, tint = MyPump.colores.textoSecundario, modifier = Modifier.size(48.dp))
        Spacer(Modifier.height(Espacio.m))
        Text(titulo, style = MaterialTheme.typography.titleLarge, textAlign = TextAlign.Center)
        Spacer(Modifier.height(Espacio.xs))
        Text(texto, style = MaterialTheme.typography.bodyMedium, color = MyPump.colores.textoSecundario, textAlign = TextAlign.Center)
        if (accion != null) {
            Spacer(Modifier.height(Espacio.l))
            accion()
        }
    }
}

/** Separador de pelo entre filas de una tarjeta. */
@Composable
fun Separador(modifier: Modifier = Modifier, sangria: Dp = 0.dp) {
    Box(modifier.padding(start = sangria).fillMaxWidth().height(0.5.dp).background(MyPump.colores.separador))
}

/** Punto de color (macros). */
@Composable
fun Punto(color: Color, lado: Dp = 9.dp) {
    Box(Modifier.size(lado).clip(CircleShape).background(color))
}

/** Un chip de dato ("3 alimentos"). */
@Composable
fun Chip(texto: String, modifier: Modifier = Modifier, tono: Color = MyPump.colores.textoSecundario, forma: Shape = CircleShape) {
    Text(
        texto,
        style = MaterialTheme.typography.labelMedium,
        color = tono,
        modifier = modifier.clip(forma).background(MyPump.colores.campo).padding(horizontal = 9.dp, vertical = 5.dp),
    )
}

/** Borde fino para un botón de contorno. */
@Composable
fun bordeFino(): BorderStroke = BorderStroke(1.dp, MyPump.colores.borde)

/**
 * Abre un link dentro de la app con una Custom Tab (las páginas legales y las fuentes), como el SFSafariViewController de
 * iOS: el cliente vuelve con Atrás sin salir de MyPump.
 *
 * El navegador va FIJO. El App Link de la MainActivity toma todo `app.mypumpteam.com` (con `autoVerify`): en un build de
 * Play, con el dominio verificado, un VIEW implícito a `privacidad.html` o `eliminar-datos.html` volvía a MyPump (que no
 * hacía nada con él) en vez de abrirse. La Capacitor no lo sufría porque su plugin Browser abre con una sesión, que fija
 * el navegador. Sin un navegador con Custom Tabs, va a uno cualquiera elegido entre los navegadores (nunca a MyPump).
 */
fun abrirEnNavegador(contexto: Context, url: String) {
    val uri = Uri.parse(url)
    val desdeAfuera = contexto !is Activity
    navegadorConPestanas(contexto)?.let { navegador ->
        try {
            val pestana = CustomTabsIntent.Builder().setShowTitle(true).build()
            pestana.intent.setPackage(navegador)
            if (desdeAfuera) pestana.intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            pestana.launchUrl(contexto, uri)
            return
        } catch (_: ActivityNotFoundException) {
        }
    }
    try {
        // El selector resuelve entre las apps que son navegadores (CATEGORY_APP_BROWSER) y a esa le llega el VIEW. Va armado a
        // mano: `makeMainSelectorActivity` devuelve un MAIN + LAUNCHER que lleva el de navegadores como SU selector, y el
        // sistema no mira el selector del selector. Con eso el link resolvía a cualquier app con ícono (en el emulador de
        // Android 9, que no trae navegador: la cámara, los contactos, Gmail, YouTube…; lo encontró CustomTabsTest, 15-oct).
        val ver = Intent(Intent.ACTION_VIEW, uri)
        ver.selector = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_APP_BROWSER)
        if (desdeAfuera) ver.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        contexto.startActivity(ver)
    } catch (_: ActivityNotFoundException) {
        // Sin navegador no hay a dónde ir: no se hace nada (no pasa en un teléfono real).
    }
}

/**
 * El navegador con Custom Tabs: el predeterminado si las tiene; si no, el primero que las tenga. Nunca MyPump. Verlos
 * necesita el `<queries>` de `CustomTabsService` del manifest (Android 11+).
 */
fun navegadorConPestanas(contexto: Context): String? {
    val propio = contexto.packageName
    val conPestanas = contexto.packageManager.queryIntentServices(Intent(CustomTabsService.ACTION_CUSTOM_TABS_CONNECTION), 0)
        .mapNotNull { it.serviceInfo?.packageName }
        .filter { it != propio }
        .distinct()
    return CustomTabsClient.getPackageName(contexto, conPestanas)?.takeIf { it != propio }
}

/** Cómo se escriben los números en la app, como los escribe un argentino. */
object Formato {
    /** `Int(x)` sin riesgo, redondeando como Swift (al más cercano, lejos del cero): NaN o infinito valen 0. */
    fun entero(x: Double?): Long {
        val v = x ?: return 0
        if (!v.isFinite()) return 0
        val r = if (v >= 0) floor(v + 0.5) else -floor(-v + 0.5)
        return r.coerceIn(-1e15, 1e15).toLong()
    }

    /** "2.454": miles con punto, como `toLocaleString('es-AR')`. */
    fun miles(x: Double?): String {
        val n = entero(x)
        val s = abs(n).toString()
        val out = StringBuilder()
        for ((i, ch) in s.reversed().withIndex()) {
            if (i > 0 && i % 3 == 0) out.append('.')
            out.append(ch)
        }
        return (if (n < 0) "-" else "") + out.reverse().toString()
    }

    /**
     * "52,5" / "55": hasta un decimal, con coma y sin ",0" (el `kg` de iOS). Redondea como el `FormatStyle` de iOS (ICU):
     * sobre el decimal más corto que representa al número y al par (0,25 → "0,2", 15,15 → "15,2"), no sobre el binario.
     */
    fun decimal(x: Double?): String {
        val v = x ?: return "0"
        if (!v.isFinite()) return "0"
        val r = BigDecimal(v.coerceIn(-1e15, 1e15).toString()).setScale(1, RoundingMode.HALF_EVEN).stripTrailingZeros()
        val texto = (if (r.signum() == 0) BigDecimal.ZERO else r).toPlainString().replace('.', ',')
        return texto
    }
}
