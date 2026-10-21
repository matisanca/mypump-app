import Foundation
import Testing
import MyPumpModelos
@testable import MyPumpReglas
@testable import MyPumpDatos

// Revisión del 21-oct del cambio D24 («Otros ejercicios de [músculo]» en la hoja «Sustituir»): el modelo de Entreno con
// el catálogo real. Gemelo de SustituirOtrosTest.kt.

private let raizDelRepo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
private let catalogoReal = try! CatalogoEjercicios(json: Data(contentsOf: raizDelRepo.appendingPathComponent("apps/shared/catalogo-ejercicios.json")))

/// Un día de empuje sin fotos en el plan (como la demo, la que mira Apple): la extensión en polea (agarre Barra, Soga o
/// Maneral), los fondos y la patada de tríceps (sin variantes, con otros de su músculo) y uno que el catálogo no conoce.
private let estructuraOtros = """
{"semanas_total":12,"dias":[{"id":"d1","n":1,"nombre":"EMPUJE","bloques":[{"titulo":"BLOQUE 1 — TRÍCEPS","ejercicios":[
  {"id":"ext-d1-0","nombre":"Extensión tríceps en polea","tipo":"aislamiento","descanso_segundos":90,"progresion":[{"semana":1,"series":4,"reps":"12","rir":"1"}]},
  {"id":"fon-d1-1","nombre":"Fondos","tipo":"compuesto","descanso_segundos":120,"progresion":[{"semana":1,"series":3,"reps":"10","rir":"1"}]},
  {"id":"pat-d1-2","nombre":"Patada de tríceps con mancuerna","tipo":"aislamiento","descanso_segundos":60,"progresion":[{"semana":1,"series":3,"reps":"12","rir":"1"}]},
  {"id":"inv-d1-3","nombre":"Saludo inventado","tipo":"aislamiento","descanso_segundos":60,"progresion":[{"semana":1,"series":3,"reps":"12","rir":"1"}]}]}]}]}
"""

private func rutinaOtros() -> RutinaActiva {
    let fila = #"{"id":"rut-otros","version":1,"semana_actual":1,"tiene_siguiente":false,"estructura":\#(estructuraOtros)}"#
    return try! JSONDecoder().decode(RutinaActiva.self, from: Data(fila.utf8))
}

@MainActor
private func modeloOtros(_ b: Banco) -> ModeloEntreno {
    let r = b.reloj
    return ModeloEntreno(cliente: ClienteRPC(transporte: b.servidor), token: "tok-prueba", outbox: b.cola, disco: b.disco,
                         rutina: rutinaOtros(), catalogo: catalogoReal, zona: zonaAR, reloj: { Date(timeIntervalSince1970: r.ms / 1000) })
}

@Suite("Sustituir con los otros del mismo músculo (revisión del 21-oct)", .serialized)
@MainActor
struct SustituirOtrosTests {
    /// Hallazgo 1: «Sustituir» miraba solo las variantes. A los fondos (van a Dips_-_Chest_Version) y a la patada de
    /// tríceps (Tricep_Dumbbell_Kickback), sin variantes, se les apagaba el botón y se les decía «No hay otra variante
    /// equivalente…» aunque tenían 26 a 30 otros ejercicios de su músculo.
    @Test func sinVariantesPeroConOtrosDelMismoMusculoSeSustituye() throws {
        let b = Banco()
        let m = modeloOtros(b)
        #expect(catalogoReal.resolver(try #require(m.dia.ejercicio("fon-d1-1")))?.slugEn == "Dips_-_Chest_Version")
        #expect(catalogoReal.resolver(try #require(m.dia.ejercicio("pat-d1-2")))?.slugEn == "Tricep_Dumbbell_Kickback")
        for lugar in ["fon-d1-1", "pat-d1-2"] {
            let t = try #require(m.tarjeta(lugar))
            #expect(m.sustitutos(lugar).isEmpty, "\(lugar): sin variantes del mismo movimiento")
            #expect(m.otrosDelMismoMusculo(lugar).count >= 15, "\(lugar): \(m.otrosDelMismoMusculo(lugar).count) otros")
            #expect(t.puedeSustituir, "\(lugar): con otros del mismo músculo se puede sustituir")
        }
        // Con variantes, como siempre.
        #expect(!m.sustitutos("ext-d1-0").isEmpty && m.tarjeta("ext-d1-0")?.puedeSustituir == true)
        // Sin ninguna de las dos no se puede (y la tarjeta dice que no hay con qué).
        #expect(m.sustitutos("inv-d1-3").isEmpty && m.otrosDelMismoMusculo("inv-d1-3").isEmpty)
        #expect(m.tarjeta("inv-d1-3")?.puedeSustituir == false)
    }
}
