import Foundation
import MyPumpModelos
import MyPumpReglas
import MyPumpDatos

/// Argumentos de lanzamiento para capturas de diseño, sin tocar la pantalla (solo en DEBUG):
///
///     simctl launch … -bocetos YES                         (las pestañas con las muestras, sin cuenta ni bienvenida)
///     simctl launch … -pestana revision -ir peso          (abre en Revisión, desplazado hasta Peso)
///     simctl launch … -pestana entreno -abrir ejercicio    (entra al primer ejercicio de trabajo)
///     simctl launch … -pestana revision -abrir misdatos    (Mis datos)
///     simctl launch … -pestana progreso -abrir detalle     (detalle del primer ejercicio)
///     simctl launch … -estado cargando|vacio|error         (estados de carga, vacío y error, con -bocetos)
///     simctl launch … -demo lleno                          (Mi Día con racha, hábitos y 30 días, con -bocetos)
///     simctl launch … -series 2                            (el ejercicio abierto con 2 series ya confirmadas)
///     simctl launch … -descanso no                         (sin el descanso de muestra)
enum DemoUI {
    enum Estado: String { case cargando, vacio, error }

    static var bocetos: Bool {
        #if DEBUG
        UserDefaults.standard.bool(forKey: "bocetos")
        #else
        false
        #endif
    }
    /// `-captura YES`: las capturas de la tienda, sin el cartel "Estás viendo la demo" (que un cliente nunca ve).
    static var captura: Bool {
        #if DEBUG
        UserDefaults.standard.bool(forKey: "captura")
        #else
        false
        #endif
    }
    static var estado: Estado? { bocetos ? valor("estado").flatMap(Estado.init(rawValue:)) : nil }
    static var ir: String? { valor("ir") }
    static var abrir: String? { valor("abrir") }
    /// `-abrir` vale una sola vez por arranque: si la vista que lo aplica se recrea (al sustituir cambia el motor), no
    /// tiene que volver a abrir lo mismo al volver a la lista.
    @MainActor static var abrioYa: Set<String> = []
    static var lleno: Bool { bocetos && valor("demo") == "lleno" }
    static var seriesHechas: Int { Int(valor("series") ?? "") ?? 0 }
    static var sinDescanso: Bool { valor("descanso") == "no" }

    private static func valor(_ clave: String) -> String? {
        #if DEBUG
        UserDefaults.standard.string(forKey: clave)
        #else
        nil
        #endif
    }
}

extension ModeloApp {
    /// Sin modelo de la cuenta: en la demo ("Ver demo", sin cuenta, nada se escribe) y en los bocetos de diseño. Con una
    /// cuenta, todo sale de este modelo.
    var conMuestras: Bool { esDemo || DemoUI.bocetos }
}

extension Muestras {
    /// Lo que la raíz les pasa a las pantallas. Las muestras (`Muestras.bundle`, datos de la cuenta de prueba) son solo
    /// de los bocetos de diseño: en Release el bundle no se empaqueta (EXCLUDED_SOURCE_FILE_NAMES) y esto queda vacío.
    static func deLaApp() -> Muestras {
        #if DEBUG
        cargar()
        #else
        vacias
        #endif
    }

    /// Lo que ve una pantalla sin cuenta: las muestras solo en los bocetos; la demo, como la web, sin datos de nadie
    /// (Revisión vacía, el chat para escribirle a Mati, Progreso sin historial). Mi Día de la demo es la semilla de la
    /// web (`MuestrasExtra.demo`), que no sale de acá.
    func paraPantalla() -> Muestras { DemoUI.bocetos ? self : .vacias }

    static let vacias = Muestras(info: nil, rutina: nil, dieta: nil, historial: [], sesionesSemana: [], salud: [],
                                 recuperacion: [], chat: [], habitos: nil, racha: nil, adherencia: [], checkin: nil,
                                 fotos: [], comidasMarcadas: [])
}

/// Mi Día y el check cuando no hay cuenta. Se arman con la MISMA forma que devuelve el servidor (decodificando JSON) y
/// con fechas relativas a hoy.
enum MuestrasExtra {
    struct MiDia {
        let racha: Racha?
        let habitos: HabitosDia?
        let adherencia: [DiaAdherencia]
    }

    /// La demo de la web (cliente.html:8873): racha de 3 hasta hoy y el día de hoy cargado.
    static var demo: MiDia {
        MiDia(racha: decodificar(#"{"streak": 3, "ultimo_dia_valido": "\#(FechaLocal.hoy())"}"#),
              habitos: decodificar(#"{"fecha": "\#(FechaLocal.hoy())", "entrenamiento": "entrene", "comio_segun_plan": true, "durmio_bien": true, "cardio": false, "vasos_agua": 2}"#),
              adherencia: dias([true, true, true, false, true, false, false, true, true, false, true, true, false, false, true,
                                true, false, true, true, true, false, true, false, false, true, true, true, false, true, false]))
    }

    /// Bocetos llenos (`-demo lleno`): 9 días seguidos y 30 días con historia.
    static var lleno: MiDia {
        MiDia(racha: decodificar(#"{"streak": 9, "ultimo_dia_valido": "\#(DiaCalendario.texto((DiaCalendario.numero(FechaLocal.hoy()) ?? 0) - 1))"}"#),
              habitos: decodificar(#"{"fecha": "\#(FechaLocal.hoy())", "entrenamiento": "entrene", "comio_segun_plan": true, "durmio_bien": false, "cardio": null, "vasos_agua": 5}"#),
              adherencia: dias([false, true, true, true, true, true, true, true, true, true, false, true, true, false, true,
                                true, true, false, false, true, true, true, true, false, true, true, true, true, false, false]))
    }

    static let checkinLleno: CheckinSemana? = decodificar(
        #"{"energia": 4, "descanso": 3, "hambre": 2, "adherencia": 5, "nota": "Bien la semana, el sábado me pasé un poco en el cumple."}"#
    )

    /// 30 días hacia atrás desde hoy (el primero del patrón es hoy). Los no cumplidos alternan parcial y vacío.
    private static func dias(_ patron: [Bool]) -> [DiaAdherencia] {
        let hoy = DiaCalendario.numero(FechaLocal.hoy()) ?? 0
        let filas = patron.enumerated().map { i, valido -> String in
            let fecha = DiaCalendario.texto(hoy - i)
            let parcial = !valido && i % 3 == 0
            let entreno = valido ? (i % 2 == 0 ? "\"entrene\"" : "\"descanso\"") : (parcial ? "\"entrene\"" : "null")
            return #"{"fecha": "\#(fecha)", "entrenamiento": \#(entreno), "comio_segun_plan": \#(valido || parcial ? "true" : "null"), "durmio_bien": \#(valido ? "true" : "null"), "vasos_agua": \#(valido ? 8 : 2), "es_valido": \#(valido)}"#
        }
        return decodificar("[\(filas.joined(separator: ","))]") ?? []
    }

    private static func decodificar<T: Decodable>(_ json: String) -> T? {
        try? JSONDecoder().decode(T.self, from: Data(json.utf8))
    }
}
