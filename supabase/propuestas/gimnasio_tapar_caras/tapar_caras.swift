// tapar_caras — PROPUESTA, SIN APLICAR. Lo usa /gimnasio/upload en mini-vision.
//
// Lee un JPEG, le aplica la orientación, lo reduce a 1600 px de lado, tapa con un rectángulo opaco toda cara que encuentre
// Vision y lo vuelve a codificar. El archivo de salida se arma de cero, así que no hereda EXIF, GPS ni nada del original.
// Si algo falla no escribe salida: sin tapar no se guarda nada.
//
//   swiftc -O -o tapar-caras tapar_caras.swift
//   tapar-caras entrada.jpg salida.jpg
// Salida por stdout, una línea JSON: {"caras":0,"ancho":1600,"alto":1200,"bytes":231000,"borde_blanco":0.02}
// Códigos: 0 bien · 2 no es un JPEG legible · 3 no se pudo escribir · 4 Vision falló · 64 mal uso
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import Vision

let ladoMaximo = 1600
let tope = 3 * 1024 * 1024

func morir(_ codigo: Int32, _ motivo: String) -> Never {
    FileHandle.standardError.write(Data("tapar-caras: \(motivo)\n".utf8))
    exit(codigo)
}

func cargar(_ ruta: String) -> CGImage {
    guard let fuente = CGImageSourceCreateWithURL(URL(fileURLWithPath: ruta) as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
          let tipo = CGImageSourceGetType(fuente), UTType(tipo as String) == .jpeg,
          let props = CGImageSourceCopyPropertiesAtIndex(fuente, 0, nil) as? [CFString: Any],
          let ancho = props[kCGImagePropertyPixelWidth] as? Int, let alto = props[kCGImagePropertyPixelHeight] as? Int,
          ancho > 0, alto > 0
    else { morir(2, "no es un JPEG legible") }
    let opciones: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,     // aplica la orientación del EXIF a los píxeles
        kCGImageSourceShouldCacheImmediately: true,
        kCGImageSourceThumbnailMaxPixelSize: min(ladoMaximo, max(ancho, alto)),
    ]
    guard let img = CGImageSourceCreateThumbnailAtIndex(fuente, 0, opciones as CFDictionary) else { morir(2, "no se pudo decodificar") }
    return img
}

