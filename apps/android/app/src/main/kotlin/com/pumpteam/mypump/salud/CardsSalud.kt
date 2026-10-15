package com.pumpteam.mypump.salud

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.pumpteam.mypump.datos.ModeloSalud
import com.pumpteam.mypump.diseno.BotonMarca
import com.pumpteam.mypump.diseno.Espacio
import com.pumpteam.mypump.diseno.Iconos
import com.pumpteam.mypump.diseno.MyPump
import com.pumpteam.mypump.diseno.Numeros
import com.pumpteam.mypump.diseno.Tarjeta
import com.pumpteam.mypump.entreno.Letras
import com.pumpteam.mypump.raiz.LocalAlcanceApp
import com.pumpteam.mypump.reglas.SaludVista
import kotlinx.coroutines.launch

// Las dos tarjetas de salud de Mi Día (cliente.html:6680-6788 y 7233-7328) con los datos de ModeloSalud: gemelas de
// CardsSalud.swift, con los textos de Health Connect (`TextosSalud.ANDROID`, SAL-08). Son piezas sueltas: las ubica quien
// arme Revisión (en Android todavía no existe); Mis datos usa el resumen, el botón y el detalle.

/**
 * Si este teléfono puede usar Health Connect, mirado de nuevo cada vez que la app vuelve a la vista (el cliente pudo
 * haberlo instalado o actualizado desde Play mientras tanto).
 */
@Composable
fun rememberEstadoHealthConnect(): EstadoHealthConnect {
    val contexto = LocalContext.current
    var estado by remember { mutableStateOf(EstadoHealthConnect.actual(contexto)) }
    LifecycleEventEffect(Lifecycle.Event.ON_RESUME) { estado = EstadoHealthConnect.actual(contexto) }
    return estado
}

/**
 * "Conectar Health Connect" con todo lo que hace la web al tocarlo (`_conectarSalud`): no se puede tocar dos veces, un
 * error se explica debajo y, si el historial termina sin un solo dato, se avisa dónde se activan los permisos (con 7 días
 * vacíos no se puede acusar a nadie de haber denegado). Sin Health Connect en el teléfono: si se consigue en Play, lo
 * ofrece; si el teléfono no lo soporta, no ofrece nada.
 */
@Composable
fun BotonConectarSalud(salud: ModeloSalud, modifier: Modifier = Modifier, titulo: String = salud.textos.boton) {
    val conectando by salud.conectando.collectAsStateWithLifecycle()
    val estado = rememberEstadoHealthConnect()
    val contexto = LocalContext.current
    val alcance = LocalAlcanceApp.current
    var aviso by rememberSaveable { mutableStateOf<String?>(null) }
    val t = salud.textos
    Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(Espacio.xs)) {
        when (estado) {
            EstadoHealthConnect.NO_SOPORTADO -> return@Column
            EstadoHealthConnect.INSTALAR, EstadoHealthConnect.ACTUALIZAR -> {
                NotaSalud(textoSinHealthConnect(estado, salud))
                BotonMarca(
                    if (estado == EstadoHealthConnect.INSTALAR) "Instalar Health Connect" else "Actualizar Health Connect",
                    alTocar = { EstadoHealthConnect.abrirEnPlay(contexto) },
                    modifier = Modifier.testTag("instalar-health-connect"),
                )
            }
            EstadoHealthConnect.DISPONIBLE -> {
                BotonMarca(
                    titulo,
                    cargando = conectando,
                    alTocar = {
                        aviso = null
                        alcance.launch {
                            val r = salud.conectar()
                            if (!r.ok) {
                                aviso = if (r.motivo == "no_disponible") t.sinApp
                                else "No pudimos conectar. Probá de nuevo en un rato; si sigue igual, avisale a Mati."
                                return@launch
                            }
                            if (r.historial?.await()?.sinDatos == true) {
                                aviso = "Quedó conectado pero no llegó ningún dato. Fijate que esté todo activado en ${t.revocar}."
                            }
                        }
                    },
                    modifier = Modifier.testTag("conectar-salud"),
                )
            }
        }
        aviso?.let { NotaSalud(it) }
    }
}

