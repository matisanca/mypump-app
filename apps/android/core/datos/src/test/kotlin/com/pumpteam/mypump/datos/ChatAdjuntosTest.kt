package com.pumpteam.mypump.datos

import com.pumpteam.mypump.modelos.AdjuntoChat
import com.pumpteam.mypump.modelos.MensajeChat
import com.pumpteam.mypump.modelos.ValorJson
import com.pumpteam.mypump.reglas.ReglasChatAdjuntos
import java.io.File
import java.io.IOException
import java.util.concurrent.CopyOnWriteArrayList
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.yield
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNotEquals
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/** Fotos y audios del chat (2.3.0), con los casos de ChatAdjuntosTests.swift. Todo contra un servidor de mentira. */
class ChatAdjuntosTest {
    private class Servidor(@Volatile var adjunto: (Pedido) -> Pair<Int, String>) : Transporte {
        val pedidos = CopyOnWriteArrayList<Pedido>()
        @Volatile var sinRed = false
        @Volatile var tokenCaido = false

        override suspend fun enviar(pedido: Pedido): Respuesta {
            pedidos += pedido
            if (sinRed) throw IOException("sin conexión (prueba)")
            val r = pedido.ruta
            val (s, t) = when {
                r.endsWith("/chat/adjunto") -> adjunto(pedido)
                r.endsWith("mypump_chat_adjuntos_estado") -> 200 to """{"habilitado":true,"audio_max_s":120}"""
                r.endsWith("mypump_get_cliente_info") -> 200 to if (tokenCaido) "[]" else """[{"cliente_id":"c1","nombre":"Cliente"}]"""
                r.endsWith("/chat/urls") -> {
                    val ids = (ValorJson.parsear(pedido.cuerpo!!.toString(Charsets.UTF_8))["ids"] as ValorJson.Lista).elementos.map { it.comoTexto!! }
                    200 to """{"ok":true,"adjuntos":[${ids.joinToString(",") { """{"id":"$it","tipo":"foto","mime":"image/jpeg","url":"https://ejemplo.invalid/firmada/$it"}""" }}]}"""
                }
                "/firmada/" in r -> return Respuesta(200, byteArrayOf(0xFF.toByte(), 0xD8.toByte(), 0xFF.toByte(), 1, 2, 3))
                else -> 200 to "[]"
            }
            return Respuesta(s, t.toByteArray())
        }

        fun a(ruta: String) = pedidos.filter { it.ruta.endsWith(ruta) }
    }

    private val okAdjunto: (Pedido) -> Pair<Int, String> = { 200 to """{"ok":true,"ya":false,"comentario_id":"c-1","created_at":"2026-11-10T15:00:00.123456+00:00"}""" }

    private class Entorno(val m: ModeloChat, val cola: Outbox, val s: Servidor, val carpeta: File)

    private suspend fun entorno(alcance: CoroutineScope, s: Servidor, activo: Boolean = true): Entorno {
        val disco = Disco(carpetaTemporal("chat-adj"), "tok")
        val cliente = ClienteRpc(transporte = s)
        val esc = Escrituras(cliente, "tok")
        val cola = Outbox(archivo = disco.archivo("outbox.json"), reintentoAutomatico = false, alcance = alcance) { esc.ejecutar(it) }
        val carpeta = disco.archivo(CARPETA_ADJUNTOS_CHAT)
        val m = ModeloChat(cliente, "tok", cola, alcance, carpetaAdjuntos = carpeta)
        cola.observar(estado = {}, abandonadas = { ops -> alcance.launch { m.alAbandonarAdjuntos(ops) } }, guardadas = m::alGuardarAdjuntos)
        if (activo) m.consultarAdjuntos(true)
        yield()
        return Entorno(m, cola, s, carpeta)
    }

    private suspend fun asentar() = repeat(15) { delay(10) }

    /** Lo que sale de `ReduccionFoto` en la app: un JPEG (acá alcanza con la firma). */
    private val jpeg = byteArrayOf(0xFF.toByte(), 0xD8.toByte(), 0xFF.toByte(), 0xE0.toByte()) + ByteArray(2000) { 7 }

