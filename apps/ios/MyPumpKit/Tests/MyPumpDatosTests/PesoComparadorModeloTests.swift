import Foundation
import Testing
import MyPumpModelos
@testable import MyPumpDatos
@testable import MyPumpReglas

/// El peso del comparador de fotos (2.3.3, el `_pcAsegurar` de la web): una serie aparte, solo `peso_kg`, desde el lunes de
/// la semana de la primera foto menos 7 días hasta hoy. La de 60 días de Salud no cambia.
@Suite("Peso del comparador de fotos", .serialized)
@MainActor
struct PesoComparadorModeloTests {
    /// Anota cada pedido (la URL con su filtro y el cuerpo) y contesta según la función y el filtro.
    final class Servidor: Transporte, @unchecked Sendable {
        struct Anotado { let funcion: String; let consulta: String?; let cuerpo: JSONValue }
        private let lock = NSLock()
        private var _pedidos: [Anotado] = []
        var pedidos: [Anotado] { lock.withLock { _pedidos } }
        var salud60 = "[]"
        var pesoAparte = "[]"
        var falla = false

        func enviar(_ pedido: URLRequest) async throws -> (Data, URLResponse) {
            let url = pedido.url!
            let fn = url.lastPathComponent
            let consulta = URLComponents(url: url, resolvingAgainstBaseURL: false)?.query
            let cuerpo = (try? JSONDecoder().decode(JSONValue.self, from: pedido.httpBody ?? Data("{}".utf8))) ?? .null
            lock.withLock { _pedidos.append(Anotado(funcion: fn, consulta: consulta, cuerpo: cuerpo)) }
            var texto = "[]", status = 200
            if fn == "mypump_get_salud" {
                if consulta == nil { texto = salud60 } else if falla { status = 503; texto = #"{"message":"caído"}"# } else { texto = pesoAparte }
            }
            return (Data(texto.utf8), HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!)
        }
        var aparte: [Anotado] { pedidos.filter { $0.funcion == "mypump_get_salud" && $0.consulta != nil } }
    }

    final class Reloj: @unchecked Sendable { var t = Date(timeIntervalSince1970: 1_800_000_000) }

    func modelo(_ s: Servidor, _ reloj: Reloj = Reloj(), hoy: String = "2026-11-19") -> ModeloRevision {
        let m = ModeloRevision(cliente: ClienteRPC(config: .produccion, transporte: s), token: "tok", outbox: nil)
        m.diaDeHoy = { hoy }
        m.ahora = { reloj.t }
        return m
    }

    private func peso(_ fecha: String, _ kg: Double, _ fuente: String = "manual") -> String {
        #"{"fecha":"\#(fecha)","tipo":"peso_kg","valor":\#(kg),"fuente":"\#(fuente)"}"#
    }

    /// Emmanuel: primera foto del 02/09 (semana del 31/08). El pedido va desde el 24/08, filtrado a peso_kg, y el pie da −4,6.
    @Test func pideDesdeElLunesDeLaPrimeraFotoMenosSieteDias() async throws {
        let s = Servidor()
        s.salud60 = "[\(peso("2026-11-16", 68.4)),\(peso("2026-11-18", 68.9))]"
        s.pesoAparte = "[\(peso("2026-11-18", 68.9)),\(peso("2026-11-16", 68.4)),\(peso("2026-09-20", 72.1)),\(peso("2026-09-02", 73.0))]"
        let m = modelo(s)
        await m.cargarRevision()
        // La de 60 días, como siempre: sin filtro, desde hoy − 59.
        let de60 = try #require(s.pedidos.first { $0.funcion == "mypump_get_salud" && $0.consulta == nil })
        #expect(de60.cuerpo["p_desde"]?.comoTexto == "2026-09-21")
        #expect(m.serieDelComparador.map(\.fecha) == ["2026-11-16", "2026-11-18"])

        let llego = await m.asegurarPesoComparador(fechasDeFotos: ["2026-11-16", "2026-08-31", "2026-09-02"])
        #expect(llego)
        let p = try #require(s.aparte.first)
        #expect(s.aparte.count == 1)
        #expect(p.consulta == "tipo=eq.peso_kg")
        #expect(p.cuerpo["p_token"]?.comoTexto == "tok")
        #expect(p.cuerpo["p_desde"]?.comoTexto == "2026-08-24")
        #expect(p.cuerpo["p_hasta"]?.comoTexto == "2026-11-19")
        #expect(m.serieDelComparador.map(\.fecha) == ["2026-09-02", "2026-09-20", "2026-11-16", "2026-11-18"])
        #expect(FotosProgreso.resumenComparador(primera: "2026-08-31", ultima: "2026-11-16", peso: m.serieDelComparador) == "11 semanas · -4,6 kg")
        // La de 60 días (Salud y la fila Peso) no recibe los pesos viejos.
        #expect(m.serieDePeso.map(\.fecha) == ["2026-11-16", "2026-11-18"])
    }

