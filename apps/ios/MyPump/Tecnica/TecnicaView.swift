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
private enum DestinoTecnica: Hashable {
    case devolucion(String), elegir, enviar(slug: String, nombre: String)
}

/// «Mi técnica» en Mis datos: lo mandado, su estado y la devolución. Pila propia con `path`: `navigationDestination(item:)` dejaba
/// la app en un bucle al 100 % de CPU en iOS 17; por lo mismo acá no hay `List`.
struct MiTecnicaRaiz: View {
    let modelo: ModeloTecnica
    let alCerrar: () -> Void
    @State private var camino: [DestinoTecnica] = []

    var body: some View {
        NavigationStack(path: $camino) {
            ListaTecnica(modelo: modelo, abrir: { camino.append($0) })
                .background(Color.fondo)
                .navigationTitle(T.entradaMisDatos)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(T.cerrar, action: alCerrar) } }
                .navigationDestination(for: DestinoTecnica.self) { d in
                    switch d {
                    case .devolucion(let id):
                        if let e = modelo.envios.first(where: { $0.id == id }), let dev = e.devolucion { DevolucionTecnicaView(modelo: modelo, envio: e, devolucion: dev) }
                    case .elegir: ElegirEjercicioTecnica(modelo: modelo, abrir: { camino.append($0) })
                    case .enviar(let slug, let nombre): EnviarTecnica(modelo: modelo, slug: slug, nombre: nombre, alTerminar: { camino = [] })
                    }
                }
        }
        .task { await modelo.refrescar(); modelo.drenarEnFondo() }
        .onChange(of: modelo.habilitado) { _, si in if !si { alCerrar() } }
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

private struct ListaTecnica: View {
    let modelo: ModeloTecnica
    let abrir: (DestinoTecnica) -> Void

    var body: some View {
        ScrollView {
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
                    }
                }
                if modelo.envios.isEmpty && modelo.pendiente == nil {
                    NotaTecnica(texto: T.sinEnvios).accessibilityIdentifier("tecnica-vacio")
                }
            }
            .padding(Espacio.m)
            .anchoLectura()
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

    var body: some View {
        Group {
            if mandado && modelo.pendiente == nil && modelo.aviso == nil {
                recibido
            } else if modelo.pendiente != nil {
                enviando
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
        .task { CompresorVideo.barrer(); await modelo.refrescar(); modelo.drenarEnFondo() }
        .onDisappear { if let v = video { try? FileManager.default.removeItem(at: v.archivo) } }
    }

    private var aviso: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Espacio.m) {
                Label { Text(T.avisoTerceros).font(.subheadline).fixedSize(horizontal: false, vertical: true) } icon: {
                    Image(systemName: "lock.fill").foregroundStyle(Color.marcaTexto)
                }
                .labelStyle(EtiquetaCompacta())
                .padding(Espacio.s)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.marcaSuave, in: .rect(cornerRadius: Radio.control, style: .continuous))
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("tecnica-aviso")
                Button(T.avisoBoton) { modelo.aceptarAviso() }.buttonStyle(BotonMarca()).accessibilityIdentifier("tecnica-aviso-ok")
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
                Button(T.cancelarEnvio) { Task { await modelo.cancelarPendiente(); mandado = false } }
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
    @State private var confirmaSacar = false
    @State private var nota: String?

    private struct MomentoVideo: Identifiable { let s: Double; var id: Double { s } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Espacio.l) {
                VStack(alignment: .leading, spacing: Espacio.xxs) {
                    Text(T.tituloDevolucion(devolucion.ejercicio ?? envio.nombre)).font(.title2.bold()).accessibilityAddTraits(.isHeader).fixedSize(horizontal: false, vertical: true)
                    Text(Gimnasio.fechaCorta(envio.publicadoEn).map(T.revisadoEl) ?? devolucion.credito).font(.subheadline).foregroundStyle(.secondary).accessibilityIdentifier("tecnica-credito")
                }
                if devolucion.correcciones.isEmpty {
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
                if let como = devolucion.otroVideo {
                    seccion(T.mandameOtro) { Text(como).fixedSize(horizontal: false, vertical: true) }
                        .accessibilityIdentifier("tecnica-otro-video")
                }
                if let nota { NotaTecnica(texto: nota, alerta: true) }
                if envio.tieneVideo {
                    Button(T.sacarVideo, role: .destructive) { confirmaSacar = true }
                        .buttonStyle(BotonSecundario(tono: .alerta))
                        .accessibilityIdentifier("tecnica-sacar")
                }
            }
            .padding(Espacio.m)
            .anchoLectura()
        }
        .background(Color.fondo)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(T.sacarConfirma, isPresented: $confirmaSacar, titleVisibility: .visible) {
            Button(T.sacarVideo, role: .destructive) { sacar() }
            Button(T.cancelar, role: .cancel) {}
        } message: { Text(T.sacarDetalle) }
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

    private func sacar() {
        Task {
            switch await modelo.sacarVideo(id: envio.id) {
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
            await p.seek(to: CMTime(seconds: desde, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
            player = p
            p.play()
        }
        .onDisappear { player?.pause() }
    }
}