func dibujar(_ img: CGImage) -> CGContext {
    guard let ctx = CGContext(data: nil, width: img.width, height: img.height, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
    else { morir(3, "sin memoria para el lienzo") }
    ctx.draw(img, in: CGRect(x: 0, y: 0, width: img.width, height: img.height))
    return ctx
}

/// Las caras en una región, en píxeles de la imagen entera y con origen abajo a la izquierda, como CoreGraphics.
func caras(en img: CGImage, recorte: CGRect) -> [CGRect] {
    guard let parte = img.cropping(to: recorte) else { return [] }
    let pedido = VNDetectFaceRectanglesRequest()
    do { try VNImageRequestHandler(cgImage: parte, options: [:]).perform([pedido]) }
    catch { morir(4, "Vision: \(error.localizedDescription)") }
    let altoTotal = CGFloat(img.height)
    return (pedido.results ?? []).map { c in
        let b = c.boundingBox
        let x = recorte.minX + b.minX * recorte.width
        let yDesdeArriba = recorte.minY + (1 - b.maxY) * recorte.height
        return CGRect(x: x, y: altoTotal - yDesdeArriba - b.height * recorte.height, width: b.width * recorte.width, height: b.height * recorte.height)
    }
}

/// La imagen entera y cuatro cuartos solapados: en una foto de salón una cara lejana no se ve en la pasada completa.
func todasLasCaras(_ img: CGImage) -> [CGRect] {
    let a = CGFloat(img.width), h = CGFloat(img.height)
    var regiones = [CGRect(x: 0, y: 0, width: a, height: h)]
    if max(img.width, img.height) >= 800 {
        let w2 = (a * 0.6).rounded(), h2 = (h * 0.6).rounded()
        for x in [0, a - w2] { for y in [0, h - h2] { regiones.append(CGRect(x: x, y: y, width: w2, height: h2)) } }
    }
    var unicas: [CGRect] = []
    for r in regiones.flatMap({ caras(en: img, recorte: $0) }) {
        let repetida = unicas.firstIndex { u in
            let i = u.intersection(r)
            return !i.isNull && i.width * i.height > 0.4 * min(u.width * u.height, r.width * r.height)
        }
        if let k = repetida { unicas[k] = unicas[k].union(r) } else { unicas.append(r) }
    }
    return unicas
}

func tapar(_ ctx: CGContext, _ rects: [CGRect]) {
    ctx.setFillColor(CGColor(srgbRed: 0.5, green: 0.5, blue: 0.5, alpha: 1))
    for r in rects {
        // Vision encuadra de cejas a mentón: se agranda para llevarse frente, pelo y orejas.
        ctx.fill(CGRect(x: r.minX - r.width * 0.3, y: r.minY - r.height * 0.3, width: r.width * 1.6, height: r.height * 1.85))
    }
}

/// Qué parte del borde es casi blanca: indicio de foto de catálogo.
func bordeBlanco(_ ctx: CGContext) -> Double {
    guard let d = ctx.data?.assumingMemoryBound(to: UInt8.self) else { return 0 }
    let a = ctx.width, h = ctx.height, fila = ctx.bytesPerRow, banda = max(1, min(a, h) / 25), paso = max(1, min(a, h) / 200)
    var total = 0, blancos = 0
    for y in stride(from: 0, to: h, by: paso) {
        for x in stride(from: 0, to: a, by: paso) where y < banda || y >= h - banda || x < banda || x >= a - banda {
            let p = y * fila + x * 4
            total += 1
            if d[p] >= 240 && d[p + 1] >= 240 && d[p + 2] >= 240 { blancos += 1 }
        }
    }
    return total == 0 ? 0 : Double(blancos) / Double(total)
}

/// ImageIO igual escribe un bloque Exif mínimo (tamaño y espacio de color): se saca, y el archivo queda sin ninguno.
func sinAPP1(_ j: Data) -> Data? {
    let b = [UInt8](j)
    guard b.count > 4, b[0] == 0xFF, b[1] == 0xD8 else { return nil }
    var sale = Data([0xFF, 0xD8]), i = 2
    while i + 4 <= b.count, b[i] == 0xFF {
        let marca = b[i + 1], largo = Int(b[i + 2]) << 8 | Int(b[i + 3])
        if marca == 0xDA { sale.append(contentsOf: b[i...]); return sale }   // empieza la imagen: de acá en más, tal cual
        guard largo >= 2, i + 2 + largo <= b.count else { return nil }
        if marca != 0xE1 { sale.append(contentsOf: b[i..<(i + 2 + largo)]) }
        i += 2 + largo
    }
    return nil
}

func codificar(_ img: CGImage, calidad: Double) -> Data? {
    let datos = NSMutableData()
    guard let d = CGImageDestinationCreateWithData(datos, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
    CGImageDestinationAddImage(d, img, [kCGImageDestinationLossyCompressionQuality: calidad] as CFDictionary)
    return CGImageDestinationFinalize(d) ? sinAPP1(datos as Data) : nil
}

guard CommandLine.arguments.count == 3 else { morir(64, "uso: tapar-caras entrada.jpg salida.jpg") }
let original = cargar(CommandLine.arguments[1])
let encontradas = todasLasCaras(original)
let lienzo = dibujar(original)
let blanco = bordeBlanco(lienzo)
tapar(lienzo, encontradas)
guard let final = lienzo.makeImage() else { morir(3, "no se pudo cerrar el lienzo") }

var salida: Data? = nil
for calidad in [0.8, 0.7, 0.6, 0.5] {
    if let d = codificar(final, calidad: calidad), d.count <= tope { salida = d; break }
}
guard let bytes = salida else { morir(3, "no entra en el tope") }
do { try bytes.write(to: URL(fileURLWithPath: CommandLine.arguments[2]), options: .atomic) }
catch { morir(3, "no se pudo escribir") }
print("{\"caras\":\(encontradas.count),\"ancho\":\(final.width),\"alto\":\(final.height),\"bytes\":\(bytes.count),\"borde_blanco\":\(String(format: "%.3f", blanco))}")
