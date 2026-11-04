package com.pumpteam.mypump.reglas

import com.pumpteam.mypump.modelos.CompraSuplemento
import com.pumpteam.mypump.modelos.ItemSuplemento
import com.pumpteam.mypump.modelos.Suplementacion
import java.text.Normalizer
import java.util.Locale

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
     * Cuándo se toma en la semana (la regla de `ReglasSuplementacion.textoDias` de iOS, con los mismos vectores:
     * `apps/shared/vectores/texto_dias.json`): null = todos los días («todos», sin `dias` o vacío). `gym` (o `entreno`)
     * = «días de entreno» y `descanso` = «días de descanso», aunque vengan mezclados con días; los días de la semana por
     * su nombre con tilde, aunque vengan abreviados o en mayúsculas («Lunes, miércoles y viernes»). Lo que no se
     * reconoce va tal cual. Sin repetidos, y la primera letra en mayúscula.
     */
    fun textoDias(dias: List<String>): String? {
        val partes = dias.map { it.trim() }.filter { it.isNotEmpty() }
        if (partes.isEmpty() || partes.any { clave(it) == "todos" }) return null
        val textos = mutableListOf<String>()
        for (p in partes) {
            val t = when (clave(p)) {
                "gym", "entreno", "entrenamiento" -> "días de entreno"
                "descanso" -> "días de descanso"
                else -> diaDeLaSemana(p) ?: p
            }
            if (t !in textos) textos += t
        }
        val junto = if (textos.size > 1) textos.dropLast(1).joinToString(", ") + " y " + textos.last() else textos[0]
        return junto.substring(0, 1).uppercase() + junto.substring(1)
    }

    private val semana = listOf(
        "lunes" to listOf("lunes", "lun", "lu"), "martes" to listOf("martes", "mar", "ma"),
        "miércoles" to listOf("miercoles", "mie", "mi"), "jueves" to listOf("jueves", "jue", "ju"),
        "viernes" to listOf("viernes", "vie", "vi"), "sábado" to listOf("sabado", "sab", "sa"),
        "domingo" to listOf("domingo", "dom", "do"),
    )

    internal fun diaDeLaSemana(s: String): String? {
        val k = clave(s)
        return semana.firstOrNull { k in it.second }?.first
    }

    /** Minúsculas y sin tildes, como el `folding` de iOS. */
    internal fun clave(s: String): String =
        Normalizer.normalize(s.trim(), Normalizer.Form.NFD).replace(MARCAS, "").lowercase(Locale.ROOT)

    private val MARCAS = Regex("\\p{Mn}+")

    /** Una toma del ítem en el detalle: cuándo (el nombre del momento), cuánto y una nota. */
    data class Toma(val cuando: String, val cantidad: String?, val nota: String?)

    /** Lo que muestra la hoja de un ítem. */
    data class Detalle(
        val nombre: String,
        val etiqueta: String?,
        val sale: Boolean,
        val opcional: Boolean,
        val dias: String?,
        /** La dosis, con la anterior si cambió: «200 mg → 400 mg» (ver [dosis]). null si no vino `cantidad` o si sale. */
        val dosis: String?,
        /** Lo que lee TalkBack de [dosis] cuando cambió: «Antes 200 mg, ahora 400 mg». */
        val dosisHablada: String?,
        val tomas: List<Toma>,
        val nota: String?,
        val detalle: List<String>,
        val porQue: String?,
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
            dosis = if (sale) null else dosis(item),
            dosisHablada = if (sale) null else dosisHablada(item),
            tomas = if (sale) emptyList() else tomas,
            nota = item.nota,
            detalle = item.detalle,
            porQue = item.porQue,
            cambio = item.cambio,
            comprar = item.comprar,
        )
    }

    /** La dosis con la anterior, si vino y es distinta: «200 mg → 400 mg» (como `ReglasSuplementacion.dosis` de iOS). */
    fun dosis(item: ItemSuplemento): String? {
        val c = item.cantidad?.takeIf { it.isNotEmpty() } ?: return null
        val a = item.antes?.takeIf { it.isNotEmpty() && it != c } ?: return c
        return "$a → $c"
    }

    /** Lo que lee TalkBack de la dosis: «Antes 200 mg, ahora 400 mg» si cambió; si no, la dosis. */
    fun dosisHablada(item: ItemSuplemento): String? {
        val c = item.cantidad?.takeIf { it.isNotEmpty() } ?: return null
        val a = item.antes?.takeIf { it.isNotEmpty() && it != c } ?: return c
        return "Antes $a, ahora $c"
    }

    /**
     * El ítem del detalle abierto, buscado por su lugar en `items` y confirmado por su nombre: si después de un refresco
     * en ese lugar hay otro suplemento (o ya no hay nada), null y el detalle se cierra.
     */
    fun itemAbierto(items: List<ItemSuplemento>, indice: Int?, nombre: String?): ItemSuplemento? {
        if (indice == null) return null
        return items.getOrNull(indice)?.takeIf { it.nombre == nombre }
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
