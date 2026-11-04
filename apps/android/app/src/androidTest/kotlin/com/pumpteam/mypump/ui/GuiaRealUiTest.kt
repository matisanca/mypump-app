package com.pumpteam.mypump.ui

import androidx.test.ext.junit.runners.AndroidJUnit4
import com.pumpteam.mypump.Entorno
import com.pumpteam.mypump.datos.Pedido
import com.pumpteam.mypump.datos.Respuesta
import com.pumpteam.mypump.datos.Transporte
import com.pumpteam.mypump.datos.TransporteOkHttp
import java.io.File
import java.io.IOException
import java.util.concurrent.CopyOnWriteArrayList
import org.json.JSONArray
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

/**
 * «Tu guía» de punta a punta contra el servidor, con el cliente de prueba `test-nativa-android`. Solo van a la red de
 * verdad las cuatro RPC `entregas_app_*` (más el resumen) y `mypump_get_cliente_info` (lectura, para que la cuenta entre);
 * todo lo demás lo contesta el [ServidorDePrueba], así nada más se escribe en la base.
 *
 * El token NO está en el repo: `scripts/nativa/guia-android.sh` lo escribe en la carpeta privada de la app
 * (`files/guia-e2e-token`) y la prueba lo lee y lo borra. Sin ese archivo, las pruebas se saltan.
 *
 * Escriben en la cuenta de prueba: el avance del video que se mira, una duda de video y una para la videollamada por corrida
 * (`Prueba nativa Android e2e …`).
 */
@RunWith(AndroidJUnit4::class)
class GuiaRealUiTest : PruebaUi() {
    /** Lo que se mandó al servidor de verdad y lo que contestó. */
    data class Real(val funcion: String, val cuerpo: String, val status: Int, val respuesta: String)

    private val reales = CopyOnWriteArrayList<Real>()

    /** Cambia el token de las `entregas_app_*` por uno inválido: el servidor contesta `ok: false` (guía revocada). */
    @Volatile private var guiaRevocada = false

    private lateinit var token: String

    @Before
    fun alServidor() {
        token = tokenDeLaCorrida() ?: ""
        assumeTrue("sin token de prueba (correr con scripts/nativa/guia-android.sh)", token.isNotEmpty())
        val falso = servidor
        val okhttp = TransporteOkHttp()
        Entorno.transporte = Transporte { pedido ->
            val funcion = pedido.ruta.substringAfterLast('/')
            val aLaRed = funcion.startsWith("entregas_app_") || funcion == "mypump_get_cliente_info"
            if (!aLaRed) return@Transporte falso.enviar(pedido)
            falso.llamadas += ServidorDePrueba.Llamada(funcion, pedido.cuerpo?.toString(Charsets.UTF_8) ?: "")
            if (falso.sinRed) throw IOException("sin conexión (prueba)")
            val enviado = if (guiaRevocada && funcion.startsWith("entregas_app_")) revocar(pedido) else pedido
            val r = okhttp.enviar(enviado)
            reales += Real(funcion, enviado.cuerpo?.toString(Charsets.UTF_8) ?: "", r.status, r.cuerpo.toString(Charsets.UTF_8))
            r
        }
    }

    @After
    fun redPrendida() {
        Telefono.shell("svc wifi enable")
        Telefono.shell("svc data enable")
        Telefono.shell("settings put system font_scale 1.0")
    }

    private fun revocar(p: Pedido): Pedido {
        val o = JSONObject(p.cuerpo!!.toString(Charsets.UTF_8))
        o.put("p_token", "token-revocado-prueba-e2e")
        return p.copy(cuerpo = o.toString().toByteArray())
    }

    private fun reales(f: String) = reales.filter { it.funcion == f }

    private fun foto(n: String) = Telefono.captura("guia-e2e-$n")

    /** La guía que guardó la app al abrir la sección (el `get` de verdad). */
    private fun guiaGuardada(): JSONObject {
        val f = File(app.filesDir, "MyPump").walkTopDown().first { it.name == "guia.json" }
        return JSONObject(f.readText())
    }

    private fun clips(g: JSONObject): List<JSONObject> {
        val a: JSONArray = g.getJSONArray("clips")
        return (0 until a.length()).map { a.getJSONObject(it) }
    }

