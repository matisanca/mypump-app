package com.pumpteam.mypump.ui

import androidx.test.ext.junit.runners.AndroidJUnit4
import com.pumpteam.mypump.Entorno
import com.pumpteam.mypump.datos.DobleTecnica
import com.pumpteam.mypump.datos.Transporte
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/** Técnica por video contra el doble del servidor (sin red). El video pasa por el compresor de verdad. Lo fino de la cola está en `TecnicaTest`. */
@RunWith(AndroidJUnit4::class)
class TecnicaUiTest : PruebaUi() {
    private var camara: CamaraDeVideoDePrueba? = null
    private val ejercicio = "jalon-al-pecho-prono-dorsal-ancho-d1-0"

    @After
    fun soltar() {
        camara?.soltar()
        Telefono.shell("settings put system font_scale 1.0")
        Telefono.modoNoche(false)
    }

    private fun lanzar(escenario: String): DobleTecnica {
        val d = DobleTecnica.escenario(escenario)
        val s = servidor
        Entorno.transporte = Transporte { pedido ->
            if ("tecnica" in pedido.ruta || pedido.ruta.endsWith("mypump_get_app_config")) d.enviar(pedido) else s.enviar(pedido)
        }
        guardarCuenta()
        camara = camara ?: CamaraDeVideoDePrueba(instr, app)
        abrir()
        return d
    }

    private fun desdeEjercicio(escenario: String): DobleTecnica {
        val d = lanzar(escenario)
        abrirPaginaDelEjercicio(ejercicio)
        p.tocar(etiqueta("tecnica-mandar-ejercicio"))
        return d
    }

    private fun miTecnica(escenario: String): DobleTecnica {
        val d = lanzar(escenario)
        p.tocar(etiqueta("pestana-revision"))
        p.tocar(etiqueta("mis-datos"))
        p.tocar(etiqueta("mis-datos-tecnica"))
        return d
    }

    private fun elegirVideo() {
        p.tocar(etiqueta("tecnica-agregar-video"))
        p.quieto(400)
        if (p.existe(etiqueta("tecnica-galeria"))) p.tocar(etiqueta("tecnica-galeria"))
        p.nodo(etiqueta("tecnica-video-listo"), 60_000)
    }

    private fun elegirYEnviar() {
        p.nodo(etiqueta("tecnica-consejo"))
        elegirVideo()
        p.tocar(etiqueta("tecnica-enviar"))
    }

    private fun recorrido(tema: String) {
        val d = desdeEjercicio("vacio")
        p.nodo(etiqueta("tecnica-aviso"))
        Telefono.captura("tec-1-aviso-$tema")
        p.tocar(etiqueta("tecnica-aviso-ok"))
        p.nodo(etiqueta("tecnica-consejo"))
        Telefono.captura("tec-2-consejo-$tema")
        assertFalse("sin video no se manda", p.habilitado(etiqueta("tecnica-enviar")))
        elegirVideo()
        p.escribir(etiqueta("tecnica-nota"), "Mirá la bajada")
        Telefono.captura("tec-3-listo-$tema")
        p.tocar(etiqueta("tecnica-enviar"))
        p.nodo(etiqueta("tecnica-recibido"), 30_000)
        Telefono.captura("tec-4-recibido-$tema")
        assertEquals(1, d.bytesSubidos.size)
        assertTrue(d.usoArchivo)
        assertEquals("Mirá la bajada", d.ultimoNuevo?.get("p_nota")?.comoTexto)
    }

    @Test fun recorridoClaro() = recorrido("claro")

    @Test fun recorridoOscuro() {
        Telefono.modoNoche(true)
        recorrido("oscuro")
    }

    @Test fun recorridoLetraGrande() {
        Telefono.shell("settings put system font_scale 1.3")
        recorrido("grande")
    }

    @Test fun desdeMisDatosEligeEjercicio() {
        miTecnica("vacio")
        p.nodo(etiqueta("tecnica-vacio"))
        Telefono.captura("tec-5-lista-vacia")
        p.tocar(etiqueta("tecnica-mandar"))
        Telefono.captura("tec-6-elegir")
        p.tocar(etiqueta("tecnica-ejercicio-0"))
        p.tocar(etiqueta("tecnica-aviso-ok"))
        elegirYEnviar()
        p.nodo(etiqueta("tecnica-recibido"), 30_000)
        p.tocar(etiqueta("tecnica-listo"))
        p.nodo(etiqueta("tecnica-fila-enviado"))
        Telefono.captura("tec-7-lista-enviado")
        assertFalse("con uno en revisión no se manda otro", p.existe(etiqueta("tecnica-mandar")))
    }

    @Test fun avisoUnaSolaVez() {
        desdeEjercicio("corte")
        p.nodo(etiqueta("tecnica-consejo"))
        assertFalse(p.existe(etiqueta("tecnica-aviso")))
    }

