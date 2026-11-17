import Foundation
import Testing
import MyPumpModelos
@testable import MyPumpDatos

/// Batería (2.3.2, punto 6): sin red la cola no reintenta sola (sale cuando vuelve la red), y con señal mala el reintento
/// se espacia hasta 120 s. Las primeras 10 pasadas fallidas van como siempre.
@Suite("Batería: la cola sin red no reintenta y con mala señal se espacia")
struct BateriaOutboxTests {
    actor Contador {
        var n = 0
        var caida = true
        func sumar() { n += 1 }
        func poner(_ v: Bool) { caida = v }
    }

    @Test func laEsperaEsLaDeSiempreLasPrimerasDiezYDespuesLlegaA120() {
        for racha in 0...10 {
            #expect(Outbox.demoraReintento(base: racha, racha: racha) == min(30_000, 2_000 * max(1, racha)))
        }
        #expect(Outbox.demoraReintento(base: 1, racha: 0) == 2_000)
        #expect(Outbox.demoraReintento(base: 8, racha: 3) == 16_000, "los intentos de la op también cuentan, como antes")
        #expect(Outbox.demoraReintento(base: 11, racha: 11) == 60_000)
        #expect(Outbox.demoraReintento(base: 12, racha: 12) == 120_000)
        #expect(Outbox.demoraReintento(base: 500, racha: 500) == 120_000)
        #expect(Outbox.topeReintento == 120_000)
        // Nunca baja con más fallos seguidos.
        var antes = 0
        for racha in 0...40 {
            let d = Outbox.demoraReintento(base: racha, racha: racha)
            #expect(d >= antes && d <= Outbox.topeReintento)
            antes = d
        }
    }

    @Test func sinRedNoReintentaSolaYAlVolverSale() async {
        let c = Contador()
        let o = Outbox(archivo: nil, reintentoAutomatico: true) { _ in
            await c.sumar()
            if await c.caida { throw URLError(.notConnectedToInternet) }
            return .respuesta(.success(.texto("row-id")))
        }
        await o.usarRed(false)
        await o.encolar("carga", .objeto(["serie": .numero(1)]), dedupeKey: "k1")
        await o.drenar()
        // La pasada que programa `encolar` puede caer después de esta: se la deja pasar.
        try? await Task.sleep(for: .milliseconds(300))
        let tras = await c.n
        #expect(tras >= 1)
        // Con red, el primer reintento iría a los 2 s; sin red no hay ninguno.
        try? await Task.sleep(for: .milliseconds(2_600))
        #expect(await c.n == tras, "sin red no se reintenta sola")
        #expect(await o.pendientes == 1, "lo encolado no se pierde")
        // Vuelve la red (lo que hace ModeloApp.alVolverLaRed): sale.
        await c.poner(false)
        await o.usarRed(true)
        await o.drenar()
        #expect(await o.pendientes == 0)
    }

    @Test func conRedYUnCorteSigueReintentandoSola() async {
        let c = Contador()
        let o = Outbox(archivo: nil, reintentoAutomatico: true) { _ in
            await c.sumar()
            if await c.n == 1 { throw URLError(.timedOut) }
            return .respuesta(.success(.texto("row-id")))
        }
        await o.encolar("carga", .objeto(["serie": .numero(1)]), dedupeKey: "k1")
        await o.drenar()
        for _ in 0..<100 where await o.pendientes > 0 { try? await Task.sleep(for: .milliseconds(50)) }
        #expect(await o.pendientes == 0, "con red el reintento sale solo, como antes")
        #expect(await c.n == 2)
    }

    /// Revisión del punto 6: con un reintento programado (acá 2 s; con mala señal hasta 120 s), una serie nueva no lo
    /// espera: `encolar` lo cancela y sale ya, con lo que había pendiente.
    @Test func loQueSeEncolaNoEsperaElReintentoProgramado() async {
        let c = Contador()
        let o = Outbox(archivo: nil, reintentoAutomatico: true) { _ in
            await c.sumar()
            if await c.caida { throw URLError(.timedOut) }
            return .respuesta(.success(.texto("row-id")))
        }
        await o.encolar("carga", .objeto(["serie": .numero(1)]), dedupeKey: "k1")
        await o.drenar()
        for _ in 0..<20 where await c.n == 0 { try? await Task.sleep(for: .milliseconds(20)) }
        #expect(await o.pendientes == 1, "la primera falló y quedó con el reintento programado")
        await c.poner(false)
        await o.encolar("carga", .objeto(["serie": .numero(2)]), dedupeKey: "k2")
        for _ in 0..<16 where await o.pendientes > 0 { try? await Task.sleep(for: .milliseconds(50)) }
        #expect(await o.pendientes == 0, "salió antes del reintento de 2 s")
    }
}