    private fun abrirGuia() {
        p.tocar(etiqueta("tarjeta-guia"), ms = 30_000)
        p.nodo(etiqueta("guia-cabecera"), ms = 30_000)
    }

    private fun bajarHasta(s: Selector, paso: Float = 600f, veces: Int = 30) {
        repeat(veces) {
            if (p.existe(s)) return
            p.desplazar(etiqueta("guia-lista"), paso)
        }
        p.nodo(s)
    }

    /** La fila de un clip, abriendo su capítulo si estaba plegado. */
    private fun irAFila(id: String, bloque: String) {
        if (p.existe(etiqueta("guia-lista"))) {
            bajarHasta(etiqueta("bloque-$bloque"))
            if (p.estado(etiqueta("bloque-$bloque")) == "cerrado") p.tocar(etiqueta("bloque-$bloque"))
            bajarHasta(etiqueta("clip-$id"), paso = 300f)
        }
    }

    @Test
    fun verUnVideoHastaEl80CerrarYVolver() {
        guardarCuenta(token)
        abrir().also { a ->
            p.nodo(etiqueta("tarjeta-guia"), ms = 30_000)
            foto("01-tarjeta")
            abrirGuia()
            p.esperar("el get") { reales("entregas_app_get").isNotEmpty() }
            assertTrue(reales("entregas_app_get").first().respuesta.contains("\"ok\":true") || reales("entregas_app_get").first().respuesta.contains("\"ok\": true"))
            // El más corto sin ver (si ya están todos vistos, el más corto).
            val todos = clips(guiaGuardada()).filter { !it.isNull("url") }
            val clip = (todos.filter { !it.optBoolean("visto") }.ifEmpty { todos }).minBy { it.optDouble("minutos", 99.0) }
            val id = clip.getString("id")
            val bloque = clip.optString("bloque", "Tu app").trim().ifEmpty { "Tu app" }
            irAFila(id, bloque)
            p.tocar(etiqueta("clip-$id"))
            // A 1,5x para que tarde menos (también prueba la velocidad).
            p.tocar(etiqueta("guia-velocidad"))
            p.tocar(etiqueta("guia-velocidad"))
            p.nodo(texto("Velocidad 1,5x"))
            foto("02-reproduciendo")
            val topeMs = (clip.optDouble("minutos", 1.0) * 60_000 / 1.5).toLong() + 60_000
            p.esperar("el avance con visto de $id", ms = topeMs, enElPrincipal = false) {
                reales("entregas_app_avance").firstOrNull { it.cuerpo.contains("\"p_video\":\"$id\"") && it.cuerpo.contains("\"p_visto\":true") && it.respuesta.trim() == "true" }
            }
            foto("03-visto")
            a.close()
        }
        // Se cierra y se vuelve a abrir: la guía viene del servidor y el video sigue visto.
        val antes = reales("entregas_app_get").size
        abrir()
        abrirGuia()
        p.esperar("el get de nuevo") { reales("entregas_app_get").size > antes }
        val id = reales("entregas_app_avance").last { it.cuerpo.contains("\"p_visto\":true") }.cuerpo.let { Regex("\"p_video\":\"([^\"]+)\"").find(it)!!.groupValues[1] }
        val vuelto = clips(guiaGuardada()).first { it.getString("id") == id }
        assertTrue("$id visto en el servidor", vuelto.optBoolean("visto"))
        irAFila(id, vuelto.optString("bloque", "Tu app").trim().ifEmpty { "Tu app" })
        p.esperar("la fila vista") { p.estado(etiqueta("clip-$id"))?.contains("visto") == true }
        foto("04-vuelta-visto")
    }

