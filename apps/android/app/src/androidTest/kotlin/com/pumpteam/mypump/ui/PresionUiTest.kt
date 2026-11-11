package com.pumpteam.mypump.ui

import androidx.test.ext.junit.runners.AndroidJUnit4
import com.pumpteam.mypump.Entorno
import com.pumpteam.mypump.datos.DoblePresion
import com.pumpteam.mypump.datos.Transporte
import com.pumpteam.mypump.presion.TiemposPresion
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Presión arterial contra el doble del servidor (sin red), con las esperas acortadas. Lo fino de la cola está en
 * `PresionModeloTest`. Las capturas quedan como `android-*` en la carpeta de capturas del teléfono.
 */
@RunWith(AndroidJUnit4::class)
class PresionUiTest : PruebaUi() {
    @After
    fun soltar() {
        TiemposPresion.segundosDePrueba = 0
        Telefono.shell("settings put system font_scale 1.0")
        Telefono.modoNoche(false)
    }

    private fun lanzar(escenario: String, preparar: (DoblePresion) -> Unit = {}): DoblePresion {
        val d = DoblePresion.escenario(escenario).also(preparar)
        val s = servidor
        Entorno.transporte = Transporte { pedido ->
            if ("presion" in pedido.ruta || pedido.ruta.endsWith("mypump_get_app_config")) d.enviar(pedido) else s.enviar(pedido)
        }
        TiemposPresion.segundosDePrueba = 1
        guardarCuenta()
        abrir()
        return d
    }

    private fun anotar(sis: String, dia: String, pulso: String) {
        p.nodo(etiqueta("presion-alta"), 20_000)
        p.escribir(etiqueta("presion-alta"), sis)
        p.escribir(etiqueta("presion-baja"), dia)
        p.escribir(etiqueta("presion-pulso"), pulso)
        p.tocar(etiqueta("presion-anotar"))
    }

    /** De la tarjeta de arriba a la toma anotada: un paso por pantalla. */
    private fun hastaAnotar(tema: String?) {
        p.nodo(etiqueta("tarjeta-presion"), 20_000)
        tema?.let { Telefono.captura("android-1-tarjeta-$it") }
        p.tocar(etiqueta("tarjeta-presion-boton"))
        p.nodo(etiqueta("presion-cuando"))
        tema?.let { Telefono.captura("android-2-cuando-$it") }
        p.tocar(etiqueta("presion-cuando-seguir"))
        p.nodo(etiqueta("presion-como"))
        tema?.let { Telefono.captura("android-3-como-$it") }
        p.tocar(etiqueta("presion-empezar"))
        assertFalse("sin contestar no se sigue", p.habilitado(etiqueta("presion-previa-seguir")))
        for (k in listOf("cafeina", "fumo", "comida", "ejercicio")) p.tocar(etiqueta("presion-previa-$k-no"))
        tema?.let { Telefono.captura("android-4-previa-$it") }
        p.tocar(etiqueta("presion-previa-seguir"))
        p.nodo(etiqueta("presion-reposo"))
    }

    private fun recorrido(tema: String) {
        val d = lanzar("serie0")
        hastaAnotar(tema)
        p.nodo(etiqueta("presion-alta"), 20_000)
        p.escribir(etiqueta("presion-alta"), "124")
        p.escribir(etiqueta("presion-baja"), "78")
        p.escribir(etiqueta("presion-pulso"), "62")
        Telefono.captura("android-5-anotar-$tema")
        p.tocar(etiqueta("presion-anotar"))
        p.nodo(etiqueta("presion-listo"))
        Telefono.captura("android-6-listo-$tema")
        p.tocar(etiqueta("presion-cerrar"))
        p.nodo(etiqueta("presion-inicio"))
        p.nodo(etiqueta("presion-hoy-listo"))
        Telefono.captura("android-7-inicio-$tema")
        p.esperar("la toma en el servidor") { (d.recibidas.size == 1).takeIf { it } }
        assertEquals("android", d.recibidas.last()["plataforma"]?.comoTexto)
    }

    @Test fun recorridoClaro() = recorrido("claro")

    @Test fun recorridoOscuro() {
        Telefono.modoNoche(true)
        recorrido("oscuro")
    }

