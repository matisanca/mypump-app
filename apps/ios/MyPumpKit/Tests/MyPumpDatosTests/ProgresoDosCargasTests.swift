import Foundation
import Testing
import MyPumpModelos
import MyPumpReglas
@testable import MyPumpDatos

/// La revisión adversarial del 15-oct: con las cuentas de Progreso fuera del hilo principal, dos cargas que se pisaban
/// (la primera con un historial largo todavía calculando, la segunda ya terminada) dejaban las tarjetas de la primera
/// con el historial de la segunda.
@Suite("Progreso: dos cargas que se pisan", .serialized)
@MainActor
struct ProgresoDosCargasTests {
    static func rutina(_ nombres: [String]) -> RutinaActiva {
        let ejs = nombres.enumerated().map { i, n in
            #"{"id":"e\#(i)","tipo":"principal","nombre":"\#(n)","progresion":[{"semana":1,"series":3,"reps":"8","rir":2}]}"#
        }.joined(separator: ",")
        let json = #"{"id":"r","version":1,"semana_actual":1,"estructura":{"dias":[{"n":1,"id":"d1","nombre":"DIA","bloques":[{"titulo":"A","ejercicios":[\#(ejs)]}]}]}}"#
        return try! JSONDecoder().decode(RutinaActiva.self, from: Data(json.utf8))
    }

