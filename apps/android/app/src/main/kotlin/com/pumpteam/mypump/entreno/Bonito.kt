package com.pumpteam.mypump.entreno

import com.pumpteam.mypump.reglas.Pauta
import com.pumpteam.mypump.reglas.TiempoEntreno
import com.pumpteam.mypump.reglas.UltimaVez

/**
 * Los textos del motor salen con el formato de la web ("52.5kg × 7", "🎉 ¡Día completado!", "Pasar a SEM 6 →"); en la app
 * van con la coma, el espacio y los íconos de acá. Gemelo de `Bonito` (Entrenamiento.swift). Sin `Regex` de Kotlin: en
 * Android `\d`, `\s` y `\b` son los de ICU y en la JVM los de OpenJDK (ver `JsRegex`); se recorre el texto a mano.
 */
object Bonito {
    /** "52.5kg × 7 · RIR 1" → "52,5 kg × 7 · RIR 1"; con el peso del cuerpo ("0kg × 12") → "12 reps". */
    fun carga(s: String): String {
        // 1) "52.5kg" → "52,5 kg" y "80kg" → "80 kg": un número pegado a "kg".
        val t = StringBuilder()
        var i = 0
        while (i < s.length) {
            if (s.startsWith("kg", i) && i > 0 && s[i - 1].esDigito()) {
                // El número que termina acá: si lleva un punto entre dígitos, va con coma.
                var j = t.length - 1
                while (j >= 0 && t[j].esDigito()) j--
                if (j > 0 && t[j] == '.' && t[j - 1].esDigito()) t.setCharAt(j, ',')
                t.append(" kg")
                i += 2
            } else {
                t.append(s[i])
                i++
            }
        }
        // 2) "0 kg × 12" al principio o después de un espacio (el 0 es el número entero, no el final de "10 kg") → "12 reps".
        val cero = "0 kg × "
        var r = t.toString()
        var desde = 0
        while (true) {
            val k = r.indexOf(cero, desde)
            if (k < 0) break
            var fin = k + cero.length
            while (fin < r.length && r[fin].esDigito()) fin++
            if ((k == 0 || r[k - 1].isWhitespace()) && fin > k + cero.length) {
                val reps = r.substring(k + cero.length, fin)
                r = r.substring(0, k) + "$reps reps" + r.substring(fin)
                desde = k + reps.length + " reps".length
            } else {
                desde = k + 1
            }
        }
        return r
    }

    /** "58kg × 9 · RIR 0 (Agarre neutro)" → ("58 kg × 9", "RIR 0 · Agarre neutro"). */
    fun partir(s: String): Pair<String, String?> {
        var texto = carga(s)
        val extra = mutableListOf<String>()
        if (texto.endsWith(")")) {
            val abre = texto.lastIndexOf(" (")
            if (abre >= 0) {
                extra += texto.substring(abre + 2, texto.length - 1)
                texto = texto.substring(0, abre)
            }
        }
        val partes = texto.split(" · ").toMutableList()
        var principal = partes.removeAt(0)
        // Lo de la variante en el medio ("58 kg × 9 (Agarre) · 3 series").
        if (principal.endsWith(")")) {
            val abre = principal.lastIndexOf(" (")
            if (abre >= 0) {
                extra.add(0, principal.substring(abre + 2, principal.length - 1))
                principal = principal.substring(0, abre)
            }
        }
        val detalle = (partes + extra).filter { it.isNotEmpty() }
        return principal to (if (detalle.isEmpty()) null else detalle.joinToString(" · "))
    }

    /** Los botones de las preguntas, sin la flecha de la web ("Pasar a SEM 6 →"). */
    fun boton(s: String): String = s.replace(" →", "").trim()

    /**
     * Lo que la web escribe con un emoji adelante ("🎯 Primera vez…", "⚠ Modo demo…"): en la app el ícono es un vector.
     * Un símbolo (categoría `So`) al principio se va con lo que lo sigue hasta el primer espacio.
     */
    fun sinEmoji(s: String): String {
        if (s.isEmpty()) return s
        val primero = s.codePointAt(0)
        if (Character.getType(primero) != Character.OTHER_SYMBOL.toInt()) return s
        val espacio = s.indexOfFirst { it.isWhitespace() }
        return if (espacio < 0) "" else s.substring(espacio).trim()
    }

    /**
     * Las palabras en mayúsculas de 4 letras o más (los nombres de los días: "EMPUJE", "TIRÓN") como nombre propio; las
     * siglas cortas ("RIR", "SEM") quedan igual. Es el `\b[A-ZÁÉÍÓÚÑÜ]{4,}\b` de iOS.
     */
    fun nombres(s: String): String {
        val out = StringBuilder()
        var i = 0
        while (i < s.length) {
            if (!s[i].esDePalabra()) {
                out.append(s[i])
                i++
                continue
            }
            var fin = i
            while (fin < s.length && s[fin].esDePalabra()) fin++
            val palabra = s.substring(i, fin)
            out.append(if (palabra.length >= 4 && palabra.all { it in MAYUSCULAS }) mayusculaInicial(palabra.lowercase()) else palabra)
            i = fin
        }
        return out.toString()
    }

