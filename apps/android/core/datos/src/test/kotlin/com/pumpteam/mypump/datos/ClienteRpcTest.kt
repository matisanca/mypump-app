package com.pumpteam.mypump.datos

import com.pumpteam.mypump.modelos.ClienteInfo
import com.pumpteam.mypump.modelos.ValorJson
import com.sun.net.httpserver.HttpServer
import java.io.File
import java.io.IOException
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.util.concurrent.ConcurrentHashMap
import kotlinx.coroutines.runBlocking
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/** El cliente de PostgREST con las respuestas REALES grabadas, y el transporte de OkHttp contra un servidor local. */
class ClienteRpcTest {
    private fun llamar(fixture: String) = runBlocking { ClienteRpc(transporte = Grabado.de(fixture)).llamar("x", emptyMap()) }

    @Test
    fun lasRespuestasGrabadasSeClasificanComoEnIos() {
        assertEquals(Resultado.Ok(ValorJson.Nulo), llamar("token_invalido_escritura"))
        assertEquals(Resultado.Ok(ValorJson.Lista(emptyList())), llamar("token_invalido_lectura"))
        assertEquals(Resultado.Ok(ValorJson.Booleano(false)), llamar("boolean_false"))
        val p0001 = llamar("p0001").errorONull()!!
        assertEquals(ErrorRpc(ErrorRpc.Clase.PERMANENTE, 400, "P0001", "token invalido"), p0001)
        val tipo = llamar("tipo_invalido").errorONull()!!
        assertTrue(tipo.clase == ErrorRpc.Clase.PERMANENTE && tipo.codigo == "22P02" && tipo.gastaIntento)
        assertTrue(llamar("pgrst202").errorONull()!!.funcionInexistente)
    }

    @Test
    fun filasConNullEsListaVaciaYUnaFormaRaraEsDecode() = runBlocking {
        val vacio = ClienteRpc(transporte = Grabado.de("token_invalido_escritura")).filas("mypump_get_chat", emptyMap(), ClienteInfo::desde)
        assertEquals(Resultado.Ok(emptyList<ClienteInfo>()), vacio)
        val raro = ClienteRpc(transporte = Grabado(200, "{\"no\":\"es una lista\"}")).filas("mypump_get_cliente_info", emptyMap(), ClienteInfo::desde)
        val e = raro.errorONull()!!
        assertTrue(e.clase == ErrorRpc.Clase.PERMANENTE && e.codigo == "DECODE" && e.status == 200)
    }

    @Test
    fun unCuerpoQueNoEsJsonEnUnErrorSeRecortaA300Bytes() = runBlocking {
        val e = ClienteRpc(transporte = Grabado(502, "x".repeat(1000))).llamar("x", emptyMap()).errorONull()!!
        assertEquals(ErrorRpc.Clase.TRANSITORIO, e.clase)
        assertEquals(300, e.mensaje.length)
    }

    @Test
    fun laVisionDevuelveDataOElErrorDelServicio() = runBlocking {
        val jpeg = byteArrayOf(1, 2, 3)
        suspend fun vision(t: Transporte) = ClienteRpc(transporte = t).vision("tokenDePrueba_0000000000", ClienteRpc.TipoVision.PLATO, jpeg)
        assertEquals(Resultado.Ok(ValorJson.objeto("kcal" to numero(500))), vision(Grabado(200, "{\"ok\":true,\"data\":{\"kcal\":500}}")))
        assertEquals(
            ErrorRpc(ErrorRpc.Clase.PERMANENTE, 403, mensaje = "token inválido"),
            vision(Grabado(403, "{\"ok\":false,\"error\":\"token inválido\"}")).errorONull(),
        )
        assertEquals(ErrorRpc.Clase.TRANSITORIO, vision(Grabado(503, "{\"ok\":false}")).errorONull()!!.clase)
        assertEquals(ErrorRpc.Clase.RED, vision(PortalCautivo).errorONull()!!.clase)
        assertEquals(ErrorRpc(ErrorRpc.Clase.RED, 0, mensaje = "sin conexión"), vision(SinRed).errorONull())
        // Un 200 sin `ok` no es una lectura.
        assertEquals(ErrorRpc(ErrorRpc.Clase.PERMANENTE, 200, mensaje = "servicio no disponible"), vision(Grabado(200, "{}")).errorONull())
    }

