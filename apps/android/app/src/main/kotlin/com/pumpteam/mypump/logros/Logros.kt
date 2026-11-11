package com.pumpteam.mypump.logros

import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.paneTitle
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTagsAsResourceId
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.pumpteam.mypump.datos.ModeloApp
import com.pumpteam.mypump.datos.ModeloEntreno
import com.pumpteam.mypump.diseno.AnchoLectura
import com.pumpteam.mypump.diseno.AsaHoja
import com.pumpteam.mypump.diseno.BotonMarca
import com.pumpteam.mypump.diseno.BotonSecundario
import com.pumpteam.mypump.diseno.Espacio
import com.pumpteam.mypump.diseno.FormaHoja
import com.pumpteam.mypump.diseno.IconoAzulejo
import com.pumpteam.mypump.diseno.Iconos
import com.pumpteam.mypump.diseno.Interruptor
import com.pumpteam.mypump.diseno.MyPump
import com.pumpteam.mypump.diseno.Numeros
import com.pumpteam.mypump.diseno.Oro
import com.pumpteam.mypump.diseno.PieSeccion
import com.pumpteam.mypump.diseno.Radio
import com.pumpteam.mypump.diseno.RotuloSeccion
import com.pumpteam.mypump.diseno.superficieTarjeta
import com.pumpteam.mypump.entreno.NombreEjercicio
import com.pumpteam.mypump.entreno.reducirMovimiento
import com.pumpteam.mypump.raiz.LocalAlcanceApp
import com.pumpteam.mypump.reglas.ReglasWins
import kotlinx.coroutines.launch

// «Récords y logros» (2.3.0, palanca `wins_app`; gemelo de LogrosVistas.swift). Los textos son los de
// `apps/shared/vectores/wins.json` (`ReglasWins`).
// · El festejo: después de «Confirmar y cerrar», si hubo récords en el día, se abre solo. Cuelga de la raíz y no de la hoja
//   de cierre, que para entonces ya se fue.
// · El permiso (explícito): «Contarle a Mati» abre la hoja; con el sí, los récords del festejo quedan en la cola.
// · La app nunca publica nada: solo deja el logro para que Mati lo vea.

/** El festejo que espera a que se cierre la hoja de «Cerrar sesión de hoy» y el que se está mostrando. */
object EstadoFestejo {
    /** Los récords del cierre que acaba de salir bien (los deja `HojaCerrarDia`). */
    var pendientes: List<ReglasWins.Record> = emptyList()

    var mostrando by mutableStateOf<List<ReglasWins.Record>?>(null)

    /** La hoja de cierre ya se fue: ahora sí se puede presentar el festejo. */
    fun alCerrarseLaHoja() {
        if (pendientes.isEmpty()) return
        mostrando = pendientes
        pendientes = emptyList()
    }

    fun soltar() {
        pendientes = emptyList()
        mostrando = null
    }
}

object WinsUI {
    /**
     * ¿Se festeja? Con cuenta, con la palanca y el servidor activos (lo recuerda `ModeloWins`, así anda sin red en el
     * gimnasio). En la demo con historial, siempre (sin palanca, y sin mandar nada).
     */
    fun activo(m: ModeloApp): Boolean =
        if (m.esDemo.value) m.demoHistorial.value != null else m.wins.value?.prendida == true

    /** Los récords de hoy para festejar al cerrar [motor], o ninguno si no se festeja. Se miran ANTES de cerrar el día. */
    fun recordsAlCerrar(m: ModeloApp, motor: ModeloEntreno): List<ReglasWins.Record> =
        if (m.entreno.value === motor && activo(m)) motor.recordsDeHoy() else emptyList()
}

