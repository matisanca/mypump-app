package com.pumpteam.mypump.estudios

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTagsAsResourceId
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.pumpteam.mypump.datos.EnvioEstudios
import com.pumpteam.mypump.datos.ModeloEstudios
import com.pumpteam.mypump.diseno.AccionHoja
import com.pumpteam.mypump.diseno.AsaHoja
import com.pumpteam.mypump.diseno.BotonMarca
import com.pumpteam.mypump.diseno.BotonSecundario
import com.pumpteam.mypump.diseno.EncabezadoHoja
import com.pumpteam.mypump.diseno.EncabezadoSeccion
import com.pumpteam.mypump.diseno.Espacio
import com.pumpteam.mypump.diseno.FormaHoja
import com.pumpteam.mypump.diseno.Iconos
import com.pumpteam.mypump.diseno.LocalRellenoInferior
import com.pumpteam.mypump.diseno.MarcoPantalla
import com.pumpteam.mypump.diseno.MyPump
import com.pumpteam.mypump.diseno.Separador
import com.pumpteam.mypump.diseno.Tarjeta
import com.pumpteam.mypump.raiz.LocalAlcanceApp
import com.pumpteam.mypump.reglas.ControlEstudios
import com.pumpteam.mypump.reglas.EnvioRecibido
import com.pumpteam.mypump.reglas.EstadoEstudios
import com.pumpteam.mypump.reglas.EstudioRecibido
import com.pumpteam.mypump.reglas.Estudios
import com.pumpteam.mypump.reglas.OrdenEstudios
import com.pumpteam.mypump.reglas.PendienteEstudios
import com.pumpteam.mypump.reglas.TextosEstudios as T
import java.time.LocalDate
import kotlinx.coroutines.flow.filterNotNull
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull

/** Lo que se espera a que la carga de la app lea la palanca al volver de una muerte del proceso. */
private const val ESPERA_PALANCA_MS = 20_000L

/** Sin pedido: «Subir un estudio» suelto. */
private const val SUBIDA_SUELTA = ""

/**
 * «Estudios y órdenes» (`estudios/CONTRATO_APP.md`): lo que falta hacer, las órdenes, lo que ya llegó y la subida. Acá no
 * hay valores, rangos ni interpretación: solo qué se pidió, qué llegó y si Mati ya lo vio.
 */
