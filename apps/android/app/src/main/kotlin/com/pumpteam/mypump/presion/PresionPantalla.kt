package com.pumpteam.mypump.presion

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.pumpteam.mypump.datos.EstadoPresion
import com.pumpteam.mypump.datos.ModeloApp
import com.pumpteam.mypump.datos.ModeloPresion
import com.pumpteam.mypump.datos.PendientePresion
import com.pumpteam.mypump.datos.SeriePresion
import com.pumpteam.mypump.diseno.AnchoLectura
import com.pumpteam.mypump.diseno.Espacio
import com.pumpteam.mypump.diseno.Iconos
import com.pumpteam.mypump.diseno.MyPump
import com.pumpteam.mypump.diseno.Radio
import com.pumpteam.mypump.diseno.Tarjeta
import com.pumpteam.mypump.raiz.Navegacion
import com.pumpteam.mypump.reglas.Presion
import kotlinx.coroutines.delay

/** Un círculo por toma, lleno o vacío. Sin promedios ni colores de riesgo. */
@Composable
private fun CirculosPresion(hechas: Int, total: Int, id: String, conOrtostatica: Boolean = false) {
    val c = MyPump.colores
    Row(
        Modifier.clearAndSetSemantics { contentDescription = TP.avanceAlt(hechas, total) }.testTag(id),
        horizontalArrangement = Arrangement.spacedBy(Espacio.s),
    ) {
        for (i in 0 until maxOf(total, 0)) {
            val hecha = i < hechas
            Box(
                Modifier.size(32.dp).clip(CircleShape).background(if (hecha) c.marcaVivo else Color.Transparent).border(2.dp, if (hecha) c.marcaVivo else c.textoSecundario, CircleShape),
                contentAlignment = Alignment.Center,
            ) {
                if (hecha) {
                    Icon(Iconos.Tilde, contentDescription = null, tint = c.sobreMarca, modifier = Modifier.size(18.dp))
                } else if (i == hechas && conOrtostatica) {
                    // La toma que lleva ortostática: un ícono chico de persona.
                    Icon(Iconos.Persona, contentDescription = null, tint = c.textoSecundario, modifier = Modifier.size(18.dp))
                }
            }
        }
    }
}

/**
 * «Presión arterial» (`presion/CONTRATO_APP.md`), a pantalla completa. Con la palanca `presion_app` apagada o sin el servidor
 * nuevo, la fila de Mis datos y la tarjeta no existen y esto no se abre.
 *
 * El alumno ve sus pasos, sus temporizadores, sus tomas tal como las anotó y el avance. No ve promedios, categorías ni colores
 * de riesgo. Y nada de acá toca Entreno ni la rutina: la presión nunca frena el entrenamiento.
 *
 * [directo]: desde la tarjeta de arriba o un aviso se abre en lo que toca (la repetición, preparar o la toma de hoy).
 */
