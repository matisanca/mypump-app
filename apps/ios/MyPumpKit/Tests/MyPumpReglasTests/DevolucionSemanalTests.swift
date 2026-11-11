import Foundation
import Testing
import MyPumpModelos
@testable import MyPumpReglas

/// La devolución de Mati: los mismos casos que Android y la web (`apps/shared/fixtures/devolucion/casos.json`).
@Suite("Devolución de Mati")
struct DevolucionSemanalTests {
    private static let raiz = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../../../shared/fixtures/devolucion").standardized

    @Test func losCasosCompartidos() throws {
        let datos = try Data(contentsOf: Self.raiz.appendingPathComponent("casos.json"))
        guard case .lista(let casos) = try JSONDecoder().decode(JSONValue.self, from: datos) else { Issue.record("casos"); return }
        #expect(casos.count >= 10)
        for c in casos {
            let nombre = c["nombre"]?.comoTexto ?? "?"
            let hoy = c["hoy"]?.comoTexto ?? ""
            let e = EstadoDevolucion(c["respuesta"] ?? .null)
            guard let esp = c["esperado"], esp != .null else { #expect(e == nil, "\(nombre)"); continue }
            guard let e else { Issue.record("\(nombre): dio nil"); continue }
            if let u = esp["ultima"], u != .null {
                #expect(e.ultima?.id == u["id"]?.comoTexto, "\(nombre)")
                #expect(e.ultima.map { ReglasDevolucion.etiqueta($0.semanaLunes, hoy: hoy) } == u["etiqueta"]?.comoTexto, "\(nombre)")
                #expect(e.ultima?.lineas == lineas(u["lineas"]), "\(nombre)")
                #expect(e.ultima.map { ReglasDevolucion.esNueva($0, hoy: hoy) } == (u["nueva"] == .bool(true)), "\(nombre)")
            } else {
                #expect(e.ultima == nil, "\(nombre)")
            }
            guard case .lista(let ant)? = esp["anteriores"] else { Issue.record("\(nombre): anteriores"); continue }
            #expect(e.anteriores.map(\.id) == ant.compactMap { $0["id"]?.comoTexto }, "\(nombre)")
            #expect(e.anteriores.map { ReglasDevolucion.etiqueta($0.semanaLunes, hoy: hoy) } == ant.compactMap { $0["etiqueta"]?.comoTexto }, "\(nombre)")
            #expect(e.anteriores.map(\.lineas) == ant.map { lineas($0["lineas"]) }, "\(nombre)")
        }
    }

    @Test func noMasDeDoce() {
        let l = (0..<20).map { i in JSONValue.objeto(["id": .texto("d\(i)"), "semana_lunes": .texto(String(format: "2026-%02d-01", (i % 12) + 1)), "texto": .texto("Bien.\nSeguí.\nAsí.")]) }
        let e = EstadoDevolucion(.objeto(["habilitado": .bool(true), "devoluciones": .lista(l)]))
        #expect((e?.devoluciones.count ?? 0) <= EstadoDevolucion.maximo)
    }

    private func lineas(_ j: JSONValue?) -> [String] {
        guard case .lista(let l)? = j else { return [] }
        return l.compactMap(\.comoTexto)
    }
}
