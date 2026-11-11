package com.pumpteam.mypump.reglas

import com.pumpteam.mypump.modelos.ValorJson
import java.time.Instant
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

/**
 * Las reglas de «Fotos de inicio» (frente, perfil y espalda, y «el físico que te motiva»), comunes con iOS y la web: las fijan
 * los vectores de `apps/shared/vectores/fotos_inicio.json`. Gemelo de FotosInicio.swift.
 */
object FotosInicio {
    data class Pose(val clave: String, val nombre: String, val instruccion: String)

    /** Las tres del cuerpo, en el orden en que se piden. */
    val poses: List<Pose> = listOf(
        Pose("frente", TextosFotosInicio.poseFrente, TextosFotosInicio.instruccionFrente),
        Pose("perfil", TextosFotosInicio.posePerfil, TextosFotosInicio.instruccionPerfil),
        Pose("espalda", TextosFotosInicio.poseEspalda, TextosFotosInicio.instruccionEspalda),
    )
    const val MOTIVACION = "motivacion"
    fun pose(clave: String): Pose? = poses.firstOrNull { it.clave == clave }

    val consejos: List<String> = listOf(
        TextosFotosInicio.consejoLuz, TextosFotosInicio.consejoDistancia, TextosFotosInicio.consejoAltura, TextosFotosInicio.consejoRopa,
        TextosFotosInicio.consejoFondo, TextosFotosInicio.consejoEspejo, TextosFotosInicio.consejoTemporizador, TextosFotosInicio.consejoPostura,
    )

    /** El JPEG que sube: lado mayor ≤ 1600 px a 0,85, sin metadatos. */
    const val MAX_PX = 1600
    const val CALIDAD = 0.85
    /** Con menos, la lectura del físico se descarta (el servidor tampoco la deja entrar). */
    const val MIN_LADO = 1080
    const val MIN_LADO_MOTIVACION = 320
    const val MAX_MOTIVACION = 4
    const val MAX_NOTA = 300
    const val BRILLO_MINIMO = 45.0
    const val NITIDEZ_MINIMA = 25.0
    const val DIAS_VIEJA = 7
    /** El control mira la foto achicada a bloques, con el lado mayor cerca de este tamaño. */
    const val LADO_ANALISIS = 640

    // ── Control de calidad ──

    data class Medida(
        /** Luz media, de 0 a 255. */
        val brillo: Double,
        /**
         * Qué tan marcados están los bordes más marcados, en la dirección en que menos lo están (una foto movida los pierde en
         * la dirección del movimiento).
         */
        val nitidez: Double,
    )

    enum class Problema(val clave: String) { CHICA("chica"), APAISADA("apaisada"), OSCURA("oscura"), MOVIDA("movida"), VIEJA("vieja") }

    /** La luz de un píxel, de 0 a 255. */
    fun luma(r: Int, g: Int, b: Int): Int = (r * 299 + g * 587 + b * 114) / 1000

    /**
     * Mide la luz y la nitidez sobre la luma de la foto (una por píxel, por filas; cada byte es un valor de 0 a 255). `paso`: el
     * lado del bloque que se promedia antes de medir; sin indicarlo, el que deja el lado mayor cerca de [LADO_ANALISIS]. Todo con
     * enteros, para que las tres plataformas den lo mismo.
     */
    fun medir(luma: ByteArray, ancho: Int, alto: Int, paso: Int? = null): Medida {
        if (ancho <= 0 || alto <= 0 || luma.size.toLong() < ancho.toLong() * alto) return Medida(0.0, 0.0)
        val n = max(1, paso ?: (max(ancho, alto) / LADO_ANALISIS))
        val w = ancho / n
        val h = alto / n
        if (w <= 0 || h <= 0) return Medida(0.0, 0.0)
        val l = IntArray(w * h)
        var total = 0L
        for (y in 0 until h) {
            for (x in 0 until w) {
                var suma = 0
                for (dy in 0 until n) {
                    val fila = (y * n + dy) * ancho + x * n
                    for (dx in 0 until n) suma += luma[fila + dx].toInt() and 0xFF
                }
                val v = suma / (n * n)
                l[y * w + x] = v
                total += v
            }
        }
        val brillo = total.toDouble() / (w * h).toDouble()
        if (w < 3 || h < 3) return Medida(brillo, 0.0)
        val horizontal = IntArray(511)
        val vertical = IntArray(511)
        for (y in 1 until h - 1) {
            for (x in 1 until w - 1) {
                val c = 2 * l[y * w + x]
                horizontal[abs(c - l[y * w + x - 1] - l[y * w + x + 1])]++
                vertical[abs(c - l[(y - 1) * w + x] - l[(y + 1) * w + x])]++
            }
        }
        val k = max(1, ((w - 2) * (h - 2)) / 100)
        return Medida(brillo, min(mediaDeLosMayores(horizontal, k), mediaDeLosMayores(vertical, k)))
    }

