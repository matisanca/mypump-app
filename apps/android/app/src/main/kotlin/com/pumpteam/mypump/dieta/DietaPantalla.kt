package com.pumpteam.mypump.dieta

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.shrinkVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.foundation.text.TextAutoSize
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.pumpteam.mypump.datos.ModeloApp
import com.pumpteam.mypump.diseno.Alerta
import com.pumpteam.mypump.diseno.AnchoLectura
import com.pumpteam.mypump.diseno.BotonAlerta
import com.pumpteam.mypump.diseno.BotonSecundario
import com.pumpteam.mypump.diseno.Espacio
import com.pumpteam.mypump.diseno.EstadoVacio
import com.pumpteam.mypump.diseno.FormaMenu
import com.pumpteam.mypump.diseno.Formato
import com.pumpteam.mypump.diseno.Iconos
import com.pumpteam.mypump.diseno.MarcoPantalla
import com.pumpteam.mypump.diseno.MyPump
import com.pumpteam.mypump.diseno.Numeros
import com.pumpteam.mypump.diseno.Punto
import com.pumpteam.mypump.diseno.Segmentado
import com.pumpteam.mypump.diseno.Separador
import com.pumpteam.mypump.diseno.Tarjeta
import com.pumpteam.mypump.diseno.sinAbajo
import com.pumpteam.mypump.entreno.AnilloProgreso
import com.pumpteam.mypump.modelos.Alimento
import com.pumpteam.mypump.modelos.Comida
import com.pumpteam.mypump.modelos.Macros
import com.pumpteam.mypump.modelos.TipoDia
import com.pumpteam.mypump.raiz.BannerRevision
import com.pumpteam.mypump.raiz.LocalAlcanceApp
import com.pumpteam.mypump.reglas.AjustePorciones
import com.pumpteam.mypump.reglas.ConsumoDelDia
import com.pumpteam.mypump.reglas.FechaLocal
import com.pumpteam.mypump.reglas.MarcaComida
import com.pumpteam.mypump.reglas.PorcionCasera
import com.pumpteam.mypump.reglas.SwapLocal
import com.pumpteam.mypump.respaldo.OrigenRespaldo
import com.pumpteam.mypump.respaldo.PieRespaldo
import com.pumpteam.mypump.respaldo.RenglonFuentes
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlinx.coroutines.launch

/**
 * Dieta (DIE-01..07, DietaView.swift): lo consumido hoy contra el objetivo del día, con sus macros y el respaldo
 * científico, y cada comida con sus opciones A/B/C/D (se combinan entre comidas), los alimentos de la opción elegida y
 * «✓ Comí» / «✗ Salté» (D25, 27-oct: los clientes de 2.0.x no podían seguir lo que comían; en D10 se había sacado). Con
 * «Comí», los tildes por alimento descuentan lo que no comió (DIE-06).
 *
 * Con escritura (DIE-08..18): la mano con la porción casera, el reemplazo de un alimento ([HojaReemplazar], con el
 * alimento propio adentro) y la vuelta al del plan, y las comidas libres al pie ([ComidasLibresSeccion], solo con cuenta).
 *
 * Los ajustes de porciones del día (feedback del 20-oct): «Ajustar esta comida» abre [HojaAjustarComida] (sumar o restar
 * kcal, cantidades a mano, «Hoy no la como», compensar en la siguiente) y las tarjetas muestran las porciones de hoy.
 */
