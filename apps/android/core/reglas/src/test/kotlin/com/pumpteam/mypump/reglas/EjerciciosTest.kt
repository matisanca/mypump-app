package com.pumpteam.mypump.reglas

import com.pumpteam.mypump.modelos.Ejercicio
import com.pumpteam.mypump.modelos.EntradaCatalogoEjercicio
import com.pumpteam.mypump.modelos.Imagenes
import java.nio.file.Files
import java.nio.file.Path
import java.security.MessageDigest
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * Gemelo de EjerciciosTests.swift: las funciones REALES de la web (`exerciseSwap` de app.js, `getEffectiveEx` y
 * `exGetSubs` de cliente.html) corridas sobre el catálogo empaquetado, por scripts/nativa/vectores-ejercicios.mjs.
 * Igualdad total.
 */
private class ArchivoSustitutos(p: Path) {
    val v: JsonObject = Vectores.json(p)
    val catalogo: JsonObject = v["catalogo"]!!.jsonObject
    /** `[_toEs, _equipLabel]` de cada fila del catálogo, por índice. */
    val traducciones: List<List<String>> = v["traducciones"]!!.jsonArray.map { t -> t.jsonArray.map { it.jsonPrimitive.content } }
    val sinteticas: List<JsonObject> = v["sinteticas"]!!.jsonArray.map { it.jsonObject }
    val orden: JsonObject = v["orden"]!!.jsonObject
    /** `findSubstitutes` de cada fila: slug → `[[índice de la fila del sustituto, _sameEquip]]`. Sin clave = vacía. */
    val listas: Map<String, List<List<Int>>> = pares(v["listas"]!!.jsonObject)
    val listasAlReves: Map<String, List<List<Int>>> = pares(v["listasAlReves"]!!.jsonObject)
    val nombres: List<JsonObject> = v["nombres"]!!.jsonArray.map { it.jsonObject }
    val ejercicios: List<JsonObject> = v["ejercicios"]!!.jsonArray.map { it.jsonObject }
    val casos: List<JsonObject> = v["casos"]!!.jsonArray.map { it.jsonObject }
    /** Solo en los públicos. */
    val sintetico: JsonObject? = v["sintetico"] as? JsonObject

    private fun pares(o: JsonObject) = o.mapValues { (_, l) -> l.jsonArray.map { p -> p.jsonArray.map { it.jsonPrimitive.int } } }
}

private fun cargar(p: Path): Pair<ArchivoSustitutos, CatalogoEjercicios> {
    val v = ArchivoSustitutos(p)
    val archivo = Vectores.raizRepo.resolve(v.catalogo["archivo"]!!.jsonPrimitive.content)
    val datos = Files.readAllBytes(archivo)
    val hash = MessageDigest.getInstance("SHA-256").digest(datos).joinToString("") { "%02x".format(it) }
    assertEquals(v.catalogo["sha256"]!!.jsonPrimitive.content, hash,
        "el catálogo no es con el que se generaron los vectores: node scripts/nativa/vectores-ejercicios.mjs --sin-red")
    return v to CatalogoEjercicios.desde(String(datos, Charsets.UTF_8))
}

private fun texto(e: JsonElement?): String? = (e as? JsonPrimitive)?.takeIf { it !is JsonNull && it.isString }?.content

/** `x || null` de JS sobre un texto. */
private fun nuloSiVacio(s: String?): String? = s?.takeIf { it.isNotEmpty() }

/** Las imágenes de JS (objeto o null; una clave que falta vale null) contra las de Kotlin. */
private fun igualesImagenes(js: JsonElement?, k: Imagenes?): Boolean {
    val o = js as? JsonObject ?: return k == null
    if (k == null) return false
    return texto(o["eccentric"]) == k.eccentric && texto(o["concentric"]) == k.concentric && texto(o["_matched_slug"]) == k.matchedSlug
}

private fun imagenes(js: JsonElement?): Imagenes? = (js as? JsonObject)?.let(Imagenes::desde)

/**
 * La lista de Kotlin contra la de la web. La web guarda cada sustituto como [fila, _sameEquip]: el generador ya verificó
 * que el objeto de `findSubstitutes` es esa fila con su `_toEs` y su `_equipLabel` (y "" como null en las imágenes);
 * acá se exige lo mismo, campo por campo.
 */
