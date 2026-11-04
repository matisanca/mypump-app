package com.pumpteam.mypump.reglas

import com.pumpteam.mypump.modelos.CompraSuplemento
import com.pumpteam.mypump.modelos.ItemSuplemento
import com.pumpteam.mypump.modelos.Suplementacion

/**
 * Los textos de la pestaña Suplementación (2.1.0) que no están en «Tu guía»: la etiqueta del estado, los días y lo que
 * muestra el detalle de un ítem. La agrupación por momento es la misma de la guía ([SuplementacionVista.armar]), así las
 * dos muestran el mismo día. Los textos visibles son los mismos de iOS.
 */
object SuplementacionPestana {
    /**
     * La etiqueta del estado (contrato, sección 10): sin estado = `nuevo`. `sigue` no lleva etiqueta y `sale` va en
     * «Dejás de tomar». Un estado desconocido tampoco lleva (se compara exacto, como la guía).
     */
    fun etiquetaEstado(estado: String?): String? = when (estado ?: "nuevo") {
        "nuevo" -> "Nuevo"
        "cambia" -> "Cambia"
        "sube" -> "Sube"
        "baja" -> "Baja"
        "vuelve" -> "Vuelve"
        else -> null
    }

    /**
     * Cuándo se toma en la semana: null = todos los días («todos» o sin `dias`). `gym` = «Días de entreno», `descanso` =
     * «Días de descanso»; los días de la semana, tal cual vinieron y unidos («Lunes, miércoles y viernes»).
     */
    fun textoDias(dias: List<String>): String? {
        val l = dias.map { it.trim() }.filter { it.isNotEmpty() }
        if (l.isEmpty() || l.any { it.equals("todos", ignoreCase = true) }) return null
        if (l.size == 1) {
            when (l[0].lowercase()) {
                "gym" -> return "Días de entreno"
                "descanso" -> return "Días de descanso"
            }
        }
        val unidos = if (l.size == 1) l[0] else l.dropLast(1).joinToString(", ") + " y " + l.last()
        return unidos.substring(0, 1).uppercase() + unidos.substring(1)
    }

    /** Una toma del ítem en el detalle: cuándo (el nombre del momento), cuánto y una nota. */
    data class Toma(val cuando: String, val cantidad: String?, val nota: String?)

    /** Lo que muestra la hoja de un ítem. */
    data class Detalle(
        val nombre: String,
        val etiqueta: String?,
        val sale: Boolean,
        val opcional: Boolean,
        val dias: String?,
        /** La cantidad de una sola toma, o null si son varias (van en [tomas]). */
        val cantidad: String?,
        val tomas: List<Toma>,
        val nota: String?,
        val detalle: List<String>,
        val porQue: String?,
        /** `antes` → `cantidad`, solo si vino `antes`. */
        val antes: String?,
        val ahora: String?,
        val cambio: String?,
        val comprar: CompraSuplemento?,
    )

    fun detalle(item: ItemSuplemento, s: Suplementacion): Detalle {
        val sale = item.estado == "sale"
        val tomas = when {
            item.tomas.isNotEmpty() -> item.tomas.map { Toma(SuplementacionVista.tituloMomento(it.momento, s), it.cantidad, it.nota) }
            // Una sola toma: la cantidad y la nota ya van arriba, acá solo el momento.
            else -> item.momento?.let { listOf(Toma(SuplementacionVista.tituloMomento(it, s), null, null)) }.orEmpty()
        }
        return Detalle(
            nombre = item.nombre,
            // En el detalle «sigue» sí lleva etiqueta (en la lista no).
            etiqueta = if (sale) null else if (item.estado == "sigue") "Sigue igual" else etiquetaEstado(item.estado),
            sale = sale,
            opcional = item.opcional,
            dias = textoDias(item.dias),
            cantidad = if (item.tomas.isEmpty()) item.cantidad else null,
            tomas = if (sale) emptyList() else tomas,
            nota = item.nota,
            detalle = item.detalle,
            porQue = item.porQue,
            antes = item.antes,
            ahora = item.antes?.let { item.cantidad },
            cambio = item.cambio,
            comprar = item.comprar,
        )
    }

    /** Lo que lee TalkBack en una fila del día: todo en una sola frase, con «Abre el detalle» como acción. */
    fun descripcionFila(f: SuplementacionVista.Fila): String = listOfNotNull(
        f.nombre,
        f.cantidad,
        etiquetaEstado(f.item.estado),
        "Opcional".takeIf { f.opcional },
        textoDias(f.item.dias),
        f.nota,
    ).joinToString(", ")
}
