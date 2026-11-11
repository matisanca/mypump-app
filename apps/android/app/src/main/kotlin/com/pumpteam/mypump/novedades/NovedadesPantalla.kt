package com.pumpteam.mypump.novedades

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTagsAsResourceId
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.pumpteam.mypump.acceso.Onboarding
import com.pumpteam.mypump.datos.ModeloApp
import com.pumpteam.mypump.datos.ModeloNovedades
import com.pumpteam.mypump.datos.NovedadPlan
import com.pumpteam.mypump.diseno.Archivo
import com.pumpteam.mypump.diseno.AsaHoja
import com.pumpteam.mypump.diseno.BotonMarca
import com.pumpteam.mypump.diseno.BotonSecundario
import com.pumpteam.mypump.diseno.Espacio
import com.pumpteam.mypump.diseno.EstadoVacio
import com.pumpteam.mypump.diseno.FormaHoja
import com.pumpteam.mypump.diseno.Iconos
import com.pumpteam.mypump.diseno.MyPump
import com.pumpteam.mypump.diseno.PantallaConTitulo
import com.pumpteam.mypump.diseno.Radio
import com.pumpteam.mypump.diseno.superficieTarjeta
import com.pumpteam.mypump.raiz.Navegacion
import com.pumpteam.mypump.raiz.Pestana
import com.pumpteam.mypump.reglas.ParteNovedad
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.temporal.ChronoUnit
import java.util.Locale
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

// «Novedades de tu plan» (2.3.0, palanca `novedades_plan`). Gemelo de NovedadesPlanView.swift: la hoja que aparece sola al
// abrir (una vez por novedad), la tarjeta de Entreno durante una semana y la lista en Mis datos (el lugar fijo).

/** Qué novedad está abierta en la hoja, y las que ya se pidieron solas en esta apertura. */
object NovedadesUI {
    var abierta by mutableStateOf<NovedadPlan?>(null)
    val yaPedidas = mutableSetOf<String>()
    /** La bienvenida de «Tu guía» a la vista: las dos hojas no se apilan (la que llega segunda espera). */
    var bienvenidaGuia by mutableStateOf(false)

    /** Al salir o cambiar de cuenta no queda nada de la anterior. */
    fun olvidar() { abierta = null; yaPedidas.clear() }
    /** El modelo de la cuenta a la que pertenecen [abierta] y [yaPedidas]. */
    internal var dueno: Any? = null
}

object TextosNovedades {
    const val CEJA = "Novedades de tu plan"
    const val ENTRADA_MIS_DATOS = "Novedades de tu plan"
    const val VACIO = "Cuando Mati cambie tu rutina, tu dieta o tu suplementación, lo vas a ver acá."
    const val LISTO = "Listo"

    fun area(a: String) = when (a) { "rutina" -> "Rutina"; "dieta" -> "Dieta"; else -> "Suplementación" }
    fun icono(a: String): ImageVector = when (a) { "rutina" -> Iconos.Pesa; "dieta" -> Iconos.Cubiertos; else -> Iconos.Pastilla }
    fun boton(a: String) = when (a) { "rutina" -> "Ver mi rutina"; "dieta" -> "Ver mi dieta"; else -> "Ver mi suplementación" }
    fun etiquetaGrande(p: ParteNovedad): String? = if (!p.grande) null
    else if (p.area == "rutina") (if ("bloque" in p.titular) "Bloque nuevo" else "Nueva")
    else if ("nueva" in p.titular) "Nueva" else "Primera vez"

    /** «Hoy», «Ayer», «Hace 3 días», «4 de noviembre». */
    fun cuando(fechaMs: Double, hoy: LocalDate = LocalDate.now()): String {
        val dia = Instant.ofEpochMilli(fechaMs.toLong()).atZone(ZoneId.systemDefault()).toLocalDate()
        return when (val d = ChronoUnit.DAYS.between(dia, hoy)) {
            in Long.MIN_VALUE..0L -> "Hoy"
            1L -> "Ayer"
            in 2L..6L -> "Hace $d días"
            else -> dia.format(DateTimeFormatter.ofPattern("d 'de' MMMM", Locale.forLanguageTag("es-AR")))
        }
    }
}

