import Foundation
import MyPumpModelos

/// SER-14: las sustituciones de ejercicio también en el servidor (`supabase/migrations/nativa_003_sustituciones_ejercicio.sql`),
/// para que pasen de un teléfono a otro y no se pierdan al reinstalar. El archivo de cada rutina sigue siendo la copia de
/// trabajo, como antes; el servidor es la referencia cuando contesta.
///
/// - Cada cambio sale por la cola (`swap_ej` / `swap_ej_del`, con la misma clave: gana el último).
/// - La primera vez que un teléfono sincroniza una rutina SUBE lo que tenía guardado (`mypump_import_exercise_swaps`): lo
///   de antes de la tabla o lo que trajo la migración. De ahí en más, LEE el servidor y lo pone por encima.
/// - Sin la migración en la base (PGRST202), sin red o con el token caído: todo sigue como antes, solo en el teléfono.
public enum SustitucionesServidor {
    public static let kindGuardar = "swap_ej"
    public static let kindBorrar = "swap_ej_del"
    /// Lo mismo que acepta la base (`mypump_sustitucion_valida`), con margen en el tamaño: la base cuenta el texto con
    /// espacios después de `:` y `,`.
    static let maxClave = 120
    static let maxTexto = 12_000
    static let maxPorRutina = 300

    public static func clave(rutinaId: String, exId: String) -> String { "swap_ej_\(rutinaId)_\(exId)" }

    /// Lo último que ya está en la cola. Si la app se cierra entre escribir el archivo de la rutina y encolar, al volver a
    /// abrir se encola la diferencia (si no, la primera lectura del servidor borraría lo que nunca le llegó).
    public static func archivoEncoladas(rutinaId: String) -> String { "ejercicios-swaps-encoladas_\(rutinaId).json" }

    /// Lo que se recuerda en el teléfono sobre la sincronización de una rutina.
    public struct Estado: Codable, Equatable, Sendable {
        /// Lo de este teléfono ya se subió una vez: de ahí en más se lee el servidor.
        public var subidas: Bool
        /// La migración del almacenamiento viejo se repitió (el cliente volvió a la app vieja): lo que trajo es lo último
        /// que hizo y, en la próxima sincronización, reemplaza a lo del servidor.
        public var reemplazar: Bool

        public init(subidas: Bool, reemplazar: Bool = false) { self.subidas = subidas; self.reemplazar = reemplazar }

        public static func archivo(rutinaId: String) -> String { "ejercicios-swaps-sync_\(rutinaId).json" }
    }

    /// Lo que el servidor acepta. Lo que no (nunca pasó con datos reales), queda solo en el teléfono.
    static func subible(_ exId: String, _ v: JSONValue) -> Bool {
        guard case .objeto = v, (1...maxClave).contains(exId.count),
              let datos = try? JSONEncoder().encode(v) else { return false }
        return datos.count <= maxTexto
    }

    /// Lo que sube la primera sincronización. Si pasa del tope de la base, no sube nada (quedan en el teléfono, como antes).
    public static func subibles(_ m: [String: JSONValue]) -> [String: JSONValue]? {
        let r = m.filter { subible($0.key, $0.value) }
        return r.count <= maxPorRutina ? r : nil
    }

    public struct Op: Equatable, Sendable {
        public let kind: String
        public let payload: JSONValue
        public let clave: String
        public let exId: String
    }

    /// Las ops para pasar de `antes` a `ahora`, en un orden fijo (las claves ordenadas).
    public static func operaciones(antes: [String: JSONValue], ahora: [String: JSONValue], rutinaId: String) -> [Op] {
        var ops: [Op] = []
        for exId in Set(antes.keys).union(ahora.keys).sorted() {
            let base: [String: JSONValue] = ["rutinaId": .texto(rutinaId), "exId": .texto(exId)]
            switch (antes[exId], ahora[exId]) {
            case (let a, let n?) where a != n:
                guard subible(exId, n) else { continue }
                var p = base
                p["swap"] = n
                ops.append(Op(kind: kindGuardar, payload: .objeto(p), clave: clave(rutinaId: rutinaId, exId: exId), exId: exId))
            case (_?, nil):
                ops.append(Op(kind: kindBorrar, payload: .objeto(base), clave: clave(rutinaId: rutinaId, exId: exId), exId: exId))
            default:
                continue
            }
        }
        return ops
    }

    /// El mapa que queda después de leer el servidor: lo del servidor, con lo que todavía está en la cola por encima (es
    /// más nuevo), lo que se tocó mientras se esperaba la respuesta (la respuesta puede no traerlo) y lo que el servidor
    /// no acepta (nunca se subió: si no, se perdería).
    public static func combinar(servidor: [String: JSONValue], local: [String: JSONValue], pendientes: [String: Operacion],
                                rutinaId: String, tocadas: Set<String>) -> [String: JSONValue] {
        var r = servidor.filter { if case .objeto = $0.value { return true } else { return false } }
        let prefijo = "swap_ej_\(rutinaId)_"
        for (k, op) in pendientes where k.hasPrefix(prefijo) {
            guard let exId = op.payload["exId"]?.comoTexto else { continue }
            switch op.kind {
            case kindGuardar: if let s = op.payload["swap"] { r[exId] = s }
            case kindBorrar: r[exId] = nil
            default: continue
            }
        }
        for exId in tocadas { r[exId] = local[exId] }
        for (exId, v) in local where !subible(exId, v) { r[exId] = v }
        return r
    }
}