@Composable
fun DietaPantalla(modelo: ModeloApp) {
    val fase by modelo.fase.collectAsStateWithLifecycle()
    val dieta by modelo.dieta.collectAsStateWithLifecycle()
    val tipoDia by modelo.tipoDiaFlow.collectAsStateWithLifecycle()
    val swaps by modelo.swaps.collectAsStateWithLifecycle()
    val ajustes by modelo.ajustes.collectAsStateWithLifecycle()
    val sinRedEn by modelo.sinRedEn.collectAsStateWithLifecycle()
    // DIE-04: la opción elegida vive en memoria (y sobrevive a cambiar de pestaña o rotar); al abrir la app vuelve a A.
    var opciones by rememberSaveable { mutableStateOf(mapOf<String, Int>()) }
    val comidas = remember(dieta, tipoDia) { modelo.comidasDelDia }
    // «Comí» / «Salté» de hoy (D25). Con el día como clave: pasada la medianoche no quedan las de ayer.
    val marcasGuardadas by modelo.marcas.collectAsStateWithLifecycle()
    val libresDeHoy by modelo.comidasLibres.collectAsStateWithLifecycle()
    val hoy = FechaLocal.hoy()
    val marcas = remember(marcasGuardadas, hoy) { modelo.marcasDeHoy }
    // La opción que se ve de una comida: la que se eligió acá, si no la que comió («Comí»), si no la del ajuste de hoy, si
    // no A. Dentro de las que hay (si Mati vuelve a publicar con menos opciones, la del ajuste puede no existir). Se lee
    // al momento: los toques que llegan antes de recomponer (la lambda de la composición anterior) ven la de ahora.
    fun opcionVigente(c: Comida): Int =
        (opciones[c.id] ?: ConsumoDelDia.opcionDeLaMarca(c, modelo.marcasDeHoy[c.id]) ?: modelo.ajustesDeHoy[c.id]?.opcion ?: 0)
            .coerceIn(0, max(c.opciones.size - 1, 0))
    val vigentes = remember(comidas, opciones, ajustes, marcas) { comidas.associate { c -> c.id to opcionVigente(c) } }
    // El día con las opciones, los reemplazos y los ajustes de hoy: lo que dibujan las tarjetas y la cabecera.
    val dia = remember(comidas, vigentes, swaps, ajustes) { modelo.diaAjustado(vigentes) }
    // Lo comido hoy (DIE-07): las marcadas «Comí» con la opción de la marca, menos lo destildado, más las comidas libres.
    val consumo = remember(comidas, vigentes, swaps, ajustes, marcas, libresDeHoy) { modelo.consumo(vigentes) }
    var ajustando by rememberSaveable { mutableStateOf<String?>(null) }
    val objetivo = remember(dieta, tipoDia) { modelo.objetivo }
    val tipos = dieta?.estructura?.tiposDia.orEmpty()
    val alcance = LocalAlcanceApp.current
    // ── Dieta con escritura (DIE-08..18) ──
    val esDemo by modelo.esDemo.collectAsStateWithLifecycle()
    // Las manos abiertas ("comida|opción|alimento") y la posición que se reemplaza o se vuelve al plan.
    var porciones by rememberSaveable { mutableStateOf(setOf<String>()) }
    var reemplazando by rememberSaveable { mutableStateOf<String?>(null) }
    var revirtiendo by rememberSaveable { mutableStateOf<String?>(null) }
    val libres = rememberEstadoComidasLibres(modelo)
    var recargando by remember { mutableStateOf(false) }

    // Elegir otra opción de una comida (el selector, o «Ver la opción X» de una comida marcada).
    fun elegir(c: Comida, nueva: Int) {
        opciones = opciones + (c.id to nueva)
        // Marcada «Comí» (D25): mirar otra opción no toca el ajuste. Lo comido es la opción de la marca, con sus porciones
        // de hoy (las cantidades a mano no se descartan por mirar).
        if (modelo.marcasDeHoy[c.id]?.estado == MarcaComida.Estado.COMIDO) return
        // Las cantidades a mano eran de la otra opción y se descartan (las kcal sumadas o restadas, «no la como» y
        // compensar siguen).
        val a = modelo.ajustesDeHoy[c.id]
        if (a != null) {
            if (a.opcion != nueva) {
                val vistas = vigentes + (c.id to nueva)
                alcance.launch { modelo.ajustar(c.id, a.copy(opcion = nueva, cantidades = emptyMap(), anclas = emptyMap()), vistas) }
            }
        } else {
            // Sin ajuste en esta comida, igual cambian las kcal del día: el resumen de los ajustes se rehace.
            alcance.launch { modelo.verOpcion(c.id, nueva) }
        }
    }

    fun recargar() {
        alcance.launch {
            recargando = true
            try {
                modelo.cargar()
            } finally {
                recargando = false
            }
        }
    }

    MarcoPantalla(
        "Dieta",
        acciones = {
            if (tipos.size > 1) SelectorTipoDia(tipos, elegido = tipoDia ?: tipos[0].id, alElegir = { modelo.tipoDia = it })
        },
    ) { relleno ->
        Box(Modifier.padding(relleno.sinAbajo()).fillMaxSize()) {
            when {
                fase == ModeloApp.Fase.LISTO && comidas.isNotEmpty() -> {
                    val elegidas = ModeloApp.sumar(dia.values.flatMap { it.alimentos })
                    Recargable(recargando, ::recargar) {
                        LazyColumn(
                            modifier = Modifier.fillMaxSize().testTag("dieta-lista"),
                            contentPadding = PaddingValues(start = Espacio.m, end = Espacio.m, top = Espacio.xxs, bottom = Espacio.xl + relleno.calculateBottomPadding()),
                            verticalArrangement = Arrangement.spacedBy(Espacio.m),
                            horizontalAlignment = Alignment.CenterHorizontally,
                        ) {
                            item(key = "cabecera") {
                                Cabecera(objetivo, consumo, elegidas, Modifier.widthIn(max = AnchoLectura), conAjustes = modelo.ajustesDeHoy.isNotEmpty())
                            }
                            item(key = "banner") { BannerRevision(modelo, Modifier.widthIn(max = AnchoLectura)) }
                            itemsIndexed(comidas, key = { i, c -> "$i-${c.id}" }) { n, c ->
                                val o = vigentes[c.id] ?: 0
                                TarjetaComida(
                                    modelo = modelo,
                                    comida = c,
                                    numero = n + 1,
                                    opcion = o,
                                    swaps = swaps,
                                    alElegir = { nueva -> elegir(c, nueva) },
                                    marca = marcas[c.id],
                                    // Con el alcance de la app: la marca sale aunque se cambie de pestaña al toque.
                                    alMarcar = { e ->
                                        // La opción que se ve queda fija: si venía de la marca, desmarcar o «Salté» no la
                                        // cambian (en la web tampoco salta) y un «Comí» después es con la que se mira.
                                        val actual = opcionVigente(c)
                                        if (c.id !in opciones) opciones = opciones + (c.id to actual)
                                        alcance.launch { modelo.marcar(c.id, e, actual) }
                                    },
                                    alTildar = { i -> alcance.launch { modelo.alternarAlimento(c.id, i) } },
                                    modifier = Modifier.widthIn(max = AnchoLectura),
                                    porciones = porciones,
                                    alTocarMano = { k -> porciones = if (k in porciones) porciones - k else porciones + k },
                                    alReemplazar = { reemplazando = it },
                                    alRevertir = { revirtiendo = it },
                                    ajustada = dia[c.id],
                                    propia = ajustes.containsKey(c.id) && modelo.ajustesDeHoy.containsKey(c.id),
                                    alAjustar = { ajustando = c.id },
                                )
                            }
                            // Las comidas libres, solo con cuenta: en la demo no están (como en la web).
                            if (!esDemo && modelo.token != null) {
                                item(key = "comidas-libres") { ComidasLibresSeccion(modelo, libres, Modifier.widthIn(max = AnchoLectura)) }
                            }
                            item(key = "pie") { PieRespaldo(OrigenRespaldo.DIETA, Modifier.widthIn(max = AnchoLectura).padding(top = Espacio.xxs)) }
                        }
                    }
                    if (libres.analizando) AnalizandoFoto("Analizando el plato…")
                }
                fase == ModeloApp.Fase.LISTO && ModeloApp.Parte.DIETA in sinRedEn ->
                    EstadoVacio(
                        icono = Iconos.SinWifi,
                        titulo = "No pudimos traer tu dieta",
                        texto = "Se cortó la conexión. Probá de nuevo cuando tengas señal.",
                        accion = { BotonSecundario("Reintentar", alTocar = ::recargar, compacto = true, cargando = recargando) },
                    )
                fase == ModeloApp.Fase.LISTO ->
                    // D11: sin una dieta usable no se muestra la de ejemplo como si fuera del cliente.
                    Recargable(recargando, ::recargar) {
                        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(top = 80.dp)) {
                            EstadoVacio(
                                icono = Iconos.Cubiertos,
                                titulo = "Todavía no hay plan de comidas",
                                texto = "Cuando Mati publique tu dieta, la vas a ver acá.",
                                modifier = Modifier.testTag("dieta-vacia"),
                            )
                        }
                    }
                fase == ModeloApp.Fase.CARGANDO ->
                    CircularProgressIndicator(Modifier.align(Alignment.Center), color = MyPump.colores.marcaTexto)
                fase == ModeloApp.Fase.SIN_SERVICIO ->
                    EstadoVacio(
                        icono = Iconos.SinWifi,
                        titulo = "Sin conexión",
                        texto = "No pudimos traer tu plan. Probá de nuevo cuando tengas señal.",
                        accion = { BotonSecundario("Reintentar", alTocar = ::recargar, compacto = true, cargando = recargando) },
                    )
                else ->
                    EstadoVacio(icono = Iconos.Link, titulo = "Entrá con tu link", texto = "Abrí el link que te pasó Mati para ver tu plan.")
            }
        }
    }

    // ── Dieta con escritura: las hojas y los avisos, afuera de la lista perezosa ──
    val aReemplazar = reemplazando?.let { posicion(comidas, it) }
    val aRevertir = revirtiendo?.let { posicion(comidas, it) }
    // El plan cambió mientras estaba abierta (tirar para actualizar, otro tipo de día): esa posición ya no existe.
    LaunchedEffect(reemplazando != null && aReemplazar == null) { if (reemplazando != null && aReemplazar == null) reemplazando = null }
    LaunchedEffect(revirtiendo != null && aRevertir == null) { if (revirtiendo != null && aRevertir == null) revirtiendo = null }
    aReemplazar?.let { p ->
        HojaReemplazar(
            modelo,
            original = p.original,
            alElegir = { food -> alcance.launch { modelo.sustituir(p.original, food, p.comidaId, p.opt, p.idx) } },
            alCerrar = { reemplazando = null },
        )
    }
    aRevertir?.let { p ->
        ConfirmarVolverAlPlan(
            original = p.original,
            mostrado = modelo.efectivo(p.original, p.comidaId, p.opt, p.idx).alimento,
            alVolver = {
                revirtiendo = null
                alcance.launch { modelo.revertir(p.comidaId, p.opt, p.idx) }
            },
            alCancelar = { revirtiendo = null },
        )
    }
    HojasComidasLibres(modelo, libres)
    // La comida que se ajusta ya no está (tirar para actualizar, otro tipo de día): la hoja se cierra.
    LaunchedEffect(ajustando, comidas) { if (ajustando != null && comidas.none { it.id == ajustando }) ajustando = null }
    ajustando?.let { id ->
        HojaAjustarComida(modelo, comidaId = id, opciones = vigentes, alCerrar = { ajustando = null })
    }
}

