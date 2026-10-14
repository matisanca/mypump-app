import Foundation
import MyPumpModelos

// Entreno, lo que es de cada serie: variantes y "sin kg" (SER-07, ENT-13), los sugeridos de un toque y el kg heredado
// (SER-01, SER-03), la lectura de los campos (SER-04), el RIR (SER-02), los topes y las preguntas (SER-05), el récord y
// "Última vez" (SER-08) y lo que viaja en la cola (`writeSet`, `writeExerciseStatus`). Port de cliente.html; lo
// verifican los vectores de scripts/nativa/vectores-entreno.mjs.

/// Una serie del día (`STATE.session[ex].sets[i]`). Los campos son texto, como en la web: lo que tipeó el cliente.
public struct SerieLocal: Codable, Equatable, Sendable {
    public var reps: String
    public var kg: String
    /// "" = no lo cargó; "0" = fue al fallo (RIR 0 ≠ null, SER-02).
    public var rir: String
    public var confirmada: Bool
    /// Con qué nombre se registró (el del sustituto, si sustituyó): reabrir el día no la renombra al original.
    public var nombreRegistrado: String?
    /// La variante con la que se registró ESTA serie (la del ejercicio cambia; la de la serie no).
    public var varianteRegistrada: String?
    /// El aviso de la fila dudosa ("Revisá las repeticiones: 1214"). Se borra al tipear.
    public var aviso: String?

    public init(reps: String = "", kg: String = "", rir: String = "", confirmada: Bool = false,
                nombreRegistrado: String? = nil, varianteRegistrada: String? = nil, aviso: String? = nil) {
        self.reps = reps; self.kg = kg; self.rir = rir; self.confirmada = confirmada
        self.nombreRegistrado = nombreRegistrado; self.varianteRegistrada = varianteRegistrada; self.aviso = aviso
    }
}

/// Un ejercicio del día en la sesión (`STATE.session[ex]`).
public struct EjercicioEnSesion: Equatable, Sendable {
    public var series: [SerieLocal]
    /// `completed`
    public var completo: Bool
    /// `status`: pendiente, completo, completo_sin_datos o saltado.
    public var estado: String
    /// La variante elegida (agarre o nivel); nil si el ejercicio no tiene.
    public var variante: String?

    public init(series: [SerieLocal], completo: Bool = false, estado: String = "pendiente", variante: String? = nil) {
        self.series = series; self.completo = completo; self.estado = estado; self.variante = variante
    }
}

/// Agarre o nivel de un ejercicio (`VARIANTES_EJ`): el peso y el historial se separan por variante.
public struct VariantesEjercicio: Equatable, Sendable {
    /// "Nivel" o "Agarre".
    public let etiqueta: String
    /// La primera es la default (las filas viejas sin nota cuentan para ella).
    public let opciones: [String]
    /// Solo la rueda: de peso corporal, sin kg.
    public let sinPeso: Bool
}

