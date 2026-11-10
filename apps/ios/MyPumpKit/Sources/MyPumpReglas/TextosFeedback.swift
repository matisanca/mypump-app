import Foundation

/// Los textos de «Feedback del alumno» (2.3.0), todos pendientes del OK de Mati (`TEXTOS_PARA_OK.md`, «Feedback del alumno»).
/// Voz de Mati en primera persona. Sin dos puntos, sin guiones y sin emojis. Los mismos en Android y en la web.
public enum TextosFeedback {
    // «Me duele»
    public static let dueleBoton = "Me duele"
    public static let dueleTitulo = "Me duele"
    public static let dueleIntro = "Contame dónde y cómo, y te cambio el ejercicio."
    public static let dueleDonde = "¿Dónde te duele?"
    public static let dueleDondeAyuda = "Tocá la zona en el dibujo."
    public static let dueleFrente = "Frente"
    public static let dueleEspalda = "Espalda"
    public static let dueleLado = "¿De qué lado?"
    public static let dueleLadoDerecho = "Derecho"
    public static let dueleLadoIzquierdo = "Izquierdo"
    public static let dueleLadoAmbos = "Los dos"
    public static let dueleDesde = "¿Desde cuándo?"
    public static let dueleCuando = "¿En qué parte del movimiento?"
    public static let dueleTipo = "¿Cómo es?"
    public static let dueleCuanto = "¿Cuánto te duele?"
    public static let dueleNota = "Algo más que quieras contarme"
    public static let dueleEnviar = "Avisarle a Mati"
    public static let dueleCorregir = "Guardar cambios"
    public static let dueleFalta = "Completá lo que falta para avisarme."
    public static let dueleListoTitulo = "Ya me llegó"
    public static let dueleListo = "Lo veo y te ajusto el ejercicio."
    public static let dueleListoFuerte = "Por hoy dejá este ejercicio y seguí con el resto."
    public static let dueleAvisada = "Molestia avisada"
    public static let dueleResuelta = "Ya lo revisé"
    public static let dueleCambiar = "Cambiar"
    public static let dueleSinRed = "No se pudo enviar. Revisá la conexión y probá de nuevo."
    public static let dueleTope = "Hoy ya me avisaste varias veces. Si es urgente, escribime por el chat."
    public static let dueleError = "No se pudo enviar. Probá de nuevo en un rato."
    public static let cerrar = "Cerrar"
    public static let listo = "Listo"

    // «Lo compré / lo estoy tomando»
    public static let supleTitulo = "¿Ya lo tenés?"
    public static let supleAyuda = "Marcalo una sola vez. Si algo cambia, lo actualizás acá."
    public static let supleMarcar = "Marcar"
    public static let supleNoConsigoAviso = "Te escribo con opciones que se consigan donde vivís."
    public static let supleError = "No se pudo guardar. Probá de nuevo."
}
