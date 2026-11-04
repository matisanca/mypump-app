import Foundation
import Testing
import MyPumpModelos
@testable import MyPumpReglas

// «Tu salud, últimos 7 días» del check de Revisión, contra los vectores compartidos con Android (salud_semana.json).
private struct ArchivoSemana: Decodable {
    struct Esperado: Decodable { let clave, etiqueta, valor, detalle: String }
    struct Caso: Decodable {
        let nombre: String
        let hoy: String
        let mostrar_score: Bool
        let salud: [FilaSalud]
        let recuperacion: [RecuperacionDia]
        let esperado: [Esperado]
    }
    let casos: [Caso]
}

@Suite("Salud de la semana en Revisión")
struct SaludSemanaTests {
    @Test func comoLosVectores() throws {
        let url = raizRepo.appendingPathComponent("apps/shared/vectores/salud_semana.json")
        let archivo = try JSONDecoder().decode(ArchivoSemana.self, from: Data(contentsOf: url))
        #expect(archivo.casos.count == 4)
        for c in archivo.casos {
            let r = SaludSemana.resumen(salud: c.salud, recuperacion: c.recuperacion, hoy: c.hoy, mostrarScore: c.mostrar_score)
            #expect(r.map(\.clave) == c.esperado.map(\.clave), "\(c.nombre)")
            #expect(r.map(\.valor) == c.esperado.map(\.valor), "\(c.nombre)")
            #expect(r.map(\.detalle) == c.esperado.map(\.detalle), "\(c.nombre)")
            #expect(r.map(\.etiqueta) == c.esperado.map(\.etiqueta), "\(c.nombre)")
        }
    }

    @Test func fechaRotaNoRompe() {
        #expect(SaludSemana.resumen(salud: [], recuperacion: [], hoy: "x", mostrarScore: true).isEmpty)
    }
}