    @Test
    fun okHttpContraUnServidorLocal() = runBlocking {
        val vistos = ConcurrentHashMap<String, String>()
        val servidor = HttpServer.create(InetSocketAddress("127.0.0.1", 0), 0)
        servidor.createContext("/rest/v1/rpc/") { x ->
            vistos["ruta"] = x.requestURI.path
            vistos["metodo"] = x.requestMethod
            vistos["apikey"] = x.requestHeaders.getFirst("apikey") ?: ""
            vistos["auth"] = x.requestHeaders.getFirst("Authorization") ?: ""
            vistos["cuerpo"] = x.requestBody.readBytes().toString(Charsets.UTF_8)
            val (status, cuerpo) = when (x.requestURI.path.substringAfterLast('/')) {
                "lento" -> {
                    Thread.sleep(1_500)
                    200 to "[]"
                }
                "vacio" -> 204 to ""
                "falla" -> 400 to "{\"code\":\"P0001\",\"message\":\"token invalido\"}"
                else -> 200 to "[{\"cliente_id\":\"c1\",\"nombre\":\"Ñandú\",\"perfil\":null}]"
            }
            val bytes = cuerpo.toByteArray()
            x.sendResponseHeaders(status, if (bytes.isEmpty()) -1 else bytes.size.toLong())
            if (bytes.isNotEmpty()) x.responseBody.use { it.write(bytes) } else x.close()
        }
        servidor.start()
        try {
            val base = "http://127.0.0.1:${servidor.address.port}"
            val config = ConfigBackend(supabase = base, anonKey = "anon-de-prueba", vision = base, app = base)
            val cliente = ClienteRpc(config = config, esperaMs = 800)
            val r = cliente.llamar("mypump_get_cliente_info", mapOf("p_token" to texto("tok"), "p_n" to numero(1.5)))
            assertEquals("Ñandú", (r.valorONull() as ValorJson.Lista).elementos.first()["nombre"]?.comoTexto)
            assertEquals("/rest/v1/rpc/mypump_get_cliente_info", vistos["ruta"])
            assertEquals("POST", vistos["metodo"])
            assertEquals("anon-de-prueba", vistos["apikey"])
            assertEquals("Bearer anon-de-prueba", vistos["auth"])
            assertEquals(ValorJson.objeto("p_token" to texto("tok"), "p_n" to numero(1.5)), ValorJson.parsear(vistos["cuerpo"]!!))
            assertEquals(Resultado.Ok(ValorJson.Nulo), cliente.llamar("vacio", emptyMap()))
            assertEquals("P0001", cliente.llamar("falla", emptyMap()).errorONull()?.codigo)
            // Pasado el tiempo de la llamada es falta de red: no gasta intento.
            assertEquals(ErrorRpc.Clase.RED, cliente.llamar("lento", emptyMap()).errorONull()?.clase)
        } finally {
            servidor.stop(0)
        }
        // Nadie escuchando: falta de red.
        val libre = ServerSocket(0).use { it.localPort }
        val sinNadie = ClienteRpc(config = ConfigBackend("http://127.0.0.1:$libre", "x", "http://127.0.0.1:$libre", "x"))
        assertEquals(ErrorRpc.Clase.RED, sinNadie.llamar("x", emptyMap()).errorONull()?.clase)
    }
}

/** Los archivos por cuenta (T1): carpeta con el hash del token y escritura atómica. */
class DiscoTest {
    @Test
    fun unaCarpetaPorCuentaComoIos() {
        val raiz = carpetaTemporal("disco")
        // SHA-256("abc") = ba7816bf8f01cfea…: la misma carpeta que arma Disco.swift.
        assertEquals(File(raiz, "MyPump/cuenta-ba7816bf8f01cfea"), Disco(raiz, "abc").carpeta)
        assertFalse(Disco(raiz, "a").carpeta == Disco(raiz, "b").carpeta)
    }

    @Test
    fun guardaLeeYNoDejaTemporales() {
        val d = Disco(carpetaTemporal("disco"), "tokenDePrueba_0000000000")
        assertEquals(null, d.leer("nada.json"))
        assertTrue(d.guardar("a.json", ValorJson.objeto("x" to numero(1))))
        assertTrue(d.guardar("a.json", ValorJson.objeto("x" to numero(2))))
        assertEquals(ValorJson.objeto("x" to numero(2)), ValorJson.desde(d.leer("a.json")!!))
        assertEquals(listOf("a.json"), d.carpeta.list()!!.toList())
        // Un archivo roto vale como que no está (no tira).
        d.archivo("roto.json").writeText("{\"x\":")
        assertEquals(null, d.leer("roto.json"))
        d.borrar("a.json")
        assertEquals(null, d.leer("a.json"))
    }

    @Test
    fun sinPermisoDeEscrituraDevuelveFalse() {
        val raiz = carpetaTemporal("disco")
        val d = Disco(raiz, "tokenDePrueba_0000000000")
        d.carpeta.mkdirs()
        d.carpeta.setWritable(false)
        try {
            assertFalse(d.guardar("a.json", ValorJson.Nulo))
        } finally {
            d.carpeta.setWritable(true)
        }
    }

    @Test
    fun unTransporteQueTiraNoEsUnaExcepcionParaQuienLlama() = runBlocking {
        val r = ClienteRpc(transporte = { throw IOException("x") }).llamar("x", emptyMap())
        assertEquals(ErrorRpc.Clase.RED, r.errorONull()?.clase)
    }
}
