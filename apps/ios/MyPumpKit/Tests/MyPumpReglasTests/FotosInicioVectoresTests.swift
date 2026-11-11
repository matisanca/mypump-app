import XCTest
import Foundation
import MyPumpModelos
@testable import MyPumpReglas

/// Los vectores que comparte con Android y la web (`apps/shared/vectores/fotos_inicio.json`).
final class FotosInicioVectoresTests: XCTestCase {
    private func vectores() throws -> JSONValue {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("shared/vectores/fotos_inicio.json")
        return try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url))
    }
    private func lista(_ j: JSONValue?) -> [JSONValue] { if case .lista(let l)? = j { l } else { [] } }
    private func textos(_ j: JSONValue?) -> [String] { lista(j).compactMap(\.comoTexto) }
    private func numero(_ j: JSONValue?) -> Double { if case .numero(let n)? = j { n } else { -1 } }
    private func entero(_ j: JSONValue?) -> Int { Int(numero(j)) }
    private func enteroONil(_ j: JSONValue?) -> Int? { if case .numero(let n)? = j { Int(n) } else { nil } }

    func testPosesConsejosYConstantes() throws {
        let v = try vectores()
        XCTAssertEqual(FotosInicio.poses.map(\.clave), lista(v["poses"]).compactMap { $0["clave"]?.comoTexto })
        XCTAssertEqual(FotosInicio.poses.map(\.nombre), lista(v["poses"]).compactMap { $0["nombre"]?.comoTexto })
        XCTAssertEqual(FotosInicio.poses.map(\.instruccion), lista(v["poses"]).compactMap { $0["instruccion"]?.comoTexto })
        XCTAssertEqual(FotosInicio.consejos, textos(v["consejos"]))
        XCTAssertEqual(FotosInicio.maxPx, entero(v["maxPx"]))
        XCTAssertEqual(FotosInicio.calidad, numero(v["calidad"]))
        XCTAssertEqual(FotosInicio.minLado, entero(v["minLado"]))
        XCTAssertEqual(FotosInicio.minLadoMotivacion, entero(v["minLadoMotivacion"]))
        XCTAssertEqual(FotosInicio.maxMotivacion, entero(v["maxMotivacion"]))
        XCTAssertEqual(FotosInicio.maxNota, entero(v["maxNota"]))
        XCTAssertEqual(FotosInicio.brilloMinimo, numero(v["brilloMinimo"]))
        XCTAssertEqual(FotosInicio.nitidezMinima, numero(v["nitidezMinima"]))
        XCTAssertEqual(FotosInicio.diasVieja, entero(v["diasVieja"]))
        XCTAssertEqual(FotosInicio.ladoAnalisis, entero(v["ladoAnalisis"]))
    }

    func testTextos() throws {
        let v = try vectores()
        guard case .objeto(let t)? = v["textos"] else { return XCTFail() }
        let enCodigo: [String: String] = [
            "tarjetaTitulo": TextosFotosInicio.tarjetaTitulo, "tarjetaBajada": TextosFotosInicio.tarjetaBajada, "tarjetaEmpezar": TextosFotosInicio.tarjetaEmpezar,
            "tarjetaSeguir": TextosFotosInicio.tarjetaSeguir, "tarjetaLista": TextosFotosInicio.tarjetaLista, "entradaMisDatos": TextosFotosInicio.entradaMisDatos,
            "privacidad": TextosFotosInicio.privacidad, "consejosTitulo": TextosFotosInicio.consejosTitulo, "consejoLuz": TextosFotosInicio.consejoLuz,
            "consejoDistancia": TextosFotosInicio.consejoDistancia, "consejoAltura": TextosFotosInicio.consejoAltura, "consejoRopa": TextosFotosInicio.consejoRopa,
            "consejoFondo": TextosFotosInicio.consejoFondo, "consejoEspejo": TextosFotosInicio.consejoEspejo, "consejoTemporizador": TextosFotosInicio.consejoTemporizador,
            "consejoPostura": TextosFotosInicio.consejoPostura, "poseFrente": TextosFotosInicio.poseFrente, "posePerfil": TextosFotosInicio.posePerfil,
            "poseEspalda": TextosFotosInicio.poseEspalda, "instruccionFrente": TextosFotosInicio.instruccionFrente, "instruccionPerfil": TextosFotosInicio.instruccionPerfil,
            "instruccionEspalda": TextosFotosInicio.instruccionEspalda, "falta": TextosFotosInicio.falta, "lista": TextosFotosInicio.lista,
            "subiendo": TextosFotosInicio.subiendo, "esperandoSenal": TextosFotosInicio.esperandoSenal, "botonFoto": TextosFotosInicio.botonFoto,
            "botonUsar": TextosFotosInicio.botonUsar, "botonUsarIgual": TextosFotosInicio.botonUsarIgual, "botonOtra": TextosFotosInicio.botonOtra,
            "seVeBien": TextosFotosInicio.seVeBien, "problemaChica": TextosFotosInicio.problemaChica, "problemaApaisada": TextosFotosInicio.problemaApaisada,
            "problemaOscura": TextosFotosInicio.problemaOscura, "problemaMovida": TextosFotosInicio.problemaMovida, "ilegible": TextosFotosInicio.ilegible,
            "fotoRechazada": TextosFotosInicio.fotoRechazada, "noSeGuardo": TextosFotosInicio.noSeGuardo, "sinSenal": TextosFotosInicio.sinSenal,
            "listoTitulo": TextosFotosInicio.listoTitulo, "listoBajada": TextosFotosInicio.listoBajada, "repetir": TextosFotosInicio.repetir,
            "motivacionTitulo": TextosFotosInicio.motivacionTitulo, "opcional": TextosFotosInicio.opcional, "motivacionBajada": TextosFotosInicio.motivacionBajada,
            "motivacionAgregar": TextosFotosInicio.motivacionAgregar, "motivacionNota": TextosFotosInicio.motivacionNota, "motivacionGuardar": TextosFotosInicio.motivacionGuardar,
            "motivacionGuardada": TextosFotosInicio.motivacionGuardada, "motivacionTope": TextosFotosInicio.motivacionTope, "borrarFoto": TextosFotosInicio.borrarFoto,
            "notaSinSenal": TextosFotosInicio.notaSinSenal, "notaError": TextosFotosInicio.notaError, "borrarSinSenal": TextosFotosInicio.borrarSinSenal, "cerrar": TextosFotosInicio.cerrar, "siguiente": TextosFotosInicio.siguiente,
            "listoBoton": TextosFotosInicio.listoBoton, "listoTeclado": TextosFotosInicio.listoTeclado,
        ]
        XCTAssertEqual(Set(enCodigo.keys), Set(t.keys))
        for (k, s) in enCodigo {
            XCTAssertEqual(t[k]?.comoTexto, s, k)
            // Las fotos son privadas: solo se nombra a Mati.
            XCTAssertNil(s.range(of: #"\bIA\b|inteligencia|coach"#, options: [.regularExpression, .caseInsensitive]), s)
        }
        for c in lista(v["plurales"]) {
            let n = entero(c["n"])
            XCTAssertEqual(TextosFotosInicio.faltan(n), c["faltan"]?.comoTexto)
            XCTAssertEqual(TextosFotosInicio.cuenta(n), c["cuenta"]?.comoTexto)
            XCTAssertEqual(TextosFotosInicio.problemaVieja(n), c["vieja"]?.comoTexto)
        }
        guard case .objeto(let p)? = v["textosProblema"] else { return XCTFail() }
        XCTAssertEqual(Set(p.keys).union(["vieja"]), Set(FotosInicio.Problema.allCases.map(\.rawValue)))
        for (k, s) in p { XCTAssertEqual(FotosInicio.Problema(rawValue: k).map { FotosInicio.texto($0) }, s.comoTexto) }
        XCTAssertEqual(FotosInicio.texto(.vieja, dias: 9), TextosFotosInicio.problemaVieja(9))
    }

    func testLumaYMedida() throws {
        let v = try vectores()
        for c in lista(v["luma"]) { XCTAssertEqual(FotosInicio.luma(r: entero(c["r"]), g: entero(c["g"]), b: entero(c["b"])), entero(c["l"])) }
        XCTAssertGreaterThan(lista(v["medir"]).count, 10)
        for c in lista(v["medir"]) {
            let luma = lista(c["luma"]).map { UInt8(entero($0)) }
            let m = FotosInicio.medir(luma: luma, ancho: entero(c["ancho"]), alto: entero(c["alto"]), paso: enteroONil(c["paso"]))
            XCTAssertEqual(m.brillo, numero(c["brillo"]), accuracy: 1e-9, c["caso"]?.comoTexto ?? "")
            XCTAssertEqual(m.nitidez, numero(c["nitidez"]), accuracy: 1e-9, c["caso"]?.comoTexto ?? "")
        }
        XCTAssertEqual(FotosInicio.medir(luma: [1, 2], ancho: 4, alto: 4), FotosInicio.Medida(brillo: 0, nitidez: 0))   // faltan datos: no se cuelga
    }

    func testProblemas() throws {
        for c in lista(try vectores()["problemas"]) {
            let p = FotosInicio.problemas(pose: c["pose"]?.comoTexto ?? "", ancho: entero(c["ancho"]), alto: entero(c["alto"]),
                                          medida: .init(brillo: numero(c["brillo"]), nitidez: numero(c["nitidez"])), dias: enteroONil(c["dias"]))
            XCTAssertEqual(p.map(\.rawValue), textos(c["problemas"]), "\(c)")
            XCTAssertEqual(FotosInicio.bloquea(p), c["bloquea"] == .bool(true))
        }
    }

    func testSubida() throws {
        for c in lista(try vectores()["subida"]) {
            let s = FotosInicio.clasificarSubida(status: entero(c["status"]), ok: c["ok"] == .bool(true))
            XCTAssertEqual(s.accion.rawValue, c["accion"]?.comoTexto, "\(c)")
            XCTAssertEqual(s.aviso?.rawValue, c["aviso"]?.comoTexto, "\(c)")
            XCTAssertEqual(s.refrescar, c["refrescar"] == .bool(true), "\(c)")
        }
    }

    func testElSet() throws {
        let v = try vectores()
        for c in lista(v["faltan"]) {
            XCTAssertEqual(FotosInicio.faltan(enServidor: Set(textos(c["enServidor"])), enCola: Set(textos(c["enCola"]))), textos(c["faltan"]))
        }
        for c in lista(v["siguiente"]) {
            XCTAssertEqual(FotosInicio.siguiente(despuesDe: c["pose"]?.comoTexto ?? "", faltan: textos(c["faltan"])), c["siguiente"]?.comoTexto, "\(c)")
        }
        for c in lista(v["motivacion"]) {
            XCTAssertEqual(FotosInicio.puedeAgregarMotivacion(enServidor: entero(c["servidor"]), enCola: entero(c["cola"]), maximo: entero(c["maximo"])), c["puede"] == .bool(true))
        }
        for c in lista(v["notas"]) { XCTAssertEqual(FotosInicio.notaRecortada(c["s"]?.comoTexto ?? ""), c["n"]?.comoTexto) }
        let iso = ISO8601DateFormatter()
        for c in lista(v["dias"]) {
            XCTAssertEqual(FotosInicio.dias(desde: iso.date(from: c["tomada"]?.comoTexto ?? "")!, hasta: iso.date(from: c["ahora"]?.comoTexto ?? "")!), entero(c["dias"]))
        }
    }

    func testDecodificar() throws {
        for c in lista(try vectores()["decodificar"]) {
            let e = EstadoFotosInicio(c["j"] ?? .null)
            XCTAssertEqual(e != nil, c["habilitado"] == .bool(true))
            guard let e else { continue }
            XCTAssertEqual(e.poses.sorted(), textos(c["poses"]))
            XCTAssertEqual(e.deMotivacion.count, entero(c["motivacion"]))
            XCTAssertEqual(e.nota, c["nota"]?.comoTexto)
            XCTAssertEqual(e.completo, c["completo"] == .bool(true))
            XCTAssertEqual(e.maxMotivacion, entero(c["maxMotivacion"]))
        }
    }

    func testSiluetas() throws {
        let v = try vectores()
        XCTAssertEqual(lista(v["siluetas"]?["caja"]).map { numero($0) }, [SiluetasFotosInicio.ancho, SiluetasFotosInicio.alto])
        for pose in FotosInicio.poses {
            let s = try XCTUnwrap(SiluetasFotosInicio.de(pose.clave))
            XCTAssertEqual(s.contorno, v["siluetas"]?[pose.clave]?["contorno"]?.comoTexto)
            XCTAssertEqual(s.detalle, v["siluetas"]?[pose.clave]?["detalle"]?.comoTexto)
            let ordenes = SiluetasFotosInicio.ordenes(s.contorno)
            XCTAssertEqual(ordenes.count, s.contorno.filter { "MCZ".contains($0) }.count)
            XCTAssertEqual(ordenes.last, .cerrar)
            // Todo adentro de la caja.
            for o in ordenes + SiluetasFotosInicio.ordenes(s.detalle) {
                let puntos: [(Double, Double)] = switch o {
                case .mover(let x, let y): [(x, y)]
                case .curva(let a, let b, let c, let d, let x, let y): [(a, b), (c, d), (x, y)]
                case .cerrar: []
                }
                for (x, y) in puntos { XCTAssertTrue((0...SiluetasFotosInicio.ancho).contains(x) && (0...SiluetasFotosInicio.alto).contains(y), "\(pose.clave) \(x),\(y)") }
            }
        }
        XCTAssertNil(SiluetasFotosInicio.de("motivacion"))
        XCTAssertEqual(SiluetasFotosInicio.ordenes("M1 2 C1 2 3 4 5 6 Z X9 M3"), [.mover(1, 2), .curva(1, 2, 3, 4, 5, 6), .cerrar])
    }
}
