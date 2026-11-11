import Foundation

/// El check guiado (2.3.0): el check de la semana, un paso por pantalla. Guarda lo mismo que el check de siempre (las
/// cuatro escalas y la nota por `checkin`, el peso por `peso`, las fotos por su cola) y suma una sola cosa: lo que el
/// alumno marca en «¿Notaste algo de esto?» (`check_guiado`). Las mismas reglas están en Android (`CheckGuiado.kt`) y en
/// la web; los casos compartidos, en `apps/shared/vectores/check_guiado.json`.
public enum CheckGuiado {
    public enum Paso: String, Codable, Sendable, CaseIterable {
        case peso, escalas, fotos, senales, nota, resumen
    }

    /// Qué lista de «¿Notaste algo?» le toca: la de ciclo solo si el servidor dice explícitamente que está en ciclo.
    public enum Catalogo: String, Codable, Sendable {
        case general, ciclo
        public init(enCiclo: Bool) { self = enCiclo ? .ciclo : .general }
    }

    public struct Opcion: Equatable, Sendable {
        public let clave: String
        public let etiqueta: String
    }

    /// «Nada de esto»: se guarda para distinguir «no pasó nada» de «no contestó». No convive con otra.
    public static let ninguno = "ninguno"

    public static func opciones(_ c: Catalogo) -> [Opcion] {
        switch c {
        case .general: [
            Opcion(clave: "dolor", etiqueta: "Dolor o molestia al entrenar"),
            Opcion(clave: "digestion", etiqueta: "Digestión pesada o malestar"),
            Opcion(clave: "animo", etiqueta: "Ánimo bajo"),
            Opcion(clave: "enfermo", etiqueta: "Estuve enfermo"),
            Opcion(clave: ninguno, etiqueta: "Nada de esto"),
        ]
        case .ciclo: [
            Opcion(clave: "acne", etiqueta: "Acné o piel grasa"),
            Opcion(clave: "retencion", etiqueta: "Retención de líquido o hinchazón"),
            Opcion(clave: "pecho", etiqueta: "Sensibilidad en el pecho"),
            Opcion(clave: "cabeza", etiqueta: "Dolor de cabeza o presión alta"),
            Opcion(clave: "animo", etiqueta: "Irritabilidad o cambios de ánimo"),
            Opcion(clave: "libido", etiqueta: "Cambios en el deseo sexual"),
            Opcion(clave: "sueno", etiqueta: "Insomnio o sudor de noche"),
            Opcion(clave: "aplicacion", etiqueta: "Dolor en la zona de aplicación"),
            Opcion(clave: ninguno, etiqueta: "Nada de esto"),
        ]
        }
    }

    public static func titulo(_ p: Paso, catalogo: Catalogo = .general) -> String {
        switch p {
        case .peso: "¿Cuánto pesaste hoy?"
        case .escalas: "¿Cómo venís esta semana?"
        case .fotos: "Tus fotos de la semana"
        case .senales: catalogo == .ciclo ? "¿Notaste algo de esto?" : "¿Algo de esto esta semana?"
        case .nota: "¿Algo que quieras contarme?"
        case .resumen: "Así va tu check"
        }
    }

    public static func apoyo(_ p: Paso, catalogo: Catalogo = .general) -> String {
        switch p {
        case .peso: "En ayunas, al despertar."
        case .escalas: "Del 1 al 5. Mati lo ve antes de tu devolución."
        case .fotos: "Frente, perfil y espalda. Mismo lugar y misma luz que siempre. Las ve solo Mati."
        case .senales: catalogo == .ciclo
            ? "Marcá lo que haya aparecido esta semana. Mati lo mira antes de tu devolución."
            : "Marcá lo que te haya pasado. Si no hubo nada, mejor."
        case .nota: "Es opcional. Lo lee Mati."
        case .resumen: "Tocá una fila si querés cambiar algo."
        }
    }

    /// La salida discreta de cada paso (lo que deja seguir sin contestar). nil = no se puede saltear.
    public static func omitir(_ p: Paso) -> String? {
        switch p {
        case .peso: "Hoy no me pesé"
        case .fotos: "Las subo después"
        default: nil
        }
    }

    /// Los pasos de esta vez. Las fotos entran solo si al abrir faltaba alguna de las tres de la semana (y no se van al
    /// subir la última: la lista se arma una vez, al abrir).
    public static func pasos(faltanFotos: Bool) -> [Paso] {
        Paso.allCases.filter { $0 != .fotos || faltanFotos }
    }

    /// Tocar una opción: se marca o se desmarca. «Nada de esto» borra las demás, y cualquiera de las demás la borra.
    public static func alternar(_ senales: [String], _ clave: String) -> [String] {
        if senales.contains(clave) { return senales.filter { $0 != clave } }
        if clave == ninguno { return [ninguno] }
        return senales.filter { $0 != ninguno } + [clave]
    }

    /// Lo que se manda: solo claves del catálogo, sin repetir, en el orden del catálogo y sin «ninguno» mezclado.
    public static func normalizar(_ senales: [String], _ c: Catalogo) -> [String] {
        let validas = opciones(c).map(\.clave).filter { senales.contains($0) }
        return validas.count > 1 ? validas.filter { $0 != ninguno } : validas
    }

