import SwiftUI
import UIKit

// Identidad de MyPump llevada a lo nativo: el verde lima de la marca como único acento, todo lo demás del sistema
// (fondos agrupados, SF Pro, SF Symbols, materiales) para que se sienta una app de iPhone y no una web.
//
// Reglas del sistema visual (valen para todas las pestañas):
// · Grilla de 8 pt (con medios pasos de 4): `Espacio`.
// · Esquinas continuas: tarjetas 24, controles 14, miniaturas 12, chips y botones principales en cápsula: `Radio`.
// · Los colores de la marca son los de la web: negro, blanco y el lima. El lima es un RELLENO con texto negro (botones,
//   selección, logros) y el color de los gráficos (`marcaVivo`); el texto y los íconos de acento van en negro en claro y
//   en lima en oscuro (`marcaTexto`). Mati, 15-oct: el verde oliva que había para el texto no es de la marca.
// · Vidrio solo en lo que flota sobre el contenido (barras, isla de descanso, compositor del chat): `Vidrio.swift`.
// · Archivo (la letra de la marca) para números grandes y títulos de día; el resto, SF Pro.

extension Color {
    /// Relleno de marca (botones principales, día hecho). Siempre con texto negro encima.
    static let marca = Color(red: 0xB8 / 255, green: 0xF0 / 255, blue: 0x60 / 255)
    static let sobreMarca = Color(red: 0x0A / 255, green: 0x0A / 255, blue: 0x0A / 255)
    /// Acento para TEXTO e íconos (links, la pestaña elegida, tildes): negro en claro, como el activo de la web, y lima en
    /// oscuro. El lima sobre blanco no se lee como texto.
    static let marcaTexto = Color(claro: UIColor(hex: 0x0A0A0A), oscuro: UIColor(hex: 0xB8F060))
    /// Fondo teñido de marca (fila confirmada, aviso de progresión).
    static let marcaSuave = Color(claro: UIColor(hex: 0xB8F060, alfa: 0.26), oscuro: UIColor(hex: 0xB8F060, alfa: 0.14))
    /// Lima para GRÁFICOS (anillos, líneas, barras, interruptores): el de la marca; en claro, el «hover» de la web
    /// (#A8E050), apenas más hondo para que una línea fina se vea sobre blanco.
    static let marcaVivo = Color(claro: UIColor(hex: 0xA8E050), oscuro: UIColor(hex: 0xB8F060))

    static let exito = Color(claro: UIColor(hex: 0x16A34A), oscuro: UIColor(hex: 0x30D158))
    static let alerta = Color(claro: UIColor(hex: 0xC2410C), oscuro: UIColor(hex: 0xFF9F0A))
    static let peligro = Color(claro: UIColor(hex: 0xDC2626), oscuro: UIColor(hex: 0xFF453A))
    static let sueno = Color(claro: UIColor(hex: 0x4F5BD5), oscuro: UIColor(hex: 0x7D8BFF))
    static let corazon = Color(claro: UIColor(hex: 0xE11D48), oscuro: UIColor(hex: 0xFF5C7A))
    /// Récords y trofeos: oro, no naranja de alerta (en claro, 4.9:1 sobre la tarjeta: se usa también como texto).
    static let record = Color(claro: UIColor(hex: 0xA16207), oscuro: UIColor(hex: 0xFFD60A))
    static let agua = Color(claro: UIColor(hex: 0x0A84FF), oscuro: UIColor(hex: 0x64D2FF))

    // Macros: tres tonos que se distinguen entre sí también en claro y que, como texto chico ("C 67"), pasan 4.5:1
    // sobre la tarjeta. Para que Dieta deje `.corazon` / `.alerta` / `.sueno`, que son señales y no macros (con
    // `.alerta` los carbos se confunden con las advertencias de la misma pantalla).
    static let proteina = Color(claro: UIColor(hex: 0xE11D48), oscuro: UIColor(hex: 0xFF5C7A))
    static let carbohidrato = Color(claro: UIColor(hex: 0xB45309), oscuro: UIColor(hex: 0xFFB020))
    static let grasa = Color(claro: UIColor(hex: 0x4F5BD5), oscuro: UIColor(hex: 0x7D8BFF))

    static let tarjeta = Color(uiColor: .secondarySystemGroupedBackground)
    static let fondo = Color(uiColor: .systemGroupedBackground)
    /// Superficie de un campo o control dentro de una tarjeta.
    static let campo = Color(uiColor: .tertiarySystemFill)
    /// Borde de pelo: separa la tarjeta del fondo en oscuro (donde no hay sombra que lo haga).
    static let borde = Color(claro: UIColor(white: 0, alpha: 0.05), oscuro: UIColor(white: 1, alpha: 0.08))

    init(claro: UIColor, oscuro: UIColor) {
        self.init(uiColor: UIColor { $0.userInterfaceStyle == .dark ? oscuro : claro })
    }
}

