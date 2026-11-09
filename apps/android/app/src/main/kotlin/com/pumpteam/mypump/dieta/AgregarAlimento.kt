package com.pumpteam.mypump.dieta

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
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
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTagsAsResourceId
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.pumpteam.mypump.datos.ModeloApp
import com.pumpteam.mypump.datos.ajustesVista
import com.pumpteam.mypump.datos.enDiaPasado
import com.pumpteam.mypump.diseno.AccionHoja
import com.pumpteam.mypump.diseno.AsaHoja
import com.pumpteam.mypump.diseno.BotonMarca
import com.pumpteam.mypump.diseno.BotonVolver
import com.pumpteam.mypump.diseno.EncabezadoHoja
import com.pumpteam.mypump.diseno.Espacio
import com.pumpteam.mypump.diseno.EstadoVacio
import com.pumpteam.mypump.diseno.FormaHoja
import com.pumpteam.mypump.diseno.Formato
import com.pumpteam.mypump.diseno.Iconos
import com.pumpteam.mypump.diseno.MyPump
import com.pumpteam.mypump.diseno.Numeros
import com.pumpteam.mypump.diseno.Radio
import com.pumpteam.mypump.diseno.Segmentado
import com.pumpteam.mypump.diseno.Separador
import com.pumpteam.mypump.diseno.Tarjeta
import com.pumpteam.mypump.diseno.superficieTarjeta
import com.pumpteam.mypump.entreno.Letras
import com.pumpteam.mypump.modelos.Alimento
import com.pumpteam.mypump.modelos.AlimentoPropio
import com.pumpteam.mypump.raiz.LocalAlcanceApp
import com.pumpteam.mypump.reglas.AgregadosComida
import com.pumpteam.mypump.reglas.AjusteComida
import com.pumpteam.mypump.reglas.AjustePorciones
import com.pumpteam.mypump.reglas.AlimentoAgregado
import com.pumpteam.mypump.reglas.AlimentoBase
import com.pumpteam.mypump.reglas.CodigoBarras
import com.pumpteam.mypump.reglas.PorcionCasera
import kotlinx.coroutines.launch

/** Qué cantidad se elige: un alimento nuevo para sumar a la comida (D1), uno ya agregado o uno del plan (D2). */
sealed interface QueCantidad {
    data class Nuevo(val candidato: AgregadosComida.Candidato) : QueCantidad
    data class Agregado(val ts: Long) : QueCantidad
    data class DelPlan(val i: Int) : QueCantidad
}

/** El pedido de la hoja de cantidad; [inicial] es la cantidad con que abre (un reciente trae la última). */
data class PedidoCantidad(val comidaId: String, val que: QueCantidad, val inicial: Pair<Double, AgregadosComida.Medida>? = null) {
    /** Para abrir la hoja desde la tarjeta sobreviviendo a rotar: «comida|plan|i» o «comida|agregado|ts». */
    fun clave(): String? = when (que) {
        is QueCantidad.DelPlan -> "$comidaId|plan|${que.i}"
        is QueCantidad.Agregado -> "$comidaId|agregado|${que.ts}"
        is QueCantidad.Nuevo -> null
    }

    companion object {
        fun desde(clave: String): PedidoCantidad? {
            val p = clave.split('|')
            if (p.size != 3) return null
            return when (p[1]) {
                "plan" -> p[2].toIntOrNull()?.let { PedidoCantidad(p[0], QueCantidad.DelPlan(it)) }
                "agregado" -> p[2].toLongOrNull()?.let { PedidoCantidad(p[0], QueCantidad.Agregado(it)) }
                else -> null
            }
        }
    }
}

/** Las cuentas de la hoja de cantidad que se comparten con el «+» de los recientes (gemelas de las de iOS). */
internal object CuentasCantidad {
    /** Un `_ts` nuevo (ms) que no tenga otro agregado de la comida. */
    fun nuevoTs(a: AjusteComida?): Long {
        var t = System.currentTimeMillis()
        while (a?.agregados?.any { it.ts == t } == true) t += 1
        return t
    }

    /**
     * El ajuste de una comida tal como está, en la opción que se ve (si era de otra, las cantidades a mano no valen, como en
     * «Ajustar esta comida»). Sin ajuste, uno nuevo con compensar prendido.
     */
    fun base(modelo: ModeloApp, comidaId: String, opciones: Map<String, Int>): AjusteComida {
        val opcion = modelo.comidasParaAjustar(opciones).firstOrNull { it.id == comidaId }?.opcion ?: 0
        val a = modelo.ajustesVista[comidaId] ?: AjusteComida(opcion = opcion)
        return if (a.opcion != opcion) a.copy(opcion = opcion, cantidades = emptyMap(), anclas = emptyMap()) else a
    }

    fun medidaDe(a: AlimentoAgregado): AgregadosComida.Medida =
        AgregadosComida.medidas(a.candidato).firstOrNull { it.nombre == a.unidad } ?: AgregadosComida.Medida(a.unidad, a.gramosUnidad ?: 1.0)
}

/**
 * «Agregar alimento» a una comida del plan (2.0.3, D1; gemela de AgregarAlimentoView.swift): los recientes con «+» de un
 * toque, los alimentos propios, el buscador sobre la base de alimentos (la misma de los reemplazos) y crear uno nuevo.
 * Tocar uno abre la cantidad dentro de la misma hoja (con la flecha de volver).
 *
 * 2.1 (S3): «Escanear código de barras», como el «Barcode scan» de MyFitnessPal: el escáner de Google lee el código, se busca
 * en Open Food Facts y abre la misma cantidad. Si no está (o le faltan datos), se carga a mano o con la foto de la etiqueta.
 */
