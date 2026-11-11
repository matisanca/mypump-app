package com.pumpteam.mypump.revision

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.saveable.Saver
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.pumpteam.mypump.datos.ModeloFotos
import com.pumpteam.mypump.datos.ModeloRevision
import com.pumpteam.mypump.diseno.AnchoLectura
import com.pumpteam.mypump.diseno.Espacio
import com.pumpteam.mypump.diseno.Iconos
import com.pumpteam.mypump.diseno.MyPump
import com.pumpteam.mypump.diseno.Radio
import com.pumpteam.mypump.diseno.superficieTarjeta
import com.pumpteam.mypump.entreno.Letras
import com.pumpteam.mypump.modelos.ValorJson
import com.pumpteam.mypump.raiz.LocalAlcanceApp
import com.pumpteam.mypump.reglas.CheckGuiado
import com.pumpteam.mypump.reglas.CheckGuiado.Paso
import com.pumpteam.mypump.reglas.CheckinSemanal
import com.pumpteam.mypump.reglas.FotosProgreso
import com.pumpteam.mypump.reglas.PesoCorporal
import com.pumpteam.mypump.reglas.SaludSemana
import com.pumpteam.mypump.salud.PantallaSuperpuesta
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * El check guiado (2.3.0): el check de la semana a pantalla completa, un paso por pantalla. Arriba, cerrar (guarda el
 * borrador y sale, sin preguntar), el avance en segmentos y «2 de 5»; abajo, fijo, el botón principal y las salidas
 * discretas («Atrás», «Hoy no me pesé»). El contenido desliza; con el teclado abierto el botón sube con él.
 *
 * Escribe lo mismo que el check de siempre (`ModeloRevision.enviarGuiado`: `checkin` y `peso` idénticos) más lo marcado en
 * «¿Notaste algo?». El peso se guarda al pasar su paso; las fotos, con el componente y la subida de «Fotos de la semana».
 * Cada cambio deja el borrador en el teléfono: al volver se abre donde quedó ([pasoInicial] lo pisa: «Subir fotos»).
 */
