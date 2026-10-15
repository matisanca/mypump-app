package com.pumpteam.mypump.salud

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.pumpteam.mypump.datos.ModeloSalud
import com.pumpteam.mypump.diseno.sinAbajo
import com.pumpteam.mypump.diseno.Interruptor
import com.pumpteam.mypump.diseno.AnchoLectura
import com.pumpteam.mypump.diseno.BotonMarca
import com.pumpteam.mypump.diseno.BotonSecundario
import com.pumpteam.mypump.diseno.Chip
import com.pumpteam.mypump.diseno.Espacio
import com.pumpteam.mypump.diseno.MarcoPantalla
import com.pumpteam.mypump.diseno.MyPump
import com.pumpteam.mypump.diseno.Numeros
import com.pumpteam.mypump.diseno.Tarjeta
import com.pumpteam.mypump.entreno.Letras
import com.pumpteam.mypump.raiz.LocalAlcanceApp
import com.pumpteam.mypump.reglas.FechaLocal
import com.pumpteam.mypump.reglas.SaludVista
import com.pumpteam.mypump.reglas.jsRound
import java.time.Duration
import java.time.Instant
import kotlinx.coroutines.launch

/**
 * "Mis datos" de salud: la escena `salud` de la web (cliente.html:6886-7059), gemela de SaludDetalleView.swift. Cómo se
 * arma el score, sueño, corazón, actividad, otras señales y cuerpo (cada uno con su promedio de 7 y 30 días y un gráfico
 * chico; una sección sin datos no se muestra), "Mostrarme el score" y el estado de Health Connect, cuyo título, tocado 5
 * veces, abre el diagnóstico (SAL-13).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SaludDetallePantalla(salud: ModeloSalud, alVolver: () -> Unit) {
    val filas by salud.salud.collectAsStateWithLifecycle()
    val recuperacion by salud.recuperacion.collectAsStateWithLifecycle()
    val fecha by salud.fecha.collectAsStateWithLifecycle()
    val c = MyPump.colores
    val t = salud.textos
    val alcance = LocalAlcanceApp.current
    var diagnostico by rememberSaveable { mutableStateOf(false) }
    var recargando by remember { mutableStateOf(false) }

    // Lo que ya trajo la cuenta, como iOS; tirar hacia abajo lo vuelve a traer (`.refreshable`). Recargar solo al abrir
    // pisaba un "Mostrarme el score" recién tocado con lo que todavía decía el servidor.
    MarcoPantalla("Salud", modifier = Modifier.testTag("salud-detalle"), alVolver = alVolver) { relleno ->
        PullToRefreshBox(
            isRefreshing = recargando,
            onRefresh = {
                recargando = true
                alcance.launch {
                    try {
                        salud.cargar()
                    } finally {
                        recargando = false
                    }
                }
            },
            modifier = Modifier.padding(relleno.sinAbajo()).fillMaxSize(),
        ) {
            Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()), horizontalAlignment = Alignment.CenterHorizontally) {
                Column(
                    Modifier.widthIn(max = AnchoLectura).fillMaxWidth().padding(horizontal = Espacio.m).padding(bottom = Espacio.xl + relleno.calculateBottomPadding()),
                    verticalArrangement = Arrangement.spacedBy(18.dp),
                ) {
                    if (filas.isEmpty()) {
                        Tarjeta {
                            EncabezadoSalud("⌚️", "Todavía no hay datos")
                            Text(
                                "Cuando conectes tu reloj o tu anillo, acá vas a ver todo lo que mide: sueño con sus fases, pulso en reposo, variabilidad, respiración, oxígeno y temperatura.",
                                style = MaterialTheme.typography.bodyMedium, color = c.textoSecundario,
                            )
                            val conectado by salud.conectado.collectAsStateWithLifecycle()
                            if (salud.sincronizador != null && !conectado) BotonConectarSalud(salud)
                            else if (salud.sincronizador == null) NotaSalud("Se conecta desde ${t.desdeApp}.")
                        }
                        SeccionHealthConnect(salud, alAbrirDiagnostico = { diagnostico = true })
                    } else {
                        Recuperacion(salud, recuperacion.isNotEmpty())
                        Sueno(salud, fecha)
                        Seccion(salud, "❤️", "Corazón", tipos = listOf("fc_reposo", "hrv_ms")) {
                            FilaMetrica(salud, "fc_reposo", "Pulso en reposo", unidad = " lpm", mejorSube = false, color = c.corazon)
                            FilaMetrica(salud, "hrv_ms", "Variabilidad (HRV)", unidad = " ms", color = c.corazon, nota = notaHRV(salud))
                        }
                        Seccion(salud, "👟", "Actividad", tipos = listOf("pasos", "actividad_min", "kcal_activas")) {
                            FilaMetrica(salud, "pasos", "Pasos", formato = SaludVista::miles)
                            FilaMetrica(salud, "actividad_min", "Minutos activos", unidad = " min")
                            FilaMetrica(salud, "kcal_activas", "Calorías activas", unidad = " kcal")
                        }
                        Seccion(
                            salud, "🌡", "Otras señales", sub = "Solo importan comparadas con lo normal tuyo, no con una tabla general.",
                            tipos = listOf("respiracion_rpm", "spo2_pct", "temp_muneca_c"),
                        ) {
                            FilaMetrica(
                                salud, "respiracion_rpm", "Respiración", unidad = " /min", color = TEAL,
                                nota = "Sube cuando estás incubando algo, con alcohol encima o durmiendo mal.",
                            )
                            FilaMetrica(salud, "spo2_pct", "Oxígeno en sangre", unidad = "%", color = TEAL)
                            FilaMetrica(salud, "temp_muneca_c", "Temperatura de muñeca", unidad = "°", color = NARANJA, formato = unDecimal)
                        }
                        Seccion(salud, "⚖️", "Cuerpo", tipos = listOf("peso_kg", "grasa_pct")) {
                            FilaMetrica(salud, "peso_kg", "Peso", unidad = " kg", formato = unDecimal)
                            FilaMetrica(salud, "grasa_pct", "Grasa corporal", unidad = "%", formato = unDecimal)
                        }
                        Preferencias(salud)
                        SeccionHealthConnect(salud, alAbrirDiagnostico = { diagnostico = true })
                        NotaSalud("Los datos los manda tu reloj a ${t.app} y de ahí llegan acá. Si algo no aparece, es porque tu dispositivo no lo mide.")
                    }
                }
            }
        }
    }
    if (diagnostico) {
        PantallaSuperpuesta(alCerrar = { diagnostico = false }) {
            DiagnosticoSaludPantalla(salud, alVolver = { diagnostico = false })
        }
    }
}

private val TEAL = Color(0xFF30B0C7)
private val NARANJA = Color(0xFFFF9500)

/** Un decimal con coma, como el resto de la app ("82,5 kg"); la web deja el punto. */
private val unDecimal: (Double) -> String = { SaludVista.unDecimal(it).replace(".", ",") }

