import Foundation
import Testing
@testable import MyPumpReloj
import MyPumpRepsHerramientas

/// El contador con señales sintéticas (tanda 4): los cinco casos del pedido, reproducibles con su semilla.
@Suite struct ContadorRepsTests {
    func contar(_ c: SenalSintetica.Caso) -> ContadorReps.Resultado { ContadorReps.contar(c.cuadros) }

    @Test func curlLimpioCuentaExacto() {
        let r = contar(SenalSintetica.curlLimpio())
        #expect(r.reps == 10, "\(r)")
        #expect(abs(r.periodo - 2.5) < 0.3, "\(r)")
        #expect(r.calidad > 0.7, "\(r)")
        #expect(r.quieto, "6 s quieto al final: la serie terminó")
    }

    @Test func sentadillaLentaConPocaSenal() {
        let r = contar(SenalSintetica.sentadillaLenta())
        #expect(abs(r.reps - 8) <= 1, "\(r)")
        #expect(r.periodo > 3.5, "\(r)")
    }

    @Test func soloRuidoNoCuenta() {
        let r = contar(SenalSintetica.soloRuido())
        #expect(r.reps <= 1, "\(r)")
    }

    @Test func pausasDentroDeLaSerieNoLaCortan() {
        let r = contar(SenalSintetica.conPausas())
        #expect(abs(r.reps - 12) <= 1, "\(r)")
    }

    @Test func serieCortadaNoCuentaLaMitad() {
        let r = contar(SenalSintetica.serieCortada())
        #expect(abs(r.reps - 7) <= 1, "\(r)")
    }

    /// Con otras semillas (otro ruido y otros tiempos) tiene que seguir dentro de ±1: no es un ajuste a una sola señal.
    @Test(arguments: [11, 23, 37, 41, 53] as [UInt64])
    func otrasSemillas(_ s: UInt64) {
        for c in [SenalSintetica.curlLimpio(semilla: s), SenalSintetica.sentadillaLenta(semilla: s), SenalSintetica.conPausas(semilla: s),
                  SenalSintetica.serieCortada(semilla: s)] {
            let r = contar(c)
            #expect(abs(r.reps - c.reps) <= 1, "\(c.nombre) semilla \(s): \(r)")
        }
        #expect(contar(SenalSintetica.soloRuido(semilla: s)).reps <= 1)
    }

    @Test func determinista() {
        let c = SenalSintetica.conPausas()
        #expect(ContadorReps.contar(c.cuadros) == ContadorReps.contar(c.cuadros))
    }

    @Test func cortoOVacioDaCero() {
        #expect(ContadorReps.contar([]) == .vacio)
        #expect(ContadorReps.contar(Array(repeating: .cero, count: 150)).reps == 0)
        #expect(ContadorReps.contar(Array(repeating: CuadroSensor(ax: 0, ay: 0, az: -1, gx: 0, gy: 0, gz: 0), count: 3_000)).reps == 0)
    }

    /// Mientras la serie va (la mitad de las reps, sin el final quieto) cuenta lo hecho y no dice «quieto».
    @Test func enVivoAMitadDeSerie() {
        let c = SenalSintetica.curlLimpio()
        let mitad = Array(c.cuadros.prefix(Int((6 + 5 * 2.5) * GrabadoraSerie.hz)))
        let r = ContadorReps.contar(mitad)
        #expect(abs(r.reps - 5) <= 1, "\(r)")
        #expect(!r.quieto)
    }
}