@Composable
internal fun PresionRaiz(modelo: ModeloPresion, directo: Boolean, alDirectoHecho: () -> Unit, alCerrar: () -> Unit) {
    val estado by modelo.estado.collectAsStateWithLifecycle()
    val local by modelo.local.collectAsStateWithLifecycle()
    val foco = LocalFocusManager.current
    var flujo by rememberSaveable { mutableStateOf(false) }
    var sintoma by rememberSaveable { mutableStateOf(false) }
    var guardia by rememberSaveable { mutableStateOf(false) }
    var cambiarAparato by rememberSaveable { mutableStateOf(false) }
    var verLista by rememberSaveable { mutableStateOf(false) }
    // Las respuestas de la lista del recordatorio (una repetición de 180/120 que quedó sin hacer).
    var recordatorio by rememberSaveable { mutableStateOf(emptyMap<String, Boolean>()) }
    var recordatorioMandado by rememberSaveable { mutableStateOf(false) }

    // Leen `estado` y `local`: se recalculan cuando cambian.
    val serieVista = modelo.serieVista
    val pendiente = modelo.pendiente
    val hoyListo = modelo.hoyListo
    val enCola = local.envios.size

    fun empezar() {
        // Con la serie completa y todavía abierta, lo que se anota es una toma suelta.
        val s = modelo.serieVista?.takeIf { it.faltan > 0 }
        if (s != null && s.compararBrazos && !s.medidaPedida) {
            // La comparación de brazos va antes de la toma del día (si falta medir el brazo, primero eso).
            modelo.empezar("comparacion_brazos", s.id, s.brazo, EtapaPresion.GUIA_INTRO)
        } else {
            modelo.empezar(s?.tipo ?: "suelta", s?.id, s?.brazo, if (s?.medidaPedida == true) EtapaPresion.MEDIR else EtapaPresion.INSTRUCCIONES)
        }
        flujo = true
    }

    fun repetir(p: PendientePresion) {
        val e = modelo.enCurso
        if (e != null && e.sesion.id == p.sesionId) {
            // Si la espera sigue corriendo, vuelve a la espera; si ya pasó, directo a anotar.
            modelo.cambiar {
                val f = it.finTemporizador
                if (f != null && f > System.currentTimeMillis()) it.copy(etapa = EtapaPresion.ESPERA) else it.copy(etapa = EtapaPresion.ANOTAR, finTemporizador = null)
            }
        } else {
            modelo.retomar(p, EtapaPresion.ANOTAR)
        }
        flujo = true
    }

    /** La lista del recordatorio viaja como síntoma. Con un Sí, guardia por síntomas en el acto. Sin contestar todo no cuenta como «no». */
    fun responderRecordatorio(p: PendientePresion, codigo: String, si: Boolean) {
        val r = recordatorio + (codigo to si)
        recordatorio = r
        if (si) {
            modelo.marcarSintoma(Presion.alarma.filter { r[it] == true }, null, contexto = "recordatorio_180_120", sesionId = p.sesionId, sinSintomasEnLista = false)
            guardia = true
        } else if (!recordatorioMandado && Presion.alarma.all { r[it] == false }) {
            recordatorioMandado = true
            modelo.marcarSintoma(emptyList(), null, contexto = "recordatorio_180_120", sesionId = p.sesionId, sinSintomasEnLista = true)
        }
    }

    /** Lo que la tarjeta o el aviso prometieron: sin pasar por la pantalla de inicio. */
    fun irALoQueToca() {
        val e = modelo.estado.value ?: return
        if (flujo || sintoma || guardia) return
        when (modelo.tarjeta) {
            ModeloPresion.Tarjeta.Repetir -> modelo.pendiente?.let { repetir(it) }
            ModeloPresion.Tarjeta.Preparar -> {
                // Sin aparato ya se está en «Antes de la primera serie». Con reloj, a cambiar el aparato. Si falta medir, la toma lo pide.
                if (e.aparato == null) return
                if (!Presion.metodo(e.circunferenciaBrazoCm, e.aparato).admiteTomas) cambiarAparato = true else empezar()
            }
            is ModeloPresion.Tarjeta.Toma -> empezar()
            is ModeloPresion.Tarjeta.HoyListo, null -> Unit
        }
    }

    LaunchedEffect(Unit) {
        modelo.refrescar()
        modelo.drenarEnFondo()
    }
    LaunchedEffect(directo, estado != null) {
        if (directo && estado != null) {
            alDirectoHecho()
            irALoQueToca()
        }
    }
    // Una sesión en curso se cerró (o era de otro día): se vuelve al inicio.
    LaunchedEffect(flujo, local.enCurso == null) { if (flujo && local.enCurso == null) flujo = false }
    // Con algo abierto no se cierra sola: el texto de guardia se queda aunque el servidor apague la sección.
    LaunchedEffect(estado == null, flujo, guardia, sintoma) { if (estado == null && !flujo && !guardia && !sintoma) alCerrar() }
    BackHandler(onBack = alCerrar)

    val e = estado
    val tapado = sintoma || guardia
    Box(Modifier.fillMaxSize().background(MyPump.colores.fondo)) {
        Box(if (tapado) Modifier.fillMaxSize().clearAndSetSemantics { } else Modifier.fillMaxSize()) {
            when {
                flujo && local.enCurso != null -> TomaPresionPantalla(modelo, alCerrar = { flujo = false })
                e == null -> Box(Modifier.fillMaxSize())
                e.aparato == null -> AparatoPresionPantalla(modelo, ModoAparato.PRIMERA, alSalir = alCerrar, alMarcarSintoma = {
                    foco.clearFocus()
                    sintoma = true
                })
                cambiarAparato -> {
                    BackHandler { cambiarAparato = false }
                    AparatoPresionPantalla(modelo, ModoAparato.CAMBIAR, alSalir = { cambiarAparato = false }, alGuardar = { cambiarAparato = false })
                }
                verLista && e.tensiometros != null && Presion.tramoBrazo(e.circunferenciaBrazoCm) != null ->
                    ListaTensiometrosPresion(e.tensiometros!!, Presion.tramoBrazo(e.circunferenciaBrazoCm)!!, alCerrar = { verLista = false })
                else -> InicioPresion(
                    e, serieVista, pendiente, hoyListo, enCola, recordatorio,
                    alCerrar = alCerrar, alEmpezar = { empezar() }, alRepetir = { repetir(it) }, alResponder = { p, c, si -> responderRecordatorio(p, c, si) },
                    alMarcarSintoma = { sintoma = true }, alVerLista = { verLista = true }, alCambiarAparato = { cambiarAparato = true },
                )
            }
        }
        if (sintoma) MarcarSintomaPresion(modelo) { sintoma = false }
        if (guardia) {
            BackHandler { guardia = false }
            GuardiaPresion(porSintomas = true, alCerrar = { guardia = false })
        }
    }
}

