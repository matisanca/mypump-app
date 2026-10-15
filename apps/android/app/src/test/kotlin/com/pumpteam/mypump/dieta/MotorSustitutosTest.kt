package com.pumpteam.mypump.dieta

import com.pumpteam.mypump.modelos.Alimento
import com.pumpteam.mypump.modelos.AlimentoPropio
import com.pumpteam.mypump.modelos.DietaActiva
import com.pumpteam.mypump.reglas.AlimentoBase
import com.pumpteam.mypump.reglas.BaseAlimentos
import com.pumpteam.mypump.reglas.Sustituto
import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.Paths
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonArray
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * El puente de la hoja "Reemplazar" (DIE-10, gemelo de `MotorSustitutos` de iOS) con la base que empaqueta la app
 * (`apps/shared/food-db.json`) y la dieta grabada de la cuenta de prueba (`fixtures/test-nativa-real`).
 */
class MotorSustitutosTest {
    private val raiz: Path = generateSequence(Paths.get("").toAbsolutePath()) { it.parent }
        .first { Files.isDirectory(it.resolve("apps/shared/fixtures")) }

    private fun compartido(r: String) = raiz.resolve("apps/shared").resolve(r).toFile().readText()

    private val base: BaseAlimentos by lazy { MotorSustitutos.leer(compartido("food-db.json"))!! }

    private val dieta: DietaActiva by lazy {
        DietaActiva.desde(Json.parseToJsonElement(compartido("fixtures/test-nativa-real/get_dieta_activa.json")).jsonArray[0])
    }

    private fun delPlan(comida: String, opcion: Int, i: Int): Alimento =
        dieta.estructura.comidas.first { it.id == comida }.opciones[opcion].alimentos[i]

    @Test
    fun huevoEnteroDaLasMismas55OpcionesQueLaWeb() {
        // Lo mismo que se comparó lado a lado con la web local de origin/main (NATIVA_ESTADO, 14-oct).
        val huevo = delPlan("c1", 0, 0)
        assertEquals("Huevo entero", huevo.nombre)
        val r = MotorSustitutos.buscar(huevo, base, emptyList(), emptyList())
        assertEquals(55, r.opciones.size)
        assertEquals("proteina", r.categoria)
        assertEquals("proteínas", MotorSustitutos.nombreCategoria(r.categoria))
        assertEquals(emptyList<String>(), r.avisos)
        // Los 🌍 universales primero (la hoja los pone en su sección, arriba), con el nombre en inglés.
        assertEquals(25, r.opciones.count { it.universal })
        assertTrue(r.opciones.take(25).all { it.universal })
        val primero = r.opciones.first()
        assertEquals(listOf("Muslo de pollo con piel", "Chicken thigh"), listOf(primero.nombre, primero.nombreIngles))
        assertEquals(Triple(90.0, "g", 173.0), Triple(primero.qty, primero.unidad, primero.kcal))
        assertEquals(1L, MotorSustitutos.deltaKcal(huevo, primero))   // 173 contra 172: +0,58 % → +1 %
    }

    @Test
    fun lasExclusionesDelClienteSacanLoQueNoCome() {
        // Lo que la cuenta tiene en `mypump_cliente_prefs.excluir`: sin cerdo ni lácteos (y los mariscos no estaban).
        val huevo = delPlan("c1", 0, 0)
        val todas = MotorSustitutos.buscar(huevo, base, emptyList(), emptyList()).opciones.map { it.nombre }
        val r = MotorSustitutos.buscar(huevo, base, emptyList(), listOf("cerdo", "mariscos", "lacteos"))
        assertEquals(51, r.opciones.size)
        val sacadas = todas - r.opciones.map { it.nombre }.toSet()
        assertTrue("Ricota magra" in sacadas)
        assertTrue(listOf("Bondiola de cerdo", "Jamón cocido", "Salame", "Chorizo fresco").all { it in sacadas })
        // Quedan opciones de la base: el modal no avisa.
        assertEquals(emptyList<String>(), r.avisos)
    }

    @Test
    fun laBusquedaFiltraSinCambiarElOrden() {
        val r = MotorSustitutos.buscar(delPlan("c1", 0, 0), base, emptyList(), emptyList())
        val pollo = MotorSustitutos.filtrar(r.opciones, "POLLO ")
        assertTrue(pollo.isNotEmpty())
        assertTrue(pollo.all { "pollo" in it.nombre.lowercase() })
        assertEquals(r.opciones.filter { "pollo" in it.nombre.lowercase() }, pollo)
        assertEquals(r.opciones, MotorSustitutos.filtrar(r.opciones, ""))
        assertEquals(emptyList<Sustituto>(), MotorSustitutos.filtrar(r.opciones, "zzz"))
    }