@OptIn(ExperimentalMaterial3Api::class, ExperimentalComposeUiApi::class)
@Composable
fun HojaAgregarAlimento(modelo: ModeloApp, comidaId: String, fecha: String, opciones: Map<String, Int>, alCerrar: () -> Unit) {
    val c = MyPump.colores
    val hoja = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val alcanceHoja = rememberCoroutineScope()
    val alcance = LocalAlcanceApp.current
    val foco = LocalFocusManager.current
    val tactil = LocalHapticFeedback.current
    val baseMotor by MotorSustitutos.base.collectAsStateWithLifecycle()
    val propios by modelo.alimentosPropios.collectAsStateWithLifecycle()
    val recientes by modelo.agregadosRecientes.collectAsStateWithLifecycle()
    var busqueda by rememberSaveable { mutableStateOf("") }
    var creando by rememberSaveable { mutableStateOf(false) }
    // El elegido no sobrevive a rotar (vuelve a la lista): la búsqueda sí.
    var elegido by remember { mutableStateOf<PedidoCantidad?>(null) }
    var aviso by remember { mutableStateOf<String?>(null) }
    // El código de barras: buscando, lo que no se encontró, sin red y lo que precarga «Alimento propio».
    val contexto = LocalContext.current
    var buscando by remember { mutableStateOf<String?>(null) }
    var sinProducto by remember { mutableStateOf<SinProductoCodigo?>(null) }
    var avisoCodigo by remember { mutableStateOf<String?>(null) }
    var precarga by remember { mutableStateOf<PrecargaCodigo?>(null) }
    val base = remember(baseMotor, propios) { baseMotor?.conPropios(propios) }
    val nombreComida = modelo.comidasParaAjustar(opciones).firstOrNull { it.id == comidaId }?.nombre.orEmpty()

    fun cerrar() {
        foco.clearFocus()
        alcanceHoja.launch { hoja.hide() }.invokeOnCompletion { alCerrar() }
    }

    fun abrir(p: PedidoCantidad) {
        foco.clearFocus()
        elegido = p
    }

    fun creado(a: AlimentoPropio) {
        creando = false
        var c0 = AgregadosComida.Candidato(
            AlimentoBase(
                nombre = a.nombre, kcal = a.kcal ?: 0.0, prot = a.prot ?: 0.0, carb = a.carb ?: 0.0, fat = a.fat ?: 0.0,
                categoria = a.categoria, unidad = a.unidad, gramosPorUnidad = a.gramosPorUnidad, esPropio = true,
            ),
        )
        // Creado desde un código: el agregado lleva el código y el próximo escaneo encuentra este alimento.
        precarga?.codigo?.let { codigo ->
            c0 = c0.copy(origen = AlimentoAgregado.Origen.PROPIO, codigo = codigo)
            modelo.recordarCodigoPropio(codigo, c0)
            sinProducto = null
        }
        precarga = null
        abrir(PedidoCantidad(comidaId, QueCantidad.Nuevo(c0)))
    }

    fun buscar(codigo: String) {
        sinProducto = null
        avisoCodigo = null
        buscando = codigo
        alcanceHoja.launch {
            val r = modelo.buscarCodigo(codigo)
            buscando = null
            when (r) {
                is ModeloApp.BusquedaCodigo.Leido -> when (val l = r.lectura) {
                    is CodigoBarras.Lectura.Encontrado -> {
                        tactil.performHapticFeedback(HapticFeedbackType.Confirm)
                        abrir(PedidoCantidad(comidaId, QueCantidad.Nuevo(l.producto.candidato)))
                    }
                    is CodigoBarras.Lectura.Incompleto -> sinProducto = SinProductoCodigo(codigo, l.parcial)
                    CodigoBarras.Lectura.NoEncontrado -> sinProducto = SinProductoCodigo(codigo, null)
                }
                ModeloApp.BusquedaCodigo.SinRed -> avisoCodigo = "Sin conexión: no pudimos buscar el código. Probá de nuevo o buscalo por nombre."
            }
        }
    }

    fun escanear() {
        foco.clearFocus()
        avisoCodigo = null
        EscanerCodigo.escanear(contexto) { r ->
            when (r) {
                is EscanerCodigo.Resultado.Leido -> buscar(r.codigo)
                EscanerCodigo.Resultado.Cancelado -> Unit
                EscanerCodigo.Resultado.Invalido -> avisoCodigo = "Ese código no es el de un producto (EAN o UPC). Probá de nuevo o buscalo por nombre."
                is EscanerCodigo.Resultado.NoDisponible -> avisoCodigo = if (r.bajando) {
                    "El escáner se está instalando: probá de nuevo en un minuto. Mientras, buscá el alimento por nombre."
                } else {
                    "Este teléfono no puede escanear códigos. Buscá el alimento por nombre, o creá el tuyo con la foto de la etiqueta."
                }
            }
        }
    }

    fun crearDesdeCodigo(sp: SinProductoCodigo, etiqueta: Boolean) {
        foco.clearFocus()
        precarga = PrecargaCodigo(sp.codigo, sp.parcial, etiqueta)
        creando = true
    }

    /** El «+» de un reciente: la misma cantidad de la última vez, a esta comida, sin pasar por la cantidad. */
    fun agregarDeUnToque(r: AlimentoAgregado) {
        val a0 = CuentasCantidad.base(modelo, comidaId, opciones)
        val nuevo = AgregadosComida.agregado(r.candidato, r.cantidad, CuentasCantidad.medidaDe(r), CuentasCantidad.nuevoTs(a0))
        val a = a0.copy(agregados = a0.agregados + nuevo)
        val dia = modelo.ajustesVista + (comidaId to a)
        AgregadosComida.motivoNoEntra(dia, comidaId)?.let {
            aviso = it
            return
        }
        tactil.performHapticFeedback(HapticFeedbackType.Confirm)
        alcance.launch { modelo.ajustar(comidaId, a, opciones, fecha) }
        modelo.recordarReciente(nuevo)
        cerrar()
    }

    val paso = when {
        elegido != null -> 2
        creando -> 1
        else -> 0
    }
    ModalBottomSheet(
        onDismissRequest = alCerrar,
        sheetState = hoja,
        shape = FormaHoja,
        containerColor = c.fondo,
        tonalElevation = 0.dp,
        dragHandle = { AsaHoja() },
        modifier = Modifier.semantics { testTagsAsResourceId = true }.testTag("hoja-agregar"),
    ) {
        BackHandler(enabled = paso != 0) {
            if (elegido != null) elegido = null else creando = false
        }
        AnimatedContent(
            targetState = paso,
            transitionSpec = {
                if (targetState > initialState) {
                    (slideInHorizontally { it / 3 } + fadeIn()) togetherWith (slideOutHorizontally { -it / 3 } + fadeOut())
                } else {
                    (slideInHorizontally { -it / 3 } + fadeIn()) togetherWith (slideOutHorizontally { it / 3 } + fadeOut())
                }
            },
            label = "agregar",
        ) { p ->
            when (p) {
                2 -> elegido?.let { e ->
                    ContenidoCantidad(
                        modelo, e, fecha, opciones,
                        izquierda = { BotonVolver({ elegido = null }, descripcion = "Volver a la búsqueda", etiqueta = "volver-a-agregar") },
                        alTerminar = ::cerrar,
                    )
                }
                1 -> CrearAlimento(
                    modelo, categoria = "", alVolver = { creando = false }, alCrear = ::creado, precarga = precarga,
                    volverDescripcion = "Volver a Agregar",
                )
                else -> Column {
                    EncabezadoHoja(
                        "Agregar ${TextosAjuste.aLa(nombreComida)}",
                        cancelar = AccionHoja("Cancelar", "agregar-cancelar", alTocar = ::cerrar),
                    )
                    CampoBusqueda(busqueda, alCambiar = { busqueda = it })
                    val consulta = busqueda.trim()
                    val resultados = remember(base, consulta) { if (base == null || consulta.isEmpty()) emptyList() else AgregadosComida.buscar(base, consulta) }
                    LazyColumn(
                        modifier = Modifier.weight(1f, fill = false).testTag("lista-agregar"),
                        contentPadding = PaddingValues(start = Espacio.m, end = Espacio.m, top = Espacio.xs, bottom = Espacio.l),
                        verticalArrangement = Arrangement.spacedBy(Espacio.xs),
                    ) {
                        aviso?.let { t -> item(key = "aviso") { AvisoAgregar(t) } }
                        item(key = "codigo") {
                            val sp = sinProducto
                            when {
                                buscando != null -> BuscandoCodigo(buscando!!)
                                sp != null -> SinProductoTarjeta(
                                    sp, conIA = modelo.token != null,
                                    alEtiqueta = { crearDesdeCodigo(sp, etiqueta = true) },
                                    alAMano = { crearDesdeCodigo(sp, etiqueta = false) },
                                    alOtro = ::escanear,
                                )
                                else -> Column(verticalArrangement = Arrangement.spacedBy(Espacio.xs)) {
                                    TarjetaEscanear(::escanear)
                                    avisoCodigo?.let { AvisoAgregar(it) }
                                }
                            }
                        }
                        if (consulta.isEmpty()) {
                            if (recientes.isNotEmpty()) {
                                item(key = "t-recientes") { TituloAgregar("Recientes") }
                                itemsIndexed(recientes, key = { _, r -> "r-${r.ts}" }) { i, r ->
                                    FilaReciente(r, i, alTocar = {
                                        abrir(PedidoCantidad(comidaId, QueCantidad.Nuevo(r.candidato), r.cantidad to CuentasCantidad.medidaDe(r)))
                                    }, alSumar = { agregarDeUnToque(r) })
                                }
                            }
                            val suyos = base?.alimentos.orEmpty().filter { it.esPropio }
                            if (suyos.isNotEmpty()) {
                                item(key = "t-propios") { TituloAgregar("Tus alimentos") }
                                items(suyos, key = { "p-" + it.nombre.lowercase() }) { a ->
                                    FilaBase(a) { abrir(PedidoCantidad(comidaId, QueCantidad.Nuevo(AgregadosComida.Candidato(a)))) }
                                }
                            }
                            item(key = "pista") {
                                Text(
                                    "Buscá entre los ${baseMotor?.alimentos?.size ?: 0} alimentos de la base: zapallo, huevo, arroz…",
                                    style = Letras.caption, color = c.textoSecundario,
                                    modifier = Modifier.padding(horizontal = Espacio.xs, vertical = Espacio.xs),
                                )
                            }
                        } else if (resultados.isEmpty()) {
                            item(key = "vacio") {
                                EstadoVacio(
                                    icono = Iconos.Buscar,
                                    titulo = "Sin resultados para “$consulta”",
                                    texto = "Probá con otro nombre o creá tu alimento con los datos de la etiqueta.",
                                    modifier = Modifier.testTag("agregar-vacio"),
                                )
                            }
                        } else {
                            item(key = "t-base") { TituloAgregar("Base de alimentos") }
                            items(resultados, key = { "b-" + it.nombre.lowercase() }) { a ->
                                FilaBase(a) { abrir(PedidoCantidad(comidaId, QueCantidad.Nuevo(AgregadosComida.Candidato(a)))) }
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
                                            precarga = null
                                            creando = true
                                        }
                                        .heightIn(min = 52.dp)
                                        .padding(horizontal = Espacio.m)
                                        .testTag("agregar-crear"),
                                    verticalAlignment = Alignment.CenterVertically,
                                    horizontalArrangement = Arrangement.spacedBy(Espacio.s),
                                ) {
                                    Icon(IconosDieta.MasEnCirculo, contentDescription = null, tint = c.marcaTexto, modifier = Modifier.size(22.dp))
                                    Text("Crear alimento personalizado", style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.Medium, color = c.marcaTexto)
                                }
                                Text(
                                    "Cargalo con los valores de la etiqueta y queda para tus próximas comidas y reemplazos.",
                                    style = Letras.caption, color = c.textoSecundario, modifier = Modifier.padding(horizontal = Espacio.m),
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}

/** La hoja de cantidad sola: tocar la cantidad de un alimento del plan (D2) o de uno agregado. */
@OptIn(ExperimentalMaterial3Api::class, ExperimentalComposeUiApi::class)
@Composable
fun HojaCantidad(modelo: ModeloApp, pedido: PedidoCantidad, fecha: String, opciones: Map<String, Int>, alCerrar: () -> Unit) {
    val c = MyPump.colores
    val hoja = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val alcanceHoja = rememberCoroutineScope()
    val foco = LocalFocusManager.current
    fun cerrar() {
        foco.clearFocus()
        alcanceHoja.launch { hoja.hide() }.invokeOnCompletion { alCerrar() }
    }
    ModalBottomSheet(
        onDismissRequest = alCerrar,
        sheetState = hoja,
        shape = FormaHoja,
        containerColor = c.fondo,
        tonalElevation = 0.dp,
        dragHandle = { AsaHoja() },
        modifier = Modifier.semantics { testTagsAsResourceId = true }.testTag("hoja-cantidad"),
    ) {
        ContenidoCantidad(modelo, pedido, fecha, opciones, cancelar = AccionHoja("Cancelar", "cantidad-cancelar", alTocar = ::cerrar), alTerminar = ::cerrar)
    }
}

/**
 * La cantidad de un alimento en una comida de hoy (2.0.3, el pedido con capturas de MyFitnessPal; gemela de
 * CantidadAlimentoView.swift): gramos o porciones (la medida casera de la base o de «la mano»), las kcal y las macros en
 * vivo, a qué comida va y, si la comida sube o baja, si se compensa en las siguientes (D3, el mismo mecanismo de «Ajustar
 * esta comida»). Nada se guarda hasta «Agregar» o «Listo».
 */
@Composable
private fun ContenidoCantidad(
    modelo: ModeloApp,
    pedido: PedidoCantidad,
    fecha: String,
    opciones: Map<String, Int>,
    cancelar: AccionHoja? = null,
    izquierda: (@Composable () -> Unit)? = null,
    alTerminar: () -> Unit,
) {
    val c = MyPump.colores
    val alcance = LocalAlcanceApp.current
    val tactil = LocalHapticFeedback.current
    val guardados by modelo.ajustes.collectAsStateWithLifecycle()
    val diaPasado by modelo.diaPasado.collectAsStateWithLifecycle()
    val swaps by modelo.swaps.collectAsStateWithLifecycle()
    val que = pedido.que

    // ── Con qué abre (una sola vez) ──
    val existente = remember { modelo.ajustesVista[pedido.comidaId] }
    val inicio = remember {
        when (que) {
            is QueCantidad.Nuevo -> pedido.inicial?.let { (q, m) -> AgregadosComida.acotar(q, m) to m } ?: AgregadosComida.inicial(que.candidato)
            is QueCantidad.Agregado -> existente?.agregados?.firstOrNull { it.ts == que.ts }?.let { it.cantidad to CuentasCantidad.medidaDe(it) }
                ?: (100.0 to AgregadosComida.Medida.GRAMO)
            is QueCantidad.DelPlan -> {
                val plan = modelo.comidasParaAjustar(opciones).firstOrNull { it.id == pedido.comidaId }?.alimentos?.getOrNull(que.i)
                val hoy = modelo.diaAjustado(opciones)[pedido.comidaId]?.alimentos?.getOrNull(que.i)
                (hoy?.qty ?: plan?.qty ?: 0.0) to AgregadosComida.Medida(plan?.unidad ?: "g", 1.0)
            }
        }
    }
    val ts = remember { if (que is QueCantidad.Agregado) que.ts else CuentasCantidad.nuevoTs(existente) }
    var comidaId by rememberSaveable { mutableStateOf(pedido.comidaId) }
    var cantidad by rememberSaveable { mutableStateOf(inicio.first) }
    var medidaNombre by rememberSaveable { mutableStateOf(inicio.second.nombre) }
    var medidaGramos by rememberSaveable { mutableStateOf(inicio.second.gramos) }
    var texto by rememberSaveable { mutableStateOf(Formato.decimal(inicio.first)) }
    var compensar by rememberSaveable { mutableStateOf(existente?.compensar ?: true) }
    // D2: hasta que no se toca, la cantidad de hoy no queda puesta a mano (puede venir escalada por las kcal sumadas).
    var tocado by rememberSaveable { mutableStateOf(false) }
    var aviso by remember { mutableStateOf<String?>(null) }
    val medida = AgregadosComida.Medida(medidaNombre, medidaGramos)

    // ── La cuenta ──
    val comidas = remember(guardados, diaPasado, swaps, opciones) { modelo.comidasParaAjustar(opciones) }
    val delPlan: Pair<Int, Alimento>? = (que as? QueCantidad.DelPlan)?.let { d ->
        comidas.firstOrNull { it.id == comidaId }?.alimentos?.getOrNull(d.i)?.let { d.i to it }
    }
    val candidato: AgregadosComida.Candidato? = when (que) {
        is QueCantidad.Nuevo -> que.candidato
        is QueCantidad.Agregado -> modelo.ajustesVista[comidaId]?.agregados?.firstOrNull { it.ts == que.ts }?.candidato
        is QueCantidad.DelPlan -> null
    }
    val medidas: List<AgregadosComida.Medida> = when {
        candidato != null -> AgregadosComida.medidas(candidato)
        delPlan != null -> {
            val p = delPlan.second
            val propia = AgregadosComida.Medida(p.unidad ?: "g", 1.0)
            val casera = if (AjustePorciones.esPeso(p.unidad)) AgregadosComida.medidaCasera(p.nombre) else null
            listOfNotNull(propia, casera)
        }
        else -> listOf(medida)
    }
    val esMedidaDelPlan = delPlan != null && medida.gramos == 1.0 && medida.nombre == (delPlan.second.unidad ?: "g")
    val cantidadValida: Double = run {
        val p = delPlan?.second
        if (p != null && esMedidaDelPlan) minOf(maxOf(0.0, if (cantidad.isFinite()) cantidad else 0.0), AjustePorciones.maximoCantidad(p))
        else AgregadosComida.acotar(cantidad, medida)
    }
    val cantidadDelPlan: Double = delPlan?.second?.let { p ->
        if (esMedidaDelPlan) cantidadValida else minOf(AjustePorciones.redondear(cantidadValida * medida.gramos, p.unidad), AjustePorciones.maximoCantidad(p))
    } ?: 0.0
    val agregadoNuevo = candidato?.let { AgregadosComida.agregado(it, cantidad, medida, ts) }
    val borrador: AjusteComida = run {
        var a = CuentasCantidad.base(modelo, comidaId, opciones).copy(compensar = compensar)
        when (que) {
            is QueCantidad.Nuevo -> if (agregadoNuevo != null) a = a.copy(agregados = a.agregados + agregadoNuevo)
            is QueCantidad.Agregado -> if (agregadoNuevo != null) a = a.copy(agregados = a.agregados.map { if (it.ts == que.ts) agregadoNuevo else it })
            is QueCantidad.DelPlan -> if (tocado) {
                val k = que.i.toString()
                a = a.copy(cantidades = a.cantidades + (k to cantidadDelPlan), anclas = a.anclas - k)
            }
        }
        a
    }
    val ajustes = modelo.ajustesVista.toMutableMap().apply { if (borrador.neutro) remove(comidaId) else put(comidaId, borrador) }.toMap()
    val dia = AjustePorciones.dia(comidas, ajustes)
    val destino = AjustePorciones.destino(comidas, ajustes, comidaId)
    val nombreComida = comidas.firstOrNull { it.id == comidaId }?.nombre.orEmpty()
    val mostrado: Alimento? = agregadoNuevo?.alimento ?: delPlan?.let { (i, p) ->
        if (tocado) AjustePorciones.conCantidad(p, cantidadDelPlan) else dia[comidaId]?.alimentos?.getOrNull(i) ?: p
    }

    val puedeBajar = if (delPlan != null && esMedidaDelPlan) AjustePorciones.puedeBajar(cantidadValida) else AgregadosComida.bajar(cantidadValida, medida) < cantidadValida
    val puedeSubir = delPlan?.second?.let { p ->
        if (esMedidaDelPlan) AjustePorciones.puedeSubir(p, cantidadValida) else cantidadDelPlan < AjustePorciones.maximoCantidad(p)
    } ?: (AgregadosComida.subir(cantidadValida, medida) > cantidadValida)

    /** Desde la cantidad de AHORA (dos toques antes de que se redibuje no se pisan, como en «Ajustar esta comida»). */
    fun mover(sentido: Int) {
        val m = AgregadosComida.Medida(medidaNombre, medidaGramos)
        val p = delPlan?.second
        val propiaDelPlan = p != null && m.gramos == 1.0 && m.nombre == (p.unidad ?: "g")
        val nueva = if (p != null && propiaDelPlan) {
            val q = minOf(maxOf(0.0, if (cantidad.isFinite()) cantidad else 0.0), AjustePorciones.maximoCantidad(p))
            if (sentido > 0) AjustePorciones.subir(p, q) else AjustePorciones.bajar(p, q)
        } else {
            val q = AgregadosComida.acotar(cantidad, m)
            if (sentido > 0) AgregadosComida.subir(q, m) else AgregadosComida.bajar(q, m)
        }
        cantidad = nueva
        texto = Formato.decimal(nueva)
        tocado = true
        tactil.performHapticFeedback(HapticFeedbackType.SegmentTick)
    }

    /** Otra medida: la misma cantidad en gramos, contada en la nueva. */
    fun cambiarMedida(m: AgregadosComida.Medida) {
        val gramos = cantidadValida * medida.gramos
        val p = delPlan?.second
        val propiaDelPlan = p != null && m.gramos == 1.0 && m.nombre == (p.unidad ?: "g")
        val q = if (p != null && propiaDelPlan) minOf(AjustePorciones.redondear(gramos, p.unidad), AjustePorciones.maximoCantidad(p))
        else AgregadosComida.acotar(gramos / m.gramos, m)
        medidaNombre = m.nombre
        medidaGramos = m.gramos
        cantidad = q
        texto = Formato.decimal(q)
    }

    fun guardar() {
        val a = borrador
        if (que !is QueCantidad.DelPlan) {
            AgregadosComida.motivoNoEntra(modelo.ajustesVista + (comidaId to a), comidaId)?.let {
                aviso = it
                return
            }
        }
        tactil.performHapticFeedback(HapticFeedbackType.Confirm)
        val id = comidaId
        alcance.launch { modelo.ajustar(id, a.takeUnless { it.neutro }, opciones, fecha) }
        agregadoNuevo?.let { if (que is QueCantidad.Nuevo) modelo.recordarReciente(it) }
        alTerminar()
    }

    Column {
        EncabezadoHoja(
            when (que) {
                is QueCantidad.Nuevo -> "Agregar alimento"
                is QueCantidad.Agregado -> "Alimento agregado"
                is QueCantidad.DelPlan -> "Cantidad"
            },
            cancelar = cancelar,
            izquierda = izquierda,
        )
        if (mostrado == null) {
            Box(Modifier.heightIn(min = 280.dp)) {
                EstadoVacio(icono = Iconos.Cubiertos, titulo = "Este alimento ya no está en la comida", texto = "Cerrá y volvé a mirar tu dieta.")
            }
            return@Column
        }
        LazyColumn(
            modifier = Modifier.weight(1f, fill = false).testTag("cantidad-lista"),
            contentPadding = PaddingValues(start = Espacio.m, end = Espacio.m, top = Espacio.xs, bottom = Espacio.s),
            verticalArrangement = Arrangement.spacedBy(Espacio.m),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            item(key = "cabecera") { CabeceraCantidad(
                    mostrado, propio = candidato?.origen == AlimentoAgregado.Origen.PROPIO,
                    codigoBarras = candidato?.takeIf { it.origen == AlimentoAgregado.Origen.BARRAS }?.codigo,
                    modifier = Modifier.widthIn(max = 640.dp),
                ) }
            item(key = "cantidad") {
                Column(Modifier.widthIn(max = 640.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text("CANTIDAD", style = Letras.ceja, color = c.textoSecundario, modifier = Modifier.padding(horizontal = Espacio.m))
                    Tarjeta(espaciado = 12.dp) {
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                            BotonPaso(Iconos.Menos, "Menos", "cantidad-menos", habilitado = puedeBajar) { mover(-1) }
                            Row(
                                Modifier.weight(1f),
                                verticalAlignment = Alignment.Bottom,
                                horizontalArrangement = Arrangement.spacedBy(6.dp, Alignment.CenterHorizontally),
                            ) {
                                BasicTextField(
                                    value = texto,
                                    onValueChange = { t ->
                                        texto = t
                                        t.replace(',', '.').toDoubleOrNull()?.takeIf { it.isFinite() }?.let {
                                            cantidad = it
                                            tocado = true
                                        }
                                    },
                                    singleLine = true,
                                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                                    textStyle = Numeros.grande.copy(color = c.texto, fontSize = 30.sp, textAlign = TextAlign.End),
                                    cursorBrush = SolidColor(c.marcaTexto),
                                    modifier = Modifier
                                        .widthIn(min = 40.dp, max = 140.dp)
                                        .semantics { contentDescription = "Cantidad en ${medida.nombre}" }
                                        .testTag("cantidad-campo"),
                                )
                                Text(
                                    if (medida.nombre.contains(' ') || cantidadValida <= 1) medida.nombre else FormatoDieta.plural(medida.nombre),
                                    style = MaterialTheme.typography.titleMedium,
                                    color = c.textoSecundario,
                                    modifier = Modifier.padding(bottom = 4.dp),
                                )
                            }
                            BotonPaso(IconosAjuste.Mas, "Más", "cantidad-mas", habilitado = puedeSubir) { mover(1) }
                        }
                        if (medidas.size > 1) {
                            Segmentado(
                                opciones = medidas.map { m -> if (m.esGramo || m.gramos == 1.0) m.nombre else "${m.nombre} (${Formato.decimal(m.gramos)} g)" },
                                elegida = medidas.indexOfFirst { it.nombre == medida.nombre && it.gramos == medida.gramos }.coerceAtLeast(0),
                                alElegir = { cambiarMedida(medidas[it]) },
                                etiquetaPrueba = { "cantidad-medida-$it" },
                            )
                        }
                    }
                    val pie = delPlan?.second?.let { p -> "En el plan: ${FormatoDieta.cantidad(p.qty, p.unidad)}. ${if (modelo.enDiaPasado) "Vale solo para ese día." else "Vale solo por hoy."}" }
                        ?: if (medida.esGramo) {
                            PorcionCasera.referencia(mostrado.nombre, cantidadValida, "g", null)?.takeUnless { it.startsWith("libre") }?.let { "≈ $it" }
                        } else {
                            null
                        }
                    pie?.let { Text(it, style = Letras.caption, color = c.textoSecundario, modifier = Modifier.padding(horizontal = Espacio.m)) }
                }
            }
            item(key = "comida") {
                Column(Modifier.widthIn(max = 640.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Tarjeta(espaciado = 0.dp, relleno = 0.dp) {
                        if (que is QueCantidad.Nuevo) {
                            SelectorComida(
                                comidas.filter { modelo.ajustesVista[it.id]?.omitida != true },
                                elegida = comidaId,
                                alElegir = { id ->
                                    comidaId = id
                                    compensar = modelo.ajustesVista[id]?.compensar ?: true
                                    aviso = null
                                },
                            )
                        } else {
                            Row(Modifier.fillMaxWidth().padding(horizontal = Espacio.m, vertical = 14.dp), verticalAlignment = Alignment.CenterVertically) {
                                Text("Comida", style = MaterialTheme.typography.bodyLarge, modifier = Modifier.weight(1f))
                                Text(nombreComida, style = MaterialTheme.typography.bodyLarge, color = c.textoSecundario)
                            }
                        }
                        if (destino != null) {
                            Separador(Modifier.padding(start = Espacio.m))
                            FilaInterruptor(
                                titulo = "Compensar en ${TextosAjuste.conArticulo(destino.nombre)}",
                                detalle = TextosAjuste.compensacion(comidas, ajustes, comidaId, compensar),
                                prendido = compensar,
                                etiqueta = "cantidad-compensar",
                                alCambiar = { compensar = it },
                            )
                        }
                    }
                    Text(
                        if (destino == null) "No hay otra comida después para compensar: lo que sumes queda en el total del día."
                        else "Para mantener las macros del día, lo que esta comida sube (o baja) sale de las siguientes.",
                        style = Letras.caption, color = c.textoSecundario, modifier = Modifier.padding(horizontal = Espacio.m),
                    )
                }
            }
            val accion: Pair<String, () -> Unit>? = when (que) {
                is QueCantidad.Agregado -> "cantidad-borrar" to {
                    val id = comidaId
                    alcance.launch { modelo.borrarAgregado(id, que.ts, opciones) }
                    alTerminar()
                }
                is QueCantidad.DelPlan -> if (modelo.ajustesVista[comidaId]?.cantidades?.get(que.i.toString()) != null) {
                    "cantidad-como-plan" to {
                        val k = que.i.toString()
                        val a = borrador.copy(cantidades = borrador.cantidades - k, anclas = borrador.anclas - k)
                        val id = comidaId
                        alcance.launch { modelo.ajustar(id, a.takeUnless { it.neutro }, opciones, fecha) }
                        alTerminar()
                    }
                } else {
                    null
                }
                is QueCantidad.Nuevo -> null
            }
            accion?.let { (etiqueta, hacer) ->
                item(key = "accion") {
                    Box(
                        Modifier
                            .widthIn(max = 640.dp)
                            .fillMaxWidth()
                            .clip(RoundedCornerShape(14.dp))
                            .background(c.tarjeta)
                            .clickable(role = Role.Button, onClick = hacer)
                            .heightIn(min = 52.dp)
                            .testTag(etiqueta),
                        contentAlignment = Alignment.Center,
                    ) {
                        Text(
                            if (etiqueta == "cantidad-borrar") "Sacar de la comida" else "Como el plan",
                            style = MaterialTheme.typography.bodyLarge,
                            fontWeight = FontWeight.Medium,
                            color = if (etiqueta == "cantidad-borrar") c.peligro else c.marcaTexto,
                        )
                    }
                }
            }
        }
        Column(
            Modifier.fillMaxWidth().padding(horizontal = Espacio.m).padding(top = Espacio.xs, bottom = Espacio.m),
            verticalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            aviso?.let { Text(it, style = Letras.caption, color = c.alerta, modifier = Modifier.testTag("cantidad-aviso")) }
            BotonMarca(
                if (que is QueCantidad.Nuevo) "Agregar ${TextosAjuste.aLa(nombreComida)}" else "Listo",
                alTocar = ::guardar,
                modifier = Modifier.testTag("cantidad-confirmar"),
            )
        }
    }
}

/** El nombre, las kcal dentro del anillo de macros (el % de las kcal de cada una) y los gramos de cada macro. */
@Composable
private fun CabeceraCantidad(a: Alimento, propio: Boolean, codigoBarras: String?, modifier: Modifier) {
    val c = MyPump.colores
    val p = a.prot ?: 0.0
    val cb = a.carb ?: 0.0
    val g = a.fat ?: 0.0
    val total = maxOf(1.0, p * 4 + cb * 4 + g * 9)
    val partes = listOf(
        Triple("Carbohidratos", cb, cb * 4 / total) to c.carbohidrato,
        Triple("Grasas", g, g * 9 / total) to c.grasa,
        Triple("Proteínas", p, p * 4 / total) to c.proteina,
    )
    Tarjeta(modifier, espaciado = 12.dp) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(a.nombre, style = MaterialTheme.typography.titleMedium, modifier = Modifier.weight(1f, fill = false))
            if (propio) {
                Text(
                    "★ Tuyo",
                    style = Letras.caption2.copy(fontWeight = FontWeight.SemiBold),
                    color = c.marcaTexto,
                    modifier = Modifier.clip(CircleShape).background(c.marcaSuave).padding(horizontal = 6.dp, vertical = 2.dp),
                )
            }
        }
        // Escaneado (2.1, S3): de dónde salen los valores (la licencia de Open Food Facts pide nombrarla).
        codigoBarras?.let { codigo ->
            Row(
                Modifier.semantics(mergeDescendants = true) {}.testTag("cantidad-origen-barras"),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                Icon(IconosDieta.CodigoBarras, contentDescription = null, tint = c.textoSecundario, modifier = Modifier.size(14.dp))
                Text("Valores de Open Food Facts · $codigo", style = Letras.caption, color = c.textoSecundario)
            }
        }
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(18.dp)) {
            Box(
                Modifier
                    .size(86.dp)
                    .testTag("cantidad-kcal")
                    .clearAndSetSemantics { contentDescription = "${Formato.miles(a.kcal)} kcal" },
                contentAlignment = Alignment.Center,
            ) {
                val fondo = c.campo
                val colores = partes.map { it.second }
                val fracciones = partes.map { it.first.third }
                Canvas(Modifier.fillMaxSize()) {
                    val grosor = 9.dp.toPx()
                    val lado = size.minDimension - grosor
                    val tl = Offset((size.width - lado) / 2, (size.height - lado) / 2)
                    drawArc(fondo, 0f, 360f, false, tl, Size(lado, lado), style = Stroke(grosor))
                    var inicio = -90f
                    val hueco = if (fracciones.count { it > 0.001 } > 1) 6f else 0f
                    fracciones.forEachIndexed { i, f ->
                        val barrido = (f * 360).toFloat()
                        if (barrido > hueco) drawArc(colores[i], inicio + hueco / 2, barrido - hueco, false, tl, Size(lado, lado), style = Stroke(grosor, cap = StrokeCap.Round))
                        inicio += barrido
                    }
                }
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Text(Formato.miles(a.kcal), style = Numeros.mediano.copy(color = c.texto))
                    Text("kcal", style = MaterialTheme.typography.labelSmall, color = c.textoSecundario)
                }
            }
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                partes.forEach { (t, color) ->
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp), modifier = Modifier.semantics(mergeDescendants = true) {}) {
                        Box(Modifier.size(8.dp).clip(CircleShape).background(color))
                        Text(t.first, style = MaterialTheme.typography.bodyMedium, modifier = Modifier.weight(1f))
                        Text("${Formato.decimal(t.second)} g", style = MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.SemiBold).merge(Letras.cifras))
                        Text(
                            "${Formato.entero(t.third * 100)} %",
                            style = Letras.caption.merge(Letras.cifras),
                            color = c.textoSecundario,
                            textAlign = TextAlign.End,
                            modifier = Modifier.widthIn(min = 34.dp),
                        )
                    }
                }
            }
        }
    }
}

