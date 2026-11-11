package com.pumpteam.mypump.revision

import androidx.compose.foundation.ScrollState
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.LayoutCoordinates
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.pumpteam.mypump.datos.ModeloApp
import com.pumpteam.mypump.datos.ModeloRevision
import com.pumpteam.mypump.datos.ModeloSalud
import com.pumpteam.mypump.diseno.AnchoLectura
import com.pumpteam.mypump.diseno.Espacio
import com.pumpteam.mypump.diseno.Iconos
import com.pumpteam.mypump.diseno.MarcoPantalla
import com.pumpteam.mypump.diseno.Letra
import com.pumpteam.mypump.diseno.MyPump
import com.pumpteam.mypump.diseno.apoyo
import com.pumpteam.mypump.diseno.Radio
import com.pumpteam.mypump.diseno.rellenoInferior
import com.pumpteam.mypump.diseno.sinAbajo
import com.pumpteam.mypump.diseno.vidrio
import com.pumpteam.mypump.fotosinicio.TarjetaFotosInicioDe
import com.pumpteam.mypump.raiz.AnclaRevision
import com.pumpteam.mypump.raiz.LocalAlcanceApp
import com.pumpteam.mypump.raiz.LocalNavegacion
import com.pumpteam.mypump.raiz.diaDeRevision
import com.pumpteam.mypump.reglas.FotosProgreso
import com.pumpteam.mypump.reglas.PesoCorporal
import com.pumpteam.mypump.reglas.SemanaRevision
import java.time.DayOfWeek
import java.time.LocalDate
import java.time.temporal.TemporalAdjusters
import kotlin.math.abs
import kotlin.math.roundToInt
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull

