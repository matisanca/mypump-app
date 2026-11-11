package com.pumpteam.mypump.reglas

import java.time.LocalDate
import java.time.OffsetDateTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.DateTimeFormatterBuilder
import java.time.format.DateTimeParseException
import java.util.Locale

/**
 * «Tu cambio» (2.3.0, detrás de `check_guiado`; gemela de `TuCambio.swift`): la foto de la semana 1 al lado de la última,
 * por pose, siempre a la vista en Revisión. Pedido de Mati del 11/11.
 *
 * - La semana 1 es la foto más vieja de esa pose: la de inicio si es de esa semana o de antes; si no, la de progreso más
 *   vieja. Empate de semana: gana la de inicio.
 * - La última es la de progreso más nueva de esa pose, de una semana posterior a la semana 1.
 * - El par aparece desde que hay dos semanas distintas con alguna foto (contando la de inicio). Antes: el texto de espera y
 *   la foto que haya.
 * - El pie es el del comparador de siempre ([FotosProgreso.resumenComparador]).
 * Casos en `apps/shared/vectores/tucambio.json`.
 */
object TuCambio {
    const val TITULO = "Tu cambio"
    const val TEXTO_ESPERA = "Tu cambio se va a ver acá desde tu segunda semana de fotos"
    const val ROTULO_ANTES = "Semana 1"
    const val ROTULO_ESTA_SEMANA = "Esta semana"
    const val BOTON_VER = "Ver mis fotos"
    const val POSE_INICIAL = "frente"
    /** La pantalla «Listo» del check guiado, arriba del par de frente. */
    const val LISTO_TITULO = "Tu cambio hasta hoy"

    enum class Modo(val clave: String) { ESPERA("espera"), PAR("par") }
    enum class Origen(val clave: String) { INICIO("inicio"), PROGRESO("progreso") }

    data class Foto(val origen: Origen, val semana: String)

    data class Vista(
        val modo: Modo,
        /** La pose que se muestra (en espera puede no ser la elegida: la que tenga foto). */
        val pose: String,
        val antes: Foto?,
        val despues: Foto?,
        val texto: String?,
        val pie: String?,
        val rotuloAntes: String,
        val rotuloDespues: String,
        val accesibleAntes: String,
        val accesibleDespues: String,
        /**
         * Lo que dice el marco de la derecha sin foto: «Sin foto de perfil», o «Todavía no hay otra foto de perfil» cuando esa
         * pose tiene una sola foto (que entonces va a la izquierda con su propia semana, nunca rotulada «Semana 1»).
         */
        val vacioDespues: String,
    )

    /**
     * [fotos]: las de progreso (servidor y cola) como (semana, pose). [inicio]: pose → fecha local de la foto de inicio
     * (AAAA-MM-DD). [semanaActual]: el lunes de esta semana.
     */
    fun vista(
        fotos: List<Pair<String, String>>,
        inicio: Map<String, String>,
        semanaActual: String,
        pose: String,
        peso: List<PesoCorporal.Punto>,
    ): Vista {
        val poses = FotosProgreso.poses.map { it.first }
        val elegida = if (pose in poses) pose else POSE_INICIAL
        val semanasInicio = inicio.filterKeys { it in poses }.mapValues { FotosProgreso.lunes(it.value) }
        val momentos = fotos.filter { it.second in poses }.map { it.first }.toSet() + semanasInicio.values

        fun semanasDe(p: String) = fotos.filter { it.second == p }.map { it.first }.toSet().sorted()
        fun primera(p: String): Foto? {
            val deProgreso = semanasDe(p).firstOrNull()
            val s = semanasInicio[p]
            if (s != null && (deProgreso == null || s <= deProgreso)) return Foto(Origen.INICIO, s)
            return deProgreso?.let { Foto(Origen.PROGRESO, it) }
        }

        if (momentos.size < 2) {
            val orden = listOf(elegida) + poses.filter { it != elegida }
            val p = orden.firstOrNull { primera(it) != null } ?: elegida
            return Vista(Modo.ESPERA, p, primera(p), null, TEXTO_ESPERA, null, ROTULO_ANTES, "", accesible(ROTULO_ANTES), "", sinFoto(p))
        }

        val antes = primera(elegida)
        val despues = antes?.let { a -> semanasDe(elegida).lastOrNull()?.takeIf { it > a.semana }?.let { Foto(Origen.PROGRESO, it) } }
        val pie = if (antes != null && despues != null) FotosProgreso.resumenComparador(antes.semana, despues.semana, peso) else null
        if (antes != null && despues == null) {
            // Esa pose tiene una sola foto: se rotula con su semana y el otro marco dice que todavía no hay otra.
            val r = rotulo(antes.semana, semanaActual)
            return Vista(Modo.PAR, elegida, antes, null, null, null, r, "", accesible(r), sinOtra(elegida), sinOtra(elegida))
        }
        val rotuloDespues = rotulo(despues?.semana ?: semanaActual, semanaActual)
        return Vista(
            Modo.PAR, elegida, antes, despues, null, pie, ROTULO_ANTES, rotuloDespues,
            accesible(ROTULO_ANTES, if (antes == null) elegida else null),
            accesible(rotuloDespues, if (despues == null) elegida else null),
            sinFoto(elegida),
        )
    }

