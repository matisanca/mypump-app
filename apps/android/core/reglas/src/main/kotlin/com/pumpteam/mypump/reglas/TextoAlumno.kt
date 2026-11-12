package com.pumpteam.mypump.reglas

/**
 * REGLA DURA (Mati): «RIR» y «reps en reserva» no aparecen NUNCA en una pantalla del alumno; todo va al fallo.
 *
 * El texto libre del plan que se dibuja tal cual (`notas_tecnica`, la nota de una serie de preparación) pasa por acá: se
 * saca la mención sin romper la frase y, si queda alguna que no se entiende, se saca la oración entera. «cerca del fallo»
 * pasa a «al fallo». Excepción: el plan con reserva a propósito (decisión clínica de Mati: lumbar, cardiopatía,
 * excepciones): si el rir de esa semana tiene un número mayor que 0, la nota es una indicación clínica y va entera.
 *
 * Port exacto de `sinRIR` / `notaParaAlumno` de la web (`public/js/reglas-entreno.js`) y de `TextoAlumno.swift`;
 * vectores en `apps/shared/vectores/sin_rir.json`.
 */
object TextoAlumno {
    private fun re(p: String) = Regex(p, RegexOption.IGNORE_CASE)
    private const val D = "$"

    private const val N = """\d+(?:[.,]\d+)?(?:\s*(?:[-–]|a|o)\s*\d+(?:[.,]\d+)?)?"""
    private const val RES = """(?:en reserva|en la recámara|en el tanque)"""
    private const val REPS = """(?:repeticiones|repes|reps|rep)"""
    private val detecta = re("""\bRIR\b|en reserva|en la recámara|en el tanque|cerca del fallo""")
    private val queda = re("""\bRIR\b|en reserva|en la recámara|en el tanque""")

    private val pasos: List<Pair<Regex, String>> = listOf(
        re("""\bcerca del fallo\b""") to "al fallo",
        re("""\bno calcules\s+(?:el\s+)?RIR\b\s*[:.,;]?\s*""") to "",
        re(""",\s*([^\s,.;:()]+(?:\s+[^\s,.;:()]+)?)\s+y\s+(?:con\s+)?RIR\s*$N""") to " y ${D}1",
        re("""\s*[·,;]\s*(?:con\s+)?RIR\s*$N""") to "",
        re("""\s+y\s+(?:con\s+)?RIR\s*$N""") to "",
        re("""\s*\([^()]*(?:\bRIR\b|en reserva|en la recámara|en el tanque|te sobra|que te queden|quedar\s+\d)[^()]*\)""") to "",
        re("""\s*\b(?:con\s+)?RIR\s*$N""") to "",
        re("""(?:\s+y\s+|\s*,\s*)?\b(?:dejá|deja|quedate con)\s+$N\s*$REPS?\s*$RES(?:\s+en todo)?\s*(?:y\s+|,\s*)?""") to " ",
        re("""\s*,?\s*(?:\by\s+)?(?:solo\s+)?(?:\b(?:dejando|dejar|con|que te queden?)\s+)?(?:solo\s+)?$N\s*$REPS?\s*$RES(?:\s+en todo)?""") to "",
    )
    private val limpieza: List<Pair<Regex, String>> = listOf(
        re("""[ \t]{2,}""") to " ",
        re("""\(\s*\)""") to "",
        re("""\s+([,.;:)])""") to "${D}1",
        re("""\(\s+""") to "(",
        re("""[,;:]\s*([.!?])""") to "${D}1",
        re("""([,;:])\s*[,;:]""") to "${D}1",
        re("""\s*[·—–]\s*([.!?)]|$D)""") to "${D}1",
    )
    private val corteOracion = re("""(?<=[.!?])\s+""")
    private val inicioSucio = re("""^[\s,;:·—–-]+""")
    private val soloPuntos = re("""^[.!?]+$D""")

    private fun oracion(o: String): String {
        val x = inicioSucio.replace(o, "").trim()
        if (x.isEmpty() || soloPuntos.matches(x) || queda.containsMatchIn(x)) return ""
        return x.substring(0, 1).uppercase() + x.substring(1)
    }

    private fun linea(l: String): String {
        var x = l
        for ((r, por) in pasos) x = r.replace(x, por)
        for ((r, por) in limpieza) x = r.replace(x, por)
        return corteOracion.split(x).map(::oracion).filter { it.isNotEmpty() }.joinToString(" ")
    }

    /** El texto sin RIR ni reps en reserva. Lo que no los menciona vuelve igual. */
    fun sinRIR(texto: String): String {
        if (!detecta.containsMatchIn(texto)) return texto
        val lineas = mutableListOf<String>()
        for (l in texto.split("\n")) {
            if (!detecta.containsMatchIn(l)) { lineas += l; continue }
            val r = linea(l)
            if (r.isNotEmpty()) lineas += r
        }
        return lineas.joinToString("\n").trim()
    }

    private val numero = Regex("""\d+([.,]\d+)?""")
    private val rango = Regex("""\d+([.,]\d+)?(\s*[-–]\s*\d+([.,]\d+)?)?""")
    private val rpe = Regex("rpe", RegexOption.IGNORE_CASE)

    /** ¿El rir del plan de esa semana pide reserva? Un número mayor que 0 (sin dato, 0, «al fallo» o RPE: no). */
    fun conReserva(rir: String?): Boolean {
        if (rir == null || rpe.containsMatchIn(rir)) return false
        val r = rango.find(rir)?.value ?: return false
        return numero.findAll(r).any { (it.value.replace(',', '.').toDoubleOrNull() ?: 0.0) > 0 }
    }

    /** La nota del plan como la ve el alumno: entera si esa semana lleva reserva clínica; si no, sin RIR. Vacía → null. */
    fun notaParaAlumno(texto: String?, rir: String?): String? {
        if (texto == null) return null
        val r = (if (conReserva(rir)) texto else sinRIR(texto)).trim()
        return r.ifEmpty { null }
    }
}
