import SwiftUI
import UIKit
import PhotosUI
import UniformTypeIdentifiers
import MyPumpReglas
import MyPumpDatos

private typealias T = TextosEstudios

/// La hoja donde se juntan los archivos de un envío: fotos de la cámara, fotos elegidas y PDF, varias de una vez. Las fotos
/// pasan a JPEG de 2400 px y calidad 0,8, sin EXIF ni ubicación; el PDF va tal cual. Nada se guarda en Fotos: lo elegido vive
/// en una carpeta de caché hasta «Enviar», y si se cierra la hoja se borra (lo hace quien la presenta, al cerrarse).
struct HojaSubidaEstudios: View {
    let modelo: ModeloEstudios
    let pedidoId: String?
    let alCerrar: () -> Void

    @State private var camara = false
    @State private var galeria = false
    @State private var importar = false
    @State private var elegidas: [PhotosPickerItem] = []
    @State private var aviso: String?
    @State private var procesando = 0

    private var dePrueba: Bool {
        #if DEBUG
        UserDefaults.standard.string(forKey: "estudiosDePrueba") != nil
        #else
        false
        #endif
    }
    private var hayCamara: Bool { dePrueba || UIImagePickerController.isSourceTypeAvailable(.camera) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Espacio.l) {
                    VStack(alignment: .leading, spacing: Espacio.xs) {
                        Text(T.guiaSubida).font(.body)
                        Text(T.topeArchivos(modelo.topeArchivos)).font(.footnote).foregroundStyle(.secondary)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("estudios-guia")

                    opciones

                    if let aviso {
                        NotaEstudios(texto: aviso, icono: "exclamationmark.circle", tono: .ambarEstudios, anunciar: true)
                            .accessibilityIdentifier("estudios-aviso-archivo")
                    }
                    if !modelo.borrador.isEmpty || procesando > 0 { lista }
                }
                .padding(Espacio.m)
                .anchoLectura()
            }
            .background(Color.fondo)
            .safeAreaInset(edge: .bottom) {
                if !modelo.borrador.isEmpty {
                    Button(action: enviar) { Text(T.enviarArchivos(modelo.borrador.count)).multilineTextAlignment(.center).padding(.vertical, 6) }
                        .buttonStyle(BotonMarca())
                        .disabled(procesando > 0)
                        .padding(.horizontal, Espacio.m)
                        .padding(.vertical, Espacio.s)
                        .anchoLectura()
                        .background(.bar)
                        .accessibilityIdentifier("estudios-enviar")
                }
            }
            .navigationTitle(pedidoId == nil ? T.subirEstudio : T.subirResultado)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(T.cancelar, action: alCerrar).accessibilityIdentifier("estudios-cancelar") } }
        }
        .tint(Color.marcaTexto)
        // Con archivos elegidos, deslizar hacia abajo no los tira por accidente: se sale con «Cancelar».
        .interactiveDismissDisabled(!modelo.borrador.isEmpty || procesando > 0)
    }

    /// Tres botones grandes, uno por renglón, con ícono y texto (pedido de Mati, 10-nov: tiene que ser obvio, también
    /// para un alumno mayor). En tres columnas el texto quedaba chico.
    private var opciones: some View {
        VStack(spacing: Espacio.s) {
            if hayCamara {
                Button { tocar { camara = true } } label: { Label(T.sacarFotos, systemImage: "camera.fill") }
                    .buttonStyle(OpcionSubida())
                    .accessibilityIdentifier("estudios-sacar-fotos")
                    .fullScreenCover(isPresented: $camara) {
                        CamaraEstudios { imagen in
                            camara = false
                            guard let imagen else { return }
                            procesar { FotoReducida.jpeg(imagen, maxPx: CGFloat(Estudios.maxPx), calidad: CGFloat(Estudios.calidad)) }
                        }
                        .ignoresSafeArea()
                    }
            }
            Button { tocar { galeria = true } } label: { Label(T.elegirFotos, systemImage: "photo.on.rectangle") }
                .buttonStyle(OpcionSubida())
                .accessibilityIdentifier("estudios-elegir-fotos")
                .photosPicker(isPresented: $galeria, selection: $elegidas, maxSelectionCount: max(1, modelo.topeArchivos - modelo.borrador.count), matching: .images)
                .onChange(of: elegidas) { _, nuevas in
                    guard !nuevas.isEmpty else { return }
                    elegidas = []
                    for item in nuevas {
                        procesar {
                            // ImageIO directo sobre los datos: una HEIC de 48 MP no se decodifica entera (ver `ReduccionFoto`).
                            guard let datos = try? await item.loadTransferable(type: Data.self) else { return nil }
                            return ReduccionFoto.jpeg(datos, maxPx: Estudios.maxPx, calidad: Estudios.calidad)
                        }
                    }
                }
            Button { tocar(pdf: true) { importar = true } } label: { Label(T.elegirPDF, systemImage: "doc.fill") }
                .buttonStyle(OpcionSubida())
                .accessibilityIdentifier("estudios-elegir-pdf")
                .fileImporter(isPresented: $importar, allowedContentTypes: [.pdf], allowsMultipleSelection: true) { r in
                    guard case .success(let urls) = r else { return }
                    let tope = modelo.topeMB
                    for url in urls {
                        procesar(muyGrande: { Self.pesa(url) > tope * 1024 * 1024 }) { Self.leer(url) }
                    }
                }
        }
        .disabled(!modelo.puedeAgregar)
    }

    private var lista: some View {
        VStack(spacing: 0) {
            ForEach(Array(modelo.borrador.enumerated()), id: \.element.id) { i, a in
                if i > 0 { Divider().padding(.leading, Espacio.m) }
                FilaElegido(archivo: a, nombre: nombre(a)) { modelo.quitar(a.id); aviso = nil }
            }
            if procesando > 0 {
                if !modelo.borrador.isEmpty { Divider().padding(.leading, Espacio.m) }
                HStack(spacing: Espacio.s) { ProgressView(); Spacer() }.padding(Espacio.m)
            }
        }
        .superficieTarjeta()
    }

    /// «Foto 2», «PDF 1»: el número entre los de su clase, en el orden en que se eligieron.
    private func nombre(_ a: ModeloEstudios.Elegido) -> String {
        let n = (modelo.borrador.filter { $0.formato == a.formato }.firstIndex { $0.id == a.id } ?? 0) + 1
        return a.formato == .pdf ? T.pdf(n) : T.foto(n)
    }

    /// En las pruebas de interfaz no hay cámara ni selector del sistema: cada botón suma un archivo armado acá.
    private func tocar(pdf: Bool = false, _ real: () -> Void) {
        aviso = nil
        #if DEBUG
        if dePrueba {
            let n = modelo.borrador.count
            procesar { pdf ? EstudioDePrueba.pdf() : EstudioDePrueba.jpeg(n) }
            return
        }
        #endif
        real()
    }

    /// La conversión va fuera del hilo principal; el resultado se suma a lo elegido o se avisa por qué no.
    private func procesar(muyGrande: (@Sendable () -> Bool)? = nil, _ trabajo: @escaping @Sendable () async -> Data?) {
        procesando += 1
        let hoja = modelo.hoja
        Task {
            let (grande, datos) = await Task.detached(priority: .userInitiated) { () -> (Bool, Data?) in
                if muyGrande?() == true { return (true, nil) }
                return (false, await trabajo())
            }.value
            procesando -= 1
            guard hoja == modelo.hoja else { return }   // la hoja se cerró mientras tanto: ese archivo no entra en otra
            if grande { aviso = T.archivoMuyGrande(modelo.topeMB); return }
            guard let datos else { aviso = T.archivoRechazado; return }
            switch modelo.elegir(datos) {
            case .ok: break
            case .tope: aviso = T.topeArchivos(modelo.topeArchivos)
            case .muyGrande: aviso = T.archivoMuyGrande(modelo.topeMB)
            case .ilegible: aviso = T.archivoRechazado
            case .noSeGuardo: aviso = T.noSePudoGuardar
            }
        }
    }

    private func enviar() {
        guard modelo.enviar(pedidoId: pedidoId) else { aviso = T.noSePudoGuardar; return }
        modelo.drenarEnFondo()
        alCerrar()
    }

    /// Un PDF de Archivos (o de otro proveedor): se lee con el permiso que da el selector, sin copiarlo a ningún otro lado.
    private nonisolated static func leer(_ url: URL) -> Data? {
        let conPermiso = url.startAccessingSecurityScopedResource()
        defer { if conPermiso { url.stopAccessingSecurityScopedResource() } }
        var datos: Data?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [.withoutChanges], error: nil) { u in datos = try? Data(contentsOf: u, options: .mappedIfSafe) }
        // Copia propia: el archivo mapeado deja de valer al soltar el permiso.
        return datos.map { Data($0) }
    }

    private nonisolated static func pesa(_ url: URL) -> Int {
        let conPermiso = url.startAccessingSecurityScopedResource()
        defer { if conPermiso { url.stopAccessingSecurityScopedResource() } }
        return (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    }
}

