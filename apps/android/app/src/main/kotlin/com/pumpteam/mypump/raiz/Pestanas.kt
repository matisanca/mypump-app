package com.pumpteam.mypump.raiz

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.consumeWindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Badge
import androidx.compose.material3.BadgedBox
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationBarItemDefaults
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Snackbar
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveableStateHolder
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.pumpteam.mypump.ModeloAppViewModel
import com.pumpteam.mypump.datos.DestinoAviso
import com.pumpteam.mypump.datos.EstadoGuardado
import com.pumpteam.mypump.datos.ModeloApp
import com.pumpteam.mypump.dieta.DietaPantalla
import com.pumpteam.mypump.diseno.BotonSecundario
import com.pumpteam.mypump.diseno.Espacio
import com.pumpteam.mypump.diseno.Iconos
import com.pumpteam.mypump.diseno.MyPump
import com.pumpteam.mypump.diseno.PantallaConTitulo
import com.pumpteam.mypump.diseno.EstadoVacio
import com.pumpteam.mypump.diseno.Radio
import com.pumpteam.mypump.diseno.superficieTarjeta
import com.pumpteam.mypump.entreno.BarraDescansoEntreno
import com.pumpteam.mypump.entreno.DialogoPreguntas
import com.pumpteam.mypump.entreno.EntrenoPantalla
import com.pumpteam.mypump.entreno.RelojDescanso
import com.pumpteam.mypump.misdatos.MisDatosPantalla
import com.pumpteam.mypump.reglas.FotosProgreso
import com.pumpteam.mypump.revision.RevisionPantalla
import com.pumpteam.mypump.salud.DiagnosticoSaludDesdeLink
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * La app con una cuenta (o la demo): las 5 pestañas (GEN-01) con sus badges (GEN-03), Mis datos colgando de Revisión, la
 * barra de la demo o el banner de "sin conexión" arriba (OFF-06) y el aviso de guardado abajo (GEN-04).
 *
 * Cada pestaña guarda su estado al cambiar de pestaña (el desplazamiento, la opción elegida de cada comida), como el
 * `TabView` de iOS. Atrás vuelve de Mis datos a Revisión y de cualquier pestaña a Entreno, y desde Entreno sale.
 */
@Composable
fun AppConPestanas(vm: ModeloAppViewModel, modelo: ModeloApp) {
    val navegacion = rememberNavegacion()
    val esDemo by modelo.esDemo.collectAsStateWithLifecycle()
    val desdeCache by modelo.desdeCache.collectAsStateWithLifecycle()
    val estadoGuardado by modelo.estadoGuardado.collectAsStateWithLifecycle()
    val destino by vm.destino.collectAsStateWithLifecycle()
    val estadosPestanas = rememberSaveableStateHolder()
    val badges = badges(modelo, esDemo)
    val entreno by modelo.entreno.collectAsStateWithLifecycle()
    // El reloj del descanso corre arriba de las pestañas: termina (y suena) aunque se esté en otra.
    entreno?.let { RelojDescanso(it) }

    // `?scene=` de un link: a su pestaña, y el destino se consume.
    LaunchedEffect(destino) {
        destino?.let {
            navegacion.ir(it)
            vm.destinoConsumido()
        }
    }
    val enMisDatos = navegacion.pestana == Pestana.REVISION && navegacion.misDatos
    BackHandler(enabled = enMisDatos) { navegacion.misDatos = false }
    BackHandler(enabled = !enMisDatos && navegacion.pestana != Pestana.ENTRENO) { navegacion.pestana = Pestana.ENTRENO }

    CompositionLocalProvider(LocalNavegacion provides navegacion) {
        Scaffold(
            containerColor = MyPump.colores.fondo,
            contentWindowInsets = WindowInsets(0, 0, 0, 0),
            bottomBar = {
                Column {
                    // El descanso arriba de la barra de pestañas, a mano desde cualquier pestaña (SES-04).
                    entreno?.let { BarraDescansoEntreno(it) }
                    BarraPestanas(navegacion, badges)
                }
            },
        ) { relleno ->
            Box(Modifier.fillMaxSize().padding(relleno).consumeWindowInsets(relleno)) {
                Column(Modifier.fillMaxSize()) {
                    val conBanner = esDemo || desdeCache
                    if (esDemo) {
                        BarraDemo(alSalir = { vm.salirDeDemo() })
                    } else if (desdeCache) {
                        BannerSinConexion()
                    }
                    Box(Modifier.weight(1f).then(if (conBanner) Modifier.consumeWindowInsets(WindowInsets.statusBars) else Modifier)) {
                        estadosPestanas.SaveableStateProvider(navegacion.pestana.name) {
                            when (navegacion.pestana) {
                                Pestana.ENTRENO -> EntrenoPantalla(modelo, vm.preguntasEntreno)
                                Pestana.DIETA -> DietaPantalla(modelo)
                                Pestana.CHAT -> PantallaEnConstruccion(Pestana.CHAT, modelo)
                                Pestana.REVISION ->
                                    if (navegacion.misDatos) {
                                        MisDatosPantalla(vm, modelo, alVolver = { navegacion.misDatos = false })
                                    } else {
                                        RevisionPantalla(modelo, alAbrirMisDatos = { navegacion.misDatos = true })
                                    }
                                Pestana.PROGRESO -> PantallaEnConstruccion(Pestana.PROGRESO, modelo)
                            }
                        }
                    }
                }
                AvisoGuardado(estadoGuardado, Modifier.align(Alignment.BottomCenter).padding(bottom = Espacio.s))
                // Las preguntas de Entreno (reabrir el día, "¿Está bien cargado?", "¡Día completado!", avanzar de semana).
                DialogoPreguntas(vm.preguntasEntreno)
                // Salud: el diagnóstico que pidió un link con `?diag=health` (SAL-13), arriba de todo.
                DiagnosticoSaludDesdeLink(modelo)
            }
        }
    }
}

