package com.pumpteam.mypump.presion

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.selection.toggleable
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
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
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.pumpteam.mypump.avisos.CentroAvisos
import com.pumpteam.mypump.datos.EnCursoPresion
import com.pumpteam.mypump.datos.ModeloPresion
import com.pumpteam.mypump.diseno.Espacio
import com.pumpteam.mypump.diseno.Iconos
import com.pumpteam.mypump.diseno.MyPump
import com.pumpteam.mypump.diseno.Numeros
import com.pumpteam.mypump.diseno.RuedaHora
import com.pumpteam.mypump.diseno.Separador
import com.pumpteam.mypump.diseno.Tarjeta
import com.pumpteam.mypump.reglas.Presion
import com.pumpteam.mypump.reglas.TextosPresion
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneId
import java.time.temporal.ChronoUnit

/**
 * Las pantallas del recorrido de una toma. El nombre queda guardado con la sesión en curso (`EnCursoPresion.etapa`), así al
 * volver a abrir la app se sabe dónde quedó. Los mismos nombres que iOS.
 */
internal object EtapaPresion {
    const val MEDIR = "medir"
    /** «Cuándo» (o las indicaciones de bajo efecto). */
    const val INSTRUCCIONES = "instrucciones"
    const val COMO = "como"
    const val PREVIA = "previa"
    const val ESPERAR_MEJOR = "esperarMejor"
    const val REPOSO = "reposo"
    const val ANOTAR = "anotar"
    const val ESPERA = "espera"
    const val GUARDIA_PRESION = "guardiaPresion"
    const val GUARDIA_SINTOMAS = "guardiaSintomas"
    const val LISTO = "listo"
    const val GUIA_INTRO = "guiaIntro"
    const val GUIA_ESPERA = "guiaEspera"
    const val GUIA_ANOTAR = "guiaAnotar"
    const val MAREO = "mareo"
}

/** Una fila para marcar o desmarcar, de 56 dp, con el texto entero. */
@Composable
private fun FilaMarcable(texto: String, marcado: Boolean, id: String, habilitado: Boolean = true, alCambiar: (Boolean) -> Unit) {
    val c = MyPump.colores
    Row(
        Modifier
            .fillMaxWidth()
            .heightIn(min = 56.dp)
            .toggleable(value = marcado, enabled = habilitado, role = Role.Checkbox, onValueChange = alCambiar)
            .testTag(id),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(Espacio.s),
    ) {
        Icon(if (marcado) Iconos.TildeEnCirculo else Iconos.Circulo, contentDescription = null, tint = if (marcado) c.texto else c.textoSecundario, modifier = Modifier.size(28.dp))
        TextoPresion(texto, Modifier.weight(1f))
    }
}

/** Las listas de síntomas para marcar: las 8 de alarma y las otras 3. */
@Composable
internal fun SelectorSintomasPresion(seleccion: Set<String>, alCambiar: (Set<String>) -> Unit) {
    for ((titulo, codigos) in listOf(NP.alarma to Presion.alarma, NP.otros to Presion.otros)) {
        Tarjeta(espaciado = Espacio.xxs) {
            TituloPresion(titulo)
            for (codigo in codigos) {
                FilaMarcable(TextosPresion.sintomas[codigo] ?: codigo, codigo in seleccion, "presion-sintoma-$codigo") { si ->
                    alCambiar(if (si) seleccion + codigo else seleccion - codigo)
                }
            }
        }
    }
}

/** «Qué evitar» (G5): diez tarjetas con su dibujo, el título y la aclaración. */
@Composable
internal fun QueEvitarPresion(alCerrar: () -> Unit) {
    BackHandler(onBack = alCerrar)
    MarcoPresion(TP.queEvitar, NP.cerrar, alCerrar, etiqueta = "presion-evitar", etiquetaSalir = "presion-evitar-cerrar") {
        @Composable
        fun tarjeta(i: Int, modifier: Modifier) {
            val t = TP.g5[i]
            Tarjeta(
                modifier.clearAndSetSemantics { contentDescription = "${TP.asiNo}. ${t[0]}. ${t[1]}" }.testTag("presion-evitar-${i + 1}"),
                relleno = 12.dp,
                espaciado = Espacio.xs,
            ) {
                DibujoPresion("presion_g5_%02d".format(i + 1), "", Modifier.widthIn(max = 120.dp).fillMaxWidth().align(Alignment.CenterHorizontally))
                TextoPresion(t[0], estilo = MaterialTheme.typography.titleSmall, fuerte = true)
                TextoPresion(t[1], estilo = MaterialTheme.typography.bodySmall, secundario = true)
            }
        }
        // Con letra grande, de a una por fila: de a dos el texto quedaba en columnas de tres palabras.
        if (letraGrande()) {
            for (i in TP.g5.indices) tarjeta(i, Modifier)
        } else {
            for (par in TP.g5.indices.chunked(2)) {
                Row(horizontalArrangement = Arrangement.spacedBy(Espacio.s), verticalAlignment = Alignment.Top) {
                    for (i in par) tarjeta(i, Modifier.weight(1f))
                    if (par.size == 1) Box(Modifier.weight(1f))
                }
            }
        }
    }
}

