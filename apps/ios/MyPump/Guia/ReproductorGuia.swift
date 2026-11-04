import AVFoundation
import AVKit
import Network
import SwiftUI
import MyPumpModelos
import MyPumpReglas
import MyPumpDatos

/// El reproductor de «Tu guía»: un AVPlayer con los controles del sistema (pantalla completa y girar, como cualquier
/// video de iOS). Lo que decide cuándo guardar, retomar y qué video sigue está en `ReglasGuia` y `AvanceVideo` (puros,
/// con tests); acá solo se conecta el AVPlayer.
///
/// Como la web: tocar una fila arranca directo; «Anterior», «Siguiente» y el final de un video pasan al otro con la
/// placa de 2,6 s («Otro tema · Video N de M»), y mientras está la placa el video no corre.
@MainActor @Observable
final class ControlReproductor {
    /// El video cargado (índice en `clips`).
    private(set) var actual: Int?
    /// La placa que se ve (índice del video que viene).
    private(set) var placa: Int?
    private(set) var velocidad: Float = 1
    private(set) var reproduciendo = false
    /// Todavía no arrancó ninguno: se ve la portada con el título y el botón de play.
    private(set) var portada = true
    /// No se puede reproducir: sin red o el video no carga.
    private(set) var sinConexion = false
    /// Cambia cada vez que cambia el video (el destello del título, el desplazamiento de la lista).
    private(set) var cambios = 0

    @ObservationIgnored let player = AVPlayer()
    @ObservationIgnored var clips: () -> [ClipGuia] = { [] }
    @ObservationIgnored var alGuardar: (String, AvanceVideo.Guardado) -> Void = { _, _ in }
    /// DEBUG `-sinRed YES`: como sin señal, aunque el simulador tenga red.
    @ObservationIgnored var forzarSinRed = false
    /// Capturas (DEBUG `-guiaPlaca YES`): la placa queda fija hasta tocarla.
    @ObservationIgnored var placaFija = false

    @ObservationIgnored private var avance = AvanceVideo(visto: false)
    @ObservationIgnored private var videoCargado: String?
    @ObservationIgnored private var observadorTiempo: Any?
    @ObservationIgnored private var observadorEstado: NSKeyValueObservation?
    @ObservationIgnored private var observadorControl: NSKeyValueObservation?
    /// Los observadores de fin y falla del video: se sacan al cambiar de video y al soltar el control.
    @ObservationIgnored nonisolated(unsafe) private var finales: [NSObjectProtocol] = []
    @ObservationIgnored private var tareaPlaca: Task<Void, Never>?
    @ObservationIgnored private var retomado = false
    @ObservationIgnored nonisolated private let red = NWPathMonitor()
    @ObservationIgnored private var hayRed = true
    /// El video está en pantalla completa (la presenta el sistema): salir de la vista de la guía no lo pausa.
    @ObservationIgnored var pantallaCompleta = false

