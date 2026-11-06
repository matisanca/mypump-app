package com.pumpteam.mypump.reglas

import com.pumpteam.mypump.modelos.AgendaEntrega
import com.pumpteam.mypump.modelos.Guia
import com.pumpteam.mypump.modelos.ReservaEntrega
import com.pumpteam.mypump.modelos.ResumenGuia
import java.time.Instant
import java.time.ZoneId
import kotlinx.serialization.json.Json
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/** La novedad, los obligatorios y la agenda de la entrega (2.2.0, ~/Desktop/Entregas-v2/app/spec.md §5, el kit). */
class AgendaReglasTest {
    private fun j(s: String) = Json.parseToJsonElement(s)

    private fun clip(id: String, bloque: String = "Tu entrenamiento", visto: Boolean = false, extra: String = "", url: String? = "https://x.invalid/$id.mp4", min: Double = 1.0) =
        """{"id":"$id","titulo":"T $id","url":${url?.let { "\"$it\"" } ?: "null"},"minutos":$min,"bloque":"$bloque","visto":$visto$extra}"""

    private fun guia(vararg clips: String, raiz: String = "") = Guia.desde(j("""{"ok":true$raiz,"clips":[${clips.joinToString(",")}]}"""))!!

    // ── La novedad ──

    @Test
    fun sinNuevosElOrdenYLosCapitulosSonLosDeSiempre() {
        val g = guia(clip("a", "Tu entrenamiento"), clip("b", "Tu app"), clip("c", "Tu dieta"))
        assertEquals(ReglasGuia.ordenados(g.clipsDeLaLista), ReglasNovedad.ordenDeLaLista(g.clipsDeLaLista))
        assertEquals(ReglasGuia.bloques(ReglasGuia.ordenados(g.clipsDeLaLista)), ReglasNovedad.bloques(ReglasNovedad.ordenDeLaLista(g.clipsDeLaLista)))
        assertEquals(1, g.fase)
        assertNull(g.novedadEn)
        // La caché de una guía sin los campos nuevos no los suma.
        assertFalse(g.aValor().aJson().toString().contains("nuevo"))
    }

    @Test
    fun losNuevosVanArribaEnNovedadYElRestoDebajo() {
        val g = guia(
            clip("a", "Tu entrenamiento", visto = true), clip("b", "Tu app", visto = true),
            clip("n1", "Tu dieta", extra = ""","nuevo":true""", min = 4.0), clip("c", "Tu dieta"),
            clip("n2", "Tu entrenamiento", extra = ""","nuevo":true""", min = 4.6),
            raiz = ""","fase":2,"novedad_en":"2026-11-05T12:00:00-03:00"""",
        )
        assertEquals(2, g.fase)
        val orden = ReglasNovedad.ordenDeLaLista(g.clipsDeLaLista)
        assertEquals(listOf("n1", "n2", "b", "a", "c"), orden.map { it.id })
        val bloques = ReglasNovedad.bloques(orden)
        assertEquals(listOf("Novedad", "Tu app", "Tu entrenamiento", "Tu dieta"), bloques.map { it.titulo })
        assertTrue(bloques[0].esNovedad)
        assertEquals(listOf(0, 1), bloques[0].indices)
        assertEquals("2 videos nuevos para vos · 9 min", bloques[0].resumen)
        // Los capítulos de siempre, solo con los que no son nuevos (y sus índices sobre el orden entero).
        assertEquals(listOf(3), bloques[2].indices)
        assertEquals(listOf(4), bloques[3].indices)
        assertEquals(ReglasNovedad.CLAVE_NOVEDAD, bloques[0].clave)
        // Va y vuelve de la caché igual.
        assertEquals(g, Guia.desde(g.aValor()))
    }

