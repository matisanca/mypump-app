package com.pumpteam.mypump.reglas

import com.pumpteam.mypump.modelos.Alimento
import com.pumpteam.mypump.modelos.ValorJson
import kotlin.math.abs
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * Ajustar porciones (feedback del 20-oct): los vectores que grabó iOS (`AjustePorcionesTests`) tienen que salir igual
 * acá, número por número, y lo de las ayudas de la hoja (anclas, topes, destino, efecto) se comporta igual.
 */
class AjustePorcionesTest {
    private val avena = Alimento("Avena", qty = 100.0, unidad = "g", kcal = 380.0, prot = 13.0, carb = 67.0, fat = 7.0)
    private val huevos = Alimento("Huevos", qty = 3.0, unidad = "u", kcal = 234.0, prot = 18.0, carb = 0.0, fat = 18.0)
    private val banana = Alimento("Banana", qty = 1.0, unidad = "u", kcal = 105.0, prot = 1.0, carb = 27.0, fat = 0.0)
    private val pollo = Alimento("Pollo", qty = 200.0, unidad = "g", kcal = 330.0, prot = 62.0, carb = 0.0, fat = 7.0)
    private val arroz = Alimento("Arroz", qty = 150.0, unidad = "g", kcal = 195.0, prot = 4.0, carb = 42.0, fat = 0.5)
    private val tostadas = Alimento("Tostadas", qty = 2.0, unidad = "rebanada", kcal = 140.0, prot = 5.0, carb = 26.0, fat = 2.0)
    private val cafe = Alimento("Café", kcal = 0.0, prot = 0.0, carb = 0.0, fat = 0.0)
    private val aceite = Alimento("Aceite de oliva", qty = 10.0, unidad = "g", kcal = 88.0, prot = 0.0, carb = 0.0, fat = 10.0)

    private val desayuno = AjustePorciones.ComidaDelDia("desayuno", "Desayuno", 0, listOf(avena, huevos, banana))
    private val pre = AjustePorciones.ComidaDelDia("pre", "Pre-entreno", 0, listOf(banana, tostadas))
    private val almuerzo = AjustePorciones.ComidaDelDia("almuerzo", "Almuerzo", 0, listOf(pollo, arroz, aceite))
    private val merienda = AjustePorciones.ComidaDelDia("merienda", "Merienda", 0, listOf(cafe))

    // ── Los vectores de iOS ──

    private fun alimento(e: JsonElement): Alimento {
        val o = e.jsonObject
        fun d(k: String) = (o[k] as? JsonPrimitive)?.doubleOrNull
        return Alimento(
            nombre = o["name"]!!.jsonPrimitive.content, qty = d("qty"), unidad = (o["unit"] as? JsonPrimitive)?.content,
            kcal = d("kcal"), prot = d("prot"), carb = d("carb"), fat = d("fat"),
        )
    }

    private fun numeros(e: JsonElement?): List<Double?> = (e as JsonArray).map { (it as? JsonPrimitive)?.doubleOrNull }

    /** Igualdad de números como la de Swift (0 y -0 son lo mismo). */
    private fun igual(a: Double?, b: Double?): Boolean = if (a == null || b == null) a == b else a == b || (a == 0.0 && b == 0.0)

