package com.pumpteam.mypump.dieta

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.waitForUpOrCancellation
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
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
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.saveable.Saver
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.addPathNodes
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.disabled
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTagsAsResourceId
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.pumpteam.mypump.datos.ModeloApp
import com.pumpteam.mypump.diseno.AccionHoja
import com.pumpteam.mypump.diseno.AsaHoja
import com.pumpteam.mypump.diseno.EncabezadoHoja
import com.pumpteam.mypump.diseno.Espacio
import com.pumpteam.mypump.diseno.EstadoVacio
import com.pumpteam.mypump.diseno.FormaHoja
import com.pumpteam.mypump.diseno.Formato
import com.pumpteam.mypump.diseno.Iconos
import com.pumpteam.mypump.diseno.Interruptor
import com.pumpteam.mypump.diseno.MyPump
import com.pumpteam.mypump.diseno.Numeros
import com.pumpteam.mypump.diseno.Punto
import com.pumpteam.mypump.diseno.Separador
import com.pumpteam.mypump.diseno.Tarjeta
import com.pumpteam.mypump.entreno.Letras
import com.pumpteam.mypump.modelos.Alimento
import com.pumpteam.mypump.modelos.ValorJson
import com.pumpteam.mypump.raiz.LocalAlcanceApp
import com.pumpteam.mypump.reglas.AjusteComida
import com.pumpteam.mypump.reglas.AjustePorciones
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * Ajustar una comida de hoy (feedback de clientes del 20-oct; gemela de AjustarComidaView.swift): sumar o restar kcal (las
 * porciones se recalculan parejo), las cantidades de cada alimento a mano, «Hoy no la como» y si la diferencia se compensa
 * en las comidas siguientes. Se ve el efecto en vivo (las kcal, las macros, el resto del día); nada se guarda hasta
 * «Listo». La cuenta es de `AjustePorciones` (la misma en iOS, con los mismos vectores).
 */