public enum ReglasEjercicio {
    /// `VARIANTES_EJ`, copiado literal (el orden es la prioridad).
    static let tabla: [(RegexWeb, VariantesEjercicio)] = [
        (RegexWeb(#"rueda\s*abdom|ab\s*wheel|abdominal\s*wheel|rollout|roller\s*abdom"#, i: true),
         VariantesEjercicio(etiqueta: "Nivel", opciones: ["Rodillas flexionadas", "Rodillas extendidas"], sinPeso: true)),
        (RegexWeb(#"(tr(i|í)ceps|pushdown|jal(o|ó)n\s+de\s+tr(i|í)ceps).*(polea|cable)|polea.*tr(i|í)ceps"#, i: true),
         VariantesEjercicio(etiqueta: "Agarre", opciones: ["Barra", "Soga", "Maneral"], sinPeso: false)),
        (RegexWeb(#"jal(o|ó)n\s+(al|a la|de)\s+(pecho|nuca)|pulldown|dorsalera"#, i: true),
         VariantesEjercicio(etiqueta: "Agarre", opciones: ["Prono", "Supino", "Neutro"], sinPeso: false)),
        (RegexWeb(#"remo\s+(en\s+)?(polea|cable|gironda)|gironda"#, i: true),
         VariantesEjercicio(etiqueta: "Agarre", opciones: ["Neutro", "Ancho", "Supino"], sinPeso: false)),
        (RegexWeb(#"curl\s+.*(polea|cable)|polea.*curl"#, i: true),
         VariantesEjercicio(etiqueta: "Agarre", opciones: ["Barra", "Soga"], sinPeso: false)),
    ]
    /// `_SIN_PESO_RE`
    static let sinPesoRE = RegexWeb(#"rueda\s*abdom|ab\s*wheel|rollout|plancha\b|abdominal(es)?\b|crunch|lagartija|flexi(o|ó)n(es)?\s+de\s+brazo|elevaci(o|ó)n(es)?\s+de\s+piernas|mountain\s*climber|hollow"#, i: true)
    /// `_CON_CARGA_RE`: si el nombre menciona equipo o carga externa, lleva kg aunque el gesto sea de peso corporal.
    static let conCargaRE = RegexWeb(#"m(a|á)quina|polea|cable|disco|lastre|mancuerna|barra\b|kettlebell|pesa\b|pesas\b|con\s+peso|con\s+carga|smith|multipower|banco\s+declinado\s+con"#, i: true)
    static let sinTopeRE = RegexWeb(#"amrap|∞|max|máx"#, i: true)
    static let numerosRE = RegexWeb(#"\d+"#)

    /// `getVariantesEntry`
    public static func variantes(_ nombre: String?) -> VariantesEjercicio? {
        let n = nombre ?? ""
        return tabla.first { $0.0.prueba(n) }?.1
    }

    /// `esSinPeso`: la carga externa gana; si no, la rueda o un gesto de peso corporal. El calentamiento va aparte.
    public static func esSinPeso(nombre: String?, tipo: String?) -> Bool {
        if tipo == "calentamiento" { return false }
        let n = nombre ?? ""
        if conCargaRE.prueba(n) { return false }
        return (variantes(n)?.sinPeso ?? false) || sinPesoRE.prueba(n)
    }

    /// `exNoKg` (ENT-13): sin columna de kg (calentamiento o peso corporal).
    public static func sinKg(nombre: String?, tipo: String?) -> Bool {
        tipo == "calentamiento" || esSinPeso(nombre: nombre, tipo: tipo)
    }

    public static func sinKg(_ ex: Ejercicio) -> Bool { sinKg(nombre: ex.nombre, tipo: ex.tipo) }

    /// `_repsSug` (SER-01): el ÚLTIMO número de las reps del plan ("8-10" → 10). nil con AMRAP, ∞ o máx: ahí no hay
    /// registro de un toque.
    public static func repsDelPlan(_ reps: String?) -> Double? {
        guard let reps else { return nil }
        if sinTopeRE.prueba(reps) { return nil }
        guard let ultimo = numerosRE.todas(reps).last else { return nil }
        return JS.parseInt(ultimo, base10: false)
    }
}

public enum CamposSerie {
    static let noDecimal = RegexWeb(#"[^0-9.]"#)
    static let punto = RegexWeb(#"\."#)
    static let noDigito = RegexWeb(#"[^0-9]"#)

    /// `normalizarCampoSerie` (SER-04): en kg la primera coma pasa a punto y queda un solo punto; en reps, solo dígitos.
    public static func normalizar(_ campo: String, _ v: String?) -> String {
        var v = v ?? ""
        if campo == "kg" {
            if let r = v.unicodeScalars.firstIndex(of: ",") {
                var u = v.unicodeScalars
                u.replaceSubrange(r...r, with: ["."])
                v = String(u)
            }
            v = noDecimal.reemplazarTodo(v, por: "")
            if let i = v.firstIndex(of: ".") {
                v = String(v[...i]) + punto.reemplazarTodo(String(v[v.index(after: i)...]), por: "")
            }
            return v
        }
        if campo == "reps" { return noDigito.reemplazarTodo(v, por: "") }
        return v
    }

    /// `rirDeSet` (SER-02): "" → null; "0" → 0 (fue al fallo, no "no lo cargó").
    public static func rir(_ v: String?) -> Double? {
        guard let v, !v.isEmpty else { return nil }
        guard let n = JS.parseInt(v), n.isFinite else { return nil }
        return n
    }

    /// Las leyendas del selector de RIR (0-5).
    public static func leyendaRIR(_ actual: String) -> String {
        let leyendas = ["0": "al fallo", "1": "casi fallo", "2": "1-2 más", "3": "3 más", "4": "4 más", "5": "muy lejos"]
        return actual.isEmpty ? "elegí un valor" : (leyendas[actual] ?? "undefined")
    }
}

/// "📅 Última vez (ayer / hace n días)": la serie tope de la sesión anterior.
public struct UltimaVez: Equatable, Sendable {
    /// "82.5kg × 8 · 3 series"
    public let valor: String
    /// "ayer", "hace 3 días", "la semana pasada" o la fecha ("04-oct").
    public let cuando: String
}

public enum HistorialEntreno {
    /// `fechaLocalDe`: la fecha local (YYYY-MM-DD) de un `registrado_en`. Una serie de las 22:00 en Argentina ya es
    /// "mañana" en UTC: cortar el texto en la T partía una sesión en dos días.
    public static func fechaLocal(_ iso: String?, zona: TimeZone) -> String {
        guard let iso = JS.verdadero(iso) else { return "" }
        guard let d = FechaJS.leer(iso) else { return String(iso.split(separator: "T", omittingEmptySubsequences: false).first ?? "") }
        return FechaJS.ymd(d, zona: zona)
    }

    /// `_ultimaSerieRef`: la MISMA serie en la última sesión del ejercicio, filtrada por variante cuando la tiene (el
    /// sugerido de "Soga" sale del historial de Soga). Las filas viejas sin nota cuentan solo para la opción default.
    /// Devuelve el índice en `h` (que viene del más nuevo al más viejo).
    public static func ultimaSerie(_ h: [RegistroHistorico], indice idx: Int, variante: String?, esDefault: Bool, zona: TimeZone) -> Int? {
        var candidatas = Array(h.indices)
        if let v = JS.verdadero(variante) {
            candidatas = candidatas.filter { JS.iguales(h[$0].notas, v) || (esDefault && h[$0].notas == nil) }
        }
        guard let primera = candidatas.first else { return nil }
        let ultimoDia = fechaLocal(h[primera].registradoEn, zona: zona)
        let delDia = candidatas.filter { fechaLocal(h[$0].registradoEn, zona: zona) == ultimoDia }
        return delDia.first { h[$0].serie == idx + 1 } ?? delDia.first
    }

    /// `suggestedKg`: el kg de la última vez en esta serie. Un 0 no sirve si el ejercicio del plan pide kg (filas viejas
    /// de cuando se trataba como "sin peso").
    public static func kgSugerido(_ h: [RegistroHistorico], indice idx: Int, variante: String?, esDefault: Bool,
                                  sinKgPlan: Bool, zona: TimeZone) -> String {
        guard let i = ultimaSerie(h, indice: idx, variante: variante, esDefault: esDefault, zona: zona), let p = h[i].pesoKg else { return "" }
        if p <= 0 && !sinKgPlan { return "" }
        return JS.texto(p)
    }

    /// `suggestedReps`: las reps de la última vez en esta serie.
    public static func repsSugeridas(_ h: [RegistroHistorico], indice idx: Int, variante: String?, esDefault: Bool, zona: TimeZone) -> String {
        guard let i = ultimaSerie(h, indice: idx, variante: variante, esDefault: esDefault, zona: zona), let r = h[i].reps else { return "" }
        return String(r)
    }

    /// `lastSessionStr` (SER-08): el récord a superar = la serie más pesada de lo traído (48 filas).
    public static func record(_ h: [RegistroHistorico]) -> String? {
        guard let top = masPesada(h) else { return nil }
        // `top.reps_realizadas || top.reps`: con 0 o null cae a `reps`, que la RPC no trae.
        let reps = top.reps.flatMap { $0 != 0 ? String($0) : nil } ?? "undefined"
        let rir = top.rir.map { " · RIR \($0)" } ?? ""
        let variante = JS.verdadero(top.notas).map { " (\($0))" } ?? ""
        return "\(JS.texto(top.pesoKg))kg × \(reps)\(rir)\(variante)"
    }

    /// `_recordKg`: el kg más alto (para la pregunta de "2,5× tu récord").
    public static func recordKg(_ h: [RegistroHistorico]) -> Double {
        h.reduce(0) { max($0, JS.oCero($1.pesoKg)) }
    }

    /// `prevSessionStr`: la sesión anterior (el día más reciente que no es hoy): su serie tope, cuántas series y cuándo.
    public static func ultimaVez(_ h: [RegistroHistorico], ahora: Date, zona: TimeZone) -> UltimaVez? {
        guard !h.isEmpty else { return nil }
        let dia = { (iso: String) -> String in FechaJS.leer(iso).map { FechaJS.ymd($0, zona: zona) } ?? "" }
        let hoy = FechaJS.ymd(ahora, zona: zona)
        let previas = h.filter { dia($0.registradoEn) != hoy }
        guard let primera = previas.first else { return nil }
        let sesion = dia(primera.registradoEn)
        let series = previas.filter { dia($0.registradoEn) == sesion }
        let top = masPesada(series)!
        let cuando: String
        if let a = FechaJS.diaUTC(hoy), let b = FechaJS.diaUTC(sesion) {
            let atras = a - b
            if atras <= 1 { cuando = "ayer" }
            else if atras < 7 { cuando = "hace \(atras) días" }
            else if atras < 14 { cuando = "la semana pasada" }
            else { cuando = FechaJS.leer(primera.registradoEn).map { FechaJS.diaMes($0, zona: zona) } ?? "Invalid Date" }
        } else {
            cuando = FechaJS.leer(primera.registradoEn).map { FechaJS.diaMes($0, zona: zona) } ?? "Invalid Date"
        }
        let reps = top.reps.map(String.init) ?? "undefined"
        let variante = JS.verdadero(top.notas).map { " (\($0))" } ?? ""
        let cuantas = series.count > 1 ? " · \(series.count) series" : ""
        return UltimaVez(valor: "\(JS.texto(top.pesoKg))kg × \(reps)\(variante)\(cuantas)", cuando: cuando)
    }

    /// `h.reduce((a,b) => (b.peso_kg||0) > (a.peso_kg||0) ? b : a, h[0])`: la primera de las más pesadas.
    static func masPesada(_ h: [RegistroHistorico]) -> RegistroHistorico? {
        guard var top = h.first else { return nil }
        for r in h.dropFirst() where JS.oCero(r.pesoKg) > JS.oCero(top.pesoKg) { top = r }
        return top
    }

    /// `kgHeredable` (SER-03): la serie confirmada más cercana hacia atrás con kg > 0; si no hay, la primera de las
    /// otras. Cargás el kg una vez y las siguientes lo arrastran.
    public static func kgHeredable(_ series: [SerieLocal], indice idx: Int) -> String {
        let sirve = { (s: SerieLocal) in s.confirmada && (JS.parseFloat(s.kg) ?? .nan) > 0 }
        var i = idx - 1
        while i >= 0 {
            if i < series.count, sirve(series[i]) { return series[i].kg }
            i -= 1
        }
        for (k, s) in series.enumerated() where k != idx && sirve(s) { return s.kg }
        return ""
    }
}

/// Un texto con una parte en negrita (el `<b>` de la web).
public struct TextoConNegrita: Equatable, Sendable {
    public let antes: String
    public let negrita: String
    public let despues: String
}

/// Cómo se ve una fila de serie (`renderSetRow`).
public struct FilaSerie: Equatable, Sendable {
    public let confirmada: Bool
    /// La primera sin confirmar: la que tiene la pista de un toque.
    public let activa: Bool
    public let placeholderReps: String
    public let placeholderKg: String
    /// Lo que muestra el campo de kg ("" sin columna de kg).
    public let kg: String
    /// Sin columna de kg: el campo es de solo lectura y dice "—".
    public let sinKg: Bool
    /// "RIR" + el valor, o "RIR·" sin cargar.
    public let rir: String
    /// El check habilitado (sin confirmar). Confirmada, el botón es el lápiz.
    public let puedeConfirmar: Bool
    /// "Registrar lo que hiciste" o "Registrar lo sugerido" (nil si ya está confirmada).
    public let tituloConfirmar: String?
    /// "✓ Tocá para registrar lo de la última vez · **80kg × 10** — o editá si hiciste otra cosa"
    public let pista: TextoConNegrita?
    /// "🎯 Primera vez con este ejercicio…" (SER-03): sin historial no hay kg sugerido.
    public let calibracion: String?

    /// `renderSetRow`. `kgUltimaVez` y `repsUltimaVez` salen del historial con el ejercicio DEL PLAN (variante y regla
    /// del 0); `sinKg` es la del ejercicio que se muestra (el sustituto, si hay).
    public static func armar(_ s: SerieLocal, activa: Bool, sinKg: Bool, repsPlan: String?, kgUltimaVez: String,
                             repsUltimaVez: String, kgHeredable: String) -> FilaSerie {
        let repsSug = ReglasEjercicio.repsDelPlan(repsPlan)
        let kgSug = sinKg ? "" : kgUltimaVez
        let repsMostrar = !repsUltimaVez.isEmpty ? repsUltimaVez : (repsSug.map(JS.texto) ?? "")
        let haySugerido = repsSug != nil && (sinKg || !kgSug.isEmpty)
        let tipeo = !s.reps.isEmpty || !s.kg.isEmpty
        let her = sinKg ? "" : kgHeredable
        let puede = tipeo ? (!s.reps.isEmpty && (sinKg || !s.kg.isEmpty || !her.isEmpty)) : haySugerido
        let pista = (!s.confirmada && activa && haySugerido && !tipeo)
            ? TextoConNegrita(antes: "✓ Tocá para registrar lo de la última vez · ", negrita: sinKg ? "\(repsMostrar) reps" : "\(kgSug)kg × \(repsMostrar)",
                              despues: " — o editá si hiciste otra cosa")
            : nil
        let calibracion = (!s.confirmada && activa && !haySugerido && !tipeo && !sinKg && repsSug != nil)
            ? "🎯 Primera vez con este ejercicio: elegí un peso con el que llegues a \(repsPlan ?? "null") reps dejando 1–2 en reserva. Queda de referencia para la próxima."
            : nil
        return FilaSerie(
            confirmada: s.confirmada, activa: activa,
            placeholderReps: !repsUltimaVez.isEmpty ? repsUltimaVez : (repsPlan ?? ""),
            placeholderKg: sinKg ? "—" : (kgSug.isEmpty ? her : kgSug),
            kg: sinKg ? "" : s.kg, sinKg: sinKg,
            rir: "RIR" + (s.rir.isEmpty ? "·" : s.rir),
            puedeConfirmar: s.confirmada ? true : puede,
            tituloConfirmar: s.confirmada ? nil : (tipeo ? "Registrar lo que hiciste" : "Registrar lo sugerido"),
            pista: pista, calibracion: calibracion)
    }
}

public enum ConfirmacionSerie {
    /// Lo que `confirmarSerie` hace con los campos antes de verificar: sin editar es "cumplí lo de la última vez" (reps
    /// de la última vez o el tope del plan, y el kg de la última vez; el RIR NUNCA); sin kg se vacía el kg; con reps y
    /// sin kg se hereda el de una serie confirmada. `lista` es false si faltan datos: la serie queda como quedó (la
    /// web también deja escritas las reps del plan aunque no confirme).
    public static func completar(_ s: SerieLocal, sinKg: Bool, repsPlan: String?, kgUltimaVez: String, repsUltimaVez: String,
                                 kgHeredable: String) -> (serie: SerieLocal, lista: Bool) {
        var s = s
        if s.reps.isEmpty && s.kg.isEmpty {
            let usar = !repsUltimaVez.isEmpty ? repsUltimaVez : (ReglasEjercicio.repsDelPlan(repsPlan).map(JS.texto) ?? "")
            let kg = sinKg ? "" : kgUltimaVez
            if !usar.isEmpty { s.reps = usar }
            if !sinKg && !kg.isEmpty { s.kg = kg }
        }
        if sinKg { s.kg = "" }
        if !sinKg && s.kg.isEmpty && !s.reps.isEmpty && !kgHeredable.isEmpty { s.kg = kgHeredable }
        return (s, !(s.reps.isEmpty || (!sinKg && s.kg.isEmpty)))
    }
}

/// `_serieVerosimil` (SER-05): lo imposible se rechaza; lo raro se pregunta.
public enum Verosimilitud {
    public static let repsMax = 300.0
    public static let kgMax = 2000.0
    public static let kgRaro = 600.0
    public static let saltoKg = 2.5
    public static let saltoReps = 3.0

    public enum Resultado: Equatable, Sendable {
        case ok
        /// "Revisá las repeticiones: 1214": se marca la fila y no se registra.
        case rechazada(String)
        /// "¿Está bien cargado?": registra solo si el cliente dice que sí.
        case preguntar(Pregunta)
    }

    public static func evaluar(reps: String, kg: String, sinKg: Bool, recordKg: Double, repsUltimaVez: String, repsPlan: String?) -> Resultado {
        let r = JS.parseInt(reps) ?? .nan
        let k = sinKg ? 0 : (JS.parseFloat(primeraComaAPunto(kg)) ?? .nan)
        if !(r >= 1) || r > repsMax { return .rechazada("Revisá las repeticiones: \(reps)") }
        if !sinKg && (!(k >= 0) || k > kgMax) { return .rechazada("Revisá el peso: \(kg) kg") }
        var dudas: [String] = []
        if !sinKg && k > kgRaro { dudas.append("\(JS.texto(k)) kg") }
        if !sinKg && recordKg >= 10 && k > recordKg * saltoKg { dudas.append("\(JS.texto(k)) kg (tu récord era \(JS.texto(recordKg)) kg)") }
        let hist = JS.parseInt(repsUltimaVez) ?? .nan
        let ref = hist >= 1 ? hist : JS.oCero(ReglasEjercicio.repsDelPlan(repsPlan))
        if ref >= 5 && r > max(30, ref * saltoReps) { dudas.append("\(JS.texto(r)) repeticiones (venías haciendo \(JS.texto(ref)))") }
        guard !dudas.isEmpty else { return .ok }
        return .preguntar(Pregunta(titulo: "¿Está bien cargado?", cuerpo: "Vas a registrar \(dudas.joined(separator: " y ")). ¿Lo hiciste así?",
                                   confirmar: "Sí, registrar", cancelar: "Corregir"))
    }

    /// `String(x).replace(',', '.')`: solo la primera coma.
    static func primeraComaAPunto(_ s: String) -> String {
        guard let r = s.unicodeScalars.firstIndex(of: ",") else { return s }
        var u = s.unicodeScalars
        u.replaceSubrange(r...r, with: ["."])
        return String(u)
    }
}

/// Lo que viaja en la cola (kinds `carga` y `estado`), con el mismo payload que la web (`writeSet`,
/// `writeExerciseStatus`), que `Escrituras` ya sabe ejecutar.
public enum EscriturasEntreno {
    /// `carga_<dia>_<ex>_<serie>` + la semana: arreglo nativo n.º 1 (en la web, la serie de la semana 5 pisaba en la
    /// cola a la de la semana 4 si las dos estaban pendientes).
    public static func claveCarga(dia: String, ejercicio: String, indice: Int, semana: Int) -> String {
        "carga_\(dia)_\(ejercicio)_\(indice)_s\(semana)"
    }

    /// `estado_<dia>_<ex>` + la semana (mismo arreglo).
    public static func claveEstado(dia: String, ejercicio: String, semana: Int) -> String {
        "estado_\(dia)_\(ejercicio)_s\(semana)"
    }

    /// El nombre que se registra (SER-13): el del sustituto si hay; si no, el que ya tenía la serie (si el "solo hoy"
    /// expiró y se reabre el día, la RPC es upsert y pisaría el nombre); si no, el del plan.
    public static func nombre(sustituto: String?, serie: SerieLocal, plan: String) -> String {
        sustituto ?? JS.verdadero(serie.nombreRegistrado) ?? plan
    }

    /// El payload de `carga`: `{sesionId, diaId, semana, datos{…}}`. Peso con coma → punto y `|| 0`; reps `|| 0`; RIR
    /// "" → null y "0" → 0; notas = la variante de la serie, o la del ejercicio, o null.
    public static func carga(sesionId: String?, dia: String, semana: Int, ejercicio: String, indice: Int, serie s: SerieLocal,
                             nombre: String, varianteEjercicio: String?) -> JSONValue {
        let peso = JS.oCero(JS.parseFloat(Verosimilitud.primeraComaAPunto(s.kg)))
        let reps = JS.oCero(JS.parseInt(s.reps))
        let notas = JS.verdadero(s.varianteRegistrada) ?? JS.verdadero(varianteEjercicio)
        return .objeto([
            "sesionId": JS.verdadero(sesionId).map(JSONValue.texto) ?? .null,
            "diaId": .texto(dia),
            "semana": .numero(Double(semana)),
            "datos": .objeto([
                "diaId": .texto(dia), "ejercicioId": .texto(ejercicio), "ejercicioNombre": .texto(nombre),
                "serie": .numero(Double(indice + 1)), "peso": .numero(peso), "reps": .numero(reps),
                "rir": CamposSerie.rir(s.rir).map(JSONValue.numero) ?? .null,
                "notas": notas.map(JSONValue.texto) ?? .null,
            ]),
        ])
    }

    /// El payload de `estado`: `{sesionId, semana, diaId, exId, seriesObjetivo, status, manual}`.
    public static func estado(sesionId: String?, semana: Int, dia: String, ejercicio: String, seriesObjetivo: Int,
                              status: String, manual: Bool) -> JSONValue {
        .objeto([
            "sesionId": JS.verdadero(sesionId).map(JSONValue.texto) ?? .null, "semana": .numero(Double(semana)),
            "diaId": .texto(dia), "exId": .texto(ejercicio), "seriesObjetivo": .numero(Double(seriesObjetivo)),
            "status": .texto(status), "manual": .bool(manual),
        ])
    }
}

public enum EstadosEjercicio {
    /// Los estados que cuentan como hecho.
    public static let terminales: Set<String> = ["completo", "completo_sin_datos", "saltado"]

    /// `checkIfDayCompleted`: hay ejercicios y todos están en un estado terminal.
    public static func diaCompleto(_ ejercicios: [String], estado: (String) -> String) -> Bool {
        !ejercicios.isEmpty && ejercicios.allSatisfy { terminales.contains(estado($0)) }
    }

    /// El siguiente pendiente después de `id` (ENT-17: al completar uno se abre ese).
    public static func siguientePendiente(_ ejercicios: [String], despuesDe id: String, estado: (String) -> String) -> String? {
        let i = ejercicios.firstIndex(of: id) ?? -1
        return ejercicios.dropFirst(i + 1).first { estado($0) == "pendiente" }
    }
}

/// Series, reps y volumen del día (la card de cierre y los modales de "Cerrar sesión de hoy").
public struct ResumenDia: Equatable, Sendable {
    public let series: Int
    public let reps: Double
    /// Σ reps × kg, sin redondear (la web muestra `Math.round`).
    public let volumen: Double

    public init(_ ejercicios: [EjercicioEnSesion]) {
        var series = 0, reps = 0.0, volumen = 0.0
        for e in ejercicios {
            for s in e.series where s.confirmada {
                series += 1
                // `parseInt(s.reps)||0` sin base y `parseFloat(s.kg)||0`, como la web.
                let r = JS.oCero(JS.parseInt(s.reps, base10: false))
                volumen += r * JS.oCero(JS.parseFloat(s.kg))
                reps += r
            }
        }
        self.series = series; self.reps = reps; self.volumen = volumen
    }

    /// `Math.round(tonnage)`
    public var volumenRedondeado: Double { jsRound(volumen) }

    /// El texto del modal de cierre: "2 series · 18 reps · 1460kg de volumen."
    public var textoCierre: String { "\(series) series · \(JS.texto(reps)) reps · \(JS.texto(volumenRedondeado))kg de volumen." }

    /// El del cierre anticipado: "2 series · 1460kg de volumen · 30 min." (`mins||'—'`: 0 y nil son "—").
    public func textoCierreAnticipado(minutos: Int?) -> String {
        "\(series) series · \(JS.texto(volumenRedondeado))kg de volumen · \(minutos.flatMap { $0 != 0 ? String($0) : nil } ?? "—") min."
    }
}

/// Las fechas como las lee y las escribe la web (`new Date(iso)`, `toLocaleDateString`).
public enum FechaJS {
    /// `new Date(iso)` para lo que manda PostgREST: "2026-10-04T22:32:00+00:00", con fracción de segundo, con Z, con
    /// espacio en vez de T. Una fecha sola es UTC; fecha y hora sin zona, hora local. nil es "Invalid Date".
    public static func leer(_ iso: String) -> Date? {
        let u = Array(iso.utf8)
        var i = 0
        func numero(_ n: Int) -> Int? {
            guard i + n <= u.count else { return nil }
            var v = 0
            for k in i..<(i + n) {
                guard u[k] >= 0x30 && u[k] <= 0x39 else { return nil }
                v = v * 10 + Int(u[k] - 0x30)
            }
            i += n
            return v
        }
        func toma(_ c: UInt8) -> Bool { if i < u.count, u[i] == c { i += 1; return true }; return false }
        guard let y = numero(4), toma(0x2D), let mo = numero(2), toma(0x2D), let d = numero(2) else { return nil }
        var c = DateComponents(year: y, month: mo, day: d)
        guard (1...12).contains(mo), (1...31).contains(d) else { return nil }
        if i == u.count {
            var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
            return cal.date(from: c)
        }
        guard toma(0x54) || toma(0x20), let h = numero(2), toma(0x3A), let mi = numero(2) else { return nil }
        c.hour = h; c.minute = mi; c.second = 0
        var ms = 0.0
        if toma(0x3A) {
            guard let s = numero(2) else { return nil }
            c.second = s
            if toma(0x2E) {   // con punto: V8 no lee "10:00:00,123Z" (Invalid Date)
                var fraccion = ""
                while i < u.count, u[i] >= 0x30 && u[i] <= 0x39 { fraccion.append(Character(UnicodeScalar(u[i]))); i += 1 }
                guard !fraccion.isEmpty else { return nil }
                ms = Double(String((fraccion + "00").prefix(3)))!   // JS se queda con los milisegundos
            }
        }
        // Las 24 valen solo en punto (es el cero del día siguiente): V8 no lee "24:30".
        guard h < 24 || (h == 24 && mi == 0 && (c.second ?? 0) == 0 && ms == 0), mi <= 59, (c.second ?? 0) <= 59 else { return nil }
        // Segundos al este de UTC. V8 acepta de -23:59 a +23:59 con los minutos obligatorios ("+05" es Invalid Date), y
        // `TimeZone(secondsFromGMT:)` da nil pasadas las 18 h: el desfasaje se resta a mano.
        var desfasaje: Int? = nil
        if toma(0x5A) {
            desfasaje = 0
        } else if i < u.count, u[i] == 0x2B || u[i] == 0x2D {
            let signo = u[i] == 0x2B ? 1 : -1
            i += 1
            guard let zh = numero(2) else { return nil }
            _ = toma(0x3A)
            guard let zm = numero(2), zh <= 23, zm <= 59 else { return nil }
            desfasaje = signo * (zh * 3600 + zm * 60)
        }
        guard i == u.count else { return nil }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = desfasaje == nil ? .current : TimeZone(identifier: "UTC")!
        return cal.date(from: c).map { $0.addingTimeInterval(ms / 1000 - Double(desfasaje ?? 0)) }
    }

    /// YYYY-MM-DD local (`toLocaleDateString('en-CA')` y el `dayStr` de `prevSessionStr`).
    public static func ymd(_ d: Date, zona: TimeZone) -> String {
        FechaLocal.hoy(d, zona: zona)
    }

    /// `new Date("YYYY-MM-DD")` en días desde 1970 (UTC): la resta de dos da los días de diferencia.
    static func diaUTC(_ ymd: String) -> Int? {
        let p = ymd.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return nil }
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        guard let d = cal.date(from: DateComponents(year: p[0], month: p[1], day: p[2])) else { return nil }
        return Int((d.timeIntervalSince1970 / 86400).rounded())
    }

    /// `toLocaleDateString('es-AR', {day:'2-digit', month:'short'})`: "04-oct", "05-sept".
    public static func diaMes(_ d: Date, zona: TimeZone) -> String {
        formato("dd-MMM", zona).string(from: d)
    }

    /// `toLocaleTimeString('es-AR', {hour:'2-digit', minute:'2-digit'})`: "06:05 p. m." (JS cambia el U+202F de ICU
    /// por un espacio común).
    public static func horaMinutos(_ d: Date, zona: TimeZone) -> String {
        formato("hh:mm a", zona).string(from: d).replacingOccurrences(of: "\u{202F}", with: " ").replacingOccurrences(of: "\u{A0}", with: " ")
    }

    private static func formato(_ patron: String, _ zona: TimeZone) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_AR")
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = zona
        f.dateFormat = patron
        return f
    }
}
