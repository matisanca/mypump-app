package com.pumpteam.mypump.entreno

import android.content.Context
import android.graphics.Rect
import android.os.Build
import android.view.ViewTreeObserver
import android.view.accessibility.AccessibilityManager
import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.animateContentSize
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.clearAndSetSemantics
import com.pumpteam.mypump.diseno.Numeros
import com.pumpteam.mypump.diseno.vidrio
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.isImeVisible
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.TextAutoSize
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.MutableIntState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.pumpteam.mypump.datos.ModeloEntreno
import com.pumpteam.mypump.diseno.Espacio
import com.pumpteam.mypump.diseno.Iconos
import com.pumpteam.mypump.diseno.MyPump
import com.pumpteam.mypump.diseno.rellenoInferior
import com.pumpteam.mypump.raiz.LocalAlcanceApp
import com.pumpteam.mypump.reglas.AumentoCarga
import com.pumpteam.mypump.reglas.CargaSimple
import com.pumpteam.mypump.reglas.EstadosEjercicio
import com.pumpteam.mypump.reglas.GuardiaOK
import com.pumpteam.mypump.reglas.Verosimilitud
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/** Los paneles de carga a la vista (la lista y la página del ejercicio): mientras haya uno, el descanso va ahí. */
val LocalPanelesCarga = staticCompositionLocalOf<MutableIntState?> { null }

