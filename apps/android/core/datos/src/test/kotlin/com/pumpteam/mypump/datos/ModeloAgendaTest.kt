package com.pumpteam.mypump.datos

import com.pumpteam.mypump.modelos.AgendaEntrega
import com.pumpteam.mypump.modelos.Guia
import com.pumpteam.mypump.modelos.ReservaEntrega
import com.pumpteam.mypump.modelos.ValorJson
import com.pumpteam.mypump.reglas.ReglasAgenda
import com.pumpteam.mypump.reglas.SeguimientoAvance
import java.io.IOException
import java.time.Instant
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch
import kotlinx.coroutines.yield
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * La novedad y la agenda de la entrega en los modelos (2.2.0, spec §5): sin el servidor nuevo todo como en la 2.1.0, la
 * caché sin red, la reserva por la cola (idempotente por `p_id`, sin gastar intento sin red, en su carril), los fallos, la
 * consulta al ver el último obligatorio, la demo y la tarjeta que vuelve después de ocultarla.
 */
class ModeloAgendaTest {
    private val guiaJson = Compartido.texto("fixtures/guia/get-tomas.json")
    private val sinFuncion = 404 to """{"code":"PGRST202","message":"Could not find the function public.entregas_app_agenda"}"""

    private val franjas = """[{"id":"11111111-1111-4111-8111-111111111111","inicio":"2026-11-12T10:00:00-03:00","fin":"2026-11-12T12:00:00-03:00"},
        {"id":"22222222-2222-4222-8222-222222222222","inicio":"2026-11-12T14:00:00-03:00","fin":"2026-11-12T16:00:00-03:00"}]"""
    private val habilitada = """{"ok":true,"habilitada":true,"autorizada":true,"faltan":0,"franjas":$franjas,"reserva":null}"""
    private fun reserva(estado: String, extra: String = "") =
        """{"id":"r1","inicio":"2026-11-12T10:00:00-03:00","fin":"2026-11-12T12:00:00-03:00","estado":"$estado"$extra}"""

    private class Entorno(val m: ModeloGuia, val cola: Outbox, val t: TransporteProgramado, val disco: Disco, val cuerpos: MutableList<Pair<String, ValorJson>>) {
        val agenda: ModeloAgenda get() = m.agenda
        fun cuerposDe(fn: String) = synchronized(cuerpos) { cuerpos.filter { it.first == fn }.map { it.second } }
    }

    private suspend fun entorno(
        alcance: CoroutineScope,
        disco: Disco = Disco(carpetaTemporal("agenda"), "tok"),
        reloj: () -> Long = System::currentTimeMillis,
        regla: suspend (String, ValorJson) -> Pair<Int, String>,
    ): Entorno {
        val cuerpos = mutableListOf<Pair<String, ValorJson>>()
        val t = TransporteProgramado { fn, c ->
            synchronized(cuerpos) { cuerpos += fn to c }
            regla(fn, c)
        }
        val cliente = ClienteRpc(transporte = t)
        val esc = Escrituras(cliente, "tok")
        val cola = Outbox(archivo = disco.archivo("outbox.json"), reintentoAutomatico = false, alcance = alcance) { esc.ejecutar(it) }
        val m = ModeloGuia(cliente, "tok", cola, disco, alcance, reloj = reloj).also {
            it.alDia()
            it.agenda.alDia()
        }
        cola.observar(estado = {}, abandonadas = m::alAbandonar, guardadas = m::alGuardar)
        yield()
        return Entorno(m, cola, t, disco, cuerpos)
    }

    private suspend fun asentar() = repeat(20) { yield() }

    // ── Sin el servidor nuevo, exactamente como la 2.1.0 ──

