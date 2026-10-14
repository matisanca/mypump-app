import SwiftUI
import MyPumpModelos

// Componentes compartidos por todas las pestañas. Los que ya existían (`Dato`, `Miniatura`, `mmss`, `cargaTexto`)
// conservan nombre y firma: Dieta los usa.

/// Un dato con su rótulo: "Última vez · 58 kg × 9 · hace 13 días". El valor va en Archivo.
struct Dato: View {
    let titulo: String
    let valor: String
    var detalle: String?
    var icono: String
    var tono: Color = .secondary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(titulo, systemImage: icono)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tono)
                .labelStyle(EtiquetaCompacta())
            Text(valor)
                .font(.numeroMediano)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText())
            if let detalle {
                Text(detalle).font(.caption).foregroundStyle(.secondary)
            }
        }
        .tarjeta(relleno: 14)
        .accessibilityElement(children: .combine)
    }
}

/// Ícono pegado al texto, más chico que el de `Label` por defecto (para rótulos de una línea).
struct EtiquetaCompacta: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        // Alineado a la primera línea: con letra grande el texto ocupa varios renglones y el ícono va arriba.
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            configuration.icon.imageScale(.small)
            configuration.title
        }
    }
}

/// Miniatura del ejercicio (la foto del catálogo) o, si no hay, un ícono del tipo sobre gris.
struct Miniatura: View {
    let url: String?
    let tipo: String?
    var lado: CGFloat = 60

    var body: some View {
        Group {
            if let url, let u = URL(string: url) {
                AsyncImage(url: u, transaction: Transaction(animation: .easeOut(duration: 0.25))) { fase in
                    if let img = fase.image { img.resizable().scaledToFill() } else { marcador }
                }
            } else { marcador }
        }
        .frame(width: lado, height: lado)
        .clipShape(.rect(cornerRadius: Radio.miniatura, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Radio.miniatura, style: .continuous).strokeBorder(Color.borde, lineWidth: 1)
        }
        .accessibilityHidden(true)
    }

    private var marcador: some View {
        ZStack {
            Color.campo
            Image(systemName: Self.simbolo(tipo))
                .font(.system(size: lado * 0.34, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
    }

    static func simbolo(_ tipo: String?) -> String {
        switch tipo {
        case "cardio": "figure.run"
        case "core": "figure.core.training"
        case "calentamiento": "figure.flexibility"
        default: "dumbbell.fill"
        }
    }
}

func mmss(_ s: Int) -> String { String(format: "%d:%02d", s / 60, s % 60) }

/// "52,5 kg × 7" o, si fue con el peso del cuerpo, "12 reps".
func cargaTexto(_ r: RegistroHistorico) -> String {
    if let kg = r.pesoKg, kg > 0 { return "\(kg.kg) kg × \(r.reps ?? 0)" }
    return "\(r.reps ?? 0) reps"
}

/// Anillo de progreso con pista (como los de Actividad). El centro es libre.
struct AnilloProgreso<Centro: View>: View {
    let fraccion: Double
    var grosor: CGFloat = 8
    var color: Color = .marcaVivo
    var pista: Color = .campo
    @ViewBuilder var centro: Centro

    var body: some View {
        ZStack {
            Circle().stroke(pista, lineWidth: grosor)
            // En cero no se dibuja nada: la tapa redonda de un trazo vacío queda como un punto suelto.
            if fraccion > 0.001 {
                Circle()
                    .trim(from: 0, to: min(fraccion, 1))
                    .stroke(color, style: StrokeStyle(lineWidth: grosor, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            centro
        }
        .padding(grosor / 2)
    }
}

extension AnilloProgreso where Centro == EmptyView {
    init(fraccion: Double, grosor: CGFloat = 8, color: Color = .marcaVivo, pista: Color = .campo) {
        self.init(fraccion: fraccion, grosor: grosor, color: color, pista: pista) { EmptyView() }
    }
}

/// Un punto por serie: lleno las confirmadas. Es lo que muestra la tarjeta cerrada de la web.
struct PuntosSeries: View {
    let total: Int
    let hechas: Int

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<max(total, 0), id: \.self) { i in
                Capsule()
                    .fill(i < hechas ? Color.marcaVivo : Color.campo)
                    .frame(width: i < hechas ? 10 : 6, height: 6)
            }
        }
        .animation(.snappy, value: hechas)
        .accessibilityElement()
        .accessibilityLabel("\(hechas) de \(total) series")
    }
}

/// Ícono en azulejo redondeado, como los de Ajustes.
struct IconoAzulejo: View {
    let simbolo: String
    let color: Color
    @ScaledMetric(relativeTo: .body) private var lado: CGFloat = 30

    init(_ simbolo: String, color: Color) {
        self.simbolo = simbolo
        self.color = color
    }

    var body: some View {
        Image(systemName: simbolo)
            .font(.system(size: lado * 0.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: lado, height: lado)
            .background(color.gradient, in: .rect(cornerRadius: lado * 0.27, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// Fila que se ilumina al tocarla (para NavigationLink dentro de una tarjeta propia).
struct FilaPresionable: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color.primary.opacity(0.06) : Color.clear)
            .contentShape(.rect)
    }
}

/// Botón de acción en tarjeta: ícono arriba, rótulo abajo, como las acciones de Contactos.
struct AccionTarjeta: ButtonStyle {
    var tono: Color = .marcaTexto

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .labelStyle(AccionApilada(tono: tono))
            .frame(maxWidth: .infinity, minHeight: 64)
            .padding(.vertical, 6)
            .superficieTarjeta(radio: Radio.control + 4)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.snappy(duration: 0.18), value: configuration.isPressed)
    }

    private struct AccionApilada: LabelStyle {
        let tono: Color
        func makeBody(configuration: Configuration) -> some View {
            VStack(spacing: 6) {
                configuration.icon.font(.title3).foregroundStyle(tono)
                configuration.title.font(.caption.weight(.semibold)).foregroundStyle(.primary)
            }
        }
    }
}

/// Fila de chips que salta de renglón cuando no entra (con letra grande no se corta nada).
struct FilaFluida: Layout {
    var espaciado: CGFloat = 6
    var interlineado: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let ancho = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, alto: CGFloat = 0, maxX: CGFloat = 0
        for s in subviews {
            let t = s.sizeThatFits(.unspecified)
            let w = min(t.width, ancho)
            if x > 0, x + w > ancho { x = 0; y += alto + interlineado; alto = 0 }
            x += w + espaciado
            maxX = max(maxX, x - espaciado)
            alto = max(alto, t.height)
        }
        return CGSize(width: proposal.width ?? maxX, height: y + alto)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, alto: CGFloat = 0
        for s in subviews {
            let t = s.sizeThatFits(.unspecified)
            let w = min(t.width, bounds.width)
            if x > bounds.minX, x + w > bounds.maxX { x = bounds.minX; y += alto + interlineado; alto = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(width: w, height: t.height))
            x += w + espaciado
            alto = max(alto, t.height)
        }
    }
}

/// Esqueleto de carga: el contenido real tapado (`redacted`) con un brillo que pasa. Respeta Reducir movimiento.
struct Esqueleto: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reducir
    @State private var fase: CGFloat = -1

    func body(content: Content) -> some View {
        content
            .redacted(reason: .placeholder)
            .overlay {
                if !reducir {
                    GeometryReader { geo in
                        LinearGradient(colors: [.clear, .white.opacity(0.35), .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: geo.size.width * 0.6)
                            .offset(x: fase * geo.size.width * 1.4)
                            .blendMode(.plusLighter)
                    }
                    .mask(content.redacted(reason: .placeholder))
                    .allowsHitTesting(false)
                }
            }
            .onAppear {
                withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) { fase = 1 }
            }
            .accessibilityLabel("Cargando")
    }
}

/// Para `List` y `Form` en iPad: los márgenes crecen para que las secciones no pasen del ancho de lectura. En el
/// teléfono no hace nada (quedan los márgenes del sistema).
struct MargenesDeLectura: ViewModifier {
    var maximo: CGFloat = Ancho.lectura
    @State private var ancho: CGFloat = 0