/**
 * El panel fijo arriba de las pestañas: la serie que toca, el dial y el OK (gemelo de PanelCarga.swift). Va fuera de la lista
 * que se desplaza, así deslizar el dial nunca mueve la pantalla y desplazar la pantalla nunca cambia las reps. Absorbe la barra
 * del descanso.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun PanelCarga(motor: ModeloEntreno, lugar: String, preguntador: Preguntador) {
    val d by motor.dia.collectAsStateWithLifecycle()
    val corrigiendo by motor.corrigiendo.collectAsStateWithLifecycle()
    val deshacible by motor.deshacible.collectAsStateWithLifecycle()
    val s = motor.cargaSimple(lugar) ?: return
    // Con el teclado arriba se esconde: si no, en un teléfono chico tapa el campo y se podría dar OK sin verlo. Corrigiendo
    // no: el campo del peso está en el panel y, si se fuera, se llevaría el foco y el teclado se cerraría al abrirse.
    val corrigiendoEste = corrigiendo?.lugar == lugar
    if (tecladoAbierto() && !corrigiendoEste) return
    val terminal = d.estado(lugar) in EstadosEjercicio.terminales
    if (!(corrigiendoEste || deshacible != null || (!s.completo && !terminal))) return

    val paneles = LocalPanelesCarga.current
    DisposableEffect(paneles) {
        paneles?.let { it.intValue += 1 }
        onDispose { paneles?.let { it.intValue -= 1 } }
    }
    // El panel flota sobre la lista; el fondo sigue por debajo de las pestañas flotantes y lo que se toca queda arriba de ellas.
    // Deshacer va encima, fuera de la superficie: aparece sin cambiar de lugar el dial (el panel crece hacia arriba).
    Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
        FilaDeshacer(motor, deshacible)
        Column(
            Modifier
                .fillMaxWidth()
                .superficiePanelCarga()
                .then(if (corrigiendoEste) Modifier.imePadding() else Modifier)
                .padding(bottom = rellenoInferior()),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Column(
                Modifier
                    .widthIn(max = 560.dp)
                    .fillMaxWidth()
                    .padding(start = Espacio.m + 2.dp, end = Espacio.m + 2.dp, top = Espacio.s, bottom = Espacio.s)
                    .animateContentSize(EstiloCarga.resorte())
                    .testTag("panel-carga"),
                verticalArrangement = Arrangement.spacedBy(Espacio.xs),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                val cor = corrigiendo
                val activa = s.activa
                when {
                    cor != null && cor.lugar == lugar && cor.indice < s.series.size -> Correccion(motor, cor.indice, s, preguntador)
                    activa != null && !terminal -> Activa(motor, lugar, activa, s, preguntador)
                    else -> Terminado()
                }
            }
        }
    }
}

/**
 * Si el teclado está arriba. Hasta Android 10, sin `adjustResize`, el sistema no informa el teclado por los insets
 * (`isImeVisible` da siempre falso): ahí se mide lo que queda visible de la ventana.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun tecladoAbierto(): Boolean {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) return WindowInsets.isImeVisible
    val vista = LocalView.current
    var abierto by remember { mutableStateOf(false) }
    DisposableEffect(vista) {
        val medir = ViewTreeObserver.OnGlobalLayoutListener {
            val visible = Rect()
            vista.getWindowVisibleDisplayFrame(visible)
            val alto = vista.rootView.height
            abierto = alto - visible.bottom > alto * 0.15f
        }
        vista.viewTreeObserver.addOnGlobalLayoutListener(medir)
        onDispose { vista.viewTreeObserver.removeOnGlobalLayoutListener(medir) }
    }
    return abierto
}

@Composable
private fun Activa(motor: ModeloEntreno, lugar: String, i: Int, s: CargaSimple, preguntador: Preguntador) {
    val c = MyPump.colores
    val alcance = LocalAlcanceApp.current
    val haptico = LocalHapticFeedback.current
    val contexto = LocalContext.current
    val reducir = reducirMovimiento()
    val guardia by motor.guardia.collectAsStateWithLifecycle()
    val d by motor.dia.collectAsStateWithLifecycle()
    var aviso by remember(i) { mutableStateOf<String?>(null) }
    val reps = s.reps(i)
    val kg = s.series[i].kg
    val enGuardia = guardia.serie == i && guardia.desde != null

    LaunchedEffect(guardia.desde) {
        if (guardia.desde == null) return@LaunchedEffect
        delay(GuardiaOK.VENCE_EN.toLong())
        motor.limpiarGuardia()
    }

    // El récord entra en el renglón del título: la tarjeta puede estar fuera de vista y el panel no cambia de alto.
    val record by motor.avisoRecord.collectAsStateWithLifecycle()
    val recordAca = record?.takeIf { it.lugar == lugar }
    LaunchedEffect(recordAca?.id) {
        val id = recordAca?.id ?: return@LaunchedEffect
        delay(3000)
        motor.descartarRecord(id)
    }
    ProgresoSeries(s.series.size, s.confirmadas, i)
    // Con letra grande, el descanso va abajo del título: al lado partía las palabras.
    val apilado = LocalDensity.current.fontScale >= 1.3f
    val titulo: @Composable (Modifier) -> Unit = { m ->
        if (recordAca != null) {
            Text(
                recordAca.texto,
                style = Letras.subtitulo.copy(fontWeight = FontWeight.Bold),
                color = MyPump.colores.marcaTexto,
                modifier = m.semantics { liveRegion = LiveRegionMode.Polite }.testTag("aviso-record-panel"),
            )
        } else {
            Text(
                "Serie ${i + 1} de ${s.series.size}",
                style = Numeros.chico.copy(fontSize = 15.sp),
                maxLines = 1,
                modifier = m.semantics { heading() },
            )
        }
    }
    if (apilado) {
        Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            titulo(Modifier)
            DescansoChip(motor)
        }
    } else {
        Row(Modifier.fillMaxWidth().heightIn(min = 32.dp), verticalAlignment = Alignment.CenterVertically) {
            titulo(Modifier.weight(1f))
            DescansoChip(motor)
        }
    }
    DialReps(reps, s.diferencia(i), textoReferencia(i, s), clave = i) { delta ->
        aviso = null
        motor.cambiarCarga(lugar) { it.ajustarReps(i, delta) }
        motor.limpiarGuardia()
    }
    val puede = s.puedeConfirmar(i)
    var sello by remember { mutableIntStateOf(0) }
    var selloVisible by remember { mutableStateOf(false) }
    LaunchedEffect(sello) {
        if (sello == 0) return@LaunchedEffect
        selloVisible = true
        delay(620)
        selloVisible = false
    }
    LaunchedEffect(enGuardia) { if (enGuardia) haptico.performHapticFeedback(HapticFeedbackType.Reject) }
    Box(Modifier.fillMaxWidth()) {
        BotonConfirmar(
            alTocar = {
                aviso = null
                alcance.launch {
                    val manejaTalkBack = (contexto.getSystemService(Context.ACCESSIBILITY_SERVICE) as? AccessibilityManager)?.isTouchExplorationEnabled == true
                    val r = motor.okSerie(lugar, i, venceEn = if (manejaTalkBack) null else 6.0) { preguntador.preguntar(it) }
                    if (r == ModeloEntreno.ResultadoOK.REGISTRADA) {
                        haptico.performHapticFeedback(HapticFeedbackType.Confirm)
                        if (!reducir) sello++
                    }
                    if (r == ModeloEntreno.ResultadoOK.FALTAN_DATOS) aviso = "Faltan datos para registrar esta serie."
                }
            },
            habilitado = puede,
            alerta = enGuardia,
            modifier = Modifier
                .fillMaxWidth()
                .semantics { contentDescription = etiquetaAccesibleOK(reps, kg, i, s, enGuardia) }
                .testTag("ok-serie"),
        ) { tinta -> EtiquetaOK(reps, kg, i, s, enGuardia, tinta) }
        // Medio segundo de tilde sobre el botón: la serie quedó anotada, sin tapar nada ni frenar el próximo toque.
        AnimatedVisibility(selloVisible, Modifier.matchParentSize(), enter = fadeIn(), exit = fadeOut()) {
            Box(Modifier.fillMaxSize().clip(CircleShape).background(c.marca).clearAndSetSemantics {}, contentAlignment = Alignment.Center) {
                Icon(Iconos.Tilde, contentDescription = null, tint = c.sobreMarca, modifier = Modifier.size(28.dp))
            }
        }
    }
    (aviso ?: d.ejercicios[lugar]?.series?.getOrNull(i)?.aviso)?.takeIf { it.isNotEmpty() }?.let {
        AvisoPanel(it, Modifier.testTag("aviso-serie-${i + 1}"))
    }
}

@Composable
private fun AvisoPanel(texto: String, modifier: Modifier = Modifier) {
    val c = MyPump.colores
    Row(modifier, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp)) {
        Icon(Iconos.Alerta, contentDescription = null, tint = c.peligro, modifier = Modifier.size(13.dp))
        Text(texto, style = Letras.caption, color = c.peligro)
    }
}

private fun textoReferencia(i: Int, s: CargaSimple): String? {
    val b = s.base(i)
    return when (b.origen) {
        CargaSimple.OrigenBase.ULTIMA_VEZ -> b.reps?.let { "La vez pasada: $it" }
        CargaSimple.OrigenBase.PLAN -> "Según el plan: ${s.repsPlan ?: "—"}"
        CargaSimple.OrigenBase.NINGUNO -> if (s.pideElegirReps) "Marcá las que hiciste" else null
    }
}

/** El texto del OK, que achica la letra antes de cortarse (`minimumScaleFactor` de iOS). */
@Composable
private fun EtiquetaOK(reps: Int?, kg: Double?, i: Int, s: CargaSimple, enGuardia: Boolean, tinta: Color) {
    val estilo = Numeros.chico.copy(fontSize = 20.sp, color = tinta)
    val tam = TextAutoSize.StepBased(minFontSize = 11.sp, maxFontSize = estilo.fontSize, stepSize = 1.sp)
    val mensaje = when {
        enGuardia -> "¿Ya hiciste la serie? Tocá de nuevo"
        s.pideElegirReps && !s.series[i].tocada -> "Marcá tus reps"
        !s.sinKg && kg == null -> "Elegí la carga"
        else -> null
    }
    if (mensaje != null) {
        Text(mensaje, style = MaterialTheme.typography.titleMedium.copy(color = tinta, fontWeight = FontWeight.SemiBold), maxLines = 1, autoSize = tam, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth())
        return
    }
    val detalle = if (s.sinKg) "${reps ?: 0} reps" else "${reps ?: 0} × ${KgTexto.de(kg)} kg"
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically) {
        Text("OK", style = estilo.copy(fontSize = 22.sp, fontWeight = FontWeight.Black), maxLines = 1)
        Spacer(Modifier.width(10.dp))
        Text(detalle, style = estilo, maxLines = 1, autoSize = tam)
    }
}

