package com.pumpteam.mypump.misalud

import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.background
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionInRoot
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.pumpteam.mypump.datos.ModeloApp
import com.pumpteam.mypump.datos.ModeloEstudios
import com.pumpteam.mypump.datos.ModeloPresion
import com.pumpteam.mypump.diseno.AnchoLectura
import com.pumpteam.mypump.diseno.apoyo
import com.pumpteam.mypump.diseno.AzulejoSuave
import com.pumpteam.mypump.diseno.EncabezadoSeccion
import com.pumpteam.mypump.diseno.Espacio
import com.pumpteam.mypump.diseno.FilaDestino
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.foundation.layout.Spacer
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.unit.em
import com.pumpteam.mypump.guia.VerdeGuia
import com.pumpteam.mypump.raiz.LocalNavegacion
import com.pumpteam.mypump.reglas.TextosControles
import com.pumpteam.mypump.diseno.Iconos
import com.pumpteam.mypump.diseno.MarcoPantalla
import com.pumpteam.mypump.diseno.MyPump
import com.pumpteam.mypump.diseno.Radio
import com.pumpteam.mypump.diseno.rellenoInferior
import com.pumpteam.mypump.diseno.superficieTarjeta
import com.pumpteam.mypump.entreno.reducirMovimiento
import com.pumpteam.mypump.estudios.AccionesEstudios
import com.pumpteam.mypump.estudios.ConEstudios
import com.pumpteam.mypump.estudios.ContenidoEstudios
import com.pumpteam.mypump.estudios.ProximoControl
import com.pumpteam.mypump.estudios.estadoDeEstudios
import com.pumpteam.mypump.estudios.hayControlCerca
import com.pumpteam.mypump.estudios.sincronizarEstudios
import com.pumpteam.mypump.presion.TarjetaPresionDe
import com.pumpteam.mypump.raiz.LocalAlcanceApp
import com.pumpteam.mypump.raiz.Navegacion
import com.pumpteam.mypump.raiz.SegmentoSalud
import com.pumpteam.mypump.reglas.EstadoEstudios
import com.pumpteam.mypump.reglas.Estudios
import com.pumpteam.mypump.reglas.MiSalud
import com.pumpteam.mypump.reglas.TextosEstudios
import com.pumpteam.mypump.reglas.TextosPresion
import com.pumpteam.mypump.revision.TarjetaRecuperacionRevision
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.filterNotNull
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull

// «Mi salud» (pedido de Mati del 11/11, `nativa-evidencia/privado/MI_SALUD_SPEC.md`): todo lo de salud en una sola
// pantalla que se abre desde Revisión, sin sumar pestañas. Reúne lo que ya existía, sin repetir lógica: el próximo control
// y la lista de Estudios ([ConEstudios], [ContenidoEstudios]), la tarjeta y la pantalla de Presión ([TarjetaPresionDe],
// la capa de Presión) y la fila de Recuperación que abre Salud ([TarjetaRecuperacionRevision]). Cada bloque va solo si su
// palanca o su condición de hoy lo muestra ([MiSalud.bloques]). Gemela de `MiSaludView.swift`.

/** Lo que tarda en aparecer un bloque pedido (la sección carga con la app recién abierta) antes de quedarse arriba. */
private const val ESPERA_BLOQUE_MS = 20_000L

/**
 * Lo que hay hoy en Mi salud y lo que dice su tarjeta de Revisión. [botonEstudios] y [presion] son lo que mostraban las
 * tarjetas viejas del inicio (el texto del botón de Estudios y la tarjeta de Presión), para la tarjeta verde de Entreno.
 */
data class EstadoMiSalud(
    val bloques: List<MiSalud.Bloque>,
    val tarjeta: MiSalud.Tarjeta?,
    val botonEstudios: Estudios.TarjetaInicio? = null,
    val presion: ModeloPresion.Tarjeta? = null,
)

/** La línea de la tarjeta de Revisión para lo que pide Presión. «La de hoy ya está» no pide nada. */
fun lineaPresion(t: ModeloPresion.Tarjeta?): String? = when (t) {
    null, is ModeloPresion.Tarjeta.HoyListo -> null
    ModeloPresion.Tarjeta.Repetir -> MiSalud.REPETIR_PRESION
    ModeloPresion.Tarjeta.Preparar -> MiSalud.PREPARAR_PRESION
    is ModeloPresion.Tarjeta.Toma -> MiSalud.faltanTomas(t.faltan)
}

