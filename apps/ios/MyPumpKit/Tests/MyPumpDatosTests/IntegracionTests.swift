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
