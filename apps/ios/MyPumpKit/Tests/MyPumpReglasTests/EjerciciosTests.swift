import CryptoKit
import Foundation
import Testing
import MyPumpModelos
@testable import MyPumpReglas

/// Vectores de scripts/nativa/vectores-ejercicios.mjs: las funciones REALES de la web (`exerciseSwap` de app.js,
/// `getEffectiveEx` y `exGetSubs` de cliente.html) corridas sobre el catálogo empaquetado. Igualdad total, y los textos
/// se comparan por unidades UTF-16 (el `==` de Swift perdona NFC contra NFD; la web no).
struct ArchivoSustitutos: Decodable {
    struct Catalogo: Decodable { let archivo: String; let filas: Int; let sha256: String }
    struct Sintetica: Decodable { let entrada: EntradaCatalogoEjercicio; let es: String; let equipo: String }
    struct Orden: Decodable { let entrada: [String]; let salida: [Int] }
    struct Nombre: Decodable { let n: String; let norm: String; let regla: String?; let slug: String? }
    struct Caso: Decodable {
        let e: Int
        let directo: Bool?
        let resuelto: String?
        let sw: JSONValue?
        let efectivo: JSONValue?
        let excluido: Bool?
        let resueltoUI: String?
        let subs: Int
    }
    /// Un catálogo armado a mano: los sustitutos van enteros (el catálogo tiene slugs repetidos a propósito).
    struct Sintetico: Decodable {
        struct Caso: Decodable { let ref: JSONValue; let resuelto: Int?; let subs: [JSONValue] }
        struct Efectivo: Decodable { let ex: JSONValue; let efectivo: JSONValue; let subs: [JSONValue] }
        let catalogo: [EntradaCatalogoEjercicio]
        let casos: [Caso]
        let efectivos: [Efectivo]
    }

    let fuente: String
    let catalogo: Catalogo
    /// `[_toEs, _equipLabel]` de cada fila del catálogo, por índice.
    let traducciones: [[String]]
    let sinteticas: [Sintetica]
    let orden: Orden
    /// `findSubstitutes` de cada fila: slug → `[[índice de la fila del sustituto, _sameEquip]]`. Sin clave = vacía.
    let listas: [String: [[Int]]]
    /// Las que cambian con el catálogo al revés.
    let listasAlReves: [String: [[Int]]]
    let nombres: [Nombre]
    let ejercicios: [JSONValue]
    let casos: [Caso]
    /// Solo en los públicos.
    let sintetico: Sintetico?
}

let vectoresSustitutos = raizRepo.appendingPathComponent("apps/shared/vectores/sustitutos_ejercicio.json")
let vectoresSustitutosPrivados = carpetaPrivada.appendingPathComponent("sustitutos_ejercicio.json")

func cargarSustitutos(_ archivo: URL) throws -> (ArchivoSustitutos, CatalogoEjercicios) {
    let v = try JSONDecoder().decode(ArchivoSustitutos.self, from: Data(contentsOf: archivo))
    let datos = try Data(contentsOf: raizRepo.appendingPathComponent(v.catalogo.archivo))
    let hash = SHA256.hash(data: datos).map { String(format: "%02x", $0) }.joined()
    #expect(hash == v.catalogo.sha256, "el catálogo no es con el que se generaron los vectores: node scripts/nativa/vectores-ejercicios.mjs --sin-red")
    return (v, try CatalogoEjercicios(json: datos))
}

/// Mismo texto que dio JS, unidad UTF-16 por unidad.
func exacto(_ a: String?, _ b: String?) -> Bool {
    switch (a, b) {
    case (nil, nil): return true
    case let (a?, b?): return a.utf16.elementsEqual(b.utf16)
    default: return false
    }
}

/// `x || null` de JS sobre un texto.
func nuloSiVacio(_ s: String?) -> String? { s?.isEmpty == false ? s : nil }

/// Las imágenes de JS (objeto o null; una clave que falta vale null) contra las de Swift.
func igualesImagenes(_ js: JSONValue?, _ swift: Imagenes?) -> Bool {
    guard case .objeto(let o)? = js else { return swift == nil }
    guard let swift else { return false }
    return exacto(o["eccentric"]?.comoTexto, swift.eccentric) && exacto(o["concentric"]?.comoTexto, swift.concentric)
        && exacto(o["_matched_slug"]?.comoTexto, swift.matchedSlug)
}

