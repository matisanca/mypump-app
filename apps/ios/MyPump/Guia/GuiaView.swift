import SwiftUI
import MyPumpModelos
import MyPumpReglas
import MyPumpDatos

/// «Tu guía»: los videos de Mati antes de la videollamada, con la misma línea que la web (`pack.html`): la cabecera con
/// el avance, el reproductor, «Tu app», las dudas para la videollamada, los demás bloques como capítulos plegables y la
/// suplementación. En iPad, dos columnas: el reproductor fijo y la lista al lado. Se abre desde la tarjeta de Entreno.
///
/// `entregas_app_get` se llama solo acá, al abrir (marca que el cliente abrió su guía, como la web).
struct GuiaView: View {
    let modelo: ModeloGuia
    @State private var control = ControlReproductor()
    @State private var abiertos: Set<String> = []
    @State private var motivosAbiertos: Set<String> = []
    @State private var volverA: String?
    @Environment(\.horizontalSizeClass) private var clase
    @Environment(\.dismiss) private var cerrar
    @Environment(\.scenePhase) private var fase
    @Environment(\.dynamicTypeSize) private var tamañoLetra

    private var clips: [ClipGuia] { modelo.clips }
    private var despues: Bool { ReglasGuia.yaPaso(modelo.guia?.fechaEntrega) }

    var body: some View {
        Group {
            switch modelo.estado {
            case .lista where modelo.guia != nil:
                contenido
            case .cargando, .lista:
                ProgressView().controlSize(.large).frame(maxWidth: .infinity, maxHeight: .infinity)
            case .sinRed:
                ContentUnavailableView {
                    Label("No pudimos traer tu guía", systemImage: "wifi.slash")
                } description: {
                    Text("Se cortó la conexión. Probá de nuevo cuando tengas señal.")
                } actions: {
                    Button("Reintentar") { Task { await modelo.abrir() } }
                        .buttonStyle(BotonSecundario(compacto: true, tono: .marcaTexto))
                }
            case .oculta:
                Color.clear
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.fondo)
        .navigationTitle("Tu guía")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            control.clips = { [modelo] in modelo.clips }
            control.alGuardar = { [modelo] id, g in Task { await modelo.avance(video: id, segundos: g.segundos, visto: g.visto) } }
            control.forzarSinRed = GuiaUI.sinRed
            if modelo.guia != nil { prepararInicial() }
            // Capturas (DEBUG): `-guiaMotivo <id>` abre el «para qué» de una fila y `-guiaPlaca YES` deja la placa fija.
            if let m = GuiaUI.motivoAbierto { motivosAbiertos.insert(m) }
            if GuiaUI.placa { control.placaFija = true; control.siguiente() }
            await modelo.abrir()
            prepararInicial()
        }
        // La guía dejó de existir (token revocado o la página se dio de baja): la sección desaparece, sin mensaje.
        .onChange(of: modelo.estado) { _, e in if e == .oculta { control.pausar(); cerrar() } }
        .onChange(of: fase) { _, f in if f != .active { control.pausar() } }
        .onDisappear { control.pausar() }
        .sensoryFeedback(.selection, trigger: control.cambios)
    }

    private func prepararInicial() {
        control.prepararInicial()
        if let c = control.clipActual { abiertos.insert(bloqueDe(c)) }
    }

