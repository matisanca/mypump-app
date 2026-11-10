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
        assertTrue(texto(etiqueta("horario-confirmar")).startsWith("Confirmar "))
        assertTrue(texto(etiqueta("horario-confirmar")).endsWith(", 10:00"))
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
        assertTrue(p.existe(etiqueta("videollamada-entrar-apagado")))
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
        assertTrue(texto(etiqueta("videollamada-cuenta")).startsWith("Se habilita "))
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
        assertTrue(texto(etiqueta("horario-confirmar")).startsWith("Cambiar al "))
        foto("and-cambiar-$m")
        p.tocar(etiqueta("horario-confirmar"))
        p.nodo(etiqueta("horario-listo"), ms = 30_000)
        assertEquals("Listo, la cambiamos", texto(etiqueta("horario-listo")))
        val pedido = JSONObject(d.a("entregas_app_cambiar").single())
        assertEquals("r1", pedido.getString("p_reserva"))
        assertEquals("00000000-0000-4000-8000-000000000004", pedido.getString("p_franja"))
        p.tocar(etiqueta("horario-listo-cerrar"))
        // Sin cambios restantes: ya no se ofrece cambiar, y se escribe por el chat.
        p.esperar("sin cambiar") { !p.existe(etiqueta("videollamada-cambiar")) }
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
        val (monitor, links) = monitorDeLinks()
        try {
            p.tocar(etiqueta("agenda-entrar"))
            assertEquals(DobleVideollamada.MEET, p.esperar("el link") { links.firstOrNull { it.action == Intent.ACTION_VIEW } }.dataString)
        } finally {
            InstrumentationRegistry.getInstrumentation().removeMonitor(monitor)
        }
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
