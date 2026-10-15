package com.pumpteam.mypump.avisos

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.addPathNodes
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LifecycleResumeEffect
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.pumpteam.mypump.ModeloAppViewModel
import com.pumpteam.mypump.acceso.Onboarding
import com.pumpteam.mypump.acceso.OnboardingPermisos
import com.pumpteam.mypump.datos.ModeloApp
import com.pumpteam.mypump.datos.ModeloEntreno
import com.pumpteam.mypump.diseno.Espacio
import com.pumpteam.mypump.diseno.IconoAzulejo
import com.pumpteam.mypump.diseno.MyPump
import com.pumpteam.mypump.diseno.PieSeccion
import com.pumpteam.mypump.diseno.RotuloSeccion
import com.pumpteam.mypump.diseno.superficieTarjeta
import com.pumpteam.mypump.raiz.LocalAlcanceApp
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * Los avisos con la app abierta (lo que en iOS hace `RaizApp`). Va en la raíz, con el modelo:
 *
 * - con una cuenta (fuera de la demo), al entrar y cada vez que la app vuelve a primer plano: lo de la Capacitor afuera, el
 *   aviso del domingo que viene armado (es de una vez) y el token de push registrado, si hay permiso; sin cuenta, con el
 *   link vencido o en la demo, nada agendado;
 * - la hoja de permisos de la primera vez (GEN-06), 1,2 s después de pintar las pestañas [enLaApp];
 * - el fin del descanso con la app en segundo plano (D8).
 */
@Composable
fun AvisosDeLaApp(vm: ModeloAppViewModel, m: ModeloApp, enLaApp: Boolean) {
    val contexto = LocalContext.current.applicationContext
    val alcance = LocalAlcanceApp.current
    val fase by m.fase.collectAsStateWithLifecycle()
    val esDemo by m.esDemo.collectAsStateWithLifecycle()
    val entreno by m.entreno.collectAsStateWithLifecycle()
    val conCuenta = fase == ModeloApp.Fase.LISTO && !esDemo && m.token != null

    // Un token nuevo de FCM se registra con este modelo mientras la app viva (así respeta la demo).
    DisposableEffect(m) {
        CentroAvisos.modeloVivo = m
        onDispose { if (CentroAvisos.modeloVivo === m) CentroAvisos.modeloVivo = null }
    }

    LaunchedEffect(fase, esDemo) {
        when {
            conCuenta -> alcance.launch { CentroAvisos.alEntrar(contexto, m, vm.version) }
            // Sin cuenta (salió), con el link vencido o en la demo: el domingo se cancela (hallazgo 8 del 15-oct).
            fase == ModeloApp.Fase.SIN_TOKEN || fase == ModeloApp.Fase.TOKEN_INVALIDO || esDemo -> CentroAvisos.alQuedarSinCuenta(contexto)
            else -> {}   // cargando o sin servicio: queda lo que estaba
        }
    }

    // Cada vez que vuelve a primer plano con la cuenta: el aviso del domingo es de una vez y se vuelve a armar (Android deja
    // la app viva días sin un arranque nuevo; hallazgo 8 del 15-oct). De paso, si volvió de Ajustes con las notificaciones
    // prendidas queda el push (si no, un comentario de Mati no llegaba hasta el próximo arranque), y si las apagó, nada
    // agendado. La primera vez ya lo hace lo de arriba.
    val conCuentaActual by rememberUpdatedState(conCuenta)
    val vueltas = remember { intArrayOf(0) }
    LifecycleResumeEffect(Unit) {
        if (vueltas[0]++ > 0 && conCuentaActual) alcance.launch { CentroAvisos.alEntrar(contexto, m, vm.version) }
        onPauseOrDispose {}
    }

    // GEN-06: la primera vez con una cuenta, 1,2 s después de pintar. Nunca en la demo.
    var onboarding by rememberSaveable { mutableStateOf(false) }
    val pedirOnboarding = enLaApp && conCuenta
    LaunchedEffect(pedirOnboarding) {
        if (!pedirOnboarding || !Onboarding.pendiente(m.preferencias)) return@LaunchedEffect
        delay(1_200)
        if (m.fase.value == ModeloApp.Fase.LISTO && !m.esDemo.value && m.token != null) onboarding = true
    }
    if (onboarding) OnboardingPermisos(m, vm.version, alTerminar = { onboarding = false })

    FinDelDescanso(entreno)
}