/** Tres cifras, o dos que ya no admiten una tercera (con «95» no hay alta posible de tres cifras): el número está entero. */
private fun numeroEntero(v: String, tope: Int): Boolean = v.length >= 3 || (v.length == 2 && (v.toIntOrNull() ?: 0) * 10 > tope)

/**
 * La alta, la baja, el pulso y el símbolo de latido irregular. Un valor imposible no pasa; uno fuera de lo común pide confirmar.
 * Con el pulso o la alta fuera de lo esperado ([preguntaSintomas], solo sentado) se abre la lista de síntomas antes de evaluar.
 */
@Composable
private fun AnotarPresion(
    titulo: String?,
    conFoto: Boolean,
    preguntaSintomas: Boolean,
    alSalir: () -> Unit,
    registrar: (sis: Int, dia: Int, pulso: Int, irregular: Boolean, confirmada: Boolean, sintomas: List<String>) -> Unit,
    extra: (@Composable ColumnScope.() -> Unit)? = null,
) {
    var sis by rememberSaveable { mutableStateOf("") }
    var dia by rememberSaveable { mutableStateOf("") }
    var pulso by rememberSaveable { mutableStateOf("") }
    var irregular by rememberSaveable { mutableStateOf(false) }
    // 0: nada; 1: imposible; 2: pide confirmar.
    var aviso by rememberSaveable { mutableStateOf(0) }
    var confirmada by rememberSaveable { mutableStateOf(false) }
    var hoja by rememberSaveable { mutableStateOf(false) }
    var sintomas by rememberSaveable { mutableStateOf(emptyList<String>()) }
    val focos = remember { List(3) { FocusRequester() } }
    val foco = LocalFocusManager.current
    val anunciar = rememberAnuncio()
    val revisar = if (conFoto) TP.revisarNumero else TP.revisarNumeroSinFoto
    val confirmando = aviso == 2

    fun numeros(): Triple<Int, Int, Int>? {
        val s = sis.toIntOrNull() ?: return null
        val d = dia.toIntOrNull() ?: return null
        val p = pulso.toIntOrNull() ?: return null
        return Triple(s, d, p)
    }

    fun enviar() {
        val (s, d, p) = numeros() ?: return
        // En el orden de las listas, no en el que los tocó.
        registrar(s, d, p, irregular, confirmada, (Presion.alarma + Presion.otros).filter { it in sintomas })
    }

    fun seguir() {
        val (s, _, p) = numeros() ?: return
        if (preguntaSintomas && (p >= 120 || p <= 40 || s < 90)) hoja = true else enviar()
    }

    fun anotar() {
        foco.clearFocus()
        // Lo que no es un número entero no pasa, igual que un valor imposible.
        when (Presion.validarToma(sis.toIntOrNull(), dia.toIntOrNull(), pulso.toIntOrNull())) {
            Presion.Validez.IMPOSIBLE -> {
                aviso = 1
                anunciar(revisar)
            }
            Presion.Validez.CONFIRMAR -> {
                aviso = 2
                anunciar(revisar)
            }
            Presion.Validez.OK -> seguir()
        }
    }

    /** Con el número entero el foco pasa solo al campo que sigue; después del pulso se va el teclado y queda el botón a la vista. */
    fun escrito(campo: Int, valor: String, tope: Int) {
        aviso = 0
        confirmada = false
        if (!numeroEntero(valor, tope)) return
        if (campo < 2) runCatching { focos[campo + 1].requestFocus() } else foco.clearFocus()
    }

    Box(Modifier.fillMaxSize()) {
        Box(if (hoja) Modifier.fillMaxSize().clearAndSetSemantics { } else Modifier.fillMaxSize()) {
            MarcoPresion(
                NP.titulo, NP.cerrar, alSalir, etiqueta = "presion-anotar-pantalla", etiquetaSalir = "presion-flujo-cerrar",
                pie = {
                    if (confirmando) {
                        BotonPresion(NP.confirmar, "presion-confirmar") {
                            confirmada = true
                            seguir()
                        }
                        BotonPresionSecundario(NP.corregir, "presion-corregir") {
                            aviso = 0
                            runCatching { focos[0].requestFocus() }
                        }
                    } else {
                        // Siempre a la vista, por encima del teclado.
                        BotonPresion(NP.anotar, "presion-anotar", habilitado = sis.isNotEmpty() && dia.isNotEmpty() && pulso.isNotEmpty()) { anotar() }
                    }
                },
            ) {
                if (titulo != null) TituloPresion(titulo, Modifier.testTag("presion-anotar-titulo"))
                Tarjeta(espaciado = Espacio.m) {
                    // Con letra grande los tres campos van uno debajo del otro.
                    @Composable
                    fun campos(m: Modifier) {
                        CampoPresion(NP.alta, sis, "presion-alta", m, teclado = KeyboardType.Number, grande = true, foco = focos[0], largoMaximo = 3, habilitado = !confirmando) {
                            sis = it
                            escrito(0, it, Presion.Lim.SIS_MAX)
                        }
                        CampoPresion(NP.baja, dia, "presion-baja", m, teclado = KeyboardType.Number, grande = true, foco = focos[1], largoMaximo = 3, habilitado = !confirmando) {
                            dia = it
                            escrito(1, it, Presion.Lim.DIA_MAX)
                        }
                        CampoPresion(
                            NP.pulso, pulso, "presion-pulso", m, teclado = KeyboardType.Number, grande = true, foco = focos[2], accion = ImeAction.Done,
                            alAccion = { foco.clearFocus() }, largoMaximo = 3, habilitado = !confirmando,
                        ) {
                            pulso = it
                            escrito(2, it, Presion.Lim.PUL_MAX)
                        }
                    }
                    if (letraGrande()) {
                        campos(Modifier.fillMaxWidth())
                    } else {
                        Row(horizontalArrangement = Arrangement.spacedBy(Espacio.s), verticalAlignment = Alignment.Top) {
                            // Dentro de la fila cada campo ocupa un tercio.
                            val tercio = Modifier.weight(1f)
                            campos(tercio)
                        }
                    }
                }
                Tarjeta { FilaMarcable(NP.irregular, irregular, "presion-irregular", habilitado = !confirmando) { irregular = it } }
                if (aviso != 0) Tarjeta { TextoPresion(revisar, Modifier.testTag("presion-revisar"), estilo = MaterialTheme.typography.titleMedium, fuerte = true) }
                extra?.invoke(this)
            }
        }
        if (hoja) {
            BackHandler { hoja = false }
            MarcoPresion(
                TP.marcarSintoma, NP.volver, { hoja = false }, etiqueta = "presion-sintomas-hoja", etiquetaSalir = "presion-sintomas-volver",
                pie = {
                    BotonPresion(NP.seguir, "presion-sintomas-seguir") {
                        hoja = false
                        enviar()
                    }
                },
            ) {
                SelectorSintomasPresion(sintomas.toSet()) { sintomas = it.toList() }
            }
        }
    }
}

