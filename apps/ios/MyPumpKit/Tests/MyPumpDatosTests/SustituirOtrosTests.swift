import Foundation
import Testing
import MyPumpModelos
@testable import MyPumpReglas
@testable import MyPumpDatos

// Revisión del 21-oct del cambio D24 («Otros ejercicios de [músculo]» en la hoja «Sustituir»): el modelo de Entreno con
// el catálogo real. Gemelo de SustituirOtrosTest.kt.

private let raizDelRepo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
private let catalogoReal = try! CatalogoEjercicios(json: Data(contentsOf: raizDelRepo.appendingPathComponent("apps/shared/catalogo-ejercicios.json")))

/// Un día de empuje sin fotos en el plan (como la demo, la que mira Apple): la extensión en polea (agarre Barra, Soga o
/// Maneral), los fondos y la patada de tríceps (sin variantes, con otros de su músculo) y uno que el catálogo no conoce.
private let estructuraOtros = """
{"semanas_total":12,"dias":[{"id":"d1","n":1,"nombre":"EMPUJE","bloques":[{"titulo":"BLOQUE 1 — TRÍCEPS","ejercicios":[
  {"id":"ext-d1-0","nombre":"Extensión tríceps en polea","tipo":"aislamiento","descanso_segundos":90,"progresion":[{"semana":1,"series":4,"reps":"12","rir":"1"}]},
  {"id":"fon-d1-1","nombre":"Fondos","tipo":"compuesto","descanso_segundos":120,"progresion":[{"semana":1,"series":3,"reps":"10","rir":"1"}]},
  {"id":"pat-d1-2","nombre":"Patada de tríceps con mancuerna","tipo":"aislamiento","descanso_segundos":60,"progresion":[{"semana":1,"series":3,"reps":"12","rir":"1"}]},
  {"id":"inv-d1-3","nombre":"Saludo inventado","tipo":"aislamiento","descanso_segundos":60,"progresion":[{"semana":1,"series":3,"reps":"12","rir":"1"}]},
  {"id":"cru-d1-4","nombre":"Crunch en máquina","tipo":"core","descanso_segundos":60,"progresion":[{"semana":1,"series":3,"reps":"15","rir":"1"}]}]}]}]}
"""

private func rutinaOtros() -> RutinaActiva {
    let fila = #"{"id":"rut-otros","version":1,"semana_actual":1,"tiene_siguiente":false,"estructura":\#(estructuraOtros)}"#
    return try! JSONDecoder().decode(RutinaActiva.self, from: Data(fila.utf8))
}

@MainActor
private func modeloOtros(_ b: Banco) -> ModeloEntreno {
    let r = b.reloj
    return ModeloEntreno(cliente: ClienteRPC(transporte: b.servidor), token: "tok-prueba", outbox: b.cola, disco: b.disco,
                         rutina: rutinaOtros(), catalogo: catalogoReal, zona: zonaAR, reloj: { Date(timeIntervalSince1970: r.ms / 1000) })
}

@Suite("Sustituir con los otros del mismo músculo (revisión del 21-oct)", .serialized)
@MainActor
struct SustituirOtrosTests {
    /// Hallazgo 1: «Sustituir» miraba solo las variantes. A los fondos (van a Dips_-_Chest_Version) y a la patada de
    /// tríceps (Tricep_Dumbbell_Kickback), sin variantes, se les apagaba el botón y se les decía «No hay otra variante
    /// equivalente…» aunque tenían 26 a 30 otros ejercicios de su músculo.
    @Test func sinVariantesPeroConOtrosDelMismoMusculoSeSustituye() throws {
        let b = Banco()
        let m = modeloOtros(b)
        #expect(catalogoReal.resolver(try #require(m.dia.ejercicio("fon-d1-1")))?.slugEn == "Dips_-_Chest_Version")
        #expect(catalogoReal.resolver(try #require(m.dia.ejercicio("pat-d1-2")))?.slugEn == "Tricep_Dumbbell_Kickback")
        for lugar in ["fon-d1-1", "pat-d1-2"] {
            let t = try #require(m.tarjeta(lugar))
            #expect(m.sustitutos(lugar).isEmpty, "\(lugar): sin variantes del mismo movimiento")
            #expect(m.otrosDelMismoMusculo(lugar).count >= 15, "\(lugar): \(m.otrosDelMismoMusculo(lugar).count) otros")
            #expect(t.puedeSustituir, "\(lugar): con otros del mismo músculo se puede sustituir")
        }
        // Con variantes, como siempre.
        #expect(!m.sustitutos("ext-d1-0").isEmpty && m.tarjeta("ext-d1-0")?.puedeSustituir == true)
        // Sin ninguna de las dos no se puede (y la tarjeta dice que no hay con qué).
        #expect(m.sustitutos("inv-d1-3").isEmpty && m.otrosDelMismoMusculo("inv-d1-3").isEmpty)
        #expect(m.tarjeta("inv-d1-3")?.puedeSustituir == false)
    }

