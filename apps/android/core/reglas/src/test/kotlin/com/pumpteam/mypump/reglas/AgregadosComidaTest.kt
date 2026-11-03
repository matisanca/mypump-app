package com.pumpteam.mypump.reglas

import com.pumpteam.mypump.modelos.Alimento
import com.pumpteam.mypump.modelos.AlimentoPropio
import com.pumpteam.mypump.modelos.Comida
import com.pumpteam.mypump.modelos.ComidaMarcada
import com.pumpteam.mypump.modelos.ValorJson
import kotlin.math.abs
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * Alimentos agregados a una comida (2.0.3, D1) y la hoja de cantidad (D2): los vectores que grabó iOS
 * (`AgregadosComidaTests`) tienen que salir igual acá, número por número, y la lectura y los topes se comportan igual.
 */
class AgregadosComidaTest {
    private val todo: JsonObject by lazy { Vectores.json(Vectores.publico("agregados_comida")) }

    private fun cerca(a: Double?, b: Double?): Boolean = if (a == null || b == null) a == b else abs(a - b) < 1e-9
    private fun d(e: JsonElement?): Double? = (e as? JsonPrimitive)?.doubleOrNull
    private fun texto(e: JsonElement?): String = e!!.jsonPrimitive.content

    private fun candidato(e: JsonElement): AgregadosComida.Candidato {
        val o = e.jsonObject
        return AgregadosComida.Candidato(
            texto(o["nombre"]), MacrosPor100.desde(ValorJson.desde(o["por100"]!!))!!, (o["unidad"] as? JsonPrimitive)?.content,
            d(o["gramosPorUnidad"]), AlimentoAgregado.Origen.entries.first { it.valor == texto(o["origen"]) },
        )
    }

    private fun medida(e: JsonElement): AgregadosComida.Medida = AgregadosComida.Medida(texto(e.jsonObject["nombre"]), d(e.jsonObject["gramos"])!!)

    @Test
    fun lasMedidasSalenIgual() {
        val casos = todo["medidas"]!!.jsonArray
        assertEquals(14, casos.size, "cambió la cantidad de casos: regenerar en iOS y revisar acá")
        for (caso in casos) {
            val o = caso.jsonObject
            val c = candidato(o["candidato"]!!)
            assertEquals(o["medidas"]!!.jsonArray.map(::medida), AgregadosComida.medidas(c), c.nombre)
            val (q, m) = AgregadosComida.inicial(c)
            val i = o["inicial"]!!.jsonObject
            assertTrue(cerca(d(i["cantidad"]), q) && medida(i["medida"]!!) == m, "${c.nombre}: inicial")
        }
    }

    @Test
    fun losPasosSalenIgual() {
        val casos = todo["pasos"]!!.jsonArray
        assertEquals(34, casos.size)
        for (caso in casos) {
            val o = caso.jsonObject
            val q = d(o["cantidad"])!!
            val m = medida(o["medida"]!!)
            assertTrue(cerca(d(o["subir"]), AgregadosComida.subir(q, m)), "subir $q ${m.nombre}")
            assertTrue(cerca(d(o["bajar"]), AgregadosComida.bajar(q, m)), "bajar $q ${m.nombre}")
            assertTrue(cerca(d(o["acotar"]), AgregadosComida.acotar(q, m)), "acotar $q ${m.nombre}")
        }
    }

    @Test
    fun losAgregadosSalenIgualYSeEscribenIgual() {
        val casos = todo["agregados"]!!.jsonArray
        assertEquals(78, casos.size)
        for (caso in casos) {
            val o = caso.jsonObject
            val c = candidato(o["candidato"]!!)
            val q = d(o["cantidad"])!!
            val m = medida(o["medida"]!!)
            val ahora = AjusteComida(agregados = listOf(AgregadosComida.agregado(c, q, m, 42))).aValor()
            assertEquals(ValorJson.desde(o["esperado"]!!), ahora, "${c.nombre} $q ${m.nombre}")
            // Y lo de iOS se lee igual.
            assertEquals(AjusteComida.desde(ahora), AjusteComida.desde(ValorJson.desde(o["esperado"]!!)))
        }
    }