@Composable
private fun BarraPestanas(navegacion: Navegacion, badges: Map<Pestana, Int>) {
    val c = MyPump.colores
    NavigationBar(containerColor = c.tarjeta, tonalElevation = 0.dp) {
        for (p in Pestana.entries) {
            val n = badges[p] ?: 0
            NavigationBarItem(
                selected = navegacion.pestana == p,
                onClick = { navegacion.elegir(p) },
                icon = {
                    BadgedBox(
                        badge = {
                            if (n > 0) {
                                Badge(modifier = Modifier.semantics { contentDescription = "$n sin ver" }) { Text(if (n > 99) "99+" else "$n") }
                            }
                        },
                    ) { Icon(p.icono, contentDescription = null) }
                },
                label = { Text(p.titulo, maxLines = 1) },
                colors = NavigationBarItemDefaults.colors(
                    selectedIconColor = c.marcaTexto,
                    selectedTextColor = c.marcaTexto,
                    indicatorColor = MaterialTheme.colorScheme.secondaryContainer,
                    unselectedIconColor = c.textoSecundario,
                    unselectedTextColor = c.textoSecundario,
                ),
                modifier = Modifier.testTag(p.etiqueta),
            )
        }
    }
}

/**
 * Entreno: comentarios de Mati sin leer en los ejercicios. Chat: lo de Mati que llegó con el chat cerrado. Revisión: lo
 * que falta de la semana (check y fotos). Siempre los reales: en la demo, ninguno.
 */
@Composable
private fun badges(modelo: ModeloApp, esDemo: Boolean): Map<Pestana, Int> {
    val entreno by modelo.entreno.collectAsStateWithLifecycle()
    val chat by modelo.chat.collectAsStateWithLifecycle()
    val comentarios = entreno?.comentarios?.collectAsStateWithLifecycle()?.value
    val noLeidos = chat?.noLeidos?.collectAsStateWithLifecycle()?.value ?: 0
    val pendientes = pendientesDeLaSemana(modelo)
    if (esDemo) return emptyMap()
    return mapOf(
        Pestana.ENTRENO to (comentarios?.totalEntreno ?: 0),
        Pestana.CHAT to noLeidos,
        Pestana.REVISION to pendientes.total,
    )
}