    nonisolated static func filas(_ nombres: [String], porEjercicio: Int) -> String {
        var t: [String] = []
        for n in nombres {
            let c = ClaveEjercicio.de(n)
            for k in 0..<porEjercicio {
                let dia = String(format: "2026-%02d-%02d %02d:00:00.123456+00", 1 + k % 9, 1 + k % 27, 8 + k % 10)
                t.append(#"{"clave":"\#(c)","registrado_en":"\#(dia)","peso_kg":\#(40 + k % 30),"reps_realizadas":8,"rir_real":2,"serie_numero":1,"notas":null,"ejercicio_nombre":"\#(n)"}"#)
            }
        }
        return "[" + t.joined(separator: ",") + "]"
    }

    final class EnOrden: Transporte, @unchecked Sendable {
        let lock = NSLock()
        var respuestas: [String]
        init(_ r: [String]) { respuestas = r }
        func enviar(_ p: URLRequest) async throws -> (Data, URLResponse) {
            let cuerpo = lock.withLock { respuestas.isEmpty ? "[]" : respuestas.removeFirst() }
            return (Data(cuerpo.utf8), HTTPURLResponse(url: p.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
    }

    /// La segunda carga entra mientras la primera hace las cuentas (después de traer lo suyo).
    @Test func laQueEntraDuranteLasCuentasGana() async throws {
        let viejos = (0..<60).map { "Viejo \($0)" }
        let t = EnOrden([Self.filas(viejos, porEjercicio: 48), Self.filas(["Nuevo"], porEjercicio: 3)])
        let m = ModeloProgreso(cliente: ClienteRPC(config: .produccion, transporte: t), token: "AAAAAAAAAAAAAAAAAAAA")
        var yaEntro = false
        m.antesDeLasCuentas = {
            guard !yaEntro else { return }
            yaEntro = true
            await m.cargar(rutina: Self.rutina(["Nuevo"]))
        }
        await m.cargar(rutina: Self.rutina(viejos))
        let nuevo = ClaveEjercicio.de("Nuevo")
        #expect(m.tarjetas.map(\.clave) == [nuevo], "las cuentas de la carga vieja pisaron a la nueva")
        #expect(Array(m.historialPorClave.keys) == [nuevo])
        #expect(m.sesiones == 3)
    }

    @Test func gananLaUltimaCargaEntera() async throws {
        let viejos = (0..<60).map { "Viejo \($0)" }
        let t = EnOrden([Self.filas(viejos, porEjercicio: 400), Self.filas(["Nuevo"], porEjercicio: 3)])
        let m = ModeloProgreso(cliente: ClienteRPC(config: .produccion, transporte: t), token: "AAAAAAAAAAAAAAAAAAAA")
        async let primera: Void = m.cargar(rutina: Self.rutina(viejos))
        // Que la primera ya esté calculando: su pedido salió (la segunda respuesta queda para la segunda carga).
        while t.lock.withLock({ t.respuestas.count }) > 1 { try await Task.sleep(for: .milliseconds(1)) }
        try await Task.sleep(for: .milliseconds(20))
        await m.cargar(rutina: Self.rutina(["Nuevo"]))
        await primera
        let nuevo = ClaveEjercicio.de("Nuevo")
        #expect(m.tarjetas.map(\.clave) == [nuevo], "quedaron las tarjetas de la carga vieja")
        #expect(Array(m.historialPorClave.keys) == [nuevo])
        #expect(m.estado == .listo)
    }
    final class Contado: Transporte, @unchecked Sendable {
        let lock = NSLock()
        var pedidos = 0
        var sinRed = false
        var demora: Duration = .zero
        var cuantos: Int { lock.withLock { pedidos } }
        func enviar(_ p: URLRequest) async throws -> (Data, URLResponse) {
            let (corte, d) = lock.withLock { pedidos += 1; return (sinRed, demora) }
            if d > .zero { try await Task.sleep(for: d) }
            if corte { throw URLError(.notConnectedToInternet) }
            let cuerpo = ProgresoDosCargasTests.filas(["Uno"], porEjercicio: 3)
            return (Data(cuerpo.utf8), HTTPURLResponse(url: p.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
    }

    /// La tarjeta de progreso de Revisión y Salud → Fuerza piden solas: con tarjetas no hace falta pedir; sin red, sí (las
    /// dos a la vez, en `laQuePidioSeVaYLaCargaSigue`).
    @Test func siHaceFaltaNoPideDosVeces() async throws {
        let t = Contado()
        let m = ModeloProgreso(cliente: ClienteRPC(config: .produccion, transporte: t), token: "AAAAAAAAAAAAAAAAAAAA")
        let r = Self.rutina(["Uno"])
        var adentro: Bool?
        m.antesDeLasCuentas = {
            guard adentro == nil else { return }
            adentro = m.cargando
        }
        await m.cargarSiHaceFalta(rutina: r)
        #expect(adentro == true)
        #expect(t.cuantos == 1)
        #expect(!m.cargando)
        #expect(m.tarjetas.map(\.clave) == [ClaveEjercicio.de("Uno")])
        await m.cargarSiHaceFalta(rutina: r)
        #expect(t.cuantos == 1, "con tarjetas no hace falta")
        // Tirar para actualizar sí pide.
        t.lock.withLock { t.sinRed = true }
        await m.cargar(rutina: r)
        let conCorte = t.cuantos
        #expect(conCorte >= 2)
        #expect(m.estado == .sinRed)
        t.lock.withLock { t.sinRed = false }
        await m.cargarSiHaceFalta(rutina: r)
        #expect(t.cuantos == conCorte + 1, "sin red se vuelve a pedir")
        #expect(m.estado == .listo)
    }
    /// Quien la pidió se va (SwiftUI cancela su `.task`) y la otra pantalla la espera: la carga sigue y termina bien, sin
    /// «sin red» y con un solo pedido.
    @Test func laQuePidioSeVaYLaCargaSigue() async throws {
        let t = Contado()
        t.demora = .milliseconds(300)
        let m = ModeloProgreso(cliente: ClienteRPC(config: .produccion, transporte: t), token: "AAAAAAAAAAAAAAAAAAAA")
        let r = Self.rutina(["Uno"])
        let revision = Task { await m.cargarSiHaceFalta(rutina: r) }
        while t.cuantos == 0 { try await Task.sleep(for: .milliseconds(5)) }
        let fuerza = Task { await m.cargarSiHaceFalta(rutina: r) }
        try await Task.sleep(for: .milliseconds(20))
        revision.cancel()
        await revision.value
        await fuerza.value
        #expect(t.cuantos == 1)
        #expect(m.estado == .listo)
        #expect(m.tarjetas.map(\.clave) == [ClaveEjercicio.de("Uno")])
    }
}
