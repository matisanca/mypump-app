import Foundation
import MyPumpModelos

/// SER-14: las sustituciones de ejercicio también en el servidor (`supabase/migrations/nativa_003_sustituciones_ejercicio.sql`),
/// para que pasen de un teléfono a otro y no se pierdan al reinstalar. El archivo de cada rutina sigue siendo la copia de
/// trabajo, como antes; el servidor la respalda y la comparte.
///
/// - Cada entrada lleva `_ts`: cuándo la eligió el cliente (lo de la app vieja no tiene y cuenta como 0, lo más viejo).
///   En el servidor y al leerlo gana lo más nuevo; borrar deja una lápida con la hora de lo que se borró, que no revive
///   con algo más viejo ni saca algo más nuevo. El servidor recorta las horas del futuro (relojes adelantados).
/// - Cada cambio del cliente sale por la cola (`swap_ej` / `swap_ej_del`, con la misma clave: gana el último). La cola no
///   muestra avisos por estas: la sustitución ya quedó en el teléfono.
/// - Al leer el servidor, que algo falte allá NO es que se borró: lo del teléfono se vuelve a subir (por ejemplo, la primera
///   vez, o si la tabla se vaciara). Solo una lápida más nueva lo saca.
/// - La poda (las no fijadas valen por su día y su semana) es solo del teléfono y no se manda: un teléfono viejo no puede
///   borrar lo que el cliente fijó después en otro.
/// - Sin la migración en la base (PGRST202), sin red o con el token caído: todo sigue como antes, solo en el teléfono.
public enum SustitucionesServidor {
    public static let kindGuardar = "swap_ej"
    public static let kindBorrar = "swap_ej_del"
    /// Lo mismo que acepta la base (`mypump_sustitucion_valida`), con margen en el tamaño: la base cuenta el texto con
    /// espacios después de `:` y `,`.
    static let maxClave = 120
    static let maxTexto = 12_000
    static let maxTs = 9_000_000_000_000_000.0
    /// Lo que el servidor deja pasar hacia el futuro (`mypump_sustitucion_tope`): 5 minutos.
    static let margenFuturo = 300_000.0

    public static func clave(rutinaId: String, exId: String) -> String { "swap_ej_\(rutinaId)_\(exId)" }

    /// Lo último que ya está en la cola o en el servidor. Si la app se cierra entre escribir el archivo de la rutina y
    /// encolar, al volver a abrir se encola la diferencia.
    public static func archivoEncoladas(rutinaId: String) -> String { "ejercicios-swaps-encoladas_\(rutinaId).json" }

    /// Lo que se leyó de la app vieja en la última corrida de la migración: la base para saber qué cambió ahí si el
    /// cliente vuelve a usarla (`volverDeLaAppVieja`).
    public static func archivoLegado(rutinaId: String) -> String { "ejercicios-swaps-legado_\(rutinaId).json" }

    /// `_ts` de una entrada (0 si no tiene: la app vieja, o de antes de SER-14).
    public static func ts(_ v: JSONValue?) -> Double {
        if case .objeto(let o)? = v, case .numero(let n)? = o["_ts"], n.isFinite, n >= 0 { return n }
        return 0
    }

    /// La entrada sin su hora: para ver si dos son la misma elección.
    public static func sinHora(_ v: JSONValue?) -> JSONValue? {
        guard case .objeto(var o)? = v else { return v }
        o["_ts"] = nil
        return .objeto(o)
    }

    /// La hora de un cambio que reemplaza a `actual`: la de ahora, pero nunca menos que la de lo que reemplaza + 1 (si el
    /// reloj de este teléfono, o el del que la eligió, iba adelantado, el cambio nuevo igual tiene que ganar).
    /// `piso`: la hora más alta que ya tuvo esa clave (por ejemplo, la de lo que se acaba de deshacer): la elección nueva
    /// tiene que superarla, si no el servidor la ignora contra la lápida.
    public static func horaDeUnCambio(_ ahora: Double, reemplaza actual: JSONValue?, piso: Double = 0) -> Double {
        max(ahora.rounded(.down), ts(actual) + 1, piso + 1)
    }

    /// La entrada con su hora.
    public static func conHora(_ v: JSONValue, _ ms: Double) -> JSONValue {
        guard case .objeto(var o) = v else { return v }
        o["_ts"] = .numero(ms.rounded(.down))
        return .objeto(o)
    }

    /// Lo que el servidor acepta. Lo que no (nunca pasó con datos reales), queda solo en el teléfono. La clave se cuenta
    /// como la base (`length` de Postgres: puntos de código, no grafemas).
    static func subible(_ exId: String, _ v: JSONValue) -> Bool {
        guard case .objeto(let o) = v, (1...maxClave).contains(exId.unicodeScalars.count),
              let datos = try? JSONEncoder().encode(v), datos.count <= maxTexto else { return false }
        switch o["_ts"] {
        case nil: return true
        case .numero(let n)?: return n.isFinite && n >= 0 && n <= maxTs
        default: return false
        }
    }

    public struct Op: Equatable, Sendable {
        public let kind: String
        public let payload: JSONValue
        public let clave: String
        public let exId: String
    }

