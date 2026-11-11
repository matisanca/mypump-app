import Foundation
import MyPumpModelos
import MyPumpReglas
import MyPumpDatos

/// Argumentos de lanzamiento para capturas de diseño, sin tocar la pantalla (solo en DEBUG):
///
///     simctl launch … -bocetos YES                         (las pestañas con las muestras, sin cuenta ni bienvenida)
///     simctl launch … -pestana revision -ir check         (abre en Revisión, desplazado hasta el check; o -ir fotos)
///     simctl launch … -pestana entreno -abrir ejercicio    (entra al primer ejercicio de trabajo)
///     simctl launch … -pestana revision -abrir misdatos    (Mis datos)
///     simctl launch … -pestana salud -segmento fuerza -abrir detalle  (detalle del primer ejercicio)
///     simctl launch … -pestana salud -segmento cuerpo      (el segmento de Salud: recuperacion, fuerza o cuerpo)
///     simctl launch … -estado cargando|vacio|error         (estados de carga, vacío y error, con -bocetos)
///     simctl launch … -demo lleno                          (el check lleno, con -bocetos)
///     simctl launch … -series 2                            (el ejercicio abierto con 2 series ya confirmadas)
///     simctl launch … -descanso no                         (sin el descanso de muestra)
///     simctl launch … -metas muestra -pasos 7420           (el «Pump del día» de muestra; -pasosLuego 10240 lo llena)
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
    /// `-segmento recuperacion|fuerza|cuerpo`: el segmento con que abre Salud.
    static var segmento: String? { valor("segmento") }
    /// `-abrir` vale una sola vez por arranque: si la vista que lo aplica se recrea (al sustituir cambia el motor), no
    /// tiene que volver a abrir lo mismo al volver a la lista.
    @MainActor static var abrioYa: Set<String> = []
    static var lleno: Bool { bocetos && valor("demo") == "lleno" }
    static var seriesHechas: Int { Int(valor("series") ?? "") ?? 0 }
    static var sinDescanso: Bool { valor("descanso") == "no" }
    /// `-historial muestra`: la demo con historial (60 kg × 10 hace 4 días en cada ejercicio), para ver el kg sugerido, la
    /// preparación con kg y el aviso de récord sin cuenta.
    static var historialDeMuestra: Bool { valor("historial") == "muestra" || cuatroSeries }
    /// `-historial muestra4` (prototipo de carga): 80 kg × 10, 10, 9 y 8, para contar los toques de hoy.
    static var cuatroSeries: Bool { valor("historial") == "muestra4" }

    /// `-aumento prueba`: la demo con el aumento sugerido a la vista, para las capturas. La demo siempre está en la semana 1,
    /// donde el plan nunca baja las reps, y la regla no se toca: se arranca como si ya estuviera sugerido.
    @MainActor static func aplicarAumentoDePrueba(motor: ModeloEntreno, lugar: String, ejercicio: Ejercicio) {
        #if DEBUG
        // La carga llega con el historial, un momento después de abrir: se aplica la primera vez que la hay.
        guard valor("aumento") == "prueba", motor.cargaSimple(lugar)?.carga != nil, abrioYa.insert("aumento-\(lugar)").inserted else { return }
        motor.cambiarCarga(lugar) { c in
            guard let desde = c.carga, let hasta = AumentoCarga.hasta(desde: desde, equipo: c.equipo) else { return }
            var e = c.estado
            e.aumento = .sugerido(desde: desde, hasta: hasta)
            c = CargaSimple(ejercicio: ejercicio, semana: 1, ultimaVez: c.ultimaVez, equipo: c.equipo, estado: e)
        }
        #endif
    }

    /// `-cardio prueba`: la demo con la cinta tal como la manda el plan (sin duración, `progresion: []`), como cardio al
    /// principio del día 1 y como calentamiento al principio del día 2 (reporte del 4-nov: pedía reps, kg y RIR).
    static var cardioDePrueba: Bool { valor("cardio") == "prueba" }

    /// `-metas muestra` (con la demo o los bocetos): el «Pump del día» con la meta de 10.000 pasos, una racha y la semana de
    /// muestra, y el ritmo de peso. `-pasos 7420` fija los de hoy; `-pasosLuego 10240` los sube a los 5 s (el video de la
    /// celebración). `-metas sinsalud`: la meta sin Salud conectada.
    static var metas: String? { valor("metas") }
    static var pasosHoy: Double? { valor("pasos").flatMap(Double.init) }
    static var pasosLuego: Double? { valor("pasosLuego").flatMap(Double.init) }

    static func conCintaDePrueba(_ rutina: Data) -> Data {
        guard var raiz = (try? JSONSerialization.jsonObject(with: rutina)) as? [String: Any],
              var dias = raiz["dias"] as? [[String: Any]], dias.count >= 2 else { return rutina }
        func cinta(_ tipo: String, _ dia: String) -> [String: Any] {
            ["id": "cinta-caminata-inclinada-10-min-\(dia)-0", "tipo": tipo, "nombre": "Cinta (caminata inclinada 10 min)",
             "catalogo_slug": "Walking_Treadmill", "progresion": [Any](), "descanso_segundos": 0]
        }
        for (i, tipo) in [(0, "cardio"), (1, "calentamiento")] {
            guard var bloques = dias[i]["bloques"] as? [[String: Any]], var ej = bloques.first?["ejercicios"] as? [[String: Any]] else { continue }
            ej.insert(cinta(tipo, "d\(i + 1)"), at: 0)
            bloques[0]["ejercicios"] = ej
            dias[i]["bloques"] = bloques
        }
        raiz["dias"] = dias
        return (try? JSONSerialization.data(withJSONObject: raiz)) ?? rutina
    }

    /// Las dos series de muestra (sin datos reales).
    static func filasDeMuestra(_ clave: String) -> [RegistroHistorico] {
        let hace4 = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-4 * 86400))
        let filas: [(Int, Int, Int)] = cuatroSeries ? [(1, 10, 80), (2, 10, 80), (3, 9, 80), (4, 8, 80)] : [(1, 10, 60), (2, 10, 60)]
        let j = filas.map { #"{"clave":"\#(clave)","registrado_en":"\#(hace4)","peso_kg":\#($0.2),"reps_realizadas":\#($0.1),"rir_real":2,"serie_numero":\#($0.0)}"# }
        return (try? JSONDecoder().decode([RegistroHistorico].self, from: Data("[\(j.joined(separator: ","))]".utf8))) ?? []
    }

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
    /// La demo con su historial de ejemplo (2.3.0). En los bocetos de DEBUG no: ahí mandan las muestras de siempre.
    var demoConHistorial: Bool { esDemo && demoHistorial != nil && !DemoUI.bocetos }
}

