import Foundation
import Testing
import MyPumpModelos
import MyPumpReglas
@testable import MyPumpDatos

/// Cargar días anteriores y copiar a hoy: lo de hoy no se toca, cada fecha va por su clave, sin leer no se escribe, la ventana
/// de «Comí» es la real de la base, y copiar nunca pisa lo cargado hoy sin que el cliente lo haya pedido.
@Suite("Dieta: días anteriores y copiar a hoy", .serialized)
@MainActor
struct DiaPasadoDietaTests {
    let raiz = FileManager.default.temporaryDirectory.appendingPathComponent("dia-pasado-\(UUID().uuidString)")
    static let token = "AAAAAAAAAAAAAAAAAAAA"
    static let dietaId = "55555555-5555-4555-8555-555555555555"
    static let dieta = #"[{"id":"55555555-5555-4555-8555-555555555555","version":1,"estructura":{"macros_target":{"kcal":2000,"prot":150,"carb":200,"fat":60},"comidas":["#
        + #"{"id":"desayuno","name":"Desayuno","options":[{"name":"A","foods":[{"name":"Avena","qty":100,"unit":"g","kcal":380,"prot":13,"carb":60,"fat":7},{"name":"Leche","qty":200,"unit":"ml","kcal":100,"prot":7,"carb":10,"fat":3}]},{"name":"B","foods":[{"name":"Tostada","qty":50,"unit":"g","kcal":120,"prot":10,"carb":20,"fat":1}]}]},"#
        + #"{"id":"almuerzo","name":"Almuerzo","options":[{"name":"A","foods":[{"name":"Pollo","qty":200,"unit":"g","kcal":330,"prot":62,"carb":0,"fat":7}]}]}"#
        + "]}}]"

    final class Servidor: @unchecked Sendable {
        private let lock = NSLock()
        private var _marcas: [String: [[String: JSONValue]]] = [:]
        private var _libres: [String: [[String: JSONValue]]] = [:]
        private var _ajustes: [String: JSONValue] = [:]
        private var _escrituras: [(String, JSONValue)] = []
        private var seq = 0
        var sinRed = false
        var config = "{}"
        var escrituras: [(String, JSONValue)] { lock.withLock { _escrituras } }
        func nombres(_ fn: String) -> [JSONValue] { escrituras.filter { $0.0 == fn }.map(\.1) }
        func ponerMarca(_ f: String, _ id: String, _ op: String, _ e: String) {
            lock.withLock { _marcas[f, default: []].append(["comida_id": .texto(id), "fecha": .texto(f), "opcion_elegida": .texto(op), "estado": .texto(e), "foods_excluidos": .null]) }
        }
        func ponerLibre(_ f: String, _ d: String, _ k: Double) {
            lock.withLock { seq += 1; _libres[f, default: []].append(["id": .texto("L\(seq)"), "fecha": .texto(f), "hora": .texto("21:30:00"), "descripcion": .texto(d), "kcal": .numero(k), "prot": .numero(1), "carb": .numero(1), "fat": .numero(1)]) }
        }
        func ponerAjustes(_ f: String, _ a: JSONValue, dieta: String = "55555555-5555-4555-8555-555555555555") {
            lock.withLock { _ajustes[f] = .objeto(["fecha": .texto(f), "dieta_id": .texto(dieta), "tipo_dia": .null, "ajustes": a]) }
        }
        private func js(_ v: JSONValue) -> String { String(data: try! JSONEncoder().encode(v), encoding: .utf8)! }
        func leer(_ fn: String, _ c: JSONValue) -> String {
            lock.withLock {
                switch fn {
                case "mypump_get_comidas_marcadas": return js(.lista((_marcas[c["p_fecha"]?.comoTexto ?? ""] ?? []).map(JSONValue.objeto)))
                case "mypump_get_comidas_libres": return js(.lista((_libres[c["p_fecha"]?.comoTexto ?? ""] ?? []).map(JSONValue.objeto)))
                case "mypump_get_ajustes_dieta": return js(.lista(_ajustes[c["p_desde"]?.comoTexto ?? ""].map { [$0] } ?? []))
                default: return "[]"
                }
            }
        }
        func escribir(_ fn: String, _ c: JSONValue) -> String {
            lock.withLock {
                _escrituras.append((fn, c))
                let f = c["p_fecha"]?.comoTexto ?? ""
                switch fn {
                case "mypump_marcar_comida":
                    var filas = _marcas[f] ?? []
                    filas.removeAll { $0["comida_id"] == c["p_comida_id"] }
                    let fila: [String: JSONValue] = ["comida_id": c["p_comida_id"] ?? .null, "fecha": .texto(f), "opcion_elegida": c["p_opcion"] ?? .null, "estado": c["p_estado"] ?? .null, "foods_excluidos": c["p_foods_excluidos"] ?? .null]
                    filas.append(fila)
                    _marcas[f] = filas
                    return js(.lista([.objeto(fila)]))
                case "mypump_desmarcar_comida":
                    _marcas[f]?.removeAll { $0["comida_id"] == c["p_comida_id"] }
                    return "true"
                case "mypump_crear_comida_libre":
                    seq += 1
                    let fila: [String: JSONValue] = ["id": .texto("N\(seq)"), "fecha": .texto(f), "hora": c["p_hora"] ?? .null, "descripcion": c["p_descripcion"] ?? .null, "kcal": c["p_kcal"] ?? .null, "prot": c["p_prot"] ?? .null, "carb": c["p_carb"] ?? .null, "fat": c["p_fat"] ?? .null]
                    _libres[f, default: []].append(fila)
                    return js(.lista([.objeto(fila)]))
                case "mypump_guardar_ajustes_dieta":
                    _ajustes[f] = .objeto(["fecha": .texto(f), "dieta_id": c["p_dieta_id"] ?? .null, "tipo_dia": c["p_tipo_dia"] ?? .null, "ajustes": c["p_ajustes"] ?? .objeto([:])])
                    return "true"
                default: return "true"
                }
            }
        }
    }

