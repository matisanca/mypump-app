package com.pumpteam.mypump.datos

import com.pumpteam.mypump.modelos.ValorJson
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * Gemelo de ArreglosAuditoriaColaTests y ArreglosAuditoriaFotosTests (Swift). Auditoría del 10/11, F5: lo que el servidor
 * rechazaba se abandonaba en más o menos un minuto, con un cartel de 9 segundos y sin lugar para reintentarlo. F6: una foto
 * de progreso rechazada al subirse sola se borraba sin avisar.
 */
class ArreglosAuditoriaColaTest {
    @Test
    fun rechazadaSeSigueIntentandoYDespuesSeReintentaAMano() = enUnHilo { alcance ->
        var ms = 1_000_000L
        var rechaza = true
        val cola = Outbox(archivo = null, ventanaAbandonoMs = 30 * 60 * 1000, reintentoAutomatico = false, alcance = alcance, reloj = { ms }) {
            if (rechaza) ResultadoOp.Respuesta(Resultado.Falla(ErrorRpc(ErrorRpc.Clase.PERMANENTE, 400, "PGRST202", "boom")))
            else ResultadoOp.Respuesta(Resultado.Ok(ValorJson.Texto("ok")))
        }
        cola.encolar("carga", ValorJson.objeto("x" to ValorJson.Numero(1.0)), "k1")
        repeat(12) {
            cola.drenar()
            ms += 1000
        }
        assertEquals(1, cola.pendientes(), "con 12 rechazos en 12 segundos sigue en la cola")
        assertTrue(cola.perdidos().isEmpty())
        ms += 31 * 60 * 1000
        cola.drenar()
        assertEquals(0, cola.pendientes())
        assertEquals(1, cola.perdidos().size, "pasada la ventana queda en «No se pudo guardar»")
        rechaza = false
        assertEquals(1, cola.reintentarPerdidos())
        assertEquals(0, cola.operaciones().first().tries)
        cola.drenar()
        assertEquals(0, cola.pendientes())
        assertTrue(cola.perdidos().isEmpty())
    }

    @Test
    fun fotoRechazadaEnLaColaNoSeBorraEnSilencio() = enUnHilo { _ ->
        val raiz = carpetaTemporal("fotos-rechazo")
        val token = "tokenDePrueba_0000000000"
        val disco = Disco(raiz, token)
        val clave = "2026-11-02|frente"
        disco.guardar(FotoPendiente.ARCHIVO, ValorJson.objeto(clave to FotoPendiente("frente", "2026-11-03", "data:image/jpeg;base64,/9j/").aValor()))
        val g = Guion(400 to """{"ok":false,"error":"fecha fuera de rango"}""", 200 to """{"ok":true}""")
        val m = ModeloFotos(ClienteRpc(transporte = g), token, disco)
        m.drenar()
        assertTrue(m.pendientes.value.isEmpty())
        assertEquals("fecha fuera de rango", m.rechazadas.value[clave]?.motivo)
        assertNotNull(ModeloFotos(ClienteRpc(transporte = g), token, disco).rechazadas.value[clave], "sobrevive a cerrar la app")
        m.reintentarRechazada(clave)
        assertTrue(m.rechazadas.value.isEmpty() && m.pendientes.value.isEmpty())
        assertEquals(2, g.pedidos.count { it.endsWith("upload") })
    }
}
