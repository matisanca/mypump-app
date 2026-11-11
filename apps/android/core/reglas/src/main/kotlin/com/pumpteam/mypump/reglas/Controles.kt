package com.pumpteam.mypump.reglas

import com.pumpteam.mypump.modelos.ValorJson
import java.text.Normalizer
import java.time.LocalDate
import java.time.ZoneId

// «Tu próximo control de salud» (pedido de Mati, 11/11; palanca `controles_app`): la lógica pura de lo que devuelve
// `mypump_controles_get` (`supabase/propuestas/nativa_controles_salud.sql`). Gemelo de iOS y de la web; los vectores de
// `apps/shared/vectores/controles.json` hacen fallar las pruebas si difieren. La app solo lee. Nunca el ciclo, fármacos
// ni «IA»: solo «Mati» y «control de salud».

/** Todo lo que lee el alumno de sus controles, en un solo lugar. */
object TextosControles {
    const val cejaInicio = "Control de salud"
    const val tituloInicio = "Tu próximo control de salud"
    const val verMisEstudios = "Ver mis estudios"
    const val notaProgramado = "Te vamos a mandar las órdenes unos días antes."
    const val notaOrdenes = "Ya te mandamos las órdenes. Están más abajo, en Tus órdenes."
    /** Con las órdenes mandadas por fuera de la app: no hay «Tus órdenes» a la que mandarlo. */
    const val notaOrdenesSinLista = "Ya te mandamos las órdenes."
    const val tituloPorDefecto = "Control de salud"
    const val hitosTitulo = "Tus controles de salud"
    const val hitoProximo = "Próximo"
    const val hitoRecibido = "Recibido"
    const val hitoVisto = "Mati lo vio"
}

/** Lo que devuelve `mypump_controles_get` con `habilitado: true`. Todo campo es opcional; lo que no se entiende se descarta. */
data class EstadoControles(
    val hoy: LocalDate?,
    /** El próximo: programado u órdenes enviadas (o un estado nuevo). Uno ya cerrado no es próximo. */
    val proximo: Controles.Control?,
    /** Hasta 3, resultado subido o revisado, en el orden del servidor (del más nuevo al más viejo). */
    val ultimos: List<Controles.Control>,
) {
    companion object {
        /** null: token caído, palanca apagada en el servidor o una respuesta que no es la esperada. */
        fun desde(j: ValorJson?): EstadoControles? {
            if (j?.get("habilitado") != ValorJson.Booleano(true)) return null
            return EstadoControles(
                hoy = Estudios.dia(j["hoy"]?.comoTexto),
                proximo = Controles.control(j["proximo"])?.takeIf { !it.estado.cerrado },
                ultimos = ((j["ultimos"] as? ValorJson.Lista)?.elementos ?: emptyList()).mapNotNull(Controles::control).filter { it.estado.cerrado }.take(3),
            )
        }
    }
}

object Controles {
    const val TITULO_MAX = 60

    enum class Estado(val cerrado: Boolean) {
        PROGRAMADO(false), ORDENES_ENVIADAS(false), RESULTADO_SUBIDO(true), REVISADO(true),
        /** Un estado que esta versión no conoce: se muestra en Estudios, sin nota y nunca arriba. */
        OTRO(false);

        companion object {
            fun de(s: String?): Estado = when (s) {
                // Sin el campo: lo más común y lo que el servidor pone por defecto.
                null, "programado" -> PROGRAMADO
                "ordenes_enviadas" -> ORDENES_ENVIADAS
                "resultado_subido" -> RESULTADO_SUBIDO
                "revisado" -> REVISADO
                else -> OTRO
            }
        }
    }

    data class Control(val titulo: String, val fecha: LocalDate, val avisarDesde: LocalDate?, val estado: Estado)

    fun control(j: ValorJson?): Control? {
        if (j !is ValorJson.Objeto) return null
        val f = Estudios.dia(j["fecha_objetivo"]?.comoTexto) ?: return null
        return Control(titulo(j["titulo_alumno"]?.comoTexto), f, Estudios.dia(j["avisar_desde"]?.comoTexto), Estado.de(j["estado"]?.comoTexto))
    }

    // ── Título ──

    private val PROHIBIDAS = setOf(
        "ciclo", "ciclos", "posciclo", "posciclos", "postciclo", "postciclos", "pct", "trt", "blast", "cruise", "nandrolona", "trembolona",
        "oxandrolona", "estanozolol", "primobolan", "boldenona", "masteron", "sarm", "sarms", "peptido", "peptidos", "dosis", "mg", "ml", "ui", "ia",
    )
    private val PREFIJOS = listOf("farmac", "testo", "esteroid", "anabolic", "androgen", "hormona")