    /** La media de los `k` valores más altos de un histograma. */
    private fun mediaDeLosMayores(histograma: IntArray, k: Int): Double {
        var faltan = k
        var suma = 0L
        for (v in histograma.indices.reversed()) {
            if (histograma[v] <= 0) continue
            val tomo = min(faltan, histograma[v])
            suma += tomo.toLong() * v
            faltan -= tomo
            if (faltan == 0) break
        }
        return suma.toDouble() / k.toDouble()
    }

    /**
     * Qué tiene de malo la foto, en el orden en que se muestra. `dias`: cuántos días hace que se sacó, si se sabe. En «el
     * físico que te motiva» solo importa que no sea diminuta.
     */
    fun problemas(pose: String, ancho: Int, alto: Int, medida: Medida, dias: Int? = null): List<Problema> {
        val lado = max(ancho, alto)
        if (pose == MOTIVACION) return if (lado < MIN_LADO_MOTIVACION) listOf(Problema.CHICA) else emptyList()
        val lista = ArrayList<Problema>()
        if (lado < MIN_LADO) lista += Problema.CHICA
        if (ancho > alto) lista += Problema.APAISADA
        // Una foto oscura también mide poca nitidez: se avisa una sola cosa.
        if (medida.brillo < BRILLO_MINIMO) lista += Problema.OSCURA else if (medida.nitidez < NITIDEZ_MINIMA) lista += Problema.MOVIDA
        if (dias != null && dias > DIAS_VIEJA) lista += Problema.VIEJA
        return lista
    }

    /** Con poca resolución no se puede usar: el servidor tampoco la recibe. Lo demás se avisa y el alumno decide. */
    fun bloquea(problemas: List<Problema>): Boolean = Problema.CHICA in problemas

    fun texto(p: Problema, dias: Int? = null): String = when (p) {
        Problema.CHICA -> TextosFotosInicio.problemaChica
        Problema.APAISADA -> TextosFotosInicio.problemaApaisada
        Problema.OSCURA -> TextosFotosInicio.problemaOscura
        Problema.MOVIDA -> TextosFotosInicio.problemaMovida
        Problema.VIEJA -> TextosFotosInicio.problemaVieja(dias ?: (DIAS_VIEJA + 1))
    }

    /** Días enteros entre que se sacó y ahora (nunca negativo). */
    fun dias(desde: Instant, hasta: Instant): Int {
        val ms = hasta.toEpochMilli() - desde.toEpochMilli()
        return max(0L, ms / 86_400_000L).toInt()
    }

    // ── El set ──

    /** Las poses del cuerpo que faltan, contando las que esperan subir. */
    fun faltan(enServidor: Set<String>, enCola: Set<String>): List<String> =
        poses.map { it.clave }.filter { it !in enServidor && it !in enCola }

    /** A qué pose se pasa después de usar una foto: la primera que falte después de esa, y si no la primera que falte. */
    fun siguiente(despuesDe: String, faltan: List<String>): String? {
        val orden = poses.map { it.clave }
        val i = orden.indexOf(despuesDe)
        if (i < 0) return faltan.firstOrNull()
        return orden.drop(i + 1).firstOrNull { it in faltan } ?: faltan.firstOrNull { it != despuesDe }
    }

    fun puedeAgregarMotivacion(enServidor: Int, enCola: Int, maximo: Int = MAX_MOTIVACION): Boolean = enServidor + enCola < maximo

