package com.pumpteam.mypump.datos

import com.pumpteam.mypump.modelos.ValorJson
import com.pumpteam.mypump.reglas.Estudios
import java.io.File
import java.nio.file.Files
import java.time.LocalDate
import kotlinx.coroutines.runBlocking
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/** La cola y el recorrido de «Estudios y órdenes» contra el doble que sigue el contrato. Sin red y con datos inventados. */
class EstudiosTest {
    private val token = "tk-prueba-estudios"
    private val pdf = DobleEstudios.pdfDePrueba()
    private val jpeg = DobleEstudios.JPEG_MINIMO
    private fun raiz(): File = Files.createTempDirectory("estudios").toFile()

    private class Armado(val m: ModeloEstudios, val raiz: File, val disco: Disco, val carpeta: File)

    private fun armar(d: DobleEstudios, r: File = raiz(), t: String = token): Armado {
        val disco = Disco(r, t)
        val carpeta = ColaEstudios.carpeta(File(r, "sin-respaldo"), disco)
        return Armado(ModeloEstudios(ClienteRpc(transporte = d), t, disco, carpeta, esperar = {}), r, disco, carpeta)
    }

    /** Los archivos como los deja la hoja de subida: temporales en una carpeta de caché. */
    private fun nuevos(r: File, vararg contenidos: Pair<ByteArray, String>): List<ModeloEstudios.Nuevo> {
        val cache = File(r, "cache").apply { mkdirs() }
        return contenidos.mapIndexed { i, (bytes, mime) -> ModeloEstudios.Nuevo(File(cache, "borrador-$i-${System.nanoTime()}").apply { writeBytes(bytes) }, mime) }
    }

    @Test fun recorridoCompleto(): Unit = runBlocking {
        val d = DobleEstudios.escenario("completo")
        val a = armar(d)
        val m = a.m
        m.refrescar()
        val e = m.estado.value!!
        assertEquals(3, e.pendientes.size)
        assertEquals("Te faltan 3 estudios", Estudios.subtitulo(e))
        val archivos = nuevos(a.raiz, pdf to Estudios.MIME_PDF, jpeg to Estudios.MIME_JPEG, jpeg + 9 to Estudios.MIME_JPEG)
        assertTrue(m.encolar(archivos, DobleEstudios.PEDIDO_LAB))
        assertTrue(archivos.none { it.archivo.exists() }, "los temporales de la hoja se borran al encolar")
        assertEquals(3, a.carpeta.listFiles()!!.size)
        assertNotNull(a.disco.leer(ColaEstudios.ARCHIVO))
        m.drenar()
        val envio = d.enviados.single()
        assertEquals(DobleEstudios.PEDIDO_LAB, envio.pedidoId)
        assertEquals(listOf(Estudios.MIME_PDF, Estudios.MIME_JPEG, Estudios.MIME_JPEG), envio.archivos.map { it.mime })
        assertTrue(pdf.contentEquals(envio.archivos[0].bytes))
        assertEquals(3, envio.archivos.map { it.id }.toSet().size)
        assertEquals(token, d.cabecerasUltimaSubida["x-estudios-token"])
        assertEquals(envio.id, d.cabecerasUltimaSubida["x-estudios-envio"])
        assertEquals(listOf("mypump_estudios_get", "mypump_estudios_envio_nuevo", "estudios/upload", "estudios/upload", "estudios/upload", "mypump_estudios_enviar", "mypump_estudios_get"), d.llamadasEstudios)
        // Al quedar enviado: sin cola, sin archivos locales y con el `get` refrescado.
        assertTrue(m.cola.value.isEmpty())
        assertTrue(a.carpeta.listFiles().isNullOrEmpty())
        assertNull(a.disco.leer(ColaEstudios.ARCHIVO))
        assertEquals(ModeloEstudios.Aviso.RECIBIDO, m.aviso.value)
        assertNull(m.progreso.value)
        assertEquals(1, m.estado.value!!.envios.size)
        assertEquals(3, m.estado.value!!.envios[0].archivos)
    }

