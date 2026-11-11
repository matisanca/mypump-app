package com.pumpteam.mypump.datos

import com.pumpteam.mypump.modelos.ValorJson
import com.pumpteam.mypump.reglas.ReglasListaPrevia
import java.io.File
import java.time.Instant
import kotlinx.coroutines.runBlocking
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/** La lista previa a la videollamada (2.3.0): qué trae, cada cuánto y cuándo no muestra nada. Gemelo de ListaPreviaModeloTests.swift. */
class ListaPreviaModeloTest {
    private val token = "WWWWWWWWWWWWWWWWWWWW"
    private fun raiz() = carpetaTemporal("lista-previa")

    private class Reloj {
        var ahora: Instant = Instant.parse("2026-11-10T15:00:00Z")
        fun avanzar(segundos: Long) { ahora = ahora.plusSeconds(segundos) }
    }

    private fun armar(d: DobleColaA, r: File = raiz(), reloj: Reloj = Reloj(), palanca: Boolean? = true) =
        ModeloListaPrevia(ClienteRpc(transporte = d), token, Disco(r, token)) { reloj.ahora }.also { m -> palanca?.let(m::recordarPalanca) }

    @Test fun traeLaLista(): Unit = runBlocking {
        val m = armar(DobleColaA.escenario("sinPermiso"))
        m.refrescar()
        val v = m.vista.value!!
        assertEquals(listOf("guia", "dudas", "formulario", "fotos"), v.items.map { it.clave })
        assertEquals("Llevás 1 de 3", v.resumen)
        assertEquals(ReglasListaPrevia.Destino.GUIA, v.items.first().destino)
        assertEquals(ReglasListaPrevia.Destino.FOTOS, v.items.last().destino)
        assertNull(v.items[2].destino)
    }

    @Test fun conLaPalancaApagadaOSinLeerNoLlama(): Unit = runBlocking {
        val d = DobleColaA.escenario("sinPermiso")
        for (p in listOf(null, false)) {
            val m = armar(d, palanca = p)
            m.refrescar()
            assertNull(m.vista.value)
        }
        assertTrue(d.llamadas.isEmpty())
    }

    @Test fun comoMuchoUnPedidoPorMinuto(): Unit = runBlocking {
        val d = DobleColaA.escenario("sinPermiso")
        val reloj = Reloj()
        val m = armar(d, reloj = reloj)
        m.refrescar()
        m.refrescar()
        reloj.avanzar(59)
        m.refrescar()
        assertEquals(1, d.llamadasLista.size)
        d.lista = DobleColaA.LISTA_LISTA
        reloj.avanzar(2)
        m.refrescar()
        assertEquals(2, d.llamadasLista.size)
        assertTrue(m.vista.value?.todoListo == true)
        assertEquals("Ya tenés todo listo", m.vista.value?.resumen)
    }

    @Test fun inactivaSinServidorOTokenCaidoNoSeVeNada(): Unit = runBlocking {
        for (caso in listOf("listaInactiva", "sinServidor")) {
            val m = armar(DobleColaA.escenario(caso))
            m.refrescar()
            assertNull(m.vista.value, caso)
        }
        val m = armar(DobleColaA().apply { tokenCaido = true })
        m.refrescar()
        assertNull(m.vista.value)
    }

    @Test fun sinRedMuestraLoUltimoGuardadoYDejaDeEstarActivaLoBorra(): Unit = runBlocking {
        val r = raiz()
        val d = DobleColaA.escenario("sinPermiso")
        armar(d, r).refrescar()
        d.sinRed = true
        val m = armar(d, r, palanca = null)
        m.refrescar()
        assertEquals(4, m.vista.value?.items?.size)
        // La videollamada ya pasó: no queda nada, tampoco sin red la próxima vez.
        d.sinRed = false
        d.lista = """{"ok":true,"activa":false,"items":[]}"""
        val m2 = armar(d, r, palanca = null)
        m2.refrescar()
        assertNull(m2.vista.value)
        d.sinRed = true
        val m3 = armar(d, r, palanca = null)
        m3.refrescar()
        assertNull(m3.vista.value)
    }

    @Test fun apagarLaPalancaBorraLoGuardado(): Unit = runBlocking {
        val r = raiz()
        val d = DobleColaA.escenario("sinPermiso")
        val m = armar(d, r)
        m.refrescar()
        m.recordarPalanca(false)
        assertNull(m.vista.value)
        assertFalse(m.palancaRecordada)
        d.sinRed = true
        val m2 = armar(d, r)
        m2.refrescar()
        assertNull(m2.vista.value)
    }

    @Test fun conLaPalancaPrendidaModeloAppLaTraeYApagadaLaBorra() = enUnHilo { alcance ->
        val d = DobleColaA.escenario("sinPermiso")
        val m = ModeloApp(ClienteRpc(transporte = d), TokenEnMemoria(token), raiz(), PreferenciasEnMemoria(), alcance)
        m.cargar()
        assertEquals(1, d.llamadasLista.size)
        assertEquals(4, m.listaPrevia.value?.vista?.value?.items?.size)
        m.sincronizarListaPrevia()   // al abrir Entreno, enseguida: no repite el pedido
        assertEquals(1, d.llamadasLista.size)
        d.palancaLista = false
        m.cargar()
        assertEquals(1, d.llamadasLista.size)
        assertNull(m.listaPrevia.value?.vista?.value)
    }

    @Test fun laDeLaDemoEsFijaYNoLlama(): Unit = runBlocking {
        val m = ModeloListaPrevia.demo(ValorJson.parsear(DobleColaA.LISTA_DEMO))
        assertTrue(m.demo)
        assertEquals("Llevás 1 de 3", m.vista.value?.resumen)
        m.refrescar()
        m.recordarPalanca(false)
        m.apagar()
        assertEquals(4, m.vista.value?.items?.size)
    }
}
