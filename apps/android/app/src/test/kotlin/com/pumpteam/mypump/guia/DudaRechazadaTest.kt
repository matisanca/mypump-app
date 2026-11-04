package com.pumpteam.mypump.guia

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test

/** Una duda que el servidor rechaza vuelve al campo y no pisa lo que el cliente escribió después. */
class DudaRechazadaTest {
    @Test
    fun conElCampoVacioVuelveTalCual() {
        assertEquals("¿Con comida?", devolverAlCampo("¿Con comida?", null))
        assertEquals("¿Con comida?", devolverAlCampo("¿Con comida?", "  "))
    }

    @Test
    fun conTextoNuevoVaAdelanteSeparada() {
        assertEquals("¿Con comida?\n\nY otra", devolverAlCampo("¿Con comida?", "Y otra"))
    }
}
