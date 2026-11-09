package com.pumpteam.mypump.reglas

import com.pumpteam.mypump.modelos.ClipGuia
import com.pumpteam.mypump.modelos.DolorGuia
import com.pumpteam.mypump.modelos.Guia
import java.time.Instant

/**
 * «Lo que más te importa»: las reglas de `pack.html` (`partesDolor`, `htmlDolor` y `htmlExtra`), con los mismos casos que
 * iOS (`apps/shared/fixtures/guia/dolor-casos.json`). Sin `dolor`, o con el texto en blanco, no hay vista y la guía queda
 * como en la 2.2.0.
 */
object ReglasDolor {
    const val TITULO_BLOQUE = "Lo que más te importa"
    const val TITULO_VIDEOS = "Tus videos sobre esto"

    /** Una parte aparte: un párrafo «## Título» del texto y lo que le sigue. */
    data class Parte(val titulo: String, val parrafos: List<String>)

    data class Vista(val subtitulo: String?, val parrafos: List<String>, val partes: List<Parte>)

    /** Qué capítulo va en cada recuadro y cuáles siguen en la lista de siempre. */
    data class Reparto(val principal: ReglasGuia.Bloque?, val partes: List<ReglasGuia.Bloque?>, val resto: List<ReglasGuia.Bloque>)

    enum class EstadoPaso { HECHO, AHORA, PENDIENTE }

    data class Paso(val id: String, val numero: Int, val titulo: String, val estado: EstadoPaso)

    data class Introduccion(val texto: String, val pasos: List<Paso>)

    /** `/^lo que m[aá]s te importa$/i`, sobre el título sin espacios en las puntas. */
    fun esBloqueDolor(titulo: String?): Boolean =
        recortar(titulo.orEmpty()).lowercase().replace("á", "a") == "lo que mas te importa"

    fun vista(dolor: DolorGuia?): Vista? {
        if (dolor == null || recortar(dolor.texto).isEmpty()) return null
        val principal = mutableListOf<String>()
        val partes = mutableListOf<Pair<String, MutableList<String>>>()
        for (crudo in dolor.texto.split(ENTRE_PARRAFOS)) {
            val t = recortar(crudo)
            val titulo = tituloDeParte(t)
            if (titulo != null) {
                partes += titulo to mutableListOf()
            } else {
                val p = limpiarParrafo(t) ?: continue
                (partes.lastOrNull()?.second ?: principal) += p
            }
        }
        // Lo que había era solo markup: es lo mismo que vacío.
        if (principal.isEmpty() && partes.isEmpty()) return null
        val subtitulo = dolor.titulo?.let(::limpiarLinea)?.takeIf { it.isNotEmpty() && !esBloqueDolor(it) }
        return Vista(subtitulo, principal, partes.map { (t, ps) -> Parte(t, ps) })
    }

    /**
     * Los capítulos de cada recuadro: el del dolor y los que se llaman como una parte. Un capítulo va una sola vez (si dos
     * partes se titulan igual, va en la primera). «Novedad» nunca entra. Sin vista, todo sigue en `resto`.
     */
    fun reparto(bloques: List<ReglasGuia.Bloque>, v: Vista?): Reparto {
        if (v == null) return Reparto(null, emptyList(), bloques)
        val usados = HashSet<String>()
        fun tomar(cumple: (ReglasGuia.Bloque) -> Boolean): ReglasGuia.Bloque? =
            bloques.firstOrNull { !it.esNovedad && it.clave !in usados && cumple(it) }?.also { usados += it.clave }
        val principal = tomar { esBloqueDolor(it.titulo) }
        val partes = v.partes.map { p -> tomar { recortar(it.titulo) == p.titulo } }
        return Reparto(principal, partes, bloques.filterNot { it.clave in usados })
    }

    /** Los videos del recuadro van primero también en el reproductor, como `PRIO` en la web. Los `nuevo` no pasan por acá. */
    fun conDolorPrimero(clips: List<ClipGuia>, dolor: DolorGuia?): List<ClipGuia> {
        val v = vista(dolor) ?: return clips
        fun rango(c: ClipGuia): Int {
            val t = recortar(c.bloque ?: "Videos")
            if (esBloqueDolor(t)) return 0
            val i = v.partes.indexOfFirst { it.titulo == t }
            return if (i >= 0) i + 1 else Int.MAX_VALUE
        }
        return clips.sortedBy(::rango)
    }

