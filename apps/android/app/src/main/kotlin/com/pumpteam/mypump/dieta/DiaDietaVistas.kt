package com.pumpteam.mypump.dieta

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
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
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTagsAsResourceId
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.pumpteam.mypump.datos.DiaPasado
import com.pumpteam.mypump.datos.ModeloApp
import com.pumpteam.mypump.datos.ResultadoCopia
import com.pumpteam.mypump.datos.copiarAHoy
import com.pumpteam.mypump.datos.fechasDieta
import com.pumpteam.mypump.datos.irADia
import com.pumpteam.mypump.datos.prepararCopia
import com.pumpteam.mypump.diseno.AccionHoja
import com.pumpteam.mypump.diseno.Alerta
import com.pumpteam.mypump.diseno.AsaHoja
import com.pumpteam.mypump.diseno.BotonAlerta
import com.pumpteam.mypump.diseno.BotonMarca
import com.pumpteam.mypump.diseno.EncabezadoHoja
import com.pumpteam.mypump.diseno.Espacio
import com.pumpteam.mypump.diseno.EstadoVacio
import com.pumpteam.mypump.diseno.FormaHoja
import com.pumpteam.mypump.diseno.Formato
import com.pumpteam.mypump.diseno.Iconos
import com.pumpteam.mypump.diseno.MyPump
import com.pumpteam.mypump.raiz.LocalAlcanceApp
import com.pumpteam.mypump.reglas.CopiaDeComidas
import com.pumpteam.mypump.reglas.DiasDieta
import com.pumpteam.mypump.reglas.FechaLocal
import com.pumpteam.mypump.reglas.jsRound
import kotlinx.coroutines.launch

/** La tira de días de Dieta: hoy y los 7 anteriores, fija arriba. «Hoy» va primero: se abre siempre ahí. */
@Composable
internal fun SelectorDiaDieta(fechas: List<String>, elegida: String, modifier: Modifier = Modifier, alElegir: (String) -> Unit) {
    val c = MyPump.colores
    val hoy = FechaLocal.hoy()
    val lista = rememberLazyListState()
    // El elegido a la vista, con el anterior asomando (el `scrollTo(anchor: .center)` de iOS).
    LaunchedEffect(elegida) {
        val i = fechas.indexOf(elegida)
        if (i >= 0) lista.animateScrollToItem((i - 1).coerceAtLeast(0))
    }
    LazyRow(
        state = lista,
        modifier = modifier.fillMaxWidth().testTag("selector-dias"),
        contentPadding = PaddingValues(horizontal = Espacio.m),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        items(fechas, key = { it }) { f ->
            val activo = f == elegida
            Box(
                Modifier
                    .heightIn(min = 48.dp)
                    .clip(CircleShape)
                    .clickable(role = Role.Button) { alElegir(f) }
                    .semantics {
                        contentDescription = if (f == hoy) "Hoy" else DiasDieta.rotuloLargo(f)
                        selected = activo
                    }
                    .testTag("dia-$f"),
                contentAlignment = Alignment.Center,
            ) {
                Box(
                    Modifier.heightIn(min = 36.dp).clip(CircleShape).background(if (activo) c.marca else c.campo).padding(horizontal = 14.dp),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(
                        DiasDieta.rotuloCorto(f, hoy),
                        style = MaterialTheme.typography.bodyMedium,
                        fontWeight = if (activo) FontWeight.Bold else FontWeight.Medium,
                        color = if (activo) c.sobreMarca else c.texto.copy(alpha = 0.8f),
                        maxLines = 1,
                    )
                }
            }
        }
    }
}

