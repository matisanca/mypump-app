package com.pumpteam.mypump.dieta

import androidx.compose.animation.animateContentSize
import androidx.compose.foundation.background
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
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
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
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.pumpteam.mypump.datos.ClienteRpc
import com.pumpteam.mypump.datos.ErrorRpc
import com.pumpteam.mypump.datos.ModeloApp
import com.pumpteam.mypump.datos.Resultado
import com.pumpteam.mypump.diseno.AccionHoja
import com.pumpteam.mypump.diseno.Alerta
import com.pumpteam.mypump.diseno.AsaHoja
import com.pumpteam.mypump.diseno.BotonAlerta
import com.pumpteam.mypump.diseno.BotonMarca
import com.pumpteam.mypump.diseno.EncabezadoHoja
import com.pumpteam.mypump.diseno.Espacio
import com.pumpteam.mypump.diseno.FormaHoja
import com.pumpteam.mypump.diseno.Formato
import com.pumpteam.mypump.diseno.Iconos
import com.pumpteam.mypump.diseno.MyPump
import com.pumpteam.mypump.diseno.RuedaHora
import com.pumpteam.mypump.diseno.Separador
import com.pumpteam.mypump.diseno.Tarjeta
import com.pumpteam.mypump.entreno.Letras
import com.pumpteam.mypump.fotos.BotonFoto
import com.pumpteam.mypump.modelos.ComidaLibre
import com.pumpteam.mypump.modelos.EstimacionPlato
import com.pumpteam.mypump.raiz.LocalAlcanceApp
import com.pumpteam.mypump.reglas.AlimentoPropioNuevo
import com.pumpteam.mypump.reglas.ComidaLibreNueva
import com.pumpteam.mypump.reglas.Formulario
import com.pumpteam.mypump.reglas.jsRound
import java.time.Instant
import java.util.Locale
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch

/** Lo que abre la hoja de comida libre: vacía (a mano) o con la estimación de la foto del plato. */
sealed interface FormularioComidaLibre {
    data object AMano : FormularioComidaLibre

    data class Estimada(val estimacion: EstimacionPlato) : FormularioComidaLibre
}

/**
 * Lo de las comidas libres que vive afuera de la lista de Dieta (`analizandoFoto`, la hoja y el aviso de iOS): la foto del
 * plato mientras la mira la IA, el formulario abierto y el error de la visión. Así una hoja abierta no depende de que la
 * tarjeta siga a la vista en la lista perezosa, y la respuesta de la IA no se pierde si el cliente cambia de pestaña o
 * gira el teléfono mientras espera ([EsperasDieta]).
 */
@Stable
class EstadoComidasLibres {
    var analizando by mutableStateOf(false)
        private set
    var formulario by mutableStateOf<FormularioComidaLibre?>(null)
    var errorFoto by mutableStateOf<String?>(null)

    /** La foto del plato (JPEG ya reducido) a la visión: con la estimación se abre el formulario; si falla, el aviso (DIE-16). */
    fun analizar(modelo: ModeloApp, alcance: CoroutineScope, jpeg: ByteArray) {
        if (analizando) return
        analizando = true
        alcance.launch {
            val r = modelo.analizarFoto(jpeg, ClienteRpc.TipoVision.PLATO)
            analizando = false
            when (r) {
                is Resultado.Ok -> {
                    val e = try {
                        EstimacionPlato.desde(r.valor.aJson())
                    } catch (_: Exception) {
                        null
                    }
                    if (e != null) formulario = FormularioComidaLibre.Estimada(e) else errorFoto = "respuesta inesperada"
                }
                is Resultado.Falla -> errorFoto = if (r.error.clase == ErrorRpc.Clase.RED) "sin conexión" else r.error.mensaje
            }
        }
    }
}

/** El de esta cuenta (sobrevive a cambiar de pestaña y a rotar). */
@Composable
fun rememberEstadoComidasLibres(modelo: ModeloApp): EstadoComidasLibres {
    val cuenta = modelo.token
    return remember(modelo, cuenta) { EsperasDieta.comidasLibres(modelo) }
}

/**
 * "Comidas libres" al pie de Dieta (DIE-15, gemela de `ComidasLibresSeccion.swift`): lo que el cliente comió además del
 * plan, del día local, con foto del plato (la IA estima y se corrige) o a mano. Borrar es optimista: si el servidor no
 * contesta bien, vuelve a aparecer. Mati las ve en su panel. En la demo no está (como en la web).
 */
