import Foundation
import Testing
import MyPumpModelos
@testable import MyPumpReglas

/// El código de barras (2.1, S3): el número del escáner, la respuesta de Open Food Facts llevada a un alimento y la caché.
/// Los casos son los vectores compartidos con Android (`apps/shared/vectores/barras_off.json`), armados con respuestas
/// reales de productos argentinos (yogur, leche, galletitas, barras de cereal) y casos sintéticos.
@Suite("Dieta: código de barras")
struct CodigoBarrasTests {
    static let archivo = raizRepo.appendingPathComponent("apps/shared/vectores/barras_off.json")
    static var vectores: [String: Any] {
        get throws { try JSONSerialization.jsonObject(with: Data(contentsOf: archivo)) as! [String: Any] }
    }

    @Test func losCodigosSeNormalizanComoLosVectores() throws {
        let casos = try Self.vectores["codigos"] as! [[String: Any]]
        #expect(casos.count >= 15)
        for c in casos {
            let r = CodigoBarras.normalizar(c["texto"] as! String, upcE: c["upcE"] as! Bool)
            #expect(r == c["esperado"] as? String, "\(c["texto"]!) upcE=\(c["upcE"]!): \(r ?? "nil")")
        }
    }

    /// Lo que sale de una lectura, con la forma de los vectores.
    static func json(_ l: CodigoBarras.Lectura) -> [String: Any] {
        switch l {
        case .noEncontrado: return ["estado": "noEncontrado"]
        case .encontrado(let p):
            var d: [String: Any] = ["estado": "encontrado", "nombre": p.nombre,
                                    "por100": ["kcal": p.por100.kcal, "p": p.por100.p, "c": p.por100.c, "g": p.por100.g]]
            if let m = p.medida, let g = p.gramosMedida { d["medida"] = ["nombre": m, "gramos": g] }
            return d
        case .incompleto(let x):
            var d: [String: Any] = ["estado": "incompleto", "motivo": x.motivo.rawValue]
            if let v = x.nombre { d["nombre"] = v }
            if let v = x.kcal { d["kcal"] = v }
            if let v = x.p { d["p"] = v }
            if let v = x.c { d["c"] = v }
            if let v = x.g { d["g"] = v }
            return d
        }
    }

    @Test func lasRespuestasDeOpenFoodFactsDanLoMismoQueLosVectores() throws {
        let casos = try Self.vectores["productos"] as! [[String: Any]]
        #expect(casos.filter { $0["real"] as! Bool }.count >= 10)
        for c in casos {
            let datos = try JSONSerialization.data(withJSONObject: c["respuesta"]!)
            let j = try JSONDecoder().decode(JSONValue.self, from: datos)
            let codigo = c["codigo"] as! String
            if c["real"] as! Bool { #expect(CodigoBarras.normalizar(codigo) == codigo, "\(codigo) no es un código válido") }
            let l = CodigoBarras.leer(j, codigo: codigo)
            let obtenido = Self.json(l)
            #expect(NSDictionary(dictionary: obtenido).isEqual(to: c["esperado"] as! [String: Any]),
                    "\(c["caso"]!): \(obtenido) contra \(c["esperado"]!)")
            if case .encontrado(let p) = l {
                #expect(p.codigo == codigo)
                #expect(p.candidato.origen == .barras && p.candidato.codigo == codigo)
            }
        }
    }

    @Test func elEscaneadoVaALaHojaConSuPorcionYQuedaConElCodigo() {
        let p = CodigoBarras.Producto(codigo: "77916501", nombre: "Cereal Mix Original (Arcor)",
                                      por100: MacrosPor100(kcal: 402, p: 6.5, c: 66, g: 13), medida: "barra", gramosMedida: 23)
        let c = p.candidato
        #expect(AgregadosComida.medidas(c) == [.gramo, .init(nombre: "barra", gramos: 23)])
        let i = AgregadosComida.inicial(c)
        #expect(i.cantidad == 1 && i.medida.nombre == "barra")
        let a = AgregadosComida.agregado(c, cantidad: 2, medida: i.medida, ts: 1)
        #expect(a.gramos == 46 && a.kcal == 185 && a.origen == .barras && a.codigo == "77916501")
        // «porción» con su tilde (normalizada quedaba «porcion»), también para los propios por porción.
        let y = CodigoBarras.Producto(codigo: "7791337006355", nombre: "Yogur", por100: MacrosPor100(kcal: 82, p: 7, c: 6.3, g: 3.2),
                                      medida: "porción", gramosMedida: 200).candidato
        #expect(AgregadosComida.medidas(y).last == .init(nombre: "porción", gramos: 200))
        let propio = AgregadosComida.Candidato(nombre: "Pan", por100: MacrosPor100(kcal: 250, p: 9, c: 48, g: 3), unidad: "porcion",
                                               gramosPorUnidad: 30, origen: .propio)
        #expect(AgregadosComida.medidas(propio).last?.nombre == "porción")
    }