    /**
     * La nota como la guarda el servidor: los caracteres de control son espacios, sin espacios en las puntas y hasta 300
     * (contados como el servidor, por punto de código y no por unidad UTF-16: un emoji cuenta uno).
     */
    fun notaRecortada(s: String): String {
        val limpia = StringBuilder(s.length)
        var i = 0
        while (i < s.length) {
            val u = s.codePointAt(i)
            if (u < 0x20 || u in 0x7F..0x9F) limpia.append(' ') else limpia.appendCodePoint(u)
            i += Character.charCount(u)
        }
        val sinPuntas = limpia.toString().trim(' ')
        val cuantos = sinPuntas.codePointCount(0, sinPuntas.length)
        return if (cuantos <= MAX_NOTA) sinPuntas else sinPuntas.substring(0, sinPuntas.offsetByCodePoints(0, MAX_NOTA))
    }

    // ── Subida ──

    enum class Accion(val clave: String) { OK("ok"), DESCARTAR("descartar"), REINTENTAR("reintentar") }
    enum class Aviso(val clave: String) { RECHAZADA("rechazada"), TOPE("tope") }
    data class Subida(val accion: Accion, val aviso: Aviso? = null, val refrescar: Boolean = false)

    /** Qué hace la cola con la respuesta de `/inicio/upload`. Todo 4xx salvo 429 es definitivo; 5xx y 429, reintentar. */
    fun clasificarSubida(status: Int, ok: Boolean): Subida = when (status) {
        in 200..299 -> Subida(if (ok) Accion.OK else Accion.REINTENTAR)
        429 -> Subida(Accion.REINTENTAR)
        403 -> Subida(Accion.DESCARTAR, refrescar = true)   // el link ya no sirve, o se cerró la sección
        409 -> Subida(Accion.DESCARTAR)
        413 -> Subida(Accion.DESCARTAR, aviso = Aviso.TOPE)
        in 400..499 -> Subida(Accion.DESCARTAR, aviso = Aviso.RECHAZADA)
        else -> Subida(Accion.REINTENTAR)
    }
}

// ── Lo que contesta el servidor ──

data class FotoInicio(val id: String, val pose: String, val tomadaEn: String? = null, val ancho: Int = 0, val alto: Int = 0) {
    companion object {
        fun desde(j: ValorJson): FotoInicio? {
            val id = j["id"]?.comoTexto ?: return null
            val pose = j["pose"]?.comoTexto ?: return null
            return FotoInicio(id, pose, j["tomada_en"]?.comoTexto, j["ancho"]?.comoNumero?.toInt() ?: 0, j["alto"]?.comoNumero?.toInt() ?: 0)
        }
    }
}

/** `mypump_fotos_inicio_get` con `habilitado: true`. Un campo que no se entiende no rompe nada: queda lo de fábrica. */
data class EstadoFotosInicio(
    val fotos: List<FotoInicio>,
    val nota: String,
    val completo: Boolean,
    val maxMotivacion: Int,
) {
    /** Las poses del cuerpo que ya están en el servidor. */
    val poses: Set<String> get() = fotos.map { it.pose }.filter { it != FotosInicio.MOTIVACION }.toSet()
    val deMotivacion: List<FotoInicio> get() = fotos.filter { it.pose == FotosInicio.MOTIVACION }
    fun foto(pose: String): FotoInicio? = fotos.firstOrNull { it.pose == pose }

    companion object {
        /** null: no es una respuesta con `habilitado: true`. */
        fun desde(j: ValorJson): EstadoFotosInicio? {
            if (j["habilitado"] != ValorJson.Booleano(true)) return null
            val n = j["max_motivacion"]?.comoNumero
            return EstadoFotosInicio(
                fotos = ((j["fotos"] as? ValorJson.Lista)?.elementos ?: emptyList()).mapNotNull(FotoInicio::desde),
                nota = j["nota"]?.comoTexto ?: "",
                completo = j["completo"] == ValorJson.Booleano(true),
                maxMotivacion = if (n != null && n >= 0 && n <= 20) n.toInt() else FotosInicio.MAX_MOTIVACION,
            )
        }
    }
}
