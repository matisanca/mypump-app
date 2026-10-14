import Foundation
import Testing
import MyPumpModelos
@testable import MyPumpDatos
@testable import MyPumpReglas

/// La `nativa_001` del lado de la app: el recibo, los conteos y la palanca remota. Antes de que se aplique en la base,
/// la app tiene que seguir igual que hoy (PGRST202). Después tiene que confirmar el recibo, reenviar lo que quedó en el
/// disco y respetar la palanca.
@Suite("Recibo, conteos y palanca remota (nativa_001)")
struct ServidorMigracionTests {
    let carpeta = FileManager.default.temporaryDirectory.appendingPathComponent("recibos-\(UUID().uuidString)")
    static let noExiste = (404, #"{"code":"PGRST202","message":"Could not find the function"}"#)

    func recibo(_ corrida: Int, cliente: String = "c1") -> ReciboLegado {
        ReciboLegado(migracion: "0b5c6c1e-0000-4000-8000-000000000001", corrida: corrida, fecha: "2026-10-14T12:00:00Z",
                     plataforma: "ios", app: "2.0.0", antes: ConteosLegado(), despues: ConteosNativos(), cliente: cliente)
    }

    func cliente(_ responder: @escaping @Sendable (String, JSONValue) throws -> (Int, String)) -> (ClienteRPC, TransporteProgramado) {
        let t = TransporteProgramado { fn, cuerpo in try responder(fn, cuerpo) }
        return (ClienteRPC(config: .produccion, transporte: t), t)
    }

    func esta(_ corrida: Int, en sub: String? = nil) -> Bool {
        let base = sub.map { carpeta.appendingPathComponent($0) } ?? carpeta
        return FileManager.default.fileExists(atPath: base.appendingPathComponent("recibo-\(corrida).json").path)
    }

    @Test func confirmadoPasaAEnviados() async {
        defer { try? FileManager.default.removeItem(at: carpeta) }
        let (c, t) = cliente { _, cuerpo in
            cuerpo["p_recibo"]?["cliente"] == .texto("c1") && cuerpo["p_corrida"] == .numero(0) ? (200, "true") : (400, "{}")
        }
        #expect(await ReciboEnServidor(cliente: c, carpeta: carpeta).enviar(recibo(0), token: "tok") == .confirmado)
        #expect(t.llamadas == ["mypump_registrar_migracion_nativa"])
        #expect(esta(0, en: "enviados") && !esta(0))
    }

    @Test func sinLaRPCQuedaEnElDiscoYSeReenviaCuandoExiste() async {
        defer { try? FileManager.default.removeItem(at: carpeta) }
        let (antes, _) = cliente { _, _ in Self.noExiste }
        #expect(await ReciboEnServidor(cliente: antes, carpeta: carpeta).enviar(recibo(0), token: "tok") == .soloLocal)
        #expect(esta(0))
        #expect(await ReciboEnServidor.reenviar(carpeta: carpeta, token: "tok", clienteId: "c1", cliente: antes) == 0)
        #expect(esta(0))
        let (despues, _) = cliente { _, _ in (200, "true") }
        #expect(await ReciboEnServidor.reenviar(carpeta: carpeta, token: "tok", clienteId: "c1", cliente: despues) == 1)
        #expect(esta(0, en: "enviados") && !esta(0))
        #expect(!ReciboEnServidor.hayPendientes(carpeta: carpeta))
    }

    @Test func rechazadoNoSeInsiste() async {
        defer { try? FileManager.default.removeItem(at: carpeta) }
        let (c, _) = cliente { _, _ in (200, "false") }
        #expect(await ReciboEnServidor(cliente: c, carpeta: carpeta).enviar(recibo(0), token: "tok") == .soloLocal)
        #expect(esta(0, en: "rechazados") && !esta(0))
        let (mal, _) = cliente { _, _ in (400, #"{"code":"22023","message":"recibo inválido"}"#) }
        #expect(await ReciboEnServidor(cliente: mal, carpeta: carpeta).enviar(recibo(1), token: "tok") == .soloLocal)
        #expect(esta(1, en: "rechazados"))
    }

    @Test func tokenCaidoOSinRedSeReintenta() async {
        defer { try? FileManager.default.removeItem(at: carpeta) }
        let (caido, _) = cliente { _, _ in (200, "null") }
        #expect(await ReciboEnServidor(cliente: caido, carpeta: carpeta).enviar(recibo(0), token: "tok") == .soloLocal)
        let (sinRed, _) = cliente { _, _ in throw URLError(.notConnectedToInternet) }
        #expect(await ReciboEnServidor(cliente: sinRed, carpeta: carpeta).enviar(recibo(1), token: "tok") == .soloLocal)
        #expect(esta(0) && esta(1))
    }

    @Test func elReenvioSoloMandaLosDeEsaCuenta() async {
        defer { try? FileManager.default.removeItem(at: carpeta) }
        let (sin, _) = cliente { _, _ in Self.noExiste }
        for (corrida, cuenta) in [(0, "c1"), (1, "c1"), (2, "c2")] {
            _ = await ReciboEnServidor(cliente: sin, carpeta: carpeta).enviar(recibo(corrida, cliente: cuenta), token: "tok")
        }
        let (c, t) = cliente { _, _ in (200, "true") }
        #expect(await ReciboEnServidor.reenviar(carpeta: carpeta, token: "tok", clienteId: "c1", cliente: c) == 2)
        #expect(t.llamadas.count == 2)
        #expect(esta(2) && esta(0, en: "enviados") && esta(1, en: "enviados"))
    }

    @Test func conteos() async {
        let (c, _) = cliente { _, _ in (200, #"{"sesiones":12,"registros_carga":340,"peso_manual":0}"#) }
        #expect(await ConteosRPC(cliente: c).contar(token: "tok") == ["sesiones": 12, "registros_carga": 340, "peso_manual": 0])
        let (caido, _) = cliente { _, _ in (200, "null") }
        #expect(await ConteosRPC(cliente: caido).contar(token: "tok") == nil)
        let (sin, _) = cliente { _, _ in Self.noExiste }
        #expect(await ConteosRPC(cliente: sin).contar(token: "tok") == nil)
    }

    @Test func palanca() async {
        let (c, t) = cliente { _, _ in
            (200, #"{"migracion_ops_legadas":false,"migracion_escritura_vuelta":true,"anclaje_borra_swaps":false,"version_minima_ios":"2.0.3","version_minima_android":null}"#)
        }
        let p = await PalancaRemota.leer(c)
        #expect(t.llamadas == ["mypump_get_app_config"])
        #expect(p?.opsLegadas == false && p?.escrituraVuelta == true && p?.anclajeBorraSwaps == false)
        #expect(p?.versionMinimaIOS == "2.0.3" && p?.versionMinimaAndroid == nil)
        let (sin, _) = cliente { _, _ in Self.noExiste }
        #expect(await PalancaRemota.leer(sin) == .deFabrica)
        let (sinRed, _) = cliente { _, _ in throw URLError(.timedOut) }
        #expect(await PalancaRemota.leer(sinRed) == nil)
        let (raro, _) = cliente { _, _ in (200, #"{"migracion_ops_legadas":"no","version_minima_ios":3}"#) }
        #expect(await PalancaRemota.leer(raro) == .deFabrica)   // un valor de otro tipo no cuenta
    }

    @Test func versionMinima() {
        #expect(PalancaRemota.debajo("2.0.0", de: "2.0.3"))
        #expect(PalancaRemota.debajo("2.0.9", de: "2.0.10"))
        #expect(!PalancaRemota.debajo("2.0.10", de: "2.0.9"))
        #expect(!PalancaRemota.debajo("2.0.3", de: "2.0.3"))
        #expect(!PalancaRemota.debajo("2.1", de: "2.0.3"))
        #expect(!PalancaRemota.debajo("2.0.0", de: nil))
        #expect(!PalancaRemota.debajo(nil, de: "2.0.3"))
    }

    @MainActor @Test func elModeloLeeLaPalancaAlCargar() async {
        let raiz = FileManager.default.temporaryDirectory.appendingPathComponent("palanca-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: raiz) }
        let t = TransporteProgramado { fn, _ in
            switch fn {
            case "mypump_get_cliente_info": return (200, #"[{"cliente_id":"c1","nombre":"Cliente","perfil":"natural"}]"#)
            case "mypump_get_app_config": return (200, #"{"anclaje_borra_swaps":false}"#)
            default: return (200, "[]")
            }
        }
        let m = ModeloApp(cliente: ClienteRPC(config: .produccion, transporte: t), almacen: TokenEnMemoria("AAAAAAAAAAAAAAAAAAAA"), raizDisco: raiz)
        await m.cargar()
        #expect(m.fase == .listo)
        #expect(m.palanca.anclajeBorraSwaps == false && m.palanca.opsLegadas)
    }
}
