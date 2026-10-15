package com.pumpteam.mypump.acceso

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.compositeOver
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTagsAsResourceId
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.pumpteam.mypump.avisos.CentroAvisos
import com.pumpteam.mypump.avisos.IconosAvisos
import com.pumpteam.mypump.avisos.PermisoAvisos
import com.pumpteam.mypump.avisos.rememberPedidoAvisos
import com.pumpteam.mypump.datos.ModeloApp
import com.pumpteam.mypump.datos.ModeloSalud
import com.pumpteam.mypump.datos.Preferencias
import com.pumpteam.mypump.diseno.Archivo
import com.pumpteam.mypump.diseno.BotonMarca
import com.pumpteam.mypump.diseno.MyPump
import com.pumpteam.mypump.raiz.LocalAlcanceApp
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch

/** Si falta mostrar la hoja de permisos de la primera vez (`mypump_onboarding_v1`, la misma clave de la web). */
object Onboarding {
    const val CLAVE = "mypump_onboarding_v1"

    fun pendiente(p: Preferencias): Boolean = p.leer(CLAVE) != "1"
}

private enum class Paso { SALUD, AVISOS }

/**
 * La primera vez con una cuenta (GEN-06, gemela de OnboardingPermisos.swift; cliente.html:4447-4593): Salud y después
 * Notificaciones, cada una con su porqué. "Ahora no" nunca dispara la hoja del sistema y nunca se traba; Salud corta a los
 * 20 s (la conexión sigue de fondo); si dice que no, se le explica dónde cambiarlo. Se muestra una sola vez (la misma clave
 * de la web: quien ya lo vio en la app vieja no lo ve de nuevo, la trae la migración). Cerrarla con Atrás o deslizándola
 * cuenta como "Ahora no" para lo que quedaba.
 *
 * Salud aparece solo si el teléfono la tiene (`ModeloSalud.fuenteDelSistema`, que pone la etapa de Health Connect); los
 * textos son los de la versión Android de la web, sin "Apple".
 */
