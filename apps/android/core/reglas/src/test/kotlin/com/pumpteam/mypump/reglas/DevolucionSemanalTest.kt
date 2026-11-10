package com.pumpteam.mypump.reglas

import com.pumpteam.mypump.modelos.ValorJson
import kotlinx.serialization.json.Json
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.nio.file.Files
import java.nio.file.Paths

/** La devolución de Mati: los mismos casos que iOS y la web (`apps/shared/fixtures/devolucion/casos.json`). */
class DevolucionSemanalTest {
    private val raiz = generateSequence(Paths.get("").toAbsolutePath()) { it.parent }
        .first { Files.isDirectory(it.resolve("apps/shared/fixtures/devolucion")) }

    private fun lineas(v: ValorJson?) = (v as? ValorJson.Lista)?.elementos?.mapNotNull { it.comoTexto } ?: emptyList()

    @Test
    fun losCasosCompartidos() {
        val casos = ValorJson.desde(Json.parseToJsonElement(Files.readString(raiz.resolve("apps/shared/fixtures/devolucion/casos.json")))) as ValorJson.Lista
        assertTrue(casos.elementos.size >= 10)
        for (c in casos.elementos) {
            val nombre = c["nombre"]?.comoTexto
            val hoy = c["hoy"]!!.comoTexto!!
            val e = EstadoDevolucion.desde(c["respuesta"] ?: ValorJson.Nulo)
            val esp = c["esperado"]
            if (esp == null || esp == ValorJson.Nulo) { assertNull(e, nombre); continue }
            assertNotNull(e, nombre)
            val u = esp["ultima"]
            if (u != null && u != ValorJson.Nulo) {
                assertEquals(u["id"]?.comoTexto, e!!.ultima?.id, nombre)
                assertEquals(u["etiqueta"]?.comoTexto, ReglasDevolucion.etiqueta(e.ultima!!.semanaLunes, hoy), nombre)
                assertEquals(lineas(u["lineas"]), e.ultima!!.lineas, nombre)
                assertEquals(u["nueva"] == ValorJson.Booleano(true), ReglasDevolucion.esNueva(e.ultima!!, hoy), nombre)
            } else {
                assertNull(e!!.ultima, nombre)
            }
            val ant = (esp["anteriores"] as ValorJson.Lista).elementos
            assertEquals(ant.map { it["id"]?.comoTexto }, e.anteriores.map { it.id }, nombre)
            assertEquals(ant.map { it["etiqueta"]?.comoTexto }, e.anteriores.map { ReglasDevolucion.etiqueta(it.semanaLunes, hoy) }, nombre)
            assertEquals(ant.map { lineas(it["lineas"]) }, e.anteriores.map { it.lineas }, nombre)
        }
    }

    @Test
    fun noMasDeDoce() {
        val l = (0 until 20).map { i ->
            ValorJson.Objeto(mapOf("id" to ValorJson.Texto("d$i"), "semana_lunes" to ValorJson.Texto("2026-%02d-01".format((i % 12) + 1)),
                "texto" to ValorJson.Texto("Bien.\nSeguí.\nAsí.")))
        }
        val e = EstadoDevolucion.desde(ValorJson.Objeto(mapOf("habilitado" to ValorJson.Booleano(true), "devoluciones" to ValorJson.Lista(l))))
        assertTrue(e!!.devoluciones.size <= EstadoDevolucion.MAXIMO)
    }
}
