import AVKit
import CoreTransferable
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import MyPumpModelos
import MyPumpReglas
import MyPumpDatos

private typealias T = TextosTecnica

private extension ModeloTecnica.Aviso {
    var texto: String {
        switch self {
        case .rechazo(let r): r.texto
        case .enCurso: T.enCurso
        case .topeSemanal: T.topeSemanal
        case .error: T.errorGenerico
        }
    }
}

private struct NotaTecnica: View {
    let texto: String
    var alerta = false
    var body: some View {
        Text(texto)
            .font(.footnote.weight(.medium))
            .foregroundStyle(alerta ? Color.alerta : Color.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .onAppear { if alerta { AccessibilityNotification.Announcement(texto).post() } }
    }
}

// MARK: Entradas

/// «Mandar mi técnica» en el detalle del ejercicio. Con la palanca apagada o sin el servidor nuevo, no existe.
struct BotonMandarTecnica: View {
    let ejercicio: Ejercicio
    @State private var app = Proveedor.modelo
    @State private var abierta = false

    var body: some View {
        // Si está abierta queda en pie aunque se apague: si no, la hoja se cierra antes de ver «Recibido».
        if let m = app.tecnica, m.habilitado || abierta {
            Button { abierta = true } label: { Label(T.entradaEjercicio, systemImage: "video.fill") }
                .buttonStyle(BotonSecundario())
                .accessibilityIdentifier("tecnica-mandar-ejercicio")
                .sheet(isPresented: $abierta) {
                    NavigationStack {
                        EnviarTecnica(modelo: m, slug: Tecnica.slug(ejercicio), nombre: ejercicio.nombre)
                            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(T.cerrar) { abierta = false } } }
                    }
                    .presentationDragIndicator(.visible)
                }
        }
    }
}

/// Lo que se apila arriba de «Mi técnica».
enum DestinoTecnica: Hashable {
    case devolucion(String), elegir, enviar(slug: String, nombre: String)
}

/// Qué bloques tiene «Mi gimnasio y mi técnica»: cada uno con su palanca de siempre (las mismas condiciones que tenían sus
/// renglones de Mis datos y el botón de casa de Entreno).
@MainActor
enum DondeEntrenoUI {
    /// «Tu gimnasio»: con la entrada habilitada, o con «Entreno en casa» para ofrecer.
    static func gimnasio(_ m: ModeloApp) -> ModeloGimnasio? {
        guard let g = m.gimnasio else { return nil }
        return g.entradaVisible || casa(m) != nil ? g : nil
    }
    /// «Entreno en casa» (palanca `casa`), habilitado para la cuenta y con el gimnasio activo.
    static func casa(_ m: ModeloApp) -> ModeloCasa? {
        guard m.palanca.casa, m.gimnasio?.estado != nil, let c = m.casa, c.visible else { return nil }
        return c
    }
    static func tecnica(_ m: ModeloApp) -> ModeloTecnica? { m.tecnica.flatMap { $0.habilitado ? $0 : nil } }
}

/// El renglón grande al final de Entreno (simplificar, 11/11): abre «Mi gimnasio y mi técnica». Con una respuesta de
/// técnica de los últimos 7 días, un botón que la abre directo (un toque). Sin ninguno de los dos, no existe.
struct EntradaDondeEntreno: View {
    @State private var app = Proveedor.modelo
    @State private var abierta = false
    @State private var devolucion: String?

    var body: some View {
        let g = DondeEntrenoUI.gimnasio(app) != nil, t = DondeEntrenoUI.tecnica(app)
        // Si está abierta queda en pie aunque se apague una palanca: si no, la hoja se cierra sola.
        if let titulo = DondeEntreno.titulo(gimnasio: g, tecnica: t != nil) ?? (abierta ? DondeEntreno.tituloAmbos : nil) {
            VStack(alignment: .leading, spacing: Espacio.s) {
                Button { devolucion = nil; abierta = true } label: {
                    HStack(spacing: Espacio.s) {
                        Image(systemName: "figure.strengthtraining.traditional")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Color.marcaTexto)
                            .frame(width: 44, height: 44)
                            .background(Color.marcaSuave, in: .circle)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(titulo).font(.headline).foregroundStyle(.primary)
                            if let b = DondeEntreno.bajada(gimnasio: g, tecnica: t != nil) {
                                Text(b).font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary).accessibilityHidden(true)
                    }
                    .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                    .contentShape(.rect)
                }
                .buttonStyle(FilaPresionable())
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("donde-entreno-entrada")
                if let r = t.flatMap({ DondeEntreno.respuestaReciente($0.envios) }) {
                    Button { devolucion = r.id; abierta = true } label: {
                        Label(DondeEntreno.verRespuesta, systemImage: "video.fill")
                    }
                    .buttonStyle(BotonMarca())
                    .accessibilityHint(r.nombre)
                    .accessibilityIdentifier("donde-entreno-respuesta")
                }
            }
            .tarjeta()
            .sheet(isPresented: $abierta) {
                DondeEntrenoRaiz(devolucion: devolucion, alCerrar: { abierta = false }).presentationDragIndicator(.visible)
            }
        }
    }
}