@OptIn(ExperimentalMaterial3Api::class, ExperimentalComposeUiApi::class)
@Composable
fun HojaAjustarComida(modelo: ModeloApp, comidaId: String, opciones: Map<String, Int>, alCerrar: () -> Unit) {
    val c = MyPump.colores
    val hoja = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val alcanceHoja = rememberCoroutineScope()
    val alcance = LocalAlcanceApp.current
    val tactil = LocalHapticFeedback.current
    val guardados by modelo.ajustes.collectAsStateWithLifecycle()
    val swaps by modelo.swaps.collectAsStateWithLifecycle()
    val teniaAjuste = remember { modelo.ajustesDeHoy[comidaId] != null }
    var borrador by rememberSaveable(stateSaver = SaverAjuste) {
        // La opción como la ve la cuenta del día (acotada a las que hay) y el ajuste guardado sin lo que ya no vale (una
        // cantidad de un alimento que Mati cambió, kcal que ya no entran): si no, los − / + no hacían nada.
        val comida = modelo.comidasParaAjustar(opciones).firstOrNull { it.id == comidaId }
        val elegida = comida?.opcion ?: 0
        var a = modelo.ajustesDeHoy[comidaId] ?: AjusteComida(opcion = elegida)
        if (a.opcion != elegida) a = a.copy(opcion = elegida, cantidades = emptyMap(), anclas = emptyMap())
        mutableStateOf(comida?.let { AjustePorciones.anclar(a, it) } ?: a)
    }
    val comidas = remember(guardados, swaps, opciones) { modelo.comidasParaAjustar(opciones) }
    // Los ajustes del día con el borrador en lugar del guardado.
    val ajustes = remember(guardados, borrador) {
        modelo.ajustesDeHoy.toMutableMap().apply { if (borrador.neutro) remove(comidaId) else put(comidaId, borrador) }.toMap()
    }
    val dia = remember(comidas, ajustes) { AjustePorciones.dia(comidas, ajustes) }
    val comida = comidas.firstOrNull { it.id == comidaId }
    val r = dia[comidaId]
    val destino = remember(comidas, ajustes) { AjustePorciones.destino(comidas, ajustes, comidaId) }

    fun cerrar() {
        alcanceHoja.launch { hoja.hide() }.invokeOnCompletion { alCerrar() }
    }

    fun guardar(a: AjusteComida?) {
        alcance.launch { modelo.ajustar(comidaId, a, opciones) }
        cerrar()
    }

    /**
     * Sobre el borrador de AHORA (dos toques antes de que se redibuje no pisan uno al otro). Con un alimento puesto a mano
     * entra menos: las kcal sumadas o restadas quedan dentro de lo que la comida absorbe.
     */
    fun cambiar(f: (AjusteComida) -> AjusteComida) {
        var nuevo = f(borrador)
        comida?.let { c -> nuevo = nuevo.copy(deltaKcal = nuevo.deltaKcal.coerceIn(AjustePorciones.limitesDelta(c, nuevo))) }
        if (nuevo == borrador) return
        borrador = nuevo
        tactil.performHapticFeedback(HapticFeedbackType.SegmentTick)
    }

    ModalBottomSheet(
        onDismissRequest = alCerrar,
        sheetState = hoja,
        shape = FormaHoja,
        containerColor = c.fondo,
        tonalElevation = 0.dp,
        dragHandle = { AsaHoja() },
        modifier = Modifier.semantics { testTagsAsResourceId = true }.testTag("hoja-ajuste"),
    ) {
        EncabezadoHoja(
            "Ajustar ${comida?.nombre?.takeIf { it.isNotEmpty() } ?: "comida"}",
            cancelar = AccionHoja("Cancelar", "ajuste-cancelar", alTocar = ::cerrar),
            confirmar = AccionHoja("Listo", "ajuste-listo", alTocar = { guardar(borrador.takeUnless { it.neutro }) }),
        )
        if (comida == null || r == null) {
            Box(Modifier.heightIn(min = 280.dp)) {
                EstadoVacio(icono = Iconos.Cubiertos, titulo = "Esta comida ya no está en tu plan", texto = "Cerrá y volvé a mirar tu dieta.")
            }
            return@ModalBottomSheet
        }
        LazyColumn(
            modifier = Modifier.weight(1f, fill = false).testTag("ajuste-lista"),
            contentPadding = PaddingValues(start = Espacio.m, end = Espacio.m, top = Espacio.xs, bottom = Espacio.l),
            verticalArrangement = Arrangement.spacedBy(Espacio.m),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            item(key = "resumen") { ResumenAjuste(r, comida, dia, Modifier.widthIn(max = 640.dp)) }
            item(key = "control") {
                Column(Modifier.widthIn(max = 640.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Tarjeta(espaciado = 0.dp, relleno = 0.dp) {
                        ControlKcal(comida, borrador, ::cambiar)
                        if (destino != null) {
                            Separador(Modifier.padding(start = Espacio.m))
                            FilaInterruptor(
                                titulo = "Compensar en ${TextosAjuste.conArticulo(destino.nombre)}",
                                detalle = TextosAjuste.compensacion(comidas, ajustes, comidaId, borrador.compensar),
                                prendido = borrador.compensar,
                                etiqueta = "ajuste-compensar",
                                alCambiar = { v -> cambiar { it.copy(compensar = v) } },
                            )
                        }
                        Separador(Modifier.padding(start = Espacio.m))
                        FilaInterruptor(
                            titulo = "Hoy no la como",
                            detalle = if (borrador.omitida && borrador.compensar && destino != null) {
                                "Sus ${Formato.miles(r.kcalPlan)} kcal pasan ${TextosAjuste.aLa(destino.nombre)}."
                            } else {
                                "Las porciones de esta comida quedan en cero por hoy."
                            },
                            prendido = borrador.omitida,
                            etiqueta = "ajuste-omitir",
                            alCambiar = { v -> cambiar { it.copy(omitida = v) } },
                        )
                    }
                    if (destino == null) {
                        Text(
                            "No hay otra comida después para compensar: lo que cambies queda en el total del día.",
                            style = Letras.caption, color = c.textoSecundario, modifier = Modifier.padding(horizontal = Espacio.m),
                        )
                    }
                }
            }
            if (!borrador.omitida) {
                item(key = "alimentos") {
                    Column(Modifier.widthIn(max = 640.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        Text(
                            "ALIMENTOS", style = Letras.ceja, color = c.textoSecundario,
                            modifier = Modifier.padding(horizontal = Espacio.m),
                        )
                        Tarjeta(espaciado = 0.dp, relleno = 0.dp) {
                            comida.alimentos.forEachIndexed { i, plan ->
                                FilaAlimentoAjuste(i, plan, hoy = r.alimentos.getOrNull(i) ?: plan, borrador, ::cambiar)
                                if (i < comida.alimentos.size - 1) Separador(Modifier.padding(start = Espacio.m))
                            }
                        }
                        Text(
                            "Tocá − o + para cambiar la cantidad de un alimento; en 0 no lo comés hoy. «Como el plan» la vuelve a la del plan.",
                            style = Letras.caption, color = c.textoSecundario, modifier = Modifier.padding(horizontal = Espacio.m),
                        )
                    }
                }
            }
            item(key = "pie") {
                Column(Modifier.widthIn(max = 640.dp).fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(Espacio.s)) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp), modifier = Modifier.padding(horizontal = Espacio.m)) {
                        Icon(Iconos.Calendario, contentDescription = null, tint = c.textoSecundario, modifier = Modifier.size(16.dp))
                        Text("Vale solo por hoy: mañana vuelve tu plan.", style = Letras.caption, color = c.textoSecundario)
                    }
                    if (teniaAjuste || !borrador.neutro) {
                        Box(
                            Modifier
                                .fillMaxWidth()
                                .clip(RoundedCornerShape(14.dp))
                                .background(c.tarjeta)
                                .clickable(role = Role.Button) { guardar(null) }
                                .heightIn(min = 52.dp)
                                .testTag("ajuste-volver-plan"),
                            contentAlignment = Alignment.Center,
                        ) {
                            Text("Volver al plan", style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.Medium, color = c.peligro)
                        }
                    }
                }
            }
        }
    }
}