    @Test
    fun losTildesSalenIgual() {
        for (caso in todo["tildes"]!!.jsonArray) {
            val o = caso.jsonObject
            val excl = o["excluidos"]!!.jsonArray.map { it.jsonPrimitive.intOrNull!! }
            val r = AgregadosComida.excluidosTrasBorrar(excl, o["n"]!!.jsonPrimitive.intOrNull!!, o["j"]!!.jsonPrimitive.intOrNull!!)
            assertEquals(o["esperado"]!!.jsonArray.map { it.jsonPrimitive.intOrNull!! }, r, "$excl")
        }
    }

    private fun alimento(e: JsonElement): Alimento {
        val o = e.jsonObject
        return Alimento(
            nombre = texto(o["name"]), qty = d(o["qty"]), unidad = (o["unit"] as? JsonPrimitive)?.content,
            kcal = d(o["kcal"]), prot = d(o["prot"]), carb = d(o["carb"]), fat = d(o["fat"]),
        )
    }

    @Test
    fun elDiaSaleIgual() {
        val casos = todo["dia"]!!.jsonArray
        assertEquals(7, casos.size)
        for (caso in casos) {
            val c = caso.jsonObject
            val nombre = texto(c["nombre"])
            val comidas = c["comidas"]!!.jsonArray.map { x ->
                val o = x.jsonObject
                AjustePorciones.ComidaDelDia(texto(o["id"]), texto(o["nombre"]), d(o["opcion"])!!.toInt(), o["alimentos"]!!.jsonArray.map(::alimento))
            }
            val ajustes = c["ajustes"]!!.jsonObject.mapValues { AjusteComida.desde(ValorJson.desde(it.value))!! }
            val dia = AjustePorciones.dia(comidas, ajustes)
            val esperado = c["esperado"]!!.jsonObject
            for (comida in comidas) {
                val e = esperado[comida.id]!!.jsonObject
                val x = dia[comida.id]!!
                fun lista(campo: String, v: List<Double?>) {
                    val ios = (e[campo] as JsonArray).map { d(it) }
                    assertTrue(ios.size == v.size && ios.indices.all { cerca(ios[it], v[it]) }, "$nombre / ${comida.id} / $campo: iOS $ios, Android $v")
                }
                lista("qty", x.alimentos.map { it.qty })
                lista("kcal", x.alimentos.map { it.kcal ?: 0.0 })
                val ag = e["agregados"]!!.jsonArray
                assertEquals(ag.size, x.agregados.size, "$nombre / ${comida.id} / agregados")
                ag.forEachIndexed { i, a ->
                    val o = a.jsonObject
                    val y = x.agregados[i]
                    assertTrue(cerca(d(o["kcal"]), y.kcal) && cerca(d(o["prot"]), y.prot) && cerca(d(o["carb"]), y.carb) && cerca(d(o["fat"]), y.fat),
                        "$nombre / ${comida.id} / agregado $i")
                }
                for ((campo, v) in listOf("kcalPlan" to x.kcalPlan, "kcalDia" to x.kcal, "compensacion" to x.compensacion,
                    "noAbsorbido" to x.noAbsorbido, "propio" to x.propio)) {
                    assertTrue(cerca(d(e[campo]), v), "$nombre / ${comida.id} / $campo: iOS ${d(e[campo])}, Android $v")
                }
                assertEquals((e["ajustada"] as JsonPrimitive).booleanOrNull, x.ajustada, "$nombre / ${comida.id} / ajustada")
            }
            assertTrue(cerca(d(esperado["_sinCompensar"]), AjustePorciones.sinCompensar(comidas, dia)), "$nombre / _sinCompensar")
        }
    }

    @Test
    fun loConsumidoSaleIgual() {
        val casos = todo["consumo"]!!.jsonArray
        assertEquals(7, casos.size)
        for (caso in casos) {
            val c = caso.jsonObject
            val nombre = texto(c["nombre"])
            val r = ConsumoDelDia.calcular(
                c["comidas"]!!.jsonArray.map(Comida::desde),
                ConsumoDelDia.marcas(c["marcas"]!!.jsonArray.map(ComidaMarcada::desde)),
                emptyList(),
                c["ajustes"]!!.jsonObject.mapValues { AjusteComida.desde(ValorJson.desde(it.value))!! },
                c["vistas"]!!.jsonObject.mapValues { it.value.jsonPrimitive.intOrNull!! },
            )
            val e = c["esperado"]!!.jsonObject
            for ((campo, v) in listOf("kcal" to r.kcal, "prot" to r.prot, "carb" to r.carb, "fat" to r.fat)) {
                assertTrue(cerca(d(e[campo]), v), "$nombre / $campo: iOS ${d(e[campo])}, Android $v")
            }
            assertEquals(d(e["comidas"])!!.toInt(), r.comidas, "$nombre / comidas")
            assertEquals(d(e["hechas"])!!.toInt(), r.hechas, "$nombre / hechas")
            assertEquals(d(e["salteadas"])!!.toInt(), r.salteadas, "$nombre / salteadas")
        }
    }