    @Test fun palancaApagadaSinLaClave(): Unit = runBlocking {
        assertFalse(PalancaRemota.deFabrica.estudiosApp)
        assertFalse(PalancaRemota.desde(ValorJson.parsear("""{"gimnasio_fotos":true}""")).estudiosApp)
        assertFalse(PalancaRemota.desde(ValorJson.parsear("""{"estudios_app":"true"}""")).estudiosApp)
        assertTrue(PalancaRemota.desde(ValorJson.parsear("""{"estudios_app":true}""")).estudiosApp)
        val a = armar(DobleEstudios.escenario("vacio"))
        assertFalse(a.m.palancaRecordada)
        a.m.recordarPalanca(true)
        assertTrue(armar(DobleEstudios.escenario("vacio"), a.raiz).m.palancaRecordada)
    }

    @Test fun sinElServidorNuevoONoHabilitadoNoHayNada(): Unit = runBlocking {
        for (nombre in listOf("sinServidor", "noHabilitado")) {
            val a = armar(DobleEstudios.escenario(nombre))
            a.m.refrescar()
            assertNull(a.m.estado.value, nombre)
            assertFalse(a.m.errorCarga.value)
            assertFalse(a.m.encolar(nuevos(a.raiz, pdf to Estudios.MIME_PDF), null), "apagado no se encola nada")
        }
        val d = DobleEstudios.escenario("vacio").apply { tokenCaido = true }
        val a = armar(d)
        a.m.refrescar()
        assertNull(a.m.estado.value)
    }

    @Test fun seApagaSiDejaDeEstarHabilitado(): Unit = runBlocking {
        val d = DobleEstudios.escenario("completo")
        val a = armar(d)
        a.m.refrescar()
        assertNotNull(a.disco.leer(ModeloEstudios.ARCHIVO_ESTADO))
        d.habilitado = false
        a.m.refrescar()
        assertNull(a.m.estado.value)
        assertNull(a.disco.leer(ModeloEstudios.ARCHIVO_ESTADO), "lo guardado se borra al apagarse")
    }

    @Test fun sinRedMuestraLoUltimoQueSeSupo(): Unit = runBlocking {
        val d = DobleEstudios.escenario("completo")
        val a = armar(d)
        a.m.refrescar()
        d.sinRed = true
        val otra = armar(d, a.raiz)
        otra.m.refrescar()
        assertEquals(3, otra.m.estado.value?.pendientes?.size)
        assertTrue(otra.m.errorCarga.value)
        d.sinRed = false
        otra.m.refrescar()
        assertFalse(otra.m.errorCarga.value)
        // Sin nada guardado y sin red, no hay sección.
        d.sinRed = true
        val nueva = armar(d)
        nueva.m.refrescar()
        assertNull(nueva.m.estado.value)
        assertFalse(nueva.m.errorCarga.value)
    }

    @Test fun corteDeRedYReanudaAlReabrir(): Unit = runBlocking {
        val d = DobleEstudios.escenario("corte")
        val a = armar(d)
        a.m.refrescar()
        a.m.encolar(nuevos(a.raiz, pdf to Estudios.MIME_PDF, jpeg to Estudios.MIME_JPEG), null)
        a.m.drenar()
        assertTrue(a.m.sinSenal.value)
        assertEquals(1, d.envios.single().archivos.size)
        assertTrue(d.enviados.isEmpty())
        assertEquals(listOf(true, false), a.m.cola.value.single().archivos.map { it.subido })
        assertEquals(2, a.carpeta.listFiles()!!.size, "nada se borra hasta que queda enviado")
        // Se cierra la app y se abre: sale sola, sin duplicar el envío ni el archivo que ya estaba.
        val b = armar(d, a.raiz)
        assertEquals(1, b.m.cola.value.size)
        b.m.refrescar()
        b.m.drenar()
        assertFalse(b.m.sinSenal.value)
        assertEquals(1, d.envios.size)
        assertEquals(2, d.enviados.single().archivos.size)
        assertEquals(1, d.llamadas.count { it == "mypump_estudios_envio_nuevo" })
        assertTrue(b.carpeta.listFiles().isNullOrEmpty())
        assertEquals(ModeloEstudios.Aviso.RECIBIDO, b.m.aviso.value)
    }

