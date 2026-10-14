import SwiftUI
import MyPumpReglas
import MyPumpDatos

// El descanso entre series (SES-04), siempre a mano como el reproductor de Música:
// · iOS 26.1+: es el accesorio de la barra de pestañas (vidrio del sistema). Al bajar, la barra se achica y el
//   descanso queda en línea con ella, con lo justo: anillo, tiempo y saltar.
// · iOS 17-26.0: una isla flotante de material encima de la barra, con los mismos controles.
// El tiempo lo lleva el motor (`BarraDescanso`, anclado a una fecha de fin): esto solo lo pinta.

/// Lo que va adentro, igual en el accesorio y en la isla.
struct DescansoContenido: View {
    var compacto = false
    @Environment(Entrenamiento.self) private var entrenamiento
    private static let fuenteTiempo = Archivo.fija(20, peso: 700)
    private static let fuenteTiempoChica = Archivo.fija(16, peso: 700)

    var body: some View {
        if let m = entrenamiento.motor, m.descanso.visible {
            contenido(m)
        }
    }

    private func contenido(_ m: ModeloEntreno) -> some View {
        let b = m.descanso
        let listo = b.listo
        // `porcentaje` es lo que ya pasó; el anillo muestra lo que falta.
        let falta = listo ? 1 : max(0, 1 - (b.porcentaje ?? 0) / 100)
        return HStack(spacing: compacto ? 10 : 12) {
            AnilloProgreso(fraccion: falta, grosor: compacto ? 3 : 3.5, color: listo ? .exito : .marcaVivo) {
                Image(systemName: listo ? "checkmark" : "timer")
                    .font(.system(size: compacto ? 9 : 11, weight: .bold))
                    .foregroundStyle(listo ? Color.exito : Color.primary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(width: compacto ? 24 : 32, height: compacto ? 24 : 32)
            .animation(.linear(duration: 0.25), value: falta)

            VStack(alignment: .leading, spacing: 0) {
                if !compacto {
                    Text(listo ? "¡A la próxima serie!" : "Descanso \(b.textoObjetivo.replacingOccurrences(of: " objetivo", with: ""))")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(listo ? Color.exito : Color.secondary)
                        .lineLimit(1)
                }
                Text(b.texto)
                    .font(compacto ? Self.fuenteTiempoChica : Self.fuenteTiempo)
                    .monospacedDigit()
                    .contentTransition(.numericText(countsDown: true))
                    .animation(.snappy, value: b.texto)
                    .foregroundStyle(listo ? Color.exito : Color.primary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(listo ? "Descanso terminado" : "Descanso, quedan \(b.texto)")

            Spacer(minLength: 0)

            if !compacto {
                Button { m.ajustarDescanso(-15) } label: { Text("−15").frame(width: 44, height: 40) }
                    .accessibilityLabel("Restar 15 segundos")
                Button { m.ajustarDescanso(15) } label: { Text("+15").frame(width: 44, height: 40) }
                    .accessibilityLabel("Sumar 15 segundos")
            }
            Button { withAnimation(.smooth) { m.saltarDescanso() } } label: {
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
        .disabled(listo)
        // La barra tiene alto fijo (como la de pestañas): la letra se topea y, con letra de accesibilidad, mantener
        // apretado muestra el control en grande (Large Content Viewer).
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
        .accessibilityShowsLargeContentViewer()
        .sensoryFeedback(.impact(weight: .light), trigger: b.textoObjetivo)
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
    @Environment(Entrenamiento.self) private var entrenamiento

    var body: some View {
        DescansoContenido()
            .padding(.leading, 14)
            .padding(.trailing, 4)
            .padding(.vertical, 4)
            .vidrio(Capsule(), tinte: entrenamiento.motor?.descanso.listo == true ? .exito : nil)
            .padding(.horizontal, Espacio.m)
            .padding(.bottom, Espacio.xs)
            .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

extension View {
    /// El descanso arriba de las pestañas, una sola vez sobre la `TabView`: el reloj de 250 ms mientras se ve la barra
    /// y, desde iOS 26.1, el accesorio de la barra de pestañas.
    func accesorioDeDescanso() -> some View { modifier(DescansoEnPestanas()) }

    /// Antes de iOS 26.1 el descanso va como isla en cada pestaña, encima de la barra.
    func islaDeDescanso() -> some View { modifier(IslaDeDescanso()) }
}

/// Modificadores aparte (y no funciones que leen el motor): así el descanso, que cambia 4 veces por segundo, solo
/// vuelve a dibujar esto y no toda la raíz con sus cinco pestañas.
private struct DescansoEnPestanas: ViewModifier {
    @Environment(Entrenamiento.self) private var entrenamiento

    func body(content: Content) -> some View {
        let visible = entrenamiento.motor?.descanso.visible == true
        Group {
            if #available(iOS 26.1, *) {
                content.tabViewBottomAccessory(isEnabled: visible) { DescansoAccesorio() }
            } else {
                content
            }
        }
        .task(id: visible) { await entrenamiento.correrDescanso() }
    }
}

private struct IslaDeDescanso: ViewModifier {
    @Environment(Entrenamiento.self) private var entrenamiento

    func body(content: Content) -> some View {
        if #available(iOS 26.1, *) {
            content
        } else {
            let visible = entrenamiento.motor?.descanso.visible == true
            content
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if visible { DescansoBarra() }
                }
                .animation(.snappy, value: visible)
        }
    }
}
