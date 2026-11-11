import XCTest
import Foundation
import MyPumpModelos
@testable import MyPumpReglas

/// Los vectores que comparte con Android y la web (`apps/shared/vectores/controles.json`): textos, título, fechas y lo que se
/// muestra en Estudios, arriba de la primera pestaña y en «Tu recorrido».
final class ControlesVectoresTests: XCTestCase {
    private func vectores() throws -> JSONValue {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("shared/vectores/controles.json")
        return try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url))
    }
    private func lista(_ j: JSONValue?) -> [JSONValue] { if case .lista(let l)? = j { l } else { [] } }
    private func texto(_ j: JSONValue?) -> String? { if case .texto(let s)? = j { s } else { nil } }

    func testTextos() throws {
        let v = try vectores()
        guard case .objeto(let t)? = v["textos"] else { return XCTFail() }
        typealias T = TextosControles
        let enCodigo: [String: String] = [
            "cejaInicio": T.cejaInicio, "tituloInicio": T.tituloInicio, "verMisEstudios": T.verMisEstudios, "notaProgramado": T.notaProgramado,
            "notaOrdenes": T.notaOrdenes, "tituloPorDefecto": T.tituloPorDefecto, "hitosTitulo": T.hitosTitulo, "hitoProximo": T.hitoProximo,
            "hitoRecibido": T.hitoRecibido, "hitoVisto": T.hitoVisto, "notaOrdenesSinLista": T.notaOrdenesSinLista,
        ]
        XCTAssertEqual(Set(enCodigo.keys), Set(t.keys))
        for (k, s) in enCodigo { XCTAssertEqual(t[k]?.comoTexto, s, k) }
        XCTAssertEqual(Double(Controles.tituloMax), v["tituloMax"]?.comoNumero)
    }

    func testTitulo() throws {
        for c in lista(try vectores()["titulo"]) { XCTAssertEqual(Controles.titulo(texto(c["entra"])), texto(c["sale"]), "\(c["entra"] ?? .null)") }
    }

    func testCuando() throws {
        for c in lista(try vectores()["cuando"]) {
            let d = try XCTUnwrap(Estudios.Dia(texto(c["fecha"])))
            XCTAssertEqual(Controles.cuando(d, hoy: Estudios.Dia(texto(c["hoy"]))), texto(c["texto"]))
        }
    }

    func testCasos() throws {
        let casos = lista(try vectores()["casos"])
        XCTAssertGreaterThanOrEqual(casos.count, 20)
        for c in casos {
            let n = texto(c["nombre"]) ?? "?"
            let e = EstadoControles(c["respuesta"] ?? .null)
            let sale = c["sale"]
            let est = e.flatMap { Controles.proximoParaEstudios($0, hayOrdenes: c["hayOrdenes"] != .bool(false)) }
            if case .objeto(let o)? = sale?["estudios"] {
                XCTAssertEqual(est?.titulo, o["titulo"]?.comoTexto, n)
                XCTAssertEqual(est?.cuando, o["cuando"]?.comoTexto, n)
                XCTAssertEqual(est?.nota, texto(o["nota"]), n)
            } else { XCTAssertNil(est, n) }
            let ini = e.flatMap { Controles.tarjetaInicio($0, hoyTelefono: Estudios.Dia(texto(c["hoyTelefono"]))) }
            if case .objeto(let o)? = sale?["inicio"] {
                XCTAssertEqual(ini, Controles.TarjetaInicio(titulo: texto(o["titulo"]) ?? "", cuando: texto(o["cuando"]) ?? "", nota: texto(o["nota"]) ?? "",
                                                            boton: texto(o["boton"]) ?? ""), n)
            } else { XCTAssertNil(ini, n) }
            let hitos = e.map(Controles.hitos) ?? []
            let esperados = lista(sale?["hitos"]).map { Controles.Hito(titulo: texto($0["titulo"]) ?? "", cuando: texto($0["cuando"]) ?? "", estado: texto($0["estado"]) ?? "") }
            XCTAssertEqual(hitos, esperados, n)
        }
    }

    /// Nada de lo que lee el alumno nombra el ciclo, fármacos ni «IA».
    func testNingunTextoNombraElCiclo() throws {
        var todos: [String] = []
        func juntar(_ j: JSONValue) {
            switch j {
            case .texto(let s): todos.append(s)
            case .lista(let l): l.forEach(juntar)
            case .objeto(let o): o.values.forEach(juntar)
            default: break
            }
        }
        let v = try vectores()
        juntar(v["textos"] ?? .null)
        for c in lista(v["casos"]) { juntar(c["sale"] ?? .null) }
        for s in todos { XCTAssertEqual(Controles.titulo(s.count > 60 ? String(s.prefix(60)) : s) == TextosControles.tituloPorDefecto && s != TextosControles.tituloPorDefecto, false, s) }
    }
}