    @Test
    fun laFotoSaleConSusEncabezadosYLaBurbujaPasaASerLaFila() = enUnHilo { alcance ->
        val e = entorno(alcance, Servidor(okAdjunto))
        assertTrue(e.m.adjuntosActivos.value)
        assertTrue(e.m.enviarFoto(jpeg))
        val b = e.m.hilo.value.mensajes.last()
        assertTrue(b.pendiente && !b.fallo && b.contenido == "Foto" && b.adjunto?.tipo == AdjuntoChat.Tipo.FOTO)
        val id = b.adjunto!!.id

        e.cola.drenar()
        asentar()
        val p = e.s.a("/chat/adjunto").single()
        assertEquals("POST", p.metodo)
        assertEquals("tok", p.cabeceras["x-chat-token"])
        assertEquals(id, p.cabeceras["x-chat-id"])
        assertEquals("foto", p.cabeceras["x-chat-tipo"])
        assertEquals("image/jpeg", p.cabeceras["Content-Type"])
        assertNull(p.cabeceras["x-chat-duracion"])
        assertTrue(p.cuerpo!!.contentEquals(jpeg))

        assertEquals(0, e.cola.pendientes())
        val real = e.m.hilo.value.mensajes.single { it.adjunto?.id == id }
        assertFalse(real.pendiente)
        assertEquals("c-1", real.id)
        assertTrue(real.createdAt.startsWith("2026-11-10T15:00"))
        // El archivo queda: se ve sin bajarlo.
        assertEquals(e.m.archivos.value[id], e.m.archivo(real.adjunto!!))
        assertTrue(e.s.a("/chat/urls").isEmpty())
    }

    @Test
    fun elAudioLlevaLaDuracionYElTextoDelServidor() = enUnHilo { alcance ->
        val e = entorno(alcance, Servidor(okAdjunto))
        val tmp = File.createTempFile("grab", ".m4a").apply { writeBytes(ByteArray(4000) { 7 }) }
        assertTrue(e.m.enviarAudio(tmp, 42.4))
        assertFalse(tmp.exists())
        val b = e.m.hilo.value.mensajes.last()
        assertEquals("Audio de 0:42", b.contenido)
        assertEquals(42.0, b.adjunto?.duracion)
        e.cola.drenar()
        asentar()
        val p = e.s.a("/chat/adjunto").single()
        assertEquals("audio", p.cabeceras["x-chat-tipo"])
        assertEquals("42", p.cabeceras["x-chat-duracion"])
        assertEquals("audio/mp4", p.cabeceras["Content-Type"])
    }

    @Test
    fun unToqueSinQuererNoSale() = enUnHilo { alcance ->
        val e = entorno(alcance, Servidor(okAdjunto))
        val tmp = File.createTempFile("grab", ".m4a").apply { writeBytes(ByteArray(100)) }
        assertFalse(e.m.enviarAudio(tmp, 0.4))
        assertTrue(e.m.hilo.value.mensajes.isEmpty())
        assertEquals(ReglasChatAdjuntos.TEXTO_MUY_CORTO, e.m.anuncio.value?.second)
        assertFalse(tmp.exists())
    }

    @Test
    fun conLaPalancaApagadaNoSeMuestraNiSeLlama() = enUnHilo { alcance ->
        val e = entorno(alcance, Servidor(okAdjunto), activo = false)
        e.m.consultarAdjuntos(false)
        assertFalse(e.m.adjuntosActivos.value)
        assertTrue(e.s.a("mypump_chat_adjuntos_estado").isEmpty())
        assertFalse(e.m.enviarFoto(jpeg))
        assertTrue(e.m.hilo.value.mensajes.isEmpty())
    }

    @Test
    fun sinLeerLaPalancaQuedaLoUltimoQueSeSupo() = enUnHilo { alcance ->
        val e = entorno(alcance, Servidor(okAdjunto))
        assertTrue(e.m.adjuntosActivos.value)
        val otro = ModeloChat(ClienteRpc(transporte = SinRed), "tok", e.cola, alcance, carpetaAdjuntos = e.carpeta)
        otro.consultarAdjuntos(null)
        assertTrue(otro.adjuntosActivos.value)
        val sinRed = ModeloChat(ClienteRpc(transporte = SinRed), "tok", e.cola, alcance, carpetaAdjuntos = e.carpeta)
        sinRed.consultarAdjuntos(true)
        assertTrue(sinRed.adjuntosActivos.value)
    }