@Composable
internal fun CheckGuiadoFlujo(
    revision: ModeloRevision,
    fotos: ModeloFotos?,
    salud: List<SaludSemana.Fila>,
    pasoInicial: Paso?,
    alEnviar: () -> Unit,
    alCerrar: () -> Unit,
) {
    val alcance = LocalAlcanceApp.current
    val tactil = LocalHapticFeedback.current
    val foco = LocalFocusManager.current
    val c = MyPump.colores
    val deLaSemana = fotosDeLaSemana(fotos)
    val guardado = revision.checkin.collectAsStateWithLifecycle().value
    val servidor = revision.guiado.collectAsStateWithLifecycle().value
    val filasDePeso = revision.salud.collectAsStateWithLifecycle().value
    val hoy = revision.fecha.collectAsStateWithLifecycle().value
    val yaEnviado = (guardado?.valores?.get("energia") ?: 0) > 0

    // La lista de pasos se arma una vez, al abrir: subir la última foto no saca el paso de las fotos de abajo de los pies.
    val conFotos = rememberSaveable { fotos != null && (deLaSemana.hechas.size < 3 || pasoInicial == Paso.FOTOS) }
    val pasos = remember(conFotos) { CheckGuiado.pasos(conFotos) }
    var b by rememberSaveable(stateSaver = GuardadorBorrador) {
        var x = revision.abrirGuiado()
        if (pasoInicial != null && pasoInicial in pasos) x = x.copy(paso = pasoInicial)
        // Si hoy ya hay un peso cargado, viene puesto.
        if (x.peso.isBlank()) revision.pesoDeHoy?.let { x = x.copy(peso = PesoCorporal.kg(it)) }
        mutableStateOf(x)
    }
    // Solo lo que el alumno tocó se guarda como borrador: abrir y cerrar no deja nada.
    var tocado by rememberSaveable { mutableStateOf(false) }
    var listo by rememberSaveable { mutableStateOf(false) }
    var enviando by remember { mutableStateOf(false) }
    var aviso by rememberSaveable { mutableStateOf<String?>(null) }
    var mensajeFotos by remember { mutableStateOf<String?>(null) }
    // Se llegó a un paso desde una fila del resumen: «Seguir» y «Atrás» vuelven al resumen.
    var desdeResumen by rememberSaveable { mutableStateOf(false) }
    val paso = CheckGuiado.retomar(b, pasos)
    val indice = pasos.indexOf(paso)

    fun cambiar(nuevo: CheckGuiado.Borrador) {
        if (nuevo == b) return
        b = nuevo
        tocado = true
        aviso = null
    }

    fun guardarYa() {
        if (tocado && !listo) revision.guardarBorrador(b)
    }

    fun ir(a: Paso) {
        foco.clearFocus()
        cambiar(b.copy(paso = a))
        guardarYa()
    }

    fun cerrar() {
        foco.clearFocus()
        guardarYa()
        alCerrar()
    }

    // El borrador queda en el teléfono poco después de cada cambio (no en cada letra de la nota) y siempre al salir.
    LaunchedEffect(b, tocado) {
        if (!tocado || listo) return@LaunchedEffect
        delay(400)
        revision.guardarBorrador(b)
    }
    val alSalir by rememberUpdatedState(::guardarYa)
    DisposableEffect(Unit) { onDispose { alSalir() } }

    // Si mientras está abierto llega que el perfil cambió, lo marcado con la otra lista no vale (como al abrir).
    val catalogo = CheckGuiado.Catalogo.de(servidor?.enCiclo ?: false)
    LaunchedEffect(catalogo) {
        if (!listo && b.catalogo != catalogo) b = b.copy(catalogo = catalogo, senales = emptyList())
    }
    // Cambió la semana con el check abierto (la medianoche del domingo): este borrador ya no es de esta semana.
    LaunchedEffect(hoy) {
        if (!listo && FotosProgreso.lunes(hoy) != b.semana) alCerrar()
    }

    fun avanzar() {
        if (desdeResumen) {
            desdeResumen = false
            ir(Paso.RESUMEN)
        } else {
            ir(pasos.getOrElse(indice + 1) { Paso.RESUMEN })
        }
    }

    fun atras() {
        if (desdeResumen) {
            desdeResumen = false
            ir(Paso.RESUMEN)
        } else if (indice > 0) {
            ir(pasos[indice - 1])
        }
    }

    fun enviar() {
        foco.clearFocus()
        CheckGuiado.pasoQueFalta(b)?.let { falta ->
            desdeResumen = true
            ir(falta)
            return
        }
        if (enviando) return
        enviando = true
        val mandado = b
        alcance.launch {
            val falta = try {
                revision.enviarGuiado(mandado)
            } finally {
                enviando = false
            }
            if (falta == null) {
                tocado = false
                listo = true
                alEnviar()
                tactil.performHapticFeedback(HapticFeedbackType.Confirm)
            } else {
                tactil.performHapticFeedback(HapticFeedbackType.Reject)
                if (falta == CheckGuiado.AVISO_RANGO_PESO) {
                    desdeResumen = true
                    ir(Paso.PESO)
                }
                aviso = falta
            }
        }
    }

    fun seguir() {
        when (paso) {
            Paso.PESO -> {
                if (PesoCorporal.leer(b.peso) == null) {
                    aviso = CheckGuiado.AVISO_RANGO_PESO
                    tactil.performHapticFeedback(HapticFeedbackType.Reject)
                    return
                }
                // Se guarda en el momento, por la misma cola que la tarjeta de peso (el mismo de hoy no se manda de nuevo).
                val kilos = b.peso
                alcance.launch { revision.guardarPesoGuiado(kilos) }
                avanzar()
            }
            Paso.RESUMEN -> enviar()
            else -> if (CheckGuiado.puedeSeguir(paso, b, deLaSemana.hechas.size)) avanzar()
        }
    }

    fun omitir() {
        if (paso == Paso.PESO) cambiar(b.copy(peso = ""))
        avanzar()
    }

    PantallaSuperpuesta(alCerrar = ::cerrar) {
        Column(
            Modifier
                .fillMaxSize()
                .background(c.fondo)
                .windowInsetsPadding(WindowInsets.safeDrawing)
                .testTag("check-guiado"),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Column(Modifier.widthIn(max = AnchoLectura).fillMaxSize()) {
                if (listo) {
                    PasoListo(alCerrar = alCerrar)
                    return@Column
                }
                BarraCheck(indice, pasos.size, conAtras = indice > 0 || desdeResumen, alCerrar = ::cerrar, alAtras = ::atras)
                AnimatedContent(
                    targetState = paso,
                    transitionSpec = { fadeIn() togetherWith fadeOut() },
                    modifier = Modifier.weight(1f).fillMaxWidth(),
                    label = "check-paso",
                ) { p ->
                    key(p) {
                        Column(
                            Modifier
                                .fillMaxSize()
                                .verticalScroll(rememberScrollState())
                                .padding(horizontal = EstiloCheck.margen)
                                .padding(top = Espacio.s, bottom = Espacio.xl)
                                .testTag("cg-paso-${p.clave}"),
                            verticalArrangement = Arrangement.spacedBy(Espacio.l),
                        ) {
                            Column(verticalArrangement = Arrangement.spacedBy(Espacio.xs)) {
                                Text(
                                    CheckGuiado.titulo(p, b.catalogo),
                                    style = EstiloCheck.titulo,
                                    color = c.texto,
                                    modifier = Modifier.semantics { heading() }.testTag("cg-titulo"),
                                )
                                Text(CheckGuiado.apoyo(p, b.catalogo), style = MaterialTheme.typography.bodyLarge, color = c.textoSecundario)
                            }
                            when (p) {
                                Paso.PESO -> PasoPeso(
                                    peso = b.peso,
                                    media = remember(filasDePeso, hoy) { PesoCorporal.media(PesoCorporal.serie(filasDePeso), hoy, 7) },
                                    alCambiar = { cambiar(b.copy(peso = it)) },
                                    alTerminar = { if (CheckGuiado.puedeSeguir(Paso.PESO, b)) seguir() },
                                )
                                Paso.ESCALAS -> Column(verticalArrangement = Arrangement.spacedBy(22.dp)) {
                                    for (m in CheckinSemanal.metricas) {
                                        EscalaCheck(m, b.valores[m.clave]) { v ->
                                            cambiar(b.copy(valores = if (v == null) b.valores - m.clave else b.valores + (m.clave to v)))
                                            tactil.performHapticFeedback(HapticFeedbackType.SegmentTick)
                                        }
                                    }
                                }
                                Paso.FOTOS -> PasoFotos(fotos, deLaSemana, mensajeFotos) { mensajeFotos = it }
                                Paso.SENALES -> Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                                    for (o in CheckGuiado.opciones(b.catalogo)) {
                                        FilaSeleccionCheck(
                                            o.etiqueta,
                                            elegida = o.clave in b.senales,
                                            alTocar = {
                                                cambiar(b.copy(senales = CheckGuiado.alternar(b.senales, o.clave)))
                                                tactil.performHapticFeedback(HapticFeedbackType.SegmentTick)
                                            },
                                            modifier = Modifier.testTag("cg-senal-${o.clave}"),
                                        )
                                    }
                                }
                                Paso.NOTA -> PasoNota(b.nota) { cambiar(b.copy(nota = it)) }
                                Paso.RESUMEN -> PasoResumen(
                                    b = b,
                                    conFotos = fotos != null,
                                    fotosTocables = Paso.FOTOS in pasos,
                                    fotosHechas = deLaSemana.hechas.size,
                                    salud = salud,
                                    alIr = { destino ->
                                        desdeResumen = true
                                        ir(destino)
                                    },
                                )
                            }
                        }
                    }
                }
                PieCheck(
                    paso = paso,
                    principal = when {
                        paso != Paso.RESUMEN -> "Seguir"
                        yaEnviado -> "Actualizar mi check"
                        else -> "Enviar mi check"
                    },
                    habilitado = !enviando && (paso == Paso.RESUMEN || CheckGuiado.puedeSeguir(paso, b, deLaSemana.hechas.size)),
                    aviso = aviso ?: when (paso) {
                        // Con alguna escala elegida ya se dice cuáles faltan (sin nada, el botón gris se entiende solo).
                        Paso.ESCALAS -> CheckinSemanal.faltan(b.valores)?.takeIf { b.valores.values.any { v -> v > 0 } }
                        Paso.RESUMEN -> CheckGuiado.faltaParaEnviar(b)
                        else -> null
                    },
                    esProblema = aviso != null,
                    omitir = CheckGuiado.omitir(paso)?.takeIf { !desdeResumen || paso == Paso.PESO },
                    alSeguir = ::seguir,
                    alOmitir = ::omitir,
                )
            }
        }
    }
}

