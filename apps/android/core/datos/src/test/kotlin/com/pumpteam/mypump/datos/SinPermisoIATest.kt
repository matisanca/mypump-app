package com.pumpteam.mypump.datos

import com.pumpteam.mypump.modelos.ValorJson
import java.io.File
import java.io.IOException
import kotlinx.coroutines.CoroutineScope
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * Sin permiso para la IA (D7 se sacó el 14-oct, decisión de Mati: la IA trabaja bajo su aprobación y no es algo que el
 * cliente acepte), gemelo de SinPermisoIATests.swift. La app no pregunta ni lee nada, un "no" que quedó guardado en el
 * teléfono no frena la foto, y lo que quedó en una cola sale igual.
 */
class SinPermisoIATest {
    private class Estado {
        @Volatile var conRed = true
        @Volatile var visiones = 0
    }

    private fun modelo(e: Estado, raiz: File, alcance: CoroutineScope): Pair<ModeloApp, TransporteProgramado> {
        val t = TransporteProgramado { fn, _ ->
            if (!e.conRed) throw IOException("sin conexión a internet")
            when (fn) {
                "mypump_get_cliente_info" -> 200 to """[{"cliente_id":"c1","nombre":"Cliente","perfil":"natural"}]"""
                "mypump_get_rutina_activa" -> 200 to """[{"id":"r1","semana_actual":1,"estructura":{"dias":[]}}]"""
                "mypump_guardar_consentimiento_ia" -> 200 to "true"
                "vision" -> {
                    e.visiones++
                    200 to "{}"
                }
                else -> 200 to "[]"
            }
        }
        return ModeloApp(ClienteRpc(transporte = t), TokenEnMemoria(TOKEN), raiz, PreferenciasEnMemoria(), alcance) to t
    }

    @Test
    fun noSeLeePermisoYLaFotoSaleAunqueHayaQuedadoUnNo() = enUnHilo { alcance ->
        val e = Estado()
        val raiz = carpetaTemporal("sin-permiso-ia")
        // Lo que dejaba la app al decir que no, en la carpeta de la cuenta.
        val disco = Disco(raiz, TOKEN)
        disco.guardar(ARCHIVO_VIEJO, ValorJson.objeto("acepta" to ValorJson.Booleano(false)))
        val (m, t) = modelo(e, raiz, alcance)
        m.cargar()
        assertEquals(ModeloApp.Fase.LISTO, m.fase.value)
        assertTrue(t.llamadas.none { "consentimiento" in it }, "${t.llamadas}")
        m.analizarFoto(byteArrayOf(0xFF.toByte()), ClienteRpc.TipoVision.PLATO)
        assertEquals(1, e.visiones, "la foto no salió")
        // El archivo queda donde estaba: no se borra nada.
        assertTrue(disco.archivo(ARCHIVO_VIEJO).isFile)
    }

    @Test
    fun loQueQuedoEnLaColaSaleIgual() = enUnHilo { alcance ->
        val e = Estado()
        val (m, t) = modelo(e, carpetaTemporal("sin-permiso-ia"), alcance)
        m.cargar()
        val cola = m.outbox!!
        cola.encolar(
            "consentimiento_ia",
            ValorJson.objeto("acepta" to ValorJson.Booleano(false), "plataforma" to ValorJson.Texto("android")),
            "consentimiento_ia",
        )
        cola.drenar()
        assertEquals(0, cola.pendientes(), "quedó trabada en la cola")
        assertTrue(cola.fallidos().isEmpty())
        assertEquals(1, t.llamadas.count { it == "mypump_guardar_consentimiento_ia" })
    }

    /**
     * [ModeloApp.cargasConRed]: lo que espera la Fase R para reintentar después de un corte (`ArranqueMigracion`). Recargar
     * una cuenta ya cargada no pasa por CARGANDO, así que la fase sola no alcanzaba para darse cuenta.
     */
    @Test
    fun cadaCargaConRedSeCuenta() = enUnHilo { alcance ->
        val e = Estado()
        val (m, _) = modelo(e, carpetaTemporal("sin-permiso-ia"), alcance)
        m.cargar()
        assertEquals(1, m.cargasConRed.value)
        m.cargar()
        assertEquals(2, m.cargasConRed.value)
        e.conRed = false
        m.cargar()
        assertEquals(2, m.cargasConRed.value)
    }

    private companion object {
        const val TOKEN = "AAAAAAAAAAAAAAAAAAAA"

        /** Donde la app guardaba la decisión hasta el 14-oct. */
        const val ARCHIVO_VIEJO = "consentimiento-ia.json"
    }
}
