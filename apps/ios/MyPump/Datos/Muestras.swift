import Foundation
import MyPumpModelos
import MyPumpReglas

/// Datos para los bocetos: las respuestas REALES de la cuenta de prueba test-nativa-real, empaquetadas en
/// Muestras.bundle. Cuando se cablee la app, esto lo reemplaza la fuente en vivo (API + caché + outbox), con la misma
/// forma.
struct Muestras: Sendable {
    let info: ClienteInfo?
    let rutina: RutinaActiva?
    let dieta: DietaActiva?
    let historial: [RegistroHistorico]
    let sesionesSemana: [Sesion]
    let salud: [FilaSalud]
    let recuperacion: [Recuperacion]
    let chat: [MensajeChat]
    let habitos: HabitosDia?
    let racha: Racha?
    let adherencia: [DiaAdherencia]
    let checkin: CheckinSemana?
    let fotos: [FotoProgreso]
    let comidasMarcadas: [ComidaMarcada]

    static func cargar() -> Muestras {
        let bundle = Bundle.main.url(forResource: "Muestras", withExtension: "bundle").flatMap(Bundle.init(url:))
        func leer<T: Decodable>(_ nombre: String, _ tipo: T.Type) -> T? {
            guard let url = bundle?.url(forResource: nombre, withExtension: "json"),
                  let data = try? Data(contentsOf: url) else { return nil }
            return try? JSONDecoder().decode(T.self, from: data)
        }
        return Muestras(
            info: leer("get_cliente_info", [ClienteInfo].self)?.first,
            rutina: leer("get_rutina_activa", [RutinaActiva].self)?.first,
            dieta: leer("get_dieta_activa", [DietaActiva].self)?.first,
            historial: leer("get_historico_por_clave", [RegistroHistorico].self) ?? [],
            sesionesSemana: leer("get_sesiones_semana", [Sesion].self) ?? [],
            salud: leer("get_salud", [FilaSalud].self) ?? [],
            recuperacion: leer("get_recuperacion", [Recuperacion].self) ?? [],
            chat: Self.chatDeEjemplo,
            habitos: leer("get_habitos_dia", [HabitosDia].self)?.first,
            racha: leer("get_streak", [Racha].self)?.first,
            adherencia: leer("get_adherencia_30d", [DiaAdherencia].self) ?? [],
            checkin: leer("get_checkin_semana", [CheckinSemana].self)?.first,
            fotos: leer("get_fotos_progreso", [FotoProgreso].self) ?? [],
            comidasMarcadas: leer("get_comidas_marcadas", [ComidaMarcada].self) ?? []
        )
    }

    /// La cuenta de prueba es invisible para el coach y no tiene chat: para el boceto se arma una conversación tipo.
    static let chatDeEjemplo: [MensajeChat] = {
        let json = """
        [{"id":"1","autor":"coach","contenido":"¿Cómo venís con la semana 5? Acordate que bajan las reps y sube la carga.","created_at":"2026-10-12T14:02:00Z"},
         {"id":"2","autor":"cliente","contenido":"Bien! El jalón lo subí a 55, me costó la última serie","created_at":"2026-10-12T18:40:00Z"},
         {"id":"3","autor":"coach","contenido":"Perfecto, así es. Si la próxima te salen las 6 limpias, subí 2,5.","created_at":"2026-10-12T18:52:00Z"},
         {"id":"4","autor":"cliente","contenido":"Dale. Una duda: el sábado tengo un cumple, ¿qué hago con la cena?","created_at":"2026-10-13T11:15:00Z"}]
        """
        return (try? JSONDecoder().decode([MensajeChat].self, from: Data(json.utf8))) ?? []
    }()
}

// MARK: - Lo que la pantalla necesita derivar (se mueve a MyPumpReglas, con vectores, al cablear)

struct ResumenHistorial: Sendable {
    let ultima: [RegistroHistorico]
    let ultimaFecha: Date?
    let recordKg: Double?
}

extension Muestras {
    var historialPorClave: [String: [RegistroHistorico]] {
        Dictionary(grouping: historial) { $0.clave ?? "" }
    }

    func resumen(de ejercicio: Ejercicio) -> ResumenHistorial? {
        let filas = historialPorClave[ClaveEjercicio.de(ejercicio.nombre)] ?? []
        guard !filas.isEmpty else { return nil }
        let porFecha = Dictionary(grouping: filas) { String($0.registradoEn.prefix(10)) }
        guard let dia = porFecha.keys.max() else { return nil }
        let ultima = (porFecha[dia] ?? []).sorted { ($0.serie ?? 0) < ($1.serie ?? 0) }
        return ResumenHistorial(ultima: ultima, ultimaFecha: Fechas.dia(dia), recordKg: filas.compactMap(\.pesoKg).max())
    }
}

enum Fechas {
    /// "2026-10-13" (o el comienzo de un timestamp) → fecha local, con calendario gregoriano y en_US_POSIX.
    static func dia(_ s: String) -> Date? {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: String(s.prefix(10)))
    }

    static func haceCuanto(_ fecha: Date?) -> String {
        guard let fecha else { return "" }
        let dias = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: fecha),
                                                   to: Calendar.current.startOfDay(for: .now)).day ?? 0
        switch dias {
        case ..<1: return "hoy"
        case 1: return "ayer"
        default: return "hace \(dias) días"
        }
    }
}

extension Double {
    /// "52,5" / "55": como lo escribe un argentino, sin ",0".
    var kg: String {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "es_AR")
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 1
        return f.string(from: NSNumber(value: self)) ?? String(self)
    }
}