@OptIn(ExperimentalMaterial3Api::class, ExperimentalComposeUiApi::class)
@Composable
fun OnboardingPermisos(modelo: ModeloApp, version: String, alTerminar: () -> Unit) {
    val c = MyPump.colores
    val contexto = LocalContext.current
    val alcance = LocalAlcanceApp.current
    val salud by modelo.salud.collectAsStateWithLifecycle()
    var pasos by remember { mutableStateOf<List<Paso>?>(null) }
    var i by rememberSaveable { mutableIntStateOf(0) }
    var trabajando by remember { mutableStateOf(false) }
    var aviso by rememberSaveable { mutableStateOf<String?>(null) }
    var resultado by rememberSaveable { mutableStateOf<String?>(null) }

    /** Un paso que se cerró a mano mientras esperaba: lo que vuelva no se pinta encima del siguiente. */
    var generacion by remember { mutableIntStateOf(0) }
    var generacionDelPedido by remember { mutableIntStateOf(-1) }
    val hoja = rememberModalBottomSheetState(skipPartiallyExpanded = true)

    LaunchedEffect(Unit) {
        val disponible = try {
            modelo.salud.value != null && ModeloSalud.fuenteDelSistema?.disponible() == true
        } catch (e: CancellationException) {
            throw e
        } catch (_: Exception) {
            false
        }
        // Notificaciones solo si todavía no llegan: hasta Android 12 vienen prendidas y el paso sobraba (lo vio el emulador
        // de Android 9). Sin ningún paso, queda vista sin mostrarse.
        val lista = buildList {
            if (disponible) add(Paso.SALUD)
            if (!CentroAvisos.concedido(contexto)) add(Paso.AVISOS)
        }
        if (lista.isEmpty()) {
            modelo.preferencias.guardar(Onboarding.CLAVE, "1")
            alTerminar()
        } else {
            pasos = lista
        }
    }

    fun terminar() {
        modelo.preferencias.guardar(Onboarding.CLAVE, "1")
        alTerminar()
    }

    fun siguiente(conservarAviso: Boolean = false) {
        generacion++
        trabajando = false
        resultado = null
        if (!conservarAviso) aviso = null
        if (i + 1 >= (pasos?.size ?: 1)) terminar() else i++
    }

    val pedir = rememberPedidoAvisos { ok ->
        if (generacionDelPedido != generacion) return@rememberPedidoAvisos
        trabajando = false
        if (ok) {
            CentroAvisos.alActivar(contexto.applicationContext, modelo, version, alcance)
            siguiente()
        } else {
            resultado = SIN_PERMISO
        }
    }

    fun aceptar(paso: Paso) {
        val gen = generacion
        when (paso) {
            Paso.SALUD -> {
                val s = salud ?: return siguiente()
                trabajando = true
                // En el alcance de la app: si la hoja se cierra, la conexión sigue (y lo que vuelva no pisa nada).
                alcance.launch {
                    val r = s.conectar(limiteMs = 20_000)
                    if (gen != generacion) return@launch
                    trabajando = false
                    when {
                        r == null -> {
                            aviso = "Salud está tardando un poco más de lo normal: sigue conectándose de fondo."
                            siguiente(conservarAviso = true)
                        }
                        r.ok -> siguiente()
                        else -> resultado = "No se pudo activar ahora. Podés intentarlo más tarde desde Mis datos."
                    }
                }
            }
            Paso.AVISOS -> when (CentroAvisos.permiso(contexto)) {
                PermisoAvisos.CONCEDIDO -> {
                    CentroAvisos.alActivar(contexto.applicationContext, modelo, version, alcance)
                    siguiente()
                }
                // Ya lo negó: la hoja del sistema no vuelve a salir (como `.denied` en iOS).
                PermisoAvisos.NEGADO -> resultado = SIN_PERMISO
                PermisoAvisos.SIN_PEDIR -> {
                    trabajando = true
                    generacionDelPedido = gen
                    pedir()
                }
            }
        }
    }

    // Un Atrás mientras la hoja todavía está apareciendo (antes de que su ventana tenga el foco) lo recibía la actividad y
    // mandaba la app al fondo: cuenta como "Ahora no", igual que cerrarla (lo encontró la suite completa el 15-oct).
    BackHandler {
        generacion++
        terminar()
    }

    ModalBottomSheet(
        onDismissRequest = {
            generacion++
            terminar()
        },
        sheetState = hoja,
        containerColor = c.fondo,
        tonalElevation = 0.dp,
        modifier = Modifier.semantics { testTagsAsResourceId = true }.testTag("onboarding-permisos"),
    ) {
        val lista = pasos
        val paso = lista?.getOrNull(i)
        BoxWithConstraints(Modifier.fillMaxWidth().fillMaxHeight()) {
            val alto = maxHeight
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .verticalScroll(rememberScrollState())
                    .heightIn(min = alto)
                    .padding(horizontal = 24.dp)
                    .padding(bottom = 16.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(18.dp),
            ) {
                if (lista != null && paso != null) {
                    val esSalud = paso == Paso.SALUD
                    Spacer(Modifier.weight(1f).heightIn(min = 12.dp))
                    Azulejo(esSalud)
                    Text(
                        if (esSalud) "Conectá tu salud" else "Que no se te pase nada",
                        style = TextStyle(fontFamily = Archivo, fontWeight = FontWeight.W800, fontSize = 28.sp, lineHeight = 32.sp),
                        textAlign = TextAlign.Center,
                        modifier = Modifier.semantics { heading() },
                    )
                    Text(
                        if (esSalud) {
                            "MyPump puede leer lo que ya mide ${salud?.textos?.telefono ?: "tu teléfono"} o tu reloj: pasos, sueño, pulso en reposo y variabilidad. Con eso Mati ve cómo venís recuperando de verdad y te ajusta el plan con datos, no a ojo."
                        } else {
                            "Para que te lleguen los mensajes de Mati y su aviso de los domingos para la revisión. Nada más: no te vamos a llenar el teléfono de notificaciones."
                        },
                        style = MaterialTheme.typography.bodyLarge,
                        textAlign = TextAlign.Center,
                    )
                    // El aviso del domingo no se configura (pedido de Mati, 14-oct): no se promete apagarlo ni cambiar la hora.
                    if (esSalud) {
                        Text(
                            "Se lee solo. Nunca escribimos nada en tu app de Salud.",
                            style = MaterialTheme.typography.bodySmall,
                            color = c.textoSecundario,
                            textAlign = TextAlign.Center,
                        )
                    }
                    val texto = aviso ?: resultado
                    if (texto != null) {
                        Text(
                            texto,
                            style = MaterialTheme.typography.bodySmall,
                            color = if (resultado != null) c.alerta else c.textoSecundario,
                            textAlign = TextAlign.Center,
                            modifier = Modifier
                                .fillMaxWidth()
                                .clip(RoundedCornerShape(12.dp))
                                .background(c.campo)
                                .padding(12.dp)
                                .testTag("onboarding-aviso"),
                        )
                    }
                    Spacer(Modifier.weight(1f).heightIn(min = 4.dp))
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        if (resultado == null) {
                            BotonMarca(
                                if (esSalud) "Permitir acceso a Salud" else "Activar notificaciones",
                                alTocar = { aceptar(paso) },
                                cargando = trabajando,
                                modifier = Modifier.testTag("onboarding-aceptar"),
                            )
                        }
                        // La puerta de salida nunca se traba (la 1.0.4 dejaba "Un momento…" sin salida).
                        TextButton(
                            onClick = { siguiente() },
                            modifier = Modifier.fillMaxWidth().heightIn(min = 44.dp).testTag("onboarding-ahora-no"),
                        ) {
                            Text(
                                if (resultado == null) "Ahora no" else if (i == lista.size - 1) "Entendido" else "Seguir",
                                style = MaterialTheme.typography.bodyLarge,
                                fontWeight = FontWeight.SemiBold,
                                color = c.marcaTexto,
                            )
                        }
                        Text(
                            "${if (lista.size > 1) "paso ${i + 1} de ${lista.size} · " else ""}esto lo podés cambiar después en Mis datos",
                            style = MaterialTheme.typography.labelSmall,
                            color = c.textoTerciario,
                            textAlign = TextAlign.Center,
                        )
                    }
                }
            }
        }
    }
}

