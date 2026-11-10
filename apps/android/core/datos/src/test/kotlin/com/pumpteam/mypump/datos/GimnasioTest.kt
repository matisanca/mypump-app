package com.pumpteam.mypump.datos

import com.pumpteam.mypump.modelos.ValorJson
import com.pumpteam.mypump.reglas.Gimnasio
import java.nio.file.Files
import kotlinx.coroutines.runBlocking
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/** La cola y el recorrido contra el doble que sigue el contrato. Gemelo de GimnasioTests.swift. */
class GimnasioTest {
    private val jpeg = byteArrayOf(0xFF.toByte(), 0xD8.toByte(), 0xFF.toByte(), 0xE0.toByte(), 1, 2, 3)
    private val token = "tk-prueba-gimnasio"
    private fun raiz() = Files.createTempDirectory("gimnasio").toFile()
    private fun armar(d: DobleGimnasio, r: java.io.File = raiz()) = ModeloGimnasio(ClienteRpc(transporte = d), token, Disco(r, token), esperar = {})

    @Test fun recorridoCompleto(): Unit = runBlocking {
        val d = DobleGimnasio.escenario("vacio")
        val m = armar(d)
        m.refrescar()
        assertTrue(m.tarjetaVisible)
        assertFalse(m.entradaVisible)
        assertEquals(Gimnasio.Pantalla.INICIO, m.pantalla)
        assertTrue(m.necesitaAviso)
        assertEquals(ModeloGimnasio.Salida.OK, m.empezar())
        assertFalse(m.necesitaAviso)
        assertEquals(9, m.faltantes.size)
        for (z in Gimnasio.zonas.map { it.clave }.filter { it != "otros" && it != "bancos" }) assertEquals(ModeloGimnasio.Foto.GUARDADA, m.agregar(z, jpeg))
        m.marcarNoHay("bancos", true)
        assertTrue(m.faltantes.isEmpty())
        assertTrue(m.puedeEnviar)
        m.fijarNota("x".repeat(400))
        assertEquals(300, m.borrador.value.nota.length)
        m.enviarCarga()
        assertEquals(8, d.fotos.size)
        assertTrue(m.cola.value.isEmpty())
        assertEquals(Gimnasio.Pantalla.RECIBIDO, m.pantalla)
        assertNull(m.borrador.value.envio)
        assertEquals("terceros-v1", d.ultimoEnviar?.get("p_consentimiento")?.comoTexto)
        assertEquals(token, d.cabecerasUltimaSubida["x-gimnasio-token"])
        assertTrue(jpeg.contentEquals(d.fotos[0].bytes))
    }

    @Test fun corteDeRedAMitadYReanuda(): Unit = runBlocking {
        val d = DobleGimnasio.escenario("borrador")
        val r = raiz()
        val m = armar(d, r)
        m.refrescar()
        for (z in listOf("poleas", "piernas", "empuje")) m.agregar(z, jpeg)
        d.proximasSubidas.addAll(listOf(200, 0))
        m.enviarCarga()
        assertEquals(1, d.fotos.size)
        assertEquals(2, m.cola.value.size)
        assertNotNull(m.borrador.value.envio)
        val m2 = armar(d, r)
        assertEquals(2, m2.cola.value.size)
        assertNotNull(m2.borrador.value.envio)
        m2.refrescar()
        d.sinRed = true
        m2.drenar()
        assertEquals(2, m2.cola.value.size)
        d.sinRed = false
        for (z in listOf("accesorios_polea", "tiron", "barras_racks", "discos", "mancuernas", "bancos")) m2.marcarNoHay(z, true)
        m2.enviarCarga()
        assertEquals(3, d.fotos.size)
        assertTrue(m2.cola.value.isEmpty())
        assertEquals(Gimnasio.Pantalla.RECIBIDO, m2.pantalla)
    }

    @Test fun cincoCeroTresNoPierdeLaFotoYSeReintenta(): Unit = runBlocking {
        val d = DobleGimnasio.escenario("borrador")
        val m = armar(d)
        m.refrescar()
        m.agregar("poleas", jpeg)
        d.proximasSubidas.addAll(listOf(503, 429, 502, 200))
        m.drenar()
        assertEquals(1, m.cola.value.size)
        m.drenar()
        assertTrue(m.cola.value.isEmpty())
        assertEquals(1, d.fotos.size)
        assertEquals(4, d.intentosDeSubida)
    }

    @Test fun fotoRechazadaAvisaYSigue(): Unit = runBlocking {
        val d = DobleGimnasio.escenario("borrador")
        val m = armar(d)
        m.refrescar()
        m.agregar("poleas", jpeg)
        m.agregar("piernas", jpeg)
        d.proximasSubidas.add(400)
        m.drenar()
        assertEquals(Gimnasio.AvisoFoto.RECHAZADA, m.avisoFoto.value)
        assertTrue(m.cola.value.isEmpty())
        assertEquals(listOf("piernas"), d.fotos.map { it.zona })
    }

    @Test fun topeDeOchenta(): Unit = runBlocking {
        val d = DobleGimnasio.escenario("borrador")
        val m = armar(d)
        m.refrescar()
        repeat(80) { assertEquals(ModeloGimnasio.Foto.GUARDADA, m.agregar("otros", jpeg)) }
        assertEquals(ModeloGimnasio.Foto.TOPE, m.agregar("otros", jpeg))
        assertEquals(Gimnasio.AvisoFoto.TOPE, m.avisoFoto.value)
    }