    @Test
    fun sinSenalEsperaSinGastarIntentosYNoSePierde() = enUnHilo { alcance ->
        val e = entorno(alcance, Servidor { 503 to """{"ok":false,"error":"no se pudo subir"}""" })
        assertTrue(e.m.enviarFoto(jpeg))
        e.cola.drenar()
        e.cola.drenar()
        asentar()
        assertEquals(1, e.cola.pendientes())
        assertEquals(0, e.cola.operaciones().single().tries)
        assertTrue(e.cola.fallidos().isEmpty())
        val b = e.m.hilo.value.mensajes.last()
        assertTrue(b.pendiente && !b.fallo)
        // La app se cierra: al volver, la burbuja vuelve desde la cola.
        val m2 = ModeloChat(ClienteRpc(transporte = e.s), "tok", e.cola, alcance, carpetaAdjuntos = e.carpeta)
        m2.cargarAdjuntosDeLaCola()
        val r = m2.hilo.value.mensajes.single()
        assertTrue(r.pendiente && !r.fallo && r.contenido == "Foto")
        assertEquals(b.adjunto?.id, r.adjunto?.id)
        assertNotNull(m2.archivos.value[r.adjunto!!.id])
    }

    @Test
    fun elTopeDelDiaVaDirectoANoSalioYSePuedeReintentar() = enUnHilo { alcance ->
        val e = entorno(alcance, Servidor { 429 to """{"ok":false,"error":"muchos adjuntos por hoy"}""" })
        assertTrue(e.m.enviarFoto(jpeg))
        e.cola.drenar()
        asentar()
        assertEquals(1, e.s.a("/chat/adjunto").size)
        assertEquals(0, e.cola.pendientes())
        assertEquals(ReglasChatAdjuntos.CODIGO_TOPE, e.cola.fallidos().single().motivo)
        val b = e.m.hilo.value.mensajes.last()
        assertTrue(b.fallo)
        assertEquals(ReglasChatAdjuntos.CODIGO_TOPE, b.motivoFallo)
        assertEquals(ReglasChatAdjuntos.TEXTO_TOPE, e.m.anuncio.value?.second)

        val id = b.adjunto!!.id
        e.m.reintentarAdjunto(id)
        assertTrue(e.cola.fallidos().isEmpty())
        assertEquals(id, e.cola.operaciones().single().payload["id"]?.comoTexto)
        assertTrue(e.m.hilo.value.mensajes.last().let { it.pendiente && !it.fallo })
    }

    @Test
    fun unRechazoNoGastaLosOchoIntentos() = enUnHilo { alcance ->
        val e = entorno(alcance, Servidor { 413 to """{"ok":false,"error":"archivo muy grande"}""" })
        assertTrue(e.m.enviarFoto(jpeg))
        e.cola.drenar()
        asentar()
        assertEquals(1, e.s.a("/chat/adjunto").size)
        assertEquals(ReglasChatAdjuntos.CODIGO_RECHAZO, e.cola.fallidos().single().motivo)
        assertTrue(e.m.hilo.value.mensajes.last().fallo)
    }

    @Test
    fun unIdDeOtroMensajeSaleSoloConOtro() = enUnHilo { alcance ->
        val e = entorno(alcance, Servidor { 409 to """{"ok":false,"error":"id repetido"}""" })
        assertTrue(e.m.enviarFoto(jpeg))
        val viejo = e.m.hilo.value.mensajes.last().adjunto!!.id
        e.cola.drenar()
        asentar()
        // Sin tocar nada: vuelve a la cola con un id nuevo y la burbuja sigue «enviando…», nunca «no salió».
        assertFalse(e.m.hilo.value.mensajes.last().fallo)
        val op = e.cola.operaciones().single()
        val nuevo = op.payload["id"]?.comoTexto!!
        assertNotEquals(viejo, nuevo)
        assertEquals("$nuevo.jpg", File(op.payload["archivo"]?.comoTexto!!).name)
        assertTrue(File(e.carpeta, "$nuevo.jpg").isFile)
        assertEquals(nuevo, e.m.hilo.value.mensajes.single().adjunto?.id)
    }

