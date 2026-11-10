package com.pumpteam.mypump.guia

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.repeatOnLifecycle
import com.pumpteam.mypump.Entorno
import com.pumpteam.mypump.avisos.CentroAvisos
import com.pumpteam.mypump.datos.ModeloAgenda
import com.pumpteam.mypump.datos.ModeloApp
import com.pumpteam.mypump.diseno.AccionHoja
import com.pumpteam.mypump.diseno.AnchoLectura
import com.pumpteam.mypump.diseno.Archivo
import com.pumpteam.mypump.diseno.BotonMarca
import com.pumpteam.mypump.diseno.EncabezadoHoja
import com.pumpteam.mypump.diseno.Espacio
import com.pumpteam.mypump.diseno.Iconos
import com.pumpteam.mypump.diseno.MyPump
import com.pumpteam.mypump.diseno.Radio
import com.pumpteam.mypump.diseno.superficieTarjeta
import com.pumpteam.mypump.modelos.AgendaEntrega
import com.pumpteam.mypump.modelos.FranjaEntrega
import com.pumpteam.mypump.modelos.ReservaEntrega
import com.pumpteam.mypump.modelos.TipoVideollamada
import com.pumpteam.mypump.reglas.ReglasAgenda
import com.pumpteam.mypump.salud.PantallaSuperpuesta
import java.time.Instant
import java.time.ZoneId
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

// La videollamada (2.3.0, decisión de Mati del 10/11), gemelo de VideollamadaView.swift: el alumno entra desde la app,
// nunca por un link de WhatsApp.
// · La tarjeta fija arriba de Entreno, desde que se agenda hasta que termina: día y hora (la del teléfono y la de Argentina
//   si difiere), «Vas a entrar a la videollamada desde acá», «Entrar» apagado con la cuenta regresiva y activo desde 10
//   minutos antes (Meet restringido: Mati lo admite y el alumno espera en la sala), y «¿Cómo entro?». La misma tarjeta va
//   al final de la guía en lugar de la confirmada de la 2.2.0.
// · Los avisos locales (un día antes y cuando se habilita «Entrar»), solo si la app ya tenía el permiso: nunca lo pide.
// · Con la palanca `elegir_horario`: la pantalla para elegir el horario (lo decide el servidor) y para cambiarlo con el
//   tope que manda el servidor. Sin la palanca, la agenda de la guía queda como en la 2.2.0.
// Al alumno nunca se le dice «entrega»: «videollamada de comienzo» o «de revisión».

object Videollamada {
    /**
     * Solo en las builds de prueba (la pone MainActivity con `--ez elegirHorario true|false`, o una prueba): pisa la
     * palanca `elegir_horario` para probar y sacar capturas. En la de la tienda queda en null y manda la palanca.
     */
    var forzada: Boolean?
        get() = ModeloApp.elegirHorarioForzado
        set(v) {
            ModeloApp.elegirHorarioForzado = v
        }

    /** La palanca `elegir_horario` (apagada de fábrica). */
    @Composable
    fun elegirHorario(modelo: ModeloApp): Boolean {
        val palanca by modelo.palanca.collectAsStateWithLifecycle()
        return forzada ?: palanca.elegirHorario
    }
}

/** La hora, que se vuelve a mirar cada 15 s (y al cambiar [clave]): la cuenta regresiva y el botón a tiempo. */
@Composable
internal fun ahoraCada15s(clave: Any?): Instant {
    val ahora by produceState(Instant.now(), clave) {
        while (true) {
            value = Instant.now()
            delay(15_000)
        }
    }
    return ahora
}

/** La letra está muy grande (Ajustes, 1,5 o más): lo que va en fila pasa a columna. */
@Composable
private fun letraGrande(): Boolean = LocalDensity.current.fontScale >= 1.5f

// ── En Entreno: la tarjeta fija arriba ──

/**
 * Arriba de todo en Entreno: la videollamada agendada (hasta que termina) o, con la palanca y horarios libres, «Agendá tu
 * videollamada». La reserva sale de la agenda (si se consultó) o del resumen. Con la pantalla en primer plano y en la
 * ventana, la agenda se consulta cada 30 s (el link si falta y «Mati ya está en la sala»). También agenda o borra los
 * avisos locales cuando cambia la reserva. Sin nada que mostrar no ocupa lugar.
 */
