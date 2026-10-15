package com.pumpteam.mypump.revision

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.animateContentSize
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.Saver
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.pumpteam.mypump.datos.Checkin
import com.pumpteam.mypump.datos.ModeloRevision
import com.pumpteam.mypump.diseno.BotonMarca
import com.pumpteam.mypump.diseno.EncabezadoSeccion
import com.pumpteam.mypump.diseno.Espacio
import com.pumpteam.mypump.diseno.Iconos
import com.pumpteam.mypump.diseno.MyPump
import com.pumpteam.mypump.diseno.Radio
import com.pumpteam.mypump.diseno.Tarjeta
import com.pumpteam.mypump.entreno.Letras
import com.pumpteam.mypump.raiz.LocalAlcanceApp
import com.pumpteam.mypump.reglas.CheckinSemanal
import com.pumpteam.mypump.reglas.FotosProgreso
import kotlinx.coroutines.launch

/**
 * Check de la semana (REV-06, gemelo de `CheckSemanal.swift`): cuatro escalas de 1 a 5 y una nota. Cada escala es una
 * fila de botones redondos con sus extremos rotulados ("muy baja → excelente"); el botón dice qué falta ("Faltan: …") en
 * vez de quedar gris sin explicación. Sale por la cola (`ModeloRevision.enviarCheckin`); en la demo queda en la pantalla.
 *
 * El borrador sobrevive a cambiar de pestaña y a rotar, lo guardado no lo pisa mientras el cliente esté tocando, y se
 * vacía al cambiar de semana: antes quedaban las respuestas de la anterior con "Enviar" habilitado (revisión del 14-oct).
 */
@Composable
fun CheckSemanal(revision: ModeloRevision?, modifier: Modifier = Modifier) {
    val alcance = LocalAlcanceApp.current
    val tactil = LocalHapticFeedback.current
    val foco = LocalFocusManager.current
    val guardado = revision?.checkin?.collectAsStateWithLifecycle()?.value
    val semana = revision?.fecha?.collectAsStateWithLifecycle()?.value?.let(FotosProgreso::lunes)
    var valores by rememberSaveable(stateSaver = GuardadorValores) { mutableStateOf(emptyMap<String, Int>()) }
    var nota by rememberSaveable { mutableStateOf("") }
    // El cliente tocó algo: lo que llegue del servidor ya no pisa el borrador.
    var editado by rememberSaveable { mutableStateOf(false) }
    var semanaDelBorrador by rememberSaveable { mutableStateOf(semana) }
    var aviso by remember { mutableStateOf<String?>(null) }
    // `checkinEnviado` del modelo, leído del flujo para recomponer.
    val enviado = (guardado?.valores?.get("energia") ?: 0) > 0
    val faltan = CheckinSemanal.faltan(valores)
    val c = MyPump.colores

    // Lo guardado (o lo que se acaba de mandar) se muestra mientras el cliente no haya tocado nada.
    LaunchedEffect(guardado) {
        if (!editado && guardado != null) {
            valores = guardado.valores
            nota = guardado.nota
        }
    }
    // Semana nueva: el formulario arranca vacío, como en la web.
    LaunchedEffect(semana) {
        if (semana == null || semana == semanaDelBorrador) return@LaunchedEffect
        semanaDelBorrador = semana
        valores = emptyMap()
        nota = ""
        editado = false
        aviso = null
    }

    fun enviar() {
        foco.clearFocus()
        val r = revision ?: return
        alcance.launch {
            val falta = r.enviarCheckin(Checkin(valores, nota))
            if (falta != null) {
                aviso = falta
                tactil.performHapticFeedback(HapticFeedbackType.Reject)
            } else {
                editado = false
                tactil.performHapticFeedback(HapticFeedbackType.Confirm)
            }
        }
    }

    Column(modifier, verticalArrangement = Arrangement.spacedBy(Espacio.s)) {
        Row(verticalAlignment = Alignment.Bottom) {
            val completas = CheckinSemanal.metricas.count { (valores[it.clave] ?: 0) != 0 }
            EncabezadoSeccion("Check de la semana", Modifier.weight(1f), detalle = if (enviado) null else "$completas/4")
            AnimatedVisibility(visible = enviado, enter = scaleIn() + fadeIn(), exit = scaleOut() + fadeOut()) {
                Row(
                    Modifier.padding(end = 4.dp).testTag("check-enviado"),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(4.dp),
                ) {
                    Icon(IconosRevision.Enviado, contentDescription = null, tint = c.marcaTexto, modifier = Modifier.size(18.dp))
                    Text("Enviado", style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold, color = c.marcaTexto)
                }
            }
        }
        Tarjeta(Modifier.animateContentSize(), espaciado = Espacio.l) {
            Text(
                "Contame en 10 segundos cómo venís. Mati lo ve antes de tu devolución.",
                style = MaterialTheme.typography.bodyMedium,
                color = c.textoSecundario,
            )
            for (m in CheckinSemanal.metricas) {
                val (icono, color) = estilo(m.clave)
                EscalaCinco(m, icono, color, valores[m.clave]) { v ->
                    valores = if (v == null) valores - m.clave else valores + (m.clave to v)
                    editado = true
                    aviso = null
                    tactil.performHapticFeedback(HapticFeedbackType.SegmentTick)
                }
            }
            BasicTextField(
                value = nota,
                onValueChange = {
                    nota = it
                    editado = true
                },
                minLines = 2,
                maxLines = 5,
                textStyle = MaterialTheme.typography.bodyLarge.copy(color = c.texto),
                cursorBrush = SolidColor(c.marcaTexto),
                modifier = Modifier
                    .fillMaxWidth()
                    .semantics { contentDescription = "Algo que quieras contarme (opcional)" }
                    .testTag("nota-check"),
                decorationBox = { campo ->
                    Box(
                        Modifier
                            .fillMaxWidth()
                            .heightIn(min = 44.dp)
                            .clip(RoundedCornerShape(Radio.control))
                            .background(c.campo)
                            .padding(horizontal = 14.dp, vertical = 12.dp),
                    ) {
                        if (nota.isEmpty()) {
                            Text(
                                "Algo que quieras contarme (opcional)",
                                style = MaterialTheme.typography.bodyLarge,
                                color = c.textoTerciario,
                                modifier = Modifier.clearAndSetSemantics {},
                            )
                        }
                        campo()
                    }
                },
            )
            Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(Espacio.xs)) {
                BotonMarca(
                    if (enviado) "Actualizar mi check" else "Enviar mi check",
                    alTocar = ::enviar,
                    habilitado = faltan == null && revision != null,
                    modifier = Modifier.testTag("enviar-check"),
                )
                (aviso ?: faltan)?.let { texto ->
                    Text(texto, style = Letras.caption, color = c.textoSecundario, modifier = Modifier.testTag("faltan-check"))
                }
            }
        }
    }
}

