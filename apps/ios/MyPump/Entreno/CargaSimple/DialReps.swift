import SwiftUI

/// El dial de repeticiones: el número grande con el anterior y el siguiente apenas visibles. Deslizar hacia arriba suma y
/// hacia abajo resta, de a una por cada escalón (como la corona del reloj); los botones de al lado hacen lo mismo y son
/// la forma accesible. Con VoiceOver es un elemento ajustable. Vive en el dock, fuera del ScrollView: no compite con el scroll.
struct DialReps: View {
    let reps: Int?
    /// Lo marcado respecto de la base: +1, −2; nil si coincide.
    let diferencia: Int?
    /// «La vez pasada» o «Según el plan».
    let referencia: String?
    let alCambiar: (Int) -> Void
    var deshabilitado = false

    private static let escalon: CGFloat = 26
    static let topePorArrastre = 5
    @GestureState private var tocando = false
    @State private var desplazamiento: CGFloat = 0
    @State private var aplicados = 0
    /// Un escalón, una vibración (la pantalla no vibra si el número cambia por otra cosa).
    @State private var escalones = 0
    @Environment(\.accessibilityReduceMotion) private var reducir
    @Environment(\.dynamicTypeSize) private var letra
    @ScaledMetric(relativeTo: .largeTitle) private var altoNumero: CGFloat = 62

    private var valorTexto: String { reps.map(String.init) ?? "—" }

    var body: some View {
        HStack(spacing: Espacio.s) {
            boton("minus", etiqueta: "Restar una repetición", id: "reps-menos", d: -1)
            rueda
            boton("plus", etiqueta: "Sumar una repetición", id: "reps-mas", d: 1)
        }
        .sensoryFeedback(.selection, trigger: escalones)
        // Si el sistema cancela el gesto (un llamado), `onEnded` no corre: lo aplicado no puede quedar arrastrado al próximo.
        .onChange(of: tocando) { _, t in
            if !t { aplicados = 0; withAnimation(.snappy(duration: 0.2)) { desplazamiento = 0 } }
        }
    }

    private func boton(_ icono: String, etiqueta: String, id: String, d: Int) -> some View {
        Button { alCambiar(d); escalones += 1 } label: {
            Image(systemName: icono)
                .font(.system(size: 20, weight: .bold))
                .frame(width: 56, height: 56)
                .background(Color.campo, in: .circle)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .foregroundStyle(deshabilitado ? Color.secondary : Color.primary)
        .disabled(deshabilitado)
        .accessibilityLabel(etiqueta)
        .accessibilityIdentifier(id)
    }

    private var rueda: some View {
        VStack(spacing: 2) {
            ZStack {
                let alto = altoNumero
                VStack(spacing: 0) {
                    if !letra.isAccessibilitySize {
                        fantasma(reps.map { max($0 - 1, 0) }, visible: (reps ?? 1) > 1)
                    }
                    Text(valorTexto)
                        .font(Archivo.fuente(52, relativoA: .largeTitle))
                        .monospacedDigit()
                        .contentTransition(reducir ? .identity : .numericText())
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .frame(height: alto)
                    if !letra.isAccessibilitySize {
                        fantasma(reps.map { $0 + 1 }, visible: true)
                    }
                }
                .offset(y: reducir ? 0 : desplazamiento)
                .mask {
                    LinearGradient(stops: [.init(color: .black.opacity(0.35), location: 0), .init(color: .black, location: 0.24),
                                           .init(color: .black, location: 0.76), .init(color: .black.opacity(0.35), location: 1)],
                                   startPoint: .top, endPoint: .bottom)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: letra.isAccessibilitySize ? altoNumero : altoNumero + 40)
            .contentShape(.rect)
            .gesture(arrastre)
            .overlay(alignment: .trailing) { pastilla }

            Text(referencia ?? " ")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Repeticiones")
        .accessibilityValue([valorTexto, referencia].compactMap { $0 }.joined(separator: ", "))
        .accessibilityHint("Deslizá hacia arriba o abajo con un dedo para sumar o restar")
        .accessibilityAdjustableAction { dir in
            switch dir {
            case .increment: alCambiar(1)
            case .decrement: alCambiar(-1)
            @unknown default: break
            }
        }
        .accessibilityIdentifier("reps-dial")
    }

    private func fantasma(_ n: Int?, visible: Bool) -> some View {
        Text(n.map(String.init) ?? " ")
            .font(Archivo.fuente(20, peso: 600, relativoA: .title3))
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .opacity(visible ? 1 : 0)
            .frame(height: 20)
    }

    @ViewBuilder private var pastilla: some View {
        if let d = diferencia {
            Text(d > 0 ? "+\(d)" : "−\(-d)")
                .font(.caption.weight(.bold).monospacedDigit())
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(d > 0 ? Color.marcaSuave : Color.campo, in: .capsule)
                .foregroundStyle(d > 0 ? Color.marcaTexto : Color.secondary)
                .transition(.opacity)
                .padding(.trailing, 4)
        }
    }

    private var arrastre: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .global)
            .updating($tocando) { _, s, _ in s = true }
            .onChanged { v in
                guard !deshabilitado else { return }
                // U2 (auditoría del 10/11): un desplazamiento largo con el pulgar sobre el dial llevaba las reps de 10 a 46.
                // Un arrastre mueve como mucho `topePorArrastre`; para más, se suelta y se vuelve a arrastrar.
                let pasos = max(-Self.topePorArrastre, min(Self.topePorArrastre, Int((-v.translation.height / Self.escalon).rounded(.towardZero))))
                if pasos != aplicados { alCambiar(pasos - aplicados); aplicados = pasos; escalones += 1 }
                desplazamiento = max(-Self.escalon, min(Self.escalon, v.translation.height + CGFloat(pasos) * Self.escalon))
            }
            .onEnded { _ in
                aplicados = 0
                withAnimation(.snappy(duration: 0.2)) { desplazamiento = 0 }
            }
    }
}
