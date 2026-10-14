import Foundation
import CoreGraphics
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import MyPumpDatos

/// REV-02: lo que sale del teléfono es un JPEG con el lado mayor ≤ 900 px (fotos de progreso, calidad 0,7), con la
/// orientación de la cámara aplicada y sin EXIF ni ubicación. Las fotos se arman acá con CoreGraphics.
@Suite("Fotos: reducción a JPEG sin metadatos")
struct ReduccionFotoTests {
    /// Una imagen con ruido (determinístico), para que la compresión tenga trabajo.
    static func imagen(_ ancho: Int, _ alto: Int) -> CGImage {
        let ctx = CGContext(data: nil, width: ancho, height: alto, bitsPerComponent: 8, bytesPerRow: ancho * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        var semilla: UInt32 = 12345
        let p = ctx.data!.bindMemory(to: UInt8.self, capacity: ancho * alto * 4)
        for i in 0..<(ancho * alto * 4) {
            semilla = semilla &* 1_103_515_245 &+ 12345
            p[i] = UInt8(truncatingIfNeeded: (semilla >> 16) % 256 / 2 + UInt32((i / 4) % ancho * 128 / max(1, ancho)))
        }
        return ctx.makeImage()!
    }

    /// Codifica con las propiedades de una foto de iPhone: orientación y GPS.
    static func archivo(_ img: CGImage, tipo: UTType = .jpeg, orientacion: Int = 1, conGPS: Bool = true) -> Data? {
        let salida = NSMutableData()
        guard let d = CGImageDestinationCreateWithData(salida as CFMutableData, tipo.identifier as CFString, 1, nil) else { return nil }
        var props: [CFString: Any] = [kCGImagePropertyOrientation: orientacion, kCGImageDestinationLossyCompressionQuality: 0.95]
        if conGPS {
            props[kCGImagePropertyGPSDictionary] = [kCGImagePropertyGPSLatitude: 34.6, kCGImagePropertyGPSLatitudeRef: "S",
                                                    kCGImagePropertyGPSLongitude: 58.4, kCGImagePropertyGPSLongitudeRef: "W"]
            props[kCGImagePropertyExifDictionary] = [kCGImagePropertyExifUserComment: "foto de prueba"]
        }
        CGImageDestinationAddImage(d, img, props as CFDictionary)
        return CGImageDestinationFinalize(d) ? salida as Data : nil
    }

    static func propiedades(_ datos: Data) -> (ancho: Int, alto: Int, props: [CFString: Any], tipo: String?) {
        let f = CGImageSourceCreateWithData(datos as CFData, nil)!
        let p = CGImageSourceCopyPropertiesAtIndex(f, 0, nil) as? [CFString: Any] ?? [:]
        return ((p[kCGImagePropertyPixelWidth] as? Int) ?? 0, (p[kCGImagePropertyPixelHeight] as? Int) ?? 0, p,
                CGImageSourceGetType(f) as String?)
    }

    @Test func unaFotoDeCamaraSaleChicaDerechaYSinUbicacion() throws {
        // 4032×3024 apaisada con orientación 6: en pantalla es vertical (3024×4032).
        let original = try #require(Self.archivo(Self.imagen(4032, 3024), orientacion: 6))
        #expect(Self.propiedades(original).props[kCGImagePropertyGPSDictionary] != nil)
        let jpeg = try #require(ReduccionFoto.jpeg(original, maxPx: 900, calidad: 0.7))
        let r = Self.propiedades(jpeg)
        #expect(r.tipo == UTType.jpeg.identifier)
        #expect(r.ancho == 675 && r.alto == 900, "quedó \(r.ancho)×\(r.alto)")
        #expect(r.props[kCGImagePropertyGPSDictionary] == nil, "salió con la ubicación")
        #expect((r.props[kCGImagePropertyOrientation] as? Int ?? 1) == 1, "la orientación no quedó aplicada")
        let exif = r.props[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        #expect(exif[kCGImagePropertyExifUserComment] == nil, "salió con el EXIF de la original")
    }

    @Test func unaHEICTambien() throws {
        // Si la Mac no puede codificar HEIC, no hay contra qué probar.
        guard let heic = Self.archivo(Self.imagen(3000, 2000), tipo: .heic) else { return }
        let jpeg = try #require(ReduccionFoto.jpeg(heic, maxPx: 900, calidad: 0.7))
        let r = Self.propiedades(jpeg)
        #expect(r.tipo == UTType.jpeg.identifier && r.ancho == 900 && r.alto == 600)
        #expect(r.props[kCGImagePropertyGPSDictionary] == nil)
    }

    @Test func unaMasChicaNoSeAgranda() throws {
        let original = try #require(Self.archivo(Self.imagen(400, 300), conGPS: false))
        let r = Self.propiedades(try #require(ReduccionFoto.jpeg(original, maxPx: 900, calidad: 0.7)))
        #expect(r.ancho == 400 && r.alto == 300)
    }

    @Test func laCalidadPesa() throws {
        let original = try #require(Self.archivo(Self.imagen(1600, 1200), conGPS: false))
        let a = try #require(ReduccionFoto.jpeg(original, maxPx: 900, calidad: 0.7))
        let b = try #require(ReduccionFoto.jpeg(original, maxPx: 900, calidad: 0.95))
        #expect(a.count < b.count, "0,7 pesa \(a.count) y 0,95 \(b.count)")
    }

    @Test func loQueNoEsUnaImagenDaNil() {
        #expect(ReduccionFoto.jpeg(Data("no es una foto".utf8), maxPx: 900, calidad: 0.7) == nil)
        #expect(ReduccionFoto.jpeg(Data(), maxPx: 900, calidad: 0.7) == nil)
    }
}