/**
 * D8: con la app en segundo plano y un descanso corriendo, el aviso de que terminó (la web no lo tenía: el cliente se
 * quedaba mirando el teléfono). Al pasar a segundo plano se agenda la alarma; al volver se cancela y se saca el aviso.
 *
 * Mientras el proceso corre, el reloj del descanso (`RelojDescanso`) sigue andando: el aviso sale en el segundo en que
 * termina, sin esperar a la alarma inexacta, y el pitido de la app no suena encima. Desde Android 14 el sistema congela a
 * los pocos segundos una app que quedó atrás: ahí avisa la alarma, que la despierta (y el reloj, que retoma, no lo repite).
 * Si el descanso desaparece antes de terminar (se salteó, se cerró el día), se cancela.
 */
@Composable
private fun FinDelDescanso(motor: ModeloEntreno?) {
    val contexto = LocalContext.current.applicationContext
    val ciclo = LocalLifecycleOwner.current.lifecycle
    val motorActual by rememberUpdatedState(motor)
    DisposableEffect(ciclo) {
        val observador = LifecycleEventObserver { _, evento ->
            when (evento) {
                Lifecycle.Event.ON_START -> {
                    CentroAvisos.enPrimerPlano = true
                    CentroAvisos.cancelarFinDescanso(contexto)
                }
                Lifecycle.Event.ON_STOP -> {
                    CentroAvisos.enPrimerPlano = false
                    val d = motorActual?.descanso?.value?.descanso
                    if (d != null && !d.terminado) CentroAvisos.programarFinDescanso(contexto, d.fin.toLong())
                }
                else -> {}
            }
        }
        ciclo.addObserver(observador)
        onDispose { ciclo.removeObserver(observador) }
    }
    LaunchedEffect(motor) {
        val m = motor ?: return@LaunchedEffect
        var avisado: Double? = null
        var finVisto: Double? = null
        m.descanso.collect { barra ->
            if (ciclo.currentState.isAtLeast(Lifecycle.State.STARTED)) {
                avisado = null
                finVisto = barra.descanso?.fin
                return@collect
            }
            val d = barra.descanso
            when {
                d != null && d.terminado && avisado != d.fin -> {
                    avisado = d.fin
                    CentroAvisos.mostrarFinDescanso(contexto)
                }
                d == null && finVisto != null && avisado == null && System.currentTimeMillis() < (finVisto ?: 0.0) -> {
                    CentroAvisos.cancelarFinDescanso(contexto)
                    finVisto = null
                }
                d != null -> finVisto = d.fin
            }
        }
    }
}

/**
 * La sección de Mis datos (gemela de la de iOS): solo si falta el permiso y no es la demo, "Activar notificaciones" o, si se
 * negó para siempre, "Activar en Ajustes". Sin interruptores de recordatorios: el aviso del domingo no se configura (D15).
 * Al volver de Ajustes se vuelve a mirar el permiso.
 */
