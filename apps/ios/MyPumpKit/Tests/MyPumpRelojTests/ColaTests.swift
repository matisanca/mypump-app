import Foundation
import Testing
@testable import MyPumpReloj

// La cola del reloj (lo hecho sin el teléfono) y los aplicados del iPhone (lo que evita duplicar).

func serie(_ lugar: String = "l", _ i: Int = 0, reps: Int = 10, kg: Double? = 50, dia: String = "d1", semana: Int = 1, t: Double = T0) -> EventoEnCola {
    EventoEnCola(.serie(diaId: dia, semana: semana, lugar: lugar, indice: i, reps: reps, kg: kg), creado: t)
}

@Suite struct ColaTests {
    @Test func guardaEnOrdenYSaleSoloConAcuse() {
        var c = ColaReloj()
        let a = EventoEnCola(.iniciar(diaId: "d1", semana: 1), creado: T0)
        let b = serie("l", 0), d = serie("l", 1)
        c.encolar(a); c.encolar(b); c.encolar(d)
        #expect(c.pendientes.map(\.id) == [a.id, b.id, d.id])
        let lote = c.paraEnviar(ahora: T0)
        #expect(lote.count == 3)
        #expect(c.pendientes.count == 3, "mandar no saca nada de la cola")
        let salen = c.acusar([AcuseEvento(id: a.id, resultado: .aplicado), AcuseEvento(id: d.id, resultado: .repetido)])
        #expect(salen.map(\.id) == [a.id, d.id])
        #expect(c.pendientes.map(\.id) == [b.id])
    }

    @Test func noReenviaAntesDelReintentoSalvoQueSeFuerce() {
        var c = ColaReloj()
        c.encolar(serie())
        let r1 = c.paraEnviar(ahora: T0)
        #expect(r1.count == 1)
        let r2 = c.paraEnviar(ahora: T0 + 1_000)
        #expect(r2.isEmpty)
        let r3 = c.paraEnviar(ahora: T0 + 1_000, forzar: true)
        #expect(r3.count == 1, "volvió la conexión: se manda todo")
        let r4 = c.paraEnviar(ahora: T0 + 1_000 + ColaReloj.reintento)
        #expect(r4.count == 1)
    }

    @Test func unEnvioFallidoSeMandaEnLaProxima() {
        var c = ColaReloj()
        c.encolar(serie())
        let lote = c.paraEnviar(ahora: T0)
        c.fallo(lote.map(\.id))
        let r5 = c.paraEnviar(ahora: T0 + 10)
        #expect(r5.count == 1)
    }

    @Test func corregirUnaSerieSinAcusarLaReemplazaEnSuLugar() {
        var c = ColaReloj()
        let primera = serie("l", 0, reps: 8)
        let otra = serie("m", 0)
        c.encolar(primera); c.encolar(otra)
        _ = c.paraEnviar(ahora: T0)
        let corregida = serie("l", 0, reps: 9)
        c.encolar(corregida)
        #expect(c.pendientes.map(\.id) == [corregida.id, otra.id])
        let r6 = c.paraEnviar(ahora: T0 + 1)
        #expect(r6.map(\.id) == [corregida.id], "la corregida es nueva: sale ya")
        // La misma serie de otro día no la pisa.
        c.encolar(serie("l", 0, dia: "d2"))
        #expect(c.pendientes.count == 3)
    }

    @Test func dosIniciarSeguidosSonUno() {
        var c = ColaReloj()
        c.encolar(EventoEnCola(.iniciar(diaId: "d1", semana: 1), creado: T0))
        c.encolar(EventoEnCola(.iniciar(diaId: "d1", semana: 1), creado: T0 + 5))
        #expect(c.pendientes.count == 1)
    }

    @Test func conElTopeSeVanLosViejosQueNoSonSeries() {
        var c = ColaReloj()
        c.encolar(EventoEnCola(.iniciar(diaId: "d0", semana: 1), creado: T0))
        for i in 0..<ColaReloj.tope { c.encolar(serie("l\(i)", 0)) }
        #expect(c.pendientes.count == ColaReloj.tope)
        #expect(c.pendientes.allSatisfy { if case .serie = $0.evento { true } else { false } })
        // Con solo series, no se pierde ninguna aunque pase el tope.
        c.encolar(serie("extra", 0))
        #expect(c.pendientes.count == ColaReloj.tope + 1)
    }

    @Test func sobreviveAlDiscoYUnArchivoRotoEsColaVacia() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("cola-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("cola.json")
        var c = ColaReloj()
        c.encolar(EventoEnCola(.iniciar(diaId: "d1", semana: 1), creado: T0))
        c.encolar(serie())
        _ = c.paraEnviar(ahora: T0)
        try c.guardar(url)
        var leida = ColaReloj.leer(url)
        #expect(leida.pendientes == c.pendientes)
        let r7 = leida.paraEnviar(ahora: T0 + 1)
        #expect(r7.count == 2, "al reabrir se reenvía todo (los envíos no se guardan)")
        try Data("{roto".utf8).write(to: url)
        #expect(ColaReloj.leer(url).vacia)
        #expect(ColaReloj.leer(dir.appendingPathComponent("no-existe.json")).vacia)
    }
}

@Suite struct AplicadosTests {
    @Test func unRepetidoNoSeVuelveAAplicar() {
        var a = AplicadosReloj()
        let id = UUID()
        let r8 = a.anotar(id)
        #expect(r8)
        let r9 = a.anotar(id)
        #expect(!r9)
        #expect(a.contiene(id))
    }

    @Test func guardaLosUltimosYOlvidaLosMasViejos() throws {
        var a = AplicadosReloj()
        let primero = UUID()
        a.anotar(primero)
        for _ in 0..<AplicadosReloj.tope { a.anotar(UUID()) }
        #expect(a.ids.count == AplicadosReloj.tope)
        #expect(!a.contiene(primero))
        let vuelta = try JSONDecoder().decode(AplicadosReloj.self, from: JSONEncoder().encode(a))
        #expect(vuelta == a)
        #expect(vuelta.contiene(a.ids.last!))
    }
}
