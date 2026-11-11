package com.pumpteam.mypump.reglas

import com.pumpteam.mypump.modelos.Alimento
import com.pumpteam.mypump.modelos.Comida
import com.pumpteam.mypump.modelos.Dia
import com.pumpteam.mypump.modelos.DietaActiva
import com.pumpteam.mypump.modelos.Ejercicio
import com.pumpteam.mypump.modelos.EstructuraDieta
import com.pumpteam.mypump.modelos.ItemSuplemento
import com.pumpteam.mypump.modelos.Macros
import com.pumpteam.mypump.modelos.RutinaActiva
import com.pumpteam.mypump.modelos.Suplementacion
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

/*
 * «Novedades de tu plan» (2.3.0): qué cambió entre la versión del plan que el alumno ya vio y la que Mati acaba de
 * publicar. Determinístico, sin IA. Port de `NovedadesPlan.swift`; los mismos casos en
 * `apps/shared/fixtures/novedades/casos.json`.
 *
 * Textos: cortos, sin dos puntos, guiones ni emojis; nunca RIR (ni se compara) ni «cerca del fallo»; repes = referencia;
 * nunca «tu coach» ni «tu entrenador», solo Mati. Nunca una dosis: de la suplementación se nombra el suplemento y nada más
 * (si el nombre trae la dosis, [NovedadesPlan.sinDosis] se la saca).
 */

/** Una parte del plan como se vio la última vez o como llega ahora. */
sealed interface AreaPlan<out T> {
    /** No se sabe (no llegó por la red, o nunca se guardó): no se compara. */
    data object Desconocida : AreaPlan<Nothing>
    /** El servidor dijo que no hay. */
    data object Ninguna : AreaPlan<Nothing>
    data class Hay<T>(val valor: T) : AreaPlan<T>
}

private val <T> AreaPlan<T>.valor: T? get() = (this as? AreaPlan.Hay<T>)?.valor
private val AreaPlan<*>.conocida: Boolean get() = this !is AreaPlan.Desconocida

data class FotoPlan(
    val rutina: AreaPlan<RutinaActiva> = AreaPlan.Desconocida,
    val dieta: AreaPlan<DietaActiva> = AreaPlan.Desconocida,
    val suplementacion: AreaPlan<Suplementacion> = AreaPlan.Desconocida,
)

data class ParteNovedad(
    /** `rutina`, `dieta` o `suplementacion`: a dónde lleva el botón. */
    val area: String,
    val titular: String,
    /** Bloque nuevo, dieta nueva o la primera vez que llega: lo principal, sin listar todo. */
    val grande: Boolean,
    val lineas: List<String>,
)

data class ResumenNovedad(val titular: String, val resumen: String, val partes: List<ParteNovedad>)

object NovedadesPlan {
    const val MAX_LINEAS = 4

    /** null = nada que contar (sin cambios, solo cambió la semana, el RIR o datos internos). */
    fun calcular(antes: FotoPlan, despues: FotoPlan): ResumenNovedad? {
        val partes = mutableListOf<ParteNovedad>()
        val rn = despues.rutina.valor
        if (antes.rutina.conocida && rn != null) rutina(antes.rutina.valor, rn)?.let(partes::add)
        val dn = despues.dieta.valor
        if (antes.dieta.conocida && dn != null) dieta(antes.dieta.valor?.estructura, dn.estructura)?.let(partes::add)
        val sn = despues.suplementacion.valor
        if (antes.suplementacion.conocida && sn != null) suplementacion(antes.suplementacion.valor, sn)?.let(partes::add)
        if (partes.isEmpty()) return null
        if (partes.size == 1) {
            val p = partes[0]
            return ResumenNovedad(p.titular, p.lineas.firstOrNull() ?: p.titular, partes)
        }
        val nombres = partes.map {
            when (it.area) { "rutina" -> "tu rutina"; "dieta" -> "tu dieta"; else -> "tu suplementación" }
        }
        return ResumenNovedad("Mati actualizó tu plan", "Hay cambios en ${lista(nombres)}", partes)
    }

