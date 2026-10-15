package com.pumpteam.mypump.raiz

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.ConnectivityManager
import android.net.Network
import android.net.Uri
import android.os.Handler
import android.os.Looper
import androidx.compose.animation.Crossfade
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTagsAsResourceId
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import com.pumpteam.mypump.ModeloAppViewModel
import com.pumpteam.mypump.acceso.AccesoPantalla
import com.pumpteam.mypump.avisos.AvisosDeLaApp
import com.pumpteam.mypump.datos.ErrorRpc
import com.pumpteam.mypump.datos.ModeloApp
import com.pumpteam.mypump.datos.PalancaRemota
import com.pumpteam.mypump.diseno.BotonMarca
import com.pumpteam.mypump.diseno.EstadoVacio
import com.pumpteam.mypump.diseno.Iconos
import com.pumpteam.mypump.diseno.MarcaMyPump
import com.pumpteam.mypump.diseno.MyPump
import com.pumpteam.mypump.diseno.fondoMarca
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch

/**
 * Qué ve el cliente según el estado de su cuenta (RaizApp.swift): la marca mientras corre la migración del almacenamiento
 * viejo o se trae la cuenta por primera vez, la bienvenida (sin link o link vencido), sin conexión sin copia guardada, o
 * la app. Los links `app.mypumpteam.com/?t=` entran desde cualquier estado (los recibe la Activity).
 */
@OptIn(ExperimentalComposeUiApi::class)
@Composable
fun RaizMyPump(vm: ModeloAppViewModel) {
    val modelo by vm.modelo.collectAsStateWithLifecycle()
    // Las etiquetas de las pruebas (`ver-demo`, `pestana-dieta`…) también como resource-id: las ven UI Automator y las
    // herramientas de accesibilidad, como los `accessibilityIdentifier` de iOS.
    Box(Modifier.fillMaxSize().semantics { testTagsAsResourceId = true }) {
        val m = modelo
        CompositionLocalProvider(LocalAlcanceApp provides vm.viewModelScope) {
            if (m == null) PantallaArranque() else RaizConModelo(vm, m)
        }
    }
}

/**
 * El alcance para lo que una pantalla le pide al modelo (entrar, recargar, decidir): el del ViewModel. El de la pantalla
 * (`rememberCoroutineScope`) no sirve: la bienvenida sale de la composición apenas la cuenta empieza a cargar, y eso
 * cancelaba la carga a la mitad (el `Task {}` de iOS no depende de la vista).
 */
val LocalAlcanceApp = staticCompositionLocalOf<CoroutineScope> { error("sin el alcance de la app") }

private enum class Destino { ARRANQUE, ACCESO, SIN_CONEXION, ACTUALIZAR, APP }

/**
 * Lo que se ve y de quién: la app de la demo y la de una cuenta son escenas distintas. Si no, salir de la demo y entrar
 * con el link enseguida (durante el fundido) reusaba la composición de la demo, con su pestaña y su estado.
 */
private data class Escena(val destino: Destino, val de: String?)

@Composable
private fun RaizConModelo(vm: ModeloAppViewModel, m: ModeloApp) {
    val fase by m.fase.collectAsStateWithLifecycle()
    val palanca by m.palanca.collectAsStateWithLifecycle()
    val esDemo by m.esDemo.collectAsStateWithLifecycle()
    val alcance = LocalAlcanceApp.current
    // Volvió la red: sale lo pendiente y, si se veía la copia guardada, se trae todo.
    MonitorDeRed { alcance.launch { m.alVolverLaRed() } }
    val destino = when (fase) {
        ModeloApp.Fase.LISTO ->
            // La palanca remota pide una versión más nueva: una con un problema grave deja de mostrarse hasta actualizar.
            if (PalancaRemota.debajo(vm.versionCorta, palanca.versionMinimaAndroid)) Destino.ACTUALIZAR else Destino.APP
        ModeloApp.Fase.CARGANDO -> Destino.ARRANQUE
        ModeloApp.Fase.SIN_SERVICIO -> Destino.SIN_CONEXION
        ModeloApp.Fase.SIN_TOKEN, ModeloApp.Fase.TOKEN_INVALIDO -> Destino.ACCESO
    }
    val escena = Escena(destino, if (destino != Destino.APP) null else if (esDemo) "demo" else m.token)
    // Avisos: el del domingo y el push con una cuenta, la hoja de permisos de la primera vez y el fin del descanso.
    AvisosDeLaApp(vm, m, enLaApp = destino == Destino.APP)
    Crossfade(targetState = escena, label = "raiz") { e ->
        when (e.destino) {
            Destino.ARRANQUE -> PantallaArranque()
            Destino.ACCESO -> AccesoPantalla(m, alVerDemo = vm::entrarEnDemo)
            Destino.SIN_CONEXION -> SinConexion(m)
            Destino.ACTUALIZAR -> ActualizarApp()
            Destino.APP -> AppConPestanas(vm, m)
        }
    }
    // Un link tocado con la cuenta andando que no se usó: se avisa y se sigue en la cuenta (hallazgo 11 del 15-oct).
    val avisoLink by m.avisoLink.collectAsStateWithLifecycle()
    avisoLink?.let { AvisoDeLink(it, alCerrar = m::cerrarAvisoLink) }
}