/** A qué comida va (solo al agregar): un menú con las comidas que hoy come. */
@Composable
private fun SelectorComida(comidas: List<AjustePorciones.ComidaDelDia>, elegida: String, alElegir: (String) -> Unit) {
    val c = MyPump.colores
    var abierto by remember { mutableStateOf(false) }
    Box {
        Row(
            Modifier
                .fillMaxWidth()
                .clickable(role = Role.DropdownList) { abierto = true }
                .padding(horizontal = Espacio.m, vertical = 14.dp)
                .testTag("cantidad-comida"),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text("Comida", style = MaterialTheme.typography.bodyLarge, modifier = Modifier.weight(1f))
            Text(comidas.firstOrNull { it.id == elegida }?.nombre.orEmpty(), style = MaterialTheme.typography.bodyLarge, color = c.marcaTexto, fontWeight = FontWeight.Medium)
            Icon(Iconos.Chevron, contentDescription = null, tint = c.marcaTexto, modifier = Modifier.padding(start = 4.dp).size(18.dp).rotate(90f))
        }
        DropdownMenu(expanded = abierto, onDismissRequest = { abierto = false }) {
            comidas.forEach { x ->
                DropdownMenuItem(
                    text = { Text(x.nombre, fontWeight = if (x.id == elegida) FontWeight.SemiBold else null) },
                    onClick = {
                        abierto = false
                        alElegir(x.id)
                    },
                    modifier = Modifier.testTag("cantidad-comida-${x.id}"),
                )
            }
        }
    }
}