    @Test
    fun laBusquedaEnLaBase() {
        val base = BaseAlimentos.desde(Vectores.texto(Vectores.compartido("food-db.json")))
            .conPropios(listOf(AlimentoPropio("Puré de zapallo casero", 45.0, 1.0, 9.0, 1.0, "g", null, null)))
        val zapallo = AgregadosComida.buscar(base, "Zapallo")
        assertEquals("Zapallo / Calabaza", zapallo.first().nombre)
        assertTrue(zapallo.any { it.nombre == "Puré de zapallo casero" && it.esPropio })
        assertEquals(listOf("Puré de zapallo casero"), AgregadosComida.buscar(base, "pure  ZAPALLO").map { it.nombre })
        val huevo = AgregadosComida.buscar(base, "huevo").map { it.nombre }
        assertEquals("Huevo entero", huevo.first())
        assertTrue("Clara de huevo" in huevo)
        assertEquals("Brócoli", AgregadosComida.buscar(base, "brocoli").first().nombre)
        assertTrue(AgregadosComida.buscar(base, "  ").isEmpty())
        assertEquals(5, AgregadosComida.buscar(base, "a", 5).size)
        assertEquals(AlimentoAgregado.Origen.PROPIO, AgregadosComida.Candidato(zapallo.first { it.esPropio }).origen)
    }

    // ── Lectura, escritura y topes (los mismos casos que iOS) ──

    private val zapallo = AgregadosComida.Candidato("Zapallo / Calabaza", MacrosPor100(26.0, 1.0, 6.5, 0.1), null, null, AlimentoAgregado.Origen.BASE)
    private val huevo = AgregadosComida.Candidato("Huevo entero", MacrosPor100(143.0, 12.6, 0.7, 9.5), "unidad", 60.0, AlimentoAgregado.Origen.BASE)

    @Test
    fun laLecturaToleraYSinAgregadosElJSONQuedaComoAntes() {
        assertNull(AjusteComida(deltaKcal = 50).aValor()["agregados"])
        val con = AjusteComida(agregados = listOf(AgregadosComida.agregado(huevo, 1.0, AgregadosComida.Medida("unidad", 60.0), 1_730_000_000_000)))
        assertFalse(con.neutro)
        assertEquals(con, AjusteComida.desde(ValorJson.parsear(con.aValor().serializar())))
        assertTrue(con.aValor().serializar().contains("\"_ts\":1730000000000"))
        val rota = AjusteComida.desde(ValorJson.parsear("""
            {"deltaKcal":50,"agregados":[{"nombre":"","cantidad":1},{"nombre":"Huevo","cantidad":1,"unidad":"unidad","gramosUnidad":60,
            "gramos":60,"kcal":86,"p":7.6,"c":0.4,"g":5.7,"por100":{"kcal":143,"p":12.6,"c":0.7,"g":9.5},"origen":"base","_ts":5},
            {"nombre":"X","cantidad":-1,"gramos":1,"kcal":1,"p":0,"c":0,"g":0,"por100":{"kcal":1,"p":0,"c":0,"g":0},"_ts":6},
            {"nombre":"Y","cantidad":10,"gramos":10,"kcal":1,"p":0,"c":0,"g":0,"por100":{"kcal":1,"p":0,"c":0,"g":0},"origen":"otro","_ts":7}]}
        """.trimIndent()))!!
        assertEquals(50, rota.deltaKcal)
        assertEquals(listOf("Huevo", "Y"), rota.agregados.map { it.nombre })
        assertEquals("g", rota.agregados[1].unidad)
        assertEquals(AlimentoAgregado.Origen.BASE, rota.agregados[1].origen)
        val otra = AjusteComida.desde(ValorJson.parsear("""{"deltaKcal":50,"agregados":"x"}"""))!!
        assertTrue(otra.deltaKcal == 50 && otra.agregados.isEmpty())
        // Dos con el mismo `_ts` (su identidad en las vistas y al borrar): queda el primero.
        val doble = AjusteComida(agregados = listOf(con.agregados[0], con.agregados[0].copy(nombre = "Otro")))
        assertEquals(listOf("Huevo entero"), AjusteComida.desde(ValorJson.parsear(doble.aValor().serializar()))!!.agregados.map { it.nombre })
    }