/** Mirando un día anterior: de qué día se trata, a la vista todo el tiempo, y la vuelta a hoy. */
@Composable
internal fun BannerDiaPasado(
    dia: DiaPasado,
    puedeMarcar: Boolean,
    diasMarcar: Int,
    modifier: Modifier = Modifier,
    copiar: () -> Unit,
    volver: () -> Unit,
) {
    val c = MyPump.colores
    Column(
        modifier
            .fillMaxWidth()
            .padding(start = Espacio.m, end = Espacio.m, bottom = 6.dp)
            .clip(RoundedCornerShape(14.dp))
            .background(c.alerta.copy(alpha = 0.16f))
            .padding(12.dp)
            .testTag("banner-dia-pasado"),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.semantics(mergeDescendants = true) {}) {
            Icon(Iconos.Calendario, contentDescription = null, tint = c.alerta, modifier = Modifier.size(20.dp))
            Column(verticalArrangement = Arrangement.spacedBy(1.dp)) {
                Text("Estás viendo otro día", style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.SemiBold, color = c.alerta)
                Text(DiasDieta.rotuloLargo(dia.fecha), style = MaterialTheme.typography.titleMedium, color = c.alerta, modifier = Modifier.testTag("dia-rotulo"))
            }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            BotonBanner(Iconos.Deshacer, "Volver a hoy", "volver-a-hoy", Modifier.weight(1f), volver)
            if (!dia.cargando && !dia.sinRed) BotonBanner(Iconos.Documento, "Copiar a hoy", "copiar-a-hoy", Modifier.weight(1f), copiar)
        }
        if (dia.otroPlan) {
            Text(
                "Ese día tenías otro plan. Acá ves el plan actual: lo que cargaste entonces queda guardado y solo podés sumar comidas libres.",
                style = MaterialTheme.typography.bodySmall,
                color = c.alerta,
                modifier = Modifier.testTag("dia-otro-plan"),
            )
        } else if (!puedeMarcar) {
            Text(
                "«Comí» y «Salté» se pueden marcar hasta $diasMarcar días atrás. Para este día, cargá lo que comiste en «Comidas libres».",
                style = MaterialTheme.typography.bodySmall,
                color = c.alerta,
                modifier = Modifier.testTag("dia-sin-marcas"),
            )
        }
    }
}

@Composable
private fun BotonBanner(icono: ImageVector, texto: String, etiqueta: String, modifier: Modifier, alTocar: () -> Unit) {
    val c = MyPump.colores
    Row(
        modifier
            .heightIn(min = 48.dp)
            .clip(RoundedCornerShape(10.dp))
            .background(c.fondo)
            .clickable(role = Role.Button, onClick = alTocar)
            .padding(horizontal = 8.dp)
            .testTag(etiqueta),
        horizontalArrangement = Arrangement.spacedBy(6.dp, Alignment.CenterHorizontally),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(icono, contentDescription = null, tint = c.alerta, modifier = Modifier.size(16.dp))
        Text(texto, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold, color = c.alerta, maxLines = 2)
    }
}

/**
 * Copiar a hoy lo cargado otro día: una lista con cada comida y cada comida libre, ya tildada, para copiar el día entero o
 * solo lo que se quiera. Lo que hoy ya tiene algo viene sin tildar, y tildarlo pregunta antes de reemplazar. Gemela de
 * `CopiarDiaView` de iOS.
 */
