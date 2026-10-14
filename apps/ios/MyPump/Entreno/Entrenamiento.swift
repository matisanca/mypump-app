import SwiftUI
import AVFoundation
import UIKit
import MyPumpModelos
import MyPumpReglas
import MyPumpDatos

/// El motor de Entreno visto desde la app. El motor (`ModeloEntreno`) lo arma y lo mantiene `ModeloApp`: uno por rutina
/// (también en la demo, donde no escribe nada), con el catálogo del servidor, la sesión que trajo la migración y la
/// versión nueva de la rutina cuando llega; también lo avisa al volver a primer plano. Acá queda lo que es de la
/// vista: el reloj del descanso (un tick cada 250 ms mientras se ve la barra) y, al terminar, el háptico y un pitido
/// con la sesión de audio `.ambient` (no corta la música del cliente, SES-05). El aviso con la app en segundo plano
/// lo programa RaizApp (D8).
///
/// Vive arriba de las pestañas: el descanso se ve en la barra de pestañas aunque se esté en otra.
@MainActor @Observable
final class Entrenamiento {
    @ObservationIgnored private let sonido = SonidoDescanso()

    /// El motor de la rutina activa, o nil sin rutina (o antes de tener cuenta).
    var motor: ModeloEntreno? { Proveedor.modelo.entreno }

    /// Lo corre la raíz mientras la barra del descanso está a la vista: el descanso va contra una fecha de fin y este
    /// tick solo la mira (la barra se pinta con lo que deja).
    func correrDescanso() async {
        while !Task.isCancelled, let m = motor, m.descanso.visible {
            if m.tickDescanso() { terminoDescanso() }
            try? await Task.sleep(for: .milliseconds(250))
        }
    }

    private func terminoDescanso() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        sonido.reproducir()
    }
}

/// El pitido del fin del descanso: dos tonos cortos, con la sesión `.ambient` que se mezcla con la música (no la corta)
/// y respeta el silencio del teléfono.
@MainActor
final class SonidoDescanso {
    private var reproductor: AVAudioPlayer?

    func reproducir() {
        let sesion = AVAudioSession.sharedInstance()
        try? sesion.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        try? sesion.setActive(true)
        if reproductor == nil { reproductor = try? AVAudioPlayer(data: Self.pitido, fileTypeHint: AVFileType.wav.rawValue) }
        reproductor?.currentTime = 0
        reproductor?.play()
    }

    /// Un WAV de 16 bits armado en memoria: 880 Hz y 1320 Hz, 120 ms cada uno, con rampas para que no haga clic.
    static let pitido: Data = {
        let frecuencia = 44_100.0
        var muestras: [Int16] = []
        func tono(_ hz: Double, _ segundos: Double) {
            let n = Int(frecuencia * segundos)
            for i in 0..<n {
                let rampa = min(1, Double(i) / 400, Double(n - i) / 400)
                muestras.append(Int16(sin(2 * .pi * hz * Double(i) / frecuencia) * 0.35 * rampa * Double(Int16.max)))
            }
        }
        func silencio(_ segundos: Double) { muestras += Array(repeating: 0, count: Int(frecuencia * segundos)) }
        tono(880, 0.12); silencio(0.06); tono(1320, 0.16)
        var d = Data()
        func agregar<T: FixedWidthInteger>(_ v: T) { var x = v.littleEndian; d.append(Data(bytes: &x, count: MemoryLayout<T>.size)) }
        let bytes = UInt32(muestras.count * 2)
        d.append(contentsOf: Array("RIFF".utf8)); agregar(UInt32(36) + bytes); d.append(contentsOf: Array("WAVE".utf8))
        d.append(contentsOf: Array("fmt ".utf8)); agregar(UInt32(16)); agregar(UInt16(1)); agregar(UInt16(1))
        agregar(UInt32(frecuencia)); agregar(UInt32(frecuencia) * 2); agregar(UInt16(2)); agregar(UInt16(16))
        d.append(contentsOf: Array("data".utf8)); agregar(bytes)
        for m in muestras { agregar(m) }
        return d
    }()
}

/// Las preguntas del motor (`Pregunta`: reabrir el día, "¿está bien cargado?", terminar sin datos, día completado,
/// avanzar de semana) como alertas del sistema, esperando la respuesta.
@MainActor @Observable
final class Preguntador {
    var actual: Pregunta?
    @ObservationIgnored private var continuacion: CheckedContinuation<Bool, Never>?

    func preguntar(_ p: Pregunta) async -> Bool {
        continuacion?.resume(returning: false)
        continuacion = nil
        actual = p
        return await withCheckedContinuation { continuacion = $0 }
    }