/**
 * Revisión (gemela de `RevisionView.swift`): arriba de todo la devolución de Mati si hay una publicada (2.3.0); después las tarjetas Recuperación y Tu progreso, que abren Salud (2.1.0, «Salud dentro
 * de Revisión»: Salud dejó de ser pestaña); después el aviso del plan incompleto (GEN-05), las fotos de la semana y el
 * check (que ya trae el peso del día y, arriba del botón, «Tu salud, últimos 7 días»). De acá cuelgan Mis datos (el ícono
 * de arriba) y Salud.
 *
 * Tirar para actualizar trae el check y las fotos. Un aviso o el banner de las otras pestañas piden una sección
 * ([AnclaRevision]): se desplaza hasta ella y se consume. En la demo el check se toca igual y no sale nada; las fotos
 * dicen que no se guardan.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun RevisionPantalla(
    modelo: ModeloApp,
    alAbrirMisDatos: () -> Unit,
    alAbrirMiSalud: (com.pumpteam.mypump.reglas.MiSalud.Bloque?) -> Unit,
    alAbrirFuerza: () -> Unit,
    alVerNovedades: () -> Unit = {},
) {
    val revision by modelo.revision.collectAsStateWithLifecycle()
    val salud by modelo.salud.collectAsStateWithLifecycle()
    val fotos by modelo.fotos.collectAsStateWithLifecycle()
    val esDemo by modelo.esDemo.collectAsStateWithLifecycle()
    val modeloDevolucion by modelo.devolucion.collectAsStateWithLifecycle()
    val devolucion = modeloDevolucion?.estado?.collectAsStateWithLifecycle()?.value
    val demoHistorial by modelo.demoHistorial.collectAsStateWithLifecycle()
    val filasDePeso = revision?.salud?.collectAsStateWithLifecycle()?.value ?: emptyList()
    val pesoParaLasFotos = remember(filasDePeso) { PesoCorporal.serie(filasDePeso) }
    // U1 (auditoría del 10/11): con la semana a medias, las fotos y el check van arriba (antes quedaban fuera de la primera
    // pantalla). La demo sigue con el orden de siempre.
    val checkin = revision?.checkin?.collectAsStateWithLifecycle()?.value
    val fotosHechas = fotos?.fotos?.collectAsStateWithLifecycle()?.value ?: emptyList()
    val fotosEnCola = fotos?.pendientes?.collectAsStateWithLifecycle()?.value ?: emptyMap()
    val semanaPendiente = remember(revision, fotos, checkin, fotosHechas, fotosEnCola, esDemo) {
        val f = fotos
        val r = revision
        !esDemo && f != null && r != null && FotosProgreso.pendientes(
            r.checkinEnviado,
            FotosProgreso.posesDeLaSemana(fotosHechas, fotosEnCola.values.map { it.pose to it.fecha }, f.semanaActual),
        ).total > 0
    }
    val alcance = LocalAlcanceApp.current
    val navegacion = LocalNavegacion.current
    val desplazamiento = rememberScrollState()
    // Dónde está cada sección y lo que se desplaza (para las anclas). No es estado de Compose: nadie lo lee al componer.
    val secciones = remember { Secciones() }
    var recargando by remember { mutableStateOf(false) }
    // Check guiado (2.3.0): con la palanca `check_guiado` prendida, la sección del check es la tarjeta que abre el check de
    // un paso por pantalla. Apagada (o en la demo), todo lo de abajo queda como siempre.
    val conCheckGuiado = !esDemo && (revision?.guiadoPrendido?.collectAsStateWithLifecycle()?.value ?: false)
    // Si está abierto lo sabe el modelo: una recreación de la Activity no lo cierra.
    val flujoGuiado = revision?.flujoGuiado?.collectAsStateWithLifecycle()?.value
    val revisionDeAhora by rememberUpdatedState(revision)
    val conCheckGuiadoAhora by rememberUpdatedState(conCheckGuiado)
    // Con cuenta y la salud del sistema conectada: los últimos días al servidor, sin esperar ni frenar el envío del check.
    val sincronizarSaludAlEnviar = {
        val s = salud
        if (!esDemo && s != null && s.conectado.value) alcance.launch { s.sincronizar() }
        Unit
    }
    val margen = with(LocalDensity.current) { Espacio.xs.toPx() }
    // «Tu cambio»: con cuenta y con la palanca `check_guiado`. Apagada, nada de esto existe (ni se lee nada).
    val inicio by modelo.fotosInicio.collectAsStateWithLifecycle()
    val fotosDeLaCuenta = fotos
    // Con `fotos_inicio` apagada no se mira nada de esa sección, tampoco lo que quedó en el teléfono.
    val inicioHabilitado = inicio?.estado?.collectAsStateWithLifecycle()?.value != null
    val tuCambio = if (conCheckGuiado && fotosDeLaCuenta != null) recordarFuentesTuCambio(fotosDeLaCuenta, inicio?.takeIf { inicioHabilitado }, pesoParaLasFotos) else null

    // Un aviso o el banner de las otras pestañas piden una sección: se va y se consume.
    val ancla = navegacion?.anclaRevision
    LaunchedEffect(ancla) {
        if (ancla == null) return@LaunchedEffect
        delay(300)
        val abreElCheck = ancla == AnclaRevision.CHECK || ancla == AnclaRevision.AVISO || ancla == AnclaRevision.PENDIENTES
        when (ancla) {
            AnclaRevision.AVISO -> Unit
            AnclaRevision.PENDIENTES ->
                irA(if (conCheckGuiadoAhora) AnclaRevision.CHECK else AnclaRevision.FOTOS, secciones, desplazamiento, margen)
            else -> irA(ancla, secciones, desplazamiento, margen)
        }
        // Con el check guiado, el aviso y el banner llevan directo: además de mostrar la tarjeta, abren el check en el paso
        // que toca. Se espera (poco) a saber si ya se envió: enviado, solo se muestra la tarjeta.
        val r = revisionDeAhora
        if (abreElCheck && conCheckGuiadoAhora && r != null) {
            withTimeoutOrNull(4_000) { r.revisionCargada.first { it } }
            if (conCheckGuiadoAhora && !r.checkinEnviado) r.abrirFlujoGuiado()
        }
        navegacion.anclaRevision = null
    }

    MarcoPantalla(
        "Revisión",
        subtitulo = semanaActual(),
        acciones = {
            // «Mis datos» con texto (simplificar, 11/11): un dibujito solo no se entiende como puerta. La píldora de vidrio de
            // iOS 26 (la misma de volver), con el ícono y la palabra.
            Row(
                Modifier
                    .padding(end = Espacio.s)
                    .defaultMinSize(minHeight = 48.dp)
                    .vidrio(CircleShape, elevacion = 6.dp)
                    .clickable(role = Role.Button, onClick = alAbrirMisDatos)
                    .semantics(mergeDescendants = true) {}
                    .testTag("mis-datos")
                    .padding(horizontal = Espacio.m - 2.dp, vertical = Espacio.xs),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(Espacio.xs),
            ) {
                Icon(Iconos.Persona, contentDescription = null, tint = MyPump.colores.marcaTexto, modifier = Modifier.size(24.dp))
                Text("Mis datos", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold, color = MyPump.colores.marcaTexto, maxLines = 1)
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
                            modeloDevolucion?.takeIf { it.palancaRecordada }?.let { d -> launch { d.refrescar() } }
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
                        // Lo que se desplaza: las anclas se miden contra esto (algunas secciones van en una columna interna).
                        .onGloballyPositioned { secciones.contenido = it }
                        .widthIn(max = AnchoLectura)
                        .fillMaxWidth()
                        .padding(horizontal = Espacio.m)
                        // Al final, lo que tapa la barra de pestañas flotante (con el teclado abierto, nada: la tapa él).
                        .padding(bottom = Espacio.xl + rellenoInferior()),
                    verticalArrangement = Arrangement.spacedBy(Espacio.xl),
                ) {
                    // La explicación de la semana va bajo el título: es contexto de toda la pantalla (entre tarjetas parecía un
                    // párrafo suelto). Pegada a lo que sigue.
                    Text(
                        SemanaRevision.EXPLICACION,
                        style = Letra.apoyo,
                        color = MyPump.colores.apoyo,
                        modifier = Modifier.padding(horizontal = 4.dp).testTag("nota-revision-semanal"),
                    )
                    // «Mi salud» (2.3.0, pedido de Mati del 11/11): arriba, grande, con lo pendiente. Sin ningún bloque, no está.
                    com.pumpteam.mypump.misalud.TarjetaMiSaludDe(modelo, alAbrirMiSalud)
                    // Fotos de inicio: arriba de todo, solo con la sección habilitada para esta cuenta. El orden de iOS: fotos
                    // de inicio, devolución, check guiado y el resto.
                    TarjetaFotosInicioDe(modelo)
                    // La devolución de Mati, arriba de todo. Apagada (el modelo queda sin estado) o sin ninguna publicada, no hay nada.
                    // En la demo con historial, las inventadas (nunca las de una cuenta).
                    val devoluciones = if (esDemo) demoHistorial?.devoluciones else devolucion
                    val ultima = devoluciones?.ultima
                    if (ultima != null) TarjetaDevolucion(ultima, devoluciones.anteriores)
                    // «Lo último que cambió en tu plan» (simplificar, 11/11): debajo de la devolución, con «Ver todo». Cada
                    // parte con su palanca (`devolucion_semanal`, `novedades_plan`): con una sola, solo esa.
                    com.pumpteam.mypump.novedades.NovedadesEnRevision(modelo, alVerNovedades)
                    // Con el check guiado, la tarjeta del check es lo primero de Revisión, siempre: fácil de encontrar.
                    val conTarjeta = revision?.takeIf { conCheckGuiado }
                    if (conTarjeta != null) {
                        CheckGuiadoTarjeta(conTarjeta, fotos, Modifier.seccion(AnclaRevision.CHECK, secciones)) { paso ->
                            conTarjeta.abrirFlujoGuiado(paso)
                        }
                        // «Tu cambio» (pedido de Mati del 11/11): siempre a la vista, debajo del check.
                        tuCambio?.let { TarjetaTuCambio(it) }
                    }
                    Column(verticalArrangement = Arrangement.spacedBy(Espacio.m)) {
                        // Quien revisa otro día que el domingo lo ve acá (el dato lo carga el equipo).
                        SemanaRevision.textoDia(diaDeRevision(modelo))?.let {
                            Text(
                                it,
                                style = MaterialTheme.typography.bodyMedium,
                                color = MyPump.colores.textoSecundario,
                                modifier = Modifier.testTag("dia-de-revision"),
                            )
                        }
                        if (semanaPendiente) {
                            AvisoPlanIncompleto(modelo)
                            FotosSemana(fotos, pesoParaLasFotos, Modifier.seccion(AnclaRevision.FOTOS, secciones), tuCambio)
                            if (conTarjeta == null) Check(revision, salud, esDemo, alcance, secciones)
                        }
                        // El progreso (la recuperación se mudó a Mi salud en la 2.3.0).
                        TarjetaComoVengo(modelo, alAbrirFuerza)
                        if (!semanaPendiente) AvisoPlanIncompleto(modelo)
                    }
                    if (!semanaPendiente) {
                        FotosSemana(fotos, pesoParaLasFotos, Modifier.seccion(AnclaRevision.FOTOS, secciones), tuCambio)
                        if (conTarjeta == null) Check(revision, salud, esDemo, alcance, secciones)
                    }
                }
            }
        }
    }

    val r = revision
    if (conCheckGuiado && flujoGuiado != null && r != null) {
        CheckGuiadoFlujo(
            revision = r,
            fotos = fotos,
            salud = filasSaludSemana(salud),
            pasoInicial = flujoGuiado.paso,
            tuCambio = tuCambio,
            alEnviar = sincronizarSaludAlEnviar,
            alCerrar = { r.cerrarFlujoGuiado() },
        )
    }
}

@Composable
private fun Check(revision: ModeloRevision?, salud: ModeloSalud?, esDemo: Boolean, alcance: CoroutineScope, secciones: Secciones) {
    CheckSemanal(
        revision,
        Modifier.seccion(AnclaRevision.CHECK, secciones),
        salud = filasSaludSemana(salud),
        alEnviar = {
            // Con cuenta y la salud del sistema conectada: los últimos días al servidor, sin esperar ni frenar el envío del
            // check.
            if (!esDemo && salud != null && salud.conectado.value) alcance.launch { salud.sincronizar() }
        },
    )
}

/**
 * Las secciones con ancla y lo que se desplaza. La altura se mide contra el contenido de la lista (no contra el padre
 * directo: con la semana pendiente, fotos y check van en una columna interna, debajo de la devolución y del check guiado).
 */
