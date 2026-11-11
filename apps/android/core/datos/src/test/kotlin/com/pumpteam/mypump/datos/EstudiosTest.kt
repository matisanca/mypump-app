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
    }

    @Test fun sinLeerLaPalancaEnEstaSesionNoSeLlamaANada(): Unit = runBlocking {
        val d = DobleEstudios.escenario("completo")
        val a = armar(d)
        assertNull(a.m.palanca.value)
        a.m.sincronizar()
        assertNull(a.m.estado.value)
        assertTrue(d.llamadas.isEmpty(), "sin una lectura fresca de la palanca no sale nada")
        a.m.usarPalanca(true)
        a.m.sincronizar()
        assertNotNull(a.m.estado.value)
        // No se recuerda de una vez para la otra: otra sesión empieza sin saber.
        val otra = armar(d, a.raiz)
        assertNull(otra.m.palanca.value)
        assertFalse(File(a.disco.carpeta, "estudios-palanca.json").exists())
        // Apagada, la sección deja de existir en el momento y lo que estaba programado no sale.
        a.m.encolar(nuevos(a.raiz, pdf to Estudios.MIME_PDF), null)
        a.m.usarPalanca(false)
        assertNull(a.m.estado.value)
        val antes = d.llamadas.size
        a.m.drenar()
        a.m.sincronizar()
        assertEquals(antes, d.llamadas.size)
        assertEquals(1, a.m.cola.value.size, "lo encolado espera")
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
        assertNotNull(a.m.estado.value)
        d.habilitado = false
        a.m.refrescar()
        assertNull(a.m.estado.value)
    }

    @Test fun elEstadoDelServidorNoSeGuardaEnElTelefono(): Unit = runBlocking {
        val d = DobleEstudios.escenario("completo")
        val r = raiz()
        // Una versión anterior lo guardaba: al arrancar se borra.
        val viejo = Disco(r, token)
        viejo.guardar("estudios-estado.json", ValorJson.parsear("""{"habilitado":true,"estudios":[{"id":"e1","titulo":"Análisis de laboratorio"}]}"""))
        viejo.guardar("estudios-palanca.json", ValorJson.Booleano(true))
        val a = armar(d, r)
        assertFalse(File(a.disco.carpeta, "estudios-estado.json").exists())
        assertFalse(File(a.disco.carpeta, "estudios-palanca.json").exists())
        a.m.refrescar()
        assertEquals(3, a.m.estado.value?.pendientes?.size)
        val enDisco = a.disco.carpeta.listFiles().orEmpty().map { it.name }
        assertTrue(enDisco.none { "estado" in it }, "nada del `get` queda en disco: $enDisco")
        // Token caído (link regenerado, baja): no se muestra nada de lo que se veía.
        d.tokenCaido = true
        a.m.refrescar()
        assertNull(a.m.estado.value)
        assertFalse(a.m.errorCarga.value)
    }

    @Test fun sinRedSeQuedaConLoQueSeVeiaEnEstaSesion(): Unit = runBlocking {
        val d = DobleEstudios.escenario("completo")
        val a = armar(d)
        a.m.refrescar()
        d.sinRed = true
        a.m.refrescar()
        assertEquals(3, a.m.estado.value?.pendientes?.size)
        assertTrue(a.m.errorCarga.value)
        d.sinRed = false
        a.m.refrescar()
        assertFalse(a.m.errorCarga.value)
        // Otra sesión sin red: no hay nada guardado, no hay sección.
        d.sinRed = true
        val otra = armar(d, a.raiz)
        otra.m.refrescar()
        assertNull(otra.m.estado.value)
        assertFalse(otra.m.errorCarga.value)
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

    // ── Los códigos de `POST /estudios/upload`, uno por uno ──

    /** Un envío de dos archivos listo para salir, con [codigos] como próximas respuestas forzadas de la subida. */
    private suspend fun conDosArchivos(vararg codigos: Int): Pair<DobleEstudios, Armado> {
        val d = DobleEstudios.escenario("vacio")
        val a = armar(d)
        a.m.refrescar()
        assertTrue(a.m.encolar(nuevos(a.raiz, pdf to Estudios.MIME_PDF, jpeg to Estudios.MIME_JPEG), null))
        d.proximasSubidas.addAll(codigos.toList())
        return d to a
    }

    private suspend fun elLinkOLaFuncionNoGastanElArchivo(codigo: Int) {
        val (d, a) = conDosArchivos(codigo)
        a.m.drenar()
        assertEquals(1, d.intentosDeSubida, "no insiste con el segundo archivo")
        assertEquals(2, a.m.cola.value.single().archivos.size)
        assertEquals(0, a.m.cola.value.single().rechazados)
        assertEquals(2, a.carpeta.listFiles()!!.size)
        assertNull(a.m.aviso.value)
        assertNull(a.m.progreso.value)
        assertFalse(a.m.sinSenal.value)
        assertEquals(2, ColaEstudios.leer(a.disco).single().archivos.size, "también en disco")
        a.m.drenar()   // con el link o la función de vuelta, la próxima pasada sale entera y con los mismos ids
        assertTrue(a.m.cola.value.isEmpty())
        assertEquals(2, d.enviados.single().archivos.size)
        assertEquals(ModeloEstudios.Aviso.RECIBIDO, a.m.aviso.value)
    }

    @Test fun subida401LinkRegeneradoConservaLaCola(): Unit = runBlocking { elLinkOLaFuncionNoGastanElArchivo(401) }

    @Test fun subida403SinLaFuncionConservaLaCola(): Unit = runBlocking { elLinkOLaFuncionNoGastanElArchivo(403) }

    @Test fun subida404ReabreElEnvioYSubeTodoDeNuevo(): Unit = runBlocking {
        val (d, a) = conDosArchivos(200, 404)
        a.m.drenar()
        assertEquals(2, d.llamadas.count { it == "mypump_estudios_envio_nuevo" })
        assertEquals(4, d.intentosDeSubida, "el que ya estaba contesta `ya`")
        assertEquals(1, d.envios.size)
        assertEquals(2, d.enviados.single().archivos.size)
        assertTrue(a.m.cola.value.isEmpty())
        assertEquals(ModeloEstudios.Aviso.RECIBIDO, a.m.aviso.value)
    }

    @Test fun subida404SinFinNoGiraNiPierdeNada(): Unit = runBlocking {
        val (d, a) = conDosArchivos(404, 404, 404, 404, 404, 404)
        a.m.drenar()
        assertEquals(ModeloEstudios.MAX_VUELTAS + 1, d.intentosDeSubida)
        assertEquals(2, a.m.cola.value.single().archivos.size, "queda guardado para más tarde")
        assertEquals(2, a.carpeta.listFiles()!!.size)
        assertNull(a.m.aviso.value)
    }

    @Test fun subida409EnvioYaEnviadoSeConfirmaYTermina(): Unit = runBlocking {
        val (d, a) = conDosArchivos(200, 0)   // sube uno y se corta
        a.m.drenar()
        assertTrue(a.m.sinSenal.value)
        d.envios.single().estado = "enviado"   // el servidor lo dio por enviado: ya no recibe
        a.m.drenar()
        assertEquals(3, d.intentosDeSubida, "un solo intento más: el 409")
        assertEquals(1, d.llamadas.count { it == "mypump_estudios_enviar" })
        assertTrue(a.m.cola.value.isEmpty())
        assertTrue(a.carpeta.listFiles().isNullOrEmpty())
        assertEquals(ModeloEstudios.Aviso.RECIBIDO, a.m.aviso.value)
    }

    @Test fun subida409SinConfirmarNoGiraNiGastaReintentos(): Unit = runBlocking {
        val (d, a) = conDosArchivos(409)
        a.m.drenar()
        assertEquals(1, d.intentosDeSubida)
        assertEquals(1, d.llamadas.count { it == "mypump_estudios_enviar" })
        assertTrue(d.enviados.isEmpty())
        assertTrue(a.m.cola.value.isEmpty())
        assertTrue(a.carpeta.listFiles().isNullOrEmpty())
        assertEquals(ModeloEstudios.Aviso.ERROR, a.m.aviso.value)
    }

    @Test fun subidaElRestoDeLos4xxEsDefinitivoParaEseArchivo(): Unit = runBlocking {
        for (codigo in listOf(400, 411, 413, 415, 422)) {
            val (d, a) = conDosArchivos(codigo)
            a.m.drenar()
            assertEquals(2, d.intentosDeSubida, "$codigo: no se reintenta")
            assertEquals(Estudios.MIME_JPEG, d.enviados.single().archivos.single().mime, "$codigo: el otro sigue")
            assertTrue(a.m.cola.value.isEmpty(), "$codigo")
            assertTrue(a.carpeta.listFiles().isNullOrEmpty(), "$codigo")
            assertEquals(ModeloEstudios.Aviso.RECIBIDO_CON_RECHAZO, a.m.aviso.value, "$codigo")
        }
    }

    @Test fun subida429Y5xxReintentanConElMismoId(): Unit = runBlocking {
        for (codigo in listOf(429, 500, 502, 503, 504)) {
            val (d, a) = conDosArchivos(codigo)
            val ids = a.m.cola.value.single().archivos.map { it.id }
            a.m.drenar()
            assertEquals(3, d.intentosDeSubida, "$codigo: el mismo archivo va de nuevo")
            assertEquals(ids, d.enviados.single().archivos.map { it.id }, "$codigo: con el mismo id")
            assertEquals(a.m.cola.value, emptyList<EnvioEstudios>(), "$codigo")
            assertEquals(ModeloEstudios.Aviso.RECIBIDO, a.m.aviso.value, "$codigo")
        }
    }

    @Test fun subidaSinRedConservaTodoYReintentaConElMismoId(): Unit = runBlocking {
        val (d, a) = conDosArchivos(0)
        val ids = a.m.cola.value.single().archivos.map { it.id }
        a.m.drenar()
        assertTrue(a.m.sinSenal.value)
        assertEquals(2, a.carpeta.listFiles()!!.size)
        assertNull(a.m.aviso.value)
        a.m.drenar()
        assertEquals(ids, d.enviados.single().archivos.map { it.id })
        assertFalse(a.m.sinSenal.value)
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
        // `no_encontrado`: ya llegó el resultado o lo cerraron. Vale lo del servidor (como iOS).
        val gets = d.llamadas.count { it == "mypump_estudios_get" }
        assertEquals(ModeloEstudios.Salida.OK, a.m.marcarHecho("no-existe", LocalDate.parse("2026-11-09")))
        assertEquals(gets + 1, d.llamadas.count { it == "mypump_estudios_get" })
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

    // ── Lo que no se queda en el teléfono ──

    private val dia = 86_400_000L

    @Test fun unEnvioQueNoSalioEnDosSemanasSeBorraDelTelefono(): Unit = runBlocking {
        val d = DobleEstudios.escenario("vacio")
        val r = raiz()
        var reloj = 1_800_000_000_000L
        fun armarEn(): Armado {
            val disco = Disco(r, token)
            val carpeta = ColaEstudios.carpeta(File(r, "sin-respaldo"), disco)
            return Armado(ModeloEstudios(ClienteRpc(transporte = d), token, disco, carpeta, esperar = {}, ahora = { reloj }), r, disco, carpeta)
        }
        val a = armarEn()
        a.m.refrescar()
        d.sinRed = true
        assertTrue(a.m.encolar(nuevos(r, pdf to Estudios.MIME_PDF, jpeg to Estudios.MIME_JPEG), null))
        assertEquals(reloj, ColaEstudios.leer(a.disco).single().creadoEn)
        reloj += 13 * dia
        assertEquals(1, armarEn().m.cola.value.size, "a los 13 días sigue esperando")
        assertEquals(2, a.carpeta.listFiles()!!.size)
        reloj += 2 * dia
        val despues = armarEn()
        assertTrue(despues.m.cola.value.isEmpty())
        assertTrue(a.carpeta.listFiles().isNullOrEmpty(), "los archivos se van con el envío")
        assertNull(a.disco.leer(ColaEstudios.ARCHIVO))
    }

    @Test fun unEnvioSinFechaEmpiezaAContarAhora(): Unit = runBlocking {
        val r = raiz()
        val disco = Disco(r, token)
        val carpeta = ColaEstudios.carpeta(File(r, "sin-respaldo"), disco).apply { mkdirs() }
        // Como lo guardaba la versión anterior: sin `creadoEn`.
        disco.guardar(ColaEstudios.ARCHIVO, ValorJson.parsear("""[{"id":"e-viejo","archivos":[{"id":"a1","mime":"application/pdf","subido":false}],"creado":false,"rechazados":0}]"""))
        File(carpeta, "a1.pdf").writeBytes(pdf)
        assertEquals(listOf(5_000L), ColaEstudios.sanear(disco, carpeta, 5_000L).map { it.creadoEn })
        assertEquals(5_000L, ColaEstudios.leer(disco).single().creadoEn, "queda anotado en disco")
        assertEquals(1, ColaEstudios.sanear(disco, carpeta, 5_000L + 14 * dia).size)
        assertTrue(ColaEstudios.sanear(disco, carpeta, 5_001L + 14 * dia).isEmpty())
        assertTrue(carpeta.listFiles().isNullOrEmpty())
    }

    @Test fun alArrancarSeBarreTodoElTelefonoSinMirarLaPalanca(): Unit = runBlocking {
        val d = DobleEstudios.escenario("vacio")
        val r = raiz()
        val sinRespaldo = File(r, "sin-respaldo")
        val cache = File(r, "cache-app")
        val t0 = 1_800_000_000_000L
        // Otra cuenta de este teléfono (sesión cerrada, otro link) con un envío que nadie vino a buscar.
        val discoOtra = Disco(r, "tk-otra-cuenta")
        val carpetaOtra = ColaEstudios.carpeta(sinRespaldo, discoOtra)
        val otra = ModeloEstudios(ClienteRpc(transporte = d), "tk-otra-cuenta", discoOtra, carpetaOtra, esperar = {}, ahora = { t0 })
        otra.refrescar()
        d.sinRed = true
        assertTrue(otra.encolar(nuevos(r, pdf to Estudios.MIME_PDF), null))
        discoOtra.guardar("estudios-estado.json", ValorJson.parsear("""{"habilitado":true}"""))
        // Archivos de una cuenta que ya no tiene carpeta, y restos en la caché de la app.
        val sinDueno = File(sinRespaldo, "MyPump/cuenta-sin-dueno/${ColaEstudios.CARPETA}/x.pdf").apply { parentFile!!.mkdirs(); writeBytes(pdf) }
        val ver = File(cache, "${ColaEstudios.CARPETA_VER}/orden.pdf").apply { parentFile!!.mkdirs(); writeBytes(pdf) }
        val borradorViejo = File(cache, "${ColaEstudios.CARPETA_BORRADOR}/viejo.jpg").apply { parentFile!!.mkdirs(); writeBytes(jpeg); setLastModified(t0 - 2 * 3_600_000L) }
        val borradorReciente = File(cache, "${ColaEstudios.CARPETA_BORRADOR}/reciente.jpg").apply { writeBytes(jpeg); setLastModified(t0 - 60_000L) }
        val camara = File(cache, ColaEstudios.CARPETA_CAMARA).apply { mkdirs() }
        val cruda = File(camara, "estudios-0001.jpg").apply { writeBytes(jpeg); setLastModified(t0 - 1000L) }
        val recienSacada = File(camara, ColaEstudios.FOTO_CAMARA).apply { writeBytes(jpeg); setLastModified(t0 - 60_000L) }
        val deOtraSeccion = File(camara, "foto-frente.jpg").apply { writeBytes(jpeg); setLastModified(t0 - 9 * dia) }

        ColaEstudios.barrerTelefono(r, sinRespaldo, cache, ahora = t0)
        assertEquals(1, ColaEstudios.leer(discoOtra).size, "dentro del plazo, la cola de la otra cuenta espera a su link nuevo")
        assertEquals(1, carpetaOtra.listFiles()!!.size)
        assertFalse(File(discoOtra.carpeta, "estudios-estado.json").exists(), "el estado guardado por la versión anterior se borra")
        assertFalse(sinDueno.exists())
        assertFalse(ver.exists())
        assertFalse(borradorViejo.exists())
        assertTrue(borradorReciente.exists(), "puede ser la hoja que Android está por restaurar")
        assertFalse(cruda.exists(), "la foto cruda de la cámara no queda")
        assertTrue(recienSacada.exists(), "la que la cámara acaba de dejar todavía se va a leer")
        assertTrue(deOtraSeccion.exists(), "lo de otras secciones no se toca")

        ColaEstudios.barrerTelefono(r, sinRespaldo, cache, ahora = t0 + 15 * dia)
        assertTrue(ColaEstudios.leer(discoOtra).isEmpty())
        assertTrue(carpetaOtra.listFiles().isNullOrEmpty())
        assertFalse(borradorReciente.exists())
        assertFalse(recienSacada.exists())
        assertTrue(deOtraSeccion.exists())
    }

    @Test fun cerrarSesionNoDejaNadaMedico(): Unit = runBlocking {
        val d = DobleEstudios.escenario("vacio")
        val a = armar(d)
        a.m.refrescar()
        d.sinRed = true
        assertTrue(a.m.encolar(nuevos(a.raiz, pdf to Estudios.MIME_PDF, jpeg to Estudios.MIME_JPEG), null))
        val elegido = nuevos(a.raiz, jpeg + 1 to Estudios.MIME_JPEG).single()
        assertTrue(a.m.sumarAlBorrador(a.m.reservar(1).hoja, elegido))
        d.sinRed = false
        a.m.borrarTodo()
        assertTrue(a.m.cola.value.isEmpty())
        assertTrue(a.m.borrador.value.isEmpty())
        assertFalse(elegido.archivo.exists())
        assertFalse(a.carpeta.exists())
        assertNull(a.disco.leer(ColaEstudios.ARCHIVO))
        assertNull(a.m.estado.value)
        val antes = d.llamadas.size
        a.m.sincronizar()
        a.m.drenar()
        assertEquals(antes, d.llamadas.size, "después de salir no se llama a nada")
        assertTrue(armar(d, a.raiz).m.cola.value.isEmpty())
    }

    // ── La cola no gira ni se traba ──

    /** Un modelo cuyas tareas de fondo (el reintento a los 60 s) se corren a mano, una por una. */
    private fun conFondo(d: DobleEstudios): Pair<Armado, ArrayDeque<suspend () -> Unit>> {
        val r = raiz()
        val disco = Disco(r, token)
        val carpeta = ColaEstudios.carpeta(File(r, "sin-respaldo"), disco)
        val tareas = ArrayDeque<suspend () -> Unit>()
        return Armado(ModeloEstudios(ClienteRpc(transporte = d), token, disco, carpeta, esperar = {}, lanzar = { tareas.addLast(it) }), r, disco, carpeta) to tareas
    }

    @Test fun faltanArchivosInsistenteNoResubeSinTope(): Unit = runBlocking {
        val d = DobleEstudios.escenario("vacio").apply { faltanVeces = 10_000 }
        val (a, tareas) = conFondo(d)
        a.m.refrescar()
        a.m.encolar(nuevos(a.raiz, pdf to Estudios.MIME_PDF, jpeg to Estudios.MIME_JPEG), null)
        a.m.drenar()
        assertFalse(a.m.detenida.value, "mientras haya un reintento programado, espera")
        var pasadas = 0
        while (tareas.isNotEmpty() && pasadas < 100) {
            tareas.removeFirst()()
            pasadas++
        }
        assertEquals(ModeloEstudios.MAX_REINTENTOS_DE_FONDO, pasadas, "las pasadas solas tienen tope aunque cada archivo suba bien")
        // Por pasada: los archivos una vez por vuelta, más la primera subida.
        val tope = 2 * (1 + (ModeloEstudios.MAX_REINTENTOS_DE_FONDO + 1) * ModeloEstudios.MAX_VUELTAS)
        assertTrue(d.intentosDeSubida <= tope, "${d.intentosDeSubida} subidas")
        assertEquals(2, a.m.cola.value.single().archivos.size, "no se pierde nada")
        assertEquals(2, a.carpeta.listFiles()!!.size)
        assertTrue(a.m.detenida.value, "agotadas las pasadas solas, se dice y se ofrece probar de nuevo")
        assertNull(a.m.aviso.value)
        // «Probar de nuevo» arranca otra tanda; cuando el servidor acepta, sale.
        a.m.usarPalanca(true)
        d.faltanVeces = 0
        a.m.reintentar()
        assertFalse(a.m.detenida.value)
        while (tareas.isNotEmpty()) tareas.removeFirst()()
        assertEquals(2, d.enviados.single().archivos.size)
        assertFalse(a.m.detenida.value)
        assertEquals(ModeloEstudios.Aviso.RECIBIDO, a.m.aviso.value)
    }

    @Test fun elLinkCaidoEnLaSubidaDejaLaColaDetenidaConExplicacion(): Unit = runBlocking {
        for (codigo in listOf(401, 403)) {
            val (d, a) = conDosArchivos(codigo)
            a.m.drenar()
            assertTrue(a.m.detenida.value, "$codigo")
            assertFalse(a.m.sinSenal.value)
            assertNull(a.m.progreso.value)
            assertEquals(2, a.m.cola.value.single().archivos.size)
            a.m.usarPalanca(true)
            a.m.reintentar()
            a.m.drenar()
            assertFalse(a.m.detenida.value)
            assertEquals(2, d.enviados.single().archivos.size)
        }
        // Sin señal no es «detenida»: sale sola cuando vuelve.
        val (_, b) = conDosArchivos(0)
        b.m.drenar()
        assertTrue(b.m.sinSenal.value)
        assertFalse(b.m.detenida.value)
    }

    @Test fun unErrorQueLaAppNoConoceNoDejaElEnvioTrabado(): Unit = runBlocking {
        // En `envio_nuevo`.
        val (d, a) = conDosArchivos()
        d.errorEnvioNuevo = "algo_nuevo"
        a.m.drenar()
        assertTrue(a.m.cola.value.isEmpty())
        assertTrue(a.carpeta.listFiles().isNullOrEmpty())
        assertEquals(ModeloEstudios.Aviso.ERROR, a.m.aviso.value)
        assertNotNull(a.m.estado.value, "la sección sigue")
        assertEquals(0, d.intentosDeSubida)
        // En `enviar`.
        val (d2, b) = conDosArchivos()
        d2.errorEnviar = "algo_nuevo"
        b.m.drenar()
        assertEquals(2, d2.intentosDeSubida)
        assertTrue(b.m.cola.value.isEmpty())
        assertEquals(ModeloEstudios.Aviso.ERROR, b.m.aviso.value)
        assertFalse(b.m.detenida.value)
    }

    @Test fun unErrorPermanenteDeLaRpcDescartaEseEnvioYNoApagaLaSeccion(): Unit = runBlocking {
        val (d, a) = conDosArchivos()
        d.statusDeEscritura = 400
        a.m.drenar()
        assertNotNull(a.m.estado.value, "un 400 habla de ese envío, no de la sección")
        assertTrue(a.m.cola.value.isEmpty())
        assertEquals(ModeloEstudios.Aviso.ERROR, a.m.aviso.value)
        // El siguiente envío sale normal.
        d.statusDeEscritura = null
        assertTrue(a.m.encolar(nuevos(a.raiz, pdf to Estudios.MIME_PDF), null))
        a.m.drenar()
        assertEquals(1, d.enviados.size)
        // Sin la función o sin permiso sí se apaga, y la cola se conserva.
        for (status in listOf(401, 403, 404)) {
            val (d3, c) = conDosArchivos()
            d3.statusDeEscritura = status
            c.m.drenar()
            assertNull(c.m.estado.value, "$status")
            assertEquals(1, c.m.cola.value.size, "$status")
            assertNull(c.m.aviso.value)
        }
    }

    @Test fun agotadasLasVueltasElAvisoEsQueNoSePudoEnviar(): Unit = runBlocking {
        val (d, a) = conDosArchivos()
        d.errorEnviar = "no_encontrado"
        a.m.drenar()
        assertEquals(ModeloEstudios.MAX_VUELTAS + 1, d.llamadas.count { it == "mypump_estudios_enviar" })
        assertTrue(a.m.cola.value.isEmpty())
        assertEquals(ModeloEstudios.Aviso.ERROR, a.m.aviso.value, "no es «No pudimos leer ese archivo»: los archivos estaban bien")
        val (d2, b) = conDosArchivos()
        d2.errorEnvioNuevo = "id_repetido"
        b.m.drenar()
        assertEquals(2, d2.llamadas.count { it == "mypump_estudios_envio_nuevo" }, "se prueba una vez con otro id")
        assertTrue(b.m.cola.value.isEmpty())
        assertEquals(ModeloEstudios.Aviso.ERROR, b.m.aviso.value)
    }

    @Test fun un408NoSeReintenta(): Unit = runBlocking {
        val (d, a) = conDosArchivos(408)
        a.m.drenar()
        assertEquals(2, d.intentosDeSubida)
        assertEquals(1, d.enviados.single().archivos.size)
        assertEquals(ModeloEstudios.Aviso.RECIBIDO_CON_RECHAZO, a.m.aviso.value)
    }

    // ── La hoja de subida ──

    @Test fun laHojaNoRepiteArchivosNiPasaElTope(): Unit = runBlocking {
        val d = DobleEstudios.escenario("vacio")
        val a = armar(d)
        a.m.refrescar()
        val (uno, repetido, otro) = nuevos(a.raiz, jpeg to Estudios.MIME_JPEG, jpeg to Estudios.MIME_JPEG, pdf to Estudios.MIME_PDF)
        val r = a.m.reservar(3)
        assertEquals(3, r.entran)
        assertEquals(3, a.m.preparando.value)
        assertTrue(a.m.sumarAlBorrador(r.hoja, uno))
        assertTrue(a.m.sumarAlBorrador(r.hoja, repetido), "los mismos bytes: ya está")
        assertFalse(repetido.archivo.exists())
        assertFalse(a.m.sumarAlBorrador(r.hoja, null), "una foto que no se pudo leer devuelve su lugar")
        assertEquals(0, a.m.preparando.value)
        assertEquals(listOf(uno.archivo), a.m.borrador.value.map { it.archivo })
        // El tope cuenta lo elegido y lo que se está convirtiendo.
        assertEquals(19, a.m.reservar(50).entran)
        assertEquals(0, a.m.reservar(1).entran)
        // Se cerró la hoja con conversiones en curso: lo que llega después no entra en la próxima y se borra.
        a.m.descartarBorrador()
        assertFalse(uno.archivo.exists())
        assertEquals(0, a.m.preparando.value)
        assertFalse(a.m.sumarAlBorrador(r.hoja, otro))
        assertFalse(otro.archivo.exists())
        assertTrue(a.m.borrador.value.isEmpty())
        assertEquals(0, a.m.preparando.value)
    }

    @Test fun enviarLoDeLaHojaYRestaurarla(): Unit = runBlocking {
        val d = DobleEstudios.escenario("vacio")
        val a = armar(d)
        a.m.refrescar()
        val (uno, dos, perdido) = nuevos(a.raiz, jpeg to Estudios.MIME_JPEG, pdf to Estudios.MIME_PDF, jpeg + 3 to Estudios.MIME_JPEG)
        // Android cerró la app con la hoja abierta: vuelve lo que sigue en el disco.
        perdido.archivo.delete()
        a.m.restaurarBorrador(listOf(uno, dos, perdido))
        assertEquals(listOf(uno.archivo, dos.archivo), a.m.borrador.value.map { it.archivo })
        val r = a.m.reservar(1)
        assertFalse(a.m.enviarBorrador(DobleEstudios.PEDIDO_LAB), "con una foto convirtiéndose no se envía")
        a.m.sumarAlBorrador(r.hoja, null)
        assertTrue(a.m.enviarBorrador(null))
        assertTrue(a.m.borrador.value.isEmpty())
        assertFalse(uno.archivo.exists())
        assertEquals(2, a.carpeta.listFiles()!!.size)
        assertFalse(a.m.enviarBorrador(null), "sin nada elegido no hay envío")
        a.m.drenar()
        assertEquals(listOf(Estudios.MIME_JPEG, Estudios.MIME_PDF), d.enviados.single().archivos.map { it.mime })
    }

    @Test fun siNoSePuedeGuardarLoElegidoQuedaEnLaHoja(): Unit = runBlocking {
        val d = DobleEstudios.escenario("vacio")
        val a = armar(d)
        a.m.refrescar()
        val (uno, dos) = nuevos(a.raiz, jpeg to Estudios.MIME_JPEG, pdf to Estudios.MIME_PDF)
        a.m.restaurarBorrador(listOf(uno, dos))
        // El segundo desaparece (la caché se vació): el primero, ya movido, vuelve a su lugar.
        dos.archivo.delete()
        assertFalse(a.m.enviarBorrador(null))
        assertTrue(uno.archivo.exists())
        assertTrue(a.m.cola.value.isEmpty())
        assertTrue(a.carpeta.listFiles().isNullOrEmpty())
        assertEquals(2, a.m.borrador.value.size)
    }

    @Test fun elPdfDePruebaEstaBienArmado() {
        val texto = String(DobleEstudios.pdfDePrueba(2), Charsets.US_ASCII)
        assertTrue(texto.startsWith("%PDF-1.4"))
        val xref = texto.substringAfter("startxref\n").substringBefore("\n").toInt()
        assertTrue(texto.substring(xref).startsWith("xref"))
        assertEquals(2, Regex("/Type /Page ").findAll(texto).count())
    }
}
