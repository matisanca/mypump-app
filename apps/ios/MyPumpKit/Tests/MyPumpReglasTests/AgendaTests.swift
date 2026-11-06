import Foundation
import Testing
import MyPumpModelos
@testable import MyPumpReglas

private func json(_ s: String) -> JSONValue { (try? JSONDecoder().decode(JSONValue.self, from: Data(s.utf8))) ?? .null }
private func agenda(_ s: String) -> AgendaGuia { AgendaGuia(json: json(s)) }
private func resumen(_ s: String) -> ResumenGuia { ResumenGuia(json: json(s)) }
private func fecha(_ s: String) -> Date { ReglasGuia.instante(s)! }

@Suite("Tu guía v2: novedad (2.2.0)")
struct NovedadTests {
    @Test func losNuevosVanPrimeroEnSuBloque() {
        let g = GuiaMuestra.guiaV2
        #expect(g.fase == 2 && g.novedadEn == "2026-11-05T12:00:00-03:00")
        let l = ReglasGuia.deLaLista(g)
        #expect(l.map(\.id) == ["N-1", "N-2", "FT-25a", "FT-2b", "MC-7a", "FT-26a"], "los nuevos en su orden, después lo de siempre")
        let b = ReglasGuia.bloques(l)
        #expect(b.first?.novedad == true && b.first?.titulo == "Novedad" && b.first?.indices == [0, 1])
        #expect(b.first?.id == ReglasGuia.idNovedad && b.first?.esApp == false)
        #expect(ReglasGuia.textoBloque(b[0]) == "2 videos nuevos para vos · 1 min")
        // Debajo, los capítulos de siempre solo con los que no son nuevos.
        #expect(b.dropFirst().allSatisfy { !$0.novedad && $0.indices.allSatisfy { !l[$0].nuevo } })
        #expect(b.filter { $0.titulo == "Tu alimentación" }.first?.indices == [5], "N-2 no se repite en su capítulo")
        #expect(ReglasGuia.claveBloque(l[0]) == ReglasGuia.idNovedad && ReglasGuia.claveBloque(l[2]) == "Tu app")
    }

    @Test func sinNuevosElOrdenDeLa210() {
        let g = GuiaMuestra.guia
        #expect(g.fase == 1 && g.novedadEn == nil && g.clips.allSatisfy { !$0.nuevo && $0.obligatorio == nil })
        let l = ReglasGuia.deLaLista(g)
        #expect(l.first?.id == "FT-25a")
        #expect(ReglasGuia.bloques(l).allSatisfy { !$0.novedad })
        #expect(ReglasGuia.textoBloque(ReglasGuia.bloques(l)[0]) == "5 videos, unos 3 minutos")
    }

