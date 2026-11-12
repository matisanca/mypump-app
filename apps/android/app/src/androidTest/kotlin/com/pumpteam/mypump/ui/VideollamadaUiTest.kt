package com.pumpteam.mypump.ui

import android.app.Instrumentation
import android.content.Intent
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.pumpteam.mypump.Entorno
import com.pumpteam.mypump.guia.Videollamada
import com.pumpteam.mypump.reglas.ReglasAgenda
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/**
 * La videollamada 2.3.0 con el [DobleVideollamada] (gemelo de VideollamadaUITests de iPhone): elegir el horario y la
 * confirmación (palanca prendida), la tarjeta fija días antes con «¿Cómo entro?» y el cambio con su tope, y «Entrar»
 * activo desde 10 minutos antes (sin la palanca: no cambia datos). Capturas `and-…` en claro, oscuro y con la letra al
 * doble; las baja el script a ~/Developer/nativa-evidencia/videollamada/capturas.
 */
@RunWith(AndroidJUnit4::class)
class VideollamadaUiTest : PruebaUi() {
    private fun fixture(n: String): String =
        InstrumentationRegistry.getInstrumentation().context.assets.open("guia/$n.json").use { it.readBytes().toString(Charsets.UTF_8) }

    /** La guía con todo visto (la agenda ya habilitada). */
    private fun guiaVista(): String = JSONObject(fixture("get-tomas-avanzado")).apply {
        val clips = getJSONArray("clips")
        for (i in 0 until clips.length()) clips.getJSONObject(i).put("visto", true)
    }.toString()

    private fun lanzar(escenario: String, palanca: Boolean = true): DobleVideollamada {
        servidor.respuestas["entregas_app_get"] = guiaVista()
        servidor.respuestas["entregas_app_avance"] = "true"
        val d = DobleVideollamada(escenario, servidor, palanca)
        Entorno.transporte = d
        guardarCuenta()
        abrir()
        return d
    }

    private fun modo(m: String) {
        Telefono.modoNoche(m == "oscuro")
        Telefono.shell("settings put system font_scale ${if (m == "grande") "2.0" else "1.0"}")
    }

    @After
    fun volver() {
        Telefono.shell("settings put system font_scale 1.0")
        Telefono.modoNoche(false)
        Videollamada.forzada = null
    }

    private fun texto(s: Selector): String = p.textosBajo(s).joinToString(" ")

    private fun foto(n: String) {
        p.quieto(600)
        Telefono.captura(n)
    }

    private fun monitorDeLinks(): Pair<Instrumentation.ActivityMonitor, MutableList<Intent>> {
        val vistos = java.util.Collections.synchronizedList(mutableListOf<Intent>())
        val monitor = object : Instrumentation.ActivityMonitor() {
            override fun onStartActivity(intent: Intent): Instrumentation.ActivityResult? {
                if (intent.action == Intent.ACTION_VIEW || intent.action == Intent.ACTION_INSERT) {
                    vistos += intent
                    return Instrumentation.ActivityResult(0, null)
                }
                return null
            }
        }
        InstrumentationRegistry.getInstrumentation().addMonitor(monitor)
        return monitor to vistos
    }

    private fun elegir(m: String) {
        modo(m)
        val d = lanzar("elegir")
        // Arriba de Entreno: «Agendá tu videollamada de comienzo».
        p.nodo(etiqueta("videollamada-agendar"), ms = 30_000)
        assertTrue(p.existe(texto("Agendá tu videollamada de comienzo")))
        assertTrue(p.existe(textoQueContiene("Elegí el día y el horario. Hay lugar desde el ")))
        foto("and-agendar-$m")
        p.tocar(etiqueta("videollamada-elegir"))
        p.nodo(etiqueta("horario-titulo"))
        assertEquals("Elegí el horario de tu videollamada de comienzo", texto(etiqueta("horario-titulo")))
        assertTrue(p.existe(texto("Dura alrededor de 1 hora y vas a entrar desde la app.")))
        assertTrue(p.existe(texto("Elegí un horario")))
        foto("and-elegir-$m")
        p.tocar(etiqueta("horario-franja-00000000-0000-4000-8000-000000000001"))
        p.esperar("confirmar") { texto(etiqueta("horario-confirmar")).startsWith("Confirmar ").takeIf { it } }
        // 10:00 de Argentina en el horario del teléfono (el emulador puede estar en otra zona).
        val local = java.time.LocalTime.of(10, 0).atDate(java.time.LocalDate.now(ReglasAgenda.ARGENTINA)).atZone(ReglasAgenda.ARGENTINA)
            .withZoneSameInstant(java.time.ZoneId.systemDefault()).toLocalTime()
        assertTrue(texto(etiqueta("horario-confirmar")).endsWith(", %02d:%02d".format(local.hour, local.minute)))
        foto("and-elegir-seleccion-$m")
        p.tocar(etiqueta("horario-confirmar"))
        p.nodo(etiqueta("horario-listo"), ms = 30_000)
        assertEquals("Listo, quedó agendada", texto(etiqueta("horario-listo")))
        assertTrue(p.existe(textoQueContiene("El botón se habilita 10 minutos antes.")))
        assertEquals("00000000-0000-4000-8000-000000000001", JSONObject(d.a("entregas_app_reservar").single()).getString("p_franja"))
        foto("and-confirmacion-$m")
        p.tocar(etiqueta("horario-listo-cerrar"))
        // La tarjeta fija, ya con el día y la hora.
        p.nodo(etiqueta("videollamada"), ms = 30_000)
        p.nodo(etiqueta("videollamada-entrar-apagado"), ms = 30_000)
        assertTrue(d.a("entregas_app_cambiar").isEmpty())
    }

