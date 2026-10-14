import Foundation
import Testing
import MyPumpModelos
@testable import MyPumpReglas

// Lo que muestran las cards, contra las funciones de cliente.html (salud_vista.json) y, lo que vive adentro de un render,
// contra la web leída a mano.

private struct ArchivoVista: Decodable {
    struct Caso: Decodable {
        struct Valores: Decodable {
            struct PorTipo: Decodable {
                struct Punto: Decodable { let fecha: String; let valor: Double; let detalle: JSONValue? }
                let serie: [Punto]
                let valores: [Double?]
            }
            struct Reciente: Decodable { let dias: Int; let nocturnos: Bool; let diurnos: Bool }
            let salud: [JSONValue]
            let fechas: [String]
            let porTipo: [String: PorTipo]
            let hoy: String
            let recientes: [Reciente]
        }
        struct Motivos: Decodable {
            struct Salida: Decodable { let flecha: String; let antes: String; let negrita: String; let despues: String }
            let motivos: JSONValue?
            let salida: [Salida]
        }
        struct Circular: Decodable { let vals: [Double]; let m: Double; let sd: Double; let dormirse: String; let sdRedondo: Int }
        struct Reloj: Decodable { let x: Double; let hhmm: String }
        let valores: [Valores]
        let motivos: [Motivos]
        let circular: [Circular]
        let relojes: [Reloj]
    }
    let casos: [Caso]
}

private func filas(_ js: [JSONValue]) throws -> [FilaSalud] {
    try JSONDecoder().decode([FilaSalud].self, from: JSONEncoder().encode(js))
}

private func fila(_ fecha: String, _ tipo: String, _ valor: Double?, _ fuente: String = "apple_health", detalle: JSONValue? = nil) -> FilaSalud {
    var o: [String: JSONValue] = ["fecha": .texto(fecha), "tipo": .texto(tipo), "valor": valor.map(JSONValue.numero) ?? .null, "fuente": .texto(fuente)]
    if let detalle { o["detalle"] = detalle }
    return try! JSONDecoder().decode(FilaSalud.self, from: JSONEncoder().encode(JSONValue.objeto(o)))
}

@Suite("Salud: las cards como la web")
struct SaludVistaTests {
    private func vectores() throws -> ArchivoVista.Caso {
        try JSONDecoder().decode(ArchivoVista.self, from: Data(contentsOf: raizRepo.appendingPathComponent("apps/shared/vectores/salud_vista.json"))).casos[0]
    }

    @Test func valorYSerieComoLaWeb() throws {
        let v = try vectores()
        var fallas: [String] = []
        var total = 0
        for (n, esc) in v.valores.enumerated() {
            let s = try filas(esc.salud)
            for (tipo, esperado) in esc.porTipo {
                for (f, e) in zip(esc.fechas, esperado.valores) {
                    total += 1
                    let swift = SaludVista.valor(s, tipo: tipo, fecha: f)
                    if swift != e { fallas.append("#\(n) valor \(tipo) \(f): web \(String(describing: e)), swift \(String(describing: swift))") }
                }
                let serie = SaludVista.serie(s, tipo: tipo)
                total += 1
                if serie.map(\.fecha) != esperado.serie.map(\.fecha) || serie.map(\.valor) != esperado.serie.map(\.valor)
                    || serie.map(\.detalle) != esperado.serie.map(\.detalle) {
                    fallas.append("#\(n) serie \(tipo)")
                }
            }
            for r in esc.recientes {
                total += 2
                if SaludVista.tieneReciente(s, tipos: ["fc_reposo", "hrv_ms", "sueno_min"], dias: r.dias, hoy: esc.hoy) != r.nocturnos { fallas.append("#\(n) noche \(r.dias)") }
                if SaludVista.tieneReciente(s, tipos: ["pasos", "actividad_min", "kcal_activas"], dias: r.dias, hoy: esc.hoy) != r.diurnos { fallas.append("#\(n) día \(r.dias)") }
            }
        }
        #expect(total > 3000)
        #expect(fallas.isEmpty, "\(fallas.count) de \(total): \(fallas.prefix(5))")
    }

    @Test func motivosComoLaWeb() throws {
        let v = try vectores()
        var fallas: [String] = []
        for (n, c) in v.motivos.enumerated() {
            let ms = SaludVista.motivos(RecuperacionDia(fecha: "2026-10-14", motivos: c.motivos))
            let swift = ms.map { "\($0.sube ? "↑" : "↓")|\($0.antes)|\($0.negrita)|\($0.despues)" }
            let web = c.salida.map { "\($0.flecha)|\($0.antes)|\($0.negrita)|\($0.despues)" }
            if swift != web { fallas.append("#\(n): web \(web), swift \(swift)") }
        }
        #expect(v.motivos.count >= 100)
        #expect(fallas.isEmpty, "\(fallas.prefix(3))")
    }

