import Foundation
import MyPumpModelos
import MyPumpReglas

// MARK: - Recibo en el servidor

/// El recibo va a `mypump_registrar_migracion_nativa` (`nativa_001`) y queda SIEMPRE también en el disco: lo que el
/// servidor no confirma (la RPC todavía no existe, sin red, token caído) se reintenta en el próximo arranque con
/// `reenviar`. Lo confirmado pasa a `recibos/enviados/` y lo que el servidor rechazó (tope del cliente, recibo mal
/// formado) a `recibos/rechazados/`, para no insistir.
public struct ReciboEnServidor: ReciboMigracion {
    public let cliente: ClienteRPC
    public let carpeta: URL

    public init(cliente: ClienteRPC, carpeta: URL) {
        self.cliente = cliente
        self.carpeta = carpeta
    }

    public func enviar(_ recibo: ReciboLegado, token: String) async -> EntregaRecibo {
        let local = await ReciboEnDisco(carpeta: carpeta).enviar(recibo, token: token)
        switch await Self.mandar(recibo, token: token, cliente: cliente) {
        case .confirmado:
            Self.archivar(carpeta: carpeta, corrida: recibo.corrida, en: "enviados")
            return .confirmado
        case .rechazado:
            Self.archivar(carpeta: carpeta, corrida: recibo.corrida, en: "rechazados")
            return local
        case .reintentar:
            return local
        }
    }

    enum Respuesta: Equatable { case confirmado, rechazado, reintentar }

    static func mandar(_ recibo: ReciboLegado, token: String, cliente: ClienteRPC) async -> Respuesta {
        guard let datos = try? JSONEncoder().encode(recibo), let json = try? JSONDecoder().decode(JSONValue.self, from: datos) else {
            return .rechazado
        }
        let r = await cliente.llamar("mypump_registrar_migracion_nativa", [
            "p_token": .texto(token), "p_migracion": .texto(recibo.migracion), "p_corrida": .numero(Double(recibo.corrida)),
            "p_recibo": json,
        ])
        switch r {
        case .success(.bool(true)): return .confirmado
        case .success(.bool(false)): return .rechazado          // tope del cliente, o el uuid es de otra cuenta
        case .success: return .reintentar                       // null: token caído
        case .failure(let e) where e.funcionInexistente: return .reintentar   // la nativa_001 todavía no está aplicada
        case .failure(let e) where e.clase == .permanente: return .rechazado  // mal formado (22023): no se insiste
        case .failure: return .reintentar                       // red o servicio caído
        }
    }

    static func archivar(carpeta: URL, corrida: Int, en subcarpeta: String) {
        let fm = FileManager.default
        let nombre = "recibo-\(corrida).json"
        let destino = carpeta.appendingPathComponent(subcarpeta).appendingPathComponent(nombre)
        try? fm.createDirectory(at: destino.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? fm.removeItem(at: destino)
        try? fm.moveItem(at: carpeta.appendingPathComponent(nombre), to: destino)
    }

    /// Los recibos que quedaron solo en el disco, de nuevo al servidor (los de otra cuenta se dejan). Corta en el primero
    /// que no se pudo preguntar: sin red o sin la RPC, los demás tampoco van a entrar. Devuelve cuántos confirmó.
    public static func reenviar(carpeta: URL, token: String, clienteId: String, cliente: ClienteRPC) async -> Int {
        guard let nombres = try? FileManager.default.contentsOfDirectory(atPath: carpeta.path) else { return 0 }
        var confirmados = 0
        for nombre in nombres.sorted() where nombre.hasPrefix("recibo-") && nombre.hasSuffix(".json") {
            guard let datos = try? Data(contentsOf: carpeta.appendingPathComponent(nombre)),
                  let recibo = try? JSONDecoder().decode(ReciboLegado.self, from: datos),
                  recibo.cliente == clienteId else { continue }
            switch await mandar(recibo, token: token, cliente: cliente) {
            case .confirmado:
                archivar(carpeta: carpeta, corrida: recibo.corrida, en: "enviados")
                confirmados += 1
            case .rechazado:
                archivar(carpeta: carpeta, corrida: recibo.corrida, en: "rechazados")
            case .reintentar:
                return confirmados
            }
        }
        return confirmados
    }

    /// ¿Queda algún recibo sin confirmar en el disco? (Para no esperar una carga con red si no hay nada que mandar.)
    public static func hayPendientes(carpeta: URL) -> Bool {
        let nombres = (try? FileManager.default.contentsOfDirectory(atPath: carpeta.path)) ?? []
        return nombres.contains { $0.hasPrefix("recibo-") && $0.hasSuffix(".json") }
    }
}

// MARK: - Conteos del servidor

/// `mypump_conteos_cliente`: filas por tabla del cliente, antes y después de mandar lo importado. nil si la RPC todavía
/// no existe, si no hubo red o si el token cayó (el recibo va igual, sin conteos del servidor).
public struct ConteosRPC: ConteosServidor {
    public let cliente: ClienteRPC

    public init(cliente: ClienteRPC) { self.cliente = cliente }

    public func contar(token: String) async -> [String: Int]? {
        guard case .success(.objeto(let o)) = await cliente.llamar("mypump_conteos_cliente", ["p_token": .texto(token)]) else {
            return nil
        }
        return o.compactMapValues { $0.comoNumero.map(\.enteroTruncado) }
    }
}
