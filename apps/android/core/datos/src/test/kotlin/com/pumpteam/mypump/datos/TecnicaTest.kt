package com.pumpteam.mypump.datos

import com.pumpteam.mypump.reglas.EnvioTecnica
import com.pumpteam.mypump.reglas.Tecnica
import java.io.File
import java.nio.file.Files
import java.util.UUID
import kotlinx.coroutines.runBlocking
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/** La cola y el recorrido contra el doble que sigue el contrato. Gemelo de TecnicaTests.swift. */
class TecnicaTest {
    private val token = "tk-prueba-tecnica"
    private fun raiz() = Files.createTempDirectory("tecnica").toFile()
    private fun armar(d: DobleTecnica, r: File = raiz(), t: String = token) = ModeloTecnica(ClienteRpc(transporte = d), t, Disco(r, t), esperar = {})
    private fun video(n: Int = 2048): File = File.createTempFile("video", ".mp4").apply { writeBytes(ByteArray(n) { 7 }) }
    private fun enDisco(r: File, t: String = token) = Disco(r, t).archivo(PendienteTecnica.CARPETA).list()?.size ?: 0

    @Test fun recorridoCompleto(): Unit = runBlocking {
        val d = DobleTecnica.escenario("vacio")
        val r = raiz()
        val m = armar(d, r)
        m.refrescar()
        assertTrue(m.habilitado)
        assertTrue(m.necesitaAviso)
        val v = video()
        assertEquals(ModeloTecnica.Encolar.OCUPADO, m.encolar(v, "s", "Remo", ""))   // el aviso va primero
        m.aceptarAviso()
        assertFalse(m.necesitaAviso)
        assertEquals(ModeloTecnica.Encolar.GUARDADO, m.encolar(v, "s", "Remo", "x".repeat(400)))
        assertEquals(1, enDisco(r))
        assertFalse(m.puedeMandar)
        m.drenar()
        assertNull(m.pendiente)
        assertEquals(0, enDisco(r))
        assertEquals(Tecnica.CONSENTIMIENTO_VIGENTE, d.ultimoNuevo?.get("p_consentimiento")?.comoTexto)
        assertEquals(300, d.ultimoNuevo?.get("p_nota")?.comoTexto?.length)
        assertEquals(listOf(2048L), d.bytesSubidos.toList())
        assertTrue(d.usoArchivo, "se sube desde el archivo")
        assertEquals(token, d.cabecerasUltimaSubida["x-tecnica-token"])
        assertEquals(EnvioTecnica.Estado.ENVIADO, m.envios.first().estado)
        assertFalse(m.puedeMandar)
    }

    @Test fun apagadoNoLlamaNiMuestra(): Unit = runBlocking {
        val d = DobleTecnica.escenario("sinServidor")
        val m = armar(d)
        m.refrescar()
        assertFalse(m.habilitado)
        val h = DobleTecnica.escenario("vacio").apply { habilitado = false }
        val m2 = armar(h)
        m2.refrescar()
        assertFalse(m2.habilitado)
        m2.drenar()
        assertEquals(0, h.intentosDeSubida)
        assertFalse(PalancaRemota.desde(com.pumpteam.mypump.modelos.ValorJson.objeto()).tecnicaVideo)
    }

    @Test fun corteNoPierdeNiDuplica(): Unit = runBlocking {
        val d = DobleTecnica.escenario("corte")
        val r = raiz()
        val m = armar(d, r)
        m.refrescar()
        assertEquals(ModeloTecnica.Encolar.GUARDADO, m.encolar(video(), "s", "Remo", ""))
        m.drenar()
        val abierto = m.pendiente?.envioId
        assertNotNull(abierto)
        assertEquals(1, enDisco(r))
        val m2 = armar(d, r)
        m2.refrescar()
        assertEquals(abierto, m2.pendiente?.envioId)
        m2.drenar()
        assertNull(m2.pendiente)
        assertEquals(1, d.envios.size)
        assertEquals("enviado", d.envios[0]["estado"]?.comoTexto)
    }

    @Test fun corteDespuesDeAbrirNoDuplica(): Unit = runBlocking {
        val d = DobleTecnica.escenario("vacio").apply { consentimientoAceptado = true; cortesEnNuevo = 1 }
        val m = armar(d)
        m.refrescar()
        m.encolar(video(), "s", "Remo", "")
        m.drenar()
        assertNull(m.pendiente?.envioId)
        m.drenar()
        assertNull(m.pendiente)
        assertEquals(1, d.envios.size)
    }

    @Test fun errorDelServidorNoGasta(): Unit = runBlocking {
        val d = DobleTecnica.escenario("reintento")
        val m = armar(d)
        m.refrescar()
        m.encolar(video(), "s", "Remo", "")
        m.drenar()
        assertEquals(3, d.intentosDeSubida)
        assertNull(m.pendiente)
        assertNull(m.aviso.value)
    }

    @Test fun tresSeguidosParaYGuarda(): Unit = runBlocking {
        val d = DobleTecnica.escenario("vacio").apply { consentimientoAceptado = true; proximasSubidas += listOf(503, 503, 503) }
        val r = raiz()
        val m = armar(d, r)
        m.refrescar()
        m.encolar(video(), "s", "Remo", "")
        m.drenar()
        assertEquals(3, d.intentosDeSubida)
        assertNotNull(m.pendiente)
        assertEquals(1, enDisco(r))
    }

