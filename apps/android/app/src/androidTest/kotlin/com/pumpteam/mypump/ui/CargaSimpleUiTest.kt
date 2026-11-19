package com.pumpteam.mypump.ui

import android.os.Build
import android.os.SystemClock
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.pumpteam.mypump.entreno.EsperaTrasTeclado
import com.pumpteam.mypump.entreno.RelojCarga
import com.pumpteam.mypump.entreno.SERIE_AHORA
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import java.util.concurrent.atomic.AtomicLong

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
        Telefono.captura("carga-7-correccion-teclado")
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

    // ── Salir del peso sin registrar nada (2.3.3, S2) ──
    // El emulador tiene teclado físico: sin «mostrar el teclado en pantalla» el de la pantalla no sale nunca. Se prende para
    // estas pruebas y se deja como estaba.

    private var imeConTeclado: String? = null

    @Before
    fun tecladoEnPantalla() {
        imeConTeclado = Telefono.shell("settings get secure show_ime_with_hard_keyboard").trim()
        Telefono.shell("settings put secure show_ime_with_hard_keyboard 1")
    }

    @After
    fun dejarComoEstaba() {
        RelojCarga.ahora = { SystemClock.uptimeMillis() }
        Telefono.shell("settings put system font_scale 1.0")
        imeConTeclado?.takeIf { it == "0" || it == "1" }?.let { Telefono.shell("settings put secure show_ime_with_hard_keyboard $it") }
    }

    /** Si el teclado de la pantalla está arriba (los insets de la ventana; desde Android 11). */
    private fun tecladoArriba(): Boolean = p.enPrincipal {
        Raices.activas().any { it.view.rootWindowInsets?.isVisible(android.view.WindowInsets.Type.ime()) == true }
    }

    private fun abrirElTeclado(): Selector {
        val kg = etiqueta("carga-valor")
        p.tocarDeVerdad(kg)
        p.esperar("el foco en el peso") { p.enfocado(kg).takeIf { it } }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) p.esperar("el teclado arriba") { tecladoArriba().takeIf { it } }
        return kg
    }

    private fun esperarTecladoCerrado(kg: Selector) {
        p.esperar("sin foco en el peso") { (!p.enfocado(kg)).takeIf { it } }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) p.esperar("el teclado abajo") { (!tecladoArriba()).takeIf { it } }
        p.esperarQueNoEste(etiqueta("teclado-listo"))
        p.nodo(ok)
    }

    /** Con el teclado del peso arriba está «Listo» (el `teclado-listo` de iOS), en lugar del OK; tocarlo cierra el teclado. */
    @Test
    fun conElTecladoEstaListoYLoCierra() {
        lanzar()
        val kg = abrirElTeclado()
        p.nodo(etiqueta("teclado-listo"))
        assertFalse("el OK quedó a la vista con el teclado", p.existe(ok))
        Telefono.captura("carga-5-listo")
        p.tocarDeVerdad(etiqueta("teclado-listo"))
        esperarTecladoCerrado(kg)
        assertEquals(listOf("0 de 4"), p.textosBajo(etiqueta("series-confirmadas")))
    }

    /** Tocar afuera del número (acá, la pauta de la semana) también cierra el teclado, y no registra nada. */
    @Test
    fun tocarAfueraDelPesoCierraElTeclado() {
        lanzar()
        val kg = abrirElTeclado()
        p.tocarDeVerdad(etiqueta("metricas"))
        esperarTecladoCerrado(kg)
        assertEquals(listOf("0 de 4"), p.textosBajo(etiqueta("series-confirmadas")))
    }

    /**
     * El caso de Sebastián (19/11): escribió 83, cerró el teclado y el toque siguiente cayó en el OK, que había vuelto justo
     * ahí. Con el reloj de la espera quieto, el OK no registra; cumplido el medio segundo, sí (y con los 83 kg).
     */
    @Test
    fun elToqueQueCierraElTecladoNoRegistraLaSerie() {
        val reloj = AtomicLong(1_000_000L)
        RelojCarga.ahora = { reloj.get() }
        lanzar()
        val kg = abrirElTeclado()
        p.quieto(300)   // que se seleccione lo escrito: lo nuevo lo reemplaza
        p.teclear(kg, "83")
        p.esperar("83") { (p.textoDe(kg) == "83").takeIf { it } }
        p.accionTeclado(kg)   // el ✓ del teclado
        esperarTecladoCerrado(kg)
        p.tocar(ok)
        p.tocarDeVerdad(ok)
        p.quieto(800)
        assertEquals("se registró una serie al cerrar el teclado", listOf("0 de 4"), p.textosBajo(etiqueta("series-confirmadas")))
        assertTrue(fila(1), fila(1).contains("pendiente"))
        assertFalse("apareció Deshacer", p.existe(etiqueta("deshacer-ok")))
        reloj.addAndGet(EsperaTrasTeclado.MS)
        p.tocar(ok)
        esperarHecha(1)
        assertTrue(fila(1), fila(1).contains("83 kilos"))
    }

    /** La serie que se carga se ve: «Ahora: serie N de 4» arriba del panel y su fila marcada; las hechas, con su tilde. */
    @Test
    fun laFilaActivaSeDistingue() {
        lanzar()
        assertEquals("Ahora: serie 1 de 4", p.textosBajo(etiqueta("serie-ahora")).joinToString(""))
        assertEquals(SERIE_AHORA, p.estado(etiqueta("fila-serie-1")))
        assertNull(p.estado(etiqueta("fila-serie-2")))
        darOK()
        esperarHecha(1)
        p.esperar("la 2 es la de ahora") { (p.estado(etiqueta("fila-serie-2")) == SERIE_AHORA).takeIf { it } }
        assertNull(p.estado(etiqueta("fila-serie-1")))
        assertEquals("Ahora: serie 2 de 4", p.textosBajo(etiqueta("serie-ahora")).joinToString(""))
        verArribaDelPanel(etiqueta("fila-serie-4"))
        Telefono.captura("carga-6-fila-activa")
    }

    /** Desplaza la página del ejercicio hasta que [s] quede justo arriba del panel (que tapa lo de abajo), para la captura. */
    private fun verArribaDelPanel(s: Selector) {
        val (fila, _) = p.lugarEnVentana(s)
        val (panel, _) = p.lugarEnVentana(etiqueta("panel-carga"))
        val margen = 40f * app.resources.displayMetrics.density
        val dy = fila.bottom + margen - panel.top   // negativo: la fila quedó arriba, fuera de la vista
        if (kotlin.math.abs(dy) > 1f) p.desplazar(etiqueta("ejercicio-pantalla"), dy)
    }

    /** Las capturas de la 2.3.3, con la letra normal y al 130 %: el descanso y el OK se ven sin desplazar. */
    @Test
    fun capturasLetraNormal() = capturas("normal")

    @Test
    fun capturasLetraGrande() = capturas("grande")

    private fun capturas(modo: String) {
        if (modo == "grande") Telefono.shell("settings put system font_scale 1.3")
        lanzar()
        Telefono.captura("s2-$modo-1-ejercicio")
        darOK()
        esperarHecha(1)
        p.nodo(etiqueta("descanso-chip"))
        for (tag in listOf("descanso-chip", "ok-serie")) {
            val (r, alto) = p.lugarEnVentana(etiqueta(tag))
            assertTrue("$tag fuera de la pantalla con la letra $modo: $r (alto $alto)", r.top >= 0f && r.bottom <= alto && r.height > 0f)
        }
        Telefono.captura("s2-$modo-2-descanso")
        verArribaDelPanel(etiqueta("fila-serie-4"))
        Telefono.captura("s2-$modo-3-series")
        abrirElTeclado()
        p.nodo(etiqueta("teclado-listo"))
        Telefono.captura("s2-$modo-4-listo")
    }

    @Test
    fun sinRirEnPantalla() {
        lanzar()
        p.quieto(500)
        assertFalse("quedó RIR en pantalla", p.existe(textoQueContiene("RIR")))
        assertFalse("quedó «en reserva» en pantalla", p.existe(textoQueContiene("en reserva")))
    }
}
