package com.pumpteam.mypump.ui

import android.app.Instrumentation
import android.content.Intent
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.pumpteam.mypump.reglas.SeguimientoAvance
import java.time.Instant
import java.time.temporal.ChronoUnit
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/**
 * La novedad de «Tu guía», los videos obligatorios y la agenda de la entrega (2.2.0, spec §5) con el [ServidorDePrueba]:
 * bloqueada → ver el último → habilitada → reservar → pendiente → confirmada → Entrar; el fallo `tomada`; sin red; sin
 * autorizar; sin el servidor nuevo (nada cambia). Las capturas quedan con el prefijo `agenda-` en claro, oscuro y con la
 * letra grande; las baja `scripts/nativa/guia-android.sh` (carpeta `agenda` → ~/Developer/nativa-evidencia/agenda).
 */
@RunWith(AndroidJUnit4::class)
class AgendaUiTest : PruebaUi() {
    private fun fixture(n: String): String =
        InstrumentationRegistry.getInstrumentation().context.assets.open("guia/$n.json").use { it.readBytes().toString(Charsets.UTF_8) }

    private val novedadEn = "2026-11-05T12:00:00-03:00"

    /**
     * La guía avanzada como fase 2: dos nuevos sin ver (abajo en el servidor, arriba en la app) y tres obligatorios, dos
     * vistos y FT-9b sin ver.
     */
    private fun guiaV2(ultimoVisto: Boolean = false): String = JSONObject(fixture("get-tomas-avanzado")).apply {
        put("fase", 2)
        put("novedad_en", novedadEn)
        val clips = getJSONArray("clips")
        for (i in 0 until clips.length()) clips.getJSONObject(i).let { c ->
            val id = c.getString("id")
            c.put("nuevo", id == "MC-13_clip3" || id == "FT-5a")
            c.put("obligatorio", id == "FT-25a" || id == "FT-2b" || id == "FT-9b")
            if (id == "FT-9b" && ultimoVisto) c.put("visto", true)
        }
    }.toString()

    private val resumen = """{"ok": true, "total": 17, "vistos": 4, "minutos_restantes": 9.0, "novedad_en": "$novedadEn"}"""

    /** Franjas siempre en el futuro: mañana y pasado, 10 y 14 de Argentina. */
    private fun franjas(): String {
        val manana = Instant.now().atZone(java.time.ZoneId.of("America/Argentina/Buenos_Aires")).toLocalDate().plusDays(1)
        fun f(n: Int, dia: Long, hora: Int): String {
            val i = manana.plusDays(dia).atTime(hora, 0).atZone(java.time.ZoneId.of("America/Argentina/Buenos_Aires")).toOffsetDateTime()
            return """{"id": "0000000$n-0000-4000-8000-000000000000", "inicio": "$i", "fin": "${i.plusHours(2)}"}"""
        }
        return "[${f(1, 0, 10)}, ${f(2, 0, 14)}, ${f(3, 1, 10)}]"
    }

    private fun reserva(estado: String, meet: String? = null): String {
        val i = Instant.now().plus(2, ChronoUnit.DAYS).truncatedTo(ChronoUnit.HOURS)
        return """{"id": "r1", "inicio": "$i", "fin": "${i.plus(2, ChronoUnit.HOURS)}", "estado": "$estado", "meet_url": ${meet?.let { "\"$it\"" } ?: "null"}, "motivo": null}"""
    }

    private val bloqueada = """{"ok": true, "habilitada": false, "autorizada": true, "faltan": 1, "franjas": [], "reserva": null}"""
    private fun habilitada() = """{"ok": true, "habilitada": true, "autorizada": true, "faltan": 0, "franjas": ${franjas()}, "reserva": null}"""
    private val noAutorizada = """{"ok": true, "habilitada": false, "autorizada": false, "faltan": 1, "franjas": [], "reserva": null}"""
    private val meet = "https://meet.google.com/abc-defg-hij"

    private fun conGuia(get: String = guiaV2(), res: String = resumen, agenda: String? = bloqueada) {
        servidor.respuestas["entregas_app_resumen"] = res
        servidor.respuestas["entregas_app_get"] = get
        servidor.respuestas["entregas_app_avance"] = "true"
        servidor.respuestas["entregas_app_duda"] = "true"
        servidor.respuestas["entregas_app_llamada_duda"] = "true"
        if (agenda != null) servidor.respuestas["entregas_app_agenda"] = agenda else servidor.respuestas["entregas_app_agenda"] = ServidorDePrueba.SIN_FUNCION
    }

