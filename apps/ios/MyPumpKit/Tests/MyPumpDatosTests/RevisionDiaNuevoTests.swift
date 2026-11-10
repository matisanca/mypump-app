import Foundation
import Testing
import MyPumpModelos
@testable import MyPumpDatos
@testable import MyPumpReglas

/// Revisión adversarial del 14-oct, hallazgos 3 y 4: con la app abierta de un día para otro (o de una semana para la
/// otra) y sin señal, lo de ayer no puede quedar como si fuera de hoy: el check de la semana pasada se veía "Enviado" (o
/// quedaba listo para mandarse de nuevo). Lo de los hábitos se fue con Mi Día (2.1).
@Suite("Revisión con el día o la semana cambiados", .serialized)
@MainActor
struct RevisionDiaNuevoTests {
    final class Reloj: @unchecked Sendable {
        var hoy: String
        init(_ hoy: String) { self.hoy = hoy }
    }

    final class Servidor: @unchecked Sendable {
        var conRed = true
        var check = #"[{"semana_lunes":"2026-10-12","energia":4,"descanso":3,"hambre":2,"adherencia":5,"nota":"me molestó el hombro"}]"#
    }

    func modelo(_ s: Servidor, _ reloj: Reloj) -> (ModeloRevision, Outbox) {
        let t = TransporteProgramado { fn, _ in
            guard s.conRed else { throw URLError(.notConnectedToInternet) }
            switch fn {
            case "mypump_get_checkin_semana": return (200, s.check)
            default: return (200, "[]")
            }
        }
        let cliente = ClienteRPC(config: .produccion, transporte: t)
        let cola = Outbox(archivo: nil, reintentoAutomatico: false) { _ in .respuesta(.failure(ErrorRPC(clase: .red, status: 0, mensaje: "sin red"))) }
        let m = ModeloRevision(cliente: cliente, token: "tok", outbox: cola)
        m.diaDeHoy = { reloj.hoy }
        return (m, cola)
    }

    /// El día de revisión: lo que manda el servidor, y sin la función (nativa_008 sin aplicar) el domingo.
    private func modeloDia(_ respuesta: @escaping @Sendable () throws -> (Int, String), disco: Disco? = nil) -> ModeloRevision {
        let t = TransporteProgramado { fn, _ in
            if fn == "mypump_get_revision_dia" { return try respuesta() }
            return (200, "[]")
        }
        return ModeloRevision(cliente: ClienteRPC(config: .produccion, transporte: t), token: "tok", outbox: nil, disco: disco)
    }

    private let sinFuncion = #"{"code":"PGRST202","message":"Could not find the function"}"#

    @Test func elDiaDeRevisionVieneDelServidor() async {
        let m = modeloDia { (200, "6") }
        #expect(m.revisionDia == 7)
        await m.cargarRevision()
        #expect(m.revisionDia == 6)
    }

    @Test func sinLaFuncionEnLaBaseEsElDomingo() async {
        let c = sinFuncion
        let m = modeloDia { (404, c) }
        await m.cargarRevision()
        #expect(m.revisionDia == 7)
    }

    @Test func unDiaRaroDelServidorEsElDomingo() async {
        let m = modeloDia { (200, "12") }
        await m.cargarRevision()
        #expect(m.revisionDia == 7)
    }

    @Test func sinRedQuedaElUltimoDiaConocido() async throws {
        let carpeta = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let disco = Disco(carpeta: carpeta)
        let a = modeloDia({ (200, "6") }, disco: disco)
        await a.cargarRevision()
        let b = modeloDia({ throw URLError(.notConnectedToInternet) }, disco: disco)
        #expect(b.revisionDia == 6)
        await b.cargarRevision()
        #expect(b.revisionDia == 6)
    }

    /// Si la función desaparece (se revirtió la 008), lo guardado no queda pisando el domingo.
    @Test func alRevertirseLaFuncionVuelveAlDomingo() async {
        let carpeta = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let disco = Disco(carpeta: carpeta)
        let a = modeloDia({ (200, "3") }, disco: disco)
        await a.cargarRevision()
        let c = sinFuncion
        let b = modeloDia({ (404, c) }, disco: disco)
        await b.cargarRevision()
        #expect(b.revisionDia == 7)
        #expect(modeloDia({ (200, "7") }, disco: disco).revisionDia == 7)
    }

    @Test func elCheckDeLaSemanaPasadaNoQuedaEnviado() async {
        let s = Servidor(), reloj = Reloj("2026-10-18")   // domingo
        let (m, _) = modelo(s, reloj)
        await m.cargarRevision()
        #expect(m.checkinEnviado)
        reloj.hoy = "2026-10-19"   // lunes, sin señal
        s.conRed = false
        await m.cargarRevision()
        #expect(m.checkin == nil)
        #expect(!m.checkinEnviado)
        #expect(m.semana == "2026-10-19")
    }

    @Test func unCheckMandadoSinSeñalSeVeEnviado() async {
        let s = Servidor(), reloj = Reloj("2026-10-20")
        s.check = "[]"
        let (m, _) = modelo(s, reloj)
        await m.cargarRevision()
        #expect(!m.checkinEnviado)
        _ = await m.enviarCheckin(Checkin(valores: ["energia": 3, "descanso": 3, "hambre": 3, "adherencia": 3], nota: "bien"))
        // Otra carga con el servidor todavía sin el check (la cola no salió): lo pendiente gana.
        await m.cargarRevision()
        #expect(m.checkinEnviado)
        #expect(m.checkin?.nota == "bien")
    }
}
