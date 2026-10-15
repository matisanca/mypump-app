package com.pumpteam.mypump.revision

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.animateContentSize
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.ProgressBarRangeInfo
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.progressBarRangeInfo
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.setProgress
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.pumpteam.mypump.datos.HabitosHoy
import com.pumpteam.mypump.datos.ModeloRevision
import com.pumpteam.mypump.datos.ModeloSalud
import com.pumpteam.mypump.diseno.BotonSecundario
import com.pumpteam.mypump.diseno.EncabezadoSeccion
import com.pumpteam.mypump.diseno.Espacio
import com.pumpteam.mypump.diseno.Iconos
import com.pumpteam.mypump.diseno.MyPump
import com.pumpteam.mypump.diseno.Numeros
import com.pumpteam.mypump.diseno.Radio
import com.pumpteam.mypump.diseno.Separador
import com.pumpteam.mypump.diseno.Tarjeta
import com.pumpteam.mypump.diseno.superficieTarjeta
import com.pumpteam.mypump.entreno.Ceja
import com.pumpteam.mypump.entreno.Letras
import com.pumpteam.mypump.modelos.DiaAdherencia
import com.pumpteam.mypump.raiz.LocalAlcanceApp
import com.pumpteam.mypump.reglas.DiaCalendario
import com.pumpteam.mypump.reglas.FechaJs
import com.pumpteam.mypump.reglas.FechaLocal
import com.pumpteam.mypump.reglas.RachaTexto
import com.pumpteam.mypump.respaldo.OrigenRespaldo
import com.pumpteam.mypump.respaldo.PieRespaldo
import com.pumpteam.mypump.salud.CardRecuperacion
import com.pumpteam.mypump.salud.CardSalud
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlinx.coroutines.launch
import kotlin.math.roundToInt

/**
 * Mi Día (DIA-01…06, gemelo de `MiDia.swift`): la racha, cómo fue hoy (entrené/descansé/falté, los hábitos ✓/✗ y el
 * agua), la recuperación y la salud (SAL-09/10, con una cuenta), los últimos 30 días y el respaldo científico (GEN-09).
 * Todo sale de `ModeloRevision`, por la cola; lo pendiente gana sobre el servidor (DIA-06). En la demo el modelo viene
 * sembrado (`ModeloRevision.demo`): se toca igual y no sale nada.
 */
@Composable
fun MiDia(revision: ModeloRevision, salud: ModeloSalud?, alVerTodaLaSalud: () -> Unit, modifier: Modifier = Modifier) {
    val habitos by revision.habitos.collectAsStateWithLifecycle()
    val racha by revision.racha.collectAsStateWithLifecycle()
    val ultimoDiaValido by revision.ultimoDiaValido.collectAsStateWithLifecycle()
    val cargado by revision.miDiaCargado.collectAsStateWithLifecycle()
    val adherencia by revision.adherencia.collectAsStateWithLifecycle()
    val alcance = LocalAlcanceApp.current
    val tactil = LocalHapticFeedback.current
    val c = MyPump.colores

    // Entrené/descansé/falté o un hábito ✓/✗: tocar de nuevo lo elegido lo borra, como la web.
    fun tocar(campo: String, valor: String) {
        tactil.performHapticFeedback(HapticFeedbackType.SegmentTick)
        alcance.launch { revision.tocar(campo, valor) }
    }

    Column(modifier, verticalArrangement = Arrangement.spacedBy(Espacio.s)) {
        if (LocalDensity.current.fontScale >= 1.5f) {
            Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                EncabezadoSeccion("Mi día")
                Text(hoyTexto(), style = MaterialTheme.typography.bodyMedium, color = c.textoSecundario, modifier = Modifier.padding(horizontal = 4.dp))
            }
        } else {
            EncabezadoSeccion("Mi día", detalle = hoyTexto())
        }
        Column(verticalArrangement = Arrangement.spacedBy(Espacio.m)) {
            // Hasta que llega lo de hoy, la racha y los botones se ven tenues y no se tocan (el `.redacted` de iOS).
            Column(Modifier.alpha(if (cargado) 1f else 0.4f), verticalArrangement = Arrangement.spacedBy(Espacio.m)) {
                TarjetaRacha(racha, ultimoDiaValido)
                Hoy(
                    habitos,
                    habilitado = cargado,
                    alTocar = ::tocar,
                    alCambiarAgua = { d ->
                        tactil.performHapticFeedback(HapticFeedbackType.SegmentTick)
                        revision.cambiarAgua(d)
                    },
                )
            }
            if (salud != null) {
                CardRecuperacion(salud, alVerTodo = alVerTodaLaSalud)
                CardSalud(salud)
            }
            UltimosTreintaDias(
                adherencia,
                cargar = {
                    revision.cargarAdherencia()
                    revision.adherencia.value
                },
            )
            PieRespaldo(OrigenRespaldo.MI_DIA)
        }
    }
}

