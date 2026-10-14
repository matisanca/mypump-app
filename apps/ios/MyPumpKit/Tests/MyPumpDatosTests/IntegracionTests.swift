import Foundation
import Testing
import MyPumpModelos
import MyPumpReglas
@testable import MyPumpDatos

/// Contra el backend REAL, con la cuenta de prueba test-nativa-real (invisible para el coach). Solo corre en la Mac de
/// desarrollo, donde está el registro privado de cuentas de prueba. Escribe datos de prueba (autorizado).
private let registro = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Developer/nativa-evidencia/privado/cuentas-prueba.json")

private func tokenDePrueba() -> String? {
    guard let d = try? Data(contentsOf: registro), let j = try? JSONDecoder().decode(JSONValue.self, from: d) else { return nil }
    return j["test-nativa-real"]?["token"]?.comoTexto
}

@Suite("Integración con el backend real (cuenta de prueba)", .enabled(if: tokenDePrueba() != nil), .serialized)
@MainActor
struct IntegracionTests {
    let raiz = FileManager.default.temporaryDirectory.appendingPathComponent("mypump-integracion-\(UUID().uuidString)")

    @Test func cargaTodoYCopiaOffline() async throws {
        let m = ModeloApp(almacen: TokenEnMemoria(tokenDePrueba()), raizDisco: raiz)
        await m.cargar()
        #expect(m.fase == .listo)
        #expect(m.info?.clienteId == "test-nativa-real")
        #expect((m.rutina?.estructura.dias.count ?? 0) == 4)
        #expect(!(m.comidasDelDia.isEmpty))
        // Sin red, arranca desde la copia offline.
        struct SinRed: Transporte { func enviar(_ p: URLRequest) async throws -> (Data, URLResponse) { throw URLError(.notConnectedToInternet) } }
        let offline = ModeloApp(cliente: ClienteRPC(transporte: SinRed()), almacen: TokenEnMemoria(tokenDePrueba()), raizDisco: raiz)
        await offline.cargar()
        #expect(offline.fase == .listo && offline.desdeCache)
        #expect(offline.dieta?.id == m.dieta?.id)
    }

    @Test func alimentoPropioSeCreaYEntraALaBase() async throws {
        let m = ModeloApp(almacen: TokenEnMemoria(tokenDePrueba()), raizDisco: raiz)
        await m.cargar()
        // Upsert por (cliente, nombre): correrlo de nuevo no duplica.
        let datos = try AlimentoPropioNuevo.preparar(nombre: "Yogur prueba nativa", kcal: 75, prot: 3, carb: 10.1, fat: 2.25,
                                                     unidad: "porcion", gramosPorUnidad: 30, categoria: "lacteo").get()
        let creado = try await m.crearAlimentoPropio(datos).get()
        #expect(creado.nombre == "Yogur prueba nativa")
        #expect(creado.kcal == 250 && creado.prot == 10 && creado.gramosPorUnidad == 30 && creado.unidad == "porcion")
        #expect(m.alimentosPropios.filter { $0.nombre == "Yogur prueba nativa" }.count == 1)
        let otra = ModeloApp(almacen: TokenEnMemoria(tokenDePrueba()), raizDisco: raiz)
        await otra.cargar()
        #expect(otra.alimentosPropios.contains { $0.nombre == "Yogur prueba nativa" && $0.kcal == 250 })
    }

    @Test func comidaLibreSeCreaSeListaYSeBorra() async throws {
        let m = ModeloApp(almacen: TokenEnMemoria(tokenDePrueba()), raizDisco: raiz)
        await m.cargar()
        let antes = m.comidasLibres.count
        let datos = try ComidaLibreNueva.preparar(descripcion: "Prueba nativa: alfajor", hora: "10:30", kcal: 250, prot: 3,
                                                  carb: 35, fat: 11, detalle: nil).get()
        let creada = try await m.crearComidaLibre(datos).get()
        #expect(creada.descripcion == "Prueba nativa: alfajor" && creada.kcal == 250)
        #expect(m.comidasLibres.count == antes + 1)
        let otra = ModeloApp(almacen: TokenEnMemoria(tokenDePrueba()), raizDisco: raiz)
        await otra.cargar()
        #expect(otra.comidasLibres.contains { $0.id == creada.id })
        #expect(await m.borrarComidaLibre(creada.id))
        await otra.cargarComidasLibres()
        #expect(!otra.comidasLibres.contains { $0.id == creada.id })
    }