/** Lo que se dice cuando Health Connect no está: falta instalarlo, actualizarlo, o el teléfono no lo tiene. */
fun textoSinHealthConnect(estado: EstadoHealthConnect, salud: ModeloSalud): String = when (estado) {
    EstadoHealthConnect.INSTALAR -> salud.textos.sinApp
    EstadoHealthConnect.ACTUALIZAR -> "Hay que actualizar Health Connect para conectarlo. Se actualiza gratis desde Google Play."
    EstadoHealthConnect.NO_SOPORTADO -> "Este teléfono no es compatible con Health Connect."
    EstadoHealthConnect.DISPONIBLE -> ""
}

/** Encabezado de las secciones de salud (ícono + título), como `myday-section-hdr`. */
@Composable
fun EncabezadoSalud(icono: String, titulo: String, modifier: Modifier = Modifier) {
    Row(modifier.semantics(mergeDescendants = true) { heading() }, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espacio.xs)) {
        Text(icono, style = MaterialTheme.typography.titleMedium)
        Text(titulo, style = MaterialTheme.typography.titleMedium)
    }
}

/** El texto chico y gris de las tarjetas (`rec-nota`). */
@Composable
fun NotaSalud(texto: String, modifier: Modifier = Modifier) {
    Text(texto, style = MaterialTheme.typography.bodySmall, color = MyPump.colores.textoSecundario, modifier = modifier)
}

/** El color de la banda del score: verde arriba, rojo abajo, ámbar en el medio. */
@Composable
fun colorBanda(banda: String): Color = when (banda) {
    "alta" -> MyPump.colores.exito
    "baja" -> MyPump.colores.peligro
    else -> MyPump.colores.alerta
}

/**
 * El caso de la tarjeta de Recuperación, leyendo todos los flujos de los que depende (así se recompone cuando cambia
 * cualquiera: la serie, la conexión, el interruptor, los datos, el avance del historial, "no llega nada" y el día).
 */
@Composable
fun cardRecuperacion(salud: ModeloSalud): SaludVista.CardRecuperacion {
    val serie by salud.recuperacion.collectAsStateWithLifecycle()
    val conectado by salud.conectado.collectAsStateWithLifecycle()
    val mostrar by salud.mostrarRecuperacion.collectAsStateWithLifecycle()
    val filas by salud.salud.collectAsStateWithLifecycle()
    val progreso by salud.progresoHistorial.collectAsStateWithLifecycle()
    val sinDatos by salud.sinDatos.collectAsStateWithLifecycle()
    val fecha by salud.fecha.collectAsStateWithLifecycle()
    return remember(serie, conectado, mostrar, filas, progreso, sinDatos, fecha) { salud.cardRecuperacion }
}

// MARK: Recuperación (SAL-09)

