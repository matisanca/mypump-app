import Foundation
import MyPumpModelos

/// El código de barras de la hoja «Agregar alimento» (2.1, S3; el «Barcode scan» de MyFitnessPal): el número que leyó el
/// escáner, la respuesta de Open Food Facts (API v2, pública y sin clave) llevada a un alimento por 100 g, y la caché por
/// código. Puro: lo usan las vistas y los tests, igual en Android (vectores en `apps/shared/vectores/barras_off.json`, con
/// respuestas reales de productos argentinos).
public enum CodigoBarras {
    /// Los campos que se le piden a Open Food Facts (el resto no viaja).
    public static let campos = "product_name,product_name_es,brands,nutriments,serving_size,serving_quantity,serving_quantity_unit,quantity"
    /// Open Food Facts contesta en menos de un segundo; con señal mala se corta antes de que la hoja parezca colgada.
    public static let esperaSegundos: Double = 8

    /// `https://world.openfoodfacts.org/api/v2/product/<código>.json?fields=…` (el código ya normalizado).
    public static func url(_ codigo: String) -> URL? {
        URL(string: "https://world.openfoodfacts.org/api/v2/product/\(codigo).json?fields=\(campos)")
    }

    /// Open Food Facts pide que cada app se identifique: «PumpTeam/2.1.0 (iOS)».
    public static func agenteUsuario(version: String, plataforma: String) -> String { "PumpTeam/\(version) (\(plataforma))" }

    // MARK: - El número

    /// El código como se le pregunta a Open Food Facts y como se guarda en la caché, o nil si no es un EAN/UPC válido (el
    /// dígito de control no cierra, otro largo, letras). EAN-13 y EAN-8 quedan igual; UPC-A (12) pasa a EAN-13 con un 0
    /// adelante; UPC-E (8, `upcE`) se expande a UPC-A y de ahí a EAN-13. Un EAN-8 y un UPC-E tienen el mismo largo: decide la
    /// simbología que informa el escáner.
    public static func normalizar(_ texto: String, upcE: Bool = false) -> String? {
        let t = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, t.unicodeScalars.allSatisfy({ ("0"..."9").contains($0) }) else { return nil }
        if upcE {
            guard t.count == 8, let a = expandirUPCE(t) else { return nil }
            return "0" + a
        }
        switch t.count {
        case 13, 8: return controlValido(t) ? t : nil
        case 12: return controlValido(t) ? "0" + t : nil
        default: return nil
        }
    }

    /// El dígito de control GTIN de los dígitos sin él: pesos 3 y 1 desde la derecha.
    static func digitoControl(_ sinControl: String) -> Int {
        let suma = sinControl.reversed().enumerated().reduce(0) { s, e in s + (e.element.wholeNumberValue ?? 0) * (e.offset % 2 == 0 ? 3 : 1) }
        return (10 - suma % 10) % 10
    }

    static func controlValido(_ c: String) -> Bool {
        guard let ultimo = c.last?.wholeNumberValue else { return false }
        return digitoControl(String(c.dropLast())) == ultimo
    }

    /// UPC-E (sistema 0 o 1, seis dígitos y el de control) a UPC-A de 12, o nil si el control no cierra.
    static func expandirUPCE(_ c: String) -> String? {
        let d = Array(c)
        guard d.count == 8, d[0] == "0" || d[0] == "1" else { return nil }
        let m = String(d[1...6]), u = d[6]
        func s(_ a: Int, _ b: Int) -> String { String(Array(m)[a..<b]) }
        let cuerpo: String
        switch u {
        case "0", "1", "2": cuerpo = s(0, 2) + String(u) + "0000" + s(2, 5)
        case "3": cuerpo = s(0, 3) + "00000" + s(3, 5)
        case "4": cuerpo = s(0, 4) + "00000" + s(4, 5)
        default: cuerpo = s(0, 5) + "0000" + String(u)
        }
        let a = String(d[0]) + cuerpo + String(d[7])
        return controlValido(a) ? a : nil
    }

    // MARK: - La respuesta de Open Food Facts

    /// Un producto que se puede agregar: macros por 100 g ya validadas como las de un alimento propio y, si la etiqueta trae
    /// porción, su medida («barra» de 23 g, «porción» de 200 g).
    public struct Producto: Codable, Equatable, Sendable {
        public var codigo: String
        public var nombre: String
        public var por100: MacrosPor100
        public var medida: String?
        public var gramosMedida: Double?
        /// `true`: es un alimento propio que el cliente creó al escanear un código que Open Food Facts no tenía.
        public var propio: Bool