/** El inicio: el avance, lo que toca hoy (un solo botón principal), los avisos del aparato, las tomas y el tensiómetro. */
@Composable
private fun InicioPresion(
    e: EstadoPresion,
    serie: SeriePresion?,
    pendiente: PendientePresion?,
    hoyListo: Boolean,
    enCola: Int,
    recordatorio: Map<String, Boolean>,
    alCerrar: () -> Unit,
    alEmpezar: () -> Unit,
    alRepetir: (PendientePresion) -> Unit,
    alResponder: (PendientePresion, String, Boolean) -> Unit,
    alMarcarSintoma: () -> Unit,
    alVerLista: () -> Unit,
    alCambiarAparato: () -> Unit,
) {
    val m = Presion.metodo(e.circunferenciaBrazoCm, e.aparato)
    val titular = MaterialTheme.typography.titleMedium
    MarcoPresion(NP.titulo, NP.cerrar, alCerrar, etiqueta = "presion-inicio") {
        if (serie != null) {
            val hechas = minOf(serie.tomasObjetivo, maxOf(0, serie.tomasObjetivo - serie.faltan))
            Tarjeta {
                CirculosPresion(hechas, serie.tomasObjetivo, "presion-avance", conOrtostatica = serie.ortostatica != null)
                TextoPresion(if (serie.faltan == 0) TP.listoSerieCorto else TP.faltan(serie.faltan), Modifier.testTag("presion-avance-texto"), estilo = titular, fuerte = true)
            }
        }
        when {
            !m.admiteTomas -> Tarjeta { TextoPresion(NP.relojNoSirve, Modifier.testTag("presion-reloj-no-sirve"), estilo = titular, fuerte = true) }
            pendiente != null -> Tarjeta(espaciado = Espacio.m) {
                TextoPresion(TP.repetirPendiente, Modifier.testTag("presion-pendiente"), estilo = titular, fuerte = true)
                if (pendiente.nivel == "urgencia") {
                    TextoPresion(TP.esperaLista)
                    ListaAlarmaPresion(recordatorio) { c, si -> alResponder(pendiente, c, si) }
                }
                BotonPresion(NP.repetir, "presion-repetir") { alRepetir(pendiente) }
            }
            hoyListo -> Tarjeta { TextoPresion(NP.hoyListo, Modifier.testTag("presion-hoy-listo"), estilo = titular, fuerte = true) }
            else -> BotonPresion(if (e.serie == null || (serie?.faltan ?: 0) <= 0) NP.tomaSuelta else NP.tomaDeHoy, "presion-toma", alTocar = alEmpezar)
        }
        // La segunda línea habla de una lista: sin la lista verificada no se muestra, ni «Ver cuáles sirven».
        val conLista = e.tensiometros != null
        val avisos: List<String> = when {
            m.metodo == "muneca_provisoria" -> if (conLista) TP.muneca else TP.muneca.take(1)
            m.metodo == "muneca_habitual" && m.pedirValidado -> if (conLista) listOf(TP.munecaNoValidada) else emptyList()
            m.metodo == "brazo" && m.pedirValidado -> if (conLista) TP.noValidado else TP.noValidado.take(1)
            else -> emptyList()
        }
        if (avisos.isNotEmpty()) {
            Tarjeta(Modifier.testTag("presion-aviso-aparato")) {
                for (t in avisos) TextoPresion(t)
                val tramo = Presion.tramoBrazo(e.circunferenciaBrazoCm)
                if (conLista && tramo != null && tramo != "menos_22") BotonPresionSecundario(TP.verCuales, "presion-ver-cuales", alTocar = alVerLista)
            }
        }
        BotonPresionSecundario(TP.marcarSintoma, "presion-marcar-sintoma", alTocar = alMarcarSintoma)
        if (enCola > 0) TextoPresion(NP.sinSenal, Modifier.testTag("presion-sin-senal"), estilo = MaterialTheme.typography.bodySmall, secundario = true)
        val conTomas = e.sesiones.filter { it.tomas.isNotEmpty() }
        Tarjeta {
            TituloPresion(NP.tusTomas)
            if (conTomas.isEmpty()) {
                TextoPresion(NP.sinTomas, Modifier.testTag("presion-sin-tomas"), secundario = true)
            } else {
                // El gráfico, con 2 tomas o más; con 1, solo la lista.
                if (conTomas.sumOf { it.tomas.size } >= 2) GraficoPresion(conTomas)
                ListaTomasPresion(conTomas)
            }
        }
        val a = e.aparato
        val nombre = listOfNotNull(a?.marca, a?.modelo).filter { it.isNotEmpty() }.joinToString(" ")
        Tarjeta(Modifier.testTag("presion-aparato"), espaciado = Espacio.xs) {
            TituloPresion(NP.aparato)
            NP.tipos[a?.tipo ?: ""]?.let { TextoPresion(it) }
            if (nombre.isNotEmpty()) TextoPresion(nombre, estilo = MaterialTheme.typography.bodyMedium, secundario = true)
            e.circunferenciaBrazoCm?.let { TextoPresion("${NP.brazo} ${NumeroPresion.texto(it)} ${NP.cm}", estilo = MaterialTheme.typography.bodyMedium, secundario = true) }
            BotonPresionSecundario(NP.cambiarAparato, "presion-cambiar-aparato", alTocar = alCambiarAparato)
        }
    }
}