/** Lo que falta de la semana (`pendientesDeLaSemana` del modelo), mirando el check y las fotos para recomponer. */
@Composable
fun pendientesDeLaSemana(modelo: ModeloApp): FotosProgreso.Pendientes {
    val revision by modelo.revision.collectAsStateWithLifecycle()
    val fotos by modelo.fotos.collectAsStateWithLifecycle()
    val checkin = revision?.checkin?.collectAsStateWithLifecycle()?.value
    val subidas = fotos?.fotos?.collectAsStateWithLifecycle()?.value
    val enCola = fotos?.pendientes?.collectAsStateWithLifecycle()?.value
    return remember(revision, fotos, checkin, subidas, enCola) { modelo.pendientesDeLaSemana }
}

/** En la demo: un aviso fijo arriba con la salida. */
@Composable
private fun BarraDemo(alSalir: () -> Unit) {
    val c = MyPump.colores
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(c.tarjeta)
            .windowInsetsPadding(WindowInsets.statusBars)
            .padding(horizontal = Espacio.m, vertical = Espacio.xs),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Icon(Iconos.Chispas, contentDescription = null, tint = c.marcaTexto, modifier = Modifier.size(20.dp))
        Text("Estás viendo la demo", style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f))
        BotonSecundario("Salir", alTocar = alSalir, compacto = true, modifier = Modifier.testTag("salir-demo"))
    }
}

/** Arriba de todo cuando lo que se ve es la copia guardada en el teléfono (OFF-06). */
@Composable
private fun BannerSinConexion() {
    val c = MyPump.colores
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(c.tarjeta)
            .windowInsetsPadding(WindowInsets.statusBars)
            .padding(vertical = Espacio.xs)
            .testTag("banner-sin-conexion"),
        horizontalArrangement = Arrangement.Center,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(Iconos.SinWifi, contentDescription = null, tint = c.alerta, modifier = Modifier.size(16.dp))
        Spacer(Modifier.width(6.dp))
        Text("Sin conexión: estás viendo tu plan guardado", style = MaterialTheme.typography.labelMedium, color = c.alerta)
    }
}

/**
 * "Te faltan tu check y tus fotos de la semana · entrá a Revisión" (GEN-03), arriba de Entreno, Dieta, Chat y Progreso.
 * Tocarlo lleva a Revisión. Con todo hecho o en la demo no se ve.
 */
@Composable
fun BannerRevision(modelo: ModeloApp, modifier: Modifier = Modifier) {
    val navegacion = LocalNavegacion.current
    val esDemo by modelo.esDemo.collectAsStateWithLifecycle()
    val p = pendientesDeLaSemana(modelo)
    val texto = FotosProgreso.textoRecordatorio(p.faltaCheck, p.faltanFotos)
    if (esDemo || texto == null) return
    val c = MyPump.colores
    Row(
        modifier = modifier
            .fillMaxWidth()
            .superficieTarjeta(radio = Radio.control + 6.dp)
            .clickable { navegacion?.ir(DestinoAviso.REVISION) }
            .padding(Espacio.s)
            .testTag("banner-revision"),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(Espacio.s),
    ) {
        Box(Modifier.size(32.dp).clip(CircleShape).background(c.marca), contentAlignment = Alignment.Center) {
            Icon(Iconos.Checklist, contentDescription = null, tint = c.sobreMarca, modifier = Modifier.size(18.dp))
        }
        Column(Modifier.weight(1f)) {
            Text(texto, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold)
            Text(
                "Entrá a Revisión: es un minuto y Mati lo ve antes de tu devolución.",
                style = MaterialTheme.typography.bodySmall,
                color = c.textoSecundario,
            )
        }
        Icon(Iconos.Chevron, contentDescription = null, tint = c.textoTerciario, modifier = Modifier.size(20.dp))
    }
}

/**
 * El aviso de guardado de la web (GEN-04, `showSaveState`), como un snackbar sobre la barra de pestañas: "Guardando…" solo
 * si el envío tarda más de 900 ms (lo decide la cola); "Guardado" solo después de un problema; "Sin conexión, se reintenta
 * solo" un rato; y "Algo no se pudo guardar" 9 segundos o hasta tocarlo.
 */
