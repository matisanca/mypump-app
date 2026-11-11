package com.pumpteam.mypump.reglas

import com.pumpteam.mypump.modelos.AgendaEntrega
import com.pumpteam.mypump.modelos.CambioAgenda
import com.pumpteam.mypump.modelos.FranjaEntrega
import com.pumpteam.mypump.modelos.ReservaEntrega
import com.pumpteam.mypump.modelos.TipoVideollamada
import java.time.Instant
import java.time.OffsetDateTime
import java.time.ZoneId
import kotlinx.serialization.json.Json
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/** La videollamada 2.3.0: la tarjeta, la cuenta regresiva, los avisos y el cambio (gemelo de VideollamadaReglasTests). */
class VideollamadaReglasTest {
    private val ar = ReglasAgenda.ARGENTINA
    private fun f(s: String): Instant = OffsetDateTime.parse(s).toInstant()
    private fun a(s: String) = AgendaEntrega.desde(Json.parseToJsonElement(s))!!
    private val r = ReservaEntrega("r1", f("2026-11-12T10:00:00-03:00"), f("2026-11-12T11:00:00-03:00"), ReservaEntrega.Estado.CONFIRMADA, "https://meet.google.com/abc", null)

    @Test
    fun nuncaDiceEntrega() {
        assertEquals("videollamada de comienzo", ReglasAgenda.nombre(TipoVideollamada.COMIENZO))
        assertEquals("videollamada de revisión", ReglasAgenda.nombre(TipoVideollamada.REVISION))
        assertEquals("Tu videollamada de revisión", ReglasAgenda.tituloTarjeta(TipoVideollamada.REVISION))
        assertEquals("Agendá tu videollamada de comienzo", ReglasAgenda.textoTitulo(null))
        val todos = listOf(
            ReglasAgenda.TEXTO_DESDE_ACA, ReglasAgenda.TEXTO_ADMITE, ReglasAgenda.TEXTO_CAMBIAR, ReglasAgenda.TEXTO_SIN_FRANJAS,
            ReglasAgenda.ETIQUETA, ReglasAgenda.TEXTO_SIN_CAMBIO, ReglasAgenda.TEXTO_PREPARANDO, ReglasAgenda.TEXTO_YA_PODES,
            ReglasAgenda.TEXTO_SALA_ABIERTA, ReglasAgenda.textoHoy(r, ar, f("2026-11-12T08:00:00-03:00"))!!,
        ) + ReglasAgenda.AYUDA_ENTRAR +
            ReglasAgenda.avisosLocales(r, f("2026-11-10T09:00:00-03:00"), ar).flatMap { listOf(it.titulo, it.cuerpo) }
        for (t in todos) {
            val l = t.lowercase()
            assertFalse(l.contains("entrega") || l.contains("whatsapp") || l.contains("coach") || l.contains("entrenador"), t)
            // Sin «:» salvo en las horas.
            assertFalse(t.replace(Regex("\\d{2}:\\d{2}"), "").contains(":"), t)
            assertFalse(t.contains(" - ") || t.contains("—"), t)
        }
    }

    @Test
    fun tipoTolerante() {
        val conRevision = a("""{"ok":true,"tipo":"revision","reserva":{"inicio":"2026-11-12T10:00:00-03:00","fin":"2026-11-12T11:00:00-03:00","estado":"confirmada","tipo":"REVISION"}}""")
        assertEquals(TipoVideollamada.REVISION, conRevision.tipo)
        assertEquals(TipoVideollamada.REVISION, conRevision.reserva?.tipo)
        assertEquals(conRevision, AgendaEntrega.desde(conRevision.aValor()))
        assertEquals(TipoVideollamada.COMIENZO, a("""{"ok":true,"tipo":"otra"}""").tipo)
        assertEquals(TipoVideollamada.COMIENZO, a("""{"ok":true}""").tipo)
        assertNull(a("""{"ok":true,"entrar_desde_min":500}""").entrarDesdeMin)
        assertNull(a("""{"ok":true,"entrar_desde_min":0}""").entrarDesdeMin)
        assertEquals(15, a("""{"ok":true,"entrar_desde_min":15}""").entrarDesdeMin)
        assertNull(a("""{"ok":true,"cambio":"si"}""").cambio)
        val c = a("""{"ok":true,"cambio":{"permitido":true,"restantes":-3,"hasta":"2026-11-11T10:00:00-03:00"}}""").cambio
        assertEquals(CambioAgenda(true, 0, f("2026-11-11T10:00:00-03:00")), c)
        assertEquals(CambioAgenda(false), a("""{"ok":true,"cambio":{}}""").cambio)
        assertEquals("Tu videollamada de revisión está agendada", ReglasAgenda.textoConfirmada(conRevision.reserva!!.copy(inicio = null), ar))
    }

