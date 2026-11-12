package com.pumpteam.mypump.guia

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.CalendarContract
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
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
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.Modifier
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
import com.pumpteam.mypump.datos.ModeloAgenda
import com.pumpteam.mypump.diseno.AsaHoja
import com.pumpteam.mypump.diseno.BotonMarca
import com.pumpteam.mypump.diseno.Espacio
import com.pumpteam.mypump.diseno.FormaHoja
import com.pumpteam.mypump.diseno.Iconos
import com.pumpteam.mypump.diseno.MyPump
import com.pumpteam.mypump.diseno.abrirEnNavegador
import com.pumpteam.mypump.diseno.superficieTarjeta
import com.pumpteam.mypump.modelos.AgendaEntrega
import com.pumpteam.mypump.modelos.FranjaEntrega
import com.pumpteam.mypump.modelos.ReservaEntrega
import com.pumpteam.mypump.reglas.ReglasAgenda
import kotlinx.coroutines.launch
import java.time.ZoneId

// La agenda de la videollamada al final de «Tu guía» (2.2.0, ~/Desktop/Entregas-v2/app/spec.md §3): el contador de los
// videos que faltan, la tarjeta bloqueada, las franjas por día, la hoja de confirmación y la reserva pendiente. La
// confirmada es la tarjeta de la videollamada (2.3.0, `Videollamada.kt`), la misma de Entreno. El servidor decide todo;
// esto pide, muestra y reserva. Sin formularios.

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
    /** La agenda (para la pantalla de elegir o cambiar el horario y la tarjeta de la videollamada). */
    modeloAgenda: ModeloAgenda? = null,
    /** La palanca `elegir_horario`: la pantalla nueva en lugar de los chips. */
    elegirHorario: Boolean = false,
) {
    var elegida by remember { mutableStateOf<FranjaEntrega?>(null) }
    var pantalla by remember { mutableStateOf<ModoHorario?>(null) }
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
        // Cada texto puede venir pisado del servidor (`textos`, spec §7).
        val titulo = ReglasAgenda.textoTitulo(agenda)
        when (vista) {
            ReglasAgenda.Vista.NO_AUTORIZADA ->
                Bloqueada(titulo, ReglasAgenda.texto(agenda, "no_autorizada", ReglasAgenda.TEXTO_NO_AUTORIZADA, faltan = faltan), null, "agenda-no-autorizada")
            ReglasAgenda.Vista.BLOQUEADA ->
                Bloqueada(titulo, ReglasAgenda.texto(agenda, "bloqueada", ReglasAgenda.textoBloqueada(faltan), faltan = faltan), alIrAlProximo, "agenda-bloqueada")
            ReglasAgenda.Vista.HABILITANDO -> Bloqueada(titulo, ReglasAgenda.textoBloqueada(0), null, "agenda-habilitando")
            ReglasAgenda.Vista.SIN_FRANJAS -> TarjetaTexto(titulo, ReglasAgenda.texto(agenda, "sin_franjas", ReglasAgenda.TEXTO_SIN_FRANJAS), "agenda-sin-franjas")
            ReglasAgenda.Vista.ELEGIR ->
                if (elegirHorario && modeloAgenda != null) {
                    // La palanca `elegir_horario`: la pantalla nueva para elegir (y después cambiar).
                    TarjetaElegirHorario(agenda, aviso?.let { ReglasAgenda.texto(agenda, "fallo", it) }, alAbrir = { pantalla = ModoHorario.Elegir })
                } else {
                    Franjas(agenda, aviso?.let { ReglasAgenda.texto(agenda, "fallo", it) }, zona, alElegir = { elegida = it })
                }
            ReglasAgenda.Vista.PENDIENTE -> Pendiente(ReglasAgenda.texto(agenda, "pendiente", ReglasAgenda.TEXTO_PENDIENTE))
            ReglasAgenda.Vista.CONFIRMADA -> agenda.reserva?.let { r ->
                // La misma tarjeta que arriba de Entreno (videollamada 2.3.0). La agenda la consulta `seguir` (el link si
                // falta y la sala).
                if (modeloAgenda != null) {
                    TarjetaVideollamada(
                        modeloAgenda = modeloAgenda,
                        agenda = agenda,
                        reserva = r,
                        ahora = ahoraCada15s(r),
                        desdeCache = false,
                        esDemo = esDemo,
                        elegirHorario = elegirHorario,
                        alCambiar = { pantalla = ModoHorario.Cambiar(r) },
                        etiqueta = "agenda-confirmada",
                    )
                }
            }
        }
    }
    if (modeloAgenda != null) {
        pantalla?.let { m -> PantallaHorario(modeloAgenda, (m as? ModoHorario.Cambiar)?.reserva, alCerrar = { pantalla = null }) }
    }
    elegida?.let { f ->
        HojaConfirmar(
            texto = ReglasAgenda.textoConfirmar(f, zona, agenda),
            alConfirmar = {
                elegida = null
                alReservar(f)
            },
            alCerrar = { elegida = null },
        )
    }
}

@Composable
private fun TituloAgenda(titulo: String, modifier: Modifier = Modifier) {
    Text(
        titulo,
        style = MaterialTheme.typography.titleMedium,
        fontWeight = FontWeight.SemiBold,
        modifier = modifier.semantics { heading() },
    )
}

