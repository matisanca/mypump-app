package com.pumpteam.mypump.ui

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/**
 * «Tu guía» con el [ServidorDePrueba] (sin red de verdad): la tarjeta de inicio con el resumen, abrir la sección (el get
 * solo ahí), los capítulos, el motivo plegado, la placa, las dudas, `ok: false` (la sección desaparece), sin red y la
 * letra más grande. Las capturas (la maqueta) quedan en [Telefono.CARPETA_CAPTURAS] con el prefijo `guia-`; las baja
 * `scripts/nativa/guia-android.sh`.
 *
 * Los videos apuntan a `videos.prueba.invalid`: el reproductor muestra «Necesitás conexión para ver el video», que es lo
 * que se ve sin red. Ver un video de verdad hasta el 80 % es de `GuiaRealUiTest` (contra el servidor).
 */
@RunWith(AndroidJUnit4::class)
class GuiaUiTest : PruebaUi() {
    private fun fixture(n: String): String =
        InstrumentationRegistry.getInstrumentation().context.assets.open("guia/$n.json").use { it.readBytes().toString(Charsets.UTF_8) }

    private val resumen = """{"ok": true, "total": 20, "vistos": 4, "minutos_restantes": 11.6}"""

    private fun conGuia(get: String = fixture("get-marcelo-avanzado"), res: String = resumen) {
        servidor.respuestas["entregas_app_resumen"] = res
        servidor.respuestas["entregas_app_get"] = get
        servidor.respuestas["entregas_app_avance"] = "true"
        servidor.respuestas["entregas_app_duda"] = "true"
        servidor.respuestas["entregas_app_llamada_duda"] = "true"
    }

    /** La guía avanzada con el video de la creatina (un «Ver por qué») ya visto. */
    private fun conCreatinaVista(): String = org.json.JSONObject(fixture("get-marcelo-avanzado")).apply {
        val clips = getJSONArray("clips")
        for (i in 0 until clips.length()) clips.getJSONObject(i).let { if (it.getString("id") == "FT-50b") it.put("visto", true) }
    }.toString()

    @After
    fun letraNormal() {
        Telefono.shell("settings put system font_scale 1.0")
    }

    private fun abrirGuia() {
        p.tocar(etiqueta("tarjeta-guia"))
        p.nodo(etiqueta("guia-cabecera"))
    }

    /** Baja la lista hasta que aparece [s] (los ítems de una lista perezosa no existen hasta verse). */
    /**
     * Deja el video del suplemento abierto arriba de la pantalla. La lista perezosa compone de antemano ítems que todavía no
     * ubicó (sus nodos existen con límites en cero): se baja hasta que el video tenga lugar en pantalla y se ajusta.
     */
    private fun alVideoDelSuplemento() {
        fun arriba(): Float? {
            val n = p.nodo(etiqueta("guia-video-porque-caja"))
            return p.enPrincipal { n.boundsInRoot }.takeIf { it.height > 0f }?.top
        }
        repeat(30) {
            val y = arriba()
            if (y != null) {
                p.desplazar(etiqueta("guia-lista"), y - 420f)
                return
            }
            p.desplazar(etiqueta("guia-lista"), 500f)
        }
    }

    private fun bajarHasta(s: Selector, paso: Float = 600f, veces: Int = 25) {
        repeat(veces) {
            if (p.existe(s)) return
            p.desplazar(etiqueta("guia-lista"), paso)
        }
        p.nodo(s)
    }

    @Test
    fun laTarjetaUsaElResumenYElGetEsSoloAlAbrir() {
        conGuia()
        guardarCuenta()
        abrir()
        p.nodo(etiqueta("tarjeta-guia"))
        assertTrue(p.existe(textoQueContiene("4 de 20 videos, te quedan 12 min")))
        assertTrue(servidor.a("entregas_app_resumen").isNotEmpty())
        // El get marca `abierto_en`: nunca sin que el cliente abra la sección.
        assertEquals(0, servidor.a("entregas_app_get").size)
        abrirGuia()
        p.esperar("el get") { servidor.a("entregas_app_get").size == 1 }
        p.nodo(texto("Hola Marcelo"))
        p.nodo(etiqueta("guia-avance"))
        // Atrás vuelve a Entreno con la tarjeta.
        p.atras()
        p.nodo(etiqueta("tarjeta-guia"))
    }

    @Test
    fun sinGuiaNoHayTarjeta() {
        conGuia(get = """{"ok": false}""", res = """{"ok": false}""")
        guardarCuenta()
        abrir()
        p.nodo(etiqueta("entreno-lista"))
        p.esperar("el resumen") { servidor.a("entregas_app_resumen").isNotEmpty() }
        p.quieto(500)
        assertFalse(p.existe(etiqueta("tarjeta-guia")))
        assertEquals(0, servidor.a("entregas_app_get").size)
    }