@Composable
private fun AvisoGuardado(estado: EstadoGuardado, modifier: Modifier = Modifier) {
    var visible by remember { mutableStateOf<EstadoGuardado?>(null) }
    var ocultar by remember { mutableStateOf<Job?>(null) }
    val alcance = rememberCoroutineScope()
    fun ocultarEn(ms: Long) {
        ocultar = alcance.launch {
            delay(ms)
            visible = null
        }
    }
    LaunchedEffect(estado) {
        // "Algo no se pudo guardar" se queda sus 9 segundos aunque la cola vuelva a quedar quieta.
        if (estado == EstadoGuardado.QUIETO && visible == EstadoGuardado.PERDIDO) return@LaunchedEffect
        ocultar?.cancel()
        when (estado) {
            // "Guardado" se deja ver un momento antes de irse.
            EstadoGuardado.QUIETO -> if (visible == EstadoGuardado.GUARDADO) ocultarEn(1_600) else visible = null
            EstadoGuardado.GUARDANDO -> visible = estado
            EstadoGuardado.SIN_CONEXION -> {
                visible = estado
                ocultarEn(3_200)
            }
            EstadoGuardado.GUARDADO -> {
                visible = estado
                ocultarEn(1_600)
            }
            EstadoGuardado.PERDIDO -> {
                visible = estado
                ocultarEn(9_000)
            }
        }
    }
    val oscuro = MyPump.colores.oscuro
    AnimatedVisibility(
        visible = visible != null,
        modifier = modifier,
        enter = slideInVertically { it } + fadeIn(),
        exit = slideOutVertically { it } + fadeOut(),
    ) {
        val v = visible ?: EstadoGuardado.QUIETO
        // Sobre el fondo invertido del snackbar los colores son los del tema contrario.
        val (texto, icono, tono) = when (v) {
            EstadoGuardado.GUARDANDO -> Triple("Guardando…", Iconos.Pegar, Color.Unspecified)
            EstadoGuardado.GUARDADO -> Triple("Guardado", Iconos.Verificado, if (oscuro) Color(0xFF16A34A) else Color(0xFF30D158))
            EstadoGuardado.SIN_CONEXION -> Triple("Sin conexión, se reintenta solo", Iconos.SinWifi, if (oscuro) Color(0xFFC2410C) else Color(0xFFFF9F0A))
            EstadoGuardado.PERDIDO -> Triple("Algo no se pudo guardar. Revisalo y cargalo de nuevo", Iconos.Alerta, if (oscuro) Color(0xFFDC2626) else Color(0xFFFF453A))
            EstadoGuardado.QUIETO -> Triple("", Iconos.Pegar, Color.Unspecified)
        }
        Snackbar(
            modifier = Modifier
                .padding(horizontal = Espacio.m)
                .clickable { visible = null }
                .semantics { liveRegion = LiveRegionMode.Polite }
                .testTag("aviso-guardado"),
            shape = RoundedCornerShape(Radio.control),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                if (v != EstadoGuardado.GUARDANDO) Icon(icono, contentDescription = null, tint = tono, modifier = Modifier.size(20.dp))
                Text(texto, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold)
            }
        }
    }
}

/** Una pestaña que en Android todavía no tiene pantalla: su título y el banner de Revisión, nada inventado. */
@Composable
private fun PantallaEnConstruccion(pestana: Pestana, modelo: ModeloApp) {
    PantallaConTitulo(pestana.titulo) {
        BannerRevision(modelo, Modifier.padding(horizontal = Espacio.m))
        EstadoVacio(
            icono = pestana.icono,
            titulo = pestana.titulo,
            texto = "Esta pantalla todavía no está lista en la app nueva de Android.",
            modifier = Modifier.testTag("en-construccion-${pestana.name.lowercase()}"),
        )
    }
}

/** Un ícono con el texto al lado, para filas sencillas. */
@Composable
fun IconoYTexto(icono: ImageVector, texto: String, tono: Color, modifier: Modifier = Modifier) {
    Row(modifier, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        Icon(icono, contentDescription = null, tint = tono, modifier = Modifier.size(18.dp))
        Text(texto, style = MaterialTheme.typography.bodyMedium, color = tono)
    }
}
