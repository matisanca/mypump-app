#if DEBUG
import SwiftUI
import MyPumpModelos
import MyPumpReglas

// PROTOTIPO: los escenarios de demo y el estado de la pantalla. Sin red, sin token y sin datos de nadie: nada de esto
// entra a la cola; «lo que se guardaría» solo muestra el mismo payload que `EscriturasEntreno.carga` armaría hoy.

struct EscenarioCarga: Identifiable, Hashable {
    let id: String
    let titulo: String
    let detalle: String
    let ejercicio: Ejercicio
    let semana: Int
    var ultimaVez: [CargaSimple.Referencia] = []
    var cuando: String?
    var sustituyeA: String?
    var variantes: [String: [CargaSimple.Referencia]] = [:]
    var conPreparacion = false

    static func == (a: Self, b: Self) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }

    private static func progresion(_ semanas: [(Int, String)]) -> [Progresion] {
        semanas.enumerated().map { i, s in Progresion(semana: i + 1, series: s.0, reps: s.1, rir: "0 (al fallo)") }
    }
    private static func refs(_ pares: [(Int, Double?)]) -> [CargaSimple.Referencia] {
        pares.map { .init(reps: $0.0, kg: $0.1) }
    }

    static let todos: [EscenarioCarga] = [
        .init(id: "normal", titulo: "Semana normal", detalle: "Carga de la vez pasada y OK por serie",
              ejercicio: Ejercicio(id: "press-banca", nombre: "Press banca con barra", tipo: "compuesto", descansoSegundos: 150,
                                   progresion: progresion([(4, "10"), (4, "10"), (4, "10"), (4, "10"), (4, "10")])),
              semana: 3, ultimaVez: refs([(10, 80), (10, 80), (9, 80), (8, 80)]), cuando: "hace 4 días", conPreparacion: true),
        .init(id: "aumento", titulo: "Día de aumento", detalle: "El plan baja las reps: sugiere subir",
              ejercicio: Ejercicio(id: "press-banca", nombre: "Press banca con barra", tipo: "compuesto", descansoSegundos: 150,
                                   progresion: progresion([(4, "10"), (4, "10"), (4, "8"), (4, "8")])),
              semana: 3, ultimaVez: refs([(10, 80), (10, 80), (9, 80), (9, 80)]), cuando: "hace 4 días"),
        .init(id: "primera", titulo: "Primera vez", detalle: "Calibración, sin historial",
              ejercicio: Ejercicio(id: "hack", nombre: "Sentadilla hack", tipo: "compuesto", descansoSegundos: 180,
                                   progresion: progresion([(4, "10-12"), (4, "10-12")])),
              semana: 1),
        .init(id: "calibracion", titulo: "Calibración con historial", detalle: "Semana 1 de un bloque nuevo",
              ejercicio: Ejercicio(id: "remo-barra", nombre: "Remo con barra", tipo: "compuesto", descansoSegundos: 120,
                                   progresion: progresion([(3, "8-10"), (3, "8")])),
              semana: 1, ultimaVez: refs([(9, 70), (9, 70), (8, 70)]), cuando: "hace 12 días"),
        .init(id: "mixta", titulo: "Una serie distinta", detalle: "La vez pasada la última salió con menos",
              ejercicio: Ejercicio(id: "press-inclinado", nombre: "Press inclinado en máquina", tipo: "compuesto", descansoSegundos: 120,
                                   progresion: progresion([(4, "10"), (4, "10"), (4, "10")])),
              semana: 2, ultimaVez: refs([(10, 60), (10, 60), (9, 60), (10, 55)]), cuando: "hace 5 días"),
        .init(id: "variante", titulo: "Con agarre", detalle: "El peso se separa por agarre",
              ejercicio: Ejercicio(id: "jalon", nombre: "Jalón al pecho", tipo: "compuesto", descansoSegundos: 120,
                                   progresion: progresion([(3, "10"), (3, "10"), (3, "10")])),
              semana: 2, cuando: "hace 3 días",
              variantes: ["Prono": refs([(10, 55), (9, 55), (8, 55)]), "Supino": refs([(11, 60), (10, 60), (9, 60)]), "Neutro": []]),
        .init(id: "sustitucion", titulo: "Sustituido", detalle: "Otro ejercicio: no hereda los kilos del original",
              ejercicio: Ejercicio(id: "press-banca", nombre: "Press plano con mancuernas", tipo: "compuesto", descansoSegundos: 150,
                                   progresion: progresion([(4, "10"), (4, "10"), (4, "10")]), equipo: "dumbbell"),
              semana: 2, sustituyeA: "Press banca con barra"),
        .init(id: "sinkg", titulo: "Sin peso", detalle: "Peso corporal: solo reps",
              ejercicio: Ejercicio(id: "abs", nombre: "Elevaciones de piernas", tipo: "core", descansoSegundos: 60,
                                   progresion: progresion([(3, "15"), (3, "15")])),
              semana: 2, ultimaVez: refs([(15, nil), (14, nil), (12, nil)]), cuando: "hace 3 días"),
        .init(id: "amrap", titulo: "Al máximo", detalle: "El plan no da reps: hay que marcarlas",
              ejercicio: Ejercicio(id: "lagartijas", nombre: "Lagartijas", tipo: "compuesto", descansoSegundos: 90,
                                   progresion: progresion([(3, "máx"), (3, "máx")])),
              semana: 2, ultimaVez: refs([(22, nil), (18, nil), (15, nil)]), cuando: "hace 3 días"),
    ]
}

