import Foundation
import Testing
import MyPumpModelos
import MyPumpReglas
@testable import MyPumpDatos

/// La lista previa a la videollamada (2.3.0): qué trae, cada cuánto pregunta y cuándo no muestra nada.
@MainActor
struct ListaPreviaModeloTests {
    private let token = "LLLLLLLLLLLLLLLLLLLL"

    /// Un reloj que las pruebas adelantan.
    private final class Reloj: @unchecked Sendable {
        private let lock = NSLock()
        private var t = Date(timeIntervalSince1970: 1_800_000_000)
        var ahora: Date { lock.withLock { t } }
        func avanzar(_ s: TimeInterval) { lock.withLock { t = t.addingTimeInterval(s) } }
    }

    private func raiz() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }
    private func armar(_ d: DobleColaA, raiz r: URL? = nil, reloj: Reloj = Reloj()) -> ModeloListaPrevia {
        ModeloListaPrevia(cliente: ClienteRPC(transporte: d), token: token, disco: Disco(raiz: r ?? raiz(), token: token)) { reloj.ahora }
    }

    @Test func traeLaLista() async {
        let m = armar(.escenario("sinPermiso"))
        await m.refrescar()
        #expect(m.vista?.items.map(\.clave) == ["guia", "dudas", "formulario", "fotos"])
        #expect(m.vista?.resumen == "Llevás 1 de 3")
        #expect(m.vista?.items.first?.destino == .guia && m.vista?.items.last?.destino == .fotos)
    }

    @Test func comoMuchoUnPedidoPorMinuto() async {
        let d = DobleColaA.escenario("sinPermiso")
        let reloj = Reloj()
        let m = armar(d, reloj: reloj)
        await m.refrescar()
        await m.refrescar()
        reloj.avanzar(59)
        await m.refrescar()
        #expect(d.llamadasLista.count == 1)
        d.lista = DobleColaA.listaLista
        reloj.avanzar(2)
        await m.refrescar()
        #expect(d.llamadasLista.count == 2)
        #expect(m.vista?.todoListo == true && m.vista?.resumen == "Ya tenés todo listo")
    }

    @Test func inactivaSinServidorOTokenCaidoNoSeVeNada() async {
        for caso in ["listaInactiva", "sinServidor"] {
            let m = armar(.escenario(caso))
            await m.refrescar()
            #expect(m.vista == nil, "\(caso)")
        }
        let d = DobleColaA(); d.tokenCaido = true
        let m = armar(d)
        await m.refrescar()
        #expect(m.vista == nil)
    }

    @Test func sinRedMuestraLoUltimoGuardadoYDejaDeEstarActivaLoBorra() async {
        let r = raiz()
        let d = DobleColaA.escenario("sinPermiso")
        await armar(d, raiz: r).refrescar()
        d.sinRed = true
        let m = armar(d, raiz: r)
        await m.refrescar()
        #expect(m.vista?.items.count == 4)
        // La videollamada ya pasó: no queda nada, tampoco sin red la próxima vez.
        d.sinRed = false
        d.lista = .objeto(["ok": .bool(true), "activa": .bool(false), "items": .lista([])])
        let reloj = Reloj()
        let m2 = armar(d, raiz: r, reloj: reloj)
        await m2.refrescar()
        #expect(m2.vista == nil)
        d.sinRed = true
        let m3 = armar(d, raiz: r)
        await m3.refrescar()
        #expect(m3.vista == nil)
    }

    @Test func conLaPalancaPrendidaModeloAppLaTraeYApagadaLaBorra() async {
        let r = raiz()
        let d = DobleColaA.escenario("sinPermiso")
        let m = ModeloApp(cliente: ClienteRPC(config: .produccion, transporte: d), almacen: TokenEnMemoria(token), raizDisco: r)
        await m.cargar()
        #expect(d.llamadasLista.count == 1)
        #expect(m.listaPrevia?.vista?.items.count == 4)
        d.palancaLista = false
        await m.cargar()
        #expect(d.llamadasLista.count == 1)
        #expect(m.listaPrevia?.vista == nil)
    }

    @Test func laDeLaDemoEsFijaYNoLlama() async {
        let m = ModeloListaPrevia(muestra: DobleColaA.listaDemo)
        #expect(m.vista?.resumen == "Llevás 1 de 3")
        await m.refrescar()
        #expect(m.vista?.items.count == 4)
    }
}
