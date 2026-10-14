package com.pumpteam.mypump.reglas

import com.pumpteam.mypump.modelos.Alimento
import com.pumpteam.mypump.modelos.Comida
import com.pumpteam.mypump.modelos.EstructuraDieta
import com.pumpteam.mypump.modelos.FoodSwap
import com.pumpteam.mypump.modelos.Opcion
import com.pumpteam.mypump.modelos.TipoDia
import com.pumpteam.mypump.modelos.ValorJson
import com.pumpteam.mypump.modelos.ValorJson.Numero
import com.pumpteam.mypump.modelos.ValorJson.Texto
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/** Los casos de scripts/test-swaps-anclados.mjs (el que cuida el BORRADO de swaps), como SwapsDeComidaTests.swift. */
class SwapsDeComidaTest {
    private fun food(n: String, q: Double, u: String = "g") = Alimento(nombre = n, qty = q, unidad = u, kcal = 100.0)
    private fun json(a: Alimento): ValorJson = ValorJson.objeto(
        "name" to Texto(a.nombre), "qty" to Numero(a.qty ?: 0.0), "unit" to Texto(a.unidad ?: ""), "kcal" to Numero(a.kcal ?: 0.0),
    )
    private fun dieta(vararg comidas: Pair<String, List<Alimento>>) =
        EstructuraDieta(comidas = comidas.map { Comida(id = it.first, opciones = listOf(Opcion(nombre = "A", alimentos = it.second))) })

    private val v1 = dieta("c2" to listOf(food("Café", 200.0, "ml"), food("Pan lactal", 60.0), food("Huevos", 3.0, "unidad")))
    private val v2 = dieta("c2" to listOf(food("Yogur", 200.0), food("Café", 200.0, "ml"), food("Pan lactal", 60.0), food("Huevos", 3.0, "unidad")))
    private val tipos = EstructuraDieta(
        tiposDia = listOf(
            TipoDia(id = "entreno", comidas = listOf(Comida(id = "c2", opciones = listOf(Opcion(nombre = "A",
                alimentos = listOf(food("Café", 200.0, "ml"), food("Avena", 80.0), food("Huevos", 3.0, "unidad"))))))),
            TipoDia(id = "descanso", comidas = listOf(Comida(id = "c2", opciones = listOf(Opcion(nombre = "A",
                alimentos = listOf(food("Café", 200.0, "ml"), food("Avena", 50.0), food("Huevos", 3.0, "unidad"))))))),
        ),
    )

    private fun efectivo(d: EstructuraDieta, original: Alimento, swap: SwapLocal?, comida: String = "c2", opt: Int = 0, idx: Int): String =
        SwapsDeComida.efectivo(original, swap, comida) { SwapsDeComida.enPosicion(d, null, comida, opt, idx) }.alimento.nombre

    private fun fila(comida: String, opt: Int, idx: Int, data: ValorJson): FoodSwap =
        FoodSwap.desde(ValorJson.objeto("comida_id" to Texto(comida), "opt_idx" to Numero(opt.toDouble()),
            "food_idx" to Numero(idx.toDouble()), "food_data" to data).aJson())

    private fun hidratar(
        d: EstructuraDieta,
        remotos: List<FoodSwap>?,
        locales: Map<String, SwapLocal> = emptyMap(),
        pendientes: Map<String, String> = emptyMap(),
        yaMigrado: Boolean = false,
    ) = SwapsDeComida.hidratar(remotos, locales, "d1", pendientes, yaMigrado) { c, o, f -> SwapsDeComida.enPosicion(d, null, c, o, f) }

    private val anclado = SwapsDeComida.conAncla(json(food("Arroz", 80.0)), food("Pan lactal", 60.0))

    // 1. el swap se ancla al alimento que reemplaza
    @Test
    fun conAnclaGuardaNombreCantidadYUnidad() {
        assertEquals(ValorJson.objeto("name" to Texto("Pan lactal"), "qty" to Numero(60.0), "unit" to Texto("g")), anclado["_orig"])
        assertEquals("Arroz", anclado["name"]?.comoTexto)
    }

    @Test
    fun conLaDietaIgualSeAplica() = assertEquals("Arroz", efectivo(v1, food("Pan lactal", 60.0), SwapLocal(current = anclado), idx = 1))

