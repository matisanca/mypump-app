package com.pumpteam.mypump.diseno

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.foundation.text.TextAutoSize
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

// El lenguaje de la carga rediseñada llevado al resto de la app (gemelo de `Sistema.swift`; aprobado por Mati el 10/11).
// Tres reglas, las mismas del panel de carga:
// · Un solo foco por pantalla: un número grande en Archivo que dice cómo voy.
// · Pocas cajas: lo que es contexto va sin fondo; la tarjeta queda para lo que se toca.
// · El verde es de lo que avanza: el botón que registra y el avance. Lo demás, neutro.
// Y una de contraste (WCAG AA): en oscuro el verde va lleno o no va, y sobre verde vivo el texto y los íconos van casi negros.
// Los colores base, `Espacio`, `Radio` y `Archivo` siguen siendo los de `Tema.kt` y `Componentes.kt`.

/** La superficie de la tarjeta principal: casi negra en claro (el negro del logo) y el escalón del panel de carga en oscuro. Nunca negro puro. */
val SuperficieHeroeClaro = Color(0xFF17181A)
val SuperficieHeroeOscuro = Color(0xFF202223)

/** El verde de un avance (segmentos y barras): en claro, el hondo, que da 3,9:1 contra el riel (el del logo, 2,9:1). */
val ColoresMyPump.avance: Color get() = if (oscuro) MarcaOscura else Color(0xFF157A28)

/** El riel de una barra o de un segmento sin hacer: gris neutro, nunca verde translúcido. */
val ColoresMyPump.riel: Color get() = if (oscuro) Color(0x24FFFFFF) else Color(0x1A000000)

/** Texto de apoyo que informa (notas, la línea de una fila): 6:1 sobre blanco. En oscuro, el secundario (7:1). */
val ColoresMyPump.apoyo: Color get() = if (oscuro) textoSecundario else Color(0xFF636369)

/** La escala de letra, con nombre. Archivo para números y títulos; Inter para lo que se lee o se toca. En sp: escala con la letra del sistema. */
object Letra {
    /** El número de la pantalla (kcal del día, tiempo de sesión): 56. */
    val heroe = TextStyle(fontFamily = Archivo, fontWeight = FontWeight.W800, fontSize = 56.sp, lineHeight = 58.sp, fontFeatureSettings = "tnum")
    /** Título de pantalla o de día: 34. */
    val titulo = TextStyle(fontFamily = Archivo, fontWeight = FontWeight.W800, fontSize = 34.sp, lineHeight = 38.sp)
    /** Número de una fila o de una columna: 22. */
    val dato = TextStyle(fontFamily = Archivo, fontWeight = FontWeight.W700, fontSize = 22.sp, lineHeight = 26.sp, fontFeatureSettings = "tnum")
    /** El texto del botón principal: 19. */
    val accion = TextStyle(fontFamily = Archivo, fontWeight = FontWeight.W700, fontSize = 19.sp, lineHeight = 23.sp)
    /** Título de sección: 20 negrita. */
    val seccion = TextStyle(fontFamily = Inter, fontWeight = FontWeight.Bold, fontSize = 20.sp, lineHeight = 25.sp)
    val cuerpo = TextStyle(fontFamily = Inter, fontSize = 15.sp, lineHeight = 20.sp)
    val apoyo = TextStyle(fontFamily = Inter, fontSize = 13.sp, lineHeight = 18.sp)
    /** Rótulo sobre un título o bajo un dato: 12 seminegrita, en mayúsculas. */
    val ceja = TextStyle(fontFamily = Inter, fontWeight = FontWeight.SemiBold, fontSize = 12.sp, lineHeight = 15.sp, letterSpacing = 0.6.sp)
}

/**
 * El botón que hace avanzar (Empezar, Comí, Entrar): el OK de la carga para toda la app. Cápsula de 58, Archivo, la luz
 * arriba y la sombra de su mismo verde. Uno solo por pantalla visible. Deshabilitado va en gris pleno, nunca verde lavado.
 */
