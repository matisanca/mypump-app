import Foundation

/// La figura del cuerpo de «Me duele»: dibujo propio hecho de cápsulas, elipses y cajas en un lienzo de 200 × 420. Las piezas
/// salen de `scripts/nativa/generar-cuerpo.py` (`FiguraCuerpoDatos.swift`), las mismas en Android y en la web
/// (`apps/shared/fixtures/feedback/cuerpo.json`). Tocar una pieza da la zona y el lado de una vez.
public enum FiguraCuerpo {
    public static let ancho: Double = 200
    public static let alto: Double = 420

    public enum Vista: String, Sendable, CaseIterable { case frente, espalda }
    public enum Forma: String, Sendable { case capsula, elipse, caja }

    public struct Pieza: Equatable, Sendable, Identifiable {
        /// nil = la cabeza, que es solo dibujo.
        public let zona: String?
        public let lado: String?
        public let forma: Forma
        /// cápsula: x1, y1, x2, y2, radio · elipse: cx, cy, rx, ry · caja: x, y, ancho, alto, radio.
        public let a: [Double]
        public var id: String { "\(zona ?? "cabeza")-\(lado ?? "")" }

        /// El centro de la pieza, para ordenar la lectura y ubicar la etiqueta.
        public var centro: (x: Double, y: Double) {
            switch forma {
            case .capsula: ((a[0] + a[2]) / 2, (a[1] + a[3]) / 2)
            case .elipse: (a[0], a[1])
            case .caja: (a[0] + a[2] / 2, a[1] + a[3] / 2)
            }
        }

        /// El rectángulo que la contiene: x, y, ancho, alto.
        public var marco: (x: Double, y: Double, ancho: Double, alto: Double) {
            switch forma {
            case .capsula:
                let x = min(a[0], a[2]) - a[4], y = min(a[1], a[3]) - a[4]
                return (x, y, abs(a[2] - a[0]) + 2 * a[4], abs(a[3] - a[1]) + 2 * a[4])
            case .elipse: return (a[0] - a[2], a[1] - a[3], 2 * a[2], 2 * a[3])
            case .caja: return (a[0], a[1], a[2], a[3])
            }
        }

        /// ¿El punto cae en la pieza? `margen` agranda el blanco: un codo de 20 puntos es chico para un dedo.
        public func contiene(x: Double, y: Double, margen: Double = 0) -> Bool {
            switch forma {
            case .elipse:
                let rx = a[2] + margen, ry = a[3] + margen
                let dx = (x - a[0]) / rx, dy = (y - a[1]) / ry
                return dx * dx + dy * dy <= 1
            case .caja:
                return x >= a[0] - margen && x <= a[0] + a[2] + margen && y >= a[1] - margen && y <= a[1] + a[3] + margen
            case .capsula:
                let vx = a[2] - a[0], vy = a[3] - a[1]
                let largo2 = vx * vx + vy * vy
                let t = largo2 == 0 ? 0 : max(0, min(1, ((x - a[0]) * vx + (y - a[1]) * vy) / largo2))
                let px = a[0] + t * vx - x, py = a[1] + t * vy - y
                let r = a[4] + margen
                return px * px + py * py <= r * r
            }
        }
    }

    public static func piezas(_ v: Vista) -> [Pieza] { v == .frente ? frente : espalda }

    /// La pieza tocada. Primero sin margen (lo que el dedo tapa de verdad) y después con margen, la de centro más cercano.
    public static func pieza(en v: Vista, x: Double, y: Double, margen: Double = 7) -> Pieza? {
        let tocables = piezas(v).filter { $0.zona != nil }
        if let p = tocables.last(where: { $0.contiene(x: x, y: y) }) { return p }
        return tocables.filter { $0.contiene(x: x, y: y, margen: margen) }
            .min { a, b in distancia2(a, x, y) < distancia2(b, x, y) }
    }

    private static func distancia2(_ p: Pieza, _ x: Double, _ y: Double) -> Double {
        let c = p.centro
        return (c.x - x) * (c.x - x) + (c.y - y) * (c.y - y)
    }

    /// La vista donde se ve una zona, para abrir el dibujo del lado correcto al corregir un aviso.
    public static func vista(de zona: String) -> Vista {
        frente.contains { $0.zona == zona } ? .frente : .espalda
    }
}