    func modelo(_ s: Servidor) -> ModeloApp {
        let dieta = Self.dieta
        let t = TransporteProgramado { fn, cuerpo in
            if s.sinRed { throw URLError(.notConnectedToInternet) }
            switch fn {
            case "mypump_get_cliente_info": return (200, #"[{"cliente_id":"c1","nombre":"Cliente","perfil":"natural"}]"#)
            case "mypump_get_dieta_activa": return (200, dieta)
            case "mypump_get_app_config": return (200, s.config)
            case "mypump_marcar_comida", "mypump_desmarcar_comida", "mypump_crear_comida_libre", "mypump_guardar_ajustes_dieta":
                return (200, s.escribir(fn, cuerpo))
            case "mypump_get_comidas_marcadas", "mypump_get_comidas_libres", "mypump_get_ajustes_dieta":
                return (200, s.leer(fn, cuerpo))
            default: return (200, "[]")
            }
        }
        return ModeloApp(cliente: ClienteRPC(config: .produccion, transporte: t), almacen: TokenEnMemoria(Self.token), raizDisco: raiz)
    }

    var hoy: String { FechaLocal.hoy() }
    func hace(_ n: Int) -> String { DiasDieta.sumar(hoy, dias: -n)! }
    func datosLibre(_ d: String = "Cena afuera") -> ComidaLibreNueva.Datos { .init(hora: "21:00", descripcion: d, kcal: 700, prot: 30, carb: 60, fat: 30, detalle: nil) }

    @Test func abreEnHoyYVuelve() async {
        let s = Servidor(); let m = modelo(s); await m.cargar()
        #expect(!m.enDiaPasado && m.fechaVista == hoy && m.fechasDieta.count == 8)
        await m.irADia(hace(1))
        #expect(m.enDiaPasado && m.fechaVista == hace(1) && m.vistaEditable)
        await m.irADia(nil)
        #expect(!m.enDiaPasado && m.fechaVista == hoy)
        // Un día que no está en la ventana no se abre.
        await m.irADia(hace(30))
        #expect(!m.enDiaPasado)
    }

    @Test func marcarAyerNoTocaHoyYVaConSuFecha() async {
        let s = Servidor(); let m = modelo(s); await m.cargar()
        await m.marcar("desayuno", .comido, opcion: 0)
        await m.irADia(hace(1))
        #expect(m.marcasVista.isEmpty)
        await m.marcar("desayuno", .saltado, opcion: 0)
        #expect(m.marcasVista["desayuno"]?.estado == .saltado)
        #expect(m.marcasDeHoy["desayuno"]?.estado == .comido)
        // Los dos en la cola al mismo tiempo: la clave lleva la fecha, no se pisan.
        let clavePasada = ModeloApp.claveMarca(hace(1), "desayuno")
        let claveHoy = ModeloApp.claveMarca(hoy, "desayuno")
        let pend = await m.outbox?.pendientesPorClave()
        #expect(claveHoy != clavePasada && (pend?[clavePasada] != nil || s.nombres("mypump_marcar_comida").count >= 1))
        await m.outbox?.drenar()
        let fechas = Set(s.nombres("mypump_marcar_comida").compactMap { $0["p_fecha"]?.comoTexto })
        #expect(fechas == [hoy, hace(1)])
        await m.irADia(nil)
        #expect(m.marcasVista["desayuno"]?.estado == .comido)
    }

    @Test func ajustarAyerNoTocaLaFilaDeHoy() async {
        let s = Servidor(); let m = modelo(s); await m.cargar()
        await m.irADia(hace(1))
        await m.ajustar("almuerzo", AjusteComida(deltaKcal: 100), opciones: [:])
        #expect(m.ajustesVista["almuerzo"]?.deltaKcal == 100 && m.ajustesDeHoy.isEmpty)
        await m.outbox?.drenar()
        let w = s.nombres("mypump_guardar_ajustes_dieta")
        #expect(w.count == 1 && w[0]["p_fecha"]?.comoTexto == hace(1) && w[0]["p_dieta_id"]?.comoTexto == Self.dietaId)
        await m.irADia(nil)
        #expect(m.ajustesVista.isEmpty)
    }

    @Test func alimentoAgregadoAyerYDescuentoDeAyer() async {
        let s = Servidor(); let m = modelo(s); await m.cargar()
        await m.irADia(hace(1))
        await m.marcar("almuerzo", .comido, opcion: 0)
        #expect(m.consumo(opciones: [:]).kcal == 330)
        await m.alternarAlimento("almuerzo", 0)
        #expect(m.consumo(opciones: [:]).kcal == 0)
        await m.irADia(nil)
        #expect(m.consumo(opciones: [:]).kcal == 0 && m.marcasDeHoy.isEmpty)
    }

    @Test func libreCaeEnElDiaQueSeMira() async {
        let s = Servidor(); let m = modelo(s); await m.cargar()
        await m.irADia(hace(3))
        guard case .success = await m.crearComidaLibre(datosLibre()) else { Issue.record("no se creó"); return }
        #expect(m.libresVista.count == 1 && m.comidasLibres.isEmpty)
        #expect(s.nombres("mypump_crear_comida_libre")[0]["p_fecha"]?.comoTexto == hace(3))
        let id = m.libresVista[0].id
        #expect(await m.borrarComidaLibre(id))
        #expect(m.libresVista.isEmpty)
    }

    @Test func loPendienteDeEseDiaGanaALoDelServidor() async {
        let s = Servidor(); let m = modelo(s); await m.cargar()
        await m.irADia(hace(1))
        s.sinRed = true   // si la marca llegara al servidor ya no sería «lo pendiente» y esto dependería de cuándo sale la cola
        await m.marcar("desayuno", .comido, opcion: 1)
        await m.irADia(nil)
        s.ponerMarca(hace(1), "desayuno", "A", "saltado")   // algo viejo o de otro lado
        s.sinRed = false
        await m.irADia(hace(1))
        #expect(m.marcasVista["desayuno"]?.opcion == "B" && m.marcasVista["desayuno"]?.estado == .comido)
    }

    @Test func sinRedNoSeAbreNiSeEscribe() async {
        let s = Servidor(); let m = modelo(s); await m.cargar()
        s.sinRed = true
        await m.irADia(hace(1))
        #expect(m.diaPasado?.sinRed == true && !m.vistaEditable)
        await m.marcar("desayuno", .comido, opcion: 0)
        await m.ajustar("almuerzo", AjusteComida(deltaKcal: 100), opciones: [:])
        #expect(m.marcasVista.isEmpty && m.ajustesVista.isEmpty)
        #expect(await m.outbox?.pendientes == 0)
    }

    @Test func otroPlanEnEseDiaSoloDejaComidasLibres() async {
        let s = Servidor()
        s.ponerAjustes(hace(2), .objeto(["almuerzo": .objeto(["deltaKcal": .numero(50)])]), dieta: "99999999-9999-4999-8999-999999999999")
        let m = modelo(s); await m.cargar()
        await m.irADia(hace(2))
        #expect(m.diaPasado?.otroPlan == true && !m.vistaEditable && m.vistaAdmiteLibres && m.ajustesVista.isEmpty)
        await m.ajustar("almuerzo", AjusteComida(deltaKcal: 100), opciones: [:])
        await m.outbox?.drenar()
        #expect(s.nombres("mypump_guardar_ajustes_dieta").isEmpty)
        guard case .success = await m.crearComidaLibre(datosLibre()) else { Issue.record("no se creó"); return }
    }

    @Test func marcasDeComidasQueYaNoExistenTambienSonOtroPlan() async {
        let s = Servidor()
        s.ponerMarca(hace(2), "colacion-vieja", "A", "comido")
        let m = modelo(s); await m.cargar()
        await m.irADia(hace(2))
        #expect(m.diaPasado?.otroPlan == true)
    }

    @Test func comiSoloDentroDeLaVentanaDeLaBase() async {
        let s = Servidor(); let m = modelo(s); await m.cargar()
        #expect(m.diasMarcar == 2)
        await m.irADia(hace(2))
        #expect(m.vistaPuedeMarcar)
        await m.irADia(hace(5))
        #expect(m.vistaEditable && !m.vistaPuedeMarcar)
        await m.marcar("desayuno", .comido, opcion: 0)
        #expect(m.marcasVista.isEmpty)
        #expect(await m.outbox?.pendientes == 0)
    }

    @Test func conLaPalancaEnSieteSeMarcaHastaElSeptimoDia() async {
        let s = Servidor(); s.config = #"{"dieta_dias_marcar":7}"#
        let m = modelo(s); await m.cargar()
        #expect(m.diasMarcar == 7)
        await m.irADia(hace(7))
        #expect(m.vistaPuedeMarcar)
    }

    // MARK: - Copiar

    @Test func copiarAyerAHoyConGramosAgregadosYMarca() async {
        let s = Servidor()
        s.ponerMarca(hace(1), "desayuno", "B", "comido")
        s.ponerAjustes(hace(1), .objeto(["desayuno": .objeto(["deltaKcal": .numero(0), "opcion": .numero(1), "cantidades": .objeto(["0": .numero(80)])])]))
        s.ponerLibre(hace(1), "Pizza", 800)
        let m = modelo(s); await m.cargar()
        guard let p = await m.prepararCopia(desde: hace(1)) else { Issue.record("sin plan"); return }
        #expect(p.comidas.map(\.comidaId) == ["desayuno"] && p.libres.count == 1)
        #expect(p.comidas[0].estado == .nueva)
        let r = await m.copiarAHoy(comidas: p.comidas, libres: p.libres, reemplazar: [])
        #expect(r.comidas == 1 && r.libres == 1 && r.saltadas == 0)
        #expect(m.marcasDeHoy["desayuno"]?.opcion == "B")
        #expect(m.ajustesDeHoy["desayuno"]?.cantidades["0"] == 80)
        #expect(m.comidasLibres.first?.descripcion == "Pizza")
        await m.outbox?.drenar()
        #expect(s.nombres("mypump_marcar_comida").last?["p_fecha"]?.comoTexto == hoy)
        #expect(s.nombres("mypump_guardar_ajustes_dieta").last?["p_fecha"]?.comoTexto == hoy)
        #expect(s.nombres("mypump_crear_comida_libre").last?["p_fecha"]?.comoTexto == hoy)
    }

    @Test func nuncaPisaLoDeHoySinPermiso() async {
        let s = Servidor()
        s.ponerMarca(hace(1), "desayuno", "A", "comido")
        let m = modelo(s); await m.cargar()
        await m.marcar("desayuno", .comido, opcion: 1)        // hoy comió otra opción
        guard let p = await m.prepararCopia(desde: hace(1)) else { Issue.record("sin plan"); return }
        #expect(p.comidas[0].estado == .conflicto)
        let r = await m.copiarAHoy(comidas: p.comidas, libres: [], reemplazar: [])
        #expect(r.saltadas == 1 && r.comidas == 0)
        #expect(m.marcasDeHoy["desayuno"]?.opcion == "B")
        let r2 = await m.copiarAHoy(comidas: p.comidas, libres: [], reemplazar: ["desayuno"])
        #expect(r2.comidas == 1 && m.marcasDeHoy["desayuno"]?.opcion == "A")
    }

    @Test func algoQueHoyAparecioDespuesDeArmarLaListaTampocoSePisa() async {
        let s = Servidor()
        s.ponerMarca(hace(1), "almuerzo", "A", "comido")
        let m = modelo(s); await m.cargar()
        guard let p = await m.prepararCopia(desde: hace(1)) else { Issue.record("sin plan"); return }
        #expect(p.comidas[0].estado == .nueva)
        await m.ajustar("almuerzo", AjusteComida(deltaKcal: 100), opciones: [:])   // mientras la hoja estaba abierta
        let r = await m.copiarAHoy(comidas: p.comidas, libres: [], reemplazar: [])
        #expect(r.saltadas == 1 && m.ajustesDeHoy["almuerzo"]?.deltaKcal == 100 && m.marcasDeHoy["almuerzo"] == nil)
    }

    @Test func copiarDosVecesNoDuplicaComidasLibres() async {
        let s = Servidor()
        s.ponerLibre(hace(1), "Pizza", 800)
        let m = modelo(s); await m.cargar()
        let p = await m.prepararCopia(desde: hace(1))!
        _ = await m.copiarAHoy(comidas: [], libres: p.libres, reemplazar: [])
        _ = await m.copiarAHoy(comidas: [], libres: p.libres, reemplazar: [])
        #expect(s.nombres("mypump_crear_comida_libre").count == 1 && m.comidasLibres.count == 1)
    }

    @Test func copiarMirandoUnDiaAnteriorEscribeHoy() async {
        let s = Servidor()
        s.ponerMarca(hace(1), "almuerzo", "A", "comido")
        let m = modelo(s); await m.cargar()
        await m.irADia(hace(1))
        let p = await m.prepararCopia(desde: hace(1))!
        let r = await m.copiarAHoy(comidas: p.comidas, libres: [], reemplazar: [])
        #expect(r.comidas == 1 && m.marcasDeHoy["almuerzo"]?.estado == .comido)
        // El día que se miraba no cambió.
        #expect(m.marcasVista["almuerzo"]?.estado == .comido && m.fechaVista == hace(1))
    }

    @Test func unaLibreConFechaFijadaCaeAhiAunqueSeHayaVueltoAHoy() async {
        let s = Servidor(); let m = modelo(s); await m.cargar()
        guard case .success = await m.crearComidaLibre(datosLibre(), fecha: hace(1)) else { Issue.record("no se creó"); return }
        #expect(s.nombres("mypump_crear_comida_libre")[0]["p_fecha"]?.comoTexto == hace(1) && m.comidasLibres.isEmpty)
    }

    @Test func agregadosDeUnaComidaMarcadaFueraDeLaVentanaNoSeTocan() async {
        let s = Servidor()
        s.ponerMarca(hace(5), "almuerzo", "A", "comido")
        let m = modelo(s); await m.cargar()
        await m.irADia(hace(5))
        var a = AjusteComida()
        a.agregados = [try! JSONDecoder().decode(AlimentoAgregado.self, from: Data(#"{"nombre":"Huevo","cantidad":50,"unidad":"g","gramos":50,"kcal":70,"p":6,"c":0,"g":5,"por100":{"kcal":140,"p":12,"c":0,"g":10},"origen":"base","_ts":1}"#.utf8))]
        await m.ajustar("almuerzo", a, opciones: [:])
        #expect(m.ajustesVista.isEmpty)
        #expect(await m.outbox?.pendientes == 0)
    }

    @Test func unaFilaIlegibleNoEsUnDiaVacio() async {
        let s = Servidor()
        s.ponerAjustes(hace(1), .texto("roto"))
        let m = modelo(s); await m.cargar()
        await m.irADia(hace(1))
        #expect(m.diaPasado?.sinRed == true && !m.vistaEditable)
    }

    @Test func dosLibresIgualesEnElOrigenSeCopianLasDos() async {
        let s = Servidor()
        s.ponerLibre(hace(1), "Yogur", 100)
        s.ponerLibre(hace(1), "Yogur", 100)
        let m = modelo(s); await m.cargar()
        let p = await m.prepararCopia(desde: hace(1))!
        #expect(p.libres.map(\.estado) == [.nueva, .nueva])
        let r = await m.copiarAHoy(comidas: [], libres: p.libres, reemplazar: [])
        #expect(r.libres == 2 && m.comidasLibres.count == 2)
    }

    @Test func dosIgualesEnElOrigenYUnaHoyCopianSoloLaQueFalta() async {
        let s = Servidor()
        s.ponerLibre(hace(1), "Yogur", 100)
        s.ponerLibre(hace(1), "Yogur", 100)
        s.ponerLibre(hoy, "Yogur", 100)
        let m = modelo(s); await m.cargar()
        let p = await m.prepararCopia(desde: hace(1))!
        #expect(p.libres.map(\.estado) == [.igual, .nueva])
        let r = await m.copiarAHoy(comidas: [], libres: p.libres, reemplazar: [])
        #expect(r.libres == 1 && m.comidasLibres.count == 2)
    }

    @Test func reemplazarConOrigenSinMarcaSacaLaDeHoy() async {
        let s = Servidor()
        s.ponerAjustes(hace(1), .objeto(["almuerzo": .objeto(["deltaKcal": .numero(50)])]))
        let m = modelo(s); await m.cargar()
        await m.marcar("almuerzo", .saltado, opcion: 0)
        let p = await m.prepararCopia(desde: hace(1))!
        #expect(p.comidas[0].estado == .conflicto && p.comidas[0].marca == nil)
        let r = await m.copiarAHoy(comidas: p.comidas, libres: [], reemplazar: ["almuerzo"])
        #expect(r.comidas == 1 && m.marcasDeHoy["almuerzo"] == nil && m.ajustesDeHoy["almuerzo"]?.deltaKcal == 50)
    }

    @Test func sinRedLaCopiaAvisaEnVezDeMostrarUnDiaVacio() async {
        let s = Servidor(); let m = modelo(s); await m.cargar()
        s.sinRed = true
        let p = await m.prepararCopia(desde: hace(1))
        #expect(p == nil)
    }

    @Test func unaLecturaViejaDeOtroDiaNoEscribeElQueSeMiraAhora() async {
        let s = Servidor()
        s.ponerMarca(hace(3), "almuerzo", "A", "comido")
        let m = modelo(s); await m.cargar()
        await m.irADia(hace(3))
        await m.irADia(hace(1))
        #expect(m.marcasVista.isEmpty && m.fechaVista == hace(1))
    }
}
