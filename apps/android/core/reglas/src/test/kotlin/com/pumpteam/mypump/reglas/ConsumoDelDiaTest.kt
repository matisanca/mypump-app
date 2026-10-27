package com.pumpteam.mypump.reglas

import com.pumpteam.mypump.modelos.Alimento
import com.pumpteam.mypump.modelos.Comida
import com.pumpteam.mypump.modelos.ComidaLibre
import com.pumpteam.mypump.modelos.ComidaMarcada
import com.pumpteam.mypump.modelos.Opcion
import com.pumpteam.mypump.modelos.ValorJson
import java.nio.file.Path
import kotlin.math.abs
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * «Consumido hoy» (DIE-05..07, D25): lo mismo que `calcularConsumido` de la web (vectores de vectores-consumo.mjs) y, con
 * los ajustes del día, lo mismo que iOS (`consumo_dia_ajustes.json`, de ConsumoDelDiaTests).
 */
class ConsumoDelDiaTest {
    private fun cerca(a: Double, b: Double) = abs(a - b) < 1e-9

    private fun fallasWeb(p: Path): Pair<Int, List<String>> {
        val casos = Vectores.json(p)["casos"]!!.jsonArray
        val fallas = mutableListOf<String>()
        for (caso in casos) {
            val c = caso.jsonObject
            val e = c["entrada"]!!.jsonObject
            val comidas = e["comidas"]!!.jsonArray.map(Comida::desde)
            val marcas = ConsumoDelDia.marcas(e["marcas"]!!.jsonArray.map(ComidaMarcada::desde))
            val libres = e["libres"]!!.jsonArray.map(ComidaLibre::desde)
            val swaps = (e["swaps"] as? JsonObject)?.mapValues { Alimento.desde(it.value) }.orEmpty()
            val r = ConsumoDelDia.calcular(comidas, marcas, libres) { cid, o, i, a -> swaps["$cid|$o|$i"] ?: a }
            val s = c["salida"]!!.jsonObject
            fun n(k: String) = s[k]!!.jsonPrimitive.doubleOrNull!!
            val iguales = cerca(r.kcal, n("kcal")) && cerca(r.prot, n("prot")) && cerca(r.carb, n("carb")) && cerca(r.fat, n("fat")) &&
                r.comidas == n("nComidas").toInt() && r.hechas == n("nComidasMarcadas").toInt()
            if (!iguales) fallas += "${c["nombre"]!!.jsonPrimitive.content}: $r ≠ $s"
        }
        return casos.size to fallas
    }

    @Test
    fun vectoresDeLaWeb() {
        val (n, f) = fallasWeb(Vectores.publico("consumo_dia"))
        assertTrue(n >= 20, "$n casos")
        assertTrue(f.isEmpty(), f.take(3).joinToString("\n"))
    }

    @Test
    fun dietasReales() {
        val (n, f) = fallasWeb(Vectores.privado("consumo_dia"))
        assertTrue(n >= 270, "$n casos")
        assertTrue(f.isEmpty(), "${f.size} de $n: ${f.take(2)}")
    }

    @Test
    fun losVectoresDeIosConAjustesSalenIgual() {
        val casos = Vectores.json(Vectores.publico("consumo_dia_ajustes"))["casos"]!!.jsonArray
        assertEquals(10, casos.size, "cambió la cantidad de casos: regenerar en iOS y revisar acá")
        for (caso in casos) {
            val c = caso.jsonObject
            val nombre = c["nombre"]!!.jsonPrimitive.content
            val r = ConsumoDelDia.calcular(
                c["comidas"]!!.jsonArray.map(Comida::desde),
                ConsumoDelDia.marcas(c["marcas"]!!.jsonArray.map(ComidaMarcada::desde)),
                c["libres"]!!.jsonArray.map(ComidaLibre::desde),
                c["ajustes"]!!.jsonObject.mapValues { AjusteComida.desde(ValorJson.desde(it.value))!! },
                c["vistas"]!!.jsonObject.mapValues { it.value.jsonPrimitive.intOrNull!! },
            )
            val e = c["esperado"]!!.jsonObject
            fun n(k: String) = (e[k] as JsonPrimitive).doubleOrNull!!
            for ((campo, v) in listOf("kcal" to r.kcal, "prot" to r.prot, "carb" to r.carb, "fat" to r.fat)) {
                assertTrue(cerca(n(campo), v), "$nombre / $campo: iOS ${n(campo)}, Android $v")
            }
            assertEquals(n("comidas").toInt(), r.comidas, "$nombre / comidas")
            assertEquals(n("hechas").toInt(), r.hechas, "$nombre / hechas")
            assertEquals(n("salteadas").toInt(), r.salteadas, "$nombre / salteadas")
        }
    }

