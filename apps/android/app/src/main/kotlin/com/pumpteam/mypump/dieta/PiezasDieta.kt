package com.pumpteam.mypump.dieta

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.addPathNodes
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.pumpteam.mypump.diseno.Espacio
import com.pumpteam.mypump.diseno.Formato
import com.pumpteam.mypump.diseno.MyPump
import com.pumpteam.mypump.diseno.Radio
import com.pumpteam.mypump.diseno.Separador
import com.pumpteam.mypump.diseno.superficieTarjeta
import com.pumpteam.mypump.entreno.Letras
import com.pumpteam.mypump.reglas.jsRound

// Las piezas de Dieta con escritura que comparten la hoja de reemplazo, la de alimento propio y la de comidas libres.

/** `Math.round` de JS como entero, sin riesgo (el `jsEntero` de iOS): NaN o infinito valen 0. */
internal fun jsEntero(x: Double): Long = Formato.entero(jsRound(x))

/**
 * Lo que se ve mientras la IA mira la foto (~30 s, hasta 150): no se puede tocar nada más. Es `AnalizandoFoto` de iOS:
 * un velo sobre la pantalla (o la hoja) y la tarjeta con la ruedita.
 */
@Composable
fun AnalizandoFoto(texto: String, modifier: Modifier = Modifier) {
    val c = MyPump.colores
    Box(
        modifier
            .fillMaxSize()
            .background(Color.Black.copy(alpha = 0.2f))
            // Se come los toques: lo de abajo no se puede tocar mientras tanto.
            .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null, onClick = {})
            .testTag("analizando-foto"),
        contentAlignment = Alignment.Center,
    ) {
        Column(
            Modifier
                .padding(Espacio.l)
                .widthIn(max = 300.dp)
                .shadow(24.dp, RoundedCornerShape(24.dp), ambientColor = Color(0x26000000), spotColor = Color(0x26000000))
                .clip(RoundedCornerShape(24.dp))
                .background(c.tarjeta)
                .padding(28.dp)
                .semantics(mergeDescendants = true) {},
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            CircularProgressIndicator(Modifier.size(36.dp), color = c.marcaTexto, strokeWidth = 3.dp)
            Text(texto, style = MaterialTheme.typography.titleMedium, textAlign = TextAlign.Center)
            Text("Puede tardar unos 30 segundos.", style = MaterialTheme.typography.bodyMedium, color = c.textoSecundario, textAlign = TextAlign.Center)
        }
    }
}

/** Botón redondo de acción en una fila (la mano, el reemplazo): 44 dp de toque, 34 dp visibles (`BotonCircular` de iOS). */
@Composable
internal fun BotonCircular(icono: ImageVector, descripcion: String, activo: Boolean, alTocar: () -> Unit, modifier: Modifier = Modifier) {
    val c = MyPump.colores
    Box(
        modifier
            .size(44.dp)
            .clip(CircleShape)
            .clickable(role = Role.Button, onClick = alTocar)
            .semantics { contentDescription = descripcion },
        contentAlignment = Alignment.Center,
    ) {
        Box(
            Modifier.size(34.dp).clip(CircleShape).background(if (activo) c.marca else c.campo),
            contentAlignment = Alignment.Center,
        ) {
            Icon(icono, contentDescription = null, tint = if (activo) c.sobreMarca else c.texto.copy(alpha = 0.75f), modifier = Modifier.size(17.dp))
        }
    }
}

/**
 * Una sección de formulario como las de iOS (`Form` agrupado): el rótulo arriba, las filas en una tarjeta separadas por
 * una línea de pelo, y la letra chica abajo.
 */
@Composable
internal fun SeccionFormulario(
    titulo: String?,
    modifier: Modifier = Modifier,
    pie: String? = null,
    contenido: @Composable ColumnScope.() -> Unit,
) {
    val c = MyPump.colores
    Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        if (titulo != null) {
            Text(
                titulo,
                style = Letras.caption.copy(fontWeight = FontWeight.SemiBold),
                color = c.textoSecundario,
                modifier = Modifier.padding(horizontal = Espacio.m).semantics { heading() },
            )
        }
        Column(Modifier.fillMaxWidth().superficieTarjeta(radio = Radio.control + 4.dp), content = contenido)
        if (pie != null) {
            Text(pie, style = Letras.caption, color = c.textoSecundario, modifier = Modifier.padding(horizontal = Espacio.m))
        }
    }
}

/** El separador entre filas de una [SeccionFormulario], con la sangría de iOS. */
@Composable
internal fun SeparadorFila() = Separador(sangria = Espacio.m)

/**
 * Una fila con un campo numérico a la derecha ("Calorías ··· 250 kcal"), el `campo` de los formularios de iOS. Acepta
 * coma o punto (lo lee `leerNumeroEscrito`); TalkBack dice "Calorías en kcal".
 */
