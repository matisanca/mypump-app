import SwiftUI
import UIKit
import UserNotifications
import MyPumpDatos
import MyPumpReglas

/// Notificaciones: la local del domingo (`AvisoDomingo`: llega como un mensaje de Mati y no se configura; id 1002, como
/// la Capacitor: reprogramar la pisa y borra las viejas 1001/1003/1004 que siguen agendadas en los teléfonos que
/// actualizan), el push de los comentarios de Mati (APNs, hex en MAYÚSCULAS) y a dónde lleva tocar cada aviso.
@MainActor @Observable
final class CentroAvisos: NSObject, UNUserNotificationCenterDelegate {
    static let shared = CentroAvisos()

    /// El destino del último aviso tocado; la raíz lo consume y cambia de pestaña (también en un arranque en frío).
    var destino: DestinoAviso?
    /// Cuándo llegó el aviso tocado (nil con un link `?scene=`): `ModeloApp.alLlegarAviso` no relee si la vuelta ya lo hizo.
    var llegadoDestino: Date?
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
    /// Mati, 14-oct). Con la semana de revisión ya completa, el de esta semana se saltea (R2 de la 2.0.3).
    func reprogramar() async {
        let centro = UNUserNotificationCenter.current()
        guard [.authorized, .provisional, .ephemeral].contains(await permiso()) else { return }
        centro.removePendingNotificationRequests(withIdentifiers: [AvisoDomingo.id] + PreferenciasAvisos.idsViejos)
        let completa = Proveedor.modelo.semanaDeRevisionCompleta
        guard let cuando = AvisoDomingo.proximo(desde: Date(), semanaCompleta: completa, dia: Proveedor.modelo.diaDeRevision) else { return }
        let c = UNMutableNotificationContent()
        c.title = AvisoDomingo.titulo
        c.body = AvisoDomingo.cuerpo
        c.sound = .default
        c.userInfo = ["destino": AvisoDomingo.destino]
        let pedido = UNNotificationRequest(identifier: AvisoDomingo.id, content: c,
                                           trigger: UNCalendarNotificationTrigger(dateMatching: cuando, repeats: false))
        try? await centro.add(pedido)
    }