@Observable @MainActor
final class PrototipoCarga {
    let escenario: EscenarioCarga
    private(set) var s: CargaSimple
    var varianteActual: String?
    /// Serie confirmada en corrección (el dock pasa a «Corrigiendo»).
    var corrigiendo: Int?
    var repsCorreccion = 0
    var kgCorreccion: Double?
    var descansoFin: Date?
    /// Serie que se puede deshacer unos segundos después del OK.
    var deshacible: Int?
    var enGuardia = false
    private var guardiaDesde = Date.distantPast
    private var tareaGuardia: Task<Void, Never>?
    /// Corrección que pidió «¿Está bien cargado?».
    private var preguntaEsDeCorreccion = false
    var pregunta: Pregunta?
    var aviso: String?
    /// serie → el JSON que se encolaría: por serie, como la clave `carga_<dia>_<ex>_<i>_s<sem>` (lo último gana).
    private(set) var registros: [Int: String] = [:]
    /// Cuántas veces se habría encolado algo (cada OK o corrección).
    private(set) var escrituras = 0
    let rir: String

    init(_ e: EscenarioCarga) {
        escenario = e
        let primera = e.variantes.isEmpty ? nil : "Prono"
        varianteActual = primera
        let g = UserDefaults.standard.object(forKey: "guardiaOK").map { _ in UserDefaults.standard.double(forKey: "guardiaOK") } ?? 10
        s = Self.armar(e, variante: primera, guardia: g)
        rir = RIRDelPlan.lleva(e.ejercicio) ? RIRDelPlan.guardar(Progresiones.pauta(e.ejercicio, semana: e.semana).rir) : ""
        s.varianteActual = primera
    }

    private static func armar(_ e: EscenarioCarga, variante: String?, guardia: Double) -> CargaSimple {
        let refs = variante.flatMap { e.variantes[$0] } ?? e.ultimaVez
        let equipo = Preparacion.equipo(nombre: e.ejercicio.nombre, equipo: e.ejercicio.equipo)
        return CargaSimple(ejercicio: e.ejercicio, semana: e.semana, ultimaVez: refs, equipo: equipo,
                           recordKg: refs.compactMap(\.kg).max() ?? 0, guardiaSegundos: guardia)
    }

    /// Otro agarre, otra historia: lo que falta sale de la nueva y lo hecho conserva su peso (la de la serie registrada).
    func elegirVariante(_ v: String) {
        guard v != varianteActual else { return }
        let hechas = s.series
        varianteActual = v
        var nuevo = Self.armar(escenario, variante: v, guardia: s.guardiaSegundos)
        nuevo.varianteActual = v
        deshacible = nil
        guard hechas.contains(where: \.confirmada) else { s = nuevo; return }
        nuevo.reemplazarHechas(hechas)
        s = nuevo
    }

    func cambiar(_ f: (inout CargaSimple) -> Void) { f(&s) }