@Composable
fun ComidasLibresSeccion(modelo: ModeloApp, estado: EstadoComidasLibres, modifier: Modifier = Modifier) {
    val c = MyPump.colores
    val alcance = LocalAlcanceApp.current
    val tactil = LocalHapticFeedback.current
    val comidas by modelo.comidasLibres.collectAsStateWithLifecycle()

    Tarjeta(modifier.testTag("comidas-libres"), espaciado = 14.dp) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp), modifier = Modifier.semantics(mergeDescendants = true) {}) {
            Box(Modifier.size(38.dp).clip(RoundedCornerShape(11.dp)).background(c.marcaSuave), contentAlignment = Alignment.Center) {
                Icon(IconosDieta.ComidaAfuera, contentDescription = null, tint = c.marcaTexto, modifier = Modifier.size(19.dp))
            }
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(1.dp)) {
                Text(
                    "Comidas libres",
                    style = MaterialTheme.typography.titleMedium.copy(fontSize = MaterialTheme.typography.titleLarge.fontSize),
                    modifier = Modifier.semantics { heading() },
                )
                Text("Lo que comiste fuera del plan", style = MaterialTheme.typography.bodySmall, color = c.textoSecundario)
            }
        }
        if (comidas.isNotEmpty()) {
            Column(Modifier.animateContentSize()) {
                comidas.forEachIndexed { i, comida ->
                    FilaComidaLibre(comida) {
                        alcance.launch {
                            // Optimista: el modelo la saca ya y la devuelve si el servidor no contesta bien.
                            if (!modelo.borrarComidaLibre(comida.id)) tactil.performHapticFeedback(HapticFeedbackType.Reject)
                        }
                    }
                    if (i < comidas.size - 1) Separador()
                }
            }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            BotonFoto(
                clave = "plato",
                maxPx = 1280,
                calidad = 0.85,
                alElegir = { jpeg -> estado.analizar(modelo, alcance, jpeg) },
                habilitado = !estado.analizando,
                modifier = Modifier.weight(1f),
            ) {
                Row(
                    Modifier
                        .fillMaxWidth()
                        .heightIn(min = 44.dp)
                        .clip(RoundedCornerShape(12.dp))
                        .background(c.marca)
                        .testTag("con-foto"),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(6.dp, Alignment.CenterHorizontally),
                ) {
                    Icon(Iconos.Camara, contentDescription = null, tint = c.sobreMarca, modifier = Modifier.size(18.dp))
                    Text("Con foto", style = MaterialTheme.typography.labelLarge, fontWeight = FontWeight.SemiBold, color = c.sobreMarca)
                }
            }
            Row(
                Modifier
                    .weight(1f)
                    .heightIn(min = 44.dp)
                    .clip(RoundedCornerShape(12.dp))
                    .background(c.campo)
                    .clickable(role = Role.Button) { estado.formulario = FormularioComidaLibre.AMano }
                    .testTag("a-mano"),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(6.dp, Alignment.CenterHorizontally),
            ) {
                Icon(Iconos.Lapiz, contentDescription = null, tint = c.texto, modifier = Modifier.size(17.dp))
                Text("A mano", style = MaterialTheme.typography.labelLarge, fontWeight = FontWeight.SemiBold, color = c.texto)
            }
        }
    }
}

