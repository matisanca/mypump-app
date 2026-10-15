import Foundation
import MyPumpDatos
import MyPumpReglas
import UIKit

/// El modelo de la app, uno solo para todas las pantallas. Mientras las demás pestañas sigan siendo bocetos con
/// `Muestras`, Dieta ya usa este (datos reales).
@MainActor
enum Proveedor {
    static let modelo: ModeloApp = {
        let m = crear()
        // Al volver al frente con la cuenta: el domingo al día y el token de push (un permiso dado desde Ajustes se
        // registra ahí, no en el próximo arranque; hallazgo 9).
        m.conAvisos = { await CentroAvisos.shared.alEntrar() }
        return m
    }()

    private static func crear() -> ModeloApp {
        #if DEBUG
        let d = UserDefaults.standard
        // `-sinOnboarding YES`: las capturas y las pruebas de interfaz no esperan la hoja de permisos;
        // `-reiniciarOnboarding YES` la vuelve a mostrar. Van antes del atajo de `-token`, que vuelve enseguida.
        if d.bool(forKey: "sinOnboarding") { d.set("1", forKey: "mypump_onboarding_v1") }
        if d.bool(forKey: "reiniciarOnboarding") { d.removeObject(forKey: "mypump_onboarding_v1") }
        // Desarrollo: `simctl launch … -token <TOKEN>` entra con una cuenta de prueba sin pasar por el link.
        if let t = d.string(forKey: "token"), FormatoToken.valido(t) {
            // `-sinRed YES`: como sin señal (el gimnasio). La app arranca de su copia guardada y lo que se carga queda
            // en la cola hasta el próximo arranque sin el argumento.
            // `-fotosDePrueba YES`: el servidor de verdad, salvo las fotos de progreso (ver `FotosDePrueba`).
            let transporte: any Transporte
            if d.bool(forKey: "sinRed") { transporte = SinRed() }
            else if d.bool(forKey: "fotosDePrueba") { transporte = FotosDePrueba() }
            else { transporte = URLSession.shared }
            return ModeloApp(cliente: ClienteRPC(transporte: transporte), almacen: TokenEnMemoria(t))
        }
        // `-reiniciar YES`: arranca como recién instalada (sin token guardado), para probar la bienvenida.
        if d.bool(forKey: "reiniciar") {
            TokenEnKeychain().guardar(nil)
            d.removeObject(forKey: "mypump_token_invalido")
        }
        #endif
        // La migración del almacenamiento viejo corre ANTES de crear el modelo (que lee token y cola al iniciar).
        return ArranqueMigracion.arrancar { ModeloApp() }
    }
}

#if DEBUG
/// Todo pedido falla como sin señal (`-sinRed YES`).
private struct SinRed: Transporte {
    func enviar(_ pedido: URLRequest) async throws -> (Data, URLResponse) { throw URLError(.notConnectedToInternet) }
}

/// `-fotosDePrueba YES`: todo va al servidor de verdad salvo las fotos de progreso. Esas son cinco semanas de las tres
/// poses, con imágenes armadas acá. Sirve para ver la galería y el comparador (REV-04), que recién se abre a las 4
/// semanas: la ventana +1/−7 del servidor no deja sembrar semanas viejas en la cuenta de prueba. Las subidas contestan
/// OK sin salir del teléfono.
private struct FotosDePrueba: Transporte {
    static let semanas = 5

    func enviar(_ pedido: URLRequest) async throws -> (Data, URLResponse) {
        let ruta = pedido.url?.path ?? ""
        if ruta.hasSuffix("mypump_get_fotos_progreso") { return Self.respuesta(pedido, Self.filas()) }
        if ruta.hasSuffix("progreso/urls") { return Self.respuesta(pedido, Self.urls()) }
        if ruta.hasSuffix("progreso/upload") { return Self.respuesta(pedido, #"{"ok":true}"#) }
        return try await URLSession.shared.data(for: pedido)
    }

    /// Los lunes de las últimas semanas, del más nuevo al más viejo.
    private static func lunes() -> [String] {
        let hoy = FechaLocal.hoy()
        let base = DiaCalendario.numero(FotosProgreso.lunes(hoy)) ?? 0
        return (0..<semanas).map { DiaCalendario.texto(base - 7 * $0) }
    }

    private static func filas() -> String {
        let f = lunes().flatMap { l in FotosProgreso.poses.map { #"{"semana_lunes":"\#(l)","pose":"\#($0.clave)","tomada_el":"\#(l)","created_at":"\#(l)T12:00:00+00:00"}"# } }
        return "[" + f.joined(separator: ",") + "]"
    }

    private static func urls() -> String {
        let f = lunes().enumerated().flatMap { i, l in
            FotosProgreso.poses.map { p in #"{"semana_lunes":"\#(l)","pose":"\#(p.clave)","url":"\#(imagen(semana: semanas - i, pose: p.etiqueta, lunes: l).absoluteString)"}"# }
        }
        return #"{"ok":true,"fotos":["# + f.joined(separator: ",") + "]}"
    }

    /// Una imagen de 600×900 con la semana y la pose, guardada en el caché temporal.
    private static func imagen(semana: Int, pose: String, lunes: String) -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("fotos-prueba-\(lunes)-\(pose).jpg")
        if FileManager.default.fileExists(atPath: url.path) { return url }
        let tono = CGFloat(semana) / CGFloat(semanas)
        let img = UIGraphicsImageRenderer(size: CGSize(width: 600, height: 900)).image { c in
            UIColor(hue: 0.25, saturation: 0.35, brightness: 0.45 + 0.4 * tono, alpha: 1).setFill()
            c.fill(CGRect(x: 0, y: 0, width: 600, height: 900))
            let texto = "Semana \(semana)\n\(pose)" as NSString
            texto.draw(in: CGRect(x: 40, y: 380, width: 520, height: 200),
                       withAttributes: [.font: UIFont.systemFont(ofSize: 64, weight: .bold), .foregroundColor: UIColor.white])
        }
        try? img.jpegData(compressionQuality: 0.8)?.write(to: url)
        return url
    }

    private static func respuesta(_ pedido: URLRequest, _ cuerpo: String) -> (Data, URLResponse) {
        (Data(cuerpo.utf8), HTTPURLResponse(url: pedido.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}
#endif