    @Test
    fun lasFranjasQuedanConLaReservaSoloSiSePuedeCambiar() {
        val fr = """[{"id":"f9","inicio":"2026-11-13T12:00:00-03:00","fin":"2026-11-13T13:00:00-03:00"}]"""
        val res = """{"id":"r1","inicio":"2026-11-12T10:00:00-03:00","fin":"2026-11-12T11:00:00-03:00","estado":"confirmada","meet_url":"https://meet.google.com/abc"}"""
        // Una 2.2.0: con la reserva vigente no van franjas.
        assertTrue(a("""{"ok":true,"habilitada":true,"franjas":$fr,"reserva":$res}""").franjas.isEmpty())
        assertTrue(a("""{"ok":true,"habilitada":true,"franjas":$fr,"reserva":$res,"cambio":{"permitido":false}}""").franjas.isEmpty())
        assertEquals(1, a("""{"ok":true,"habilitada":true,"franjas":$fr,"reserva":$res,"cambio":{"permitido":true}}""").franjas.size)
        // Pendiente: nunca (no hay nada que cambiar todavía).
        val pend = res.replace("confirmada", "pendiente")
        assertTrue(a("""{"ok":true,"habilitada":true,"franjas":$fr,"reserva":$pend,"cambio":{"permitido":true}}""").franjas.isEmpty())
    }

    @Test
    fun cuentaRegresiva() {
        fun t(ahora: String) = ReglasAgenda.textoCuenta(ReglasAgenda.estadoEntrar(r, f(ahora)))
        assertEquals("Se habilita 10 minutos antes de empezar", t("2026-11-10T09:00:00-03:00"))
        assertEquals("Se habilita en 21 h 50 min", t("2026-11-11T12:00:00-03:00"))
        assertEquals("Se habilita en 2 h", t("2026-11-12T07:50:00-03:00"))
        assertEquals("Se habilita en 25 min", t("2026-11-12T09:25:00-03:00"))
        assertEquals("Se habilita en menos de 1 min", t("2026-11-12T09:49:30-03:00"))
        assertNull(t("2026-11-12T09:50:00-03:00"))
        assertEquals("Se habilita 15 minutos antes de empezar", ReglasAgenda.textoCuenta(ReglasAgenda.estadoEntrar(r, f("2026-11-10T09:00:00-03:00"), 15), 15))
        assertEquals(ReglasAgenda.EstadoEntrar.Nada, ReglasAgenda.estadoEntrar(r, f("2026-11-12T11:00:00-03:00")))
        val sinLink = r.copy(meetUrl = null)
        assertEquals(ReglasAgenda.EstadoEntrar.Preparando, ReglasAgenda.estadoEntrar(sinLink, f("2026-11-12T09:55:00-03:00")))
        assertEquals(ReglasAgenda.TEXTO_PREPARANDO, ReglasAgenda.textoCuenta(ReglasAgenda.EstadoEntrar.Preparando))
        assertEquals("1 h 1 min", ReglasAgenda.cuenta(3601))
    }

    @Test
    fun etiquetaYHoraDeArgentina() {
        assertEquals("Hoy", ReglasAgenda.cuando(r, ar, f("2026-11-12T08:00:00-03:00")))
        assertEquals("Mañana", ReglasAgenda.cuando(r, ar, f("2026-11-11T23:00:00-03:00")))
        assertEquals("En 3 días", ReglasAgenda.cuando(r, ar, f("2026-11-09T23:00:00-03:00")))
        val madrid = ZoneId.of("Europe/Madrid")
        assertEquals("10:00 en Argentina", ReglasAgenda.horaArgentina(r.inicio!!, madrid))
        assertNull(ReglasAgenda.horaArgentina(r.inicio!!, ar))
        assertEquals("Jueves 12 de noviembre, de 14:00 a 15:00", ReglasAgenda.textoConfirmada(r, madrid))
    }

    @Test
    fun tarjetaDesdeQueSeAgendaHastaQueTermina() {
        assertTrue(ReglasAgenda.paraTarjeta(r, f("2026-11-01T10:00:00-03:00")))
        assertTrue(ReglasAgenda.paraTarjeta(r, f("2026-11-12T10:59:00-03:00")))
        assertFalse(ReglasAgenda.paraTarjeta(r, f("2026-11-12T11:00:00-03:00")))
        assertTrue(ReglasAgenda.paraTarjeta(r.copy(estado = ReservaEntrega.Estado.PENDIENTE), f("2026-11-01T10:00:00-03:00")))
        assertFalse(ReglasAgenda.paraTarjeta(r.copy(estado = ReservaEntrega.Estado.FALLO), f("2026-11-01T10:00:00-03:00")))
        assertFalse(ReglasAgenda.paraTarjeta(null, f("2026-11-01T10:00:00-03:00")))
    }

