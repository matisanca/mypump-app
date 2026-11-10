import SwiftUI

/// El dial de repeticiones: un tambor de números. Sigue al dedo de verdad, y deslizar hacia arriba suma y hacia abajo resta
/// de a una por cada escalón (como la corona del reloj). Las rayitas de los costados son la regla que se mueve con el dedo.
/// Los botones de al lado hacen lo mismo y son la forma accesible; con VoiceOver es un elemento ajustable. Vive en el dock,
/// fuera del ScrollView: no compite con el scroll. No tiene tope ni colores de «te pasaste»: las reps son referencia.
struct DialReps: View {
    let reps: Int?
    /// Lo marcado respecto de la base: +1, −2; nil si coincide.
    let diferencia: Int?
    /// «La vez pasada» o «Según el plan».
    let referencia: String?
    /// La serie: al cambiar, el tambor entra de abajo, aunque el número sea el mismo.
    var clave = 0
    var deshabilitado = false
    let alCambiar: (Int) -> Void

    private static let escalon: CGFloat = 26
    private static let maximo = 300
    @GestureState private var tocando = false
    @State private var desplazamiento: CGFloat = 0
    @State private var aplicados = 0
    /// Un escalón, una vibración. Al caer justo en la vez pasada es más firme, como la muesca de una perilla.
    @State private var escalones = 0
    @Environment(\.accessibilityReduceMotion) private var reducir
    @Environment(\.dynamicTypeSize) private var letra