    /// El agregado con origen «barras» y su código va y vuelve; uno con un código roto conserva todo menos el código. Una
    /// 2.0.3 (que solo conoce base y propio) lo lee como «base»: no lo descarta.
    @Test func elAgregadoConCodigoVaYVuelve() throws {
        let p = MacrosPor100(kcal: 402, p: 6.5, c: 66, g: 13)
        let a = AlimentoAgregado(nombre: "Cereal Mix", cantidad: 1, unidad: "barra", gramosUnidad: 23, gramos: 23, kcal: 92, p: 1.5,
                                 c: 15.2, g: 3, por100: p, origen: .barras, ts: 5, codigo: "77916501")
        let datos = try JSONEncoder().encode(a)
        let j = try JSONDecoder().decode(JSONValue.self, from: datos)
        #expect(j["origen"] == .texto("barras") && j["codigo"] == .texto("77916501"))
        #expect(try JSONDecoder().decode(AlimentoAgregado.self, from: datos) == a)

        var o = try JSONSerialization.jsonObject(with: datos) as! [String: Any]
        o["codigo"] = "77a16501"
        let roto = try JSONDecoder().decode(AlimentoAgregado.self, from: JSONSerialization.data(withJSONObject: o))
        #expect(roto.codigo == nil && roto.kcal == 92)
        o["codigo"] = nil
        #expect(try JSONDecoder().decode(AlimentoAgregado.self, from: JSONSerialization.data(withJSONObject: o)).codigo == nil)

        // Lo que hace una 2.0.3 con un origen que no conoce (su decodificado: `try? decode(Origen) ?? .base`).
        enum Origen203: String, Decodable { case base, propio }
        struct Agregado203: Decodable {
            let origen: Origen203
            init(from d: Decoder) throws {
                let x = try d.container(keyedBy: CodingKeys.self)
                origen = (try? x.decode(Origen203.self, forKey: .origen)) ?? .base
            }
            enum CodingKeys: String, CodingKey { case origen }
        }
        #expect(try JSONDecoder().decode(Agregado203.self, from: datos).origen == .base)
    }

    @Test func laCacheVenceSegunLoQueEncontro() {
        let dia = CacheCodigos.diaMs
        let prod = CodigoBarras.Producto(codigo: "1", nombre: "X", por100: MacrosPor100(kcal: 1, p: 0, c: 0, g: 0), medida: nil, gramosMedida: nil)
        var c = CacheCodigos()
        c.guardar("a", .encontrado(prod), ahoraMs: 0)
        c.guardar("b", .noEncontrado, ahoraMs: 0)
        c.guardar("c", .incompleto(.init(codigo: "c", motivo: .faltanDatos)), ahoraMs: 0)
        #expect(c.vigente("a", ahoraMs: 29 * dia) == .encontrado(prod))
        #expect(c.vigente("a", ahoraMs: 30 * dia) == nil)
        #expect(c.vigente("b", ahoraMs: dia - 1) == .noEncontrado)
        #expect(c.vigente("b", ahoraMs: dia) == nil)
        #expect(c.vigente("c", ahoraMs: dia) == nil)
        #expect(c.vigente("a", ahoraMs: -1) == nil, "Un reloj que volvió atrás no da por vigente")
        #expect(c.vigente("z", ahoraMs: 0) == nil)

        // Un propio no vence ni lo pisa lo que diga Open Food Facts después.
        var propio = prod
        propio.propio = true
        c.guardar("p", .encontrado(propio), ahoraMs: 0)
        c.guardar("p", .noEncontrado, ahoraMs: 1)
        c.guardar("p", .encontrado(prod), ahoraMs: 1)
        #expect(c.vigente("p", ahoraMs: 3650 * dia) == .encontrado(propio))
    }