    // ---------------------------------------------------------------- Rutina

    private data class EjercicioPlano(val clave: String, val nombre: String, val ejercicio: Ejercicio)

    private fun ejercicios(d: Dia): List<EjercicioPlano> {
        val vistos = HashSet<String>()
        val r = mutableListOf<EjercicioPlano>()
        for (b in d.bloques) for (e in b.ejercicios) {
            val nombre = limpio(e.nombre)
            val k = clave(nombre)
            if (k.isEmpty() || !vistos.add(k)) continue
            r.add(EjercicioPlano(k, nombre, e))
        }
        return r
    }

    private fun claveDia(d: Dia, i: Int): String {
        val id = d.id?.let(::limpio).orEmpty()
        return if (id.isNotEmpty()) "id:$id" else "i:$i"
    }

    /** «Tirón A — Ancho» → «Tirón A»; «TORSO A» → «Torso A». */
    internal fun nombreDia(d: Dia, i: Int): String {
        var n = limpio(d.nombre ?: "")
        for (sep in listOf(" — ", " – ", " - ")) {
            val k = n.indexOf(sep)
            if (k >= 0) n = limpio(n.substring(0, k))
        }
        if (n.isEmpty()) return "Día ${d.n ?: (i + 1)}"
        if (n == n.uppercase() && n != n.lowercase()) {
            n = n.split(" ").joinToString(" ") { p -> p.take(1).uppercase() + p.drop(1).lowercase() }
        }
        return n
    }

    private fun pauta(e: Ejercicio, semana: Int): Pair<Int?, String?> {
        if (e.progresion.isNotEmpty()) {
            val p = e.progresion[max(0, min(semana - 1, e.progresion.size - 1))]
            return p.series to repsNormal(p.reps)
        }
        return e.series to repsNormal(e.reps)
    }

    private fun pautas(e: Ejercicio): List<Pair<Int?, String?>> =
        if (e.progresion.isEmpty()) listOf(e.series to repsNormal(e.reps)) else e.progresion.map { it.series to repsNormal(it.reps) }