    /**
     * La línea y los pasos de arriba de la guía, solo con `dolor` y antes de la videollamada. Son dos pasos, los de la web sin
     * el de entrar a la app. Sin fecha, la línea va sin fecha.
     */
    fun introduccion(g: Guia, hayDudas: Boolean, ahora: Instant = Instant.now()): Introduccion? {
        if (vista(g.dolor) == null || ReglasGuia.yaPaso(g.fechaEntrega, ahora)) return null
        val cuando = ReglasGuia.fechaCorta(g.fechaEntrega)?.let { " del $it" }.orEmpty()
        val lista = g.clipsDeLaLista
        val vistos = lista.isNotEmpty() && lista.all { it.visto }
        return Introduccion(
            "Antes de nuestra videollamada$cuando, hacé estos dos pasos.",
            listOf(
                Paso("videos", 1, "Mirá tus videos", if (vistos) EstadoPaso.HECHO else EstadoPaso.AHORA),
                Paso("dudas", 2, "Dejá tus dudas", if (hayDudas) EstadoPaso.HECHO else EstadoPaso.PENDIENTE),
            ),
        )
    }

    /** Lo que dice TalkBack de un paso. */
    fun textoHablado(p: Paso, total: Int): String {
        val estado = when (p.estado) {
            EstadoPaso.HECHO -> ", hecho"
            EstadoPaso.AHORA -> ", es el que sigue"
            EstadoPaso.PENDIENTE -> ""
        }
        return "Paso ${p.numero} de $total, ${p.titulo}$estado"
    }

    private const val E = "[\\s\\x0B\\p{Z}\\uFEFF]"
    private val ENTRE_PARRAFOS = Regex("\\r?\\n$E*?\\n")
    private val SALTOS = Regex("\\r\\n|[\\n\\r\\u000B\\u000C\\u0085\\u2028\\u2029]")
    private val NUMERALES = Regex("^#{1,6}(?:$E+|$)")
    /** Un «>» seguido de un número es un dato («> 54 de hematocrito»), no una cita. */
    private val CITA = Regex("^>(?!$E*[0-9])$E*")
    private val SEPARADOR = Regex("^([-*_])(?:$E*\\1){2,}$E*$")
    private val VINETA = Regex("^[-*+•]$E+")
    private val INLINES = listOf(
        Regex("!?\\[([^\\]]+)\\]\\([^)\\s]+\\)"),
        Regex("\\*\\*(?=\\S)(.+?)(?<=\\S)\\*\\*"),
        Regex("(?<![\\p{L}\\p{N}_])__(?=\\S)(.+?)(?<=\\S)__(?![\\p{L}\\p{N}_])"),
        Regex("~~(?=\\S)(.+?)(?<=\\S)~~"),
        Regex("(?<![\\p{L}\\p{N}_*])\\*(?=[^\\s*])(.+?)(?<=[^\\s*])\\*(?![\\p{L}\\p{N}_*])"),
        Regex("(?<![\\p{L}\\p{N}_])_(?=[^\\s_])(.+?)(?<=[^\\s_])_(?![\\p{L}\\p{N}_])"),
        Regex("`([^`\\n]+)`"),
    )

    private fun recortar(s: String): String = s.trim { it.isWhitespace() || it == '﻿' }

    /** `/^##\s+(.+)$/`: un párrafo de una sola línea. */
    private fun tituloDeParte(t: String): String? {
        if (!t.startsWith("##") || t.length < 3 || SALTOS.containsMatchIn(t)) return null
        val c = t[2]
        if (!c.isWhitespace() && c != '﻿') return null
        return limpiarInline(recortar(t.substring(2))).ifEmpty { null }
    }

    /** El párrafo como lo lee el cliente: un salto simple es un espacio (como en el HTML), salvo en una lista, y sin marcas. */
    private fun limpiarParrafo(t: String): String? {
        var hayLista = false
        val lineas = mutableListOf<String>()
        for (cruda in t.split(SALTOS)) {
            val s = NUMERALES.replaceFirst(CITA.replaceFirst(recortar(cruda), ""), "")
            if (SEPARADOR.containsMatchIn(s)) continue
            val v = VINETA.find(s)
            if (v != null) {
                hayLista = true
                s.substring(v.range.last + 1).takeIf { recortar(it).isNotEmpty() }?.let { lineas += "• $it" }
            } else if (recortar(s).isNotEmpty()) {
                lineas += s
            }
        }
        if (lineas.isEmpty()) return null
        // Sin lista, el párrafo entero: una marca puede abrir en una línea y cerrar en la otra.
        val limpio = if (hayLista) lineas.map(::limpiarInline).filter { it.isNotEmpty() }.joinToString("\n") else limpiarInline(lineas.joinToString(" "))
        return limpio.ifEmpty { null }
    }

    private fun limpiarLinea(s: String): String = limpiarInline(NUMERALES.replaceFirst(recortar(s), ""))

    private fun limpiarInline(s: String): String = recortar(INLINES.fold(s) { t, r -> r.replace(t, "$1") })
}
