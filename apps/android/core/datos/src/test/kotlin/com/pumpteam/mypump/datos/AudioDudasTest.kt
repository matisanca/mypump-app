package com.pumpteam.mypump.datos

import com.pumpteam.mypump.modelos.ValorJson
import java.io.File
import java.io.IOException
import java.util.concurrent.CopyOnWriteArrayList
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.yield
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * Las dudas en audio (`entregas_019`, todavía sin aplicar en el servidor): un doble que contesta el contrato de
 * `AUDIO_APP.md` (iniciar, la subida a Storage, subido y la lista), con la cola de verdad sin reintento automático.
 */
class AudioDudasTest {
    /** El servidor de mentira. [regla] decide por función (o `storage` para la subida); anota cada pedido. */
    private class Servidor(var regla: (fn: String, p: Pedido) -> Pair<Int, String>) : Transporte {
        val pedidos = CopyOnWriteArrayList<Pedido>()
        @Volatile var sinRed = false
        @Volatile var sinRedEnSubida = false

        override suspend fun enviar(pedido: Pedido): Respuesta {
            pedidos += pedido
            val storage = "/storage/v1/object/" in pedido.url
            if (sinRed || (storage && sinRedEnSubida)) throw IOException("sin conexión (prueba)")
            val fn = if (storage) "storage" else pedido.ruta.substringAfterLast('/')
            val (s, t) = regla(fn, pedido)
            return Respuesta(s, t.toByteArray())
        }

        fun a(fn: String): List<Pedido> = pedidos.filter { if (fn == "storage") "/storage/v1/object/" in it.url else it.ruta.endsWith("/$fn") }

        fun cuerpo(p: Pedido): ValorJson = ValorJson.parsear(p.cuerpo!!.toString(Charsets.UTF_8))
    }

    private val ticket = """{"ok": true, "id": "x", "bucket": "entregas-audio", "ruta": "cliente-x/a.m4a", "mime": "audio/mp4"}"""

    private fun normal(lista: String = "[]"): (String, Pedido) -> Pair<Int, String> = { fn, _ ->
        when (fn) {
            "entregas_app_audio_iniciar" -> 200 to ticket
            "storage" -> 200 to """{"Key": "entregas-audio/cliente-x/a.m4a"}"""
            "entregas_app_audio_subido" -> 200 to "true"
            "entregas_app_audios" -> 200 to lista
            "mypump_get_cliente_info" -> 200 to """[{"nombre": "Marcelo"}]"""
            else -> 200 to "true"
        }
    }

    private class Entorno(val m: ModeloAudioDudas, val cola: Outbox, val s: Servidor, val disco: Disco)

    private suspend fun entorno(
        alcance: CoroutineScope,
        s: Servidor,
        disco: Disco = Disco(carpetaTemporal("audio"), "tok"),
        reloj: () -> Long = System::currentTimeMillis,
        esperar: suspend (Long) -> Unit = {},
    ): Entorno {
        val cliente = ClienteRpc(transporte = s)
        val esc = Escrituras(cliente, "tok")
        val cola = Outbox(archivo = disco.archivo("outbox.json"), reintentoAutomatico = false, alcance = alcance) { esc.ejecutar(it) }
        val m = ModeloAudioDudas(cliente, "tok", cola, disco, alcance, reloj = reloj, esperar = esperar)
        m.alDia()
        cola.observar(estado = {}, abandonadas = m::alAbandonar, guardadas = m::alGuardar)
        yield()
        return Entorno(m, cola, s, disco)
    }

    /** Deja correr lo lanzado (las RPC salen por Dispatchers.Default y el disco por IO: hace falta tiempo de verdad). */
    private suspend fun asentar() = repeat(15) { delay(10) }

    private fun grabado(bytes: Int = 4_000): File = File.createTempFile("grab", ".m4a").apply { writeBytes(ByteArray(bytes) { (it % 7).toByte() }) }

    private fun carpetaAudios(d: Disco): File = d.archivo(ModeloAudioDudas.CARPETA)