    @Test
    fun sinLaFuncionNoHayAgendaNiNadaNuevo() = enUnHilo { alcance ->
        val e = entorno(alcance) { fn, _ ->
            when (fn) {
                "entregas_app_agenda" -> sinFuncion
                "entregas_app_get" -> 200 to guiaJson
                "entregas_app_resumen" -> 200 to """{"ok":true,"total":17,"vistos":0,"minutos_restantes":12}"""
                else -> 200 to "true"
            }
        }
        e.m.abrir()
        e.m.refrescarResumen()
        assertFalse(e.agenda.refrescar())
        assertNull(e.agenda.agenda.value)
        assertFalse(e.agenda.desdeCache.value)
        // La guía y el resumen, sin los campos nuevos: los de la 2.1.0.
        val g = e.m.guia.value!!
        assertEquals(1, g.fase)
        assertNull(g.novedadEn)
        assertTrue(g.clips.none { it.nuevo || it.obligatorio != null })
        assertNull(e.m.resumen.value!!.novedadEn)
        assertNull(e.m.resumen.value!!.reserva)
        // `ok: false` (sin guía o el token) tampoco muestra agenda, y borra lo guardado.
        val otro = entorno(alcance, disco = e.disco) { fn, _ -> if (fn == "entregas_app_agenda") 200 to """{"ok":false,"motivo":"sin_guia"}""" else 200 to "true" }
        otro.agenda.refrescar()
        assertNull(otro.agenda.agenda.value)
        otro.agenda.alDia()
        assertNull(otro.disco.leer(ModeloAgenda.ARCHIVO))
        // Ver el último video con la agenda en null no la consulta.
        val antes = e.t.llamadas.count { it == "entregas_app_agenda" }
        for (c in g.clips) e.m.guardarAvance(SeguimientoAvance.Guardado(c.id, 30, true))
        e.cola.drenar()
        asentar()
        assertEquals(antes, e.t.llamadas.count { it == "entregas_app_agenda" })
    }

    @Test
    fun laMarcaDeOcultarSinNovedadValeComoAntes() = enUnHilo { alcance ->
        val disco = Disco(carpetaTemporal("agenda"), "tok")
        disco.guardar(ModeloGuia.ARCHIVO_OCULTA, ValorJson.Booleano(true))
        val e = entorno(alcance, disco) { fn, _ ->
            if (fn == "entregas_app_resumen") 200 to """{"ok":true,"total":17,"vistos":2,"minutos_restantes":12}""" else 200 to "true"
        }
        assertTrue(e.m.ocultaAMano.value)
        e.m.refrescarResumen()
        assertTrue(e.m.ocultaAMano.value)
        e.m.ocultarDeEntreno(false)
        assertFalse(e.m.ocultaAMano.value)
    }

    // ── La novedad hace volver la tarjeta ──

    @Test
    fun laTarjetaVuelveConUnaNovedadPosteriorYOcultarlaGuardaLaFecha() = enUnHilo { alcance ->
        var ahora = Instant.parse("2026-11-04T12:00:00Z").toEpochMilli()
        var novedad: String? = null
        val e = entorno(alcance, reloj = { ahora }) { fn, _ ->
            if (fn == "entregas_app_resumen") {
                200 to """{"ok":true,"total":17,"vistos":2,"minutos_restantes":12${novedad?.let { ",\"novedad_en\":\"$it\"" } ?: ""}}"""
            } else {
                200 to "true"
            }
        }
        e.m.refrescarResumen()
        e.m.ocultarDeEntreno(true)
        assertTrue(e.m.ocultaAMano.value)
        e.m.alDia()
        assertEquals("2026-11-04T12:00:00Z", e.disco.leer(ModeloGuia.ARCHIVO_OCULTA)?.let { ValorJson.desde(it) }?.get("en")?.comoTexto)
        // Una novedad de antes de ocultarla no la trae.
        novedad = "2026-11-03T12:00:00-03:00"
        e.m.refrescarResumen()
        assertTrue(e.m.ocultaAMano.value)
        // Una posterior, sí.
        novedad = "2026-11-05T12:00:00-03:00"
        e.m.refrescarResumen()
        assertFalse(e.m.ocultaAMano.value)
        // Ocultarla de nuevo guarda la fecha de ahora: queda oculta con esa misma novedad.
        ahora = Instant.parse("2026-11-06T10:00:00Z").toEpochMilli()
        e.m.ocultarDeEntreno(true)
        e.m.refrescarResumen()
        assertTrue(e.m.ocultaAMano.value)
        // Al abrir la app otra vez, se lee la fecha del disco.
        e.m.alDia()
        val otra = entorno(alcance, e.disco, reloj = { ahora }) { fn, _ ->
            if (fn == "entregas_app_resumen") 200 to """{"ok":true,"total":17,"vistos":2,"minutos_restantes":12,"novedad_en":"$novedad"}""" else 200 to "true"
        }
        otra.m.refrescarResumen()
        assertTrue(otra.m.ocultaAMano.value)
    }