    private fun rutina(antes: RutinaActiva?, despues: RutinaActiva): ParteNovedad? {
        val nuevaE = despues.estructura
        val diasNuevos = nuevaE.dias.withIndex().filter { ejercicios(it.value).isNotEmpty() }
        if (diasNuevos.isEmpty()) return null
        if (antes == null) {
            return ParteNovedad("rutina", "Mati te armó tu rutina", true, lineasBloque(diasNuevos.map { nombreDia(it.value, it.index) }, 0))
        }
        val viejaE = antes.estructura
        val diasViejos = viejaE.dias.withIndex().filter { ejercicios(it.value).isNotEmpty() }

        val clavesViejas = diasViejos.flatMap { d -> ejercicios(d.value).map { it.clave } }.toSet()
        val clavesNuevas = LinkedHashSet<String>()
        for (d in diasNuevos) for (e in ejercicios(d.value)) clavesNuevas.add(e.clave)
        val nuevos = clavesNuevas.count { it !in clavesViejas }
        val otroPlan = run {
            val a = viejaE.nombrePlan?.let(::clave).orEmpty()
            val b = nuevaE.nombrePlan?.let(::clave).orEmpty()
            (a.isNotEmpty() && b.isNotEmpty() && a != b) ||
                (viejaE.fase != null && nuevaE.fase != null && viejaE.fase != nuevaE.fase)
        }
        if (otroPlan || (nuevos >= 3 && nuevos * 2 >= clavesNuevas.size)) {
            return ParteNovedad("rutina", "Mati te armó un bloque nuevo", true, lineasBloque(diasNuevos.map { nombreDia(it.value, it.index) }, nuevos))
        }

        val semana = max(1, despues.semanaActual)
        val lineas = mutableListOf<String>()
        val usados = HashSet<String>()
        for ((i, d) in diasNuevos) {
            val k = claveDia(d, i)
            val nombre = nombreDia(d, i)
            val v = diasViejos.firstOrNull { claveDia(it.value, it.index) == k }?.value
            if (v == null) {
                lineas.add("Se suma un día nuevo, $nombre")
                continue
            }
            usados.add(k)
            val viejos = ejercicios(v)
            val actuales = ejercicios(d)
            val clavesV = viejos.map { it.clave }.toSet()
            val clavesA = actuales.map { it.clave }.toSet()
            val salen = viejos.filter { it.clave !in clavesA }
            val entran = actuales.filter { it.clave !in clavesV }
            val pares = min(salen.size, entran.size)
            for (j in 0 until pares) lineas.add("En $nombre cambia ${salen[j].nombre} por ${entran[j].nombre}")
            for (e in entran.drop(pares)) lineas.add("En $nombre se suma ${e.nombre}")
            for (e in salen.drop(pares)) lineas.add("En $nombre sale ${e.nombre}")
            for (e in actuales) {
                val anterior = viejos.firstOrNull { it.clave == e.clave } ?: continue
                val (sN, rN) = pauta(e.ejercicio, semana)
                val (sV, rV) = pauta(anterior.ejercicio, semana)
                if (sN != sV || rN != rV) {
                    formatoPauta(sN, rN)?.let { lineas.add("En $nombre, ${e.nombre} pasa a $it") }
                    continue
                }
                val pn = pautas(e.ejercicio)
                val pv = pautas(anterior.ejercicio)
                val hasta = min(pn.size, pv.size)
                if (semana < hasta && (semana until hasta).any { pn[it] != pv[it] }) {
                    lineas.add("En $nombre, ${e.nombre} cambia en las próximas semanas")
                }
            }
        }
        for ((i, v) in diasViejos) if (claveDia(v, i) !in usados) lineas.add("Sale el día ${nombreDia(v, i)}")
        if (lineas.isEmpty()) return null
        return ParteNovedad("rutina", "Mati actualizó tu rutina", false, recortar(lineas))
    }

    private fun lineasBloque(dias: List<String>, nuevos: Int): List<String> {
        val r = mutableListOf<String>()
        when {
            dias.size == 1 -> r.add("Un día, ${dias[0]}")
            dias.size <= 5 -> r.add("${dias.size} días, ${lista(dias)}")
            else -> r.add("${dias.size} días de entrenamiento")
        }
        if (nuevos == 1) r.add("Un ejercicio nuevo") else if (nuevos > 1) r.add("$nuevos ejercicios nuevos")
        return r
    }

    private val repsNumericas = Regex("^\\d+( a \\d+)?$")
    private val repsProhibidas = Regex("(?i)rir|fallo|[-–—:]")

    internal fun formatoPauta(series: Int?, reps: String?): String? {
        // Repes con texto que no puede salir (RIR, fallo, guiones, dos puntos): se dicen solo las series.
        val r = reps?.ifEmpty { null }?.takeUnless { repsProhibidas.containsMatchIn(it) }
        val numerico = r?.let { repsNumericas.matches(it) } ?: false
        fun s(n: Int) = "$n ${if (n == 1) "serie" else "series"}"
        return when {
            series != null && r != null -> if (numerico) "${s(series)} de $r" else "${s(series)}, $r"
            series != null -> s(series)
            r != null -> if (numerico) "$r repes" else r
            else -> null
        }
    }

    private val rango = Regex("^(\\d+)\\s*[-–—]\\s*(\\d+)$")

    internal fun repsNormal(r: String?): String? {
        if (r == null) return null
        val s = rango.replace(limpio(r), "$1 a $2")
        return s.ifEmpty { null }
    }

    // ---------------------------------------------------------------- Dieta