@Composable
fun EstudiosPantalla(m: ModeloEstudios, alVolver: () -> Unit) {
    val estado by m.estado.collectAsStateWithLifecycle()
    // Al volver de una muerte del proceso el estado todavía no está: se decide después de preguntar.
    var preguntado by remember { mutableStateOf(false) }
    LaunchedEffect(m) {
        // La palanca no se recuerda de una vez para la otra: al volver de una muerte del proceso se espera a que la carga
        // de la app la lea. Sin esa lectura (o apagada) no se llama a nada y la pantalla se cierra.
        if (m.palanca.value == null) withTimeoutOrNull(ESPERA_PALANCA_MS) { m.palanca.filterNotNull().first() }
        m.sincronizar()
        preguntado = true
    }
    LaunchedEffect(preguntado, estado == null) { if (preguntado && estado == null) alVolver() }
    // El «Recibido» de un envío se lee una vez: al salir de la pantalla ya no hace falta.
    DisposableEffect(m) { onDispose { m.limpiarAviso() } }

    var ordenAbierta by rememberSaveable { mutableStateOf<String?>(null) }
    var subida by rememberSaveable { mutableStateOf<String?>(null) }
    var fechaDe by rememberSaveable { mutableStateOf<String?>(null) }
    // Rotar el teléfono no cierra lo que se está mirando (el papel se vuelve a bajar: en el teléfono no queda guardado).
    var abierto by rememberSaveable(stateSaver = Abierto.Guarda) { mutableStateOf<Abierto?>(null) }

    val e = estado ?: return Box(Modifier.fillMaxSize().background(MyPump.colores.fondo))
    val orden = e.orden(ordenAbierta)
    val viendo = abierto
    BackHandler(enabled = orden != null && viendo == null) { ordenAbierta = null }

    fun verOrden(o: OrdenEstudios) {
        abierto = Abierto("orden", o.id, o.titulo)
    }

    when {
        viendo != null -> VisorEstudios(m, viendo, alCerrar = { abierto = null })
        orden != null -> DetalleOrden(orden, alVolver = { ordenAbierta = null }, alVer = { verOrden(orden) })
        else -> Principal(
            m, e, alVolver,
            alSubir = { subida = it ?: SUBIDA_SUELTA },
            alPedirFecha = { fechaDe = it },
            alAbrirOrden = { id ->
                // Con la orden en la lista se abre su detalle; si no está (no debería), el papel directo.
                if (e.orden(id) != null) ordenAbierta = id else abierto = Abierto("orden", id, T.verOrden)
            },
            alVerEstudio = { s -> s.id?.let { abierto = Abierto("estudio", it, s.titulo) } },
        )
    }

    subida?.let { pedido -> SubidaEstudios(m, pedido.ifEmpty { null }, alCerrar = { subida = null }) }
    fechaDe?.let { pedido -> HojaFecha(m, pedido, e.hoy ?: LocalDate.now(), alCerrar = { fechaDe = null }) }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun Principal(
    m: ModeloEstudios,
    e: EstadoEstudios,
    alVolver: () -> Unit,
    alSubir: (String?) -> Unit,
    alPedirFecha: (String) -> Unit,
    alAbrirOrden: (String) -> Unit,
    alVerEstudio: (EstudioRecibido) -> Unit,
) {
    val c = MyPump.colores
    val alcance = LocalAlcanceApp.current
    val cola by m.cola.collectAsStateWithLifecycle()
    val progreso by m.progreso.collectAsStateWithLifecycle()
    val sinSenal by m.sinSenal.collectAsStateWithLifecycle()
    val aviso by m.aviso.collectAsStateWithLifecycle()
    val errorCarga by m.errorCarga.collectAsStateWithLifecycle()
    val detenida by m.detenida.collectAsStateWithLifecycle()
    var recargando by remember { mutableStateOf(false) }
    val hoy = e.hoy
    val bloques = Estudios.bloques(e)

    MarcoPantalla(T.titulo, alVolver = alVolver) { relleno ->
        PullToRefreshBox(
            isRefreshing = recargando,
            onRefresh = {
                recargando = true
                alcance.launch {
                    try {
                        m.sincronizar()   // respeta la palanca: apagada, no llama a nada
                    } finally {
                        recargando = false
                    }
                }
            },
            modifier = Modifier.fillMaxSize().padding(top = relleno.calculateTopPadding()),
        ) {
            Column(
                Modifier
                    .fillMaxSize()
                    .verticalScroll(rememberScrollState())
                    .padding(horizontal = Espacio.m)
                    .padding(top = Espacio.xs, bottom = Espacio.xl + LocalRellenoInferior.current)
                    .testTag("estudios-pantalla"),
                verticalArrangement = Arrangement.spacedBy(Espacio.m),
            ) {
                if (errorCarga) Renglon(Iconos.SinNube, T.errorDeCarga, c.textoSecundario, Modifier.padding(horizontal = Espacio.xxs).testTag("estudios-error-carga"), vivo = true)
                EstadoDeLaSubida(cola, progreso, sinSenal, detenida, aviso, alReintentar = { alcance.launch { m.reintentar() } })

                for (bloque in bloques) {
                    when (bloque) {
                        Estudios.Bloque.VACIO -> Tarjeta(Modifier.testTag("estudios-vacio"), relleno = Espacio.l) {
                            Icon(Iconos.Documento, contentDescription = null, tint = c.marcaTexto, modifier = Modifier.size(28.dp))
                            Text(T.vacio, style = MaterialTheme.typography.bodyLarge, color = c.textoSecundario)
                        }
                        Estudios.Bloque.PROXIMO -> e.proximo?.let { ProximoControl(it) }
                        Estudios.Bloque.PENDIENTES -> Seccion(T.teFaltaHacer) {
                            for (p in e.pendientes) {
                                TarjetaPendiente(m, p, hoy, alSubir = { alSubir(p.id) }, alPedirFecha = { alPedirFecha(p.id) }, alAbrirOrden = alAbrirOrden)
                            }
                        }
                        Estudios.Bloque.SUBIR -> BotonMarca(T.subirUnEstudio, alTocar = { alSubir(null) }, modifier = Modifier.testTag("estudios-subir"))
                        Estudios.Bloque.ORDENES -> Seccion(T.tusOrdenes) {
                            Tarjeta(relleno = 0.dp, espaciado = 0.dp) {
                                e.ordenes.forEachIndexed { i, o ->
                                    if (i > 0) Separador(sangria = 64.dp)
                                    FilaOrden(o) { alAbrirOrden(o.id) }
                                }
                            }
                        }
                        Estudios.Bloque.ESTUDIOS -> Seccion(T.tusEstudios) {
                            Tarjeta(relleno = 0.dp, espaciado = 0.dp) {
                                var primera = true
                                // Primero lo que se mandó desde la app y todavía no se ve como estudio; después, los estudios.
                                for (s in e.envios) {
                                    if (!primera) Separador(sangria = Espacio.m)
                                    primera = false
                                    FilaEnvio(s)
                                }
                                for (s in e.estudios) {
                                    if (!primera) Separador(sangria = Espacio.m)
                                    primera = false
                                    FilaEstudio(s) { alVerEstudio(s) }
                                }
                            }
                            Text(
                                T.notaFija,
                                style = MaterialTheme.typography.bodySmall,
                                color = c.textoSecundario,
                                modifier = Modifier.padding(horizontal = Espacio.xs).testTag("estudios-nota-fija"),
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun Seccion(titulo: String, contenido: @Composable ColumnScope.() -> Unit) {
    Column(Modifier.padding(top = Espacio.xs), verticalArrangement = Arrangement.spacedBy(Espacio.s)) {
        EncabezadoSeccion(titulo)
        contenido()
    }
}

/** Un ícono y un texto en un renglón: lo que se dice no depende solo del color. */
@Composable
private fun Renglon(icono: ImageVector, texto: String, tono: Color, modifier: Modifier = Modifier, vivo: Boolean = false, fuerte: Boolean = false) {
    Row(
        modifier.fillMaxWidth().then(if (vivo) Modifier.semantics { liveRegion = LiveRegionMode.Polite } else Modifier),
        horizontalArrangement = Arrangement.spacedBy(Espacio.xs),
    ) {
        Icon(icono, contentDescription = null, tint = tono, modifier = Modifier.padding(top = 2.dp).size(18.dp))
        Text(texto, style = MaterialTheme.typography.bodyMedium.copy(fontWeight = if (fuerte) FontWeight.SemiBold else FontWeight.Medium), color = tono, modifier = Modifier.weight(1f))
    }
}

/** Lo que pasa con lo que el alumno mandó: subiendo, esperando señal, recibido o por qué no salió. */
@Composable
private fun EstadoDeLaSubida(
    cola: List<EnvioEstudios>,
    progreso: ModeloEstudios.Progreso?,
    sinSenal: Boolean,
    detenida: Boolean,
    aviso: ModeloEstudios.Aviso?,
    alReintentar: () -> Unit,
) {
    val c = MyPump.colores
    if (cola.isEmpty() && aviso == null) return
    Tarjeta(Modifier.testTag("estudios-estado-subida"), espaciado = Espacio.s) {
        if (cola.isNotEmpty()) {
            val primero = cola.first()
            val total = (progreso?.total ?: primero.archivos.size).coerceAtLeast(1)
            val subidos = progreso?.let { it.va - 1 } ?: primero.archivos.count { it.subido }
            val va = (subidos + 1).coerceIn(1, total)
            if (sinSenal && progreso == null) {
                Renglon(Iconos.SinWifi, T.sinSenal, c.textoSecundario, Modifier.testTag("estudios-sin-senal"), vivo = true, fuerte = true)
            } else if (detenida && progreso == null) {
                // La cola quedó parada por algo que no es la red (el link, el servidor): se dice y se ofrece retomarla.
                Renglon(Iconos.Alerta, T.noSePudoEnviar, c.alerta, Modifier.testTag("estudios-detenida"), vivo = true, fuerte = true)
                BotonSecundario(T.probarDeNuevo, alTocar = alReintentar, compacto = true, tono = c.marcaTexto, modifier = Modifier.testTag("estudios-reintentar"))
            } else {
                Text(
                    Estudios.progreso(subidos, total),
                    style = MaterialTheme.typography.titleMedium,
                    color = c.texto,
                    modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite }.testTag("estudios-subiendo"),
                )
                LinearProgressIndicator(
                    progress = { (va - 1).toFloat() / total },
                    modifier = Modifier.fillMaxWidth().clip(CircleShape).clearAndSetSemantics { },
                    color = c.marcaVivo,
                    trackColor = c.campo,
                )
            }
        }
        when (aviso) {
            ModeloEstudios.Aviso.RECIBIDO, ModeloEstudios.Aviso.RECIBIDO_CON_RECHAZO -> {
                Renglon(Iconos.TildeEnCirculo, T.recibidoAviso, c.marcaTexto, Modifier.testTag("estudios-recibido"), vivo = true, fuerte = true)
                if (aviso == ModeloEstudios.Aviso.RECIBIDO_CON_RECHAZO) Renglon(Iconos.Alerta, T.archivoRechazado, c.alerta, Modifier.testTag("estudios-rechazado"), vivo = true)
            }
            ModeloEstudios.Aviso.RECHAZADO -> Renglon(Iconos.Alerta, T.archivoRechazado, c.alerta, Modifier.testTag("estudios-rechazado"), vivo = true, fuerte = true)
            ModeloEstudios.Aviso.TOPE_DIA -> Renglon(Iconos.Alerta, T.topeDia, c.alerta, Modifier.testTag("estudios-tope-dia"), vivo = true, fuerte = true)
            ModeloEstudios.Aviso.ERROR -> Renglon(Iconos.Alerta, T.noSePudoEnviar, c.alerta, Modifier.testTag("estudios-no-se-pudo-enviar"), vivo = true, fuerte = true)
            null -> Unit
        }
    }
}

/** La tarjeta chica de arriba: el control que viene, todavía sin nada para hacer. */
@Composable
private fun ProximoControl(p: ControlEstudios) {
    val c = MyPump.colores
    val cuando = Estudios.cuandoControl(p.desde, p.hasta)
    Row(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(20.dp))
            .background(c.marcaSuave)
            .padding(horizontal = Espacio.m, vertical = Espacio.s)
            .semantics(mergeDescendants = true) { }
            .testTag("estudios-proximo"),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(Espacio.s),
    ) {
        Icon(Iconos.Calendario, contentDescription = null, tint = c.marcaTexto, modifier = Modifier.size(24.dp))
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(T.proximoControl.uppercase(), style = MaterialTheme.typography.labelSmall.copy(letterSpacing = 0.8.sp, fontWeight = FontWeight.SemiBold), color = c.marcaTexto)
            Text(p.titulo, style = MaterialTheme.typography.titleMedium, color = c.texto)
            if (cuando != null) Text(cuando, style = MaterialTheme.typography.bodyMedium, color = c.textoSecundario)
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun TarjetaPendiente(m: ModeloEstudios, p: PendienteEstudios, hoy: LocalDate?, alSubir: () -> Unit, alPedirFecha: () -> Unit, alAbrirOrden: (String) -> Unit) {
    val c = MyPump.colores
    val alcance = LocalAlcanceApp.current
    val cuando = Estudios.cuandoPendiente(p.desde, p.hasta, hoy)
    var deshaciendo by remember(p.id) { mutableStateOf(false) }
    var error by remember(p.id, p.hecho) { mutableStateOf(false) }
    Tarjeta(Modifier.testTag("estudios-pendiente-${p.id}"), relleno = Espacio.l, espaciado = Espacio.m) {
        Column(Modifier.semantics(mergeDescendants = true) { }, verticalArrangement = Arrangement.spacedBy(Espacio.xs)) {
            Text(p.titulo, style = MaterialTheme.typography.titleLarge.copy(fontWeight = FontWeight.Bold), color = c.texto, modifier = Modifier.semantics { heading() })
            p.detalle?.let { Text(it, style = MaterialTheme.typography.bodyMedium, color = c.textoSecundario) }
            if (p.hecho) {
                Renglon(Iconos.TildeEnCirculo, Estudios.hecho(p.hechoFecha), c.marcaTexto, Modifier.testTag("estudios-hecho"))
            } else if (cuando != null) {
                // Una fecha pasada va en ámbar con su reloj: avisa, no alarma.
                Renglon(if (cuando.pasada) Iconos.Reloj else Iconos.Calendario, cuando.texto, if (cuando.pasada) c.alerta else c.textoSecundario, fuerte = cuando.pasada)
            }
        }
        BotonSuave(T.subirResultado, alSubir, Modifier.fillMaxWidth().testTag("estudios-subir-resultado"))
        FlowRow(horizontalArrangement = Arrangement.spacedBy(Espacio.xs), verticalArrangement = Arrangement.spacedBy(Espacio.xs)) {
            if (p.hecho) {
                BotonSecundario(
                    T.deshacer,
                    alTocar = {
                        deshaciendo = true
                        error = false
                        alcance.launch {
                            try {
                                error = m.marcarHecho(p.id, null) != ModeloEstudios.Salida.OK
                            } finally {
                                deshaciendo = false
                            }
                        }
                    },
                    compacto = true, cargando = deshaciendo, modifier = Modifier.testTag("estudios-deshacer"),
                )
            } else {
                BotonSecundario(T.yaMeLoHice, alTocar = alPedirFecha, compacto = true, modifier = Modifier.testTag("estudios-ya-me-lo-hice"))
            }
            p.ordenId?.let { id -> BotonSecundario(T.verOrden, alTocar = { alAbrirOrden(id) }, compacto = true, modifier = Modifier.testTag("estudios-ver-orden-pendiente")) }
        }
        if (error) Renglon(Iconos.Alerta, T.noSePudoGuardar, c.alerta, vivo = true)
    }
}

/** El botón de una tarjeta: verde suave, para que el principal de la pantalla siga siendo uno solo. */
@Composable
private fun BotonSuave(texto: String, alTocar: () -> Unit, modifier: Modifier = Modifier) {
    val c = MyPump.colores
    Button(
        onClick = alTocar,
        modifier = modifier.defaultMinSize(minHeight = 50.dp),
        shape = CircleShape,
        colors = ButtonDefaults.buttonColors(containerColor = c.marcaSuave, contentColor = c.marcaTexto),
        elevation = null,
        contentPadding = PaddingValues(horizontal = 20.dp, vertical = 8.dp),
    ) {
        Text(texto, style = MaterialTheme.typography.titleMedium, textAlign = TextAlign.Center)
    }
}

@Composable
private fun FilaOrden(o: OrdenEstudios, alAbrir: () -> Unit) {
    val c = MyPump.colores
    val renglones = Estudios.renglonesOrden(o)
    Row(
        Modifier
            .fillMaxWidth()
            .heightIn(min = 64.dp)
            // Una orden vencida se lista, pero no se abre.
            .then(if (o.vigente) Modifier.clickable(role = Role.Button, onClickLabel = T.verOrden, onClick = alAbrir) else Modifier)
            .padding(horizontal = Espacio.m, vertical = Espacio.s)
            .semantics(mergeDescendants = true) { }
            .testTag("estudios-orden-${o.id}"),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(Espacio.s),
    ) {
        Box(Modifier.size(36.dp).background(if (o.vigente) c.marcaSuave else c.campo, CircleShape), contentAlignment = Alignment.Center) {
            Icon(Iconos.Documento, contentDescription = null, tint = if (o.vigente) c.marcaTexto else c.textoSecundario, modifier = Modifier.size(20.dp))
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(o.titulo, style = MaterialTheme.typography.titleMedium, color = if (o.vigente) c.texto else c.textoSecundario)
            if (o.vigente) {
                if (renglones.isNotEmpty()) Text(renglones.joinToString(" · "), style = MaterialTheme.typography.bodyMedium, color = c.textoSecundario)
            } else {
                for (r in renglones) Text(r, style = MaterialTheme.typography.bodyMedium, color = c.textoSecundario)
            }
        }
        if (o.vigente) Icon(Iconos.Chevron, contentDescription = null, tint = c.textoTerciario, modifier = Modifier.size(20.dp))
    }
}

/** El estado como etiqueta con ícono y texto: «Recibido» neutro, «Mati lo vio» verde con tilde. */
@Composable
private fun EtiquetaEstado(visto: Boolean) {
    val c = MyPump.colores
    val tono = if (visto) c.marcaTexto else c.textoSecundario
    Row(
        Modifier.clip(CircleShape).background(if (visto) c.marcaSuave else c.campo).padding(horizontal = 10.dp, vertical = 5.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(5.dp),
    ) {
        Icon(if (visto) Iconos.TildeEnCirculo else Iconos.NubeGuardada, contentDescription = null, tint = tono, modifier = Modifier.size(15.dp))
        Text(if (visto) T.matiLoVio else T.recibido, style = MaterialTheme.typography.labelMedium.copy(fontWeight = FontWeight.SemiBold), color = tono)
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun FilaEnvio(s: EnvioRecibido) {
    val c = MyPump.colores
    Column(
        Modifier
            .fillMaxWidth()
            .padding(horizontal = Espacio.m, vertical = Espacio.s)
            .clearAndSetSemantics { contentDescription = Estudios.envioCompleto(s) }
            .testTag("estudios-envio"),
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Text(Estudios.tituloEnvio(s), style = MaterialTheme.typography.titleMedium, color = c.texto)
        FlowRow(horizontalArrangement = Arrangement.spacedBy(Espacio.xs), verticalArrangement = Arrangement.spacedBy(6.dp), itemVerticalAlignment = Alignment.CenterVertically) {
            if (s.archivos > 0) Text(T.archivos(s.archivos), style = MaterialTheme.typography.bodyMedium, color = c.textoSecundario)
            EtiquetaEstado(visto = false)
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun FilaEstudio(s: EstudioRecibido, alVer: () -> Unit) {
    val c = MyPump.colores
    Row(
        Modifier
            .fillMaxWidth()
            // Solo se abre lo que el servidor deja abrir; si no, la fila no se toca.
            .then(if (s.sePuedeAbrir) Modifier.clickable(role = Role.Button, onClickLabel = T.ver, onClick = alVer) else Modifier)
            .padding(horizontal = Espacio.m, vertical = Espacio.s)
            .semantics(mergeDescendants = true) { }
            .testTag("estudios-estudio-${s.id ?: "sin-id"}"),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(Espacio.s),
    ) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(s.titulo, style = MaterialTheme.typography.titleMedium, color = c.texto)
            FlowRow(horizontalArrangement = Arrangement.spacedBy(Espacio.xs), verticalArrangement = Arrangement.spacedBy(6.dp), itemVerticalAlignment = Alignment.CenterVertically) {
                Text(Estudios.detalleEstudio(s), style = MaterialTheme.typography.bodyMedium, color = c.textoSecundario)
                EtiquetaEstado(s.visto)
            }
        }
        if (s.sePuedeAbrir) {
            Text(T.ver, style = MaterialTheme.typography.titleSmall.copy(fontWeight = FontWeight.SemiBold), color = c.marcaTexto)
            Icon(Iconos.Chevron, contentDescription = null, tint = c.textoTerciario, modifier = Modifier.size(20.dp))
        }
    }
}

// ── El detalle de una orden ──

@Composable
private fun DetalleOrden(o: OrdenEstudios, alVolver: () -> Unit, alVer: () -> Unit) {
    val c = MyPump.colores
    MarcoPantalla(o.titulo, alVolver = alVolver) { relleno ->
        Column(
            Modifier
                .padding(top = relleno.calculateTopPadding())
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = Espacio.m)
                .padding(top = Espacio.xs, bottom = Espacio.xl + LocalRellenoInferior.current)
                .testTag("estudios-detalle-orden"),
            verticalArrangement = Arrangement.spacedBy(Espacio.m),
        ) {
            val renglones = Estudios.renglonesOrden(o)
            if (renglones.isNotEmpty()) {
                Column(Modifier.padding(horizontal = Espacio.xxs).semantics(mergeDescendants = true) { }, verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    for (r in renglones) Text(r, style = MaterialTheme.typography.bodyLarge, color = c.textoSecundario)
                }
            }
            if (o.vigente) BotonMarca(T.verOrden, alTocar = alVer, modifier = Modifier.testTag("estudios-ver-orden"))
            Seccion(T.comoPrepararte) { Tarjeta(relleno = Espacio.l, espaciado = Espacio.s) { for (t in T.preparacion(o.tipo)) Punto(t) } }
            Seccion(T.dondeHacerlo) { Tarjeta(relleno = Espacio.l, espaciado = Espacio.s) { for (t in T.donde(o.tipo)) Punto(t) } }
        }
    }
}

@Composable
private fun Punto(texto: String) {
    val c = MyPump.colores
    Row(horizontalArrangement = Arrangement.spacedBy(Espacio.s)) {
        Box(Modifier.padding(top = 9.dp).size(6.dp).background(c.marcaVivo, CircleShape))
        Text(texto, style = MaterialTheme.typography.bodyLarge, color = c.texto, modifier = Modifier.weight(1f))
    }
}

// ── «¿Cuándo te lo hiciste?» ──

@OptIn(ExperimentalMaterial3Api::class, ExperimentalComposeUiApi::class)
@Composable
private fun HojaFecha(m: ModeloEstudios, pedidoId: String, hoy: LocalDate, alCerrar: () -> Unit) {
    val c = MyPump.colores
    val alcance = LocalAlcanceApp.current
    val alcanceHoja = rememberCoroutineScope()
    val hoja = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    var dia by rememberSaveable { mutableStateOf(hoy.toString()) }
    var error by rememberSaveable { mutableStateOf<String?>(null) }
    var guardando by remember { mutableStateOf(false) }
    val fecha = Estudios.dia(dia) ?: hoy

    fun cerrar() {
        alcanceHoja.launch { hoja.hide() }.invokeOnCompletion { alCerrar() }
    }

    fun mover(dias: Long) {
        val nueva = fecha.plusDays(dias)
        if (Estudios.fechaHechoValida(nueva, hoy)) {
            dia = nueva.toString()
            error = null
        }
    }

    ModalBottomSheet(
        onDismissRequest = alCerrar,
        sheetState = hoja,
        shape = FormaHoja,
        containerColor = c.fondo,
        tonalElevation = 0.dp,
        dragHandle = { AsaHoja() },
        modifier = Modifier.semantics { testTagsAsResourceId = true }.testTag("hoja-fecha-estudio"),
    ) {
        EncabezadoHoja(T.cuandoTeLoHiciste, cancelar = AccionHoja(T.cancelar, "estudios-cancelar-fecha", alTocar = ::cerrar))
        Column(
            Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).navigationBarsPadding().padding(horizontal = Espacio.m).padding(top = Espacio.s, bottom = Espacio.l),
            verticalArrangement = Arrangement.spacedBy(Espacio.l),
        ) {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espacio.s)) {
                BotonRedondo(Iconos.Menos, T.diaAnterior, Estudios.fechaHechoValida(fecha.minusDays(1), hoy), "estudios-fecha-menos") { mover(-1) }
                Text(
                    Estudios.diaLargo(fecha),
                    style = MaterialTheme.typography.headlineSmall.copy(fontWeight = FontWeight.Bold),
                    color = c.texto,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.weight(1f).semantics { liveRegion = LiveRegionMode.Polite }.testTag("estudios-fecha"),
                )
                BotonRedondo(Iconos.Mas, T.diaSiguiente, Estudios.fechaHechoValida(fecha.plusDays(1), hoy), "estudios-fecha-mas") { mover(1) }
            }
            error?.let { Renglon(Iconos.Alerta, it, c.alerta, Modifier.testTag("estudios-fecha-error"), vivo = true) }
            BotonMarca(
                T.guardar,
                alTocar = {
                    guardando = true
                    error = null
                    alcance.launch {
                        try {
                            when (m.marcarHecho(pedidoId, fecha)) {
                                ModeloEstudios.Salida.OK -> cerrar()
                                ModeloEstudios.Salida.FECHA -> error = T.revisaLaFecha
                                else -> error = T.noSePudoGuardar
                            }
                        } finally {
                            guardando = false
                        }
                    }
                },
                modifier = Modifier.testTag("estudios-guardar-fecha"),
                cargando = guardando,
            )
        }
    }
}

@Composable
private fun BotonRedondo(icono: ImageVector, descripcion: String, habilitado: Boolean, etiqueta: String, alTocar: () -> Unit) {
    val c = MyPump.colores
    Box(
        Modifier
            .size(56.dp)
            .clip(CircleShape)
            .background(c.campo)
            .clickable(enabled = habilitado, role = Role.Button, onClick = alTocar)
            .semantics { contentDescription = descripcion }
            .testTag(etiqueta),
        contentAlignment = Alignment.Center,
    ) {
        Icon(icono, contentDescription = null, tint = if (habilitado) c.texto else c.textoTerciario, modifier = Modifier.size(24.dp))
    }
}
