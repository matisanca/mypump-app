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
        m.conAvisos = { @MainActor in
            await CentroAvisos.shared.alEntrar()
            DatosCalibracion.subirSiCorresponde()   // lo grabado que falte, si el servidor lo habilita
        }
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
            // `-recuperacionDePrueba baja|alta|calibrando`: lo mismo con la serie de recuperación (ver `RecuperacionDePrueba`).
            var transporte: any Transporte
            if d.bool(forKey: "sinRed") { transporte = SinRed() }
            // `-gimnasioDePrueba <escenario>`: el servidor del gimnasio de mentira y lo demás de las muestras (ver `GimnasioDePrueba`).
            else if let caso = d.string(forKey: "gimnasioDePrueba") { transporte = GimnasioDePrueba(doble: .escenario(caso), sinRutina: d.bool(forKey: "gimnasioSinRutina")) }
            // `-fotosInicioDePrueba <escenario>`: lo mismo con las fotos de inicio (`-fotosInicioFoto buena|oscura|chica|movida`: la foto que «saca»).
            else if let caso = d.string(forKey: "fotosInicioDePrueba") { transporte = FotosInicioDePrueba(doble: .escenario(caso)) }
            else if let caso = d.string(forKey: "tecnicaDePrueba") { transporte = TecnicaDePrueba(doble: .escenario(caso)) }
            else if d.bool(forKey: "fotosDePrueba") { transporte = FotosDePrueba() }
            else if let caso = d.string(forKey: "recuperacionDePrueba") { transporte = RecuperacionDePrueba(caso: caso) }
            // `-semanaDePrueba completa|incompleta`: el check y las fotos de esta semana inventados (ver `SemanaDePrueba`).
            else if let caso = d.string(forKey: "semanaDePrueba") { transporte = SemanaDePrueba(completa: caso == "completa") }
            else { transporte = URLSession.shared }
            // `-guiaOkFalse YES`: «Tu guía» contesta `{"ok": false}`, como con el token revocado o la página dada de baja (la
            // sección tiene que desaparecer). Lo demás va al servidor de verdad.
            if d.bool(forKey: "guiaOkFalse") { transporte = GuiaRevocada(resto: transporte) }
            // `-guiaTarjeta no`: el resumen de verdad con `mostrar_tarjeta` false, como pasadas las 48 h de la entrega.
            else if d.string(forKey: "guiaTarjeta") == "no" { transporte = GuiaDespuesDeLaEntrega(resto: transporte) }
            let m = ModeloApp(cliente: ClienteRPC(transporte: transporte), almacen: TokenEnMemoria(t))
            // `-offDePrueba encontrado|incompleto|noEncontrado|sinRed`: Open Food Facts de mentira (ver `OFFDePrueba`).
            if let caso = d.string(forKey: "offDePrueba") { m.transporteBarras = OFFDePrueba(caso: caso) }
            return m
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
#if DEBUG
/// `-tecnicaDePrueba`: lo de técnica lo contesta el doble (sin red), y la cuenta y el plan salen de las muestras.
private struct TecnicaDePrueba: Transporte {
    let doble: DobleTecnica

