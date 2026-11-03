package com.pumpteam.mypump.datos

import com.pumpteam.mypump.reglas.AgregadosComida
import com.pumpteam.mypump.reglas.AlimentoAgregado
import com.pumpteam.mypump.reglas.CodigoBarras
import com.pumpteam.mypump.reglas.MacrosPor100
import java.io.File
import java.io.IOException
import java.util.concurrent.CopyOnWriteArrayList
import kotlinx.coroutines.CoroutineScope
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * El código de barras en el modelo (2.1, S3): la pregunta a Open Food Facts (solo el código, con el User-Agent propio), la
 * caché por código en el teléfono y lo que pasa sin red o con Open Food Facts caído. Gemelo de BarrasDietaTests de iOS.
 */
class BarrasDietaTest {
    private val raiz: File = carpetaTemporal("barras")

    /** Open Food Facts de mentira: contesta [respuesta] (null = sin red) y anota cada pedido. */
    private class OFF : Transporte {
        val pedidos = CopyOnWriteArrayList<Pedido>()
        var respuesta: Pair<Int, String>? = 200 to "{}"
        override suspend fun enviar(pedido: Pedido): Respuesta {
            pedidos += pedido
            val (s, cuerpo) = respuesta ?: throw IOException("sin conexión (prueba)")
            return Respuesta(s, cuerpo.toByteArray())
        }
    }

    private val yogur = """{"code":"7791337006355","status":1,"product":{"product_name":"Yogurisimo sabor Natural","brands":"La serenisima","serving_quantity":200,"serving_size":"200 g","nutriments":{"energy-kcal_100g":81.5,"energy-kj_100g":341.8,"proteins_100g":7,"carbohydrates_100g":6.25,"fat_100g":3.15}}}"""

    private fun modelo(t: OFF, alcance: CoroutineScope, token: String = "AAAAAAAAAAAAAAAAAAAA") =
        ModeloApp(ClienteRpc(transporte = t), TokenEnMemoria(token), raiz, PreferenciasEnMemoria(), alcance).also { it.versionApp = "2.1.0" }

    @Test
    fun encontradoQuedaEnLaCacheYNoVuelveALaRed() = enUnHilo { alcance ->
        val off = OFF()
        off.respuesta = 200 to yogur
        val m = modelo(off, alcance)
        val r = m.buscarCodigo("7791337006355") as ModeloApp.BusquedaCodigo.Leido
        val p = (r.lectura as CodigoBarras.Lectura.Encontrado).producto
        assertEquals("Yogurisimo sabor Natural (La serenisima)", p.nombre)
        assertEquals(82.0, p.por100.kcal)
        assertEquals(200.0, p.gramosMedida)
        val pedido = off.pedidos.single()
        assertTrue(pedido.url.startsWith("https://world.openfoodfacts.org/api/v2/product/7791337006355.json?fields="))
        assertEquals("PumpTeam/2.1.0 (Android)", pedido.cabeceras["User-Agent"])
        assertEquals("GET", pedido.metodo)
        assertNull(pedido.cuerpo)
        assertEquals(CodigoBarras.ESPERA_MS, pedido.esperaMs)

        // La segunda vez sale de la caché, también en otro arranque (quedó en el disco de la cuenta).
        off.respuesta = null
        assertEquals(r, m.buscarCodigo("7791337006355"))
        assertEquals(r, modelo(off, alcance).buscarCodigo("7791337006355"))
        assertEquals(1, off.pedidos.size)
        // Otra cuenta del teléfono tiene su caché.
        assertEquals(ModeloApp.BusquedaCodigo.SinRed, modelo(off, alcance, "BBBBBBBBBBBBBBBBBBBB").buscarCodigo("7791337006355"))
    }

    @Test
    fun noEncontradoEs404ConStatus0() = enUnHilo { alcance ->
        val off = OFF()
        off.respuesta = 404 to """{"code":"7790742000101","status":0,"status_verbose":"product not found"}"""
        val m = modelo(off, alcance)
        assertEquals(ModeloApp.BusquedaCodigo.Leido(CodigoBarras.Lectura.NoEncontrado), m.buscarCodigo("7790742000101"))
        assertEquals(ModeloApp.BusquedaCodigo.Leido(CodigoBarras.Lectura.NoEncontrado), m.buscarCodigo("7790742000101"))
        assertEquals(1, off.pedidos.size, "El no encontrado también se guarda (un día)")
    }

    @Test
    fun sinRedOCaidoNoGuardaNada() = enUnHilo { alcance ->
        val off = OFF()
        val m = modelo(off, alcance)
        off.respuesta = null
        assertEquals(ModeloApp.BusquedaCodigo.SinRed, m.buscarCodigo("7791337006355"))
        off.respuesta = 503 to "<html>Page temporarily unavailable</html>"
        assertEquals(ModeloApp.BusquedaCodigo.SinRed, m.buscarCodigo("7791337006355"))
        off.respuesta = 429 to """{"status":0}"""
        assertEquals(ModeloApp.BusquedaCodigo.SinRed, m.buscarCodigo("7791337006355"))
        off.respuesta = 200 to "<html>no es JSON</html>"
        assertEquals(ModeloApp.BusquedaCodigo.SinRed, m.buscarCodigo("7791337006355"))
        off.respuesta = 200 to yogur
        assertTrue((m.buscarCodigo("7791337006355") as ModeloApp.BusquedaCodigo.Leido).lectura is CodigoBarras.Lectura.Encontrado)
        assertEquals(5, off.pedidos.size)
    }

    @Test
    fun elPropioCreadoDesdeUnCodigoApareceAlVolverAEscanearlo() = enUnHilo { alcance ->
        val off = OFF()
        off.respuesta = 404 to """{"status":0}"""
        val m = modelo(off, alcance)
        assertEquals(ModeloApp.BusquedaCodigo.Leido(CodigoBarras.Lectura.NoEncontrado), m.buscarCodigo("7790742000101"))
        val c = AgregadosComida.Candidato("Leche de la Mini", MacrosPor100(60.0, 3.0, 5.0, 3.0), "porcion", 200.0,
            AlimentoAgregado.Origen.PROPIO, "7790742000101")
        m.recordarCodigoPropio("7790742000101", c)
        val p = ((m.buscarCodigo("7790742000101") as ModeloApp.BusquedaCodigo.Leido).lectura as CodigoBarras.Lectura.Encontrado).producto
        assertTrue(p.propio)
        assertEquals(AlimentoAgregado.Origen.PROPIO, p.candidato.origen)
        assertEquals("7790742000101", p.candidato.codigo)
        assertEquals(1, off.pedidos.size)
    }
}
