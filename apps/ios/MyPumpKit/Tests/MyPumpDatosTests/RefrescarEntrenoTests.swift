import Foundation
import Testing
import MyPumpModelos
@testable import MyPumpDatos

/// Revisión del 15-oct, hallazgo 6: "tirar para actualizar" en Entreno llamaba a `motor.cargar()`, que no pide
/// `get_rutina_activa`: una rutina que Mati republicó no aparecía hasta reabrir la app. Dieta ya lo hacía con la carga
/// entera (`ModeloApp.cargar()`).
@Suite("Tirar para actualizar en Entreno trae la rutina", .serialized)
@MainActor
struct RefrescarEntrenoTests {
    let raiz = FileManager.default.temporaryDirectory.appendingPathComponent("refrescar-entreno-\(UUID().uuidString)")

    nonisolated static func rutina(version: Int, ejercicio: String) -> String {
        let ej = #"{"id":"press-d1-0","tipo":"principal","nombre":"\#(ejercicio)","progresion":[{"semana":1,"series":3,"reps":"8","rir":2}]}"#
        return #"[{"id":"rut-1","version":\#(version),"semana_actual":1,"tiene_siguiente":false,"estructura":{"semanas_total":12,"dias":[{"n":1,"id":"d1","nombre":"EMPUJE","bloques":[{"titulo":"A","ejercicios":[\#(ej)]}]}]}}]"#
    }

    @Test func laRutinaRepublicadaSeVeAlTirarParaActualizar() async throws {
        let publicada = Publicada()
        let t = TransporteProgramado { fn, _ in
            switch fn {
            case "mypump_get_cliente_info": return (200, #"[{"cliente_id":"c1","nombre":"Cliente","perfil":"natural"}]"#)
            case "mypump_get_rutina_activa":
                let (v, nombre) = publicada.actual
                return (200, Self.rutina(version: v, ejercicio: nombre))
            default: return (200, "[]")
            }
        }
        let m = ModeloApp(cliente: ClienteRPC(config: .produccion, transporte: t), almacen: TokenEnMemoria("AAAAAAAAAAAAAAAAAAAA"), raizDisco: raiz)
        await m.cargar()
        let e = try #require(m.entreno)
        #expect(e.rutina.version == 1 && e.dia.ejercicio("press-d1-0")?.nombre == "Press banca")

        // Mati cambia el ejercicio y republica.
        publicada.actual = (2, "Press inclinado con mancuernas")
        await m.refrescarEntreno()
        let ahora = try #require(m.entreno)
        #expect(ahora.rutina.version == 2, "seguía la rutina de antes")
        #expect(ahora.dia.ejercicio("press-d1-0")?.nombre == "Press inclinado con mancuernas")
        #expect(m.rutina?.version == 2)
        // Y la copia offline quedó con la nueva.
        let copia = Disco(raiz: raiz, token: "AAAAAAAAAAAAAAAAAAAA").leer(ModeloApp.CopiaOffline.self, "offline.json")
        #expect(copia?.rutina?["version"] == .numero(2))
    }
}

/// La versión publicada (la regla del servidor corre fuera del actor principal).
final class Publicada: @unchecked Sendable {
    private let lock = NSLock()
    private var _actual: (Int, String) = (1, "Press banca")
    var actual: (Int, String) { get { lock.withLock { _actual } } set { lock.withLock { _actual = newValue } } }
}
