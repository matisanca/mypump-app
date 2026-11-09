import Foundation
import Testing
import MyPumpModelos
@testable import MyPumpDatos

/// La subida de grabaciones del contador: nunca sin habilitación del servidor, idempotente, sin perder nada ante un fallo.
@Suite struct SubidaGrabacionesTests {
    let carpeta: URL = {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("subida-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }()
    nonisolated(unsafe) let defaults = UserDefaults(suiteName: "subida-\(UUID().uuidString)")!

    func archivo(_ sesion: String, _ contenido: String = "MPC1datos") -> URL {
        let u = carpeta.appendingPathComponent("calibracion-\(sesion).mpcal")
        try? Data(contenido.utf8).write(to: u)
        return u
    }

    func cliente(_ t: TransporteProgramado) -> ClienteRPC { ClienteRPC(config: .produccion, transporte: AdaptadorSubida(t)) }

    /// La subida va cruda y con cabeceras: acá se le muestra al doble como un cuerpo JSON, para escribir las reglas igual.
    final class AdaptadorSubida: Transporte, @unchecked Sendable {
        let t: TransporteProgramado
        init(_ t: TransporteProgramado) { self.t = t }
        func enviar(_ pedido: URLRequest) async throws -> (Data, URLResponse) {
            guard pedido.url?.lastPathComponent == "subir" else { return try await t.enviar(pedido) }
            var p = pedido
            let c: [String: JSONValue] = ["token": .texto(pedido.value(forHTTPHeaderField: "x-reps-token") ?? ""),
                                          "sesion": .texto(pedido.value(forHTTPHeaderField: "x-reps-sesion") ?? ""),
                                          "sha256": .texto(pedido.value(forHTTPHeaderField: "x-reps-sha256") ?? "")]
            p.httpBody = try JSONEncoder().encode(JSONValue.objeto(c))
            return try await t.enviar(p)
        }
    }

    /// El estado que contesta la RPC y lo que contesta el POST de subir.
    func transporte(estado: (Int, String) = (200, #"{"automatica":false,"acepta":true}"#), subir: (Int, String) = (200, #"{"ok":true}"#)) -> TransporteProgramado {
        TransporteProgramado { fn, _ in fn == "mypump_reps_estado" ? estado : subir }
    }

    func subir(_ t: TransporteProgramado, _ urls: [URL]) async -> Int {
        await SubidaGrabaciones(cliente: cliente(t), defaults: defaults).subirPendientes(token: "tok", archivos: { _ in urls })
    }

    @Test func sinLaRPCNoSubeNadaYNoRompe() async {
        let t = transporte(estado: (404, #"{"code":"PGRST202","message":"no existe"}"#))
        #expect(await subir(t, [archivo("2026-11-07-s6-a")]) == 0)
        #expect(!t.llamadas.contains("subir"))
        #expect(await cliente(t).estadoSubidaReps(token: "tok") == nil)
    }

    @Test func sinConsentimientoNoSube() async {
        for cuerpo in [#"{"automatica":false,"acepta":false}"#, #"{"automatica":false,"acepta":null}"#, "null"] {
            let t = transporte(estado: (200, cuerpo))
            #expect(await subir(t, [archivo("2026-11-07-s6-a")]) == 0, "\(cuerpo)")
            #expect(!t.llamadas.contains("subir"), "\(cuerpo)")
        }
    }

    @Test func laCuentaAutomaticaSubeSinConsentimiento() async {
        let t = transporte(estado: (200, #"{"automatica":true,"acepta":null}"#))
        #expect(await subir(t, [archivo("2026-11-07-s6-a")]) == 1)
    }

    @Test func noRepiteLoYaSubidoYSiLaSesionCrecioVuelveAMandar() async {
        let t = transporte()
        let u = archivo("2026-11-07-s6-a")
        #expect(await subir(t, [u]) == 1)
        #expect(await subir(t, [u]) == 0)
        #expect(t.llamadas.filter { $0 == "subir" }.count == 1)
        _ = archivo("2026-11-07-s6-a", "MPC1datos y una serie mas")
        #expect(await subir(t, [u]) == 1)
    }

    @Test func unFalloNoPierdeNadaYSeReintenta() async {
        let u = archivo("2026-11-07-s6-a")
        #expect(await subir(transporte(subir: (503, #"{"ok":false}"#)), [u]) == 0)
        #expect(FileManager.default.fileExists(atPath: u.path), "el archivo queda")
        #expect(await subir(transporte(), [u]) == 1, "la próxima vez sale")
    }

    @Test func unArchivoRechazadoNoFrenaALosDemas() async {
        let t = TransporteProgramado { fn, cuerpo in
            if fn == "mypump_reps_estado" { return (200, #"{"automatica":true,"acepta":null}"#) }
            return cuerpo["sesion"] == .texto("2026-11-07-s6-a") ? (400, #"{"ok":false}"#) : (200, #"{"ok":true}"#)
        }
        #expect(await subir(t, [archivo("2026-11-07-s6-a"), archivo("2026-11-08-s6-b")]) == 1)
    }

    @Test func revocadoEnElServidorNoSigueIntentando() async {
        let t = transporte(subir: (403, #"{"ok":false}"#))
        #expect(await subir(t, [archivo("2026-11-07-s6-a"), archivo("2026-11-08-s6-b")]) == 0)
        #expect(t.llamadas.filter { $0 == "subir" }.count == 1)
    }

    @Test func alRevocarSeOlvidaLoSubido() async {
        let t = transporte()
        let s = SubidaGrabaciones(cliente: cliente(t), defaults: defaults)
        let u = archivo("2026-11-07-s6-a")
        #expect(await s.subirPendientes(token: "tok", archivos: { _ in [u] }) == 1)
        await s.olvidarSubidas()
        #expect(await s.subirPendientes(token: "tok", archivos: { _ in [u] }) == 1)
    }

    /// Revocó mientras viajaba un archivo: al terminar no queda anotado como subido y corta lo que falta.
    @Test func revocarDuranteUnaSubidaNoDejaRecuerdos() async {
        nonisolated(unsafe) var s: SubidaGrabaciones?
        let t = TransporteProgramado { fn, _ in
            if fn == "mypump_reps_estado" { return (200, #"{"automatica":true,"acepta":null}"#) }
            await s?.olvidarSubidas()
            return (200, #"{"ok":true}"#)
        }
        s = SubidaGrabaciones(cliente: cliente(t), defaults: defaults)
        let urls = [archivo("2026-11-07-s6-a"), archivo("2026-11-08-s6-b")]
        #expect(await s!.subirPendientes(token: "tok", archivos: { _ in urls }) == 0)
        #expect(t.llamadas.filter { $0 == "subir" }.count == 1)
        #expect(defaults.stringArray(forKey: SubidaGrabaciones.claveSubidas) == nil)
    }

    @Test func alVerRevocadoEnElServidorOlvidaLoSubido() async {
        let u = archivo("2026-11-07-s6-a")
        #expect(await subir(transporte(), [u]) == 1)
        #expect(await subir(transporte(estado: (200, #"{"automatica":false,"acepta":false}"#)), [u]) == 0)
        #expect(defaults.stringArray(forKey: SubidaGrabaciones.claveSubidas) == nil)
    }

    @Test func unArchivoDeMasNoSeMandaYNoFrena() async {
        let t = transporte()
        let grande = carpeta.appendingPathComponent("calibracion-2026-11-07-s6-a.mpcal")
        try? Data(count: SubidaGrabaciones.topeBytes + 1).write(to: grande)
        #expect(await subir(t, [grande, archivo("2026-11-08-s6-b")]) == 1)
        #expect(t.llamadas.filter { $0 == "subir" }.count == 1)
    }

    @Test func soloConElTokenYSinCuentaEnElCuerpo() async {
        nonisolated(unsafe) var visto: JSONValue?
        let t = TransporteProgramado { fn, cuerpo in
            if fn == "mypump_reps_estado" { return (200, #"{"automatica":true,"acepta":null}"#) }
            visto = cuerpo
            return (200, #"{"ok":true}"#)
        }
        #expect(await subir(t, [archivo("2026-11-07-s6-a")]) == 1)
        #expect(visto?["token"] == .texto("tok"))
        #expect(visto?["cliente_id"] == nil)
        if case .texto(let h)? = visto?["sha256"] { #expect(h.count == 64) } else { Issue.record("sin hash") }
    }

    /// Un iPhone con dos cuentas: cada una sube solo lo suyo y lo viejo sin marca solo la automática.
    @Test func nuncaLoDeOtraCuenta() {
        let urls = ["a", "b", "viejo"].map { URL(fileURLWithPath: "/x/calibracion-\($0).mpcal") }
        let marcas = ["calibracion-a.mpcal": "yo", "calibracion-b.mpcal": "otra"]
        func nombres(_ e: EstadoSubidaReps, prendidas: [String]) -> [String] {
            SubidaGrabaciones.deLaCuenta(urls, cuenta: "yo", marcas: marcas, prendidas: prendidas, estado: e).map(\.lastPathComponent)
        }
        #expect(nombres(.init(acepta: true), prendidas: ["yo"]) == ["calibracion-a.mpcal"])
        #expect(nombres(.init(automatica: true), prendidas: ["yo"]) == ["calibracion-a.mpcal"], "sin la habilitación del servidor, lo viejo no")
        #expect(nombres(.init(automatica: true, adoptarSinMarca: true), prendidas: ["yo"]) == ["calibracion-a.mpcal", "calibracion-viejo.mpcal"])
        #expect(nombres(.init(automatica: true, adoptarSinMarca: true), prendidas: ["yo", "otra"]) == ["calibracion-a.mpcal"])
        #expect(nombres(.init(automatica: true, adoptarSinMarca: true), prendidas: []) == ["calibracion-a.mpcal"], "si no se sabe quién grabó, tampoco")
    }

    /// El token nunca en la URL; el cuerpo es el archivo tal cual, con su largo.
    @Test func laSubidaVaCrudaConElTokenEnCabecera() async {
        final class Mira: Transporte, @unchecked Sendable {
            nonisolated(unsafe) var visto: URLRequest?
            func enviar(_ pedido: URLRequest) async throws -> (Data, URLResponse) {
                visto = pedido
                return (Data(#"{"ok":true}"#.utf8), HTTPURLResponse(url: pedido.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            }
        }
        let m = Mira()
        let datos = Data("MPC1datos".utf8)
        #expect(await ClienteRPC(config: .produccion, transporte: m).subirGrabacion(token: "tok", sesion: "s-1", sha256: "ab", datos: datos) == .hecho)
        #expect(m.visto?.httpBody == datos)
        #expect(m.visto?.value(forHTTPHeaderField: "x-reps-token") == "tok")
        #expect(m.visto?.value(forHTTPHeaderField: "Content-Length") == String(datos.count))
        #expect(m.visto?.url?.absoluteString.contains("tok") == false)
    }

    @Test func elNombreDebeSerDeUnaSesion() {
        #expect(SubidaGrabaciones.sesion(deArchivo: URL(fileURLWithPath: "/x/calibracion-2026-11-07-s6-c7ae9e.mpcal")) == "2026-11-07-s6-c7ae9e")
        #expect(SubidaGrabaciones.sesion(deArchivo: URL(fileURLWithPath: "/x/otra.mpcal")) == nil)
        #expect(SubidaGrabaciones.sesion(deArchivo: URL(fileURLWithPath: "/x/calibracion-a b.mpcal")) == nil)
    }

    @Test func consentimientoSoloConfirmaSiElServidorLoGuardo() async {
        #expect(await cliente(transporte()).guardarConsentimientoReps(token: "t", acepta: true, plataforma: "ios", app: "2.3") == true)
        #expect(await cliente(transporte(subir: (502, #"{"ok":false}"#))).guardarConsentimientoReps(token: "t", acepta: false, plataforma: "ios", app: nil) == false)
    }
}
