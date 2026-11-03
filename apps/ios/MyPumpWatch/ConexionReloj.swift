import Foundation
@preconcurrency import WatchConnectivity
import MyPumpReloj

/// WatchConnectivity del lado del reloj. Con el iPhone a la vista, los eventos salen con `sendMessage` (inmediato) y el
/// iPhone contesta con el acuse; sin el iPhone, una sola vez con `transferUserInfo` (el sistema lo entrega cuando
/// vuelve), y la cola del reloj los reenvía al volver la conexión. La rutina llega como `applicationContext` (la última
/// gana, aunque el reloj estuviera dormido) o como mensaje.
@MainActor
final class ConexionReloj: NSObject {
    var alRecibir: ((MensajeReloj) -> Void)?
    var alCambiarAlcance: ((Bool) -> Void)?
    var alFallarVersion: (() -> Void)?

    /// Los eventos que ya salieron por `transferUserInfo` (no se encolan dos veces en el sistema).
    private var transferidos: Set<UUID> = []
    private var sesion: WCSession? { WCSession.isSupported() ? WCSession.default : nil }

    func activar() {
        guard let s = sesion else { return }
        s.delegate = self
        s.activate()
    }

    /// Manda un mensaje. `alTerminar(false)` = no salió (se reintenta con la cola).
    func enviar(_ m: MensajeReloj, alTerminar: ((Bool) -> Void)?) {
        guard let s = sesion, s.activationState == .activated,
              let d = try? ProtocoloReloj.diccionario(SobreReloj(m, enviado: Date().timeIntervalSince1970 * 1000)) else {
            alTerminar?(false)
            return
        }
        if s.isReachable {
            s.sendMessage(d, replyHandler: { [weak self] respuesta in
                Task { @MainActor in self?.leer(respuesta) }
            }, errorHandler: { _ in
                Task { @MainActor in alTerminar?(false) }
            })
            alTerminar?(true)
            return
        }
        // Sin el iPhone a la vista: los eventos nuevos, una vez, por la vía que el sistema entrega después.
        if case .eventos(let lote) = m {
            let nuevos = lote.filter { !transferidos.contains($0.id) }
            guard !nuevos.isEmpty, let dn = try? ProtocoloReloj.diccionario(SobreReloj(.eventos(nuevos), enviado: Date().timeIntervalSince1970 * 1000)) else {
                alTerminar?(false)
                return
            }
            s.transferUserInfo(dn)
            nuevos.forEach { transferidos.insert($0.id) }
        }
        alTerminar?(false)
    }

    private func leer(_ d: [String: Any]) {
        do {
            alRecibir?(try ProtocoloReloj.leer(d).mensaje)
        } catch .versionNueva, .versionVieja {
            alFallarVersion?()
        } catch {
            // Un mensaje que no se entiende se descarta.
        }
    }
}

extension ConexionReloj: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let alcanzable = session.isReachable
        let contexto = session.receivedApplicationContext
        Task { @MainActor in
            if !contexto.isEmpty { self.leer(contexto) }
            self.alCambiarAlcance?(alcanzable)
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let alcanzable = session.isReachable
        Task { @MainActor in self.alCambiarAlcance?(alcanzable) }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        nonisolated(unsafe) let d = applicationContext
        Task { @MainActor in self.leer(d) }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        nonisolated(unsafe) let d = message
        Task { @MainActor in self.leer(d) }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        nonisolated(unsafe) let d = message
        replyHandler([:])
        Task { @MainActor in self.leer(d) }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        nonisolated(unsafe) let d = userInfo
        Task { @MainActor in self.leer(d) }
    }
}
