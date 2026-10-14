import Foundation
import Testing
import MyPumpModelos
@testable import MyPumpDatos
@testable import MyPumpReglas

/// Regresiones de la revisión adversarial del 14-oct: cada test reproduce una falla real que se encontró en el código
/// (carreras de token, cola trabada, plan que desaparecía, demo que escribía, badge del chat…). Tienen que pasar siempre.
private let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../../../..").standardizedFileURL

/// Transporte programable: decide por nombre de función y token. Anota cada llamada.
final class TransporteProgramado: Transporte, @unchecked Sendable {
    typealias Regla = @Sendable (_ fn: String, _ cuerpo: JSONValue) async throws -> (Int, String)
    private let lock = NSLock()
    private var _llamadas: [String] = []
    var llamadas: [String] { lock.withLock { _llamadas } }
    var regla: Regla
    init(_ regla: @escaping Regla) { self.regla = regla }
    func enviar(_ pedido: URLRequest) async throws -> (Data, URLResponse) {
        let fn = pedido.url!.lastPathComponent
        let cuerpo = (try? JSONDecoder().decode(JSONValue.self, from: pedido.httpBody ?? Data("{}".utf8))) ?? .null
        lock.withLock { _llamadas.append(fn) }
        let (status, texto) = try await regla(fn, cuerpo)
        return (Data(texto.utf8), HTTPURLResponse(url: pedido.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}

private func leerMuestra(_ n: String) -> String {
    (try? String(contentsOf: repo.appendingPathComponent("apps/shared/fixtures/test-nativa-real/\(n).json"), encoding: .utf8)) ?? "[]"
}

private let tokA = "AAAAAAAAAAAAAAAAAAAA"
private let tokB = "BBBBBBBBBBBBBBBBBBBB"
private let info = #"[{"cliente_id":"c1","nombre":"Cliente","perfil":"natural"}]"#

@Suite("Regresiones de la revisión del 14-oct", .serialized)
@MainActor
struct RegresionesRevision {
    let raiz = FileManager.default.temporaryDirectory.appendingPathComponent("verif-\(UUID().uuidString)")

    // 1. Arranque en frío por un link nuevo mientras carga la cuenta vieja (revocada).
    @Test func carreraArranqueConLinkNuevo() async throws {
        defer { UserDefaults.standard.removeObject(forKey: "mypump_token_invalido") }
        let t = TransporteProgramado { fn, cuerpo in
            let tok = cuerpo["p_token"]?.comoTexto
            if fn == "mypump_get_cliente_info" {
                if tok == tokA { try await Task.sleep(for: .milliseconds(150)); return (200, "[]") }
                try await Task.sleep(for: .milliseconds(30)); return (200, info)
            }
            return (200, "[]")
        }
        let almacen = TokenEnMemoria(tokA)
        let m = ModeloApp(cliente: ClienteRPC(config: .produccion, transporte: t), almacen: almacen, raizDisco: raiz)
        async let a: Void = m.cargar()
        try await Task.sleep(for: .milliseconds(5))
        async let b: Bool = m.entrar(con: "https://app.mypumpteam.com/?t=\(tokB)")
        let (_, ok) = await (a, b)
        print("REGRESION1 entrar devolvió=\(ok) fase=\(m.fase) token en memoria=\(m.token ?? "nil") token guardado=\(almacen.leer() ?? "nil")")
        #expect(almacen.leer() == tokB)
        #expect(m.fase == .listo)
    }

    // 2. resolverSesion: sin rutina activa (iniciar_sesion → null) la cola se congela y lo de atrás no sale nunca.
    @Test func colaCongeladaPorSesionNula() async throws {
        let t = TransporteProgramado { fn, _ in
            switch fn {
            case "mypump_get_sesion_dia": return (200, "[]")
            case "mypump_iniciar_sesion": return (200, "null")
            case "mypump_set_habito": return (200, #"[{"fecha":"2026-10-14","vasos_agua":3}]"#)
            case "mypump_get_cliente_info": return (200, info)   // el token anda: es "sin rutina activa", no un token caído
            default: return (200, "[]")
            }
        }
        let esc = Escrituras(cliente: ClienteRPC(config: .produccion, transporte: t), token: tokA)
        let estados = EstadosRegresion()
        let o = Outbox(archivo: nil, reintentoAutomatico: false) { op in await esc.ejecutar(op) }
        await o.observar(estado: { e in estados.anotar(e) }, abandonadas: { _ in })
        await o.encolar("carga", .objeto(["diaId": .texto("d1"), "semana": .numero(1),
                                          "datos": .objeto(["diaId": .texto("d1"), "ejercicioId": .texto("x-d1-0"), "serie": .numero(1)])]),
                        dedupeKey: "carga_d1_x_0")
        await o.encolar("habito", .objeto(["fecha": .texto("2026-10-14"), "campo": .texto("vasos_agua"), "valor": .texto("3")]),
                        dedupeKey: "habito|2026-10-14|vasos_agua")
        for _ in 0..<20 { await o.drenar() }
        let ops = await o.operaciones
        print("REGRESION2 pendientes=\(ops.count) tries=\(ops.map(\.tries)) fallidos=\(await o.fallidos.count) set_habito llamado=\(t.llamadas.contains("mypump_set_habito")) ultimoEstado=\(String(describing: estados.lista.last))")
        #expect(t.llamadas.contains("mypump_set_habito"))
    }

    // 3. Demo después de "Este link ya no sirve": ¿escribe?
    @Test func demoConTokenVencidoEscribe() async throws {
        defer { UserDefaults.standard.removeObject(forKey: "mypump_token_invalido") }
        let t = TransporteProgramado { fn, _ in
            if fn == "mypump_get_cliente_info" { return (200, "[]") }
            if fn == "mypump_save_food_swap" { return (400, #"{"code":"22P02","message":"invalid input syntax for type uuid: \"demo\""}"#) }
            return (200, "[]")
        }
        let m = ModeloApp(cliente: ClienteRPC(config: .produccion, transporte: t), almacen: TokenEnMemoria(tokA), raizDisco: raiz)
        await m.cargar()
        #expect(m.fase == .tokenInvalido)
        let demo = repo.appendingPathComponent("apps/shared/demo")
        m.entrarEnDemo(rutina: try Data(contentsOf: demo.appendingPathComponent("rutina.json")),
                       dieta: try Data(contentsOf: demo.appendingPathComponent("dieta.json")))
        let c = try #require(m.comidasDelDia.first)
        let a = try #require(c.opciones.first?.alimentos.first)
        await m.sustituir(a, por: .objeto(["name": .texto("Ricota"), "qty": .numero(100), "unit": .texto("g"), "kcal": .numero(138),
                                           "prot": .numero(11), "carb": .numero(4), "fat": .numero(9)]), comidaId: c.id, opt: 0, idx: 0)
        try await Task.sleep(for: .milliseconds(300))
        let alimento = await m.crearAlimentoPropio(.init(nombre: "X", kcal: 100, prot: 1, carb: 1, fat: 1, unidad: "g", gramosPorUnidad: nil, categoria: ""))
        print("REGRESION3 esDemo=\(m.esDemo) llamadas=\(t.llamadas) pendientesCola=\(await m.outbox?.pendientes ?? -1) crearAlimentoPropio=\(alimento)")
        #expect(!t.llamadas.contains("mypump_save_food_swap"))
        #expect(!t.llamadas.contains("mypump_create_custom_food"))
    }

    // 4. Se cae solo la dieta (red) con la info bien: ¿se pierde de la pantalla y de la copia offline?
    @Test func fallaParcialPisaLaCopiaOffline() async throws {
        let caeDieta = BanderaRegresion()
        let t = TransporteProgramado { fn, _ in
            switch fn {
            case "mypump_get_cliente_info": return (200, info)
            case "mypump_get_rutina_activa": return (200, leerMuestra("get_rutina_activa"))
            case "mypump_get_dieta_activa":
                if await caeDieta.valor { throw URLError(.timedOut) }
                return (200, leerMuestra("get_dieta_activa"))
            default: return (200, "[]")
            }
        }
        let m = ModeloApp(cliente: ClienteRPC(config: .produccion, transporte: t), almacen: TokenEnMemoria(tokA), raizDisco: raiz)
        await m.cargar()
        let antes = m.dieta != nil
        await caeDieta.prender()
        await m.cargar()   // "tirar para actualizar" con la señal del gym
        let disco = Disco(raiz: raiz, token: tokA)
        let copia = disco.leer(ModeloApp.CopiaOffline.self, "offline.json")
        print("REGRESION4 dietaAntes=\(antes) dietaDespues=\(m.dieta != nil) desdeCache=\(m.desdeCache) fase=\(m.fase) copiaTieneDieta=\(copia?.dieta != nil && copia?.dieta != .null)")
        #expect(m.dieta != nil)
        #expect(copia?.dieta != nil)
    }

    // 5. Token revocado: ¿las ops se estacionan (arreglo nativo n.º 3) o se abandonan?
    @Test func tokenRevocadoNoEstaciona() async throws {
        let t = TransporteProgramado { _, _ in (200, "null") }
        let esc = Escrituras(cliente: ClienteRPC(config: .produccion, transporte: t), token: tokA)
        let o = Outbox(archivo: nil, reintentoAutomatico: false) { op in await esc.ejecutar(op) }
        await o.encolar("habito", .objeto(["fecha": .texto("2026-10-14"), "campo": .texto("durmio_bien"), "valor": .texto("true")]), dedupeKey: "habito|2026-10-14|durmio_bien")
        await o.encolar("peso", .objeto(["fecha": .texto("2026-10-14"), "valor": .numero(80)]), dedupeKey: "peso_2026-10-14")
        await o.encolar("chat", .objeto(["contenido": .texto("hola")]), dedupeKey: "chat_1_hola")
        for _ in 0..<10 { await o.drenar() }
        print("REGRESION5 pendientes=\(await o.pendientes) fallidos=\(await o.fallidos.count) get_cliente_info consultado=\(t.llamadas.contains("mypump_get_cliente_info"))")
        #expect(await o.pendientes == 3)
    }

    // 7. Una op encolada durante una pasada: ¿sale sola (sin otro disparador)?
    @Test func encoladoDuranteLaPasadaSale() async throws {
        var atascadas = 0
        for _ in 0..<60 {
            let o = Outbox(archivo: nil, reintentoAutomatico: true) { _ in
                try? await Task.sleep(for: .milliseconds(3))
                return .respuesta(.success(.texto("id")))
            }
            await o.encolar("x", .null, dedupeKey: "a")
            try await Task.sleep(for: .milliseconds(1))
            await o.encolar("x", .null, dedupeKey: "b")
            try await Task.sleep(for: .milliseconds(120))
            if await o.pendientes > 0 {
                try await Task.sleep(for: .seconds(2))
                if await o.pendientes > 0 { atascadas += 1 }
            }
        }
        print("REGRESION7 atascadas (tras 2 s más)=\(atascadas)/60")
        #expect(atascadas == 0)
    }

    // 8. Arranque en frío tocando un link VIEJO (ya marcado inválido) con una cuenta buena guardada (ACC-02).
    @Test func linkViejoEnArranqueEnFrio() async throws {
        let viejo = "VVVVVVVVVVVVVVVVVVVV"
        UserDefaults.standard.set(viejo, forKey: "mypump_token_invalido")
        defer { UserDefaults.standard.removeObject(forKey: "mypump_token_invalido") }
        let t = TransporteProgramado { fn, cuerpo in
            let tok = cuerpo["p_token"]?.comoTexto
            if fn == "mypump_get_cliente_info" {
                try await Task.sleep(for: .milliseconds(60))
                return tok == viejo ? (200, "[]") : (200, info)
            }
            return (200, "[]")
        }
        let almacen = TokenEnMemoria(tokA)
        let m = ModeloApp(cliente: ClienteRPC(config: .produccion, transporte: t), almacen: almacen, raizDisco: raiz)
        async let a: Void = m.cargar()          // .task de RaizApp
        try await Task.sleep(for: .milliseconds(5))
        async let b: Bool = m.entrar(con: "https://app.mypumpteam.com/?t=\(viejo)")   // onOpenURL
        _ = await (a, b)
        print("REGRESION8 fase=\(m.fase) token en memoria=\(m.token ?? "nil") token guardado=\(almacen.leer() ?? "nil")")
        #expect(almacen.leer() == tokA)
    }

    // 9. Reemplazar mientras hidrata (antes de leer los swaps del disco) pisa el archivo local.
    @Test func reemplazarDuranteLaHidratacionPisaLosSwapsLocales() async throws {
        let dietaId = "15a9a59f-9b90-4e42-b6a4-07b1e4bb4a7f"
        let disco = Disco(raiz: raiz, token: tokA)
        func sw(_ n: String) -> SwapLocal { SwapLocal(original: nil, current: .objeto(["name": .texto(n), "qty": .numero(100), "unit": .texto("g")])) }
        disco.guardar(["swap_\(dietaId)_c1_0_1": sw("Ricota"), "swap_\(dietaId)_c2_0_1": sw("Fideos")], "swaps_\(dietaId).json")
        let t = TransporteProgramado { fn, _ in
            switch fn {
            case "mypump_get_cliente_info": return (200, info)
            case "mypump_get_rutina_activa": return (200, leerMuestra("get_rutina_activa"))
            case "mypump_get_dieta_activa": return (200, leerMuestra("get_dieta_activa"))
            case "mypump_get_cliente_prefs": try await Task.sleep(for: .milliseconds(300)); return (200, "[]")
            case "mypump_get_food_swaps": throw URLError(.timedOut)
            default: return (200, "[]")
            }
        }
        let m = ModeloApp(cliente: ClienteRPC(config: .produccion, transporte: t), almacen: TokenEnMemoria(tokA), raizDisco: raiz)
        async let carga: Void = m.cargar()
        var listoSinSwaps = false
        for _ in 0..<50 { if m.fase == .listo { listoSinSwaps = m.swaps.isEmpty; break }; try await Task.sleep(for: .milliseconds(5)) }
        let c = try #require(m.comidasDelDia.first)
        let a = try #require(c.opciones.first?.alimentos.first)
        await m.sustituir(a, por: .objeto(["name": .texto("Tofu"), "qty": .numero(100), "unit": .texto("g")]), comidaId: c.id, opt: 0, idx: 0)
        await carga
        let enDisco = disco.leer([String: SwapLocal].self, "swaps_\(dietaId).json") ?? [:]
        print("REGRESION9 listoConSwapsVacios=\(listoSinSwaps) swapsEnMemoria=\(m.swaps.keys.sorted()) swapsEnDisco=\(enDisco.keys.sorted())")
        #expect(enDisco.count == 3)
    }

    // 10. El badge del chat: lo que llegó por el sondeo (sin campo de leído) se pierde al recargar (tirar para actualizar).
    @Test func badgeDelChatSePierdeAlRecargar() async throws {
        let paso = BanderaRegresion()
        let m1 = #"{"id":"m1","autor":"coach","contenido":"hola","leido_por_cliente":true,"created_at":"2026-10-14T10:00:00.123456+00:00"}"#
        let m2nuevo = #"{"id":"m2","autor":"coach","contenido":"¿cómo venís?","created_at":"2026-10-14T11:00:00.123456+00:00"}"#
        let m2 = #"{"id":"m2","autor":"coach","contenido":"¿cómo venís?","leido_por_cliente":false,"created_at":"2026-10-14T11:00:00.123456+00:00"}"#
        let t = TransporteProgramado { fn, _ in
            switch fn {
            case "mypump_get_chat": return (200, await paso.valor ? "[\(m2),\(m1)]" : "[\(m1)]")
            case "mypump_chat_nuevos": return (200, "[\(m2nuevo)]")
            default: return (200, "[]")
            }
        }
        let chat = ModeloChat(cliente: ClienteRPC(config: .produccion, transporte: t), token: tokA, outbox: nil)
        await chat.cargar()
        await chat.sondear()
        let conBadge = chat.noLeidos
        await paso.prender()
        await chat.cargar()            // ModeloApp.cargar() → chat.cargar() (refresh de Dieta, volver con copia offline)
        print("REGRESION10 badge tras el sondeo=\(conBadge) badge tras recargar=\(chat.noLeidos)")
        #expect(chat.noLeidos == 1)
    }

    // 4b. Se cae la RUTINA (o las dos) con la info bien: la web usa la copia; la nativa no.
    @Test(arguments: [false, true])
    func fallaRutinaPisaLaCopia(tambienDieta: Bool) async throws {
        let cae = BanderaRegresion()
        let t = TransporteProgramado { fn, _ in
            switch fn {
            case "mypump_get_cliente_info": return (200, info)
            case "mypump_get_rutina_activa":
                if await cae.valor { throw URLError(.timedOut) }
                return (200, leerMuestra("get_rutina_activa"))
            case "mypump_get_dieta_activa":
                if tambienDieta, await cae.valor { throw URLError(.timedOut) }
                return (200, leerMuestra("get_dieta_activa"))
            default: return (200, "[]")
            }
        }
        let m = ModeloApp(cliente: ClienteRPC(config: .produccion, transporte: t), almacen: TokenEnMemoria(tokA), raizDisco: raiz)
        await m.cargar()
        await cae.prender()
        await m.cargar()
        let copia = Disco(raiz: raiz, token: tokA).leer(ModeloApp.CopiaOffline.self, "offline.json")
        print("REGRESION4b tambienDieta=\(tambienDieta) rutina=\(m.rutina != nil) dieta=\(m.dieta != nil) fase=\(m.fase) desdeCache=\(m.desdeCache) copiaRutina=\(copia?.rutina != nil && copia?.rutina != .null) copiaDieta=\(copia?.dieta != nil && copia?.dieta != .null)")
        #expect(m.rutina != nil)
    }
}

final class EstadosRegresion: @unchecked Sendable {
    private let lock = NSLock()
    private var _lista: [EstadoGuardado] = []
    var lista: [EstadoGuardado] { lock.withLock { _lista } }
    func anotar(_ e: EstadoGuardado) { lock.withLock { _lista.append(e) } }
}

actor BanderaRegresion {
    var valor = false
    func prender() { valor = true }
}