    private data class ComidaPlana(val clave: String, val nombre: String, val comida: Comida)

    private fun comidas(cs: List<Comida>): List<ComidaPlana> {
        val vistas = HashSet<String>()
        val r = mutableListOf<ComidaPlana>()
        for ((i, c) in cs.withIndex()) {
            val n = limpio(c.nombre ?: "")
            val nombre = if (n.isEmpty()) "Comida ${i + 1}" else n
            val id = limpio(c.id)
            val k = if (id.isEmpty()) "n:${clave(nombre)}" else "id:$id"
            if (!vistas.add(k)) continue
            r.add(ComidaPlana(k, nombre, c))
        }
        return r
    }

    private fun alimentosDe(e: EstructuraDieta): List<String> {
        val cs = if (e.tiposDia.isEmpty()) e.comidas else e.tiposDia.flatMap { it.comidas }
        val r = LinkedHashSet<String>()
        for (c in cs) for (o in c.opciones) for (a in o.alimentos) {
            val k = clave(a.nombre)
            if (k.isNotEmpty()) r.add(k)
        }
        return r.toList()
    }

    private fun nombreTipo(nombre: String?, i: Int): String = limpio(nombre ?: "").ifEmpty { "Día ${i + 1}" }

    private fun claveTipo(id: String, nombre: String): String = limpio(id).let { if (it.isEmpty()) "n:${clave(nombre)}" else "id:$it" }

    private fun lineasDietaNueva(e: EstructuraDieta): List<String> {
        val r = mutableListOf<String>()
        val n = if (e.tiposDia.isEmpty()) comidas(e.comidas).size else (e.tiposDia.maxOfOrNull { comidas(it.comidas).size } ?: 0)
        if (e.tiposDia.size > 1) {
            r.add("${e.tiposDia.size} tipos de día, ${lista(e.tiposDia.mapIndexed { i, t -> nombreTipo(t.nombre, i) })}")
        }
        if (n == 1) r.add("Una comida por día") else if (n > 1) r.add("$n comidas por día")
        val kcal = if (e.tiposDia.isEmpty()) e.macrosTarget?.kcal else if (e.tiposDia.size == 1) e.tiposDia[0].macrosTarget?.kcal else null
        if (kcal != null && kcal > 0) r.add("Objetivo de ${formatoKcal(kcal)} kcal por día")
        return r
    }

    private fun dieta(antes: EstructuraDieta?, despues: EstructuraDieta): ParteNovedad? {
        val todosNuevos = alimentosDe(despues)
        if (todosNuevos.isEmpty()) return null
        if (antes == null) return ParteNovedad("dieta", "Mati te armó tu dieta", true, lineasDietaNueva(despues))
        val viejos = alimentosDe(antes).toSet()
        val nuevos = todosNuevos.count { it !in viejos }
        val cambioDeFormato = antes.tiposDia.isEmpty() != despues.tiposDia.isEmpty()
        if (cambioDeFormato || (nuevos >= 4 && nuevos * 2 >= todosNuevos.size)) {
            return ParteNovedad("dieta", "Mati te armó una dieta nueva", true, lineasDietaNueva(despues))
        }
        val lineas = mutableListOf<String>()
        if (despues.tiposDia.isEmpty()) {
            lineas += lineasKcal(antes.macrosTarget, despues.macrosTarget, null)
            lineas += lineasComidas(antes.comidas, despues.comidas, null)
        } else {
            val varios = despues.tiposDia.size > 1
            val usados = HashSet<String>()
            for ((i, t) in despues.tiposDia.withIndex()) {
                val nombre = nombreTipo(t.nombre, i)
                val k = claveTipo(t.id, nombre)
                val v = antes.tiposDia.withIndex().firstOrNull { (j, x) -> claveTipo(x.id, nombreTipo(x.nombre, j)) == k }?.value
                if (v == null) {
                    lineas.add("Se suma un tipo de día, $nombre")
                    continue
                }
                usados.add(k)
                lineas += lineasKcal(v.macrosTarget, t.macrosTarget, if (varios) nombre else null)
                lineas += lineasComidas(v.comidas, t.comidas, if (varios) nombre else null)
            }
            for ((j, x) in antes.tiposDia.withIndex()) {
                val nx = nombreTipo(x.nombre, j)
                if (claveTipo(x.id, nx) !in usados) lineas.add("Sale el tipo de día $nx")
            }
        }
        if (lineas.isEmpty()) return null
        return ParteNovedad("dieta", "Mati actualizó tu dieta", false, recortar(lineas))
    }

