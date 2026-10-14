import Foundation
import Testing
import MyPumpModelos
@testable import MyPumpReglas

// Vectores de scripts/nativa/vectores-entreno.mjs: las funciones REALES de cliente.html (normalizarRutina, los
// sugeridos, las variantes, renderSetRow, confirmarSerie, los handlers de bindTrainEvents, la poda, el descanso…)
// corridas con dobles del DOM y de la base. Igualdad total; los textos se comparan por unidades UTF-16.

let vectoresEntreno = raizRepo.appendingPathComponent("apps/shared/vectores/entreno.json")
let vectoresEntrenoPrivados = carpetaPrivada.appendingPathComponent("entreno.json")
let zonaVectores = TimeZone(identifier: "America/Argentina/Buenos_Aires")!

struct VectoresEntreno: Decodable {
    let fuente: String
    let ahora: Double
    let archivos: [String]?
    let normalizar: [CasoNormalizar]
    let textos: Textos
    let ejercicios: [CasoEjercicio]
    let reps: [CasoReps]
    let campos: [CasoCampo]?
    let rir: [CasoRir]?
    let historial: Historial
    let heredable: Heredable?
    let filas: Filas
    let confirmar: Confirmar?
    let acciones: Acciones?
    let resumen: Resumen?
    let restaurar: [CasoRestaurar]?
    let poda: Poda?
    let comentarios: Comentarios?
    let tiempo: Tiempo?
    let descanso: [[PasoDescanso]]?
    let semana: Semana
    let textosFijos: [String: String]?
    let excepciones: [String]?