func imagenes(_ js: JSONValue?) throws -> Imagenes? {
    guard case .objeto? = js else { return nil }
    return try JSONDecoder().decode(Imagenes.self, from: JSONEncoder().encode(js))
}

/// La lista de Swift contra la de la web. La web guarda cada sustituto como [fila, _sameEquip]: el generador ya
/// verificó que el objeto de `findSubstitutes` es esa fila con su `_toEs` y su `_equipLabel` (y "" como null en las
/// imágenes); acá se exige lo mismo, campo por campo.
func diferencia(_ swift: [SustitutoEjercicio], _ web: [[Int]], _ cat: CatalogoEjercicios, _ trad: [[String]]) -> String? {
    guard swift.count == web.count else {
        return "\(swift.count) sustitutos y la web \(web.count): swift \(swift.map { $0.slug ?? "nil" }), web \(web.map { cat.entradas[$0[0]].slugEn ?? "nil" })"
    }
    for (k, (s, par)) in zip(swift, web).enumerated() {
        let e = cat.entradas[par[0]]
        let ok = exacto(s.slug, e.slugEn) && exacto(s.nombre, trad[par[0]][0]) && exacto(s.nombreIngles, e.nameEn)
            && exacto(s.equipo, trad[par[0]][1]) && exacto(s.equipoCrudo, e.equipment) && exacto(s.musculo, e.primaryMuscle)
            && exacto(s.patron, e.patronMovimiento) && exacto(s.imagenes.eccentric, nuloSiVacio(e.imageEccentric))
            && exacto(s.imagenes.concentric, nuloSiVacio(e.imageConcentric)) && s.imagenes.matchedSlug == nil
            && s.mismoEquipo == (par[1] == 1)
        if !ok { return "posición \(k): swift \(s), web \(e.slugEn ?? "nil") \(trad[par[0]]) mismo equipo \(par[1])" }
    }
    return nil
}

/// Sustitutos enteros, tal como los devolvió `findSubstitutes`, contra los de Swift.
func diferenciaCompleta(_ swift: [SustitutoEjercicio], _ web: [JSONValue]) -> String? {
    guard swift.count == web.count else {
        return "\(swift.count) sustitutos y la web \(web.count): swift \(swift.map { $0.slug ?? "nil" }), web \(web.map { $0["slug"]?.comoTexto ?? "nil" })"
    }
    for (k, (s, w)) in zip(swift, web).enumerated() {
        let ok = exacto(s.slug, w["slug"]?.comoTexto) && exacto(s.nombre, w["name"]?.comoTexto)
            && exacto(s.nombreIngles, w["name_en"]?.comoTexto) && exacto(s.equipo, w["equipo"]?.comoTexto)
            && exacto(s.equipoCrudo, w["equipmentRaw"]?.comoTexto) && exacto(s.musculo, w["primary_muscle"]?.comoTexto)
            && exacto(s.patron, w["patron_movimiento"]?.comoTexto) && igualesImagenes(w["images"], s.imagenes)
            && (w["_sameEquip"] == .bool(true)) == s.mismoEquipo
        if !ok { return "posición \(k): swift \(s), web \(w)" }
    }
    return nil
}

/// `getEffectiveEx` de la web contra `efectivo` de Swift. `Ejercicio.nombre` no distingue ausente de "" (en JS los
/// dos son falsos y dan lo mismo más adelante).
func diferenciaEfectivo(_ js: JSONValue?, _ ef: EjercicioEfectivo) -> String? {
    guard let js else { return "el vector no trae efectivo" }
    var malos: [String] = []
    if !exacto(js["nombre"]?.comoTexto ?? "", ef.ejercicio.nombre) { malos.append("nombre") }
    if !igualesImagenes(js["images"], ef.ejercicio.imagenes) { malos.append("images") }
    if (js["_isSwapped"] == .bool(true)) != ef.sustituido { malos.append("_isSwapped") }
    if !exacto(js["_swapSlug"]?.comoTexto, ef.slugSustituto) { malos.append("_swapSlug") }
    if (js["_swapFijado"] == .bool(true)) != ef.fijado { malos.append("_swapFijado") }
    if !exacto(js["_origNombre"]?.comoTexto ?? "", ef.nombreOriginal ?? "") { malos.append("_origNombre") }
    if !igualesImagenes(js["_origImages"], ef.imagenesOriginales) { malos.append("_origImages") }
    if !exacto(js["_origSlug"]?.comoTexto, ef.slugOriginal) { malos.append("_origSlug") }
    return malos.isEmpty ? nil : "\(malos): web \(js), swift \(ef)"
}

