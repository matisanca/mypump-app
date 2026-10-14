package com.pumpteam.mypump.raiz

import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.Saver
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.vector.ImageVector
import com.pumpteam.mypump.datos.DestinoAviso
import com.pumpteam.mypump.diseno.Iconos

/** Las 5 pestañas de la app actual (GEN-01), en el mismo orden. */
enum class Pestana(val titulo: String) {
    ENTRENO("Entreno"),
    DIETA("Dieta"),
    CHAT("Chat"),
    REVISION("Revisión"),
    PROGRESO("Progreso");

    val icono: ImageVector
        get() = when (this) {
            ENTRENO -> Iconos.Pesa
            DIETA -> Iconos.Cubiertos
            CHAT -> Iconos.Chat
            REVISION -> Iconos.Checklist
            PROGRESO -> Iconos.Progreso
        }

    /** Para las pruebas y las herramientas que leen la pantalla (`pestana-dieta`). */
    val etiqueta: String get() = "pestana-${name.lowercase()}"
}

/**
 * A dónde se va dentro de la app: la pestaña y, en Revisión, Mis datos (que cuelga de Revisión, como en iOS). Sobrevive a
 * rotar la pantalla. La usan la barra de pestañas, el banner de "te falta tu check" de las otras pestañas y un link con
 * `?scene=` (ACC-09).
 */
class Navegacion(pestana: Pestana = Pestana.ENTRENO, misDatos: Boolean = false) {
    var pestana by mutableStateOf(pestana)
    var misDatos by mutableStateOf(misDatos)

    /** Tocar una pestaña. Tocar Revisión estando en Mis datos vuelve a Revisión (como volver al principio de la pila). */
    fun elegir(p: Pestana) {
        if (p == pestana && p == Pestana.REVISION) misDatos = false
        pestana = p
    }

    /** NOT-03 / ACC-09: train, diet, progress, myday, revision, salud; lo desconocido ya llega como Chat. */
    fun ir(destino: DestinoAviso) {
        when (destino) {
            DestinoAviso.ENTRENO -> pestana = Pestana.ENTRENO
            DestinoAviso.DIETA -> pestana = Pestana.DIETA
            DestinoAviso.CHAT -> pestana = Pestana.CHAT
            DestinoAviso.PROGRESO -> pestana = Pestana.PROGRESO
            DestinoAviso.REVISION, DestinoAviso.MI_DIA -> {
                pestana = Pestana.REVISION
                misDatos = false
            }
            DestinoAviso.MIS_DATOS -> {
                pestana = Pestana.REVISION
                misDatos = true
            }
        }
    }

    companion object {
        val Guardador: Saver<Navegacion, List<Any>> = Saver(
            save = { listOf(it.pestana.name, it.misDatos) },
            restore = { Navegacion(Pestana.valueOf(it[0] as String), it[1] as Boolean) },
        )
    }
}

@Composable
fun rememberNavegacion(): Navegacion = rememberSaveable(saver = Navegacion.Guardador) { Navegacion() }

/** La navegación de la app, para las pantallas que llevan a otra pestaña (el banner de Revisión). */
val LocalNavegacion = staticCompositionLocalOf<Navegacion?> { null }
