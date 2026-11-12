package com.pumpteam.mypump.reglas

import com.pumpteam.mypump.modelos.AgendaEntrega
import com.pumpteam.mypump.modelos.CambioAgenda
import com.pumpteam.mypump.modelos.ClipGuia
import com.pumpteam.mypump.modelos.FranjaEntrega
import com.pumpteam.mypump.modelos.Guia
import com.pumpteam.mypump.modelos.ReservaEntrega
import com.pumpteam.mypump.modelos.ResumenGuia
import com.pumpteam.mypump.modelos.TipoVideollamada
import java.time.DayOfWeek
import java.time.Duration
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.temporal.ChronoUnit
import java.util.Locale

/**
 * La novedad de «Tu guía» (fase 2, 2.2.0): los clips de la última tanda (`nuevo`) van arriba en «Novedad», la tarjeta de
 * Entreno pasa a «NOVEDAD EN TU GUÍA» y vuelve si el cliente la había ocultado antes de `novedad_en`. Sin `novedad_en` ni
 * clips nuevos, todo queda como en la 2.1.0.
 */
object ReglasNovedad {
    /** La clave del bloque «Novedad» en la lista (los capítulos abiertos y la clave de la fila). */
    const val CLAVE_NOVEDAD = "__novedad__"

    const val TITULO = "Novedad"

    /**
     * El orden de la lista y del reproductor: los nuevos arriba, en el orden del servidor, y debajo los de siempre
     * ([ReglasGuia.ordenados]). Sin nuevos es exactamente [ReglasGuia.ordenados].
     */
    fun ordenDeLaLista(clipsDeLaLista: List<ClipGuia>): List<ClipGuia> {
        val (nuevos, resto) = clipsDeLaLista.partition { it.nuevo }
        return nuevos + ReglasGuia.ordenados(resto)
    }

    /** Como arriba, con los videos de «Lo que más te importa» y sus partes antes que los demás, si hay `dolor`. */
    fun ordenDeLaLista(g: Guia): List<ClipGuia> {
        val (nuevos, resto) = g.clipsDeLaLista.partition { it.nuevo }
        return nuevos + ReglasDolor.conDolorPrimero(ReglasGuia.ordenados(resto), g.dolor)
    }

    /**
     * Los capítulos sobre [ordenados] (de [ordenDeLaLista]): primero «Novedad» con los nuevos y después los de siempre solo
     * con los que no son nuevos (lo ya visto queda abajo). Sin nuevos, [ReglasGuia.bloques].
     */
    fun bloques(ordenados: List<ClipGuia>): List<ReglasGuia.Bloque> {
        val n = ordenados.takeWhile { it.nuevo }.size
        if (n == 0) return ReglasGuia.bloques(ordenados)
        val novedad = ReglasGuia.Bloque(TITULO, (0 until n).toList(), ordenados.take(n).sumOf { it.minutos }, esNovedad = true)
        return listOf(novedad) + ReglasGuia.bloques(ordenados.drop(n)).map { b -> b.copy(indices = b.indices.map { it + n }) }
    }

    /** «3 videos nuevos para vos · 9 min». */
    fun textoNovedad(n: Int, minutos: Double): String =
        (if (n == 1) "1 video nuevo para vos" else "$n videos nuevos para vos") + " · ${ReglasGuia.minutosRedondos(minutos)} min"

    /**
     * Lo que muestra la tarjeta de Entreno con novedad. [total] null: la guía guardada es de antes de la tanda (otro
     * `novedad_en`) y todavía no se sabe cuáles son los nuevos.
     */
    data class Tarjeta(val total: Int?, val vistos: Int, val minutosRestantes: Double?) {
        val fraccion: Float get() = if (total == null || total <= 0) 0f else vistos.toFloat() / total
    }

    /**
     * La tarjeta con novedad: con `novedad_en` en el resumen y algún nuevo sin ver. Los nuevos salen de la guía en memoria
     * o guardada si es de la misma tanda; si no lo es (o nunca se abrió), se muestra la novedad mientras quede algo sin ver
     * en el resumen. null: la tarjeta de la 2.1.0.
     */
    fun tarjeta(r: ResumenGuia, g: Guia?): Tarjeta? {
        val en = r.novedadEn ?: return null
        // Lo del servidor (`nuevos_total` y `nuevos_vistos`, opcionales) o, si no vino, lo que se sepa en el teléfono.
        val delServidor = r.nuevosTotal?.takeIf { it > 0 }?.let { it to (r.nuevosVistos ?: 0).coerceIn(0, it) }
        if (g != null && g.novedadEn == en && g.nuevos.isNotEmpty()) {
            val nuevos = g.nuevos
            // Lo visto en el teléfono que todavía no salió gana; lo del servidor, si ya sabe más.
            val vistos = maxOf(nuevos.count { it.visto }, delServidor?.takeIf { it.first == nuevos.size }?.second ?: 0)
            if (vistos >= nuevos.size) return null
            val resta = nuevos.filter { !it.visto }.sumOf { it.minutos }
            return Tarjeta(nuevos.size, vistos, Math.round(resta * 10) / 10.0)
        }
        if (delServidor != null) {
            val (total, vistos) = delServidor
            return if (vistos >= total) null else Tarjeta(total, vistos, null)
        }
        return if (r.vistos < r.total) Tarjeta(null, 0, null) else null
    }

