import Foundation
import Testing
import MyPumpModelos
import MyPumpReglas
@testable import MyPumpDatos

/// Un HealthKit de mentira: un peso por día (o nada) y la cuenta de las consultas.
final class FuenteSimple: FuenteSalud, @unchecked Sendable {
    let iosMayor = 18
    var hay = true
    var conPeso = true
    private(set) var agregados = 0
    private(set) var pedidos: [[String]] = []
    private let candado = NSLock()

    /// La hoja de permisos tarda (para probar el corte del onboarding).
    var demora: Duration?
    /// Tira si se piden más tipos juntos que estos (en HealthKit, un tipo que el iOS no tiene tira la hoja entera).
    var tiraConMasDe: Int?

    func disponible() async -> Bool { hay }
    func pedirLectura(_ tipos: [String]) async throws {
        if let demora { try? await Task.sleep(for: demora) }
        candado.withLock { pedidos.append(tipos) }
        if let n = tiraConMasDe, tipos.count > n { throw ErrorFuenteSalud("tipo desconocido") }
    }
    func permisos(_ tipos: [String]) async throws -> PermisosSalud { PermisosSalud(preguntados: tipos, pendientes: []) }
    func agregado(_ dataType: String, agregacion: String, desde: Double, hasta: Double) async throws -> [BaldeDiario] {
        candado.withLock { agregados += 1 }
        return []
    }
    func muestras(_ dataType: String, desde: Double, hasta: Double, limite: Int) async throws -> [MuestraSalud] {
        guard conPeso, dataType == "weight" else { return [] }
        return [MuestraSalud(inicio: desde + 8 * 3_600_000, fin: desde + 8 * 3_600_000, valor: 80, fuenteId: "balanza", fuenteNombre: "Balanza")]
    }
    func entrenos(desde: Double, hasta: Double) async throws -> [EntrenoCrudo] { [] }
}