    /// Valores raros en los motivos, con lo que da `_recDrivers` en node (hallazgo del gemelo de Android, 3091e8e):
    /// `Number(null)` es 0, un ausente es NaN y `m.baseline ?` usa la verdad de JS (un "0" de texto cuenta).
    @Test func motivosConValoresRaros() {
        func texto(_ m: [String: JSONValue]) -> String? {
            SaludVista.motivos(RecuperacionDia(fecha: "2026-10-14", motivos: .lista([.objeto(m)]))).first?.texto
        }
        #expect(texto(["tipo": .texto("sueno"), "valor": .null]) == "Dormiste 0h00")
        #expect(texto(["tipo": .texto("sueno")]) == "Dormiste NaNhNaN")
        #expect(texto(["tipo": .texto("sueno"), "valor": .texto("450"), "baseline": .texto("0")]) == "Dormiste 7h30 · venís de 0h00")
        #expect(texto(["tipo": .texto("sueno"), "valor": .numero(450), "baseline": .numero(0)]) == "Dormiste 7h30")
        #expect(texto(["tipo": .texto("fc_reposo"), "valor": .numero(50), "baseline": .texto("0")]) == "Pulso en reposo 50 · 50 más que tu normal")
        #expect(texto(["tipo": .texto("hrv"), "valor": .null, "baseline": .null]) == "Variabilidad 0 ms")
    }