    @Test func laCacheTieneTopeYSeVanLasMasViejas() {
        var c = CacheCodigos()
        var propio = CodigoBarras.Producto(codigo: "p", nombre: "X", por100: MacrosPor100(kcal: 1, p: 0, c: 0, g: 0), medida: nil, gramosMedida: nil)
        propio.propio = true
        c.guardar("p", .encontrado(propio), ahoraMs: 0)
        for i in 1...(CacheCodigos.maximo + 5) { c.guardar("k\(i)", .noEncontrado, ahoraMs: Int64(i)) }
        #expect(c.entradas.count == CacheCodigos.maximo)
        #expect(c.entradas["p"] != nil, "El propio, el más viejo, queda")
        #expect(c.entradas["k1"] == nil && c.entradas["k5"] == nil && c.entradas["k6"] == nil)
        #expect(c.entradas["k7"] != nil)
    }

    @Test func elPedidoVaConLosCamposYElAgente() {
        #expect(CodigoBarras.url("7791337006355")?.absoluteString
            == "https://world.openfoodfacts.org/api/v2/product/7791337006355.json?fields=product_name,product_name_es,brands,nutriments,serving_size,serving_quantity,serving_quantity_unit,quantity")
        #expect(CodigoBarras.agenteUsuario(version: "2.1.0", plataforma: "iOS") == "PumpTeam/2.1.0 (iOS)")
    }

    @Test func losCamposSonLosDeLosVectores() throws {
        #expect(try Self.vectores["campos"] as? String == CodigoBarras.campos)
    }

    @Test func elNombreSeSaneaIgualQueEnAndroid() {
        #expect(CodigoBarras.limpio(.texto("Yogur <b>Natural</b><br/>")) == "Yogur Natural")
        #expect(CodigoBarras.limpio(.texto("Yogur\u{07}Natural\u{1F}\t\n")) == "Yogur Natural")
        #expect(CodigoBarras.limpio(.texto("\u{A0}Yogur\u{A0}\u{A0}Natural\u{2007}\u{202F}\u{2028}x")) == "Yogur Natural x")
        #expect(CodigoBarras.limpio(.texto("2 < 3 y 5 > 4")) == "2 < 3 y 5 > 4")
        #expect(CodigoBarras.limpio(nil) == "")
    }

    @Test func todoEnCeroTieneSuTextoYNoDiceQueNoCierra() {
        let t = CodigoBarras.Parcial(codigo: "1", motivo: .enCero).texto
        #expect(!t.contains("no cierran") && t.contains("todo en cero"))
    }

    @Test func elPropioBorradoOEditadoSeSueltaDeLaCache() {
        func propio(_ nombre: String, kcal: Double) -> CodigoBarras.Lectura {
            .encontrado(.init(codigo: "x", nombre: nombre, por100: MacrosPor100(kcal: kcal, p: 3, c: 5, g: 3), medida: "porcion",
                              gramosMedida: 200, propio: true))
        }
        var c = CacheCodigos()
        c.guardar("a", propio("Leche A", kcal: 60), ahoraMs: 0)
        c.guardar("b", propio("Leche B", kcal: 60), ahoraMs: 0)
        c.guardar("c", propio("Leche C", kcal: 60), ahoraMs: 0)
        c.guardar("o", .noEncontrado, ahoraMs: 0)
        func ap(_ n: String, _ kcal: Double?, unidad: String? = "porcion", g: Double? = 200) -> AlimentoPropio {
            AlimentoPropio(nombre: n, kcal: kcal, prot: 3, carb: 5, fat: 3, unidad: unidad, gramosPorUnidad: g, categoria: nil)
        }
        // A sigue igual (otro caso de letra), B se editó, C se borró.
        let r1 = c.conciliarPropios([ap("leche a", 60.04), ap("Leche B", 75)])
        #expect(r1)
        #expect(c.entradas["a"] != nil && c.entradas["b"] == nil && c.entradas["c"] == nil && c.entradas["o"] != nil)
        let r2 = c.conciliarPropios([ap("Leche A", 60)])
        #expect(!r2, "Sin cambios no suelta nada")
        let r3 = c.conciliarPropios([ap("Leche A", 60, g: 250)])
        #expect(r3, "Otra porción también es una edición")
        #expect(c.entradas["a"] == nil)
    }
}