/// Una base que acepta todo (o rechaza todo) los lotes de salud.
final class BaseSimple: Transporte, @unchecked Sendable {
    var rechaza = false
    private(set) var lotes = 0
    private let candado = NSLock()
    func enviar(_ pedido: URLRequest) async throws -> (Data, URLResponse) {
        candado.withLock { lotes += 1 }
        let url = pedido.url!
        if rechaza {
            return (Data(#"{"code":"42501","message":"permission denied"}"#.utf8), HTTPURLResponse(url: url, statusCode: 403, httpVersion: nil, headerFields: nil)!)
        }
        return (Data("1".utf8), HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}

@Suite("SincronizadorSalud: el reintento del historial y sin HealthKit")
@MainActor
struct SincronizadorSaludTests {
    let ahora = Date(timeIntervalSince1970: 1_792_000_000)
    var ms: Double { RelojLocal.ms(ahora) }

    func sinc(_ fuente: FuenteSimple, _ base: BaseSimple, _ estado: [String: String]) -> (SincronizadorSalud, AlmacenSaludEnMemoria) {
        let almacen = AlmacenSaludEnMemoria(estado)
        let ahora = self.ahora
        let s = SincronizadorSalud(fuente: fuente, cliente: ClienteRPC(transporte: base), token: "tok-de-prueba-nativa-0001", almacen: almacen,
                                   ahora: { ahora }, zona: TimeZone(identifier: "America/Argentina/Buenos_Aires")!)
        return (s, almacen)
    }

    @Test func retomaSiPasaronSeisHoras() async {
        let f = FuenteSimple(), b = BaseSimple()
        let (s, almacen) = sinc(f, b, [ClaveSalud.conectado: "1", ClaveSalud.intento: String(Int(ms - 7 * 3_600_000))])
        s.retomarHistorialSiFalta()
        let r = await s.historialEnCurso?.value
        #expect(r?.ok == true && r?.ventanasFallidas == 0)
        #expect(f.agregados == 36)   // 12 ventanas × 3 agregados
        #expect(almacen.leer(ClaveSalud.historialHecho) == "1")
        #expect(almacen.leer(ClaveSalud.cursor) == nil)
        #expect(s.historialEnCurso == nil)
    }

    @Test func elAvanceArrancaEnCeroYTerminaVacio() async {
        let f = FuenteSimple(), b = BaseSimple()
        let (s, _) = sinc(f, b, [ClaveSalud.conectado: "1"])
        final class Avances { var lista: [String] = [] }
        let a = Avances()
        s.alCambiarProgreso = { p in a.lista.append(p.map { "\($0.hecho)/\($0.total)" } ?? "nil") }
        _ = await s.historial()
        #expect(a.lista.first == "0/60")
        #expect(a.lista.last == "nil")
        #expect(a.lista.dropFirst().dropLast() == (1...12).map { "\($0 * 5)/60" })
    }

    @Test func noLoRepiteAntesDeSeisHorasNiSinConectar() async {
        let f = FuenteSimple(), b = BaseSimple()
        let (s, _) = sinc(f, b, [ClaveSalud.conectado: "1", ClaveSalud.intento: String(Int(ms - 3_600_000))])
        s.retomarHistorialSiFalta()
        #expect(s.historialEnCurso == nil)
        let (s2, _) = sinc(f, b, [:])
        s2.retomarHistorialSiFalta()
        #expect(s2.historialEnCurso == nil)
        let (s3, _) = sinc(f, b, [ClaveSalud.conectado: "1", ClaveSalud.historialHecho: "1"])
        s3.retomarHistorialSiFalta()
        #expect(s3.historialEnCurso == nil)
        #expect(f.agregados == 0)
    }

    @Test func siTodoFallaSellaElReintentoYNoQuedaHecho() async {
        let f = FuenteSimple(), b = BaseSimple()
        b.rechaza = true
        let (s, almacen) = sinc(f, b, [ClaveSalud.conectado: "1"])
        s.retomarHistorialSiFalta()
        let r = await s.historialEnCurso?.value
        #expect(r?.ok == false && r?.ventanasFallidas == 12)
        #expect(almacen.leer(ClaveSalud.historialHecho) == nil)
        #expect(almacen.leer(ClaveSalud.intento) == String(Int(ms)))   // la próxima vuelta espera 6 h
        #expect(almacen.leer(ClaveSalud.denegado) == nil)               // se leyó algo: no es falta de permiso
    }

    @Test func unHistorialEnCursoNoSeDuplica() async {
        let f = FuenteSimple(), b = BaseSimple()
        let (s, _) = sinc(f, b, [ClaveSalud.conectado: "1"])
        s.retomarHistorialSiFalta()
        let primero = s.historialEnCurso
        s.retomarHistorialSiFalta()
        #expect(s.historialEnCurso == primero)
        _ = await primero?.value
        #expect(f.agregados == 36)
    }

    @Test func sinSaludDisponibleNoPidePermisos() async {
        let f = FuenteSimple(), b = BaseSimple()
        f.hay = false
        let (s, almacen) = sinc(f, b, [:])
        let r = await s.conectar()
        #expect(!r.ok && r.motivo == "no_disponible")
        #expect(f.pedidos.isEmpty && b.lotes == 0)
        #expect(almacen.leer(ClaveSalud.conectado) == nil)
        #expect(s.ultimoIntento?["paso"]?.comoTexto == "isAvailable")
        let e = await s.estado()
        #expect(!e.disponible && e.total == 0 && e.preguntados == nil)
    }

    /// Alan Fried, 17-oct: con dos hojas, después de «No permitir» la segunda no aparecía y el onboarding esperaba el
    /// corte de 20 s. Va una sola hoja con todo, y nunca escritura.
    @Test func nuncaPideEscrituraYPideTodoEnUnaSolaHoja() async {
        let f = FuenteSimple(), b = BaseSimple()
        let (s, _) = sinc(f, b, [ClaveSalud.historialHecho: "1"])
        _ = await s.conectar()
        #expect(f.pedidos == [PuenteSalud.nucleo + PuenteSalud.resto(iosMayor: 18)])
        #expect(Set(f.pedidos.joined()) == Set(PuenteSalud.tiposLectura(iosMayor: 18)))
        #expect(PuenteSalud.tiposLectura(iosMayor: 15).contains("appleSleepingWristTemperature") == false)
    }

    /// Si la hoja entera falla (antes de mostrar nada), vuelven las dos tandas de la web: el núcleo y después el resto.
    @Test func siLaHojaEnteraFallaVuelvenLasDosTandas() async {
        let f = FuenteSimple(), b = BaseSimple()
        let resto = PuenteSalud.resto(iosMayor: 18)
        f.tiraConMasDe = max(PuenteSalud.nucleo.count, resto.count)
        let (s, _) = sinc(f, b, [ClaveSalud.historialHecho: "1"])
        let r = await s.conectar()
        #expect(r.ok)
        #expect(f.pedidos == [PuenteSalud.nucleo + resto, PuenteSalud.nucleo, resto])
    }

    @Test func elOnboardingNoEsperaMasDelLimiteYLaConexionSigue() async {
        let f = FuenteSimple(), b = BaseSimple()
        f.demora = .milliseconds(300)
        let m = ModeloSalud(cliente: ClienteRPC(transporte: b), token: "tok-de-prueba-nativa-0001", fuente: f,
                            almacen: AlmacenSaludEnMemoria([ClaveSalud.historialHecho: "1"]))
        let r = await m.conectar(esperandoComoMucho: .milliseconds(20))
        #expect(r == nil)                      // cortó: la pantalla avanza
        #expect(m.conectado == false)
        for _ in 0..<100 where !m.conectado { try? await Task.sleep(for: .milliseconds(20)) }
        #expect(m.conectado)                   // y la conexión terminó de fondo
        let rapido = await m.conectar(esperandoComoMucho: .seconds(5))
        #expect(rapido?.ok == true)
    }

    @Test func desconectarEsSoloLocal() async {
        let f = FuenteSimple(), b = BaseSimple()
        let (s, almacen) = sinc(f, b, [ClaveSalud.conectado: "1", ClaveSalud.ultimaSync: "x", ClaveSalud.historialHecho: "1", ClaveSalud.rachaVacia: "2"])
        s.desconectar()
        #expect(almacen.leer(ClaveSalud.conectado) == nil && almacen.leer(ClaveSalud.ultimaSync) == nil && almacen.leer(ClaveSalud.historialHecho) == nil)
        #expect(almacen.leer(ClaveSalud.rachaVacia) == "2")
        #expect(b.lotes == 0)
    }
}