/** Ícono y color de cada escala (las claves y los textos salen de `CheckinSemanal.metricas`, como en la web). */
@Composable
private fun estilo(clave: String): Pair<ImageVector, Color> {
    val c = MyPump.colores
    return when (clave) {
        "energia" -> Iconos.Rayo to c.alerta
        "descanso" -> Iconos.Luna to c.sueno
        "hambre" -> Iconos.Cubiertos to c.corazon
        "adherencia" -> Iconos.Mira to c.marcaTexto
        else -> Iconos.Circulo to c.textoSecundario
    }
}

/** Una escala de 1 a 5: cinco círculos de 44 dp; el elegido, en lima. Tocar el elegido lo borra. */
@Composable
private fun EscalaCinco(metrica: CheckinSemanal.Metrica, icono: ImageVector, color: Color, valor: Int?, alCambiar: (Int?) -> Unit) {
    val c = MyPump.colores
    Column(verticalArrangement = Arrangement.spacedBy(Espacio.xs)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            Icon(icono, contentDescription = null, tint = color, modifier = Modifier.size(18.dp))
            Text(metrica.etiqueta, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold)
        }
        Row(Modifier.fillMaxWidth()) {
            for (n in 1..5) {
                val elegido = valor == n
                val escala by animateFloatAsState(if (elegido) 1.08f else 1f, label = "escala")
                Box(Modifier.weight(1f), contentAlignment = Alignment.Center) {
                    Box(
                        Modifier
                            .size(44.dp)
                            .scale(escala)
                            .clip(CircleShape)
                            .background(if (elegido) c.marca else c.campo)
                            .clickable(role = Role.Button) { alCambiar(if (elegido) null else n) }
                            .semantics {
                                contentDescription = "${metrica.etiqueta}: $n de 5"
                                selected = elegido
                            }
                            .testTag("escala-${metrica.clave}-$n"),
                        contentAlignment = Alignment.Center,
                    ) {
                        Text(
                            "$n",
                            style = MaterialTheme.typography.bodyLarge.merge(Letras.cifras),
                            fontWeight = FontWeight.SemiBold,
                            color = if (elegido) c.sobreMarca else c.texto,
                            modifier = Modifier.clearAndSetSemantics {},
                        )
                    }
                }
            }
        }
        Row(Modifier.fillMaxWidth().padding(horizontal = 2.dp).clearAndSetSemantics {}) {
            Text(metrica.bajo, style = Letras.caption2, color = c.textoTerciario, modifier = Modifier.weight(1f))
            Text(metrica.alto, style = Letras.caption2, color = c.textoTerciario)
        }
    }
}

/** El borrador de las escalas, para `rememberSaveable` (un mapa no se guarda solo). */
private val GuardadorValores: Saver<Map<String, Int>, Any> = Saver(
    save = { m -> ArrayList(m.flatMap { (k, v) -> listOf(k, v) }) },
    restore = { l ->
        val lista = l as List<*>
        lista.chunked(2).mapNotNull { (k, v) -> (k as? String)?.let { clave -> (v as? Int)?.let { clave to it } } }.toMap()
    },
)
