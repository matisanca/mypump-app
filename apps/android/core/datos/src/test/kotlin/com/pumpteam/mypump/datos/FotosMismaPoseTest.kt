package com.pumpteam.mypump.datos

import com.pumpteam.mypump.reglas.DiaCalendario
import com.pumpteam.mypump.reglas.FechaLocal
import com.pumpteam.mypump.reglas.FotosProgreso
import com.pumpteam.mypump.modelos.ValorJson
import java.io.IOException
import java.util.Base64
import kotlinx.coroutines.async
import kotlinx.coroutines.delay
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/** Servicio de fotos con compuerta: cada subida sigue su guion, y lo guardado queda como el upsert real (gana la última). */
class ServicioConCompuerta(vararg pasos: String) : Transporte {
    private val guion = ArrayDeque(pasos.toList())
    val recibidas = mutableListOf<String>()
    val guardada = mutableMapOf<String, String>()
    @Volatile var abierta = false

    fun cuantas() = synchronized(this) { recibidas.size }

    override suspend fun enviar(pedido: Pedido): Respuesta {
        if (!pedido.ruta.endsWith("upload")) return Respuesta(200, "[]".toByteArray())
        val cuerpo = ValorJson.parsear(pedido.cuerpo!!.toString(Charsets.UTF_8))
        val imagen = cuerpo["imagen_base64"]?.comoTexto ?: ""
        val pose = cuerpo["pose"]?.comoTexto ?: ""
        val paso = synchronized(this) {
            recibidas += imagen
            guion.removeFirstOrNull() ?: "sinRed"
        }
        if (paso == "sinRed") throw IOException("se cortó")
        if (paso == "okDespuesDeLaCompuerta") while (!abierta) delay(5)
        synchronized(this) { guardada[pose] = imagen }
        return Respuesta(200, "{\"ok\":true}".toByteArray())
    }
}

/**
 * La revisión adversarial del 15-oct: el cliente vuelve a sacar la foto de una pose mientras la cola sube la vieja (la
 * cámara es otra app y al volver la app drena). La pasada borraba la clave al terminar bien con la VIEJA y se llevaba la
 * NUEVA; o la vieja terminaba después y el upsert la dejaba en el bucket. Las mismas pruebas que FotosMismaPoseTests.swift.
 */
class FotosMismaPoseTest {
    private val token = "tokenDePrueba_0000000000"
    private val vieja = byteArrayOf(0xFF.toByte(), 0xD8.toByte(), 0xFF.toByte(), 0xE0.toByte(), 0x01)
    private val nueva = byteArrayOf(0xFF.toByte(), 0xD8.toByte(), 0xFF.toByte(), 0xE0.toByte(), 0x02)

    private fun dataUrl(b: ByteArray) = "data:image/jpeg;base64," + Base64.getEncoder().encodeToString(b)

    @Test
    fun laNuevaQueNoSalioQuedaEnLaCola() = enUnHilo { alcance ->
        val s = ServicioConCompuerta("sinRed", "okDespuesDeLaCompuerta", "sinRed")
        val m = ModeloFotos(ClienteRpc(transporte = s), token, Disco(carpetaTemporal("fotos-misma-pose"), token))
        assertEquals(ModeloFotos.Resultado.SinConexion, m.subir("frente", vieja))
        val clave = "${m.semanaActual}|frente"
        val pasada = alcance.async { m.drenar() }
        while (s.cuantas() < 2) delay(5)
        val r = alcance.async { m.subir("frente", nueva) }
        esperarLaNueva(m, s, clave)
        s.abierta = true
        pasada.await()
        assertEquals(ModeloFotos.Resultado.SinConexion, r.await())
        assertEquals(dataUrl(nueva), m.pendientes.value[clave]?.dataUrl, "subir dijo que quedaba guardada y la pasada la borró")
    }