    @Test
    fun avisosUnDiaAntesYAlHabilitarse() {
        val av = ReglasAgenda.avisosLocales(r, f("2026-11-10T09:00:00-03:00"), ar)
        assertEquals(listOf(ReglasAgenda.ID_AVISO_DIA, ReglasAgenda.ID_AVISO_ENTRAR), av.map { it.id })
        assertEquals(f("2026-11-11T10:00:00-03:00"), av[0].fecha)
        assertEquals(f("2026-11-12T09:50:00-03:00"), av[1].fecha)
        assertEquals("Mañana es tu videollamada de comienzo", av[0].titulo)
        assertEquals("Es a las 10:00. Vas a entrar desde la app, en Entreno.", av[0].cuerpo)
        assertEquals("Ya podés entrar a tu videollamada de comienzo", av[1].titulo)
        assertEquals("Abrí la app y tocá Entrar. Mati te admite en la sala.", av[1].cuerpo)
        // Agendada para dentro de unas horas: solo el de entrar. Con 15 del servidor, 15 antes.
        assertEquals(listOf(ReglasAgenda.ID_AVISO_ENTRAR), ReglasAgenda.avisosLocales(r, f("2026-11-12T08:00:00-03:00"), ar).map { it.id })
        assertEquals(f("2026-11-12T09:45:00-03:00"), ReglasAgenda.avisosLocales(r, f("2026-11-12T08:00:00-03:00"), ar, 15).single().fecha)
        assertTrue(ReglasAgenda.avisosLocales(r.copy(estado = ReservaEntrega.Estado.PENDIENTE), f("2026-11-10T09:00:00-03:00"), ar).isEmpty())
        assertTrue(ReglasAgenda.avisosLocales(null, f("2026-11-10T09:00:00-03:00"), ar).isEmpty())
    }

    @Test
    fun cambioConTopeYPlazo() {
        val base = """{"ok":true,"autorizada":true,"habilitada":true,"franjas":[{"id":"f9","inicio":"2026-11-13T12:00:00-03:00","fin":"2026-11-13T13:00:00-03:00"}],"reserva":{"id":"r1","inicio":"2026-11-12T10:00:00-03:00","fin":"2026-11-12T11:00:00-03:00","estado":"confirmada","meet_url":"https://meet.google.com/abc"},"cambio":"""
        val ahora = f("2026-11-10T09:00:00-03:00")
        assertTrue(ReglasAgenda.puedeCambiar(a(base + """{"permitido":true,"restantes":1,"hasta":"2026-11-11T10:00:00-03:00"}}"""), ahora))
        assertFalse(ReglasAgenda.puedeCambiar(a(base + """{"permitido":true,"restantes":0}}"""), ahora))
        assertFalse(ReglasAgenda.puedeCambiar(a(base + """{"permitido":true,"hasta":"2026-11-10T08:00:00-03:00"}}"""), ahora))
        assertFalse(ReglasAgenda.puedeCambiar(a(base + """{"permitido":false}}"""), ahora))
        assertFalse(ReglasAgenda.puedeCambiar(a(base + """{"permitido":true}}"""), f("2026-11-12T10:00:00-03:00")), "ya empezó")
        val c = CambioAgenda(true, 1, f("2026-11-11T10:00:00-03:00"))
        assertEquals("Podés cambiarlo 1 vez, hasta el miércoles 11 a las 10:00.", ReglasAgenda.textoTope(c, ar))
        assertEquals("Podés cambiarlo 2 veces.", ReglasAgenda.textoTope(CambioAgenda(true, 2), ar))
        assertNull(ReglasAgenda.textoTope(CambioAgenda(false, 1), ar))
        assertEquals("Ahora es el jueves 12 a las 10:00.", ReglasAgenda.textoAhoraEs(r, ar))
        assertEquals(ReglasAgenda.TEXTO_SIN_CAMBIO, ReglasAgenda.avisoFallo("tope"))
        assertEquals(ReglasAgenda.TEXTO_SIN_CAMBIO, ReglasAgenda.avisoFallo("plazo"))
    }

    @Test
    fun laPantallaDeElegir() {
        val fs = listOf(
            FranjaEntrega("a", f("2026-11-12T10:00:00-03:00"), f("2026-11-12T11:00:00-03:00")),
            FranjaEntrega("b", f("2026-11-12T12:00:00-03:00"), f("2026-11-12T13:00:00-03:00")),
        )
        assertEquals("Elegí el horario de tu videollamada de comienzo", ReglasAgenda.tituloElegir(TipoVideollamada.COMIENZO))
        assertEquals("Dura alrededor de 1 hora y vas a entrar desde la app.", ReglasAgenda.textoElegirPantalla(fs))
        assertEquals("Vas a entrar desde la app.", ReglasAgenda.textoElegirPantalla(fs + FranjaEntrega("c", f("2026-11-13T10:00:00-03:00"), f("2026-11-13T10:30:00-03:00"))))
        assertEquals("Confirmar jueves 12, 10:00", ReglasAgenda.textoBotonElegir(fs[0], cambiando = false, zona = ar))
        assertEquals("Cambiar al jueves 12, 12:00", ReglasAgenda.textoBotonElegir(fs[1], cambiando = true, zona = ar))
        assertEquals("Elegí el día y el horario. Hay lugar desde el jueves 12.", ReglasAgenda.textoAgendar(fs.reversed(), ar))
    }
}
