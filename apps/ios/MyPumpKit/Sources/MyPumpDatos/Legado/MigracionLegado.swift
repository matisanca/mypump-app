import Foundation
import MyPumpModelos
import MyPumpReglas

// La migración del almacenamiento viejo (la app Capacitor, `localStorage` del WebView) a la nativa. Dos fases:
//
// - Fase L, local y sin red, antes de crear el modelo: `planificar` (función pura, este archivo) decide todo a partir
//   de las claves; `EjecutorLegado` lo aplica (token al Keychain, ajustes, archivos de la cuenta, cola).
// - Fase R, con red, después del primer `get_cliente_info`: `FaseRemotaLegado` valida las ops que no traen sesión,
//   reasigna las colas de tokens rotados, deja el recibo y arma la escritura de vuelta.
//
// Idempotente y repetible: el libro mayor anota cada op importada (id = sha256 de su contenido, porque hay formatos
// sin `_id`), y si la huella de los archivos cambia (alguien volvió a la Capacitor) la Fase L corre de nuevo.

// MARK: - Lo que la web guardaba y la nativa todavía no modela (los lee Entreno y Revisión)

/// `legado-entreno.json`, en la carpeta de la cuenta: lo de Entreno que vivía solo en el teléfono, con los campos de la
/// web. Lo lee el modelo de Entreno; la migración solo lo deja.
public struct EntrenoLegado: Codable, Equatable, Sendable {
    /// Por día: `mypump_sesion_<T>_<diaId>` y sus sufijos `_semana`, `_start`, `_finalizada`. Solo las vigentes: sin
    /// cerrar y con el arranque hace menos de `SESION_MAX_H` (6 h). Pasado eso la web descarta la duración, así que
    /// el arranque ya no sirve para nada. Lo demás de la sesión lo manda el servidor.
    public var sesiones: [String: SesionLegada]
    /// `mypump_rest_<T>`: el descanso en curso, si `autoCloseAt` no pasó.
    public var descanso: DescansoLegado?
    /// `mypump_dia_visualizado_<rutinaId>` → `diaId` (también queda en UserDefaults con la clave de la web).
    public var diaVisualizado: [String: String]

    public init(sesiones: [String: SesionLegada] = [:], descanso: DescansoLegado? = nil, diaVisualizado: [String: String] = [:]) {
        self.sesiones = sesiones; self.descanso = descanso; self.diaVisualizado = diaVisualizado
    }

    public static let archivo = "legado-entreno.json"
}

public struct SesionLegada: Codable, Equatable, Sendable {
    /// El valor de `mypump_sesion_<T>_<diaId>` (uuid de `iniciar_sesion`).
    public var sesionId: String?
    /// `_semana`: la semana de la rutina en la que se abrió. La web la tira si no es la actual.
    public var semana: Int?
    /// `_start`: ms desde 1970 (`Date.now()`). La duración se calcula en el teléfono con esto.
    public var start: Double?
    /// `_finalizada === '1'`.
    public var finalizada: Bool

    public init(sesionId: String? = nil, semana: Int? = nil, start: Double? = nil, finalizada: Bool = false) {
        self.sesionId = sesionId; self.semana = semana; self.start = start; self.finalizada = finalizada
    }
}

/// `{endsAt, target, autoCloseAt}`: anclas de reloj en ms (`target` en segundos), como `persistRest`.
public struct DescansoLegado: Codable, Equatable, Sendable {
    public var endsAt: Double
    public var target: Double
    public var autoCloseAt: Double
}

/// `ejercicios-swaps_<rutinaId>.json`: `mypump_exercise_swaps_<RUTINA_ID>` tal cual (`exId` del lugar → sustitución).
/// La poda (las no fijadas valen por su día y su semana) la hace Entreno al cargar, como `pruneExerciseSwaps` en el
/// arranque de la web; acá no hay semana ni días cerrados confiables.
public struct SustitucionEjercicio: Codable, Equatable, Sendable {
    public struct Ejercicio: Codable, Equatable, Sendable {
        public var slug: String?
        public var nombre: String?
        public var equipment: String?
        /// `{eccentric, concentric, _matched_slug}` o null, tal cual.
        public var images: JSONValue?
    }
    public var original: Ejercicio
    public var current: Ejercicio
    /// Una entrada sin `fijado` cuenta como fijada: se eligió cuando el swap era permanente (compat de la web, F5).
    public var fijado: Bool
    public var semana: Int?
    public var diaId: String?