    func confirmarActiva(registrarIgual: Bool? = nil) {
        guard let i = s.activa else { return }
        // Un doble toque no es confirmar: la insistencia cuenta medio segundo después.
        if enGuardia && Date.now.timeIntervalSince(guardiaDesde) < 0.5 { return }
        let insistio = enGuardia
        switch s.confirmar(i, ahora: .now, insistio: insistio, registrarIgual: registrarIgual) {
        case .registrada:
            enGuardia = false
            tareaGuardia?.cancel()
            encolar(i)
            deshacible = i
            aviso = nil
            anunciar(i)
            if !s.completo, let d = escenario.ejercicio.descansoSegundos { descansoFin = .now + Double(d) } else { descansoFin = nil }
        case .guardia:
            enGuardia = true
            guardiaDesde = .now
            tareaGuardia?.cancel()
            tareaGuardia = Task { [weak self] in
                guard (try? await Task.sleep(for: .seconds(3))) != nil else { return }
                self?.enGuardia = false
            }
        case .preguntar(let p): preguntaEsDeCorreccion = false; pregunta = p
        case .rechazada(let t): aviso = t
        case .faltanDatos: break
        }
    }

    func responderPregunta() {
        if preguntaEsDeCorreccion { guardarCorreccion(registrarIgual: true) } else { confirmarActiva(registrarIgual: true) }
    }

    private func anunciar(_ i: Int) {
        let que = s.sinKg ? "\(s.reps(i) ?? 0) repeticiones" : "\(s.reps(i) ?? 0) repeticiones con \(CargaSimpleView.kg(s.series[i].kg)) kilos"
        let sigue = s.activa.map { "Sigue la serie \($0 + 1)" } ?? "Ejercicio completo"
        AccessibilityNotification.Announcement("Serie \(i + 1) anotada: \(que). \(sigue)").post()
    }

    func deshacerUltima() {
        guard let i = deshacible else { return }
        s.deshacer(i)
        registros[i] = nil
        deshacible = nil
        descansoFin = nil
    }

    func aplicarALasHechas() {
        for i in s.aplicarCargaALasHechas() { encolar(i) }
    }

    func abrirCorreccion(_ i: Int) {
        guard s.series[i].confirmada, let r = s.reps(i) else { return }
        corrigiendo = i
        repsCorreccion = r
        kgCorreccion = s.series[i].kg
        deshacible = nil
    }

    func guardarCorreccion(registrarIgual: Bool = false) {
        guard let i = corrigiendo else { return }
        // Sin cambios no se escribe nada.
        guard repsCorreccion != s.reps(i) || (!s.sinKg && kgCorreccion != s.series[i].kg) else { corrigiendo = nil; return }
        let textoKg = kgCorreccion.map(JS.texto) ?? ""
        switch Verosimilitud.evaluar(reps: String(repsCorreccion), kg: textoKg, sinKg: s.sinKg, recordKg: s.recordKg,
                                     repsUltimaVez: s.referencia(i).map { String($0.reps) } ?? "", repsPlan: s.repsPlan) {
        case .ok: break
        case .rechazada(let t): aviso = t; return
        case .preguntar(let p):
            guard registrarIgual else { preguntaEsDeCorreccion = true; pregunta = p; return }
        }
        s.corregir(i, reps: repsCorreccion, kg: kgCorreccion)
        encolar(i)
        aviso = nil
        corrigiendo = nil
    }

    private func encolar(_ i: Int) {
        let nombre = NombreEjercicio(escenario.ejercicio.nombre).principal
        let p = EscriturasEntreno.carga(sesionId: nil, dia: "demo", semana: escenario.semana, ejercicio: escenario.ejercicio.id, indice: i,
                                        serie: s.serieLocal(i, rir: rir), nombre: nombre, varianteEjercicio: varianteActual)
        let datos = (try? JSONEncoder.ordenado.encode(p)).flatMap { String(data: $0, encoding: .utf8) } ?? "?"
        registros[i] = datos
        escrituras += 1
    }
}

private extension JSONEncoder {
    static let ordenado: JSONEncoder = { let e = JSONEncoder(); e.outputFormatting = [.sortedKeys]; return e }()
}
#endif
