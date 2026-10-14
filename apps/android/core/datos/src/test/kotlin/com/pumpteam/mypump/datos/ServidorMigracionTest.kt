package com.pumpteam.mypump.datos

import com.pumpteam.mypump.modelos.ValorJson
import java.io.File
import java.io.IOException
import kotlinx.coroutines.runBlocking
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * La `nativa_001` del lado de la app (ServidorMigracionTests.swift): el recibo, los conteos y la palanca remota. Antes de
 * que se aplique en la base, la app tiene que seguir igual que hoy (PGRST202). Después tiene que confirmar el recibo,
 * reenviar lo que quedó en el disco y respetar la palanca.
 */
class ServidorMigracionTest {
    private val carpeta: File = carpetaTemporal("recibos")
    private val noExiste = 404 to """{"code":"PGRST202","message":"Could not find the function"}"""

    private fun recibo(corrida: Int, cliente: String = "c1") = ReciboLegado(
        migracion = "0b5c6c1e-0000-4000-8000-000000000001", corrida = corrida, fecha = "2026-10-14T12:00:00Z", plataforma = "android",
        app = "2.0.0", antes = ConteosLegado(), despues = ConteosNativos(), cliente = cliente,
    )

    private fun cliente(responder: suspend (String, ValorJson) -> Pair<Int, String>): Pair<ClienteRpc, TransporteProgramado> {
        val t = TransporteProgramado(responder)
        return ClienteRpc(transporte = t) to t
    }

    private fun esta(corrida: Int, en: String? = null): Boolean = File(en?.let { File(carpeta, it) } ?: carpeta, "recibo-$corrida.json").isFile

    @Test
    fun confirmadoPasaAEnviados() = runBlocking {
        val (c, t) = cliente { _, cuerpo ->
            if (cuerpo["p_recibo"]?.get("cliente") == ValorJson.Texto("c1") && cuerpo["p_corrida"] == ValorJson.Numero(0.0) &&
                cuerpo["p_recibo"]?.get("plataforma") == ValorJson.Texto("android") && cuerpo["p_migracion"]?.comoTexto == "0b5c6c1e-0000-4000-8000-000000000001"
            ) {
                200 to "true"
            } else {
                400 to "{}"
            }
        }
        assertEquals(EntregaRecibo.CONFIRMADO, ReciboEnServidor(c, carpeta).enviar(recibo(0), "tok"))
        assertEquals(listOf("mypump_registrar_migracion_nativa"), t.llamadas)
        assertTrue(esta(0, "enviados") && !esta(0))
    }

    @Test
    fun sinLaRpcQuedaEnElDiscoYSeReenviaCuandoExiste() = runBlocking {
        val (antes, _) = cliente { _, _ -> noExiste }
        assertEquals(EntregaRecibo.SOLO_LOCAL, ReciboEnServidor(antes, carpeta).enviar(recibo(0), "tok"))
        assertTrue(esta(0))
        assertEquals(0, ReciboEnServidor.reenviar(carpeta, "tok", "c1", antes))
        assertTrue(esta(0))
        val (despues, _) = cliente { _, _ -> 200 to "true" }
        assertEquals(1, ReciboEnServidor.reenviar(carpeta, "tok", "c1", despues))
        assertTrue(esta(0, "enviados") && !esta(0))
        assertFalse(ReciboEnServidor.hayPendientes(carpeta))
    }

    @Test
    fun rechazadoNoSeInsiste() = runBlocking {
        val (c, _) = cliente { _, _ -> 200 to "false" }
        assertEquals(EntregaRecibo.SOLO_LOCAL, ReciboEnServidor(c, carpeta).enviar(recibo(0), "tok"))
        assertTrue(esta(0, "rechazados") && !esta(0))
        val (mal, _) = cliente { _, _ -> 400 to """{"code":"22023","message":"recibo inválido"}""" }
        assertEquals(EntregaRecibo.SOLO_LOCAL, ReciboEnServidor(mal, carpeta).enviar(recibo(1), "tok"))
        assertTrue(esta(1, "rechazados"))
    }

    @Test
    fun tokenCaidoOSinRedSeReintenta() = runBlocking {
        val (caido, _) = cliente { _, _ -> 200 to "null" }
        assertEquals(EntregaRecibo.SOLO_LOCAL, ReciboEnServidor(caido, carpeta).enviar(recibo(0), "tok"))
        val (sinRed, _) = cliente { _, _ -> throw IOException("sin conexión a internet") }
        assertEquals(EntregaRecibo.SOLO_LOCAL, ReciboEnServidor(sinRed, carpeta).enviar(recibo(1), "tok"))
        assertTrue(esta(0) && esta(1))
    }

