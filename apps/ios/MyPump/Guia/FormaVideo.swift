import AVFoundation
import SwiftUI
import UIKit
import MyPumpReglas
import MyPumpDatos

/// La forma del clip cargado (ancho sobre alto), para que el cuadro tome la del video y nunca queden franjas negras
/// (pedido de Mati del 6/11). Arranca con la última conocida de ese clip (guardada por id) o 16:9; la lee de la pista
/// (`naturalSize` con `preferredTransform`) apenas se elige el clip, aunque todavía esté la portada, y la confirma con
/// `presentationSize` cuando el video corre.
///
/// Además mira si el archivo trae el negro adentro (una grabación vertical metida en un 1280×720): toma 4 cuadros chicos
/// (al 30, 50, 70 y 90 %: desde el 30 % para saltear la placa del título del principio, que es texto a lo ancho sobre
/// negro y agrandaría la zona), busca lo que no es negro y, si ocupa menos del 92 % del ancho o del alto, el cuadro toma la forma
/// de esa zona y el video se recorta a ella. El resultado queda guardado por clip. Si algo falla, la del archivo.
@MainActor @Observable
final class FormaVideo {
    /// La proporción del archivo (sin recorte).
    private(set) var archivo: Double = ReglasVideo.proporcionPorDefecto
    /// La zona útil, si el archivo trae franjas (nil: se ve entero).
    private(set) var recorte: RecuadroVideo?
    /// La que toma el cuadro.
    var proporcion: Double { ReglasVideo.proporcion(archivo: archivo, recorte: recorte) }

    @ObservationIgnored private var id: String?
    @ObservationIgnored private var tarea: Task<Void, Never>?
    @ObservationIgnored private var observador: NSKeyValueObservation?
    @ObservationIgnored private let guardadas = ProporcionesVideo()

    init() {
        #if DEBUG
        // Pruebas: `-guiaOlvidarFormas YES` arranca sin nada medido.
        if UserDefaults.standard.bool(forKey: "guiaOlvidarFormas") { ProporcionesVideo().olvidarTodo() }
        #endif
    }

    /// Se eligió otro clip: lo guardado (o 16:9 sin recorte) ya, y lo real en cuanto se lee.
    func preparar(id nuevo: String, url: URL?) {
        guard nuevo != id else { return }
        id = nuevo
        tarea?.cancel()
        observador = nil
        archivo = guardadas.proporcion(nuevo) ?? ReglasVideo.proporcionPorDefecto
        let medido = url.flatMap { guardadas.recuadro(nuevo, url: $0) }
        recorte = ReglasVideo.recorte(medido)
        guard let url else { return }
        tarea = Task { [weak self] in
            let asset = AVURLAsset(url: url)
            guard let pista = try? await asset.loadTracks(withMediaType: .video).first,
                  let datos = try? await pista.load(.naturalSize, .preferredTransform),
                  !Task.isCancelled else { return }
            if let p = ReglasVideo.proporcion(ancho: datos.0.width, alto: datos.0.height, transformacion: datos.1) {
                self?.fijar(p, id: nuevo)
            }
            guard medido == nil, let r = await Self.medir(asset), !Task.isCancelled else { return }
            self?.fijar(r, id: nuevo, url: url)
        }
    }

    /// El item que se reproduce: su `presentationSize` (ya girado) manda en la del archivo.
    func observar(_ item: AVPlayerItem, id clip: String) {
        observador = item.observe(\.presentationSize, options: [.initial, .new]) { [weak self] it, _ in
            let s = it.presentationSize
            Task { @MainActor in
                guard let p = ReglasVideo.proporcion(ancho: s.width, alto: s.height) else { return }
                self?.fijar(p, id: clip)
            }
        }
    }

    private func fijar(_ p: Double, id clip: String) {
        guard clip == id else { return }
        if abs(p - archivo) > 0.005 { withAnimation(.easeInOut(duration: 0.35)) { archivo = p } }
        guardadas.guardar(p, para: clip)
    }

    private func fijar(_ r: RecuadroVideo, id clip: String, url: URL) {
        guardadas.guardar(r, para: clip, url: url)
        guard clip == id else { return }
        let nuevo = ReglasVideo.recorte(r)
        if nuevo != recorte { withAnimation(.easeInOut(duration: 0.35)) { recorte = nuevo } }
    }