    fun textoTarjeta(t: Tarjeta): String {
        val total = t.total ?: return "Hay videos nuevos para vos"
        val min = t.minutosRestantes?.let { ReglasGuia.minutosRedondos(it) }
        return if (t.vistos == 0) (if (total == 1) "1 video nuevo para vos" else "$total videos nuevos para vos") + (min?.let { " · $it min" } ?: "")
        else "${t.vistos} de $total videos nuevos" + (min?.let { ", " + ReglasGuia.teQuedanMin(it) } ?: "")
    }

    const val BOTON = "Ver lo nuevo"

    /**
     * La tarjeta ocultada a mano vuelve si `novedad_en` es posterior a la marca. Una marca sin fecha (la de la 2.1.0) es de
     * antes de cualquier novedad. Una fecha que no se entiende no cambia nada.
     */
    fun reaparece(novedadEn: String?, ocultaEn: String?): Boolean {
        val n = AgendaEntrega.instante(novedadEn) ?: return false
        val o = ocultaEn?.let(AgendaEntrega::instante) ?: return true
        return n.isAfter(o)
    }

    /** Lo que vale para [ReglasGuia.lugar]: la marca, salvo que la novedad la haga volver. */
    fun ocultaEfectiva(ocultaAMano: Boolean, ocultaEn: String?, novedadEn: String?): Boolean =
        ocultaAMano && !reaparece(novedadEn, ocultaEn)
}

/**
 * Los videos obligatorios y la agenda de la entrega al final de «Tu guía» (2.2.0). El servidor decide si se puede agendar y
 * qué franjas hay; esto solo cuenta, ordena y arma los textos (en la zona del teléfono).
 */
object ReglasAgenda {
    val ARGENTINA: ZoneId = ZoneId.of("America/Argentina/Buenos_Aires")

    /** De lunes a viernes, como las franjas del servidor (`agenda_lib.huecos`, `weekday < 5`). */
    fun esHabil(d: LocalDate): Boolean = d.dayOfWeek != DayOfWeek.SATURDAY && d.dayOfWeek != DayOfWeek.SUNDAY

    /** El [n]-ésimo día hábil después de [desde] (n = 1: el próximo). */
    fun diaHabil(desde: LocalDate, n: Int): LocalDate {
        var d = desde
        var k = 0
        while (k < maxOf(n, 1)) {
            d = d.plusDays(1)
            if (esHabil(d)) k++
        }
        return d
    }

    /** Cuántos días hábiles hay después de [a] hasta [b] inclusive (0 si [b] no es posterior). */
    internal fun habilesEntre(a: LocalDate, b: LocalDate): Int {
        var d = a
        var k = 0
        while (d.isBefore(b)) {
            d = d.plusDays(1)
            if (esHabil(d)) k++
        }
        return k
    }

    /**
     * Las franjas de la demo (`demo/agenda.json`) corridas para que la primera caiga el próximo día hábil después de [hoy],
     * con la misma hora de Argentina y los mismos días hábiles de diferencia entre sí: nunca un sábado ni un domingo.
     */
    fun correrADiasHabiles(franjas: List<FranjaEntrega>, hoy: LocalDate): List<FranjaEntrega> {
        val base = franjas.minOfOrNull { it.inicio }?.atZone(ARGENTINA)?.toLocalDate() ?: return franjas
        return franjas.map { f ->
            val dia = f.inicio.atZone(ARGENTINA).toLocalDate()
            val dias = ChronoUnit.DAYS.between(dia, diaHabil(hoy, 1 + habilesEntre(base, dia)))
            // Argentina no cambia de hora: correr días enteros deja la misma hora.
            f.copy(inicio = f.inicio.plus(Duration.ofDays(dias)), fin = f.fin.plus(Duration.ofDays(dias)))
        }
    }
    private val ES = Locale.forLanguageTag("es-AR")
    private val DIA = DateTimeFormatter.ofPattern("EEEE d 'de' MMMM", ES)
    private val DIA_CORTO = DateTimeFormatter.ofPattern("EEEE d", ES)
    private val HORA = DateTimeFormatter.ofPattern("HH:mm", ES)

    /** La etiqueta discreta de los que cuentan (todos la misma: la marca de los datos no se muestra). */
    const val ETIQUETA = "Para ver antes de la videollamada"

