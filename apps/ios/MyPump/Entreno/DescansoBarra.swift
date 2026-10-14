import SwiftUI

// El descanso entre series, siempre a mano como el reproductor de Música:
// · iOS 26.1+: es el accesorio de la barra de pestañas (vidrio del sistema). Al bajar, la barra se achica y el
//   descanso queda en línea con ella, con lo justo: anillo, tiempo y saltar.
// · iOS 17-26.0: una isla flotante de material encima de la barra, con los mismos controles.

/// Lo que va adentro, igual en el accesorio y en la isla.
struct DescansoContenido: View {
    var compacto = false
    @Environment(Descanso.self) private var descanso
    private static let fuenteTiempo = Archivo.fija(20, peso: 700)
    private static let fuenteTiempoChica = Archivo.fija(16, peso: 700)

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let restante = descanso.restante(a: ctx.date)
            let segundos = Int(restante.rounded(.up))
            let terminado = descanso.terminado || segundos == 0
            HStack(spacing: compacto ? 10 : 12) {
                AnilloProgreso(fraccion: terminado ? 1 : restante / max(descanso.total, 1),
                               grosor: compacto ? 3 : 3.5,
                               color: terminado ? .exito : .marcaVivo) {
                    Image(systemName: terminado ? "checkmark" : "timer")
                        .font(.system(size: compacto ? 9 : 11, weight: .bold))
                        .foregroundStyle(terminado ? Color.exito : Color.primary)
                        .contentTransition(.symbolEffect(.replace))
                }
                .frame(width: compacto ? 24 : 32, height: compacto ? 24 : 32)
                .animation(.linear(duration: 1), value: segundos)

                VStack(alignment: .leading, spacing: 0) {
                    if !compacto {
                        Text(terminado ? "¡A la próxima serie!" : "Descanso")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(terminado ? Color.exito : Color.secondary)
                            .lineLimit(1)
                    }
                    Text(mmss(segundos))
                        .font(compacto ? Self.fuenteTiempoChica : Self.fuenteTiempo)
                        .monospacedDigit()
                        .contentTransition(.numericText(countsDown: true))
                        .animation(.snappy, value: segundos)
                        .foregroundStyle(terminado ? Color.exito : Color.primary)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(terminado ? "Descanso terminado" : "Descanso, quedan \(segundos) segundos")

                Spacer(minLength: 0)

                if !compacto {
                    Button { descanso.ajustar(-15) } label: { Text("−15").frame(width: 44, height: 40) }
                        .accessibilityLabel("Restar 15 segundos")
                    Button { descanso.ajustar(15) } label: { Text("+15").frame(width: 44, height: 40) }
                        .accessibilityLabel("Sumar 15 segundos")
                }
                Button { descanso.saltar() } label: {
                    Image(systemName: "forward.end.fill")
                        .font(.system(size: compacto ? 11 : 13, weight: .bold))
                        .foregroundStyle(Color.sobreMarca)
                        .frame(width: compacto ? 28 : 34, height: compacto ? 28 : 34)
                        .background(Color.marca, in: .circle)
                        .frame(width: 44, height: 44)
                        .contentShape(.rect)
                }
                .accessibilityLabel("Saltar descanso")
            }
            .font(.subheadline.weight(.semibold).monospacedDigit())
            .buttonStyle(.plain)
            .disabled(terminado)
        }
        // La barra tiene alto fijo (como la de pestañas): la letra se topea y, con letra de accesibilidad, mantener
        // apretado muestra el control en grande (Large Content Viewer).
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
        .accessibilityShowsLargeContentViewer()
        .sensoryFeedback(.success, trigger: descanso.terminado) { _, nuevo in nuevo }
        .sensoryFeedback(.impact(weight: .light), trigger: descanso.ajustes)
    }
}

/// iOS 26: el accesorio de la barra de pestañas. Lee si está expandido o en línea con la barra achicada.
@available(iOS 26.0, *)
struct DescansoAccesorio: View {
    @Environment(\.tabViewBottomAccessoryPlacement) private var lugar

    var body: some View {
        DescansoContenido(compacto: lugar == .inline)
            .padding(.leading, lugar == .inline ? 10 : 14)
            .padding(.trailing, 4)
    }
}

/// iOS 17-26.0: la isla flotante. Mismo contenido, en una cápsula de material.
struct DescansoBarra: View {
    @Environment(Descanso.self) private var descanso

    var body: some View {
        DescansoContenido()
            .padding(.leading, 14)
            .padding(.trailing, 4)
            .padding(.vertical, 4)
            .vidrio(Capsule(), tinte: descanso.terminado ? .exito : nil)
            .padding(.horizontal, Espacio.m)
            .padding(.bottom, Espacio.xs)
            .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

extension View {
    /// Pone el descanso donde corresponda según la versión de iOS. Se aplica una sola vez, a la `TabView`.
    @ViewBuilder
    func accesorioDeDescanso(_ descanso: Descanso) -> some View {
        if #available(iOS 26.1, *) {
            tabViewBottomAccessory(isEnabled: descanso.activo) { DescansoAccesorio() }
        } else {
            self
        }
    }

    /// Antes de iOS 26.1 el descanso va como isla en cada pestaña, encima de la barra.
    @ViewBuilder
    func islaDeDescanso(_ descanso: Descanso) -> some View {
        if #available(iOS 26.1, *) {
            self
        } else {
            safeAreaInset(edge: .bottom, spacing: 0) {
                if descanso.activo { DescansoBarra() }
            }
            .animation(.snappy, value: descanso.activo)
        }
    }
}
