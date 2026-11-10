import SwiftUI
import AVFoundation
import UIKit
import MyPumpModelos
import MyPumpReglas
import MyPumpDatos

// Fotos y audios en el chat con Mati (2.3.0). Solo aparece con la palanca `chat_adjuntos` prendida y el cliente
// habilitado. Nada en la pantalla dice qué pasa con el archivo después: para el cliente es una foto o un audio que le
// llega a Mati, como por WhatsApp.

// MARK: - La foto o el audio dentro de la burbuja

/// El contenido de una burbuja con adjunto. Se baja (o se toma del teléfono) cuando aparece en pantalla.
struct AdjuntoEnBurbuja: View {
    let mensaje: BurbujaChat
    let adjunto: AdjuntoChat
    let chat: ModeloChat?
    let reproductor: ReproductorChat
    var conCola = true
    var verFoto: (UIImage) -> Void = { _ in }

    var body: some View {
        if adjunto.borrado {
            noDisponible
        } else {
            switch adjunto.tipo {
            case .foto:
                FotoEnBurbuja(mensaje: mensaje, adjunto: adjunto, chat: chat, conCola: conCola, ver: verFoto)
            case .audio:
                AudioEnBurbuja(mensaje: mensaje, adjunto: adjunto, chat: chat, reproductor: reproductor, conCola: conCola)
            }
        }
    }

    private var noDisponible: some View {
        let mio = !mensaje.esDelCoach
        return Label(ReglasChatAdjuntos.textoNoDisponible, systemImage: adjunto.tipo == .foto ? "photo" : "waveform")
            .font(.subheadline.italic())
            .foregroundStyle(mio ? Color.sobreMarca.opacity(0.85) : Color.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background {
                FormaBurbuja(mia: mio, conCola: conCola).fill(mio ? Color.marca.opacity(0.75) : Color.tarjeta)
            }
            .accessibilityIdentifier("chat-adjunto-no-disponible")
    }
}

private struct FotoEnBurbuja: View {
    let mensaje: BurbujaChat
    let adjunto: AdjuntoChat
    let chat: ModeloChat?
    let conCola: Bool
    let ver: (UIImage) -> Void
    @State private var imagen: UIImage?
    @State private var intento = 0
    @ScaledMetric(relativeTo: .body) private var ancho: CGFloat = 228

    var body: some View {
        let lado = min(ancho, 300)
        ZStack {
            if let imagen {
                Image(uiImage: imagen)
                    .resizable()
                    .scaledToFill()
                    .frame(width: lado, height: alto(imagen, lado))
                    .clipped()
            } else {
                Rectangle()
                    .fill(Color.campo)
                    .frame(width: lado, height: lado * 0.75)
                    .overlay {
                        if chat?.sinBajar.contains(adjunto.id) == true {
                            VStack(spacing: 6) {
                                Image(systemName: "arrow.clockwise").font(.title3.weight(.semibold))
                                Text(ReglasChatAdjuntos.textoNoCarga).font(.footnote).multilineTextAlignment(.center)
                            }
                            .foregroundStyle(.secondary)
                            .padding(Espacio.m)
                        } else {
                            ProgressView().tint(.secondary)
                        }
                    }
            }
            if mensaje.pendiente && !mensaje.fallo {
                // Mientras sale: un velo y el reloj, como el «enviando…» del texto.
                Color.black.opacity(0.18)
                ProgressView().tint(.white).controlSize(.large)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.borde, lineWidth: 1) }
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onTapGesture {
            if let imagen { ver(imagen) } else if chat?.sinBajar.contains(adjunto.id) == true { intento += 1 }
        }
        .task(id: "\(adjunto.id)-\(intento)") { await cargar() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ReglasChatAdjuntos.textoFotoAccesible)
        .accessibilityAddTraits(imagen != nil ? [.isImage, .isButton] : .isImage)
        .accessibilityHint(imagen != nil ? "Tocá dos veces para verla grande." : "")
        .accessibilityIdentifier("chat-foto")
    }

    private func alto(_ i: UIImage, _ lado: CGFloat) -> CGFloat {
        guard i.size.width > 0 else { return lado }
        return min(max(lado * i.size.height / i.size.width, lado * 0.56), lado * 1.33)
    }

