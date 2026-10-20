package com.pumpteam.mypump.reglas

import com.pumpteam.mypump.modelos.Alimento
import com.pumpteam.mypump.modelos.ValorJson
import kotlin.math.abs

/**
 * El alimento al que se le puso una cantidad a mano. La dieta se vuelve a publicar con el mismo id (013): si en esa
 * posición queda otro alimento u otra unidad, la cantidad no vale (60 g de avena no son 60 g de aceite).
 */
data class AnclaAlimento(val nombre: String, val unidad: String?) {
    constructor(a: Alimento) : this(a.nombre, a.unidad)

    /** El mismo alimento: el nombre sin espacios de más ni mayúsculas, y la misma unidad (g, gr y gramos son una). */
    fun coincide(con: Alimento): Boolean = normal(nombre) == normal(con.nombre) && unidadNormal(unidad) == unidadNormal(con.unidad)

    fun aValor(): ValorJson = ValorJson.objeto("nombre" to ValorJson.Texto(nombre), "unidad" to (unidad?.let { ValorJson.Texto(it) } ?: ValorJson.Nulo))

    companion object {
        internal fun normal(s: String): String = s.trim().lowercase()

        internal fun unidadNormal(u: String?): String {
            val n = normal(u ?: "")
            if (n in setOf("", "g", "gr", "grs", "gramo", "gramos")) return "g"
            if (n == "cc") return "ml"
            return n
        }

        fun desde(v: ValorJson?): AnclaAlimento? {
            val o = v as? ValorJson.Objeto ?: return null
            val nombre = o["nombre"]?.comoTexto ?: return null
            val unidad = when (val u = o["unidad"]) {
                null, ValorJson.Nulo -> null
                is ValorJson.Texto -> u.valor
                else -> return null
            }
            return AnclaAlimento(nombre, unidad)
        }
    }
}

/**
 * Lo que el cliente cambió de una comida en un día (feedback del 20-oct: «si tengo más hambre en una comida, agregar
 * cuántas calorías más quiero y que recalcule las porciones; después restarlas en la siguiente», y Emilio García
 * Álvarez: «hoy no fui a entrenar, saco el pre-entreno… cómo puedo jugar con los gramos»). No es «Comí / Salté» (D10):
 * es el plan del día, ajustado por el cliente. Gemelo de `AjusteComida` de iOS (mismo JSON).
 */
data class AjusteComida(
    /** Kcal que se suman (o restan) a esta comida, de a [AjustePorciones.PASO]. */
    val deltaKcal: Int = 0,
    /** Lo que esta comida se aparta del plan se compensa en la siguiente. */
    val compensar: Boolean = true,
    /** Hoy no la come. */
    val omitida: Boolean = false,
    /** La opción (0 = A) a la que aplican las cantidades a mano: si el cliente cambia de opción, no valen. */
    val opcion: Int = 0,
    /** Cantidades puestas a mano, por índice del alimento en la opción, en la unidad del plan (g o unidades). */
    val cantidades: Map<String, Double> = emptyMap(),
    /** A qué alimento corresponde cada cantidad (las pone [AjustePorciones.anclar] al guardar). Sin ancla, vale. */
    val anclas: Map<String, AnclaAlimento> = emptyMap(),
) {
    /** Sin nada que cambie la comida: se borra. */
    val neutro: Boolean get() = deltaKcal == 0 && cantidades.isEmpty() && !omitida

    fun aValor(): ValorJson = ValorJson.objeto(
        "deltaKcal" to ValorJson.Numero(deltaKcal.toDouble()),
        "compensar" to ValorJson.Booleano(compensar),
        "omitida" to ValorJson.Booleano(omitida),
        "opcion" to ValorJson.Numero(opcion.toDouble()),
        "cantidades" to ValorJson.Objeto(cantidades.mapValues { ValorJson.Numero(it.value) }),
        "anclas" to ValorJson.Objeto(anclas.mapValues { it.value.aValor() }),
    )

    companion object {
        /**
         * Tolerante como el de iOS: lo que falta o no es del tipo, por defecto; las cantidades negativas o no finitas,
         * afuera. Un mapa con algo que no se entiende se descarta entero (como el `Decodable` de Swift).
         */
        fun desde(v: ValorJson?): AjusteComida? {
            val o = v as? ValorJson.Objeto ?: return null
            // Con topes (una fila rota no puede dar una comida de un millón de kcal ni una opción que no existe): lo que no
            // entra vale por defecto, igual en iOS.
            fun entero(k: String, def: Int, rango: IntRange): Int =
                o[k]?.comoNumero?.takeIf { it.isFinite() && it == Math.floor(it) && it >= rango.first && it <= rango.last }?.toInt() ?: def
            fun booleano(k: String, def: Boolean): Boolean = (o[k] as? ValorJson.Booleano)?.valor ?: def
            val cantidades = (o["cantidades"] as? ValorJson.Objeto)?.campos?.let { m ->
                if (m.values.all { it is ValorJson.Numero }) m.mapValues { (it.value as ValorJson.Numero).valor } else null
            }.orEmpty().filterValues { it.isFinite() && it >= 0 }
            val anclas = (o["anclas"] as? ValorJson.Objeto)?.campos?.let { m ->
                val r = m.mapValues { AnclaAlimento.desde(it.value) }
                if (r.values.all { it != null }) r.mapValues { it.value!! } else null
            }.orEmpty()
            return AjusteComida(
                entero("deltaKcal", 0, -30000..30000), booleano("compensar", true), booleano("omitida", false), entero("opcion", 0, 0..99),
                cantidades, anclas,
            )
        }
    }
}

