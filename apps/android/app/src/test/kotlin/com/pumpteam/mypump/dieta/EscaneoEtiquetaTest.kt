package com.pumpteam.mypump.dieta

import com.pumpteam.mypump.datos.Resultado
import com.pumpteam.mypump.modelos.ValorJson
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * La lectura de una etiqueta es del formulario que la pidió. Sin el dueño, cerrar «Alimento propio» a mitad de la lectura y
 * abrir otro aplicaba la respuesta vieja al nuevo y lo dejaba con el «Leyendo la etiqueta…» encima (y escanear ahí no hacía nada).
 */
class EscaneoEtiquetaTest {
    private val alcance = CoroutineScope(Dispatchers.Unconfined)
    private fun lectura(nombre: String): Resultado<ValorJson> = Resultado.Ok(ValorJson.objeto("nombre" to ValorJson.Texto(nombre)))

    @Test
    fun unFormularioNuevoNoHeredaLaLecturaDeOtro() {
        val e = EscaneoEtiqueta()
        val vieja = CompletableDeferred<Resultado<ValorJson>>()
        e.escanear("viejo", alcance) { vieja.await() }
        assertTrue(e.escaneando("viejo"))
        // Volvió a la lista y abrió otro formulario: ni bloqueado ni con el overlay.
        assertFalse(e.escaneando("nuevo"))
        vieja.complete(lectura("de la foto vieja"))
        assertNull(e.resultado("nuevo"))
        assertFalse(e.escaneando("nuevo"))
    }

    @Test
    fun laLecturaViejaNoPisaLaDelFormularioNuevo() {
        val e = EscaneoEtiqueta()
        val vieja = CompletableDeferred<Resultado<ValorJson>>()
        val nueva = CompletableDeferred<Resultado<ValorJson>>()
        e.escanear("viejo", alcance) { vieja.await() }
        e.escanear("nuevo", alcance) { nueva.await() }
        assertTrue(e.escaneando("nuevo"))
        vieja.complete(lectura("vieja"))
        // Sigue esperando la suya.
        assertTrue(e.escaneando("nuevo"))
        assertNull(e.resultado("nuevo"))
        val r = lectura("nueva")
        nueva.complete(r)
        assertEquals(r, e.resultado("nuevo"))
        assertFalse(e.escaneando("nuevo"))
    }

    @Test
    fun elMismoFormularioAlGirarRecibeSuLectura() {
        val e = EscaneoEtiqueta()
        val d = CompletableDeferred<Resultado<ValorJson>>()
        e.escanear("id", alcance) { d.await() }
        // El mismo id (rememberSaveable) después de rotar: sigue esperando y la respuesta llega.
        assertTrue(e.escaneando("id"))
        val r = lectura("x")
        d.complete(r)
        assertEquals(r, e.resultado("id"))
        e.consumir("id")
        assertNull(e.resultado("id"))
    }

    @Test
    fun cerrarLaHojaOlvidaLoQueEstabaEnCamino() {
        val e = EscaneoEtiqueta()
        val d = CompletableDeferred<Resultado<ValorJson>>()
        e.escanear("id", alcance) { d.await() }
        e.olvidar()
        assertFalse(e.escaneando("id"))
        d.complete(lectura("tarde"))
        assertNull(e.resultado("id"))
    }
}