    @Test
    fun losVectoresDeIosSalenIgual() {
        val todo = Vectores.json(Vectores.publico("ajuste_porciones"))
        val casos = todo["casos"]!!.jsonArray
        assertEquals(23, casos.size, "cambió la cantidad de casos: regenerar en iOS y revisar acá")
        for (caso in casos) {
            val c = caso.jsonObject
            val nombre = c["nombre"]!!.jsonPrimitive.content
            val comidas = c["comidas"]!!.jsonArray.map { x ->
                val o = x.jsonObject
                AjustePorciones.ComidaDelDia(
                    id = o["id"]!!.jsonPrimitive.content, nombre = o["nombre"]!!.jsonPrimitive.content,
                    opcion = o["opcion"]!!.jsonPrimitive.content.toDouble().toInt(), alimentos = o["alimentos"]!!.jsonArray.map(::alimento),
                )
            }
            val ajustes = c["ajustes"]!!.jsonObject.mapValues { AjusteComida.desde(ValorJson.desde(it.value))!! }
            val d = AjustePorciones.dia(comidas, ajustes)
            val esperado = c["esperado"]!!.jsonObject
            for (comida in comidas) {
                val e = esperado[comida.id]!!.jsonObject
                val x = d[comida.id]!!
                fun chequear(campo: String, kotlin: List<Double?>) {
                    val js = numeros(e[campo])
                    assertTrue(js.size == kotlin.size && js.indices.all { igual(js[it], kotlin[it]) }, "$nombre / ${comida.id} / $campo: iOS $js, Android $kotlin")
                }
                chequear("qty", x.alimentos.map { it.qty })
                chequear("kcal", x.alimentos.map { it.kcal ?: 0.0 })
                chequear("prot", x.alimentos.map { it.prot ?: 0.0 })
                chequear("carb", x.alimentos.map { it.carb ?: 0.0 })
                chequear("fat", x.alimentos.map { it.fat ?: 0.0 })
                fun numero(campo: String) = (e[campo] as JsonPrimitive).doubleOrNull
                for ((campo, v) in listOf("kcalPlan" to x.kcalPlan, "kcalDia" to x.kcal, "compensacion" to x.compensacion,
                    "noAbsorbido" to x.noAbsorbido, "propio" to x.propio, "deltaPropio" to x.deltaPropio.toDouble())) {
                    assertTrue(igual(numero(campo), v), "$nombre / ${comida.id} / $campo: iOS ${numero(campo)}, Android $v")
                }
                assertEquals((e["omitida"] as JsonPrimitive).booleanOrNull, x.omitida, "$nombre / ${comida.id} / omitida")
                assertEquals(e["compensaDe"]!!.jsonArray.map { it.jsonPrimitive.content }, x.compensaDe, "$nombre / ${comida.id} / compensaDe")
                assertEquals(numeros(e["cambiados"]).map { it!!.toInt() }, x.cambiados.sorted(), "$nombre / ${comida.id} / cambiados")
            }
            val sin = (esperado["_sinCompensar"] as JsonPrimitive).doubleOrNull
            assertTrue(igual(sin, AjustePorciones.sinCompensar(comidas, d)), "$nombre / _sinCompensar")
        }
    }

    // ── Las ayudas de la hoja (los mismos casos que iOS) ──

    @Test
    fun redondeaAPorcionesServibles() {
        assertEquals(115.0, AjustePorciones.redondear(113.0, "g"))
        assertEquals(12.0, AjustePorciones.redondear(12.4, "g"))
        assertEquals(3.5, AjustePorciones.redondear(3.3, "u"))
        assertEquals(0.5, AjustePorciones.redondear(0.1, "u"))
        assertEquals(0.0, AjustePorciones.redondear(Double.NaN, "g"))
        assertEquals(10.0, AjustePorciones.pasoCantidad(avena))
        assertEquals(0.5, AjustePorciones.pasoCantidad(huevos))
    }

    @Test
    fun restarNuncaAgrandaUnAlimentoYSumarNuncaAchica() {
        val plan = listOf(avena, huevos, banana, aceite)
        for (paso in 1..10) {
            val menos = AjustePorciones.escalar(plan, -50.0 * paso)
            assertTrue(menos.zip(plan).all { (a, b) -> (a.qty ?: 0.0) <= (b.qty ?: 0.0) }, "−${50 * paso}")
        }
        for (paso in 1..12) {
            val mas = AjustePorciones.escalar(plan, 50.0 * paso)
            assertTrue(mas.zip(plan).all { (a, b) -> (a.qty ?: 0.0) >= (b.qty ?: 0.0) }, "+${50 * paso}")
            assertTrue(abs(AjustePorciones.kcal(mas) - AjustePorciones.kcal(plan) - 50 * paso) <= 25, "+${50 * paso}")
        }
    }