/** En la raíz, arriba de las pestañas: presenta el festejo cuando hay uno. */
@Composable
fun FestejoRaiz(modelo: ModeloApp, esperar: Boolean = false) {
    val records = EstadoFestejo.mostrando ?: return
    // Con una pregunta de Entreno abierta («¡Día completado!», avanzar de semana) el festejo espera: sale cuando se
    // contesta, sin taparla. Una vez abierto, ya no se esconde.
    var abierto by remember(records) { mutableStateOf(false) }
    LaunchedEffect(records, esperar) { if (!esperar) abierto = true }
    if (!abierto) return
    // Con la palanca apagada (o la cuenta que cambió) no se festeja nada.
    if (!WinsUI.activo(modelo)) {
        LaunchedEffect(Unit) { EstadoFestejo.soltar() }
        return
    }
    HojaFestejo(modelo, records, alCerrar = { EstadoFestejo.mostrando = null })
}

// ── El festejo ──

@OptIn(ExperimentalMaterial3Api::class, ExperimentalComposeUiApi::class)
@Composable
fun HojaFestejo(modelo: ModeloApp, records: List<ReglasWins.Record>, alCerrar: () -> Unit) {
    val c = MyPump.colores
    val hoja = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val alcanceHoja = rememberCoroutineScope()
    val haptico = LocalHapticFeedback.current
    val reducir = reducirMovimiento()
    val esDemo by modelo.esDemo.collectAsStateWithLifecycle()
    val wins = modelo.wins.collectAsStateWithLifecycle().value?.takeIf { !esDemo }
    val estado = wins?.estado?.collectAsStateWithLifecycle()?.value
    val conPermiso = estado?.permiso == true
    val n = records.size
    var entro by remember { mutableStateOf(false) }
    var pidiendoPermiso by remember { mutableStateOf(false) }
    var avisoDemo by remember { mutableStateOf(false) }

    LaunchedEffect(Unit) {
        // Con el permiso ya dado, los récords quedan en la cola al aparecer (sin permiso no se encola nada).
        wins?.encolar(records)
        haptico.performHapticFeedback(HapticFeedbackType.Confirm)
        entro = true
    }

    fun cerrar() {
        alcanceHoja.launch { hoja.hide() }.invokeOnCompletion { alCerrar() }
    }

    ModalBottomSheet(
        onDismissRequest = alCerrar,
        sheetState = hoja,
        shape = FormaHoja,
        containerColor = c.fondo,
        tonalElevation = 0.dp,
        dragHandle = { AsaHoja() },
        modifier = Modifier.semantics { testTagsAsResourceId = true; paneTitle = ReglasWins.titulo(n) }.testTag("hoja-festejo"),
    ) {
        Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
            Column(
                Modifier
                    .weight(1f, fill = false)
                    .verticalScroll(rememberScrollState())
                    .widthIn(max = AnchoLectura)
                    .fillMaxWidth()
                    .padding(horizontal = Espacio.m)
                    .padding(top = Espacio.l, bottom = Espacio.m),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(Espacio.l),
            ) {
                Trofeo(entro, reducir)
                Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(Espacio.xs)) {
                    Text(
                        ReglasWins.titulo(n),
                        style = Numeros.gigante.copy(fontSize = 38.sp, lineHeight = 44.sp),
                        color = c.marcaTexto,
                        textAlign = TextAlign.Center,
                        modifier = Modifier.semantics { heading(); liveRegion = LiveRegionMode.Polite }.testTag("festejo-titulo"),
                    )
                    Text(
                        ReglasWins.subtitulo(n),
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.SemiBold,
                        color = c.texto,
                        textAlign = TextAlign.Center,
                        modifier = Modifier.testTag("festejo-subtitulo"),
                    )
                }
                Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(Espacio.s)) {
                    records.forEachIndexed { i, r -> FilaRecord(r, Modifier.testTag("festejo-record-$i")) }
                }
                if (conPermiso) {
                    Row(
                        Modifier
                            .fillMaxWidth()
                            .clip(RoundedCornerShape(Radio.control + 4.dp))
                            .background(c.marcaSuave)
                            .padding(Espacio.m)
                            .semantics(mergeDescendants = true) { liveRegion = LiveRegionMode.Polite }
                            .testTag("festejo-con-permiso"),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(Espacio.xs),
                    ) {
                        Icon(Iconos.TildeEnCirculo, contentDescription = null, tint = c.marcaTexto, modifier = Modifier.size(22.dp))
                        Text(
                            ReglasWins.conPermiso(n),
                            style = MaterialTheme.typography.bodyMedium,
                            fontWeight = FontWeight.SemiBold,
                            color = c.marcaTexto,
                            modifier = Modifier.weight(1f),
                        )
                    }
                }
                if (avisoDemo) {
                    Row(
                        Modifier.fillMaxWidth().semantics(mergeDescendants = true) { liveRegion = LiveRegionMode.Polite }.testTag("festejo-demo"),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(Espacio.xs),
                    ) {
                        Icon(Iconos.Chispas, contentDescription = null, tint = c.textoSecundario, modifier = Modifier.size(20.dp))
                        Text(ReglasWins.DEMO, style = MaterialTheme.typography.bodyMedium, color = c.textoSecundario, modifier = Modifier.weight(1f))
                    }
                }
            }
            // Los botones quedan siempre a la vista, debajo de lo que se desplaza (con letra grande no se tapan).
            Column(
                Modifier.widthIn(max = AnchoLectura).fillMaxWidth().padding(horizontal = Espacio.m).padding(top = Espacio.xs, bottom = Espacio.m),
                verticalArrangement = Arrangement.spacedBy(Espacio.xs),
            ) {
                if (!conPermiso) {
                    BotonMarca(
                        ReglasWins.CONTARLE,
                        alTocar = { if (esDemo) avisoDemo = true else pidiendoPermiso = true },
                        modifier = Modifier.testTag("festejo-contarle"),
                    )
                    BotonSecundario(ReglasWins.SEGUIR, alTocar = ::cerrar, modifier = Modifier.testTag("festejo-seguir"), tono = c.marcaTexto)
                } else {
                    BotonMarca(ReglasWins.SEGUIR, alTocar = ::cerrar, modifier = Modifier.testTag("festejo-seguir"))
                }
            }
        }
    }
    if (pidiendoPermiso) HojaPermisoLogros(modelo, records, alCerrar = { pidiendoPermiso = false })
}

