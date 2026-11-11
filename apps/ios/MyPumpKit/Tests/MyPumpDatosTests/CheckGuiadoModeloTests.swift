import Foundation
import Testing
import MyPumpModelos
@testable import MyPumpDatos
@testable import MyPumpReglas

private let raizRepo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

/// El check guiado en el modelo: escribe exactamente lo mismo que el check de siempre (más lo marcado), apagado no llama a
/// nada nuevo, y el borrador se guarda y se retoma.
@Suite("Check guiado: modelo y cola", .serialized)
@MainActor
struct CheckGuiadoModeloTests {
    final class Servidor: @unchecked Sendable {
        var conRed = true
        var guiado = #"{"activo":true,"en_ciclo":false,"semana":"2026-11-09","catalogo":null,"senales":null}"#
        var estadoGuiado = 200
        var check = "[]"
        private let candado = NSLock()
        private var _cuerpos: [String: JSONValue] = [:]
        var cuerpos: [String: JSONValue] { candado.withLock { _cuerpos } }
        func anotar(_ fn: String, _ c: JSONValue) { candado.withLock { _cuerpos[fn] = c } }
    }

    let hoy = "2026-11-11"
    let llenas = ["energia": 4, "descanso": 3, "hambre": 2, "adherencia": 5]

    func armar(_ s: Servidor, prendido: Bool = true, disco: Disco? = nil, mandar: Bool = false) -> (ModeloRevision, Outbox, TransporteProgramado) {
        let t = TransporteProgramado { fn, cuerpo in
            guard s.conRed else { throw URLError(.notConnectedToInternet) }
            s.anotar(fn, cuerpo)
            switch fn {
            case "mypump_check_guiado_get": return (s.estadoGuiado, s.guiado)
            case "mypump_get_checkin_semana": return (200, s.check)
            case "mypump_check_guiado_guardar": return (200, "true")
            case "mypump_guardar_checkin": return (200, #"[{"semana_lunes":"2026-11-09","energia":4}]"#)
            default: return (200, "[]")
            }
        }
        let cliente = ClienteRPC(config: .produccion, transporte: t)
        let esc = Escrituras(cliente: cliente, token: "AAAAAAAAAAAAAAAAAAAA")
        let cola = Outbox(archivo: nil, reintentoAutomatico: false) { op in
            mandar ? await esc.ejecutar(op) : .respuesta(.failure(ErrorRPC(clase: .red, status: 0, mensaje: "sin red")))
        }
        let m = ModeloRevision(cliente: cliente, token: "AAAAAAAAAAAAAAAAAAAA", outbox: cola, disco: disco)
        m.guiadoPrendido = prendido
        let h = hoy
        m.diaDeHoy = { h }
        return (m, cola, t)
    }

    func discoNuevo() -> Disco { Disco(carpeta: FileManager.default.temporaryDirectory.appendingPathComponent("cg-\(UUID().uuidString)")) }

    @Test func apagadoNoLlamaANadaNuevo() async {
        let (m, _, t) = armar(Servidor(), prendido: false)
        await m.cargarRevision()
        #expect(!t.llamadas.contains("mypump_check_guiado_get"))
        #expect(m.guiado == nil)
        #expect(m.catalogoGuiado == .general)
    }

    @Test func prendidoLeeSiEstaEnCicloYLoYaMarcado() async {
        let s = Servidor()
        s.guiado = #"{"activo":true,"en_ciclo":true,"semana":"2026-11-09","catalogo":"ciclo","senales":["acne"],"glp1":true,"intensidades":{"acne":"moderado"}}"#
        s.check = #"[{"semana_lunes":"2026-11-09","energia":4,"descanso":3,"hambre":2,"adherencia":5,"nota":"bien"}]"#
        let (m, _, _) = armar(s)
        await m.cargarRevision()
        #expect(s.cuerpos["mypump_check_guiado_get"]?["p_fecha"] == .texto(hoy))
        #expect(m.catalogoGuiado == .ciclo)
        let b = m.abrirGuiado()
        #expect(b == CheckGuiado.Borrador(semana: "2026-11-09", paso: .resumen, valores: llenas, catalogo: .ciclo, senales: ["acne"],
                                          intensidades: ["acne": "moderado"], nota: "bien"))
        // Los digestivos, solo si el servidor dice que usa un GLP-1; sin el campo (o en false), no.
        #expect(m.glp1Guiado)
        s.guiado = #"{"activo":true,"en_ciclo":true,"semana":"2026-11-09","catalogo":null,"senales":null}"#
        await m.cargarRevision()
        #expect(!m.glp1Guiado)
    }

    @Test func sinLaFuncionOConLaPalancaApagadaEnElServidorEsLaListaGeneral() async {
        let s = Servidor()
        s.estadoGuiado = 404
        s.guiado = #"{"code":"PGRST202","message":"Could not find the function"}"#
        let (m, _, _) = armar(s)
        await m.cargarRevision()
        #expect(m.guiado == nil && m.catalogoGuiado == .general)
        s.estadoGuiado = 200
        s.guiado = #"{"activo":false}"#
        await m.cargarRevision()
        #expect(m.guiado == nil)
    }

    @Test func sinRedQuedaLoUltimoQueSeSupo() async {
        let s = Servidor(), disco = discoNuevo()
        s.guiado = #"{"activo":true,"en_ciclo":true,"semana":"2026-11-09","catalogo":null,"senales":null}"#
        let (a, _, _) = armar(s, disco: disco)
        await a.cargarRevision()
        s.conRed = false
        let (b, _, _) = armar(s, disco: disco)
        #expect(b.catalogoGuiado == .ciclo, "al arrancar sin señal, lo del disco")
        await b.cargarRevision()
        #expect(b.catalogoGuiado == .ciclo)
    }

    /// Lo central: lo que sale por la cola es lo del vector compartido, y `checkin` y `peso` son idénticos a los de siempre.
    @Test func enviarEscribeLoMismoQueElCheckDeSiempreMasLoMarcado() async throws {
        let v = try JSONSerialization.jsonObject(with: Data(contentsOf: raizRepo.appendingPathComponent("apps/shared/vectores/check_guiado.json"))) as! [String: Any]
        let p = v["payload"] as! [String: Any]
        let b = try JSONDecoder().decode(CheckGuiado.Borrador.self, from: JSONSerialization.data(withJSONObject: p["borrador"]!))
        #expect(p["fecha"] as? String == hoy)

        let (m, cola, _) = armar(Servidor())
        #expect(await m.enviarGuiado(b) == nil)
        let ops = await cola.operaciones
        let esperadas = p["ops"] as! [[String: Any]]
        #expect(ops.map(\.kind) == esperadas.map { $0["kind"] as! String })
        for (op, e) in zip(ops, esperadas) {
            #expect(op.dedupeKey == e["dedupeKey"] as? String)
            let esperado = try JSONDecoder().decode(JSONValue.self, from: JSONSerialization.data(withJSONObject: e["payload"]!))
            #expect(op.payload == esperado, "\(op.kind)")
        }

        // El check de siempre, con los mismos datos, encola un `checkin` y un `peso` iguales byte a byte.
        let (viejo, colaVieja, _) = armar(Servidor(), prendido: false)
        _ = await viejo.enviarCheckin(Checkin(valores: b.valores, nota: b.nota))
        await viejo.guardarPeso(b.peso)
        let viejas = await colaVieja.operaciones
        #expect(viejas.map(\.kind) == ["checkin", "peso"])
        #expect(viejas.map(\.payload) == Array(ops.prefix(2)).map(\.payload))
        #expect(viejas.map(\.dedupeKey) == Array(ops.prefix(2)).map(\.dedupeKey))

        #expect(m.checkinEnviado)
        #expect(m.borradorGuiado == nil)
        #expect(m.guiado?.senales == ["acne", "sueno"])
        #expect(m.guiado?.intensidades == ["acne": "leve", "sueno": "moderado"])
    }

    /// Un efecto marcado sin su intensidad no sale: ni el check de siempre ni lo marcado.
    @Test func sinIntensidadNoSaleNada() async {
        let (m, cola, _) = armar(Servidor())
        let b = CheckGuiado.Borrador(semana: "2026-11-09", valores: llenas, catalogo: .ciclo, senales: ["acne", "nauseas"], intensidades: ["acne": "leve"])
        #expect(await m.enviarGuiado(b) == CheckGuiado.avisoIntensidad)
        #expect(await cola.operaciones.isEmpty)
    }

    @Test func laColaLlamaALaFuncionConLosParametrosDelContrato() async {
        let s = Servidor()
        let (m, cola, t) = armar(s, mandar: true)
        _ = await m.enviarGuiado(.init(semana: "2026-11-09", valores: llenas, catalogo: .general, senales: ["ninguno"]))
        for _ in 0..<3 { await cola.drenar() }
        #expect(t.llamadas.contains("mypump_guardar_checkin"))
        let c = s.cuerpos["mypump_check_guiado_guardar"]
        #expect(c?["p_fecha"] == .texto(hoy))
        #expect(c?["p_respuestas"] == .objeto(["catalogo": .texto("general"), "senales": .lista([.texto("ninguno")]), "intensidades": .objeto([:])]))
        #expect(c?["p_token"] == .texto("AAAAAAAAAAAAAAAAAAAA"))
        #expect(await cola.operaciones.isEmpty)
        // El check de siempre no lleva ni un parámetro más.
        if case .objeto(let o)? = s.cuerpos["mypump_guardar_checkin"] {
            #expect(Set(o.keys) == ["p_token", "p_fecha", "p_energia", "p_descanso", "p_hambre", "p_adherencia", "p_nota"])
        } else { Issue.record("sin cuerpo") }
    }

    @Test func sinLaFuncionEnLaBaseLaOpNoQuedaTrabada() async {
        let t = TransporteProgramado { fn, _ in
            fn == "mypump_check_guiado_guardar" ? (404, #"{"code":"PGRST202","message":"Could not find the function"}"#) : (200, "[]")
        }
        let esc = Escrituras(cliente: ClienteRPC(config: .produccion, transporte: t), token: "AAAAAAAAAAAAAAAAAAAA")
        let cola = Outbox(archivo: nil, reintentoAutomatico: false) { op in await esc.ejecutar(op) }
        await cola.encolar("check_guiado", .objeto(["fecha": .texto(hoy), "respuestas": .objeto(["catalogo": .texto("general"), "senales": .lista([.texto("dolor")])])]),
                           dedupeKey: "check_guiado_\(hoy)")
        await cola.drenar()
        #expect(await cola.operaciones.isEmpty)
    }

    @Test func sinLoObligatorioNoSaleNada() async {
        let (m, cola, _) = armar(Servidor())
        #expect(await m.enviarGuiado(.init(semana: "2026-11-09", valores: ["energia": 4])) == "Faltan: Descanso, Hambre, Adherencia")
        #expect(await m.enviarGuiado(.init(semana: "2026-11-09", valores: llenas)) == "Falta: ¿Algo de esto esta semana?")
        #expect(await m.enviarGuiado(.init(semana: "2026-11-09", peso: "12", valores: llenas, senales: ["ninguno"])) == PesoCorporal.avisoRango)
        #expect(await cola.operaciones.isEmpty)
        #expect(!m.checkinEnviado)
    }

    @Test func sinPesoNoSeMandaPeso() async {
        let (m, cola, _) = armar(Servidor())
        #expect(await m.enviarGuiado(.init(semana: "2026-11-09", valores: llenas, senales: ["dolor"])) == nil)
        #expect(await cola.operaciones.map(\.kind) == ["checkin", "check_guiado"])
    }

    @Test func elPesoDelPasoSeGuardaEnElMomentoYNoSeRepite() async {
        let (m, cola, _) = armar(Servidor())
        #expect(await m.guardarPesoGuiado("abc") == false)
        #expect(await m.guardarPesoGuiado("78,4"))
        #expect(await cola.operaciones.map(\.kind) == ["peso"])
        let primera = await cola.operaciones.first?.id
        #expect(await m.guardarPesoGuiado("78.4"))
        #expect(await cola.operaciones.first?.id == primera, "el mismo peso no se encola de nuevo")
        #expect(await m.enviarGuiado(.init(semana: "2026-11-09", peso: "78,4", valores: llenas, senales: ["ninguno"])) == nil)
        #expect(await cola.operaciones.map(\.kind) == ["peso", "checkin", "check_guiado"])
    }

    @Test func elBorradorSeGuardaSeRetomaYElDeOtraSemanaSeDescarta() async {
        let s = Servidor(), disco = discoNuevo()
        let (a, _, _) = armar(s, disco: disco)
        var b = a.abrirGuiado()
        #expect(b == CheckGuiado.Borrador(semana: "2026-11-09"))
        b.peso = "78,4"; b.valores = llenas; b.paso = .senales
        a.guardarBorrador(b)

        // Se cierra la app: al volver está donde quedó.
        let (c, _, _) = armar(s, disco: disco)
        #expect(c.borradorGuiado == b)
        // El peso del borrador no está cargado hoy (quedó de otro día o sin confirmar): no vuelve, para no mandarlo con la fecha de hoy.
        var sinPeso = b; sinPeso.peso = ""
        #expect(c.abrirGuiado() == sinPeso)
        #expect(CheckGuiado.estado(enviado: c.checkinEnviado, borrador: c.borradorGuiado, semana: c.semana, faltanFotos: true) == .aMedias)

        // Semana nueva: el borrador de la anterior no es de esta.
        let (d, _, _) = armar(s, disco: disco)
        d.diaDeHoy = { "2026-11-16" }
        await d.cargarRevision()
        #expect(d.borradorGuiado == nil)
        #expect(d.abrirGuiado() == CheckGuiado.Borrador(semana: "2026-11-16"))
        let (e, _, _) = armar(s, disco: disco)
        #expect(e.borradorGuiado == nil, "también se borró del disco")
    }

    @Test func loMarcadoQueNoSalioGanaSobreElServidor() async {
        let s = Servidor()
        let (m, _, _) = armar(s)
        _ = await m.enviarGuiado(.init(semana: "2026-11-09", valores: llenas, catalogo: .general, senales: ["dolor"]))
        await m.cargarRevision()   // el servidor todavía no lo tiene
        #expect(m.guiado?.senales == ["dolor"])
        #expect(m.checkinEnviado)
        #expect(m.abrirGuiado().senales == ["dolor"])
    }

    @Test func laPalancaSeLeeYSinLaClaveEstaApagada() {
        #expect(PalancaRemota(.objeto([:])).checkGuiado == false)
        #expect(PalancaRemota(.objeto(["check_guiado": .bool(true)])).checkGuiado)
        #expect(PalancaRemota(.objeto(["check_guiado": .texto("true")])).checkGuiado == false)
        #expect(PalancaRemota.deFabrica.checkGuiado == false)
    }
}
