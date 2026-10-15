import SwiftUI
import UIKit
import UserNotifications
import MyPumpDatos

/// Notificaciones: la local del domingo (`AvisoDomingo`: llega como un mensaje de Mati y no se configura; id 1002, como
/// la Capacitor: reprogramar la pisa y borra las viejas 1001/1003/1004 que siguen agendadas en los teléfonos que
/// actualizan), el push de los comentarios de Mati (APNs, hex en MAYÚSCULAS) y a dónde lleva tocar cada aviso.
@MainActor @Observable
final class CentroAvisos: NSObject, UNUserNotificationCenterDelegate {
    static let shared = CentroAvisos()

    /// El destino del último aviso tocado; la raíz lo consume y cambia de pestaña (también en un arranque en frío).
    var destino: DestinoAviso?
    /// `?diag=health` en el link (SAL-13, ACC-09): la raíz abre el diagnóstico de Salud. Es la herramienta de soporte de la
    /// web: a quien no puede conectar Salud, Mati le manda ese link.
    var diagnosticoSalud = false

    func configurar() {
        UNUserNotificationCenter.current().delegate = self
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

    /// Al abrir con la cuenta (y al dar el permiso): se borra lo nuestro y se agenda el aviso del domingo que viene, una
    /// sola vez (`AvisoDomingo.proximo`). Sale siempre que haya permiso: no es algo que el cliente configure (pedido de
    /// Mati, 14-oct).
    func reprogramar() async {
        let centro = UNUserNotificationCenter.current()
        guard [.authorized, .provisional, .ephemeral].contains(await permiso()) else { return }
        centro.removePendingNotificationRequests(withIdentifiers: [AvisoDomingo.id] + PreferenciasAvisos.idsViejos)
        guard let cuando = AvisoDomingo.proximo(desde: Date()) else { return }
        let c = UNMutableNotificationContent()
        c.title = AvisoDomingo.titulo
        c.body = AvisoDomingo.cuerpo
        c.sound = .default
        c.userInfo = ["destino": AvisoDomingo.destino]
        let pedido = UNNotificationRequest(identifier: AvisoDomingo.id, content: c,
                                           trigger: UNCalendarNotificationTrigger(dateMatching: cuando, repeats: false))
        try? await centro.add(pedido)
    }

    /// Sin cuenta (salió) o con el link vencido: el aviso del domingo ya no es para este teléfono.
    func cancelarDomingo() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [AvisoDomingo.id] + PreferenciasAvisos.idsViejos)
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

    // Las versiones con cierre, no las `async`: con la `async` de `didReceive`, Swift llamaba al cierre de UIKit desde un
    // hilo de fondo y, con la app en segundo plano, tocar un aviso la cerraba (una aserción de UIKit en
    // `_updateSnapshotAndStateRestoration`). Lo encontró la prueba de interfaz que toca el aviso (15-oct).

    /// Con la app abierta también se ve el aviso (como `presentationOptions` de la Capacitor).
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    /// Tocar un aviso: se anota su destino (la raíz cambia de pestaña) y se avisa a iOS en el hilo principal.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let destino = response.notification.request.content.userInfo["destino"] as? String
        nonisolated(unsafe) let terminar = completionHandler
        Task { @MainActor in
            self.destino = DestinoAviso(destino: destino)
            terminar()
        }
    }

    #if DEBUG
    /// `-avisoDePrueba <destino>` (solo Debug): pide el permiso y agenda, a los 8 s, un aviso como el push de Mati con ese
    /// `destino`. La prueba de interfaz manda la app al fondo, lo toca y mira a dónde llega (NOT-03).
    func agendarAvisoDePrueba(_ destino: String) async {
        let centro = UNUserNotificationCenter.current()
        _ = try? await centro.requestAuthorization(options: [.alert, .sound, .badge])
        let c = UNMutableNotificationContent()
        c.title = "Mati te dejó un mensaje"
        c.body = "Aviso de prueba"
        c.userInfo = ["destino": destino]
        try? await centro.add(UNNotificationRequest(identifier: "aviso-de-prueba", content: c,
                                                    trigger: UNTimeIntervalNotificationTrigger(timeInterval: 8, repeats: false)))
    }
    #endif
}

/// El delegado de la app: solo lo que SwiftUI no da (el token de APNs).
final class DelegadoApp: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        MainActor.assumeIsolated { CentroAvisos.shared.configurar() }
        #if DEBUG
        if let d = UserDefaults.standard.string(forKey: "avisoDePrueba") { Task { await CentroAvisos.shared.agendarAvisoDePrueba(d) } }
        #endif
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