    @Test
    fun mandaLosTresPasosYBorraElArchivo() = enUnHilo { alcance ->
        val e = entorno(alcance, Servidor(normal()))
        assertTrue(e.m.mandar(grabado(), 42))
        assertEquals(ModeloAudioDudas.Estado.MANDANDO, e.m.items.value.single().estado)
        assertTrue(e.m.hayMandando)
        assertEquals(1, carpetaAudios(e.disco).listFiles()!!.size)
        e.cola.drenar()
        asentar()

        val ini = e.s.cuerpo(e.s.a("entregas_app_audio_iniciar").single())
        assertEquals("tok", ini["p_token"]?.comoTexto)
        assertEquals("audio/mp4", ini["p_mime"]?.comoTexto)
        assertEquals(4_000.0, ini["p_bytes"]?.comoNumero)
        assertEquals(42.0, ini["p_segundos"]?.comoNumero)
        val id = ini["p_id"]?.comoTexto!!
        assertTrue(Regex("^[0-9a-f-]{36}$").matches(id))

        val sub = e.s.a("storage").single()
        assertEquals("POST", sub.metodo)
        assertTrue(sub.url.endsWith("/storage/v1/object/entregas-audio/cliente-x/a.m4a"), sub.url)
        assertEquals("audio/mp4", sub.cabeceras["Content-Type"])
        assertEquals("false", sub.cabeceras["x-upsert"])
        assertEquals("Bearer ${ConfigBackend.produccion.anonKey}", sub.cabeceras["Authorization"])
        assertEquals(ConfigBackend.produccion.anonKey, sub.cabeceras["apikey"])
        assertEquals(4_000, sub.cuerpo!!.size)

        assertEquals(id, e.s.cuerpo(e.s.a("entregas_app_audio_subido").single())["p_id"]?.comoTexto)
        assertEquals(0, e.cola.pendientes())
        // Confirmado: el archivo se borra y se ve «Listo, me llegó tu audio» hasta que la lista lo traiga.
        assertTrue(carpetaAudios(e.disco).listFiles()!!.isEmpty())
        assertEquals(ModeloAudioDudas.Estado.SUBIDO, e.m.items.value.single().estado)
        assertTrue(e.s.a("entregas_app_audios").isNotEmpty(), "después de mandar se pide la lista")
    }

    @Test
    fun laListaTraeLoTranscriptoYElError() = enUnHilo { alcance ->
        val lista = """[
            {"id": "a1", "estado": "transcripto", "en": "2026-11-04T10:00:00Z", "segundos": 31, "texto": "¿Puedo entrenar en ayunas?"},
            {"id": "a2", "estado": "error", "en": "2026-11-04T10:05:00Z", "texto": null},
            {"id": "a3", "estado": "subido", "en": "2026-11-04T10:06:00Z"}
        ]"""
        val e = entorno(alcance, Servidor(normal(lista)))
        assertTrue(e.m.refrescar())
        assertTrue(e.m.disponible.value)
        val items = e.m.items.value
        assertEquals(listOf("a1", "a2", "a3"), items.map { it.id })
        assertEquals(listOf(ModeloAudioDudas.Estado.TRANSCRIPTO, ModeloAudioDudas.Estado.ERROR, ModeloAudioDudas.Estado.SUBIDO), items.map { it.estado })
        assertEquals("¿Puedo entrenar en ayunas?", items[0].texto)
        assertEquals(listOf("¿Puedo entrenar en ayunas?"), e.m.transcriptos)

        // La caché: otra sesión sin red ve lo mismo.
        e.m.alDia()
        asentar()
        val otra = ModeloAudioDudas(ClienteRpc(transporte = SinRed), "tok", null, e.disco, alcance).also { it.alDia() }
        assertTrue(otra.disponible.value)
        assertEquals(3, otra.items.value.size)
    }

    @Test
    fun sinLaFuncionNoHayAudios() = enUnHilo { alcance ->
        val s = Servidor { fn, _ ->
            if (fn == "entregas_app_audios") 404 to """{"code":"PGRST202","message":"Could not find the function public.entregas_app_audios"}""" else 200 to "true"
        }
        val e = entorno(alcance, s)
        assertFalse(e.m.disponible.value)
        assertFalse(e.m.refrescar())
        assertFalse(e.m.disponible.value)
        // Sin red tampoco aparece (nunca contestó).
        val sinRed = ModeloAudioDudas(ClienteRpc(transporte = SinRed), "tok", null, Disco(carpetaTemporal("audio"), "tok"), alcance).also { it.alDia() }
        sinRed.refrescar()
        assertFalse(sinRed.disponible.value)
    }