/// Cada ejercicio: `_resolve` y `findSubstitutes` del ejercicio del plan; `getEffectiveEx` con y sin sustitución; y
/// `exGetSubs` sobre el efectivo (o sobre el objeto con `_orig*`, en los casos directos).
func fallasCasos(_ v: ArchivoSustitutos, _ cat: CatalogoEjercicios) throws -> [String] {
    var fallas: [String] = []
    func lista(_ slug: String?) -> [[Int]] { slug.flatMap { v.listas[$0] } ?? [] }
    // Sobre qué armó la web las listas de cada ejercicio sin sustituir: con el lugar sustituido, la app arma las mismas.
    var antesDeSustituir: [Int: String?] = [:]
    for c in v.casos where c.sw == nil && c.directo != true && c.excluido != true { antesDeSustituir[c.e] = c.resueltoUI }
    for c in v.casos {
        let crudo = v.ejercicios[c.e]
        let ex = try JSONDecoder().decode(Ejercicio.self, from: JSONEncoder().encode(crudo))
        let quien = "#\(c.e) \(ex.nombre.debugDescription)"
        let ef: EjercicioEfectivo
        var sw: SustitucionAplicada?
        if c.directo == true {
            ef = EjercicioEfectivo(ejercicio: ex, nombreOriginal: crudo["_origNombre"]?.comoTexto,
                                   imagenesOriginales: try imagenes(crudo["_origImages"]), slugOriginal: crudo["_origSlug"]?.comoTexto)
        } else {
            let r = cat.resolver(ex)
            if !exacto(r?.slugEn, c.resuelto) { fallas.append("\(quien): _resolve web \(c.resuelto ?? "null"), swift \(r?.slugEn ?? "null")") }
            if let d = diferencia(cat.sustitutos(ReferenciaEjercicio(ex)), lista(c.resuelto), cat, v.traducciones) {
                fallas.append("\(quien): findSubstitutes \(d)")
            }
            sw = try c.sw.map {
                SustitucionAplicada(slug: $0["slug"]?.comoTexto, nombre: $0["nombre"]?.comoTexto ?? "", equipo: $0["equipment"]?.comoTexto,
                                    imagenes: try imagenes($0["images"]), fijado: $0["fijado"] == .bool(true))
            }
            ef = cat.efectivo(ex, sustitucion: sw)
            if let d = diferenciaEfectivo(c.efectivo, ef) { fallas.append("\(quien)\(sw == nil ? "" : " sustituido"): getEffectiveEx \(d)") }
        }
        let subs = cat.sustitutos(de: ef)
        // Desvío a propósito (revisión del 21-oct): con el lugar sustituido, las listas son las de antes de sustituir
        // (`referenciaDeLasListas`). La web, con un plan sin fotos, las arma sobre la foto del sustituto
        // (`_origImages || images`) y al reabrir «Cambiar» ofrece las del sustituto. El `orig` de la web sigue igual.
        let esperado: String? = sw == nil ? c.resueltoUI : (antesDeSustituir[c.e] ?? c.resueltoUI)
        if c.excluido == true {
            if !subs.isEmpty { fallas.append("\(quien): calentamiento o cardio con \(subs.count) sustitutos") }
        } else {
            let r = cat.resolver(CatalogoEjercicios.referencia(de: ef))
            if !exacto(r?.slugEn, c.resueltoUI) { fallas.append("\(quien): exGetSubs resolvió web \(c.resueltoUI ?? "null"), swift \(r?.slugEn ?? "null")") }
            let rl = cat.resolver(cat.referenciaDeLasListas(ef))
            if !exacto(rl?.slugEn, esperado) { fallas.append("\(quien): las listas van sobre \(rl?.slugEn ?? "null") y no \(esperado ?? "null")") }
            if let d = diferencia(subs, lista(esperado), cat, v.traducciones) { fallas.append("\(quien): exGetSubs \(d)") }
        }
        if subs.count != (sw == nil ? c.subs : lista(esperado).count) { fallas.append("\(quien): exGetSubs da \(subs.count), la web \(c.subs)") }
    }
    return fallas
}