    @Test fun elegirEnClaro() = elegir("claro")

    @Test fun elegirEnOscuro() = elegir("oscuro")

    @Test fun elegirConLetraGrande() = elegir("grande")

    private fun diasAntes(m: String, cambiar: Boolean) {
        modo(m)
        val d = lanzar("diasAntes")
        p.nodo(etiqueta("videollamada"), ms = 30_000)
        assertTrue(p.existe(texto("Tu videollamada de comienzo")))
        assertTrue(p.existe(texto(ReglasAgenda.TEXTO_DESDE_ACA)))
        assertTrue(p.existe(etiqueta("videollamada-entrar-apagado")))
        // La cuenta la lee TalkBack dentro del botón apagado (el texto suelto no se repite).
        assertTrue(p.existe(etiqueta("videollamada-cuenta")))
        assertTrue(p.descripcion(etiqueta("videollamada-entrar-apagado")).startsWith("Entrar, todavía no. Se habilita "))
        assertFalse(p.existe(etiqueta("agenda-entrar")))
        foto("and-tarjeta-dias-antes-$m")
        p.tocar(etiqueta("videollamada-como-entro"))
        p.nodo(etiqueta("videollamada-ayuda"))
        ReglasAgenda.AYUDA_ENTRAR.forEach { assertTrue(it, p.existe(texto(it))) }
        foto("and-tarjeta-dias-antes-ayuda-$m")
        if (!cambiar) return
        p.tocar(etiqueta("videollamada-cambiar"))
        p.nodo(etiqueta("horario-ahora-es"))
        assertTrue(texto(etiqueta("horario-ahora-es")).contains("Podés cambiarlo 1 vez, hasta el "))
        p.tocar(etiqueta("horario-franja-00000000-0000-4000-8000-000000000004"))
        p.esperar("cambiar al") { texto(etiqueta("horario-confirmar")).startsWith("Cambiar al ").takeIf { it } }
        foto("and-cambiar-$m")
        p.tocar(etiqueta("horario-confirmar"))
        p.nodo(etiqueta("horario-listo"), ms = 30_000)
        assertEquals("Listo, la cambiamos", texto(etiqueta("horario-listo")))
        val pedido = JSONObject(d.a("entregas_app_cambiar").single())
        assertEquals("r1", pedido.getString("p_reserva"))
        assertEquals("00000000-0000-4000-8000-000000000004", pedido.getString("p_franja"))
        p.tocar(etiqueta("horario-listo-cerrar"))
        // Sin cambios restantes: ya no se ofrece cambiar, y se escribe por el chat.
        p.esperar("sin cambiar") { (!p.existe(etiqueta("videollamada-cambiar"))).takeIf { it } }
        assertTrue(p.existe(texto("¿Necesitás cambiarla? Escribinos por el chat.")))
    }

    @Test fun diasAntesYCambiarEnClaro() = diasAntes("claro", cambiar = true)

    @Test fun diasAntesEnOscuro() = diasAntes("oscuro", cambiar = false)

    @Test fun diasAntesConLetraGrande() = diasAntes("grande", cambiar = false)

