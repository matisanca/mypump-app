import Foundation
import Testing
import MyPumpModelos
import MyPumpReglas
@testable import MyPumpDatos

/// Revisión del 15-oct, hallazgo 3: el estado de Salud era del teléfono. Con el link de otra cuenta en el mismo teléfono
/// (Mati mirando la de un cliente), al abrir se subían 7 días de su salud a la ficha del otro, y el historial quedaba
/// marcado como hecho para una cuenta que nunca lo trajo.
@Suite("Salud por cuenta", .serialized)
@MainActor
struct SaludPorCuentaTests {
    /// Lo que dejó la migración (o una versión anterior): Salud conectada, sin cuenta.
    func telefonoConectado() -> AlmacenSaludEnMemoria {
        AlmacenSaludEnMemoria([ClaveSalud.conectado: "1", ClaveSalud.historialHecho: "1"])
    }

    @Test func laPrimeraCuentaSeQuedaConLoQueHabiaYLaOtraArrancaSinConectar() {
        let telefono = telefonoConectado()
        let duenio = AlmacenSaludPorCuenta(base: telefono, cuenta: "aaaa")
        #expect(duenio.leer(ClaveSalud.conectado) == "1" && duenio.leer(ClaveSalud.historialHecho) == "1")
        let otra = AlmacenSaludPorCuenta(base: telefono, cuenta: "bbbb")
        #expect(otra.leer(ClaveSalud.conectado) == nil && otra.leer(ClaveSalud.historialHecho) == nil)
        // Lo que haga una no toca a la otra, y la dueña no cambia al volver.
        otra.escribir(ClaveSalud.conectado, "1")
        duenio.escribir(ClaveSalud.ultimaSync, "2026-10-15T03:00:00.000Z")
        #expect(AlmacenSaludPorCuenta(base: telefono, cuenta: "bbbb").leer(ClaveSalud.ultimaSync) == nil)
        #expect(AlmacenSaludPorCuenta(base: telefono, cuenta: "aaaa").leer(ClaveSalud.conectado) == "1")
        #expect(telefono.leer(AlmacenSaludPorCuenta.duenia) == "aaaa")
    }

    @Test func alAbrirConOtraCuentaNoSeSubeLaSaludDelDuenio() async {
        let telefono = telefonoConectado()
        // El dueño abre primero (se queda con lo que había) y después se abre el link de otra persona.
        _ = AlmacenSaludPorCuenta(base: telefono, cuenta: "aaaa")
        let base = BasePorFuncion()
        let otra = ModeloSalud(cliente: ClienteRPC(transporte: base), token: "tok-de-otra-cuenta-00001", fuente: FuenteConPasos(),
                               almacen: AlmacenSaludPorCuenta(base: telefono, cuenta: "bbbb"))
        await otra.alAbrir()
        #expect(!otra.conectado)
        #expect(base.cuantas("mypump_ingest_salud") == 0, "se subió la salud del dueño a otra cuenta")

        // El dueño sí sincroniza al abrir.
        let baseDuenio = BasePorFuncion()
        let duenio = ModeloSalud(cliente: ClienteRPC(transporte: baseDuenio), token: "tok-del-duenio-0000001", fuente: FuenteConPasos(),
                                 almacen: AlmacenSaludPorCuenta(base: telefono, cuenta: "aaaa"))
        await duenio.alAbrir()
        #expect(duenio.conectado)
        #expect(baseDuenio.cuantas("mypump_ingest_salud") >= 1)
    }
}

/// Una fuente con pasos de hoy: si se sincroniza, hay algo para subir.
private struct FuenteConPasos: FuenteSalud {
    var iosMayor: Int { 18 }
    func disponible() async -> Bool { true }
    func pedirLectura(_ tipos: [String]) async throws {}
    func permisos(_ tipos: [String]) async throws -> PermisosSalud { PermisosSalud(preguntados: tipos, pendientes: []) }
    func agregado(_ dataType: String, agregacion: String, desde: Double, hasta: Double) async throws -> [BaldeDiario] {
        dataType == "steps" ? [BaldeDiario(inicio: hasta - 3_600_000, valor: 4_321)] : []
    }
    func muestras(_ dataType: String, desde: Double, hasta: Double, limite: Int) async throws -> [MuestraSalud] { [] }
    func entrenos(desde: Double, hasta: Double) async throws -> [EntrenoCrudo] { [] }
}
