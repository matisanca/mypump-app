import Foundation
import Testing
import MyPumpModelos
import MyPumpReglas
@testable import MyPumpDatos

/// Reserva clínica (19/11, OK de Mati) en el modelo: un plan con RIR clínico y otro sin RIR, con todo lo que ve el
/// alumno en el teléfono y en el reloj. Con reserva nunca «Al fallo», «llevá al fallo» ni «Subí la carga».
@Suite("Reserva clínica: la pauta del plan en lugar de «Al fallo»", .serialized)
@MainActor
struct ReservaClinicaModeloTests {
    let lugar = "pre-d1-0"
    let prohibido = try! NSRegularExpression(pattern: #"\bal fallo\b|sub[ií]\s+(un poco\s+)?la carga|toca subir|subí la próxima"#,
                                             options: .caseInsensitive)

    /// Press banca 4×10 → 4×8 (bajan las reps: sin reserva, «Subí la carga» y la sugerencia de subir) y unas aperturas
    /// sin historial (el aviso de primera vez). `rir`: el de todas las semanas.
    func rutina(rir: String, semana: Int = 2) -> RutinaActiva {
        func prog(_ reps: [String]) -> String {
            reps.enumerated().map { #"{"semana":\#($0.offset + 1),"series":4,"reps":"\#($0.element)","rir":"\#(rir)"}"# }.joined(separator: ",")
        }
        let est = #"{"semanas_total":4,"dias":[{"id":"d1","n":1,"nombre":"EMPUJE","bloques":[{"titulo":"B1","ejercicios":["#
            + #"{"id":"pre-d1-0","nombre":"Press banca con barra","tipo":"compuesto","descanso_segundos":120,"notas_tecnica":"Dejá 2 repeticiones en reserva y bajá controlado.","aproximaciones":[{"reps":"8","pct":60,"nota":"Con RIR 3, sin apurar."}],"progresion":[\#(prog(["10", "8", "8", "6"]))]},"#
            + #"{"id":"ape-d1-1","nombre":"Aperturas con mancuernas","tipo":"aislamiento","descanso_segundos":90,"progresion":[\#(prog(["12", "12", "10", "10"]))]}"#
            + #"]}]}]}"#
        return try! JSONDecoder().decode(RutinaActiva.self, from: Data(#"{"id":"r1","version":1,"semana_actual":\#(semana),"tiene_siguiente":false,"estructura":\#(est)}"#.utf8))
    }

    /// 80 kg × 10 hace una semana en el press (las aperturas, sin historial).
    func historial(_ b: Banco) {
        let f = (1...4).map { #"{"clave":"\#(ClaveEjercicio.de("Press banca con barra"))","registrado_en":"2026-10-07T18:00:00Z","peso_kg":80,"reps_realizadas":10,"rir_real":0,"serie_numero":\#($0),"notas":null,"ejercicio_nombre":"Press banca con barra"}"# }
        b.servidor.cuando("get_historico_por_clave", "[\(f.joined(separator: ","))]")
    }

    func modelo(_ b: Banco, _ r: RutinaActiva, token: String? = "tok-prueba") async -> ModeloEntreno {
        historial(b)
        let m = b.modelo(r, token: token)
        await m.cargar()
        return m
    }

    /// Todo lo que el alumno lee del entreno: el cartel, cada tarjeta (nota, leyenda, aviso de primera vez, nota técnica y
    /// la de la preparación) y lo que va al reloj.
    func textos(_ m: ModeloEntreno) -> [String] {
        var t: [String] = [m.banner.texto].compactMap { $0 }
        for e in m.dia.lista {
            guard let tj = m.tarjeta(e.id) else { continue }
            t += [tj.nota?.texto, m.leyendaRIR(e.id), TextoAlumno.notaParaAlumno(tj.efectivo.ejercicio.notasTecnica, rir: tj.pauta.rir, clinica: tj.reservaClinica)]
                .compactMap { $0 }
            t += tj.filas.compactMap(\.calibracion)
            t += m.preparacion(e.id).compactMap(\.nota)
        }
        t += m.rutinaReloj().ejercicios.compactMap(\.leyendaRIR)
        return t
    }

    func dice(_ textos: [String]) -> String? {
        textos.first { prohibido.firstMatch(in: $0, range: NSRange($0.startIndex..., in: $0)) != nil }
    }

    @Test func conReservaLaPautaDelPlanEnTodosLados() async {
        let b = Banco()
        let m = await modelo(b, rutina(rir: "2-3"))
        #expect(m.reservaClinica)
        #expect(m.banner.cambian == 0 && !m.banner.calibracion && m.banner.texto == nil)
        #expect(m.tarjeta(lugar)?.nota?.texto == "Seguí la pauta de esta semana (4×8), dejando 2–3 en reserva.")
        #expect(m.tarjeta(lugar)?.nota?.cambia == false)
        #expect(m.leyendaRIR(lugar) == "Dejando 2–3 en reserva")
        #expect(m.cargaSimple(lugar)?.aumento == .noCorresponde, "nunca «toca subir»")
        #expect(m.rutinaReloj().ejercicios.first { $0.lugar == lugar }?.leyendaRIR == "Dejando 2–3 en reserva")
        let t = textos(m)
        #expect(dice(t) == nil, "apareció: \(dice(t) ?? "")")
        #expect(t.contains("Dejá 2 repeticiones en reserva y bajá controlado."), "la nota técnica de Mati entera")
        #expect(t.contains("Con RIR 3, sin apurar."), "la nota de la preparación entera")
        #expect(t.contains { $0.contains("dejando 2–3 en reserva") && $0.contains("Primera vez") }, "el aviso de primera vez con la reserva")
    }

    @Test func sinReservaTodoIgual() async {
        let b = Banco()
        let m = await modelo(b, rutina(rir: "0"))
        #expect(!m.reservaClinica)
        #expect(m.banner.cambian == 1)
        #expect(m.tarjeta(lugar)?.nota?.texto.contains("Subí la carga") == true)
        #expect(m.leyendaRIR(lugar) == "Al fallo")
        #expect(m.rutinaReloj().ejercicios.first { $0.lugar == lugar }?.leyendaRIR == "Al fallo")
        if case .sugerido(80, 82.5) = m.cargaSimple(lugar)?.aumento {} else { Issue.record("sin reserva sugiere subir: \(String(describing: m.cargaSimple(lugar)?.aumento))") }
        let t = textos(m)
        #expect(!t.contains("Dejá 2 repeticiones en reserva y bajá controlado."), "sin reserva la nota va sin RIR")
        #expect(t.contains { $0.contains("al fallo") && $0.contains("Primera vez") })
    }

    @Test func semanaUnoConReservaSinLaCalibracionAlFallo() async {
        let b = Banco()
        let m = await modelo(b, rutina(rir: "2-3", semana: 1))
        #expect(!m.banner.calibracion && m.banner.texto == nil)
        let n = m.tarjeta(lugar)?.nota
        #expect(n?.texto == "Seguí la pauta de esta semana (4×10), dejando 2–3 en reserva.")
        #expect(n?.cambia == false && n?.calibracion == true, "el rótulo «Semana 1», sin «al fallo»")
        #expect(dice(textos(m)) == nil)
        let sin = await modelo(Banco(), rutina(rir: "0", semana: 1))
        #expect(sin.banner.calibracion)
        #expect(sin.tarjeta(lugar)?.nota?.texto.hasPrefix("Semana de calibración. Llevá cada serie al fallo") == true)
    }

    @Test func laDemoQuedaComoSiempre() async {
        let m = await modelo(Banco(), rutina(rir: "2-3"), token: nil)
        #expect(m.demo)
        #expect(!m.reservaClinica)
        #expect(m.leyendaRIR(lugar) == "Al fallo")
    }

    @Test func otraRutinaSeVuelveACalcular() async {
        let b = Banco()
        let m = await modelo(b, rutina(rir: "0"))
        #expect(!m.reservaClinica)
        m.reemplazarRutina(rutina(rir: "2-3"))
        #expect(m.reservaClinica)
        #expect(m.leyendaRIR(lugar) == "Dejando 2–3 en reserva")
        m.reemplazarRutina(rutina(rir: "0", semana: 3))
        #expect(!m.reservaClinica)
    }
}
