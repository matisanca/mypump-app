import SwiftUI
import MyPumpModelos

/// Fotos de la semana: frente, perfil y espalda (REV-02). Cada lugar es un marco vertical que invita a sacar la
/// foto; cuando está, lleva el tilde. Desde cámara o galería.
struct FotosSemana: View {
    let fotos: [FotoProgreso]
    @State private var pose: Pose?
    @Environment(\.dynamicTypeSize) private var tamañoLetra

    struct Pose: Identifiable, Hashable {
        let clave: String
        let nombre: String
        var id: String { clave }
    }

    private let poses = [Pose(clave: "frente", nombre: "Frente"), Pose(clave: "perfil", nombre: "Perfil"),
                         Pose(clave: "espalda", nombre: "Espalda")]

    /// Las de esta semana (el lunes de la semana, como `semana_lunes`).
    private var deEstaSemana: Set<String> {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2
        guard let lunes = cal.dateInterval(of: .weekOfYear, for: .now)?.start else { return [] }
        let f = DateFormatter()
        f.calendar = cal
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        let clave = f.string(from: lunes)
        return Set(fotos.filter { $0.semanaLunes == clave }.map(\.pose))
    }

    private var semanas: Int { Set(fotos.map(\.semanaLunes)).count }

    var body: some View {
        let hechas = deEstaSemana
        VStack(alignment: .leading, spacing: Espacio.s) {
            EncabezadoSeccion(titulo: "Fotos de la semana", detalle: hechas.count == 3 ? "Completas" : "\(hechas.count)/3")
            VStack(alignment: .leading, spacing: Espacio.m) {
                Label {
                    Text("Mismo lugar, misma luz, en ayunas. Las ve \(Text("solo Mati").bold()): no se publican ni salen de la app.")
                } icon: {
                    Image(systemName: "lock.fill").foregroundStyle(Color.marcaTexto)
                }
                .labelStyle(EtiquetaCompacta())
                .font(.footnote)
                .foregroundStyle(.secondary)

                // Con letra de accesibilidad, los tres marcos pasan a ser filas (no entran las palabras).
                let disposicion = tamañoLetra.isAccessibilitySize
                    ? AnyLayout(VStackLayout(spacing: Espacio.xs))
                    : AnyLayout(HStackLayout(spacing: Espacio.s))
                disposicion {
                    ForEach(poses) { p in
                        Button { pose = p } label: {
                            MarcoPose(nombre: p.nombre, lista: hechas.contains(p.clave), enFila: tamañoLetra.isAccessibilitySize)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Foto de \(p.nombre.lowercased())\(hechas.contains(p.clave) ? ", lista" : "")")
                    }
                }

                if semanas == 0 {
                    Text("Con la primera foto arranca tu historial. Mismo lugar y misma luz cada semana: así la comparación muestra tu cambio y no el del ambiente.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Button("Ver mis fotos · \(semanas) semana\(semanas == 1 ? "" : "s")") {}
                        .buttonStyle(BotonSecundario(compacto: true, tono: .marcaTexto))
                    if semanas < 4 {
                        Text("El comparador antes/después se abre en \(4 - semanas) semana\(4 - semanas > 1 ? "s" : "") más.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .tarjeta()
        }
        .confirmationDialog(pose.map { "Foto de \($0.nombre.lowercased())" } ?? "", isPresented: Binding(
            get: { pose != nil }, set: { if !$0 { pose = nil } }), titleVisibility: .visible) {
            Button("Sacar foto") {}
            Button("Elegir de la galería") {}
            Button("Cancelar", role: .cancel) {}
        }
    }
}

/// Marco vertical punteado con la cámara; con la foto lista, el tilde de marca. `enFila`: la versión horizontal
/// para letra de accesibilidad.
private struct MarcoPose: View {
    let nombre: String
    let lista: Bool
    var enFila = false

    var body: some View {
        let forma = RoundedRectangle(cornerRadius: Radio.control + 4, style: .continuous)
        Group {
            if enFila {
                HStack(spacing: Espacio.s) {
                    icono
                    VStack(alignment: .leading, spacing: 0) {
                        Text(nombre).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                        Text(lista ? "Lista" : "Agregar").font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(Espacio.s)
            } else {
                VStack(spacing: Espacio.xs) {
                    icono
                    Text(nombre).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                        .lineLimit(1).minimumScaleFactor(0.75)
                    Text(lista ? "Lista" : "Agregar").font(.caption2).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .aspectRatio(3 / 4, contentMode: .fit)
            }
        }
        .background(Color.campo.opacity(0.5), in: forma)
        .overlay {
            forma.strokeBorder(lista ? Color.marcaVivo.opacity(0.6) : Color.secondary.opacity(0.35),
                               style: StrokeStyle(lineWidth: 1.5, dash: lista ? [] : [6, 5]))
        }
        .contentShape(forma)
    }

    private var icono: some View {
        Image(systemName: lista ? "checkmark" : "camera.fill")
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(lista ? Color.sobreMarca : Color.marcaTexto)
            .frame(width: 42, height: 42)
            .background(lista ? Color.marca : Color.marcaSuave, in: .circle)
    }
}
