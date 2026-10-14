import Foundation

/// "La mano": la equivalencia casera de un alimento (palmas, puños, tazas, cucharadas, vasos, latas…) para el
/// cliente que no usa balanza. Port exacto de `porcionReferencia` (cliente.html:5464). Devuelve el texto sin el
/// "≈ " (lo agrega la pantalla, salvo en "libre 🥗") o nil si no hay equivalencia útil.
public enum PorcionCasera {
    public static func referencia(nombre: String?, qty: Double?, unidad: String?, gramosPorUnidad: Double?) -> String? {
        let name = normalizar(nombre)
        guard !name.isEmpty else { return nil }
        // Number(food.qty): sin valor es NaN → no hay porción.
        guard let qty, qty.isFinite, qty > 0 else { return nil }
        let unitRaw = normalizar(unidad)
        let unitGrams = gramosPorUnidad ?? .nan
        let isMl = ["ml", "cc", "mililitro", "mililitros"].contains(unitRaw)
        let isGram = unitRaw.isEmpty || ["g", "gr", "grs", "gramo", "gramos"].contains(unitRaw) || isMl
        let unitWords = ["u", "un", "uni", "unid", "unidad", "unidades"]

        // ---- Rama unidad: qty ya es un conteo ----
        if !isGram {
            let n: Double, base: String
            if unitGrams > 0 && qty > 20 {
                n = qty / unitGrams
                base = (!unitRaw.isEmpty && !unitWords.contains(unitRaw)) ? singular(unitRaw) : sustantivo(de: name)
            } else if unitWords.contains(unitRaw) {
                n = qty
                base = sustantivo(de: name)
            } else {
                return nil   // unidad ya casera (plato, taza…): no aporta nada
            }
            return contar(n, base)
        }

        // ---- Rama gramos / ml ----
        func has(_ kw: String...) -> Bool { kw.contains { name.contains($0) } }
        let g = qty

        if has("mani", "cacahuate") && has("mantequilla", "manteca", "crema", "pasta", "untable") {
            if g < 8 { return "1 cucharadita" }
            return contar(g / 16, "cucharada")
        }
        if has("leche", "bebida", "jugo", "zumo", "licuado", "gaseosa", "kefir", "caldo", "infusion", "yogur bebible", "chocolatada") {
            return contar(g / 200, "vaso")
        }
        if isMl || has("aceite", "oliva", "ghee") || has("manteca", "mantequilla") {
            if isMl && g > 100 && !has("aceite", "oliva", "ghee", "manteca", "mantequilla") {
                return contar(g / 200, "vaso")
            }
            if g < 7.5 { return "1 cucharadita" }
            return contar(g / 15, "cucharada")
        }
        if has("almendra", "nuez", "nueces", "castana", "avellana", "pistacho", "mani", "cacahuate", "frutos secos",
               "semilla", "girasol", "chia", "lino", "mix de") {
            return contar(g / 30, "puñado")
        }
        if has("whey", "proteina en polvo", "caseina") || (has("proteina") && g <= 60) {
            let scoops = max(1, jsRound(g / 30))
            return scoops == 1 ? "1 scoop (1 medida)" : "\(entero(scoops)) scoops"
        }
        if has("atun") {
            let n = g / 120
            let frac = n - n.rounded(.down)
            if frac >= 0.75 { return "casi \(entero(n.rounded(.up))) latas" }
            let nh = jsRound(n * 2) / 2
            let whole = nh.rounded(.down)
            let s = whole > 1 ? "s" : ""
            if nh - whole == 0.5 { return whole >= 1 ? "\(entero(whole)) lata\(s) y media" : "media lata" }
            return "\(entero(whole)) lata\(s) escurrida\(s)"
        }
        if has("pollo", "pechuga", "carne", "nalga", "bife", "cerdo", "lomo", "pescado", "merluza", "pavo", "salmon",
               "cuadril", "cuadrada", "peceto", "asado", "bondiola", "milanesa", "tira", "magra", "roast", "colita") {
            let gCocido = has("crud") ? g * 0.75 : g   // palma = 100 g COCIDO; crudo pierde ~25 %
            return contar(gCocido / 100, "palma")
        }
        if has("arroz", "fideo", "pasta", "avena", "quinoa", "polenta", "tallarin", "noqui", "cuscus", "couscous",
               "trigo", "mostacho", "spaghetti", "ravioli") {
            if has("avena") { return taza(g / 80) }
            if has("cocid", "hervid", "al dente") { return taza(g / 175) }
            var ratio = 2.8, rawCup = 185.0
            if has("fideo", "pasta", "tallarin", "noqui", "mostacho", "spaghetti", "ravioli", "cuscus", "couscous") { ratio = 2.4; rawCup = 100 }
            else if has("quinoa") { ratio = 2.6; rawCup = 170 }
            else if has("polenta") { ratio = 4; rawCup = 150 }
            guard let cruda = taza(g / rawCup) else { return nil }
            // JS concatena el null como "null" si la cocida no existe (no pasa: ratio > 0).
            return "\(cruda) en crudo (≈ \(taza((g * ratio) / 175) ?? "null") cocido)"
        }
        if has("lenteja", "garbanzo", "poroto", "alubia", "frijol", "chaucha seca") { return taza(g / 190) }
        if has("papa", "patata", "batata", "boniato") && !has("papaya") {
            if g < 110 { return "1 chica" }
            if g <= 190 { return "1 mediana" }
            if g <= 280 { return "1 grande" }
            return "\(entero(max(2, jsRound(g / 160)))) medianas"
        }
        if has("lechuga", "rucula", "radicheta", "escarola", "hojas verdes", "mix de hojas") { return "libre 🥗" }
        if has("brocoli", "brecol", "coliflor", "calabaza", "zapallo", "zanahoria", "espinaca", "morron", "pimiento",
               "berenjena", "zucchini", "zapallito", "repollo", "remolacha", "chaucha", "cebolla", "tomate", "verdura") {
            return contar(g / 90, "puño")
        }
        if has("ricota", "untable", "yogur", "yoghurt", "queso blanco", "queso crema", "cottage", "requeson") {
            return taza(g / 245)
        }
        if has("frutilla", "arandano", "mora", "frambuesa", "frutos rojos", "berries") { return contar(g / 80, "puñado") }
        if has("palta", "aguacate") {
            if g <= 90 { return "media palta chica" }
            if g <= 160 { return "1 palta" }
            return "\(medio(g / 140)) paltas"
        }
        if has("pan") && !has("rallado") {
            let n = max(1, jsRound(g / 30))
            return "\(entero(n)) rebanada\(n > 1 ? "s" : "")"
        }
        if has("tostada") {
            let n = max(1, jsRound(g / (has("arroz") ? 9 : 25)))
            return "\(entero(n)) tostada\(n > 1 ? "s" : "")"
        }
        return nil
    }