    private func cargar() async {
        guard imagen == nil, let chat else { return }
        guard let u = await chat.archivo(de: adjunto) else { return }
        // Una miniatura del tamaño de la burbuja: 30 fotos de 1600 px enteras en memoria serían ~300 MB.
        let i = await Task.detached(priority: .userInitiated) { () -> UIImage? in
            guard let d = try? Data(contentsOf: u), let jpeg = ReduccionFoto.jpeg(d, maxPx: 900, calidad: 0.9) else { return nil }
            return UIImage(data: jpeg)
        }.value
        withAnimation(.easeOut(duration: 0.2)) { imagen = i }
    }
}

private struct AudioEnBurbuja: View {
    let mensaje: BurbujaChat
    let adjunto: AdjuntoChat
    let chat: ModeloChat?
    let reproductor: ReproductorChat
    let conCola: Bool
    @State private var cargando = false
    @State private var noSeEscucha = false
    @ScaledMetric(relativeTo: .body) private var ancho: CGFloat = 220
    @ScaledMetric(relativeTo: .body) private var boton: CGFloat = 36

    var body: some View {
        let mio = !mensaje.esDelCoach
        let suena = reproductor.idSonando == adjunto.id
        let total = max(adjunto.duracion ?? reproductor.duracion(adjunto.id) ?? 0, 0)
        let avance = suena && total > 0 ? min(1, reproductor.actual / total) : (reproductor.idCargado == adjunto.id && total > 0 ? min(1, reproductor.actual / total) : 0)
        let frente = mio ? Color.sobreMarca : Color.marcaTexto
        HStack(spacing: Espacio.s) {
            Button { Task { await alternar() } } label: {
                ZStack {
                    Circle().fill(mio ? Color.sobreMarca.opacity(0.2) : Color.marca.opacity(0.14))
                    if cargando {
                        ProgressView().tint(frente)
                    } else {
                        Image(systemName: suena ? "pause.fill" : "play.fill")
                            .font(.system(size: boton * 0.42, weight: .bold))
                            .foregroundStyle(frente)
                            .offset(x: suena ? 0 : 1.5)
                            .contentTransition(.symbolEffect(.replace))
                    }
                }
                .frame(width: max(boton, 36), height: max(boton, 36))
                .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .disabled(noSeEscucha || (mensaje.pendiente && !mensaje.fallo && chat == nil))
            .accessibilityLabel(suena ? ReglasChatAdjuntos.textoPausar : ReglasChatAdjuntos.textoReproducir)
            .accessibilityIdentifier("chat-audio-play")

            VStack(alignment: .leading, spacing: 5) {
                if noSeEscucha {
                    Text(ReglasChatAdjuntos.textoNoSeEscucha).font(.footnote)
                        .foregroundStyle(mio ? Color.sobreMarca : Color.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    BarraAudio(avance: avance, color: frente)
                        .frame(height: 22)
                        .accessibilityHidden(true)
                    Text(ReglasChatAdjuntos.duracion(suena ? max(0, total - reproductor.actual) : total))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(mio ? Color.sobreMarca.opacity(0.85) : Color.secondary)
                }
            }
        }
        .frame(width: min(ancho, 300), alignment: .leading)
        .padding(.leading, 10)
        .padding(.trailing, 14)
        .padding(.vertical, 9)
        .background {
            FormaBurbuja(mia: mio, conCola: conCola)
                .fill(mio ? Color.marca : Color.tarjeta)
                .overlay { if !mio { FormaBurbuja(mia: mio, conCola: conCola).stroke(Color.borde, lineWidth: 1) } }
        }
        .opacity(mensaje.pendiente && !mensaje.fallo ? 0.6 : 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(ReglasChatAdjuntos.textoAudioAccesible(segundos: total))
        .accessibilityIdentifier("chat-audio")
        .task(id: adjunto.id) {
            // Un audio de la web en un formato que el iPhone no reproduce: se dice en vez de un botón que no anda.
            if let f = chat?.formato(de: adjunto), f != ReglasChatAdjuntos.mimeAudio { noSeEscucha = true }
        }
    }

    private func alternar() async {
        if reproductor.idSonando == adjunto.id { reproductor.pausar(); return }
        guard let chat else { return }
        cargando = true
        let u = await chat.archivo(de: adjunto)
        cargando = false
        if let f = chat.formato(de: adjunto), f != ReglasChatAdjuntos.mimeAudio { noSeEscucha = true; return }
        guard let u else { return }
        reproductor.alternar(adjunto.id, u)
    }
}

/// La onda del audio: barras fijas (no hay que analizar el archivo) que se pintan a medida que avanza.
private struct BarraAudio: View {
    let avance: Double
    let color: Color
    private static let alturas: [CGFloat] = [0.35, 0.6, 0.9, 0.55, 0.75, 0.4, 0.95, 0.7, 0.5, 0.85, 0.45, 0.65, 1, 0.6, 0.4, 0.8,
                                             0.55, 0.9, 0.5, 0.7, 0.35, 0.6, 0.85, 0.45, 0.7, 0.5, 0.3]

    var body: some View {
        GeometryReader { g in
            let n = Self.alturas.count
            let paso = g.size.width / CGFloat(n)
            HStack(alignment: .center, spacing: paso * 0.45) {
                ForEach(0..<n, id: \.self) { i in
                    Capsule()
                        .fill(color.opacity(Double(i) / Double(n) < avance ? 1 : 0.35))
                        .frame(width: paso * 0.55, height: max(3, g.size.height * Self.alturas[i]))
                }
            }
            .frame(width: g.size.width, height: g.size.height, alignment: .leading)
        }
        .animation(.linear(duration: 0.25), value: avance)
    }
}

// MARK: - El reproductor del chat (uno a la vez)

@MainActor @Observable
final class ReproductorChat: NSObject, AVAudioPlayerDelegate {
    private(set) var idSonando: String?
    private(set) var idCargado: String?
    private(set) var actual: Double = 0
    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var tics: Task<Void, Never>?
    @ObservationIgnored private var duraciones: [String: Double] = [:]
    @ObservationIgnored private var sesionTomada = false

    func duracion(_ id: String) -> Double? { duraciones[id] }

    func alternar(_ id: String, _ url: URL) {
        if idSonando == id { pausar(); return }
        if idCargado != id || player == nil {
            player?.stop()
            player = try? AVAudioPlayer(contentsOf: url)
            player?.delegate = self
            idCargado = id
            actual = 0
            if let d = player?.duration, d.isFinite { duraciones[id] = d }
        }
        guard let player else { idCargado = nil; return }
        SesionAudio.activar()
        sesionTomada = true
        player.play()
        idSonando = id
        tics?.cancel()
        tics = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                guard let self, let p = self.player else { return }
                self.actual = p.currentTime
            }
        }
    }

    func pausar() {
        player?.pause()
        idSonando = nil
        tics?.cancel()
    }

    /// Al salir del chat o al grabar: se suelta todo, así la música del cliente vuelve.
    func soltar() {
        pausar()
        player = nil
        idCargado = nil
        actual = 0
        if sesionTomada { sesionTomada = false; SesionAudio.soltar() }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.idSonando = nil
            self.actual = 0
            self.tics?.cancel()
            if self.sesionTomada { self.sesionTomada = false; SesionAudio.soltar() }
        }
    }
}

// MARK: - La foto grande

struct FotoParaVer: Identifiable {
    let id = UUID()
    let imagen: UIImage
}

struct VisorFoto: View {
    let foto: FotoParaVer
    let cerrar: () -> Void
    @State private var escala: CGFloat = 1
    @State private var base: CGFloat = 1
    @State private var desplazamiento: CGSize = .zero
    @State private var desplazamientoBase: CGSize = .zero

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            Image(uiImage: foto.imagen)
                .resizable()
                .scaledToFit()
                .scaleEffect(escala)
                .offset(desplazamiento)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .gesture(
                    MagnifyGesture()
                        .onChanged { v in escala = min(5, max(1, base * v.magnification)) }
                        .onEnded { _ in
                            base = escala
                            if escala == 1 { withAnimation(.snappy) { desplazamiento = .zero; desplazamientoBase = .zero } }
                        }
                        .simultaneously(with: DragGesture()
                            .onChanged { v in
                                guard escala > 1 else { return }
                                desplazamiento = CGSize(width: desplazamientoBase.width + v.translation.width,
                                                        height: desplazamientoBase.height + v.translation.height)
                            }
                            .onEnded { v in
                                if escala <= 1, v.translation.height > 120 { cerrar(); return }
                                desplazamientoBase = desplazamiento
                            })
                )
                .onTapGesture(count: 2) {
                    withAnimation(.snappy) {
                        if escala > 1 { escala = 1; base = 1; desplazamiento = .zero; desplazamientoBase = .zero } else { escala = 2.5; base = 2.5 }
                    }
                }
                .accessibilityLabel(ReglasChatAdjuntos.textoFotoAccesible)
                .accessibilityAddTraits(.isImage)
            Button(action: cerrar) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: .circle)
                    .environment(\.colorScheme, .dark)
            }
            .padding(Espacio.m)
            .accessibilityLabel(ReglasChatAdjuntos.textoCerrar)
            .accessibilityIdentifier("chat-visor-cerrar")
        }
        .statusBarHidden()
    }
}