/** Un código que Open Food Facts no tiene, o tiene incompleto. */
data class SinProductoCodigo(val codigo: String, val parcial: CodigoBarras.Parcial?)

/** El acceso al escáner, arriba de todo y bien visible (como en MyFitnessPal). */
@Composable
private fun TarjetaEscanear(alTocar: () -> Unit) {
    val c = MyPump.colores
    Row(
        Modifier
            .fillMaxWidth()
            .superficieTarjeta(radio = Radio.control + 4.dp)
            .clickable(role = Role.Button, onClickLabel = "escanear el código de barras", onClick = alTocar)
            .padding(horizontal = Espacio.s, vertical = Espacio.s)
            .semantics(mergeDescendants = true) {}
            .testTag("agregar-escanear"),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(Espacio.s),
    ) {
        Box(
            Modifier.size(46.dp).clip(RoundedCornerShape(Radio.miniatura)).background(c.marca),
            contentAlignment = Alignment.Center,
        ) {
            Icon(IconosDieta.CodigoBarras, contentDescription = null, tint = c.sobreMarca, modifier = Modifier.size(24.dp))
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text("Escanear código de barras", style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.SemiBold)
            Text("Apuntá al código del envase y se carga solo", style = Letras.caption, color = c.textoSecundario)
        }
        Icon(Iconos.Chevron, contentDescription = null, tint = c.textoTerciario, modifier = Modifier.size(16.dp))
    }
}

