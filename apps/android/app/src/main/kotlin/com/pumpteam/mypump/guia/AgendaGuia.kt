package com.pumpteam.mypump.guia

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.CalendarContract
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTagsAsResourceId
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.repeatOnLifecycle
import com.pumpteam.mypump.datos.ModeloApp
import com.pumpteam.mypump.diseno.AsaHoja
import com.pumpteam.mypump.diseno.BotonMarca
import com.pumpteam.mypump.diseno.Espacio
import com.pumpteam.mypump.diseno.FormaHoja
import com.pumpteam.mypump.diseno.Iconos
import com.pumpteam.mypump.diseno.MyPump
import com.pumpteam.mypump.diseno.Radio
import com.pumpteam.mypump.diseno.superficieTarjeta
import com.pumpteam.mypump.modelos.AgendaEntrega
import com.pumpteam.mypump.modelos.FranjaEntrega
import com.pumpteam.mypump.modelos.ReservaEntrega
import com.pumpteam.mypump.reglas.ReglasAgenda
import java.time.Instant
import java.time.ZoneId
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

// La agenda de la entrega al final de «Tu guía» (2.2.0, ~/Desktop/Entregas-v2/app/spec.md §3): el contador de los videos
// que faltan, la tarjeta bloqueada, las franjas por día, la hoja de confirmación, la reserva pendiente y la confirmada con
// «Entrar a la videollamada». El servidor decide todo; esto pide, muestra y reserva. Sin formularios.

/** «Te faltan N videos para habilitar la agenda»: tocarlo salta al primer video que falta. */
@Composable
fun ContadorObligatorios(faltan: Int, alTocar: (() -> Unit)?, modifier: Modifier = Modifier) {
    val c = MyPump.colores
    val texto = ReglasAgenda.textoContador(faltan)
    Row(
        modifier
            .fillMaxWidth()
            .heightIn(min = 48.dp)
            .then(if (alTocar != null) Modifier.clickable(role = Role.Button, onClickLabel = "Ir al próximo video", onClick = alTocar) else Modifier)
            .padding(horizontal = 4.dp, vertical = Espacio.xs)
            .testTag("agenda-contador"),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(Espacio.xs),
    ) {
        Icon(Iconos.Video, contentDescription = null, tint = c.marcaTexto, modifier = Modifier.size(20.dp))
        Text(texto, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold, color = c.marcaTexto, modifier = Modifier.weight(1f))
    }
}

/**
 * La tarjeta de la agenda en su estado ([vista]). [faltan] es el número que se muestra (el del servidor si vino). Las
 * horas van en la zona del teléfono ([zona]).
 */
@Composable
fun TarjetaAgenda(
    agenda: AgendaEntrega,
    vista: ReglasAgenda.Vista,
    faltan: Int,
    aviso: String?,
    desdeCache: Boolean,
    esDemo: Boolean,
    zona: ZoneId,
    alIrAlProximo: (() -> Unit)?,
    alReservar: (FranjaEntrega) -> Unit,
    modifier: Modifier = Modifier,
) {
    val contexto = LocalContext.current
    var elegida by remember { mutableStateOf<FranjaEntrega?>(null) }
    Column(modifier.fillMaxWidth().testTag("agenda"), verticalArrangement = Arrangement.spacedBy(Espacio.xs)) {
        if (desdeCache) {
            Row(
                Modifier.semantics { liveRegion = LiveRegionMode.Polite }.testTag("agenda-sin-conexion"),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                Icon(Iconos.SinWifi, contentDescription = null, tint = MyPump.colores.alerta, modifier = Modifier.padding(start = 4.dp).size(18.dp))
                Text("Sin conexión", style = MaterialTheme.typography.labelLarge, color = MyPump.colores.alerta)
            }
        }
        when (vista) {
            ReglasAgenda.Vista.NO_AUTORIZADA -> Bloqueada(ReglasAgenda.TEXTO_NO_AUTORIZADA, null, "agenda-no-autorizada")
            ReglasAgenda.Vista.BLOQUEADA -> Bloqueada(ReglasAgenda.textoBloqueada(faltan), alIrAlProximo, "agenda-bloqueada")
            ReglasAgenda.Vista.HABILITANDO -> Bloqueada(ReglasAgenda.textoBloqueada(0), null, "agenda-habilitando")
            ReglasAgenda.Vista.SIN_FRANJAS -> TarjetaTexto(ReglasAgenda.TEXTO_SIN_FRANJAS, "agenda-sin-franjas")
            ReglasAgenda.Vista.ELEGIR -> Franjas(agenda.franjas, aviso, zona, alElegir = { elegida = it })
            ReglasAgenda.Vista.PENDIENTE -> Pendiente()
            ReglasAgenda.Vista.CONFIRMADA -> agenda.reserva?.let { r ->
                Confirmada(
                    r,
                    esDemo = esDemo,
                    zona = zona,
                    alEntrar = { url -> abrirMeet(contexto, url) },
                    alAgregar = { agregarAlCalendario(contexto, r) },
                )
            }
        }
    }
    elegida?.let { f ->
        HojaConfirmar(
            texto = ReglasAgenda.textoConfirmar(f, zona),
            alConfirmar = {
                elegida = null
                alReservar(f)
            },
            alCerrar = { elegida = null },
        )
    }
}