    @Test fun corteEsperaYSePuedeCancelar() {
        val d = desdeEjercicio("corte")
        elegirYEnviar()
        p.nodo(etiqueta("tecnica-cancelar"), 30_000)
        Telefono.captura("tec-8-esperando-senal")
        assertFalse(p.existe(etiqueta("tecnica-recibido")))
        p.tocar(etiqueta("tecnica-cancelar"))
        p.nodo(etiqueta("tecnica-consejo"))
        assertTrue(d.envios.isEmpty())
    }

    @Test fun reintentaAnte503Y429() {
        val d = desdeEjercicio("reintento")
        elegirYEnviar()
        p.nodo(etiqueta("tecnica-recibido"), 30_000)
        assertEquals(3, d.intentosDeSubida)
    }

    @Test fun rechazoSeVeYDejaProbarDeNuevo() {
        desdeEjercicio("rechazo")
        elegirYEnviar()
        p.nodo(etiqueta("tecnica-aviso-envio"), 30_000)
        Telefono.captura("tec-9-rechazo")
        p.nodo(textoQueContiene("muy corto"))
        p.nodo(etiqueta("tecnica-agregar-video"))
    }

    @Test fun topeSemanal() {
        desdeEjercicio("tope")
        elegirYEnviar()
        p.nodo(etiqueta("tecnica-aviso-envio"), 30_000)
        p.nodo(textoQueContiene("3 videos"))
    }

    private fun noHayNada(escenario: String, d: DobleTecnica) {
        p.nodo(etiqueta("pestana-entreno"))
        p.quieto(2500)
        abrirPaginaDelEjercicio(ejercicio)
        p.quieto(1500)
        assertFalse(escenario, p.existe(etiqueta("tecnica-mandar-ejercicio")))
        p.atras()
        p.tocar(etiqueta("pestana-revision"))
        p.tocar(etiqueta("mis-datos"))
        p.nodo(etiqueta("mis-datos-pantalla"))
        assertFalse(escenario, p.existe(etiqueta("mis-datos-tecnica")))
        assertTrue("$escenario: subió algo", d.bytesSubidos.isEmpty())
    }

    @Test fun palancaApagadaNoLlamaNiMuestra() {
        val d = lanzar("apagado")
        noHayNada("apagado", d)
        assertTrue("llamó: ${d.llamadasTecnica}", d.llamadasTecnica.isEmpty())
    }

    @Test fun sinServidorNoHayNada() {
        val d = lanzar("sinServidor")
        noHayNada("sinServidor", d)
    }

    @Test fun enRevisionNoDejaMandarOtro() {
        desdeEjercicio("enRevision")
        p.nodo(etiqueta("tecnica-en-curso"))
        Telefono.captura("tec-10-en-curso")
    }

    private fun publicado(tema: String) {
        miTecnica("publicado")
        p.tocar(etiqueta("tecnica-fila-publicado"))
        p.nodo(etiqueta("tecnica-credito"))
        Telefono.captura("tec-11-devolucion-$tema")
        p.nodo(texto("Lo revisó Mati el 12/11"))
        p.tocar(etiqueta("tecnica-ver-en-video"))
        p.nodo(etiqueta("tecnica-video"))
        Telefono.captura("tec-12-video-$tema")
        // Con el reproductor abierto, Android 9 sin ventana se queda sin dibujar al recrear la Activity (cambio de letra del @After).
        p.atras()
        p.nodo(etiqueta("tecnica-credito"))
    }

    @Test fun publicadoClaro() = publicado("claro")

    @Test fun publicadoOscuro() {
        Telefono.modoNoche(true)
        publicado("oscuro")
    }

    @Test fun publicadoLetraGrande() {
        Telefono.shell("settings put system font_scale 1.3")
        publicado("grande")
    }

    @Test fun sinCorrecciones() {
        miTecnica("publicadoSinCorrecciones")
        p.tocar(etiqueta("tecnica-fila-publicado"))
        p.nodo(etiqueta("tecnica-sin-correcciones"))
        Telefono.captura("tec-13-sin-correcciones")
    }

    @Test fun rechazadoEnLaLista() {
        miTecnica("rechazado")
        p.nodo(etiqueta("tecnica-fila-rechazado"))
        Telefono.captura("tec-14-rechazado")
    }

    @Test fun sacarVideo() {
        miTecnica("publicado")
        p.tocar(etiqueta("tecnica-fila-publicado"))
        p.nodo(etiqueta("tecnica-ver-en-video"))
        p.tocar(etiqueta("tecnica-sacar"))
        p.tocar(etiqueta("tecnica-sacar-si"))
        p.esperarQueNoEste(etiqueta("tecnica-ver-en-video"))
    }
}
