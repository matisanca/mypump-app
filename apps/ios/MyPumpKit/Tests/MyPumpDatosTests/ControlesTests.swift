import Foundation
import Testing
import MyPumpModelos
import MyPumpReglas
@testable import MyPumpDatos

/// «Tu próximo control de salud» dentro de `ModeloEstudios`, contra el doble (`DobleEstudios`): las dos palancas, la
/// sección de Estudios y la caída segura.
@MainActor
struct ControlesTests {
    private func armar(_ d: DobleEstudios, estudios: Bool = true, controles: Bool = true) -> ModeloEstudios {
        let r = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let m = ModeloEstudios(cliente: ClienteRPC(transporte: d), token: "tk-prueba", disco: Disco(raiz: r.appendingPathComponent("soporte"), token: "tk-prueba"),
                               cache: r.appendingPathComponent("caches"), esperar: { _ in })
        m.usarPalanca(estudios)
        m.usarPalancaControles(controles)
        return m
    }
    private func llamoControles(_ d: DobleEstudios) -> Bool { d.llamadas.contains("mypump_controles_get") }

    @Test func palancaApagadaNoLlamaNiMuestra() async {
        let d = DobleEstudios.escenario("controlesApagado")
        let m = armar(d, controles: false)
        await m.sincronizar()
        #expect(m.habilitado)
        #expect(!llamoControles(d))
        #expect(m.controles == nil && m.tarjetaControl == nil && m.hitosControl.isEmpty)
        // El bloque «Próximo control» queda con lo que trajo Estudios.
        #expect(m.estado?.proximoControl?.cuando == "Semana del 23/11")
        #expect(m.estado?.proximoControl?.nota == nil)
    }

    @Test func sinEstudiosNoHayControles() async {
        let d = DobleEstudios.escenario("controlEnVentana")
        let m = armar(d, estudios: false)
        await m.sincronizar()
        #expect(!llamoControles(d))
        #expect(m.controles == nil && m.tarjetaControl == nil)
        let n = DobleEstudios.escenario("controlEnVentana"); n.habilitado = false
        let m2 = armar(n)
        await m2.sincronizar()
        #expect(!llamoControles(n))
        #expect(m2.tarjetaControl == nil)
    }

    @Test func sinControl() async {
        let d = DobleEstudios.escenario("sinControl")
        let m = armar(d)
        await m.sincronizar()
        #expect(llamoControles(d))
        #expect(m.controles != nil && m.controles?.proximo == nil)
        #expect(m.tarjetaControl == nil && m.hitosControl.isEmpty)
        #expect(m.estado?.proximoControl?.cuando == "Semana del 23/11")
    }

    @Test func controlLejano() async {
        let d = DobleEstudios.escenario("controlLejano")
        let m = armar(d)
        await m.sincronizar()
        #expect(m.tarjetaControl == nil)
        let p = m.estado?.proximoControl
        #expect(p?.titulo == "Control de salud")
        #expect(p?.cuando == "El miércoles 30/12")
        #expect(p?.nota == TextosControles.notaProgramado)
        #expect(m.hitosControl.map(\.estado) == ["Próximo", "Mati lo vio"])
    }

