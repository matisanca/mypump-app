package com.pumpteam.mypump.suplementacion

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.selection.SelectionContainer
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
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTagsAsResourceId
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.platform.LocalContext
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.pumpteam.mypump.diseno.BotonMarca
import com.pumpteam.mypump.diseno.BotonSecundario
import com.pumpteam.mypump.diseno.abrirEnNavegador
import com.pumpteam.mypump.datos.ModeloApp
import com.pumpteam.mypump.datos.ModeloSuplementacion
import com.pumpteam.mypump.diseno.AccionHoja
import com.pumpteam.mypump.diseno.AsaHoja
import com.pumpteam.mypump.diseno.Chip
import com.pumpteam.mypump.diseno.EncabezadoHoja
import com.pumpteam.mypump.diseno.EncabezadoSeccion
import com.pumpteam.mypump.diseno.Espacio
import com.pumpteam.mypump.diseno.FormaHoja
import com.pumpteam.mypump.diseno.Iconos
import com.pumpteam.mypump.diseno.MyPump
import com.pumpteam.mypump.diseno.PantallaConTitulo
import com.pumpteam.mypump.diseno.Separador
import com.pumpteam.mypump.diseno.superficieTarjeta
import com.pumpteam.mypump.guia.TextoConNegritas
import com.pumpteam.mypump.guia.TextoRotulado
import com.pumpteam.mypump.modelos.ItemSuplemento
import com.pumpteam.mypump.modelos.Suplementacion
import com.pumpteam.mypump.raiz.BannerRevision
import com.pumpteam.mypump.reglas.Compras
import com.pumpteam.mypump.reglas.OpcionCompra
import com.pumpteam.mypump.reglas.SuplementacionPestana
import com.pumpteam.mypump.reglas.SuplementacionVista
import kotlinx.coroutines.launch

/**
 * La pestaña Suplementación (2.1.0), de solo lectura: arriba el título y la acción si vienen, «Tu día» con los momentos
 * en el orden de `dia[]` (la misma agrupación de «Tu guía», [SuplementacionVista.armar]) y abajo «Dejás de tomar». Tocar
 * un ítem abre su detalle en una hoja. Los textos visibles son los mismos de iOS.
 */
