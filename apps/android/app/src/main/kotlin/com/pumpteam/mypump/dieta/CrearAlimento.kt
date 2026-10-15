package com.pumpteam.mypump.dieta

import androidx.compose.animation.animateContentSize
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.semantics.testTagsAsResourceId
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.pumpteam.mypump.datos.ErrorRpc
import com.pumpteam.mypump.datos.ModeloApp
import com.pumpteam.mypump.datos.Resultado
import com.pumpteam.mypump.diseno.BotonVolver
import com.pumpteam.mypump.diseno.BotonMarca
import com.pumpteam.mypump.diseno.Espacio
import com.pumpteam.mypump.diseno.Formato
import com.pumpteam.mypump.diseno.Iconos
import com.pumpteam.mypump.diseno.MyPump
import com.pumpteam.mypump.entreno.Letras
import com.pumpteam.mypump.fotos.BotonFoto
import com.pumpteam.mypump.modelos.AlimentoPropio
import com.pumpteam.mypump.modelos.LecturaEtiqueta
import com.pumpteam.mypump.raiz.LocalAlcanceApp
import com.pumpteam.mypump.reglas.AlimentoPropioNuevo
import com.pumpteam.mypump.reglas.Formulario
import com.pumpteam.mypump.reglas.jsRound
import kotlinx.coroutines.launch

/**
 * "Alimento propio" (DIE-14, gemela de `CrearAlimentoView.swift`: `openCustomFoodModal` / `saveCustomFood` de la web).
 * Los números se piden en la base que corresponde a la unidad (por 100 g con g o ml, de 1 porción con el resto) y se
 * guardan siempre por 100 g ([AlimentoPropioNuevo]). La categoría es la del alimento que se está reemplazando.
 *
 * "Escanear etiqueta" (con cuenta: en la demo no hay IA) manda la foto a la visión (`tipo: etiqueta`) y prellena todo,
 * editable. "Crear y usar" va directo al servidor (no por la cola, como la web) y [alCrear] lo aplica como reemplazo.
 */