/** El borrador entre rotaciones y muertes del proceso, con las mismas claves que en el disco. */
private val GuardadorBorrador: Saver<CheckGuiado.Borrador, String> = Saver(
    save = { it.aValor().serializar() },
    restore = { texto -> runCatching { CheckGuiado.Borrador.desde(ValorJson.parsear(texto)) }.getOrNull() },
)

/**
 * Arriba: «Salir» y «Atrás» con texto (ningún botón es solo un ícono), «Paso 2 de 5» con palabras y, debajo, el avance en
 * segmentos (hasta el paso de ahora, inclusive).
 */
@Composable
private fun BarraCheck(indice: Int, total: Int, conAtras: Boolean, alCerrar: () -> Unit, alAtras: () -> Unit) {
    val c = MyPump.colores
    Column(
        Modifier.fillMaxWidth().padding(horizontal = EstiloCheck.margen).padding(top = Espacio.xs, bottom = Espacio.xs),
        verticalArrangement = Arrangement.spacedBy(Espacio.xs),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espacio.xs)) {
            BotonBarraCheck("Salir", Iconos.Cerrar, alCerrar, Modifier.testTag("cg-cerrar"))
            if (conAtras) BotonBarraCheck("Atrás", null, alAtras, Modifier.testTag("cg-atras"))
            Text(
                "Paso ${indice + 1} de $total",
                style = MaterialTheme.typography.bodyLarge.merge(Letras.cifras),
                fontWeight = FontWeight.SemiBold,
                color = c.textoSecundario,
                textAlign = TextAlign.End,
                maxLines = 1,
                modifier = Modifier.weight(1f).testTag("cg-avance"),
            )
        }
        // Los segmentos repiten lo que ya dice el texto: para el lector de pantalla no existen.
        AvanceCheck(total, indice + 1, Modifier.fillMaxWidth())
    }
}

