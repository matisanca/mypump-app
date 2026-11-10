// Solo para las pruebas: arma un JPEG con EXIF, GPS y orientación, o lee un píxel. Sin fotos reales en el repo.
//   generar_prueba escribir salida.jpg ancho alto orientacion
//   generar_prueba pixel archivo.jpg x y   (x, y desde arriba a la izquierda)
//   generar_prueba metadatos archivo.jpg
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
let a = CommandLine.arguments
switch a[1] {
case "escribir":
    let w = Int(a[3])!, h = Int(a[4])!
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.setFillColor(CGColor(srgbRed: 0.2, green: 0.6, blue: 0.3, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    ctx.setFillColor(CGColor(srgbRed: 0.9, green: 0.1, blue: 0.1, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: w / 2, height: h / 2))
    let d = CGImageDestinationCreateWithURL(URL(fileURLWithPath: a[2]) as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
    let props: [CFString: Any] = [
        kCGImagePropertyOrientation: Int(a[5])!,
        kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 34.6, kCGImagePropertyGPSLatitudeRef: "S", kCGImagePropertyGPSLongitude: 58.4, kCGImagePropertyGPSLongitudeRef: "W"],
        kCGImagePropertyExifDictionary: [kCGImagePropertyExifUserComment: "MARCA-SECRETA-EXIF"],
        kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFModel: "MARCA-SECRETA-MODELO"],
    ]
    CGImageDestinationAddImage(d, ctx.makeImage()!, props as CFDictionary)
    precondition(CGImageDestinationFinalize(d))
case "pixel":
    let s = CGImageSourceCreateWithURL(URL(fileURLWithPath: a[2]) as CFURL, nil)!
    let img = CGImageSourceCreateImageAtIndex(s, 0, nil)!
    let ctx = CGContext(data: nil, width: img.width, height: img.height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.draw(img, in: CGRect(x: 0, y: 0, width: img.width, height: img.height))
    let p = ctx.data!.assumingMemoryBound(to: UInt8.self), o = Int(a[4])! * ctx.bytesPerRow + Int(a[3])! * 4
    print("\(p[o]) \(p[o + 1]) \(p[o + 2])")
case "metadatos":
    let s = CGImageSourceCreateWithURL(URL(fileURLWithPath: a[2]) as CFURL, nil)!
    let p = CGImageSourceCopyPropertiesAtIndex(s, 0, nil) as! [CFString: Any]
    print(p[kCGImagePropertyGPSDictionary] != nil ? "gps" : "sin-gps", p[kCGImagePropertyOrientation] != nil ? "orientacion" : "sin-orientacion", p[kCGImagePropertyExifDictionary].map { "\($0)".contains("MARCA") ? "exif-marca" : "exif-limpio" } ?? "sin-exif")
default: exit(64)
}
