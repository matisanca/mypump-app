package com.pumpteam.mypump.entreno

import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.sp
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * La espera del OK cuando vuelve el panel y el tope de la letra grande (2.3.3, S2), con un reloj que maneja la prueba. El caso
 * de Sebastián (19/11): escribió el peso, se cerró el teclado y el mismo toque registró la serie.
 */
class EsperaTecladoTest {
    private var ahora = 1_000L
    private val espera = EsperaTrasTeclado({ ahora })

    @Test
    fun sinTecladoElOKNoEspera() {
        espera.ver(false)
        assertTrue(espera.admite())
        espera.ver(false)
        assertTrue(espera.admite())
    }

    @Test
    fun conElPanelEscondidoNoAdmite() {
        espera.ver(true)
        assertFalse(espera.admite())
        ahora += 10_000
        assertFalse(espera.admite(), "escondido no registra nunca")
    }

    @Test
    fun alVolverEsperaMedioSegundo() {
        espera.ver(true)
        ahora = 5_000
        espera.ver(false)
        assertFalse(espera.admite(), "el toque que cerró el teclado")
        ahora = 5_000 + EsperaTrasTeclado.MS - 1
        assertFalse(espera.admite())
        ahora = 5_000 + EsperaTrasTeclado.MS
        assertTrue(espera.admite())
    }

    @Test
    fun recomponerSinCambiosNoReiniciaLaEspera() {
        espera.ver(true)
        ahora = 5_000
        espera.ver(false)
        ahora = 5_300
        espera.ver(false)   // otra composición con el panel a la vista: la espera sigue contando desde que volvió
        ahora = 5_500
        assertTrue(espera.admite())
    }

    @Test
    fun cadaVueltaArrancaOtraEspera() {
        espera.ver(true)
        espera.ver(false)
        ahora += 2_000
        assertTrue(espera.admite())
        espera.ver(true)
        ahora += 3_000
        espera.ver(false)
        assertFalse(espera.admite())
        ahora += EsperaTrasTeclado.MS
        assertTrue(espera.admite())
    }

    /** El kilo (46, 44 y 40) y la rueda (64 y 76) con la letra del teléfono: nunca más de 1,15 veces su tamaño. */
    @Test
    fun laLetraGrandeSeTopeaEn115() {
        for (escala in listOf(0.85f, 1f, 1.1f, 1.15f, 1.3f, 1.5f, 2f)) {
            val d = Density(2.625f, escala)
            for (base in listOf(40f, 44f, 46f, 64f, 76f)) {
                val final = with(d) { letraConTope(base.sp).toDp().value }
                val natural = with(d) { base.sp.toDp().value }
                assertTrue(final <= base * TOPE_LETRA + 0.05f, "$base sp a $escala: $final dp")
                assertEquals(minOf(natural, base * TOPE_LETRA), final, 0.05f, "$base sp a $escala")
            }
        }
    }

    @Test
    fun conLaLetraNormalNoCambia() {
        val d = Density(2.625f, 1f)
        assertEquals(46.sp, with(d) { letraConTope(46.sp) })
    }
}