    @Test fun conflictoDescartaYRefresca(): Unit = runBlocking {
        val d = DobleGimnasio.escenario("borrador")
        val m = armar(d)
        m.refrescar()
        m.agregar("poleas", jpeg)
        d.proximasSubidas.add(409)
        m.drenar()
        assertTrue(m.cola.value.isEmpty())
        assertEquals(2, d.llamadas.count { it == "mypump_gimnasio_get" })
    }

    @Test fun faltanFotosAlEnviar(): Unit = runBlocking {
        val d = DobleGimnasio.escenario("borrador")
        val m = armar(d)
        m.refrescar()
        m.agregar("poleas", jpeg)
        m.enviarCarga()
        assertEquals(8, (m.avisoEnvio.value as ModeloGimnasio.AvisoEnvio.Faltan).zonas.size)
        assertNull(m.borrador.value.envio)
    }

    @Test fun preguntasConFotoVanDespuesDeLaFoto(): Unit = runBlocking {
        val d = DobleGimnasio.escenario("preguntas")
        val m = armar(d)
        m.refrescar()
        assertEquals(Gimnasio.Pantalla.PREGUNTAS, m.pantalla)
        val ps = m.abierta!!.preguntas
        assertEquals(6, ps.size)
        assertEquals(1, Gimnasio.fotosPedidas(ps, m.borrador.value.respuestas))
        m.responder("remo", ValorJson.Lista(listOf(ValorJson.Texto("remo_t"))))
        m.responder("peso_mancuernas", ValorJson.Numero(50.0))
        m.agregar("bancos", jpeg, "foto_1")
        d.sinRed = true
        m.enviarRespuestas()
        assertNotNull(m.borrador.value.envio)
        d.sinRed = false
        m.drenar()
        assertEquals(1, d.fotos.size)
        assertEquals("subida", d.ultimoResponder?.get("foto_1")?.comoTexto)
        assertNull(d.ultimoResponder?.get("peso_discos"))
        assertEquals(Gimnasio.Pantalla.RECIBIDO, m.pantalla)
    }

    @Test fun listoYParcial(): Unit = runBlocking {
        val d = DobleGimnasio.escenario("listo")
        val m = armar(d)
        m.refrescar()
        assertEquals(Gimnasio.Pantalla.LISTO, m.pantalla)
        assertFalse(m.tarjetaVisible)
        assertTrue(m.entradaVisible)
        assertEquals(ModeloGimnasio.Salida.OK, m.empezar("parcial"))
        assertEquals("parcial", m.abierta?.modo)
        assertFalse(m.puedeEnviar)
        m.alternarQuitar("prensa_45")
        assertTrue(m.puedeEnviar)
        m.enviarCarga()
        assertEquals(ValorJson.Lista(listOf(ValorJson.Texto("prensa_45"))), d.ultimoEnviar?.get("p_quitar"))
    }

    @Test fun apagadoNoMuestraNada(): Unit = runBlocking {
        val m = armar(DobleGimnasio.escenario("sinServidor"))
        m.refrescar()
        assertNull(m.estado.value)
        val d = DobleGimnasio.escenario("vacio").also { it.habilitado = false }
        val m2 = armar(d)
        m2.refrescar()
        assertNull(m2.estado.value)
    }

    @Test fun sinRedLaPrimeraVezNoMuestraYDespuesUsaLoGuardado(): Unit = runBlocking {
        val d = DobleGimnasio.escenario("borrador")
        d.sinRed = true
        val r = raiz()
        val m = armar(d, r)
        m.refrescar()
        assertNull(m.estado.value)
        d.sinRed = false
        m.refrescar()
        assertNotNull(m.estado.value)
        d.sinRed = true
        val m2 = armar(d, r)
        m2.refrescar()
        assertEquals(Gimnasio.Pantalla.ZONAS, m2.pantalla)
    }

    @Test fun borrarFotoPendienteYSubida(): Unit = runBlocking {
        val d = DobleGimnasio.escenario("borrador")
        val m = armar(d)
        m.refrescar()
        m.agregar("poleas", jpeg)
        assertEquals(ModeloGimnasio.Salida.OK, m.borrarFoto(m.cola.value[0].id))
        assertTrue(m.cola.value.isEmpty())
        m.agregar("poleas", jpeg)
        m.drenar()
        assertEquals(ModeloGimnasio.Salida.OK, m.borrarFoto(d.fotos[0].id))
        assertTrue(d.fotos.isEmpty())
        assertTrue(m.fotos("poleas").isEmpty())
    }

    @Test fun noHaySeSacaAlSumarFoto(): Unit = runBlocking {
        val d = DobleGimnasio.escenario("borrador")
        val m = armar(d)
        m.refrescar()
        m.marcarNoHay("poleas", true)
        assertEquals(setOf("poleas"), m.noHay)
        m.agregar("poleas", jpeg)
        assertTrue(m.noHay.isEmpty())
    }

    @Test fun palancaApagadaNoLlamaNadaNuevo(): Unit = runBlocking {
        val j = ValorJson.desde(kotlinx.serialization.json.Json.parseToJsonElement("""{"gimnasio_fotos":false}"""))
        assertFalse(PalancaRemota.desde(j).gimnasioFotos)
        assertFalse(PalancaRemota.deFabrica.gimnasioFotos)
        val d = DobleGimnasio.escenario("apagado")
        val m = armar(d)
        assertFalse(m.palancaRecordada)
        assertTrue(d.llamadasGimnasio.isEmpty())
    }
}