/// «Mi gimnasio y mi técnica» (simplificar, 11/11): Tu gimnasio (con el interruptor de «Entreno en casa» adentro, a dos
/// toques como antes) y Mi técnica (lo mandado, su estado y la respuesta de Mati), cada bloque solo con su palanca. Pila
/// propia con `path`: `navigationDestination(item:)` dejaba la app en un bucle al 100 % de CPU en iOS 17; por lo mismo acá no
/// hay `List`.
struct DondeEntrenoRaiz: View {
    let alCerrar: () -> Void
    @State private var camino: [DestinoTecnica]
    @State private var app = Proveedor.modelo
    @State private var verGimnasio = false
    @Environment(\.dynamicTypeSize) private var letra

    /// `devolucion`: la respuesta de técnica a abrir directo (el botón del renglón de Entreno).
    init(devolucion: String? = nil, alCerrar: @escaping () -> Void) {
        self.alCerrar = alCerrar
        _camino = State(initialValue: devolucion.map { [.devolucion($0)] } ?? [])
    }

    var body: some View {
        let g = DondeEntrenoUI.gimnasio(app), t = DondeEntrenoUI.tecnica(app)
        NavigationStack(path: $camino) {
            ScrollView {
                VStack(alignment: .leading, spacing: Espacio.xl) {
                    if g == nil && t == nil {
                        NotaTecnica(texto: DondeEntreno.vacio).accessibilityIdentifier("donde-entreno-vacio")
                    }
                    if let g {
                        VStack(alignment: .leading, spacing: Espacio.s) {
                            titulo(DondeEntreno.tituloGimnasio)
                            if let c = DondeEntrenoUI.casa(app) {
                                InterruptorCasa(casa: c, gimnasio: g, compacto: letra.isAccessibilitySize)
                            }
                            // Siempre, aunque la carga esté pedida (y también en la tarjeta de Entreno): prendida «casa», la
                            // lista para marcar vive en «Tu gimnasio», y tiene que quedar a un toque desde acá.
                            Button { verGimnasio = true } label: {
                                FilaEnvio(titulo: TextosGimnasio.tarjetaTitulo, detalle: TarjetaGimnasio.detalle(g, app: app), chevron: true)
                            }
                            .buttonStyle(FilaPresionable())
                            .accessibilityIdentifier("donde-entreno-gimnasio")
                        }
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("donde-entreno-bloque-gimnasio")
                    }
                    if let t {
                        VStack(alignment: .leading, spacing: Espacio.s) {
                            titulo(DondeEntreno.tituloTecnica)
                            ContenidoTecnica(modelo: t, abrir: { camino.append($0) })
                        }
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("donde-entreno-bloque-tecnica")
                    }
                }
                .padding(Espacio.m)
                .anchoLectura()
            }
            .background(Color.fondo)
            .navigationTitle(DondeEntreno.titulo(gimnasio: g != nil, tecnica: t != nil) ?? DondeEntreno.tituloAmbos)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(DondeEntreno.cerrar, action: alCerrar) } }
            .navigationDestination(for: DestinoTecnica.self) { d in
                if let t = DondeEntrenoUI.tecnica(app) { DestinoTecnicaVista(destino: d, modelo: t, camino: $camino) }
            }
        }
        .accessibilityIdentifier("donde-entreno")
        .task {
            async let a: Void = DondeEntrenoUI.tecnica(app)?.refrescar() ?? ()
            async let b: Void = app.gimnasio?.refrescar() ?? ()
            async let c: Void = app.palanca.casa ? (app.casa?.refrescar() ?? ()) : ()
            _ = await (a, b, c)
            DondeEntrenoUI.tecnica(app)?.drenarEnFondo()
        }
        .sheet(isPresented: $verGimnasio) {
            if let g = app.gimnasio { GimnasioRaiz(modelo: g, alCerrar: { verGimnasio = false }).presentationDragIndicator(.visible) }
        }
    }

    private func titulo(_ t: String) -> some View {
        Text(t).font(.title2.weight(.bold)).foregroundStyle(.primary)
            .accessibilityAddTraits(.isHeader)
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Cada pantalla que se apila arriba de la lista de técnica.
private struct DestinoTecnicaVista: View {
    let destino: DestinoTecnica
    let modelo: ModeloTecnica
    @Binding var camino: [DestinoTecnica]

    var body: some View {
        switch destino {
        case .devolucion(let id):
            if let e = modelo.envios.first(where: { $0.id == id }), let dev = e.devolucion { DevolucionTecnicaView(modelo: modelo, envio: e, devolucion: dev) }
        case .elegir: ElegirEjercicioTecnica(modelo: modelo, abrir: { camino.append($0) })
        case .enviar(let slug, let nombre): EnviarTecnica(modelo: modelo, slug: slug, nombre: nombre, alTerminar: { camino = [] })
        }
    }
}

private struct FilaEnvio: View {
    let titulo: String
    let detalle: String
    var alerta = false
    var chevron = false
    var body: some View {
        HStack(spacing: Espacio.s) {
            VStack(alignment: .leading, spacing: 2) {
                Text(titulo).font(.headline).foregroundStyle(.primary).multilineTextAlignment(.leading)
                Text(detalle).font(.subheadline).foregroundStyle(alerta ? Color.alerta : .secondary).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if chevron { Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary).accessibilityHidden(true) }
        }
        .tarjeta()
        .accessibilityElement(children: .combine)
    }
}

/// La lista de «Mi técnica» (lo mandado, su estado y la respuesta), sin desplazamiento propio: va dentro de «Mi gimnasio y mi
/// técnica».
struct ContenidoTecnica: View {
    let modelo: ModeloTecnica
    let abrir: (DestinoTecnica) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Espacio.m) {
            if let a = modelo.aviso { NotaTecnica(texto: a.texto, alerta: true).accessibilityIdentifier("tecnica-aviso-envio") }
            if modelo.puedeMandar {
                Button(T.entradaEjercicio) { modelo.limpiarAviso(); abrir(.elegir) }
                    .buttonStyle(BotonMarca())
                    .accessibilityIdentifier("tecnica-mandar")
            }
            if let p = modelo.pendiente {
                FilaEnvio(titulo: p.nombre, detalle: modelo.subiendo ? T.subiendo : T.esperandoSenal).accessibilityIdentifier("tecnica-fila-pendiente")
            }
            ForEach(modelo.envios) { e in
                switch e.estado {
                case .publicado:
                    Button { abrir(.devolucion(e.id)) } label: {
                        FilaEnvio(titulo: e.nombre, detalle: Gimnasio.fechaCorta(e.publicadoEn).map(T.revisadoEl) ?? (e.devolucion?.credito ?? ""), chevron: true)
                    }
                    .buttonStyle(FilaPresionable())
                    .accessibilityIdentifier("tecnica-fila-publicado")
                case .rechazado:
                    FilaEnvio(titulo: e.nombre, detalle: e.rechazoTexto ?? T.rechazoIlegible, alerta: true).accessibilityIdentifier("tecnica-fila-rechazado")
                default:
                    FilaEnvio(titulo: e.nombre, detalle: T.recibido).accessibilityIdentifier("tecnica-fila-enviado")
                    if e.tieneVideo { SacarVideoTecnica(modelo: modelo, envioId: e.id) }
                }
            }
            if modelo.envios.isEmpty && modelo.pendiente == nil {
                NotaTecnica(texto: T.sinEnvios).accessibilityIdentifier("tecnica-vacio")
            }
        }
    }
}