/** «Marcar un síntoma»: siempre a mano, haya o no una sesión en curso. Medir nunca es condición para marcarlo. */
@Composable
internal fun MarcarSintomaPresion(modelo: ModeloPresion, alCerrar: () -> Unit) {
    var seleccion by rememberSaveable { mutableStateOf(emptyList<String>()) }
    var nota by rememberSaveable { mutableStateOf("") }
    // 0: eligiendo; 1: anotado; 2: guardia.
    var resultado by rememberSaveable { mutableStateOf(0) }
    val foco = LocalFocusManager.current
    BackHandler(onBack = alCerrar)
    when (resultado) {
        2 -> GuardiaPresion(porSintomas = true, alCerrar = alCerrar)
        1 -> MarcoPresion(
            TP.marcarSintoma, NP.cerrar, alCerrar, etiqueta = "presion-sintoma-pantalla", etiquetaSalir = "presion-sintoma-salir",
            pie = { BotonPresion(NP.cerrar, "presion-sintoma-cerrar", alTocar = alCerrar) },
        ) {
            Tarjeta { TextoPresion(NP.sintomaRecibido, Modifier.testTag("presion-sintoma-recibido"), estilo = MaterialTheme.typography.titleMedium, fuerte = true) }
        }
        else -> MarcoPresion(
            TP.marcarSintoma, NP.cerrar, alCerrar, etiqueta = "presion-sintoma-pantalla", etiquetaSalir = "presion-sintoma-salir",
            pie = {
                BotonPresion(NP.enviar, "presion-sintoma-enviar", habilitado = seleccion.isNotEmpty() || nota.isNotBlank()) {
                    foco.clearFocus()
                    // En el orden de las listas, no en el que los tocó.
                    val codigos = (Presion.alarma + Presion.otros).filter { it in seleccion }
                    resultado = if (modelo.marcarSintoma(codigos, nota, sesionId = modelo.enCurso?.sesion?.id)) 2 else 1
                }
            },
        ) {
            SelectorSintomasPresion(seleccion.toSet()) { seleccion = it.toList() }
            CampoPresion(NP.nota, nota, "presion-sintoma-nota", accion = ImeAction.Default, largoMaximo = 500, lineas = 5) { nota = it }
        }
    }
}

/**
 * «Tu presión», arriba de todo en la pantalla con la que abre la app mientras haya algo para hacer (`presion/CONTRATO_APP.md`):
 * la repetición pendiente, preparar (medir el brazo y anotar el tensiómetro), la toma de hoy o el avance.
 *
 * Es una tarjeta más: no tapa, no frena ni condiciona la rutina. La presión nunca frena el entrenamiento. Con la palanca
 * apagada, sin el servidor nuevo o sin la sección habilitada, no existe. Devuelve si se mostró.
 */
