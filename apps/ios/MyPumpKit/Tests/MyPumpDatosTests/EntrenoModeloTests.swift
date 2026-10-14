import Foundation
import Testing
import MyPumpModelos
import MyPumpReglas
@testable import MyPumpDatos

// El modelo de Entreno contra un servidor de mentira que contesta por RPC (las respuestas tienen la forma de las
// reales: apps/shared/fixtures). Los casos de la sesión cacheada son los de scripts/test-sesion-cacheada.mjs de la
// rama fix/sesion-cache-valida-servidor (SES-02).

/// Contesta cada RPC con lo que diga su regla; nil es "sin red". Anota todo lo que le piden.
final class Servidor: Transporte, @unchecked Sendable {
    typealias Regla = @Sendable (JSONValue) async -> (status: Int, cuerpo: String)?
    private let lock = NSLock()
    private var reglas: [String: Regla] = [:]
    private var anotadas: [(String, JSONValue)] = []

    func regla(_ fn: String, _ r: @escaping Regla) { lock.withLock { reglas["mypump_\(fn)"] = r } }
    func cuando(_ fn: String, _ status: Int, _ cuerpo: String) { regla(fn) { _ in (status, cuerpo) } }
    func cuando(_ fn: String, _ cuerpo: String) { cuando(fn, 200, cuerpo) }
    func sinRed(_ fn: String) { regla(fn) { _ in nil } }

    func llamadas(_ fn: String) -> [JSONValue] { lock.withLock { anotadas.filter { $0.0 == "mypump_\(fn)" }.map(\.1) } }
    var orden: [String] { lock.withLock { anotadas.map(\.0) } }

    func enviar(_ pedido: URLRequest) async throws -> (Data, URLResponse) {
        let fn = pedido.url!.lastPathComponent
        let cuerpo = pedido.httpBody.flatMap { try? JSONDecoder().decode(JSONValue.self, from: $0) } ?? .null
        let regla: Regla? = lock.withLock {
            anotadas.append((fn, cuerpo))
            return reglas[fn]
        }
        guard let regla else { return (Data("[]".utf8), HTTPURLResponse(url: pedido.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!) }
        guard let r = await regla(cuerpo) else { throw URLError(.notConnectedToInternet) }
        return (Data(r.cuerpo.utf8), HTTPURLResponse(url: pedido.url!, statusCode: r.status, httpVersion: nil, headerFields: nil)!)
    }
}

/// Una demora que NO se corta al cancelar la tarea (como una respuesta de red que igual llega).
func demora(_ ms: Int) async {
    await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
        DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(ms)) { c.resume() }
    }
}

final class RelojDePrueba: @unchecked Sendable {
    private let lock = NSLock()
    private var valor: Double
    init(_ ms: Double) { valor = ms }
    var ms: Double { get { lock.withLock { valor } } set { lock.withLock { valor = newValue } } }
}

let AHORA = 1_792_000_800_000.0          // 14-oct-2026 15:00 en Buenos Aires
let JULIO = 1_784_570_400_000.0          // 20-jul-2026 18:00 UTC
let zonaAR = TimeZone(identifier: "America/Argentina/Buenos_Aires")!

let estructuraDePrueba = """
{"semanas_total":12,"dias":[
  {"id":"d1","n":1,"nombre":"TIRÓN A — ANCHO","bloques":[{"titulo":"BLOQUE 1 — ESPALDA","ejercicios":[
    {"id":"jal-d1-0","nombre":"Jalón al pecho","tipo":"compuesto","descanso_segundos":150,"progresion":[{"semana":1,"series":2,"reps":"10","rir":"1"}]},
    {"id":"rem-d1-1","nombre":"Remo con barra","tipo":"compuesto","descanso_segundos":0,"progresion":[{"semana":1,"series":2,"reps":"8","rir":"1"}]}]}]},
  {"id":"d2","n":2,"nombre":"EMPUJE","bloques":[{"titulo":"BLOQUE 1 — PECHO","ejercicios":[
    {"id":"pre-d2-0","nombre":"Press banca","tipo":"compuesto","descanso_segundos":180,"progresion":[{"semana":1,"series":1,"reps":"8","rir":"1"}]}]}]},
  {"id":"d3","nombre":"PIERNA","bloques":[{"titulo":"BLOQUE 1","ejercicios":[
    {"id":"sen-d3-0","nombre":"Sentadilla","tipo":"compuesto","descanso_segundos":180,"progresion":[{"semana":1,"series":1,"reps":"6","rir":"1"}]}]}]}
]}
"""

/// La fila de `get_rutina_activa` de la rutina de prueba.
func filaRutina(semana: Int = 5, tieneSiguiente: Bool = false) -> String {
    #"{"id":"rut-prueba","version":1,"semana_actual":\#(semana),"tiene_siguiente":\#(tieneSiguiente),"estructura":\#(estructuraDePrueba)}"#
}

func rutinaDePrueba(semana: Int = 5, tieneSiguiente: Bool = false) -> RutinaActiva {
    try! JSONDecoder().decode(RutinaActiva.self, from: Data(filaRutina(semana: semana, tieneSiguiente: tieneSiguiente).utf8))
}