    @Test
    fun sinElArchivoNoSeOfreceReintentarYSePuedeBorrar() = enUnHilo { alcance ->
        val e = entorno(alcance, Servidor(okAdjunto))
        assertTrue(e.m.enviarFoto(jpeg))
        val id = e.m.hilo.value.mensajes.last().adjunto!!.id
        File(e.carpeta, "$id.jpg").delete()
        e.cola.drenar()
        asentar()
        assertTrue(e.s.a("/chat/adjunto").isEmpty())
        val b = e.m.hilo.value.mensajes.last()
        assertTrue(b.fallo)
        assertFalse(ReglasChatAdjuntos.sePuedeReintentar(b.motivoFallo))
        e.m.descartarAdjunto(id)
        assertTrue(e.m.hilo.value.mensajes.isEmpty())
        assertTrue(e.cola.fallidos().isEmpty())
    }

    @Test
    fun unTokenCaidoEstacionaSinGastarIntento() = enUnHilo { alcance ->
        val s = Servidor { 403 to """{"ok":false,"error":"token inválido"}""" }
        val e = entorno(alcance, s)
        s.tokenCaido = true
        assertTrue(e.m.enviarFoto(jpeg))
        e.cola.drenar()
        asentar()
        assertEquals(1, e.cola.pendientes())
        assertEquals(0, e.cola.operaciones().single().tries)
        assertTrue(e.cola.fallidos().isEmpty())
    }

    @Test
    fun loQueLlegoSeBajaConUnaFirmaParaVariosALaVez() = enUnHilo { alcance ->
        val s = Servidor(okAdjunto)
        val e = entorno(alcance, s)
        val ids = List(3) { java.util.UUID.randomUUID().toString() }
        e.m._hilo.value = e.m.hilo.value.mezclar(ids.mapIndexed { i, id -> fila("m$i", "Foto", """{"id":"$id","tipo":"foto"}""", "2026-11-10T1$i:00:00+00:00") }).hilo
        val f = e.m.archivo(AdjuntoChat(ids[0], AdjuntoChat.Tipo.FOTO))!!
        assertEquals("${ids[0]}.jpg", f.name)
        assertNotNull(e.m.archivo(AdjuntoChat(ids[2], AdjuntoChat.Tipo.FOTO)))
        assertEquals(1, s.a("/chat/urls").size)
        val antes = s.pedidos.size
        assertEquals(f, e.m.archivo(AdjuntoChat(ids[0], AdjuntoChat.Tipo.FOTO)))
        assertNull(e.m.archivo(AdjuntoChat(java.util.UUID.randomUUID().toString(), AdjuntoChat.Tipo.FOTO, borrado = true)))
        assertEquals(antes, s.pedidos.size)
    }

    @Test
    fun sinRedLaBurbujaOfreceProbarDeNuevo() = enUnHilo { alcance ->
        val s = Servidor(okAdjunto)
        val e = entorno(alcance, s)
        s.sinRed = true
        val a = AdjuntoChat(java.util.UUID.randomUUID().toString(), AdjuntoChat.Tipo.AUDIO, 5.0)
        assertNull(e.m.archivo(a))
        assertTrue(a.id in e.m.sinBajar.value)
    }

    // ── El hilo ──

    private fun fila(id: String, contenido: String, adjunto: String? = null, hora: String = "2026-11-10T15:00:00+00:00"): MensajeChat {
        val adj = adjunto?.let { ""","adjunto":$it""" } ?: ""
        return MensajeChat.desde(ValorJson.parsear("""{"id":"$id","autor":"cliente","contenido":"$contenido","created_at":"$hora"$adj}""").aJson())
    }

    private fun pendiente(id: String, tipo: AdjuntoChat.Tipo = AdjuntoChat.Tipo.FOTO) =
        burbujaPendiente(id, tipo, if (tipo == AdjuntoChat.Tipo.AUDIO) 5.0 else null, "2026-11-10T15:00:00.000Z")