@Composable
private fun BuscandoCodigo(codigo: String) {
    val c = MyPump.colores
    Row(
        Modifier
            .fillMaxWidth()
            .superficieTarjeta(radio = Radio.control + 4.dp)
            .padding(horizontal = Espacio.m, vertical = Espacio.m)
            .semantics(mergeDescendants = true) {}
            .testTag("codigo-buscando"),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(Espacio.s),
    ) {
        CircularProgressIndicator(Modifier.size(22.dp), color = c.marcaTexto, strokeWidth = 2.5.dp)
        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text("Buscando el producto…", style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.Medium)
            Text("Código $codigo", style = Letras.caption, color = c.textoSecundario)
        }
    }
}

/** No está, o le faltan datos: por qué y las dos salidas (la foto de la etiqueta con la IA, o a mano). */
@Composable
private fun SinProductoTarjeta(sp: SinProductoCodigo, conIA: Boolean, alEtiqueta: () -> Unit, alAMano: () -> Unit, alOtro: () -> Unit) {
    val c = MyPump.colores
    Column(Modifier.fillMaxWidth().superficieTarjeta(radio = Radio.control + 4.dp)) {
        Column(
            Modifier.fillMaxWidth().padding(Espacio.m).semantics(mergeDescendants = true) {}.testTag("codigo-sin-producto"),
            verticalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espacio.xs)) {
                Icon(IconosDieta.CodigoBarras, contentDescription = null, tint = c.texto, modifier = Modifier.size(20.dp))
                Text(
                    if (sp.parcial == null) "No encontramos este producto" else "Le faltan datos a este producto",
                    style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold,
                )
            }
            Text(
                sp.parcial?.texto ?: "Todavía no está en Open Food Facts, la base de productos que usamos.",
                style = MaterialTheme.typography.bodyMedium, color = c.textoSecundario,
            )
            Text("Código ${sp.codigo}", style = Letras.caption, color = c.textoSecundario)
        }
        if (conIA) {
            Separador()
            FilaAccionCodigo(IconosDieta.Escanear, "Escanear la etiqueta", "Sacale una foto a la tabla nutricional y se completa solo", "codigo-etiqueta", alEtiqueta)
        }
        Separador()
        FilaAccionCodigo(IconosDieta.AMano, "Cargarlo a mano", null, "codigo-a-mano", alAMano)
        Separador()
        FilaAccionCodigo(IconosDieta.CodigoBarras, "Escanear otro código", null, "codigo-otro", alOtro, secundaria = true)
    }
}