/** La tarjeta de Recuperación: sin conectar, conectada sin score (qué falta), calibrando, oculta o con el score. */
@Composable
fun CardRecuperacion(salud: ModeloSalud, alVerTodo: () -> Unit, modifier: Modifier = Modifier) {
    val card = cardRecuperacion(salud)
    val t = salud.textos
    val c = MyPump.colores
    Tarjeta(modifier.testTag("card-recuperacion")) {
        EncabezadoSalud("🔋", "Recuperación")
        when (card) {
            SaludVista.CardRecuperacion.SinConectar -> {
                Text(
                    "Tu recuperación se calcula con lo que mide tu reloj mientras dormís: pulso en reposo, sueño y variabilidad.",
                    style = MaterialTheme.typography.bodyMedium, color = c.textoSecundario,
                )
                if (salud.sincronizador != null) BotonConectarSalud(salud)
                else NotaSalud("Si tenés reloj o anillo, conectalo desde ${t.desdeApp} y esto se llena solo.")
            }
            is SaludVista.CardRecuperacion.ConectadoSinScore -> {
                Text(card.sinScore.frase(t), style = MaterialTheme.typography.bodyMedium.merge(Letras.cifras), fontWeight = FontWeight.Medium)
                NotaSalud(card.sinScore.nota(t))
            }
            is SaludVista.CardRecuperacion.Calibrando -> {
                Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text("${card.dias}", style = Numeros.grande)
                    Text("/ 14 días", style = MaterialTheme.typography.bodyMedium, color = c.textoSecundario, modifier = Modifier.padding(bottom = 6.dp))
                }
                LinearProgressIndicator(
                    progress = { (card.porcentaje / 100f).coerceIn(0f, 1f) },
                    modifier = Modifier.fillMaxWidth(),
                    color = c.marcaTexto,
                    trackColor = c.campo,
                    drawStopIndicator = {},
                )
                Text("Estoy aprendiendo cómo es tu normal. ${card.yaSe}".trim(), style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Medium)
                NotaSalud("Sin unos días de historia, cualquier número sería inventado.")
            }
            SaludVista.CardRecuperacion.Oculto -> {
                Text("Tenés el score apagado. Tus datos se siguen guardando y Mati los ve igual.", style = MaterialTheme.typography.bodyMedium)
                VerTodo(alVerTodo)
            }
            is SaludVista.CardRecuperacion.ConScore -> {
                ConScore(card.score)
                VerTodo(alVerTodo)
            }
        }
    }
}

@Composable
private fun ConScore(s: SaludVista.ConScore) {
    val c = MyPump.colores
    val color = colorBanda(s.banda)
    Row(horizontalArrangement = Arrangement.spacedBy(14.dp), verticalAlignment = Alignment.Top) {
        Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(2.dp)) {
            Text("${s.fila.score ?: 0}", style = Numeros.gigante, color = color)
            Text("/100", style = MaterialTheme.typography.bodyMedium, color = c.textoSecundario, modifier = Modifier.padding(bottom = 10.dp))
        }
        Column(Modifier.padding(top = 10.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(s.bandaTexto, style = MaterialTheme.typography.titleMedium, color = color)
            s.frase?.let { Text(it, style = MaterialTheme.typography.bodyMedium) }
        }
    }
    s.notaVieja?.let { NotaSalud(it) }
    if (s.grafico.isNotEmpty()) {
        LineaSalud(
            s.grafico.map { it.second.toDouble() }, color, 38.dp, dominio = 0.0..100.0, marcarUltimo = true,
            descripcion = "Tu recuperación de los últimos 14 días",
        )
    }
    if (s.motivos.isNotEmpty()) {
        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            for (m in s.motivos) {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(if (m.sube) "↑" else "↓", style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Bold, color = c.textoSecundario)
                    Text(
                        buildAnnotatedString {
                            append(m.antes)
                            withStyle(SpanStyle(fontWeight = FontWeight.Bold)) { append(m.negrita) }
                            append(m.despues)
                        },
                        style = MaterialTheme.typography.bodyMedium,
                    )
                }
            }
        }
    }
    if (s.provisoria) NotaSalud("Todavía estoy afinando tu rango normal — puede moverse un poco estos días.")
}

/** "Ver todos mis datos" (abre el detalle de salud). */
@Composable
private fun VerTodo(alTocar: () -> Unit) {
    val c = MyPump.colores
    Row(
        Modifier.fillMaxWidth().clickable(role = Role.Button, onClick = alTocar).padding(vertical = Espacio.xxs).testTag("ver-todos-mis-datos"),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text("Ver todos mis datos", style = MaterialTheme.typography.labelLarge, color = c.marcaTexto, modifier = Modifier.weight(1f))
        Icon(Iconos.Chevron, contentDescription = null, tint = c.marcaTexto, modifier = Modifier.size(18.dp))
    }
}