    /**
     * Los que cuentan para habilitar la agenda, siempre de la lista ([Guia.clipsDeLaLista]: sin los de «Tu suplementación»
     * que muestra su suplemento, el mismo filtro del resumen y del servidor): los que traen `obligatorio: true`. Si
     * **ningún** clip trae el campo (servidor viejo), todos los de la lista que se pueden ver.
     */
    fun obligatorios(g: Guia): List<ClipGuia> =
        if (g.clips.any { it.obligatorio != null }) g.clipsDeLaLista.filter { it.obligatorio == true }
        else g.clipsDeLaLista.filter { it.sePuedeVer }

    /** Los obligatorios sin ver, contados en el teléfono (`visto` ya incluye la tilde manual). Ver [faltanAMostrar]. */
    fun faltan(g: Guia): Int = obligatorios(g).count { !it.visto }

    /**
     * El número que se muestra: el `faltan` de `entregas_app_agenda` si vino (el servidor cuenta con su filtro); el del
     * teléfono solo de respaldo (sin respuesta de la agenda o un servidor viejo).
     */
    fun faltanAMostrar(a: AgendaEntrega?, g: Guia?): Int = when {
        a == null -> g?.let(::faltan) ?: 0
        a.faltan != null -> a.faltan!!
        // Habilitada sin `faltan`: no hay nada que contar (puede no exigir los obligatorios, spec §7).
        a.habilitada -> 0
        else -> g?.let(::faltan) ?: 0
    }

    /** El primer obligatorio sin ver que se puede ver, en el orden en que se muestran ([orden]). */
    fun proximoQueFalta(g: Guia, orden: List<ClipGuia>): ClipGuia? {
        val ids = obligatorios(g).filter { !it.visto && it.sePuedeVer }.map { it.id }.toSet()
        return orden.firstOrNull { it.id in ids }
    }

    fun textoContador(n: Int): String =
        if (n == 1) "Te falta 1 video para habilitar la agenda" else "Te faltan $n videos para habilitar la agenda"

    fun textoBloqueada(n: Int): String =
        "Cuando termines los videos de arriba se habilita la agenda." + if (n > 0) " Te faltan $n." else ""

    /** Con `autorizada: false` (Mati todavía no dio el OK de horarios). */
    const val TEXTO_NO_AUTORIZADA = "Cuando termines de ver todo te habilitamos la agenda."

    const val TEXTO_PENDIENTE = "Estamos reservando tu horario…"
    const val TEXTO_SIN_FRANJAS = "Ahora no hay horarios libres. Mirá de nuevo más tarde o escribinos por el chat."
    const val TEXTO_CAMBIAR = "¿Necesitás cambiarla? Escribinos por el chat."
    const val TEXTO_DEMO = "En la demo no se crea ninguna videollamada"
    const val TEXTO_HORARIO_TELEFONO = "Horario de tu teléfono"
    const val TEXTO_TOMADA = "Ese horario se ocupó recién, elegí otro."

    /** El cambio ya no se puede desde la app (`tope` o `plazo` de `entregas_app_cambiar`). */
    const val TEXTO_SIN_CAMBIO = "Ese cambio ya no se puede hacer desde la app. Escribinos por el chat."

    /** Lo que se ve al final de la guía. */
    enum class Vista {
        /** `autorizada: false`: «Cuando termines de ver todo te habilitamos la agenda.». */
        NO_AUTORIZADA,

        /** Autorizada y con obligatorios sin ver: la tarjeta gris con candado. */
        BLOQUEADA,

        /** Vio todo en el teléfono, pero el servidor todavía no lo sabe (el avance está saliendo). */
        HABILITANDO,
        ELEGIR,
        SIN_FRANJAS,
        PENDIENTE,
        CONFIRMADA,
    }

    /**
     * [faltan]: lo del teléfono (la guía en memoria) si se sabe; si no, lo del servidor. [reservando]: la reserva salió del
     * teléfono y no volvió la respuesta.
     */
    fun vista(a: AgendaEntrega, faltan: Int, reservando: Boolean): Vista = when {
        a.reserva?.estado == ReservaEntrega.Estado.CONFIRMADA -> Vista.CONFIRMADA
        reservando || a.reserva?.estado == ReservaEntrega.Estado.PENDIENTE -> Vista.PENDIENTE
        // Lo que diga el servidor (spec §7): habilitada manda, aunque queden videos sin ver.
        a.habilitada -> if (a.franjas.isEmpty()) Vista.SIN_FRANJAS else Vista.ELEGIR
        !a.autorizada -> Vista.NO_AUTORIZADA
        faltan > 0 -> Vista.BLOQUEADA
        else -> Vista.HABILITANDO
    }

    // ── Textos editables (spec §7: `textos` de `entregas_app_agenda`) ──

