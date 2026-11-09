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
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.semantics.testTagsAsResourceId
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.pumpteam.mypump.datos.ClienteRpc
import com.pumpteam.mypump.datos.ErrorRpc
import com.pumpteam.mypump.datos.ModeloApp
import com.pumpteam.mypump.datos.Resultado
import com.pumpteam.mypump.diseno.BotonMarca
import com.pumpteam.mypump.diseno.BotonSecundario
import com.pumpteam.mypump.diseno.BotonVolver
import com.pumpteam.mypump.diseno.EncabezadoHoja
import com.pumpteam.mypump.diseno.Espacio
import com.pumpteam.mypump.diseno.FormaMenu
import com.pumpteam.mypump.diseno.Formato
import com.pumpteam.mypump.diseno.Iconos
import com.pumpteam.mypump.diseno.MyPump
import com.pumpteam.mypump.entreno.Letras
import com.pumpteam.mypump.fotos.BotonFoto
import com.pumpteam.mypump.modelos.AlimentoPropio
import com.pumpteam.mypump.modelos.LecturaEtiqueta
import com.pumpteam.mypump.raiz.LocalAlcanceApp
import com.pumpteam.mypump.reglas.AlimentoPropioNuevo
import com.pumpteam.mypump.reglas.CodigoBarras
import com.pumpteam.mypump.reglas.Formulario
import java.util.UUID
import kotlinx.coroutines.launch

/**
 * "Alimento propio" (DIE-14, gemela de `CrearAlimentoView.swift`: `openCustomFoodModal` / `saveCustomFood` de la web).
 * Los números se piden en la base que corresponde a la unidad (por 100 g con g o ml, de 1 porción con el resto) y se
 * guardan siempre por 100 g ([AlimentoPropioNuevo]). La categoría es la del alimento que se está reemplazando.
 *
 * "Escanear etiqueta" (con cuenta: en la demo no hay IA) manda la foto a la visión (`tipo: etiqueta`) y prellena todo,
 * editable. "Crear y usar" va directo al servidor (no por la cola, como la web) y [alCrear] lo aplica como reemplazo.
 */
/**
 * Lo que llega de un código de barras que Open Food Facts no tenía o tenía incompleto (2.1, S3): el código (se muestra y queda
 * asociado al alimento en el teléfono), lo que se pudo leer y si abre directo la foto de la etiqueta.
 */
data class PrecargaCodigo(val codigo: String, val parcial: CodigoBarras.Parcial?, val escanearEtiqueta: Boolean)

