package com.pumpteam.mypump.reglas

import com.pumpteam.mypump.modelos.ClipGuia
import com.pumpteam.mypump.modelos.Guia
import com.pumpteam.mypump.modelos.ItemSuplemento
import com.pumpteam.mypump.modelos.ResumenGuia
import com.pumpteam.mypump.modelos.Suplementacion
import java.time.Instant
import java.time.LocalDate
import java.time.OffsetDateTime
import java.time.ZoneId
import java.time.format.TextStyle
import java.util.Locale
import kotlin.math.roundToInt

/**
 * Las reglas de «Tu guía», portadas de la web (`pack.html`) para que las dos se vean y se comporten igual: los capítulos,
 * el avance, el motivo partido, la suplementación por momento del día y los textos que arma la app. Sin Android: se prueban
 * en la JVM.
 */
object ReglasGuia {
    /** Los textos de las dudas: de 1 a 1000 caracteres (lo mismo que acepta el servidor). */
    const val MAX_DUDA = 1000

    /** Las dudas para la videollamada: hasta 30, compartidas con la web. */
    const val TOPE_DUDAS_LLAMADA = 30

    private val ZONA = ZoneId.of("America/Argentina/Buenos_Aires")
    private val ES = Locale.forLanguageTag("es-AR")

    /** Un capítulo: su nombre tal cual viene y los índices de sus clips (en la lista de [ordenados]). */
    data class Bloque(val titulo: String, val indices: List<Int>, val minutos: Double) {
        /** «8 videos, unos 4 minutos», como la web. */
        val resumen: String get() = "${cantidadVideos(indices.size)}, unos ${minutosRedondos(minutos)} minutos"
    }

    /** El botón del video de un suplemento, como pack.html: «Ver por qué (18 s)» (al menos 1 s). */
    fun rotuloPorQue(minutos: Double): String = "Ver por qué (" + maxOf(1L, Math.round(minutos * 60)) + " s)"

    fun esTuApp(bloque: String?): Boolean = bloque?.trim()?.equals("tu app", ignoreCase = true) == true

    /**
     * Los clips en el orden en que se muestran: los de «Tu app» primero (como la web) y el resto en el orden del servidor.
     * Todo lo demás (siguiente, anterior, «Video N de M») usa este orden.
     */
    fun ordenados(clips: List<ClipGuia>): List<ClipGuia> = clips.filter { esTuApp(it.bloque) } + clips.filterNot { esTuApp(it.bloque) }

    /** Agrupa por bloque respetando el orden de aparición. Un clip sin bloque va en «Videos». */
    fun bloques(ordenados: List<ClipGuia>): List<Bloque> {
        val porTitulo = LinkedHashMap<String, MutableList<Int>>()
        ordenados.forEachIndexed { i, c -> porTitulo.getOrPut(c.bloque ?: "Videos") { mutableListOf() } += i }
        return porTitulo.map { (t, idx) -> Bloque(t, idx, idx.sumOf { ordenados[it].minutos }) }
    }

    /** `Math.max(1, Math.round(m))` de la web. */
    fun minutosRedondos(m: Double): Int = maxOf(1, Math.round(m).toInt())

    private fun cantidadVideos(n: Int): String = if (n == 1) "1 video" else "$n videos"

    /** La duración de la fila, `m:ss` (0.7 → «0:42»). */
    fun duracion(minutos: Double): String {
        val s = (minutos * 60).roundToInt().coerceAtLeast(0)
        return "${s / 60}:${(s % 60).toString().padStart(2, '0')}"
    }

    /** Lo mismo para TalkBack: «42 segundos», «1 minuto 48 segundos». */
    fun duracionHablada(minutos: Double): String {
        val s = (minutos * 60).roundToInt().coerceAtLeast(0)
        val m = s / 60
        val r = s % 60
        val partes = buildList {
            if (m > 0) add(if (m == 1) "1 minuto" else "$m minutos")
            if (r > 0 || m == 0) add(if (r == 1) "1 segundo" else "$r segundos")
        }
        return partes.joinToString(" ")
    }