    init() {
        player.actionAtItemEnd = .pause
        // La posición cada segundo: alcanza para «cada 10 s» y el 80 %.
        observadorTiempo = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 1, preferredTimescale: 600), queue: .main) { [weak self] t in
            MainActor.assumeIsolated { self?.avanzo(t.seconds) }
        }
        observadorControl = player.observe(\.timeControlStatus, options: [.new]) { [weak self] p, _ in
            let corre = p.timeControlStatus != .paused
            Task { @MainActor in self?.reproduciendo = corre }
        }
        red.pathUpdateHandler = { [weak self] camino in
            let ok = camino.status == .satisfied
            Task { @MainActor in self?.hayRed = ok }
        }
        red.start(queue: .main)
    }

    deinit {
        red.cancel()
        finales.forEach(NotificationCenter.default.removeObserver)
    }

    var clipActual: ClipGuia? {
        guard let i = actual else { return nil }
        let c = clips()
        return c.indices.contains(i) ? c[i] : nil
    }

    var haySiguiente: Bool { actual.flatMap { ReglasGuia.siguiente(clips(), desde: $0) } != nil }
    var hayAnterior: Bool { actual.flatMap { ReglasGuia.anterior(clips(), desde: $0) } != nil }

    // MARK: - Acciones

    /// Al abrir la sección: el primero sin ver, sin reproducir (se ve la portada).
    func prepararInicial() {
        guard actual == nil, let i = ReglasGuia.inicial(clips()) else { return }
        cargar(i, reproducir: false, conPlaca: false)
    }

    /// Tocar una fila (o «Ver por qué»): arranca directo, sin placa.
    func reproducir(_ i: Int) { cargar(i, reproducir: true, conPlaca: false) }

    func reproducir(video id: String) {
        guard let i = clips().firstIndex(where: { $0.id == id && $0.url != nil }) else { return }
        reproducir(i)
    }

    func siguiente() {
        guard let a = actual, let i = ReglasGuia.siguiente(clips(), desde: a) else { return }
        cargar(i, reproducir: true, conPlaca: true)
    }

    func anterior() {
        guard let a = actual, let i = ReglasGuia.anterior(clips(), desde: a) else { return }
        cargar(i, reproducir: true, conPlaca: true)
    }

    /// El play de la portada.
    func empezar() {
        guard actual != nil else { prepararInicial(); return }
        portada = false
        arrancar()
    }

    func cambiarVelocidad() {
        velocidad = ReglasGuia.velocidadSiguiente(velocidad)
        player.defaultRate = velocidad
        if player.timeControlStatus != .paused { player.rate = velocidad }
    }

    /// La placa se cierra sola a los 2,6 s o al tocarla, y ahí arranca el video.
    func cerrarPlaca() {
        guard placa != nil else { return }
        tareaPlaca?.cancel()
        placa = nil
        arrancar()
    }

    /// Reintentar después de «Necesitás conexión».
    func reintentar() {
        guard let i = actual else { return }
        videoCargado = nil
        cargar(i, reproducir: true, conPlaca: false)
    }

    /// Al salir de la sección o al ir a segundo plano: lo último que se vio queda guardado.
    func guardarAlSalir() {
        guard let id = videoCargado, player.currentItem != nil else { return }
        if let g = avance.alSalir(player.currentTime().seconds) { alGuardar(id, g) }
    }

    func pausar() {
        guardarAlSalir()
        player.pause()
    }

    // MARK: - Carga

    private func cargar(_ i: Int, reproducir: Bool, conPlaca: Bool) {
        let lista = clips()
        guard lista.indices.contains(i), let url = lista[i].url else { return }
        guardarAlSalir()
        tareaPlaca?.cancel()
        placa = nil
        let clip = lista[i]
        actual = i
        cambios += 1
        if reproducir { portada = false }
        sinConexion = false
        if videoCargado != clip.id {
            videoCargado = clip.id
            avance = AvanceVideo(visto: clip.visto)
            retomado = false
            if forzarSinRed || !hayRed {
                player.replaceCurrentItem(with: nil)
                sinConexion = reproducir
                return
            }
            let item = AVPlayerItem(url: url)
            observar(item)
            player.replaceCurrentItem(with: item)
        }
        player.defaultRate = velocidad
        if conPlaca {
            player.pause()
            placa = i
            if placaFija { return }
            tareaPlaca = Task { [weak self] in
                try? await Task.sleep(for: .seconds(ReglasGuia.placaSegundos))
                guard !Task.isCancelled else { return }
                self?.cerrarPlaca()
            }
        } else if reproducir {
            arrancar()
        } else {
            player.pause()
        }
    }

    private func arrancar() {
        if forzarSinRed || (player.currentItem == nil && !hayRed) {
            sinConexion = true
            return
        }
        if player.currentItem == nil, let i = actual { videoCargado = nil; cargar(i, reproducir: true, conPlaca: false); return }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
        player.defaultRate = velocidad
        player.play()
        player.rate = velocidad
    }

    private func observar(_ item: AVPlayerItem) {
        observadorEstado = item.observe(\.status, options: [.new]) { [weak self] it, _ in
            let estado = it.status
            let dur = it.duration.seconds
            Task { @MainActor in self?.cambioEstado(estado, duracion: dur, item: it) }
        }
        finales.forEach(NotificationCenter.default.removeObserver)
        finales = [
            NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.termino() }
            },
            NotificationCenter.default.addObserver(forName: AVPlayerItem.failedToPlayToEndTimeNotification, object: item, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.sinConexion = true }
            },
        ]
    }

    private func cambioEstado(_ estado: AVPlayerItem.Status, duracion: Double, item: AVPlayerItem) {
        guard item === player.currentItem else { return }
        switch estado {
        case .readyToPlay:
            sinConexion = false
            // Retoma desde donde lo dejó (ver espec 4.6), una vez por carga.
            if !retomado, let c = clipActual {
                retomado = true
                if let desde = ReglasGuia.retomar(c, duracion: duracion) {
                    avance = AvanceVideo(visto: c.visto, desde: desde)
                    item.seek(to: CMTime(seconds: desde, preferredTimescale: 600), completionHandler: nil)
                }
            }
        case .failed:
            if !portada || placa != nil { sinConexion = true }
        default: break
        }
    }

    private func avanzo(_ t: Double) {
        guard placa == nil, player.timeControlStatus == .playing, let id = videoCargado,
              let dur = player.currentItem?.duration.seconds else { return }
        if let g = avance.alAvanzar(t, duracion: dur) { alGuardar(id, g) }
    }

    private func termino() {
        guard let id = videoCargado else { return }
        alGuardar(id, avance.alTerminar(duracion: player.currentItem?.duration.seconds ?? .nan))
        // Pasa solo al siguiente, con su placa. Si era el último, queda ahí.
        if haySiguiente { siguiente() }
    }
}

