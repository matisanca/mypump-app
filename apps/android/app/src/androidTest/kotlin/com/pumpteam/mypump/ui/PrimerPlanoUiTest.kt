package com.pumpteam.mypump.ui

import android.os.SystemClock
import androidx.lifecycle.Lifecycle
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.pumpteam.mypump.Entorno
import com.pumpteam.mypump.datos.Disco
import com.pumpteam.mypump.datos.FotoPendiente
import com.pumpteam.mypump.datos.ModeloApp
import com.pumpteam.mypump.modelos.ValorJson
import com.pumpteam.mypump.reglas.FechaLocal
import com.pumpteam.mypump.reglas.FotosProgreso
import java.time.Instant
import java.util.TimeZone
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

/**
 * GEN-07, el recorrido entero de volver a primer plano: `MainActivity` (ON_START) → `ModeloAppViewModel.primerPlano` →
 * `ModeloApp.alVolverAPrimerPlano`. Al volver salen la cola de escrituras y la de fotos, se mira el chat y, si cambió el
 * día, se recarga lo de hoy: las comidas libres, Mi Día y el check de la semana. La app pasa a segundo plano y vuelve con
 * `ActivityScenario.moveToState`, que pasa por ON_STOP y ON_START como el botón de inicio y volver desde Recientes.
 *
 * Con el [ChatDePrueba] encima del [ServidorDePrueba]: nada sale a la red.
 */
@RunWith(AndroidJUnit4::class)
class PrimerPlanoUiTest : PruebaUi() {
    private lateinit var chat: ChatDePrueba
    private var zonaAntes: TimeZone? = null

    @Before
    fun conElChatDePrueba() {
        chat = ChatDePrueba(servidor)
        Entorno.transporte = chat
    }

    @After
    fun devolverLaZona() {
        zonaAntes?.let(TimeZone::setDefault)
        zonaAntes = null
    }

    /** Los pesos que intentaron salir (el peso va por `ingest_salud`, con el tipo `peso_kg`). */
    private fun pesos(): List<String> = servidor.a("mypump_ingest_salud").filter { "peso_kg" in it }

    /** Lo que espera en la cola de escrituras (fuera del hilo principal: la cola es un actor). */
    private fun enLaCola(m: ModeloApp): Int = runBlocking { m.outbox?.pendientes() ?: -1 }

    /** Hasta que el servidor de prueba deja de recibir pedidos un rato (la carga terminó entera). */
    private fun servidorQuieto() {
        var antes = -1
        p.esperar("el servidor quieto", ms = 30_000, enElPrincipal = false) {
            val ahora = servidor.llamadas.size
            if (ahora == antes) {
                true
            } else {
                antes = ahora
                Thread.sleep(1_200)
                null
            }
        }
    }