    /** Sin la RPC (o sin red) el reenvío corta en el primero: los demás tampoco van a entrar. */
    @Test
    fun elReenvioCortaEnElPrimeroQueNoSePudoMandar() = runBlocking {
        val (sin, t) = cliente { _, _ -> noExiste }
        for (corrida in 0..2) ReciboEnServidor(sin, carpeta).enviar(recibo(corrida), "tok")
        assertEquals(3, t.llamadas.size)
        assertEquals(0, ReciboEnServidor.reenviar(carpeta, "tok", "c1", sin))
        assertEquals(4, t.llamadas.size)
        assertTrue(esta(0) && esta(1) && esta(2) && ReciboEnServidor.hayPendientes(carpeta))
    }

    @Test
    fun elReenvioSoloMandaLosDeEsaCuenta() = runBlocking {
        val (sin, _) = cliente { _, _ -> noExiste }
        for ((corrida, cuenta) in listOf(0 to "c1", 1 to "c1", 2 to "c2")) ReciboEnServidor(sin, carpeta).enviar(recibo(corrida, cuenta), "tok")
        val (c, t) = cliente { _, _ -> 200 to "true" }
        assertEquals(2, ReciboEnServidor.reenviar(carpeta, "tok", "c1", c))
        assertEquals(2, t.llamadas.size)
        assertTrue(esta(2) && esta(0, "enviados") && esta(1, "enviados"))
    }

    /** El recibo que queda en el disco se lee de vuelta igual (lo que se reenvía es lo mismo que se armó). */
    @Test
    fun elReciboVaYVuelveDelDisco() = runBlocking {
        val r = recibo(4).copy(
            antes = ConteosLegado(claves = 12, opsPorKind = linkedMapOf("carga" to 3)), despues = ConteosNativos(libro = mapOf("cola" to 3), fallidos = 1),
            servidorAntes = mapOf("sesiones" to 2), servidorDespues = mapOf("sesiones" to 3),
        )
        ReciboEnDisco(carpeta).enviar(r, "tok")
        assertEquals(r, ReciboLegado.desde(leerJson(File(carpeta, "recibo-4.json"))?.let(ValorJson::desde)))
    }

    @Test
    fun conteos() = runBlocking {
        val (c, _) = cliente { _, _ -> 200 to """{"sesiones":12,"registros_carga":340,"peso_manual":0}""" }
        assertEquals(mapOf("sesiones" to 12, "registros_carga" to 340, "peso_manual" to 0), ConteosRpc(c).contar("tok"))
        val (caido, _) = cliente { _, _ -> 200 to "null" }
        assertNull(ConteosRpc(caido).contar("tok"))
        val (sin, _) = cliente { _, _ -> noExiste }
        assertNull(ConteosRpc(sin).contar("tok"))
    }

    @Test
    fun palanca() = runBlocking {
        val (c, t) = cliente { _, _ ->
            200 to """{"migracion_ops_legadas":false,"migracion_escritura_vuelta":true,"anclaje_borra_swaps":false,"version_minima_ios":"2.0.3","version_minima_android":null}"""
        }
        val p = PalancaRemota.leer(c)
        assertEquals(listOf("mypump_get_app_config"), t.llamadas)
        assertTrue(p?.opsLegadas == false && p.escrituraVuelta && !p.anclajeBorraSwaps)
        assertTrue(p?.versionMinimaIOS == "2.0.3" && p.versionMinimaAndroid == null)
        val (sin, _) = cliente { _, _ -> noExiste }
        assertEquals(PalancaRemota.deFabrica, PalancaRemota.leer(sin))
        val (sinRed, _) = cliente { _, _ -> throw IOException("timeout") }
        assertNull(PalancaRemota.leer(sinRed))
        val (raro, _) = cliente { _, _ -> 200 to """{"migracion_ops_legadas":"no","version_minima_ios":3}""" }
        assertEquals(PalancaRemota.deFabrica, PalancaRemota.leer(raro))   // un valor de otro tipo no cuenta
        val (android, _) = cliente { _, _ -> 200 to """{"version_minima_android":"2.1.0","version_minima_ios":""}""" }
        assertEquals(PalancaRemota(versionMinimaAndroid = "2.1.0"), PalancaRemota.leer(android))
        // Un 500 no es un "no": quien llama decide si espera (null), como sin red.
        val (caido, _) = cliente { _, _ -> 503 to """{"message":"caído"}""" }
        assertNull(PalancaRemota.leer(caido))
    }

    @Test
    fun versionMinima() {
        assertTrue(PalancaRemota.debajo("2.0.0", "2.0.3"))
        assertTrue(PalancaRemota.debajo("2.0.9", "2.0.10"))
        assertFalse(PalancaRemota.debajo("2.0.10", "2.0.9"))
        assertFalse(PalancaRemota.debajo("2.0.3", "2.0.3"))
        assertFalse(PalancaRemota.debajo("2.1", "2.0.3"))
        assertFalse(PalancaRemota.debajo("2.0.0", null))
        assertFalse(PalancaRemota.debajo(null, "2.0.3"))
        assertTrue(PalancaRemota.debajo("2.0", "2.0.1"))
        assertTrue(PalancaRemota.debajo("2.0.0-beta", "2.0.1"))   // lo que no es un número vale 0
        assertFalse(PalancaRemota.debajo("3000000000.0", "2.0"))   // números que no entran en un Int de 32 bits
    }

