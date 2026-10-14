import Foundation
import Testing
import MyPumpModelos
@testable import MyPumpReglas

/// La base que empaqueta la app: el MYPUMP_FOOD_DB de la web (scripts/nativa/vectores-alimentos.mjs).
let archivoBaseAlimentos = raizRepo.appendingPathComponent("apps/shared/food-db.json")

func casiIgual(_ a: Double, _ b: Double) -> Bool { a == b || abs(a - b) <= 1e-9 }

/// Igualdad de JSON con tolerancia en los números.
func casiIgual(_ a: JSONValue, _ b: JSONValue) -> Bool {
    switch (a, b) {
    case let (.numero(x), .numero(y)): return casiIgual(x, y)
    case let (.objeto(x), .objeto(y)):
        return Set(x.keys) == Set(y.keys) && x.allSatisfy { casiIgual($0.value, y[$0.key]!) }
    case let (.lista(x), .lista(y)): return x.count == y.count && zip(x, y).allSatisfy { casiIgual($0, $1) }
    default: return a == b
    }
}

/// `a === b` de JS: por unidades UTF-16 (para Swift "é" y "e\u{301}" son iguales).
func mismoTextoJS(_ a: String?, _ b: String?) -> Bool {
    guard let a, let b else { return a == nil && b == nil }
    return a.utf16.elementsEqual(b.utf16)
}

// MARK: - Categoría

/// Vectores de `_inferCategory` (app.js), `inferFoodCategory` (cliente.html) e `inferCategory` (food-db.js).
struct ArchivoCategoriasAlimento: Decodable {
    struct Caso: Decodable {
        let name: String?
        /// Crudo, para distinguir `null` de ausente.
        let prot: JSONValue?
        let carb: JSONValue?
        let fat: JSONValue?
        let app: String
        let cliente: String
        let fooddb: String

        enum CodingKeys: String, CodingKey { case name, prot, carb, fat, app, cliente, fooddb }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            func crudo(_ k: CodingKeys) throws -> JSONValue? { c.contains(k) ? try c.decode(JSONValue.self, forKey: k) : nil }
            name = try c.decodeIfPresent(String.self, forKey: .name)
            prot = try crudo(.prot); carb = try crudo(.carb); fat = try crudo(.fat)
            app = try c.decode(String.self, forKey: .app)
            cliente = try c.decode(String.self, forKey: .cliente)
            fooddb = try c.decode(String.self, forKey: .fooddb)
        }
    }
    let fuente: String
    let casos: [Caso]
}

/// Un número como lo lee la regla de la web: ausente = undefined (nil); `null` vale 0 en todas sus cuentas.
func numeroJS(_ v: JSONValue?) -> Double? {
    switch v {
    case .none: return nil
    case .some(.null): return 0
    case .some(.numero(let d)): return d
    default: return .nan
    }
}

func fallasCategoria(_ archivo: URL) throws -> (total: Int, fallas: [String]) {
    let v = try JSONDecoder().decode(ArchivoCategoriasAlimento.self, from: Data(contentsOf: archivo))
    var fallas: [String] = []
    for c in v.casos {
        let swift = CategoriaAlimento.inferir(nombre: c.name, prot: numeroJS(c.prot), carb: numeroJS(c.carb), fat: numeroJS(c.fat))
        if swift != c.app || swift != c.cliente || swift != c.fooddb {
            fallas.append("\((c.name ?? "∅").debugDescription) \(String(describing: c.prot))/\(String(describing: c.carb))/\(String(describing: c.fat)): "
                + "app.js \(c.app), cliente.html \(c.cliente), food-db.js \(c.fooddb), swift \(swift)")
        }
    }
    return (v.casos.count, fallas)
}

@Suite("Categoría de alimento: la misma que las tres copias de la web")
struct CategoriaAlimentoTests {
    @Test func vectoresPublicos() throws {
        let r = try fallasCategoria(raizRepo.appendingPathComponent("apps/shared/vectores/categoria_alimento.json"))
        #expect(r.total > 800)
        #expect(r.fallas.isEmpty, "\(r.fallas.count) de \(r.total): \(r.fallas.prefix(8))")
    }

    @Test(.enabled(if: FileManager.default.fileExists(atPath: carpetaPrivada.appendingPathComponent("categoria_alimento.json").path)))
    func alimentosDeLasDietasReales() throws {
        let r = try fallasCategoria(carpetaPrivada.appendingPathComponent("categoria_alimento.json"))
        #expect(r.total > 1000)
        #expect(r.fallas.isEmpty, "\(r.fallas.count) de \(r.total): \(r.fallas.prefix(8))")
    }

