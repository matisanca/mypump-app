package com.pumpteam.mypump.recorrido

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.isImeVisible
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
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
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTagsAsResourceId
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.pumpteam.mypump.acceso.Onboarding
import com.pumpteam.mypump.datos.ModeloApp
import com.pumpteam.mypump.datos.ModeloFinPlan
import com.pumpteam.mypump.diseno.AsaHoja
import com.pumpteam.mypump.diseno.BotonMarca
import com.pumpteam.mypump.diseno.BotonSecundario
import com.pumpteam.mypump.diseno.Espacio
import com.pumpteam.mypump.diseno.FormaHoja
import com.pumpteam.mypump.diseno.Iconos
import com.pumpteam.mypump.diseno.MyPump
import com.pumpteam.mypump.diseno.Radio
import com.pumpteam.mypump.diseno.superficieTarjeta
import com.pumpteam.mypump.novedades.NovedadesUI
import com.pumpteam.mypump.raiz.LocalAlcanceApp
import com.pumpteam.mypump.raiz.Navegacion
import com.pumpteam.mypump.reglas.FinPlan
import com.pumpteam.mypump.reglas.FinPlan.Textos as T
import com.pumpteam.mypump.reglas.LogroRecorrido
import com.pumpteam.mypump.reglas.Recorrido
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

// Fin de plan, «Tu recorrido» (2.3.0, palanca `fin_plan`; contrato `cola-b/CONTRATO_APP.md`, sección 1): la tarjeta arriba de
// Entreno, la entrada en Mis datos y la hoja, que se abre sola una vez. Regla de Mati: fácil de encontrar y súper visible
// (hay alumnos mayores): botones grandes con texto, textos cortos y que ande con la letra más grande (los renglones bajan).

/** La hoja de «Tu recorrido», abierta desde la tarjeta, desde Mis datos o sola. */
object RecorridoUI {
    var abierta by mutableStateOf(false)

    /** El modelo de la cuenta a la que pertenece [abierta]: al salir o cambiar de cuenta no queda abierta la de la anterior. */
    internal var dueno: Any? = null
}

/** Arriba de Entreno (debajo de la tarjeta de la videollamada, si está), mientras el servidor diga que se ve. */
@Composable
fun TarjetaRecorridoDe(modelo: ModeloApp, modifier: Modifier = Modifier) {
    val fp by modelo.finPlan.collectAsStateWithLifecycle()
    val m = fp ?: return
    val recorrido by m.recorrido.collectAsStateWithLifecycle()
    val r = recorrido ?: return
    val c = MyPump.colores
    Column(
        modifier.fillMaxWidth().superficieTarjeta().padding(Espacio.m).testTag("recorrido-tarjeta"),
        verticalArrangement = Arrangement.spacedBy(Espacio.s),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espacio.s)) {
            Box(Modifier.size(44.dp).background(c.marcaSuave, CircleShape), contentAlignment = Alignment.Center) {
                Icon(Iconos.Trofeo, contentDescription = null, tint = c.marcaTexto, modifier = Modifier.size(24.dp))
            }
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(T.TARJETA_TITULO, style = MaterialTheme.typography.titleMedium, color = c.texto, modifier = Modifier.semantics { heading() })
                Text(FinPlan.textoTarjeta(r.estado), style = MaterialTheme.typography.bodyLarge, color = c.textoSecundario, modifier = Modifier.testTag("recorrido-tarjeta-texto"))
            }
        }
        BotonMarca(T.TARJETA_BOTON, alTocar = { RecorridoUI.abierta = true }, modifier = Modifier.testTag("recorrido-abrir"))
    }
}

/** La hoja desde cualquier lugar y, la primera vez que llega sin pedir, sola (si hay otra hoja abierta, espera). */
@Composable
fun HojaDeRecorridoDe(modelo: ModeloApp, navegacion: Navegacion) {
    val fase by modelo.fase.collectAsStateWithLifecycle()
    val fp by modelo.finPlan.collectAsStateWithLifecycle()
    val m = fp
    LaunchedEffect(m) {
        if (RecorridoUI.dueno !== m) {
            RecorridoUI.abierta = false
            RecorridoUI.dueno = m
        }
    }
    if (m == null) return
    val recorrido by m.recorrido.collectAsStateWithLifecycle()
    val local by m.local.collectAsStateWithLifecycle()
    val r = recorrido
    val sola = fase == ModeloApp.Fase.LISTO && FinPlan.seAbreSola(r, local.abiertaSola)
    LaunchedEffect(m, sola) {
        if (!sola) return@LaunchedEffect
        // Después de la hoja de permisos, de la bienvenida de la guía y de «Novedades de tu plan»: nunca dos hojas apiladas.
        delay(2_000)
        while (Onboarding.pendiente(modelo.preferencias) || NovedadesUI.bienvenidaGuia || NovedadesUI.abierta != null || navegacion.guia) delay(400)
        if (RecorridoUI.abierta || !m.seAbreSola) return@LaunchedEffect
        m.marcarAbiertaSola()
        RecorridoUI.abierta = true
    }
    // Dejó de verse (Mati lo cerró, o se apagó) con la hoja abierta: se cierra.
    LaunchedEffect(r == null) { if (r == null) RecorridoUI.abierta = false }
    if (RecorridoUI.abierta && r != null) HojaRecorrido(m, r, modelo, alCerrar = { RecorridoUI.abierta = false })
}

