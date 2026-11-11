import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Testing
import MyPumpReglas
@testable import MyPumpDatos

/// La foto real pasa por el mismo control que fijan los vectores: acá se prueba el camino entero (JPEG → medida → problemas).
struct PreparacionFotoInicioTests {
    private let ahora = Date(timeIntervalSince1970: 1_794_313_800)

    private func preparada(_ escenario: String) -> FotoInicioPreparada? {
        FotoSinteticaFotosInicio.jpeg(escenario).flatMap { PreparacionFotoInicio.preparar($0, ahora: ahora) }
    }

    @Test func lasCuatroDePrueba() throws {
        let buena = try #require(preparada("buena"))
        #expect(buena.ancho == 1200 && buena.alto == 1600)
        #expect(buena.problemas(pose: "frente").isEmpty)
        #expect(buena.dias == nil && buena.tomadaEn == ahora)
        #expect(DobleFotosInicio.jpegEntero(buena.jpeg))
        #expect(DobleFotosInicio.medidas(buena.jpeg) == (1200, 1600))
        #expect(try #require(preparada("oscura")).problemas(pose: "frente") == [.oscura])
        #expect(try #require(preparada("movida")).problemas(pose: "perfil") == [.movida])
        let chica = try #require(preparada("chica")).problemas(pose: "espalda")
        #expect(chica.contains(.chica) && FotosInicio.bloquea(chica))
        #expect(try #require(preparada("chica")).problemas(pose: FotosInicio.motivacion).isEmpty, "en motivación alcanza con 320 px")
        #expect(PreparacionFotoInicio.preparar(Data([1, 2, 3])) == nil)
    }

    /// Una foto grande y acostada con EXIF: se achica a 1600, pierde los metadatos y conserva la fecha.
    @Test func reduceSacaElExifYLeeLaFecha() throws {
        let espacio = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let c = try #require(CGContext(data: nil, width: 3200, height: 2400, bitsPerComponent: 8, bytesPerRow: 0, space: espacio, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        c.setFillColor(CGColor(colorSpace: espacio, components: [0.7, 0.7, 0.7, 1])!); c.fill(CGRect(x: 0, y: 0, width: 3200, height: 2400))
        let salida = NSMutableData()
        let d = try #require(CGImageDestinationCreateWithData(salida as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil))
        let props: [CFString: Any] = [
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: "2026:10:30 10:00:00", kCGImagePropertyExifOffsetTimeOriginal: "-03:00"] as [CFString: Any],
            kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 34.6, kCGImagePropertyGPSLatitudeRef: "S"] as [CFString: Any],
        ]
        CGImageDestinationAddImage(d, try #require(c.makeImage()), props as CFDictionary)
        #expect(CGImageDestinationFinalize(d))
        let original = salida as Data
        #expect(PreparacionFotoInicio.fechaExif(original) == ISO8601DateFormatter().date(from: "2026-10-30T10:00:00-03:00"))
        let p = try #require(PreparacionFotoInicio.preparar(original, ahora: ahora))
        #expect(p.ancho == 1600 && p.alto == 1200)
        #expect(p.dias == 10)
        #expect(p.problemas(pose: "frente").contains(.apaisada) && p.problemas(pose: "frente").contains(.vieja))
        let f = try #require(CGImageSourceCreateWithData(p.jpeg as CFData, nil))
        let limpias = CGImageSourceCopyPropertiesAtIndex(f, 0, nil) as? [CFString: Any] ?? [:]
        #expect(limpias[kCGImagePropertyGPSDictionary] == nil)
        #expect((limpias[kCGImagePropertyExifDictionary] as? [CFString: Any])?[kCGImagePropertyExifDateTimeOriginal] == nil)
        #expect(PreparacionFotoInicio.fechaExif(p.jpeg) == nil)
    }

    @Test func fechas() {
        let utc = TimeZone(secondsFromGMT: 0)!
        #expect(PreparacionFotoInicio.fecha("2026:11:09 10:00:00", desfase: "+02:00", zona: utc) == ISO8601DateFormatter().date(from: "2026-11-09T08:00:00Z"))
        #expect(PreparacionFotoInicio.fecha("2026:11:09 10:00:00", desfase: nil, zona: utc) == ISO8601DateFormatter().date(from: "2026-11-09T10:00:00Z"))
        #expect(PreparacionFotoInicio.fecha("2026:11:09 10:00:00", desfase: "raro", zona: utc) == ISO8601DateFormatter().date(from: "2026-11-09T10:00:00Z"))
        #expect(PreparacionFotoInicio.fecha("0000:00:00 00:00:00", desfase: nil, zona: utc) == nil)
        // Una fecha del futuro (reloj de la cámara mal puesto) no cuenta: ahora, y sin aviso de vieja.
        let jpeg = FotoSinteticaFotosInicio.jpeg("buena")!
        let p = PreparacionFotoInicio.deJPEG(jpeg, tomadaEn: ahora.addingTimeInterval(10 * 86_400), ahora: ahora)
        #expect(p?.tomadaEn == ahora && p?.dias == nil)
    }
}