@Composable
fun SuplementacionPantalla(m: ModeloSuplementacion, modelo: ModeloApp) {
    val plan by m.plan.collectAsStateWithLifecycle()
    val p = plan ?: return
    val s = p.suplementacion
    val vista = remember(s) { SuplementacionVista.armar(s) }
    // El ítem abierto, por su lugar en la lista y su nombre: sobrevive a girar el teléfono. Si después de un refresco en
    // ese lugar ya no está el mismo suplemento, el detalle se cierra (no muestra otro).
    var abierto by rememberSaveable { mutableStateOf<Int?>(null) }
    var abiertoNombre by rememberSaveable { mutableStateOf<String?>(null) }
    fun abrir(item: ItemSuplemento) {
        abierto = s.items.indexOf(item).takeIf { it >= 0 }
        abiertoNombre = item.nombre
    }
    fun cerrarDetalle() {
        abierto = null
        abiertoNombre = null
    }
    val itemAbierto = SuplementacionPestana.itemAbierto(s.items, abierto, abiertoNombre)
    LaunchedEffect(abierto, itemAbierto) {
        if (abierto != null && itemAbierto == null) cerrarDetalle()
    }

    // «Dónde comprarlo» (2.3.0, palanca `compras_pais`): solo lo que el servidor verificó; sin eso, la pestaña de siempre.
    val modeloCompras by modelo.compras.collectAsStateWithLifecycle()
    val compras = modeloCompras?.compras?.collectAsStateWithLifecycle()?.value
    val comprasPorItem = remember(s, compras) { Compras.porItem(s.items, compras) }
    val botonesCompra = remember(vista, comprasPorItem) { Compras.botones(vista, s.items, comprasPorItem) }
    var comprasDe by rememberSaveable { mutableStateOf<Int?>(null) }
    var comprasNombre by rememberSaveable { mutableStateOf<String?>(null) }
    // Si después de un refresco ese suplemento ya no está ahí o ya no tiene dónde comprarlo, la hoja se cierra.
    val comprasAbiertas = comprasDe?.let { i -> comprasPorItem[i]?.takeIf { s.items.getOrNull(i)?.nombre == comprasNombre } }
    LaunchedEffect(comprasDe, comprasAbiertas) {
        if (comprasDe != null && comprasAbiertas == null) {
            comprasDe = null
            comprasNombre = null
        }
    }

    PantallaConTitulo("Suplementación", desplazable = true, modifier = Modifier.testTag("suplementacion-pantalla")) {
        BannerRevision(modelo, Modifier.padding(horizontal = Espacio.m))
        Column(Modifier.fillMaxWidth().padding(horizontal = Espacio.m), verticalArrangement = Arrangement.spacedBy(Espacio.m)) {
            if (s.titulo != null || s.accion != null) Cabecera(s.titulo, s.accion)
            if (botonesCompra.isNotEmpty()) {
                Text(
                    Compras.Textos.AYUDA,
                    style = MaterialTheme.typography.bodyLarge,
                    color = MyPump.colores.texto,
                    modifier = Modifier.fillMaxWidth().superficieTarjeta(color = MyPump.colores.marcaSuave).padding(Espacio.m).testTag("compras-ayuda"),
                )
            }
            if (vista.momentos.isNotEmpty()) {
                EncabezadoSeccion("Tu día", Modifier.padding(top = Espacio.xs))
                for ((lugar, momento) in vista.momentos.withIndex()) {
                    Momento(
                        momento, ::abrir,
                        compra = { fila -> botonesCompra[lugar to fila] },
                        alComprar = { i ->
                            comprasDe = i
                            comprasNombre = s.items.getOrNull(i)?.nombre
                        },
                    )
                }
            }
            if (vista.protectores.isNotEmpty()) {
                EncabezadoSeccion(SuplementacionVista.TITULO_PROTECTORES, Modifier.padding(top = Espacio.xs))
                BloqueProtectores(vista.protectores, Modifier.fillMaxWidth().superficieTarjeta().testTag("suplementacion-protectores"))
            }
            // «¿Ya lo tenés?» (palanca `suple_estado`): con la palanca apagada o sin el servidor nuevo, no existe.
            val feedback by modelo.feedback.collectAsStateWithLifecycle()
            SeccionYaLoTenes(feedback, s.items)
            vista.sigue?.let { TextoRotulado("Sigue igual.", it, Modifier.padding(horizontal = 4.dp), tonoTexto = MyPump.colores.texto) }
            if (vista.sale.isNotEmpty()) {
                EncabezadoSeccion("Dejás de tomar", Modifier.padding(top = Espacio.xs))
                Column(Modifier.fillMaxWidth().superficieTarjeta().testTag("suplementacion-sale")) {
                    for ((i, x) in vista.sale.withIndex()) {
                        if (i > 0) Separador(sangria = Espacio.m)
                        FilaSale(x) { abrir(x.item) }
                    }
                }
            }
        }
    }

    itemAbierto?.let { item ->
        HojaSuplemento(item, s, alCerrar = ::cerrarDetalle)
    }
    comprasAbiertas?.let { opciones ->
        HojaCompras(comprasNombre.orEmpty().trim(), opciones, alCerrar = {
            comprasDe = null
            comprasNombre = null
        })
    }
}