    /**
     * Al volver salen las dos colas y se mira el chat, enseguida. La cola de escrituras se reintenta sola, pero sin red
     * espera cada vez más entre un intento y otro (hasta 30 s): se la hace fallar unas cuantas veces antes, así lo que sale
     * apenas vuelve la app es por volver y no por su temporizador. La de fotos no se reintenta sola.
     */
    @Test
    fun alVolverSalenLasColasYSeMiraElChat() {
        // Una foto de hoy esperando en su cola, con el servicio de fotos sin red, y el chat con un mensaje ya leído.
        val hoy = FechaLocal.hoy()
        val foto = FotoPendiente("frente", hoy, "data:image/jpeg;base64,AAAA")
        Disco(app.filesDir, ServidorDePrueba.TOKEN).guardar(FotoPendiente.ARCHIVO, ValorJson.Objeto(mapOf("${FotosProgreso.lunes(hoy)}|frente" to foto.aValor())))
        servidor.fotosSinRed = true
        chat.agregar("coach", "Hola, ¿cómo venís?", Instant.now().minusSeconds(3_600), leido = true)
        guardarCuenta()
        val e = abrir()
        val (_, m) = p.modeloCargado(e)
        p.esperar("al abrir se intentó subir la foto") { servidor.a("upload").isNotEmpty() }
        servidorQuieto()
        assertTrue(servidor.fotosSubidas.isEmpty())

        // Sin red, el peso de hoy queda en la cola…
        p.tocar(etiqueta("pestana-revision"))
        p.nodo(etiqueta("guardar-peso"))
        servidor.sinRed = true
        p.escribir(etiqueta("peso-hoy"), "80")
        p.tocar(etiqueta("guardar-peso"))
        p.esperar("el peso quedó en la cola", enElPrincipal = false) { enLaCola(m) == 1 && pesos().isNotEmpty() }
        // … y falla varias veces: el próximo reintento solo queda a 30 s.
        runBlocking { repeat(15) { m.outbox!!.drenar() } }
        var intentos = -1
        p.esperar("la cola sin reintentar por un rato", ms = 30_000, enElPrincipal = false) {
            val ahora = pesos().size
            if (ahora == intentos) {
                true
            } else {
                intentos = ahora
                Thread.sleep(5_000)
                null
            }
        }
        assertEquals(1, enLaCola(m))

        // A segundo plano. Mientras tanto vuelve la red y Mati escribe.
        e.moveToState(Lifecycle.State.CREATED)
        servidor.sinRed = false
        servidor.fotosSinRed = false
        chat.agregar("coach", "¿Pudiste entrenar?")
        val nuevos = servidor.a("mypump_chat_nuevos").size
        val deHoy = DE_HOY.map { servidor.a(it).size }
        Thread.sleep(1_500)
        assertEquals("en segundo plano la cola no tiene que haber salido", intentos, pesos().size)
        assertTrue("en segundo plano la foto no tiene que haber subido", servidor.fotosSubidas.isEmpty())
        assertEquals("en segundo plano no se mira el chat", nuevos, servidor.a("mypump_chat_nuevos").size)

        // Vuelve: sale todo y se mira el chat, enseguida (la cola por su cuenta recién reintentaría en ~30 s).
        e.moveToState(Lifecycle.State.RESUMED)
        val fin = SystemClock.uptimeMillis() + 8_000
        var salioLaCola = false
        var subioLaFoto = false
        var seMiroElChat = false
        while (SystemClock.uptimeMillis() < fin && !(salioLaCola && subioLaFoto && seMiroElChat)) {
            salioLaCola = enLaCola(m) == 0
            subioLaFoto = servidor.fotosSubidas.isNotEmpty()
            seMiroElChat = servidor.a("mypump_chat_nuevos").size > nuevos
            Thread.sleep(100)
        }
        assertEquals(
            "al volver: salió la cola, subió la foto y se miró el chat",
            listOf("cola" to true, "foto" to true, "chat" to true),
            listOf("cola" to salioLaCola, "foto" to subioLaFoto, "chat" to seMiroElChat),
        )
        assertTrue(pesos().last().contains("\"fuente\":\"manual\""))
        assertEquals("frente", servidor.fotosSubidas.single().pose)
        // Lo que llegó de Mati se ve en el badge del Chat.
        p.esperar("el mensaje nuevo en el badge del Chat") { "1" in p.textosBajo(etiqueta("pestana-chat")) }
        // El mismo día no se recarga lo de hoy.
        p.quieto(1_000)
        assertEquals("con el mismo día no se recarga lo de hoy", deHoy, DE_HOY.map { servidor.a(it).size })
    }

    /** Con otro día al volver se recarga lo de hoy, con la fecha nueva; volver otra vez el mismo día no lo pide de nuevo. */
    @Test
    fun alVolverConOtroDiaSeRecargaLoDeHoy() {
        // El «hoy» local es el del teléfono: de UTC−12 a UTC+14 siempre es otro día (26 h de diferencia).
        zonaAntes = TimeZone.getDefault()
        TimeZone.setDefault(TimeZone.getTimeZone("Etc/GMT+12"))
        val diaViejo = FechaLocal.hoy()
        guardarCuenta()
        val e = abrir()
        p.modeloCargado(e)
        // Que termine la carga entera: ahí se anota el día cargado.
        p.esperar("la carga terminó") { servidor.a("mypump_get_fotos_progreso").isNotEmpty() }
        servidorQuieto()
        for (f in DE_HOY) assertTrue("$f con el día de la carga", servidor.a(f).isNotEmpty() && servidor.a(f).all { "\"p_fecha\":\"$diaViejo\"" in it })

        TimeZone.setDefault(TimeZone.getTimeZone("Etc/GMT-14"))
        val diaNuevo = FechaLocal.hoy()
        assertNotEquals(diaViejo, diaNuevo)
        e.moveToState(Lifecycle.State.CREATED)
        e.moveToState(Lifecycle.State.RESUMED)
        for (f in DE_HOY) p.esperar("$f con el día nuevo", ms = 8_000) { servidor.a(f).any { "\"p_fecha\":\"$diaNuevo\"" in it } }

        // Otra vuelta el mismo día: se mira el chat (volvió de verdad) y lo de hoy no se pide de nuevo.
        servidorQuieto()
        val antes = DE_HOY.map { servidor.a(it).size }
        val chats = servidor.a("mypump_chat_nuevos").size + servidor.a("mypump_get_chat").size
        e.moveToState(Lifecycle.State.CREATED)
        e.moveToState(Lifecycle.State.RESUMED)
        p.esperar("se miró el chat al volver", ms = 8_000) { servidor.a("mypump_chat_nuevos").size + servidor.a("mypump_get_chat").size > chats }
        p.quieto(1_500)
        assertEquals(antes, DE_HOY.map { servidor.a(it).size })
    }

    private companion object {
        /** Lo "de hoy" que se recarga si cambió el día, con su `p_fecha`. */
        val DE_HOY = listOf("mypump_get_comidas_libres", "mypump_get_habitos_dia", "mypump_get_checkin_semana")
    }
}