/** Una posición del plan ("comida|opción|alimento") con el alimento del plan que hay ahí. */
private class Posicion(val comidaId: String, val opt: Int, val idx: Int, val original: Alimento)

private fun clavePosicion(comidaId: String, opt: Int, idx: Int) = "$comidaId|$opt|$idx"

private fun posicion(comidas: List<Comida>, clave: String): Posicion? {
    val partes = clave.split('|')
    if (partes.size < 3) return null
    val idx = partes[partes.size - 1].toIntOrNull() ?: return null
    val opt = partes[partes.size - 2].toIntOrNull() ?: return null
    val comidaId = partes.dropLast(2).joinToString("|")
    val a = comidas.firstOrNull { it.id == comidaId }?.opciones?.getOrNull(opt)?.alimentos?.getOrNull(idx) ?: return null
    return Posicion(comidaId, opt, idx, a)
}

/** "¿Volver al alimento del plan?" (el `confirmationDialog` de iOS): al tocar la marca de un reemplazo. */
@Composable
private fun ConfirmarVolverAlPlan(original: Alimento, mostrado: Alimento, alVolver: () -> Unit, alCancelar: () -> Unit) {
    Alerta(
        titulo = "¿Volver al alimento del plan?",
        mensaje = "Hoy estás comiendo ${mostrado.nombre}.",
        botones = listOf(
            BotonAlerta("Cancelar", etiqueta = "cancelar-volver", cancelar = true, alTocar = alCancelar),
            BotonAlerta("Volver a ${original.nombre}", etiqueta = "volver-al-plan", alTocar = alVolver),
        ),
        alDescartar = alCancelar,
        modifier = Modifier.testTag("confirmar-volver"),
    )
}

/** Tirar para actualizar (en la demo no hace nada: no hay red). */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun Recargable(recargando: Boolean, alRecargar: () -> Unit, contenido: @Composable () -> Unit) {
    PullToRefreshBox(isRefreshing = recargando, onRefresh = alRecargar, modifier = Modifier.fillMaxSize()) { contenido() }
}

/** DIE-01: el tipo de día (entreno/descanso) en dietas con `tipos_dia`; se guarda para todo el teléfono (`mypump_tipo_dia`). */
@Composable
private fun SelectorTipoDia(tipos: List<TipoDia>, elegido: String, alElegir: (String) -> Unit) {
    var abierto by remember { mutableStateOf(false) }
    val actual = tipos.firstOrNull { it.id == elegido } ?: tipos[0]
    Box {
        TextButton(onClick = { abierto = true }, modifier = Modifier.testTag("tipo-dia")) {
            Icon(Iconos.Calendario, contentDescription = null, modifier = Modifier.size(18.dp))
            Spacer(Modifier.width(6.dp))
            Text(actual.nombre ?: actual.id, fontWeight = FontWeight.SemiBold)
        }
        DropdownMenu(expanded = abierto, onDismissRequest = { abierto = false }, shape = FormaMenu, containerColor = MyPump.colores.tarjeta, shadowElevation = 12.dp) {
            for (t in tipos) {
                DropdownMenuItem(
                    text = { Text(t.nombre ?: t.id, fontWeight = if (t.id == actual.id) FontWeight.SemiBold else FontWeight.Normal) },
                    onClick = {
                        alElegir(t.id)
                        abierto = false
                    },
                    leadingIcon = {
                        if (t.id == actual.id) Icon(Iconos.Verificado, contentDescription = null, tint = MyPump.colores.marcaTexto, modifier = Modifier.size(18.dp))
                    },
                    modifier = Modifier.testTag("tipo-dia-${t.id}"),
                )
            }
        }
    }
}

/**
 * Lo consumido hoy contra el objetivo del día (DIE-07, D25; la `Cabecera` de iOS): el anillo se llena con las kcal de las
 * comidas marcadas «Comí» (con lo que destildó, las porciones de hoy y las comidas libres) y cada macro con su barra.
 * Abajo, cuántas comidas van, cuánto suman las opciones elegidas contra el objetivo y el respaldo (DIE-03).
 */