    private fun porEntrar(m: String) {
        modo(m)
        // Sin la palanca: la tarjeta fija y «Entrar» van igual (no cambian datos).
        lanzar("porEntrar", palanca = false)
        p.nodo(etiqueta("agenda-entrar"), ms = 30_000)
        assertEquals("Ya podés entrar", texto(etiqueta("agenda-sala")))
        assertTrue(p.existe(texto(ReglasAgenda.TEXTO_ADMITE)))
        assertTrue(p.existe(texto("Hoy")) || m == "grande")
        foto("and-entrar-$m")
        // 2.3.1: el código de la reunión, siempre a la vista debajo de «Entrar», con «Copiar código» y dónde pegarlo.
        assertTrue(p.existe(etiqueta("videollamada-codigo")))
        assertTrue(p.existe(texto(ReglasAgenda.TITULO_PASOS_CODIGO)))
        ReglasAgenda.PASOS_CODIGO.forEach { assertTrue(it, p.existe(texto(it))) }
        p.tocar(etiqueta("videollamada-copiar-codigo"))
        p.esperar("copiado") { p.existe(texto(ReglasAgenda.TEXTO_CODIGO_COPIADO)).takeIf { it } }
        var copiado: String? = null
        InstrumentationRegistry.getInstrumentation().runOnMainSync {
            val cm = InstrumentationRegistry.getInstrumentation().targetContext.getSystemService(android.content.ClipboardManager::class.java)
            copiado = cm?.primaryClip?.getItemAt(0)?.text?.toString()
        }
        // Android 10+ solo deja leer el portapapeles a la app con foco; con el aviso de «copiado» del sistema (13+) a veces
        // no lo tiene y da null. Si se pudo leer, tiene que ser el código.
        copiado?.let { assertEquals("abc-defg-hij", it) }
        foto("and-codigo-copiado-$m")
        val (monitor, links) = monitorDeLinks()
        try {
            p.tocar(etiqueta("agenda-entrar"))
            val ver = p.esperar("el link") { links.firstOrNull { it.action == Intent.ACTION_VIEW } }
            assertEquals(DobleVideollamada.MEET, ver.dataString)
            // Nunca un VIEW suelto que pueda tomar Gmail: la app de Meet fija o una Custom Tab con su navegador fijo.
            assertTrue("va a ${ver.`package`}", ver.`package` == "com.google.android.apps.tachyon" ||
                (ver.`package` != null && ver.`package` != "com.google.android.gm" && ver.hasExtra("android.support.customtabs.extra.SESSION")))
        } finally {
            InstrumentationRegistry.getInstrumentation().removeMonitor(monitor)
        }
    }

    /**
     * Solo a mano, con `-e meetUrl <sala de prueba>`: «Entrar» de verdad, sin interceptar el link. Lo que queda adelante
     * tiene que ser la app de Meet o el navegador con la reunión, nunca Gmail. Sin el argumento, se saltea.
     */
    @Test fun entrarDeVerdad() {
        val url = InstrumentationRegistry.getArguments().getString("meetUrl")
        org.junit.Assume.assumeTrue(url != null)
        modo("claro")
        lanzar("porEntrar", palanca = false)
        p.nodo(etiqueta("agenda-entrar"), ms = 30_000)
        foto("and-real-tarjeta")
        p.tocar(etiqueta("agenda-entrar"))
        // Destinos válidos: la app de Meet, la Custom Tab o, sin Meet instalada, Google Play (la web de Meet manda ahí). Nunca Gmail.
        val validos = listOf("com.google.android.apps.tachyon", "chrome", "com.android.vending")
        var arriba = ""
        val hasta = System.currentTimeMillis() + 15_000
        while (System.currentTimeMillis() < hasta) {
            arriba = Telefono.shell("dumpsys activity activities").lineSequence().firstOrNull { "topResumedActivity" in it }.orEmpty()
            if ("com.google.android.gm" in arriba) break
            if (validos.any { it in arriba }) { Thread.sleep(2_000); break }
            Thread.sleep(500)
        }
        Telefono.captura("and-real-reunion")
        arriba = Telefono.shell("dumpsys activity activities").lineSequence().firstOrNull { "topResumedActivity" in it }.orEmpty()
        assertFalse(arriba, "com.google.android.gm" in arriba)
        assertTrue(arriba, validos.any { it in arriba })
    }

    @Test fun porEntrarEnClaro() = porEntrar("claro")

    @Test fun porEntrarEnOscuro() = porEntrar("oscuro")

    @Test fun porEntrarConLetraGrande() = porEntrar("grande")

    /** Con la palanca apagada no aparece «Agendá tu videollamada» ni se llama a nada nuevo. */
    @Test
    fun sinLaPalancaNoSeOfreceElegir() {
        val d = lanzar("elegir", palanca = false)
        p.nodo(etiqueta("tarjeta-guia"), ms = 30_000)
        p.quieto(1500)
        assertFalse(p.existe(etiqueta("videollamada-agendar")))
        assertFalse(p.existe(etiqueta("videollamada")))
        assertTrue(d.a("entregas_app_cambiar").isEmpty())
    }
}
