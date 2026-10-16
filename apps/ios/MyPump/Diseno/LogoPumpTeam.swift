import SwiftUI

/// El torso del logo de Pump Team, el del ícono de la app (`public/icons/logo.svg`), en una grilla de 512: el contorno de
/// hombros, brazos y cintura, los pectorales y los abdominales. Es un trazo: se pinta con `stroke`.
struct TorsoPumpTeam: Shape {
    /// Cuánto del lado ocupa el torso (en el ícono, el 57 %).
    var ocupa: CGFloat = 0.57

    func path(in r: CGRect) -> Path {
        let s = min(r.width, r.height) * ocupa / 292           // el torso mide 292 de ancho y de alto
        let dx = r.midX - 256 * s, dy = r.midY - 296 * s       // va de 150 a 442: centrado en su alto, no en la grilla
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: dx + x * s, y: dy + y * s) }
        var t = Path()
        t.move(to: p(110, 195))
        t.addCurve(to: p(210, 150), control1: p(130, 165), control2: p(175, 145))
        t.addLine(to: p(256, 178))
        t.addLine(to: p(302, 150))
        t.addCurve(to: p(402, 195), control1: p(337, 145), control2: p(382, 165))
        t.addLine(to: p(402, 250))
        t.addCurve(to: p(365, 282), control1: p(395, 270), control2: p(380, 280))
        for (x, y) in [(350, 282), (340, 320), (350, 360), (332, 405), (296, 432), (256, 442), (216, 432), (180, 405),
                       (162, 360), (172, 320), (162, 282), (147, 282)] as [(CGFloat, CGFloat)] {
            t.addLine(to: p(x, y))
        }
        t.addCurve(to: p(110, 250), control1: p(132, 280), control2: p(117, 270))
        t.closeSubpath()
        t.move(to: p(210, 195)); t.addCurve(to: p(220, 265), control1: p(195, 215), control2: p(195, 245)); t.addLine(to: p(250, 275))
        t.move(to: p(302, 195)); t.addCurve(to: p(292, 265), control1: p(317, 215), control2: p(317, 245)); t.addLine(to: p(262, 275))
        t.move(to: p(256, 282)); t.addLine(to: p(256, 405))
        for (x1, x2, y) in [(200, 312, 312), (195, 317, 348), (190, 322, 385)] as [(CGFloat, CGFloat, CGFloat)] {
            t.move(to: p(x1, y)); t.addLine(to: p(x2, y))
        }
        return t
    }
}

/// El logo de Pump Team como el ícono de la app: el torso blanco sobre el verde de la marca. `circular` para el avatar
/// del chat; si no, el cuadrado redondeado del ícono. El trazo engorda en lo chico para que no se pierda.
struct LogoPumpTeam: View {
    var lado: CGFloat
    var circular = false

    var body: some View {
        TorsoPumpTeam(ocupa: circular ? 0.66 : 0.57)
            .stroke(Color.sobreMarca, style: StrokeStyle(lineWidth: max(1.5, lado * (circular ? 0.045 : 0.028)), lineCap: .round, lineJoin: .round))
            .frame(width: lado, height: lado)
            .background(Color.marca.gradient, in: circular ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: lado * 0.24, style: .continuous)))
            .accessibilityHidden(true)
    }
}