    struct CasoNormalizar: Decodable {
        let est: JSONValue?
        let ref: Int?
        let usable: Bool
        let problemas: [String]
        let semanasTotal: Int?
        let dias: [DiaN]?
        struct DiaN: Decodable { let id: String; let nombre: String; let numero: String; let bloques: [[[Int]]] }
    }
    struct Textos: Decodable {
        struct DiaT: Decodable { let nombre: String?; let corto: String }
        struct BloqueT: Decodable { let titulo: String?; let subtitulo: String?; let nombre: String }
        let dias: [DiaT]
        let bloques: [BloqueT]
    }
    struct CasoEjercicio: Decodable {
        struct Var: Decodable { let etiqueta: String; let ops: [String]; let sinPeso: Bool }
        let nombre: String
        let tipo: String?
        let variantes: Var?
        let sinPeso: Bool
        let sinKg: Bool
    }
    struct CasoReps: Decodable { let reps: JSONValue?; let sug: Double? }
    struct CasoCampo: Decodable { let campo: String; let v: String?; let out: String }
    struct CasoRir: Decodable { let v: String?; let out: Double? }
    struct Historial: Decodable {
        struct Caso: Decodable {
            let ex: Int
            let h: Int
            let variante: String?
            let idx: Int
            let ref: Int?
            let kg: String
            let reps: String
            let record: String?
            let recordKg: Double
            let ultimaVez: UV?
        }
        struct UV: Decodable { let val: String; let rel: String }
        let ejercicios: [Ejercicio]
        let historiales: [[RegistroHistorico]]
        let casos: [Caso]
    }
    struct SerieJS: Decodable {
        let reps: String?
        let kg: String
        let rir: String?
        let confirmed: Bool
        let nombreRegistrado: String?
        let varianteRegistrada: String?
        var local: SerieLocal {
            SerieLocal(reps: reps ?? "", kg: kg, rir: rir ?? "", confirmada: confirmed, nombreRegistrado: nombreRegistrado, varianteRegistrada: varianteRegistrada)
        }
    }
    struct Heredable: Decodable {
        struct Caso: Decodable { let series: Int; let idx: Int; let kg: String }
        let series: [[SerieJS]]
        let casos: [Caso]
    }
    struct Filas: Decodable {
        struct Caso: Decodable {
            let ex: Int
            let efectivo: String
            let h: Int
            let series: Int
            let variante: String?
            let i: Int
            let activa: Bool
            let clase: String
            let phReps: String
            let reps: String
            let repsSoloLectura: Bool
            let phKg: String
            let kg: String
            let kgSoloLectura: Bool
            let rir: String
            let editar: Bool
            let deshabilitado: Bool
            let titulo: String?
            let pista: String?
            let calibracion: String?
        }
        let ejercicios: [Ejercicio]
        let historiales: [[RegistroHistorico]]
        let series: [[SerieJS]]
        let casos: [Caso]
    }
    struct EjSesion: Decodable { let sets: [SerieJS]; let completed: Bool; let status: String; let variante: String? }
    struct Op: Decodable { let kind: String; let key: String; let payload: JSONValue }
    struct Modal: Decodable { let titulo: String; let cuerpo: String; let confirmar: String; let cancelar: String? }
    struct Confirmar: Decodable {
        struct Antes: Decodable { let sets: [String: [SerieJS]]; let variante: [String: String]; let status: [String: String]; let swaps: [String: JSONValue] }
        struct Despues: Decodable { let sesion: [String: EjSesion]; let diaFinalizado: Bool; let expandido: String?; let finalizadaLocal: String? }
        struct Caso: Decodable {
            let nombre: String
            let ex: String
            let idx: Int
            let semana: Int
            let sesionId: String?
            let diaFinalizado: Bool
            let respuestas: [Bool]
            let antes: Antes
            let despues: Despues
            let cola: [Op]
            let modales: [Modal]
            let dudosas: [String?]
            let descanso: Double?
            let historialPedido: [String]
            let leidos: [String]
            let sesionAsegurada: Bool
            let diaCompleto: Bool
        }
        let dia: Dia
        let historial: [String: [RegistroHistorico]]
        let casos: [Caso]
    }
    struct Acciones: Decodable {
        struct Antes: Decodable { let sets: [String: String]; let status: [String: String]; let swaps: [String: JSONValue]; let expandido: String?; let conHistorial: Bool }
        struct Despues: Decodable { let sesion: [String: EjSesion]; let expandido: String?; let swaps: [String]; let historialEnCache: [String] }
        struct Caso: Decodable {
            let nombre: String
            let attr: String
            let valor: String
            let respuestas: [Bool]
            let antes: Antes
            let despues: Despues
            let cola: [Op]
            let modales: [Modal]
            let stopRest: Bool
            let sesionAsegurada: Bool
            let historialPedido: [String]
            let leidos: [String]
            let diaCompleto: Bool
            let swapsGuardados: [String]?
        }
        struct Rir: Decodable {
            let ex: String
            let confirmada: Bool
            let inicial: String
            let varianteRegistrada: String?
            let valor: String
            let leyenda: String
            let serie: SerieJS
            let cola: [Op]
        }
        let casos: [Caso]
        let rir: [Rir]
    }
    struct Resumen: Decodable {
        struct Caso: Decodable {
            let modal: String
            let series: Int
            let estados: Int
            let inicio: Double?
            let ahora: Double
            let texto: String
            let aviso: String?
            let pendientes: [String]
        }
        let series: [[String: [SerieJS]]]
        let estados: [[String: String]]
        let casos: [Caso]
    }
    struct CasoRestaurar: Decodable {
        struct Meta: Decodable { let series_completadas: Int; let marcado_manualmente: Bool }
        let nombre: String
        let registros: [RegistroSesion]?
        let estados: [EstadoEjercicio]?
        let confirmadaLocal: Bool
        let sesion: [String: EjSesion]
        let estadosLocales: [String: String]
        let meta: [String: Meta]
    }
    struct Poda: Decodable {
        struct Opciones: Decodable { let conservarDiaActual: Bool?; let sinPrefetch: Bool? }
        struct Caso: Decodable {
            let mapa: Int
            let semana: Int
            let completados: [String]
            let diaId: String
            let diaFinalizado: Bool
            let opciones: Opciones?
            let quedan: [String]
            let invalidados: [String]
            let guardo: Bool
            let prefetch: Bool
        }
        let mapas: [[String: JSONValue]]
        let casos: [Caso]
    }
    struct Comentarios: Decodable {
        struct Caso: Decodable { let filas: [String]; let porRef: [String: [String]]; let sinLeer: [String: Int]; let total: Int; let dia: Int }
        struct Fecha: Decodable { let iso: String; let texto: String }
        let filas: [Comentario]
        let casos: [Caso]
        let fechas: [Fecha]
    }
    struct Tiempo: Decodable {
        struct Fmt: Decodable { let s: Double; let texto: String }
        struct Crono: Decodable { let ms: Double; let texto: String }
        struct Min: Decodable { let inicio: Double?; let ahora: Double; let min: Int? }
        let fmt: [Fmt]
        let crono: [Crono]
        let minutos: [Min]
    }
    struct PasoDescanso: Decodable {
        struct D: Decodable { let fin: Double; let objetivo: Double; let cierre: Double; let terminado: Bool }
        struct G: Decodable { let fin: Double; let objetivo: Double; let cierre: Double }
        let accion: String
        let t: Double
        let arg: JSONValue?
        let descanso: D?
        let disparos: Int
        let guardado: G?
        let visible: Bool
        let listo: Bool
        let texto: String
        let objetivoTexto: String
        let ancho: String?
    }
    struct Semana: Decodable {
        struct Banner: Decodable { let plan: Int?; let ref: Int?; let dia: Int; let semana: Int; let offset: Int; let n: Int; let calibracion: Bool; let texto: String? }
        struct Avanzar: Decodable { let semana: Int; let total: Int; let offset: Int; let diaCompleto: Bool; let modal: Modal? }
        struct Error: Decodable { let fn: String; let caso: String; let modal: Modal? }
        struct DiaCompleto: Decodable {
            struct Caso: Decodable { let actual: String; let mostrado: Bool; let modal: Modal? }
            let dias: [Dia]
            let casos: [Caso]
        }
        let banners: [Banner]
        let planes: [JSONValue]?
        let avanzar: [Avanzar]?
        let errores: [Error]?
        let bloque: Modal?
        let diaCompleto: DiaCompleto?
    }
}

func cargarEntreno(_ url: URL) throws -> VectoresEntreno {
    try JSONDecoder().decode(VectoresEntreno.self, from: Data(contentsOf: url))
}

/// Las estructuras privadas, en el orden en que las leyó el generador.
func estructurasPrivadas(_ archivos: [String]) throws -> [EstructuraRutina] {
    let base = carpetaPrivada.deletingLastPathComponent()
    return try archivos.flatMap { try JSONDecoder().decode([EstructuraRutina?].self, from: Data(contentsOf: base.appendingPathComponent($0))).map { $0 ?? EstructuraRutina() } }
}

func estructura(_ v: JSONValue?) throws -> EstructuraRutina? {
    guard let v, v != .null else { return nil }
    return try JSONDecoder().decode(EstructuraRutina.self, from: JSONEncoder().encode(v))
}

/// El `texto()` del decodificador: un número entero se lee "12".
func textoComoDecodificador(_ v: JSONValue?) -> String? {
    switch v {
    case .texto(let s)?: return s
    case .numero(let d)?: return d == d.rounded() ? String(Int(d)) : String(d)
    default: return nil
    }
}

