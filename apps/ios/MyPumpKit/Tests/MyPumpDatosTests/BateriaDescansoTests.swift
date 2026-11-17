import Foundation
import Observation
import Testing
import MyPumpModelos
import MyPumpReglas
@testable import MyPumpDatos

/// Batería (2.3.2, punto 7): el tick del descanso sigue cada 250 ms (la precisión del pitido), pero solo avisa a quien
/// mira la barra cuando cambia algo (el texto y la barra cambian 1 vez por segundo).
@Suite("Batería: el descanso no redibuja sin cambios", .serialized)
@MainActor
struct BateriaDescansoTests {
    final class Avisos: @unchecked Sendable {
        private let lock = NSLock()
        private var _n = 0
        var n: Int { lock.withLock { _n } }
        func sumar() { lock.withLock { _n += 1 } }
    }

    func observar(_ m: ModeloEntreno, _ a: Avisos) {
        withObservationTracking { _ = m.descanso } onChange: { a.sumar() }
    }

    @Test func dentroDelMismoSegundoNoAvisaYAlCambiarSi() async {
        let b = Banco()
        let m = b.modelo()
        m.escribir("jal-d1-0", 0, campo: "reps", valor: "10")
        m.escribir("jal-d1-0", 0, campo: "kg", valor: "60")
        await m.confirmarSerie("jal-d1-0", 0) { _ in true }
        #expect(m.descanso.visible)
        let base = b.reloj.ms
        // Al segundo y medio del arranque: el texto ya es otro.
        b.reloj.ms = base + 1_100
        m.tickDescanso()
        let texto = m.descanso.texto
        let a = Avisos()
        observar(m, a)
        for paso in [1_250.0, 1_500, 1_750] {
            b.reloj.ms = base + paso
            #expect(m.tickDescanso() == false)
        }
        #expect(a.n == 0, "tres ticks del mismo segundo no avisan")
        #expect(m.descanso.texto == texto)
        b.reloj.ms = base + 2_100
        m.tickDescanso()
        #expect(a.n == 1, "al cambiar el segundo, sí")
        #expect(m.descanso.texto != texto)
    }

    @Test func elFinSigueSonandoEnElTickQueLoCruza() async {
        let b = Banco()
        let m = b.modelo()
        m.escribir("jal-d1-0", 0, campo: "reps", valor: "10")
        m.escribir("jal-d1-0", 0, campo: "kg", valor: "60")
        await m.confirmarSerie("jal-d1-0", 0) { _ in true }
        guard let fin = m.descanso.descanso?.fin else { Issue.record("sin descanso"); return }
        b.reloj.ms = fin - 100
        #expect(m.tickDescanso() == false)
        b.reloj.ms = fin + 150
        #expect(m.tickDescanso() == true, "suena en el primer tick después del fin")
        b.reloj.ms = fin + 400
        #expect(m.tickDescanso() == false, "una sola vez")
        #expect(m.descanso.listo)
    }
}
