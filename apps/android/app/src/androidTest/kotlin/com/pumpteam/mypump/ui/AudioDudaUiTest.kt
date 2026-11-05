package com.pumpteam.mypump.ui

import android.Manifest
import android.content.Context
import android.os.Build
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.pumpteam.mypump.guia.AudioDudaEntorno
import com.pumpteam.mypump.guia.GrabadorAudio
import java.io.File
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Las dudas en audio de «Tu guía» (2.1.0) con el [ServidorDePrueba]: el contrato de `entregas_019` simulado (iniciar, la
 * subida a Storage, subido y la lista), sin red de verdad. El micrófono es un doble ([AudioDudaEntorno]) salvo en
 * [conElMicrofonoDelEmulador]. Las capturas (`audio-<teléfono>-<estado>-<tema>`) las baja `scripts/nativa/guia-android.sh`.
 */
@RunWith(AndroidJUnit4::class)
class AudioDudaUiTest : PruebaUi() {
    private fun fixture(n: String): String =
        InstrumentationRegistry.getInstrumentation().context.assets.open("guia/$n.json").use { it.readBytes().toString(Charsets.UTF_8) }

    /** Lo que graba el doble: unos bytes en el archivo, sin micrófono. */
    private class GrabadorDePrueba : GrabadorAudio {
        private var f: File? = null
        override fun empezar(archivo: File, alCortarse: () -> Unit) {
            archivo.parentFile?.mkdirs()
            archivo.writeBytes(ByteArray(24_000) { (it % 251).toByte() })
            f = archivo
        }
        override fun detener(): Boolean = f?.isFile == true
        override fun soltar() {}
    }

    private val ticket = """{"ok": true, "id": "x", "bucket": "entregas-audio", "ruta": "cliente-x/a.m4a", "mime": "audio/mp4", "max_bytes": 6291456, "estado": "pendiente"}"""
    private val texto = "Quería saber si puedo entrenar en ayunas"

    /** La guía con la duda transcripta ya sumada a las de la videollamada (como queda en el servidor). */
    private fun getConTranscripta(): String = org.json.JSONObject(fixture("get-tomas-avanzado")).apply {
        val l = optJSONArray("dudas_llamada") ?: org.json.JSONArray().also { put("dudas_llamada", it) }
        l.put(org.json.JSONObject().put("texto", texto).put("en", "2026-11-04T10:00:00Z"))
    }.toString()

    private fun conGuia(audios: String = "[]", get: String = fixture("get-tomas-avanzado")) {
        servidor.respuestas["entregas_app_resumen"] = """{"ok": true, "total": 20, "vistos": 4, "minutos_restantes": 11.6}"""
        servidor.respuestas["entregas_app_get"] = get
        servidor.respuestas["entregas_app_avance"] = "true"
        servidor.respuestas["entregas_app_duda"] = "true"
        servidor.respuestas["entregas_app_llamada_duda"] = "true"
        servidor.respuestas["entregas_app_audios"] = audios
        servidor.respuestas["entregas_app_audio_iniciar"] = ticket
        servidor.respuestas["entregas_app_audio_subido"] = """{"ok": true, "estado": "subido"}"""
    }

    private val telefono: String by lazy {
        val dm = app.resources.displayMetrics
        if (dm.widthPixels / dm.density < 380) "chico" else "grande"
    }

    private fun foto(n: String, sufijo: String = "claro") = Telefono.captura("$telefono-$n-$sufijo")

    /** Sin esperar a que el hilo quede quieto (el punto que late no termina nunca). */
    private fun fotoYa(n: String, sufijo: String = "claro") {
        Thread.sleep(500)
        Telefono.shell("mkdir -p ${Telefono.CARPETA_CAPTURAS}")
        Telefono.shell("screencap -p ${Telefono.CARPETA_CAPTURAS}/$telefono-$n-$sufijo.png")
    }

    @Before
    fun conDoble() {
        AudioDudaEntorno.grabador = { _: Context -> GrabadorDePrueba() }
        AudioDudaEntorno.permiso = true
    }

    @After
    fun sinDoble() {
        AudioDudaEntorno.grabador = null
        AudioDudaEntorno.permiso = null
        Telefono.shell("settings put system font_scale 1.0")
    }

    private fun abrirGuiaHastaElAudio() {
        guardarCuenta()
        abrir()
        p.tocar(etiqueta("tarjeta-guia"))
        p.nodo(etiqueta("guia-cabecera"), ms = 60_000)
        alAudio()
    }

    /** Baja la lista hasta dejar el recuadro del audio a la vista. */
    private fun alAudio(s: Selector = etiqueta("audio-duda")) {
        repeat(30) {
            if (p.existe(s)) {
                val alto = p.enPrincipal { p.nodo(s).boundsInRoot }
                if (alto.height > 0f) {
                    p.desplazar(etiqueta("guia-lista"), alto.top - 350f)
                    p.quieto(300)
                    return
                }
            }
            p.desplazar(etiqueta("guia-lista"), 500f)
        }
        p.nodo(s)
    }

