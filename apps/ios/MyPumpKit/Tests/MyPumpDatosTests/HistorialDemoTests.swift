import Foundation
import Testing
import MyPumpModelos
import MyPumpReglas
@testable import MyPumpDatos

private let raizRepo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

/// La demo con historial (2.3.0): `apps/shared/demo/historial.json` con las fechas relativas a hoy, lo que ven Progreso,
/// Entreno, el Pump del día, el chat, la devolución y la lista previa. Sin red y sin escribir nada.
@MainActor
struct HistorialDemoTests {
    private static func archivo(_ nombre: String) throws -> Data {
        try Data(contentsOf: raizRepo.appendingPathComponent("apps/shared/demo/\(nombre).json"))
    }
    private var zona: TimeZone { TimeZone(identifier: "America/Argentina/Buenos_Aires")! }
    /// Un martes a las 16:30 de Buenos Aires.
    private var ahora: Date { FechaJS.leer("2026-11-10T16:30:00-03:00")! }

    /// Un transporte que falla la prueba si alguien lo usa.
    private final class Espia: Transporte, @unchecked Sendable {
        private let lock = NSLock()
        private var n = 0
        var pedidos: Int { lock.withLock { n } }
        func enviar(_ pedido: URLRequest) async throws -> (Data, URLResponse) {
            lock.withLock { n += 1 }
            throw URLError(.notConnectedToInternet)
        }
    }

    @Test func lasFechasSonRelativasAHoy() throws {
        let h = try #require(HistorialDemo(json: Self.archivo("historial"), ahora: ahora, zona: zona))
        let remo = try #require(h.porClave["remo con barra"])
        // Del más nuevo al más viejo; la última sesión del día 1 fue hace 5 días a las 18:40, una serie cada 3 minutos.
        #expect(remo.first?.registradoEn == "2026-11-05T18:40:00-03:00")
        #expect(remo.prefix(4).map(\.serie) == [1, 2, 3, 4])
        #expect(remo[1].registradoEn == "2026-11-05T18:43:00-03:00")
        #expect(HistorialEntreno.fechaLocal(remo.last?.registradoEn, zona: zona) == "2026-09-17")
        #expect(remo.allSatisfy { $0.clave == "remo con barra" && ($0.pesoKg ?? 0) >= 50 && ($0.reps ?? 0) >= 1 && $0.rir == nil })
        // Hoy no hay sesión, y otro día es otra fecha.
        #expect(h.historial.allSatisfy { HistorialEntreno.fechaLocal($0.registradoEn, zona: zona) < "2026-11-10" })
        let manana = try #require(HistorialDemo(json: Self.archivo("historial"), ahora: ahora.addingTimeInterval(86_400), zona: zona))
        #expect(manana.porClave["remo con barra"]?.first?.registradoEn == "2026-11-06T18:40:00-03:00")
        #expect(h.porClave.count == 11)
    }

    @Test func pesoPasosYMetas() throws {
        let h = try #require(HistorialDemo(json: Self.archivo("historial"), ahora: ahora, zona: zona))
        let peso = PesoCorporal.serie(h.salud)
        #expect(peso.count == 32)
        #expect(peso.first?.fecha == "2026-09-15" && peso.first?.kg == 84.5)
        #expect(peso.allSatisfy { $0.fecha <= "2026-11-10" })
        let pasos = PumpDelDia.pasosPorDia(h.salud)
        #expect(pasos["2026-11-10"] == 6240)
        #expect(h.metas == MetasPlan(metaPasos: 9000, ritmoKgSemana: -0.4))
        let v = try #require(PumpDelDia.vista(pasosPorDia: pasos, meta: 9000, hoy: "2026-11-10"))
        #expect(v.pasosHoy == 6240 && !v.cumplido && v.racha >= 2)
    }

    @Test func chatDevolucionesYListaPrevia() throws {
        let h = try #require(HistorialDemo(json: Self.archivo("historial"), ahora: ahora, zona: zona))
        #expect(h.chat.count == 10)
        #expect(h.chat.first?.esDelCoach == true && h.chat.first?.contenido == "Buenas, cómo arrancaste la semana?")
        #expect(h.chat.first?.createdAt == "2026-10-29T10:15:00-03:00")
        #expect(h.chat.map(\.createdAt) == h.chat.map(\.createdAt).sorted())
        #expect(Set(h.chat.map(\.id)).count == 10)
        // `semanas_atras: 1` = el lunes de la semana pasada (hoy es martes 10: el lunes 2).
        let d = try #require(h.devoluciones)
        #expect(d.devoluciones.map(\.semanaLunes) == ["2026-11-02", "2026-10-26", "2026-10-19"])
        #expect(d.ultima?.lineas.count == 3 && d.ultima?.lineas.first == "Muy buena semana. Entrenaste los tres días y subiste la sentadilla.")
        #expect(d.ultima?.publicadaDia == "2026-11-09")
        #expect(ReglasListaPrevia.vista(h.listaPrevia)?.resumen == "Llevás 1 de 3")
    }

