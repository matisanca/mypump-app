package com.pumpteam.mypump.ui

import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.pumpteam.mypump.MainActivity
import com.pumpteam.mypump.avisos.CentroAvisos
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/**
 * «Salud dentro de Revisión» (2.1.0, `docs/NATIVA_SALUD_EN_REVISION.md`): la barra sin Salud, la tarjeta Recuperación
 * arriba de todo en Revisión que abre Salud, un aviso de fuerza que abre Revisión + Salud en ese segmento y «Tu salud,
 * últimos 7 días» en el check de la demo (con la salud de muestra, ficticia). Las capturas quedan en
 * [Telefono.CARPETA_CAPTURAS] (`salud-rev-*`).
 */
@RunWith(AndroidJUnit4::class)
class SaludEnRevisionUiTest : PruebaUi() {
    /** Lleva la sección arriba de todo con el desplazamiento de la lista (como `RevisionCapturasTest`). */
    private fun llevarArriba(etiquetaDe: String) {
        val delta = p.esperar("se ubica $etiquetaDe") {
            val visible = p.nodo(etiqueta("revision-lista"), ms = 0).boundsInRoot
            p.nodo(etiqueta(etiquetaDe), ms = 0).positionInRoot.y - visible.top - 24f
        }
        p.desplazar(etiqueta("revision-lista"), delta)
        p.quieto(400)
    }

    /** Dónde empieza el nodo, sin recortar por lo que se ve (`boundsInRoot` de lo que queda fuera de la pantalla se achica). */
    private fun arriba(tag: String): Float = p.nodo(etiqueta(tag)).let { n -> p.enPrincipal { n.positionInRoot.y } }

    @Test
    fun laTarjetaVaArribaDeTodoYAbreSaludEnRecuperacion() {
        abrir()
        p.tocar(etiqueta("ver-demo"))
        p.tocar(etiqueta("pestana-revision"))
        p.nodo(etiqueta("tarjeta-recuperacion-revision"))
        // Lo primero de Revisión: antes que las fotos y el check. El corazón de arriba ya no está.
        assertTrue(arriba("tarjeta-recuperacion-revision") < arriba("seccion-fotos"))
        assertTrue(arriba("seccion-fotos") < arriba("seccion-check"))
        assertFalse(p.existe(etiqueta("abrir-salud")))
        // En la demo: lo que se va a ver con la cuenta, y la fila de abajo.
        p.nodo(texto("Con tu cuenta, acá vas a ver tu recuperación de cada día."))
        p.nodo(texto("Ver sueño, corazón, fuerza y cuerpo"))
        Telefono.captura("salud-rev-01-tarjeta-demo")

        p.tocar(etiqueta("tarjeta-recuperacion-revision"))
        p.nodo(etiqueta("salud-pantalla"))
        p.esperar("Recuperación elegida") { p.seleccionado(etiqueta("segmento-recuperacion")) }
        assertTrue("Revisión marcada con Salud abierta", p.seleccionado(etiqueta("pestana-revision")))
        p.tocar(etiqueta("volver"))
        p.esperarQueNoEste(etiqueta("salud-pantalla"))
        p.nodo(etiqueta("tarjeta-recuperacion-revision"))
    }

    @Test
    fun elCheckDeLaDemoLlevaTuSaludDeLosUltimos7Dias() {
        abrir()
        p.tocar(etiqueta("ver-demo"))
        p.tocar(etiqueta("pestana-revision"))
        p.nodo(etiqueta("salud-del-check"))
        llevarArriba("salud-del-check")
        // Una segunda vez: la primera puede quedarse corta si lo de arriba todavía se estaba acomodando.
        llevarArriba("salud-del-check")
        p.nodo(texto("Tu salud, últimos 7 días"))
        p.nodo(texto("Va con tu check: Mati lo ve junto a tus respuestas."))
        // La salud de muestra: 7 días de sueño, HRV, pulso y pasos; sin recuperación (la demo no tiene cuenta).
        assertFalse(p.existe(etiqueta("salud-check-recuperacion")))
        assertEquals(listOf("Sueño", "7h 04", "promedio de 7 días"), p.textosBajo(etiqueta("salud-check-sueno")))
        assertEquals(listOf("Variabilidad (HRV)", "53 ms", "promedio de 7 días"), p.textosBajo(etiqueta("salud-check-hrv")))
        assertEquals(listOf("Pulso en reposo", "58 lpm", "promedio de 7 días"), p.textosBajo(etiqueta("salud-check-fc_reposo")))
        assertEquals(listOf("Pasos", "8.243 por día", "promedio de 7 días"), p.textosBajo(etiqueta("salud-check-pasos")))
        // Arriba del botón de enviar.
        assertTrue(arriba("salud-del-check") < arriba("enviar-check"))
        Telefono.captura("salud-rev-02-check-demo")
        assertTrue("la demo tocó la red: ${servidor.llamadas.map { it.funcion }}", servidor.llamadas.isEmpty())
    }

    @Test
    fun unAvisoDeFuerzaAbreRevisionYSaludEnFuerza() {
        // Sin suplementación (el servidor de prueba contesta `[]`): la barra tampoco tiene Salud.
        guardarCuenta()
        registrar(ActivityScenario.launch<MainActivity>(CentroAvisos.intentDeAviso(app, "progress"))).also {
            p.esperar("Revisión + Salud", ms = 30_000) { p.enSalud() }
            p.esperar("Fuerza elegida") { p.seleccionado(etiqueta("segmento-fuerza")) }
            assertFalse(p.existe(etiqueta("pestana-salud")))
            // Atrás vuelve a Revisión, con la tarjeta arriba.
            p.atras()
            p.esperarQueNoEste(etiqueta("salud-pantalla"))
            p.nodo(etiqueta("tarjeta-recuperacion-revision"))
            assertTrue(p.seleccionado(etiqueta("pestana-revision")))
        }.close()
    }
}
