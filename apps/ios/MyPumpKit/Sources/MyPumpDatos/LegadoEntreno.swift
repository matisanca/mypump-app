import Foundation
import MyPumpModelos
import MyPumpReglas

/// Lo que la app vieja (la Capacitor) dejó del Entreno en curso, como lo lee la migración del almacenamiento viejo
/// (MIG-02): la sesión de cada día (`mypump_sesion_<TOKEN>_<dia>{,_semana,_finalizada,_start}`), el descanso que estaba
/// corriendo (`mypump_rest_<TOKEN>`), el último día que se vio (`mypump_dia_visualizado_<RUTINA>`) y las sustituciones
/// de la rutina (`mypump_exercise_swaps_<RUTINA>`). El formato del archivo lo termina de fijar la migración: acá hay un
/// lector tolerante y un punto de entrada, `ModeloEntreno.aplicarLegado`.
public struct LegadoEntreno: Sendable, Equatable {
    public struct SesionDia: Sendable, Equatable {
        public var diaId: String
        public var sesionId: String?
        public var semana: Int?
        /// `_start` (ms desde 1970).
        public var inicio: Double?
        /// `_finalizada === '1'`
        public var finalizada: Bool

        public init(diaId: String, sesionId: String? = nil, semana: Int? = nil, inicio: Double? = nil, finalizada: Bool = false) {
            self.diaId = diaId; self.sesionId = sesionId; self.semana = semana; self.inicio = inicio; self.finalizada = finalizada
        }
    }

    public var sesiones: [SesionDia]
    public var descanso: Descanso.Guardado?
    public var diaVisualizado: String?
    /// En el formato de la web (`exId → {original, current, fijado, semana, diaId}`).
    public var sustituciones: [String: JSONValue]?

    public init(sesiones: [SesionDia] = [], descanso: Descanso.Guardado? = nil, diaVisualizado: String? = nil, sustituciones: [String: JSONValue]? = nil) {
        self.sesiones = sesiones; self.descanso = descanso; self.diaVisualizado = diaVisualizado; self.sustituciones = sustituciones
    }

    public var vacio: Bool { sesiones.isEmpty && descanso == nil && diaVisualizado == nil && (sustituciones ?? [:]).isEmpty }

    /// Las claves crudas del localStorage viejo (clave → valor, como las leen la Ruta A y la B).
    public static func desdeAlmacenamiento(_ claves: [String: String], token: String, rutinaId: String) -> LegadoEntreno {
        var l = LegadoEntreno()
        var porDia: [String: SesionDia] = [:]
        let prefijo = "mypump_sesion_\(token)_"
        for (k, v) in claves where k.hasPrefix(prefijo) {
            var dia = String(k.dropFirst(prefijo.count))
            var campo = ""
            for sufijo in ["_semana", "_start", "_finalizada"] where dia.hasSuffix(sufijo) {
                campo = sufijo
                dia = String(dia.dropLast(sufijo.count))
            }
            guard !dia.isEmpty else { continue }
            var s = porDia[dia] ?? SesionDia(diaId: dia)
            switch campo {
            case "_semana": s.semana = JS.parseInt(v).flatMap { $0.isFinite && abs($0) < 1e15 ? Int($0) : nil }
            case "_start": s.inicio = JS.parseInt(v).flatMap { $0 > 0 ? $0 : nil }
            case "_finalizada": s.finalizada = v == "1"
            default: s.sesionId = JS.verdadero(v)
            }
            porDia[dia] = s
        }
        l.sesiones = porDia.values.sorted { $0.diaId < $1.diaId }
        if let r = claves["mypump_rest_\(token)"], let d = r.data(using: .utf8) {
            l.descanso = try? JSONDecoder().decode(Descanso.Guardado.self, from: d)
        }
        l.diaVisualizado = JS.verdadero(claves["mypump_dia_visualizado_\(rutinaId)"])
        if let s = claves["mypump_exercise_swaps_\(rutinaId)"], let d = s.data(using: .utf8),
           case .objeto(let o)? = try? JSONDecoder().decode(JSONValue.self, from: d) {
            l.sustituciones = o
        }
        return l
    }

