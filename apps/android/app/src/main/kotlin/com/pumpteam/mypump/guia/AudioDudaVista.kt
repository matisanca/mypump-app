package com.pumpteam.mypump.guia

import android.Manifest
import android.content.Intent
import android.net.Uri
import android.provider.Settings
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.repeatOnLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.pumpteam.mypump.datos.ModeloAudioDudas
import com.pumpteam.mypump.diseno.BotonMarca
import com.pumpteam.mypump.diseno.BotonSecundario
import com.pumpteam.mypump.diseno.Espacio
import com.pumpteam.mypump.diseno.MyPump
import com.pumpteam.mypump.entreno.reducirMovimiento
import com.pumpteam.mypump.reglas.MaquinaAudioDuda
import com.pumpteam.mypump.reglas.ReglasAudioDuda
import com.pumpteam.mypump.raiz.LocalAlcanceApp
import kotlinx.coroutines.launch

/**
 * Lo que rodea a los audios en toda la pantalla de la guía (no adentro de la lista, que suelta los ítems al bajar):
 * - al empezar a grabar o escuchar se pausa el video y el campo de texto pierde el foco;
 * - si la app pasa a segundo plano, o se sale de la guía, se frena y queda para revisar;
 * - la lista de audios se pide al abrir y, con alguno en `subido`, cada 15 s hasta 3 minutos, solo con la guía a la vista.
 */
@Composable
fun AudioDudaAlrededor(audios: ModeloAudioDudas, control: ControlReproductor) {
    val vm: ControlAudioDuda = viewModel()
    val foco = LocalFocusManager.current
    vm.alEmpezar = {
        control.pausar()
        foco.clearFocus()
    }
    val ciclo = LocalLifecycleOwner.current
    val actividad = LocalContext.current.actividadDeAudio()
    DisposableEffect(ciclo) {
        val obs = LifecycleEventObserver { _, e -> if (e == Lifecycle.Event.ON_STOP) vm.segundoPlano() }
        ciclo.lifecycle.addObserver(obs)
        onDispose {
            ciclo.lifecycle.removeObserver(obs)
            // Girar el teléfono arma la Activity de nuevo: eso no es salir de la guía.
            if (actividad?.isChangingConfigurations != true) vm.segundoPlano()
        }
    }
    val disponible by audios.disponible.collectAsStateWithLifecycle()
    LaunchedEffect(audios, ciclo) {
        ciclo.repeatOnLifecycle(Lifecycle.State.RESUMED) { audios.seguir() }
    }
    // Si dejó de estar disponible (la función se sacó) con algo para revisar, no queda colgado.
    LaunchedEffect(disponible) { if (!disponible) vm.borrar() }
}

/**
 * El audio dentro del recuadro de dudas para la videollamada, debajo del campo: la invitación, «Grabar un audio», la
 * grabación con su contador, la revisión (escuchar, Mandar, Grabar de nuevo, Borrar) y cómo va cada audio mandado
 * (sin la transcripción: el cliente no se entera de que se pasa a texto). Sin la
 * 019 en el servidor no se muestra nada ([ModeloAudioDudas.disponible]).
 */