/** Un botón de la barra de arriba: cápsula gris de 48 con texto (y la X en «Salir»). */
@Composable
private fun BotonBarraCheck(texto: String, icono: ImageVector?, alTocar: () -> Unit, modifier: Modifier = Modifier) {
    val c = MyPump.colores
    Row(
        modifier
            .heightIn(min = 48.dp)
            .clip(CircleShape)
            .background(c.campo)
            .clickable(role = Role.Button, onClick = alTocar)
            .padding(horizontal = 16.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        if (icono != null) Icon(icono, contentDescription = null, tint = c.texto, modifier = Modifier.size(16.dp))
        Text(texto, style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.SemiBold, color = c.texto, maxLines = 1)
    }
}

/**
 * Abajo, fijo: lo que falta (si hay), el botón principal (uno solo por pantalla) y, debajo, la salida discreta del paso
 * («Hoy no me pesé», «Las subo después»), también de ancho completo y con texto.
 */
@Composable
private fun PieCheck(
    paso: Paso,
    principal: String,
    habilitado: Boolean,
    aviso: String?,
    esProblema: Boolean,
    omitir: String?,
    alSeguir: () -> Unit,
    alOmitir: () -> Unit,
) {
    val c = MyPump.colores
    Column(
        Modifier.fillMaxWidth().padding(horizontal = EstiloCheck.margen).padding(top = Espacio.xs, bottom = Espacio.xs),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(Espacio.xs),
    ) {
        if (aviso != null) {
            Text(
                aviso,
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.Medium,
                color = if (esProblema) c.alerta else c.textoSecundario,
                textAlign = TextAlign.Center,
                modifier = Modifier.testTag("cg-falta"),
            )
        }
        BotonPrincipalCheck(principal, alSeguir, Modifier.testTag(if (paso == Paso.RESUMEN) "cg-enviar" else "cg-seguir"), habilitado = habilitado)
        if (omitir != null) SalidaDiscretaCheck(omitir, alOmitir, Modifier.testTag("cg-omitir"))
    }
}

/** El peso de hoy: el número grande, editable, con «kg» al lado. */
@Composable
private fun PasoPeso(peso: String, media: Double?, alCambiar: (String) -> Unit, alTerminar: () -> Unit) {
    val c = MyPump.colores
    // El campo mide lo que mide lo escrito (o el ejemplo): así el número y «kg» quedan juntos y al centro.
    val medidor = rememberTextMeasurer()
    val estiloEjemplo = EstiloCheck.peso.copy(fontSize = 44.sp)
    val ancho = with(LocalDensity.current) {
        (if (peso.isEmpty()) medidor.measure("Ej: 78,4", estiloEjemplo, maxLines = 1) else medidor.measure(peso, EstiloCheck.peso, maxLines = 1)).size.width.toDp()
    } + 16.dp
    Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(Espacio.s)) {
        Row(
            Modifier.fillMaxWidth().padding(top = Espacio.m),
            horizontalArrangement = Arrangement.spacedBy(Espacio.xs, Alignment.CenterHorizontally),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            BasicTextField(
                value = peso,
                // Solo lo que puede ser un peso: dígitos y una coma o un punto.
                onValueChange = { nuevo -> alCambiar(nuevo.filter { it.isDigit() || it == ',' || it == '.' }.take(6)) },
                singleLine = true,
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal, imeAction = ImeAction.Done),
                keyboardActions = KeyboardActions(onDone = { alTerminar() }),
                // A la izquierda dentro de un campo que mide justo lo escrito: el cursor queda antes del ejemplo, no cruzándolo.
                textStyle = EstiloCheck.peso.copy(color = c.texto, textAlign = TextAlign.Start),
                cursorBrush = SolidColor(c.marcaTexto),
                modifier = Modifier
                    .weight(1f, fill = false)
                    .width(ancho)
                    .semantics { contentDescription = "Tu peso de hoy, en kilos" }
                    .testTag("cg-peso"),
                decorationBox = { campo ->
                    Box(Modifier.heightIn(min = with(LocalDensity.current) { EstiloCheck.peso.lineHeight.toDp() }).padding(horizontal = 8.dp), contentAlignment = Alignment.CenterStart) {
                        if (peso.isEmpty()) {
                            Text(
                                "Ej: 78,4",
                                style = estiloEjemplo,
                                color = c.textoTerciario,
                                maxLines = 1,
                                softWrap = false,
                                modifier = Modifier.clearAndSetSemantics {},
                            )
                        }
                        campo()
                    }
                },
            )
            Text("kg", style = EstiloCheck.unidad, color = c.textoSecundario, modifier = Modifier.clearAndSetSemantics {})
        }
        if (media != null) {
            Text(
                "Media de 7 días: ${PesoCorporal.kg(media)} kg",
                style = MaterialTheme.typography.bodyLarge.merge(Letras.cifras),
                color = c.textoSecundario,
                modifier = Modifier.testTag("cg-peso-media"),
            )
        }
    }
}