/// Un catálogo chico: los tres comparten patrón y músculo, así "Jalón al pecho" tiene sustitutos.
let catalogoDePrueba = try! CatalogoEjercicios(json: Data("""
[{"slug_en":"Wide-Grip_Lat_Pulldown","name_en":"Wide-Grip Lat Pulldown","primary_muscle":"lats","equipment":"cable","patron_movimiento":"traccion_vertical"},
 {"slug_en":"V-Bar_Pulldown","name_en":"V-Bar Pulldown","primary_muscle":"lats","equipment":"cable","patron_movimiento":"traccion_vertical"},
 {"slug_en":"Pullups","name_en":"Pullups","primary_muscle":"lats","equipment":"body only","patron_movimiento":"traccion_vertical"}]
""".utf8))

@MainActor
struct Banco {
    let servidor = Servidor()
    let reloj = RelojDePrueba(AHORA)
    let raiz = FileManager.default.temporaryDirectory.appendingPathComponent("mypump-entreno-\(UUID().uuidString)")
    var disco: Disco { Disco(raiz: raiz, token: "tok-prueba") }
    let cola: Outbox

    init(ejecutar: Bool = false) {
        let cliente = ClienteRPC(transporte: servidor)
        let escrituras = Escrituras(cliente: cliente, token: "tok-prueba")
        cola = Outbox(archivo: nil, reintentoAutomatico: false) { op in
            ejecutar ? await escrituras.ejecutar(op) : .respuesta(.failure(ErrorRPC(clase: .red, status: 0, mensaje: "sin mandar")))
        }
    }

    func modelo(_ rutina: RutinaActiva = rutinaDePrueba(), token: String? = "tok-prueba") -> ModeloEntreno {
        let r = reloj
        return ModeloEntreno(cliente: ClienteRPC(transporte: servidor), token: token, outbox: token == nil ? nil : cola, disco: token == nil ? nil : disco,
                             rutina: rutina, catalogo: catalogoDePrueba, zona: zonaAR, reloj: { Date(timeIntervalSince1970: r.ms / 1000) })
    }

    func cacheDeSesion(_ m: [String: ModeloEntreno.SesionLocal]) { disco.guardar(m, ModeloEntreno.Archivo.sesiones) }
    var sesionesEnDisco: [String: ModeloEntreno.SesionLocal] { disco.leer([String: ModeloEntreno.SesionLocal].self, ModeloEntreno.Archivo.sesiones) ?? [:] }
}

func sesionJSON(_ id: String, dia: String = "d1", semana: Int = 5, iniciada: String? = nil, finalizada: String? = nil) -> String {
    let i = iniciada.map { "\"\($0)\"" } ?? "null", f = finalizada.map { "\"\($0)\"" } ?? "null"
    return #"[{"id":"\#(id)","dia_id":"\#(dia)","semana":\#(semana),"iniciada_en":\#(i),"finalizada_en":\#(f)}]"#
}

@Suite("Entreno: la sesión del día se confirma con el servidor (SES-02)", .serialized)
@MainActor
struct EntrenoSesionTests {
    /// El teléfono de Matoff: abrió el día 1 de la semana 5 del bloque viejo, lo cerró, y le quedó todo eso guardado.
    func cacheViejo(_ b: Banco, semana: Int = 5) {
        b.cacheDeSesion(["d1": .init(sesionId: "ses-vieja", semana: semana, finalizada: true, inicio: JULIO)])
    }

    @Test func mismaSesionEnElServidor_seUsaElCache() async {
        let b = Banco()
        cacheViejo(b)
        b.servidor.cuando("get_sesion_dia", sesionJSON("ses-vieja"))
        let m = b.modelo()
        await m.restaurarSesion()
        #expect(m.dia.sesionId == "ses-vieja")
        // El cerrado es LOCAL a propósito: reabrir el día solo borra la marca del teléfono.
        #expect(m.dia.diaFinalizado)
        #expect(m.inicioSesion == JULIO)
        #expect(b.servidor.llamadas("get_sesion_dia").count == 1)
        #expect(b.servidor.llamadas("get_registros_sesion").first?["p_sesion_id"]?.comoTexto == "ses-vieja")
        #expect(b.servidor.llamadas("get_ejercicios_estado").count == 1)
    }

    @Test func noHaySesionDelDia_arrancaLimpioYSeBorraElCache() async {
        let b = Banco()
        cacheViejo(b)
        b.servidor.cuando("get_sesion_dia", "[]")
        let m = b.modelo()
        await m.restaurarSesion()
        #expect(m.dia.sesionId == nil && !m.sesionIniciada && !m.dia.diaFinalizado && m.inicioSesion == nil)
        #expect(b.sesionesEnDisco["d1"] == nil)
        #expect(b.servidor.llamadas("get_registros_sesion").isEmpty, "traía las series de julio")
        #expect(b.servidor.llamadas("get_sesion_dia").count == 1)
    }

