package com.pumpteam.mypump.ui

import androidx.test.ext.junit.runners.AndroidJUnit4
import com.pumpteam.mypump.Entorno
import com.pumpteam.mypump.datos.DobleGimnasio
import com.pumpteam.mypump.datos.Transporte
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/** Entrenar en casa (palanca `casa`) contra el doble del servidor, sin red. Lo fino está en `ColaBTest`; acá, la pantalla. */
@RunWith(AndroidJUnit4::class)
class CasaUiTest : PruebaUi() {
    @After
    fun soltar() {
        Telefono.shell("settings put system font_scale 1.0")
    }

    private fun lanzar(escenario: String): DobleGimnasio {
        val d = DobleGimnasio.escenario(escenario)
        val s = servidor
        Entorno.transporte = Transporte { pedido ->
            val suyo = "gimnasio" in pedido.ruta || "mypump_casa_" in pedido.ruta || pedido.ruta.endsWith("mypump_get_app_config")
            if (suyo) d.enviar(pedido) else s.enviar(pedido)
        }
        guardarCuenta()
        abrir()
        return d
    }

    private fun abrirMiGimnasioDesdeLaTarjeta() {
        p.tocar(etiqueta("gimnasio-tarjeta"))
        p.nodo(etiqueta("casa-interruptor"))
    }

    private fun deLaListaAlEnvio(d: DobleGimnasio) {
        abrirMiGimnasioDesdeLaTarjeta()
        assertFalse(p.prendido(etiqueta("casa-interruptor")))
        p.tocar(etiqueta("casa-interruptor"))
        p.nodo(etiqueta("casa-lista"))
        assertTrue(p.prendido(etiqueta("casa-interruptor")))
        assertFalse("sin nada marcado no se puede enviar", p.habilitado(etiqueta("casa-enviar")))
        p.tocar(etiqueta("casa-tipo-mancuernas"))
        p.escribir(etiqueta("casa-kg-mancuernas"), "20")
        p.tocar(etiqueta("casa-tipo-banco_plano"))
        assertFalse("el banco no lleva kilos", p.existe(etiqueta("casa-kg-banco_plano")))
        p.tocar(etiqueta("casa-enviar"))
        p.nodo(etiqueta("gimnasio-recibido"))
        assertFalse("ya enviado, el interruptor queda fijo", p.habilitado(etiqueta("casa-interruptor")))
        assertTrue(d.ultimoEnviarCasa?.serializar().orEmpty().contains("mancuernas"))
    }

    @Test
    fun deLaListaAlEnvio() = deLaListaAlEnvio(lanzar("casaVacio"))

    @Test
    fun letraGrande() {
        Telefono.shell("settings put system font_scale 2.0")
        deLaListaAlEnvio(lanzar("casaVacio"))
    }

    @Test
    fun sinEquipoTambienSePuedeEnviar() {
        lanzar("casaBorrador")
        abrirMiGimnasioDesdeLaTarjeta()
        p.nodo(etiqueta("casa-lista"))
        p.tocar(etiqueta("casa-sin-equipo"))
        p.esperar("enviar habilitado") { p.habilitado(etiqueta("casa-enviar")) }
    }

    @Test
    fun siNoSePuedeCambiarVuelveYAvisa() {
        val d = lanzar("casaVacio")
        abrirMiGimnasioDesdeLaTarjeta()
        d.proximosElegir += "red"
        p.tocar(etiqueta("casa-interruptor"))
        p.nodo(etiqueta("casa-error"))
        assertFalse(p.prendido(etiqueta("casa-interruptor")))
        assertFalse(p.existe(etiqueta("casa-lista")))
    }

    @Test
    fun laVigenteDeCasaNoMuestraZonas() {
        lanzar("casaVigente")
        p.nodo(etiqueta("pestana-entreno"))
        // Simplificar: Mi gimnasio vive en «Mi gimnasio y mi técnica», al final de Entreno.
        p.abrirDondeEntreno()
        p.tocar(etiqueta("donde-entreno-gimnasio"))
        p.nodo(etiqueta("casa-vigente"))
        p.nodo(textoQueContiene("Mancuernas"))
        assertTrue(p.prendido(etiqueta("casa-interruptor")))
        assertFalse(p.existe(etiqueta("gimnasio-falta-algo")))
        p.tocar(etiqueta("casa-cambiar"))
        p.nodo(etiqueta("casa-lista"))
    }

    /**
     * Con el gimnasio ya cargado no hay tarjeta; el interruptor de casa está en «Mi gimnasio y mi técnica» (simplificar): dos
     * toques desde Entreno, como antes con el botón suelto.
     */
    @Test
    fun conElGimnasioCargadoElInterruptorDeCasaQuedaADosToques() {
        lanzar("casaConGimnasioVigente")
        p.nodo(etiqueta("donde-entreno-entrada"), 20_000)
        assertFalse("con el gimnasio cargado la tarjeta no va", p.existe(etiqueta("gimnasio-tarjeta")))
        assertFalse("el botón suelto ya no está", p.existe(etiqueta("casa-tarjeta")))
        p.abrirDondeEntreno()
        p.nodo(etiqueta("casa-interruptor"))
        assertFalse(p.prendido(etiqueta("casa-interruptor")))
    }

    /** Entrenando en casa el botón no hace falta (y lo de casa sí llegó: no pasa por no haber cargado). */
    @Test
    fun entrenandoEnCasaNoHayBoton() {
        val d = lanzar("casaVigente")
        p.nodo(etiqueta("pestana-entreno"))
        p.esperar("casa y el gimnasio pedidos") { (d.llamadasCasa.isNotEmpty() && d.llamadasGimnasio.isNotEmpty()).takeIf { it } }
        p.quieto(2000)
        assertFalse("entrenando en casa", p.existe(etiqueta("casa-tarjeta")))
    }

    @Test
    fun conLaPalancaApagadaYElGimnasioCargadoNoHayBoton() {
        val d = lanzar("listo")
        p.nodo(etiqueta("pestana-entreno"))
        p.esperar("el gimnasio pedido") { d.llamadasGimnasio.isNotEmpty().takeIf { it } }
        p.quieto(2000)
        assertFalse(p.existe(etiqueta("casa-tarjeta")))
        assertFalse(p.existe(etiqueta("gimnasio-tarjeta")))
        assertEquals("apagada no se llama nada de casa", emptyList<String>(), d.llamadasCasa)
    }

    @Test
    fun conLaPalancaApagadaNoHayInterruptorNiLlamadas() {
        val d = lanzar("vacio")
        p.tocar(etiqueta("gimnasio-tarjeta"))
        p.quieto(2000)
        assertFalse(p.existe(etiqueta("casa-interruptor")))
        assertEquals("apagada no se llama nada de casa", emptyList<String>(), d.llamadasCasa)
    }
}
