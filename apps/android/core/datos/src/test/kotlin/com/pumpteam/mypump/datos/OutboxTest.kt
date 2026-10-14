package com.pumpteam.mypump.datos

import com.pumpteam.mypump.modelos.ValorJson
import java.io.File
import java.io.IOException
import java.util.Collections
import java.util.concurrent.atomic.AtomicBoolean
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.params.ParameterizedTest
import org.junit.jupiter.params.provider.ValueSource

/**
 * Los casos de scripts/test-outbox.mjs (cada uno encierra un bug real) y de OutboxTests.swift, con la cola de Android.
 * Los dobles devuelven lo que devuelve la API REAL (apps/shared/fixtures/errores/).
 */
class OutboxTest {
    private val alcances = mutableListOf<CoroutineScope>()

    private fun alcance(): CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.Default).also { alcances += it }

    @AfterEach
    fun cerrar() = alcances.forEach { it.cancel() }

    private fun cola(ejecutor: suspend (Operacion) -> ResultadoOp) =
        Outbox(archivo = null, reintentoAutomatico = false, alcance = alcance(), ejecutor = ejecutor)

    private fun carga(serie: Int): ValorJson = ValorJson.objeto(
        "diaId" to texto("d1"), "semana" to numero(1), "datos" to ValorJson.objeto("serie" to numero(serie)),
    )

    private val ok: ResultadoOp = ResultadoOp.Respuesta(Resultado.Ok(texto("row-id")))

    private fun red(): ResultadoOp = ResultadoOp.Respuesta(Resultado.Falla(ErrorRpc(ErrorRpc.Clase.RED, 0, mensaje = "x")))

    @Test
    fun loEncoladoDuranteElVueloNoSePierde() = runBlocking {
        val enviados = Collections.synchronizedList(mutableListOf<String>())
        val o = Outbox(archivo = null, reintentoAutomatico = true, alcance = alcance()) { op ->
            enviados += op.dedupeKey ?: ""
            delay(40)
            ok
        }
        o.encolar("carga", carga(1), "k1")
        delay(10)
        o.encolar("carga", carga(2), "k2")
        delay(400)
        assertTrue("k2" in enviados)
        assertEquals(0, o.pendientes())
    }

    @Test
    fun tampocoSePierdeDelDisco() = runBlocking {
        val archivo = File(carpetaTemporal("outbox"), "outbox.json")
        val o = Outbox(archivo = archivo, reintentoAutomatico = true, alcance = alcance()) {
            delay(60)
            ok
        }
        o.encolar("carga", carga(1), "k1")
        delay(10)
        o.encolar("carga", carga(2), "k2")
        val enDisco = Json.parseToJsonElement(archivo.readText()).jsonObject["ops"]!!.jsonArray
        assertTrue(enDisco.any { it.jsonObject["dedupeKey"]?.jsonPrimitive?.content == "k2" })
        // Y una cola nueva sobre el mismo archivo la levanta (sobrevive a cerrar la app).
        val otra = Outbox(archivo = archivo, reintentoAutomatico = false, alcance = alcance()) { ok }
        assertTrue(otra.pendientes() >= 1)
    }

    @ParameterizedTest
    @ValueSource(strings = ["token_invalido_escritura", "token_invalido_lectura"])
    fun nullOListaVaciaNoCuentanComoGuardado(fixture: String) = runBlocking {
        val cliente = ClienteRpc(transporte = Grabado.de(fixture))
        val o = cola { ResultadoOp.Respuesta(cliente.llamar("mypump_registrar_carga", emptyMap())) }
        o.encolar("carga", carga(1), "k1")
        o.drenar()
        assertEquals(1, o.pendientes())
    }

    @Test
    fun unCeroTampoco() = runBlocking {
        val o = cola { ResultadoOp.Respuesta(Resultado.Ok(numero(0))) }
        o.encolar("peso", ValorJson.objeto(), "p")
        o.drenar()
        assertEquals(1, o.pendientes())
    }

    @Test
    fun falseSiCuenta() = runBlocking {
        // Desmarcar algo que no estaba: la RPC devuelve false y el objetivo está cumplido.
        val cliente = ClienteRpc(transporte = Grabado.de("boolean_false"))
        val o = cola { ResultadoOp.Respuesta(cliente.llamar("mypump_desmarcar_comida", emptyMap())) }
        o.encolar("comida", ValorJson.objeto(), "c")
        o.drenar()
        assertEquals(0, o.pendientes())
    }

    @Test
    fun unRechazoRealGastaIntentosYTerminaEnFallidos() = runBlocking {
        val cliente = ClienteRpc(transporte = Grabado.de("tipo_invalido"))
        val o = cola { ResultadoOp.Respuesta(cliente.llamar("mypump_registrar_carga", emptyMap())) }
        o.encolar("carga", carga(1), "k1")
        repeat(12) { if (o.pendientes() > 0) o.drenar() }
        assertEquals(0, o.pendientes())
        val f = o.fallidos()
        assertEquals(1, f.size)   // no se pierde: queda para el diagnóstico y el recibo
        assertEquals(8, f.first().op.tries)
    }

    @Test
    fun sinRedTreintaPasadasNoAbandonanNada() = runBlocking {
        val cliente = ClienteRpc(transporte = SinRed)
        val o = cola { ResultadoOp.Respuesta(cliente.llamar("mypump_registrar_carga", emptyMap())) }
        o.encolar("carga", carga(1), "k1")
        o.encolar("carga", carga(2), "k2")
        repeat(30) { o.drenar() }
        assertEquals(2, o.pendientes())
        assertTrue(o.operaciones().all { it.tries == 0 })
    }

    @Test
    fun portalCautivoEsFaltaDeRed() = runBlocking {
        val cliente = ClienteRpc(transporte = PortalCautivo)
        val o = cola { ResultadoOp.Respuesta(cliente.llamar("mypump_registrar_carga", emptyMap())) }
        o.encolar("carga", carga(1), "k1")
        repeat(12) { o.drenar() }
        assertEquals(1, o.pendientes())
    }

    @ParameterizedTest
    @ValueSource(ints = [503, 429, 408, 500])
    fun transitorioNoGastaIntentos(status: Int) = runBlocking {
        val cliente = ClienteRpc(transporte = Grabado(status, "{\"message\":\"x\"}"))
        val o = cola { ResultadoOp.Respuesta(cliente.llamar("mypump_registrar_carga", emptyMap())) }
        o.encolar("carga", carga(1), "k1")
        repeat(12) { o.drenar() }
        assertEquals(1, o.pendientes())
    }

    @Test
    fun sinRedNoSigueMandandoLasDemas() = runBlocking {
        val enviados = Collections.synchronizedList(mutableListOf<String>())
        val o = cola { op ->
            enviados += op.id
            red()
        }
        o.encolar("carga", carga(1), "k1")
        o.encolar("carga", carga(2), "k2")
        repeat(30) { o.drenar() }
        assertTrue(enviados.size <= 31)
        assertEquals(2, o.pendientes())
    }

    @Test
    fun cuandoVuelveLaRedSeMandan() = runBlocking {
        val hayRed = AtomicBoolean(false)
        val o = cola { if (hayRed.get()) ok else red() }
        o.encolar("carga", carga(1), "k1")
        repeat(10) { o.drenar() }
        hayRed.set(true)
        o.drenar()
        assertEquals(0, o.pendientes())
    }

    @Test
    fun unThrowDeRedNoGastaIntentos() = runBlocking {
        val o = cola { throw IOException("se cortó la conexión") }
        o.encolar("carga", carga(1), "k1")
        repeat(12) { o.drenar() }
        assertEquals(1, o.pendientes())
    }

    @Test
    fun unBugNuestroGastaIntentosYNoCongelaALasDeAtras() = runBlocking {
        val enviados = Collections.synchronizedList(mutableListOf<String>())
        val o = cola { op ->
            if (op.dedupeKey == "k1") error("bug")
            enviados += op.dedupeKey ?: ""
            ok
        }
        o.encolar("carga", carga(1), "k1")
        o.encolar("carga", carga(2), "k2")
        repeat(12) { if (o.pendientes() > 0) o.drenar() }
        assertTrue("k2" in enviados)
        assertEquals(0, o.pendientes())
        assertEquals(1, o.fallidos().size)
    }

    @Test
    fun ganaLaUltimaDecisionPorClave() = runBlocking {
        val enviados = Collections.synchronizedList(mutableListOf<String>())
        val o = cola { op ->
            enviados += (op.payload["estado"]?.comoTexto ?: "null")
            ResultadoOp.Respuesta(Resultado.Ok(ValorJson.Booleano(false)))
        }
        o.encolar("comida", ValorJson.objeto("estado" to texto("comido")), "comida|2026-09-19|c2")
        o.encolar("comida", ValorJson.objeto("estado" to ValorJson.Nulo), "comida|2026-09-19|c2")
        assertEquals(1, o.pendientes())
        o.drenar()
        assertEquals(listOf("null"), enviados.toList())
        assertEquals(0, o.pendientes())
    }

    @Test
    fun drenarEsperaLaPasadaEnCurso() = runBlocking {
        val fin = AtomicBoolean(false)
        val o = Outbox(archivo = null, reintentoAutomatico = true, alcance = alcance()) {
            delay(80)
            fin.set(true)
            ok
        }
        o.encolar("carga", carga(1), "k1")
        delay(15)
        o.drenar()
        assertTrue(fin.get())
    }

    @Test
    fun abandonarDejaElAvisoDePerdido() = runBlocking {
        val estados = Collections.synchronizedList(mutableListOf<EstadoGuardado>())
        val o = cola { ResultadoOp.Respuesta(Resultado.Falla(ErrorRpc(ErrorRpc.Clase.PERMANENTE, 400, "22P02", "boom"))) }
        o.observar(estado = { estados += it }, abandonadas = {})
        o.encolar("carga", carga(1), "k1")
        repeat(12) { if (o.pendientes() > 0) o.drenar() }
        assertEquals(EstadoGuardado.PERDIDO, estados.last())
    }

    @Test
    fun tokenCaidoEstacionaSinGastar() = runBlocking {
        val o = cola { ResultadoOp.TokenCaido }
        o.encolar("carga", carga(1), "k1")
        repeat(20) { o.drenar() }
        assertEquals(1, o.pendientes())
        assertEquals(0, o.operaciones().first().tries)
    }

    @Test
    fun importarRespetaOrdenYNoDuplica() = runBlocking {
        val o = cola { ok }
        val viejas = (1..3).map { Operacion("legado_$it", "carga", carga(it), "k$it", ts = it.toDouble()) }
        o.importar(viejas)
        o.importar(viejas)
        assertEquals(listOf("legado_1", "legado_2", "legado_3"), o.operaciones().map { it.id })
    }

    @Test
    fun pgrst202EsPermanenteYSeReconoce() = runBlocking {
        val e = ClienteRpc(transporte = Grabado.de("pgrst202")).llamar("x", emptyMap()).errorONull()!!
        assertTrue(e.clase == ErrorRpc.Clase.PERMANENTE && e.funcionInexistente)
        val e2 = ClienteRpc(transporte = Grabado.de("p0001")).llamar("x", emptyMap()).errorONull()!!
        assertTrue(e2.codigo == "P0001" && e2.mensaje == "token invalido")
    }

    // ── Lo que agregó la migración del almacenamiento viejo (Outbox.swift @025c9d0) ──

    @Test
    fun importarSinPisarDejaGanarALoMasNuevo() = runBlocking {
        val o = cola { ok }
        // La nativa ya tiene pendiente el agua de hoy, cargada DESPUÉS que la de la app vieja.
        val nativa = Operacion("nativa_1", "habito", ValorJson.objeto("valor" to texto("6")), "habito|2026-10-14|vasos_agua", ts = 2_000_000_000_000.0)
        o.importar(listOf(nativa))
        val vieja = Operacion("1_1", "habito", ValorJson.objeto("valor" to texto("2")), "habito|2026-10-14|vasos_agua", ts = 1_791_000_000_000.0)
        val masVieja = Operacion("1_2", "peso", ValorJson.objeto("valor" to numero(80)), "peso_2026-10-14", ts = 1_791_000_000_000.0)
        val entraron = o.importarSinPisar(listOf(vieja, masVieja, nativa))
        assertEquals(listOf("1_2", "nativa_1"), entraron.map { it.id })
        assertEquals(listOf("nativa_1", "1_2"), o.operaciones().map { it.id })
        // Al revés, una vieja que llega con una clave cuya pendiente es MÁS vieja la reemplaza.
        val nueva = Operacion("1_3", "peso", ValorJson.objeto("valor" to numero(81)), "peso_2026-10-14", ts = 1_792_000_000_000.0)
        o.importarSinPisar(listOf(nueva))
        assertEquals(listOf("nativa_1", "1_3"), o.operaciones().map { it.id })
    }

    @Test
    fun archivarEnFallidosNoPierdeNada() = runBlocking {
        val o = cola { ok }
        val op = Operacion("legado_9", "carga", carga(1), "k9", ts = 1.0)
        o.importar(listOf(op))
        o.archivarEnFallidos(listOf(op), "para revisar: la rutina activa ya no es la de la foto")
        o.archivarEnFallidos(listOf(op), "otra vez")
        assertEquals(0, o.pendientes())
        assertEquals(listOf("para revisar: la rutina activa ya no es la de la foto"), o.fallidos().map { it.motivo })
    }

    @Test
    fun drenarVaciaTodoLoEncoladoAunqueLlegueEnVuelo() = runBlocking {
        // "Cerrar el día" espera el envío de TODO lo anterior: lo que se encola durante una pasada sale en la misma llamada.
        val enviados = Collections.synchronizedList(mutableListOf<String>())
        lateinit var o: Outbox
        var segunda = true
        o = cola { op ->
            enviados += op.dedupeKey ?: ""
            if (segunda) {
                segunda = false
                o.encolar("carga", carga(2), "k2")
            }
            ok
        }
        o.encolar("carga", carga(1), "k1")
        o.drenar()
        assertEquals(listOf("k1", "k2"), enviados.toList())
        assertEquals(0, o.pendientes())
    }
}
