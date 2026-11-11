package com.pumpteam.mypump.revision

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.pumpteam.mypump.datos.ModeloFotos
import com.pumpteam.mypump.datos.ModeloRevision
import com.pumpteam.mypump.diseno.BotonSecundario
import com.pumpteam.mypump.diseno.EncabezadoSeccion
import com.pumpteam.mypump.diseno.Espacio
import com.pumpteam.mypump.diseno.MyPump
import com.pumpteam.mypump.diseno.Tarjeta
import com.pumpteam.mypump.reglas.CheckGuiado
import com.pumpteam.mypump.reglas.FechaLocal
import com.pumpteam.mypump.reglas.FotosProgreso

/** Las fotos de esta semana como las ven «Fotos de la semana» y el check guiado: cuáles están, subiendo o esperando señal. */
internal data class FotosDeLaSemana(
    val semana: String,
    val hechas: Set<String>,
    val pendientes: Set<String>,
    val urls: Map<String, String>,
    val subiendo: Set<String>,
)

@Composable
internal fun fotosDeLaSemana(modelo: ModeloFotos?): FotosDeLaSemana {
    val fotos = modelo?.fotos?.collectAsStateWithLifecycle()?.value ?: emptyList()
    val pendientes = modelo?.pendientes?.collectAsStateWithLifecycle()?.value ?: emptyMap()
    val urls = modelo?.urls?.collectAsStateWithLifecycle()?.value ?: emptyMap()
    val subiendo = modelo?.subiendo?.collectAsStateWithLifecycle()?.value ?: emptySet()
    val semana = modelo?.semanaActual ?: FotosProgreso.lunes(FechaLocal.hoy())
    val hechas = remember(fotos, pendientes, semana) {
        FotosProgreso.posesDeLaSemana(fotos, pendientes.values.map { it.pose to it.fecha }, semana)
    }
    return FotosDeLaSemana(semana, hechas, pendientes.keys, urls, subiendo)
}

/**
 * La tarjeta del check guiado en Revisión (2.3.0, con la palanca `check_guiado`): va primera, arriba de todo, y abre el
 * check de un paso por pantalla ([CheckGuiadoFlujo]). El texto y el botón salen de `CheckGuiado.estado`:
 * sin empezar, a medias (se retoma donde quedó), enviado, o enviado sin las fotos (abre directo en las fotos).
 */
@Composable
internal fun CheckGuiadoTarjeta(
    revision: ModeloRevision,
    fotos: ModeloFotos?,
    modifier: Modifier = Modifier,
    alAbrir: (CheckGuiado.Paso?) -> Unit,
) {
    val guardado = revision.checkin.collectAsStateWithLifecycle().value
    val borrador = revision.borradorGuiado.collectAsStateWithLifecycle().value
    val semana = FotosProgreso.lunes(revision.fecha.collectAsStateWithLifecycle().value)
    val deLaSemana = fotosDeLaSemana(fotos)
    // Sin saber qué fotos hay en el servidor no se dice «te faltan» (como el aviso de las fotos).
    val cargadas = fotos?.cargadas?.collectAsStateWithLifecycle()?.value ?: false
    val faltanFotos = fotos != null && cargadas && deLaSemana.hechas.size < 3
    val enviado = (guardado?.valores?.get("energia") ?: 0) > 0
    val estado = CheckGuiado.estado(enviado, borrador, semana, faltanFotos)
    val pasos = CheckGuiado.pasos(faltanFotos)
    val hechos = when (estado) {
        CheckGuiado.Estado.SIN_EMPEZAR -> 0
        CheckGuiado.Estado.A_MEDIAS -> borrador?.let { pasos.indexOf(CheckGuiado.retomar(it, pasos)) }?.coerceAtLeast(1) ?: 1
        CheckGuiado.Estado.ENVIADO -> pasos.size
        CheckGuiado.Estado.ENVIADO_SIN_FOTOS -> pasos.size - 1
    }
    val c = MyPump.colores

    Column(modifier, verticalArrangement = Arrangement.spacedBy(Espacio.s)) {
        EncabezadoSeccion("Check de la semana", detalle = if (enviado) "Enviado" else null)
        Tarjeta(Modifier.testTag("check-guiado-tarjeta"), espaciado = Espacio.m) {
            Text(
                CheckGuiado.textoTarjeta(estado),
                style = MaterialTheme.typography.bodyLarge,
                color = c.texto,
                modifier = Modifier.testTag("check-guiado-texto"),
            )
            AvanceCheck(pasos.size, hechos, Modifier.fillMaxWidth(), descripcion = "$hechos de ${pasos.size} pasos")
            val texto = CheckGuiado.botonTarjeta(estado)
            val abrir = { alAbrir(if (estado == CheckGuiado.Estado.ENVIADO_SIN_FOTOS) CheckGuiado.Paso.FOTOS else null) }
            // El verde, solo para lo que avanza: con todo enviado, «Cambiar algo» es un botón secundario.
            if (estado == CheckGuiado.Estado.ENVIADO) {
                BotonSecundario(texto, alTocar = abrir, modifier = Modifier.heightIn(min = 58.dp).testTag("check-guiado-abrir"))
            } else {
                BotonPrincipalCheck(texto, alTocar = abrir, modifier = Modifier.testTag("check-guiado-abrir"))
            }
        }
    }
}
