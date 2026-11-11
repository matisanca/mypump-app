package com.pumpteam.mypump.avisos

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * Auditoría del 10/11, F8: con la pantalla apagada una sola alarma inexacta para el fin del descanso podía sonar hasta un
 * minuto tarde. Se simula el peor caso del sistema (cada alarma suena al principio o al final de su margen) y el aviso
 * tiene que salir en el segundo, con pocas alarmas.
 */
class SaltosDescansoTest {
    /** Corre la cadena: `tarde` elige, para cada alarma, si el sistema la toca al principio (0) o al final (1) del margen. */
    private fun simular(descansoMs: Long, tarde: (Int) -> Double): Pair<Long, Int> {
        val fin = 1_000_000L + descansoMs
        var ahora = 1_000_000L
        var alarmas = 0
        while (true) {
            val proximo = SaltosDescanso.proximo(ahora, fin) ?: return (maxOf(ahora, fin) - fin) to alarmas
            val pedido = proximo - ahora
            assertTrue(pedido >= SaltosDescanso.FUTURO_MINIMO_MS, "nunca menos de lo que el sistema deja")
            val suena = proximo + (SaltosDescanso.margenDelSistema(pedido) * tarde(alarmas)).toLong()
            assertTrue(suena < fin, "una alarma de la cadena sonó después del fin: ${suena - fin} ms")
            ahora = suena
            alarmas++
        }
    }

    @Test
    fun antesHabiaUnMinutoDeAtraso() {
        // La alarma vieja: una sola, para el fin, con todo el margen.
        assertEquals(67_500L, SaltosDescanso.margenDelSistema(90_000L))
    }

    @Test
    fun avisaEnElSegundoConPocasAlarmas() {
        for (descanso in listOf(9_000L, 15_000L, 30_000L, 60_000L, 90_000L, 120_000L, 180_000L, 300_000L)) {
            for (modo in listOf<(Int) -> Double>({ 0.0 }, { 1.0 }, { if (it % 2 == 0) 1.0 else 0.0 }, { 0.5 })) {
                val (atraso, alarmas) = simular(descanso, modo)
                assertEquals(0L, atraso, "descanso de $descanso ms")
                val tope = if (descanso <= 90_000L) 4 else if (descanso <= 180_000L) 5 else 6
                assertTrue(alarmas <= tope, "descanso de $descanso ms: $alarmas alarmas")
            }
        }
    }

    @Test
    fun conPocoTiempoSeEsperaEnElReceptor() {
        assertNull(SaltosDescanso.proximo(0, SaltosDescanso.ESPERA_FINAL_MS))
        assertTrue(SaltosDescanso.ESPERA_FINAL_MS < 10_000L, "el receptor no puede esperar más de 10 s")
    }
}
