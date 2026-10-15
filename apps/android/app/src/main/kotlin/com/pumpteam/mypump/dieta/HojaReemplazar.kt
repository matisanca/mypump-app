package com.pumpteam.mypump.dieta

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.togetherWith
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
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
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
import androidx.compose.ui.graphics.compositeOver
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTagsAsResourceId
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.pumpteam.mypump.datos.ModeloApp
import com.pumpteam.mypump.diseno.BotonMarca
import com.pumpteam.mypump.diseno.Espacio
import com.pumpteam.mypump.diseno.Formato
import com.pumpteam.mypump.diseno.Iconos
import com.pumpteam.mypump.diseno.MyPump
import com.pumpteam.mypump.diseno.Radio
import com.pumpteam.mypump.diseno.superficieTarjeta
import com.pumpteam.mypump.entreno.Ceja
import com.pumpteam.mypump.entreno.Letras
import com.pumpteam.mypump.modelos.Alimento
import com.pumpteam.mypump.modelos.AlimentoPropio
import com.pumpteam.mypump.modelos.ValorJson
import com.pumpteam.mypump.reglas.Sustituto
import kotlin.math.abs
import kotlinx.coroutines.launch

/**
 * "Reemplazar" (DIE-10/11/13, gemela de `SustituirAlimentoView.swift` y `openSwapModal` de la web): los 🌍 universales
 * arriba con su nombre en inglés, los propios con ★, la diferencia de kcal contra el original (verde hasta 5 %), los
 * avisos del motor, la búsqueda y "Crear alimento personalizado" (DIE-14), que se abre adentro de la misma hoja.
 *
 * [original] es el alimento DEL PLAN en esa posición (no el sustituto que se esté mostrando): los candidatos son los
 * suyos, como en la web. [alElegir] recibe el `food_data` del elegido (macros totales de su porción, DIE-13); el ancla la
 * agrega `ModeloApp.sustituir`.
 */
