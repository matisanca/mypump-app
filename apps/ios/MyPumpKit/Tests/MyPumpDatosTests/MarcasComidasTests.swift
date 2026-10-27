import Foundation
import Testing
import MyPumpModelos
import MyPumpReglas
@testable import MyPumpDatos

/// «Comí» / «Salté» y lo consumido del día en el modelo (D25): salen por la cola con el payload de la web, se leen del
/// servidor (las de la web también), sin red quedan en el teléfono y en la cola, lo que se toca mientras viaja la lectura
/// no se pierde, y «Hoy no la como» saca la marca.
@Suite("Dieta: marcas de comidas y consumido", .serialized)
@MainActor
struct MarcasComidasTests {
    let raiz = FileManager.default.temporaryDirectory.appendingPathComponent("marcas-\(UUID().uuidString)")
    static let token = "AAAAAAAAAAAAAAAAAAAA"
    static let dieta = #"[{"id":"55555555-5555-4555-8555-555555555555","version":1,"estructura":{"macros_target":{"kcal":2000,"prot":150,"carb":200,"fat":60},"comidas":["#
        + #"{"id":"desayuno","name":"Desayuno","options":[{"name":"A","foods":[{"name":"Avena","qty":100,"unit":"g","kcal":380,"prot":13,"carb":67,"fat":7},{"name":"Huevos","qty":3,"unit":"u","kcal":234,"prot":18,"carb":0,"fat":18}]},{"name":"B","foods":[{"name":"Yogur","qty":200,"unit":"g","kcal":120,"prot":10,"carb":14,"fat":3}]}]},"#
        + #"{"id":"almuerzo","name":"Almuerzo","options":[{"name":"A","foods":[{"name":"Pollo","qty":200,"unit":"g","kcal":330,"prot":62,"carb":0,"fat":7},{"name":"Arroz","qty":150,"unit":"g","kcal":195,"prot":4,"carb":42,"fat":0.5}]}]}"#
        + "]}}]"

    /// El servidor de las marcas: una fila por (fecha, comida), como `mypump_comidas_marcadas`.
    final class Servidor: @unchecked Sendable {
        private let lock = NSLock()
        private var _filas: [String: [String: JSONValue]] = [:]
        private var _escrituras: [(String, JSONValue)] = []
        var sinRed = false
        /// La lectura contesta con lo que había al empezar, pero tarde.
        var lecturaLenta = false
        private var _leyendo = false
        var leyendo: Bool { lock.withLock { _leyendo } }
        var escrituras: [(String, JSONValue)] { lock.withLock { _escrituras } }
        func fila(_ id: String) -> [String: JSONValue]? { lock.withLock { _filas[id] } }
        func poner(_ id: String, _ f: [String: JSONValue]?) { lock.withLock { _filas[id] = f } }
        func foto() -> String {
            lock.withLock {
                let filas = _filas.values.map { JSONValue.objeto($0) }
                return String(data: try! JSONEncoder().encode(JSONValue.lista(filas)), encoding: .utf8)!
            }
        }
        func escribir(_ fn: String, _ c: JSONValue) {
            lock.withLock {
                _escrituras.append((fn, c))
                guard let id = c["p_comida_id"]?.comoTexto else { return }
                if fn == "mypump_desmarcar_comida" { _filas[id] = nil; return }
                _filas[id] = ["comida_id": .texto(id), "fecha": c["p_fecha"] ?? .null, "opcion_elegida": c["p_opcion"] ?? .null,
                              "estado": c["p_estado"] ?? .null, "foods_excluidos": c["p_foods_excluidos"] ?? .null]
            }
        }
        func empezarLectura(_ v: Bool) { lock.withLock { _leyendo = v } }
    }

