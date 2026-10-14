package com.pumpteam.mypump.reglas

/** Lo que devuelve la validación de un formulario: los datos listos para mandar, o el mensaje de error de la web. */
sealed interface Formulario<out T> {
    data class Valido<T>(val datos: T) : Formulario<T>

    data class Invalido(val mensaje: String) : Formulario<Nothing>

    /** Los datos, o null si no pasó la validación. */
    fun datosONull(): T? = (this as? Valido<T>)?.datos
}

/**
 * Un número que escribe el cliente en un campo: acepta coma o punto decimal ("1,5" y "1.5"), con espacios alrededor.
 * Vacío, ilegible o infinito es null. (La web usa `parseFloat`, que con "1,5" lee 1: en el teclado numérico de un
 * teléfono en castellano la coma es lo normal, así que acá vale.)
 */
fun leerNumeroEscrito(texto: String): Double? {
    val t = texto.trim { it == '\t' || Character.getType(it) == Character.SPACE_SEPARATOR.toInt() }.replace(',', '.')
    if (!NUMERO_DECIMAL.matches(t)) return null
    return t.toDouble().takeIf { it.isFinite() }
}

private val NUMERO_DECIMAL = Regex("[+-]?(?:[0-9]+(?:\\.[0-9]*)?|\\.[0-9]+)(?:[eE][+-]?[0-9]+)?")
