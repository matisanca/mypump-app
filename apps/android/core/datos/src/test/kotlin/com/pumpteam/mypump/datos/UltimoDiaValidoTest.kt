package com.pumpteam.mypump.datos

import com.pumpteam.mypump.reglas.FechaJs
import java.util.concurrent.atomic.AtomicReference
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Test

/**
 * DIA-01: `get_streak` trae `ultimo_dia_valido` y llega al modelo, para "Último día válido: martes, 21 de julio" como
 * `renderMydayStreak`. Antes se tiraba, y con una cuenta real la racha nunca decía el último día válido (como iOS, 9b023ea).
 */
class UltimoDiaValidoTest {
    @Test
    fun laRachaTraeSuUltimoDiaValido() = enUnHilo { alcance ->
        val racha = AtomicReference("""[{"streak":4,"ultimo_dia_valido":"2026-07-20"}]""")
        val t = TransporteProgramado { fn, _ -> if (fn == "mypump_get_streak") 200 to racha.get() else 200 to "[]" }
        val m = ModeloRevision(ClienteRpc(transporte = t), "tok", null, alcance)
        m.cargarMiDia()
        assertEquals(4, m.racha.value)
        assertEquals("2026-07-20", m.ultimoDiaValido.value)
        // Marcar el día vuelve a pedir la racha, con su último día válido.
        racha.set("""[{"streak":5,"ultimo_dia_valido":"2026-07-21"}]""")
        m.setHabito("entrenamiento", "entrene")
        assertEquals(5, m.racha.value)
        assertEquals("martes, 21 de julio", m.ultimoDiaValido.value?.let(FechaJs::diaLargo))
        // Sin fila no hay último día: la tarjeta dice "—".
        racha.set("[]")
        m.cargarMiDia()
        assertEquals(0, m.racha.value)
        assertNull(m.ultimoDiaValido.value)
    }
}