    /// «Pump lleno» con la app en segundo plano (2.3.0): un aviso local ahora mismo, solo si los avisos ya estaban
    /// permitidos (nunca se piden por esto). Tocarlo abre Entreno, donde está el «Pump del día».
    func avisarPumpLleno(meta: Int) async {
        guard [.authorized, .provisional, .ephemeral].contains(await permiso()) else { return }
        let c = UNMutableNotificationContent()
        c.title = PumpDelDia.lleno
        c.body = PumpDelDia.celebracion(meta: meta)
        c.sound = .default
        c.userInfo = ["destino": "train"]
        try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "pump-lleno", content: c, trigger: nil))
    }

    /// Se completó (o se cargó) la semana de revisión: el aviso se vuelve a armar, solo con una cuenta de verdad y si ya
    /// había permiso (nunca lo pide). Así quien sube todo el sábado no recibe nada el domingo.
    func alCambiarLaSemana() async {
        let m = Proveedor.modelo
        guard m.token != nil, !m.esDemo, m.fase == .listo else { return }
        await reprogramar()
    }

    /// Lo que hay agendado del domingo (las pruebas de interfaz lo leen con `-verAvisoDomingo`): "2026-11-08 11:00" o "".
    func avisoDomingoAgendado() async -> String {
        let pedidos = await UNUserNotificationCenter.current().pendingNotificationRequests()
        guard let t = pedidos.first(where: { $0.identifier == AvisoDomingo.id })?.trigger as? UNCalendarNotificationTrigger else { return "" }
        let c = t.dateComponents
        return String(format: "%04d-%02d-%02d %02d:%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0)
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

    // MARK: - Presión: repetición pendiente

    static let idRepetirPresion = "mypump-presion-repetir"

    /// A los 10 minutos de una toma que pide repetición y todavía no se hizo (PROTOCOLO §5.4). Solo con permiso de
    /// notificaciones; nunca lo pide. Se cancela al repetir.
    func programarRepetirPresion(_ cuando: Date) async {
        guard [.authorized, .provisional, .ephemeral].contains(await permiso()), cuando.timeIntervalSinceNow > 1 else { return }
        let c = UNMutableNotificationContent()
        c.title = TextosPresion.N.entrada
        c.body = TextosPresion.T.repetirPendiente
        c.sound = .default
        // Tocarlo abre Presión directo en la repetición pendiente, no la pantalla de inicio de la app.
        c.userInfo = ["destino": "presion"]
        let pedido = UNNotificationRequest(identifier: Self.idRepetirPresion, content: c,
                                           trigger: UNTimeIntervalNotificationTrigger(timeInterval: cuando.timeIntervalSinceNow, repeats: false))
        try? await UNUserNotificationCenter.current().add(pedido)
    }

    func cancelarRepetirPresion() {
        let centro = UNUserNotificationCenter.current()
        centro.removePendingNotificationRequests(withIdentifiers: [Self.idRepetirPresion])
        centro.removeDeliveredNotifications(withIdentifiers: [Self.idRepetirPresion])
    }

    /// Cuándo se pidió el token de APNs en este arranque (nil: todavía no, o se perdió el permiso).
    private var tokenPedido: Date?

    /// Al arrancar con una cuenta y en cada vuelta al frente: si ya hay permiso, reprograma el aviso del domingo (local,
    /// sin red) y pide el token de push. El token se pide una vez por arranque (batería, 2.3.2): antes iba en cada
    /// desbloqueo. Un permiso dado desde Ajustes igual se registra al volver (hallazgo 9), porque sin permiso se olvida
    /// lo pedido; y con la app viva días se pide de nuevo una vez por día (`registrarPush` ya no llama al servidor si el
    /// token y la cuenta son los mismos y no pasó la semana).
    func alEntrar() async {
        guard [.authorized, .provisional, .ephemeral].contains(await permiso()) else { tokenPedido = nil; return }
        await revisarEntregados()
        await reprogramar()
        if let t = tokenPedido, Date().timeIntervalSince(t) < 24 * 3600, Date() >= t { return }
        tokenPedido = Date()
        UIApplication.shared.registerForRemoteNotifications()
    }

    /// Hasta cuándo se miraron los avisos entregados (nil: todavía no; la primera vez viene pegada a la carga completa).
    private var entregadosHasta: Date?

    /// Batería (2.3.2): un push que llegó con la app en el fondo y no se tocó (se abrió desde el ícono) no esperaba los
    /// 90 s de la vuelta. Se mira el centro de notificaciones: solo los push (los locales no traen nada del servidor)
    /// llegados después de la última vuelta. Va antes de que la vuelta mire su espera (`conAvisos`).
    private func revisarEntregados() async {
        let ahora = Date()
        guard let desde = entregadosHasta else { entregadosHasta = ahora; return }
        entregadosHasta = ahora
        let lista = await UNUserNotificationCenter.current().deliveredNotifications().map {
            AvisoEntregado(fecha: $0.date, esPush: $0.request.trigger is UNPushNotificationTrigger,
                           destino: $0.request.content.userInfo["destino"] as? String)
        }
        let nuevos = AvisoEntregado.nuevos(lista, desde: desde)
        if !nuevos.isEmpty { await Proveedor.modelo.alVolverConAvisos(nuevos) }
    }

    /// Un aviso que ya se atendió (llegó con la app a la vista o se tocó) no vuelve a contar en la próxima vuelta.
    private func yaAtendido(_ fecha: Date) {
        if let h = entregadosHasta, h < fecha { entregadosHasta = fecha }
    }

    /// Cambió la cuenta (otro link): el token se vuelve a pedir para registrarlo con la nueva.
    func olvidarTokenPedido() { tokenPedido = nil }

    // MARK: - UNUserNotificationCenterDelegate

    // Las versiones con cierre, no las `async`: con la `async` de `didReceive`, Swift llamaba al cierre de UIKit desde un
    // hilo de fondo y, con la app en segundo plano, tocar un aviso la cerraba (una aserción de UIKit en
    // `_updateSnapshotAndStateRestoration`). Lo encontró la prueba de interfaz que toca el aviso (15-oct).

    /// Con la app abierta también se ve el aviso (como `presentationOptions` de la Capacitor).
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Un push con la app a la vista (un mensaje de Mati, la devolución, un estudio): lo suyo se trae ya. Con el chat
        // cerrado el sondeo de respaldo va cada 150 s (batería, 2.3.2): el número rojo lo pone este push, no la espera.
        // Los avisos locales (descanso, domingo, presión) no traen nada del servidor.
        if notification.request.trigger is UNPushNotificationTrigger {
            let destino = DestinoAviso(destino: notification.request.content.userInfo["destino"] as? String)
            let fecha = notification.date
            Task { @MainActor in
                self.yaAtendido(fecha)
                await Proveedor.modelo.alLlegarAviso(destino, llegado: fecha)
            }
        }
        completionHandler([.banner, .list, .sound])
    }

    /// Tocar un aviso: se anota su destino (la raíz cambia de pestaña) y se avisa a iOS en el hilo principal.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let destino = response.notification.request.content.userInfo["destino"] as? String
        let fecha = response.notification.date
        nonisolated(unsafe) let terminar = completionHandler
        Task { @MainActor in
            self.yaAtendido(fecha)
            self.llegadoDestino = fecha
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
        // `-destinoDePrueba <destino>`: como tocar un aviso con la app cerrada (el destino queda anotado antes de que
        // cargue nada). Las pruebas de interfaz miran a dónde llega sin depender del centro de notificaciones.
        if let d = UserDefaults.standard.string(forKey: "destinoDePrueba") {
            MainActor.assumeIsolated { CentroAvisos.shared.destino = DestinoAviso(destino: d) }
        }
        // `-semanaDePrueba`: la prueba del aviso del domingo necesita el permiso para que haya algo agendado.
        if UserDefaults.standard.string(forKey: "semanaDePrueba") != nil {
            Task { @MainActor in
                _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
                await CentroAvisos.shared.alCambiarLaSemana()
            }
        }
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