@OptIn(ExperimentalMaterial3Api::class, ExperimentalComposeUiApi::class)
@Composable
internal fun HojaCopiarDia(modelo: ModeloApp, origenInicial: String, alCerrar: () -> Unit) {
    val c = MyPump.colores
    val hoja = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val alcanceHoja = rememberCoroutineScope()
    val alcance = LocalAlcanceApp.current
    var origen by rememberSaveable { mutableStateOf(origenInicial) }
    var plan by remember { mutableStateOf<CopiaDeComidas.Plan?>(null) }
    var sinRed by remember { mutableStateOf(false) }
    var elegidas by rememberSaveable { mutableStateOf(setOf<String>()) }
    // De qué día son los tildes: al girar el teléfono la lista se vuelve a pedir y lo elegido no se pierde.
    var elegidasDe by rememberSaveable { mutableStateOf<String?>(null) }
    var preguntar by rememberSaveable { mutableStateOf(false) }
    var copiando by remember { mutableStateOf(false) }
    var falla by remember { mutableStateOf<ResultadoCopia?>(null) }
    val pisan = plan?.comidas.orEmpty().filter { it.id in elegidas && it.estado == CopiaDeComidas.Estado.CONFLICTO }
    val cuantas = elegidas.size

    fun cerrar() {
        alcanceHoja.launch { hoja.hide() }.invokeOnCompletion { alCerrar() }
    }

    LaunchedEffect(origen) {
        plan = null
        sinRed = false
        val p = modelo.prepararCopia(origen)
        plan = p
        sinRed = p == null
        // Todo lo nuevo viene tildado: es copiar el día entero con un toque. Lo que pisa algo de hoy, no.
        if (elegidasDe != origen) {
            elegidas = p?.comidas.orEmpty().filter { it.estado == CopiaDeComidas.Estado.NUEVA }.map { it.id }.toSet() +
                p?.libres.orEmpty().filter { it.estado == CopiaDeComidas.Estado.NUEVA }.map { it.id }
            elegidasDe = origen
        }
    }

    fun copiar() {
        val p = plan ?: return
        val reemplazar = pisan.map { it.id }.toSet()
        copiando = true
        // Con el alcance de la app: lo que empezó a copiarse termina aunque se cierre la hoja.
        alcance.launch {
            // Las iguales van siempre: cada una descuenta la suya de hoy (dos iguales en el origen y una hoy son una que falta).
            val libres = p.libres.filter { it.id in elegidas || it.estado == CopiaDeComidas.Estado.IGUAL }
            val r = modelo.copiarAHoy(p.comidas.filter { it.id in elegidas }, libres, reemplazar)
            copiando = false
            modelo.irADia(null)
            if (r.libresFallidas > 0 || r.saltadas > 0) falla = r else cerrar()
        }
    }

    ModalBottomSheet(
        onDismissRequest = alCerrar,
        sheetState = hoja,
        shape = FormaHoja,
        containerColor = c.fondo,
        tonalElevation = 0.dp,
        dragHandle = { AsaHoja() },
        modifier = Modifier.semantics { testTagsAsResourceId = true }.testTag("hoja-copiar"),
    ) {
        Column(Modifier.fillMaxWidth().fillMaxHeight(0.92f).navigationBarsPadding()) {
            EncabezadoHoja("Copiar a hoy", cancelar = AccionHoja("Cancelar", "copiar-cancelar", alTocar = ::cerrar))
            val p = plan
            LazyColumn(
                Modifier.weight(1f).fillMaxWidth(),
                contentPadding = PaddingValues(bottom = Espacio.m),
                verticalArrangement = Arrangement.spacedBy(Espacio.xxs),
            ) {
                item(key = "desde") {
                    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        Encabezado("Copiar desde")
                        SelectorDiaDieta(modelo.fechasDieta.drop(1), origen, alElegir = { origen = it })
                    }
                }
                when {
                    sinRed -> item(key = "sin-red") {
                        EstadoVacio(icono = Iconos.SinWifi, titulo = "Sin conexión", texto = "Hace falta señal para traer lo de ese día.")
                    }
                    p == null -> item(key = "cargando") {
                        Box(Modifier.fillMaxWidth().padding(Espacio.l), contentAlignment = Alignment.Center) {
                            CircularProgressIndicator(color = c.marcaTexto)
                        }
                    }
                    else -> {
                        if (p.otroPlan) item(key = "otro-plan") {
                            Text(
                                "Ese día tenías otro plan: solo se pueden copiar las comidas libres.",
                                style = MaterialTheme.typography.bodySmall,
                                color = c.textoSecundario,
                                modifier = Modifier.padding(horizontal = Espacio.m),
                            )
                        }
                        if (p.vacio) item(key = "vacio") {
                            EstadoVacio(
                                icono = Iconos.Cubiertos,
                                titulo = "Nada para copiar",
                                texto = "Ese día no tiene comidas marcadas ni cargadas.",
                                modifier = Modifier.testTag("copiar-vacio"),
                            )
                        }
                        if (p.comidas.isNotEmpty()) {
                            item(key = "t-comidas") { Encabezado("Comidas") }
                            items(p.comidas, key = { "c-${it.id}" }) { i ->
                                FilaCopia(i.id, i.nombre, detalleCopia(i), i.estado, i.id in elegidas) { elegidas = if (i.id in elegidas) elegidas - i.id else elegidas + i.id }
                            }
                        }
                        if (p.libres.isNotEmpty()) {
                            item(key = "t-libres") { Encabezado("Comidas libres") }
                            items(p.libres, key = { "l-${it.id}" }) { i ->
                                FilaCopia(i.id, i.libre.descripcion ?: "", "${Formato.miles(jsRound(i.libre.kcal ?: 0.0))} kcal", i.estado, i.id in elegidas) {
                                    elegidas = if (i.id in elegidas) elegidas - i.id else elegidas + i.id
                                }
                            }
                        }
                    }
                }
            }
            if (p != null && !p.vacio) {
                BotonMarca(
                    if (cuantas == 1) "Copiar 1 comida a hoy" else "Copiar $cuantas comidas a hoy",
                    alTocar = { if (pisan.isEmpty()) copiar() else preguntar = true },
                    modifier = Modifier.fillMaxWidth().padding(Espacio.m).testTag("copiar-confirmar"),
                    habilitado = cuantas > 0,
                    cargando = copiando,
                )
            }
        }
    }
    if (preguntar) {
        Alerta(
            titulo = "¿Reemplazar lo que cargaste hoy?",
            mensaje = "Hoy ya tenés cargado: ${pisan.joinToString(", ") { it.nombre }}. Se reemplaza por lo de ese día.",
            botones = listOf(
                BotonAlerta("Cancelar", etiqueta = "copiar-no-reemplazar", cancelar = true) { preguntar = false },
                BotonAlerta("Reemplazar y copiar", etiqueta = "copiar-reemplazar", destructivo = true) {
                    preguntar = false
                    copiar()
                },
            ),
            alDescartar = { preguntar = false },
            modifier = Modifier.testTag("copiar-preguntar"),
        )
    }
    falla?.let { r ->
        Alerta(
            titulo = "No se pudo copiar todo",
            mensaje = listOfNotNull(
                "Faltaron ${r.libresFallidas} comidas libres: probá de nuevo cuando tengas señal.".takeIf { r.libresFallidas > 0 },
                "No se copiaron ${r.saltadas} comidas: cambiaron o no entraban. Probá de nuevo.".takeIf { r.saltadas > 0 },
            ).joinToString(" "),
            etiquetaMensaje = "copiar-aviso",
            botones = listOf(BotonAlerta("OK", cancelar = true) { falla = null; cerrar() }),
            alDescartar = { falla = null; cerrar() },
        )
    }
}