    /** «Viste 4 de 13, te quedan unos 12 minutos» (la cabecera, como la web). */
    fun textoAvance(r: ResumenGuia): String =
        if (r.vistos >= r.total) "Viste todos, nos vemos en la videollamada"
        else "Viste ${r.vistos} de ${r.total}, te quedan unos ${minutosRedondos(r.minutosRestantes)} minutos"

    /** «4 de 13 videos, te quedan 12 min» (la tarjeta de inicio, propuesta de la espec). */
    fun textoTarjeta(r: ResumenGuia): String =
        if (r.vistos >= r.total) "Viste los ${r.total} videos"
        else "${r.vistos} de ${r.total} videos, te quedan ${minutosRedondos(r.minutosRestantes)} min"

    /** La fracción vista, para la barra. */
    fun fraccion(r: ResumenGuia): Float = if (r.total <= 0) 0f else r.vistos.toFloat() / r.total

    /**
     * El motivo puede traer «qué hacer ||| para qué» (3/11). Devuelve (qué hacer, para qué), cada uno null si está vacío. Sin
     * separador, todo es el para qué.
     */
    fun partesMotivo(motivo: String?): Pair<String?, String?> {
        val m = motivo ?: return null to null
        val i = m.indexOf("|||")
        if (i < 0) return null to m.trim().ifEmpty { null }
        return m.substring(0, i).trim().ifEmpty { null } to m.substring(i + 3).trim().ifEmpty { null }
    }

    /** Ya pasó la videollamada (`yaPaso` de la web): cambian los textos («me llega y te contesto»). */
    fun yaPaso(fechaEntrega: String?, ahora: Instant = Instant.now()): Boolean {
        val f = fechaEntrega?.trim()?.ifEmpty { null } ?: return false
        if (f.length > 10) return instante(f)?.isBefore(ahora) ?: false
        val dia = try {
            LocalDate.parse(f.take(10))
        } catch (_: Exception) {
            return false
        }
        return dia.isBefore(ahora.atZone(ZONA).toLocalDate())
    }

    // ── Después de la entrega (`entregas_014`, decisión de Mati del 4/11) ──

    /** Lo que se ve de la guía fuera de la sección: la tarjeta en Entreno, la fila «Ver mi guía» en Mis datos o nada. */
    enum class Lugar { ENTRENO, MIS_DATOS, NINGUNO }

    /** La acción discreta al pie de la sección. */
    enum class AccionEntreno { QUITAR, VOLVER_A_MOSTRAR, NINGUNA }

    /** Las horas después de la videollamada en que la tarjeta sigue en Entreno (exactas, como el servidor). */
    const val HORAS_TARJETA = 48L

    /**
     * `mostrar_tarjeta` del resumen. Si no vino (vuelta atrás a la 012), la misma cuenta del servidor con `fecha_entrega`:
     * sin fecha, o antes de fecha + 48 h exactas. Una fecha que no se entiende muestra la tarjeta (lo de siempre).
     */
    fun mostrarTarjeta(r: ResumenGuia, ahora: Instant = Instant.now()): Boolean = r.mostrarTarjeta ?: dentroDelPlazo(r.fechaEntrega, ahora)

    internal fun dentroDelPlazo(fechaEntrega: String?, ahora: Instant): Boolean {
        val f = fechaEntrega?.trim()?.ifEmpty { null } ?: return true
        val desde = if (f.length > 10) instante(f) else try {
            LocalDate.parse(f.take(10)).atStartOfDay(ZONA).toInstant()
        } catch (_: Exception) {
            null
        }
        desde ?: return true
        return ahora.isBefore(desde.plusSeconds(HORAS_TARJETA * 3600))
    }