func modal(_ p: Pregunta?) -> String {
    guard let p else { return "nil" }
    return "\(p.titulo) | \(p.cuerpo) | \(p.confirmar) | \(p.cancelar)"
}

func modal(_ m: VectoresEntreno.Modal?) -> String {
    guard let m else { return "nil" }
    return "\(m.titulo) | \(m.cuerpo) | \(m.confirmar) | \(m.cancelar ?? "")"
}

// MARK: - Verificaciones (públicos y privados usan las mismas)

func fallasNormalizar(_ v: VectoresEntreno, privadas: [EstructuraRutina] = []) throws -> [String] {
    var fallas: [String] = []
    for (k, c) in v.normalizar.enumerated() {
        let e: EstructuraRutina? = try c.ref.map { privadas[$0] } ?? estructura(c.est)
        let r = NormalizacionRutina.normalizar(e)
        var malos: [String] = []
        if r.usable != c.usable { malos.append("usable \(r.usable)") }
        if r.problemas != c.problemas { malos.append("problemas \(r.problemas) vs \(c.problemas)") }
        if let dias = c.dias {
            if r.estructura.semanasTotal != c.semanasTotal { malos.append("semanas \(String(describing: r.estructura.semanasTotal))") }
            if r.estructura.dias.count != dias.count { malos.append("días \(r.estructura.dias.count)") }
            for (d, w) in zip(r.estructura.dias, dias) {
                if !JS.iguales(d.id, w.id) || !JS.iguales(d.nombre, w.nombre) { malos.append("día \(String(describing: d.id)) \(String(describing: d.nombre))") }
                let n = String(TextosEntreno.numeroDia(d, en: r.estructura.dias))
                if n != w.numero { malos.append("número \(n) vs \(w.numero)") }
                let bloques = d.bloques.map { $0.ejercicios.map { [$0.descansoSegundos ?? -1, $0.series ?? -1] } }
                if bloques != w.bloques { malos.append("bloques \(bloques) vs \(w.bloques)") }
            }
        }
        if !malos.isEmpty { fallas.append("#\(k): \(malos)") }
    }
    return fallas
}

func fallasTextos(_ v: VectoresEntreno) -> [String] {
    var fallas: [String] = []
    for c in v.textos.dias where !JS.iguales(TextosEntreno.nombreCortoDia(c.nombre), c.corto) {
        fallas.append("día \(String(describing: c.nombre).debugDescription): web \(c.corto.debugDescription), swift \(TextosEntreno.nombreCortoDia(c.nombre).debugDescription)")
    }
    for c in v.textos.bloques {
        let s = TextosEntreno.nombreBloque(Bloque(titulo: c.titulo, subtitulo: c.subtitulo))
        if !JS.iguales(s, c.nombre) { fallas.append("bloque \(String(describing: c.titulo)) / \(String(describing: c.subtitulo)): web \(c.nombre.debugDescription), swift \(s.debugDescription)") }
    }
    return fallas
}

func fallasEjercicios(_ v: VectoresEntreno) -> [String] {
    var fallas: [String] = []
    for c in v.ejercicios {
        let var_ = ReglasEjercicio.variantes(c.nombre)
        let okVar = (var_ == nil && c.variantes == nil)
            || (var_?.etiqueta == c.variantes?.etiqueta && var_?.opciones == c.variantes?.ops && var_?.sinPeso == c.variantes?.sinPeso)
        let sinPeso = ReglasEjercicio.esSinPeso(nombre: c.nombre, tipo: c.tipo)
        let sinKg = ReglasEjercicio.sinKg(nombre: c.nombre, tipo: c.tipo)
        if !okVar || sinPeso != c.sinPeso || sinKg != c.sinKg {
            fallas.append("\(c.nombre.debugDescription) [\(c.tipo ?? "-")]: variantes \(String(describing: var_)) vs \(String(describing: c.variantes?.ops)), sinPeso \(sinPeso) vs \(c.sinPeso), sinKg \(sinKg) vs \(c.sinKg)")
        }
    }
    for c in v.reps {
        let s = ReglasEjercicio.repsDelPlan(textoComoDecodificador(c.reps))
        if s != c.sug { fallas.append("reps \(String(describing: c.reps)): web \(String(describing: c.sug)), swift \(String(describing: s))") }
    }
    return fallas
}

func fallasHistorial(_ v: VectoresEntreno) -> [String] {
    var fallas: [String] = []
    let ahora = Date(timeIntervalSince1970: v.ahora / 1000)
    for c in v.historial.casos {
        let ex = v.historial.ejercicios[c.ex]
        let h = v.historial.historiales[c.h]
        var dia = DiaEnCurso(dia: Dia(id: "d1", bloques: [Bloque(ejercicios: [ex])]), semana: 1, zona: zonaVectores)
        dia.ejercicios[ex.id]?.variante = c.variante
        dia.historial[ex.id] = h
        let (va, def) = dia.varianteActiva(ex.id)
        let ref = HistorialEntreno.ultimaSerie(h, indice: c.idx, variante: va, esDefault: def, zona: zonaVectores)
        let kg = dia.kgUltimaVez(ex.id, c.idx), reps = dia.repsUltimaVez(ex.id, c.idx)
        let record = dia.record(ex.id), recordKg = HistorialEntreno.recordKg(h)
        let uv = dia.ultimaVez(ex.id, ahora: ahora)
        let okUV = (uv == nil && c.ultimaVez == nil) || (JS.iguales(uv?.valor, c.ultimaVez?.val) && JS.iguales(uv?.cuando, c.ultimaVez?.rel))
        if ref != c.ref || !JS.iguales(kg, c.kg) || !JS.iguales(reps, c.reps) || !JS.iguales(record, c.record) || recordKg != c.recordKg || !okUV {
            fallas.append("\(ex.nombre) h\(c.h) \(c.variante ?? "-") #\(c.idx): ref \(String(describing: ref))/\(String(describing: c.ref)) kg \(kg)/\(c.kg) reps \(reps)/\(c.reps) record \(String(describing: record))/\(String(describing: c.record)) \(recordKg)/\(c.recordKg) última \(String(describing: uv))/\(String(describing: c.ultimaVez))")
        }
    }
    return fallas
}