/** El borrador sobrevive a rotar la pantalla (en JSON, como va al disco). */
private val SaverAjuste = Saver<AjusteComida, String>(
    save = { it.aValor().serializar() },
    restore = { AjusteComida.desde(ValorJson.parsear(it)) },
)

/**
 * Las kcal de hoy en grande contra las del plan, las macros (Emilio: «jugar con los gramos de proteínas, carbohidratos y
 * grasas»), lo que le llega de antes y cómo queda el día.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun ResumenAjuste(r: AjustePorciones.ComidaAjustada, comida: AjustePorciones.ComidaDelDia, dia: Map<String, AjustePorciones.ComidaAjustada>, modifier: Modifier) {
    val c = MyPump.colores
    val diferencia = r.kcal - r.kcalPlan
    val hoy = ModeloApp.sumar(r.alimentos)
    val plan = ModeloApp.sumar(comida.alimentos)
    val diaHoy = dia.values.sumOf { it.kcal }
    val diaPlan = dia.values.sumOf { it.kcalPlan }
    Tarjeta(modifier, espaciado = 10.dp) {
        Column(
            // La etiqueta antes: `clearAndSetSemantics` borra la semántica de lo que va después.
            Modifier.fillMaxWidth().testTag("ajuste-kcal").clearAndSetSemantics {
                contentDescription = "Kcal de esta comida: ${Formato.miles(r.kcal)}" +
                    (if (abs(diferencia) >= 1) ", ${TextosAjuste.signo(diferencia)} contra el plan" else "") + ", en el plan ${Formato.miles(r.kcalPlan)}"
            },
            verticalArrangement = Arrangement.spacedBy(2.dp),
        ) {
            Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(Formato.miles(r.kcal), style = Numeros.grande.copy(color = c.texto, fontSize = 40.sp, lineHeight = 44.sp), maxLines = 1)
                Text("kcal", style = MaterialTheme.typography.titleMedium, color = c.textoSecundario, modifier = Modifier.padding(bottom = 8.dp))
                Box(Modifier.weight(1f))
                if (abs(diferencia) >= 1) {
                    Text(
                        TextosAjuste.signo(diferencia),
                        style = MaterialTheme.typography.titleSmall.copy(fontWeight = FontWeight.Bold, fontFeatureSettings = "tnum"),
                        color = c.marcaTexto,
                        modifier = Modifier.padding(bottom = 10.dp).clip(CircleShape).background(c.marcaSuave).padding(horizontal = 10.dp, vertical = 4.dp),
                    )
                }
            }
            Text("En el plan: ${Formato.miles(r.kcalPlan)} kcal", style = MaterialTheme.typography.bodyMedium, color = c.textoSecundario)
        }
        FlowRow(
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp),
            modifier = Modifier.testTag("ajuste-macros"),
        ) {
            MacroDelAjuste("Proteínas", "P", hoy.prot ?: 0.0, plan.prot ?: 0.0, c.proteina)
            MacroDelAjuste("Carbohidratos", "C", hoy.carb ?: 0.0, plan.carb ?: 0.0, c.carbohidrato)
            MacroDelAjuste("Grasas", "G", hoy.fat ?: 0.0, plan.fat ?: 0.0, c.grasa)
        }
        if (abs(r.absorbido) >= 1) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Icon(if (r.absorbido < 0) IconosAjuste.AbajoDerecha else IconosAjuste.ArribaDerecha, contentDescription = null, tint = c.textoSecundario, modifier = Modifier.size(16.dp))
                Text(TextosAjuste.llega(r), style = Letras.caption, color = c.textoSecundario)
            }
        }
        Text(
            "Tu día: ${Formato.miles(diaHoy)} kcal · en el plan ${Formato.miles(diaPlan)}",
            style = Letras.caption.copy(fontWeight = FontWeight.Medium),
            color = c.textoSecundario,
            modifier = Modifier.testTag("ajuste-dia"),
        )
    }
}

/** Una macro de la comida: lo de hoy y cuánto se aparta del plan. */
@Composable
private fun MacroDelAjuste(nombre: String, letra: String, hoy: Double, plan: Double, color: Color) {
    val c = MyPump.colores
    val d = Formato.entero(hoy - plan)
    Row(
        Modifier
            .clip(CircleShape)
            .background(c.campo.copy(alpha = c.campo.alpha * 0.6f))
            .padding(horizontal = 8.dp, vertical = 5.dp)
            .clearAndSetSemantics {
                contentDescription = "$nombre: ${Formato.entero(hoy)} gramos" + (if (d != 0L) ", ${if (d > 0) "más" else "menos"} ${abs(d)} que el plan" else "")
            },
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Punto(color, 7.dp)
        Text(letra, style = MaterialTheme.typography.labelSmall, fontWeight = FontWeight.Bold, color = c.textoSecundario)
        Text("${Formato.entero(hoy)} g", style = MaterialTheme.typography.labelMedium.copy(fontWeight = FontWeight.Medium, fontFeatureSettings = "tnum"))
        if (d != 0L) {
            Text(TextosAjuste.signo(d.toDouble()), style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.SemiBold, fontFeatureSettings = "tnum"), color = c.marcaTexto)
        }
    }
}