    /**
     * Dónde queda la guía. Sin resumen (`ok: false`, sin guía) no hay tarjeta ni fila. Con la tarjeta oculta a mano o pasado
     * el plazo, la fila de Mis datos.
     */
    fun lugar(r: ResumenGuia?, ocultaAMano: Boolean, ahora: Instant = Instant.now()): Lugar = when {
        r == null -> Lugar.NINGUNO
        !ocultaAMano && mostrarTarjeta(r, ahora) -> Lugar.ENTRENO
        else -> Lugar.MIS_DATOS
    }

    /** «Quitar de Entreno» mientras la tarjeta está; «Volver a mostrar en Entreno» solo si el plazo todavía no pasó. */
    fun accionEntreno(r: ResumenGuia?, ocultaAMano: Boolean, ahora: Instant = Instant.now()): AccionEntreno = when {
        r == null || !mostrarTarjeta(r, ahora) -> AccionEntreno.NINGUNA
        ocultaAMano -> AccionEntreno.VOLVER_A_MOSTRAR
        else -> AccionEntreno.QUITAR
    }

    private fun instante(iso: String): Instant? = try {
        OffsetDateTime.parse(iso).toInstant()
    } catch (_: Exception) {
        try {
            Instant.parse(iso)
        } catch (_: Exception) {
            null
        }
    }

    /** «miércoles 6/11», en la hora de Argentina como la web. null si no hay fecha o no se entiende. */
    fun fechaCorta(fechaEntrega: String?): String? {
        val f = fechaEntrega?.trim()?.ifEmpty { null } ?: return null
        val dia = if (f.length > 10) instante(f)?.atZone(ZONA)?.toLocalDate() else try {
            LocalDate.parse(f.take(10))
        } catch (_: Exception) {
            null
        }
        dia ?: return null
        return "${dia.dayOfWeek.getDisplayName(TextStyle.FULL, ES).lowercase(ES)} ${dia.dayOfMonth}/${dia.monthValue}"
    }

    /** La línea de la cabecera, debajo de «Hola Marcelo». */
    fun lineaCabecera(g: Guia, ahora: Instant = Instant.now()): String {
        if (yaPaso(g.fechaEntrega, ahora)) return "Te dejo estos videos según lo que hablamos en la videollamada. Miralos con calma."
        val cuando = fechaCorta(g.fechaEntrega)
        return "Armé estos videos para vos" + (cuando?.let { ", antes de nuestra videollamada del $it" } ?: "") +
            ", según lo que me contaste."
    }

    fun saludo(g: Guia): String = g.nombrePila?.let { "Hola $it" } ?: "Hola"

    /** La duda tal como se manda: sin espacios en los bordes; null si queda vacía o pasa el tope. */
    fun dudaValida(texto: String): String? = texto.trim().takeIf { it.isNotEmpty() && it.length <= MAX_DUDA }
}

/**
 * El reproductor de la guía sin la vista: qué video arranca, siguiente y anterior (salteando los que todavía no se pueden
 * ver), desde dónde retoma y la velocidad. La vista (Media3) solo ejecuta.
 */
object ReglasReproductor {
    /** La placa de «Otro tema» dura 2,6 s (como la web). */
    const val PLACA_MS = 2_600L

    /** Al pasar este punto se marca visto. */
    const val UMBRAL_VISTO = 0.8

    /** Cada cuántos segundos de reproducción se guarda el avance. */
    const val CADA_SEGUNDOS = 10.0

    val VELOCIDADES = listOf(1f, 1.25f, 1.5f)

    /** El primero sin ver que se pueda ver; si están todos vistos, el primero que se pueda ver. -1 si ninguno. */
    fun indiceInicial(clips: List<ClipGuia>): Int {
        val i = clips.indexOfFirst { !it.visto && it.sePuedeVer }
        return if (i >= 0) i else clips.indexOfFirst { it.sePuedeVer }
    }

    fun siguiente(clips: List<ClipGuia>, actual: Int): Int? = ((actual + 1) until clips.size).firstOrNull { clips[it].sePuedeVer }