    @Test
    fun laMarcaDeLaVersionAnteriorVuelveConLaNovedad() = enUnHilo { alcance ->
        val disco = Disco(carpetaTemporal("agenda"), "tok")
        disco.guardar(ModeloGuia.ARCHIVO_OCULTA, ValorJson.Booleano(true))
        val e = entorno(alcance, disco) { fn, _ ->
            if (fn == "entregas_app_resumen") 200 to """{"ok":true,"total":17,"vistos":2,"minutos_restantes":12,"novedad_en":"2026-11-05T12:00:00-03:00"}""" else 200 to "true"
        }
        assertTrue(e.m.ocultaAMano.value)
        e.m.refrescarResumen()
        assertFalse(e.m.ocultaAMano.value)
    }

    // ── La agenda ──

    @Test
    fun laAgendaSeGuardaYSinRedQuedaLaUltima() = enUnHilo { alcance ->
        val conReserva = """{"ok":true,"habilitada":true,"autorizada":true,"faltan":0,"reserva":${reserva("confirmada", ""","meet_url":"https://meet.google.com/abc"""")}}"""
        val e = entorno(alcance) { fn, _ -> if (fn == "entregas_app_agenda") 200 to conReserva else 200 to "true" }
        assertTrue(e.agenda.refrescar())
        assertEquals(ReservaEntrega.Estado.CONFIRMADA, e.agenda.agenda.value?.reserva?.estado)
        e.agenda.alDia()
        val sinRed = ModeloAgenda(ClienteRpc(transporte = SinRed), "tok", null, e.disco, alcance).also { it.alDia() }
        assertEquals(e.agenda.agenda.value, sinRed.agenda.value)
        assertFalse(sinRed.refrescar())
        assertTrue(sinRed.desdeCache.value)
        // Con la reserva confirmada guardada, el link sigue a mano.
        assertEquals("https://meet.google.com/abc", sinRed.agenda.value?.reserva?.meetUrl)
    }

    @Test
    fun reservarEsIdempotentePorPidYSinRedNoGastaIntento() = enUnHilo { alcance ->
        var red = false
        var estado = "pendiente"
        val e = entorno(alcance) { fn, c ->
            when (fn) {
                "entregas_app_agenda" -> 200 to (if (red) """{"ok":true,"habilitada":true,"autorizada":true,"faltan":0,"reserva":${reserva(estado)}}""" else habilitada)
                "entregas_app_reservar" -> {
                    if (!red) throw IOException("sin conexión (prueba)")
                    200 to """{"ok":true,"reserva":${reserva("pendiente", ""","id":"${c["p_id"]?.comoTexto}"""").replace("\"id\":\"r1\",", "")}}"""
                }
                else -> 200 to "true"
            }
        }
        e.agenda.refrescar()
        val f = e.agenda.agenda.value!!.franjas.first()
        assertTrue(e.agenda.reservar(f))
        // Un segundo toque mientras sale no encola otra.
        assertFalse(e.agenda.reservar(f))
        assertEquals(f, e.agenda.reservando.value)
        assertEquals(ReglasAgenda.Vista.PENDIENTE, ReglasAgenda.vista(e.agenda.agenda.value!!, 0, e.agenda.reservando.value != null))
        // Sin red: la op queda, sin gastar intento, y el carril general no se frena.
        e.m.guardarAvance(SeguimientoAvance.Guardado("FT-1a", 12, false))
        e.cola.drenar()
        e.cola.drenar()
        val ops = e.cola.operaciones()
        assertEquals(1, ops.size)
        assertEquals(ModeloAgenda.KIND, ops[0].kind)
        assertEquals(0, ops[0].tries)
        assertEquals(1, e.cuerposDe("entregas_app_avance").size)
        // Vuelve la red: el reintento manda el mismo p_id.
        red = true
        e.cola.drenar()
        asentar()
        val pids = e.cuerposDe("entregas_app_reservar").map { it["p_id"]?.comoTexto }
        assertEquals(3, pids.size)
        assertEquals(1, pids.toSet().size)
        assertEquals(f.id, e.cuerposDe("entregas_app_reservar").first()["p_franja"]?.comoTexto)
        assertTrue(e.cola.operaciones().isEmpty())
        assertNull(e.agenda.reservando.value)
        assertEquals(ReservaEntrega.Estado.PENDIENTE, e.agenda.agenda.value?.reserva?.estado)
        assertTrue(e.agenda.agenda.value!!.franjas.isEmpty())
        // El daemon la confirma: la próxima consulta la trae con el link.
        estado = "confirmada\",\"meet_url\":\"https://meet.google.com/abc"
        e.agenda.refrescar()
        assertEquals(ReservaEntrega.Estado.CONFIRMADA, e.agenda.agenda.value?.reserva?.estado)
        // Con una reserva vigente no se puede reservar otra.
        assertFalse(e.agenda.reservar(f))
    }

