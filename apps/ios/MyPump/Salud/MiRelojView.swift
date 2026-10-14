import SwiftUI
import SafariServices
import MyPumpDatos

/// "Mi reloj" de Revisión (REV-08, cliente.html:8088-8239): Oura y WHOOP según lo que el servidor tenga habilitado (o
/// lo que el cliente ya tenía conectado). "Conectar" abre la autorización del proveedor en SFSafariViewController (el
/// token viaja en la query: nunca en un WebView propio) y pregunta `get_conexiones` cada 3 s durante 2 min, porque el
/// callback no vuelve a la app. "Quitar" pide confirmación. Sin relojes para ofrecer, no ocupa lugar.
struct MiRelojView: View {
    let modelo: ModeloSalud
    @State private var abierto: RelojAbierto?
    @State private var mensaje: String?
    @State private var aQuitar: ModeloSalud.Reloj?

    struct RelojAbierto: Identifiable { let id: String; let url: URL }

    var body: some View {
        let relojes = modelo.relojesVisibles
        Group {
            if !relojes.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    EncabezadoSalud(icono: "⌚️", titulo: "Mi reloj")
                    Text(modelo.textoRelojes).font(.footnote).foregroundStyle(.secondary)
                    ForEach(relojes) { r in
                        fila(r)
                        if r.id != relojes.last?.id { Divider() }
                    }
                    if let mensaje { NotaSalud(mensaje) }
                }
                .tarjeta()
            }
        }
        .task { if modelo.relojesDisponibles == nil { await modelo.cargarRelojes() } }
        .sheet(item: $abierto) { a in SafariSalud(url: a.url).ignoresSafeArea() }
        .confirmationDialog("¿Quitar \(aQuitar?.id ?? "")?", isPresented: Binding(get: { aQuitar != nil }, set: { if !$0 { aQuitar = nil } }),
                            titleVisibility: .visible, presenting: aQuitar) { r in
            Button("Quitar", role: .destructive) { Task { await modelo.quitar(r.id) } }
            Button("Cancelar", role: .cancel) {}
        } message: { _ in
            Text("Dejamos de traer tus datos. Los que ya están se quedan.")
        }
    }

    private func fila(_ r: ModeloSalud.Reloj) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(r.nombre).font(.subheadline.weight(.medium))
                    if r.conectado { Chip(texto: "conectado", tono: .exito) }
                    if r.enError { Chip(texto: "hay que reconectar", tono: .peligro) }
                }
                Text(r.ultimaSincronizacion.map { "Última sincronización: \($0)" } ?? r.descripcion)
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if r.conectado {
                Button("Quitar") { aQuitar = r }.buttonStyle(.bordered).controlSize(.small)
                    .accessibilityIdentifier("reloj-quitar-\(r.id)")
            } else {
                Button(modelo.esperandoReloj == r.id ? "Abriendo…" : "Conectar") { conectar(r) }
                    .buttonStyle(.bordered).controlSize(.small)
                    .disabled(modelo.esperandoReloj == r.id)
                    .accessibilityIdentifier("reloj-conectar-\(r.id)")
            }
        }
        .padding(.vertical, 4)
    }

    private func conectar(_ r: ModeloSalud.Reloj) {
        guard let url = modelo.urlConectar(r.id) else { return }
        mensaje = "Te va a abrir el sitio de \(r.id). Cuando termines, volvé acá — se conecta solo."
        abierto = RelojAbierto(id: r.id, url: url)
        Task {
            if await modelo.esperarConexion(r.id) {
                abierto = nil
                mensaje = "✅ Listo. Tus datos van a aparecer en un rato."
            } else if modelo.esperandoReloj == nil {
                mensaje = "No llegué a confirmarlo. Si lo autorizaste, va a aparecer solo en unos minutos."
            }
        }
    }
}

/// SFSafariViewController: comparte las cookies de Safari (el cliente ya puede estar logueado en Oura) y no le da a la
/// app acceso a lo que pasa adentro.
struct SafariSalud: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let c = SFSafariViewController(url: url)
        c.preferredControlTintColor = UIColor(Color.marcaTexto)
        c.dismissButtonStyle = .close
        return c
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
