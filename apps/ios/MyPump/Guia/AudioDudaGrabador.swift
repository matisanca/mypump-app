import AVFoundation
import Observation
import MyPumpDatos
import MyPumpReglas

/// El micrófono de las dudas en audio: AVAudioRecorder con AAC en m4a, mono, 64 kbps y 44,1 kHz. Mientras graba, la sesión
/// de audio es `.playAndRecord`; al terminar vuelve a la de la app según la cuenta de `SesionAudio` (la de un video o
/// audio que siga sonando, o `.ambient` desactivada).
/// El permiso se pide recién al tocar «Grabar».
@MainActor
final class GrabadorAV: NSObject, GrabadorAudio, SuenaAudio {
    var alInterrumpir: (@MainActor () -> Void)?
    private var grabador: AVAudioRecorder?
    private var observador: NSObjectProtocol?

    var permiso: PermisoMicrofono {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: .dado
        case .denied: .negado
        default: .sinPreguntar
        }
    }

    func pedirPermiso() async -> Bool { await AVAudioApplication.requestRecordPermission() }

    var suenaAudio: Bool { grabador?.isRecording == true }

    func empezar(en archivo: URL) -> AvisoAudio? {
        let s = AVAudioSession.sharedInstance()
        // Cuenta como un reproductor más: el pitido del descanso no toca la sesión mientras graba.
        SesionAudio.contar(self)
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

    /// Lo decide la cuenta: si era el último dueño, se desactiva y vuelve a `.ambient`; si queda un video o un audio de la
    /// app, vuelve a su `.playback` sin desactivarse. Repetirlo (un `empezar` fallido y después `terminar`) no hace nada.
    private func volverALaSesionDeLaApp() { SesionAudio.soltarGrabador(self) }
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
final class ReproductorRevision: NSObject, AVAudioPlayerDelegate, SuenaAudio {
    private(set) var sonando = false
    private(set) var actual: Double = 0
    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var archivo: URL?
    @ObservationIgnored private var tics: Task<Void, Never>?
    /// Una llamada, Siri o irse a segundo plano: pausa y suelta (el `AVAudioPlayer` se corta sin avisar).
    @ObservationIgnored private var cortes: AlCortarAudio?

    override init() {
        super.init()
        cortes = AlCortarAudio { [weak self] in if self?.sonando == true { self?.pausar() } }
    }

    var suenaAudio: Bool { player?.isPlaying == true }

    func alternar(_ url: URL) {
        if sonando { pausar(); return }
        if archivo != url || player == nil {
            player = try? AVAudioPlayer(contentsOf: url)
            player?.delegate = self
            archivo = url
        }
        guard let player else { return }
        SesionAudio.activar(self)
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

    /// En pausa suelta la sesión: la música del cliente vuelve a su volumen.
    func pausar() {
        player?.pause()
        sonando = false
        tics?.cancel()
        soltarSesion()
    }

    /// Al mandar, grabar de nuevo, borrar o salir: se suelta el archivo y la sesión, así la música del cliente vuelve.
    func soltar() {
        pausar()
        player = nil
        archivo = nil
        actual = 0
        soltarSesion()
    }

    private func soltarSesion() { SesionAudio.soltar(self) }

    /// Al terminar de escucharse, la sesión se suelta con `.notifyOthersOnDeactivation` (revisión del 4-nov, punto 8).
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.sonando = false
            self.actual = 0
            self.tics?.cancel()
            self.soltarSesion()
        }
    }
}