@Composable
fun TarjetaVideollamadaEntreno(modelo: ModeloApp, modifier: Modifier = Modifier) {
    val g = modelo.guia.collectAsStateWithLifecycle().value ?: return
    val resumen by g.resumen.collectAsStateWithLifecycle()
    val agenda by g.agenda.agenda.collectAsStateWithLifecycle()
    val guia by g.guia.collectAsStateWithLifecycle()
    val reservando by g.agenda.reservando.collectAsStateWithLifecycle()
    val desdeCache by g.agenda.desdeCache.collectAsStateWithLifecycle()
    val esDemo by modelo.esDemo.collectAsStateWithLifecycle()
    val elegir = Videollamada.elegirHorario(modelo)
    // La del resumen solo mientras la agenda no se trajo: si la agenda ya contestó sin reserva o con la reserva caída
    // (cancelada, en fallo), la del resumen es vieja y no puede dejar «Entrar» ni los avisos.
    val deLaAgenda = agenda
    val fuente = if (deLaAgenda != null) deLaAgenda.reserva else resumen?.reserva
    val ahora = ahoraCada15s(fuente)
    val r = fuente?.takeIf { ReglasAgenda.paraTarjeta(it, ahora) }
    var pantalla by remember { mutableStateOf<ModoHorario?>(null) }

    val ciclo = LocalLifecycleOwner.current.lifecycle
    LaunchedEffect(g, ciclo, elegir) {
        ciclo.repeatOnLifecycle(Lifecycle.State.RESUMED) {
            // La reserva vino solo del resumen (la guía no se abrió), o la palanca pide saber si hay horarios: la agenda.
            if (g.agenda.agenda.value == null && (g.resumen.value?.reserva != null || elegir)) g.agenda.refrescar()
            g.agenda.seguirSala { g.agenda.agenda.value.let { a -> if (a != null) a.reserva else g.resumen.value?.reserva } }
        }
    }
    // Los avisos: ids fijos (reprogramar pisa); sin reserva confirmada, se borran. Nunca en la demo ni en las pruebas.
    val contexto = LocalContext.current
    val confirmada = r?.takeIf { it.estado == ReservaEntrega.Estado.CONFIRMADA }
    val desdeMin = agenda?.entrarDesdeMin
    LaunchedEffect(confirmada?.inicio, confirmada?.tipo, desdeMin, esDemo) {
        if (esDemo || Entorno.enPruebas) return@LaunchedEffect
        CentroAvisos.programarVideollamada(contexto, ReglasAgenda.avisosLocales(confirmada, Instant.now(), ZoneId.systemDefault(), desdeMin))
    }

    if (r != null) {
        TarjetaVideollamada(
            modeloAgenda = g.agenda,
            agenda = agenda,
            reserva = r,
            ahora = ahora,
            desdeCache = desdeCache,
            esDemo = esDemo,
            elegirHorario = elegir,
            alCambiar = { pantalla = ModoHorario.Cambiar(r) },
            modifier = modifier,
        )
    } else if (elegir && agenda != null && reservando == null) {
        val a = agenda!!
        val vista = ReglasAgenda.vista(a, ReglasAgenda.faltanAMostrar(a, guia), reservando != null)
        if (vista == ReglasAgenda.Vista.ELEGIR) {
            val aviso by g.agenda.aviso.collectAsStateWithLifecycle()
            TarjetaElegirHorario(a, aviso, alAbrir = { pantalla = ModoHorario.Elegir }, modifier = modifier)
        }
    }
    pantalla?.let { m -> PantallaHorario(g.agenda, (m as? ModoHorario.Cambiar)?.reserva, alCerrar = { pantalla = null }) }
}

/** Qué se abre: elegir por primera vez o cambiar la que hay. */
internal sealed interface ModoHorario {
    data object Elegir : ModoHorario

    data class Cambiar(val reserva: ReservaEntrega) : ModoHorario
}

// ── La tarjeta de la videollamada (Entreno y el final de la guía) ──