    private var chico: Bool { EstiloCarga.pantallaChica }
    private var conVecinos: Bool { !letra.isAccessibilitySize && reps != nil }
    private var tamaño: CGFloat { chico ? 64 : 76 }
    private var paso: CGFloat { tamaño * 0.58 }
    private var altoTambor: CGFloat {
        conVecinos ? (chico ? 104 : 122) : tamaño * 1.1
    }
    private var valorTexto: String { reps.map(String.init) ?? "—" }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Espacio.xs) {
                boton("minus", etiqueta: "Restar una repetición", id: "reps-menos", d: -1)
                rueda
                boton("plus", etiqueta: "Sumar una repetición", id: "reps-mas", d: 1)
            }
            filaReferencia
        }
        .sensoryFeedback(trigger: escalones) { _, _ in
            diferencia == nil && referencia != nil ? .impact(weight: .medium, intensity: 0.9) : .selection
        }
        // Si el sistema cancela el gesto (un llamado), `onEnded` no corre: lo aplicado no puede quedar arrastrado al próximo.
        .onChange(of: tocando) { _, t in
            if !t { aplicados = 0; withAnimation(EstiloCarga.resorteDial) { desplazamiento = 0 } }
        }
    }

    private func boton(_ icono: String, etiqueta: String, id: String, d: Int) -> some View {
        Button {
            alCambiar(d)
            escalones += 1
            impulso(d)
        } label: {
            Image(systemName: icono)
        }
        .buttonStyle(BotonCircularCarga())
        .foregroundStyle(deshabilitado ? Color.secondary : Color.primary)
        .disabled(deshabilitado)
        .accessibilityLabel(etiqueta)
        .accessibilityIdentifier(id)
    }

    /// El − y el + también giran el tambor: el número nuevo llega desde donde estaba.
    private func impulso(_ d: Int) {
        guard !reducir else { return }
        var sinAnimar = Transaction()
        sinAnimar.disablesAnimations = true
        withTransaction(sinAnimar) { desplazamiento = CGFloat(d) * Self.escalon }
        DispatchQueue.main.async { withAnimation(EstiloCarga.resorteDial) { desplazamiento = 0 } }
    }

    /// De dónde sale el número y cuánto le sumaste. El alto es fijo: la pastilla aparece sin mover el dial.
    private var filaReferencia: some View {
        HStack(spacing: 6) {
            Text(referencia ?? " ")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if let d = diferencia { pastilla(d) }
        }
        .frame(minHeight: 20)
        .animation(EstiloCarga.resorte, value: diferencia)
        .accessibilityHidden(true)
    }

    private var rueda: some View {
        ZStack {
            if conVecinos { regla }
            tambor
        }
        .frame(maxWidth: .infinity)
        .frame(height: altoTambor)
        .scaleEffect(tocando && !reducir ? 1.03 : 1)
        .animation(.snappy(duration: 0.18), value: tocando)
        .contentShape(.rect)
        .gesture(arrastre)
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

    // MARK: Tambor

    /// De −1 a 1: cuánto del escalón siguiente ya entró. Contra el borde (1 rep o 300) el tambor se resiste.
    private var fraccion: CGFloat {
        guard !reducir, !deshabilitado else { return 0 }
        let f = desplazamiento / Self.escalon
        if f > 0, (reps ?? 2) <= 1 { return f * 0.22 }
        if f < 0, (reps ?? 0) >= Self.maximo { return f * 0.22 }
        return f
    }

    private var tambor: some View {
        ZStack {
            Group {
                ForEach(conVecinos ? Array(-2...2) : [0], id: \.self) { k in numero(k) }
            }
            .id(clave)
            .transition(reducir ? .opacity : .asymmetric(insertion: .offset(y: paso).combined(with: .opacity).combined(with: .scale(scale: 0.8)),
                                                         removal: .offset(y: -paso).combined(with: .opacity).combined(with: .scale(scale: 0.8))))
        }
        .animation(reducir ? .easeInOut(duration: 0.15) : EstiloCarga.resorte, value: clave)
        .frame(maxWidth: .infinity)
        .frame(height: altoTambor)
        .mask {
            LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.1),
                                   .init(color: .black, location: 0.9), .init(color: .clear, location: 1)],
                           startPoint: .top, endPoint: .bottom)
        }
    }

    @ViewBuilder private func numero(_ k: Int) -> some View {
        let valor = (reps ?? 0) + k
        if k == 0 || (reps != nil && valor >= 1 && valor <= Self.maximo) {
            let d = CGFloat(k) + fraccion
            let lejos = abs(d)
            let escala = max(0.3, 1 - 0.6 * min(lejos, 1) - 0.1 * max(lejos - 1, 0))
            let opacidad = lejos <= 1 ? 1 - 0.68 * lejos : max(0, 0.32 * (2 - lejos))
            Text(k == 0 ? valorTexto : String(valor))
                .font(Archivo.fija(tamaño, peso: 900))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .scaleEffect(escala)
                .rotation3DEffect(.degrees(Double(-d) * 20), axis: (x: 1, y: 0, z: 0), perspective: 0.4)
                .opacity(opacidad)
                .offset(y: d * paso)
        }
    }

    /// La regla: una raya por repetición, a los costados del número, que viaja con el dedo. Va pegada al número y no a los
    /// botones, y gris: en verde y a su lado se leía como otro «−».
    private var regla: some View {
        Canvas { ctx, size in
            let centro = size.height / 2
            let corrimiento = (fraccion * Self.escalon).truncatingRemainder(dividingBy: Self.escalon)
            let cuantas = Int(centro / Self.escalon) + 2
            let margen: CGFloat = 14, largo: CGFloat = 12
            for n in -cuantas...cuantas {
                let y = centro + CGFloat(n) * Self.escalon + corrimiento
                let lejania = min(abs(y - centro) / centro, 1)
                let opacidad = pow(1 - lejania, 1.2) * 0.42
                guard opacidad > 0.01 else { continue }
                var trazo = Path()
                trazo.move(to: CGPoint(x: margen, y: y)); trazo.addLine(to: CGPoint(x: margen + largo, y: y))
                trazo.move(to: CGPoint(x: size.width - margen, y: y)); trazo.addLine(to: CGPoint(x: size.width - margen - largo, y: y))
                ctx.stroke(trazo, with: .color(.primary.opacity(opacidad)), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func pastilla(_ d: Int) -> some View {
        Text(d > 0 ? "+\(d)" : "−\(-d)")
            .font(.footnote.weight(.bold).monospacedDigit())
            .contentTransition(.numericText())
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(d > 0 ? Color.marcaSuave : Color.campo, in: .capsule)
            .foregroundStyle(d > 0 ? Color.marcaTexto : Color.secondary)
            .transition(.scale(scale: 0.6).combined(with: .opacity))
    }

    private var arrastre: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .global)
            .updating($tocando) { _, s, _ in s = true }
            .onChanged { v in
                guard !deshabilitado else { return }
                let pasos = Int((-v.translation.height / Self.escalon).rounded(.towardZero))
                if pasos != aplicados { alCambiar(pasos - aplicados); aplicados = pasos; escalones += 1 }
                desplazamiento = v.translation.height + CGFloat(pasos) * Self.escalon
            }
            .onEnded { _ in
                aplicados = 0
                withAnimation(EstiloCarga.resorteDial) { desplazamiento = 0 }
            }
    }
}
