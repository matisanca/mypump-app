import XCTest
@testable import MyPumpReglas
import MyPumpModelos

/// Feedback del alumno: los mismos casos que Android y la web (`apps/shared/fixtures/feedback/`).
final class FeedbackTests: XCTestCase {
    private static let raiz = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../../../shared/fixtures/feedback").standardized
    private func json(_ n: String) throws -> JSONValue { try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: Self.raiz.appendingPathComponent("\(n).json"))) }
    private func lista(_ j: JSONValue?) -> [JSONValue] { if case .lista(let l)? = j { return l }; return [] }

    func testLaFiguraEsLaDelArchivoCompartido() throws {
        let j = try json("cuerpo")
        XCTAssertEqual(j["ancho"]?.comoNumero, FiguraCuerpo.ancho)
        XCTAssertEqual(j["alto"]?.comoNumero, FiguraCuerpo.alto)
        for v in FiguraCuerpo.Vista.allCases {
            let esperadas = lista(j["vistas"]?[v.rawValue])
            let piezas = FiguraCuerpo.piezas(v)
            XCTAssertEqual(piezas.count, esperadas.count, v.rawValue)
            for (p, e) in zip(piezas, esperadas) {
                XCTAssertEqual(p.zona, e["zona"]?.comoTexto)
                XCTAssertEqual(p.lado, e["lado"]?.comoTexto)
                XCTAssertEqual(p.forma.rawValue, e["forma"]?.comoTexto)
                XCTAssertEqual(p.a, lista(e["a"]).compactMap(\.comoNumero))
            }
        }
    }

    func testTodasLasZonasDelServidorEstanEnElDibujoYTienenNombre() {
        let dibujadas = Set(FiguraCuerpo.Vista.allCases.flatMap { FiguraCuerpo.piezas($0).compactMap(\.zona) })
        XCTAssertEqual(dibujadas, Set(ReglasMolestia.zonas.map(\.id)))
        XCTAssertEqual(ReglasMolestia.zonas.count, 17)
        for p in FiguraCuerpo.Vista.allCases.flatMap(FiguraCuerpo.piezas) where p.zona != nil {
            XCTAssertFalse(ReglasMolestia.nombreZona(p.zona!, lado: p.lado!).isEmpty)
            XCTAssertTrue(ReglasMolestia.lados.contains(p.lado!))
        }
    }

    func testCasosCompartidos() throws {
        let j = try json("casos")
        for c in lista(j["zonas"]) {
            XCTAssertEqual(ReglasMolestia.nombreZona(c["zona"]!.comoTexto!, lado: c["lado"]!.comoTexto!), c["nombre"]!.comoTexto!)
        }
        for c in lista(j["niveles"]) { let p = lista(c); XCTAssertEqual(ReglasMolestia.nivel(Int(p[0].comoNumero!)).id, Int(p[1].comoNumero!)) }
        for c in lista(j["fuerte"]) { let p = lista(c); XCTAssertEqual(JSONValue.bool(ReglasMolestia.esFuerte(Int(p[0].comoNumero!))), p[1]) }
        for c in lista(j["claves"]) { let p = lista(c); XCTAssertEqual(ReglasSupleEstado.clave(p[0].comoTexto!), p[1].comoTexto!) }
        for c in lista(j["toques"]) {
            let p = FiguraCuerpo.pieza(en: FiguraCuerpo.Vista(rawValue: c["vista"]!.comoTexto!)!, x: c["x"]!.comoNumero!, y: c["y"]!.comoNumero!)
            XCTAssertEqual(p?.zona, c["zona"]?.comoTexto, "\(c)")
            XCTAssertEqual(p?.lado, c["lado"]?.comoTexto, "\(c)")
        }
    }

    func testFilasDeSuplementos() throws {
        let s = try json("casos")["suple"]!
        let items = try JSONDecoder().decode([ItemSuplemento].self, from: JSONEncoder().encode(s["items"]!))
        var marcas: [String: ReglasSupleEstado.Estado] = [:]
        if case .objeto(let o)? = s["marcas"] { for (k, v) in o { marcas[k] = ReglasSupleEstado.Estado(rawValue: v.comoTexto!) } }
        let filas = ReglasSupleEstado.filas(items, marcas: marcas)
        XCTAssertEqual(filas.map(\.id), lista(s["filas"]).map { $0["id"]!.comoTexto! })
        XCTAssertEqual(filas.map(\.nombre), lista(s["filas"]).map { $0["nombre"]!.comoTexto! })
        XCTAssertEqual(filas.map { $0.estado?.rawValue }, lista(s["filas"]).map { $0["estado"]?.comoTexto })
        XCTAssertEqual(ReglasSupleEstado.resumen(filas), s["resumen"]!.comoTexto!)
        XCTAssertFalse(filas.contains { $0.id == "telmisartan" }, "un protector no se marca nunca")
    }

    func testDecodificaConTolerancia() throws {
        let m = try json("casos")["molestias"]!
        let e = try XCTUnwrap(EstadoFeedback(m["respuesta"]!))
        XCTAssertTrue(e.dueleHabilitado)
        XCTAssertFalse(e.supleHabilitado)
        XCTAssertEqual(e.molestias.map(\.id), lista(m["ids"]).map { $0.comoTexto! })
        if case .objeto(let o)? = m["por_ejercicio"] { for (k, v) in o { XCTAssertEqual(e.molestia(ejercicio: k)?.id, v.comoTexto, k) } }
        XCTAssertEqual(e.molestias[2].nombreZona, m["nombre_a3"]!.comoTexto!)
        XCTAssertNil(e.molestias[2].intensidad)
        XCTAssertEqual(e.marcas, ["zinc": .comprado])
        XCTAssertNil(EstadoFeedback(.lista([])))
    }

    func testBorrador() {
        var b = ReglasMolestia.Borrador()
        XCTAssertFalse(b.completa)
        b.zona = "hombro"; b.lado = "derecho"; b.desde = "hoy"; b.cuando = "al_subir"; b.tipo = "sordo"
        XCTAssertFalse(b.completa)
        b.intensidad = 5
        XCTAssertTrue(b.completa)
        XCTAssertEqual(b.nombreZona, "Hombro derecho")
        b.zona = "oreja"
        XCTAssertFalse(b.completa)
        XCTAssertEqual(ReglasMolestia.nota(String(repeating: "á", count: 600)).unicodeScalars.count, 500)
    }

    /// Lo que no puede aparecer en ningún texto que lee el alumno.
    func testTextosSinLoProhibido() {
        var textos = [TextosFeedback.dueleBoton, TextosFeedback.dueleTitulo, TextosFeedback.dueleIntro, TextosFeedback.dueleDonde, TextosFeedback.dueleDondeAyuda,
                      TextosFeedback.dueleFrente, TextosFeedback.dueleEspalda, TextosFeedback.dueleLado, TextosFeedback.dueleDesde, TextosFeedback.dueleCuando,
                      TextosFeedback.dueleTipo, TextosFeedback.dueleCuanto, TextosFeedback.dueleNota, TextosFeedback.dueleEnviar, TextosFeedback.dueleCorregir,
                      TextosFeedback.dueleFalta, TextosFeedback.dueleListoTitulo, TextosFeedback.dueleListo, TextosFeedback.dueleListoFuerte, TextosFeedback.dueleAvisada,
                      TextosFeedback.dueleResuelta, TextosFeedback.dueleCambiar, TextosFeedback.dueleSinRed, TextosFeedback.dueleTope, TextosFeedback.dueleError,
                      TextosFeedback.supleTitulo, TextosFeedback.supleAyuda, TextosFeedback.supleMarcar, TextosFeedback.supleNoConsigoAviso, TextosFeedback.supleError]
        textos += ReglasMolestia.ladosElegibles.map(\.texto) + ReglasMolestia.desde.map(\.texto) + ReglasMolestia.cuando.map(\.texto) + ReglasMolestia.tipo.map(\.texto) + ReglasMolestia.niveles.map(\.texto)
        textos += ReglasSupleEstado.Estado.allCases.flatMap { [$0.accion, $0.marcado] }
        textos += ReglasMolestia.zonas.flatMap { z in ReglasMolestia.lados.map { ReglasMolestia.nombreZona(z.id, lado: $0) } }
        let prohibido = try! NSRegularExpression(pattern: #"[:\-–—]|\bIA\b|inteligencia artificial|coach|entrenador|\bRIR\b|cerca del fallo|diagn[oó]stic|lesi[oó]n"#, options: [.caseInsensitive])
        for t in textos {
            XCTAssertEqual(prohibido.numberOfMatches(in: t, range: NSRange(t.startIndex..., in: t)), 0, t)
            XCTAssertNil(t.unicodeScalars.first { $0.properties.isEmojiPresentation }, t)
        }
    }
}