@Composable
fun AudioDudaLlamada(audios: ModeloAudioDudas, despues: Boolean, modifier: Modifier = Modifier) {
    val disponible by audios.disponible.collectAsStateWithLifecycle()
    if (!disponible) return
    val vm: ControlAudioDuda = viewModel()
    val items by audios.items.collectAsStateWithLifecycle()
    val c = MyPump.colores
    val contexto = LocalContext.current
    val alcance = LocalAlcanceApp.current
    // Se relee el permiso cuando vuelve el cartel o de los ajustes.
    var vuelta by remember { mutableIntStateOf(0) }
    val lanzador = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { ok ->
        vuelta++
        vm.alPermiso(ok)
    }
    val permiso = remember(vuelta, vm.estado) { vm.permisoActual() }
    val estado = vm.estado
    val mandandoAlguno = items.any { it.estado == ModeloAudioDudas.Estado.MANDANDO } || vm.mandando

    Column(modifier.fillMaxWidth().testTag("audio-duda"), verticalArrangement = Arrangement.spacedBy(Espacio.xs)) {
        Box(Modifier.fillMaxWidth().padding(vertical = 2.dp).background(c.separador).padding(top = 1.dp))
        Text(ReglasAudioDuda.INVITACION, style = MaterialTheme.typography.bodyMedium, color = c.textoSecundario, modifier = Modifier.testTag("audio-invitacion"))

        when (estado) {
            is MaquinaAudioDuda.Estado.Grabando -> Grabando(vm.segundos, alTerminar = vm::terminar)
            is MaquinaAudioDuda.Estado.Revisando -> Revisando(
                segundos = estado.segundos,
                escuchando = vm.escuchando,
                posicion = vm.posicionEscucha,
                mandando = vm.mandando,
                alEscuchar = vm::escuchar,
                alMandar = { vm.mandar(audios) },
                alGrabarDeNuevo = { vm.grabar(vm.permisoActual()) { lanzador.launch(Manifest.permission.RECORD_AUDIO) } },
                alBorrar = vm::borrar,
            )
            else -> {
                BotonMarca(
                    ReglasAudioDuda.GRABAR,
                    alTocar = { vm.grabar(vm.permisoActual()) { lanzador.launch(Manifest.permission.RECORD_AUDIO) } },
                    compacto = true,
                    habilitado = estado == MaquinaAudioDuda.Estado.Reposo && !mandandoAlguno,
                    modifier = Modifier
                        .semantics {
                            contentDescription = ReglasAudioDuda.GRABAR
                            stateDescription = "Sin grabar"
                        }
                        .testTag("audio-grabar"),
                )
                if (permiso != MaquinaAudioDuda.Permiso.CONCEDIDO) {
                    Text(ReglasAudioDuda.ANTES_DEL_PERMISO, style = MaterialTheme.typography.bodySmall, color = c.textoTerciario, modifier = Modifier.testTag("audio-antes-permiso"))
                }
            }
        }

        // La región viva: los avisos de la grabación (y los errores del micrófono o del permiso).
        vm.aviso?.let { a ->
            Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(Espacio.xxs)) {
                Text(
                    a.texto,
                    style = MaterialTheme.typography.bodySmall,
                    color = if (a.error) c.peligro else c.textoSecundario,
                    modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite }.testTag("audio-aviso"),
                )
                if (a.ajustes) {
                    BotonSecundario(
                        ReglasAudioDuda.ABRIR_AJUSTES,
                        alTocar = {
                            val i = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", contexto.packageName, null))
                                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            runCatching { contexto.startActivity(i) }
                        },
                        compacto = true,
                        modifier = Modifier.testTag("audio-ajustes"),
                    )
                }
            }
        }

        for (it in items) ItemAudio(it, despues, alReintentar = { alcance.launch { audios.reintentar(it.id) } })
    }
}

/** «Terminar» en rojo, el contador como número aparte y el punto que late (quieto con «Quitar animaciones»). */
@Composable
private fun Grabando(segundos: Int, alTerminar: () -> Unit) {
    val c = MyPump.colores
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espacio.s)) {
        Button(
            onClick = alTerminar,
            shape = CircleShape,
            colors = ButtonDefaults.buttonColors(containerColor = c.peligro, contentColor = androidx.compose.ui.graphics.Color.White),
            modifier = Modifier
                .padding(vertical = 2.dp)
                .semantics {
                    contentDescription = ReglasAudioDuda.TERMINAR_ACCESIBLE
                    stateDescription = "Grabando"
                }
                .testTag("audio-terminar"),
        ) { Text(ReglasAudioDuda.TERMINAR, style = MaterialTheme.typography.labelLarge) }
        val quieto = reducirMovimiento()
        val opacidad = if (quieto) {
            1f
        } else {
            val t = rememberInfiniteTransition(label = "punto")
            t.animateFloat(1f, 0.25f, infiniteRepeatable(tween(700), RepeatMode.Reverse), label = "punto").value
        }
        Box(Modifier.size(12.dp).alpha(opacidad).clip(CircleShape).background(c.peligro).testTag("audio-punto"))
        // El contador no se anuncia cada segundo: se anuncia la duración al terminar.
        Text(
            ReglasAudioDuda.contador(segundos),
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.SemiBold,
            modifier = Modifier.clearAndSetSemantics {}.testTag("audio-contador"),
        )
    }
}