extension UIColor {
    convenience init(hex: UInt32, alfa: CGFloat = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: alfa)
    }
}

/// Grilla de 8 pt.
enum Espacio {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let s: CGFloat = 12
    static let m: CGFloat = 16
    static let l: CGFloat = 24
    static let xl: CGFloat = 32
    static let xxl: CGFloat = 48
}

/// Esquinas continuas, siempre las mismas.
enum Radio {
    static let tarjeta: CGFloat = 24
    static let control: CGFloat = 14
    static let miniatura: CGFloat = 12
}

/// Ancho de lectura en iPad: el contenido no se estira más que esto.
enum Ancho {
    static let lectura: CGFloat = 700
    static let doble: CGFloat = 1080
}

/// Archivo (la tipografía de la marca, OFL, de Omnibus-Type) solo para títulos de día y números grandes. Es variable:
/// el peso va por el eje `wght`. Se pide con `Font.custom(_:size:relativeTo:)`, así escala con Dynamic Type EN VIVO y
/// respeta los topes de `.dynamicTypeSize(...)` (un `UIFont` escalado con `UIFontMetrics` queda fijo en el tamaño del
/// arranque y no los respeta: medido en el simulador con letra de accesibilidad).
enum Archivo {
    static func fuente(_ tamaño: CGFloat, peso: CGFloat = 800, relativoA estilo: UIFont.TextStyle = .body) -> Font {
        Font.custom("Archivo", size: tamaño, relativeTo: Self.estilo(estilo)).weight(Self.peso(peso))
    }

    /// Tamaño fijo, sin Dynamic Type: solo para lo que vive en barras de alto fijo (la isla de descanso), que con
    /// letra de accesibilidad se lee con el visor de contenido grande.
    static func fija(_ tamaño: CGFloat, peso: CGFloat = 800) -> Font {
        Font.custom("Archivo", fixedSize: tamaño).weight(Self.peso(peso))
    }

    private static func peso(_ wght: CGFloat) -> Font.Weight {
        switch wght {
        case ..<150: .ultraLight
        case ..<250: .thin
        case ..<350: .light
        case ..<450: .regular
        case ..<550: .medium
        case ..<650: .semibold
        case ..<750: .bold
        case ..<850: .heavy
        default: .black
        }
    }

    private static func estilo(_ e: UIFont.TextStyle) -> Font.TextStyle {
        switch e {
        case .largeTitle: .largeTitle
        case .title1: .title
        case .title2: .title2
        case .title3: .title3
        case .headline: .headline
        case .subheadline: .subheadline
        case .callout: .callout
        case .footnote: .footnote
        case .caption1: .caption
        case .caption2: .caption2
        default: .body
        }
    }
}

extension Font {
    static let numeroGigante = Archivo.fuente(56, relativoA: .largeTitle)
    static let numeroGrande = Archivo.fuente(36, relativoA: .title1)
    static let numeroMediano = Archivo.fuente(22, peso: 700, relativoA: .title3)
    /// Números chicos en filas y chips grandes (kg de una fila, el anillo del día).
    static let numeroChico = Archivo.fuente(17, peso: 700, relativoA: .headline)
    static let tituloDia = Archivo.fuente(40, relativoA: .largeTitle)
}

extension View {
    /// La "ceja" que va arriba de un título: chica, en mayúsculas, espaciada y gris.
    func textoCeja() -> some View {
        font(.caption.weight(.semibold)).tracking(0.8).textCase(.uppercase).foregroundStyle(.secondary)
    }
}

// MARK: - Componentes

/// Tarjeta del sistema: fondo agrupado secundario, esquinas continuas, sombra suave en claro y borde de pelo en
/// oscuro (en negro una sombra no se ve: lo que separa es el borde).
struct Tarjeta: ViewModifier {
    var relleno: CGFloat

    init(relleno: CGFloat = 16) { self.relleno = relleno }

    func body(content: Content) -> some View {
        content
            .padding(relleno)
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(SuperficieTarjeta())
    }
}

/// Solo la superficie (fondo, borde y sombra), para lo que maneja su propio relleno (listas dentro de una tarjeta).
struct SuperficieTarjeta: ViewModifier {
    var radio: CGFloat = Radio.tarjeta
    var color: Color = .tarjeta
    @Environment(\.colorScheme) private var esquema

    func body(content: Content) -> some View {
        let forma = RoundedRectangle(cornerRadius: radio, style: .continuous)
        content
            .background(color, in: forma)
            .overlay { forma.strokeBorder(Color.borde, lineWidth: 1) }
            .shadow(color: .black.opacity(esquema == .dark ? 0 : 0.045), radius: 14, x: 0, y: 6)
    }
}

extension View {
    func tarjeta(relleno: CGFloat = 16) -> some View { modifier(Tarjeta(relleno: relleno)) }
    func superficieTarjeta(radio: CGFloat = Radio.tarjeta, color: Color = .tarjeta) -> some View {
        modifier(SuperficieTarjeta(radio: radio, color: color))
    }
}

