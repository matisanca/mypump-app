import Foundation
import Testing
import MyPumpModelos
@testable import MyPumpDatos
@testable import MyPumpReglas

/// Revisión adversarial del 14-oct, hallazgos 3 y 4: con la app abierta de un día para otro (o de una semana para la
/// otra) y sin señal, lo de ayer no puede quedar como si fuera de hoy. Un toque sobre los 8 vasos de ayer encolaba 9
/// para hoy, y el check de la semana pasada se veía "Enviado" (o quedaba listo para mandarse de nuevo).
@Suite("Revisión con el día o la semana cambiados", .serialized)
@MainActor
struct RevisionDiaNuevoTests {
    final class Reloj: @unchecked Sendable {
        var hoy: String
        init(_ hoy: String) { self.hoy = hoy }
    }

    final class Servidor: @unchecked Sendable {
        var conRed = true
        var habitos = #"[{"fecha":"2026-10-13","entrenamiento":"entrene","vasos_agua":8}]"#
        var check = #"[{"semana_lunes":"2026-10-12","energia":4,"descanso":3,"hambre":2,"adherencia":5,"nota":"me molestó el hombro"}]"#
    }

    func modelo(_ s: Servidor, _ reloj: Reloj) -> (ModeloRevision, Outbox) {
        let t = TransporteProgramado { fn, _ in
            guard s.conRed else { throw URLError(.notConnectedToInternet) }
            switch fn {
            case "mypump_get_habitos_dia": return (200, s.habitos)
            case "mypump_get_checkin_semana": return (200, s.check)
            case "mypump_get_streak": return (200, #"[{"streak":3}]"#)
            default: return (200, "[]")
            }
        }
        let cliente = ClienteRPC(config: .produccion, transporte: t)
        let cola = Outbox(archivo: nil, reintentoAutomatico: false) { _ in .respuesta(.failure(ErrorRPC(clase: .red, status: 0, mensaje: "sin red"))) }
        let m = ModeloRevision(cliente: cliente, token: "tok", outbox: cola)
        m.diaDeHoy = { reloj.hoy }
        return (m, cola)
    }

    @Test func losHabitosDeAyerNoSonLosDeHoy() async {
        let s = Servidor(), reloj = Reloj("2026-10-13")
        let (m, cola) = modelo(s, reloj)
        await m.cargarMiDia()
        #expect(m.habitos.vasosAgua == 8 && m.habitos.entrenamiento == "entrene")
        // Medianoche con la app abierta, y sin señal.
        reloj.hoy = "2026-10-14"
        s.conRed = false
        await m.cargarMiDia()
        #expect(m.habitos == HabitosHoy())
        #expect(m.miDiaCargado)   // se puede marcar igual: sale por la cola
        m.cambiarAgua(1)
        // Se guarda 600 ms después del último toque: se espera a que aparezca (con la suite entera corriendo tarda más).
        var op: Operacion?
        for _ in 0..<50 where op == nil {
            try? await Task.sleep(for: .milliseconds(100))
            op = await cola.pendientesPorClave()["habito|2026-10-14|vasos_agua"]
        }
        #expect(op?.payload["valor"] == .texto("1"))   // antes: 9 (los 8 de ayer + 1)
    }

    @Test func mismoDiaSinRedConservaLoDeHoy() async {
        let s = Servidor(), reloj = Reloj("2026-10-13")
        let (m, _) = modelo(s, reloj)
        await m.cargarMiDia()
        s.conRed = false
        await m.cargarMiDia()
        #expect(m.habitos.vasosAgua == 8)
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