private fun diferencia(k: List<SustitutoEjercicio>, web: List<List<Int>>, cat: CatalogoEjercicios, trad: List<List<String>>): String? {
    if (k.size != web.size) {
        return "${k.size} sustitutos y la web ${web.size}: kotlin ${k.map { it.slug }}, web ${web.map { cat.entradas[it[0]].slugEn }}"
    }
    for ((n, par) in k.zip(web).withIndex()) {
        val (s, w) = par
        val e = cat.entradas[w[0]]
        val ok = s.slug == e.slugEn && s.nombre == trad[w[0]][0] && s.nombreIngles == e.nameEn && s.equipo == trad[w[0]][1] &&
            s.equipoCrudo == e.equipment && s.musculo == e.primaryMuscle && s.patron == e.patronMovimiento &&
            s.imagenes.eccentric == nuloSiVacio(e.imageEccentric) && s.imagenes.concentric == nuloSiVacio(e.imageConcentric) &&
            s.imagenes.matchedSlug == null && s.mismoEquipo == (w[1] == 1)
        if (!ok) return "posición $n: kotlin $s, web ${e.slugEn} ${trad[w[0]]} mismo equipo ${w[1]}"
    }
    return null
}

/** Sustitutos enteros, tal como los devolvió `findSubstitutes`, contra los de Kotlin. */
private fun diferenciaCompleta(k: List<SustitutoEjercicio>, web: List<JsonObject>): String? {
    if (k.size != web.size) return "${k.size} sustitutos y la web ${web.size}: kotlin ${k.map { it.slug }}, web ${web.map { texto(it["slug"]) }}"
    for ((n, par) in k.zip(web).withIndex()) {
        val (s, w) = par
        val ok = s.slug == texto(w["slug"]) && s.nombre == texto(w["name"]) && s.nombreIngles == texto(w["name_en"]) &&
            s.equipo == texto(w["equipo"]) && s.equipoCrudo == texto(w["equipmentRaw"]) && s.musculo == texto(w["primary_muscle"]) &&
            s.patron == texto(w["patron_movimiento"]) && igualesImagenes(w["images"], s.imagenes) &&
            (w["_sameEquip"] == JsonPrimitive(true)) == s.mismoEquipo
        if (!ok) return "posición $n: kotlin $s, web $w"
    }
    return null
}

/** `getEffectiveEx` de la web contra `efectivo` de Kotlin. `Ejercicio.nombre` no distingue ausente de "". */
private fun diferenciaEfectivo(js: JsonObject?, ef: EjercicioEfectivo): String? {
    if (js == null) return "el vector no trae efectivo"
    val malos = mutableListOf<String>()
    if ((texto(js["nombre"]) ?: "") != ef.ejercicio.nombre) malos += "nombre"
    if (!igualesImagenes(js["images"], ef.ejercicio.imagenes)) malos += "images"
    if ((js["_isSwapped"] == JsonPrimitive(true)) != ef.sustituido) malos += "_isSwapped"
    if (texto(js["_swapSlug"]) != ef.slugSustituto) malos += "_swapSlug"
    if ((js["_swapFijado"] == JsonPrimitive(true)) != ef.fijado) malos += "_swapFijado"
    if ((texto(js["_origNombre"]) ?: "") != (ef.nombreOriginal ?: "")) malos += "_origNombre"
    if (!igualesImagenes(js["_origImages"], ef.imagenesOriginales)) malos += "_origImages"
    if (texto(js["_origSlug"]) != ef.slugOriginal) malos += "_origSlug"
    return if (malos.isEmpty()) null else "$malos: web $js, kotlin $ef"
}

/**
 * Cada ejercicio: `_resolve` y `findSubstitutes` del ejercicio del plan; `getEffectiveEx` con y sin sustitución; y
 * `exGetSubs` sobre el efectivo (o sobre el objeto con `_orig*`, en los casos directos).
 */