    /// Las ops para pasar de `antes` a `ahora`, en un orden fijo (las claves ordenadas). Un borrado lleva la hora de lo que
    /// se borra (lo que el cliente veía): así nunca borra en el servidor algo más nuevo que no vio.
    public static func operaciones(antes: [String: JSONValue], ahora: [String: JSONValue], rutinaId: String) -> [Op] {
        var ops: [Op] = []
        for exId in Set(antes.keys).union(ahora.keys).sorted() {
            var p: [String: JSONValue] = ["rutinaId": .texto(rutinaId), "exId": .texto(exId)]
            switch (antes[exId], ahora[exId]) {
            case (let a, let n?) where a != n:
                guard subible(exId, n) else { continue }
                p["swap"] = n
                ops.append(Op(kind: kindGuardar, payload: .objeto(p), clave: clave(rutinaId: rutinaId, exId: exId), exId: exId))
            case (let a?, nil):
                p["ts"] = .numero(ts(a).rounded(.down))
                ops.append(Op(kind: kindBorrar, payload: .objeto(p), clave: clave(rutinaId: rutinaId, exId: exId), exId: exId))
            default:
                continue
            }
        }
        return ops
    }

    /// Lo que contestó `mypump_get_exercise_swaps`: `{"vivas": {exId: entrada}, "borradas": {exId: ms}, "ahora": ms}`.
    /// nil si no es eso.
    public static func leer(_ r: JSONValue) -> (vivas: [String: JSONValue], borradas: [String: Double], ahora: Double?)? {
        guard case .objeto(let o) = r, case .objeto(let v)? = o["vivas"] else { return nil }
        var b: [String: Double] = [:]
        if case .objeto(let bo)? = o["borradas"] {
            for (k, x) in bo { if case .numero(let n) = x { b[k] = n } }
        }
        var ahora: Double?
        if case .numero(let n)? = o["ahora"], n.isFinite, n > 0 { ahora = n }
        return (v.filter { if case .objeto = $0.value { return true } else { return false } }, b, ahora)
    }

    /// El mapa del teléfono después de leer el servidor, clave por clave:
    /// - lo que se tocó mientras se esperaba la respuesta, lo que estaba en la cola al empezar y lo que quedó en fallidos:
    ///   queda lo del teléfono (es más nuevo, o nunca llegó);
    /// - lo que sigue en la cola: se pinta encima;
    /// - si no: la del servidor si es tan nueva como la del teléfono; una lápida más nueva la saca; y lo que el servidor
    ///   no tiene (o tiene más viejo) queda, para volver a subirlo.
    /// Lo que el servidor no acepta (nunca se sube) queda siempre.
    ///
    /// Con `ahora` (la hora del servidor), lo del teléfono estampado más allá de lo que el servidor deja (un reloj
    /// adelantado) no le gana a lo que diga el servidor: si no, volvía a subirse y pisaba lo que el cliente hizo después en
    /// otro teléfono.
    public static func combinar(vivas: [String: JSONValue], borradas: [String: Double], local: [String: JSONValue],
                                pendientes: [String: Operacion], rutinaId: String, tocadas: Set<String>,
                                ahora: Double? = nil) -> [String: JSONValue] {
        func tsLocal(_ l: JSONValue) -> Double {
            let t = ts(l)
            if let ahora, t > ahora + margenFuturo { return -1 }
            return t
        }
        var r: [String: JSONValue] = [:]
        let vivas = vivas.filter { if case .objeto = $0.value { return true } else { return false } }
        let prefijo = "swap_ej_\(rutinaId)_"
        var enCola: [String: Operacion] = [:]
        for (k, op) in pendientes where k.hasPrefix(prefijo) {
            if let exId = op.payload["exId"]?.comoTexto { enCola[exId] = op }
        }
        for exId in Set(vivas.keys).union(borradas.keys).union(local.keys).union(enCola.keys) {
            let l = local[exId]
            if tocadas.contains(exId) {
                r[exId] = l
            } else if let op = enCola[exId] {
                r[exId] = op.kind == kindGuardar ? op.payload["swap"] : nil
            } else if let v = vivas[exId], let l, sinHora(v) == sinHora(l) {
                // La misma elección con otra hora (el servidor recortó una del futuro): queda la del servidor.
                r[exId] = v
            } else if let v = vivas[exId], l == nil || ts(v) >= tsLocal(l!) {
                r[exId] = v
            } else if let b = borradas[exId], let l, b >= tsLocal(l) {
                r[exId] = nil
            } else {
                r[exId] = l
            }
        }
        for (exId, v) in local where !subible(exId, v) { r[exId] = v }
        return r
    }

    /// La vuelta a la app vieja (la migración del almacenamiento viejo que se repite): solo lo que el cliente cambió AHÍ
    /// desde la corrida anterior (`base`, lo que se leyó entonces) pisa lo del teléfono, con la hora de ahora para que gane
    /// también en el servidor; lo que sacó ahí se saca. Lo demás (lo que se hizo en la nativa o llegó de otro teléfono)
    /// queda. Sin `base` (una corrida anterior a SER-14), todo lo de la app vieja cuenta como cambiado y nada se saca.
    public static func volverDeLaAppVieja(nativa: [String: JSONValue], legado: [String: JSONValue], base: [String: JSONValue]?,
                                          ms: Double) -> [String: JSONValue] {
        var r = nativa
        for (exId, v) in legado where base?[exId] != v { r[exId] = conHora(v, horaDeUnCambio(ms, reemplaza: nativa[exId])) }
        for exId in (base ?? [:]).keys where legado[exId] == nil { r[exId] = nil }
        return r
    }
}