    @Test
    fun laReservaPendienteSeConsultaCada5sElPrimerMinutoYDespuesCada30s() = enUnHilo { alcance ->
        var ahora = 0L
        val esperas = mutableListOf<Long>()
        val t = TransporteProgramado { fn, _ ->
            if (fn == "entregas_app_agenda") 200 to """{"ok":true,"habilitada":true,"autorizada":true,"reserva":${reserva("pendiente")}}""" else 200 to "true"
        }
        val m = ModeloAgenda(ClienteRpc(transporte = t), "tok", null, null, alcance, reloj = { ahora }, esperar = { ms ->
            esperas += ms
            ahora += ms
        })
        val trabajo = alcance.launch { m.seguir() }
        kotlinx.coroutines.withTimeout(10_000) { while (esperas.size < 15) kotlinx.coroutines.delay(5) }
        trabajo.cancel()
        // La primera al abrir, cada 5 s durante 60 s y después cada 30 s (el daemon puede tardar).
        assertEquals(List(12) { ModeloAgenda.CONSULTA_CADA_MS }, esperas.take(12))
        assertTrue(esperas.drop(12).all { it == ReglasAgenda.CONSULTA_SALA_MS })
        assertTrue(t.llamadas.count { it == "entregas_app_agenda" } >= 15)
    }

    @Test
    fun enLaFranjaSeConsultaCada30sHastaQueMatiAbraLaSala() = enUnHilo { alcance ->
        // 9:40 de Argentina del día de la entrega (10:00): 20 min antes, dentro de la ventana.
        var ahora = Instant.parse("2026-11-12T12:40:00Z").toEpochMilli()
        val esperas = mutableListOf<Long>()
        var consultas = 0
        val t = TransporteProgramado { fn, _ ->
            if (fn != "entregas_app_agenda") return@TransporteProgramado 200 to "true"
            consultas++
            // A la tercera consulta Mati ya entró al Meet.
            val sala = if (consultas >= 3) ""","sala_abierta_en":"2026-11-12T09:59:00-03:00"""" else ""
            200 to """{"ok":true,"habilitada":true,"autorizada":true,"faltan":0,"reserva":${reserva("confirmada", ""","meet_url":"https://meet.google.com/abc"$sala""")}}"""
        }
        val m = ModeloAgenda(ClienteRpc(transporte = t), "tok", null, null, alcance, reloj = { ahora }, esperar = { ms ->
            esperas += ms
            ahora += ms
        })
        val trabajo = alcance.launch { m.seguir() }
        kotlinx.coroutines.withTimeout(10_000) { while (consultas < 3) kotlinx.coroutines.delay(5) }
        kotlinx.coroutines.delay(300)
        trabajo.cancel()
        // Sin la sala: sin botón; cada 30 s; con la sala, para (queda esperando un cambio).
        assertEquals(listOf(ReglasAgenda.CONSULTA_SALA_MS, ReglasAgenda.CONSULTA_SALA_MS), esperas)
        assertEquals(3, consultas)
        val r = m.agenda.value!!.reserva!!
        assertNotNull(r.salaAbiertaEn)
        assertTrue(ReglasAgenda.puedeEntrar(r, Instant.ofEpochMilli(ahora)))
        // Al volver a primer plano en la franja sin sala, consulta; antes del día, no.
        var c2 = 0
        val sinSala = """{"ok":true,"habilitada":true,"autorizada":true,"faltan":0,"reserva":${reserva("confirmada", ""","meet_url":"https://meet.google.com/abc"""")}}"""
        val t2 = TransporteProgramado { fn, _ -> if (fn == "entregas_app_agenda") { c2++; 200 to sinSala } else 200 to "true" }
        var reloj2 = Instant.parse("2026-11-11T12:40:00Z").toEpochMilli()
        val m2 = ModeloAgenda(ClienteRpc(transporte = t2), "tok", null, null, alcance, reloj = { reloj2 })
        m2.refrescar()
        m2.alVolverAPrimerPlano()
        assertEquals(1, c2)
        reloj2 = Instant.parse("2026-11-12T12:50:00Z").toEpochMilli()
        m2.alVolverAPrimerPlano()
        assertEquals(2, c2)
    }