    /// Hallazgo 2: al cambiar de movimiento a mitad del ejercicio, el kg y el agarre del plan pasaban al sustituto. La
    /// extensión en polea con Soga, 2 series de 30 kg × 12, y después «Fondos · Peso corporal»: la serie 3 sugería 30 kg y
    /// se grababa {ejercicioNombre: "Fondos", peso: 30, notas: "Soga"} (récord e historial de fondos sucios).
    @Test func alCambiarDeMovimientoNoSeHeredanElKgNiElAgarre() async throws {
        let b = Banco()
        let m = modeloOtros(b)
        let lugar = "ext-d1-0"
        func carga(_ i: Int) async -> JSONValue? { await b.cola.operaciones.first { $0.dedupeKey == "carga_d1_\(lugar)_\(i)_s1" }?.payload["datos"] }
        m.elegirVariante(lugar, "Soga")
        for i in 0..<2 {
            m.escribir(lugar, i, campo: "reps", valor: "12")
            m.escribir(lugar, i, campo: "kg", valor: "30")
            await m.confirmarSerie(lugar, i) { _ in true }
        }
        #expect(await carga(1)?["notas"]?.comoTexto == "Soga", "con el selector a la vista, el agarre viaja")
        #expect(m.dia.ejercicios[lugar]?.series[1].nombreRegistrado == "Extensión tríceps en polea")

        let fondos = try #require(m.otrosDelMismoMusculo(lugar).first { $0.nombre == "Fondos" && $0.equipo == "Peso corporal" })
        await m.sustituir(lugar, por: fondos, fijar: false)
        let t = try #require(m.tarjeta(lugar))
        #expect(t.variantes == nil, "los fondos no muestran el selector de agarre")
        #expect(t.filas[2].placeholderKg.isEmpty, "la serie 3 no sugiere los 30 kg de la polea: \(t.filas[2].placeholderKg)")
        // Con las reps y sin kg no hay de dónde heredarlo: no se registra.
        m.escribir(lugar, 2, campo: "reps", valor: "10")
        await m.confirmarSerie(lugar, 2) { _ in true }
        #expect(m.dia.ejercicios[lugar]?.series[2].confirmada == false)
        #expect(await carga(2) == nil)
        // Con el lastre cargado va con el nombre de los fondos y sin el agarre de la polea.
        m.escribir(lugar, 2, campo: "kg", valor: "10")
        await m.confirmarSerie(lugar, 2) { _ in true }
        let s3 = try #require(await carga(2))
        #expect(s3["ejercicioNombre"]?.comoTexto == "Fondos" && s3["peso"] == .numero(10) && s3["notas"] == .null, "\(s3)")

        // De vuelta a la polea: la serie 4 hereda de las de la polea (30), no de los fondos, y el agarre vuelve.
        await m.revertirSustitucion(lugar)
        m.escribir(lugar, 3, campo: "reps", valor: "11")
        await m.confirmarSerie(lugar, 3) { _ in true }
        let s4 = try #require(await carga(3))
        #expect(s4["ejercicioNombre"]?.comoTexto == "Extensión tríceps en polea" && s4["peso"] == .numero(30) && s4["notas"]?.comoTexto == "Soga", "\(s4)")
    }

