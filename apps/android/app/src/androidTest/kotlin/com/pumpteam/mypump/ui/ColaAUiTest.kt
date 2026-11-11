package com.pumpteam.mypump.ui

import androidx.test.ext.junit.runners.AndroidJUnit4
import com.pumpteam.mypump.Entorno
import com.pumpteam.mypump.datos.DobleColaA
import com.pumpteam.mypump.datos.Transporte
import com.pumpteam.mypump.logros.EstadoFestejo
import com.pumpteam.mypump.reglas.RecordSerie
import com.pumpteam.mypump.reglas.ReglasListaPrevia
import com.pumpteam.mypump.reglas.ReglasWins
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/**
 * La cola A (2.3.0) en la pantalla de verdad, contra el doble del servidor (sin red): «Récords y logros», la lista previa a
 * la videollamada y la demo con historial. Lo fino del permiso y de la cola está en `WinsModeloTest` y
 * `ListaPreviaModeloTest` (JVM).
 *
 * ESCRITAS SIN CORRER (10-nov): el encargo de la cola A pidió no levantar emuladores. Antes de darlas por buenas hay que
 * correrlas una vez (`./gradlew connectedDebugAndroidTest`) y ajustar lo que haga falta.
 */
@RunWith(AndroidJUnit4::class)
class ColaAUiTest : PruebaUi() {
    @After
    fun soltar() {
        Telefono.shell("settings put system font_scale 1.0")
        p.enPrincipal { EstadoFestejo.soltar() }
    }

    private fun lanzar(escenario: String): DobleColaA {
        val d = DobleColaA.escenario(escenario)
        val s = servidor
        Entorno.transporte = Transporte { pedido ->
            val r = pedido.ruta
            if ("mypump_wins" in r || r.endsWith("mypump_lista_previa") || r.endsWith("mypump_get_app_config")) d.enviar(pedido) else s.enviar(pedido)
        }
        guardarCuenta()
        abrir()
        p.nodo(etiqueta("pestana-entreno"), ms = 40_000)
        return d
    }

    private val records: List<ReglasWins.Record>
        get() = ReglasWins.records(
            listOf(
                ReglasWins.Ejercicio("remo con barra", "Remo con barra", listOf(RecordSerie.Marca(55.0, 8)), listOf(RecordSerie.Marca(57.5, 8))),
                ReglasWins.Ejercicio("pullover en polea", "Pullover en polea", listOf(RecordSerie.Marca(25.0, 10)), listOf(RecordSerie.Marca(25.0, 11))),
            ),
        )

    /** El festejo, sin cerrar una sesión: lo que deja `HojaCerrarDia` cuando el cierre salió bien. */
    private fun festejar() {
        p.enPrincipal { EstadoFestejo.mostrando = records }
        p.nodo(etiqueta("hoja-festejo"))
    }

    private fun abrirMisDatos() {
        p.tocar(etiqueta("pestana-revision"))
        p.tocar(etiqueta("mis-datos"))
        p.nodo(etiqueta("mis-datos-pantalla"))
    }

    @Test
    fun conLasPalancasApagadasNoSeVeNiSeLlamaNada() {
        val d = lanzar("apagado")
        p.quieto(1_500)
        assertFalse(p.existe(etiqueta("lista-previa")))
        assertFalse(p.existe(etiqueta("lista-previa-dentro")))
        // Tampoco de muestra: sin la función prendida no hay festejo.
        p.enPrincipal { EstadoFestejo.mostrando = records }
        p.quieto(1_000)
        assertFalse(p.existe(etiqueta("hoja-festejo")))
        abrirMisDatos()
        assertFalse(p.existe(etiqueta("seccion-logros")))
        assertTrue(d.llamadasWins.isEmpty())
        assertTrue(d.llamadasLista.isEmpty())
    }

    @Test
    fun sinElServidorNuevoTampocoSeVeNada() {
        lanzar("sinServidor")
        p.quieto(1_500)
        assertFalse(p.existe(etiqueta("lista-previa")))
        abrirMisDatos()
        assertFalse(p.existe(etiqueta("seccion-logros")))
    }

    @Test
    fun laListaPreviaArribaDeEntrenoYLlevaALasFotos() {
        lanzar("sinPermiso")
        p.nodo(etiqueta("lista-previa"))
        p.nodo(texto(ReglasListaPrevia.TITULO))
        p.nodo(texto("Llevás 1 de 3"))
        p.nodo(texto("Te faltan 2 videos"))
        p.nodo(texto(ReglasListaPrevia.CONSEJO))
        assertEquals("Subir tus fotos de inicio, Falta", p.descripcion(etiqueta("lista-previa-fotos")))
        Telefono.captura("cola-a-lista-previa")
        p.tocar(etiqueta("lista-previa-fotos"))
        p.esperar("Revisión elegida") { p.seleccionado(etiqueta("pestana-revision")).takeIf { it } }
    }

    @Test
    fun laListaPreviaConLetraMuyGrande() {
        Telefono.shell("settings put system font_scale 2.0")
        lanzar("sinPermiso")
        p.nodo(etiqueta("lista-previa"))
        // Las cuatro filas y el consejo siguen estando (se llega desplazando), y la de las fotos sigue siendo un botón.
        for (clave in listOf("guia", "dudas", "formulario", "fotos")) p.nodo(etiqueta("lista-previa-$clave"))
        p.nodo(etiqueta("lista-previa-consejo"))
        Telefono.captura("cola-a-lista-previa-letra-grande")
        p.tocar(etiqueta("lista-previa-fotos"))
        p.esperar("Revisión elegida") { p.seleccionado(etiqueta("pestana-revision")).takeIf { it } }
    }

