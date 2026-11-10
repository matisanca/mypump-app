package com.pumpteam.mypump.datos

import kotlinx.coroutines.CoroutineScope
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNotEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * Gemelo de SesionNoSeCierraTests.swift. Un alumno quedó afuera con «No reconocí ese link»: la pantalla de acceso solo
 * aparece sin cuenta, así que primero se le había cerrado la sesión. Un fallo pasajero no puede cerrarla: solo un `[]` del
 * servidor dice que el token no sirve.
 */
class SesionNoSeCierraTest {
    private val raiz = carpetaTemporal("sesion-no-se-cierra")

    /** El Keystore con una falla pasajera: no se pudo leer, aunque el token esté guardado. */
    private class Bloqueado(var token: String?) : AlmacenToken {
        var abierto = false

        override fun leer(): String? = if (abierto) token else null

        override fun guardar(token: String?) {
            this.token = token
        }
    }

    private fun modelo(almacen: AlmacenToken, prefs: Preferencias, alcance: CoroutineScope, cuerpo: () -> String): ModeloApp {
        val t = TransporteProgramado { fn, _ -> if (fn == "mypump_get_cliente_info") 200 to cuerpo() else 200 to "[]" }
        return ModeloApp(ClienteRpc(transporte = t), almacen, raiz, prefs, alcance)
    }

    @Test
    fun unDoscientosQueNoEsListaNoBorraLaCuenta() = enUnHilo { alcance ->
        for (cuerpo in listOf("", "null", "{}", """{"message":"ocupado"}""")) {
            val almacen = TokenEnMemoria(TOKEN)
            val prefs = PreferenciasEnMemoria()
            val m = modelo(almacen, prefs, alcance) { cuerpo }
            m.cargar()
            assertEquals(ModeloApp.Fase.SIN_SERVICIO, m.fase.value, "con «$cuerpo»")
            assertEquals(TOKEN, almacen.leer(), "borró la cuenta con «$cuerpo»")
            assertNull(prefs.leer(ModeloApp.CLAVE_TOKEN_INVALIDO), "anotó como vencido un token válido con «$cuerpo»")
        }
    }

    @Test
    fun conCopiaGuardadaSigueAdentro() = enUnHilo { alcance ->
        val almacen = TokenEnMemoria(TOKEN)
        var cuerpo = INFO
        // Con un plan: sin plan no se guarda copia.
        val t = TransporteProgramado { fn, _ ->
            when (fn) {
                "mypump_get_cliente_info" -> 200 to cuerpo
                "mypump_get_dieta_activa" -> 200 to MarcasComidasTest.DIETA
                else -> 200 to "[]"
            }
        }
        val m = ModeloApp(ClienteRpc(transporte = t), almacen, raiz, PreferenciasEnMemoria(), alcance)
        m.cargar()
        assertEquals(ModeloApp.Fase.LISTO, m.fase.value)
        cuerpo = ""
        m.cargar()
        assertEquals(ModeloApp.Fase.LISTO, m.fase.value)
        assertTrue(m.desdeCache.value)
        assertEquals(TOKEN, almacen.leer())
    }

    @Test
    fun laListaVaciaSigueSiendoUnLinkQueYaNoSirve() = enUnHilo { alcance ->
        val almacen = TokenEnMemoria(TOKEN)
        val m = modelo(almacen, PreferenciasEnMemoria(), alcance) { "[]" }
        m.cargar()
        assertEquals(ModeloApp.Fase.TOKEN_INVALIDO, m.fase.value)
        assertNull(almacen.leer())
    }

    @Test
    fun unLinkNuevoConRespuestaRaraNoSeDaPorVencido() = enUnHilo { alcance ->
        val t = TransporteProgramado { fn, cuerpo ->
            if (fn == "mypump_get_cliente_info") 200 to (if (cuerpo["p_token"]?.comoTexto == NUEVO) "" else INFO) else 200 to "[]"
        }
        val almacen = TokenEnMemoria(TOKEN)
        val prefs = PreferenciasEnMemoria()
        val m = ModeloApp(ClienteRpc(transporte = t), almacen, raiz, prefs, alcance)
        m.cargar()
        assertFalse(m.entrar(NUEVO))
        assertEquals(ModeloApp.AvisoLink.SIN_CONEXION, m.avisoLink.value)
        assertEquals(ModeloApp.Fase.LISTO, m.fase.value)
        assertEquals(TOKEN, almacen.leer())
        assertNotEquals(NUEVO, prefs.leer(ModeloApp.CLAVE_TOKEN_INVALIDO))
    }

    @Test
    fun elTokenQueNoSePudoLeerSeRetomaAlVolver() = enUnHilo { alcance ->
        val almacen = Bloqueado(TOKEN)
        val m = modelo(almacen, PreferenciasEnMemoria(), alcance) { INFO }
        assertEquals(ModeloApp.Fase.SIN_TOKEN, m.fase.value)
        almacen.abierto = true
        m.alVolverAPrimerPlano()
        assertEquals(ModeloApp.Fase.LISTO, m.fase.value)
        assertEquals(TOKEN, m.token)
    }

    @Test
    fun unLinkViejoQueLlegaAntesDeVolverNoPisaLaCuenta() = enUnHilo { alcance ->
        val almacen = Bloqueado(TOKEN)
        val t = TransporteProgramado { fn, cuerpo ->
            if (fn == "mypump_get_cliente_info") 200 to (if (cuerpo["p_token"]?.comoTexto == NUEVO) "[]" else INFO) else 200 to "[]"
        }
        val m = ModeloApp(ClienteRpc(transporte = t), almacen, raiz, PreferenciasEnMemoria(), alcance)
        almacen.abierto = true
        assertFalse(m.entrar(NUEVO))
        assertEquals(ModeloApp.Fase.LISTO, m.fase.value)
        assertEquals(TOKEN, almacen.leer())
        assertEquals(ModeloApp.AvisoLink.VENCIDO, m.avisoLink.value)
    }

    @Test
    fun habiendoSalidoNoVuelveAEntrarSolo() = enUnHilo { alcance ->
        val m = modelo(TokenEnMemoria(TOKEN), PreferenciasEnMemoria(), alcance) { INFO }
        m.cargar()
        m.salir()
        m.alVolverAPrimerPlano()
        assertEquals(ModeloApp.Fase.SIN_TOKEN, m.fase.value)
    }

    private companion object {
        const val TOKEN = "TOKENGUARDADO0000000"
        const val NUEVO = "LINKNUEVO00000000000"
        const val INFO = """[{"cliente_id":"c1","nombre":"Cliente","perfil":"natural"}]"""
    }
}