private fun notaHRV(salud: ModeloSalud): String? = when (salud.serie("hrv_ms").lastOrNull()?.detalle?.get("metrica")?.comoTexto) {
    "sdnn" -> "Tu reloj mide SDNN en momentos sueltos del día, así que un valor aislado varía mucho. Lo que importa es la línea, no el número de hoy."
    "rmssd" -> "Medida durante la noche (rMSSD): es la más confiable para ver recuperación."
    else -> null
}

/**
 * `_seccionSalud`: con [tipos], si ninguno tiene datos la sección no se muestra (la web devuelve '' y la saca). Sin
 * [tipos] (recuperación, sueño, preferencias) va siempre: esas deciden solas qué mostrar.
 */
@Composable
private fun Seccion(
    salud: ModeloSalud,
    icono: String,
    titulo: String,
    sub: String? = null,
    tipos: List<String>? = null,
    cuerpo: @Composable ColumnScope.() -> Unit,
) {
    val filas by salud.salud.collectAsStateWithLifecycle()
    val hay = tipos?.any { SaludVista.fila(filas, it, true, SaludVista.entero) != null } ?: true
    if (!hay) return
    Tarjeta {
        EncabezadoSalud(icono, titulo)
        if (sub != null) Text(sub, style = MaterialTheme.typography.bodySmall, color = MyPump.colores.textoSecundario)
        cuerpo()
    }
}