/**
 * −50 / +50 kcal, con lo sumado en el medio. Mantener apretado repite. Los topes (un cuarto, el triple) son de lo que se
 * puede agrandar o achicar: lo puesto a mano no cuenta.
 */
@Composable
private fun ControlKcal(comida: AjustePorciones.ComidaDelDia, borrador: AjusteComida, cambiar: ((AjusteComida) -> AjusteComida) -> Unit) {
    val c = MyPump.colores
    val paso = AjustePorciones.PASO
    val base = AjustePorciones.baseEscalable(comida, borrador)
    val limites = AjustePorciones.limitesDelta(comida, borrador)
    val minimo = limites.first
    val maximo = limites.last
    val activo = !borrador.omitida && base > 0
    val menos = @Composable {
        BotonKcal("−$paso", "Restar $paso kcal", "ajuste-menos", habilitado = activo && borrador.deltaKcal > minimo) {
            cambiar { it.copy(deltaKcal = max(minimo, it.deltaKcal - paso)) }
        }
    }
    val mas = @Composable {
        BotonKcal("+$paso", "Sumar $paso kcal", "ajuste-mas", habilitado = activo && borrador.deltaKcal < maximo) {
            cambiar { it.copy(deltaKcal = min(maximo, it.deltaKcal + paso)) }
        }
    }
    val cuanto = @Composable { m: Modifier ->
        Column(m.semantics(mergeDescendants = true) {}, horizontalAlignment = Alignment.CenterHorizontally) {
            Text(
                if (borrador.deltaKcal == 0) "Como el plan" else "${TextosAjuste.signo(borrador.deltaKcal.toDouble())} kcal",
                style = MaterialTheme.typography.titleMedium.copy(fontFeatureSettings = "tnum"),
                color = if (borrador.omitida) c.textoTerciario else c.texto,
                modifier = Modifier.testTag("ajuste-delta"),
            )
            Text("a esta comida", style = Letras.caption, color = c.textoSecundario)
        }
    }
    Column(Modifier.fillMaxWidth().padding(Espacio.m), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        if (LocalDensity.current.fontScale >= ESCALA_APILADA_AJUSTE) {
            // Con la letra muy grande, como en iOS: lo sumado arriba y −50/+50 abajo.
            cuanto(Modifier.fillMaxWidth())
            Row(verticalAlignment = Alignment.CenterVertically) {
                menos()
                Box(Modifier.weight(1f))
                mas()
            }
        } else {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                menos()
                cuanto(Modifier.weight(1f))
                mas()
            }
        }
        if (!borrador.omitida && base == 0.0) {
            Text(
                if (AjustePorciones.baseEscalable(comida, null) > 0) "Con todo puesto a mano, las kcal son la suma de los alimentos."
                else "Esta comida no tiene cantidades para recalcular.",
                style = Letras.caption,
                color = c.textoSecundario,
            )
        }
    }
}

