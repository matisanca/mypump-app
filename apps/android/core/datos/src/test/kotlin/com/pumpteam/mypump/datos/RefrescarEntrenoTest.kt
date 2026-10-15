package com.pumpteam.mypump.datos

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test

/**
 * Revisión del 15-oct, hallazgo 6 (gemelo de RefrescarEntrenoTests.swift): "tirar para actualizar" en Entreno llamaba a
 * `motor.cargar()`, que no pide `get_rutina_activa`: una rutina que Mati republicó no aparecía hasta reabrir la app. Dieta
 * ya lo hacía con la carga entera (`ModeloApp.cargar()`).
 */
class RefrescarEntrenoTest {
    private val raiz = carpetaTemporal("refrescar-entreno")

    /** La versión publicada (la regla del servidor corre fuera del hilo del test). */
    @Volatile private var publicada = 1 to "Press banca"

    private fun rutina(version: Int, ejercicio: String): String {
        val ej = """{"id":"press-d1-0","tipo":"principal","nombre":"$ejercicio","progresion":[{"semana":1,"series":3,"reps":"8","rir":2}]}"""
        return """[{"id":"rut-1","version":$version,"semana_actual":1,"tiene_siguiente":false,""" +
            """"estructura":{"semanas_total":12,"dias":[{"n":1,"id":"d1","nombre":"EMPUJE","bloques":[{"titulo":"A","ejercicios":[$ej]}]}]}}]"""
    }

    @Test
    fun laRutinaRepublicadaSeVeAlTirarParaActualizar() = enUnHilo { alcance ->
        val t = TransporteProgramado { fn, _ ->
            when (fn) {
                "mypump_get_cliente_info" -> 200 to """[{"cliente_id":"c1","nombre":"Cliente","perfil":"natural"}]"""
                "mypump_get_rutina_activa" -> publicada.let { (v, nombre) -> 200 to rutina(v, nombre) }
                else -> 200 to "[]"
            }
        }
        val m = ModeloApp(ClienteRpc(transporte = t), TokenEnMemoria(TOKEN), raiz, PreferenciasEnMemoria(), alcance)
        m.cargar()
        val e = m.entreno.value!!
        assertEquals(1, e.rutina.value.version)
        assertEquals("Press banca", e.dia.value.ejercicio("press-d1-0")?.nombre)

        // Mati cambia el ejercicio y republica.
        publicada = 2 to "Press inclinado con mancuernas"
        m.refrescarEntreno()
        val ahora = m.entreno.value!!
        assertEquals(2, ahora.rutina.value.version, "seguía la rutina de antes")
        assertEquals("Press inclinado con mancuernas", ahora.dia.value.ejercicio("press-d1-0")?.nombre)
        assertEquals(2, m.rutina.value?.version)
        // Y la copia offline quedó con la nueva.
        val copia = ModeloApp.CopiaOffline.desde(Disco(raiz, TOKEN).leer(ModeloApp.ARCHIVO_COPIA))
        assertEquals(2.0, copia?.rutina?.get("version")?.comoNumero)
    }

    private companion object {
        const val TOKEN = "AAAAAAAAAAAAAAAAAAAA"
    }
}
