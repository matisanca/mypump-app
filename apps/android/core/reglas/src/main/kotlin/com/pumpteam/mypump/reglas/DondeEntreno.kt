package com.pumpteam.mypump.reglas

import java.time.Instant

/**
 * «Mi gimnasio y mi técnica» (simplificar, OK de Mati del 11/11): Tu gimnasio (con «Entreno en casa» adentro) y Mi técnica
 * en una sola pantalla, con un renglón grande al final de Entreno. Cada bloque va con su palanca de siempre
 * (`gimnasio_fotos`, `casa`, `tecnica_video`): acá no hay palancas nuevas. Mismos textos que iOS (`DondeEntreno.swift`,
 * `nativa-evidencia/mi-salud/DECISIONES.md`, iOS simplificar 4).
 */
object DondeEntreno {
    const val TITULO_AMBOS = "Mi gimnasio y mi técnica"
    const val TITULO_GIMNASIO = "Mi gimnasio"
    const val TITULO_TECNICA = "Mi técnica"
    const val BAJADA_AMBOS = "Las fotos de tu gimnasio y los videos de tu técnica"
    const val BAJADA_GIMNASIO = "Las fotos de tu gimnasio o lo que tenés en casa"
    const val BAJADA_TECNICA = "Tus videos y lo que te respondió Mati"

    /** El botón del renglón cuando hay una respuesta nueva: la abre directo. */
    const val VER_RESPUESTA = "Ver lo que te respondió Mati"
    const val VACIO = "Por ahora no hay nada para mostrar acá."

    /** El título del renglón y de la pantalla, según lo que haya. null: no hay ninguno de los dos. */
    fun titulo(gimnasio: Boolean, tecnica: Boolean): String? = when {
        gimnasio && tecnica -> TITULO_AMBOS
        gimnasio -> TITULO_GIMNASIO
        tecnica -> TITULO_TECNICA
        else -> null
    }

    fun bajada(gimnasio: Boolean, tecnica: Boolean): String? = when {
        gimnasio && tecnica -> BAJADA_AMBOS
        gimnasio -> BAJADA_GIMNASIO
        tecnica -> BAJADA_TECNICA
        else -> null
    }

    /** Cuántos días una respuesta de técnica sigue «nueva» en el renglón de Entreno. */
    const val DIAS_RESPUESTA_RECIENTE = 7L

    /**
     * La respuesta de Mati más nueva, publicada en los últimos 7 días. Sin fecha legible no cuenta (la lista la sigue
     * mostrando).
     */
    fun respuestaReciente(envios: List<EnvioTecnica>, ahora: Instant = Instant.now()): EnvioTecnica? =
        envios
            .filter { it.estado == EnvioTecnica.Estado.PUBLICADO && it.devolucion != null }
            .mapNotNull { e -> e.publicadoEn?.let(ReglasGuia::instante)?.let { e to it } }
            .filter { (_, en) -> ahora.isBefore(en.plusSeconds(DIAS_RESPUESTA_RECIENTE * 86_400)) }
            .maxByOrNull { (_, en) -> en }
            ?.first
}
