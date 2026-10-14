import SwiftUI
import MyPumpModelos

/// Check de la semana (REV-06): cuatro escalas de 1 a 5 y una nota. Cada escala es una fila de botones redondos con
/// sus extremos rotulados ("muy baja → excelente"); el botón dice qué falta en vez de quedar gris sin explicación.
struct CheckSemanal: View {
    let guardado: CheckinSemana?
    @State private var valores: [String: Int] = [:]
    @State private var nota = ""
    @State private var enviado = false
    @State private var cargado = false
    @FocusState private var escribiendo: Bool

    struct Metrica: Identifiable {
        let clave: String
        let nombre: String
        let icono: String
        let color: Color
        let bajo: String
        let alto: String
        var id: String { clave }
    }

    static let metricas = [
        Metrica(clave: "energia", nombre: "Energía", icono: "bolt.fill", color: .alerta, bajo: "muy baja", alto: "excelente"),
        Metrica(clave: "descanso", nombre: "Descanso", icono: "moon.zzz.fill", color: .sueno, bajo: "dormí mal", alto: "dormí bien"),
        Metrica(clave: "hambre", nombre: "Hambre", icono: "fork.knife", color: .corazon, bajo: "sin hambre", alto: "mucha"),
        Metrica(clave: "adherencia", nombre: "Adherencia", icono: "target", color: .marcaTexto, bajo: "me costó", alto: "la seguí"),
    ]

    private var faltan: [String] { Self.metricas.filter { valores[$0.clave] == nil }.map(\.nombre) }

    var body: some View {
        VStack(alignment: .leading, spacing: Espacio.s) {
            EncabezadoSeccion(titulo: "Check de la semana", detalle: enviado ? nil : "\(4 - faltan.count)/4")
                .overlay(alignment: .trailing) {
                    if enviado {
                        Label("Enviado", systemImage: "checkmark.circle.fill")
                            .labelStyle(EtiquetaCompacta())
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.marcaTexto)
                            .padding(.trailing, 4)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
            VStack(alignment: .leading, spacing: Espacio.l) {
                Text("Contame en 10 segundos cómo venís. Mati lo ve antes de tu devolución.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                ForEach(Self.metricas) { m in
                    EscalaCinco(metrica: m, valor: Binding(get: { valores[m.clave] }, set: { valores[m.clave] = $0 }))
                }

                TextField("Algo que quieras contarme (opcional)", text: $nota, axis: .vertical)
                    .lineLimit(2...5)
                    .focused($escribiendo)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Color.campo, in: .rect(cornerRadius: Radio.control, style: .continuous))

                VStack(spacing: Espacio.xs) {
                    Button {
                        escribiendo = false
                        withAnimation(.snappy) { enviado = true }
                    } label: {
                        Text(enviado ? "Actualizar mi check" : "Enviar mi check")
                    }
                    .buttonStyle(BotonMarca())
                    .disabled(!faltan.isEmpty)
                    .sensoryFeedback(.success, trigger: enviado) { _, nuevo in nuevo }
                    if !faltan.isEmpty {
                        Text("Faltan: \(faltan.joined(separator: ", "))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .contentTransition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .tarjeta()
        }
        .animation(.snappy, value: faltan)
        .onAppear {
            guard !cargado else { return }
            cargado = true
            if let g = guardado, g.energia != nil {
                valores = ["energia": g.energia, "descanso": g.descanso, "hambre": g.hambre, "adherencia": g.adherencia]
                    .compactMapValues { $0 }
                nota = g.nota ?? ""
                enviado = true
            }
        }
    }
}

/// Una escala de 1 a 5: cinco círculos de 44 pt; el elegido, en lima.
private struct EscalaCinco: View {
    let metrica: CheckSemanal.Metrica
    @Binding var valor: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: Espacio.xs) {
            Label(metrica.nombre, systemImage: metrica.icono)
                .font(.subheadline.weight(.semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.primary)
                .labelStyle(IconoTeñido(color: metrica.color))
            HStack(spacing: 0) {
                ForEach(1...5, id: \.self) { n in
                    let elegido = valor == n
                    Button {
                        withAnimation(.snappy(duration: 0.25)) { valor = elegido ? nil : n }
                    } label: {
                        Text("\(n)")
                            .font(.body.weight(.semibold).monospacedDigit())
                            .foregroundStyle(elegido ? Color.sobreMarca : Color.primary)
                            .frame(width: 44, height: 44)
                            .background(elegido ? Color.marca : Color.campo, in: .circle)
                            .scaleEffect(elegido ? 1.08 : 1)
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("\(metrica.nombre): \(n) de 5")
                    .accessibilityAddTraits(elegido ? .isSelected : [])
                }
            }
            HStack {
                Text(metrica.bajo)
                Spacer()
                Text(metrica.alto)
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 2)
            .accessibilityHidden(true)
        }
        .sensoryFeedback(.selection, trigger: valor)
    }
}

/// Ícono con su color y el título en el color del texto.
struct IconoTeñido: LabelStyle {
    let color: Color
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon.foregroundStyle(color).imageScale(.small)
            configuration.title
        }
    }
}
