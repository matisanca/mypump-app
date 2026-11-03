package com.pumpteam.mypump.reglas

import com.pumpteam.mypump.modelos.Ejercicio
import kotlin.math.ceil

/**
 * El descanso elegido a mano para un ejercicio (2.0.3, E2; gemelo de PreferenciasEntreno.swift): tocar el descanso del
 * ejercicio abre un selector de 0:30 a 5:00 en pasos de 15 s. Lo elegido vive en el teléfono, por la clave del ejercicio
 * que se hace ([ClaveEjercicio]), y le gana al `descanso_segundos` del plan. Lo verifican los vectores de
 * `apps/shared/vectores/entreno_203.json`.
 */
object DescansoPropio {
    const val MINIMO = 30
    const val MAXIMO = 300
    const val PASO = 15

    /** 0:30, 0:45 … 5:00. */
    val opciones: List<Int> = (MINIMO..MAXIMO step PASO).toList()

    /** Lo elegido vale si es una de las opciones (un archivo viejo o tocado no mete un descanso de 0 ni de una hora). */
    fun valido(s: Int?): Int? = s?.takeIf { it in opciones }

    /** El descanso que se usa: el propio si hay, si no el del plan (que `normalizarRutina` ya completó con 90). */
    /**
     * «Usar» del selector: lo que se guarda, o null para no tocar nada. Lo elegido se guarda aunque sea igual al del plan:
     * el propio solo se borra con «Volver al del plan». Si no había propio, la rueda no se movió y el del plan no es una
     * de las opciones (la rueda arrancó en la más cercana), no se guarda nada.
     */
    fun alUsar(seleccion: Int, inicial: Int, plan: Int, propio: Boolean): Int? {
        if (!propio && seleccion == inicial && valido(plan) == null) return null
        return valido(seleccion)
    }

    fun segundos(propio: Int?, plan: Int?): Int = valido(propio) ?: plan ?: NormalizacionRutina.DESCANSO_POR_DEFECTO
}

/**
 * El RIR que se guarda sin preguntarlo (2.0.3, gemelo de `RIRDelPlan` en PreferenciasEntreno.swift): las series
 * efectivas van al fallo y la app ya no muestra el RIR, pero la recuperación cuenta las «series duras» con `rir_real`
 * ≤ 2 (todo null la apaga). Al confirmar se guarda el objetivo del plan para la semana: el primer número del rango
 * (redondeado hacia arriba, entre 0 y 5); sin objetivo o sin número, 0. La leyenda debajo de «Series efectivas» es
 * «Al fallo» o «Dejando 1–2 en reserva» con el rango del plan. Vectores: `entreno_203.json`, sección `rir`.
 */
object RirDelPlan {
    private val numero = Regex("""\d+([.,]\d+)?""")
    private val rango = Regex("""\d+([.,]\d+)?(\s*[-–]\s*\d+([.,]\d+)?)?""")

    /** Un objetivo en RPE no es RIR: se toma como al fallo. */
    private val rpe = Regex("rpe", RegexOption.IGNORE_CASE)

    /** ¿La serie lleva RIR? No el calentamiento, el cardio, el core ni lo que va sin peso (plancha, abdominales): null. */
    fun lleva(ex: Ejercicio): Boolean =
        ex.tipo !in setOf("calentamiento", "cardio", "core") && !ReglasEjercicio.esSinPeso(ex.nombre, ex.tipo, ex.equipo)

    /** El aviso de primera vez con la leyenda en lugar de «dejando 1–2 en reserva». */
    fun calibracion(texto: String, leyenda: String?): String {
        val l = leyenda ?: return texto
        val frase = if (l == "Al fallo") "al fallo" else l.replaceFirstChar { it.lowercase() }
        return texto.replace("dejando 1–2 en reserva", frase)
    }

    fun guardar(objetivo: String?): String {
        if (objetivo != null && rpe.containsMatchIn(objetivo)) return "0"
        val primero = objetivo?.let { numero.find(it)?.value } ?: return "0"
        val n = primero.replace(',', '.').toDoubleOrNull()?.takeIf { it.isFinite() } ?: return "0"
        return ceil(n).toInt().coerceIn(0, 5).toString()
    }

    fun leyenda(objetivo: String?): String {
        if (objetivo != null && rpe.containsMatchIn(objetivo)) return "Al fallo"
        val r = objetivo?.let { rango.find(it)?.value } ?: return "Al fallo"
        val numeros = numero.findAll(r).mapNotNull { it.value.replace(',', '.').toDoubleOrNull() }.toList()
        if (numeros.all { it == 0.0 }) return "Al fallo"
        val partes = r.split('-', '–').map { it.trim().replace('.', ',') }
        return "Dejando ${partes.joinToString("–")} en reserva"
    }
}