    @Test
    fun loQueNoEntraPorElTopeSigueALaOtra() {
        val d = AjustePorciones.dia(listOf(desayuno, almuerzo, pre), mapOf("desayuno" to AjusteComida(deltaKcal = 600)))
        val alm = d.getValue("almuerzo")
        assertEquals(-d.getValue("desayuno").propio, alm.compensacion)
        assertEquals(jsRound(alm.compensacion + 613 * 0.75), alm.noAbsorbido)
        assertEquals(alm.noAbsorbido, d.getValue("pre").compensacion)
        assertEquals(listOf("Desayuno"), d.getValue("pre").compensaDe)
    }

    @Test
    fun propioEsLoQueHizoElCliente() {
        val d = AjustePorciones.dia(
            listOf(desayuno, pre, almuerzo),
            mapOf("desayuno" to AjusteComida(deltaKcal = 200), "pre" to AjusteComida(omitida = true)),
        )
        assertTrue(abs(d.getValue("desayuno").propio - 200) <= 25)
        assertEquals(-245.0, d.getValue("pre").propio)
        assertEquals(0.0, d.getValue("almuerzo").propio)
        assertEquals(0.0, d.getValue("pre").absorbido)
    }

    @Test
    fun lasCantidadesSeAnclanAlAlimento() {
        val a = AjustePorciones.anclar(AjusteComida(deltaKcal = 50, cantidades = mapOf("0" to 60.0, "7" to 10.0)), desayuno)
        assertEquals(mapOf("0" to 60.0), a.cantidades)
        assertEquals(mapOf("0" to AnclaAlimento("Avena", "g")), a.anclas)
        val otra = AjustePorciones.ComidaDelDia("desayuno", "Desayuno", 0, listOf(aceite, huevos, banana))
        assertTrue(AjustePorciones.cantidadesValidas(otra, a).isEmpty())
        val b = AjustePorciones.anclar(a, otra)
        assertTrue(b.cantidades.isEmpty() && b.anclas.isEmpty() && b.deltaKcal == 50)
        assertTrue(AjustePorciones.anclar(AjusteComida(opcion = 1, cantidades = mapOf("0" to 60.0)), desayuno).neutro)
        assertTrue(AnclaAlimento("Avena", "gramos").coincide(avena))
        assertFalse(AnclaAlimento("Avena", "taza").coincide(avena))
    }

    @Test
    fun laBaseNoCuentaLoPuestoAMano() {
        assertEquals(719.0, AjustePorciones.baseEscalable(desayuno, null))
        assertEquals(339.0, AjustePorciones.baseEscalable(desayuno, AjusteComida(cantidades = mapOf("0" to 60.0))))
        assertEquals(0.0, AjustePorciones.baseEscalable(merienda, null))
    }

    @Test
    fun elDestinoSaltaLaQueNoSeComeYLaQueNoEscala() {
        val comidas = listOf(desayuno, pre, merienda, almuerzo)
        assertEquals("almuerzo", AjustePorciones.destino(comidas, mapOf("pre" to AjusteComida(omitida = true)), "desayuno")?.id)
        assertEquals("pre", AjustePorciones.destino(comidas, emptyMap(), "desayuno")?.id)
        assertNull(AjustePorciones.destino(comidas, emptyMap(), "almuerzo"))
    }

    @Test
    fun elEfectoEsLoQueCambiaEnElRestoDelDia() {
        val comidas = listOf(desayuno, almuerzo, pre)
        val e = AjustePorciones.efecto(comidas, mapOf("desayuno" to AjusteComida(deltaKcal = 600)), "desayuno")
        assertEquals(listOf("almuerzo", "pre"), e.cambios.map { it.id })
        assertEquals(0.0, e.sinCompensar)
        assertTrue(e.cambios.all { it.kcal < 0 })
        assertTrue(AjustePorciones.efecto(comidas, mapOf("desayuno" to AjusteComida(deltaKcal = 600, compensar = false)), "desayuno").cambios.isEmpty())
        val ultima = AjustePorciones.efecto(listOf(desayuno, pre), mapOf("desayuno" to AjusteComida(deltaKcal = 600)), "desayuno")
        assertEquals(listOf("pre"), ultima.cambios.map { it.id })
        assertTrue(ultima.sinCompensar < -300)
    }