    @Test
    fun conOkFalseAlAbrirLaSeccionDesaparece() {
        // El resumen todavía decía que había guía, pero el token se revocó o Mati la sacó: el get da ok false.
        conGuia(get = """{"ok": false}""")
        guardarCuenta()
        abrir()
        p.tocar(etiqueta("tarjeta-guia"))
        p.esperar("el get") { servidor.a("entregas_app_get").size == 1 }
        p.esperarQueNoEste(etiqueta("guia-pantalla"))
        p.esperarQueNoEste(etiqueta("tarjeta-guia"))
        p.nodo(etiqueta("entreno-lista"))
    }

    @Test
    fun capitulosFilasYMotivo() {
        conGuia()
        guardarCuenta()
        abrir()
        abrirGuia()
        // El capítulo del video que suena (el primero sin ver, «Tu app») abierto; los demás, plegados.
        p.nodo(etiqueta("clip-FT-9b"))
        assertEquals("abierto", p.estado(etiqueta("bloque-Tu app")))
        bajarHasta(etiqueta("bloque-Tu entrenamiento"))
        assertEquals("cerrado", p.estado(etiqueta("bloque-Tu entrenamiento")))
        assertFalse(p.existe(etiqueta("clip-FT-5a")))
        p.tocar(etiqueta("bloque-Tu entrenamiento"))
        p.nodo(etiqueta("clip-FT-5a"))
        // El motivo va plegado bajo la flechita, aparte de la fila.
        assertFalse(p.existe(etiqueta("motivo-abierto-FT-5a")))
        p.tocar(etiqueta("motivo-FT-5a"))
        p.nodo(etiqueta("motivo-abierto-FT-5a"))
        assertEquals("desplegado", p.estado(etiqueta("motivo-FT-5a")))
        assertTrue(p.encabezado(etiqueta("bloque-Tu entrenamiento")))
    }

    @Test
    fun tocarUnaFilaCargaEseVideoYSiguienteMuestraLaPlaca() {
        conGuia()
        guardarCuenta()
        abrir()
        abrirGuia()
        p.tocar(etiqueta("clip-FT-9c"))
        p.esperar("el título del video") { p.textosBajo(etiqueta("guia-titulo")).any { it.contains("comida libre") } }
        // Tocar una fila arranca directo, sin placa (como la web).
        assertFalse(p.existe(etiqueta("guia-placa")))
        p.tocar(etiqueta("guia-siguiente"))
        p.nodo(etiqueta("guia-placa"), ms = 1_500)
        assertTrue(p.textosBajo(etiqueta("guia-placa")).any { it.contains("VIDEO 7 DE 17") })
        // Se cierra sola a los 2,6 s.
        p.esperarQueNoEste(etiqueta("guia-placa"), ms = 5_000)
        // Sin poder cargar el video: lo dice, y la lista se sigue viendo.
        p.nodo(etiqueta("guia-sin-conexion-video"), ms = 45_000)
        p.tocar(etiqueta("guia-velocidad"))
        p.nodo(texto("Velocidad 1,25x"))
    }

    @Test
    fun dudaDeVideoYDudaParaLaLlamada() {
        conGuia()
        guardarCuenta()
        abrir()
        abrirGuia()
        p.nodo(etiqueta("duda-video"))
        p.escribir(etiqueta("duda-campo"), "¿Puedo hacerlo en casa?")
        p.tocar(etiqueta("duda-enviar"))
        p.esperar("la duda en el servidor") { servidor.a("entregas_app_duda").size == 1 }
        val cuerpo = servidor.a("entregas_app_duda").single()
        assertTrue(cuerpo.contains("\"p_texto\":\"¿Puedo hacerlo en casa?\"") && cuerpo.contains("\"p_video\":\"FT-9b\""))
        p.nodo(texto("Listo, me llega antes de la videollamada."))
        assertEquals("", p.textoDe(etiqueta("duda-campo")))
        bajarHasta(etiqueta("llamada-campo"))
        assertTrue(p.existe(texto("Ya me dejaste estas 2")))
        p.escribir(etiqueta("llamada-campo"), "Quiero ver el cardio")
        p.tocar(etiqueta("llamada-enviar"))
        p.esperar("la duda general") { servidor.a("entregas_app_llamada_duda").size == 1 }
        p.nodo(texto("Ya me dejaste estas 3"))
    }

    @Test
    fun unFalseDevuelveElTextoAlCampo() {
        conGuia()
        servidor.respuestas["entregas_app_duda"] = "false"
        guardarCuenta()
        abrir()
        abrirGuia()
        p.escribir(etiqueta("duda-campo"), "Una duda que no entra")
        p.tocar(etiqueta("duda-enviar"))
        p.nodo(texto("No se pudo guardar, probá de nuevo."))
        assertEquals("Una duda que no entra", p.textoDe(etiqueta("duda-campo")))
    }

    @Test
    fun sinRedSeVeLaGuiaGuardada() {
        conGuia()
        guardarCuenta()
        abrir().also { app ->
            abrirGuia()
            p.esperar("el get") { servidor.a("entregas_app_get").size == 1 }
            app.close()
        }
        servidor.sinRed = true
        abrir()
        // Sin red la app abre desde su copia; la tarjeta, desde la caché del resumen.
        p.tocar(etiqueta("tarjeta-guia"))
        p.nodo(etiqueta("guia-desde-cache"))
        p.nodo(texto("Hola Marcelo"))
        p.nodo(etiqueta("guia-sin-conexion-video"), ms = 45_000)
    }

