package com.pumpteam.mypump.datos

import com.pumpteam.mypump.modelos.ValorJson
import com.pumpteam.mypump.reglas.Controles
import com.pumpteam.mypump.reglas.TextosControles
import java.io.File
import java.nio.file.Files
import kotlinx.coroutines.runBlocking
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/** «Tu próximo control de salud» dentro de `ModeloEstudios`, contra el doble: las dos palancas, la sección y la caída segura. */
class ControlesTest {
    private fun armar(d: DobleEstudios, estudios: Boolean = true, controles: Boolean = true): ModeloEstudios {
        val r: File = Files.createTempDirectory("controles").toFile()
        val disco = Disco(r, "tk-prueba-controles")
        val m = ModeloEstudios(ClienteRpc(transporte = d), "tk-prueba-controles", disco, ColaEstudios.carpeta(File(r, "sin-respaldo"), disco), esperar = {})
        m.usarPalanca(estudios)
        m.usarPalancaControles(controles)
        return m
    }
    private fun llamo(d: DobleEstudios) = "mypump_controles_get" in d.llamadas

    @Test fun palancaApagadaNoLlamaNiMuestra(): Unit = runBlocking {
        val d = DobleEstudios.escenario("controlesApagado")
        val m = armar(d, controles = false)
        m.sincronizar()
        assertNotNull(m.estado.value)
        assertFalse(llamo(d))
        assertNull(m.controles.value)
        assertNull(m.tarjetaControl())
        assertTrue(m.hitosControl().isEmpty())
        assertEquals("Semana del 23/11", m.estado.value?.proximo?.cuando)
        assertNull(m.estado.value?.proximo?.nota)
    }

    @Test fun sinEstudiosNoHayControles(): Unit = runBlocking {
        val d = DobleEstudios.escenario("controlEnVentana")
        val m = armar(d, estudios = false)
        m.sincronizar()
        assertFalse(llamo(d))
        assertNull(m.tarjetaControl())
        val n = DobleEstudios.escenario("controlEnVentana").apply { habilitado = false }
        val m2 = armar(n)
        m2.sincronizar()
        assertFalse(llamo(n))
        assertNull(m2.tarjetaControl())
    }

    @Test fun sinControl(): Unit = runBlocking {
        val d = DobleEstudios.escenario("sinControl")
        val m = armar(d)
        m.sincronizar()
        assertTrue(llamo(d))
        assertNotNull(m.controles.value)
        assertNull(m.controles.value?.proximo)
        assertNull(m.tarjetaControl())
        assertTrue(m.hitosControl().isEmpty())
        assertEquals("Semana del 23/11", m.estado.value?.proximo?.cuando)
    }

    @Test fun controlLejano(): Unit = runBlocking {
        val m = armar(DobleEstudios.escenario("controlLejano"))
        m.sincronizar()
        assertNull(m.tarjetaControl())
        val p = m.estado.value?.proximo
        assertEquals("Control de salud", p?.titulo)
        assertEquals("El miércoles 30/12", p?.cuando)
        assertEquals(TextosControles.notaProgramado, p?.nota)
        assertEquals(listOf("Próximo", "Mati lo vio"), m.hitosControl().map { it.estado })
    }

    @Test fun controlEnVentana(): Unit = runBlocking {
        val m = armar(DobleEstudios.escenario("controlEnVentana"))
        m.sincronizar()
        assertEquals(Controles.TarjetaInicio("Tu próximo control de salud", "El lunes 16/11", TextosControles.notaProgramado, "Ver mis estudios"), m.tarjetaControl())
        assertEquals("El lunes 16/11", m.estado.value?.proximo?.cuando)
        assertEquals(3, m.estado.value?.pendientes?.size)
    }

    @Test fun ordenesEnviadasSacanLaTarjetaDeArriba(): Unit = runBlocking {
        val m = armar(DobleEstudios.escenario("controlOrdenes"))
        m.sincronizar()
        assertNull(m.tarjetaControl())
        assertEquals(TextosControles.notaOrdenes, m.estado.value?.proximo?.nota)
    }

    @Test fun apagarEnElMomento(): Unit = runBlocking {
        val m = armar(DobleEstudios.escenario("controlEnVentana"))
        m.sincronizar()
        assertNotNull(m.tarjetaControl())
        m.usarPalancaControles(false)
        assertNull(m.tarjetaControl())
        assertEquals("Semana del 23/11", m.estado.value?.proximo?.cuando)
        m.usarPalancaControles(true)
        m.sincronizar()
        assertNotNull(m.tarjetaControl())
        m.usarPalanca(false)
        assertNull(m.tarjetaControl())
        assertNull(m.estado.value)
    }

    /** Apagar la palanca o la sección mientras viaja `mypump_controles_get`: esa respuesta no vuelve a pintar nada. */
    @Test fun respuestaViejaNoVuelve(): Unit = runBlocking {
        for (apagarSeccion in listOf(false, true)) {
            val d = DobleEstudios.escenario("controlEnVentana")
            val m = armar(d)
            d.antesDeControles = { if (apagarSeccion) m.usarPalanca(false) else m.usarPalancaControles(false) }
            m.sincronizar()
            assertTrue(llamo(d))
            assertNull(m.controles.value)
            assertNull(m.tarjetaControl())
            assertTrue(m.hitosControl().isEmpty())
            assertNull(m.estado.value?.proximo?.nota, "el bloque de Estudios vuelve a lo suyo")
        }
    }

    /** Prendida con la app abierta: avisa que hay que traerlos y los trae sin pedir Estudios de nuevo. */
    @Test fun prenderConLaAppAbiertaLosTrae(): Unit = runBlocking {
        val d = DobleEstudios.escenario("controlEnVentana")
        val m = armar(d, controles = false)
        m.sincronizar()
        assertFalse(llamo(d))
        assertTrue(m.usarPalancaControles(true))
        assertFalse(m.usarPalancaControles(true), "ya prendida: no hace falta otra vez")
        m.traerControles()
        assertNotNull(m.tarjetaControl())
    }

    @Test fun caidaSegura(): Unit = runBlocking {
        val d = DobleEstudios.escenario("controlEnVentana").apply { controlesSinFuncion = true }
        val m = armar(d)
        m.sincronizar()
        assertNotNull(m.estado.value)
        assertNull(m.controles.value)
        val d2 = DobleEstudios.escenario("controlEnVentana")
        val m2 = armar(d2)
        m2.sincronizar()
        d2.sinRed = true
        m2.sincronizar()
        assertNotNull(m2.tarjetaControl(), "un corte deja lo de esta sesión")
        val d3 = DobleEstudios.escenario("controlEnVentana").apply { controles = ValorJson.Lista(emptyList()) }
        val m3 = armar(d3)
        m3.sincronizar()
        assertNotNull(m3.estado.value)
        assertNull(m3.controles.value)
    }

    @Test fun palancaDeLaConfig() {
        assertFalse(PalancaRemota.desde(ValorJson.Objeto(emptyMap())).controlesApp)
        assertTrue(PalancaRemota.desde(ValorJson.Objeto(mapOf("controles_app" to ValorJson.Booleano(true)))).controlesApp)
        assertFalse(PalancaRemota.desde(ValorJson.Objeto(mapOf("controles_app" to ValorJson.Texto("true")))).controlesApp)
    }
}