    public static func archivo(rutinaId: String) -> String { "ejercicios-swaps_\(rutinaId).json" }
}

/// `fotos-pendientes.json`: la cola de fotos `mypump_fotoq_<T>` (`"<lunes>|<pose>"` → foto) se guarda con
/// `FotoPendiente` de Fotos.swift, el mismo tipo que usa ModeloFotos para subirlas. Las que estén fuera de la ventana del
/// servidor (−7/+1 días) quedan ahí y se cuentan en el recibo.

/// `mypump_food_swaps_<DIETA>` (el mismo mapa que usa ModeloApp: `swaps_<dieta>.json`) y si la web ya los había subido
/// (`mypump_swaps_migrados_<DIETA>`). Sin la marca, la primera hidratación de la nativa los ancla y los sube por la cola,
/// igual que la web.
public struct SwapsComidaLegado: Equatable, Sendable {
    public var swaps: [String: SwapLocal]
    public var migrados: Bool
}

/// `mypump_offline_<T>`: `{info, rutina, dieta, ts}`, la misma forma que `offline.json` (CopiaOffline de ModeloApp).
public struct CopiaOfflineLegada: Equatable, Sendable {
    public var info: JSONValue
    public var rutina: JSONValue?
    public var dieta: JSONValue?
    public var ts: Double
}

// MARK: - Las colas

/// Una op de la cola vieja, ya con la forma nativa.
public struct OpLegada: Codable, Equatable, Sendable {
    /// sha256(clave + índice + kind + dedupeKey + ts + payload canónico). El índice es el ordinal entre ops IDÉNTICAS
    /// de la misma cola, no la posición: si la Capacitor drena una de adelante, las de atrás no cambian de id.
    public let idLibro: String
    public let operacion: Operacion
    /// `carga` o `estado` sin `sesionId`: antes de mandarla hay que confirmar que su día sigue en la rutina activa.
    public let necesitaValidar: Bool
}

/// Lo que dejó una cuenta (un token) para mandar: su cola de escrituras y su cola de fotos.
public struct ColaLegada: Equatable, Sendable {
    public enum Tipo: String, Codable, Sendable {
        /// La cuenta que queda en el Keychain.
        case vigente
        /// `mypump_outbox_anon`: sin token (la demo, o antes de pegar el link). Nunca se ejecuta.
        case anon
        /// Un token rotado: se estaciona y en la Fase R se reasigna solo si resuelve al mismo `cliente_id`.
        case otroToken
    }
    public var clave: String
    public var tipo: Tipo
    public var token: String?
    public var ops: [OpLegada]
    /// Entradas que no son una op (sin `kind`): la web las descarta igual. Quedan en la copia cruda.
    public var ilegibles: Int
    /// El valor entero no era JSON: no se importa nada y la clave no se toca.
    public var valorIlegible: Bool
    /// La de la clave entera, para borrarla en la escritura de vuelta solo si no cambió.
    public var firma: FirmaValor?
    public var fotos: [String: FotoPendiente]
    /// `rutina.id` de la foto offline de ESE token: contra qué rutina se cargaron las ops sin sesión.
    public var rutinaFoto: String?
}

// MARK: - Contexto y plan

/// Lo que ya hay del lado nativo y lo que dejó la corrida anterior: hace falta para no pisar lo que la nativa ya tiene.
public struct ContextoMigracion: Equatable, Sendable {
    public var tokenNativo: String?
    /// `mypump_token_invalido` de la nativa (ModeloApp lo anota cuando la base dice que el link ya no sirve).
    public var tokenInvalidoNativo: String?
    /// nil = primera corrida.
    public var anterior: CorridaAnterior?

    public init(tokenNativo: String? = nil, tokenInvalidoNativo: String? = nil, anterior: CorridaAnterior? = nil) {
        self.tokenNativo = tokenNativo; self.tokenInvalidoNativo = tokenInvalidoNativo; self.anterior = anterior
    }
}

/// Lo mínimo de la corrida anterior para saber qué cambió desde entonces. Sin tokens ni valores: solo hashes.
public struct CorridaAnterior: Codable, Equatable, Sendable {
    /// sha256(clave) → sha256(valor).
    public var huellasClaves: [String: String]
    /// sha256 del `mypump_token` legado que se leyó.
    public var tokenLegado: String?