@Composable
private fun Cabecera(objetivo: Macros, consumo: ConsumoDelDia.Consumo, elegidas: Macros, modifier: Modifier = Modifier, conAjustes: Boolean = false) {
    val c = MyPump.colores
    val meta = objetivo.kcal ?: 0.0
    val delta = if (meta > 0) ((elegidas.kcal ?: 0.0) - meta) / meta * 100 else 0.0
    val macros = listOf(
        Triple("Proteínas", consumo.prot, objetivo.prot) to c.proteina,
        Triple("Carbos", consumo.carb, objetivo.carb) to c.carbohidrato,
        Triple("Grasas", consumo.fat, objetivo.fat) to c.grasa,
    )
    Tarjeta(modifier.testTag("dieta-cabecera"), espaciado = Espacio.m) {
        // En el teléfono, el anillo arriba y los macros en tres cajas de color debajo, como en el iPhone: lado a lado salía
        // en los teléfonos anchos y la cabecera no se parecía a la de iOS (15-oct). En la tablet, lado a lado si entra (el
        // ancho que hace falta crece con la escala de la letra).
        val escala = LocalDensity.current.fontScale
        BoxWithConstraints(Modifier.fillMaxWidth()) {
            if (maxWidth >= 520.dp * max(1f, escala)) {
                Row(horizontalArrangement = Arrangement.spacedBy(20.dp), verticalAlignment = Alignment.CenterVertically) {
                    AnilloConsumido(consumo.kcal, meta)
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        for ((m, color) in macros) FilaMacro(m.first, m.second, m.third, color)
                    }
                }
            } else if (escala >= ESCALA_APILADA) {
                // Letra muy grande: ni las tres columnas entran (quedaban en "Proteí", "Carbo"). Van una debajo de la otra,
                // como en iOS con la letra de accesibilidad.
                Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(18.dp)) {
                    AnilloConsumido(consumo.kcal, meta, lado = 200.dp)
                    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                        for ((m, color) in macros) ColumnaMacro(m.first, m.second, m.third, color, Modifier.fillMaxWidth())
                    }
                }
            } else {
                Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(18.dp)) {
                    AnilloConsumido(consumo.kcal, meta)
                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        for ((m, color) in macros) ColumnaMacro(m.first, m.second, m.third, color, Modifier.weight(1f))
                    }
                }
            }
        }
        RenglonComidas(consumo)
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.testTag("opciones-elegidas")) {
            val dentro = abs(delta) <= 5
            Icon(
                if (dentro) Iconos.Verificado else Iconos.Alerta,
                contentDescription = null,
                tint = if (dentro) c.exito else c.alerta,
                modifier = Modifier.size(18.dp),
            )
            Text(
                buildAnnotatedString {
                    append(if (conAjustes) "Con tus ajustes de hoy: " else "Con las opciones elegidas: ")
                    withStyle(SpanStyle(fontWeight = FontWeight.Bold)) { append("${Formato.miles(elegidas.kcal)} kcal") }
                    // Con espacio duro: el "%)" no queda solo en el renglón de abajo.
                    if (abs(delta) >= 0.5) append(" (${if (delta > 0) "+" else ""}${Formato.entero(delta)} %)")
                },
                style = MaterialTheme.typography.bodySmall,
            )
        }
        RenglonFuentes()
    }
}

/** Desde esta escala de letra la cabecera, el total de Dieta y «Comí / Salté» van apilados (lado a lado se cortaban). */
private const val ESCALA_APILADA = 1.5f

/** Las kcal consumidas hoy en un anillo que se llena hasta el objetivo (pasado, queda lleno). */
@Composable
private fun AnilloConsumido(kcal: Double, meta: Double, lado: Dp = 132.dp) {
    val c = MyPump.colores
    AnilloProgreso(
        fraccion = if (meta > 0) kcal / meta else 0.0,
        modifier = Modifier
            .size(lado)
            // TalkBack: «Consumido hoy, 544 de 2.373 kcal» (el `accessibilityValue` de iOS, que leen también las pruebas).
            .semantics(mergeDescendants = true) {
                contentDescription = "Consumido hoy"
                stateDescription = if (meta > 0) "${Formato.miles(kcal)} de ${Formato.miles(meta)} kcal" else "${Formato.miles(kcal)} kcal"
            }
            .testTag("consumido-kcal"),
        grosor = 14.dp,
        color = c.marca,
    ) {
        Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.padding(horizontal = 18.dp)) {
            BasicText(
                Formato.miles(kcal),
                style = Numeros.grande.copy(color = c.texto),
                maxLines = 1,
                autoSize = TextAutoSize.StepBased(minFontSize = 20.sp, maxFontSize = 36.sp),
            )
            Text(
                if (meta > 0) "de ${Formato.miles(meta)} kcal" else "kcal hoy",
                style = MaterialTheme.typography.labelSmall,
                color = c.textoSecundario,
                maxLines = 1,
            )
        }
    }
}

/** «Comiste 1 de 4 comidas · salteaste 1», o cómo se usa mientras no marcó ninguna. */
@Composable
private fun RenglonComidas(consumo: ConsumoDelDia.Consumo) {
    val c = MyPump.colores
    val ninguna = consumo.hechas + consumo.salteadas == 0
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        modifier = Modifier.semantics(mergeDescendants = true) {}.testTag("consumido-comidas"),
    ) {
        Icon(if (ninguna) Iconos.Toque else Iconos.Cubiertos, contentDescription = null, tint = c.textoSecundario, modifier = Modifier.size(18.dp))
        Text(
            if (ninguna) {
                AnnotatedString("Tocá «Comí» en cada comida y acá se va sumando lo que comés.")
            } else {
                buildAnnotatedString {
                    append("Comiste ")
                    withStyle(SpanStyle(fontWeight = FontWeight.Bold)) { append("${consumo.hechas} de ${consumo.comidas}") }
                    append(if (consumo.comidas == 1) " comida" else " comidas")
                    if (consumo.salteadas > 0) append(" · salteaste ${consumo.salteadas}")
                }
            },
            style = MaterialTheme.typography.bodySmall,
            color = c.textoSecundario,
        )
    }
}

/** Lo consumido de un macro contra el objetivo, con una barra en su color. */
@Composable
private fun BarraMacro(consumido: Double, objetivo: Double?, color: Color, modifier: Modifier = Modifier) {
    val o = objetivo ?: 0.0
    val fraccion by animateFloatAsState(if (o > 0) (consumido / o).toFloat().coerceIn(0f, 1f) else 0f, label = "barra-macro")
    Box(modifier.fillMaxWidth().height(6.dp).clip(CircleShape).background(color.copy(alpha = 0.18f))) {
        if (fraccion > 0f) Box(Modifier.fillMaxHeight().fillMaxWidth(fraccion).clip(CircleShape).background(color))
    }
}

/** Un macro en fila (cabecera ancha): nombre, «41 / 175 g» y la barra. */
@Composable
private fun FilaMacro(nombre: String, consumido: Double, objetivo: Double?, color: Color) {
    val c = MyPump.colores
    Column(
        Modifier.semantics(mergeDescendants = true) {
            contentDescription = nombre
            stateDescription = "${Formato.entero(consumido)} de ${Formato.entero(objetivo)} g"
        },
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Punto(color)
            Text(nombre, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Medium, maxLines = 1, modifier = Modifier.weight(1f))
            Text(
                buildAnnotatedString {
                    withStyle(Numeros.mediano.toSpanStyle()) { append("${Formato.entero(consumido)}") }
                    withStyle(MaterialTheme.typography.bodySmall.toSpanStyle().copy(color = c.textoSecundario)) { append(" / ${Formato.entero(objetivo)} g") }
                },
                maxLines = 1,
            )
        }
        BarraMacro(consumido, objetivo, color)
    }
}