private struct ElegirEjercicioTecnica: View {
    let modelo: ModeloTecnica
    let abrir: (DestinoTecnica) -> Void
    @State private var app = Proveedor.modelo

    private var ejercicios: [Ejercicio] {
        Tecnica.ejerciciosParaElegir(app.rutina?.estructura.dias ?? [], efectivo: { app.entreno?.efectivo($0).ejercicio ?? $0 })
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Espacio.s) {
                if ejercicios.isEmpty { NotaTecnica(texto: T.sinEjercicios) }
                ForEach(Array(ejercicios.enumerated()), id: \.offset) { i, e in
                    Button { abrir(.enviar(slug: Tecnica.slug(e), nombre: e.nombre)) } label: {
                        HStack {
                            Text(e.nombre).foregroundStyle(.primary).multilineTextAlignment(.leading)
                            Spacer(minLength: Espacio.s)
                            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary).accessibilityHidden(true)
                        }
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(.rect)
                        .tarjeta(relleno: 12)
                    }
                    .buttonStyle(FilaPresionable())
                    .accessibilityIdentifier("tecnica-ejercicio-\(i)")
                }
            }
            .padding(Espacio.m)
            .anchoLectura()
        }
        .background(Color.fondo)
        .navigationTitle(T.elegirEjercicio)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: Enviar

