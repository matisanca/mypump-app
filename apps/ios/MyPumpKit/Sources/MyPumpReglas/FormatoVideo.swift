import CoreGraphics
import Foundation

/// El tamaño del cuadro de los videos de «Tu guía» y del «Ver por qué» (pedido de Mati del 6/11: nunca franjas negras).
/// Los clips vienen en tres formatos: verticales de unos 570×720 (Mati en el cuadro del Meet), horizontales de 1280×720 y
/// cuadrados. El cuadro toma la proporción real del clip; los verticales no pasan del 60 % del alto de la pantalla y quedan
/// centrados, con el fondo de la tarjeta a los costados.
public enum ReglasVideo {
    /// Mientras no se sabe nada del clip (ni guardado ni leído).
    public static let proporcionPorDefecto: Double = 16.0 / 9.0
    /// El alto máximo del cuadro, sobre el alto de la pantalla.
    public static let altoMaximo: Double = 0.6
    /// Fuera de esto, el dato está roto (un 1×2000 no es un clip): se descarta.
    static let rango: ClosedRange<Double> = 0.25...4

    /// Ancho sobre alto, como se ve (con la rotación de la pista aplicada). nil si el tamaño no sirve.
    public static func proporcion(ancho: Double, alto: Double, transformacion t: CGAffineTransform = .identity) -> Double? {
        guard ancho.isFinite, alto.isFinite, ancho > 0, alto > 0 else { return nil }
        let r = CGRect(x: 0, y: 0, width: ancho, height: alto).applying(t)
        let w = abs(Double(r.width)), h = abs(Double(r.height))
        guard w > 0, h > 0 else { return nil }
        let p = w / h
        return rango.contains(p) ? p : nil
    }

    /// El cuadro para ese ancho disponible y ese alto de pantalla: todo el ancho si entra; si no (los verticales), el alto
    /// máximo y el ancho que le corresponde. Una proporción rota usa la de por defecto.
    public static func cuadro(proporcion: Double?, anchoDisponible: Double, altoPantalla: Double) -> CGSize {
        let p = proporcion.flatMap { rango.contains($0) ? $0 : nil } ?? proporcionPorDefecto
        guard anchoDisponible > 0 else { return .zero }
        var ancho = anchoDisponible
        var alto = ancho / p
        if altoPantalla > 0, alto > altoPantalla * altoMaximo {
            alto = altoPantalla * altoMaximo
            ancho = alto * p
        }
        return CGSize(width: ancho.rounded(), height: alto.rounded())
    }
}

// MARK: - Franjas metidas en el archivo

/// La zona útil de un video, en fracciones del cuadro (0…1), ya girado. Hay clips que traen el negro dentro del MP4
/// (una grabación vertical de 434 px en un 1280×720): la app la detecta y muestra solo esa zona.
public struct RecuadroVideo: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var ancho: Double
    public var alto: Double

    public init(x: Double, y: Double, ancho: Double, alto: Double) { self.x = x; self.y = y; self.ancho = ancho; self.alto = alto }

    public static let entero = RecuadroVideo(x: 0, y: 0, ancho: 1, alto: 1)
}

extension ReglasVideo {
    /// Luminancia por debajo de esto es negro (las franjas de un MP4 comprimido no son 0: andan por 10-14).
    public static let umbralNegro = 16
    /// Si lo útil ocupa al menos esto del ancho y del alto, no se recorta (un borde oscuro del propio video no es franja).
    public static let minimoSinRecorte = 0.92

    /// Un borde de hasta esto (de cada lado, sobre el cuadro) que es oscuro y parejo se suma al recorte: el marco del
    /// teléfono grabado o el halo de la compresión, que pasan el umbral pero se ven como franja.
    public static let bordeOscuroMaximo = 0.04