    private func bloqueDe(_ c: ClipGuia) -> String {
        (c.bloque?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? "Videos"
    }

    // MARK: - Disposición

    @ViewBuilder private var contenido: some View {
        ScrollViewReader { lector in
            Group {
                if clase == .regular {
                    // iPad: el reproductor fijo a la izquierda; la lista, a la derecha, se mueve sola.
                    HStack(alignment: .top, spacing: Espacio.l) {
                        ScrollView {
                            reproductor(lector).padding(.vertical, Espacio.m)
                        }
                        .frame(maxWidth: .infinity)
                        .scrollDismissesKeyboard(.interactively)
                        ScrollView {
                            VStack(spacing: Espacio.m) { lista(lector) }.padding(.vertical, Espacio.m)
                        }
                        .frame(maxWidth: 520)
                        .scrollDismissesKeyboard(.interactively)
                    }
                    .padding(.horizontal, Espacio.l)
                } else {
                    ScrollView {
                        VStack(spacing: Espacio.m) {
                            cabecera
                            reproductor(lector).id("reproductor")
                            listaSinCabecera(lector)
                        }
                        .padding(.horizontal, Espacio.m)
                        .padding(.vertical, Espacio.m)
                        .anchoLectura()
                    }
                    .scrollDismissesKeyboard(.interactively)
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if modelo.desdeCache { BannerGuiaSinConexion() }
            }
            .task {
                // Capturas (DEBUG): `-guiaAncla dudas-llamada|suplementacion|<id de clip>`.
                guard let a = GuiaUI.ancla else { return }
                try? await Task.sleep(for: .milliseconds(700))
                lector.scrollTo(a, anchor: .top)
            }
            .onChange(of: control.cambios) { _, _ in
                // El bloque del video que suena queda abierto.
                if let c = control.clipActual { withAnimation(.snappy) { _ = abiertos.insert(bloqueDe(c)) } }
            }
        }
    }

    @ViewBuilder private func lista(_ lector: ScrollViewProxy) -> some View {
        cabecera
        listaSinCabecera(lector)
    }

    @ViewBuilder private func listaSinCabecera(_ lector: ScrollViewProxy) -> some View {
        let bloques = ReglasGuia.bloques(clips)
        ForEach(bloques.filter(\.esApp)) { b in bloque(b, lector) }
        DudasLlamada(modelo: modelo, despues: despues)
        ForEach(bloques.filter { !$0.esApp }) { b in bloque(b, lector) }
        if let s = VistaSuplementacion(modelo.guia?.suplementacion) {
            Suplementacion(vista: s, puedeVer: { id in clips.contains { $0.id == id && $0.url != nil } }) { id in
                control.reproducir(video: id)
                irAlReproductor(lector, desde: nil)
            }
        }
        Text(despues ? "Si algún video no te carga o tenés algo para contarme, escribime por el chat."
                     : "Si algún video no te carga o tenés algo para contarme antes de la llamada, escribime por el chat.")
            .font(.subheadline).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .tarjeta()
    }

    private func irAlReproductor(_ lector: ScrollViewProxy, desde fila: String?) {
        guard clase != .regular else { return }
        withAnimation(.snappy) { lector.scrollTo("reproductor", anchor: .top) }
        volverA = fila
    }

    // MARK: - Cabecera

    private var cabecera: some View {
        let g = modelo.guia
        let a = ReglasGuia.avance(clips)
        let cuando = ReglasGuia.fechaLlamada(g?.fechaEntrega)
        return VStack(alignment: .leading, spacing: Espacio.xs) {
            Text("Hola \(g?.nombrePila ?? "")")
                .font(.title2.weight(.bold))
                .accessibilityAddTraits(.isHeader)
            Text(despues ? "Te dejo estos videos según lo que hablamos en la videollamada. Miralos con calma, te van a servir para arrancar bien."
                         : "Armé estos videos para vos\(cuando.map { ", antes de nuestra videollamada del \($0)" } ?? ""), según lo que me contaste. Si llegás a ver el primer bloque, en la llamada vamos directo a lo tuyo.")
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
            Text("Mati").font(.subheadline).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 6) {
                Text(ReglasGuia.textoAvance(a)).font(.subheadline).foregroundStyle(.secondary)
                ProgressView(value: a.fraccion).tint(Color.marca)
                    .accessibilityHidden(true)
            }
            .padding(.top, Espacio.xs)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("guia-avance")
        }
        .tarjeta(relleno: 20)
        .overlay(alignment: .top) {
            UnevenRoundedRectangle(topLeadingRadius: Radio.tarjeta, topTrailingRadius: Radio.tarjeta, style: .continuous)
                .fill(Color.marca).frame(height: 6).accessibilityHidden(true)
        }
    }

    // MARK: - Reproductor

    private func reproductor(_ lector: ScrollViewProxy) -> some View {
        let c = control.clipActual
        let total = clips.count
        return VStack(alignment: .leading, spacing: 0) {
            CuadroVideo(control: control, total: total)
            VStack(alignment: .leading, spacing: Espacio.xs) {
                if let c, let i = control.actual {
                    Text(ReglasGuia.textoNumero(i, de: total, bloque: c.bloque))
                        .font(.caption.weight(.semibold)).tracking(0.6).textCase(.uppercase)
                        .foregroundStyle(Color.marcaTexto)
                    Text(c.titulo).font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("guia-titulo-actual")
                }
                botones(lector)
            }
            .padding(Espacio.m)
            .background(Color.marcaSuave)
            if let c {
                VStack(alignment: .leading, spacing: Espacio.s) {
                    MotivoTexto(motivo: c.motivo)
                    DudaVideo(modelo: modelo, clip: c, despues: despues)
                }
                .padding(Espacio.m)
            }
        }
        .superficieTarjeta(radio: Radio.control + 6)
        .clipShape(RoundedRectangle(cornerRadius: Radio.control + 6, style: .continuous))
    }

    private func botones(_ lector: ScrollViewProxy) -> some View {
        FilaFluida(espaciado: Espacio.xs, interlineado: Espacio.xs) {
            if control.hayAnterior {
                Button { control.anterior() } label: { Label("Anterior", systemImage: "backward.fill") }
                    .accessibilityIdentifier("guia-anterior")
            }
            if control.haySiguiente {
                Button { control.siguiente() } label: { Label("Siguiente", systemImage: "forward.fill") }
                    .accessibilityIdentifier("guia-siguiente")
            }
            Button { control.cambiarVelocidad() } label: { Label("Velocidad \(ReglasGuia.textoVelocidad(control.velocidad))", systemImage: "gauge.with.dots.needle.67percent") }
                .accessibilityLabel("Velocidad \(ReglasGuia.textoVelocidad(control.velocidad))")
                .accessibilityHint("Cambia entre 1x, 1,25x y 1,5x")
                .accessibilityIdentifier("guia-velocidad")
            if let v = volverA, clase != .regular {
                Button {
                    withAnimation(.snappy) { lector.scrollTo(v, anchor: .center) }
                    volverA = nil
                } label: { Label("Volver a la lista", systemImage: "list.bullet") }
            }
        }
        .buttonStyle(BotonGuia())
        .padding(.top, 4)
    }

    // MARK: - Bloques

    private func bloque(_ b: ReglasGuia.Bloque, _ lector: ScrollViewProxy) -> some View {
        let abierto = abiertos.contains(b.titulo)
        let vistos = b.indices.filter { clips.indices.contains($0) && clips[$0].visto }.count
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.snappy) { if abierto { abiertos.remove(b.titulo) } else { abiertos.insert(b.titulo) } }
            } label: {
                HStack(alignment: .center, spacing: Espacio.s) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(b.titulo).font(.headline).foregroundStyle(.primary)
                        Text(ReglasGuia.textoBloque(b) + (vistos > 0 ? ", \(vistos == b.indices.count ? "todos vistos" : "\(vistos) \(vistos == 1 ? "visto" : "vistos")")" : ""))
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                        .rotationEffect(.degrees(abierto ? 180 : 0))
                }
                .padding(.horizontal, 20).padding(.vertical, Espacio.s + 2)
                .frame(minHeight: 56)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isHeader)
            .accessibilityValue(abierto ? "Abierto" : "Cerrado")
            .accessibilityHint(abierto ? "Pliega el capítulo" : "Muestra los videos")
            .accessibilityIdentifier("guia-bloque-\(b.titulo)")
            if abierto {
                // Los índices son de `clips` en este mismo pase; si la guía cambió en el medio, lo que sobra no se pinta.
                ForEach(b.indices.filter { clips.indices.contains($0) }, id: \.self) { i in fila(i, lector) }
                    .padding(.bottom, 2)
            }
        }
        .padding(.bottom, abierto ? 6 : 0)
        .superficieTarjeta(radio: Radio.control + 6)
        .clipShape(RoundedRectangle(cornerRadius: Radio.control + 6, style: .continuous))
    }

    private func fila(_ i: Int, _ lector: ScrollViewProxy) -> some View {
        let c = clips[i]
        let actual = control.actual == i
        let (hacer, paraQue) = ReglasGuia.partes(c.motivo)
        let tieneMotivo = !hacer.isEmpty || !paraQue.isEmpty
        let motivoAbierto = motivosAbiertos.contains(c.id)
        // Con letra de accesibilidad, la duración va abajo del título y la flechita en su propio renglón: al lado dejaban
        // al título en una columna de tres letras.
        let apilado = tamañoLetra.isAccessibilitySize
        let duracion = Text(c.url == nil ? "Lo estoy subiendo" : ReglasGuia.duracion(minutos: c.minutos))
            .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
        let botonMotivo = Button {
            withAnimation(.snappy) { if motivoAbierto { motivosAbiertos.remove(c.id) } else { motivosAbiertos.insert(c.id) } }
        } label: {
            HStack(spacing: 6) {
                if apilado { Text("Para qué sirve").font(.subheadline.weight(.semibold)).foregroundStyle(Color.marcaTexto) }
                Image(systemName: "chevron.down")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(motivoAbierto ? 180 : 0))
            }
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Para qué sirve")
        .accessibilityValue(motivoAbierto ? "Abierto" : "Cerrado")
        .accessibilityIdentifier("guia-motivo-\(c.id)")

        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 0) {
                Button {
                    control.reproducir(i)
                    irAlReproductor(lector, desde: c.id)
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: Espacio.s) {
                        IconoClip(visto: c.visto, actual: actual, sonando: actual && control.reproduciendo)
                            .alignmentGuide(.firstTextBaseline) { d in d[VerticalAlignment.center] + 5 }
                        if apilado {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(c.titulo).font(.body).foregroundStyle(.primary)
                                duracion
                            }
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        } else {
                            Text(c.titulo)
                                .font(.body)
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: Espacio.xs)
                            duracion
                        }
                    }
                    .padding(.leading, apilado ? Espacio.m : 20).padding(.trailing, tieneMotivo && !apilado ? 4 : Espacio.m)
                    .padding(.vertical, Espacio.s)
                    .frame(minHeight: 48)
                    .contentShape(.rect)
                }
                .buttonStyle(FilaPresionable())
                .disabled(c.url == nil)
                .opacity(c.url == nil ? 0.5 : 1)
                .accessibilityLabel(c.titulo)
                .accessibilityValue([c.visto ? "Visto" : "Sin ver", actual ? "Es el video actual" : nil,
                                     c.url == nil ? "Lo estoy subiendo" : ReglasGuia.duracionHablada(minutos: c.minutos)].compactMap { $0 }.joined(separator: ", "))
                .accessibilityHint(c.url == nil ? "" : "Reproduce el video")
                .accessibilityIdentifier("guia-fila-\(c.id)")
                if tieneMotivo && !apilado { botonMotivo.padding(.trailing, 8) }
            }
            if tieneMotivo && apilado { botonMotivo.padding(.leading, Espacio.m) }
            if motivoAbierto {
                MotivoTexto(motivo: c.motivo)
                    .padding(.leading, apilado ? Espacio.m : 20 + 22 + Espacio.s).padding(.trailing, apilado ? Espacio.m : 20).padding(.bottom, Espacio.s)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(actual ? Color.marcaSuave : .clear)
        .id(c.id)
    }
}