    @After
    fun letraNormal() {
        Telefono.shell("settings put system font_scale 1.0")
        Telefono.modoNoche(false)
    }

    private fun abrirGuia() {
        p.tocar(etiqueta("tarjeta-guia"))
        p.nodo(etiqueta("guia-cabecera"))
    }

    private fun bajarHasta(s: Selector, paso: Float = 600f, veces: Int = 30) {
        repeat(veces) {
            if (p.existe(s)) return
            p.desplazar(etiqueta("guia-lista"), paso)
        }
        p.nodo(s)
    }

    /** Deja [s] cerca de [arriba] px del borde de arriba (para la captura), de a pasos cortos. */
    private fun mostrar(s: Selector, arriba: Float = 400f) {
        bajarHasta(s)
        repeat(20) {
            val n = p.nodo(s)
            val b = p.enPrincipal { n.boundsInRoot }
            val dy = if (b.height <= 0f) 400f else b.top - arriba
            if (kotlin.math.abs(dy) < 40f) return
            p.desplazar(etiqueta("guia-lista"), dy.coerceIn(-600f, 600f))
            p.quieto(250)
        }
    }

    private fun marcarVisto(e: androidx.test.core.app.ActivityScenario<*>, video: String) {
        @Suppress("UNCHECKED_CAST")
        val (vm, m) = p.modeloCargado(e as androidx.test.core.app.ActivityScenario<com.pumpteam.mypump.MainActivity>)
        // Lo mismo que hace el reproductor al pasar el 80 %: el avance con visto, por la cola.
        p.enLaApp(vm) { m.guia.value!!.guardarAvance(SeguimientoAvance.Guardado(video, 40, true)) }
    }

    /** Los pedidos de abrir un link, capturados sin abrir nada. */
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

    // ── El flujo entero ──