    /// Lo que no es negro en un cuadro en gris (`luma`, fila por fila, `ancho × alto`). Una columna (o fila) cuenta si al
    /// menos el 1 % de sus píxeles (y 2 o más) pasa el umbral: un píxel suelto de ruido no la cuenta. Después se le sacan los
    /// bordes oscuros y parejos (media < 40, desvío < 12) de hasta el 4 % de cada lado, y `margen` px más hacia adentro:
    /// mejor perder un hilo de imagen que dejar negro a la vista. nil si todo el cuadro es negro (un fundido).
    public static func recuadro(luma: [UInt8], ancho: Int, alto: Int, umbral: Int = umbralNegro, margen: Int = 1) -> RecuadroVideo? {
        guard ancho > 0, alto > 0, luma.count >= ancho * alto else { return nil }
        var porColumna = [Int](repeating: 0, count: ancho)
        var porFila = [Int](repeating: 0, count: alto)
        for y in 0..<alto {
            let base = y * ancho
            for x in 0..<ancho where Int(luma[base + x]) > umbral {
                porColumna[x] += 1
                porFila[y] += 1
            }
        }
        let minCol = max(2, (alto + 99) / 100), minFila = max(2, (ancho + 99) / 100)
        guard var x0 = porColumna.firstIndex(where: { $0 >= minCol }), var x1 = porColumna.lastIndex(where: { $0 >= minCol }),
              var y0 = porFila.firstIndex(where: { $0 >= minFila }), var y1 = porFila.lastIndex(where: { $0 >= minFila }) else { return nil }
        // Media y desvío de una columna (o fila) dentro de lo útil.
        func oscuroParejo(_ valores: () -> [Int]) -> Bool {
            let v = valores()
            guard !v.isEmpty else { return false }
            let media = Double(v.reduce(0, +)) / Double(v.count)
            let desvio = (v.reduce(0.0) { $0 + pow(Double($1) - media, 2) } / Double(v.count)).squareRoot()
            return media < 40 && desvio < 12
        }
        func columna(_ x: Int) -> [Int] { (y0...y1).map { Int(luma[$0 * ancho + x]) } }
        func fila(_ y: Int) -> [Int] { (x0...x1).map { Int(luma[y * ancho + $0]) } }
        let topeX = max(1, Int(Double(ancho) * bordeOscuroMaximo)), topeY = max(1, Int(Double(alto) * bordeOscuroMaximo))
        var n = 0
        while n < topeX, x0 < x1, oscuroParejo({ columna(x0) }) { x0 += 1; n += 1 }
        n = 0
        while n < topeX, x1 > x0, oscuroParejo({ columna(x1) }) { x1 -= 1; n += 1 }
        n = 0
        while n < topeY, y0 < y1, oscuroParejo({ fila(y0) }) { y0 += 1; n += 1 }
        n = 0
        while n < topeY, y1 > y0, oscuroParejo({ fila(y1) }) { y1 -= 1; n += 1 }
        // Hacia adentro solo donde hay franja (un borde que toca el cuadro no se come).
        if x0 > 0 { x0 = min(x0 + margen, x1) }
        if x1 < ancho - 1 { x1 = max(x1 - margen, x0) }
        if y0 > 0 { y0 = min(y0 + margen, y1) }
        if y1 < alto - 1 { y1 = max(y1 - margen, y0) }
        return RecuadroVideo(x: Double(x0) / Double(ancho), y: Double(y0) / Double(alto),
                             ancho: Double(x1 - x0 + 1) / Double(ancho), alto: Double(y1 - y0 + 1) / Double(alto))
    }

    /// La unión de los cuadros (el 10 %, el 50 % y el 90 %): lo que en alguno tiene imagen.
    public static func unir(_ rs: [RecuadroVideo]) -> RecuadroVideo? {
        guard let p = rs.first else { return nil }
        var x0 = p.x, y0 = p.y, x1 = p.x + p.ancho, y1 = p.y + p.alto
        for r in rs.dropFirst() {
            x0 = min(x0, r.x); y0 = min(y0, r.y); x1 = max(x1, r.x + r.ancho); y1 = max(y1, r.y + r.alto)
        }
        return RecuadroVideo(x: x0, y: y0, ancho: x1 - x0, alto: y1 - y0)
    }

    /// El recorte que se aplica, o nil si no hace falta (ocupa el 92 % o más en los dos sentidos). Queda centrado: el
    /// reproductor del sistema recorta parejo de los dos lados (`resizeAspectFill`), y así sus controles no se mueven. Si
    /// las franjas no son parejas, se achica del lado ancho (se pierde un hilo de imagen): nunca negro a la vista.
    public static func recorte(_ r: RecuadroVideo?) -> RecuadroVideo? {
        guard let r, r.ancho > 0, r.alto > 0, r.ancho < minimoSinRecorte || r.alto < minimoSinRecorte else { return nil }
        let mitadX = min(0.5 - r.x, r.x + r.ancho - 0.5), mitadY = min(0.5 - r.y, r.y + r.alto - 0.5)
        guard mitadX > 0, mitadY > 0 else { return nil }
        let ancho = min(1, 2 * mitadX), alto = min(1, 2 * mitadY)
        guard ancho < minimoSinRecorte || alto < minimoSinRecorte else { return nil }
        return RecuadroVideo(x: (1 - ancho) / 2, y: (1 - alto) / 2, ancho: ancho, alto: alto)
    }

    /// La proporción que se ve: la del archivo, achicada al recorte.
    public static func proporcion(archivo: Double, recorte: RecuadroVideo?) -> Double {
        guard let r = recorte, r.ancho > 0, r.alto > 0 else { return archivo }
        return proporcion(ancho: archivo * r.ancho, alto: r.alto) ?? archivo
    }
}
