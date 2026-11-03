import Foundation
import Observation
@preconcurrency import WatchConnectivity
import MyPumpDatos
import MyPumpReloj

/// El Apple Watch del lado del iPhone (tanda 3, 2.2). El iPhone es el único que habla con el servidor: le manda al reloj
/// la rutina del día (`applicationContext`, la última gana, y un mensaje si el reloj está a la vista) cada vez que cambia
/// el motor de Entreno, y recibe los eventos del reloj (iniciar, series, terminar), que aplica el motor por el mismo
/// camino que un toque (a la cola de siempre). Contesta con el acuse para que el reloj los saque de su cola.
///
/// Sin reloj emparejado o sin la app del reloj instalada no manda nada (y mientras el reloj no viaje dentro de la app,
/// `isWatchAppInstalled` es false: el puente queda callado en la tienda).
@MainActor
final class PuenteReloj: NSObject {
    static let compartido = PuenteReloj()

    /// El receptor de la cuenta abierta (sus aplicados viven en el disco de esa cuenta). Va atado a la cuenta, no a la
    /// instancia del motor: un motor nuevo de la misma cuenta (otra rutina, un refresco) sigue con los mismos aplicados.
    private var receptor: (cuenta: String, r: ReceptorReloj)?
    private var envio: Task<Void, Never>?
    /// La última rutina mandada (no se manda dos veces lo mismo).
    private var ultima: RutinaReloj?
    private var sesion: WCSession? { WCSession.isSupported() ? WCSession.default : nil }
    private var motor: ModeloEntreno? { Proveedor.modelo.entreno }

    func activar() {
        guard let s = sesion, s.delegate == nil else { return }
        s.delegate = self
        s.activate()
    }

    private var hayReloj: Bool {
        guard let s = sesion, s.activationState == .activated else { return false }
        return s.isPaired && s.isWatchAppInstalled
    }

    // MARK: - La rutina al reloj

    /// Sigue al motor mientras haya un reloj con la app: un cambio del día (series, estados, sustituciones), de la sesión,
    /// de la rutina o de la cuenta vuelve a mandar la rutina, medio segundo después y juntando los cambios seguidos. El
    /// tick del descanso (4 por segundo) no se sigue: la rutina se arma solo cuando cambia algo que el reloj muestra.
    private var observando = false
    private func observar() {
        guard hayReloj, !observando else { return }
        observando = true
        withObservationTracking {
            if let m = Proveedor.modelo.entreno {
                _ = m.dia
                _ = m.inicioSesion
                _ = m.diasCompletados
                _ = m.rutina
            }
        } onChange: {
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.observando = false
                self.programarEnvio()
                self.observar()
            }
        }
    }

    private func programarEnvio() {
        guard envio == nil else { return }
        envio = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            self?.envio = nil
            self?.mandarRutina()
        }
    }

    func mandarRutina(forzar: Bool = false) {
        guard hayReloj, let s = sesion else { return }
        let ahora = Date().timeIntervalSince1970 * 1000
        let mensaje: MensajeReloj
        if let m = motor {
            let r = m.rutinaReloj()
            var comparable = r
            comparable.generada = ultima?.generada ?? 0
            if !forzar, comparable == ultima { return }
            ultima = r
            mensaje = .rutina(r)
        } else {
            ultima = nil
            mensaje = .sinRutina(motivo: "Abrí Pump Team en el iPhone y entrá con tu link.")
        }
        guard let d = try? ProtocoloReloj.diccionario(SobreReloj(mensaje, enviado: ahora)) else { return }
        try? s.updateApplicationContext(d)
        if s.isReachable { s.sendMessage(d, replyHandler: nil, errorHandler: nil) }
    }

    // MARK: - Lo que llega del reloj

    private func recibir(_ d: [String: Any]) async -> [String: Any] {
        let ahora = Date().timeIntervalSince1970 * 1000
        // Un reloj con otra versión del protocolo: se le contesta la nuestra y deja de reenviar hasta actualizar.
        if let incompatible = ProtocoloReloj.respuestaIncompatible(d, ahora: ahora) { return incompatible }
        guard let sobre = try? ProtocoloReloj.leer(d) else { return [:] }
        switch sobre.mensaje {
        case .pedirRutina:
            mandarRutina(forzar: true)
            return [:]
        case .eventos(let lote):
            // Sin cuenta abierta también se contesta (pendiente, con el motivo): el reloj lo guarda y le dice al alumno qué falta.
            let m = motor
            let r: ReceptorReloj
            if let m {
                if let c = receptor, c.cuenta == m.cuentaReloj { r = c.r } else {
                    r = ReceptorReloj(motor: m)
                    receptor = (m.cuentaReloj, r)
                }
            } else {
                r = ReceptorReloj(disco: nil)
            }
            let acuses = await r.recibir(lote, motor: m)
            mandarRutina()
            guard !acuses.isEmpty, let respuesta = try? ProtocoloReloj.diccionario(SobreReloj(.acuse(acuses), enviado: ahora))
            else { return [:] }
            return respuesta
        case .rutina, .acuse, .sinRutina, .incompatible:
            return [:]
        }
    }

    /// Un acuse que no pudo ir como respuesta (el evento llegó por `transferUserInfo`): por mensaje o, sin el reloj a
    /// la vista, por la vía que el sistema entrega después.
    private func mandar(_ d: [String: Any]) {
        guard !d.isEmpty, let s = sesion, s.activationState == .activated else { return }
        if s.isReachable { s.sendMessage(d, replyHandler: nil, errorHandler: { _ in s.transferUserInfo(d) }) } else { s.transferUserInfo(d) }
    }
}

extension PuenteReloj: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            self.observar()
            self.mandarRutina(forzar: true)
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        // Cambió el reloj emparejado: se reactiva con el nuevo.
        session.activate()
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.observar()
            self.mandarRutina(forzar: true)
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        guard session.isReachable else { return }
        Task { @MainActor in self.mandarRutina(forzar: true) }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        nonisolated(unsafe) let d = message
        nonisolated(unsafe) let responder = replyHandler
        Task { @MainActor in responder(await self.recibir(d)) }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        nonisolated(unsafe) let d = message
        Task { @MainActor in self.mandar(await self.recibir(d)) }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        nonisolated(unsafe) let d = userInfo
        Task { @MainActor in self.mandar(await self.recibir(d)) }
    }
}
