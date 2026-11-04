package com.pumpteam.mypump.reglas

import com.pumpteam.mypump.reglas.MaquinaAudioDuda.Efecto
import com.pumpteam.mypump.reglas.MaquinaAudioDuda.Estado
import com.pumpteam.mypump.reglas.MaquinaAudioDuda.Permiso
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/** La máquina del grabador de las dudas en audio y las reglas que copia de la web (topes, textos, deduplicación). */
class AudioDudaTest {
    private val m = MaquinaAudioDuda

    @Test
    fun conPermisoGrabaYTerminaEnRevisar() {
        val p = m.grabar(Estado.Reposo, Permiso.CONCEDIDO)
        assertEquals(listOf(Efecto.Empezar), p.efectos)
        val g = m.empezo(1_000).estado as Estado.Grabando
        assertNull(m.tic(g, 5_000))
        val fin = m.terminar(g, 43_400)
        assertEquals(Estado.Revisando(42), fin.estado)
        assertEquals(listOf(Efecto.Detener), fin.efectos)
        // El contador se anuncia al terminar, no cada segundo.
        assertEquals("Grabaste 0:42", fin.aviso?.texto)
    }

    @Test
    fun sinPermisoLoPideYSiLoNiegaVaAAjustes() {
        val p = m.grabar(Estado.Reposo, Permiso.SIN_PEDIR)
        assertEquals(Estado.PidiendoPermiso, p.estado)
        assertEquals(listOf(Efecto.PedirPermiso), p.efectos)
        assertEquals(listOf(Efecto.Empezar), m.permiso(true).efectos)
        val no = m.permiso(false)
        assertEquals(Estado.Reposo, no.estado)
        assertTrue(no.aviso!!.ajustes)
        assertTrue(no.aviso!!.error)
        assertTrue("Abrir ajustes" in no.aviso!!.texto)
        // Negado para siempre: no se vuelve a pedir, va la explicación directo.
        val otra = m.grabar(Estado.Reposo, Permiso.NEGADO)
        assertTrue(otra.efectos.isEmpty())
        assertEquals(ReglasAudioDuda.PERMISO_NEGADO, otra.aviso?.texto)
    }

    @Test
    fun avisaA270YCortaA300() {
        val g = Estado.Grabando(0)
        assertNull(m.tic(g, 269_999))
        val aviso = m.tic(g, 270_000)!!
        assertEquals("Te quedan 30 segundos.", aviso.aviso?.texto)
        val avisado = aviso.estado as Estado.Grabando
        assertTrue(avisado.avisado)
        // Una sola vez.
        assertNull(m.tic(avisado, 280_000))
        val corte = m.tic(avisado, 300_000)!!
        assertEquals(Estado.Revisando(300), corte.estado)
        assertEquals(listOf(Efecto.Detener), corte.efectos)
        // Un reloj atrasado (un tic tarde) no pasa del tope.
        assertEquals(Estado.Revisando(300), m.terminar(avisado, 312_000).estado)
    }

    @Test
    fun menosDeDosSegundosNoSeManda() {
        val p = m.terminar(Estado.Grabando(10_000), 11_900)
        assertEquals(Estado.Reposo, p.estado)
        assertEquals(listOf(Efecto.Descartar), p.efectos)
        assertEquals("No se escuchó nada, probá de nuevo.", p.aviso?.texto)
        assertEquals(Estado.Revisando(2), m.terminar(Estado.Grabando(10_000), 12_000).estado)
    }