// MARK: - Piezas

/// El círculo de la fila: vacío sin ver, verde con la tilde visto, con el play en el que suena.
private struct IconoClip: View {
    let visto: Bool
    let actual: Bool
    let sonando: Bool
    @ScaledMetric(relativeTo: .body) private var lado: CGFloat = 22

    var body: some View {
        ZStack {
            if visto {
                Circle().fill(Color.marca)
                Image(systemName: "checkmark").font(.system(size: lado * 0.5, weight: .bold)).foregroundStyle(Color.sobreMarca)
            } else {
                Circle().strokeBorder(actual ? Color.marca : Color.secondary, lineWidth: 2)
                if actual {
                    Image(systemName: sonando ? "speaker.wave.2.fill" : "play.fill")
                        .font(.system(size: lado * 0.42, weight: .bold)).foregroundStyle(Color.marcaTexto)
                }
            }
        }
        .frame(width: lado, height: lado)
        .accessibilityHidden(true)
    }
}

/// «Qué hacer» y «Para qué» (`motivo`, con «indicación ||| motivo»).
private struct MotivoTexto: View {
    let motivo: String?

    var body: some View {
        let (hacer, paraQue) = ReglasGuia.partes(motivo)
        VStack(alignment: .leading, spacing: 4) {
            if !paraQue.isEmpty {
                Text("\(Text("Para qué.").fontWeight(.semibold).foregroundStyle(Color.marcaTexto)) \(paraQue)")
            }
            if !hacer.isEmpty {
                Text("\(Text("Qué hacer.").fontWeight(.semibold).foregroundStyle(Color.marcaTexto)) \(hacer)")
                    .foregroundStyle(.primary)
            }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Los botones chicos del reproductor: texto verde sobre el fondo, de 44 pt de alto.
private struct BotonGuia: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .labelStyle(.titleOnly)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.marcaTexto)
            .padding(.horizontal, Espacio.s)
            .frame(minHeight: 44)
            .background(Color.tarjeta.opacity(configuration.isPressed ? 0.6 : 1), in: .capsule)
            .contentShape(.capsule)
    }
}

