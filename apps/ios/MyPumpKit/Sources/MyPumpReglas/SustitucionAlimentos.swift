import Foundation
import MyPumpModelos

/// Un sustituto que ofrece el modal de "Sustituir", con la porción ya calculada. Es el objeto que arma
/// `findSubstitutes` de la web y el que se persiste en `mypump_food_swaps.food_data` (ver `foodData`).
public struct Sustituto: Equatable, Sendable {
    public var nombre: String
    /// Gramos, o unidades enteras si el alimento tiene medida casera (`unidad` dice cuál).
    public var qty: Double
    public var unidad: String
    /// TOTALES de la porción que el cliente realmente come (no por 100 g).
    public var kcal: Double
    public var prot: Double
    public var carb: Double
    public var fat: Double
    public var categoria: String?
    /// `_dev`: el peor desvío relativo entre kcal y macro dominante contra el original (0.05 = 5 %).
    public var desvio: Double
    /// `_universal`: se consigue en cualquier país; la UI los muestra arriba.
    public var universal: Bool
    /// `_en`: etiqueta en inglés; solo la tienen los universales, y puede ser "".
    public var nombreIngles: String?
    /// `_isCustom`: alimento propio del cliente.
    public var esPropio: Bool

    public init(nombre: String, qty: Double, unidad: String, kcal: Double, prot: Double, carb: Double, fat: Double,
                categoria: String?, desvio: Double, universal: Bool = false, nombreIngles: String? = nil,
                esPropio: Bool = false) {
        self.nombre = nombre; self.qty = qty; self.unidad = unidad
        self.kcal = kcal; self.prot = prot; self.carb = carb; self.fat = fat
        self.categoria = categoria; self.desvio = desvio
        self.universal = universal; self.nombreIngles = nombreIngles; self.esPropio = esPropio
    }

    /// El objeto de la web: `{name, qty, unit, kcal, prot, carb, fat, category, _dev, _isCustom?, _universal?, _en?}`.
    /// (El ancla `_orig` la agrega quien confirma el swap.)
    public var foodData: JSONValue {
        var o: [String: JSONValue] = [
            "name": .texto(nombre), "qty": .numero(qty), "unit": .texto(unidad), "kcal": .numero(kcal),
            "prot": .numero(prot), "carb": .numero(carb), "fat": .numero(fat), "_dev": .numero(desvio),
        ]
        if let categoria { o["category"] = .texto(categoria) }
        if esPropio { o["_isCustom"] = .bool(true) }
        if universal { o["_universal"] = .bool(true); o["_en"] = .texto(nombreIngles ?? "") }
        return .objeto(o)
    }
}

/// `_lastInfo` de la web: el diagnóstico de la última búsqueda, para los avisos del modal.
public struct InfoSustitucion: Equatable, Sendable {
    /// Cuántos candidatos escondieron las preferencias del cliente (si vacían la lista, el modal lo dice).
    public var prefsFiltraron: Int
    /// Densidad calórica absurda en el original (macros por porción guardadas como por 100 g en dietas viejas).
    public var macrosSospechosos: Bool
    /// La categoría exacta rendía menos de 3 candidatos reales y se sumaron los de la categoría por macros.
    public var categoriaFallback: Bool

    public init(prefsFiltraron: Int = 0, macrosSospechosos: Bool = false, categoriaFallback: Bool = false) {
        self.prefsFiltraron = prefsFiltraron
        self.macrosSospechosos = macrosSospechosos
        self.categoriaFallback = categoriaFallback
    }
}

public struct ResultadoSustitucion: Equatable, Sendable {
    public var sustitutos: [Sustituto]
    public var info: InfoSustitucion
}

/// El motor de sustitución de alimentos: port exacto de `window.MyPump.foodSwap` (app.js:19-394), verificado con los
/// vectores que genera la web (scripts/nativa/vectores-alimentos.mjs).
///
/// Política (decidida con Mati): misma categoría, mismo macro dominante, porción que ajusta a la vez kcal y macro
/// dominante, descartar solo los perfiles muy distintos (desvío > 35 %), top 30 más los universales y los propios,
/// que se garantizan siempre.
public enum SustitucionAlimentos {

