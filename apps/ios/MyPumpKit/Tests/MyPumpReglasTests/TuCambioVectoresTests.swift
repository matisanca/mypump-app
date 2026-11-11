import XCTest
import Foundation
import MyPumpModelos
@testable import MyPumpReglas

/// Los vectores que comparte con Android y la web (`apps/shared/vectores/tucambio.json`).
final class TuCambioVectoresTests: XCTestCase {
    private func vectores() throws -> JSONValue {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("shared/vectores/tucambio.json")
        return try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url))
    }
    private func lista(_ j: JSONValue?) -> [JSONValue] { if case .lista(let l)? = j { l } else { [] } }
    private func numero(_ j: JSONValue?) -> Double? { if case .numero(let n)? = j { n } else { nil } }
    private func foto(_ j: JSONValue?) -> TuCambio.Foto? {
        guard let o = j?["origen"]?.comoTexto, let origen = TuCambio.Origen(rawValue: o), let s = j?["semana"]?.comoTexto else { return nil }
        return TuCambio.Foto(origen: origen, semana: s)
    }

    func testTextos() throws {
        let t = try vectores()["textos"]
        XCTAssertEqual(TuCambio.titulo, t?["titulo"]?.comoTexto)
        XCTAssertEqual(TuCambio.textoEspera, t?["textoEspera"]?.comoTexto)
        XCTAssertEqual(TuCambio.rotuloAntes, t?["rotuloAntes"]?.comoTexto)
        XCTAssertEqual(TuCambio.rotuloEstaSemana, t?["rotuloEstaSemana"]?.comoTexto)
        XCTAssertEqual(TuCambio.botonVer, t?["botonVer"]?.comoTexto)
        XCTAssertEqual(TuCambio.poseInicial, t?["poseInicial"]?.comoTexto)
        XCTAssertEqual(TuCambio.listoTitulo, t?["listoTitulo"]?.comoTexto)
    }

    func testCasos() throws {
        let v = try vectores()
        let actual = try XCTUnwrap(v["semanaActual"]?.comoTexto)
        let casos = lista(v["casos"])
        XCTAssertGreaterThan(casos.count, 15)
        for c in casos {
            let n = c["nombre"]?.comoTexto ?? "?"
            let fotos = lista(c["fotos"]).map { (semana: lista($0)[0].comoTexto ?? "", pose: lista($0)[1].comoTexto ?? "") }
            var inicio: [String: String] = [:]
            if case .objeto(let o)? = c["inicio"] { for (k, val) in o { inicio[k] = val.comoTexto } }
            let peso = lista(c["peso"]).map { PesoCorporal.Punto(fecha: lista($0)[0].comoTexto ?? "", kg: numero(lista($0)[1]) ?? 0) }
            let r = TuCambio.vista(fotos: fotos, inicio: inicio, semanaActual: actual, pose: c["pose"]?.comoTexto ?? "", peso: peso)
            let e = c["esperado"]
            XCTAssertEqual(r.modo.rawValue, e?["modo"]?.comoTexto, n)
            XCTAssertEqual(r.pose, e?["pose"]?.comoTexto, n)
            XCTAssertEqual(r.antes, foto(e?["antes"]), n)
            XCTAssertEqual(r.despues, foto(e?["despues"]), n)
            XCTAssertEqual(r.texto, e?["texto"]?.comoTexto, n)
            XCTAssertEqual(r.pie, e?["pie"]?.comoTexto, n)
            XCTAssertEqual(r.rotuloAntes, e?["rotuloAntes"]?.comoTexto, n)
            XCTAssertEqual(r.rotuloDespues, e?["rotuloDespues"]?.comoTexto, n)
            XCTAssertEqual(r.accesibleAntes, e?["accesibleAntes"]?.comoTexto, n)
            XCTAssertEqual(r.accesibleDespues, e?["accesibleDespues"]?.comoTexto, n)
            XCTAssertEqual(r.vacioDespues, e?["vacioDespues"]?.comoTexto, n)
        }
    }

    func testFechasYSinFoto() throws {
        let v = try vectores()
        for f in lista(v["fechas"]) { XCTAssertEqual(TuCambio.fecha(lista(f)[0].comoTexto ?? ""), lista(f)[1].comoTexto) }
        for f in lista(v["sinFoto"]) { XCTAssertEqual(TuCambio.sinFoto(lista(f)[0].comoTexto ?? ""), lista(f)[1].comoTexto) }
        for f in lista(v["sinOtra"]) { XCTAssertEqual(TuCambio.sinOtra(lista(f)[0].comoTexto ?? ""), lista(f)[1].comoTexto) }
        XCTAssertFalse(lista(v["sinOtra"]).isEmpty)
        for f in lista(v["fechaLocal"]) {
            let zona = try XCTUnwrap(TimeZone(identifier: f["zona"]?.comoTexto ?? ""))
            XCTAssertEqual(TuCambio.fechaLocal(f["iso"]?.comoTexto ?? "", zona: zona), f["esperado"]?.comoTexto, f["iso"]?.comoTexto ?? "")
        }
    }
}