    @Test
    fun conLaPantallaAbiertaLaPendienteSeConfirmaSola() = enUnHilo { alcance ->
        var respuesta = habilitada
        val e = entorno(alcance) { fn, _ ->
            when (fn) {
                "entregas_app_agenda" -> 200 to respuesta
                "entregas_app_reservar" -> 200 to """{"ok":true,"reserva":${reserva("pendiente")}}"""
                else -> 200 to "true"
            }
        }
        val trabajo = alcance.launch { e.agenda.seguir() }
        kotlinx.coroutines.withTimeout(5_000) { while (e.agenda.agenda.value?.franjas.isNullOrEmpty()) kotlinx.coroutines.delay(20) }
        respuesta = """{"ok":true,"habilitada":true,"autorizada":true,"faltan":0,"reserva":${reserva("pendiente")}}"""
        assertTrue(e.agenda.reservar(e.agenda.agenda.value!!.franjas.first()))
        e.cola.drenar()
        kotlinx.coroutines.withTimeout(5_000) { while (e.agenda.agenda.value?.reserva?.estado != ReservaEntrega.Estado.PENDIENTE) kotlinx.coroutines.delay(20) }
        respuesta = """{"ok":true,"habilitada":true,"autorizada":true,"faltan":0,"reserva":${reserva("confirmada", ""","meet_url":"https://meet.google.com/abc"""")}}"""
        // La consulta de cada 5 s la trae confirmada.
        kotlinx.coroutines.withTimeout(12_000) { while (e.agenda.agenda.value?.reserva?.estado != ReservaEntrega.Estado.CONFIRMADA) kotlinx.coroutines.delay(50) }
        trabajo.cancel()
    }

    @Test
    fun laFranjaTomadaAvisaYMuestraLasFranjasDeNuevo() = enUnHilo { alcance ->
        var tomada = false
        val e = entorno(alcance) { fn, _ ->
            when (fn) {
                "entregas_app_agenda" -> 200 to habilitada
                "entregas_app_reservar" -> {
                    tomada = true
                    200 to """{"ok":false,"motivo":"tomada"}"""
                }
                else -> 200 to "true"
            }
        }
        e.agenda.refrescar()
        e.agenda.reservar(e.agenda.agenda.value!!.franjas.first())
        e.cola.drenar()
        asentar()
        assertTrue(tomada)
        assertNull(e.agenda.reservando.value)
        assertEquals("Ese horario se ocupó recién, elegí otro.", e.agenda.aviso.value)
        assertEquals(ReglasAgenda.Vista.ELEGIR, ReglasAgenda.vista(e.agenda.agenda.value!!, 0, false))
        // Elegir otra borra el aviso.
        assertTrue(e.agenda.reservar(e.agenda.agenda.value!!.franjas.last()))
        assertNull(e.agenda.aviso.value)
    }

    @Test
    fun unaReservaVencidaOConMotivoDesconocidoVuelveALasFranjas() = enUnHilo { alcance ->
        var motivo = "vencida"
        val e = entorno(alcance) { fn, _ ->
            if (fn == "entregas_app_agenda") 200 to """{"ok":true,"habilitada":true,"autorizada":true,"franjas":$franjas,"reserva":${reserva("fallo", ""","motivo":"$motivo"""")}}"""
            else 200 to "true"
        }
        e.agenda.refrescar()
        assertEquals("No pudimos reservar ese horario, elegí otro.", e.agenda.aviso.value)
        assertEquals(ReglasAgenda.Vista.ELEGIR, ReglasAgenda.vista(e.agenda.agenda.value!!, 0, false))
        assertEquals(2, e.agenda.agenda.value!!.franjas.size)
        motivo = "algo_nuevo"
        val otra = entorno(alcance) { fn, _ ->
            if (fn == "entregas_app_agenda") 200 to """{"ok":true,"habilitada":true,"autorizada":true,"franjas":$franjas,"reserva":${reserva("fallo", ""","motivo":"$motivo"""")}}"""
            else 200 to "true"
        }
        otra.agenda.refrescar()
        assertEquals("No pudimos reservar ese horario, elegí otro.", otra.agenda.aviso.value)
    }

