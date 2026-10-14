import SwiftUI
import MyPumpModelos

struct ChatView: View {
    let datos: Muestras
    @State private var texto = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 6) {
                    Text("Escribile a Mati cuando quieras. Te responde acá.")
                        .font(.footnote).foregroundStyle(.secondary).padding(.vertical, 12)
                    ForEach(Array(datos.chat.enumerated()), id: \.element.id) { i, m in
                        let dia = String(m.createdAt.prefix(10))
                        if i == 0 || String(datos.chat[i - 1].createdAt.prefix(10)) != dia {
                            Text(separador(dia)).font(.caption.weight(.semibold)).foregroundStyle(.secondary).padding(.top, 10)
                        }
                        Burbuja(mensaje: m)
                    }
                }
                .padding(.horizontal)
            }
            .defaultScrollAnchor(.bottom)
            .background(Color.fondo)
            .navigationTitle("Mati")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) { entrada }
        }
    }

    /// Hoy / Ayer / "lun 12 oct", como la web.
    private func separador(_ dia: String) -> String {
        guard let f = Fechas.dia(dia) else { return dia }
        if Calendar.current.isDateInToday(f) { return "Hoy" }
        if Calendar.current.isDateInYesterday(f) { return "Ayer" }
        return f.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(Locale(identifier: "es_AR")))
    }

    private var entrada: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Mensaje", text: $texto, axis: .vertical)
                .lineLimit(1...5)
                .padding(.horizontal, 14).padding(.vertical, 9)
                .background(Color.tarjeta, in: .rect(cornerRadius: 20, style: .continuous))
            Button {} label: {
                Image(systemName: "arrow.up.circle.fill").font(.system(size: 32)).foregroundStyle(texto.isEmpty ? Color.secondary : Color.marcaTexto)
            }
            .disabled(texto.isEmpty)
            .accessibilityLabel("Enviar")
        }
        .padding(.horizontal).padding(.vertical, 8)
        .background(.bar)
    }
}

struct Burbuja: View {
    let mensaje: MensajeChat

    var body: some View {
        HStack {
            if !mensaje.esDelCoach { Spacer(minLength: 48) }
            Text(mensaje.contenido)
                .font(.body)
                .padding(.horizontal, 14).padding(.vertical, 9)
                .foregroundStyle(mensaje.esDelCoach ? Color.primary : Color.sobreMarca)
                .background(mensaje.esDelCoach ? Color.tarjeta : Color.marca, in: .rect(cornerRadius: 18, style: .continuous))
            if mensaje.esDelCoach { Spacer(minLength: 48) }
        }
    }
}
