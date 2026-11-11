import Foundation
import Testing
import MyPumpModelos
@testable import MyPumpDatos

/// «Novedades de tu plan»: la base guardada en el teléfono, la lista, la palanca y la carga entera.
@Suite("Novedades de tu plan: modelo", .serialized)
@MainActor
struct NovedadesModeloTests {
    let raiz = FileManager.default.temporaryDirectory.appendingPathComponent("novedades-\(UUID().uuidString)")
    static let token = "AAAAAAAAAAAAAAAAAAAA"

    nonisolated static func rutina(_ ejercicio: String, series: Int = 3, semana: Int = 1, version: Int = 1) -> JSONValue {
        let txt = #"{"id":"r-1","version":\#(version),"semana_actual":\#(semana),"estructura":{"dias":[{"id":"d1","n":1,"nombre":"Torso","bloques":[{"ejercicios":[{"id":"e1","nombre":"\#(ejercicio)","series":\#(series),"reps":"8-10"},{"id":"e2","nombre":"Remo","series":3,"reps":"10"}]}]}]}}"#
        return try! JSONDecoder().decode(JSONValue.self, from: Data(txt.utf8))
    }

    nonisolated static func supl(_ nombres: [String]) -> JSONValue {
        .objeto(["suplementacion": .objeto(["items": .lista(nombres.map { .objeto(["nombre": .texto($0), "cantidad": .texto("5 g"), "momento": .texto("desayuno")]) })]),
                 "esquema": .numero(1)])
    }

    func nuevo() -> ModeloNovedades { ModeloNovedades(disco: Disco(raiz: raiz, token: Self.token)) }

    @Test func laPrimeraVezSinNadaGuardaYNoMuestra() {
        let m = nuevo()
        #expect(m.observar(rutina: .hay(Self.rutina("Press banca")), dieta: .ninguna, suplementacion: .noLlego) == nil)
        #expect(m.lista.isEmpty)
        // La segunda, con un cambio: ahora sí.
        let n = m.observar(rutina: .hay(Self.rutina("Press inclinado", version: 2)), dieta: .ninguna, suplementacion: .noLlego)
        #expect(n?.partes.first?.lineas == ["En Torso cambia Press banca por Press inclinado"])
        #expect(m.pendiente?.id == n?.id)
        // Otro modelo con la misma carpeta (se cerró la app) la sigue teniendo.
        #expect(nuevo().pendiente?.id == n?.id)
    }

    @Test func conLaSemillaSeVeLoQueCambioAntesDeLaPrimeraVez() {
        let m = nuevo()
        let n = m.observar(rutina: .hay(Self.rutina("Press banca", series: 4)), dieta: .noLlego, suplementacion: .noLlego,
                           semilla: (.hay(Self.rutina("Press banca")), .noLlego, .noLlego))
        #expect(n?.titular == "Mati actualizó tu rutina")
        #expect(n?.resumen == "En Torso, Press banca pasa a 4 series de 8 a 10")
    }

    @Test func loQueNoLlegoNoSeComparaNiSePisa() {
        let m = nuevo()
        m.observar(rutina: .hay(Self.rutina("Press banca")), dieta: .noLlego, suplementacion: .hay(Self.supl(["Creatina"])))
        #expect(m.observar(rutina: .noLlego, dieta: .noLlego, suplementacion: .noLlego) == nil)
        // La base sigue siendo la primera: el cambio se ve cuando vuelve a llegar.
        let n = m.observar(rutina: .noLlego, dieta: .noLlego, suplementacion: .hay(Self.supl(["Creatina", "Omega 3"])))
        #expect(n?.partes.map(\.lineas) == [["Se suma Omega 3"]])
        #expect(n.map { !$0.resumen.contains("5 g") } == true)
    }

    @Test func republicarIgualOPasarDeSemanaNoMuestraNada() {
        let m = nuevo()
        m.observar(rutina: .hay(Self.rutina("Press banca")), dieta: .noLlego, suplementacion: .noLlego)
        #expect(m.observar(rutina: .hay(Self.rutina("Press banca", semana: 2, version: 7)), dieta: .noLlego, suplementacion: .noLlego) == nil)
        #expect(m.lista.isEmpty)
    }

    @Test func soloConBaseNoArrancaUnaBase() {
        let m = nuevo()
        #expect(m.observar(rutina: .noLlego, dieta: .noLlego, suplementacion: .hay(Self.supl(["Creatina"])), soloConBase: true) == nil)
        #expect(Disco(raiz: raiz, token: Self.token).leer(ModeloNovedades.Base.self, ModeloNovedades.archivoBase) == nil)
    }