// iOS dice la ruta de sus Ajustes; en Android cambia según la marca, así que se manda a Mis datos, que abre la pantalla justa.
private const val SIN_PERMISO = "Quedó sin permiso. Si cambiás de idea, lo activás desde Mis datos."

/** El ícono del paso: el corazón en rojo o la campana en el lima de la marca, en un azulejo grande con sombra de su color. */
@Composable
private fun Azulejo(esSalud: Boolean) {
    val c = MyPump.colores
    val fondo = if (esSalud) c.corazon else c.marca
    val forma = RoundedCornerShape(24.dp)
    Column(
        modifier = Modifier
            .padding(bottom = 4.dp)
            .size(88.dp)
            .shadow(16.dp, forma, ambientColor = fondo.copy(alpha = 0.35f), spotColor = fondo.copy(alpha = 0.35f))
            .clip(forma)
            // El degradé opaco (sobre el fondo): uno transparente dejaría ver la sombra a través.
            .background(Brush.verticalGradient(listOf(fondo.copy(alpha = 0.85f).compositeOver(c.fondo), fondo))),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Icon(
            if (esSalud) IconosAvisos.Corazon else IconosAvisos.Campana,
            contentDescription = null,
            tint = if (esSalud) Color.White else c.sobreMarca,
            modifier = Modifier.size(42.dp),
        )
    }
}