func fallasFilas(_ v: VectoresEntreno) -> [String] {
    var fallas: [String] = []
    for c in v.filas.casos {
        let ex = v.filas.ejercicios[c.ex]
        var dia = DiaEnCurso(dia: Dia(id: "d1", bloques: [Bloque(ejercicios: [ex])]), semana: 1, zona: zonaVectores)
        dia.ejercicios[ex.id] = EjercicioEnSesion(series: v.filas.series[c.series].map(\.local), variante: c.variante)
        dia.historial[ex.id] = v.filas.historiales[c.h]
        var efectivo = ex
        efectivo.nombre = c.efectivo
        guard let f = dia.fila(ex.id, c.i, efectivo: efectivo) else { fallas.append("sin fila \(c)"); continue }
        let clase = "set-row" + (f.confirmada ? " is-confirmed" : "") + (!f.confirmada && !c.activa ? " is-pending" : "") + (c.activa ? " is-active" : "")
        let pista = f.pista.map { "\($0.antes)«\($0.negrita)»\($0.despues)" }
        let serie = v.filas.series[c.series][c.i]
        var malos: [String] = []
        if f.activa != c.activa { malos.append("activa") }
        if clase != c.clase { malos.append("clase \(clase)") }
        if !JS.iguales(f.placeholderReps, c.phReps) { malos.append("phReps \(f.placeholderReps)") }
        if !JS.iguales(serie.reps ?? "", c.reps) || f.confirmada != c.repsSoloLectura { malos.append("reps") }
        if !JS.iguales(f.placeholderKg, c.phKg) { malos.append("phKg \(f.placeholderKg)") }
        if !JS.iguales(f.kg, c.kg) || (f.confirmada || f.sinKg) != c.kgSoloLectura { malos.append("kg \(f.kg) \(f.sinKg)") }
        if !JS.iguales(f.rir, c.rir) { malos.append("rir \(f.rir)") }
        if f.confirmada != c.editar || !f.puedeConfirmar != c.deshabilitado { malos.append("botón \(f.puedeConfirmar)") }
        if !JS.iguales(f.tituloConfirmar, c.titulo) { malos.append("título \(String(describing: f.tituloConfirmar))") }
        if !JS.iguales(pista, c.pista) { malos.append("pista \(String(describing: pista))") }
        if !JS.iguales(f.calibracion, c.calibracion) { malos.append("calibración \(String(describing: f.calibracion))") }
        if !malos.isEmpty { fallas.append("\(ex.nombre) → \(c.efectivo) h\(c.h) series\(c.series) \(c.variante ?? "-") #\(c.i): \(malos) — web \(c)") }
    }
    return fallas
}

func fallasBanners(_ banners: [VectoresEntreno.Semana.Banner], planes: [EstructuraRutina?]) -> [String] {
    var normalizados: [Int: EstructuraRutina] = [:]
    var fallas: [String] = []
    for b in banners {
        let i = b.ref ?? b.plan ?? -1
        let est = normalizados[i] ?? NormalizacionRutina.normalizar(planes[i]).estructura
        normalizados[i] = est
        let r = SemanaEntreno.banner(est.dias[b.dia], semana: b.semana, offset: b.offset)
        if r.cambian != b.n || r.calibracion != b.calibracion || !JS.iguales(r.texto, b.texto) {
            fallas.append("plan \(i) día \(b.dia) sem \(b.semana)+\(b.offset): \(r) vs n \(b.n) calibración \(b.calibracion)")
        }
    }
    return fallas
}

/// El estado del día después de una acción, contra el de la web.
func diferenciaSesion(_ d: DiaEnCurso, _ web: [String: VectoresEntreno.EjSesion]) -> [String] {
    var malos: [String] = []
    for (id, w) in web {
        guard let e = d.ejercicios[id] else { malos.append("\(id) no está"); continue }
        let series = w.sets.map(\.local)
        if e.series.map({ SerieLocal(reps: $0.reps, kg: $0.kg, rir: $0.rir, confirmada: $0.confirmada, nombreRegistrado: $0.nombreRegistrado,
                                     varianteRegistrada: $0.varianteRegistrada) }) != series {
            malos.append("\(id) series \(e.series) vs \(series)")
        }
        if e.completo != w.completed || e.estado != w.status || !JS.iguales(e.variante, w.variante) {
            malos.append("\(id) completo \(e.completo)/\(w.completed) estado \(e.estado)/\(w.status) variante \(String(describing: e.variante))/\(String(describing: w.variante))")
        }
    }
    return malos
}

