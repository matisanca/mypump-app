package com.pumpteam.mypump.ui

import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.pumpteam.mypump.Entorno
import com.pumpteam.mypump.MainActivity
import com.pumpteam.mypump.avisos.CentroAvisos
import com.pumpteam.mypump.datos.DobleEstudios
import com.pumpteam.mypump.datos.DoblePresion
import com.pumpteam.mypump.datos.Respuesta
import com.pumpteam.mypump.datos.Transporte
import com.pumpteam.mypump.presion.TiemposPresion
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/**
 * «Mi salud» (2.3.0, pedido de Mati del 11/11) contra los dobles de Estudios, controles y Presión (sin red, datos
 * inventados): la tarjeta de Revisión con lo pendiente, la pantalla con sus bloques en orden (o con uno solo), los destinos
 * viejos que ahora caen ahí y que en Mis datos queda una sola fila. Capturas `mi-salud-*` en claro, oscuro y letra grande.
 */
@RunWith(AndroidJUnit4::class)
class MiSaludUiTest : PruebaUi() {
    @After
    fun soltar() {
        TiemposPresion.segundosDePrueba = 0
        Telefono.shell("settings put system font_scale 1.0")
        Telefono.modoNoche(false)
    }

    /** Con todo prendido: un control cerca, estudios con novedad y una serie de presión abierta. */
    private fun lanzarTodo(abrirLaApp: () -> Unit = { abrir() }): Pair<DobleEstudios, DoblePresion> {
        val est = DobleEstudios.escenario("controlEnVentana")
        val pres = DoblePresion.escenario("serie0")
        val s = servidor
        Entorno.transporte = Transporte { pedido ->
            val r = pedido.ruta
            when {
                r.endsWith("mypump_get_app_config") ->
                    Respuesta(200, """{"estudios_app":true,"controles_app":true,"presion_app":true}""".toByteArray())
                "estudios" in r || "controles" in r -> est.enviar(pedido)
                "presion" in r -> pres.enviar(pedido)
                else -> s.enviar(pedido)
            }
        }
        TiemposPresion.segundosDePrueba = 1
        guardarCuenta()
        abrirLaApp()
        return est to pres
    }

    private fun tema(t: String) {
        if (t == "oscuro") {
            Telefono.modoNoche(true)
            guardarTemaOscuro()
        }
        if (t == "grande") Telefono.shell("settings put system font_scale 2.0")
    }

    private fun completa(t: String) {
        tema(t)
        lanzarTodo()
        // Simplificar: arriba de Entreno, UNA tarjeta «Mi salud» (en lugar de las de control, estudios y presión), con
        // lo primero para hacer, el número y «Y 2 cosas más».
        p.nodo(etiqueta("tarjeta-mi-salud-inicio"), 40_000)
        p.esperar("las tres cosas en el inicio", 20_000) { p.descripcion(etiqueta("tarjeta-mi-salud-inicio-cuenta")).takeIf { it == "3 cosas para hacer" } }
        p.nodo(texto("Y 2 cosas más"))
        p.nodo(texto("Subir resultado"))
        for (vieja in listOf("control-tarjeta-inicio", "estudios-tarjeta-inicio", "tarjeta-presion")) assertFalse(vieja, p.existe(etiqueta(vieja)))
        Telefono.captura("simplificar-1-entreno-mi-salud-$t")
        p.tocar(etiqueta("pestana-revision"))
        // La tarjeta, arriba, con el número de cosas para hacer y lo primero.
        p.nodo(etiqueta("tarjeta-mi-salud"))
        p.esperar("las tres cosas pendientes", 20_000) { p.descripcion(etiqueta("tarjeta-mi-salud-cuenta")).takeIf { it == "3 cosas para hacer" } }
        p.nodo(texto("Mi salud"))
        p.nodo(texto("Tenés un estudio para hacer"))
        Telefono.captura("mi-salud-revision-$t")
        p.tocar(etiqueta("tarjeta-mi-salud"))
        p.nodo(etiqueta("mi-salud-pantalla"))
        // Los cuatro bloques, en el orden de la spec.
        val orden = listOf("control", "estudios", "presion", "recuperacion").map { "mi-salud-bloque-$it" }
        val ys = p.esperar("los bloques ubicados") { orden.map { p.nodo(etiqueta(it), ms = 0).positionInRoot.y } }
        assertEquals("en orden: $ys", ys.sorted(), ys)
        p.nodo(etiqueta("estudios-proximo"))
        p.nodo(texto("Estudios y órdenes"))
        p.nodo(texto("Te falta hacer"))
        p.nodo(etiqueta("tarjeta-presion"))
        p.nodo(etiqueta("mi-salud-presion"))
        p.nodo(etiqueta("tarjeta-recuperacion-revision"))
        Telefono.captura("mi-salud-completa-$t")
        // Lo de abajo: Presión y Recuperación.
        val y = { tag: String -> p.nodo(etiqueta(tag)).let { n -> p.enPrincipal { n.positionInRoot.y } } }
        val arriba = y("mi-salud-pantalla")
        val presion = y("mi-salud-bloque-presion")
        p.desplazar(etiqueta("mi-salud-pantalla"), presion - arriba)
        Telefono.captura("mi-salud-completa-abajo-$t")
        // Sin palabras prohibidas.
        for (prohibido in listOf("entrenador", "inteligencia", "RIR", "ciclo")) assertFalse(prohibido, p.existe(textoQueContiene(prohibido)))
        // Atrás vuelve a Revisión.
        p.atras()
        p.esperarQueNoEste(etiqueta("mi-salud-pantalla"))
        p.nodo(etiqueta("tarjeta-mi-salud"))
    }