    public init(huellasClaves: [String: String] = [:], tokenLegado: String? = nil) {
        self.huellasClaves = huellasClaves; self.tokenLegado = tokenLegado
    }
}

/// Todo lo que hay que hacer, tipado. Lo produce `MigracionLegado.planificar` sin tocar nada.
public struct PlanMigracion: Equatable, Sendable {
    // Acceso
    /// `mypump_token` con forma válida y que no es el marcado como inválido (ni del lado web ni del nativo).
    public var tokenLegado: String?
    /// Había un `mypump_token` pero no se usa (marcado inválido o con forma rara).
    public var tokenDescartado = false
    /// La cuenta que queda después de migrar: la nativa, o la legada si no había o si la Capacitor cambió de link
    /// después de la última migración.
    public var tokenVigente: String?
    /// Escribir `tokenVigente` en el Keychain.
    public var adoptarToken = false

    /// Ajustes nativos, con la misma clave que la web (UserDefaults). En una repetición, solo los que cambiaron.
    public var preferencias: [String: String] = [:]

    // De la cuenta vigente
    public var entreno: EntrenoLegado?
    public var copiaOffline: CopiaOfflineLegada?
    /// rutinaId → exId → sustitución (sin las `_demo`).
    public var sustituciones: [String: [String: SustitucionEjercicio]] = [:]
    /// dietaId → swaps (sin las `_demo`).
    public var swapsComida: [String: SwapsComidaLegado] = [:]

    public var colas: [ColaLegada] = []

    // Escritura de vuelta
    /// `mypump_sesion_*`: cachés que la Capacitor usaría vencidos si alguien vuelve a ella. Se borran.
    public var sesionesParaBorrar: [String: FirmaValor] = [:]
    /// `mypump_nativa_marca` tal como estaba (la deja la escritura de vuelta; leerla confirma que llegó al disco).
    public var marcaLeida: String?

    // Repetición y recibo
    public var huellasClaves: [String: String] = [:]
    public var tokenLegadoHash: String?
    public var conteos = ConteosLegado()
}

/// Conteos para el recibo, sin contenido crudo ni claves con token.
public struct ConteosLegado: Codable, Equatable, Sendable {
    public var claves = 0
    public var unidadesUTF16 = 0
    public var opsPorKind: [String: Int] = [:]
    public var opsPorCola: [String: Int] = [:]
    public var opsSinSesion = 0
    public var opsIlegibles = 0
    public var colasIlegibles = 0
    public var fotos = 0
    public var fotosFueraDeVentana = 0
    public var sustituciones = 0
    public var swapsComida = 0
    public var sesionesVigentes = 0
    public var sesionesVencidas = 0
    public var descansoVigente = false
    public var preferencias = 0
    /// Claves de la demo (`*_demo`) o sin cuenta (token vacío): nunca se aplican.
    public var demo = 0
    public var ignoradas = 0
    public var desconocidas = 0

    public init() {}
}

// MARK: - Fase L, la parte pura

public enum MigracionLegado {
    /// `SESION_MAX_H` de la web.
    static let sesionMaxima: Double = 6 * 3600 * 1000

    /// Claves de salud que se pasan tal cual (las lee el sincronizador nativo). `mypump_health_diag` no: es un
    /// diagnóstico de la Capacitor.
    static let clavesSalud: Set<String> = [
        "mypump_health_connected", "mypump_health_denegado", "mypump_health_racha_vacia", "mypump_health_backfill_v1",
        "mypump_health_backfill_off", "mypump_health_backfill_intento", "mypump_health_historial_ok", "mypump_health_last_sync",
    ]

    /// Cachés y registros que la nativa rehace por su cuenta.
    static let clavesIgnoradas: Set<String> = [
        "mypump_health_diag", "mypump_push_token", "mypump_push_web_endpoint", "mypump_ejercicio_catalogo_v1",
        "mypump_a2hs_v1", "mypump_dl_pospuesto", "mypump_reload_online",
    ]

    public static let claveMarca = "mypump_nativa_marca"