private fun fallasCasos(v: ArchivoSustitutos, cat: CatalogoEjercicios): List<String> {
    val fallas = mutableListOf<String>()
    fun lista(slug: String?) = slug?.let { v.listas[it] } ?: emptyList()
    for (c in v.casos) {
        val crudo = v.ejercicios[c["e"]!!.jsonPrimitive.int]
        val ex = Ejercicio.desde(crudo)
        val quien = "#${c["e"]} ${ex.nombre.debug()}"
        val ef: EjercicioEfectivo
        if (c["directo"] == JsonPrimitive(true)) {
            ef = EjercicioEfectivo(ejercicio = ex, nombreOriginal = texto(crudo["_origNombre"]),
                imagenesOriginales = imagenes(crudo["_origImages"]), slugOriginal = texto(crudo["_origSlug"]))
        } else {
            val resuelto = texto(c["resuelto"])
            val r = cat.resolver(ex)
            if (r?.slugEn != resuelto) fallas += "$quien: _resolve web $resuelto, kotlin ${r?.slugEn}"
            diferencia(cat.sustitutos(ReferenciaEjercicio(ex)), lista(resuelto), cat, v.traducciones)?.let { fallas += "$quien: findSubstitutes $it" }
            val sw = (c["sw"] as? JsonObject)?.let {
                SustitucionAplicada(slug = texto(it["slug"]), nombre = texto(it["nombre"]) ?: "", equipo = texto(it["equipment"]),
                    imagenes = imagenes(it["images"]), fijado = it["fijado"] == JsonPrimitive(true))
            }
            ef = cat.efectivo(ex, sw)
            diferenciaEfectivo(c["efectivo"] as? JsonObject, ef)?.let { fallas += "$quien${if (sw == null) "" else " sustituido"}: getEffectiveEx $it" }
        }
        val subs = cat.sustitutos(ef)
        if (c["excluido"] == JsonPrimitive(true)) {
            if (subs.isNotEmpty()) fallas += "$quien: calentamiento o cardio con ${subs.size} sustitutos"
        } else {
            val resueltoUi = texto(c["resueltoUI"])
            val r = cat.resolver(CatalogoEjercicios.referencia(ef))
            if (r?.slugEn != resueltoUi) fallas += "$quien: exGetSubs resolvió web $resueltoUi, kotlin ${r?.slugEn}"
            diferencia(subs, lista(resueltoUi), cat, v.traducciones)?.let { fallas += "$quien: exGetSubs $it" }
        }
        if (subs.size != c["subs"]!!.jsonPrimitive.int) fallas += "$quien: exGetSubs da ${subs.size}, la web ${c["subs"]}"
    }
    return fallas
}

/** `_norm`, `_resolveByRules` y `_resolve` por nombre. */
private fun fallasNombres(v: ArchivoSustitutos, cat: CatalogoEjercicios): List<String> = v.nombres.mapNotNull { x ->
    val n = x["n"]!!.jsonPrimitive.content
    val norm = SustitucionEjercicios.normalizar(n)
    val regla = SustitucionEjercicios.slugPorReglas(n)
    val slug = cat.resolver(ReferenciaEjercicio(nombre = n))?.slugEn
    if (norm == texto(x["norm"]) && regla == texto(x["regla"]) && slug == texto(x["slug"])) null
    else "${n.debug()}: web (${texto(x["norm"])?.debug()}, ${texto(x["regla"])}, ${texto(x["slug"])}), kotlin (${norm.debug()}, $regla, $slug)"
}

class SustitucionEjerciciosTest {
    private val publicos = Vectores.publico("sustitutos_ejercicio")

    /**
     * Nombres que la app cambia a propósito (20-oct, igual que iOS): la patada de tríceps, que la web llama «Patada de
     * glúteo». Allá no se ve; en la app aparece entre los otros ejercicios de tríceps y es el nombre que se registra.
     */
    private val desvios = mapOf("Tricep_Dumbbell_Kickback" to ("Patada de glúteo con mancuernas" to "Patada de tríceps con mancuernas"))

    @Test
    fun traduccionesDelCatalogo() {
        val (v, cat) = cargar(publicos)
        assertEquals(v.catalogo["filas"]!!.jsonPrimitive.int, cat.entradas.size)
        val fallas = mutableListOf<String>()
        for ((i, e) in cat.entradas.withIndex()) {
            val es = SustitucionEjercicios.castellano(e)
            val eq = SustitucionEjercicios.etiquetaEquipo(e)
            // Los desvíos a propósito: la web sigue con su nombre (si lo arregla allá, esto avisa).
            val d = desvios[e.slugEn]
            if (d != null) {
                if (v.traducciones[i][0] != d.first || es != d.second) fallas += "${e.slugEn}: desvío $d, web ${v.traducciones[i][0]}, kotlin $es"
                continue
            }
            if (es != v.traducciones[i][0] || eq != v.traducciones[i][1]) fallas += "${e.slugEn}: web ${v.traducciones[i]}, kotlin [$es, $eq]"
        }
        for (s in v.sinteticas) {
            val entrada = EntradaCatalogoEjercicio.desde(s["entrada"]!!)
            val es = SustitucionEjercicios.castellano(entrada)
            val eq = SustitucionEjercicios.etiquetaEquipo(entrada)
            if (es != texto(s["es"]) || eq != texto(s["equipo"])) {
                fallas += "${entrada.nameEn?.debug()} / ${entrada.equipment}: web [${texto(s["es"])}, ${texto(s["equipo"])}], kotlin [$es, $eq]"
            }
        }
        assertTrue(v.sinteticas.size > 200)
        assertEquals(emptyList<String>(), fallas.take(8), "${fallas.size} de ${cat.entradas.size + v.sinteticas.size}")
    }