/// La cola de Swift contra la de la web: mismo payload y la misma clave + la semana (arreglo nativo n.º 1).
func diferenciaCola(_ efectos: [DiaEnCurso.Efecto], _ web: [VectoresEntreno.Op], semana: Int) -> [String] {
    let cola = efectos.compactMap { e -> (String, JSONValue, String)? in
        if case .encolar(let k, let p, let c) = e { return (k, p, c) }
        return nil
    }
    guard cola.count == web.count else { return ["cola \(cola.map(\.2)) vs \(web.map(\.key))"] }
    var malos: [String] = []
    for (s, w) in zip(cola, web) where s.0 != w.kind || s.1 != w.payload || s.2 != "\(w.key)_s\(semana)" {
        malos.append("op \(s.0) \(s.2) \(s.1) vs \(w.kind) \(w.key) \(w.payload)")
    }
    return malos
}

func pedidos(_ efectos: [DiaEnCurso.Efecto]) -> (historial: [String], leidos: [String], descanso: Double?, detener: Bool, asegurar: Bool, completo: Bool, guardar: Bool, reabrio: Bool) {
    var h: [String] = [], l: [String] = [], d: Double? = nil, det = false, a = false, c = false, g = false, r = false
    for e in efectos {
        switch e {
        case .pedirHistorial(let x): h.append(x)
        case .marcarLeidos(let x): l.append(x)
        case .iniciarDescanso(let s): d = s
        case .detenerDescanso: det = true
        case .asegurarSesion: a = true
        case .diaCompleto: c = true
        case .guardarSustituciones: g = true
        case .reabrioDia: r = true
        case .encolar: break
        }
    }
    return (h, l, d, det, a, c, g, r)
}

// MARK: - Tests

@Suite("Entreno: misma salida que la web")
struct EntrenoVectoresTests {
    @Test func normalizarRutina() throws {
        let v = try cargarEntreno(vectoresEntreno)
        #expect(v.normalizar.count >= 10)
        let f = try fallasNormalizar(v)
        #expect(f.isEmpty, "\(f.count) de \(v.normalizar.count): \(f.prefix(5))")
    }

    @Test func textosDeDiaYBloque() throws {
        let v = try cargarEntreno(vectoresEntreno)
        let f = fallasTextos(v)
        #expect(f.isEmpty, "\(f.count): \(f.prefix(8))")
    }

    @Test func variantesSinKgYRepsDelPlan() throws {
        let v = try cargarEntreno(vectoresEntreno)
        #expect(v.ejercicios.count > 100)
        let f = fallasEjercicios(v)
        #expect(f.isEmpty, "\(f.count): \(f.prefix(8))")
    }

    @Test func camposYRIR() throws {
        let v = try cargarEntreno(vectoresEntreno)
        for c in v.campos ?? [] {
            #expect(JS.iguales(CamposSerie.normalizar(c.campo, c.v), c.out), "\(c.campo) \(String(describing: c.v)): web \(c.out), swift \(CamposSerie.normalizar(c.campo, c.v))")
        }
        for c in v.rir ?? [] {
            #expect(CamposSerie.rir(c.v) == c.out, "rir \(String(describing: c.v)): web \(String(describing: c.out)), swift \(String(describing: CamposSerie.rir(c.v)))")
        }
    }

    @Test func historialSugeridosRecordYUltimaVez() throws {
        let v = try cargarEntreno(vectoresEntreno)
        #expect(v.historial.casos.count > 500)
        let f = fallasHistorial(v)
        #expect(f.isEmpty, "\(f.count) de \(v.historial.casos.count): \(f.prefix(5))")
        for c in v.heredable?.casos ?? [] {
            let s = HistorialEntreno.kgHeredable(v.heredable!.series[c.series].map(\.local), indice: c.idx)
            #expect(s == c.kg, "heredable \(c.series) #\(c.idx): web \(c.kg), swift \(s)")
        }
    }

    @Test func filaDeUnaSerie() throws {
        let v = try cargarEntreno(vectoresEntreno)
        #expect(v.filas.casos.count > 1000)
        let f = fallasFilas(v)
        #expect(f.isEmpty, "\(f.count) de \(v.filas.casos.count): \(f.prefix(4))")
    }

    /// Lo que hace el modelo: un paso, y si pregunta, otro con la respuesta.
    func confirmar(_ d: inout DiaEnCurso, _ id: String, _ idx: Int, preguntar: (Pregunta) -> Bool) -> [DiaEnCurso.Efecto] {
        var r = DiaEnCurso.Respuestas()
        var efectos: [DiaEnCurso.Efecto] = []
        while true {
            let paso = d.confirmarSerie(id, idx, respuestas: r)
            efectos += paso.efectos
            guard let p = paso.pregunta, let motivo = paso.motivo else { return efectos }
            let si = preguntar(p)
            switch motivo {
            case .reabrir: r.reabrir = si
            case .registrarIgual: r.registrarIgual = si
            }
        }
    }