@OptIn(ExperimentalComposeUiApi::class)
@Composable
fun CrearAlimento(modelo: ModeloApp, categoria: String, alVolver: () -> Unit, alCrear: (AlimentoPropio) -> Unit) {
    val c = MyPump.colores
    val alcance = LocalAlcanceApp.current
    val foco = LocalFocusManager.current
    val tactil = LocalHapticFeedback.current
    var nombre by rememberSaveable { mutableStateOf("") }
    var kcal by rememberSaveable { mutableStateOf("") }
    var prot by rememberSaveable { mutableStateOf("") }
    var carb by rememberSaveable { mutableStateOf("") }
    var fat by rememberSaveable { mutableStateOf("") }
    var unidad by rememberSaveable { mutableStateOf("g") }
    var gramos by rememberSaveable { mutableStateOf("") }
    var error by rememberSaveable { mutableStateOf<String?>(null) }
    var guardando by remember { mutableStateOf(false) }
    var estadoEscaneo by rememberSaveable { mutableStateOf<String?>(null) }
    // La lectura de la etiqueta vive afuera de la composición: si el teléfono gira mientras la IA mira la foto, la respuesta
    // llega igual a este formulario (ver EsperasDieta).
    val escaneo = remember(modelo) { EsperasDieta.etiqueta(modelo) }
    val focoNombre = remember { FocusRequester() }
    val conCuenta = modelo.token != null

    // Como iOS: el nombre con el teclado listo al abrir.
    LaunchedEffect(Unit) { runCatching { focoNombre.requestFocus() } }

    /** "Escanear etiqueta": la foto a la visión (`tipo: etiqueta`). */
    fun escanear(jpeg: ByteArray) {
        foco.clearFocus()
        escaneo.escanear(modelo, alcance, jpeg)
    }

    /** Lo que leyó la visión: prellena todo editable. `porcion_g` 100 = valores por 100 g (unidad g); otra porción = "porción". */
    LaunchedEffect(escaneo.resultado) {
        val r = escaneo.resultado ?: return@LaunchedEffect
        escaneo.consumir()
        when (r) {
            is Resultado.Ok -> {
                val d = try {
                    LecturaEtiqueta.desde(r.valor.aJson())
                } catch (_: Exception) {
                    estadoEscaneo = "⚠ No pudimos leer la foto (respuesta inesperada). Cargalo a mano o probá otra foto con más luz."
                    tactil.performHapticFeedback(HapticFeedbackType.Reject)
                    return@LaunchedEffect
                }
                d.nombre?.takeIf { it.isNotEmpty() }?.let { nombre = it }
                d.kcal?.let { kcal = jsEntero(it).toString() }
                d.prot?.let { prot = Formato.decimal(it) }
                d.carb?.let { carb = Formato.decimal(it) }
                d.fat?.let { fat = Formato.decimal(it) }
                val g = d.porcionG
                if (g != null && g.isFinite() && g > 0 && jsRound(g) != 100.0) {
                    unidad = "porcion"
                    gramos = jsEntero(g).toString()
                } else {
                    unidad = "g"
                }
                error = null
                estadoEscaneo = if (d.confianza == "baja") {
                    "⚠ La etiqueta se leyó con poca claridad: revisá los valores antes de guardar."
                } else {
                    "✓ Etiqueta leída. Revisá los valores y tocá \"Crear y usar\"."
                }
                tactil.performHapticFeedback(HapticFeedbackType.Confirm)
            }
            is Resultado.Falla -> {
                val motivo = if (r.error.clase == ErrorRpc.Clase.RED) "sin conexión" else r.error.mensaje
                estadoEscaneo = "⚠ No pudimos leer la foto ($motivo). Cargalo a mano o probá otra foto con más luz."
                tactil.performHapticFeedback(HapticFeedbackType.Reject)
            }
        }
    }

    fun crear() {
        foco.clearFocus()
        val leer = AlimentoPropioNuevo::leerNumero
        val f = AlimentoPropioNuevo.preparar(nombre, leer(kcal), leer(prot), leer(carb), leer(fat), unidad, leer(gramos), categoria)
        when (f) {
            is Formulario.Invalido -> {
                error = f.mensaje
                tactil.performHapticFeedback(HapticFeedbackType.Reject)
            }
            is Formulario.Valido -> {
                error = null
                guardando = true
                alcance.launch {
                    val r = modelo.crearAlimentoPropio(f.datos)
                    guardando = false
                    when (r) {
                        is Resultado.Ok -> alCrear(r.valor)
                        is Resultado.Falla -> {
                            error = if (r.error.clase == ErrorRpc.Clase.RED) {
                                "Sin conexión: probá de nuevo cuando tengas señal."
                            } else {
                                "No se pudo crear el alimento. Probá de nuevo."
                            }
                            tactil.performHapticFeedback(HapticFeedbackType.Reject)
                        }
                    }
                }
            }
        }
    }

    Box(Modifier.semantics { testTagsAsResourceId = true }.testTag("crear-alimento-formulario")) {
        Column {
            Row(Modifier.fillMaxWidth().padding(start = Espacio.xxs, end = Espacio.m), verticalAlignment = Alignment.CenterVertically) {
                BotonVolver(
                    alVolver,
                    Modifier.padding(start = Espacio.xxs, end = Espacio.xs),
                    descripcion = "Volver a Reemplazar",
                    etiqueta = "volver-a-reemplazos",
                    habilitado = !guardando,
                )
                Text("Alimento propio", style = MaterialTheme.typography.titleLarge, modifier = Modifier.weight(1f).semantics { heading() })
            }
            Column(
                Modifier
                    .weight(1f, fill = false)
                    .verticalScroll(rememberScrollState())
                    .padding(horizontal = Espacio.m)
                    .padding(top = Espacio.xs, bottom = Espacio.s)
                    .animateContentSize(),
                verticalArrangement = Arrangement.spacedBy(Espacio.l),
            ) {
                if (conCuenta) {
                    SeccionFormulario(titulo = null, pie = "Después podés corregir cualquier valor.") {
                        BotonFoto(
                            clave = "etiqueta",
                            maxPx = 1600,
                            calidad = 0.85,
                            alElegir = ::escanear,
                            habilitado = !escaneo.escaneando && !guardando,
                            modifier = Modifier.fillMaxWidth(),
                        ) {
                            Row(
                                Modifier.fillMaxWidth().heightIn(min = 60.dp).padding(horizontal = Espacio.m, vertical = 10.dp).testTag("escanear-etiqueta"),
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(Espacio.s),
                            ) {
                                Icon(IconosDieta.Escanear, contentDescription = null, tint = c.marcaTexto, modifier = Modifier.size(26.dp))
                                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                                    Text("Escanear etiqueta", style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.SemiBold)
                                    Text("Sacale una foto a la tabla nutricional y se completa solo", style = Letras.caption, color = c.textoSecundario)
                                }
                            }
                        }
                        estadoEscaneo?.let {
                            SeparadorFila()
                            Text(
                                it,
                                style = MaterialTheme.typography.bodySmall,
                                color = c.textoSecundario,
                                modifier = Modifier.padding(horizontal = Espacio.m, vertical = 10.dp).testTag("estado-escaneo"),
                            )
                        }
                    }
                }
                SeccionFormulario("Nombre") {
                    FilaTexto(
                        nombre,
                        alCambiar = { nombre = it },
                        ejemplo = "Ej: Pan integral marca X",
                        etiqueta = "nombre-alimento",
                        descripcion = "Nombre",
                        foco = focoNombre,
                    )
                }
                SeccionFormulario(
                    "Cómo lo medís",
                    pie = if (AlimentoPropioNuevo.porUnidad(unidad)) {
                        "Cuánto pesa 1 ${AlimentoPropioNuevo.texto(unidad)} en gramos (sirve para la medida casera)."
                    } else {
                        null
                    },
                ) {
                    SelectorUnidad(unidad, alElegir = { unidad = it })
                    if (AlimentoPropioNuevo.porUnidad(unidad)) {
                        SeparadorFila()
                        FilaNumero(
                            "Gramos por ${AlimentoPropioNuevo.texto(unidad)}",
                            gramos,
                            alCambiar = { gramos = it },
                            unidad = "g",
                            etiqueta = "gramos-por-unidad",
                        )
                    }
                }
                SeccionFormulario(
                    "Valores",
                    pie = AlimentoPropioNuevo.base(unidad, AlimentoPropioNuevo.leerNumero(gramos)) +
                        " Si no sabés las calorías, se calculan con los macros.",
                ) {
                    FilaNumero("Calorías", kcal, alCambiar = { kcal = it }, unidad = "kcal", etiqueta = "kcal-alimento")
                    SeparadorFila()
                    FilaNumero("Proteínas", prot, alCambiar = { prot = it }, unidad = "g", etiqueta = "prot-alimento")
                    SeparadorFila()
                    FilaNumero("Carbohidratos", carb, alCambiar = { carb = it }, unidad = "g", etiqueta = "carb-alimento")
                    SeparadorFila()
                    FilaNumero("Grasas", fat, alCambiar = { fat = it }, unidad = "g", etiqueta = "fat-alimento")
                }
                error?.let { ErrorFormulario(it, etiqueta = "error-alimento") }
            }
            Box(Modifier.fillMaxWidth().padding(horizontal = Espacio.m).padding(top = Espacio.xs, bottom = Espacio.m)) {
                BotonMarca(
                    "Crear y usar",
                    alTocar = ::crear,
                    habilitado = nombre.isNotBlank() && !escaneo.escaneando,
                    cargando = guardando,
                    modifier = Modifier.testTag("crear-y-usar"),
                )
            }
        }
        if (escaneo.escaneando) AnalizandoFoto("Leyendo la etiqueta…", Modifier.matchParentSize())
    }
}

