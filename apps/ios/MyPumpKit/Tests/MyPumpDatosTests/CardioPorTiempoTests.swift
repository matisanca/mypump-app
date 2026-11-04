import Foundation
import Testing
import MyPumpModelos
@testable import MyPumpReglas
@testable import MyPumpDatos

// Reporte del 4-nov: la cinta, tal como la manda el plan (sin duración y con `progresion: []`), pedía reps, kg y RIR en
// vez de ir por tiempo, y no ofrecía «Sustituir». `normalizarRutina` le pone `series = 1` a todo lo que no trae series,
// así que la sesión le armaba una fila. Gemelo de CardioPorTiempoTest.kt.

private let raizDelRepo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
private let catalogoReal = try! CatalogoEjercicios(json: Data(contentsOf: raizDelRepo.appendingPathComponent("apps/shared/catalogo-ejercicios.json")))

/// La cinta exacta del reporte: cardio en el día 1 y calentamiento en el día 2, con un calentamiento de fuerza (banda)
/// y un ejercicio de fuerza al lado. Bloque 2, semana 3.
private let estructuraCardio = """
{"semanas_total":12,"dias":[
 {"id":"d1","n":1,"nombre":"TIRÓN","bloques":[{"titulo":"BLOQUE 1","ejercicios":[
  {"id":"cinta-caminata-inclinada-10-min-d1-0","tipo":"cardio","nombre":"Cinta (caminata inclinada 10 min)","catalogo_slug":"Walking_Treadmill","progresion":[],"descanso_segundos":0,"notas_tecnica":"Inclinación 10-12 %"},
  {"id":"movilidad-d1-1","tipo":"calentamiento","nombre":"Movilidad de hombros con banda","progresion":[],"series":2,"reps":"15","descanso_segundos":0},
  {"id":"remo-d1-2","tipo":"compuesto","nombre":"Remo con barra","descanso_segundos":120,"progresion":[{"semana":1,"series":3,"reps":"8-10","rir":"1-2"},{"semana":2,"series":3,"reps":"8-10","rir":"1"},{"semana":3,"series":4,"reps":"8","rir":"1"}]}]}]},
 {"id":"d2","n":2,"nombre":"PIERNA","bloques":[{"titulo":"BLOQUE 1","ejercicios":[
  {"id":"cinta-caminata-inclinada-10-min-d2-0","tipo":"calentamiento","nombre":"Cinta (caminata inclinada 10 min)","catalogo_slug":"Walking_Treadmill","progresion":[],"descanso_segundos":0},
  {"id":"sentadilla-d2-1","tipo":"compuesto","nombre":"Sentadilla con barra","descanso_segundos":150,"progresion":[{"semana":1,"series":3,"reps":"8","rir":"2"}]}]}]}]}
"""

private func rutinaCardio() -> RutinaActiva {
    let fila = #"{"id":"rut-cardio","version":1,"semana_actual":3,"tiene_siguiente":false,"estructura":\#(estructuraCardio)}"#
    return try! JSONDecoder().decode(RutinaActiva.self, from: Data(fila.utf8))
}

private func estructuraNormalizada() -> EstructuraRutina { NormalizacionRutina.normalizar(rutinaCardio().estructura).estructura }

private func registros(_ id: String) -> [RegistroSesion] {
    let j = #"[{"ejercicio_id":"\#(id)","serie_numero":1,"peso_kg":0,"reps_realizadas":1,"rir_real":2,"ejercicio_nombre":"Cinta (caminata inclinada 10 min)"}]"#
    return try! JSONDecoder().decode([RegistroSesion].self, from: Data(j.utf8))
}

@MainActor
private func modeloCardio(_ b: Banco) -> ModeloEntreno {
    let r = b.reloj
    let m = ModeloEntreno(cliente: ClienteRPC(transporte: b.servidor), token: "tok-prueba", outbox: b.cola, disco: b.disco,
                          rutina: rutinaCardio(), catalogo: catalogoReal, zona: zonaAR, reloj: { Date(timeIntervalSince1970: r.ms / 1000) })
    return m
}