/** Una comida libre: qué fue y a qué hora, sus kcal ("estimado") y macros, y la ✕ para borrarla. */
@Composable
private fun FilaComidaLibre(comida: ComidaLibre, alBorrar: () -> Unit) {
    val c = MyPump.colores
    val descripcion = comida.descripcion ?: ""
    Row(
        Modifier.fillMaxWidth().padding(vertical = 8.dp).testTag("comida-libre"),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Column(Modifier.weight(1f).semantics(mergeDescendants = true) {}, verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(descripcion, style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.Medium, modifier = Modifier.weight(1f, fill = false))
                comida.hora?.takeIf { it.isNotEmpty() }?.let {
                    Text(it.take(5), style = Letras.caption.merge(Letras.cifras), color = c.textoSecundario)
                }
            }
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Text("${Formato.miles(jsRound(comida.kcal ?: 0.0))} kcal", style = MaterialTheme.typography.bodyMedium, color = c.textoSecundario)
                Text(
                    "estimado",
                    style = Letras.caption2.copy(fontWeight = FontWeight.SemiBold),
                    color = c.textoSecundario,
                    modifier = Modifier.clip(CircleShape).background(c.campo).padding(horizontal = 6.dp, vertical = 2.dp),
                )
            }
            // Las macros redondeadas, como iOS.
            Text(
                FormatoDieta.macros(
                    Formato.entero(comida.prot ?: 0.0).toDouble(),
                    Formato.entero(comida.carb ?: 0.0).toDouble(),
                    Formato.entero(comida.fat ?: 0.0).toDouble(),
                    c.proteina,
                    c.carbohidrato,
                    c.grasa,
                ),
                style = Letras.caption.merge(Letras.cifras),
                color = c.textoSecundario,
            )
        }
        Box(
            Modifier
                .size(44.dp)
                .clip(CircleShape)
                .clickable(role = Role.Button, onClick = alBorrar)
                .semantics { contentDescription = "Borrar ${comida.descripcion ?: "comida"}" },
            contentAlignment = Alignment.Center,
        ) {
            Box(Modifier.size(30.dp).clip(CircleShape).background(c.campo), contentAlignment = Alignment.Center) {
                Icon(Iconos.Cerrar, contentDescription = null, tint = c.textoSecundario, modifier = Modifier.size(15.dp))
            }
        }
    }
}

/**
 * Las hojas de las comidas libres, que van afuera de la lista perezosa de Dieta: el formulario (vacío o con la estimación)
 * y el aviso de la visión que falló, con el pase a mano (DIE-16).
 */
@Composable
fun HojasComidasLibres(modelo: ModeloApp, estado: EstadoComidasLibres) {
    val c = MyPump.colores
    estado.formulario?.let { f ->
        HojaComidaLibre(modelo, (f as? FormularioComidaLibre.Estimada)?.estimacion, alCerrar = { estado.formulario = null })
    }
    estado.errorFoto?.let { motivo ->
        Alerta(
            titulo = "No pudimos leer la foto",
            mensaje = "$motivo. Podés cargarla a mano.",
            etiquetaMensaje = "motivo-foto",
            botones = listOf(
                BotonAlerta("Cancelar", etiqueta = "cancelar-foto", cancelar = true) { estado.errorFoto = null },
                BotonAlerta("Cargar a mano", etiqueta = "cargar-a-mano") {
                    estado.errorFoto = null
                    estado.formulario = FormularioComidaLibre.AMano
                },
            ),
            alDescartar = { estado.errorFoto = null },
            modifier = Modifier.testTag("foto-no-leida"),
        )
    }
}

/**
 * Registrar una comida fuera del plan (DIE-15, gemela de `ComidaLibreView.swift`, `openComidaLibreModal` de la web):
 * vacía, o con la estimación de la foto. Todo es editable; corregir los gramos de un alimento re-escala sus macros y
 * recalcula los totales. Va directo al servidor (no por la cola), con la fecha local.
 */