@Composable
private fun TituloAgenda(modifier: Modifier = Modifier) {
    Text(
        "Agendá tu entrega",
        style = MaterialTheme.typography.titleMedium,
        fontWeight = FontWeight.SemiBold,
        modifier = modifier.semantics { heading() },
    )
}

/** La tarjeta gris con candado. */
@Composable
private fun Bloqueada(texto: String, alIrAlProximo: (() -> Unit)?, etiqueta: String) {
    val c = MyPump.colores
    Column(
        Modifier.fillMaxWidth().superficieTarjeta(color = c.campo).padding(Espacio.m + 2.dp).testTag(etiqueta),
        verticalArrangement = Arrangement.spacedBy(Espacio.xs),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espacio.s)) {
            Icon(Iconos.Candado, contentDescription = null, tint = c.textoSecundario, modifier = Modifier.size(22.dp))
            TituloAgenda(Modifier.weight(1f))
        }
        Text(texto, style = MaterialTheme.typography.bodyMedium, color = c.textoSecundario, modifier = Modifier.testTag("agenda-texto"))
        if (alIrAlProximo != null) {
            OutlinedButton(
                onClick = alIrAlProximo,
                modifier = Modifier.padding(top = Espacio.xxs).defaultMinSize(minHeight = 48.dp).testTag("agenda-ir-al-proximo"),
                shape = CircleShape,
                colors = ButtonDefaults.outlinedButtonColors(contentColor = c.marcaTexto),
            ) {
                Text("Ir al próximo video", style = MaterialTheme.typography.labelLarge)
            }
        }
    }
}

@Composable
private fun TarjetaTexto(texto: String, etiqueta: String) {
    val c = MyPump.colores
    Column(Modifier.fillMaxWidth().superficieTarjeta().padding(Espacio.m + 2.dp).testTag(etiqueta), verticalArrangement = Arrangement.spacedBy(Espacio.xs)) {
        TituloAgenda()
        Text(texto, style = MaterialTheme.typography.bodyMedium, color = c.textoSecundario)
    }
}