@OptIn(ExperimentalMaterial3Api::class, ExperimentalComposeUiApi::class, ExperimentalLayoutApi::class)
@Composable
private fun HojaRecorrido(m: ModeloFinPlan, r: Recorrido, app: ModeloApp, alCerrar: () -> Unit) {
    val c = MyPump.colores
    val hoja = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val alcance = rememberCoroutineScope()
    val alcanceApp = LocalAlcanceApp.current
    val enviando by m.enviando.collectAsStateWithLifecycle()
    var error by remember { mutableStateOf(false) }
    fun cerrar() {
        alcance.launch { hoja.hide() }.invokeOnCompletion { alCerrar() }
    }
    LaunchedEffect(m) { m.alAbrirLaHoja() }
    val pide = FinPlan.pidePreguntas(r)
    ModalBottomSheet(
        onDismissRequest = alCerrar,
        sheetState = hoja,
        shape = FormaHoja,
        containerColor = c.fondo,
        tonalElevation = 0.dp,
        dragHandle = { AsaHoja() },
        modifier = Modifier.semantics { testTagsAsResourceId = true }.testTag("recorrido-hoja"),
    ) {
        Column(Modifier.fillMaxWidth().navigationBarsPadding(), horizontalAlignment = Alignment.CenterHorizontally) {
            Row(Modifier.widthIn(max = 700.dp).fillMaxWidth().padding(horizontal = Espacio.m), horizontalArrangement = Arrangement.End) {
                BotonSecundario(T.CERRAR, alTocar = ::cerrar, compacto = true, modifier = Modifier.testTag("recorrido-cerrar"))
            }
            Column(
                Modifier.weight(1f, fill = false).widthIn(max = 700.dp).fillMaxWidth()
                    .verticalScroll(rememberScrollState()).padding(horizontal = Espacio.m).padding(top = Espacio.xs, bottom = Espacio.m),
                verticalArrangement = Arrangement.spacedBy(Espacio.m),
            ) {
                Text(
                    FinPlan.tituloHoja(r), style = MaterialTheme.typography.headlineMedium, color = c.texto,
                    modifier = Modifier.semantics { heading() }.testTag("recorrido-titulo"),
                )
                r.resumen.mensaje?.let { Text(it, style = MaterialTheme.typography.bodyLarge, color = c.texto, modifier = Modifier.testTag("recorrido-mensaje")) }
                r.resumen.logros.forEachIndexed { i, l -> TarjetaLogro(l, Modifier.testTag("recorrido-logro-$i")) }
                // Los controles de salud, como hitos con fecha (`controles_app`).
                com.pumpteam.mypump.estudios.HitosControlRecorrido(app)
                if (pide) {
                    Column(Modifier.padding(top = Espacio.xs), verticalArrangement = Arrangement.spacedBy(Espacio.xxs)) {
                        Text(T.PREGUNTAS_TITULO, style = MaterialTheme.typography.titleLarge, color = c.texto, modifier = Modifier.semantics { heading() })
                        Text(T.PREGUNTAS_TEXTO, style = MaterialTheme.typography.bodyLarge, color = c.textoSecundario)
                    }
                    for (clave in FinPlan.CLAVES) {
                        CampoPregunta(
                            pregunta = T.pregunta(clave),
                            inicial = remember(m, clave) { m.local.value.escrito.de(clave) },
                            alCambiar = { m.escribir(clave, it) },
                            etiqueta = "recorrido-$clave",
                            habilitado = !enviando,
                        )
                    }
                } else {
                    FinPlan.cartel(r)?.let { (principal, debajo) -> CartelListo(principal, debajo) }
                }
            }
            if (pide) {
                Column(
                    Modifier.widthIn(max = 700.dp).fillMaxWidth().padding(horizontal = Espacio.m).padding(top = Espacio.xs, bottom = Espacio.s),
                    verticalArrangement = Arrangement.spacedBy(Espacio.xs),
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    if (error && !enviando) {
                        Text(
                            T.ERROR, style = MaterialTheme.typography.bodyLarge.copy(fontWeight = FontWeight.Medium), color = c.alerta,
                            modifier = Modifier.fillMaxWidth().semantics { liveRegion = LiveRegionMode.Polite }.testTag("recorrido-error"),
                        )
                    }
                    // Mientras manda dice «Enviando…» y no se puede tocar dos veces.
                    BotonMarca(
                        if (enviando) T.ENVIANDO else T.AGENDAR,
                        alTocar = {
                            error = false
                            // Con el alcance de la app: cerrar la hoja a mitad del envío no lo corta.
                            alcanceApp.launch {
                                when (m.pedir()) {
                                    ModeloFinPlan.Salida.ERROR -> error = true
                                    ModeloFinPlan.Salida.YA_NO -> alCerrar()
                                    ModeloFinPlan.Salida.OK, ModeloFinPlan.Salida.OCUPADO -> Unit
                                }
                            }
                        },
                        habilitado = !enviando,
                        modifier = Modifier.testTag("recorrido-agendar"),
                    )
                    // Con el teclado arriba no se muestra: el lugar es para lo que está escribiendo.
                    if (!WindowInsets.isImeVisible) {
                        Text(T.AGENDAR_DEBAJO, style = MaterialTheme.typography.bodyMedium, color = c.textoSecundario)
                    }
                }
            }
        }
    }
}