@OptIn(ExperimentalComposeUiApi::class)
@Composable
fun CrearAlimento(
    modelo: ModeloApp,
    categoria: String,
    alVolver: () -> Unit,
    alCrear: (AlimentoPropio) -> Unit,
    precarga: PrecargaCodigo? = null,
    volverDescripcion: String = "Volver a Reemplazar",
) {
    val c = MyPump.colores
    val alcance = LocalAlcanceApp.current
    val foco = LocalFocusManager.current
    val tactil = LocalHapticFeedback.current
    // Con un código incompleto, arranca con lo que se pudo leer (por 100 g, todo editable).
    val parcial = precarga?.parcial
    var nombre by rememberSaveable { mutableStateOf(parcial?.nombre ?: "") }
    var kcal by rememberSaveable { mutableStateOf(parcial?.kcal?.let { jsEntero(it).toString() } ?: "") }
    var prot by rememberSaveable { mutableStateOf(parcial?.p?.let { Formato.decimal(it) } ?: "") }
    var carb by rememberSaveable { mutableStateOf(parcial?.c?.let { Formato.decimal(it) } ?: "") }
    var fat by rememberSaveable { mutableStateOf(parcial?.g?.let { Formato.decimal(it) } ?: "") }
    var unidad by rememberSaveable { mutableStateOf("g") }
    var gramos by rememberSaveable { mutableStateOf("") }
    var error by rememberSaveable { mutableStateOf<String?>(null) }
    var guardando by remember { mutableStateOf(false) }
    var estadoEscaneo by rememberSaveable { mutableStateOf<String?>(null) }
    // La etiqueta no dijo cuánto pesa la porción: se pregunta si los números son por 100 g o de 1 porción (6-nov).
    var preguntaBase by rememberSaveable { mutableStateOf(false) }
    // La lectura de la etiqueta vive afuera de la composición: si el teléfono gira mientras la IA mira la foto, la respuesta
    // llega igual a este formulario (ver EsperasDieta).
    val escaneo = remember(modelo) { EsperasDieta.etiqueta(modelo) }
    // De quién es la lectura (`rememberSaveable`: el mismo formulario al girar). Un formulario nuevo no hereda la de otro.
    val dueno = rememberSaveable { UUID.randomUUID().toString() }
    val escaneando = escaneo.escaneando(dueno)
    val resultadoEscaneo = escaneo.resultado(dueno)
    val focoNombre = remember { FocusRequester() }
    val conCuenta = modelo.token != null

    // Como iOS: el nombre con el teclado listo al abrir (no con la foto de la etiqueta abriéndose).
    LaunchedEffect(Unit) { if (precarga?.escanearEtiqueta != true) runCatching { focoNombre.requestFocus() } }

    /** "Escanear etiqueta": la foto a la visión (`tipo: etiqueta`). */
    fun escanear(jpeg: ByteArray) {
        foco.clearFocus()
        escaneo.escanear(dueno, alcance) { modelo.analizarFoto(jpeg, ClienteRpc.TipoVision.ETIQUETA) }
    }

    /**
     * Lo que leyó la visión: prellena todo editable y dice en qué base quedó. Porción con gramos = "porción" con sus
     * gramos; 100 g = unidad g; sin gramos de la porción se pregunta (antes se asumía 100 g).
     */
    LaunchedEffect(resultadoEscaneo) {
        val r = resultadoEscaneo ?: return@LaunchedEffect
        escaneo.consumir(dueno)
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
                val base = AlimentoPropioNuevo.baseLectura(d.porcionG, d.base)
                when (base) {
                    is AlimentoPropioNuevo.BaseLectura.Porcion -> {
                        unidad = "porcion"
                        gramos = jsEntero(base.gramos).toString()
                        preguntaBase = false
                    }
                    AlimentoPropioNuevo.BaseLectura.Cien -> {
                        unidad = "g"
                        preguntaBase = false
                    }
                    AlimentoPropioNuevo.BaseLectura.Desconocida -> {
                        unidad = "g"
                        gramos = ""
                        // Sin ningún número (no se leyó la tabla) no hay nada que ubicar: se carga a mano.
                        preguntaBase = listOf(d.kcal, d.prot, d.carb, d.fat).any { it != null }
                    }
                }
                error = null
                estadoEscaneo = AlimentoPropioNuevo.textoLectura(base, d.confianza == "baja", d.avisos)
                tactil.performHapticFeedback(HapticFeedbackType.Confirm)
            }
            is Resultado.Falla -> {
                val motivo = if (r.error.clase == ErrorRpc.Clase.RED) "sin conexión" else r.error.mensaje
                estadoEscaneo = "⚠ No pudimos leer la foto ($motivo). Cargalo a mano o probá otra foto con más luz."
                tactil.performHapticFeedback(HapticFeedbackType.Reject)
            }
        }
    }

    /** La respuesta a «¿por 100 g o de 1 porción?». De 1 porción pide los gramos (la etiqueta no los dijo). */
    fun elegirBase(porcion: Boolean) {
        preguntaBase = false
        error = null
        unidad = if (porcion) "porcion" else "g"
        estadoEscaneo = if (porcion) {
            "Poné cuánto pesa 1 porción en gramos y revisá los valores."
        } else {
            "✓ Quedaron como valores por 100 g. Revisalos y tocá \"Crear y usar\"."
        }
    }

    fun crear() {
        foco.clearFocus()
        if (preguntaBase) {
            error = "Antes de guardar, elegí si los valores son por 100 g o de 1 porción."
            tactil.performHapticFeedback(HapticFeedbackType.Reject)
            return
        }
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
            EncabezadoHoja(
                "Alimento propio",
                izquierda = {
                    BotonVolver(alVolver, descripcion = volverDescripcion, etiqueta = "volver-a-reemplazos", habilitado = !guardando)
                },
            )
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
                            habilitado = !escaneando && !guardando,
                            abrirAlAparecer = precarga?.escanearEtiqueta == true,
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
                        if (preguntaBase) {
                            Row(
                                Modifier.fillMaxWidth().padding(horizontal = Espacio.m).padding(bottom = 10.dp),
                                horizontalArrangement = Arrangement.spacedBy(Espacio.s),
                            ) {
                                BotonSecundario(
                                    "Por 100 g",
                                    alTocar = { elegirBase(porcion = false) },
                                    modifier = Modifier.weight(1f).testTag("base-100"),
                                    compacto = true,
                                )
                                BotonSecundario(
                                    "De 1 porción",
                                    alTocar = { elegirBase(porcion = true) },
                                    modifier = Modifier.weight(1f).testTag("base-porcion"),
                                    compacto = true,
                                )
                            }
                        }
                    }
                }
                precarga?.let { p ->
                    SeccionFormulario(titulo = null, pie = "Queda guardado en este teléfono: la próxima vez que lo escanees, aparece tu alimento.") {
                        Row(
                            Modifier
                                .fillMaxWidth()
                                .heightIn(min = 48.dp)
                                .padding(horizontal = Espacio.m)
                                .semantics(mergeDescendants = true) {}
                                .testTag("crear-codigo"),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(Espacio.s),
                        ) {
                            Icon(IconosDieta.CodigoBarras, contentDescription = null, tint = c.marcaTexto, modifier = Modifier.size(20.dp))
                            Text("Código de barras", style = MaterialTheme.typography.bodyLarge, modifier = Modifier.weight(1f))
                            Text(p.codigo, style = MaterialTheme.typography.bodyLarge.copy(fontFeatureSettings = "tnum"), color = c.textoSecundario)
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
                    SelectorUnidad(unidad, alElegir = {
                        unidad = it
                        preguntaBase = false
                    })
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
                // No frena el guardado: un polvo de proteína con menos de 300 kcal por 100 g (casi seguro, el scoop como 100 g).
                val leerAviso = AlimentoPropioNuevo::leerNumero
                AlimentoPropioNuevo.avisoPolvoProteina(
                    nombre, leerAviso(kcal), leerAviso(prot), leerAviso(carb), leerAviso(fat), unidad, leerAviso(gramos),
                )?.let { aviso ->
                    Row(
                        Modifier.fillMaxWidth().padding(horizontal = Espacio.m).semantics(mergeDescendants = true) {}
                            .testTag("aviso-polvo"),
                        horizontalArrangement = Arrangement.spacedBy(Espacio.s),
                    ) {
                        Icon(Iconos.Alerta, contentDescription = null, tint = c.alerta, modifier = Modifier.size(18.dp))
                        Text(aviso, style = MaterialTheme.typography.bodySmall, color = c.alerta)
                    }
                }
                error?.let { ErrorFormulario(it, etiqueta = "error-alimento") }
            }
            Box(Modifier.fillMaxWidth().padding(horizontal = Espacio.m).padding(top = Espacio.xs, bottom = Espacio.m)) {
                BotonMarca(
                    "Crear y usar",
                    alTocar = ::crear,
                    habilitado = nombre.isNotBlank() && !escaneando,
                    cargando = guardando,
                    modifier = Modifier.testTag("crear-y-usar"),
                )
            }
        }
        if (escaneando) AnalizandoFoto("Leyendo la etiqueta…", Modifier.matchParentSize())
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
        DropdownMenu(expanded = abierto, onDismissRequest = { abierto = false }, shape = FormaMenu, containerColor = MyPump.colores.tarjeta, shadowElevation = 12.dp, modifier = Modifier.semantics { testTagsAsResourceId = true }) {
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