/// El aviso (una sola vez), el consejo, el video, la nota y «Enviar a Mati». Lo que sigue lo cuenta la cola.
struct EnviarTecnica: View {
    let modelo: ModeloTecnica
    let slug: String
    let nombre: String
    var alTerminar: (() -> Void)?

    @State private var video: CompresorVideo.Listo?
    @State private var preparando = false
    @State private var error: String?
    @State private var nota = ""
    @State private var mandado = false
    @State private var barrido = false

    var body: some View {
        Group {
            if mandado && modelo.pendiente == nil && modelo.aviso == nil {
                recibido
            } else if modelo.pendiente != nil {
                enviando
            } else if !modelo.habilitado && !mandado {
                VStack { NotaTecnica(texto: T.errorGenerico) }.padding(Espacio.l).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !modelo.puedeMandar && !mandado {
                VStack { NotaTecnica(texto: T.enCurso).accessibilityIdentifier("tecnica-en-curso") }.padding(Espacio.l).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if modelo.necesitaAviso {
                aviso
            } else {
                formulario
            }
        }
        .background(Color.fondo)
        .navigationTitle(NombreEjercicio(nombre).principal)
        .navigationBarTitleDisplayMode(.inline)
        // Una sola vez y sin borrar al desaparecer: abrir la cámara a pantalla completa dispara estos dos y se llevaría el video elegido.
        // Lo que quede sin mandar lo barre la próxima entrada.
        .task {
            if !barrido { barrido = true; CompresorVideo.barrer() }
            await modelo.refrescar()
            modelo.drenarEnFondo()
        }
    }

    private var aviso: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Espacio.m) {
                Label { Text(T.avisoBreve).font(.subheadline).fixedSize(horizontal: false, vertical: true) } icon: {
                    Image(systemName: "lock.fill").foregroundStyle(Color.marcaTexto)
                }
                .labelStyle(EtiquetaCompacta())
                .padding(Espacio.s)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.marcaSuave, in: .rect(cornerRadius: Radio.control, style: .continuous))
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("tecnica-aviso")
                Button(T.avisoBoton) { modelo.marcarAvisoVisto() }.buttonStyle(BotonMarca()).accessibilityIdentifier("tecnica-aviso-ok")
            }
            .padding(Espacio.m)
            .anchoLectura()
        }
    }

    private var formulario: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Espacio.m) {
                Text(T.consejo).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("tecnica-consejo")
                if let a = modelo.aviso { NotaTecnica(texto: a.texto, alerta: true).accessibilityIdentifier("tecnica-aviso-envio") }
                if let error { NotaTecnica(texto: error, alerta: true).accessibilityIdentifier("tecnica-error") }
                if preparando {
                    HStack(spacing: Espacio.s) { ProgressView(); Text(T.preparando).font(.subheadline) }
                        .frame(maxWidth: .infinity, minHeight: 54)
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("tecnica-preparando")
                } else {
                    if let v = video {
                        Label(T.videoListo(Int(v.duracion.rounded())), systemImage: "checkmark.circle.fill")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(Color.marcaTexto).accessibilityIdentifier("tecnica-video-listo")
                    }
                    ElegirVideoTecnica(alElegir: preparar, alElegirDePrueba: { poner($0) }, alFallar: { error = T.errorVideo }) {
                        Label(video == nil ? T.agregarVideo : T.cambiarVideo, systemImage: "video.fill")
                            .frame(maxWidth: .infinity, minHeight: 54)
                            .font(.headline)
                            .foregroundStyle(video == nil ? Color.sobreMarca : Color.primary)
                            .background(video == nil ? Color.marca : Color.campo, in: .capsule)
                    }
                    .accessibilityIdentifier("tecnica-agregar-video")
                }
                TextField(T.notaPregunta, text: $nota, axis: .vertical)
                    .lineLimit(2...5)
                    .padding(Espacio.s)
                    .background(Color.campo, in: .rect(cornerRadius: Radio.control, style: .continuous))
                    .accessibilityIdentifier("tecnica-nota")
                Button(T.botonEnviar) { enviar() }
                    .buttonStyle(BotonMarca())
                    .disabled(video == nil || preparando)
                    .accessibilityIdentifier("tecnica-enviar")
            }
            .padding(Espacio.m)
            .anchoLectura()
        }
        .scrollDismissesKeyboard(.interactively)
        .onChange(of: nota) { _, n in if n.count > Tecnica.maxNota { nota = Tecnica.nota(n) } }
    }

    private var enviando: some View {
        VStack(spacing: Espacio.m) {
            ProgressView().controlSize(.large)
            Text(modelo.subiendo ? T.subiendo : T.esperandoSenal).font(.headline).multilineTextAlignment(.center).accessibilityIdentifier("tecnica-enviando")
            Text(T.enviandoSeguir).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            if !modelo.subiendo {
                Button(T.cancelarEnvio) {
                    // Antes de sacarlo de la cola: si no, se ve un instante «Recibido».
                    mandado = false
                    Task { if await !modelo.cancelarPendiente() { mandado = true } }
                }
                    .buttonStyle(BotonSecundario())
                    .accessibilityIdentifier("tecnica-cancelar")
            }
        }
        .padding(Espacio.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var recibido: some View {
        VStack(spacing: Espacio.m) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 48)).foregroundStyle(Color.marcaTexto).accessibilityHidden(true)
            Text(T.recibido).font(.headline).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("tecnica-recibido")
            if let alTerminar { Button(T.otroRecibido, action: alTerminar).buttonStyle(BotonSecundario()).accessibilityIdentifier("tecnica-listo") }
        }
        .padding(Espacio.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func preparar(_ entrada: URL) {
        error = nil
        modelo.limpiarAviso()
        preparando = true
        let topes = modelo.topes
        Task {
            let r = await CompresorVideo.preparar(entrada: entrada, topes: topes)
            try? FileManager.default.removeItem(at: entrada)
            preparando = false
            switch r {
            case .listo(let l): poner(l)
            case .rechazado(let rechazo): quitarVideo(); error = rechazo.texto
            }
        }
    }

    private func poner(_ l: CompresorVideo.Listo) {
        quitarVideo()
        video = l
        error = nil
    }

    private func quitarVideo() {
        if let v = video { try? FileManager.default.removeItem(at: v.archivo) }
        video = nil
    }

    private func enviar() {
        guard let v = video else { return }
        switch modelo.encolar(archivo: v.archivo, slug: slug, nombre: nombre, nota: nota) {
        case .guardado:
            video = nil
            mandado = true
            modelo.drenarEnFondo()
        case .ocupado: error = T.enCurso
        case .noSeGuardo: error = T.noSeGuardo
        }
    }
}

