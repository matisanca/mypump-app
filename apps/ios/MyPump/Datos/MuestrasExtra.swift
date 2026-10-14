import Foundation
import MyPumpModelos

/// Argumentos de lanzamiento de los bocetos, para sacar capturas sin tocar la pantalla:
///
///     simctl launch … -pestana revision -ir peso          (abre en Revisión, desplazado hasta Peso)
///     simctl launch … -pestana entreno -abrir ejercicio    (entra al primer ejercicio de trabajo)
///     simctl launch … -pestana revision -abrir misdatos    (Mis datos)
///     simctl launch … -pestana progreso -abrir detalle     (detalle del primer ejercicio)
///     simctl launch … -estado cargando|vacio|error         (estados de carga, vacío y error)
///     simctl launch … -demo lleno                          (Mi Día con racha, hábitos y 30 días cargados)
///     simctl launch … -series 2                            (el ejercicio abierto con 2 series ya confirmadas)
///     simctl launch … -descanso no                         (sin el descanso de muestra)
///
/// Cuando se cablee la app, esto desaparece: los estados salen de la fuente en vivo.
enum DemoUI {
    enum Estado: String { case cargando, vacio, error }

    static var estado: Estado? { valor("estado").flatMap(Estado.init(rawValue:)) }
    static var ir: String? { valor("ir") }
    static var abrir: String? { valor("abrir") }
    static var lleno: Bool { valor("demo") == "lleno" }
    static var seriesHechas: Int { Int(valor("series") ?? "") ?? 0 }
    static var sinDescanso: Bool { valor("descanso") == "no" }

    private static func valor(_ clave: String) -> String? { UserDefaults.standard.string(forKey: clave) }
}

/// Datos de ejemplo para mostrar los estados "llenos" que la cuenta de prueba no tiene (su racha está en 0 y los 30
/// días vacíos). Se arman con la MISMA forma que devuelve el servidor, decodificando JSON.
enum MuestrasExtra {
    static let racha: Racha? = decodificar(#"{"streak": 9, "ultimo_dia_valido": "2026-10-13"}"#)

    static let habitos: HabitosDia? = decodificar(
        #"{"fecha": "2026-10-14", "entrenamiento": "entrene", "comio_segun_plan": true, "durmio_bien": false, "cardio": null, "vasos_agua": 5}"#
    )

    /// 30 días hacia atrás desde el 14-oct: 9 seguidos cumplidos, y antes un patrón realista de cumplidos y parciales.
    static let adherencia: [DiaAdherencia] = {
        let patron = [true, true, true, true, true, true, true, true, true, false, true, true, false, true, true,
                      true, false, false, true, true, true, true, false, true, true, true, true, false, false, true]
        let calendario = Calendar(identifier: .gregorian)
        let f = DateFormatter()
        f.calendar = calendario
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        let hoy = f.date(from: "2026-10-14") ?? .now
        let filas = patron.enumerated().map { i, valido -> String in
            let fecha = f.string(from: calendario.date(byAdding: .day, value: -i, to: hoy) ?? hoy)
            let parcial = !valido && i % 3 == 0
            let entreno = valido ? (i % 2 == 0 ? "\"entrene\"" : "\"descanso\"") : (parcial ? "\"entrene\"" : "null")
            return #"{"fecha": "\#(fecha)", "entrenamiento": \#(entreno), "comio_segun_plan": \#(valido || parcial), "durmio_bien": \#(valido), "vasos_agua": \#(valido ? 8 : 2), "es_valido": \#(valido)}"#
        }
        return decodificar("[\(filas.joined(separator: ","))]") ?? []
    }()

    static let checkin: CheckinSemana? = decodificar(
        #"{"energia": 4, "descanso": 3, "hambre": 2, "adherencia": 5, "nota": "Bien la semana, el sábado me pasé un poco en el cumple."}"#
    )

    private static func decodificar<T: Decodable>(_ json: String) -> T? {
        try? JSONDecoder().decode(T.self, from: Data(json.utf8))
    }
}
