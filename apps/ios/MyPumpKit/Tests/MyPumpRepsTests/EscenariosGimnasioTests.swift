import Foundation
import Testing
@testable import MyPumpReloj
import MyPumpRepsHerramientas

/// El camino entero en vivo (grabadora, ventana desde la confirmación anterior, conteo cada segundo y propuesta) con
/// cuadros inyectados, por familia y en los casos difíciles. Las señales son SINTÉTICAS: prueban el camino y que no se
/// rompa nada, no cuánto acierta el reloj en una muñeca real (eso lo mide `evaluar-reps` sobre grabaciones).
@Suite struct EscenariosGimnasioTests {
    static let semillas: [UInt64] = [3, 7, 19, 29, 43, 59]
    static let conSenal = FamiliaMovimiento.allCases.filter { ![.maquinaMunecaQuieta, .encogimiento, .gemelo].contains($0) }

    func paso() -> (Bool, ContadorReps.Resultado) -> Int? {
        var p = PropuestaSerie()
        return { enDescanso, c in enDescanso ? nil : p.proponer(c) }
    }

    func correr(_ f: FamiliaMovimiento, _ c: EscenarioGimnasio.Caso = .normal, sensores: EscenarioGimnasio.Sensores = .vivo,
                reps: Int = 10) -> EscenarioGimnasio.Marcador {
        var m = EscenarioGimnasio.Marcador()
        for s in Self.semillas {
            let l = EscenarioGimnasio.armar(f, caso: c, reps: reps, semilla: s)
            m.sumar(reales: l.reps, EscenarioGimnasio.enVivo(l, sensores: sensores, proponer: paso()))
        }
        return m
    }

    /// Por familia solo se exige no inventar y proponer algo: con 6 semillas el acierto de una familia es puro ruido.
    @Test(arguments: conSenal)
    func cadaFamiliaPropone(_ f: FamiliaMovimiento) {
        let m = correr(f)
        #expect(m.falsas == 0, "\(f): \(m.texto)")
        #expect(m.propuestas >= 2, "\(f): \(m.texto)")
    }

    @Test func enConjuntoAciertaYProponeLaMayoria() {
        var cubiertas = 0, propuestas = 0, bien = 0, corridas = 0
        for f in Self.conSenal {
            let m = correr(f)
            corridas += m.corridas; cubiertas += m.propuestas; propuestas += m.propuestas; bien += m.dentroDeUno
        }
        #expect(Double(cubiertas) >= 0.7 * Double(corridas), "propuso \(cubiertas) de \(corridas)")
        #expect(Double(bien) >= 0.8 * Double(propuestas), "±1 \(bien) de \(propuestas)")
    }

    /// Encogimientos, gemelos y máquinas con la muñeca quieta casi no mueven el reloj: se puede quedar callado, nunca inventar.
    @Test(arguments: [FamiliaMovimiento.encogimiento, .gemelo, .maquinaMunecaQuieta])
    func conPocaSenalSeCallaAntesQueErrar(_ f: FamiliaMovimiento) {
        let m = correr(f)
        #expect(m.falsas == 0, "\(f): \(m.texto)")
        #expect(m.propuestas == 0 || m.conError <= m.propuestas, "\(f): \(m.texto)")
    }

    @Test func unaMaquinaConLaMunecaInmovilNoInventa() {
        let m = correr(.maquinaMunecaQuieta, .munecaInmovil)
        #expect(m.propuestas <= 2 && m.falsas == 0, "\(m.texto)")
    }

    @Test(arguments: [EscenarioGimnasio.Caso.lentaAlFallo, .pausaMedia, .arrancaEnDescanso])
    func casosDificilesNoFalsean(_ c: EscenarioGimnasio.Caso) {
        var total = (0, 0)
        for f in [FamiliaMovimiento.curl, .empujeHorizontal, .tironVertical, .elevacionLateral] {
            let m = correr(f, c)
            #expect(m.falsas == 0, "\(f) \(c): \(m.texto)")
            total.0 += m.dentroDeUno; total.1 += m.propuestas
        }
        // Al fallo es el caso que peor anda (la velocidad cae a un tercio): el número va en el informe, acá solo el piso.
        #expect(total.0 * 2 >= total.1, "\(c): ±1 \(total.0) de \(total.1)")
    }

    /// Con un drop no se sabe si el alumno lo carga como una serie: lo que importa es que no proponga antes de la serie.
    @Test func elDropNoInventaAntes() {
        let m = correr(.curl, .drop)
        #expect(m.falsas == 0, "\(m.texto)")
    }

    /// Sin serie casi nunca propone; si lo hace, el alumno igual tiene que confirmar. El tope es sobre las 18 corridas.
    @Test func sinSerieCasiNuncaPropone() {
        let falsas = [FamiliaMovimiento.curl, .sentadilla, .tironVertical].map { correr($0, .sinSerie).falsas }.reduce(0, +)
        #expect(falsas <= 2, "falsas: \(falsas) de 18")
    }

    @Test func conLaMunecaBajaCuentaIgual() {
        let f = correr(.curl)
        let b = correr(.curl, sensores: .munecaBaja)
        #expect(b.propuestas >= f.propuestas - 1, "\(b.texto)")
        #expect(b.conError <= f.conError + 1 && b.falsas == 0, "\(b.texto)")
    }

    @Test func sinMuestrasNoPropone() {
        let m = correr(.curl, sensores: .sinMuestras)
        #expect(m.propuestas == 0 && m.falsas == 0, "\(m.texto)")
    }

    @Test func conLaAppSuspendidaNoProponeAMedias() {
        let m = correr(.curl, sensores: .suspendida)
        #expect(m.propuestas == 0, "\(m.texto)")
    }

    @Test func conLaSesionCortadaNoProponeAMedias() {
        let m = correr(.curl, sensores: .sesionCortada)
        #expect(m.propuestas <= 1, "\(m.texto)")
    }

    /// Grabación real privada, si se apunta a ella (`MPCAL_REAL=<archivo>`). No vive en el repo.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["MPCAL_REAL"] != nil))
    func grabacionReal() throws {
        let u = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["MPCAL_REAL"]))
        let rs = try ArchivoCalibracion.leer(Data(contentsOf: u))
        var dentroDeDos = 0, con = 0
        for r in rs where r.encabezado.finDescanso != nil || r.cuadros.count > 3_000 {
            guard let p = EvaluacionReps.repetirEnVivo(r).propuesta else { continue }
            con += 1
            if abs(p - r.encabezado.reps) <= 2 { dentroDeDos += 1 }
        }
        #expect(con >= 8 && dentroDeDos >= 7, "propuso \(con), a ±2: \(dentroDeDos)")
    }
}
