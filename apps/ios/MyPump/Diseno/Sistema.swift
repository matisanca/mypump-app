import SwiftUI

// PROPUESTA DE DISEÑO (rama descartable `nativa-diseno-propuesta`): el lenguaje de la carga rediseñada llevado al resto.
// Tres reglas, las mismas del panel de carga:
// · Un solo foco por pantalla: un número grande en Archivo que dice cómo voy.
// · Pocas cajas: lo que es contexto va sin fondo; la tarjeta queda para lo que se toca.
// · El verde es de lo que avanza: el botón que registra y el avance. Lo demás, neutro.
// Los colores, `Espacio`, `Radio` y `Archivo` siguen siendo los de `Tema.swift`; acá van las piezas nuevas.

/// La escala de letra, con nombre. Archivo para números y títulos de pantalla; SF para todo lo que se lee o se toca.
/// Todas escalan con Dynamic Type (van atadas a un estilo del sistema).
enum Letra {
    /// El número de la pantalla (kcal del día, kilos): 56 pt.
    static let heroe = Archivo.fuente(56, peso: 800, relativoA: .largeTitle)
    /// Título de pantalla o de día: 34 pt.
    static let titulo = Archivo.fuente(34, peso: 800, relativoA: .largeTitle)
    /// Número de una fila o de una columna: 22 pt.
    static let dato = Archivo.fuente(22, peso: 700, relativoA: .title3)
    /// El texto del botón principal: 19 pt.
    static let accion = Archivo.fuente(19, peso: 700, relativoA: .headline)
    /// Título de sección: SF 20 negrita.
    static let seccion = Font.title3.weight(.bold)
    /// Cuerpo y apoyo.
    static let cuerpo = Font.subheadline
    static let apoyo = Font.footnote
}

/// El botón que hace avanzar (Empezar, Comí, Entrar, Enviar): el OK de la carga para toda la app. Alto, en cápsula, con la
/// luz arriba y la sombra de su mismo verde. Uno solo por pantalla visible.
struct BotonAccion: ButtonStyle {
    var compacto = false

    func makeBody(configuration: Configuration) -> some View {
        Cuerpo(configuration: configuration, compacto: compacto)
    }

    private struct Cuerpo: View {
        let configuration: ButtonStyleConfiguration
        let compacto: Bool
        @Environment(\.isEnabled) private var habilitado
        @Environment(\.colorScheme) private var esquema

        var body: some View {
            configuration.label
                .font(compacto ? .headline : Letra.accion)
                .foregroundStyle(habilitado ? Color.sobreMarca : Color.secondary)
                .padding(.horizontal, compacto ? 16 : 20)
                .frame(maxWidth: .infinity, minHeight: compacto ? 48 : 58)
                .background {
                    Capsule()
                        .fill(habilitado ? Color.marca : Color.campo)
                        .overlay {
                            if habilitado {
                                Capsule().fill(LinearGradient(colors: [.white.opacity(0.1), .clear], startPoint: .top, endPoint: .center))
                            }
                        }
                        .shadow(color: habilitado && !compacto ? Color.marca.opacity(esquema == .dark ? 0.28 : 0.32) : .clear,
                                radius: 14, x: 0, y: 6)
                }
                .contentShape(.capsule)
                .scaleEffect(configuration.isPressed ? 0.965 : 1)
                .brightness(configuration.isPressed ? -0.05 : 0)
                .animation(.snappy(duration: 0.16), value: configuration.isPressed)
        }
    }
}

/// La salida discreta que acompaña al botón principal («Salté», «Dejar»): solo texto, con zona de toque de 44 pt.
struct BotonDiscreto: ButtonStyle {
    var tono: Color = .secondary

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(tono)
            .padding(.horizontal, 14)
            .frame(minHeight: 48)
            .contentShape(.rect)
            .opacity(configuration.isPressed ? 0.5 : 1)
    }
}

/// El avance en segmentos de la carga (uno por serie), para cualquier cuenta corta: ejercicios del día, fotos, el check.
/// Hechos en verde, el que sigue a medio encender y el resto apagados. Pasados los 12, una sola barra.
struct AvanceSegmentos: View {
    let total: Int
    let hechos: Int
    var alto: CGFloat = 5

    var body: some View {
        Group {
            if total > 12 {
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.campo)
                        Capsule().fill(Color.marca).frame(width: g.size.width * CGFloat(hechos) / CGFloat(max(total, 1)))
                    }
                }
            } else {
                HStack(spacing: 4) {
                    ForEach(0..<max(total, 1), id: \.self) { i in
                        Capsule().fill(i < hechos ? Color.marca : (i == hechos ? Color.marca.opacity(0.36) : Color.campo))
                    }
                }
            }
        }
        .frame(height: alto)
        .animation(.spring(response: 0.36, dampingFraction: 0.8), value: hechos)
        .accessibilityHidden(true)
    }
}

/// Una nota de contexto: ícono y texto, sin caja. Reemplaza a los recuadros teñidos cuando no hay nada que tocar ni nada
/// que anda mal (para eso sigue el aviso con fondo).
struct NotaDiscreta: View {
    let icono: String
    let texto: Text
    var tono: Color = .marcaTexto

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Espacio.xs) {
            Image(systemName: icono).font(.footnote.weight(.semibold)).foregroundStyle(tono).frame(width: 20)
            texto.font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
    }
}

/// Una fila de tarjeta que lleva a otro lado: azulejo, título, una línea y, a la derecha, el dato si lo hay. Reemplaza a
/// la tarjeta de tres pisos (título, texto, renglón «Ver…»).
struct FilaDestino<Dato: View>: View {
    let simbolo: String
    let color: Color
    let titulo: String
    let detalle: String?
    @ViewBuilder var dato: Dato

    var body: some View {
        HStack(spacing: Espacio.s) {
            IconoAzulejo(simbolo, color: color)
            VStack(alignment: .leading, spacing: 2) {
                Text(titulo).font(.headline).foregroundStyle(.primary)
                if let detalle {
                    Text(detalle).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            .multilineTextAlignment(.leading)
            Spacer(minLength: Espacio.xs)
            dato
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, Espacio.m)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
    }
}

/// Título de sección con su avance en segmentos debajo («Fotos de la semana», 1 de 3), en vez de la fracción gris.
struct EncabezadoAvance: View {
    let titulo: String
    let hechos: Int
    let total: Int
    var completo: String = "Completo"

    var body: some View {
        VStack(alignment: .leading, spacing: Espacio.xs) {
            HStack(alignment: .firstTextBaseline, spacing: Espacio.xs) {
                Text(titulo).font(Letra.seccion).accessibilityAddTraits(.isHeader)
                Spacer(minLength: Espacio.xs)
                if hechos >= total {
                    Label(completo, systemImage: "checkmark.circle.fill")
                        .labelStyle(EtiquetaCompacta())
                        .font(.subheadline.weight(.semibold)).foregroundStyle(Color.marcaTexto)
                } else {
                    (Text("\(hechos)").font(Letra.dato).foregroundStyle(.primary)
                        + Text(" de \(total)").font(.subheadline.weight(.medium)).foregroundStyle(.secondary))
                }
            }
            AvanceSegmentos(total: total, hechos: hechos)
        }
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
        .accessibilityValue("\(hechos) de \(total)")
    }
}
