package com.pumpteam.mypump.progreso

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.pumpteam.mypump.datos.ModeloApp
import com.pumpteam.mypump.datos.ModeloProgreso
import com.pumpteam.mypump.datos.TarjetaProgreso
import com.pumpteam.mypump.diseno.AnchoLectura
import com.pumpteam.mypump.diseno.BotonMarca
import com.pumpteam.mypump.diseno.EncabezadoSeccion
import com.pumpteam.mypump.diseno.Espacio
import com.pumpteam.mypump.diseno.EstadoVacio
import com.pumpteam.mypump.diseno.Iconos
import com.pumpteam.mypump.diseno.MarcoPantalla
import com.pumpteam.mypump.diseno.MyPump
import com.pumpteam.mypump.diseno.Numeros
import com.pumpteam.mypump.diseno.Separador
import com.pumpteam.mypump.diseno.superficieTarjeta
import com.pumpteam.mypump.entreno.Dato
import com.pumpteam.mypump.entreno.Letras
import com.pumpteam.mypump.entreno.NombreEjercicio
import com.pumpteam.mypump.raiz.BannerRevision
import com.pumpteam.mypump.raiz.LocalAlcanceApp
import kotlinx.coroutines.launch

/**
 * Progreso (PRO-01…05, ProgresoView.swift): los totales arriba y, por día, cada ejercicio una sola vez (por clave, no por
 * lugar) con el tope de sus últimas 8 sesiones, la variación, el 🏆 PR y una curva chica. Tocar una fila abre el detalle
 * (`ProgresoDetalle`) dentro de la pestaña; Atrás vuelve a la lista.
 *
 * Se carga al abrir la pestaña (como la web), solo si no hay nada o la vez anterior faltó la red, y siempre con
 * `ModeloApp.cargarProgreso`: agrupa por el ejercicio que se hace de verdad, el sustituto si hay (PRO-02). Tirar hacia
 * abajo la vuelve a traer. En la demo no hay historial (como la web).
 */