    /// La plomería de mini-vision sin gastar una llamada a la IA: con un token que no existe, el servicio corta antes
    /// (403) y el mensaje llega tal cual. Si el body estuviera mal armado contestaría 400 "falta imagen".
    @Test func visionConTokenInvalidoCortaAntesDeLaIA() async throws {
        let c = ClienteRPC()
        let jpeg = Data(base64Encoded: "/9j/4AAQSkZJRgABAQEASABIAAD/2wBDAP//////////////////////////////////////////////////////////////////////////////////////wAALCAABAAEBAREA/8QAFAABAAAAAAAAAAAAAAAAAAAACf/EABQQAQAAAAAAAAAAAAAAAAAAAAD/2gAIAQEAAD8AKp//2Q==")!
        let r = await c.vision(token: "tokenQueNoExiste_0000000000000000", tipo: .plato, jpeg: jpeg)
        guard case .failure(let e) = r else { Issue.record("respondió ok con un token inválido"); return }
        #expect(e.status == 403)
        #expect(e.clase == .permanente)
    }

    @Test func chatEnviaPorLaColaYNoDuplicaUnReintento() async throws {
        let m = ModeloApp(almacen: TokenEnMemoria(tokenDePrueba()), raizDisco: raiz)
        await m.cargar()
        let t = try #require(tokenDePrueba())
        let chat = ModeloChat(cliente: m.cliente, token: t, outbox: m.outbox)
        await chat.cargar()
        let texto = "Prueba nativa \(UUID().uuidString.prefix(8))"
        await chat.enviar(texto)
        #expect(chat.hilo.mensajes.last?.pendiente == true)
        await m.outbox?.drenar()
        #expect(await m.outbox?.pendientes == 0)
        await chat.sondear()
        #expect(chat.hilo.mensajes.contains { $0.contenido == texto && !$0.pendiente })
        #expect(!chat.hilo.mensajes.contains { $0.pendiente })
        // La respuesta se perdió y la cola lo reintenta: no se manda de nuevo.
        let e = Escrituras(cliente: m.cliente, token: t)
        let op = Operacion(id: "x", kind: "chat", payload: .objeto(["contenido": .texto(texto)]), dedupeKey: nil, tries: 0,
                           ts: Date().timeIntervalSince1970 * 1000 - 5_000)
        _ = await e.ejecutar(op)
        let filas = try await m.cliente.filas("mypump_get_chat", ["p_token": .texto(t), "p_antes": .null, "p_limite": .numero(10)],
                                              como: MensajeChat.self).get()
        #expect(filas.filter { $0.contenido == texto }.count == 1)
    }

    @Test func sustituirLlegaAnclado_yRevertirLoBorra() async throws {
        let m = ModeloApp(almacen: TokenEnMemoria(tokenDePrueba()), raizDisco: raiz)
        await m.cargar()
        let comida = try #require(m.comidasDelDia.first)
        let original = try #require(comida.opciones.first?.alimentos.first)
        let sustituto: JSONValue = .objeto(["name": .texto("Ricota descremada"), "qty": .numero(150), "unit": .texto("g"),
                                            "kcal": .numero(207), "prot": .numero(17), "carb": .numero(6), "fat": .numero(12), "category": .texto("lacteo")])
        await m.sustituir(original, por: sustituto, comidaId: comida.id, opt: 0, idx: 0)
        #expect(m.efectivo(original, comidaId: comida.id, opt: 0, idx: 0).alimento.nombre == "Ricota descremada")
        await m.outbox?.drenar()
        #expect(await m.outbox?.pendientes == 0)

        let t = try #require(tokenDePrueba())
        let dietaId = try #require(m.dieta?.id)
        let remotos = try await m.cliente.filas("mypump_get_food_swaps", ["p_token": .texto(t), "p_dieta_id": .texto(dietaId)], como: FoodSwap.self).get()
        let fila = try #require(remotos.first { $0.comidaId == comida.id && $0.optIdx == 0 && $0.foodIdx == 0 })
        #expect(fila.foodData["_orig"]?["name"]?.comoTexto == original.nombre)

        await m.revertir(comidaId: comida.id, opt: 0, idx: 0)
        await m.outbox?.drenar()
        let despues = try await m.cliente.filas("mypump_get_food_swaps", ["p_token": .texto(t), "p_dieta_id": .texto(dietaId)], como: FoodSwap.self).get()
        #expect(!despues.contains { $0.comidaId == comida.id && $0.optIdx == 0 && $0.foodIdx == 0 })
        #expect(m.efectivo(original, comidaId: comida.id, opt: 0, idx: 0).alimento.nombre == original.nombre)
    }

    @Test func tokenInvalido() async {
        let m = ModeloApp(almacen: TokenEnMemoria("TokenInvalidoDePrueba00000000000"), raizDisco: raiz)
        await m.cargar()
        #expect(m.fase == .tokenInvalido)
    }
}