/** Lo que se sabe hoy, de lo que ya trajo la app: acá no se llama a nada. */
@Composable
fun estadoMiSalud(modelo: ModeloApp): EstadoMiSalud {
    val e = estadoDeEstudios(modelo)
    val presion by modelo.presion.collectAsStateWithLifecycle()
    val p = presion
    val estadoPresion = p?.estado?.collectAsStateWithLifecycle()?.value
    val localPresion = p?.local?.collectAsStateWithLifecycle()?.value
    val tarjetaPresion = remember(p, estadoPresion, localPresion) { p?.takeIf { estadoPresion != null }?.tarjeta }
    val controlCerca = hayControlCerca(modelo)
    val partes = MiSalud.Partes(control = e?.proximo != null, estudios = e != null, presion = estadoPresion != null)
    val pendientes = MiSalud.Pendientes(
        estudios = e?.let(Estudios::tarjetaInicio)?.titulo,
        control = controlCerca,
        presion = lineaPresion(tarjetaPresion),
    )
    return EstadoMiSalud(MiSalud.bloques(partes), MiSalud.tarjeta(partes, pendientes), e?.let(Estudios::tarjetaInicio), tarjetaPresion)
}

/**
 * Arriba de Entreno (simplificar, 11/11): en lugar de las tarjetas de presión, estudios y control, UNA sola «Mi salud», y
 * solo con algo para hacer. Verde como las viejas, con la línea de lo primero pendiente, el número de cosas y un botón
 * grande con el texto de siempre de esa cosa. Estudios y control llevan a su bloque de Mi salud; la presión, directo a la
 * toma (con Mi salud debajo), como la tarjeta vieja. Gemela de `TarjetaMiSaludInicio` de iOS.
 */