    func modelo(_ s: Servidor) -> ModeloApp {
        let dieta = Self.dieta
        let t = TransporteProgramado { fn, cuerpo in
            if s.sinRed { throw URLError(.notConnectedToInternet) }
            switch fn {
            case "mypump_get_cliente_info": return (200, #"[{"cliente_id":"c1","nombre":"Cliente","perfil":"natural"}]"#)
            case "mypump_get_dieta_activa": return (200, dieta)
            case "mypump_get_comidas_marcadas":
                let foto = s.foto()
                if s.lecturaLenta {
                    s.empezarLectura(true)
                    for _ in 0..<300 where s.escrituras.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
                    try await Task.sleep(for: .milliseconds(50))
                    s.empezarLectura(false)
                }
                return (200, foto)
            case "mypump_marcar_comida":
                s.escribir(fn, cuerpo)
                return (200, "[\(s.foto())]")
            case "mypump_desmarcar_comida":
                s.escribir(fn, cuerpo)
                return (200, "true")
            default: return (200, "[]")
            }
        }
        return ModeloApp(cliente: ClienteRPC(config: .produccion, transporte: t), almacen: TokenEnMemoria(Self.token), raizDisco: raiz)
    }

    @Test func comiConLaOpcionQueSeVeYTocarDeNuevoDesmarca() async {
        let s = Servidor()
        let m = modelo(s)
        await m.cargar()
        #expect(m.marcasDeHoy.isEmpty && m.consumo(opciones: [:]).kcal == 0)
        await m.marcar("desayuno", .comido, opcion: 1)
        // Al toque, antes de que salga.
        #expect(m.marcasDeHoy["desayuno"] == MarcaComida(opcion: "B", estado: .comido))
        let c = m.consumo(opciones: [:])
        #expect(c.kcal == 120 && c.prot == 10 && c.hechas == 1 && c.comidas == 2)
        await m.outbox?.drenar()
        let w = s.escrituras.last
        #expect(w?.0 == "mypump_marcar_comida")
        #expect(w?.1["p_fecha"]?.comoTexto == FechaLocal.hoy() && w?.1["p_comida_id"]?.comoTexto == "desayuno")
        #expect(w?.1["p_opcion"]?.comoTexto == "B" && w?.1["p_estado"]?.comoTexto == "comido" && w?.1["p_foods_excluidos"] == .null)
        // Mirando la A, lo comido sigue siendo la B.
        #expect(m.consumo(opciones: ["desayuno": 0]).kcal == 120)
        // «Salté» pisa a «Comí»; desmarcar la borra del servidor.
        await m.marcar("desayuno", .saltado, opcion: 0)
        #expect(m.consumo(opciones: [:]).kcal == 0 && m.consumo(opciones: [:]).salteadas == 1)
        await m.marcar("desayuno", nil, opcion: 0)
        await m.outbox?.drenar()
        #expect(s.escrituras.last?.0 == "mypump_desmarcar_comida" && s.fila("desayuno") == nil)
        let quedan = await m.outbox?.pendientes
        #expect(m.marcasDeHoy.isEmpty && quedan == 0)
        // Una comida que no está en el plan no se marca.
        await m.marcar("cena", .comido, opcion: 0)
        #expect(m.marcasDeHoy.isEmpty)
    }

    @Test func destildarUnAlimentoLoDescuentaYVuelveATildar() async {
        let s = Servidor()
        let m = modelo(s)
        await m.cargar()
        await m.marcar("desayuno", .comido, opcion: 0)
        await m.alternarAlimento("desayuno", 1)
        #expect(m.marcasDeHoy["desayuno"]?.excluidos == [1])
        #expect(m.consumo(opciones: [:]).kcal == 380)
        await m.outbox?.drenar()
        #expect(s.escrituras.last?.1["p_foods_excluidos"] == .lista([.numero(1)]))
        // Una sola op por comida y día: la última gana.
        await m.alternarAlimento("desayuno", 0)
        await m.alternarAlimento("desayuno", 1)
        #expect(m.marcasDeHoy["desayuno"]?.excluidos == [0])
        await m.outbox?.drenar()
        #expect(s.fila("desayuno")?["foods_excluidos"] == .lista([.numero(0)]))
        await m.alternarAlimento("desayuno", 0)
        await m.outbox?.drenar()
        #expect(s.escrituras.last?.1["p_foods_excluidos"] == .null)
        #expect(m.consumo(opciones: [:]).kcal == 614)
        // Sin «Comí», destildar no hace nada.
        await m.alternarAlimento("almuerzo", 0)
        #expect(m.marcasDeHoy["almuerzo"] == nil)
    }

    @Test func lasDeLaWebSeVenAlCargarYAlVolver() async {
        let s = Servidor()
        s.poner("almuerzo", ["comida_id": .texto("almuerzo"), "opcion_elegida": .texto("A"), "estado": .texto("comido"),
                             "foods_excluidos": .lista([.numero(1)])])
        let m = modelo(s)
        await m.cargar()
        #expect(m.marcasDeHoy["almuerzo"] == MarcaComida(opcion: "A", estado: .comido, excluidos: [1]))
        #expect(m.consumo(opciones: [:]).kcal == 330)
        // La web la desmarca y marca el desayuno: al volver a la app se ve.
        s.poner("almuerzo", nil)
        s.poner("desayuno", ["comida_id": .texto("desayuno"), "opcion_elegida": .texto("A"), "estado": .texto("saltado")])
        await m.alVolverAPrimerPlano()
        #expect(m.marcasDeHoy == ["desayuno": MarcaComida(opcion: "A", estado: .saltado)])
    }

    @Test func sinRedQuedaEnElTelefonoYEnLaColaYGanaAlVolver() async {
        let s = Servidor()
        let m = modelo(s)
        await m.cargar()
        s.sinRed = true
        await m.marcar("almuerzo", .comido, opcion: 0)
        await m.alternarAlimento("almuerzo", 1)
        await m.outbox?.drenar()
        #expect(await m.outbox?.pendientes == 1)
        #expect(m.consumo(opciones: [:]).kcal == 330)
        // Otro arranque sin red: la copia offline y las marcas del teléfono.
        let otro = modelo(s)
        await otro.cargar()
        #expect(otro.marcasDeHoy["almuerzo"] == MarcaComida(opcion: "A", estado: .comido, excluidos: [1]))
        // Vuelve la red: el servidor todavía no la tiene, pero lo de la cola gana sobre lo que lee; después sale.
        s.sinRed = false
        await otro.hidratarMarcas()
        #expect(otro.marcasDeHoy["almuerzo"]?.excluidos == [1])
        await otro.outbox?.drenar()
        #expect(s.fila("almuerzo")?["foods_excluidos"] == .lista([.numero(1)]))
    }

    /// La lectura sale, el cliente marca, la escritura llega antes que la respuesta: la respuesta (sin la marca) no la
    /// borra (en la web, «la comida se desmarcaba sola al terminar la carga»).
    @Test func loQueSeTocaMientrasViajaLaLecturaNoSePierde() async throws {
        let s = Servidor()
        let m = modelo(s)
        await m.cargar()
        s.lecturaLenta = true
        async let lectura: Void = m.hidratarMarcas()
        for _ in 0..<200 where !s.leyendo { try await Task.sleep(for: .milliseconds(5)) }
        await m.marcar("desayuno", .comido, opcion: 0)
        await m.outbox?.drenar()
        await lectura
        #expect(m.marcasDeHoy["desayuno"]?.estado == .comido)
        s.lecturaLenta = false
        await m.hidratarMarcas()
        #expect(m.marcasDeHoy["desayuno"]?.estado == .comido)
    }

    @Test func hoyNoLaComoSacaLaMarcaYNoCuenta() async {
        let s = Servidor()
        let m = modelo(s)
        await m.cargar()
        await m.marcar("desayuno", .comido, opcion: 0)
        await m.marcar("almuerzo", .comido, opcion: 0)
        await m.outbox?.drenar()
        await m.ajustar("desayuno", AjusteComida(compensar: true, omitida: true), opciones: [:])
        #expect(m.marcasDeHoy["desayuno"] == nil)
        await m.outbox?.drenar()
        #expect(s.fila("desayuno") == nil)
        let c = m.consumo(opciones: [:])
        // El almuerzo se come con lo que le pasa el desayuno (porciones de hoy): más que su plan.
        #expect(c.comidas == 1 && c.hechas == 1 && c.kcal > 525)
        let dia = m.diaAjustado(opciones: [:])
        #expect(abs(c.kcal - AjustePorciones.kcal(dia["almuerzo"]!.alimentos)) < 1e-9)
    }

    @Test func alCambiarElDiaNoValenYLaDemoNoEscribe() async {
        let s = Servidor()
        let m = modelo(s)
        await m.cargar()
        await m.marcar("desayuno", .comido, opcion: 0)
        await m.outbox?.drenar()
        // Lo del teléfono de otro día no vale.
        m.fechaMarcas = "2000-01-01"
        #expect(m.marcasDeHoy.isEmpty)
        _ = m.disco?.guardar(MarcasGuardadas(fecha: "2000-01-01", marcas: ["almuerzo": MarcaComida(opcion: "A", estado: .comido)]),
                             ModeloApp.archivoMarcas)
        m.cargarMarcas()
        #expect(m.marcasDeHoy.isEmpty && m.fechaMarcas == FechaLocal.hoy())
        // Demo: en memoria, nada al servidor.
        let antes = s.escrituras.count
        let demo = modelo(s)
        demo.entrarEnDemo(rutina: Data("{}".utf8), dieta: Data(Self.dietaDemo.utf8))
        #expect(demo.marcasDeHoy.isEmpty)
        await demo.marcar("almuerzo", .comido, opcion: 0)
        await demo.alternarAlimento("almuerzo", 0)
        #expect(demo.marcasDeHoy["almuerzo"]?.excluidos == [0] && demo.consumo(opciones: [:]).kcal == 195)
        // Al salir, lo de la cuenta (el desayuno del servidor), sin lo de la demo.
        await demo.salirDeDemo()
        #expect(demo.marcasDeHoy["almuerzo"] == nil && demo.marcasDeHoy["desayuno"]?.estado == .comido)
        #expect(s.escrituras.count == antes)
    }

    static var dietaDemo: String {
        let d = try! JSONDecoder().decode(JSONValue.self, from: Data(dieta.utf8))
        guard case .lista(let filas) = d, let e = filas.first?["estructura"] else { return "{}" }
        return String(data: try! JSONEncoder().encode(e), encoding: .utf8)!
    }
}