    private fun lineasKcal(a: Macros?, b: Macros?, tipo: String?): List<String> {
        val x = a?.kcal ?: return emptyList()
        val y = b?.kcal ?: return emptyList()
        if (x <= 0 || y <= 0 || abs(y - x) < 50) return emptyList()
        return listOf(if (tipo != null) "En $tipo, tu objetivo pasa a ${formatoKcal(y)} kcal" else "Tu objetivo del día pasa a ${formatoKcal(y)} kcal")
    }

    private fun lineasComidas(viejas: List<Comida>, nuevas: List<Comida>, tipo: String?): List<String> {
        val lineas = mutableListOf<String>()
        val cv = comidas(viejas)
        val cn = comidas(nuevas)
        fun etiqueta(n: String) = if (tipo != null) "$n ($tipo)" else n
        for (c in cn) {
            val v = cv.firstOrNull { it.clave == c.clave } ?: cv.firstOrNull { clave(it.nombre) == clave(c.nombre) }
            if (v == null) {
                lineas.add("Se suma ${etiqueta(c.nombre)}")
                continue
            }
            val nombre = etiqueta(c.nombre)
            val on = c.comida.opciones
            val ov = v.comida.opciones
            val varias = on.size > 1
            for (i in 0 until min(on.size, ov.size)) {
                val letra = limpio(on[i].nombre ?: "").ifEmpty { letraOpcion(i) }
                val lugar = if (varias) "En $nombre, opción $letra," else "En $nombre"
                val lugarComa = if (varias) lugar else "$lugar,"
                lineas += lineasOpcion(ov[i].alimentos, on[i].alimentos, lugar, lugarComa)
            }
            if (on.size > ov.size) {
                lineas.add(if (on.size - ov.size == 1) "En $nombre se suma una opción" else "En $nombre se suman ${on.size - ov.size} opciones")
            } else if (ov.size > on.size) {
                lineas.add(if (ov.size - on.size == 1) "En $nombre sale una opción" else "En $nombre salen ${ov.size - on.size} opciones")
            }
        }
        for (v in cv) {
            if (cn.none { it.clave == v.clave || clave(it.nombre) == clave(v.nombre) }) lineas.add("Sale ${etiqueta(v.nombre)}")
        }
        return lineas
    }

    private fun lineasOpcion(viejos: List<Alimento>, nuevos: List<Alimento>, lugar: String, lugarComa: String): List<String> {
        fun planos(xs: List<Alimento>): List<Pair<String, Alimento>> {
            val vistos = HashSet<String>()
            return xs.mapNotNull { a -> clave(a.nombre).takeIf { it.isNotEmpty() && vistos.add(it) }?.let { it to a } }
        }
        val v = planos(viejos)
        val n = planos(nuevos)
        val kv = v.map { it.first }.toSet()
        val kn = n.map { it.first }.toSet()
        val salen = v.filter { it.first !in kn }
        val entran = n.filter { it.first !in kv }
        val pares = min(salen.size, entran.size)
        val r = mutableListOf<String>()
        for (j in 0 until pares) r.add("$lugar cambia ${limpio(salen[j].second.nombre)} por ${limpio(entran[j].second.nombre)}")
        for (e in entran.drop(pares)) r.add("$lugar se suma ${limpio(e.second.nombre)}")
        for (e in salen.drop(pares)) r.add("$lugar sale ${limpio(e.second.nombre)}")
        for ((k, a) in n) {
            val b = v.firstOrNull { it.first == k }?.second ?: continue
            val mismaUnidad = unidadNormal(a.unidad) == unidadNormal(b.unidad)
            val qa = a.qty
            val qb = b.qty
            val mismaCantidad = if (qa != null && qb != null) abs(qa - qb) < 0.001 else (qa == null && qb == null)
            if (!(mismaUnidad && mismaCantidad) && qa != null) {
                r.add("$lugarComa ${limpio(a.nombre)} pasa a ${formatoCantidad(qa, a.unidad)}")
            }
        }
        return r
    }

