import Foundation

/// Todo lo que lee el alumno en «Técnica por video», en un solo lugar: para cambiar un texto se cambia acá y en el gemelo
/// `TextosTecnica.kt`, sin tocar lógica (`apps/shared/vectores/tecnica.json` hace fallar las pruebas si difieren).
/// Lista para el OK de Mati en `privado/TEXTOS_PARA_OK.md`.
public enum TextosTecnica {
    public static let entradaEjercicio = "Mandar mi técnica"
    public static let entradaMisDatos = "Mi técnica"
    public static let avisoBreve = "Mati revisa tu video antes de que te llegue la devolución. El video se borra a los 90 días y lo podés sacar cuando quieras."
    public static let avisoBoton = "Entendido, empezar"
    public static let consejo = "Apoyá el teléfono a unos 3 metros, a la altura de la cadera. De costado es lo mejor para casi todos los ejercicios. Que entre todo tu cuerpo. Una serie, de hasta 75 segundos. No grabes a otras personas"
    public static let notaPregunta = "¿Querés que mire algo en particular?"
    public static let botonEnviar = "Enviar a Mati"
    public static let subiendo = "Subiendo tu video"
    public static let recibido = "Recibido. Mati lo va a mirar y te llega la devolución en 1 a 2 días"
    public static func tituloDevolucion(_ ejercicio: String) -> String { "Tu técnica en \(ejercicio)" }
    public static func revisadoEl(_ fecha: String) -> String { "Lo revisó Mati el \(fecha)" }
    public static let loQueEstaBien = "Lo que está bien"
    public static let paraCorregir = "Para corregir"
    public static let queSeVe = "Qué se ve"
    public static let porQueImporta = "Por qué importa"
    public static let comoHacerlo = "Cómo hacerlo"
    public static let verEnElVideo = "Ver en el video"
    public static let noSePudoVer = "Lo que no se pudo ver"
    public static let mandameOtro = "Mandame otro video"
    public static let sinCorrecciones = "Mati miró tu serie y no hay nada para corregir. Seguí así"
    public static let rechazoCorto = "El video es muy corto. Grabá al menos 2 o 3 repeticiones completas."
    public static let rechazoLargo = "El video es muy largo. Mandá una sola serie, de hasta 75 segundos."
    public static let rechazoPesado = "El video pesa demasiado. Probá con uno más corto."
    public static let rechazoIlegible = "No pudimos abrir el video. Probá grabarlo de nuevo."
    public static let topeSemanal = "Ya mandaste 3 videos esta semana. Vas a poder mandar otro en unos días"
    public static let enCurso = "Ya tenés un video en revisión"
    // Sumados en la obra de las apps (también en TEXTOS_PARA_OK.md).
    public static let agregarVideo = "Grabar o elegir video"
    public static let grabarVideo = "Grabar video"
    public static let elegirGaleria = "Elegir de la galería"
    public static let preparando = "Preparando tu video"
    public static func videoListo(_ segundos: Int) -> String { segundos == 1 ? "Video listo: 1 segundo" : "Video listo: \(segundos) segundos" }
    public static let cambiarVideo = "Cambiar video"
    public static let enviandoSeguir = "Queda guardado y se envía solo cuando vuelva la señal"
    public static let esperandoSenal = "Esperando señal"
    public static let cancelarEnvio = "Cancelar envío"
    public static let elegirEjercicio = "¿De qué ejercicio?"
    public static let sinEjercicios = "Todavía no tenés ejercicios en tu rutina"
    public static let sinEnvios = "Todavía no mandaste ningún video"
    public static let sacarVideo = "Sacar mi video"
    public static let sacarConfirma = "¿Sacar tu video?"
    public static let sacarDetalle = "Se borra y no se puede recuperar"
    public static let sacarOcupado = "Lo estamos mirando. Probá en un rato"
    public static let cerrar = "Cerrar"
    public static let cancelar = "Cancelar"
    public static let errorGenerico = "No se pudo enviar. Probá de nuevo"
    public static let sinSenal = "Se cortó la conexión. Probá de nuevo cuando tengas señal."
    public static let noSeGuardo = "No se pudo guardar el video en el teléfono. Probá de nuevo"
    public static let errorVideo = "No se pudo abrir el video. Probá de nuevo"
    public static let otroRecibido = "Listo"

    /// Todos los fijos, para comparar con los vectores.
    public static let todos: [String: String] = [
        "entradaEjercicio": entradaEjercicio, "entradaMisDatos": entradaMisDatos, "avisoBreve": avisoBreve, "avisoBoton": avisoBoton, "consejo": consejo,
        "notaPregunta": notaPregunta, "botonEnviar": botonEnviar, "subiendo": subiendo, "recibido": recibido, "loQueEstaBien": loQueEstaBien, "paraCorregir": paraCorregir,
        "queSeVe": queSeVe, "porQueImporta": porQueImporta, "comoHacerlo": comoHacerlo, "verEnElVideo": verEnElVideo, "noSePudoVer": noSePudoVer, "mandameOtro": mandameOtro,
        "sinCorrecciones": sinCorrecciones, "rechazoCorto": rechazoCorto, "rechazoLargo": rechazoLargo, "rechazoPesado": rechazoPesado, "rechazoIlegible": rechazoIlegible,
        "topeSemanal": topeSemanal, "enCurso": enCurso, "agregarVideo": agregarVideo, "grabarVideo": grabarVideo, "elegirGaleria": elegirGaleria, "preparando": preparando,
        "cambiarVideo": cambiarVideo, "enviandoSeguir": enviandoSeguir, "esperandoSenal": esperandoSenal, "cancelarEnvio": cancelarEnvio, "elegirEjercicio": elegirEjercicio,
        "sinEjercicios": sinEjercicios, "sinEnvios": sinEnvios, "sacarVideo": sacarVideo, "sacarConfirma": sacarConfirma, "sacarDetalle": sacarDetalle, "sacarOcupado": sacarOcupado,
        "cerrar": cerrar, "cancelar": cancelar, "errorGenerico": errorGenerico, "sinSenal": sinSenal, "noSeGuardo": noSeGuardo, "errorVideo": errorVideo, "otroRecibido": otroRecibido,
    ]
}