/// `_norm`, `_resolveByRules` y `_resolve` por nombre.
func fallasNombres(_ v: ArchivoSustitutos, _ cat: CatalogoEjercicios) -> [String] {
    v.nombres.compactMap { x in
        let norm = SustitucionEjercicios.normalizar(x.n)
        let regla = SustitucionEjercicios.slugPorReglas(x.n)
        let slug = cat.resolver(ReferenciaEjercicio(nombre: x.n))?.slugEn
        if exacto(norm, x.norm) && exacto(regla, x.regla) && exacto(slug, x.slug) { return nil }
        return "\(x.n.debugDescription): web (\(x.norm.debugDescription), \(x.regla ?? "null"), \(x.slug ?? "null")), "
            + "swift (\(norm.debugDescription), \(regla ?? "null"), \(slug ?? "null"))"
    }
}

@Suite("Sustitución de ejercicios: misma salida que la web")
struct SustitucionVectoresTests {
    /// Nombres que la app cambia a propósito (20-oct): la patada de tríceps, que la web llama «Patada de glúteo». Allá no
    /// se ve; en la app aparece entre los otros ejercicios de tríceps y es el nombre que se registra al sustituir.
    static let desvios: [String: (web: String, app: String)] = [
        "Tricep_Dumbbell_Kickback": ("Patada de glúteo con mancuernas", "Patada de tríceps con mancuernas"),
    ]

    @Test func traduccionesDelCatalogo() throws {
        let (v, cat) = try cargarSustitutos(vectoresSustitutos)
        #expect(cat.entradas.count == v.catalogo.filas)
        var fallas: [String] = []
        for (i, e) in cat.entradas.enumerated() {
            let es = SustitucionEjercicios.castellano(e), eq = SustitucionEjercicios.etiquetaEquipo(e)
            // Los desvíos a propósito: la web sigue con su nombre (si lo arregla allá, esto avisa).
            if let d = Self.desvios[e.slugEn ?? ""] {
                if !exacto(v.traducciones[i][0], d.web) || !exacto(es, d.app) { fallas.append("\(e.slugEn ?? ""): desvío \(d), web \(v.traducciones[i][0]), swift \(es)") }
                continue
            }
            if !exacto(es, v.traducciones[i][0]) || !exacto(eq, v.traducciones[i][1]) {
                fallas.append("\(e.slugEn ?? "nil"): web \(v.traducciones[i]), swift [\(es), \(eq)]")
            }
        }
        for s in v.sinteticas {
            let es = SustitucionEjercicios.castellano(s.entrada), eq = SustitucionEjercicios.etiquetaEquipo(s.entrada)
            if !exacto(es, s.es) || !exacto(eq, s.equipo) {
                fallas.append("\(s.entrada.nameEn.debugDescription) / \(s.entrada.equipment.debugDescription): web [\(s.es), \(s.equipo)], swift [\(es), \(eq)]")
            }
        }
        #expect(v.sinteticas.count > 200)
        #expect(fallas.isEmpty, "\(fallas.count) de \(cat.entradas.count + v.sinteticas.count): \(fallas.prefix(8))")
    }

    @Test func ordenComoLocaleCompare() throws {
        let (v, _) = try cargarSustitutos(vectoresSustitutos)
        let e = v.orden.entrada
        let swift = e.indices.sorted { a, b in
            switch SustitucionEjercicios.compararNombres(e[a], e[b]) {
            case .orderedAscending: true
            case .orderedDescending: false
            case .orderedSame: a < b
            }
        }
        #expect(e.count > 1000)
        let primera = Array(zip(swift, v.orden.salida)).firstIndex { $0 != $1 }
        #expect(swift == v.orden.salida, "primera diferencia en \(primera.map(String.init) ?? "el largo"): swift \(primera.map { e[swift[$0]] } ?? ""), web \(primera.map { e[v.orden.salida[$0]] } ?? "")")
    }

    @Test func nombresYReglas() throws {
        let (v, cat) = try cargarSustitutos(vectoresSustitutos)
        let fallas = fallasNombres(v, cat)
        #expect(v.nombres.count > 300)
        #expect(fallas.isEmpty, "\(fallas.count) de \(v.nombres.count): \(fallas.prefix(8))")
    }