private fun etiquetaAccesibleOK(reps: Int?, kg: Double?, i: Int, s: CargaSimple, enGuardia: Boolean): String = when {
    enGuardia -> "¿Ya hiciste la serie? Tocá de nuevo para registrarla"
    !s.puedeConfirmar(i) -> "Falta completar la serie"
    s.sinKg -> "OK, registrar ${reps ?: 0} repeticiones"
    else -> "OK, registrar ${reps ?: 0} repeticiones con ${KgTexto.de(kg)} kilos"
}

/** Flota arriba del panel, en una cápsula: no le guarda un renglón vacío al panel ni mueve el dial. */
@Composable
private fun FilaDeshacer(motor: ModeloEntreno, d: ModeloEntreno.OKDeshacible?) {
    val c = MyPump.colores
    // Mientras se va, sigue diciendo la serie que era (d ya es null) y el botón no responde.
    var ultimo by remember { mutableStateOf(d) }
    if (d != null) ultimo = d
    AnimatedVisibility(
        d != null,
        enter = slideInVertically { it } + fadeIn(),
        exit = slideOutVertically { it } + fadeOut(),
    ) {
        val indice = ultimo?.indice ?: 0
        Row(
            Modifier
                .padding(bottom = Espacio.s)
                .vidrio()
                .heightIn(min = 44.dp)
                .padding(start = Espacio.m, end = Espacio.xs),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            Icon(Iconos.TildeEnCirculo, contentDescription = null, tint = c.marcaTexto, modifier = Modifier.size(18.dp))
            Text("Serie ${indice + 1} anotada.", style = Letras.subtitulo.copy(fontWeight = FontWeight.Medium), color = c.texto)
            EnlaceTexto("Deshacer", "deshacer-ok", Letras.subtitulo.copy(fontWeight = FontWeight.Bold)) { motor.deshacerOK() }
        }
    }
}