    /** «Esta semana» o «Semana del 12 de octubre». */
    fun rotulo(semana: String, semanaActual: String): String =
        if (semana == semanaActual) ROTULO_ESTA_SEMANA else "Semana del ${fecha(semana)}"

    /** «Foto de la semana 1», «Foto de esta semana»; sin foto, «…, sin foto de perfil». */
    fun accesible(rotulo: String, falta: String? = null): String {
        val base = if (rotulo == ROTULO_ESTA_SEMANA) "Foto de esta semana" else "Foto de la ${minusculaInicial(rotulo)}"
        return if (falta == null) base else "$base, ${minusculaInicial(sinFoto(falta))}"
    }

    /** Lo que dice el marco vacío: «Sin foto de perfil». */
    fun sinFoto(pose: String): String =
        "Sin foto de ${(FotosProgreso.poses.firstOrNull { it.first == pose }?.second ?: pose).lowercase(Locale.ROOT)}"

    /** El marco de la derecha cuando esa pose tiene una sola foto: «Todavía no hay otra foto de perfil». */
    fun sinOtra(pose: String): String =
        "Todavía no hay otra foto de ${(FotosProgreso.poses.firstOrNull { it.first == pose }?.second ?: pose).lowercase(Locale.ROOT)}"

    private fun minusculaInicial(s: String) = s.take(1).lowercase(Locale.ROOT) + s.drop(1)

    private val MESES = listOf("enero", "febrero", "marzo", "abril", "mayo", "junio", "julio", "agosto", "septiembre", "octubre", "noviembre", "diciembre")

    /** «12 de octubre» (sin depender del idioma del teléfono). */
    fun fecha(dia: String): String {
        val p = dia.split("-")
        if (p.size != 3) return dia
        val m = p[1].toIntOrNull() ?: return dia
        val d = p[2].toIntOrNull() ?: return dia
        if (m !in 1..12) return dia
        return "$d de ${MESES[m - 1]}"
    }

    /** ISO 8601 con la zona como «Z», «-03:00» o «+0000» (Postgres puede mandar cualquiera). */
    private val ISO_CON_ZONA: DateTimeFormatter = DateTimeFormatterBuilder()
        .append(DateTimeFormatter.ISO_LOCAL_DATE_TIME)
        .optionalStart().appendOffset("+HH:MM", "Z").optionalEnd()
        .optionalStart().appendOffset("+HHMM", "Z").optionalEnd()
        .optionalStart().appendOffset("+HH", "Z").optionalEnd()
        .toFormatter()

    /** La fecha local (AAAA-MM-DD) de un `tomada_en` del servidor. Sin zona o ilegible: sus 10 primeros caracteres, si son una fecha. */
    fun fechaLocal(iso: String, zona: ZoneId = ZoneId.systemDefault()): String? = try {
        OffsetDateTime.parse(iso, ISO_CON_ZONA).atZoneSameInstant(zona).toLocalDate().toString()
    } catch (e: DateTimeParseException) {
        val p = iso.take(10)
        if (p.length == 10 && DiaCalendario.numero(p) != null) LocalDate.ofEpochDay(DiaCalendario.numero(p)!!).toString() else null
    }
}