/// Un recuadro de texto con contador (hasta 1000), del mismo estilo en la duda del video y la de la llamada.
struct CampoDuda: View {
    @Binding var texto: String
    let placeholder: String
    let identificador: String
    @FocusState private var foco: Bool

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            TextField(placeholder, text: $texto, axis: .vertical)
                .lineLimit(2...6)
                .focused($foco)
                .padding(.horizontal, Espacio.s).padding(.vertical, 10)
                .background(Color.campo, in: RoundedRectangle(cornerRadius: Radio.control, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Radio.control, style: .continuous)
                        .strokeBorder(foco ? Color.marca : .clear, lineWidth: 1.5)
                }
                .accessibilityIdentifier(identificador)
            if texto.count > 800 {
                Text(texto.count > ReglasGuia.maxTexto ? "Te pasaste: \(texto.count.formatted()) de 1.000 caracteres" : "\(texto.count.formatted()) de 1.000 caracteres")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(texto.count > ReglasGuia.maxTexto ? Color.peligro : .secondary)
            }
        }
    }
}

/// La duda del video que suena: lo ya dejado arriba, lo que está saliendo y el campo.
private struct DudaVideo: View {
    @Bindable var modelo: ModeloGuia
    let clip: ClipGuia
    let despues: Bool

    var body: some View {
        let ya = ReglasGuia.renglones(clip.duda)
        let enCola = modelo.pendientes.filter { $0.video == clip.id }
        let borrador = Binding(get: { modelo.borradores[clip.id] ?? "" }, set: { modelo.borradores[clip.id] = $0 })
        VStack(alignment: .leading, spacing: Espacio.xs) {
            Divider().padding(.bottom, 4)
            Text("¿Te quedó alguna duda de este video?").font(.subheadline.weight(.semibold))
            if !ya.isEmpty || !enCola.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    if !ya.isEmpty {
                        Text("Ya me dejaste").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        ForEach(Array(ya.enumerated()), id: \.offset) { _, d in Text(d).font(.subheadline) }
                    }
                    ForEach(enCola) { p in
                        Label(p.texto, systemImage: "clock").font(.subheadline).foregroundStyle(.secondary)
                            .accessibilityLabel("Enviando: \(p.texto)")
                    }
                }
                .padding(Espacio.s)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.campo, in: RoundedRectangle(cornerRadius: Radio.miniatura, style: .continuous))
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("guia-dudas-video")
            }
            CampoDuda(texto: borrador, placeholder: despues ? "Escribila acá y me llega" : "Escribila acá y me llega antes de la videollamada",
                      identificador: "guia-duda-campo")
            HStack {
                EstadoEnvio(envio: modelo.envios[clip.id], listo: despues ? "Listo, me llega y te contesto." : "Listo, me llega antes de la videollamada.",
                            enCola: !enCola.isEmpty)
                Spacer(minLength: Espacio.xs)
                Button("Enviar duda") { Task { await modelo.enviarDuda(video: clip.id) } }
                    .buttonStyle(BotonMarca(compacto: true))
                    .disabled(ReglasGuia.textoParaMandar(borrador.wrappedValue) == nil)
                    .accessibilityIdentifier("guia-duda-enviar")
            }
        }
    }
}