    @Test
    fun matiAgregaUnYogurAntesYElSwapDelPanNoTapaAlCafe() =
        assertEquals("Café", efectivo(v2, food("Café", 200.0, "ml"), SwapLocal(current = anclado), idx = 1))

    @Test
    fun matiCambia60a80YElSwapNoSeAplica() {
        val v3 = dieta("c2" to listOf(food("Café", 200.0, "ml"), food("Pan lactal", 80.0)))
        assertEquals("Pan lactal", efectivo(v3, food("Pan lactal", 80.0), SwapLocal(current = anclado), idx = 1))
    }

    @Test
    fun mayusculasYEspaciosNoRompenElAncla() {
        val s = SwapLocal(current = SwapsDeComida.conAncla(json(food("Arroz", 80.0)), food("  PAN LACTAL ", 60.0, " G ")))
        assertEquals("Arroz", efectivo(v1, food("Pan lactal", 60.0), s, idx = 1))
    }

    // 2. hidratar desde el backend
    @Test
    fun legadoSinOrigSeAnclaYSeResube() {
        val r = hidratar(v1, listOf(fila("c2", 0, 1, json(food("Arroz", 80.0)))))!!
        val k = "swap_d1_c2_0_1"
        assertEquals("Pan lactal", r.swaps[k]?.current?.get("_orig")?.get("name")?.comoTexto)
        assertEquals(listOf("swap"), r.operaciones.map { it.kind })
        assertEquals(k, r.operaciones.first().clave)
    }

    @Test
    fun ancladoQueYaNoCoincideSeSacaYSeBorraEnElBackend() {
        val r = hidratar(v2, listOf(fila("c2", 0, 1, anclado)))!!   // en v2 la posición 1 es Café
        assertNull(r.swaps["swap_d1_c2_0_1"])
        assertEquals(listOf("swap_del"), r.operaciones.map { it.kind })
    }

    // La palanca remota apagada (`anclaje_borra_swaps = false`): el que no coincide se oculta, pero no se borra.
    @Test
    fun conLaPalancaApagadaElAncladoQueNoCoincideSoloSeOculta() {
        val r = SwapsDeComida.hidratar(listOf(fila("c2", 0, 1, anclado)), emptyMap(), "d1", emptyMap(), yaMigrado = false, borrarAnclados = false) { c, o, f ->
            SwapsDeComida.enPosicion(v2, null, c, o, f)
        }!!
        assertNotNull(r.swaps["swap_d1_c2_0_1"])
        assertTrue(r.operaciones.isEmpty())
        assertEquals("Café", efectivo(v2, food("Café", 200.0, "ml"), r.swaps["swap_d1_c2_0_1"], idx = 1))
    }

    @Test
    fun ancladoQueSigueCoincidiendoQuedaSinTrafico() {
        val r = hidratar(v1, listOf(fila("c2", 0, 1, anclado)))!!
        assertNotNull(r.swaps["swap_d1_c2_0_1"])
        assertTrue(r.operaciones.isEmpty())
    }

    @Test
    fun posicionQueYaNoExisteNoRompe() {
        val r = hidratar(v1, listOf(fila("c9", 0, 7, json(food("Arroz", 80.0)))))!!
        assertTrue(r.operaciones.isEmpty())
    }

    // 2b. tipos de día y cola
    @Test
    fun unSwapDeOtroAlimentoNoSeCruzaEntreTiposDeDia() {
        val cruzada = EstructuraDieta(tiposDia = listOf(
            TipoDia(id = "a", comidas = listOf(Comida(id = "c2", opciones = listOf(Opcion(nombre = "A",
                alimentos = listOf(food("Café", 200.0, "ml"), food("Avena", 80.0))))))),
            TipoDia(id = "b", comidas = listOf(Comida(id = "c2", opciones = listOf(Opcion(nombre = "A",
                alimentos = listOf(food("Café", 200.0, "ml"), food("Tostadas", 2.0, "unidad"))))))),
        ))
        val s = SwapLocal(current = SwapsDeComida.conAncla(json(food("Galletas", 30.0)), food("Tostadas", 2.0, "unidad")))
        assertEquals("Avena", efectivo(cruzada, food("Avena", 80.0), s, idx = 1))
    }

