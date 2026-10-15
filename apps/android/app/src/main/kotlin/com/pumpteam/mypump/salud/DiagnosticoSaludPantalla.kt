package com.pumpteam.mypump.salud

import android.net.Uri
import android.os.Build
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.pumpteam.mypump.datos.DiagnosticoSalud
import com.pumpteam.mypump.datos.EstadoSalud
import com.pumpteam.mypump.datos.HistorialSalud
import com.pumpteam.mypump.datos.ModeloApp
import com.pumpteam.mypump.datos.ModeloSalud
import com.pumpteam.mypump.diseno.Espacio
import com.pumpteam.mypump.diseno.MyPump
import com.pumpteam.mypump.diseno.PantallaConTitulo
import com.pumpteam.mypump.diseno.Tarjeta
import com.pumpteam.mypump.entreno.Letras
import kotlin.coroutines.cancellation.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * El diagnóstico de Health Connect (SAL-13, cliente.html:8605-8665; gemelo de DiagnosticoSaludView.swift): qué trajo cada
 * tipo en 14 días y por qué camino, el error textual del que falló, el estado (en Health Connect los permisos sí se
 * informan), el permiso de historial, el último intento de conectar, el último rechazo de la base y el sueño por noche y
 * por fuente. Es una herramienta nuestra: se abre con 5 toques en el título "Health Connect" del detalle de salud, o con
 * `?diag=health` en el link.
 */
@Composable
fun DiagnosticoSaludPantalla(salud: ModeloSalud, alVolver: () -> Unit) {
    var estado by remember { mutableStateOf<EstadoSalud?>(null) }
    var diag by remember { mutableStateOf<DiagnosticoSalud?>(null) }
    var historial by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(salud) {
        estado = salud.estado()
        historial = textoHistorial(salud)
        diag = salud.diagnostico()
    }
    val c = MyPump.colores
    PantallaConTitulo("Diagnóstico", alVolver = alVolver, desplazable = true, modifier = Modifier.testTag("diagnostico-salud")) {
        Column(Modifier.padding(horizontal = Espacio.m), verticalArrangement = Arrangement.spacedBy(Espacio.m)) {
            estado?.let { e ->
                Tarjeta(espaciado = 6.dp) {
                    Rotulo("Estado de Health Connect")
                    Renglon("Health Connect", if (e.disponible) "sí" else "no")
                    Renglon("Conectado", if (e.conectado) "sí" else "no")
                    Renglon("No llega nada", if (e.sinDatos) "sí" else "no")
                    Renglon("Permisos dados", e.preguntados?.let { "$it/${e.total}" } ?: "?")
                    Renglon("Historial (más de 30 días)", historial ?: "…")
                    Renglon("Última sync", e.ultimaSync ?: "nunca")
                    Renglon("Android", "${Build.VERSION.RELEASE} (API ${Build.VERSION.SDK_INT})")
                    e.errorEstado?.let { Text("checkAuthorization: $it", style = Letras.caption, color = c.peligro) }
                    Text(
                        "En Health Connect los permisos sí se informan: \"Permisos dados\" son los que el cliente dio. Si dice 13/13 y " +
                            "abajo todo da 0, el reloj no está escribiendo en Health Connect.",
                        style = Letras.caption2, color = c.textoSecundario,
                    )
                }
            }
            (salud.ultimoErrorIngesta ?: diag?.errorIngesta)?.let { e ->
                Tarjeta(espaciado = 6.dp) {
                    Text("⚠ El servidor rechazó la última ingesta: $e", style = MaterialTheme.typography.bodyMedium, color = c.peligro)
                    Text(
                        "Los datos se leen bien de Health Connect pero no se están guardando. Es un problema del backend, no del teléfono.",
                        style = Letras.caption, color = c.textoSecundario,
                    )
                }
            }
            Tarjeta(espaciado = 6.dp) {
                Rotulo("Último intento de conectar")
                SelectionContainer {
                    Text(
                        salud.ultimoIntento?.serializar() ?: "(todavía no se intentó conectar)",
                        style = Letras.caption.copy(fontFamily = FontFamily.Monospace),
                    )
                }
            }
            val d = diag
            if (d == null) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espacio.xs)) {
                    CircularProgressIndicator(Modifier.size(18.dp), color = c.marcaTexto, strokeWidth = 2.dp)
                    Text("Consultando…", style = MaterialTheme.typography.bodyMedium, color = c.textoSecundario)
                }
            } else {
                Tarjeta(espaciado = 6.dp, modifier = Modifier.testTag("diagnostico-tipos")) {
                    Rotulo("Tipos (14 días)")
                    for (t in d.tipos) {
                        Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                                Text(t.tipo, style = Letras.caption.copy(fontFamily = FontFamily.Monospace))
                                Text(t.via, style = Letras.caption2, color = c.textoSecundario, modifier = Modifier.weight(1f))
                                Text(
                                    "${t.n}", style = Letras.caption.copy(fontFamily = FontFamily.Monospace), fontWeight = FontWeight.Bold,
                                    color = if (t.n > 0) c.exito else c.peligro,
                                )
                            }
                            t.primero?.let { p ->
                                Text(p + (t.ultimo?.let { u -> if (u != p) " → $u" else "" } ?: ""), style = Letras.caption2, color = c.textoSecundario)
                            }
                            t.error?.let { Text(it.take(90), style = Letras.caption2, color = c.peligro) }
                        }
                    }
                }
                Tarjeta(espaciado = 6.dp) {
                    Rotulo("Sueño por noche y por fuente")
                    if (d.noches.isEmpty()) Text("sin datos de sueño", style = MaterialTheme.typography.bodyMedium, fontStyle = FontStyle.Italic)
                    for (n in d.noches.takeLast(10)) {
                        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                            Text(n.fecha, style = Letras.caption, fontWeight = FontWeight.Bold)
                            for (f in n.fuentes.keys.sorted()) {
                                val estados = (n.fuentes[f] ?: emptyMap()).entries.sortedBy { it.key }.joinToString(", ") { "${it.key} ${it.value}m" }
                                Text("  $f: $estados", style = Letras.caption2.copy(fontFamily = FontFamily.Monospace))
                            }
                        }
                    }
                    Text(
                        "Si una noche aparece con 2 fuentes, se queda solo con la que más minutos de sueño real aportó (si no, se duplicarían las horas).",
                        style = Letras.caption2, color = c.textoSecundario,
                    )
                }
                if (d.errores.isNotEmpty()) {
                    Tarjeta(espaciado = 6.dp) {
                        Rotulo("Errores")
                        for (e in d.errores) Text(e, style = Letras.caption2.copy(fontFamily = FontFamily.Monospace))
                    }
                }
            }
        }
    }
}

