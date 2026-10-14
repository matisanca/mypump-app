import Foundation
import Testing
import MyPumpModelos
@testable import MyPumpDatos
@testable import MyPumpReglas

/// `Int()` de Swift cierra la app con NaN, infinito o más de 2^63, y todo esto se lee de afuera: la base, la cola, el
/// almacenamiento de la Capacitor y las preferencias. Lo del almacenamiento viejo corre al arrancar, así que un solo
/// valor raro cerraba la app en cada apertura. Los encontró el port de Android (14-oct); cada test es una entrada real.
struct NumerosAbsurdosTests {
    private let token = "tokAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
    private let ahora = Date(timeIntervalSince1970: 1_791_990_000)

    @Test func rutinaConSemanaGigante() throws {
        let json = #"{"id":"r","version":1,"semana_actual":1e19,"estructura":{"dias":[]}}"#
        let r = try JSONDecoder().decode(RutinaActiva.self, from: Data(json.utf8))
        #expect(r.semanaActual == 1)   // no sirve: queda el valor por defecto, como con cualquier otro dato roto
        let normal = try JSONDecoder().decode(RutinaActiva.self, from: Data(#"{"id":"r","semana_actual":3.0}"#.utf8))
        #expect(normal.semanaActual == 3)
    }

    @Test(arguments: ["nan", "NaN", "inf", "-Infinity", "1e20", "-1e300", "abc", ""])
    func aguaConUnValorRaro(valor: String) {
        var h = HabitosHoy()
        h.aplicar(campo: "vasos_agua", valor: .texto(valor))
        #expect(abs(h.vasosAgua) <= 1_000_000_000_000_000)
    }

    @Test func aguaNormal() {
        var h = HabitosHoy()
        h.aplicar(campo: "vasos_agua", valor: .texto("7"))
        #expect(h.vasosAgua == 7)
        h.aplicar(campo: "vasos_agua", valor: .numero(4))
        #expect(h.vasosAgua == 4)
    }

    @Test func recordatorioConHoraImposible() {
        let porDefecto = PreferenciasAvisos.Recordatorio(on: true, hora: 11, min: 0)
        #expect(PreferenciasAvisos.leer(#"{"check":{"on":true,"hora":1e20,"min":0}}"#).check == porDefecto)
        #expect(PreferenciasAvisos.leer(#"{"check":{"on":false,"hora":25,"min":-3}}"#).check == .init(on: false, hora: 11, min: 0))
        #expect(PreferenciasAvisos.leer(#"{"check":{"on":true,"hora":9.5,"min":1e300}}"#).check == porDefecto)
        #expect(PreferenciasAvisos.leer(#"{"check":{"on":true,"hora":9,"min":30}}"#).check == .init(on: true, hora: 9, min: 30))
    }

    @Test func almacenamientoViejoConNumerosRaros() {
        let op = #"{"_id":"a1","kind":"peso","payload":{"fecha":"2026-10-13","valor":80},"dedupeKey":"peso|2026-10-13","tries":"nan","ts":"inf"}"#
        let op2 = #"{"_id":"a2","kind":"peso","payload":{"fecha":"2026-10-12","valor":81},"dedupeKey":"peso|2026-10-12","tries":1e300,"ts":1}"#
        let items = [
            "mypump_token": token,
            "mypump_outbox_\(token)": "[\(op),\(op2)]",
            "mypump_fotoq_\(token)": #"{"2026-10-12|frente":{"pose":"frente","fecha":"2026-10-12","dataUrl":"data:image/jpeg;base64,AA==","intentos":"nan"},"2026-10-12|perfil":{"pose":"perfil","fecha":"2026-10-12","dataUrl":"data:image/jpeg;base64,AA==","intentos":-1e300}}"#,
            "mypump_exercise_swaps_r1": #"{"ex1":{"original":{"nombre":"A"},"current":{"nombre":"B"},"fijado":false,"semana":"nan","diaId":"d1"},"ex2":{"original":{"nombre":"A"},"current":{"nombre":"C"},"fijado":false,"semana":1e300,"diaId":"d1"}}"#,
        ]
        let plan = MigracionLegado.planificar(items, ahora: ahora)
        let cola = plan.colas.first { $0.token == token }
        #expect(cola?.ops.map(\.operacion.tries) == [0, 1_000_000_000_000_000])
        #expect(cola?.fotos.values.map(\.intentos).sorted() == [0, 0])
        #expect(plan.sustituciones["r1"]?["ex1"]?.semana == nil)
        #expect(plan.sustituciones["r1"]?["ex2"]?.semana == 1_000_000_000_000_000)
    }

    @Test func sesionesViejasConSemanaGigante() {
        let l = LegadoEntreno.desdeAlmacenamiento(["mypump_sesion_\(token)_d1": "s-1",
                                                   "mypump_sesion_\(token)_d1_semana": "99999999999999999999"],
                                                  token: token, rutinaId: "r1")
        #expect(l.sesiones.first?.sesionId == "s-1")
        #expect(l.sesiones.first?.semana == nil)
    }

    @MainActor @Test func respuestasDeLaIngestaConNumerosRaros() {
        #expect(SincronizadorSalud.numeroJS(.numero(1e300)) == 1_000_000_000_000_000)
        #expect(SincronizadorSalud.numeroJS(.texto("nan")) == 0)
        #expect(SincronizadorSalud.numeroJS(.texto(" 12 ")) == 12)
        #expect(SincronizadorSalud.numeroJS(.numero(7)) == 7)
    }
}

@Suite("Lo que se muestra con números raros de la base")
struct NumerosAbsurdosVistaTests {
    @Test func formatosDeSalud() {
        #expect(SaludVista.enteroJS(1e21) == "1e+21")
        #expect(SaludVista.enteroJS(57.4) == "57")
        #expect(SaludVista.enteroJS(-0.3) == "0")
        #expect(SaludVista.miles(1e20) == "100.000.000.000.000.000.000")
        #expect(SaludVista.miles(8548.2) == "8.548")
        #expect(SaludVista.miles(-1234) == "-1.234")
        #expect(SaludVista.horaReloj(1e300) == SaludVista.horaReloj(1e300.truncatingRemainder(dividingBy: 1440)))
        #expect(SaludVista.horaReloj(-90) == "22:30")
        #expect(SaludVista.horas(425) == "7h 05")
        _ = SaludVista.horas(1e300)   // antes: cierre
    }

    @Test func pesoConUnValorAbsurdo() {
        let serie = [PesoCorporal.Punto(fecha: "2026-10-01", kg: 80), PesoCorporal.Punto(fecha: "2026-10-08", kg: 1e300)]
        #expect(PesoCorporal.deltaSemanal(serie, hoy: "2026-10-08") == 1_000_000_000_000_000)   // antes: cierre
    }
}

@Suite("Un swap de comida con food_data falso (0, \"\", false) no se aplica, como en la web")
struct SwapFalsoTests {
    let original = Alimento(nombre: "Avena", qty: 50, unidad: "g")

    @Test(arguments: [JSONValue.numero(0), .texto(""), .bool(false), .null])
    func noSeAplica(food: JSONValue) {
        #expect(!AnclajeSwaps.aplica(foodData: food, original: original, comidaId: "c1") { [] })
    }

    @Test func unoVerdaderoSinAnclaSiSeAplica() {
        #expect(AnclajeSwaps.aplica(foodData: .objeto(["name": .texto("Pan")]), original: original, comidaId: "c1") { [] })
    }
}