    @Test
    fun conTodoListoLoDice() {
        lanzar("listaLista")
        p.nodo(etiqueta("lista-previa"))
        p.nodo(texto(ReglasListaPrevia.TODO_LISTO))
    }

    @Test
    fun elFestejoPideElPermisoYDejaLosRecords() {
        val d = lanzar("sinPermiso")
        festejar()
        p.nodo(texto(ReglasWins.titulo(2)))
        p.nodo(texto(ReglasWins.subtitulo(2)))
        p.nodo(etiqueta("festejo-record-0"))
        p.nodo(etiqueta("festejo-record-1"))
        assertFalse(p.existe(etiqueta("festejo-con-permiso")))
        Telefono.captura("cola-a-festejo")
        p.tocar(etiqueta("festejo-contarle"))
        p.nodo(etiqueta("hoja-permiso-logros"))
        p.nodo(texto(ReglasWins.PERMISO_TITULO))
        Telefono.captura("cola-a-permiso")
        p.tocar(etiqueta("permiso-si"))
        p.nodo(etiqueta("festejo-con-permiso"))
        p.nodo(texto(ReglasWins.conPermiso(2)))
        p.esperar("los dos récords en el servidor") { (d.registrados.size == 2).takeIf { it } }
        assertEquals(listOf("record_kg", "record_reps"), d.registrados.map { it.tipo })
        p.tocar(etiqueta("festejo-seguir"))
        p.esperarQueNoEste(etiqueta("hoja-festejo"))
    }

    @Test
    fun ahoraNoNoMandaNada() {
        val d = lanzar("sinPermiso")
        festejar()
        p.tocar(etiqueta("festejo-contarle"))
        p.tocar(etiqueta("permiso-no"))
        p.esperarQueNoEste(etiqueta("hoja-permiso-logros"))
        p.tocar(etiqueta("festejo-seguir"))
        p.esperarQueNoEste(etiqueta("hoja-festejo"))
        assertTrue(d.permisosPedidos.isEmpty())
        assertTrue(d.registrados.isEmpty())
    }

    @Test
    fun sinRedElPermisoAvisaYNoQuedaDado() {
        lanzar("sinRedPermiso")
        festejar()
        p.tocar(etiqueta("festejo-contarle"))
        p.tocar(etiqueta("permiso-si"))
        p.nodo(etiqueta("permiso-aviso"))
        p.nodo(texto(ReglasWins.SIN_RED))
    }

    @Test
    fun elFestejoConLetraMuyGrandeDejaLosBotonesALaVista() {
        Telefono.shell("settings put system font_scale 2.0")
        lanzar("sinPermiso")
        festejar()
        // Los botones van fuera de lo que se desplaza: se tocan sin desplazar.
        p.nodo(etiqueta("festejo-contarle"))
        Telefono.captura("cola-a-festejo-letra-grande")
        p.tocar(etiqueta("festejo-seguir"))
        p.esperarQueNoEste(etiqueta("hoja-festejo"))
    }

    @Test
    fun elInterruptorDeMisDatosSacaElPermiso() {
        val d = lanzar("conPermiso")
        abrirMisDatos()
        p.nodo(etiqueta("seccion-logros"))
        p.nodo(texto(ReglasWins.AJUSTE_SECCION))
        p.nodo(texto(ReglasWins.AJUSTE_INTERRUPTOR))
        p.nodo(texto(ReglasWins.AJUSTE_PIE))
        p.tocar(etiqueta("logros-interruptor"))
        p.nodo(texto(ReglasWins.DESACTIVADO))
        assertEquals(listOf(false), d.permisosPedidos.toList())
        assertFalse(d.permiso)
        // Prenderlo de nuevo pide el permiso explícito.
        p.tocar(etiqueta("logros-interruptor"))
        p.nodo(etiqueta("hoja-permiso-logros"))
        p.tocar(etiqueta("permiso-si"))
        p.esperar("el permiso dado") { d.permiso.takeIf { it } }
    }

    @Test
    fun laDemoTraeLaListaPreviaElHistorialYElChat() {
        abrir()
        p.tocar(etiqueta("ver-demo"))
        p.nodo(etiqueta("pestana-entreno"), ms = 40_000)
        // La lista previa de la demo (sola, o dentro de la tarjeta de la videollamada de muestra).
        p.esperar("la lista previa") { (p.existe(etiqueta("lista-previa")) || p.existe(etiqueta("lista-previa-dentro"))).takeIf { it } }
        p.nodo(etiqueta("pump-del-dia"))
        // El chat con Mati y su devolución.
        p.tocar(etiqueta("pestana-chat"))
        p.nodo(texto("Buenas, cómo arrancaste la semana?"))
        p.tocar(etiqueta("pestana-revision"))
        p.nodo(etiqueta("devolucion-seccion"))
        // El festejo de la demo no manda nada: lo dice.
        p.enPrincipal { EstadoFestejo.mostrando = records }
        p.nodo(etiqueta("hoja-festejo"))
        p.tocar(etiqueta("festejo-contarle"))
        p.nodo(etiqueta("festejo-demo"))
        p.nodo(texto(ReglasWins.DEMO))
        assertFalse(p.existe(etiqueta("hoja-permiso-logros")))
    }
}
