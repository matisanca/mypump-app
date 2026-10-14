import SwiftUI

// Liquid Glass (iOS 26) para lo que flota sobre el contenido, con un material del sistema como respaldo en iOS 17-25.
// Nunca en tarjetas de contenido: el vidrio es la capa de navegación y control, no la de lectura.

extension View {
    /// Vidrio en la forma dada. En iOS 26 es `glassEffect` (con tinte e interacción si se piden); antes, un material
    /// grueso con borde de pelo y sombra, que es lo más parecido que tiene el sistema.
    @ViewBuilder
    func vidrio(_ forma: some Shape = Capsule(), tinte: Color? = nil, interactivo: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(Glass.regular.tint(tinte).interactive(interactivo), in: forma)
        } else {
            background {
                ZStack {
                    forma.fill(.regularMaterial)
                    if let tinte { forma.fill(tinte.opacity(0.18)) }
                }
                .overlay { forma.stroke(Color.borde, lineWidth: 1) }
                .shadow(color: .black.opacity(0.14), radius: 16, x: 0, y: 6)
            }
        }
    }
}

/// Agrupa vidrios vecinos para que se fundan entre sí (iOS 26). Antes de iOS 26 no hace nada.
struct ContenedorVidrio<Contenido: View>: View {
    var espaciado: CGFloat = 8
    @ViewBuilder var contenido: Contenido

    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: espaciado) { contenido }
        } else {
            contenido
        }
    }
}

extension View {
    /// iOS 26: el subtítulo nativo bajo el título grande. Antes no hay dónde ponerlo y se omite (el dato está en la
    /// pantalla de otra forma).
    @ViewBuilder
    func subtituloNavegacion(_ texto: String?) -> some View {
        if #available(iOS 26.0, *), let texto {
            navigationSubtitle(texto)
        } else {
            self
        }
    }

    /// iOS 26: la barra de pestañas se achica al bajar, como en Música, y deja más pantalla al entrenamiento.
    @ViewBuilder
    func barraQueSeAchica() -> some View {
        if #available(iOS 26.0, *) {
            tabBarMinimizeBehavior(.onScrollDown)
        } else {
            self
        }
    }
}
