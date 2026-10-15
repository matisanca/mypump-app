package com.pumpteam.mypump.datos

import kotlinx.coroutines.delay
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * CHA-04 (SondeoChatTests de iOS): el sondeo va cada 45 s con el chat cerrado y cada 15 s abierto (al abrirlo arranca de
 * nuevo), y parado no consulta más (la app en segundo plano lo para). Las esperas se anotan en vez de dormirlas.
 */
class SondeoChatTest {
    @Test
    fun cuarentaYCincoCerradoQuinceAbiertoYNadaParado() = enUnHilo { alcance ->
        val m = ModeloChat(ClienteRpc(transporte = TransporteProgramado { _, _ -> 200 to "[]" }), "tokenDePrueba_0000000000", null, alcance)
        // Todo corre en el hilo del test (enUnHilo): la lista no necesita candado.
        val pedidas = mutableListOf<Long>()
        m.dormir = { ms ->
            pedidas += ms
            delay(5)
        }
        suspend fun esperar(condicion: () -> Boolean): Boolean {
            repeat(200) {
                if (condicion()) return true
                delay(10)
            }
            return condicion()
        }
        m.empezarSondeo()
        assertTrue(esperar { pedidas.size >= 2 })
        assertTrue(pedidas.all { it == 45_000L }, "$pedidas")
        m.abierto = true
        val antes = pedidas.size
        assertTrue(esperar { pedidas.size >= antes + 2 })
        assertEquals(15_000L, pedidas.last())
        m.pararSondeo()
        delay(30)
        val parado = pedidas.size
        delay(100)
        assertEquals(parado, pedidas.size, "siguió consultando parado")
    }
}