    @Test
    fun ordenComoLocaleCompare() {
        val (v, _) = cargar(publicos)
        val e = v.orden["entrada"]!!.jsonArray.map { it.jsonPrimitive.content }
        val web = v.orden["salida"]!!.jsonArray.map { it.jsonPrimitive.int }
        val kotlin = SemanticaJs.ordenarEstable(e.indices.toList()) { a, b -> SustitucionEjercicios.compararNombres(e[a], e[b]) }
        assertTrue(e.size > 1000)
        val primera = kotlin.zip(web).indexOfFirst { it.first != it.second }
        assertEquals(web, kotlin, if (primera < 0) "el largo" else "primera diferencia en $primera: kotlin ${e[kotlin[primera]].debug()}, web ${e[web[primera]].debug()}")
    }

    @Test
    fun nombresYReglas() {
        val (v, cat) = cargar(publicos)
        val fallas = fallasNombres(v, cat)
        assertTrue(v.nombres.size > 300)
        assertEquals(emptyList<String>(), fallas.take(8), "${fallas.size} de ${v.nombres.size}")
    }

    /** Todas las listas posibles: `findSubstitutes` de cada fila del catálogo, en el orden del archivo y al revés. */
    @Test
    fun listasDeTodoElCatalogo() {
        val (v, cat) = cargar(publicos)
        val alReves = CatalogoEjercicios(cat.entradas.reversed())
        val fallas = mutableListOf<String>()
        for (e in cat.entradas) {
            val slug = e.slugEn ?: ""
            diferencia(cat.sustitutos(ReferenciaEjercicio(catalogoSlug = slug)), v.listas[slug] ?: emptyList(), cat, v.traducciones)
                ?.let { fallas += "$slug: $it" }
            // Al revés cambian la variante que queda de cada nombre repetido y el orden de los empates.
            val web = v.listasAlReves[slug] ?: v.listas[slug] ?: emptyList()
            diferencia(alReves.sustitutos(ReferenciaEjercicio(catalogoSlug = slug)), web, cat, v.traducciones)
                ?.let { fallas += "$slug al revés: $it" }
        }
        assertTrue(v.listas.size > 400)
        assertTrue(v.listasAlReves.size > 100)
        assertEquals(emptyList<String>(), fallas.take(5), "${fallas.size} de ${2 * cat.entradas.size}")
    }

    /**
     * Lo que el catálogo real hoy no ejercita: el tope de 30, slugs repetidos, un alias igual al `name_normalized` de otra
     * fila, null === null, patrón "", filas sin foto y un slug con acento descompuesto.
     */
    @Test
    fun catalogoSintetico() {
        val (v, _) = cargar(publicos)
        val s = v.sintetico!!
        val cat = CatalogoEjercicios(s["catalogo"]!!.jsonArray.map(EntradaCatalogoEjercicio::desde))
        val fallas = mutableListOf<String>()
        val casos = s["casos"]!!.jsonArray.map { it.jsonObject }
        for (c in casos) {
            val ref = c["ref"]!!.jsonObject
            val r = ReferenciaEjercicio(nombre = texto(ref["nombre"]), imagenes = imagenes(ref["images"]),
                catalogoSlug = texto(ref["catalogo_slug"]), matchedSlug = texto(ref["_matched_slug"]))
            // La fila resuelta por identidad: con slugs repetidos, dos filas pueden tener los mismos datos.
            val resuelto = cat.resolver(r)?.let { e -> cat.entradas.indexOfFirst { it === e } }
            val web = (c["resuelto"] as? JsonPrimitive)?.takeIf { it !is JsonNull }?.int
            if (resuelto != web) fallas += "$ref: _resolve web fila $web, kotlin $resuelto"
            diferenciaCompleta(cat.sustitutos(r), c["subs"]!!.jsonArray.map { it.jsonObject })?.let { fallas += "$ref: findSubstitutes $it" }
        }
        for (c in s["efectivos"]!!.jsonArray.map { it.jsonObject }) {
            val ex = Ejercicio.desde(c["ex"]!!)
            val ef = cat.efectivo(ex, null)
            diferenciaEfectivo(c["efectivo"] as? JsonObject, ef)?.let { fallas += "${c["ex"]}: getEffectiveEx $it" }
            diferenciaCompleta(cat.sustitutos(ef), c["subs"]!!.jsonArray.map { it.jsonObject })?.let { fallas += "${c["ex"]}: exGetSubs $it" }
        }
        assertTrue(casos.any { it["subs"]!!.jsonArray.size == 30 })
        assertEquals(emptyList<String>(), fallas.take(5), "${fallas.size} de ${casos.size + s["efectivos"]!!.jsonArray.size}")
    }

