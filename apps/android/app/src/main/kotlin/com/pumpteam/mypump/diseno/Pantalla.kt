package com.pumpteam.mypump.diseno

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LargeTopAppBar
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.rememberTopAppBarState
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp

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
            LargeTopAppBar(
                title = { Text(titulo, maxLines = 1, overflow = TextOverflow.Ellipsis) },
                navigationIcon = {
                    if (alVolver != null) {
                        IconButton(onClick = alVolver, modifier = Modifier.testTag("volver")) {
                            Icon(Iconos.Atras, contentDescription = "Volver")
                        }
                    }
                },
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
                expandedHeight = 136.dp,
                scrollBehavior = comportamiento,
            )
        },
    ) { relleno -> contenido(relleno) }
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
    MarcoPantalla(titulo, modifier, alVolver, acciones) { relleno ->
        Column(
            modifier = Modifier
                .padding(relleno)
                .fillMaxSize()
                .then(if (desplazable) Modifier.verticalScroll(rememberScrollState()) else Modifier),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Column(
                modifier = Modifier
                    .widthIn(max = AnchoLectura)
                    .fillMaxWidth()
                    .then(if (desplazable) Modifier else Modifier.fillMaxSize())
                    .padding(bottom = Espacio.xl),
                verticalArrangement = Arrangement.spacedBy(Espacio.m),
                content = contenido,
            )
        }
    }
}
