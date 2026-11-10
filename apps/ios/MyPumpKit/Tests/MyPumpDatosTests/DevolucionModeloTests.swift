import Foundation
import Testing
import MyPumpModelos
import MyPumpReglas
@testable import MyPumpDatos

/// La tarjeta «Devolución de Mati»: qué trae, qué guarda y cuándo no muestra nada. Gemelo de DevolucionModeloTest.kt.
@MainActor
struct DevolucionModeloTests {
    private let token = "DDDDDDDDDDDDDDDDDDDD"

    private func armar(_ d: DobleDevolucion, raiz: URL? = nil) -> ModeloDevolucion {
        let r = raiz ?? FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        return ModeloDevolucion(cliente: ClienteRPC(transporte: d), token: token, disco: Disco(raiz: r, token: token))
    }

    @Test func traeLaUltimaYElHistorial() async {
        let m = armar(.escenario("dos"))
        await m.refrescar()
        #expect(m.ultima?.id == "d1")
        #expect(m.ultima?.lineas.count == 4)
        #expect(m.anteriores.map(\.id) == ["d2", "d3"])
    }

    @Test func sinNadaPublicadoNoHayTarjeta() async {
        let m = armar(.escenario("vacio"))
        await m.refrescar()
        #expect(m.estado != nil && m.ultima == nil && m.anteriores.isEmpty)
    }

    @Test func apagadaSinHabilitarSinServidorOTokenCaidoNoSeVeNada() async {
        for caso in ["apagado", "noHabilitado", "sinServidor"] {
            let m = armar(.escenario(caso))
            await m.refrescar()
            #expect(m.estado == nil, "\(caso)")
        }
        let d = DobleDevolucion.escenario("dos"); d.tokenCaido = true
        let m = armar(d)
        await m.refrescar()
        #expect(m.estado == nil)
    }

    @Test func sinRedMuestraLoUltimoGuardado() async {
        let r = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let d = DobleDevolucion.escenario("dos")
        await armar(d, raiz: r).refrescar()
        d.sinRed = true
        let m = armar(d, raiz: r)
        await m.refrescar()
        #expect(m.ultima?.id == "d1")
        // Apagada después: se borra lo guardado y sin red ya no vuelve.
        m.apagar()
        let m2 = armar(d, raiz: r)
        await m2.refrescar()
        #expect(m2.estado == nil)
    }

    @Test func dejaDeEstarHabilitadoBorraLoGuardado() async {
        let r = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let d = DobleDevolucion.escenario("dos")
        let m = armar(d, raiz: r)
        await m.refrescar()
        d.habilitado = false
        await m.refrescar()
        #expect(m.estado == nil)
        d.sinRed = true
        let m2 = armar(d, raiz: r)
        await m2.refrescar()
        #expect(m2.estado == nil)
    }

    @Test func laPalancaSeLeeYSinLaClaveEstaApagada() {
        #expect(PalancaRemota(.objeto(["devolucion_semanal": .bool(true)])).devolucionSemanal)
        #expect(!PalancaRemota(.objeto([:])).devolucionSemanal)
        #expect(!PalancaRemota(.objeto(["devolucion_semanal": .texto("true")])).devolucionSemanal)
        #expect(!PalancaRemota.deFabrica.devolucionSemanal)
    }

    @Test func conLaPalancaApagadaModeloAppNoPreguntaPorLaDevolucion() async {
        let d = DobleDevolucion.escenario("apagado")
        let m = ModeloApp(cliente: ClienteRPC(config: .produccion, transporte: d), almacen: TokenEnMemoria(token),
                          raizDisco: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        await m.cargar()
        #expect(d.llamadasDevolucion.isEmpty)
        #expect(m.devolucion?.estado == nil)
    }

    @Test func conLaPalancaPrendidaModeloAppLaTrae() async {
        let d = DobleDevolucion.escenario("dos")
        let m = ModeloApp(cliente: ClienteRPC(config: .produccion, transporte: d), almacen: TokenEnMemoria(token),
                          raizDisco: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        await m.cargar()
        #expect(d.llamadasDevolucion == ["mypump_devolucion_get"])
        #expect(m.devolucion?.ultima?.id == "d1")
    }
}