/** Un macro en columna (cabecera angosta): nombre, lo consumido grande, el objetivo y la barra. */
@Composable
private fun ColumnaMacro(nombre: String, consumido: Double, objetivo: Double?, color: Color, modifier: Modifier = Modifier) {
    Column(
        modifier = modifier
            .clip(RoundedCornerShape(12.dp))
            .background(color.copy(alpha = 0.08f))
            .padding(10.dp)
            .semantics(mergeDescendants = true) {
                contentDescription = nombre
                stateDescription = "${Formato.entero(consumido)} de ${Formato.entero(objetivo)} g"
            },
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp)) {
            Punto(color, 8.dp)
            Text(nombre, style = MaterialTheme.typography.labelSmall, fontWeight = FontWeight.SemiBold, color = MyPump.colores.textoSecundario, maxLines = 1)
        }
        Text("${Formato.entero(consumido)} g", style = Numeros.mediano, maxLines = 1)
        Text("de ${Formato.entero(objetivo)} g", style = MaterialTheme.typography.labelSmall, color = MyPump.colores.textoSecundario, maxLines = 1)
        BarraMacro(consumido, objetivo, color, Modifier.padding(top = 2.dp))
    }
}

/**
 * Una comida: encabezado con su total, el selector de opción (DIE-04), «Comí» / «Salté» (DIE-05) y los alimentos de la
 * opción elegida, con los tildes de lo que comió si la marcó «Comí» y se mira esa opción (DIE-06).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun TarjetaComida(
    modelo: ModeloApp,
    comida: Comida,
    numero: Int,
    opcion: Int,
    swaps: Map<String, SwapLocal>,
    alElegir: (Int) -> Unit,
    modifier: Modifier = Modifier,
    porciones: Set<String> = emptySet(),
    alTocarMano: (String) -> Unit = {},
    alReemplazar: (String) -> Unit = {},
    alRevertir: (String) -> Unit = {},
    /** Lo de hoy con los ajustes (null: como el plan). */
    ajustada: AjustePorciones.ComidaAjustada? = null,
    /** La ajustó el cliente (no solo le llega lo de otra). */
    propia: Boolean = false,
    alAjustar: () -> Unit = {},
    /** «Comí» / «Salté» de hoy (D25). */
    marca: MarcaComida? = null,
    alMarcar: (MarcaComida.Estado?) -> Unit = {},
    alTildar: (Int) -> Unit = {},
) {
    val c = MyPump.colores
    // Con los reemplazos como clave: un parámetro que no se usa no cuenta para recomponer, y la tarjeta seguía mostrando
    // el alimento del plan después de reemplazarlo (`efectivo` lee el modelo, no un estado de Compose).
    val alimentos = remember(comida, opcion, swaps) {
        (comida.opciones.getOrNull(opcion)?.alimentos ?: emptyList()).mapIndexed { i, a -> a to modelo.efectivo(a, comida.id, opcion, i) }
    }
    // Lo que se muestra: el reemplazo (si hay) con la cantidad del ajuste de hoy (si hay).
    val hoy = alimentos.mapIndexed { i, (_, e) -> ajustada?.alimentos?.getOrNull(i) ?: e.alimento }
    val omitida = ajustada?.omitida == true
    val total = ModeloApp.sumar(hoy)
    val nombreOpcion = comida.opciones.getOrNull(opcion)?.nombre ?: letra(opcion)
    // «Comí» / «Salté» (D25). La que hoy no come no se marca.
    val estado = if (omitida) null else marca?.estado
    // Los tildes por alimento son índices de la opción con que marcó «Comí»: solo se ven mirando esa opción (la web guardaba
    // el índice de la que se miraba contra la marcada y descontaba otro alimento).
    val oMarcada = if (omitida) null else ConsumoDelDia.opcionDeLaMarca(comida, marca)
    val excluidos = if (oMarcada == opcion) marca?.excluidos.orEmpty().toSet() else null
    val fondoIcono by animateColorAsState(
        when (estado) {
            MarcaComida.Estado.COMIDO -> c.marca
            MarcaComida.Estado.SALTADO -> c.campo
            null -> c.marcaSuave
        },
        label = "icono-comida",
    )
    Tarjeta(modifier.testTag("comida-${comida.id}"), espaciado = 14.dp) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            modifier = Modifier.semantics(mergeDescendants = true) {
                when (estado) {
                    MarcaComida.Estado.COMIDO -> stateDescription = "La comiste"
                    MarcaComida.Estado.SALTADO -> stateDescription = "La salteaste"
                    null -> {}
                }
            },
        ) {
            Box(Modifier.size(38.dp).clip(RoundedCornerShape(11.dp)).background(fondoIcono), contentAlignment = Alignment.Center) {
                Icon(
                    when (estado) {
                        MarcaComida.Estado.COMIDO -> Iconos.Tilde
                        MarcaComida.Estado.SALTADO -> Iconos.Cerrar
                        null -> iconoComida(comida.nombre)
                    },
                    contentDescription = null,
                    tint = when (estado) {
                        MarcaComida.Estado.COMIDO -> c.sobreMarca
                        MarcaComida.Estado.SALTADO -> c.textoSecundario
                        null -> c.marcaTexto
                    },
                    modifier = Modifier.size(20.dp),
                )
            }
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(1.dp)) {
                Text(comida.nombre ?: "Comida $numero", style = MaterialTheme.typography.titleMedium.copy(fontSize = 20.sp, lineHeight = 25.sp))
                Text(
                    "Opción $nombreOpcion · ${alimentos.size} ${if (alimentos.size == 1) "alimento" else "alimentos"}",
                    style = MaterialTheme.typography.bodySmall,
                    color = c.textoSecundario,
                    modifier = Modifier.testTag("resumen-${comida.id}"),
                )
            }
            Column(horizontalAlignment = Alignment.End) {
                Text(Formato.miles(total.kcal), style = Numeros.mediano)
                Text("kcal", style = MaterialTheme.typography.labelSmall, color = c.textoSecundario)
            }
        }
        if (comida.opciones.size > 1) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Text("Opción", style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Medium, color = c.textoSecundario)
                Segmentado(
                    opciones = comida.opciones.mapIndexed { i, op -> op.nombre ?: letra(i) },
                    elegida = opcion,
                    alElegir = alElegir,
                    etiquetaPrueba = { "opcion-${comida.id}-$it" },
                    modifier = Modifier.weight(1f),
                )
            }
        }
        if (!omitida) BotonesMarca(estado, comida.id, alMarcar)
        if (oMarcada != null) {
            if (excluidos != null) {
                val contado = hoy.filterIndexed { i, _ -> i !in excluidos }.sumOf { it.kcal ?: 0.0 }
                PistaMarca(
                    if (excluidos.isEmpty()) "Destildá lo que no comiste: solo cuenta lo tildado."
                    else "Cuenta lo tildado: ${Formato.miles(contado)} de ${Formato.miles(total.kcal)} kcal.",
                    Modifier.testTag("tildes-${comida.id}"),
                )
            } else {
                val comio = comida.opciones.getOrNull(oMarcada)?.nombre ?: letra(oMarcada)
                Column {
                    PistaMarca("Comiste la opción $comio. Para marcar qué dejaste, volvé a esa.", Modifier.testTag("tildes-${comida.id}"))
                    TextButton(
                        onClick = { alElegir(oMarcada) },
                        contentPadding = PaddingValues(horizontal = 4.dp),
                        modifier = Modifier.testTag("ver-opcion-${comida.id}"),
                    ) {
                        Text("Ver la opción $comio", style = MaterialTheme.typography.bodySmall, fontWeight = FontWeight.SemiBold, color = c.marcaTexto)
                    }
                }
            }
        }
        if (ajustada != null && hayQueMostrarAviso(ajustada, propia)) AvisoAjuste(ajustada, propia, Modifier.testTag("ajuste-aviso-${comida.id}"))
        if (!omitida) {
            TotalYAlimentos(comida, opcion, alimentos.map { it.first }, alimentos.map { it.second }, hoy, total, porciones, alTocarMano, alReemplazar, alRevertir, excluidos, alTildar)
        }
        Box(
            Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(12.dp))
                .background(c.marcaSuave.copy(alpha = c.marcaSuave.alpha * 0.6f))
                .clickable(role = Role.Button, onClick = alAjustar)
                .heightIn(min = 48.dp)
                .testTag("ajustar-${comida.id}"),
            contentAlignment = Alignment.Center,
        ) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Icon(IconosAjuste.Ajustar, contentDescription = null, tint = c.marcaTexto, modifier = Modifier.size(18.dp))
                Text(
                    if (propia) "Cambiar el ajuste" else "Ajustar esta comida",
                    style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold, color = c.marcaTexto,
                )
            }
        }
    }
}