    @Test
    fun sinRedNoGastaIntentoYSeReintentaConElMismoId() = enUnHilo { alcance ->
        val s = Servidor(normal())
        val e = entorno(alcance, s)
        e.m.mandar(grabado(), 10)
        s.sinRedEnSubida = true
        e.cola.drenar()
        asentar()
        assertEquals(1, e.cola.pendientes())
        assertEquals(0, e.cola.operaciones().single().tries)
        val item = e.m.items.value.single()
        assertEquals(ModeloAudioDudas.Estado.NO_SE_MANDO, item.estado)
        assertEquals("No se pudo mandar.", item.aviso)
        assertTrue(item.reintentable)
        assertFalse(e.m.hayMandando)

        s.sinRedEnSubida = false
        e.m.reintentar(item.id)
        e.cola.drenar()
        asentar()
        assertEquals(0, e.cola.pendientes())
        val ids = s.a("entregas_app_audio_iniciar").map { s.cuerpo(it)["p_id"]?.comoTexto }
        assertEquals(2, ids.size)
        assertEquals(1, ids.toSet().size, "el mismo p_id en cada intento")
        assertEquals(ModeloAudioDudas.Estado.SUBIDO, e.m.items.value.single().estado)
    }

    @Test
    fun laReSubidaConTresCientosTresLaDecideSubido() = enUnHilo { alcance ->
        // Contrato final: la re-subida de la misma ruta da 403; `subido` confirma.
        val base = normal()
        val s = Servidor { fn, p -> if (fn == "storage") 403 to """{"statusCode":"403","error":"Unauthorized","message":"new row violates row-level security policy"}""" else base(fn, p) }
        val e = entorno(alcance, s)
        e.m.mandar(grabado(), 10)
        e.cola.drenar()
        asentar()
        assertEquals(0, e.cola.pendientes())
        assertEquals(1, s.a("entregas_app_audio_subido").size)
        assertTrue(EnvioAudioDuda.quizasYaEstaba(Respuesta(409, ByteArray(0))))
        assertTrue(EnvioAudioDuda.quizasYaEstaba(Respuesta(400, """{"statusCode":"409","error":"Duplicate"}""".toByteArray())))
        assertTrue(EnvioAudioDuda.quizasYaEstaba(Respuesta(400, """{"statusCode":"403","error":"Unauthorized","message":"new row violates row-level security policy"}""".toByteArray())))
        assertFalse(EnvioAudioDuda.quizasYaEstaba(Respuesta(400, """{"statusCode":"400","message":"mime type not supported"}""".toByteArray())))
    }

    @Test
    fun sinArchivoSubeOtraVezYVencidoPideOtroTicket() = enUnHilo { alcance ->
        val base = normal()
        val respuestas = ArrayDeque(listOf("""{"ok": false, "motivo": "sin_archivo"}""", """{"ok": false, "motivo": "vencido"}""", """{"ok": true, "estado": "subido"}"""))
        val s = Servidor { fn, p -> if (fn == "entregas_app_audio_subido") 200 to respuestas.removeFirst() else base(fn, p) }
        val e = entorno(alcance, s)
        e.m.mandar(grabado(), 10)
        e.cola.drenar()
        asentar()
        assertEquals(0, e.cola.pendientes())
        // sin_archivo: subir de nuevo con el mismo ticket; vencido: iniciar de nuevo con el mismo id.
        assertEquals(3, s.a("storage").size)
        val ids = s.a("entregas_app_audio_iniciar").map { s.cuerpo(it)["p_id"]?.comoTexto }
        assertEquals(2, ids.size)
        assertEquals(1, ids.toSet().size)
        assertEquals(ModeloAudioDudas.Estado.SUBIDO, e.m.items.value.single().estado)
    }

    @Test
    fun siSubidoNuncaConfirmaGastaIntento() = enUnHilo { alcance ->
        val base = normal()
        val s = Servidor { fn, p -> if (fn == "entregas_app_audio_subido") 200 to """{"ok": false, "motivo": "sin_archivo"}""" else base(fn, p) }
        val e = entorno(alcance, s)
        e.m.mandar(grabado(), 10)
        e.cola.drenar()
        assertEquals(EnvioAudioDuda.RONDAS, s.a("storage").size)
        assertEquals(1, e.cola.operaciones().single().tries)
    }