    /** Claves de la 2.2.0 con otro sentido (la sala, el aviso de Entreno): ya no se usan, va el texto propio. */
    val CLAVES_VIEJAS = setOf("hoy_sin_sala", "sala_abierta", "entreno_aviso")

    /** Palabras que no van en los textos al alumno: un texto del servidor que las tenga se descarta. */
    private val PROHIBIDAS = Regex("entrega|whatsapp|coach|entrenador", RegexOption.IGNORE_CASE)

    /**
     * El texto de [clave]: el del servidor si vino y no está vacío, con `{hora}`, `{dia}`, `{duracion}` y `{faltan}`
     * reemplazados; si no, [propio]. Una clave que la app no usa se ignora; las [CLAVES_VIEJAS] y un texto con «entrega»,
     * «WhatsApp», «coach» o «entrenador» también.
     */
    fun texto(
        a: AgendaEntrega?,
        clave: String,
        propio: String,
        hora: String? = null,
        dia: String? = null,
        duracion: String? = null,
        faltan: Int? = null,
    ): String {
        if (clave in CLAVES_VIEJAS) return propio
        val t = a?.textos?.get(clave)?.trim()?.ifEmpty { null }?.takeUnless { PROHIBIDAS.containsMatchIn(it) } ?: return propio
        return t.replace("{hora}", hora.orEmpty())
            .replace("{dia}", dia.orEmpty())
            .replace("{duracion}", duracion.orEmpty())
            .replace("{faltan}", faltan?.toString().orEmpty())
            .replace(Regex(" {2,}"), " ")
            .trim()
    }

    /** «Agendá tu videollamada de comienzo». El `titulo` del servidor no pisa el de una revisión. */
    fun textoTitulo(a: AgendaEntrega?): String {
        val propio = "Agendá tu ${nombre(a?.tipo ?: TipoVideollamada.COMIENZO)}"
        return if (a?.tipo == TipoVideollamada.REVISION) propio else texto(a, "titulo", propio)
    }

    /** La duración común de las franjas («alrededor de 1 hora»), o null si no todas duran lo mismo. */
    fun duracionComun(franjas: List<FranjaEntrega>): String? =
        franjas.map { duracion(it.inicio, it.fin) }.distinct().singleOrNull()

    /** El encabezado de las franjas: «Elegí el horario que mejor te quede. Dura alrededor de 1 hora.» */
    fun textoEncabezado(a: AgendaEntrega?, franjas: List<FranjaEntrega>): String {
        val d = duracionComun(franjas)
        return texto(a, "encabezado", "Elegí el horario que mejor te quede." + (d?.let { " Dura $it." } ?: ""), duracion = d)
    }

    /** El aviso arriba de las franjas después de un fallo: `tomada` (o la franja que ya no está), o cualquier otro. */
    fun avisoFallo(motivo: String?): String = when (motivo) {
        "tomada", "franja" -> TEXTO_TOMADA
        "tope", "plazo" -> TEXTO_SIN_CAMBIO
        else -> "No pudimos reservar ese horario, elegí otro."
    }

    // ── Fechas, siempre en la zona del teléfono ──

    /** «jueves 12 de noviembre». */
    fun dia(i: Instant, zona: ZoneId): String = DIA.format(i.atZone(zona))

    /** «jueves 12». */
    fun diaCorto(i: Instant, zona: ZoneId): String = DIA_CORTO.format(i.atZone(zona))

    fun hora(i: Instant, zona: ZoneId): String = HORA.format(i.atZone(zona))

    /** «10:00 a 12:00». */
    fun rango(inicio: Instant, fin: Instant, zona: ZoneId): String = "${hora(inicio, zona)} a ${hora(fin, zona)}"

    /** Las franjas agrupadas por día del teléfono, en orden: («jueves 12 de noviembre», franjas). */
    fun porDia(franjas: List<FranjaEntrega>, zona: ZoneId): List<Pair<String, List<FranjaEntrega>>> =
        franjas.sortedBy { it.inicio }.groupBy { it.inicio.atZone(zona).toLocalDate() }.map { (_, l) -> dia(l.first().inicio, zona) to l }

    /** La hora del teléfono no es la de Argentina en alguno de esos momentos: se agrega «Horario de tu teléfono». */
    fun difiereDeArgentina(zona: ZoneId, instantes: List<Instant>): Boolean =
        instantes.any { zona.rules.getOffset(it) != ARGENTINA.rules.getOffset(it) }

