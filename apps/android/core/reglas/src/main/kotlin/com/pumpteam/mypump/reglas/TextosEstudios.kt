package com.pumpteam.mypump.reglas

/**
 * Todo lo que lee el alumno en «Estudios y órdenes», en un solo lugar y tal cual `estudios/CONTRATO_APP.md` (los mismos
 * textos en iPhone, Android y web). Para cambiar un texto se cambia acá y en los gemelos, sin tocar lógica. Sin valores,
 * rangos ni interpretación: acá no hay nada clínico.
 */
object TextosEstudios {
    const val entrada = "Estudios y órdenes"
    const val todoAlDia = "Todo al día"
    fun subtitulo(pendientes: Int): String = when {
        pendientes <= 0 -> todoAlDia
        pendientes == 1 -> "Te falta 1 estudio"
        else -> "Te faltan $pendientes estudios"
    }

    const val titulo = "Estudios"
    const val proximoControl = "Próximo control"
    fun semanaDel(dia: String) = "Semana del $dia"
    fun entreElYEl(desde: String, hasta: String) = "Entre el $desde y el $hasta"

    const val teFaltaHacer = "Te falta hacer"
    fun antesDel(dia: String) = "Antes del $dia"
    fun eraParaEl(dia: String) = "Era para el $dia"
    const val subirResultado = "Subir resultado"
    const val yaMeLoHice = "Ya me lo hice"
    const val verOrden = "Ver orden"
    fun hechoEl(dia: String) = "Hecho el $dia. Falta subir el resultado."
    const val hechoSinFecha = "Hecho. Falta subir el resultado."
    const val deshacer = "Deshacer"

    const val cuandoTeLoHiciste = "¿Cuándo te lo hiciste?"
    const val guardar = "Guardar"
    const val revisaLaFecha = "Revisá la fecha."

    const val subirUnEstudio = "Subir un estudio"
    const val guiaSubida = "Subí todas las hojas juntas, en PDF o en fotos donde se lea bien."
    const val sacarFotos = "Sacar fotos"
    const val elegirFotos = "Elegir fotos"
    const val elegirPdf = "Elegir PDF"
    const val quitar = "Quitar"
    fun enviarArchivos(n: Int) = if (n == 1) "Enviar 1 archivo" else "Enviar $n archivos"
    fun topeArchivos(n: Int) = "Hasta $n archivos por envío."
    fun pesaDeMas(mb: Int) = "Ese archivo pesa más de $mb MB."
    fun subiendo(va: Int, total: Int) = "Subiendo $va de $total"
    const val sinSenal = "Sin señal. Se envía solo cuando vuelva."
    const val recibidoAviso = "Recibido. Mati lo revisa y te escribe."
    const val topeDia = "Ya mandaste varios envíos hoy. Probá mañana o escribile a Mati."
    const val archivoRechazado = "No pudimos leer ese archivo. Probá con una foto o un PDF."

    const val tusOrdenes = "Tus órdenes"
    fun emitidaEl(dia: String) = "Emitida el $dia"
    fun valeHasta(dia: String) = "Vale hasta el $dia"
    const val ordenVencida = "Vencida. Si la necesitás, pedísela a Mati por el chat."
    const val comoPrepararte = "Cómo prepararte"
    const val dondeHacerlo = "Dónde hacerlo"
    const val noSePudoAbrir = "No se pudo abrir. Probá de nuevo."

    const val tusEstudios = "Tus estudios"
    const val sinFecha = "Sin fecha"
    fun hojas(n: Int) = if (n == 1) "1 hoja" else "$n hojas"
    fun archivos(n: Int) = if (n == 1) "1 archivo" else "$n archivos"
    const val recibido = "Recibido"
    const val matiLoVio = "Mati lo vio"
    fun envioDel(dia: String) = "Envío del $dia"
    const val envio = "Envío"
    const val ver = "Ver"
    const val notaFija = "Recibido quiere decir que llegó. Mati lo revisa y te escribe. Si te sentís mal, no esperes: escribile o consultá a un médico."
    const val vacio = "Acá vas a ver los estudios que te pida Mati, tus órdenes y lo que nos mandes."
    const val errorDeCarga = "No se pudo cargar. Deslizá para reintentar."