@Composable
private fun Trofeo(entro: Boolean, reducir: Boolean) {
    val escala by animateFloatAsState(
        if (entro || reducir) 1f else 0.6f,
        if (reducir) tween(0) else spring(dampingRatio = 0.45f, stiffness = Spring.StiffnessMediumLow),
        label = "trofeo",
    )
    val giro by animateFloatAsState(if (entro || reducir) 0f else -12f, if (reducir) tween(0) else spring(dampingRatio = 0.5f), label = "giro")
    val halo by animateFloatAsState(if (entro || reducir) 1f else 0f, tween(if (reducir) 0 else 450), label = "halo")
    Box(Modifier.height(144.dp).fillMaxWidth().clearAndSetSemantics {}, contentAlignment = Alignment.Center) {
        Box(Modifier.size(200.dp).background(Brush.radialGradient(listOf(Oro.copy(alpha = 0.45f * halo), Color.Transparent)), CircleShape))
        Box(
            Modifier
                .size(96.dp)
                .scale(escala)
                .rotate(giro)
                .background(Brush.verticalGradient(listOf(Oro, Color(0xFFEDAD1A))), CircleShape),
            contentAlignment = Alignment.Center,
        ) {
            Icon(Iconos.Trofeo, contentDescription = null, tint = Color(0xFF5C4000), modifier = Modifier.size(48.dp))
        }
    }
}

