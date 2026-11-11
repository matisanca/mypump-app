package com.pumpteam.mypump.ui

import androidx.test.ext.junit.runners.AndroidJUnit4
import com.pumpteam.mypump.Entorno
import com.pumpteam.mypump.datos.DobleFotosInicio
import com.pumpteam.mypump.datos.Transporte
import com.pumpteam.mypump.reglas.FotosInicio
import com.pumpteam.mypump.reglas.TextosFotosInicio
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Fotos de inicio contra el doble del servidor (sin red) y con las fotos de mentira del modo de prueba
 * ([Entorno.fotosInicioDePrueba]). Lo fino de la cola está en `FotosInicioTest`; acá, la pantalla de verdad.
 */
@RunWith(AndroidJUnit4::class)
class FotosInicioUiTest : PruebaUi() {
    @After
    fun soltar() {
        Entorno.fotosInicioDePrueba = null
        Telefono.shell("settings put system font_scale 1.0")
    }

    private fun lanzar(escenario: String, foto: String = "buena"): DobleFotosInicio {
        val d = DobleFotosInicio.escenario(escenario)
        val s = servidor
        Entorno.transporte = Transporte { pedido ->
            if ("inicio" in pedido.ruta || pedido.ruta.endsWith("mypump_get_app_config")) d.enviar(pedido) else s.enviar(pedido)
        }
        Entorno.fotosInicioDePrueba = foto
        guardarCuenta()
        abrir()
        return d
    }

    private fun abrirDesdeRevision() {
        p.tocar(etiqueta("pestana-revision"))
        p.tocar(etiqueta("fotos-inicio-tarjeta"), ms = 30_000)
        // La tarjeta abre derecho en la pose que falta; atrás queda el resumen.
        p.nodo(etiqueta("fotos-inicio-instruccion"))
        p.atras()
        p.nodo(etiqueta("fotos-inicio-pose-frente"))
    }

    /** En la pantalla de una pose: saca la foto de mentira y la revisa. */
    private fun sacar() {
        p.nodo(etiqueta("fotos-inicio-instruccion"))
        p.tocar(etiqueta("fotos-inicio-foto"))
        p.nodo(etiqueta("fotos-inicio-vista-previa"), ms = 30_000)
    }

    private fun recorridoCompleto(tema: String): DobleFotosInicio {
        val d = lanzar("vacio")
        p.tocar(etiqueta("pestana-revision"))
        p.nodo(etiqueta("fotos-inicio-tarjeta"), ms = 30_000)
        p.nodo(texto(TextosFotosInicio.cuenta(0)))
        p.nodo(texto(TextosFotosInicio.tarjetaEmpezar))
        Telefono.captura("fi-tarjeta-$tema")
        p.tocar(etiqueta("fotos-inicio-tarjeta"))
        p.nodo(etiqueta("fotos-inicio-instruccion"))
        p.atras()
        p.nodo(etiqueta("fotos-inicio-pose-frente"))
        p.nodo(texto(TextosFotosInicio.faltan(3)))
        p.nodo(texto(TextosFotosInicio.privacidad))
        Telefono.captura("fi-resumen-$tema")
        p.tocar(etiqueta("fotos-inicio-pose-frente"))
        p.nodo(texto(TextosFotosInicio.instruccionFrente))
        Telefono.captura("fi-pose-$tema")
        sacar()
        p.nodo(etiqueta("fotos-inicio-bien"))
        assertFalse("sin problemas no va «Usar igual»", p.existe(etiqueta("fotos-inicio-usar-igual")))
        p.nodo(etiqueta("fotos-inicio-otra"))
        Telefono.captura("fi-revisar-$tema")
        p.tocar(etiqueta("fotos-inicio-usar"))
        // Pasa sola a la que falta.
        p.nodo(texto(TextosFotosInicio.instruccionPerfil))
        sacar()
        p.tocar(etiqueta("fotos-inicio-usar"))
        p.nodo(texto(TextosFotosInicio.instruccionEspalda))
        sacar()
        p.tocar(etiqueta("fotos-inicio-usar"))
        // Con las tres, al resumen.
        p.nodo(etiqueta("fotos-inicio-listo"), ms = 30_000)
        p.esperar("subieron las tres", 30_000) { d.fotos.size.takeIf { it == 3 } }
        p.nodo(texto(TextosFotosInicio.listoTitulo), ms = 30_000)
        Telefono.captura("fi-listo-$tema")
        // El físico que te motiva: una foto y la nota.
        p.tocar(etiqueta("fotos-inicio-motivacion-agregar"))
        p.nodo(etiqueta("fotos-inicio-bien"), ms = 30_000)
        p.tocar(etiqueta("fotos-inicio-usar"))
        p.nodo(etiqueta("fotos-inicio-motivacion-foto"), ms = 30_000)
        p.escribir(etiqueta("fotos-inicio-nota"), "Hombros anchos")
        p.tocar(etiqueta("fotos-inicio-nota-guardar"))
        p.nodo(texto(TextosFotosInicio.motivacionGuardada), ms = 30_000)
        p.esperar("subió la de motivación", 30_000) { d.dePose(FotosInicio.MOTIVACION).size.takeIf { it == 1 } }
        Telefono.captura("fi-motivacion-$tema")
        p.tocar(etiqueta("fotos-inicio-listo"))
        p.nodo(texto(TextosFotosInicio.tarjetaLista), ms = 30_000)
        Telefono.captura("fi-tarjeta-lista-$tema")
        return d
    }