    private fun letraOpcion(i: Int): String = if (i < 10) ('A' + i).toString() else "${i + 1}"

    private fun unidadNormal(u: String?): String = clave(u ?: "").ifEmpty { "g" }

    internal fun formatoCantidad(q: Double, unidad: String?): String {
        val num = formatoNumero(q)
        val u = unidadNormal(unidad)
        if (u in setOf("unidad", "unidades", "u", "un", "ud", "uds")) return "$num ${if (num == "1") "unidad" else "unidades"}"
        return "$num ${limpio(unidad ?: "").ifEmpty { "g" }}"
    }

    /** Redondeo a un decimal, como `Double.rounded()` de Swift (la mitad, lejos del cero). */
    private fun redondear(x: Double): Double = if (x >= 0) Math.floor(x + 0.5) else -Math.floor(-x + 0.5)

    private fun formatoNumero(q: Double): String {
        val r = redondear(q * 10) / 10
        if (r == redondear(r)) return r.toLong().toString()
        return String.format(java.util.Locale.US, "%.1f", r).replace(".", ",")
    }

    internal fun formatoKcal(k: Double): String {
        val n = redondear(k).toLong()
        val s = abs(n).toString()
        val sb = StringBuilder()
        for ((i, ch) in s.reversed().withIndex()) {
            if (i > 0 && i % 3 == 0) sb.append('.')
            sb.append(ch)
        }
        return (if (n < 0) "-" else "") + sb.reverse().toString()
    }

    // ---------------------------------------------------------------- Suplementación

    private data class SuplementoPlano(val clave: String, val nombre: String, val item: ItemSuplemento)

    private fun suplementacion(antes: Suplementacion?, despues: Suplementacion): ParteNovedad? {
        // Se compara y se muestra el nombre sin la dosis: «Creatina 5 g» es «Creatina». Lo que queda vacío no es un suplemento.
        fun activos(s: Suplementacion?): List<SuplementoPlano> {
            val vistos = HashSet<String>()
            return (s?.items ?: emptyList()).mapNotNull { it ->
                val nombre = sinDosis(it.nombre)
                val k = clave(nombre)
                if (k.isEmpty() || clave(it.estado ?: "") == "sale" || !vistos.add(k)) null else SuplementoPlano(k, nombre, it)
            }
        }
        val n = activos(despues)
        if (antes == null) {
            if (n.isEmpty()) return null
            return ParteNovedad("suplementacion", "Mati te armó tu suplementación", true,
                listOf(if (n.size == 1) "Un suplemento para tu día" else "${n.size} suplementos para tu día"))
        }
        val v = activos(antes)
        val kv = v.map { it.clave }.toSet()
        val kn = n.map { it.clave }.toSet()
        val lineas = mutableListOf<String>()
        for (x in n) if (x.clave !in kv) lineas.add("Se suma ${x.nombre}")
        for (x in v) if (x.clave !in kn) lineas.add("Dejás de tomar ${x.nombre}")
        for (x in n) {
            val b = v.firstOrNull { it.clave == x.clave } ?: continue
            if (firma(x) != firma(b)) lineas.add("Cambia cómo tomás ${x.nombre}")
        }
        if (lineas.isEmpty()) return null
        return ParteNovedad("suplementacion", "Mati actualizó tu suplementación", false, recortar(lineas))
    }

