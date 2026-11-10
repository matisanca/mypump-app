package com.pumpteam.mypump.ui

import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/**
 * La carga simple en la pantalla real de Entreno (gemelo de CargaSimpleUITests.swift), con la cuenta grabada y un historial de
 * 58 kg × 10 en la serie 1 y × 9 en las otras. Lo fino (aumentos, guardia a los 10 s, relanzar) está en los tests de `core`; acá va
 * lo que solo se ve con la vista.
 */
@RunWith(AndroidJUnit4::class)
class CargaSimpleUiTest : PruebaUi() {
    private val lugar = "jalon-al-pecho-prono-dorsal-ancho-d1-0"
    private val ok = etiqueta("ok-serie")

    private fun lanzar() {
        servidor.respuestas["mypump_get_sesion_dia"] = "[]"
        servidor.respuestas["mypump_iniciar_sesion"] = "\"ses-prueba-1\""
        guardarCuenta()
        abrir()
        p.nodo(etiqueta("entreno-cabecera"))
        abrirPaginaDelEjercicio(lugar)
        p.nodo(etiqueta("fila-serie-1"))
        p.esperar("la carga de la vez pasada") { p.textoDe(etiqueta("carga-valor")).takeIf { it.isNotEmpty() } }
    }

    private fun fila(n: Int) = p.descripcion(etiqueta("fila-serie-$n"))

    @Test
    fun laCargaUnicaSeAplicaATodasLasPendientes() {
        lanzar()
        Telefono.captura("carga-1-pantalla")
        p.tocar(etiqueta("carga-mas"))
        val tras = p.esperar("subió la carga") { p.textoDe(etiqueta("carga-valor")).takeIf { it != "58" } }
        for (n in 1..4) assertTrue(fila(n), fila(n).contains("$tras kilos"))
        assertTrue("El − y el + tienen que estar a la vista", p.existe(etiqueta("reps-mas")) && p.existe(etiqueta("reps-menos")))
        darOK()
        esperarHecha(1)
        assertTrue("grabó otro kilo: ${fila(1)}", fila(1).contains("$tras kilos"))
        // La serie 2 sale con el kilo nuevo (el error de producción era el kilo viejo).
        darOK()
        esperarHecha(2)
        assertTrue(fila(2), fila(2).contains("$tras kilos"))
        val cargas = p.esperar("las dos en el servidor") { servidor.a("mypump_registrar_carga").takeIf { it.size == 2 } }
        val kilos = tras.replace(",", ".")
        assertTrue(cargas.toString(), cargas.all { it.contains("\"p_peso\":$kilos") })
    }

    @Test
    fun deshacerVuelveLaSeriePendienteYNoLlegaAlServidor() {
        lanzar()
        darOK()
        esperarHecha(1)
        p.nodo(etiqueta("deshacer-ok"))
        Telefono.captura("carga-2-deshacer")
        p.tocar(etiqueta("deshacer-ok"))
        p.esperar("la serie pendiente") { fila(1).contains("pendiente").takeIf { it } }
        p.esperarQueNoEste(etiqueta("deshacer-ok"), ms = 2_000)   // la cápsula se va con una animación corta
        p.quieto(7_000)   // más que la ventana: no sale nada
        assertTrue("la deshecha llegó al servidor", servidor.a("mypump_registrar_carga").isEmpty())
    }

    @Test
    fun laVentanaVenceSolaYElOKSaleAlServidor() {
        lanzar()
        darOK()
        esperarHecha(1)
        p.esperarQueNoEste(etiqueta("deshacer-ok"), ms = 12_000)
        p.esperar("la serie en el servidor") { servidor.a("mypump_registrar_carga").firstOrNull() }
    }

    @Test
    fun pesoPorSerieSoloCambiaEsaSerie() {
        lanzar()
        p.tocar(etiqueta("toggle-mismo-peso"))
        p.nodo(etiqueta("kg-serie-2"))
        val antes1 = p.textoDe(etiqueta("kg-serie-1"))
        val antes2 = p.textoDe(etiqueta("kg-serie-2"))
        val antes3 = p.textoDe(etiqueta("kg-serie-3"))
        p.tocar(etiqueta("kg-mas-2"))
        p.esperar("subió la 2") { (p.textoDe(etiqueta("kg-serie-2")) != antes2).takeIf { it } }
        assertEquals(antes1, p.textoDe(etiqueta("kg-serie-1")))
        assertEquals(antes3, p.textoDe(etiqueta("kg-serie-3")))
        p.tocar(etiqueta("kg-menos-3"))
        p.esperar("bajó la 3") { (p.textoDe(etiqueta("kg-serie-3")) != antes3).takeIf { it } }
        assertEquals(antes1, p.textoDe(etiqueta("kg-serie-1")))
        Telefono.captura("carga-3-por-serie")
    }