/**
 * «✓ Comí» / «✗ Salté» de una comida (DIE-05, el `BotonesMarca` de iOS). Tocar el que está marcado lo desmarca, como en la
 * web. Con letra muy grande van uno debajo del otro.
 */
@Composable
private fun BotonesMarca(estado: MarcaComida.Estado?, comidaId: String, alElegir: (MarcaComida.Estado?) -> Unit) {
    val tactil = LocalHapticFeedback.current
    val tocar = { e: MarcaComida.Estado ->
        val nuevo = if (estado == e) null else e
        tactil.performHapticFeedback(if (nuevo == MarcaComida.Estado.COMIDO) HapticFeedbackType.Confirm else HapticFeedbackType.SegmentTick)
        alElegir(nuevo)
    }
    if (LocalDensity.current.fontScale >= ESCALA_APILADA) {
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            BotonMarca(MarcaComida.Estado.COMIDO, estado, comidaId, Modifier.fillMaxWidth(), tocar)
            BotonMarca(MarcaComida.Estado.SALTADO, estado, comidaId, Modifier.fillMaxWidth(), tocar)
        }
    } else {
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            BotonMarca(MarcaComida.Estado.COMIDO, estado, comidaId, Modifier.weight(1f), tocar)
            BotonMarca(MarcaComida.Estado.SALTADO, estado, comidaId, Modifier.weight(1f), tocar)
        }
    }
}

@Composable
private fun BotonMarca(e: MarcaComida.Estado, estado: MarcaComida.Estado?, comidaId: String, modifier: Modifier, alTocar: (MarcaComida.Estado) -> Unit) {
    val c = MyPump.colores
    val activo = estado == e
    val comi = e == MarcaComida.Estado.COMIDO
    val fondo by animateColorAsState(
        when {
            !activo -> c.campo
            comi -> c.marca
            else -> c.alerta.copy(alpha = 0.16f)
        },
        label = "fondo-marca",
    )
    val tinta = when {
        !activo -> c.texto.copy(alpha = 0.8f)
        comi -> c.sobreMarca
        else -> c.alerta
    }
    Row(
        modifier
            .heightIn(min = 48.dp)
            .clip(RoundedCornerShape(12.dp))
            .background(fondo)
            // TalkBack: «Comí, seleccionado, botón: tocá dos veces para desmarcar».
            .clickable(role = Role.Button, onClickLabel = if (activo) "desmarcar" else null) { alTocar(e) }
            .semantics { selected = activo }
            .testTag("${if (comi) "comi" else "salte"}-$comidaId")
            .padding(horizontal = 12.dp, vertical = 10.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterHorizontally),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        when {
            // El tilde y la cruz en un círculo lleno al marcar (el `.circle.fill` de iOS).
            activo && comi -> Icon(Iconos.TildeEnCirculo, contentDescription = null, tint = tinta, modifier = Modifier.size(20.dp))
            activo -> Box(Modifier.size(20.dp).clip(CircleShape).background(c.alerta), contentAlignment = Alignment.Center) {
                Icon(Iconos.Cerrar, contentDescription = null, tint = c.tarjeta, modifier = Modifier.size(13.dp))
            }
            else -> Icon(if (comi) Iconos.Tilde else Iconos.Cerrar, contentDescription = null, tint = tinta, modifier = Modifier.size(18.dp))
        }
        Text(if (comi) "Comí" else "Salté", style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold, color = tinta)
    }
}

/** La pista de los tildes debajo de «Comí / Salté». */
@Composable
private fun PistaMarca(texto: String, modifier: Modifier = Modifier) {
    val c = MyPump.colores
    Row(
        modifier.semantics(mergeDescendants = true) {},
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Icon(Iconos.Checklist, contentDescription = null, tint = c.textoSecundario, modifier = Modifier.size(18.dp))
        Text(texto, style = MaterialTheme.typography.bodySmall, color = c.textoSecundario)
    }
}