private val ES_AR: Locale = Locale.forLanguageTag("es-AR")

/** "miércoles 14 de octubre". */
internal fun hoyTexto(hoy: LocalDate = LocalDate.now()): String = DateTimeFormatter.ofPattern("EEEE d 'de' MMMM", ES_AR).format(hoy)

// MARK: Racha

/**
 * La racha (DIA-01): el número grande en Archivo, el ícono del nivel (🔥 7+, ⚡ 3+, ✨ 1+, 💤 0: `RachaTexto.icono`) y la
 * frase de la web. Desde 2 días dice el último día válido (`renderMydayStreak`: "martes, 21 de julio", o "—").
 */
@Composable
private fun TarjetaRacha(n: Int, ultimoDiaValido: String?) {
    val c = MyPump.colores
    val (nivel, color) = when {
        n >= 7 -> "En llamas" to c.alerta
        n >= 3 -> "Buen ritmo" to c.record
        n >= 1 -> "Arrancando" to c.marcaTexto
        else -> "A retomar" to c.sueno
    }
    val sub = when (n) {
        0 -> "Completá hoy para empezar tu racha"
        1 -> "¡Primer día, seguí así!"
        else -> "Último día válido: ${ultimoDiaValido?.let(FechaJs::diaLargo) ?: "—"}"
    }
    Row(
        Modifier
            .fillMaxWidth()
            .superficieTarjeta()
            .padding(Espacio.m)
            .semantics(mergeDescendants = true) {}
            .testTag("racha"),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(Espacio.m),
    ) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Ceja("Racha activa")
            Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                AnimatedContent(n, transitionSpec = { fadeIn() togetherWith fadeOut() }, label = "racha") { v ->
                    Text("$v", style = Numeros.gigante)
                }
                Text(
                    if (n == 1) "día" else "días",
                    style = MaterialTheme.typography.titleLarge.copy(fontFamily = null),
                    fontWeight = FontWeight.SemiBold,
                    color = c.textoSecundario,
                    modifier = Modifier.padding(bottom = 8.dp),
                )
            }
            Text(sub, style = MaterialTheme.typography.bodySmall, color = c.textoSecundario)
        }
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Box(Modifier.size(64.dp).clip(CircleShape).background(color.copy(alpha = 0.14f)), contentAlignment = Alignment.Center) {
                Text(RachaTexto.icono(n), fontSize = 30.sp)
            }
            Text(nivel, style = Letras.caption, fontWeight = FontWeight.SemiBold, color = color)
        }
    }
}

// MARK: Hoy

