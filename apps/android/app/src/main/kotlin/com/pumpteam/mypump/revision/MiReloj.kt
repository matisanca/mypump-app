package com.pumpteam.mypump.revision

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.pumpteam.mypump.datos.ModeloSalud
import com.pumpteam.mypump.diseno.Alerta
import com.pumpteam.mypump.diseno.BotonAlerta
import com.pumpteam.mypump.diseno.BotonSecundario
import com.pumpteam.mypump.diseno.Chip
import com.pumpteam.mypump.diseno.MyPump
import com.pumpteam.mypump.diseno.Separador
import com.pumpteam.mypump.diseno.Tarjeta
import com.pumpteam.mypump.diseno.abrirEnNavegador
import com.pumpteam.mypump.entreno.Letras
import com.pumpteam.mypump.raiz.LocalAlcanceApp
import com.pumpteam.mypump.salud.EncabezadoSalud
import com.pumpteam.mypump.salud.NotaSalud
import kotlinx.coroutines.launch

/**
 * "Mi reloj" de Revisión (REV-08, gemelo de `MiRelojView.swift`, cliente.html:8088-8239): Oura y WHOOP según lo que el
 * servidor tenga habilitado (o lo que el cliente ya tenía conectado). "Conectar" abre la autorización del proveedor en
 * una Custom Tab con el navegador FIJO (`abrirEnNavegador`): el link es de `app.mypumpteam.com`, que es también el App
 * Link de MyPump, y con el dominio verificado volvería a la app en vez de abrirse. El token viaja en la query: nunca en
 * un WebView propio. Después pregunta `get_conexiones` cada 3 s durante 2 min, porque el callback no vuelve a la app.
 * "Quitar" pide confirmación. Sin relojes para ofrecer, no ocupa lugar.
 */
@Composable
fun MiReloj(salud: ModeloSalud, modifier: Modifier = Modifier) {
    val contexto = LocalContext.current
    val alcance = LocalAlcanceApp.current
    // Lo que mira `relojesVisibles`, leído de los flujos para recomponer.
    val disponibles by salud.relojesDisponibles.collectAsStateWithLifecycle()
    val conexiones by salud.conexiones.collectAsStateWithLifecycle()
    val esperando by salud.esperandoReloj.collectAsStateWithLifecycle()
    val relojes = remember(disponibles, conexiones) { salud.relojesVisibles }
    var mensaje by remember { mutableStateOf<String?>(null) }
    var aQuitar by remember { mutableStateOf<ModeloSalud.Reloj?>(null) }

    LaunchedEffect(salud) { if (salud.relojesDisponibles.value == null) salud.cargarRelojes() }

    fun conectar(r: ModeloSalud.Reloj) {
        mensaje = "Te va a abrir el sitio de ${r.id}. Cuando termines, volvé acá — se conecta solo."
        abrirEnNavegador(contexto, salud.urlConectar(r.id))
        alcance.launch {
            if (salud.esperarConexion(r.id)) {
                mensaje = "✅ Listo. Tus datos van a aparecer en un rato."
            } else if (salud.esperandoReloj.value == null) {
                mensaje = "No llegué a confirmarlo. Si lo autorizaste, va a aparecer solo en unos minutos."
            }
        }
    }

    if (relojes.isEmpty()) return
    val c = MyPump.colores
    // La tarjeta en su propio nodo: el [modifier] de afuera trae la etiqueta de la sección, y dos etiquetas en el mismo
    // nodo se pisan.
    Column(modifier) {
        Tarjeta(Modifier.testTag("card-reloj"), espaciado = 10.dp) {
            EncabezadoSalud("⌚️", "Mi reloj")
            Text(salud.textoRelojes, style = MaterialTheme.typography.bodySmall, color = c.textoSecundario)
            relojes.forEachIndexed { i, r ->
                Row(Modifier.padding(vertical = 4.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                            Text(r.nombre, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Medium)
                            if (r.conectado) Chip("conectado", tono = c.exito)
                            if (r.enError) Chip("hay que reconectar", tono = c.peligro)
                        }
                        Text(r.ultimaSincronizacion?.let { "Última sincronización: $it" } ?: r.descripcion, style = Letras.caption, color = c.textoSecundario)
                    }
                    if (r.conectado) {
                        BotonSecundario("Quitar", alTocar = { aQuitar = r }, compacto = true, modifier = Modifier.testTag("reloj-quitar-${r.id}"))
                    } else {
                        BotonSecundario(
                            if (esperando == r.id) "Abriendo…" else "Conectar",
                            alTocar = { conectar(r) },
                            compacto = true,
                            habilitado = esperando != r.id,
                            modifier = Modifier.testTag("reloj-conectar-${r.id}"),
                        )
                    }
                }
                if (i < relojes.lastIndex) Separador()
            }
            mensaje?.let { NotaSalud(it, Modifier.testTag("mensaje-reloj")) }
        }
    }

    aQuitar?.let { r ->
        Alerta(
            titulo = "¿Quitar ${r.id}?",
            mensaje = "Dejamos de traer tus datos. Los que ya están se quedan.",
            botones = listOf(
                BotonAlerta("Cancelar", etiqueta = "cancelar-quitar-reloj", cancelar = true) { aQuitar = null },
                BotonAlerta("Quitar", etiqueta = "confirmar-quitar-reloj", destructivo = true) {
                    aQuitar = null
                    alcance.launch { salud.quitar(r.id) }
                },
            ),
            alDescartar = { aQuitar = null },
        )
    }
}