/** Los tres marcos de siempre, con la misma subida, y cuántas van. */
@Composable
private fun PasoFotos(modelo: ModeloFotos?, deLaSemana: FotosDeLaSemana, mensaje: String?, alMensaje: (String) -> Unit) {
    val c = MyPump.colores
    // Las miniaturas van con URLs firmadas (el modelo las guarda 50 minutos).
    LaunchedEffect(modelo, deLaSemana.hechas.size) { if (modelo != null && deLaSemana.hechas.isNotEmpty()) modelo.firmar() }
    Column(verticalArrangement = Arrangement.spacedBy(Espacio.s)) {
        MarcosFotosSemana(
            modelo, deLaSemana.semana, deLaSemana.hechas, deLaSemana.pendientes, deLaSemana.urls, deLaSemana.subiendo,
            // Con letra de accesibilidad, los tres marcos pasan a ser filas (como en «Fotos de la semana»).
            enFilas = LocalDensity.current.fontScale >= 1.5f,
            alMensaje = alMensaje,
        )
        Text(
            "${deLaSemana.hechas.size} de 3",
            style = MaterialTheme.typography.bodyLarge.merge(Letras.cifras),
            fontWeight = FontWeight.SemiBold,
            color = if (deLaSemana.hechas.size >= 3) c.marcaTexto else c.textoSecundario,
            modifier = Modifier.testTag("cg-fotos-cuenta"),
        )
        mensaje?.let { m ->
            val problema = m.startsWith("No") || m.startsWith("Esa") || m.startsWith("Hay")
            Text(m, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Medium, color = if (problema) c.alerta else c.marcaTexto, modifier = Modifier.testTag("cg-fotos-mensaje"))
        }
    }
}

