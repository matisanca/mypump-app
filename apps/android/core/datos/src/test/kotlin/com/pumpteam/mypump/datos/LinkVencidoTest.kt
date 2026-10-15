package com.pumpteam.mypump.datos

import java.io.IOException
import kotlinx.coroutines.CoroutineScope
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * Revisión del 15-oct, hallazgo 11 (gemelo de LinkVencidoTests.swift): `entrar` guardaba el token nuevo antes de validarlo y
 * lo borraba al ver `[]`. Un cliente con su cuenta andando que tocaba un link viejo de WhatsApp (nunca usado en ese
 * teléfono, así que no estaba anotado como inválido) quedaba en "pegá tu link" y sin su cuenta. Ahora, con una cuenta que
 * anda, el link nuevo se valida antes de reemplazarla.
 */
class LinkVencidoTest {
    private val raiz = carpetaTemporal("link-vencido")

    private class Telefono(val m: ModeloApp, val almacen: TokenEnMemoria, val prefs: PreferenciasEnMemoria)

    private fun telefono(alcance: CoroutineScope, sinRedParaElLink: Boolean = false): Telefono {
        val t = TransporteProgramado { fn, cuerpo ->
            val tok = cuerpo["p_token"]?.comoTexto
            if (fn == "mypump_get_cliente_info") {
                if (tok == VIEJO) {
                    if (sinRedParaElLink) throw IOException("sin conexión a internet")
                    return@TransporteProgramado 200 to "[]"
                }
                if (tok == NUEVO && sinRedParaElLink) throw IOException("sin conexión a internet")
                return@TransporteProgramado 200 to INFO
            }
            200 to "[]"
        }
        val almacen = TokenEnMemoria(TOK_A)
        val prefs = PreferenciasEnMemoria()
        return Telefono(ModeloApp(ClienteRpc(transporte = t), almacen, raiz, prefs, alcance), almacen, prefs)
    }

    @Test
    fun unLinkViejoNuncaUsadoNoBorraLaCuenta() = enUnHilo { alcance ->
        val tel = telefono(alcance)
        val m = tel.m
        m.cargar()
        assertEquals(ModeloApp.Fase.LISTO, m.fase.value)
        assertFalse(m.entrar("https://app.mypumpteam.com/?t=$VIEJO"))
        assertEquals(ModeloApp.Fase.LISTO, m.fase.value, "quedó en \"pegá tu link\"")
        assertTrue(m.token == TOK_A && tel.almacen.leer() == TOK_A, "se perdió la cuenta que andaba")
        assertEquals(VIEJO, tel.prefs.leer(ModeloApp.CLAVE_TOKEN_INVALIDO), "queda anotado: la próxima vez ni se pregunta")
        assertEquals(ModeloApp.AvisoLink.VENCIDO, m.avisoLink.value)
        // Tocarlo otra vez avisa lo mismo sin preguntar, y lo que no tocó el cliente (la migración) no avisa.
        m.cerrarAvisoLink()
        assertFalse(m.entrar(VIEJO))
        assertTrue(m.avisoLink.value == ModeloApp.AvisoLink.VENCIDO && m.token == TOK_A)
        m.cerrarAvisoLink()
        assertFalse(m.entrar(VIEJO, avisar = false))
        assertNull(m.avisoLink.value)
    }

    @Test
    fun siLaMigracionDejoElLinkVencidoEnElAlmacenVuelveElQueAnda() = enUnHilo { alcance ->
        val tel = telefono(alcance)
        val m = tel.m
        m.cargar()
        tel.almacen.guardar(VIEJO)   // la Fase L adoptó el link de la app vieja, que ya no sirve
        assertFalse(m.entrar(VIEJO, avisar = false))
        assertTrue(m.token == TOK_A && tel.almacen.leer() == TOK_A, "el próximo arranque iba a abrir con el link vencido")
    }

    @Test
    fun sinRedParaRevisarElLinkSeQuedaEnLaCuenta() = enUnHilo { alcance ->
        val tel = telefono(alcance, sinRedParaElLink = true)
        val m = tel.m
        m.cargar()
        assertFalse(m.entrar("https://app.mypumpteam.com/?t=$NUEVO"))
        assertTrue(
            m.fase.value == ModeloApp.Fase.LISTO && m.token == TOK_A && tel.almacen.leer() == TOK_A,
            "se reemplazó la cuenta sin poder revisar el link",
        )
        assertEquals(ModeloApp.AvisoLink.SIN_CONEXION, m.avisoLink.value)
    }

    @Test
    fun unLinkQueAndaCambiaDeCuenta() = enUnHilo { alcance ->
        val tel = telefono(alcance)
        val m = tel.m
        m.cargar()
        assertTrue(m.entrar("https://app.mypumpteam.com/?t=$NUEVO"))
        assertTrue(m.fase.value == ModeloApp.Fase.LISTO && m.token == NUEVO && tel.almacen.leer() == NUEVO)
        assertNull(m.avisoLink.value)
    }

    @Test
    fun sinCuentaUnLinkVencidoAvisaComoHoy() = enUnHilo { alcance ->
        val t = TransporteProgramado { _, _ -> 200 to "[]" }
        val almacen = TokenEnMemoria(null)
        val m = ModeloApp(ClienteRpc(transporte = t), almacen, raiz, PreferenciasEnMemoria(), alcance)
        assertFalse(m.entrar(VIEJO))
        assertTrue(m.fase.value == ModeloApp.Fase.TOKEN_INVALIDO && almacen.leer() == null)
    }

    private companion object {
        const val TOK_A = "AAAAAAAAAAAAAAAAAAAA"
        const val VIEJO = "VVVVVVVVVVVVVVVVVVVV"
        const val NUEVO = "NNNNNNNNNNNNNNNNNNNN"
        const val INFO = """[{"cliente_id":"c1","nombre":"Cliente","perfil":"natural"}]"""
    }
}
