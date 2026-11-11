package com.pumpteam.mypump.ui

import androidx.test.ext.junit.runners.AndroidJUnit4
import com.pumpteam.mypump.Entorno
import com.pumpteam.mypump.datos.DobleEstudios
import com.pumpteam.mypump.datos.Transporte
import org.junit.After
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/**
 * «Tu próximo control de salud» (`controles_app`) contra el doble del servidor (sin red y con datos inventados; hoy = 10/11):
 * palanca apagada, sin control, control lejano y control dentro de la ventana de aviso. Lo fino está en `ControlesTest`.
 */
@RunWith(AndroidJUnit4::class)
class ControlesUiTest : PruebaUi() {
    @After
    fun soltar() {
        Telefono.shell("settings put system font_scale 1.0")
    }

    private fun lanzar(escenario: String): DobleEstudios {
        val d = DobleEstudios.escenario(escenario)
        val s = servidor
        Entorno.transporte = Transporte { pedido ->
            val r = pedido.ruta
            if ("estudios" in r || "controles" in r || r.endsWith("mypump_get_app_config")) d.enviar(pedido) else s.enviar(pedido)
        }
        guardarCuenta()
        abrir()
        return d
    }

    private fun abrirEstudios() {
        p.nodo(etiqueta("pestana-entreno"))
        p.tocar(etiqueta("pestana-revision"))
        p.tocar(etiqueta("mis-datos"))
        p.tocar(etiqueta("mis-datos-estudios"))
        p.nodo(etiqueta("estudios-pantalla"))
    }

    /** Lo de antes sigue igual: la tarjeta de estudios pendientes sí; la del control, no. */
    private fun sinTarjetaDeControl() {
        p.nodo(etiqueta("estudios-tarjeta-inicio"), 40_000)
        p.quieto(2500)
        assertFalse(p.existe(etiqueta("control-tarjeta-inicio")))
        assertFalse(p.existe(texto("Ver mis estudios")))
    }

    @Test
    fun palancaApagadaNoMuestraNiLlama() {
        val d = lanzar("controlesApagado")
        sinTarjetaDeControl()
        assertTrue("apagada no llama: ${d.llamadas}", d.llamadas.none { "controles" in it })
        abrirEstudios()
        p.nodo(textoQueContiene("Semana del 23/11"))
        assertFalse(p.existe(textoQueContiene("Te vamos a mandar las órdenes")))
    }

    @Test
    fun sinControlNoMuestraNada() {
        lanzar("sinControl")
        sinTarjetaDeControl()
        abrirEstudios()
        p.nodo(textoQueContiene("Semana del 23/11"))
        assertFalse(p.existe(texto("Control de salud")))
    }

    private fun lejano(tema: String) {
        lanzar("controlLejano")
        sinTarjetaDeControl()
        abrirEstudios()
        p.nodo(etiqueta("estudios-proximo-cuando"))
        p.nodo(texto("El miércoles 30/12"))
        p.nodo(texto("Te vamos a mandar las órdenes unos días antes."))
        assertFalse("un solo próximo control", p.existe(textoQueContiene("Semana del 23/11")))
        Telefono.captura("controles-estudios-lejano-$tema")
    }

    @Test
    fun controlLejanoSoloEnEstudios() = lejano("claro")

    private fun enVentana(tema: String) {
        lanzar("controlEnVentana")
        p.nodo(etiqueta("control-tarjeta-inicio-boton"), 40_000)
        p.nodo(texto("Tu próximo control de salud"))
        p.nodo(texto("El lunes 16/11"))
        p.nodo(texto("Te vamos a mandar las órdenes unos días antes."))
        p.nodo(texto("Ver mis estudios"))
        assertTrue("arriba de todo, antes que la lista", p.existe(etiqueta("control-tarjeta-inicio")))
        Telefono.captura("controles-inicio-$tema")
        // Un toque: directo a Estudios, con el control en el bloque «Próximo control».
        p.tocar(etiqueta("control-tarjeta-inicio-boton"))
        p.nodo(etiqueta("estudios-pantalla"))
        p.nodo(etiqueta("estudios-proximo-cuando"))
        p.nodo(texto("El lunes 16/11"))
        Telefono.captura("controles-estudios-$tema")
    }

    @Test
    fun controlEnVentanaVaArribaYLlevaAEstudios() = enVentana("claro")

    @Test
    fun ordenesEnviadasNoVaArriba() {
        lanzar("controlOrdenes")
        sinTarjetaDeControl()
        abrirEstudios()
        p.nodo(textoQueContiene("Ya te mandamos las órdenes"))
    }

    @Test
    fun capturasOscuro() {
        Telefono.modoNoche(true)
        guardarTemaOscuro()
        enVentana("oscuro")
    }

    /** La letra al máximo que deja Android (200 %): nada se corta y el botón se sigue tocando. */
    @Test
    fun letraGrande() {
        Telefono.shell("settings put system font_scale 2.0")
        enVentana("grande")
    }
}