// MARK: - Grabar manteniendo apretado

/// El micrófono del chat: mientras se mantiene apretado graba; al soltar se manda; deslizando a la izquierda se cancela.
/// A los 2 minutos se corta solo y se manda. Con VoiceOver se toca una vez para empezar y otra para mandar.
@MainActor @Observable
final class GrabacionChat {
    enum Estado: Equatable { case quieto, grabando }
    private(set) var estado = Estado.quieto
    private(set) var segundos: Double = 0
    /// El dedo ya pasó el límite de cancelar (se suelta y no sale).
    private(set) var cancelando = false
    /// Arrancó con un toque (VoiceOver): se ven «Cancelar» y «Mandar el audio».
    private(set) var porToque = false
    var aviso: String?
    var sinPermiso = false
    var maximo: Double = ReglasChatAdjuntos.audioMaximo

    @ObservationIgnored private var grabador: any GrabadorAudio
    @ObservationIgnored private var archivo: URL?
    @ObservationIgnored private var inicio = Date()
    @ObservationIgnored private var reloj: Task<Void, Never>?
    @ObservationIgnored var alTerminar: (URL, Double) -> Void = { _, _ in }

    init(grabador: any GrabadorAudio) {
        self.grabador = grabador
        self.grabador.alInterrumpir = { [weak self] in self?.terminar(mandar: true) }
    }