@Composable
fun TarjetaPresion(app: ModeloApp, navegacion: Navegacion, bajoLaBarraDeEstado: Boolean): Boolean {
    val modelo = app.presion.collectAsStateWithLifecycle().value ?: return false
    // Leerlos hace que la tarjeta siga a lo que cambia en el servidor y en el teléfono.
    val estado by modelo.estado.collectAsStateWithLifecycle()
    val local by modelo.local.collectAsStateWithLifecycle()
    val t = remember(estado, local) { modelo.tarjeta } ?: return false
    val c = MyPump.colores
    val forma = RoundedCornerShape(Radio.tarjeta)
    val abrir = { directo: Boolean -> navegacion.abrirPresion(directo) }
    Box(
        Modifier.fillMaxWidth().then(if (bajoLaBarraDeEstado) Modifier.windowInsetsPadding(WindowInsets.statusBars) else Modifier).padding(horizontal = Espacio.m, vertical = Espacio.xs),
        contentAlignment = Alignment.TopCenter,
    ) {
        Tarjeta(
            Modifier
                .widthIn(max = AnchoLectura)
                .border(2.dp, c.marcaVivo, forma)
                .clip(forma)
                // Sin botón (la de hoy ya está), tocar la tarjeta abre Presión.
                .then(if (t is ModeloPresion.Tarjeta.HoyListo) Modifier.clickable(role = Role.Button) { abrir(false) } else Modifier)
                .testTag("tarjeta-presion"),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espacio.xs)) {
                Icon(Iconos.Corazon, contentDescription = null, tint = c.marcaTexto, modifier = Modifier.size(24.dp))
                Text(NP.tarjeta, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold, color = c.texto, modifier = Modifier.weight(1f).semantics { heading() })
            }
            val titular = MaterialTheme.typography.titleMedium
            when (t) {
                ModeloPresion.Tarjeta.Repetir -> {
                    TextoPresion(TP.repetirPendiente, estilo = titular, fuerte = true)
                    BotonPresion(NP.repetir, "tarjeta-presion-boton") { abrir(true) }
                }
                ModeloPresion.Tarjeta.Preparar -> {
                    TextoPresion(NP.tarjetaPreparar, estilo = titular, fuerte = true)
                    BotonPresion(NP.empezar, "tarjeta-presion-boton") { abrir(true) }
                }
                is ModeloPresion.Tarjeta.Toma -> {
                    TextoPresion(TP.faltan(t.faltan), estilo = titular, fuerte = true)
                    if (t.hechas == 0) TextoPresion(NP.tarjetaSerie, estilo = MaterialTheme.typography.bodyMedium, secundario = true)
                    CirculosPresion(t.hechas, t.total, "tarjeta-presion-avance")
                    BotonPresion(NP.tomaDeHoy, "tarjeta-presion-boton") { abrir(true) }
                }
                is ModeloPresion.Tarjeta.HoyListo -> {
                    CirculosPresion(t.hechas, t.total, "tarjeta-presion-avance")
                    TextoPresion(NP.hoyListo, estilo = titular, fuerte = true)
                }
            }
        }
    }
    return true
}

/**
 * Presión por encima de las pestañas, cuando se pidió ([Navegacion.presion]) y la sección está habilitada. Con la palanca apagada
 * o sin el servidor nuevo no hay estado: no se muestra ni se llama nada, y el pedido se descarta.
 */
@Composable
fun CapaPresion(app: ModeloApp, navegacion: Navegacion, alCambiarVisible: (Boolean) -> Unit) {
    val modelo by app.presion.collectAsStateWithLifecycle()
    val m = modelo
    val habilitado = if (m != null) m.estado.collectAsStateWithLifecycle().value != null else false
    // Ya abierta, se queda aunque la sección se apague con algo abierto (el texto de guardia): PresionRaiz decide cuándo cerrarse.
    var abierta by remember { mutableStateOf(false) }
    val visible = navegacion.presion && m != null && (habilitado || abierta)
    LaunchedEffect(visible) {
        abierta = visible
        alCambiarVisible(visible)
    }
    // Se pidió (un aviso al arrancar) y la sección no aparece: se espera un rato a que cargue y, si no, el pedido se olvida.
    LaunchedEffect(navegacion.presion, visible) {
        if (navegacion.presion && !visible) {
            delay(20_000)
            navegacion.cerrarPresion()
        }
    }
    if (visible) {
        key(m) {
            PresionRaiz(m, directo = navegacion.presionDirecta, alDirectoHecho = { navegacion.presionDirecta = false }, alCerrar = { navegacion.cerrarPresion() })
        }
    }
}