    @Test func confirmarSerie() async throws {
        let v = try cargarEntreno(vectoresEntreno)
        let c = try #require(v.confirmar)
        #expect(c.casos.count > 30)
        for caso in c.casos {
            var d = DiaEnCurso(dia: c.dia, semana: caso.semana, sesionId: caso.sesionId, diaFinalizado: caso.diaFinalizado, zona: zonaVectores)
            d.historial = c.historial
            d.expandido = caso.ex
            for (k, s) in caso.antes.sets { d.ejercicios[k]?.series = s.map(\.local) }
            for (k, x) in caso.antes.variante { d.ejercicios[k]?.variante = x }
            for (k, x) in caso.antes.status { d.estados[k] = x; d.ejercicios[k]?.estado = x }
            d.sustituciones = caso.antes.swaps
            var respuestas = caso.respuestas
            var preguntas: [Pregunta] = []
            let efectos = confirmar(&d, caso.ex, caso.idx) { p in
                preguntas.append(p)
                return respuestas.isEmpty ? false : respuestas.removeFirst()
            }
            var malos = diferenciaSesion(d, caso.despues.sesion) + diferenciaCola(efectos, caso.cola, semana: caso.semana)
            let p = pedidos(efectos)
            if preguntas.map(modal) != caso.modales.map(modal) { malos.append("modales \(preguntas.map(modal))") }
            let aviso = d.ejercicios[caso.ex]?.series[caso.idx].aviso
            let avisoWeb: String?? = caso.dudosas.last.map { $0 ?? "" }
            if aviso != avisoWeb ?? nil { malos.append("aviso \(String(describing: aviso)) vs \(caso.dudosas)") }
            if p.descanso != caso.descanso { malos.append("descanso \(String(describing: p.descanso))") }
            if p.historial != caso.historialPedido || p.leidos != caso.leidos { malos.append("historial \(p.historial) leídos \(p.leidos)") }
            if p.asegurar != caso.sesionAsegurada || p.completo != caso.diaCompleto { malos.append("sesión \(p.asegurar) día completo \(p.completo)") }
            if d.diaFinalizado != caso.despues.diaFinalizado || d.expandido != caso.despues.expandido { malos.append("día \(d.diaFinalizado) expandido \(String(describing: d.expandido))") }
            let finalizadaLocal: String? = caso.diaFinalizado && !p.reabrio ? "1" : nil
            if finalizadaLocal != caso.despues.finalizadaLocal { malos.append("marca local \(String(describing: finalizadaLocal))") }
            #expect(malos.isEmpty, "\(caso.nombre): \(malos)")
        }
    }

    @Test func accionesDeLaCard() async throws {
        let v = try cargarEntreno(vectoresEntreno)
        let c = try #require(v.confirmar)
        let a = try #require(v.acciones)
        for caso in a.casos {
            var d = DiaEnCurso(dia: c.dia, semana: 1, sesionId: "ses-1", zona: zonaVectores)
            d.historial = caso.antes.conHistorial ? c.historial : [:]
            d.expandido = caso.antes.expandido
            for (k, modo) in caso.antes.sets {
                let series = d.ejercicios[k]!.series.enumerated().map { i, s in
                    modo == "todas" || i == 0 ? SerieLocal(reps: "10", kg: "50", confirmada: true) : s
                }
                d.ejercicios[k]?.series = series
            }
            for (k, x) in caso.antes.status { d.estados[k] = x; d.ejercicios[k]?.estado = x }
            d.sustituciones = caso.antes.swaps
            var respuestas = caso.respuestas
            var preguntas: [Pregunta] = []
            var asegurada = false
            let id = String(caso.valor.split(separator: "|", maxSplits: 1)[0])
            let resto = caso.valor.contains("|") ? String(caso.valor[caso.valor.index(after: caso.valor.firstIndex(of: "|")!)...]) : ""
            let efectos: [DiaEnCurso.Efecto]
            switch caso.attr {
            case "data-mark": efectos = d.marcarCompleto(id)
            case "data-finish":
                if let p = d.preguntaTerminar(id) {
                    preguntas.append(p)
                    guard respuestas.isEmpty ? false : respuestas.removeFirst() else { efectos = []; break }
                }
                asegurada = true
                efectos = d.terminar(id)
            case "data-reopen": efectos = d.reabrir(id)
            case "data-edit": efectos = d.editarSerie(id, Int(resto)!)
            case "data-variante": d.elegirVariante(id, resto); efectos = []
            case "data-toggle": efectos = d.tocarCard(id)
            case "data-revert-ex": efectos = d.revertir(id)
            default: Issue.record("acción desconocida \(caso.attr)"); continue
            }
            var malos = diferenciaSesion(d, caso.despues.sesion) + diferenciaCola(efectos, caso.cola, semana: 1)
            let p = pedidos(efectos)
            if preguntas.map(modal) != caso.modales.map(modal) { malos.append("modales \(preguntas.map(modal))") }
            if d.expandido != caso.despues.expandido { malos.append("expandido \(String(describing: d.expandido))") }
            if d.sustituciones.keys.sorted() != caso.despues.swaps { malos.append("swaps \(d.sustituciones.keys.sorted())") }
            if d.historial.keys.sorted() != caso.despues.historialEnCache { malos.append("historial en caché \(d.historial.keys.sorted())") }
            if p.detener != caso.stopRest || (asegurada || p.asegurar) != caso.sesionAsegurada { malos.append("descanso \(p.detener) sesión \(asegurada)") }
            if p.historial != caso.historialPedido || p.leidos != caso.leidos || p.completo != caso.diaCompleto { malos.append("pedidos \(p)") }
            if (p.guardar ? d.sustituciones.keys.sorted() : nil) != caso.swapsGuardados { malos.append("guardadas \(p.guardar)") }
            #expect(malos.isEmpty, "\(caso.nombre): \(malos)")
        }
        for r in a.rir {
            var d = DiaEnCurso(dia: c.dia, semana: 1, sesionId: "ses-1", zona: zonaVectores)
            d.ejercicios[r.ex]?.series[1] = SerieLocal(reps: "8", kg: "82.5", rir: r.inicial, confirmada: r.confirmada, varianteRegistrada: r.varianteRegistrada)
            #expect(CamposSerie.leyendaRIR(r.inicial) == r.leyenda)
            let efectos = d.elegirRIR(r.ex, 1, r.valor)
            #expect(d.ejercicios[r.ex]?.series[1] == r.serie.local)
            #expect(diferenciaCola(efectos, r.cola, semana: 1).isEmpty, "rir \(r.valor): \(efectos)")
        }
    }

