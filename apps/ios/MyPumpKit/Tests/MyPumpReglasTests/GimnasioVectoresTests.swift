import XCTest
import Foundation
import MyPumpModelos
@testable import MyPumpReglas

/// Los vectores que comparte con Android (`apps/shared/vectores/gimnasio.json`).
final class GimnasioVectoresTests: XCTestCase {
    private func vectores() throws -> JSONValue {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("shared/vectores/gimnasio.json")
        return try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url))
    }
    private func lista(_ j: JSONValue?) -> [JSONValue] { if case .lista(let l)? = j { l } else { [] } }
    private func textos(_ j: JSONValue?) -> [String] { lista(j).compactMap(\.comoTexto) }
    private func entero(_ j: JSONValue?) -> Int { if case .numero(let n)? = j { Int(n) } else { -1 } }
    private func bool(_ j: JSONValue?) -> Bool { j == .bool(true) }

    func testZonasYConstantes() throws {
        let v = try vectores()
        XCTAssertEqual(Gimnasio.zonas.map(\.clave), lista(v["zonas"]).compactMap { $0["clave"]?.comoTexto })
        XCTAssertEqual(Gimnasio.zonas.map(\.nombre), lista(v["zonas"]).compactMap { $0["nombre"]?.comoTexto })
        XCTAssertEqual(Gimnasio.topeFotos, entero(v["topeFotos"]))
        XCTAssertEqual(Gimnasio.maxNota, entero(v["maxNota"]))
        XCTAssertEqual(Gimnasio.maxPx, entero(v["maxPx"]))
    }

    func testTextos() throws {
        let v = try vectores()
        guard case .objeto(let t)? = v["textos"] else { return XCTFail() }
        let enCodigo: [String: String] = [
            "tarjetaTitulo": TextosGimnasio.tarjetaTitulo, "confirmarTarjeta": TextosGimnasio.confirmarTarjeta, "entradaMisDatos": TextosGimnasio.entradaMisDatos, "inicioTitulo": TextosGimnasio.inicioTitulo,
            "inicioBajada": TextosGimnasio.inicioBajada, "avisoTerceros": TextosGimnasio.avisoTerceros, "botonEmpezar": TextosGimnasio.botonEmpezar,
            "consejoPermiso": TextosGimnasio.consejoPermiso, "noHay": TextosGimnasio.noHay, "noHayCorto": TextosGimnasio.noHayCorto,
            "sinFotos": TextosGimnasio.sinFotos, "opcional": TextosGimnasio.opcional, "consejoCamara": TextosGimnasio.consejoCamara,
            "agregarFoto": TextosGimnasio.agregarFoto, "borrarFoto": TextosGimnasio.borrarFoto, "subiendo": TextosGimnasio.subiendo,
            "esperandoSenal": TextosGimnasio.esperandoSenal, "revisarYEnviar": TextosGimnasio.revisarYEnviar, "tope": TextosGimnasio.tope,
            "fotoRechazada": TextosGimnasio.fotoRechazada, "noSeGuardo": TextosGimnasio.noSeGuardo, "sinSenal": TextosGimnasio.sinSenal,
            "revisarTitulo": TextosGimnasio.revisarTitulo, "notaPlaceholder": TextosGimnasio.notaPlaceholder, "botonEnviar": TextosGimnasio.botonEnviar,
            "enviandoSeguir": TextosGimnasio.enviandoSeguir, "sinNovedad": TextosGimnasio.sinNovedad, "errorGenerico": TextosGimnasio.errorGenerico,
            "recibido": TextosGimnasio.recibido, "sinCambios": TextosGimnasio.sinCambios, "anterior": TextosGimnasio.anterior,
            "siguiente": TextosGimnasio.siguiente, "noSe": TextosGimnasio.noSe, "si": TextosGimnasio.si, "no": TextosGimnasio.no,
            "noPuedoFoto": TextosGimnasio.noPuedoFoto, "marcarTodas": TextosGimnasio.marcarTodas, "elegirKilos": TextosGimnasio.elegirKilos,
            "kilosInvalidos": TextosGimnasio.kilosInvalidos, "faltaAlgo": TextosGimnasio.faltaAlgo, "yaNoEsta": TextosGimnasio.yaNoEsta,
            "cambieDeGimnasio": TextosGimnasio.cambieDeGimnasio, "marcarLoQueNoEsta": TextosGimnasio.marcarLoQueNoEsta,
        ]
        XCTAssertEqual(Set(enCodigo.keys), Set(t.keys))
        for (k, s) in enCodigo { XCTAssertEqual(t[k]?.comoTexto, s, k) }
        for c in lista(v["plurales"]) {
            let n = entero(c["n"])
            XCTAssertEqual(TextosGimnasio.cuentaFotos(n), c["fotos"]?.comoTexto)
            XCTAssertEqual(TextosGimnasio.faltanZonas(n), c["faltan"]?.comoTexto)
            XCTAssertEqual(TextosGimnasio.necesitamosFotos(n), c["necesitamos"]?.comoTexto)
        }
        XCTAssertEqual(TextosGimnasio.adaptadoPorMati("12/11"), "Adaptado por Mati el 12/11")
        XCTAssertFalse(TextosGimnasio.adaptadoPorMati("").lowercased().contains("inteligencia"))
    }

    func testZonasCompletasYTope() throws {
        let v = try vectores()
        for c in lista(v["faltantes"]) {
            XCTAssertEqual(Gimnasio.zonasFaltantes(conFotos: Set(textos(c["conFotos"])), noHay: Set(textos(c["noHay"])), modo: c["modo"]!.comoTexto!), textos(c["faltan"]))
        }
        for c in lista(v["puedeEnviar"]) {
            XCTAssertEqual(Gimnasio.puedeEnviar(modo: c["modo"]!.comoTexto!, conFotos: Set(textos(c["conFotos"])), noHay: Set(textos(c["noHay"])), quitar: Set(textos(c["quitar"]))), bool(c["puede"]))
        }
        for c in lista(v["tope"]) {
            XCTAssertEqual(Gimnasio.restan(enServidor: entero(c["servidor"]), enCola: entero(c["cola"])), entero(c["restan"]))
            XCTAssertEqual(Gimnasio.puedeAgregar(enServidor: entero(c["servidor"]), enCola: entero(c["cola"])), bool(c["puede"]))
        }
    }

    func testPantallasYEntradas() throws {
        let v = try vectores()
        for c in lista(v["pantalla"]) {
            XCTAssertEqual(Gimnasio.pantalla(abierta: c["abierta"]?.comoTexto, hayVigente: bool(c["vigente"])).rawValue, c["pantalla"]?.comoTexto)
        }
        for c in lista(v["tarjeta"]) {
            XCTAssertEqual(Gimnasio.tarjetaVisible(habilitado: bool(c["habilitado"]), abierta: c["abierta"]?.comoTexto, hayVigente: bool(c["vigente"])), bool(c["visible"]))
        }
        for c in lista(v["entrada"]) {
            XCTAssertEqual(Gimnasio.entradaVisible(habilitado: bool(c["habilitado"]), hayVigente: bool(c["vigente"])), bool(c["visible"]))
        }
    }

    func testClasificacionDeSubidas() throws {
        for c in lista(try vectores()["subida"]) {
            let s = Gimnasio.clasificarSubida(status: entero(c["status"]), ok: bool(c["ok"]))
            XCTAssertEqual(s.accion.rawValue, c["accion"]?.comoTexto, "\(entero(c["status"]))")
            XCTAssertEqual(s.refrescar, bool(c["refrescar"]))
            XCTAssertEqual(s.aviso?.rawValue, c["aviso"]?.comoTexto)
        }
    }

    func testRespuestas() throws {
        let v = try vectores()
        for c in lista(v["respuestas"]) {
            let p = try XCTUnwrap(PreguntaGimnasio(c["p"]!))
            XCTAssertEqual(Gimnasio.respuestaValida(p, c["v"]!), bool(c["valida"]), "\(p.id) \(c["v"]!)")
        }
        let e = v["paraEnviar"]!
        let ps = lista(e["preguntas"]).compactMap(PreguntaGimnasio.init)
        guard case .objeto(let b)? = e["borrador"], case .objeto(let r)? = e["resultado"] else { return XCTFail() }
        XCTAssertEqual(Gimnasio.respuestasParaEnviar(ps, b), r)
        XCTAssertEqual(Gimnasio.fotosPedidas(ps, b), entero(e["fotosPedidas"]))
        for c in lista(v["kilos"]) {
            var n: Double?; if case .numero(let x)? = c["n"] { n = x }
            XCTAssertEqual(Gimnasio.kilos(c["s"]!.comoTexto!), n)
        }
    }

    func testFechas() throws {
        for c in lista(try vectores()["fechas"]) {
            XCTAssertEqual(Gimnasio.fechaCorta(c["iso"]?.comoTexto, zona: TimeZone(identifier: c["zona"]!.comoTexto!)!), c["texto"]?.comoTexto)
        }
    }

    func testDecodificacionTolerante() throws {
        for c in lista(try vectores()["decodificar"]) {
            let e = EstadoGimnasio(c["j"]!)
            XCTAssertEqual(e != nil, bool(c["habilitado"]))
            guard let e else { continue }
            XCTAssertEqual(e.consentimientoVersion, c["version"]?.comoTexto)
            XCTAssertEqual(e.consentimientoAceptado, bool(c["aceptado"]))
            XCTAssertEqual(e.abierta?.estado, c["abierta"]?.comoTexto)
            if c["equipos"] != nil { XCTAssertEqual(e.vigente?.equipos.count, entero(c["equipos"])); XCTAssertEqual(e.vigente?.equipos.last?.cantidad, entero(c["cantidad"])) }
            if c["preguntas"] != nil { XCTAssertEqual(e.abierta?.preguntas.count, entero(c["preguntas"])) }
        }
    }
}
