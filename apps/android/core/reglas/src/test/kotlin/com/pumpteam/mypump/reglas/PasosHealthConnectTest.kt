package com.pumpteam.mypump.reglas

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/** 2.3.1: pasos que no llegan de Samsung Health por Health Connect. */
class PasosHealthConnectTest {
    @Test fun sinPermisoNoDiceNada() {
        assertNull(PasosHealthConnect.evaluar(false, emptyList()))
        assertNull(PasosHealthConnect.evaluar(false, listOf(PasosHealthConnect.SAMSUNG_HEALTH to 500.0)))
    }

    @Test fun conPermisoYCeroPasosAvisa() {
        assertEquals(PasosHealthConnect.Estado(true, null), PasosHealthConnect.evaluar(true, emptyList()))
        // Registros en cero o rotos cuentan como nada.
        assertEquals(PasosHealthConnect.Estado(true, null), PasosHealthConnect.evaluar(true, listOf("x" to 0.0, "y" to Double.NaN)))
    }

    @Test fun conPasosDiceDeDondeVienen() {
        val e = PasosHealthConnect.evaluar(true, listOf(
            PasosHealthConnect.SAMSUNG_HEALTH to 4000.0, "com.google.android.apps.fitness" to 300.0, PasosHealthConnect.SAMSUNG_HEALTH to 2500.0,
        ))!!
        assertFalse(e.sinPasos)
        assertEquals("Samsung Health", e.origen)
        assertEquals("Pasos desde: Samsung Health", PasosHealthConnect.pasosDesde(e.origen!!))
    }

    @Test fun empateYPaqueteDesconocido() {
        assertEquals("com.otra.app", PasosHealthConnect.evaluar(true, listOf("com.otra.app" to 100.0))!!.origen)
        // Empate: el primero por nombre de paquete, siempre el mismo.
        assertEquals("Google Fit", PasosHealthConnect.evaluar(true, listOf("com.sec.android.app.shealth" to 50.0, "com.google.android.apps.fitness" to 50.0))!!.origen)
    }

    @Test fun textosSinRirNiEntrenador() {
        for (t in listOf(PasosHealthConnect.TITULO, PasosHealthConnect.TEXTO, PasosHealthConnect.BOTON_SAMSUNG, PasosHealthConnect.BOTON_HEALTH_CONNECT)) {
            assertFalse(Regex("\\bRIR\\b", RegexOption.IGNORE_CASE).containsMatchIn(t)); assertFalse(t.contains("entrenador"))
        }
        assertTrue(PasosHealthConnect.TEXTO.contains("Health Connect") && PasosHealthConnect.TEXTO.contains("Pasos"))
    }
}