    @Test
    fun revisarMandarGrabarDeNuevoYBorrar() {
        val r = Estado.Revisando(12)
        assertEquals(listOf(Efecto.Encolar(12)), m.mandar(r, vistaPrevia = false).efectos)
        assertEquals(Estado.Reposo, m.mandar(r, vistaPrevia = false).estado)
        // Grabar de nuevo descarta el anterior antes de empezar.
        assertEquals(listOf(Efecto.Descartar, Efecto.Empezar), m.grabar(r, Permiso.CONCEDIDO).efectos)
        assertEquals(listOf(Efecto.Descartar), m.borrar(r).efectos)
        assertTrue(m.borrar(Estado.Reposo).efectos.isEmpty())
        // Mandar sin nada para revisar no hace nada.
        assertTrue(m.mandar(Estado.Reposo, false).efectos.isEmpty())
    }

    @Test
    fun enLaDemoNoSeManda() {
        val p = m.mandar(Estado.Revisando(8), vistaPrevia = true)
        assertEquals(Estado.Revisando(8), p.estado)
        assertTrue(p.efectos.isEmpty())
        assertEquals("Vista previa: el audio no se manda.", p.aviso?.texto)
    }

    @Test
    fun fallosDelMicrofono() {
        assertEquals(ReglasAudioDuda.SIN_MICROFONO, m.noEmpezo(MaquinaAudioDuda.Fallo.SIN_MICROFONO).aviso?.texto)
        assertEquals(ReglasAudioDuda.MICROFONO_OCUPADO, m.noEmpezo(MaquinaAudioDuda.Fallo.OCUPADO).aviso?.texto)
        assertEquals(listOf(Efecto.Descartar), m.seCorto().efectos)
        // Terminar fuera de la grabación (un segundo plano en reposo) no cambia nada.
        assertEquals(Estado.Revisando(5), m.terminar(Estado.Revisando(5), 99).estado)
        assertNull(m.tic(Estado.Reposo, 1))
    }

    @Test
    fun textosDeLosMotivos() {
        assertEquals("Ya me mandaste 10 audios. Lo que te falte escribímelo o lo vemos en la llamada.", ReglasAudioDuda.textoMotivo("tope"))
        assertEquals("Esperá un toque que se terminen de mandar los otros audios.", ReglasAudioDuda.textoMotivo("pendientes"))
        assertEquals(ReglasAudioDuda.textoMotivo("tamano"), ReglasAudioDuda.textoMotivo("largo"))
        assertNull(ReglasAudioDuda.textoMotivo("algo-nuevo"))
        assertTrue(ReglasAudioDuda.motivoReintentable("pendientes"))
        assertTrue(ReglasAudioDuda.motivoReintentable(null))
        assertFalse(ReglasAudioDuda.motivoReintentable("tope"))
        assertFalse(ReglasAudioDuda.motivoReintentable("formato"))
        assertFalse(ReglasAudioDuda.motivoReintentable("id"))
        assertFalse(ReglasAudioDuda.motivoReintentable("error"))
        assertEquals(ReglasAudioDuda.ERROR_AUDIO, ReglasAudioDuda.textoMotivo("error"))
    }

    @Test
    fun contadorYDeduplicacion() {
        assertEquals("0:00", ReglasAudioDuda.contador(0))
        assertEquals("0:42", ReglasAudioDuda.contador(42))
        assertEquals("4:30", ReglasAudioDuda.contador(270))
        assertEquals("5:00", ReglasAudioDuda.contador(300))
        val dudas = listOf("¿Puedo entrenar en ayunas?", "Lo del sueño", "¿Y la creatina?")
        assertEquals(listOf("Lo del sueño"), ReglasAudioDuda.sinTranscriptas(dudas, listOf(" ¿Puedo entrenar en ayunas? ", "¿Y la creatina?")))
        assertEquals(dudas, ReglasAudioDuda.sinTranscriptas(dudas, emptyList()))
    }

    @Test
    fun consultaHastaTresMinutos() {
        assertTrue(ReglasAudioDuda.seguirConsultando(true, 0, 179_999))
        assertFalse(ReglasAudioDuda.seguirConsultando(true, 0, 180_000))
        assertFalse(ReglasAudioDuda.seguirConsultando(false, 0, 1))
    }
}
