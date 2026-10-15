package com.pumpteam.mypump.datos

import com.pumpteam.mypump.reglas.AlimentoPropioNuevo
import com.pumpteam.mypump.reglas.ComidaLibreNueva
import java.util.concurrent.atomic.AtomicBoolean
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.async
import kotlinx.coroutines.delay
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * Lo mismo que el hallazgo 10 (`hidratarDieta`, revisión del 15-oct) en las funciones de Dieta que esperan al servidor: las
 * comidas libres (traerlas, crear una y borrar una) y el alimento propio. Si mientras se espera entra el link de otra persona
 * (Mati abriendo la cuenta de un cliente en su teléfono), lo que vuelve es de la cuenta anterior y no se aplica a la nueva.
 * Gemelo de DietaOtraCuentaTests.swift (3d59f6f), más crear la comida y el alimento propio. Cada prueba falla sin el arreglo
 * y, al final, mira que en la misma cuenta todo siga andando como siempre.
 */
class DietaOtraCuentaTest {
    private val raiz = carpetaTemporal("dieta-otra-cuenta")

    /** El servidor de las dos cuentas: lo de A que elija la prueba tarda, y mientras tanto entra B. */
    private class Servidor(borrarFalla: Boolean = false) {
        /** La función de A que tarda. Se prende después de la carga de A (que también trae las comidas libres). */
        @Volatile var lentaDeA: String? = null

        /** El pedido lento de A ya está esperando la respuesta. */
        val esperando = AtomicBoolean(false)

        val transporte = TransporteProgramado { fn, cuerpo ->
            val deA = cuerpo["p_token"]?.comoTexto == TOK_A
            if (deA && fn == lentaDeA) {
                esperando.set(true)
                delay(300)
            }
            when (fn) {
                "mypump_get_cliente_info" -> 200 to """[{"cliente_id":"${if (deA) "c-a" else "c-b"}","nombre":"Cliente","perfil":"natural"}]"""
                "mypump_get_comidas_libres" -> 200 to "[${comida(if (deA) "de-a" else "de-b")}]"
                "mypump_crear_comida_libre" -> 200 to "[${comida(if (deA) "nueva-de-a" else "nueva-de-b")}]"
                "mypump_borrar_comida_libre" -> if (borrarFalla) 500 to """{"message":"caído (prueba)"}""" else 200 to "true"
                "mypump_create_custom_food" ->
                    200 to """[{"name":"${if (deA) "Pan de A" else "Pan de B"}","kcal":250,"prot":8,"carb":48,"fat":3,"unit":"g"}]"""
                else -> 200 to "[]"
            }
        }
    }

    private fun modelo(s: Servidor, alcance: CoroutineScope) =
        ModeloApp(ClienteRpc(transporte = s.transporte), TokenEnMemoria(TOK_A), raiz, PreferenciasEnMemoria(), alcance)

    /** Espera a que el pedido lento de A esté en vuelo (así B entra justo en el medio). */
    private suspend fun enVuelo(s: Servidor) {
        repeat(100) { if (!s.esperando.get()) delay(10) }
        assertTrue(s.esperando.get(), "el pedido de A nunca salió")
    }

    private suspend fun entraB(m: ModeloApp) {
        assertTrue(m.entrar("https://app.mypumpteam.com/?t=$TOK_B"))
        assertEquals(TOK_B, m.token)
    }

    @Test
    fun lasComidasLibresDeLaCuentaAnteriorNoPisanLasDeLaNueva() = enUnHilo { alcance ->
        val s = Servidor()
        val m = modelo(s, alcance)
        m.cargar()
        assertEquals(listOf("de-a"), m.comidasLibres.value.map { it.id })
        s.lentaDeA = "mypump_get_comidas_libres"
        val tarde = async { m.cargarComidasLibres() }
        enVuelo(s)
        entraB(m)
        tarde.await()
        assertEquals(listOf("de-b"), m.comidasLibres.value.map { it.id }, "quedaron las comidas libres de A en B")
        // En la misma cuenta se traen como siempre.
        m.cargarComidasLibres()
        assertEquals(listOf("de-b"), m.comidasLibres.value.map { it.id })
    }

    @Test
    fun unaComidaCreadaEnLaCuentaAnteriorNoApareceEnLaNueva() = enUnHilo { alcance ->
        val s = Servidor()
        val m = modelo(s, alcance)
        m.cargar()
        s.lentaDeA = "mypump_crear_comida_libre"
        val creada = async { m.crearComidaLibre(COMIDA) }
        enVuelo(s)
        entraB(m)
        // Se creó (en la cuenta de A, que es donde se pidió): no es un error para quien la cargó.
        assertEquals("nueva-de-a", creada.await().valorONull()?.id)
        assertEquals(listOf("de-b"), m.comidasLibres.value.map { it.id }, "la comida creada en A apareció en B")
        // En la misma cuenta se suma como siempre.
        assertEquals("nueva-de-b", m.crearComidaLibre(COMIDA).valorONull()?.id)
        assertEquals(listOf("de-b", "nueva-de-b"), m.comidasLibres.value.map { it.id })
    }

    @Test
    fun unBorradoQueFallaNoVuelveAPonerLasDeLaCuentaAnterior() = enUnHilo { alcance ->
        val s = Servidor(borrarFalla = true)
        val m = modelo(s, alcance)
        m.cargar()
        s.lentaDeA = "mypump_borrar_comida_libre"
        val borrado = async { m.borrarComidaLibre("de-a") }
        enVuelo(s)
        entraB(m)
        assertFalse(borrado.await())
        assertEquals(listOf("de-b"), m.comidasLibres.value.map { it.id }, "el borrado que falló volvió a poner las de A en B")
        // En la misma cuenta, un borrado que falla sí la vuelve a poner.
        assertFalse(m.borrarComidaLibre("de-b"))
        assertEquals(listOf("de-b"), m.comidasLibres.value.map { it.id })
    }

    @Test
    fun unAlimentoPropioCreadoEnLaCuentaAnteriorNoSeSumaALaNueva() = enUnHilo { alcance ->
        val s = Servidor()
        val m = modelo(s, alcance)
        m.cargar()
        s.lentaDeA = "mypump_create_custom_food"
        val creado = async { m.crearAlimentoPropio(ALIMENTO) }
        enVuelo(s)
        entraB(m)
        assertEquals("Pan de A", creado.await().valorONull()?.nombre)
        assertTrue(m.alimentosPropios.value.isEmpty(), "el alimento propio de A quedó en B: ${m.alimentosPropios.value}")
        // En la misma cuenta se suma como siempre.
        assertEquals("Pan de B", m.crearAlimentoPropio(ALIMENTO).valorONull()?.nombre)
        assertEquals(listOf("Pan de B"), m.alimentosPropios.value.map { it.nombre })
    }

    private companion object {
        const val TOK_A = "AAAAAAAAAAAAAAAAAAAA"
        const val TOK_B = "BBBBBBBBBBBBBBBBBBBB"
        val COMIDA = ComidaLibreNueva.Datos(hora = "13:00", descripcion = "Milanesa con puré", kcal = 700.0, prot = 40.0, carb = 60.0, fat = 30.0, detalle = null)
        val ALIMENTO = AlimentoPropioNuevo.Datos("Pan", 250.0, 8.0, 48.0, 3.0, "g", null, "")

        fun comida(id: String) = """{"id":"$id","fecha":"2026-10-15","descripcion":"$id","kcal":100,"prot":1,"carb":1,"fat":1}"""
    }
}