/// El selector del sistema: la cámara (`UIImagePickerController`) o la galería (`PhotosPicker`, sin permiso). En las pruebas, un
/// archivo armado acá (el simulador no tiene cámara).
private struct ElegirVideoTecnica<Etiqueta: View>: View {
    let alElegir: (URL) -> Void
    let alElegirDePrueba: (CompresorVideo.Listo) -> Void
    let alFallar: () -> Void
    @ViewBuilder let etiqueta: () -> Etiqueta

    @State private var camara = false
    @State private var galeria = false
    @State private var item: PhotosPickerItem?

    var body: some View {
        #if DEBUG
        if UserDefaults.standard.string(forKey: "tecnicaDePrueba") != nil {
            Button {
                let u = FileManager.default.temporaryDirectory.appendingPathComponent("tecnica-listo-prueba-\(UUID().uuidString).mp4")
                try? Data(repeating: 7, count: 2048).write(to: u)
                alElegirDePrueba(CompresorVideo.Listo(archivo: u, duracion: 32, bytes: 2048))
            } label: { etiqueta() }
            .buttonStyle(.plain)
        } else { real }
        #else
        real
        #endif
    }

    private var real: some View {
        Group {
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Menu {
                    Button { camara = true } label: { Label(T.grabarVideo, systemImage: "video") }
                    Button { galeria = true } label: { Label(T.elegirGaleria, systemImage: "photo.on.rectangle") }
                } label: { etiqueta() }
            } else {
                Button { galeria = true } label: { etiqueta() }.buttonStyle(.plain)
            }
        }
        .photosPicker(isPresented: $galeria, selection: $item, matching: .videos, preferredItemEncoding: .current)
        .fullScreenCover(isPresented: $camara) {
            CamaraVideo(alTerminar: { url in camara = false; if let url { alElegir(url) } }).ignoresSafeArea()
        }
        .onChange(of: item) { _, nuevo in
            guard let nuevo else { return }
            item = nil
            Task {
                do {
                    if let v = try await nuevo.loadTransferable(type: VideoElegido.self) { alElegir(v.archivo) } else { alFallar() }
                } catch { alFallar() }
            }
        }
    }
}