/** "Cómo se arma tu recuperación": el score de hoy y cada componente con su barra y lo que pesa. */
@Composable
private fun Recuperacion(salud: ModeloSalud, hay: Boolean) {
    val score = salud.scoreDeHoy
    if (!hay || score == null) return
    val c = MyPump.colores
    Seccion(salud, "🔋", "Cómo se arma tu recuperación") {
        Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(2.dp)) {
            Text("$score", style = Numeros.grande)
            Text("/100", style = MaterialTheme.typography.bodyMedium, color = c.textoSecundario, modifier = Modifier.padding(bottom = 6.dp))
        }
        for (comp in salud.componentes) {
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Row {
                    Text(comp.nombre, style = MaterialTheme.typography.bodyMedium, modifier = Modifier.weight(1f))
                    Text("${comp.score}", style = MaterialTheme.typography.bodyMedium.merge(Letras.cifras), fontWeight = FontWeight.Bold)
                }
                LinearProgressIndicator(
                    progress = { (comp.score.coerceIn(0, 100) / 100f) },
                    modifier = Modifier.fillMaxWidth(),
                    color = if (comp.score >= 67) c.exito else if (comp.score >= 34) c.alerta else c.peligro,
                    trackColor = c.campo,
                    drawStopIndicator = {},
                )
                Text("pesa ${comp.aporte}% en tu score", style = Letras.caption, color = c.textoSecundario)
            }
        }
        NotaSalud("Los que no tenés no se promedian como cero: el score se reparte entre los datos que sí hay. Por eso podés tener número aunque tu reloj no mida variabilidad.")
    }
}

/** Sueño: la última noche, sus fases, el gráfico, el promedio de 7 días, la eficiencia y la regularidad. */
@Composable
private fun Sueno(salud: ModeloSalud, hoy: String) {
    val filas by salud.salud.collectAsStateWithLifecycle()
    val serie = remember(filas) { salud.serie("sueno_min") }
    val ultima = serie.lastOrNull() ?: return
    val c = MyPump.colores
    Seccion(salud, "😴", "Sueño") {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(SaludVista.rotuloNoche(ultima.fecha, hoy), style = MaterialTheme.typography.bodyMedium, modifier = Modifier.weight(1f))
            Text(SaludVista.horas(ultima.valor), style = Numeros.mediano.merge(Letras.cifras))
        }
        if (ultima.detalle?.get("estimado")?.let { it == com.pumpteam.mypump.modelos.ValorJson.Booleano(true) } == true) {
            NotaSalud("Estimado a partir del tiempo en la cama: tu reloj no mandó las fases.")
        }
        Etapas(salud)
        GraficoSalud(serie, c.sueno)
        val ultimas = serie.takeLast(7)
        Text(
            buildAnnotatedString {
                append("promedio 7 días: ")
                withStyle(SpanStyle(fontWeight = FontWeight.SemiBold)) { append(SaludVista.horas(ultimas.sumOf { it.valor } / minOf(serie.size, 7))) }
                append(" · ${serie.size} noches con dato")
            },
            style = Letras.caption, color = c.textoSecundario,
        )
        FilaMetrica(salud, "sueno_eficiencia_pct", "Eficiencia (dormido / en cama)", unidad = "%", color = c.sueno)
        SaludVista.regularidad(filas)?.let { r ->
            Text(
                buildAnnotatedString {
                    append("Te dormís en promedio cerca de las ")
                    withStyle(SpanStyle(fontWeight = FontWeight.Bold)) { append(r.horaDormirse) }
                    append(", con una variación de ")
                    withStyle(SpanStyle(fontWeight = FontWeight.Bold)) { append("±${r.variacion} min") }
                    append(". ${r.texto}")
                },
                style = MaterialTheme.typography.bodySmall, color = c.textoSecundario,
            )
        }
    }
}

/** Las fases de la última noche como tres barras (profundo, REM, ligero). */
@Composable
private fun Etapas(salud: ModeloSalud) {
    val tipos = listOf(
        Triple("sueno_profundo_min", "Profundo", Color(0xFF5B6EE1)),
        Triple("sueno_rem_min", "REM", Color(0xFF9B6EE1)),
        Triple("sueno_ligero_min", "Ligero", Color(0xFF8FA8D8)),
    )
    val et = tipos.mapNotNull { t -> salud.serie(t.first).lastOrNull()?.let { t to it.valor } }
    if (et.isEmpty()) return
    val total = et.sumOf { it.second }.let { if (it == 0.0) 1.0 else it }
    Row(Modifier.fillMaxWidth().height(110.dp), verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(Espacio.s)) {
        for ((t, v) in et) {
            Column(Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Box(
                    Modifier.fillMaxWidth().height(maxOf(6.0, v / total * 70).dp).clip(RoundedCornerShape(4.dp)).background(t.third),
                )
                Text(SaludVista.horas(v), style = Letras.caption.merge(Letras.cifras), fontWeight = FontWeight.SemiBold)
                Text(t.second, style = Letras.caption2, color = MyPump.colores.textoSecundario)
            }
        }
    }
}

/**
 * `_filaSalud`: el valor del último día con su flecha contra el promedio de 30 días, el gráfico chico y los promedios.
 * Si no hay datos de ese tipo, no ocupa lugar.
 */
