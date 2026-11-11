import Foundation
import Testing
import MyPumpModelos
import MyPumpReglas
@testable import MyPumpDatos

private let raizRepo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

/// «Récords y logros» (2.3.0): el permiso, la cola local y cuándo no se llama a nada. Gemelo de WinsModeloTest.kt.
@MainActor
struct WinsModeloTests {
    private let token = "WWWWWWWWWWWWWWWWWWWW"

    private func raiz() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }
    private func armar(_ d: DobleColaA, raiz r: URL? = nil) -> ModeloWins {
        ModeloWins(cliente: ClienteRPC(transporte: d), token: token, disco: Disco(raiz: r ?? raiz(), token: token))
    }
    private func app(_ d: DobleColaA, raiz r: URL? = nil) -> ModeloApp {
        ModeloApp(cliente: ClienteRPC(config: .produccion, transporte: d), almacen: TokenEnMemoria(token), raizDisco: r ?? raiz())
    }
    private var records: [ReglasWins.Record] {
        ReglasWins.records([
            .init(clave: "remo con barra", nombre: "Remo con barra", anteriores: [.init(kg: 55, reps: 8)], hoy: [.init(kg: 57.5, reps: 8)]),
            .init(clave: "curl", nombre: "Curl", anteriores: [.init(kg: 12, reps: 10)], hoy: [.init(kg: 12, reps: 12)]),
        ])
    }
    /// La cola se vacía en una tarea aparte: se espera a que no quede nada (o a que pase el tiempo).
    private func esperar(_ m: ModeloWins, hasta condicion: @MainActor () -> Bool) async {
        for _ in 0..<400 where !condicion() { try? await Task.sleep(for: .milliseconds(10)) }
        _ = m
    }

    @Test func lasPalancasSeLeenYSinLaClaveEstanApagadas() {
        let p = PalancaRemota(.objeto(["wins_app": .bool(true), "lista_previa": .bool(true)]))
        #expect(p.winsApp && p.listaPrevia)
        #expect(!PalancaRemota(.objeto([:])).winsApp && !PalancaRemota(.objeto([:])).listaPrevia)
        #expect(!PalancaRemota(.objeto(["wins_app": .texto("true"), "lista_previa": .numero(1)])).winsApp)
        #expect(!PalancaRemota(.objeto(["wins_app": .texto("true"), "lista_previa": .numero(1)])).listaPrevia)
        #expect(!PalancaRemota.deFabrica.winsApp && !PalancaRemota.deFabrica.listaPrevia)
    }

    @Test func conLaPalancaApagadaModeloAppNoLlamaANada() async {
        let d = DobleColaA.escenario("apagado")
        let m = app(d)
        await m.cargar()
        await m.alVolverAPrimerPlano()
        #expect(d.llamadasWins.isEmpty)
        #expect(d.llamadasLista.isEmpty)
        #expect(m.wins?.prendida == false && m.wins?.permiso == false)
        #expect(m.wins?.encolar(records) == false)
        #expect(m.wins?.encolarRacha(dias: 7, meta: 9000) == false)
        #expect(m.wins?.visibleEnMisDatos == false)
        #expect(m.listaPrevia?.vista == nil)
        #expect(d.llamadasWins.isEmpty)
    }

    @Test func conLaPalancaPrendidaTraeElEstado() async {
        let d = DobleColaA.escenario("conPermiso")
        let m = app(d)
        await m.cargar()
        #expect(d.llamadasWins == ["mypump_wins_estado"])
        #expect(m.wins?.activa == true && m.wins?.permiso == true && m.wins?.visibleEnMisDatos == true)
    }

    @Test func sinPermisoNuncaEncola() async {
        let d = DobleColaA.escenario("sinPermiso")
        let m = armar(d)
        await m.refrescar()
        #expect(!m.permiso)
        #expect(!m.encolar(records))
        #expect(!m.encolarRacha(dias: 7, meta: 9000))
        #expect(m.cola.isEmpty)
        await m.vaciar()
        #expect(!d.llamadasWins.contains("mypump_wins_registrar"))
    }

    @Test func darElPermisoEncolaLosRecordsDelFestejoYLosManda() async {
        let d = DobleColaA.escenario("sinPermiso")
        let m = armar(d)
        await m.refrescar()
        #expect(await m.darPermiso(records: records, dia: "2026-11-10"))
        #expect(m.permiso && d.permiso && d.permisosPedidos == [true])
        await esperar(m) { m.cola.isEmpty }
        #expect(d.registrados.map(\.tipo) == ["record_kg", "record_reps"])
        #expect(d.registrados.map(\.clave) == ["remo con barra", "curl"])
        #expect(d.registrados.allSatisfy { $0.dia == "2026-11-10" && UUID(uuidString: $0.id) != nil })
        #expect(d.registrados.first?.datos == .objeto(["ejercicio": .texto("Remo con barra"), "kg": .numero(57.5), "reps": .numero(8),
                                                       "antes_kg": .numero(55), "antes_reps": .numero(8)]))
    }

    @Test func sinRedElPermisoNoQuedaDado() async {
        let d = DobleColaA.escenario("sinRedPermiso")
        let m = armar(d)
        await m.refrescar()
        #expect(await m.darPermiso(records: records) == false)
        #expect(!m.permiso && m.cola.isEmpty)
        // Y sacarlo sin red tampoco cambia nada.
        d.sinRedPermiso = false; d.permiso = true
        await m.refrescar()
        d.sinRedPermiso = true
        #expect(await m.revocar() == false)
        #expect(m.permiso)
    }

    @Test func revocarVaciaLaColaYAndaConLaPalancaApagada() async {
        let r = raiz()
        let d = DobleColaA.escenario("conPermiso")
        d.registrarCaido = true
        let m = armar(d, raiz: r)
        await m.refrescar()
        #expect(m.encolar(records))
        await m.vaciar()
        #expect(m.cola.count == 2)
        // La palanca se apaga: el permiso recordado sigue y el interruptor se sigue viendo para poder sacarlo.
        d.palancaWins = false
        let m2 = armar(d, raiz: r)
        m2.apagar()
        #expect(m2.permiso && m2.visibleEnMisDatos && m2.cola.count == 2)
        #expect(await m2.revocar())
        #expect(!m2.permiso && m2.cola.isEmpty && !m2.visibleEnMisDatos && !d.permiso)
        #expect(armar(d, raiz: r).cola.isEmpty)
    }

    @Test func laColaPersisteYSeReintenta() async {
        let r = raiz()
        let d = DobleColaA.escenario("conPermiso")
        d.registrarCaido = true
        let m = armar(d, raiz: r)
        await m.refrescar()
        #expect(m.encolar(records, dia: "2026-11-10"))
        #expect(m.encolarRacha(dias: 7, meta: 9000, dia: "2026-11-10"))
        #expect(!m.encolarRacha(dias: 8, meta: 9000), "8 días no es un hito")
        await m.vaciar()
        #expect(m.cola.count == 3 && d.registrados.isEmpty, "un 503 lo deja para después")
        // Sin red tampoco se pierde.
        d.registrarCaido = false; d.sinRed = true
        await m.vaciar()
        #expect(m.cola.count == 3)
        // Otra vez la app: la cola está en disco y sale con los mismos ids.
        let ids = m.cola.map(\.id)
        d.sinRed = false
        let m2 = armar(d, raiz: r)
        #expect(m2.cola.map(\.id) == ids && m2.permiso)
        await m2.refrescar()
        await m2.vaciar()
        #expect(m2.cola.isEmpty)
        #expect(d.registrados.map(\.id) == ids)
        #expect(d.registrados.last == .init(id: ids[2], tipo: "racha_pasos", clave: "pasos", dia: "2026-11-10",
                                            datos: .objeto(["dias": .numero(7), "meta": .numero(9000)])))
        #expect(armar(d, raiz: r).cola.isEmpty)
    }

    @Test func elMismoLogroDelDiaReemplazaAlQueNoSalio() async {
        let d = DobleColaA.escenario("conPermiso")
        d.registrarCaido = true
        let m = armar(d)
        await m.refrescar()
        m.encolar(records, dia: "2026-11-10")
        let primero = m.cola.first?.id
        m.encolar(records, dia: "2026-11-10")
        #expect(m.cola.count == 2 && m.cola.first?.id != primero)
        m.encolar(records, dia: "2026-11-11")
        #expect(m.cola.count == 4)
    }

    @Test func elServidorRechazaLosDatosYSeDescarta() async {
        let d = DobleColaA.escenario("conPermiso")
        d.registrarRechaza = true
        let m = armar(d)
        await m.refrescar()
        m.encolar(records)
        await esperar(m) { m.cola.isEmpty }
        #expect(m.cola.isEmpty && d.registrados.isEmpty && m.permiso)
    }

    @Test func sinPermisoEnElServidorSeRecuerdaYSeVaciaLaCola() async {
        let r = raiz()
        let d = DobleColaA.escenario("conPermiso")
        let m = armar(d, raiz: r)
        await m.refrescar()
        d.permiso = false   // lo sacó desde otro teléfono
        m.encolar(records)
        await esperar(m) { !m.permiso }
        #expect(!m.permiso && m.cola.isEmpty)
        #expect(!armar(d, raiz: r).permiso)
        #expect(!m.encolar(records))
    }

    @Test func sinLaFuncionDelServidorSeVaciaLaCola() async {
        let d = DobleColaA.escenario("conPermiso")
        d.registrarCaido = true
        let m = armar(d)
        await m.refrescar()
        m.encolar(records)
        await m.vaciar()
        #expect(m.cola.count == 2)
        d.registrarCaido = false; d.sinFuncion = true
        await m.vaciar()
        #expect(m.cola.isEmpty)
        // Y al preguntar el estado no queda nada prendido ni dado.
        await m.refrescar()
        #expect(!m.activa && !m.permiso)
    }

    @Test func elTopeDeLaColaDescartaLoMasViejo() async {
        let d = DobleColaA.escenario("conPermiso")
        d.sinRed = true
        let r = raiz()
        let m = armar(d, raiz: r)
        d.sinRed = false
        await m.refrescar()
        d.sinRed = true
        for i in 0..<60 {
            m.encolar(ReglasWins.records([.init(clave: "ejercicio \(i)", nombre: "Ejercicio \(i)", anteriores: [.init(kg: 10, reps: 10)],
                                                hoy: [.init(kg: 12, reps: 10)])]))
        }
        #expect(m.cola.count == ModeloWins.topeCola)
        #expect(m.cola.first?.clave == "ejercicio 10" && m.cola.last?.clave == "ejercicio 59")
    }

    @Test func sinRedAlAbrirValeElUltimoPermisoConocido() async {
        let r = raiz()
        let d = DobleColaA.escenario("conPermiso")
        await armar(d, raiz: r).refrescar()
        d.sinRed = true
        let m = armar(d, raiz: r)
        await m.refrescar()
        #expect(m.permiso)
        #expect(m.encolar(records))
        #expect(m.cola.count == 2)
    }

    @Test func laDemoNoTieneModeloNiLlamaANada() async throws {
        let d = DobleColaA.escenario("conPermiso")
        let m = ModeloApp(cliente: ClienteRPC(config: .produccion, transporte: d), almacen: TokenEnMemoria(nil), raizDisco: raiz())
        let demo = raizRepo.appendingPathComponent("apps/shared/demo")
        m.entrarEnDemo(rutina: try Data(contentsOf: demo.appendingPathComponent("rutina.json")),
                       dieta: try Data(contentsOf: demo.appendingPathComponent("dieta.json")),
                       historial: try Data(contentsOf: demo.appendingPathComponent("historial.json")))
        await m.cargar()
        await m.alVolverAPrimerPlano()
        await m.sincronizarListaPrevia()
        #expect(m.wins == nil)
        #expect(d.llamadas.isEmpty)
    }
}