    @Test
    fun unaSerieHechaSeCorrigeYNoSeDesmarca() {
        lanzar()
        darOK()
        esperarHecha(1)
        p.tocar(etiqueta("fila-serie-1"))
        p.nodo(etiqueta("correccion-guardar"))
        assertTrue("tocar una serie hecha la desmarcó", fila(1).contains("hecha"))
        p.tocar(etiqueta("reps-menos"))
        p.quieto(300)
        Telefono.captura("carga-4-correccion")
        p.tocar(etiqueta("correccion-guardar"))
        p.esperarQueNoEste(etiqueta("correccion-guardar"))
        assertTrue(fila(1), fila(1).contains("hecha: 9 repeticiones"))
        p.esperar("la corrección en el servidor") { servidor.a("mypump_registrar_carga").lastOrNull()?.takeIf { it.contains("\"p_reps\":9") } }
    }

    /** El peso se corrige con el teclado: el campo está en el panel, y el panel no se puede esconder mientras se corrige. */
    @Test
    fun corregirElPesoConElTeclado() {
        lanzar()
        darOK()
        esperarHecha(1)
        p.tocar(etiqueta("fila-serie-1"))
        p.nodo(etiqueta("correccion-guardar"))
        val kg = etiqueta("correccion-kg")
        p.tocarDeVerdad(kg)
        p.esperar("el foco en el peso") { p.enfocado(kg).takeIf { it } }
        p.quieto(800)
        assertTrue("el panel se llevó el campo", p.enfocado(kg))
        p.teclear(kg, "55")
        p.esperar("55") { (p.textoDe(kg) == "55").takeIf { it } }
        p.tocar(etiqueta("correccion-guardar"))
        p.esperarQueNoEste(etiqueta("correccion-guardar"))
        p.esperar("corregida") { fila(1).contains("55 kilos").takeIf { it } }
    }

    @Test
    fun repetirElOKAlInstantePideUnSegundoToque() {
        lanzar()
        darOK()
        esperarHecha(1)
        p.quieto(700)
        p.tocar(ok)
        p.esperar("la guardia") { p.descripcion(ok).startsWith("¿Ya hiciste").takeIf { it } }
        assertTrue("la guardia no frenó el OK", fila(2).contains("pendiente"))
        p.quieto(950)
        p.tocar(ok)
        esperarHecha(2)
    }

    /** El dial con el dedo: hacia arriba suma, y deslizar sobre él no desplaza la pantalla. */
    @Test
    fun elDialSeDeslizaConElDedo() {
        lanzar()
        p.esperar("OK listo") { p.descripcion(ok).startsWith("OK, registrar 10").takeIf { it } }
        val densidad = app.resources.displayMetrics.density
        p.deslizarDeVerdad(etiqueta("reps-dial"), -(26 * 3.6f * densidad).toInt())
        val r = p.esperar("sumó") { Regex("""registrar (\d+)""").find(p.descripcion(ok))?.groupValues?.get(1)?.toInt()?.takeIf { it > 10 } }
        assertTrue("sumó $r", r in 12..14)
        p.tocar(etiqueta("reps-menos"))
        p.esperar("restó") { p.descripcion(ok).startsWith("OK, registrar ${r - 1}").takeIf { it } }
    }

    /** Con el teclado arriba el panel se esconde: si no, en un teléfono chico tapa el campo y se podría dar OK sin verlo. */
    @Test
    fun conElTecladoElPanelSeEsconde() {
        lanzar()
        p.nodo(ok)
        p.tocarDeVerdad(etiqueta("carga-valor"))
        p.esperarQueNoEste(ok)
        p.tocar(etiqueta("carga-mas"))   // saca el foco
        p.atras()
        p.nodo(ok)
    }

    /** Sin red: el OK se anota igual, no pierde la serie y sale cuando vuelve. */
    @Test
    fun sinRedElOKQuedaYSaleAlVolver() {
        lanzar()
        servidor.sinRed = true
        darOK()
        esperarHecha(1)
        p.esperarQueNoEste(etiqueta("deshacer-ok"), ms = 12_000)
        assertTrue(fila(1), fila(1).contains("hecha"))
        servidor.sinRed = false
        p.quieto(11_000)   // sin guardia
        darOK()
        esperarHecha(2)
        p.esperar("las dos en el servidor", ms = 60_000) { servidor.a("mypump_registrar_carga").takeIf { c -> c.any { it.contains("\"p_serie\":1") } && c.any { it.contains("\"p_serie\":2") } } }
    }

    @Test
    fun sinRirEnPantalla() {
        lanzar()
        p.quieto(500)
        assertFalse("quedó RIR en pantalla", p.existe(textoQueContiene("RIR")))
        assertFalse("quedó «en reserva» en pantalla", p.existe(textoQueContiene("en reserva")))
    }
}
