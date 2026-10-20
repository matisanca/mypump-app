package com.pumpteam.mypump.entreno

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
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
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTagsAsResourceId
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import com.pumpteam.mypump.datos.ModeloEntreno
import com.pumpteam.mypump.diseno.AccionHoja
import com.pumpteam.mypump.diseno.AsaHoja
import com.pumpteam.mypump.diseno.EncabezadoHoja
import com.pumpteam.mypump.diseno.Espacio
import com.pumpteam.mypump.diseno.FormaHoja
import com.pumpteam.mypump.diseno.Iconos
import com.pumpteam.mypump.diseno.Interruptor
import com.pumpteam.mypump.diseno.MyPump
import com.pumpteam.mypump.diseno.Radio
import com.pumpteam.mypump.diseno.Separador
import com.pumpteam.mypump.diseno.superficieTarjeta
import com.pumpteam.mypump.raiz.LocalAlcanceApp
import com.pumpteam.mypump.reglas.Js
import com.pumpteam.mypump.reglas.SustitucionEjercicios
import com.pumpteam.mypump.reglas.SustitucionesEntreno
import com.pumpteam.mypump.reglas.SustitutoEjercicio
import kotlinx.coroutines.launch

/**
 * Sustituir un ejercicio (SER-11/13, SustituirEjercicioView.swift): variantes del mismo gesto y músculo (otro equipo
 * primero, hasta 30), búsqueda y "Fijar para las próximas semanas" (sin fijar vale solo por hoy). Si ya estaba
 * sustituido, "Volver a …". La hoja se cierra ya: el cambio se aplica en el acto y el historial del sustituto llega después
 * (esperarlo la dejaba abierta hasta 20 s con mala señal, revisión del 14-oct, hallazgo 14).
 */
