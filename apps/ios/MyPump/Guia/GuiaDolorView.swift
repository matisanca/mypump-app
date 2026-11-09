import SwiftUI
import MyPumpReglas

/// Un recuadro de «Lo que más te importa» o de una parte «## Título», como `.dolor` en `pack.html`: el texto siempre a la
/// vista y abajo el capítulo plegable con sus videos, si tiene.
struct TarjetaDolor<Videos: View>: View {
    let titulo: String
    var subtitulo: String? = nil
    let parrafos: [String]
    let identificador: String
    @ViewBuilder var videos: () -> Videos

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: Espacio.s) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: titulo).font(.title3.weight(.bold)).accessibilityAddTraits(.isHeader)
                    if let subtitulo {
                        Text(verbatim: subtitulo).font(.subheadline.weight(.semibold)).foregroundStyle(Color.marcaTexto)
                    }
                }
                ForEach(Array(parrafos.enumerated()), id: \.offset) { i, p in
                    Text(verbatim: p).font(.body)
                        .accessibilityIdentifier("\(identificador)-parrafo-\(i)")
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            videos()
        }
        .superficieTarjeta(radio: Radio.control + 6)
        .overlay {
            RoundedRectangle(cornerRadius: Radio.control + 6, style: .continuous)
                .strokeBorder(Color.marca, lineWidth: 1)
                .accessibilityHidden(true)
        }
        .clipShape(RoundedRectangle(cornerRadius: Radio.control + 6, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identificador)
    }
}

/// El mapa de pasos de la cabecera, como `.mapa` en `pack.html`. Tocar un paso lleva a lo suyo; con letra grande van uno
/// abajo del otro.
struct PasosGuia: View {
    let pasos: [ReglasDolor.Paso]
    let alTocar: (ReglasDolor.Paso) -> Void
    @Environment(\.dynamicTypeSize) private var tamañoLetra
    @ScaledMetric(relativeTo: .subheadline) private var diametro: CGFloat = 32

    var body: some View {
        let apilado = tamañoLetra.isAccessibilitySize
        let capa = apilado ? AnyLayout(VStackLayout(alignment: .leading, spacing: Espacio.xs))
                           : AnyLayout(HStackLayout(alignment: .top, spacing: Espacio.xs))
        capa {
            ForEach(pasos) { p in
                Button { alTocar(p) } label: { etiqueta(p, apilado: apilado) }
                    .buttonStyle(.plain)
                    .accessibilityLabel(ReglasDolor.textoHablado(p, de: pasos.count))
                    .accessibilityIdentifier("guia-paso-\(p.id)")
            }
        }
        .padding(.top, Espacio.xs)
    }

    @ViewBuilder private func etiqueta(_ p: ReglasDolor.Paso, apilado: Bool) -> some View {
        let capa = apilado ? AnyLayout(HStackLayout(alignment: .center, spacing: Espacio.s))
                           : AnyLayout(VStackLayout(alignment: .center, spacing: 6))
        capa {
            circulo(p)
            Text(verbatim: p.titulo)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(apilado ? .leading : .center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: apilado ? .leading : .center)
        .contentShape(.rect)
    }

    @ViewBuilder private func circulo(_ p: ReglasDolor.Paso) -> some View {
        ZStack {
            if p.estado == .hecho {
                Circle().fill(Color.marca)
                Image(systemName: "checkmark").font(.subheadline.weight(.bold)).foregroundStyle(Color.sobreMarca)
            } else {
                Circle().strokeBorder(p.estado == .ahora ? Color.marca : Color.secondary.opacity(0.5), lineWidth: 2)
                Text(verbatim: "\(p.numero)").font(.subheadline.weight(.semibold))
                    .foregroundStyle(p.estado == .ahora ? Color.marcaTexto : Color.secondary)
            }
        }
        .frame(width: diametro, height: diametro)
    }
}
