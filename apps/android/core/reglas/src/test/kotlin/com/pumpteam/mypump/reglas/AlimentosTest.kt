package com.pumpteam.mypump.reglas

import com.pumpteam.mypump.modelos.Alimento
import com.pumpteam.mypump.modelos.AlimentoPropio
import com.pumpteam.mypump.modelos.ValorJson
import com.pumpteam.mypump.modelos.listaEstricta
import java.nio.file.Path
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.double
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

// Gemelo de AlimentosTests.swift: categoría (las tres copias de la web), la base empaquetada y findSubstitutes.

/** La base que empaqueta la app: el MYPUMP_FOOD_DB de la web (scripts/nativa/vectores-alimentos.mjs). */
private val baseEmpaquetada: BaseAlimentos by lazy { BaseAlimentos.desde(Vectores.texto(Vectores.compartido("food-db.json"))) }

private fun casiIgual(a: Double, b: Double) = a == b || Math.abs(a - b) <= 1e-9

/** Igualdad de JSON con tolerancia en los números. */
private fun casiIgual(a: ValorJson, b: ValorJson): Boolean = when {
    a is ValorJson.Numero && b is ValorJson.Numero -> casiIgual(a.valor, b.valor)
    a is ValorJson.Objeto && b is ValorJson.Objeto ->
        a.campos.keys == b.campos.keys && a.campos.all { (k, v) -> casiIgual(v, b.campos.getValue(k)) }
    a is ValorJson.Lista && b is ValorJson.Lista -> a.elementos.size == b.elementos.size && a.elementos.zip(b.elementos).all { casiIgual(it.first, it.second) }
    else -> a == b
}

/** Un número como lo lee la regla de la web: ausente = undefined (null); `null` vale 0 en todas sus cuentas. */
private fun numeroJs(o: JsonObject, k: String): Double? = when (val v = o[k]) {
    null -> null
    JsonNull -> 0.0
    is JsonPrimitive -> if (!v.isString) v.content.toDoubleOrNull() ?: Double.NaN else Double.NaN
    else -> Double.NaN
}

private fun fallasCategoria(archivo: Path): Pair<Int, List<String>> {
    val casos = Vectores.json(archivo)["casos"]!!.jsonArray.map { it.jsonObject }
    val fallas = mutableListOf<String>()
    for (c in casos) {
        val name = (c["name"] as? JsonPrimitive)?.takeIf { it.isString }?.content
        val kotlin = CategoriaAlimento.inferir(name, numeroJs(c, "prot"), numeroJs(c, "carb"), numeroJs(c, "fat"))
        val app = c["app"]!!.jsonPrimitive.content
        val cliente = c["cliente"]!!.jsonPrimitive.content
        val fooddb = c["fooddb"]!!.jsonPrimitive.content
        if (kotlin != app || kotlin != cliente || kotlin != fooddb) {
            fallas += "${(name ?: "∅").debug()} ${c["prot"]}/${c["carb"]}/${c["fat"]}: app.js $app, cliente.html $cliente, food-db.js $fooddb, kotlin $kotlin"
        }
    }
    return casos.size to fallas
}

class CategoriaAlimentoTest {
    @Test
    fun vectoresPublicos() {
        val (n, fallas) = fallasCategoria(Vectores.publico("categoria_alimento"))
        assertTrue(n > 800, "$n casos")
        assertEquals(emptyList<String>(), fallas.take(8), "${fallas.size} de $n")
    }

    @Test
    fun alimentosDeLasDietasReales() {
        val (n, fallas) = fallasCategoria(Vectores.privado("categoria_alimento"))
        assertTrue(n > 1000, "$n casos")
        assertEquals(emptyList<String>(), fallas.take(8), "${fallas.size} de $n")
    }

    @Test
    fun porMacros() {
        assertEquals("proteina", CategoriaAlimento.porMacros(25.0, 2.0, 3.0))
        assertEquals("grasa", CategoriaAlimento.porMacros(1.0, 2.0, 50.0))
        assertEquals("carbohidrato", CategoriaAlimento.porMacros(2.0, 60.0, 1.0))
        assertEquals(null, CategoriaAlimento.porMacros(10.0, 10.0, 5.0))
        assertEquals(null, CategoriaAlimento.porMacros(null, null, null))
    }

