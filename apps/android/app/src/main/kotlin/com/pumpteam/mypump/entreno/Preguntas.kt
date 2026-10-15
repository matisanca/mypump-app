package com.pumpteam.mypump.entreno

import androidx.compose.runtime.Composable
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import com.pumpteam.mypump.diseno.Alerta
import com.pumpteam.mypump.diseno.BotonAlerta
import com.pumpteam.mypump.reglas.Pregunta
import kotlinx.coroutines.CompletableDeferred

/**
 * Las preguntas del motor (`Pregunta`: reabrir el día, "¿Está bien cargado?", terminar sin datos, "¡Día completado!",
 * avanzar de semana, el bloque nuevo) como diálogos del sistema, esperando la respuesta. Gemelo del `Preguntador` de iOS.
 * Vive en el ViewModel: una pregunta abierta sobrevive a rotar la pantalla, y lo que la espera corre en el alcance de la
 * app.
 */
@Stable
class Preguntador {
    var actual by mutableStateOf<Pregunta?>(null)
        private set

    private var respuesta: CompletableDeferred<Boolean>? = null

    /** Muestra la pregunta y espera. Una pregunta nueva contesta "no" a la que estaba abierta. */
    suspend fun preguntar(p: Pregunta): Boolean {
        respuesta?.complete(false)
        val r = CompletableDeferred<Boolean>()
        respuesta = r
        actual = p
        return try {
            r.await()
        } finally {
            if (respuesta === r) {
                respuesta = null
                actual = null
            }
        }
    }

    fun responder(si: Boolean) {
        val r = respuesta
        respuesta = null
        actual = null
        r?.complete(si)
    }
}

/**
 * El diálogo de la pregunta abierta, con los textos de la app: sin el emoji del título y los nombres de los días como en
 * la lista ("Ir a EMPUJE" → "Ir a Empuje"). Atrás o tocar afuera es "no".
 */
@Composable
fun DialogoPreguntas(p: Preguntador) {
    val q = p.actual ?: return
    Alerta(
        titulo = Bonito.sinEmoji(q.titulo),
        mensaje = Bonito.nombres(q.cuerpo),
        botones = buildList {
            if (q.cancelar.isNotEmpty()) {
                add(BotonAlerta(Bonito.nombres(Bonito.boton(q.cancelar)), etiqueta = "pregunta-no", cancelar = true) { p.responder(false) })
            }
            add(BotonAlerta(Bonito.nombres(Bonito.boton(q.confirmar)), etiqueta = "pregunta-si") { p.responder(true) })
        },
        alDescartar = { p.responder(false) },
        modifier = Modifier.testTag("pregunta"),
    )
}
