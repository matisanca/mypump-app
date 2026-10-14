import SwiftUI

/// El descanso entre series, siempre a mano encima de la barra de pestañas (como el reproductor de Música).
/// Cuenta contra una FECHA de fin, no con un contador: sobrevive a irse de la app y volver.
struct DescansoBarra: View {
    let fin: Date
    let total: Int

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let restante = max(0, Int(fin.timeIntervalSince(ctx.date).rounded(.up)))
            HStack(spacing: 14) {
                ZStack {
                    Circle().stroke(Color(uiColor: .tertiarySystemFill), lineWidth: 4)
                    Circle()
                        .trim(from: 0, to: CGFloat(restante) / CGFloat(max(total, 1)))
                        .stroke(restante == 0 ? Color.exito : Color.marca, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 1), value: restante)
                    Image(systemName: restante == 0 ? "checkmark" : "timer").font(.caption.weight(.bold))
                }
                .frame(width: 38, height: 38)
                VStack(alignment: .leading, spacing: 0) {
                    Text(restante == 0 ? "¡A la próxima serie!" : "Descanso").font(.caption).foregroundStyle(.secondary)
                    Text(mmss(restante)).font(.numeroMediano).monospacedDigit().contentTransition(.numericText(countsDown: true))
                }
                Spacer()
                Button("−15") {}.buttonStyle(.bordered).controlSize(.small)
                Button("+15") {}.buttonStyle(.bordered).controlSize(.small)
                Button {} label: { Image(systemName: "forward.fill") }
                    .buttonStyle(.borderedProminent).tint(Color.marca).foregroundStyle(Color.sobreMarca).controlSize(.small)
                    .accessibilityLabel("Saltar descanso")
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(.regularMaterial, in: .rect(cornerRadius: 22, style: .continuous))
            .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
            .padding(.horizontal).padding(.bottom, 6)
            .sensoryFeedback(.success, trigger: restante == 0)
        }
    }
}