    @Test
    fun laBaseEmpaquetadaTieneLasCategoriasDeLaRegla() {
        val base = baseEmpaquetada
        assertTrue(base.alimentos.size > 400)
        assertTrue(base.fuente?.startsWith("public/js/food-db.js@") == true, "${base.fuente}")
        val distintas = base.alimentos.filter { CategoriaAlimento.inferir(it.nombre, it.prot, it.carb, it.fat) != it.categoria }
        assertEquals(emptyList<String>(), distintas.take(5).map { it.nombre })
    }
}

// ── Sustitutos ──
// Formato compacto: ver el comentario de `compactador` en scripts/nativa/vectores-alimentos.mjs.

/** Lo que un sustituto toma de la base. */
private class AlimentoJs(o: JsonObject) {
    val name = o["name"]!!.jsonPrimitive.content
    val category = (o["category"] as? JsonPrimitive)?.takeIf { it.isString }?.content
    val esPropio = (o["_isCustom"] as? JsonPrimitive)?.boolean
    val universal = (o["_universal"] as? JsonPrimitive)?.boolean
    val en = (o["_en"] as? JsonPrimitive)?.takeIf { it.isString }?.content
}

/** `[a, qty, unit, kcal, prot, carb, fat, _dev]`. */
private class Item(e: JsonElement) {
    private val a = e.jsonArray
    val alimento = a[0].jsonPrimitive.int
    val qty = a[1].jsonPrimitive.double
    val unit = a[2].jsonPrimitive.content
    val kcal = a[3].jsonPrimitive.double
    val prot = a[4].jsonPrimitive.double
    val carb = a[5].jsonPrimitive.double
    val fat = a[6].jsonPrimitive.double
    val dev = a[7].jsonPrimitive.double
}

/** Lo que devolvió la web para un sustituto, como objeto de JS (el `food_data` que persiste). */
private fun objetoJs(e: Item, al: AlimentoJs): ValorJson {
    val o = linkedMapOf<String, ValorJson>(
        "name" to ValorJson.Texto(al.name), "qty" to ValorJson.Numero(e.qty), "unit" to ValorJson.Texto(e.unit),
        "kcal" to ValorJson.Numero(e.kcal), "prot" to ValorJson.Numero(e.prot), "carb" to ValorJson.Numero(e.carb),
        "fat" to ValorJson.Numero(e.fat), "_dev" to ValorJson.Numero(e.dev),
    )
    al.category?.let { o["category"] = ValorJson.Texto(it) }
    if (al.esPropio == true) o["_isCustom"] = ValorJson.Booleano(true)
    if (al.universal == true) {
        o["_universal"] = ValorJson.Booleano(true)
        o["_en"] = ValorJson.Texto(al.en ?: "")
    }
    return ValorJson.Objeto(o)
}

private fun igualAWeb(s: Sustituto, e: Item, al: AlimentoJs): Boolean =
    s.nombre == al.name && casiIgual(s.qty, e.qty) && s.unidad == e.unit && casiIgual(s.kcal, e.kcal) &&
        casiIgual(s.prot, e.prot) && casiIgual(s.carb, e.carb) && casiIgual(s.fat, e.fat) && s.categoria == al.category &&
        casiIgual(s.desvio, e.dev) && s.esPropio == (al.esPropio == true) && s.universal == (al.universal == true) &&
        s.nombreIngles == (if (al.universal == true) al.en else null) && casiIgual(s.foodData, objetoJs(e, al))

