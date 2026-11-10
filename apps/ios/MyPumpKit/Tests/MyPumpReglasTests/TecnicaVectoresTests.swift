import XCTest
import Foundation
import MyPumpModelos
@testable import MyPumpReglas

/// Los vectores que comparte con Android (`apps/shared/vectores/tecnica.json`).
final class TecnicaVectoresTests: XCTestCase {
    private func vectores() throws -> JSONValue {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("shared/vectores/tecnica.json")
        return try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url))
    }
    private func lista(_ j: JSONValue?) -> [JSONValue] { if case .lista(let l)? = j { l } else { [] } }
    private func num(_ j: JSONValue?) -> Double { if case .numero(let n)? = j { n } else { -1 } }

    func testConstantesYTextos() throws {
        let v = try vectores()
        XCTAssertEqual(Tecnica.consentimientoVigente, v["consentimiento"]?.comoTexto)
        XCTAssertEqual(Double(Tecnica.maxNota), num(v["maxNota"]))
        let f = TopesTecnica()
        XCTAssertEqual(f.duracionMinS, num(v["topesDeFabrica"]?["duracion_min_s"]))
        XCTAssertEqual(f.duracionMaxS, num(v["topesDeFabrica"]?["duracion_max_s"]))
        XCTAssertEqual(Double(f.bytesMax), num(v["topesDeFabrica"]?["bytes_max"]))
        guard case .objeto(let t)? = v["textos"] else { return XCTFail() }
        XCTAssertEqual(TextosTecnica.todos, t.compactMapValues(\.comoTexto))
        for c in lista(v["plantillas"]) {
            let e = c["texto"]?.comoTexto
            switch c["clave"]?.comoTexto {
            case "tituloDevolucion": XCTAssertEqual(TextosTecnica.tituloDevolucion(c["valor"]!.comoTexto!), e)
            case "revisadoEl": XCTAssertEqual(TextosTecnica.revisadoEl(c["valor"]!.comoTexto!), e)
            case "videoListo": XCTAssertEqual(TextosTecnica.videoListo(Int(num(c["n"]))), e)
            default: XCTFail()
            }
        }
    }

    func testSubidaYValidacion() throws {
        let v = try vectores()
        for c in lista(v["subida"]) {
            let s = Tecnica.clasificarSubida(status: Int(num(c["status"])), ok: c["ok"] == .bool(true), error: c["error"]?.comoTexto)
            XCTAssertEqual(s.accion.rawValue, c["accion"]?.comoTexto, "\(c)")
            XCTAssertEqual(s.rechazo?.rawValue, c["rechazo"]?.comoTexto, "\(c)")
        }
        for c in lista(v["validar"]) {
            XCTAssertEqual(Tecnica.validar(duracion: num(c["duracion"]), bytes: Int64(num(c["bytes"])), topes: TopesTecnica())?.rawValue, c["rechazo"]?.comoTexto, "\(c)")
        }
    }

    func testDecodificarTolerante() throws {
        let v = try vectores()
        for c in lista(v["decodificar"]) {
            let e = EstadoTecnica(c["json"]!)
            if c["nulo"] == .bool(true) { XCTAssertNil(e); continue }
            let est = try XCTUnwrap(e)
            XCTAssertEqual(est.envios.map(\.id), lista(c["ids"]).compactMap(\.comoTexto))
            XCTAssertEqual(est.consentimientoAceptado, c["aceptado"] == .bool(true))
            XCTAssertEqual(est.topes.duracionMaxS, num(c["duracionMax"]))
            XCTAssertEqual(Double(est.topes.bytesMax), num(c["bytesMax"]))
            if case .lista(let t)? = c["titulos"] {
                let d = try XCTUnwrap(est.envios.first?.devolucion)
                XCTAssertEqual(d.correcciones.map(\.titulo), t.compactMap(\.comoTexto))
                XCTAssertEqual(d.correcciones.map(\.momentoS), lista(c["momentos"]).map { if case .numero(let n) = $0 { n } else { nil } })
                XCTAssertEqual(Double(d.bien.count), num(c["bien"]))
                XCTAssertEqual(Double(d.noEvaluable.count), num(c["noEvaluable"]))
                XCTAssertEqual(d.otroVideo, c["otroVideo"]?.comoTexto)
            }
        }
    }

    func testEjerciciosParaElegir() {
        let a = Ejercicio(id: "1", nombre: "Remo", tipo: nil, catalogoSlug: "remo")
        let dias = [Dia(bloques: [Bloque(ejercicios: [a, Ejercicio(id: "2", nombre: "Trote", tipo: "cardio"), Ejercicio(id: "3", nombre: "REMO")])])]
        XCTAssertEqual(Tecnica.ejerciciosParaElegir(dias).map(\.id), ["1"])
        XCTAssertEqual(Tecnica.slug(a), "remo")
    }
}
