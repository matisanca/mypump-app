package com.pumpteam.mypump.reglas

/**
 * Los textos de «Feedback del alumno» (2.3.0), todos pendientes del OK de Mati (`TEXTOS_PARA_OK.md`, «Feedback del alumno»).
 * Voz de Mati en primera persona. Sin dos puntos, sin guiones y sin emojis. Los mismos que `TextosFeedback.swift` y la web.
 */
object TextosFeedback {
    // «Me duele»
    const val dueleBoton = "Me duele"
    const val dueleTitulo = "Me duele"
    const val dueleIntro = "Contame dónde y cómo, y te cambio el ejercicio."
    const val dueleDonde = "¿Dónde te duele?"
    const val dueleDondeAyuda = "Tocá la zona en el dibujo."
    const val dueleFrente = "Frente"
    const val dueleEspalda = "Espalda"
    const val dueleLado = "¿De qué lado?"
    const val dueleLadoDerecho = "Derecho"
    const val dueleLadoIzquierdo = "Izquierdo"
    const val dueleLadoAmbos = "Los dos"
    const val dueleDesde = "¿Desde cuándo?"
    const val dueleCuando = "¿En qué parte del movimiento?"
    const val dueleTipo = "¿Cómo es?"
    const val dueleCuanto = "¿Cuánto te duele?"
    const val dueleNota = "Algo más que quieras contarme"
    const val dueleEnviar = "Avisarle a Mati"
    const val dueleCorregir = "Guardar cambios"
    const val dueleFalta = "Completá lo que falta para avisarme."
    const val dueleListoTitulo = "Ya me llegó"
    const val dueleListo = "Lo veo y te ajusto el ejercicio."
    const val dueleListoFuerte = "Por hoy dejá este ejercicio y seguí con el resto."
    const val dueleAvisada = "Molestia avisada"
    const val dueleResuelta = "Ya lo revisé"
    const val dueleCambiar = "Cambiar"
    const val dueleSinRed = "No se pudo enviar. Revisá la conexión y probá de nuevo."
    const val dueleTope = "Hoy ya me avisaste varias veces. Si es urgente, escribime por el chat."
    const val dueleError = "No se pudo enviar. Probá de nuevo en un rato."
    const val cerrar = "Cerrar"
    const val listo = "Listo"

    // «Lo compré / lo estoy tomando»
    const val supleTitulo = "¿Ya lo tenés?"
    const val supleAyuda = "Marcalo una sola vez. Si algo cambia, lo actualizás acá."
    const val supleMarcar = "Marcar"
    const val supleNoConsigoAviso = "Te escribo con opciones que se consigan donde vivís."
    const val supleError = "No se pudo guardar. Probá de nuevo."

    /** Todo lo de arriba, para la prueba de lo que no puede aparecer en pantalla. */
    val todos: List<String> = listOf(
        dueleBoton, dueleTitulo, dueleIntro, dueleDonde, dueleDondeAyuda, dueleFrente, dueleEspalda, dueleLado, dueleLadoDerecho, dueleLadoIzquierdo,
        dueleLadoAmbos, dueleDesde, dueleCuando, dueleTipo, dueleCuanto, dueleNota, dueleEnviar, dueleCorregir, dueleFalta, dueleListoTitulo, dueleListo,
        dueleListoFuerte, dueleAvisada, dueleResuelta, dueleCambiar, dueleSinRed, dueleTope, dueleError, cerrar, listo,
        supleTitulo, supleAyuda, supleMarcar, supleNoConsigoAviso, supleError,
    )
}
