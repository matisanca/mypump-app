import Foundation
import Testing
import MyPumpModelos
import MyPumpReglas
@testable import MyPumpDatos

/// Lo encontró el agente de los hallazgos menores (15-oct): con el link vencido o regenerado, `progreso/upload` contesta
/// 403 «token inválido» y la foto se borraba como un rechazo definitivo (la web también la perdía). Ahora queda guardada y
/// la adopta la cuenta del link nuevo de la misma persona.
@Suite("Fotos con el token caído", .serialized)
@MainActor
struct FotosTokenCaidoTests {
    let raiz = FileManager.default.temporaryDirectory.appendingPathComponent("fotos-token-\(UUID().uuidString)")
    static let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10])

    @Test func unTokenCaidoNoBorraLaFotoNiGastaIntentos() async {
        let g = Guion()
        g.respuestas = [(403, #"{"ok":false,"error":"token inválido"}"#), (403, #"{"ok":false,"error":"token inválido"}"#)]
        let f = ModeloFotos(cliente: ClienteRPC(config: .produccion, transporte: g), token: "AAAAAAAAAAAAAAAAAAAA",
                            disco: Disco(raiz: raiz, token: "AAAAAAAAAAAAAAAAAAAA"))
        #expect(await f.subir(pose: "frente", jpeg: Self.jpeg) == .tokenCaido)
        #expect(f.pendientes.count == 1, "se borraba como un rechazo")
        await f.drenar()
        #expect(f.pendientes.count == 1 && f.pendientes.values.first?.intentos == 0)
    }

    @Test func unRechazoQueNoEsDelTokenSiLaDescarta() async {
        let g = Guion()
        g.respuestas = [(400, #"{"ok":false,"error":"fecha fuera de la ventana"}"#)]
        let f = ModeloFotos(cliente: ClienteRPC(config: .produccion, transporte: g), token: "AAAAAAAAAAAAAAAAAAAA",
                            disco: Disco(raiz: raiz, token: "AAAAAAAAAAAAAAAAAAAA"))
        #expect(await f.subir(pose: "frente", jpeg: Self.jpeg) == .rechazada("fecha fuera de la ventana"))
        #expect(f.pendientes.isEmpty)
    }

    @Test func elLinkNuevoDeLaMismaPersonaSeLlevaLasFotos() async throws {
        let viejo = "VIEJOVIEJOVIEJOVIEJO", nuevo = "NUEVONUEVONUEVONUEVO"
        // La carpeta del link viejo: de c1, con una foto que no llegó a subirse.
        let carpetaVieja = Disco(raiz: raiz, token: viejo)
        CuentasDelTelefono.anotar(clienteId: "c1", en: carpetaVieja)
        let hoy = FechaLocal.hoy()
        carpetaVieja.guardar(["\(FotosProgreso.lunes(hoy))|perfil": FotoPendiente(pose: "perfil", fecha: hoy, dataUrl: "data:image/jpeg;base64,AAAA")],
                             FotoPendiente.archivo)
        let subidas = Tokens()
        let t = TransporteProgramado { fn, cuerpo in
            switch fn {
            case "mypump_get_cliente_info": return (200, #"[{"cliente_id":"c1","nombre":"Cliente","perfil":"natural"}]"#)
            case "upload": subidas.anotar(cuerpo["token"]?.comoTexto ?? "?"); return (200, #"{"ok":true}"#)
            default: return (200, "[]")
            }
        }
        let m = ModeloApp(cliente: ClienteRPC(config: .produccion, transporte: t), almacen: TokenEnMemoria(nuevo), raizDisco: raiz)
        await m.cargar()
        await m.fotos?.drenar()
        #expect(subidas.lista == [nuevo], "la foto del link viejo no salió con el nuevo")
        #expect(carpetaVieja.leer([String: FotoPendiente].self, FotoPendiente.archivo) == nil)
    }

    @Test func deOtraPersonaNoSeAdopta() async throws {
        let carpetaAjena = Disco(raiz: raiz, token: "AJENOAJENOAJENOAJENO")
        CuentasDelTelefono.anotar(clienteId: "otra", en: carpetaAjena)
        let hoy = FechaLocal.hoy()
        carpetaAjena.guardar(["\(FotosProgreso.lunes(hoy))|perfil": FotoPendiente(pose: "perfil", fecha: hoy, dataUrl: "data:image/jpeg;base64,AAAA")],
                             FotoPendiente.archivo)
        let subidas = Tokens()
        let t = TransporteProgramado { fn, cuerpo in
            switch fn {
            case "mypump_get_cliente_info": return (200, #"[{"cliente_id":"c1","nombre":"Cliente","perfil":"natural"}]"#)
            case "upload": subidas.anotar(cuerpo["token"]?.comoTexto ?? "?"); return (200, #"{"ok":true}"#)
            default: return (200, "[]")
            }
        }
        let m = ModeloApp(cliente: ClienteRPC(config: .produccion, transporte: t), almacen: TokenEnMemoria("NUEVONUEVONUEVONUEVO"), raizDisco: raiz)
        await m.cargar()
        #expect(subidas.lista.isEmpty)
        #expect(carpetaAjena.leer([String: FotoPendiente].self, FotoPendiente.archivo)?.count == 1)
    }
}

final class Tokens: @unchecked Sendable {
    private let lock = NSLock()
    private var _lista: [String] = []
    var lista: [String] { lock.withLock { _lista } }
    func anotar(_ t: String) { lock.withLock { _lista.append(t) } }
}