    fun anterior(clips: List<ClipGuia>, actual: Int): Int? = (minOf(actual, clips.size) - 1 downTo 0).firstOrNull { clips[it].sePuedeVer }

    /**
     * Desde dónde arranca (espec 4.6): retoma desde `segundos` si el video no está visto y quedó entre el segundo 5 y 5
     * segundos antes del final. Si no, desde el principio. Sin la duración (todavía no se sabe) no retoma.
     */
    fun retomarDesde(clip: ClipGuia, duracionSegundos: Double): Double {
        if (clip.visto || !(duracionSegundos > 0)) return 0.0
        val s = clip.segundos.toDouble()
        return if (s > 5 && s < duracionSegundos - 5) s else 0.0
    }

    /** 1x → 1,25x → 1,5x → 1x. */
    fun velocidadSiguiente(v: Float): Float {
        val i = VELOCIDADES.indexOfFirst { kotlin.math.abs(it - v) < 0.01f }
        return VELOCIDADES[(i + 1).mod(VELOCIDADES.size)]
    }

    /** «1x», «1,25x», «1,5x». */
    fun textoVelocidad(v: Float): String = NumeroCorto.texto(v.toDouble()).replace('.', ',') + "x"

    /** «Otro tema · Video 3 de 20». */
    fun textoPlaca(indice: Int, total: Int): String = "Otro tema · Video ${indice + 1} de $total"

    /** «Video 3 de 20 · Tu app», arriba del título en el reproductor. */
    fun textoNumero(indice: Int, total: Int, bloque: String?): String = "Video ${indice + 1} de $total" + (bloque?.let { " · $it" } ?: "")

    private object NumeroCorto {
        fun texto(d: Double): String = if (d == Math.floor(d)) d.toLong().toString() else d.toString().trimEnd('0')
    }
}

/**
 * Cuándo se guarda el avance de UN video (espec 4.7): cada 10 s de reproducción, al pasar el 80 % (con visto) y al terminar.
 * La vista le pasa la posición cada tanto ([alAvanzar]) y el fin ([alTerminar]); lo que devuelve es lo que hay que mandar.
 *
 * - «10 s de reproducción» es tiempo reproducido, no la posición: saltar adelante o atrás no cuenta (un salto de más de 3 s
 *   entre dos lecturas es un salto, no reproducción).
 * - `visto` va en TODOS los guardados después de marcarlo: la cola deduplica el avance de un video (gana el último) y un
 *   guardado posterior sin visto no puede tapar el que lo marcó.
 * - `segundos` es el mayor alcanzado (el servidor también se queda con el mayor): volver atrás no lo achica.
 */
class SeguimientoAvance(private val clip: ClipGuia) {
    data class Guardado(val video: String, val segundos: Int, val visto: Boolean)

    var visto: Boolean = clip.visto
        private set
    private var maximo: Double = clip.segundos.toDouble()
    private var ultimaPosicion: Double? = null
    private var reproducido = 0.0

    /** Los segundos del último [Guardado] (o lo que ya tenía el servidor): [alCortar] solo guarda si se pasó de acá. */
    private var ultimoGuardado: Int = clip.segundos

    /** Una lectura de la posición mientras el video corre. */
    fun alAvanzar(posicion: Double, duracion: Double): Guardado? {
        if (!posicion.isFinite() || posicion < 0) return null
        val antes = ultimaPosicion
        ultimaPosicion = posicion
        if (antes != null) {
            val delta = posicion - antes
            if (delta > 0 && delta <= MAX_DELTA) reproducido += delta
        }
        if (posicion > maximo) maximo = posicion
        if (duracion > 0 && !visto && posicion / duracion >= ReglasReproductor.UMBRAL_VISTO) {
            visto = true
            reproducido = 0.0
            return guardado(posicion)
        }
        if (reproducido >= ReglasReproductor.CADA_SEGUNDOS) {
            reproducido = 0.0
            return guardado(posicion)
        }
        return null
    }