/** «Dónde comprarlo» de un suplemento: una tarjeta por opción y, si hay dirección segura, «Abrir la tienda». */
@OptIn(ExperimentalMaterial3Api::class, ExperimentalComposeUiApi::class)
@Composable
private fun HojaCompras(nombre: String, opciones: List<OpcionCompra>, alCerrar: () -> Unit) {
    val c = MyPump.colores
    val contexto = LocalContext.current
    val hoja = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val alcance = rememberCoroutineScope()
    fun cerrar() {
        alcance.launch { hoja.hide() }.invokeOnCompletion { alCerrar() }
    }
    ModalBottomSheet(
        onDismissRequest = alCerrar,
        sheetState = hoja,
        shape = FormaHoja,
        containerColor = c.fondo,
        tonalElevation = 0.dp,
        dragHandle = { AsaHoja() },
        modifier = Modifier.semantics { testTagsAsResourceId = true }.testTag("compras-hoja"),
    ) {
        Row(Modifier.fillMaxWidth().padding(horizontal = Espacio.m), horizontalArrangement = Arrangement.End) {
            BotonSecundario(Compras.Textos.CERRAR, alTocar = ::cerrar, compacto = true, modifier = Modifier.testTag("compras-cerrar"))
        }
        Column(
            Modifier.verticalScroll(rememberScrollState()).padding(horizontal = Espacio.m).padding(top = Espacio.xs, bottom = Espacio.xl),
            verticalArrangement = Arrangement.spacedBy(Espacio.m),
        ) {
            Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(nombre, style = MaterialTheme.typography.headlineSmall, color = c.texto, modifier = Modifier.semantics { heading() }.testTag("compras-titulo"))
                Text(Compras.Textos.SUBTITULO, style = MaterialTheme.typography.titleMedium, color = c.textoSecundario)
            }
            opciones.forEachIndexed { i, o ->
                Column(
                    Modifier.fillMaxWidth().superficieTarjeta().padding(Espacio.m).testTag("compras-opcion-$i"),
                    verticalArrangement = Arrangement.spacedBy(Espacio.xs),
                ) {
                    Column(Modifier.semantics(mergeDescendants = true) {}, verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        Text(o.producto, style = MaterialTheme.typography.titleLarge, color = c.texto)
                        Text(o.tienda, style = MaterialTheme.typography.bodyLarge, color = c.texto)
                        o.nota?.let { Text(it, style = MaterialTheme.typography.bodyMedium, color = c.textoSecundario) }
                    }
                    o.url?.let { url ->
                        BotonMarca(Compras.Textos.ABRIR_TIENDA, alTocar = { abrirEnNavegador(contexto, url) }, modifier = Modifier.testTag("compras-tienda-$i"))
                    }
                }
            }
            Text(Compras.Textos.PIE, style = MaterialTheme.typography.bodyMedium, color = c.textoSecundario, modifier = Modifier.testTag("compras-pie"))
        }
    }
}

@Composable
private fun Cabecera(titulo: String?, accion: String?) {
    Column(
        Modifier.fillMaxWidth().superficieTarjeta().padding(horizontal = Espacio.m, vertical = Espacio.s).testTag("suplementacion-cabecera"),
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        titulo?.let { Text(it, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold, modifier = Modifier.semantics { heading() }) }
        accion?.let { Text(it, style = MaterialTheme.typography.bodyMedium, color = if (titulo == null) MyPump.colores.texto else MyPump.colores.textoSecundario) }
    }
}

@Composable
private fun Momento(
    momento: SuplementacionVista.Momento,
    alAbrir: (ItemSuplemento) -> Unit,
    /** El índice del ítem si en ese renglón va «Dónde comprarlo». */
    compra: (fila: Int) -> Int? = { null },
    alComprar: (Int) -> Unit = {},
) {
    Column(verticalArrangement = Arrangement.spacedBy(Espacio.xs)) {
        Text(
            momento.titulo,
            style = MaterialTheme.typography.titleSmall,
            color = MyPump.colores.marcaTexto,
            fontWeight = FontWeight.SemiBold,
            modifier = Modifier.padding(horizontal = 4.dp).semantics { heading() },
        )
        Column(Modifier.fillMaxWidth().superficieTarjeta().testTag("momento-${momento.id}")) {
            for ((i, f) in momento.filas.withIndex()) {
                if (i > 0) Separador(sangria = Espacio.m)
                FilaDia(f) { alAbrir(f.item) }
                // Debajo de lo que ya muestra el ítem: un botón grande y con texto.
                compra(i)?.let { item ->
                    BotonSecundario(
                        Compras.Textos.BOTON,
                        alTocar = { alComprar(item) },
                        tono = MyPump.colores.marcaTexto,
                        modifier = Modifier.padding(horizontal = Espacio.m).padding(bottom = Espacio.s).testTag("compras-abrir-$item"),
                    )
                }
            }
        }
    }
}