    @Test
    fun unCapituloQueSeLlamaNovedadNoChocaConElBloque() {
        val g = guia(clip("n", "X", extra = ""","nuevo":true"""), clip("a", "Novedad"))
        val b = ReglasNovedad.bloques(ReglasNovedad.ordenDeLaLista(g.clipsDeLaLista))
        assertEquals(2, b.size)
        assertTrue(b[0].clave != b[1].clave)
    }

    @Test
    fun laTarjetaConNovedadCuentaSoloLosNuevos() {
        val en = "2026-11-05T12:00:00-03:00"
        val g = guia(
            clip("a", visto = true), clip("n1", extra = ""","nuevo":true""", visto = true, min = 2.0),
            clip("n2", extra = ""","nuevo":true""", min = 3.0), raiz = ""","novedad_en":"$en"""",
        )
        val r = ResumenGuia(3, 2, 3.0, novedadEn = en)
        val t = ReglasNovedad.tarjeta(r, g)!!
        assertEquals(2, t.total)
        assertEquals(1, t.vistos)
        assertEquals("1 de 2 videos nuevos, te quedan 3 min", ReglasNovedad.textoTarjeta(t))
        assertEquals(0.5f, t.fraccion)
        // Sin `novedad_en`: la tarjeta de la 2.1.0.
        assertNull(ReglasNovedad.tarjeta(r.copy(novedadEn = null), g))
        // Con los nuevos vistos, no hay novedad (y la compacta sale si vio todo).
        val todo = guia(clip("a", visto = true), clip("n1", extra = ""","nuevo":true""", visto = true), raiz = ""","novedad_en":"$en"""")
        assertNull(ReglasNovedad.tarjeta(ResumenGuia(2, 2, 0.0, novedadEn = en), todo))
        // La guía guardada es de otra tanda: novedad mientras quede algo sin ver, sin saber cuáles.
        val vieja = guia(clip("a", visto = true))
        val sinSaber = ReglasNovedad.tarjeta(ResumenGuia(3, 1, 4.0, novedadEn = en), vieja)!!
        assertNull(sinSaber.total)
        assertEquals("Hay videos nuevos para vos", ReglasNovedad.textoTarjeta(sinSaber))
        assertNull(ReglasNovedad.tarjeta(ResumenGuia(3, 3, 0.0, novedadEn = en), vieja))
        // Con `nuevos_total` y `nuevos_vistos` del resumen.
        val delServidor = ReglasNovedad.tarjeta(ResumenGuia(5, 3, 4.0, novedadEn = en, nuevosTotal = 3, nuevosVistos = 1), vieja)!!
        assertEquals(3, delServidor.total)
        assertEquals("1 de 3 videos nuevos", ReglasNovedad.textoTarjeta(delServidor))
        assertNull(ReglasNovedad.tarjeta(ResumenGuia(5, 3, 4.0, novedadEn = en, nuevosTotal = 3, nuevosVistos = 3), vieja))
    }

    @Test
    fun reapareceDespuesDeOcultarConFechas() {
        val novedad = "2026-11-05T12:00:00-03:00"
        // Ocultada antes de la novedad: vuelve.
        assertTrue(ReglasNovedad.reaparece(novedad, "2026-11-04T10:00:00Z"))
        assertFalse(ReglasNovedad.ocultaEfectiva(true, "2026-11-04T10:00:00Z", novedad))
        // Ocultada de nuevo después: queda oculta.
        assertFalse(ReglasNovedad.reaparece(novedad, "2026-11-05T16:00:00Z"))
        assertTrue(ReglasNovedad.ocultaEfectiva(true, "2026-11-05T16:00:00Z", novedad))
        // La marca de la 2.1.0 (sin fecha) es de antes de cualquier novedad.
        assertTrue(ReglasNovedad.reaparece(novedad, null))
        // Sin novedad, o una que no se entiende, la marca vale tal cual.
        assertTrue(ReglasNovedad.ocultaEfectiva(true, null, null))
        assertTrue(ReglasNovedad.ocultaEfectiva(true, null, "ayer"))
        assertFalse(ReglasNovedad.ocultaEfectiva(false, null, novedad))
    }

    // ── Los obligatorios ──

    @Test
    fun obligatoriosConElCampo() {
        val g = guia(
            clip("a", extra = ""","obligatorio":true""", visto = true), clip("b", extra = ""","obligatorio":true"""),
            clip("c", extra = ""","obligatorio":false"""), clip("d"), clip("e", extra = ""","obligatorio":true""", url = null),
        )
        assertEquals(listOf("a", "b", "e"), ReglasAgenda.obligatorios(g).map { it.id })
        assertEquals(2, ReglasAgenda.faltan(g))
        // El próximo que falta se puede ver (el que se está subiendo no).
        assertEquals("b", ReglasAgenda.proximoQueFalta(g, ReglasNovedad.ordenDeLaLista(g.clipsDeLaLista))?.id)
    }

    @Test
    fun obligatoriosSinElCampoSonTodosLosQueSePuedenVer() {
        val g = guia(clip("a", visto = true), clip("b"), clip("c", url = null))
        assertEquals(listOf("a", "b"), ReglasAgenda.obligatorios(g).map { it.id })
        assertEquals(1, ReglasAgenda.faltan(g))
    }

    @Test
    fun lasDeSuplementacionNoCuentanComoElResumen() {
        val g = Guia.desde(
            j(
                """{"ok":true,"clips":[${clip("a", extra = ""","obligatorio":true""")},${clip("s", "Tu suplementación", extra = ""","obligatorio":true""")}],
                "suplementacion":{"items":[{"nombre":"Creatina","momento":"desayuno","video_id":"s"}]}}""",
            ),
        )!!
        assertEquals(listOf("a"), ReglasAgenda.obligatorios(g).map { it.id })
    }

    @Test
    fun faltanAMostrarEsElDelServidorSiVino() {
        val g = guia(clip("a"), clip("b"))
        val a = AgendaEntrega.desde(j("""{"ok":true,"habilitada":false,"autorizada":true,"faltan":1}"""))
        assertEquals(1, ReglasAgenda.faltanAMostrar(a, g))
        assertEquals(2, ReglasAgenda.faltanAMostrar(a!!.copy(faltan = null), g))
        assertEquals(2, ReglasAgenda.faltanAMostrar(null, g))
        assertEquals(0, ReglasAgenda.faltanAMostrar(null, null))
        assertEquals("Te faltan 2 videos para habilitar la agenda", ReglasAgenda.textoContador(2))
        assertEquals("Te falta 1 video para habilitar la agenda", ReglasAgenda.textoContador(1))
    }

    // ── La agenda: decodificar y sus estados ──

    private val franjas = """[
        {"id":"f2","inicio":"2026-11-12T14:00:00-03:00","fin":"2026-11-12T16:00:00-03:00"},
        {"id":"f1","inicio":"2026-11-12T10:00:00-03:00","fin":"2026-11-12T12:00:00-03:00"},
        {"id":"f3","inicio":"2026-11-13 13:00:00+00","otro":1},
        {"inicio":"2026-11-14T10:00:00-03:00"},
        {"id":"rota","inicio":"mañana"}
    ]"""

    @Test
    fun decodificaLaAgendaConCamposDeMasYDeMenos() {
        val a = AgendaEntrega.desde(j("""{"ok":true,"habilitada":true,"autorizada":true,"faltan":0,"zona":"America/Argentina/Buenos_Aires","franjas":$franjas,"reserva":null,"nuevo_campo":[1,2]}"""))!!
        assertEquals(listOf("f1", "f2", "f3"), a.franjas.map { it.id })
        // Sin fin, las 2 h; con la hora de Postgres.
        assertEquals(Instant.parse("2026-11-13T15:00:00Z"), a.franjas[2].fin)
        assertTrue(a.puedeAgendar)
        assertNull(a.reserva)
        assertEquals(a, AgendaEntrega.desde(a.aValor()))
        // ok false, nada, o una forma rota: no hay agenda.
        assertNull(AgendaEntrega.desde(j("""{"ok":false,"motivo":"sin_guia"}""")))
        assertNull(AgendaEntrega.desde(j("""{"ok":false,"motivo":"token"}""")))
        assertNull(AgendaEntrega.desde(j("[]")))
        assertNull(AgendaEntrega.desde(j("null")))
        // Solo `ok`: todo por defecto, y `autorizada` que falta es false.
        val minima = AgendaEntrega.desde(j("""{"ok":true}"""))!!
        assertFalse(minima.habilitada)
        assertFalse(minima.autorizada)
        assertNull(minima.faltan)
        assertTrue(minima.franjas.isEmpty())
        // Habilitada pero sin `autorizada` (servidor viejo): no se agenda.
        assertFalse(AgendaEntrega.desde(j("""{"ok":true,"habilitada":true,"franjas":$franjas}"""))!!.puedeAgendar)
    }

    @Test
    fun decodificaLaReservaEnTodosSusEstados() {
        val base = """"id":"r","inicio":"2026-11-12T10:00:00-03:00","fin":"2026-11-12T12:00:00-03:00""""
        val pend = ReservaEntrega.desde(j("""{$base,"estado":"pendiente","meet_url":null,"motivo":null}"""))!!
        assertEquals(ReservaEntrega.Estado.PENDIENTE, pend.estado)
        assertTrue(pend.vigente)
        val conf = ReservaEntrega.desde(j("""{$base,"estado":"Confirmada","meet_url":"https://meet.google.com/abc-defg-hij","extra":true}"""))!!
        assertEquals(ReservaEntrega.Estado.CONFIRMADA, conf.estado)
        assertEquals("https://meet.google.com/abc-defg-hij", conf.meetUrl)
        // Un link que no es https no se abre.
        assertNull(ReservaEntrega.desde(j("""{$base,"estado":"confirmada","meet_url":"javascript:alert(1)"}"""))!!.meetUrl)
        val fallo = ReservaEntrega.desde(j("""{$base,"estado":"fallo","motivo":"tomada"}"""))!!
        assertFalse(fallo.vigente)
        assertEquals("tomada", fallo.motivo)
        // Un estado que no se conoce no se muestra; sin horas, se tolera.
        assertNull(ReservaEntrega.desde(j("""{$base,"estado":"cancelada"}""")))
        assertNull(ReservaEntrega.desde(j("""{"id":"r"}""")))
        assertNull(ReservaEntrega.desde(j("\"pendiente\"")))
        assertNull(ReservaEntrega.desde(j("""{"estado":"confirmada"}"""))!!.inicio)
        // Con una reserva vigente no hay franjas, aunque vengan.
        val a = AgendaEntrega.desde(j("""{"ok":true,"habilitada":true,"autorizada":true,"franjas":$franjas,"reserva":{$base,"estado":"pendiente"}}"""))!!
        assertTrue(a.franjas.isEmpty())
        // Con una que falló, las franjas de nuevo.
        val b = AgendaEntrega.desde(j("""{"ok":true,"habilitada":true,"autorizada":true,"franjas":$franjas,"reserva":{$base,"estado":"fallo","motivo":"vencida"}}"""))!!
        assertEquals(3, b.franjas.size)
        assertEquals(ReglasAgenda.Vista.ELEGIR, ReglasAgenda.vista(b, 0, reservando = false))
        // El resumen trae la reserva para la tarjeta de Entreno (sin id ni motivo).
        val r = ResumenGuia.desde(j("""{"ok":true,"total":3,"vistos":3,"minutos_restantes":0,"reserva":{"inicio":"2026-11-12T10:00:00-03:00","fin":"2026-11-12T12:00:00-03:00","estado":"confirmada","meet_url":"https://meet.google.com/x"}}"""))!!
        assertEquals(ReservaEntrega.Estado.CONFIRMADA, r.reserva?.estado)
        assertEquals(r, ResumenGuia.desde(r.aValor()))
        // Un resumen sin los campos nuevos queda igual que en la 2.1.0.
        val viejo = ResumenGuia.desde(j("""{"ok":true,"total":3,"vistos":1,"minutos_restantes":2}"""))!!
        assertEquals(ResumenGuia(3, 1, 2.0), viejo)
    }

    @Test
    fun laVistaDeLaAgenda() {
        fun a(s: String) = AgendaEntrega.desde(j("""{"ok":true$s}"""))!!
        val r = """"inicio":"2026-11-12T10:00:00-03:00","fin":"2026-11-12T12:00:00-03:00""""
        assertEquals(ReglasAgenda.Vista.NO_AUTORIZADA, ReglasAgenda.vista(a(""","habilitada":false,"autorizada":false,"faltan":2"""), 2, false))
        // Sin `autorizada` (servidor viejo), también.
        assertEquals(ReglasAgenda.Vista.NO_AUTORIZADA, ReglasAgenda.vista(a(""","habilitada":true,"franjas":$franjas"""), 0, false))
        assertEquals(ReglasAgenda.Vista.BLOQUEADA, ReglasAgenda.vista(a(""","habilitada":false,"autorizada":true,"faltan":2"""), 2, false))
        assertEquals(ReglasAgenda.Vista.HABILITANDO, ReglasAgenda.vista(a(""","habilitada":false,"autorizada":true"""), 0, false))
        assertEquals(ReglasAgenda.Vista.SIN_FRANJAS, ReglasAgenda.vista(a(""","habilitada":true,"autorizada":true,"franjas":[]"""), 0, false))
        assertEquals(ReglasAgenda.Vista.ELEGIR, ReglasAgenda.vista(a(""","habilitada":true,"autorizada":true,"franjas":$franjas"""), 0, false))
        assertEquals(ReglasAgenda.Vista.PENDIENTE, ReglasAgenda.vista(a(""","habilitada":true,"autorizada":true,"franjas":$franjas"""), 0, true))
        assertEquals(ReglasAgenda.Vista.PENDIENTE, ReglasAgenda.vista(a(""","habilitada":true,"autorizada":true,"reserva":{$r,"estado":"pendiente"}"""), 0, false))
        assertEquals(ReglasAgenda.Vista.CONFIRMADA, ReglasAgenda.vista(a(""","habilitada":true,"autorizada":true,"reserva":{$r,"estado":"confirmada"}"""), 0, true))
        assertEquals("Cuando termines los videos de arriba se habilita la agenda. Te faltan 2.", ReglasAgenda.textoBloqueada(2))
        assertEquals("Cuando termines de ver todo te habilitamos la agenda.", ReglasAgenda.TEXTO_NO_AUTORIZADA)
        // Los fallos: `tomada` con su texto; `vencida` y cualquier otro, el de siempre.
        assertEquals("Ese horario se ocupó recién, elegí otro.", ReglasAgenda.avisoFallo("tomada"))
        assertEquals("No pudimos reservar ese horario, elegí otro.", ReglasAgenda.avisoFallo("vencida"))
        assertEquals("No pudimos reservar ese horario, elegí otro.", ReglasAgenda.avisoFallo("otro_que_no_se_conoce"))
        assertEquals("No pudimos reservar ese horario, elegí otro.", ReglasAgenda.avisoFallo(null))
    }

    // ── La zona horaria ──

    @Test
    fun laHoraVaEnLaZonaDelTelefono() {
        val a = AgendaEntrega.desde(j("""{"ok":true,"habilitada":true,"autorizada":true,"franjas":$franjas}"""))!!
        val ar = ReglasAgenda.ARGENTINA
        val madrid = ZoneId.of("Europe/Madrid")
        val mexico = ZoneId.of("America/Mexico_City")
        val f1 = a.franjas[0]
        assertEquals("10:00 a 12:00", ReglasAgenda.rango(f1.inicio, f1.fin, ar))
        assertEquals("14:00 a 16:00", ReglasAgenda.rango(f1.inicio, f1.fin, madrid))
        assertEquals("07:00 a 09:00", ReglasAgenda.rango(f1.inicio, f1.fin, mexico))
        assertEquals("jueves 12 de noviembre", ReglasAgenda.dia(f1.inicio, ar))
        assertFalse(ReglasAgenda.difiereDeArgentina(ar, a.franjas.map { it.inicio }))
        assertFalse(ReglasAgenda.difiereDeArgentina(ZoneId.of("America/Sao_Paulo"), a.franjas.map { it.inicio }))
        assertTrue(ReglasAgenda.difiereDeArgentina(madrid, a.franjas.map { it.inicio }))
        assertTrue(ReglasAgenda.difiereDeArgentina(mexico, a.franjas.map { it.inicio }))
        assertEquals("¿Confirmás la entrega el jueves 12 a las 10:00? Dura unas 2 horas.", ReglasAgenda.textoConfirmar(f1, ar))
        assertEquals("¿Confirmás la entrega el jueves 12 a las 14:00? Dura unas 2 horas.", ReglasAgenda.textoConfirmar(f1, madrid))
        // Por día del teléfono: en Tokio las de la tarde de Argentina ya son del viernes.
        val tokio = ReglasAgenda.porDia(a.franjas, ZoneId.of("Asia/Tokyo"))
        assertEquals(listOf("jueves 12 de noviembre", "viernes 13 de noviembre"), tokio.map { it.first })
        assertEquals(listOf(listOf("f1"), listOf("f2", "f3")), tokio.map { d -> d.second.map { it.id } })
        assertEquals(listOf(2, 1), ReglasAgenda.porDia(a.franjas, ar).map { it.second.size })
        val conf = ReservaEntrega(null, f1.inicio, f1.fin, ReservaEntrega.Estado.CONFIRMADA, "https://meet.google.com/x", null)
        assertEquals("Tu entrega: jueves 12 de noviembre, 10:00 a 12:00", ReglasAgenda.textoConfirmada(conf, ar))
        assertEquals("Tu entrega: jueves 12 de noviembre, 07:00 a 09:00", ReglasAgenda.textoConfirmada(conf, mexico))
    }

    @Test
    fun entrarDesde30MinutosAntesHastaElFin() {
        val i = Instant.parse("2026-11-12T13:00:00Z")
        val r = ReservaEntrega("r", i, i.plusSeconds(7200), ReservaEntrega.Estado.CONFIRMADA, "https://meet.google.com/x", null)
        assertFalse(ReglasAgenda.puedeEntrar(r, i.minusSeconds(31 * 60)))
        assertTrue(ReglasAgenda.puedeEntrar(r, i.minusSeconds(30 * 60)))
        assertTrue(ReglasAgenda.puedeEntrar(r, i.plusSeconds(7199)))
        assertFalse(ReglasAgenda.puedeEntrar(r, i.plusSeconds(7200)))
        assertFalse(ReglasAgenda.puedeEntrar(r.copy(meetUrl = null), i))
        assertFalse(ReglasAgenda.puedeEntrar(r.copy(estado = ReservaEntrega.Estado.PENDIENTE), i))
        assertEquals("Tu entrega empieza a las 10:00", ReglasAgenda.textoEmpieza(r, ReglasAgenda.ARGENTINA, i.minusSeconds(600)))
        assertNotNull(ReglasAgenda.textoEmpieza(r, ReglasAgenda.ARGENTINA, i.plusSeconds(60)))
    }
}