/**
 * Las porciones de una comida (y del día) con los ajustes del cliente. Puro: lo usan las pantallas y los tests, igual
 * que `AjustePorciones` de iOS (vectores en `apps/shared/vectores/ajuste_porciones.json`).
 */
object AjustePorciones {
    /** De a cuánto se suma o se resta. */
    const val PASO = 50

    /**
     * Ni menos de un cuarto ni más del triple de lo del plan: más allá ya no es la misma comida (para no comerla, «Hoy no
     * la como»).
     */
    const val FACTOR_MINIMO = 0.25
    const val FACTOR_MAXIMO = 3.0

    data class ComidaDelDia(
        val id: String,
        val nombre: String,
        /** La opción elegida (0 = A). */
        val opcion: Int,
        /** Los alimentos de esa opción como se ven hoy (con los reemplazos). */
        val alimentos: List<Alimento>,
    )

    data class ComidaAjustada(
        val alimentos: List<Alimento>,
        /** Kcal del plan (sin ajustes) y las de hoy. */
        val kcalPlan: Double,
        val kcal: Double,
        /** Lo que puso el cliente en esta comida. */
        val deltaPropio: Int,
        val omitida: Boolean,
        /** Lo que le llega de las comidas anteriores (negativo: hay que comer menos) y de cuáles. */
        val compensacion: Double,
        val compensaDe: List<String>,
        /** Lo que le llegó y no pudo absorber (no la come, nada se puede escalar o llegó al tope): pasa a la siguiente. */
        val noAbsorbido: Double,
        /** Índices de los alimentos que cambiaron respecto del plan. */
        val cambiados: Set<Int>,
        /**
         * Lo que la comida se apartó del plan por el cliente (kcal, ya redondeadas las porciones): es lo que se compensa en
         * la siguiente. Cero si solo recibe; sin comerla, menos todo el plan.
         */
        val propio: Double,
    ) {
        /** Hay que mostrarla como ajustada (por el cliente o por lo que le llega). */
        val ajustada: Boolean get() = omitida || cambiados.isNotEmpty()

        /** Lo que tomó de las anteriores. */
        val absorbido: Double get() = compensacion - noAbsorbido
    }

    /** Las de peso van de a 5 g (de a 1 si son menos de 20 g); las contables, de a media unidad. */
    fun esPeso(unidad: String?): Boolean = (unidad ?: "g").lowercase().trim() in setOf("g", "gr", "grs", "gramo", "gramos", "ml", "cc", "")

    fun redondear(q: Double, unidad: String?): Double {
        if (!q.isFinite() || q <= 0) return 0.0
        if (esPeso(unidad)) return if (q < 20) maxOf(1.0, jsRound(q)) else maxOf(5.0, jsRound(q / 5) * 5)
        return maxOf(0.5, jsRound(q * 2) / 2)
    }

    /** De a cuánto cambia el botón de un alimento: 5 g (10 g desde 100 g) o media unidad. */
    fun pasoCantidad(a: Alimento): Double {
        if (!esPeso(a.unidad)) return 0.5
        return if ((a.qty ?: 0.0) >= 100) 10.0 else 5.0
    }