/** Una toma del día: nombre, cantidad, etiquetas (estado, opcional, días) y la nota. Tocarla abre el detalle. */
@Composable
private fun FilaDia(f: SuplementacionVista.Fila, alTocar: () -> Unit) {
    val c = MyPump.colores
    val descripcion = SuplementacionPestana.descripcionFila(f)
    Row(
        Modifier
            .fillMaxWidth()
            .heightIn(min = 48.dp)
            .testTag("suple-${f.nombre}")
            .clearAndSetSemantics {
                contentDescription = descripcion
                role = Role.Button
                onClick(label = "ver el detalle") {
                    alTocar()
                    true
                }
            }
            .clickable(onClick = alTocar)
            .padding(horizontal = Espacio.m, vertical = Espacio.s),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(f.nombre, style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.SemiBold)
            Etiquetas(SuplementacionPestana.etiquetaEstado(f.item.estado), f.opcional, SuplementacionPestana.textoDias(f.item.dias))
            f.nota?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = c.textoSecundario) }
        }
        f.cantidad?.let {
            Spacer(Modifier.width(Espacio.s))
            Text(it, style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.SemiBold, textAlign = TextAlign.End, modifier = Modifier.widthIn(max = 140.dp))
        }
        Spacer(Modifier.width(Espacio.xs))
        Icon(Iconos.Chevron, contentDescription = null, tint = c.textoTerciario, modifier = Modifier.size(20.dp))
    }
}

@Composable
private fun FilaSale(x: SuplementacionVista.Sale, alTocar: () -> Unit) {
    val c = MyPump.colores
    val descripcion = listOfNotNull(x.nombre, x.porQue).joinToString(". ")
    Row(
        Modifier
            .fillMaxWidth()
            .heightIn(min = 48.dp)
            .testTag("sale-${x.nombre}")
            .clearAndSetSemantics {
                contentDescription = descripcion
                role = Role.Button
                onClick(label = "ver el detalle") {
                    alTocar()
                    true
                }
            }
            .clickable(onClick = alTocar)
            .padding(horizontal = Espacio.m, vertical = Espacio.s),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(x.nombre, style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.SemiBold)
            x.porQue?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = c.textoSecundario) }
        }
        Spacer(Modifier.width(Espacio.xs))
        Icon(Iconos.Chevron, contentDescription = null, tint = c.textoTerciario, modifier = Modifier.size(20.dp))
    }
}

