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
 * arriba de todo en Revisión que abre Salud, «Tu progreso» que abre Fuerza, un aviso de fuerza que abre Revisión + Salud
 * en ese segmento y que la demo, sin datos de salud, no muestra «Tu salud, últimos 7 días» en el check. Las capturas quedan en
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
        p.nodo(etiqueta("tarjeta-mi-salud"))
        // 2.3.0: «Mi salud» arriba de todo, antes que las fotos y el check; en la demo solo trae la recuperación. Las tres en
        // la misma pasada: buscar una puede desplazar la lista.
        p.nodo(etiqueta("seccion-fotos"))
        val (fotos, check, rec) = p.esperar("todo ubicado") {
            listOf("seccion-fotos", "seccion-check", "tarjeta-mi-salud").map { p.nodo(etiqueta(it), ms = 0).positionInRoot.y }
        }
        assertTrue("Mi salud antes de las fotos: $rec, fotos $fotos", rec < fotos)
        assertTrue("fotos antes del check: $fotos, $check", fotos < check)
        assertFalse("sin el corazón de arriba", p.existe(etiqueta("abrir-salud")))
        assertFalse("Recuperación ya no está en Revisión", p.existe(etiqueta("tarjeta-recuperacion-revision")))
        p.nodo(texto("Recuperación"))
        Telefono.captura("salud-rev-00-mi-salud-demo")
        p.tocar(etiqueta("tarjeta-mi-salud"))
        p.nodo(etiqueta("mi-salud-pantalla"))
        // En la demo: lo que se va a ver con la cuenta. 2.3.0: una fila con flecha (el renglón «Ver sueño…» ya no va).
        p.nodo(texto("Con tu cuenta, acá vas a ver tu recuperación de cada día."))
        assertFalse("sin el renglón Ver sueño", p.existe(texto("Ver sueño, corazón y cuerpo")))
        // «Tu progreso» sigue en Revisión; abre Salud en Fuerza (se prueba con cuenta en SaludPestanaUiTest). Desde la cola A
        // la demo trae historial: ya no dice lo genérico.
        p.tocar(etiqueta("volver"))
        p.nodo(etiqueta("tarjeta-progreso-revision"))
        p.nodo(texto("Tu progreso"))
        // La línea sale del progreso de la demo, que se arma al abrir (un instante después que la fila).
        p.esperarQueNoEste(texto("Tu fuerza y tus récords, ejercicio por ejercicio."))
        p.nodo(textoQueContiene("esta semana"))
        Telefono.captura("salud-rev-01-tarjeta-demo")

        p.tocar(etiqueta("tarjeta-mi-salud"))
        p.tocar(etiqueta("tarjeta-recuperacion-revision"))
        p.nodo(etiqueta("salud-pantalla"))
        p.esperar("Recuperación elegida") { p.seleccionado(etiqueta("segmento-recuperacion")) }
        assertTrue("Revisión marcada con Salud abierta", p.seleccionado(etiqueta("pestana-revision")))
        // Volver lleva a Mi salud, de donde se abrió; otra vez, a Revisión.
        p.tocar(etiqueta("volver"))
        p.esperarQueNoEste(etiqueta("salud-pantalla"))
        p.nodo(etiqueta("tarjeta-recuperacion-revision"))
        p.tocar(etiqueta("volver"))
        p.esperarQueNoEste(etiqueta("mi-salud-pantalla"))
        p.tocar(etiqueta("tarjeta-progreso-revision"))
        p.nodo(etiqueta("salud-pantalla"))
        p.esperar("Fuerza elegida") { p.seleccionado(etiqueta("segmento-fuerza")) }
    }

    @Test
    fun elCheckDeLaDemoNoTraeSaludPorqueNoHayDatos() {
        abrir()
        p.tocar(etiqueta("ver-demo"))
        p.tocar(etiqueta("pestana-revision"))
        p.nodo(etiqueta("enviar-check"))
        // Como iOS: la demo no tiene datos de salud y el bloque «Tu salud, últimos 7 días» no aparece.
        assertFalse(p.existe(etiqueta("salud-del-check")))
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
            // Atrás vuelve a Revisión, con la tarjeta Mi salud arriba.
            p.atras()
            p.esperarQueNoEste(etiqueta("salud-pantalla"))
            p.nodo(etiqueta("tarjeta-mi-salud"))
            assertTrue(p.seleccionado(etiqueta("pestana-revision")))
        }.close()
    }
}
