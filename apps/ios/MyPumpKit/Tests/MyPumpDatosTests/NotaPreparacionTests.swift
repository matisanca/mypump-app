import XCTest
import MyPumpModelos
@testable import MyPumpDatos

/// La nota de una serie de preparación del plan llega al alumno (teléfono y reloj) sin RIR, salvo reserva clínica.
final class NotaPreparacionTests: XCTestCase {
    func testLaNotaDeLaPreparacionPasaPorSinRIR() {
        let plan = [Aproximacion(reps: "8", pct: 60, nota: "Con RIR 2."), Aproximacion(reps: "5", pct: 80, nota: "Lento abajo.")]
        XCTAssertEqual(ModeloEntreno.aproximacionesParaAlumno(plan, rir: "0")?.map(\.nota), [nil, "Lento abajo."])
        XCTAssertEqual(ModeloEntreno.aproximacionesParaAlumno(plan, rir: nil)?.map(\.nota), [nil, "Lento abajo."])
        XCTAssertEqual(ModeloEntreno.aproximacionesParaAlumno(plan, rir: "2-3")?.map(\.nota), ["Con RIR 2.", "Lento abajo."],
                       "reserva clínica: la nota de Mati entera")
        XCTAssertNil(ModeloEntreno.aproximacionesParaAlumno(nil, rir: "0"))
    }
}
