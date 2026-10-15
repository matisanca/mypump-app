package com.pumpteam.mypump.entreno

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.pumpteam.mypump.datos.ModeloApp
import com.pumpteam.mypump.datos.ModeloEntreno
import com.pumpteam.mypump.diseno.BotonSecundario
import com.pumpteam.mypump.diseno.EstadoVacio
import com.pumpteam.mypump.diseno.Iconos
import com.pumpteam.mypump.diseno.MarcoPantalla
import com.pumpteam.mypump.diseno.MyPump
import com.pumpteam.mypump.modelos.EstructuraRutina
import com.pumpteam.mypump.modelos.RutinaActiva
import com.pumpteam.mypump.raiz.LocalAlcanceApp
import com.pumpteam.mypump.reglas.CatalogoEjercicios
import com.pumpteam.mypump.reglas.DiaEnCurso
import com.pumpteam.mypump.reglas.IndiceComentarios
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * Entreno (EntrenoView.swift): el día elegido con su progreso, el cronómetro de la sesión, los bloques y cada ejercicio,
 * avanzar de semana y cerrar el día. Todo sale del motor (`ModeloEntreno`, que arma `ModeloApp`). Tocar un ejercicio
 * abre su pantalla dentro de la pestaña (la barra de pestañas sigue a la vista, como el `NavigationStack` de iOS) y Atrás
 * vuelve a la lista.
 *
 * Sin rutina usable, "Todavía no hay rutina" (D11+: la de ejemplo es solo de la demo); si un corte dejó afuera la rutina y
 * no había copia guardada, lo dice.
 */
@Composable
fun EntrenoPantalla(modelo: ModeloApp, preguntador: Preguntador) {
    val fase by modelo.fase.collectAsStateWithLifecycle()
    val motor by modelo.entreno.collectAsStateWithLifecycle()
    val sinRedEn by modelo.sinRedEn.collectAsStateWithLifecycle()
    val esDemo by modelo.esDemo.collectAsStateWithLifecycle()
    val alcance = LocalAlcanceApp.current
    // El ejercicio abierto (el lugar en la rutina). Sobrevive a cambiar de pestaña y a rotar.
    var abierto by rememberSaveable { mutableStateOf<String?>(null) }
    // La lista conserva dónde estaba al volver de un ejercicio.
    val desplazamiento = rememberScrollState()
    val m = motor
    val usable = m?.usable?.collectAsStateWithLifecycle()?.value ?: false

    BackHandler(enabled = abierto != null && m != null && usable) { abierto = null }

    when {
        m != null && usable -> {
            val v = vistaDe(m)
            // "🎉 ¡Día completado!" medio segundo después (como la web); con un día siguiente, ofrece ir.
            val alCompletarDia: (ModeloEntreno.DiaCompletado) -> Unit = { c ->
                alcance.launch {
                    delay(500)
                    val ir = preguntador.preguntar(c.pregunta)
                    val sig = c.siguiente?.id
                    if (ir && sig != null) {
                        abierto = null
                        m.cambiarDia(sig)
                    }
                }
            }
            AnimatedContent(
                targetState = abierto,
                transitionSpec = {
                    if (targetState != null) {
                        (slideInHorizontally { it } + fadeIn()) togetherWith (slideOutHorizontally { -it / 4 } + fadeOut())
                    } else {
                        (slideInHorizontally { -it / 4 } + fadeIn()) togetherWith (slideOutHorizontally { it } + fadeOut())
                    }
                },
                label = "entreno",
            ) { lugar ->
                if (lugar == null) {
                    ListaEntreno(
                        motor = m,
                        v = v,
                        deEjemplo = m.demo && !esDemo,
                        modelo = modelo,
                        preguntador = preguntador,
                        desplazamiento = desplazamiento,
                        alAbrir = { abierto = it },
                    )
                } else {
                    EjercicioPantalla(
                        motor = m,
                        v = v,
                        lugar = lugar,
                        preguntador = preguntador,
                        alVolver = { abierto = null },
                        alAbrir = { abierto = it },
                        alCompletarDia = alCompletarDia,
                    )
                }
            }
        }
        fase == ModeloApp.Fase.LISTO && ModeloApp.Parte.RUTINA in sinRedEn ->
            // Un corte dejó afuera la rutina y no había copia guardada.
            MarcoPantalla("Entreno") { relleno ->
                var reintentando by remember { mutableStateOf(false) }
                EstadoVacio(
                    icono = Iconos.SinWifi,
                    titulo = "No pudimos traer tu rutina",
                    texto = "Se cortó la conexión. Probá de nuevo cuando tengas señal.",
                    modifier = Modifier.padding(relleno).testTag("entreno-sin-red"),
                    accion = {
                        BotonSecundario(
                            "Reintentar",
                            alTocar = {
                                reintentando = true
                                alcance.launch {
                                    try {
                                        modelo.cargar()
                                    } finally {
                                        reintentando = false
                                    }
                                }
                            },
                            compacto = true,
                            tono = MyPump.colores.marcaTexto,
                            cargando = reintentando,
                        )
                    },
                )
            }
        fase == ModeloApp.Fase.LISTO -> SinRutina(modelo)
        else -> MarcoPantalla("Entreno") { relleno ->
            Box(Modifier.padding(relleno).fillMaxSize(), contentAlignment = Alignment.Center) {
                CircularProgressIndicator(color = MyPump.colores.marcaTexto)
            }
        }
    }
}