private fun fallasSustitutos(archivo: Path): Pair<Int, List<String>> {
    val v = Vectores.json(archivo)
    val base = baseEmpaquetada
    val fallas = mutableListOf<String>()
    val largo = v["base"]!!.jsonObject["largo"]!!.jsonPrimitive.int
    if (base.alimentos.size != largo) fallas += "food-db.json tiene ${base.alimentos.size} alimentos y los vectores $largo: regenerar"
    val conPropios = base.conPropios(listaEstricta(v["propios"]!!, AlimentoPropio::desde))
    (v["baseConPropios"] as? JsonObject)?.let { esperado ->
        val propios = conPropios.alimentos.indices.filter { conPropios.alimentos[it].esPropio }
        val largoP = esperado["largo"]!!.jsonPrimitive.int
        val propiosP = esperado["propios"]!!.jsonArray.map { it.jsonPrimitive.int }
        if (conPropios.alimentos.size != largoP || propios != propiosP) {
            fallas += "conPropios: ${conPropios.alimentos.size} alimentos, propios en $propios; la web: $largoP, $propiosP"
        }
    }
    val preferencias = v["preferencias"]!!.jsonArray.map { p -> p.jsonArray.map { it.jsonPrimitive.content } }
    val originales = listaEstricta(v["originales"]!!, Alimento::desde)
    val alimentos = v["alimentos"]!!.jsonArray.map { AlimentoJs(it.jsonObject) }
    val items = v["items"]!!.jsonArray.map(::Item)
    val resultados = v["resultados"]!!.jsonArray.map { r -> r.jsonArray.map { it.jsonPrimitive.int } }
    val casos = v["casos"]!!.jsonArray.map { it.jsonObject }

    val obtenidos = mutableListOf<List<Sustituto>>()
    for ((k, c) in casos.withIndex()) {
        val original = originales[c["o"]!!.jsonPrimitive.int]
        val excluir = preferencias[c["x"]!!.jsonPrimitive.int]
        val conP = c["p"]!!.jsonPrimitive.boolean
        val r = SustitucionAlimentos.buscar(original, if (conP) conPropios else base, excluir)
        obtenidos += r.sustitutos
        val donde = "caso $k (${original.nombre.debug()}, excluir $excluir, propios $conP)"
        val i = c["info"]!!.jsonArray
        val infoWeb = InfoSustitucion(i[0].jsonPrimitive.int, i[1].jsonPrimitive.boolean, i[2].jsonPrimitive.boolean)
        if (r.info != infoWeb) fallas += "$donde: info web $infoWeb, kotlin ${r.info}"
        val esperados = resultados[c["r"]!!.jsonPrimitive.int].map { items[it] }
        if (r.sustitutos.size != esperados.size) {
            val primero = r.sustitutos.zip(esperados).indexOfFirst { (s, e) -> !igualAWeb(s, e, alimentos[e.alimento]) }
            fallas += "$donde: web ${esperados.size} sustitutos, kotlin ${r.sustitutos.size}; primera diferencia en $primero"
            continue
        }
        for ((n, par) in r.sustitutos.zip(esperados).withIndex()) {
            val (s, e) = par
            if (!igualAWeb(s, e, alimentos[e.alimento])) {
                fallas += "$donde #$n: web ${objetoJs(e, alimentos[e.alimento]).serializar()}, kotlin ${s.foodData.serializar()}"
                break
            }
        }
    }

    for (b in (v["busquedas"] as? JsonArray ?: JsonArray(emptyList())).map { it.jsonObject }) {
        val lista = obtenidos[b["c"]!!.jsonPrimitive.int]
        val consulta = b["consulta"]!!.jsonPrimitive.content
        val hallados = SustitucionAlimentos.filtrar(lista, consulta)
        val posiciones = hallados.map { h -> lista.indexOfFirst { it.nombre == h.nombre } }
        val web = b["posiciones"]!!.jsonArray.map { it.jsonPrimitive.int }
        if (posiciones != web) fallas += "búsqueda ${consulta.debug()} en el caso ${b["c"]}: web $web, kotlin $posiciones"
    }
    return casos.size to fallas
}

class SustitucionAlimentosTest {
    @Test
    fun vectoresPublicos() {
        val (n, fallas) = fallasSustitutos(Vectores.publico("sustitutos_alimento"))
        assertTrue(n > 2000, "$n casos")
        assertEquals(emptyList<String>(), fallas.take(5), "${fallas.size} fallas en $n casos")
    }