private fun puedeIr(modelo: ModeloApp, area: String) = area != "suplementacion" || modelo.suplementacion.value?.plan?.value != null

private fun ir(navegacion: Navegacion, area: String) {
    navegacion.pestana = when (area) { "rutina" -> Pestana.ENTRENO; "dieta" -> Pestana.DIETA; else -> Pestana.SUPLEMENTACION }
}

@Composable
private fun IconoNovedad(lado: androidx.compose.ui.unit.Dp) {
    val c = MyPump.colores
    Box(
        Modifier.size(lado).clip(RoundedCornerShape(lado * 0.3f))
            .background(Brush.verticalGradient(listOf(c.marca.copy(alpha = 0.85f), c.marca))),
        contentAlignment = Alignment.Center,
    ) {
        Icon(Iconos.Chispas, contentDescription = null, tint = c.sobreMarca, modifier = Modifier.size(lado * 0.48f))
    }
}

@Composable
private fun TarjetaParte(parte: ParteNovedad, ver: ((String) -> Unit)?) {
    val c = MyPump.colores
    Column(
        Modifier.fillMaxWidth().superficieTarjeta().padding(Espacio.m).testTag("novedad-parte-${parte.area}"),
        verticalArrangement = Arrangement.spacedBy(Espacio.s),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espacio.xs)) {
            Box(Modifier.size(34.dp).clip(RoundedCornerShape(10.dp)).background(c.marcaSuave), contentAlignment = Alignment.Center) {
                Icon(TextosNovedades.icono(parte.area), contentDescription = null, tint = c.marcaTexto, modifier = Modifier.size(18.dp))
            }
            Text(
                TextosNovedades.area(parte.area),
                style = MaterialTheme.typography.titleLarge.copy(fontSize = MaterialTheme.typography.titleMedium.fontSize),
                color = c.texto,
                modifier = Modifier.semantics { heading() },
            )
            TextosNovedades.etiquetaGrande(parte)?.let {
                Text(
                    it, style = MaterialTheme.typography.labelMedium.copy(fontWeight = FontWeight.Bold), color = c.marcaTexto,
                    modifier = Modifier.clip(CircleShape).background(c.marcaSuave).padding(horizontal = 9.dp, vertical = 4.dp),
                )
            }
            Spacer(Modifier.weight(1f))
            if (ver != null) {
                Row(
                    Modifier.heightIn(min = 44.dp).clip(CircleShape).clickable(role = Role.Button) { ver(parte.area) }
                        .padding(horizontal = Espacio.xs)
                        .semantics { contentDescription = TextosNovedades.boton(parte.area) }
                        .testTag("novedad-ver-${parte.area}"),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text("Ver", style = MaterialTheme.typography.titleSmall, color = c.marcaTexto)
                    Icon(Iconos.Chevron, contentDescription = null, tint = c.marcaTexto, modifier = Modifier.size(16.dp))
                }
            }
        }
        Column(verticalArrangement = Arrangement.spacedBy(Espacio.xs)) {
            for (l in parte.lineas) {
                Row(horizontalArrangement = Arrangement.spacedBy(Espacio.s)) {
                    Box(Modifier.padding(top = 8.dp).size(7.dp).clip(CircleShape).background(c.marca))
                    Text(l, style = MaterialTheme.typography.bodyLarge, color = c.texto)
                }
            }
        }
    }
}

@Composable
private fun ContenidoNovedad(n: NovedadPlan, ver: ((String) -> Unit)?, puede: (String) -> Boolean) {
    val c = MyPump.colores
    Column(verticalArrangement = Arrangement.spacedBy(Espacio.l)) {
        Column(verticalArrangement = Arrangement.spacedBy(Espacio.s)) {
            IconoNovedad(56.dp)
            Text(TextosNovedades.CEJA.uppercase(), style = MaterialTheme.typography.labelMedium, color = c.textoSecundario)
            Text(
                n.titular, style = MaterialTheme.typography.headlineMedium, color = c.texto,
                modifier = Modifier.semantics { heading() }.testTag("novedad-titular"),
            )
            Text(TextosNovedades.cuando(n.fecha), style = MaterialTheme.typography.bodyMedium, color = c.textoSecundario)
        }
        for (p in n.partes) TarjetaParte(p, if (n.partes.size > 1 && puede(p.area)) ver else null)
    }
}

