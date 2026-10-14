package com.pumpteam.mypump.ui

import androidx.test.ext.junit.runners.AndroidJUnit4
import com.pumpteam.mypump.acceso.Apariencia
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith

/**
 * D5: el tema sigue al sistema salvo que el cliente haya guardado oscuro (en Mis datos, o lo que trajo la migración de la
 * web). Se mira la pantalla de verdad: el color del fondo en el pantallazo.
 */
@RunWith(AndroidJUnit4::class)
class TemaUiTest : PruebaUi() {
    private fun esperarFondo(oscuro: Boolean) {
        p.esperar("el fondo ${if (oscuro) "oscuro" else "claro"}", ms = 10_000, enElPrincipal = false) { Telefono.fondoOscuro() == oscuro }
    }

    @Test
    fun sigueAlSistema() {
        abrir()
        p.nodo(etiqueta("ver-demo"))
        esperarFondo(oscuro = false)
        Telefono.modoNoche(true)
        // La Activity se recrea con el modo nuevo y sigue en la bienvenida.
        p.nodo(etiqueta("ver-demo"))
        esperarFondo(oscuro = true)
        Telefono.modoNoche(false)
        esperarFondo(oscuro = false)
    }

    @Test
    fun elOscuroGuardadoGanaConElTelefonoEnClaro() {
        guardarTemaOscuro()
        abrir()
        p.nodo(etiqueta("ver-demo"))
        esperarFondo(oscuro = true)
    }

    @Test
    fun elClaroQueGuardaLaWebNoEsUnaEleccion() {
        // `theme.js` escribe 'light' en cada carga: no fuerza claro con el teléfono en oscuro.
        guardarPreferencia(Apariencia.CLAVE, "light")
        Telefono.modoNoche(true)
        abrir()
        p.nodo(etiqueta("ver-demo"))
        esperarFondo(oscuro = true)
    }

    @Test
    fun elInterruptorDeMisDatosLoCambiaEnVivo() {
        abrir()
        p.tocar(etiqueta("ver-demo"))
        p.tocar(etiqueta("pestana-revision"))
        p.tocar(etiqueta("mis-datos"))
        p.nodo(texto("La app sigue al teléfono: clara u oscura según cómo lo tengas."))
        assertFalse(p.prendido(etiqueta("tema-oscuro")))
        esperarFondo(oscuro = false)
        p.tocar(etiqueta("tema-oscuro"))
        esperarFondo(oscuro = true)
        p.nodo(texto("La app queda oscura aunque el teléfono esté en claro."))
        assertEquals(Apariencia.OSCURO, preferencia(Apariencia.CLAVE))
        p.tocar(etiqueta("tema-oscuro"))
        esperarFondo(oscuro = false)
        assertNull("apagado vuelve a seguir al teléfono (sin la clave)", preferencia(Apariencia.CLAVE))
    }
}