    /**
     * El título del servidor, si es corto y no nombra nada del ciclo (el servidor ya lo controla: esto es la segunda llave).
     * Si no, «Control de salud».
     */
    fun titulo(s: String?): String {
        val t = s?.trim()?.takeIf { it.isNotEmpty() && it.codePointCount(0, it.length) <= TITULO_MAX } ?: return TextosControles.tituloPorDefecto
        val plano = Normalizer.normalize(t.lowercase(), Normalizer.Form.NFD).replace(Regex("\\p{M}+"), "")
        val palabras = plano.split(Regex("[^\\p{L}\\p{N}]+")).filter { it.isNotEmpty() }
        val malo = palabras.any { p -> p in PROHIBIDAS || PREFIJOS.any(p::startsWith) } || "inteligencia artificial" in plano
        return if (malo) TextosControles.tituloPorDefecto else t
    }

    // ── Fechas ──

    /** «lunes 16/11», con el año si no es el de hoy: «lunes 4/1/2027». */
    fun conDia(d: LocalDate, hoy: LocalDate?): String =
        if (hoy != null && hoy.year != d.year) "${Estudios.diaLargo(d)}/${d.year}" else Estudios.diaLargo(d)

    /** «El lunes 16/11» o, si ya pasó, «Era para el lunes 9/11» (sin tono de alarma). */
    fun cuando(d: LocalDate, hoy: LocalDate?): String =
        if (hoy != null && d.isBefore(hoy)) "Era para el ${conDia(d, hoy)}" else "El ${conDia(d, hoy)}"

    private fun nota(e: Estado, hayOrdenes: Boolean): String? = when (e) {
        Estado.PROGRAMADO -> TextosControles.notaProgramado
        Estado.ORDENES_ENVIADAS -> if (hayOrdenes) TextosControles.notaOrdenes else TextosControles.notaOrdenesSinLista
        else -> null
    }

    // ── Lo que muestra la app ──

    /**
     * El bloque «Próximo control» de Estudios, alimentado por el control. null sin próximo. [hayOrdenes]: si Estudios muestra
     * «Tus órdenes» (si no, la nota no manda a buscarlas ahí).
     */
    fun proximoParaEstudios(e: EstadoControles, hayOrdenes: Boolean = true): ControlEstudios? {
        val c = e.proximo ?: return null
        return ControlEstudios(tipo = null, titulo = c.titulo, desde = null, hasta = null, cuandoFijo = cuando(c.fecha, e.hoy), nota = nota(c.estado, hayOrdenes))
    }

    data class TarjetaInicio(val titulo: String, val cuando: String, val nota: String, val boton: String)

    /**
     * La tarjeta de arriba de la primera pestaña: desde `avisar_desde` y mientras siga `programado`. [hoyTelefono] cuenta solo
     * si el servidor no mandó `hoy`; sin ninguno de los dos, no se muestra (mejor nada que antes de tiempo).
     */
    fun tarjetaInicio(e: EstadoControles, hoyTelefono: LocalDate?): TarjetaInicio? {
        val c = e.proximo ?: return null
        if (c.estado != Estado.PROGRAMADO) return null
        val desde = c.avisarDesde ?: return null
        val hoy = e.hoy ?: hoyTelefono ?: return null
        if (desde.isAfter(hoy)) return null
        return TarjetaInicio(TextosControles.tituloInicio, cuando(c.fecha, hoy), TextosControles.notaProgramado, TextosControles.verMisEstudios)
    }

    data class Hito(val titulo: String, val cuando: String, val estado: String)

    /** «Tu recorrido»: el próximo y los últimos, cada uno con su fecha. */
    fun hitos(e: EstadoControles): List<Hito> = buildList {
        e.proximo?.let { add(Hito(it.titulo, conDia(it.fecha, e.hoy), TextosControles.hitoProximo)) }
        for (u in e.ultimos) add(Hito(u.titulo, conDia(u.fecha, e.hoy), if (u.estado == Estado.REVISADO) TextosControles.hitoVisto else TextosControles.hitoRecibido))
    }

    /** La fecha de hoy en el teléfono (solo si el servidor no la manda). */
    fun hoyDelTelefono(zona: ZoneId = ZoneId.systemDefault()): LocalDate = LocalDate.now(zona)
}