    @Test
    fun dudaDeVideoYDudaParaLaLlamada() {
        guardarCuenta(token)
        abrir()
        abrirGuia()
        p.esperar("el get") { reales("entregas_app_get").isNotEmpty() }
        val marca = System.currentTimeMillis() / 1000
        val dudaVideo = "Prueba nativa Android e2e $marca, video"
        if (p.existe(etiqueta("guia-lista"))) bajarHasta(etiqueta("duda-campo"), paso = 400f)
        p.escribir(etiqueta("duda-campo"), dudaVideo)
        p.tocar(etiqueta("duda-enviar"))
        p.esperar("la duda en el servidor", ms = 30_000, enElPrincipal = false) {
            reales("entregas_app_duda").firstOrNull { it.cuerpo.contains(dudaVideo) }
        }.also { assertEquals("true", it.respuesta.trim()) }
        p.nodo(texto("Listo, me llega antes de la videollamada."), ms = 30_000)
        foto("05-duda-video")

        val dudas = guiaGuardada().optJSONArray("dudas_llamada")?.length() ?: 0
        assumeTrue("la cuenta de prueba llegó al tope de 30 dudas para la llamada", dudas < 30)
        val dudaLlamada = "Prueba nativa Android e2e $marca, llamada"
        bajarHasta(etiqueta("llamada-campo"))
        p.escribir(etiqueta("llamada-campo"), dudaLlamada)
        p.tocar(etiqueta("llamada-enviar"))
        p.esperar("la duda general", ms = 30_000, enElPrincipal = false) {
            reales("entregas_app_llamada_duda").firstOrNull { it.cuerpo.contains(dudaLlamada) }
        }.also { assertEquals("true", it.respuesta.trim()) }
        p.nodo(textoQueContiene("Ya me dejaste estas ${dudas + 1}"), ms = 30_000)
        foto("06-duda-llamada")
    }

    @Test
    fun conLaGuiaRevocadaLaSeccionDesaparece() {
        guardarCuenta(token)
        abrir()
        p.nodo(etiqueta("tarjeta-guia"), ms = 30_000)
        guiaRevocada = true
        p.tocar(etiqueta("tarjeta-guia"))
        p.esperar("el get revocado", ms = 30_000, enElPrincipal = false) { reales("entregas_app_get").firstOrNull() }
            .also { assertTrue(it.respuesta, it.respuesta.replace(" ", "").contains("\"ok\":false")) }
        p.esperarQueNoEste(etiqueta("guia-pantalla"), ms = 30_000)
        p.esperarQueNoEste(etiqueta("tarjeta-guia"), ms = 30_000)
        p.nodo(etiqueta("entreno-lista"))
        // Sin la caché: al volver a abrir la app tampoco está (el resumen también da ok false).
        assertFalse(File(app.filesDir, "MyPump").walkTopDown().any { it.name == "guia.json" })
        foto("07-revocada-sin-tarjeta")
    }

    @Test
    fun sinRedSeVeLoGuardado() {
        guardarCuenta(token)
        abrir().also { a ->
            abrirGuia()
            p.esperar("el get") { reales("entregas_app_get").isNotEmpty() }
            a.close()
        }
        servidor.sinRed = true
        Telefono.shell("svc wifi disable")
        Telefono.shell("svc data disable")
        abrir()
        abrirGuia()
        p.nodo(etiqueta("guia-desde-cache"), ms = 30_000)
        val primero = clips(guiaGuardada()).firstOrNull { !it.optBoolean("visto") && !it.isNull("url") }
        if (primero != null) {
            irAFila(primero.getString("id"), primero.optString("bloque", "Tu app").trim().ifEmpty { "Tu app" })
            p.tocar(etiqueta("clip-${primero.getString("id")}"))
        }
        p.nodo(etiqueta("guia-sin-conexion-video"), ms = 30_000)
        foto("08-sin-red")
    }

    @Test
    fun letraGrande() {
        Telefono.shell("settings put system font_scale 1.3")
        guardarCuenta(token)
        abrir()
        p.nodo(etiqueta("tarjeta-guia"), ms = 30_000)
        foto("09-tarjeta-letra-grande")
        abrirGuia()
        p.nodo(etiqueta("guia-reproductor"), ms = 30_000)
        foto("10-guia-letra-grande")
        if (p.existe(etiqueta("guia-lista"))) {
            bajarHasta(etiqueta("guia-llamada"))
            foto("11-llamada-letra-grande")
        }
    }

    companion object {
        private var leido: String? = null

        /** El token que dejó el script: se lee una vez por corrida y se borra el archivo. */
        @Synchronized
        fun tokenDeLaCorrida(): String? {
            if (leido == null) {
                val f = File(androidx.test.platform.app.InstrumentationRegistry.getInstrumentation().targetContext.filesDir, "guia-e2e-token")
                leido = f.takeIf { it.exists() }?.readText()?.trim()
                f.delete()
            }
            return leido
        }
    }
}