    @Test
    fun enElBucketQuedaLaNueva() = enUnHilo { alcance ->
        val s = ServicioConCompuerta("sinRed", "okDespuesDeLaCompuerta", "ok")
        val m = ModeloFotos(ClienteRpc(transporte = s), token, Disco(carpetaTemporal("fotos-misma-pose"), token))
        m.subir("frente", vieja)
        val clave = "${m.semanaActual}|frente"
        val pasada = alcance.async { m.drenar() }
        while (s.cuantas() < 2) delay(5)
        val r = alcance.async { m.subir("frente", nueva) }
        esperarLaNueva(m, s, clave)
        s.abierta = true
        pasada.await()
        assertEquals(ModeloFotos.Resultado.Guardada, r.await())
        assertEquals(dataUrl(nueva), s.guardada["frente"], "el bucket quedó con la foto vieja")
        assertTrue(m.pendientes.value.isEmpty())
    }

    /** Que la nueva ya esté en la cola esperando su turno (o, si no espera, que ya haya salido). */
    private suspend fun esperarLaNueva(m: ModeloFotos, s: ServicioConCompuerta, clave: String) {
        val tope = System.currentTimeMillis() + 5_000
        while (m.pendientes.value[clave]?.dataUrl != dataUrl(nueva) && s.cuantas() < 3 && System.currentTimeMillis() < tope) delay(5)
    }
}

/** El orden de `handleFotoUpload`: el tope (que SUMA el intento) va antes que el bucket. Con el storage caído se gasta igual. */
class ServicioConTope : Transporte {
    @Volatile var usados = 0
    @Volatile var bucketCaido = true

    override suspend fun enviar(pedido: Pedido): Respuesta = synchronized(this) {
        if (!pedido.ruta.endsWith("upload")) return Respuesta(200, "[]".toByteArray())
        if (usados >= 12) return Respuesta(429, "{\"ok\":false,\"error\":\"muchas fotos por hoy, probá mañana\"}".toByteArray())
        usados += 1
        if (bucketCaido) Respuesta(502, "{\"ok\":false,\"error\":\"no se pudo guardar la foto\"}".toByteArray())
        else Respuesta(200, "{\"ok\":true}".toByteArray())
    }
}

class FotosTopeTest {
    /**
     * Con dos en la cola, seis aperturas gastaban los 12 del día (revisión adversarial del 15-oct): después decía «Hoy ya
     * subiste muchas fotos» sin que hubiera entrado ninguna. Ahora el 5xx corta la pasada: seis aperturas, seis intentos.
     */
    @Test
    fun elStorageCaidoGastaUnIntentoPorApertura() = enUnHilo {
        val token = "tokenDePrueba_0000000000"
        val s = ServicioConTope()
        val disco = Disco(carpetaTemporal("fotos-tope"), token)
        val lunes = DiaCalendario.texto((DiaCalendario.numero(FotosProgreso.lunes(FechaLocal.hoy())) ?: 0L) - 7)
        val fecha = DiaCalendario.texto((DiaCalendario.numero(lunes) ?: 0L) + 3)
        val viejas = listOf("perfil", "espalda").associate { p -> "$lunes|$p" to FotoPendiente(p, fecha, "data:image/jpeg;base64,/9j/").aValor() }
        disco.guardar(FotoPendiente.ARCHIVO, ValorJson.Objeto(viejas))
        val m = ModeloFotos(ClienteRpc(transporte = s), token, disco)
        assertEquals(2, m.pendientes.value.size)
        repeat(6) { m.drenar() }
        assertEquals(6, s.usados, "cada apertura tiene que gastar un solo intento del día")
        assertEquals(2, m.pendientes.value.size, "con el storage caído no se pierde ninguna")
        s.bucketCaido = false
        assertEquals(ModeloFotos.Resultado.Guardada, m.subir("frente", byteArrayOf(0xFF.toByte(), 0xD8.toByte(), 0xFF.toByte(), 0xE0.toByte())))
    }
}