    /** Como pack.html (A5): «Ver por qué (N s)» abre el video debajo del suplemento, con su duda; el tilde si ya lo vio. */
    @Test
    fun suplementacionConVerPorQue() {
        conGuia(get = conCreatinaVista())
        guardarCuenta()
        abrir()
        abrirGuia()
        val tituloArriba = p.textosBajo(etiqueta("guia-titulo"))
        bajarHasta(etiqueta("ver-por-que-FT-1b"))
        assertTrue(p.textosBajo(etiqueta("ver-por-que-FT-1b")).any { it.startsWith("Ver por qué (") && it.endsWith(" s)") })
        assertTrue(p.estado(etiqueta("ver-por-que-FT-50b"))!!.contains("visto"))
        assertFalse(p.estado(etiqueta("ver-por-que-FT-1b"))!!.contains("visto"))
        p.tocar(etiqueta("ver-por-que-FT-1b"))
        p.nodo(etiqueta("guia-porque-FT-1b"))
        p.nodo(etiqueta("duda-campo-porque"))
        assertTrue(p.textosBajo(etiqueta("ver-por-que-FT-1b")).contains("Cerrar el video"))
        // El reproductor de arriba no cambia de video.
        assertEquals(tituloArriba, p.textosBajo(etiqueta("guia-titulo")))
        // Otro suplemento cierra el anterior; el mismo botón lo cierra. Sin url (el magnesio), no hay botón, como la web.
        assertFalse(p.existe(etiqueta("ver-por-que-FT-4b")))
        p.tocar(etiqueta("ver-por-que-FT-50b"))
        p.nodo(etiqueta("guia-porque-FT-50b"))
        assertFalse(p.existe(etiqueta("guia-porque-FT-1b")))
        p.tocar(etiqueta("ver-por-que-FT-50b"))
        p.esperarQueNoEste(etiqueta("guia-porque-FT-50b"))
    }

    // ── La maqueta: capturas en claro y en oscuro ──

    @Test
    fun capturasEnClaro() = capturas(oscuro = false)

    @Test
    fun capturasEnOscuro() = capturas(oscuro = true)

    /** Con la letra más grande del sistema (accesibilidad): la cabecera, las filas y las dudas no se cortan. */
    @Test
    fun capturasLetraGrande() {
        Telefono.shell("settings put system font_scale 1.3")
        capturas(oscuro = false, sufijo = "letra-grande", completas = false)
    }

    private fun capturas(oscuro: Boolean, sufijo: String = if (oscuro) "oscuro" else "claro", completas: Boolean = true) {
        Telefono.modoNoche(oscuro)
        conGuia(get = conCreatinaVista())
        guardarCuenta()
        fun foto(n: String) = Telefono.captura("guia-$n-$sufijo")
        abrir()
        p.nodo(etiqueta("tarjeta-guia"))
        foto("01-inicio-tarjeta")
        abrirGuia()
        p.nodo(etiqueta("guia-reproductor"))
        foto("02-cabecera-y-reproductor")
        if (p.existe(etiqueta("guia-lista"))) {
            bajarHasta(etiqueta("duda-campo"), paso = 400f)
            foto("03-duda-del-video")
            bajarHasta(etiqueta("bloque-Tu app"))
            p.desplazar(etiqueta("guia-lista"), 500f)
            foto("04-capitulo-abierto")
            if (completas) {
                p.tocar(etiqueta("motivo-FT-9c"))
                foto("05-motivo-desplegado")
            }
            bajarHasta(etiqueta("guia-llamada"))
            p.desplazar(etiqueta("guia-lista"), 300f)
            foto("06-capitulos-y-llamada")
            bajarHasta(etiqueta("guia-suplementacion"))
            p.desplazar(etiqueta("guia-lista"), 1400f)
            foto("07-suplementacion")
            if (completas) {
                bajarHasta(etiqueta("ver-por-que-FT-1b"))
                p.tocar(etiqueta("ver-por-que-FT-1b"))
                p.nodo(etiqueta("guia-porque-FT-1b"))
                alVideoDelSuplemento()
                foto("07b-ver-por-que-abierto")
                p.tocar(etiqueta("ver-por-que-FT-1b"))
            }
            bajarHasta(etiqueta("guia-fin"))
            foto("08-fin")
        }
        if (completas) {
            if (p.existe(etiqueta("guia-lista"))) bajarHasta(etiqueta("guia-siguiente"), paso = -900f, veces = 40)
            p.tocar(etiqueta("guia-siguiente"))
            p.nodo(etiqueta("guia-placa"), ms = 1_500)
            p.quieto(900)   // que la lista termine de subir hasta el reproductor (la placa dura 2,6 s)
            Telefono.shell("screencap -p ${Telefono.CARPETA_CAPTURAS}/guia-09-placa-$sufijo.png")
        }
    }
}