    /** El mismo alimento con otra cantidad: las macros, proporcionales (son el TOTAL de la qty del plan). */
    fun conCantidad(a: Alimento, qty: Double): Alimento {
        val q0 = a.qty
        if (q0 == null || q0 <= 0 || !qty.isFinite() || qty < 0) return a
        val f = qty / q0
        return a.copy(
            qty = qty,
            kcal = a.kcal?.let { jsRound(it * f) },
            prot = a.prot?.let { jsRound(it * f * 10) / 10 },
            carb = a.carb?.let { jsRound(it * f * 10) / 10 },
            fat = a.fat?.let { jsRound(it * f * 10) / 10 },
        )
    }

    fun kcal(alimentos: List<Alimento>): Double = alimentos.fold(0.0) { s, a -> s + (a.kcal ?: 0.0) }

    /** Los alimentos que se pueden agrandar o achicar: con cantidad y kcal, y no puestos a mano. */
    internal fun escalables(alimentos: List<Alimento>, fijos: Set<Int>): List<Int> =
        alimentos.indices.filter { it !in fijos && (alimentos[it].kcal ?: 0.0) > 0 && (alimentos[it].qty ?: 0.0) > 0 }

    /** El escalón fino de una cantidad, el mismo del redondeo: 1 g por debajo de 20 g, 5 g arriba; media unidad. */
    internal fun escalon(q: Double, unidad: String?): Double = if (esPeso(unidad)) (if (q < 20) 1.0 else 5.0) else 0.5

    /**
     * Una comida: primero las cantidades a mano; después, si hay [deltaKcal], el resto de los alimentos por el mismo factor
     * (así se mantiene la proporción de macros del plan), redondeado a porciones que se puedan servir. El redondeo de las
     * contables salta fuerte (medio huevo son 39 kcal): al final se afina de a un escalón por vez, en el alimento que más
     * acerque al objetivo, hasta que ninguno lo mejore.
     */
    fun escalar(alimentos: List<Alimento>, deltaKcal: Double, cantidades: Map<Int, Double> = emptyMap()): List<Alimento> {
        val r = alimentos.mapIndexed { i, a -> cantidades[i]?.let { conCantidad(a, it) } ?: a }.toMutableList()
        if (!deltaKcal.isFinite() || deltaKcal == 0.0) return r
        val libres = escalables(alimentos, cantidades.keys)
        val base = libres.fold(0.0) { s, i -> s + (alimentos[i].kcal ?: 0.0) }
        if (base <= 0) return r
        val f = factor(base, deltaKcal)
        val sube = deltaKcal > 0
        for (i in libres) {
            val a = alimentos[i]
            val q0 = a.qty ?: 0.0
            // El redondeo a porciones servibles no cruza el plan al revés de lo pedido: con un plan fuera de la grilla
            // (36 g de queso, +50 kcal) daba 35 g, menos de lo del plan, y el afinado no lo podía arreglar.
            val q = redondear(q0 * f, a.unidad)
            r[i] = conCantidad(a, if (sube) maxOf(q, q0) else minOf(q, q0))
        }
        afinar(r, alimentos, libres, objetivo = base * f, sube = sube)
        return r
    }

    /** El factor de los alimentos libres para sumarles [delta] kcal, dentro de los topes. */
    internal fun factor(base: Double, delta: Double): Double = minOf(FACTOR_MAXIMO, maxOf(FACTOR_MINIMO, (base + delta) / base))

    /**
     * Acerca la suma de [libres] a [objetivo] moviendo un escalón por vez, sin salir de los topes de cada alimento (un
     * cuarto y el triple de lo del plan) ni cruzar el plan al revés de lo pedido: si se sumó, ninguno queda por debajo de lo
     * del plan; si se restó, ninguno por arriba. Gana el que deja el error más chico; si empatan, el primero.
     */
    internal fun afinar(r: MutableList<Alimento>, plan: List<Alimento>, libres: List<Int>, objetivo: Double, sube: Boolean) {
        repeat(60) {
            val actual = libres.fold(0.0) { s, i -> s + (r[i].kcal ?: 0.0) }
            val resto = objetivo - actual
            if (abs(resto) < 1) return
            var mejorI = -1
            var mejorQty = 0.0
            var mejorError = 0.0
            for (i in libres) {
                val a = plan[i]
                val q0 = a.qty ?: 0.0
                val q = r[i].qty ?: 0.0
                val paso = escalon(if (resto > 0) q else maxOf(0.0, q - 1), a.unidad)
                val nueva = if (resto > 0) q + paso else q - paso
                val minimo = maxOf(redondear(q0 * FACTOR_MINIMO, a.unidad), if (esPeso(a.unidad)) 1.0 else 0.5, if (sube) q0 else 0.0)
                val maximo = minOf(redondear(q0 * FACTOR_MAXIMO, a.unidad), if (sube) Double.POSITIVE_INFINITY else q0)
                if (nueva < minimo || nueva > maximo) continue
                val cambio = (conCantidad(a, nueva).kcal ?: 0.0) - (r[i].kcal ?: 0.0)
                val error = abs(resto - cambio)
                if (error < abs(resto) && (mejorI < 0 || error < mejorError)) {
                    mejorI = i
                    mejorQty = nueva
                    mejorError = error
                }
            }
            if (mejorI < 0) return
            r[mejorI] = conCantidad(plan[mejorI], mejorQty)
        }
    }