/// Píldora chica de dato ("4 × 6-8", "RIR 1-2", "3:00"). Con un `tono` de color, el fondo se tiñe del mismo.
struct Chip: View {
    let texto: String
    var icono: String?
    var tono: Color = .secondary

    var body: some View {
        HStack(spacing: 4) {
            if let icono { Image(systemName: icono).imageScale(.small) }
            Text(texto).monospacedDigit()
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(tono)
        .lineLimit(1)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(tono == .secondary ? Color.campo : tono.opacity(0.14), in: .capsule)
    }
}

/// Botón principal de la marca: lima con texto negro, en cápsula como los del sistema. Deshabilitado no se desvanece
/// (un lima lavado parece un error): pasa a gris con el texto secundario.
struct BotonMarca: ButtonStyle {
    var compacto: Bool

    init(compacto: Bool = false) { self.compacto = compacto }

    func makeBody(configuration: Configuration) -> some View {
        CuerpoBotonMarca(configuration: configuration, compacto: compacto)
    }
}

private struct CuerpoBotonMarca: View {
    let configuration: ButtonStyleConfiguration
    let compacto: Bool
    @Environment(\.isEnabled) private var habilitado

    var body: some View {
        configuration.label
            .font(compacto ? .subheadline.weight(.semibold) : .headline)
            .foregroundStyle(habilitado ? Color.sobreMarca : Color.secondary)
            .padding(.horizontal, compacto ? 16 : 20)
            .frame(maxWidth: compacto ? nil : .infinity, minHeight: compacto ? 44 : 54)
            .background(habilitado ? Color.marca : Color.campo, in: .capsule)
            .contentShape(.capsule)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .brightness(configuration.isPressed ? -0.06 : 0)
            .animation(.snappy(duration: 0.18), value: configuration.isPressed)
    }
}

/// Botón secundario a juego: misma forma, relleno gris del sistema y texto de acento.
struct BotonSecundario: ButtonStyle {
    var compacto = false
    var tono: Color = .primary

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(compacto ? .subheadline.weight(.semibold) : .headline)
            .foregroundStyle(tono)
            .padding(.horizontal, compacto ? 16 : 20)
            .frame(maxWidth: compacto ? nil : .infinity, minHeight: compacto ? 44 : 54)
            .background(Color.campo, in: .capsule)
            .contentShape(.capsule)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(.snappy(duration: 0.18), value: configuration.isPressed)
    }
}

/// Encabezado de sección como los de Salud y Fitness: título en negrita, en minúscula de oración, con un detalle a
/// la derecha ("Fotos de la semana        0/3").
struct EncabezadoSeccion<Accesorio: View>: View {
    let titulo: String
    var detalle: String?
    /// Lo de la derecha que no es texto (el "Enviado" del check). Va adentro y no encima: como `.overlay` no ocupaba
    /// lugar y, con el título en varios renglones, se dibujaba sobre él.
    let accesorio: Accesorio
    @Environment(\.dynamicTypeSize) private var tamañoLetra

    init(titulo: String, detalle: String? = nil, @ViewBuilder accesorio: () -> Accesorio) {
        self.titulo = titulo; self.detalle = detalle; self.accesorio = accesorio()
    }

    var body: some View {
        // Con letra de accesibilidad, lo de la derecha va abajo del título: al lado lo dejaba en una columna angosta.
        let apilado = tamañoLetra.isAccessibilitySize
        let disposicion = apilado ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                                  : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: Espacio.xs))
        disposicion {
            Text(titulo).font(.title3.weight(.bold)).foregroundStyle(.primary)
                .accessibilityAddTraits(.isHeader)
            if !apilado { Spacer(minLength: Espacio.xs) }
            if let detalle {
                Text(detalle).font(.subheadline.weight(.medium).monospacedDigit()).foregroundStyle(.secondary)
            }
            accesorio
        }
        .padding(.horizontal, 4)
    }
}

extension EncabezadoSeccion where Accesorio == EmptyView {
    init(titulo: String, detalle: String? = nil) { self.init(titulo: titulo, detalle: detalle) { EmptyView() } }
}

/// Renglón de respaldo científico (Apple 1.4.1): pegado a los números, gris y chico, con "Ver fuentes" en el verde de
/// la marca. Es solo la etiqueta: lo que abre las 14 fuentes es `RenglonFuentes` (y `PieRespaldo` para el pie de
/// Dieta, Entreno y Mi Día), en `Respaldo/FuentesView.swift`.
struct RespaldoCientifico: View {
    var texto = "Objetivos calculados con Mifflin-St Jeor · macros según ISSN y NASEM"

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Image(systemName: "book.closed.fill").imageScale(.small)
            Text("\(texto) · \(Text("Ver fuentes").foregroundStyle(Color.marcaTexto).fontWeight(.semibold))")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.leading)
        .contentShape(.rect)
    }
}