/** La tarjeta gris con candado. */
@Composable
private fun Bloqueada(titulo: String, texto: String, alIrAlProximo: (() -> Unit)?, etiqueta: String) {
    val c = MyPump.colores
    Column(
        Modifier.fillMaxWidth().superficieTarjeta(color = c.campo).padding(Espacio.m + 2.dp).testTag(etiqueta),
        verticalArrangement = Arrangement.spacedBy(Espacio.xs),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Espacio.s)) {
            Icon(Iconos.Candado, contentDescription = null, tint = c.textoSecundario, modifier = Modifier.size(22.dp))
            TituloAgenda(titulo, Modifier.weight(1f))
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
private fun TarjetaTexto(titulo: String, texto: String, etiqueta: String) {
    val c = MyPump.colores
    Column(Modifier.fillMaxWidth().superficieTarjeta().padding(Espacio.m + 2.dp).testTag(etiqueta), verticalArrangement = Arrangement.spacedBy(Espacio.xs)) {
        TituloAgenda(titulo)
        Text(texto, style = MaterialTheme.typography.bodyMedium, color = c.textoSecundario)
    }
}

/** Las franjas por día, con chips «10:00 a 12:00». */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun Franjas(agenda: AgendaEntrega, aviso: String?, zona: ZoneId, alElegir: (FranjaEntrega) -> Unit) {
    val c = MyPump.colores
    val franjas = agenda.franjas
    val dias = remember(franjas, zona) { ReglasAgenda.porDia(franjas, zona) }
    val difiere = remember(franjas, zona) { ReglasAgenda.difiereDeArgentina(zona, franjas.map { it.inicio }) }
    Column(
        Modifier.fillMaxWidth().superficieTarjeta().padding(Espacio.m + 2.dp).testTag("agenda-franjas"),
        verticalArrangement = Arrangement.spacedBy(Espacio.s),
    ) {
        TituloAgenda(ReglasAgenda.textoTitulo(agenda))
        Text(
            ReglasAgenda.textoEncabezado(agenda, franjas),
            style = MaterialTheme.typography.bodyMedium,
            color = c.textoSecundario,
            modifier = Modifier.testTag("agenda-encabezado"),
        )
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
private fun Pendiente(texto: String) {
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
        Text(texto, style = MaterialTheme.typography.bodyLarge, modifier = Modifier.weight(1f))
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

/**
 * El link de Meet: lo abre la app de Meet si está (el link de Meet es un App Link suyo) o, si no, el navegador. Si el
 * sistema no deja elegir nada (un perfil de trabajo raro), se prueba directo con el navegador.
 */
internal fun abrirMeet(contexto: Context, url: String) {
    // 1) La app de Meet, FIJA: un VIEW implícito al link lo podía tomar Gmail (o el diálogo de elegir app), y con otra cuenta
    //    o sin sesión el alumno caía en la bandeja o en la portada de Meet, no en la reunión (lo reportó Mati, 12/11). Con el
    //    paquete fijo va directo a ESA reunión; Meet deja entrar con la cuenta que tenga o como invitado, con su nombre.
    if (appDeMeetInstalada(contexto)) {
        val enMeet = Intent(Intent.ACTION_VIEW, Uri.parse(url)).setPackage(PAQUETE_MEET)
        if (contexto !is android.app.Activity) enMeet.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        try {
            contexto.startActivity(enMeet)
            return
        } catch (_: ActivityNotFoundException) {
        } catch (_: SecurityException) {
        }
    }
    // 2) Sin la app: la web de Meet en una Custom Tab dentro de MyPump. La pestaña no le pasa el link a otra app al cargar,
    //    así que no cae en Gmail; en el celular Android la web de Meet manda a instalar la app desde Google Play (probado en
    //    el emulador, 12/11), y la tarjeta lo avisa (TEXTO_SIN_APP_MEET): instalada, el próximo toque va por 1).
    //    3) Sin Custom Tabs: el navegador (nunca Gmail).
    abrirEnNavegador(contexto, url)
}

/** La app de Google Meet de hoy (la que era Duo). La «Meet (original)», `com.google.android.apps.meetings`, ya no entra. */
internal const val PAQUETE_MEET = "com.google.android.apps.tachyon"

/** Si la app de Meet está instalada y prendida. Verla necesita el `<queries>` del manifest (Android 11+). */
internal fun appDeMeetInstalada(contexto: Context): Boolean = try {
    contexto.packageManager.getApplicationInfo(PAQUETE_MEET, 0).enabled
} catch (_: Exception) {
    false
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
        .putExtra(CalendarContract.Events.TITLE, ReglasAgenda.mayuscula(ReglasAgenda.nombre(r.tipo)) + " con Mati")
        // Se entra desde la app (Mati, 10/11); el link queda en el evento solo de respaldo.
        .putExtra(CalendarContract.Events.DESCRIPTION, "Entrá desde la app MyPump, en Entreno. Mati te admite en la sala.")
        .apply { r.meetUrl?.let { putExtra(CalendarContract.Events.EVENT_LOCATION, it) } }
    try {
        contexto.startActivity(intent)
    } catch (_: ActivityNotFoundException) {
        // Sin app de calendario.
    }
}
