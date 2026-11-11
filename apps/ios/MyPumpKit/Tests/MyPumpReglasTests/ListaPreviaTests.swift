import Foundation
import Testing
@testable import MyPumpModelos
@testable import MyPumpReglas

/// La lista previa a la videollamada (2.3.0) contra apps/shared/vectores/lista_previa.json: los mismos casos y textos que
/// leen Android y la web.
struct ListaPreviaTests {
    private static var vectores: JSONValue {
        let url = raizRepo.appendingPathComponent("apps/shared/vectores/lista_previa.json")
        return (try? JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url))) ?? .null
    }
    private static func lista(_ j: JSONValue?) -> [JSONValue] { if case .lista(let l)? = j { return l }; return [] }

    @Test func todosLosCasos() {
        let casos = Self.lista(Self.vectores["casos"])
        #expect(casos.count >= 20)
        for c in casos {
            let nombre = c["nombre"]?.comoTexto ?? ""
            let v = ReglasListaPrevia.vista(c["respuesta"])
            guard let esperada = c["salida"], esperada != .null else {
                #expect(v == nil, "\(nombre)")
                continue
            }
            guard let v else { Issue.record("sin vista: \(nombre)"); continue }
            let items = Self.lista(esperada["items"])
            #expect(v.items.count == items.count, "\(nombre)")
            for (i, e) in zip(v.items, items) {
                #expect(i.clave == e["clave"]?.comoTexto, "\(nombre)")
                #expect(i.titulo == e["titulo"]?.comoTexto, "\(nombre)")
                #expect(i.hecho == (e["hecho"] == .bool(true)), "\(nombre)")
                #expect(i.opcional == (e["opcional"] == .bool(true)), "\(nombre)")
                #expect(i.detalle == e["detalle"]?.comoTexto, "\(nombre)")
                #expect(i.destino?.rawValue == e["destino"]?.comoTexto, "\(nombre)")
                #expect(i.accesible == e["accesible"]?.comoTexto, "\(nombre)")
            }
            #expect(v.resumen == esperada["resumen"]?.comoTexto, "\(nombre)")
            #expect(v.todoListo == (esperada["todo_listo"] == .bool(true)), "\(nombre)")
        }
    }

    @Test func textosTitulosYDestinos() {
        let t = Self.vectores["textos"]
        let pares: [(String, String)] = [("titulo", ReglasListaPrevia.titulo), ("todo_listo", ReglasListaPrevia.todoListo),
                                         ("consejo", ReglasListaPrevia.consejo), ("opcional", ReglasListaPrevia.opcional),
                                         ("hecho", ReglasListaPrevia.hecho), ("falta", ReglasListaPrevia.falta)]
        for (k, v) in pares { #expect(t?[k]?.comoTexto == v, "\(k)") }
        if case .objeto(let o)? = t { #expect(Set(o.keys) == Set(pares.map(\.0))) } else { Issue.record("sin textos") }
        if case .objeto(let o)? = Self.vectores["titulos"] {
            #expect(o.compactMapValues(\.comoTexto) == ReglasListaPrevia.titulos)
        } else { Issue.record("sin titulos") }
        if case .objeto(let o)? = Self.vectores["destinos"] {
            #expect(o.compactMapValues(\.comoTexto) == ReglasListaPrevia.destinos.mapValues(\.rawValue))
        } else { Issue.record("sin destinos") }
    }

    @Test func sinRespuestaNoHayNada() {
        #expect(ReglasListaPrevia.vista(nil) == nil)
        #expect(ReglasListaPrevia.vista(.null) == nil)
    }
}