@OptIn(ExperimentalMaterial3Api::class, ExperimentalComposeUiApi::class)
@Composable
fun HojaReemplazar(modelo: ModeloApp, original: Alimento, alElegir: (ValorJson) -> Unit, alCerrar: () -> Unit) {
    val c = MyPump.colores
    val hoja = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val alcanceHoja = rememberCoroutineScope()
    val foco = LocalFocusManager.current
    val tactil = LocalHapticFeedback.current
    val base by MotorSustitutos.base.collectAsStateWithLifecycle()
    val propios by modelo.alimentosPropios.collectAsStateWithLifecycle()
    val excluir by modelo.excluir.collectAsStateWithLifecycle()
    var busqueda by rememberSaveable { mutableStateOf("") }
    // El elegido por su nombre (la identidad de la web: no hay dos con el mismo nombre en minúsculas).
    var elegido by rememberSaveable { mutableStateOf<String?>(null) }
    var creando by rememberSaveable { mutableStateOf(false) }
    val resultado = remember(base, propios, excluir, original) {
        base?.let { MotorSustitutos.buscar(original, it, propios, excluir) } ?: MotorSustitutos.Resultado(categoria = CategoriaComida.inferir(original))
    }
    val filtradas = remember(resultado, busqueda) { MotorSustitutos.filtrar(resultado.opciones, busqueda) }
    val opcionElegida = resultado.opciones.firstOrNull { it.nombre.lowercase() == elegido }

    // Cerrar la hoja o volver del formulario de verdad (no al rotar): una etiqueta que la IA todavía está leyendo ya no
    // es de nadie, como el `@State` del formulario de iOS al salir de él.
    fun olvidarEscaneo() = EsperasDieta.etiqueta(modelo).olvidar()

    fun terminar() {
        olvidarEscaneo()
        alCerrar()
    }

    fun volverALaLista() {
        olvidarEscaneo()
        creando = false
    }

    fun cerrar() {
        foco.clearFocus()
        alcanceHoja.launch { hoja.hide() }.invokeOnCompletion { terminar() }
    }

    fun elegir(s: Sustituto) {
        alElegir(s.foodData)
        cerrar()
    }

    /** "Crear y usar": si el motor lo ofrece como sustituto, se aplica de una (`aplicarCustomFoodComoSwap`). */
    fun creado(a: AlimentoPropio) {
        val b = base
        val ahora = if (b == null) null else MotorSustitutos.buscar(original, b, modelo.alimentosPropios.value, modelo.excluir.value)
        val s = ahora?.opciones?.firstOrNull { it.nombre.lowercase() == a.nombre.lowercase() }
        if (s != null) {
            tactil.performHapticFeedback(HapticFeedbackType.Confirm)
            elegir(s)
        } else {
            creando = false
            busqueda = ""
        }
    }

    ModalBottomSheet(
        onDismissRequest = ::terminar,
        sheetState = hoja,
        containerColor = c.fondo,
        tonalElevation = 0.dp,
        modifier = Modifier.semantics { testTagsAsResourceId = true }.testTag("hoja-reemplazar"),
    ) {
        // Atrás desde "Alimento propio" vuelve a la lista (como el botón de volver de iOS), no cierra la hoja. Va adentro:
        // la hoja es otra ventana, con su propio Atrás.
        BackHandler(enabled = creando, onBack = ::volverALaLista)
        AnimatedContent(
            targetState = creando,
            transitionSpec = {
                if (targetState) {
                    (slideInHorizontally { it / 3 } + fadeIn()) togetherWith (slideOutHorizontally { -it / 3 } + fadeOut())
                } else {
                    (slideInHorizontally { -it / 3 } + fadeIn()) togetherWith (slideOutHorizontally { it / 3 } + fadeOut())
                }
            },
            label = "reemplazar",
        ) { formulario ->
            if (formulario) {
                CrearAlimento(modelo, categoria = resultado.categoria, alVolver = ::volverALaLista, alCrear = ::creado)
            } else {
                Column {
                    Row(Modifier.fillMaxWidth().padding(start = Espacio.l, end = Espacio.xs), verticalAlignment = Alignment.CenterVertically) {
                        Column(Modifier.weight(1f)) {
                            Text("Reemplazar", style = MaterialTheme.typography.titleLarge, modifier = Modifier.semantics { heading() })
                            Text(
                                "${filtradas.size} de ${resultado.opciones.size} · ${MotorSustitutos.nombreCategoria(resultado.categoria)}",
                                style = Letras.caption.merge(Letras.cifras),
                                color = c.textoSecundario,
                                modifier = Modifier.testTag("conteo-sustitutos"),
                            )
                        }
                        TextButton(onClick = ::cerrar, modifier = Modifier.testTag("cancelar-reemplazo")) {
                            Text("Cancelar", color = c.marcaTexto)
                        }
                    }
                    CampoBusqueda(busqueda, alCambiar = { busqueda = it })
                    LazyColumn(
                        modifier = Modifier.weight(1f, fill = false).testTag("lista-sustitutos"),
                        contentPadding = PaddingValues(start = Espacio.m, end = Espacio.m, top = Espacio.xs, bottom = Espacio.s),
                        verticalArrangement = Arrangement.spacedBy(Espacio.xs),
                    ) {
                        item(key = "reemplazas") { Reemplazas(original) }
                        if (resultado.avisos.isNotEmpty()) {
                            items(resultado.avisos, key = { "aviso-$it" }) { AvisoSustitutos(it) }
                        }
                        if (filtradas.isEmpty()) {
                            item(key = "vacio") { SinSustitutos(busqueda) }
                        } else {
                            val universales = filtradas.filter { it.universal }
                            val resto = filtradas.filterNot { it.universal }
                            if (universales.isNotEmpty()) {
                                item(key = "titulo-universales") { TituloSeccion("🌍 Disponibles en cualquier país") }
                                items(universales, key = { "u-" + it.nombre.lowercase() }) { s ->
                                    FilaSustituto(original, s, marcado = s.nombre.lowercase() == elegido) {
                                        elegido = if (s.nombre.lowercase() == elegido) null else s.nombre.lowercase()
                                    }
                                }
                            }
                            if (resto.isNotEmpty()) {
                                item(key = "titulo-resto") { TituloSeccion(if (universales.isEmpty()) "Equivalentes" else "Otras opciones") }
                                items(resto, key = { "r-" + it.nombre.lowercase() }) { s ->
                                    FilaSustituto(original, s, marcado = s.nombre.lowercase() == elegido) {
                                        elegido = if (s.nombre.lowercase() == elegido) null else s.nombre.lowercase()
                                    }
                                }
                            }
                        }
                        item(key = "crear") {
                            Column(Modifier.padding(top = Espacio.s), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                                Row(
                                    Modifier
                                        .fillMaxWidth()
                                        .superficieTarjeta(radio = Radio.control + 4.dp)
                                        .clickable(role = Role.Button) {
                                            foco.clearFocus()
                                            creando = true
                                        }
                                        .heightIn(min = 52.dp)
                                        .padding(horizontal = Espacio.m)
                                        .testTag("crear-alimento"),
                                    verticalAlignment = Alignment.CenterVertically,
                                    horizontalArrangement = Arrangement.spacedBy(Espacio.s),
                                ) {
                                    Icon(IconosDieta.MasEnCirculo, contentDescription = null, tint = c.marcaTexto, modifier = Modifier.size(22.dp))
                                    Text("Crear alimento personalizado", style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.Medium, color = c.marcaTexto)
                                }
                                Text(
                                    "Cargalo con los valores de la etiqueta y queda para todos tus reemplazos.",
                                    style = Letras.caption,
                                    color = c.textoSecundario,
                                    modifier = Modifier.padding(horizontal = Espacio.m),
                                )
                            }
                        }
                    }
                    // Abajo, siempre a mano.
                    Box(Modifier.fillMaxWidth().padding(horizontal = Espacio.m).padding(top = Espacio.xs, bottom = Espacio.m)) {
                        BotonMarca(
                            opcionElegida?.let { "Reemplazar por ${it.nombre}" } ?: "Elegí un alimento",
                            alTocar = {
                                opcionElegida?.let {
                                    tactil.performHapticFeedback(HapticFeedbackType.Confirm)
                                    elegir(it)
                                }
                            },
                            habilitado = opcionElegida != null,
                            modifier = Modifier.testTag("confirmar-reemplazo"),
                        )
                    }
                }
            }
        }
    }
}