    @Test fun rechazoDefinitivo(): Unit = runBlocking {
        val d = DobleTecnica.escenario("rechazo")
        val r = raiz()
        val m = armar(d, r)
        m.refrescar()
        m.encolar(video(), "s", "Remo", "")
        m.drenar()
        assertEquals(ModeloTecnica.Aviso.Rechazo(Tecnica.Rechazo.CORTO), m.aviso.value)
        assertNull(m.pendiente)
        assertEquals(0, enDisco(r))
        assertTrue("mypump_tecnica_cancelar" in d.llamadasTecnica)
        assertTrue(d.envios.isEmpty())
        assertTrue(m.puedeMandar)
    }

    @Test fun tokenCaidoGuarda(): Unit = runBlocking {
        val d = DobleTecnica.escenario("vacio").apply { consentimientoAceptado = true; proximasSubidas += 403 }
        val r = raiz()
        val m = armar(d, r)
        m.refrescar()
        m.encolar(video(), "s", "Remo", "")
        m.drenar()
        assertNotNull(m.pendiente)
        assertEquals(1, enDisco(r))
        assertEquals(1, d.intentosDeSubida)
    }

    @Test fun enCursoYTope(): Unit = runBlocking {
        val d = DobleTecnica.escenario("tope")
        val m = armar(d)
        m.refrescar()
        m.encolar(video(), "s", "Remo", "")
        m.drenar()
        assertEquals(ModeloTecnica.Aviso.TopeSemanal, m.aviso.value)
        assertNull(m.pendiente)
        val m2 = armar(DobleTecnica.escenario("enRevision"))
        m2.refrescar()
        assertFalse(m2.puedeMandar)
        assertEquals(ModeloTecnica.Encolar.OCUPADO, m2.encolar(video(), "s", "Remo", ""))
    }

    @Test fun cancelar(): Unit = runBlocking {
        val d = DobleTecnica.escenario("corte")
        val r = raiz()
        val m = armar(d, r)
        m.refrescar()
        m.encolar(video(), "s", "Remo", "")
        m.drenar()
        assertNotNull(m.pendiente?.envioId)
        assertTrue(m.cancelarPendiente())
        assertNull(m.pendiente)
        assertEquals(0, enDisco(r))
        assertTrue(d.envios.isEmpty())
    }

    @Test fun borradorNoSeMuestra(): Unit = runBlocking {
        val d = DobleTecnica.escenario("corte")
        val m = armar(d)
        m.refrescar()
        m.encolar(video(), "s", "Remo", "")
        m.drenar()
        m.refrescar()
        assertTrue(m.envios.isEmpty())
    }

    @Test fun publicadoSinRed(): Unit = runBlocking {
        val d = DobleTecnica.escenario("publicado")
        val r = raiz()
        val m = armar(d, r)
        m.refrescar()
        val dev = m.envios.first().devolucion
        assertEquals(3.5, dev?.correcciones?.first()?.momentoS)
        assertEquals("Lo revisó Mati", dev?.credito)
        assertTrue(m.puedeMandar)
        d.sinRed = true
        val m2 = armar(d, r)
        m2.refrescar()
        assertEquals(dev, m2.envios.first().devolucion)
    }

    @Test fun sacarVideoYUrl(): Unit = runBlocking {
        val d = DobleTecnica.escenario("publicado")
        val m = armar(d)
        m.refrescar()
        val id = m.envios[0].id
        assertNotNull(m.urlVideo(id))
        assertEquals(ModeloTecnica.Salida.OK, m.sacarVideo(id))
        assertFalse(m.envios[0].tieneVideo)
        d.sinRed = true
        assertEquals(ModeloTecnica.Salida.SIN_SENAL, m.sacarVideo(id))
    }

    @Test fun archivoQueDesaparecio(): Unit = runBlocking {
        val d = DobleTecnica.escenario("corte")
        val m = armar(d)
        m.refrescar()
        m.encolar(video(), "s", "Remo", "")
        m.drenar()
        m.url(m.pendiente!!.id).delete()
        m.drenar()
        assertNull(m.pendiente)
        assertEquals(ModeloTecnica.Aviso.Error, m.aviso.value)
    }

    @Test fun huerfanos() {
        val r = raiz()
        val c = Disco(r, token).archivo(PendienteTecnica.CARPETA)
        c.mkdirs()
        File(c, "suelto.mp4").writeBytes(byteArrayOf(1))
        armar(DobleTecnica.escenario("vacio"), r)
        assertEquals(0, enDisco(r))
    }

    @Test fun adoptaDeOtroLink(): Unit = runBlocking {
        val raiz = raiz()
        val d = DobleTecnica.escenario("corte")
        val viejo = armar(d, raiz, "tk-viejo-${UUID.randomUUID()}".take(20))
        viejo.refrescar()
        viejo.encolar(video(), "s", "Remo", "")
        viejo.drenar()
        val discoViejo = viejo.javaClass.getDeclaredField("disco").apply { isAccessible = true }.get(viejo) as Disco
        CuentasDelTelefono.anotar("cli", discoViejo)
        val nuevoT = "tk-nuevo"
        val nuevo = armar(d, raiz, nuevoT)
        assertTrue(CuentasDelTelefono.adoptarTecnica("cli", Disco(raiz, nuevoT), nuevo))
        nuevo.refrescar()
        nuevo.drenar()
        assertNull(nuevo.pendiente)
        assertEquals("enviado", d.envios[0]["estado"]?.comoTexto)
    }
}