    /// El dedo bajó. false = no empezó (permiso).
    @discardableResult
    func empezar(porToque: Bool = false) -> Bool {
        guard estado == .quieto else { return false }
        switch grabador.permiso {
        case .negado:
            sinPermiso = true
            return false
        case .sinPreguntar:
            // La primera vez el permiso del sistema tapa el dedo: se pide y la próxima graba.
            Task { _ = await grabador.pedirPermiso() }
            return false
        case .dado:
            break
        }
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("chat-\(UUID().uuidString).m4a")
        if let a = grabador.empezar(en: u) {
            aviso = ReglasAudioDuda.texto(a)
            return false
        }
        archivo = u
        inicio = Date()
        segundos = 0
        cancelando = false
        self.porToque = porToque
        estado = .grabando
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        reloj = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard let self, self.estado == .grabando else { return }
                self.segundos = Date().timeIntervalSince(self.inicio)
                if self.segundos >= self.maximo { self.terminar(mandar: true); return }
            }
        }
        return true
    }

    func mover(_ dx: CGFloat) {
        guard estado == .grabando, !porToque else { return }
        let ahora = -dx > ReglasChatAdjuntos.deslizarParaCancelar
        if ahora != cancelando {
            cancelando = ahora
            UISelectionFeedbackGenerator().selectionChanged()
        }
    }

    func terminar(mandar: Bool) {
        guard estado == .grabando else { return }
        reloj?.cancel()
        grabador.terminar()
        let s = Date().timeIntervalSince(inicio)
        estado = .quieto
        porToque = false
        let enviar = mandar && !cancelando
        cancelando = false
        guard let archivo else { return }
        self.archivo = nil
        if enviar {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            alTerminar(archivo, min(s, maximo))
        } else {
            try? FileManager.default.removeItem(at: archivo)
        }
    }
}

