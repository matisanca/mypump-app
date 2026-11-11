package com.pumpteam.mypump.reglas

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Test
import java.time.Instant

class DondeEntrenoTest {
    private val dev = DevolucionTecnica("Mati", null, emptyList(), emptyList(), emptyList(), null)
    private fun envio(id: String, estado: EnvioTecnica.Estado, en: String?, d: DevolucionTecnica? = dev) =
        EnvioTecnica(id, estado, "s", "Sentadilla", publicadoEn = en, devolucion = d)

    @Test
    fun tituloYBajadaSegunLoQueHay() {
        assertEquals("Mi gimnasio y mi técnica", DondeEntreno.titulo(gimnasio = true, tecnica = true))
        assertEquals("Mi gimnasio", DondeEntreno.titulo(gimnasio = true, tecnica = false))
        assertEquals("Mi técnica", DondeEntreno.titulo(gimnasio = false, tecnica = true))
        assertNull(DondeEntreno.titulo(gimnasio = false, tecnica = false))
        assertEquals("Tus videos y lo que te respondió Mati", DondeEntreno.bajada(gimnasio = false, tecnica = true))
        assertNull(DondeEntreno.bajada(gimnasio = false, tecnica = false))
    }

    @Test
    fun laRespuestaRecienteEsLaMasNuevaDeLosUltimos7Dias() {
        val ahora = Instant.parse("2026-11-11T12:00:00Z")
        val vieja = envio("a", EnvioTecnica.Estado.PUBLICADO, "2026-11-01T12:00:00Z")
        val nueva = envio("b", EnvioTecnica.Estado.PUBLICADO, "2026-11-10T12:00:00Z")
        val media = envio("c", EnvioTecnica.Estado.PUBLICADO, "2026-11-08T12:00:00-03:00")
        val enviado = envio("d", EnvioTecnica.Estado.ENVIADO, "2026-11-11T11:00:00Z", d = null)
        val sinFecha = envio("e", EnvioTecnica.Estado.PUBLICADO, "ayer")
        assertEquals("b", DondeEntreno.respuestaReciente(listOf(vieja, media, nueva, enviado, sinFecha), ahora)?.id)
        assertEquals("c", DondeEntreno.respuestaReciente(listOf(vieja, media), ahora)?.id)
        assertNull(DondeEntreno.respuestaReciente(listOf(vieja, enviado, sinFecha), ahora))
        // A los 7 días justos ya no es nueva.
        assertNull(DondeEntreno.respuestaReciente(listOf(envio("f", EnvioTecnica.Estado.PUBLICADO, "2026-11-04T12:00:00Z")), ahora))
    }

    @Test
    fun laFilaDeLaGuiaCompletaDura7Dias() {
        val en = Instant.parse("2026-11-01T12:00:00Z")
        assertEquals(true, ReglasGuia.filaInicioVigente(null, en))
        assertEquals(true, ReglasGuia.filaInicioVigente(en, en.plusSeconds(7 * 86_400 - 1)))
        assertEquals(false, ReglasGuia.filaInicioVigente(en, en.plusSeconds(7 * 86_400)))
    }
}