/** La hoja de la novedad: el contenido, «Ver mi …» y «Listo». Al abrirse queda vista. */
@OptIn(ExperimentalMaterial3Api::class, ExperimentalComposeUiApi::class)
@Composable
fun HojaNovedad(n: NovedadPlan, modelo: ModeloApp, navegacion: Navegacion, alCerrar: () -> Unit) {
    val c = MyPump.colores
    val hoja = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val alcance = rememberCoroutineScope()
    LaunchedEffect(n.id) { modelo.novedades.value?.marcarVista(n.id) }
    fun cerrarY(accion: () -> Unit) {
        alcance.launch { hoja.hide() }.invokeOnCompletion { accion() }
    }
    val destino = n.partes.singleOrNull()?.area?.takeIf { puedeIr(modelo, it) }
    ModalBottomSheet(
        onDismissRequest = alCerrar,
        sheetState = hoja,
        shape = FormaHoja,
        containerColor = c.fondo,
        tonalElevation = 0.dp,
        dragHandle = { AsaHoja() },
        modifier = Modifier.semantics { testTagsAsResourceId = true }.testTag("novedad-hoja"),
    ) {
        Column(Modifier.fillMaxWidth().navigationBarsPadding(), horizontalAlignment = Alignment.CenterHorizontally) {
            Column(
                Modifier.weight(1f, fill = false).widthIn(max = 700.dp).fillMaxWidth()
                    .verticalScroll(rememberScrollState()).padding(horizontal = Espacio.m, vertical = Espacio.m),
            ) {
                ContenidoNovedad(n, ver = { a -> cerrarY { alCerrar(); ir(navegacion, a) } }, puede = { puedeIr(modelo, it) })
            }
            Column(
                Modifier.widthIn(max = 700.dp).fillMaxWidth().padding(horizontal = Espacio.m, vertical = Espacio.s),
                verticalArrangement = Arrangement.spacedBy(Espacio.xs),
            ) {
                if (destino != null) {
                    BotonMarca(TextosNovedades.boton(destino), alTocar = { cerrarY { alCerrar(); ir(navegacion, destino) } }, modifier = Modifier.testTag("novedad-ver"))
                    BotonSecundario(TextosNovedades.LISTO, alTocar = { cerrarY(alCerrar) }, modifier = Modifier.testTag("novedad-listo"))
                } else {
                    BotonMarca(TextosNovedades.LISTO, alTocar = { cerrarY(alCerrar) }, modifier = Modifier.testTag("novedad-listo"))
                }
            }
        }
    }
}

/** La hoja desde cualquier lugar y, al abrir, la pendiente una sola vez (después de la hoja de permisos). */
@Composable
fun HojaDeNovedadesDe(modelo: ModeloApp, navegacion: Navegacion) {
    val fase by modelo.fase.collectAsStateWithLifecycle()
    val palanca by modelo.palanca.collectAsStateWithLifecycle()
    val esDemo by modelo.esDemo.collectAsStateWithLifecycle()
    val nov by modelo.novedades.collectAsStateWithLifecycle()
    val lista = nov?.lista?.collectAsStateWithLifecycle()?.value.orEmpty()
    val pendiente = if ((palanca.novedadesPlan || esDemo) && fase == ModeloApp.Fase.LISTO) lista.firstOrNull { !it.vista } else null
    LaunchedEffect(nov) {
        if (NovedadesUI.dueno !== nov) { NovedadesUI.olvidar(); NovedadesUI.dueno = nov }
    }
    LaunchedEffect(pendiente?.id) {
        val p = pendiente ?: return@LaunchedEffect
        if (p.id in NovedadesUI.yaPedidas) return@LaunchedEffect
        delay(1_200)
        // «Tu recorrido» a la vista: las hojas no se apilan (la que llega segunda espera).
        while ((Onboarding.pendiente(modelo.preferencias) && !esDemo) || NovedadesUI.bienvenidaGuia || com.pumpteam.mypump.recorrido.RecorridoUI.abierta) delay(400)
        if (navegacion.guia || NovedadesUI.abierta != null) return@LaunchedEffect
        NovedadesUI.yaPedidas += p.id
        NovedadesUI.abierta = p
    }
    NovedadesUI.abierta?.let { n -> HojaNovedad(n, modelo, navegacion, alCerrar = { NovedadesUI.abierta = null }) }
}