    @Test func unBloqueDelServidorLlamadoNovedadNoChoca() {
        let g = Guia(json: json(#"{"ok":true,"clips":[{"id":"a","titulo":"A","url":"https://x.invalid/a.mp4","minutos":1,"bloque":"Novedad","nuevo":false},{"id":"b","titulo":"B","url":"https://x.invalid/b.mp4","minutos":2,"nuevo":true}]}"#))
        let b = ReglasGuia.bloques(ReglasGuia.deLaLista(g))
        #expect(b.count == 2 && Set(b.map(\.id)).count == 2)
        #expect(ReglasGuia.textoBloque(b[0]) == "1 video nuevo para vos · 2 min")
    }

    @Test func laTarjetaCuentaSoloLosNuevos() {
        let g = GuiaMuestra.guiaV2
        let a = ReglasGuia.avanceNovedad(nil, guia: g)
        #expect(a == ReglasGuia.Avance(total: 2, vistos: 1, minutosRestantes: 0.4))
        #expect(ReglasGuia.textoTarjetaNovedad(a!) == "1 de 2 videos nuevos, te queda 1 min")
        #expect(ReglasGuia.textoTarjetaNovedad(.init(total: 3, vistos: 0, minutosRestantes: 9)) == "3 videos nuevos, unos 9 min")
        // Con todo lo nuevo visto, la de la 2.1.0.
        var vista = g
        for i in vista.clips.indices { vista.clips[i].visto = true }
        #expect(ReglasGuia.avanceNovedad(nil, guia: vista) == nil)
        // Sin `novedad_en` (servidor viejo), la de la 2.1.0 aunque haya `nuevo`.
        var sin = g
        sin.novedadEn = nil
        #expect(ReglasGuia.avanceNovedad(nil, guia: sin) == nil)
    }

    @Test func elResumenConNuevosTotalManda() {
        let r = resumen(#"{"ok":true,"total":6,"vistos":4,"minutos_restantes":1.0,"novedad_en":"2026-11-05T12:00:00-03:00","nuevos_total":3,"nuevos_vistos":1}"#)
        #expect(r.nuevosTotal == 3 && r.nuevosVistos == 1)
        let a = ReglasGuia.avanceNovedad(r, guia: GuiaMuestra.guiaV2)
        #expect(a?.total == 3 && a?.vistos == 1 && a?.minutosRestantes == 0.4, "los minutos, de la copia al día")
        // Sin copia: los minutos del resumen.
        #expect(ReglasGuia.avanceNovedad(r, guia: nil) == ReglasGuia.Avance(total: 3, vistos: 1, minutosRestantes: 1.0))
        let completo = resumen(#"{"ok":true,"total":6,"vistos":6,"novedad_en":"2026-11-05T12:00:00-03:00","nuevos_total":3,"nuevos_vistos":3}"#)
        #expect(ReglasGuia.avanceNovedad(completo, guia: nil) == nil)
        // nuevos_vistos de más se recorta; sin nuevos_total, no hay nuevos_vistos.
        #expect(resumen(#"{"ok":true,"nuevos_total":2,"nuevos_vistos":9}"#).nuevosVistos == 2)
        #expect(resumen(#"{"ok":true,"nuevos_vistos":1}"#).nuevosVistos == nil)
    }

    @Test func conLaCopiaViejaCuentaConElResumen() {
        // La copia es de antes de la tanda (la tarjeta nunca pide el get): mientras falte algo, NOVEDAD con el resumen.
        let r = resumen(#"{"ok":true,"total":13,"vistos":11,"minutos_restantes":2.5,"novedad_en":"2026-11-05T12:00:00-03:00"}"#)
        #expect(ReglasGuia.avanceNovedad(r, guia: GuiaMuestra.guia) == ReglasGuia.Avance(total: 13, vistos: 11, minutosRestantes: 2.5))
        // La copia al día y sin nuevos: nada.
        var g = GuiaMuestra.guia
        g.novedadEn = "2026-11-05T12:00:00-03:00"
        #expect(ReglasGuia.avanceNovedad(r, guia: g) == nil)
    }

    @Test func reapareceDespuesDeOcultarSiHayNovedadPosterior() {
        let marca = fecha("2026-11-04T18:00:00-03:00")
        // Sin novedad: la 2.1.0 tal cual.
        #expect(ReglasGuia.quitadaVigente(quitada: true, marca: marca, novedadEn: nil))
        #expect(!ReglasGuia.quitadaVigente(quitada: false, marca: nil, novedadEn: "2026-11-05T12:00:00-03:00"))
        // Novedad posterior a la marca: vuelve.
        #expect(!ReglasGuia.quitadaVigente(quitada: true, marca: marca, novedadEn: "2026-11-05T12:00:00-03:00"))
        // Novedad anterior (o la misma): sigue oculta.
        #expect(ReglasGuia.quitadaVigente(quitada: true, marca: marca, novedadEn: "2026-11-03T12:00:00-03:00"))
        #expect(ReglasGuia.quitadaVigente(quitada: true, marca: marca, novedadEn: "2026-11-04 21:00:00+00"))
        // Ocultar de nuevo guarda la fecha actual: la misma novedad ya no la trae de vuelta.
        #expect(ReglasGuia.quitadaVigente(quitada: true, marca: fecha("2026-11-06T09:00:00-03:00"), novedadEn: "2026-11-05T12:00:00-03:00"))
        // Una marca de la 2.1.0 (sin fecha) con novedad: vuelve. Una novedad que no se entiende: no cambia nada.
        #expect(!ReglasGuia.quitadaVigente(quitada: true, marca: nil, novedadEn: "2026-11-05T12:00:00-03:00"))
        #expect(ReglasGuia.quitadaVigente(quitada: true, marca: nil, novedadEn: "ayer"))
    }
}

@Suite("Videos obligatorios (2.2.0)")
struct ObligatoriosTests {
    @Test func conElCampoCuentanLosMarcados() {
        let g = GuiaMuestra.guiaV2
        #expect(ReglasAgenda.obligatorios(g).map(\.id) == ["N-1", "N-2", "FT-25a", "FT-2b", "MC-7a"])
        #expect(ReglasAgenda.faltan(g) == 1)
        #expect(ReglasAgenda.primeroQueFalta(g)?.id == "N-1")
        #expect(!ReglasAgenda.esObligatorio(g.clips.first { $0.id == "FT-26a" }!, en: g))
        var todo = g
        for i in todo.clips.indices where todo.clips[i].id == "N-1" { todo.clips[i].visto = true }
        #expect(ReglasAgenda.faltan(todo) == 0 && ReglasAgenda.primeroQueFalta(todo) == nil)
    }

    @Test func sinElCampoCuentanTodosLosQueTienenUrl() {
        // Ningún clip trae `obligatorio` (servidor viejo): los de la lista con url (sin los de los suplementos ni el que se
        // está subiendo).
        let g = GuiaMuestra.guia
        let o = ReglasAgenda.obligatorios(g)
        #expect(o.count == 10 && !o.contains { $0.id == "FT-5a" || $0.id == "FT-1b" || $0.id == "FT-4b" })
        #expect(ReglasAgenda.faltan(g) == 6)
        #expect(ReglasAgenda.primeroQueFalta(g)?.id == "FT-2a")
        #expect(ReglasAgenda.textoContador(6) == "Te faltan 6 videos para habilitar la agenda")
        #expect(ReglasAgenda.textoContador(1) == "Te falta 1 video para habilitar la agenda")
        #expect(ReglasAgenda.textoBloqueada(1) == "Cuando termines los videos de arriba se habilita la agenda. Te falta 1.")
    }

    @Test func conUnoSoloConElCampoLosDemasNoCuentan() {
        let g = Guia(json: json(#"{"ok":true,"clips":[{"id":"a","titulo":"A","url":"https://x.invalid/a.mp4","minutos":1,"obligatorio":true},{"id":"b","titulo":"B","url":"https://x.invalid/b.mp4","minutos":1}]}"#))
        #expect(ReglasAgenda.obligatorios(g).map(\.id) == ["a"])
        #expect(ReglasAgenda.faltan(nil) == 0)
    }

    @Test func elCampoTolerante() {
        let g = Guia(json: json(#"{"ok":true,"fase":"2","novedad_en":"  ","clips":[{"id":"a","titulo":"A","minutos":1,"nuevo":1,"obligatorio":"true"},{"id":"b","titulo":"B","minutos":1,"nuevo":null,"obligatorio":0}]}"#))
        #expect(g.fase == 2 && g.novedadEn == nil)
        #expect(g.clips[0].nuevo && g.clips[0].obligatorio == true)
        #expect(!g.clips[1].nuevo && g.clips[1].obligatorio == false)
        #expect(Guia(json: json(#"{"ok":true,"fase":7,"clips":[]}"#)).fase == 1)
    }
}

@Suite("Agenda de la entrega: decodificar (2.2.0)")
struct AgendaDecodificarTests {
    @Test func completaHabilitada() {
        let a = agenda(#"""
        {"ok":true,"autorizada":true,"habilitada":true,"faltan":0,"zona":"America/Argentina/Buenos_Aires","extra":{"x":1},
         "franjas":[{"id":"f1","inicio":"2026-11-12T10:00:00-03:00","fin":"2026-11-12T12:00:00-03:00","coach":"no importa"},
                    {"id":"f2","inicio":"2026-11-12T14:00:00-03:00","fin":"2026-11-12T16:00:00-03:00"},
                    {"id":"","inicio":"2026-11-13T10:00:00-03:00","fin":"2026-11-13T12:00:00-03:00"},
                    {"id":"f3","inicio":null,"fin":"x"}, null, 7,
                    {"id":"f1","inicio":"2026-11-14T10:00:00-03:00","fin":"2026-11-14T12:00:00-03:00"}],
         "reserva":null}
        """#)
        #expect(a.ok && a.autorizada && a.habilitada && a.faltan == 0 && a.zona == "America/Argentina/Buenos_Aires")
        #expect(a.franjas.map(\.id) == ["f1", "f2"], "las rotas y las repetidas no van")
        #expect(a.reserva == nil)
    }

    @Test func okFalseNullYCosasRaras() {
        #expect(!agenda(#"{"ok":false,"motivo":"token"}"#).ok)
        #expect(agenda(#"{"ok":false,"motivo":"sin_guia"}"#).motivo == "sin_guia")
        #expect(!AgendaGuia(json: .null).ok)
        #expect(!AgendaGuia(json: .bool(false)).ok)
        #expect(!AgendaGuia(json: .lista([])).ok)
        #expect(!agenda(#"{"habilitada":true}"#).ok, "sin ok no hay agenda")
    }

    @Test func sinAutorizadaNoHayHabilitadaNiFranjas() {
        // Servidor sin el punto de control: `autorizada` falta, se toma como false.
        let a = agenda(#"{"ok":true,"habilitada":true,"faltan":"2","franjas":[{"id":"f1","inicio":"2026-11-12T10:00:00-03:00","fin":"2026-11-12T12:00:00-03:00"}]}"#)
        #expect(a.ok && !a.autorizada && !a.habilitada && a.franjas.isEmpty && a.faltan == 2)
        let b = agenda(#"{"ok":true,"autorizada":true,"habilitada":false,"faltan":-3,"franjas":[{"id":"f1","inicio":"2026-11-12T10:00:00-03:00","fin":"2026-11-12T12:00:00-03:00"}]}"#)
        #expect(b.autorizada && !b.habilitada && b.franjas.isEmpty && b.faltan == 0)
    }

    @Test func reservaEnTodosSusEstados() {
        let p = agenda(#"{"ok":true,"autorizada":true,"habilitada":true,"franjas":[{"id":"f1","inicio":"2026-11-12T10:00:00-03:00","fin":"2026-11-12T12:00:00-03:00"}],"reserva":{"id":"r1","inicio":"2026-11-12T10:00:00-03:00","fin":"2026-11-12T12:00:00-03:00","estado":"pendiente","meet_url":null,"motivo":null}}"#)
        #expect(p.reserva?.estado == .pendiente && p.reserva?.id == "r1" && p.reserva?.meetUrl == nil)
        #expect(p.franjas.isEmpty, "con la reserva vigente no van franjas")
        let c = agenda(#"{"ok":true,"autorizada":true,"habilitada":true,"reserva":{"id":"r1","inicio":"2026-11-12T10:00:00-03:00","fin":"2026-11-12T12:00:00-03:00","estado":"CONFIRMADA","meet_url":" https://meet.google.com/abc-defg-hij "}}"#)
        #expect(c.reserva?.estado == .confirmada && c.reserva?.meetUrl?.absoluteString == "https://meet.google.com/abc-defg-hij")
        let f = agenda(#"{"ok":true,"autorizada":true,"habilitada":true,"franjas":[{"id":"f2","inicio":"2026-11-12T14:00:00-03:00","fin":"2026-11-12T16:00:00-03:00"}],"reserva":{"inicio":"2026-11-12T10:00:00-03:00","fin":"2026-11-12T12:00:00-03:00","estado":"fallo","motivo":"tomada"}}"#)
        #expect(f.reserva?.estado == .fallo && f.reserva?.motivo == "tomada" && f.franjas.map(\.id) == ["f2"], "con fallo vuelven las franjas")
        // Un estado que no se conoce, sin horas o un link que no es https: no se adivina.
        #expect(agenda(#"{"ok":true,"reserva":{"inicio":"2026-11-12T10:00:00-03:00","fin":"2026-11-12T12:00:00-03:00","estado":"cancelada"}}"#).reserva == nil)
        #expect(agenda(#"{"ok":true,"reserva":{"estado":"confirmada"}}"#).reserva == nil)
        #expect(agenda(#"{"ok":true,"reserva":{"inicio":"2026-11-12T10:00:00-03:00","fin":"2026-11-12T12:00:00-03:00","estado":"confirmada","meet_url":"http://meet.google.com/x"}}"#).reserva?.meetUrl == nil)
        #expect(agenda(#"{"ok":true,"reserva":"si"}"#).reserva == nil)
    }

    @Test func elResumenSumaLaReservaOpcional() {
        let r = resumen(#"{"ok":true,"total":3,"vistos":1,"reserva":{"inicio":"2026-11-12T10:00:00-03:00","fin":"2026-11-12T12:00:00-03:00","estado":"confirmada","meet_url":"https://meet.google.com/abc"}}"#)
        #expect(r.reserva?.estado == .confirmada && r.reserva?.id == nil)
        #expect(resumen(#"{"ok":true,"total":3,"vistos":1}"#).reserva == nil)
        #expect(resumen(#"{"ok":true,"total":3,"reserva":{"estado":"x"}}"#).reserva == nil && resumen(#"{"ok":true,"total":3,"reserva":{"estado":"x"}}"#).total == 3)
        #expect(resumen(#"{"ok":false,"novedad_en":"2026-11-05T12:00:00-03:00","reserva":{"inicio":"a","fin":"b","estado":"confirmada"}}"#) == ResumenGuia(ok: false))
    }

    @Test func idaYVueltaPorLaCopia() throws {
        let a = agenda(#"{"ok":true,"autorizada":true,"habilitada":true,"faltan":0,"franjas":[{"id":"f1","inicio":"2026-11-12T10:00:00-03:00","fin":"2026-11-12T12:00:00-03:00"}]}"#)
        let b = try JSONDecoder().decode(AgendaGuia.self, from: JSONEncoder().encode(a))
        #expect(a == b)
    }
}

@Suite("Agenda de la entrega: qué se muestra y la hora (2.2.0)")
struct AgendaVistaTests {
    let franjas = #"[{"id":"f1","inicio":"2026-11-12T10:00:00-03:00","fin":"2026-11-12T12:00:00-03:00"},{"id":"f2","inicio":"2026-11-12T14:00:00-03:00","fin":"2026-11-12T16:00:00-03:00"},{"id":"f3","inicio":"2026-11-13T10:00:00-03:00","fin":"2026-11-13T12:00:00-03:00"}]"#

    @Test func cadaEstado() {
        #expect(ReglasAgenda.vista(nil, faltanLocal: 2, enCola: false) == .nada)
        #expect(ReglasAgenda.vista(agenda(#"{"ok":false}"#), faltanLocal: 0, enCola: false) == .nada)
        // El `faltan` del servidor manda; el del teléfono es el respaldo.
        #expect(ReglasAgenda.vista(agenda(#"{"ok":true,"faltan":3}"#), faltanLocal: 1, enCola: false) == .noAutorizada(faltan: 3))
        #expect(ReglasAgenda.vista(agenda(#"{"ok":true}"#), faltanLocal: 1, enCola: false) == .noAutorizada(faltan: 1))
        #expect(ReglasAgenda.vista(agenda(#"{"ok":true,"autorizada":true,"habilitada":false,"faltan":2}"#), faltanLocal: 0, enCola: false) == .bloqueada(faltan: 2))
        let h = agenda(#"{"ok":true,"autorizada":true,"habilitada":true,"faltan":0,"franjas":\#(franjas)}"#)
        #expect(ReglasAgenda.vista(h, faltanLocal: 0, enCola: false) == .franjas(aviso: nil))
        #expect(ReglasAgenda.vista(h, faltanLocal: 0, enCola: false, aviso: .tomada) == .franjas(aviso: .tomada))
        #expect(ReglasAgenda.vista(h, faltanLocal: 0, enCola: true) == .reservando)
        #expect(ReglasAgenda.vista(agenda(#"{"ok":true,"autorizada":true,"habilitada":true,"franjas":[]}"#), faltanLocal: 0, enCola: false) == .sinFranjas(aviso: nil))
        let p = agenda(#"{"ok":true,"autorizada":true,"habilitada":true,"reserva":{"inicio":"2026-11-12T10:00:00-03:00","fin":"2026-11-12T12:00:00-03:00","estado":"pendiente"}}"#)
        #expect(ReglasAgenda.vista(p, faltanLocal: 0, enCola: false) == .reservando)
        let c = agenda(#"{"ok":true,"autorizada":true,"habilitada":true,"reserva":{"inicio":"2026-11-12T10:00:00-03:00","fin":"2026-11-12T12:00:00-03:00","estado":"confirmada","meet_url":"https://meet.google.com/abc"}}"#)
        guard case .confirmada(let r, nil) = ReglasAgenda.vista(c, faltanLocal: 0, enCola: false) else { Issue.record("no quedó confirmada"); return }
        #expect(r.meetUrl != nil)
        let f = agenda(#"{"ok":true,"autorizada":true,"habilitada":true,"franjas":\#(franjas),"reserva":{"inicio":"2026-11-12T10:00:00-03:00","fin":"2026-11-12T12:00:00-03:00","estado":"fallo","motivo":"tomada"}}"#)
        #expect(ReglasAgenda.vista(f, faltanLocal: 0, enCola: false) == .franjas(aviso: .tomada))
        let fe = agenda(#"{"ok":true,"autorizada":true,"habilitada":true,"franjas":[],"reserva":{"inicio":"2026-11-12T10:00:00-03:00","fin":"2026-11-12T12:00:00-03:00","estado":"fallo","motivo":"error"}}"#)
        #expect(ReglasAgenda.vista(fe, faltanLocal: 0, enCola: false) == .sinFranjas(aviso: .error))
    }

    @Test func textos() {
        #expect(ReglasAgenda.textoBloqueada(2) == "Cuando termines los videos de arriba se habilita la agenda. Te faltan 2.")
        #expect(ReglasAgenda.textoNoAutorizada == "Cuando termines de ver todo te habilitamos la agenda.")
        #expect(ReglasAgenda.Aviso.tomada.texto == "Ese horario se ocupó recién, elegí otro.")
        #expect(ReglasAgenda.textoSinFranjas == "Ahora no hay horarios libres. Te escribimos por WhatsApp para coordinar.")
    }

    @Test func enArgentinaPorDia() throws {
        let ba = try #require(TimeZone(identifier: "America/Argentina/Buenos_Aires"))
        let ahora = fecha("2026-11-06T12:00:00-03:00")
        let d = ReglasAgenda.dias(agenda(#"{"ok":true,"autorizada":true,"habilitada":true,"franjas":\#(franjas)}"#).franjas, zona: ba, ahora: ahora)
        #expect(d.map(\.titulo) == ["jueves 12 de noviembre", "viernes 13 de noviembre"])
        #expect(d[0].chips.map(\.texto) == ["10:00 a 12:00", "14:00 a 16:00"])
        #expect(!ReglasAgenda.difiereDeArgentina(d.flatMap(\.chips).map(\.inicio), zona: ba))
        #expect(ReglasAgenda.textoConfirmar(d[0].chips[0], zona: ba) == "¿Confirmás la entrega el jueves 12 a las 10:00? Dura unas 2 horas.")
        let r = ReservaAgenda(inicio: "2026-11-12T10:00:00-03:00", fin: "2026-11-12T12:00:00-03:00", estado: .confirmada)
        #expect(ReglasAgenda.textoConfirmada(r, zona: ba) == "Tu entrega: jueves 12 de noviembre, 10:00 a 12:00")
    }

    /// Mati cambia horarios y duración solo con datos (10, 11 y 12, llamadas más cortas): nada fijo en 2 h ni en 10 o 14.
    @Test func laDuracionSaleDeCadaFranja() throws {
        let ba = try #require(TimeZone(identifier: "America/Argentina/Buenos_Aires"))
        let ahora = fecha("2026-11-06T12:00:00-03:00")
        let fs = agenda(#"{"ok":true,"autorizada":true,"habilitada":true,"franjas":[{"id":"f1","inicio":"2026-11-12T11:00:00-03:00","fin":"2026-11-12T12:00:00-03:00"},{"id":"f2","inicio":"2026-11-12T12:00:00-03:00","fin":"2026-11-12T12:45:00-03:00"}]}"#).franjas
        let d = ReglasAgenda.dias(fs, zona: ba, ahora: ahora)
        #expect(d[0].chips.map(\.texto) == ["11:00 a 12:00", "12:00 a 12:45"])
        #expect(ReglasAgenda.textoConfirmar(d[0].chips[0], zona: ba) == "¿Confirmás la entrega el jueves 12 a las 11:00? Dura alrededor de 1 hora.")
        #expect(ReglasAgenda.textoConfirmar(d[0].chips[1], zona: ba) == "¿Confirmás la entrega el jueves 12 a las 12:00? Dura unos 45 minutos.")
        // Duran distinto: el encabezado no promete una sola duración.
        #expect(ReglasAgenda.textoElegir(d[0].chips) == "Elegí un horario para la videollamada.")
        #expect(ReglasAgenda.textoElegir([d[0].chips[0]]) == "Elegí un horario para la videollamada. Dura alrededor de 1 hora.")
        let dos = ReglasAgenda.dias(agenda(#"{"ok":true,"autorizada":true,"habilitada":true,"franjas":\#(franjas)}"#).franjas, zona: ba, ahora: ahora)
        #expect(ReglasAgenda.textoElegir(dos.flatMap(\.chips)) == "Elegí un horario para la videollamada. Dura unas 2 horas.")
    }

    @Test func redondeoDeLaDuracion() {
        let i = fecha("2026-11-12T10:00:00-03:00")
        func dura(_ min: Double) -> String? { ReglasAgenda.textoDuracion(desde: i, hasta: i.addingTimeInterval(min * 60)) }
        #expect(dura(120) == "Dura unas 2 horas.")
        #expect(dura(110) == "Dura unas 2 horas.")
        #expect(dura(90) == "Dura alrededor de 1 hora y media.")
        #expect(dura(150) == "Dura unas 2 horas y media.")
        #expect(dura(70) == "Dura alrededor de 1 hora.")
        #expect(dura(60) == "Dura alrededor de 1 hora.")
        #expect(dura(55) == "Dura alrededor de 1 hora.")
        #expect(dura(45) == "Dura unos 45 minutos.")
        #expect(dura(40) == "Dura unos 45 minutos.")
        #expect(dura(30) == "Dura unos 30 minutos.")
        #expect(dura(5) == "Dura unos 15 minutos.")
        #expect(dura(0) == nil && dura(-30) == nil)
    }

    @Test func unTelefonoEnMadridYOtroEnMexicoVenLaHoraConvertida() throws {
        let ahora = fecha("2026-11-06T12:00:00-03:00")
        let fs = agenda(#"{"ok":true,"autorizada":true,"habilitada":true,"franjas":[{"id":"f1","inicio":"2026-11-12T10:00:00-03:00","fin":"2026-11-12T12:00:00-03:00"},{"id":"f2","inicio":"2026-11-12T22:00:00-03:00","fin":"2026-11-13T00:00:00-03:00"}]}"#).franjas
        let madrid = try #require(TimeZone(identifier: "Europe/Madrid"))
        let dm = ReglasAgenda.dias(fs, zona: madrid, ahora: ahora)
        // Madrid en noviembre es UTC+1: 4 h más que Argentina. La de las 22 pasa al día siguiente.
        #expect(dm.map(\.titulo) == ["jueves 12 de noviembre", "viernes 13 de noviembre"])
        #expect(dm[0].chips[0].texto == "14:00 a 16:00" && dm[1].chips[0].texto == "02:00 a 04:00")
        #expect(ReglasAgenda.difiereDeArgentina(dm.flatMap(\.chips).map(\.inicio), zona: madrid))
        #expect(ReglasAgenda.textoConfirmar(dm[0].chips[0], zona: madrid) == "¿Confirmás la entrega el jueves 12 a las 14:00 (10:00 en Argentina)? Dura unas 2 horas.")
        let mexico = try #require(TimeZone(identifier: "America/Mexico_City"))
        let dx = ReglasAgenda.dias(fs, zona: mexico, ahora: ahora)
        // México (sin horario de verano desde 2022) es UTC−6: 3 h menos.
        #expect(dx.map(\.titulo) == ["jueves 12 de noviembre"] && dx[0].chips.map(\.texto) == ["07:00 a 09:00", "19:00 a 21:00"])
        let r = ReservaAgenda(inicio: "2026-11-12T10:00:00-03:00", fin: "2026-11-12T12:00:00-03:00", estado: .confirmada)
        #expect(ReglasAgenda.textoConfirmada(r, zona: mexico) == "Tu entrega: jueves 12 de noviembre, 07:00 a 09:00")
        #expect(ReglasAgenda.textoEsperandoSala(r, zona: madrid) == "Tu entrega es hoy a las 14:00. Cuando Mati abra la videollamada se habilita el botón para entrar.")
    }

    @Test func lasQueYaEmpezaronOVienenRotasNoVan() throws {
        let ba = try #require(TimeZone(identifier: "America/Argentina/Buenos_Aires"))
        let fs = [FranjaAgenda(id: "vieja", inicio: "2026-11-05T10:00:00-03:00", fin: "2026-11-05T12:00:00-03:00"),
                  FranjaAgenda(id: "rota", inicio: "mañana", fin: "pasado"),
                  FranjaAgenda(id: "alreves", inicio: "2026-11-12T12:00:00-03:00", fin: "2026-11-12T10:00:00-03:00"),
                  FranjaAgenda(id: "ok", inicio: "2026-11-12 13:00:00+00", fin: "2026-11-12 15:00:00+00")]
        let d = ReglasAgenda.dias(fs, zona: ba, ahora: fecha("2026-11-06T12:00:00-03:00"))
        #expect(d.flatMap(\.chips).map(\.id) == ["ok"] && d[0].chips[0].texto == "10:00 a 12:00")
    }

    @Test func entrarSoloConLaSalaAbiertaOALaHoraDeInicio() throws {
        let ba = try #require(TimeZone(identifier: "America/Argentina/Buenos_Aires"))
        let r = ReservaAgenda(inicio: "2026-11-12T10:00:00-03:00", fin: "2026-11-12T12:00:00-03:00", estado: .confirmada,
                              meetUrl: URL(string: "https://meet.google.com/abc"))
        // La tarjeta de Entreno: desde 30 min antes hasta el fin.
        #expect(!ReglasAgenda.enVentana(r, ahora: fecha("2026-11-12T09:29:00-03:00")))
        #expect(ReglasAgenda.enVentana(r, ahora: fecha("2026-11-12T09:30:00-03:00")))
        #expect(!ReglasAgenda.enVentana(r, ahora: fecha("2026-11-12T12:00:00-03:00")))
        // Sin `sala_abierta_en`: sin botón hasta la hora de inicio (el respaldo), y mientras tanto se espera la sala.
        #expect(!ReglasAgenda.puedeEntrar(r, ahora: fecha("2026-11-12T09:50:00-03:00")))
        #expect(ReglasAgenda.esperandoSala(r, ahora: fecha("2026-11-12T09:50:00-03:00")))
        #expect(!ReglasAgenda.esperandoSala(r, ahora: fecha("2026-11-12T09:00:00-03:00")), "antes de la ventana no se consulta")
        #expect(ReglasAgenda.puedeEntrar(r, ahora: fecha("2026-11-12T10:00:00-03:00")))
        #expect(!ReglasAgenda.esperandoSala(r, ahora: fecha("2026-11-12T10:00:00-03:00")))
        #expect(ReglasAgenda.textoEntrar(r, zona: ba) == "Tu entrega empezó a las 10:00")
        #expect(!ReglasAgenda.puedeEntrar(r, ahora: fecha("2026-11-12T12:00:00-03:00")))
        // Con `sala_abierta_en`: el botón enseguida, con «Mati ya está en la videollamada».
        var abierta = r; abierta.salaAbiertaEn = "2026-11-12T09:52:00-03:00"
        #expect(ReglasAgenda.puedeEntrar(abierta, ahora: fecha("2026-11-12T09:53:00-03:00")))
        #expect(ReglasAgenda.textoEntrar(abierta, zona: ba) == "Mati ya está en la videollamada")
        #expect(!ReglasAgenda.puedeEntrar(abierta, ahora: fecha("2026-11-12T12:01:00-03:00")))
        // Sin link o sin confirmar: nunca.
        var sinLink = abierta; sinLink.meetUrl = nil
        #expect(!ReglasAgenda.puedeEntrar(sinLink, ahora: fecha("2026-11-12T10:00:00-03:00")))
        var pendiente = abierta; pendiente.estado = .pendiente
        #expect(!ReglasAgenda.puedeEntrar(pendiente, ahora: fecha("2026-11-12T10:00:00-03:00")))
        #expect(!ReglasAgenda.enVentana(pendiente, ahora: fecha("2026-11-12T10:00:00-03:00")))
        // «Es hoy»: el mismo día del teléfono, hasta el fin. Antes del día, solo la fecha y la hora.
        #expect(ReglasAgenda.esHoy(r, zona: ba, ahora: fecha("2026-11-12T07:00:00-03:00")))
        #expect(!ReglasAgenda.esHoy(r, zona: ba, ahora: fecha("2026-11-11T22:00:00-03:00")))
        #expect(!ReglasAgenda.esHoy(r, zona: ba, ahora: fecha("2026-11-12T12:30:00-03:00")))
        #expect(ReglasAgenda.textoEsperandoSala(r, zona: ba) == "Tu entrega es hoy a las 10:00. Cuando Mati abra la videollamada se habilita el botón para entrar.")
        // Decodificar: opcional y tolerante.
        let a = agenda(#"{"ok":true,"autorizada":true,"habilitada":true,"reserva":{"inicio":"2026-11-12T10:00:00-03:00","fin":"2026-11-12T12:00:00-03:00","estado":"confirmada","meet_url":"https://meet.google.com/abc","sala_abierta_en":"2026-11-12T09:52:00-03:00"}}"#)
        #expect(a.reserva?.salaAbiertaEn == "2026-11-12T09:52:00-03:00")
        #expect(agenda(#"{"ok":true,"reserva":{"inicio":"2026-11-12T10:00:00-03:00","fin":"2026-11-12T12:00:00-03:00","estado":"confirmada","sala_abierta_en":" "}}"#).reserva?.salaAbiertaEn == nil)
    }
}

@Suite("Agenda de la demo (2.2.0)")
struct AgendaDemoTests {
    @Test func lasFranjasDeLaDemoSeCorrenAMañana() throws {
        let fs = [FranjaAgenda(id: "a", inicio: "2026-11-12T10:00:00-03:00", fin: "2026-11-12T12:00:00-03:00"),
                  FranjaAgenda(id: "b", inicio: "2026-11-13T14:00:00-03:00", fin: "2026-11-13T16:00:00-03:00")]
        let ahora = ReglasGuia.instante("2026-12-01T20:30:00-03:00")!
        let c = ReglasAgenda.correrAlFuturo(fs, ahora: ahora)
        #expect(c.map(\.inicio) == ["2026-12-02T10:00:00-03:00", "2026-12-03T14:00:00-03:00"])
        #expect(c.map(\.fin) == ["2026-12-02T12:00:00-03:00", "2026-12-03T16:00:00-03:00"])
        // En el futuro, como vinieron.
        #expect(ReglasAgenda.correrAlFuturo(fs, ahora: ReglasGuia.instante("2026-11-01T10:00:00-03:00")!) == fs)
    }

    /// Como el servidor (`agenda_lib.huecos`): solo de lunes a viernes. Un viernes a la noche, la primera cae el lunes.
    @Test func laDemoNuncaOfreceSabadosNiDomingos() throws {
        let demo = [("a", "2026-11-12T10:00:00-03:00"), ("b", "2026-11-12T14:00:00-03:00"), ("c", "2026-11-13T10:00:00-03:00"),
                    ("d", "2026-11-16T10:00:00-03:00"), ("e", "2026-11-16T14:00:00-03:00"), ("f", "2026-11-17T14:00:00-03:00")]
        let fs = demo.map { FranjaAgenda(id: $0.0, inicio: $0.1, fin: $0.1.replacingOccurrences(of: ":00:00-", with: ":59:00-")) }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Argentina/Buenos_Aires")!
        // Cada día de dos semanas, a las 8 y a las 23.
        for d in 0..<14 {
            for h in [8, 23] {
                let ahora = cal.date(byAdding: .hour, value: 24 * d + h, to: ReglasGuia.instante("2026-11-20T00:00:00-03:00")!)!
                let c = ReglasAgenda.correrAlFuturo(fs, ahora: ahora)
                #expect(c.count == fs.count)
                for f in c {
                    let i = try #require(ReglasGuia.instante(f.inicio))
                    #expect(!cal.isDateInWeekend(i), "\(f.inicio) cae fin de semana (ahora \(ahora))")
                    #expect(i > ahora)
                }
                // El mismo orden y la misma hora.
                #expect(c.map(\.id) == fs.map(\.id))
                #expect(c.map { String($0.inicio.dropFirst(11)) } == fs.map { String($0.inicio.dropFirst(11)) })
            }
        }
        // Viernes 4/12 a la noche: el jueves y el viernes de la demo van al lunes 7 y al martes 8; su lunes, al miércoles 9.
        let c = ReglasAgenda.correrAlFuturo(fs, ahora: ReglasGuia.instante("2026-12-04T20:30:00-03:00")!)
        #expect(c.map(\.inicio) == ["2026-12-07T10:00:00-03:00", "2026-12-07T14:00:00-03:00", "2026-12-08T10:00:00-03:00",
                                     "2026-12-09T10:00:00-03:00", "2026-12-09T14:00:00-03:00", "2026-12-10T14:00:00-03:00"])
        #expect(c.first?.fin == "2026-12-07T10:59:00-03:00")
    }

    @Test func elProximoDiaHabil() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Argentina/Buenos_Aires")!
        let viernes = ReglasGuia.instante("2026-11-06T18:00:00-03:00")!
        let fmt = { (d: Date) in ReglasAgenda.claveDia(d, zona: cal.timeZone) }
        #expect(fmt(ReglasAgenda.diaHabil(1, desde: viernes, cal)) == "2026-11-09")
        #expect(fmt(ReglasAgenda.diaHabil(2, desde: viernes, cal)) == "2026-11-10")
        #expect(fmt(ReglasAgenda.diaHabil(4, desde: viernes, cal)) == "2026-11-12")
        let sabado = ReglasGuia.instante("2026-11-07T10:00:00-03:00")!
        #expect(fmt(ReglasAgenda.diaHabil(1, desde: sabado, cal)) == "2026-11-09")
        let martes = ReglasGuia.instante("2026-11-10T10:00:00-03:00")!
        #expect(fmt(ReglasAgenda.diaHabil(4, desde: martes, cal)) == "2026-11-16")
    }
}

/// Spec §7: Mati edita todo desde el servidor, sin versión nueva.
@Suite("Agenda: lo que edita Mati (§7)")
struct AgendaEditableTests {
    private let ba = TimeZone(identifier: "America/Argentina/Buenos_Aires")!

    @Test func unTextoPisadoConSusValores() throws {
        let a = agenda(#"{"ok":true,"autorizada":true,"habilitada":true,"franjas":[{"id":"f1","inicio":"2026-11-12T11:00:00-03:00","fin":"2026-11-12T12:00:00-03:00"}],"textos":{"confirmar":"¿Te anoto el {dia} a las {hora}? Son {duracion}.","titulo":"Tu llamada","cambiar":"  ","sala_abierta":7,"inventada":"x","bloqueada":"Faltan {faltan} videos"}}"#)
        // Solo los textos no vacíos; lo que no es texto no entra. Una clave desconocida queda guardada pero no se usa.
        #expect(a.textos["titulo"] == "Tu llamada" && a.textos["cambiar"] == nil && a.textos["sala_abierta"] == nil)
        let t = ReglasAgenda.Textos(a.textos)
        let c = try #require(ReglasAgenda.dias(a.franjas, zona: ba, ahora: fecha("2026-11-06T12:00:00-03:00")).first?.chips.first)
        #expect(t.confirmar(c, zona: ba) == "¿Te anoto el jueves 12 a las 11:00? Son alrededor de 1 hora.")
        #expect(t.titulo == "Tu llamada")
        #expect(t.cambiar == ReglasAgenda.textoCambiar)
        #expect(t.bloqueada(2) == "Faltan 2 videos")
        // Con 0 no hay clave: «Ya viste todo…».
        #expect(t.bloqueada(0) == ReglasAgenda.textoBloqueada(0))
        // Sin textos, los de la app.
        #expect(ReglasAgenda.Textos().confirmar(c, zona: ba) == ReglasAgenda.textoConfirmar(c, zona: ba))
    }

    @Test func unValorQueNoHayNoDejaLlavesALaVista() {
        let t = ReglasAgenda.Textos(["encabezado": "Elegí un horario. Dura {duracion}.", "sin_franjas": "Sin lugar: {hora}"])
        // Franjas de duración distinta: no hay una sola, va el de la app.
        let f1 = FranjaAgenda(id: "a", inicio: "2026-11-12T10:00:00-03:00", fin: "2026-11-12T11:00:00-03:00")
        let f2 = FranjaAgenda(id: "b", inicio: "2026-11-12T14:00:00-03:00", fin: "2026-11-12T14:45:00-03:00")
        let chips = ReglasAgenda.dias([f1, f2], zona: ba, ahora: fecha("2026-11-06T12:00:00-03:00")).flatMap(\.chips)
        #expect(t.encabezado(chips) == ReglasAgenda.textoElegir(chips))
        #expect(t.encabezado([chips[0]]) == "Elegí un horario. Dura alrededor de 1 hora.")
        #expect(t.sinFranjas == ReglasAgenda.textoSinFranjas)
    }

    @Test func losTextosDeLaSalaYDelFallo() {
        let t = ReglasAgenda.Textos(["hoy_sin_sala": "Hoy a las {hora}, esperá a Mati", "sala_abierta": "Mati te espera", "fallo": "Elegí otro",
                                     "entreno_aviso": "Entrega {hora}"])
        let r = ReservaAgenda(inicio: "2026-11-12T10:00:00-03:00", fin: "2026-11-12T11:00:00-03:00", estado: .confirmada,
                              meetUrl: URL(string: "https://meet.google.com/x"), salaAbiertaEn: "2026-11-12T09:58:00-03:00")
        #expect(t.hoySinSala(r, zona: ba) == "Hoy a las 10:00, esperá a Mati")
        #expect(t.entrenoAviso(r, zona: ba) == "Entrega 10:00")
        #expect(t.entrar(r, zona: ba) == "Mati te espera")
        var sinSala = r; sinSala.salaAbiertaEn = nil
        // El respaldo de la hora de inicio no es la sala abierta: no se pisa.
        #expect(t.entrar(sinSala, zona: ba) == ReglasAgenda.textoEntrar(sinSala, zona: ba))
        #expect(t.fallo(.tomada) == "Elegí otro" && t.fallo(.error) == "Elegí otro" && t.fallo(.demo) == ReglasAgenda.Aviso.demo.texto)
        // Sin `entreno_aviso`, el de la guía.
        #expect(ReglasAgenda.Textos(["hoy_sin_sala": "Hoy {hora}"]).entrenoAviso(r, zona: ba) == "Hoy 10:00")
    }

    @Test func avisoMin15() {
        let a = agenda(#"{"ok":true,"autorizada":true,"habilitada":true,"aviso_min":15}"#)
        #expect(a.avisoMin == 15)
        #expect(agenda(#"{"ok":true,"aviso_min":-3}"#).avisoMin == nil && agenda(#"{"ok":true,"aviso_min":"x"}"#).avisoMin == nil)
        let r = ReservaAgenda(inicio: "2026-11-12T10:00:00-03:00", fin: "2026-11-12T11:00:00-03:00", estado: .confirmada)
        let a20 = fecha("2026-11-12T09:40:00-03:00"), a10 = fecha("2026-11-12T09:50:00-03:00")
        #expect(!ReglasAgenda.enVentana(r, ahora: a20, avisoMin: 15))
        #expect(ReglasAgenda.enVentana(r, ahora: a10, avisoMin: 15))
        // Sin el dato, los 30 de la app.
        #expect(ReglasAgenda.enVentana(r, ahora: a20))
    }

    /// `exigir_obligatorios: false` en el servidor: habilitada con videos sin ver. La app no bloquea por su cuenta.
    @Test func habilitadaConVideosSinVerMuestraLasFranjas() {
        let a = agenda(#"{"ok":true,"autorizada":true,"habilitada":true,"faltan":0,"franjas":\#(AgendaReservaTests.franjasDe)}"#)
        #expect(ReglasAgenda.vista(a, faltanLocal: 3, enCola: false) == .franjas(aviso: nil))
        // Aunque el servidor diga faltan > 0 (informativo), si habilitó, habilitó.
        let b = agenda(#"{"ok":true,"autorizada":true,"habilitada":true,"faltan":2,"franjas":\#(AgendaReservaTests.franjasDe)}"#)
        #expect(ReglasAgenda.vista(b, faltanLocal: 2, enCola: false) == .franjas(aviso: nil))
        // Y si no habilitó, manda su `faltan` sobre el del teléfono.
        let c = agenda(#"{"ok":true,"autorizada":true,"habilitada":false,"faltan":1}"#)
        #expect(ReglasAgenda.vista(c, faltanLocal: 4, enCola: false) == .bloqueada(faltan: 1))
    }
}

enum AgendaReservaTests {
    static let franjasDe = #"[{"id":"f1","inicio":"2026-11-12T10:00:00-03:00","fin":"2026-11-12T11:00:00-03:00"}]"#
}