    /// Todas las listas posibles: `findSubstitutes` de cada fila del catálogo, en el orden del archivo y al revés.
    @Test func listasDeTodoElCatalogo() throws {
        let (v, cat) = try cargarSustitutos(vectoresSustitutos)
        let alReves = CatalogoEjercicios(cat.entradas.reversed())
        var fallas: [String] = []
        for e in cat.entradas {
            let slug = e.slugEn ?? ""
            if let d = diferencia(cat.sustitutos(ReferenciaEjercicio(catalogoSlug: slug)), v.listas[slug] ?? [], cat, v.traducciones) {
                fallas.append("\(slug): \(d)")
            }
            // Al revés cambian la variante que queda de cada nombre repetido y el orden de los empates.
            let web = v.listasAlReves[slug] ?? v.listas[slug] ?? []
            if let d = diferencia(alReves.sustitutos(ReferenciaEjercicio(catalogoSlug: slug)), web, cat, v.traducciones) {
                fallas.append("\(slug) al revés: \(d)")
            }
        }
        #expect(v.listas.count > 400)
        #expect(v.listasAlReves.count > 100)
        #expect(fallas.isEmpty, "\(fallas.count) de \(2 * cat.entradas.count): \(fallas.prefix(5))")
    }

    /// Lo que el catálogo real hoy no ejercita: el tope de 30, slugs repetidos, un alias igual al `name_normalized` de
    /// otra fila, null === null, patrón "", filas sin foto y un slug con acento descompuesto.
    @Test func catalogoSintetico() throws {
        let (v, _) = try cargarSustitutos(vectoresSustitutos)
        let s = try #require(v.sintetico)
        let cat = CatalogoEjercicios(s.catalogo)
        var fallas: [String] = []
        for c in s.casos {
            let ref = ReferenciaEjercicio(nombre: c.ref["nombre"]?.comoTexto, imagenes: try imagenes(c.ref["images"]),
                                          catalogoSlug: c.ref["catalogo_slug"]?.comoTexto, matchedSlug: c.ref["_matched_slug"]?.comoTexto)
            let r = cat.resolver(ref).flatMap { e in cat.entradas.firstIndex { $0 == e } }
            if r != c.resuelto { fallas.append("\(c.ref): _resolve web fila \(c.resuelto.map(String.init) ?? "null"), swift \(r.map(String.init) ?? "null")") }
            if let d = diferenciaCompleta(cat.sustitutos(ref), c.subs) { fallas.append("\(c.ref): findSubstitutes \(d)") }
        }
        for c in s.efectivos {
            let ex = try JSONDecoder().decode(Ejercicio.self, from: JSONEncoder().encode(c.ex))
            let ef = cat.efectivo(ex, sustitucion: nil)
            if let d = diferenciaEfectivo(c.efectivo, ef) { fallas.append("\(c.ex): getEffectiveEx \(d)") }
            if let d = diferenciaCompleta(cat.sustitutos(de: ef), c.subs) { fallas.append("\(c.ex): exGetSubs \(d)") }
        }
        #expect(s.casos.contains { $0.subs.count == 30 })
        #expect(fallas.isEmpty, "\(fallas.count) de \(s.casos.count + s.efectivos.count): \(fallas.prefix(5))")
    }

    @Test func casosPublicos() throws {
        let (v, cat) = try cargarSustitutos(vectoresSustitutos)
        let fallas = try fallasCasos(v, cat)
        #expect(v.casos.count > 250)
        #expect(v.casos.contains { $0.sw != nil } && v.casos.contains { $0.directo == true } && v.casos.contains { $0.excluido == true })
        #expect(fallas.isEmpty, "\(fallas.count) de \(v.casos.count): \(fallas.prefix(5))")
        // El desvío de `referencia(de:)`: la web sigue armando sobre el sustituto los de un plan sin fotos.
        #expect(v.casos.filter { $0.sw != nil && !exacto($0.resueltoUI, $0.resuelto) }.count > 50, "la web ya arma las listas sobre el original: sacar el desvío")
    }

    @Test(.enabled(if: FileManager.default.fileExists(atPath: carpetaPrivada.appendingPathComponent("sustitutos_ejercicio.json").path)))
    func ejerciciosDeLosPlanesReales() throws {
        let (v, cat) = try cargarSustitutos(vectoresSustitutosPrivados)
        let fallas = try fallasCasos(v, cat) + fallasNombres(v, cat)
        #expect(v.casos.count > 2000)
        #expect(v.nombres.count > 500)
        #expect(fallas.isEmpty, "\(fallas.count) de \(v.casos.count + v.nombres.count): \(fallas.prefix(5))")
    }

