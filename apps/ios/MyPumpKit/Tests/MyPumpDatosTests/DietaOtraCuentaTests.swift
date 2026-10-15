import Foundation
import Testing
import MyPumpModelos
@testable import MyPumpDatos

/// Como el hallazgo 10 (15-oct), en las comidas libres y los alimentos propios: una respuesta que llega después de que
/// entró el link de otra persona no se aplica a la cuenta nueva (lo encontró el agente que portó los menores a Android).
@Suite("Dieta: lo que vuelve tarde no se mezcla con otra cuenta", .serialized)
@MainActor
struct DietaOtraCuentaTests {
    let raiz = FileManager.default.temporaryDirectory.appendingPathComponent("dieta-otra-cuenta-\(UUID().uuidString)")
    nonisolated static let a = "AAAAAAAAAAAAAAAAAAAA"
    nonisolated static let b = "BBBBBBBBBBBBBBBBBBBB"

    nonisolated static func comida(_ id: String) -> String {
        #"{"id":"\#(id)","fecha":"2026-10-15","descripcion":"\#(id)","kcal":100,"prot":1,"carb":1,"fat":1}"#
    }

    func modelo(_ borrarFalla: Bool = false) -> ModeloApp {
        let t = TransporteProgramado { fn, cuerpo in
            let tok = cuerpo["p_token"]?.comoTexto
            switch fn {
            case "mypump_get_cliente_info":
                return (200, #"[{"cliente_id":"\#(tok == Self.a ? "ca" : "cb")","nombre":"Cliente","perfil":"natural"}]"#)
            case "mypump_get_comidas_libres":
                if tok == Self.a, cuerpo["p_fecha"] != nil {
                    try await Task.sleep(for: .milliseconds(200))   // la de A llega tarde
                    return (200, "[" + Self.comida("de-a") + "]")
                }
                return (200, "[" + Self.comida("de-b") + "]")
            case "mypump_borrar_comida_libre":
                try await Task.sleep(for: .milliseconds(200))
                return borrarFalla ? (500, #"{"message":"caído"}"#) : (200, "true")
            default:
                return (200, "[]")
            }
        }
        return ModeloApp(cliente: ClienteRPC(config: .produccion, transporte: t), almacen: TokenEnMemoria(Self.a), raizDisco: raiz)
    }

    @Test func lasComidasDeLaCuentaAnteriorNoPisanLasDeLaNueva() async {
        let m = modelo()
        await m.cargar()
        async let tarde: Void = m.cargarComidasLibres()   // la de A, que tarda
        try? await Task.sleep(for: .milliseconds(20))
        #expect(await m.entrar(con: "https://app.mypumpteam.com/?t=\(Self.b)"))
        await tarde
        #expect(m.comidasLibres.map(\.id) == ["de-b"], "quedaron las comidas de la cuenta anterior")
    }

    @Test func unBorradoQueFallaNoVuelveAPonerLasDeLaCuentaAnterior() async {
        let m = modelo(true)
        await m.cargar()
        try? await Task.sleep(for: .milliseconds(300))   // que termine la carga lenta de A
        let id = m.comidasLibres.first?.id ?? "de-a"
        async let borrado = m.borrarComidaLibre(id)
        try? await Task.sleep(for: .milliseconds(20))
        #expect(await m.entrar(con: "https://app.mypumpteam.com/?t=\(Self.b)"))
        #expect(await borrado == false)
        #expect(m.comidasLibres.map(\.id) == ["de-b"], "el borrado que falló volvió a poner las de A")
    }
}