@Composable
private fun FilaMetrica(
    salud: ModeloSalud,
    tipo: String,
    nombre: String,
    unidad: String = "",
    mejorSube: Boolean = true,
    color: Color = MyPump.colores.marcaTexto,
    formato: (Double) -> String = SaludVista.entero,
    nota: String? = null,
) {
    val filas by salud.salud.collectAsStateWithLifecycle()
    val f = remember(filas, tipo, mejorSube) { SaludVista.fila(filas, tipo, mejorSube, formato) } ?: return
    val c = MyPump.colores
    Column(Modifier.padding(vertical = 2.dp).testTag("fila-$tipo"), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(nombre, style = MaterialTheme.typography.bodyMedium, modifier = Modifier.weight(1f))
            Text(
                buildAnnotatedString {
                    withStyle(SpanStyle(fontWeight = FontWeight.SemiBold, fontSize = MaterialTheme.typography.titleMedium.fontSize)) { append(f.valor) }
                    append(unidad)
                },
                style = Letras.caption.merge(Letras.cifras),
            )
            f.delta?.let {
                Spacer(Modifier.width(6.dp))
                Text(it, style = Letras.caption, fontWeight = FontWeight.SemiBold, color = if (f.deltaEsBueno) c.exito else c.alerta)
            }
        }
        GraficoSalud(f.serie, color)
        Text(
            buildAnnotatedString {
                append("promedio 7 días: ")
                withStyle(SpanStyle(fontWeight = FontWeight.Bold)) { append("${f.promedio7}$unidad") }
                f.promedio30?.let { append(" · 30 días: $it$unidad") }
                append(" · ${f.diasConDato} día${if (f.diasConDato != 1) "s" else ""} con dato")
            },
            style = Letras.caption, color = c.textoSecundario,
        )
        nota?.let { NotaSalud(it) }
    }
}

/** "Mostrarme el score": optimista (responde ya) y en el alcance de la app (no se corta si se cierra la pantalla). */
@Composable
private fun Preferencias(salud: ModeloSalud) {
    val mostrar by salud.mostrarRecuperacion.collectAsStateWithLifecycle()
    val alcance = LocalAlcanceApp.current
    val c = MyPump.colores
    Seccion(salud, "⚙️", "Preferencias") {
        Row(
            Modifier.fillMaxWidth()
                .toggleable(value = mostrar, role = Role.Switch, onValueChange = { v -> alcance.launch { salud.cambiarMostrarRecuperacion(v) } })
                .testTag("mostrar-score"),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(Espacio.s),
        ) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text("Mostrarme el score", style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Medium)
                Text(
                    "Si preferís no ver el número, lo apagás acá. Tus datos se siguen guardando y Mati los sigue viendo igual.",
                    style = Letras.caption, color = c.textoSecundario,
                )
            }
            Interruptor(mostrar, alCambiar = null, color = c.exito)
        }
    }
}

// MARK: Health Connect (renderAppleHealthEstado)

/**
 * El estado real de Health Connect: no está (instalarlo o actualizarlo desde Play, o el teléfono no lo soporta), "no está
 * llegando ningún dato" (con Reintentar), conectado (última sincronización y Sincronizar) o sin conectar. El título,
 * tocado 5 veces seguidas, abre el diagnóstico (SAL-13).
 */