    /**
     * «¿Confirmás tu videollamada de comienzo el jueves 12 a las 10:00? Dura alrededor de 1 hora.» Si el teléfono está en
     * otra zona, también la hora de Argentina. La duración sale de la franja (fin − inicio): los horarios y la duración
     * cambian solo con datos.
     */
    fun textoConfirmar(f: FranjaEntrega, zona: ZoneId, a: AgendaEntrega? = null): String {
        val dura = textoDuracion(f.inicio, f.fin)?.let { " $it." } ?: ""
        val ar = if (difiereDeArgentina(zona, listOf(f.inicio))) " (${hora(f.inicio, ARGENTINA)} en Argentina)" else ""
        val n = nombre(a?.tipo ?: TipoVideollamada.COMIENZO)
        val propio = "¿Confirmás tu $n el ${diaCorto(f.inicio, zona)} a las ${hora(f.inicio, zona)}$ar?$dura"
        return texto(a, "confirmar", propio, hora(f.inicio, zona), diaCorto(f.inicio, zona), duracion(f.inicio, f.fin))
    }

    /**
     * «Dura unas 2 horas», «Dura alrededor de 1 hora y media», «Dura alrededor de 1 hora», «Dura unos 45 minutos». Más de
     * 1 h se redondea a la media hora; hasta 1 h, a los 15 min. null si no cierra.
     */
    fun textoDuracion(inicio: Instant, fin: Instant): String? = duracion(inicio, fin)?.let { "Dura $it" }

    /** «unas 2 horas», «alrededor de 1 hora y media», «alrededor de 1 hora», «unos 45 minutos» (el `{duracion}`). */
    fun duracion(inicio: Instant, fin: Instant): String? {
        val min = java.time.Duration.between(inicio, fin).toMinutes()
        if (min <= 0) return null
        if (min > 60) {
            val medias = Math.round(min / 30.0).toInt()
            val horas = medias / 2
            val yMedia = if (medias % 2 == 1) " y media" else ""
            return if (horas == 1) "alrededor de 1 hora$yMedia" else "unas $horas horas$yMedia"
        }
        val cuartos = (Math.round(min / 15.0) * 15).coerceAtLeast(15)
        return if (cuartos >= 60) "alrededor de 1 hora" else "unos $cuartos minutos"
    }

    /** «Jueves 12 de noviembre, de 10:00 a 11:00» (sin dos puntos después del nombre: regla de los textos del alumno). */
    fun textoConfirmada(r: ReservaEntrega, zona: ZoneId, a: AgendaEntrega? = null): String {
        val i = r.inicio ?: return "Tu ${nombre(r.tipo)} está agendada"
        val f = r.fin
        val propio = if (f == null) "${mayuscula(dia(i, zona))}, a las ${hora(i, zona)}" else "${mayuscula(dia(i, zona))}, de ${rango(i, f, zona)}"
        return texto(a, "confirmada", propio, hora(i, zona), dia(i, zona), f?.let { duracion(i, it) })
    }

    /** Desde cuánto antes de la franja se consulta seguido si falta el link o si Mati ya abrió la sala. */
    const val MINUTOS_ANTES = 30L

    /** Cada cuánto se consulta la agenda, con la pantalla abierta, mientras se espera el link o la sala. */
    const val CONSULTA_SALA_MS = 30_000L

    /**
     * Hasta cuándo dura la videollamada: el `fin` de la reserva. Sin él (no debería pasar: el servidor lo manda siempre) no
     * se inventa una duración: se toma el fin de ese día en Argentina, para no cortar el «Entrar» antes de tiempo.
     */
    fun finDe(r: ReservaEntrega): Instant? =
        r.fin ?: r.inicio?.let { it.atZone(ARGENTINA).toLocalDate().plusDays(1).atStartOfDay(ARGENTINA).toInstant() }

    /** Los minutos de la ventana de consultas: `aviso_min` del servidor (spec §7) o los 30 de la app. */
    fun minutosAntes(avisoMin: Int?): Long = avisoMin?.toLong() ?: MINUTOS_ANTES

    // ── La videollamada (2.3.0, Mati 10/11): cómo se nombra, la tarjeta fija, «Entrar», la cuenta regresiva y los avisos ──

    /** «videollamada de comienzo» o «videollamada de revisión». Al alumno nunca se le dice «entrega». */
    fun nombre(t: TipoVideollamada): String =
        if (t == TipoVideollamada.REVISION) "videollamada de revisión" else "videollamada de comienzo"

    /** «Tu videollamada de comienzo». */
    fun tituloTarjeta(t: TipoVideollamada): String = "Tu ${nombre(t)}"

    /**
     * Desde cuántos minutos antes del inicio se habilita «Entrar» (Meet restringido: Mati lo admite y el alumno espera en la
     * sala). El servidor lo puede cambiar con `entrar_desde_min`.
     */
    const val ENTRAR_DESDE_MIN = 10

    const val TEXTO_DESDE_ACA = "Vas a entrar a la videollamada desde acá."
    const val TEXTO_ADMITE = "Mati te admite en la sala. Si tarda un poco, esperá ahí sin salir."
    const val TEXTO_YA_PODES = "Ya podés entrar"
    const val TEXTO_SALA_ABIERTA = "Mati ya está en la sala"
    const val TEXTO_PREPARANDO = "Estamos preparando la sala. El botón se activa en un momento."

