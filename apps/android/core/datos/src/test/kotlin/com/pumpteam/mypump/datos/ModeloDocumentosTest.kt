package com.pumpteam.mypump.datos

import com.pumpteam.mypump.modelos.ValorJson
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/** Documentos: `mypump_contrato_get`, error = sin documentos, y el enlace del servicio de firma. Datos ficticios. */
class ModeloDocumentosTest {
    private val dos = """
        {"documentos":[
          {"id":"d1","tipo":"servicio_ar","titulo":"Contrato","estado":"pendiente","firmado_en":null,"revocado_en":null},
          {"id":"d2","tipo":"consentimiento_ar","titulo":"Consentimiento","estado":"firmado","firmado_en":"2026-11-10T15:03:22.123456+00:00","revocado_en":null}
        ],"pendientes":1}
    """

    /** La RPC de Supabase y el servicio de firma, cada uno con su respuesta; anota los pedidos. */
    private class Servidor : Transporte {
        var rpc: Pair<Int, String> = 200 to """{"documentos":[]}"""
        var firma: Pair<Int, String> = 200 to """{"documentos":[]}"""
        var sinRed = false
        val pedidos = mutableListOf<Pedido>()

        override suspend fun enviar(pedido: Pedido): Respuesta {
            pedidos += pedido
            if (sinRed) throw java.io.IOException("sin conexión")
            val (status, texto) = if (java.net.URI(pedido.url).host == "firma.mypumpteam.com") firma else rpc
            return Respuesta(status, texto.toByteArray())
        }
    }

    /** Con la palanca `contrato_app` prendida (lo normal en estas pruebas). */
    private fun prendido(s: Servidor) = ModeloDocumentos(ClienteRpc(transporte = s), "tok").apply { recordarPalanca(true) }

    @Test
    fun laPalancaNaceApagadaYSoloValeTrue() {
        assertFalse(PalancaRemota.deFabrica.contratoApp)
        assertFalse(PalancaRemota.desde(ValorJson.parsear("{}")).contratoApp)
        assertFalse(PalancaRemota.desde(ValorJson.parsear("""{"contrato_app":"true"}""")).contratoApp)
        assertFalse(PalancaRemota.desde(ValorJson.parsear("""{"contrato_app":1}""")).contratoApp)
        assertTrue(PalancaRemota.desde(ValorJson.parsear("""{"contrato_app":true}""")).contratoApp)
    }

    @Test
    fun apagadaNoLlamaANadaNiMuestraNada() = enUnHilo {
        val s = Servidor().apply { rpc = 200 to dos }
        val m = ModeloDocumentos(ClienteRpc(transporte = s), "tok")
        assertFalse(m.palancaRecordada)
        m.refrescar()
        assertTrue(s.pedidos.isEmpty())
        assertFalse(m.hay || m.contratoPendiente)
        // Prendida trae; apagada de nuevo, se va todo y no vuelve a llamar.
        m.recordarPalanca(true)
        m.refrescar()
        assertTrue(m.hay && m.contratoPendiente)
        assertEquals(1, s.pedidos.size)
        m.recordarPalanca(false)
        assertFalse(m.hay || m.contratoPendiente)
        m.refrescar()
        assertFalse(m.hay)
        assertEquals(1, s.pedidos.size)
    }

    @Test
    fun laPalancaSeRecuerdaEnElDiscoDeLaCuenta() = enUnHilo {
        val raiz = carpetaTemporal("docs-palanca")
        val s = Servidor().apply { rpc = 200 to dos }
        assertFalse(ModeloDocumentos(ClienteRpc(transporte = s), "tok", Disco(raiz, "tok")).palancaRecordada, "nunca leída = apagada")
        ModeloDocumentos(ClienteRpc(transporte = s), "tok", Disco(raiz, "tok")).recordarPalanca(true)
        // Otro arranque, la config no contesta: vale lo último que se supo.
        val otro = ModeloDocumentos(ClienteRpc(transporte = s), "tok", Disco(raiz, "tok"))
        assertTrue(otro.palancaRecordada)
        otro.refrescar()
        assertTrue(otro.hay)
        otro.recordarPalanca(false)
        assertFalse(ModeloDocumentos(ClienteRpc(transporte = s), "tok", Disco(raiz, "tok")).palancaRecordada)
    }