/**
 * La videollamada agendada. Lejos: la tarjeta de siempre con un borde verde, «Entrar» apagado con candado y la cuenta
 * regresiva. Habilitada (desde 10 minutos antes): verde llena, para que no haya dudas de dónde tocar, con el botón blanco
 * «Entrar a la videollamada» que abre el Meet (la app de Meet si está; si no, el navegador).
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun TarjetaVideollamada(
    modeloAgenda: ModeloAgenda,
    agenda: AgendaEntrega?,
    reserva: ReservaEntrega,
    ahora: Instant,
    desdeCache: Boolean,
    esDemo: Boolean,
    elegirHorario: Boolean,
    alCambiar: () -> Unit,
    modifier: Modifier = Modifier,
    etiqueta: String = "videollamada",
) {
    val c = MyPump.colores
    val contexto = LocalContext.current
    val zona = ZoneId.systemDefault()
    val desdeMin = agenda?.entrarDesdeMin
    val estado = ReglasAgenda.estadoEntrar(reserva, ahora, desdeMin)
    val activa = estado == ReglasAgenda.EstadoEntrar.Habilitado
    val confirmada = reserva.estado == ReservaEntrega.Estado.CONFIRMADA
    val grande = letraGrande()
    val sobre = if (activa) Color.White else c.texto
    val secundario = if (activa) Color.White.copy(alpha = 0.86f) else c.textoSecundario
    val forma = RoundedCornerShape(Radio.tarjeta)
    val fondo by animateColorAsState(if (activa) VerdeGuia else c.tarjeta, label = "fondo-videollamada")
    Column(
        modifier
            .fillMaxWidth()
            .then(
                if (activa) Modifier.shadow(16.dp, forma, ambientColor = VerdeGuia.copy(alpha = 0.35f), spotColor = VerdeGuia.copy(alpha = 0.35f))
                    .clip(forma).background(fondo)
                else Modifier.superficieTarjeta().border(1.5.dp, c.marca.copy(alpha = 0.45f), forma),
            )
            .padding(20.dp)
            .testTag(etiqueta),
        verticalArrangement = Arrangement.spacedBy(Espacio.m),
    ) {
        if (desdeCache) {
            Row(
                Modifier.semantics(mergeDescendants = true) { liveRegion = LiveRegionMode.Polite }.testTag("agenda-sin-conexion"),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                Icon(Iconos.SinWifi, contentDescription = null, tint = if (activa) Color.White else c.alerta, modifier = Modifier.size(18.dp))
                Text("Sin conexión", style = MaterialTheme.typography.labelLarge, color = if (activa) Color.White else c.alerta)
            }
        }
        // La cabecera: el ícono, «Tu videollamada de comienzo» y «Hoy», «Mañana» o «En 3 días».
        val cuando = ReglasAgenda.cuando(reserva, zona, ahora)
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espacio.xs)) {
            Box(
                Modifier.size(30.dp).clip(CircleShape).background(if (activa) Color.White else c.marca),
                contentAlignment = Alignment.Center,
            ) {
                Icon(Iconos.Video, contentDescription = null, tint = if (activa) VerdeGuia else c.sobreMarca, modifier = Modifier.size(17.dp))
            }
            Text(
                ReglasAgenda.tituloTarjeta(reserva.tipo),
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.Bold,
                color = if (activa) Color.White else c.marcaTexto,
                modifier = Modifier.weight(1f).semantics { heading() },
            )
            if (cuando != null && !grande) Etiqueta(cuando, activa)
        }
        // El día y la hora, grande.
        reserva.inicio?.let { inicio ->
            Column(
                Modifier.semantics(mergeDescendants = true) {}.testTag("videollamada-dia"),
                verticalArrangement = Arrangement.spacedBy(2.dp),
            ) {
                if (cuando != null && grande) Etiqueta(cuando, activa)
                Text(
                    ReglasAgenda.mayuscula(ReglasAgenda.dia(inicio, zona)),
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold,
                    color = sobre,
                )
                FlowRow(
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                    itemVerticalAlignment = Alignment.Bottom,
                ) {
                    Text(
                        ReglasAgenda.hora(inicio, zona),
                        style = MaterialTheme.typography.displaySmall.copy(fontSize = 44.sp, lineHeight = 50.sp, fontFeatureSettings = "tnum"),
                        fontFamily = Archivo,
                        fontWeight = FontWeight.W800,
                        color = sobre,
                    )
                    ReglasAgenda.finDe(reserva)?.takeIf { reserva.fin != null }?.let { fin ->
                        Text(
                            "a ${ReglasAgenda.hora(fin, zona)}",
                            style = MaterialTheme.typography.titleMedium.copy(fontFeatureSettings = "tnum"),
                            color = secundario,
                            modifier = Modifier.padding(bottom = 6.dp),
                        )
                    }
                }
                ReglasAgenda.horaArgentina(inicio, zona)?.let { ar ->
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        Icon(Iconos.Reloj, contentDescription = null, tint = secundario, modifier = Modifier.size(16.dp))
                        Text(ar, style = MaterialTheme.typography.bodySmall, color = secundario, modifier = Modifier.testTag("videollamada-argentina"))
                    }
                }
            }
        }
        if (reserva.estado == ReservaEntrega.Estado.PENDIENTE) {
            Row(
                Modifier.semantics(mergeDescendants = true) { liveRegion = LiveRegionMode.Polite }.testTag("videollamada-reservando"),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(Espacio.s),
            ) {
                CircularProgressIndicator(color = c.marca, strokeWidth = 3.dp, modifier = Modifier.size(22.dp))
                Text(ReglasAgenda.texto(agenda, "pendiente", ReglasAgenda.TEXTO_PENDIENTE), style = MaterialTheme.typography.bodyLarge, color = sobre)
            }
        } else if (activa) {
            Text(
                ReglasAgenda.textoEntrar(reserva, zona, agenda),
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold,
                color = Color.White,
                modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite }.testTag("agenda-sala"),
            )
            Button(
                onClick = { reserva.meetUrl?.let { abrirMeet(contexto, it) } },
                modifier = Modifier
                    .fillMaxWidth()
                    .defaultMinSize(minHeight = 56.dp)
                    .semantics { contentDescription = "Entrar a la videollamada. Abre Google Meet. Mati te admite en la sala" }
                    .testTag("agenda-entrar"),
                shape = CircleShape,
                colors = ButtonDefaults.buttonColors(containerColor = Color.White, contentColor = VerdeGuia),
                elevation = null,
                contentPadding = PaddingValues(horizontal = 20.dp, vertical = 10.dp),
            ) {
                Icon(Iconos.Video, contentDescription = null, modifier = Modifier.size(22.dp))
                Spacer(Modifier.size(Espacio.xs))
                Text("Entrar a la videollamada", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center)
            }
            Text(ReglasAgenda.TEXTO_ADMITE, style = MaterialTheme.typography.bodyMedium, color = Color.White, modifier = Modifier.testTag("videollamada-admite"))
        } else if (confirmada) {
            val cuenta = ReglasAgenda.textoCuenta(estado, desdeMin)
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Row(
                    Modifier
                        .fillMaxWidth()
                        .heightIn(min = 54.dp)
                        .clip(CircleShape)
                        .background(c.campo)
                        // La etiqueta va antes: clearAndSetSemantics borra la de adentro.
                        .testTag("videollamada-entrar-apagado")
                        // TalkBack: «Entrar, desactivado. Se habilita en 2 h 15 min».
                        .clearAndSetSemantics {
                            contentDescription = "Entrar, todavía no" + (cuenta?.let { ". $it" } ?: "")
                            stateDescription = "Desactivado"
                        },
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.Center,
                ) {
                    Icon(Iconos.Candado, contentDescription = null, tint = c.textoSecundario, modifier = Modifier.size(18.dp))
                    Spacer(Modifier.size(6.dp))
                    Text("Entrar", style = MaterialTheme.typography.titleMedium, color = c.textoSecundario)
                }
                if (cuenta != null) {
                    Text(
                        cuenta,
                        style = MaterialTheme.typography.bodyMedium.copy(fontFeatureSettings = "tnum"),
                        fontWeight = FontWeight.SemiBold,
                        color = c.textoSecundario,
                        textAlign = TextAlign.Center,
                        modifier = Modifier.fillMaxWidth().testTag("videollamada-cuenta").clearAndSetSemantics {},
                    )
                }
            }
            ReglasAgenda.textoHoy(reserva, zona, ahora, agenda)?.let {
                Text(it, style = MaterialTheme.typography.bodyMedium, color = c.texto, modifier = Modifier.testTag("videollamada-hoy"))
            }
            Linea(Iconos.Toque, ReglasAgenda.TEXTO_DESDE_ACA, c.marcaTexto, sobre, Modifier.testTag("videollamada-desde-aca"))
            if (esDemo && reserva.meetUrl == null) {
                Text(ReglasAgenda.TEXTO_DEMO, style = MaterialTheme.typography.bodySmall, color = c.textoSecundario, modifier = Modifier.testTag("agenda-demo"))
            }
        }
        if (confirmada) ComoEntro(activa)
        if (confirmada && !activa) {
            val puedeCambiar = elegirHorario && ReglasAgenda.puedeCambiar(agenda, ahora)
            FlowRow(horizontalArrangement = Arrangement.spacedBy(Espacio.xs), verticalArrangement = Arrangement.spacedBy(Espacio.xs)) {
                Pildora(Iconos.Calendario, "Al calendario", "Agregar a mi calendario", Modifier.testTag("agenda-calendario")) {
                    agregarAlCalendario(contexto, reserva)
                }
                if (puedeCambiar) {
                    Pildora(Iconos.Intercambio, "Cambiar horario", null, Modifier.testTag("videollamada-cambiar"), alTocar = alCambiar)
                }
            }
            if (!puedeCambiar) {
                Text(
                    ReglasAgenda.texto(agenda, "cambiar", ReglasAgenda.TEXTO_CAMBIAR),
                    style = MaterialTheme.typography.bodySmall,
                    color = c.textoSecundario,
                    modifier = Modifier.testTag("agenda-cambiar"),
                )
            }
        }
    }
}

/** «Hoy», «Mañana», «En 3 días», en una cápsula. */
@Composable
private fun Etiqueta(texto: String, activa: Boolean) {
    val c = MyPump.colores
    Text(
        texto,
        style = MaterialTheme.typography.labelMedium,
        fontWeight = FontWeight.Bold,
        color = if (activa) VerdeGuia else c.marcaTexto,
        modifier = Modifier
            .clip(CircleShape)
            .background(if (activa) Color.White else c.marcaSuave)
            .padding(horizontal = 10.dp, vertical = 5.dp)
            .testTag("videollamada-cuando"),
    )
}