    /// La sugerencia de kg de la tabla es la de la confirmación (revisión del 21-oct: la tabla la calculaba con todas las
    /// series). Con la polea, las reps de la serie 3 sugieren los 30; ya en fondos, nada, y sin kg no se registra.
    @Test func laSugerenciaDeKgEsLaQueSeHereda() async throws {
        let b = Banco()
        let m = modeloOtros(b)
        let lugar = "ext-d1-0"
        for i in 0..<2 {
            m.escribir(lugar, i, campo: "reps", valor: "12")
            m.escribir(lugar, i, campo: "kg", valor: "30")
            await m.confirmarSerie(lugar, i) { _ in true }
        }
        m.escribir(lugar, 2, campo: "reps", valor: "10")
        #expect(m.tarjeta(lugar)?.filas[2].sugerenciaKg == "30", "con la polea se heredan los 30")
        let fondos = try #require(m.otrosDelMismoMusculo(lugar).first { $0.nombre == "Fondos" && $0.equipo == "Peso corporal" })
        await m.sustituir(lugar, por: fondos, fijar: false)
        let f = try #require(m.tarjeta(lugar)?.filas[2])
        #expect(f.sugerenciaKg.isEmpty && !f.puedeConfirmar, "ya en fondos no sugiere los kg de la polea: \(f)")
    }