@Composable
fun TarjetaMiSaludInicioDe(modelo: ModeloApp, modifier: Modifier = Modifier) {
    val navegacion = LocalNavegacion.current
    val estado = estadoMiSalud(modelo)
    val t = estado.tarjeta?.takeIf { it.cuenta > 0 } ?: return
    val primero = t.bloque ?: return
    val boton: Pair<String, ImageVector> = when (primero) {
        // Sin pendiente de estudios, lo primero es el control cerca (sin bloque propio: va en Estudios).
        MiSalud.Bloque.ESTUDIOS -> estado.botonEstudios?.let { it.boton to (if (it.nueva) Iconos.FlechaDerecha else Iconos.FlechaArriba) }
            ?: (TextosControles.verMisEstudios to Iconos.FlechaDerecha)
        // Lleva al bloque «Próximo control» (con el control sin bloque propio, `bloque` es ESTUDIOS).
        MiSalud.Bloque.CONTROL -> MiSalud.VER_MI_CONTROL to Iconos.FlechaDerecha
        MiSalud.Bloque.PRESION -> when (estado.presion) {
            ModeloPresion.Tarjeta.Repetir -> TextosPresion.N.repetir
            ModeloPresion.Tarjeta.Preparar -> TextosPresion.N.empezar
            is ModeloPresion.Tarjeta.Toma -> TextosPresion.N.tomaDeHoy
            is ModeloPresion.Tarjeta.HoyListo, null -> null
        }?.let { it to Iconos.Corazon }
        MiSalud.Bloque.RECUPERACION -> null
        // Con algo para hacer, la tarjeta nunca se esconde por falta de botón: «Ver» abre Mi salud en ese bloque.
    } ?: ("Ver" to Iconos.FlechaDerecha)
    val ir = {
        when (primero) {
            MiSalud.Bloque.ESTUDIOS -> navegacion?.irAEstudios()
            MiSalud.Bloque.CONTROL -> navegacion?.irAControl()
            MiSalud.Bloque.PRESION -> if (estado.presion != null) navegacion?.irAPresion(true) else navegacion?.irAMiSalud(MiSalud.Bloque.PRESION)
            MiSalud.Bloque.RECUPERACION -> navegacion?.irAMiSalud(MiSalud.Bloque.RECUPERACION)
        }
        Unit
    }
    val apilada = LocalDensity.current.fontScale >= 1.5f
    val mas = MiSalud.masCosas(t.cuenta)
    Column(
        modifier = modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(Radio.tarjeta))
            .background(VerdeGuia)
            .clickable(onClickLabel = boton.first, role = Role.Button, onClick = ir)
            .testTag("tarjeta-mi-salud-inicio")
            .padding(Espacio.m + 2.dp),
        verticalArrangement = Arrangement.spacedBy(Espacio.s + 4.dp),
    ) {
        val insignia: @Composable () -> Unit = {
            Box(
                Modifier.defaultMinSize(minWidth = 32.dp, minHeight = 32.dp).clip(CircleShape).background(Color.White).padding(horizontal = 8.dp)
                    .clearAndSetSemantics {
                        contentDescription = if (t.cuenta == 1) "1 cosa para hacer" else "${t.cuenta} cosas para hacer"
                        testTag = "tarjeta-mi-salud-inicio-cuenta"
                    },
                contentAlignment = Alignment.Center,
            ) {
                Text("${t.cuenta}", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold, color = VerdeGuia, textAlign = TextAlign.Center)
            }
        }
        val icono: @Composable () -> Unit = {
            Box(Modifier.size(52.dp).clip(CircleShape).background(Color.White.copy(alpha = 0.2f)), contentAlignment = Alignment.Center) {
                Icon(Iconos.Corazon, contentDescription = null, tint = Color.White, modifier = Modifier.size(28.dp))
            }
        }
        val textos: @Composable (Modifier) -> Unit = { m ->
            Column(
                // TalkBack la lee de una, como encabezado: «Mi salud», la línea y si hay más.
                m.semantics(mergeDescendants = true) {
                    heading()
                    testTag = "tarjeta-mi-salud-inicio-texto"
                },
                verticalArrangement = Arrangement.spacedBy(2.dp),
            ) {
                Text(MiSalud.CEJA_INICIO.uppercase(), style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.Bold, letterSpacing = 0.08.em, color = Color.White)
                Text(t.linea, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold, color = Color.White)
                if (mas != null) Text(mas, style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.Medium, color = Color.White)
            }
        }
        // Con la letra muy grande, el ícono y el número arriba y el texto con todo el ancho.
        if (apilada) {
            Row(verticalAlignment = Alignment.CenterVertically) { icono(); Spacer(Modifier.weight(1f)); insignia() }
            textos(Modifier.fillMaxWidth())
        } else {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espacio.s + 4.dp)) {
                icono()
                textos(Modifier.weight(1f))
                insignia()
            }
        }
        Button(
            onClick = ir,
            modifier = Modifier.fillMaxWidth().defaultMinSize(minHeight = 52.dp).testTag("tarjeta-mi-salud-inicio-boton"),
            shape = CircleShape,
            colors = ButtonDefaults.buttonColors(containerColor = Color.White, contentColor = VerdeGuia),
            elevation = null,
        ) {
            Icon(boton.second, contentDescription = null, modifier = Modifier.size(20.dp))
            Text(boton.first, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center, modifier = Modifier.padding(start = Espacio.xs))
        }
    }
}

/** La tarjeta «Mi salud» de Revisión. Sin ningún bloque no existe. */
@Composable
fun TarjetaMiSaludDe(modelo: ModeloApp, alAbrir: (MiSalud.Bloque?) -> Unit, modifier: Modifier = Modifier) {
    val t = estadoMiSalud(modelo).tarjeta ?: return
    // Con algo pendiente lleva a eso (a la primera tarjeta nueva, en Estudios), como las tarjetas del inicio.
    TarjetaMiSalud(t, { alAbrir(t.bloque) }, modifier)
}

/**
 * Grande y fácil de ver (hay alumnos mayores): el corazón, «Mi salud», una línea y la flecha. Con algo pendiente, el
 * número en un círculo y la línea dice lo primero que hay para hacer; sin nada, qué hay adentro.
 */
