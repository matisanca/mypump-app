package com.pumpteam.mypump.reglas

import com.pumpteam.mypump.modelos.Comida
import com.pumpteam.mypump.modelos.EstructuraDieta
import com.pumpteam.mypump.modelos.Macros
import com.pumpteam.mypump.modelos.ValorJson
import java.nio.file.Path
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/** Gemelo de NormalizarDietaTests.swift: las mismas comidas, opciones y objetivo que la web, con sus vectores. */
class NormalizarDietaTest {
    private fun resumen(r: NormalizarDieta.Resultado): ValorJson {
        val e = r.estructura
        fun plan(m: Macros?, comidas: List<Comida>): ValorJson = ValorJson.objeto(
            "macros" to (m?.let { listOf(it.kcal, it.prot, it.carb, it.fat).map { x -> x?.let(ValorJson::Numero) ?: ValorJson.Nulo } }
                ?.let(ValorJson::Lista) ?: ValorJson.Nulo),
            "comidas" to ValorJson.Lista(
                comidas.map { c ->
                    ValorJson.objeto(
                        "id" to (if (c.id.isEmpty()) ValorJson.Nulo else ValorJson.Texto(c.id)),
                        "opciones" to ValorJson.Lista(
                            c.opciones.map { o ->
                                ValorJson.objeto(
                                    "nombre" to (o.nombre?.let(ValorJson::Texto) ?: ValorJson.Nulo),
                                    "alimentos" to ValorJson.Lista(o.alimentos.map { ValorJson.Texto(it.nombre) }),
                                )
                            },
                        ),
                    )
                },
            ),
        )
        val planes = if (e.tiposDia.isEmpty()) listOf(plan(e.macrosTarget, e.comidas)) else e.tiposDia.map { plan(it.macrosTarget, it.comidas) }
        return ValorJson.objeto(
            "usable" to ValorJson.Booleano(r.usable),
            "problemas" to ValorJson.Lista(r.problemas.map(ValorJson::Texto)),
            "planes" to ValorJson.Lista(planes),
        )
    }

    private fun fallas(p: Path): Pair<Int, List<String>> {
        val casos = Vectores.json(p)["casos"]!!.jsonArray
        val fallas = mutableListOf<String>()
        casos.forEachIndexed { i, c ->
            val mio = resumen(NormalizarDieta.normalizar(EstructuraDieta.desde(c.jsonObject["entrada"]!!)))
            val esperado = ValorJson.desde(c.jsonObject["salida"]!!)
            if (mio != esperado) fallas += "caso $i: ${mio.serializar()} ≠ ${esperado.serializar()}"
        }
        return casos.size to fallas
    }

    @Test
    fun vectoresPublicos() {
        val (n, f) = fallas(Vectores.publico("normalizar_dieta"))
        assertTrue(n >= 11)
        assertTrue(f.isEmpty(), f.take(3).joinToString("\n"))
    }

    @Test
    fun dietasReales() {
        val (n, f) = fallas(Vectores.privado("normalizar_dieta"))
        assertTrue(n >= 90)
        assertTrue(f.isEmpty(), "${f.size} de $n: ${f.take(2)}")
    }
}

/** Gemelo de ToFixedTests (RevisionTests.swift): `toFixed` exacto como JS, con los casos que encontró la revisión. */
class ToFixedTest {
    @Test
    fun casosDeLaRevisionYBordes() {
        assertEquals("60.0", toFixed((60.0 + 60.1) / 2, 1))
        assertEquals("1.1", toFixed(1150.0 / 1000, 1))
        assertEquals("-9.9", toFixed(-9950.0 / 1000, 1))
        assertEquals("1.3", toFixed(1.25, 1))       // empate exacto: el mayor
        assertEquals("0.1", toFixed(0.15, 1))       // 0,1499…
        assertEquals("-0.0", toFixed(-0.04, 1))
        assertEquals("10.0", toFixed(9.96, 1))
        assertEquals("100.0", toFixed(99.95, 1))    // 99,9500000000000028…
        assertEquals("0.0", toFixed(0.0, 1))
        assertEquals("13.2", toFixed(13.207547169811321, 1))
        assertEquals("+1,1 kg", PesoCorporal.textoDelta(1150))
    }
}
