package com.pumpteam.mypump.datos

import kotlinx.coroutines.runBlocking
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Assumptions.assumeTrue
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.Test

/**
 * La `nativa_001` contra el backend REAL (está aplicada desde 2486bb0), con la cuenta `test-nativa-android`. Solo lecturas
 * y llamadas que el servidor rechaza sin guardar nada: un recibo de verdad dejaría una fila de una migración que no
 * existió. El token sale del registro privado y no se imprime.
 */
class ServidorMigracionIntegracionTest {
    private lateinit var token: String

    @BeforeEach
    fun cuenta() {
        val t = IntegracionTest.tokenDePrueba()
        assumeTrue(t != null, "sin el registro privado de cuentas de prueba")
        token = t!!
    }

    private fun recibo(corrida: Int, plataforma: String = "android") = ReciboLegado(
        migracion = "0b5c6c1e-0000-4000-8000-00000000a0d1", corrida = corrida, fecha = "2026-10-14T12:00:00Z", plataforma = plataforma,
        app = "prueba", antes = ConteosLegado(), despues = ConteosNativos(), cliente = "test-nativa-android",
    )

    @Test
    fun laPalancaContesta() = runBlocking {
        // La tabla existe y trae las cinco claves (con lo que esté puesto: no se compara con lo de fábrica).
        val r = ClienteRpc().llamar("mypump_get_app_config", emptyMap())
        val claves = ((r as? Resultado.Ok)?.valor as? com.pumpteam.mypump.modelos.ValorJson.Objeto)?.campos?.keys
        assertNotNull(claves, "mypump_get_app_config no contestó un objeto: $r")
        assertTrue(claves!!.containsAll(listOf("migracion_ops_legadas", "migracion_escritura_vuelta", "anclaje_borra_swaps",
            "version_minima_ios", "version_minima_android")), "$claves")
        assertNotNull(PalancaRemota.leer(ClienteRpc()))
    }

    @Test
    fun losConteosDeLaCuentaDePrueba() = runBlocking {
        val c = ConteosRpc(ClienteRpc()).contar(token)
        assertNotNull(c, "mypump_conteos_cliente no contestó")
        assertTrue(c!!.keys.containsAll(listOf("sesiones", "registros_carga", "salud_diaria", "food_swaps")), "${c.keys}")
        assertTrue(c.values.all { it >= 0 })
        assertNull(ConteosRpc(ClienteRpc()).contar("no-es-un-token-de-nadie-000000"))   // token caído: null, no un error
    }

    @Test
    fun unReciboMalFormadoSeRechazaSinGuardarse() = runBlocking {
        // Corrida fuera de rango y plataforma inválida: 22023, que es "no insistir" (rechazado), y nada se inserta.
        assertEquals(ReciboEnServidor.Respuesta.RECHAZADO, ReciboEnServidor.mandar(recibo(10_001), token, ClienteRpc()))
        assertEquals(ReciboEnServidor.Respuesta.RECHAZADO, ReciboEnServidor.mandar(recibo(0, plataforma = "web"), token, ClienteRpc()))
        // Con un token que no es de nadie la base devuelve null: se reintenta (y tampoco guarda nada).
        assertEquals(ReciboEnServidor.Respuesta.REINTENTAR, ReciboEnServidor.mandar(recibo(0), "no-es-un-token-de-nadie-000000", ClienteRpc()))
    }
}