@Composable
fun ProgresoPantalla(modelo: ModeloApp) {
    val progreso by modelo.progreso.collectAsStateWithLifecycle()
    val p = progreso
    val tarjetas = p?.tarjetas?.collectAsStateWithLifecycle()?.value.orEmpty()
    val estado = p?.estado?.collectAsStateWithLifecycle()?.value
    val sesiones = p?.sesiones?.collectAsStateWithLifecycle()?.value ?: 0
    val alcance = LocalAlcanceApp.current
    // El ejercicio abierto (su id). Sobrevive a cambiar de pestaña y a rotar, como la pila de iOS.
    var abierto by rememberSaveable { mutableStateOf<String?>(null) }
    // Afuera de la lista: al volver del detalle queda donde estaba.
    val estadoLista = rememberLazyListState()

    // El `.task` de iOS: al abrir la pestaña, solo si no hay tarjetas o faltó la red (lo demás se actualiza tirando). En
    // el alcance de la app: cambiar de pestaña no corta la carga a la mitad.
    LaunchedEffect(p) {
        val m = p ?: return@LaunchedEffect
        if (m.tarjetas.value.isEmpty() || m.estado.value == ModeloProgreso.Estado.SIN_RED) {
            alcance.launch { modelo.cargarProgreso() }
        }
    }

    val elegida = abierto?.let { id -> tarjetas.firstOrNull { it.id == id } }
    BackHandler(enabled = elegida != null) { abierto = null }

    AnimatedContent(
        targetState = elegida,
        contentKey = { it?.id },
        transitionSpec = {
            if (targetState != null) {
                (slideInHorizontally { it } + fadeIn()) togetherWith (slideOutHorizontally { -it / 4 } + fadeOut())
            } else {
                (slideInHorizontally { -it / 4 } + fadeIn()) togetherWith (slideOutHorizontally { it } + fadeOut())
            }
        },
        label = "progreso",
    ) { t ->
        if (t == null) {
            ListaProgreso(modelo, p, tarjetas, estado, sesiones, estadoLista, alAbrir = { abierto = it })
        } else {
            ProgresoDetalle(t, alVolver = { abierto = null })
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ListaProgreso(
    modelo: ModeloApp,
    p: ModeloProgreso?,
    tarjetas: List<TarjetaProgreso>,
    estado: ModeloProgreso.Estado?,
    sesiones: Int,
    estadoLista: LazyListState,
    alAbrir: (String) -> Unit,
) {
    val alcance = LocalAlcanceApp.current
    var recargando by remember { mutableStateOf(false) }
    fun recargar() {
        recargando = true
        alcance.launch {
            try {
                modelo.cargarProgreso()
            } finally {
                recargando = false
            }
        }
    }
    MarcoPantalla("Progreso", modifier = Modifier.testTag("progreso-pantalla")) { relleno ->
        Box(Modifier.padding(relleno).fillMaxSize()) {
            when {
                // Trayendo el historial por primera vez.
                p != null && estado == ModeloProgreso.Estado.CARGANDO && tarjetas.isEmpty() -> EsqueletoProgreso()
                // PRO-05: se cortó la red y no hay nada que mostrar.
                p != null && estado == ModeloProgreso.Estado.SIN_RED && tarjetas.isEmpty() -> SinRed(modelo, cargando = recargando, alReintentar = ::recargar)
                else -> PullToRefreshBox(isRefreshing = recargando, onRefresh = ::recargar, modifier = Modifier.fillMaxSize()) {
                    if (tarjetas.isEmpty()) {
                        SinHistorial(modelo)
                    } else {
                        Lista(modelo, tarjetas, sesiones, estadoLista, alAbrir)
                    }
                }
            }
        }
    }
}

@Composable
private fun Lista(modelo: ModeloApp, tarjetas: List<TarjetaProgreso>, sesiones: Int, estadoLista: LazyListState, alAbrir: (String) -> Unit) {
    val secciones = remember(tarjetas) { VistaProgreso.secciones(tarjetas) }
    LazyColumn(
        state = estadoLista,
        modifier = Modifier.fillMaxSize().testTag("progreso-lista"),
        contentPadding = PaddingValues(start = Espacio.m, end = Espacio.m, top = Espacio.xxs, bottom = Espacio.xl),
        verticalArrangement = Arrangement.spacedBy(Espacio.l),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        // Como la web, arriba de todas las escenas menos Revisión (GEN-03). Sin pendientes no ocupa lugar.
        item(key = "banner") { BannerRevision(modelo, Modifier.widthIn(max = AnchoLectura)) }
        item(key = "totales") { Totales(tarjetas.size, sesiones, Modifier.widthIn(max = AnchoLectura)) }
        items(secciones, key = { "seccion-${it.id}" }) { s ->
            SeccionProgreso(s, alAbrir, Modifier.widthIn(max = AnchoLectura))
        }
    }
}

/** PRO-01: cuántos ejercicios tienen historial y cuántas sesiones hubo. Con letra grande, uno debajo del otro. */
@Composable
private fun Totales(ejercicios: Int, sesiones: Int, modifier: Modifier = Modifier) {
    val grande = LocalDensity.current.fontScale >= 1.3f
    val m = modifier.fillMaxWidth().testTag("progreso-totales")
    if (grande) {
        Column(m, verticalArrangement = Arrangement.spacedBy(Espacio.s)) {
            Dato("Ejercicios", "$ejercicios", null, Iconos.Pesa, Modifier.fillMaxWidth())
            Dato("Sesiones", "$sesiones", null, Iconos.Calendario, Modifier.fillMaxWidth())
        }
    } else {
        Row(m, horizontalArrangement = Arrangement.spacedBy(Espacio.s)) {
            Dato("Ejercicios", "$ejercicios", null, Iconos.Pesa, Modifier.weight(1f))
            Dato("Sesiones", "$sesiones", null, Iconos.Calendario, Modifier.weight(1f))
        }
    }
}

/** PRO-02: "Tirón · Piernas" y sus ejercicios en una tarjeta, separados como una lista. */
@Composable
private fun SeccionProgreso(s: VistaProgreso.Seccion, alAbrir: (String) -> Unit, modifier: Modifier = Modifier) {
    Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(Espacio.s)) {
        EncabezadoSeccion(s.titulo, detalle = "máx. por sesión")
        Column(Modifier.fillMaxWidth().superficieTarjeta()) {
            s.tarjetas.forEachIndexed { i, t ->
                FilaProgreso(t, alTocar = { alAbrir(t.id) })
                if (i < s.tarjetas.size - 1) Separador(sangria = Espacio.m)
            }
        }
    }
}

/**
 * PRO-03: el ejercicio (y el músculo abajo), el 🏆 si la última sesión superó a todas, "Top 58 kg" (o "Peso corporal"), la
 * variación y la curva de las últimas 8. Con letra grande la curva baja a lo ancho. TalkBack lee una sola frase.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun FilaProgreso(t: TarjetaProgreso, alTocar: () -> Unit) {
    val c = MyPump.colores
    val nombre = NombreEjercicio(t.nombre)
    val grande = LocalDensity.current.fontScale >= 1.3f
    val conPeso = VistaProgreso.conPeso(t)
    Box(
        Modifier
            .fillMaxWidth()
            .clickable(role = Role.Button, onClick = alTocar)
            .semantics(mergeDescendants = true) { contentDescription = VistaProgreso.accesible(t) }
            .testTag("progreso-fila-${t.id}"),
    ) {
        val textos = @Composable { mod: Modifier ->
            Column(mod, verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(nombre.principal, style = Letras.subtitulo.copy(fontWeight = FontWeight.SemiBold), color = c.texto, maxLines = if (grande) Int.MAX_VALUE else 2)
                nombre.detalle?.let { Text(it, style = Letras.caption, color = c.textoSecundario, maxLines = if (grande) Int.MAX_VALUE else 1) }
                FlowRow(
                    Modifier.padding(top = 2.dp),
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                    verticalArrangement = Arrangement.spacedBy(4.dp),
                    itemVerticalAlignment = Alignment.CenterVertically,
                ) {
                    if (t.resumen.esPR) InsigniaPR(compacta = true, accesible = false)
                    if (conPeso) {
                        Text(
                            buildAnnotatedString {
                                withStyle(SpanStyle(fontFamily = null, fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = c.textoSecundario)) { append("Top") }
                                append(" ${VistaProgreso.kg(t.resumen.tope)} kg")
                            },
                            style = Numeros.chico.merge(Letras.cifras),
                            color = c.texto,
                        )
                    } else {
                        Text("Peso corporal", style = Letras.subtitulo.copy(fontWeight = FontWeight.SemiBold), color = c.textoSecundario)
                    }
                    PildoraVariacion(t.resumen.variacion)
                }
            }
        }
        if (grande) {
            Column(Modifier.fillMaxWidth().padding(start = Espacio.m, end = Espacio.m + 18.dp, top = 14.dp, bottom = 14.dp), verticalArrangement = Arrangement.spacedBy(Espacio.s)) {
                textos(Modifier.fillMaxWidth())
                CurvaChica(t.resumen.serie, t.resumen.esPR, Modifier.fillMaxWidth().height(56.dp))
            }
        } else {
            Row(
                Modifier.fillMaxWidth().padding(start = Espacio.m, end = Espacio.m + 18.dp, top = 14.dp, bottom = 14.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                textos(Modifier.weight(1f))
                Spacer(Modifier.width(Espacio.xs))
                CurvaChica(t.resumen.serie, t.resumen.esPR, Modifier.size(width = 84.dp, height = 44.dp))
            }
        }
        Icon(
            Iconos.Chevron,
            contentDescription = null,
            tint = c.textoTerciario,
            modifier = Modifier.align(Alignment.CenterEnd).padding(end = Espacio.s).size(20.dp),
        )
    }
}

/** PRO-05: todavía no hay nada registrado (o es la demo, que como la web no tiene historial). */
@Composable
private fun SinHistorial(modelo: ModeloApp) {
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState())) {
        BannerRevision(modelo, Modifier.padding(horizontal = Espacio.m))
        EstadoVacio(
            icono = Iconos.Tendencia,
            titulo = "Aún no hay historial",
            texto = "Aún no hay historial registrado. Empezá tu primera sesión para ver el progreso acá.",
            modifier = Modifier.padding(top = 80.dp).testTag("progreso-vacio"),
        )
    }
}