/** Desde esta escala de letra lo sumado va arriba de los botones (la misma de la cabecera de Dieta). */
private const val ESCALA_APILADA_AJUSTE = 1.5f

@Composable
private fun BotonKcal(texto: String, descripcion: String, etiqueta: String, habilitado: Boolean, accion: () -> Unit) {
    val c = MyPump.colores
    Repetible(habilitado, descripcion, etiqueta, accion) { apretado ->
        Box(
            Modifier
                .widthIn(min = 72.dp)
                .heightIn(min = 48.dp)
                .clip(CircleShape)
                .background(if (apretado) c.marcaSuave.mezclar(c.marcaTexto, 0.12f) else c.marcaSuave)
                .padding(horizontal = 14.dp),
            contentAlignment = Alignment.Center,
        ) {
            Text(
                texto,
                style = MaterialTheme.typography.titleMedium.copy(fontFeatureSettings = "tnum"),
                color = if (habilitado) c.marcaTexto else c.textoTerciario,
            )
        }
    }
}

/** Un alimento: lo de hoy (con lo del plan al lado si cambió), − / + para ponerlo a mano y «Como el plan» si está a mano. */
@Composable
private fun FilaAlimentoAjuste(i: Int, plan: Alimento, hoy: Alimento, borrador: AjusteComida, cambiar: ((AjusteComida) -> AjusteComida) -> Unit) {
    val c = MyPump.colores
    val clave = i.toString()
    val aMano = borrador.cantidades[clave] != null
    val q = hoy.qty ?: 0.0
    // Desde la cantidad a mano de AHORA si ya la tiene (dos toques seguidos), si no la de hoy. El − llega a 0: ese alimento
    // sale de la comida por hoy.
    fun mover(f: (Double) -> Double) = cambiar { a -> a.copy(cantidades = a.cantidades + (clave to f(a.cantidades[clave] ?: q))) }
    Row(
        Modifier.fillMaxWidth().padding(start = Espacio.m, end = 6.dp, top = 8.dp, bottom = 8.dp).testTag("ajuste-alimento-$i"),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Column(Modifier.weight(1f).semantics(mergeDescendants = true) {}, verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(hoy.nombre, style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.Medium)
            Text(
                "${FormatoDieta.cantidad(hoy.qty, hoy.unidad)} · ${Formato.miles(hoy.kcal)} kcal",
                style = MaterialTheme.typography.bodyMedium.copy(fontFeatureSettings = "tnum"),
                color = if (hoy.qty != plan.qty) c.marcaTexto else c.textoSecundario,
            )
            if (hoy.qty != plan.qty) {
                Text(
                    "En el plan: ${FormatoDieta.cantidad(plan.qty, plan.unidad)}${if (aMano) " · a mano" else ""}",
                    style = Letras.caption, color = c.textoSecundario,
                )
            }
            if (aMano) {
                Text(
                    "Como el plan",
                    style = Letras.caption.copy(fontWeight = FontWeight.SemiBold),
                    color = c.marcaTexto,
                    modifier = Modifier
                        .padding(top = 2.dp)
                        .clip(CircleShape)
                        .clickable(role = Role.Button) { cambiar { it.copy(cantidades = it.cantidades - clave, anclas = it.anclas - clave) } }
                        .padding(vertical = 4.dp)
                        .testTag("ajuste-como-el-plan-$i"),
                )
            }
        }
        if (plan.qty != null && (plan.kcal ?: 0.0) > 0) {
            BotonPaso(Iconos.Menos, "Menos ${plan.nombre}", "ajuste-menos-$i", habilitado = AjustePorciones.puedeBajar(q)) {
                mover { actual -> AjustePorciones.bajar(plan, actual) }
            }
            BotonPaso(IconosAjuste.Mas, "Más ${plan.nombre}", "ajuste-mas-$i", habilitado = AjustePorciones.puedeSubir(plan, q)) {
                mover { actual -> AjustePorciones.subir(plan, actual) }
            }
        }
    }
}