    /** La cantidad se compara pero nunca se muestra. Si el nombre traía la dosis, el nombre entero también cuenta. */
    private fun firma(x: SuplementoPlano): String {
        val it = x.item
        val tomas = it.tomas.joinToString(";") { "${clave(it.momento ?: "")}=${clave(it.cantidad ?: "")}" }
        val dias = it.dias.map(::clave).sorted().joinToString(",")
        val entero = clave(it.nombre).takeIf { k -> k != x.clave }.orEmpty()
        return listOf(clave(it.cantidad ?: ""), clave(it.momento ?: ""), tomas, dias, if (it.opcional) "1" else "0", entero).joinToString("|")
    }

    // ---------------------------------------------------------------- Sin dosis

    private val unidadesDosis = ("mg mcg ug \u00B5g g gr grs kg ml l ui iu % cap caps capsula capsulas comprimido comprimidos comp tableta tabletas " +
        "tab tabs pastilla pastillas gota gotas scoop scoops cucharada cucharadas cucharadita cucharaditas sobre sobres unidad unidades").split(" ").toSet()
    private val tiemposDosis = setOf("dia", "toma", "noche", "semana", "comida", "mañana")
    private val enlacesDosis = setOf("por", "x", "al", "/", "c/")
    private val sueltosDosis = setOf("x", "-", "–", "—", ":", "·")
    private const val NUMERO_DOSIS = "0123456789.,"
    private const val DIGITOS = "0123456789"

    private fun normDosis(t: String): String {
        var n = clave(t)
        while (n.isNotEmpty() && n[0] in "([") n = n.substring(1)
        while (n.isNotEmpty() && n[n.length - 1] in ").,;:]") n = n.substring(0, n.length - 1)
        return n
    }

    /** (número, resto). El número: dígitos con . o , y a lo sumo un rango «3-5» o «3/5». */
    private fun partirDosis(n: String): Pair<String, String> {
        if (n.isEmpty() || n[0] !in DIGITOS) return "" to n
        var i = 0
        while (i < n.length && n[i] in NUMERO_DOSIS) i++
        if (i + 1 < n.length && n[i] in "-/" && n[i + 1] in DIGITOS) {
            i++
            while (i < n.length && n[i] in NUMERO_DOSIS) i++
        }
        return n.substring(0, i) to n.substring(i)
    }

    private fun esUnidadDosis(resto: String): Boolean {
        var r = resto.substringBefore('/')
        while (r.endsWith(".")) r = r.substring(0, r.length - 1)
        return r in unidadesDosis
    }

    private fun esNumeroDosis(n: String): Boolean = partirDosis(n).let { (p, r) -> p.isNotEmpty() && r.isEmpty() }

    private fun cuenta(xs: List<String>, c: Char): Int = xs.sumOf { x -> x.count { it == c } }