@Composable
fun BotonAccion(
    texto: String,
    alTocar: () -> Unit,
    modifier: Modifier = Modifier,
    icono: ImageVector? = null,
    habilitado: Boolean = true,
    compacto: Boolean = false,
    cargando: Boolean = false,
    ancho: Boolean = true,
) {
    val c = MyPump.colores
    val activo = habilitado && !cargando
    val interaccion = remember { MutableInteractionSource() }
    val apretado by interaccion.collectIsPressedAsState()
    val escala by animateFloatAsState(if (apretado) 0.965f else 1f, spring(stiffness = Spring.StiffnessHigh), label = "escala-accion")
    val lleno = habilitado || cargando
    val fondo by animateColorAsState(if (lleno) c.marca else c.campo, label = "color-accion")
    val tinta = if (lleno) c.sobreMarca else c.textoSecundario
    Box(
        modifier
            .then(if (ancho) Modifier.fillMaxWidth() else Modifier)
            .defaultMinSize(minHeight = if (compacto) 48.dp else 58.dp)
            .graphicsLayer { scaleX = escala; scaleY = escala }
            .then(
                if (lleno && !compacto) Modifier.shadow(12.dp, CircleShape, clip = false, ambientColor = c.marca.copy(alpha = 0.5f), spotColor = c.marca)
                else Modifier,
            )
            .clip(CircleShape)
            .background(fondo)
            .then(if (lleno) Modifier.background(Brush.verticalGradient(0f to Color.White.copy(alpha = 0.10f), 0.5f to Color.Transparent)) else Modifier)
            .clickable(interactionSource = interaccion, indication = null, enabled = activo, role = Role.Button, onClick = alTocar)
            .padding(horizontal = if (compacto) 16.dp else 20.dp, vertical = 8.dp),
        contentAlignment = Alignment.Center,
    ) {
        if (cargando) {
            CircularProgressIndicator(Modifier.size(22.dp), color = tinta, strokeWidth = 2.5.dp)
        } else {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                if (icono != null) Icon(icono, contentDescription = null, tint = tinta, modifier = Modifier.size(if (compacto) 18.dp else 20.dp))
                Text(
                    texto,
                    style = if (compacto) MaterialTheme.typography.titleMedium else Letra.accion,
                    color = tinta,
                    textAlign = TextAlign.Center,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f, fill = false),
                )
            }
        }
    }
}

/** La salida discreta que acompaña al botón principal («Salté», «Dejar»): solo texto (con su ícono), zona de toque de 48. */
@Composable
fun BotonDiscreto(
    texto: String,
    alTocar: () -> Unit,
    modifier: Modifier = Modifier,
    icono: ImageVector? = null,
    tono: Color = MyPump.colores.apoyo,
    habilitado: Boolean = true,
) {
    Row(
        modifier
            .defaultMinSize(minWidth = 48.dp, minHeight = 48.dp)
            .clip(CircleShape)
            .clickable(enabled = habilitado, role = Role.Button, onClick = alTocar)
            .padding(horizontal = 14.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp, Alignment.CenterHorizontally),
    ) {
        if (icono != null) Icon(icono, contentDescription = null, tint = tono, modifier = Modifier.size(16.dp))
        Text(texto, style = MaterialTheme.typography.labelLarge, color = tono, maxLines = 1)
    }
}

/**
 * El avance en segmentos de la carga (uno por serie), para cualquier cuenta corta: ejercicios del día, fotos, el check.
 * Hecho o no hecho: sin verdes a medias (un verde translúcido sobre negro se ensucia). Pasados los 12, una sola barra.
 */
