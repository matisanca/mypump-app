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

/**
 * Las pestañas (GEN-01). Salud (lo que era Progreso) ya no está en la barra (2.1.0, «Salud dentro de Revisión»): se abre
 * desde la tarjeta Recuperación de Revisión y tapa Revisión hasta volver. Ver [barra].
 */
enum class Pestana(val titulo: String) {
    ENTRENO("Entreno"),
    DIETA("Dieta"),
    CHAT("Chat"),
    REVISION("Revisión"),
    SALUD("Salud"),

    /** Solo si el cliente tiene suplementación (`mypump_suplementacion` devolvió una fila). */
    SUPLEMENTACION("Suplementación");

    val icono: ImageVector
        get() = when (this) {
            ENTRENO -> Iconos.Pesa
            DIETA -> Iconos.Cubiertos
            CHAT -> Iconos.Chat
            REVISION -> Iconos.Checklist
            SALUD -> Iconos.Progreso
            SUPLEMENTACION -> Iconos.Pastilla
        }

    /** Para las pruebas y las herramientas que leen la pantalla (`pestana-dieta`). */
    val etiqueta: String get() = "pestana-${name.lowercase()}"

    companion object {
        /**
         * Las de la barra: Entreno · Dieta · [Suplementación] · Chat · Revisión. Salud no está nunca (pedido de Mati del
         * 4-nov: lo principal de Salud es la recuperación y va con la revisión): se abre desde la tarjeta Recuperación de
         * Revisión, y los avisos y links que llevan a Salud siguen llegando ([Navegacion.irASalud]).
         */
        fun barra(conSuplementacion: Boolean): List<Pestana> =
            if (conSuplementacion) listOf(ENTRENO, DIETA, SUPLEMENTACION, CHAT, REVISION) else listOf(ENTRENO, DIETA, CHAT, REVISION)
    }
}

/** Las secciones de Revisión a las que se puede llevar al cliente (los `.id` de `RevisionView.swift`). */
object AnclaRevision {
    const val FOTOS = "fotos"
    const val CHECK = "check"
}

/**
 * Los tres segmentos de Salud (2.1, S1): Recuperación (el score, la salud del reloj o del teléfono y Mi reloj), Fuerza
 * (el volumen por músculo y lo que era Progreso) y Cuerpo (el peso, las fotos y el check de la semana, de solo lectura).
 */
enum class SegmentoSalud(val titulo: String) {
    RECUPERACION("Recuperación"),
    FUERZA("Fuerza"),
    CUERPO("Cuerpo");

    /** Para las pruebas (`segmento-fuerza`). */
    val etiqueta: String get() = "segmento-${name.lowercase()}"
}

/**
 * A dónde se va dentro de la app: la pestaña y, en Revisión, una sección o Mis datos (que cuelga de Revisión, como en
 * iOS). Sobrevive a rotar la pantalla. La usan la barra de pestañas, el banner de "te falta tu check" de las otras
 * pestañas, tocar un aviso y un link con `?scene=` (ACC-09).
 */