private class Secciones {
    var contenido: LayoutCoordinates? = null
    val lugares = HashMap<String, LayoutCoordinates>()

    /** Dónde empieza la sección dentro de lo que se desplaza (no cambia al desplazar). */
    fun y(clave: String): Float? {
        val c = contenido?.takeIf { it.isAttached } ?: return null
        val l = lugares[clave]?.takeIf { it.isAttached } ?: return null
        return c.localPositionOf(l, Offset.Zero).y
    }
}

/** Anota dónde está la sección y la deja encontrar en las pruebas (`seccion-check`). */
private fun Modifier.seccion(clave: String, secciones: Secciones): Modifier =
    this
        .onGloballyPositioned { secciones.lugares[clave] = it }
        .testTag("seccion-$clave")

/**
 * Desplaza hasta la sección, arriba de todo (el `scrollTo(anchor: .top)` de iOS). Si lo de arriba todavía estaba
 * cargando y la sección se movió (el gráfico del peso, el check), se corrige una vez, salvo que el cliente ya se haya
 * movido solo.
 */
private suspend fun irA(ancla: String, secciones: Secciones, desplazamiento: ScrollState, margen: Float) {
    val y = secciones.y(ancla) ?: return
    desplazamiento.animateScrollTo((y - margen).roundToInt().coerceAtLeast(0))
    val dejado = desplazamiento.value
    delay(700)
    val ahora = secciones.y(ancla) ?: return
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