    @Test fun sinRedDesdeElPrincipioQuedaTodoGuardado(): Unit = runBlocking {
        val d = DobleEstudios.escenario("vacio")
        val a = armar(d)
        a.m.refrescar()
        d.sinRed = true
        a.m.encolar(nuevos(a.raiz, pdf to Estudios.MIME_PDF), null)
        a.m.drenar()
        assertTrue(a.m.sinSenal.value)
        assertFalse(a.m.cola.value.single().creado)
        assertTrue(d.envios.isEmpty())
        d.sinRed = false
        a.m.drenar()
        assertEquals(1, d.enviados.size)
    }

    @Test fun reintentaUn503SinGastarElArchivo(): Unit = runBlocking {
        val d = DobleEstudios.escenario("reintento")
        val a = armar(d)
        a.m.refrescar()
        a.m.encolar(nuevos(a.raiz, pdf to Estudios.MIME_PDF), null)
        a.m.drenar()
        assertEquals(2, d.intentosDeSubida)
        assertEquals(1, d.enviados.single().archivos.size)
        assertEquals(ModeloEstudios.Aviso.RECIBIDO, a.m.aviso.value)
    }

    @Test fun tresFallasSeguidasCortanLaPasadaYNoPierdenNada(): Unit = runBlocking {
        val d = DobleEstudios.escenario("vacio").apply { proximasSubidas.addAll(listOf(503, 429, 500)) }
        val a = armar(d)
        a.m.refrescar()
        a.m.encolar(nuevos(a.raiz, pdf to Estudios.MIME_PDF), null)
        a.m.drenar()
        assertEquals(3, d.intentosDeSubida)
        assertEquals(1, a.m.cola.value.size)
        assertEquals(1, a.carpeta.listFiles()!!.size)
        assertNull(a.m.aviso.value)
        a.m.drenar()
        assertEquals(1, d.enviados.size)
    }

    @Test fun unArchivoRechazadoSeSacaYElRestoSigue(): Unit = runBlocking {
        val d = DobleEstudios.escenario("rechazo")
        val a = armar(d)
        a.m.refrescar()
        a.m.encolar(nuevos(a.raiz, pdf to Estudios.MIME_PDF, jpeg to Estudios.MIME_JPEG), null)
        a.m.drenar()
        assertEquals(1, d.enviados.single().archivos.size)
        assertEquals(Estudios.MIME_JPEG, d.enviados.single().archivos[0].mime)
        assertEquals(ModeloEstudios.Aviso.RECIBIDO_CON_RECHAZO, a.m.aviso.value)
        assertTrue(a.carpeta.listFiles().isNullOrEmpty())
    }

    @Test fun siNoQuedaNingunoElEnvioSeDescarta(): Unit = runBlocking {
        val d = DobleEstudios.escenario("rechazo")
        val a = armar(d)
        a.m.refrescar()
        a.m.encolar(nuevos(a.raiz, pdf to Estudios.MIME_PDF), null)
        a.m.drenar()
        assertTrue(d.enviados.isEmpty())
        assertEquals(0, d.llamadas.count { it == "mypump_estudios_enviar" })
        assertTrue(a.m.cola.value.isEmpty())
        assertTrue(a.carpeta.listFiles().isNullOrEmpty())
        assertEquals(ModeloEstudios.Aviso.RECHAZADO, a.m.aviso.value)
    }

    @Test fun elServidorRechazaLoQueNoEsPdfNiJpeg(): Unit = runBlocking {
        val d = DobleEstudios.escenario("vacio")
        val a = armar(d)
        a.m.refrescar()
        a.m.encolar(nuevos(a.raiz, "no soy un pdf".toByteArray() to Estudios.MIME_PDF), null)
        a.m.drenar()
        assertEquals(ModeloEstudios.Aviso.RECHAZADO, a.m.aviso.value)
        assertTrue(a.m.cola.value.isEmpty())
    }