    /// Si los 60 días de Salud ya llegan a la primera foto (o no hay fotos), no sale ningún pedido nuevo.
    @Test func sinPedidoSiLosSesentaDiasAlcanzan() async {
        let s = Servidor()
        let m = modelo(s)
        #expect(await m.asegurarPesoComparador(fechasDeFotos: []) == false)
        // Semana del 28/09: desde el 21/09, el primer día de los 60.
        #expect(await m.asegurarPesoComparador(fechasDeFotos: ["2026-09-28", "2026-11-16"]) == false)
        #expect(s.aparte.isEmpty)
        // Semana del 21/09: desde el 14/09, que ya no entra.
        #expect(await m.asegurarPesoComparador(fechasDeFotos: ["2026-09-21"]))
        #expect(s.aparte.first?.cuerpo["p_desde"]?.comoTexto == "2026-09-14")
    }

    /// Una vez por día: no se repite con las mismas fotos; sí con una foto más vieja o con un día nuevo.
    @Test func unaVezHastaQueApareceUnaFotoMasViejaOCambiaElDia() async {
        let s = Servidor()
        final class Dia: @unchecked Sendable { var hoy = "2026-11-19" }
        let dia = Dia()
        let m = ModeloRevision(cliente: ClienteRPC(config: .produccion, transporte: s), token: "tok", outbox: nil)
        m.diaDeHoy = { dia.hoy }
        await m.asegurarPesoComparador(fechasDeFotos: ["2026-09-02"])
        await m.asegurarPesoComparador(fechasDeFotos: ["2026-09-02", "2026-11-16"])
        #expect(s.aparte.count == 1)
        await m.asegurarPesoComparador(fechasDeFotos: ["2026-07-22"])
        #expect(s.aparte.count == 2)
        #expect(s.aparte.last?.cuerpo["p_desde"]?.comoTexto == "2026-07-13")
        // Una foto más nueva que la más vieja no pide de nuevo (el rango ya la cubre).
        await m.asegurarPesoComparador(fechasDeFotos: ["2026-08-10"])
        #expect(s.aparte.count == 2)
        dia.hoy = "2026-11-20"
        await m.asegurarPesoComparador(fechasDeFotos: ["2026-07-22"])
        #expect(s.aparte.count == 3)
        #expect(s.aparte.last?.cuerpo["p_hasta"]?.comoTexto == "2026-11-20")
    }

    /// Dos pedidos a la vez (la tarjeta y la galería) salen como uno.
    @Test func dosALaVezSonUnPedido() async {
        let s = Servidor()
        let m = modelo(s)
        async let a = m.asegurarPesoComparador(fechasDeFotos: ["2026-09-02"])
        async let b = m.asegurarPesoComparador(fechasDeFotos: ["2026-09-02"])
        _ = await (a, b)
        #expect(s.aparte.count == 1)
    }

    /// Si falla, el comparador sigue con los 60 días y se reintenta pasados 5 minutos (no en cada pintada).
    @Test func siFallaReintentaALosCincoMinutos() async {
        let s = Servidor()
        s.falla = true
        s.salud60 = "[\(peso("2026-11-16", 68.4))]"
        let reloj = Reloj()
        let m = modelo(s, reloj)
        await m.cargarRevision()
        #expect(await m.asegurarPesoComparador(fechasDeFotos: ["2026-09-02"]) == false)
        #expect(m.serieDelComparador.map(\.fecha) == ["2026-11-16"])
        #expect(FotosProgreso.resumenComparador(primera: "2026-08-31", ultima: "2026-11-16", peso: m.serieDelComparador) == "11 semanas")
        reloj.t += 4 * 60
        await m.asegurarPesoComparador(fechasDeFotos: ["2026-09-02"])
        #expect(s.aparte.count == 1)
        s.falla = false
        s.pesoAparte = "[\(peso("2026-09-02", 73.0))]"
        reloj.t += 61
        #expect(await m.asegurarPesoComparador(fechasDeFotos: ["2026-09-02"]))
        #expect(s.aparte.count == 2)
        #expect(FotosProgreso.resumenComparador(primera: "2026-08-31", ultima: "2026-11-16", peso: m.serieDelComparador) == "11 semanas · -4,6 kg")
    }

    /// En las fechas que trae Salud manda Salud: el peso de hoy corregido se ve enseguida, aunque la serie aparte tenga el viejo.
    @Test func laCorreccionDeHoyGanaSobreLaSerieAparte() async {
        let s = Servidor()
        s.salud60 = "[\(peso("2026-11-19", 80.0))]"
        s.pesoAparte = "[\(peso("2026-09-02", 73.0)),\(peso("2026-11-19", 80.0)),\(peso("2026-11-19", 79.0, "apple_health"))]"
        let m = modelo(s)
        await m.cargarRevision()
        await m.asegurarPesoComparador(fechasDeFotos: ["2026-09-02"])
        #expect(m.serieDelComparador.last == PesoCorporal.Punto(fecha: "2026-11-19", kg: 80.0))
        #expect(await m.guardarPeso("70"))
        #expect(m.serieDelComparador.map(\.kg) == [73.0, 70.0])
        #expect(m.serieDePeso.map(\.kg) == [70.0])
    }
}
