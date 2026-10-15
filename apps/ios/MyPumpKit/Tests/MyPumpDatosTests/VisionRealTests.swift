import Foundation
import Testing
import MyPumpModelos
import MyPumpReglas
@testable import MyPumpDatos

/// DIE-14/15 con la IA de verdad: las respuestas de mini-vision del 15-oct, recién arreglado (Codex con gpt-5.6-sol), a
/// una foto de un plato y a una tabla nutricional, tal cual llegaron. Las pruebas de pantalla usan el servidor de prueba;
/// esto fija que el formato real entra por el mismo `vision(...)` y se lee igual.
@Suite("La visión real: el plato y la etiqueta")
struct VisionRealTests {
    static let plato = #"{"ok":true,"data":{"descripcion":"Milanesa con puré","escala":"plato playo 26 cm, usado como única referencia","alimentos":[{"nombre":"Milanesa frita","gramos":155,"kcal":390,"prot":31,"carb":22,"fat":20},{"nombre":"Puré de papas","gramos":165,"kcal":175,"prot":3,"carb":28,"fat":6}],"kcal":565,"prot":34,"carb":50,"fat":26,"confianza":"baja"}}"#
    static let etiqueta = #"{"ok":true,"data":{"nombre":"Producto alimenticio","porcion_g":30,"kcal":120,"prot":3.5,"carb":21,"fat":2.5,"confianza":"alta"}}"#

    func cliente(_ cuerpo: String) -> ClienteRPC {
        ClienteRPC(config: .produccion, transporte: TransporteProgramado { _, _ in (200, cuerpo) })
    }

    @Test func elPlatoSeLeeYSusGramosReescalan() async throws {
        let r = await cliente(Self.plato).vision(token: "AAAAAAAAAAAAAAAAAAAA", tipo: .plato, jpeg: Data([0xFF, 0xD8]))
        let data = try r.get()
        let e = try JSONDecoder().decode(EstimacionPlato.self, from: JSONEncoder().encode(data))
        #expect(e.alimentos.map(\.nombre) == ["Milanesa frita", "Puré de papas"])
        let bases = ComidaLibreNueva.bases(e)
        let t = ComidaLibreNueva.totales(bases, gramos: ComidaLibreNueva.gramos(bases, escritos: [nil, nil]))
        #expect(t.kcal == 565 && t.prot == 34 && t.carb == 50 && t.fat == 26)
        // El cliente corrige la milanesa a la mitad: sus macros se re-escalan.
        let mitad = ComidaLibreNueva.totales(bases, gramos: ComidaLibreNueva.gramos(bases, escritos: [77.5, nil]))
        #expect(mitad.kcal == 370)
    }

    @Test func laEtiquetaSeLee() async throws {
        let r = await cliente(Self.etiqueta).vision(token: "AAAAAAAAAAAAAAAAAAAA", tipo: .etiqueta, jpeg: Data([0xFF, 0xD8]))
        let d = try JSONDecoder().decode(LecturaEtiqueta.self, from: JSONEncoder().encode(try r.get()))
        #expect(d.porcionG == 30 && d.kcal == 120 && d.prot == 3.5 && d.carb == 21 && d.fat == 2.5 && d.confianza == "alta")
    }
}