    @Test
    fun unSwapDeEntrenoSigueValiendoEnDescanso() {
        val s = SwapLocal(current = SwapsDeComida.conAncla(json(food("Pan", 60.0)), food("Avena", 80.0)))
        assertEquals("Pan", efectivo(tipos, food("Avena", 50.0), s, idx = 1))
    }

    @Test
    fun yElHydrateNoLoBorra() {
        val a = SwapsDeComida.conAncla(json(food("Pan", 60.0)), food("Avena", 80.0))
        val r = hidratar(tipos, listOf(fila("c2", 0, 1, a)))!!
        assertNotNull(r.swaps["swap_d1_c2_0_1"])
        assertFalse(r.operaciones.any { it.kind == "swap_del" })
    }

    @Test
    fun elAnclaValeContraCualquierTipoDeDia() {
        val a = SwapsDeComida.conAncla(json(food("Pan", 40.0)), food("Avena", 50.0))
        val r = hidratar(tipos, listOf(fila("c2", 0, 1, a)))!!
        assertNotNull(r.swaps["swap_d1_c2_0_1"])
        assertFalse(r.operaciones.any { it.kind == "swap_del" })
        assertEquals("Pan", efectivo(tipos, food("Avena", 80.0), r.swaps["swap_d1_c2_0_1"], idx = 1))
    }

    @Test
    fun conUnaOpPendienteElHydrateNoLaToca() {
        val k = "swap_d1_c2_0_1"
        val local = SwapLocal(current = SwapsDeComida.conAncla(json(food("Galletas", 30.0)), food("Café", 200.0, "ml")))
        val r = hidratar(v2, listOf(fila("c2", 0, 1, anclado)), locales = mapOf(k to local), pendientes = mapOf(k to "swap"))!!
        assertEquals(local, r.swaps[k])
        assertTrue(r.operaciones.isEmpty())
    }

    @Test
    fun unLegadoTampocoSeResubeSiHayAlgoPendiente() {
        val k = "swap_d1_c2_0_1"
        val r = hidratar(v1, listOf(fila("c2", 0, 1, json(food("Arroz", 80.0)))), pendientes = mapOf(k to "swap"))!!
        assertTrue(r.operaciones.isEmpty())
    }

    @Test
    fun unaReversionPendienteNoLaResucitaElRemoto() {
        val k = "swap_d1_c2_0_1"
        val r = hidratar(v1, listOf(fila("c2", 0, 1, anclado)), pendientes = mapOf(k to "swap_del"))!!
        assertNull(r.swaps[k])
    }

    // 3. migración y red
    @Test
    fun sinRedNoSeTocaNada() = assertNull(hidratar(v1, null, locales = mapOf("x" to SwapLocal(current = ValorJson.Nulo))))

    @Test
    fun laMigracionVaPorLaColaYNoSeMarcaHastaDrenar() {
        val k = "swap_d1_c2_0_1"
        val r = hidratar(v1, emptyList(), locales = mapOf(k to SwapLocal(current = anclado)))!!
        assertTrue(r.migrando)
        assertEquals(listOf(k), r.operaciones.map { it.clave })
        assertTrue(r.operaciones.first().comidaId == "c2" && r.operaciones.first().foodIdx == 1)
        assertFalse(r.marcarMigrado)
    }

    @Test
    fun yaMigradoYBackendVacioDescartaLoLocalSalvoLoPendiente() {
        val local = SwapLocal(current = ValorJson.objeto("name" to Texto("X")))
        val r = hidratar(v1, emptyList(), locales = mapOf("a" to local, "b" to local), pendientes = mapOf("b" to "swap"), yaMigrado = true)!!
        assertEquals(setOf("b"), r.swaps.keys)
    }

    @Test
    fun laMigracionSaltaLoQueNoEsDeEstaDieta() {
        val r = hidratar(v1, emptyList(), locales = mapOf(
            "swap_d1_c2_0_1" to SwapLocal(current = anclado),
            "swap_otra_c2_0_1" to SwapLocal(current = anclado),       // de otra dieta: no matchea
            "swap_d1_c3_0_x" to SwapLocal(current = anclado),         // índice que no es número
            "swap_d1_c1_0_0" to SwapLocal(current = ValorJson.Texto("")), // `!swap.current`: se saltea
        ))!!
        assertEquals(listOf("swap_d1_c2_0_1"), r.operaciones.map { it.clave })
    }
}
