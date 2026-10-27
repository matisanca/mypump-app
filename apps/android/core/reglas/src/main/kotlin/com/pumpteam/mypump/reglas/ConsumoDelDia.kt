package com.pumpteam.mypump.reglas

import com.pumpteam.mypump.modelos.Alimento
import com.pumpteam.mypump.modelos.Comida
import com.pumpteam.mypump.modelos.ComidaLibre
import com.pumpteam.mypump.modelos.ComidaMarcada
import com.pumpteam.mypump.modelos.Macros
import com.pumpteam.mypump.modelos.ValorJson
import kotlin.math.max

/**
 * Lo que el cliente marcó de una comida hoy: «✓ Comí» o «✗ Salté» (DIE-05) y, si la comió, qué alimentos dejó (DIE-06).
 * Una por (cliente, fecha, comida) en `mypump_comidas_marcadas`, la misma que escribe la web. Volvió en D25 (27-oct): los
 * clientes de 2.0.x no podían seguir lo que comían ni ver las calorías del día. Gemelo de `MarcaComida` de iOS (mismo
 * JSON en disco).
 */
class MarcaComida(
    /**
     * El nombre de la opción con que se marcó (el de la opción, o su letra si no tiene): lo comido se cuenta con esa,
     * aunque después se mire otra.
     */
    val opcion: String?,
    val estado: Estado,
    excluidos: List<Int> = emptyList(),
) {
    enum class Estado(val valor: String) {
        COMIDO("comido"), SALTADO("saltado");

        companion object {
            fun desde(s: String?): Estado? = entries.firstOrNull { it.valor == s }
        }
    }

    /** Los alimentos de esa opción que NO comió (índices), sin repetir y en orden. */
    val excluidos: List<Int> = excluidos.filter { it >= 0 }.distinct().sorted()

    fun aValor(): ValorJson = ValorJson.objeto(
        "opcion" to (opcion?.let { ValorJson.Texto(it) } ?: ValorJson.Nulo),
        "estado" to ValorJson.Texto(estado.valor),
        "excluidos" to ValorJson.Lista(excluidos.map { ValorJson.Numero(it.toDouble()) }),
    )

    override fun equals(other: Any?): Boolean =
        other is MarcaComida && other.opcion == opcion && other.estado == estado && other.excluidos == excluidos

    override fun hashCode(): Int = (opcion.hashCode() * 31 + estado.hashCode()) * 31 + excluidos.hashCode()

    override fun toString(): String = "MarcaComida($opcion, ${estado.valor}, $excluidos)"

    companion object {
        /** La fila del servidor. Un estado que no es «comido» ni «saltado» no es una marca (la web tampoco la cuenta). */
        fun desde(fila: ComidaMarcada): MarcaComida? =
            Estado.desde(fila.estado)?.let { MarcaComida(fila.opcionElegida, it, fila.foodsExcluidos) }

        /** Lo que guardó el teléfono (el de iOS: una lista rota no tira la marca). */
        fun desde(v: ValorJson?): MarcaComida? {
            val o = v as? ValorJson.Objeto ?: return null
            val e = Estado.desde((o["estado"] as? ValorJson.Texto)?.valor) ?: return null
            val excl = (o["excluidos"] as? ValorJson.Lista)?.elementos?.let { l ->
                val n = l.map { (it as? ValorJson.Numero)?.valor }
                if (n.all { it != null && it.isFinite() && it == Math.floor(it) }) n.map { it!!.toInt() } else null
            }.orEmpty()
            return MarcaComida((o["opcion"] as? ValorJson.Texto)?.valor, e, excl)
        }
    }
}

/**
 * «Consumido hoy» (DIE-07): lo comido según las marcas, contra el objetivo del día. Es `calcularConsumido` de la web
 * (vectores en `apps/shared/vectores/consumo_dia.json`) más lo que la web no conoce: los ajustes del día de D22
 * (`consumo_dia_ajustes.json`, que genera iOS). Gemelo de `ConsumoDelDia` de iOS.
 */
object ConsumoDelDia {
    data class Consumo(
        val kcal: Double = 0.0,
        val prot: Double = 0.0,
        val carb: Double = 0.0,
        val fat: Double = 0.0,
        /** Las comidas del día que cuentan: todas menos las que hoy no come («Hoy no la como»). */
        val comidas: Int = 0,
        /** Cuántas de esas marcó «Comí» y cuántas «Salté». */
        val hechas: Int = 0,
        val salteadas: Int = 0,
    ) {
        val macros: Macros get() = Macros(kcal, prot, carb, fat)

        /** Las que todavía no marcó. */
        val pendientes: Int get() = max(0, comidas - hechas - salteadas)
    }

    /** La letra de una opción (0 = A). */
    fun letra(i: Int): String = ('A'.code + i.coerceIn(0, 25)).toChar().toString()

