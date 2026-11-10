#if canImport(AVFoundation) && !os(watchOS)
@preconcurrency import AVFoundation
import Foundation
import MyPumpReglas

/// Deja el video listo para subir: 720p, H.264, sin audio y sin metadatos. Todo de disco a disco: un video grande no pasa por memoria.
/// Si la conversión falla y el original entra en el tope, va el original (el servidor saca audio y metadatos igual).
public enum CompresorVideo {
    public struct Listo: Equatable, Sendable {
        public let archivo: URL
        public let duracion: Double
        public let bytes: Int64
        public init(archivo: URL, duracion: Double, bytes: Int64) { self.archivo = archivo; self.duracion = duracion; self.bytes = bytes }
    }
    public enum Resultado: Equatable, Sendable { case listo(Listo), rechazado(Tecnica.Rechazo) }

    private static let prefijo = "tecnica-listo-"

    /// Lo que quedó de una preparación anterior que no llegó a la cola.
    public static func barrer() {
        let t = FileManager.default.temporaryDirectory
        for f in (try? FileManager.default.contentsOfDirectory(atPath: t.path)) ?? [] where f.hasPrefix(prefijo) {
            try? FileManager.default.removeItem(at: t.appendingPathComponent(f))
        }
    }

    public static func preparar(entrada: URL, topes: TopesTecnica) async -> Resultado {
        let asset = AVURLAsset(url: entrada)
        guard let duracion = try? await asset.load(.duration).seconds, duracion.isFinite, duracion > 0,
              let pista = try? await asset.loadTracks(withMediaType: .video).first else { return .rechazado(.ilegible) }
        if duracion < topes.duracionMinS { return .rechazado(.corto) }
        if duracion > topes.duracionMaxS + 0.5 { return .rechazado(.largo) }
        let salida = FileManager.default.temporaryDirectory.appendingPathComponent("\(prefijo)\(UUID().uuidString).mp4")
        if await convertir(asset: asset, pista: pista, a: salida), let b = bytes(salida) {
            if let r = Tecnica.validar(duracion: duracion, bytes: b, topes: topes) {
                try? FileManager.default.removeItem(at: salida)
                return .rechazado(r)
            }
            return .listo(Listo(archivo: salida, duracion: duracion, bytes: b))
        }
        try? FileManager.default.removeItem(at: salida)
        guard let b = bytes(entrada) else { return .rechazado(.ilegible) }
        if let r = Tecnica.validar(duracion: duracion, bytes: b, topes: topes) { return .rechazado(r) }
        do { try FileManager.default.copyItem(at: entrada, to: salida) } catch { return .rechazado(.ilegible) }
        return .listo(Listo(archivo: salida, duracion: duracion, bytes: b))
    }

    private static func bytes(_ u: URL) -> Int64? {
        ((try? FileManager.default.attributesOfItem(atPath: u.path))?[.size] as? NSNumber)?.int64Value
    }

    private static func convertir(asset: AVAsset, pista: AVAssetTrack, a salida: URL) async -> Bool {
        let c = AVMutableComposition()
        guard let destino = c.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let rango = try? await pista.load(.timeRange),
              (try? destino.insertTimeRange(rango, of: pista, at: .zero)) != nil else { return false }
        destino.preferredTransform = (try? await pista.load(.preferredTransform)) ?? .identity
        guard let e = AVAssetExportSession(asset: c, presetName: AVAssetExportPreset1280x720) else { return false }
        e.outputURL = salida
        e.outputFileType = .mp4
        e.shouldOptimizeForNetworkUse = true
        e.metadata = []
        await e.export()
        return e.status == .completed
    }
}
#endif
