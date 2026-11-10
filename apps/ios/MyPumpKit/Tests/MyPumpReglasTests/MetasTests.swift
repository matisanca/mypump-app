import Foundation
import Testing
@testable import MyPumpModelos
@testable import MyPumpReglas

/// Metas de pasos y ritmo de peso (2.3.0), contra apps/shared/vectores/metas_pasos.json: los mismos casos que lee
/// MetasTest.kt y la web (scripts/test-metas.mjs).
struct MetasTests {
    private static var vectores: [String: JSONValue] {
        let url = raizRepo.appendingPathComponent("apps/shared/vectores/metas_pasos.json")
        guard let data = try? Data(contentsOf: url), case .objeto(let o)? = try? JSONDecoder().decode(JSONValue.self, from: data) else { return [:] }
        return o
    }
    private static func lista(_ k: String) -> [JSONValue] { if case .lista(let l)? = vectores[k] { return l }; return [] }
    private static func pasos(_ j: JSONValue?) -> [String: Double] {
        guard case .objeto(let o)? = j else { return [:] }
        return o.compactMapValues { if case .numero(let n) = $0 { return n }; return nil }
    }
    private static func numero(_ j: JSONValue?) -> Double? { if case .numero(let n)? = j { return n }; return nil }
    private static func texto(_ j: JSONValue?) -> String? { if case .texto(let s)? = j { return s }; return nil }
    private static func bool(_ j: JSONValue?) -> Bool? { if case .bool(let b)? = j { return b }; return nil }

    @Test func metasDelPlan() throws {
        let casos = Self.lista("metas")
        #expect(casos.count >= 10)
        for c in casos {
            let e = try JSONDecoder().decode(EstructuraDieta.self, from: JSONEncoder().encode(c["estructura"]!))
            let m = MetasPlan(e)
            #expect(m.metaPasos == Self.numero(c["metaPasos"]).map { Int($0) }, "\(Self.texto(c["nombre"]) ?? "")")
            #expect(m.ritmoKgSemana == Self.numero(c["ritmo"]), "\(Self.texto(c["nombre"]) ?? "")")
        }
    }