/// La barra que reemplaza al campo mientras se graba: el punto rojo, el tiempo y «Deslizá para cancelar».
struct BarraGrabando: View {
    let grabacion: GrabacionChat
    @State private var latido = false

    var body: some View {
        HStack(spacing: Espacio.s) {
            Circle()
                .fill(Color.peligro)
                .frame(width: 10, height: 10)
                .opacity(latido ? 0.25 : 1)
                .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: latido)
                .onAppear { latido = true }
                .accessibilityHidden(true)
            Text(ReglasChatAdjuntos.duracion(grabacion.segundos))
                .font(.body.monospacedDigit().weight(.semibold))
                .contentTransition(.numericText())
                .accessibilityLabel("Grabando, \(ReglasChatAdjuntos.duracionHablada(grabacion.segundos))")
            Spacer(minLength: Espacio.xs)
            if grabacion.porToque {
                Button(ReglasChatAdjuntos.textoCancelar) { grabacion.terminar(mandar: false) }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.peligro)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("chat-grabar-cancelar")
            } else if grabacion.segundos >= ReglasChatAdjuntos.audioAviso {
                Text(ReglasChatAdjuntos.textoQuedanDiez).font(.footnote.weight(.semibold)).foregroundStyle(Color.peligro)
            } else {
                Label(ReglasChatAdjuntos.textoDeslizarParaCancelar, systemImage: "chevron.left")
                    .labelStyle(EtiquetaCompacta())
                    .font(.footnote)
                    .foregroundStyle(grabacion.cancelando ? Color.peligro : Color.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .padding(.horizontal, Espacio.m)
        .frame(minHeight: 44)
        .vidrio(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("chat-grabando")
    }
}

/// El botón del micrófono (con el campo vacío ocupa el lugar de Enviar, como en WhatsApp).
struct BotonMicrofono: View {
    let grabacion: GrabacionChat
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @State private var apretado = false

    var body: some View {
        let graba = grabacion.estado == .grabando
        Image(systemName: graba ? (grabacion.porToque ? "arrow.up" : "mic.fill") : "mic")
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(graba ? Color.sobreMarca : Color.marcaTexto)
            .frame(width: 44, height: 44)
            .background { if graba { Circle().fill(grabacion.cancelando ? Color.peligro : Color.marca) } }
            .vidrio(Circle(), interactivo: true)
            .scaleEffect(graba && !grabacion.porToque ? 1.35 : 1)
            .animation(.snappy(duration: 0.2), value: graba)
            .contentShape(.circle)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        guard !voiceOver, !grabacion.porToque else { return }
                        if !apretado {
                            apretado = true
                            grabacion.empezar()
                        } else {
                            grabacion.mover(v.translation.width)
                        }
                    }
                    .onEnded { _ in
                        guard !voiceOver, !grabacion.porToque else { return }
                        apretado = false
                        grabacion.terminar(mandar: true)
                    }
            )
            .accessibilityElement()
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(graba ? ReglasChatAdjuntos.textoMandarAudioAccesible : ReglasChatAdjuntos.textoGrabarAccesible)
            .accessibilityHint(graba ? "" : ReglasChatAdjuntos.ayudaGrabarAccesible)
            .accessibilityAction {
                if graba { grabacion.terminar(mandar: true) } else { grabacion.empezar(porToque: true) }
            }
            .accessibilityIdentifier("chat-microfono")
            .help(ReglasChatAdjuntos.textoMantenerParaGrabar)
    }
}

/// El botón de la foto, a la izquierda del campo: «Sacar una foto» o «Elegir de tus fotos».
struct BotonFotoChat: View {
    let alElegir: (Data) -> Void