@Composable
private fun Linea(icono: ImageVector, texto: String, tono: Color, color: Color, modifier: Modifier = Modifier) {
    Row(
        modifier.clearAndSetSemantics { contentDescription = texto },
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(Espacio.xs),
    ) {
        Icon(icono, contentDescription = null, tint = tono, modifier = Modifier.size(20.dp))
        Text(texto, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Medium, color = color)
    }
}

/** Un botón chico en cápsula gris, con ícono (los secundarios de la tarjeta). */
@Composable
private fun Pildora(icono: ImageVector, texto: String, descripcion: String?, modifier: Modifier = Modifier, alTocar: () -> Unit) {
    val c = MyPump.colores
    Button(
        onClick = alTocar,
        modifier = modifier
            .defaultMinSize(minHeight = 44.dp)
            .then(if (descripcion != null) Modifier.semantics { contentDescription = descripcion } else Modifier),
        shape = CircleShape,
        colors = ButtonDefaults.buttonColors(containerColor = c.campo, contentColor = c.marcaTexto),
        elevation = null,
        contentPadding = PaddingValues(horizontal = 14.dp, vertical = 8.dp),
    ) {
        Icon(icono, contentDescription = null, modifier = Modifier.size(18.dp))
        Spacer(Modifier.size(6.dp))
        Text(texto, style = MaterialTheme.typography.labelLarge, fontWeight = FontWeight.SemiBold)
    }
}