/// Una opción de la hoja de subida: de ancho completo, alta, con el ícono en un círculo y el texto grande al lado.
private struct OpcionSubida: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Cuerpo(configuration: configuration)
    }

    private struct Cuerpo: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isEnabled) private var habilitado
        @ScaledMetric(relativeTo: .headline) private var lado: CGFloat = 44

        var body: some View {
            configuration.label
                .labelStyle(Renglon(lado: lado, tono: habilitado ? .marcaTexto : .secondary))
                .padding(.horizontal, Espacio.m)
                .padding(.vertical, Espacio.s)
                .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                .superficieTarjeta(radio: Radio.control + 4)
                .contentShape(.rect)
                .opacity(habilitado ? 1 : 0.45)
                .scaleEffect(configuration.isPressed ? 0.98 : 1)
                .opacity(configuration.isPressed ? 0.85 : 1)
                .animation(.snappy(duration: 0.18), value: configuration.isPressed)
        }
    }

    private struct Renglon: LabelStyle {
        let lado: CGFloat
        let tono: Color

        func makeBody(configuration: Configuration) -> some View {
            HStack(spacing: Espacio.s) {
                configuration.icon
                    .font(.system(size: lado * 0.45, weight: .semibold))
                    .foregroundStyle(tono)
                    .frame(width: lado, height: lado)
                    .background(Color.marcaSuave, in: .circle)
                configuration.title
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
        }
    }
}