/** Un récord: el ejercicio, la marca de hoy, cuánto subió y la marca anterior. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun FilaRecord(record: ReglasWins.Record, modifier: Modifier = Modifier) {
    val c = MyPump.colores
    val nombre = NombreEjercicio(record.ejercicio).principal
    Column(
        modifier
            .fillMaxWidth()
            .superficieTarjeta()
            .padding(Espacio.m)
            .clearAndSetSemantics { contentDescription = "$nombre, ${record.marca}, ${record.chip}. ${record.antes}" },
        verticalArrangement = Arrangement.spacedBy(Espacio.xs),
    ) {
        Text(nombre, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold, color = c.texto)
        // Con letra muy grande el chip baja solo debajo de la marca.
        FlowRow(
            Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(Espacio.s),
            verticalArrangement = Arrangement.spacedBy(Espacio.xs),
        ) {
            Text(record.marca, style = Numeros.mediano.copy(fontFeatureSettings = "tnum"), color = c.texto, modifier = Modifier.align(Alignment.CenterVertically))
            Text(
                record.chip,
                style = MaterialTheme.typography.labelLarge.copy(fontFeatureSettings = "tnum"),
                fontWeight = FontWeight.Bold,
                color = c.record,
                modifier = Modifier
                    .align(Alignment.CenterVertically)
                    .background(c.record.copy(alpha = 0.14f), CircleShape)
                    .padding(horizontal = 12.dp, vertical = 6.dp),
            )
        }
        Text(record.antes, style = MaterialTheme.typography.bodyMedium, color = c.textoSecundario)
    }
}

// ── El permiso ──

/** «¿Querés que Mati se entere de tus logros?»: el permiso explícito. Con el sí, [records] quedan en la cola. */
@OptIn(ExperimentalMaterial3Api::class, ExperimentalComposeUiApi::class)
@Composable
fun HojaPermisoLogros(modelo: ModeloApp, records: List<ReglasWins.Record> = emptyList(), alCerrar: () -> Unit) {
    val c = MyPump.colores
    val hoja = rememberModalBottomSheetState(skipPartiallyExpanded = true, confirmValueChange = { true })
    val alcanceHoja = rememberCoroutineScope()
    val alcance = LocalAlcanceApp.current
    var enviando by remember { mutableStateOf(false) }
    var aviso by remember { mutableStateOf<String?>(null) }

    fun cerrar() {
        alcanceHoja.launch { hoja.hide() }.invokeOnCompletion { alCerrar() }
    }

    fun aceptar() {
        val wins = modelo.wins.value
        if (wins == null || modelo.esDemo.value) {
            cerrar()
            return
        }
        enviando = true
        aviso = null
        alcance.launch {
            val ok = wins.darPermiso(records)
            enviando = false
            if (ok) cerrar() else aviso = ReglasWins.SIN_RED
        }
    }

    ModalBottomSheet(
        onDismissRequest = { if (!enviando) alCerrar() },
        sheetState = hoja,
        shape = FormaHoja,
        containerColor = c.fondo,
        tonalElevation = 0.dp,
        dragHandle = { AsaHoja() },
        modifier = Modifier.semantics { testTagsAsResourceId = true; paneTitle = ReglasWins.PERMISO_TITULO }.testTag("hoja-permiso-logros"),
    ) {
        Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
            Column(
                Modifier
                    .weight(1f, fill = false)
                    .verticalScroll(rememberScrollState())
                    .widthIn(max = AnchoLectura)
                    .fillMaxWidth()
                    .padding(horizontal = Espacio.l)
                    .padding(top = Espacio.l, bottom = Espacio.m),
                verticalArrangement = Arrangement.spacedBy(Espacio.l),
            ) {
                Box(Modifier.size(64.dp).background(c.marca, CircleShape).clearAndSetSemantics {}, contentAlignment = Alignment.Center) {
                    Icon(Iconos.Trofeo, contentDescription = null, tint = c.sobreMarca, modifier = Modifier.size(32.dp))
                }
                Text(
                    ReglasWins.PERMISO_TITULO,
                    style = MaterialTheme.typography.headlineSmall,
                    fontWeight = FontWeight.Bold,
                    color = c.texto,
                    modifier = Modifier.semantics { heading() }.testTag("permiso-titulo"),
                )
                Column(verticalArrangement = Arrangement.spacedBy(Espacio.m)) {
                    for (t in ReglasWins.PERMISO_CUERPO) Text(t, style = MaterialTheme.typography.bodyLarge, color = c.texto)
                }
                aviso?.let {
                    Row(
                        Modifier.fillMaxWidth().semantics(mergeDescendants = true) { liveRegion = LiveRegionMode.Polite }.testTag("permiso-aviso"),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(Espacio.xs),
                    ) {
                        Icon(Iconos.SinWifi, contentDescription = null, tint = c.peligro, modifier = Modifier.size(20.dp))
                        Text(it, style = MaterialTheme.typography.bodyMedium, color = c.texto, modifier = Modifier.weight(1f))
                    }
                }
            }
            Column(
                Modifier.widthIn(max = AnchoLectura).fillMaxWidth().padding(horizontal = Espacio.m).padding(top = Espacio.xs, bottom = Espacio.m),
                verticalArrangement = Arrangement.spacedBy(Espacio.xs),
            ) {
                BotonMarca(ReglasWins.PERMISO_SI, alTocar = ::aceptar, modifier = Modifier.testTag("permiso-si"), cargando = enviando)
                BotonSecundario(
                    ReglasWins.PERMISO_NO, alTocar = ::cerrar, modifier = Modifier.testTag("permiso-no"), tono = c.marcaTexto, habilitado = !enviando,
                )
            }
        }
    }
}

