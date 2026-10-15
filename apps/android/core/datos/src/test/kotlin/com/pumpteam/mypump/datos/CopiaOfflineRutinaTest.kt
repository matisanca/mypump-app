package com.pumpteam.mypump.datos

import java.io.IOException
import kotlinx.coroutines.CoroutineScope
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * Revisión del 15-oct, hallazgo 1 (gemelo de CopiaOfflineRutinaTests.swift): después de "Pasar a semana" o "Empezar bloque
 * nuevo" la copia offline quedaba con la rutina vieja. Un arranque sin señal (en el gimnasio) volvía a la semana anterior
 * y lo que se cargaba iba a su sesión: `registrar_carga` es upsert por (sesión, ejercicio, serie) y pisaba las series de la
 * semana pasada. La web lo resuelve con `location.reload()`, que vuelve a guardar el snapshot.
 */
class CopiaOfflineRutinaTest {
    private val raiz = carpetaTemporal("copia-rutina")

    /** El servidor de las pruebas: la rutina activa y lo que falla (la regla del transporte corre fuera del hilo del test). */
    private class ServidorRutina(semana: Int, tieneSiguiente: Boolean = false) {
        @Volatile var semana = semana
        @Volatile var rutinaId = "rut-1"
        @Volatile var tieneSiguiente = tieneSiguiente
        @Volatile var sinRed = false
        @Volatile var rutinaFalla = false
    }

    private fun modelo(s: ServidorRutina, alcance: CoroutineScope): ModeloApp {
        val t = TransporteProgramado { fn, _ ->
            if (s.sinRed) throw IOException("sin conexión a internet")
            when (fn) {
                "mypump_get_cliente_info" -> 200 to """[{"cliente_id":"c1","nombre":"Cliente","perfil":"natural"}]"""
                "mypump_get_rutina_activa" -> {
                    if (s.rutinaFalla) throw IOException("se cortó la señal")
                    200 to "[${rutina(s.rutinaId, s.semana, s.tieneSiguiente)}]"
                }
                "mypump_avanzar_semana" -> {
                    s.semana += 1
                    200 to "${s.semana}"
                }
                "mypump_activar_siguiente" -> {
                    s.rutinaId = "rut-2"
                    s.semana = 1
                    s.tieneSiguiente = false
                    200 to "true"
                }
                else -> 200 to "[]"
            }
        }
        return ModeloApp(ClienteRpc(transporte = t), TokenEnMemoria(TOKEN), raiz, PreferenciasEnMemoria(), alcance)
    }

    /** La semana de la rutina que quedó en `offline.json`, o null si la copia no tiene rutina. */
    private fun semanaEnLaCopia(): Int? =
        ModeloApp.CopiaOffline.desde(Disco(raiz, TOKEN).leer(ModeloApp.ARCHIVO_COPIA))?.rutina?.get("semana_actual")?.comoNumero?.toInt()

    @Test
    fun pasarDeSemanaYArrancarSinSenalSigueEnLaNueva() = enUnHilo { alcance ->
        val s = ServidorRutina(semana = 5)
        val m = modelo(s, alcance)
        m.cargar()
        assertEquals(5, semanaEnLaCopia())
        assertEquals(ModeloEntreno.ResultadoAvance.Listo, m.entreno.value!!.avanzarSemana())
        assertTrue(m.entreno.value?.semana == 6 && m.rutina.value?.semanaActual == 6)
        assertEquals(6, semanaEnLaCopia(), "la copia offline quedaba en la 5")

        // Otro arranque, sin señal: tiene que seguir en la 6.
        s.sinRed = true
        val otro = modelo(s, alcance)
        otro.cargar()
        assertTrue(otro.desdeCache.value && otro.entreno.value?.semana == 6)
    }

    @Test
    fun siLaRutinaNoLlegaDespuesDeAvanzarIgualQuedaEnLaSemanaNueva() = enUnHilo { alcance ->
        val s = ServidorRutina(semana = 5)
        val m = modelo(s, alcance)
        m.cargar()
        s.rutinaFalla = true   // el servidor avanza, pero la rutina no llega
        assertEquals(ModeloEntreno.ResultadoAvance.Listo, m.entreno.value!!.avanzarSemana())
        assertEquals(6, s.semana)
        assertTrue(m.entreno.value?.semana == 6 && m.rutina.value?.semanaActual == 6, "se quedaba en la 5 con el servidor en la 6")
        assertEquals(6, semanaEnLaCopia())
    }

    @Test
    fun siElBloqueNuevoNoLlegaElViejoNoSePuedeSeguirCargando() = enUnHilo { alcance ->
        val s = ServidorRutina(semana = 12, tieneSiguiente = true)
        val m = modelo(s, alcance)
        m.cargar()
        val e = m.entreno.value!!
        assertTrue(e.puedeEmpezarBloque)
        s.rutinaFalla = true   // se activa el bloque nuevo, pero no llega
        assertEquals(ModeloEntreno.ResultadoAvance.Listo, e.empezarBloqueNuevo())
        assertFalse(e.usable.value, "el bloque archivado seguía para cargar")
        assertNull(semanaEnLaCopia(), "la copia offline seguía con el bloque archivado")

        // Sin señal, otro arranque no muestra el bloque viejo (la copia sigue, sin rutina); con señal llega el nuevo.
        s.sinRed = true
        val sinSenal = modelo(s, alcance)
        sinSenal.cargar()
        assertTrue(sinSenal.fase.value == ModeloApp.Fase.LISTO && sinSenal.desdeCache.value)
        assertNull(sinSenal.entreno.value)
        s.sinRed = false
        s.rutinaFalla = false
        val conSenal = modelo(s, alcance)
        conSenal.cargar()
        assertTrue(conSenal.rutina.value?.id == "rut-2" && conSenal.entreno.value?.semana == 1)
    }

    private companion object {
        const val TOKEN = "AAAAAAAAAAAAAAAAAAAA"

        fun rutina(id: String, semana: Int, tieneSiguiente: Boolean): String {
            val ej = """{"id":"press-d1-0","tipo":"principal","nombre":"Press banca","progresion":[{"semana":1,"series":3,"reps":"8","rir":2}]}"""
            return """{"id":"$id","version":1,"semana_actual":$semana,"tiene_siguiente":$tieneSiguiente,""" +
                """"estructura":{"semanas_total":12,"dias":[{"n":1,"id":"d1","nombre":"EMPUJE","bloques":[{"titulo":"A","ejercicios":[$ej]}]}]}}"""
        }
    }
}
