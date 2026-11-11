import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import MyPumpReglas

/// La foto de inicio lista para revisar: el JPEG que sube (lado mayor ≤ 1600, 0,85, derecho y sin metadatos), sus medidas, lo
/// que midió el control de calidad sobre esos mismos píxeles y cuándo se sacó.
public struct FotoInicioPreparada: Equatable, Sendable, Identifiable {
    public let id = UUID()
    public let jpeg: Data
    public let ancho: Int
    public let alto: Int
    public let medida: FotosInicio.Medida
    public let tomadaEn: Date
    /// Días desde que se sacó; nil si la original no traía fecha (no se avisa que es vieja).
    public let dias: Int?

    /// Lo que se le avisa al alumno, en el orden en que se muestra.
    public func problemas(pose: String) -> [FotosInicio.Problema] {
        FotosInicio.problemas(pose: pose, ancho: ancho, alto: alto, medida: medida, dias: dias)
    }
}

public enum PreparacionFotoInicio {
    /// De la foto original (galería): lee la fecha del EXIF antes de reducirla, que la reducción la borra. nil si no es una imagen.
    public static func preparar(_ original: Data, ahora: Date = Date(), zona: TimeZone = .current) -> FotoInicioPreparada? {
        let fecha = fechaExif(original, zona: zona)
        guard let jpeg = ReduccionFoto.jpeg(original, maxPx: FotosInicio.maxPx, calidad: FotosInicio.calidad) else { return nil }
        return deJPEG(jpeg, tomadaEn: fecha, ahora: ahora)
    }

    /// Del JPEG ya reducido (la cámara: se sacó recién). `tomadaEn` nil o en el futuro (reloj mal puesto): ahora, y sin aviso de vieja.
    public static func deJPEG(_ jpeg: Data, tomadaEn: Date?, ahora: Date = Date()) -> FotoInicioPreparada? {
        guard let fuente = CGImageSourceCreateWithData(jpeg as CFData, nil), let imagen = CGImageSourceCreateImageAtIndex(fuente, 0, nil),
              let luma = luma(imagen) else { return nil }
        let medida = FotosInicio.medir(luma: luma, ancho: imagen.width, alto: imagen.height)
        let fecha = tomadaEn.flatMap { $0 <= ahora.addingTimeInterval(86_400) ? min($0, ahora) : nil }
        return FotoInicioPreparada(jpeg: jpeg, ancho: imagen.width, alto: imagen.height, medida: medida, tomadaEn: fecha ?? ahora,
                                   dias: fecha.map { FotosInicio.dias(desde: $0, hasta: ahora) })
    }

    /// `DateTimeOriginal` del EXIF, con su `OffsetTimeOriginal` si lo trae (si no, la hora es la del teléfono).
    public static func fechaExif(_ datos: Data, zona: TimeZone = .current) -> Date? {
        guard let fuente = CGImageSourceCreateWithData(datos as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let props = CGImageSourceCopyPropertiesAtIndex(fuente, 0, nil) as? [CFString: Any],
              let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any],
              let texto = exif[kCGImagePropertyExifDateTimeOriginal] as? String else { return nil }
        return fecha(texto, desfase: exif[kCGImagePropertyExifOffsetTimeOriginal] as? String, zona: zona)
    }

    /// «2026:11:09 10:00:00» y, si viene, «-03:00».
    static func fecha(_ texto: String, desfase: String?, zona: TimeZone) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy:MM:dd HH:mm:ss"
        f.timeZone = desfase.flatMap(zonaDe) ?? zona
        return f.date(from: String(texto.prefix(19)))
    }

    private static func zonaDe(_ desfase: String) -> TimeZone? {
        let s = desfase.trimmingCharacters(in: .whitespaces)
        guard s.count == 6, let signo = s.first, signo == "+" || signo == "-" else { return nil }
        let partes = s.dropFirst().split(separator: ":")
        guard partes.count == 2, let h = Int(partes[0]), let m = Int(partes[1]), h <= 14, m < 60 else { return nil }
        return TimeZone(secondsFromGMT: (signo == "-" ? -1 : 1) * (h * 3600 + m * 60))
    }

    /// Una luma por píxel, por filas (`FotosInicio.luma`), de la imagen dibujada en sRGB de 8 bits.
    static func luma(_ imagen: CGImage) -> [UInt8]? {
        let w = imagen.width, h = imagen.height
        guard w > 0, h > 0, let espacio = CGColorSpace(name: CGColorSpace.sRGB),
              let c = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: espacio,
                                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        c.interpolationQuality = .none
        c.draw(imagen, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let base = c.data else { return nil }
        let px = base.bindMemory(to: UInt8.self, capacity: w * h * 4)
        var salida = [UInt8](repeating: 0, count: w * h)
        for i in 0..<(w * h) {
            salida[i] = UInt8(FotosInicio.luma(r: Int(px[i * 4]), g: Int(px[i * 4 + 1]), b: Int(px[i * 4 + 2])))
        }
        return salida
    }
}

#if DEBUG
/// Las fotos de mentira del modo de prueba (`-fotosInicioFoto buena|oscura|chica|movida`): pasan por la misma reducción y el
/// mismo control que una de verdad.
public enum FotoSinteticaFotosInicio {
    /// buena: 1200 × 1600, clara y con bordes nítidos; oscura: igual pero sin luz; chica: 600 × 800; movida: un degradé suave.
    public static func jpeg(_ escenario: String) -> Data? {
        let (w, h) = escenario == "chica" ? (600, 800) : (1200, 1600)
        guard let espacio = CGColorSpace(name: CGColorSpace.sRGB),
              let c = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: espacio,
                                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        func gris(_ v: Int) -> CGColor { CGColor(colorSpace: espacio, components: [CGFloat(v) / 255, CGFloat(v) / 255, CGFloat(v) / 255, 1])! }
        if escenario == "movida" {
            for y in 0..<h {
                c.setFillColor(gris(90 + Int((130.0 * Double(y) / Double(h)).rounded())))
                c.fill(CGRect(x: 0, y: y, width: w, height: 1))
            }
        } else {
            let (claro, oscuro) = escenario == "oscura" ? (40, 10) : (210, 120)
            c.setFillColor(gris(claro)); c.fill(CGRect(x: 0, y: 0, width: w, height: h))
            c.setFillColor(gris(oscuro))
            let lado = w / 15
            for fy in 0...(h / lado) { for fx in 0...(w / lado) where (fx + fy) % 2 == 0 { c.fill(CGRect(x: fx * lado, y: fy * lado, width: lado, height: lado)) } }
        }
        guard let imagen = c.makeImage() else { return nil }
        let salida = NSMutableData()
        guard let destino = CGImageDestinationCreateWithData(salida as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destino, imagen, [kCGImageDestinationLossyCompressionQuality: FotosInicio.calidad] as CFDictionary)
        return CGImageDestinationFinalize(destino) ? salida as Data : nil
    }
}
#endif