    /// La Fase L sin tocar nada: de las claves del `localStorage` viejo a todo lo que hay que hacer.
    public static func planificar(_ items: [String: String], firmas: [String: FirmaValor] = [:], ahora: Date,
                                  zona: TimeZone = .current, contexto: ContextoMigracion = ContextoMigracion()) -> PlanMigracion {
        var plan = PlanMigracion()
        let ms = ahora.timeIntervalSince1970 * 1000
        let primera = contexto.anterior == nil
        var huellas: [String: String] = [:]
        for (k, v) in items { huellas[JSONLegado.sha256(k)] = JSONLegado.sha256(v) }
        plan.huellasClaves = huellas
        /// En una repetición, lo que no cambió ya se aplicó (y la nativa pudo haberlo cambiado después): no se pisa.
        func cambio(_ k: String) -> Bool {
            guard let ant = contexto.anterior else { return true }
            return ant.huellasClaves[JSONLegado.sha256(k)] != huellas[JSONLegado.sha256(k)]
        }
        var c = ConteosLegado()
        c.claves = items.count
        c.unidadesUTF16 = items.values.reduce(0) { $0 + $1.utf16.count }

        // 1. Acceso: el token legado, respetando los marcados como inválidos.
        let invalidoWeb = items["mypump_token_invalido"]
        if let t = items["mypump_token"] {
            if FormatoToken.valido(t), t != invalidoWeb, t != contexto.tokenInvalidoNativo {
                plan.tokenLegado = t
            } else {
                plan.tokenDescartado = true
            }
        }
        plan.tokenLegadoHash = plan.tokenLegado.map(JSONLegado.sha256)
        switch (contexto.tokenNativo, plan.tokenLegado) {
        case (nil, let l):
            plan.tokenVigente = l
            plan.adoptarToken = l != nil
        case (let k?, let l?) where l != k && !primera && plan.tokenLegadoHash != contexto.anterior?.tokenLegado:
            // La Capacitor cambió de link DESPUÉS de la última migración: es lo último que hizo el cliente.
            plan.tokenVigente = l
            plan.adoptarToken = true
        case (let k?, _):
            plan.tokenVigente = k
        }
        let vigente = plan.tokenVigente

        // 2. Clasificar todas las claves.
        // Por token; las que no tienen token (`anon`, o un sufijo que no es un token) van cada una aparte.
        var colas: [String: ColaLegada] = [:]
        func cola(_ token: String, clave: String) -> ColaLegada {
            if let c = colas[token.isEmpty ? clave : token] { return c }
            let tipo: ColaLegada.Tipo = token.isEmpty ? .anon : (token == vigente ? .vigente : .otroToken)
            return ColaLegada(clave: token.isEmpty ? clave : "mypump_outbox_\(token)", tipo: tipo, token: token.isEmpty ? nil : token,
                              ops: [], ilegibles: 0, valorIlegible: false, firma: nil, fotos: [:], rutinaFoto: nil)
        }
        func tokenDe(_ s: String) -> String { FormatoToken.valido(s) ? s : "" }
        var sesiones: [String: SesionLegada] = [:]
        var sesionCambio: Set<String> = []
        var entreno = EntrenoLegado()
        var entrenoCambio = false

        for k in items.keys.sorted() {
            let v = items[k] ?? ""
            if k == "mypump_token" || k == claveMarca { continue }
            if clavesIgnoradas.contains(k) { c.ignoradas += 1; continue }

            if let t = sufijo(k, "mypump_outbox_") {
                let token = t == "anon" ? "" : tokenDe(t)
                var q = cola(token, clave: k)
                q.clave = k
                q.firma = firmas[k]
                if let lista = JSONLegado.parsear(v), case .lista(let entradas) = lista {
                    let (ops, ilegibles) = leerOps(entradas, clave: k)
                    q.ops = ops
                    q.ilegibles = ilegibles
                } else {
                    q.valorIlegible = true
                    c.colasIlegibles += 1
                }
                colas[token.isEmpty ? k : token] = q
            } else if let t = sufijo(k, "mypump_fotoq_") {
                let token = tokenDe(t)
                guard !token.isEmpty else { c.demo += 1; continue }
                var q = cola(token, clave: k)
                q.fotos = leerFotos(v)
                colas[token] = q
            } else if let t = sufijo(k, "mypump_offline_") {
                let token = tokenDe(t)
                guard !token.isEmpty else { c.demo += 1; continue }
                let copia = leerCopiaOffline(v)
                if let id = JSONLegado.texto(copia?.rutina?["id"]) {
                    var q = cola(token, clave: k)
                    q.rutinaFoto = id
                    colas[token] = q
                }
                if token == vigente, let copia, cambio(k) { plan.copiaOffline = copia }
            } else if let t = sufijo(k, "mypump_rest_") {
                guard let vigente, t == vigente else { if tokenDe(t).isEmpty { c.demo += 1 }; continue }
                if let d = leerDescanso(v), d.autoCloseAt > ms {
                    c.descansoVigente = true
                    if cambio(k) { entreno.descanso = d; entrenoCambio = true }
                }
            } else if k.hasPrefix("mypump_sesion_") {
                plan.sesionesParaBorrar[k] = firmas[k] ?? FirmaValor.de(Array(v.utf16))
                guard let vigente, let resto = sufijo(k, "mypump_sesion_\(vigente)_"), !resto.isEmpty else { continue }
                var dia = resto
                var s: SesionLegada
                if let d = sinFinal(resto, "_semana") {
                    dia = d; s = sesiones[dia] ?? SesionLegada(); s.semana = Int(v.trimmingCharacters(in: .whitespaces))
                } else if let d = sinFinal(resto, "_start") {
                    dia = d; s = sesiones[dia] ?? SesionLegada(); s.start = Double(v.trimmingCharacters(in: .whitespaces))
                } else if let d = sinFinal(resto, "_finalizada") {
                    dia = d; s = sesiones[dia] ?? SesionLegada(); s.finalizada = v == "1"
                } else {
                    s = sesiones[dia] ?? SesionLegada(); s.sesionId = v
                }
                sesiones[dia] = s
                if cambio(k) { sesionCambio.insert(dia) }
            } else if let r = sufijo(k, "mypump_exercise_swaps_") {
                guard r != "demo", nombreSeguro(r) else { c.demo += 1; continue }
                let s = leerSustituciones(v)
                c.sustituciones += s.count
                if !s.isEmpty, cambio(k) { plan.sustituciones[r] = s }
            } else if let d = sufijo(k, "mypump_food_swaps_") {
                guard d != "demo", nombreSeguro(d) else { c.demo += 1; continue }
                let swaps = leerSwapsComida(v)
                c.swapsComida += swaps.count
                let migrados = items["mypump_swaps_migrados_\(d)"] == "1"
                if !swaps.isEmpty || migrados { plan.swapsComida[d] = SwapsComidaLegado(swaps: swaps, migrados: migrados) }
            } else if let d = sufijo(k, "mypump_swaps_migrados_") {
                guard d != "demo", nombreSeguro(d) else { c.demo += 1; continue }
                if v == "1", items["mypump_food_swaps_\(d)"] == nil { plan.swapsComida[d] = SwapsComidaLegado(swaps: [:], migrados: true) }
            } else if let r = sufijo(k, "mypump_dia_visualizado_") {
                guard r != "demo", !v.isEmpty else { c.demo += 1; continue }
                c.preferencias += 1
                if cambio(k) {
                    plan.preferencias[k] = v
                    entreno.diaVisualizado[r] = v
                    entrenoCambio = true
                }
            } else if let p = preferencia(k, v) {
                c.preferencias += 1
                if cambio(k) { plan.preferencias[k] = p }
            } else if k == "mypump-theme" || k == "mypump_tipo_dia" || k == "mypump_notif_prefs" || k == "mypump_notif_pedido"
                        || k == "mypump_onboarding_v1" || k == "mypump_token_invalido" || clavesSalud.contains(k) {
                c.ignoradas += 1   // una preferencia conocida con un valor que no es una elección (tema 'light', etc.)
            } else {
                c.desconocidas += 1
            }
        }

        // 3. Sesiones vigentes de la cuenta.
        for (dia, s) in sesiones {
            let vigenteSesion = !s.finalizada && s.start.map { ms - $0 >= 0 && ms - $0 <= sesionMaxima } == true
            if vigenteSesion {
                c.sesionesVigentes += 1
                if sesionCambio.contains(dia) { entreno.sesiones[dia] = s; entrenoCambio = true }
            } else {
                c.sesionesVencidas += 1
            }
        }
        if entrenoCambio { plan.entreno = entreno }

        // 4. Colas: orden estable (vigente, otras, anon) y conteos.
        let hoy = FechaLegado.dia(ms, zona: zona)
        let ventana = (FechaLegado.sumar(hoy, -7, zona: zona), FechaLegado.sumar(hoy, 1, zona: zona))
        plan.colas = colas.values.sorted { orden($0) < orden($1) || (orden($0) == orden($1) && $0.clave < $1.clave) }
        for q in plan.colas {
            c.opsPorCola[q.tipo.rawValue, default: 0] += q.ops.count
            c.opsIlegibles += q.ilegibles
            for op in q.ops {
                c.opsPorKind[op.operacion.kind, default: 0] += 1
                if op.necesitaValidar { c.opsSinSesion += 1 }
            }
            c.fotos += q.fotos.count
            c.fotosFueraDeVentana += q.fotos.values.filter { $0.fecha < ventana.0 || $0.fecha > ventana.1 }.count
            if q.tipo == .anon { c.demo += 1 }
        }
        plan.marcaLeida = items[claveMarca]
        plan.conteos = c
        return plan
    }

