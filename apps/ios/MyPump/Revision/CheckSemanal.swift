import SwiftUI
import MyPumpModelos
import MyPumpReglas
import MyPumpDatos

/// Check de la semana (REV-06): cuatro escalas de 1 a 5 y una nota. Cada escala es una fila de botones redondos con
/// sus extremos rotulados ("muy baja → excelente"); el botón dice qué falta en vez de quedar gris sin explicación.
/// Sale por la cola (`ModeloRevision.enviarCheckin`); en la demo y en los bocetos queda en la pantalla.
struct CheckSemanal: View {
    /// El modelo real, o nil con las muestras.
    let revision: ModeloRevision?
    let muestra: CheckinSemana?
    @State private var valores: [String: Int] = [:]
    @State private var nota = ""
    /// El cliente tocó algo: lo que llegue del servidor ya no pisa el borrador.
    @State private var editado = false
    @State private var enviadoMuestra = false
    @State private var envios = 0
    @State private var aviso: String?
    @FocusState private var escribiendo: Bool

    /// Ícono y color de cada escala (las claves y los textos salen de `CheckinSemanal.metricas`, como en la web).
    private static let estilo: [String: (icono: String, color: Color)] = [
        "energia": ("bolt.fill", .alerta), "descanso": ("moon.zzz.fill", .sueno),
        "hambre": ("fork.knife", .corazon), "adherencia": ("target", .marcaTexto),
    ]

    private var enviado: Bool { revision?.checkinEnviado ?? (enviadoMuestra || (muestra?.energia ?? 0) > 0) }
    private var faltan: String? { CheckinSemanal.faltan(valores) }

    var body: some View {
        VStack(alignment: .leading, spacing: Espacio.s) {
            EncabezadoSeccion(titulo: "Check de la semana",
                              detalle: enviado ? nil : "\(CheckinSemanal.metricas.count - CheckinSemanal.metricas.filter { (valores[$0.clave] ?? 0) == 0 }.count)/4") {
                if enviado {
                    Label("Enviado", systemImage: "checkmark.circle.fill")
                        .labelStyle(EtiquetaCompacta())
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.marcaTexto)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            VStack(alignment: .leading, spacing: Espacio.l) {
                Text("Contame en 10 segundos cómo venís. Mati lo ve antes de tu devolución.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                ForEach(CheckinSemanal.metricas, id: \.clave) { m in
                    EscalaCinco(metrica: m, icono: Self.estilo[m.clave]?.icono ?? "circle",
                                color: Self.estilo[m.clave]?.color ?? .secondary,
                                valor: Binding(get: { valores[m.clave] }, set: {
                                    valores[m.clave] = $0
                                    editado = true
                                    aviso = nil
                                }))
                }

                TextField("Algo que quieras contarme (opcional)", text: Binding(get: { nota }, set: { nota = $0; editado = true }),
                          axis: .vertical)
                    .lineLimit(2...5)
                    .focused($escribiendo)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Color.campo, in: .rect(cornerRadius: Radio.control, style: .continuous))

                VStack(spacing: Espacio.xs) {
                    Button(action: enviar) {
                        Text(enviado ? "Actualizar mi check" : "Enviar mi check")
                    }
                    .buttonStyle(BotonMarca())
                    .disabled(faltan != nil)
                    .sensoryFeedback(.success, trigger: envios)
                    .accessibilityIdentifier("enviar-check")
                    if let texto = aviso ?? faltan {
                        Text(texto)
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
        .animation(.snappy, value: enviado)
        // Lo guardado (o lo que se acaba de mandar) se muestra mientras el cliente no haya tocado nada.
        .onChange(of: revision?.checkin, initial: true) { _, c in
            guard !editado, let c else { return }
            valores = c.valores
            nota = c.nota
        }
        // Semana nueva: el formulario arranca vacío, como en la web. Antes quedaban las respuestas (y la nota) de la
        // anterior con "Enviar" habilitado: un toque las mandaba como las de esta semana (revisión, hallazgo 4).
        .onChange(of: revision?.semana) { _, _ in
            valores = [:]
            nota = ""
            editado = false
            aviso = nil
        }
        .onAppear {
            guard revision == nil, !editado, let m = muestra, m.energia != nil else { return }
            valores = ["energia": m.energia, "descanso": m.descanso, "hambre": m.hambre, "adherencia": m.adherencia].compactMapValues { $0 }
            nota = m.nota ?? ""
        }
    }

    private func enviar() {
        escribiendo = false
        guard let revision else {
            enviadoMuestra = true
            envios += 1
            return
        }
        let check = Checkin(valores: valores, nota: nota)
        Task {
            if let falta = await revision.enviarCheckin(check) {
                aviso = falta
            } else {
                editado = false
                envios += 1
            }
        }
    }
}

/// Una escala de 1 a 5: cinco círculos de 44 pt; el elegido, en lima. Tocar el elegido lo borra.
private struct EscalaCinco: View {
    let metrica: CheckinSemanal.Metrica
    let icono: String
    let color: Color
    @Binding var valor: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: Espacio.xs) {
            Label(metrica.etiqueta, systemImage: icono)
                .font(.subheadline.weight(.semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.primary)
                .labelStyle(IconoTeñido(color: color))
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
                    .accessibilityLabel("\(metrica.etiqueta): \(n) de 5")
                    .accessibilityAddTraits(elegido ? .isSelected : [])
                }
            }
            HStack {
                Text(metrica.bajo)
                Spacer()
                Text(metrica.alto)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
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