    // MARK: - Helpers (los mismos de la web)

    /// minúsculas, NFD sin U+0300–U+036F, trim.
    static func normalizar(_ s: String?) -> String {
        let d = (s ?? "").lowercased().decomposedStringWithCanonicalMapping
        let sinMarcas = String(String.UnicodeScalarView(d.unicodeScalars.filter { !(0x300...0x36F).contains($0.value) }))
        return sinMarcas.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// El largo en JS es en unidades UTF-16.
    static func singular(_ w: String) -> String {
        let largo = w.utf16.count
        if largo > 4 && w.hasSuffix("ces") { return String(w.dropLast(3)) + "z" }
        if largo > 3 && w.hasSuffix("es") { return String(w.dropLast(2)) }
        if largo > 3 && w.hasSuffix("s") { return String(w.dropLast(1)) }
        return w
    }

    static func plural(_ w: String) -> String {
        if let u = w.last, "aeiou".contains(u) { return w + "s" }
        return w + "es"
    }

    private static let palabrasVacias: Set<String> = ["de", "del", "la", "el", "los", "las", "al", "con", "a", "en", "sin", "y"]
    private static let separador = JSRegex(#"[\s/]+"#)

    static func sustantivo(de name: String) -> String {
        let tokens = separador.reemplazarTodo(name, por: "\u{0}").split(separator: "\u{0}", omittingEmptySubsequences: true)
            .map(String.init).filter { !$0.isEmpty && !palabrasVacias.contains($0) }
        return singular(tokens.first ?? name)
    }

    /// `fmtCount`: medias; "½ palma", "1½ palmas", "2 palmas".
    static func contar(_ valor: Double, _ base: String) -> String? {
        let n = jsRound(valor * 2) / 2
        if n <= 0 { return nil }
        let whole = n.rounded(.down)
        if whole == 0 { return "½ \(base)" }
        if n - whole == 0.5 { return "\(entero(whole))½ \(plural(base))" }
        return "\(entero(whole)) \(n == 1 ? base : plural(base))"
    }

    /// `nStr`: medias sin sustantivo.
    static func medio(_ valor: Double) -> String {
        let n = jsRound(valor * 2) / 2
        let whole = n.rounded(.down)
        if whole == 0 { return "½" }
        return n - whole == 0.5 ? "\(entero(whole))½" : entero(whole)
    }

    /// `fmtCup`: cuartos de taza (¼ ½ ¾).
    static func taza(_ valor: Double) -> String? {
        let cups = jsRound(valor * 4) / 4
        if cups <= 0 { return nil }
        let whole = cups.rounded(.down)
        let frac: String
        switch cups - whole {
        case 0.25: frac = "¼"
        case 0.5: frac = "½"
        case 0.75: frac = "¾"
        default: frac = ""
        }
        let num = whole == 0 ? frac : "\(entero(whole))\(frac)"
        return "\(num) \(cups > 1 ? "tazas" : "taza")"
    }

    /// Lo entero como lo imprime JS: sin cerrar la app con una cantidad absurda (`Int()` de Swift se cae fuera de rango).
    static func entero(_ d: Double) -> String {
        guard d.isFinite else { return d.isNaN ? "NaN" : (d > 0 ? "Infinity" : "-Infinity") }
        if abs(d) < 9e15 { return String(Int(d)) }
        return abs(d) < 1e21 ? String(format: "%.0f", d) : String(d)
    }
}