/** El estado (Nuevo, Cambia, Sube, Baja, Vuelve) en verde, «Opcional» y los días, en chips que bajan de renglón. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun Etiquetas(estado: String?, opcional: Boolean, dias: String?, modifier: Modifier = Modifier) {
    if (estado == null && !opcional && dias == null) return
    val c = MyPump.colores
    FlowRow(modifier, horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
        estado?.let { Chip(it, tono = c.marcaTexto) }
        if (opcional) Chip("Opcional")
        dias?.let { Chip(it) }
    }
}

/** El detalle de un ítem: cuándo, cuánto, cómo tomarlo, por qué, el cambio y qué comprar. */
@OptIn(ExperimentalMaterial3Api::class, ExperimentalComposeUiApi::class)
@Composable
private fun HojaSuplemento(item: ItemSuplemento, s: Suplementacion, alCerrar: () -> Unit) {
    val c = MyPump.colores
    val d = remember(item, s) { SuplementacionPestana.detalle(item, s) }
    val hoja = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val alcance = rememberCoroutineScope()
    fun cerrar() {
        alcance.launch { hoja.hide() }.invokeOnCompletion { alCerrar() }
    }
    ModalBottomSheet(
        onDismissRequest = alCerrar,
        sheetState = hoja,
        shape = FormaHoja,
        containerColor = c.fondo,
        tonalElevation = 0.dp,
        dragHandle = { AsaHoja() },
        modifier = Modifier.semantics { testTagsAsResourceId = true }.testTag("hoja-suplemento"),
    ) {
        EncabezadoHoja(d.nombre, confirmar = AccionHoja("Listo", "listo-suplemento", alTocar = ::cerrar))
        Column(
            Modifier.verticalScroll(rememberScrollState()).padding(horizontal = Espacio.m).padding(bottom = Espacio.xl),
            verticalArrangement = Arrangement.spacedBy(Espacio.m),
        ) {
            // Arriba, como en iOS: la dosis (con la anterior si cambió), el cambio, las etiquetas y la nota.
            Column(verticalArrangement = Arrangement.spacedBy(Espacio.xs)) {
                d.dosis?.let { dosis ->
                    val hablada = d.dosisHablada ?: dosis
                    Text(
                        dosis,
                        style = MaterialTheme.typography.titleLarge,
                        fontWeight = FontWeight.SemiBold,
                        modifier = Modifier.semantics { contentDescription = hablada }.testTag("suplemento-dosis"),
                    )
                }
                d.cambio?.let { Text(it, style = MaterialTheme.typography.bodyMedium, color = c.textoSecundario) }
                if (d.sale) {
                    Chip("Dejás de tomar", tono = c.alerta)
                } else {
                    Etiquetas(d.etiqueta, d.opcional, d.dias)
                }
                d.nota?.let { Text(it, style = MaterialTheme.typography.bodyMedium, modifier = Modifier.testTag("suplemento-nota")) }
            }
            if (d.tomas.isNotEmpty()) {
                Seccion("Cuándo") {
                    Column(
                        Modifier.fillMaxWidth().superficieTarjeta().padding(horizontal = Espacio.m, vertical = Espacio.s),
                        verticalArrangement = Arrangement.spacedBy(Espacio.xs),
                    ) {
                        for (t in d.tomas) {
                            Row(verticalAlignment = Alignment.Top) {
                                Text(t.cuando, style = MaterialTheme.typography.bodyLarge, modifier = Modifier.weight(1f))
                                t.cantidad?.let {
                                    Spacer(Modifier.width(Espacio.s))
                                    Text(it, style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.SemiBold, textAlign = TextAlign.End)
                                }
                            }
                            t.nota?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = c.textoSecundario) }
                        }
                    }
                }
            }
            if (d.detalle.isNotEmpty()) {
                Seccion("Cómo tomarlo") { for (x in d.detalle) TextoConNegritas(x) }
            }
            d.porQue?.let { TextoRotulado("Por qué.", it, tonoTexto = c.texto) }
            d.comprar?.let { compra ->
                Seccion("Para comprar") {
                    // «Buscá» discreto y el producto en negrita, como en iOS; se puede seleccionar para copiarlo.
                    compra.buscar?.let { b ->
                        SelectionContainer {
                            Text(
                                buildAnnotatedString {
                                    withStyle(SpanStyle(color = c.textoSecundario)) { append("Buscá ") }
                                    withStyle(SpanStyle(color = c.texto, fontWeight = FontWeight.SemiBold)) { append(b) }
                                },
                                style = MaterialTheme.typography.bodyLarge,
                            )
                        }
                    }
                    compra.donde?.let { TextoRotulado("Dónde.", it) }
                    compra.nota?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = c.textoSecundario) }
                }
            }
        }
    }
}

@Composable
private fun Seccion(titulo: String, contenido: @Composable () -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Text(
            titulo,
            style = MaterialTheme.typography.titleSmall,
            color = MyPump.colores.marcaTexto,
            fontWeight = FontWeight.SemiBold,
            modifier = Modifier.semantics { heading() },
        )
        contenido()
    }
}

/**
 * «Protectores, indicados por Mati» (2.3.1): los fármacos que indicó Mati, aparte de los suplementos. Cada uno con su
 * cantidad y su momento; sin «Comprar», sin marcar y sin abrir el detalle. Lo usan la pestaña y «Tu guía».
 */
@Composable
fun BloqueProtectores(protectores: List<SuplementacionVista.Protector>, modifier: Modifier = Modifier, margen: Dp = Espacio.m) {
    val c = MyPump.colores
    Column(modifier) {
        for ((i, p) in protectores.withIndex()) {
            if (i > 0) Separador(sangria = margen)
            Row(
                Modifier.fillMaxWidth().heightIn(min = 48.dp).testTag("protector-${p.indice}")
                    .semantics(mergeDescendants = true) {}
                    .padding(horizontal = margen, vertical = Espacio.s),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(p.nombre, style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.SemiBold, color = c.texto)
                    p.momento?.let { Text(it, style = MaterialTheme.typography.bodyMedium, color = c.marcaTexto) }
                    p.nota?.let { Text(it, style = MaterialTheme.typography.bodyMedium, color = c.textoSecundario) }
                }
                p.cantidad?.let {
                    Text(it, style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.SemiBold, color = c.texto,
                        modifier = Modifier.padding(start = Espacio.s))
                }
            }
        }
    }
}
