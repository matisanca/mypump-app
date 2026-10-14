import SwiftUI
import UIKit
import UserNotifications
import MyPumpDatos

/// Notificaciones: la local del domingo ("Tu revisión de la semana", id 1002, como la Capacitor: reprogramar la pisa y
/// borra las viejas 1001/1003/1004 que siguen agendadas en los teléfonos que actualizan), el push de los comentarios de
/// Mati (APNs, hex en MAYÚSCULAS) y a dónde lleva tocar cada aviso.
@MainActor @Observable
final class CentroAvisos: NSObject, UNUserNotificationCenterDelegate {
    static let shared = CentroAvisos()

    /// El destino del último aviso tocado; la raíz lo consume y cambia de pestaña (también en un arranque en frío).
    var destino: DestinoAviso?

    func configurar() {
        UNUserNotificationCenter.current().delegate = self
    }

    var preferencias: PreferenciasAvisos {
        get { PreferenciasAvisos.leer(UserDefaults.standard.string(forKey: PreferenciasAvisos.clave)) }
        set { UserDefaults.standard.set(newValue.texto, forKey: PreferenciasAvisos.clave) }
    }

    func permiso() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// `activar`: pide permiso (si ya lo negó, iOS no vuelve a mostrar la hoja: se manda a Ajustes), programa y registra
    /// el push apenas se concede, para no perder un comentario de Mati en la ventana hasta el próximo arranque.
    @discardableResult
    func activar() async -> Bool {
        let centro = UNUserNotificationCenter.current()
        switch await permiso() {
        case .denied: return false
        case .authorized, .provisional, .ephemeral: break
        default:
            let ok = (try? await centro.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
            UserDefaults.standard.set("1", forKey: "mypump_notif_pedido")
            guard ok else { return false }
        }
        await reprogramar()
        UIApplication.shared.registerForRemoteNotifications()
        return true
    }

    /// Al abrir (y al cambiar las preferencias): con permiso, se borra lo nuestro y se vuelve a agendar.
    func reprogramar() async {
        let centro = UNUserNotificationCenter.current()
        guard [.authorized, .provisional, .ephemeral].contains(await permiso()) else { return }
        centro.removePendingNotificationRequests(withIdentifiers: [PreferenciasAvisos.idRevision] + PreferenciasAvisos.idsViejos)
        let p = preferencias
        guard p.check.on else { return }
        let c = UNMutableNotificationContent()
        c.title = "Tu revisión de la semana"
        c.body = "Contale a Mati cómo venís: 1 minuto y ya está."
        c.sound = .default
        c.userInfo = ["destino": "revision"]
        var cuando = DateComponents()
        cuando.weekday = 1          // domingo: es cuando se arma la ronda de Mati
        cuando.hour = p.check.hora
        cuando.minute = p.check.min
        let pedido = UNNotificationRequest(identifier: PreferenciasAvisos.idRevision, content: c,
                                           trigger: UNCalendarNotificationTrigger(dateMatching: cuando, repeats: true))
        try? await centro.add(pedido)
    }

    // MARK: - Fin del descanso (D8)

    static let idDescanso = "mypump-fin-descanso"

    /// Con la app en segundo plano y un descanso corriendo, el aviso de que terminó (la web no lo tenía: el cliente se
    /// quedaba mirando el teléfono). Solo con permiso de notificaciones; nunca lo pide.
    func programarFinDescanso(_ fin: Date) async {
        guard [.authorized, .provisional, .ephemeral].contains(await permiso()), fin.timeIntervalSinceNow > 1 else { return }
        let c = UNMutableNotificationContent()
        c.title = "Terminó el descanso"
        c.body = "Seguí con la próxima serie."
        c.sound = .default
        c.userInfo = ["destino": "train"]
        let pedido = UNNotificationRequest(identifier: Self.idDescanso, content: c,
                                           trigger: UNTimeIntervalNotificationTrigger(timeInterval: fin.timeIntervalSinceNow, repeats: false))
        try? await UNUserNotificationCenter.current().add(pedido)
    }

    func cancelarFinDescanso() {
        let centro = UNUserNotificationCenter.current()
        centro.removePendingNotificationRequests(withIdentifiers: [Self.idDescanso])
        centro.removeDeliveredNotifications(withIdentifiers: [Self.idDescanso])
    }

    /// Al arrancar con una cuenta: si ya hay permiso, reprograma y refresca el token de push.
    func alEntrar() async {
        guard [.authorized, .provisional, .ephemeral].contains(await permiso()) else { return }
        await reprogramar()
        UIApplication.shared.registerForRemoteNotifications()
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Con la app abierta también se ve el aviso (como `presentationOptions` de la Capacitor).
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let destino = response.notification.request.content.userInfo["destino"] as? String
        await MainActor.run { self.destino = DestinoAviso(destino: destino) }
    }
}

/// El delegado de la app: solo lo que SwiftUI no da (el token de APNs).
final class DelegadoApp: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        MainActor.assumeIsolated { CentroAvisos.shared.configurar() }
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        #if DEBUG
        // El token de un build de desarrollo es de sandbox: push.py manda a producción, lo vería muerto y lo daría de baja.
        return
        #else
        let hex = TokenPush.hex(deviceToken)
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        Task { @MainActor in _ = await Proveedor.modelo.registrarPush(dispositivo: hex, version: version) }
        #endif
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {}
}
