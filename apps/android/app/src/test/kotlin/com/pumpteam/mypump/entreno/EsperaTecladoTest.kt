package com.pumpteam.mypump.entreno

import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * La espera del OK cuando vuelve el panel (2.3.3, S2), con un reloj que maneja la prueba. El caso
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

}