    @Test func porMacros() {
        #expect(CategoriaAlimento.porMacros(prot: 25, carb: 2, fat: 3) == "proteina")
        #expect(CategoriaAlimento.porMacros(prot: 1, carb: 2, fat: 50) == "grasa")
        #expect(CategoriaAlimento.porMacros(prot: 2, carb: 60, fat: 1) == "carbohidrato")
        #expect(CategoriaAlimento.porMacros(prot: 10, carb: 10, fat: 5) == nil)
        #expect(CategoriaAlimento.porMacros(prot: nil, carb: nil, fat: nil) == nil)
    }

    @Test func laBaseEmpaquetadaTieneLasCategoriasDeLaRegla() throws {
        let base = try BaseAlimentos(json: Data(contentsOf: archivoBaseAlimentos))
        #expect(base.alimentos.count > 400)
        #expect(base.fuente?.hasPrefix("public/js/food-db.js@") == true)
        let distintas = base.alimentos.filter {
            CategoriaAlimento.inferir(nombre: $0.nombre, prot: $0.prot, carb: $0.carb, fat: $0.fat) != $0.categoria
        }
        #expect(distintas.isEmpty, "\(distintas.prefix(5).map(\.nombre))")
    }
}

// MARK: - Sustitutos

/// Vectores de `findSubstitutes` + `_lastInfo` (y unas búsquedas de `searchSubstitutes`). Formato compacto: ver el
/// comentario de `compactador` en scripts/nativa/vectores-alimentos.mjs.
struct ArchivoSustitutosAlimento: Decodable {
    struct Base: Decodable { let largo: Int }
    struct BaseConPropios: Decodable { let largo: Int; let propios: [Int] }
    /// Lo que un sustituto toma de la base.
    struct AlimentoJS: Decodable {
        let name: String
        let category: String?
        let esPropio: Bool?
        let universal: Bool?
        let en: String?
        enum CodingKeys: String, CodingKey { case name, category, esPropio = "_isCustom", universal = "_universal", en = "_en" }
    }
    /// `[a, qty, unit, kcal, prot, carb, fat, _dev]`
    struct Item: Decodable {
        let a: Int
        let qty, kcal, prot, carb, fat, dev: Double
        let unit: String
        init(from decoder: Decoder) throws {
            var c = try decoder.unkeyedContainer()
            a = try c.decode(Int.self); qty = try c.decode(Double.self); unit = try c.decode(String.self)
            kcal = try c.decode(Double.self); prot = try c.decode(Double.self); carb = try c.decode(Double.self)
            fat = try c.decode(Double.self); dev = try c.decode(Double.self)
        }
    }
    /// `[prefsFiltraron, macrosSospechosos, categoriaFallback]`
    struct Info: Decodable {
        let valor: InfoSustitucion
        init(from decoder: Decoder) throws {
            var c = try decoder.unkeyedContainer()
            valor = InfoSustitucion(prefsFiltraron: try c.decode(Int.self), macrosSospechosos: try c.decode(Bool.self),
                                    categoriaFallback: try c.decode(Bool.self))
        }
    }
    struct Caso: Decodable { let o: Int; let x: Int; let p: Bool; let r: Int; let info: Info }
    struct Busqueda: Decodable { let c: Int; let consulta: String; let posiciones: [Int] }

    let fuente: String
    let base: Base
    let propios: [AlimentoPropio]
    let baseConPropios: BaseConPropios?
    let preferencias: [[String]]
    let originales: [Alimento]
    let alimentos: [AlimentoJS]
    let items: [Item]
    let resultados: [[Int]]
    let casos: [Caso]
    let busquedas: [Busqueda]?
}

/// Lo que devolvió la web para un sustituto, como objeto de JS (el `food_data` que persiste).
func objetoJS(_ e: ArchivoSustitutosAlimento.Item, _ al: ArchivoSustitutosAlimento.AlimentoJS) -> JSONValue {
    var o: [String: JSONValue] = [
        "name": .texto(al.name), "qty": .numero(e.qty), "unit": .texto(e.unit), "kcal": .numero(e.kcal),
        "prot": .numero(e.prot), "carb": .numero(e.carb), "fat": .numero(e.fat), "_dev": .numero(e.dev),
    ]
    if let c = al.category { o["category"] = .texto(c) }
    if al.esPropio == true { o["_isCustom"] = .bool(true) }
    if al.universal == true { o["_universal"] = .bool(true); o["_en"] = .texto(al.en ?? "") }
    return .objeto(o)
}

