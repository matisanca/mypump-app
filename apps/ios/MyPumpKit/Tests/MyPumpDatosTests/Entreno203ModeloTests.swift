import Foundation
import Testing
import MyPumpModelos
import MyPumpReglas
@testable import MyPumpDatos

// 2.0.3, Entreno en el modelo: lo que depende del catálogo (el equipo del ejercicio del plan para la preparación), el
// aviso de primera vez con la leyenda del RIR y el caché de la preparación.

@Suite("2.0.3: Entreno en el modelo", .serialized)
@MainActor
struct Entreno203ModeloTests {
    /// «Sentadilla» a secas no dice barra: la reconoce por el `equipment` del catálogo.
    static let catalogo = try! CatalogoEjercicios(json: Data("""
    [{"slug_en":"Barbell_Squat","name_en":"Barbell Squat","name_normalized":"sentadilla","primary_muscle":"quadriceps","equipment":"barbell"}]
    """.utf8))

    func modelo() -> ModeloEntreno {
        let fila = #"{"id":"rut-203","version":1,"semana_actual":1,"tiene_siguiente":false,"estructura":{"semanas_total":4,"dias":[{"id":"d1","n":1,"nombre":"PIERNA","bloques":[{"titulo":"BLOQUE 1","ejercicios":[{"id":"sen-d1-0","nombre":"Sentadilla","tipo":"compuesto","descanso_segundos":120,"progresion":[{"semana":1,"series":2,"reps":"8","rir":"0"}]}]}]}]}}"#
        let rutina = try! JSONDecoder().decode(RutinaActiva.self, from: Data(fila.utf8))
        return ModeloEntreno(cliente: ClienteRPC(transporte: Servidor()), token: nil, outbox: nil, disco: nil, rutina: rutina,
                             catalogo: Self.catalogo, zona: zonaAR, reloj: { Date(timeIntervalSince1970: AHORA / 1000) })
    }

    @Test func laPreparacionUsaElEquipoDelCatalogo() {
        let m = modelo()
        m.escribir("sen-d1-0", 0, campo: "kg", valor: "60")
        let p = m.preparacion("sen-d1-0")
        #expect(p.first?.tipo == .calentamiento && p.first?.barraSola == true && p.first?.kg == 20, "\(p)")
        #expect(p.map(\.kg) == [20, 35, 50, 65])
        // El caché: tipear las reps no la cambia; el kg de la primera efectiva sí.
        m.escribir("sen-d1-0", 0, campo: "reps", valor: "8")
        #expect(m.preparacion("sen-d1-0") == p)
        m.escribir("sen-d1-0", 0, campo: "kg", valor: "80")
        #expect(m.preparacion("sen-d1-0").map(\.kg) == [20, 47.5, 67.5, 85])
    }

    @Test func elAvisoDePrimeraVezDiceLaLeyenda() {
        let m = modelo()
        m.dia.historial["sen-d1-0"] = []
        let c = m.tarjeta("sen-d1-0")?.filas.first?.calibracion ?? ""
        #expect(c.contains("llegues a 8 reps al fallo") && !c.contains("1–2"), "\(c)")
        #expect(m.leyendaRIR("sen-d1-0") == "Al fallo")
    }
}
