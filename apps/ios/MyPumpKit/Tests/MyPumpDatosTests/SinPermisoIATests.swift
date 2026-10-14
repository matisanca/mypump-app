import Foundation
import Testing
import MyPumpModelos
@testable import MyPumpDatos
@testable import MyPumpReglas

/// Sin permiso para la IA (D7 se sacó el 14-oct, decisión de Mati: la IA trabaja bajo su aprobación y no es algo que el
/// cliente acepte). La app no pregunta ni lee nada, un "no" que quedó guardado de la 101/102 no frena la foto, y lo que
/// quedó en una cola sale igual.
@Suite("Sin permiso para la IA", .serialized)
@MainActor
struct SinPermisoIATests {
    final class Estado: @unchecked Sendable {
        var conRed = true
        var llamadas: [String] = []
        var visiones = 0
    }

    func modelo(_ e: Estado, raiz: URL) -> ModeloApp {
        let t = TransporteProgramado { fn, _ in
            guard e.conRed else { throw URLError(.notConnectedToInternet) }
            e.llamadas.append(fn)
            switch fn {
            case "mypump_get_cliente_info": return (200, #"[{"cliente_id":"c1","nombre":"Cliente","perfil":"natural"}]"#)
            case "mypump_get_rutina_activa": return (200, #"[{"id":"r1","semana_actual":1,"estructura":{"dias":[]}}]"#)
            case "mypump_guardar_consentimiento_ia": return (200, "true")
            case "vision": e.visiones += 1; return (200, "{}")
            default: return (200, "[]")
            }
        }
        return ModeloApp(cliente: ClienteRPC(config: .produccion, transporte: t), almacen: TokenEnMemoria("AAAAAAAAAAAAAAAAAAAA"), raizDisco: raiz)
    }

    func raiz() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("sin-permiso-ia-\(UUID().uuidString)") }

    @Test func noSeLeePermisoYLaFotoSaleAunqueHayaQuedadoUnNo() async {
        let e = Estado()
        let r = raiz(); defer { try? FileManager.default.removeItem(at: r) }
        // Lo que dejaba la 101/102 en la carpeta de la cuenta al decir que no.
        let carpeta = Disco(raiz: r, token: "AAAAAAAAAAAAAAAAAAAA")
        carpeta.guardar(["acepta": false], "consentimiento-ia.json")
        let m = modelo(e, raiz: r)
        await m.cargar()
        #expect(m.fase == .listo)
        #expect(!e.llamadas.contains { $0.contains("consentimiento") }, "\(e.llamadas)")
        _ = await m.analizarFoto(Data([0xFF]), tipo: .plato)
        #expect(e.visiones == 1, "la foto no salió")
    }

    @Test func loQueQuedoEnLaColaSaleIgual() async {
        let e = Estado()
        let r = raiz(); defer { try? FileManager.default.removeItem(at: r) }
        let m = modelo(e, raiz: r)
        await m.cargar()
        _ = await m.outbox?.encolar("consentimiento_ia", .objeto(["acepta": .bool(false), "plataforma": .texto("ios")]),
                                    dedupeKey: "consentimiento_ia")
        await m.outbox?.drenar()
        #expect(await m.outbox?.operaciones.isEmpty == true, "quedó trabada en la cola")
        #expect(await m.outbox?.fallidos.isEmpty == true)
    }

    /// `cargasConRed`: lo que espera la Fase R para reintentar después de un corte (`ArranqueMigracion`). Recargar una
    /// cuenta ya cargada no pasa por `.cargando`, así que la fase sola no alcanzaba para darse cuenta.
    @Test func cadaCargaConRedSeCuenta() async {
        let e = Estado()
        let r = raiz(); defer { try? FileManager.default.removeItem(at: r) }
        let m = modelo(e, raiz: r)
        await m.cargar()
        #expect(m.cargasConRed == 1)
        await m.cargar()
        #expect(m.cargasConRed == 2)
        e.conRed = false
        await m.cargar()
        #expect(m.cargasConRed == 2)
    }
}