    var body: some View {
        BotonFoto(maxPx: CGFloat(ReglasChatAdjuntos.fotoLadoMaximo), calidad: 0.92, alElegir: alElegir) {
            Image(systemName: "camera")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.marcaTexto)
                .frame(width: 44, height: 44)
                .vidrio(Circle(), interactivo: true)
                .contentShape(.circle)
        }
        .accessibilityLabel(ReglasChatAdjuntos.textoAdjuntar)
        .accessibilityIdentifier("chat-foto-boton")
    }
}

#if DEBUG
// MARK: - Pruebas de interfaz y capturas (`-chatAdjuntosDePrueba YES`)

/// Un chat de mentira con fotos y audios (sin cuenta ni red): el hilo armado, la cola y mini-vision simulados. Para las
/// pruebas de interfaz y las capturas en claro y oscuro. Nunca toca la base.
@MainActor enum ChatAdjuntosUI {
    static var activo: Bool { UserDefaults.standard.bool(forKey: "chatAdjuntosDePrueba") }

    private static var creado: ModeloChat??

    /// Se arma una sola vez (la pantalla lo pide en cada dibujo).
    static var modelo: ModeloChat? {
        if let c = creado { return c }
        let m = activo ? crear() : nil
        creado = .some(m)
        return m
    }

    private static func crear() -> ModeloChat {
        let s = ServidorChatUI()
        let cliente = ClienteRPC(transporte: s)
        let raiz = FileManager.default.temporaryDirectory.appendingPathComponent("chat-ui-\(UUID().uuidString)", isDirectory: true)
        let carpeta = raiz.appendingPathComponent("chat-adjuntos", isDirectory: true)
        let escrituras = Escrituras(cliente: cliente, token: "token-ui", carpetaAudios: raiz.appendingPathComponent("audios"))
        let cola = Outbox(archivo: nil) { await escrituras.ejecutar($0) }
        let m = ModeloChat(cliente: cliente, token: "token-ui", outbox: cola, carpetaAdjuntos: carpeta)
        Task {
            await cola.observar(estado: { _ in }, abandonadas: { ops in Task { @MainActor in await m.alAbandonarAdjuntos(ops) } },
                                guardadas: { ops in Task { @MainActor in m.alGuardarAdjuntos(ops) } })
            await m.consultarAdjuntos(palanca: true)
            await m.cargar()
            if UserDefaults.standard.bool(forKey: "chatAdjuntosConFallo") {
                s.rechazar = true
                _ = await m.enviarFoto(ServidorChatUI.foto(tono: 0.55))
                await cola.drenarAudios()   // en la app lo dispara ModeloApp; acá no hay quien
            }
        }
        return m
    }

    static var grabador: any GrabadorAudio { UserDefaults.standard.bool(forKey: "audioDoble") || activo ? GrabadorDobleUI() : GrabadorAV() }
}

/// mini-vision y la base de mentira: un hilo con una foto y un audio del cliente, una foto que ya no está, y la subida.
final class ServidorChatUI: Transporte, @unchecked Sendable {
    private let cerrojo = NSLock()
    private var _rechazar = false
    var rechazar: Bool { get { cerrojo.withLock { _rechazar } } set { cerrojo.withLock { _rechazar = newValue } } }
    static let idFoto = "6f1b8a52-6a0e-4d3b-9b8f-0a1c2d3e4f50"
    static let idAudio = "7a2c9b63-7b1f-4e4c-8c90-1b2d3e4f5061"
    static let idBorrado = "8b3dac74-8c20-4f5d-9da1-2c3e4f506172"