@Composable
internal fun FilaNumero(
    titulo: String,
    valor: String,
    alCambiar: (String) -> Unit,
    unidad: String,
    etiqueta: String,
    modifier: Modifier = Modifier,
    descripcion: String = "$titulo en $unidad",
    decimal: Boolean = true,
    foco: FocusRequester? = null,
) {
    val c = MyPump.colores
    Row(
        modifier.fillMaxWidth().heightIn(min = 48.dp).padding(horizontal = Espacio.m),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(Espacio.s),
    ) {
        Text(titulo, style = MaterialTheme.typography.bodyLarge, modifier = Modifier.weight(1f).clearAndSetSemantics {})
        BasicTextField(
            value = valor,
            onValueChange = alCambiar,
            singleLine = true,
            textStyle = MaterialTheme.typography.bodyLarge.merge(Letras.cifras).copy(color = c.texto, textAlign = TextAlign.End),
            cursorBrush = SolidColor(c.marcaTexto),
            keyboardOptions = KeyboardOptions(keyboardType = if (decimal) KeyboardType.Decimal else KeyboardType.Number, imeAction = ImeAction.Next),
            modifier = Modifier
                .widthIn(min = 64.dp, max = 110.dp)
                .then(if (foco != null) Modifier.focusRequester(foco) else Modifier)
                .semantics { contentDescription = descripcion }
                .testTag(etiqueta),
            decorationBox = { campo ->
                Box(Modifier.padding(vertical = 10.dp), contentAlignment = Alignment.CenterEnd) {
                    if (valor.isEmpty()) {
                        Text(
                            "0",
                            style = MaterialTheme.typography.bodyLarge.merge(Letras.cifras),
                            color = c.textoTerciario,
                            textAlign = TextAlign.End,
                            modifier = Modifier.fillMaxWidth().clearAndSetSemantics {},
                        )
                    }
                    campo()
                }
            },
        )
        Text(unidad, style = MaterialTheme.typography.bodyLarge, color = c.textoSecundario, modifier = Modifier.widthIn(min = 30.dp).clearAndSetSemantics {})
    }
}

/** Una fila con un campo de texto libre a lo ancho (el nombre de un alimento, qué se comió), con su ejemplo gris. */
@Composable
internal fun FilaTexto(
    valor: String,
    alCambiar: (String) -> Unit,
    ejemplo: String,
    etiqueta: String,
    descripcion: String,
    modifier: Modifier = Modifier,
    foco: FocusRequester? = null,
) {
    val c = MyPump.colores
    BasicTextField(
        value = valor,
        onValueChange = alCambiar,
        singleLine = true,
        textStyle = MaterialTheme.typography.bodyLarge.copy(color = c.texto),
        cursorBrush = SolidColor(c.marcaTexto),
        keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Sentences, imeAction = ImeAction.Next),
        modifier = modifier
            .fillMaxWidth()
            .then(if (foco != null) Modifier.focusRequester(foco) else Modifier)
            .semantics { contentDescription = descripcion }
            .testTag(etiqueta),
        decorationBox = { campo ->
            Box(Modifier.fillMaxWidth().heightIn(min = 48.dp).padding(horizontal = Espacio.m, vertical = 12.dp), contentAlignment = Alignment.CenterStart) {
                if (valor.isEmpty()) {
                    Text(ejemplo, style = MaterialTheme.typography.bodyLarge, color = c.textoTerciario, modifier = Modifier.clearAndSetSemantics {})
                }
                campo()
            }
        },
    )
}

/** El error de un formulario (en rojo, con su ícono), como la sección de error de iOS. */
@Composable
internal fun ErrorFormulario(texto: String, etiqueta: String, modifier: Modifier = Modifier) {
    val c = MyPump.colores
    Row(
        modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(Radio.control + 4.dp))
            .background(c.peligro.copy(alpha = 0.10f))
            .padding(horizontal = Espacio.m, vertical = Espacio.s)
            .testTag(etiqueta),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(Espacio.xs),
    ) {
        Icon(com.pumpteam.mypump.diseno.Iconos.Error, contentDescription = null, tint = c.peligro, modifier = Modifier.size(20.dp))
        Text(texto, style = MaterialTheme.typography.bodyMedium, color = c.peligro)
    }
}

/**
 * Los íconos de Dieta que no están en `Iconos` (trazados de Material Icons, Apache 2.0, grilla de 24). Van acá y no en
 * `diseno/Iconos.kt` para no tocar un archivo de todas las pantallas, como `IconosRevision`.
 */
internal object IconosDieta {
    private fun icono(nombre: String, trazado: String): ImageVector =
        ImageVector.Builder(name = nombre, defaultWidth = 24.dp, defaultHeight = 24.dp, viewportWidth = 24f, viewportHeight = 24f)
            .apply { addPath(pathData = addPathNodes(trazado), fill = SolidColor(Color.Black)) }
            .build()

    /** add_circle: "Crear alimento personalizado". */
    val MasEnCirculo: ImageVector by lazy {
        icono("MasEnCirculo", "M12,2C6.48,2 2,6.48 2,12s4.48,10 10,10 10,-4.48 10,-10S17.52,2 12,2zM17,13h-4v4h-2v-4H7v-2h4V7h2v4h4v2z")
    }

    /** document_scanner: "Escanear etiqueta". */
    val Escanear: ImageVector by lazy {
        icono(
            "Escanear",
            "M7,3H4v3H2V1h5V3zM22,6V1h-5v2h3v3H22zM7,21H4v-3H2v5h5V21zM20,18v3h-3v2h5v-5H20zM19,18c0,1.1 -0.9,2 -2,2H7c-1.1,0 -2,-0.9 -2,-2V6c0,-1.1 0.9,-2 2,-2h10c1.1,0 2,0.9 2,2V18zM15,8H9v2h6V8zM15,11H9v2h6V11zM15,14H9v2h6V14z",
        )
    }

    /** fastfood: las comidas libres (fuera del plan). */
    val ComidaAfuera: ImageVector by lazy {
        icono(
            "ComidaAfuera",
            "M18.06,22.99h1.66c0.84,0 1.53,-0.64 1.63,-1.46L23,5.05h-5V1h-1.97v4.05h-4.97l0.3,2.34c1.71,0.47 3.31,1.32 4.27,2.26 1.44,1.42 2.43,2.89 2.43,5.29v8.05zM1,21.99V21h15.03v0.99c0,0.55 -0.45,1 -1.01,1H2.01c-0.56,0 -1.01,-0.45 -1.01,-1zM16.03,14.99c0,-8 -15.03,-8 -15.03,0h15.03zM1.02,17h15v2h-15z",
        )
    }
}