/**
 * El permiso de historial, preguntado en el momento (sin abrir la hoja): sin él solo llegan los últimos 30 días, y un
 * Health Connect viejo ni lo conoce.
 */
private suspend fun textoHistorial(salud: ModeloSalud): String {
    val h: HistorialSalud? = try {
        salud.sincronizador?.fuente?.historial()
    } catch (e: CancellationException) {
        throw e
    } catch (e: Exception) {
        return "? (${e.message ?: e})"
    }
    return when {
        h == null -> "?"
        h.autorizado -> "sí"
        !h.disponible -> "no: este Health Connect no lo tiene"
        else -> "no: solo llegan los últimos 30 días"
    }
}

@Composable
private fun Rotulo(texto: String) {
    Text(texto, style = MaterialTheme.typography.titleSmall, color = MyPump.colores.textoSecundario)
}

@Composable
private fun Renglon(clave: String, valor: String) {
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Text(clave, style = MaterialTheme.typography.bodyMedium, modifier = Modifier.weight(1f))
        Text(valor, style = MaterialTheme.typography.bodyMedium.merge(Letras.cifras), color = MyPump.colores.textoSecundario)
    }
}

/**
 * `?diag=health` en el link (SAL-13, ACC-09): la raíz abre el diagnóstico de Salud directo, sin los cinco toques. Es la
 * herramienta de soporte de "no me anda la salud": se le manda al cliente el link con el parámetro y lo toca.
 */
object DiagnosticoSaludPedido {
    private val _pedido = MutableStateFlow(false)
    val pedido: StateFlow<Boolean> = _pedido.asStateFlow()

    fun desdeLink(link: String) {
        val diag = try {
            Uri.parse(link).getQueryParameter("diag")
        } catch (_: Exception) {
            null
        }
        if (diag == "health") _pedido.value = true
    }

    fun cerrar() {
        _pedido.value = false
    }
}

/** Lo que pone la raíz de la app: el diagnóstico pedido por el link, si hay una cuenta (sin cuenta no hay qué mirar). */
@Composable
fun DiagnosticoSaludDesdeLink(modelo: ModeloApp) {
    val pedido by DiagnosticoSaludPedido.pedido.collectAsStateWithLifecycle()
    val salud by modelo.salud.collectAsStateWithLifecycle()
    val s = salud
    if (pedido && s != null) {
        PantallaSuperpuesta(alCerrar = DiagnosticoSaludPedido::cerrar) {
            DiagnosticoSaludPantalla(s, alVolver = DiagnosticoSaludPedido::cerrar)
        }
    }
}