@Composable
private fun Hoy(h: HabitosHoy, habilitado: Boolean, alTocar: (String, String) -> Unit, alCambiarAgua: (Int) -> Unit) {
    val c = MyPump.colores
    val letraGrande = LocalDensity.current.fontScale >= 1.5f
    Tarjeta(espaciado = Espacio.l) {
        Column(verticalArrangement = Arrangement.spacedBy(Espacio.s)) {
            Text("Entrenamiento", style = MaterialTheme.typography.titleMedium)
            val opciones = listOf(
                Triple("entrene", "Entrené", Iconos.Pesa),
                Triple("descanso", "Descansé", IconosRevision.Cama),
                Triple("falte", "Falté", Iconos.Cerrar),
            )
            if (letraGrande) {
                Column(verticalArrangement = Arrangement.spacedBy(Espacio.xs)) {
                    for ((clave, titulo, icono) in opciones) {
                        OpcionEntreno(clave, titulo, icono, h.entrenamiento == clave, habilitado, Modifier.fillMaxWidth()) { alTocar("entrenamiento", clave) }
                    }
                }
            } else {
                Row(horizontalArrangement = Arrangement.spacedBy(Espacio.xs)) {
                    for ((clave, titulo, icono) in opciones) {
                        OpcionEntreno(clave, titulo, icono, h.entrenamiento == clave, habilitado, Modifier.weight(1f)) { alTocar("entrenamiento", clave) }
                    }
                }
            }
        }
        Column {
            Text("Hábitos", style = MaterialTheme.typography.titleMedium, modifier = Modifier.padding(bottom = Espacio.xs))
            FilaHabito("comio_segun_plan", h.comioSegunPlan, "Comí según el plan", "Seguiste tu dieta hoy", Iconos.Cubiertos, c.alerta, habilitado, alTocar)
            Separador(sangria = 42.dp)
            FilaHabito("durmio_bien", h.durmioBien, "Dormí bien", "7 horas o más", IconosRevision.Cama, c.sueno, habilitado, alTocar)
            Separador(sangria = 42.dp)
            FilaHabito("cardio", h.cardio, "Hice cardio", "Sesión de cardio hoy", Iconos.Correr, c.corazon, habilitado, alTocar)
        }
        Vasos(h.vasosAgua, habilitado, alCambiarAgua)
    }
}

/** Entrené / Descansé / Falté (DIA-02): el elegido, en lima. */
@Composable
private fun OpcionEntreno(
    clave: String,
    titulo: String,
    icono: ImageVector,
    elegida: Boolean,
    habilitado: Boolean,
    modifier: Modifier,
    alTocar: () -> Unit,
) {
    val c = MyPump.colores
    val contenido = if (elegida) c.sobreMarca else c.texto
    Column(
        modifier
            .heightIn(min = 66.dp)
            .clip(RoundedCornerShape(Radio.control))
            .background(if (elegida) c.marca else c.campo)
            .clickable(enabled = habilitado, role = Role.Button, onClick = alTocar)
            .semantics { selected = elegida }
            .padding(vertical = Espacio.s)
            .testTag("entrenamiento-$clave"),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(6.dp, Alignment.CenterVertically),
    ) {
        Icon(icono, contentDescription = null, tint = contenido, modifier = Modifier.size(22.dp))
        Text(titulo, style = Letras.caption, fontWeight = FontWeight.SemiBold, color = contenido)
    }
}

/** Un hábito con ✗ y ✓ (DIA-03): sin marcar, sí o no; tocar de nuevo lo borra. */
@Composable
private fun FilaHabito(
    campo: String,
    valor: Boolean?,
    titulo: String,
    sub: String,
    icono: ImageVector,
    color: Color,
    habilitado: Boolean,
    alTocar: (String, String) -> Unit,
) {
    val c = MyPump.colores
    Row(Modifier.padding(vertical = 10.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espacio.s)) {
        Box(Modifier.size(30.dp), contentAlignment = Alignment.Center) {
            Icon(icono, contentDescription = null, tint = color, modifier = Modifier.size(20.dp))
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(1.dp)) {
            Text(titulo, style = MaterialTheme.typography.bodyLarge)
            Text(sub, style = Letras.caption, color = c.textoSecundario)
        }
        BotonHabito(campo, si = false, valor, titulo, habilitado, alTocar)
        BotonHabito(campo, si = true, valor, titulo, habilitado, alTocar)
    }
}

