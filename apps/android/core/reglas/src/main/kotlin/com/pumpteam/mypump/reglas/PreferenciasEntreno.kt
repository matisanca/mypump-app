package com.pumpteam.mypump.reglas

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
    fun segundos(propio: Int?, plan: Int?): Int = valido(propio) ?: plan ?: NormalizacionRutina.DESCANSO_POR_DEFECTO
}

/**
 * El RIR con el que arranca una serie sin cargar (2.0.3, E4): el objetivo del plan para la semana, así el selector no
 * arranca en 0 (el 48 % de los RIR cargados eran 0, la primera opción). Con un rango («1-2») vale el primer número; con
 * decimales, redondeado hacia arriba; topeado a 5 (el selector va de 0 a 5). Sin objetivo, "" (sin preselección: se
 * guarda null, como siempre). Desvío a propósito de la web, donde el RIR nunca se completa solo (SER-02).
 */
object RirInicial {
    private val numero = Regex("""\d+([.,]\d+)?""")

    fun de(objetivo: String?): String {
        val primero = objetivo?.let { numero.find(it)?.value } ?: return ""
        val n = primero.replace(',', '.').toDoubleOrNull()?.takeIf { it.isFinite() } ?: return ""
        return ceil(n).toInt().coerceIn(0, 5).toString()
    }
}
