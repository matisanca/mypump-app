package com.pumpteam.mypump.datos

import com.pumpteam.mypump.modelos.ValorJson
import java.io.File
import kotlinx.coroutines.delay
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Assumptions.assumeTrue
import org.junit.jupiter.api.Test

/**
 * Las dudas en audio contra el backend REAL (`entregas_019`, contrato final) con la cuenta `test-nativa-android`. Sube UN
 * audio de verdad (un m4a AAC, `MYPUMP_AUDIO_M4A`) y lo manda otra vez con el mismo `p_id` (la re-subida da 403 y `subido`
 * confirma): en el servidor queda uno solo. Corre solo con `MYPUMP_PROBAR_AUDIO=1` (el tope es de 10 por cliente). El token
 * sale del registro privado o de `MYPUMP_TOKEN_GUIA`; nunca se imprime.
 */
class AudioIntegracionTest {
    @Test
    fun subeUnAudioYLaListaLoTrae() = enUnHilo { alcance ->
        assumeTrue(System.getenv("MYPUMP_PROBAR_AUDIO") == "1", "MYPUMP_PROBAR_AUDIO=1 para subir un audio real")
        val origen = System.getenv("MYPUMP_AUDIO_M4A")?.let(::File)
        assumeTrue(origen?.isFile == true, "MYPUMP_AUDIO_M4A con un m4a de prueba")
        val token = System.getenv("MYPUMP_TOKEN_GUIA")?.ifBlank { null } ?: IntegracionTest.tokenDePrueba()
        assumeTrue(token != null, "sin token de la cuenta de prueba")
        val t = token!!

        val disco = Disco(carpetaTemporal("audio-int"), t)
        val cliente = ClienteRpc()
        val esc = Escrituras(cliente, t)
        val cola = Outbox(archivo = disco.archivo("outbox.json"), reintentoAutomatico = false, alcance = alcance) { esc.ejecutar(it) }
        val m = ModeloAudioDudas(cliente, t, cola, disco, alcance)
        m.alDia()
        cola.observar(estado = {}, abandonadas = m::alAbandonar, guardadas = m::alGuardar)
        assertTrue(m.refrescar(), "entregas_app_audios tendría que contestar")
        assertTrue(m.disponible.value)
        val antes = m.items.value.size

        val copia = File.createTempFile("audio-int", ".m4a").also { origen!!.copyTo(it, overwrite = true) }
        assertTrue(m.mandar(copia, 3))
        val op = cola.operaciones().single()
        cola.drenar()
        repeat(50) { if (cola.pendientes() > 0 || m.items.value.none { it.estado == ModeloAudioDudas.Estado.SUBIDO }) delay(100) }
        assertEquals(0, cola.pendientes(), "fallidos: ${cola.fallidos().map { it.motivo }}")
        val id = op.payload["id"]?.comoTexto!!

        // La lista lo trae, con su duración.
        assertTrue(m.refrescar())
        val fila = cliente.llamar("entregas_app_audios", mapOf("p_token" to ValorJson.Texto(t))).valorONull()
            ?.let { (it as? ValorJson.Lista)?.elementos }?.firstOrNull { it["id"]?.comoTexto == id }
        assertTrue(fila != null, "la lista no trae el audio")
        assertTrue(fila!!["estado"]?.comoTexto in setOf("subido", "transcripto", "error"))
        assertEquals(antes + 1, m.items.value.size)

        // Otra vez con el mismo p_id (como un reintento de la cola después de un corte): la re-subida da 403 y `subido`
        // confirma. No suma otro audio.
        val otra = File.createTempFile("audio-int", ".m4a").also { origen!!.copyTo(it, overwrite = true) }
        val r = EnvioAudioDuda(cliente, t).ejecutar(op.payload.let { p ->
            ValorJson.Objeto((p as ValorJson.Objeto).campos + ("archivo" to ValorJson.Texto(otra.absolutePath)))
        })
        val e = r.errorONull()
        assertTrue(e == null, "reintento: ${e?.status} ${e?.codigo} ${e?.mensaje?.take(200)}")
        assertEquals(ValorJson.Booleano(true), (r as Resultado.Ok).valor["ok"], "reintento: ${r.valor}")
        assertTrue(m.refrescar())
        assertEquals(antes + 1, m.items.value.size)
        otra.delete()
    }
}