/// La línea de cómo quedó el último envío.
private struct EstadoEnvio: View {
    let envio: ModeloGuia.Envio?
    let listo: String
    let enCola: Bool

    var body: some View {
        Group {
            switch envio {
            case .noSeGuardo:
                Text("No se pudo guardar, probá de nuevo o escribime por el chat.").foregroundStyle(Color.peligro)
            case .listo where !enCola:
                Text(listo).foregroundStyle(.secondary)
            case .enviando, .listo:
                Text(enCola ? "Se envía sola apenas tengas señal." : listo).foregroundStyle(.secondary)
            case nil:
                EmptyView()
            }
        }
        .font(.footnote)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier("guia-envio")
    }
}

/// «¿Qué querés que hablemos en la videollamada?»: el mismo recuadro de la web, con la lista y el tope de 30.
private struct DudasLlamada: View {
    @Bindable var modelo: ModeloGuia
    let despues: Bool

    var body: some View {
        let ya = modelo.guia?.dudasLlamada.map(\.texto) ?? []
        let enCola = modelo.pendientes.filter { $0.video == nil }
        let borrador = Binding(get: { modelo.borradores[""] ?? "" }, set: { modelo.borradores[""] = $0 })
        VStack(alignment: .leading, spacing: Espacio.xs) {
            Text(despues ? "¿Te quedó algo para preguntarme?" : "¿Qué querés que hablemos en la videollamada?")
                .font(.headline).accessibilityAddTraits(.isHeader)
            Text(despues ? "Recorré tu plan con calma y si te surge alguna duda, anotala acá y te contesto."
                         : "Recorré tu plan con calma y anotá acá todas las dudas que te surjan, así las vemos en la videollamada.")
                .font(.subheadline.weight(.semibold))
                .padding(Espacio.s)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.marcaSuave, in: RoundedRectangle(cornerRadius: Radio.miniatura, style: .continuous))
            Text(despues ? "Me llega y te contesto. Podés dejar varias." : "Me llega antes de la videollamada. Podés dejar varias.")
                .font(.footnote).foregroundStyle(.secondary)
            if !ya.isEmpty || !enCola.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    if !ya.isEmpty {
                        Text(ya.count == 1 ? "Ya me dejaste esta" : "Ya me dejaste estas \(ya.count)")
                            .font(.caption.weight(.semibold)).tracking(0.5).textCase(.uppercase)
                            .foregroundStyle(Color.marcaTexto).padding(.bottom, 4)
                    }
                    ForEach(Array(ya.enumerated()), id: \.offset) { _, d in
                        Divider()
                        Text(d).font(.subheadline).padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    ForEach(enCola) { p in
                        Divider()
                        Label(p.texto, systemImage: "clock").font(.subheadline).foregroundStyle(.secondary).padding(.vertical, 8)
                            .accessibilityLabel("Enviando: \(p.texto)")
                    }
                }
                .accessibilityIdentifier("guia-dudas-llamada")
            }
            if modelo.puedeSumarDudaLlamada {
                CampoDuda(texto: borrador, placeholder: despues ? "Tu pregunta" : "Por ejemplo, algo que no entendiste del plan o que querés cambiar",
                          identificador: "guia-llamada-campo")
                HStack {
                    EstadoEnvio(envio: modelo.envios[""], listo: despues ? "Listo, me llega y te contesto." : "Listo, la vemos en la videollamada.",
                                enCola: !enCola.isEmpty)
                    Spacer(minLength: Espacio.xs)
                    Button("Enviar") { Task { await modelo.enviarDudaLlamada() } }
                        .buttonStyle(BotonMarca(compacto: true))
                        .disabled(ReglasGuia.textoParaMandar(borrador.wrappedValue) == nil)
                        .accessibilityIdentifier("guia-llamada-enviar")
                }
            } else {
                Text("Ya dejaste 30, que es el máximo. Si te queda algo, escribime por el chat.")
                    .font(.footnote).foregroundStyle(.secondary)
                    .accessibilityIdentifier("guia-llamada-tope")
            }
        }
        .padding(.vertical, Espacio.m).padding(.trailing, 20).padding(.leading, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .superficieTarjeta(radio: Radio.control + 6)
        .overlay(alignment: .leading) {
            UnevenRoundedRectangle(topLeadingRadius: Radio.control + 6, bottomLeadingRadius: Radio.control + 6, style: .continuous)
                .fill(Color.marca).frame(width: 6).accessibilityHidden(true)
        }
        .id("dudas-llamada")
    }
}