    /// Cuatro cuadros chicos (al 30, 50, 70 y 90 %), ya girados: la unión de lo que no es negro. `.entero` si no hay nada que
    /// medir de más (un video negro entero no se recorta); nil si no se pudo leer (se prueba la próxima vez).
    nonisolated private static func medir(_ asset: AVURLAsset) async -> RecuadroVideo? {
        guard let dur = try? await asset.load(.duration), dur.seconds.isFinite, dur.seconds > 0 else { return nil }
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 320, height: 320)
        gen.requestedTimeToleranceBefore = CMTime(seconds: 0.5, preferredTimescale: 600)
        gen.requestedTimeToleranceAfter = CMTime(seconds: 0.5, preferredTimescale: 600)
        var rs: [RecuadroVideo] = []
        var leidos = 0
        for f in [0.3, 0.5, 0.7, 0.9] {
            guard let img = try? await gen.image(at: CMTime(seconds: dur.seconds * f, preferredTimescale: 600)).image else { continue }
            leidos += 1
            if let r = recuadro(img) { rs.append(r) }
        }
        guard leidos > 0 else { return nil }
        return ReglasVideo.unir(rs) ?? .entero
    }

    nonisolated private static func recuadro(_ img: CGImage) -> RecuadroVideo? {
        let w = img.width, h = img.height
        guard w > 0, h > 0 else { return nil }
        var luma = [UInt8](repeating: 0, count: w * h)
        let ok: Bool = luma.withUnsafeMutableBytes { b in
            guard let ctx = CGContext(data: b.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        return ok ? ReglasVideo.recuadro(luma: luma, ancho: w, alto: h) : nil
    }
}

/// El cuadro con la forma del clip: a todo el ancho si entra; los verticales hasta el 60 % del alto visible,
/// centrados, con el fondo de la tarjeta a los costados (nunca negro).
struct CuadroConForma<Contenido: View>: View {
    let proporcion: Double
    @ViewBuilder let contenido: () -> Contenido
    @State private var ancho: CGFloat = 0

    var body: some View {
        let t = ReglasVideo.cuadro(proporcion: proporcion, anchoDisponible: ancho, altoPantalla: Self.altoPantalla)
        Group {
            if ancho > 0 {
                Color.clear
                    .frame(maxWidth: .infinity)
                    .frame(height: t.height)
                    .overlay { contenido().frame(width: t.width, height: t.height).clipped() }
            } else {
                // El primer pase, antes de saber el ancho: la proporción sola, sin el tope.
                Color.clear.aspectRatio(proporcion, contentMode: .fit).frame(maxWidth: .infinity)
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { ancho = $0 }
        .animation(.easeInOut(duration: 0.25), value: proporcion)
    }

    /// El alto que se ve de la guía: la ventana sin las zonas seguras ni las barras de navegación (44) y de pestañas (49).
    /// El tope del 60 % es sobre esto, así el cuadro entra entero en pantalla.
    static var altoPantalla: Double {
        let escena = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        guard let v = escena?.windows.first(where: \.isKeyWindow) ?? escena?.windows.first else { return 600 }
        return max(300, Double(v.bounds.height - v.safeAreaInsets.top - v.safeAreaInsets.bottom) - 44 - 49)
    }
}

#if DEBUG
/// `-guiaFormatos YES` (con `-guiaMuestra YES`): tres MP4 chicos hechos acá mismo, sin clips de clientes. MC-7a
/// vertical (570×720, grabado acostado y con la pista girada, como sale de un teléfono), MC-13c horizontal (1280×720) y
/// FT-26a cuadrado (720×720); el «Ver por qué» de la citrulina (FT-1b), también vertical.
enum VideosDePrueba {
    static let formatos: [String: (ancho: Int, alto: Int, girado: Bool)] = [
        "MC-7a": (720, 570, true), "MC-13c": (1280, 720, false), "FT-26a": (720, 720, false), "FT-1b": (720, 570, true),
    ]

    static var activo: Bool { UserDefaults.standard.bool(forKey: "guiaFormatos") }

    /// La URL local del clip de prueba (lo arma si no está).
    static func url(_ id: String) -> URL? {
        guard let f = formatos[id] else { return nil }
        let destino = FileManager.default.temporaryDirectory
            .appendingPathComponent("formato30-\(f.ancho)x\(f.alto)\(f.girado ? "-girado" : "").mp4")
        if FileManager.default.fileExists(atPath: destino.path) { return destino }
        return armar(destino, ancho: f.ancho, alto: f.alto, girado: f.girado) ? destino : nil
    }

    /// 30 s (un cuadro por segundo, así no termina en medio de la prueba ni tarda en armarse) de un degradé verde.
    private static func armar(_ destino: URL, ancho: Int, alto: Int, girado: Bool) -> Bool {
        guard let w = try? AVAssetWriter(outputURL: destino, fileType: .mp4) else { return false }
        let entrada = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: ancho, AVVideoHeightKey: alto,
        ])
        if girado { entrada.transform = CGAffineTransform(rotationAngle: .pi / 2) }
        let adaptador = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: entrada, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: ancho, kCVPixelBufferHeightKey as String: alto,
        ])
        w.add(entrada)
        guard w.startWriting() else { return false }
        w.startSession(atSourceTime: .zero)
        for cuadro in 0...30 {
            while !entrada.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.005) }
            guard let pool = adaptador.pixelBufferPool else { return false }
            var b: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &b)
            guard let b else { return false }
            pintar(b, ancho: ancho, alto: alto, cuadro: cuadro)
            adaptador.append(b, withPresentationTime: CMTime(value: CMTimeValue(cuadro), timescale: 1))
        }
        entrada.markAsFinished()
        let listo = DispatchSemaphore(value: 0)
        w.finishWriting { listo.signal() }
        listo.wait()
        return w.status == .completed
    }

    private static func pintar(_ b: CVPixelBuffer, ancho: Int, alto: Int, cuadro: Int) {
        CVPixelBufferLockBaseAddress(b, [])
        defer { CVPixelBufferUnlockBaseAddress(b, []) }
        guard let base = CVPixelBufferGetBaseAddress(b) else { return }
        let fila = CVPixelBufferGetBytesPerRow(b)
        let p = base.assumingMemoryBound(to: UInt8.self)
        for y in 0..<alto {
            for x in 0..<ancho {
                let i = y * fila + x * 4
                // BGRA: verde de la marca con un degradé suave que corre con el tiempo.
                p[i] = UInt8(70 + (x + cuadro * 4) % 60)
                p[i + 1] = UInt8(150 + (y * 60 / max(alto, 1)))
                p[i + 2] = 60
                p[i + 3] = 255
            }
        }
    }
}
#endif