    func body(content: Content) -> some View {
        Group {
            if ancho > maximo + 2 * Espacio.l {
                content.contentMargins(.horizontal, (ancho - maximo) / 2, for: .scrollContent)
            } else {
                content
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { ancho = $0 }
    }
}

extension View {
    func esqueleto() -> some View { modifier(Esqueleto()) }
    func margenesDeLectura(_ maximo: CGFloat = Ancho.lectura) -> some View { modifier(MargenesDeLectura(maximo: maximo)) }

    /// Columna de lectura: en iPad el contenido no pasa de `maximo` y queda centrado.
    func anchoLectura(_ maximo: CGFloat = Ancho.lectura) -> some View {
        frame(maxWidth: maximo).frame(maxWidth: .infinity)
    }
}

/// Los nombres del catálogo traen el músculo entre paréntesis: "Jalón al pecho prono (dorsal ancho)". Se muestran en
/// dos renglones con jerarquía: el ejercicio y, abajo, el músculo. El nombre completo sigue entero para VoiceOver.
struct NombreEjercicio {
    let principal: String
    let detalle: String?

    init(_ nombre: String) {
        let limpio = nombre.trimmingCharacters(in: .whitespaces)
        if limpio.hasSuffix(")"), let abre = limpio.range(of: " (", options: .backwards) {
            principal = String(limpio[..<abre.lowerBound])
            let d = String(limpio[abre.upperBound...].dropLast()).trimmingCharacters(in: .whitespaces)
            detalle = d.isEmpty ? nil : d.prefix(1).uppercased() + d.dropFirst()
        } else {
            principal = limpio
            detalle = nil
        }
    }
}

extension String {
    /// "BLOQUE 1 — ESPALDA" → "Espalda"; "TIRÓN" → "Tirón". Lo que no viene en mayúsculas queda tal cual.
    var enOracion: String {
        guard self == uppercased(), contains(where: \.isLetter) else { return self }
        let minus = lowercased()
        return minus.prefix(1).uppercased() + minus.dropFirst()
    }
}
