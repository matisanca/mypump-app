import SwiftUI
import MyPumpModelos
import MyPumpReglas
import MyPumpDatos

/// "Comidas libres fuera del plan" al pie de Dieta: lo que el cliente comió además del plan, con foto del plato (la IA
/// estima y se corrige) o a mano. Mati las ve en su panel. En la demo no aparece (como en la web).
struct ComidasLibresSeccion: View {
    let modelo: ModeloApp
    @Binding var analizando: Bool

    @State private var formulario: Formulario?
    @State private var errorFoto: String?
    @State private var fechaFoto: String?

    enum Formulario: Identifiable {
        case manual(String)
        case estimada(EstimacionPlato, String)
        var id: String {
            switch self {
            case .manual(let f): "manual-\(f)"
            case .estimada(let e, let f): "estimada-\(e.descripcion ?? "")-\(e.kcal ?? 0)-\(f)"
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "takeoutbag.and.cup.and.straw.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.marcaTexto)
                    .frame(width: 38, height: 38)
                    .background(Color.marcaSuave, in: .rect(cornerRadius: 11, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Comidas libres").font(.title3.weight(.semibold))
                    Text("Lo que comiste fuera del plan").font(.footnote).foregroundStyle(.secondary)
                }
            }

            if !modelo.libresVista.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(modelo.libresVista.enumerated()), id: \.element.id) { i, c in
                        fila(c)
                        if i < modelo.libresVista.count - 1 { Divider() }
                    }
                }
            }

            HStack(spacing: 10) {
                BotonFoto(maxPx: 1280, alElegir: analizar) {
                    Label("Con foto", systemImage: "camera.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .foregroundStyle(Color.sobreMarca)
                        .background(Color.marca, in: .rect(cornerRadius: 12, style: .continuous))
                }
                Button { formulario = .manual(modelo.fechaVista) } label: {
                    Label("A mano", systemImage: "square.and.pencil")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .foregroundStyle(.primary)
                        .background(Color(uiColor: .tertiarySystemFill), in: .rect(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .disabled(!modelo.vistaAdmiteLibres)
            // En la fila de botones y no en la tarjeta, que ya tiene la hoja del formulario: una `.sheet` por vista.
        }
        .tarjeta()
        .animation(.snappy, value: modelo.libresVista.map(\.id))
        .sheet(item: $formulario) { f in
            switch f {
            case .manual(let fecha): ComidaLibreView(modelo: modelo, estimacion: nil, fecha: fecha)
            case .estimada(let e, let fecha): ComidaLibreView(modelo: modelo, estimacion: e, fecha: fecha)
            }
        }
        .alert("No pudimos leer la foto", isPresented: Binding(get: { errorFoto != nil }, set: { if !$0 { errorFoto = nil } })) {
            Button("Cargar a mano") { formulario = .manual(fechaFoto ?? modelo.fechaVista) }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("\(errorFoto ?? ""). Podés cargarla a mano.")
        }
    }

    private func fila(_ c: ComidaLibre) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(c.descripcion ?? "").font(.body.weight(.medium))
                    if let h = c.hora, !h.isEmpty { Text(String(h.prefix(5))).font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
                }
                HStack(spacing: 6) {
                    Text("\((c.kcal ?? 0).jsEntero) kcal").font(.subheadline).foregroundStyle(.secondary)
                    Text("estimado").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color(uiColor: .tertiarySystemFill), in: .capsule)
                }
                FormatoDieta.macros(prot: (c.prot ?? 0).rounded(), carb: (c.carb ?? 0).rounded(), fat: (c.fat ?? 0).rounded())
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button(role: .destructive) {
                Task { await modelo.borrarComidaLibre(c.id) }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 30)
                    .background(Color(uiColor: .tertiarySystemFill), in: .circle)
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Borrar \(c.descripcion ?? "comida")")
        }
        .padding(.vertical, 8)
        .transition(.opacity.combined(with: .move(edge: .leading)))
    }

    private func analizar(_ jpeg: Data) {
        analizando = true
        // El día en que sacó la foto, aunque cambie de día mientras la IA mira.
        let fecha = modelo.fechaVista
        fechaFoto = fecha
        Task {
            let r = await modelo.analizarFoto(jpeg, tipo: .plato)
            analizando = false
            switch r {
            case .success(let data):
                if let e = try? JSONDecoder().decode(EstimacionPlato.self, from: JSONEncoder().encode(data)) {
                    formulario = .estimada(e, fecha)
                } else {
                    errorFoto = "respuesta inesperada"
                }
            case .failure(let e):
                errorFoto = e.clase == .red ? "sin conexión" : e.mensaje
            }
        }
    }
}