    @Test
    fun recorridoCompleto() {
        val d = recorridoCompleto("claro")
        assertEquals(listOf("frente", "perfil", "espalda", FotosInicio.MOTIVACION), d.fotos.map { it.pose })
        assertEquals("Hombros anchos", d.nota)
        val h = d.cabecerasUltimaSubida
        assertTrue("la fecha va con zona: ${h["x-inicio-tomada"]}", h["x-inicio-tomada"]?.matches(Regex(".*([+-]\\d\\d:\\d\\d|Z)$")) == true)
        assertTrue(h["x-inicio-brillo"] != null && h["x-inicio-nitidez"] != null)
        assertEquals(1200 to 1600, d.fotos[0].ancho to d.fotos[0].alto)
        assertFalse(p.existe(textoQueContiene("inteligencia")))
        assertFalse(p.existe(textoQueContiene("coach")))
    }

    @Test
    fun fotoOscuraConUsarIgual() {
        val d = lanzar("vacio", foto = "oscura")
        abrirDesdeRevision()
        p.tocar(etiqueta("fotos-inicio-pose-frente"))
        sacar()
        p.nodo(etiqueta("fotos-inicio-problema-oscura"))
        p.nodo(texto(TextosFotosInicio.problemaOscura))
        assertFalse("con avisos no va «Usar esta foto»", p.existe(etiqueta("fotos-inicio-usar")))
        assertFalse(p.existe(etiqueta("fotos-inicio-bien")))
        p.nodo(etiqueta("fotos-inicio-otra"))
        Telefono.captura("fi-oscura-claro")
        p.tocar(etiqueta("fotos-inicio-usar-igual"))
        p.nodo(texto(TextosFotosInicio.instruccionPerfil))
        p.esperar("subió la oscura", 30_000) { d.dePose("frente").size.takeIf { it == 1 } }
        // Sacar otra con una buena: ya no hay avisos.
        Entorno.fotosInicioDePrueba = "movida"
        sacar()
        p.nodo(etiqueta("fotos-inicio-problema-movida"))
        Entorno.fotosInicioDePrueba = "buena"
        p.tocar(etiqueta("fotos-inicio-otra"))
        p.nodo(etiqueta("fotos-inicio-bien"), ms = 30_000)
    }

    @Test
    fun fotoChicaNoSePuedeUsar() {
        val d = lanzar("vacio", foto = "chica")
        abrirDesdeRevision()
        p.tocar(etiqueta("fotos-inicio-pose-frente"))
        sacar()
        p.nodo(etiqueta("fotos-inicio-problema-chica"))
        p.nodo(etiqueta("fotos-inicio-otra"))
        assertFalse(p.existe(etiqueta("fotos-inicio-usar")))
        assertFalse(p.existe(etiqueta("fotos-inicio-usar-igual")))
        Telefono.captura("fi-chica-claro")
        p.quieto(1500)
        assertEquals(0, d.intentosDeSubida)
    }

    @Test
    fun palancaApagadaNoSeVeNiLlamaNada() {
        val d = lanzar("apagado")
        p.tocar(etiqueta("pestana-revision"))
        p.quieto(2500)
        assertFalse(p.existe(etiqueta("fotos-inicio-tarjeta")))
        p.tocar(etiqueta("mis-datos"))
        p.nodo(etiqueta("mis-datos-pantalla"))
        assertFalse(p.existe(etiqueta("mis-datos-fotos-inicio")))
        assertTrue("con la palanca apagada no se llama nada: ${d.llamadasFotosInicio}", d.llamadasFotosInicio.isEmpty())
    }