    @Test
    fun traeLosDocumentosConElToken() = enUnHilo {
        val s = Servidor().apply { rpc = 200 to dos }
        val m = prendido(s)
        assertFalse(m.hay)
        m.refrescar()
        assertTrue(m.hay)
        assertTrue(m.contratoPendiente)
        assertEquals(listOf("d1", "d2"), m.documentos.value.map { it.id })
        val p = s.pedidos.single()
        assertTrue(p.url.endsWith("/rest/v1/rpc/mypump_contrato_get"))
        assertEquals("tok", ValorJson.parsear(p.cuerpo!!.toString(Charsets.UTF_8))["p_token"]?.comoTexto)
    }

    @Test
    fun cualquierErrorEsSinDocumentos() = enUnHilo {
        val s = Servidor()
        val m = prendido(s)
        val errores = listOf(
            401 to """{"code":"28000","message":"token inválido"}""",
            404 to """{"code":"PGRST202","message":"no existe"}""",
            503 to "caído",
            200 to "<html>portal</html>",
            200 to "null",
            200 to "[]",
        )
        for (e in errores) {
            s.rpc = 200 to dos
            m.refrescar()
            assertTrue(m.hay)
            s.rpc = e
            m.refrescar()
            assertFalse(m.hay, "$e")
            assertFalse(m.contratoPendiente)
        }
        s.rpc = 200 to dos
        m.refrescar()
        s.sinRed = true
        m.refrescar()
        assertFalse(m.hay)
    }

    @Test
    fun elConsentimientoSoloNoPrendeElAviso() = enUnHilo {
        val s = Servidor().apply {
            rpc = 200 to """{"documentos":[{"id":"x","tipo":"consentimiento_ar","estado":"pendiente"},{"id":"y","tipo":"servicio_ext","estado":"firmado","firmado_en":"2026-11-01T12:00:00+00:00"}]}"""
        }
        val m = prendido(s)
        m.refrescar()
        assertTrue(m.hay)
        assertFalse(m.contratoPendiente)
    }

    @Test
    fun elEnlaceSalDelServicioDeFirma() = enUnHilo {
        val s = Servidor().apply {
            rpc = 200 to dos
            firma = 200 to """{"documentos":[{"id":"d2","url":"https://firma.mypumpteam.com/f/otro"},{"id":"d1","tipo":"servicio_ar","estado":"pendiente","firmado_en":null,"url":"https://firma.mypumpteam.com/f/abc.def"}]}"""
        }
        val m = prendido(s)
        m.refrescar()
        assertEquals("https://firma.mypumpteam.com/f/abc.def", m.enlace(m.documentos.value[0]))
        val p = s.pedidos.last()
        assertEquals("https://firma.mypumpteam.com/api/app/documentos", p.url)
        assertEquals("POST", p.metodo)
        assertNull(p.cabeceras["Authorization"], "el token va en el cuerpo, como pide el servicio")
        assertEquals(ValorJson.objeto("token" to ValorJson.Texto("tok")), ValorJson.parsear(p.cuerpo!!.toString(Charsets.UTF_8)))
    }

    @Test
    fun sinServicioNoHayEnlace() = enUnHilo {
        val s = Servidor().apply { rpc = 200 to dos }
        val m = prendido(s)
        m.refrescar()
        val d = m.documentos.value[0]
        for (r in listOf(401 to """{"error":"token"}""", 502 to "Bad gateway", 200 to """{"documentos":[]}""", 200 to "<html></html>")) {
            s.firma = r
            assertNull(m.enlace(d), "$r")
        }
        s.sinRed = true
        assertNull(m.enlace(d))
    }

    @Test
    fun soloSeAbreHttpsDelPropioServicio() {
        val f = ConfigBackend.FIRMA_PRODUCCION
        assertNotNull(ModeloDocumentos.enlaceSeguro("https://firma.mypumpteam.com/f/x", f))
        assertNotNull(ModeloDocumentos.enlaceSeguro("https://FIRMA.mypumpteam.com/f/x", f))
        assertNull(ModeloDocumentos.enlaceSeguro("http://firma.mypumpteam.com/f/x", f))
        assertNull(ModeloDocumentos.enlaceSeguro("https://otro.example.com/f/x", f))
        assertNull(ModeloDocumentos.enlaceSeguro("https://firma.mypumpteam.com.example.com/f/x", f))
        assertNull(ModeloDocumentos.enlaceSeguro("javascript:alert(1)", f))
        assertNull(ModeloDocumentos.enlaceSeguro("", f))
    }
}