    @Test fun topeDelDia(): Unit = runBlocking {
        val d = DobleEstudios.escenario("topeDia")
        val a = armar(d)
        a.m.refrescar()
        a.m.encolar(nuevos(a.raiz, pdf to Estudios.MIME_PDF), null)
        a.m.drenar()
        assertEquals(ModeloEstudios.Aviso.TOPE_DIA, a.m.aviso.value)
        assertTrue(a.m.cola.value.isEmpty())
        assertTrue(a.carpeta.listFiles().isNullOrEmpty())
        assertEquals(0, d.intentosDeSubida)
    }

    @Test fun faltanArchivosVuelveASubirYReintenta(): Unit = runBlocking {
        val d = DobleEstudios.escenario("vacio").apply { faltanVeces = 1 }
        val a = armar(d)
        a.m.refrescar()
        a.m.encolar(nuevos(a.raiz, pdf to Estudios.MIME_PDF, jpeg to Estudios.MIME_JPEG), null)
        a.m.drenar()
        assertEquals(2, d.enviados.single().archivos.size, "los que ya estaban contestan `ya`: no se duplican")
        assertEquals(4, d.intentosDeSubida)
        assertEquals(2, d.llamadas.count { it == "mypump_estudios_enviar" })
        assertEquals(ModeloEstudios.Aviso.RECIBIDO, a.m.aviso.value)
    }

    @Test fun faltanArchivosSinFinNoGiraParaSiempre(): Unit = runBlocking {
        val d = DobleEstudios.escenario("vacio").apply { faltanVeces = 50 }
        val a = armar(d)
        a.m.refrescar()
        a.m.encolar(nuevos(a.raiz, pdf to Estudios.MIME_PDF), null)
        a.m.drenar()
        assertEquals(3, d.llamadas.count { it == "mypump_estudios_enviar" })
        assertEquals(1, a.m.cola.value.size, "queda guardado para más tarde")
        assertEquals(1, a.carpeta.listFiles()!!.size)
    }

    @Test fun tokenCaidoDejaTodoGuardadoParaElLinkNuevo(): Unit = runBlocking {
        val d = DobleEstudios.escenario("vacio")
        val a = armar(d)
        a.m.refrescar()
        a.m.encolar(nuevos(a.raiz, pdf to Estudios.MIME_PDF), null)
        d.tokenCaido = true
        a.m.drenar()
        assertEquals(1, a.m.cola.value.size)
        assertEquals(1, a.carpeta.listFiles()!!.size)
        assertNull(a.m.aviso.value)
    }

    @Test fun elLinkNuevoAdoptaLoQueQuedoEnElViejo(): Unit = runBlocking {
        val d = DobleEstudios.escenario("vacio")
        val r = raiz()
        val viejo = armar(d, r, "tk-link-viejo")
        viejo.m.refrescar()
        d.sinRed = true
        viejo.m.encolar(nuevos(r, pdf to Estudios.MIME_PDF, jpeg to Estudios.MIME_JPEG), null)
        viejo.m.drenar()
        d.sinRed = false
        val nuevo = armar(d, r, "tk-link-nuevo")
        CuentasDelTelefono.anotar("cliente-1", viejo.disco)
        CuentasDelTelefono.anotar("cliente-1", nuevo.disco)
        assertEquals(1, CuentasDelTelefono.adoptarEstudios("cliente-1", nuevo.disco, nuevo.m))
        assertEquals(2, nuevo.carpeta.listFiles()!!.size)
        assertFalse(viejo.carpeta.exists())
        assertNull(viejo.disco.leer(ColaEstudios.ARCHIVO))
        nuevo.m.refrescar()
        nuevo.m.drenar()
        assertEquals(2, d.enviados.single().archivos.size)
        assertEquals("tk-link-nuevo", d.cabecerasUltimaSubida["x-estudios-token"])
        // De otra persona no se adopta nada.
        val ajeno = armar(d, r, "tk-otra-persona")
        ajeno.m.refrescar()
        d.sinRed = true
        ajeno.m.encolar(nuevos(r, pdf to Estudios.MIME_PDF), null)
        CuentasDelTelefono.anotar("cliente-2", ajeno.disco)
        assertEquals(0, CuentasDelTelefono.adoptarEstudios("cliente-1", nuevo.disco, nuevo.m))
        assertEquals(1, ajeno.carpeta.listFiles()!!.size)
    }

