import Foundation

/// Fila de `mypump_ejercicios_catalogo`: lectura pública sin token, con las columnas que pide `getCatalogoEjercicios`
/// (public/js/supabase-client.js). Es free-exercise-db, en inglés, más el patrón de movimiento que decide qué sustituye a
/// qué. La app trae una copia (`apps/shared/catalogo-ejercicios.json`) para cuando no hay red.
///
/// Los textos se leen solo si son texto: la web los compara con `===`, y un número nunca es igual a un texto.
public struct EntradaCatalogoEjercicio: Decodable, Sendable, Equatable {
    public var slugEn: String?
    public var nameEn: String?
    public var nameNormalized: String?
    /// Palabras clave genéricas ("remo", "jalon", "core"): sirven para resolver un nombre, no para distinguir variantes.
    public var aliasesEs: [String]?
    public var primaryMuscle: String?
    public var equipment: String?
    /// NULL en casi la mitad del catálogo: sin patrón no se ofrecen sustitutos.
    public var patronMovimiento: String?
    public var imageEccentric: String?
    public var imageConcentric: String?

    enum CodingKeys: String, CodingKey {
        case slugEn = "slug_en", nameEn = "name_en", nameNormalized = "name_normalized", aliasesEs = "aliases_es"
        case primaryMuscle = "primary_muscle", equipment, patronMovimiento = "patron_movimiento"
        case imageEccentric = "image_eccentric", imageConcentric = "image_concentric"
    }

    public init(slugEn: String?, nameEn: String? = nil, nameNormalized: String? = nil, aliasesEs: [String]? = nil,
                primaryMuscle: String? = nil, equipment: String? = nil, patronMovimiento: String? = nil,
                imageEccentric: String? = nil, imageConcentric: String? = nil) {
        self.slugEn = slugEn; self.nameEn = nameEn; self.nameNormalized = nameNormalized; self.aliasesEs = aliasesEs
        self.primaryMuscle = primaryMuscle; self.equipment = equipment; self.patronMovimiento = patronMovimiento
        self.imageEccentric = imageEccentric; self.imageConcentric = imageConcentric
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func cadena(_ k: CodingKeys) -> String? { (try? c.decodeIfPresent(String.self, forKey: k)) ?? nil }
        slugEn = cadena(.slugEn); nameEn = cadena(.nameEn); nameNormalized = cadena(.nameNormalized)
        // `Array.isArray(e.aliases_es) && e.aliases_es.includes(nn)`: lo que no es array no tiene alias, y un elemento
        // que no es texto nunca coincide.
        aliasesEs = (try? c.decodeIfPresent([Opcional<String>].self, forKey: .aliasesEs))?.compactMap(\.valor)
        primaryMuscle = cadena(.primaryMuscle); equipment = cadena(.equipment); patronMovimiento = cadena(.patronMovimiento)
        imageEccentric = cadena(.imageEccentric); imageConcentric = cadena(.imageConcentric)
    }
}