    @Test
    fun losTopes() {
        val uno = AgregadosComida.agregado(zapallo, 80.0, AgregadosComida.Medida.GRAMO, 1)
        val ocho = AjusteComida(agregados = List(8) { uno })
        assertNull(AgregadosComida.motivoNoEntra(mapOf("c1" to ocho), "c1"))
        assertNotNull(AgregadosComida.motivoNoEntra(mapOf("c1" to AjusteComida(agregados = List(9) { uno })), "c1"))
        val dia = mapOf("c1" to ocho, "c2" to ocho, "c3" to ocho)
        assertNull(AgregadosComida.motivoNoEntra(dia, "c3"))
        assertNotNull(AgregadosComida.motivoNoEntra(dia + ("c4" to AjusteComida(agregados = listOf(uno))), "c4"))
        val largo = AgregadosComida.agregado(
            AgregadosComida.Candidato("Ñandú asado con salsa ".repeat(6), MacrosPor100(200.0, 20.0, 10.0, 10.0), null, null, AlimentoAgregado.Origen.PROPIO),
            1999.0, AgregadosComida.Medida.GRAMO, 1,
        )
        assertEquals(AgregadosComida.LARGO_NOMBRE, largo.nombre.length)
        val lleno = (0 until 3).associate { i ->
            "comida-$i" to AjusteComida(
                deltaKcal = -50, cantidades = mapOf("0" to 120.0, "1" to 35.0),
                anclas = mapOf("0" to AnclaAlimento("Pechuga de pollo cocida", "g"), "1" to AnclaAlimento("Arroz integral", "g")),
                agregados = List(8) { largo },
            )
        }
        assertTrue(AgregadosComida.bytesJsonb(lleno) <= AgregadosComida.MAXIMO_BYTES_JSONB, "${AgregadosComida.bytesJsonb(lleno)}")
        // El tope deja 1000 bytes de margen con los 16000 de nativa_004.
        assertTrue(AgregadosComida.MAXIMO_BYTES_JSONB <= 15000)
        // Un día que pasa la cota no entra, aunque no llegue a los topes de cantidad (el compacto de antes lo dejaba pasar).
        val enorme = AgregadosComida.Candidato("Ñ".repeat(80), MacrosPor100(1.3, 0.1, 0.3, 0.1), "taza", 245.5, AlimentoAgregado.Origen.BASE)
        val gordo = (0 until 3).associate { i ->
            "comida-$i" to AjusteComida(
                cantidades = (0 until 30).associate { "$it" to 12.345 + it },
                anclas = (0 until 30).associate { "$it" to AnclaAlimento("x".repeat(40), "g") },
                agregados = List(8) { j -> AgregadosComida.agregado(enorme, 1.5, AgregadosComida.Medida("taza", 245.5), (i * 10 + j).toLong()) },
            )
        }
        assertTrue(AgregadosComida.bytesJsonb(gordo) > AgregadosComida.MAXIMO_BYTES_JSONB)
        assertEquals("No entran más alimentos agregados hoy.", AgregadosComida.motivoNoEntra(gordo, "comida-0"))
    }

    /** La cota del jsonb nunca da menos que lo que midió la base (y no se pasa de más del 15 %). */
    @Test
    fun laCotaDelJsonbCubreLoMedido() {
        for (caso in Vectores.json(Vectores.publico("agregados_jsonb_medido"))["casos"]!!.jsonArray) {
            val o = caso.jsonObject
            val medido = o["jsonb"]!!.jsonPrimitive.intOrNull!!
            val dia = (ValorJson.parsear(o["ajustes"].toString()) as ValorJson.Objeto).campos.mapValues { AjusteComida.desde(it.value)!! }
            val cota = AgregadosComida.bytesJsonb(dia)
            assertTrue(cota >= medido, "${texto(o["caso"])}: $cota < $medido")
            assertTrue(cota <= medido * 1.15, "${texto(o["caso"])}: $cota muy por encima de $medido")
        }
    }
}