@Composable
private fun FilaAccionCodigo(icono: ImageVector, titulo: String, detalle: String?, etiqueta: String, alTocar: () -> Unit, secundaria: Boolean = false) {
    val c = MyPump.colores
    Row(
        Modifier
            .fillMaxWidth()
            .clickable(role = Role.Button, onClick = alTocar)
            .heightIn(min = 52.dp)
            .padding(horizontal = Espacio.m, vertical = 10.dp)
            .semantics(mergeDescendants = true) {}
            .testTag(etiqueta),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(Espacio.s),
    ) {
        Icon(icono, contentDescription = null, tint = if (secundaria) c.textoSecundario else c.marcaTexto, modifier = Modifier.size(22.dp))
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(
                titulo, style = MaterialTheme.typography.bodyLarge,
                fontWeight = if (secundaria) FontWeight.Normal else FontWeight.SemiBold,
                color = if (secundaria) c.textoSecundario else c.marcaTexto,
            )
            detalle?.let { Text(it, style = Letras.caption, color = c.textoSecundario) }
        }
    }
}

@Composable
private fun TituloAgregar(texto: String) {
    Text(
        texto.uppercase(),
        style = Letras.ceja,
        color = MyPump.colores.textoSecundario,
        modifier = Modifier.padding(start = Espacio.xs, top = Espacio.s, bottom = 2.dp),
    )
}