func igualAWeb(_ s: Sustituto, _ e: ArchivoSustitutosAlimento.Item, _ al: ArchivoSustitutosAlimento.AlimentoJS) -> Bool {
    mismoTextoJS(s.nombre, al.name) && casiIgual(s.qty, e.qty) && s.unidad == e.unit
        && casiIgual(s.kcal, e.kcal) && casiIgual(s.prot, e.prot) && casiIgual(s.carb, e.carb) && casiIgual(s.fat, e.fat)
        && mismoTextoJS(s.categoria, al.category) && casiIgual(s.desvio, e.dev)
        && s.esPropio == (al.esPropio == true) && s.universal == (al.universal == true)
        && s.nombreIngles == (al.universal == true ? al.en : nil)
        && casiIgual(s.foodData, objetoJS(e, al))
}

func fallasSustitutos(_ archivo: URL) throws -> (total: Int, fallas: [String]) {
    let v = try JSONDecoder().decode(ArchivoSustitutosAlimento.self, from: Data(contentsOf: archivo))
    let base = try BaseAlimentos(json: Data(contentsOf: archivoBaseAlimentos))
    var fallas: [String] = []
    if base.alimentos.count != v.base.largo {
        fallas.append("food-db.json tiene \(base.alimentos.count) alimentos y los vectores \(v.base.largo): regenerar")
    }
    let conPropios = base.conPropios(v.propios)
    if let esperado = v.baseConPropios {
        let propios = conPropios.alimentos.indices.filter { conPropios.alimentos[$0].esPropio }
        if conPropios.alimentos.count != esperado.largo || propios != esperado.propios {
            fallas.append("conPropios: \(conPropios.alimentos.count) alimentos, propios en \(propios); la web: \(esperado.largo), \(esperado.propios)")
        }
    }

    var obtenidos: [[Sustituto]] = []
    for (k, c) in v.casos.enumerated() {
        let original = v.originales[c.o]
        let r = SustitucionAlimentos.buscar(original: original, base: c.p ? conPropios : base, excluir: v.preferencias[c.x])
        obtenidos.append(r.sustitutos)
        let donde = "caso \(k) (\(original.nombre.debugDescription), excluir \(v.preferencias[c.x]), propios \(c.p))"
        if r.info != c.info.valor { fallas.append("\(donde): info web \(c.info.valor), swift \(r.info)") }
        let esperados = v.resultados[c.r].map { v.items[$0] }
        if r.sustitutos.count != esperados.count {
            let primero = zip(r.sustitutos, esperados).enumerated().first { !igualAWeb($0.element.0, $0.element.1, v.alimentos[$0.element.1.a]) }?.offset
            fallas.append("\(donde): web \(esperados.count) sustitutos, swift \(r.sustitutos.count); primera diferencia en \(String(describing: primero))")
            continue
        }
        for (i, (s, e)) in zip(r.sustitutos, esperados).enumerated() where !igualAWeb(s, e, v.alimentos[e.a]) {
            fallas.append("\(donde) #\(i): web \(objetoJS(e, v.alimentos[e.a])), swift \(s.foodData)")
            break
        }
    }

    for b in v.busquedas ?? [] {
        let lista = obtenidos[b.c]
        let hallados = SustitucionAlimentos.filtrar(lista, consulta: b.consulta)
        let posiciones = hallados.map { h in lista.firstIndex { mismoTextoJS($0.nombre, h.nombre) } ?? -1 }
        if posiciones != b.posiciones {
            fallas.append("búsqueda \(b.consulta.debugDescription) en el caso \(b.c): web \(b.posiciones), swift \(posiciones)")
        }
    }
    return (v.casos.count, fallas)
}

@Suite("Sustitución de alimentos: la misma lista que la web")
struct SustitucionAlimentosTests {
    @Test func vectoresPublicos() throws {
        let r = try fallasSustitutos(raizRepo.appendingPathComponent("apps/shared/vectores/sustitutos_alimento.json"))
        #expect(r.total > 2000)
        #expect(r.fallas.isEmpty, "\(r.fallas.count) fallas en \(r.total) casos: \(r.fallas.prefix(5))")
    }