@OptIn(ExperimentalMaterial3Api::class, ExperimentalComposeUiApi::class)
@Composable
fun HojaComidaLibre(modelo: ModeloApp, estimacion: EstimacionPlato?, alCerrar: () -> Unit) {
    val c = MyPump.colores
    val hoja = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val alcanceHoja = rememberCoroutineScope()
    val alcance = LocalAlcanceApp.current
    val foco = LocalFocusManager.current
    val tactil = LocalHapticFeedback.current
    val bases = remember(estimacion) { ComidaLibreNueva.bases(estimacion) }
    var descripcion by rememberSaveable { mutableStateOf(estimacion?.descripcion ?: "") }
    var hora by rememberSaveable { mutableStateOf(ComidaLibreNueva.hora(Instant.now())) }
    var kcal by rememberSaveable { mutableStateOf(estimacion?.kcal?.let { jsEntero(it).toString() } ?: "") }
    var prot by rememberSaveable { mutableStateOf(estimacion?.prot?.let(Formato::decimal) ?: "") }
    var carb by rememberSaveable { mutableStateOf(estimacion?.carb?.let(Formato::decimal) ?: "") }
    var fat by rememberSaveable { mutableStateOf(estimacion?.fat?.let(Formato::decimal) ?: "") }
    var gramos by rememberSaveable { mutableStateOf(bases.map { Formato.entero(it.gramosIniciales).toString() }) }
    var error by rememberSaveable { mutableStateOf<String?>(null) }
    var guardando by remember { mutableStateOf(false) }
    var eligiendoHora by remember { mutableStateOf(false) }

    fun cerrar() {
        foco.clearFocus()
        alcanceHoja.launch { hoja.hide() }.invokeOnCompletion { alCerrar() }
    }

    /** Corregir los gramos re-escala las macros de ese alimento y los totales (`_recalcularDesdeGramos`). */
    fun cambiarGramos(i: Int, texto: String) {
        val nuevos = gramos.toMutableList().also { it[i] = texto }
        gramos = nuevos
        val t = ComidaLibreNueva.totales(bases, ComidaLibreNueva.gramos(bases, nuevos.map(AlimentoPropioNuevo::leerNumero)))
        kcal = Formato.entero(t.kcal).toString()
        prot = Formato.decimal(t.prot)
        carb = Formato.decimal(t.carb)
        fat = Formato.decimal(t.fat)
    }

    fun guardar() {
        foco.clearFocus()
        val leer = AlimentoPropioNuevo::leerNumero
        val vigentes = ComidaLibreNueva.gramos(bases, gramos.map(leer))
        val detalle = ComidaLibreNueva.detalle(bases, vigentes, estimacion?.confianza, estimacion?.escala)
        when (val f = ComidaLibreNueva.preparar(descripcion, hora, leer(kcal), leer(prot), leer(carb), leer(fat), detalle)) {
            is Formulario.Invalido -> {
                error = f.mensaje
                tactil.performHapticFeedback(HapticFeedbackType.Reject)
            }
            is Formulario.Valido -> {
                error = null
                guardando = true
                alcance.launch {
                    val r = modelo.crearComidaLibre(f.datos)
                    guardando = false
                    when (r) {
                        is Resultado.Ok -> {
                            tactil.performHapticFeedback(HapticFeedbackType.Confirm)
                            cerrar()
                        }
                        is Resultado.Falla -> {
                            error = if (r.error.clase == ErrorRpc.Clase.RED) "Sin conexión: probá de nuevo cuando tengas señal." else "No se pudo guardar. Probá de nuevo."
                            tactil.performHapticFeedback(HapticFeedbackType.Reject)
                        }
                    }
                }
            }
        }
    }

    ModalBottomSheet(
        onDismissRequest = { if (!guardando) alCerrar() },
        sheetState = hoja,
        shape = FormaHoja,
        containerColor = c.fondo,
        tonalElevation = 0.dp,
        dragHandle = { AsaHoja() },
        modifier = Modifier.semantics { testTagsAsResourceId = true }.testTag("hoja-comida-libre"),
    ) {
        EncabezadoHoja(
            if (estimacion == null) "Comida libre" else "Revisá la estimación",
            cancelar = AccionHoja("Cancelar", "cancelar-comida-libre", habilitada = !guardando, alTocar = ::cerrar),
        )
        Column(
            Modifier
                .weight(1f, fill = false)
                .verticalScroll(rememberScrollState())
                .padding(horizontal = Espacio.m)
                .padding(top = Espacio.xs, bottom = Espacio.s),
            verticalArrangement = Arrangement.spacedBy(Espacio.l),
        ) {
            if (estimacion != null) {
                SeccionFormulario(titulo = null) {
                    Row(
                        Modifier.fillMaxWidth().padding(horizontal = Espacio.m, vertical = 12.dp).testTag("aviso-estimacion"),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(Espacio.s),
                    ) {
                        Icon(Iconos.Chispas, contentDescription = null, tint = c.marcaTexto, modifier = Modifier.size(20.dp))
                        Text("La IA estimó esto de tu foto. Es un estimativo: corregí lo que haga falta.", style = MaterialTheme.typography.bodyMedium)
                    }
                    if (estimacion.confianza == "baja") {
                        SeparadorFila()
                        Row(
                            Modifier.fillMaxWidth().padding(horizontal = Espacio.m, vertical = 12.dp).testTag("confianza-baja"),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(Espacio.s),
                        ) {
                            Icon(Iconos.Alerta, contentDescription = null, tint = c.alerta, modifier = Modifier.size(20.dp))
                            Text("La foto se leyó con poca claridad.", style = MaterialTheme.typography.bodyMedium, color = c.alerta)
                        }
                    }
                }
            }
            if (bases.isNotEmpty()) {
                SeccionFormulario("Lo que vio en el plato", pie = estimacion?.escala?.takeIf { it.isNotEmpty() }?.let { "📐 $it" }) {
                    bases.forEachIndexed { i, b ->
                        if (i > 0) SeparadorFila()
                        FilaNumero(
                            b.nombre,
                            gramos.getOrElse(i) { "" },
                            alCambiar = { cambiarGramos(i, it) },
                            unidad = "g",
                            etiqueta = "gramos-$i",
                            descripcion = "Gramos de ${b.nombre}",
                            decimal = false,
                        )
                    }
                }
            }
            SeccionFormulario("Qué comiste") {
                FilaTexto(
                    descripcion,
                    alCambiar = { descripcion = it },
                    ejemplo = "Ej: Milanesa con puré",
                    etiqueta = "descripcion-comida-libre",
                    descripcion = "Qué comiste",
                )
                SeparadorFila()
                Row(
                    Modifier
                        .fillMaxWidth()
                        .clickable(role = Role.Button, onClickLabel = "cambiar la hora") { eligiendoHora = true }
                        .heightIn(min = 48.dp)
                        .padding(horizontal = Espacio.m)
                        .semantics(mergeDescendants = true) {
                            contentDescription = "Hora"
                            stateDescription = hora
                        }
                        .testTag("hora-comida-libre"),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text("Hora", style = MaterialTheme.typography.bodyLarge, modifier = Modifier.weight(1f))
                    Text(
                        hora,
                        style = MaterialTheme.typography.bodyLarge.merge(Letras.cifras),
                        color = c.texto,
                        modifier = Modifier.clip(RoundedCornerShape(8.dp)).background(c.campo).padding(horizontal = 10.dp, vertical = 5.dp),
                    )
                }
            }
            SeccionFormulario("Valores") {
                FilaNumero("Calorías", kcal, alCambiar = { kcal = it }, unidad = "kcal", etiqueta = "kcal-comida-libre")
                SeparadorFila()
                FilaNumero("Proteínas", prot, alCambiar = { prot = it }, unidad = "g", etiqueta = "prot-comida-libre")
                SeparadorFila()
                FilaNumero("Carbohidratos", carb, alCambiar = { carb = it }, unidad = "g", etiqueta = "carb-comida-libre")
                SeparadorFila()
                FilaNumero("Grasas", fat, alCambiar = { fat = it }, unidad = "g", etiqueta = "fat-comida-libre")
            }
            error?.let { ErrorFormulario(it, etiqueta = "error-comida-libre") }
        }
        Box(Modifier.fillMaxWidth().padding(horizontal = Espacio.m).padding(top = Espacio.xs, bottom = Espacio.m)) {
            BotonMarca("Registrar", alTocar = ::guardar, cargando = guardando, modifier = Modifier.testTag("registrar-comida-libre"))
        }
    }

    if (eligiendoHora) {
        DialogoHora(hora, alElegir = {
            hora = it
            eligiendoHora = false
        }, alCancelar = { eligiendoHora = false })
    }
}

/** La hora de la comida: la rueda del `DatePicker` de horas y minutos de iOS ([RuedaHora]), en 24 h. */
@Composable
private fun DialogoHora(hora: String, alElegir: (String) -> Unit, alCancelar: () -> Unit) {
    val partes = hora.split(":")
    var h by remember { mutableIntStateOf(partes.getOrNull(0)?.toIntOrNull()?.coerceIn(0, 23) ?: 0) }
    var m by remember { mutableIntStateOf(partes.getOrNull(1)?.toIntOrNull()?.coerceIn(0, 59) ?: 0) }
    Alerta(
        titulo = "Hora",
        botones = listOf(
            BotonAlerta("Cancelar", cancelar = true, alTocar = alCancelar),
            BotonAlerta("Listo", etiqueta = "hora-listo") { alElegir(String.format(Locale.ROOT, "%02d:%02d", h, m)) },
        ),
        alDescartar = alCancelar,
        contenido = {
            RuedaHora(h, m, alCambiar = { nh, nm ->
                h = nh
                m = nm
            }, modifier = Modifier.fillMaxWidth())
        },
    )
}
