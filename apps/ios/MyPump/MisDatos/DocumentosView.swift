import SwiftUI
import MyPumpModelos
import MyPumpReglas
import MyPumpDatos

/// Documentos (contrato y consentimiento), desde Mis datos. La app no firma: cada documento muestra su estado y, al
/// tocarlo, se pide el enlace personal al servicio de firma y se abre en Safari (no en una hoja dentro de la app), donde
/// se lee, se firma o se baja el PDF. Regla del iPhone: acá no hay nada de pagos ni precios, solo el estado y abrir.
struct DocumentosView: View {
    let modelo: ModeloDocumentos
    @Environment(\.openURL) private var abrirURL
    /// El documento cuyo enlace se está pidiendo (su botón muestra la ruedita y los demás esperan).
    @State private var abriendo: String?
    @State private var error = false

    var body: some View {
        Form {
            Section {
                ForEach(modelo.documentos) { d in
                    FilaDocumento(documento: d, abriendo: abriendo == d.id, ocupado: abriendo != nil) {
                        Task { await abrir(d) }
                    }
                }
            } footer: {
                Text(TextosDocumentos.pie)
            }
        }
        .margenesDeLectura()
        .navigationTitle(TextosDocumentos.titulo)
        .navigationBarTitleDisplayMode(.inline)
        .tint(Color.marcaTexto)
        .refreshable { await modelo.cargar() }
        .task { await modelo.cargar() }
        .alert(TextosDocumentos.errorAbrir, isPresented: $error) {
            Button("Entendido", role: .cancel) {}
        }
    }

    private func abrir(_ d: DocumentoFirma) async {
        guard abriendo == nil else { return }
        abriendo = d.id
        defer { abriendo = nil }
        guard let url = await modelo.enlace(de: d) else {
            error = true
            return
        }
        // `openURL` con un https abre el navegador del sistema (el enlace es de firma.mypumpteam.com: no es un universal
        // link de la app, así que no vuelve a entrar acá).
        abrirURL(url) { aceptado in
            if !aceptado { error = true }
        }
    }
}

private struct FilaDocumento: View {
    let documento: DocumentoFirma
    let abriendo: Bool
    let ocupado: Bool
    let tocar: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Espacio.s) {
            HStack(alignment: .top, spacing: Espacio.m) {
                IconoAzulejo(documento.tipo.esContrato ? "doc.text.fill" : "cross.case.fill",
                             color: documento.estado == .pendiente ? .alerta : .marcaTexto)
                VStack(alignment: .leading, spacing: 2) {
                    Text(TextosDocumentos.nombre(documento.tipo)).font(.body.weight(.semibold))
                    Text(TextosDocumentos.estado(documento))
                        .font(.subheadline)
                        .foregroundStyle(documento.estado == .pendiente ? Color.alerta : .secondary)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            Button(action: tocar) {
                HStack(spacing: Espacio.s) {
                    if abriendo { ProgressView().controlSize(.small) }
                    Text(TextosDocumentos.boton(documento.estado))
                    Image(systemName: "arrow.up.right.square").font(.footnote.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(documento.estado == .pendiente ? Color.marca : Color.marcaTexto)
            .disabled(ocupado)
            .accessibilityHint("Se abre en Safari")
            .accessibilityIdentifier("documento-\(documento.id)")
        }
        .padding(.vertical, Espacio.xs)
    }
}

/// «Tenés el contrato pendiente de firma», arriba de Entreno: un renglón discreto que lleva a Documentos. No bloquea
/// nada. Solo con un contrato de coaching pendiente (el consentimiento solo no lo prende); en la demo y sin cuenta no hay.
struct AvisoContratoPendiente: View {
    @State private var modelo = Proveedor.modelo
    @Environment(Navegacion.self) private var navegacion: Navegacion?

    var body: some View {
        if !modelo.conMuestras, let docs = modelo.documentos, docs.contratoPendiente {
            Button {
                withAnimation(.snappy) { navegacion?.irADocumentos() }
            } label: {
                HStack(spacing: Espacio.s) {
                    Image(systemName: "signature")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.alerta)
                        .frame(width: 32, height: 32)
                        .background(Color.alerta.opacity(0.14), in: .circle)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(TextosDocumentos.avisoContrato).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                        Text(TextosDocumentos.avisoContratoDetalle).font(.caption).foregroundStyle(.secondary)
                    }
                    .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.tertiary)
                }
                .padding(Espacio.s)
                .frame(maxWidth: .infinity, alignment: .leading)
                .superficieTarjeta(radio: Radio.control + 6)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Abre Documentos")
            .accessibilityIdentifier("aviso-contrato")
        }
    }
}