    /// El borrador de la semana: lo que el alumno lleva contestado. Vive en el teléfono hasta que manda el check.
    public struct Borrador: Codable, Equatable, Sendable {
        /// El lunes de la semana del borrador: el de otra semana no sirve.
        public var semana: String
        public var paso: Paso
        public var peso: String
        public var valores: [String: Int]
        public var catalogo: Catalogo
        public var senales: [String]
        public var nota: String

        public init(semana: String, paso: Paso = .peso, peso: String = "", valores: [String: Int] = [:],
                    catalogo: Catalogo = .general, senales: [String] = [], nota: String = "") {
            self.semana = semana; self.paso = paso; self.peso = peso; self.valores = valores
            self.catalogo = catalogo; self.senales = senales; self.nota = nota
        }

        /// ¿Contestó algo? Un borrador sin nada no cuenta como «a medias».
        public var empezado: Bool {
            !peso.trimmingCharacters(in: .whitespaces).isEmpty || valores.values.contains { $0 > 0 } || !senales.isEmpty
                || !nota.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    /// El borrador con el que se abre: el guardado si es de esta semana; si no, uno nuevo con lo que ya está enviado.
    /// Si el perfil cambió (otro catálogo), lo marcado con la lista anterior no vale.
    public static func abrir(guardado: Borrador?, semana: String, catalogo: Catalogo, enviado: (valores: [String: Int], nota: String)?,
                             senalesEnviadas: [String]?, catalogoEnviado: Catalogo?) -> Borrador {
        if var b = guardado, b.semana == semana {
            if b.catalogo != catalogo { b.catalogo = catalogo; b.senales = [] }
            return b
        }
        var b = Borrador(semana: semana, catalogo: catalogo)
        if let enviado {
            b.valores = enviado.valores
            b.nota = enviado.nota
            b.paso = .resumen
        }
        if let senalesEnviadas, catalogoEnviado == catalogo { b.senales = normalizar(senalesEnviadas, catalogo) }
        return b
    }

    /// En qué paso se abre: donde lo dejó, si ese paso sigue estando; si no, el primero.
    public static func retomar(_ b: Borrador, pasos: [Paso]) -> Paso {
        pasos.contains(b.paso) ? b.paso : (pasos.first ?? .peso)
    }

    /// ¿Se puede seguir desde este paso? El peso vacío no sigue (para eso está «Hoy no me pesé»); con algo escrito
    /// sigue, y si no es un peso válido lo dice la pantalla. Las fotos, con las tres.
    public static func puedeSeguir(_ p: Paso, _ b: Borrador, fotosHechas: Int = 0) -> Bool {
        switch p {
        case .peso: !b.peso.trimmingCharacters(in: .whitespaces).isEmpty
        case .escalas: CheckinSemanal.faltan(b.valores) == nil
        case .fotos: fotosHechas >= 3
        case .senales: !normalizar(b.senales, b.catalogo).isEmpty
        case .nota, .resumen: true
        }
    }

    /// Lo que falta para poder mandar (el resumen lo dice en vez de dejar el botón gris sin explicación).
    public static func faltaParaEnviar(_ b: Borrador) -> String? {
        if let f = CheckinSemanal.faltan(b.valores) { return f }
        if normalizar(b.senales, b.catalogo).isEmpty { return "Falta: \(titulo(.senales, catalogo: b.catalogo))" }
        return nil
    }

    /// El primer paso al que hay que volver para completar lo que falta.
    public static func pasoQueFalta(_ b: Borrador) -> Paso? {
        if CheckinSemanal.faltan(b.valores) != nil { return .escalas }
        if normalizar(b.senales, b.catalogo).isEmpty { return .senales }
        return nil
    }

    /// «Acné o piel grasa, Retención de líquido o hinchazón» para la fila del resumen.
    public static func textoSenales(_ senales: [String], _ c: Catalogo) -> String {
        let n = normalizar(senales, c)
        return opciones(c).filter { n.contains($0.clave) }.map(\.etiqueta).joined(separator: ", ")
    }

    // MARK: - La tarjeta de Revisión

    public enum Estado: String, Equatable, Sendable { case sinEmpezar, aMedias, enviado, enviadoSinFotos }

    public static func estado(enviado: Bool, borrador: Borrador?, semana: String, faltanFotos: Bool) -> Estado {
        // Un borrador de esta semana posterior al envío («Cambiar algo» sin terminar) no lo vuelve a «a medias».
        if enviado { return faltanFotos ? .enviadoSinFotos : .enviado }
        if let borrador, borrador.semana == semana, borrador.empezado { return .aMedias }
        return .sinEmpezar
    }

    public static func textoTarjeta(_ e: Estado) -> String {
        switch e {
        case .sinEmpezar: "Un minuto: tu peso, cómo venís y tus fotos. Mati lo ve antes de tu devolución."
        case .aMedias: "Lo dejaste por la mitad. Seguís donde quedaste."
        case .enviado: "Enviado. Mati lo ve antes de tu devolución."
        case .enviadoSinFotos: "Enviado. Te faltan las fotos de la semana."
        }
    }

    public static func botonTarjeta(_ e: Estado) -> String {
        switch e {
        case .sinEmpezar: "Empezar"
        case .aMedias: "Seguir"
        case .enviado: "Cambiar algo"
        case .enviadoSinFotos: "Subir fotos"
        }
    }
}

extension PesoCorporal {
    /// Lo que se le dice al alumno cuando el peso que escribió no se puede guardar.
    public static let avisoRango = "Revisá el peso: tiene que estar entre 30 y 300 kg."
}