// MARK: Salud (SAL-10)

/**
 * La tarjeta de Salud: pasos de hoy, minutos activos, sueño de anoche, HRV y el promedio de pasos. Sin conectar, ofrece
 * conectar solo si la de Recuperación no lo hace (dos botones iguales seguidos se ven mal). Sin pasos ni actividad no
 * muestra nada (la de Recuperación explica qué falta), salvo el avance del historial.
 */
@Composable
fun CardSalud(salud: ModeloSalud, modifier: Modifier = Modifier) {
    val card = cardRecuperacion(salud)
    val conectado by salud.conectado.collectAsStateWithLifecycle()
    val filas by salud.salud.collectAsStateWithLifecycle()
    val fecha by salud.fecha.collectAsStateWithLifecycle()
    val progreso by salud.progresoHistorial.collectAsStateWithLifecycle()
    val resumen = remember(filas, fecha) { salud.resumenSalud }
    val c = MyPump.colores
    if (salud.sincronizador != null && !conectado) {
        if (card !is SaludVista.CardRecuperacion.SinConectar) {
            Tarjeta(modifier) {
                EncabezadoSalud("👟", "Salud")
                Text(
                    "Conectá ${salud.textos.app} una sola vez y tus pasos y actividad se sincronizan solos para que Mati los vea.",
                    style = MaterialTheme.typography.bodyMedium, color = c.textoSecundario,
                )
                BotonConectarSalud(salud)
            }
        }
    } else if (resumen != null) {
        Tarjeta(modifier.testTag("card-salud"), espaciado = 14.dp) {
            EncabezadoSalud("👟", "Salud")
            Row(horizontalArrangement = Arrangement.spacedBy(Espacio.l)) {
                MetricaSalud(resumen.pasosHoy?.let(SaludVista::miles) ?: "—", "pasos hoy")
                resumen.minutosActivosHoy?.let { MetricaSalud(SaludVista.miles(it), "min activos") }
            }
            if (resumen.suenoAnoche != null || resumen.hrv != null) {
                Row(horizontalArrangement = Arrangement.spacedBy(Espacio.l)) {
                    resumen.suenoAnoche?.let { MetricaSalud(SaludVista.horas(it), "dormiste anoche") }
                    resumen.hrv?.let { MetricaSalud(SaludVista.enteroJS(it), "HRV (recuperación)", unidad = " ms") }
                }
            }
            Text(
                buildAnnotatedString {
                    append("Promedio ${resumen.diasPromedio} día${if (resumen.diasPromedio != 1) "s" else ""}: ")
                    withStyle(SpanStyle(fontWeight = FontWeight.SemiBold, color = c.texto)) { append("${SaludVista.miles(resumen.promedioPasos.toDouble())} pasos") }
                },
                style = MaterialTheme.typography.bodySmall, color = c.textoSecundario,
            )
        }
    } else if (progreso != null) {
        Tarjeta(modifier) {
            EncabezadoSalud("👟", "Salud")
            Text(
                "Trayendo tu historial… ${progreso!!.hecho}/${progreso!!.total} días",
                style = MaterialTheme.typography.bodyMedium.merge(Letras.cifras), fontWeight = FontWeight.Medium,
            )
        }
    }
}

/** Un número grande con su rótulo ("8.548 · pasos hoy"). */
@Composable
fun MetricaSalud(valor: String, etiqueta: String, unidad: String = "") {
    Column(Modifier.semantics(mergeDescendants = true) {}, verticalArrangement = Arrangement.spacedBy(2.dp)) {
        Text(
            buildAnnotatedString {
                append(valor)
                if (unidad.isNotEmpty()) withStyle(SpanStyle(fontSize = MaterialTheme.typography.bodyMedium.fontSize)) { append(unidad) }
            },
            style = Numeros.mediano.merge(Letras.cifras),
        )
        Text(etiqueta, style = Letras.caption, color = MyPump.colores.textoSecundario)
    }
}
