package com.pumpteam.mypump.datos

import com.pumpteam.mypump.modelos.ValorJson
import java.util.Collections
import java.util.concurrent.atomic.AtomicBoolean
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * Un audio de la guía con `pendientes` (3 a la vez sin terminar de procesar) espera con backoff sin gastar intentos, como
 * en iOS: no frena al resto de la cola, no muestra «sin conexión» y lo nuevo que se encola no espera su backoff.
 */
class OutboxAudioPendientesTest {
    private val alcances = mutableListOf<CoroutineScope>()

    private fun alcance(): CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.Default).also { alcances += it }

    @AfterEach
    fun cerrar() = alcances.forEach { it.cancel() }

    private val ok: ResultadoOp = ResultadoOp.Respuesta(Resultado.Ok(ValorJson.Texto("row-id")))

    private val pendientes: ResultadoOp = ResultadoOp.Respuesta(
        Resultado.Falla(ErrorRpc(ErrorRpc.Clase.TRANSITORIO, 200, EnvioAudioDuda.MOTIVO_PENDIENTES, "entregas_app_audio_iniciar: pendientes")),
    )

    private fun audio(id: String) = ValorJson.objeto("p_id" to ValorJson.Texto(id))

    private fun serie(n: Int) = ValorJson.objeto("diaId" to ValorJson.Texto("d1"), "datos" to ValorJson.objeto("serie" to ValorJson.Numero(n.toDouble())))

    @Test
    fun unaSerieEncoladaDespuesDeUnAudioEnPendientesSaleIgual() = runBlocking {
        val enviados = Collections.synchronizedList(mutableListOf<String>())
        val estados = Collections.synchronizedList(mutableListOf<EstadoGuardado>())
        val o = Outbox(archivo = null, reintentoAutomatico = false, alcance = alcance()) { op ->
            enviados += op.kind
            if (op.kind == ModeloAudioDudas.KIND) pendientes else ok
        }
        o.observar(estado = { estados += it }, abandonadas = {})
        o.encolar(ModeloAudioDudas.KIND, audio("a1"), "guia_audio_a1")
        o.encolar("carga", serie(1), "k1")
        o.drenar()

        assertEquals(setOf(ModeloAudioDudas.KIND, "carga"), enviados.toSet())
        val quedan = o.operaciones()
        assertEquals(listOf(ModeloAudioDudas.KIND), quedan.map { it.kind })
        assertEquals(0, quedan.single().tries)   // no gasta intento
        assertTrue(o.fallidos().isEmpty())
        assertFalse(EstadoGuardado.SIN_CONEXION in estados)
    }

    @Test
    fun loEncoladoDespuesNoEsperaElBackoffDelAudio() = runBlocking {
        val enviados = Collections.synchronizedList(mutableListOf<String>())
        val o = Outbox(archivo = null, reintentoAutomatico = true, alcance = alcance()) { op ->
            enviados += op.kind
            if (op.kind == ModeloAudioDudas.KIND) pendientes else ok
        }
        o.encolar(ModeloAudioDudas.KIND, audio("a1"), "guia_audio_a1")
        delay(300)   // la primera pasada ya volvió: el audio quedó esperando su backoff (2 s o más)
        assertEquals(1, enviados.count { it == ModeloAudioDudas.KIND })
        o.encolar("carga", serie(1), "k1")
        delay(300)
        assertTrue("carga" in enviados, "la serie salió sin esperar el backoff del audio")
        assertEquals(listOf(ModeloAudioDudas.KIND), o.operaciones().map { it.kind })
    }

    @Test
    fun elAudioSaleCuandoSeLibera() = runBlocking {
        val libre = AtomicBoolean(false)
        val o = Outbox(archivo = null, reintentoAutomatico = false, alcance = alcance()) { op ->
            if (op.kind == ModeloAudioDudas.KIND && !libre.get()) pendientes else ok
        }
        o.encolar(ModeloAudioDudas.KIND, audio("a1"), "guia_audio_a1")
        repeat(10) { o.drenar() }   // más que los 8 intentos: no se abandona
        assertEquals(0, o.operaciones().single().tries)
        assertTrue(o.fallidos().isEmpty())
        libre.set(true)
        o.drenar()
        assertEquals(0, o.pendientes())
    }

    // ── Revisión adversarial del 4-nov ──

    private val sinRedAudio: ResultadoOp = ResultadoOp.Respuesta(Resultado.Falla(ErrorRpc(ErrorRpc.Clase.RED, 0, mensaje = "subida: sin red")))

    @Test
    fun conLaSubidaDelAudioFallandoPorRedUnaSerieEncoladaDetrasSale() = runBlocking {
        // Hallazgo 1 (bloqueante): un audio sin red no corta la pasada; la serie sale y el audio no gasta intento.
        for (falla in listOf<suspend () -> ResultadoOp>({ sinRedAudio }, { throw java.io.IOException("sin red") })) {
            val enviados = Collections.synchronizedList(mutableListOf<String>())
            val estados = Collections.synchronizedList(mutableListOf<EstadoGuardado>())
            val o = Outbox(archivo = null, reintentoAutomatico = false, alcance = alcance()) { op ->
                enviados += op.kind
                if (op.kind == ModeloAudioDudas.KIND) falla() else ok
            }
            o.observar(estado = { estados += it }, abandonadas = {})
            o.encolar(ModeloAudioDudas.KIND, audio("a1"), "guia_audio_a1")
            o.encolar(ModeloAudioDudas.KIND, audio("a2"), "guia_audio_a2")
            o.encolar("carga", serie(1), "k1")
            o.drenar()
            assertTrue("carga" in enviados)
            assertEquals(2, enviados.count { it == ModeloAudioDudas.KIND }, "el segundo audio también se probó (continue)")
            val quedan = o.operaciones()
            assertEquals(listOf(ModeloAudioDudas.KIND, ModeloAudioDudas.KIND), quedan.map { it.kind })
            assertTrue(quedan.all { it.tries == 0 })
            assertFalse(EstadoGuardado.SIN_CONEXION in estados)
        }
    }

    @Test
    fun cerrarElDiaNoEsperaALosAudios() = runBlocking {
        val suelta = kotlinx.coroutines.CompletableDeferred<Unit>()
        val enviados = Collections.synchronizedList(mutableListOf<String>())
        val o = Outbox(archivo = null, reintentoAutomatico = false, alcance = alcance()) { op ->
            enviados += op.kind
            if (op.kind == ModeloAudioDudas.KIND) suelta.await()
            ok
        }
        o.encolar(ModeloAudioDudas.KIND, audio("a1"), "guia_audio_a1")
        o.encolar("carga", serie(1), "k1")
        kotlinx.coroutines.withTimeout(2_000) { o.drenar(esperarAudios = false) }
        assertEquals(listOf(ModeloAudioDudas.KIND), o.operaciones().map { it.kind }, "la serie salió con el audio en vuelo")
        suelta.complete(Unit)
        o.drenar()
        assertEquals(0, o.pendientes())
    }

    @Test
    fun pendientesPasadasDosHorasVaAFallidos() = runBlocking {
        // Hallazgo 16: sin gastar intento, pero con un tope de 2 h desde la primera vez; después, fallidos («No se pudo mandar»).
        var ahora = 1_000_000L
        val archivo = java.io.File.createTempFile("outbox", ".json").apply { delete() }
        val abandonadas = Collections.synchronizedList(mutableListOf<Operacion>())
        val o = Outbox(archivo = archivo, reintentoAutomatico = false, alcance = alcance(), reloj = { ahora }) { pendientes }
        o.observar(estado = {}, abandonadas = { abandonadas += it })
        o.encolar(ModeloAudioDudas.KIND, audio("a1"), "guia_audio_a1")
        o.drenar()
        assertEquals(ahora.toDouble(), o.operaciones().single().esperaDesde)
        // Se guarda en el archivo: cerrar la app no reinicia el reloj.
        val otra = Outbox(archivo = archivo, reintentoAutomatico = false, alcance = alcance(), reloj = { ahora }) { pendientes }
        assertEquals(ahora.toDouble(), otra.operaciones().single().esperaDesde)
        ahora += Outbox.TOPE_ESPERA_AUDIO_MS - 1
        o.drenar()
        assertEquals(1, o.pendientes())
        assertEquals(0, o.operaciones().single().tries)
        ahora += 1
        o.drenar()
        assertEquals(0, o.pendientes())
        val f = o.fallidos().single()
        assertEquals(Outbox.MOTIVO_ESPERA_VENCIDA, f.motivo)
        assertEquals(listOf(ModeloAudioDudas.KIND), abandonadas.map { it.kind })
        archivo.delete()
    }
}