    /**
     * Las cantidades a mano que valen hoy: de la opción elegida, en una posición que existe y del mismo alimento (sin ancla,
     * recién puesta en la hoja, vale).
     */
    fun cantidadesValidas(c: ComidaDelDia, aj: AjusteComida?): Map<Int, Double> {
        if (aj == null || aj.opcion != c.opcion) return emptyMap()
        val r = LinkedHashMap<Int, Double>()
        for ((k, v) in aj.cantidades) {
            val i = k.toIntOrNull() ?: continue
            if (i !in c.alimentos.indices || !v.isFinite() || v < 0) continue
            val ancla = aj.anclas[k]
            if (ancla != null && !ancla.coincide(c.alimentos[i])) continue
            r[i] = v
        }
        return r
    }

    /**
     * Al guardar (y al abrir la hoja): cada cantidad a mano con el alimento al que va, afuera las que ya no valen y las kcal
     * sumadas o restadas dentro de lo que la comida puede absorber (con alimentos a mano entra menos).
     */
    fun anclar(a: AjusteComida, en: ComidaDelDia): AjusteComida {
        val validas = cantidadesValidas(en, a)
        val r = a.copy(
            cantidades = validas.entries.associate { it.key.toString() to it.value },
            anclas = validas.keys.associate { it.toString() to AnclaAlimento(en.alimentos[it]) },
        )
        return r.copy(deltaKcal = r.deltaKcal.coerceIn(limitesDelta(en, r)))
    }

    /**
     * Cuánto se puede sumar o restar a una comida, de a [PASO]: hasta un cuarto y hasta el triple de lo que se puede
     * escalar (lo puesto a mano no cuenta). Sin nada que escalar, nada.
     */
    fun limitesDelta(c: ComidaDelDia, aj: AjusteComida?): IntRange {
        val base = baseEscalable(c, aj)
        val minimo = -Math.floor(base * (1 - FACTOR_MINIMO) / PASO).toInt() * PASO
        val maximo = Math.floor(base * (FACTOR_MAXIMO - 1) / PASO).toInt() * PASO
        return minimo..maximo
    }

    /** Las kcal de lo que se agranda o se achica parejo (sin lo puesto a mano): sobre eso se miden los topes. */
    fun baseEscalable(c: ComidaDelDia, aj: AjusteComida?): Double =
        escalables(c.alimentos, cantidadesValidas(c, aj).keys).fold(0.0) { s, i -> s + (c.alimentos[i].kcal ?: 0.0) }