// MARK: - Vista

/// El cuadro del video (16:9) con la portada, la placa y el aviso sin conexión encima.
struct CuadroVideo: View {
    let control: ControlReproductor
    let total: Int

    var body: some View {
        ZStack {
            Color.black
            VistaAVPlayer(player: control.player, control: control)
                .opacity(control.portada || control.sinConexion ? 0 : 1)
                .accessibilityLabel(control.clipActual.map { "Video: \($0.titulo)" } ?? "Video")
            // La placa va primero: si el video no carga, el aviso aparece al cerrarla.
            if let i = control.placa, let c = control.clips().indices.contains(i) ? control.clips()[i] : nil {
                PlacaVideo(clip: c, indice: i, total: total) { control.cerrarPlaca() }
                    .transition(.opacity)
            } else if control.sinConexion {
                SinConexionVideo { control.reintentar() }
            } else if control.portada, let c = control.clipActual {
                PortadaVideo(clip: c, indice: control.actual ?? 0, total: total) { control.empezar() }
            }
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .clipped()
        .animation(.easeOut(duration: 0.3), value: control.placa)
        .environment(\.colorScheme, .dark)
    }
}

/// AVPlayerViewController con los controles del sistema: pantalla completa, girar, AirPlay y Picture in Picture.
struct VistaAVPlayer: UIViewControllerRepresentable {
    let player: AVPlayer
    let control: ControlReproductor

    func makeCoordinator() -> Coordinador { Coordinador(control: control) }

    /// Avisa al control cuando el sistema presenta el video a pantalla completa (la guía queda debajo y no se pausa).
    @MainActor final class Coordinador: NSObject, @preconcurrency AVPlayerViewControllerDelegate {
        let control: ControlReproductor
        init(control: ControlReproductor) { self.control = control }

        func playerViewController(_ vc: AVPlayerViewController, willBeginFullScreenPresentationWithAnimationCoordinator c: any UIViewControllerTransitionCoordinator) {
            control.pantallaCompleta = true
        }