/** La búsqueda (el `.searchable` de iOS), siempre a la vista. */
@Composable
private fun CampoBusqueda(valor: String, alCambiar: (String) -> Unit) {
    val c = MyPump.colores
    BasicTextField(
        value = valor,
        onValueChange = alCambiar,
        singleLine = true,
        textStyle = MaterialTheme.typography.bodyLarge.copy(color = c.texto),
        cursorBrush = SolidColor(c.marcaTexto),
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = Espacio.m, vertical = Espacio.xs)
            .semantics { contentDescription = "Buscar alimento" }
            .testTag("buscar-alimento"),
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
                    if (valor.isEmpty()) {
                        Text("Buscar alimento", style = MaterialTheme.typography.bodyLarge, color = c.textoTerciario, modifier = Modifier.clearAndSetSemantics {})
                    }
                    campo()
                }
            }
        },
    )
}

/** "Reemplazás": el alimento del plan con su cantidad, kcal y macros, y la pista de los universales. */
@Composable
private fun Reemplazas(original: Alimento) {
    val c = MyPump.colores
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        TituloSeccion("Reemplazás")
        Column(
            Modifier
                .fillMaxWidth()
                .superficieTarjeta(radio = Radio.control + 4.dp)
                .padding(Espacio.m)
                .semantics(mergeDescendants = true) {}
                .testTag("reemplazas"),
            verticalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            Text(original.nombre, style = MaterialTheme.typography.titleMedium)
            Text(
                "${FormatoDieta.cantidad(original.qty, original.unidad)} · ${Formato.miles(original.kcal)} kcal",
                style = MaterialTheme.typography.bodyMedium,
                color = c.textoSecundario,
            )
            Text(FormatoDieta.macros(original, c.proteina, c.carbohidrato, c.grasa), style = Letras.caption.merge(Letras.cifras), color = c.textoSecundario)
        }
        Text(
            "¿No conseguís este alimento? Elegí una opción 🌍 disponible en cualquier país.",
            style = Letras.caption,
            color = c.textoSecundario,
            modifier = Modifier.padding(horizontal = Espacio.m),
        )
    }
}

@Composable
private fun TituloSeccion(texto: String) {
    Ceja(texto, Modifier.padding(start = Espacio.m, end = Espacio.m, top = Espacio.s, bottom = 2.dp).semantics { heading() })
}