@Composable
private fun BotonHabito(campo: String, si: Boolean, valor: Boolean?, titulo: String, habilitado: Boolean, alTocar: (String, String) -> Unit) {
    val c = MyPump.colores
    val activo = valor == si
    val escala by animateFloatAsState(if (activo) 1f else 0.94f, label = "habito")
    Box(
        Modifier
            .size(44.dp)
            .clip(CircleShape)
            .clickable(enabled = habilitado, role = Role.Button) { alTocar(campo, if (si) "true" else "false") }
            // TalkBack dice "Dormí bien: sí, marcado, botón" (el `accessibilityValue` de iOS, que leen también las pruebas).
            // Sin `selected`: con eso Android lo anunciaba además como casilla ("no marcado") encima del estado propio.
            .semantics {
                contentDescription = "$titulo: ${if (si) "sí" else "no"}"
                if (activo) stateDescription = "marcado"
            }
            .testTag("habito-$campo-${if (si) "si" else "no"}"),
        contentAlignment = Alignment.Center,
    ) {
        Box(
            Modifier
                .size(38.dp * escala)
                .clip(CircleShape)
                .background(if (activo) (if (si) c.marca else c.peligro) else c.campo),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                if (si) Iconos.Tilde else Iconos.Cerrar,
                contentDescription = null,
                tint = if (activo) (if (si) c.sobreMarca else Color.White) else c.textoSecundario,
                modifier = Modifier.size(18.dp),
            )
        }
    }
}

/** Agua de 0 a 12 vasos (DIA-04): doce gotas que se llenan, con − y + grandes. Se guarda sola 600 ms después del último toque. */
@Composable
private fun Vasos(agua: Int, habilitado: Boolean, alCambiar: (Int) -> Unit) {
    val c = MyPump.colores
    Column(verticalArrangement = Arrangement.spacedBy(Espacio.s)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("Agua", style = MaterialTheme.typography.titleMedium, modifier = Modifier.weight(1f))
            Text(
                buildAnnotatedString {
                    withStyle(SpanStyle(fontFamily = Numeros.chico.fontFamily, fontWeight = FontWeight.Bold, color = c.texto)) { append("$agua") }
                    append(" de 12 vasos")
                },
                style = MaterialTheme.typography.bodyMedium,
                color = c.textoSecundario,
                modifier = Modifier.testTag("agua"),
            )
        }
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espacio.s)) {
            BotonAgua(Iconos.Menos, "Un vaso menos", habilitado && agua > 0, "agua-menos") { alCambiar(-1) }
            // Para TalkBack las gotas son un control con rango, como un selector: deslizar para arriba o para abajo suma o
            // resta un vaso. Mide lo mismo que los botones (auditoría de accesibilidad del 15-oct, como iOS).
            Row(
                Modifier
                    .weight(1f)
                    .heightIn(min = 44.dp)
                    // La etiqueta va antes: lo que viene después de clearAndSetSemantics se borra con el resto.
                    .testTag("control-agua")
                    .clearAndSetSemantics {
                        contentDescription = "Agua"
                        stateDescription = "$agua de 12 vasos"
                        progressBarRangeInfo = ProgressBarRangeInfo(agua.toFloat(), 0f..12f, steps = 11)
                        if (habilitado) {
                            setProgress { valor ->
                                val nuevo = valor.roundToInt().coerceIn(0, 12)
                                if (nuevo != agua) alCambiar(nuevo - agua)
                                true
                            }
                        }
                    },
                horizontalArrangement = Arrangement.spacedBy(3.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                for (i in 0 until 12) {
                    Box(Modifier.weight(1f), contentAlignment = Alignment.Center) {
                        Icon(
                            if (i < agua) IconosRevision.Gota else IconosRevision.GotaVacia,
                            contentDescription = null,
                            tint = if (i < agua) c.agua else c.textoSecundario.copy(alpha = 0.35f),
                            modifier = Modifier.size(17.dp),
                        )
                    }
                }
            }
            BotonAgua(IconosRevision.Mas, "Un vaso más", habilitado && agua < 12, "agua-mas") { alCambiar(1) }
        }
    }
}

