package com.pumpteam.mypump.reglas

/**
 * Todo lo que lee el alumno en «Gimnasio por fotos», en un solo lugar: para cambiar un texto se cambia acá y en el gemelo
 * `TextosGimnasio.swift`, sin tocar lógica (`apps/shared/vectores/gimnasio.json` hace fallar las pruebas si difieren). Lista
 * para el OK de Mati en `privado/TEXTOS_PARA_OK.md`.
 */
object TextosGimnasio {
    const val tarjetaTitulo = "Tu gimnasio"
    const val entradaMisDatos = "Mi gimnasio"
    const val confirmarTarjeta = "Confirmanos qué de esto hay en tu gimnasio"
    const val inicioBajada = "Sacale fotos a lo que hay y adaptamos tu plan a tus máquinas"
    const val botonReintentar = "Probar de nuevo"
    const val consejoPermiso = "Si tu gimnasio no deja, pedí permiso o sacalas en un horario tranquilo"
    const val noHay = "No hay en mi gimnasio"
    const val noHayCorto = "No hay"
    const val sinFotos = "Sin fotos"
    const val opcional = "Opcional"
    const val consejoCamara = "La máquina entera, de costado. Si hay alguien, esperá a que se vaya: no sacamos fotos con gente"
    const val agregarFoto = "Sacar o elegir foto"
    const val borrarFoto = "Borrar foto"
    const val subiendo = "Subiendo…"
    const val esperandoSenal = "Esperando señal"
    const val revisarYEnviar = "Revisar y enviar"
    const val tope = "Llegaste al máximo de 80 fotos"
    const val fotoRechazada = "Una foto no se pudo usar. Sacala de nuevo"
    const val noSeGuardo = "No se pudo guardar la foto en el teléfono. Probá de nuevo"
    const val sinSenal = "Se cortó la conexión. Probá de nuevo cuando tengas señal."
    fun cuentaFotos(n: Int) = if (n == 1) "1 foto" else "$n fotos"
    const val revisarTitulo = "Revisar y enviar"
    const val notaPlaceholder = "Algo que no se vea en las fotos"
    const val botonEnviar = "Enviar a Mati"
    fun faltanZonas(n: Int) = if (n == 1) "Te falta 1 zona" else "Te faltan $n zonas"
    fun subiendoFotos(hechas: Int, total: Int) = "Subiendo tus fotos: $hechas de $total"
    const val enviandoSeguir = "Queda guardado y se envía solo cuando vuelva la señal"
    const val sinNovedad = "Sumá una foto o marcá algo que ya no esté"
    const val errorGenerico = "No se pudo enviar. Probá de nuevo"
    const val recibido = "Recibido. Mati lo está viendo. Te avisamos por WhatsApp"
    fun adaptadoPorMati(fecha: String) = "Adaptado por Mati el $fecha"
    const val sinCambios = "Mati revisó tu gimnasio y tu rutina encaja tal cual"
    fun necesitamosFotos(n: Int) = if (n == 1) "Necesitamos 1 foto más" else "Necesitamos $n fotos más"
    fun preguntaDe(i: Int, n: Int) = "Pregunta $i de $n"
    const val anterior = "Anterior"
    const val siguiente = "Siguiente"
    const val noSe = "No sé"
    const val si = "Sí"
    const val no = "No"
    const val noPuedoFoto = "No puedo sacarla"
    const val marcarTodas = "Marcá todas las que haya: lo que no marques cuenta como que no está"
    const val elegirKilos = "Kilos"
    const val kilosInvalidos = "Poné un número entre 1 y 400"
    const val faltaAlgo = "Falta algo"
    const val yaNoEsta = "Esto ya no está"
    const val cambieDeGimnasio = "Cambié de gimnasio"
    const val marcarLoQueNoEsta = "Marcá lo que ya no está"
    const val volverAEditar = "Volver a editar"
    const val cerrar = "Cerrar"
    const val listoTeclado = "Listo"
    const val kg = "kg"

    /** Para los vectores: clave → texto. */
    val todos: Map<String, String> = linkedMapOf(
        "tarjetaTitulo" to tarjetaTitulo, "entradaMisDatos" to entradaMisDatos, "confirmarTarjeta" to confirmarTarjeta, "inicioBajada" to inicioBajada, "botonReintentar" to botonReintentar, "consejoPermiso" to consejoPermiso,
        "noHay" to noHay, "noHayCorto" to noHayCorto, "sinFotos" to sinFotos, "opcional" to opcional, "consejoCamara" to consejoCamara,
        "agregarFoto" to agregarFoto, "borrarFoto" to borrarFoto, "subiendo" to subiendo, "esperandoSenal" to esperandoSenal,
        "revisarYEnviar" to revisarYEnviar, "tope" to tope, "fotoRechazada" to fotoRechazada, "noSeGuardo" to noSeGuardo, "sinSenal" to sinSenal,
        "revisarTitulo" to revisarTitulo, "notaPlaceholder" to notaPlaceholder, "botonEnviar" to botonEnviar, "enviandoSeguir" to enviandoSeguir,
        "sinNovedad" to sinNovedad, "errorGenerico" to errorGenerico, "recibido" to recibido, "sinCambios" to sinCambios, "anterior" to anterior,
        "siguiente" to siguiente, "noSe" to noSe, "si" to si, "no" to no, "noPuedoFoto" to noPuedoFoto, "marcarTodas" to marcarTodas,
        "elegirKilos" to elegirKilos, "kilosInvalidos" to kilosInvalidos, "faltaAlgo" to faltaAlgo, "yaNoEsta" to yaNoEsta,
        "cambieDeGimnasio" to cambieDeGimnasio, "marcarLoQueNoEsta" to marcarLoQueNoEsta,
        "volverAEditar" to volverAEditar, "cerrar" to cerrar, "listoTeclado" to listoTeclado, "kg" to kg,
    )
}
