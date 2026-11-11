import SwiftUI

/// Una ilustración de la pantalla de presión arterial (GRAFICOS.md): `presion_g1_postura`, `presion_g5_03`,
/// `presion_tilde`…
///
/// Cada dibujo son dos imágenes de plantilla del catálogo (`Presion/<nombre>_base` y `<nombre>_acento`), generadas
/// por `scripts/nativa/presion-dibujos.mjs` desde la misma fuente que la web y Android. La base toma el color del
/// texto y el acento (el manguito) el verde de la marca, así se ven bien en claro y en oscuro. No llevan texto
/// adentro: los títulos y las aclaraciones van al lado, en componentes nativos, y `alt` es lo que lee VoiceOver.
struct DibujoPresion: View {
    private let nombre: String
    private let alt: String

    init(_ nombre: String, alt: String) {
        self.nombre = nombre
        self.alt = alt
    }

    var body: some View {
        ZStack {
            capa("base").foregroundStyle(.primary)
            capa("acento").foregroundStyle(Color.marcaVivo)
        }
        .aspectRatio(Self.proporcion(nombre), contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel(alt)
        .accessibilityAddTraits(.isImage)
    }

    private func capa(_ sufijo: String) -> some View {
        Image("\(nombre)_\(sufijo)")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
    }

    /// Ancho sobre alto del viewBox: 360 × 240 las ilustraciones; cuadradas las tarjetas de «Qué evitar» (96 × 96)
    /// y los íconos de tilde y cruz (24 × 24).
    private static func proporcion(_ nombre: String) -> CGFloat {
        nombre.hasPrefix("presion_g5_") || nombre == "presion_tilde" || nombre == "presion_cruz" ? 1 : 360.0 / 240.0
    }
}