    /** «¿Cómo entro?», en el orden en que pasan las cosas. */
    val AYUDA_ENTRAR = listOf(
        "Tocás Entrar y se abre la reunión. Si te pide tu nombre, escribilo y tocá «Solicitar unirse».",
        "Mati te admite en la sala. Esperá ahí, no hace falta salir y volver a entrar.",
        "Si se abre Gmail o la portada de Meet, copiá el código de la reunión, que aparece junto a Entrar, y pegalo en «Unirse con un código».",
        "Si se corta, volvé a la app y tocá Entrar de nuevo.",
        "Si no podés entrar, escribinos por el chat.",
    )

    // El código de la reunión (2.3.1): el respaldo de «Entrar».

    const val TITULO_CODIGO = "Código de la reunión"
    const val TEXTO_COPIAR_CODIGO = "Copiar código"
    const val TEXTO_CODIGO_COPIADO = "Código copiado"
    /**
     * Solo Android, sin la app de Meet: la web de Meet en el celular manda a instalar la app (Google Play) en vez de dejar
     * entrar en el navegador, como sí pasa en el iPhone.
     */
    const val TEXTO_SIN_APP_MEET = "Si te pide instalar Google Meet, instalala y volvé a tocar Entrar."
    /** Dónde se pega el código si «Entrar» no abre la reunión, en pasos cortos para gente mayor (Mati, 12/11). */
    const val TITULO_PASOS_CODIGO = "Si no se abre la reunión:"
    val PASOS_CODIGO = listOf(
        "Tocá «Copiar código».",
        "Abrí Google Meet.",
        "Tocá «Unirse con un código».",
        "Pegá el código y tocá «Unirse».",
    )

    private val CODIGO_CON_GUIONES = Regex("^[a-z]{3}-[a-z]{4}-[a-z]{3}$")
    private val CODIGO_SIN_GUIONES = Regex("^[a-z]{10}$")

    /**
     * El código de un link de Meet, «abc-defg-hij», o null si el link no es de una reunión de Meet (gemelo de
     * `ReglasAgenda.codigoMeet` de iOS). Acepta el código sin guiones y lo devuelve con guiones; ignora mayúsculas, la barra
     * final y lo que venga después (`?authuser`, `#`).
     */
    fun codigoMeet(url: String?): String? {
        val u = url?.trim() ?: return null
        val m = Regex("^https://(www\\.)?meet\\.google\\.com(/[^?#]*)?([?#].*)?$", RegexOption.IGNORE_CASE).matchEntire(u) ?: return null
        val partes = (m.groupValues[2]).split('/').filter { it.isNotEmpty() }
        if (partes.size != 1) return null
        val crudo = partes[0].lowercase()
        val letras = when {
            CODIGO_CON_GUIONES.matches(crudo) -> crudo.replace("-", "")
            CODIGO_SIN_GUIONES.matches(crudo) -> crudo
            else -> return null
        }
        return "${letras.substring(0, 3)}-${letras.substring(3, 7)}-${letras.substring(7)}"
    }

    /** En qué está el botón «Entrar». */
    sealed interface EstadoEntrar {
        /** Todavía no: faltan estos segundos para que se habilite. */
        data class Falta(val segundos: Long) : EstadoEntrar

        /** Habilitado (desde `desdeMin` antes, o antes con la sala abierta, hasta el fin). */
        data object Habilitado : EstadoEntrar

        /** En la ventana pero el link todavía no llegó (el daemon no lo cargó): sin botón activo. */
        data object Preparando : EstadoEntrar

        /** Terminó, o no es una reserva confirmada. */
        data object Nada : EstadoEntrar
    }

    fun estadoEntrar(r: ReservaEntrega?, ahora: Instant, desdeMin: Int? = null): EstadoEntrar {
        if (r == null || r.estado != ReservaEntrega.Estado.CONFIRMADA) return EstadoEntrar.Nada
        val i = r.inicio ?: return EstadoEntrar.Nada
        val f = finDe(r) ?: return EstadoEntrar.Nada
        if (!ahora.isBefore(f)) return EstadoEntrar.Nada
        val desde = i.minusSeconds((desdeMin ?: ENTRAR_DESDE_MIN) * 60L)
        // Si Mati ya abrió la sala, se puede entrar antes (espera en la sala igual).
        if (ahora.isBefore(desde) && (r.salaAbiertaEn == null || r.meetUrl == null)) {
            return EstadoEntrar.Falta(Duration.between(ahora, desde).seconds)
        }
        return if (r.meetUrl == null) EstadoEntrar.Preparando else EstadoEntrar.Habilitado
    }