@Suite("Cardio por tiempo (reporte del 4-nov)")
struct CardioPorTiempoReglasTests {
    @Test func laCintaEsCardioComoCardioYComoCalentamiento() throws {
        let est = estructuraNormalizada()
        let d1 = est.dias[0].bloques[0].ejercicios, d2 = est.dias[1].bloques[0].ejercicios
        // La normalización le sigue poniendo series = 1 (como la web): la decisión es de la pauta.
        #expect(d1[0].series == 1)
        for cinta in [d1[0], d2[0]] {
            #expect(ReglasEjercicio.esCardio(cinta), "\(cinta.tipo ?? "-")")
            let p = Progresiones.pauta(cinta, semana: 3)
            #expect(p.series == nil && p.rir == nil, "\(cinta.tipo ?? "-"): \(p)")
        }
        // El calentamiento de fuerza y la fuerza siguen con sus series.
        #expect(!ReglasEjercicio.esCardio(d1[1]) && Progresiones.pauta(d1[1], semana: 3).series == 2)
        #expect(!ReglasEjercicio.esCardio(d1[2]) && Progresiones.pauta(d1[2], semana: 3).series == 4)
    }

    @Test func laSesionNoLeArmaFilasConOSinHistorial() throws {
        let est = estructuraNormalizada()
        for (i, id) in [(0, "cinta-caminata-inclinada-10-min-d1-0"), (1, "cinta-caminata-inclinada-10-min-d2-0")] {
            var d = DiaEnCurso(dia: est.dias[i], semana: 3, sesionId: "ses-1", zona: zonaAR)
            #expect(d.ejercicios[id]?.series.isEmpty == true, "\(id): sin historial")
            // Con una carga vieja en esa clave (un cliente que registró la cinta como serie): sigue sin filas.
            d.aplicarRegistros(registros(id))
            #expect(d.ejercicios[id]?.series.isEmpty == true, "\(id): con historial")
        }
        let d = DiaEnCurso(dia: est.dias[0], semana: 3, sesionId: "ses-1", zona: zonaAR)
        #expect(d.ejercicios["movilidad-d1-1"]?.series.count == 2, "el calentamiento con banda va por series")
        #expect(d.ejercicios["remo-d1-2"]?.series.count == 4)
    }

    @Test func detectaCardioPorTipoNombreOSlug() {
        #expect(ReglasEjercicio.esCardio(nombre: "Cualquier cosa", tipo: " Cardio "))
        #expect(ReglasEjercicio.esCardio(nombre: "Bicicleta fija 15 min", tipo: "calentamiento"))
        #expect(ReglasEjercicio.esCardio(nombre: "Elíptico", tipo: nil))
        #expect(ReglasEjercicio.esCardio(nombre: "Escaladora 5'", tipo: ""))
        #expect(ReglasEjercicio.esCardio(nombre: "Remo ergómetro", tipo: "calentamiento"))
        #expect(ReglasEjercicio.esCardio(nombre: "Entrada en calor", tipo: "calentamiento", slugs: ["Rowing_Stationary"]))
        #expect(!ReglasEjercicio.esCardio(nombre: "Remo con barra", tipo: nil))
        #expect(!ReglasEjercicio.esCardio(nombre: "Caminata del granjero", tipo: nil))
        #expect(!ReglasEjercicio.esCardio(nombre: "Face-pull con banda", tipo: "calentamiento"))
        // Revisión del 4-nov: «bici» como palabra entera, el core y la caminata lateral no son cardio.
        #expect(!ReglasEjercicio.esCardio(nombre: "Curl en cable a una mano (cabeza corta — pico bicipital)", tipo: "calentamiento"), "Curl en cable a una mano (cabeza corta — pico bicipital)")
        #expect(!ReglasEjercicio.esCardio(nombre: "Curl de bíceps liviano", tipo: "calentamiento"), "Curl de bíceps liviano")
        #expect(!ReglasEjercicio.esCardio(nombre: "Crunch bicicleta", tipo: "calentamiento"), "Crunch bicicleta")
        #expect(!ReglasEjercicio.esCardio(nombre: "Caminata lateral con banda", tipo: "calentamiento"), "Caminata lateral con banda")
        #expect(!ReglasEjercicio.esCardio(nombre: "Mountain climbers (escaladores)", tipo: "calentamiento"), "Mountain climbers (escaladores)")
        #expect(!ReglasEjercicio.esCardio(nombre: "Escalador", tipo: "calentamiento"), "Escalador")
        #expect(ReglasEjercicio.esCardio(nombre: "Bicis 10 min", tipo: "calentamiento"), "Bicis 10 min")
        #expect(ReglasEjercicio.esCardio(nombre: "Cardio suave 5 min", tipo: "calentamiento"), "Cardio suave 5 min")
        #expect(ReglasEjercicio.esCardio(nombre: "Cicloergómetro", tipo: "calentamiento"), "Cicloergómetro")
        #expect(ReglasEjercicio.esCardio(nombre: "Bicicleta reclinada", tipo: "calentamiento"), "Bicicleta reclinada")
        #expect(ReglasEjercicio.esCardio(nombre: "Cinta (trote)", tipo: "calentamiento"), "Cinta (trote)")
        #expect(ReglasEjercicio.esCardio(nombre: "Elíptico", tipo: "calentamiento"), "Elíptico")
        #expect(!ReglasEjercicio.esCardio(nombre: "Cinta (caminata)", tipo: "compuesto"), "un tipo de fuerza manda")
    }
}