    @Test func otraSesion_seUsaEsaConSuArranque() async {
        let b = Banco()
        cacheViejo(b)
        b.servidor.cuando("get_sesion_dia", sesionJSON("ses-nueva", iniciada: "2026-09-26T13:00:00Z"))
        let m = b.modelo()
        await m.restaurarSesion()
        let iniciada = FechaJS.leer("2026-09-26T13:00:00Z")!.timeIntervalSince1970 * 1000
        #expect(m.dia.sesionId == "ses-nueva" && !m.dia.diaFinalizado)
        // El arranque guardado era el de la sesión archivada: no se hereda.
        #expect(m.inicioSesion == iniciada)
        #expect(b.sesionesEnDisco["d1"] == .init(sesionId: "ses-nueva", semana: 5, finalizada: false, inicio: iniciada))
        #expect(b.servidor.llamadas("get_sesion_dia").count == 1, "se reusa la respuesta")
        #expect(b.servidor.llamadas("get_registros_sesion").first?["p_sesion_id"]?.comoTexto == "ses-nueva")
    }

    @Test func laOtraYaEstaCerrada_elDiaApareceCerrado() async {
        let b = Banco()
        b.cacheDeSesion(["d1": .init(sesionId: "ses-vieja", semana: 5, finalizada: false, inicio: JULIO)])
        b.servidor.cuando("get_sesion_dia", sesionJSON("ses-nueva", iniciada: "2026-09-25T13:00:00Z", finalizada: "2026-09-25T14:10:00Z"))
        let m = b.modelo()
        await m.restaurarSesion()
        #expect(m.dia.diaFinalizado)
        #expect(b.sesionesEnDisco["d1"]?.finalizada == true)
    }

    @Test func sinRed_seConfiaEnElCache() async {
        let b = Banco()
        cacheViejo(b)
        b.servidor.sinRed("get_sesion_dia")
        let m = b.modelo()
        await m.restaurarSesion()
        #expect(m.dia.sesionId == "ses-vieja" && m.dia.diaFinalizado && m.inicioSesion == JULIO)
        #expect(b.sesionesEnDisco["d1"] == .init(sesionId: "ses-vieja", semana: 5, finalizada: true, inicio: JULIO))
    }