    @Test func unArchivoRotoNoRompeLaDemo() {
        #expect(HistorialDemo(json: Data("no es json".utf8)) == nil)
        #expect(HistorialDemo(json: Data("[1,2]".utf8)) == nil)
        let vacio = HistorialDemo(json: Data(#"{"entreno": "x", "peso": [{"dia": "hoy"}], "chat": [3]}"#.utf8))
        #expect(vacio?.porClave.isEmpty == true && vacio?.salud.isEmpty == true && vacio?.chat.isEmpty == true)
        #expect(vacio?.metas == nil && vacio?.devoluciones == nil && vacio?.listaPrevia == nil)
    }

    @Test func laDemoMuestraElHistorialSinRedYSinEscribir() async throws {
        let espia = Espia()
        let raiz = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let m = ModeloApp(cliente: ClienteRPC(config: .produccion, transporte: espia), almacen: TokenEnMemoria(nil), raizDisco: raiz)
        m.entrarEnDemo(rutina: try Self.archivo("rutina"), dieta: try Self.archivo("dieta"), historial: try Self.archivo("historial"))
        #expect(m.esDemo && m.demoHistorial != nil)
        let e = try #require(m.entreno)
        await e.cargar()
        await e.precargarHistorial()
        // «Última vez» y «récord a superar» en Entreno, del historial de la demo.
        let lugar = try #require(e.dia.lista.first { $0.tipo != "calentamiento" })
        await e.pedirHistorial(lugar.id)
        let t = try #require(e.tarjeta(lugar.id))
        #expect(t.record != nil && t.ultimaVez != nil)
        // Progreso: una tarjeta por ejercicio, con su récord.
        let filas = try #require(m.demoHistorial?.porClave[ClaveEjercicio.de(lugar.nombre)])
        #expect((ProgresoEjercicio.resumen(filas)?.tope ?? 0) > 0)
        // Pump del día y ritmo de peso, sin palanca.
        #expect(m.metas?.metaPasos == 9000 && m.metas?.ritmoKgSemana == -0.4)
        let p = try #require(m.pumpDelDia())
        #expect(p.conectado && p.vista.pasosHoy == 6240 && p.vista.meta == 9000)
        // La lista previa de la demo, como tarjeta propia.
        #expect(m.listaPrevia?.vista?.items.count == 4)
        #expect(m.wins == nil && m.devolucion == nil && m.chat == nil)
        // Cargar más kg que la última vez: récord, y al cerrar hay festejo. Nada viaja.
        let ultimo = try #require(filas.compactMap(\.pesoKg).max())
        e.escribir(lugar.id, 0, campo: "kg", valor: JS.texto(ultimo + 2.5))
        e.escribir(lugar.id, 0, campo: "reps", valor: "8")
        _ = await e.confirmarSerie(lugar.id, 0) { _ in true }
        let records = e.recordsDeHoy()
        #expect(records.count == 1 && records.first?.tipo == .recordKg && records.first?.chip == "+2,5 kg")
        #expect(records.first?.ejercicio == lugar.nombre)
        #expect(await e.cerrarDia(notas: "") == .demo)
        #expect(espia.pedidos == 0)
        #expect(!FileManager.default.fileExists(atPath: raiz.path), "la demo no escribe nada en disco")
        // Salir de la demo no deja nada.
        await m.salirDeDemo()
        #expect(m.demoHistorial == nil && m.listaPrevia == nil && m.metas == nil)
    }

    @Test func sinElHistorialLaDemoQuedaComoAntes() async throws {
        let m = ModeloApp(cliente: ClienteRPC(config: .produccion, transporte: Espia()), almacen: TokenEnMemoria(nil),
                          raizDisco: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        m.entrarEnDemo(rutina: try Self.archivo("rutina"), dieta: try Self.archivo("dieta"))
        #expect(m.demoHistorial == nil && m.listaPrevia == nil && m.metas == nil && m.pumpDelDia() == nil)
        let e = try #require(m.entreno)
        await e.cargar()
        let lugar = try #require(e.dia.lista.first { $0.tipo != "calentamiento" })
        await e.pedirHistorial(lugar.id)
        #expect(e.tarjeta(lugar.id)?.record == nil)
        #expect(e.recordsDeHoy().isEmpty)
    }
}
