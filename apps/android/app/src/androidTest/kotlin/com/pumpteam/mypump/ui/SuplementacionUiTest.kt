package com.pumpteam.mypump.ui

import androidx.compose.ui.semantics.SemanticsProperties
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/**
 * La pestaña Suplementación (2.1.0): aparece solo con suplementación, Salud pasa al botón de arriba de Revisión (y los
 * links siguen llevando a Salud), «Tu día», «Dejás de tomar» y el detalle en una hoja. Datos ficticios.
 */
@RunWith(AndroidJUnit4::class)
class SuplementacionUiTest : PruebaUi() {
    /** Las pestañas de la barra, de izquierda a derecha. */
    private fun barra(): List<String> = listOf("entreno", "dieta", "chat", "revision", "salud", "suplementacion")
        .filter { p.existe(etiqueta("pestana-$it")) }
        .sortedBy { t -> p.nodo(etiqueta("pestana-$t")).let { n -> p.enPrincipal { n.boundsInRoot.left } } }

    @Test
    fun laDemoMuestraLaPestanaYElDetalle() {
        abrir()
        p.tocar(etiqueta("ver-demo"))
        p.nodo(etiqueta("pestana-suplementacion"))
        // Con suplementación: Entreno, Dieta, Suplementación, Chat y Revisión. Salud sale de la barra.
        assertEquals(listOf("entreno", "dieta", "suplementacion", "chat", "revision"), barra())
        assertFalse(p.existe(etiqueta("pestana-salud")))

        p.tocar(etiqueta("pestana-suplementacion"))
        p.nodo(etiqueta("suplementacion-pantalla"))
        p.nodo(texto("Tu suplementación"))
        p.nodo(texto("Empezá esta semana con lo nuevo"))
        p.nodo(texto("Tu día"))
        assertTrue(p.encabezado(texto("Tu día")))
        p.nodo(texto("Con el desayuno"))
        p.nodo(texto("30 a 60 minutos antes de entrenar"))
        // Omega 3 va en sus dos momentos; el multivitamínico (sale) no va en el día.
        assertEquals(2, p.cuantos(etiqueta("suple-Omega 3")))
        assertFalse(p.existe(etiqueta("suple-Multivitamínico")))
        // TalkBack lee la fila entera: nombre, cantidad, estado, opcional, días y nota.
        val cafeina = p.nodo(etiqueta("suple-Cafeína"))
        assertEquals(
            "Cafeína, 200 mg, Nuevo, Opcional, Días de entreno, No después de las 17",
            p.enPrincipal { cafeina.config[SemanticsProperties.ContentDescription].first() },
        )

        // El detalle de la creatina: cómo tomarlo, el porqué y qué comprar.
        p.tocar(etiqueta("suple-Creatina monohidrato"))
        p.nodo(etiqueta("hoja-suplemento"))
        p.nodo(texto("Cómo tomarlo"))
        p.nodo(texto("Todos los días, también los de descanso"))
        p.nodo(textoQueContiene("Te ayuda a rendir más en las series pesadas"))
        p.nodo(texto("Qué comprar"))
        p.nodo(texto("Creatina monohidrato 100 % pura"))
        p.tocar(etiqueta("listo-suplemento"))
        p.esperarQueNoEste(etiqueta("hoja-suplemento"))

        // El magnesio sube: antes y ahora.
        p.tocar(etiqueta("suple-Magnesio glicinato"))
        p.nodo(etiqueta("hoja-suplemento"))
        p.nodo(textoQueContiene("200 mg"))
        p.nodo(texto("Sube"))
        p.tocar(etiqueta("listo-suplemento"))
        p.esperarQueNoEste(etiqueta("hoja-suplemento"))

        // «Dejás de tomar», abajo, con su porqué y su detalle.
        p.nodo(texto("Dejás de tomar"))
        p.tocar(etiqueta("sale-Multivitamínico"))
        p.nodo(etiqueta("hoja-suplemento"))
        p.nodo(textoQueContiene("Ya lo cubrís con la dieta"))
        p.tocar(etiqueta("listo-suplemento"))
        p.esperarQueNoEste(etiqueta("hoja-suplemento"))
        assertTrue("la demo tocó la red: ${servidor.llamadas.map { it.funcion }}", servidor.llamadas.isEmpty())
    }

    @Test
    fun saludSeAbreDesdeRevisionYVuelve() {
        abrir()
        p.tocar(etiqueta("ver-demo"))
        p.tocar(etiqueta("pestana-revision"))
        p.nodo(etiqueta("mis-datos"))
        p.tocar(etiqueta("abrir-salud"))
        p.nodo(etiqueta("salud-pantalla"))
        p.tocar(etiqueta("segmento-fuerza"))
        p.esperar("Fuerza elegida") { p.seleccionado(etiqueta("segmento-fuerza")) }
        // Volver (la flecha) lleva a Revisión.
        p.tocar(etiqueta("volver"))
        p.esperar("Revisión elegida") { p.seleccionado(etiqueta("pestana-revision")) }
        p.esperarQueNoEste(etiqueta("salud-pantalla"))
        // Otra vez, y con Atrás del sistema.
        p.tocar(etiqueta("abrir-salud"))
        p.nodo(etiqueta("salud-pantalla"))
        instr.uiAutomation.performGlobalAction(android.accessibilityservice.AccessibilityService.GLOBAL_ACTION_BACK)
        p.esperar("Revisión elegida") { p.seleccionado(etiqueta("pestana-revision")) }
    }

    @Test
    fun sinSuplementacionLaBarraQuedaComoHoy() {
        // El servidor de prueba contesta cero filas (`[]`): no hay suplementación.
        guardarCuenta()
        abrir()
        p.nodo(etiqueta("pestana-entreno"))
        p.esperar("pidió la suplementación") { servidor.llamadas.any { it.funcion == "mypump_suplementacion" } }
        p.quieto(500)
        assertEquals(listOf("entreno", "dieta", "chat", "revision", "salud"), barra())
        p.tocar(etiqueta("pestana-revision"))
        p.nodo(etiqueta("mis-datos"))
        assertFalse(p.existe(etiqueta("abrir-salud")))
    }

    @Test
    fun conSuplementacionLosLinksDeSaludSiguenLlegando() {
        servidor.respuestas["mypump_suplementacion"] = FILA
        abrirConLink("https://app.mypumpteam.com/?t=${ServidorDePrueba.TOKEN}&scene=progress")
        p.nodo(etiqueta("pestana-suplementacion"), ms = 30_000)
        p.nodo(etiqueta("salud-pantalla"))
        p.esperar("Fuerza elegida") { p.seleccionado(etiqueta("segmento-fuerza")) }
        assertFalse(p.existe(etiqueta("pestana-salud")))
        p.tocar(etiqueta("pestana-suplementacion"))
        p.nodo(texto("Antes de dormir"))
        p.nodo(etiqueta("suple-Zinc"))
        assertFalse(p.existe(texto("Dejás de tomar")))
    }

    private companion object {
        /** Una fila mínima del RPC (ficticia), sin `dia[].nombre`: el momento usa el texto propio de la app. */
        const val FILA = """[{"suplementacion":{"dia":[{"id":"dormir"}],"items":[{"nombre":"Zinc","cantidad":"15 mg","momento":"dormir","estado":"sigue"}]},"fase":"final","actualizado":"2026-11-04T18:30:00+00:00","esquema":1}]"""
    }
}