/** Los alimentos de la opción (con lo de hoy) y el total de macros: lo que no se muestra si hoy no la come. */
@Composable
private fun TotalYAlimentos(
    comida: Comida,
    opcion: Int,
    originales: List<Alimento>,
    efectivos: List<com.pumpteam.mypump.reglas.AlimentoEfectivo>,
    hoy: List<Alimento>,
    total: Macros,
    porciones: Set<String>,
    alTocarMano: (String) -> Unit,
    alReemplazar: (String) -> Unit,
    alRevertir: (String) -> Unit,
    /** Con «Comí», mirando la opción que comió: lo que NO comió (DIE-06). null, sin tildes. */
    excluidos: Set<Int>? = null,
    alTildar: (Int) -> Unit = {},
) {
    val c = MyPump.colores
    Column {
        originales.forEachIndexed { i, original ->
            val k = clavePosicion(comida.id, opcion, i)
            val efectivo = efectivos[i]
            FilaAlimento(
                original,
                hoy[i],
                efectivo.sustituido,
                Modifier.testTag("alimento-${comida.id}-$i"),
                sufijo = "${comida.id}-$i",
                porcionAbierta = k in porciones,
                alTocarMano = { alTocarMano(k) },
                alReemplazar = { alReemplazar(k) },
                alRevertir = { alRevertir(k) },
                enElPlan = if (hoy[i].qty != efectivo.alimento.qty) efectivo.alimento else null,
                tildado = excluidos?.let { i !in it },
                alTildar = { alTildar(i) },
            )
            if (i < originales.size - 1) Separador()
        }
    }
    Column {
        val fondoTotal = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(12.dp))
            .background(c.campo.copy(alpha = c.campo.alpha * 0.6f))
            .padding(horizontal = 12.dp, vertical = 9.dp)
        val rotulo = @Composable { m: Modifier ->
            Text("TOTAL", style = MaterialTheme.typography.labelSmall.copy(letterSpacing = 0.5.sp), fontWeight = FontWeight.SemiBold, color = c.textoSecundario, modifier = m)
        }
        if (LocalDensity.current.fontScale >= ESCALA_APILADA) {
            // Letra muy grande: el rótulo y los macros, uno por renglón (al lado, "TOTAL" quedaba letra por letra).
            Column(fondoTotal, verticalArrangement = Arrangement.spacedBy(6.dp)) {
                rotulo(Modifier)
                MacroMini("P", total.prot, c.proteina)
                MacroMini("C", total.carb, c.carbohidrato)
                MacroMini("G", total.fat, c.grasa)
            }
        } else {
            Row(fondoTotal, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                rotulo(Modifier.weight(1f))
                MacroMini("P", total.prot, c.proteina)
                MacroMini("C", total.carb, c.carbohidrato)
                MacroMini("G", total.fat, c.grasa)
            }
        }
    }
}

/**
 * Un alimento de la opción elegida (`renderFood`, la `FilaAlimento` de iOS): nombre (con la marca si está reemplazado, que
 * al tocarla ofrece volver al del plan), cantidad, kcal y macros, la mano con la porción casera (DIE-08) y el reemplazo
 * (DIE-09, salvo condimentos y lo que Mati marcó `swappable: false`).
 *
 * [modifier] (con la etiqueta de las pruebas) va en el bloque de los textos; los botones quedan aparte, como en TalkBack.
 */
@Composable
private fun FilaAlimento(
    original: Alimento,
    mostrado: Alimento,
    sustituido: Boolean,
    modifier: Modifier = Modifier,
    sufijo: String = "",
    porcionAbierta: Boolean = false,
    alTocarMano: () -> Unit = {},
    alReemplazar: () -> Unit = {},
    alRevertir: () -> Unit = {},
    /** Si el ajuste de hoy cambió la cantidad: lo del plan, para mostrarlo al lado. */
    enElPlan: Alimento? = null,
    /** Con «Comí», mirando la opción que comió: si lo comió (tildado) o lo dejó (DIE-06). null, sin tilde. */
    tildado: Boolean? = null,
    alTildar: () -> Unit = {},
) {
    val c = MyPump.colores
    val porcion = PorcionCasera.referencia(mostrado.nombre, mostrado.qty, mostrado.unidad, mostrado.gramosPorUnidad)
    val sustituible = CategoriaComida.sustituible(original)
    val tactil = LocalHapticFeedback.current
    Column(Modifier.fillMaxWidth().padding(vertical = 10.dp), verticalArrangement = Arrangement.spacedBy(Espacio.xs)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espacio.xxs)) {
            if (tildado != null) {
                // Una casilla para TalkBack: «Huevo entero, Lo comiste» (el `isToggle` de iOS).
                Box(
                    Modifier
                        .size(48.dp)
                        .clip(CircleShape)
                        .toggleable(value = tildado, role = Role.Checkbox) {
                            tactil.performHapticFeedback(HapticFeedbackType.SegmentTick)
                            alTildar()
                        }
                        .semantics {
                            contentDescription = mostrado.nombre
                            stateDescription = if (tildado) "Lo comiste" else "No lo comiste"
                        }
                        .testTag("comido-$sufijo"),
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(
                        if (tildado) Iconos.TildeEnCirculo else Iconos.Circulo,
                        contentDescription = null,
                        tint = if (tildado) c.marca else c.textoSecundario,
                        modifier = Modifier.size(26.dp),
                    )
                }
            }
            Column(modifier.weight(1f).semantics(mergeDescendants = true) {}, verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text(
                        mostrado.nombre,
                        style = MaterialTheme.typography.bodyLarge,
                        fontWeight = FontWeight.Medium,
                        // Lo que no comió, tachado.
                        color = if (tildado == false) c.textoSecundario else Color.Unspecified,
                        textDecoration = if (tildado == false) TextDecoration.LineThrough else null,
                        modifier = Modifier.weight(1f, fill = false),
                    )
                    if (sustituido) {
                        // La marca del reemplazo: tocarla ofrece volver al del plan (28 dp de toque sin agrandar el renglón).
                        Box(
                            Modifier
                                .size(28.dp)
                                .clip(CircleShape)
                                .clickable(role = Role.Button, onClick = alRevertir)
                                .semantics { contentDescription = "Reemplazado. Tocá para volver a ${original.nombre}" }
                                .testTag("reemplazado-$sufijo"),
                            contentAlignment = Alignment.Center,
                        ) {
                            Box(Modifier.size(20.dp).clip(CircleShape).background(c.marca), contentAlignment = Alignment.Center) {
                                Icon(Iconos.Intercambio, contentDescription = null, tint = c.sobreMarca, modifier = Modifier.size(13.dp))
                            }
                        }
                    }
                }
                Text(
                    "${FormatoDieta.cantidad(mostrado.qty, mostrado.unidad)} · ${Formato.miles(mostrado.kcal)} kcal",
                    style = MaterialTheme.typography.bodyMedium,
                    color = if (enElPlan != null) c.marcaTexto else c.textoSecundario,
                )
                if (enElPlan != null) {
                    Text("En el plan: ${FormatoDieta.cantidad(enElPlan.qty, enElPlan.unidad)}", style = MaterialTheme.typography.bodySmall, color = c.textoSecundario)
                }
                Text(FormatoDieta.macros(mostrado, c.proteina, c.carbohidrato, c.grasa), style = MaterialTheme.typography.bodySmall, color = c.textoSecundario)
            }
            if (porcion != null) {
                BotonCircular(
                    Iconos.Mano,
                    descripcion = if (porcionAbierta) "Ocultar porción casera" else "Ver porción casera",
                    activo = porcionAbierta,
                    alTocar = alTocarMano,
                    modifier = Modifier.testTag("mano-$sufijo"),
                )
            }
            if (sustituible) {
                BotonCircular(
                    Iconos.Intercambio,
                    descripcion = "Reemplazar ${mostrado.nombre}",
                    activo = false,
                    alTocar = alReemplazar,
                    modifier = Modifier.testTag("reemplazar-$sufijo"),
                )
            }
        }
        AnimatedVisibility(visible = porcionAbierta && porcion != null, enter = expandVertically() + fadeIn(), exit = shrinkVertically() + fadeOut()) {
            val p = porcion ?: ""
            Row(
                Modifier
                    .clip(CircleShape)
                    .background(c.marcaSuave)
                    .padding(horizontal = 12.dp, vertical = 7.dp)
                    .clearAndSetSemantics { contentDescription = "Porción casera: $p" }
                    .testTag("porcion-$sufijo"),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                Icon(Iconos.Mano, contentDescription = null, tint = c.marcaTexto, modifier = Modifier.size(15.dp))
                Text(if (p.startsWith("libre")) p else "≈ $p", style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold, color = c.marcaTexto)
            }
        }
    }
}