/** «¿Cómo entro?», desplegable con los 4 pasos. */
@Composable
private fun ColumnScope.ComoEntro(activa: Boolean) {
    val c = MyPump.colores
    var abierto by rememberSaveable { mutableStateOf(false) }
    val tono = if (activa) Color.White else c.marcaTexto
    val giro by animateFloatAsState(if (abierto) 180f else 0f, label = "giro-como-entro")
    // Los signos dentro de un círculo fijo no crecen con la letra (con 2x se salían): son decorativos, TalkBack no los lee.
    val (signo, numero) = with(LocalDensity.current) { 12.dp.toSp() to 13.dp.toSp() }
    Column(verticalArrangement = Arrangement.spacedBy(Espacio.xs)) {
        Row(
            Modifier
                .fillMaxWidth()
                .heightIn(min = 44.dp)
                .toggleable(value = abierto, role = Role.Button, onValueChange = { abierto = it })
                .semantics { stateDescription = if (abierto) "Abierto" else "Cerrado" }
                .testTag("videollamada-como-entro"),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(Espacio.xs),
        ) {
            Box(Modifier.size(20.dp).border(1.6.dp, tono, CircleShape), contentAlignment = Alignment.Center) {
                Text("?", fontSize = signo, lineHeight = signo, fontWeight = FontWeight.Bold, color = tono, modifier = Modifier.clearAndSetSemantics {})
            }
            Text("¿Cómo entro?", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold, color = tono, modifier = Modifier.weight(1f))
            Icon(Iconos.Chevron, contentDescription = null, tint = tono, modifier = Modifier.size(18.dp).rotate(90f + giro))
        }
        AnimatedVisibility(abierto) {
            Column(Modifier.testTag("videollamada-ayuda"), verticalArrangement = Arrangement.spacedBy(Espacio.xs)) {
                ReglasAgenda.AYUDA_ENTRAR.forEachIndexed { i, t ->
                    Row(Modifier.semantics(mergeDescendants = true) {}, horizontalArrangement = Arrangement.spacedBy(Espacio.xs)) {
                        Box(
                            Modifier.size(24.dp).clip(CircleShape).background(if (activa) Color.White.copy(alpha = 0.22f) else c.marcaSuave),
                            contentAlignment = Alignment.Center,
                        ) {
                            Text("${i + 1}", fontSize = numero, lineHeight = numero, fontWeight = FontWeight.Bold, color = tono, modifier = Modifier.clearAndSetSemantics {})
                        }
                        Text(t, style = MaterialTheme.typography.bodyMedium, color = if (activa) Color.White else c.texto, modifier = Modifier.weight(1f))
                    }
                }
            }
        }
    }
}

// ── «Agendá tu videollamada» (palanca) ──

@Composable
fun TarjetaElegirHorario(agenda: AgendaEntrega, aviso: String?, alAbrir: () -> Unit, modifier: Modifier = Modifier) {
    val c = MyPump.colores
    val zona = ZoneId.systemDefault()
    Column(
        modifier
            .fillMaxWidth()
            .superficieTarjeta()
            .border(1.5.dp, c.marca.copy(alpha = 0.45f), RoundedCornerShape(Radio.tarjeta))
            .padding(20.dp)
            .testTag("videollamada-agendar"),
        verticalArrangement = Arrangement.spacedBy(Espacio.s),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espacio.xs)) {
            Box(Modifier.size(30.dp).clip(CircleShape).background(c.marca), contentAlignment = Alignment.Center) {
                Icon(Iconos.Calendario, contentDescription = null, tint = c.sobreMarca, modifier = Modifier.size(17.dp))
            }
            Text(
                ReglasAgenda.textoTitulo(agenda),
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold,
                modifier = Modifier.weight(1f).semantics { heading() },
            )
        }
        if (aviso != null) AvisoHorario(aviso, Modifier.testTag("videollamada-aviso"))
        Text(ReglasAgenda.textoAgendar(agenda.franjas, zona), style = MaterialTheme.typography.bodyMedium, color = c.textoSecundario)
        BotonMarca("Elegir horario", alTocar = alAbrir, modifier = Modifier.testTag("videollamada-elegir"))
    }
}