    @Test
    fun elModeloLeeLaPalancaAlCargar() = enUnHilo { alcance ->
        val t = TransporteProgramado { fn, _ ->
            when (fn) {
                "mypump_get_cliente_info" -> 200 to """[{"cliente_id":"c1","nombre":"Cliente","perfil":"natural"}]"""
                "mypump_get_app_config" -> 200 to """{"anclaje_borra_swaps":false}"""
                else -> 200 to "[]"
            }
        }
        val m = ModeloApp(ClienteRpc(transporte = t), TokenEnMemoria("AAAAAAAAAAAAAAAAAAAA"), carpetaTemporal("palanca"), PreferenciasEnMemoria(), alcance)
        m.cargar()
        assertEquals(ModeloApp.Fase.LISTO, m.fase.value)
        assertTrue(!m.palanca.value.anclajeBorraSwaps && m.palanca.value.opsLegadas)
    }

    /**
     * `anclaje_borra_swaps = false` llega a la hidratación de la dieta: un swap anclado al pan que ya no coincide (Mati
     * agregó un yogur antes) se oculta pero NO se borra del servidor. Con la palanca de fábrica, se borra.
     */
    @Test
    fun laPalancaDelAnclajeLlegaALaHidratacion() {
        for (borra in listOf(true, false)) {
            enUnHilo { alcance ->
                val dieta = """[{"id":"d1","version":1,"estructura":{"comidas":[{"id":"c2","name":"Desayuno","options":[{"name":"A","foods":[
                    {"name":"Yogur","qty":200,"unit":"g","kcal":100,"prot":1,"carb":1,"fat":1},
                    {"name":"Café","qty":200,"unit":"ml","kcal":100,"prot":1,"carb":1,"fat":1},
                    {"name":"Pan lactal","qty":60,"unit":"g","kcal":100,"prot":1,"carb":1,"fat":1}]}]}]}}]"""
                val swap = """[{"comida_id":"c2","opt_idx":0,"food_idx":1,"food_data":{"name":"Arroz","qty":80,"unit":"g","kcal":100,"_orig":{"name":"Pan lactal","qty":60,"unit":"g"}}}]"""
                val t = TransporteProgramado { fn, _ ->
                    when (fn) {
                        "mypump_get_cliente_info" -> 200 to """[{"cliente_id":"c1","nombre":"Cliente","perfil":"natural"}]"""
                        "mypump_get_app_config" -> 200 to """{"anclaje_borra_swaps":$borra}"""
                        "mypump_get_dieta_activa" -> 200 to dieta
                        "mypump_get_food_swaps" -> 200 to swap
                        "mypump_delete_food_swap" -> 200 to "true"
                        else -> 200 to "[]"
                    }
                }
                val m = ModeloApp(ClienteRpc(transporte = t), TokenEnMemoria("AAAAAAAAAAAAAAAAAAAA"), carpetaTemporal("anclaje"), PreferenciasEnMemoria(), alcance)
                m.cargar()
                assertEquals(borra, "mypump_delete_food_swap" in t.llamadas, "palanca $borra")
                assertEquals(!borra, "swap_d1_c2_0_1" in m.swaps.value, "palanca $borra")
            }
        }
    }

    /** Sin la tabla (PGRST202) o sin red, la palanca queda como estaba: la de fábrica, o la última que se leyó. */
    @Test
    fun sinRespuestaLaPalancaNoCambia() = enUnHilo { alcance ->
        var config: Pair<Int, String> = 200 to """{"anclaje_borra_swaps":false}"""
        val t = TransporteProgramado { fn, _ ->
            when (fn) {
                "mypump_get_cliente_info" -> 200 to """[{"cliente_id":"c1","nombre":"Cliente","perfil":"natural"}]"""
                "mypump_get_app_config" -> config
                else -> 200 to "[]"
            }
        }
        val m = ModeloApp(ClienteRpc(transporte = t), TokenEnMemoria("AAAAAAAAAAAAAAAAAAAA"), carpetaTemporal("palanca"), PreferenciasEnMemoria(), alcance)
        m.cargar()
        assertFalse(m.palanca.value.anclajeBorraSwaps)
        config = 503 to """{"message":"caído"}"""
        m.cargar()
        assertFalse(m.palanca.value.anclajeBorraSwaps)   // un corte no la resetea
        config = noExiste
        m.cargar()
        assertEquals(PalancaRemota.deFabrica, m.palanca.value)   // sin la tabla: lo de fábrica
    }
}