/** PRO-05: se cortó la red trayendo el historial. Reintentar lo vuelve a pedir (con el sustituto, como al abrir). */
@Composable
private fun SinRed(modelo: ModeloApp, cargando: Boolean, alReintentar: () -> Unit) {
    Column(Modifier.fillMaxSize()) {
        BannerRevision(modelo, Modifier.padding(horizontal = Espacio.m))
        EstadoVacio(
            icono = Iconos.SinWifi,
            titulo = "No pudimos traer tu historial",
            texto = "Sin conexión. Revisá la señal y probá de nuevo.",
            modifier = Modifier.weight(1f).testTag("progreso-sin-red"),
            accion = {
                BotonMarca("Reintentar", alTocar = alReintentar, compacto = true, cargando = cargando, modifier = Modifier.testTag("progreso-reintentar"))
            },
        )
    }
}

/** PRO-01: el esqueleto mientras llega el historial (los totales y dos secciones), con el brillo de `esqueleto`. */
@Composable
private fun EsqueletoProgreso() {
    Column(
        Modifier
            .fillMaxSize()
            .padding(horizontal = Espacio.m)
            .padding(top = Espacio.xs)
            // La etiqueta antes: `esqueleto` limpia la semántica de lo que viene después.
            .testTag("progreso-cargando")
            .esqueleto(),
        verticalArrangement = Arrangement.spacedBy(Espacio.l),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Row(Modifier.widthIn(max = AnchoLectura).fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(Espacio.s)) {
            repeat(2) {
                Column(Modifier.weight(1f).superficieTarjeta().padding(14.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                        BloqueEsqueleto(12.dp, 12.dp, forma = CircleShape)
                        BloqueEsqueleto(80.dp, 12.dp)
                    }
                    BloqueEsqueleto(30.dp, 20.dp)
                }
            }
        }
        repeat(2) {
            Column(Modifier.widthIn(max = AnchoLectura).fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(Espacio.s)) {
                BloqueEsqueleto(70.dp, 20.dp, Modifier.padding(horizontal = 4.dp))
                Column(Modifier.fillMaxWidth().superficieTarjeta()) {
                    repeat(4) { i ->
                        Row(Modifier.fillMaxWidth().padding(Espacio.m), verticalAlignment = Alignment.CenterVertically) {
                            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                BloqueEsqueleto(170.dp, 14.dp)
                                BloqueEsqueleto(110.dp, 12.dp)
                            }
                            BloqueEsqueleto(84.dp, 44.dp)
                        }
                        if (i < 3) Separador(sangria = Espacio.m)
                    }
                }
            }
        }
    }
}