    /// Lo que ICU haría distinto si no se tradujera (lo esperado salió de node).
    @Test func semanticaDeJS() {
        // El `.` de JS toma VT y NEL: el paréntesis se va entero.
        #expect(SustitucionEjercicios.normalizar("Curl (a\u{0B}b) martillo") == "curl martillo")
        #expect(SustitucionEjercicios.normalizar("Curl (a\u{85}b) martillo") == "curl martillo")
        #expect(SustitucionEjercicios.normalizar("Curl (a\u{0C}b) martillo") == "curl martillo")
        // `\n` y U+2028 sí lo cortan, como en JS.
        #expect(SustitucionEjercicios.normalizar("Curl (a\nb) martillo") == "curl a b martillo")
        #expect(SustitucionEjercicios.normalizar("Curl (a\u{2028}b) martillo") == "curl a b martillo")
        // Acento descompuesto: la web no lo normaliza.
        #expect(SustitucionEjercicios.normalizar("Jalo\u{301}n") == "jalo n")
        // `/\bsmith\b/i` sin flag u: la "ſ" no es "s".
        #expect(SustitucionEjercicios.etiquetaEquipo(EntradaCatalogoEjercicio(slugEn: "x", nameEn: "ſmith row", equipment: "barbell")) == "Barra")
        #expect(SustitucionEjercicios.etiquetaEquipo(EntradaCatalogoEjercicio(slugEn: "x", nameEn: "SMITH row", equipment: "barbell")) == "Multipower")
        // `exec`: la primera aparición, aunque no esté en el catálogo.
        #expect(SustitucionEjercicios.slugDeURL("a/exercise-images/No_Existe/exercise-images/Leg_Press/0.jpg") == "No_Existe")
        #expect(SustitucionEjercicios.slugDeURL("exercise-images//0.jpg") == nil)
    }
}

/// SER-11: la búsqueda de la hoja de sustitutos, como la web
/// (`all.filter(s => s.name.toLowerCase().includes(query.toLowerCase().trim()))`; los resultados salen de node).
@Suite("Sustitutos de ejercicio: la búsqueda")
struct BusquedaSustitutosTests {
    static func sustituto(_ nombre: String) -> SustitutoEjercicio {
        SustitutoEjercicio(slug: nil, nombre: nombre, nombreIngles: nil, equipo: "Máquina", equipoCrudo: nil, musculo: nil,
                           patron: nil, imagenes: Imagenes(eccentric: nil, concentric: nil), mismoEquipo: false)
    }

    @Test func comoLaWeb() {
        let todos = ["Jalón al pecho", "Remo con barra", "JALÓN TRAS NUCA", "Remo en polea baja"].map(Self.sustituto)
        func nombres(_ q: String) -> [String] { SustitucionesEntreno.filtrar(todos, q).map(\.nombre) }
        #expect(nombres("") == todos.map(\.nombre))
        #expect(nombres("   ") == todos.map(\.nombre))   // recortada queda vacía: entra todo
        #expect(nombres("jalón") == ["Jalón al pecho", "JALÓN TRAS NUCA"])
        #expect(nombres("  REMO ") == ["Remo con barra", "Remo en polea baja"])
        #expect(nombres("jalon").isEmpty)                 // la web no pliega acentos
        #expect(nombres("polea baja") == ["Remo en polea baja"])
    }
}


/// Los otros ejercicios del mismo músculo (Mati, 20-oct: Eric, con la polea ocupada, no tenía con qué cambiar la extensión
/// en polea; quería fondos). Es de la app: la web solo ofrece el mismo movimiento.
@Suite("Sustitución de ejercicios: otros del mismo músculo")
struct OtrosDelMismoMusculoTests {
    @Test func aLaExtensionEnPoleaLeQuedanFondosYExtensiones() throws {
        let (_, cat) = try cargarSustitutos(vectoresSustitutos)
        let r = ReferenciaEjercicio(nombre: "Extensión en polea alta con barra", imagenes: nil, catalogoSlug: "Triceps_Pushdown")
        let arriba = cat.sustitutos(r)
        let otros = cat.otrosDelMismoMusculo(r)
        let nombres = otros.map { "\($0.nombre) · \($0.equipo)" }
        #expect(arriba.map(\.nombre) == ["Extensión de tríceps en polea"], "las variantes de siempre, igual que la web")
        #expect(nombres.contains("Fondos · Peso corporal"), "\(nombres)")
        #expect(nombres.contains("Patada de tríceps con mancuernas · Mancuernas"))
        #expect(nombres.contains("Press francés con barra Z · Barra Z"))
        #expect(!otros.contains { $0.nombre == "Press" || $0.nombre == $0.nombreIngles }, "sin nombres sueltos ni sin traducir")
        #expect(!otros.contains { s in arriba.contains { $0.nombre == s.nombre && $0.equipo == s.equipo } }, "sin repetir lo de arriba")
        #expect(otros.allSatisfy { $0.musculo == "triceps" && $0.patron != nil && $0.patron != "extension_triceps_pushdown" })
        // Otro equipo primero: la polea es la que está ocupada.
        let desde = otros.firstIndex(where: \.mismoEquipo) ?? otros.count
        #expect(otros[desde...].allSatisfy(\.mismoEquipo) && desde > 0)
        #expect((15...30).contains(otros.count), "\(otros.count)")
    }