    @Test func vistaUnaVezYLaListaTieneTope() {
        let m = nuevo()
        m.observar(rutina: .hay(Self.rutina("E0")), dieta: .noLlego, suplementacion: .noLlego)
        for i in 1...15 { m.observar(rutina: .hay(Self.rutina("E\(i)")), dieta: .noLlego, suplementacion: .noLlego) }
        #expect(m.lista.count == ModeloNovedades.maximo)
        let id = try! #require(m.pendiente).id
        m.marcarVista(id)
        #expect(m.pendiente?.id != id)
        #expect(nuevo().lista.first { $0.id == id }?.vista == true)
    }

    @Test func laTarjetaDuraUnaSemana() {
        var hoy = Date(timeIntervalSince1970: 1_800_000_000)
        let m = ModeloNovedades(disco: Disco(raiz: raiz, token: Self.token), ahora: { hoy })
        m.observar(rutina: .hay(Self.rutina("A")), dieta: .noLlego, suplementacion: .noLlego)
        m.observar(rutina: .hay(Self.rutina("B")), dieta: .noLlego, suplementacion: .noLlego)
        #expect(m.reciente != nil)
        hoy = hoy.addingTimeInterval(8 * 86_400)
        #expect(m.reciente == nil)
        #expect(m.lista.count == 1)
    }

    // MARK: - La carga entera, con la palanca

    final class Servidor: @unchecked Sendable {
        var palanca: Bool
        var ejercicio = "Press banca"
        var version = 1
        var llamadas: [String] = []
        init(palanca: Bool) { self.palanca = palanca }
    }

    func app(_ s: Servidor) -> ModeloApp {
        let t = TransporteProgramado { fn, _ in
            s.llamadas.append(fn)
            switch fn {
            case "mypump_get_cliente_info": return (200, #"[{"cliente_id":"c1","nombre":"Cliente","perfil":"natural"}]"#)
            case "mypump_get_app_config": return (200, s.palanca ? #"{"novedades_plan":true}"# : "{}")
            case "mypump_get_rutina_activa":
                let r = Self.rutina(s.ejercicio, version: s.version)
                return (200, "[" + String(decoding: try JSONEncoder().encode(r), as: UTF8.self) + "]")
            default: return (200, "[]")
            }
        }
        return ModeloApp(cliente: ClienteRPC(config: .produccion, transporte: t), almacen: TokenEnMemoria(Self.token), raizDisco: raiz)
    }

    func esperar(_ c: () -> Bool) async {
        for _ in 0..<100 where !c() { try? await Task.sleep(for: .milliseconds(20)) }
    }

    @Test func conLaPalancaPrendidaUnaPublicacionNuevaSeVe() async {
        let s = Servidor(palanca: true)
        let m = app(s)
        await m.cargar()
        await esperar { FileManager.default.fileExists(atPath: Disco(raiz: raiz, token: Self.token).url(ModeloNovedades.archivoBase).path) }
        #expect(m.novedades?.lista.isEmpty == true)
        s.ejercicio = "Press inclinado"; s.version = 2
        let otra = app(s)
        await otra.cargar()
        await esperar { otra.novedades?.pendiente != nil }
        #expect(otra.novedades?.pendiente?.resumen == "En Torso cambia Press banca por Press inclinado")
    }

    @Test func conLaPalancaApagadaNoSeGuardaNiSeMuestraNada() async {
        let s = Servidor(palanca: false)
        let m = app(s)
        await m.cargar()
        s.ejercicio = "Press inclinado"
        let otra = app(s)
        await otra.cargar()
        try? await Task.sleep(for: .milliseconds(300))
        #expect(otra.novedades?.lista.isEmpty == true)
        let d = Disco(raiz: raiz, token: Self.token)
        #expect(!FileManager.default.fileExists(atPath: d.url(ModeloNovedades.archivoBase).path))
        #expect(!FileManager.default.fileExists(atPath: d.url(ModeloNovedades.archivoLista).path))
    }

    @Test func laPalancaSeLeeDeLaClave() {
        #expect(!PalancaRemota(.objeto([:])).novedadesPlan)
        #expect(PalancaRemota(.objeto(["novedades_plan": .bool(true)])).novedadesPlan)
        #expect(!PalancaRemota(.objeto(["novedades_plan": .texto("true")])).novedadesPlan)
    }
}
