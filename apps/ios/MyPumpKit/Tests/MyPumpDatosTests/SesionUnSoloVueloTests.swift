import Foundation
import Testing
import MyPumpModelos
@testable import MyPumpDatos

/// Revisión del 15-oct, hallazgo 5: al confirmar la primera serie del día salían juntos `asegurarSesion` (la pantalla) y
/// `resolverSesion` (la cola), y cada uno mandaba su `iniciar_sesion`. La web comparte la llamada en vuelo
/// (`_sesionInflight`): acá, un solo vuelo por día y semana para los dos.
@Suite("Un solo vuelo para crear la sesión del día", .serialized)
@MainActor
struct SesionUnSoloVueloTests {
    let raiz = FileManager.default.temporaryDirectory.appendingPathComponent("sesion-vuelo-\(UUID().uuidString)")
    static let token = "AAAAAAAAAAAAAAAAAAAA"

    func esperar(_ condicion: () async -> Bool) async -> Bool {
        for _ in 0..<150 {
            if await condicion() { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return await condicion()
    }

    @Test func confirmarLaPrimeraSerieCreaLaSesionUnaSolaVez() async throws {
        let t = TransporteProgramado { fn, _ in
            switch fn {
            case "mypump_get_cliente_info": return (200, #"[{"cliente_id":"c1","nombre":"Cliente","perfil":"natural"}]"#)
            case "mypump_get_rutina_activa": return (200, "[" + filaRutina(semana: 5) + "]")
            case "mypump_get_sesion_dia": return (200, "[]")
            case "mypump_iniciar_sesion":
                try await Task.sleep(for: .milliseconds(100))
                return (200, #""ses-1""#)
            case "mypump_registrar_carga": return (200, #""fila-1""#)
            default: return (200, "[]")
            }
        }
        let m = ModeloApp(cliente: ClienteRPC(config: .produccion, transporte: t), almacen: TokenEnMemoria(Self.token), raizDisco: raiz)
        await m.cargar()
        let e = try #require(m.entreno)
        // La carga del motor (restaurar la sesión, el historial, los comentarios) corre aparte: que termine antes de tocar.
        #expect(await esperar { t.llamadas.contains("mypump_get_comentarios") })
        e.escribir("jal-d1-0", 0, campo: "reps", valor: "10")
        e.escribir("jal-d1-0", 0, campo: "kg", valor: "60")
        await e.confirmarSerie("jal-d1-0", 0) { _ in true }
        #expect(await esperar {
            guard t.llamadas.contains("mypump_registrar_carga") else { return false }
            return await m.outbox?.pendientes == 0
        })
        #expect(await esperar { e.dia.sesionId == "ses-1" })
        #expect(t.llamadas.filter { $0 == "mypump_iniciar_sesion" }.count == 1, "la pantalla y la cola crearon cada una la suya")
    }
}
