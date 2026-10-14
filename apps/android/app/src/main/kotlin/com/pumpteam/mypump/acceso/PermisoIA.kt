package com.pumpteam.mypump.acceso

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.ModalBottomSheetProperties
import androidx.compose.material3.SheetValue
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.pumpteam.mypump.datos.ModeloApp
import com.pumpteam.mypump.diseno.BotonMarca
import com.pumpteam.mypump.diseno.BotonSecundario
import com.pumpteam.mypump.diseno.Espacio
import com.pumpteam.mypump.diseno.Iconos
import com.pumpteam.mypump.diseno.MyPump
import com.pumpteam.mypump.diseno.Radio
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch

/** Lo que el cliente estaba por hacer cuando apareció la pregunta: sigue con lo que eligió. */
class PedidoIA(val seguir: (acepta: Boolean) -> Unit)

/**
 * El permiso para la IA (D7, guía 5.1.2(i) de Apple, que en Android se respeta igual): una sola vez por cliente, justo
 * antes del primer uso. Las pantallas que mandan algo a la IA (el primer mensaje del chat, la primera foto analizada, el
 * primer check) llaman a [antesDeUsarIA]; la raíz muestra la hoja ([HojaPermisoIA]) mientras haya un pedido.
 */
@Stable
class PermisoIAEstado {
    var pedido by mutableStateOf<PedidoIA?>(null)
        private set

    /**
     * Si el cliente nunca decidió, pregunta y después sigue con lo que eligió (los dos caminos siguen: con "No, sin IA" el
     * mensaje igual sale y lo contesta Mati). Si ya decidió, o el servidor todavía no sabe de permisos, sigue directo con
     * si la IA puede leerlo. Devuelve si mostró la pregunta.
     */
    fun antesDeUsarIA(modelo: ModeloApp, seguir: (acepta: Boolean) -> Unit): Boolean {
        if (modelo.faltaConsentimientoIA) {
            pedido = PedidoIA(seguir)
            return true
        }
        seguir(modelo.analisisDeFotoPermitido)
        return false
    }

    internal fun cerrar() {
        pedido = null
    }
}

/** El permiso de la IA de la app (lo provee la raíz). */
val LocalPermisoIA = staticCompositionLocalOf<PermisoIAEstado?> { null }