    @Test fun recorridoLetraGrande() {
        Telefono.shell("settings put system font_scale 2.0")
        recorrido("grande")
    }

    @Test fun palancaApagadaNoMuestraNiLlamaNada() {
        val d = lanzar("apagado")
        p.nodo(etiqueta("pestana-entreno"), 20_000)
        p.quieto(1_500)
        assertFalse(p.existe(etiqueta("tarjeta-presion")))
        p.tocar(etiqueta("pestana-revision"))
        p.tocar(etiqueta("mis-datos"))
        p.quieto(500)
        assertFalse(p.existe(etiqueta("mis-datos-presion")))
        assertTrue("no se llama a nada de presión", d.llamadasPresion.isEmpty())
    }

    @Test fun sinElServidorNuevoNoSeVeNada() {
        lanzar("sinServidor")
        p.nodo(etiqueta("pestana-entreno"), 20_000)
        p.quieto(1_500)
        assertFalse(p.existe(etiqueta("tarjeta-presion")))
    }

    @Test fun desdeMisDatosSinSerie() {
        lanzar("sinSerie")
        p.nodo(etiqueta("pestana-entreno"), 20_000)
        p.quieto(1_000)
        assertFalse("sin serie abierta no hay tarjeta", p.existe(etiqueta("tarjeta-presion")))
        p.tocar(etiqueta("pestana-revision"))
        p.tocar(etiqueta("mis-datos"))
        p.tocar(etiqueta("mis-datos-presion"))
        p.nodo(etiqueta("presion-inicio"))
        p.nodo(etiqueta("presion-sin-tomas"))
        assertFalse("sin la lista verificada no hay «Ver cuáles sirven»", p.existe(etiqueta("presion-ver-cuales")))
        p.tocar(etiqueta("presion-cerrar-seccion"))
        p.esperarQueNoEste(etiqueta("presion-inicio"))
    }

    /** 180/120 o más: pide confirmar, espera con la lista de alarma y, con un Sí, guardia en el acto y sin red. */
    @Test fun urgenciaListaYGuardiaSinRed() {
        val d = lanzar("serie0")
        hastaAnotar(null)
        d.sinRed = true
        anotar("184", "121", "88")
        p.nodo(etiqueta("presion-revisar"))
        p.tocar(etiqueta("presion-confirmar"))
        p.nodo(etiqueta("presion-espera-sintomas"))
        Telefono.captura("android-8-espera-lista")
        p.tocar(etiqueta("presion-alarma-dolor_pecho-si"))
        p.nodo(etiqueta("presion-guardia-sintomas"))
        Telefono.captura("android-9-guardia")
    }

    @Test fun tomaAltaPideRepetirYLaTarjetaLoRecuerda() {
        lanzar("serie0")
        hastaAnotar(null)
        anotar("164", "98", "70")
        p.tocar(etiqueta("presion-confirmar"))
        p.nodo(etiqueta("presion-espera"))
        p.nodo(etiqueta("presion-repetir-toma"), 20_000)
        // Sale sin repetir: queda pendiente en el inicio y en la tarjeta.
        p.tocar(etiqueta("presion-flujo-cerrar"))
        p.nodo(etiqueta("presion-pendiente"))
        p.tocar(etiqueta("presion-cerrar-seccion"))
        p.nodo(etiqueta("tarjeta-presion"))
        p.tocar(etiqueta("tarjeta-presion-boton"))
        anotar("150", "90", "70")
        p.nodo(etiqueta("presion-listo"))
    }

    @Test fun sinAparatoPrimeroPreparar() {
        lanzar("serie0") { it.aparato = null }
        p.nodo(etiqueta("tarjeta-presion"), 20_000)
        p.tocar(etiqueta("tarjeta-presion-boton"))
        p.nodo(etiqueta("presion-antes"))
        Telefono.captura("android-10-aparato")
        assertFalse(p.habilitado(etiqueta("presion-guardar")))
        p.escribir(etiqueta("presion-medida"), "35")
        p.tocar(etiqueta("presion-tipo-reloj_anillo_otro"))
        p.nodo(etiqueta("presion-reloj-no-sirve"))
        p.tocar(etiqueta("presion-tipo-brazo"))
        p.tocar(etiqueta("presion-guardar"))
        p.nodo(etiqueta("presion-inicio"))
    }
}