    /** "TIRÓN A — ANCHO" → "Tirón A — Ancho" (cada palabra, como `localizedCapitalized`); lo que no viene en mayúsculas queda igual. */
    fun titulo(s: String?): String {
        if (s.isNullOrEmpty()) return ""
        if (s != s.uppercase()) return s
        val out = StringBuilder()
        var inicio = true
        for (c in s.lowercase()) {
            out.append(if (inicio && c.isLetter()) c.uppercaseChar() else c)
            // Una palabra nueva después de un espacio o de un signo ("PECHO/HOMBRO" → "Pecho/Hombro"), no de un apóstrofo.
            inicio = !c.isLetterOrDigit() && c != '\''
        }
        return out.toString()
    }

    /** "BLOQUE 1 — ESPALDA" → "Bloque 1 — espalda"; "TIRÓN" → "Tirón". Lo que no viene en mayúsculas queda tal cual. */
    fun enOracion(s: String): String {
        if (s != s.uppercase() || s.none { it.isLetter() }) return s
        return mayusculaInicial(s.lowercase())
    }

    /** kg con la coma de acá ("52.5" → "52,5"). */
    fun coma(s: String): String = s.replace('.', ',')

    private fun mayusculaInicial(s: String): String = if (s.isEmpty()) s else s.substring(0, 1).uppercase() + s.substring(1)

    private const val MAYUSCULAS = "ABCDEFGHIJKLMNOPQRSTUVWXYZÁÉÍÓÚÑÜ"

    private fun Char.esDigito(): Boolean = this in '0'..'9'

    private fun Char.esDePalabra(): Boolean = isLetterOrDigit() || this == '_'
}

/**
 * Los nombres del catálogo traen el músculo entre paréntesis: "Jalón al pecho prono (dorsal ancho)". Se muestran en dos
 * renglones con jerarquía: el ejercicio y, abajo, el músculo. El nombre completo sigue entero para TalkBack.
 */
class NombreEjercicio(nombre: String) {
    val principal: String
    val detalle: String?

    init {
        val limpio = nombre.trim()
        val abre = limpio.lastIndexOf(" (")
        if (limpio.endsWith(")") && abre >= 0) {
            principal = limpio.substring(0, abre)
            val d = limpio.substring(abre + 2, limpio.length - 1).trim()
            detalle = if (d.isEmpty()) null else d.substring(0, 1).uppercase() + d.substring(1)
        } else {
            principal = limpio
            detalle = null
        }
    }
}

/** Lo que lee TalkBack en la card de un ejercicio (el `accessibilityValue` de `FilaEjercicio` en iOS). */
object CardAccesible {
    /** "Completo", "Terminado sin series", "Saltado", "2 de 4 series" o "Pendiente". */
    fun estado(estado: String, hechas: Int, total: Int): String = when (estado) {
        "completo" -> "Completo"
        "completo_sin_datos" -> "Terminado sin series"
        "saltado" -> "Saltado"
        else -> if (hechas > 0) "$hechas de $total series" else "Pendiente"
    }

    /**
     * El estado y lo mismo que se ve en la card: la sustitución, "marcado a mano", los mensajes, calentamiento o cardio, la
     * pauta, el RIR, el descanso, la última vez, el récord o "primera vez".
     */
    fun valor(
        estado: String,
        hechas: Int,
        total: Int,
        sustituido: Boolean,
        fijado: Boolean,
        manual: Boolean,
        mensajes: Int,
        tipo: String?,
        pauta: Pauta,
        descansoSegundos: Int,
        ultima: UltimaVez?,
        record: String?,
        buscandoHistorial: Boolean,
    ): String {
        val partes = mutableListOf(estado(estado, hechas, total))
        if (sustituido) partes += if (fijado) "sustitución fijada" else "sustituido solo por hoy"
        if (manual) partes += "marcado a mano"
        if (mensajes > 0) partes += if (mensajes == 1) "1 mensaje sin leer" else "$mensajes mensajes sin leer"
        if (tipo == "calentamiento") partes += "calentamiento" else if (tipo == "cardio") partes += "cardio"
        val porTiempo = tipo == "cardio" || pauta.series == null
        if (porTiempo) {
            pauta.reps?.let { partes += it }
        } else {
            partes += "${pauta.series} series de ${pauta.reps ?: "—"}"
        }
        pauta.rir?.let { partes += "RIR $it" }
        partes += "descanso ${TiempoEntreno.fmtTiempo(descansoSegundos.toDouble())}"
        ultima?.let { partes += "última vez ${Bonito.carga(it.valor)}, ${it.cuando}" }
        record?.let { partes += "récord ${Bonito.carga(it)}" }
        if (ultima == null && record == null && !porTiempo && !buscandoHistorial) partes += "primera vez con este ejercicio"
        return partes.joinToString(", ")
    }
}