    @Test
    fun casosPublicos() {
        val (v, cat) = cargar(publicos)
        val fallas = fallasCasos(v, cat)
        assertTrue(v.casos.size > 250)
        assertTrue(v.casos.any { it["sw"] is JsonObject } && v.casos.any { it["directo"] == JsonPrimitive(true) } &&
            v.casos.any { it["excluido"] == JsonPrimitive(true) })
        assertEquals(emptyList<String>(), fallas.take(5), "${fallas.size} de ${v.casos.size}")
    }

    @Test
    fun ejerciciosDeLosPlanesReales() {
        val (v, cat) = cargar(Vectores.privado("sustitutos_ejercicio"))
        val fallas = fallasCasos(v, cat) + fallasNombres(v, cat)
        assertTrue(v.casos.size > 2000, "${v.casos.size} casos")
        assertTrue(v.nombres.size > 500, "${v.nombres.size} nombres")
        assertEquals(emptyList<String>(), fallas.take(5), "${fallas.size} de ${v.casos.size + v.nombres.size}")
    }

    /** Lo que Java o ICU harían distinto si no se tradujera (lo esperado salió de node). */
    @Test
    fun semanticaDeJs() {
        // El `.` de JS toma VT, FF y NEL: el paréntesis se va entero.
        assertEquals("curl martillo", SustitucionEjercicios.normalizar("Curl (a\u000Bb) martillo"))
        assertEquals("curl martillo", SustitucionEjercicios.normalizar("Curl (a\u0085b) martillo"))
        assertEquals("curl martillo", SustitucionEjercicios.normalizar("Curl (a\u000Cb) martillo"))
        // `\n` y U+2028 sí lo cortan, como en JS.
        assertEquals("curl a b martillo", SustitucionEjercicios.normalizar("Curl (a\nb) martillo"))
        assertEquals("curl a b martillo", SustitucionEjercicios.normalizar("Curl (a b) martillo"))
        // Acento descompuesto: la web no lo normaliza.
        assertEquals("jalo n", SustitucionEjercicios.normalizar("Jalón"))
        // `/\bsmith\b/i` sin flag u: la "ſ" no es "s".
        assertEquals("Barra", SustitucionEjercicios.etiquetaEquipo(EntradaCatalogoEjercicio(slugEn = "x", nameEn = "ſmith row", equipment = "barbell")))
        assertEquals("Multipower", SustitucionEjercicios.etiquetaEquipo(EntradaCatalogoEjercicio(slugEn = "x", nameEn = "SMITH row", equipment = "barbell")))
        // `exec`: la primera aparición, aunque no esté en el catálogo.
        assertEquals("No_Existe", SustitucionEjercicios.slugDeUrl("a/exercise-images/No_Existe/exercise-images/Leg_Press/0.jpg"))
        assertNull(SustitucionEjercicios.slugDeUrl("exercise-images//0.jpg"))
    }
}


/**
 * Los otros ejercicios del mismo músculo (Mati, 20-oct: Eric, con la polea ocupada, no tenía con qué cambiar la extensión
 * en polea; quería fondos). Es de la app: la web solo ofrece el mismo movimiento. Gemelo de OtrosDelMismoMusculoTests.
 */
class OtrosDelMismoMusculoTest {
    private val cat = CatalogoEjercicios.desde(Vectores.texto(Vectores.compartido("catalogo-ejercicios.json")))

