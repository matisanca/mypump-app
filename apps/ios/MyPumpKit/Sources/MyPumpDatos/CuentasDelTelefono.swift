import Foundation
import MyPumpModelos
import MyPumpReglas

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

    /// Los mapas de reemplazos de comida sin decidir (sin la marca de migrados) de otras carpetas de la misma persona: pasan
    /// a esta sin pisar lo que ya tiene, y la vieja queda marcada para no volver a pasarlos. Devuelve si pasó alguno: la cola
    /// tiene que retener los reemplazos hasta decidir. Sin esto, un reemplazo que estaba solo en la carpeta del link viejo se
    /// perdía al cambiar de link antes de la primera carga con red (revisión adversarial del 15-oct, hallazgo 9).
    static func adoptarSwaps(clienteId: String, en disco: Disco) -> Bool {
        guard !clienteId.isEmpty else { return false }
        let base = disco.carpeta.deletingLastPathComponent()
        let propia = disco.carpeta.lastPathComponent
        let otras = ((try? FileManager.default.contentsOfDirectory(atPath: base.path)) ?? [])
            .filter { $0.hasPrefix("cuenta-") && $0 != propia }
            .sorted()
        var paso = false
        for nombre in otras {
            let otra = Disco(carpeta: base.appendingPathComponent(nombre, isDirectory: true))
            guard Self.clienteId(de: otra) == clienteId else { continue }
            let mapas = ((try? FileManager.default.contentsOfDirectory(atPath: otra.carpeta.path)) ?? [])
                .filter { $0.hasPrefix("swaps_") && $0.hasSuffix(".json") }
            for n in mapas {
                let dieta = String(n.dropFirst("swaps_".count).dropLast(".json".count))
                // Si esta cuenta ya decidió esa dieta, lo de la vieja llega tarde: manda el servidor.
                guard otra.leer(Bool.self, "swaps_migrados_\(dieta)") != true, disco.leer(Bool.self, "swaps_migrados_\(dieta)") != true,
                      let viejos = otra.leer([String: SwapLocal].self, n), !viejos.isEmpty else { continue }
                var propios = disco.leer([String: SwapLocal].self, n) ?? [:]
                let faltan = viejos.filter { propios[$0.key] == nil }
                guard !faltan.isEmpty else { continue }
                propios.merge(faltan) { actual, _ in actual }
                // Primero quedan en esta; recién después la vieja se marca.
                if disco.guardar(propios, n) {
                    paso = true
                    otra.guardar(true, "swaps_migrados_\(dieta)")
                }
            }
        }
        return paso
    }

    /// Lo mismo con las fotos de progreso que no llegaron a subirse (con el token caído quedan guardadas): pasan a la cola
    /// de fotos de esta cuenta y se borran de la vieja recién cuando quedaron en el disco de esta. Devuelve cuántas pasaron.
    @discardableResult
    static func adoptarFotos(clienteId: String, en disco: Disco, fotos: ModeloFotos) async -> Int {
        guard !clienteId.isEmpty else { return 0 }
        let base = disco.carpeta.deletingLastPathComponent()
        let propia = disco.carpeta.lastPathComponent
        let nombres = ((try? FileManager.default.contentsOfDirectory(atPath: base.path)) ?? [])
            .filter { $0.hasPrefix("cuenta-") && $0 != propia }
            .sorted()
        var total = 0
        for nombre in nombres {
            let otra = Disco(carpeta: base.appendingPathComponent(nombre, isDirectory: true))
            guard let viejas = otra.leer([String: FotoPendiente].self, FotoPendiente.archivo), !viejas.isEmpty,
                  Self.clienteId(de: otra) == clienteId else { continue }
            if await fotos.adoptar(viejas) {
                otra.borrar(FotoPendiente.archivo)
                total += viejas.count
            }
        }
        return total
    }
}
