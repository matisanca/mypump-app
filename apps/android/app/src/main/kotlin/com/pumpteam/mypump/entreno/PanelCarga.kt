package com.pumpteam.mypump.entreno

import android.content.Context
import android.graphics.Rect
import android.os.Build
import android.view.ViewTreeObserver
import android.view.accessibility.AccessibilityManager
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.isImeVisible
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.TextAutoSize
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.HorizontalDivider
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
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.pumpteam.mypump.datos.ModeloEntreno
import com.pumpteam.mypump.diseno.BotonMarca
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
    val c = MyPump.colores
    // El fondo sigue por debajo de las pestañas flotantes; lo que se toca queda arriba de ellas.
    Column(
        Modifier.fillMaxWidth().background(c.fondo).then(if (corrigiendoEste) Modifier.imePadding() else Modifier).padding(bottom = rellenoInferior()),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        HorizontalDivider(color = c.separador)
        Column(
            Modifier
                .widthIn(max = 560.dp)
                .fillMaxWidth()
                .padding(start = Espacio.m, end = Espacio.m, top = Espacio.s, bottom = Espacio.xs)
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
            FilaDeshacer(motor, deshacible)
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

    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Text(
            "Serie ${i + 1} de ${s.series.size}",
            style = Letras.subtitulo.copy(fontWeight = FontWeight.SemiBold),
            modifier = Modifier.weight(1f).semantics { heading() },
        )
        DescansoChip(motor)
    }
    DialReps(reps, s.diferencia(i), textoReferencia(i, s)) { delta ->
        aviso = null
        motor.cambiarCarga(lugar) { it.ajustarReps(i, delta) }
        motor.limpiarGuardia()
    }
    val puede = s.puedeConfirmar(i)
    Button(
        onClick = {
            aviso = null
            alcance.launch {
                val manejaTalkBack = (contexto.getSystemService(Context.ACCESSIBILITY_SERVICE) as? AccessibilityManager)?.isTouchExplorationEnabled == true
                val r = motor.okSerie(lugar, i, venceEn = if (manejaTalkBack) null else 6.0) { preguntador.preguntar(it) }
                if (r == ModeloEntreno.ResultadoOK.REGISTRADA) haptico.performHapticFeedback(HapticFeedbackType.Confirm)
                if (r == ModeloEntreno.ResultadoOK.FALTAN_DATOS) aviso = "Faltan datos para registrar esta serie."
            }
        },
        enabled = puede,
        modifier = Modifier
            .fillMaxWidth()
            .defaultMinSize(minHeight = 54.dp)
            .semantics { contentDescription = etiquetaAccesibleOK(reps, kg, i, s, enGuardia) }
            .testTag("ok-serie"),
        shape = CircleShape,
        colors = ButtonDefaults.buttonColors(
            containerColor = if (enGuardia) c.alerta else c.marca,
            contentColor = if (enGuardia) c.sobreMarca else c.sobreMarca,
            disabledContainerColor = c.campo,
            disabledContentColor = c.textoSecundario,
        ),
        contentPadding = PaddingValues(horizontal = 16.dp, vertical = 8.dp),
    ) {
        EtiquetaOK(reps, kg, i, s, enGuardia)
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
private fun EtiquetaOK(reps: Int?, kg: Double?, i: Int, s: CargaSimple, enGuardia: Boolean) {
    val estilo = MaterialTheme.typography.titleMedium.merge(Letras.cifras)
    val tam = TextAutoSize.StepBased(minFontSize = 11.sp, maxFontSize = estilo.fontSize, stepSize = 1.sp)
    val mensaje = when {
        enGuardia -> "¿Ya hiciste la serie? Tocá de nuevo"
        s.pideElegirReps && !s.series[i].tocada -> "Marcá tus reps"
        !s.sinKg && kg == null -> "Elegí la carga"
        else -> null
    }
    if (mensaje != null) {
        Text(mensaje, style = estilo, maxLines = 1, autoSize = tam, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth())
        return
    }
    val detalle = if (s.sinKg) "${reps ?: 0} reps" else "${reps ?: 0} × ${KgTexto.de(kg)} kg"
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically) {
        Text("OK", style = estilo.copy(fontWeight = FontWeight.ExtraBold), maxLines = 1)
        Spacer(Modifier.width(8.dp))
        Text(detalle, style = estilo.copy(fontWeight = FontWeight.SemiBold), maxLines = 1, autoSize = tam)
    }
}

private fun etiquetaAccesibleOK(reps: Int?, kg: Double?, i: Int, s: CargaSimple, enGuardia: Boolean): String = when {
    enGuardia -> "¿Ya hiciste la serie? Tocá de nuevo para registrarla"
    !s.puedeConfirmar(i) -> "Falta completar la serie"
    s.sinKg -> "OK, registrar ${reps ?: 0} repeticiones"
    else -> "OK, registrar ${reps ?: 0} repeticiones con ${KgTexto.de(kg)} kilos"
}

/** Reserva siempre su renglón: si apareciera y desapareciera, el panel saltaría y el dial se movería bajo el dedo. */
@Composable
private fun FilaDeshacer(motor: ModeloEntreno, d: ModeloEntreno.OKDeshacible?) {
    Row(Modifier.heightIn(min = 44.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(2.dp)) {
        if (d != null) {
            Text("Serie ${d.indice + 1} anotada.", style = Letras.caption, color = MyPump.colores.textoSecundario)
            EnlaceTexto("Deshacer", "deshacer-ok") { motor.deshacerOK() }
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
        Text("Corrigiendo la serie ${i + 1}", style = Letras.subtitulo.copy(fontWeight = FontWeight.SemiBold), modifier = Modifier.weight(1f).semantics { heading() })
        EnlaceTexto("Cancelar", "correccion-cancelar", Letras.subtitulo) { motor.cancelarCorreccion() }
    }
    DialReps(reps, null, "Solo cambia esta serie") { delta ->
        reps = minOf(Verosimilitud.REPS_MAX.toInt(), maxOf(1, reps + delta))
    }
    if (!s.sinKg) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espacio.s)) {
            BotonRedondo(Iconos.Menos, "Bajar el peso", "correccion-kg-menos") { kg?.let { kg = AumentoCarga.mover(it, -1, s.equipo) } }
            CampoKilos(
                valor = KgTexto.de(kg),
                etiqueta = "Peso de la serie en kilos",
                alCambiar = { kg = KgTexto.numero(it) },
                estilo = Letras.titulo3.copy(fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center).merge(Letras.cifras),
                modifier = Modifier.width(90.dp).testTag("correccion-kg"),
            ) { _, campo ->
                Box(Modifier.heightIn(min = 44.dp).clip(RoundedCornerShape(10.dp)).background(c.campo).padding(horizontal = 4.dp), contentAlignment = Alignment.Center) { campo() }
            }
            BotonRedondo(Iconos.Mas, "Subir el peso", "correccion-kg-mas") { kg?.let { kg = AumentoCarga.mover(it, 1, s.equipo) } }
        }
    }
    aviso?.let { AvisoPanel(it) }
    BotonMarca(
        "Guardar corrección",
        alTocar = {
            foco.clearFocus()
            alcance.launch {
                aviso = (motor.guardarCorreccion(reps, kg) { preguntador.preguntar(it) } as? ModeloEntreno.ResultadoCorreccion.Rechazada)?.aviso
            }
        },
        modifier = Modifier.testTag("correccion-guardar"),
    )
}

