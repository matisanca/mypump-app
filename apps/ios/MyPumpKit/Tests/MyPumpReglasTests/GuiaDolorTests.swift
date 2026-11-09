import Foundation
import Testing
import MyPumpModelos
@testable import MyPumpReglas

/// «Lo que más te importa»: los mismos casos que Android (`apps/shared/fixtures/guia/dolor-casos.json`).
@Suite("Guía: lo que más te importa")
struct GuiaDolorTests {
    private static let raiz = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../../../shared/fixtures/guia").standardized

    private static func archivo(_ n: String) throws -> Data { try Data(contentsOf: raiz.appendingPathComponent(n)) }

    private func guia(_ n: String) throws -> Guia { Guia(json: try JSONDecoder().decode(JSONValue.self, from: try Self.archivo(n))) }

    private func guia(texto: String) -> Guia {
        Guia(json: (try? JSONDecoder().decode(JSONValue.self, from: Data(texto.utf8))) ?? .null)
    }

    private func clip(_ id: String, _ bloque: String?, visto: Bool = false, nuevo: Bool = false, duda: String? = nil) -> ClipGuia {
        ClipGuia(id: id, titulo: id, url: URL(string: "https://x.invalid/\(id).mp4"), minutos: 1, bloque: bloque, visto: visto, duda: duda, nuevo: nuevo)
    }

    struct Caso: Decodable {
        struct P: Decodable { let titulo: String; let parrafos: [String] }
        let nombre: String
        let titulo: String?
        let texto: String
        let subtitulo: String?
        let parrafos: [String]?
        let partes: [P]?
        let vacio: Bool?
    }

