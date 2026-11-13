package com.pumpteam.mypump.reglas

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/** La comida marcada plegada se tiene que poder abrir a la vista (bug del 13-nov: no podía destildar ni desmarcar). */
class PliegueComidaTest {
    private val comi = MarcaComida("A", MarcaComida.Estado.COMIDO, listOf(1))
    private val salte = MarcaComida("A", MarcaComida.Estado.SALTADO)

    @Test
    fun sinMarcaNuncaSePliega() {
        assertFalse(PliegueComida.plegada(null, false))
        assertFalse(PliegueComida.plegada(null, true))
    }

    @Test
    fun marcadaSePliegaSalvoAbierta() {
        assertTrue(PliegueComida.plegada(comi, false))
        assertFalse(PliegueComida.plegada(comi, true))
        assertTrue(PliegueComida.plegada(salte, false))
    }

    @Test
    fun elBotonDiceQueSePuedeDestildarYDesmarcar() {
        assertEquals("Destildar lo que no comiste o desmarcar", PliegueComida.rotuloAbrir(MarcaComida.Estado.COMIDO))
        assertEquals("Ver la comida o desmarcar", PliegueComida.rotuloAbrir(MarcaComida.Estado.SALTADO))
    }

    @Test
    fun fueraDeLaVentanaDeComiSoloSeVe() {
        assertEquals("Ver la comida", PliegueComida.rotuloAbrir(MarcaComida.Estado.COMIDO, puedeMarcar = false))
        assertEquals("Ver la comida", PliegueComida.rotuloAbrir(MarcaComida.Estado.SALTADO, puedeMarcar = false))
    }
}
