package com.pumpteam.mypump.legado

import android.os.Build
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.pumpteam.mypump.datos.FaseRemotaLegado
import com.pumpteam.mypump.datos.FirmaValor
import com.pumpteam.mypump.datos.JsAscii
import com.pumpteam.mypump.datos.LecturaJs
import com.pumpteam.mypump.datos.LevelDbLegado
import com.pumpteam.mypump.datos.Marca
import com.pumpteam.mypump.datos.MigracionLegado
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

/**
 * El lector y la escritura de vuelta con el WebView DE VERDAD (`./gradlew connectedDebugAndroidTest`, en el emulador).
 * Corren en el proceso de la app con su almacén del WebView: usan claves propias (`mypump_prueba_lector_*`) y las borran
 * al terminar, así no tocan lo que haya dejado la Capacitor.
 */
@RunWith(AndroidJUnit4::class)
class LegadoWebViewTest {
    private val contexto = InstrumentationRegistry.getInstrumentation().targetContext
    private val p = "mypump_prueba_lector_"

    private val valores = linkedMapOf(
        "${p}chat" to "Mati, ¿cambio el jalón? 😀",
        "${p}suelto" to "a\uD83Db",
        "${p}nulo" to "x\u0000y",
        "${p}clave\uD800" to "la clave tiene un surrogate suelto",
    )

    /** Más de un tramo de `evaluateJavascript`. Solo en la prueba de lectura: Chromium limita cuántos bytes por hora baja
     *  al disco, y sembrarlo en cada prueba lo agota. */
    private val grande = "z".repeat(LecturaJs.TRAMO + 500_000) + "😀"

    /** Un literal de JavaScript en ASCII (así llega entero aunque tenga un surrogate suelto). */
    private fun js(s: String): String = "'" + JsAscii.escapar(s.replace("\\", "\\\\").replace("'", "\\'").replace("\u0000", "\\u0000")) + "'"

    private fun correr(script: String): String? = runBlocking { conPagina(contexto, 1, 20_000, {}) { pg -> pg.evaluar(script, 20_000) } }

    private fun borrarLasDePrueba() {
        correr("Object.keys(localStorage).filter(function (k) { return k.indexOf(${js(p)}) === 0 || k === ${js(MigracionLegado.CLAVE_MARCA)}; }).forEach(function (k) { localStorage.removeItem(k); }); true")
    }

    @Before
    fun sembrar() {
        borrarLasDePrueba()
        val js = valores.entries.joinToString("\n") { (k, v) -> "localStorage.setItem(${js(k)}, ${js(v)});" } + "\ntrue"
        assertEquals("true", correr(js))
    }

    @After
    fun limpiar() = borrarLasDePrueba()

    private fun soloLasDePrueba(m: Map<String, String>) = m.filterKeys { it.startsWith(p) }

    @Test
    fun leeCadaValorEnteroConLaFirmaDeJavaScript() = runBlocking {
        val lector = LectorWebView(contexto)
        // El leveldb aparece cuando el WebView abre el almacén: no se busca por una ruta fija.
        repeat(50) { if (!lector.hay()) delay(200) }
        assertTrue("no encontré el leveldb del WebView", lector.hay())
        val donde = LevelDbLegado.ubicar(contexto.dataDir).map { LevelDbLegado.relativa(it, contexto.dataDir) }
        assertTrue("$donde", donde.all { it.startsWith("app_webview") && it.endsWith("Local Storage/leveldb") })
        assertEquals("true", correr("localStorage.setItem(${js("${p}grande")}, 'z'.repeat(${LecturaJs.TRAMO + 500_000}) + ${js("😀")}); true"))
        val l = lector.leer()!!
        val esperado = valores + ("${p}grande" to grande)
        assertEquals(esperado, soloLasDePrueba(l.items))
        for ((k, v) in esperado) assertEquals(k, FirmaValor.de(v), l.firmas[k])
        assertTrue(l.huella.archivos.isNotEmpty())
    }