@Composable
private fun AvisoAgregar(texto: String) {
    val c = MyPump.colores
    Text(
        texto,
        style = Letras.caption,
        color = c.alerta,
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(Radio.control))
            .background(c.alerta.copy(alpha = 0.12f))
            .padding(Espacio.s)
            .testTag("agregar-aviso"),
    )
}

/** Un alimento de la base (o propio): las kcal cada 100 g y su medida casera. */
@Composable
private fun FilaBase(a: AlimentoBase, alTocar: () -> Unit) {
    val c = MyPump.colores
    val medida = AgregadosComida.medidas(AgregadosComida.Candidato(a)).drop(1).firstOrNull()
    Row(
        Modifier
            .fillMaxWidth()
            .superficieTarjeta(radio = Radio.control + 4.dp)
            .clickable(role = Role.Button, onClick = alTocar)
            .padding(horizontal = Espacio.s, vertical = 10.dp)
            .semantics(mergeDescendants = true) {}
            .testTag("agregar-alimento"),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(Espacio.s),
    ) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(a.nombre, style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.Medium, modifier = Modifier.weight(1f, fill = false))
                if (a.esPropio) {
                    Text(
                        "★ Tuyo",
                        style = Letras.caption2.copy(fontWeight = FontWeight.SemiBold),
                        color = c.marcaTexto,
                        maxLines = 1,
                        modifier = Modifier.clip(CircleShape).background(c.marcaSuave).padding(horizontal = 6.dp, vertical = 2.dp),
                    )
                }
            }
            Text(
                "${Formato.miles(a.kcal)} kcal cada 100 g" + (medida?.let { " · 1 ${it.nombre} ≈ ${Formato.decimal(it.gramos)} g" } ?: ""),
                style = MaterialTheme.typography.bodyMedium,
                color = c.textoSecundario,
            )
            Text(FormatoDieta.macros(a.prot, a.carb, a.fat, c.proteina, c.carbohidrato, c.grasa), style = Letras.caption.merge(Letras.cifras), color = c.textoSecundario)
        }
        Icon(Iconos.Chevron, contentDescription = null, tint = c.textoTerciario, modifier = Modifier.size(18.dp))
    }
}