/// El historial de la demo (`Demo.bundle/historial.json`, también en Release): series, peso, pasos, chat, devolución,
/// metas y la lista previa de ejemplo. No sale de ninguna cuenta ni se escribe en ningún lado.
enum DemoHistorialApp {
    static var datos: Data? {
        #if DEBUG
        // Los bocetos, `-historial muestra` y `-demoHistorial NO` quedan como siempre (capturas y pruebas viejas).
        let d = UserDefaults.standard
        if d.bool(forKey: "bocetos") || d.string(forKey: "historial") != nil || d.string(forKey: "demoHistorial") == "NO" { return nil }
        #endif
        return Bundle.main.url(forResource: "historial", withExtension: "json", subdirectory: "Demo.bundle").flatMap { try? Data(contentsOf: $0) }
    }
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

    /// Lo que ve una pantalla sin cuenta: las muestras solo en los bocetos. La demo (2.3.0) muestra su historial de
    /// ejemplo (`Demo.bundle/historial.json`, que no es de nadie): las series de cada ejercicio, el peso y los pasos, y
    /// una charla con Mati. Sin ese historial queda como antes: vacía.
    @MainActor func paraPantalla() -> Muestras {
        if DemoUI.bocetos { return self }
        let m = Proveedor.modelo
        guard m.esDemo, let h = m.demoHistorial else { return .vacias }
        return Muestras(info: nil, rutina: m.rutina, dieta: nil, historial: h.historial, sesionesSemana: [], salud: h.salud,
                        recuperacion: [], chat: h.chat, checkin: nil, fotos: [], comidasMarcadas: [])
    }

    static let vacias = Muestras(info: nil, rutina: nil, dieta: nil, historial: [], sesionesSemana: [], salud: [],
                                 recuperacion: [], chat: [], checkin: nil,
                                 fotos: [], comidasMarcadas: [])
}

/// El check cuando no hay cuenta. Se arman con la MISMA forma que devuelve el servidor (decodificando JSON) y
/// con fechas relativas a hoy.
enum MuestrasExtra {
    static let checkinLleno: CheckinSemana? = decodificar(
        #"{"energia": 4, "descanso": 3, "hambre": 2, "adherencia": 5, "nota": "Bien la semana, el sábado me pasé un poco en el cumple."}"#
    )

    private static func decodificar<T: Decodable>(_ json: String) -> T? {
        try? JSONDecoder().decode(T.self, from: Data(json.utf8))
    }
}
