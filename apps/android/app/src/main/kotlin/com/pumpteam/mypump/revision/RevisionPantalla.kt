package com.pumpteam.mypump.revision

import androidx.compose.foundation.ScrollState
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionInParent
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.pumpteam.mypump.datos.ModeloApp
import com.pumpteam.mypump.diseno.rellenoInferior
import com.pumpteam.mypump.diseno.sinAbajo
import com.pumpteam.mypump.diseno.AnchoLectura
import com.pumpteam.mypump.diseno.Espacio
import com.pumpteam.mypump.diseno.Iconos
import com.pumpteam.mypump.diseno.MarcoPantalla
import com.pumpteam.mypump.diseno.MyPump
import com.pumpteam.mypump.diseno.Radio
import com.pumpteam.mypump.raiz.AnclaRevision
import com.pumpteam.mypump.respaldo.OrigenRespaldo
import com.pumpteam.mypump.respaldo.PieRespaldo
import com.pumpteam.mypump.salud.CardSalud
import com.pumpteam.mypump.salud.CardRecuperacion
import com.pumpteam.mypump.raiz.LocalAlcanceApp
import com.pumpteam.mypump.raiz.LocalNavegacion
import com.pumpteam.mypump.reglas.PesoCorporal
import com.pumpteam.mypump.salud.PantallaSuperpuesta
import com.pumpteam.mypump.salud.SaludDetallePantalla
import java.time.DayOfWeek
import java.time.LocalDate
import java.time.temporal.TemporalAdjusters
import kotlin.math.abs
import kotlin.math.roundToInt
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * Revisión (gemela de `RevisionView.swift`): lo de la semana (fotos, check, peso), Mi reloj y, al final, Mi Día (lo de
 * todos los días, con la recuperación y la salud). Mismo orden que la web (REV-01). Arriba, el aviso de plan incompleto
 * (GEN-05); de acá cuelga Mis datos (el ícono de arriba).
 *
 * Tirar para actualizar trae el check, el peso, Mi Día, las fotos y la salud. Un aviso, el banner de las otras pestañas
 * o `?scene=myday` piden una sección ([AnclaRevision]): se desplaza hasta ella y se consume. En la demo el check, el
 * peso y Mi Día se tocan igual y no sale nada; las fotos dicen que no se guardan, y sin cuenta no hay reloj ni salud.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun RevisionPantalla(modelo: ModeloApp, alAbrirMisDatos: () -> Unit) {
    val revision by modelo.revision.collectAsStateWithLifecycle()
    val fotos by modelo.fotos.collectAsStateWithLifecycle()
    val salud by modelo.salud.collectAsStateWithLifecycle()
    val esDemo by modelo.esDemo.collectAsStateWithLifecycle()
    val filasDePeso = revision?.salud?.collectAsStateWithLifecycle()?.value ?: emptyList()
    val pesoParaLasFotos = remember(filasDePeso) { PesoCorporal.serie(filasDePeso) }
    val alcance = LocalAlcanceApp.current
    val navegacion = LocalNavegacion.current
    val desplazamiento = rememberScrollState()
    // Dónde empieza cada sección dentro de lo que se desplaza (para las anclas). No es estado de Compose: nadie lo lee
    // al componer, y se anota en cada cuadro del desplazamiento.
    val secciones = remember { HashMap<String, Float>() }
    var recargando by remember { mutableStateOf(false) }
    var detalleSalud by rememberSaveable { mutableStateOf(false) }
    val margen = with(LocalDensity.current) { Espacio.xs.toPx() }

    // Un aviso o el banner de las otras pestañas piden una sección: se va y se consume.
    val ancla = navegacion?.anclaRevision
    LaunchedEffect(ancla) {
        if (ancla == null) return@LaunchedEffect
        delay(300)
        irA(ancla, secciones, desplazamiento, margen)
        navegacion.anclaRevision = null
    }

    MarcoPantalla(
        "Revisión",
        acciones = {
            IconButton(onClick = alAbrirMisDatos, modifier = Modifier.testTag("mis-datos")) {
                Icon(Iconos.Persona, contentDescription = "Mis datos", modifier = Modifier.size(28.dp))
            }
        },
    ) { relleno ->
        PullToRefreshBox(
            isRefreshing = recargando,
            onRefresh = {
                // Sin cuenta no hay nada que traer (la demo no toca la red).
                if (esDemo) return@PullToRefreshBox
                recargando = true
                alcance.launch {
                    try {
                        coroutineScope {
                            launch { revision?.cargarRevision() }
                            launch { fotos?.cargar() }
                            launch { salud?.cargar() }
                        }
                    } finally {
                        recargando = false
                    }
                }
            },
            modifier = Modifier.padding(relleno.sinAbajo()).fillMaxSize(),
        ) {
            Column(
                // Con el teclado abierto (la nota del check, el peso) lo que se desplaza se achica y el campo queda a la vista.
                Modifier.fillMaxSize().imePadding().verticalScroll(desplazamiento).testTag("revision-lista"),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Column(
                    Modifier
                        .widthIn(max = AnchoLectura)
                        .fillMaxWidth()
                        .padding(horizontal = Espacio.m)
                        // Al final, lo que tapa la barra de pestañas flotante (con el teclado abierto, nada: la tapa él).
                        .padding(bottom = Espacio.xl + rellenoInferior()),
                    verticalArrangement = Arrangement.spacedBy(Espacio.xl),
                ) {
                    Column(verticalArrangement = Arrangement.spacedBy(Espacio.m)) {
                        Text(
                            semanaActual(),
                            style = MaterialTheme.typography.bodyMedium,
                            color = MyPump.colores.textoSecundario,
                            modifier = Modifier.padding(horizontal = 4.dp),
                        )
                        AvisoPlanIncompleto(modelo)
                    }
                    FotosSemana(fotos, pesoParaLasFotos, Modifier.seccion(AnclaRevision.FOTOS, secciones))
                    CheckSemanal(revision, Modifier.seccion(AnclaRevision.CHECK, secciones))
                    PesoTarjeta(revision, Modifier.seccion(AnclaRevision.PESO, secciones))
                    // Oura y WHOOP según lo que ofrezca el servidor (sin relojes para ofrecer, no ocupa lugar). Sin cuenta no hay.
                    salud?.let { MiReloj(it, Modifier.seccion(AnclaRevision.RELOJ, secciones)) }
                    // La recuperación y la salud. Mi día (la racha, el entrenamiento del día, los hábitos, el agua y los
                    // últimos 30 días) se sacó el 15-oct: nadie lo usaba (Mati). Conserva el ancla: los avisos y links que
                    // llevaban a Mi día caen acá.
                    salud?.let { s ->
                        Column(Modifier.seccion(AnclaRevision.MI_DIA, secciones), verticalArrangement = Arrangement.spacedBy(Espacio.m)) {
                            CardRecuperacion(s, alVerTodo = { detalleSalud = true })
                            CardSalud(s)
                        }
                    }
                    PieRespaldo(OrigenRespaldo.MI_DIA)
                }
            }
        }
    }

    val s = salud
    if (detalleSalud && s != null) {
        PantallaSuperpuesta(alCerrar = { detalleSalud = false }) {
            SaludDetallePantalla(s, alVolver = { detalleSalud = false })
        }
    }
}