    @Test
    fun laConfirmadaNoMueveElCursorHastaQueLlegaLaFila() {
        val coach = MensajeChat.desde(ValorJson.parsear("""{"id":"m1","autor":"coach","contenido":"hola","created_at":"2026-11-10T14:00:00+00:00"}""").aJson())
        var h = HiloChat().mezclar(listOf(coach)).hilo.agregarPendiente(pendiente("a"))
            .confirmarAdjunto("a", "c1", "2026-11-10T15:00:00+00:00")
        h = h.mezclar(emptyList()).hilo
        assertEquals("2026-11-10T14:00:00+00:00", h.cursor)
        h = h.mezclar(listOf(fila("c1", "Foto", """{"id":"a","tipo":"foto"}"""))).hilo
        assertEquals("2026-11-10T15:00:00+00:00", h.cursor)
        assertTrue(h.mensajes.none { it.confirmado })
    }

    @Test
    fun dosFotosSeguidasSonDosMensajes() {
        val h = HiloChat().agregarPendiente(pendiente("a")).agregarPendiente(pendiente("b"))
            .mezclar(listOf(fila("c1", "Foto", """{"id":"a","tipo":"foto"}"""))).hilo
        assertEquals(listOf("adj_b", "c1"), h.mensajes.map { it.id }.sorted())
    }

    @Test
    fun unTextoFotoNoSeComeLaFotoNiAlReves() {
        var h = HiloChat().agregarPendiente(pendiente("a"))
            .agregarPendiente(BurbujaChat("tmp_1", "cliente", "Foto", null, "2026-11-10T15:00:01.000Z", pendiente = true))
            .mezclar(listOf(fila("t1", "Foto"))).hilo
        assertTrue(h.mensajes.any { it.id == "adj_a" })
        assertTrue(h.mensajes.none { it.id == "tmp_1" })
        h = h.agregarPendiente(BurbujaChat("tmp_2", "cliente", "Foto", null, "2026-11-10T15:00:02.000Z", pendiente = true))
            .mezclar(listOf(fila("c1", "Foto", """{"id":"a","tipo":"foto"}"""))).hilo
        assertTrue(h.mensajes.any { it.id == "tmp_2" })
        h = h.marcarFallido("Foto")
        assertTrue(h.mensajes.filter { it.adjunto != null }.none { it.fallo })
    }

    @Test
    fun confirmarConLaFilaQueYaLlegoSoloSacaLaOptimista() {
        val h = HiloChat().agregarPendiente(pendiente("a", AdjuntoChat.Tipo.AUDIO))
            .mezclar(listOf(fila("c1", "Audio de 0:05", """{"id":"a","tipo":"audio","duracion_s":5}"""))).hilo
            .confirmarAdjunto("a", "c1", null)
        assertEquals(listOf("c1"), h.mensajes.map { it.id })
        assertEquals(5.0, h.mensajes.single().adjunto?.duracion)
    }

    @Test
    fun laRetencionBorroElArchivoYLaBurbujaLoDice() {
        var h = HiloChat().mezclar(listOf(fila("c1", "Foto", """{"id":"a","tipo":"foto"}"""))).hilo
        assertEquals(1, h.adjuntosReales.size)
        h = h.mezclar(listOf(fila("c1", "Foto", """{"id":"a","tipo":"foto","borrado":true}"""))).hilo
        assertEquals(true, h.mensajes.single().adjunto?.borrado)
        assertTrue(h.adjuntosReales.isEmpty())
    }

    @Test
    fun elMensajeSinAdjuntoOConUnTipoNuevoSigueSiendoTexto() {
        assertNull(fila("x", "hola").adjunto)
        assertNull(fila("x", "Video", """{"id":"a","tipo":"video"}""").adjunto)
        assertNull(fila("x", "Foto", "null").adjunto)
        val a = fila("x", "Audio", """{"id":"A-B","tipo":"audio","duracion_s":"12.5"}""").adjunto!!
        assertEquals("a-b", a.id)
        assertEquals(12.5, a.duracion)
        assertFalse(a.borrado)
    }
}