    @Test fun seBarrenLosArchivosHuerfanos(): Unit = runBlocking {
        val d = DobleEstudios.escenario("vacio")
        val a = armar(d)
        a.m.refrescar()
        d.sinRed = true
        a.m.encolar(nuevos(a.raiz, pdf to Estudios.MIME_PDF), null)
        val vivo = a.carpeta.listFiles()!!.single()
        val huerfano = File(a.carpeta, "huerfano.pdf").apply { writeBytes(pdf) }
        armar(d, a.raiz)
        assertFalse(huerfano.exists())
        assertTrue(vivo.exists())
    }

    @Test fun yaMeLoHiceYDeshacer(): Unit = runBlocking {
        val d = DobleEstudios.escenario("completo")
        val a = armar(d)
        a.m.refrescar()
        assertEquals(ModeloEstudios.Salida.OK, a.m.marcarHecho(DobleEstudios.PEDIDO_LAB, LocalDate.parse("2026-11-09")))
        assertEquals("2026-11-09", d.ultimoHecho?.get("p_fecha")?.comoTexto)
        val p = a.m.estado.value!!.pendientes.first { it.id == DobleEstudios.PEDIDO_LAB }
        assertTrue(p.hecho)
        assertEquals(LocalDate.parse("2026-11-09"), p.hechoFecha)
        assertEquals(ModeloEstudios.Salida.FECHA, a.m.marcarHecho(DobleEstudios.PEDIDO_LAB, LocalDate.parse("2026-01-01")))
        assertEquals(ModeloEstudios.Salida.OK, a.m.marcarHecho(DobleEstudios.PEDIDO_LAB, null))
        assertEquals(ValorJson.Nulo, d.ultimoHecho?.get("p_fecha"))
        assertFalse(a.m.estado.value!!.pendientes.first { it.id == DobleEstudios.PEDIDO_LAB }.hecho)
        assertEquals(ModeloEstudios.Salida.ERROR, a.m.marcarHecho("no-existe", LocalDate.parse("2026-11-09")))
        d.sinRed = true
        assertEquals(ModeloEstudios.Salida.SIN_SENAL, a.m.marcarHecho(DobleEstudios.PEDIDO_LAB, LocalDate.parse("2026-11-09")))
    }

    @Test fun abrirUnaOrdenYUnEstudioPropio(): Unit = runBlocking {
        val d = DobleEstudios.escenario("completo")
        val a = armar(d)
        a.m.refrescar()
        val orden = a.m.urls("orden", DobleEstudios.ORDEN_LAB) as ModeloEstudios.Apertura.Ok
        assertEquals(token, d.ultimoUrls?.get("token")?.comoTexto)
        assertEquals(Estudios.MIME_PDF, orden.archivos.single().mime)
        val destino = File(a.raiz, "ver/orden.pdf")
        assertTrue(a.m.bajar(orden.archivos.single(), destino))
        assertTrue(Estudios.esPdf(destino.readBytes()))
        assertEquals(ModeloEstudios.Apertura.Error, a.m.urls("orden", DobleEstudios.ORDEN_VENCIDA))
        assertEquals(ModeloEstudios.Apertura.TodaviaNo, a.m.urls("estudio", DobleEstudios.ESTUDIO_RECIBIDO))
        assertEquals(2, (a.m.urls("estudio", DobleEstudios.ESTUDIO_VISTO) as ModeloEstudios.Apertura.Ok).archivos.size)
        d.sinRed = true
        assertEquals(ModeloEstudios.Apertura.Error, a.m.urls("orden", DobleEstudios.ORDEN_LAB))
        assertFalse(a.m.bajar(orden.archivos.single(), File(a.raiz, "ver/otra.pdf")))
    }

    @Test fun elPdfDePruebaEstaBienArmado() {
        val texto = String(DobleEstudios.pdfDePrueba(2), Charsets.US_ASCII)
        assertTrue(texto.startsWith("%PDF-1.4"))
        val xref = texto.substringAfter("startxref\n").substringBefore("\n").toInt()
        assertTrue(texto.substring(xref).startsWith("xref"))
        assertEquals(2, Regex("/Type /Page ").findAll(texto).count())
    }
}