@Composable
private fun AvisoHorario(texto: String, modifier: Modifier = Modifier) {
    val c = MyPump.colores
    Row(
        modifier.semantics(mergeDescendants = true) { liveRegion = LiveRegionMode.Polite },
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(Espacio.xs),
    ) {
        Icon(Iconos.Alerta, contentDescription = null, tint = c.alerta, modifier = Modifier.size(20.dp))
        Text(texto, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold, color = c.alerta)
    }
}

// ── Elegir o cambiar el horario (palanca) ──

/**
 * La pantalla para elegir el horario ([cambiando] null) o cambiarlo: una tarjeta por día con botones grandes por horario,
 * la selección resaltada con su tilde y el botón fijo abajo («Elegí un horario» apagado, «Confirmar jueves 12, 10:00»).
 * Al quedar: «Listo, quedó agendada» (o «Listo, la cambiamos»). Tomada, vencida o sin cambio: se vuelve a elegir con el
 * aviso arriba.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun PantallaHorario(modeloAgenda: ModeloAgenda, cambiando: ReservaEntrega?, alCerrar: () -> Unit) {
    val c = MyPump.colores
    val contexto = LocalContext.current
    val alcance = rememberCoroutineScope()
    val zona = ZoneId.systemDefault()
    val agenda by modeloAgenda.agenda.collectAsStateWithLifecycle()
    val reservando by modeloAgenda.reservando.collectAsStateWithLifecycle()
    val aviso by modeloAgenda.aviso.collectAsStateWithLifecycle()
    var elegido by remember { mutableStateOf<FranjaEntrega?>(null) }
    var enviado by remember { mutableStateOf(false) }
    val conAvisos = remember { CentroAvisos.concedido(contexto) }
    val tipo = cambiando?.tipo ?: agenda?.tipo ?: TipoVideollamada.COMIENZO
    // Lo que ya quedó: la reserva confirmada que no es la que se cambia.
    val lista = agenda?.reserva?.takeIf { enviado && it.estado == ReservaEntrega.Estado.CONFIRMADA && (cambiando == null || it.inicio != cambiando.inicio) }
    val enviando = enviado && lista == null && (reservando != null || agenda?.reserva?.estado == ReservaEntrega.Estado.PENDIENTE)
    // Tomada, vencida o sin cambio: se vuelve a elegir con el aviso arriba.
    LaunchedEffect(aviso) {
        if (aviso != null && enviado) {
            enviado = false
            elegido = null
        }
    }
    PantallaSuperpuesta(alCerrar = alCerrar) {
        Column(Modifier.fillMaxSize().background(c.fondo).systemBarsPadding().testTag("horario")) {
            if (lista == null) {
                EncabezadoHoja(
                    if (cambiando == null) "Elegí tu horario" else "Cambiar horario",
                    cancelar = AccionHoja("Cerrar", "horario-cerrar", alTocar = alCerrar),
                )
                Elegir(agenda, cambiando, tipo, aviso, elegido, habilitado = !enviando, zona = zona, modifier = Modifier.weight(1f)) { elegido = it }
                // El botón fijo abajo.
                Column(
                    Modifier.fillMaxWidth().background(c.fondo).padding(horizontal = Espacio.m, vertical = Espacio.s),
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    Box(Modifier.widthIn(max = AnchoLectura).fillMaxWidth()) {
                        if (enviando) {
                            Row(
                                Modifier.fillMaxWidth().heightIn(min = 54.dp).semantics(mergeDescendants = true) { liveRegion = LiveRegionMode.Polite }
                                    .testTag("horario-enviando"),
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(Espacio.s, Alignment.CenterHorizontally),
                            ) {
                                CircularProgressIndicator(color = c.marca, strokeWidth = 3.dp, modifier = Modifier.size(22.dp))
                                Text(
                                    if (cambiando == null) ReglasAgenda.texto(agenda, "pendiente", ReglasAgenda.TEXTO_PENDIENTE) else "Estamos cambiando tu horario…",
                                    style = MaterialTheme.typography.titleSmall,
                                )
                            }
                        } else {
                            BotonMarca(
                                elegido?.let { ReglasAgenda.textoBotonElegir(it, cambiando != null, zona) } ?: "Elegí un horario",
                                alTocar = {
                                    val f = elegido ?: return@BotonMarca
                                    enviado = true
                                    alcance.launch {
                                        val ok = if (cambiando != null) modeloAgenda.cambiar(f) else modeloAgenda.reservar(f)
                                        if (!ok) enviado = false
                                    }
                                },
                                habilitado = elegido != null,
                                modifier = Modifier.testTag("horario-confirmar"),
                            )
                        }
                    }
                }
            } else {
                Listo(lista, cambiando != null, conAvisos, alCerrar = alCerrar, alCalendario = { agregarAlCalendario(contexto, lista) })
            }
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun Elegir(
    agenda: AgendaEntrega?,
    cambiando: ReservaEntrega?,
    tipo: TipoVideollamada,
    aviso: String?,
    elegido: FranjaEntrega?,
    habilitado: Boolean,
    zona: ZoneId,
    modifier: Modifier,
    alElegir: (FranjaEntrega?) -> Unit,
) {
    val c = MyPump.colores
    val franjas = agenda?.franjas.orEmpty().filter { it.inicio != cambiando?.inicio }
    val dias = remember(franjas, zona) { ReglasAgenda.porDia(franjas, zona) }
    val grande = letraGrande()
    Column(
        modifier.fillMaxWidth().verticalScroll(rememberScrollState()),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Column(
            Modifier.widthIn(max = AnchoLectura).fillMaxWidth().padding(horizontal = Espacio.m).padding(top = Espacio.xs, bottom = Espacio.l),
            verticalArrangement = Arrangement.spacedBy(Espacio.l),
        ) {
            Column(verticalArrangement = Arrangement.spacedBy(Espacio.xs)) {
                Text(
                    if (cambiando == null) ReglasAgenda.tituloElegir(tipo) else "Elegí el nuevo horario",
                    style = MaterialTheme.typography.headlineSmall,
                    modifier = Modifier.semantics { heading() }.testTag("horario-titulo"),
                )
                Text(ReglasAgenda.textoElegirPantalla(franjas), style = MaterialTheme.typography.bodyLarge, color = c.textoSecundario)
                if (ReglasAgenda.difiereDeArgentina(zona, franjas.map { it.inicio })) {
                    Text(ReglasAgenda.TEXTO_HORARIO_TELEFONO, style = MaterialTheme.typography.bodySmall, color = c.textoSecundario)
                }
            }
            if (cambiando != null) {
                Column(
                    Modifier.fillMaxWidth().clip(RoundedCornerShape(Radio.control)).background(c.marcaSuave).padding(Espacio.m)
                        .semantics(mergeDescendants = true) {}.testTag("horario-ahora-es"),
                    verticalArrangement = Arrangement.spacedBy(4.dp),
                ) {
                    ReglasAgenda.textoAhoraEs(cambiando, zona)?.let { Text(it, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold) }
                    ReglasAgenda.textoTope(agenda?.cambio, zona)?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = c.textoSecundario) }
                }
            }
            if (aviso != null) AvisoHorario(aviso, Modifier.testTag("horario-aviso"))
            if (dias.isEmpty()) {
                Text(ReglasAgenda.texto(agenda, "sin_franjas", ReglasAgenda.TEXTO_SIN_FRANJAS), style = MaterialTheme.typography.bodyLarge, modifier = Modifier.testTag("horario-sin-franjas"))
            }
            for ((dia, delDia) in dias) {
                Column(
                    Modifier.fillMaxWidth().superficieTarjeta(radio = Radio.control + 6.dp).padding(Espacio.m),
                    verticalArrangement = Arrangement.spacedBy(Espacio.s),
                ) {
                    Text(ReglasAgenda.mayuscula(dia), style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold, modifier = Modifier.semantics { heading() })
                    FlowRow(
                        horizontalArrangement = Arrangement.spacedBy(Espacio.xs),
                        verticalArrangement = Arrangement.spacedBy(Espacio.xs),
                        maxItemsInEachRow = if (grande) 1 else 2,
                    ) {
                        for (f in delDia) {
                            val sel = elegido?.id == f.id
                            Horario(f, sel, habilitado, zona, dia, Modifier.weight(1f)) { alElegir(if (sel) null else f) }
                        }
                    }
                }
            }
        }
    }
}

/** Un botón grande por horario: la hora y, abajo, «a 11:00» (o la de Argentina si el teléfono da otra). */
@Composable
private fun Horario(f: FranjaEntrega, sel: Boolean, habilitado: Boolean, zona: ZoneId, dia: String, modifier: Modifier, alTocar: () -> Unit) {
    val c = MyPump.colores
    val forma = RoundedCornerShape(Radio.control)
    val fondo by animateColorAsState(if (sel) c.marca else c.campo, label = "fondo-horario")
    val texto = if (sel) c.sobreMarca else c.texto
    Box(
        modifier
            .heightIn(min = 76.dp)
            .clip(forma)
            .background(fondo)
            .then(if (sel) Modifier else Modifier.border(1.dp, c.borde, forma))
            .clickable(enabled = habilitado, role = Role.Button, onClick = alTocar)
            .semantics(mergeDescendants = true) {
                contentDescription = "$dia, a las ${ReglasAgenda.hora(f.inicio, zona)}"
                selected = sel
            }
            .testTag("horario-franja-${f.id}"),
        contentAlignment = Alignment.Center,
    ) {
        Column(Modifier.padding(vertical = 10.dp, horizontal = 12.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            Text(
                ReglasAgenda.hora(f.inicio, zona),
                style = MaterialTheme.typography.titleLarge.copy(fontSize = 26.sp, lineHeight = 30.sp, fontFeatureSettings = "tnum"),
                fontWeight = FontWeight.W800,
                color = texto,
            )
            Text(
                ReglasAgenda.horaArgentina(f.inicio, zona) ?: "a ${ReglasAgenda.hora(f.fin, zona)}",
                style = MaterialTheme.typography.bodySmall.copy(fontFeatureSettings = "tnum"),
                color = if (sel) c.sobreMarca.copy(alpha = 0.86f) else c.textoSecundario,
                textAlign = TextAlign.Center,
            )
        }
        if (sel) {
            Icon(
                Iconos.TildeEnCirculo,
                contentDescription = null,
                tint = c.sobreMarca,
                modifier = Modifier.align(Alignment.TopEnd).padding(8.dp).size(20.dp),
            )
        }
    }
}

/** «Listo, quedó agendada»: el día y la hora, cómo se entra y los avisos (solo con permiso). */
@Composable
private fun Listo(r: ReservaEntrega, cambio: Boolean, conAvisos: Boolean, alCerrar: () -> Unit, alCalendario: () -> Unit) {
    val c = MyPump.colores
    val zona = ZoneId.systemDefault()
    Column(
        Modifier.fillMaxSize().verticalScroll(rememberScrollState()).testTag("horario-listo-pantalla"),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Column(
            Modifier.widthIn(max = AnchoLectura).fillMaxWidth().padding(horizontal = Espacio.m).padding(top = Espacio.xl, bottom = Espacio.l),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(Espacio.l),
        ) {
            Box(Modifier.size(84.dp).clip(CircleShape).background(c.marca), contentAlignment = Alignment.Center) {
                Icon(Iconos.Tilde, contentDescription = null, tint = c.sobreMarca, modifier = Modifier.size(42.dp))
            }
            Text(
                if (cambio) "Listo, la cambiamos" else "Listo, quedó agendada",
                style = MaterialTheme.typography.headlineSmall,
                textAlign = TextAlign.Center,
                modifier = Modifier.semantics { heading(); liveRegion = LiveRegionMode.Polite }.testTag("horario-listo"),
            )
            r.inicio?.let { i ->
                Column(
                    Modifier.fillMaxWidth().superficieTarjeta().padding(Espacio.l).semantics(mergeDescendants = true) {},
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(4.dp),
                ) {
                    Text(ReglasAgenda.tituloTarjeta(r.tipo), style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold, color = c.marcaTexto, textAlign = TextAlign.Center)
                    Text(ReglasAgenda.mayuscula(ReglasAgenda.dia(i, zona)), style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center)
                    Text(
                        ReglasAgenda.hora(i, zona),
                        style = MaterialTheme.typography.displaySmall.copy(fontSize = 44.sp, lineHeight = 50.sp, fontFeatureSettings = "tnum"),
                        fontFamily = Archivo,
                        fontWeight = FontWeight.W800,
                    )
                    ReglasAgenda.horaArgentina(i, zona)?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = c.textoSecundario) }
                }
            }
            Column(Modifier.fillMaxWidth().testTag("horario-listo-texto"), verticalArrangement = Arrangement.spacedBy(Espacio.s)) {
                Linea(Iconos.Toque, "Vas a entrar a la videollamada desde la app, en Entreno. El botón se habilita 10 minutos antes.", c.marcaTexto, c.texto)
                if (conAvisos) Linea(Iconos.Reloj, "Te avisamos un día antes y cuando se habilite el botón.", c.marcaTexto, c.texto)
                Linea(Iconos.Persona, ReglasAgenda.TEXTO_ADMITE, c.marcaTexto, c.texto)
            }
            Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(Espacio.xs)) {
                BotonMarca("Listo", alTocar = alCerrar, modifier = Modifier.testTag("horario-listo-cerrar"))
                Pildora(Iconos.Calendario, "Agregar a mi calendario", null, Modifier.fillMaxWidth().defaultMinSize(minHeight = 54.dp).testTag("horario-calendario"), alTocar = alCalendario)
            }
        }
    }
}
