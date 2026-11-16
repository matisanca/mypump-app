import XCTest
import Foundation
import MyPumpModelos
@testable import MyPumpReglas

/// Por qué no cuenta una toma y cómo se le dice al alumno (`apps/shared/vectores/presion_no_cuenta.json`), y los textos del aviso
/// del reposo. Gemelo de PresionNoCuentaTest.kt. La regla clínica (5 minutos sentado obligatorios) no cambia: `texto` es lo que ya
/// daba `Presion.evaluarSesion`.
final class PresionNoCuentaTests: XCTestCase {
    private func vectores() throws -> JSONValue {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("shared/vectores/presion_no_cuenta.json")
        return try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url))
    }
    private func lista(_ j: JSONValue?) -> [JSONValue] { if case .lista(let l)? = j { l } else { [] } }

    func testSeRecorreTodoElArchivo() throws {
        guard case .objeto(let o) = try vectores() else { return XCTFail("no es un objeto") }
        XCTAssertEqual(Set(o.keys), ["_", "casos", "propios"])
        XCTAssertEqual(lista(o["casos"]).count, 16)
    }

    func testCadaCasoDaElMotivoYElTexto() throws {
        for c in lista(try vectores()["casos"]) {
            let nombre = c["nombre"]?.comoTexto ?? ""
            let s = Presion.Sesion(c["entrada"]!)
            let sale = c["sale"]!
            XCTAssertEqual(Presion.evaluarSesion(s).texto, sale["texto"]?.comoTexto, "\(nombre): texto")
            let motivos = Presion.motivosNoCuenta(s)
            XCTAssertEqual(motivos, lista(sale["motivos"]).compactMap(\.comoTexto), "\(nombre): motivos")
            if let mensaje = sale["mensaje"]?.comoTexto {
                XCTAssertEqual(TextosPresion.T.noCuentaPor(motivos), mensaje, "\(nombre): mensaje")
            } else {
                XCTAssertEqual(Presion.evaluarSesion(s).texto, "ninguno", "\(nombre): sin mensaje solo si cuenta")
            }
        }
    }

    /// Cada motivo, solo: el texto nombra lo que pasó y nada de lo que no pasó (lo que confundió a un alumno que no tomó café).
    func testCadaMotivoNombraSoloLoSuyo() {
        let propio = [
            "reposo": "No esperaste los 5 minutos sentado.",
            "cafeina": "tomaste café, mate, energizante o preentreno",
            "fumo": "fumaste o vapeaste",
            "comida": "comiste",
            "ejercicio": "Entrenaste en la última hora.",
            "entreno_entre_dosis": "Entrenaste entre la dosis y la toma.",
        ]
        for (m, frase) in propio {
            let t = TextosPresion.T.noCuentaPor([m])
            XCTAssertTrue(t.hasPrefix("Esta toma no cuenta."), t)
            XCTAssertTrue(t.hasSuffix("Hacé otra toma otro día."), t)
            XCTAssertTrue(t.contains(frase), "\(m): «\(t)»")
            XCTAssertTrue(t.contains("La próxima"), "\(m): dice qué hacer la próxima vez")
            for (otro, f) in propio where otro != m { XCTAssertFalse(t.contains(f), "\(m) nombra \(otro): «\(t)»") }
            if m != "cafeina" { XCTAssertFalse(t.contains("café"), "\(m) habla de café: «\(t)»") }
        }
        XCTAssertEqual(TextosPresion.T.noCuentaPor([]), "Esta toma no cuenta. Hacé otra toma otro día.")
    }

    /// El reposo salteado con el botón es exactamente lo que marca la sesión: no cuenta y dice por qué.
    func testBotonDelReposoSalteado() {
        let base = Presion.Sesion(tipo: "estandar", tomas: [Presion.Toma(orden: 1, posicion: "sentado", sis: 124, dia: 78, pulso: 62)])
        var salteado = base
        salteado.reposoCumplido = false
        salteado.temporizadorSalteado = true
        let ev = Presion.evaluarSesion(salteado)
        XCTAssertFalse(ev.cuenta)
        XCTAssertEqual(ev.motivoExclusion, "condicion_incumplida")
        XCTAssertEqual(ev.texto, "toma_no_cuenta")
        XCTAssertEqual(Presion.motivosNoCuenta(salteado), ["reposo"])
        XCTAssertEqual(TextosPresion.T.noCuentaPor(Presion.motivosNoCuenta(salteado)),
                       "Esta toma no cuenta. No esperaste los 5 minutos sentado. La próxima, quedate sentado y quieto hasta que terminen los 5 minutos. Hacé otra toma otro día.")
        // Con los 5 minutos cumplidos sí cuenta y no hay motivo.
        var cumplido = base
        cumplido.reposoCumplido = true
        cumplido.temporizadorSalteado = false
        XCTAssertTrue(Presion.evaluarSesion(cumplido).cuenta)
        XCTAssertEqual(Presion.motivosNoCuenta(cumplido), [])
    }

    /// Los textos del aviso son los del vector, el botón ya no dice que esperó y ninguno invita a saltear.
    func testTextosDelAvisoDelReposo() throws {
        XCTAssertEqual(TextosPresion.A.todos, try vectores()["propios"])
        XCTAssertFalse(TextosPresion.A.reposoSalir.lowercased().contains("esperé"))
        XCTAssertTrue(TextosPresion.A.reposoAviso.contains("no cuenta"))
        XCTAssertEqual(TextosPresion.A.seguirEsperando, "Seguir esperando")
    }

    /// Las mismas reglas de escritura que el resto de Presión: sin «:», «;», guiones ni palabras vedadas.
    func testTextosSinPalabrasVedadas() throws {
        var todos: [String] = []
        if case .objeto(let o) = TextosPresion.A.todos { todos += o.values.compactMap(\.comoTexto) }
        todos += lista(try vectores()["casos"]).compactMap { $0["sale"]?["mensaje"]?.comoTexto }
        XCTAssertGreaterThanOrEqual(todos.count, 17)
        for s in todos {
            let m = s.lowercased()
            for vedada in ["hipertens", "normal", "riesgo", "promedio de", "tu coach", "tu entrenador", " ia ", "inteligencia artificial"] {
                XCTAssertFalse(m.contains(vedada), "«\(s)» dice \(vedada)")
            }
            XCTAssertFalse(s.contains(":") || s.contains(";") || s.contains(" - ") || s.contains("—") || s.contains("–"), "«\(s)» lleva puntuación vedada")
        }
    }
}