    func enviar(_ pedido: URLRequest) async throws -> (Data, URLResponse) {
        try? await Task.sleep(for: .milliseconds(400))
        let ruta = pedido.url?.path ?? ""
        let (status, cuerpo): (Int, Data)
        if ruta.hasSuffix("mypump_chat_adjuntos_estado") {
            (status, cuerpo) = (200, Data(#"{"habilitado":true,"audio_max_s":120}"#.utf8))
        } else if ruta.hasSuffix("mypump_get_chat") {
            (status, cuerpo) = (200, Data(Self.hilo.utf8))
        } else if ruta.hasSuffix("/chat/adjunto") {
            try? await Task.sleep(for: .seconds(1.5))
            (status, cuerpo) = rechazar ? (429, Data(#"{"ok":false,"error":"muchos adjuntos por hoy"}"#.utf8))
                : (200, Data(#"{"ok":true,"ya":false,"comentario_id":"\#(UUID().uuidString.lowercased())","created_at":"\#(FechaISO.texto(Date()))"}"#.utf8))
        } else if ruta.hasSuffix("/chat/urls") {
            let filas = [(Self.idFoto, "foto", "image/jpeg"), (Self.idAudio, "audio", "audio/mp4")]
                .map { #"{"id":"\#($0.0)","tipo":"\#($0.1)","mime":"\#($0.2)","url":"https://adjuntos.invalid/\#($0.0)"}"# }
            (status, cuerpo) = (200, Data(#"{"ok":true,"adjuntos":[\#(filas.joined(separator: ","))],"expira_en":3600}"#.utf8))
        } else if ruta.hasSuffix(Self.idFoto) {
            (status, cuerpo) = (200, Self.foto(tono: 0.35))
        } else if ruta.hasSuffix(Self.idAudio) {
            let u = FileManager.default.temporaryDirectory.appendingPathComponent("tono-ui-\(UUID().uuidString).m4a")
            await MainActor.run { GrabadorDobleUI.escribirTono(en: u, segundos: 7) }
            (status, cuerpo) = (200, (try? Data(contentsOf: u)) ?? Data())
        } else {
            (status, cuerpo) = (200, Data("[]".utf8))
        }
        return (cuerpo, HTTPURLResponse(url: pedido.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }

    func subir(_ pedido: URLRequest, archivo: URL) async throws -> (Data, URLResponse) { try await enviar(pedido) }

    private static var hilo: String {
        let hoy = Date()
        func iso(_ min: Double) -> String { FechaISO.texto(hoy.addingTimeInterval(-min * 60)) }
        return """
        [{"id":"u1","autor":"coach","contenido":"¿Cómo te fue con la sentadilla hoy?","leido_por_cliente":true,"created_at":"\(iso(42))"},
         {"id":"u2","autor":"cliente","contenido":"Bien, mirá cómo quedó la barra","leido_por_cliente":true,"created_at":"\(iso(40))"},
         {"id":"u3","autor":"cliente","contenido":"Foto","leido_por_cliente":true,"created_at":"\(iso(39))","adjunto":{"id":"\(idFoto)","tipo":"foto"}},
         {"id":"u4","autor":"cliente","contenido":"Audio de 0:07","leido_por_cliente":true,"created_at":"\(iso(38))","adjunto":{"id":"\(idAudio)","tipo":"audio","duracion_s":7}},
         {"id":"u5","autor":"coach","contenido":"Muy bien. La próxima subí 2,5 kg y seguí al fallo.","leido_por_cliente":true,"created_at":"\(iso(20))"},
         {"id":"u6","autor":"cliente","contenido":"Foto","leido_por_cliente":true,"created_at":"\(iso(5))","adjunto":{"id":"\(idBorrado)","tipo":"foto","borrado":true}}]
        """
    }

    /// Una foto de muestra dibujada (sin personas ni datos): un degradé con una barra.
    static func foto(tono: Double) -> Data {
        let r = UIGraphicsImageRenderer(size: CGSize(width: 1200, height: 900))
        let img = r.image { c in
            let colores = [UIColor(hue: tono, saturation: 0.45, brightness: 0.55, alpha: 1).cgColor,
                           UIColor(hue: tono + 0.08, saturation: 0.35, brightness: 0.85, alpha: 1).cgColor] as CFArray
            let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colores, locations: [0, 1])!
            c.cgContext.drawLinearGradient(g, start: .zero, end: CGPoint(x: 1200, y: 900), options: [])
            UIColor(white: 0.15, alpha: 0.9).setFill()
            c.fill(CGRect(x: 120, y: 420, width: 960, height: 40))
            UIColor(white: 0.1, alpha: 0.95).setFill()
            for x in [140, 220, 920, 1000] { c.fill(CGRect(x: x, y: 330, width: 60, height: 220)) }
        }
        return img.jpegData(compressionQuality: 0.85) ?? Data()
    }
}
#endif