/** D11+: sin rutina publicada (o con una sin un solo ejercicio) no se muestra la de ejemplo como si fuera del cliente. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun SinRutina(modelo: ModeloApp) {
    val alcance = LocalAlcanceApp.current
    var recargando by remember { mutableStateOf(false) }
    MarcoPantalla("Entreno") { relleno ->
        PullToRefreshBox(
            isRefreshing = recargando,
            onRefresh = {
                recargando = true
                alcance.launch {
                    try {
                        modelo.cargar()
                    } finally {
                        recargando = false
                    }
                }
            },
            modifier = Modifier.padding(relleno).fillMaxSize(),
        ) {
            Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(top = 80.dp)) {
                EstadoVacio(
                    icono = Iconos.Pesa,
                    titulo = "Todavía no hay rutina",
                    texto = "Cuando Mati publique tu rutina, la vas a ver acá.",
                    modifier = Modifier.testTag("entreno-vacio"),
                )
            }
        }
    }
}

/**
 * Lo que las pantallas leen del motor. Cada cambio publica una copia nueva del día (el motor nunca toca la que ya
 * publicó), así que esto cambia cuando cambia algo y las piezas que lo reciben se recomponen. El descanso no va acá: cambia
 * cuatro veces por segundo y solo lo mira su barra.
 */
@Immutable
data class VistaEntreno(
    val dia: DiaEnCurso,
    val comentarios: IndiceComentarios,
    val completados: Set<String>,
    val inicio: Double?,
    val porBoton: Boolean,
    val sesionIniciada: Boolean,
    val cargandoHistorial: Set<String>,
    val catalogo: CatalogoEjercicios,
    val estructura: EstructuraRutina,
    val rutina: RutinaActiva,
)

@Composable
fun vistaDe(m: ModeloEntreno): VistaEntreno {
    val dia by m.dia.collectAsStateWithLifecycle()
    val comentarios by m.comentarios.collectAsStateWithLifecycle()
    val completados by m.diasCompletados.collectAsStateWithLifecycle()
    val inicio by m.inicioSesion.collectAsStateWithLifecycle()
    val porBoton by m.iniciadaConBoton.collectAsStateWithLifecycle()
    val sesion by m.sesionIniciada.collectAsStateWithLifecycle()
    val cargando by m.historialCargando.collectAsStateWithLifecycle()
    val catalogo by m.catalogo.collectAsStateWithLifecycle()
    val estructura by m.estructura.collectAsStateWithLifecycle()
    val rutina by m.rutina.collectAsStateWithLifecycle()
    return VistaEntreno(dia, comentarios, completados, inicio, porBoton, sesion, cargando, catalogo, estructura, rutina)
}