/**
 * La hoja del permiso mientras haya un pedido. Hay que elegir: no se cierra deslizando, tocando afuera ni con Atrás. La
 * decisión entra primero a la cola, después lo que la disparó (queda detrás) y recién ahí se vacía: con mala señal el
 * mensaje no espera a que salga la decisión, y el servidor ya la tiene cuando llega lo otro. Eso corre en [alcance] (el
 * del ViewModel): ni rotar la pantalla ni que se cierre la hoja lo cortan.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HojaPermisoIA(modelo: ModeloApp, estado: PermisoIAEstado, alcance: CoroutineScope) {
    val pedido = estado.pedido ?: return
    var decidido by remember(pedido) { mutableStateOf(false) }
    val hoja = rememberModalBottomSheetState(
        skipPartiallyExpanded = true,
        confirmValueChange = { it != SheetValue.Hidden || decidido },
    )
    val alcanceHoja = rememberCoroutineScope()
    fun decidir(acepta: Boolean) {
        if (decidido) return
        decidido = true
        alcance.launch {
            modelo.decidirConsentimientoIA(acepta, drenar = false)
            pedido.seguir(acepta)
            modelo.drenarCola()
        }
        alcanceHoja.launch {
            try {
                hoja.hide()
            } finally {
                estado.cerrar()
            }
        }
    }
    ModalBottomSheet(
        onDismissRequest = {},
        sheetState = hoja,
        properties = ModalBottomSheetProperties(shouldDismissOnBackPress = false, shouldDismissOnClickOutside = false),
        dragHandle = null,
        containerColor = MyPump.colores.fondo,
        tonalElevation = 0.dp,
        modifier = Modifier.testTag("permiso-ia"),
    ) {
        ContenidoPermisoIA(alDecidir = ::decidir)
    }
}

/** Qué lee la IA y de quién es, con un "no" real (supabase/migrations/nativa_002, chat_worker y centinela). */
@Composable
fun ContenidoPermisoIA(alDecidir: (Boolean) -> Unit) {
    val c = MyPump.colores
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = Espacio.l)
            .padding(bottom = Espacio.l),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Column(
            modifier = Modifier.widthIn(max = 560.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(Espacio.m),
        ) {
            Spacer(Modifier.height(Espacio.l))
            Box(
                modifier = Modifier
                    .size(84.dp)
                    .shadow(16.dp, RoundedCornerShape(24.dp), ambientColor = c.marca, spotColor = c.marca)
                    .clip(RoundedCornerShape(24.dp))
                    .background(Brush.verticalGradient(listOf(c.marca, c.marca.copy(alpha = 0.85f)))),
                contentAlignment = Alignment.Center,
            ) {
                Icon(Iconos.Chispas, contentDescription = null, tint = c.sobreMarca, modifier = Modifier.size(40.dp))
            }
            Text(
                "Antes de seguir: el asistente de IA",
                style = MaterialTheme.typography.headlineSmall.copy(fontSize = 26.sp, lineHeight = 31.sp),
                textAlign = TextAlign.Center,
                modifier = Modifier.semantics { heading() },
            )
            Text(
                "Para contestarte más rápido, Mati usa herramientas de inteligencia artificial de OpenAI y Anthropic. Esto es lo que leen:",
                style = MaterialTheme.typography.bodyLarge,
                textAlign = TextAlign.Center,
            )
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(Radio.control + 4.dp))
                    .background(c.campo)
                    .padding(Espacio.m),
                verticalArrangement = Arrangement.spacedBy(Espacio.m),
            ) {
                FilaPermiso(
                    Iconos.Chat,
                    "Chat",
                    "Tus mensajes, tu nombre de pila y el resumen de tu check (por ejemplo, tu peso), para preparar la respuesta. Lo que es sobre tu plan, tu salud o tus números lo contesta Mati.",
                )
                FilaPermiso(Iconos.Camara, "Fotos", "La foto de un plato o de una etiqueta que mandes a analizar, para calcular los valores.")
                FilaPermiso(
                    Iconos.Checklist,
                    "Revisión semanal",
                    "Tu check y tus métricas, para ayudar a Mati con tu devolución. Los datos de salud van sin tu nombre.",
                )
            }
            Text(
                "Si decís que no, ninguna IA lee tus datos: te contesta Mati y las fotos no se analizan. Lo podés cambiar cuando quieras en Mis datos.",
                style = MaterialTheme.typography.bodySmall,
                color = c.textoSecundario,
                textAlign = TextAlign.Center,
            )
            Column(Modifier.padding(top = Espacio.xs), verticalArrangement = Arrangement.spacedBy(Espacio.xs)) {
                BotonMarca("Acepto", alTocar = { alDecidir(true) }, modifier = Modifier.testTag("ia-acepto"))
                BotonSecundario("No, sin IA", alTocar = { alDecidir(false) }, modifier = Modifier.testTag("ia-no"))
            }
        }
    }
}

@Composable
private fun FilaPermiso(icono: ImageVector, titulo: String, texto: String) {
    val c = MyPump.colores
    Row(horizontalArrangement = Arrangement.spacedBy(Espacio.s), modifier = Modifier.semantics(mergeDescendants = true) {}) {
        Icon(icono, contentDescription = null, tint = c.marcaTexto, modifier = Modifier.padding(top = 2.dp).size(22.dp))
        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(titulo, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold)
            Text(texto, style = MaterialTheme.typography.bodyMedium, color = c.textoSecundario)
        }
    }
}