/** − o + de un alimento: 48 dp de toque. */
@Composable
private fun BotonPaso(icono: ImageVector, descripcion: String, etiqueta: String, habilitado: Boolean, accion: () -> Unit) {
    val c = MyPump.colores
    Repetible(habilitado, descripcion, etiqueta, accion) { apretado ->
        Box(Modifier.size(48.dp), contentAlignment = Alignment.Center) {
            Box(
                Modifier.size(34.dp).clip(CircleShape).background(if (apretado) c.campo.mezclar(c.texto, 0.12f) else c.campo),
                contentAlignment = Alignment.Center,
            ) {
                Icon(icono, contentDescription = null, tint = if (habilitado) c.texto else c.textoTerciario, modifier = Modifier.size(17.dp))
            }
        }
    }
}

/**
 * Tocar hace [accion] una vez (al soltar, como un botón: si el dedo se va o la lista se mueve, nada); mantener apretado la
 * repite (el `buttonRepeatBehavior` de iOS). Con TalkBack es un botón común.
 */
@Composable
private fun Repetible(habilitado: Boolean, descripcion: String, etiqueta: String, accion: () -> Unit, contenido: @Composable (apretado: Boolean) -> Unit) {
    val accionActual by rememberUpdatedState(accion)
    val habilitadoActual by rememberUpdatedState(habilitado)
    var apretado by remember { mutableStateOf(false) }
    Box(
        Modifier
            .semantics {
                role = Role.Button
                contentDescription = descripcion
                if (!habilitado) disabled()
                onClick(descripcion) {
                    if (habilitadoActual) accionActual()
                    habilitadoActual
                }
            }
            .testTag(etiqueta)
            .pointerInput(Unit) {
                coroutineScope {
                    awaitEachGesture {
                        awaitFirstDown()
                        if (!habilitadoActual) return@awaitEachGesture
                        apretado = true
                        var repitio = false
                        val repetir = launch {
                            delay(450)
                            while (habilitadoActual) {
                                repitio = true
                                accionActual()
                                delay(110)
                            }
                        }
                        val arriba = waitForUpOrCancellation()
                        repetir.cancel()
                        apretado = false
                        if (arriba != null && !repitio && habilitadoActual) accionActual()
                    }
                }
            },
    ) { contenido(apretado) }
}

/** Una fila con un interruptor: toda la fila lo cambia (y es lo que anuncia TalkBack). */
@Composable
private fun FilaInterruptor(titulo: String, detalle: String, prendido: Boolean, etiqueta: String, alCambiar: (Boolean) -> Unit) {
    val c = MyPump.colores
    Row(
        Modifier
            .fillMaxWidth()
            .toggleable(value = prendido, role = Role.Switch, onValueChange = alCambiar)
            .padding(horizontal = Espacio.m, vertical = 12.dp)
            .testTag(etiqueta),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(titulo, style = MaterialTheme.typography.bodyLarge)
            Text(detalle, style = Letras.caption, color = c.textoSecundario, modifier = Modifier.testTag("$etiqueta-detalle"))
        }
        Interruptor(prendido, alCambiar = null)
    }
}

/** Los textos de la hoja y de las tarjetas (los mismos de iOS). */
internal object TextosAjuste {
    /** «+100» / «−100», con el signo menos de verdad. */
    fun signo(x: Double): String = "${if (x > 0) "+" else "−"}${abs(Formato.entero(x))}"