@Composable
fun AvanceSegmentos(total: Int, hechos: Int, modifier: Modifier = Modifier, alto: Dp = 5.dp) {
    val c = MyPump.colores
    val n = maxOf(total, 1)
    if (total > 12) {
        Box(modifier.fillMaxWidth().height(alto).clip(CircleShape).background(c.riel).clearAndSetSemantics {}) {
            Box(Modifier.fillMaxWidth((hechos.toFloat() / n).coerceIn(0f, 1f)).height(alto).clip(CircleShape).background(c.avance))
        }
    } else {
        Row(modifier.fillMaxWidth().clearAndSetSemantics {}, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            repeat(n) { i ->
                val color by animateColorAsState(if (i < hechos) c.avance else c.riel, label = "segmento-$i")
                Box(Modifier.weight(1f).height(alto).clip(CircleShape).background(color))
            }
        }
    }
}

/** Una nota de contexto: ícono y texto, sin caja. Reemplaza a los recuadros teñidos cuando no hay nada que tocar ni nada que anda mal. */
@Composable
fun NotaDiscreta(icono: ImageVector, texto: AnnotatedString, modifier: Modifier = Modifier, tono: Color = MyPump.colores.marcaTexto) {
    Row(
        modifier.fillMaxWidth().padding(horizontal = 4.dp).semantics(mergeDescendants = true) {},
        horizontalArrangement = Arrangement.spacedBy(Espacio.xs),
    ) {
        Icon(icono, contentDescription = null, tint = tono, modifier = Modifier.padding(top = 1.dp).size(16.dp))
        Text(texto, style = Letra.apoyo, color = MyPump.colores.apoyo, modifier = Modifier.weight(1f))
    }
}

@Composable
fun NotaDiscreta(icono: ImageVector, texto: String, modifier: Modifier = Modifier, tono: Color = MyPump.colores.marcaTexto) =
    NotaDiscreta(icono, AnnotatedString(texto), modifier, tono)

/**
 * Azulejo teñido: el ícono en el verde de texto sobre el verde suave. Reemplaza al azulejo de relleno vivo con ícono blanco,
 * que en oscuro no llega a contraste (blanco sobre #5BBE62, 2,3:1).
 */
@Composable
fun AzulejoSuave(icono: ImageVector, modifier: Modifier = Modifier, tinta: Color = MyPump.colores.marcaTexto, lado: Dp = 36.dp) {
    val c = MyPump.colores
    Box(
        modifier.size(lado).clip(RoundedCornerShape(lado * 0.3f)).background(if (tinta == c.marcaTexto) c.marcaSuave else tinta.copy(alpha = 0.16f)),
        contentAlignment = Alignment.Center,
    ) {
        Icon(icono, contentDescription = null, tint = tinta, modifier = Modifier.size(lado * 0.56f))
    }
}

/**
 * Una fila de tarjeta que lleva a otro lado: azulejo, título, una línea y, a la derecha, el dato si lo hay y la flecha.
 * Reemplaza a la tarjeta de tres pisos (título, texto, renglón «Ver…»). Toda la fila se toca.
 */
@Composable
fun FilaDestino(
    icono: ImageVector,
    titulo: String,
    detalle: String?,
    alTocar: () -> Unit,
    modifier: Modifier = Modifier,
    color: Color = MyPump.colores.marcaTexto,
    etiquetaToque: String? = null,
    dato: @Composable () -> Unit = {},
) {
    val c = MyPump.colores
    Row(
        modifier
            .fillMaxWidth()
            .defaultMinSize(minHeight = 64.dp)
            .clickable(onClickLabel = etiquetaToque, role = Role.Button, onClick = alTocar)
            .padding(horizontal = Espacio.m, vertical = 14.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(Espacio.s),
    ) {
        AzulejoSuave(icono, tinta = color)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(titulo, style = MaterialTheme.typography.titleMedium, color = c.texto)
            if (detalle != null) Text(detalle, style = Letra.cuerpo, color = c.apoyo)
        }
        dato()
        Icon(Iconos.Chevron, contentDescription = null, tint = c.textoTerciario, modifier = Modifier.size(16.dp))
    }
}