private struct FilaElegido: View {
    let archivo: ModeloEstudios.Elegido
    let nombre: String
    let quitar: () -> Void
    @ScaledMetric(relativeTo: .body) private var lado: CGFloat = 52
    @Environment(\.dynamicTypeSize) private var letra

    var body: some View {
        let fila = letra.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: Espacio.s)) : AnyLayout(HStackLayout(spacing: Espacio.s))
        fila {
            HStack(spacing: Espacio.s) {
                Group {
                    if archivo.formato == .pdf {
                        Image(systemName: "doc.text.fill").font(.title3).foregroundStyle(Color.marcaTexto)
                            .frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.marcaSuave)
                    } else {
                        MiniaturaEstudio(archivo: archivo.url)
                    }
                }
                .frame(width: lado, height: lado)
                .clipShape(.rect(cornerRadius: Radio.miniatura, style: .continuous))
                .accessibilityHidden(true)
                Text(nombre).font(.headline)
                Spacer(minLength: 0)
            }
            Button(T.quitar, role: .destructive, action: quitar)
                .buttonStyle(BotonSecundario(compacto: true, tono: .primary))
                .accessibilityLabel("\(T.quitar), \(nombre)")
                .accessibilityIdentifier("estudios-quitar")
        }
        .padding(Espacio.m)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// La foto del caché, reducida fuera del hilo principal.
private struct MiniaturaEstudio: View {
    let archivo: URL
    @State private var imagen: UIImage?

    var body: some View {
        Color.campo
            .overlay { if let imagen { Image(uiImage: imagen).resizable().scaledToFill() } }
            .clipped()
            .task(id: archivo) {
                let f = archivo
                imagen = await Task.detached(priority: .utility) { () -> UIImage? in
                    guard let s = CGImageSourceCreateWithURL(f as CFURL, nil),
                          let c = CGImageSourceCreateThumbnailAtIndex(s, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 240, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) else { return nil }
                    return UIImage(cgImage: c)
                }.value
            }
    }
}

/// La cámara del sistema. La foto vuelve en memoria: no pasa por la fototeca.
private struct CamaraEstudios: UIViewControllerRepresentable {
    let alTerminar: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let c = UIImagePickerController()
        c.sourceType = .camera
        c.delegate = context.coordinator
        return c
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinador { Coordinador(alTerminar: alTerminar) }

    final class Coordinador: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let alTerminar: (UIImage?) -> Void
        init(alTerminar: @escaping (UIImage?) -> Void) { self.alTerminar = alTerminar }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            alTerminar(info[.originalImage] as? UIImage)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { alTerminar(nil) }
    }
}

#if DEBUG
/// Archivos inventados para las pruebas de interfaz: una hoja con renglones grises, sin texto ni datos de nadie.
enum EstudioDePrueba {
    static func jpeg(_ n: Int) -> Data? {
        let formato = UIGraphicsImageRendererFormat()
        formato.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 600, height: 800), format: formato).image { c in
            UIColor.white.setFill(); c.fill(CGRect(x: 0, y: 0, width: 600, height: 800))
            UIColor(white: 0.78 - CGFloat(n % 4) * 0.05, alpha: 1).setFill()
            for i in 0..<14 { c.fill(CGRect(x: 60, y: 90 + i * 46, width: i % 3 == 0 ? 300 : 480, height: 14)) }
        }.jpegData(compressionQuality: 0.8)
    }

    /// El PDF de ejemplo del doble, con un comentario distinto al final para que no sean los mismos bytes.
    static func pdf() -> Data? { DobleEstudios.pdfDeEjemplo + Data("%\(UUID().uuidString)\n".utf8) }
}
#endif