/** La nota: un campo grande, opcional. */
@Composable
private fun PasoNota(nota: String, alCambiar: (String) -> Unit) {
    val c = MyPump.colores
    val forma = RoundedCornerShape(Radio.control + 4.dp)
    BasicTextField(
        value = nota,
        onValueChange = alCambiar,
        minLines = 4,
        keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Sentences),
        textStyle = MaterialTheme.typography.bodyLarge.copy(color = c.texto),
        cursorBrush = SolidColor(c.marcaTexto),
        modifier = Modifier.fillMaxWidth().semantics { contentDescription = "Escribí acá (opcional)" }.testTag("cg-nota"),
        decorationBox = { campo ->
            Box(Modifier.fillMaxWidth().clip(forma).background(c.tarjeta).border(1.dp, c.borde, forma).padding(Espacio.m)) {
                if (nota.isEmpty()) {
                    Text("Escribí acá (opcional)", style = MaterialTheme.typography.bodyLarge, color = c.textoTerciario, modifier = Modifier.clearAndSetSemantics {})
                }
                campo()
            }
        },
    )
}

/** El resumen: una fila por dato (tocarla lleva a su paso) y, debajo, la salud de los últimos 7 días que va con el check. */
@Composable
private fun PasoResumen(
    b: CheckGuiado.Borrador,
    conFotos: Boolean,
    fotosTocables: Boolean,
    fotosHechas: Int,
    salud: List<SaludSemana.Fila>,
    alIr: (Paso) -> Unit,
) {
    val c = MyPump.colores
    val sinDato = "Sin contestar"
    Column(verticalArrangement = Arrangement.spacedBy(Espacio.m)) {
        Column(Modifier.fillMaxWidth().superficieTarjeta().testTag("cg-resumen")) {
            val kilos = PesoCorporal.leer(b.peso)
            FilaResumen("Peso", if (kilos != null) "${PesoCorporal.kg(kilos)} kg" else if (b.peso.isBlank()) "Hoy no me pesé" else b.peso, "cg-fila-peso") { alIr(Paso.PESO) }
            CheckinSemanal.metricas.forEachIndexed { i, m ->
                HorizontalDivider(Modifier.padding(start = Espacio.m), color = c.separador, thickness = 0.5.dp)
                val v = b.valores[m.clave] ?: 0
                // La primera lleva el identificador del paso; las otras tres, además, su clave.
                FilaResumen(m.etiqueta, if (v > 0) "$v de 5" else sinDato, if (i == 0) "cg-fila-escalas" else "cg-fila-escalas-${m.clave}", falta = v == 0) { alIr(Paso.ESCALAS) }
            }
            if (conFotos) {
                HorizontalDivider(Modifier.padding(start = Espacio.m), color = c.separador, thickness = 0.5.dp)
                FilaResumen("Fotos", "${fotosHechas.coerceAtMost(3)} de 3", "cg-fila-fotos", alTocar = if (fotosTocables) ({ alIr(Paso.FOTOS) }) else null)
            }
            HorizontalDivider(Modifier.padding(start = Espacio.m), color = c.separador, thickness = 0.5.dp)
            val marcado = CheckGuiado.textoSenales(b.senales, b.catalogo)
            FilaResumen(
                if (b.catalogo == CheckGuiado.Catalogo.CICLO) "Lo que notaste" else "Esta semana",
                marcado.ifEmpty { sinDato },
                "cg-fila-senales",
                falta = marcado.isEmpty(),
            ) { alIr(Paso.SENALES) }
            HorizontalDivider(Modifier.padding(start = Espacio.m), color = c.separador, thickness = 0.5.dp)
            FilaResumen("Nota", b.nota.trim().ifEmpty { "Sin nota" }, "cg-fila-nota") { alIr(Paso.NOTA) }
        }
        if (salud.isNotEmpty()) {
            Box(Modifier.fillMaxWidth().superficieTarjeta().padding(Espacio.m)) { SaludDelCheck(salud) }
        }
    }
}

