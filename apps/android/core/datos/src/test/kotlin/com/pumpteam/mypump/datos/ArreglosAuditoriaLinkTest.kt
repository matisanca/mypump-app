package com.pumpteam.mypump.datos

import com.pumpteam.mypump.modelos.ValorJson
import kotlinx.coroutines.delay
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Test

/**
 * Gemelo de ArreglosAuditoriaLinkTests.swift. Auditoría del 10/11, F10: el alumno quedaba afuera sin explicación al volver a
 * abrir la app después de la baja del link, con un link cortado tocado desde afuera, o si el link caía con la app abierta.
 */
class ArreglosAuditoriaLinkTest {
    private val raiz = carpetaTemporal("link-caido")
    private val token = "BBBBBBBBBBBBBBBBBBBB"

    private class Base {
        @Volatile var baja = false
    }

    private fun transporte(base: Base) = TransporteProgramado { fn, _ ->
        when (fn) {
            "mypump_get_cliente_info" -> 200 to if (base.baja) "[]" else """[{"cliente_id":"c1","nombre":"Cliente","perfil":"natural"}]"""
            "mypump_set_habito" -> 200 to if (base.baja) "null" else "true"
            else -> 200 to "[]"
        }
    }

    @Test
    fun alVolverAAbrirSeSigueExplicando() = enUnHilo { alcance ->
        val base = Base().apply { baja = true }
        val almacen = TokenEnMemoria(token)
        val prefs = PreferenciasEnMemoria()
        ModeloApp(ClienteRpc(transporte = transporte(base)), almacen, raiz, prefs, alcance).cargar()
        val otra = ModeloApp(ClienteRpc(transporte = transporte(base)), almacen, raiz, prefs, alcance)
        assertEquals(ModeloApp.Fase.TOKEN_INVALIDO, otra.fase.value, "antes: la bienvenida vacía, sin decir qué pasó")
        otra.salir()
        assertEquals(ModeloApp.Fase.SIN_TOKEN, ModeloApp(ClienteRpc(transporte = transporte(base)), almacen, raiz, prefs, alcance).fase.value)
    }

    @Test
    fun unLinkCortadoDesdeAfueraAvisa() = enUnHilo { alcance ->
        val m = ModeloApp(ClienteRpc(transporte = transporte(Base())), TokenEnMemoria(null), raiz, PreferenciasEnMemoria(), alcance)
        assertFalse(m.entrar("https://app.ejemplo.com/?t=AAAA"))
        assertEquals(ModeloApp.AvisoLink.MAL_FORMADO, m.avisoLink.value)
        m.cerrarAvisoLink()
        m.entrar("mypump://abrir?scene=diet")
        assertNull(m.avisoLink.value, "los links de los avisos no son un link de entrada")
    }

    @Test
    fun siCaeConLaAppAbiertaNoDiceSinConexion() = enUnHilo { alcance ->
        val base = Base()
        val m = ModeloApp(ClienteRpc(transporte = transporte(base)), TokenEnMemoria(token), raiz, PreferenciasEnMemoria(), alcance)
        m.cargar()
        assertEquals(ModeloApp.Fase.LISTO, m.fase.value)
        base.baja = true
        m.outbox!!.encolar("habito", ValorJson.objeto("fecha" to ValorJson.Texto("2026-11-10"), "campo" to ValorJson.Texto("agua"), "valor" to ValorJson.Numero(3.0)), "h1")
        m.outbox!!.drenar()
        repeat(100) { if (m.fase.value != ModeloApp.Fase.TOKEN_INVALIDO) delay(20) }
        assertEquals(ModeloApp.Fase.TOKEN_INVALIDO, m.fase.value)
    }
}