    @Test
    fun sinAutorizarNoSeAgendaYReservarPuedeRechazarPorAutorizada() = enUnHilo { alcance ->
        val e = entorno(alcance) { fn, _ ->
            when (fn) {
                "entregas_app_agenda" -> 200 to """{"ok":true,"habilitada":false,"autorizada":false,"faltan":3}"""
                "entregas_app_reservar" -> 200 to """{"ok":false,"motivo":"autorizada"}"""
                else -> 200 to "true"
            }
        }
        e.agenda.refrescar()
        val a = e.agenda.agenda.value!!
        assertEquals(ReglasAgenda.Vista.NO_AUTORIZADA, ReglasAgenda.vista(a, ReglasAgenda.faltanAMostrar(a, null), false))
        assertEquals(3, ReglasAgenda.faltanAMostrar(a, null))
        // Una franja guardada de antes que el servidor rechaza: sin aviso de «se ocupó», queda lo que diga la agenda.
        e.agenda.reservar(AgendaEntrega.desde(com.pumpteam.mypump.modelos.ValorJson.parsear(habilitada).aJson())!!.franjas.first())
        e.cola.drenar()
        asentar()
        assertNull(e.agenda.aviso.value)
        assertNull(e.agenda.reservando.value)
    }

    @Test
    fun verElUltimoObligatorioConsultaLaAgendaDespuesDeMandarElAvance() = enUnHilo { alcance ->
        val conCampos = ValorJson.parsear(guiaJson).let { v ->
            val o = (v as ValorJson.Objeto).campos.toMutableMap()
            val clips = (o["clips"] as ValorJson.Lista).elementos.mapIndexed { i, c ->
                val campos = (c as ValorJson.Objeto).campos.toMutableMap()
                campos["obligatorio"] = ValorJson.Booleano(i == 0)
                ValorJson.Objeto(campos)
            }
            o["clips"] = ValorJson.Lista(clips)
            ValorJson.Objeto(o).serializar()
        }
        val orden = mutableListOf<String>()
        val e = entorno(alcance) { fn, _ ->
            synchronized(orden) { orden += fn }
            when (fn) {
                "entregas_app_get" -> 200 to conCampos
                "entregas_app_agenda" -> 200 to """{"ok":true,"habilitada":false,"autorizada":true,"faltan":1}"""
                else -> 200 to "true"
            }
        }
        e.m.abrir()
        e.agenda.refrescar()
        val primero = e.m.guia.value!!.clips[0]
        assertEquals(1, ReglasAgenda.faltan(e.m.guia.value!!))
        // Un video que no es obligatorio no la consulta.
        e.m.guardarAvance(SeguimientoAvance.Guardado(e.m.guia.value!!.clips[1].id, 40, true))
        e.cola.drenar()
        asentar()
        assertEquals(1, orden.count { it == "entregas_app_agenda" })
        e.m.guardarAvance(SeguimientoAvance.Guardado(primero.id, 40, true))
        repeat(5) {
            e.cola.drenar()
            asentar()
        }
        assertEquals(0, ReglasAgenda.faltan(e.m.guia.value!!))
        val avance = orden.lastIndexOf("entregas_app_avance")
        val agenda = orden.lastIndexOf("entregas_app_agenda")
        assertEquals(2, orden.count { it == "entregas_app_agenda" })
        assertTrue(agenda > avance, "la agenda se consulta después de mandar el avance: $orden")
    }

    @Test
    fun laDemoSeHabilitaConLoVistoYConfirmaSinVideollamada() = enUnHilo { alcance ->
        val g = Guia.desde(ValorJson.parsear(Compartido.texto("demo/guia.json")).aJson())!!
        val plantilla = AgendaEntrega.desde(ValorJson.parsear(Compartido.texto("demo/agenda.json")).aJson())!!
        val t = TransporteProgramado { _, _ -> 500 to "" }
        val m = ModeloGuia.demo(ClienteRpc(transporte = t), g, alcance, plantilla)
        m.agenda.alDia()
        asentar()
        assertEquals(2, g.fase)
        assertEquals(2, g.nuevos.size)
        val a = m.agenda.agenda.value!!
        assertTrue(a.autorizada)
        assertFalse(a.habilitada)
        assertEquals(ReglasAgenda.faltan(g), a.faltan)
        assertTrue(ReglasAgenda.faltan(g) > 0)
        for (c in ReglasAgenda.obligatorios(g)) m.guardarAvance(SeguimientoAvance.Guardado(c.id, 30, true))
        asentar()
        val hab = m.agenda.agenda.value!!
        assertTrue(hab.puedeAgendar)
        assertTrue(hab.franjas.isNotEmpty())
        // Las franjas de muestra siempre empiezan mañana o después.
        assertTrue(hab.franjas.all { it.inicio.isAfter(Instant.now()) })
        // Y de lunes a viernes, como el servidor: nunca un sábado ni un domingo.
        assertTrue(hab.franjas.all { ReglasAgenda.esHabil(it.inicio.atZone(ReglasAgenda.ARGENTINA).toLocalDate()) }, "${hab.franjas}")
        assertTrue(m.agenda.reservar(hab.franjas.first()))
        val r = m.agenda.agenda.value!!.reserva!!
        assertEquals(ReservaEntrega.Estado.CONFIRMADA, r.estado)
        assertNull(r.meetUrl)
        // La demo no llama al servidor.
        assertTrue(t.llamadas.isEmpty())
    }