    @Test
    fun siSubidoSeCortaSeVuelveAProbarYElArchivoQueda() = enUnHilo { alcance ->
        val base = normal()
        var cortar = true
        val s = Servidor { fn, p -> if (fn == "entregas_app_audio_subido" && cortar) 503 to """{"message":"ocupado"}""" else base(fn, p) }
        val e = entorno(alcance, s)
        e.m.mandar(grabado(), 10)
        e.cola.drenar()
        asentar()
        assertEquals(1, e.cola.pendientes())
        assertEquals(0, e.cola.operaciones().single().tries)
        assertEquals(1, carpetaAudios(e.disco).listFiles()!!.size, "hasta que se confirma, el archivo queda")
        cortar = false
        e.cola.drenar()
        asentar()
        assertEquals(0, e.cola.pendientes())
        assertTrue(carpetaAudios(e.disco).listFiles()!!.isEmpty())
    }

    @Test
    fun motivoIdVaAFallidosYErrorAvisa() = enUnHilo { alcance ->
        var motivo = "id"
        val base = normal()
        val s = Servidor { fn, p -> if (fn == "entregas_app_audio_iniciar") 200 to """{"ok": false, "motivo": "$motivo"}""" else base(fn, p) }
        val e = entorno(alcance, s)
        e.m.mandar(grabado(), 10)
        e.cola.drenar()
        asentar()
        assertEquals(0, e.cola.pendientes())
        assertEquals(1, e.cola.fallidos().size)
        assertFalse(e.m.items.value.single().reintentable)
        motivo = "error"
        e.m.mandar(grabado(), 10)
        e.cola.drenar()
        asentar()
        val err = e.m.items.value.last()
        assertEquals("No pude escuchar bien este audio, ¿me lo mandás de nuevo o lo escribís?", err.aviso)
        assertFalse(err.reintentable)
    }

    @Test
    fun losMotivosDeIniciar() = enUnHilo { alcance ->
        var motivo = "tope"
        val base = normal()
        val s = Servidor { fn, p -> if (fn == "entregas_app_audio_iniciar") 200 to """{"ok": false, "motivo": "$motivo"}""" else base(fn, p) }
        val e = entorno(alcance, s)
        e.m.mandar(grabado(), 10)
        e.cola.drenar()
        asentar()
        // Rechazado: sale de la cola, avisa y el archivo se borra (no va a entrar nunca).
        assertEquals(0, e.cola.pendientes())
        val tope = e.m.items.value.single()
        assertEquals(ModeloAudioDudas.Estado.NO_SE_MANDO, tope.estado)
        assertEquals("Ya me mandaste 10 audios. Lo que te falte escribímelo o lo vemos en la llamada.", tope.aviso)
        assertFalse(tope.reintentable)
        assertTrue(carpetaAudios(e.disco).listFiles()!!.isEmpty())
        assertTrue(s.a("storage").isEmpty())

        // `pendientes`: el audio queda y se puede reintentar con el mismo id.
        motivo = "pendientes"
        e.m.mandar(grabado(), 11)
        e.cola.drenar()
        asentar()
        val pend = e.m.items.value.last()
        assertEquals("Esperá un toque que se terminen de mandar los otros audios.", pend.aviso)
        assertTrue(pend.reintentable)
        assertEquals(1, carpetaAudios(e.disco).listFiles()!!.size)
        s.regla = base
        e.m.reintentar(pend.id)
        e.cola.drenar()
        asentar()
        assertEquals(ModeloAudioDudas.Estado.SUBIDO, e.m.items.value.single { it.id == pend.id }.estado)
        assertTrue(carpetaAudios(e.disco).listFiles()!!.isEmpty())
    }

    @Test
    fun conElTokenCaidoQuedaEstacionado() = enUnHilo { alcance ->
        val s = Servidor { fn, _ ->
            when (fn) {
                "entregas_app_audio_iniciar" -> 200 to """{"ok": false, "motivo": "token"}"""
                "mypump_get_cliente_info" -> 200 to "[]"
                else -> 200 to "true"
            }
        }
        val e = entorno(alcance, s)
        e.m.mandar(grabado(), 10)
        e.cola.drenar()
        asentar()
        assertEquals(1, e.cola.pendientes())
        assertEquals(0, e.cola.operaciones().single().tries)
        assertTrue(e.cola.fallidos().isEmpty())
    }

