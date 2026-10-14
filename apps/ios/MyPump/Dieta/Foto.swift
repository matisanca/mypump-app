import SwiftUI
import PhotosUI
import UIKit

/// Elegir una foto para la IA (plato o etiqueta): cámara si hay (en el simulador no) o galería. Devuelve la imagen ya
/// reducida a JPEG como la web (`_fotoABase64Reducida`: lado mayor ≤ `maxPx`, calidad 0,85, sin metadatos).
struct BotonFoto<Etiqueta: View>: View {
    let maxPx: CGFloat
    /// Calidad del JPEG: 0,85 para la IA (plato, etiqueta); las fotos de progreso van a 0,7 como en la web.
    var calidad: CGFloat = 0.85
    let alElegir: (Data) -> Void
    @ViewBuilder let etiqueta: () -> Etiqueta

    @State private var camara = false
    @State private var galeria = false
    @State private var item: PhotosPickerItem?

    var body: some View {
        Menu {
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button { camara = true } label: { Label("Sacar foto", systemImage: "camera") }
            }
            Button { galeria = true } label: { Label("Elegir de la galería", systemImage: "photo.on.rectangle") }
        } label: {
            etiqueta()
        } primaryAction: {
            if UIImagePickerController.isSourceTypeAvailable(.camera) { camara = true } else { galeria = true }
        }
        .photosPicker(isPresented: $galeria, selection: $item, matching: .images, photoLibrary: .shared())
        .fullScreenCover(isPresented: $camara) {
            Camara { imagen in
                camara = false
                if let imagen, let jpeg = FotoReducida.jpeg(imagen, maxPx: maxPx, calidad: calidad) { alElegir(jpeg) }
            }
            .ignoresSafeArea()
        }
        .onChange(of: item) { _, nuevo in
            guard let nuevo else { return }
            Task {
                if let datos = try? await nuevo.loadTransferable(type: Data.self), let imagen = UIImage(data: datos),
                   let jpeg = FotoReducida.jpeg(imagen, maxPx: maxPx, calidad: calidad) {
                    alElegir(jpeg)
                }
                item = nil
            }
        }
    }
}

enum FotoReducida {
    /// Redibuja la imagen (eso también aplica la orientación y descarta EXIF y GPS) con el lado mayor ≤ `maxPx`.
    static func jpeg(_ imagen: UIImage, maxPx: CGFloat, calidad: CGFloat = 0.85) -> Data? {
        let lado = max(imagen.size.width, imagen.size.height)
        guard lado > 0 else { return nil }
        let escala = min(1, maxPx / lado)
        let tamaño = CGSize(width: max(1, (imagen.size.width * escala).rounded()), height: max(1, (imagen.size.height * escala).rounded()))
        let formato = UIGraphicsImageRendererFormat()
        formato.scale = 1
        formato.opaque = true
        let redibujada = UIGraphicsImageRenderer(size: tamaño, format: formato).image { _ in
            imagen.draw(in: CGRect(origin: .zero, size: tamaño))
        }
        return redibujada.jpegData(compressionQuality: calidad)
    }
}

/// La cámara del sistema (PhotosPicker no saca fotos).
private struct Camara: UIViewControllerRepresentable {
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

/// Lo que se ve mientras la IA mira la foto (~30 s): no se puede tocar nada más de la hoja.
struct AnalizandoFoto: View {
    let texto: String

    var body: some View {
        VStack(spacing: 14) {
            ProgressView().controlSize(.large)
            Text(texto).font(.headline).multilineTextAlignment(.center)
            Text("Puede tardar unos 30 segundos.").font(.subheadline).foregroundStyle(.secondary)
        }
        .padding(28)
        .frame(maxWidth: 300)
        .background(.regularMaterial, in: .rect(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 24, y: 8)
        .accessibilityElement(children: .combine)
    }
}