    @Test
    fun elRedondeoNoCruzaElPlanAlReves() {
        val queso = Alimento("Queso", qty = 36.0, unidad = "g", kcal = 130.0, prot = 9.0, carb = 1.0, fat = 10.0)
        val pasta = Alimento("Pasta", qty = 200.0, unidad = "g", kcal = 1870.0, prot = 60.0, carb = 300.0, fat = 20.0)
        val mas = AjustePorciones.escalar(listOf(queso, pasta), 50.0)
        assertTrue((mas[0].qty ?: 0.0) >= 36 && (mas[1].qty ?: 0.0) >= 200, mas.map { it.qty }.toString())
        val pollo = Alimento("Pollo", qty = 38.0, unidad = "g", kcal = 63.0, prot = 12.0, carb = 0.0, fat = 1.5)
        val arroz = Alimento("Arroz", qty = 300.0, unidad = "g", kcal = 1937.0, prot = 20.0, carb = 420.0, fat = 3.0)
        val menos = AjustePorciones.escalar(listOf(pollo, arroz), -50.0)
        assertTrue((menos[0].qty ?: 0.0) <= 38 && (menos[1].qty ?: 0.0) <= 300, menos.map { it.qty }.toString())
    }

    @Test
    fun lasKcalSeAcotanALoQueLaComidaAbsorbe() {
        val c = AjustePorciones.ComidaDelDia("d", "Desayuno", 0, listOf(avena, banana))
        assertEquals(-350..950, AjustePorciones.limitesDelta(c, null))
        val aMano = AjusteComida(deltaKcal = 500, cantidades = mapOf("0" to 100.0))
        assertEquals(-50..200, AjustePorciones.limitesDelta(c, aMano))
        assertEquals(200, AjustePorciones.anclar(aMano, c).deltaKcal)
        assertEquals(0..0, AjustePorciones.limitesDelta(merienda, null))
        assertTrue(AjustePorciones.anclar(AjusteComida(deltaKcal = 100), merienda).neutro)
    }

    @Test
    fun neutroYLecturaTolerante() {
        assertTrue(AjusteComida().neutro)
        assertFalse(AjusteComida(deltaKcal = 50).neutro || AjusteComida(omitida = true).neutro || AjusteComida(cantidades = mapOf("0" to 10.0)).neutro)
        val viejo = AjusteComida.desde(ValorJson.parsear("""{"deltaKcal":100,"cantidades":{"0":-5,"1":30}}"""))!!
        assertEquals(AjusteComida(deltaKcal = 100, cantidades = mapOf("1" to 30.0)), viejo)
        val conAnclas = AjusteComida.desde(ValorJson.parsear("""{"cantidades":{"1":30},"anclas":{"1":{"nombre":"Huevos","unidad":"u"}}}"""))!!
        assertEquals(mapOf("1" to AnclaAlimento("Huevos", "u")), conAnclas.anclas)
        // Topes: lo que no entra vale por defecto (igual en iOS).
        val rota = AjusteComida.desde(ValorJson.parsear("""{"deltaKcal":5000000000,"opcion":-2}"""))!!
        assertTrue(rota.deltaKcal == 0 && rota.opcion == 0)
        val otra = AjusteComida.desde(ValorJson.parsear("""{"deltaKcal":-30000,"opcion":99}"""))!!
        assertTrue(otra.deltaKcal == -30000 && otra.opcion == 99)
        // Ida y vuelta por JSON (lo que va al disco y al servidor).
        val a = AjusteComida(deltaKcal = -150, compensar = false, opcion = 2, cantidades = mapOf("0" to 60.0), anclas = mapOf("0" to AnclaAlimento("Avena", null)))
        assertEquals(a, AjusteComida.desde(ValorJson.parsear(a.aValor().serializar())))
        assertNull(AjusteComida.desde(JsonNull.let { ValorJson.desde(it) }))
        assertNull(AjusteComida.desde(ValorJson.desde(JsonObject(emptyMap())))?.takeIf { !it.neutro })
    }
}