@Composable
private fun BotonAgua(icono: ImageVector, descripcion: String, habilitado: Boolean, etiqueta: String, alTocar: () -> Unit) {
    val c = MyPump.colores
    Box(
        Modifier
            .size(44.dp)
            .clip(CircleShape)
            .background(c.agua.copy(alpha = if (habilitado) 0.14f else 0.06f))
            .clickable(enabled = habilitado, role = Role.Button, onClick = alTocar)
            .semantics { contentDescription = descripcion }
            .testTag(etiqueta),
        contentAlignment = Alignment.Center,
    ) {
        Icon(icono, contentDescription = null, tint = c.agua.copy(alpha = if (habilitado) 1f else 0.4f), modifier = Modifier.size(20.dp))
    }
}

// MARK: Últimos 30 días

/**
 * Los últimos 30 días como calendario (DIA-05): lunes a domingo, cumplido en lima, parcial en lima suave, vacío en gris,
 * y hoy con aro. Se trae al abrirla (como la web: un pedido menos al entrar a Revisión). Sin red, el error y Reintentar
 * en vez de "Cargando…" para siempre.
 */
@Composable
private fun UltimosTreintaDias(dias: List<DiaAdherencia>?, cargar: suspend () -> List<DiaAdherencia>?) {
    var abierto by rememberSaveable { mutableStateOf(false) }
    var cargando by remember { mutableStateOf(false) }
    var fallo by remember { mutableStateOf(false) }
    val alcance = rememberCoroutineScope()
    val c = MyPump.colores
    val giro by animateFloatAsState(if (abierto) 180f else 0f, label = "desplegar")

    suspend fun traer() {
        cargando = true
        fallo = false
        val r = cargar()
        cargando = false
        fallo = r == null
    }

    LaunchedEffect(abierto) { if (abierto && dias == null && !cargando) traer() }

    Tarjeta(Modifier.animateContentSize(), espaciado = Espacio.s) {
        Row(
            Modifier
                .fillMaxWidth()
                .heightIn(min = 32.dp)
                // TalkBack lo dice como "Presioná dos veces para ver tu historial…" (el hint de iOS, en infinitivo).
                .clickable(role = Role.Button, onClickLabel = if (abierto) "ocultar el historial" else "ver tu historial de adherencia") { abierto = !abierto }
                .testTag("ultimos-30"),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(Espacio.xs),
        ) {
            Text("Mis últimos 30 días", style = MaterialTheme.typography.titleMedium, modifier = Modifier.weight(1f))
            if (dias != null) {
                Text(
                    "${dias.count { it.esValido }}/30",
                    style = MaterialTheme.typography.bodyMedium.merge(Letras.cifras),
                    fontWeight = FontWeight.SemiBold,
                    color = c.textoSecundario,
                    modifier = Modifier.testTag("ultimos-30-total"),
                )
            }
            Icon(IconosRevision.Desplegar, contentDescription = null, tint = c.textoTerciario, modifier = Modifier.size(20.dp).rotate(giro))
        }
        if (!abierto) {
            Text("Ver mi historial de adherencia", style = MaterialTheme.typography.bodyMedium, color = c.textoSecundario)
        } else if (dias != null) {
            if (dias.isEmpty()) Text("Sin datos aún", style = MaterialTheme.typography.bodyMedium, color = c.textoSecundario) else Grilla(dias)
        } else if (fallo && !cargando) {
            Column(
                Modifier.fillMaxWidth().heightIn(min = 120.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(Espacio.xs, Alignment.CenterVertically),
            ) {
                Text("No pudimos traer tu historial.", style = MaterialTheme.typography.bodyMedium, color = c.textoSecundario)
                BotonSecundario("Reintentar", alTocar = { alcance.launch { traer() } }, compacto = true, modifier = Modifier.testTag("reintentar-30"))
            }
        } else {
            Row(
                Modifier.fillMaxWidth().heightIn(min = 120.dp),
                horizontalArrangement = Arrangement.spacedBy(Espacio.xs, Alignment.CenterHorizontally),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                CircularProgressIndicator(Modifier.size(18.dp), color = c.textoSecundario, strokeWidth = 2.dp)
                Text("Cargando…", style = MaterialTheme.typography.bodyMedium, color = c.textoSecundario)
            }
        }
    }
}

private class Celda(val dia: Long, val estado: Int, val esHoy: Boolean)

@Composable
private fun Grilla(dias: List<DiaAdherencia>) {
    val c = MyPump.colores
    val hoy = FechaLocal.hoy()
    val celdas = remember(dias, hoy) {
        dias.mapNotNull { d ->
            DiaCalendario.numero(d.fecha)?.let { n ->
                val parcial = d.entrenamiento != null || d.comioSegunPlan != null || d.durmioBien != null
                Celda(n, if (d.esValido) 2 else if (parcial) 1 else 0, d.fecha == hoy)
            }
        }.sortedBy { it.dia }
    }
    if (celdas.isEmpty()) return
    // 1970-01-01 fue jueves: (n + 3) mod 7 es 0 el lunes. Los huecos ponen el primer día en su columna.
    val huecos = Math.floorMod(celdas.first().dia + 3, 7L).toInt()
    val lugares: List<Celda?> = List(huecos) { null } + celdas
    val formato = remember { DateTimeFormatter.ofPattern("d 'de' MMMM", ES_AR) }
    Column(Modifier.testTag("grilla-30"), verticalArrangement = Arrangement.spacedBy(Espacio.s)) {
        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Row(Modifier.clearAndSetSemantics {}, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                for (d in listOf("L", "M", "X", "J", "V", "S", "D")) {
                    Text(d, style = Letras.caption2, fontWeight = FontWeight.SemiBold, color = c.textoSecundario, modifier = Modifier.weight(1f), textAlign = TextAlign.Center)
                }
            }
            for (semana in lugares.chunked(7)) {
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    for (i in 0 until 7) {
                        val celda = semana.getOrNull(i)
                        if (celda == null) {
                            Spacer(Modifier.weight(1f))
                            continue
                        }
                        val fecha = LocalDate.ofEpochDay(celda.dia)
                        val estado = when (celda.estado) {
                            2 -> "cumplido"
                            1 -> "parcial"
                            else -> "sin datos"
                        }
                        val forma = RoundedCornerShape(8.dp)
                        Box(
                            Modifier
                                .weight(1f)
                                .aspectRatio(1f)
                                .clip(forma)
                                .background(fondoCelda(celda.estado))
                                .then(if (celda.esHoy) Modifier.border(2.dp, c.marcaVivo, forma) else Modifier)
                                .clearAndSetSemantics { contentDescription = "${formato.format(fecha)}: $estado" },
                            contentAlignment = Alignment.Center,
                        ) {
                            Text(
                                "${fecha.dayOfMonth}",
                                style = Letras.caption2.merge(Letras.cifras),
                                fontWeight = if (celda.esHoy) FontWeight.Bold else FontWeight.Medium,
                                color = when (celda.estado) {
                                    2 -> c.sobreMarca
                                    1 -> c.texto
                                    else -> c.textoSecundario
                                },
                            )
                        }
                    }
                }
            }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(Espacio.s)) {
            for ((estado, texto) in listOf(2 to "Cumplido", 1 to "Parcial", 0 to "Sin datos")) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                    Box(Modifier.size(12.dp).clip(RoundedCornerShape(3.dp)).background(fondoCelda(estado)))
                    Text(texto, style = Letras.caption, color = c.textoSecundario)
                }
            }
        }
    }
}

@Composable
private fun fondoCelda(estado: Int): Color {
    val c = MyPump.colores
    return when (estado) {
        2 -> c.marca
        1 -> c.marca.copy(alpha = 0.35f)
        else -> c.campo
    }
}