@Composable
fun SeccionNotificaciones(vm: ModeloAppViewModel, modelo: ModeloApp) {
    val contexto = LocalContext.current
    val alcance = LocalAlcanceApp.current
    val esDemo by modelo.esDemo.collectAsStateWithLifecycle()
    var permiso by remember { mutableStateOf<PermisoAvisos?>(null) }
    LifecycleResumeEffect(Unit) {
        permiso = CentroAvisos.permiso(contexto)
        onPauseOrDispose {}
    }
    val pedir = rememberPedidoAvisos { ok ->
        // Con el sí, el aviso del domingo y el push quedan listos ya (como `activar` de iOS).
        if (ok) CentroAvisos.alActivar(contexto.applicationContext, modelo, vm.version, alcance)
        permiso = CentroAvisos.permiso(contexto)
    }
    val p = permiso
    if (p == null || p == PermisoAvisos.CONCEDIDO || esDemo) return
    val c = MyPump.colores
    val negado = p == PermisoAvisos.NEGADO
    Column(Modifier.padding(horizontal = Espacio.m).testTag("seccion-notificaciones")) {
        RotuloSeccion("Notificaciones", Modifier.padding(start = 0.dp))
        Column(Modifier.fillMaxWidth().superficieTarjeta()) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .heightIn(min = 56.dp)
                    .clickable(role = Role.Button) { if (negado) CentroAvisos.abrirAjustes(contexto) else pedir() }
                    .padding(horizontal = Espacio.m, vertical = Espacio.xs)
                    .testTag("activar-notificaciones"),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(Espacio.s),
            ) {
                IconoAzulejo(IconosAvisos.Campana, c.peligro)
                Text(if (negado) "Activar en Ajustes" else "Activar notificaciones", style = MaterialTheme.typography.bodyLarge, modifier = Modifier.weight(1f))
            }
        }
        PieSeccion(
            if (negado) {
                "Las notificaciones de MyPump están apagadas en el teléfono: los mensajes de Mati no te van a llegar hasta que las prendas."
            } else {
                "Para que te lleguen los mensajes de Mati."
            },
        )
    }
}

/**
 * Pedir el permiso desde una pantalla: devuelve la acción, que abre la hoja del sistema y contesta en [alResultado]. La
 * respuesta llega aunque la pantalla se haya recreado (al rotar) mientras la hoja estaba abierta.
 */
@Composable
fun rememberPedidoAvisos(alResultado: (Boolean) -> Unit): () -> Unit {
    val contexto = LocalContext.current
    val actual by rememberUpdatedState(alResultado)
    val lanzador = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { ok -> actual(ok) }
    return remember(lanzador, contexto) { { CentroAvisos.pedir(contexto, lanzador) { ok -> actual(ok) } } }
}

/** Los íconos de los avisos, con los trazados de Material Icons (Apache 2.0) como `Iconos`. */
object IconosAvisos {
    private fun icono(nombre: String, trazado: String): ImageVector =
        ImageVector.Builder(name = nombre, defaultWidth = 24.dp, defaultHeight = 24.dp, viewportWidth = 24f, viewportHeight = 24f)
            .apply { addPath(pathData = addPathNodes(trazado), fill = SolidColor(Color.Black)) }
            .build()

    /** notifications_active: la `bell.badge.fill` de iOS. */
    val Campana: ImageVector by lazy {
        icono(
            "Campana",
            "M7.58,4.08L6.15,2.65C3.75,4.48 2.17,7.3 2.03,10.5h2c0.15,-2.65 1.51,-4.97 3.55,-6.42zM19.97,10.5h2c-0.15,-3.2 -1.73,-6.02 -4.12,-7.85l-1.42,1.43c2.02,1.45 3.39,3.77 3.54,6.42zM18,11c0,-3.07 -1.64,-5.64 -4.5,-6.32V4c0,-0.83 -0.67,-1.5 -1.5,-1.5s-1.5,0.67 -1.5,1.5v0.68C7.63,5.36 6,7.92 6,11v5l-2,2v1h16v-1l-2,-2v-5zM12,22c0.14,0 0.27,-0.01 0.4,-0.04 0.65,-0.14 1.18,-0.58 1.44,-1.18 0.1,-0.24 0.15,-0.5 0.15,-0.78h-4c0.01,1.1 0.9,2 2.01,2z",
        )
    }

    /** favorite: el `heart.fill` de iOS. */
    val Corazon: ImageVector by lazy {
        icono(
            "Corazon",
            "M12,21.35l-1.45,-1.32C5.4,15.36 2,12.28 2,8.5 2,5.42 4.42,3 7.5,3c1.74,0 3.41,0.81 4.5,2.09C13.09,3.81 14.76,3 16.5,3 19.58,3 22,5.42 22,8.5c0,3.78 -3.4,6.86 -8.55,11.54L12,21.35z",
        )
    }
}
