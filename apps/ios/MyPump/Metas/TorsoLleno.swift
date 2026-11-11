import SwiftUI

/// El «Pump del día»: el torso del logo de Pump Team que se llena de verde desde la cintura con los pasos de hoy. Arriba
/// del verde, una ola suave que respira (quieta con «Reducir movimiento»). Lleno, el trazo pasa a blanco sobre el verde,
/// como el ícono de la app. No es un anillo: es la marca la que se carga.
struct TorsoLleno: View {
    /// De 0 a 1.
    var fraccion: Double
    var lado: CGFloat
    /// La ola se mueve. En lo chico (la semana) va quieta.
    var vivo = true
    /// El dibujo del logo (pectorales y abdominales). En lo chico se ve como un manchón: solo la silueta.
    var detalle = true
    @Environment(\.accessibilityReduceMotion) private var reducir
    @Environment(\.colorScheme) private var esquema
    @State private var olaViva = false

    private var lleno: Bool { fraccion >= 1 }
    private var grosor: CGFloat { max(1.4, lado * 0.028) }

    var body: some View {
        ZStack {
            // La silueta vacía: un gris de fondo, para que se lea lo que falta.
            TorsoPumpTeam(ocupa: 0.94, soloContorno: true)
                .fill(Color.campo)
            if vivo && !reducir && !lleno && fraccion > 0 {
                // La ola se mueve unos segundos al aparecer o al cambiar los pasos y se queda quieta: un dibujo a 30 cuadros
                // por segundo en la pantalla de inicio gastaba batería sin sumar nada.
                TimelineView(.animation(minimumInterval: 1 / 30, paused: !olaViva)) { t in
                    relleno(fase: t.date.timeIntervalSinceReferenceDate)
                }
                .task(id: fraccion) {
                    olaViva = true
                    try? await Task.sleep(for: .seconds(6))
                    olaViva = false
                }
            } else {
                relleno(fase: 0)
            }
            // El dibujo del logo encima: gris donde está vacío, blanco donde ya hay verde.
            if detalle {
                TorsoPumpTeam(ocupa: 0.94)
                    .stroke(Color.secondary.opacity(0.45), style: StrokeStyle(lineWidth: grosor, lineCap: .round, lineJoin: .round))
                TorsoPumpTeam(ocupa: 0.94)
                    .stroke(Color.sobreMarca, style: StrokeStyle(lineWidth: grosor, lineCap: .round, lineJoin: .round))
                    .mask { Ola(nivel: fraccion, fase: 0, amplitud: 0) }
            }
        }
        .frame(width: lado, height: lado)
        .shadow(color: lleno ? Color.marcaVivo.opacity(esquema == .dark ? 0.55 : 0.35) : .clear, radius: lado * 0.12)
        .animation(reducir ? nil : .spring(duration: 0.8, bounce: 0.25), value: fraccion)
        .accessibilityHidden(true)
    }

    private func relleno(fase: Double) -> some View {
        Ola(nivel: fraccion, fase: fase * 2.2, amplitud: lleno || fraccion <= 0 ? 0 : lado * 0.025)
            .fill(LinearGradient(colors: [Color.marcaVivo, Color.marca], startPoint: .top, endPoint: .bottom))
            .mask { TorsoPumpTeam(ocupa: 0.94, soloContorno: true).fill(Color.black) }
    }
}

/// Lo que está debajo del nivel, con el borde de arriba en ola. El nivel se mide sobre el alto del torso (no del cuadro):
/// 0 es la cintura y 1 los hombros, así un 50 % se ve a mitad del torso.
struct Ola: Shape {
    var nivel: Double
    var fase: Double
    var amplitud: CGFloat

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(nivel, fase) }
        set { nivel = newValue.first; fase = newValue.second }
    }

    func path(in r: CGRect) -> Path {
        // El torso (ocupa 0,94) va de 150 a 442 en la grilla de 512, centrado en su alto.
        let alto = min(r.width, r.height) * 0.94
        let abajo = r.midY + alto / 2
        let n = max(0, min(1, nivel))
        // Lleno de verdad: un poco más arriba de los hombros, para que la ola no deje un hilo vacío.
        let y = n >= 1 ? r.minY - 2 : abajo - CGFloat(n) * alto
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: y))
        let pasos = 24
        for i in 0...pasos {
            let x = r.minX + r.width * CGFloat(i) / CGFloat(pasos)
            let onda = sin(Double(i) / Double(pasos) * .pi * 2 + fase)
            p.addLine(to: CGPoint(x: x, y: y + amplitud * CGFloat(onda)))
        }
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

#Preview {
    HStack {
        TorsoLleno(fraccion: 0, lado: 80)
        TorsoLleno(fraccion: 0.45, lado: 80)
        TorsoLleno(fraccion: 0.8, lado: 80)
        TorsoLleno(fraccion: 1, lado: 80)
    }
    .padding()
}
