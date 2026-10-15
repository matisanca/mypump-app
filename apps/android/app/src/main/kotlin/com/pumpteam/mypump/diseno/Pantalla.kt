package com.pumpteam.mypump.diseno

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.calculateEndPadding
import androidx.compose.foundation.layout.calculateStartPadding
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.LargeTopAppBar
import androidx.compose.material3.LocalTextStyle
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.rememberTopAppBarState
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/**
 * El marco de cada pantalla: el título grande en Archivo que se achica al desplazar (el título grande de iOS, en su
 * versión de Material), la flecha de volver si corresponde y las acciones a la derecha. El contenido recibe el relleno de
 * la barra.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MarcoPantalla(
    titulo: String,
    modifier: Modifier = Modifier,
    subtitulo: String? = null,
    alVolver: (() -> Unit)? = null,
    acciones: @Composable RowScope.() -> Unit = {},
    contenido: @Composable (relleno: PaddingValues) -> Unit,
) {
    val c = MyPump.colores
    val comportamiento = TopAppBarDefaults.exitUntilCollapsedScrollBehavior(rememberTopAppBarState())
    Scaffold(
        modifier = modifier.nestedScroll(comportamiento.nestedScrollConnection),
        containerColor = c.fondo,
        topBar = {
            // El título grande de iOS: la letra del sistema en negrita, 34; plegado, 17 como el título de la barra.
            MaterialTheme(typography = MaterialTheme.typography.copy(headlineMedium = TituloGrande, titleLarge = TituloBarra)) {
            LargeTopAppBar(
                title = {
                    // Expandido, el subtítulo va pegado abajo del título grande (el `navigationSubtitle` de iOS); plegado, solo
                    // el título. Material pinta este mismo contenido en los dos lugares, cada uno con su estilo.
                    val expandido = LocalTextStyle.current.fontSize == TituloGrande.fontSize
                    if (subtitulo != null && expandido) {
                        Column {
                            Text(titulo, maxLines = 1, overflow = TextOverflow.Ellipsis)
                            Text(
                                subtitulo,
                                style = MaterialTheme.typography.bodySmall,
                                color = c.textoSecundario,
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis,
                                modifier = Modifier.testTag("subtitulo"),
                            )
                        }
                    } else {
                        Text(titulo, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                },
                navigationIcon = { if (alVolver != null) BotonVolver(alVolver, Modifier.padding(start = Espacio.xs)) },
                actions = acciones,
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = c.fondo,
                    scrolledContainerColor = c.tarjeta,
                    titleContentColor = c.texto,
                    navigationIconContentColor = c.marcaTexto,
                    actionIconContentColor = c.marcaTexto,
                ),
                // La de Material mide 152: con 136 el título sigue entrando y la fila de arriba (vacía si no hay acciones)
                // no deja tanto hueco.
                expandedHeight = if (subtitulo != null) 156.dp else 136.dp,
                scrollBehavior = comportamiento,
            )
            }
        },
    ) { relleno ->
        // Abajo, lo que tapa la barra de pestañas flotante: va al final del desplazamiento (adentro), así lo último queda
        // arriba de la barra y el resto pasa por debajo, como en iOS.
        val dir = LocalLayoutDirection.current
        contenido(
            PaddingValues(
                start = relleno.calculateStartPadding(dir),
                top = relleno.calculateTopPadding(),
                end = relleno.calculateEndPadding(dir),
                bottom = relleno.calculateBottomPadding() + LocalRellenoInferior.current,
            ),
        )
    }
}

/**
 * [MarcoPantalla] con el contenido en una columna: desplazable (lo de siempre) o fija a la altura de la pantalla (los
 * estados vacíos, centrados).
 */
@Composable
fun PantallaConTitulo(
    titulo: String,
    modifier: Modifier = Modifier,
    alVolver: (() -> Unit)? = null,
    acciones: @Composable RowScope.() -> Unit = {},
    desplazable: Boolean = false,
    contenido: @Composable ColumnScope.() -> Unit,
) {
    MarcoPantalla(titulo, modifier, alVolver = alVolver, acciones = acciones) { relleno ->
        val dir = LocalLayoutDirection.current
        Column(
            modifier = Modifier
                .padding(start = relleno.calculateStartPadding(dir), top = relleno.calculateTopPadding(), end = relleno.calculateEndPadding(dir))
                .fillMaxSize()
                .then(if (desplazable) Modifier.verticalScroll(rememberScrollState()) else Modifier),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Column(
                modifier = Modifier
                    .widthIn(max = AnchoLectura)
                    .fillMaxWidth()
                    .then(if (desplazable) Modifier else Modifier.fillMaxSize())
                    .padding(bottom = relleno.calculateBottomPadding() + Espacio.xl),
                verticalArrangement = Arrangement.spacedBy(Espacio.m),
                content = contenido,
            )
        }
    }
}

/** El título grande de iOS (34, negrita, en Inter como SF Pro) y el de la barra plegada (17, semibold). */
private val TituloGrande = TextStyle(fontFamily = Inter, fontWeight = FontWeight.Bold, fontSize = 34.sp, lineHeight = 41.sp, letterSpacing = (-0.4).sp)
private val TituloBarra = TextStyle(fontFamily = Inter, fontWeight = FontWeight.SemiBold, fontSize = 17.sp, lineHeight = 22.sp, letterSpacing = 0.sp)

/**
 * Volver, como en iOS 26: un círculo de vidrio de 44 con la flecha. Lo encuentran las pruebas y TalkBack ("Volver").
 */
@Composable
fun BotonVolver(
    alVolver: () -> Unit,
    modifier: Modifier = Modifier,
    descripcion: String = "Volver",
    etiqueta: String = "volver",
    habilitado: Boolean = true,
) {
    val c = MyPump.colores
    Box(
        modifier = modifier
            .size(44.dp)
            .vidrio(CircleShape, elevacion = 6.dp)
            .clickable(enabled = habilitado, role = Role.Button, onClick = alVolver)
            .semantics { contentDescription = descripcion }
            .testTag(etiqueta),
        contentAlignment = Alignment.Center,
    ) {
        Icon(Iconos.ChevronAtras, contentDescription = null, tint = if (habilitado) c.texto else c.textoTerciario, modifier = Modifier.size(26.dp))
    }
}

/**
 * El relleno del marco sin el de abajo: lo de abajo (la barra de pestañas flotante) va al final del desplazamiento, así
 * el contenido pasa por debajo de la barra y lo último queda arriba de ella.
 */
@Composable
fun PaddingValues.sinAbajo(): PaddingValues {
    val dir = LocalLayoutDirection.current
    return PaddingValues(start = calculateStartPadding(dir), top = calculateTopPadding(), end = calculateEndPadding(dir))
}
