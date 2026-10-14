package com.pumpteam.mypump.reglas

import com.pumpteam.mypump.modelos.TextoJs
import java.text.Normalizer

/**
 * La identidad de un ejercicio para el historial: port exacto de `claveEjercicio` (cliente.html:2092), gemela de
 * `mypump_clave_ejercicio` en SQL (072), de `clave_ejercicio` en Python, de `_norm` del Cerebro y de ClaveEjercicio.swift.
 * Si se toca una, se tocan todas.
 *
 * Solo se borra el rango U+0300–U+036F después de NFD, como hace JS: "ø" no es una "o" con tilde y se descarta.
 */
object ClaveEjercicio {
    private val parentesis = JsRegex("\\(.*?\\)")
    private val noAlfanumerico = JsRegex("[^a-z0-9 ]+")
    private val espacios = JsRegex("\\s+")

    fun de(nombre: String?): String {
        var s = Normalizer.normalize((nombre ?: "").lowercase(), Normalizer.Form.NFD)
        s = s.filterNot { it in '̀'..'ͯ' }   // acentos, ñ → n
        s = parentesis.reemplazarTodo(s, " ")           // "(cabeza medial)" es el músculo, no el ejercicio
        s = noAlfanumerico.reemplazarTodo(s, " ")
        s = espacios.reemplazarTodo(s, " ")
        return TextoJs.recortar(s)
    }
}
