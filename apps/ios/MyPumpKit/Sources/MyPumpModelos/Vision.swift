import Foundation

/// `data` de `POST /vision` (mini-vision) con `tipo: etiqueta`: la tabla nutricional leída de una foto.
/// `porcionG` 100 = valores por 100 g; otra porción = valores de esa porción.
public struct LecturaEtiqueta: Decodable, Sendable, Equatable {
    public let nombre: String?
    public let porcionG: Double?
    public let kcal: Double?
    public let prot: Double?
    public let carb: Double?
    public let fat: Double?
    /// "alta" | "media" | "baja".
    public let confianza: String?
    enum CodingKeys: String, CodingKey { case nombre, porcionG = "porcion_g", kcal, prot, carb, fat, confianza }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        nombre = c.texto(.nombre); porcionG = c.decimal(.porcionG); kcal = c.decimal(.kcal); prot = c.decimal(.prot)
        carb = c.decimal(.carb); fat = c.decimal(.fat); confianza = c.texto(.confianza)
    }
}

/// `data` de `POST /vision` con `tipo: plato`: la estimación de un plato (la descripción, la escala que usó la IA,
/// los alimentos con sus gramos y los totales).
public struct EstimacionPlato: Decodable, Sendable, Equatable {
    public struct AlimentoEstimado: Decodable, Sendable, Equatable {
        public let nombre: String?
        public let gramos: Double?
        public let kcal: Double?
        public let prot: Double?
        public let carb: Double?
        public let fat: Double?
        enum CodingKeys: String, CodingKey { case nombre, gramos, kcal, prot, carb, fat }
        public init(nombre: String?, gramos: Double?, kcal: Double?, prot: Double?, carb: Double?, fat: Double?) {
            self.nombre = nombre; self.gramos = gramos; self.kcal = kcal; self.prot = prot; self.carb = carb; self.fat = fat
        }
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            nombre = c.texto(.nombre); gramos = c.decimal(.gramos); kcal = c.decimal(.kcal); prot = c.decimal(.prot)
            carb = c.decimal(.carb); fat = c.decimal(.fat)
        }
    }
    public let descripcion: String?
    public let escala: String?
    public let alimentos: [AlimentoEstimado]
    public let kcal: Double?
    public let prot: Double?
    public let carb: Double?
    public let fat: Double?
    public let confianza: String?
    enum CodingKeys: String, CodingKey { case descripcion, escala, alimentos, kcal, prot, carb, fat, confianza }
    public init(descripcion: String?, escala: String?, alimentos: [AlimentoEstimado], kcal: Double?, prot: Double?,
                carb: Double?, fat: Double?, confianza: String?) {
        self.descripcion = descripcion; self.escala = escala; self.alimentos = alimentos; self.kcal = kcal; self.prot = prot
        self.carb = carb; self.fat = fat; self.confianza = confianza
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        descripcion = c.texto(.descripcion); escala = c.texto(.escala)
        alimentos = (try? c.decodeIfPresent([AlimentoEstimado].self, forKey: .alimentos)) ?? []
        kcal = c.decimal(.kcal); prot = c.decimal(.prot); carb = c.decimal(.carb); fat = c.decimal(.fat); confianza = c.texto(.confianza)
    }
}