/** Una fila del resumen: el nombre, lo contestado (hasta tres renglones) y la flecha si se puede tocar. */
@Composable
private fun FilaResumen(etiqueta: String, valor: String, id: String, falta: Boolean = false, alTocar: (() -> Unit)?) {
    val c = MyPump.colores
    Row(
        Modifier
            .fillMaxWidth()
            .heightIn(min = 52.dp)
            .then(if (alTocar != null) Modifier.clickable(role = Role.Button, onClick = alTocar) else Modifier)
            .semantics(mergeDescendants = true) {}
            .testTag(id)
            .padding(horizontal = Espacio.m, vertical = Espacio.s),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(Espacio.s),
    ) {
        Text(etiqueta, style = MaterialTheme.typography.bodyLarge, color = c.textoSecundario)
        Text(
            valor,
            style = MaterialTheme.typography.bodyLarge.merge(Letras.cifras),
            fontWeight = FontWeight.SemiBold,
            color = if (falta) c.alerta else c.texto,
            textAlign = TextAlign.End,
            maxLines = 3,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.weight(1f),
        )
        if (alTocar != null) Icon(Iconos.Chevron, contentDescription = null, tint = c.textoTerciario, modifier = Modifier.size(16.dp))
    }
}

/** Enviado: «Listo», a quién le llega y «Cerrar». */
@Composable
private fun PasoListo(alCerrar: () -> Unit) {
    val c = MyPump.colores
    Column(Modifier.fillMaxSize()) {
        Column(
            Modifier.weight(1f).fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = EstiloCheck.margen, vertical = Espacio.l),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(Espacio.m, Alignment.CenterVertically),
        ) {
            Box(Modifier.size(84.dp).clip(CircleShape).background(c.marca), contentAlignment = Alignment.Center) {
                Icon(Iconos.Tilde, contentDescription = null, tint = c.sobreMarca, modifier = Modifier.size(44.dp))
            }
            Text("Listo", style = EstiloCheck.titulo, color = c.texto, modifier = Modifier.semantics { heading() }.testTag("cg-listo"))
            Text(
                "Mati lo ve antes de tu devolución.",
                style = MaterialTheme.typography.bodyLarge,
                color = c.textoSecundario,
                textAlign = TextAlign.Center,
                modifier = Modifier.testTag("cg-listo-texto"),
            )
        }
        Column(Modifier.fillMaxWidth().padding(horizontal = EstiloCheck.margen).padding(top = Espacio.xs, bottom = Espacio.m)) {
            BotonPrincipalCheck("Cerrar", alCerrar, Modifier.testTag("cg-cerrar-listo"))
        }
    }
}