@Composable
private fun Revisando(
    segundos: Int,
    escuchando: Boolean,
    posicion: Int,
    mandando: Boolean,
    alEscuchar: () -> Unit,
    alMandar: () -> Unit,
    alGrabarDeNuevo: () -> Unit,
    alBorrar: () -> Unit,
) {
    val c = MyPump.colores
    Column(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(12.dp))
            .background(c.campo)
            .padding(horizontal = Espacio.s, vertical = Espacio.xs)
            .testTag("audio-revisar"),
        verticalArrangement = Arrangement.spacedBy(Espacio.xs),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espacio.s)) {
            BotonSecundario(
                if (escuchando) "Pausar" else "Escuchar",
                alTocar = alEscuchar,
                compacto = true,
                tono = c.marcaTexto,
                habilitado = !mandando,
                modifier = Modifier.testTag("audio-escuchar"),
            )
            Column(Modifier.weight(1f)) {
                LinearProgressIndicator(
                    progress = { if (segundos > 0) (posicion.toFloat() / segundos).coerceIn(0f, 1f) else 0f },
                    color = c.marca,
                    trackColor = c.borde,
                    modifier = Modifier.fillMaxWidth().clearAndSetSemantics {},
                )
                Text(
                    ReglasAudioDuda.contador(if (escuchando) posicion else segundos),
                    style = MaterialTheme.typography.labelMedium,
                    color = c.textoSecundario,
                    modifier = Modifier.padding(top = 2.dp).semantics { contentDescription = "Tu audio dura " + ReglasAudioDuda.contador(segundos) }.testTag("audio-duracion"),
                )
            }
        }
        FlowRow(horizontalArrangement = Arrangement.spacedBy(Espacio.xs), verticalArrangement = Arrangement.spacedBy(Espacio.xs)) {
            BotonMarca(ReglasAudioDuda.MANDAR, alTocar = alMandar, compacto = true, cargando = mandando, modifier = Modifier.testTag("audio-mandar"))
            BotonSecundario(ReglasAudioDuda.GRABAR_DE_NUEVO, alTocar = alGrabarDeNuevo, compacto = true, habilitado = !mandando, modifier = Modifier.testTag("audio-de-nuevo"))
            BotonSecundario(ReglasAudioDuda.BORRAR, alTocar = alBorrar, compacto = true, tono = c.peligro, habilitado = !mandando, modifier = Modifier.testTag("audio-borrar"))
        }
    }
}

/** Cómo va un audio mandado: saliendo, no salió, me llegó o no se escuchó. La transcripción nunca se muestra. */
@Composable
private fun ItemAudio(item: ModeloAudioDudas.Item, despues: Boolean, alReintentar: () -> Unit) {
    val c = MyPump.colores
    Column(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(12.dp))
            .background(c.campo)
            .padding(horizontal = Espacio.s, vertical = Espacio.xs)
            .semantics(mergeDescendants = false) { liveRegion = LiveRegionMode.Polite }
            .testTag("audio-item-" + (if (item.estado == ModeloAudioDudas.Estado.TRANSCRIPTO) "subido" else item.estado.name.lowercase())),
        verticalArrangement = Arrangement.spacedBy(2.dp),
    ) {
        when (item.estado) {
            ModeloAudioDudas.Estado.MANDANDO -> Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espacio.xs)) {
                CircularProgressIndicator(Modifier.size(14.dp), color = c.marca, strokeWidth = 2.dp)
                Text(ReglasAudioDuda.MANDANDO, style = MaterialTheme.typography.bodyMedium, color = c.textoSecundario)
            }
            ModeloAudioDudas.Estado.NO_SE_MANDO -> {
                Text(item.aviso ?: ReglasAudioDuda.NO_SE_PUDO, style = MaterialTheme.typography.bodyMedium, color = c.peligro)
                if (item.reintentable) {
                    BotonSecundario(ReglasAudioDuda.REINTENTAR, alTocar = alReintentar, compacto = true, tono = c.marcaTexto, modifier = Modifier.testTag("audio-reintentar"))
                }
            }
            // Subido o transcripto se ve igual: el cliente no se entera de que se pasa a texto (Mati, 4-nov).
            ModeloAudioDudas.Estado.SUBIDO, ModeloAudioDudas.Estado.TRANSCRIPTO -> Text(
                if (despues) ReglasAudioDuda.SUBIDO_DESPUES else ReglasAudioDuda.SUBIDO,
                style = MaterialTheme.typography.bodyMedium,
                color = c.textoSecundario,
            )
            ModeloAudioDudas.Estado.ERROR -> Text(ReglasAudioDuda.ERROR_AUDIO, style = MaterialTheme.typography.bodyMedium, color = c.peligro)
        }
    }
}

private tailrec fun android.content.Context.actividadDeAudio(): android.app.Activity? = when (this) {
    is android.app.Activity -> this
    is android.content.ContextWrapper -> baseContext.actividadDeAudio()
    else -> null
}