    // Lo que no está en el contrato porque no se lee: solo lo dice el lector de pantalla o nombra un archivo de la hoja.
    fun fotoN(n: Int) = "Foto $n"
    fun pdfN(n: Int) = "PDF $n"
    fun paginaDe(n: Int, total: Int) = "Página $n de $total"
    const val cancelar = "Cancelar"
    const val probarDeNuevo = "Probar de nuevo"
    /** Fuera del contrato: «Ya me lo hice», «Deshacer» o «Enviar» no se pudieron guardar (sin señal o falla del servidor). */
    const val noSePudoGuardar = "No se pudo guardar. Probá de nuevo."
    const val diaAnterior = "Un día antes"
    const val diaSiguiente = "Un día después"
    const val tituloSinNombre = "Estudio"

    // ── Cómo prepararte y dónde hacerlo (por `tipo`) ──

    private val laboratorio = listOf(
        "Ayuno de 8 a 12 horas. Podés tomar agua, y andá bien hidratado.",
        "Extracción entre las 7 y las 10 de la mañana.",
        "48 horas antes: sin entrenar y sin alcohol.",
        "3 días antes: sin biotina (viene en suplementos para pelo y uñas y en algunos multivitamínicos).",
        "Si te piden orina, la primera de la mañana.",
        "Si estás enfermo o pasaste la noche sin dormir, mejor pasalo a otro día.",
    )
    private val ecografia = listOf("Si es abdominal, ayuno de 6 a 8 horas.", "Para otras ecografías, seguí lo que te indique el centro al sacar el turno.")
    private val sinPreparacion = listOf("No necesita preparación.")
    private val esfuerzo = listOf("Comida liviana 2 horas antes.", "Ese día, sin café, mate ni tabaco.", "Llevá ropa y zapatillas para hacer ejercicio.")
    private val mapa = listOf(
        "Elegí un día común de semana.", "En cada toma, dejá el brazo quieto y relajado.", "Anotá lo que vas haciendo: comidas, entreno y sueño.",
        "Con el aparato puesto no te podés duchar.",
    )
    private val otro = listOf("Seguí lo que te indique el centro al sacar el turno.")
    const val avisoCorazon = "Si tenés dolor de pecho, falta de aire o palpitaciones, avisale a Mati antes de hacerlo."
    val siempre = listOf("Si Mati te dio una indicación propia, vale esa.", "No dejes ninguna medicación sin que Mati te lo diga.")
    private val delCorazon = setOf("ecocardiograma", "electrocardiograma", "ergometria", "eco_estres", "mapa")

    /** Los renglones de «Cómo prepararte», en orden: los del tipo, el aviso del corazón si toca y los dos de siempre. */
    fun preparacion(tipo: String?): List<String> {
        val propios = when (tipo) {
            "laboratorio" -> laboratorio
            "ecografia" -> ecografia
            "ecocardiograma", "electrocardiograma" -> sinPreparacion
            "ergometria", "eco_estres" -> esfuerzo
            "mapa" -> mapa
            else -> otro
        }
        return propios + (if (tipo in delCorazon) listOf(avisoCorazon) else emptyList()) + siempre
    }

    private val dondeLaboratorio = listOf(
        "En cualquier laboratorio de análisis clínicos. Si tenés obra social o prepaga, en uno de tu cartilla: llevá la orden, tu credencial y tu DNI.",
        "Si podés, siempre en el mismo laboratorio: así los resultados se comparan mejor.",
    )
    private val dondeLosDemas = listOf(
        "En un centro de diagnóstico o de cardiología, con turno. Si tenés obra social o prepaga, en uno de tu cartilla: llevá la orden, tu credencial y tu DNI.",
    )

    fun donde(tipo: String?): List<String> = if (tipo == "laboratorio") dondeLaboratorio else dondeLosDemas
}