    @Test fun completaClaro() = completa("claro")
    @Test fun completaOscuro() = completa("oscuro")
    @Test fun completaLetraGrande() = completa("grande")

    /** Sin estudios ni presión: solo la recuperación. La tarjeta dice qué hay y no lleva número. */
    private fun unSoloBloque(t: String) {
        tema(t)
        guardarCuenta()
        abrir()
        p.nodo(etiqueta("pestana-entreno"))
        p.tocar(etiqueta("pestana-revision"))
        p.nodo(etiqueta("tarjeta-mi-salud"))
        p.nodo(texto("Recuperación"))
        p.quieto(1500)
        assertFalse("sin nada para hacer no hay número", p.existe(etiqueta("tarjeta-mi-salud-cuenta")))
        Telefono.captura("mi-salud-revision-sin-pendientes-$t")
        p.tocar(etiqueta("tarjeta-mi-salud"))
        p.nodo(etiqueta("mi-salud-bloque-recuperacion"))
        for (b in listOf("control", "estudios", "presion")) assertFalse(b, p.existe(etiqueta("mi-salud-bloque-$b")))
        Telefono.captura("mi-salud-un-bloque-$t")
        // La fila abre Salud en Recuperación y Volver regresa a Mi salud.
        p.tocar(etiqueta("tarjeta-recuperacion-revision"))
        p.esperar("Salud abierta") { p.enSalud() }
        p.esperar("Recuperación elegida") { p.enSeccion("recuperacion") }
        p.tocar(etiqueta("volver"))
        p.nodo(etiqueta("mi-salud-pantalla"))
    }

    @Test fun unSoloBloqueClaro() = unSoloBloque("claro")
    @Test fun unSoloBloqueOscuro() = unSoloBloque("oscuro")
    @Test fun unSoloBloqueLetraGrande() = unSoloBloque("grande")

    /** En Mis datos, Estudios y Presión ya no están sueltas: una sola fila «Mi salud» que lleva ahí. */
    @Test
    fun misDatosTieneUnaSolaFila() {
        lanzarTodo()
        p.nodo(etiqueta("tarjeta-mi-salud-inicio"), 20_000)
        p.tocar(etiqueta("pestana-revision"))
        p.tocar(etiqueta("mis-datos"))
        p.nodo(etiqueta("mis-datos-mi-salud"))
        assertFalse(p.existe(etiqueta("mis-datos-estudios")))
        assertFalse(p.existe(etiqueta("mis-datos-presion")))
        p.tocar(etiqueta("mis-datos-mi-salud"))
        p.nodo(etiqueta("mi-salud-pantalla"))
    }

    /** Sin estudios ni presión la fila sigue (la recuperación vive en Mi salud, como iOS) y lleva a la recuperación sola. */
    @Test
    fun misDatosSinEstudiosNiPresionLlevaALaRecuperacion() {
        guardarCuenta()
        abrir()
        p.tocar(etiqueta("pestana-revision"))
        p.tocar(etiqueta("mis-datos"))
        p.tocar(etiqueta("mis-datos-mi-salud"))
        p.nodo(etiqueta("mi-salud-bloque-recuperacion"))
        assertFalse(p.existe(etiqueta("mi-salud-bloque-estudios")))
    }

    /** El aviso viejo de presión: Mi salud en Presión, con Presión encima; al cerrarla queda Mi salud. */
    @Test
    fun elAvisoDePresionCaeEnMiSalud() {
        lanzarTodo { registrar(ActivityScenario.launch<MainActivity>(CentroAvisos.intentDeAviso(app, "presion"))) }
        p.nodo(etiqueta("presion-cuando"), 30_000)
        p.tocar(etiqueta("presion-flujo-cerrar"))
        p.esperar("cerró Presión") { (!p.existe(etiqueta("presion-cuando"))).takeIf { it } }
        if (p.existe(etiqueta("presion-cerrar-seccion"))) p.tocar(etiqueta("presion-cerrar-seccion"))
        p.nodo(etiqueta("mi-salud-pantalla"))
        p.nodo(etiqueta("mi-salud-bloque-presion"))
        assertTrue(p.seleccionado(etiqueta("pestana-revision")))
    }

    /** La tarjeta «Mi salud» del inicio lleva a lo primero pendiente: con un estudio para hacer, Mi salud en Estudios. */
    @Test
    fun laTarjetaDelInicioLlevaALoPrimeroPendiente() {
        lanzarTodo()
        p.tocar(etiqueta("tarjeta-mi-salud-inicio-boton"), 20_000)
        p.nodo(etiqueta("mi-salud-pantalla"))
        p.nodo(etiqueta("mi-salud-bloque-estudios"))
        assertTrue(p.seleccionado(etiqueta("pestana-revision")))
    }

    /** `?scene=estudios`: Mi salud, en su bloque. */
    @Test
    fun elLinkDeEstudiosCaeEnMiSalud() {
        lanzarTodo { abrirConLink("https://app.mypumpteam.com/?t=${ServidorDePrueba.TOKEN}&scene=estudios") }
        p.nodo(etiqueta("mi-salud-pantalla"), 30_000)
        p.nodo(etiqueta("mi-salud-bloque-estudios"))
    }
}