        public init(codigo: String, nombre: String, por100: MacrosPor100, medida: String?, gramosMedida: Double?, propio: Bool = false) {
            self.codigo = codigo; self.nombre = nombre; self.por100 = por100; self.medida = medida; self.gramosMedida = gramosMedida
            self.propio = propio
        }

        /// Para la hoja de cantidad: origen «barras» con el código (o «propio», con el código igual).
        public var candidato: AgregadosComida.Candidato {
            AgregadosComida.Candidato(nombre: nombre, por100: por100, unidad: medida, gramosPorUnidad: gramosMedida,
                                      origen: propio ? .propio : .barras, codigo: codigo)
        }
    }

    /// Lo que se pudo leer de un producto incompleto: precarga el alimento propio (todo editable).
    public struct Parcial: Codable, Equatable, Sendable {
        /// `enCero`: las macros en cero y sin calorías declaradas (no se sabe si es agua o si nadie cargó la etiqueta).
        public enum Motivo: String, Codable, Sendable { case sinNombre, faltanDatos, noCierran, enCero }
        public var codigo: String
        public var motivo: Motivo
        public var nombre: String?
        public var kcal: Double?
        public var p: Double?
        public var c: Double?
        public var g: Double?

        public init(codigo: String, motivo: Motivo, nombre: String? = nil, kcal: Double? = nil, p: Double? = nil, c: Double? = nil, g: Double? = nil) {
            self.codigo = codigo; self.motivo = motivo; self.nombre = nombre; self.kcal = kcal; self.p = p; self.c = c; self.g = g
        }

        /// El renglón de la hoja: por qué no se puede agregar directo.
        public var texto: String {
            switch motivo {
            case .sinNombre, .faltanDatos: "Open Food Facts tiene este producto, pero le faltan datos de la etiqueta."
            case .noCierran: "Open Food Facts tiene este producto, pero sus valores no cierran."
            case .enCero: "Open Food Facts tiene este producto con todo en cero y sin calorías: revisá la etiqueta y cargalo."
            }
        }
    }

    public enum Lectura: Codable, Equatable, Sendable {
        case encontrado(Producto)
        case incompleto(Parcial)
        case noEncontrado
    }

