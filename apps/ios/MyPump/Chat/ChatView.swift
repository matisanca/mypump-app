import SwiftUI
import MyPumpModelos
import MyPumpReglas
import MyPumpDatos

/// Chat con Mati (CHA-01…05): burbujas agrupadas por autor (con cola en la última del grupo y la hora debajo),
/// separadores Hoy / Ayer / fecha, "Ver mensajes anteriores" de a 30, "enviando…" y "no salió → Reintentar", y el
/// compositor flotando en vidrio como en Mensajes. Con una cuenta sale de `ModeloChat`; en la demo y en los bocetos,
/// la conversación de muestra (sin enviar nada).
struct ChatView: View {
    let datos: Muestras
    @State private var modelo = Proveedor.modelo
    /// Lo que se está escribiendo vive acá y no en el modelo: sobrevive a que llegue un mensaje (CHA-02).
    @State private var texto = ""
    @FocusState private var escribiendo: Bool
    @State private var enviados = 0
    /// D7: el primer mensaje espera la respuesta del permiso para la IA (con un "no" sale igual: lo contesta Mati).
    @State private var pedidoIA: PedidoIA?

    private let limite = 1000

    /// El chat real, o nil en la demo y en los bocetos.
    private var chat: ModeloChat? { modelo.conMuestras ? nil : modelo.chat }