    @Test func losCasosCompartidos() throws {
        let casos = try JSONDecoder().decode([Caso].self, from: try Self.archivo("dolor-casos.json"))
        #expect(casos.count >= 15)
        for c in casos {
            let v = ReglasDolor.vista(DolorGuia(titulo: c.titulo, texto: c.texto))
            if c.vacio == true { #expect(v == nil, "\(c.nombre)"); continue }
            #expect(v?.subtitulo == c.subtitulo, "\(c.nombre)")
            #expect(v?.parrafos == c.parrafos, "\(c.nombre)")
            #expect(v?.partes.map(\.titulo) == c.partes?.map(\.titulo), "\(c.nombre)")
            #expect(v?.partes.map(\.parrafos) == c.partes?.map(\.parrafos), "\(c.nombre)")
        }
    }

    @Test func laRespuestaDeHoySigueIgual() throws {
        let g = try guia("get-tomas.json")
        #expect(g.ok)
        #expect(g.dolor == nil)
        #expect(ReglasDolor.vista(g.dolor) == nil)
        #expect(ReglasDolor.introduccion(g, hayDudas: false) == nil)
        let bloques = ReglasGuia.bloques(ReglasGuia.deLaLista(g))
        let r = ReglasDolor.reparto(bloques, nil)
        #expect(r.principal == nil && r.partes.isEmpty && r.resto == bloques)
    }

    @Test(arguments: [
        "{\"ok\":true,\"clips\":[],\"dolor\":null}",
        "{\"ok\":true,\"clips\":[],\"dolor\":{}}",
        "{\"ok\":true,\"clips\":[],\"dolor\":{\"titulo\":\"x\"}}",
        "{\"ok\":true,\"clips\":[],\"dolor\":{\"titulo\":\"x\",\"texto\":\"\"}}",
        "{\"ok\":true,\"clips\":[],\"dolor\":{\"titulo\":\"x\",\"texto\":null}}",
        "{\"ok\":true,\"clips\":[],\"dolor\":\"texto suelto\"}",
        "{\"ok\":true,\"clips\":[],\"dolor\":[1,2]}",
        "{\"ok\":true,\"clips\":[],\"dolor\":{\"texto\":{\"a\":1}}}",
    ])
    func dolorRaroNoRompe(_ json: String) {
        let g = guia(texto: json)
        #expect(g.ok)
        #expect(g.dolor == nil)
    }

    @Test func seGuardaEnLaCopia() throws {
        let g = try guia("get-tomas-dolor.json")
        #expect(g.dolor?.titulo == "Bajar la panza sin perder fuerza")
        let vuelta = try JSONDecoder().decode(Guia.self, from: try JSONEncoder().encode(g))
        #expect(vuelta == g)
    }

    @Test func unBloqueDelDolorSinTextoSigueEnLaLista() {
        let g = Guia(ok: true, clips: [clip("a", "Tu app"), clip("b", "Lo que más te importa")])
        #expect(ReglasGuia.deLaLista(g).map(\.id) == ["a", "b"])
    }

    @Test func losVideosDelDolorVanPrimeroYElResto() throws {
        let g = Guia(ok: true, clips: [clip("app", "Tu app"), clip("n", "Otro", nuevo: true), clip("otro", "Otro"), clip("plan", "Tu plan"), clip("d", "lo que mas te importa")],
                     dolor: DolorGuia(texto: "Uno.\n\n## Tu plan\n\nDos."))
        let lista = ReglasGuia.deLaLista(g)
        #expect(lista.map(\.id) == ["n", "d", "plan", "app", "otro"])
        let r = ReglasDolor.reparto(ReglasGuia.bloques(lista), ReglasDolor.vista(g.dolor))
        #expect(r.principal?.titulo == "lo que mas te importa")
        #expect(r.partes.map { $0?.titulo } == ["Tu plan"])
        #expect(r.resto.map(\.titulo) == ["Novedad", "Tu app", "Otro"])
    }

    @Test func dosPartesIgualesNoRepitenVideos() {
        let v = ReglasDolor.vista(DolorGuia(texto: "## Plan\n\nA.\n\n## Plan\n\nB."))
        let b = ReglasGuia.bloques([clip("p", "Plan")])
        let r = ReglasDolor.reparto(b, v)
        #expect(r.partes.count == 2)
        #expect(r.partes[0]?.titulo == "Plan")
        #expect(r.partes[1] == nil)
        #expect(r.resto.isEmpty)
    }

    @Test func introConFechaEnHoraArgentina() {
        // 02:00 UTC del jueves es miércoles 23:00 en Argentina.
        let g = Guia(ok: true, fechaEntrega: "2035-03-08T02:00:00Z", clips: [clip("a", "Otro")], dolor: DolorGuia(texto: "Uno."))
        let i = ReglasDolor.introduccion(g, hayDudas: false, ahora: Date(timeIntervalSince1970: 1_800_000_000))
        #expect(i?.texto == "Antes de nuestra videollamada del miércoles 7/3, hacé estos dos pasos.")
        #expect(i?.pasos.map(\.titulo) == ["Mirá tus videos", "Dejá tus dudas"])
        #expect(i?.pasos.map(\.estado) == [.ahora, .pendiente])
    }

    @Test func introSinFechaNoInventaNinguna() {
        let g = Guia(ok: true, fechaEntrega: nil, clips: [clip("a", "Otro", visto: true)], dolor: DolorGuia(texto: "Uno."))
        let i = ReglasDolor.introduccion(g, hayDudas: true)
        #expect(i?.texto == "Antes de nuestra videollamada, hacé estos dos pasos.")
        #expect(i?.pasos.map(\.estado) == [.hecho, .hecho])
    }

    @Test func introNoVaDespuesDeLaLlamadaNiSinDolor() {
        let ahora = Date(timeIntervalSince1970: 1_800_000_000)
        let paso = Guia(ok: true, fechaEntrega: "2020-01-01T10:00:00-03:00", dolor: DolorGuia(texto: "Uno."))
        #expect(ReglasDolor.introduccion(paso, hayDudas: false, ahora: ahora) == nil)
        let sin = Guia(ok: true, fechaEntrega: "2035-03-07T14:00:00-03:00")
        #expect(ReglasDolor.introduccion(sin, hayDudas: false, ahora: ahora) == nil)
    }

    @Test func textoHabladoDelPaso() {
        let p = ReglasDolor.Paso(id: "videos", numero: 1, titulo: "Mirá tus videos", estado: .hecho)
        #expect(ReglasDolor.textoHablado(p, de: 2) == "Paso 1 de 2, Mirá tus videos, hecho")
    }
}