/** Las franjas por día, con chips «10:00 a 12:00». */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun Franjas(franjas: List<FranjaEntrega>, aviso: String?, zona: ZoneId, alElegir: (FranjaEntrega) -> Unit) {
    val c = MyPump.colores
    val dias = remember(franjas, zona) { ReglasAgenda.porDia(franjas, zona) }
    val difiere = remember(franjas, zona) { ReglasAgenda.difiereDeArgentina(zona, franjas.map { it.inicio }) }
    Column(
        Modifier.fillMaxWidth().superficieTarjeta().padding(Espacio.m + 2.dp).testTag("agenda-franjas"),
        verticalArrangement = Arrangement.spacedBy(Espacio.s),
    ) {
        TituloAgenda()
        Text("Elegí el horario que mejor te quede.", style = MaterialTheme.typography.bodyMedium, color = c.textoSecundario)
        if (aviso != null) {
            Text(
                aviso,
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.SemiBold,
                color = c.peligro,
                modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite }.testTag("agenda-aviso"),
            )
        }
        for ((dia, delDia) in dias) {
            Text(dia, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold, modifier = Modifier.padding(top = 4.dp).semantics { heading() })
            FlowRow(horizontalArrangement = Arrangement.spacedBy(Espacio.xs), verticalArrangement = Arrangement.spacedBy(Espacio.xs)) {
                for (f in delDia) {
                    val rango = ReglasAgenda.rango(f.inicio, f.fin, zona)
                    OutlinedButton(
                        onClick = { alElegir(f) },
                        modifier = Modifier
                            .defaultMinSize(minHeight = 48.dp)
                            // TalkBack lee el día con la hora (el chip solo, «10:00 a 12:00», no dice cuándo).
                            .semantics { contentDescription = "$dia, de $rango" }
                            .testTag("agenda-franja-${f.id}"),
                        shape = CircleShape,
                        colors = ButtonDefaults.outlinedButtonColors(contentColor = c.marcaTexto),
                    ) {
                        Text(rango, style = MaterialTheme.typography.labelLarge)
                    }
                }
            }
        }
        if (difiere) {
            Text(ReglasAgenda.TEXTO_HORARIO_TELEFONO, style = MaterialTheme.typography.bodySmall, color = c.textoTerciario, modifier = Modifier.testTag("agenda-horario-telefono"))
        }
    }
}

@Composable
private fun Pendiente() {
    val c = MyPump.colores
    Row(
        Modifier
            .fillMaxWidth()
            .superficieTarjeta()
            .semantics(mergeDescendants = true) { liveRegion = LiveRegionMode.Polite }
            .padding(Espacio.m + 2.dp)
            .testTag("agenda-pendiente"),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(Espacio.s),
    ) {
        CircularProgressIndicator(color = c.marca, strokeWidth = 3.dp, modifier = Modifier.size(24.dp))
        Text(ReglasAgenda.TEXTO_PENDIENTE, style = MaterialTheme.typography.bodyLarge, modifier = Modifier.weight(1f))
    }
}

/**
 * La tarjeta verde: el día y la hora, «Agregar a mi calendario» y cómo cambiarla. «Entrar a la videollamada» no aparece al
 * confirmar: recién con Mati en el Meet (`sala_abierta_en`) o, de respaldo, a la hora de inicio (cambio de Mati del 6/11).
 * El mismo día, mientras tanto, «Tu entrega es hoy a las 10:00. Cuando Mati abra…». La hora se vuelve a mirar cada 30 s
 * (la agenda la consulta `seguir`).
 */