    private static func orden(_ q: ColaLegada) -> Int {
        switch q.tipo { case .vigente: return 0; case .otroToken: return 1; case .anon: return 2 }
    }

    /// Ajustes que pasan tal cual, con la regla de cada uno. nil = no es una de estas claves o el valor no es una elección.
    static func preferencia(_ k: String, _ v: String) -> String? {
        switch k {
        case "mypump-theme":
            // theme.js escribe 'light' en CADA carga (`apply(stored || 'light')`): solo 'dark' es una elección.
            return v == "dark" ? v : nil
        case "mypump_tipo_dia":
            return v.isEmpty ? nil : v
        case "mypump_notif_prefs":
            if case .objeto? = JSONLegado.parsear(v) { return v }
            return nil
        case "mypump_notif_pedido", "mypump_onboarding_v1":
            return v == "1" ? v : nil
        case "mypump_token_invalido":
            return FormatoToken.valido(v) ? v : nil
        default:
            return clavesSalud.contains(k) && !v.isEmpty ? v : nil
        }
    }

    /// Las entradas de una cola, en orden. Las que no tienen `kind` no son ops (la web las descarta igual).
    static func leerOps(_ entradas: [JSONValue], clave: String) -> ([OpLegada], Int) {
        var ops: [OpLegada] = []
        var ilegibles = 0
        var vistas: [String: Int] = [:]
        for e in entradas {
            guard case .objeto(let o) = e, case .texto(let kind)? = o["kind"], !kind.isEmpty else { ilegibles += 1; continue }
            let payload = o["payload"] ?? .null
            let dedupe = o["dedupeKey"]?.comoTexto
            let ts = JSONLegado.numero(o["ts"]) ?? 0
            let tries = max(0, Int(JSONLegado.numero(o["tries"]) ?? 0))
            let contenido = JSONLegado.canonico(.lista([.texto(clave), .texto(kind), dedupe.map(JSONValue.texto) ?? .null,
                                                        .numero(ts), payload]))
            let indice = vistas[contenido, default: 0]
            vistas[contenido] = indice + 1
            let id = JSONLegado.sha256(JSONLegado.canonico(.lista([.texto(clave), .numero(Double(indice)), .texto(kind),
                                                                    dedupe.map(JSONValue.texto) ?? .null, .numero(ts), payload])))
            let op = Operacion(id: "legado-\(id.prefix(32))", kind: kind, payload: payload, dedupeKey: dedupe, tries: tries, ts: ts)
            let sinSesion = (kind == "carga" || kind == "estado") && (payload["sesionId"]?.comoTexto ?? "").isEmpty
            ops.append(OpLegada(idLibro: id, operacion: op, necesitaValidar: sinSesion))
        }
        return (ops, ilegibles)
    }

