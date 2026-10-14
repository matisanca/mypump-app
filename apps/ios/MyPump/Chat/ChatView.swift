import SwiftUI
import MyPumpModelos

/// Chat con Mati: burbujas agrupadas por autor (con cola en la última del grupo y la hora debajo), separadores
/// Hoy / Ayer / fecha, y el compositor flotando en vidrio como en Mensajes.
struct ChatView: View {
    let datos: Muestras
    @State private var texto = ""
    @FocusState private var escribiendo: Bool
    @State private var enviados = 0

    private let limite = 1000

    var body: some View {
        NavigationStack {
            contenido
                .background(Color.fondo)
                .navigationTitle("Mati")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        HStack(spacing: Espacio.xs) {
                            AvatarMati(lado: 30)
                            VStack(alignment: .leading, spacing: 0) {
                                Text("Mati").font(.headline)
                                Text("Tu coach").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
        }
    }

    @ViewBuilder private var contenido: some View {
        switch DemoUI.estado {
        case .cargando:
            ScrollView { EsqueletoChat().padding(.horizontal, Espacio.m).anchoLectura() }.scrollDisabled(true)
        case .error:
            ContentUnavailableView {
                Label("Sin conexión", systemImage: "wifi.slash")
            } description: {
                Text("No pudimos traer los mensajes. Lo que escribas se manda solo cuando vuelva la señal.")
            } actions: {
                Button("Reintentar") {}.buttonStyle(BotonMarca(compacto: true))
            }
        case .vacio:
            conversacion([])
        case nil:
            conversacion(datos.chat)
        }
    }

    private func conversacion(_ mensajes: [MensajeChat]) -> some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                encabezado(vacio: mensajes.isEmpty)
                ForEach(Array(mensajes.enumerated()), id: \.element.id) { i, m in
                    let dia = String(m.createdAt.prefix(10))
                    let nuevoDia = i == 0 || String(mensajes[i - 1].createdAt.prefix(10)) != dia
                    let previo = i > 0 && !nuevoDia ? mensajes[i - 1] : nil
                    let siguiente = i + 1 < mensajes.count ? mensajes[i + 1] : nil
                    if nuevoDia {
                        Text(separador(dia))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.top, Espacio.l)
                            .padding(.bottom, Espacio.xs)
                            .accessibilityAddTraits(.isHeader)
                    }
                    let iniciaGrupo = previo?.autor != m.autor
                    let cierraGrupo = siguiente?.autor != m.autor
                        || String(siguiente?.createdAt.prefix(10) ?? "") != dia
                    Burbuja(mensaje: m, conCola: cierraGrupo, hora: cierraGrupo ? hora(m.createdAt) : nil)
                        .padding(.top, iniciaGrupo ? Espacio.s : 2)
                }
            }
            .padding(.horizontal, Espacio.m)
            .padding(.bottom, Espacio.s)
            .anchoLectura()
        }
        .defaultScrollAnchor(.bottom)
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom, spacing: 0) { compositor }
    }

    /// El comienzo de la conversación. Con mensajes, una línea discreta (el avatar ya está en la barra, como en
    /// Mensajes); sin mensajes, el avatar grande y para qué sirve el chat.
    @ViewBuilder
    private func encabezado(vacio: Bool) -> some View {
        if vacio {
            VStack(spacing: Espacio.xs) {
                AvatarMati(lado: 72)
                Text("Mati").font(.title2.weight(.bold)).padding(.top, 4)
                Text("Escribile a Mati cuando quieras. Te responde acá.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, Espacio.xxl)
            .padding(.bottom, Espacio.l)
        } else {
            Text("Escribile a Mati cuando quieras. Te responde acá.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.top, Espacio.m)
                .padding(.bottom, Espacio.xs)
        }
    }

    private var compositor: some View {
        HStack(alignment: .bottom, spacing: Espacio.xs) {
            HStack(alignment: .bottom) {
                TextField("Mensaje", text: $texto, axis: .vertical)
                    .lineLimit(1...5)
                    .focused($escribiendo)
                    .onChange(of: texto) { _, nuevo in
                        if nuevo.count > limite { texto = String(nuevo.prefix(limite)) }
                    }
                if texto.count > limite - 100 {
                    Text("\(texto.count)/\(limite)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(texto.count >= limite ? Color.peligro : Color.secondary)
                        .padding(.bottom, 2)
                }
            }
            .padding(.horizontal, Espacio.m)
            .padding(.vertical, 11)
            .frame(minHeight: 44)
            .vidrio(RoundedRectangle(cornerRadius: 22, style: .continuous), interactivo: true)

            Button {
                texto = ""
                enviados += 1
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(vacio ? Color.secondary : Color.sobreMarca)
                    .frame(width: 44, height: 44)
                    .background {
                        if vacio { Circle().fill(.clear) } else { Circle().fill(Color.marca) }
                    }
                    .vidrio(Circle(), interactivo: true)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .disabled(vacio)
            .animation(.snappy(duration: 0.2), value: vacio)
            .sensoryFeedback(.impact(weight: .light), trigger: enviados)
            .accessibilityLabel("Enviar")
        }
        .padding(.horizontal, Espacio.m)
        .padding(.top, Espacio.xs)
        .padding(.bottom, Espacio.xs)
        .anchoLectura()
    }

    private var vacio: Bool { texto.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// Hoy / Ayer / "lun 12 oct", como la web.
    private func separador(_ dia: String) -> String {
        guard let f = Fechas.dia(dia) else { return dia }
        if Calendar.current.isDateInToday(f) { return "Hoy" }
        if Calendar.current.isDateInYesterday(f) { return "Ayer" }
        let s = f.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "es_AR")))
        return s.prefix(1).uppercased() + s.dropFirst()
    }

    /// "18:52" en la hora del teléfono, en 24 h como la web (`es-AR`).
    private func hora(_ iso: String) -> String? {
        guard let fecha = ISO8601DateFormatter().date(from: iso) else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        return f.string(from: fecha)
    }
}

/// El avatar de Mati: la inicial sobre el lima de la marca.
struct AvatarMati: View {
    var lado: CGFloat

    var body: some View {
        Text("M")
            .font(Archivo.fuente(lado * 0.46, peso: 800, relativoA: .body))
            .foregroundStyle(Color.sobreMarca)
            .frame(width: lado, height: lado)
            .background(Color.marca.gradient, in: .circle)
            .overlay { Circle().strokeBorder(Color.borde, lineWidth: 1) }
            .accessibilityHidden(true)
    }
}

struct Burbuja: View {
    let mensaje: MensajeChat
    var conCola = true
    var hora: String?

    var body: some View {
        let mio = !mensaje.esDelCoach
        VStack(alignment: mio ? .trailing : .leading, spacing: 3) {
            Text(mensaje.contenido)
                .font(.body)
                .foregroundStyle(mio ? Color.sobreMarca : Color.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background {
                    FormaBurbuja(mia: mio, conCola: conCola)
                        .fill(mio ? Color.marca : Color.tarjeta)
                        .overlay {
                            if !mio { FormaBurbuja(mia: mio, conCola: conCola).stroke(Color.borde, lineWidth: 1) }
                        }
                }
                .textSelection(.enabled)
            if let hora {
                Text(hora).font(.caption2.monospacedDigit()).foregroundStyle(.tertiary).padding(.horizontal, 6)
            }
        }
        .frame(maxWidth: .infinity, alignment: mio ? .trailing : .leading)
        .padding(mio ? .leading : .trailing, 56)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(mio ? "Vos" : "Mati"): \(mensaje.contenido)")
    }
}

/// Burbuja con esquinas continuas y, en la última del grupo, la colita del lado de quien habla.
struct FormaBurbuja: Shape {
    let mia: Bool
    let conCola: Bool

    func path(in r: CGRect) -> Path {
        let radio: CGFloat = min(18, r.height / 2)
        var p = Path(roundedRect: r, cornerRadius: radio, style: .continuous)
        guard conCola else { return p }
        // La cola: una gota chica que sale de la esquina de abajo del lado de quien habla.
        var cola = Path()
        if mia {
            cola.move(to: CGPoint(x: r.maxX - 12, y: r.maxY - 12))
            cola.addQuadCurve(to: CGPoint(x: r.maxX + 5, y: r.maxY), control: CGPoint(x: r.maxX - 4, y: r.maxY - 1))
            cola.addQuadCurve(to: CGPoint(x: r.maxX - 18, y: r.maxY - 1), control: CGPoint(x: r.maxX - 8, y: r.maxY + 1))
        } else {
            cola.move(to: CGPoint(x: r.minX + 12, y: r.maxY - 12))
            cola.addQuadCurve(to: CGPoint(x: r.minX - 5, y: r.maxY), control: CGPoint(x: r.minX + 4, y: r.maxY - 1))
            cola.addQuadCurve(to: CGPoint(x: r.minX + 18, y: r.maxY - 1), control: CGPoint(x: r.minX + 8, y: r.maxY + 1))
        }
        cola.closeSubpath()
        p = p.union(cola)
        return p
    }
}

private struct EsqueletoChat: View {
    var body: some View {
        VStack(spacing: Espacio.s) {
            Circle().fill(Color.campo).frame(width: 64, height: 64).padding(.top, Espacio.l)
            Text("Escribile a Mati cuando quieras.").font(.subheadline)
            ForEach(0..<5, id: \.self) { i in
                Text(i % 2 == 0 ? "Un mensaje de ejemplo bastante largo" : "Una respuesta corta")
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(Color.campo, in: .rect(cornerRadius: 18, style: .continuous))
                    .frame(maxWidth: .infinity, alignment: i % 2 == 0 ? .leading : .trailing)
            }
        }
        .esqueleto()
    }
}
