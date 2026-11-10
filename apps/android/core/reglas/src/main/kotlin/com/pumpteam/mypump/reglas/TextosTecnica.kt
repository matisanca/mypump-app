package com.pumpteam.mypump.reglas

/**
 * Todo lo que lee el alumno en «Técnica por video», en un solo lugar: para cambiar un texto se cambia acá y en el gemelo
 * `TextosTecnica.swift`, sin tocar lógica (`apps/shared/vectores/tecnica.json` hace fallar las pruebas si difieren). Lista para el
 * OK de Mati en `privado/TEXTOS_PARA_OK.md`.
 */
object TextosTecnica {
    const val entradaEjercicio = "Mandar mi técnica"
    const val entradaMisDatos = "Mi técnica"
    const val avisoBreve = "Mati revisa tu video antes de que te llegue la devolución. El video se borra a los 90 días y lo podés sacar cuando quieras."
    const val avisoBoton = "Entendido, empezar"
    const val consejo = "Apoyá el teléfono a unos 3 metros, a la altura de la cadera. De costado es lo mejor para casi todos los ejercicios. Que entre todo tu cuerpo. Una serie, de hasta 75 segundos. No grabes a otras personas"
    const val notaPregunta = "¿Querés que mire algo en particular?"
    const val botonEnviar = "Enviar a Mati"
    const val subiendo = "Subiendo tu video"
    const val recibido = "Recibido. Mati lo va a mirar y te llega la devolución en 1 a 2 días"
    const val loQueEstaBien = "Lo que está bien"
    const val paraCorregir = "Para corregir"
    const val queSeVe = "Qué se ve"
    const val porQueImporta = "Por qué importa"
    const val comoHacerlo = "Cómo hacerlo"
    const val verEnElVideo = "Ver en el video"
    const val noSePudoVer = "Lo que no se pudo ver"
    const val mandameOtro = "Mandame otro video"
    const val sinCorrecciones = "Mati miró tu serie y no hay nada para corregir. Seguí así"
    const val rechazoCorto = "El video es muy corto. Grabá al menos 2 o 3 repeticiones completas."
    const val rechazoLargo = "El video es muy largo. Mandá una sola serie, de hasta 75 segundos."
    const val rechazoPesado = "El video pesa demasiado. Probá con uno más corto."
    const val rechazoIlegible = "No pudimos abrir el video. Probá grabarlo de nuevo."
    const val topeSemanal = "Ya mandaste 3 videos esta semana. Vas a poder mandar otro en unos días"
    const val enCurso = "Ya tenés un video en revisión"
    const val agregarVideo = "Grabar o elegir video"
    const val grabarVideo = "Grabar video"
    const val elegirGaleria = "Elegir de la galería"
    const val preparando = "Preparando tu video"
    const val cambiarVideo = "Cambiar video"
    const val enviandoSeguir = "Queda guardado y se envía solo cuando vuelva la señal"
    const val esperandoSenal = "Esperando señal"
    const val cancelarEnvio = "Cancelar envío"
    const val elegirEjercicio = "¿De qué ejercicio?"
    const val sinEjercicios = "Todavía no tenés ejercicios en tu rutina"
    const val sinEnvios = "Todavía no mandaste ningún video"
    const val sacarVideo = "Sacar mi video"
    const val sacarConfirma = "¿Sacar tu video?"
    const val sacarDetalle = "Se borra y no se puede recuperar"
    const val sacarOcupado = "Lo estamos mirando. Probá en un rato"
    const val cerrar = "Cerrar"
    const val cancelar = "Cancelar"
    const val errorGenerico = "No se pudo enviar. Probá de nuevo"
    const val sinSenal = "Se cortó la conexión. Probá de nuevo cuando tengas señal."
    const val noSeGuardo = "No se pudo guardar el video en el teléfono. Probá de nuevo"
    const val errorVideo = "No se pudo abrir el video. Probá de nuevo"
    const val otroRecibido = "Listo"

    fun tituloDevolucion(ejercicio: String) = "Tu técnica en $ejercicio"
    fun revisadoEl(fecha: String) = "Lo revisó Mati el $fecha"
    fun videoListo(segundos: Int) = if (segundos == 1) "Video listo: 1 segundo" else "Video listo: $segundos segundos"

    /** Todos los fijos, para comparar con los vectores. */
    val todos: Map<String, String> = mapOf(
        "entradaEjercicio" to entradaEjercicio,
        "entradaMisDatos" to entradaMisDatos,
        "avisoBreve" to avisoBreve,
        "avisoBoton" to avisoBoton,
        "consejo" to consejo,
        "notaPregunta" to notaPregunta,
        "botonEnviar" to botonEnviar,
        "subiendo" to subiendo,
        "recibido" to recibido,
        "loQueEstaBien" to loQueEstaBien,
        "paraCorregir" to paraCorregir,
        "queSeVe" to queSeVe,
        "porQueImporta" to porQueImporta,
        "comoHacerlo" to comoHacerlo,
        "verEnElVideo" to verEnElVideo,
        "noSePudoVer" to noSePudoVer,
        "mandameOtro" to mandameOtro,
        "sinCorrecciones" to sinCorrecciones,
        "rechazoCorto" to rechazoCorto,
        "rechazoLargo" to rechazoLargo,
        "rechazoPesado" to rechazoPesado,
        "rechazoIlegible" to rechazoIlegible,
        "topeSemanal" to topeSemanal,
        "enCurso" to enCurso,
        "agregarVideo" to agregarVideo,
        "grabarVideo" to grabarVideo,
        "elegirGaleria" to elegirGaleria,
        "preparando" to preparando,
        "cambiarVideo" to cambiarVideo,
        "enviandoSeguir" to enviandoSeguir,
        "esperandoSenal" to esperandoSenal,
        "cancelarEnvio" to cancelarEnvio,
        "elegirEjercicio" to elegirEjercicio,
        "sinEjercicios" to sinEjercicios,
        "sinEnvios" to sinEnvios,
        "sacarVideo" to sacarVideo,
        "sacarConfirma" to sacarConfirma,
        "sacarDetalle" to sacarDetalle,
        "sacarOcupado" to sacarOcupado,
        "cerrar" to cerrar,
        "cancelar" to cancelar,
        "errorGenerico" to errorGenerico,
        "sinSenal" to sinSenal,
        "noSeGuardo" to noSeGuardo,
        "errorVideo" to errorVideo,
        "otroRecibido" to otroRecibido,
    )
}