/** Los textos de iOS (las alertas de RaizApp.swift). Cerrarlo como sea lo borra. */
@Composable
private fun AvisoDeLink(aviso: ModeloApp.AvisoLink, alCerrar: () -> Unit) {
    val c = MyPump.colores
    val (titulo, texto) = when (aviso) {
        ModeloApp.AvisoLink.VENCIDO -> "Este link ya no sirve" to "Seguís con tu cuenta."
        ModeloApp.AvisoLink.SIN_CONEXION -> "Sin conexión" to "No pudimos abrir ese link. Probá de nuevo cuando tengas señal."
    }
    AlertDialog(
        onDismissRequest = alCerrar,
        title = { Text(titulo) },
        text = { Text(texto, style = MaterialTheme.typography.bodyMedium) },
        confirmButton = {
            TextButton(onClick = alCerrar, modifier = Modifier.testTag("aviso-link-entendido")) {
                Text("Entendido", color = c.marcaTexto, fontWeight = FontWeight.SemiBold)
            }
        },
        containerColor = c.tarjeta,
        modifier = Modifier.testTag("aviso-link"),
    )
}

/** La marca mientras se trae la cuenta por primera vez (con copia offline la app abre directo) o corre la Fase L. */
@Composable
fun PantallaArranque() {
    Column(
        modifier = Modifier.fillMaxSize().fondoMarca().systemBarsPadding().testTag("arranque"),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        MarcaMyPump()
        Spacer(Modifier.height(24.dp))
        CircularProgressIndicator(Modifier.size(36.dp), color = MyPump.colores.marcaTexto)
    }
}

/**
 * Sin copia guardada y sin poder traer el plan (ACC-05): "Sin conexión" o "Servicio fuera de línea" según lo que pasó,
 * reintentar a mano y una sola recarga automática cuando vuelve la red.
 */
@Composable
fun SinConexion(m: ModeloApp) {
    val falla by m.ultimaFalla.collectAsStateWithLifecycle()
    val servidorCaido = falla != null && falla != ErrorRpc.Clase.RED
    var reintentando by remember { mutableStateOf(false) }
    var yaReintentoSolo by rememberSaveable { mutableStateOf(false) }
    val alcance = LocalAlcanceApp.current
    fun reintentar() {
        if (reintentando) return
        reintentando = true
        alcance.launch {
            try {
                m.cargar()
            } finally {
                reintentando = false
            }
        }
    }
    MonitorDeRed {
        if (!yaReintentoSolo) {
            yaReintentoSolo = true
            reintentar()
        }
    }
    Box(Modifier.fillMaxSize().fondoMarca().systemBarsPadding().testTag("sin-conexion")) {
        EstadoVacio(
            icono = if (servidorCaido) Iconos.SinNube else Iconos.SinWifi,
            titulo = if (servidorCaido) "Servicio fuera de línea" else "Sin conexión",
            texto = if (servidorCaido) {
                "No pudimos traer tu plan. Estamos con un problema del servicio: probá de nuevo en unos minutos."
            } else {
                "No pudimos traer tu plan. Cuando vuelva la señal lo intentamos solos."
            },
            accion = {
                BotonMarca("Reintentar", alTocar = ::reintentar, compacto = true, cargando = reintentando, modifier = Modifier.testTag("reintentar"))
            },
        )
    }
}

/** La palanca remota pide una versión más nueva (`version_minima_android`). La cola sigue subiendo sola lo ya cargado. */
@Composable
private fun ActualizarApp() {
    val contexto = LocalContext.current
    Box(Modifier.fillMaxSize().fondoMarca().systemBarsPadding().padding(horizontal = 8.dp)) {
        EstadoVacio(
            icono = Iconos.Actualizar,
            titulo = "Actualizá MyPump",
            texto = "Hay una versión nueva que necesitás para seguir. Lo que ya cargaste está guardado.",
            accion = { BotonMarca("Abrir Google Play", alTocar = { abrirPlay(contexto) }, compacto = true) },
        )
    }
}

private fun abrirPlay(contexto: Context) {
    val paquete = contexto.packageName
    val intentos = listOf("market://details?id=$paquete", "https://play.google.com/store/apps/details?id=$paquete")
    for (url in intentos) {
        try {
            contexto.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            return
        } catch (_: ActivityNotFoundException) {
        }
    }
}

/**
 * Avisa cuando la red VUELVE (pasa de no disponible a disponible), no en el primer aviso del sistema: así un reintento
 * automático no se gasta apenas aparece la pantalla. Es la red por defecto del teléfono (wifi o datos).
 */
@Composable
fun MonitorDeRed(alVolver: () -> Unit) {
    val contexto = LocalContext.current
    val actual by rememberUpdatedState(alVolver)
    DisposableEffect(contexto) {
        val cm = contexto.getSystemService(ConnectivityManager::class.java)
        var hayRed = cm?.activeNetwork != null
        val oyente = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                if (!hayRed) {
                    hayRed = true
                    actual()
                }
            }

            override fun onLost(network: Network) {
                hayRed = false
            }
        }
        val registrado = try {
            cm?.registerDefaultNetworkCallback(oyente, Handler(Looper.getMainLooper()))
            cm != null
        } catch (_: RuntimeException) {
            // Un teléfono con demasiados oyentes registrados tira: sin monitor queda el "Reintentar" a mano.
            false
        }
        onDispose {
            if (registrado) {
                try {
                    cm?.unregisterNetworkCallback(oyente)
                } catch (_: RuntimeException) {
                }
            }
        }
    }
}
