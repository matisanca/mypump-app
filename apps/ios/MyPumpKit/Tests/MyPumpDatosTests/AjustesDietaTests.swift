import Foundation
import Testing
import MyPumpModelos
import MyPumpReglas
@testable import MyPumpDatos

/// Los ajustes de porciones del día (feedback del 20-oct) en el modelo: quedan en el teléfono solo por hoy, salen por la
/// cola con el día entero (una op por día), sin la tabla (PGRST202) no se pierden ni avisan, y al hidratar gana lo del
/// teléfono que todavía no salió.
@Suite("Dieta: ajustes de porciones del día", .serialized)
@MainActor
struct AjustesDietaTests {
    let raiz = FileManager.default.temporaryDirectory.appendingPathComponent("ajustes-\(UUID().uuidString)")
    static let token = "AAAAAAAAAAAAAAAAAAAA"
    static let dietaId = "44444444-4444-4444-8444-444444444444"
    static let dieta = #"[{"id":"\#(dietaId)","version":1,"estructura":{"macros_target":{"kcal":2000,"prot":150,"carb":200,"fat":60},"comidas":["#
        + #"{"id":"desayuno","name":"Desayuno","options":[{"name":"A","foods":[{"name":"Avena","qty":100,"unit":"g","kcal":380,"prot":13,"carb":67,"fat":7},{"name":"Huevos","qty":3,"unit":"u","kcal":234,"prot":18,"carb":0,"fat":18}]},{"name":"B","foods":[{"name":"Yogur","qty":200,"unit":"g","kcal":120,"prot":10,"carb":14,"fat":3}]}]},"#
        + #"{"id":"almuerzo","name":"Almuerzo","options":[{"name":"A","foods":[{"name":"Pollo","qty":200,"unit":"g","kcal":330,"prot":62,"carb":0,"fat":7},{"name":"Arroz","qty":150,"unit":"g","kcal":195,"prot":4,"carb":42,"fat":0.5}]}]}"#
        + "]}}]"

    /// El servidor: guarda lo que le llega y contesta las lecturas. `sinTabla` = la migración nativa_004 no está.
    final class Servidor: @unchecked Sendable {
        private let lock = NSLock()
        private var _guardados: [JSONValue] = []
        var guardados: [JSONValue] { lock.withLock { _guardados } }
        var sinTabla = false
        /// La base rechaza el día (el 22023 de nativa_004 con un `ajustes` de más de 16000 bytes en jsonb).
        var rechaza = false
        /// `mypump_get_food_swaps` falla (un 500).
        var sinSwaps = false
        var filas = "[]"
        /// Otra estructura con el mismo id: Mati volvió a publicar (013 actualiza en el lugar).
        var dieta: String?
        /// La lectura de los ajustes contesta tarde: la escritura que sale después llega antes (revisión del 20-oct).
        var getLento = false
        private var _getEmpezo = false
        var getEmpezo: Bool { lock.withLock { _getEmpezo } }
        func marcarGet() { lock.withLock { _getEmpezo = true } }
        func guardar(_ c: JSONValue) { lock.withLock { _guardados.append(c) } }
        /// Dos teléfonos de la misma cuenta: lo que guarda uno es lo que lee el otro (el día de ajustes y las marcas).
        var persistente = false
        /// Las marcas no salen (sin red para esa escritura): quedan en la cola.
        var marcasCaidas = false
        private var _marcas: [String: JSONValue] = [:]
        private var _marcasEscritas = 0
        var marcasEscritas: Int { lock.withLock { _marcasEscritas } }
        var marcasFilas: String {
            lock.withLock { String(data: try! JSONEncoder().encode(JSONValue.lista(Array(_marcas.values))), encoding: .utf8)! }
        }
        func guardarMarca(_ c: JSONValue) {
            lock.withLock {
                _marcasEscritas += 1
                guard let id = c["p_comida_id"]?.comoTexto else { return }
                _marcas[id] = .objeto(["comida_id": .texto(id), "opcion_elegida": c["p_opcion"] ?? .null, "estado": c["p_estado"] ?? .null,
                                       "foods_excluidos": c["p_foods_excluidos"] ?? .lista([])])
            }
        }
        func desmarcar(_ c: JSONValue) { lock.withLock { _marcasEscritas += 1; if let id = c["p_comida_id"]?.comoTexto { _marcas[id] = nil } } }
        func marcaDelServidor(_ id: String) -> JSONValue? { lock.withLock { _marcas[id] } }
    }