    static func leerFotos(_ v: String) -> [String: FotoPendiente] {
        guard case .objeto(let o)? = JSONLegado.parsear(v) else { return [:] }
        var fotos: [String: FotoPendiente] = [:]
        for (k, x) in o {
            // Sin dataUrl la web la borra de la cola sin intentar (`if (!item || !item.dataUrl)`).
            guard let dataUrl = x["dataUrl"]?.comoTexto, !dataUrl.isEmpty else { continue }
            let partes = k.split(separator: "|", maxSplits: 1).map(String.init)
            fotos[k] = FotoPendiente(pose: x["pose"]?.comoTexto ?? (partes.count == 2 ? partes[1] : ""),
                                     fecha: x["fecha"]?.comoTexto ?? partes.first ?? "",
                                     dataUrl: dataUrl, intentos: Int(JSONLegado.numero(x["intentos"]) ?? 0))
        }
        return fotos
    }

    /// La web solo usa la foto si trae `info` y `rutina` (`snap && snap.info && snap.rutina`).
    static func leerCopiaOffline(_ v: String) -> CopiaOfflineLegada? {
        guard let j = JSONLegado.parsear(v), case .objeto? = j["info"], case .objeto? = j["rutina"] else { return nil }
        return CopiaOfflineLegada(info: j["info"] ?? .null, rutina: j["rutina"], dieta: j["dieta"].flatMap { $0 == .null ? nil : $0 },
                                  ts: JSONLegado.numero(j["ts"]) ?? 0)
    }

