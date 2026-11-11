package com.pumpteam.mypump.reglas

/**
 * Todo lo que lee el alumno en «Fotos de inicio», en un solo lugar: para cambiar un texto se cambia acá, en el gemelo
 * `TextosFotosInicio.swift` y en la web, sin tocar lógica (`apps/shared/vectores/fotos_inicio.json` hace fallar las pruebas si
 * difieren). Las fotos son privadas: ningún texto nombra a otra cosa que a Mati.
 */
object TextosFotosInicio {
    // Entrada
    const val tarjetaTitulo = "Tus fotos de inicio"
    const val tarjetaBajada = "Tres fotos para que Mati vea de dónde arrancás"
    const val tarjetaEmpezar = "Empezar"
    const val tarjetaSeguir = "Seguir"
    const val tarjetaLista = "Listas. Mati ya las tiene"
    const val entradaMisDatos = "Mis fotos de inicio"
    const val privacidad = "Las ve solo Mati. No se publican"
    // Consejos
    const val consejosTitulo = "Antes de sacarlas"
    const val consejoLuz = "De frente a una ventana o con la luz prendida. Sin contraluz"
    const val consejoDistancia = "El teléfono a unos 2 metros: tenés que entrar de la cabeza a los pies"
    const val consejoAltura = "La cámara derecha, a la altura del pecho"
    const val consejoRopa = "En short o ropa interior, y con top deportivo si usás"
    const val consejoFondo = "Una pared lisa atrás, sin cosas en el medio"
    const val consejoEspejo = "Mejor sin espejo: apoyá el teléfono o pedile a alguien que te la saque"
    const val consejoTemporizador = "Si estás solo, usá el temporizador de la cámara y después elegí la foto de la galería"
    const val consejoPostura = "Relajado, sin sacar músculo ni meter la panza"
    // Poses
    const val poseFrente = "De frente"
    const val posePerfil = "De perfil"
    const val poseEspalda = "De espalda"
    const val instruccionFrente = "Parate derecho mirando a la cámara, con los brazos un poco separados del cuerpo y los pies al ancho de la cadera"
    const val instruccionPerfil = "De costado a la cámara, mirando al frente y con los brazos al costado del cuerpo"
    const val instruccionEspalda = "De espaldas a la cámara, en la misma postura que de frente"
    const val falta = "Falta"
    const val lista = "Lista"
    const val subiendo = "Subiendo…"
    const val esperandoSenal = "Esperando señal"
    // Sacar y revisar
    const val botonFoto = "Sacar o elegir foto"
    const val botonUsar = "Usar esta foto"
    const val botonUsarIgual = "Usar igual"
    const val botonOtra = "Sacar otra"
    const val seVeBien = "Se ve bien"
    const val problemaChica = "Tiene poca resolución. Sacala de nuevo con la cámara del teléfono"
    const val problemaApaisada = "Salió acostada. Sacala con el teléfono en vertical"
    const val problemaOscura = "Salió oscura. Buscá más luz, de frente a una ventana"
    const val problemaMovida = "Salió movida. Apoyá el teléfono o usá el temporizador"
    fun problemaVieja(dias: Int): String = "Es de hace $dias días. Mati necesita una de esta semana"
    const val ilegible = "No se pudo leer esa foto. Probá con otra"
    const val fotoRechazada = "Una foto no se pudo usar. Sacala de nuevo"
    const val noSeGuardo = "No se pudo guardar la foto en el teléfono. Probá de nuevo"
    const val sinSenal = "Sin señal: queda guardada y se sube sola"
    // Resumen
    fun cuenta(n: Int): String = "$n de 3"
    fun faltan(n: Int): String = if (n == 1) "Te falta 1 foto" else "Te faltan $n fotos"
    const val listoTitulo = "Listo, Mati ya tiene tus fotos"
    const val listoBajada = "Si querés repetir alguna, tocala"
    const val repetir = "Repetir"
    // El físico que te motiva
    const val motivacionTitulo = "El físico que te motiva"
    const val opcional = "Opcional"
    const val motivacionBajada = "Si hay un físico al que te gustaría acercarte, sumá una o más fotos y contale a Mati qué te gusta"
    const val motivacionAgregar = "Agregar foto"
    const val motivacionNota = "Qué te gusta de ese físico"
    const val motivacionGuardar = "Guardar nota"
    const val motivacionGuardada = "Nota guardada"
    const val motivacionTope = "Hasta 4 fotos"
    const val borrarFoto = "Borrar foto"
    const val notaSinSenal = "Sin señal: la nota queda guardada y se manda sola"
    const val notaError = "No se pudo guardar la nota. Probá de nuevo"
    const val borrarSinSenal = "Sin señal: no se pudo borrar. Probá de nuevo"
    // Botones
    const val cerrar = "Cerrar"
    const val siguiente = "Siguiente"
    const val listoBoton = "Listo"
    const val listoTeclado = "Listo"

    /** Para los vectores: clave → texto. */
    val todos: Map<String, String> = linkedMapOf(
        "tarjetaTitulo" to tarjetaTitulo,
        "tarjetaBajada" to tarjetaBajada,
        "tarjetaEmpezar" to tarjetaEmpezar,
        "tarjetaSeguir" to tarjetaSeguir,
        "tarjetaLista" to tarjetaLista,
        "entradaMisDatos" to entradaMisDatos,
        "privacidad" to privacidad,
        "consejosTitulo" to consejosTitulo,
        "consejoLuz" to consejoLuz,
        "consejoDistancia" to consejoDistancia,
        "consejoAltura" to consejoAltura,
        "consejoRopa" to consejoRopa,
        "consejoFondo" to consejoFondo,
        "consejoEspejo" to consejoEspejo,
        "consejoTemporizador" to consejoTemporizador,
        "consejoPostura" to consejoPostura,
        "poseFrente" to poseFrente,
        "posePerfil" to posePerfil,
        "poseEspalda" to poseEspalda,
        "instruccionFrente" to instruccionFrente,
        "instruccionPerfil" to instruccionPerfil,
        "instruccionEspalda" to instruccionEspalda,
        "falta" to falta,
        "lista" to lista,
        "subiendo" to subiendo,
        "esperandoSenal" to esperandoSenal,
        "botonFoto" to botonFoto,
        "botonUsar" to botonUsar,
        "botonUsarIgual" to botonUsarIgual,
        "botonOtra" to botonOtra,
        "seVeBien" to seVeBien,
        "problemaChica" to problemaChica,
        "problemaApaisada" to problemaApaisada,
        "problemaOscura" to problemaOscura,
        "problemaMovida" to problemaMovida,
        "ilegible" to ilegible,
        "fotoRechazada" to fotoRechazada,
        "noSeGuardo" to noSeGuardo,
        "sinSenal" to sinSenal,
        "listoTitulo" to listoTitulo,
        "listoBajada" to listoBajada,
        "repetir" to repetir,
        "motivacionTitulo" to motivacionTitulo,
        "opcional" to opcional,
        "motivacionBajada" to motivacionBajada,
        "motivacionAgregar" to motivacionAgregar,
        "motivacionNota" to motivacionNota,
        "motivacionGuardar" to motivacionGuardar,
        "motivacionGuardada" to motivacionGuardada,
        "motivacionTope" to motivacionTope,
        "borrarFoto" to borrarFoto,
        "notaSinSenal" to notaSinSenal,
        "notaError" to notaError,
        "borrarSinSenal" to borrarSinSenal,
        "cerrar" to cerrar,
        "siguiente" to siguiente,
        "listoBoton" to listoBoton,
        "listoTeclado" to listoTeclado,
    )
}