@OptIn(ExperimentalMaterial3Api::class, ExperimentalComposeUiApi::class)
@Composable
fun HojaSustituir(motor: ModeloEntreno, v: VistaEntreno, lugar: String, alCerrar: () -> Unit) {
    val c = MyPump.colores
    val hoja = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val alcanceHoja = rememberCoroutineScope()
    val alcance = LocalAlcanceApp.current
    val foco = LocalFocusManager.current
    var busqueda by rememberSaveable(lugar) { mutableStateOf("") }
    // El elegido por su clave, no por su posición: si con la hoja abierta llega el catálogo del servidor, la lista cambia de
    // orden y la misma posición era otro ejercicio (revisión del 15-oct, hallazgo 13). La clave sobrevive a rotar; el que se
    // tocó queda por si ya no está en la lista de ahora.
    var elegido by rememberSaveable(lugar) { mutableStateOf<String?>(null) }
    var tocado by remember(lugar) { mutableStateOf<SustitutoEjercicio?>(null) }
    // Arranca como estaba la sustitución previa: al cambiar de sustituto no se pierde que estaba fijada.
    var fijar by rememberSaveable(lugar) { mutableStateOf(motor.fijadaAntes(lugar)) }
    val plan = v.dia.ejercicio(lugar)
    val ef = plan?.let { motor.efectivo(it) }
    val original = NombreEjercicio(ef?.nombreOriginal ?: plan?.nombre ?: "").principal
    val todos = remember(v, lugar) { motor.sustitutos(lugar) }
    val opciones = remember(v, lugar, busqueda) { motor.sustitutos(lugar, busqueda) }
    // Debajo, los otros ejercicios del mismo músculo (Mati, 20-oct: con la polea ocupada no quedaba nada).
    val todosOtros = remember(v, lugar) { motor.otrosDelMismoMusculo(lugar) }
    val otros = remember(v, lugar, busqueda) { SustitucionesEntreno.filtrar(todosOtros, busqueda) }
    val musculo = SustitucionEjercicios.musculo(todosOtros.firstOrNull()?.musculo)

    fun cerrar() {
        foco.clearFocus()
        alcanceHoja.launch { hoja.hide() }.invokeOnCompletion { alCerrar() }
    }

    fun sustituir() {
        val clave = elegido ?: return
        // El mismo, con lo que tenga el catálogo de ahora; si ya no está entre los sustitutos, el que se tocó.
        val s = motor.sustituto(lugar, clave) ?: tocado?.takeIf { it.clave == clave } ?: return
        val fijada = fijar
        cerrar()
        alcance.launch { motor.sustituir(lugar, s, fijada) }
    }

    ModalBottomSheet(
        onDismissRequest = alCerrar,
        sheetState = hoja,
        shape = FormaHoja,
        containerColor = c.fondo,
        tonalElevation = 0.dp,
        dragHandle = { AsaHoja() },
        modifier = Modifier.semantics { testTagsAsResourceId = true }.testTag("hoja-sustituir"),
    ) {
        EncabezadoHoja("Sustituir ejercicio", cancelar = AccionHoja("Cancelar", "cancelar-sustitucion", alTocar = ::cerrar))
        // La búsqueda (el `.searchable` de iOS).
        BasicTextField(
            value = busqueda,
            onValueChange = { busqueda = it },
            singleLine = true,
            textStyle = MaterialTheme.typography.bodyLarge.copy(color = c.texto),
            cursorBrush = SolidColor(c.marcaTexto),
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = Espacio.m, vertical = Espacio.xs)
                .semantics { contentDescription = "Buscar ejercicio" }
                .testTag("buscar-variante"),
            decorationBox = { campo ->
                Row(
                    Modifier
                        .fillMaxWidth()
                        .heightIn(min = 44.dp)
                        .clip(RoundedCornerShape(Radio.control))
                        .background(c.campo)
                        .padding(horizontal = Espacio.s),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(Espacio.xs),
                ) {
                    Icon(Iconos.Buscar, contentDescription = null, tint = c.textoSecundario, modifier = Modifier.size(20.dp))
                    Box(Modifier.weight(1f)) {
                        if (busqueda.isEmpty()) {
                            Text("Buscar ejercicio", style = MaterialTheme.typography.bodyLarge, color = c.textoTerciario, modifier = Modifier.clearAndSetSemantics {})
                        }
                        campo()
                    }
                }
            },
        )
        LazyColumn(
            modifier = Modifier.weight(1f, fill = false),
            contentPadding = PaddingValues(start = Espacio.m, end = Espacio.m, top = Espacio.xs, bottom = Espacio.s),
            verticalArrangement = Arrangement.spacedBy(Espacio.s),
        ) {
            item(key = "original") {
                Column(Modifier.fillMaxWidth().superficieTarjeta(radio = Radio.control + 4.dp)) {
                    Column(Modifier.padding(Espacio.m).semantics(mergeDescendants = true) {}, verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        Text(original, style = MaterialTheme.typography.titleMedium)
                        Text(
                            if (todosOtros.isEmpty()) "Mismo gesto · otra variante"
                            else "Otra variante u otro ejercicio ${musculo?.let { "de $it" } ?: "del mismo músculo"}",
                            style = Letras.subtitulo,
                            color = c.textoSecundario,
                        )
                    }
                    if (ef?.sustituido == true) {
                        Separador(sangria = Espacio.m)
                        Row(
                            Modifier
                                .fillMaxWidth()
                                .clickable {
                                    alcance.launch { motor.revertirSustitucion(lugar) }
                                    cerrar()
                                }
                                .padding(Espacio.m)
                                .testTag("volver-al-original"),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(Espacio.s),
                        ) {
                            Icon(Iconos.Deshacer, contentDescription = null, tint = c.marcaTexto, modifier = Modifier.size(20.dp))
                            Text("Volver a $original", style = MaterialTheme.typography.bodyLarge, color = c.marcaTexto)
                        }
                    }
                }
            }
            item(key = "encabezado") {
                Row(Modifier.fillMaxWidth().padding(start = 4.dp, end = 4.dp, top = Espacio.xs), verticalAlignment = Alignment.CenterVertically) {
                    Ceja("Variantes del mismo movimiento", Modifier.weight(1f))
                    Text("${opciones.size}/${todos.size}", style = Letras.caption.merge(Letras.cifras), color = c.textoSecundario)
                }
            }
            if (opciones.isEmpty()) {
                item(key = "vacio") {
                    Text(
                        if (busqueda.isEmpty()) "No hay variantes equivalentes." else "Sin resultados para “$busqueda”.",
                        style = Letras.subtitulo,
                        color = c.textoSecundario,
                        modifier = Modifier.padding(horizontal = 4.dp).testTag("sin-variantes"),
                    )
                }
            }
            itemsIndexed(opciones, key = { _, s -> "${s.slug}|${s.nombre}|${s.equipo}" }) { _, s ->
                FilaSustituto(s, elegida = s.clave == elegido, etiqueta = "variante") {
                    elegido = s.clave
                    tocado = s
                }
            }
            if (otros.isNotEmpty()) {
                item(key = "encabezado-otros") {
                    Row(Modifier.fillMaxWidth().padding(start = 4.dp, end = 4.dp, top = Espacio.s), verticalAlignment = Alignment.CenterVertically) {
                        Ceja(musculo?.let { "Otros ejercicios de $it" } ?: "Otros ejercicios del mismo músculo", Modifier.weight(1f).testTag("titulo-otros"))
                        Text("${otros.size}/${todosOtros.size}", style = Letras.caption.merge(Letras.cifras), color = c.textoSecundario)
                    }
                }
                itemsIndexed(otros, key = { _, s -> "otro|${s.slug}|${s.nombre}|${s.equipo}" }) { _, s ->
                    FilaSustituto(s, elegida = s.clave == elegido, etiqueta = "otro-ejercicio") {
                        elegido = s.clave
                        tocado = s
                    }
                }
                item(key = "pie-otros") {
                    Text(
                        "Otro movimiento para el mismo músculo, por si lo del plan está ocupado.",
                        style = Letras.caption,
                        color = c.textoSecundario,
                        modifier = Modifier.padding(horizontal = 4.dp),
                    )
                }
            }
        }
        // Abajo, siempre a mano: fijar (sin tildar vale solo por hoy) y sustituir.
        Column(
            Modifier.fillMaxWidth().padding(horizontal = Espacio.m).padding(top = Espacio.xs, bottom = Espacio.m),
            verticalArrangement = Arrangement.spacedBy(Espacio.s),
        ) {
            Row(
                Modifier.fillMaxWidth().superficieTarjeta(radio = Radio.control + 4.dp).padding(horizontal = Espacio.m, vertical = Espacio.xs),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(Espacio.s),
            ) {
                Icon(Iconos.Candado, contentDescription = null, tint = c.marcaTexto, modifier = Modifier.size(20.dp))
                Text("Fijar para las próximas semanas", style = MaterialTheme.typography.bodyLarge, modifier = Modifier.weight(1f))
                Interruptor(
                    fijar,
                    alCambiar = { fijar = it },
                    color = c.marcaVivo,
                    modifier = Modifier.semantics { contentDescription = "Fijar para las próximas semanas" }.testTag("fijar"),
                )
            }
            Text(
                "Si no lo fijás, vale solo por hoy: la próxima sesión vuelve “$original”.",
                style = Letras.caption,
                color = c.textoSecundario,
                modifier = Modifier.padding(horizontal = 4.dp),
            )
            BotonConIcono(
                "Sustituir",
                Iconos.Intercambio,
                habilitado = elegido != null,
                alTocar = ::sustituir,
                modifier = Modifier.testTag("confirmar-sustitucion"),
            )
        }
    }
}