    /// `restoreRest` exige `autoCloseAt`.
    static func leerDescanso(_ v: String) -> DescansoLegado? {
        guard let j = JSONLegado.parsear(v), let cierre = JSONLegado.numero(j["autoCloseAt"]), cierre > 0 else { return nil }
        return DescansoLegado(endsAt: JSONLegado.numero(j["endsAt"]) ?? cierre, target: JSONLegado.numero(j["target"]) ?? 0, autoCloseAt: cierre)
    }

    static func leerSustituciones(_ v: String) -> [String: SustitucionEjercicio] {
        guard case .objeto(let o)? = JSONLegado.parsear(v) else { return [:] }
        func ejercicio(_ e: JSONValue?) -> SustitucionEjercicio.Ejercicio {
            SustitucionEjercicio.Ejercicio(slug: JSONLegado.texto(e?["slug"]), nombre: JSONLegado.texto(e?["nombre"]),
                                           equipment: JSONLegado.texto(e?["equipment"]), images: e?["images"])
        }
        var r: [String: SustitucionEjercicio] = [:]
        for (exId, s) in o {
            guard case .objeto(let campos) = s, case .objeto? = campos["current"] else { continue }
            // Compat F5: `fijado === undefined` → fijado. Ojo: `null` no es undefined (la web lo deja como no fijado).
            let fijado = campos.keys.contains("fijado") ? JSONLegado.verdadero(campos["fijado"]) : true
            r[exId] = SustitucionEjercicio(original: ejercicio(campos["original"]), current: ejercicio(campos["current"]), fijado: fijado,
                                           semana: JSONLegado.numero(campos["semana"]).map { Int($0) },
                                           diaId: JSONLegado.texto(campos["diaId"]))
        }
        return r
    }

    static func leerSwapsComida(_ v: String) -> [String: SwapLocal] {
        guard case .objeto(let o)? = JSONLegado.parsear(v) else { return [:] }
        var r: [String: SwapLocal] = [:]
        for (k, s) in o {
            guard case .objeto(let campos) = s else { continue }
            r[k] = SwapLocal(original: campos["original"].flatMap { $0 == .null ? nil : $0 }, current: campos["current"] ?? .null)
        }
        return r
    }

    static func sufijo(_ k: String, _ prefijo: String) -> String? {
        k.hasPrefix(prefijo) ? String(k.dropFirst(prefijo.count)) : nil
    }

    static func sinFinal(_ k: String, _ final: String) -> String? {
        guard k.hasSuffix(final), k.count > final.count else { return nil }
        return String(k.dropLast(final.count))
    }

    /// Un id que va a parar a un nombre de archivo.
    static func nombreSeguro(_ s: String) -> Bool {
        !s.isEmpty && s.count <= 80 && s.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
    }
}

/// Fechas `YYYY-MM-DD` locales, gregoriano y `en_US_POSIX`, como `hoyLocal()` de la web.
enum FechaLegado {
    static func calendario(_ zona: TimeZone) -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = zona
        c.locale = Locale(identifier: "en_US_POSIX")
        return c
    }

    static func dia(_ ms: Double, zona: TimeZone) -> String {
        let c = calendario(zona).dateComponents([.year, .month, .day], from: Date(timeIntervalSince1970: ms / 1000))
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static func sumar(_ dia: String, _ n: Int, zona: TimeZone) -> String {
        let p = dia.split(separator: "-").compactMap { Int($0) }
        let cal = calendario(zona)
        guard p.count == 3, let d = cal.date(from: DateComponents(year: p[0], month: p[1], day: p[2], hour: 12)),
              let r = cal.date(byAdding: .day, value: n, to: d) else { return dia }
        return Self.dia(r.timeIntervalSince1970 * 1000, zona: zona)
    }
}