    @Test
    fun dosAudiosSonDosOps() = enUnHilo { alcance ->
        val e = entorno(alcance, Servidor(normal()))
        e.m.mandar(grabado(), 10)
        e.m.mandar(grabado(), 10)
        assertEquals(2, e.cola.pendientes())
        assertEquals(2, e.m.items.value.size)
        assertEquals(2, e.cola.operaciones().map { it.payload["id"]?.comoTexto }.toSet().size)
    }

    @Test
    fun abandonadoSeReintentaDesdeFallidos() = enUnHilo { alcance ->
        val base = normal()
        val s = Servidor { fn, p -> if (fn == "storage") 400 to """{"statusCode":"400","message":"mime type not supported"}""" else base(fn, p) }
        val e = entorno(alcance, s)
        e.m.mandar(grabado(), 10)
        repeat(8) { e.cola.drenar() }
        asentar()
        assertEquals(0, e.cola.pendientes())
        assertEquals(1, e.cola.fallidos().size)
        val item = e.m.items.value.single()
        assertEquals(ModeloAudioDudas.Estado.NO_SE_MANDO, item.estado)
        assertTrue(item.reintentable)
        assertEquals(1, carpetaAudios(e.disco).listFiles()!!.size, "abandonado, el archivo queda para reintentar")

        s.regla = base
        e.m.reintentar(item.id)
        assertTrue(e.cola.fallidos().isEmpty())
        e.cola.drenar()
        asentar()
        assertEquals(ModeloAudioDudas.Estado.SUBIDO, e.m.items.value.single().estado)
    }

    @Test
    fun sigueLaListaCada15sHasta3Minutos() = enUnHilo { alcance ->
        var ahora = 0L
        val s = Servidor(normal("""[{"id": "a1", "estado": "subido", "en": "2026-11-04T10:00:00Z"}]"""))
        val e = entorno(alcance, s, reloj = { ahora }, esperar = { ms -> ahora += ms; yield() })
        val seguir = alcance.launch { e.m.seguir() }
        repeat(100) { if (s.a("entregas_app_audios").size < 13) delay(20) }
        asentar()
        // 1 al abrir y una cada 15 s mientras no pasen 3 minutos: 0, 15, …, 180 → 13 consultas.
        assertEquals(13, s.a("entregas_app_audios").size)
        assertTrue(seguir.isActive, "queda esperando un audio nuevo, sin consultar")
        seguir.cancel()

        // Con todo transcripto no sigue.
        val s2 = Servidor(normal("""[{"id": "a1", "estado": "transcripto", "texto": "hola"}]"""))
        val e2 = entorno(alcance, s2, reloj = { ahora }, esperar = { ms -> ahora += ms; yield() })
        val seguir2 = alcance.launch { e2.m.seguir() }
        asentar()
        asentar()
        assertEquals(1, s2.a("entregas_app_audios").size)
        seguir2.cancel()
    }

    @Test
    fun losHuerfanosSeBorranAlAbrir() = enUnHilo { alcance ->
        val disco = Disco(carpetaTemporal("audio"), "tok")
        val viejo = File(carpetaAudios(disco).apply { mkdirs() }, "viejo.m4a").apply { writeBytes(ByteArray(10)) }
        entorno(alcance, Servidor(normal()), disco = disco)
        assertFalse(viejo.exists())
    }

    @Test
    fun sinArchivoNoEsFaltaDeRed() = enUnHilo { alcance ->
        val e = entorno(alcance, Servidor(normal()))
        e.m.mandar(grabado(), 10)
        carpetaAudios(e.disco).listFiles()!!.forEach { it.delete() }
        e.cola.drenar()
        asentar()
        assertEquals(0, e.cola.pendientes())
        assertTrue(e.s.a("entregas_app_audio_iniciar").isEmpty())
        assertEquals("No se pudo mandar.", e.m.items.value.single().aviso)
    }

    @Test
    fun enLaDemoNoSaleNada() = enUnHilo { alcance ->
        val s = Servidor(normal())
        val m = ModeloAudioDudas(ClienteRpc(transporte = s), "", null, null, alcance, esDemo = true)
        assertTrue(m.disponible.value)
        assertFalse(m.mandar(grabado(), 10))
        m.seguir()
        assertTrue(m.refrescar())
        assertTrue(s.pedidos.isEmpty())
        assertNull(m.items.value.firstOrNull())
    }
}