    @Test
    fun unAlimentoPropioEntraConSuMarcaYSeGarantiza() {
        val huevo = delPlan("c1", 0, 0)
        // Por 100 g, con la categoría del alimento que se reemplazaba (lo que guarda "Crear y usar").
        val tofu = AlimentoPropio("Prueba tofu firme", 144.0, 15.8, 2.8, 8.7, "g", null, "proteina")
        val r = MotorSustitutos.buscar(huevo, base, listOf(tofu), emptyList())
        assertEquals(56, r.opciones.size)
        val propio = r.opciones.single { it.esPropio }
        assertEquals("Prueba tofu firme", propio.nombre)
        // Los garantizados (universales y propios) van antes que el resto.
        assertTrue(r.opciones.indexOf(propio) < r.opciones.indexOfFirst { !it.universal && !it.esPropio })
        // Sin la misma categoría no entra: el motor busca en la del original.
        val otro = MotorSustitutos.buscar(huevo, base, listOf(tofu.copy(categoria = "carbohidrato")), emptyList())
        assertTrue(otro.opciones.none { it.esPropio })
    }

    @Test
    fun macrosSospechososSeAvisan() {
        // 1.200 kcal en 100 g: macros por porción guardadas como por 100 g (dietas viejas).
        val roto = Alimento("Pechuga de pollo", qty = 100.0, unidad = "g", kcal = 1200.0, prot = 30.0, carb = 0.0, fat = 3.0)
        val r = MotorSustitutos.buscar(roto, base, emptyList(), emptyList())
        assertEquals(listOf("Los datos de este alimento parecen incorrectos: avisale a Mati así lo corrige."), r.avisos)
        assertEquals(emptyList<String>(), MotorSustitutos.buscar(delPlan("c2", 0, 0), base, emptyList(), emptyList()).avisos)
    }

    @Test
    fun lasRestriccionesSeAvisanSoloSiVacianLaLista() {
        val lacteos = BaseAlimentos(
            listOf(
                AlimentoBase("Leche descremada", 35.0, 3.4, 5.0, 0.1, "lacteo"),
                AlimentoBase("Yogur natural", 61.0, 3.5, 4.7, 3.3, "lacteo"),
                AlimentoBase("Queso fresco magro", 120.0, 18.0, 3.0, 4.0, "lacteo"),
            ),
        )
        val yogur = Alimento("Yogur griego descremado", qty = 320.0, unidad = "g", kcal = 189.0, prot = 32.0, carb = 11.5, fat = 1.3)
        val sinNada = MotorSustitutos.buscar(yogur, lacteos, emptyList(), listOf("lacteos"))
        assertTrue(sinNada.opciones.isEmpty())
        assertEquals(listOf("3 opciones quedaron ocultas por tus restricciones alimentarias."), sinNada.avisos)
        // Si quedan opciones de la base, el modal no avisa aunque haya escondido algunas (como la web).
        val conLaBase = MotorSustitutos.buscar(delPlan("c1", 1, 0), base, emptyList(), listOf("lacteos"))
        assertTrue(conLaBase.opciones.any { !it.universal && !it.esPropio })
        assertEquals(emptyList<String>(), conLaBase.avisos)
    }

    @Test
    fun laDiferenciaDeKcalRedondeaComoJs() {
        val original = Alimento("Arroz", qty = 100.0, unidad = "g", kcal = 200.0)
        fun s(kcal: Double) = Sustituto("x", 100.0, "g", kcal, 0.0, 0.0, 0.0, null, 0.0)
        // Math.round(-2,5) es -2 en JS (al más cercano, y los empates hacia +∞); el redondeo de iOS daría -3.
        assertEquals(-2L, MotorSustitutos.deltaKcal(original, s(195.0)))
        assertEquals(3L, MotorSustitutos.deltaKcal(original, s(205.0)))
        assertEquals(0L, MotorSustitutos.deltaKcal(original.copy(kcal = null), s(150.0)))
        assertEquals(0L, MotorSustitutos.deltaKcal(original.copy(kcal = 0.0), s(150.0)))
    }

    @Test
    fun queSeOfreceParaReemplazar() {
        assertTrue(CategoriaComida.sustituible(delPlan("c1", 0, 0)))
        // DIE-09: ni condimentos ni lo que Mati marcó `swappable: false`.
        assertFalse(CategoriaComida.sustituible(Alimento("Mostaza", qty = 10.0, unidad = "g", kcal = 7.0, prot = 0.4, carb = 0.6, fat = 0.4)))
        assertFalse(CategoriaComida.sustituible(Alimento("Sal fina", qty = 1.0, unidad = "g", kcal = 0.0)))
        assertFalse(CategoriaComida.sustituible(delPlan("c1", 0, 0).copy(sustituible = false)))
        // La categoría que trae el plan gana sobre la inferida.
        assertFalse(CategoriaComida.sustituible(delPlan("c1", 0, 0).copy(categoria = "condimento")))
        assertEquals("lacteo", CategoriaComida.inferir(delPlan("c1", 0, 0).copy(categoria = "lacteo")))
        assertEquals("proteina", CategoriaComida.inferir(delPlan("c1", 0, 0).copy(categoria = "")))
    }

    @Test
    fun laBaseEmpaquetadaSeLee() {
        assertEquals(base.alimentos.size, Json.parseToJsonElement(compartido("food-db.json")).let { (it as kotlinx.serialization.json.JsonObject)["alimentos"]!!.jsonArray.size })
        assertTrue(base.alimentos.size > 300)
        assertTrue(base.fuente!!.startsWith("public/js/food-db.js@"))
        assertNull(MotorSustitutos.leer("no es json"))
        assertNull(MotorSustitutos.leer("""{"fuente":"x","alimentos":[]}"""))
    }
}
