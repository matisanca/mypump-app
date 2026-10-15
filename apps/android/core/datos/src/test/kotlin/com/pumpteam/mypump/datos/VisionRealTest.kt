package com.pumpteam.mypump.datos

import com.pumpteam.mypump.modelos.EstimacionPlato
import com.pumpteam.mypump.modelos.LecturaEtiqueta
import com.pumpteam.mypump.reglas.ComidaLibreNueva
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test

/**
 * DIE-14/15 con la IA de verdad: las respuestas de mini-vision del 15-oct, recién arreglado (Codex con gpt-5.6-sol), a una
 * foto de un plato y a una tabla nutricional, tal cual llegaron. Como VisionRealTests.swift.
 */
class VisionRealTest {
    private val plato = """{"ok":true,"data":{"descripcion":"Milanesa con puré","escala":"plato playo 26 cm, usado como única referencia","alimentos":[{"nombre":"Milanesa frita","gramos":155,"kcal":390,"prot":31,"carb":22,"fat":20},{"nombre":"Puré de papas","gramos":165,"kcal":175,"prot":3,"carb":28,"fat":6}],"kcal":565,"prot":34,"carb":50,"fat":26,"confianza":"baja"}}"""
    private val etiqueta = """{"ok":true,"data":{"nombre":"Producto alimenticio","porcion_g":30,"kcal":120,"prot":3.5,"carb":21,"fat":2.5,"confianza":"alta"}}"""

    private fun cliente(cuerpo: String) = ClienteRpc(transporte = TransporteProgramado { _, _ -> 200 to cuerpo })

    @Test
    fun elPlatoSeLeeYSusGramosReescalan() = enUnHilo {
        val r = cliente(plato).vision("AAAAAAAAAAAAAAAAAAAA", ClienteRpc.TipoVision.PLATO, byteArrayOf(0xFF.toByte(), 0xD8.toByte()))
        val e = EstimacionPlato.desde((r as Resultado.Ok).valor.aJson())
        assertEquals(listOf("Milanesa frita", "Puré de papas"), e.alimentos.map { it.nombre })
        val bases = ComidaLibreNueva.bases(e)
        assertEquals(ComidaLibreNueva.Totales(565.0, 34.0, 50.0, 26.0), ComidaLibreNueva.totales(bases, ComidaLibreNueva.gramos(bases, listOf(null, null))))
        // El cliente corrige la milanesa a la mitad: sus macros se re-escalan.
        assertEquals(370.0, ComidaLibreNueva.totales(bases, ComidaLibreNueva.gramos(bases, listOf(77.5, null))).kcal)
    }

    @Test
    fun laEtiquetaSeLee() = enUnHilo {
        val r = cliente(etiqueta).vision("AAAAAAAAAAAAAAAAAAAA", ClienteRpc.TipoVision.ETIQUETA, byteArrayOf(0xFF.toByte(), 0xD8.toByte()))
        val d = LecturaEtiqueta.desde((r as Resultado.Ok).valor.aJson())
        assertEquals(LecturaEtiqueta("Producto alimenticio", 30.0, 120.0, 3.5, 21.0, 2.5, "alta"), d)
    }
}