/** La unidad (el `Picker` de iOS): un menú con las siete de la web, en su orden. */
@Composable
private fun SelectorUnidad(unidad: String, alElegir: (String) -> Unit) {
    val c = MyPump.colores
    var abierto by remember { mutableStateOf(false) }
    val texto = AlimentoPropioNuevo.unidades.firstOrNull { it.first == unidad }?.second ?: unidad
    Box {
        Row(
            Modifier
                .fillMaxWidth()
                .clickable(role = Role.DropdownList, onClickLabel = "elegir la unidad") { abierto = true }
                .heightIn(min = 48.dp)
                .padding(horizontal = Espacio.m)
                .semantics(mergeDescendants = true) {
                    contentDescription = "Unidad"
                    stateDescription = texto
                }
                .testTag("unidad"),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text("Unidad", style = MaterialTheme.typography.bodyLarge, modifier = Modifier.weight(1f))
            Text(texto, style = MaterialTheme.typography.bodyLarge, color = c.marcaTexto)
            Icon(Iconos.ArribaAbajo, contentDescription = null, tint = c.marcaTexto, modifier = Modifier.padding(start = 4.dp).size(16.dp))
        }
        DropdownMenu(expanded = abierto, onDismissRequest = { abierto = false }, modifier = Modifier.semantics { testTagsAsResourceId = true }) {
            for ((valor, nombre) in AlimentoPropioNuevo.unidades) {
                DropdownMenuItem(
                    text = { Text(nombre, fontWeight = if (valor == unidad) FontWeight.SemiBold else FontWeight.Normal) },
                    onClick = {
                        alElegir(valor)
                        abierto = false
                    },
                    leadingIcon = {
                        if (valor == unidad) Icon(Iconos.Verificado, contentDescription = null, tint = c.marcaTexto, modifier = Modifier.size(18.dp))
                    },
                    modifier = Modifier.testTag("unidad-$valor"),
                )
            }
        }
    }
}
