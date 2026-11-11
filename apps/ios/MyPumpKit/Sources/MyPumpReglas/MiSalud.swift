/// «Mi salud» (pedido de Mati del 11/11): una sola pantalla con todo lo de salud, que se abre desde Revisión sin sumar
/// pestañas. Acá solo se decide qué bloques van, qué dice la tarjeta de Revisión y a qué bloque lleva cada destino viejo.
/// Cada bloque va solo si su palanca o su condición de hoy lo muestra (las mismas de antes: acá no hay palancas nuevas).
/// Los mismos textos en iPhone y Android (`nativa-evidencia/mi-salud/DECISIONES.md`, `MiSalud.kt`).
public enum MiSalud {
    public static let titulo = "Mi salud"

    /// Los bloques, en el orden de la pantalla.
    public enum Bloque: String, CaseIterable, Sendable {
        case control, estudios, presion, recuperacion

        public var nombre: String {
            switch self {
            case .control: "control"
            case .estudios: "estudios"
            case .presion: "presión"
            case .recuperacion: "recuperación"
            }
        }
        /// Para las pruebas y el desplazamiento (`mi-salud-bloque-presion`), igual que en Android.
        public var etiqueta: String { "mi-salud-bloque-\(rawValue)" }
    }

    /// Lo que se sabe hoy de cada parte.
    public struct Partes: Equatable, Sendable {
        /// Hay «Próximo control» en Estudios.
        public var control: Bool
        /// La sección Estudios existe (palanca prendida, servidor nuevo, habilitada).
        public var estudios: Bool
        /// La sección Presión está habilitada.
        public var presion: Bool
        /// La recuperación (Salud) se puede abrir: como estaba en Revisión, siempre.
        public var recuperacion: Bool

        public init(control: Bool = false, estudios: Bool = false, presion: Bool = false, recuperacion: Bool = true) {
            self.control = control; self.estudios = estudios; self.presion = presion; self.recuperacion = recuperacion
        }
    }

    /// Qué pide hoy cada parte (lo de las tarjetas del inicio). nil o false: nada.
    public struct Pendientes: Equatable, Sendable {
        /// El texto de la tarjeta de estudios del inicio (novedad o algo por hacer).
        public var estudios: String?
        /// El control de salud está cerca (la tarjeta del control del inicio se ve).
        public var control: Bool
        /// La línea de presión cuando pide algo; nil si no pide nada (o ya hizo la de hoy).
        public var presion: String?

        public init(estudios: String? = nil, control: Bool = false, presion: String? = nil) {
            self.estudios = estudios; self.control = control; self.presion = presion
        }
    }

    public static func bloques(_ p: Partes) -> [Bloque] {
        var l: [Bloque] = []
        if p.control { l.append(.control) }
        if p.estudios { l.append(.estudios) }
        if p.presion { l.append(.presion) }
        if p.recuperacion { l.append(.recuperacion) }
        return l
    }

    /// La tarjeta de Revisión: sin ningún bloque no existe. `cuenta` = cosas pendientes (no ítems), de 0 a 3.
    public struct Tarjeta: Equatable, Sendable {
        public let linea: String
        public let cuenta: Int
    }

    public static let controlCerca = "Tu próximo control de salud"
    public static let repetirPresion = "Te falta repetir la toma de presión"
    public static let prepararPresion = "Primero medí tu brazo y anotá tu tensiómetro"
    public static func faltanTomas(_ n: Int) -> String { n == 1 ? "Te falta 1 toma de presión" : "Te faltan \(n) tomas de presión" }
    /// La fila del bloque de presión que abre la pantalla de Presión (la guía y las tomas).
    public static let verPresion = "Ver mis tomas y cómo medirme"
    /// La fila de Mis datos y lo que lee VoiceOver de la tarjeta.
    public static let abre = "Abre Mi salud"
    /// Se llegó por un link o un aviso y no hay ningún bloque.
    public static let vacio = "Por ahora no hay nada de salud para mostrar."
    public static let tituloEstudios = "Estudios y órdenes"
    public static let tituloPresion = "Presión arterial"

    public static func tarjeta(_ p: Partes, pendientes: Pendientes) -> Tarjeta? {
        let b = bloques(p)
        guard !b.isEmpty else { return nil }
        let lineas = [
            p.estudios ? pendientes.estudios : nil,
            pendientes.control && (p.control || p.estudios) ? controlCerca : nil,
            p.presion ? pendientes.presion : nil,
        ].compactMap { $0 }
        return Tarjeta(linea: lineas.first ?? lista(b), cuenta: lineas.count)
    }

    // MARK: Entreno (simplificar, 11/11)

    /// La tarjeta de arriba de Entreno: en lugar de las tres viejas (presión, estudios y control), una sola, y solo con algo
    /// para hacer. Lleva a lo primero pendiente, en el mismo orden que la línea de la tarjeta de Revisión.
    public static let cejaInicio = "Mi salud"

    /// El bloque de lo primero pendiente (estudios, control, presión), o nil sin nada para hacer. Las mismas condiciones que
    /// `tarjeta`: el control cuenta con el bloque de control o con Estudios.
    public static func primerPendiente(_ p: Partes, pendientes: Pendientes) -> Bloque? {
        if p.estudios, pendientes.estudios != nil { return .estudios }
        // El control lleva a su bloque si está; si no, a Estudios (lo decide quien navega, con `Partes.control`).
        if pendientes.control, p.control || p.estudios { return .control }
        if p.presion, pendientes.presion != nil { return .presion }
        return nil
    }

    /// Debajo de la línea, cuando hay más de una cosa: «Y 1 cosa más» / «Y 2 cosas más». nil con una sola.
    public static func masCosas(_ cuenta: Int) -> String? {
        switch cuenta {
        case ...1: nil
        case 2: "Y 1 cosa más"
        default: "Y \(cuenta - 1) cosas más"
        }
    }

    /// «Control, estudios, presión y recuperación».
    public static func lista(_ bloques: [Bloque]) -> String {
        let n = bloques.map(\.nombre)
        let texto: String
        switch n.count {
        case 0: texto = ""
        case 1: texto = n[0]
        default: texto = n.dropLast().joined(separator: ", ") + " y " + n[n.count - 1]
        }
        return texto.prefix(1).uppercased() + texto.dropFirst()
    }
}