    /// `legado-entreno.json` del disco de la cuenta. Lo escribe la migración (`EntrenoLegado`): `{"sesiones": {"d1":
    /// {"sesionId", "semana", "start", "finalizada"}}, "descanso": {"endsAt", "target", "autoCloseAt"}, "diaVisualizado":
    /// {"<rutinaId>": "d1"}}`. También acepta las claves crudas (`{"mypump_sesion_…": "…", …}` o `{"claves": {…}}`), y
    /// `"dias"` en vez de `"sesiones"`, `_semana`/`_start`/`inicio`/`_finalizada` y `diaVisualizado` como texto.
    /// Hasta el 14-oct solo leía esa otra forma: la sesión en curso y el día que se veía se perdían al migrar.
    public static func leer(_ disco: Disco, token: String, rutinaId: String) -> LegadoEntreno? {
        guard let v = disco.leer(JSONValue.self, ModeloEntreno.Archivo.legado), case .objeto(let o) = v else { return nil }
        func textos(_ o: [String: JSONValue]) -> [String: String] {
            o.compactMapValues { x in
                switch x {
                case .texto(let s): return s
                case .numero(let d): return JS.texto(d)
                case .bool(let b): return b ? "1" : nil
                case .objeto, .lista: return (try? JSONEncoder().encode(x)).flatMap { String(data: $0, encoding: .utf8) }
                case .null: return nil
                }
            }
        }
        if case .objeto(let c)? = o["claves"] { return desdeAlmacenamiento(textos(c), token: token, rutinaId: rutinaId) }
        if o.keys.contains(where: { $0.hasPrefix("mypump_") }) { return desdeAlmacenamiento(textos(o), token: token, rutinaId: rutinaId) }
        var l = LegadoEntreno()
        if case .objeto(let dias)? = o["sesiones"] ?? o["dias"] {
            for (dia, x) in dias {
                guard case .objeto(let d) = x else { continue }
                let numero = { (k: String) -> Double? in
                    switch d[k] {
                    case .numero(let n)?: return n
                    case .texto(let s)?: return JS.parseInt(s)
                    default: return nil
                    }
                }
                let fin = d["_finalizada"] ?? d["finalizada"]
                l.sesiones.append(SesionDia(
                    diaId: dia, sesionId: (d["sesionId"] ?? d["_sesionId"])?.comoTexto,
                    semana: (numero("_semana") ?? numero("semana")).flatMap { $0.isFinite && abs($0) < 1e15 ? Int($0) : nil },
                    inicio: (numero("start") ?? numero("_start") ?? numero("inicio")).flatMap { $0 > 0 ? $0 : nil },
                    finalizada: fin == .bool(true) || fin == .texto("1") || fin == .numero(1)))
            }
            l.sesiones.sort { $0.diaId < $1.diaId }
        }
        if let d = o["descanso"] { l.descanso = try? JSONDecoder().decode(Descanso.Guardado.self, from: JSONEncoder().encode(d)) }
        // La migración lo guarda por rutina (`mypump_dia_visualizado_<rutinaId>`): vale solo el de la rutina activa.
        if case .objeto(let porRutina)? = o["diaVisualizado"] { l.diaVisualizado = porRutina[rutinaId]?.comoTexto }
        else { l.diaVisualizado = o["diaVisualizado"]?.comoTexto }
        if case .objeto(let s)? = o["sustituciones"] { l.sustituciones = s }
        return l
    }
}

extension ModeloEntreno {
    /// Lo del almacenamiento viejo, SIN pisar lo que la nativa ya sabe: la sesión de un día solo si no tiene una
    /// local; el descanso solo si no hay uno; el día que se veía, solo si este teléfono todavía no eligió; las
    /// sustituciones solo si no hay ninguna. La sesión se CONFIRMA con el servidor al restaurar (SES-02): una vieja que
    /// el servidor ya archivó se descarta, sin sesiones fantasma. Se puede llamar antes o después de `cargar()`.
    public func aplicarLegado(_ l: LegadoEntreno) async {
        var huboSesion = false
        for s in l.sesiones where sesionesLocales[s.diaId] == nil && (s.sesionId != nil || s.inicio != nil) {
            sesionesLocales[s.diaId] = SesionLocal(sesionId: JS.verdadero(s.sesionId), semana: s.semana, finalizada: s.finalizada, inicio: s.inicio)
            huboSesion = huboSesion || s.diaId == dia.dia.id
        }
        guardarSesiones()
        if let s = l.sustituciones, !s.isEmpty, dia.sustituciones.isEmpty {
            dia.sustituciones = SustitucionesEntreno.compat(s)
            guardarSustituciones()
            podarSustituciones()
        }
        // Primero el día y después el descanso, como la web al abrir: arranca en el último día visto y recién ahí
        // `restoreRest()`. Cambiar de día detiene el descanso (`cambiarDia` → `stopRest()`), así que al revés el
        // descanso que venía corriendo se perdía.
        var cambioDeDia = false
        if !habiaDiaGuardado, let d = JS.verdadero(l.diaVisualizado), d != dia.dia.id, dias.contains(where: { $0.id == d }) {
            habiaDiaGuardado = true
            await cambiarDia(d)
            cambioDeDia = true
        }
        if descanso.descanso == nil && descanso.guardado == nil, let g = l.descanso {
            descanso = BarraDescanso(guardado: g)
            descanso.restaurar(ahora: ahoraMs)
            guardarDescanso()
        }
        if !cambioDeDia && huboSesion && dia.sesionId == nil { await restaurarSesion() }
    }

    /// Lee `legado-entreno.json` del disco de la cuenta, lo aplica y lo borra (para no aplicarlo dos veces).
    @discardableResult
    public func aplicarLegadoDelDisco() async -> Bool {
        guard let disco, let token, let l = LegadoEntreno.leer(disco, token: token, rutinaId: rutina.id) else { return false }
        await aplicarLegado(l)
        disco.borrar(Archivo.legado)
        return true
    }
}