/** Un reciente: tocarlo abre la cantidad con la de la última vez; el «+» lo suma de una. */
@Composable
private fun FilaReciente(r: AlimentoAgregado, i: Int, alTocar: () -> Unit, alSumar: () -> Unit) {
    val c = MyPump.colores
    Row(
        Modifier.fillMaxWidth().superficieTarjeta(radio = Radio.control + 4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(
            Modifier
                .weight(1f)
                .clickable(role = Role.Button, onClick = alTocar)
                .padding(horizontal = Espacio.s, vertical = 10.dp)
                .semantics(mergeDescendants = true) {}
                .testTag("reciente-$i"),
            verticalArrangement = Arrangement.spacedBy(3.dp),
        ) {
            Text(r.nombre, style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.Medium)
            Text("${FormatoDieta.cantidad(r.cantidad, r.unidad)} · ${Formato.miles(r.kcal)} kcal", style = MaterialTheme.typography.bodyMedium, color = c.textoSecundario)
        }
        Box(
            Modifier
                .size(48.dp)
                .clip(CircleShape)
                .clickable(role = Role.Button, onClick = alSumar)
                .semantics { contentDescription = "Agregar ${r.nombre}" }
                .testTag("reciente-agregar-$i"),
            contentAlignment = Alignment.Center,
        ) {
            Box(Modifier.size(34.dp).clip(CircleShape).background(c.marca), contentAlignment = Alignment.Center) {
                Icon(IconosAjuste.Mas, contentDescription = null, tint = c.sobreMarca, modifier = Modifier.size(18.dp))
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
            .testTag("buscar-agregar"),
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