    /** Se buscó otra posición: la próxima lectura no suma reproducción desde la anterior. */
    fun alInterrumpir() {
        ultimaPosicion = null
    }

    /**
     * El video dejó de correr (pausa, otro video, se cerró «Ver por qué», la app se fue atrás) en [posicion]: el último
     * tramo (hasta 10 s que todavía no se guardaron) se guarda si el máximo subió desde el último [Guardado].
     */
    fun alCortar(posicion: Double?): Guardado? {
        if (posicion != null && posicion.isFinite() && posicion > maximo) maximo = posicion
        ultimaPosicion = null
        reproducido = 0.0
        return if (maximo.roundToInt().coerceIn(0, MAX_SEGUNDOS) > ultimoGuardado) guardado(maximo) else null
    }

    /** Terminó: se guarda con visto y el final. */
    fun alTerminar(duracion: Double): Guardado {
        visto = true
        if (duracion.isFinite() && duracion > maximo) maximo = duracion
        reproducido = 0.0
        return guardado(maximo)
    }

    private fun guardado(posicion: Double): Guardado {
        val s = maxOf(posicion, maximo).roundToInt().coerceIn(0, MAX_SEGUNDOS)
        ultimoGuardado = maxOf(ultimoGuardado, s)
        return Guardado(clip.id, s, visto)
    }

    companion object {
        /** El servidor acepta de 0 a 36000. */
        const val MAX_SEGUNDOS = 36_000

        /** Entre dos lecturas (cada ~0,5 s, a 1,5x) no corren más de 3 s: más es un salto. */
        private const val MAX_DELTA = 3.0

        /**
         * Dos avances del mismo video que se juntan en la cola (gana el último): el mayor de los segundos y visto si alguno
         * lo tenía, así lo que quedó sin mandar nunca se pierde.
         */
        fun fusionar(previo: Guardado?, nuevo: Guardado): Guardado =
            if (previo == null || previo.video != nuevo.video) nuevo
            else Guardado(nuevo.video, maxOf(previo.segundos, nuevo.segundos), previo.visto || nuevo.visto)
    }
}

/**
 * «Tu suplementación» como «Tu día» del PDF (`bloqueSuple` de la web): un grupo por momento del día con el nombre y la
 * cantidad, la nota debajo, y el «por qué», el detalle y el «Ver por qué» solo la primera vez que aparece cada ítem.
 */
object SuplementacionVista {
    data class Fila(
        val nombre: String,
        val cantidad: String?,
        val nota: String?,
        val nuevo: Boolean,
        val opcional: Boolean,
        /** Solo en la primera aparición del ítem. */
        val porQue: String?,
        val detalle: List<String>,
        val videoId: String?,
        /** El ítem entero (la pestaña Suplementación lo usa para la etiqueta, los días y el detalle). */
        val item: ItemSuplemento,
    )

    data class Momento(val id: String, val titulo: String, val filas: List<Fila>)

    data class Sale(val nombre: String, val porQue: String?, val detalle: List<String>, val item: ItemSuplemento)

    data class Vista(val titulo: String, val accion: String?, val momentos: List<Momento>, val sigue: String?, val sale: List<Sale>)

    /** Los momentos con nombre propio de la web (`MOMENTOS`), en su orden. */
    val MOMENTOS: List<Pair<String, String>> = listOf(
        "despertar" to "Al despertar", "ayunas" to "En ayunas", "desayuno" to "Desayuno", "media_manana" to "Media mañana",
        "almuerzo" to "Almuerzo", "merienda" to "Merienda", "pre" to "Antes de entrenar", "intra" to "Mientras entrenás",
        "post" to "Después de entrenar", "cena" to "Cena", "dormir" to "Antes de dormir", "noche" to "Si te despertás de noche",
    )