    /// Las filas mal clasificadas no se cuelan: «Encogimientos» figura como espalda media en el catálogo, pero su patrón
    /// es de trapecio, así que al remo con barra no le aparece (lo vio la prueba de la demo, 20-oct).
    @Test func unaFilaMalClasificadaNoSeOfrece() throws {
        let (_, cat) = try cargarSustitutos(vectoresSustitutos)
        #expect(cat.musculo(dePatron: "encogimiento_trapecio") == "traps")
        #expect(cat.musculo(dePatron: "fondos_paralelas") == "triceps")
        let remo = cat.otrosDelMismoMusculo(ReferenciaEjercicio(nombre: "Remo con barra", imagenes: nil, catalogoSlug: "Bent_Over_Barbell_Row"))
        #expect(!remo.contains { $0.nombre.hasPrefix("Encogimientos") }, "\(remo.map(\.nombre))")
        // A una sentadilla le quedan zancadas y extensión de cuádriceps.
        let sentadilla = cat.otrosDelMismoMusculo(ReferenciaEjercicio(nombre: "Sentadilla con barra", imagenes: nil, catalogoSlug: "Barbell_Squat"))
        #expect(sentadilla.contains { $0.patron == "zancada_unilateral" } && sentadilla.contains { $0.patron == "extension_rodilla" })
        #expect(sentadilla.allSatisfy { $0.musculo == "quadriceps" })
    }

    /// Las listas de 8 ejercicios (empuje, tirón, piernas, brazos) quedan grabadas para que Android dé exactamente lo mismo.
    /// Para regenerarlas: `GENERAR_VECTORES_OTROS=1 swift test --filter OtrosDelMismoMusculoTests/generarVectores`.
    static let slugsVector = ["Triceps_Pushdown", "Barbell_Squat", "Bent_Over_Barbell_Row", "Barbell_Bench_Press_-_Medium_Grip",
                              "Barbell_Curl", "Romanian_Deadlift", "Side_Lateral_Raise", "Wide-Grip_Lat_Pulldown"]
    static var archivoVector: URL { raizRepo.appendingPathComponent("apps/shared/vectores/otros_mismo_musculo.json") }

    static func listas(_ cat: CatalogoEjercicios) -> [String: [String]] {
        Dictionary(uniqueKeysWithValues: slugsVector.map { slug in
            (slug, cat.otrosDelMismoMusculo(ReferenciaEjercicio(nombre: nil, imagenes: nil, catalogoSlug: slug)).map { "\($0.nombre) · \($0.equipo)" })
        })
    }

