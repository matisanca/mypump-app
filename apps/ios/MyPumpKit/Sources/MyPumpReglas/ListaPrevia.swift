import Foundation
import MyPumpModelos

/// La lista previa a la videollamada de comienzo (2.3.0, palanca `lista_previa`): lo que devuelve `mypump_lista_previa` →
/// lo que se muestra. La referencia es `scripts/nativa/generar-vectores-cola-a.py` y los vectores de
/// `apps/shared/vectores/lista_previa.json`.
///
/// Solo con `ok` y `activa` en true. Un ítem vale si es un objeto con una clave conocida y un estado conocido; una clave
/// repetida, la primera. `opcional` solo si es true. `faltan` solo en la guía, si falta, y si es un entero >= 1. Sin ítems
/// válidos no se muestra nada. El orden es el del servidor.
public enum ReglasListaPrevia {
    /// A dónde lleva tocar un punto que falta.
    public enum Destino: String, Equatable, Sendable {
        /// La guía de videos.
        case guia
        /// Las fotos de Revisión.
        case fotos
    }

    public struct Item: Equatable, Sendable, Identifiable {
        public let clave: String
        public let titulo: String
        public let hecho: Bool
        public let opcional: Bool
        public let detalle: String?
        /// nil: la fila no es un botón.
        public let destino: Destino?
        public let accesible: String
        public var id: String { clave }
    }

    public struct Vista: Equatable, Sendable {
        public let items: [Item]
        /// «Llevás 1 de 3» o «Ya tenés todo listo»; nil con solo opcionales.
        public let resumen: String?
        public let todoListo: Bool
    }

    public static let titulo = "Antes de la videollamada"
    public static let todoListo = "Ya tenés todo listo"
    public static let consejo = "Ese día buscá un lugar tranquilo y con buena conexión."
    public static let opcional = "Opcional"
    public static let hecho = "Hecho"
    public static let falta = "Falta"

    /// En el orden en que se conocen (el que manda es el del servidor).
    public static let titulos: [String: String] = [
        "guia": "Mirar los videos de tu guía",
        "dudas": "Dejarle tus dudas a Mati",
        "formulario": "Responder las preguntas de Mati",
        "fotos": "Subir tus fotos de inicio",
        "estudios": "Subir tus estudios",
        "contrato": "Firmar el contrato",
    ]
    public static let destinos: [String: Destino] = ["guia": .guia, "dudas": .guia, "fotos": .fotos]

    public static func vista(_ j: JSONValue?) -> Vista? {
        guard let j, case .objeto = j, j["ok"] == .bool(true), j["activa"] == .bool(true), case .lista(let lista)? = j["items"] else { return nil }
        var items: [Item] = []
        var vistas = Set<String>()
        for it in lista {
            guard case .objeto = it, case .texto(let clave)? = it["clave"], case .texto(let estado)? = it["estado"],
                  let titulo = titulos[clave], estado == "hecho" || estado == "falta", !vistas.contains(clave) else { continue }
            vistas.insert(clave)
            let hecho = estado == "hecho"
            let opcional = it["opcional"] == .bool(true)
            var detalle: String?
            if !hecho, clave == "guia", case .numero(let n)? = it["faltan"], n.isFinite, n == n.rounded(), n >= 1, n < 1e9 {
                detalle = Int(n) == 1 ? "Te falta 1 video" : "Te faltan \(Int(n)) videos"
            } else if !hecho, opcional {
                detalle = Self.opcional
            }
            let partes: [String?] = [titulo, hecho ? Self.hecho : (opcional ? detalle : Self.falta), (detalle != nil && !opcional) ? detalle : nil]
            items.append(Item(clave: clave, titulo: titulo, hecho: hecho, opcional: opcional, detalle: detalle,
                              destino: hecho ? nil : destinos[clave], accesible: partes.compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")))
        }
        guard !items.isEmpty else { return nil }
        let obligatorios = items.filter { !$0.opcional }
        let hechos = obligatorios.filter(\.hecho).count
        let resumen: String?
        if obligatorios.isEmpty {
            resumen = nil
        } else if hechos == obligatorios.count {
            resumen = todoListo
        } else {
            resumen = "Llevás \(hechos) de \(obligatorios.count)"
        }
        return Vista(items: items, resumen: resumen, todoListo: !obligatorios.isEmpty && hechos == obligatorios.count)
    }
}