/// «Tu suplementación», al final y por momento del día, como «Tu día» del PDF.
private struct Suplementacion: View {
    let vista: VistaSuplementacion
    let puedeVer: (String) -> Bool
    let verPorQue: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Espacio.s) {
            Text(vista.titulo).font(.headline).accessibilityAddTraits(.isHeader)
            if let a = vista.accion { Text(a).font(.subheadline) }
            ForEach(vista.momentos) { m in
                VStack(alignment: .leading, spacing: Espacio.xs) {
                    Divider()
                    Text(m.titulo).font(.subheadline.weight(.semibold)).foregroundStyle(Color.marcaTexto)
                        .accessibilityAddTraits(.isHeader)
                    ForEach(m.filas) { f in fila(f) }
                }
            }
            if let s = vista.sigue {
                Divider()
                Text("\(Text("Sigue igual.").fontWeight(.semibold)) \(s)").font(.subheadline)
            }
            if !vista.sale.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(Text("Dejás de tomar.").fontWeight(.semibold)) \(vista.sale.map(\.nombre).joined(separator: ", "))").font(.subheadline)
                    ForEach(Array(vista.sale.enumerated()), id: \.offset) { _, s in
                        if let p = s.porQue { Text("\(s.nombre): \(p)").font(.footnote).foregroundStyle(.secondary) }
                        ForEach(Array(s.detalle.enumerated()), id: \.offset) { _, d in ConNegritas(texto: d).font(.footnote).foregroundStyle(.secondary) }
                    }
                }
            }
        }
        .tarjeta(relleno: 20)
        .accessibilityIdentifier("guia-suplementacion")
        .id("suplementacion")
    }

    private func fila(_ f: VistaSuplementacion.Fila) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: Espacio.xs) {
                (Text(f.nombre).fontWeight(.semibold)
                 + (f.nuevo ? Text("  nuevo").font(.caption.weight(.semibold)).foregroundColor(Color.marcaTexto) : Text(""))
                 + (f.opcional ? Text("  opcional").font(.caption).foregroundColor(.secondary) : Text("")))
                    .font(.body)
                Spacer(minLength: Espacio.xs)
                if let c = f.cantidad { Text(c).font(.body.weight(.semibold).monospacedDigit()).multilineTextAlignment(.trailing) }
            }
            if let n = f.nota { Text(n).font(.subheadline).foregroundStyle(.secondary) }
            if let p = f.porQue {
                Text("\(Text("Por qué.").fontWeight(.semibold).foregroundStyle(Color.marcaTexto)) \(p)").font(.subheadline)
            }
            ForEach(Array(f.detalle.enumerated()), id: \.offset) { _, d in
                ConNegritas(texto: d).font(.subheadline).foregroundStyle(.secondary)
                    .padding(.leading, 10)
                    .overlay(alignment: .leading) { Rectangle().fill(Color.borde).frame(width: 2) }
            }
            if let v = f.videoId, puedeVer(v) {
                Button { verPorQue(v) } label: { Label("Ver por qué", systemImage: "play.circle.fill") }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.marcaTexto)
                    .frame(minHeight: 44)
                    .accessibilityHint("Reproduce el video de \(f.nombre)")
                    .accessibilityIdentifier("guia-ver-por-que-\(v)")
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
    }
}

