package com.pumpteam.mypump.datos

import com.pumpteam.mypump.modelos.ValorJson
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Test

/**
 * DIA-06 (RevisionDiaNuevoTests.unHabitoEnLaColaLeGanaAlServidor de iOS): lo que todavía está en la cola para HOY le gana
 * a lo que trae `get_habitos_dia` (la web pinta encima lo pendiente, cliente.html:6270-6276). También un "desmarcado"
 * (null). Lo de otro día en la cola no se mezcla.
 */
class HabitoEnLaColaTest {
    @Test
    fun unHabitoEnLaColaLeGanaAlServidor() = enUnHilo { alcance ->
        // El servidor dice 8 vasos y "entrené".
        val t = TransporteProgramado { fn, _ ->
            when (fn) {
                "mypump_get_habitos_dia" -> 200 to """[{"fecha":"2026-10-13","entrenamiento":"entrene","vasos_agua":8}]"""
                "mypump_get_streak" -> 200 to """[{"streak":3}]"""
                else -> 200 to "[]"
            }
        }
        // La cola no sale (sin red): lo encolado queda pendiente.
        val cola = Outbox(archivo = null, reintentoAutomatico = false, alcance = alcance) { _ ->
            ResultadoOp.Respuesta(Resultado.Falla(ErrorRpc(ErrorRpc.Clase.RED, 0, mensaje = "sin red")))
        }
        val m = ModeloRevision(ClienteRpc(transporte = t), "tok", cola, alcance)
        m.diaDeHoy = { "2026-10-13" }
        suspend fun pendiente(fecha: String, campo: String, valor: ValorJson) {
            cola.encolar("habito", ValorJson.objeto("fecha" to texto(fecha), "campo" to texto(campo), "valor" to valor), "habito|$fecha|$campo")
        }
        pendiente("2026-10-13", "vasos_agua", texto("3"))
        pendiente("2026-10-13", "entrenamiento", ValorJson.Nulo)
        pendiente("2026-10-12", "vasos_agua", texto("11"))
        m.cargarMiDia()
        assertEquals(3, m.habitos.value.vasosAgua)
        assertNull(m.habitos.value.entrenamiento)
    }
}