    private const val ADEMAS = "__ademas__"

    fun armar(s: Suplementacion): Vista {
        val porMomento = LinkedHashMap<String, MutableList<Pair<ItemSuplemento, TomaVista>>>()
        val sueltos = mutableListOf<Pair<ItemSuplemento, TomaVista>>()
        val sale = mutableListOf<ItemSuplemento>()
        for (it in s.items) {
            if (it.estado == "sale") {
                sale += it
                continue
            }
            val tomas = if (it.tomas.isNotEmpty()) it.tomas.map { t -> TomaVista(t.momento, t.cantidad, t.nota, t.nombre) }
            else it.momento?.let { m -> listOf(TomaVista(m, it.cantidad, it.nota, null)) }
            if (tomas == null) {
                sueltos += it to TomaVista(ADEMAS, it.cantidad, it.nota, null)
                continue
            }
            for (t in tomas) porMomento.getOrPut(t.momento) { mutableListOf() } += it to t
        }
        // El orden: los de `dia`, después los conocidos que falten en su orden, después cualquier otro.
        val orden = s.dia.map { it.id }.toMutableList()
        MOMENTOS.forEach { (m, _) -> if (m in porMomento && m !in orden) orden += m }
        porMomento.keys.forEach { if (it !in orden) orden += it }
        if (s.dia.isEmpty()) {
            fun pos(m: String): Int = MOMENTOS.indexOfFirst { it.first == m }.let { if (it < 0) 99 else it }
            orden.sortBy(::pos)
        }
        val vistos = HashSet<ItemSuplemento>()
        fun fila(par: Pair<ItemSuplemento, TomaVista>): Fila {
            val (it, t) = par
            val primera = vistos.add(it)
            return Fila(
                nombre = t.nombre ?: it.nombre,
                cantidad = t.cantidad,
                nota = mayuscula(t.nota),
                nuevo = it.estado == "nuevo",
                opcional = it.opcional,
                porQue = if (primera) it.porQue else null,
                detalle = if (primera) it.detalle else emptyList(),
                videoId = if (primera) it.videoId else null,
                item = it,
            )
        }
        val momentos = orden.filter { it in porMomento }.map { m ->
            Momento(m, tituloMomento(m, s), porMomento.getValue(m).map(::fila))
        }.toMutableList()
        if (sueltos.isNotEmpty()) momentos += Momento(ADEMAS, "Además", sueltos.map(::fila))
        return Vista(
            titulo = s.titulo ?: "Tu suplementación",
            accion = s.accion,
            momentos = momentos,
            sigue = s.sigueTexto,
            sale = sale.map { Sale(it.nombre, it.porQue, it.detalle, it) },
        )
    }

    /** El nombre de un momento: el de `dia[]` si lo trae, si no el propio de la app, si no el id legible. */
    fun tituloMomento(id: String, s: Suplementacion): String =
        s.dia.lastOrNull { it.id == id }?.nombre ?: MOMENTOS.firstOrNull { it.first == id }?.second ?: mayuscula(id.replace('_', ' ')) ?: id

    private data class TomaVista(val momento: String, val cantidad: String?, val nota: String?, val nombre: String?)

    private fun mayuscula(x: String?): String? {
        val t = x?.trim()?.ifEmpty { null } ?: return null
        return t.substring(0, 1).uppercase() + t.substring(1)
    }

    /** Los tramos de un texto con *negrita* de Markdown: (texto, negrita). */
    fun tramos(x: String): List<Pair<String, Boolean>> {
        val r = mutableListOf<Pair<String, Boolean>>()
        val patron = Regex("\\*([^*]+)\\*")
        var desde = 0
        for (m in patron.findAll(x)) {
            if (m.range.first > desde) r += x.substring(desde, m.range.first) to false
            r += m.groupValues[1] to true
            desde = m.range.last + 1
        }
        if (desde < x.length) r += x.substring(desde) to false
        return r
    }
}
