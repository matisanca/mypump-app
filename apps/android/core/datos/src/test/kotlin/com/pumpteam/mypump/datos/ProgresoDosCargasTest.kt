package com.pumpteam.mypump.datos

import com.pumpteam.mypump.modelos.RutinaActiva
import com.pumpteam.mypump.modelos.ValorJson
import com.pumpteam.mypump.reglas.ClaveEjercicio
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * La revisión adversarial del 15-oct: con las cuentas de Progreso fuera del hilo principal, una carga que entraba mientras la
 * anterior hacía las cuentas quedaba pisada por ellas: las tarjetas de una con el historial de la otra. Como
 * ProgresoDosCargasTests.swift.
 */
class ProgresoDosCargasTest {
    private fun rutina(nombres: List<String>): RutinaActiva {
        val ejs = nombres.mapIndexed { i, n ->
            """{"id":"e$i","tipo":"principal","nombre":"$n","progresion":[{"semana":1,"series":3,"reps":"8","rir":2}]}"""
        }.joinToString(",")
        val json = """{"id":"r","version":1,"semana_actual":1,"estructura":{"dias":[{"n":1,"id":"d1","nombre":"DIA","bloques":[{"titulo":"A","ejercicios":[$ejs]}]}]}}"""
        return RutinaActiva.desde(ValorJson.parsear(json).aJson())
    }

    private fun filas(nombres: List<String>, porEjercicio: Int): String = nombres.flatMap { n ->
        val c = ClaveEjercicio.de(n)
        (0 until porEjercicio).map { k ->
            val dia = String.format("2026-%02d-%02d %02d:00:00.123456+00", 1 + k % 9, 1 + k % 27, 8 + k % 10)
            """{"clave":"$c","registrado_en":"$dia","peso_kg":${40 + k % 30},"reps_realizadas":8,"rir_real":2,"serie_numero":1,"notas":null,"ejercicio_nombre":"$n"}"""
        }
    }.joinToString(",", "[", "]")

    @Test
    fun laQueEntraDuranteLasCuentasGana() = enUnHilo {
        val viejos = (0 until 60).map { "Viejo $it" }
        val respuestas = ArrayDeque(listOf(filas(viejos, 48), filas(listOf("Nuevo"), 3)))
        val t = TransporteProgramado { _, _ -> 200 to synchronized(respuestas) { respuestas.removeFirstOrNull() ?: "[]" } }
        val p = ModeloProgreso(ClienteRpc(transporte = t), "AAAAAAAAAAAAAAAAAAAA")
        var yaEntro = false
        p.antesDeLasCuentas = {
            if (!yaEntro) {
                yaEntro = true
                p.cargar(rutina(listOf("Nuevo")))
            }
        }
        p.cargar(rutina(viejos))
        val nuevo = ClaveEjercicio.de("Nuevo")
        assertEquals(listOf(nuevo), p.tarjetas.value.map { it.clave }, "las cuentas de la carga vieja pisaron a la nueva")
        assertEquals(setOf(nuevo), p.historialPorClave.value.keys)
        assertEquals(3, p.sesiones.value)
        assertEquals(ModeloProgreso.Estado.LISTO, p.estado.value)
    }
    /**
     * La tarjeta de progreso de Revisión y Salud → Fuerza piden solas: con una carga en camino, la segunda no sale (eran
     * dos pedidos iguales con todas las claves del plan). Con tarjetas tampoco; sin red, sí.
     */
    @Test
    fun siHaceFaltaNoPideDosVeces() = enUnHilo {
        var sinRed = false
        val t = TransporteProgramado { _, _ ->
            if (sinRed) throw java.io.IOException("sin conexión (prueba)")
            200 to filas(listOf("Uno"), 3)
        }
        fun pedidos() = t.llamadas.size
        val p = ModeloProgreso(ClienteRpc(transporte = t), "AAAAAAAAAAAAAAAAAAAA")
        val r = rutina(listOf("Uno"))
        p.antesDeLasCuentas = {
            p.antesDeLasCuentas = null
            assertEquals(true, p.cargando)
            p.cargarSiHaceFalta(r)
        }
        p.cargarSiHaceFalta(r)
        assertEquals(1, pedidos(), "con una carga en camino salió otra")
        assertEquals(false, p.cargando)
        assertEquals(listOf(ClaveEjercicio.de("Uno")), p.tarjetas.value.map { it.clave })
        p.cargarSiHaceFalta(r)
        assertEquals(1, pedidos(), "con tarjetas no hace falta")
        // Tirar para actualizar sí pide.
        sinRed = true
        p.cargar(r)
        val conCorte = pedidos()
        assertTrue(conCorte >= 2)
        assertEquals(ModeloProgreso.Estado.SIN_RED, p.estado.value)
        sinRed = false
        p.cargarSiHaceFalta(r)
        assertEquals(conCorte + 1, pedidos(), "sin red se vuelve a pedir")
        assertEquals(ModeloProgreso.Estado.LISTO, p.estado.value)
    }
}
