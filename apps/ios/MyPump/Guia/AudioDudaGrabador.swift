import AVFoundation
import Observation
import MyPumpDatos
import MyPumpReglas

/// El micrófono de las dudas en audio: AVAudioRecorder con AAC en m4a, mono, 64 kbps y 44,1 kHz. Mientras graba, la sesión
/// de audio es `.playAndRecord`; al terminar vuelve a la que tenía la app (la del reproductor de la guía, o la de fábrica).
/// El permiso se pide recién al tocar «Grabar».
@MainActor
final class GrabadorAV: NSObject, GrabadorAudio {
    var alInterrumpir: (@MainActor () -> Void)?
    private var grabador: AVAudioRecorder?
    private var previa: (AVAudioSession.Category, AVAudioSession.Mode, AVAudioSession.CategoryOptions)?
    private var observador: NSObjectProtocol?

    var permiso: PermisoMicrofono {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: .dado
        case .denied: .negado
        default: .sinPreguntar
        }
    }

    func pedirPermiso() async -> Bool { await AVAudioApplication.requestRecordPermission() }

    func empezar(en archivo: URL) -> AvisoAudio? {
        let s = AVAudioSession.sharedInstance()
        previa = (s.category, s.mode, s.categoryOptions)
        do {
            try s.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try s.setActive(true)
        } catch {
            // Lo tiene otra app (una llamada en curso) o el sistema no lo suelta.
            volverALaSesionDeLaApp()
            return .ocupado
        }
        guard s.isInputAvailable else { volverALaSesionDeLaApp(); return .sinMicrofono }
        let ajustes: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: ReglasAudioDuda.frecuencia,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: ReglasAudioDuda.bitrate,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
        ]
        do {
            let g = try AVAudioRecorder(url: archivo, settings: ajustes)
            guard g.record() else { volverALaSesionDeLaApp(); return .ocupado }
            grabador = g
        } catch {
            volverALaSesionDeLaApp()
            return .ocupado
        }
        // Una llamada o Siri cortan el micrófono: se frena y se pasa a revisar con lo grabado.
        observador = NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: s, queue: .main) { [weak self] n in
            let tipo = (n.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt).flatMap(AVAudioSession.InterruptionType.init(rawValue:))
            guard tipo == .began else { return }
            MainActor.assumeIsolated { self?.alInterrumpir?() }
        }
        return nil
    }

    func terminar() {
        if let o = observador { NotificationCenter.default.removeObserver(o) }
        observador = nil
        grabador?.stop()
        grabador = nil
        volverALaSesionDeLaApp()
    }

    private func volverALaSesionDeLaApp() {
        let s = AVAudioSession.sharedInstance()
        try? s.setActive(false, options: .notifyOthersOnDeactivation)
        if let (c, m, o) = previa { try? s.setCategory(c, mode: m, options: o) }
        previa = nil
    }
}

#if DEBUG
/// Las pruebas de interfaz sin micrófono (`-audioDoble YES`): escribe un m4a de verdad con un tono, así la revisión lo
/// puede reproducir. `-audioPermiso negado|sinPreguntar` cambia lo que contesta el permiso.
@MainActor
final class GrabadorDobleUI: GrabadorAudio {
    var alInterrumpir: (@MainActor () -> Void)?
    private var archivo: URL?
    private var inicio = Date()
    var permiso: PermisoMicrofono = {
        switch UserDefaults.standard.string(forKey: "audioPermiso") {
        case "negado": .negado
        case "sinPreguntar": .sinPreguntar
        default: .dado
        }
    }()

    func pedirPermiso() async -> Bool { permiso = .dado; return true }

    func empezar(en archivo: URL) -> AvisoAudio? {
        self.archivo = archivo
        inicio = Date()
        return nil
    }

    func terminar() {
        guard let archivo else { return }
        self.archivo = nil
        Self.escribirTono(en: archivo, segundos: min(10, max(1, Date().timeIntervalSince(inicio))))
    }

    static func escribirTono(en url: URL, segundos: Double) {
        let fr = ReglasAudioDuda.frecuencia
        guard let formato = AVAudioFormat(standardFormatWithSampleRate: fr, channels: 1),
              let f = try? AVAudioFile(forWriting: url, settings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: fr,
                                                                  AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: ReglasAudioDuda.bitrate]),
              let b = AVAudioPCMBuffer(pcmFormat: formato, frameCapacity: AVAudioFrameCount(fr * segundos))
        else { return }
        b.frameLength = b.frameCapacity
        let datos = b.floatChannelData![0]
        for i in 0..<Int(b.frameLength) { datos[i] = 0.2 * sin(Float(i) * 2 * .pi * 440 / Float(fr)) }
        try? f.write(from: b)
    }
}
#endif

/// El reproductor de la revisión: play y pausa, con el avance.
@MainActor @Observable
final class ReproductorRevision: NSObject, AVAudioPlayerDelegate {
    private(set) var sonando = false
    private(set) var actual: Double = 0
    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var archivo: URL?
    @ObservationIgnored private var tics: Task<Void, Never>?

    func alternar(_ url: URL) {
        if sonando { pausar(); return }
        if archivo != url || player == nil {
            player = try? AVAudioPlayer(contentsOf: url)
            player?.delegate = self
            archivo = url
        }
        guard let player else { return }
        SesionAudio.activar()
        player.play()
        sonando = true
        tics?.cancel()
        tics = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard let self, let p = self.player else { return }
                self.actual = p.currentTime
            }
        }
    }

    func pausar() {
        player?.pause()
        sonando = false
        tics?.cancel()
    }

    /// Al mandar, grabar de nuevo o borrar: se suelta el archivo.
    func soltar() {
        pausar()
        player = nil
        archivo = nil
        actual = 0
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.sonando = false
            self.actual = 0
            self.tics?.cancel()
        }
    }
}