/** Anota dónde empieza la sección (dentro de lo que se desplaza) y la deja encontrar en las pruebas (`seccion-check`). */
private fun Modifier.seccion(clave: String, secciones: HashMap<String, Float>): Modifier =
    this
        .onGloballyPositioned { secciones[clave] = it.positionInParent().y }
        .testTag("seccion-$clave")

/**
 * Desplaza hasta la sección, arriba de todo (el `scrollTo(anchor: .top)` de iOS). Si lo de arriba todavía estaba
 * cargando y la sección se movió (el gráfico del peso, el check), se corrige una vez, salvo que el cliente ya se haya
 * movido solo.
 */
private suspend fun irA(ancla: String, secciones: Map<String, Float>, desplazamiento: ScrollState, margen: Float) {
    val y = secciones[ancla] ?: return
    desplazamiento.animateScrollTo((y - margen).roundToInt().coerceAtLeast(0))
    val dejado = desplazamiento.value
    delay(700)
    val ahora = secciones[ancla] ?: return
    if (abs(ahora - y) > margen && desplazamiento.value == dejado && !desplazamiento.isScrollInProgress) {
        desplazamiento.animateScrollTo((ahora - margen).roundToInt().coerceAtLeast(0))
    }
}

/**
 * GEN-05 (`avisarPlanIncompleto`): al plan publicado le falta algo. No es para el cliente sino para la captura que le
 * manda a Mati (qué republicar): discreto, con el detalle chico y gris.
 */
@Composable
fun AvisoPlanIncompleto(modelo: ModeloApp, modifier: Modifier = Modifier) {
    val entreno by modelo.entreno.collectAsStateWithLifecycle()
    val esDemo by modelo.esDemo.collectAsStateWithLifecycle()
    // Lo que mira `avisoPlanIncompleto`: los problemas de la dieta y los de la rutina (se leen para recomponer).
    val problemasDieta by modelo.problemasDieta.collectAsStateWithLifecycle()
    val problemasRutina = entreno?.problemas?.collectAsStateWithLifecycle()?.value
    if (esDemo || (problemasDieta.isEmpty() && problemasRutina.isNullOrEmpty())) return
    val aviso = modelo.avisoPlanIncompleto ?: return
    val c = MyPump.colores
    Row(
        modifier = modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(Radio.control + 4.dp))
            .background(c.alerta.copy(alpha = 0.10f))
            .padding(Espacio.m)
            .semantics(mergeDescendants = true) {}
            .testTag("aviso-plan-incompleto"),
        horizontalArrangement = Arrangement.spacedBy(Espacio.s),
    ) {
        Icon(Iconos.Alerta, contentDescription = null, tint = c.alerta, modifier = Modifier.size(20.dp))
        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(aviso.first, style = MaterialTheme.typography.bodyMedium)
            Text(aviso.second, style = MaterialTheme.typography.bodySmall, color = c.textoSecundario)
        }
    }
}

private val MESES = listOf(
    "enero", "febrero", "marzo", "abril", "mayo", "junio", "julio", "agosto", "septiembre", "octubre", "noviembre", "diciembre",
)

/** "Semana del 12 al 18 de octubre" (de lunes a domingo); si cambia el mes, "Semana del 28 de septiembre al 4 de octubre". */
fun semanaActual(hoy: LocalDate = LocalDate.now()): String {
    val lunes = hoy.with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY))
    val domingo = lunes.plusDays(6)
    val desde = if (lunes.month == domingo.month) "${lunes.dayOfMonth}" else "${lunes.dayOfMonth} de ${MESES[lunes.monthValue - 1]}"
    return "Semana del $desde al ${domingo.dayOfMonth} de ${MESES[domingo.monthValue - 1]}"
}