@Suite("Cardio por tiempo en el modelo (reporte del 4-nov)", .serialized)
@MainActor
struct CardioPorTiempoModeloTests {
    @Test func laTarjetaVaPorTiempoYOfreceSustituirCardio() async throws {
        let b = Banco()
        let m = modeloCardio(b)
        let lugar = "cinta-caminata-inclinada-10-min-d1-0"
        // Con historial de la clave (la cinta registrada antes como serie de 60 kg × 10) y la serie de hoy en el servidor.
        let h = #"[{"clave":"cinta","registrado_en":"2026-10-30T12:00:00Z","peso_kg":60,"reps_realizadas":10,"rir_real":2,"serie_numero":1}]"#
        m.dia.historial[lugar] = try JSONDecoder().decode([RegistroHistorico].self, from: Data(h.utf8))
        m.dia.aplicarRegistros(registros(lugar))
        let t = try #require(m.tarjeta(lugar))
        #expect(t.filas.isEmpty, "sin tabla de reps, kg y RIR")
        #expect(t.pauta.series == nil && t.pauta.rir == nil)
        #expect(t.ultimaVez == nil && t.record == nil, "sin «Última vez» ni récord de kg en la cinta")
        #expect(m.leyendaRIR(lugar) == nil)
        #expect(m.preparacion(lugar).isEmpty)
        #expect(t.puedeSustituir, "la cinta ofrece «Sustituir»")
        let subs = m.sustitutos(lugar)
        #expect(subs.map(\.nombre) == ["Cinta (trote)", "Bicicleta fija", "Bicicleta reclinada", "Elíptico", "Remo ergómetro", "Escaladora"])
        #expect(m.otrosDelMismoMusculo(lugar).isEmpty)
        // Sustituida por la bici: sigue por tiempo.
        let bici = try #require(subs.first { $0.nombre == "Bicicleta fija" })
        await m.sustituir(lugar, por: bici, fijar: false)
        let tb = try #require(m.tarjeta(lugar))
        #expect(tb.efectivo.ejercicio.nombre == "Bicicleta fija")
        #expect(tb.filas.isEmpty && tb.pauta.series == nil)
        // La fuerza de al lado, igual que siempre.
        #expect(m.tarjeta("remo-d1-2")?.filas.count == 4)
        #expect(m.tarjeta("movilidad-d1-1")?.filas.count == 2)
    }
}