    /**
     * El nombre con que se guarda la opción `i` al marcar: el suyo (como la web), o su letra si no tiene. La web guarda «A»
     * para cualquier opción sin nombre (3 de 100 dietas publicadas): acá, la letra de la que se ve.
     */
    fun nombreOpcion(c: Comida, i: Int): String = c.opciones.getOrNull(i)?.nombre?.takeIf { it.isNotEmpty() } ?: letra(i)

    /**
     * La opción de una marca: la primera con ese nombre (como la web); si ninguna se llama así, la opción sin nombre con esa
     * letra (la marcó una app); si no, la A.
     */
    fun indiceOpcion(c: Comida, nombre: String?): Int {
        if (nombre.isNullOrEmpty()) return 0
        c.opciones.indexOfFirst { it.nombre == nombre }.takeIf { it >= 0 }?.let { return it }
        c.opciones.indices.firstOrNull { c.opciones[it].nombre.isNullOrEmpty() && letra(it) == nombre }?.let { return it }
        return 0
    }

    /** La opción que hay que mostrar de una comida sin elegir otra: la que comió, si la marcó «Comí». */
    fun opcionDeLaMarca(c: Comida, m: MarcaComida?): Int? =
        if (m?.estado == MarcaComida.Estado.COMIDO) indiceOpcion(c, m.opcion) else null

    /** Las marcas por comida desde las filas del servidor (si una comida viene dos veces, vale la última, como la web). */
    fun marcas(filas: List<ComidaMarcada>): Map<String, MarcaComida> {
        val r = LinkedHashMap<String, MarcaComida>()
        for (f in filas) {
            if (f.comidaId.isEmpty()) continue
            val m = MarcaComida.desde(f)
            if (m != null) r[f.comidaId] = m else r.remove(f.comidaId)
        }
        return r
    }

    /**
     * Lo comido hoy.
     * - Las marcadas «Comí» con la opción de la marca, con sus reemplazos (`efectivo`) y, si hoy hay ajustes, con las
     *   porciones de hoy (lo que le pasan las anteriores incluido), menos los alimentos que destildó.
     * - «Salté» no suma. Las que hoy no come no suman ni cuentan entre las comidas, aunque tengan marca (la web no conoce
     *   los ajustes: ahí cuentan).
     * - Más las comidas libres del día.
     * `vistas` es la opción que se ve de cada comida (las no comidas también importan: lo que se compensa de una a la
     * siguiente depende de la opción). Sin ajustes, es exactamente lo de la web, con las sumas en el mismo orden.
     */
    fun calcular(
        comidas: List<Comida>,
        marcas: Map<String, MarcaComida>,
        libres: List<ComidaLibre>,
        ajustes: Map<String, AjusteComida> = emptyMap(),
        vistas: Map<String, Int> = emptyMap(),
        efectivo: (comidaId: String, opcion: Int, idx: Int, original: Alimento) -> Alimento = { _, _, _, a -> a },
    ): Consumo {
        val delDia = comidas.map { c ->
            val elegida = opcionDeLaMarca(c, marcas[c.id]) ?: vistas[c.id] ?: ajustes[c.id]?.opcion ?: 0
            val o = if (c.opciones.isEmpty()) 0 else elegida.coerceIn(0, c.opciones.size - 1)
            val alimentos = c.opciones.getOrNull(o)?.alimentos.orEmpty().mapIndexed { i, a -> efectivo(c.id, o, i, a) }
            AjustePorciones.ComidaDelDia(c.id, c.nombre ?: "", o, alimentos)
        }
        val ajustadas = if (ajustes.isEmpty()) emptyMap() else AjustePorciones.dia(delDia, ajustes)
        var kcal = 0.0
        var prot = 0.0
        var carb = 0.0
        var fat = 0.0
        var n = 0
        var hechas = 0
        var salteadas = 0
        for (c in delDia) {
            if (ajustes[c.id]?.omitida == true) continue
            n++
            val m = marcas[c.id] ?: continue
            if (m.estado != MarcaComida.Estado.COMIDO) { salteadas++; continue }
            hechas++
            val excluidos = m.excluidos.toSet()
            (ajustadas[c.id]?.alimentos ?: c.alimentos).forEachIndexed { i, a ->
                if (i in excluidos) return@forEachIndexed
                kcal += a.kcal ?: 0.0
                prot += a.prot ?: 0.0
                carb += a.carb ?: 0.0
                fat += a.fat ?: 0.0
            }
        }
        for (l in libres) {
            kcal += l.kcal ?: 0.0
            prot += l.prot ?: 0.0
            carb += l.carb ?: 0.0
            fat += l.fat ?: 0.0
        }
        return Consumo(kcal, prot, carb, fat, n, hechas, salteadas)
    }
}