    /** [modo]: claro, oscuro o grande (letra 1,3). Saca las capturas de cada estado. */
    private fun flujo(modo: String) {
        Telefono.modoNoche(modo == "oscuro")
        if (modo == "grande") Telefono.shell("settings put system font_scale 1.3")
        fun foto(n: String) = Telefono.captura("agenda-$n-$modo")
        conGuia()
        guardarCuenta()
        val e = abrir()
        // La tarjeta de Entreno con la novedad.
        p.nodo(etiqueta("guia-novedad"))
        assertTrue(p.existe(textoQueContiene("2 videos nuevos para vos")))
        foto("01-tarjeta-novedad")
        abrirGuia()
        // La novedad arriba, antes de «Tu app».
        bajarHasta(etiqueta("bloque-novedad"))
        assertTrue(p.existe(textoQueContiene("2 videos nuevos para vos ·")))
        mostrar(etiqueta("bloque-novedad"), arriba = 250f)
        foto("02-novedad-arriba")
        // Bloqueada: el contador, la etiqueta y la tarjeta gris.
        mostrar(etiqueta("agenda-bloqueada"))
        assertTrue(p.existe(texto("Te falta 1 video para habilitar la agenda")))
        assertTrue(p.existe(textoQueContiene("Cuando termines los videos de arriba se habilita la agenda. Te faltan 1.")))
        foto("03-agenda-bloqueada")
        // «Ir al próximo video» lleva al que falta.
        p.tocar(etiqueta("agenda-ir-al-proximo"))
        val titulo = JSONObject(guiaV2()).getJSONArray("clips").let { l -> (0 until l.length()).map { l.getJSONObject(it) }.first { it.getString("id") == "FT-9b" }.getString("titulo") }
        p.esperar("FT-9b en el reproductor", enElPrincipal = false) { p.textoDe(etiqueta("guia-titulo")).takeIf { it == titulo } }
        // Ve el último: el avance sale y la agenda se consulta de nuevo, ya habilitada.
        servidor.respuestas["entregas_app_get"] = guiaV2(ultimoVisto = true)
        servidor.respuestas["entregas_app_agenda"] = habilitada()
        val antes = servidor.a("entregas_app_agenda").size
        marcarVisto(e, "FT-9b")
        p.esperar("el avance") { servidor.a("entregas_app_avance").any { it.contains("FT-9b") } }
        p.esperar("la agenda de nuevo") { servidor.a("entregas_app_agenda").size > antes }
        mostrar(etiqueta("agenda-franjas"), arriba = 200f)
        assertFalse(p.existe(etiqueta("agenda-contador")))
        foto("04-agenda-habilitada")
        // Tocar un chip abre la hoja de confirmación.
        p.tocar(etiqueta("agenda-franja-00000001-0000-4000-8000-000000000000"))
        p.nodo(etiqueta("agenda-hoja-texto"))
        assertTrue(p.textoDe(etiqueta("agenda-hoja-texto")).startsWith("¿Confirmás la entrega el "))
        assertTrue(p.textoDe(etiqueta("agenda-hoja-texto")).endsWith("Dura unas 2 horas."))
        foto("05-confirmacion")
        // Confirmar: sale por la cola y queda pendiente.
        servidor.respuestas["entregas_app_reservar"] = """{"ok": true, "reserva": ${reserva("pendiente")}}"""
        servidor.respuestas["entregas_app_agenda"] = """{"ok": true, "habilitada": true, "autorizada": true, "faltan": 0, "reserva": ${reserva("pendiente")}}"""
        p.tocar(etiqueta("agenda-confirmar"))
        p.esperarQueNoEste(etiqueta("agenda-hoja"))
        p.nodo(etiqueta("agenda-pendiente"))
        p.esperar("la reserva") { servidor.a("entregas_app_reservar").singleOrNull() }
        val cuerpo = JSONObject(servidor.a("entregas_app_reservar").single())
        assertEquals("00000001-0000-4000-8000-000000000000", cuerpo.getString("p_franja"))
        assertTrue(cuerpo.getString("p_id").matches(Regex("[0-9a-f-]{36}")))
        mostrar(etiqueta("agenda-pendiente"))
        p.quieto(400)
        Telefono.shell("mkdir -p ${Telefono.CARPETA_CAPTURAS}")
        Telefono.shell("screencap -p ${Telefono.CARPETA_CAPTURAS}/agenda-06-pendiente-$modo.png")
        // El daemon la confirma: la consulta de cada 5 s la trae con el link.
        servidor.respuestas["entregas_app_agenda"] = """{"ok": true, "habilitada": true, "autorizada": true, "faltan": 0, "reserva": ${reserva("confirmada", meet)}}"""
        p.nodo(etiqueta("agenda-confirmada"), ms = 15_000)
        mostrar(etiqueta("agenda-confirmada"))
        assertTrue(p.textoDe(etiqueta("agenda-confirmada-texto")).startsWith("Tu entrega: "))
        assertTrue(p.existe(texto("¿Necesitás cambiarla? Escribinos por WhatsApp")))
        foto("07-confirmada")
        // «Entrar a la videollamada» abre el link de Meet; «Agregar a mi calendario», el calendario del teléfono.
        val (monitor, links) = monitorDeLinks()
        try {
            p.tocar(etiqueta("agenda-entrar"))
            p.esperar("el link") { links.firstOrNull { it.action == Intent.ACTION_VIEW } }
            assertEquals(meet, links.first { it.action == Intent.ACTION_VIEW }.dataString)
            p.tocar(etiqueta("agenda-calendario"))
            val cal = p.esperar("el calendario") { links.firstOrNull { it.action == Intent.ACTION_INSERT } }
            assertTrue(cal.getLongExtra(android.provider.CalendarContract.EXTRA_EVENT_BEGIN_TIME, 0) > 0)
        } finally {
            InstrumentationRegistry.getInstrumentation().removeMonitor(monitor)
        }
    }

    @Test
    fun flujoEnClaro() = flujo("claro")

    @Test
    fun flujoEnOscuro() = flujo("oscuro")

    @Test
    fun flujoConLetraGrande() = flujo("grande")

    // ── Los otros estados ──

    @Test
    fun laFranjaTomadaMuestraElAvisoYLasFranjasDeNuevo() {
        for (modo in listOf("claro", "oscuro")) {
            Telefono.modoNoche(modo == "oscuro")
            conGuia(get = guiaV2(ultimoVisto = true), agenda = habilitada())
            servidor.respuestas["entregas_app_reservar"] = """{"ok": false, "motivo": "tomada"}"""
            guardarCuenta()
            val e = abrir()
            abrirGuia()
            mostrar(etiqueta("agenda-franjas"), arriba = 200f)
            p.tocar(etiqueta("agenda-franja-00000002-0000-4000-8000-000000000000"))
            p.tocar(etiqueta("agenda-confirmar"))
            p.nodo(etiqueta("agenda-aviso"))
            assertEquals("Ese horario se ocupó recién, elegí otro.", p.textoDe(etiqueta("agenda-aviso")))
            mostrar(etiqueta("agenda-franjas"), arriba = 200f)
            assertTrue(p.existe(etiqueta("agenda-franja-00000001-0000-4000-8000-000000000000")))
            Telefono.captura("agenda-08-fallo-$modo")
            e.close()
        }
    }