@Composable
private fun Terminado() {
    val c = MyPump.colores
    Column(Modifier.fillMaxWidth().padding(vertical = Espacio.s), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(Espacio.xs)) {
        Row(Modifier.testTag("ejercicio-completo"), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp)) {
            Icon(Iconos.TildeEnCirculo, contentDescription = null, tint = c.marcaTexto, modifier = Modifier.size(18.dp))
            Text("Ejercicio completo", style = MaterialTheme.typography.titleMedium, color = c.marcaTexto)
        }
        Text("Tocá una serie si querés corregirla.", style = Letras.caption, color = c.textoSecundario)
    }
}

/** El descanso en el panel: aparte, para que lo que cambia 4 veces por segundo solo redibuje esto. */
@Composable
private fun DescansoChip(motor: ModeloEntreno) {
    val c = MyPump.colores
    val b by motor.descanso.collectAsStateWithLifecycle()
    if (!b.visible) return
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(2.dp)) {
        Text(
            if (b.listo) "A la serie" else "Descanso ${b.texto}",
            style = Letras.caption.copy(fontWeight = FontWeight.SemiBold).merge(Letras.cifras),
            color = if (b.listo) c.marcaTexto else c.textoSecundario,
            modifier = Modifier.testTag("descanso-chip"),
        )
        if (!b.listo) EnlaceTexto("Saltar", "saltar-descanso") { motor.saltarDescanso() }
    }
}