    @Test
    fun alimentosDeLasDietasReales() {
        val (n, fallas) = fallasSustitutos(Vectores.privado("sustitutos_alimento"))
        assertTrue(n > 1000, "$n casos")
        assertEquals(emptyList<String>(), fallas.take(5), "${fallas.size} fallas en $n casos")
    }

    @Test
    fun sinBaseNoHaySustitutos() {
        val r = SustitucionAlimentos.buscar(
            Alimento(nombre = "Arroz", qty = 100.0, unidad = "g", kcal = 130.0, prot = 2.7, carb = 28.0, fat = 0.3), BaseAlimentos(emptyList()),
        )
        assertTrue(r.sustitutos.isEmpty())
        assertEquals(InfoSustitucion(), r.info)
    }

    @Test
    fun losPropiosReemplazanPorNombreOSeAgregan() {
        val base = baseEmpaquetada
        val propios = listaEstricta(
            """[{"name": "CUADRIL", "kcal": 140, "prot": 21, "carb": 0, "fat": 6, "unit": "g", "unit_grams": null, "category": "proteina"},
                {"name": "Barrita casera", "kcal": null, "prot": 30, "carb": 40, "fat": 10, "unit": "unidad", "unit_grams": 0}]""",
            AlimentoPropio::desde,
        )
        val con = base.conPropios(propios)
        assertEquals(base.alimentos.size + 1, con.alimentos.size)
        val i = base.alimentos.indexOfFirst { it.nombre == "Cuadril" }
        assertTrue(i >= 0)
        assertTrue(con.alimentos[i].nombre == "CUADRIL" && con.alimentos[i].esPropio && con.alimentos[i].kcal == 140.0)
        val barrita = con.alimentos.last()
        assertTrue(barrita.esPropio && barrita.kcal == 0.0 && barrita.gramosPorUnidad == null && barrita.categoria == null)
    }
}

/** Gemelo de SemanticaJSAlimentosTests (lo de las regex y el trim está en JsRegexTest y NumeroJsTest). */
class SemanticaJsAlimentosTest {
    @Test
    fun textoPorUnidadesUtf16() {
        val nfc = "Vacío"
        val nfd = "Vacío"
        assertFalse(nfc == nfd)                                    // JS (y Kotlin): otro texto
        assertTrue("pań".contains("pan"))
        assertEquals("vacío", SustitucionAlimentos.normalizar(nfd))   // la tilde suelta no se toca, como en la web
        assertEquals("nandu nono", SustitucionAlimentos.normalizar("ÑANDÚ Ñoño"))
    }

    @Test
    fun universalesYEtiquetas() {
        assertTrue(SustitucionAlimentos.esUniversal("Pan francés / baguette"))
        assertFalse(SustitucionAlimentos.esUniversal("Panceta"))
        assertEquals("Lean ground beef (90/10)", SustitucionAlimentos.etiquetaIngles("Carne vacuna picada (magra 90/10)"))
        assertEquals("Bread", SustitucionAlimentos.etiquetaIngles("Panceta"))   // `includes`, no palabra: así lo hace la web
        assertEquals("", SustitucionAlimentos.etiquetaIngles("Brócoli"))
    }

    @Test
    fun ordenEstableComoJs() {
        val l = listOf("b" to 1.0, "a" to 0.5, "c" to 1.0, "d" to Double.NaN, "e" to 0.5)
        val o = SemanticaJs.ordenarEstable(l) { x, y -> val d = x.second - y.second; if (d < 0) -1 else if (d > 0) 1 else 0 }
        assertEquals(5, o.size)                                   // con un NaN no tira excepción
        val sinNan = SemanticaJs.ordenarEstable(l.filter { !it.second.isNaN() }) { x, y -> x.second.compareTo(y.second) }
        assertEquals(listOf("a", "e", "b", "c"), sinNan.map { it.first })   // los empates, en el orden de entrada
    }
}
