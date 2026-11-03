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
            == "https://world.openfoodfacts.org/api/v2/product/7791337006355.json?fields=product_name,product_name_es,brands,nutriments,serving_size,serving_quantity,quantity")
        #expect(CodigoBarras.agenteUsuario(version: "2.1.0", plataforma: "iOS") == "PumpTeam/2.1.0 (iOS)")
    }
}