    /// Una serie ya registrada se vuelve a mandar con el ejercicio con el que se registró, aunque el lugar ahora esté
    /// sustituido (o se haya vuelto al original): el RIR, o el lápiz y confirmar de nuevo, corrigen lo que se hizo. Antes
    /// el sustituto ganaba y la serie de la polea se volvía a mandar como fondos, con sus 30 kg.
    @Test func unaSerieYaRegistradaSeVuelveAMandarConSuEjercicio() async throws {
        let b = Banco()
        let m = modeloOtros(b)
        let lugar = "ext-d1-0"
        func carga(_ i: Int) async -> JSONValue? { await b.cola.operaciones.first { $0.dedupeKey == "carga_d1_\(lugar)_\(i)_s1" }?.payload["datos"] }
        m.elegirVariante(lugar, "Soga")
        for i in 0..<2 {
            m.escribir(lugar, i, campo: "reps", valor: "12")
            m.escribir(lugar, i, campo: "kg", valor: "30")
            await m.confirmarSerie(lugar, i) { _ in true }
        }
        let fondos = try #require(m.otrosDelMismoMusculo(lugar).first { $0.nombre == "Fondos" && $0.equipo == "Peso corporal" })
        await m.sustituir(lugar, por: fondos, fijar: false)

        // El RIR de la serie 2, ya con los fondos puestos: va como la extensión, con su agarre.
        await m.elegirRIR(lugar, 1, 2)
        let s2 = try #require(await carga(1))
        #expect(s2["ejercicioNombre"]?.comoTexto == "Extensión tríceps en polea" && s2["peso"] == .numero(30)
                    && s2["notas"]?.comoTexto == "Soga" && s2["rir"] == .numero(2), "\(s2)")
        // El lápiz sobre la serie 1: se corrige el kg y sigue siendo de la extensión.
        await m.editarSerie(lugar, 0)
        m.escribir(lugar, 0, campo: "kg", valor: "32")
        await m.confirmarSerie(lugar, 0) { _ in true }
        let s1 = try #require(await carga(0))
        #expect(s1["ejercicioNombre"]?.comoTexto == "Extensión tríceps en polea" && s1["peso"] == .numero(32) && s1["notas"]?.comoTexto == "Soga", "\(s1)")
        // Y otra vez el lápiz y el ✓, sin tocar nada: sigue siendo de la extensión, con su agarre.
        await m.editarSerie(lugar, 0)
        await m.confirmarSerie(lugar, 0) { _ in true }
        let otraVez = try #require(await carga(0))
        #expect(otraVez["ejercicioNombre"]?.comoTexto == "Extensión tríceps en polea" && otraVez["peso"] == .numero(32)
                    && otraVez["notas"]?.comoTexto == "Soga", "\(otraVez)")
        #expect(m.dia.ejercicios[lugar]?.series[0].nombreRegistrado == "Extensión tríceps en polea")

        // La serie 3 con los fondos y después de vuelta a la polea: su RIR va como fondos, sin el agarre de la polea.
        m.escribir(lugar, 2, campo: "reps", valor: "10")
        m.escribir(lugar, 2, campo: "kg", valor: "10")
        await m.confirmarSerie(lugar, 2) { _ in true }
        await m.revertirSustitucion(lugar)
        await m.elegirRIR(lugar, 2, 1)
        let s3 = try #require(await carga(2))
        #expect(s3["ejercicioNombre"]?.comoTexto == "Fondos" && s3["peso"] == .numero(10) && s3["notas"] == .null && s3["rir"] == .numero(1), "\(s3)")
    }

    /// El agarre del plan no filtra el historial del sustituto (revisión del 21-oct): con la polea en «Soga» y los fondos
    /// puestos, lo de la última vez sale de las series de fondos (sin notas). Con el filtro de «Soga», que no es el agarre
    /// por defecto, quedaban afuera y no había sugerencia.
    @Test func elAgarreDelPlanNoFiltraElHistorialDelSustituto() async throws {
        let b = Banco()
        b.servidor.cuando("get_historico_por_clave", #"[{"clave":"fondos","registrado_en":"2026-10-07T21:04:00+00:00","peso_kg":10,"reps_realizadas":8,"rir_real":1,"serie_numero":3,"notas":null,"ejercicio_nombre":"Fondos"},{"clave":"fondos","registrado_en":"2026-10-07T21:02:00+00:00","peso_kg":10,"reps_realizadas":9,"rir_real":1,"serie_numero":2,"notas":null,"ejercicio_nombre":"Fondos"},{"clave":"fondos","registrado_en":"2026-10-07T21:00:00+00:00","peso_kg":10,"reps_realizadas":10,"rir_real":2,"serie_numero":1,"notas":null,"ejercicio_nombre":"Fondos"}]"#)
        let m = modeloOtros(b)
        let lugar = "ext-d1-0"
        m.elegirVariante(lugar, "Soga")
        let fondos = try #require(m.otrosDelMismoMusculo(lugar).first { $0.nombre == "Fondos" && $0.equipo == "Peso corporal" })
        await m.sustituir(lugar, por: fondos, fijar: false)
        #expect(m.dia.historial[lugar]?.count == 3, "llegó el historial de los fondos")
        let f = try #require(m.tarjeta(lugar)?.filas[0])
        #expect(f.placeholderKg == "10" && f.pista?.negrita == "10kg × 10", "lo de la última vez con los fondos: \(f)")
    }

    /// Reconfirmar una serie vieja con el lugar ya sustituido se evalúa contra el ejercicio de la serie (revisión del
    /// 21-oct): de crunch en máquina a plancha (sin kg), el lápiz y el ✓ sobre la serie del crunch le borraban el kg y la
    /// grababan con peso 0 bajo el nombre del crunch.
    @Test func reconfirmarUnaSerieViejaConservaSuKg() async throws {
        let b = Banco()
        let m = modeloOtros(b)
        let lugar = "cru-d1-4"
        func carga(_ i: Int) async -> JSONValue? { await b.cola.operaciones.first { $0.dedupeKey == "carga_d1_\(lugar)_\(i)_s1" }?.payload["datos"] }
        m.escribir(lugar, 0, campo: "reps", valor: "15")
        m.escribir(lugar, 0, campo: "kg", valor: "40")
        await m.confirmarSerie(lugar, 0) { _ in true }
        #expect(await carga(0)?["peso"] == .numero(40))
        let plancha = SustitutoEjercicio(slug: "Plank", nombre: "Plancha", nombreIngles: "Plank", equipo: "Peso corporal", equipoCrudo: "body only",
                                         musculo: "abdominals", patron: "core_anti_extension", imagenes: .init(eccentric: nil, concentric: nil), mismoEquipo: false)
        await m.sustituir(lugar, por: plancha, fijar: false)
        #expect(m.tarjeta(lugar)?.filas[1].sinKg == true, "la plancha no lleva kg")
        await m.editarSerie(lugar, 0)
        m.escribir(lugar, 0, campo: "reps", valor: "14")
        await m.confirmarSerie(lugar, 0) { _ in true }
        let s1 = try #require(await carga(0))
        #expect(s1["ejercicioNombre"]?.comoTexto == "Crunch en máquina" && s1["peso"] == .numero(40) && s1["reps"] == .numero(14), "\(s1)")
        #expect(m.dia.ejercicios[lugar]?.series[0].kg == "40")
    }

    /// El crunch con soga del catálogo (Rope_Crunch o Standing_Rope_Crunch, de polea) se traduce «Crunch» y quedaba sin kg
    /// al sustituir (21-oct): ahora lo decide su equipo (27-oct). Se registra con kg y, de vuelta al original, el lápiz y el
    /// ✓ sobre esa serie no se lo borran aunque «Crunch» por el nombre no lleve.
    @Test func elCrunchConSogaLlevaKgPorSuEquipo() async throws {
        let b = Banco()
        let m = modeloOtros(b)
        let lugar = "cru-d1-4"
        func carga(_ i: Int) async -> JSONValue? { await b.cola.operaciones.first { $0.dedupeKey == "carga_d1_\(lugar)_\(i)_s1" }?.payload["datos"] }
        let soga = try #require(m.sustitutos(lugar).first { $0.nombre == "Crunch" && $0.equipoCrudo == "cable" })
        await m.sustituir(lugar, por: soga, fijar: false)
        let t = try #require(m.tarjeta(lugar))
        #expect(t.efectivo.ejercicio.nombre == "Crunch" && !t.sinKg && t.filas.allSatisfy { !$0.sinKg }, "el crunch con soga lleva kg")
        m.escribir(lugar, 0, campo: "reps", valor: "15")
        m.escribir(lugar, 0, campo: "kg", valor: "25")
        await m.confirmarSerie(lugar, 0) { _ in true }
        let s1 = try #require(await carga(0))
        #expect(s1["ejercicioNombre"]?.comoTexto == "Crunch" && s1["peso"] == .numero(25), "\(s1)")

        await m.revertirSustitucion(lugar)
        await m.editarSerie(lugar, 0)
        m.escribir(lugar, 0, campo: "reps", valor: "14")
        await m.confirmarSerie(lugar, 0) { _ in true }
        let otraVez = try #require(await carga(0))
        #expect(otraVez["ejercicioNombre"]?.comoTexto == "Crunch" && otraVez["peso"] == .numero(25) && otraVez["reps"] == .numero(14), "\(otraVez)")
        #expect(m.dia.ejercicios[lugar]?.series[0].kg == "25")

        // El crunch de peso corporal del catálogo sigue sin kg.
        let corporal = try #require(m.sustitutos(lugar).first { $0.nombre == "Crunch" && $0.equipoCrudo == "body only" })
        await m.sustituir(lugar, por: corporal, fijar: false)
        #expect(m.tarjeta(lugar)?.sinKg == true, "el crunch de peso corporal no lleva kg")
    }

    /// Hallazgo 4: con un plan sin fotos (la demo, que es la que mira Apple, o la cuenta test-nativa-ios), al reabrir
    /// «Cambiar» después de pasar la extensión en polea a fondos, las listas se armaban sobre los fondos: sin foto del
    /// original, `referencia(de:)` caía en la del sustituto.
    @Test func alReabrirCambiarLasListasSonLasDelOriginal() async throws {
        let b = Banco()
        let m = modeloOtros(b)
        let lugar = "ext-d1-0"
        let plan = try #require(m.dia.ejercicio(lugar))
        #expect(plan.imagenes == nil && plan.catalogoSlug == nil, "el plan no trae fotos ni slug")
        let variantes = m.sustitutos(lugar), otros = m.otrosDelMismoMusculo(lugar)
        #expect(!variantes.isEmpty && !otros.isEmpty)
        let fondos = try #require(otros.first { $0.nombre == "Fondos" && $0.equipo == "Peso corporal" })
        await m.sustituir(lugar, por: fondos, fijar: true)
        let ef = m.efectivo(plan)
        #expect(ef.sustituido && ef.ejercicio.imagenes?.eccentric != nil, "el sustituto sí trae foto")
        #expect(m.sustitutos(lugar) == variantes, "las variantes son las de la extensión: \(m.sustitutos(lugar).map(\.nombre))")
        #expect(m.otrosDelMismoMusculo(lugar) == otros, "los otros son los de la extensión")
        #expect(m.tarjeta(lugar)?.puedeSustituir == true)
    }
}