    @Test func vista() {
        let casos = Self.lista("vista")
        #expect(casos.count >= 8)
        for c in casos {
            let nombre = Self.texto(c["nombre"]) ?? ""
            let esp = c["esperado"]!
            guard let v = PumpDelDia.vista(pasosPorDia: Self.pasos(c["pasos"]), meta: Int(Self.numero(c["meta"])!), hoy: Self.texto(c["hoy"])!) else {
                Issue.record("sin vista: \(nombre)"); continue
            }
            #expect(v.pasosHoy == Int(Self.numero(esp["pasosHoy"])!), "\(nombre)")
            #expect(abs(v.fraccion - Self.numero(esp["fraccion"])!) < 1e-5, "\(nombre)")
            #expect(v.falta == Int(Self.numero(esp["falta"])!), "\(nombre)")
            #expect(v.cumplido == Self.bool(esp["cumplido"]), "\(nombre)")
            #expect(v.racha == Int(Self.numero(esp["racha"])!), "\(nombre)")
            if case .lista(let s)? = esp["semana"] { #expect(v.semana.map(\.estado.rawValue) == s.compactMap(Self.texto), "\(nombre)") }
            #expect(v.promedio7 == Self.numero(esp["promedio7"]).map { Int($0) }, "\(nombre)")
            #expect(v.semana.map(\.inicial) == ["L", "M", "M", "J", "V", "S", "D"])
        }
    }

    @Test func celebrarUnaVezPorDia() {
        for c in Self.lista("celebrar") {
            var cel: [String] = []
            if case .lista(let l)? = c["celebrados"] { cel = l.compactMap(Self.texto) }
            let r = PumpDelDia.debeCelebrar(.init(celebrados: cel), hoy: Self.texto(c["hoy"])!, pasosHoy: Int(Self.numero(c["pasos"])!),
                                            meta: Int(Self.numero(c["meta"])!))
            #expect(r == Self.bool(c["celebra"]), "\(Self.texto(c["nombre"]) ?? "")")
        }
    }

    @Test func ritmo() {
        for c in Self.lista("ritmo") {
            let nombre = Self.texto(c["nombre"]) ?? ""
            let serie = Self.pasos(c["pesos"]).map { PesoCorporal.Punto(fecha: $0.key, kg: $0.value) }.sorted { $0.fecha < $1.fecha }
            let r = RitmoPeso.resumen(ritmo: Self.numero(c["ritmo"])!, serie: serie, hoy: Self.texto(c["hoy"])!)
            let esp = c["esperado"]!
            #expect(r.meta == Self.texto(esp["meta"]), "\(nombre)")
            #expect(r.tendencia == Self.texto(esp["tendencia"]), "\(nombre)")
            #expect(r.enRitmo == Self.bool(esp["enRitmo"]), "\(nombre)")
        }
        for c in Self.lista("cantidad") {
            #expect(RitmoPeso.cantidad(kg: Self.numero(c["kg"])!) == Self.texto(c["texto"]))
        }
    }

    /// Marcar el día lo deja una sola vez, en orden, y guarda las últimas 60 fechas.
    @Test func marcarGuardaUnaVezYPoda() {
        var r = PumpDelDia.Registro()
        r = PumpDelDia.marcar(r, hoy: "2026-11-10")
        r = PumpDelDia.marcar(r, hoy: "2026-11-10")
        #expect(r.celebrados == ["2026-11-10"])
        #expect(!PumpDelDia.debeCelebrar(r, hoy: "2026-11-10", pasosHoy: 20000, meta: 10000))
        for i in 0..<80 { r = PumpDelDia.marcar(r, hoy: DiaCalendario.texto(21_000 + i)) }
        #expect(r.celebrados.count == 60)
        #expect(r.celebrados.last == DiaCalendario.texto(21_079))
    }

    /// El cambio de día con la zona del teléfono: las 23:30 en Buenos Aires ya son mañana en Madrid.
    @Test func hoyDependeDeLaZona() {
        let instante = Date(timeIntervalSince1970: 1_762_828_200)   // 2025-11-11 02:30 UTC
        let ba = TimeZone(identifier: "America/Argentina/Buenos_Aires")!, madrid = TimeZone(identifier: "Europe/Madrid")!
        let hoyBA = FechaLocal.hoy(instante, zona: ba), hoyMadrid = FechaLocal.hoy(instante, zona: madrid)
        #expect(hoyBA == "2025-11-10")
        #expect(hoyMadrid == "2025-11-11")
        let r = PumpDelDia.marcar(.init(), hoy: hoyMadrid)
        // Volvió a Buenos Aires el mismo instante: «ayer» no se festeja de nuevo.
        #expect(!PumpDelDia.debeCelebrar(r, hoy: hoyBA, pasosHoy: 12000, meta: 10000))
    }

    @Test func textosSinDosPuntosNiGuiones() {
        let v = PumpDelDia.vista(pasosPorDia: ["2026-11-12": 7420], meta: 10000, hoy: "2026-11-12")!
        let todos = [PumpDelDia.deMeta(v), PumpDelDia.estado(v), PumpDelDia.racha(3)!, PumpDelDia.sinSalud(meta: 10000),
                     PumpDelDia.conectar, PumpDelDia.celebracion(meta: 10000), PumpDelDia.celebracionRacha(4)!,
                     PumpDelDia.lineaSalud(meta: 10000, promedio: 8700), RitmoPeso.textoMeta(-0.5), RitmoPeso.enRitmoTexto]
        for t in todos {
            #expect(!t.contains(":") && !t.contains(" - ") && !t.contains("—"), "\(t)")
            #expect(!t.lowercased().contains("coach") && !t.lowercased().contains("entrenador") && !t.contains("IA"), "\(t)")
        }
        #expect(PumpDelDia.estado(v) == "Te faltan 2.580 pasos")
        #expect(PumpDelDia.lineaSalud(meta: 10000, promedio: 8700) == "Meta 10.000 pasos por día, tu promedio 8.700")
    }
}