    private fun grabarYTerminar(segundos: Long = 2_300) {
        p.tocar(etiqueta("audio-grabar"))
        p.nodo(etiqueta("audio-terminar"))
        Thread.sleep(segundos)
        p.tocar(etiqueta("audio-terminar"))
        p.nodo(etiqueta("audio-revisar"))
    }

    @Test
    fun grabarRevisarMandarYLoQueEntendi() = recorrido("claro")

    @Test
    fun enOscuro() = recorrido("oscuro")

    private fun recorrido(sufijo: String) {
        Telefono.modoNoche(sufijo == "oscuro")
        conGuia()
        abrirGuiaHastaElAudio()
        p.nodo(texto("Grabar un audio"))
        p.nodo(texto("¿Te es más fácil hablarlo? Mandame un audio, como por WhatsApp. Hasta 5 minutos cada uno."))
        foto("reposo", sufijo)

        p.tocar(etiqueta("audio-grabar"))
        p.nodo(etiqueta("audio-terminar"))
        assertEquals("Grabando", p.estado(etiqueta("audio-terminar")))
        Thread.sleep(2_500)
        fotoYa("grabando", sufijo)
        p.tocar(etiqueta("audio-terminar"))
        p.nodo(etiqueta("audio-revisar"))
        p.nodo(texto("Mandar"))
        p.nodo(texto("Grabar de nuevo"))
        p.nodo(texto("Borrar"))
        // La duración se anuncia al terminar.
        p.nodo(textoQueContiene("Grabaste 0:0"))
        foto("revisar", sufijo)

        // Mandar con el servidor lento: «Mandando tu audio…» y el botón de grabar apagado.
        servidor.demoraMs = 2_500
        p.tocar(etiqueta("audio-mandar"))
        p.nodo(etiqueta("audio-item-mandando"))
        p.nodo(texto("Mandando tu audio…"))
        assertFalse(p.habilitado(etiqueta("audio-grabar")))
        fotoYa("mandando", sufijo)
        p.esperar("subido", ms = 20_000) { servidor.a("entregas_app_audio_subido").isNotEmpty() }
        p.nodo(etiqueta("audio-item-subido"), ms = 15_000)
        p.nodo(texto("Listo, me llegó tu audio, lo escucho antes de la videollamada."))
        servidor.demoraMs = 0
        foto("subido", sufijo)

        // Lo que mandó a Storage: el tipo exacto, sin pisar.
        val ini = org.json.JSONObject(servidor.a("entregas_app_audio_iniciar").single())
        assertEquals("audio/mp4", ini.getString("p_mime"))
        assertEquals(24_000, ini.getInt("p_bytes"))
        assertTrue(ini.getString("p_id").length == 36)

        // Transcripto se ve igual que subido (el cliente no se entera de que se pasa a texto) y la transcripción, que entra
        // como una duda más de la videollamada, no se muestra.
        servidor.respuestas["entregas_app_audios"] = """[{"id": "${ini.getString("p_id")}", "estado": "transcripto", "en": "2026-11-04T10:00:00Z", "segundos": 2, "texto": "$texto"}]"""
        servidor.respuestas["entregas_app_get"] = getConTranscripta()
        p.atras()
        p.tocar(etiqueta("tarjeta-guia"))
        p.nodo(etiqueta("guia-cabecera"), ms = 60_000)
        alAudio(etiqueta("audio-item-subido"))
        p.nodo(texto("Listo, me llegó tu audio, lo escucho antes de la videollamada."))
        assertEquals(0, p.cuantos(texto(texto)))
        assertFalse(p.existe(textoQueContiene("entendí")))
        foto("transcripto", sufijo)
    }

    @Test
    fun permisoNegado() {
        AudioDudaEntorno.permiso = false
        conGuia()
        abrirGuiaHastaElAudio()
        p.nodo(textoQueContiene("Te va a pedir permiso para usar el micrófono"))
        p.tocar(etiqueta("audio-grabar"))
        p.nodo(textoQueContiene("Tu celu no me dio permiso para el micrófono"))
        p.nodo(etiqueta("audio-ajustes"))
        p.nodo(texto("Abrir ajustes"))
        foto("permiso-negado")
        assertFalse(p.existe(etiqueta("audio-terminar")))
    }

    @Test
    fun menosDeDosSegundosNoSeManda() {
        conGuia()
        abrirGuiaHastaElAudio()
        p.tocar(etiqueta("audio-grabar"))
        p.tocar(etiqueta("audio-terminar"))
        p.nodo(texto("No se escuchó nada, probá de nuevo."))
        assertFalse(p.existe(etiqueta("audio-revisar")))
        p.nodo(etiqueta("audio-grabar"))
    }