// ── Mis datos ──

/**
 * La sección «Logros» de Mis datos: el interruptor del permiso. Se ve con la función prendida, o apagada si el permiso
 * quedó dado (para poder sacarlo). Prender abre la hoja del permiso; apagar lo saca en el servidor y vacía la cola.
 */
@Composable
fun SeccionLogros(modelo: ModeloApp) {
    val esDemo by modelo.esDemo.collectAsStateWithLifecycle()
    val wins = modelo.wins.collectAsStateWithLifecycle().value?.takeIf { !esDemo } ?: return
    val estado by wins.estado.collectAsStateWithLifecycle()
    var aviso by remember(wins) { mutableStateOf<String?>(null) }
    // Recién apagado se sigue viendo, con su aviso, aunque la función esté apagada.
    if (!estado.visibleEnMisDatos && aviso == null) return
    val c = MyPump.colores
    val alcance = LocalAlcanceApp.current
    var pidiendo by remember { mutableStateOf(false) }
    var trabajando by remember { mutableStateOf(false) }

    fun cambiar(nuevo: Boolean) {
        aviso = null
        if (nuevo) {
            // Con la función apagada no se puede dar (solo sacar).
            if (estado.prendida) pidiendo = true
            return
        }
        trabajando = true
        alcance.launch {
            val ok = wins.revocar()
            trabajando = false
            aviso = if (ok) ReglasWins.DESACTIVADO else ReglasWins.SIN_RED
        }
    }

    Column(Modifier.padding(horizontal = Espacio.m).testTag("seccion-logros")) {
        RotuloSeccion(ReglasWins.AJUSTE_SECCION, Modifier.padding(start = 0.dp))
        Column(Modifier.fillMaxWidth().superficieTarjeta()) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .heightIn(min = 56.dp)
                    .toggleable(value = estado.permiso, enabled = !trabajando, role = Role.Switch, onValueChange = ::cambiar)
                    .padding(horizontal = Espacio.m, vertical = Espacio.xs)
                    .testTag("logros-interruptor"),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(Espacio.s),
            ) {
                IconoAzulejo(Iconos.Trofeo, c.record)
                Text(ReglasWins.AJUSTE_INTERRUPTOR, style = MaterialTheme.typography.bodyLarge, modifier = Modifier.weight(1f))
                Interruptor(estado.permiso, alCambiar = null, color = c.marcaVivo)
            }
            aviso?.let {
                Text(
                    it,
                    style = MaterialTheme.typography.bodyMedium,
                    color = c.textoSecundario,
                    modifier = Modifier
                        .padding(horizontal = Espacio.m)
                        .padding(bottom = Espacio.s)
                        .semantics { liveRegion = LiveRegionMode.Polite }
                        .testTag("logros-aviso"),
                )
            }
        }
        PieSeccion(ReglasWins.AJUSTE_PIE)
    }
    if (pidiendo) HojaPermisoLogros(modelo, alCerrar = { pidiendo = false })
}