/** Título de sección con su avance: «Fotos de la semana», «1 de 3» en Archivo y los segmentos debajo, en vez de la fracción gris. */
@Composable
fun EncabezadoAvance(titulo: String, hechos: Int, total: Int, modifier: Modifier = Modifier, completo: String = "Completo") {
    val c = MyPump.colores
    Column(
        modifier.fillMaxWidth().padding(horizontal = 4.dp),
        verticalArrangement = Arrangement.spacedBy(Espacio.xs),
    ) {
        Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(Espacio.xs)) {
            Text(titulo, style = Letra.seccion, color = c.texto, modifier = Modifier.weight(1f).semantics { heading() })
            if (hechos >= total) {
                Row(
                    Modifier.semantics(mergeDescendants = true) {},
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(4.dp),
                ) {
                    Icon(Iconos.TildeEnCirculo, contentDescription = null, tint = c.marcaTexto, modifier = Modifier.size(18.dp))
                    Text(completo, style = MaterialTheme.typography.labelLarge, color = c.marcaTexto)
                }
            } else {
                Row(
                    Modifier.clearAndSetSemantics { contentDescription = "$hechos de $total" },
                    verticalAlignment = Alignment.Bottom,
                ) {
                    Text("$hechos", style = Letra.dato, color = c.texto)
                    Text(" de $total", style = Letra.cuerpo.copy(fontWeight = FontWeight.Medium), color = c.apoyo, modifier = Modifier.padding(bottom = 2.dp))
                }
            }
        }
        AvanceSegmentos(total, hechos)
    }
}

/**
 * La tarjeta principal de una pestaña: el número, el avance y la acción del día en un solo bloque oscuro, como el panel de
 * carga. Es la firma visual de la app: una por pantalla, arriba. Adentro rige el modo oscuro, así se ve igual en claro y
 * en oscuro. [marca]: una marca de agua grande en la esquina (el número del día), decorativa.
 */
@Composable
fun Heroe(modifier: Modifier = Modifier, marca: String? = null, espaciado: Dp = Espacio.m, contenido: @Composable ColumnScope.() -> Unit) {
    val oscuro = MyPump.colores.oscuro
    val forma = RoundedCornerShape(28.dp)
    Box(
        modifier
            .fillMaxWidth()
            .then(if (oscuro) Modifier else Modifier.shadow(16.dp, forma, clip = false, ambientColor = Color.Black.copy(alpha = 0.3f), spotColor = Color.Black.copy(alpha = 0.3f)))
            .clip(forma)
            .background(if (oscuro) SuperficieHeroeOscuro else SuperficieHeroeClaro)
            .border(1.dp, Color.White.copy(alpha = 0.08f), forma),
    ) {
        if (marca != null) {
            BasicText(
                marca,
                style = TextStyle(fontFamily = Archivo, fontWeight = FontWeight.W900, fontSize = 120.sp, color = Color.White.copy(alpha = 0.045f)),
                modifier = Modifier.align(Alignment.TopEnd).offset(x = (-10).dp, y = (-30).dp).clearAndSetSemantics {},
            )
        }
        EnOscuro {
            Column(Modifier.fillMaxWidth().padding(20.dp), verticalArrangement = Arrangement.spacedBy(espaciado), content = contenido)
        }
    }
}

/** Un dato de la tarjeta principal: el número en Archivo y su rótulo en mayúsculas debajo. */
@Composable
fun DatoHeroe(valor: String, rotulo: String, modifier: Modifier = Modifier) {
    val c = MyPump.colores
    Column(modifier.semantics(mergeDescendants = true) {}, verticalArrangement = Arrangement.spacedBy(1.dp)) {
        BasicText(
            valor,
            style = Letra.dato.copy(color = c.texto),
            maxLines = 1,
            autoSize = TextAutoSize.StepBased(minFontSize = 14.sp, maxFontSize = 22.sp),
        )
        Text(
            rotulo.uppercase(),
            style = Letra.ceja,
            color = c.textoSecundario,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.semantics { contentDescription = rotulo },
        )
    }
}
