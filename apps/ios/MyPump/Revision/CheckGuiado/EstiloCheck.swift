import SwiftUI

// El lenguaje visual del check guiado, en la línea de la carga de series: un foco por pantalla, pocas cajas y el verde solo
// para lo que avanza. Botones grandes y con texto (hay alumnos que no se llevan bien con la tecnología). Los colores y
// Archivo son los de `Tema.swift`; lo de acá lleva nombre propio para no chocar con las piezas de otras ramas.

extension Color {
    /// Lo que falta de una barra de avance: gris neutro. En oscuro el verde va lleno o no va (nada de verde translúcido).
    static let rielCheck = Color(claro: UIColor(white: 0, alpha: 0.12), oscuro: UIColor(white: 1, alpha: 0.16))
    /// El gris de las líneas de apoyo, con contraste AA sobre el fondo en claro y en oscuro.
    static let apoyoCheck = Color(claro: UIColor(hex: 0x55585F), oscuro: UIColor(white: 0.74, alpha: 1))
}

extension Font {
    static let tituloCheck = Archivo.fuente(32, relativoA: .title1)
    static let accionCheck = Archivo.fuente(19, peso: 700, relativoA: .headline)
    static let pesoCheck = Archivo.fuente(64, relativoA: .largeTitle)
    static let datoCheck = Archivo.fuente(20, peso: 700, relativoA: .title3)
}

/// El botón que avanza: cápsula alta, Archivo, luz arriba y sombra del mismo verde. Deshabilitado, gris pleno.
struct BotonCheck: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { Cuerpo(configuration: configuration) }

    private struct Cuerpo: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isEnabled) private var habilitado
        @Environment(\.colorScheme) private var esquema

        var body: some View {
            configuration.label
                .font(.accionCheck)
                .multilineTextAlignment(.center)
                .foregroundStyle(habilitado ? Color.sobreMarca : Color.apoyoCheck)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, minHeight: 58)
                .background {
                    Capsule()
                        .fill(habilitado ? Color.marca : Color.campo)
                        .overlay {
                            if habilitado {
                                Capsule().fill(LinearGradient(colors: [.white.opacity(0.1), .clear], startPoint: .top, endPoint: .center))
                            }
                        }
                        .shadow(color: habilitado ? Color.marca.opacity(esquema == .dark ? 0.26 : 0.30) : .clear, radius: 14, x: 0, y: 6)
                }
                .contentShape(.capsule)
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .brightness(configuration.isPressed ? -0.05 : 0)
                .animation(.snappy(duration: 0.16), value: configuration.isPressed)
        }
    }
}

/// La salida que acompaña al botón principal («Hoy no me pesé», «Las subo después»): texto solo, de ancho completo.
struct BotonCheckDiscreto: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(Color.primary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 48)
            .contentShape(.rect)
            .opacity(configuration.isPressed ? 0.55 : 1)
    }
}

/// El avance, un segmento por paso: los hechos y el de ahora en verde lleno, el resto en el riel gris.
struct AvanceCheck: View {
    let total: Int
    let hechos: Int

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<max(total, 1), id: \.self) { i in
                Capsule().fill(i < hechos ? Color.marca : Color.rielCheck).frame(height: 6)
            }
        }
        .animation(.spring(response: 0.36, dampingFraction: 0.8), value: hechos)
        .accessibilityHidden(true)
    }
}