@Composable
private fun AvisoSustitutos(texto: String) {
    val c = MyPump.colores
    Row(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(Radio.control + 4.dp))
            .background(c.alerta.copy(alpha = 0.12f))
            .padding(horizontal = Espacio.m, vertical = Espacio.s)
            .testTag("aviso-sustitutos"),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(Espacio.xs),
    ) {
        Icon(Iconos.Alerta, contentDescription = null, tint = c.alerta, modifier = Modifier.size(18.dp))
        Text(texto, style = MaterialTheme.typography.bodySmall, color = c.texto)
    }
}

/** Sin equivalentes (o sin resultados para lo buscado): el `ContentUnavailableView` de iOS. */
@Composable
private fun SinSustitutos(busqueda: String) {
    val c = MyPump.colores
    Column(
        Modifier.fillMaxWidth().padding(vertical = Espacio.l, horizontal = Espacio.m).testTag("sin-sustitutos"),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(Espacio.xs),
    ) {
        Icon(Iconos.Buscar, contentDescription = null, tint = c.textoSecundario, modifier = Modifier.size(36.dp))
        Text(
            if (busqueda.isEmpty()) "Sin equivalentes" else "Sin resultados para “$busqueda”",
            style = MaterialTheme.typography.titleMedium,
        )
        Text(
            if (busqueda.isEmpty()) "No hay sustitutos equivalentes dentro del rango de macros." else "Probá con otro nombre o creá tu alimento personalizado.",
            style = MaterialTheme.typography.bodyMedium,
            color = c.textoSecundario,
        )
    }
}

/**
 * Un candidato: el círculo de elegido, el nombre (con "★ Tuyo" si es propio), el nombre en inglés de los universales, la
 * porción con sus kcal y macros, y la diferencia de kcal contra el original (verde hasta 5 %).
 */
@Composable
private fun FilaSustituto(original: Alimento, s: Sustituto, marcado: Boolean, alTocar: () -> Unit) {
    val c = MyPump.colores
    val delta = MotorSustitutos.deltaKcal(original, s)
    val bien = abs(delta) <= 5
    val tono = if (bien) c.exito else c.alerta
    Row(
        Modifier
            .fillMaxWidth()
            // Opaco: el lima suave es translúcido y dejaba ver la sombra de la tarjeta adentro.
            .superficieTarjeta(radio = Radio.control + 4.dp, color = if (marcado) c.marcaSuave.compositeOver(c.tarjeta) else c.tarjeta)
            .clickable(role = Role.RadioButton, onClick = alTocar)
            .padding(horizontal = Espacio.s, vertical = 10.dp)
            .semantics { selected = marcado }
            .testTag("sustituto"),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(Espacio.s),
    ) {
        Icon(
            if (marcado) Iconos.TildeEnCirculo else Iconos.Circulo,
            contentDescription = null,
            tint = if (marcado) c.marcaTexto else c.textoTerciario,
            modifier = Modifier.size(24.dp),
        )
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(s.nombre, style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.Medium, modifier = Modifier.weight(1f, fill = false))
                if (s.esPropio) {
                    Text(
                        "★ Tuyo",
                        style = Letras.caption2.copy(fontWeight = FontWeight.SemiBold),
                        color = c.marcaTexto,
                        maxLines = 1,
                        modifier = Modifier.clip(CircleShape).background(c.marcaSuave).padding(horizontal = 6.dp, vertical = 2.dp),
                    )
                }
            }
            s.nombreIngles?.takeIf { it.isNotEmpty() }?.let { Text(it, style = Letras.caption, color = c.textoSecundario, maxLines = 1, overflow = TextOverflow.Ellipsis) }
            Text(
                "${FormatoDieta.cantidad(s.qty, s.unidad)} · ${Formato.miles(s.kcal)} kcal",
                style = MaterialTheme.typography.bodyMedium,
                color = c.textoSecundario,
            )
            Text(FormatoDieta.macros(s.prot, s.carb, s.fat, c.proteina, c.carbohidrato, c.grasa), style = Letras.caption.merge(Letras.cifras), color = c.textoSecundario)
        }
        Text(
            "${if (delta > 0) "+" else ""}$delta %",
            style = Letras.caption.copy(fontWeight = FontWeight.SemiBold).merge(Letras.cifras),
            color = tono,
            maxLines = 1,
            modifier = Modifier
                .clip(CircleShape)
                .background(tono.copy(alpha = 0.14f))
                .padding(horizontal = 8.dp, vertical = 4.dp)
                .semantics { contentDescription = "${if (delta > 0) "más" else "menos"} ${abs(delta)} por ciento de calorías" },
        )
    }
}