    /**
     * El botón para entrar (Mati, 10/11): confirmada, con link, desde `desdeMin` (10) antes del inicio hasta el fin. El Meet
     * es restringido: Mati lo admite y el alumno espera en la sala, así que ya no se espera `sala_abierta_en`.
     */
    fun puedeEntrar(r: ReservaEntrega?, ahora: Instant, desdeMin: Int? = null): Boolean =
        estadoEntrar(r, ahora, desdeMin) == EstadoEntrar.Habilitado

    /** Debajo del botón apagado: lejos, «Se habilita 10 minutos antes de empezar»; a menos de un día, la cuenta regresiva. */
    fun textoCuenta(e: EstadoEntrar, desdeMin: Int? = null): String? = when (e) {
        is EstadoEntrar.Falta ->
            if (e.segundos >= 24 * 3600) "Se habilita ${desdeMin ?: ENTRAR_DESDE_MIN} minutos antes de empezar" else "Se habilita en ${cuenta(e.segundos)}"
        EstadoEntrar.Preparando -> TEXTO_PREPARANDO
        EstadoEntrar.Habilitado, EstadoEntrar.Nada -> null
    }

    /** «2 h 15 min», «25 min», «menos de 1 min». Redondea para arriba: nunca dice 0 antes de tiempo. */
    fun cuenta(segundos: Long): String {
        if (segundos < 60) return "menos de 1 min"
        val min = ((segundos + 59) / 60).toInt()
        if (min < 60) return "$min min"
        val h = min / 60
        val m = min % 60
        return if (m == 0) "$h h" else "$h h $m min"
    }

    /** Con el botón: «Mati ya está en la sala» o «Ya podés entrar» (siempre los propios: `sala_abierta` es de la 2.2.0). */
    @Suppress("UNUSED_PARAMETER")
    fun textoEntrar(r: ReservaEntrega, zona: ZoneId, a: AgendaEntrega? = null): String =
        if (r.salaAbiertaEn == null) TEXTO_YA_PODES else TEXTO_SALA_ABIERTA

    /** La etiqueta de arriba de la tarjeta: «Hoy», «Mañana», «En 3 días» (por día del calendario, en la zona del teléfono). */
    fun cuando(r: ReservaEntrega, zona: ZoneId, ahora: Instant): String? {
        val i = r.inicio ?: return null
        val d = ChronoUnit.DAYS.between(ahora.atZone(zona).toLocalDate(), i.atZone(zona).toLocalDate())
        return when {
            d < 0 -> null
            d == 0L -> "Hoy"
            d == 1L -> "Mañana"
            else -> "En $d días"
        }
    }

    /** «10:00 en Argentina», solo si el teléfono da otra hora. */
    fun horaArgentina(i: Instant, zona: ZoneId): String? =
        if (difiereDeArgentina(zona, listOf(i))) "${hora(i, ARGENTINA)} en Argentina" else null

    /** La reserva de la tarjeta fija de Entreno: confirmada (o reservándose) y que no terminó. */
    fun paraTarjeta(r: ReservaEntrega?, ahora: Instant): Boolean {
        if (r == null || !r.vigente || r.inicio == null) return false
        return ahora.isBefore(finDe(r))
    }

    /**
     * En la ventana (desde `aviso_min`, 30, antes hasta el fin) y todavía sin el link o sin la sala abierta: con la pantalla
     * a la vista se consulta la agenda cada 30 s (para el link que falta y para «Mati ya está en la sala»).
     */
    fun esperandoSala(r: ReservaEntrega?, ahora: Instant, avisoMin: Int? = null): Boolean {
        if (r == null || r.estado != ReservaEntrega.Estado.CONFIRMADA) return false
        if (r.meetUrl != null && r.salaAbiertaEn != null) return false
        val i = r.inicio ?: return false
        return !ahora.isBefore(i.minusSeconds(minutosAntes(avisoMin) * 60)) && ahora.isBefore(finDe(r)!!)
    }

    /**
     * El día de la videollamada, en la guía: «Tu videollamada de comienzo es hoy a las 10:00. El botón para entrar se
     * habilita 10 minutos antes.» (con la reserva confirmada, ese día y antes de que se habilite «Entrar»). Si no, null.
     */
    fun textoHoy(r: ReservaEntrega, zona: ZoneId, ahora: Instant, a: AgendaEntrega? = null): String? {
        val i = r.inicio ?: return null
        val desdeMin = a?.entrarDesdeMin
        if (r.estado != ReservaEntrega.Estado.CONFIRMADA || estadoEntrar(r, ahora, desdeMin) !is EstadoEntrar.Falta) return null
        if (i.atZone(zona).toLocalDate() != ahora.atZone(zona).toLocalDate()) return null
        // Siempre el propio: `hoy_sin_sala` es de la 2.2.0.
        return "Tu ${nombre(r.tipo)} es hoy a las ${hora(i, zona)}. El botón para entrar se habilita ${desdeMin ?: ENTRAR_DESDE_MIN} minutos antes."
    }

