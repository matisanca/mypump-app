package com.pumpteam.mypump.datos

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/** La tabla de `docs/NATIVA_CONTRATO.md` §1: qué gasta un intento de la cola y qué no. */
class ErrorRpcTest {
    @Test
    fun clasificaComoLaWeb() {
        assertEquals(ErrorRpc.Clase.RED, ErrorRpc.claseDe(0))
        for (s in listOf(500, 502, 503, 599, 429, 408)) assertEquals(ErrorRpc.Clase.TRANSITORIO, ErrorRpc.claseDe(s), "$s")
        for (s in listOf(400, 401, 403, 404, 409, 600)) assertEquals(ErrorRpc.Clase.PERMANENTE, ErrorRpc.claseDe(s), "$s")
    }

    @Test
    fun soloLoPermanenteGastaIntento() {
        assertFalse(ErrorRpc(ErrorRpc.Clase.RED, 0, mensaje = "sin señal").gastaIntento)
        assertFalse(ErrorRpc(ErrorRpc.Clase.TRANSITORIO, 503, mensaje = "ocupado").gastaIntento)
        assertTrue(ErrorRpc(ErrorRpc.Clase.PERMANENTE, 400, "P0001", "token invalido").gastaIntento)
        assertTrue(ErrorRpc(ErrorRpc.Clase.PERMANENTE, 404, "PGRST202", "no existe").funcionInexistente)
    }
}