    @Test
    fun noHabilitadoNoSeVe() {
        lanzar("noHabilitado")
        p.tocar(etiqueta("pestana-revision"))
        p.quieto(2500)
        assertFalse(p.existe(etiqueta("fotos-inicio-tarjeta")))
    }

    /** En Entreno, lo primero que se ve al abrir: la tarjeta con el botón grande; un toque lleva a la pose que falta. */
    @Test
    fun tarjetaEnEntrenoConBotonGrande() {
        lanzar("vacio")
        p.nodo(etiqueta("fotos-inicio-tarjeta"), ms = 30_000)
        p.nodo(etiqueta("fotos-inicio-tarjeta-boton"))
        Telefono.captura("fi-entreno-tarjeta-claro")
        p.tocar(etiqueta("fotos-inicio-tarjeta"))
        p.nodo(etiqueta("fotos-inicio-instruccion"))
        p.nodo(etiqueta("fotos-inicio-foto"))
        assertTrue(p.seleccionado(etiqueta("pestana-revision")))
    }

    /** El aviso «subí tus fotos de inicio» (destino `fotos_inicio`), con la app cerrada: abre la pantalla en la pose que falta. */
    @Test
    fun elAvisoAbreLasFotosDeInicio() {
        val d = DobleFotosInicio.escenario("vacio")
        val s = servidor
        Entorno.transporte = Transporte { pedido ->
            if ("inicio" in pedido.ruta || pedido.ruta.endsWith("mypump_get_app_config")) d.enviar(pedido) else s.enviar(pedido)
        }
        Entorno.fotosInicioDePrueba = "buena"
        guardarCuenta()
        registrar(androidx.test.core.app.ActivityScenario.launch<com.pumpteam.mypump.MainActivity>(com.pumpteam.mypump.avisos.CentroAvisos.intentDeAviso(app, "fotos_inicio")))
        p.nodo(etiqueta("fotos-inicio-instruccion"), ms = 30_000)
        p.nodo(etiqueta("fotos-inicio-foto"))
        assertTrue(p.seleccionado(etiqueta("pestana-revision")))
        Telefono.captura("fi-aviso-abre-la-pose-claro")
    }

    /** El mismo aviso con la sección sin habilitar: queda en Revisión, sin pantalla rota. */
    @Test
    fun elAvisoSinHabilitarQuedaEnRevision() {
        val d = DobleFotosInicio.escenario("noHabilitado")
        val s = servidor
        Entorno.transporte = Transporte { pedido ->
            if ("inicio" in pedido.ruta || pedido.ruta.endsWith("mypump_get_app_config")) d.enviar(pedido) else s.enviar(pedido)
        }
        guardarCuenta()
        registrar(androidx.test.core.app.ActivityScenario.launch<com.pumpteam.mypump.MainActivity>(com.pumpteam.mypump.avisos.CentroAvisos.intentDeAviso(app, "fotos_inicio")))
        p.esperar<Boolean>("Revisión elegida") { p.seleccionado(etiqueta("pestana-revision")) }
        p.quieto(2500)
        assertFalse(p.existe(etiqueta("fotos-inicio-instruccion")))
        p.nodo(etiqueta("mis-datos"))
    }

    /** Simplificar: el renglón de Mis datos se fue; la tarjeta fija de Revisión abre las fotos de inicio (también ya mandadas). */
    @Test
    fun desdeLaTarjetaDeRevision() {
        lanzar("completo")
        p.tocar(etiqueta("pestana-revision"))
        p.nodo(texto(TextosFotosInicio.tarjetaLista), ms = 30_000)
        p.tocar(etiqueta("mis-datos"))
        p.nodo(etiqueta("mis-datos-pantalla"))
        assertFalse(p.existe(etiqueta("mis-datos-fotos-inicio")))
        p.tocar(etiqueta("pestana-revision"))
        p.tocar(etiqueta("fotos-inicio-tarjeta"))
        p.nodo(texto(TextosFotosInicio.listoTitulo))
        p.nodo(texto(TextosFotosInicio.lista))
        Telefono.captura("fi-mis-datos-claro")
    }

    @Test
    fun capturasOscuro() {
        Telefono.modoNoche(true)
        guardarTemaOscuro()
        recorridoCompleto("oscuro")
    }

    @Test
    fun letraGrande() {
        Telefono.shell("settings put system font_scale 1.3")
        recorridoCompleto("grande")
    }
}
