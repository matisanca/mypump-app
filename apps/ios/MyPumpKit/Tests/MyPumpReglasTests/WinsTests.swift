import Foundation
import Testing
@testable import MyPumpModelos
@testable import MyPumpReglas

/// «Récords y logros» (2.3.0) contra apps/shared/vectores/wins.json: los mismos casos y textos que leen Android y la web.
struct WinsTests {
    private static var vectores: JSONValue {
        let url = raizRepo.appendingPathComponent("apps/shared/vectores/wins.json")
        return (try? JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url))) ?? .null
    }
    private static func lista(_ j: JSONValue?) -> [JSONValue] { if case .lista(let l)? = j { return l }; return [] }
    private static func marcas(_ j: JSONValue?) -> [ReglasWins.Marca] {
        lista(j).map { ReglasWins.Marca(kg: $0["kg"]?.comoNumero ?? .nan, reps: Int($0["reps"]?.comoNumero ?? 0)) }
    }

    @Test func recordsDelDia() {
        let casos = Self.lista(Self.vectores["records"])
        #expect(casos.count >= 18)
        for c in casos {
            let nombre = c["nombre"]?.comoTexto ?? ""
            let entrada = Self.lista(c["ejercicios"]).map { e in
                ReglasWins.Ejercicio(clave: e["clave"]?.comoTexto ?? "", nombre: e["nombre"]?.comoTexto ?? "",
                                     anteriores: Self.marcas(e["anteriores"]), hoy: Self.marcas(e["hoy"]),
                                     sinKg: e["sin_kg"] == .bool(true), suficiente: e["suficiente"] != .bool(false))
            }
            let salida = ReglasWins.records(entrada)
            let esperada = Self.lista(c["salida"])
            #expect(salida.count == esperada.count, "\(nombre)")
            for (r, e) in zip(salida, esperada) {
                #expect(r.tipo.rawValue == e["tipo"]?.comoTexto, "\(nombre)")
                #expect(r.clave == e["clave"]?.comoTexto, "\(nombre)")
                #expect(r.ejercicio == e["ejercicio"]?.comoTexto, "\(nombre)")
                #expect(r.kg == e["kg"]?.comoNumero, "\(nombre)")
                #expect(Double(r.reps) == e["reps"]?.comoNumero, "\(nombre)")
                #expect(r.antesKg == e["antes_kg"]?.comoNumero, "\(nombre)")
                #expect(Double(r.antesReps) == e["antes_reps"]?.comoNumero, "\(nombre)")
                #expect(r.delta == e["delta"]?.comoNumero, "\(nombre)")
                #expect(r.marca == e["marca"]?.comoTexto, "\(nombre)")
                #expect(r.chip == e["chip"]?.comoTexto, "\(nombre)")
                #expect(r.antes == e["antes"]?.comoTexto, "\(nombre)")
            }
        }
        #expect(Self.vectores["tope"]?.comoNumero == Double(ReglasWins.tope))
    }

    @Test func textosPorCantidad() {
        let casos = Self.lista(Self.vectores["textos"])
        #expect(casos.count >= 4)
        for c in casos {
            let n = Int(c["n"]?.comoNumero ?? 0)
            #expect(ReglasWins.titulo(n) == c["titulo"]?.comoTexto)
            #expect(ReglasWins.subtitulo(n) == c["subtitulo"]?.comoTexto)
            #expect(ReglasWins.conPermiso(n) == c["con_permiso"]?.comoTexto)
        }
    }

    @Test func textosFijos() {
        let f = Self.vectores["fijos"]
        let pares: [(String, String)] = [
            ("contarle", ReglasWins.contarle), ("seguir", ReglasWins.seguir), ("permiso_titulo", ReglasWins.permisoTitulo),
            ("permiso_si", ReglasWins.permisoSi), ("permiso_no", ReglasWins.permisoNo), ("ajuste_seccion", ReglasWins.ajusteSeccion),
            ("ajuste_interruptor", ReglasWins.ajusteInterruptor), ("ajuste_pie", ReglasWins.ajustePie),
            ("desactivado", ReglasWins.desactivado), ("sin_red", ReglasWins.sinRed), ("demo", ReglasWins.demo),
            ("racha_con_permiso", ReglasWins.rachaConPermiso),
        ]
        for (k, v) in pares { #expect(f?[k]?.comoTexto == v, "\(k)") }
        // Ningún texto fijo del vector queda sin comparar.
        if case .objeto(let o)? = f { #expect(Set(o.keys) == Set(pares.map(\.0) + ["permiso_cuerpo"])) } else { Issue.record("sin fijos") }
        #expect(Self.lista(f?["permiso_cuerpo"]).compactMap(\.comoTexto) == ReglasWins.permisoCuerpo)
        #expect(Self.vectores["permiso_version"]?.comoNumero == Double(ReglasWins.permisoVersion))
    }

    @Test func hitosDeLaRacha() {
        #expect(Self.lista(Self.vectores["hitos_racha"]).compactMap(\.comoNumero).map { Int($0) } == ReglasWins.hitosRacha)
        let casos = Self.lista(Self.vectores["racha"])
        #expect(casos.count >= 18)
        for c in casos {
            let dias = Int(c["dias"]?.comoNumero ?? -1)
            #expect(ReglasWins.esHito(dias) == (c["es_hito"] == .bool(true)), "\(dias)")
        }
    }

    @Test func losDatosQueViajan() {
        let r = ReglasWins.records([ReglasWins.Ejercicio(clave: "remo con barra", nombre: "Remo con barra",
                                                          anteriores: [.init(kg: 55, reps: 8)], hoy: [.init(kg: 57.5, reps: 8)])])
        #expect(r.first?.datos == .objeto(["ejercicio": .texto("Remo con barra"), "kg": .numero(57.5), "reps": .numero(8),
                                           "antes_kg": .numero(55), "antes_reps": .numero(8)]))
        #expect(ReglasWins.datosRacha(dias: 7, meta: 9000) == .objeto(["dias": .numero(7), "meta": .numero(9000)]))
    }
}