/** Un ejercicio para elegir en «Sustituir»: la foto, el nombre, el equipo y la marca de elegido. */
@Composable
private fun FilaSustituto(s: SustitutoEjercicio, elegida: Boolean, etiqueta: String, alTocar: () -> Unit) {
    val c = MyPump.colores
    Row(
        Modifier
            .fillMaxWidth()
            .superficieTarjeta(radio = Radio.control + 4.dp)
            .clickable(onClick = alTocar)
            .padding(horizontal = Espacio.s, vertical = 10.dp)
            .semantics { selected = elegida }
            .testTag(etiqueta),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(Espacio.s),
    ) {
        Miniatura(s.imagenes.concentric ?: s.imagenes.eccentric, null, 48.dp)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(s.nombre, style = MaterialTheme.typography.bodyLarge, color = c.texto)
            Text(s.equipo, style = Letras.caption, color = c.textoSecundario)
        }
        Icon(
            if (elegida) Iconos.TildeEnCirculo else Iconos.Circulo,
            contentDescription = null,
            tint = if (elegida) c.marcaVivo else c.textoTerciario,
            modifier = Modifier.size(24.dp),
        )
    }
}

/**
 * "Cerrar sesión de hoy" (SES-06, CerrarDiaView.swift): el resumen (series, reps, volumen y minutos), lo que queda sin
 * completar si se cierra antes, y las notas para Mati. El motor vacía la cola antes de cerrar; si no se pudo, lo dice.
 */