@Composable
fun TarjetaMiSalud(t: MiSalud.Tarjeta, alAbrir: () -> Unit, modifier: Modifier = Modifier) {
    val c = MyPump.colores
    val forma = RoundedCornerShape(Radio.tarjeta)
    val conPendientes = t.cuenta > 0
    // TalkBack lee la tarjeta de una: «Mi salud», la línea y, si hay, cuántas cosas para hacer.
    val cuentaLeida = if (t.cuenta == 1) "1 cosa para hacer" else "${t.cuenta} cosas para hacer"
    Row(
        modifier
            .fillMaxWidth()
            .defaultMinSize(minHeight = 88.dp)
            .superficieTarjeta()
            .then(if (conPendientes) Modifier.border(2.dp, c.marcaVivo, forma) else Modifier)
            .clip(forma)
            .clickable(onClickLabel = MiSalud.ABRE, role = Role.Button, onClick = alAbrir)
            .semantics(mergeDescendants = true) {}
            .testTag("tarjeta-mi-salud")
            .padding(horizontal = Espacio.m, vertical = Espacio.m),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(Espacio.s + 4.dp),
    ) {
        AzulejoSuave(Iconos.Corazon, lado = 52.dp)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(MiSalud.TITULO, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold, color = c.texto)
            Text(
                t.linea,
                style = MaterialTheme.typography.bodyLarge,
                fontWeight = if (conPendientes) FontWeight.SemiBold else FontWeight.Normal,
                color = if (conPendientes) c.texto else c.apoyo,
                modifier = Modifier.testTag("tarjeta-mi-salud-linea"),
            )
        }
        if (conPendientes) {
            Box(
                Modifier.defaultMinSize(minWidth = 32.dp, minHeight = 32.dp).clip(CircleShape).background(c.marca).padding(horizontal = 8.dp)
                    .clearAndSetSemantics { contentDescription = cuentaLeida; testTag = "tarjeta-mi-salud-cuenta" },
                contentAlignment = Alignment.Center,
            ) {
                Text("${t.cuenta}", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold, color = c.sobreMarca, textAlign = TextAlign.Center)
            }
        }
        Icon(Iconos.Chevron, contentDescription = null, tint = c.textoTerciario, modifier = Modifier.size(20.dp))
    }
}

/**
 * La pantalla «Mi salud». Cuelga de Revisión (Atrás vuelve ahí). Si se llegó con un bloque pedido
 * ([Navegacion.anclaMiSalud]) se desplaza hasta él y lo consume; en Estudios, con [Navegacion.enfocarEstudios], hasta la
 * primera tarjeta nueva. La orden y el visor de Estudios se abren a pantalla completa; Presión, por encima de todo.
 */