@Composable
fun SeccionHealthConnect(salud: ModeloSalud, alAbrirDiagnostico: () -> Unit) {
    if (salud.sincronizador == null) return
    val conectado by salud.conectado.collectAsStateWithLifecycle()
    val sinDatos by salud.sinDatos.collectAsStateWithLifecycle()
    val ultimaSync by salud.ultimaSync.collectAsStateWithLifecycle()
    val conectando by salud.conectando.collectAsStateWithLifecycle()
    val sincronizando by salud.sincronizando.collectAsStateWithLifecycle()
    val disponible = rememberEstadoHealthConnect()
    val contexto = LocalContext.current
    val alcance = LocalAlcanceApp.current
    var mensaje by rememberSaveable { mutableStateOf<String?>(null) }
    var ocupado by remember { mutableStateOf(false) }
    var toques by remember { mutableIntStateOf(0) }
    var ultimoToque by remember { mutableLongStateOf(0L) }
    val t = salud.textos
    val c = MyPump.colores

    val descripcion = when {
        disponible != EstadoHealthConnect.DISPONIBLE -> textoSinHealthConnect(disponible, salud)
        sinDatos -> "No está llegando ningún dato. Revisá que esté todo activado en ${t.revocar}."
        conectado -> ultimaSync?.let { "Última sincronización: ${hace(it)}" } ?: "Conectado"
        else -> "Conectalo y tus pasos, sueño y pulso entran solos."
    }

    Tarjeta(Modifier.testTag("seccion-health-connect")) {
        EncabezadoSalud(
            "❤️", t.app,
            // Cinco toques y no un botón: es una herramienta nuestra, no una función del producto.
            Modifier
                .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null) {
                    val ahora = System.currentTimeMillis()
                    toques = if (ahora - ultimoToque < 1_500) toques + 1 else 1   // la racha se corta sola
                    ultimoToque = ahora
                    if (toques >= 5) {
                        toques = 0
                        alAbrirDiagnostico()
                    }
                }
                .testTag("titulo-health-connect"),
        )
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espacio.s)) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text(t.dispositivo, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Medium)
                    if (conectado && !sinDatos && disponible == EstadoHealthConnect.DISPONIBLE) Chip("activo", tono = c.exito)
                }
                Text(descripcion, style = Letras.caption, color = c.textoSecundario)
            }
            when {
                disponible == EstadoHealthConnect.NO_SOPORTADO -> {}
                disponible != EstadoHealthConnect.DISPONIBLE -> BotonMarca(
                    if (disponible == EstadoHealthConnect.INSTALAR) "Instalar" else "Actualizar",
                    alTocar = { EstadoHealthConnect.abrirEnPlay(contexto) },
                    compacto = true,
                    modifier = Modifier.testTag("instalar-health-connect"),
                )
                sinDatos -> BotonSecundario("Reintentar", compacto = true, cargando = ocupado, alTocar = {
                    ocupado = true
                    alcance.launch {
                        // Solo sirve si volvió de Health Connect y activó algo: si sigue denegado, no se ve nada.
                        val r = salud.conectar()
                        ocupado = false
                        if (!r.ok) mensaje = "Sigue sin permiso. Activalo en Ajustes y volvé."
                    }
                })
                conectado -> BotonSecundario(
                    "Sincronizar", compacto = true, cargando = ocupado || sincronizando,
                    modifier = Modifier.testTag("sincronizar-salud"),
                    alTocar = {
                        ocupado = true
                        alcance.launch {
                            val r = salud.sincronizar()
                            salud.cargar()
                            ocupado = false
                            mensaje = ModeloSalud.textoSincronizacion(r)
                        }
                    },
                )
                else -> BotonMarca("Conectar", compacto = true, cargando = ocupado || conectando, modifier = Modifier.testTag("conectar-health-connect"), alTocar = {
                    ocupado = true
                    alcance.launch {
                        val r = salud.conectar()
                        ocupado = false
                        if (!r.ok) {
                            mensaje = if (r.motivo == "no_disponible") t.sinApp
                            else "No pudimos conectar. Probá de nuevo en un rato; si sigue igual, avisale a Mati."
                        }
                    }
                })
            }
        }
        // En Android los permisos se cambian en Health Connect, y desde acá se llega directo (Ajustes no tiene un camino
        // fijo: cambia con cada marca de teléfono).
        if (sinDatos && disponible == EstadoHealthConnect.DISPONIBLE) {
            TextButton(onClick = { abrirPermisosHealthConnect(contexto) }, modifier = Modifier.testTag("abrir-health-connect")) {
                Text("Abrir Health Connect", color = c.marcaTexto, style = MaterialTheme.typography.labelLarge)
            }
        }
        mensaje?.let { NotaSalud(it) }
    }
}

/** "recién", "hace 3 h" o "12 oct". */
internal fun hace(instante: Instant, ahora: Instant = Instant.now()): String {
    val h = Duration.between(instante, ahora).toMillis() / 3_600_000.0
    if (h < 1) return "recién"
    if (h < 24) return "hace ${SaludVista.enteroJS(jsRound(h))} h"
    return SaludVista.fechaCorta(FechaLocal.hoy(instante)) ?: ""
}

/**
 * Los permisos de MyPump en Health Connect: en Android 14+ la pantalla de la app (`MANAGE_HEALTH_PERMISSIONS`); antes,
 * la de Health Connect.
 */
fun abrirPermisosHealthConnect(contexto: Context) {
    val intentos = buildList {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            add(Intent("android.health.connect.action.MANAGE_HEALTH_PERMISSIONS").putExtra(Intent.EXTRA_PACKAGE_NAME, contexto.packageName))
        }
        add(Intent(androidx.health.connect.client.HealthConnectClient.ACTION_HEALTH_CONNECT_SETTINGS))
    }
    for (i in intentos) {
        try {
            contexto.startActivity(i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            return
        } catch (_: ActivityNotFoundException) {
        } catch (_: SecurityException) {
        }
    }
}