    @Test func errorDelServidor_tampocoSeDescarta() async {
        let b = Banco()
        cacheViejo(b)
        b.servidor.cuando("get_sesion_dia", 503, #"{"code":"","message":"Service Unavailable"}"#)
        let m = b.modelo()
        await m.restaurarSesion()
        #expect(m.dia.sesionId == "ses-vieja")
        #expect(b.sesionesEnDisco["d1"]?.sesionId == "ses-vieja")
    }

    @Test func cacheDeOtraSemana_seBorraYSePreguntaUnaVez() async {
        let b = Banco()
        cacheViejo(b, semana: 4)
        b.servidor.cuando("get_sesion_dia", "[]")
        let m = b.modelo()
        await m.restaurarSesion()
        #expect(m.dia.sesionId == nil)
        #expect(b.sesionesEnDisco["d1"] == nil)
        #expect(b.servidor.llamadas("get_sesion_dia").map { $0["p_semana"] } == [.numero(5)])
    }

    @Test func sinCache_preguntaYGuardaLoQueVenga() async {
        let b = Banco()
        b.servidor.cuando("get_sesion_dia", sesionJSON("ses-x", iniciada: "2026-10-14T17:00:00Z"))
        let m = b.modelo()
        await m.restaurarSesion()
        #expect(m.dia.sesionId == "ses-x" && m.sesionIniciada)
        #expect(b.sesionesEnDisco["d1"]?.sesionId == "ses-x")
        #expect(m.minutos == 60)
    }

    @Test func laRespuestaTardiaDelDiaAnteriorNoPisaLaDelDiaNuevo() async {
        let b = Banco()
        b.cacheDeSesion(["d1": .init(sesionId: "ses-vieja", semana: 5), "d2": .init(sesionId: "ses-d2", semana: 5)])
        b.servidor.regla("get_sesion_dia") { p in
            if p["p_dia_id"]?.comoTexto == "d1" {
                await demora(150)
                return (200, sesionJSON("ses-vieja"))
            }
            return (200, sesionJSON("ses-d2", dia: "d2"))
        }
        let m = b.modelo()
        async let primera: Void = m.restaurarSesion()   // día 1: la respuesta tarda
        try? await Task.sleep(for: .milliseconds(20))
        await m.cambiarDia("d2")                          // día 2: responde enseguida
        await primera
        #expect(m.dia.dia.id == "d2" && m.dia.sesionId == "ses-d2")
        #expect(!b.servidor.llamadas("get_registros_sesion").contains { $0["p_sesion_id"]?.comoTexto == "ses-vieja" })
    }

    @Test func loQueSigueEnLaColaSePintaEncimaDeLoDelServidor() async {
        let b = Banco()
        b.servidor.cuando("get_sesion_dia", sesionJSON("ses-1"))
        // El servidor tiene la serie 2 con lo de antes; en la cola está corregida (sin red): gana la cola.
        b.servidor.cuando("get_registros_sesion", #"[{"ejercicio_id":"jal-d1-0","serie_numero":2,"peso_kg":60,"reps_realizadas":8,"rir_real":null,"notas":null,"ejercicio_nombre":"Jalón al pecho"}]"#)
        await b.cola.encolar("carga", EscriturasEntreno.carga(sesionId: "ses-1", dia: "d1", semana: 5, ejercicio: "jal-d1-0", indice: 1,
                                                              serie: SerieLocal(reps: "9", kg: "62,5", rir: "0", varianteRegistrada: "Supino"),
                                                              nombre: "Jalón al pecho", varianteEjercicio: "Prono"),
                              dedupeKey: EscriturasEntreno.claveCarga(dia: "d1", ejercicio: "jal-d1-0", indice: 1, semana: 5))
        // Otra semana: no es de este día que se mira.
        await b.cola.encolar("carga", EscriturasEntreno.carga(sesionId: nil, dia: "d1", semana: 4, ejercicio: "jal-d1-0", indice: 0,
                                                              serie: SerieLocal(reps: "8", kg: "60"), nombre: "Jalón al pecho", varianteEjercicio: nil),
                              dedupeKey: EscriturasEntreno.claveCarga(dia: "d1", ejercicio: "jal-d1-0", indice: 0, semana: 4))
        let m = b.modelo()
        await m.restaurarSesion()
        let series = m.dia.ejercicios["jal-d1-0"]?.series
        #expect(series?[1] == SerieLocal(reps: "9", kg: "62.5", rir: "0", confirmada: true, nombreRegistrado: "Jalón al pecho", varianteRegistrada: "Supino"))
        #expect(series?[0].confirmada == false)
        #expect(await b.cola.pendientes == 2, "las dos semanas conviven en la cola (dedupe con semana)")
    }

    /// Revisión del 14-oct, hallazgo 5: sin señal en el gimnasio la sesión no se pudo crear y las series quedaron en la
    /// cola. Al volver al día (o abrir la app sin red) tienen que verse confirmadas, no vacías.
    @Test func sinSesionYSinRed_laColaIgualSePinta() async {
        let b = Banco()
        b.servidor.sinRed("get_sesion_dia")
        await b.cola.encolar("carga", EscriturasEntreno.carga(sesionId: nil, dia: "d1", semana: 5, ejercicio: "jal-d1-0", indice: 0,
                                                              serie: SerieLocal(reps: "10", kg: "60"), nombre: "Jalón al pecho", varianteEjercicio: nil),
                              dedupeKey: EscriturasEntreno.claveCarga(dia: "d1", ejercicio: "jal-d1-0", indice: 0, semana: 5))
        let m = b.modelo()
        await m.restaurarSesion()
        #expect(m.dia.sesionId == nil)
        #expect(m.dia.ejercicios["jal-d1-0"]?.series[0].confirmada == true)
        #expect(m.dia.ejercicios["jal-d1-0"]?.series[0].kg == "60")
    }
}

@Suite("Entreno: historial por clave (SER-08/09/10)", .serialized)
@MainActor
struct EntrenoHistorialTests {
    let filaJalon = #"{"clave":"jalon al pecho","registrado_en":"2026-10-12T21:00:00+00:00","peso_kg":60,"reps_realizadas":10,"rir_real":1,"serie_numero":1,"notas":null,"ejercicio_nombre":"Jalón al pecho"}"#

    @Test func unPedidoPorDia_yLaClaveEsLaDelEfectivo() async {
        let b = Banco()
        b.servidor.cuando("get_historico_por_clave", "[\(filaJalon)]")
        let m = b.modelo()
        await m.precargarHistorial()
        #expect(b.servidor.llamadas("get_historico_por_clave").count == 1)
        let claves = b.servidor.llamadas("get_historico_por_clave").first?["p_claves"]
        #expect(claves == .lista([.texto("jalon al pecho"), .texto("remo con barra")]))
        #expect(b.servidor.llamadas("get_historico_por_clave").first?["p_limit_por_ej"] == .numero(48))
        #expect(m.dia.historial["jal-d1-0"]?.count == 1 && m.dia.historial["rem-d1-1"] == [])
        #expect(m.dia.record("jal-d1-0") == "60kg × 10 · RIR 1")
    }

    @Test func pgrst202_caeAlCaminoViejo_yQuedaRecordado() async {
        let b = Banco()
        b.servidor.cuando("get_historico_por_clave", 404, #"{"code":"PGRST202","message":"Could not find the function public.mypump_get_historico_por_clave"}"#)
        b.servidor.cuando("get_historico_ejercicio", "[\(filaJalon)]")
        let m = b.modelo()
        await m.pedirHistorial("jal-d1-0")
        #expect(m.dia.historial["jal-d1-0"]?.count == 1)
        await m.pedirHistorial("rem-d1-1")
        #expect(b.servidor.llamadas("get_historico_por_clave").count == 1, "la ausencia se recuerda")
        #expect(b.servidor.llamadas("get_historico_ejercicio").map { $0["p_ejercicio_id"] } == [.texto("jal-d1-0"), .texto("rem-d1-1")])
    }

    @Test func sinRed_quedaSinCargar_yNuncaCaeAlCaminoPorLugar() async {
        let b = Banco()
        b.servidor.sinRed("get_historico_por_clave")
        let m = b.modelo()
        await m.pedirHistorial("jal-d1-0")
        #expect(m.dia.historial["jal-d1-0"] == nil, "un corte no es 'Primera vez'")
        #expect(b.servidor.llamadas("get_historico_ejercicio").isEmpty, "por lugar el historial viene mezclado")
        // Vuelve la señal: el próximo toque lo trae.
        b.servidor.cuando("get_historico_por_clave", "[\(filaJalon)]")
        await m.tocarCard("jal-d1-0")
        #expect(m.dia.historial["jal-d1-0"]?.count == 1)
    }

    @Test func unaRespuestaViejaNoPisaElHistorialDeUnLugarYaSustituido() async throws {
        let b = Banco()
        b.servidor.regla("get_historico_por_clave") { p in
            if p["p_claves"] == .lista([.texto("jalon al pecho")]) {
                await demora(150)   // llega DESPUÉS que la del sustituto
                return (200, #"[{"clave":"jalon al pecho","registrado_en":"2026-10-12T21:00:00+00:00","peso_kg":60,"reps_realizadas":10,"rir_real":1,"serie_numero":1,"notas":null,"ejercicio_nombre":"Jalón al pecho"}]"#)
            }
            return (200, "[]")
        }
        let m = b.modelo()
        let sub = try #require(m.sustitutos("jal-d1-0").first)
        async let viejo: Void = m.pedirHistorial("jal-d1-0")
        try await Task.sleep(for: .milliseconds(20))
        await m.sustituir("jal-d1-0", por: sub, fijar: false)
        await viejo
        #expect(m.clave("jal-d1-0") == ClaveEjercicio.de(sub.nombre))
        #expect(m.dia.historial["jal-d1-0"] == [], "quedó el historial del original bajo el lugar sustituido")
        #expect(b.servidor.llamadas("get_historico_por_clave").count == 2)
    }
}

@Suite("Entreno: series, cola, cierre y semana", .serialized)
@MainActor
struct EntrenoAccionesTests {
    @Test func confirmarEncolaConLaSemana_yArrancaElDescanso() async throws {
        let b = Banco()
        let m = b.modelo()
        m.escribir("jal-d1-0", 0, campo: "reps", valor: "10")
        m.escribir("jal-d1-0", 0, campo: "kg", valor: "62,5")
        await m.elegirRIR("jal-d1-0", 0, 0)
        await m.confirmarSerie("jal-d1-0", 0) { _ in true }
        let op = try #require(await b.cola.operaciones.first)
        #expect(op.kind == "carga" && op.dedupeKey == "carga_d1_jal-d1-0_0_s5")
        #expect(op.payload["datos"]?["peso"] == .numero(62.5) && op.payload["datos"]?["rir"] == .numero(0))
        #expect(op.payload["datos"]?["notas"]?.comoTexto == "Prono", "la variante default del jalón")
        #expect(m.descanso.descanso?.objetivo == 150 && m.descanso.visible)
        #expect(b.disco.leer(Descanso.Guardado.self, ModeloEntreno.Archivo.descanso)?.target == 150)
        #expect(m.inicioSesion == AHORA, "el cronómetro arranca con la primera serie")
        // El descanso 0 del plan es 90 (normalizarRutina).
        m.escribir("rem-d1-1", 0, campo: "reps", valor: "8")
        m.escribir("rem-d1-1", 0, campo: "kg", valor: "70")
        await m.confirmarSerie("rem-d1-1", 0) { _ in true }
        #expect(m.descanso.descanso?.objetivo == 90)
    }

    @Test func conSustitucion_vaElNombreDelSustitutoYElIdDelLugar() async throws {
        let b = Banco()
        let m = b.modelo()
        let sub = try #require(m.sustitutos("jal-d1-0").first)
        await m.sustituir("jal-d1-0", por: sub, fijar: true)
        m.escribir("jal-d1-0", 0, campo: "reps", valor: "10")
        m.escribir("jal-d1-0", 0, campo: "kg", valor: "50")
        await m.confirmarSerie("jal-d1-0", 0) { _ in true }
        let op = try #require(await b.cola.operaciones.first)
        #expect(op.payload["datos"]?["ejercicioNombre"]?.comoTexto == sub.nombre)
        #expect(op.payload["datos"]?["ejercicioId"]?.comoTexto == "jal-d1-0")
        // En disco, con el formato de la web.
        let guardadas = try #require(b.disco.leer([String: JSONValue].self, ModeloEntreno.Archivo.sustituciones("rut-prueba")))
        #expect(guardadas["jal-d1-0"]?["current"]?["nombre"]?.comoTexto == sub.nombre)
        #expect(guardadas["jal-d1-0"]?["fijado"] == .bool(true) && guardadas["jal-d1-0"]?["semana"] == .numero(5))
        #expect(guardadas["jal-d1-0"]?["diaId"]?.comoTexto == "d1" && guardadas["jal-d1-0"]?["original"]?["nombre"]?.comoTexto == "Jalón al pecho")
        await m.revertirSustitucion("jal-d1-0")
        #expect(m.efectivo(m.dia.ejercicio("jal-d1-0")!).sustituido == false)
    }

    @Test func lasNoFijadasDeOtraSemanaSePodanAlCargar() async {
        let b = Banco()
        b.disco.guardar(["jal-d1-0": JSONValue.objeto(["original": .objeto(["nombre": .texto("Jalón al pecho")]),
                                                       "current": .objeto(["nombre": .texto("Dominadas")]), "fijado": .bool(false),
                                                       "semana": .numero(4), "diaId": .texto("d1")]),
                         "rem-d1-1": .objeto(["current": .objeto(["nombre": .texto("Remo en T")]), "semana": .numero(4), "diaId": .texto("d1")])],
                        ModeloEntreno.Archivo.sustituciones("rut-prueba"))
        let m = b.modelo()
        await m.cargar()
        // La de otra semana sin fijar se va; la que no tenía `fijado` cuenta como fijada y queda.
        #expect(m.dia.sustituciones.keys.sorted() == ["rem-d1-1"])
        #expect(m.efectivo(m.dia.ejercicio("rem-d1-1")!).ejercicio.nombre == "Remo en T")
    }

    @Test func cerrarElDia_primeroVaciaLaCola() async throws {
        let b = Banco(ejecutar: true)
        b.servidor.cuando("get_sesion_dia", sesionJSON("ses-1", iniciada: "2026-10-14T17:30:00Z"))
        b.servidor.cuando("registrar_carga", #""fila-1""#)
        b.servidor.cuando("finalizar_sesion", "true")
        let m = b.modelo()
        await m.restaurarSesion()
        m.escribir("jal-d1-0", 0, campo: "reps", valor: "10")
        m.escribir("jal-d1-0", 0, campo: "kg", valor: "60")
        await m.confirmarSerie("jal-d1-0", 0) { _ in true }
        let r = await m.cerrarDia(notas: "  molestia en el hombro  ")
        #expect(r == .cerrado)
        let orden = b.servidor.orden.filter { $0 == "mypump_registrar_carga" || $0 == "mypump_finalizar_sesion" }
        #expect(orden.last == "mypump_finalizar_sesion" && orden.contains("mypump_registrar_carga"))
        let fin = try #require(b.servidor.llamadas("finalizar_sesion").first)
        #expect(fin["p_notas"]?.comoTexto == "molestia en el hombro" && fin["p_duracion_segundos"] == .numero(1800))
        #expect(m.dia.diaFinalizado && m.hecho(m.dias[0]) && b.sesionesEnDisco["d1"]?.finalizada == true)
        #expect(await b.cola.pendientes == 0)
    }

    @Test func cerrarElDia_conFalse_avisa_yConMasDe6hLaDuracionVaNull() async throws {
        let b = Banco(ejecutar: true)
        b.servidor.cuando("get_sesion_dia", sesionJSON("ses-1", iniciada: "2026-10-14T03:00:00Z"))
        b.servidor.cuando("finalizar_sesion", "false")
        let m = b.modelo()
        await m.restaurarSesion()
        #expect(m.cronometro() == .sinCerrar)
        #expect(await m.cerrarDia(notas: "") == .fallo)
        #expect(b.servidor.llamadas("finalizar_sesion").first?["p_duracion_segundos"] == .null)
        #expect(!m.dia.diaFinalizado)
    }

    @Test func diaCerrado_cargarUnaSeriePreguntaSiSeReabre() async throws {
        let b = Banco()
        b.cacheDeSesion(["d1": .init(sesionId: "ses-1", semana: 5, finalizada: true)])
        b.servidor.cuando("get_sesion_dia", sesionJSON("ses-1", finalizada: "2026-10-14T17:00:00Z"))
        let m = b.modelo()
        await m.restaurarSesion()
        m.escribir("jal-d1-0", 0, campo: "reps", valor: "10")
        m.escribir("jal-d1-0", 0, campo: "kg", valor: "60")
        var preguntas: [String] = []
        await m.confirmarSerie("jal-d1-0", 0) { p in preguntas.append(p.titulo); return false }
        let pendientes = await b.cola.pendientes
        #expect(preguntas == ["Este día ya lo cerraste"] && m.dia.diaFinalizado && pendientes == 0)
        await m.confirmarSerie("jal-d1-0", 0) { p in preguntas.append(p.titulo); return true }
        #expect(!m.dia.diaFinalizado && b.sesionesEnDisco["d1"]?.finalizada == false)
        let op = try #require(await b.cola.operaciones.first)
        #expect(op.payload["sesionId"]?.comoTexto == "ses-1", "la misma sesión")
    }

    @Test func avanzarSemana_mandaElDestino_borraLasSesiones_yRecarga() async {
        let b = Banco()
        // También la de un día que no se mira: si no se borra, queda colgada hasta que se lo abra.
        b.cacheDeSesion(["d1": .init(sesionId: "ses-1", semana: 5), "d3": .init(sesionId: "ses-3", semana: 5, finalizada: true)])
        b.servidor.cuando("avanzar_semana", "6")
        b.servidor.cuando("get_rutina_activa", "[\(filaRutina(semana: 6))]")
        let m = b.modelo()
        var avisada: RutinaActiva?
        m.alCambiarRutina = { avisada = $0 }
        #expect(m.puedeAvanzar && m.botonAvanzar == "Pasar a Semana 6 →")
        #expect(await m.avanzarSemana() == .listo)
        #expect(b.servidor.llamadas("avanzar_semana").first?["p_semana_destino"] == .numero(6))
        #expect(m.semana == 6 && avisada?.semanaActual == 6)
        #expect(b.sesionesEnDisco.isEmpty)
    }

    @Test func avanzarSemana_sinRed_yRechazado() async {
        let b = Banco()
        b.servidor.sinRed("avanzar_semana")
        let m = b.modelo()
        #expect(await m.avanzarSemana() == .error(SemanaEntreno.errorAvanzar(sinRed: true)))
        b.servidor.cuando("avanzar_semana", 400, #"{"code":"P0001","message":"no"}"#)
        #expect(await m.avanzarSemana() == .error(SemanaEntreno.errorAvanzar(sinRed: false)))
        b.servidor.cuando("activar_siguiente", "false")
        #expect(await m.empezarBloqueNuevo() == .error(SemanaEntreno.errorBloqueNuevo(sinRed: false)))
    }

    @Test func comentarios_directosConAviso_yLeidosOptimistas() async {
        let b = Banco()
        b.servidor.cuando("get_comentarios", #"[{"id":"c1","ambito":"ejercicio","referencia_id":"jal-d1-0","referencia_nombre":"Jalón al pecho","autor":"coach","contenido":"bajá el peso","leido_por_cliente":false,"leido_por_coach":true,"created_at":"2026-10-13T12:00:00+00:00"},{"id":"c2","ambito":"general","referencia_id":null,"referencia_nombre":null,"autor":"coach","contenido":"hola","leido_por_cliente":false,"leido_por_coach":true,"created_at":"2026-10-13T12:00:00+00:00"}]"#)
        let m = b.modelo()
        await m.cargarComentarios()
        #expect(m.sinLeerEntreno == 1 && m.sinLeer(m.dias[0]) == 1, "el chat no cuenta en Entreno")
        b.servidor.cuando("agregar_comentario", "null")
        #expect(await m.comentar("jal-d1-0", "  hice 2 menos  ") == false, "null es que no se guardó")
        b.servidor.cuando("agregar_comentario", #""c3""#)
        #expect(await m.comentar("jal-d1-0", "  hice 2 menos  "))
        let enviado = b.servidor.llamadas("agregar_comentario").last
        #expect(enviado?["p_contenido"]?.comoTexto == "hice 2 menos" && enviado?["p_referencia_nombre"]?.comoTexto == "Jalón al pecho")
        await m.marcarLeidos("jal-d1-0")
        #expect(m.comentarios.sinLeer(ejercicio: "jal-d1-0") == 0)
        #expect(b.servidor.llamadas("marcar_leidos_cliente").first?["p_referencia_id"]?.comoTexto == "jal-d1-0")
    }

    @Test func elDescansoSobreviveAlReinicio_yRestaurarLoBorra() async {
        let b = Banco()
        let m = b.modelo()
        m.escribir("jal-d1-0", 0, campo: "reps", valor: "10")
        m.escribir("jal-d1-0", 0, campo: "kg", valor: "60")
        await m.confirmarSerie("jal-d1-0", 0) { _ in true }
        m.ajustarDescanso(15)
        b.reloj.ms = AHORA + 60_000
        let otro = b.modelo()
        await otro.cargar()
        #expect(otro.descanso.visible && otro.descanso.descanso?.objetivo == 165 && otro.descanso.texto == "1:45")
        #expect(b.disco.leer(Descanso.Guardado.self, ModeloEntreno.Archivo.descanso) == nil, "como la web: restaurar lo borra")
        b.reloj.ms = AHORA + 165_000
        #expect(otro.tickDescanso() == true)
        b.reloj.ms = AHORA + 167_000
        otro.tickDescanso()
        #expect(!otro.descanso.visible)
    }

    @Test func diaCompleto_unaSolaVez() async throws {
        let b = Banco()
        let m = b.modelo()
        await m.cambiarDia("d2")
        m.escribir("pre-d2-0", 0, campo: "reps", valor: "8")
        m.escribir("pre-d2-0", 0, campo: "kg", valor: "80")
        let completo = try #require(await m.confirmarSerie("pre-d2-0", 0) { _ in true })
        #expect(completo.pregunta.cuerpo == "Buen trabajo. ¿Querés ir al siguiente día (PIERNA)?" && completo.siguiente?.id == "d3")
        await m.reabrir("pre-d2-0")
        #expect(await m.marcarCompleto("pre-d2-0") == nil, "ya se mostró en este día")
    }

    @Test func laSesionEnVueloDeOtroDiaNoSeReusa() async {
        let b = Banco()
        b.servidor.regla("iniciar_sesion") { p in
            if p["p_dia_id"]?.comoTexto == "d1" { await demora(150); return (200, #""ses-d1""#) }
            return (200, #""ses-d2""#)
        }
        let m = b.modelo()
        async let primera = m.asegurarSesion()
        try? await Task.sleep(for: .milliseconds(20))
        await m.cambiarDia("d2")
        let segunda = await m.asegurarSesion()
        _ = await primera
        #expect(segunda == "ses-d2" && m.dia.sesionId == "ses-d2")
        #expect(b.sesionesEnDisco["d1"]?.sesionId == nil, "la del día 1 llegó tarde: no se guarda como la del día que se mira")
    }

    @Test func otroCargarNoBorraElDescansoEnCurso() async {
        let b = Banco()
        let m = b.modelo()
        await m.cargar()
        m.escribir("jal-d1-0", 0, campo: "reps", valor: "10")
        m.escribir("jal-d1-0", 0, campo: "kg", valor: "60")
        await m.confirmarSerie("jal-d1-0", 0) { _ in true }
        await m.cargar()
        #expect(m.descanso.visible && b.disco.leer(Descanso.Guardado.self, ModeloEntreno.Archivo.descanso) != nil)
    }

    @Test func demo_noEscribeNiTocaLaRed() async {
        let b = Banco()
        let m = b.modelo(token: nil)
        await m.cargar()
        m.escribir("jal-d1-0", 0, campo: "reps", valor: "10")
        m.escribir("jal-d1-0", 0, campo: "kg", valor: "60")
        await m.confirmarSerie("jal-d1-0", 0) { _ in true }
        #expect(m.dia.ejercicios["jal-d1-0"]?.series[0].confirmada == true && m.descanso.visible)
        #expect(b.servidor.orden.isEmpty)
        #expect(!m.puedeAvanzar)
    }
}

@Suite("Entreno: lo que dejó la app vieja", .serialized)
@MainActor
struct EntrenoLegadoTests {
    @Test func clavesCrudasDelLocalStorage() {
        let l = LegadoEntreno.desdeAlmacenamiento([
            "mypump_sesion_tok_d1": "ses-vieja", "mypump_sesion_tok_d1_semana": "5", "mypump_sesion_tok_d1_start": "1784570400000",
            "mypump_sesion_tok_d1_finalizada": "1", "mypump_sesion_tok_b2d3_start": "1784570500000",
            "mypump_sesion_otro_d1": "de-otra-cuenta", "mypump_rest_tok": #"{"endsAt":1792000830000,"target":90,"autoCloseAt":1792000832000}"#,
            "mypump_dia_visualizado_rut-prueba": "d2", "mypump_exercise_swaps_rut-prueba": #"{"jal-d1-0":{"current":{"nombre":"Dominadas"},"fijado":true}}"#,
        ], token: "tok", rutinaId: "rut-prueba")
        #expect(l.sesiones == [.init(diaId: "b2d3", inicio: 1_784_570_500_000), .init(diaId: "d1", sesionId: "ses-vieja", semana: 5, inicio: JULIO, finalizada: true)])
        #expect(l.descanso == .init(endsAt: 1_792_000_830_000, target: 90, autoCloseAt: 1_792_000_832_000))
        #expect(l.diaVisualizado == "d2" && l.sustituciones?["jal-d1-0"]?["current"]?["nombre"]?.comoTexto == "Dominadas")
    }

    @Test func unaSesionViejaQueElServidorArchivoSeDescarta() async {
        let b = Banco()
        b.servidor.cuando("get_sesion_dia", "[]")
        b.disco.guardar(JSONValue.objeto(["dias": .objeto(["d1": .objeto(["sesionId": .texto("ses-julio"), "_semana": .numero(5), "_start": .numero(JULIO),
                                                                           "_finalizada": .bool(true)])]),
                                          "descanso": .objeto(["endsAt": .numero(AHORA + 30_000), "target": .numero(90), "autoCloseAt": .numero(AHORA + 32_000)]),
                                          "diaVisualizado": .texto("d1")]),
                        ModeloEntreno.Archivo.legado)
        let m = b.modelo()
        await m.cargar()
        #expect(await m.aplicarLegadoDelDisco())
        #expect(m.dia.sesionId == nil && !m.dia.diaFinalizado, "nada de sesiones fantasma")
        #expect(m.descanso.visible && m.descanso.texto == "0:30")
        #expect(b.disco.leer(JSONValue.self, ModeloEntreno.Archivo.legado) == nil)
        #expect(await m.aplicarLegadoDelDisco() == false, "no se aplica dos veces")
    }

    @Test func laSesionViejaConfirmadaSeRetoma() async {
        let b = Banco()
        b.servidor.cuando("get_sesion_dia", sesionJSON("ses-1"))
        b.servidor.cuando("get_registros_sesion", #"[{"ejercicio_id":"jal-d1-0","serie_numero":1,"peso_kg":60,"reps_realizadas":10,"rir_real":0,"notas":"Neutro","ejercicio_nombre":"Jalón al pecho"}]"#)
        let m = b.modelo()
        await m.aplicarLegado(LegadoEntreno(sesiones: [.init(diaId: "d1", sesionId: "ses-1", semana: 5, inicio: AHORA - 600_000)]))
        #expect(m.dia.sesionId == "ses-1" && m.inicioSesion == AHORA - 600_000)
        #expect(m.dia.ejercicios["jal-d1-0"]?.series[0].confirmada == true && m.dia.ejercicios["jal-d1-0"]?.variante == "Neutro")
    }
}

