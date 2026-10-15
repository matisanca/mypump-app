import Foundation
import MyPumpModelos

/// Las carpetas de cuenta del teléfono (`Disco`, una por token). Un link que Mati regeneró (`mypump_regenerar_token`) es
/// OTRO token de la MISMA persona: la carpeta nueva arrancaba con la cola vacía y lo que quedó en la vieja (series
/// cargadas sin señal, estacionadas con el token caído hasta "que entre con un link nuevo") no salía nunca (revisión del
/// 15-oct, hallazgo 4). Al entrar, lo de las otras carpetas del MISMO `cliente_id` pasa a la cola de la cuenta.
enum CuentasDelTelefono {
    /// El `cliente_id` de la carpeta, anotado en cada carga con red. Las que no lo tienen (de antes) se reconocen por el
    /// `info` de su copia offline.
    static let archivoCuenta = "cuenta.json"
    /// Los ids de lo que ya se pasó a otra cuenta: no se vuelve a adoptar ni a mandar aunque la cola vieja lo siga
    /// teniendo (una cola de esa cuenta que todavía viva en este proceso puede volver a escribir su archivo).
    static let archivoAdoptadas = "adoptadas.json"

    struct Cuenta: Codable, Equatable {
        var clienteId: String
        enum CodingKeys: String, CodingKey { case clienteId = "cliente_id" }
    }

    static func anotar(clienteId: String, en disco: Disco) {
        guard disco.leer(Cuenta.self, archivoCuenta)?.clienteId != clienteId else { return }
        disco.guardar(Cuenta(clienteId: clienteId), archivoCuenta)
    }

    static func clienteId(de disco: Disco) -> String? {
        if let c = disco.leer(Cuenta.self, archivoCuenta) { return c.clienteId }
        return disco.leer(ModeloApp.CopiaOffline.self, "offline.json")?.info["cliente_id"]?.comoTexto
    }

    /// Pasa a `cola` (la de `disco`) lo pendiente y los fallidos de las otras carpetas de la misma persona, en el orden en
    /// que estaban. Nunca de otro `cliente_id`, ni de una carpeta que no dice de quién es. Devuelve cuántas pendientes
    /// entraron.
    @discardableResult
    static func adoptar(clienteId: String, en disco: Disco, cola: Outbox) async -> Int {
        guard !clienteId.isEmpty else { return 0 }
        let base = disco.carpeta.deletingLastPathComponent()
        let propia = disco.carpeta.lastPathComponent
        let nombres = ((try? FileManager.default.contentsOfDirectory(atPath: base.path)) ?? [])
            .filter { $0.hasPrefix("cuenta-") && $0 != propia }
            .sorted()
        var total = 0
        for nombre in nombres {
            let otra = Disco(carpeta: base.appendingPathComponent(nombre, isDirectory: true))
            guard let vieja = otra.leer(Outbox.Persistido.self, "outbox.json") else { continue }
            let yaAdoptadas = Set(otra.leer([String].self, archivoAdoptadas) ?? [])
            let ops = vieja.ops.filter { !yaAdoptadas.contains($0.id) }
            let fallidos = vieja.fallidos.filter { !yaAdoptadas.contains($0.op.id) }
            guard !ops.isEmpty || !fallidos.isEmpty, Self.clienteId(de: otra) == clienteId else { continue }
            total += await cola.adoptar(ops, fallidos: fallidos).count
            // Primero quedó en la cola de esta cuenta (en disco); recién después se anota en la vieja. Si el proceso muere
            // en el medio, la próxima vez no se duplica: lo que ya está en la cola tiene el mismo id.
            let anotadas = yaAdoptadas.union(ops.map(\.id)).union(fallidos.map(\.op.id))
            otra.guardar(anotadas.sorted(), archivoAdoptadas)
        }
        return total
    }
}