    /**
     * El nombre del suplemento sin la dosis («Creatina 5 g» → «Creatina»). Port EXACTO de la referencia
     * `scripts/nativa/novedades-sin-dosis.py`: un recorrido de tokens, sin expresiones regulares. La prueba compartida es
     * `apps/shared/fixtures/novedades/sin_dosis.json`; las tres plataformas dan la misma salida.
     */
    fun sinDosis(nombre: String): String {
        val ts = limpio(nombre).let { if (it.isEmpty()) emptyList() else it.split(" ") }
        val out = mutableListOf<String>()
        var i = 0
        var cerrar = 0
        while (i < ts.size) {
            var t = ts[i]
            val n = normDosis(t)
            val (p, r) = partirDosis(n)
            var quita = 0
            if (p.isNotEmpty()) {
                if (r.isNotEmpty() && (esUnidadDosis(r) || r == "x")) {
                    quita = 1
                } else if (r.isEmpty() && i + 1 < ts.size && normDosis(ts[i + 1]).let { it.isNotEmpty() && esUnidadDosis(it) }) {
                    quita = 2
                }
            } else if (n.length > 1 && n[0] == 'x' && n.substring(1).all { it in DIGITOS }) {
                quita = 1
            }
            if (quita == 0) {
                if (cerrar > 0 && t.endsWith(")")) {
                    t = t.substring(0, t.length - 1)
                    cerrar--
                }
                if (t.isNotEmpty()) out.add(t)
                i++
                continue
            }
            val ido = ts.subList(i, i + quita).toMutableList()
            i += quita
            if (i + 1 < ts.size && normDosis(ts[i]) in enlacesDosis && normDosis(ts[i + 1]) in tiemposDosis) {
                ido += ts.subList(i, i + 2)
                i += 2
            } else if (i < ts.size && normDosis(ts[i]).let { it.startsWith("/") && it.substring(1) in tiemposDosis }) {
                ido += ts[i]
                i += 1
            } else if (i + 1 < ts.size && normDosis(ts[i]) == "x" && esNumeroDosis(normDosis(ts[i + 1]))) {
                ido += ts.subList(i, i + 2)
                i += 2
            }
            if (out.size >= 2 && normDosis(out[out.size - 1]) == "a" && esNumeroDosis(normDosis(out[out.size - 2]))) {
                ido.addAll(0, out.subList(out.size - 2, out.size).toList())
                out.removeAt(out.size - 1)
                out.removeAt(out.size - 1)
            }
            if (out.isNotEmpty() && out[out.size - 1] in sueltosDosis) out.removeAt(out.size - 1)
            val abren = cuenta(ido, '(')
            val cierran = cuenta(ido, ')')
            if (abren > cierran) {
                cerrar += abren - cierran
            } else if (cierran > abren && out.isNotEmpty() && cuenta(out, '(') > cuenta(out, ')')) {
                out[out.size - 1] = out[out.size - 1] + ")"
            }
        }
        while (out.isNotEmpty() && out[out.size - 1].all { it in "-–—:,·+/x" }) out.removeAt(out.size - 1)
        if (out.isNotEmpty()) {
            var u = out[out.size - 1]
            while (u.isNotEmpty() && u[u.length - 1] in ",:;") u = u.substring(0, u.length - 1)
            if (u.isEmpty()) out.removeAt(out.size - 1) else out[out.size - 1] = u
        }
        return out.joinToString(" ").replace("()", "").trim()
    }

    // ---------------------------------------------------------------- Texto

    internal fun recortar(l: List<String>): List<String> {
        if (l.size <= MAX_LINEAS) return l
        val resto = l.size - (MAX_LINEAS - 1)
        return l.take(MAX_LINEAS - 1) + (if (resto == 1) "Y un cambio más" else "Y $resto cambios más")
    }

    internal fun lista(xs: List<String>): String =
        if (xs.size <= 1) xs.firstOrNull() ?: "" else xs.dropLast(1).joinToString(", ") + " y " + xs.last()

    internal fun limpio(s: String): String = s.split(' ', '\t', '\n', '\r').filter { it.isNotEmpty() }.joinToString(" ")

    private val tildes = mapOf(
        'á' to 'a', 'à' to 'a', 'ä' to 'a', 'â' to 'a', 'é' to 'e', 'è' to 'e', 'ë' to 'e', 'ê' to 'e', 'í' to 'i', 'ì' to 'i',
        'ï' to 'i', 'î' to 'i', 'ó' to 'o', 'ò' to 'o', 'ö' to 'o', 'ô' to 'o', 'ú' to 'u', 'ù' to 'u', 'ü' to 'u', 'û' to 'u',
    )

    internal fun clave(s: String): String = java.text.Normalizer.normalize(limpio(s), java.text.Normalizer.Form.NFC).lowercase().map { tildes[it] ?: it }.joinToString("")
}