@OptIn(ExperimentalMaterial3Api::class, ExperimentalComposeUiApi::class)
@Composable
fun HojaCerrarDia(motor: ModeloEntreno, v: VistaEntreno, alCerrar: () -> Unit) {
    val c = MyPump.colores
    val hoja = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val alcanceHoja = rememberCoroutineScope()
    val alcance = LocalAlcanceApp.current
    val foco = LocalFocusManager.current
    val haptico = LocalHapticFeedback.current
    var notas by rememberSaveable { mutableStateOf("") }
    var enviando by remember { mutableStateOf(false) }
    var aviso by remember { mutableStateOf<String?>(null) }
    val r = remember(v) { motor.resumen }
    val anticipado = !motor.todoHecho

    fun cerrar() {
        foco.clearFocus()
        alcanceHoja.launch { hoja.hide() }.invokeOnCompletion { alCerrar() }
    }

    fun confirmar() {
        foco.clearFocus()
        enviando = true
        aviso = null
        alcance.launch {
            val resultado = motor.cerrarDia(notas)
            enviando = false
            val a = resultado.aviso
            if (a != null) {
                aviso = a
            } else {
                haptico.performHapticFeedback(HapticFeedbackType.Confirm)
                cerrar()
            }
        }
    }

    ModalBottomSheet(
        onDismissRequest = { if (!enviando) alCerrar() },
        sheetState = hoja,
        shape = FormaHoja,
        containerColor = c.fondo,
        tonalElevation = 0.dp,
        dragHandle = { AsaHoja() },
        modifier = Modifier.semantics { testTagsAsResourceId = true }.testTag("hoja-cerrar-dia"),
    ) {
        EncabezadoHoja("Cerrar sesión de hoy", cancelar = AccionHoja("Cancelar", "cancelar-cierre", habilitada = !enviando, alTocar = ::cerrar))
        Column(
            Modifier.verticalScroll(rememberScrollState()).padding(Espacio.m),
            verticalArrangement = Arrangement.spacedBy(Espacio.l),
        ) {
            Row(Modifier.fillMaxWidth().superficieTarjeta().padding(14.dp).testTag("resumen-cierre"), verticalAlignment = Alignment.CenterVertically) {
                CeldaResumen("Series", "${r.series}", Modifier.weight(1f))
                SeparadorVertical()
                CeldaResumen("Reps", Js.texto(r.reps), Modifier.weight(1f))
                SeparadorVertical()
                CeldaResumen("Volumen", "${Js.texto(r.volumenRedondeado)} kg", Modifier.weight(1f))
                SeparadorVertical()
                CeldaResumen("Tiempo", motor.minutos?.let { "$it min" } ?: "—", Modifier.weight(1f))
            }
            v.dia.avisoPendientes?.let { titulo ->
                Column(
                    Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(Radio.control + 4.dp))
                        .background(c.alerta.copy(alpha = 0.12f))
                        .padding(Espacio.m)
                        .testTag("pendientes-cierre"),
                    verticalArrangement = Arrangement.spacedBy(Espacio.xs),
                ) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        Icon(Iconos.Error, contentDescription = null, tint = c.alerta, modifier = Modifier.size(18.dp))
                        Text(titulo, style = Letras.subtitulo.copy(fontWeight = FontWeight.SemiBold))
                    }
                    for (p in v.dia.pendientes) Text("· ${NombreEjercicio(p).principal}", style = Letras.subtitulo, color = c.textoSecundario)
                }
            }
            Column(verticalArrangement = Arrangement.spacedBy(Espacio.xs)) {
                Text(
                    buildAnnotatedString {
                        append("Notas de la sesión ")
                        withStyle(SpanStyle(color = c.textoTerciario)) { append("· opcional") }
                    },
                    style = Letras.subtitulo.copy(fontWeight = FontWeight.SemiBold),
                    color = c.textoSecundario,
                )
                BasicTextField(
                    value = notas,
                    onValueChange = { notas = it },
                    minLines = 3,
                    maxLines = 6,
                    textStyle = MaterialTheme.typography.bodyLarge.copy(color = c.texto),
                    cursorBrush = SolidColor(c.marcaTexto),
                    modifier = Modifier.fillMaxWidth().semantics { contentDescription = "Notas de la sesión" }.testTag("notas-sesion"),
                    decorationBox = { campo ->
                        Box(
                            Modifier
                                .fillMaxWidth()
                                .clip(RoundedCornerShape(Radio.control))
                                .background(c.campo)
                                .padding(horizontal = 14.dp, vertical = 12.dp),
                        ) {
                            if (notas.isEmpty()) {
                                Text(
                                    if (anticipado) "ej: poco tiempo hoy, saltó press de banca…" else "ej: molestia leve hombro derecho, jalón se sintió pesado…",
                                    style = MaterialTheme.typography.bodyLarge,
                                    color = c.textoTerciario,
                                    modifier = Modifier.clearAndSetSemantics {},
                                )
                            }
                            campo()
                        }
                    },
                )
            }
            aviso?.let {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp), modifier = Modifier.testTag("aviso-cierre")) {
                    Icon(Iconos.SinWifi, contentDescription = null, tint = c.peligro, modifier = Modifier.size(18.dp))
                    Text(it, style = Letras.subtitulo, color = c.texto)
                }
            }
            BotonConIcono("Confirmar y cerrar", Iconos.Bandera, alTocar = ::confirmar, cargando = enviando, modifier = Modifier.testTag("confirmar-cierre"))
        }
    }
}