/// El video del carrete, copiado a un archivo propio: nunca pasa por memoria.
private struct VideoElegido: Transferable {
    let archivo: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { recibido in
            let destino = FileManager.default.temporaryDirectory.appendingPathComponent("tecnica-listo-original-\(UUID().uuidString).\(recibido.file.pathExtension)")
            try FileManager.default.copyItem(at: recibido.file, to: destino)
            return VideoElegido(archivo: destino)
        }
    }
}

private struct CamaraVideo: UIViewControllerRepresentable {
    let alTerminar: (URL?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let c = UIImagePickerController()
        c.sourceType = .camera
        c.mediaTypes = [UTType.movie.identifier]
        c.cameraCaptureMode = .video
        c.videoQuality = .typeHigh
        c.videoMaximumDuration = 75
        c.delegate = context.coordinator
        return c
    }

    func updateUIViewController(_ vc: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coord { Coord(alTerminar) }

    final class Coord: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let alTerminar: (URL?) -> Void
        init(_ a: @escaping (URL?) -> Void) { alTerminar = a }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            guard let u = info[.mediaURL] as? URL else { alTerminar(nil); return }
            // El sistema borra el suyo al volver de este método.
            let destino = FileManager.default.temporaryDirectory.appendingPathComponent("tecnica-listo-original-\(UUID().uuidString).\(u.pathExtension)")
            do { try FileManager.default.moveItem(at: u, to: destino); alTerminar(destino) } catch { alTerminar(nil) }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { alTerminar(nil) }
    }
}

// MARK: Devolución

private struct DevolucionTecnicaView: View {
    let modelo: ModeloTecnica
    let envio: EnvioTecnica
    let devolucion: DevolucionTecnica
    @State private var enVideo: MomentoVideo?