    @Test
    fun laEscrituraDeVueltaBorraSoloLoQueSigueIgualYDejaLaMarca() = runBlocking {
        val lector = LectorWebView(contexto)
        val antes = lector.leer()!!
        val marca = Marca("0b5c6c1e-0000-4000-8000-0000000000aa", 1, "2026-10-14T15:00:00Z", "2.0.0 (100)").texto
        val cambios = FaseRemotaLegado.CambiosEscritura(
            corrida = 1,
            borrar = mapOf(
                "${p}chat" to antes.firmas.getValue("${p}chat"),
                "${p}suelto" to antes.firmas.getValue("${p}suelto"),
                "${p}nulo" to FirmaValor.de("cambió después de leerla"),
                "${p}no_estaba" to FirmaValor.de("x"),
            ),
            marca = marca,
        )
        val r = EscritorLegado(contexto).escribir(cambios)
        assertEquals(
            mapOf("${p}chat" to "borrada", "${p}suelto" to "borrada", "${p}nulo" to "cambio", "${p}no_estaba" to "no estaba", MigracionLegado.CLAVE_MARCA to "ok"),
            r,
        )
        val despues = lector.leer()!!
        assertNull(despues.items["${p}chat"])
        assertNull(despues.items["${p}suelto"])
        assertEquals(valores["${p}nulo"], despues.items["${p}nulo"])
        assertEquals(marca, despues.items[MigracionLegado.CLAVE_MARCA])
        // Que llegue al DISCO lo confirma el arranque siguiente (la prueba de punta a punta, scripts/nativa/emu-migracion.sh):
        // acá todas las pruebas comparten el proceso, y Chromium espacia las bajadas al disco según lo escrito en la hora.
        val t0 = System.currentTimeMillis()
        while (lector.huella() == despues.huella && System.currentTimeMillis() - t0 < 15_000) delay(250)
        android.util.Log.i("MyPumpLegadoTest", "la escritura de vuelta cambió los archivos a los ${System.currentTimeMillis() - t0} ms (tope 15000)")
        Unit
    }

    /** Leer no escribe: la huella de después de una lectura es la de la lectura siguiente (si no, la Fase L correría siempre). */
    @Test
    fun leerNoCambiaLaHuella() = runBlocking {
        val lector = LectorWebView(contexto)
        lector.leer()
        delay(8_000)   // que baje lo que haya sembrado el @Before
        val h1 = lector.leer()!!.huella
        delay(8_000)
        assertEquals(h1, lector.huella())
        assertEquals(h1, lector.leer()!!.huella)
    }

    /** Si el sistema mata el renderer en medio, se arma un WebView nuevo y se reintenta. */
    @Test
    fun siMuereElRendererSeReintenta() = runBlocking {
        renderSeMataDesdeLaPrueba()
        var intentos = 0
        val fallas = mutableListOf<String>()
        val r = conPagina(contexto, 3, 20_000, { fallas += it }) { pg ->
            intentos++
            if (intentos == 1) {
                assertTrue(pg.matarRenderer())
                delay(2_000)   // `terminate()` no espera: el aviso (`onRenderProcessGone`) llega después
            }
            pg.evaluar("1 + 1", 20_000)
        }
        assertEquals("2", r)
        assertEquals(2, intentos)
        assertEquals(listOf("intento 1: murió el proceso del renderer"), fallas)
    }

    /** Sin intentos que alcancen, TIRA: nunca devuelve "no había nada". */
    @Test
    fun sinIntentosTira() = runBlocking {
        renderSeMataDesdeLaPrueba()
        val e = runCatching {
            conPagina(contexto, 2, 20_000, {}) { pg ->
                pg.matarRenderer()
                delay(2_000)
                pg.evaluar("1", 20_000)
            }
        }.exceptionOrNull()
        assertTrue("$e", e is FallaPagina.ProcesoMuerto)
    }

    /**
     * Supuesto de versión: estas pruebas matan el renderer con `WebViewRenderProcess.terminate()`, que es de Android 10 (API
     * 29). En 8 y 9 el sistema también lo puede matar y el aviso (`onRenderProcessGone`) es el mismo, pero desde la prueba no
     * hay cómo provocarlo (`matarRenderer` devuelve false).
     */
    private fun renderSeMataDesdeLaPrueba() {
        assumeTrue("matar el renderer desde la prueba necesita Android 10 (API 29)", Build.VERSION.SDK_INT >= 29)
    }

    /** La página está en el origen de la Capacitor, y nada de lo que pida sale a la red ni trae la app vieja. */
    @Test
    fun origenYSinRed() {
        assertEquals("\"https://localhost\"", correr("location.origin"))
        fun pedir(url: String) = correr(
            "(function () { try { var x = new XMLHttpRequest(); x.open('GET', '$url', false); x.send(); return String(x.status); } catch (e) { return 'error'; } })()",
        )
        val local = pedir("/sw.js")
        assertTrue(local, local == "\"404\"" || local == "\"error\"")
        assertNotEquals("\"200\"", pedir("https://app.mypumpteam.com/"))
    }
}