    /// Hallazgo 1 del gemelo de Android: `Int()` sobre `dias_datos / 14 * 100` cerraba la app con un número absurdo.
    @Test func calibrandoConDiasAbsurdos() {
        let hoy = "2026-10-14"
        for n in [Int.max, Int.min, 7] {
            let card = SaludVista.cardRecuperacion(serie: [RecuperacionDia(fecha: hoy, estado: "calibrando", diasDatos: n)], conectado: true,
                                                   mostrar: true, salud: [], historial: nil, sinDatos: false, hoy: hoy)
            if case .calibrando(let dias, let pct, _) = card { #expect(dias == n && pct <= 100) } else { Issue.record("\(card)") }
        }
    }

    @Test func milesComoToLocaleString() {
        #expect(SaludVista.miles(.infinity) == "∞" && SaludVista.miles(-.infinity) == "-∞" && SaludVista.miles(.nan) == "NaN")
        #expect(SaludVista.miles(-0.4) == "-0" && SaludVista.miles(-0.5) == "-0" && SaludVista.miles(0.5) == "1")
        #expect(SaludVista.miles(1e23) == "100.000.000.000.000.000.000.000")
        #expect(SaludVista.miles(1e21) == "1.000.000.000.000.000.000.000")
        #expect(SaludVista.miles(123456789012345680000) == "123.456.789.012.345.680.000")
        #expect(SaludVista.miles(-1234.5) == "-1.234" && SaludVista.miles(8548.4) == "8.548")
    }

    @Test func regularidadComoLaWeb() throws {
        let v = try vectores()
        for c in v.circular {
            let (m, sd) = SaludVista.promedioCircular(c.vals)
            // Seno y coseno de V8 y de Darwin pueden diferir en el último bit: lo que se muestra tiene que ser igual.
            #expect(abs(m - c.m) < 1e-9 && abs(sd - c.sd) < 1e-9)
            #expect(SaludVista.horaReloj(m - 210) == c.dormirse)
            #expect(Int(jsRound(sd)) == c.sdRedondo)
        }
        for r in v.relojes { #expect(SaludVista.horaReloj(r.x) == r.hhmm, "\(r.x)") }
    }

    // MARK: - Card de Recuperación (renderMydayRecuperacion, a mano)

    private let hoy = "2026-10-14"

    @Test func sinScoreYSinConectarOfreceConectar() {
        let serie = [RecuperacionDia(fecha: hoy, estado: "insuficiente")]
        #expect(SaludVista.cardRecuperacion(serie: serie, conectado: false, mostrar: true, salud: [], historial: nil, sinDatos: false, hoy: hoy) == .sinConectar)
        #expect(SaludVista.cardRecuperacion(serie: [], conectado: false, mostrar: true, salud: [], historial: nil, sinDatos: false, hoy: hoy) == .sinConectar)
    }

    @Test func conectadoSinScoreExplicaQueFalta() {
        let serie = [RecuperacionDia(fecha: hoy, estado: "insuficiente")]
        func caso(_ salud: [FilaSalud], historial: (Int, Int)? = nil, sinDatos: Bool = false) -> SaludVista.CardRecuperacion {
            SaludVista.cardRecuperacion(serie: serie, conectado: true, mostrar: true, salud: salud, historial: historial.map { ($0.0, $0.1) },
                                        sinDatos: sinDatos, hoy: hoy)
        }
        #expect(caso([], historial: (25, 60)) == .conectadoSinScore(.trayendoHistorial(hecho: 25, total: 60)))
        // Tuvo datos de la noche hace 10 días y ya no: va ANTES que "solo pasos" (tiene reloj, se le cortó).
        #expect(caso([fila("2026-10-04", "hrv_ms", 50), fila(hoy, "pasos", 8000)]) == .conectadoSinScore(.faltanDatosDeLaNoche))
        #expect(caso([fila("2026-10-12", "pasos", 8000)]) == .conectadoSinScore(.soloPasos))
        #expect(caso([], sinDatos: true) == .conectadoSinScore(.noLlegaNada))
        #expect(caso([]) == .conectadoSinScore(.esperando))
        // Un valor nulo no cuenta como dato.
        #expect(caso([fila("2026-10-13", "pasos", nil)]) == .conectadoSinScore(.esperando))
    }

    @Test func calibrandoMuestraLoQueYaSabe() {
        let c1 = SaludVista.cardRecuperacion(serie: [RecuperacionDia(fecha: hoy, estado: "calibrando", diasDatos: 5, cobertura: .objeto(["sueno_min": .numero(452)]))],
                                             conectado: true, mostrar: true, salud: [], historial: nil, sinDatos: false, hoy: hoy)
        #expect(c1 == .calibrando(dias: 5, porcentaje: 36, yaSe: "Ya sé que dormís cerca de 7h32."))
        let c2 = SaludVista.cardRecuperacion(serie: [RecuperacionDia(fecha: hoy, estado: "calibrando", diasDatos: 20, cobertura: .objeto(["fc_reposo": .numero(51.5)]))],
                                             conectado: true, mostrar: true, salud: [], historial: nil, sinDatos: false, hoy: hoy)
        #expect(c2 == .calibrando(dias: 20, porcentaje: 100, yaSe: "Ya sé que tu pulso en reposo ronda los 52."))
    }

    @Test func conScoreFraseMotivosYScoreViejo() {
        let motivos: JSONValue = .lista([.objeto(["tipo": .texto("sueno"), "dir": .numero(-1), "valor": .numero(372), "baseline": .numero(455)])])
        var serie = (1...11).map { RecuperacionDia(fecha: "2026-10-0\(min($0, 9))", score: 60 + $0, estado: "ok", banda: "media") }
        serie.append(RecuperacionDia(fecha: "2026-10-12", score: 81, estado: "ok", banda: "alta", motivos: motivos))
        serie.append(RecuperacionDia(fecha: "2026-10-13", estado: "insuficiente"))
        serie.append(RecuperacionDia(fecha: hoy, estado: "insuficiente"))
        guard case .conScore(let c) = SaludVista.cardRecuperacion(serie: serie, conectado: true, mostrar: true, salud: [], historial: nil, sinDatos: false, hoy: hoy)
        else { Issue.record("esperaba score"); return }
        #expect(c.fila.score == 81 && c.banda == "alta" && c.bandaTexto == "Recuperado")
        #expect(c.motivos.map(\.texto) == ["Dormiste 6h12 · venís de 7h35"])
        #expect(c.frase == nil)   // con motivos no hay frase genérica
        #expect(c.notaVieja == "Score de lunes: la de anoche todavía no llegó.")
        #expect(c.grafico.count == 12)
        // Apagado por el cliente: no hay número.
        #expect(SaludVista.cardRecuperacion(serie: serie, conectado: true, mostrar: false, salud: [], historial: nil, sinDatos: false, hoy: hoy) == .oculto)
        // Sin motivos, la frase sale de la banda; discordancia y estado autonómico ganan.
        let baja = [RecuperacionDia(fecha: hoy, score: 30, estado: "ok", banda: "baja")]
        if case .conScore(let b) = SaludVista.cardRecuperacion(serie: baja, conectado: true, mostrar: true, salud: [], historial: nil, sinDatos: false, hoy: hoy) {
            #expect(b.frase == "Hoy tu cuerpo pide más descanso." && b.notaVieja == nil && b.grafico.isEmpty)
        } else { Issue.record("esperaba score") }
        let fat = [RecuperacionDia(fecha: hoy, score: 40, estado: "ok", banda: "baja", estadoAutonomico: "fatiga_acumulada", discordancia: true)]
        if case .conScore(let f) = SaludVista.cardRecuperacion(serie: fat, conectado: true, mostrar: true, salud: [], historial: nil, sinDatos: false, hoy: hoy) {
            #expect(f.frase == "Los números dicen una cosa y vos me dijiste otra. Le creo a lo que sentís.")
        } else { Issue.record("esperaba score") }
    }

    // MARK: - Card Salud y Mis datos

    @Test func resumenDeLaCardSalud() {
        let salud = [
            fila(hoy, "pasos", 8548.161), fila(hoy, "pasos", 9000, "manual"), fila("2026-10-13", "pasos", 6000),
            fila("2026-10-13", "sueno_min", 452, "oura"), fila("2026-10-13", "sueno_min", 430),
            fila("2026-10-13", "hrv_ms", 40, detalle: .objeto(["metrica": .texto("sdnn")])),
            fila("2026-10-13", "hrv_ms", 55, "whoop", detalle: .objeto(["metrica": .texto("rmssd")])),
            fila(hoy, "actividad_min", 32),
        ]
        let r = SaludVista.resumen(salud, hoy: hoy)
        #expect(r?.pasosHoy == 8548.161)          // apple_health le gana a lo manual
        #expect(r?.suenoAnoche == 452)            // no hay de hoy: el de ayer, y Oura gana
        #expect(r?.hrv == 55)                     // el rMSSD gana
        #expect(r?.minutosActivosHoy == 32)
        #expect(r?.diasPromedio == 2 && r?.promedioPasos == 7274)
        #expect(SaludVista.resumen([fila(hoy, "sueno_min", 400)], hoy: hoy) == nil)
        #expect(SaludVista.miles(8548.161) == "8.548" && SaludVista.miles(1234567) == "1.234.567" && SaludVista.miles(999) == "999")
        #expect(SaludVista.horas(452) == "7h 32" && SaludVista.horasSinEspacio(59.6) == "0h60")
    }

    @Test func componentesSeRepartenEntreLosPresentes() {
        let comp: JSONValue = .objeto([
            "autonomico": .objeto(["score": .numero(72.4), "peso": .numero(45)]),
            "sueno": .objeto(["score": .numero(50), "peso": .numero(25)]),
            "carga": .objeto(["score": .null, "peso": .numero(20)]),
        ])
        let c = SaludVista.componentes(RecuperacionDia(fecha: hoy, score: 66, componentes: comp))
        #expect(c.map(\.clave) == ["autonomico", "sueno"])
        #expect(c.map(\.score) == [72, 50])
        #expect(c.map(\.aporte) == [64, 36])
        #expect(SaludVista.componentes(RecuperacionDia(fecha: hoy, estado: "calibrando", componentes: comp)).isEmpty)
    }

    @Test func filaDeMetricaConPromediosYFlecha() {
        var salud = (1...9).map { fila("2026-10-0\($0)", "fc_reposo", 50) }
        salud.append(fila("2026-10-10", "fc_reposo", 56))
        let f = SaludVista.fila(salud, tipo: "fc_reposo", mejorSube: false)
        #expect(f?.valor == "56")
        #expect(f?.delta == "↑ 5" && f?.deltaEsBueno == false)   // promedio 50,6: subir el pulso no es bueno
        #expect(f?.promedio7 == "51" && f?.promedio30 == "51" && f?.diasConDato == 10)
        #expect(SaludVista.fila(salud, tipo: "pasos") == nil)
        #expect(SaludVista.rotuloNoche(hoy, hoy: hoy) == "Anoche")
        #expect(SaludVista.rotuloNoche("2026-10-13", hoy: hoy) == "Anteanoche")
        #expect(SaludVista.rotuloNoche("2026-09-12", hoy: hoy) == "Noche del 12 sept")
    }

    // MARK: - Fechas locales como JS

    @Test func medianochesYMediodiaComoJS() {
        // Nueva York, la semana del cambio de hora (1-nov-2026): 7 días atrás desde el 4-nov a las 8:45.
        let ny = RelojLocal(zona: TimeZone(identifier: "America/New_York")!)
        let ahora = 1_793_799_917_345.0   // 2026-11-04T08:45:17.345-05:00
        #expect(RelojLocal.iso(ny.medianoche(haceDias: 7, desde: ahora)) == "2026-10-28T04:00:00.000Z")   // todavía EDT
        #expect(RelojLocal.iso(ny.medianoche(haceDias: 0, desde: ahora)) == "2026-11-04T05:00:00.000Z")
        #expect(RelojLocal.iso(ny.mediodiaDelDiaAnterior(ny.medianoche(haceDias: 7, desde: ahora))) == "2026-10-27T16:00:00.000Z")
        #expect(ny.ymd(ahora) == "2026-11-04")
        #expect(RelojLocal.iso(1_792_032_617_345) == "2026-10-15T02:50:17.345Z")
        #expect(RelojLocal.desdeISO("2026-10-14 13:59:00.123456+00:00") == 1_791_986_340_123)
        #expect(RelojLocal.desdeISO("2026-10-14T13:59:00Z") == 1_791_986_340_000)
    }
}
