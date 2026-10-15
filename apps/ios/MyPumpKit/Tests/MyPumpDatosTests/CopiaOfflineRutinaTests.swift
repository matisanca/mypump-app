import Foundation
import Testing
import MyPumpModelos
@testable import MyPumpDatos

/// Revisión del 15-oct, hallazgo 1: después de "Pasar a semana" o "Empezar bloque nuevo" la copia offline quedaba con la
/// rutina vieja. Un arranque sin señal (en el gimnasio) volvía a la semana anterior y lo que se cargaba iba a su sesión:
/// `registrar_carga` es upsert por (sesión, ejercicio, serie) y pisaba las series de la semana pasada. La web lo resuelve
/// con `location.reload()`, que vuelve a guardar el snapshot.
@Suite("Copia offline al pasar de semana o de bloque", .serialized)
@MainActor
struct CopiaOfflineRutinaTests {
    let raiz = FileManager.default.temporaryDirectory.appendingPathComponent("copia-rutina-\(UUID().uuidString)")
    static let token = "AAAAAAAAAAAAAAAAAAAA"

    func modelo(_ s: ServidorRutina) -> ModeloApp {
        let t = TransporteProgramado { fn, _ in
            if s.sinRed { throw URLError(.notConnectedToInternet) }
            switch fn {
            case "mypump_get_cliente_info": return (200, #"[{"cliente_id":"c1","nombre":"Cliente","perfil":"natural"}]"#)
            case "mypump_get_rutina_activa":
                if s.rutinaFalla { throw URLError(.timedOut) }
                return (200, "[" + Datos.rutina(id: s.rutinaId, semana: s.semana, tieneSiguiente: s.tieneSiguiente) + "]")
            case "mypump_avanzar_semana":
                s.semana += 1
                return (200, "\(s.semana)")
            case "mypump_activar_siguiente":
                s.rutinaId = "rut-2"; s.semana = 1; s.tieneSiguiente = false
                return (200, "true")
            default: return (200, "[]")
            }
        }
        return ModeloApp(cliente: ClienteRPC(config: .produccion, transporte: t), almacen: TokenEnMemoria(Self.token), raizDisco: raiz)
    }

    /// La semana de la rutina que quedó en `offline.json`, o nil si la copia no tiene rutina.
    func semanaEnLaCopia() -> Int? {
        let copia = Disco(raiz: raiz, token: Self.token).leer(ModeloApp.CopiaOffline.self, "offline.json")
        guard case .objeto(let o)? = copia?.rutina, case .numero(let n)? = o["semana_actual"] else { return nil }
        return Int(n)
    }

    @Test func pasarDeSemanaYArrancarSinSenalSigueEnLaNueva() async throws {
        let s = ServidorRutina(semana: 5)
        let m = modelo(s)
        await m.cargar()
        #expect(semanaEnLaCopia() == 5)
        #expect(await try #require(m.entreno).avanzarSemana() == .listo)
        #expect(m.entreno?.semana == 6 && m.rutina?.semanaActual == 6)
        #expect(semanaEnLaCopia() == 6, "la copia offline quedaba en la 5")

        // Otro arranque, sin señal: tiene que seguir en la 6.
        s.sinRed = true
        let otro = modelo(s)
        await otro.cargar()
        #expect(otro.desdeCache && otro.entreno?.semana == 6)
    }

    @Test func siLaRutinaNoLlegaDespuesDeAvanzarIgualQuedaEnLaSemanaNueva() async throws {
        let s = ServidorRutina(semana: 5)
        let m = modelo(s)
        await m.cargar()
        s.rutinaFalla = true   // el servidor avanza, pero la rutina no llega
        #expect(await try #require(m.entreno).avanzarSemana() == .listo)
        #expect(s.semana == 6)
        #expect(m.entreno?.semana == 6 && m.rutina?.semanaActual == 6, "se quedaba en la 5 con el servidor en la 6")
        #expect(semanaEnLaCopia() == 6)
    }

    @Test func siElBloqueNuevoNoLlegaElViejoNoSePuedeSeguirCargando() async throws {
        let s = ServidorRutina(semana: 12, tieneSiguiente: true)
        let m = modelo(s)
        await m.cargar()
        let e = try #require(m.entreno)
        #expect(e.puedeEmpezarBloque)
        s.rutinaFalla = true   // se activa el bloque nuevo, pero no llega
        #expect(await e.empezarBloqueNuevo() == .listo)
        #expect(!e.usable, "el bloque archivado seguía para cargar")
        #expect(semanaEnLaCopia() == nil, "la copia offline seguía con el bloque archivado")

        // Sin señal, otro arranque no muestra el bloque viejo; con señal llega el nuevo.
        s.sinRed = true
        let sinSenal = modelo(s)
        await sinSenal.cargar()
        #expect(sinSenal.entreno == nil)
        s.sinRed = false; s.rutinaFalla = false
        let conSenal = modelo(s)
        await conSenal.cargar()
        #expect(conSenal.rutina?.id == "rut-2" && conSenal.entreno?.semana == 1)
    }
}

/// El servidor de las pruebas: la rutina activa y lo que falla (la regla del transporte corre fuera del actor principal).
final class ServidorRutina: @unchecked Sendable {
    private let lock = NSLock()
    private var _semana: Int
    private var _rutinaId = "rut-1"
    private var _tieneSiguiente: Bool
    private var _sinRed = false
    private var _rutinaFalla = false
    init(semana: Int, tieneSiguiente: Bool = false) { _semana = semana; _tieneSiguiente = tieneSiguiente }
    var semana: Int { get { lock.withLock { _semana } } set { lock.withLock { _semana = newValue } } }
    var rutinaId: String { get { lock.withLock { _rutinaId } } set { lock.withLock { _rutinaId = newValue } } }
    var tieneSiguiente: Bool { get { lock.withLock { _tieneSiguiente } } set { lock.withLock { _tieneSiguiente = newValue } } }
    var sinRed: Bool { get { lock.withLock { _sinRed } } set { lock.withLock { _sinRed = newValue } } }
    var rutinaFalla: Bool { get { lock.withLock { _rutinaFalla } } set { lock.withLock { _rutinaFalla = newValue } } }
}

private enum Datos {
    static func rutina(id: String, semana: Int, tieneSiguiente: Bool) -> String {
        let ej = #"{"id":"press-d1-0","tipo":"principal","nombre":"Press banca","progresion":[{"semana":1,"series":3,"reps":"8","rir":2}]}"#
        return #"{"id":"\#(id)","version":1,"semana_actual":\#(semana),"tiene_siguiente":\#(tieneSiguiente),"estructura":{"semanas_total":12,"dias":[{"n":1,"id":"d1","nombre":"EMPUJE","bloques":[{"titulo":"A","ejercicios":[\#(ej)]}]}]}}"#
    }
}
