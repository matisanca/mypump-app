package com.pumpteam.mypump.datos

import com.pumpteam.mypump.modelos.ValorJson
import java.io.File
import java.util.concurrent.atomic.AtomicInteger
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeoutOrNull
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * Los dos carriles de la cola (los audios de la guía y las demás ops; revisión del 4-nov, hallazgo 1) llaman al ejecutor a
 * la vez. Con el token caído, los dos ven «no se guardó» al mismo tiempo: la verificación del token se pregunta UNA vez (el
 * candado de [VerificacionToken] y su minuto), las dos ops se estacionan sin gastar intento y el archivo de la cola queda
 * igual que la memoria (las dos pasadas escriben por el mismo despachador).
 */
class OutboxCarrilesConcurrenciaTest {
    private val alcances = mutableListOf<CoroutineScope>()

    private fun alcance(): CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.Default).also { alcances += it }

    @AfterEach
    fun cerrar() = alcances.forEach { it.cancel() }

    @Test
    fun losDosCarrilesConElTokenCaidoVerificanUnaSolaVez() = runBlocking {
        val carpeta = carpetaTemporal("carriles")
        val grabacion = File(carpeta, "a1.m4a").apply { writeBytes(ByteArray(64) { 1 }) }
        // Las dos primeras llamadas (iniciar del audio y la del hábito) se esperan entre sí: así seguro vuelan a la vez.
        val llegaron = AtomicInteger(0)
        val juntas = CompletableDeferred<Unit>()
        val t = TransporteProgramado { fn, _ ->
            if (fn == "entregas_app_audio_iniciar" || fn == "mypump_set_habito") {
                if (llegaron.incrementAndGet() >= 2) juntas.complete(Unit)
                withTimeoutOrNull(5_000) { juntas.await() }
            }
            if (fn == "mypump_get_cliente_info") delay(150)   // la verificación tarda: la otra llega mientras tanto
            200 to if (fn == "mypump_get_cliente_info") "[]" else "null"
        }
        val esc = Escrituras(ClienteRpc(transporte = t), "tok-carriles-0000000000")
        val archivo = File(carpeta, "outbox.json")
        val o = Outbox(archivo = archivo, reintentoAutomatico = false, alcance = alcance()) { esc.ejecutar(it) }
        o.encolar(
            ModeloAudioDudas.KIND,
            ValorJson.objeto("id" to ValorJson.Texto("a1"), "archivo" to ValorJson.Texto(grabacion.path), "segundos" to ValorJson.Numero(5.0)),
            null,
        )
        o.encolar("habito", ValorJson.objeto("fecha" to ValorJson.Texto("2026-11-04"), "campo" to ValorJson.Texto("durmio_bien"), "valor" to ValorJson.Texto("true")), "habito|2026-11-04|durmio_bien")
        o.drenar()

        assertTrue(juntas.isCompleted, "los dos carriles no volaron a la vez")
        assertEquals(1, t.llamadas.count { it == "mypump_get_cliente_info" })
        val quedan = o.operaciones()
        assertEquals(setOf(ModeloAudioDudas.KIND, "habito"), quedan.map { it.kind }.toSet())
        assertTrue(quedan.all { it.tries == 0 })   // estacionadas, no gastan intento
        assertTrue(o.fallidos().isEmpty())
        // Lo del disco es lo de la memoria: ninguna pasada pisó la escritura de la otra.
        val (enDisco, fallidosEnDisco) = Outbox.leerArchivo(archivo)!!
        assertEquals(quedan.map { it.id to it.intentada }, enDisco.map { it.id to it.intentada })
        assertTrue(fallidosEnDisco.isEmpty())
    }
}