    @Test
    fun aLaExtensionEnPoleaLeQuedanFondosYExtensiones() {
        val r = ReferenciaEjercicio(nombre = "Extensión en polea alta con barra", catalogoSlug = "Triceps_Pushdown")
        val arriba = cat.sustitutos(r)
        val otros = cat.otrosDelMismoMusculo(r)
        val nombres = otros.map { "${it.nombre} · ${it.equipo}" }
        assertEquals(listOf("Extensión de tríceps en polea"), arriba.map { it.nombre }, "las variantes de siempre, igual que la web")
        assertTrue("Fondos · Peso corporal" in nombres, nombres.toString())
        assertTrue("Patada de tríceps con mancuernas · Mancuernas" in nombres)
        assertTrue("Press francés con barra Z · Barra Z" in nombres)
        assertTrue(otros.none { it.nombre == "Press" || it.nombre == it.nombreIngles }, "sin nombres sueltos ni sin traducir")
        assertTrue(otros.none { s -> arriba.any { it.nombre == s.nombre && it.equipo == s.equipo } }, "sin repetir lo de arriba")
        assertTrue(otros.all { it.musculo == "triceps" && it.patron != null && it.patron != "extension_triceps_pushdown" })
        val desde = otros.indexOfFirst { it.mismoEquipo }.let { if (it < 0) otros.size else it }
        assertTrue(desde > 0 && otros.drop(desde).all { it.mismoEquipo }, "otro equipo primero")
        assertTrue(otros.size in 15..30, "${otros.size}")
    }

    @Test
    fun unaFilaMalClasificadaNoSeOfrece() {
        assertEquals("traps", cat.musculoDePatron("encogimiento_trapecio"))
        assertEquals("triceps", cat.musculoDePatron("fondos_paralelas"))
        val remo = cat.otrosDelMismoMusculo(ReferenciaEjercicio(nombre = "Remo con barra", catalogoSlug = "Bent_Over_Barbell_Row"))
        assertTrue(remo.none { it.nombre.startsWith("Encogimientos") }, remo.map { it.nombre }.toString())
        val sentadilla = cat.otrosDelMismoMusculo(ReferenciaEjercicio(nombre = "Sentadilla con barra", catalogoSlug = "Barbell_Squat"))
        assertTrue(sentadilla.any { it.patron == "zancada_unilateral" } && sentadilla.any { it.patron == "extension_rodilla" })
        assertTrue(sentadilla.all { it.musculo == "quadriceps" })
    }

    @Test
    fun sinPatronNoSeOfreceNada() {
        val r = ReferenciaEjercicio(nombre = "Bench Press - Powerlifting", catalogoSlug = "Bench_Press_-_Powerlifting")
        assertTrue(cat.sustitutos(r).isEmpty() && cat.otrosDelMismoMusculo(r).isEmpty())
    }

    /** Las mismas listas que grabó iOS (apps/shared/vectores/otros_mismo_musculo.json), elemento por elemento. */
    @Test
    fun lasMismasListasQueIos() {
        val listas = Vectores.json(Vectores.publico("otros_mismo_musculo"))["listas"]!!.jsonObject
        assertEquals(8, listas.size)
        for ((slug, esperada) in listas) {
            val ios = esperada.jsonArray.map { it.jsonPrimitive.content }
            val android = cat.otrosDelMismoMusculo(ReferenciaEjercicio(catalogoSlug = slug)).map { "${it.nombre} · ${it.equipo}" }
            assertEquals(ios, android, slug)
        }
    }

    /** Y todo el catálogo: la huella de la lista de cada ejercicio (los 16 primeros hex del SHA-256), igual a la de iOS. */
    @Test
    fun lasMismasHuellasQueIos() {
        val ios = Vectores.json(Vectores.publico("otros_mismo_musculo"))["huellas"]!!.jsonObject.mapValues { it.value.jsonPrimitive.content }
        val android = LinkedHashMap<String, String>()
        for (slug in cat.entradas.mapNotNull { it.slugEn }) {
            if (slug in android) continue
            val lista = cat.otrosDelMismoMusculo(ReferenciaEjercicio(catalogoSlug = slug)).map { "${it.nombre} · ${it.equipo}" }
            if (lista.isEmpty()) continue
            val sha = MessageDigest.getInstance("SHA-256").digest(lista.joinToString("\n").toByteArray(Charsets.UTF_8))
            android[slug] = sha.take(8).joinToString("") { "%02x".format(it) }
        }
        assertTrue(ios.size > 300, "${ios.size}")
        assertEquals(ios.keys.sorted(), android.keys.sorted(), "los mismos ejercicios con otros del mismo músculo")
        for ((slug, h) in ios) assertEquals(h, android[slug], slug)
    }
}