    fun mayuscula(s: String): String = s.replaceFirstChar { it.uppercase() }

    /** «a», «a y b», «a, b y c». */
    fun unir(partes: List<String>): String = if (partes.size <= 1) partes.firstOrNull().orEmpty() else partes.dropLast(1).joinToString(", ") + " y " + partes.last()

    /** «el Almuerzo», «la Merienda», «la Colación»: femenino si la primera palabra termina en «a» o en «ón». */
    fun conArticulo(nombre: String): String {
        if (nombre.isEmpty()) return "la comida siguiente"
        val primera = nombre.lowercase().split(' ', '-').firstOrNull { it.isNotEmpty() }.orEmpty()
        return (if (primera.endsWith("a") || primera.endsWith("ón") || primera.endsWith("on")) "la " else "el ") + nombre
    }

    /** «al Almuerzo», «a la Merienda» (a + el = al). */
    fun aLa(nombre: String): String = conArticulo(nombre).let { if (it.startsWith("el ")) "al " + it.removePrefix("el ") else "a $it" }

    /** Lo que el ajuste de [id] le hace al resto del día, comida por comida (y lo que no entra en ninguna). */
    fun compensacion(comidas: List<AjustePorciones.ComidaDelDia>, ajustes: Map<String, AjusteComida>, id: String, compensar: Boolean): String {
        val e = AjustePorciones.efecto(comidas, ajustes, id)
        if (e.cambios.isEmpty()) return if (compensar) "Lo que cambies acá se compensa ahí." else "El total del día queda con la diferencia."
        val partes = e.cambios.map { x ->
            "${conArticulo(x.nombre)} ${if (x.kcal < 0) "baja" else "sube"} ${Formato.miles(abs(x.kcal))} kcal (queda en ${Formato.miles(x.queda)})"
        }
        var t = mayuscula(unir(partes)) + "."
        if (abs(e.sinCompensar) >= 1) t += " No alcanza: ${Formato.miles(abs(e.sinCompensar))} kcal quedan sin compensar."
        return t
    }

    /** «Baja 100 kcal por el Desayuno.» (lo que la comida tomó de las anteriores). */
    fun llega(r: AjustePorciones.ComidaAjustada): String {
        val de = r.compensaDe.map(::conArticulo)
        return "${if (r.absorbido < 0) "Baja" else "Sube"} ${Formato.miles(abs(r.absorbido))} kcal por ${if (de.isEmpty()) "la comida anterior" else unir(de)}."
    }
}

/** Mezcla [otro] sobre este color (para el apretado de los botones). */
private fun Color.mezclar(otro: Color, cuanto: Float): Color =
    Color(red + (otro.red - red) * cuanto, green + (otro.green - green) * cuanto, blue + (otro.blue - blue) * cuanto, alpha)

/** Los íconos de los ajustes (Material Symbols, como el resto). */
internal object IconosAjuste {
    private fun icono(nombre: String, trazado: String): ImageVector =
        ImageVector.Builder(name = nombre, defaultWidth = 24.dp, defaultHeight = 24.dp, viewportWidth = 24f, viewportHeight = 24f)
            .apply { addPath(pathData = addPathNodes(trazado), fill = SolidColor(Color.Black)) }
            .build()

    /** tune: «Ajustar esta comida». */
    val Ajustar: ImageVector by lazy { icono("Ajustar", "M3,17v2h6v-2H3zM3,5v2h10V5H3zM13,21v-2h8v-2h-8v-2h-2v6h2zM7,9v2H3v2h4v2h2V9H7zM21,13v-2H11v2h10zM15,9h2V7h4V5h-4V3h-2v6z") }

    /** add: + de un alimento. */
    val Mas: ImageVector by lazy { icono("Mas", "M19,13h-6v6h-2v-6H5v-2h6V5h2v6h6v2z") }

    /** south_east / north_east: lo que baja o sube por otra comida. */
    val AbajoDerecha: ImageVector by lazy { icono("AbajoDerecha", "M19,9h-2v6.59L5.41,4 4,5.41 15.59,17H9v2h10V9z") }
    val ArribaDerecha: ImageVector by lazy { icono("ArribaDerecha", "M9,5v2h6.59L4,18.59 5.41,20 17,8.41V15h2V5H9z") }
}