    /**
     * El día: cada comida con su ajuste y lo que le pasan las anteriores.
     * - Lo que una comida se aparta del plan POR EL CLIENTE (sumó, restó, cambió gramos o no la come) va a la siguiente si
     *   eligió compensar.
     * - Lo que le llega y no puede absorber (no la come, no tiene nada que escalar o llegó al tope de un cuarto o el triple)
     *   sigue de largo a la otra. Lo propio de la comida va primero; lo que llega entra en lo que queda.
     * - La última no pasa nada: lo que le quede sin absorber es [sinCompensar] (la hoja lo avisa).
     */
    fun dia(comidas: List<ComidaDelDia>, ajustes: Map<String, AjusteComida>): Map<String, ComidaAjustada> {
        val r = LinkedHashMap<String, ComidaAjustada>()
        var arrastre = 0.0
        var origenes: List<String> = emptyList()
        for (c in comidas) {
            val aj = ajustes[c.id]
            val llega = arrastre
            val deQuien = origenes
            val plan = kcal(c.alimentos)
            val cantidades = cantidadesValidas(c, aj)
            val omitida = aj?.omitida == true
            val delta = (if (omitida) 0 else aj?.deltaKcal ?: 0).toDouble()
            val als: List<Alimento>
            val noAbsorbido: Double
            if (omitida) {
                als = c.alimentos.map { if ((it.qty ?: 0.0) > 0) conCantidad(it, 0.0) else it }
                noAbsorbido = llega
            } else {
                val base = escalables(c.alimentos, cantidades.keys).fold(0.0) { s, i -> s + (c.alimentos[i].kcal ?: 0.0) }
                if (base > 0) {
                    als = escalar(c.alimentos, delta + llega, cantidades)
                    noAbsorbido = jsRound(llega - base * (factor(base, delta + llega) - factor(base, delta)))
                } else {
                    als = escalar(c.alimentos, 0.0, cantidades)
                    noAbsorbido = llega
                }
            }
            val hoy = kcal(als)
            val cambiados = c.alimentos.indices.filter { als[it].qty != c.alimentos[it].qty }.toSet()
            // Lo que se apartó del plan por el cliente: lo de hoy menos el plan y lo que sí absorbió de las anteriores. Sin
            // nada propio (solo recibe), es cero: el redondeo de lo que absorbió no se le pasa a la siguiente.
            val propio = if (aj == null || aj.neutro) 0.0 else jsRound(hoy - plan - (llega - noAbsorbido))
            r[c.id] = ComidaAjustada(
                alimentos = als, kcalPlan = plan, kcal = hoy, deltaPropio = delta.toInt(), omitida = omitida, compensacion = llega,
                compensaDe = if (llega != 0.0) deQuien else emptyList(), noAbsorbido = noAbsorbido, cambiados = cambiados, propio = propio,
            )
            var siguiente = noAbsorbido
            val nuevosOrigenes = (if (noAbsorbido != 0.0) deQuien else emptyList()).toMutableList()
            if (aj != null && aj.compensar && propio != 0.0) {
                siguiente -= propio
                nuevosOrigenes += c.nombre
            }
            arrastre = siguiente
            origenes = if (siguiente != 0.0) nuevosOrigenes else emptyList()
        }
        return r
    }

    /** La comida que recibe lo que sale de [id]: la primera de las siguientes que se come y tiene algo que escalar. */
    fun destino(comidas: List<ComidaDelDia>, ajustes: Map<String, AjusteComida>, despuesDe: String): ComidaDelDia? {
        val i = comidas.indexOfFirst { it.id == despuesDe }
        if (i < 0) return null
        return comidas.drop(i + 1).firstOrNull { ajustes[it.id]?.omitida != true && baseEscalable(it, ajustes[it.id]) > 0 }
    }

    data class CambioEnOtra(
        val id: String,
        val nombre: String,
        /** Cuánto cambia (kcal) y en cuánto queda. */
        val kcal: Double,
        val queda: Double,
    )

    data class Efecto(val cambios: List<CambioEnOtra>, val sinCompensar: Double)

    /**
     * Lo que el ajuste de [de] le hace al resto del día, comparado con el día sin ese ajuste: cuánto cambia cada una de las
     * siguientes y cuánto queda sin compensar al final. Es lo que explica la hoja.
     */
    fun efecto(comidas: List<ComidaDelDia>, ajustes: Map<String, AjusteComida>, de: String): Efecto {
        val i = comidas.indexOfFirst { it.id == de }
        if (i < 0) return Efecto(emptyList(), 0.0)
        val con = dia(comidas, ajustes)
        val antes = dia(comidas, ajustes - de)
        val cambios = comidas.drop(i + 1).mapNotNull { c ->
            val a = con[c.id] ?: return@mapNotNull null
            val b = antes[c.id] ?: return@mapNotNull null
            if (abs(a.kcal - b.kcal) < 1) null else CambioEnOtra(c.id, c.nombre, a.kcal - b.kcal, a.kcal)
        }
        return Efecto(cambios, sinCompensar(comidas, con) - sinCompensar(comidas, antes))
    }

    /** Lo que llegó a la última comida y no pudo absorber (no había otra después). */
    fun sinCompensar(comidas: List<ComidaDelDia>, dia: Map<String, ComidaAjustada>): Double {
        val ultima = comidas.lastOrNull() ?: return 0.0
        return dia[ultima.id]?.noAbsorbido ?: 0.0
    }
}
