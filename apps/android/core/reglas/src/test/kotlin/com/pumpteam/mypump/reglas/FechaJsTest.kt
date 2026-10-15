package com.pumpteam.mypump.reglas

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Test

/** Las fechas de Mi Día como las escribe la web (FechaJSTests de iOS). */
class FechaJsTest {
    /** `formatFechaLocal` de la web (node 26): "martes, 21 de julio" (DIA-01, "Último día válido"). */
    @Test
    fun diaLargoComoLaWeb() {
        assertEquals("martes, 21 de julio", FechaJs.diaLargo("2026-07-21"))
        assertEquals("miércoles, 14 de octubre", FechaJs.diaLargo("2026-10-14"))
        assertEquals("martes, 1 de septiembre", FechaJs.diaLargo("2026-09-01"))
        // `new Date(2026, 1, 31)` se desborda a marzo, como en node.
        assertEquals("martes, 3 de marzo", FechaJs.diaLargo("2026-02-31"))
        assertNull(FechaJs.diaLargo("no es fecha"))
    }
}
