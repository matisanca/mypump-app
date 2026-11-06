package com.pumpteam.mypump.reglas

import com.pumpteam.mypump.modelos.AgendaEntrega
import com.pumpteam.mypump.modelos.ClipGuia
import com.pumpteam.mypump.modelos.FranjaEntrega
import com.pumpteam.mypump.modelos.Guia
import com.pumpteam.mypump.modelos.ReservaEntrega
import com.pumpteam.mypump.modelos.ResumenGuia
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
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
        else "${t.vistos} de $total videos nuevos" + (min?.let { ", te quedan $it min" } ?: "")
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
    private val ES = Locale.forLanguageTag("es-AR")
    private val DIA = DateTimeFormatter.ofPattern("EEEE d 'de' MMMM", ES)
    private val DIA_CORTO = DateTimeFormatter.ofPattern("EEEE d", ES)
    private val HORA = DateTimeFormatter.ofPattern("HH:mm", ES)

    /** La etiqueta discreta de los que cuentan (todos la misma: la marca de los datos no se muestra). */
    const val ETIQUETA = "Para ver antes de la entrega"

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
    fun faltanAMostrar(a: AgendaEntrega?, g: Guia?): Int = a?.faltan ?: g?.let(::faltan) ?: 0

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
    const val TEXTO_SIN_FRANJAS = "Ahora no hay horarios libres. Te escribimos por WhatsApp para coordinar."
    const val TEXTO_CAMBIAR = "¿Necesitás cambiarla? Escribinos por WhatsApp"
    const val TEXTO_DEMO = "En la demo no se crea ninguna videollamada"
    const val TEXTO_HORARIO_TELEFONO = "Horario de tu teléfono"
    const val TEXTO_TOMADA = "Ese horario se ocupó recién, elegí otro."

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
        !a.autorizada -> Vista.NO_AUTORIZADA
        !a.habilitada -> if (faltan > 0) Vista.BLOQUEADA else Vista.HABILITANDO
        a.franjas.isEmpty() -> Vista.SIN_FRANJAS
        else -> Vista.ELEGIR
    }

    /** El aviso arriba de las franjas después de un fallo: `tomada` (o la franja que ya no está), o cualquier otro. */
    fun avisoFallo(motivo: String?): String = when (motivo) {
        "tomada", "franja" -> TEXTO_TOMADA
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
     * «¿Confirmás la entrega el jueves 12 a las 10:00? Dura unas 2 horas.» La duración sale de la franja (fin − inicio): los
     * horarios y la duración cambian solo con datos.
     */
    fun textoConfirmar(f: FranjaEntrega, zona: ZoneId): String {
        val dura = textoDuracion(f.inicio, f.fin)?.let { " $it." } ?: ""
        return "¿Confirmás la entrega el ${diaCorto(f.inicio, zona)} a las ${hora(f.inicio, zona)}?$dura"
    }

    /**
     * «Dura unas 2 horas», «Dura alrededor de 1 hora y media», «Dura alrededor de 1 hora», «Dura unos 45 minutos». Más de
     * 1 h se redondea a la media hora; hasta 1 h, a los 15 min. null si no cierra.
     */
    fun textoDuracion(inicio: Instant, fin: Instant): String? {
        val min = java.time.Duration.between(inicio, fin).toMinutes()
        if (min <= 0) return null
        if (min > 60) {
            val medias = Math.round(min / 30.0).toInt()
            val horas = medias / 2
            val yMedia = medias % 2 == 1
            return when {
                horas == 1 -> "Dura alrededor de 1 hora" + if (yMedia) " y media" else ""
                else -> "Dura unas $horas horas" + if (yMedia) " y media" else ""
            }
        }
        val cuartos = (Math.round(min / 15.0) * 15).coerceAtLeast(15)
        return if (cuartos >= 60) "Dura alrededor de 1 hora" else "Dura unos $cuartos minutos"
    }

    /** «Tu entrega: jueves 12 de noviembre, 10:00 a 12:00». */
    fun textoConfirmada(r: ReservaEntrega, zona: ZoneId): String {
        val i = r.inicio ?: return "Tu entrega está confirmada"
        val f = r.fin ?: return "Tu entrega: ${dia(i, zona)}, ${hora(i, zona)}"
        return "Tu entrega: ${dia(i, zona)}, ${rango(i, f, zona)}"
    }

    /** Desde cuánto antes de la franja se muestra la tarjeta de Entreno y se consulta seguido si Mati ya abrió la sala. */
    const val MINUTOS_ANTES = 30L

    /** Cada cuánto se consulta la agenda, con la pantalla abierta, mientras se espera que Mati abra la sala. */
    const val CONSULTA_SALA_MS = 30_000L

    /**
     * Hasta cuándo dura la entrega: el `fin` de la reserva. Sin él (no debería pasar: el servidor lo manda siempre) no se
     * inventa una duración: se toma el fin de ese día en Argentina, para no cortar el «Entrar» antes de tiempo.
     */
    fun finDe(r: ReservaEntrega): Instant? =
        r.fin ?: r.inicio?.let { it.atZone(ARGENTINA).toLocalDate().plusDays(1).atStartOfDay(ARGENTINA).toInstant() }

    private fun fin(r: ReservaEntrega): Instant? = finDe(r)

    /**
     * «Entrar» (cambio de Mati del 6/11: el cliente nunca entra directo): confirmada, con link y antes del fin, y además
     * con `sala_abierta_en` (Mati ya está en el Meet) o, de respaldo si el daemon no ve a los participantes, desde la hora
     * de inicio. Entrar igual pide que Mati lo acepte (el Meet es restringido).
     */
    fun puedeEntrar(r: ReservaEntrega?, ahora: Instant): Boolean {
        if (r == null || r.estado != ReservaEntrega.Estado.CONFIRMADA || r.meetUrl == null) return false
        val i = r.inicio ?: return false
        if (!ahora.isBefore(fin(r)!!)) return false
        return r.salaAbiertaEn != null || !ahora.isBefore(i)
    }

    /**
     * Se espera que Mati abra la sala: confirmada, desde 30 min antes hasta el fin y todavía sin `sala_abierta_en`. Con la
     * pantalla abierta se consulta cada 30 s ([CONSULTA_SALA_MS]); la tarjeta de Entreno se muestra (sin botón).
     */
    fun esperandoSala(r: ReservaEntrega?, ahora: Instant): Boolean {
        if (r == null || r.estado != ReservaEntrega.Estado.CONFIRMADA || r.salaAbiertaEn != null) return false
        val i = r.inicio ?: return false
        return !ahora.isBefore(i.minusSeconds(MINUTOS_ANTES * 60)) && ahora.isBefore(fin(r)!!)
    }

    /** La tarjeta de Entreno: desde 30 min antes (o con la sala ya abierta) hasta el fin de la franja. */
    fun tarjetaEntreno(r: ReservaEntrega?, ahora: Instant): Boolean = esperandoSala(r, ahora) || puedeEntrar(r, ahora)

    const val TEXTO_SALA_ABIERTA = "Mati ya está en la videollamada"

    /**
     * La línea de la reserva confirmada sobre el botón (o en su lugar): con la sala abierta, «Mati ya está en la
     * videollamada»; el mismo día, sin sala, «Tu entrega es hoy a las 10:00. Cuando Mati abra la videollamada se habilita el
     * botón para entrar.»; con el respaldo de la hora de inicio, «Tu entrega empezó a las 10:00». Antes del día, null (solo
     * la fecha y la hora).
     */
    fun textoSala(r: ReservaEntrega, zona: ZoneId, ahora: Instant): String? {
        if (r.estado != ReservaEntrega.Estado.CONFIRMADA) return null
        val i = r.inicio ?: return null
        val f = fin(r)!!
        if (!ahora.isBefore(f)) return null
        if (r.salaAbiertaEn != null && r.meetUrl != null) return TEXTO_SALA_ABIERTA
        if (!ahora.isBefore(i) && r.meetUrl != null) return "Tu entrega empezó a las ${hora(i, zona)}"
        if (i.atZone(zona).toLocalDate() != ahora.atZone(zona).toLocalDate()) return null
        return "Tu entrega es hoy a las ${hora(i, zona)}. Cuando Mati abra la videollamada se habilita el botón para entrar."
    }
}
