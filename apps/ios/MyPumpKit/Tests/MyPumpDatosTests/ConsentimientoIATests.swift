import Foundation
import Testing
import MyPumpModelos
@testable import MyPumpDatos
@testable import MyPumpReglas

/// D7 del lado de la app (`nativa_002`): sin la migración todo sigue como hoy; con ella se pregunta antes del primer
/// uso, el "no" sale por la cola y la foto no sale del teléfono.
@Suite("Permiso para la IA (D7)", .serialized)
@MainActor
struct ConsentimientoIATests {
    final class Estado: @unchecked Sendable {
        var respuesta: (Int, String) = (200, #"{"acepta":null}"#)
        var conRed = true
        var guardados: [JSONValue] = []
        var visiones = 0
    }

    func modelo(_ e: Estado, raiz: URL) -> ModeloApp {
        let t = TransporteProgramado { fn, cuerpo in
            guard e.conRed else { throw URLError(.notConnectedToInternet) }
            switch fn {
            case "mypump_get_cliente_info": return (200, #"[{"cliente_id":"c1","nombre":"Cliente","perfil":"natural"}]"#)
            case "mypump_get_consentimiento_ia": return e.respuesta
            case "mypump_guardar_consentimiento_ia": e.guardados.append(cuerpo); return (200, "true")
            case "mypump_get_rutina_activa": return (200, #"[{"id":"r1","semana_actual":1,"estructura":{"dias":[]}}]"#)
            case "vision": e.visiones += 1; return (200, "{}")
            default: return (200, "[]")
            }
        }
        return ModeloApp(cliente: ClienteRPC(config: .produccion, transporte: t), almacen: TokenEnMemoria("AAAAAAAAAAAAAAAAAAAA"), raizDisco: raiz)
    }

    func raiz() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("consentimiento-\(UUID().uuidString)") }

    @Test func sinLaMigracionTodoSigueComoHoy() async {
        let e = Estado(); e.respuesta = (404, #"{"code":"PGRST202","message":"Could not find the function"}"#)
        let r = raiz(); defer { try? FileManager.default.removeItem(at: r) }
        let m = modelo(e, raiz: r)
        await m.cargar()
        #expect(!m.consentimientoIADisponible)
        #expect(!m.faltaConsentimientoIA)
        #expect(m.analisisDeFotoPermitido)
    }

    @Test func nuncaSeLePreguntoPidePermisoYFrenaLaFoto() async {
        let e = Estado()
        let r = raiz(); defer { try? FileManager.default.removeItem(at: r) }
        let m = modelo(e, raiz: r)
        await m.cargar()
        #expect(m.faltaConsentimientoIA)
        #expect(!m.analisisDeFotoPermitido)
        let foto = await m.analizarFoto(Data([0xFF]), tipo: .plato)
        if case .failure(let err) = foto { #expect(err.codigo == "SIN_PERMISO_IA") } else { Issue.record("la foto salió sin permiso") }
        #expect(e.visiones == 0)
    }

    @Test func elNoSalePorLaColaYQueda() async {
        let e = Estado()
        let r = raiz(); defer { try? FileManager.default.removeItem(at: r) }
        let m = modelo(e, raiz: r)
        await m.cargar()
        await m.decidirConsentimientoIA(false)
        #expect(m.consentimientoIA == false)
        #expect(!m.faltaConsentimientoIA)
        #expect(e.guardados.first?["p_acepta"] == .bool(false))
        #expect(e.guardados.first?["p_plataforma"] == .texto("ios"))
        // Otro arranque, sin red: la decisión se conserva.
        e.conRed = false
        let otro = modelo(e, raiz: r)
        await otro.cargar()
        #expect(otro.consentimientoIA == false)
        #expect(!otro.analisisDeFotoPermitido)
    }

    @Test func loDecididoSinRedGanaSobreElServidor() async {
        let e = Estado()
        let r = raiz(); defer { try? FileManager.default.removeItem(at: r) }
        let m = modelo(e, raiz: r)
        await m.cargar()
        e.conRed = false
        await m.decidirConsentimientoIA(true)   // queda en la cola
        e.conRed = true
        e.respuesta = (200, #"{"acepta":null}"#)
        // Recarga antes de que la cola salga: lo pendiente gana.
        await m.cargar()
        #expect(m.consentimientoIA == true)
        #expect(m.analisisDeFotoPermitido)
    }
}