    private var burbujas: [BurbujaChat] {
        if let chat { return chat.hilo.mensajes }
        if DemoUI.estado == .vacio { return [] }
        // La demo, como la web: el hilo vacío para escribirle a Mati. La conversación tipo es solo de los bocetos.
        return datos.paraPantalla().chat.map {
            BurbujaChat(id: $0.id, autor: $0.autor, contenido: $0.contenido, leidoPorCliente: true, createdAt: $0.createdAt)
        }
    }

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
        // Con el chat a la vista el sondeo va cada 15 s y lo nuevo queda leído (CHA-04).
        .onAppear {
            chat?.abierto = true
            Task { await chat?.marcarLeido() }
        }
        .onDisappear { chat?.abierto = false }
        .permisoIA($pedidoIA, modelo: modelo)
    }

    @ViewBuilder private var contenido: some View {
        if DemoUI.estado == .cargando || (chat?.cargando == true && burbujas.isEmpty) {
            ScrollView { EsqueletoChat().padding(.horizontal, Espacio.m).anchoLectura() }.scrollDisabled(true)
        } else if DemoUI.estado == .error {
            ContentUnavailableView {
                Label("Sin conexión", systemImage: "wifi.slash")
            } description: {
                Text("No pudimos traer los mensajes. Lo que escribas se manda solo cuando vuelva la señal.")
            } actions: {
                Button("Reintentar") {}.buttonStyle(BotonMarca(compacto: true))
            }
        } else {
            conversacion(burbujas)
        }
    }

    private func conversacion(_ mensajes: [BurbujaChat]) -> some View {
        ScrollViewReader { lector in
            ScrollView {
                LazyVStack(spacing: 0) {
                    encabezado(vacio: mensajes.isEmpty)
                    if let chat, chat.hilo.hayMas, !mensajes.isEmpty {
                        Button {
                            Task { await chat.cargar(masViejos: true) }
                        } label: {
                            Text(chat.cargando ? "Cargando…" : "Ver mensajes anteriores")
                        }
                        .buttonStyle(BotonSecundario(compacto: true, tono: .marcaTexto))
                        .disabled(chat.cargando)
                        .padding(.bottom, Espacio.xs)
                    }
                    ForEach(Array(mensajes.enumerated()), id: \.element.id) { i, m in
                        let dia = FechaLocal.de(m.createdAt)
                        let nuevoDia = i == 0 || FechaLocal.de(mensajes[i - 1].createdAt) != dia
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
                        let cierraGrupo = siguiente?.autor != m.autor || FechaLocal.de(siguiente?.createdAt ?? "") != dia
                        Burbuja(mensaje: m, conCola: cierraGrupo, hora: cierraGrupo ? hora(m.createdAt) : nil) {
                            Task { await chat?.reintentar(m.id) }
                        }
                        .padding(.top, iniciaGrupo ? Espacio.s : 2)
                        .id(m.id)
                        .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity))
                    }
                }
                .padding(.horizontal, Espacio.m)
                .padding(.bottom, Espacio.s)
                .anchoLectura()
                .animation(.snappy, value: mensajes.map(\.id))
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom, spacing: 0) { compositor }
            // Lo nuevo (de Mati o lo que se acaba de mandar) se ve sin buscarlo.
            .onChange(of: mensajes.last?.id) { _, ultimo in
                guard let ultimo else { return }
                withAnimation(.snappy) { lector.scrollTo(ultimo, anchor: .bottom) }
            }
        }
    }

    /// El comienzo de la conversación. Con mensajes, una línea discreta (el avatar ya está en la barra, como en
    /// Mensajes); sin mensajes, el avatar grande y para qué sirve el chat.
    @ViewBuilder
    private func encabezado(vacio: Bool) -> some View {
        if vacio {
            VStack(spacing: Espacio.xs) {
                AvatarMati(lado: 72)
                Text("Escribile a Mati").font(.title2.weight(.bold)).padding(.top, 4)
                Text("Contale cómo venís, qué te costó esta semana o lo que necesites. Te contesta acá mismo.")
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
        VStack(spacing: 6) {
            if modelo.esDemo {
                Label("En la demo los mensajes no se envían.", systemImage: "sparkles")
                    .labelStyle(EtiquetaCompacta())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(alignment: .bottom, spacing: Espacio.xs) {
                HStack(alignment: .bottom) {
                    TextField("Escribile a Mati…", text: $texto, axis: .vertical)
                        .lineLimit(1...5)
                        .focused($escribiendo)
                        .onChange(of: texto) { _, nuevo in
                            if nuevo.count > limite { texto = String(nuevo.prefix(limite)) }
                        }
                        .accessibilityIdentifier("chat-campo")
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

                Button(action: enviar) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(puedeEnviar ? Color.sobreMarca : Color.secondary)
                        .frame(width: 44, height: 44)
                        .background {
                            if puedeEnviar { Circle().fill(Color.marca) } else { Circle().fill(.clear) }
                        }
                        .vidrio(Circle(), interactivo: true)
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .disabled(!puedeEnviar)
                .animation(.snappy(duration: 0.2), value: puedeEnviar)
                .sensoryFeedback(.impact(weight: .light), trigger: enviados)
                .accessibilityLabel("Enviar")
                .accessibilityIdentifier("chat-enviar")
            }
        }
        .padding(.horizontal, Espacio.m)
        .padding(.top, Espacio.xs)
        .padding(.bottom, Espacio.xs)
        .anchoLectura()
    }

    private var puedeEnviar: Bool {
        chat != nil && !texto.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// La burbuja aparece ya ("enviando…") y el mensaje sale por la cola (CHA-03).
    private func enviar() {
        guard chat != nil, puedeEnviar else { return }
        if modelo.faltaConsentimientoIA {
            pedidoIA = PedidoIA { _ in mandar() }
            return
        }
        mandar()
    }

    private func mandar() {
        guard let chat, puedeEnviar else { return }
        let mensaje = texto
        texto = ""
        enviados += 1
        Task { await chat.enviar(mensaje) }
    }

    /// Hoy / Ayer / "Lunes 12 de octubre", con el día local.
    private func separador(_ dia: String) -> String {
        guard let f = Fechas.dia(dia) else { return dia }
        if Calendar.current.isDateInToday(f) { return "Hoy" }
        if Calendar.current.isDateInYesterday(f) { return "Ayer" }
        let s = f.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "es_AR")))
        return s.prefix(1).uppercased() + s.dropFirst()
    }

    /// "18:52" en la hora del teléfono, en 24 h como la web (`es-AR`).
    private func hora(_ iso: String) -> String? {
        guard let fecha = FechaISO.fecha(iso) else { return nil }
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

/// Una burbuja. Las del cliente que todavía no salieron se ven más tenues con "enviando…"; las que la cola abandonó,
/// con "no salió" y Reintentar (el texto nunca se pierde).
struct Burbuja: View {
    let mensaje: BurbujaChat
    var conCola = true
    var hora: String?
    var reintentar: () -> Void = {}

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
                .opacity(mensaje.pendiente && !mensaje.fallo ? 0.6 : 1)
                .textSelection(.enabled)
            estado
        }
        .frame(maxWidth: .infinity, alignment: mio ? .trailing : .leading)
        .padding(mio ? .leading : .trailing, 56)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(mio ? "Vos" : "Mati"): \(mensaje.contenido)")
        .accessibilityValue(mensaje.fallo ? "No salió" : (mensaje.pendiente ? "Enviando" : ""))
    }

    @ViewBuilder private var estado: some View {
        if mensaje.fallo {
            HStack(spacing: 6) {
                Label("no salió", systemImage: "exclamationmark.circle.fill")
                    .labelStyle(EtiquetaCompacta())
                    .foregroundStyle(Color.peligro)
                Button("Reintentar", action: reintentar)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.marcaTexto)
                    .frame(minHeight: 32)
                    .accessibilityIdentifier("chat-reintentar")
            }
            .font(.caption)
            .padding(.horizontal, 6)
        } else if mensaje.pendiente {
            Label("enviando…", systemImage: "clock")
                .labelStyle(EtiquetaCompacta())
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 6)
        } else if let hora {
            Text(hora).font(.caption2.monospacedDigit()).foregroundStyle(.tertiary).padding(.horizontal, 6)
        }
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