    @Test
    fun borrarYGrabarDeNuevo() {
        conGuia()
        abrirGuiaHastaElAudio()
        grabarYTerminar()
        p.tocar(etiqueta("audio-de-nuevo"))
        p.nodo(etiqueta("audio-terminar"))
        Thread.sleep(2_300)
        p.tocar(etiqueta("audio-terminar"))
        p.tocar(etiqueta("audio-borrar"))
        p.esperarQueNoEste(etiqueta("audio-revisar"))
        p.nodo(etiqueta("audio-grabar"))
        assertTrue(servidor.a("entregas_app_audio_iniciar").isEmpty())
    }

    @Test
    fun sinRedNoSeMandaYReintentar() {
        conGuia()
        abrirGuiaHastaElAudio()
        grabarYTerminar()
        servidor.sinRed = true
        p.tocar(etiqueta("audio-mandar"))
        p.nodo(etiqueta("audio-item-no_se_mando"), ms = 15_000)
        p.nodo(texto("No se pudo mandar."))
        foto("sin-red")
        servidor.sinRed = false
        p.tocar(etiqueta("audio-reintentar"))
        p.nodo(etiqueta("audio-item-subido"), ms = 20_000)
        // El mismo p_id en todos los intentos que llegaron al servidor.
        val ids = servidor.a("entregas_app_audio_iniciar").map { org.json.JSONObject(it).getString("p_id") }.toSet()
        assertEquals(1, ids.size)
    }

    @Test
    fun elTopeAvisa() {
        conGuia()
        servidor.respuestas["entregas_app_audio_iniciar"] = """{"ok": false, "motivo": "tope"}"""
        abrirGuiaHastaElAudio()
        grabarYTerminar()
        p.tocar(etiqueta("audio-mandar"))
        p.nodo(textoQueContiene("Ya me mandaste 10 audios"), ms = 15_000)
        assertFalse(p.existe(etiqueta("audio-reintentar")))
    }

    @Test
    fun sinLaFuncionNoHayBoton() {
        conGuia(audios = ServidorDePrueba.SIN_FUNCION)
        guardarCuenta()
        abrir()
        p.tocar(etiqueta("tarjeta-guia"))
        p.nodo(etiqueta("guia-cabecera"), ms = 60_000)
        p.esperar("la lista de audios") { servidor.a("entregas_app_audios").isNotEmpty() }
        repeat(12) { p.desplazar(etiqueta("guia-lista"), 500f) }
        p.nodo(etiqueta("guia-fin"))
        assertFalse(p.existe(etiqueta("audio-duda")))
        assertFalse(p.existe(etiqueta("audio-grabar")))
    }

    @Test
    fun conLetraGrande() {
        Telefono.shell("settings put system font_scale 1.3")
        conGuia()
        abrirGuiaHastaElAudio()
        foto("reposo", "letra-grande")
        grabarYTerminar()
        foto("revisar", "letra-grande")
    }

    @Test
    fun enLaDemoNoSeManda() {
        abrir()
        p.tocar(etiqueta("ver-demo"))
        p.nodo(texto("Estás viendo la demo"))
        p.tocar(etiqueta("tarjeta-guia"))
        p.nodo(etiqueta("guia-cabecera"), ms = 60_000)
        alAudio()
        grabarYTerminar()
        p.tocar(etiqueta("audio-mandar"))
        p.nodo(texto("Vista previa: el audio no se manda."))
        p.nodo(etiqueta("audio-revisar"))
        foto("demo-vista-previa")
        assertTrue(servidor.llamadas.none { it.funcion.startsWith("entregas_app_audio") })
    }

    /** El MediaRecorder de verdad con el micrófono del emulador (en silencio sin `-allow-host-audio`): graba y se escucha. */
    @Test
    fun conElMicrofonoDelEmulador() {
        AudioDudaEntorno.grabador = null
        AudioDudaEntorno.permiso = null
        instr.uiAutomation.grantRuntimePermission(app.packageName, Manifest.permission.RECORD_AUDIO)
        conGuia()
        abrirGuiaHastaElAudio()
        assertFalse(p.existe(etiqueta("audio-antes-permiso")))
        grabarYTerminar(3_200)
        assertFalse(p.existe(textoQueContiene("No se escuchó nada")))
        p.tocar(etiqueta("audio-escuchar"))
        p.nodo(texto("Pausar"))
        p.tocar(etiqueta("audio-mandar"))
        p.nodo(etiqueta("audio-item-subido"), ms = 20_000)
        val ini = org.json.JSONObject(servidor.a("entregas_app_audio_iniciar").single())
        // 3 s de AAC a 64 kbps: unos 25 KB (y un m4a de verdad, no vacío).
        assertTrue("bytes ${ini.getInt("p_bytes")}", ini.getInt("p_bytes") in 5_000..80_000)
        assertTrue(ini.getInt("p_segundos") in 2..4)
        // API ${Build.VERSION.SDK_INT}: en la 28 va el constructor viejo de MediaRecorder.
    }
}
