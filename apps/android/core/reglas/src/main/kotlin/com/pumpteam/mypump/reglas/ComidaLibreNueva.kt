package com.pumpteam.mypump.reglas

import com.pumpteam.mypump.modelos.EstimacionPlato
import com.pumpteam.mypump.modelos.TextoJs
import com.pumpteam.mypump.modelos.ValorJson
import java.time.Instant
import java.time.ZoneId
import java.util.Locale

/**
 * "Comida libre" fuera del plan (`openComidaLibreModal` / `guardarComidaLibre`, cliente.html:5345-5440): a mano o con la
 * estimación de la foto del plato. La estimación nunca es exacta, así que los gramos de cada alimento se pueden corregir y
 * los macros se re-escalan en proporción; los totales siguen siendo editables a mano.
 */
object ComidaLibreNueva {
    /** Un alimento de la estimación llevado a "por gramo" (`_porGramo`): base para re-escalar. */
    data class Base(
        val nombre: String,
        /** Los gramos que estimó la IA, redondeados (lo que muestra el campo al abrir). */
        val gramosIniciales: Double,
        val kcal: Double,
        val prot: Double,
        val carb: Double,
        val fat: Double,
    )

    data class Totales(val kcal: Double, val prot: Double, val carb: Double, val fat: Double)

    /** Lo que se manda a `mypump_crear_comida_libre` (más la fecha local, que pone el modelo). */
    data class Datos(
        val hora: String?,
        val descripcion: String,
        val kcal: Double,
        val prot: Double,
        val carb: Double,
        val fat: Double,
        val detalle: ValorJson?,
    )

    fun bases(e: EstimacionPlato?): List<Base> = (e?.alimentos ?: emptyList()).map { a ->
        val g = maxOf(1.0, oCero(a.gramos))
        Base(a.nombre ?: "", jsRound(oCero(a.gramos)), oCero(a.kcal) / g, oCero(a.prot) / g, oCero(a.carb) / g, oCero(a.fat) / g)
    }

    /** Los gramos vigentes: lo escrito si es un número ≥ 0, si no los iniciales (`_gramosActuales`). */
    fun gramos(bases: List<Base>, escritos: List<Double?>): List<Double> = bases.mapIndexed { i, b ->
        val v = escritos.getOrNull(i)
        if (v != null && v.isFinite() && v >= 0) v else b.gramosIniciales
    }

    /** `_recalcularDesdeGramos`: kcal enteras, macros con un decimal. */
    fun totales(bases: List<Base>, gramos: List<Double>): Totales {
        var kcal = 0.0
        var prot = 0.0
        var carb = 0.0
        var fat = 0.0
        for ((b, g) in bases.zip(gramos)) {
            kcal += b.kcal * g
            prot += b.prot * g
            carb += b.carb * g
            fat += b.fat * g
        }
        return Totales(jsRound(kcal), r1(prot), r1(carb), r1(fat))
    }

    /** El `detalle` que se guarda: los gramos YA corregidos por el cliente, con sus macros re-escalados. */
    fun detalle(bases: List<Base>, gramos: List<Double>, confianza: String?, escala: String?): ValorJson? {
        if (bases.isEmpty()) return null
        val alimentos = bases.zip(gramos).map { (b, g) ->
            ValorJson.objeto(
                "nombre" to ValorJson.Texto(b.nombre), "gramos" to ValorJson.Numero(jsRound(g)),
                "kcal" to ValorJson.Numero(jsRound(b.kcal * g)), "prot" to ValorJson.Numero(r1(b.prot * g)),
                "carb" to ValorJson.Numero(r1(b.carb * g)), "fat" to ValorJson.Numero(r1(b.fat * g)),
            )
        }
        return ValorJson.objeto("alimentos" to ValorJson.Lista(alimentos), "confianza" to vacioANull(confianza), "escala" to vacioANull(escala))
    }

    /** Al guardar: descripción obligatoria y al menos kcal o un macro. Negativos y vacíos valen 0. */
    fun preparar(
        descripcion: String,
        hora: String?,
        kcal: Double?,
        prot: Double?,
        carb: Double?,
        fat: Double?,
        detalle: ValorJson?,
    ): Formulario<Datos> {
        val d = TextoJs.recortar(descripcion)
        fun num(x: Double?) = if (x != null && x.isFinite() && x > 0) x else 0.0
        val k = num(kcal)
        val p = num(prot)
        val c = num(carb)
        val f = num(fat)
        if (d.isEmpty()) return Formulario.Invalido("Contá qué comiste.")
        if (k <= 0 && p <= 0 && c <= 0 && f <= 0) return Formulario.Invalido("Cargá al menos las calorías o algún macro.")
        return Formulario.Valido(Datos(hora?.takeIf { it.isNotEmpty() }, d, k, p, c, f, detalle))
    }

    /** "HH:MM" de un instante en la zona dada (el valor por defecto del campo hora). */
    fun hora(instante: Instant, zona: ZoneId = ZoneId.systemDefault()): String {
        val t = instante.atZone(zona)
        return String.format(Locale.ROOT, "%02d:%02d", t.hour, t.minute)
    }

    private fun oCero(x: Double?) = SemanticaJs.oCero(x)
    private fun r1(v: Double) = jsRound(v * 10) / 10
    private fun vacioANull(s: String?): ValorJson = if (s.isNullOrEmpty()) ValorJson.Nulo else ValorJson.Texto(s)
}

/**
 * La fecha local "YYYY-MM-DD" (`hoyLocal()` de la web): el servidor acepta de −7 a +1 días respecto de la suya, así que
 * marcar o registrar no se "corre de día" en otra zona horaria. Siempre con dígitos ASCII, aunque el teléfono esté en un
 * idioma que use otros.
 */
object FechaLocal {
    fun hoy(ahora: Instant = Instant.now(), zona: ZoneId = ZoneId.systemDefault()): String {
        val d = ahora.atZone(zona)
        return String.format(Locale.ROOT, "%04d-%02d-%02d", d.year, d.monthValue, d.dayOfMonth)
    }
}