/**
 * Una toma de principio a fin: medir de nuevo (si la serie lo pide), cuándo y cómo, las preguntas previas, el reposo, anotar y lo
 * que toque después (repetir, la lista de alarma, la guardia o el cierre), y la ortostática y la comparación de brazos si la serie
 * las trae. Un paso por pantalla. Nada de acá toca Entreno ni la rutina.
 */
@Composable
internal fun TomaPresionPantalla(modelo: ModeloPresion, alCerrar: () -> Unit) {
    val local by modelo.local.collectAsStateWithLifecycle()
    val estado by modelo.estado.collectAsStateWithLifecycle()
    val contexto = LocalContext.current
    val foco = LocalFocusManager.current
    val enCurso: EnCursoPresion? = local.enCurso

    var previas by rememberSaveable { mutableStateOf(emptyMap<String, Boolean>()) }
    val ahoraLocal = remember { LocalTime.now() }
    var horaDosis by rememberSaveable { mutableStateOf(ahoraLocal.hour) }
    var minutoDosis by rememberSaveable { mutableStateOf(ahoraLocal.minute) }
    var entreno by rememberSaveable { mutableStateOf<Boolean?>(null) }
    var queEvitar by rememberSaveable { mutableStateOf(false) }
    var sintoma by rememberSaveable { mutableStateOf(false) }

    val tipo = enCurso?.sesion?.tipo ?: "estandar"
    val guiada = tipo == "ortostatica" || tipo == "comparacion_brazos"
    val brazo = enCurso?.sesion?.brazo
    val sentadoParado = enCurso?.variante == "sentado_parado"
    val pasos = Presion.pasos(tipo, enCurso?.variante)
    val pasoActual = enCurso?.let { pasos.getOrNull(it.paso) }
    val conFoto = estado?.fotos == true
    // Lee `estado` y `local`: se recalcula cuando cambian.
    val serieVista = modelo.serieVista

    fun ir(etapa: String, fin: Long? = null) = modelo.cambiar { it.copy(etapa = etapa, finTemporizador = fin) }

    /** Al salir: una repetición que quedó pendiente se guarda para retomarla; lo demás se cierra (lo anotado ya está en la cola). */
    fun cerrar() {
        val e = modelo.enCurso
        if (e != null && !guiada && e.sesion.tomas.isNotEmpty() && (e.etapa == EtapaPresion.ESPERA || e.etapa == EtapaPresion.ANOTAR)) {
            val ev = modelo.evaluar()
            if (ev != null && (ev.paso == Presion.Paso.REPETIR || ev.paso == Presion.Paso.REPETIR_CON_LISTA)) {
                alCerrar()
                return
            }
        }
        modelo.terminar()
        alCerrar()
    }

    fun empezarReposo() = ir(EtapaPresion.REPOSO, System.currentTimeMillis() + TiemposPresion.ms(Presion.REPOSO_S))

    /** Con el brazo medido: la comparación de brazos va antes de la toma del día, si la serie la pide. */
    fun trasMedir() {
        val s = modelo.serieVista
        if (s != null && s.compararBrazos && modelo.enCurso?.sesion?.serieId == s.id) {
            modelo.empezar("comparacion_brazos", s.id, s.brazo, EtapaPresion.GUIA_INTRO)
        } else {
            ir(EtapaPresion.INSTRUCCIONES)
        }
    }

    /** Qué pantalla sigue según la regla. Se decide en el teléfono, sin esperar al servidor. */
    fun rutear(ev: Presion.Evaluacion) {
        when (ev.paso) {
            Presion.Paso.GUARDIA_SINTOMAS -> ir(EtapaPresion.GUARDIA_SINTOMAS)
            Presion.Paso.GUARDIA_PRESION -> ir(EtapaPresion.GUARDIA_PRESION)
            Presion.Paso.REPETIR, Presion.Paso.REPETIR_CON_LISTA -> {
                val ahora = System.currentTimeMillis()
                ir(EtapaPresion.ESPERA, ahora + TiemposPresion.ms(Presion.ESPERA_REPETICION_S))
                // El recordatorio de los 10 minutos, por si no hace la repetición. Con los tiempos acortados de las pruebas no se agenda.
                if (TiemposPresion.segundosDePrueba == 0) CentroAvisos.programarRepetirPresion(contexto, ahora + Presion.RECORDATORIO_MIN * 60_000L)
            }
            Presion.Paso.LISTO -> ir(EtapaPresion.LISTO)
        }
    }

    fun registrar(sis: Int, dia: Int, pulso: Int, irregular: Boolean, confirmada: Boolean, sintomas: List<String>) {
        CentroAvisos.cancelarRepetirPresion(contexto)
        val p = if (guiada) pasoActual else null
        val ev = modelo.anotarToma(sis, dia, pulso, irregular, p?.posicion ?: "sentado", p?.minutosDePie, p?.brazo, confirmada, sintomas) ?: return
        val e = modelo.enCurso
        if (guiada && ev.paso == Presion.Paso.LISTO && e != null && e.paso + 1 < pasos.size) {
            val sigue = pasos[e.paso + 1]
            modelo.cambiar { it.copy(paso = it.paso + 1, etapa = EtapaPresion.GUIA_ESPERA, finTemporizador = System.currentTimeMillis() + TiemposPresion.ms(sigue.esperaS)) }
            return
        }
        rutear(ev)
    }

    fun marcarMareo() {
        // Marcarlo nunca depende de haber medido: sin ninguna toma viaja como síntoma suelto.
        if (modelo.enCurso?.sesion?.tomas.isNullOrEmpty()) {
            modelo.marcarSintoma(listOf("mareo_al_pararse"), null, sesionId = modelo.enCurso?.sesion?.id)
        } else {
            modelo.sumarSintomas(listOf("mareo_al_pararse"))
        }
        ir(EtapaPresion.MAREO)
    }

    fun tituloPaso(anotando: Boolean): String {
        val e = enCurso ?: return ""
        if (tipo == "ortostatica") {
            val m = pasoActual?.minutosDePie
            if (anotando && m != null) return NP.minutoParado(m)
            return TP.g6(sentadoParado).getOrNull(e.paso) ?: ""
        }
        return if (pasoActual?.brazo == "der") NP.brazoDer else NP.brazoIzq
    }

    // Sin sesión en curso no hay nada que mostrar.
    LaunchedEffect(enCurso == null) { if (enCurso == null) alCerrar() }
    BackHandler { cerrar() }
    if (enCurso == null) {
        Box(Modifier.fillMaxSize().background(MyPump.colores.fondo))
        return
    }

    val abrirSintoma = {
        foco.clearFocus()
        sintoma = true
    }

    /** El marco de un paso: arriba «Cerrar», el contenido y, al final, «Marcar un síntoma» con palabras (nunca solo un ícono). */
    @Composable
    fun Paso(id: String, pie: (@Composable ColumnScope.() -> Unit)? = null, contenido: @Composable ColumnScope.() -> Unit) {
        MarcoPresion(NP.titulo, NP.cerrar, { cerrar() }, etiqueta = id, etiquetaSalir = "presion-flujo-cerrar", pie = pie) {
            contenido()
            BotonPresionSecundario(TP.marcarSintoma, "presion-flujo-sintoma", alTocar = abrirSintoma)
        }
    }

    val tapado = sintoma || queEvitar
    Box(Modifier.fillMaxSize()) {
        Box(if (tapado) Modifier.fillMaxSize().clearAndSetSemantics { } else Modifier.fillMaxSize()) {
            when (enCurso.etapa) {
                EtapaPresion.MEDIR -> AparatoPresionPantalla(modelo, ModoAparato.MEDIR_DE_NUEVO, alSalir = { cerrar() }, alGuardar = { trasMedir() }, alMarcarSintoma = abrirSintoma)

                // «Cuándo», o las indicaciones de la toma bajo efecto. Un paso por pantalla: «Cómo» va en la siguiente.
                EtapaPresion.INSTRUCCIONES -> Paso("presion-paso-cuando", pie = { BotonPresion(NP.seguir, "presion-cuando-seguir") { ir(EtapaPresion.COMO) } }) {
                    if (tipo == "bajo_efecto") {
                        Tarjeta(Modifier.testTag("presion-bajo-efecto")) { PasosPresion(TP.bajoEfecto) }
                    } else {
                        TituloPresion(TP.cuandoTitulo)
                        Tarjeta(Modifier.testTag("presion-cuando")) { PasosPresion(TP.cuando) }
                        BotonPresionSecundario(TP.queEvitar, "presion-que-evitar") { queEvitar = true }
                    }
                }

                EtapaPresion.COMO -> Paso(
                    "presion-paso-como",
                    pie = {
                        BotonPresion(NP.empezar, "presion-empezar") { ir(EtapaPresion.PREVIA) }
                        BotonPresionSecundario(NP.volver, "presion-como-volver") { ir(EtapaPresion.INSTRUCCIONES) }
                    },
                ) {
                    TituloPresion(TP.comoTitulo, Modifier.testTag("presion-como"))
                    LaminaPresion("presion_g1_postura", TP.g1Alt, TP.g1)
                    Tarjeta {
                        DibujoPresion("presion_g2_altura_brazo", TP.g2Alt, Modifier.widthIn(max = 420.dp).fillMaxWidth().align(Alignment.CenterHorizontally))
                        TP.g2.forEachIndexed { i, t ->
                            val marca = if (i == 1) TP.bien else TP.asiNo
                            Row(
                                Modifier.fillMaxWidth().clearAndSetSemantics { contentDescription = "$marca. ${t[0]}. ${t[1]}" },
                                horizontalArrangement = Arrangement.spacedBy(Espacio.s),
                                verticalAlignment = Alignment.Top,
                            ) {
                                DibujoPresion(if (i == 1) "presion_tilde" else "presion_cruz", marca, Modifier.size(24.dp))
                                Column(Modifier.weight(1f)) {
                                    TextoPresion(t[0], estilo = MaterialTheme.typography.titleSmall, fuerte = true)
                                    TextoPresion(t[1], estilo = MaterialTheme.typography.bodyMedium, secundario = true)
                                }
                            }
                        }
                    }
                    LaminaPresion("presion_g4_colocar_manguito", TP.g4Alt, TP.g4)
                    // Numerados corridos desde 1, igual en las tres plataformas (los números de adentro del dibujo son de su leyenda).
                    Tarjeta(Modifier.testTag("presion-como-pasos")) { PasosPresion(TP.como(brazo)) }
                }

                EtapaPresion.PREVIA -> {
                    val claves = listOf("cafeina", "fumo", "comida", "ejercicio")
                    Paso(
                        "presion-paso-previa",
                        pie = {
                            if (tipo == "bajo_efecto") {
                                BotonPresion(NP.seguir, "presion-previa-seguir", habilitado = entreno != null) {
                                    val zona = ZoneId.systemDefault()
                                    var dosis = LocalDate.now(zona).atTime(horaDosis, minutoDosis).atZone(zona).toInstant()
                                    // Una hora que todavía no llegó es de ayer.
                                    if (dosis.toEpochMilli() > System.currentTimeMillis()) dosis = dosis.minus(1, ChronoUnit.DAYS)
                                    val hora = dosis.truncatedTo(ChronoUnit.SECONDS).toString()
                                    modelo.cambiar { it.copy(sesion = it.sesion.copy(dosisEstimulanteHora = hora, entrenoEntreDosisYToma = entreno)) }
                                    empezarReposo()
                                }
                            } else {
                                BotonPresion(NP.seguir, "presion-previa-seguir", habilitado = claves.all { it in previas }) {
                                    val p = Presion.Previo(previas["cafeina"] == true, previas["fumo"] == true, previas["comida"] == true, previas["ejercicio"] == true)
                                    modelo.cambiar { it.copy(sesion = it.sesion.copy(previo = p)) }
                                    if (p.alguno) ir(EtapaPresion.ESPERAR_MEJOR) else empezarReposo()
                                }
                            }
                        },
                    ) {
                        TituloPresion(NP.previas)
                        if (tipo == "bajo_efecto") {
                            Tarjeta {
                                TextoPresion(NP.horaDosis)
                                RuedaHora(horaDosis, minutoDosis, { h, m ->
                                    horaDosis = h
                                    minutoDosis = m
                                }, Modifier.fillMaxWidth().testTag("presion-hora-dosis"))
                                Separador()
                                FilaSiNoPresion(NP.entrenoEntre, entreno, "presion-entreno-entre") { entreno = it }
                            }
                        } else {
                            for (k in claves) Tarjeta(relleno = 12.dp) { FilaSiNoPresion(NP.previa[k] ?: k, previas[k], "presion-previa-$k") { previas = previas + (k to it) } }
                        }
                    }
                }

                EtapaPresion.ESPERAR_MEJOR -> Paso(
                    "presion-paso-esperar",
                    pie = {
                        BotonPresion(NP.esperar, "presion-esperar") {
                            modelo.terminar()
                            alCerrar()
                        }
                        BotonPresionSecundario(NP.medirIgual, "presion-medir-igual") { empezarReposo() }
                    },
                ) {
                    Tarjeta { TextoPresion(NP.esperarMejor, Modifier.testTag("presion-esperar-mejor"), estilo = MaterialTheme.typography.titleLarge, fuerte = true) }
                }

                EtapaPresion.REPOSO -> Paso("presion-paso-reposo") {
                    TextoPresion(NP.reposo, Modifier.testTag("presion-reposo"), estilo = MaterialTheme.typography.titleMedium, fuerte = true)
                    enCurso.finTemporizador?.let { fin ->
                        TemporizadorPresion(fin, voz = NP.reposo, vozFin = NP.anotar) {
                            modelo.cambiar {
                                it.copy(sesion = it.sesion.copy(reposoCumplido = true, temporizadorSalteado = false), etapa = EtapaPresion.ANOTAR, finTemporizador = null)
                            }
                        }
                    }
                    BotonPresionSecundario(NP.saltear, "presion-saltear") {
                        modelo.cambiar {
                            it.copy(sesion = it.sesion.copy(reposoCumplido = false, temporizadorSalteado = true), etapa = EtapaPresion.ANOTAR, finTemporizador = null)
                        }
                    }
                }

                EtapaPresion.ANOTAR -> key(enCurso.sesion.tomas.size) {
                    AnotarPresion(null, conFoto, preguntaSintomas = true, alSalir = { cerrar() }, registrar = ::registrar) {
                        BotonPresionSecundario(TP.marcarSintoma, "presion-flujo-sintoma", alTocar = abrirSintoma)
                    }
                }

                EtapaPresion.ESPERA -> {
                    val ev = modelo.evaluar()
                    val fin = enCurso.finTemporizador
                    var terminada by remember(fin) { mutableStateOf(fin == null || fin <= System.currentTimeMillis()) }
                    Paso("presion-paso-espera", pie = if (terminada) ({ BotonPresion(NP.repetir, "presion-repetir-toma") { ir(EtapaPresion.ANOTAR) } }) else null) {
                        TextoPresion(
                            if (ev?.texto == "repetir_pendiente") TP.repetirPendiente else TP.esperaTitulo,
                            Modifier.testTag("presion-espera"), estilo = MaterialTheme.typography.titleMedium, fuerte = true,
                        )
                        if (fin != null && !terminada) TemporizadorPresion(fin, voz = TP.esperaVoz, vozFin = NP.repetir) { terminada = true }
                        if (ev?.paso == Presion.Paso.REPETIR_CON_LISTA) {
                            Tarjeta(Modifier.testTag("presion-espera-sintomas")) {
                                TextoPresion(TP.esperaLista, estilo = MaterialTheme.typography.titleMedium, fuerte = true)
                                ListaAlarmaPresion(enCurso.lista) { codigo, si ->
                                    // Con un Sí, la guardia por síntomas en el acto, sin esperar la repetición.
                                    if (modelo.responderLista(codigo, si)?.paso == Presion.Paso.GUARDIA_SINTOMAS) ir(EtapaPresion.GUARDIA_SINTOMAS)
                                }
                            }
                        }
                    }
                }

                EtapaPresion.GUARDIA_PRESION -> GuardiaPresion(porSintomas = false, alCerrar = { cerrar() })
                EtapaPresion.GUARDIA_SINTOMAS -> GuardiaPresion(porSintomas = true, alCerrar = { cerrar() })

                EtapaPresion.LISTO -> {
                    val ev = modelo.evaluar()
                    val e = enCurso
                    val s = serieVista?.takeIf { e.sesion.serieId != null && it.id == e.sesion.serieId }
                    // Lo que sigue después de esta sesión, si la serie lo pide: la ortostática va después de la toma sentado; la
                    // comparación de brazos va antes de la toma del día, así que al terminarla sigue la toma si hoy no la hizo.
                    val sigue: String? = when {
                        s == null -> null
                        tipo == "estandar" || tipo == "bajo_efecto" -> if (s.ortostatica != null) "ortostatica" else null
                        tipo == "comparacion_brazos" -> if (modelo.hoy !in s.dias && s.faltan > 0) s.tipo else null
                        else -> null
                    }
                    val completo = run {
                        val servidor = estado?.serie
                        if (e.sesion.serieId == null || servidor == null) return@run false
                        if (guiada || modelo.hoy in servidor.dias) return@run servidor.faltan == 0
                        val vale = if (servidor.tipo == "bajo_efecto") ev?.validaBajoEfecto == true else ev?.cuenta == true
                        vale && servidor.faltan <= 1
                    }
                    LaunchedEffect(Unit) { CentroAvisos.cancelarRepetirPresion(contexto) }
                    Paso(
                        "presion-paso-listo",
                        pie = {
                            if (sigue != null) {
                                BotonPresion(NP.seguir, "presion-seguir") {
                                    val v = modelo.serieVista
                                    if (sigue == "ortostatica") {
                                        modelo.empezar(sigue, v?.id, brazo, EtapaPresion.GUIA_INTRO, variante = v?.ortostatica)
                                    } else {
                                        modelo.empezar(sigue, v?.id, v?.brazo, EtapaPresion.INSTRUCCIONES)
                                    }
                                }
                            } else {
                                BotonPresion(NP.cerrar, "presion-cerrar") { cerrar() }
                            }
                        },
                    ) {
                        Tarjeta {
                            if (ev?.texto == "toma_no_cuenta") TextoPresion(TP.noCuenta, Modifier.testTag("presion-no-cuenta"))
                            if (ev?.texto == "sentate_agua") TextoPresion(TP.sentateAgua, Modifier.testTag("presion-sentate-agua"))
                            if (e.sesion.tomas.any { it.latidoIrregular }) TextoPresion(TP.latidoIrregular, Modifier.testTag("presion-latido-irregular"))
                            val titular = MaterialTheme.typography.titleMedium
                            if (sigue == null) {
                                // En una toma suelta, «Anotado.»; en serie, el cierre del protocolo (si la toma no cuenta, ya lo dice arriba).
                                when {
                                    tipo == "suelta" -> TextoPresion(NP.sintomaRecibido, Modifier.testTag("presion-listo"), estilo = titular, fuerte = true)
                                    completo -> TextoPresion(TP.listoSerie, Modifier.testTag("presion-listo"), estilo = titular, fuerte = true)
                                    ev?.texto != "toma_no_cuenta" -> TextoPresion(TP.como(brazo).last(), Modifier.testTag("presion-listo"), estilo = titular, fuerte = true)
                                }
                            } else {
                                e.sesion.tomas.lastOrNull()?.let { u ->
                                    TextoPresion("${u.sis}/${u.dia}  ${NP.pulso} ${u.pulso}", Modifier.testTag("presion-anotada"), estilo = Numeros.grande, fuerte = true)
                                }
                            }
                        }
                    }
                }

                EtapaPresion.GUIA_INTRO -> Paso(
                    "presion-paso-guia",
                    pie = {
                        BotonPresion(NP.empezar, "presion-empezar") {
                            val s = pasos.firstOrNull()?.esperaS ?: Presion.REPOSO_S
                            modelo.cambiar { it.copy(paso = 0, etapa = EtapaPresion.GUIA_ESPERA, finTemporizador = System.currentTimeMillis() + TiemposPresion.ms(s)) }
                        }
                    },
                ) {
                    if (tipo == "ortostatica") {
                        Tarjeta(Modifier.testTag("presion-ortostatica")) {
                            DibujoPresion(
                                if (sentadoParado) "presion_g6_ortostatica_sentado" else "presion_g6_ortostatica", TP.g6Alt,
                                Modifier.widthIn(max = 420.dp).fillMaxWidth().align(Alignment.CenterHorizontally),
                            )
                            PasosPresion(TP.g6(sentadoParado))
                            TextoPresion(TP.g6Antebrazo, estilo = MaterialTheme.typography.bodyMedium, secundario = true)
                            TextoPresion(TP.g6Mareo, estilo = MaterialTheme.typography.titleSmall, fuerte = true)
                        }
                        Tarjeta { PasosPresion(TP.ortostatica(sentadoParado)) }
                    } else {
                        Column(Modifier.testTag("presion-brazos"), verticalArrangement = Arrangement.spacedBy(Espacio.s)) {
                            for (t in TP.brazos) Tarjeta(relleno = 12.dp) { TextoPresion(t) }
                        }
                    }
                }

                EtapaPresion.GUIA_ESPERA -> {
                    val titulo = tituloPaso(anotando = false)
                    Paso("presion-paso-guia-espera") {
                        TituloPresion(titulo, Modifier.testTag("presion-guia-titulo"))
                        enCurso.finTemporizador?.let { fin ->
                            TemporizadorPresion(fin, voz = titulo, vozFin = NP.anotar) { modelo.cambiar { it.copy(etapa = EtapaPresion.GUIA_ANOTAR, finTemporizador = null) } }
                        }
                        if (tipo == "ortostatica") BotonPresionSecundario(NP.meMaree, "presion-me-maree") { marcarMareo() }
                    }
                }

                EtapaPresion.GUIA_ANOTAR -> key(enCurso.paso) {
                    AnotarPresion(
                        tituloPaso(anotando = true), conFoto, preguntaSintomas = pasoActual?.posicion == "sentado" && tipo == "ortostatica", alSalir = { cerrar() },
                        registrar = ::registrar,
                    ) {
                        if (tipo == "ortostatica") BotonPresionSecundario(NP.meMaree, "presion-me-maree") { marcarMareo() }
                        BotonPresionSecundario(TP.marcarSintoma, "presion-flujo-sintoma", alTocar = abrirSintoma)
                    }
                }

                EtapaPresion.MAREO -> Paso("presion-paso-mareo", pie = { BotonPresion(NP.cerrar, "presion-cerrar") { cerrar() } }) {
                    Tarjeta { TextoPresion(TP.mareoOrtostatica, Modifier.testTag("presion-mareo"), estilo = MaterialTheme.typography.titleMedium, fuerte = true) }
                }

                else -> Box(Modifier.fillMaxSize())
            }
        }
        if (queEvitar) QueEvitarPresion { queEvitar = false }
        if (sintoma) MarcarSintomaPresion(modelo) { sintoma = false }
    }
}