        func playerViewController(_ vc: AVPlayerViewController, willEndFullScreenPresentationWithAnimationCoordinator c: any UIViewControllerTransitionCoordinator) {
            control.pantallaCompleta = false
        }
    }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let vc = AVPlayerViewController()
        vc.delegate = context.coordinator
        vc.allowsPictureInPicturePlayback = false
        vc.player = player
        vc.showsPlaybackControls = true
        vc.videoGravity = .resizeAspect
        vc.entersFullScreenWhenPlaybackBegins = false
        vc.exitsFullScreenWhenPlaybackEnds = false
        // La velocidad la maneja el botón de la app (1 → 1,25 → 1,5), como en la web.
        vc.speeds = []
        return vc
    }

    func updateUIViewController(_ vc: AVPlayerViewController, context: Context) {
        if vc.player !== player { vc.player = player }
    }
}

/// Antes del primer play: el título sobre negro, como el cuadro de la web, y el botón de reproducir.
private struct PortadaVideo: View {
    let clip: ClipGuia
    let indice: Int
    let total: Int
    let alTocar: () -> Void

    var body: some View {
        Button(action: alTocar) {
            ZStack {
                LinearGradient(colors: [Color(white: 0.04), Color(red: 0.07, green: 0.11, blue: 0.08)], startPoint: .top, endPoint: .bottom)
                VStack(spacing: Espacio.s) {
                    Spacer(minLength: 0)
                    Text(clip.titulo)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .minimumScaleFactor(0.7)
                    Capsule().fill(Color(red: 0.36, green: 0.73, blue: 0.45)).frame(width: 56, height: 3)
                    Spacer(minLength: 0)
                    Image(systemName: "play.fill")
                        .font(.title2)
                        .foregroundStyle(.black)
                        .frame(width: 56, height: 56)
                        .background(.white, in: .circle)
                        .padding(.bottom, Espacio.m)
                }
                .padding(.horizontal, Espacio.l)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Reproducir \(clip.titulo)")
        .accessibilityHint("Video \(indice + 1) de \(total), \(ReglasGuia.duracionHablada(minutos: clip.minutos))")
        .accessibilityIdentifier("guia-portada")
    }
}

/// La placa al pasar a otro video: 2,6 s, se cierra sola o al tocarla.
private struct PlacaVideo: View {
    let clip: ClipGuia
    let indice: Int
    let total: Int
    let alTocar: () -> Void
    @State private var lleno = false

    var body: some View {
        Button(action: alTocar) {
            VStack(alignment: .leading, spacing: 2) {
                Spacer(minLength: 0)
                Text(ReglasGuia.textoPlaca(indice, de: total))
                    .font(.caption.weight(.semibold)).tracking(0.8).textCase(.uppercase)
                    .foregroundStyle(Color(red: 0.66, green: 0.85, blue: 0.71))
                if let b = clip.bloque, !b.isEmpty {
                    Text(b).font(.subheadline).foregroundStyle(Color(white: 0.86))
                }
                Text(clip.titulo)
                    .font(.title3.weight(.semibold)).foregroundStyle(.white)
                    .lineLimit(3).minimumScaleFactor(0.75)
                    .padding(.top, 6)
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.2))
                        Capsule().fill(Color(red: 0.36, green: 0.73, blue: 0.45)).frame(width: lleno ? g.size.width : 0)
                    }
                }
                .frame(height: 3)
                .padding(.top, Espacio.s)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Espacio.l)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(Color(red: 0.067, green: 0.094, blue: 0.078))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onAppear { withAnimation(.linear(duration: ReglasGuia.placaSegundos)) { lleno = true } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(ReglasGuia.textoPlaca(indice, de: total)). \(clip.bloque ?? ""). \(clip.titulo)")
        .accessibilityHint("Tocá para empezar ya")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("guia-placa")
    }
}

private struct SinConexionVideo: View {
    let reintentar: () -> Void

    var body: some View {
        VStack(spacing: Espacio.s) {
            Image(systemName: "wifi.slash").font(.title2).foregroundStyle(.white.opacity(0.8))
            Text("Necesitás conexión para ver el video")
                .font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("guia-sin-conexion")
            Button("Reintentar", action: reintentar)
                .buttonStyle(BotonSecundario(compacto: true, tono: .white))
        }
        .padding(Espacio.m)
    }
}
