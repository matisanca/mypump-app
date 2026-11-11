package com.pumpteam.mypump.reglas

/**
 * «Mi salud» (pedido de Mati del 11/11): una sola pantalla con todo lo de salud, que se abre desde Revisión sin sumar
 * pestañas. Acá solo se decide qué bloques van, qué dice la tarjeta de Revisión y a qué bloque lleva cada destino viejo.
 * Cada bloque va solo si su palanca o su condición de hoy lo muestra (las mismas de antes: acá no hay palancas nuevas).
 * Los mismos textos en iPhone y Android (`nativa-evidencia/mi-salud/DECISIONES.md`).
 */
object MiSalud {
    const val TITULO = "Mi salud"

    /** Los bloques, en el orden de la pantalla. */
    enum class Bloque(val nombre: String) {
        CONTROL("control"),
        ESTUDIOS("estudios"),
        PRESION("presión"),
        RECUPERACION("recuperación");

        /** Para las pruebas y las herramientas que leen la pantalla (`mi-salud-bloque-presion`). */
        val etiqueta: String get() = "mi-salud-bloque-${name.lowercase()}"
    }

    /** Lo que se sabe hoy de cada parte. */
    data class Partes(
        /** Hay «Próximo control» en Estudios. */
        val control: Boolean = false,
        /** La sección Estudios existe (palanca prendida, servidor nuevo, habilitada). */
        val estudios: Boolean = false,
        /** La sección Presión está habilitada. */
        val presion: Boolean = false,
        /** La recuperación (Salud) se puede abrir: como estaba en Revisión, siempre. */
        val recuperacion: Boolean = true,
    )

    /** Qué pide hoy cada parte (lo de las tarjetas del inicio). null o false: nada. */
    data class Pendientes(
        /** El texto de la tarjeta de estudios del inicio (novedad o algo por hacer). */
        val estudios: String? = null,
        /** El control de salud está cerca (la tarjeta del control del inicio se ve). */
        val control: Boolean = false,
        /** La línea de presión cuando pide algo; null si no pide nada (o ya hizo la de hoy). */
        val presion: String? = null,
    )

    fun bloques(p: Partes): List<Bloque> = buildList {
        if (p.control) add(Bloque.CONTROL)
        if (p.estudios) add(Bloque.ESTUDIOS)
        if (p.presion) add(Bloque.PRESION)
        if (p.recuperacion) add(Bloque.RECUPERACION)
    }

    /** La tarjeta de Revisión: sin ningún bloque no existe. [bloque]: el de lo primero pendiente (a donde lleva tocarla). */
    data class Tarjeta(val linea: String, val cuenta: Int, val bloque: Bloque? = null)

    const val CONTROL_CERCA = "Tu próximo control de salud"
    const val REPETIR_PRESION = "Te falta repetir la toma de presión"
    const val PREPARAR_PRESION = "Primero medí tu brazo y anotá tu tensiómetro"
    fun faltanTomas(n: Int): String = if (n == 1) "Te falta 1 toma de presión" else "Te faltan $n tomas de presión"

    /** La fila del bloque de presión que abre la pantalla de Presión (la guía y las tomas). */
    const val VER_PRESION = "Ver mis tomas y cómo medirme"

    /** La fila de Mis datos y lo que lee TalkBack de la tarjeta. */
    const val ABRE = "Abre Mi salud"

    fun tarjeta(p: Partes, pendientes: Pendientes): Tarjeta? {
        val bloques = bloques(p)
        if (bloques.isEmpty()) return null
        val lineas = listOfNotNull(
            pendientes.estudios?.takeIf { p.estudios }?.let { it to Bloque.ESTUDIOS },
            CONTROL_CERCA.takeIf { pendientes.control && (p.control || p.estudios) }?.let { it to (if (p.control) Bloque.CONTROL else Bloque.ESTUDIOS) },
            pendientes.presion?.takeIf { p.presion }?.let { it to Bloque.PRESION },
        )
        val primero = lineas.firstOrNull()
        return Tarjeta(primero?.first ?: lista(bloques), lineas.size, primero?.second)
    }

    /** La ceja de la tarjeta verde de arriba de Entreno (simplificar, 11/11). */
    const val CEJA_INICIO = "Mi salud"

    /**
     * El botón de la tarjeta de Entreno cuando lo primero es el control y lleva al bloque «Próximo control». Sin ese bloque
     * lleva a Estudios y dice «Ver mis estudios», como la tarjeta vieja. Igual en iOS y la web.
     */
    const val VER_MI_CONTROL = "Ver mi control"

    /** Debajo de la línea, con más de una cosa: «Y 1 cosa más» / «Y 2 cosas más». null con una sola. */
    fun masCosas(cuenta: Int): String? = when {
        cuenta <= 1 -> null
        cuenta == 2 -> "Y 1 cosa más"
        else -> "Y ${cuenta - 1} cosas más"
    }

    /** «Control, estudios, presión y recuperación». */
    fun lista(bloques: List<Bloque>): String {
        val nombres = bloques.map { it.nombre }
        val texto = when (nombres.size) {
            0 -> ""
            1 -> nombres[0]
            else -> nombres.dropLast(1).joinToString(", ") + " y " + nombres.last()
        }
        return texto.replaceFirstChar { it.uppercase() }
    }
}