    @Test
    fun sinRedQuedaLoGuardadoYElLinkSigueAMano() {
        conGuia(get = guiaV2(ultimoVisto = true), agenda = """{"ok": true, "habilitada": true, "autorizada": true, "faltan": 0, "reserva": ${reserva("confirmada", meet)}}""")
        guardarCuenta()
        abrir().also { e ->
            abrirGuia()
            mostrar(etiqueta("agenda-confirmada"))
            e.close()
        }
        servidor.sinRed = true
        abrir()
        abrirGuia()
        mostrar(etiqueta("agenda-confirmada"))
        p.nodo(etiqueta("agenda-sin-conexion"))
        assertTrue(p.existe(etiqueta("agenda-entrar")))
        Telefono.captura("agenda-09-sin-red-claro")
        servidor.sinRed = false
    }

    @Test
    fun sinAutorizarElTextoYElContador() {
        for (modo in listOf("claro", "oscuro", "grande")) {
            Telefono.modoNoche(modo == "oscuro")
            Telefono.shell("settings put system font_scale ${if (modo == "grande") "1.3" else "1.0"}")
            conGuia(agenda = noAutorizada)
            guardarCuenta()
            val e = abrir()
            abrirGuia()
            mostrar(etiqueta("agenda-no-autorizada"))
            assertTrue(p.existe(texto("Cuando termines de ver todo te habilitamos la agenda.")))
            assertTrue(p.existe(texto("Te falta 1 video para habilitar la agenda")))
            // Sin el botón: no hay nada que hacer más que mirar los videos (el contador lleva al que falta).
            assertFalse(p.existe(etiqueta("agenda-ir-al-proximo")))
            Telefono.captura("agenda-10-no-autorizada-$modo")
            e.close()
        }
    }

    @Test
    fun sinElServidorNuevoLaGuiaQuedaComoAntes() {
        // La guía y el resumen de la 2.1.0, y la agenda que no existe (PGRST202).
        conGuia(get = fixture("get-tomas-avanzado"), res = """{"ok": true, "total": 17, "vistos": 4, "minutos_restantes": 9.0}""", agenda = null)
        guardarCuenta()
        abrir()
        p.nodo(etiqueta("guia-empeza-por-aca"))
        assertFalse(p.existe(etiqueta("guia-novedad")))
        abrirGuia()
        p.esperar("la agenda") { servidor.a("entregas_app_agenda").firstOrNull() }
        bajarHasta(etiqueta("guia-fin"))
        p.quieto(500)
        assertFalse(p.existe(etiqueta("agenda")))
        assertFalse(p.existe(etiqueta("agenda-contador")))
        assertFalse(p.existe(etiqueta("bloque-novedad")))
        assertFalse(p.existe(textoQueContiene("Para ver antes de la entrega")))
    }

    @Test
    fun laTarjetaDeEntrenoMuestraEntrarMediaHoraAntes() {
        val i = Instant.now().plus(10, ChronoUnit.MINUTES)
        val r = """{"inicio": "$i", "fin": "${i.plus(2, ChronoUnit.HOURS)}", "estado": "confirmada", "meet_url": "$meet"}"""
        conGuia(get = guiaV2(ultimoVisto = true), res = """{"ok": true, "total": 17, "vistos": 17, "minutos_restantes": 0, "reserva": $r}""", agenda = null)
        guardarCuenta()
        abrir()
        p.nodo(etiqueta("entrega-ahora"))
        assertTrue(p.existe(textoQueContiene("Tu entrega empieza a las ")))
        Telefono.captura("agenda-11-entreno-entrar-claro")
        val (monitor, links) = monitorDeLinks()
        try {
            p.tocar(etiqueta("entrega-ahora"))
            assertEquals(meet, p.esperar("el link") { links.firstOrNull() }.dataString)
        } finally {
            InstrumentationRegistry.getInstrumentation().removeMonitor(monitor)
        }
    }
}