@Composable
fun MiSaludPantalla(modelo: ModeloApp, navegacion: Navegacion, alVolver: () -> Unit) {
    val esDemo by modelo.esDemo.collectAsStateWithLifecycle()
    val modeloEstudios by modelo.estudios.collectAsStateWithLifecycle()
    val m = modeloEstudios?.takeIf { !esDemo }
    // Como al abrir Estudios: se le pregunta al servidor una vez al entrar.
    val preguntado = if (m != null) key(m) { sincronizarEstudios(m) } else true
    val e = estadoDeEstudios(modelo)
    if (m != null && e != null) {
        ConEstudios(m, e) { acciones -> Lista(modelo, navegacion, alVolver, m, e, acciones, preguntado) }
    } else {
        Lista(modelo, navegacion, alVolver, null, null, null, preguntado)
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun Lista(
    modelo: ModeloApp,
    navegacion: Navegacion,
    alVolver: () -> Unit,
    m: ModeloEstudios?,
    e: EstadoEstudios?,
    acciones: AccionesEstudios?,
    preguntado: Boolean,
) {
    val estado = estadoMiSalud(modelo)
    val salud by modelo.salud.collectAsStateWithLifecycle()
    val alcance = LocalAlcanceApp.current
    val desplazamiento = rememberScrollState()
    val reducir = reducirMovimiento()
    val margen = with(LocalDensity.current) { Espacio.m.roundToPx() }
    var recargando by remember { mutableStateOf(false) }
    // Dónde empieza cada bloque y la tarjeta nueva de Estudios, en el contenido (no cambia al desplazar).
    val lugares = remember { mutableStateMapOf<MiSalud.Bloque, Float>() }
    var yLista by remember { mutableStateOf(0f) }
    var yNuevaEstudios by remember { mutableStateOf<Float?>(null) }
    val preguntadoAhora by rememberUpdatedState(preguntado)

    val ancla = navegacion.anclaMiSalud
    LaunchedEffect(ancla) {
        if (ancla == null) return@LaunchedEffect
        var y = withTimeoutOrNull(ESPERA_BLOQUE_MS) { snapshotFlow { lugares[ancla] }.filterNotNull().first() }
        if (ancla == MiSalud.Bloque.ESTUDIOS && navegacion.enfocarEstudios) {
            // Recién con lo que contestó el servidor: la copia de antes puede no tener lo nuevo.
            withTimeoutOrNull(6_000) { snapshotFlow { preguntadoAhora }.first { it } }
            delay(150)
            y = yNuevaEstudios ?: y
            navegacion.enfocarEstudios = false
        }
        if (y != null) {
            val destino = ((y - yLista).toInt() - margen).coerceAtLeast(0)
            if (reducir) desplazamiento.scrollTo(destino) else desplazamiento.animateScrollTo(destino)
        }
        navegacion.anclaMiSalud = null
    }
    fun Modifier.bloque(b: MiSalud.Bloque): Modifier =
        onGloballyPositioned { lugares[b] = it.positionInRoot().y + desplazamiento.value }.testTag(b.etiqueta)

    MarcoPantalla(MiSalud.TITULO, alVolver = alVolver) { relleno ->
        PullToRefreshBox(
            isRefreshing = recargando,
            onRefresh = {
                recargando = true
                alcance.launch {
                    try {
                        coroutineScope {
                            // Cada uno respeta su palanca: apagada, no llama a nada.
                            m?.let { launch { it.sincronizar() } }
                            modelo.presion.value?.let { launch { it.refrescar() } }
                        }
                    } finally {
                        recargando = false
                    }
                }
            },
            modifier = Modifier.fillMaxSize().padding(top = relleno.calculateTopPadding()).onGloballyPositioned { yLista = it.positionInRoot().y },
        ) {
            Column(
                Modifier.fillMaxSize().verticalScroll(desplazamiento).testTag("mi-salud-pantalla"),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Column(
                    Modifier
                        .widthIn(max = AnchoLectura)
                        .fillMaxWidth()
                        .padding(horizontal = Espacio.m)
                        .padding(top = Espacio.xs, bottom = Espacio.xl + rellenoInferior()),
                    verticalArrangement = Arrangement.spacedBy(Espacio.xl),
                ) {
                    for (b in estado.bloques) {
                        when (b) {
                            MiSalud.Bloque.CONTROL -> e?.proximo?.let { p -> Box(Modifier.bloque(b)) { ProximoControl(p) } }
                            MiSalud.Bloque.ESTUDIOS -> if (m != null && e != null && acciones != null) {
                                Column(Modifier.bloque(b), verticalArrangement = Arrangement.spacedBy(Espacio.m)) {
                                    EncabezadoSeccion(TextosEstudios.entrada)
                                    ContenidoEstudios(
                                        m, e, acciones,
                                        conProximo = false,
                                        alUbicarAncla = { yNuevaEstudios = it + desplazamiento.value },
                                    )
                                }
                            }
                            MiSalud.Bloque.PRESION -> Column(Modifier.bloque(b), verticalArrangement = Arrangement.spacedBy(Espacio.m)) {
                                TarjetaPresionDe(modelo, enMiSalud = true)
                                Column(Modifier.fillMaxWidth().superficieTarjeta()) {
                                    FilaDestino(
                                        Iconos.Corazon, TextosPresion.N.entrada, MiSalud.VER_PRESION,
                                        alTocar = { navegacion.abrirPresion(directo = false) },
                                        modifier = Modifier.testTag("mi-salud-presion"),
                                    )
                                }
                            }
                            MiSalud.Bloque.RECUPERACION -> Column(Modifier.bloque(b).fillMaxWidth().superficieTarjeta()) {
                                TarjetaRecuperacionRevision(salud, alAbrirSalud = { navegacion.irASalud(SegmentoSalud.RECUPERACION, desdeMiSalud = true) })
                            }
                        }
                    }
                }
            }
        }
    }
}
