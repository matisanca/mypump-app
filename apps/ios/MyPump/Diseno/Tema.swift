import SwiftUI
import UIKit

// Identidad de MyPump llevada a lo nativo: el verde lima de la marca como acento, todo lo demás del sistema
// (fondos agrupados, SF Pro, SF Symbols) para que se sienta una app de iPhone y no una web.

extension Color {
    /// Relleno de marca (botones principales, día hecho). Siempre con texto negro encima.
    static let marca = Color(red: 0xB8 / 255, green: 0xF0 / 255, blue: 0x60 / 255)
    static let sobreMarca = Color(red: 0x0A / 255, green: 0x0A / 255, blue: 0x0A / 255)
    /// Verde para TEXTO e íconos: el lima sobre blanco no tiene contraste, así que en claro va uno oscuro.
    static let marcaTexto = Color(claro: UIColor(red: 0x3F / 255, green: 0x62 / 255, blue: 0x12 / 255, alpha: 1),
                                  oscuro: UIColor(red: 0xB8 / 255, green: 0xF0 / 255, blue: 0x60 / 255, alpha: 1))
    static let marcaSuave = Color(claro: UIColor(red: 0xB8 / 255, green: 0xF0 / 255, blue: 0x60 / 255, alpha: 0.22),
                                  oscuro: UIColor(red: 0xB8 / 255, green: 0xF0 / 255, blue: 0x60 / 255, alpha: 0.16))
    static let exito = Color(claro: UIColor(red: 0x16 / 255, green: 0xA3 / 255, blue: 0x4A / 255, alpha: 1),
                             oscuro: UIColor(red: 0x22 / 255, green: 0xC5 / 255, blue: 0x5E / 255, alpha: 1))
    static let alerta = Color(claro: UIColor(red: 0xD9 / 255, green: 0x77 / 255, blue: 0x06 / 255, alpha: 1),
                              oscuro: UIColor(red: 0xFB / 255, green: 0xBF / 255, blue: 0x24 / 255, alpha: 1))
    static let peligro = Color(claro: UIColor(red: 0xDC / 255, green: 0x26 / 255, blue: 0x26 / 255, alpha: 1),
                               oscuro: UIColor(red: 0xEF / 255, green: 0x44 / 255, blue: 0x44 / 255, alpha: 1))
    static let sueno = Color(red: 0x5B / 255, green: 0x6E / 255, blue: 0xE1 / 255)
    static let corazon = Color(red: 0xE1 / 255, green: 0x5B / 255, blue: 0x6E / 255)
    static let tarjeta = Color(uiColor: .secondarySystemGroupedBackground)
    static let fondo = Color(uiColor: .systemGroupedBackground)

    init(claro: UIColor, oscuro: UIColor) {
        self.init(uiColor: UIColor { $0.userInterfaceStyle == .dark ? oscuro : claro })
    }
}

/// Archivo (la tipografía de la marca, OFL) solo para títulos de día y números grandes. Es variable: el peso se pide
/// por el eje `wght` y escala con Dynamic Type como el estilo de texto al que acompaña.
enum Archivo {
    static func fuente(_ tamaño: CGFloat, peso: CGFloat = 800, relativoA estilo: UIFont.TextStyle = .body) -> Font {
        let wght = 0x77676874 // 'wght'
        let descriptor = UIFontDescriptor(fontAttributes: [
            .name: "Archivo",
            UIFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String): [wght: peso],
        ])
        let base = UIFont(descriptor: descriptor, size: tamaño)
        return Font(UIFontMetrics(forTextStyle: estilo).scaledFont(for: base))
    }
}

extension Font {
    static let numeroGigante = Archivo.fuente(52, relativoA: .largeTitle)
    static let numeroGrande = Archivo.fuente(34, relativoA: .title1)
    static let numeroMediano = Archivo.fuente(22, peso: 700, relativoA: .title3)
    static let tituloDia = Archivo.fuente(30, relativoA: .largeTitle)
}

// MARK: - Componentes

/// Tarjeta del sistema: fondo agrupado secundario, esquinas continuas.
struct Tarjeta: ViewModifier {
    var relleno: CGFloat = 16
    func body(content: Content) -> some View {
        content
            .padding(relleno)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.tarjeta, in: .rect(cornerRadius: 18, style: .continuous))
    }
}

extension View {
    func tarjeta(relleno: CGFloat = 16) -> some View { modifier(Tarjeta(relleno: relleno)) }
}

/// Píldora chica de dato ("4 × 6-8", "RIR 1-2", "3:00").
struct Chip: View {
    let texto: String
    var icono: String?
    var tono: Color = .secondary

    var body: some View {
        HStack(spacing: 4) {
            if let icono { Image(systemName: icono).imageScale(.small) }
            Text(texto).monospacedDigit()
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(tono)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(uiColor: .tertiarySystemFill), in: .capsule)
    }
}

/// Botón principal de la marca: lima con texto negro, como en la web, pero con la forma del sistema.
struct BotonMarca: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Color.sobreMarca)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(Color.marca.opacity(configuration.isPressed ? 0.8 : 1), in: .rect(cornerRadius: 16, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

/// Encabezado de sección con contador a la derecha ("BLOQUE 1 · ESPALDA      0/3").
struct EncabezadoSeccion: View {
    let titulo: String
    var detalle: String?

    var body: some View {
        HStack {
            Text(titulo.uppercased()).font(.footnote.weight(.semibold)).foregroundStyle(.secondary).tracking(0.6)
            Spacer()
            if let detalle { Text(detalle).font(.footnote.monospacedDigit()).foregroundStyle(.secondary) }
        }
        .padding(.horizontal, 4)
    }
}

/// Renglón de respaldo científico (Apple 1.4.1): pegado a los números, gris y chico, abre las fuentes.
struct RespaldoCientifico: View {
    var texto = "Objetivos calculados con Mifflin-St Jeor · macros según ISSN y NASEM"
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Image(systemName: "book.closed").imageScale(.small)
            Text(texto) + Text(" · ") + Text("Ver fuentes").foregroundStyle(Color.marcaTexto)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
}
