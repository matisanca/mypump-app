package com.pumpteam.mypump.entreno

import androidx.compose.animation.core.Spring
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
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
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.pumpteam.mypump.diseno.MyPump

// El lenguaje visual de la carga de series (gemelo de EstiloCarga.swift): un instrumento de gimnasio. Un solo foco por serie
// (el número grande), pocas cajas, y todo el verde reservado para lo que avanza. Colores y Archivo, los de `Tema.kt`.

object EstiloCarga {
    /** La superficie del panel: blanca en claro y, en oscuro, un escalón arriba de las tarjetas para que se note que flota. */
    val panelClaro = Color(0xFFFFFFFF)
    val panelOscuro = Color(0xFF202223)

    /** El resorte de todo lo que se mueve al confirmar: rápido y sin rebote de juguete. */
    fun <T> resorte() = spring<T>(dampingRatio = 0.8f, stiffness = Spring.StiffnessMediumLow)
    fun <T> resorteDial() = spring<T>(dampingRatio = 0.7f, stiffness = 900f)
}

/** Pantallas bajas (un teléfono chico): el panel achica el tambor para dejarle lugar a la lista. */
@Composable
internal fun pantallaChica(): Boolean = LocalConfiguration.current.screenHeightDp < 700

/** La superficie del panel: esquinas de arriba redondeadas, sombra hacia arriba en claro y filo de luz en oscuro. */
@Composable
internal fun Modifier.superficiePanelCarga(): Modifier {
    val c = MyPump.colores
    val forma = RoundedCornerShape(topStart = 28.dp, topEnd = 28.dp)
    return this
        .shadow(if (c.oscuro) 0.dp else 18.dp, forma, clip = false, ambientColor = Color.Black.copy(alpha = 0.25f), spotColor = Color.Black.copy(alpha = 0.25f))
        .clip(forma)
        .background(if (c.oscuro) EstiloCarga.panelOscuro else EstiloCarga.panelClaro)
        .border(1.dp, c.borde, forma)
}

/**
 * El botón que registra: alto, en cápsula, con la luz arriba. En la guardia cambia de color sin moverse. Deshabilitado pasa a
 * gris (un verde lavado parece un error).
 */
@Composable
internal fun BotonConfirmar(
    alTocar: () -> Unit,
    modifier: Modifier = Modifier,
    habilitado: Boolean = true,
    alerta: Boolean = false,
    compacto: Boolean = false,
    contenido: @Composable BoxScope.(Color) -> Unit,
) {
    val c = MyPump.colores
    val interaccion = remember { MutableInteractionSource() }
    val apretado by interaccion.collectIsPressedAsState()
    val escala by animateFloatAsState(if (apretado) 0.965f else 1f, spring(stiffness = Spring.StiffnessHigh), label = "escala-ok")
    val fondo by animateColorAsState(
        when {
            !habilitado -> c.campo
            alerta -> c.alerta
            else -> c.marca
        },
        label = "color-ok",
    )
    val tinta = when {
        !habilitado -> c.textoSecundario
        alerta && !c.oscuro -> Color.White
        else -> c.sobreMarca
    }
    val alto: Dp = if (compacto) 48.dp else if (pantallaChica()) 54.dp else 60.dp
    Box(
        modifier
            .heightIn(min = alto)
            .graphicsLayer { scaleX = escala; scaleY = escala }
            .clip(CircleShape)
            .background(fondo)
            .then(if (habilitado) Modifier.background(Brush.verticalGradient(0f to Color.White.copy(alpha = 0.10f), 0.5f to Color.Transparent)) else Modifier)
            .clickable(interactionSource = interaccion, indication = null, enabled = habilitado, role = Role.Button, onClick = alTocar)
            .padding(horizontal = if (compacto) 14.dp else 20.dp, vertical = 6.dp),
        contentAlignment = Alignment.Center,
    ) { contenido(tinta) }
}

/** − y + redondos: se hunden al apretar. */
@Composable
internal fun BotonCircularCarga(
    icono: ImageVector,
    etiqueta: String,
    id: String,
    lado: Dp = 60.dp,
    tamanoIcono: Dp = 24.dp,
    habilitado: Boolean = true,
    alTocar: () -> Unit,
) {
    val c = MyPump.colores
    val interaccion = remember { MutableInteractionSource() }
    val apretado by interaccion.collectIsPressedAsState()
    val escala by animateFloatAsState(if (apretado) 0.88f else 1f, spring(stiffness = Spring.StiffnessHigh), label = "escala-circulo")
    Box(
        Modifier
            .size(lado)
            .graphicsLayer { scaleX = escala; scaleY = escala; alpha = if (apretado) 0.75f else 1f }
            .clip(CircleShape)
            .background(c.campo)
            .clickable(interactionSource = interaccion, indication = null, enabled = habilitado, role = Role.Button, onClick = alTocar)
            .semantics { contentDescription = etiqueta }
            .testTag(id),
        contentAlignment = Alignment.Center,
    ) {
        Icon(icono, contentDescription = null, tint = if (habilitado) c.texto else c.textoTerciario, modifier = Modifier.size(tamanoIcono))
    }
}

/** El avance del ejercicio, un segmento por serie: hechas en verde, la de ahora a medio llenar y el resto apagadas. */
@Composable
internal fun ProgresoSeries(total: Int, hechas: Int, actual: Int?) {
    val c = MyPump.colores
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
        repeat(maxOf(total, 1)) { i ->
            val color by animateColorAsState(
                when {
                    i < hechas -> c.marca
                    i == actual -> c.marca.copy(alpha = 0.36f)
                    else -> c.campo
                },
                EstiloCarga.resorte(),
                label = "segmento-$i",
            )
            Box(Modifier.weight(1f).height(4.dp).clip(CircleShape).background(color))
        }
    }
}