    /// Y la huella de la lista de CADA ejercicio del catálogo que tenga alguno (los 16 primeros hex del SHA-256 de las
    /// líneas «nombre · equipo» unidas con \n): con eso Android se compara ejercicio por ejercicio sin un archivo enorme.
    static func huellas(_ cat: CatalogoEjercicios) -> [String: String] {
        var out: [String: String] = [:]
        for slug in cat.entradas.compactMap(\.slugEn) where out[slug] == nil {
            let lista = cat.otrosDelMismoMusculo(ReferenciaEjercicio(nombre: nil, imagenes: nil, catalogoSlug: slug)).map { "\($0.nombre) · \($0.equipo)" }
            if lista.isEmpty { continue }
            out[slug] = SHA256.hash(data: Data(lista.joined(separator: "\n").utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
        }
        return out
    }

    @Test func generarVectores() throws {
        guard ProcessInfo.processInfo.environment["GENERAR_VECTORES_OTROS"] == "1" else { return }
        let (_, cat) = try cargarSustitutos(vectoresSustitutos)
        let todo: [String: Any] = ["generado": "MyPumpKit OtrosDelMismoMusculoTests (iOS). Android: OtrosDelMismoMusculoTest lo tiene que dar igual.",
                                   "listas": Self.listas(cat), "huellas": Self.huellas(cat)]
        try JSONSerialization.data(withJSONObject: todo, options: [.prettyPrinted, .sortedKeys]).write(to: Self.archivoVector)
    }

    @Test func losVectoresSiguenIguales() throws {
        let (_, cat) = try cargarSustitutos(vectoresSustitutos)
        let todo = try JSONSerialization.jsonObject(with: Data(contentsOf: Self.archivoVector)) as! [String: Any]
        #expect((todo["listas"] as? [String: [String]]) == Self.listas(cat))
        let huellas = try #require(todo["huellas"] as? [String: String])
        #expect(huellas == Self.huellas(cat))
        #expect(huellas.count > 300, "casi todo el catálogo con patrón tiene otros del mismo músculo: \(huellas.count)")
    }

    /// Revisión del 21-oct, hallazgo 3: entre los otros de hombros salían «Remo con barra · Barra» (Barbell_Rear_Delt_Row)
    /// y «Remo en polea · Polea» (Cable_Rope_Rear-Delt_Rows), con el nombre (y entonces el historial, que va por el nombre)
    /// de los remos de espalda; entre los de bíceps, «Curl de bíceps · Otro» (Reverse_Plate_Curls), un nombre que el
    /// catálogo usa también para filas de antebrazo y de abdominales. Los fondos de tríceps se quedan: la fila de pecho con
    /// ese nombre (Dips_-_Chest_Version) es el mismo movimiento.
    @Test func unNombreQueElCatalogoUsaParaOtroMusculoNoSeOfrece() throws {
        let (_, cat) = try cargarSustitutos(vectoresSustitutos)
        let hombros = cat.otrosDelMismoMusculo(ReferenciaEjercicio(nombre: "Elevaciones laterales", imagenes: nil, catalogoSlug: "Side_Lateral_Raise"))
        let nombres = hombros.map { "\($0.nombre) · \($0.equipo)" }
        #expect(!nombres.contains("Remo con barra · Barra") && !nombres.contains("Remo en polea · Polea"), "\(nombres)")
        #expect(!hombros.contains { $0.nombre.hasPrefix("Remo") }, "ningún remo del deltoide posterior con nombre de remo de espalda")
        #expect(hombros.count >= 15, "a los hombros les quedan otros: \(hombros.count)")
        let biceps = cat.otrosDelMismoMusculo(ReferenciaEjercicio(nombre: "Curl con barra", imagenes: nil, catalogoSlug: "Barbell_Curl"))
        #expect(!biceps.contains { $0.nombre == "Curl de bíceps" }, "\(biceps.map(\.nombre))")
        let triceps = cat.otrosDelMismoMusculo(ReferenciaEjercicio(nombre: "Extensión en polea alta con barra", imagenes: nil, catalogoSlug: "Triceps_Pushdown"))
        #expect(triceps.contains { $0.nombre == "Fondos" && $0.equipo == "Peso corporal" }, "los fondos de tríceps siguen")
        // En ninguna de las listas grabadas un otro comparte nombre con una fila de otro músculo y otro movimiento.
        var usos: [String: [(musculo: String?, patron: String?)]] = [:]
        for e in cat.entradas { usos[SustitucionEjercicios.castellano(e), default: []].append((e.primaryMuscle, e.patronMovimiento)) }
        for slug in Self.slugsVector {
            for o in cat.otrosDelMismoMusculo(ReferenciaEjercicio(nombre: nil, imagenes: nil, catalogoSlug: slug)) {
                let ajenas = (usos[o.nombre] ?? []).filter { $0.musculo != o.musculo && $0.patron != o.patron }
                #expect(ajenas.isEmpty, "\(slug): «\(o.nombre)» también es de \(ajenas)")
            }
        }
    }

    @Test func sinPatronNoSeOfreceNada() throws {
        let (_, cat) = try cargarSustitutos(vectoresSustitutos)
        // Sin clasificar en el catálogo (como en la web, sin patrón no hay sustitutos): ni variantes ni otros.
        let r = ReferenciaEjercicio(nombre: "Bench Press - Powerlifting", imagenes: nil, catalogoSlug: "Bench_Press_-_Powerlifting")
        #expect(cat.sustitutos(r).isEmpty && cat.otrosDelMismoMusculo(r).isEmpty)
    }
}
