package com.pumpteam.mypump.ui

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import androidx.compose.ui.unit.toSize
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Los reproductores de «Tu guía» toman la proporción real del clip (pedido de Mati del 6/11: nunca franjas negras), con MP4
 * locales de prueba (assets/videos: barras de color, nunca clips reales) de 570×720, 1280×720 y 720×720. El vertical no pasa
 * del 60 % del alto y la pantalla completa también respeta la proporción. Capturas `video-<formato>`.
 */
@RunWith(AndroidJUnit4::class)
class VideoProporcionUiTest : PruebaUi() {
    private fun fixture(n: String): String =
        InstrumentationRegistry.getInstrumentation().context.assets.open("guia/$n.json").use { it.readBytes().toString(Charsets.UTF_8) }

    @Before
    fun sinProporcionesGuardadas() {
        com.pumpteam.mypump.guia.ProporcionesVideo.olvidar(app)
        com.pumpteam.mypump.guia.RecuadrosVideo.olvidar(app)
    }

    /** Lo que se guardó con estos MP4 (por id de clip) no tiene que llegar a las otras pruebas de la guía. */
    @org.junit.After
    fun sinLoDeEstasPruebas() {
        com.pumpteam.mypump.guia.ProporcionesVideo.olvidar(app)
        com.pumpteam.mypump.guia.RecuadrosVideo.olvidar(app)
    }

    /** El MP4 de prueba copiado a la app (file://, sin red). */
    private fun video(formato: String): String {
        val f = File(app.cacheDir, "video-prueba-$formato.mp4")
        InstrumentationRegistry.getInstrumentation().context.assets.open("videos/$formato.mp4").use { i -> f.outputStream().use { i.copyTo(it) } }
        return "file://${f.absolutePath}"
    }

    private fun guiaCon(url: String): String = JSONObject(fixture("get-tomas-avanzado")).apply {
        val clips = getJSONArray("clips")
        for (i in 0 until clips.length()) clips.getJSONObject(i).let { if (!it.isNull("url")) it.put("url", url) }
    }.toString()

    private fun probar(formato: String, proporcion: Float, tolerancia: Float = 0.03f) {
        servidor.respuestas["entregas_app_resumen"] = """{"ok": true, "total": 17, "vistos": 4, "minutos_restantes": 9.0}"""
        servidor.respuestas["entregas_app_get"] = guiaCon(video(formato))
        servidor.respuestas["entregas_app_avance"] = "true"
        servidor.respuestas["entregas_app_agenda"] = ServidorDePrueba.SIN_FUNCION
        guardarCuenta()
        val e = abrir()
        p.tocar(etiqueta("tarjeta-guia"))
        p.nodo(etiqueta("guia-cabecera"))
        val pantalla = app.resources.displayMetrics
        // La caja pasa del 16:9 de mientras carga a la proporción del clip, apenas Media3 sabe su tamaño.
        val caja = p.esperar("la caja del video con la proporción $proporcion", ms = 30_000, enElPrincipal = false) {
            val n = p.nodo(etiqueta("guia-video"))
            // El tamaño entero (los límites en pantalla se cortan si la caja sigue más abajo del borde).
            val b = p.enPrincipal { androidx.compose.ui.geometry.Rect(n.positionInRoot, n.size.toSize()) }
            b.takeIf { it.height > 0f && kotlin.math.abs(it.width / it.height - proporcion) < tolerancia }
        }
        // El vertical topa al 60 % del alto de la pantalla; nunca más ancho que la tarjeta.
        assertTrue("alto ${caja.height} de ${pantalla.heightPixels}", caja.height <= pantalla.heightPixels * 0.6f + 2f)
        assertTrue(caja.width <= pantalla.widthPixels)
        // Centrada en la tarjeta.
        val nt = p.nodo(etiqueta("guia-reproductor"))
        val tarjeta = p.enPrincipal { androidx.compose.ui.geometry.Rect(nt.positionInRoot, nt.size.toSize()) }
        assertEquals((tarjeta.left + tarjeta.right) / 2f, (caja.left + caja.right) / 2f, 2f)
        // Para la captura, el video entero a la vista.
        p.desplazar(etiqueta("guia-lista"), caja.top - 120f)
        p.quieto(800)
        Telefono.captura("video-$formato")
        // Pantalla completa: la misma proporción, lo más grande que entra.
        e.onActivity { a -> a.findViewById<android.view.View>(androidx.media3.ui.R.id.exo_fullscreen)?.performClick() }
        val completa = p.esperar("la pantalla completa", enElPrincipal = false) {
            val n = p.nodo(etiqueta("guia-video-completo-caja"))
            p.enPrincipal { androidx.compose.ui.geometry.Rect(n.positionInRoot, n.size.toSize()) }.takeIf { it.height > 0f }
        }
        assertEquals(proporcion, completa.width / completa.height, tolerancia)
        Telefono.captura("video-$formato-completa")
        e.close()
    }

    /**
     * Un clip con las franjas metidas en el archivo (1280×720 con contenido solo en las columnas 422 a 855, como FT-2b): la
     * caja toma la proporción de la zona útil (~0,6, recortando 1 px más del cuadro analizado) y no la del archivo.
     */
    @Test
    fun conFranjasEnElArchivo() = probar("con-franjas", 432f / 720f, tolerancia = 0.03f)

    @Test
    fun vertical() = probar("vertical", 570f / 720f)

    @Test
    fun horizontal() = probar("horizontal", 1280f / 720f)

    @Test
    fun cuadrado() = probar("cuadrado", 1f)
}