    func enviar(_ pedido: URLRequest) async throws -> (Data, URLResponse) {
        let ruta = pedido.url?.path ?? ""
        let f = ruta.components(separatedBy: "/").last ?? ""
        if ruta.contains("/tecnica/") || f.hasPrefix("mypump_tecnica") || f == "mypump_get_app_config" { return try await doble.enviar(pedido) }
        var cuerpo = Data("[]".utf8)
        if let b = Bundle.main.url(forResource: "Muestras", withExtension: "bundle").flatMap(Bundle.init(url:)),
           let u = b.url(forResource: f.replacingOccurrences(of: "mypump_", with: ""), withExtension: "json"), let d = try? Data(contentsOf: u) { cuerpo = d }
        return (cuerpo, HTTPURLResponse(url: pedido.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}

/// `-fotosInicioDePrueba`: lo de las fotos de inicio lo contesta el doble (sin red), y la cuenta y el plan salen de las muestras.
private struct FotosInicioDePrueba: Transporte {
    let doble: DobleFotosInicio

    func enviar(_ pedido: URLRequest) async throws -> (Data, URLResponse) {
        let ruta = pedido.url?.path ?? ""
        let f = ruta.components(separatedBy: "/").last ?? ""
        if ruta.contains("/inicio/") || f.hasPrefix("mypump_fotos_inicio") || f == "mypump_get_app_config" { return try await doble.enviar(pedido) }
        var cuerpo = Data("[]".utf8)
        if let b = Bundle.main.url(forResource: "Muestras", withExtension: "bundle").flatMap(Bundle.init(url:)),
           let u = b.url(forResource: f.replacingOccurrences(of: "mypump_", with: ""), withExtension: "json"), let d = try? Data(contentsOf: u) { cuerpo = d }
        return (cuerpo, HTTPURLResponse(url: pedido.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}

/// `-gimnasioDePrueba`: lo del gimnasio lo contesta el doble (sin red), y la cuenta y el plan salen de las muestras.
private struct GimnasioDePrueba: Transporte {
    let doble: DobleGimnasio
    let sinRutina: Bool

    func enviar(_ pedido: URLRequest) async throws -> (Data, URLResponse) {
        let ruta = pedido.url?.path ?? ""
        let f = ruta.components(separatedBy: "/").last ?? ""
        if ruta.contains("/gimnasio/") || f.hasPrefix("mypump_gimnasio") || f == "mypump_get_app_config" { return try await doble.enviar(pedido) }
        var cuerpo = Data("[]".utf8)
        if !(sinRutina && f == "mypump_get_rutina_activa"),
           let b = Bundle.main.url(forResource: "Muestras", withExtension: "bundle").flatMap(Bundle.init(url:)),
           let u = b.url(forResource: f.replacingOccurrences(of: "mypump_", with: ""), withExtension: "json"), let d = try? Data(contentsOf: u) { cuerpo = d }
        return (cuerpo, HTTPURLResponse(url: pedido.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}
#endif

private struct SinRed: Transporte {
    func enviar(_ pedido: URLRequest) async throws -> (Data, URLResponse) { throw URLError(.notConnectedToInternet) }
}

/// `-guiaOkFalse YES`: las lecturas de «Tu guía» dicen que no hay guía.
private struct GuiaRevocada: Transporte {
    let resto: any Transporte

    func enviar(_ pedido: URLRequest) async throws -> (Data, URLResponse) {
        let ruta = pedido.url?.path ?? ""
        if ruta.hasSuffix("entregas_app_get") || ruta.hasSuffix("entregas_app_resumen") {
            return (Data(#"{"ok":false}"#.utf8), HTTPURLResponse(url: pedido.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        return try await resto.enviar(pedido)
    }
}

/// `-guiaTarjeta no`: `entregas_app_resumen` del servidor de verdad, con `mostrar_tarjeta` false (lo demás tal cual).
private struct GuiaDespuesDeLaEntrega: Transporte {
    let resto: any Transporte

    func enviar(_ pedido: URLRequest) async throws -> (Data, URLResponse) {
        let (datos, respuesta) = try await resto.enviar(pedido)
        guard pedido.url?.path.hasSuffix("entregas_app_resumen") == true,
              var o = (try? JSONSerialization.jsonObject(with: datos)) as? [String: Any], o["ok"] as? Bool == true else { return (datos, respuesta) }
        o["mostrar_tarjeta"] = false
        return ((try? JSONSerialization.data(withJSONObject: o)) ?? datos, respuesta)
    }
}

/// `-semanaDePrueba completa|incompleta`: todo va al servidor de verdad salvo el check y las fotos de la semana: completa
/// (el check enviado y las tres poses de esta semana) o vacía. Para ver que el aviso del domingo se saltea con la semana
/// completa (R2 de la 2.0.3) sin tocar lo que tiene guardado la cuenta de prueba.
private struct SemanaDePrueba: Transporte {
    let completa: Bool

    func enviar(_ pedido: URLRequest) async throws -> (Data, URLResponse) {
        let ruta = pedido.url?.path ?? ""
        let lunes = FotosProgreso.lunes(FechaLocal.hoy())
        if ruta.hasSuffix("mypump_get_checkin_semana") {
            return Self.respuesta(pedido, completa ? #"[{"energia":4,"descanso":3,"hambre":2,"adherencia":4,"nota":null}]"# : "[]")
        }
        if ruta.hasSuffix("mypump_get_fotos_progreso") {
            let f = completa ? FotosProgreso.poses.map { #"{"semana_lunes":"\#(lunes)","pose":"\#($0.clave)","tomada_el":"\#(lunes)","created_at":"\#(lunes)T12:00:00+00:00"}"# } : []
            return Self.respuesta(pedido, "[" + f.joined(separator: ",") + "]")
        }
        if ruta.hasSuffix("progreso/urls") { return Self.respuesta(pedido, #"{"ok":true,"fotos":[]}"#) }
        // `-revisionDiaDePrueba 6`: el día de revisión que todavía no puede venir de la base (nativa_008 sin aplicar).
        if ruta.hasSuffix("mypump_get_revision_dia"), let dia = UserDefaults.standard.string(forKey: "revisionDiaDePrueba") {
            return Self.respuesta(pedido, dia)
        }
        return try await URLSession.shared.data(for: pedido)
    }

    private static func respuesta(_ pedido: URLRequest, _ cuerpo: String) -> (Data, URLResponse) {
        (Data(cuerpo.utf8), HTTPURLResponse(url: pedido.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}

/// `-recuperacionDePrueba <caso>`: todo va al servidor de verdad salvo la recuperación, que es una serie inventada de 14
/// días con las columnas de nativa_007 (`confianza`, `motivo_falta`). Para ver la pastilla de confianza y el texto de qué
/// falta sin depender del reloj de la cuenta de prueba (R1 de la 2.0.3).
private struct RecuperacionDePrueba: Transporte {
    let caso: String

    func enviar(_ pedido: URLRequest) async throws -> (Data, URLResponse) {
        let ruta = pedido.url?.path ?? ""
        if ruta.hasSuffix("mypump_get_recuperacion") { return Self.respuesta(pedido, filas()) }
        if ruta.hasSuffix("mypump_get_mostrar_recuperacion") { return Self.respuesta(pedido, "true") }
        return try await URLSession.shared.data(for: pedido)
    }

    private func filas() -> String {
        let hoy = DiaCalendario.numero(FechaLocal.hoy()) ?? 0
        let deHoy: String
        var conScore = 6
        switch caso {
        case "calibrando":
            deHoy = #""score":null,"estado":"calibrando","dias_datos":5,"motivo_falta":"Calibrando, hay 5 de 14 días con datos del reloj. Faltan 9 días.","confianza":null"#
            conScore = 0
        case "alta":
            deHoy = #""score":74,"estado":"ok","banda":"alta","dias_datos":40,"motivos":[],"motivo_falta":null,"confianza":"alta""#
        default:
            deHoy = #""score":41,"estado":"ok","banda":"media","dias_datos":40,"banda_provisoria":false,"discordancia":false,"motivos":[],"motivo_falta":"Confianza baja. Para mejorarla, usá el reloj para dormir.","confianza":"baja""#
        }
        let f = (0..<14).reversed().map { i -> String in
            let fecha = DiaCalendario.texto(hoy - i)
            if i == 0 { return #"{"fecha":"\#(fecha)",\#(deHoy)}"# }
            if i < conScore { return #"{"fecha":"\#(fecha)","score":\#(50 + i * 3),"estado":"ok","banda":"media","dias_datos":40,"confianza":"media"}"# }
            return #"{"fecha":"\#(fecha)","score":null,"estado":"insuficiente"}"#
        }
        return "[" + f.joined(separator: ",") + "]"
    }

    private static func respuesta(_ pedido: URLRequest, _ cuerpo: String) -> (Data, URLResponse) {
        (Data(cuerpo.utf8), HTTPURLResponse(url: pedido.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
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
