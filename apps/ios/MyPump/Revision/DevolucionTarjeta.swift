import SwiftUI
import MyPumpModelos
import MyPumpReglas
import MyPumpDatos

/// «Devolución de Mati», arriba de todo en Revisión: lo que Mati le dice de su semana, como un mensaje suyo. Debajo, las
/// semanas anteriores, que se abren de a una. Sin devolución publicada (o con la palanca apagada) no se muestra nada.
struct DevolucionTarjeta: View {
    let ultima: DevolucionSemanal
    let anteriores: [DevolucionSemanal]

    var body: some View {
        VStack(alignment: .leading, spacing: Espacio.s) {
            MensajeDeMati(devolucion: ultima, destacada: true)
            if !anteriores.isEmpty { Historial(devoluciones: anteriores) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("devolucion-seccion")
    }
}

/// Las iniciales de Mati en un círculo de la marca: lo que lo hace sentir un mensaje de una persona y no un aviso.
private struct FirmaMati: View {
    @ScaledMetric(relativeTo: .headline) private var lado: CGFloat = 40

    var body: some View {
        Text("M")
            .font(.system(size: lado * 0.46, weight: .bold, design: .rounded))
            .foregroundStyle(Color.sobreMarca)
            .frame(width: lado, height: lado)
            .background(
                LinearGradient(colors: [Color.marca, Color.marcaTexto], startPoint: .topLeading, endPoint: .bottomTrailing),
                in: .circle
            )
            .accessibilityHidden(true)
    }
}

struct MensajeDeMati: View {
    let devolucion: DevolucionSemanal
    let destacada: Bool
    @Environment(\.dynamicTypeSize) private var tipo
    @Environment(\.colorScheme) private var esquema

    private var nueva: Bool { destacada && ReglasDevolucion.esNueva(devolucion) }

    var body: some View {
        VStack(alignment: .leading, spacing: Espacio.m) {
            encabezado
            VStack(alignment: .leading, spacing: Espacio.s) {
                ForEach(Array(devolucion.lineas.enumerated()), id: \.offset) { _, l in
                    Text(l)
                        .font(.body)
                        .lineSpacing(3)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.leading, Espacio.s + 2)
            .overlay(alignment: .leading) {
                Capsule().fill(Color.marca.opacity(esquema == .dark ? 0.55 : 0.4)).frame(width: 3)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("devolucion-texto")
        }
        .padding(Espacio.m + 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            // Un velo verde muy suave arriba: cálido y de la marca, sin competir con el texto.
            LinearGradient(colors: [Color.marcaSuave, Color.marcaSuave.opacity(0)], startPoint: .top, endPoint: .center)
                .clipShape(.rect(cornerRadius: Radio.tarjeta, style: .continuous))
        }
        .modifier(SuperficieTarjeta())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("devolucion-tarjeta")
    }

    @ViewBuilder private var encabezado: some View {
        let textos = VStack(alignment: .leading, spacing: 2) {
            Text("Devolución de Mati")
                .font(.headline)
                .foregroundStyle(.primary)
            Text(devolucion.etiqueta)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)

        if tipo.isAccessibilitySize {
            VStack(alignment: .leading, spacing: Espacio.xs) {
                HStack { FirmaMati(); Spacer(minLength: 0); if nueva { Nueva() } }
                textos
            }
        } else {
            HStack(alignment: .center, spacing: Espacio.s) {
                FirmaMati()
                textos
                Spacer(minLength: Espacio.xs)
                if nueva { Nueva() }
            }
        }
    }
}

private struct Nueva: View {
    var body: some View {
        Text("Nueva")
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.marcaTexto)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color.marcaSuave, in: .capsule)
            .accessibilityIdentifier("devolucion-nueva")
    }
}

/// Las semanas anteriores: una fila por semana con el principio del mensaje; tocar la abre ahí mismo.
private struct Historial: View {
    let devoluciones: [DevolucionSemanal]
    @State private var abierta: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Semanas anteriores")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, Espacio.m)
                .padding(.top, Espacio.s)
                .padding(.bottom, Espacio.xs)
                .accessibilityAddTraits(.isHeader)
            ForEach(Array(devoluciones.enumerated()), id: \.element.id) { i, d in
                if i > 0 { Divider().padding(.leading, Espacio.m) }
                fila(d)
            }
        }
        .padding(.bottom, Espacio.xs)
        .modifier(SuperficieTarjeta())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("devolucion-historial")
    }

    @ViewBuilder private func fila(_ d: DevolucionSemanal) -> some View {
        let abiertaEsta = abierta == d.id
        Button {
            withAnimation(.snappy) { abierta = abiertaEsta ? nil : d.id }
        } label: {
            VStack(alignment: .leading, spacing: Espacio.xs) {
                HStack(alignment: .firstTextBaseline, spacing: Espacio.s) {
                    Text(d.etiqueta)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(abiertaEsta ? 180 : 0))
                        .accessibilityHidden(true)
                }
                if abiertaEsta {
                    VStack(alignment: .leading, spacing: Espacio.xs) {
                        ForEach(Array(d.lineas.enumerated()), id: \.offset) { _, l in
                            Text(l).font(.subheadline).foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                } else {
                    Text(d.lineas.first ?? "")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .multilineTextAlignment(.leading)
            .padding(.horizontal, Espacio.m)
            .padding(.vertical, Espacio.s)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(FilaPresionable())
        .accessibilityElement(children: .combine)
        .accessibilityHint(abiertaEsta ? "Cierra esta devolución" : "Abre esta devolución")
        .accessibilityIdentifier("devolucion-anterior-\(d.id)")
    }
}