    func modelo(_ s: Servidor, raiz otra: URL? = nil) -> ModeloApp {
        let dieta = Self.dieta
        let t = TransporteProgramado { fn, cuerpo in
            switch fn {
            case "mypump_get_cliente_info": return (200, #"[{"cliente_id":"c1","nombre":"Cliente","perfil":"natural"}]"#)
            case "mypump_get_dieta_activa": return (200, s.dieta ?? dieta)
            case "mypump_guardar_ajustes_dieta":
                if s.sinTabla { return (404, #"{"code":"PGRST202","message":"Could not find the function"}"#) }
                if s.rechaza { return (400, #"{"code":"22023","message":"ajustes invalidos"}"#) }
                s.guardar(cuerpo)
                if s.persistente {
                    let fila: JSONValue = .lista([.objeto(["fecha": cuerpo["p_fecha"] ?? .null, "dieta_id": cuerpo["p_dieta_id"] ?? .null,
                                                           "tipo_dia": .null, "ajustes": cuerpo["p_ajustes"] ?? .objeto([:])])])
                    s.filas = String(data: try JSONEncoder().encode(fila), encoding: .utf8)!
                }
                return (200, "true")
            case "mypump_marcar_comida":
                if s.marcasCaidas { return (503, #"{"message":"sin red"}"#) }
                s.guardarMarca(cuerpo)
                return (200, "true")
            case "mypump_desmarcar_comida":
                s.desmarcar(cuerpo)
                return (200, "true")
            case "mypump_get_comidas_marcadas" where s.persistente: return (200, s.marcasFilas)
            case "mypump_get_food_swaps" where s.sinSwaps: return (500, #"{"message":"caído"}"#)
            case "mypump_get_ajustes_dieta":
                if s.sinTabla { return (404, #"{"code":"PGRST202","message":"Could not find the function"}"#) }
                let foto = s.filas   // lo que tiene el servidor cuando lee
                s.marcarGet()
                if s.getLento {
                    for _ in 0..<300 where s.guardados.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
                    try await Task.sleep(for: .milliseconds(50))
                }
                return (200, foto)
            case "mypump_save_food_swap", "mypump_delete_food_swap": return (200, "true")
            default: return (200, "[]")
            }
        }
        return ModeloApp(cliente: ClienteRPC(config: .produccion, transporte: t), almacen: TokenEnMemoria(Self.token), raizDisco: otra ?? raiz)
    }

    @Test func ajustarCambiaElDiaLoGuardaYLoMandaEntero() async {
        let s = Servidor()
        let m = modelo(s)
        await m.cargar()
        await m.outbox?.drenar()
        #expect(m.ajustesDeHoy.isEmpty)
        await m.ajustar("desayuno", AjusteComida(deltaKcal: 200), opciones: [:])
        let dia = m.diaAjustado(opciones: [:])
        #expect(dia["desayuno"]!.kcal > dia["desayuno"]!.kcalPlan && dia["almuerzo"]!.kcal < dia["almuerzo"]!.kcalPlan, "compensa en el almuerzo")
        // La cola puede haberla mandado ya; si sigue ahí, es UNA, del día.
        let ops = await m.outbox?.operaciones ?? []
        #expect(ops.count <= 1 && ops.allSatisfy { $0.kind == ModeloApp.kindAjustes && $0.dedupeKey == "ajustes_dieta_\(FechaLocal.hoy())" })
        await m.outbox?.drenar()
        #expect(await m.outbox?.pendientes == 0)
        let g = s.guardados.last
        #expect(g?["p_fecha"]?.comoTexto == FechaLocal.hoy() && g?["p_dieta_id"]?.comoTexto == Self.dietaId)
        #expect(g?["p_ajustes"]?["desayuno"]?["deltaKcal"]?.comoNumero == 200)
        guard case .lista(let resumen)? = g?["p_resumen"] else { Issue.record("sin resumen"); return }
        #expect(resumen.map { $0["comida_id"]?.comoTexto } == ["desayuno", "almuerzo"])
        #expect(g?["p_kcal_plan"]?.comoNumero == dia.values.reduce(0) { $0 + $1.kcalPlan })
        #expect(g?["p_kcal_dia"]?.comoNumero == dia.values.reduce(0) { $0 + $1.kcal })

        // Otro arranque (sin red para los ajustes) lo encuentra en el teléfono.
        let otro = modelo(s)
        await otro.cargar()
        #expect(otro.ajustesDeHoy["desayuno"]?.deltaKcal == 200)
    }

    /// La cola puede mandar cada cambio apenas llega (con red), pero nunca quedan dos ops del mismo día y lo último que
    /// recibe el servidor es el estado final (la hoja de ajustes junta los toques y guarda una vez, con «Listo»).
    @Test func variosCambiosSeguidosDejanUnaOpYLaUltimaGana() async {
        let s = Servidor()
        let m = modelo(s)
        await m.cargar()
        await m.outbox?.drenar()
        await m.ajustar("desayuno", AjusteComida(deltaKcal: 50), opciones: [:])
        await m.ajustar("desayuno", AjusteComida(deltaKcal: 100), opciones: [:])
        await m.ajustar("almuerzo", AjusteComida(deltaKcal: -50, compensar: false), opciones: [:])
        #expect((await m.outbox?.operaciones ?? []).count <= 1)
        await m.outbox?.drenar()
        #expect(await m.outbox?.pendientes == 0)
        let ultimo = s.guardados.last
        #expect(ultimo?["p_ajustes"]?["desayuno"]?["deltaKcal"]?.comoNumero == 100)
        #expect(ultimo?["p_ajustes"]?["almuerzo"]?["compensar"] == .bool(false))
    }

    @Test func volverAlPlanMandaElDiaVacio() async {
        let s = Servidor()
        let m = modelo(s)
        await m.cargar()
        await m.outbox?.drenar()
        await m.ajustar("desayuno", AjusteComida(deltaKcal: 100), opciones: [:])
        await m.outbox?.drenar()
        await m.ajustar("desayuno", nil, opciones: [:])
        #expect(m.ajustesDeHoy.isEmpty)
        await m.outbox?.drenar()
        #expect(s.guardados.last?["p_ajustes"] == .objeto([:]) && s.guardados.last?["p_resumen"] == .null)
        // Un ajuste neutro (sin kcal, sin gramos, comiéndola) es lo mismo que sacarlo.
        await m.ajustar("desayuno", AjusteComida(), opciones: [:])
        #expect((await m.outbox?.operaciones ?? []).isEmpty, "nada cambió: no hay nada que mandar")
    }

    @Test func sinLaTablaQuedaEnElTelefonoSinAvisosNiFallidos() async {
        let s = Servidor()
        s.sinTabla = true
        let m = modelo(s)
        await m.cargar()
        await m.outbox?.drenar()
        await m.ajustar("desayuno", AjusteComida(omitida: true), opciones: [:])
        await m.outbox?.drenar()
        #expect(await m.outbox?.pendientes == 0)
        #expect((await m.outbox?.fallidos ?? []).isEmpty)
        #expect(m.ajustesDeHoy["desayuno"]?.omitida == true)
    }

    /// Revisión adversarial del 3-nov: un día que la base rechaza termina en fallidos; la hidratación ya no lo veía
    /// pendiente y la fila vieja del servidor pisaba el día del teléfono sin aviso. Ahora no lo pisa, Dieta avisa y el
    /// próximo cambio que sale lo resuelve.
    @Test func unDiaQueLaBaseRechazaNoLoPisaLaHidratacionYSeAvisa() async throws {
        let s = Servidor()
        s.rechaza = true
        let m = modelo(s)
        await m.cargar()
        await m.ajustar("desayuno", AjusteComida(deltaKcal: 50), opciones: [:])
        for _ in 0..<12 {
            if (await m.outbox?.pendientes ?? 0) == 0 { break }
            await m.outbox?.drenar()
        }
        #expect(await m.outbox?.pendientes == 0)
        #expect((await m.outbox?.fallidos ?? []).count == 1)
        for _ in 0..<100 where !m.ajustesSinGuardar { try await Task.sleep(for: .milliseconds(10)) }
        #expect(m.ajustesSinGuardar, "Dieta avisa que no se guardó")

        // La fila vieja del servidor no pisa el día del teléfono.
        let hoy = FechaLocal.hoy()
        s.filas = #"[{"fecha":"\#(hoy)","dieta_id":"\#(Self.dietaId)","tipo_dia":null,"ajustes":{"almuerzo":{"deltaKcal":-100,"compensar":false,"omitida":false,"opcion":0,"cantidades":{}}}}]"#
        await m.hidratarDieta()
        #expect(m.ajustesDeHoy["desayuno"]?.deltaKcal == 50 && m.ajustesDeHoy["almuerzo"] == nil)
        #expect(m.ajustesSinGuardar)

        // El próximo cambio sale entero: el aviso se va y el fallido de ese día se olvida (la hidratación vuelve a valer).
        s.rechaza = false
        await m.ajustar("desayuno", AjusteComida(deltaKcal: 100), opciones: [:])
        await m.outbox?.drenar()
        for _ in 0..<100 {
            let quedan = await m.outbox?.fallidos ?? []
            if !m.ajustesSinGuardar && quedan.isEmpty { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(!m.ajustesSinGuardar)
        #expect((await m.outbox?.fallidos ?? []).isEmpty)
        await m.hidratarDieta()
        #expect(m.ajustesDeHoy["almuerzo"]?.deltaKcal == -100, "con el día guardado, lo del servidor vuelve a valer")
    }

    /// El aviso que quedó de ayer (la app abierta pasada la medianoche) se apaga con la hidratación cuando hoy no hay
    /// fallidos, aunque el servidor no conteste.
    @Test func elAvisoDeAyerSeApagaAlHidratarSinFallidosDeHoy() async {
        let s = Servidor()
        let m = modelo(s)
        await m.cargar()
        m.ajustesSinGuardar = true   // lo que dejó el día anterior
        s.sinTabla = true            // tampoco hace falta que el servidor conteste
        await m.hidratarDieta()
        #expect(!m.ajustesSinGuardar)
    }

    @Test func alHidratarGanaLoDelServidorSalvoQueHayaAlgoSinSalir() async {
        let s = Servidor()
        let hoy = FechaLocal.hoy()
        s.filas = #"[{"fecha":"\#(hoy)","dieta_id":"\#(Self.dietaId)","tipo_dia":null,"ajustes":{"almuerzo":{"deltaKcal":-100,"compensar":false,"omitida":false,"opcion":0,"cantidades":{}}}}]"#
        let m = modelo(s)
        await m.cargar()
        #expect(m.ajustesDeHoy["almuerzo"]?.deltaKcal == -100, "lo de otro teléfono")

        // Con un cambio local que todavía no salió, lo del servidor no lo pisa.
        await m.ajustar("desayuno", AjusteComida(deltaKcal: 50), opciones: [:])
        s.filas = "[]"
        await m.hidratarDieta()
        #expect(m.ajustesDeHoy["desayuno"]?.deltaKcal == 50 && m.ajustesDeHoy["almuerzo"]?.deltaKcal == -100)
    }

    /// Sin los reemplazos del servidor (falló esa lectura), los ajustes se hidratan igual.
    @Test func sinLosReemplazosLosAjustesSeHidratanIgual() async {
        let s = Servidor()
        s.sinSwaps = true
        s.filas = #"[{"fecha":"\#(FechaLocal.hoy())","dieta_id":"\#(Self.dietaId)","ajustes":{"almuerzo":{"deltaKcal":-100}}}]"#
        let m = modelo(s)
        await m.cargar()
        #expect(m.ajustesDeHoy["almuerzo"]?.deltaKcal == -100)
    }

    /// Revisión del 20-oct: un cambio hecho mientras la hidratación espera al servidor llegaba antes que la respuesta (la
    /// cola manda al toque) y la foto vieja del servidor lo pisaba; el cambio siguiente borraba también lo del servidor.
    @Test func unCambioDuranteLaHidratacionNoSePierde() async throws {
        let s = Servidor()
        s.filas = #"[{"fecha":"\#(FechaLocal.hoy())","dieta_id":"\#(Self.dietaId)","ajustes":{}}]"#
        s.getLento = true
        let m = modelo(s)
        let carga = Task { await m.cargar() }
        for _ in 0..<500 where !s.getEmpezo { try await Task.sleep(for: .milliseconds(10)) }
        #expect(s.getEmpezo)
        await m.ajustar("desayuno", AjusteComida(deltaKcal: 100), opciones: [:])
        await carga.value
        #expect(m.ajustesDeHoy["desayuno"]?.deltaKcal == 100, "el cambio sobrevive a la hidratación")
        await m.ajustar("almuerzo", AjusteComida(deltaKcal: -50), opciones: [:])
        await m.outbox?.drenar()
        #expect(s.guardados.last?["p_ajustes"]?["desayuno"]?["deltaKcal"]?.comoNumero == 100, "y el siguiente no lo borra del servidor")
    }

    /// El resumen que ve Mati son las kcal del plan de hoy: otra opción a la vista o un reemplazo, aun en una comida sin
    /// ajuste, lo cambian (revisión del 20-oct).
    @Test func otraOpcionOUnReemplazoRehacenElResumen() async {
        let s = Servidor()
        let m = modelo(s)
        await m.cargar()
        await m.ajustar("almuerzo", AjusteComida(deltaKcal: -50, compensar: false), opciones: [:])
        await m.outbox?.drenar()
        func planDelDesayuno() -> Double? {
            guard case .lista(let r)? = s.guardados.last?["p_resumen"] else { return nil }
            return r.first { $0["comida_id"]?.comoTexto == "desayuno" }?["kcal_plan"]?.comoNumero
        }
        #expect(planDelDesayuno() == 614)
        await m.verOpcion("desayuno", 1)
        await m.outbox?.drenar()
        #expect(planDelDesayuno() == 120, "el yogur de la B")
        await m.verOpcion("desayuno", 0)
        let avena = m.comidasDelDia[0].opciones[0].alimentos[0]
        await m.sustituir(avena, por: .objeto(["name": .texto("Pan integral"), "qty": .numero(2), "unit": .texto("rebanada"),
                                                "kcal": .numero(140), "prot": .numero(6), "carb": .numero(24), "fat": .numero(2)]),
                          comidaId: "desayuno", opt: 0, idx: 0)
        await m.outbox?.drenar()
        #expect(planDelDesayuno() == 374, "el pan (140) y los huevos (234)")
    }

    @Test func lasOpcionesVistasNoPasanALaDemo() async {
        let s = Servidor()
        let m = modelo(s)
        await m.cargar()
        await m.verOpcion("desayuno", 1)
        #expect(m.opcionesVistas["desayuno"] == 1)
        m.entrarEnDemo(rutina: Data(#"{"dias":[]}"#.utf8), dieta: Data(#"{"comidas":[]}"#.utf8))
        #expect(m.opcionesVistas.isEmpty)
    }

    @Test func otraDietaEnElServidorNoSeMezcla() async {
        let s = Servidor()
        s.filas = #"[{"fecha":"\#(FechaLocal.hoy())","dieta_id":"55555555-5555-4555-8555-555555555555","ajustes":{"desayuno":{"deltaKcal":300}}}]"#
        let m = modelo(s)
        await m.cargar()
        #expect(m.ajustesDeHoy.isEmpty)
    }

    @Test func siElServidorNoTieneNadaYElTelefonoSiSeSube() async {
        // Lo que se ajustó antes de la migración (salió «sin tabla») sube en la primera hidratación con la tabla.
        let s = Servidor()
        let disco = Disco(raiz: raiz, token: Self.token)
        _ = disco.guardar(AjustesGuardados(fecha: FechaLocal.hoy(), comidas: ["desayuno": AjusteComida(deltaKcal: 150)]),
                          ModeloApp.archivoAjustes(Self.dietaId))
        let m = modelo(s)
        await m.cargar()
        await m.outbox?.drenar()
        #expect(s.guardados.last?["p_ajustes"]?["desayuno"]?["deltaKcal"]?.comoNumero == 150)
    }

    @Test func losDeAyerNoValen() async {
        let s = Servidor()
        let disco = Disco(raiz: raiz, token: Self.token)
        _ = disco.guardar(AjustesGuardados(fecha: "2026-01-01", comidas: ["desayuno": AjusteComida(deltaKcal: 150)]),
                          ModeloApp.archivoAjustes(Self.dietaId))
        let m = modelo(s)
        await m.cargar()
        #expect(m.ajustesDeHoy.isEmpty)
    }

    @Test func laOpcionElegidaVaEnLaCuentaYLasCantidadesDeOtraNoValen() async {
        let s = Servidor()
        let m = modelo(s)
        await m.cargar()
        await m.ajustar("desayuno", AjusteComida(opcion: 0, cantidades: ["0": 50]), opciones: ["desayuno": 0])
        #expect(m.diaAjustado(opciones: ["desayuno": 0])["desayuno"]!.alimentos[0].qty == 50)
        // Con la opción B a la vista, las cantidades de la A no se aplican.
        let b = m.diaAjustado(opciones: ["desayuno": 1])["desayuno"]!
        #expect(b.alimentos.map(\.nombre) == ["Yogur"] && b.alimentos[0].qty == 200)
        // Sin decir cuál se ve, la del ajuste.
        #expect(m.comidasParaAjustar(opciones: [:]).first?.opcion == 0)
    }

    /// La dieta se vuelve a publicar con el mismo id: si en la posición de una cantidad a mano queda otro alimento, esa
    /// cantidad no vale (los 60 g de avena no pueden pasar a ser 60 huevos).
    @Test func lasCantidadesAManoQuedanAncladasAlAlimento() async {
        let s = Servidor()
        let m = modelo(s)
        await m.cargar()
        await m.ajustar("desayuno", AjusteComida(deltaKcal: 50, opcion: 0, cantidades: ["0": 60]), opciones: ["desayuno": 0])
        #expect(m.ajustesDeHoy["desayuno"]?.anclas == ["0": AnclaAlimento(nombre: "Avena", unidad: "g")])
        await m.outbox?.drenar()
        #expect(s.guardados.last?["p_ajustes"]?["desayuno"]?["anclas"]?["0"]?["nombre"]?.comoTexto == "Avena")
        // Mati invierte el orden de los alimentos del desayuno.
        s.dieta = Self.dieta.replacingOccurrences(
            of: #"{"name":"Avena","qty":100,"unit":"g","kcal":380,"prot":13,"carb":67,"fat":7},{"name":"Huevos","qty":3,"unit":"u","kcal":234,"prot":18,"carb":0,"fat":18}"#,
            with: #"{"name":"Huevos","qty":3,"unit":"u","kcal":234,"prot":18,"carb":0,"fat":18},{"name":"Avena","qty":100,"unit":"g","kcal":380,"prot":13,"carb":67,"fat":7}"#)
            .replacingOccurrences(of: #""version":1"#, with: #""version":2"#)
        #expect(s.dieta != Self.dieta)
        await m.cargar()
        let d = m.diaAjustado(opciones: ["desayuno": 0])["desayuno"]!
        #expect(d.alimentos.map(\.nombre) == ["Huevos", "Avena"])
        #expect(d.alimentos[0].qty != 60, "los 60 eran de avena")
        #expect(d.kcal > d.kcalPlan, "las +50 siguen")
    }

    /// 60 g de avena a mano y después la reemplaza por pan: los «60» no pueden quedar pegados al pan (60 rebanadas).
    @Test func unReemplazoSueltaLaCantidadAManoDeEseAlimento() async {
        let s = Servidor()
        let m = modelo(s)
        await m.cargar()
        // Sin kcal sumadas: con los dos alimentos a mano no queda nada que escalar y se acotarían a cero.
        await m.ajustar("desayuno", AjusteComida(opcion: 0, cantidades: ["0": 60, "1": 4]), opciones: ["desayuno": 0])
        let avena = m.comidasDelDia[0].opciones[0].alimentos[0]
        await m.sustituir(avena, por: .objeto(["name": .texto("Pan integral"), "qty": .numero(2), "unit": .texto("rebanada"),
                                                "kcal": .numero(140), "prot": .numero(6), "carb": .numero(24), "fat": .numero(2)]),
                          comidaId: "desayuno", opt: 0, idx: 0)
        #expect(m.ajustesDeHoy["desayuno"]?.cantidades == ["1": 4], "la de la avena se va, la de los huevos queda")
        await m.revertir(comidaId: "desayuno", opt: 0, idx: 1)
        #expect(m.ajustesDeHoy["desayuno"] == nil, "sin nada a mano ni kcal, el ajuste se va")
    }

    @Test func enLaDemoNoSeEscribeNada() async {
        let m = ModeloApp(cliente: ClienteRPC(config: .produccion, transporte: TransporteProgramado { _, _ in (200, "[]") }),
                          almacen: TokenEnMemoria(nil), raizDisco: raiz)
        let rutina = Data(#"{"dias":[]}"#.utf8)
        let dieta = Data(#"{"macros_target":{"kcal":2000},"comidas":[{"id":"d","name":"Desayuno","options":[{"name":"A","foods":[{"name":"Avena","qty":100,"unit":"g","kcal":380,"prot":13,"carb":67,"fat":7}]}]}]}"#.utf8)
        m.entrarEnDemo(rutina: rutina, dieta: dieta)
        await m.ajustar("d", AjusteComida(deltaKcal: 100), opciones: [:])
        #expect(m.ajustesDeHoy["d"]?.deltaKcal == 100, "en la demo se puede probar")
        #expect(m.outbox == nil)
    }

    // MARK: - Alimentos agregados (2.0.3, D1)

    static func huevo(_ ts: Int64) -> AlimentoAgregado {
        AgregadosComida.agregado(AgregadosComida.Candidato(nombre: "Huevo entero", por100: MacrosPor100(kcal: 143, p: 12.6, c: 0.7, g: 9.5),
                                                           unidad: "unidad", gramosPorUnidad: 60, origen: .base),
                                 cantidad: 1, medida: AgregadosComida.Medida(nombre: "unidad", gramos: 60), ts: ts)
    }

    /// Un agregado solo (sin otro cambio) ya es un ajuste: se guarda, sale con el día y va en el resumen de esa comida.
    @Test func unAgregadoSaleConElDiaYVaEnElResumen() async {
        let s = Servidor()
        let m = modelo(s)
        await m.cargar()
        await m.outbox?.drenar()
        await m.ajustar("desayuno", AjusteComida(compensar: false, agregados: [Self.huevo(1)]), opciones: [:])
        #expect(m.ajustesDeHoy["desayuno"]?.agregados.count == 1)
        #expect(m.diaAjustado(opciones: [:])["desayuno"]!.kcal == 614 + 86)
        await m.outbox?.drenar()
        let g = s.guardados.last
        #expect(g?["p_ajustes"]?["desayuno"]?["agregados"]?[0]?["nombre"]?.comoTexto == "Huevo entero")
        let kcalDia = g?["p_kcal_dia"]?.comoNumero ?? 0
        #expect(abs(kcalDia - (614 + 525 + 86)) < 1e-9)
        guard case .lista(let resumen)? = g?["p_resumen"] else { Issue.record("sin resumen"); return }
        #expect(resumen[0]["agregados"]?[0]?["kcal"]?.comoNumero == 86 && resumen[0]["agregados"]?[0]?["gramos"]?.comoNumero == 60)
        // El almuerzo, sin agregados, queda como antes (sin la clave).
        #expect(resumen[1]["agregados"] == nil)
        // Al volver a abrir (otro arranque) lo lee del disco.
        let otra = modelo(Servidor())
        await otra.cargar()
        #expect(otra.ajustesDeHoy["desayuno"]?.agregados.map(\.ts) == [1])
    }

    /// Borrar un agregado de una comida marcada «Comí»: el tilde del borrado se va y los de los siguientes bajan uno.
    @Test func borrarUnAgregadoCorreLosTildes() async {
        let s = Servidor()
        let m = modelo(s)
        await m.cargar()
        await m.ajustar("desayuno", AjusteComida(compensar: false, agregados: [Self.huevo(1), Self.huevo(2), Self.huevo(3)]), opciones: [:])
        await m.marcar("desayuno", .comido, opcion: 0)
        // Plan de 2 (avena, huevos): los agregados son 2, 3 y 4. Destilda el segundo y el tercero.
        await m.alternarAlimento("desayuno", 3)
        await m.alternarAlimento("desayuno", 4)
        await m.borrarAgregado("desayuno", ts: 2, opciones: [:])
        #expect(m.ajustesDeHoy["desayuno"]?.agregados.map(\.ts) == [1, 3])
        #expect(m.marcasDeHoy["desayuno"]?.excluidos == [3])
        // Lo consumido: el plan entero y el primer huevo.
        #expect(m.consumo(opciones: [:]).kcal == 614 + 86)
        // Sin agregados ni otro cambio, el ajuste se va.
        await m.borrarAgregado("desayuno", ts: 1, opciones: [:])
        await m.borrarAgregado("desayuno", ts: 3, opciones: [:])
        #expect(m.ajustesDeHoy["desayuno"] == nil && m.marcasDeHoy["desayuno"]?.excluidos == [])
    }

    /// Revisión del 3-nov: «Volver al plan» (o una hidratación con menos agregados) dejaba en la marca tildes de agregados
    /// que ya no estaban, y el próximo agregado aparecía destildado. Los tildes siguen a cada agregado por su `_ts`.
    @Test func volverAlPlanNoDejaTildesDeAgregadosViejos() async {
        let m = modelo(Servidor())
        await m.cargar()
        await m.ajustar("desayuno", AjusteComida(compensar: false, agregados: [Self.huevo(1), Self.huevo(2)]), opciones: [:])
        await m.marcar("desayuno", .comido, opcion: 0)
        await m.alternarAlimento("desayuno", 0)   // la avena (del plan)
        await m.alternarAlimento("desayuno", 3)   // el segundo huevo
        #expect(m.marcasDeHoy["desayuno"]?.excluidos == [0, 3])
        await m.ajustar("desayuno", nil, opciones: [:])
        #expect(m.marcasDeHoy["desayuno"]?.excluidos == [0], "el del plan queda; el del agregado se va")
        await m.ajustar("desayuno", AjusteComida(compensar: false, agregados: [Self.huevo(5), Self.huevo(6)]), opciones: [:])
        #expect(m.consumo(opciones: [:]).kcal == 234 + 86 * 2, "los agregados nuevos llegan tildados")
    }

    /// Dos «Sacar» seguidos sin esperar (dos toques rápidos): cada uno saca el suyo y los tildes quedan bien.
    @Test func dosBorradosSeguidosNoCorrenMalLosTildes() async {
        let m = modelo(Servidor())
        await m.cargar()
        await m.ajustar("desayuno", AjusteComida(compensar: false, agregados: [Self.huevo(1), Self.huevo(2), Self.huevo(3)]), opciones: [:])
        await m.marcar("desayuno", .comido, opcion: 0)
        await m.alternarAlimento("desayuno", 4)   // el tercer huevo
        async let a: Void = m.borrarAgregado("desayuno", ts: 1, opciones: [:])
        async let b: Void = m.borrarAgregado("desayuno", ts: 2, opciones: [:])
        async let c: Void = m.borrarAgregado("desayuno", ts: 2, opciones: [:])
        _ = await (a, b, c)
        #expect(m.ajustesDeHoy["desayuno"]?.agregados.map(\.ts) == [3])
        #expect(m.marcasDeHoy["desayuno"]?.excluidos == [2], "el tercero sigue destildado, ahora en el índice 2")
    }

    /// Segunda revisión del 3-nov: la hidratación de los ajustes corría los tildes ENCOLANDO una marca. Como en el arranque
    /// los ajustes se hidratan antes que las marcas, la marca vieja de este teléfono quedaba en la cola y le ganaba a la
    /// más nueva de otro: se perdían las exclusiones del otro teléfono. Ahora se remapea solo en memoria.
    @Test func laHidratacionNoPisaLaMarcaDeOtroTelefono() async throws {
        let s = Servidor()
        s.persistente = true
        let otraRaiz = FileManager.default.temporaryDirectory.appendingPathComponent("ajustes-b-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: otraRaiz) }
        // Teléfono A: dos huevos agregados, «Comí» y destilda el segundo (índice 3: plan de 2 + agregado 1).
        let a = modelo(s)
        await a.cargar()
        await a.ajustar("desayuno", AjusteComida(compensar: false, agregados: [Self.huevo(1), Self.huevo(2)]), opciones: [:])
        await a.marcar("desayuno", .comido, opcion: 0)
        await a.alternarAlimento("desayuno", 3)
        await a.outbox?.drenar()
        #expect(await a.outbox?.pendientes == 0)

        // Teléfono B: lo lee, saca el primer huevo (el segundo pasa al índice 2) y destilda la avena.
        let b = modelo(s, raiz: otraRaiz)
        await b.cargar()
        #expect(b.marcasDeHoy["desayuno"]?.excluidos == [3])
        await b.borrarAgregado("desayuno", ts: 1, opciones: [:])
        await b.alternarAlimento("desayuno", 0)
        await b.outbox?.drenar()
        #expect(await b.outbox?.pendientes == 0)
        #expect(Set(b.marcasDeHoy["desayuno"]?.excluidos ?? []) == [0, 2])
        let escritas = s.marcasEscritas

        // A vuelve a abrir: trae el día de B y su marca, sin mandar la suya vieja.
        await a.cargar()
        #expect(a.ajustesDeHoy["desayuno"]?.agregados.map(\.ts) == [2])
        #expect(Set(a.marcasDeHoy["desayuno"]?.excluidos ?? []) == [0, 2], "la marca de B, no la vieja de A remapeada")
        #expect((await a.outbox?.pendientesPorClave() ?? [:]).keys.allSatisfy { !$0.hasPrefix("comida|") })
        #expect(s.marcasEscritas == escritas, "A no escribió ninguna marca")
        if case .lista(let excl)? = s.marcaDelServidor("desayuno")?["foods_excluidos"] {
            #expect(Set(excl.compactMap { $0.comoNumero.map { Int($0) } }) == [0, 2])
        } else { Issue.record("el servidor perdió la marca") }
    }

    /// Con una marca de esa comida todavía en la cola (lo último que hizo el cliente en este teléfono), la hidratación sí
    /// corrige la cola: si no, saldría con los índices viejos.
    @Test func conUnaMarcaEnLaColaLaHidratacionLaCorrigeEnLaCola() async throws {
        let s = Servidor()
        s.persistente = true
        let a = modelo(s)
        await a.cargar()
        await a.ajustar("desayuno", AjusteComida(compensar: false, agregados: [Self.huevo(1), Self.huevo(2)]), opciones: [:])
        await a.outbox?.drenar()
        s.marcasCaidas = true
        await a.marcar("desayuno", .comido, opcion: 0)
        await a.alternarAlimento("desayuno", 3)   // queda en la cola: esa escritura no sale
        // Otro teléfono sacó el primer huevo.
        let hoy = FechaLocal.hoy()
        let dia = AjusteComida(compensar: false, agregados: [Self.huevo(2)])
        let ajustes = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(["desayuno": dia]))
        s.filas = String(data: try JSONEncoder().encode(JSONValue.lista([.objeto(["fecha": .texto(hoy), "dieta_id": .texto(Self.dietaId),
                                                                                 "tipo_dia": .null, "ajustes": ajustes])])), encoding: .utf8)!
        await a.hidratarDieta()
        #expect(a.ajustesDeHoy["desayuno"]?.agregados.map(\.ts) == [2])
        #expect(a.marcasDeHoy["desayuno"]?.excluidos == [2])
        let op = try #require((await a.outbox?.pendientesPorClave() ?? [:])["comida|\(hoy)|desayuno"])
        #expect(ModeloApp.marcaDelPayload(op.payload)?.excluidos == [2], "la cola sale con el índice nuevo")
    }

    /// Cambiar de opción saca las cantidades a mano (eran de la otra) pero deja los agregados.
    @Test func losAgregadosSobrevivenAlCambioDeOpcion() async {
        let s = Servidor()
        let m = modelo(s)
        await m.cargar()
        await m.ajustar("desayuno", AjusteComida(cantidades: ["0": 50], agregados: [Self.huevo(1)]), opciones: ["desayuno": 0])
        var a = m.ajustesDeHoy["desayuno"]!
        a.opcion = 1
        a.cantidades = [:]
        await m.ajustar("desayuno", a, opciones: ["desayuno": 1])
        #expect(m.ajustesDeHoy["desayuno"]?.agregados.count == 1 && m.ajustesDeHoy["desayuno"]?.cantidades.isEmpty == true)
        #expect(m.diaAjustado(opciones: ["desayuno": 1])["desayuno"]!.kcal == 120 + 86)
    }

    @Test func losRecientesQuedanEnElTelefono() async {
        let m = modelo(Servidor())
        await m.cargar()
        m.recordarReciente(Self.huevo(1))
        var otro = Self.huevo(2)
        otro.nombre = "Clara de huevo"
        m.recordarReciente(otro)
        m.recordarReciente(Self.huevo(3))
        #expect(m.agregadosRecientes.map(\.ts) == [3, 2])
        let otra = modelo(Servidor())
        await otra.cargar()
        #expect(otra.agregadosRecientes.map(\.nombre) == ["Huevo entero", "Clara de huevo"])
    }
}

private extension JSONValue {
    subscript(i: Int) -> JSONValue? {
        guard case .lista(let a) = self, a.indices.contains(i) else { return nil }
        return a[i]
    }
}