@Composable
private fun Correccion(motor: ModeloEntreno, i: Int, s: CargaSimple, preguntador: Preguntador) {
    val c = MyPump.colores
    val alcance = LocalAlcanceApp.current
    val foco = LocalFocusManager.current
    var reps by remember(i) { mutableStateOf(s.reps(i) ?: 1) }
    var kg by remember(i) { mutableStateOf(s.series[i].kg) }
    var aviso by remember(i) { mutableStateOf<String?>(null) }

    // El Atrás del teléfono cancela la corrección, como «Cancelar».
    BackHandler { motor.cancelarCorreccion() }

    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Text("Corrigiendo la serie ${i + 1}", style = Numeros.chico.copy(fontSize = 15.sp), modifier = Modifier.weight(1f).semantics { heading() })
        EnlaceTexto("Cancelar", "correccion-cancelar", Letras.subtitulo) { motor.cancelarCorreccion() }
    }
    DialReps(reps, null, "Solo cambia esta serie", clave = i) { delta ->
        reps = minOf(Verosimilitud.REPS_MAX.toInt(), maxOf(1, reps + delta))
    }
    if (!s.sinKg) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espacio.s)) {
            BotonCircularCarga(Iconos.Menos, "Bajar el peso", "correccion-kg-menos", lado = 44.dp, tamanoIcono = 18.dp) { kg?.let { kg = AumentoCarga.mover(it, -1, s.equipo) } }
            CampoKilos(
                valor = KgTexto.de(kg),
                etiqueta = "Peso de la serie en kilos",
                alCambiar = { kg = KgTexto.numero(it) },
                estilo = Numeros.mediano.copy(fontSize = 24.sp, fontWeight = FontWeight.ExtraBold, textAlign = TextAlign.Center).merge(Letras.cifras),
                modifier = Modifier.width(96.dp).testTag("correccion-kg"),
            ) { enfocado, campo ->
                val forma = RoundedCornerShape(10.dp)
                Box(Modifier.heightIn(min = 44.dp).clip(forma).then(if (enfocado) Modifier.background(c.campo).border(2.dp, c.marcaVivo, forma) else Modifier).padding(horizontal = 4.dp), contentAlignment = Alignment.Center) { campo() }
            }
            BotonCircularCarga(Iconos.Mas, "Subir el peso", "correccion-kg-mas", lado = 44.dp, tamanoIcono = 18.dp) { kg?.let { kg = AumentoCarga.mover(it, 1, s.equipo) } }
        }
    }
    aviso?.let { AvisoPanel(it) }
    BotonConfirmar(
        alTocar = {
            foco.clearFocus()
            alcance.launch {
                aviso = (motor.guardarCorreccion(reps, kg) { preguntador.preguntar(it) } as? ModeloEntreno.ResultadoCorreccion.Rechazada)?.aviso
            }
        },
        modifier = Modifier.fillMaxWidth().testTag("correccion-guardar"),
    ) { tinta -> Text("Guardar corrección", style = Numeros.chico.copy(fontSize = 19.sp, color = tinta, fontWeight = FontWeight.ExtraBold)) }
}

@Composable
private fun Terminado() {
    val c = MyPump.colores
    Column(Modifier.fillMaxWidth().padding(vertical = Espacio.xs), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(Espacio.xs)) {
        Box(Modifier.size(44.dp).clip(CircleShape).background(c.marca), contentAlignment = Alignment.Center) {
            Icon(Iconos.Tilde, contentDescription = null, tint = c.sobreMarca, modifier = Modifier.size(24.dp))
        }
        Text("Ejercicio completo", style = Numeros.chico.copy(fontSize = 20.sp, fontWeight = FontWeight.ExtraBold), color = c.texto, modifier = Modifier.testTag("ejercicio-completo"))
        Text("Tocá una serie si querés corregirla.", style = Letras.caption, color = c.textoSecundario)
    }
}

/** El descanso en el panel: aparte, para que lo que cambia 4 veces por segundo solo redibuje esto. */
@Composable
private fun DescansoChip(motor: ModeloEntreno) {
    val c = MyPump.colores
    val b by motor.descanso.collectAsStateWithLifecycle()
    if (!b.visible) return
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espacio.xs)) {
        Text(
            if (b.listo) "A la serie" else "Descanso ${b.texto}",
            style = Numeros.chico.copy(fontSize = 14.sp).merge(Letras.cifras),
            color = if (b.listo) c.marcaTexto else c.texto,
            maxLines = 1,
            modifier = Modifier
                .clip(CircleShape)
                .background(if (b.listo) c.marcaSuave else c.campo)
                .padding(horizontal = 10.dp, vertical = 5.dp)
                .testTag("descanso-chip"),
        )
        if (!b.listo) EnlaceTexto("Saltar", "saltar-descanso") { motor.saltarDescanso() }
    }
}