/// `*negrita*` del PDF.
private struct ConNegritas: View {
    let texto: String
    var body: some View {
        ReglasGuia.negritas(texto).reduce(Text("")) { acc, t in acc + (t.negrita ? Text(t.texto).fontWeight(.semibold) : Text(t.texto)) }
    }
}

private struct BannerGuiaSinConexion: View {
    var body: some View {
        Label("Sin conexión: ves lo último que guardaste", systemImage: "wifi.slash")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Color.alerta)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(.bar)
            .accessibilityIdentifier("guia-sin-red")
    }
}

// MARK: - Tarjeta de inicio

/// La entrada en Entreno: aparece solo con `entregas_app_resumen` en `ok: true`, con el avance («4 de 13 videos, te
/// quedan 12 min»). Tocarla abre la guía.
struct TarjetaGuia: View {
    let modelo: ModeloGuia
    let abrir: () -> Void

    var body: some View {
        if let r = modelo.resumen, r.hayGuia {
            let a = ReglasGuia.Avance(total: r.total, vistos: r.vistos, minutosRestantes: r.minutosRestantes)
            Button(action: abrir) {
                HStack(spacing: Espacio.s) {
                    ZStack {
                        AnilloProgreso(fraccion: a.fraccion, grosor: 4, color: .marca)
                        Image(systemName: a.completo ? "checkmark" : "play.fill")
                            .font(.subheadline.weight(.bold)).foregroundStyle(Color.marcaTexto)
                    }
                    .frame(width: 44, height: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Tu guía").font(.headline).foregroundStyle(.primary)
                        Text(ReglasGuia.textoTarjeta(a)).font(.subheadline).foregroundStyle(.secondary)
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
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Tu guía, \(ReglasGuia.textoTarjeta(a))")
            .accessibilityHint("Abre los videos de Mati")
            .accessibilityIdentifier("guia-tarjeta")
        }
    }
}

/// De dónde sale el modelo de la guía: el de la cuenta, o en DEBUG la muestra (`-guiaMuestra YES`, para la maqueta y
/// las capturas sin token).
@MainActor
enum GuiaUI {
    static let destino = "guia:tu-guia"

    static var modelo: ModeloGuia? {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "guiaMuestra") { return muestra }
        #endif
        return Proveedor.modelo.guia
    }

    #if DEBUG
    private static let muestra = ModeloGuia(muestra: GuiaMuestra.guia)
    #endif

    /// `-sinRed YES` (DEBUG): el reproductor dice «Necesitás conexión» aunque el simulador tenga red.
    static var sinRed: Bool {
        #if DEBUG
        UserDefaults.standard.bool(forKey: "sinRed")
        #else
        false
        #endif
    }

    static var ancla: String? { valor("guiaAncla") }
    static var motivoAbierto: String? { valor("guiaMotivo") }
    static var placa: Bool { valor("guiaPlaca") == "YES" }

    private static func valor(_ k: String) -> String? {
        #if DEBUG
        UserDefaults.standard.string(forKey: k)
        #else
        nil
        #endif
    }

    /// `-abrir guia` (DEBUG): las capturas entran directo a la guía.
    static var abrirAlArrancar: Bool { DemoUI.abrir == "guia" }
}