/** Un logro: el valor bien grande, el título y el detalle. Con la letra grande los renglones bajan. */
@Composable
private fun TarjetaLogro(l: LogroRecorrido, modifier: Modifier = Modifier) {
    val c = MyPump.colores
    Column(
        modifier.fillMaxWidth().superficieTarjeta().padding(Espacio.m).semantics(mergeDescendants = true) {},
        verticalArrangement = Arrangement.spacedBy(2.dp),
    ) {
        Text(l.valor, style = MaterialTheme.typography.headlineLarge.copy(fontWeight = FontWeight.Bold), color = c.marcaTexto)
        Text(l.titulo, style = MaterialTheme.typography.titleMedium, color = c.texto)
        l.detalle?.let { Text(it, style = MaterialTheme.typography.bodyLarge, color = c.textoSecundario) }
    }
}

@Composable
private fun CartelListo(principal: String, debajo: String?) {
    val c = MyPump.colores
    Row(
        Modifier.fillMaxWidth().superficieTarjeta(color = c.marcaSuave).padding(Espacio.m).semantics(mergeDescendants = true) {}.testTag("recorrido-listo"),
        horizontalArrangement = Arrangement.spacedBy(Espacio.s),
    ) {
        Icon(Iconos.TildeEnCirculo, contentDescription = null, tint = c.marcaTexto, modifier = Modifier.size(28.dp))
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(principal, style = MaterialTheme.typography.titleMedium, color = c.texto)
            debajo?.let { Text(it, style = MaterialTheme.typography.bodyLarge, color = c.texto) }
        }
    }
}

/** Una pregunta opcional, de varias líneas, con el tope de 500. La pregunta va arriba, entera: nunca solo como marcador. */
@Composable
private fun CampoPregunta(pregunta: String, inicial: String, alCambiar: (String) -> Unit, etiqueta: String, habilitado: Boolean) {
    val c = MyPump.colores
    var texto by remember { mutableStateOf(inicial) }
    Column(verticalArrangement = Arrangement.spacedBy(Espacio.xs)) {
        Text(pregunta, style = MaterialTheme.typography.titleMedium, color = c.texto)
        BasicTextField(
            value = texto,
            onValueChange = {
                texto = FinPlan.recortar(it)
                alCambiar(texto)
            },
            enabled = habilitado,
            minLines = 3,
            maxLines = 8,
            keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Sentences),
            textStyle = MaterialTheme.typography.bodyLarge.copy(color = c.texto),
            cursorBrush = SolidColor(c.marcaTexto),
            modifier = Modifier.fillMaxWidth().semantics { contentDescription = pregunta }.testTag(etiqueta),
            decorationBox = { campo ->
                Box(Modifier.heightIn(min = 96.dp).background(c.campo, RoundedCornerShape(Radio.control)).padding(Espacio.s)) { campo() }
            },
        )
    }
}