    /// La respuesta de `/api/v2/product/<código>.json`. Encontrado solo si tiene nombre, las tres macros y los valores
    /// pasan la validación del alimento propio (`AlimentoPropioNuevo.preparar` con «g»: nada de más de 950 kcal o 110 g de
    /// macros cada 100 g) y las kcal cierran con las macros. Lo demás es incompleto, con lo que se pudo leer.
    ///
    /// Todo en cero (agua, gaseosa sin azúcar): `preparar` lo rechaza («Cargá al menos las calorías o algún macro», que es
    /// para lo que tipea el cliente), así que se acepta acá, SOLO para Open Food Facts, cuando la etiqueta declara 0 kcal
    /// (o 0 kJ). Sin calorías declaradas es `enCero`: no se sabe si es agua o si faltan los datos.
    ///
    /// La porción solo se usa si viene en gramos: con `serving_quantity_unit` «ml» se queda por 100 g (la app muestra las
    /// medidas en gramos y 200 ml no son 200 g).
    public static func leer(_ j: JSONValue, codigo: String) -> Lectura {
        guard j["status"]?.comoNumero == 1, case .objeto = j["product"], let p = j["product"] else { return .noEncontrado }
        var nombre = limpio(p["product_name_es"])
        if nombre.isEmpty { nombre = limpio(p["product_name"]) }
        let marca = limpio(p["brands"]).split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty } ?? ""
        if !nombre.isEmpty {
            nombre = nombre.prefix(1).uppercased() + nombre.dropFirst()
            if !marca.isEmpty, !PorcionCasera.normalizar(nombre).contains(PorcionCasera.normalizar(marca)) { nombre += " (\(marca))" }
            nombre = String(nombre.prefix(AgregadosComida.largoNombre)).trimmingCharacters(in: .whitespaces)
        }
        let n = p["nutriments"]
        let prot = numero(n?["proteins_100g"]), carb = numero(n?["carbohydrates_100g"]), grasa = numero(n?["fat_100g"])
        let kcalDeclaradas = numero(n?["energy-kcal_100g"])
        // `energy_100g` de Open Food Facts va siempre en kJ.
        let kj = numero(n?["energy-kj_100g"]) ?? numero(n?["energy_100g"])
        let kcalDeKj = kj.map { $0 / 4.184 }
        var atwater: Double?
        if let prot, let carb, let grasa { atwater = 4 * prot + 4 * carb + 9 * grasa }
        let kcal: Double?
        if let kd = kcalDeclaradas, let kk = kcalDeKj {
            // Las dos y no coinciden (pasa: un alfajor con 376 kcal y 2138 kJ): vale la que cierra con las macros.
            if abs(kd - kk) > 0.1 * max(kd, kk), let a = atwater {
                kcal = abs(kd - a) <= abs(kk - a) ? kd : kk
            } else {
                kcal = kd
            }
        } else {
            kcal = kcalDeclaradas ?? kcalDeKj
        }
        func parcial(_ m: Parcial.Motivo) -> Lectura {
            .incompleto(Parcial(codigo: codigo, motivo: m, nombre: nombre.isEmpty ? nil : nombre, kcal: kcal.map(jsRound),
                                p: prot.map(r1), c: carb.map(r1), g: grasa.map(r1)))
        }
        guard !nombre.isEmpty else { return parcial(.sinNombre) }
        guard let prot, let carb, let grasa, let atwater else { return parcial(.faltanDatos) }
        if let k = kcal, !(0.6 * atwater - 25 <= k && k <= 1.4 * atwater + 40) { return parcial(.noCierran) }
        let por100: MacrosPor100
        if prot == 0, carb == 0, grasa == 0, kcal.map(jsRound) ?? 0 == 0 {
            guard kcal != nil else { return parcial(.enCero) }
            por100 = MacrosPor100(kcal: 0, p: 0, c: 0, g: 0)
        } else {
            guard case .success(let d) = AlimentoPropioNuevo.preparar(nombre: nombre, kcal: kcal, prot: prot, carb: carb, fat: grasa,
                                                                      unidad: "g", gramosPorUnidad: nil, categoria: "") else {
                return parcial(.noCierran)
            }
            por100 = MacrosPor100(kcal: d.kcal, p: d.prot, c: d.carb, g: d.fat)
        }
        var producto = Producto(codigo: codigo, nombre: nombre, por100: por100, medida: nil, gramosMedida: nil)
        let unidadPorcion = limpio(p["serving_quantity_unit"]).lowercased()
        if let sq = numero(p["serving_quantity"]), sq >= 1, sq <= 1000, jsRound(sq) != 100, unidadPorcion.isEmpty || unidadPorcion == "g" {
            producto.medida = nombreMedida(p["serving_size"]?.comoTexto)
            producto.gramosMedida = r1(sq)
        }
        return .encontrado(producto)
    }

    /// La medida de la porción: «1 barra/bar (23 g)» → «barra», «1 vaso 200 ml» → «vaso»; si no hay una palabra clara
    /// después de un «1», «porción».
    static func nombreMedida(_ s: String?) -> String {
        let t = Array((s ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
        guard t.count >= 3, t[0] == "1", t[1] == " " || t[1] == "\t" else { return "porción" }
        var i = 1
        while i < t.count, t[i] == " " || t[i] == "\t" { i += 1 }
        var j = i
        while j < t.count, letras.contains(t[j]) { j += 1 }
        let w = String(t[i..<j])
        if w.isEmpty || noEsMedida.contains(w) || w.count > 20 { return "porción" }
        return w
    }

    private static let letras = Set("abcdefghijklmnopqrstuvwxyzáéíóúüñ")
    private static let noEsMedida: Set<String> = ["portion", "portions", "serving", "servings", "porcion", "porción", "porciones",
                                                  "unit", "g", "gr", "grs", "gramo", "gramos", "ml", "cc", "oz", "kg", "l", "lt"]

    /// Un texto de Open Food Facts saneado (lo escribe cualquiera): sin etiquetas `<…>` (las que empiezan con letra, «/» o «!»: «2 < 3» queda), con los caracteres de control y
    /// todos los espacios Unicode (NBSP U+00A0 incluido) como separadores, y sin espacios de más. Igual que en Android.
    static func limpio(_ v: JSONValue?) -> String {
        guard let s = v?.comoTexto else { return "" }
        let sinEtiquetas = s.replacingOccurrences(of: "<[/!]?[A-Za-z][^<>]*>", with: " ", options: .regularExpression)
        var t = String.UnicodeScalarView()
        for u in sinEtiquetas.unicodeScalars {
            switch u.properties.generalCategory {
            case .control, .spaceSeparator, .lineSeparator, .paragraphSeparator: t.append(" ")
            default: t.append(u)
            }
        }
        return String(t).split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
    }

    /// Un número de Open Food Facts: número o texto («7,5»); negativo, infinito o ilegible = nil.
    static func numero(_ v: JSONValue?) -> Double? {
        let x: Double?
        switch v {
        case .numero(let d): x = d
        case .texto(let s): x = AlimentoPropioNuevo.leerNumero(s)
        default: x = nil
        }
        guard let x, x.isFinite, x >= 0 else { return nil }
        return x
    }

    private static func r1(_ x: Double) -> Double { jsRound(x * 10) / 10 }
}

/// Lo ya buscado, por código (en el teléfono): un producto encontrado vale 30 días; uno que no está o está incompleto, un
/// día (así uno que se carga en Open Food Facts aparece al día siguiente). Los alimentos propios creados desde un código
/// no vencen: al volver a escanearlo aparece el suyo.
public struct CacheCodigos: Codable, Equatable, Sendable {
    public struct Entrada: Codable, Equatable, Sendable {
        public var lectura: CodigoBarras.Lectura
        /// Cuándo se buscó (ms).
        public var ms: Int64
    }

    public static let maximo = 300
    public static let diaMs: Int64 = 86_400_000

    public private(set) var entradas: [String: Entrada] = [:]

    public init() {}

    /// Lo guardado que sigue valiendo.
    public func vigente(_ codigo: String, ahoraMs: Int64) -> CodigoBarras.Lectura? {
        guard let e = entradas[codigo] else { return nil }
        let vida: Int64
        switch e.lectura {
        case .encontrado(let p): vida = p.propio ? .max : 30 * Self.diaMs
        case .incompleto, .noEncontrado: vida = Self.diaMs
        }
        let edad = ahoraMs - e.ms
        return edad >= 0 && edad < vida ? e.lectura : nil
    }

    /// Suelta los propios creados desde un código que ya no son como el alimento propio de la cuenta: se borró o se editó
    /// (en la app o en la web). El próximo escaneo vuelve a preguntar. Se compara por nombre (sin distinguir mayúsculas,
    /// como `sumarPropio`), macros, unidad y gramos por unidad. Devuelve si soltó alguno.
    @discardableResult
    public mutating func conciliarPropios(_ propios: [AlimentoPropio]) -> Bool {
        let antes = entradas.count
        entradas = entradas.filter { _, e in
            guard case .encontrado(let p) = e.lectura, p.propio else { return true }
            return propios.contains { Self.mismo(p, $0) }
        }
        return entradas.count != antes
    }

    static func mismo(_ p: CodigoBarras.Producto, _ a: AlimentoPropio) -> Bool {
        func cerca(_ x: Double?, _ y: Double?) -> Bool {
            switch (x, y) {
            case (nil, nil): true
            case let (x?, y?): abs(x - y) < 0.05
            default: false
            }
        }
        return p.nombre.lowercased() == a.nombre.lowercased()
            && cerca(p.por100.kcal, a.kcal ?? 0) && cerca(p.por100.p, a.prot ?? 0) && cerca(p.por100.c, a.carb ?? 0)
            && cerca(p.por100.g, a.fat ?? 0) && p.medida == a.unidad && cerca(p.gramosMedida, a.gramosPorUnidad)
    }

    /// Guarda una lectura (no pisa un propio con lo que diga Open Food Facts). Pasado el máximo, se van las más viejas (los
    /// propios, al final).
    public mutating func guardar(_ codigo: String, _ l: CodigoBarras.Lectura, ahoraMs: Int64) {
        if case .encontrado(let p)? = entradas[codigo]?.lectura, p.propio {
            if case .encontrado(let n) = l, n.propio {} else { return }
        }
        entradas[codigo] = Entrada(lectura: l, ms: ahoraMs)
        if entradas.count > Self.maximo {
            func propio(_ e: Entrada) -> Bool { if case .encontrado(let p) = e.lectura { return p.propio }; return false }
            let viejas = entradas.sorted { (propio($0.value) ? 1 : 0, $0.value.ms, $0.key) < (propio($1.value) ? 1 : 0, $1.value.ms, $1.key) }
                .prefix(entradas.count - Self.maximo)
            for (k, _) in viejas { entradas[k] = nil }
        }
    }
}
