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
        #expect(r.calidad > 0.5, "\(r)")
        #expect(r.quieto, "6 s quieto al final: la serie terminó")
    }

    /// Casi sin movimiento del reloj y sin vibración de carga: puede contar de menos, pero no se propone.
    @Test func sentadillaLentaConPocaSenalNoSePropone() {
        let r = contar(SenalSintetica.sentadillaLenta())
        #expect(r.reps <= 9, "\(r)")
        #expect(ConfirmacionReps.propuesta(r) == nil, "\(r)")
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
        for c in [SenalSintetica.curlLimpio(semilla: s), SenalSintetica.conPausas(semilla: s), SenalSintetica.serieCortada(semilla: s)] {
            let r = contar(c)
            #expect(abs(r.reps - c.reps) <= 1, "\(c.nombre) semilla \(s): \(r)")
        }
        #expect(ConfirmacionReps.propuesta(contar(SenalSintetica.sentadillaLenta(semilla: s))) == nil)
        #expect(contar(SenalSintetica.soloRuido(semilla: s)).reps <= 1)
    }

    // MARK: - Los criterios del 9-nov

    /// Una señal con períodos y amplitudes dadas, a `hzAnalisis`. Cada ciclo es un coseno del período y la amplitud que le toca.
    static func ciclos(_ lista: [(periodo: Double, amplitud: Double)], antes: Double = 2) -> [Double] {
        let fs = ContadorReps.hzAnalisis
        var x = [Double](repeating: 0, count: Int(antes * fs))
        for c in lista {
            let m = Int(c.periodo * fs)
            x += (0..<m).map { c.amplitud * (1 - cos(2 * Double.pi * Double($0) / Double(m))) / 2 }
        }
        return x + [Double](repeating: 0, count: Int(4 * fs))
    }

    func racha(_ x: [Double]) -> ContadorReps.Racha? {
        ContadorReps.buscar(x, fs: ContadorReps.hzAnalisis).filter { !$0.negado }.max { $0.picos < $1.picos }
    }

    /// Los picos de cada dos pasos no son repeticiones: entre pico y pico hay otro ciclo parecido.
    @Test func picosSalteadosNoSonRepeticiones() throws {
        let fs = ContadorReps.hzAnalisis
        // Un ciclo de 1,1 s (la caminata) y, en un ciclo de cada dos, un poco más de altura.
        let x = (0..<Int(30 * fs)).map { i -> Double in
            let t = Double(i) / fs
            return sin(2 * .pi * t / 1.1) + 0.3 * sin(2 * .pi * t / 2.2)
        }
        let r = ContadorReps.Racha(picos: 13, desde: 1, hasta: 27, amplitud: 2, periodo: 2.2, calidad: 0.9)
        #expect(ContadorReps.tieneCiclosIntermedios(r, x: x, fs: fs))
        let unaPorCiclo = (0..<Int(30 * fs)).map { sin(2 * .pi * (Double($0) / fs) / 2.2) }
        let s = ContadorReps.Racha(picos: 13, desde: 1, hasta: 27, amplitud: 2, periodo: 2.2, calidad: 0.9)
        #expect(!ContadorReps.tieneCiclosIntermedios(s, x: unaPorCiclo, fs: fs))
    }

    /// Las últimas reps, lentas y chicas, cuentan; la que queda a medias, no.
    @Test func laColaAlFalloSumaLasLentasYNoLaAMedias() throws {
        var lista = Array(repeating: (periodo: 3.0, amplitud: 0.8), count: 7)
        // La caída es de a poco; la última, a un séptimo del recorrido, queda a medias.
        lista += [(4.5, 0.62), (6.0, 0.5), (7.0, 0.11)]
        let x = Self.ciclos(lista)
        let parejas = try #require(racha(x))
        let c = ContadorReps.conCola(parejas, x: x, fs: ContadorReps.hzAnalisis)
        #expect(c.picos == 9, "racha \(parejas.picos), con cola \(c.picos)")
    }

    /// Los tramos de las puntas sin vibración de carga son acomodarse y soltar: no son reps.
    @Test func lasPuntasSinCargaNoCuentan() {
        let fs = ContadorReps.hzAnalisis, hz = GrabadoraSerie.hz
        var g = Azar(5)
        let serie = (0..<8).map { ContadorReps.Pico(i: Int(Double(($0 + 1) * 4) * fs), v: 1, prominencia: 1) }
        let r = ContadorReps.Racha(picos: 8, desde: 4, hasta: 32, amplitud: 1, periodo: 4, calidad: 0.9, serie: serie)
        let cuadros = (0..<Int(36 * hz)).map { i -> CuadroSensor in
            let t = Double(i) / hz
            let v = t < 8 ? 0.004 : 0.15     // el primer tramo, sin carga
            return CuadroSensor(ax: Float(g.normal() * v), ay: Float(g.normal() * v), az: Float(-1 + g.normal() * v), gx: 0, gy: 0, gz: 0)
        }
        let c = ContadorReps.sinPuntasSinCarga(r, cuadros, hz: hz, fs: fs)
        #expect(c.picos == 7, "\(c.picos)")
        #expect(abs(c.desde - 8) < 0.1, "\(c.desde)")
    }

    /// Una racha que terminó bien antes del fin del descanso no es la serie que se confirma.
    @Test func loHechoEnPlenoDescansoNoSePropone() {
        let c = SenalSintetica.curlLimpio()
        let total = Double(c.cuadros.count) / GrabadoraSerie.hz
        #expect(ContadorReps.contar(c.cuadros).reps == 10)
        #expect(ContadorReps.contar(c.cuadros, noAntesDe: total + 30).reps == 0)
        #expect(ContadorReps.contar(c.cuadros, noAntesDe: total - 5).reps == 10, "terminar justo antes de que suene el descanso sí vale")
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