@Composable
private fun Encabezado(texto: String) {
    Text(
        texto,
        style = MaterialTheme.typography.labelLarge,
        fontWeight = FontWeight.SemiBold,
        color = MyPump.colores.textoSecundario,
        modifier = Modifier.padding(start = Espacio.m, end = Espacio.m, top = Espacio.s),
    )
}

private fun detalleCopia(i: CopiaDeComidas.ItemComida): String = buildList {
    add("Opción ${i.nombreOpcion}")
    if (i.agregados > 0) add("${i.agregados} ${if (i.agregados == 1) "agregado" else "agregados"}")
    if (i.conCantidades) add("con ajustes")
    add("${Formato.miles(i.kcal)} kcal")
}.joinToString(" · ")

@Composable
private fun FilaCopia(id: String, titulo: String, detalle: String, estado: CopiaDeComidas.Estado, tildada: Boolean, alTocar: () -> Unit) {
    val c = MyPump.colores
    Row(
        Modifier
            .fillMaxWidth()
            .padding(horizontal = Espacio.m)
            .clip(RoundedCornerShape(12.dp))
            .background(c.tarjeta)
            .toggleable(value = tildada, enabled = estado != CopiaDeComidas.Estado.IGUAL, role = Role.Checkbox) { alTocar() }
            .heightIn(min = 56.dp)
            .padding(horizontal = 12.dp, vertical = 10.dp)
            .testTag("copiar-item-$id"),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(
            if (tildada) Iconos.TildeEnCirculo else Iconos.Circulo,
            contentDescription = null,
            tint = if (tildada) c.marca else c.textoSecundario,
            modifier = Modifier.size(24.dp),
        )
        Spacer(Modifier.width(10.dp))
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(titulo, style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.Medium)
            Text(detalle, style = MaterialTheme.typography.bodySmall, color = c.textoSecundario)
            if (estado == CopiaDeComidas.Estado.CONFLICTO) {
                Text("Hoy ya cargaste algo acá: si la tildás, se reemplaza.", style = MaterialTheme.typography.labelSmall, fontWeight = FontWeight.SemiBold, color = c.alerta)
            } else if (estado == CopiaDeComidas.Estado.IGUAL) {
                Text("Ya está igual hoy", style = MaterialTheme.typography.labelSmall, fontWeight = FontWeight.SemiBold, color = c.textoSecundario)
            }
        }
    }
}