    @Test
    fun elResumenConservaLaNovedadYLaReservaAlAbrirLaGuia() = enUnHilo { alcance ->
        val e = entorno(alcance) { fn, _ ->
            when (fn) {
                "entregas_app_resumen" -> 200 to """{"ok":true,"total":17,"vistos":0,"minutos_restantes":12,"novedad_en":"2026-11-05T12:00:00-03:00","reserva":${reserva("confirmada", ""","meet_url":"https://meet.google.com/x"""")}}"""
                "entregas_app_get" -> 200 to guiaJson
                else -> 200 to "true"
            }
        }
        e.m.refrescarResumen()
        e.m.abrir()
        val r = e.m.resumen.value!!
        assertEquals("2026-11-05T12:00:00-03:00", r.novedadEn)
        assertNotNull(r.reserva)
    }

    // ── Cambiar el horario (videollamada 2.3.0, palanca `elegir_horario`) ──

    private val franjasLejos = """[{"id":"f1","inicio":"2099-11-12T10:00:00-03:00","fin":"2099-11-12T11:00:00-03:00"},
        {"id":"f2","inicio":"2099-11-13T12:00:00-03:00","fin":"2099-11-13T13:00:00-03:00"}]"""
    private fun reservaLejos(inicio: String = "2099-11-12T10:00:00-03:00", tipo: String = "revision") =
        """{"id":"r1","inicio":"$inicio","fin":"${inicio.replace("T10:", "T11:").replace("T12:", "T13:")}","estado":"confirmada","meet_url":"https://meet.google.com/x","tipo":"$tipo"}"""

    @Test
    fun cambiarVaPorLaColaConLaReservaQueSeDejaYElTopeDelServidor() = enUnHilo { alcance ->
        var agenda = """{"ok":true,"autorizada":true,"habilitada":true,"faltan":0,"franjas":$franjasLejos,"cambio":{"permitido":true,"restantes":1,"hasta":"2099-11-11T10:00:00-03:00"},"reserva":${reservaLejos()}}"""
        val e = entorno(alcance) { fn, _ ->
            when (fn) {
                "entregas_app_agenda" -> 200 to agenda
                "entregas_app_cambiar" -> 200 to """{"ok":true,"reserva":${reservaLejos("2099-11-13T12:00:00-03:00")}}"""
                else -> 200 to "true"
            }
        }
        e.agenda.refrescar()
        assertTrue(e.agenda.puedeCambiar(), "con cambio permitido vienen las franjas")
        assertEquals(2, e.agenda.agenda.value!!.franjas.size)
        assertEquals(com.pumpteam.mypump.modelos.TipoVideollamada.REVISION, e.agenda.agenda.value!!.reserva!!.tipo)
        // Lo que el servidor va a decir después del cambio: sin cambios restantes y sin franjas.
        agenda = """{"ok":true,"autorizada":true,"habilitada":true,"faltan":0,"franjas":$franjasLejos,"cambio":{"permitido":false,"restantes":0},"reserva":${reservaLejos("2099-11-13T12:00:00-03:00")}}"""
        val nueva = e.agenda.agenda.value!!.franjas.first { it.id == "f2" }
        assertTrue(e.agenda.cambiar(nueva))
        assertEquals(nueva, e.agenda.reservando.value)
        // Un segundo toque no encola otro.
        assertFalse(e.agenda.cambiar(nueva))
        val ops = e.cola.operaciones().filter { it.kind == ModeloAgenda.KIND }
        assertEquals(1, ops.size)
        assertEquals("r1", ops.single().payload["cambia"]?.comoTexto)
        e.cola.drenar()
        asentar()
        val pedidos = e.cuerposDe("entregas_app_cambiar")
        assertEquals(1, pedidos.size)
        assertEquals("r1", pedidos.single()["p_reserva"]?.comoTexto)
        assertEquals("f2", pedidos.single()["p_franja"]?.comoTexto)
        assertEquals(ops.single().payload["id"]?.comoTexto, pedidos.single()["p_id"]?.comoTexto)
        assertTrue(e.cuerposDe("entregas_app_reservar").isEmpty(), "cambiar no reserva otra")
        assertNull(e.agenda.reservando.value)
        assertEquals(Instant.parse("2099-11-13T15:00:00Z"), e.agenda.agenda.value!!.reserva!!.inicio)
        assertEquals(ReservaEntrega.Estado.CONFIRMADA, e.agenda.agenda.value!!.reserva!!.estado)
        assertFalse(e.agenda.puedeCambiar())
        assertTrue(e.agenda.agenda.value!!.franjas.isEmpty(), "sin cambios restantes: sin franjas")
    }