@Composable
private fun Confirmada(r: ReservaEntrega, esDemo: Boolean, zona: ZoneId, alEntrar: (String) -> Unit, alAgregar: () -> Unit) {
    val forma = RoundedCornerShape(Radio.tarjeta)
    val texto = ReglasAgenda.textoConfirmada(r, zona)
    val ahora = ahoraCada30s(r)
    val sala = ReglasAgenda.textoSala(r, zona, ahora)
    val puedeEntrar = ReglasAgenda.puedeEntrar(r, ahora)
    Column(
        Modifier.fillMaxWidth().clip(forma).background(VerdeGuia).padding(Espacio.m + 2.dp).testTag("agenda-confirmada"),
        verticalArrangement = Arrangement.spacedBy(Espacio.s),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espacio.s)) {
            Box(Modifier.size(36.dp).clip(CircleShape).background(Color.White), contentAlignment = Alignment.Center) {
                Icon(Iconos.Calendario, contentDescription = null, tint = VerdeGuia, modifier = Modifier.size(20.dp))
            }
            Text(
                texto,
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold,
                color = Color.White,
                modifier = Modifier.weight(1f).semantics { heading() }.testTag("agenda-confirmada-texto"),
            )
        }
        if (sala != null) {
            Text(
                sala,
                style = MaterialTheme.typography.bodyLarge,
                color = Color.White,
                // Que TalkBack avise cuando cambia (Mati abrió la sala) sin tener que volver a recorrer la tarjeta.
                modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite }.testTag("agenda-sala"),
            )
        }
        val url = r.meetUrl
        if (url != null && puedeEntrar) {
            Button(
                onClick = { alEntrar(url) },
                modifier = Modifier.fillMaxWidth().defaultMinSize(minHeight = 52.dp).testTag("agenda-entrar"),
                shape = CircleShape,
                colors = ButtonDefaults.buttonColors(containerColor = Color.White, contentColor = VerdeGuia),
                elevation = null,
            ) {
                Text(if (r.salaAbiertaEn != null) "Entrar" else "Entrar a la videollamada", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center)
            }
        } else if (url == null && esDemo) {
            Text(ReglasAgenda.TEXTO_DEMO, style = MaterialTheme.typography.bodyMedium, color = Color.White, modifier = Modifier.testTag("agenda-demo"))
        }
        if (r.inicio != null) {
            TextButton(
                onClick = alAgregar,
                modifier = Modifier.defaultMinSize(minHeight = 48.dp).testTag("agenda-calendario"),
                colors = ButtonDefaults.textButtonColors(contentColor = Color.White),
            ) {
                Icon(Iconos.Calendario, contentDescription = null, modifier = Modifier.size(18.dp))
                Spacer(Modifier.size(6.dp))
                Text("Agregar a mi calendario", style = MaterialTheme.typography.labelLarge)
            }
        }
        Text(ReglasAgenda.TEXTO_CAMBIAR, style = MaterialTheme.typography.bodySmall, color = Color.White.copy(alpha = 0.92f), modifier = Modifier.testTag("agenda-cambiar"))
    }
}

/** La hoja de confirmación: la pregunta, [Confirmar] y [Elegir otro]. */
@OptIn(ExperimentalMaterial3Api::class, ExperimentalComposeUiApi::class)
@Composable
private fun HojaConfirmar(texto: String, alConfirmar: () -> Unit, alCerrar: () -> Unit) {
    val c = MyPump.colores
    val hoja = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val alcance = rememberCoroutineScope()
    fun cerrarY(accion: () -> Unit) {
        alcance.launch { hoja.hide() }.invokeOnCompletion { accion() }
    }
    ModalBottomSheet(
        onDismissRequest = alCerrar,
        sheetState = hoja,
        shape = FormaHoja,
        containerColor = c.fondo,
        tonalElevation = 0.dp,
        dragHandle = { AsaHoja() },
        modifier = Modifier.semantics { testTagsAsResourceId = true }.testTag("agenda-hoja"),
    ) {
        Column(
            Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).navigationBarsPadding().padding(horizontal = Espacio.l, vertical = Espacio.m),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(Espacio.s),
        ) {
            Text(
                texto,
                style = MaterialTheme.typography.titleLarge,
                textAlign = TextAlign.Center,
                modifier = Modifier.widthIn(max = 460.dp).semantics { heading() }.testTag("agenda-hoja-texto"),
            )
            Spacer(Modifier.height(Espacio.xs))
            Column(Modifier.widthIn(max = 460.dp).fillMaxWidth()) {
                BotonMarca("Confirmar", alTocar = { cerrarY(alConfirmar) }, modifier = Modifier.testTag("agenda-confirmar"))
                Spacer(Modifier.height(Espacio.xs))
                TextButton(
                    onClick = { cerrarY(alCerrar) },
                    modifier = Modifier.fillMaxWidth().defaultMinSize(minHeight = 48.dp).testTag("agenda-elegir-otro"),
                    colors = ButtonDefaults.textButtonColors(contentColor = c.marcaTexto),
                ) {
                    Text("Elegir otro", style = MaterialTheme.typography.titleSmall)
                }
            }
        }
    }
}

/** La hora, que se vuelve a mirar cada 30 s (y al cambiar la reserva): para que el botón aparezca a tiempo. */
@Composable
private fun ahoraCada30s(r: ReservaEntrega?): Instant {
    val ahora by produceState(Instant.now(), r) {
        while (true) {
            value = Instant.now()
            delay(ReglasAgenda.CONSULTA_SALA_MS)
        }
    }
    return ahora
}