    private fun comida(vararg nombres: String?) = Comida("c1", "Desayuno", nombres.map { Opcion(it, emptyList()) })

    @Test
    fun laOpcionSeGuardaPorNombreOLetra() {
        val c = comida("A", "B", "C")
        assertEquals("B", ConsumoDelDia.nombreOpcion(c, 1))
        assertEquals(2, ConsumoDelDia.indiceOpcion(c, "C"))
        // Una opción que ya no existe (Mati volvió a publicar) o sin nombre guardado: la A, como la web.
        assertEquals(0, ConsumoDelDia.indiceOpcion(c, "D"))
        assertEquals(0, ConsumoDelDia.indiceOpcion(c, null))
        assertEquals(0, ConsumoDelDia.indiceOpcion(c, ""))
        // Sin nombres: la letra de la que se ve; la «A» que guarda la web es la primera.
        val sin = comida(null, null, "")
        assertEquals("A", ConsumoDelDia.nombreOpcion(sin, 0))
        assertEquals("C", ConsumoDelDia.nombreOpcion(sin, 2))
        assertEquals(1, ConsumoDelDia.indiceOpcion(sin, "B"))
        assertEquals(2, ConsumoDelDia.indiceOpcion(sin, "C"))
        assertEquals(0, ConsumoDelDia.indiceOpcion(sin, "A"))
        // Nombres repetidos (A, A, B, C): la primera con ese nombre, como la web.
        val rep = comida("A", "A", "B", "C")
        assertEquals("A", ConsumoDelDia.nombreOpcion(rep, 1))
        assertEquals(0, ConsumoDelDia.indiceOpcion(rep, "A"))
        assertEquals(2, ConsumoDelDia.indiceOpcion(rep, "B"))
    }

    @Test
    fun laMarcaDesdeLaFilaYDesdeElTelefono() {
        val filas = Json.parseToJsonElement(
            """[{"comida_id":"c1","opcion_elegida":"B","estado":"comido","foods_excluidos":[3,1,3]},
               {"comida_id":"c2","opcion_elegida":"A","estado":"saltado","foods_excluidos":null},
               {"comida_id":"c3","opcion_elegida":"A","estado":"otro"},
               {"comida_id":"c4","opcion_elegida":"A","estado":"comido"},
               {"comida_id":"c4","opcion_elegida":"C","estado":"saltado"}]""",
        ).jsonArray.map(ComidaMarcada::desde)
        val m = ConsumoDelDia.marcas(filas)
        assertEquals(MarcaComida("B", MarcaComida.Estado.COMIDO, listOf(1, 3)), m["c1"])
        assertEquals(MarcaComida("A", MarcaComida.Estado.SALTADO), m["c2"])
        assertNull(m["c3"])
        assertEquals(MarcaComida("C", MarcaComida.Estado.SALTADO), m["c4"])
        val c = comida("A", "B")
        assertEquals(1, ConsumoDelDia.opcionDeLaMarca(c, m["c1"]))
        assertNull(ConsumoDelDia.opcionDeLaMarca(c, m["c2"]))
        // En disco va igual que se lee (y una lista rota no tira la marca), con el JSON de iOS.
        assertEquals(m["c1"], MarcaComida.desde(m["c1"]!!.aValor()))
        val rota = MarcaComida.desde(ValorJson.desde(Json.parseToJsonElement("""{"opcion":"A","estado":"comido","excluidos":"x"}""")))
        assertEquals(MarcaComida("A", MarcaComida.Estado.COMIDO), rota)
        assertNull(MarcaComida.desde(ValorJson.desde(Json.parseToJsonElement("""{"opcion":"A","estado":"nada"}"""))))
    }
}