    @Test
    fun elTopeOElPlazoDejanElAvisoDeEscribirPorElChat() = enUnHilo { alcance ->
        val e = entorno(alcance) { fn, _ ->
            when (fn) {
                "entregas_app_agenda" -> 200 to """{"ok":true,"autorizada":true,"habilitada":true,"faltan":0,"franjas":$franjasLejos,"cambio":{"permitido":true},"reserva":${reservaLejos()}}"""
                "entregas_app_cambiar" -> 200 to """{"ok":false,"motivo":"tope"}"""
                else -> 200 to "true"
            }
        }
        e.agenda.refrescar()
        assertTrue(e.agenda.cambiar(e.agenda.agenda.value!!.franjas[1]))
        e.cola.drenar()
        asentar()
        assertEquals(ReglasAgenda.TEXTO_SIN_CAMBIO, e.agenda.aviso.value)
        assertEquals(Instant.parse("2099-11-12T13:00:00Z"), e.agenda.agenda.value!!.reserva!!.inicio, "la reserva queda como estaba")
        assertNull(e.agenda.reservando.value)
    }

    @Test
    fun laPalancaElegirHorarioEstaApagadaSinLaClave() {
        assertFalse(PalancaRemota.desde(ValorJson.objeto()).elegirHorario)
        assertFalse(PalancaRemota.desde(ValorJson.objeto("elegir_horario" to ValorJson.Texto("si"))).elegirHorario)
        assertTrue(PalancaRemota.desde(ValorJson.objeto("elegir_horario" to ValorJson.Booleano(true))).elegirHorario)
    }

    @Test
    fun sinPermisoDeCambioNoSeEncolaNada() = enUnHilo { alcance ->
        val e = entorno(alcance) { fn, _ ->
            if (fn == "entregas_app_agenda") 200 to """{"ok":true,"autorizada":true,"habilitada":true,"franjas":$franjasLejos,"reserva":${reservaLejos()}}""" else 200 to "true"
        }
        e.agenda.refrescar()
        assertTrue(e.agenda.agenda.value!!.franjas.isEmpty(), "una 2.2.0: con la reserva vigente no van franjas")
        assertFalse(e.agenda.cambiar(com.pumpteam.mypump.modelos.FranjaEntrega("f2", Instant.parse("2099-11-13T15:00:00Z"), Instant.parse("2099-11-13T16:00:00Z"))))
        assertTrue(e.cola.operaciones().isEmpty())
    }

    @Test
    fun sinElLinkTambienSeConsultaEnLaVentana() = enUnHilo { alcance ->
        // 9:55 del día, confirmada sin `meet_url` todavía: «Estamos preparando la sala» y se consulta cada 30 s.
        var ahora = Instant.parse("2026-11-12T12:55:00Z").toEpochMilli()
        var consultas = 0
        val t = TransporteProgramado { fn, _ ->
            if (fn != "entregas_app_agenda") return@TransporteProgramado 200 to "true"
            consultas++
            val link = if (consultas >= 3) ""","meet_url":"https://meet.google.com/abc","sala_abierta_en":"2026-11-12T09:58:00-03:00"""" else ""
            200 to """{"ok":true,"habilitada":true,"autorizada":true,"faltan":0,"reserva":${reserva("confirmada", link)}}"""
        }
        val m = ModeloAgenda(ClienteRpc(transporte = t), "tok", null, null, alcance, reloj = { ahora }, esperar = { ms -> ahora += ms })
        m.refrescar()
        assertEquals(ReglasAgenda.EstadoEntrar.Preparando, ReglasAgenda.estadoEntrar(m.agenda.value!!.reserva, Instant.ofEpochMilli(ahora)))
        val trabajo = alcance.launch { m.seguir() }
        kotlinx.coroutines.withTimeout(10_000) { while (consultas < 3) kotlinx.coroutines.delay(5) }
        trabajo.cancel()
        assertTrue(ReglasAgenda.puedeEntrar(m.agenda.value!!.reserva, Instant.ofEpochMilli(ahora)))
    }
}
