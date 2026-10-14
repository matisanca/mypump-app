package com.pumpteam.mypump.reglas

import com.pumpteam.mypump.modelos.Alimento
import com.pumpteam.mypump.modelos.NumeroJs
import com.pumpteam.mypump.modelos.TextoJs
import com.pumpteam.mypump.modelos.ValorJson

/**
 * Un swap de comida está ANCLADO al alimento que reemplaza, no a su posición. Port de `_huellaFood` y `_swapAplicable`
 * (cliente.html:1990-2015).
 *
 * La clave del swap es posicional (comida, opción, índice) y `mypump_publicar_cliente` conserva el `dieta_id`: si Mati
 * agrega un alimento antes, el swap caería sobre otro (la leche de Alejandro Romero, 28-ago). Por eso cada swap guarda
 * en `food_data._orig` lo que reemplazó, y solo se aplica si lo que hay hoy en esa posición es eso — o el mismo alimento
 * con la cantidad de OTRO tipo de día ("Avena 80 g" entreno / "Avena 50 g" descanso).
 */
object AnclajeSwaps {
    /** `nombre|qty|unidad`, en minúsculas y sin espacios en los bordes. La qty como la imprime JS (`Number(x) || 0`). */
    fun huella(nombre: String?, qty: Double?, unidad: String?): String {
        val n = TextoJs.recortar(nombre ?: "").lowercase()
        val u = TextoJs.recortar(unidad ?: "").lowercase()
        return "$n|${numeroJs(qty)}|$u"
    }

    fun huella(a: Alimento): String = huella(a.nombre, a.qty, a.unidad)

    /** La huella del ancla `_orig` (viene del servidor tal cual: el nombre o la qty pueden ser número o texto). */
    fun huella(ancla: ValorJson): String =
        huella(SemanticaJs.texto(ancla["name"]), SemanticaJs.numero(ancla["qty"]), SemanticaJs.texto(ancla["unit"]))

    /**
     * ¿El swap (su `food_data`) se aplica al alimento que se está mostrando?
     *
     * @param comidaId null cuando no se conoce la posición (en la web, `comidaId == null`).
     * @param enPosicion los alimentos de esa misma posición en TODOS los tipos de día.
     */
    fun aplica(foodData: ValorJson?, original: Alimento, comidaId: String?, enPosicion: () -> List<Alimento>): Boolean {
        // `!swap.current`: null, false, 0 o "" no son un swap.
        if (!SemanticaJs.esVerdadero(foodData)) return false
        val ancla = foodData!!["_orig"]
        if (!SemanticaJs.esVerdadero(ancla)) return true   // legado: sin ancla, se aplica
        val h = huella(ancla!!)
        if (h == huella(original)) return true
        if (comidaId == null) return false
        val nombre = { s: String? -> TextoJs.recortar(s ?: "").lowercase() }
        if (nombre(SemanticaJs.texto(ancla["name"])) != nombre(original.nombre)) return false
        return enPosicion().any { huella(it) == h }
    }

    /** Cómo imprime JS `Number(qty) || 0`: NaN, null y 0 son "0"; el resto con su representación más corta. */
    fun numeroJs(d: Double?): String = if (d == null || d.isNaN() || d == 0.0) "0" else NumeroJs.texto(d)
}