    /** Un aviso local de la videollamada (sin permisos nuevos: solo si la app ya los tenía). */
    data class AvisoLocal(val id: String, val fecha: Instant, val titulo: String, val cuerpo: String)

    const val ID_AVISO_DIA = "mypump-videollamada-dia"
    const val ID_AVISO_ENTRAR = "mypump-videollamada-entrar"

    /** Un día antes y cuando se habilita «Entrar». Los que ya pasaron no van. Sin reserva confirmada, ninguno. */
    fun avisosLocales(r: ReservaEntrega?, ahora: Instant, zona: ZoneId, desdeMin: Int? = null): List<AvisoLocal> {
        if (r == null || r.estado != ReservaEntrega.Estado.CONFIRMADA) return emptyList()
        val i = r.inicio ?: return emptyList()
        val n = nombre(r.tipo)
        return listOf(
            AvisoLocal(ID_AVISO_DIA, i.minus(Duration.ofHours(24)), "Mañana es tu $n", "Es a las ${hora(i, zona)}. Vas a entrar desde la app, en Entreno."),
            AvisoLocal(
                ID_AVISO_ENTRAR,
                i.minusSeconds((desdeMin ?: ENTRAR_DESDE_MIN) * 60L),
                "Ya podés entrar a tu $n",
                "Abrí la app y tocá Entrar. Mati te admite en la sala.",
            ),
        ).filter { it.fecha.isAfter(ahora) }
    }

    // ── Elegir y cambiar el horario (palanca `elegir_horario`) ──

    /** «Elegí el horario de tu videollamada de comienzo». */
    fun tituloElegir(t: TipoVideollamada): String = "Elegí el horario de tu ${nombre(t)}"

    /** «Dura alrededor de 1 hora y vas a entrar desde la app.» (la duración, de las franjas si todas duran lo mismo). */
    fun textoElegirPantalla(franjas: List<FranjaEntrega>): String =
        duracionComun(franjas)?.let { "Dura $it y vas a entrar desde la app." } ?: "Vas a entrar desde la app."

    /** «Elegí el día y el horario. Hay lugar desde el jueves 12.» */
    fun textoAgendar(franjas: List<FranjaEntrega>, zona: ZoneId): String =
        franjas.minOfOrNull { it.inicio }?.let { "Elegí el día y el horario. Hay lugar desde el ${diaCorto(it, zona)}." }
            ?: "Elegí el día y el horario. Vas a entrar desde la app."

    /** El botón de abajo con un horario elegido: «Confirmar jueves 12, 10:00» o «Cambiar al viernes 13, 12:00». */
    fun textoBotonElegir(f: FranjaEntrega, cambiando: Boolean, zona: ZoneId): String {
        val d = "${diaCorto(f.inicio, zona)}, ${hora(f.inicio, zona)}"
        return if (cambiando) "Cambiar al $d" else "Confirmar $d"
    }

    /** Se puede cambiar desde la app: lo dice el servidor, quedan cambios, no pasó el plazo ni empezó, y hay horarios. */
    fun puedeCambiar(a: AgendaEntrega?, ahora: Instant): Boolean {
        val r = a?.reserva ?: return false
        val c = a.cambio ?: return false
        if (r.estado != ReservaEntrega.Estado.CONFIRMADA || !c.permitido || a.franjas.isEmpty() || r.id == null) return false
        val restantes = c.restantes
        val hasta = c.hasta
        val inicio = r.inicio
        if (restantes != null && restantes <= 0) return false
        if (hasta != null && !ahora.isBefore(hasta)) return false
        if (inicio != null && !ahora.isBefore(inicio)) return false
        return true
    }

    /** «Podés cambiarlo 1 vez, hasta el miércoles 11 a las 10:00.» */
    fun textoTope(c: CambioAgenda?, zona: ZoneId): String? {
        if (c == null || !c.permitido) return null
        val veces = c.restantes?.let { if (it == 1) " 1 vez" else " $it veces" } ?: ""
        val hasta = c.hasta?.let { ", hasta el ${diaCorto(it, zona)} a las ${hora(it, zona)}" } ?: ""
        return "Podés cambiarlo$veces$hasta."
    }

    /** Lo que se ve arriba al cambiar: «Ahora es el jueves 12 a las 10:00.» */
    fun textoAhoraEs(r: ReservaEntrega, zona: ZoneId): String? =
        r.inicio?.let { "Ahora es el ${diaCorto(it, zona)} a las ${hora(it, zona)}." }

    /** La primera letra en mayúscula («Jueves 12 de noviembre»). */
    fun mayuscula(s: String): String = s.replaceFirstChar { if (it.isLowerCase()) it.titlecase(ES) else it.toString() }
}