/** Arriba de Entreno, durante una semana después de la última novedad. Sin ver, con el punto verde. */
@Composable
fun TarjetaNovedadDe(modelo: ModeloApp, modifier: Modifier = Modifier) {
    val palanca by modelo.palanca.collectAsStateWithLifecycle()
    val esDemo by modelo.esDemo.collectAsStateWithLifecycle()
    val nov by modelo.novedades.collectAsStateWithLifecycle()
    val m = nov ?: return
    val lista by m.lista.collectAsStateWithLifecycle()
    if (!palanca.novedadesPlan && !esDemo) return
    val n = m.reciente(lista) ?: return
    val c = MyPump.colores
    Row(
        modifier.fillMaxWidth().superficieTarjeta().clip(RoundedCornerShape(Radio.tarjeta))
            .clickable(role = Role.Button) { NovedadesUI.abierta = n }
            .padding(Espacio.s + 2.dp).testTag("novedad-tarjeta"),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(Espacio.s),
    ) {
        IconoNovedad(44.dp)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(n.titular, style = MaterialTheme.typography.titleLarge.copy(fontSize = MaterialTheme.typography.titleMedium.fontSize), color = c.texto, modifier = Modifier.weight(1f, fill = false))
                if (!n.vista) Box(Modifier.size(8.dp).clip(CircleShape).background(c.marca))
            }
            Text(n.resumen, style = MaterialTheme.typography.bodyMedium, color = c.textoSecundario, maxLines = 2)
        }
        Icon(Iconos.Chevron, contentDescription = null, tint = c.textoTerciario, modifier = Modifier.size(20.dp))
    }
}

/** «Novedades de tu plan» en Mis datos: todas las guardadas, de la más nueva a la más vieja. */
@Composable
fun NovedadesListaPantalla(m: ModeloNovedades, alVolver: () -> Unit) {
    val lista by m.lista.collectAsStateWithLifecycle()
    val c = MyPump.colores
    PantallaConTitulo(TextosNovedades.ENTRADA_MIS_DATOS, alVolver = alVolver, desplazable = true) {
        if (lista.isEmpty()) {
            EstadoVacio(Iconos.Chispas, TextosNovedades.CEJA, TextosNovedades.VACIO)
        }
        for (n in lista) {
            Row(
                Modifier.padding(horizontal = Espacio.m).fillMaxWidth().superficieTarjeta().clip(RoundedCornerShape(Radio.tarjeta))
                    .clickable(role = Role.Button) { NovedadesUI.abierta = n }
                    .padding(Espacio.m).testTag("novedad-fila"),
                horizontalArrangement = Arrangement.spacedBy(Espacio.s),
            ) {
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(TextosNovedades.cuando(n.fecha).uppercase(), style = MaterialTheme.typography.labelMedium, color = c.textoSecundario)
                    Text(n.titular, style = MaterialTheme.typography.titleLarge.copy(fontSize = MaterialTheme.typography.titleMedium.fontSize), color = c.texto)
                    Text(n.resumen, style = MaterialTheme.typography.bodyMedium, color = c.textoSecundario)
                }
                Icon(Iconos.Chevron, contentDescription = null, tint = c.textoTerciario, modifier = Modifier.padding(top = 4.dp).size(20.dp))
            }
        }
    }
}