    @Test func resumenDelCierre() throws {
        let v = try cargarEntreno(vectoresEntreno)
        let c = try #require(v.confirmar)
        let r = try #require(v.resumen)
        #expect(r.casos.count > 50)
        for caso in r.casos {
            var d = DiaEnCurso(dia: c.dia, semana: 1, zona: zonaVectores)
            for (k, s) in r.series[caso.series] { d.ejercicios[k]?.series = s.map(\.local) }
            for (k, x) in r.estados[caso.estados] { d.estados[k] = x }
            let minutos = TiempoEntreno.minutosSesion(inicio: caso.inicio, ahora: caso.ahora)
            let texto = caso.modal == "openFinishModal" ? d.resumen.textoCierre : d.resumen.textoCierreAnticipado(minutos: minutos)
            #expect(texto == caso.texto, "\(caso.modal) series \(caso.series): web \(caso.texto), swift \(texto)")
            if caso.modal == "openEarlyFinishModal" {
                #expect(d.avisoPendientes == caso.aviso, "aviso \(String(describing: d.avisoPendientes))")
                #expect(d.pendientes == caso.pendientes, "pendientes \(d.pendientes)")
            }
        }
    }

    @Test func restaurarRegistrosYEstados() throws {
        let v = try cargarEntreno(vectoresEntreno)
        let c = try #require(v.confirmar)
        for caso in v.restaurar ?? [] {
            var d = DiaEnCurso(dia: c.dia, semana: 1, sesionId: "ses-1", zona: zonaVectores)
            if caso.confirmadaLocal { d.ejercicios["pre-d2-0"]?.series[1] = SerieLocal(reps: "7", kg: "85", confirmada: true) }
            d.aplicarEstados(caso.estados ?? [])
            d.aplicarRegistros(caso.registros ?? [])
            let malos = diferenciaSesion(d, caso.sesion)
            #expect(malos.isEmpty, "\(caso.nombre): \(malos)")
            #expect(d.estados == caso.estadosLocales, "\(caso.nombre): estados \(d.estados)")
            #expect(d.meta.mapValues { [$0.seriesCompletadas, $0.manual ? 1 : 0] } == caso.meta.mapValues { [$0.series_completadas, $0.marcado_manualmente ? 1 : 0] },
                    "\(caso.nombre): meta \(d.meta)")
        }
    }

    @Test func podaDeSustituciones() throws {
        let v = try cargarEntreno(vectoresEntreno)
        let p = try #require(v.poda)
        #expect(p.casos.count > 100)
        for c in p.casos {
            let r = SustitucionesEntreno.podar(p.mapas[c.mapa], semanaActual: c.semana, diasCompletados: Set(c.completados), diaActual: c.diaId,
                                               diaFinalizado: c.diaFinalizado, conservarDiaActual: c.opciones?.conservarDiaActual == true)
            let bien = r.quedan.keys.sorted() == c.quedan && r.borradas.sorted() == c.invalidados && !r.borradas.isEmpty == c.guardo
                && (!r.borradas.isEmpty && c.opciones?.sinPrefetch != true) == c.prefetch
            #expect(bien, "mapa \(c.mapa) sem \(c.semana) \(c.completados) \(c.diaId) cerrado \(c.diaFinalizado) \(String(describing: c.opciones)): \(r.quedan.keys.sorted()) vs \(c.quedan)")
        }
    }

    @Test func comentarios() throws {
        let v = try cargarEntreno(vectoresEntreno)
        let c = try #require(v.comentarios)
        let dia = try #require(v.confirmar?.dia)
        for caso in c.casos {
            let filas = caso.filas.compactMap { id in c.filas.first { $0.id == id } }
            let i = IndiceComentarios(filas)
            #expect(i.porReferencia.mapValues { $0.map(\.id) } == caso.porRef)
            #expect(i.sinLeer == caso.sinLeer)
            #expect(i.totalEntreno == caso.total)
            #expect(i.sinLeer(dia: dia) == caso.dia)
        }
        for f in c.fechas {
            #expect(JS.iguales(IndiceComentarios.fecha(f.iso, zona: zonaVectores), f.texto), "\(f.iso): web \(f.texto), swift \(IndiceComentarios.fecha(f.iso, zona: zonaVectores))")
        }
    }

    @Test func tiempoDeLaSesion() throws {
        let v = try cargarEntreno(vectoresEntreno)
        let t = try #require(v.tiempo)
        for c in t.fmt { #expect(TiempoEntreno.fmtTiempo(c.s) == c.texto, "fmtTime(\(c.s))") }
        for c in t.crono { #expect(TiempoEntreno.fmtCrono(c.ms) == c.texto, "fmtCrono(\(c.ms))") }
        for c in t.minutos {
            #expect(TiempoEntreno.minutosSesion(inicio: c.inicio, ahora: c.ahora) == c.min, "minutosSesion(\(String(describing: c.inicio)), \(c.ahora))")
        }
    }

    @Test func descanso() throws {
        let v = try cargarEntreno(vectoresEntreno)
        let secuencias = try #require(v.descanso)
        for (k, pasos) in secuencias.enumerated() {
            var b = BarraDescanso()
            var disparos = 0
            for p in pasos {
                let ahora = v.ahora + p.t
                switch p.accion {
                case "iniciar": b.iniciar(segundos: p.arg?.comoNumero ?? 0, ahora: ahora)
                case "tick": if b.tick(ahora: ahora) { disparos += 1 }
                case "restaurar": b.restaurar(ahora: ahora)
                case "saltar": b.ajustar("skip", ahora: ahora)
                default: b.ajustar(p.arg?.comoTexto ?? "", ahora: ahora)
                }
                let d = b.descanso.map { [$0.fin - v.ahora, $0.objetivo, $0.cierre - v.ahora, $0.terminado ? 1 : 0] }
                let dw = p.descanso.map { [$0.fin, $0.objetivo, $0.cierre, $0.terminado ? 1 : 0] }
                let g = b.guardado.map { [$0.endsAt - v.ahora, $0.target, ($0.autoCloseAt ?? 0) - v.ahora] }
                let gw = p.guardado.map { [$0.fin, $0.objetivo, $0.cierre] }
                let ancho = b.porcentaje.map { JS.texto($0) + "%" }
                let bien = d == dw && g == gw && disparos == p.disparos && b.visible == p.visible && b.listo == p.listo
                    && b.texto == p.texto && b.textoObjetivo == p.objetivoTexto && ancho == p.ancho
                #expect(bien, "secuencia \(k), \(p.accion) en \(p.t): \(b) vs \(p)")
            }
        }
    }

    @Test func semanaBannersYPreguntas() throws {
        let v = try cargarEntreno(vectoresEntreno)
        let planes = try (v.semana.planes ?? []).map(estructura)
        let f = fallasBanners(v.semana.banners, planes: planes)
        #expect(v.semana.banners.count > 100)
        #expect(f.isEmpty, "\(f.count): \(f.prefix(5))")
        for c in v.semana.avanzar ?? [] {
            let p = SemanaEntreno.preguntaAvanzar(semana: c.semana, total: c.total, offset: c.offset, diaCompleto: c.diaCompleto)
            #expect(modal(p) == modal(c.modal), "avanzar \(c.semana)/\(c.total)+\(c.offset)")
        }
        for c in v.semana.errores ?? [] {
            let sinRed = c.caso == "red" || c.caso == "transitorio"
            let p = c.fn == "doAvanzarSemana" ? SemanaEntreno.errorAvanzar(sinRed: sinRed) : SemanaEntreno.errorBloqueNuevo(sinRed: sinRed)
            #expect(modal(p) == modal(c.modal), "\(c.fn) \(c.caso)")
        }
        #expect(modal(SemanaEntreno.preguntaBloqueNuevo) == modal(v.semana.bloque))
        if let dc = v.semana.diaCompleto {
            for c in dc.casos {
                let p = c.mostrado ? nil : SemanaEntreno.preguntaDiaCompletado(dias: dc.dias, actual: c.actual).pregunta
                #expect(modal(p) == modal(c.modal), "día completado \(c.actual)")
            }
        }
    }

    @Test func textosFijosIgualesALaWeb() throws {
        let v = try cargarEntreno(vectoresEntreno)
        let t = try #require(v.textosFijos)
        let nuestros: [String: String] = [
            "diaVacio": TextosEntreno.diaVacio, "demo": TextosEntreno.demo, "empezar": TextosEntreno.empezar,
            "empezarDetalle": TextosEntreno.empezarDetalle, "sinCerrar": TextosEntreno.sinCerrar, "porPrimeraSerie": TextosEntreno.porPrimeraSerie,
            "sinComentarios": TextosEntreno.sinComentarios, "comentarioFallo": TextosEntreno.comentarioFallo,
            "cerrarSinSesion": TextosEntreno.cerrarSinSesion, "cerrarFallo": TextosEntreno.cerrarFallo, "sinVariantes": TextosEntreno.sinVariantes,
        ]
        #expect(Set(t.keys) == Set(nuestros.keys))
        for (k, web) in t { #expect(nuestros[k] == web, "\(k): web \(web.debugDescription), swift \(String(describing: nuestros[k]).debugDescription)") }
    }

    // MARK: Privados: las estructuras de los planes activos reales (fuera del repo)

    @Test(.enabled(if: FileManager.default.fileExists(atPath: vectoresEntrenoPrivados.path)))
    func planesReales() throws {
        let v = try cargarEntreno(vectoresEntrenoPrivados)
        let privadas = try estructurasPrivadas(v.archivos ?? [])
        #expect(v.normalizar.count > 50)
        let n = try fallasNormalizar(v, privadas: privadas)
        #expect(n.isEmpty, "normalizar: \(n.count) de \(v.normalizar.count): \(n.prefix(3))")
        let t = fallasTextos(v)
        #expect(t.isEmpty, "textos: \(t.count): \(t.prefix(5))")
        let e = fallasEjercicios(v)
        #expect(v.ejercicios.count > 1000)
        #expect(e.isEmpty, "ejercicios: \(e.count) de \(v.ejercicios.count): \(e.prefix(5))")
        let h = fallasHistorial(v)
        #expect(h.isEmpty, "historial: \(h.count) de \(v.historial.casos.count): \(h.prefix(3))")
        let f = fallasFilas(v)
        #expect(v.filas.casos.count > 10_000)
        #expect(f.isEmpty, "filas: \(f.count) de \(v.filas.casos.count): \(f.prefix(3))")
        let b = fallasBanners(v.semana.banners, planes: privadas.map { Optional($0) })
        #expect(b.isEmpty, "banners: \(b.count) de \(v.semana.banners.count): \(b.prefix(3))")
    }
}