    @Test func controlEnVentana() async {
        let d = DobleEstudios.escenario("controlEnVentana")
        let m = armar(d)
        await m.sincronizar()
        #expect(m.tarjetaControl == Controles.TarjetaInicio(titulo: "Tu próximo control de salud", cuando: "El lunes 16/11",
                                                            nota: TextosControles.notaProgramado, boton: "Ver mis estudios"))
        #expect(m.estado?.proximoControl?.cuando == "El lunes 16/11")
        // Lo de Estudios sigue entero: la tarjeta de estudios pendientes no se pisa.
        #expect(m.pendientes == 3)
    }

    @Test func ordenesEnviadasSacanLaTarjetaDeArriba() async {
        let d = DobleEstudios.escenario("controlOrdenes")
        let m = armar(d)
        await m.sincronizar()
        #expect(m.tarjetaControl == nil)
        #expect(m.estado?.proximoControl?.nota == TextosControles.notaOrdenes)
    }

    @Test func apagarEnElMomento() async {
        let d = DobleEstudios.escenario("controlEnVentana")
        let m = armar(d)
        await m.sincronizar()
        #expect(m.tarjetaControl != nil)
        m.usarPalancaControles(false)
        #expect(m.tarjetaControl == nil && m.controles == nil)
        #expect(m.estado?.proximoControl?.cuando == "Semana del 23/11")
        m.usarPalancaControles(true)
        await m.sincronizar()
        #expect(m.tarjetaControl != nil)
        m.usarPalanca(false)
        #expect(m.tarjetaControl == nil && m.estado == nil)
    }

    /// Apagar la palanca o la sección mientras viaja `mypump_controles_get`: esa respuesta no vuelve a pintar nada.
    @Test func respuestaViejaNoVuelve() async {
        for apagarSeccion in [false, true] {
            let d = DobleEstudios.escenario("controlEnVentana")
            let m = armar(d)
            d.antesDeControles = { @MainActor in if apagarSeccion { m.usarPalanca(false) } else { m.usarPalancaControles(false) } }
            await m.sincronizar()
            #expect(llamoControles(d))
            #expect(m.controles == nil && m.tarjetaControl == nil && m.hitosControl.isEmpty)
            #expect(m.estado?.proximoControl?.nota == nil, "el bloque de Estudios vuelve a lo suyo")
        }
    }

    /// Prendida con la app abierta: los trae sin esperar a la próxima carga.
    @Test func prenderConLaAppAbiertaLosTrae() async {
        let d = DobleEstudios.escenario("controlEnVentana")
        let m = armar(d, controles: false)
        await m.sincronizar()
        #expect(!llamoControles(d))
        m.usarPalancaControles(true)
        for _ in 0..<50 where m.tarjetaControl == nil { await Task.yield(); try? await Task.sleep(nanoseconds: 10_000_000) }
        #expect(m.tarjetaControl != nil)
    }

    /// Con las órdenes mandadas por fuera de la app no hay «Tus órdenes»: la nota no manda a buscarlas.
    @Test func ordenesSinListaNoMandaABuscarlas() async {
        let d = DobleEstudios.escenario("controlOrdenes")
        let m = armar(d)
        await m.sincronizar()
        let conLista = m.estado?.ordenes.isEmpty == false
        #expect(m.estado?.proximoControl?.nota == (conLista ? TextosControles.notaOrdenes : TextosControles.notaOrdenesSinLista))
    }

    @Test func caidaSegura() async {
        // Función inexistente: sin controles, Estudios igual.
        let d = DobleEstudios.escenario("controlEnVentana"); d.controlesSinFuncion = true
        let m = armar(d)
        await m.sincronizar()
        #expect(m.habilitado && m.controles == nil && m.tarjetaControl == nil)
        // Un corte después de haber cargado: queda lo de esta sesión.
        let d2 = DobleEstudios.escenario("controlEnVentana")
        let m2 = armar(d2)
        await m2.sincronizar()
        d2.sinRed = true
        await m2.sincronizar()
        #expect(m2.tarjetaControl != nil)
        // Una respuesta rara: sin controles.
        let d3 = DobleEstudios.escenario("controlEnVentana"); d3.controles = .lista([])
        let m3 = armar(d3)
        await m3.sincronizar()
        #expect(m3.habilitado && m3.controles == nil)
    }

    @Test func palancaDeLaConfig() {
        #expect(PalancaRemota(.objeto([:])).controlesApp == false)
        #expect(PalancaRemota(.objeto(["controles_app": .bool(true)])).controlesApp == true)
        #expect(PalancaRemota(.objeto(["controles_app": .texto("true")])).controlesApp == false)
    }
}
