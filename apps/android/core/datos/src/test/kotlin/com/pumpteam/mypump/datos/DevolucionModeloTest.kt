package com.pumpteam.mypump.datos

import com.pumpteam.mypump.modelos.ValorJson
import java.io.File
import java.nio.file.Files
import kotlinx.coroutines.runBlocking
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/** La tarjeta «Devolución de Mati»: qué trae, qué guarda y cuándo no muestra nada. Gemelo de DevolucionModeloTests.swift. */
class DevolucionModeloTest {
    private val token = "tk-prueba-devolucion"
    private fun raiz() = Files.createTempDirectory("devolucion").toFile()
    private fun armar(d: DobleDevolucion, r: File = raiz()) = ModeloDevolucion(ClienteRpc(transporte = d), token, Disco(r, token))

    @Test fun traeLaUltimaYElHistorial(): Unit = runBlocking {
        val m = armar(DobleDevolucion.escenario("dos"))
        m.refrescar()
        assertEquals("d1", m.ultima?.id)
        assertEquals(4, m.ultima?.lineas?.size)
        assertEquals(listOf("d2", "d3"), m.anteriores.map { it.id })
    }

    @Test fun sinNadaPublicadoNoHayTarjeta(): Unit = runBlocking {
        val m = armar(DobleDevolucion.escenario("vacio"))
        m.refrescar()
        assertNotNull(m.estado.value)
        assertNull(m.ultima)
        assertTrue(m.anteriores.isEmpty())
    }

    @Test fun apagadaSinHabilitarSinServidorOTokenCaidoNoSeVeNada(): Unit = runBlocking {
        for (caso in listOf("apagado", "noHabilitado", "sinServidor")) {
            val m = armar(DobleDevolucion.escenario(caso))
            m.refrescar()
            assertNull(m.estado.value, caso)
        }
        val d = DobleDevolucion.escenario("dos").apply { tokenCaido = true }
        val m = armar(d)
        m.refrescar()
        assertNull(m.estado.value)
    }

    @Test fun sinRedMuestraLoUltimoGuardado(): Unit = runBlocking {
        val r = raiz()
        val d = DobleDevolucion.escenario("dos")
        armar(d, r).refrescar()
        d.sinRed = true
        val m = armar(d, r)
        m.refrescar()
        assertEquals("d1", m.ultima?.id)
        m.apagar()
        val m2 = armar(d, r)
        m2.refrescar()
        assertNull(m2.estado.value)
    }

    @Test fun dejaDeEstarHabilitadoBorraLoGuardado(): Unit = runBlocking {
        val r = raiz()
        val d = DobleDevolucion.escenario("dos")
        val m = armar(d, r)
        m.refrescar()
        d.habilitado = false
        m.refrescar()
        assertNull(m.estado.value)
        d.sinRed = true
        val m2 = armar(d, r)
        m2.refrescar()
        assertNull(m2.estado.value)
    }

    @Test fun laPalancaSeLeeYSinLaClaveEstaApagada() {
        assertTrue(PalancaRemota.desde(ValorJson.objeto("devolucion_semanal" to ValorJson.Booleano(true))).devolucionSemanal)
        assertFalse(PalancaRemota.desde(ValorJson.objeto()).devolucionSemanal)
        assertFalse(PalancaRemota.desde(ValorJson.objeto("devolucion_semanal" to ValorJson.Texto("true"))).devolucionSemanal)
        assertFalse(PalancaRemota.deFabrica.devolucionSemanal)
    }

    @Test fun laPalancaSeRecuerdaPorCuenta() {
        val m = armar(DobleDevolucion.escenario("dos"))
        assertFalse(m.palancaRecordada)
        m.recordarPalanca(true)
        assertTrue(m.palancaRecordada)
        m.recordarPalanca(false)
        assertFalse(m.palancaRecordada)
    }
}