/**
 * Lo que cambió de una comida hoy: lo que hizo el cliente y lo que tomó de las anteriores (lo que solo pasa de largo, porque
 * no la come o no tiene qué escalar, no se cuenta acá: se ve en la que lo recibe). Gemelo del `AvisoAjuste` de iOS.
 */
@Composable
private fun AvisoAjuste(a: AjustePorciones.ComidaAjustada, propia: Boolean, modifier: Modifier = Modifier) {
    val c = MyPump.colores
    val llega = llegaPorOtras(a, propia)
    Column(
        modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(12.dp))
            .background(c.marcaSuave)
            .padding(horizontal = 12.dp, vertical = 9.dp)
            .semantics(mergeDescendants = true) {},
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        @Composable
        fun renglon(icono: ImageVector, texto: String) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Icon(icono, contentDescription = null, tint = c.marcaTexto, modifier = Modifier.size(18.dp))
                Text(texto, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold, color = c.marcaTexto)
            }
        }
        if (a.omitida) {
            renglon(Iconos.Luna, "Hoy no la comés")
        } else if (propia) {
            renglon(IconosAjuste.Ajustar, if (abs(a.propio) >= 1) "Ajustada: ${TextosAjuste.signo(a.propio)} kcal" else "Ajustada a mano")
        }
        if (!a.omitida && abs(a.absorbido) >= 1 && abs(llega) >= 1) {
            val de = a.compensaDe.map(TextosAjuste::conArticulo)
            renglon(
                if (llega < 0) IconosAjuste.AbajoDerecha else IconosAjuste.ArribaDerecha,
                "${TextosAjuste.signo(llega)} kcal por ${if (de.isEmpty()) "la comida anterior" else TextosAjuste.unir(de)}",
            )
        }
    }
}

/**
 * Lo que cambió por las anteriores. Si solo recibe, todo lo que cambió es por ellas: la diferencia real (con el redondeo de
 * las porciones), la misma que anticipó la hoja de la que la mandó. Con un ajuste propio, lo que tomó (lo propio va en el
 * renglón de arriba).
 */
private fun llegaPorOtras(a: AjustePorciones.ComidaAjustada, propia: Boolean): Double = if (propia) a.absorbido else a.kcal - a.kcalPlan

private fun hayQueMostrarAviso(a: AjustePorciones.ComidaAjustada, propia: Boolean): Boolean =
    a.omitida || propia || (abs(a.absorbido) >= 1 && abs(llegaPorOtras(a, propia = false)) >= 1)

@Composable
private fun MacroMini(letra: String, valor: Double?, color: Color) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
        Punto(color, 7.dp)
        Text(letra, style = MaterialTheme.typography.labelSmall, fontWeight = FontWeight.Bold, color = MyPump.colores.textoSecundario)
        Text("${Formato.entero(valor)} g", style = MaterialTheme.typography.labelMedium.copy(fontWeight = FontWeight.Medium))
    }
}

private fun letra(i: Int): String = if (i in 0..25) ('A' + i).toString() else "?"

/** El ícono de cada comida por su nombre (como `iconoComida` de iOS). */
private fun iconoComida(nombre: String?): ImageVector {
    val n = (nombre ?: "").lowercase()
    return when {
        "desayuno" in n -> Iconos.Amanecer
        "almuerzo" in n -> Iconos.Sol
        "merienda" in n -> Iconos.Taza
        "cena" in n -> Iconos.Luna
        "pre" in n || "post" in n || "entreno" in n -> Iconos.Rayo
        "colaci" in n || "snack" in n -> Iconos.Hoja
        else -> Iconos.Cubiertos
    }
}

/** Cómo se escriben cantidades y macros en Dieta (FormatoDieta de iOS). */
object FormatoDieta {
    /**
     * "2 unidades", "110 g", "1 rebanada": la web imprime `qty unit` crudo ("2 unidad"); acá se pluraliza solo lo que es
     * palabra (las unidades reales de los planes: g, unidad, rebanada, ml, vianda, cuchara, scoop).
     */
    fun cantidad(q: Double?, u: String?): String {
        val unidad = u ?: "g"
        if (q == null) return unidad
        return "${Formato.decimal(q)} ${if (q == 1.0) unidad else plural(unidad)}"
    }

    fun plural(u: String): String {
        val l = u.lowercase()
        if (l in setOf("g", "gr", "kg", "ml", "l", "cc", "mg", "oz") || l.endsWith(".") || u.length <= 2) return u
        if (l.endsWith("s")) return u
        if (l.endsWith("ón")) return u.dropLast(2) + "ones"
        if (l.endsWith("on")) return u + "es"
        if (l.isNotEmpty() && l.last() in "aeiouáéó") return u + "s"
        if (l.endsWith("d") || l.endsWith("r") || l.endsWith("l") || l.endsWith("n")) return u + "es"
        return u + "s"
    }

    /** "P 15,1 · C 0,8 · G 11,4", con la letra en el color del macro (como el anillo de arriba). */
    fun macros(a: Alimento, proteina: Color, carbohidrato: Color, grasa: Color): AnnotatedString =
        macros(a.prot, a.carb, a.fat, proteina, carbohidrato, grasa)

    /** Lo mismo con las macros sueltas (un sustituto, una comida libre). */
    fun macros(prot: Double?, carb: Double?, fat: Double?, proteina: Color, carbohidrato: Color, grasa: Color): AnnotatedString = buildAnnotatedString {
        fun parte(letra: String, v: Double?, color: Color) {
            withStyle(SpanStyle(color = color, fontWeight = FontWeight.Bold)) { append(letra) }
            append(" ${Formato.decimal(v ?: 0.0)}")
        }
        parte("P", prot, proteina)
        append("  ·  ")
        parte("C", carb, carbohidrato)
        append("  ·  ")
        parte("G", fat, grasa)
    }
}
