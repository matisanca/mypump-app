import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// `_fotoABase64Reducida` de la web: la foto con el lado mayor ≤ `maxPx`, en JPEG con `calidad`, con la orientación ya
/// aplicada y SIN metadatos (ni EXIF ni la ubicación). Lee lo que lea ImageIO: JPEG, HEIC, PNG.
///
/// Con ImageIO y no redibujando un `UIImage`: la miniatura sale sin decodificar la foto entera. Una de 48 MP de un
/// iPhone nuevo, decodificada, son ~190 MB, y eso puede hacer que iOS cierre la app. Además se prueba en la Mac.
public enum ReduccionFoto {
    /// nil si los datos no son una imagen.
    public static func jpeg(_ datos: Data, maxPx: Int, calidad: Double) -> Data? {
        guard maxPx > 0,
              let fuente = CGImageSourceCreateWithData(datos as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(fuente) > 0 else { return nil }
        let opciones: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,   // la orientación de la cámara, aplicada
            kCGImageSourceThumbnailMaxPixelSize: maxPx,         // nunca agranda una más chica
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let imagen = CGImageSourceCreateThumbnailAtIndex(fuente, 0, opciones as CFDictionary) else { return nil }
        let salida = NSMutableData()
        guard let destino = CGImageDestinationCreateWithData(salida as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil)
        else { return nil }
        // Solo la imagen y la calidad: sin propiedades de la original, así no viaja ni el EXIF ni el GPS.
        CGImageDestinationAddImage(destino, imagen, [kCGImageDestinationLossyCompressionQuality: calidad] as CFDictionary)
        guard CGImageDestinationFinalize(destino) else { return nil }
        return salida as Data
    }
}
