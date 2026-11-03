import Foundation
import Testing
import MyPumpModelos
@testable import MyPumpReglas

// 2.1, S2: el volumen por músculo. Los casos están a mano en `apps/shared/vectores/volumen.json`; Android
// (VolumenMusculoTest) lee el mismo archivo y tiene que dar lo mismo.

private extension JSONValue {
    subscript(_ k: String) -> JSONValue? { if case .objeto(let o) = self { return o[k] }; return nil }
    var elementos: [JSONValue] { if case .lista(let l) = self { return l }; return [] }
    var num: Double? { if case .numero(let n) = self { return n }; return nil }
    var txt: String? { if case .texto(let t) = self { return t }; return nil }
}

private func registros(_ v: JSONValue?) -> [VolumenMusculo.Registro] {
    (v?.elementos ?? []).map { (o: JSONValue) -> VolumenMusculo.Registro in
        let serie: Int? = o["serie"]?.num.map { Int($0) }
        return VolumenMusculo.Registro(musculo: o["musculo"]?.txt, tipo: o["tipo"]?.txt, fecha: o["fecha"]?.txt ?? "",
                                       lugar: o["lugar"]?.txt ?? "", serie: serie, clave: o["clave"]?.txt)
    }
}

@Suite("2.1: volumen por músculo (S2)")
struct VolumenMusculoTests {
    @Test func losCasosCompartidos() throws {
        let url = raizRepo.appendingPathComponent("apps/shared/vectores/volumen.json")
        let v = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url))
        let casos = v["casos"]!.elementos
        #expect(casos.count >= 15)
        for c in casos {
            let nombre = c["nombre"]!.txt!
            let r = VolumenMusculo.calcular(historial: registros(c["historial"]), enVivo: registros(c["enVivo"]), hoy: c["hoy"]!.txt!)
            let sale = c["sale"]!
            #expect(r.semana == sale["semana"]!.txt!, "\(nombre)")
            #expect(r.total == Int(sale["total"]!.num!), "\(nombre)")
            #expect(r.totalAnterior == Int(sale["totalAnterior"]!.num!), "\(nombre)")
            #expect(r.totalHoy == Int(sale["totalHoy"]!.num!), "\(nombre)")
            let filas = sale["filas"]!.elementos
            #expect(r.filas.count == filas.count, "\(nombre): \(r.filas)")
            for (a, b) in zip(r.filas, filas) {
                #expect(a.musculo == b["musculo"]?.txt, "\(nombre)")
                #expect(a.nombre == b["nombre"]!.txt!, "\(nombre)")
                #expect(a.semana == Int(b["semana"]!.num!), "\(nombre): \(a)")
                #expect(a.anterior == Int(b["anterior"]!.num!), "\(nombre): \(a)")
                #expect(a.hoy == Int(b["hoy"]!.num!), "\(nombre): \(a)")
            }
            #expect(r.filasDeHoy.map { $0.musculo } == sale["deHoy"]!.elementos.map { $0.txt }, "\(nombre)")
        }
    }

    @Test func textos() {
        #expect(VolumenMusculo.series(1) == "1 serie")
        #expect(VolumenMusculo.series(0) == "0 series")
        #expect(VolumenMusculo.nombre("middle back") == "Espalda media")
        #expect(VolumenMusculo.nombre(nil) == "Sin músculo asignado")
        let f = VolumenMusculo.Fila(musculo: "chest", nombre: "Pecho", semana: 12, anterior: 10, hoy: 0)
        #expect(f.textoAccesible == "Pecho, 12 series esta semana, 10 la semana pasada")
    }
}