    func responder(_ si: Bool) {
        let c = continuacion
        continuacion = nil
        actual = nil
        c?.resume(returning: si)
    }
}

extension View {
    /// Con los textos de la app: sin el emoji del título (las alertas del sistema van limpias) y los nombres de los
    /// días como en la lista ("Ir a EMPUJE" → "Ir a Empuje").
    func preguntas(_ p: Preguntador) -> some View {
        alert(Bonito.sinEmoji(p.actual?.titulo ?? ""), isPresented: Binding(get: { p.actual != nil }, set: { if !$0 { p.responder(false) } }),
              presenting: p.actual) { q in
            if !q.cancelar.isEmpty {
                Button(Bonito.nombres(Bonito.boton(q.cancelar)), role: .cancel) { p.responder(false) }
            }
            Button(Bonito.nombres(Bonito.boton(q.confirmar))) { p.responder(true) }
        } message: { q in
            Text(Bonito.nombres(q.cuerpo))
        }
    }
}

/// Los textos del motor salen con el formato de la web ("52.5kg × 7"); en la app van con la coma y el espacio de acá.
enum Bonito {
    /// "52.5kg × 7 · RIR 1" → "52,5 kg × 7 · RIR 1"; con el peso del cuerpo ("0kg × 12") → "12 reps".
    static func carga(_ s: String) -> String {
        var t = s.replacingOccurrences(of: #"(\d+)\.(\d+)kg"#, with: "$1,$2 kg", options: .regularExpression)
        t = t.replacingOccurrences(of: #"(\d)kg"#, with: "$1 kg", options: .regularExpression)
        t = t.replacingOccurrences(of: #"(^|\s)0 kg × (\d+)"#, with: "$1$2 reps", options: .regularExpression)
        return t
    }

    /// "58kg × 9 · RIR 0 (Agarre neutro)" → ("58 kg × 9", "RIR 0 · Agarre neutro")
    static func partir(_ s: String) -> (principal: String, detalle: String?) {
        var texto = carga(s)
        var extra: [String] = []
        if texto.hasSuffix(")"), let abre = texto.range(of: " (", options: .backwards) {
            extra.append(String(texto[abre.upperBound...].dropLast()))
            texto = String(texto[..<abre.lowerBound])
        }
        var partes = texto.components(separatedBy: " · ")
        let principal = partes.removeFirst()
        // Lo de la variante en el medio ("58 kg × 9 (Agarre) · 3 series").
        var limpio = principal
        if limpio.hasSuffix(")"), let abre = limpio.range(of: " (", options: .backwards) {
            extra.insert(String(limpio[abre.upperBound...].dropLast()), at: 0)
            limpio = String(limpio[..<abre.lowerBound])
        }
        let detalle = (partes + extra).filter { !$0.isEmpty }
        return (limpio, detalle.isEmpty ? nil : detalle.joined(separator: " · "))
    }

    /// Los botones de las preguntas, sin la flecha de la web ("Pasar a SEM 6 →").
    static func boton(_ s: String) -> String {
        s.replacingOccurrences(of: " →", with: "").trimmingCharacters(in: .whitespaces)
    }

    /// Lo que la web escribe con un emoji adelante ("🎯 Primera vez…"): en la app el ícono es un SF Symbol.
    static func sinEmoji(_ s: String) -> String {
        guard let primero = s.unicodeScalars.first, primero.properties.isEmojiPresentation || primero.properties.isEmoji,
              !("0"..."9").contains(Character(primero)) else { return s }
        return String(s.drop { !$0.isWhitespace }).trimmingCharacters(in: .whitespaces)
    }

    /// Las palabras en mayúsculas de 4 letras o más (los nombres de los días: "EMPUJE", "TIRÓN") como nombre propio; las
    /// siglas cortas ("RIR", "SEM") quedan igual.
    static func nombres(_ s: String) -> String {
        var t = s
        let patron = #"\b[A-ZÁÉÍÓÚÑÜ]{4,}\b"#
        while let r = t.range(of: patron, options: .regularExpression) {
            t.replaceSubrange(r, with: t[r].lowercased().localizedCapitalized)
        }
        return t
    }

    /// "TIRÓN A — ANCHO" → "Tirón A — ancho"; lo que no viene en mayúsculas queda igual.
    static func titulo(_ s: String?) -> String {
        guard let s, !s.isEmpty else { return "" }
        return s == s.uppercased() ? s.localizedCapitalized : s
    }
}
