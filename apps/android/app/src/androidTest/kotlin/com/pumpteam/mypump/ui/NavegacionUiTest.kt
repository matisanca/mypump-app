package com.pumpteam.mypump.ui

import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/** Las 5 pestañas con sus badges (GEN-01, GEN-03), Mis datos colgando de Revisión y el botón Atrás. */
@RunWith(AndroidJUnit4::class)
class NavegacionUiTest : PruebaUi() {
    @Test
    fun lasCincoPestanasConSusBadgesYElBannerDeRevision() {
        // Un mensaje de Mati sin leer con el chat cerrado; el check y las fotos de la semana, sin hacer (lo grabado).
        servidor.respuestas["mypump_get_chat"] =
            """[{"id":"m1","autor":"coach","contenido":"¿Cómo venís con el plan?","leido_por_cliente":false,"created_at":"2026-10-14T12:00:00Z"}]"""
        guardarCuenta()
        abrir()
        for (pestana in listOf("entreno", "dieta", "chat", "revision", "progreso")) p.nodo(etiqueta("pestana-$pestana"))
        assertTrue(p.seleccionado(etiqueta("pestana-entreno")))
        p.esperar("el badge de Chat") { "1" in p.textosBajo(etiqueta("pestana-chat")) }
        p.esperar("el badge de Revisión (check y fotos)") { "2" in p.textosBajo(etiqueta("pestana-revision")) }
        assertFalse("Entreno sin comentarios no lleva badge", p.textosBajo(etiqueta("pestana-entreno")).any { it.all(Char::isDigit) })
        // El banner de las otras pestañas lleva a Revisión.
        p.tocar(etiqueta("pestana-dieta"))
        p.nodo(texto("Te faltan tu check y tus fotos de la semana"))
        p.tocar(etiqueta("banner-revision"))
        p.esperar("Revisión elegida") { p.seleccionado(etiqueta("pestana-revision")) }
        p.nodo(textoQueContiene("Semana del"))
    }

    /** La app de la demo y la de la cuenta son escenas distintas: entrar enseguida no hereda la pestaña de la demo. */
    @Test
    fun salirDeLaDemoYEntrarEnseguidaArrancaEnEntreno() {
        abrir()
        p.tocar(etiqueta("ver-demo"))
        p.tocar(etiqueta("pestana-dieta"))
        p.nodo(texto("2.454"))
        p.tocar(etiqueta("salir-demo"))
        entrarConLaCuenta()
        p.esperar("Entreno elegido") { p.seleccionado(etiqueta("pestana-entreno")) }
        p.quieto(500)
        assertTrue(p.seleccionado(etiqueta("pestana-entreno")))
        assertFalse(p.existe(texto("Estás viendo la demo")))
    }

    @Test
    fun misDatosCuelgaDeRevisionYAtrasVuelve() {
        abrir()
        p.tocar(etiqueta("ver-demo"))
        p.tocar(etiqueta("pestana-revision"))
        p.tocar(etiqueta("mis-datos"))
        p.nodo(etiqueta("mis-datos-pantalla"))
        // Cambiar de pestaña y volver deja Mis datos abierto (como la pila de iOS)…
        p.tocar(etiqueta("pestana-dieta"))
        p.nodo(texto("Desayuno"))
        p.tocar(etiqueta("pestana-revision"))
        p.nodo(etiqueta("mis-datos-pantalla"))
        // …y tocar Revisión estando ahí vuelve a Revisión.
        p.tocar(etiqueta("pestana-revision"))
        p.esperarQueNoEste(etiqueta("mis-datos-pantalla"))
        p.nodo(textoQueContiene("Semana del"))
        // Atrás: de Mis datos a Revisión, y de cualquier pestaña a Entreno.
        p.tocar(etiqueta("mis-datos"))
        p.nodo(etiqueta("mis-datos-pantalla"))
        p.atras()
        p.esperarQueNoEste(etiqueta("mis-datos-pantalla"))
        p.nodo(textoQueContiene("Semana del"))
        p.atras()
        p.esperar("Entreno elegido") { p.seleccionado(etiqueta("pestana-entreno")) }
        // La flecha de Mis datos también vuelve.
        p.tocar(etiqueta("pestana-revision"))
        p.tocar(etiqueta("mis-datos"))
        p.tocar(etiqueta("volver"))
        p.esperarQueNoEste(etiqueta("mis-datos-pantalla"))
    }
}