    /// `_UNIVERSAL`: staples que se consiguen en cualquier país (clientes del exterior). Minúsculas y sin tilde; un
    /// alimento es universal si su nombre normalizado los contiene como palabra. Nunca se filtran por desvío.
    static let universales = [
        "pechuga de pollo", "muslo de pollo", "pollo entero", "pavo pechuga",
        "huevo entero", "clara de huevo",
        "atun al natural", "merluza", "lenguado", "salmon", "trucha",
        "carne vacuna picada", "nalga", "cuadril", "lomo vacuno", "bife de chorizo", "bife de costilla", "asado de tira",
        "vacio", "entrana", "paleta vacuna", "matambre",
        "leche", "yogur", "queso cottage", "queso mozzarella", "ricota",
        "arroz blanco", "arroz integral", "avena", "pan", "papa", "patata", "lentejas", "garbanzos", "porotos", "fideos",
        "aceite de oliva", "palta", "aguacate", "mani", "almendras", "nueces",
        "banana", "manzana", "naranja", "tomate", "zanahoria", "cebolla", "lechuga", "espinaca",
    ]
    /// `_uniRe`: `new RegExp('\\b(' + _UNIVERSAL.join('|') + ')\\b')`.
    static let reUniversal = JSRegex(#"\b("# + universales.joined(separator: "|") + #")\b"#)

    /// `_EN`: etiqueta en inglés para las cards universales. De lo específico a lo general: gana la primera clave
    /// que el nombre normalizado contenga.
    static let etiquetasIngles: [(clave: String, ingles: String)] = [
        ("carne vacuna picada (magra", "Lean ground beef (90/10)"),
        ("carne vacuna picada (comun", "Ground beef (80/20)"),
        ("carne vacuna picada", "Ground beef"),
        ("nalga", "Beef round / topside"),
        ("cuadril", "Beef rump"),
        ("lomo vacuno", "Beef tenderloin"),
        ("bife de chorizo", "Beef sirloin"),
        ("bife de costilla", "Beef rib steak"),
        ("asado de tira", "Beef short ribs"),
        ("vacio", "Beef flank steak"),
        ("entrana", "Beef skirt steak"),
        ("paleta vacuna", "Beef shoulder / chuck"),
        ("matambre", "Beef flank (matambre)"),
        ("pechuga de pollo", "Chicken breast"),
        ("muslo de pollo", "Chicken thigh"),
        ("pollo entero", "Whole chicken"),
        ("pavo pechuga", "Turkey breast"),
        ("clara de huevo", "Egg whites"),
        ("huevo entero", "Whole egg"),
        ("atun al natural", "Canned tuna (in water)"),
        ("merluza", "White fish (hake / sea bass)"),
        ("lenguado", "White fish (sole)"),
        ("salmon", "Salmon"),
        ("trucha", "Trout"),
        ("leche", "Milk"),
        ("yogur", "Yogurt"),
        ("queso cottage", "Cottage cheese"),
        ("queso mozzarella", "Mozzarella"),
        ("ricota", "Ricotta"),
        ("arroz", "Rice"),
        ("avena", "Oats"),
        ("fideos", "Pasta"),
        ("pan", "Bread"),
        ("papa", "Potato"),
        ("patata", "Potato"),
        ("lentejas", "Lentils"),
        ("garbanzos", "Chickpeas"),
        ("porotos", "Beans"),
        ("aceite de oliva", "Olive oil"),
        ("palta", "Avocado"),
        ("aguacate", "Avocado"),
        ("mani", "Peanut"),
        ("almendras", "Almonds"),
        ("nueces", "Walnuts"),
        ("banana", "Banana"),
        ("manzana", "Apple"),
        ("naranja", "Orange"),
        ("tomate", "Tomato"),
        ("zanahoria", "Carrot"),
        ("cebolla", "Onion"),
        ("lechuga", "Lettuce"),
        ("espinaca", "Spinach"),
    ]

    /// `_EXCLUDE_GROUPS`: lo que esconde cada preferencia del cliente (`mypump_cliente_prefs.excluir`), sobre el nombre
    /// normalizado. "Bife de chorizo" es carne vacuna: por eso el cerdo matchea "chorizo fresco" y no "chorizo".
    static let gruposExclusion: [String: JSRegex] = [
        "cerdo": JSRegex(#"\bcerdo\b|lechon|bondiola|\bpanceta\b|\btocino\b|\bjamon\b|\bsalame\b|\bsalami\b|chorizo fresco|longaniza|morcilla|salchicha|mortadela|prosciutto|pancetta|\bbacon\b"#),
        "mariscos": JSRegex(#"langostino|camaron|\bgamba\b|mejillon|\bcalamar\b|\bpulpo\b|almeja|\bostra\b|vieira|cangrejo|\bkani\b|surimi|\bmarisco|\bsepia\b|jibia|scallop"#),
        "lacteos": JSRegex(#"\bleche\b|yogur|\bqueso\b|ricota|\bnata\b|mozzarella|parmesano|provolone|cottage|\bcasein"#),
    ]

    // `_norm`: estas tildes, de a una regex como en la web (sin normalizar Unicode: una tilde suelta, NFD, queda).
    private static let sinTilde: [(JSRegex, String)] = [
        (JSRegex(#"[áàäâã]"#), "a"), (JSRegex(#"[éèëê]"#), "e"), (JSRegex(#"[íìïî]"#), "i"),
        (JSRegex(#"[óòöôõ]"#), "o"), (JSRegex(#"[úùüû]"#), "u"), (JSRegex(#"ñ"#), "n"),
    ]

    /// `_norm(name)`: minúsculas y sin tildes.
    static func normalizar(_ nombre: String?) -> String {
        var s = (nombre ?? "").lowercased()
        for (re, letra) in sinTilde { s = re.reemplazarTodo(s, por: letra) }
        return s
    }

    /// `_isUniversal(name)`.
    public static func esUniversal(_ nombre: String) -> Bool { esUniversal(normalizado: normalizar(nombre)) }
    static func esUniversal(normalizado: String) -> Bool { reUniversal.prueba(normalizado) }

    /// `_enLabel(name)`: "" si ninguna clave matchea.
    public static func etiquetaIngles(_ nombre: String) -> String { etiquetaIngles(normalizado: normalizar(nombre)) }
    static func etiquetaIngles(normalizado: String) -> String {
        let n = Array(normalizado.utf16)
        return etiquetasIngles.first { SemanticaJS.incluye(n, Array($0.clave.utf16)) }?.ingles ?? ""
    }

    /// El macro que domina las kcal de un alimento (`_getDominantMacro`; en empate gana prot, después carb).
    enum MacroDominante {
        case prot, carb, fat

        init(prot: Double?, carb: Double?, fat: Double?) {
            let p = SemanticaJS.oCero(prot) * 4, c = SemanticaJS.oCero(carb) * 4, f = SemanticaJS.oCero(fat) * 9
            if p >= c && p >= f { self = .prot } else if c >= f { self = .carb } else { self = .fat }
        }

        func de(_ a: Alimento) -> Double? {
            switch self { case .prot: a.prot; case .carb: a.carb; case .fat: a.fat }
        }
        func de(_ a: AlimentoBase) -> Double {
            switch self { case .prot: a.prot; case .carb: a.carb; case .fat: a.fat }
        }
        func de(_ s: Sustituto) -> Double {
            switch self { case .prot: s.prot; case .carb: s.carb; case .fat: s.fat }
        }
    }

    /// `findSubstitutes(original)` con `window.MYPUMP_FOOD_DB = base` y `window.MYPUMP_PREFS.excluir = excluir`.
    ///
    /// - Parameters:
    ///   - original: el alimento del plan (macros TOTALES de su `qty`). Si no trae categoría, se infiere.
    ///   - base: la base con los alimentos propios ya sumados (`BaseAlimentos.conPropios`).
    ///   - excluir: las etiquetas de `mypump_cliente_prefs` ("cerdo", "mariscos", "lacteos"); las desconocidas no hacen nada.
    public static func buscar(original: Alimento, base: BaseAlimentos, excluir: [String] = []) -> ResultadoSustitucion {
        var info = InfoSustitucion()
        let db = base.alimentos
        guard !db.isEmpty else { return ResultadoSustitucion(sustitutos: [], info: info) }

        let originalCat = original.categoria.flatMap { $0.isEmpty ? nil : $0 } ?? CategoriaAlimento.inferir(original)
        // Condimento REAL (sin calorías) no se sustituye. Uno calórico mal inferido como condimento sigue (F8).
        if SemanticaJS.iguales(originalCat, CategoriaAlimento.condimento) && SemanticaJS.oCero(original.kcal) < 30 {
            return ResultadoSustitucion(sustitutos: [], info: info)
        }

        let dominante = MacroDominante(prot: original.prot, carb: original.carb, fat: original.fat)
        let M0 = SemanticaJS.oCero(dominante.de(original))
        // `originalFood.kcal` va SIN `|| 0`: undefined no es > 0, igual que 0.
        let K0 = original.kcal ?? .nan
        let hayK0 = K0 > 0

        // Gramos del original, para acotar el tamaño del sustituto: unidades × unitGrams si viene en unidades.
        let q = SemanticaJS.oCero(original.qty)
        let originalQtyG: Double
        if original.unidad == "g" || original.unidad == "ml" {
            originalQtyG = q
        } else if SemanticaJS.verdadero(original.gramosPorUnidad), let g = original.gramosPorUnidad {
            originalQtyG = q * g
        } else {
            originalQtyG = q
        }
        // El sustituto no puede pedir más de 3× el original (con piso de 500 g para porciones chicas).
        let maxQty = SemanticaJS.max(originalQtyG * 3, 500)

        // F8: densidad calórica implícita absurda → macros probablemente corruptos. No bloquea; el modal avisa.
        if originalQtyG >= 20 && hayK0 {
            let dens = (K0 / originalQtyG) * 100
            if dens > 950 || dens < 10 { info.macrosSospechosos = true }
        }

        let exclusiones = excluir.compactMap { gruposExclusion[$0] }
        let nombreOriginal = SemanticaJS.minusculas(original.nombre)
        var excluidosPorPrefs = 0
        // matchCat && pasaPrefs: misma categoría, otro nombre, y las preferencias (que cuentan lo que esconden).
        func candidato(_ f: AlimentoBase, _ cat: String) -> Bool {
            guard SemanticaJS.iguales(f.categoria, cat), f.minusculas != nombreOriginal else { return false }
            if exclusiones.isEmpty { return true }
            if exclusiones.contains(where: { $0.prueba(f.normalizado) }) {
                excluidosPorPrefs += 1
                return false
            }
            return true
        }

        var pool = db.filter { candidato($0, originalCat) }
        // F8: si la categoría exacta rinde poco (< 3 no universales ni propios), sumar la categoría por macros.
        if let catMacros = CategoriaAlimento.porMacros(prot: original.prot, carb: original.carb, fat: original.fat),
           !SemanticaJS.iguales(catMacros, originalCat) {
            let nReal = pool.filter { !$0.universal && !$0.esPropio }.count
            if nReal < 3 {
                info.categoriaFallback = true
                let extra = db.filter { candidato($0, catMacros) }
                let vistos = Set(pool.map(\.minusculas))      // como en la web: no se actualiza dentro del loop
                for f in extra where !vistos.contains(f.minusculas) { pool.append(f) }
            }
        }
        info.prefsFiltraron = excluidosPorPrefs

        var ranked: [Sustituto] = []
        for food in pool {
            let K = food.kcal                   // kcal por 100 g del sustituto
            let M = dominante.de(food)          // macro dominante por 100 g
            if M == 0 { continue }

            // Porción por MEJOR AJUSTE combinado: el factor f (porción/100 g) que minimiza
            // ((K·f−K0)/K0)² + ((M·f−M0)/M0)². Con a = K/K0 y b = M/M0, f* = (a+b)/(a²+b²).
            let factor: Double
            if hayK0 && M0 > 0 {
                let a = K / K0, b = M / M0
                let denom = a * a + b * b
                factor = denom > 0 ? (a + b) / denom : (M0 / M)
            } else if hayK0 && K > 0 {
                factor = K0 / K                 // F8: original con macros en cero pero kcal válida
            } else {
                factor = M0 / M
            }
            let requiredQty = factor * 100
            if requiredQty <= 0 || requiredQty > maxQty { continue }

            var qty = jsRound(requiredQty)
            var unidad = "g"
            var gramosReales = qty
            if let ug = food.gramosPorUnidad {
                let unidades = requiredQty / ug
                if unidades >= 0.5 {
                    qty = jsRound(unidades)
                    unidad = food.unidad.flatMap { $0.isEmpty ? nil : $0 } ?? "unidad"
                    gramosReales = qty * ug
                }
            }
            // Las macros salen de lo que el cliente REALMENTE come (la porción redondeada), no del factor exacto.
            let factorReal = gramosReales / 100
            var s = Sustituto(nombre: food.nombre, qty: qty, unidad: unidad,
                              kcal: jsRound(K * factorReal),
                              prot: jsRound(food.prot * factorReal * 10) / 10,
                              carb: jsRound(food.carb * factorReal * 10) / 10,
                              fat: jsRound(food.fat * factorReal * 10) / 10,
                              categoria: food.categoria, desvio: 0, esPropio: food.esPropio)
            let kcalDev = hayK0 ? abs(s.kcal - K0) / K0 : 0
            let macroDev = M0 > 0 ? abs(SemanticaJS.oCero(dominante.de(s)) - M0) / M0 : 0
            s.desvio = SemanticaJS.max(kcalDev, macroDev)
            if food.universal { s.universal = true; s.nombreIngles = food.nombreIngles }

            // Propios y universales: siempre, con su desvío real. El resto, solo si el perfil se parece.
            if food.esPropio || food.universal || !(s.desvio > 0.35) { ranked.append(s) }
        }

        // Más exacto primero. El sort de JS es estable: a igual desvío, el orden de la base.
        let ordenados = ranked.enumerated()
            .sorted { $0.element.desvio != $1.element.desvio ? $0.element.desvio < $1.element.desvio : $0.offset < $1.offset }
            .map(\.element)

        // Universales y propios se garantizan; el resto se corta a 30. Después, sin repetir nombre.
        let garantizado = { (s: Sustituto) in s.universal || s.esPropio }
        var vistos = Set<[UInt16]>()
        let sustitutos = (ordenados.filter(garantizado) + ordenados.filter { !garantizado($0) }.prefix(30))
            .filter { vistos.insert(SemanticaJS.minusculas($0.nombre)).inserted }
        return ResultadoSustitucion(sustitutos: sustitutos, info: info)
    }

    /// `searchSubstitutes` / el buscador del modal: los que contienen el texto (minúsculas, `trim` de JS). Sin texto,
    /// todos.
    public static func filtrar(_ sustitutos: [Sustituto], consulta: String?) -> [Sustituto] {
        guard let consulta, !consulta.isEmpty else { return sustitutos }
        let q = Array(SemanticaJS.recortar(consulta.lowercased()).utf16)
        return sustitutos.filter { SemanticaJS.incluye(SemanticaJS.minusculas($0.nombre), q) }
    }
}