/**
 * La entrega arriba de Entreno, con la reserva confirmada, desde 30 min antes hasta el fin de la franja, con la misma regla
 * que la tarjeta de la guía: sin botón hasta que Mati abra la sala («Mati ya está en la videollamada · Entrar») o, de
 * respaldo, hasta la hora de inicio. La reserva sale de la agenda (si se consultó) o del resumen. Con la pantalla en primer
 * plano y en la franja, la agenda se consulta cada 30 s.
 */
@Composable
fun EntregaAhoraDe(modelo: ModeloApp, modifier: Modifier = Modifier) {
    val g = modelo.guia.collectAsStateWithLifecycle().value ?: return
    val resumen by g.resumen.collectAsStateWithLifecycle()
    val agenda by g.agenda.agenda.collectAsStateWithLifecycle()
    val r = (if (agenda != null) agenda?.reserva else null) ?: resumen?.reserva
    val ciclo = LocalLifecycleOwner.current.lifecycle
    LaunchedEffect(g, ciclo) {
        ciclo.repeatOnLifecycle(Lifecycle.State.RESUMED) {
            g.agenda.seguirSala { g.agenda.agenda.value?.reserva ?: g.resumen.value?.reserva }
        }
    }
    val ahora = ahoraCada30s(r)
    if (r == null || !ReglasAgenda.tarjetaEntreno(r, ahora)) return
    val zona = ZoneId.systemDefault()
    val url = r.meetUrl?.takeIf { ReglasAgenda.puedeEntrar(r, ahora) }
    val contexto = LocalContext.current
    val texto = ReglasAgenda.textoSala(r, zona, ahora) ?: ReglasAgenda.textoConfirmada(r, zona)
    val forma = RoundedCornerShape(Radio.tarjeta)
    Row(
        modifier
            .fillMaxWidth()
            .clip(forma)
            .background(VerdeGuia)
            .then(
                if (url != null) Modifier.clickable(role = Role.Button, onClickLabel = "Entrar a la videollamada") { abrirMeet(contexto, url) }
                else Modifier.semantics { liveRegion = LiveRegionMode.Polite },
            )
            .padding(horizontal = Espacio.m + 2.dp, vertical = Espacio.s)
            .testTag("entrega-ahora"),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(Espacio.s),
    ) {
        Icon(Iconos.Video, contentDescription = null, tint = Color.White, modifier = Modifier.size(24.dp))
        Text(texto, style = MaterialTheme.typography.bodyLarge, color = Color.White, modifier = Modifier.weight(1f))
        if (url != null) {
            Text("Entrar", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold, color = Color.White, modifier = Modifier.testTag("entrega-ahora-entrar"))
        }
    }
}

/** El link de Meet: lo abre la app de Meet si está, o el navegador. */
internal fun abrirMeet(contexto: Context, url: String) {
    try {
        contexto.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
    } catch (_: ActivityNotFoundException) {
        // Sin nada que abra un link: no hay mucho que hacer.
    }
}

/**
 * «Agregar a mi calendario»: `Intent.ACTION_INSERT` al calendario del teléfono, que muestra su propia pantalla para guardar
 * el evento (sin permisos de la app ni de la cuenta).
 */
internal fun agregarAlCalendario(contexto: Context, r: ReservaEntrega) {
    val inicio = r.inicio ?: return
    val intent = Intent(Intent.ACTION_INSERT)
        .setData(CalendarContract.Events.CONTENT_URI)
        .putExtra(CalendarContract.EXTRA_EVENT_BEGIN_TIME, inicio.toEpochMilli())
        // Sin fin, el calendario pone su duración (no se inventa una).
        .apply { r.fin?.let { putExtra(CalendarContract.EXTRA_EVENT_END_TIME, it.toEpochMilli()) } }
        .putExtra(CalendarContract.Events.TITLE, "Entrega Pump Team")
        .apply { r.meetUrl?.let { putExtra(CalendarContract.Events.DESCRIPTION, it).putExtra(CalendarContract.Events.EVENT_LOCATION, it) } }
    try {
        contexto.startActivity(intent)
    } catch (_: ActivityNotFoundException) {
        // Sin app de calendario.
    }
}
