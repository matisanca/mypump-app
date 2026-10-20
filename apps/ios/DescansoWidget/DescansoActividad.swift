import ActivityKit
import SwiftUI
import WidgetKit

@main
struct DescansoWidgets: WidgetBundle {
    var body: some Widget { DescansoActividad() }
}

/// El verde del logo (#1D9330; en oscuro #5BBE62), como `Color.marca` de la app.
private let verde = Color(red: 0x1D / 255, green: 0x93 / 255, blue: 0x30 / 255)
private let verdeVivo = Color(red: 0x5B / 255, green: 0xBE / 255, blue: 0x62 / 255)

struct DescansoActividad: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DescansoAtributos.self) { contexto in
            PantallaBloqueada(estado: contexto.state, terminado: contexto.isStale)
                .activityBackgroundTint(Color.black.opacity(0.55))
                .activitySystemActionForegroundColor(verdeVivo)
        } dynamicIsland: { contexto in
            let e = contexto.state
            let terminado = contexto.isStale
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(terminado ? "Listo" : "Descanso", systemImage: terminado ? "checkmark.circle.fill" : "timer")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(verdeVivo)
                        .padding(.leading, 6)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Cuenta(estado: e, terminado: terminado)
                        .font(.title2.weight(.bold))
                        .padding(.trailing, 6)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Barra(estado: e, terminado: terminado)
                        Text(terminado ? "¡A la próxima serie!" : "Preparate para la próxima serie")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 6)
                }
            } compactLeading: {
                Image(systemName: terminado ? "checkmark.circle.fill" : "timer")
                    .foregroundStyle(verdeVivo)
            } compactTrailing: {
                Cuenta(estado: e, terminado: terminado)
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: 44)
            } minimal: {
                Image(systemName: terminado ? "checkmark" : "timer")
                    .foregroundStyle(verdeVivo)
            }
            .keylineTint(verdeVivo)
        }
    }
}

/// «1:29» que baja solo (el sistema lo actualiza, sin la app abierta), o «0:00» cuando terminó.
private struct Cuenta: View {
    let estado: DescansoAtributos.ContentState
    let terminado: Bool

    var body: some View {
        // Una sola lectura de la hora: dos podían caer a cada lado del fin y armar un rango al revés (y eso cierra la
        // extensión).
        let ahora = Date.now
        if terminado || estado.fin <= ahora {
            Text("0:00").monospacedDigit()
        } else {
            Text(timerInterval: ahora...estado.fin, countsDown: true, showsHours: false)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
        }
    }
}

/// La barra que se vacía hasta el fin.
private struct Barra: View {
    let estado: DescansoAtributos.ContentState
    let terminado: Bool

    var body: some View {
        let inicio = estado.fin.addingTimeInterval(-Double(max(estado.objetivo, 1)))
        if terminado || estado.fin <= Date.now {
            // Vacía, como la de la app: lo que falta es nada.
            ProgressView(value: 0).tint(verdeVivo)
        } else {
            ProgressView(timerInterval: inicio...estado.fin, countsDown: true) { EmptyView() } currentValueLabel: { EmptyView() }
                .tint(verdeVivo)
        }
    }
}

private struct PantallaBloqueada: View {
    let estado: DescansoAtributos.ContentState
    let terminado: Bool

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: terminado ? "checkmark.circle.fill" : "timer")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(verde, in: .circle)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(terminado ? "¡A la próxima serie!" : "Descanso")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Spacer(minLength: 8)
                    Cuenta(estado: estado, terminado: terminado)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.white)
                }
                Barra(estado: estado, terminado: terminado)
            }
        }
        .padding(16)
    }
}
