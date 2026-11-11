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
import com.pumpteam.mypump.reglas.MiSalud

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

    /** El aviso de la revisión: con el check guiado prendido y sin enviar abre el paso a paso; si no, Revisión como siempre. */
    const val AVISO = "aviso"

    /** El banner cuando faltan el check y las fotos: con el check guiado va al check; si no, a las fotos como siempre. */
    const val PENDIENTES = "pendientes"
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
    documentosEnMisDatos: Boolean = false,
    miSalud: Boolean = false,
    fotosInicio: Boolean = false,
    fotosInicioEnMisDatos: Boolean = false,
    presion: Boolean = false,
    presionDirecta: Boolean = false,
) {
    private var pestanaElegida by mutableStateOf(pestana)

    /** Al salir de Revisión se olvida el pedido de las fotos de inicio que no se pudo abrir (como el `didSet` de iOS). */
    var pestana: Pestana
        get() = pestanaElegida
        set(valor) {
            pestanaElegida = valor
            if (valor != Pestana.REVISION) fotosInicio = false
        }
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

    /** «Novedades de tu plan» abierto desde Mis datos (no sobrevive a rotar: vuelve a Mis datos). */
    var novedadesEnMisDatos by mutableStateOf(false)
    /** «Documentos» (contrato y consentimiento) abierto desde Mis datos o desde el aviso del contrato pendiente. */
    var documentosEnMisDatos by mutableStateOf(documentosEnMisDatos)
    /**
     * «Mi salud» (2.3.0, pedido de Mati del 11/11): todo lo de salud en una pantalla que cuelga de Revisión (como Mis datos).
     * Ahí viven el próximo control, Estudios y órdenes, Presión y la entrada a la recuperación.
     */
    var miSalud by mutableStateOf(miSalud)

    /** El bloque de Mi salud al que hay que llevar (un aviso, una tarjeta del inicio). Mi salud lo consume al llegar. */
    var anclaMiSalud by mutableStateOf<MiSalud.Bloque?>(null)

    /** Al abrirse, el bloque de Estudios se desplaza hasta la primera tarjeta nueva y lo consume. */
    var enfocarEstudios by mutableStateOf(false)
    /** «Tus fotos de inicio» abierto desde la tarjeta de Revisión. */
    var fotosInicio by mutableStateOf(fotosInicio)

    /** «Mis fotos de inicio» abierto desde Mis datos. */
    var fotosInicioEnMisDatos by mutableStateOf(fotosInicioEnMisDatos)

    /**
     * «Presión arterial», a pantalla completa por encima de las pestañas (desde Mis datos, la tarjeta de arriba o un aviso).
     * Solo se ve si la sección está habilitada. No cambia de pestaña ni toca Entreno.
     */
    var presion by mutableStateOf(presion)
        private set

    /** Abrir directo en lo que toca (la repetición, preparar o la toma de hoy), sin pasar por el inicio. Presión lo consume. */
    var presionDirecta by mutableStateOf(presionDirecta)

    fun abrirPresion(directo: Boolean) {
        presionDirecta = directo
        presion = true
    }

    fun cerrarPresion() {
        presion = false
        presionDirecta = false
    }

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
            novedadesEnMisDatos = false
            documentosEnMisDatos = false
            miSalud = false
            fotosInicio = false
            fotosInicioEnMisDatos = false
        }
        // Tocar Revisión con Salud abierta (desde Mi salud) también vuelve al principio de Revisión.
        if (p == Pestana.REVISION && pestana == Pestana.SALUD) miSalud = false
        if (p == pestana && p == Pestana.ENTRENO) {
            guia = false
            gimnasio = false
        }
        pestana = p
    }

    /** NOT-03 / ACC-09: train, diet, progress, myday, revision, salud; lo desconocido ya llega como Chat. */
    fun ir(destino: DestinoAviso) {
        // Un aviso de otro destino (chat, dieta…) con Presión abierta: se cierra, si no tapaba a donde se fue. Como iOS.
        if (destino != DestinoAviso.PRESION) cerrarPresion()
        when (destino) {
            DestinoAviso.ENTRENO -> pestana = Pestana.ENTRENO
            DestinoAviso.DIETA -> pestana = Pestana.DIETA
            DestinoAviso.CHAT -> pestana = Pestana.CHAT
            // `progress` (lo que era Progreso): Revisión + Salud → Fuerza. No es de salud: no pasa por Mi salud.
            DestinoAviso.FUERZA -> irASalud(SegmentoSalud.FUERZA)
            DestinoAviso.REVISION -> irARevision(AnclaRevision.AVISO)
            // `?scene=myday` y el aviso de Mi Día (ya no existe): Mi salud, en la recuperación (2.3.0; antes Salud directo).
            DestinoAviso.RECUPERACION -> irAMiSalud(MiSalud.Bloque.RECUPERACION)
            // `salud` (el kit lo sigue leyendo como Mis datos): desde la 2.3.0, Mi salud en la recuperación, como la web y iOS.
            DestinoAviso.MIS_DATOS -> irAMiSalud(MiSalud.Bloque.RECUPERACION)
            // El aviso de «subí tus fotos de inicio»: Revisión con la pantalla abierta en la pose que falta. Si la sección
            // no está habilitada (o todavía no cargó), se ve Revisión y la pantalla aparece sola cuando llega.
            DestinoAviso.FOTOS_INICIO -> {
                irARevision(null)
                fotosInicio = true
            }
            // El aviso de un estudio pedido o una orden nueva y `?scene=estudios`: Mi salud, en Estudios (antes Mis datos →
            // Estudios). Si la sección no existe (o no cargó), Mi salud igual se abre: es la caída segura.
            DestinoAviso.ESTUDIOS -> irAEstudios()
            // El aviso de presión: Mi salud en Presión y, si la sección está habilitada, Presión encima, directo en lo
            // pendiente. Al cerrarla queda Mi salud (antes, Entreno).
            DestinoAviso.PRESION -> irAPresion(directo = true)
        }
    }

    private fun irAMisDatos() {
        pestana = Pestana.REVISION
        misDatos = true
        guiaEnMisDatos = false
        gimnasioEnMisDatos = false
        tecnicaEnMisDatos = false
        novedadesEnMisDatos = false
        documentosEnMisDatos = false
        miSalud = false
        anclaMiSalud = null
        enfocarEstudios = false
        fotosInicioEnMisDatos = false
    }

    /** Documentos: Revisión → Mis datos → Documentos (el aviso «Tenés el contrato pendiente de firma»). */
    fun irADocumentos() {
        irAMisDatos()
        documentosEnMisDatos = true
    }

    /**
     * A «Mi salud», en [bloque] si lo hay: Revisión con Mi salud abierta (Atrás vuelve a Revisión). Si el bloque todavía no
     * está (la sección no cargó), Mi salud espera un rato y si no aparece se queda arriba de todo.
     */
    fun irAMiSalud(bloque: MiSalud.Bloque? = null) {
        irARevision(null)
        miSalud = true
        anclaMiSalud = bloque
    }

    /** A «Estudios y órdenes» dentro de Mi salud, en la primera tarjeta nueva (avisos, links, tarjetas del inicio, novedades). */
    fun irAEstudios() {
        irAMiSalud(MiSalud.Bloque.ESTUDIOS)
        enfocarEstudios = true
    }

    /** Al control de salud de Mi salud (la tarjeta del inicio). */
    fun irAControl() = irAMiSalud(MiSalud.Bloque.CONTROL)

    /** A Presión dentro de Mi salud y, encima, la pantalla de Presión ([directo]: en lo que toca). */
    fun irAPresion(directo: Boolean) {
        irAMiSalud(MiSalud.Bloque.PRESION)
        abrirPresion(directo)
    }

    /** A Revisión (fuera de Mis datos) y, si hay [ancla], a esa sección. */
    fun irARevision(ancla: String?) {
        pestana = Pestana.REVISION
        misDatos = false
        guiaEnMisDatos = false
        gimnasioEnMisDatos = false
        tecnicaEnMisDatos = false
        novedadesEnMisDatos = false
        documentosEnMisDatos = false
        miSalud = false
        anclaMiSalud = null
        enfocarEstudios = false
        fotosInicio = false
        fotosInicioEnMisDatos = false
        anclaRevision = ancla
    }

    /**
     * A Salud, en ese segmento: Revisión con Salud abierta encima (la barra marca Revisión y Atrás vuelve a Revisión o, con
     * [desdeMiSalud], a Mi salud). La usan la fila Recuperación de Mi salud, «Tu progreso», el Pump del día y el aviso de
     * fuerza.
     */
    fun irASalud(segmento: SegmentoSalud, desdeMiSalud: Boolean = false) {
        segmentoSalud = segmento
        miSalud = desdeMiSalud
        anclaMiSalud = null
        // Mis datos quedaba prendido: al volver a Revisión desde la barra caía ahí (revisión, hallazgo 2).
        misDatos = false
        aperturasSalud++
        pestana = Pestana.SALUD
    }

    /** Atrás desde Salud: a Mi salud si se abrió desde ahí; si no, a Revisión. */
    fun volverDeSalud() {
        if (miSalud) pestana = Pestana.REVISION else irARevision(null)
    }

    companion object {
        val Guardador: Saver<Navegacion, List<Any>> = Saver(
            save = { listOf(it.pestana.name, it.misDatos, it.anclaRevision ?: "", it.segmentoSalud.name, it.guia, it.guiaEnMisDatos, it.gimnasio, it.gimnasioEnMisDatos, it.tecnicaEnMisDatos, it.documentosEnMisDatos, it.miSalud, it.fotosInicio, it.fotosInicioEnMisDatos, it.presion, it.presionDirecta) },
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
                    it.getOrNull(11) as? Boolean ?: false,
                    it.getOrNull(12) as? Boolean ?: false,
                    it.getOrNull(13) as? Boolean ?: false,
                    it.getOrNull(14) as? Boolean ?: false,
                )
            },
        )
    }
}

@Composable
fun rememberNavegacion(): Navegacion = rememberSaveable(saver = Navegacion.Guardador) { Navegacion() }

/** La navegación de la app, para las pantallas que llevan a otra pestaña (el banner de Revisión). */
val LocalNavegacion = staticCompositionLocalOf<Navegacion?> { null }