class Navegacion(
    pestana: Pestana = Pestana.ENTRENO,
    misDatos: Boolean = false,
    anclaRevision: String? = null,
    segmentoSalud: SegmentoSalud = SegmentoSalud.RECUPERACION,
    guia: Boolean = false,
    guiaEnMisDatos: Boolean = false,
    gimnasio: Boolean = false,
    gimnasioEnMisDatos: Boolean = false,
    tecnicaEnMisDatos: Boolean = false,
    fotosInicio: Boolean = false,
    fotosInicioEnMisDatos: Boolean = false,
) {
    var pestana by mutableStateOf(pestana)
    var misDatos by mutableStateOf(misDatos)

    /** «Tu guía», abierta desde su tarjeta en Entreno (cuelga de Entreno, como Mis datos de Revisión). */
    var guia by mutableStateOf(guia)

    /** «Tu guía», abierta desde la fila «Ver mi guía» de Mis datos (después de la entrega o quitada de Entreno). */
    var guiaEnMisDatos by mutableStateOf(guiaEnMisDatos)

    /** «Tu gimnasio» abierto desde la tarjeta de Entreno. */
    var gimnasio by mutableStateOf(gimnasio)

    /** «Mi gimnasio» abierto desde Mis datos. */
    var gimnasioEnMisDatos by mutableStateOf(gimnasioEnMisDatos)

    /** «Mi técnica» abierto desde Mis datos. */
    var tecnicaEnMisDatos by mutableStateOf(tecnicaEnMisDatos)

    /** «Tus fotos de inicio» abierto desde la tarjeta de Revisión. */
    var fotosInicio by mutableStateOf(fotosInicio)

    /** «Mis fotos de inicio» abierto desde Mis datos. */
    var fotosInicioEnMisDatos by mutableStateOf(fotosInicioEnMisDatos)

    /**
     * Una sección de Revisión a la que desplazarse ([AnclaRevision]: fotos, check), como `anclaRevision` de
     * `Navegacion.swift`. Revisión la consume al llegar.
     */
    var anclaRevision by mutableStateOf(anclaRevision)

    /** Cada «Ocultar» de la tarjeta de la guía suma uno: dispara el aviso «La encontrás en Mis datos» con «Deshacer». */
    var avisoGuiaOculta by mutableStateOf(0)

    /** El segmento de Salud: arranca en Recuperación y queda el último elegido mientras viva la app. */
    var segmentoSalud by mutableStateOf(segmentoSalud)

    /** Cuántas veces se pidió abrir Salud: Salud lo mira para volver a la lista de Fuerza en vez del detalle viejo. */
    var aperturasSalud by mutableStateOf(0)
        private set

    /** Tocar una pestaña. Tocar Revisión estando en Mis datos vuelve a Revisión (como volver al principio de la pila). */
    fun elegir(p: Pestana) {
        if (p == pestana && p == Pestana.REVISION) {
            misDatos = false
            guiaEnMisDatos = false
            gimnasioEnMisDatos = false
            tecnicaEnMisDatos = false
            fotosInicio = false
            fotosInicioEnMisDatos = false
        }
        if (p == pestana && p == Pestana.ENTRENO) {
            guia = false
            gimnasio = false
        }
        pestana = p
    }

    /** NOT-03 / ACC-09: train, diet, progress, myday, revision, salud; lo desconocido ya llega como Chat. */
    fun ir(destino: DestinoAviso) {
        when (destino) {
            DestinoAviso.ENTRENO -> pestana = Pestana.ENTRENO
            DestinoAviso.DIETA -> pestana = Pestana.DIETA
            DestinoAviso.CHAT -> pestana = Pestana.CHAT
            // `progress` (lo que era Progreso): Revisión + Salud → Fuerza.
            DestinoAviso.FUERZA -> irASalud(SegmentoSalud.FUERZA)
            DestinoAviso.REVISION -> irARevision(null)
            // `?scene=myday` y el aviso de Mi Día (ya no existe): Revisión + Salud → Recuperación.
            DestinoAviso.RECUPERACION -> irASalud(SegmentoSalud.RECUPERACION)
            // El aviso de «subí tus fotos de inicio»: Revisión con la pantalla abierta en la pose que falta. Si la sección
            // no está habilitada (o todavía no cargó), se ve Revisión y la pantalla aparece sola cuando llega.
            DestinoAviso.FOTOS_INICIO -> {
                irARevision(null)
                fotosInicio = true
            }
            DestinoAviso.MIS_DATOS -> {
                pestana = Pestana.REVISION
                misDatos = true
                guiaEnMisDatos = false
                gimnasioEnMisDatos = false
                tecnicaEnMisDatos = false
                fotosInicioEnMisDatos = false
            }
        }
    }

    /** A Revisión (fuera de Mis datos) y, si hay [ancla], a esa sección. */
    fun irARevision(ancla: String?) {
        pestana = Pestana.REVISION
        misDatos = false
        guiaEnMisDatos = false
        gimnasioEnMisDatos = false
        tecnicaEnMisDatos = false
        fotosInicio = false
        fotosInicioEnMisDatos = false
        anclaRevision = ancla
    }

    /**
     * A Salud, en ese segmento: Revisión con Salud abierta encima (la barra marca Revisión y Atrás vuelve a Revisión). La
     * usan la tarjeta Recuperación y los avisos y links de fuerza o recuperación.
     */
    fun irASalud(segmento: SegmentoSalud) {
        segmentoSalud = segmento
        // Mis datos quedaba prendido: al volver a Revisión desde la barra caía ahí (revisión, hallazgo 2).
        misDatos = false
        aperturasSalud++
        pestana = Pestana.SALUD
    }

    companion object {
        val Guardador: Saver<Navegacion, List<Any>> = Saver(
            save = { listOf(it.pestana.name, it.misDatos, it.anclaRevision ?: "", it.segmentoSalud.name, it.guia, it.guiaEnMisDatos, it.gimnasio, it.gimnasioEnMisDatos, it.tecnicaEnMisDatos, it.fotosInicio, it.fotosInicioEnMisDatos) },
            restore = {
                Navegacion(
                    Pestana.entries.firstOrNull { p -> p.name == it[0] } ?: Pestana.ENTRENO,
                    it[1] as Boolean,
                    (it.getOrNull(2) as? String)?.ifEmpty { null },
                    SegmentoSalud.entries.firstOrNull { s -> s.name == it.getOrNull(3) } ?: SegmentoSalud.RECUPERACION,
                    it.getOrNull(4) as? Boolean ?: false,
                    it.getOrNull(5) as? Boolean ?: false,
                    it.getOrNull(6) as? Boolean ?: false,
                    it.getOrNull(7) as? Boolean ?: false,
                    it.getOrNull(8) as? Boolean ?: false,
                    it.getOrNull(9) as? Boolean ?: false,
                    it.getOrNull(10) as? Boolean ?: false,
                )
            },
        )
    }
}

@Composable
fun rememberNavegacion(): Navegacion = rememberSaveable(saver = Navegacion.Guardador) { Navegacion() }

/** La navegación de la app, para las pantallas que llevan a otra pestaña (el banner de Revisión). */
val LocalNavegacion = staticCompositionLocalOf<Navegacion?> { null }
