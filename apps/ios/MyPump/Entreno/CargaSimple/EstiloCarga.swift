import SwiftUI

// El lenguaje visual de la carga de series: un instrumento de gimnasio. Un solo foco por serie (el número grande), pocas
// cajas, y todo el verde reservado para lo que avanza. Los colores y Archivo son los de `Tema.swift`.

extension Color {
    /// La superficie del panel: blanca en claro y, en oscuro, un escalón arriba de las tarjetas para que se note que flota.
    static let panelCarga = Color(claro: UIColor(hex: 0xFFFFFF), oscuro: UIColor(hex: 0x202223))
}

enum EstiloCarga {
    /// El resorte de todo lo que se mueve al confirmar: rápido y sin rebote de juguete.
    static let resorte = Animation.spring(response: 0.36, dampingFraction: 0.8)
    static let resorteDial = Animation.interpolatingSpring(stiffness: 460, damping: 30)

    /// iPhone SE y compañía: el panel achica el tambor para dejarle lugar a la lista.
    @MainActor static var pantallaChica: Bool {
        let alto = (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.screen.bounds.height ?? 800
        return alto < 700
    }
}

/// La superficie del panel: esquinas de arriba redondeadas, sombra hacia arriba en claro y filo de luz en oscuro.
struct SuperficiePanelCarga: View {
    @Environment(\.colorScheme) private var esquema

    var body: some View {
        let forma = UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28, style: .continuous)
        forma
            .fill(Color.panelCarga)
            .overlay { forma.strokeBorder(Color.borde, lineWidth: 1) }
            .shadow(color: .black.opacity(esquema == .dark ? 0.5 : 0.10), radius: 22, x: 0, y: -6)
            // Sigue por debajo de las pestañas: el panel no termina en un borde con la lista asomando abajo.
            .padding(.bottom, -160)
    }
}

/// El botón que registra: alto, con la luz arriba y una sombra del mismo verde. En la guardia cambia de color, sin moverse.
struct BotonConfirmar: ButtonStyle {
    var alerta = false
    var compacto = false

    func makeBody(configuration: Configuration) -> some View {
        Cuerpo(configuration: configuration, alerta: alerta, compacto: compacto)
    }

    private struct Cuerpo: View {
        let configuration: ButtonStyleConfiguration
        let alerta: Bool
        let compacto: Bool
        @Environment(\.isEnabled) private var habilitado
        @Environment(\.colorScheme) private var esquema

        var body: some View {
            let color = alerta ? Color.alerta : Color.marca
            configuration.label
                .foregroundStyle(habilitado ? (alerta && esquema == .light ? Color.white : Color.sobreMarca) : Color.secondary)
                .padding(.horizontal, compacto ? 14 : 20)
                .frame(maxWidth: .infinity, minHeight: compacto ? 48 : (EstiloCarga.pantallaChica ? 54 : 60))
                .background {
                    Capsule()
                        .fill(habilitado ? color : Color.campo)
                        .overlay {
                            if habilitado {
                                Capsule().fill(LinearGradient(colors: [.white.opacity(0.1), .clear], startPoint: .top, endPoint: .center))
                            }
                        }
                        .shadow(color: habilitado && !compacto ? color.opacity(esquema == .dark ? 0.28 : 0.32) : .clear, radius: 14, x: 0, y: 6)
                }
                .contentShape(.capsule)
                .scaleEffect(configuration.isPressed ? 0.965 : 1)
                .brightness(configuration.isPressed ? -0.05 : 0)
                .animation(.snappy(duration: 0.16), value: configuration.isPressed)
                .animation(.snappy(duration: 0.2), value: alerta)
        }
    }
}

/// − y + redondos: se hunden al apretar.
struct BotonCircularCarga: ButtonStyle {
    var lado: CGFloat = 60
    var tamañoIcono: CGFloat = 22

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: tamañoIcono, weight: .bold))
            .frame(width: lado, height: lado)
            .background(Color.campo, in: .circle)
            .contentShape(.circle)
            .scaleEffect(configuration.isPressed ? 0.88 : 1)
            .opacity(configuration.isPressed ? 0.75 : 1)
            .animation(.snappy(duration: 0.14), value: configuration.isPressed)
    }
}

/// El avance del ejercicio, un segmento por serie: hechas en verde lleno y el resto en el riel gris.
struct ProgresoSeries: View {
    let total: Int
    let hechas: Int
    let actual: Int?

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<max(total, 1), id: \.self) { i in
                Capsule()
                    // En oscuro el verde va lleno o no va: sin segmento «a medias» (al 36 % daba 1,9:1 y quedaba oliva).
                    .fill(i < hechas ? Color.avance : Color.riel)
                    .frame(height: 4)
            }
        }
        .animation(EstiloCarga.resorte, value: hechas)
        .accessibilityHidden(true)
    }
}