    private struct MomentoVideo: Identifiable { let s: Double; var id: Double { s } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Espacio.l) {
                VStack(alignment: .leading, spacing: Espacio.xxs) {
                    Text(T.tituloDevolucion(devolucion.ejercicio ?? envio.nombre)).font(.title2.bold()).accessibilityAddTraits(.isHeader).fixedSize(horizontal: false, vertical: true)
                    Text(Gimnasio.fechaCorta(envio.publicadoEn).map(T.revisadoEl) ?? devolucion.credito).font(.subheadline).foregroundStyle(.secondary).accessibilityIdentifier("tecnica-credito")
                }
                // Sin correcciones no quiere decir que esté bien si no se pudo ver o hace falta otro video.
                if devolucion.correcciones.isEmpty && devolucion.noEvaluable.isEmpty && devolucion.otroVideo == nil {
                    Text(T.sinCorrecciones).font(.headline).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("tecnica-sin-correcciones")
                }
                if !devolucion.bien.isEmpty {
                    seccion(T.loQueEstaBien) {
                        ForEach(devolucion.bien, id: \.self) { b in
                            Label { Text(b).fixedSize(horizontal: false, vertical: true) } icon: { Image(systemName: "checkmark").foregroundStyle(Color.marcaTexto) }
                                .labelStyle(EtiquetaCompacta())
                        }
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("tecnica-bien")
                }
                if !devolucion.correcciones.isEmpty {
                    seccion(T.paraCorregir) {
                        ForEach(devolucion.correcciones) { c in correccion(c) }
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("tecnica-correcciones")
                }
                if !devolucion.noEvaluable.isEmpty {
                    seccion(T.noSePudoVer) {
                        ForEach(devolucion.noEvaluable) { n in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(n.que).font(.subheadline.weight(.semibold))
                                Text(n.motivo).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
                if let como = devolucion.otroVideo, !como.isEmpty {
                    seccion(T.mandameOtro) { Text(como).fixedSize(horizontal: false, vertical: true) }
                        .accessibilityIdentifier("tecnica-otro-video")
                }
                if envio.tieneVideo { SacarVideoTecnica(modelo: modelo, envioId: envio.id) }
            }
            .padding(Espacio.m)
            .anchoLectura()
        }
        .background(Color.fondo)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $enVideo) { m in VideoTecnica(modelo: modelo, envioId: envio.id, desde: m.s) }
    }

    private func seccion<C: View>(_ titulo: String, @ViewBuilder contenido: () -> C) -> some View {
        VStack(alignment: .leading, spacing: Espacio.s) {
            Text(titulo).font(.headline).accessibilityAddTraits(.isHeader)
            contenido()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func correccion(_ c: CorreccionTecnica) -> some View {
        VStack(alignment: .leading, spacing: Espacio.xs) {
            Text(c.titulo).font(.headline).fixedSize(horizontal: false, vertical: true)
            bloque(T.queSeVe, c.queSeVe)
            bloque(T.porQueImporta, c.porQue)
            bloque(T.comoHacerlo, c.comoCorregir)
            if let m = c.momentoS, envio.tieneVideo {
                Button { enVideo = MomentoVideo(s: m) } label: { Label(T.verEnElVideo, systemImage: "play.circle") }
                    .buttonStyle(BotonSecundario())
                    .accessibilityIdentifier("tecnica-ver-en-video")
            }
        }
        .tarjeta()
    }

    @ViewBuilder private func bloque(_ t: String, _ s: String) -> some View {
        if !s.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text(t).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text(s).font(.subheadline).fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
        }
    }

}

/// «Sacar mi video»: el aviso promete que se puede cuando quiera, también mientras está en revisión.
private struct SacarVideoTecnica: View {
    let modelo: ModeloTecnica
    let envioId: String
    @State private var confirma = false
    @State private var nota: String?

    var body: some View {
        VStack(spacing: Espacio.xs) {
            if let nota { NotaTecnica(texto: nota, alerta: true) }
            Button(T.sacarVideo, role: .destructive) { confirma = true }
                .buttonStyle(BotonSecundario(tono: .alerta))
                .accessibilityIdentifier("tecnica-sacar")
        }
        .confirmationDialog(T.sacarConfirma, isPresented: $confirma, titleVisibility: .visible) {
            Button(T.sacarVideo, role: .destructive) { sacar() }
            Button(T.cancelar, role: .cancel) {}
        } message: { Text(T.sacarDetalle) }
    }

    private func sacar() {
        Task {
            switch await modelo.sacarVideo(id: envioId) {
            case .ok: nota = nil
            case .ocupado: nota = T.sacarOcupado
            case .sinSenal: nota = T.sinSenal
            case .error: nota = T.errorGenerico
            }
        }
    }
}

private struct VideoTecnica: View {
    let modelo: ModeloTecnica
    let envioId: String
    let desde: Double
    @Environment(\.dismiss) private var cerrar
    @State private var player: AVPlayer?
    @State private var fallo = false

    var body: some View {
        NavigationStack {
            Group {
                if let player {
                    VistaAVPlayer(player: player, recortar: false) { _ in }.ignoresSafeArea(edges: .bottom)
                } else if fallo {
                    NotaTecnica(texto: T.errorVideo, alerta: true).padding(Espacio.l)
                } else {
                    ProgressView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityIdentifier("tecnica-video")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(T.cerrar) { cerrar() } } }
        }
        .task {
            guard let u = await modelo.urlVideo(id: envioId) else { fallo = true; return }
            let p = AVPlayer(url: u)
            player = p
            // Un `seek` antes de estar listo se puede perder y arrancaría en cero. Si no llega a estar listo, igual queda el reproductor.
            if let item = p.currentItem {
                for await s in item.publisher(for: \.status).values where s != .unknown { _ = s; break }
            }
            guard !Task.isCancelled else { return }
            await p.seek(to: CMTime(seconds: desde, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
            guard !Task.isCancelled else { return }
            p.play()
        }
        .onDisappear { player?.pause() }
    }
}