    @Test(.enabled(if: FileManager.default.fileExists(atPath: carpetaPrivada.appendingPathComponent("sustitutos_alimento.json").path)))
    func alimentosDeLasDietasReales() throws {
        let r = try fallasSustitutos(carpetaPrivada.appendingPathComponent("sustitutos_alimento.json"))
        #expect(r.total > 1000)
        #expect(r.fallas.isEmpty, "\(r.fallas.count) fallas en \(r.total) casos: \(r.fallas.prefix(5))")
    }

    @Test func sinBaseNoHaySustitutos() {
        let r = SustitucionAlimentos.buscar(original: Alimento(nombre: "Arroz", qty: 100, unidad: "g", kcal: 130, prot: 2.7, carb: 28, fat: 0.3),
                                            base: BaseAlimentos([]))
        #expect(r.sustitutos.isEmpty)
        #expect(r.info == InfoSustitucion())
    }

    @Test func losPropiosReemplazanPorNombreOSeAgregan() throws {
        let base = try BaseAlimentos(json: Data(contentsOf: archivoBaseAlimentos))
        let propios = try JSONDecoder().decode([AlimentoPropio].self, from: Data("""
            [{"name": "CUADRIL", "kcal": 140, "prot": 21, "carb": 0, "fat": 6, "unit": "g", "unit_grams": null, "category": "proteina"},
             {"name": "Barrita casera", "kcal": null, "prot": 30, "carb": 40, "fat": 10, "unit": "unidad", "unit_grams": 0}]
            """.utf8))
        let con = base.conPropios(propios)
        #expect(con.alimentos.count == base.alimentos.count + 1)
        let i = try #require(base.alimentos.firstIndex { $0.nombre == "Cuadril" })
        #expect(con.alimentos[i].nombre == "CUADRIL" && con.alimentos[i].esPropio && con.alimentos[i].kcal == 140)
        let barrita = try #require(con.alimentos.last)
        #expect(barrita.esPropio && barrita.kcal == 0 && barrita.gramosPorUnidad == nil && barrita.categoria == nil)
    }
}

// MARK: - Semántica de JS que usa el motor

@Suite("Semántica de JS del motor de alimentos")
struct SemanticaJSAlimentosTests {
    @Test func finDeTextoComoJS() {
        // En JS /^ajo$/ no acepta un salto de línea final; el `$` de ICU sí (por eso JSRegex lo traduce a \z).
        #expect(JSRegex(#"^ajo$"#).prueba("ajo"))
        #expect(!JSRegex(#"^ajo$"#).prueba("ajo\n"))
        #expect(!JSRegex(#"^ajo$"#).prueba("ajo\r\n"))
        #expect(!JSRegex(#"\bmani$"#).prueba("mani\u{85}"))
        #expect(JSRegex(#"[$]"#).prueba("u$s"))
        #expect(JSRegex(#"\$"#).prueba("u$s"))
    }

    @Test func trimDeJS() {
        #expect(SemanticaJS.recortar("\u{FEFF} pan\u{A0}\u{3000}") == "pan")
        #expect(SemanticaJS.recortar("pan\u{85}") == "pan\u{85}")     // NEL no es espacio para JS
        #expect(SemanticaJS.recortar("   ") == "")
    }

    @Test func textoPorUnidadesUTF16() {
        let nfc = "Vac\u{ED}o", nfd = "Vaci\u{301}o"
        #expect(nfc == nfd)                                   // Swift: equivalencia canónica
        #expect(!SemanticaJS.iguales(nfc, nfd))               // JS: otro texto
        #expect(SemanticaJS.incluye(Array("pan\u{301}".utf16), Array("pan".utf16)))
        #expect(!"pan\u{301}".contains("pan"))                // Swift compara caracteres completos
        #expect(SustitucionAlimentos.normalizar(nfd) == "vaci\u{301}o")   // la tilde suelta no se toca, como en la web
        #expect(SustitucionAlimentos.normalizar("ÑANDÚ Ñoño") == "nandu nono")
    }

    @Test func universalesYEtiquetas() {
        #expect(SustitucionAlimentos.esUniversal("Pan francés / baguette"))
        #expect(!SustitucionAlimentos.esUniversal("Panceta"))
        #expect(SustitucionAlimentos.etiquetaIngles("Carne vacuna picada (magra 90/10)") == "Lean ground beef (90/10)")
        #expect(SustitucionAlimentos.etiquetaIngles("Panceta") == "Bread")   // `includes`, no palabra: así lo hace la web
        #expect(SustitucionAlimentos.etiquetaIngles("Brócoli") == "")
    }
}
